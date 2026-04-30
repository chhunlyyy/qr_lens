import 'package:flutter/material.dart';
import 'package:qr_lens/qr_lens.dart';

/// Demonstrates every field of [ViewfinderState] exposed by [viewFinderBuilder].
///
/// The overlay is built from two pieces:
///   • [_OverlayPainter] — a CustomPainter that draws the dim background,
///     corner brackets, animated scan line, capture ring, and success glow.
///   • [_DetectedQrBox] — a positioned widget that highlights the live
///     detected-QR rect before the capture animation starts.
///
/// A separate [AnimationController] drives a pulse effect that is entirely
/// independent of the scanner's own internal animation ticks, showing how to
/// combine local animations with the state callbacks.
class CustomViewfinderScreen extends StatefulWidget {
  const CustomViewfinderScreen({super.key});

  @override
  State<CustomViewfinderScreen> createState() => _CustomViewfinderScreenState();
}

class _CustomViewfinderScreenState extends State<CustomViewfinderScreen>
    with SingleTickerProviderStateMixin {
  // Local controller — drives the capture-ring / success-glow pulse.
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return QrLensScannerPage(
      // ── Custom viewfinder ──────────────────────────────────────────────
      //
      // [viewFinderBuilder] replaces the entire default ScannerBox overlay.
      // It is called on every animation tick and receives a [ViewfinderState]
      // snapshot. The returned widget fills the full screen so you can use
      // Positioned/Stack with screen-coordinate values from [state.boundingRect]
      // and [state.detectedRect].
      viewFinderBuilder: (context, state) {
        // Wrap in AnimatedBuilder so the local pulse animation also triggers
        // a rebuild. The scanner passes [state] fresh each tick regardless.
        return AnimatedBuilder(
          animation: _pulseAnim,
          builder: (context, _) => _CustomOverlay(
            state: state,
            pulse: _pulseAnim.value,
          ),
        );
      },

      // Hide the default hint — our overlay renders its own status label.
      hintText: null,

      onScanComplete: (value) => debugPrint('Scanned: $value'),
    );
  }
}

// ── Overlay widget ────────────────────────────────────────────────────────────

class _CustomOverlay extends StatelessWidget {
  final ViewfinderState state;

  /// 0–1 value from the local AnimationController. Used for pulsing effects
  /// that need their own timing independent of the scanner's scan-line tick.
  final double pulse;

  const _CustomOverlay({required this.state, required this.pulse});

  @override
  Widget build(BuildContext context) {
    final rect = state.boundingRect;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Dark background + corner brackets + dynamic scan/capture/result
        //    effects — all drawn in a single CustomPainter pass.
        CustomPaint(painter: _OverlayPainter(state: state, pulse: pulse)),

        // 2. Live detected-QR bounding box.
        //    [state.detectedRect] is non-null while the scanner sees a QR but
        //    hasn't started the capture animation yet. It's in screen coords,
        //    so it can be used directly in a Positioned inside this Stack.
        if (state.detectedRect != null &&
            !state.isCapturing &&
            !state.isShowingResult)
          _DetectedQrBox(rect: state.detectedRect!),

        // 3. Status label — shows the current phase. Remove or replace in
        //    a real app; included here for educational purposes.
        Positioned(
          bottom: rect.bottom + 20,
          left: 0,
          right: 0,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                key: ValueKey(_statusLabel),
                _statusLabel,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String get _statusLabel {
    if (state.isShowingResult) return 'Scanned ✓  ${state.scannedValue ?? ''}';
    if (state.isCapturing) return 'Capturing…';
    if (state.detectedRect != null) return 'QR detected — hold still';
    return 'Align QR code inside the frame';
  }
}

// ── CustomPainter ─────────────────────────────────────────────────────────────

class _OverlayPainter extends CustomPainter {
  final ViewfinderState state;
  final double pulse;

  static const double _cornerLen = 28.0;
  static const double _strokeWidth = 3.0;
  static const _accentIdle = Color(0xFF6C63FF);
  static const _accentCapture = Colors.white;
  static const _accentSuccess = Color(0xFF4CFF91);

  _OverlayPainter({required this.state, required this.pulse});

  Color get _cornerColor {
    if (state.isShowingResult) return _accentSuccess;
    if (state.isCapturing) return _accentCapture;
    return _accentIdle;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = state.boundingRect;

    // Step 1: dim the area outside the viewfinder window.
    _paintDim(canvas, size, rect);

    // Step 2: corner bracket marks (glow + sharp pass).
    _paintCorners(canvas, rect);

    // Step 3: pick the right effect for the current scan phase.
    //   • isCapturing      — the box animation is running (QR just detected)
    //   • isShowingResult  — capture animation finished; result card is visible
    //   • else             — idle scanning, draw the sweep line
    if (state.isShowingResult) {
      _paintSuccessGlow(canvas, rect);
    } else if (state.isCapturing) {
      _paintCaptureRing(canvas, rect);
    } else {
      _paintScanLine(canvas, rect);
    }
  }

  void _paintDim(Canvas canvas, Size size, Rect rect) {
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(12)));
    path.fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.65));
  }

  void _paintCorners(Canvas canvas, Rect rect) {
    // Glow layer
    canvas.drawPath(
      _cornersPath(rect),
      Paint()
        ..color = _cornerColor.withValues(alpha: 0.35)
        ..strokeWidth = _strokeWidth + 6
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    // Sharp layer
    canvas.drawPath(
      _cornersPath(rect),
      Paint()
        ..color = _cornerColor
        ..strokeWidth = _strokeWidth
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  Path _cornersPath(Rect rect) {
    final l = rect.left;
    final t = rect.top;
    final r = rect.right;
    final b = rect.bottom;
    const c = _cornerLen;

    return Path()
      // top-left
      ..moveTo(l, t + c)
      ..lineTo(l, t)
      ..lineTo(l + c, t)
      // top-right
      ..moveTo(r - c, t)
      ..lineTo(r, t)
      ..lineTo(r, t + c)
      // bottom-right
      ..moveTo(r, b - c)
      ..lineTo(r, b)
      ..lineTo(r - c, b)
      // bottom-left
      ..moveTo(l + c, b)
      ..lineTo(l, b)
      ..lineTo(l, b - c);
  }

  // [state.scanProgress] is the normalised (0→1) position of the scan line,
  // driven by the scanner's own internal AnimationController.
  void _paintScanLine(Canvas canvas, Rect rect) {
    canvas.save();
    canvas.clipRect(rect);

    final y = rect.top + rect.height * state.scanProgress;
    final x = rect.left;
    final w = rect.width;

    // Soft glow band
    canvas.drawRect(
      Rect.fromLTWH(x, y - 20, w, 40),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            _accentIdle.withValues(alpha: 0.12),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTWH(x, y - 20, w, 40)),
    );

    // Sharp line
    canvas.drawLine(
      Offset(x + 8, y),
      Offset(x + w - 8, y),
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            _accentIdle.withValues(alpha: 0.6),
            _accentIdle,
            _accentIdle.withValues(alpha: 0.6),
            Colors.transparent,
          ],
          stops: const [0.0, 0.1, 0.5, 0.9, 1.0],
        ).createShader(Rect.fromLTWH(x, y, w, 2))
        ..strokeWidth = 1.5,
    );

    canvas.restore();
  }

  // Expanding ring that pulses while the box animation runs.
  void _paintCaptureRing(Canvas canvas, Rect rect) {
    final expanded = rect.inflate(4 + 8 * pulse);
    canvas.drawRRect(
      RRect.fromRectAndRadius(expanded, const Radius.circular(14)),
      Paint()
        ..color = _accentCapture.withValues(alpha: 0.08 + 0.12 * pulse)
        ..maskFilter =
            MaskFilter.blur(BlurStyle.normal, 12 + 8 * pulse)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(expanded, const Radius.circular(14)),
      Paint()
        ..color = _accentCapture.withValues(alpha: 0.55 + 0.45 * pulse)
        ..strokeWidth = _strokeWidth
        ..style = PaintingStyle.stroke,
    );
  }

  // Green pulsing glow once the result is ready.
  void _paintSuccessGlow(Canvas canvas, Rect rect) {
    final glow = 6.0 + 6.0 * pulse;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.inflate(glow), const Radius.circular(16)),
      Paint()
        ..color =
            _accentSuccess.withValues(alpha: 0.15 + 0.15 * pulse)
        ..maskFilter =
            MaskFilter.blur(BlurStyle.normal, 14 + 8 * pulse)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(12)),
      Paint()
        ..color = _accentSuccess.withValues(alpha: 0.10)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_OverlayPainter old) => true;
}

// ── Detected-QR highlight ─────────────────────────────────────────────────────

/// A thin border that tracks the live detected QR position ([state.detectedRect])
/// before the capture animation starts. Gives the user visual confirmation that
/// the scanner sees the code even before they've held still long enough.
class _DetectedQrBox extends StatelessWidget {
  final Rect rect;

  const _DetectedQrBox({required this.rect});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: rect.left - 4,
      top: rect.top - 4,
      width: rect.width + 8,
      height: rect.height + 8,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: const Color(0xFF6C63FF).withValues(alpha: 0.7),
            width: 1.5,
          ),
        ),
      ),
    );
  }
}
