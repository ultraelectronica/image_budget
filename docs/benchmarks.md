# Benchmarks

## What is measured

The benchmark measures **decoded pixel bytes**, not process RSS and not file
size:

```
decodedBytes = image.width * image.height * 4
```

This is the raw RGBA bitmap that Flutter holds for a decoded image. It
excludes row padding, GPU copies, cache bookkeeping, the Flutter engine, and
Dart heap. Those are real costs too, but they are outside this package's
scope.

## Reproduction

```sh
flutter test test/decoded_bytes_benchmark_test.dart --reporter expanded
```

The test generates a 4000 × 3000 PNG in memory, decodes it once at full size,
then decodes it again through `ResizeImage` at 1200 × 900, which is a
400 × 300 logical box at 3× DPR. It disposes each image before measuring the
next one.

## Expected result

| Path | Dimensions | Decoded bytes | Decimal MB | MiB |
|---|---:|---:|---:|---:|
| Full source | 4000 × 3000 | 48,000,000 | 48.00 | 45.78 |
| Display-sized | 1200 × 900 | 4,320,000 | 4.32 | 4.12 |
| Reduction | | 43,680,000 | 43.68 | 41.66 |

Reduction: **91%** (11.1× smaller).

These numbers are deterministic on any platform because they are pixel
counts, not timings. The test fails if the decoded dimensions do not match.

## What this does not prove

- It does not prove a lower total app RSS. Flutter's engine, Skia/Impeller
  caches, and GPU allocations dominate some workloads.
- It does not prove smoother scrolling. A smaller cache can cause more
  redecodes. Measure frame timings in profile mode on a physical device.
- It does not measure `ImageCache` eviction. The cache tests cover that
  separately.

## Real-device follow-up

When a physical Android device is available:

1. Build a profile-mode demo with a long image feed.
2. Capture `FrameTiming` p50/p95/p99 and `dumpsys meminfo` RSS for stock
   `Image` versus `BudgetedImage`.
3. Report both decoded bytes and total RSS, with the device model and
   display refresh rate.
