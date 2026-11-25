# Benchmarks

## What's measured

The harness is `benchmark/image_budget_benchmark_test.dart`, a headless
Flutter test. It reports four things:

1. decoded pixel bytes for 19 layout scenarios,
2. cold decode time for the same scenarios,
3. CPU cost of `computeDecodeTarget`,
4. bytes retained by Flutter's `ImageCache` under different limits.

Decoded bytes are `image.width * image.height * 4` from the actual
`ui.Image`. They are not process RSS, GPU memory, or file size.

## Run it

```sh
flutter test benchmark/image_budget_benchmark_test.dart --reporter expanded
```

Results are written to `benchmark/results/latest.json` and
`benchmark/results/latest.md`. That directory is gitignored. See
`benchmark/README.md` for iteration and output options.

The default run does 1 warmup and 5 measured decodes per scenario. It takes
about 13 seconds on the machine below.

## Test environment

| | |
|---|---|
| Date | 2026-11-25 |
| Flutter | 3.50.1 |
| Dart | 3.14.0 |
| OS | Linux 6.12 (Debian 13), x64 |
| CPU | Intel Core i3-8145U, 2.10 GHz, 4 logical CPUs |
| Mode | `flutter test`, JIT, headless |
| Fixtures | synthetic PNGs generated in memory |

## Decode size

The headline case is a 4000 × 3000 source drawn in a 400 × 300 logical card
at 3× DPR:

| Path | Dimensions | Decoded bytes | MiB |
|---|---:|---:|---:|
| Full source | 4000 × 3000 | 48,000,000 | 45.78 |
| `BudgetedImage`, contain | 1200 × 900 | 4,320,000 | 4.12 |
| Reduction | | 43,680,000 | 41.66 |

That is **91.0% less**, or 11.1× smaller.

All 19 scenarios:

| Scenario | Decode bounds | Decoded | MiB | Saved | Decode ms | Full ms |
|---|---|---|---|---:|---:|---:|
| contain, card @3x | 1200 × 900 | 1200 × 900 | 4.12 | 91.0% | 49.75 | 29.84 |
| contain, card @2x | 800 × 600 | 800 × 600 | 1.83 | 96.0% | 40.00 | 29.84 |
| contain, card @1x | 400 × 300 | 400 × 300 | 0.46 | 99.0% | 32.52 | 29.84 |
| contain, thumbnail @2x | 200 × 200 | 200 × 150 | 0.11 | 99.8% | 30.34 | 29.84 |
| cover, square card @3x | 800 × 600 | 800 × 600 | 1.83 | 96.0% | 37.30 | 29.84 |
| cover, square, no source size | 1200 × 1200 | 1200 × 900 | 4.12 | 91.0% | 45.33 | 29.84 |
| cover, square, overscan 3 | 1800 × 1800 | 1800 × 1350 | 9.27 | 79.8% | 65.66 | 29.84 |
| cover, card @3x | 1200 × 900 | 1200 × 900 | 4.12 | 91.0% | 49.16 | 29.84 |
| cover, portrait in card @3x | 1200 × 1600 | 1200 × 1600 | 7.32 | 84.0% | 61.05 | 38.56 |
| cover, portrait, no source size | 2400 × 1800 | 1350 × 1800 | 9.27 | 79.8% | 67.66 | 38.56 |
| fill, card @3x | 1200 × 900 | 1200 × 900 | 4.12 | 91.0% | 48.94 | 29.84 |
| fitWidth, banner @3x | 1200 × 900 | 1200 × 900 | 4.12 | 91.0% | 47.67 | 29.84 |
| fitHeight, tall card @3x | 1600 × 1200 | 1600 × 1200 | 7.32 | 84.0% | 59.54 | 29.84 |
| contain, portrait in card @3x | 1200 × 900 | 675 × 900 | 2.32 | 94.9% | 43.10 | 38.56 |
| fitWidth, portrait @3x | 1200 × 1600 | 1200 × 1600 | 7.32 | 84.0% | 62.44 | 38.56 |
| contain, small source @3x | 1200 × 900 | 800 × 600 | 1.83 | 0.0% | 1.55 | 2.08 |
| fill, small source @3x | 1200 × 900 | 800 × 600 | 1.83 | 0.0% | 1.38 | 2.08 |
| scaleDown, card @3x | none | 4000 × 3000 | 45.78 | 0.0% | 31.89 | 29.84 |
| none, card @3x | none | 4000 × 3000 | 45.78 | 0.0% | 33.19 | 29.84 |

Rows with an 800 × 600 source stay at 800 × 600. `allowUpscaling: false`
means a small source is never enlarged to the decode bounds.

`contain` keeps the source aspect ratio inside the bounds. The portrait
source in a landscape card decodes to 675 × 900, not 1200 × 900.

`scaleDown` and `none` paint at the bitmap's natural size, so the package
does not resize them. They decode at full source size.

### Decode time is not the win

On these PNG fixtures, every resized path decoded slower than the full
source. The large-source scenarios ran at 0.45× to 0.98× the full decode
speed. The PNG path in this engine does not turn a smaller target into less
decode work, and the resize adds time.

That matches what this package claims. It reduces retained decoded bytes. It
does not promise faster decoding. A smaller bitmap can help upload and
raster cost later, but this harness does not measure GPU or frame time. A
format with true scaled decode, such as JPEG, may behave differently. That
was not measured here.

The small-source rows are faster because the codec returns the 800 × 600
source unchanged. The `scaleDown` and `none` rows do the same work as the
baseline.

## Sizing overhead

`computeDecodeTarget` runs once per `BudgetedImage` layout. Each sample is
100,000 calls; the table reports the median of three samples.

| Case | ns per call | µs per 1000 calls |
|---|---:|---:|
| contain, card @3x | 34.5 | 34.5 |
| cover with source size | 46.1 | 46.1 |
| cover without source size | 45.4 | 45.4 |
| cover without source, overscan 3 | 45.9 | 45.9 |
| fill | 39.2 | 39.2 |
| fitWidth with source size | 40.4 | 40.4 |
| fitHeight with source size | 41.7 | 41.7 |
| scaleDown (no resize) | 25.0 | 25.0 |
| contain, fractional DPR | 33.0 | 33.0 |

That is 25 to 46 ns per call, or 25 to 46 µs per 1,000 calls. For comparison,
one frame at 60 Hz is 16,700 µs. The sizing code is not the bottleneck.

## Cache retention

The harness loads 120 unique 400 × 300 images, 54.9 MiB total, through
Flutter's shared `ImageCache`. The stock limits are Flutter's 100 MiB and
1,000 entries.

| Limits | Retained entries | Retained MiB | Evicted | Peak MiB |
|---|---:|---:|---:|---:|
| stock 100 MiB / 1000 entries | 120 / 120 | 54.93 | 0 | 54.93 |
| 32 MiB byte cap | 69 / 120 | 31.59 | 51 | 31.59 |
| 8 MiB byte cap | 17 / 120 | 7.78 | 103 | 7.78 |
| 24 entry cap | 24 / 120 | 10.99 | 96 | 10.99 |

The byte cap settles just below the limit. Eviction is LRU, and the cache
counts its own retained image bytes.

## Method

- Each fixture is a synthetic flat-color PNG built at test start:
  4000 × 3000 landscape, 3000 × 4000 portrait, and 800 × 600 small.
- For each scenario, the harness pumps a real `BudgetedImage`, extracts the
  provider it built, and checks the provider dimensions against
  `computeDecodeTarget`.
- The widget is unmounted before timing, so its first decode does not
  compete with the measured runs.
- Each decode starts with `ImageCache.clear()` and
  `clearLiveImages()`. Every sample is a cold decode, not a cache hit.
- Timing starts before `resolve()` and stops in the image listener. It
  includes codec decode and cache insertion.
- Each scenario reports the median of 5 samples after 1 warmup.
- Full-size decode time is measured once per fixture with the same method.
- `flutter test` runs JIT, so absolute milliseconds are machine-specific.
  Compare ratios on one machine, not across machines or with release builds.

## What this doesn't prove

- Total app RSS. The engine, Skia/Impeller caches, codec scratch space, GPU
  buffers, and the Dart heap can dominate.
- Release or AOT performance.
- Scrolling or frame timings. A smaller cache can cause redecodes and jank.
- Decode behavior for JPEG, WebP, network images, or the web.
- Peak decode memory. A codec can decode the full source and then scale, so
  peak memory can exceed the retained bitmap even when retained bytes drop.
- Budget enforcement under memory pressure from sources other than this
  cache.

## Real-device follow-up

When you have an Android phone handy:

1. Profile a demo with a long image feed.
2. Capture `FrameTiming` p50/p95/p99 and `dumpsys meminfo` RSS for stock
   `Image` vs `BudgetedImage`.
3. Report decoded bytes and total RSS together, plus the device model and
   refresh rate.
