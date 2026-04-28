import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QrView extends StatelessWidget {
  final String data;
  final double? size;
  final Color foregroundColor;
  final Color backgroundColor;
  final EdgeInsets padding;
  final double borderRadius;
  final QrEyeShape eyeShape;
  final QrDataModuleShape dataModuleShape;

  const QrView({
    super.key,
    required this.data,
    this.size,
    this.foregroundColor = Colors.black,
    this.backgroundColor = Colors.white,
    this.padding = const EdgeInsets.all(8),
    this.borderRadius = 6,
    this.eyeShape = QrEyeShape.square,
    this.dataModuleShape = QrDataModuleShape.square,
  });

  @override
  Widget build(BuildContext context) {
    final qr = QrImageView(
      data: data,
      version: QrVersions.auto,
      gapless: false,
      eyeStyle: QrEyeStyle(eyeShape: eyeShape, color: foregroundColor),
      dataModuleStyle: QrDataModuleStyle(dataModuleShape: dataModuleShape, color: foregroundColor),
      backgroundColor: backgroundColor,
      padding: padding,
    );

    final content = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: ColoredBox(color: backgroundColor, child: qr),
    );

    if (size != null) {
      return SizedBox(width: size, height: size, child: content);
    }
    return content;
  }
}
