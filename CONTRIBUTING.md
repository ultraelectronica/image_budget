# Contributing

## Setup

Tested with Flutter 3.50.1. From the package root:

```sh
flutter pub get
flutter analyze
flutter test
```

The tests are headless. No emulator or display needed.

## Pull requests

- Document public API changes in `README.md`.
- Add a test for any sizing or cache behavior change.
- Run `dart format .` before committing.
- Don't claim total app memory savings in docs or commit messages. Report
  decoded bytes and measured RSS separately if you have it.

## Docs

Keep prose short and plain. Write like you're explaining the code to
another dev, not writing a spec.

## Scope

This package handles decoded image sizing and Flutter's image cache. It
doesn't touch engine baseline, APK size, or Dart heap.
