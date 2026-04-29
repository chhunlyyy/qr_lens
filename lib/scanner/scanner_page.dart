import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'qr_overlay_painter.dart';
import 'scanner_theme.dart';

// Capture flow: idle → capturing → showingQrSnippet → showingResult → idle
enum _CaptureState { idle, capturing, showingQrSnippet, showingResult }

/// Provides programmatic control over [QrLensScannerPage].
///
/// Pass an instance to [QrLensScannerPage.controller] and call [scanFromFile]
/// to trigger a scan from any [XFile] — e.g. one returned by a custom image
/// picker, [file_picker], or [photo_manager].
class QrLensScannerController {
  _QrLensScannerPageState? _state;

  void _attach(_QrLensScannerPageState state) => _state = state;
  void _detach() => _state = null;

  /// Scan a QR code from [file]. No-op if a scan is already in progress.
  Future<void> scanFromFile(XFile file) async {
    await _state?._processPickedFile(file);
  }

  /// Stops the camera image stream. The scanner will stop processing frames
  /// and remain on the current preview frame.
  Future<void> stopStream() async {
    _state?._stopCameraStream();
  }

  /// Resumes the camera image stream after it has been stopped manually or
  /// by disabling [QrLensScannerPage.autoResume].
  Future<void> resumeStream() async {
    await _state?._resetCapture();
  }
}

class QrLensScannerPage extends StatefulWidget {
  // ── Callbacks ──────────────────────────────────────────────────────

  /// Called the moment a new QR value is detected (before animation completes).
  final void Function(String value)? onScanned;

  /// Called when the capture animation finishes and the result card is shown.
  final void Function(String value)? onScanComplete;

  /// Called if the camera fails to initialize or encounters a runtime error.
  final void Function(Object error)? onError;

  /// Called once the camera has initialized and the image stream is running.
  final VoidCallback? onCameraReady;

  // ── App bar ────────────────────────────────────────────────────────

  /// App bar title widget. Defaults to a "QR Scanner" text label.
  final Widget title;

  /// Replaces the entire app bar. Receives [isBackCamera] for conditional
  /// UI such as the torch toggle.
  final PreferredSizeWidget Function(BuildContext context, {required bool isBackCamera})? appBarBuilder;

  // ── Toggles ────────────────────────────────────────────────────────

  /// Show/hide the torch toggle button (only visible on back camera).
  final bool showTorchButton;

  /// Show/hide the camera flip button.
  final bool showFlipButton;

  /// Show/hide the history button (automatically hidden when history is empty).
  final bool showHistoryButton;

  /// Show/hide the upload button to scan QR codes from gallery images.
  final bool showUploadButton;

  /// Replaces the built-in gallery picker invoked by the upload button.
  /// Return an [XFile] to proceed with scanning, or null to cancel.
  /// When null the default [ImagePicker] gallery picker is used.
  final Future<XFile?> Function()? imagePickerBuilder;

  /// Controller for programmatic operations such as scanning from a file.
  final QrLensScannerController? controller;

  /// Whether to play haptic feedback when a QR code is captured.
  final bool hapticFeedback;

  // ── Camera ─────────────────────────────────────────────────────────

  /// Camera resolution preset. Defaults to [ResolutionPreset.veryHigh].
  final ResolutionPreset cameraResolution;

  /// Preferred initial lens direction. Defaults to back-facing camera.
  final CameraLensDirection preferredLensDirection;

  // ── Scanning ───────────────────────────────────────────────────────

  /// Barcode formats that the scanner recognises. Defaults to QR codes only.
  final List<BarcodeFormat> barcodeFormats;

  // ── Viewfinder ─────────────────────────────────────────────────────

  /// Fraction of the shorter screen edge used for the scan viewfinder.
  final double viewfinderSizeRatio;

  /// Replaces the entire viewfinder overlay. When provided the default
  /// [ScannerBox] / [QrOverlayPainter] stack is omitted.
  final Widget Function(BuildContext context, ViewfinderState state)? viewFinderBuilder;

  // ── Hint ───────────────────────────────────────────────────────────

  /// Hint text shown below the viewfinder when idle. Set null to hide.
  final String? hintText;

  /// Style for the hint text.
  final TextStyle? hintTextStyle;

  // ── Result ─────────────────────────────────────────────────────────

  /// Replaces the default result card. Receives the scanned value.
  final Widget Function(BuildContext context, String value)? resultBuilder;

  // ── History ────────────────────────────────────────────────────────

  /// Replaces the default history bottom-sheet. Receives an immutable copy
  /// of the scan history list.
  final Widget Function(BuildContext context, List<String> history)? historyBuilder;

  /// Maximum number of entries kept in the scan history.
  final int scanHistoryMaxSize;

  // ── Timing ─────────────────────────────────────────────────────────

  /// Duration of the scan-line sweep animation.
  final Duration scanLineAnimationDuration;

  /// Duration of the bounding-box expand/contract animation when a QR
  /// is captured.
  final Duration boxAnimationDuration;

  /// Duration of the QR-code fly-to-center animation.
  final Duration qrMoveAnimationDuration;

  /// Delay between the box-animation completing and the QR-snippet
  /// animation starting.
  final Duration qrSnippetDelay;

  /// Delay after the QR-move animation completes before [onScanComplete]
  /// is invoked.
  final Duration onScanCompleteDelay;

  /// How long the result is shown before the scanner resets.
  final Duration resultDuration;

  /// When true (default), the camera stream automatically resumes after
  /// [resultDuration] expires and the scanner begins looking for codes again.
  /// When false, the scanner stays on the frozen frame after a scan completes
  /// and you must call [QrLensScannerController.resumeStream] to restart.
  final bool autoResume;

  // ── Colours ────────────────────────────────────────────────────────

  /// Primary accent colour for corners, scan line, and result card border.
  final Color accentColor;

  /// Colour used for the success glow when a QR is captured.
  final Color successColor;

  /// Background colour of the scaffold. Defaults to [Colors.black].
  final Color scaffoldBackgroundColor;

  /// Colour of the scanning line. When null falls back to [accentColor].
  final Color? scanLineColor;

  const QrLensScannerPage({
    super.key,
    // callbacks
    this.onScanned,
    this.onScanComplete,
    this.onError,
    this.onCameraReady,
    // app bar
    this.title = const Text(
      'QR Scanner',
      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 0.4),
    ),
    this.appBarBuilder,
    // toggles
    this.showTorchButton = true,
    this.showFlipButton = true,
    this.showHistoryButton = true,
    this.showUploadButton = true,
    this.imagePickerBuilder,
    this.controller,
    this.hapticFeedback = true,
    // camera
    this.cameraResolution = ResolutionPreset.veryHigh,
    this.preferredLensDirection = CameraLensDirection.back,
    // scanning
    this.barcodeFormats = const [BarcodeFormat.qrCode],
    // viewfinder
    this.viewfinderSizeRatio = 0.68,
    this.viewFinderBuilder,
    // hint
    this.hintText = 'Point camera at a QR code',
    this.hintTextStyle,
    // result
    this.resultBuilder,
    // history
    this.historyBuilder,
    this.scanHistoryMaxSize = 20,
    // timing
    this.scanLineAnimationDuration = const Duration(milliseconds: 2400),
    this.boxAnimationDuration = const Duration(milliseconds: 350),
    this.qrMoveAnimationDuration = const Duration(milliseconds: 900),
    this.qrSnippetDelay = const Duration(milliseconds: 500),
    this.onScanCompleteDelay = Duration.zero,
    this.resultDuration = const Duration(milliseconds: 2800),
    this.autoResume = true,
    // colours
    this.accentColor = kAccent,
    this.successColor = kSuccess,
    this.scaffoldBackgroundColor = Colors.black,
    this.scanLineColor,
  });

  @override
  State<QrLensScannerPage> createState() => _QrLensScannerPageState();
}

/// State snapshot passed to [QrLensScannerPage.viewFinderBuilder].
class ViewfinderState {
  /// The computed viewfinder bounding rectangle.
  final Rect boundingRect;

  /// Normalised scan-line progress (0 → 1).
  final double scanProgress;

  /// Current overlay alpha.
  final double overlayAlpha;

  /// Whether a QR is currently being captured.
  final bool isCapturing;

  /// Whether the scanner is in the "showing result" phase.
  final bool isShowingResult;

  /// The detected QR corner rect, or null.
  final Rect? detectedRect;

  /// The scanned value, or null.
  final String? scannedValue;

  const ViewfinderState({
    required this.boundingRect,
    required this.scanProgress,
    required this.overlayAlpha,
    required this.isCapturing,
    required this.isShowingResult,
    this.detectedRect,
    this.scannedValue,
  });
}

class _QrLensScannerPageState extends State<QrLensScannerPage> with TickerProviderStateMixin {
  List<CameraDescription> _cameras = [];
  CameraController? _cameraController;
  late final AnimationController _anim;
  late final BarcodeScanner _barcodeScanner;

  int _sensorOrientation = 90;
  bool _isCameraReady = false;
  bool _isTorchOn = false;

  Rect? _targetRect;
  Rect? _currentRect;
  double _overlayAlpha = 0.0;

  bool _isProcessing = false;
  String? _scannedValue;
  final List<String> _scanHistory = [];

  DateTime _lastDetectTime = DateTime(2000);
  static const int _overlayFadeTimeout = 500;
  static const double _moveThreshold = 3.0;
  static const double _sizeThreshold = 6.0;

  late final AnimationController _boxAnim;
  _CaptureState _captureState = _CaptureState.idle;
  Rect? _captureStartRect;
  Rect? _captureTargetRect;

  late final AnimationController _qrMoveAnim;

  final GlobalKey _previewKey = GlobalKey();
  Uint8List? _frozenFrameBytes;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    _barcodeScanner = BarcodeScanner(formats: widget.barcodeFormats);
    _anim = AnimationController(vsync: this, duration: widget.scanLineAnimationDuration)..repeat();
    _anim.addListener(_onAnimTick);

    _boxAnim = AnimationController(vsync: this, duration: widget.boxAnimationDuration);
    _boxAnim.addListener(_onBoxTick);
    _boxAnim.addStatusListener(_onBoxStatus);

    _qrMoveAnim = AnimationController(vsync: this, duration: widget.qrMoveAnimationDuration);
    _qrMoveAnim.addListener(_onQrMoveTick);
    _qrMoveAnim.addStatusListener(_onQrMoveStatus);

    _initCamera();
  }

  @override
  void didUpdateWidget(QrLensScannerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach();
      widget.controller?._attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller?._detach();
    _anim.removeListener(_onAnimTick);
    _anim.dispose();
    _boxAnim.removeListener(_onBoxTick);
    _boxAnim.removeStatusListener(_onBoxStatus);
    _boxAnim.dispose();
    _qrMoveAnim.removeListener(_onQrMoveTick);
    _qrMoveAnim.removeStatusListener(_onQrMoveStatus);
    _qrMoveAnim.dispose();
    _stopCameraStream();
    _cameraController?.dispose();
    _barcodeScanner.close();
    super.dispose();
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) return;
    _cameras = await availableCameras();
    if (_cameras.isEmpty) return;
    final camera = _cameras.firstWhere(
      (c) => c.lensDirection == widget.preferredLensDirection,
      orElse: () => _cameras.first,
    );
    await _startCamera(camera);
  }

  Future<void> _startCamera(CameraDescription camera) async {
    _stopCameraStream();
    await _cameraController?.dispose();

    _sensorOrientation = camera.sensorOrientation;

    _cameraController = CameraController(
      camera,
      widget.cameraResolution,
      enableAudio: false,
      imageFormatGroup: Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.nv21,
    );

    try {
      await _cameraController!.initialize();
      if (!mounted) return;
      await _cameraController!.startImageStream(_processImage);
      setState(() {
        _isCameraReady = true;
        _isTorchOn = false;
      });
      widget.onCameraReady?.call();
    } catch (e) {
      widget.onError?.call(e);
      debugPrint('Camera error: $e');
    }
  }

  void _stopCameraStream() {
    if (_cameraController != null && _cameraController!.value.isStreamingImages) {
      _cameraController!.stopImageStream();
    }
  }

  Future<void> _switchCamera() async {
    if (_cameraController == null || !_isCameraReady) return;
    if (_cameras.length < 2) return;
    final currentLens = _cameraController!.description.lensDirection;
    final newLens = currentLens == CameraLensDirection.back ? CameraLensDirection.front : CameraLensDirection.back;
    final target = _cameras.firstWhere((c) => c.lensDirection == newLens, orElse: () => _cameras.first);
    if (target.lensDirection == currentLens) return;
    await _startCamera(target);
  }

  Future<void> _toggleTorch() async {
    if (_cameraController == null || !_isCameraReady) return;
    await _cameraController!.setFlashMode(_isTorchOn ? FlashMode.off : FlashMode.torch);
    setState(() => _isTorchOn = !_isTorchOn);
  }

  void _onAnimTick() {
    if (!mounted || _captureState == _CaptureState.capturing) return;

    final dtMs = DateTime.now().difference(_lastDetectTime).inMilliseconds;

    if (dtMs > _overlayFadeTimeout) {
      if (_overlayAlpha > 0 || _currentRect != null) {
        setState(() {
          _overlayAlpha = math.max(0.0, _overlayAlpha - 0.08);
          if (_overlayAlpha <= 0.01) {
            _overlayAlpha = 0.0;
            _currentRect = null;
            _targetRect = null;
          }
        });
      }
      return;
    }

    if (_targetRect == null) return;

    final lerped = _currentRect == null ? _targetRect! : Rect.lerp(_currentRect, _targetRect, 0.25)!;
    final targetAlpha = math.min(1.0, _overlayAlpha + 0.15);

    if (_currentRect == null ||
        _rectChanged(_currentRect!, lerped, 0.3) ||
        (targetAlpha - _overlayAlpha).abs() > 0.005) {
      setState(() {
        _currentRect = lerped;
        _overlayAlpha = targetAlpha;
      });
    }
  }

  bool _rectChanged(Rect a, Rect b, double t) =>
      (a.left - b.left).abs() > t ||
      (a.top - b.top).abs() > t ||
      (a.width - b.width).abs() > t ||
      (a.height - b.height).abs() > t;

  void _processImage(CameraImage image) {
    if (_isProcessing || _captureState != _CaptureState.idle || !mounted) return;
    _isProcessing = true;

    final input = _toInputImage(image);
    if (input == null) {
      _isProcessing = false;
      return;
    }

    _barcodeScanner
        .processImage(input)
        .then((barcodes) {
          if (!mounted) return;
          _isProcessing = false;
          if (barcodes.isEmpty) return;

          _lastDetectTime = DateTime.now();
          final bc = barcodes.first;

          if (bc.cornerPoints.isEmpty) return;

          final corners = bc.cornerPoints.map((p) => Offset(p.x.toDouble(), p.y.toDouble())).toList();
          final imageSize = Size(image.width.toDouble(), image.height.toDouble());
          final mapped = _mapToScreen(corners, imageSize);
          if (mapped == null) return;

          if (bc.rawValue != null && bc.rawValue != _scannedValue) {
            _startCapture(mapped, bc.rawValue!);
          } else {
            _updateTarget(mapped);
          }
        })
        .catchError((_) {
          _isProcessing = false;
        });
  }

  void _updateTarget(Rect next) {
    if (_targetRect == null) {
      _targetRect = next;
      return;
    }
    final moved = (_targetRect!.center - next.center).distance;
    final changed = (_targetRect!.width - next.width).abs() + (_targetRect!.height - next.height).abs();
    if (moved > _moveThreshold || changed > _sizeThreshold) {
      _targetRect = next;
    }
  }

  InputImage? _toInputImage(CameraImage image) {
    final rotation = _intToRotation(_sensorOrientation);
    if (rotation == null) return null;

    final format = Platform.isAndroid ? InputImageFormat.nv21 : InputImageFormat.bgra8888;
    final Uint8List bytes;
    int bytesPerRow;

    if (Platform.isAndroid) {
      final buffer = WriteBuffer();
      for (final plane in image.planes) {
        buffer.putUint8List(plane.bytes);
      }
      bytes = buffer.done().buffer.asUint8List();
      bytesPerRow = image.planes.first.bytesPerRow;
    } else {
      bytes = image.planes.first.bytes;
      bytesPerRow = image.planes.first.bytesPerRow;
    }

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: bytesPerRow,
      ),
    );
  }

  InputImageRotation? _intToRotation(int degrees) {
    switch (degrees) {
      case 0:
        return InputImageRotation.rotation0deg;
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return null;
    }
  }

  // ML Kit returns corners already in upright display orientation because it
  // applies the rotation we pass via InputImageMetadata — no affine transform needed.
  Rect? _mapToScreen(List<Offset> corners, Size imageSize) {
    if (corners.isEmpty) return null;
    final screenSize = MediaQuery.of(context).size;
    if (screenSize.isEmpty) return null;
    final previewSize = _cameraController?.value.previewSize;
    if (previewSize == null) return null;

    final orient = _sensorOrientation;
    final upright = (orient == 90 || orient == 270) ? Size(imageSize.height, imageSize.width) : imageSize;
    final displaySrcSize = (orient == 90 || orient == 270) ? Size(previewSize.height, previewSize.width) : previewSize;
    if (displaySrcSize.isEmpty) return null;

    final sx = displaySrcSize.width / upright.width;
    final sy = displaySrcSize.height / upright.height;
    final scale = math.max(screenSize.width / displaySrcSize.width, screenSize.height / displaySrcSize.height);
    final ox = (screenSize.width - displaySrcSize.width * scale) / 2;
    final oy = (screenSize.height - displaySrcSize.height * scale) / 2;

    final mapped = corners.map((c) => Offset(c.dx * sx * scale + ox, c.dy * sy * scale + oy)).toList();
    final xs = mapped.map((o) => o.dx);
    final ys = mapped.map((o) => o.dy);
    return Rect.fromLTRB(xs.reduce(math.min), ys.reduce(math.min), xs.reduce(math.max), ys.reduce(math.max));
  }

  Future<void> _freezeFrame() async {
    if (_frozenFrameBytes != null) return; // already provided (e.g. uploaded image)
    try {
      final boundary = _previewKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data != null) _frozenFrameBytes = data.buffer.asUint8List();
    } catch (_) {}
  }

  Future<void> _resumeCameraStream() async {
    final ctrl = _cameraController;
    if (ctrl != null && ctrl.value.isInitialized && !ctrl.value.isStreamingImages) {
      setState(() => _frozenFrameBytes = null);
      await ctrl.startImageStream(_processImage);
    }
  }

  Future<void> _pickAndScanImage() async {
    if (_captureState != _CaptureState.idle) return;
    _stopCameraStream();

    final XFile? file = widget.imagePickerBuilder != null
        ? await widget.imagePickerBuilder!()
        : await ImagePicker().pickImage(source: ImageSource.gallery);

    if (!mounted) return;

    if (file == null) {
      await _resumeCameraStream();
      return;
    }

    await _processPickedFile(file);
  }

  /// Scans [file] for a QR code and shows the result directly without capture animation.
  /// Can be called directly from [QrLensScannerController.scanFromFile].
  Future<void> _processPickedFile(XFile file) async {
    if (_captureState != _CaptureState.idle) return;
    _stopCameraStream();

    final bytes = await file.readAsBytes();
    final inputImage = InputImage.fromFilePath(file.path);
    final barcodes = await _barcodeScanner.processImage(inputImage);

    if (!mounted) return;

    if (barcodes.isEmpty || barcodes.first.rawValue == null) {
      await _resumeCameraStream();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No QR code found in image'), duration: Duration(seconds: 2)));
      return;
    }

    final value = barcodes.first.rawValue!;
    _scannedValue = value;
    _frozenFrameBytes = bytes;
    _anim.stop();

    if (!mounted) return;
    widget.onScanned?.call(value);

    _scanHistory.remove(value);
    _scanHistory.insert(0, value);
    if (_scanHistory.length > widget.scanHistoryMaxSize) _scanHistory.removeLast();

    setState(() => _captureState = _CaptureState.showingResult);

    widget.onScanComplete?.call(value);

    if (widget.autoResume) {
      Future.delayed(widget.resultDuration, () {
        if (!mounted) return;
        _resetCapture();
      });
    }
  }

  Future<void> _startCapture(Rect qrRect, String value) async {
    if (_captureState != _CaptureState.idle) return;
    // Set immediately (before any await) to block re-entry from new frames.
    _captureState = _CaptureState.capturing;

    _scannedValue = value;
    _targetRect = qrRect;
    _captureStartRect = _currentRect ?? _viewfinderRect;
    _captureTargetRect = qrRect.inflate(8);

    await _freezeFrame(); // snapshot while stream is still live
    _anim.stop();
    _stopCameraStream();
    if (!mounted) return;

    widget.onScanned?.call(value);

    _scanHistory.remove(value);
    _scanHistory.insert(0, value);
    if (_scanHistory.length > widget.scanHistoryMaxSize) _scanHistory.removeLast();

    setState(() {
      _captureState = _CaptureState.capturing;
      _overlayAlpha = 1.0;
    });

    _boxAnim.forward(from: 0);
  }

  void _onBoxTick() {
    if (!mounted || _captureStartRect == null || _captureTargetRect == null) return;
    setState(() {
      _currentRect = Rect.lerp(_captureStartRect!, _captureTargetRect!, _boxAnim.value);
    });
  }

  void _onBoxStatus(AnimationStatus status) {
    if (!mounted || status != AnimationStatus.completed) return;
    if (widget.hapticFeedback) HapticFeedback.mediumImpact();
    setState(() {
      _captureState = _CaptureState.showingQrSnippet;
      _currentRect = _captureTargetRect;
    });
    Future.delayed(widget.qrSnippetDelay, () {
      if (!mounted) return;
      _qrMoveAnim.forward(from: 0);
    });
  }

  void _onQrMoveTick() {
    _currentRect = _computeQrSnippetRect();
  }

  void _onQrMoveStatus(AnimationStatus status) {
    if (!mounted || status != AnimationStatus.completed) return;
    setState(() => _captureState = _CaptureState.showingResult);
    Future.delayed(widget.onScanCompleteDelay, () {
      if (!mounted || _scannedValue == null) return;
      widget.onScanComplete?.call(_scannedValue!);
    });
    if (widget.autoResume) {
      Future.delayed(widget.resultDuration, () {
        if (!mounted) return;
        _resetCapture();
      });
    }
  }

  Rect? _computeQrSnippetRect() {
    if (_captureTargetRect == null) return null;
    final screenSize = MediaQuery.of(context).size;
    final t = Curves.easeOutCubic.transform(_qrMoveAnim.value);
    final startRect = _captureTargetRect!;
    final endCenter = Offset(screenSize.width / 2, screenSize.height / 2);
    final currentCenter = Offset.lerp(startRect.center, endCenter, t)!;
    final endSize = math.min(screenSize.width, screenSize.height) * widget.viewfinderSizeRatio;
    final currentSize = ui.lerpDouble(startRect.width, endSize, t)!;
    return Rect.fromCenter(center: currentCenter, width: currentSize, height: currentSize);
  }

  Future<void> _resetCapture() async {
    if (!mounted) return;
    setState(() {
      _scannedValue = null;
      _targetRect = null;
      _currentRect = null;
      _overlayAlpha = 0.0;
      _captureState = _CaptureState.idle;
      _captureStartRect = null;
      _captureTargetRect = null;
      _frozenFrameBytes = null;
    });
    _qrMoveAnim.reset();
    _anim.repeat();

    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized || !mounted) return;

    if (!controller.value.isStreamingImages) {
      await controller.startImageStream(_processImage);
    }
  }

  Rect get _viewfinderRect {
    final screen = MediaQuery.of(context).size;
    final short = math.min(screen.width, screen.height);
    final boxSize = short * widget.viewfinderSizeRatio;
    return Rect.fromCenter(center: Offset(screen.width / 2, screen.height * 0.44), width: boxSize, height: boxSize);
  }

  void _showHistory() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => widget.historyBuilder != null
          ? widget.historyBuilder!(context, List.unmodifiable(_scanHistory))
          : _HistorySheet(history: List.unmodifiable(_scanHistory), accentColor: widget.accentColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraReady || _cameraController == null) {
      return Scaffold(backgroundColor: widget.scaffoldBackgroundColor);
    }

    final viewfinderRect = _viewfinderRect;
    final screen = MediaQuery.of(context).size;
    final isIdle = _captureState == _CaptureState.idle;
    final isShowingQrSnippet = _captureState == _CaptureState.showingQrSnippet;
    final isShowingQr = isShowingQrSnippet || _captureState == _CaptureState.showingResult;
    final displayRect = _currentRect ?? viewfinderRect;
    final displayAlpha = _currentRect != null ? _overlayAlpha : 1.0;

    final previewSize = _cameraController!.value.previewSize!;
    final isRotated = _sensorOrientation == 90 || _sensorOrientation == 270;
    final displaySrcSize = isRotated ? Size(previewSize.height, previewSize.width) : previewSize;
    final isBackCamera = _cameraController!.description.lensDirection == CameraLensDirection.back;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: widget.scaffoldBackgroundColor,
      appBar: widget.appBarBuilder?.call(context, isBackCamera: isBackCamera) ?? _appBar(isBackCamera: isBackCamera),
      body: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            key: _previewKey,
            child: ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: displaySrcSize.width,
                  height: displaySrcSize.height,
                  child: CameraPreview(_cameraController!),
                ),
              ),
            ),
          ),

          if (_frozenFrameBytes != null)
            Positioned.fill(child: Image.memory(_frozenFrameBytes!, fit: BoxFit.cover, gaplessPlayback: true)),

          Positioned.fill(
            child: AnimatedBuilder(
              animation: isShowingQr ? _qrMoveAnim : _anim,
              builder: (_, __) {
                final qrProgress = isShowingQrSnippet
                    ? Curves.easeOutCubic.transform(_qrMoveAnim.value)
                    : (isShowingQr ? 1.0 : 0.0);
                final targetSize = math.min(screen.width, screen.height) * widget.viewfinderSizeRatio;
                final qrTargetRect = Rect.fromCenter(
                  center: Offset(screen.width / 2, screen.height / 2),
                  width: targetSize,
                  height: targetSize,
                );

                if (widget.viewFinderBuilder != null) {
                  final customView = widget.viewFinderBuilder!(
                    context,
                    ViewfinderState(
                      boundingRect: isShowingQr ? (_currentRect ?? viewfinderRect) : displayRect,
                      scanProgress: _anim.value,
                      overlayAlpha: isShowingQr ? 0.92 : displayAlpha,
                      isCapturing: !isShowingQr && _captureState == _CaptureState.capturing,
                      isShowingResult: isShowingQr,
                      detectedRect: _currentRect,
                      scannedValue: _scannedValue,
                    ),
                  );

                  if (isShowingQr && _scannedValue != null && _captureTargetRect != null) {
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        customView,
                        QrContentWidget(
                          qrData: _scannedValue!,
                          qrStartRect: _captureTargetRect!,
                          qrTargetRect: qrTargetRect,
                          qrProgress: qrProgress,
                          padding: const EdgeInsets.all(14),
                        ),
                      ],
                    );
                  }

                  return customView;
                }

                return ScannerBox(
                  boundingRect: isShowingQr ? (_currentRect ?? viewfinderRect) : displayRect,
                  scanProgress: _anim.value,
                  alpha: isShowingQr ? 0.92 : displayAlpha,
                  isScanned: isShowingQr,
                  isIdle: !isShowingQr && isIdle && _currentRect == null,
                  isCapturing: !isShowingQr && _captureState == _CaptureState.capturing,
                  showQrContent: isShowingQr,
                  qrData: _scannedValue,
                  qrStartRect: _captureTargetRect,
                  qrTargetRect: qrTargetRect,
                  qrProgress: qrProgress,
                  accentColor: widget.accentColor,
                  successColor: widget.successColor,
                  scanLineColor: widget.scanLineColor ?? widget.accentColor,
                );
              },
            ),
          ),

          if (isIdle && _currentRect == null && widget.hintText != null)
            Positioned(
              top: viewfinderRect.bottom + 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    widget.hintText!,
                    textAlign: TextAlign.center,
                    style:
                        widget.hintTextStyle ??
                        const TextStyle(color: Colors.white70, fontSize: 13, height: 1.6, letterSpacing: 0.3),
                  ),
                ),
              ),
            ),

          if (_scannedValue != null && _captureState == _CaptureState.showingResult)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).padding.bottom + 32),
                child: widget.resultBuilder != null
                    ? widget.resultBuilder!(context, _scannedValue!)
                    : _ResultCard(value: _scannedValue!, accentColor: widget.accentColor),
              ),
            ),
        ],
      ),
    );
  }

  PreferredSizeWidget _appBar({required bool isBackCamera}) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      title: widget.title,
      actions: [
        if (widget.showUploadButton)
          IconButton(
            icon: const Icon(Icons.photo_library_rounded, color: Colors.white70),
            tooltip: 'Scan from gallery',
            onPressed: _captureState == _CaptureState.idle ? _pickAndScanImage : null,
          ),
        if (widget.showTorchButton && isBackCamera)
          IconButton(
            icon: Icon(
              _isTorchOn ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
              color: _isTorchOn ? widget.accentColor : Colors.white70,
            ),
            tooltip: 'Toggle torch',
            onPressed: _toggleTorch,
          ),
        if (widget.showFlipButton)
          IconButton(
            icon: const Icon(Icons.cameraswitch_rounded, color: Colors.white70),
            tooltip: 'Flip camera',
            onPressed: _switchCamera,
          ),
        if (widget.showHistoryButton && _scanHistory.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.history_rounded, color: Colors.white70),
            tooltip: 'Scan history',
            onPressed: _showHistory,
          ),
        const SizedBox(width: 4),
      ],
    );
  }
}

class QrContentWidget extends StatelessWidget {
  final String qrData;
  final Rect qrStartRect;
  final Rect qrTargetRect;
  final double qrProgress;
  final EdgeInsets padding;

  const QrContentWidget({
    super.key,
    required this.qrData,
    required this.qrStartRect,
    required this.qrTargetRect,
    required this.qrProgress,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    const inset = 3.0;
    final startQRRect = Rect.fromLTRB(
      qrStartRect.left + padding.left + inset,
      qrStartRect.top + padding.top + inset,
      qrStartRect.right - padding.right - inset,
      qrStartRect.bottom - padding.bottom - inset,
    );
    final targetQRRect = Rect.fromLTRB(
      qrTargetRect.left + padding.left + inset,
      qrTargetRect.top + padding.top + inset,
      qrTargetRect.right - padding.right - inset,
      qrTargetRect.bottom - padding.bottom - inset,
    );

    final offset = Offset.lerp(startQRRect.topLeft - targetQRRect.topLeft, Offset.zero, qrProgress)!;

    final scale = ui.lerpDouble(startQRRect.width / targetQRRect.width, 1.0, qrProgress)!;

    return Positioned(
      left: targetQRRect.left,
      top: targetQRRect.top,
      child: Transform(
        transform: Matrix4.identity()
          ..translate(offset.dx, offset.dy)
          ..scale(scale),
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: targetQRRect.width,
          height: targetQRRect.height,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
            child: QrImageView(
              data: qrData,
              version: QrVersions.auto,
              gapless: false,
              eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
              dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
              backgroundColor: Colors.white,
              padding: const EdgeInsets.all(8),
            ),
          ),
        ),
      ),
    );
  }
}

class ScannerBox extends StatelessWidget {
  final Rect boundingRect;
  final double scanProgress;
  final double alpha;
  final bool isScanned;
  final bool isIdle;
  final bool isCapturing;
  final bool showQrContent;
  final String? qrData;
  final Rect? qrStartRect;
  final Rect? qrTargetRect;
  final double qrProgress;
  final Color accentColor;
  final Color successColor;
  final Color scanLineColor;

  const ScannerBox({
    super.key,
    required this.boundingRect,
    required this.scanProgress,
    required this.alpha,
    this.isScanned = false,
    this.isIdle = false,
    this.isCapturing = false,
    this.showQrContent = false,
    this.qrData,
    this.qrStartRect,
    this.qrTargetRect,
    this.qrProgress = 0.0,
    this.accentColor = kAccent,
    this.successColor = kSuccess,
    this.scanLineColor = kAccent,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: QrOverlayPainter(
            boundingRect: boundingRect,
            scanProgress: scanProgress,
            alpha: alpha,
            isScanned: isScanned,
            isIdle: isIdle,
            isCapturing: isCapturing,
            accentColor: accentColor,
            successColor: successColor,
            scanLineColor: scanLineColor,
          ),
        ),
        if (showQrContent && qrData != null && qrTargetRect != null && qrStartRect != null)
          QrContentWidget(
            qrData: qrData!,
            qrStartRect: qrStartRect!,
            qrTargetRect: qrTargetRect!,
            qrProgress: qrProgress,
          ),
      ],
    );
  }
}

class _HistorySheet extends StatelessWidget {
  final List<String> history;
  final Color accentColor;
  const _HistorySheet({required this.history, this.accentColor = kAccent});

  static bool _isUrl(String v) => v.startsWith('http://') || v.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(height: 16),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Recent Scans',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: history.length,
            separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 1),
            itemBuilder: (ctx, i) {
              final value = history[i];
              final isUrl = _isUrl(value);
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                leading: Icon(isUrl ? Icons.link_rounded : Icons.qr_code_2_rounded, color: accentColor, size: 20),
                title: Text(
                  value,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isUrl)
                      IconButton(
                        icon: const Icon(Icons.open_in_new_rounded, color: Colors.white54, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        onPressed: () => launchUrl(Uri.parse(value), mode: LaunchMode.externalApplication),
                      ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, color: Colors.white54, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: value));
                        ScaffoldMessenger.of(
                          ctx,
                        ).showSnackBar(const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)));
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  final String value;
  final Color accentColor;
  const _ResultCard({required this.value, this.accentColor = kAccent});

  bool get _isUrl => value.startsWith('http://') || value.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.55)),
        boxShadow: [BoxShadow(color: accentColor.withValues(alpha: 0.18), blurRadius: 24)],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_isUrl ? Icons.link_rounded : Icons.qr_code_2_rounded, color: accentColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isUrl ? 'URL DETECTED' : 'QR CODE SCANNED',
                  style: TextStyle(color: accentColor, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.45),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (_isUrl)
            IconButton(
              icon: const Icon(Icons.open_in_new_rounded, color: Colors.white54, size: 20),
              tooltip: 'Open URL',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: () => launchUrl(Uri.parse(value), mode: LaunchMode.externalApplication),
            ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, color: Colors.white54, size: 20),
            tooltip: 'Copy',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 1)));
            },
          ),
        ],
      ),
    );
  }
}
