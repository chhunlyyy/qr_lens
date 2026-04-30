import 'package:flutter/material.dart';
import 'package:qr_lens/qr_lens.dart';

/// Demonstrates using an image (or any widget) as the viewfinder overlay,
/// with a [ScaleTransition] pulse that stops on capture and resumes after
/// the result is handled.
///
/// This is the same pattern you would use in production when you have a
/// custom PNG or SVG scanner frame:
///
/// ```dart
/// // With flutter_svg:
/// child: SvgPicture.asset('assets/qr_frame.svg', fit: BoxFit.contain),
///
/// // With a PNG asset:
/// child: Image.asset('assets/qr_frame.png', fit: BoxFit.contain),
/// ```
///
/// The image should be transparent in the centre (so the camera shows
/// through) and carry its own dim / decorative edges.
///
/// Key points demonstrated:
///   • [QrLensScannerController] — stops and resumes the camera stream.
///   • [autoResume: false]       — keeps the frame frozen after a scan so
///                                 you control when scanning restarts.
///   • [onScanned]               — fires the moment a value is detected;
///                                 used to pause the pulse animation.
///   • [viewFinderBuilder]       — positions the frame widget over
///                                 [state.boundingRect] using [ScaleTransition].
class ImageViewfinderScreen extends StatefulWidget {
  const ImageViewfinderScreen({super.key});

  @override
  State<ImageViewfinderScreen> createState() => _ImageViewfinderScreenState();
}

class _ImageViewfinderScreenState extends State<ImageViewfinderScreen>
    with SingleTickerProviderStateMixin {
  final _controller = QrLensScannerController();

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  bool _resultShowing = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  // Called the moment a QR value is detected (before animation completes).
  // Stop pulsing so the frame sits still during the capture animation.
  void _onScanned(String _) {
    _pulseCtrl.stop();
  }

  // Called after the full capture animation finishes.
  // Show a result dialog, then resume scanning.
  void _onScanComplete(String value) async {
    if (_resultShowing) return;
    _resultShowing = true;

    await _showResult(value);

    _resultShowing = false;
    _pulseCtrl.repeat(reverse: true);
    _controller.resumeStream();
  }

  @override
  Widget build(BuildContext context) {
    return QrLensScannerPage(
      controller: _controller,

      // Keep the frame frozen after a scan — we resume manually in
      // _onScanComplete once the user dismisses the result dialog.
      autoResume: false,

      onScanned: _onScanned,
      onScanComplete: _onScanComplete,

      // ── Custom viewfinder ──────────────────────────────────────────
      viewFinderBuilder: (context, state) {
        final rect = state.boundingRect;

        return Stack(
          children: [
            // 1. Dim overlay with a transparent cutout for the camera.
            //    If your image already carries its own dark edges (common
            //    with transparent-centre PNGs), you can omit this layer.
            CustomPaint(
              size: MediaQuery.of(context).size,
              painter: _DimPainter(rect: rect),
            ),

            // 2. Frame image, sized and centred on boundingRect.
            //
            //    Replace _FrameWidget with your actual asset:
            //      Image.asset('assets/qr_frame.png', fit: BoxFit.contain)
            //    or:
            //      SvgPicture.asset('assets/qr_frame.svg')
            Positioned(
              left: rect.left,
              top: rect.top,
              width: rect.width,
              height: rect.height,
              child: ScaleTransition(
                scale: _pulseAnim,
                child: const _FrameWidget(),
              ),
            ),
          ],
        );
      },

      // Hide everything else — the image is the entire UI.
      hintText: null,
      showTorchButton: true,
      showFlipButton: true,
      showHistoryButton: false,
      showUploadButton: false,

      appBarBuilder: (ctx, {required bool isBackCamera}) => AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70),
          onPressed: () => Navigator.of(ctx).pop(),
        ),
      ),

      // Suppress the built-in result card — result is shown via dialog.
      resultBuilder: (context, value) => const SizedBox.shrink(),
    );
  }

  Future<void> _showResult(String value) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: const Color(0xFF1C1C1C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'QR Scanned',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF00D4AA),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('OK', style: TextStyle(color: Colors.black)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Dim painter ───────────────────────────────────────────────────────────────

/// Draws a semi-transparent overlay with a transparent window at [rect].
/// Use this when your frame asset does not carry its own dark background.
class _DimPainter extends CustomPainter {
  final Rect rect;

  const _DimPainter({required this.rect});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRect(rect); // transparent cutout
    path.fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.55));
  }

  @override
  bool shouldRepaint(_DimPainter old) => old.rect != rect;
}

// ── Frame widget ──────────────────────────────────────────────────────────────

/// Placeholder that mimics a custom PNG scanner-frame asset.
///
/// In a real app, replace this with:
///   Image.asset('assets/qr_frame.png', fit: BoxFit.contain)
///
/// The real image should:
///   • be fully transparent in the centre
///   • carry corner decoration / brand marks on its edges
///   • optionally carry semi-transparent dark edges (removing the need
///     for _DimPainter above)
class _FrameWidget extends StatelessWidget {
  const _FrameWidget();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _FramePainter());
  }
}

class _FramePainter extends CustomPainter {
  static const _accent = Color(0xFF00D4AA);
  static const _corner = 36.0;
  static const _stroke = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Outer glow
    canvas.drawPath(
      _cornersPath(0, 0, w, h),
      Paint()
        ..color = _accent.withValues(alpha: 0.35)
        ..strokeWidth = _stroke + 8
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Sharp corners
    canvas.drawPath(
      _cornersPath(0, 0, w, h),
      Paint()
        ..color = _accent
        ..strokeWidth = _stroke
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );

    // Centre cross-hair dot
    canvas.drawCircle(
      Offset(w / 2, h / 2),
      4,
      Paint()..color = _accent.withValues(alpha: 0.5),
    );
    canvas.drawCircle(
      Offset(w / 2, h / 2),
      2,
      Paint()..color = _accent,
    );
  }

  Path _cornersPath(double l, double t, double r, double b) {
    const c = _corner;
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

  @override
  bool shouldRepaint(_FramePainter old) => false;
}
