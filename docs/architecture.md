# Architecture

## Pieces

```
BudgetedImage
  ├─ LayoutBuilder / displaySize
  ├─ computeDecodeTarget()
  │    ├─ logical size → physical box
  │    ├─ BoxFit policy
  │    └─ optional sourcePixelSize
  ├─ ResizeImage(provider, width, height, policy, allowUpscaling: false)
  └─ Image(provider: resized, fit: original fit, ...)

ImageBudget
  ├─ configure(maxCachedBytes, maxEntries)
  ├─ stats
  ├─ clear()
  └─ reset()
```

`lib/image_budget.dart` is the public API. Implementation lives in
`lib/src/`.

## How a widget gets sized

1. Work out the logical size.
   - If you passed `displaySize`, clamp it to the parent's constraints.
   - Otherwise, use the biggest constraints from `LayoutBuilder`.
   - If either axis is unbounded and there's no `displaySize`, throw a
     `FlutterError` that says what to do. A zero-area box renders nothing
     and skips the decode.
2. Convert to physical pixels:
   `ceil(logicalWidth * dpr)` by `ceil(logicalHeight * dpr)`.
3. Pick a decode target from `BoxFit`.
4. Wrap the provider in `ResizeImage`, unless it already is one or the fit
   needs the original bitmap.
5. Paint in a fixed-size box, so layout doesn't jump while loading.

## Decode targets

`ResizeImagePolicy.fit` keeps the aspect ratio and fits inside the given box.
`ResizeImagePolicy.exact` decodes to exactly the given dimensions.

| Fit | Source size known | Source size unknown |
|---|---|---|
| `contain` | fit inside box | fit inside box |
| `scaleDown` | no resize | no resize |
| `cover` | scale the source to cover the box | box × `coverOverscan`, then fit |
| `fill` | exact box, capped per source axis | exact box, capped per source axis |
| `fitWidth` | box width × rendered height | fit inside box |
| `fitHeight` | rendered width × box height | fit inside box |
| `none` | no resize | no resize |

Cover factor:

```
scale = max(boxWidth / sourceWidth, boxHeight / sourceHeight)
targetWidth  = max(boxWidth,  ceil(sourceWidth  × scale))
targetHeight = max(boxHeight, ceil(sourceHeight × scale))
```

A 4000 × 3000 image covering a 600 × 600 physical box asks for 800 × 600.
Flutter crops the extra width when it paints. The decoder won't enlarge a
smaller source. Codecs round to integers, so expect a pixel of drift.

## Cache policy

`ImageBudget.configure` sets two fields on
`PaintingBinding.instance.imageCache`:

- `maximumSizeBytes = maxCachedBytes`
- `maximumSize = maxEntries`

Flutter evicts least-recently-used entries when either limit is exceeded.
There's no second cache and no memory-pressure hook. The painting binding
already clears the image cache on `didHaveMemoryPressure`.

`ImageBudget.stats` reads the `ImageCache` fields directly. `cachedBytes` is
the cache's own accounting, not RSS. `liveImages` counts images that widgets
or listeners still hold. A live image survives eviction, so the byte limit
doesn't cap live-image memory.

## Why not measure total app memory?

Total RSS includes the Flutter engine, Dart heap, GPU driver allocations,
platform-view textures, and the OS. A Dart package can't control all of
that, and the image cache is one lever. So the package sticks to what it can
check: display-sized decodes and a cache byte limit you set.

## When it goes wrong

- **Unbounded parent**: pass `displaySize` or wrap the image in something
  bounded.
- **Cover without `sourcePixelSize`**: it over-decodes by `coverOverscan`,
  and panoramic sources can end up upscaled. Pass `sourcePixelSize` for an
  exact target.
- **Animated layout**: every distinct decode size is its own cache entry,
  so size animations churn the cache. A future version will quantize sizes.
- **Full-size decodes elsewhere**: `Image.asset(...)` without `cacheWidth`,
  or anything outside `BudgetedImage`, still caches a full-size bitmap.
- **Eviction during scroll**: too small a cache means redecodes when you
  scroll back. That trades memory for CPU and jank.

## Tests

- `computeDecodeTarget` has unit tests for every fit, fractional DPR,
  unbounded input, and small sources.
- Widget tests check the `Image` provider, fit, and `ResizeImage`
  dimensions without depending on frame timing.
- Cache tests set a tiny byte limit, resolve images, and check eviction and
  reset.
- The benchmark test resolves the provider, checks the decoded `ui.Image`
  dimensions, and compares `width * height * 4` for a full-size and a
  1200 × 900 decode.
