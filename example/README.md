# Image Budget demo

## Run it locally

From `example/`:

```sh
flutter build web --no-web-resources-cdn
python3 -m http.server 8080 --bind 127.0.0.1 --directory build/web
```

Open `http://127.0.0.1:8080/` in Firefox or Chrome. Skip the build if
`build/web` already exists. If `flutter` isn't on your `PATH`, use the full
path, like `~/dev/flutter/bin/flutter`. With Chrome installed,
`flutter run -d chrome` gives you hot reload.

## What to try

Flip between **Stock** (`Image`) and **Budgeted** (`BudgetedImage`) while
scrolling the same feed. Both modes use the same images and the same
`BoxFit.cover` crop. Budgeted mode passes each file's real pixel size and
`sourceFormat: ImageSourceFormat.png`, so the PNG path skips the default
quality margin. It takes the display size from the card's tight
constraints.

The feed repeats two generated fixtures: a 2400 × 1600 landscape and a
1600 × 2400 portrait. To regenerate them, run
`python3 tool/generate_fixtures.py`.

The readout shows Flutter's shared image cache, not total browser memory.
Switching modes doesn't clear the cache, and repeated cards reuse the same
assets. It's a usage demo, not a benchmark. Web decode savings aren't
verified.

## Android resize benchmark

The speed icon in the app bar opens a 1.67 s width animation. It compares
stock PNG, exact PNG, quantized PNG, stock JPEG, and budgeted JPEG. In
profile mode the app runs the benchmark automatically and prints one line
per mode:

```sh
flutter run --profile --dart-define=IMAGE_BUDGET_BENCH=true
```

Look for `IMAGE_BUDGET_BENCH` in the log. Each line has build/raster
averages, p90 total frame time, jank count, and cache bytes. Frame timings
are diagnostic, not a release-mode promise.

On an `A063` running Android 15 at 60 Hz, the 2400 × 1600 source kept
14.65 MiB for stock PNG. Exact PNG retained 99.90 MiB, step 32 retained
27.75 MiB, and budgeted JPEG retained 9.38 MiB versus 14.65 MiB for stock
JPEG. Exact and step 32 were not faster than stock at this display size.
See [the benchmark notes](../docs/benchmarks.md) for the full table.

The JPEG uses `assets/landscape.jpg`, generated from the PNG with
`dart run tool/make_example_jpeg.dart` from the package root.
