# Architecture

## Components

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

`lib/image_budget.dart` exports the public surface. Implementation lives under
`lib/src/`.

## Sizing pipeline

1. Determine the logical display size.
   - Constrain `displaySize` to the parent's actual layout constraints.
   - Otherwise, use the largest finite size from `LayoutBuilder`.
   - If either axis is unbounded and no override is provided, throw a
     descriptive `FlutterError`. Skip the decode for a zero-area box.
2. Convert to physical pixels:
   `boxWidth = ceil(logicalWidth * devicePixelRatio)`,
   `boxHeight = ceil(logicalHeight * devicePixelRatio)`.
3. Build a decode target based on `BoxFit`.
4. Wrap the original provider in `ResizeImage` unless it is already resized
   or the fit mode needs the original bitmap.
5. Render in a fixed-size box with the same `fit`, including while loading.

## Decode target rules

`ResizeImagePolicy.fit` means "preserve aspect ratio and fit inside the
given box." `ResizeImagePolicy.exact` means "decode to exactly these
dimensions."

| Fit | Source size known | Source size unknown |
|---|---|---|
| `contain` | fit inside box | fit inside box |
| `scaleDown` | no resize | no resize |
| `cover` | scale the source rectangle to cover the box | box × `coverOverscan`, then fit |
| `fill` | exact box, clamped per source axis | exact box, clamped per source axis |
| `fitWidth` | box width × rendered height | fit inside box |
| `fitHeight` | rendered width × box height | fit inside box |
| `none` | no resize | no resize |

Cover factor:

```
scale = max(boxWidth / sourceWidth, boxHeight / sourceHeight)
targetWidth  = max(boxWidth,  ceil(sourceWidth  × scale))
targetHeight = max(boxHeight, ceil(sourceHeight × scale))
```

For example, a 4000 × 3000 image covering a 600 × 600 physical box requests
an 800 × 600 decode. Flutter crops the extra width when painting. A smaller
source is not enlarged by the decoder. Integer codec rounding applies.

## Cache policy

`ImageBudget.configure` mutates `PaintingBinding.instance.imageCache`:

- `maximumSizeBytes = maxCachedBytes`
- `maximumSize = maxEntries`

Flutter evicts least-recently-used entries when either limit is exceeded.
The package does not add a second cache and does not intercept memory
pressure. Flutter's painting binding already clears the image cache on
`didHaveMemoryPressure`.

`ImageBudget.stats` reads `ImageCache` fields directly. `cachedBytes` is the
cache's accounting, not process RSS. `liveImages` counts images retained by
widgets or listeners. A live image can survive cache eviction, so the byte
limit does not bound live-image memory.

## Why not measure total app memory?

Total RSS includes the Flutter engine, Dart heap, GPU driver allocations,
platform-view textures, and the host operating system. A package cannot
control all of those from Dart, and changing the image cache is only one
lever. The package therefore makes a narrow, testable promise: display-sized
decoding plus an explicit cache byte limit.

## Failure modes

- **Unbounded constraints**: provide `displaySize` or a bounded parent.
- **Unknown source size with cover**: over-decodes by `coverOverscan`;
  extreme panoramic sources may be upscaled. Pass `sourcePixelSize` for an
  exact target.
- **Frequent size changes**: each distinct decode size creates a cache entry.
  Animated layout changes can churn the cache. A future version will
  quantize sizes.
- **Full-size decodes elsewhere**: `Image.asset(...)` without `cacheWidth`
  or `BudgetedImage` still creates a full-size entry.
- **Cache eviction during scroll**: a smaller cache may re-decode images
  when the user scrolls back, trading memory for CPU and jank.

## Test strategy

- Pure unit tests for `computeDecodeTarget` cover all fit modes, fractional
  DPR, unbounded inputs, and small sources.
- Provider tests resolve `ResizeImage` directly and assert decoded `ui.Image`
  dimensions.
- Widget tests inspect the `Image` widget's provider and fit without relying
  on flaky frame timing.
- Cache tests configure a tiny byte limit, resolve images, and assert
  eviction and restoration.
- A benchmark test decodes the same generated 4000 × 3000 PNG at full size
  and at 1200 × 900, then compares `width * height * 4`.
