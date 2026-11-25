# image_budget

**Decode images for their display size and set a budget for Flutter’s image cache.**

`image_budget` is a small Flutter package for two related jobs:

1. Decode images at the size they actually occupy on screen, instead of at
   their full source resolution.
2. Put an explicit byte limit on Flutter's shared decoded-image cache, only
   when the app asks for one.

Status: `0.1.0-dev`. Use a local path dependency while the package is unpublished.

## The problem

A decoded image costs roughly:

```
width × height × 4 bytes
```

At four bytes per pixel, a 4000 × 3000 photo represents **48.00 MB** of
decoded pixel data. In a 400 × 300 logical card at 3× device pixel ratio,
the same photo needs **4.32 MB** at 1200 × 900. That comparison assumes
matching aspect ratios. A `BoxFit.cover` crop may need extra pixels along
one axis. These figures are pixel estimates, not app RAM measurements.

Flutter can already do the right thing with `ResizeImage` and `cacheWidth` /
`cacheHeight`. The hard parts are:

- computing the right target size from layout constraints and device pixel
  ratio,
- keeping `BoxFit.cover` crops sharp,
- and making the cache limit explicit instead of relying on the 100 MiB
  default.

This package packages those decisions into one widget and one opt-in cache
configuration.

## Install

Until the first pub.dev release, use a path dependency:

```yaml
dependencies:
  image_budget:
    path: ../image_budget
```

Planned pub.dev install:

```sh
flutter pub add image_budget
```

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:image_budget/image_budget.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Optional. Without this, Flutter's default image cache limits stay active.
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
        // The intrinsic aspect ratio lets cover choose the right decode bounds.
        sourcePixelSize: const Size(4000, 3000),
        fit: BoxFit.cover,
        semanticLabel: 'A sample photo',
      ),
    );
  }
}
```

`BudgetedImage` measures its parent with `LayoutBuilder` when `displaySize`
is not provided. In an unbounded context such as a bare `Column`, provide
`displaySize` or wrap the widget in a bounded box.

## API

### `BudgetedImage`

| Parameter | Meaning |
|---|---|
| `image` | A Flutter `ImageProvider`, such as an asset, network, file, or memory image. An existing `ResizeImage` is left unchanged. |
| `displaySize` | Optional logical size request, clamped to the parent's constraints. Without it, both axes must be bounded. |
| `fit` | Paint fit, defaulting to `BoxFit.contain`. Also determines the decode bounds. |
| `sourcePixelSize` | Optional intrinsic pixel dimensions. The aspect ratio is used for `cover`, `fitWidth`, and `fitHeight`. |
| `coverOverscan` | Fallback multiplier when `cover` is used without `sourcePixelSize`. Default `2.0` |
| `alignment` | Passed to `Image` |
| `filterQuality` | Passed to `Image` |
| `semanticLabel` | Passed to `Image` |
| `excludeFromSemantics` | Passed to `Image` |
| `frameBuilder` | Passed to `Image` |
| `loadingBuilder` | Passed to `Image` |
| `errorBuilder` | Passed to `Image` |

### `ImageBudget`

```dart
ImageBudget.configure(
  maxCachedBytes: 48 << 20,
  maxEntries: 200,
);

final stats = ImageBudget.stats;
print('${stats.cachedBytes} cached bytes');
print('${stats.liveImages} live images');

ImageBudget.clear(); // Clear cached images. Live images stay alive.
ImageBudget.reset(); // Restore the cache limits that existed before configure().
```

`configure` explicitly changes `PaintingBinding.instance.imageCache`, the
shared cache for standard providers on the current Flutter binding. It is
safe to call more than once. `reset()` restores the original limits, not the
original cache contents.

`ImageBudget.stats` reports:

- `cachedBytes`: bytes held by the image cache,
- `cachedEntries`: number of cached entries,
- `liveImages`: images still referenced by widgets,
- `pendingImages`: images currently loading,
- `maxCachedBytes`: configured cache byte limit,
- `maxEntries`: configured entry limit.

## How sizing works

For a logical display size `(w, h)` and device pixel ratio `dpr`:

```
box = (ceil(w * dpr), ceil(h * dpr))
```

The decode target depends on `fit`:

- **contain**: fit inside `box`, preserving aspect ratio.
- **cover**: with `sourcePixelSize`, scale the source rectangle until it
  covers `box` on both axes. The longer axis can exceed the visible box so
  Flutter can crop without magnifying the retained bitmap, if the source
  has enough pixels. Without a source size, use `box × coverOverscan`.
- **fill**: request the box dimensions directly, clamped to the source.
- **fitWidth / fitHeight**: use the corresponding axis and source aspect
  ratio when known. Otherwise, fall back to fitting inside `box`.
- **none / scaleDown**: leave the provider unchanged to preserve
  intrinsic-size painting behavior.

Decoding uses `ResizeImage` with `allowUpscaling: false`, so a small source
is never decoded into a larger bitmap.

### Cover crops at paint time

With an accurate `sourcePixelSize`, the decode target leaves enough pixels
for the visible region when the source resolution allows it. The codec still
decodes pixels outside the visible crop. This is not region-of-interest decoding.

Without `sourcePixelSize`, `coverOverscan` doubles the requested bounds on
each axis by default, not necessarily the decoded dimensions. Extreme
aspect ratios may still be magnified at paint time. Pass the source size
when available to avoid guessing.

## What this does and does not save

**Saves:**

- decoded pixel memory for images that are displayed smaller than their
  source,
- bytes retained in Flutter's `ImageCache` when an opt-in limit evicts entries.

**Does not save:**

- APK or IPA size,
- the Flutter engine baseline,
- Dart heap, GPU buffers, platform-view textures, or other app memory,
- memory held by images you already decoded at full size elsewhere.

An image stream can remain live after cache eviction. `liveImages` counts
tracked streams, not bytes. The limit is a cache policy, not a total RAM
or peak decode-memory guarantee. Runtime decode savings on web depend on the
provider and browser and have not been benchmarked.

A smaller cache can also cause more redecodes when the user scrolls back.
That can show up as jank. Tune the limit with a profile build on a real
device.

## Documentation

- [Stock vs. budgeted cover demo](example/README.md)
- [Architecture](docs/architecture.md)
- [Benchmark method](docs/benchmarks.md)
- [Scope decision](docs/decisions/0001-scope.md)

## Development

```sh
flutter analyze
flutter test
```

The test suite generates a 4000 × 3000 PNG in memory and compares the
decoded pixel bytes of a full decode with a display-sized decode. It reports
decoded bytes, not process RSS.

## Roadmap

- Investigate decoding only the visible source region for `BoxFit.cover`.
- Quantized decode sizes to reduce cache churn during size animations.
- Optional DevTools extension for cache and live-image stats.
- A small benchmark harness for scroll jank on a physical Android device.

## License

MIT. See [LICENSE](LICENSE).
