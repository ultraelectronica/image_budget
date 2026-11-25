# Architecture

## Pieces

```
BudgetedImage
  ├─ LayoutBuilder / displaySize
  ├─ optional ImageVariant selection
  ├─ computeDecodeTarget()
  │    ├─ logical size → physical box
  │    ├─ BoxFit policy
  │    ├─ optional sourcePixelSize
  │    ├─ quality margin / JPEG native scale
  │    └─ optional decodeSizeStep
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
4. Pick a variant, if any, and use its real pixel size as the source size.
5. Apply the quality margin, JPEG native scale, and decode-size step.
6. Wrap the provider in `ResizeImage`, unless it already is one or the fit
   needs the original bitmap.
7. Paint in a fixed-size box, so layout doesn't jump while loading.

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

After the fit target:

- `qualityMargin` multiplies width and height for `auto` and `jpeg`. PNG
  skips it.
- `sourceFormat: jpeg` with a source size replaces the target with the next
  native 1/8 source scale. The result is no smaller than the target.
- `decodeSizeStep` rounds up to a multiple of physical pixels. JPEG skips it.
  The default is 1, which changes nothing.

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
- **Animated layout**: every distinct decode size is its own cache entry.
  `decodeSizeStep` groups nearby sizes, but it is opt-in. The session
  benchmark found a large animation win and no reliable static-feed win. On
  one Android profile run, step 32 cut retained bytes 72% but did not
  improve raster time. Measure on your target.
- **PNG cold decode**: `ResizeImage` cuts retained bytes, but the codec still
  decodes the full PNG. Use pre-sized variants when cold decode time matters.
- **Full-size decodes elsewhere**: `Image.asset(...)` without `cacheWidth`,
  or anything outside `BudgetedImage`, still caches a full-size bitmap.
- **Eviction during scroll**: too small a cache means redecodes when you
  scroll back. That trades memory for CPU and jank.

## Tests

- `computeDecodeTarget` has unit tests for every fit, fractional DPR,
  unbounded input, small sources, quality margins, JPEG native scales, and
  decode-size steps.
- Widget tests check the `Image` provider, fit, and `ResizeImage`
  dimensions, variant selection, and source-format behavior without
  depending on frame timing.
- Cache tests set a tiny byte limit, resolve images, and check eviction and
  reset.
- `test/jpeg_quality_test.dart` compares a safe JPEG resize with an exact
  auto resize against a full decode using PSNR and MAE.
- `test/generate_variants_test.dart` checks the PNG variant generator.
- `test/decoded_bytes_benchmark_test.dart` resolves the provider, checks the
  decoded `ui.Image` dimensions, and compares `width * height * 4` for a
  full-size and a 1200 × 900 decode.
- `benchmark/image_budget_benchmark_test.dart` measures 26 layout scenarios,
  JPEG and PNG, `computeDecodeTarget` overhead, and cache retention.
- `benchmark/session_benchmark_test.dart` measures pre-sized PNG, a static
  feed, and resize animations at several decode-size steps.
