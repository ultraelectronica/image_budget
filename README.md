# image_budget

**Decode only what you display, under a hard byte budget.**

`image_budget` is a small Flutter package for two related jobs:

1. Decode images at the size they actually occupy on screen, instead of at
   their full source resolution.
2. Put an explicit byte limit on Flutter's shared decoded-image cache, only
   when the app asks for one.

Status: `0.1.0-dev`. Experimental, no pub.dev release yet.

## The problem

A decoded image costs roughly:

```
width × height × 4 bytes
```

A 4000 × 3000 photo therefore occupies about **48 MB** of decoded memory,
regardless of whether the JPEG is 300 KB. Displayed in a 400 × 300 card at
3× device pixel ratio, only about **4.3 MB** of pixels are needed. The rest
is decoded, cached, and never seen.

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
        // The intrinsic pixel size is optional, but makes cover crops exact.
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
| `image` | Any `ImageProvider`: asset, network, file, or memory |
| `displaySize` | Optional logical size override. Defaults to the parent's constraints |
| `fit` | `BoxFit` value used for rendering and sizing. `contain`, `cover`, and `fill` are exact |
| `sourcePixelSize` | Optional intrinsic pixel size. Makes `cover`, `fitWidth`, and `fitHeight` exact |
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

`configure` is explicit and global. It changes `PaintingBinding.instance
.imageCache`. It is safe to call more than once. `reset()` restores the
original limits, not the original cache contents.

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

- **contain / scaleDown**: fit inside `box`, preserving aspect ratio.
- **cover**: with `sourcePixelSize`, expand the box by
  `max(sourceAspect / boxAspect, boxAspect / sourceAspect)` so the image can
  cover the box and be cropped without upscaling. Without a source size, use
  `box * coverOverscan`.
- **fill**: decode exactly to `box`.
- **fitWidth / fitHeight**: with `sourcePixelSize`, size the target box to
  the rendered width or height. Without it, fall back to fitting inside `box`.
- **none**: no resize.

Decoding uses `ResizeImage` with `allowUpscaling: false`, so a small source
is never decoded into a larger bitmap.

### Cover is exact, but not crop-aware

`BoxFit.cover` crops the decoded image at render time. With
`sourcePixelSize`, the visible region stays sharp. The package still decodes
the parts of the source that are cropped away. A future version can decode
only the visible source rectangle by using a custom codec pipeline.

Without `sourcePixelSize`, `coverOverscan` over-decodes by 2× in each axis
by default. That keeps common photo aspect ratios sharp, but extreme
panoramas may still be upscaled.

## What this does and does not save

**Saves:**

- decoded pixel memory for images that are displayed smaller than their
  source,
- bytes held by Flutter's `ImageCache`,
- memory pressure on low-RAM devices.

**Does not save:**

- APK or IPA size,
- the Flutter engine baseline,
- Dart heap, GPU buffers, platform-view textures, or other app memory,
- memory held by images you already decoded at full size elsewhere.

`ImageCache` tracks cached images. A widget can keep an image alive even
after it is evicted from the cache, so `liveImages` can exceed the configured
cache limit. The limit is a cache policy, not a total RAM guarantee.

A smaller cache can also cause more redecodes when the user scrolls back.
That can show up as jank. Tune the limit with a profile build on a real
device.

## Documentation

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

- Crop-aware decoding for `BoxFit.cover` so invisible source regions are
  never decoded.
- Quantized decode sizes to reduce cache churn during size animations.
- Optional DevTools extension for cache and live-image stats.
- A small benchmark harness for scroll jank on a physical Android device.

## License

MIT. See [LICENSE](LICENSE).
