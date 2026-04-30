import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_lens/qr_lens.dart';

/// Demonstrates three independent customisation surfaces together:
///
///   1. [appBarBuilder]  — replaces the entire app bar with a branded one.
///   2. [viewFinderBuilder] — a minimal rounded-window overlay with brand colours.
///   3. [resultBuilder]  — a gradient result card that matches the brand.
///
/// All other scanner behaviour (camera init, capture animation, history, etc.)
/// is unchanged.
class BrandedScannerScreen extends StatelessWidget {
  const BrandedScannerScreen({super.key});

  static const Color _brand = Color(0xFFFF6B6B);
  static const Color _success = Color(0xFF4CFF91);

  @override
  Widget build(BuildContext context) {
    return QrLensScannerPage(
      // ── 1. Custom app bar ────────────────────────────────────────────
      //
      // [appBarBuilder] receives [isBackCamera] so you can conditionally
      // show a torch button only when the back camera is active.
      appBarBuilder: (ctx, {required bool isBackCamera}) {
        return AppBar(
          backgroundColor: Colors.black.withValues(alpha: 0.55),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _brand.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.qr_code_2_rounded, color: _brand, size: 18),
              ),
              const SizedBox(width: 8),
              const Text(
                'Brand Scanner',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          actions: [
            if (isBackCamera)
              IconButton(
                icon: const Icon(Icons.flashlight_off_rounded, color: Colors.white70),
                tooltip: 'Toggle torch',
                // Torch state is managed internally; connect a controller here
                // if you need to drive it from your own UI.
                onPressed: () {},
              ),
            const SizedBox(width: 4),
          ],
        );
      },

      // ── 2. Custom viewfinder — minimal rounded window ────────────────
      //
      // Only [state.boundingRect], [state.scanProgress], [state.isCapturing],
      // and [state.isShowingResult] are used here to keep the example focused.
      viewFinderBuilder: (context, state) {
        return CustomPaint(
          painter: _RoundedOverlayPainter(state: state),
        );
      },

      // ── 3. Custom result card ────────────────────────────────────────
      //
      // [resultBuilder] receives the raw scanned string. The built-in result
      // card is replaced entirely; the scanner still handles timing and reset.
      resultBuilder: (context, value) => _BrandResultCard(value: value),

      // ── Misc ─────────────────────────────────────────────────────────
      accentColor: _brand,
      successColor: _success,
      hintText: 'Place QR code within the frame',
      showTorchButton: false, // handled manually in appBarBuilder above
    );
  }
}

// ── Rounded overlay painter ───────────────────────────────────────────────────

class _RoundedOverlayPainter extends CustomPainter {
  final ViewfinderState state;

  static const Color _brand = Color(0xFFFF6B6B);
  static const Color _success = Color(0xFF4CFF91);

  _RoundedOverlayPainter({required this.state});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = state.boundingRect;
    final radius = Radius.circular(rect.width * 0.1);

    // Dim outside the viewfinder
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(rect, radius));
    path.fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.6));

    // Border — switches to success colour on scan completion
    final borderColor =
        state.isShowingResult ? _success : _brand;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()
        ..color =
            borderColor.withValues(alpha: state.isShowingResult ? 0.85 : 0.55)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );

    // Outer glow when showing result
    if (state.isShowingResult) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(10), Radius.circular(radius.x + 6)),
        Paint()
          ..color = _success.withValues(alpha: 0.22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18)
          ..style = PaintingStyle.fill,
      );
    }

    // Scan line while idle
    if (!state.isShowingResult && !state.isCapturing) {
      canvas.save();
      canvas.clipRRect(RRect.fromRectAndRadius(rect, radius));

      final y = rect.top + rect.height * state.scanProgress;

      canvas.drawLine(
        Offset(rect.left + 12, y),
        Offset(rect.right - 12, y),
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.transparent,
              _brand.withValues(alpha: 0.55),
              _brand,
              _brand.withValues(alpha: 0.55),
              Colors.transparent,
            ],
            stops: const [0.0, 0.15, 0.5, 0.85, 1.0],
          ).createShader(Rect.fromLTWH(rect.left, y, rect.width, 2))
          ..strokeWidth = 1.5,
      );

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_RoundedOverlayPainter old) => true;
}

// ── Brand result card ─────────────────────────────────────────────────────────

class _BrandResultCard extends StatelessWidget {
  final String value;

  static const Color _brand = Color(0xFFFF6B6B);

  const _BrandResultCard({required this.value});

  bool get _isUrl =>
      value.startsWith('http://') || value.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1C1C1C),
            _brand.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _brand.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: _brand.withValues(alpha: 0.18),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _brand.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isUrl ? Icons.link_rounded : Icons.qr_code_2_rounded,
              color: _brand,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isUrl ? 'URL FOUND' : 'CODE SCANNED',
                  style: const TextStyle(
                    color: _brand,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.45,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, color: Colors.white38, size: 20),
            tooltip: 'Copy',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied to clipboard'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
