import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'scanner_theme.dart';

class QrOverlayPainter extends CustomPainter {
  final Rect boundingRect;
  final double scanProgress;
  final double alpha;
  final bool isScanned;
  final bool isIdle;
  final bool isCapturing;
  final Color accentColor;
  final Color successColor;
  final Color scanLineColor;

  static const _cornerLen = 24.0;
  static const _cornerStroke = 3.0;

  const QrOverlayPainter({
    required this.boundingRect,
    required this.scanProgress,
    required this.alpha,
    required this.isScanned,
    this.isIdle = false,
    this.isCapturing = false,
    this.accentColor = kAccent,
    this.successColor = kSuccess,
    this.scanLineColor = kAccent,
  });

  Color get _cornerColor => isScanned ? successColor : (isIdle ? Colors.white : accentColor);

  @override
  void paint(Canvas canvas, Size size) {
    if (alpha <= 0.001) return;
    _paintDim(canvas, size);
    _paintCorners(canvas);
    if (isScanned) {
      _paintSuccessGlow(canvas);
    } else if (!isCapturing) {
      _paintScanLine(canvas);
    } else {
      _paintCaptureGlow(canvas);
    }
  }

  void _paintDim(Canvas canvas, Size size) {
    final dimAlpha = (isIdle ? 0.55 : 0.60) * alpha;
    final dimPaint = Paint()..color = Colors.black.withValues(alpha: dimAlpha);

    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(
        boundingRect.inflate(4),
        const Radius.circular(10),
      ));
    path.fillType = PathFillType.evenOdd;
    canvas.drawPath(path, dimPaint);

    final borderColor = isIdle ? Colors.white : accentColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(boundingRect.inflate(4), const Radius.circular(10)),
      Paint()
        ..color = borderColor.withValues(alpha: (isIdle ? 0.35 : 0.22) * alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _paintCorners(Canvas canvas) {
    final color = _cornerColor;

    _drawCorners(
      canvas,
      Paint()
        ..color = color.withValues(alpha: (isIdle ? 0.18 : 0.30) * alpha)
        ..strokeWidth = _cornerStroke + 5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );

    _drawCorners(
      canvas,
      Paint()
        ..color = color.withValues(alpha: alpha)
        ..strokeWidth = _cornerStroke
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  void _drawCorners(Canvas canvas, Paint paint) {
    final l = boundingRect.left;
    final t = boundingRect.top;
    final r = boundingRect.right;
    final b = boundingRect.bottom;

    canvas.drawLine(Offset(l, t + _cornerLen), Offset(l, t), paint);
    canvas.drawLine(Offset(l, t), Offset(l + _cornerLen, t), paint);
    canvas.drawLine(Offset(r - _cornerLen, t), Offset(r, t), paint);
    canvas.drawLine(Offset(r, t), Offset(r, t + _cornerLen), paint);
    canvas.drawLine(Offset(r, b - _cornerLen), Offset(r, b), paint);
    canvas.drawLine(Offset(r, b), Offset(r - _cornerLen, b), paint);
    canvas.drawLine(Offset(l + _cornerLen, b), Offset(l, b), paint);
    canvas.drawLine(Offset(l, b), Offset(l, b - _cornerLen), paint);
  }

  void _paintScanLine(Canvas canvas) {
    canvas.save();
    canvas.clipRect(boundingRect);

    final y = boundingRect.top + boundingRect.height * scanProgress;
    final w = boundingRect.width;
    final x = boundingRect.left;

    final glowRect = Rect.fromLTWH(x, y - 24, w, 48);
    canvas.drawRect(
      glowRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            scanLineColor.withValues(alpha: 0.10 * alpha),
            scanLineColor.withValues(alpha: 0.04 * alpha),
            Colors.transparent,
          ],
          stops: const [0, 0.35, 0.65, 1],
        ).createShader(glowRect),
    );

    canvas.drawLine(
      Offset(x, y),
      Offset(x + w, y),
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            scanLineColor.withValues(alpha: 0.50 * alpha),
            scanLineColor.withValues(alpha: alpha),
            scanLineColor.withValues(alpha: 0.50 * alpha),
            Colors.transparent,
          ],
          stops: const [0, 0.15, 0.5, 0.85, 1],
        ).createShader(Rect.fromLTWH(x, y, w, 2))
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke,
    );

    canvas.restore();
  }

  void _paintCaptureGlow(Canvas canvas) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(boundingRect.inflate(4), const Radius.circular(10)),
      Paint()
        ..color = accentColor.withValues(alpha: 0.08 * alpha)
        ..style = PaintingStyle.fill,
    );
  }

  void _paintSuccessGlow(Canvas canvas) {
    final pulse = (math.sin(scanProgress * 2 * math.pi) * 0.5 + 0.5);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        boundingRect.inflate(6 + 6 * pulse),
        const Radius.circular(10),
      ),
      Paint()
        ..color = successColor.withValues(alpha: (0.12 + 0.18 * pulse) * alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 + 10 * pulse)
        ..style = PaintingStyle.fill,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(boundingRect, const Radius.circular(6)),
      Paint()
        ..color = successColor.withValues(alpha: (0.05 + 0.07 * pulse) * alpha)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(QrOverlayPainter old) =>
      old.scanProgress != scanProgress ||
      old.boundingRect != boundingRect ||
      old.alpha != alpha ||
      old.isScanned != isScanned ||
      old.isIdle != isIdle ||
      old.isCapturing != isCapturing ||
      old.accentColor != accentColor ||
      old.successColor != successColor ||
      old.scanLineColor != scanLineColor;
}
