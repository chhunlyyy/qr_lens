## 1.1.2

- Add `onQrNotFound` callback to `QrLensScannerPage` — called when an image is picked from the gallery but contains no detectable QR code. Falls back to the built-in snack bar when not provided.

## 1.1.1

- Fix iOS camera rotation: frames are already in display orientation so ML Kit now receives `rotation0deg`, correcting corner-coordinate mapping on iOS.

## 1.1.0

- Add `stopStream()` and `resumeStream()` methods to `QrLensScannerController` for manual camera stream control.
- Add `autoResume` parameter to `QrLensScannerPage` — when `false`, the scanner stays frozen after a scan until `resumeStream()` is called manually.
- Add `scanLineAnimationDuration`, `boxAnimationDuration`, and `qrMoveAnimationDuration` parameters to allow customising animation timing.
- Extract `QrContentWidget` as a public standalone widget, now reused by both the default `ScannerBox` and custom `viewFinderBuilder` layouts.
- Fix `scanFromFile` to show the result directly without running the capture animation.
- Fix camera stream resume to clear the frozen frame before restarting.

## 1.0.1

- Rename `ScannerPage` to `QrLensScannerPage`.

## 1.0.0

- Initial release.
- QR code scanning with live corner tracking overlay.
- Animated capture feedback with haptic response.
- Torch/flashlight toggle.
- Front/back camera switching.
- Scan history with URL detection.
- Copy-to-clipboard and URL opening support.
