import 'package:flutter/material.dart';
import 'package:qr_lens/qr_lens.dart';

/// Simplest possible integration — no arguments required.
///
/// QrLensScannerPage ships with a built-in app bar, torch / flip / upload /
/// history buttons, animated scan-line overlay, copy / open-URL result card,
/// and auto-resume after [resultDuration]. Nothing else needs to be wired up.
class DefaultScannerScreen extends StatelessWidget {
  const DefaultScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return QrLensScannerPage(
      onScanComplete: (value) {
        // Called once the capture animation finishes.
        // Navigate, validate, or process [value] here.
        debugPrint('Scanned: $value');
      },
    );
  }
}
