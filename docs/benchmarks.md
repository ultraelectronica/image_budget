# Benchmarks

## What is measured

The benchmark measures **decoded pixel bytes**, not process RSS and not file
size:

```
decodedBytes = image.width * image.height * 4
```

This is a four-byte-per-pixel estimate based on actual decoded dimensions.
It excludes row padding, GPU copies, cache bookkeeping, the Flutter engine,
and the Dart heap.

## Reproduction

```sh
flutter test test/decoded_bytes_benchmark_test.dart --reporter expanded
```

The test generates a 4000 × 3000 PNG in memory. It compares the full decode,
a manual `ResizeImage`, and the image rendered by `BudgetedImage` in a
400 × 300 logical box at 3× DPR. The two resized results must agree.

## Verified result

| Path | Dimensions | Decoded bytes | Decimal MB | MiB |
|---|---:|---:|---:|---:|
| Full source | 4000 × 3000 | 48,000,000 | 48.00 | 45.78 |
| Display-sized | 1200 × 900 | 4,320,000 | 4.32 | 4.12 |
| Reduction | | 43,680,000 | 43.68 | 41.66 |

Reduction: **91%** (11.1× smaller).

Verified headlessly on Linux with Flutter 3.50.1. The test also verified
that a 200 × 200 logical `BoxFit.cover` card at 3× DPR decodes the same
fixture to 800 × 600 (1.92 MB), not 600 × 600. Flutter needs the extra width
for the paint-time crop. Browser decode behavior was not measured.

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
