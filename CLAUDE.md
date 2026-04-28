# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Get dependencies
flutter pub get

# Run the app
flutter run

# Run tests
flutter test

# Run a single test file
flutter test test/widget_test.dart

# Analyze/lint
flutter analyze

# Build for specific platform
flutter build ios
flutter build apk
flutter build macos
flutter build web
```

## Architecture

This is a Flutter cross-platform application targeting iOS, Android, macOS, Linux, Windows, and Web.

- **Language:** Dart ^3.7.2
- **Flutter channel:** stable
- **Linting:** `flutter_lints ^5.0.0` (rules defined in `analysis_options.yaml`)

### Code structure

All application code lives in `lib/`. Currently the project is in early-stage boilerplate with a single entry point at `lib/main.dart`. As features are added, organize by feature or layer under `lib/`.

### Platform-specific code

Each platform has its own directory (`android/`, `ios/`, `macos/`, `linux/`, `windows/`, `web/`) with native configuration. Android uses Kotlin + Gradle; iOS/macOS use Swift + Xcode.
