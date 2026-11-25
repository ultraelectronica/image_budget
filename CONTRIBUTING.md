# Contributing

## Development setup

Install Flutter stable, then from the package root:

```sh
flutter pub get
flutter analyze
flutter test
```

The tests are headless and do not need an emulator or a display.

## Pull requests

- Keep the public API documented in `README.md`.
- Add a test for every sizing or cache behavior change.
- Run `dart format .` before committing.
- Do not claim total app memory savings in docs or commit messages. Report
  decoded bytes and, when available, measured RSS separately.

## Scope

This package handles decoded image sizing and Flutter's image cache. It does
not attempt to reduce the Flutter engine baseline, APK size, or Dart heap.
