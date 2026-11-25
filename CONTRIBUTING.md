# Contributing

## Setup

Tested with Flutter 3.50.1. From the package root:

```sh
flutter pub get
flutter analyze
flutter test

# Optional, but expected for decode sizing or cache changes.
flutter test benchmark/image_budget_benchmark_test.dart --reporter expanded
flutter test benchmark/session_benchmark_test.dart --reporter expanded
```

The tests are headless. No emulator or display needed.

For the Android profile pass, from `example/`:

```sh
flutter run --profile --dart-define=IMAGE_BUDGET_BENCH=true
```

Look for `IMAGE_BUDGET_BENCH` lines in the log. If you change the example
JPEG, regenerate it with `dart run tool/make_example_jpeg.dart`.

## Pull requests

- Document public API changes in `README.md`.
- Add a test for any sizing or cache behavior change.
- Run the benchmark when decode sizing or cache behavior changes.
- Run the session benchmark when variants, margins, or quantization change.
- Run `dart format .` before committing.
- Don't claim total app memory savings in docs or commit messages. Report
  decoded bytes and measured RSS separately if you have it.

## Docs

Keep prose short and plain. Write like you're explaining the code to
another dev, not writing a spec.

## Scope

This package handles decoded image sizing and Flutter's image cache. It
doesn't touch engine baseline, APK size, or Dart heap.
