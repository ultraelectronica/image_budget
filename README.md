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
        fit: BoxFit.cover,
        semanticLabel: 'A sample photo',
      ),
    );
  }
}
```

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
| `alignment`, `filterQuality`, `semanticLabel`, `excludeFromSemantics`, `frameBuilder`, `loadingBuilder`, `errorBuilder` | Passed straight to `Image`. |

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
- cache bytes evicted by your limit.

**Doesn't save:**

- APK or IPA size,
- the engine baseline,
- Dart heap, GPU buffers, platform-view textures, or other app memory,
- images you already decoded at full size somewhere else.

Eviction doesn't kill an image a widget still uses. `liveImages` counts
streams, not bytes. The byte limit is a cache policy, not a cap on total RAM
or peak decode memory. On web, savings depend on the provider and browser.
Nobody has benchmarked that here.

A tight cache also means more redecodes when you scroll back, which can show
up as jank. Tune it in a profile build on a real device.

## Docs

- [Stock vs. budgeted cover demo](example/README.md)
- [Architecture](docs/architecture.md)
- [Benchmark method](docs/benchmarks.md)
- [Scope decision](docs/decisions/0001-scope.md)

## Development

```sh
flutter analyze
flutter test
```

The tests build a 4000 × 3000 PNG in memory and compare a full decode with a
display-sized one. They report decoded bytes, not process RSS.

## Roadmap

- Region-of-interest decoding for `BoxFit.cover`.
- Quantized decode sizes, so layout animations don't churn the cache.
- Maybe a DevTools extension for cache and live-image stats.
- A scroll-jank benchmark on a real Android device.

## License

MIT. See [LICENSE](LICENSE).
