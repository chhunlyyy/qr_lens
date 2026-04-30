# qr_lens

[![pub package](https://img.shields.io/pub/v/qr_lens.svg)](https://pub.dev/packages/qr_lens)

A polished Flutter QR code scanner widget with animated capture overlay, live corner tracking, torch control, scan history, and URL detection. Built on `camera` and Google ML Kit.

## Features

- Clean scan overlay with animated sweep line
- Live corner tracking that follows QR codes in frame
- Smooth capture animation: box expand → QR fly-to-center → result card
- Haptic feedback on capture
- Torch / flashlight toggle
- Front/back camera switching
- Scan from gallery image (`ImagePicker` or custom picker)
- Scan history with URL detection, copy, and open-in-browser
- Fully replaceable: app bar, viewfinder overlay, result card, history sheet

## Getting Started

Add to your `pubspec.yaml`:

```yaml
dependencies:
  qr_lens: ^1.0.0
```

### Platform Setup

**iOS** — add camera usage description to `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Camera needed to scan QR codes</string>
```

**Android** — ensure `android/app/build.gradle` sets `minSdkVersion` to 21 or higher.

---

## Basic Usage

```dart
import 'package:qr_lens/qr_lens.dart';

Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => QrLensScannerPage(
      onScanComplete: (value) {
        // Called once the capture animation finishes.
        Navigator.pop(context);
        handleResult(value);
      },
    ),
  ),
);
```

`QrLensScannerPage` handles camera initialisation, ML Kit scanning, overlay animations, and result display with zero configuration.

---

## Customisation

### Accent & success colours

```dart
QrLensScannerPage(
  accentColor: const Color(0xFF6C63FF),  // corners, scan line, result border
  successColor: const Color(0xFF4CFF91), // glow when a QR is captured
)
```

---

### Custom app bar — `appBarBuilder`

Replace the entire app bar. Receives `isBackCamera` so you can conditionally
show a torch button.

```dart
QrLensScannerPage(
  appBarBuilder: (context, {required bool isBackCamera}) {
    return AppBar(
      backgroundColor: Colors.black54,
      leading: BackButton(color: Colors.white),
      title: const Text('Scan QR'),
      actions: [
        if (isBackCamera)
          IconButton(
            icon: const Icon(Icons.flashlight_off_rounded, color: Colors.white70),
            onPressed: () {}, // wire up a QrLensScannerController to drive torch
          ),
      ],
    );
  },
)
```

---

### Custom result card — `resultBuilder`

Replace the bottom result card. The scanner still handles timing and auto-reset.

```dart
QrLensScannerPage(
  resultBuilder: (context, value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.5)),
      ),
      child: Text(value, style: const TextStyle(color: Colors.white)),
    );
  },
)
```

---

### Custom viewfinder — `viewFinderBuilder`

`viewFinderBuilder` replaces the entire scanner overlay. The returned widget
fills the **full screen**, so you can use `Positioned` with screen-coordinate
values from `ViewfinderState`.

#### `ViewfinderState` fields

| Field | Type | Description |
|---|---|---|
| `boundingRect` | `Rect` | Viewfinder window in screen coordinates |
| `scanProgress` | `double` | Normalised scan-line position (0 → 1) |
| `overlayAlpha` | `double` | Current overlay opacity (fades in/out as QR enters/leaves frame) |
| `isCapturing` | `bool` | Box-expand animation is running (QR just detected) |
| `isShowingResult` | `bool` | Capture animation finished; result card is visible |
| `detectedRect` | `Rect?` | Live bounding rect of detected QR, or `null` |
| `scannedValue` | `String?` | The scanned string, available from capture onward |

#### Minimal example — custom dim + border

```dart
QrLensScannerPage(
  viewFinderBuilder: (context, state) {
    final rect = state.boundingRect;
    return CustomPaint(
      painter: _MyOverlayPainter(rect: rect, scanProgress: state.scanProgress),
    );
  },
)

class _MyOverlayPainter extends CustomPainter {
  final Rect rect;
  final double scanProgress;

  _MyOverlayPainter({required this.rect, required this.scanProgress});

  @override
  void paint(Canvas canvas, Size size) {
    // Dim background with clear window
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(12)));
    path.fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.65));

    // Border
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(12)),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );

    // Scan line using state.scanProgress
    canvas.save();
    canvas.clipRect(rect);
    final y = rect.top + rect.height * scanProgress;
    canvas.drawLine(
      Offset(rect.left, y),
      Offset(rect.right, y),
      Paint()..color = Colors.greenAccent..strokeWidth = 2,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MyOverlayPainter old) => true;
}
```

#### Using all state fields — animated corner brackets

```dart
// In a StatefulWidget with SingleTickerProviderStateMixin:

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
Widget build(BuildContext context) {
  return QrLensScannerPage(
    viewFinderBuilder: (context, state) {
      // Wrap in AnimatedBuilder to also rebuild on the local pulse tick.
      return AnimatedBuilder(
        animation: _pulseAnim,
        builder: (context, _) {
          final rect = state.boundingRect;

          return Stack(
            fit: StackFit.expand,
            children: [
              // Main overlay via CustomPainter
              CustomPaint(
                painter: _CornerPainter(state: state, pulse: _pulseAnim.value),
              ),

              // Live detected-QR rect — visible before capture starts
              if (state.detectedRect != null &&
                  !state.isCapturing &&
                  !state.isShowingResult)
                Positioned(
                  left: state.detectedRect!.left - 4,
                  top: state.detectedRect!.top - 4,
                  width: state.detectedRect!.width + 8,
                  height: state.detectedRect!.height + 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Colors.purpleAccent.withValues(alpha: 0.7),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),

              // Status hint below the viewfinder
              Positioned(
                bottom: rect.bottom + 20,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    state.isShowingResult
                        ? 'Scanned ✓'
                        : state.isCapturing
                            ? 'Capturing…'
                            : state.detectedRect != null
                                ? 'QR detected'
                                : 'Align QR code inside the frame',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
    hintText: null, // replaced by the custom label above
  );
}
```

See [`example/lib/screens/custom_viewfinder_screen.dart`](example/lib/screens/custom_viewfinder_screen.dart) for the full `_CornerPainter` implementation with scan line, capture ring, and success glow.

#### Image or widget as the viewfinder frame

Place any widget — a PNG asset, an SVG, or a custom-painted widget — over
`state.boundingRect` and animate it with `ScaleTransition`. Pair with
`autoResume: false` and a `QrLensScannerController` to freeze the frame after
a scan and resume only after your own result dialog is dismissed.

```dart
// In a StatefulWidget with SingleTickerProviderStateMixin:

final _controller = QrLensScannerController();

late final AnimationController _pulseCtrl;
late final Animation<double> _pulseAnim;

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
Widget build(BuildContext context) {
  return QrLensScannerPage(
    controller: _controller,
    autoResume: false, // keep frame frozen until we call resumeStream()

    // Stop the pulse the moment a value is detected.
    onScanned: (_) => _pulseCtrl.stop(),

    // After capture animation finishes, show your own result UI,
    // then restart scanning.
    onScanComplete: (value) async {
      await showMyResultDialog(value);
      _pulseCtrl.repeat(reverse: true);
      _controller.resumeStream();
    },

    viewFinderBuilder: (context, state) {
      final rect = state.boundingRect;
      return Stack(
        children: [
          // Optional dim overlay (omit if your image already has dark edges).
          CustomPaint(
            size: MediaQuery.of(context).size,
            painter: _DimPainter(rect: rect),
          ),

          // Position the frame widget over the viewfinder rect.
          Positioned(
            left: rect.left,
            top: rect.top,
            width: rect.width,
            height: rect.height,
            child: ScaleTransition(
              scale: _pulseAnim,
              // Replace with your real asset:
              //   Image.asset('assets/qr_frame.png', fit: BoxFit.contain)
              //   SvgPicture.asset('assets/qr_frame.svg')
              child: Image.asset('assets/qr_frame.png', fit: BoxFit.contain),
            ),
          ),
        ],
      );
    },

    // Suppress the built-in result card — we show our own dialog.
    resultBuilder: (context, value) => const SizedBox.shrink(),
    hintText: null,
  );
}
```

The image asset should be **transparent in the centre** so the live camera feed
shows through. Dark or semi-transparent edges on the asset act as the natural
dim overlay, removing the need for `_DimPainter`.

See [`example/lib/screens/image_viewfinder_screen.dart`](example/lib/screens/image_viewfinder_screen.dart) for the full runnable version with a placeholder frame drawn via `CustomPaint`.

---

### Programmatic control — `QrLensScannerController`

```dart
final _controller = QrLensScannerController();

QrLensScannerPage(
  controller: _controller,
  autoResume: false, // scanner stays frozen after each scan
  onScanComplete: (value) {
    validate(value); // do your work
    _controller.resumeStream(); // then restart when you're ready
  },
)

// Scan from a file (e.g. from photo_manager or file_picker):
final file = await ImagePicker().pickImage(source: ImageSource.gallery);
if (file != null) await _controller.scanFromFile(file);
```

---

### Custom gallery picker — `imagePickerBuilder`

Replace the default `ImagePicker` invoked by the upload button:

```dart
QrLensScannerPage(
  imagePickerBuilder: () async {
    // Return an XFile, or null to cancel.
    return await MyCustomPicker.pick();
  },
)
```

---

### Timing

```dart
QrLensScannerPage(
  scanLineAnimationDuration: const Duration(milliseconds: 2400),
  boxAnimationDuration: const Duration(milliseconds: 350),
  qrMoveAnimationDuration: const Duration(milliseconds: 900),
  qrSnippetDelay: const Duration(milliseconds: 500),
  onScanCompleteDelay: Duration.zero,
  resultDuration: const Duration(milliseconds: 2800),
  autoResume: true,
)
```

---

## Examples

The [`example/`](example/) directory contains a runnable app with four screens:

| Screen | File | Demonstrates |
|---|---|---|
| Default Scanner | `screens/default_scanner_screen.dart` | Zero-config drop-in usage |
| Custom Viewfinder | `screens/custom_viewfinder_screen.dart` | `viewFinderBuilder` with all `ViewfinderState` fields, local `AnimationController` |
| Branded Scanner | `screens/branded_scanner_screen.dart` | `appBarBuilder` + `resultBuilder` + minimal rounded overlay |
| Image Viewfinder | `screens/image_viewfinder_screen.dart` | Image / widget over `boundingRect` with `ScaleTransition` pulse, `autoResume: false`, controller-driven resume |

Run it with:

```
cd example
flutter run
```

---

## License

MIT
