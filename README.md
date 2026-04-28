# qr_lens

[![pub package](https://img.shields.io/pub/v/qr_lens.svg)](https://pub.dev/packages/qr_lens)

A polished Flutter QR code scanner widget with animated capture overlay, live corner tracking, torch control, scan history, and URL detection. Built on `camera` and Google ML Kit.

## Features

- Clean scan overlay with animated scanning line
- Live corner tracking that follows QR codes in frame
- Smooth capture animation with haptic feedback
- Torch/flashlight toggle
- Front/back camera switching
- Scan history with URL detection
- Copy-to-clipboard and URL opening

## Getting Started

Add to your `pubspec.yaml`:

```yaml
dependencies:
  qr_lens: ^1.0.0
```

### Platform Setup

**iOS**: Add camera usage description to `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Camera needed to scan QR codes</string>
```

**Android**: Ensure `android/app/build.gradle` has `minSdkVersion` 21 or higher.

### Usage

```dart
import 'package:qr_lens/qr_lens.dart';

// Push ScannerPage as a full-screen route
Navigator.push(
  context,
  MaterialPageRoute(builder: (context) => const ScannerPage()),
);
```

The `ScannerPage` widget handles everything — camera initialization, scanning, overlay animations, and result display.

## Customization

You can override the accent and success colors by importing `scanner_theme.dart` and changing `kAccent` and `kSuccess` in your own theme, or pass them via the widget constructors if you extend the classes.

## License

MIT
