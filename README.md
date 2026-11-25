# image_budget

Decode images at display size. Keep Flutter's image cache under a byte budget.

`image_budget` does two jobs:

1. Decode images at the size they're drawn, not their full source resolution.
2. Set a byte limit on Flutter's shared decoded-image cache, if you want one.

Status: `0.1.0-dev`. Not on pub.dev yet, so use a path dependency.

## The problem

A decoded image costs about:

```
width × height × 4 bytes
```

A 4000 × 3000 photo is 48 MB of pixels. In a 400 × 300 card at 3× device
pixel ratio (DPR), you only need 1200 × 900, or 4.32 MB. That assumes
matching aspect ratios. A `BoxFit.cover` crop can need extra pixels on one
axis. Either way, these are pixel estimates, not app RAM measurements.

Flutter already has `ResizeImage`, `cacheWidth`, and `cacheHeight`. The
annoying parts are:

- working out the target size from layout constraints and DPR,
- keeping `BoxFit.cover` crops sharp,
- and picking a cache limit instead of leaving the 100 MiB default alone.

This package does that bookkeeping for you.

## Install

Not on pub.dev yet. Use a path dependency:

```yaml
dependencies:
  image_budget:
    path: ../image_budget
```

For a complete app setup, see
[Use image_budget in an app](docs/using-in-an-app.md).

Once it's published:

```sh
flutter pub add image_budget
```

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:image_budget/image_budget.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Optional. Without it, Flutter's default cache limits stay in place.
  ImageBudget.configure(
    maxCachedBytes: 48 << 20, // 48 MiB
    maxEntries: 200,
  );

  runApp(const MyApp());
}

class PhotoCard extends StatelessWidget {
  const PhotoCard({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 400,
      height: 300,
      child: BudgetedImage(
        image: const AssetImage('assets/photo.jpg'),
        // Gives cover the real aspect ratio for its decode bounds.
        sourcePixelSize: const Size(4000, 3000),
        sourceFormat: ImageSourceFormat.jpeg,
        fit: BoxFit.cover,
        semanticLabel: 'A sample photo',
      ),
    );
  }
}
```

Use `ImageSourceFormat.jpeg` for JPEG and `ImageSourceFormat.png` for PNG.
`auto` is a fallback for unknown formats: it applies `qualityMargin` but
does not assume a native codec scale. Without the PNG hint, a PNG source
gets that extra margin too.

`BudgetedImage` measures its parent with `LayoutBuilder` when you don't pass
`displaySize`. In an unbounded parent, like a bare `Column`, pass
`displaySize` or wrap the image in a bounded box.

## API

### `BudgetedImage`

| Parameter | What it does |
|---|---|
| `image` | The `ImageProvider` to decode: asset, network, file, memory, whatever. An existing `ResizeImage` is left alone. |
| `displaySize` | Logical size to request, clamped to the parent's constraints. Without it, both axes must be bounded. |
| `fit` | How the image is painted, and how the decode bounds are picked. Defaults to `BoxFit.contain`. |
| `sourcePixelSize` | The image's real pixel size. Its aspect ratio makes `cover`, `fitWidth`, and `fitHeight` exact. |
| `coverOverscan` | Multiplier for the decode box when `cover` has no `sourcePixelSize`. Default `2.0`. |
| `sourceFormat` | Codec hint: `auto` (default), `jpeg`, or `png`. JPEG snaps to native 1/8 scales; PNG skips the quality margin. |
| `qualityMargin` | Extra decode headroom. Default `1.25`. Applied to `auto` and `jpeg`, ignored for `png`. |
| `decodeSizeStep` | Rounds the target up to a multiple of physical pixels. Default `1`, which is exact. Ignored for JPEG. |
| `imageVariants` | Optional pre-sized sources. The smallest variant that covers the target wins. |
| `selectedVariant` | Forces one variant instead of automatic selection. |
| `alignment`, `filterQuality`, `semanticLabel`, `excludeFromSemantics`, `frameBuilder`, `loadingBuilder`, `errorBuilder` | Passed straight to `Image`. |

### JPEG, PNG, and pre-sized variants

`sourceFormat` tells the sizer what the codec will do:

- **`jpeg`**: with `sourcePixelSize`, snap up to the next native 1/8 source
  scale. The codec decodes fewer pixels.
- **`png`**: ignore `qualityMargin` and ask for the exact target. The codec
  still has to decode the full PNG, then resize.
- **`auto`**: apply the margin without assuming a native scale. Safe for
  unknown formats, but over-decodes PNG by the margin.

Pre-sized PNG variants are the PNG time win. Generate width buckets:

```sh
dart run tool/generate_variants.dart assets/photo.png --widths 400,800,1200
```

The tool writes `photo_400w.png`, `photo_800w.png`, and so on, then prints a
Dart snippet. It uses the `image` package; add it to your dev dependencies
if you run the tool outside this repository. Use the variants directly:

```dart
BudgetedImage(
  image: const AssetImage('assets/photo_1200w.png'),
  sourcePixelSize: const Size(1200, 900),
  imageVariants: [
    ImageVariant(
      image: const AssetImage('assets/photo_400w.png'),
      pixelSize: const Size(400, 300),
      label: '400w',
    ),
    ImageVariant(
      image: const AssetImage('assets/photo_800w.png'),
      pixelSize: const Size(800, 600),
      label: '800w',
    ),
    ImageVariant(
      image: const AssetImage('assets/photo_1200w.png'),
      pixelSize: const Size(1200, 900),
      label: '1200w',
    ),
  ],
  sourceFormat: ImageSourceFormat.png,
  qualityMargin: 1,
  fit: BoxFit.cover,
)
```

Pass the real `pixelSize` for every variant; the widget validates it.
`image` is the fallback when `imageVariants` is empty. If no variant covers
the target, the largest one is used. `selectedVariant` forces one source.
`BoxFit.none` and `BoxFit.scaleDown` keep the largest variant because they
paint at natural size.

### Resize animations

`decodeSizeStep` groups nearby layout sizes. The default is `1`, so every
pixel size is exact. On the desktop session benchmark, step `32` cut a
100-frame resize animation from 41 unique sizes and 41 decodes to 5 and 5,
and reduced peak cache bytes from 49.5 MiB to 6.27 MiB. The same step did not
show a reliable win on a static image feed, and it over-decodes small 1×
targets. Use it for layouts that resize continuously, not as a blanket
default. On a 60 Hz phone the step 32 path still retained more bytes and
used more raster time than one full-size decode at a small card size. Treat
it as a cache-pressure tool, not an automatic frame-time win.

### `ImageBudget`

```dart
ImageBudget.configure(
  maxCachedBytes: 48 << 20,
  maxEntries: 200,
);

final stats = ImageBudget.stats;
print('${stats.cachedBytes} cached bytes');
print('${stats.liveImages} live images');

ImageBudget.clear(); // Drops cached images. Live ones stay alive.
ImageBudget.reset(); // Restores the limits from before configure().
```

`configure` needs at least one of the two limits. It changes
`PaintingBinding.instance.imageCache`, the cache shared by standard providers
on the current binding. Calling it again applies the new limits. `reset()`
restores the old limits, not the old contents, so lowering a limit can evict
entries.

`ImageBudget.stats` reports:

- `cachedBytes` and `cachedEntries`: what the cache is holding,
- `liveImages`: images widgets still reference,
- `pendingImages`: images still loading,
- `maxCachedBytes` and `maxEntries`: your limits,
- `byteUsage`: fraction of the byte budget in use, 0 to 1,
- `isOverBudget`: true when either limit is exceeded.

`decodedBytesFor(image)` returns `width * height * 4` for a decoded
`ui.Image`. Handy for logging.

## How sizing works

For a logical size `(w, h)` and device pixel ratio `dpr`:

```
box = (ceil(w * dpr), ceil(h * dpr))
```

What gets decoded depends on `fit`:

- **contain**: fit inside the box, keeping the aspect ratio.
- **cover**: with `sourcePixelSize`, scale the source until it covers the
  box. The longer axis can exceed the box, so Flutter can crop without
  stretching the bitmap. Without a source size, fit inside a box scaled by
  `coverOverscan`.
- **fill**: decode exactly at the box size, capped by the source.
- **fitWidth / fitHeight**: use the matching axis plus the source aspect
  ratio. Without a source size, fit inside the box.
- **none / scaleDown**: no resize, since these paint at the bitmap's
  natural size.

When it resizes, the package uses `ResizeImage` with `allowUpscaling:
false`, so a small source stays small. A `ResizeImage` you pass in is left
alone.

Three options adjust the final target:

- `qualityMargin` multiplies the target before the codec sees it. It is on by
  default for `auto` and `jpeg`. PNG ignores it because the PNG path does not
  round the request down.
- `sourceFormat: jpeg` snaps up to the next native 1/8 source scale, such as
  3/8 or 1/2. This is the JPEG decode-time win.
- `decodeSizeStep` rounds up to a multiple of physical pixels. It is off by
  default and ignored for JPEG.

### Cover crops

With an accurate `sourcePixelSize`, the decoded bitmap has enough pixels for
the visible crop, as long as the source has them. The codec still decodes
pixels outside the crop. This isn't region-of-interest decoding.

Without `sourcePixelSize`, the default `coverOverscan` doubles the requested
box on each axis. That's a guess. Extreme aspect ratios can still get
upscaled when painted. Pass the real size when you have it.

## What this saves

**Saves:**

- decoded pixels for images shown smaller than their source,
- cold decode time for JPEG with a known source size,
- cold decode time for PNG when you ship pre-sized variants,
- cache bytes evicted by your limit.

**Doesn't save:**

- APK or IPA size,
- the engine baseline,
- Dart heap, GPU buffers, platform-view textures, or other app memory,
- images you already decoded at full size somewhere else.
- cold decode time for PNG resized from the original file. The codec decodes
  the full PNG, then resizes. Use variants when that matters.

Eviction doesn't kill an image a widget still uses. `liveImages` counts
streams, not bytes. The byte limit is a cache policy, not a cap on total RAM
or peak decode memory. On web, savings depend on the provider and browser.
Nobody has benchmarked that here.

A tight cache also means more redecodes when you scroll back, which can show
up as jank. Tune it in a profile build on a real device.

The desktop benchmark measured a 4000 × 3000 JPEG in a 400 × 300 card at 3×
as 1500 × 1125 (6.44 MiB) and 61 ms, versus 45.78 MiB and 154 ms for the full
decode. The same PNG case decoded 4.12 MiB but took 133 ms versus 105 ms for
the full source. A 1200 × 900 pre-sized PNG decoded 4.12 MiB in 4.9 ms
versus 45.78 MiB and 39.3 ms for the 4000 × 3000 original. These are
`flutter test` JIT numbers on one laptop, not a release-mode promise. See
[docs/benchmarks.md](docs/benchmarks.md).

A separate 60 Hz Android run measured exact PNG targets during a resize at
99.90 MiB, step 32 kept 27.75 MiB, and stock kept 14.65 MiB. Budgeted JPEG
kept 9.38 MiB versus 14.65 MiB for stock JPEG. Cache bytes are the reliable
part of that run. Frame times moved with display mode and load.

## Docs

- [Stock vs. budgeted cover demo](example/README.md)
- [Use image_budget in an app](docs/using-in-an-app.md)
- [Architecture](docs/architecture.md)
- [Benchmark method](docs/benchmarks.md)
- [Benchmark harness](benchmark/README.md)
- [Scope decision](docs/decisions/0001-scope.md)
- [Codec and quantization decision](docs/decisions/0002-jpeg-png-and-quantization.md)

## Development

```sh
flutter analyze
flutter test

# Decoded bytes, decode time, sizing overhead, and cache retention.
flutter test benchmark/image_budget_benchmark_test.dart --reporter expanded

# Pre-sized PNG, static feeds, and resize animations.
flutter test benchmark/session_benchmark_test.dart --reporter expanded
```

The tests use synthetic 4000 × 3000 PNG fixtures and generated JPEG fixtures,
then compare full decodes with display-sized ones. They report decoded bytes,
not process RSS. The benchmark writes `benchmark/results/latest.json` and
`benchmark/results/latest.md`. The session benchmark writes `session.json`
and `session.md`.

For the Android profile pass:

```sh
cd example
flutter run --profile --dart-define=IMAGE_BUDGET_BENCH=true
```

The app prints one `IMAGE_BUDGET_BENCH` line per mode. Frame timings are
diagnostic, not a release-mode promise.

## Roadmap

- Region-of-interest decoding for `BoxFit.cover`.
- Maybe a DevTools extension for cache and live-image stats.
- WebP and AVIF scaled-decode support.
- A wider device matrix for the profile benchmark.

## License

MIT. See [LICENSE](LICENSE).
