import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'qr_overlay_painter.dart';
import 'scanner_theme.dart';

// Capture flow: idle → capturing → showingQrSnippet → showingResult → idle
enum _CaptureState { idle, capturing, showingQrSnippet, showingResult }

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> with TickerProviderStateMixin {
  List<CameraDescription> _cameras = [];
  CameraController? _cameraController;
  late final AnimationController _anim;
  final BarcodeScanner _barcodeScanner = BarcodeScanner(formats: [BarcodeFormat.qrCode]);

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
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
    _anim.addListener(_onAnimTick);

    _boxAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _boxAnim.addListener(_onBoxTick);
    _boxAnim.addStatusListener(_onBoxStatus);

    _qrMoveAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _qrMoveAnim.addListener(_onQrMoveTick);
    _qrMoveAnim.addStatusListener(_onQrMoveStatus);

    _initCamera();
  }

  @override
  void dispose() {
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
    _cameras = await availableCameras();
    if (_cameras.isEmpty) return;
    final camera = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
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
      ResolutionPreset.veryHigh,
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
    } catch (e) {
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
      case 0: return InputImageRotation.rotation0deg;
      case 90: return InputImageRotation.rotation90deg;
      case 180: return InputImageRotation.rotation180deg;
      case 270: return InputImageRotation.rotation270deg;
      default: return null;
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
    try {
      final boundary = _previewKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data != null) _frozenFrameBytes = data.buffer.asUint8List();
    } catch (_) {}
  }

  Future<void> _startCapture(Rect qrRect, String value) async {
    if (_captureState != _CaptureState.idle) return;
    // Set immediately (before any await) to block re-entry from new frames.
    _captureState = _CaptureState.capturing;

    _scannedValue = value;
    _targetRect = qrRect;
    _captureStartRect = _currentRect ?? _viewfinderRect;
    _captureTargetRect = qrRect.inflate(8);

    await _freezeFrame();  // snapshot while stream is still live
    _anim.stop();
    _stopCameraStream();
    if (!mounted) return;

    _scanHistory.remove(value);
    _scanHistory.insert(0, value);
    if (_scanHistory.length > 20) _scanHistory.removeLast();

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
    HapticFeedback.mediumImpact();
    setState(() {
      _captureState = _CaptureState.showingQrSnippet;
      _currentRect = _captureTargetRect;
    });
    Future.delayed(const Duration(milliseconds: 500), () {
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
    Future.delayed(const Duration(milliseconds: 2800), () {
      if (!mounted) return;
      _resetCapture();
    });
  }

  Rect? _computeQrSnippetRect() {
    if (_captureTargetRect == null) return null;
    final screenSize = MediaQuery.of(context).size;
    final t = Curves.easeOutCubic.transform(_qrMoveAnim.value);
    final startRect = _captureTargetRect!;
    final endCenter = Offset(screenSize.width / 2, screenSize.height / 2);
    final currentCenter = Offset.lerp(startRect.center, endCenter, t)!;
    final endSize = math.min(screenSize.width, screenSize.height) * 0.68;
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
    final boxSize = short * 0.68;
    return Rect.fromCenter(center: Offset(screen.width / 2, screen.height * 0.44), width: boxSize, height: boxSize);
  }

  void _showHistory() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _HistorySheet(history: List.unmodifiable(_scanHistory)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraReady || _cameraController == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
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
      backgroundColor: Colors.black,
      appBar: _appBar(isBackCamera: isBackCamera),
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
            Positioned.fill(
              child: Image.memory(_frozenFrameBytes!, fit: BoxFit.cover, gaplessPlayback: true),
            ),

          Positioned.fill(
            child: AnimatedBuilder(
              animation: isShowingQr ? _qrMoveAnim : _anim,
              builder: (_, __) {
                final qrProgress = isShowingQrSnippet
                    ? Curves.easeOutCubic.transform(_qrMoveAnim.value)
                    : (isShowingQr ? 1.0 : 0.0);
                final targetSize = math.min(screen.width, screen.height) * 0.68;
                final qrTargetRect = Rect.fromCenter(
                  center: Offset(screen.width / 2, screen.height / 2),
                  width: targetSize,
                  height: targetSize,
                );

                return _ScannerBox(
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
                );
              },
            ),
          ),

          if (isIdle && _currentRect == null)
            Positioned(
              top: viewfinderRect.bottom + 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
                  child: const Text(
                    'Point camera at a QR code',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.6, letterSpacing: 0.3),
                  ),
                ),
              ),
            ),

          if (_scannedValue != null && _captureState == _CaptureState.showingResult)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).padding.bottom + 32),
                child: _ResultCard(value: _scannedValue!),
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
      title: const Text(
        'QR Scanner',
        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 0.4),
      ),
      actions: [
        if (isBackCamera)
          IconButton(
            icon: Icon(
              _isTorchOn ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
              color: _isTorchOn ? kAccent : Colors.white70,
            ),
            tooltip: 'Toggle torch',
            onPressed: _toggleTorch,
          ),
        IconButton(
          icon: const Icon(Icons.cameraswitch_rounded, color: Colors.white70),
          tooltip: 'Flip camera',
          onPressed: _switchCamera,
        ),
        if (_scanHistory.isNotEmpty)
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

class _ScannerBox extends StatelessWidget {
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

  const _ScannerBox({
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
          ),
        ),
        if (showQrContent && qrData != null && qrTargetRect != null && qrStartRect != null)
          _buildQrContent(),
      ],
    );
  }

  Widget _buildQrContent() {
    const inset = 3.0;
    final startQRRect = qrStartRect!.deflate(inset);
    final targetQRRect = qrTargetRect!.deflate(inset);

    final offset = Offset.lerp(
      startQRRect.topLeft - targetQRRect.topLeft,
      Offset.zero,
      qrProgress,
    )!;

    final scale = ui.lerpDouble(
      startQRRect.width / targetQRRect.width,
      1.0,
      qrProgress,
    )!;

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
            borderRadius: BorderRadius.circular(6),
            child: QrImageView(
              data: qrData!,
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

class _HistorySheet extends StatelessWidget {
  final List<String> history;
  const _HistorySheet({required this.history});

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
                leading: Icon(
                  isUrl ? Icons.link_rounded : Icons.qr_code_2_rounded,
                  color: kAccent,
                  size: 20,
                ),
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
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
                        );
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
  const _ResultCard({required this.value});

  bool get _isUrl => value.startsWith('http://') || value.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kAccent.withValues(alpha: 0.55)),
        boxShadow: [BoxShadow(color: kAccent.withValues(alpha: 0.18), blurRadius: 24)],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: kAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_isUrl ? Icons.link_rounded : Icons.qr_code_2_rounded, color: kAccent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isUrl ? 'URL DETECTED' : 'QR CODE SCANNED',
                  style: const TextStyle(
                    color: kAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
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
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 1)),
              );
            },
          ),
        ],
      ),
    );
  }
}
