# Benchmarks

## What's measured

Decoded pixel bytes. Not process RSS, not file size.

```
decodedBytes = image.width * image.height * 4
```

That's 4 bytes per pixel, using the actual decoded dimensions. It ignores row
padding, GPU copies, cache bookkeeping, the engine, and the Dart heap.

## Reproduce it

```sh
flutter test test/decoded_bytes_benchmark_test.dart --reporter expanded
```

The test builds a 4000 × 3000 PNG in memory and decodes it three ways: full
size, a manual `ResizeImage`, and `BudgetedImage` in a 400 × 300 logical box
at 3× DPR. The two resized results have to match.

## Result

| Path | Dimensions | Decoded bytes | Decimal MB | MiB |
|---|---:|---:|---:|---:|
| Full source | 4000 × 3000 | 48,000,000 | 48.00 | 45.78 |
| Display-sized | 1200 × 900 | 4,320,000 | 4.32 | 4.12 |
| Reduction | | 43,680,000 | 43.68 | 41.66 |

That's **91% less**, or 11.1× smaller.

Verified headlessly on Linux with Flutter 3.50.1. The same test checks a
200 × 200 `BoxFit.cover` card at 3× DPR. It decodes to 800 × 600 (1.92 MB),
not 600 × 600, because Flutter needs the extra width for the crop. Browser
decode behavior wasn't measured.

## What this doesn't prove

- Total app RSS. The engine, Skia/Impeller caches, and GPU allocations can
  dominate.
- Smoother scrolling. A smaller cache can cause more redecodes. Measure
  frame timings in profile mode on a real device.
- `ImageCache` eviction. The cache tests cover that separately.

## Real-device follow-up

When you have an Android phone handy:

1. Profile a demo with a long image feed.
2. Capture `FrameTiming` p50/p95/p99 and `dumpsys meminfo` RSS for stock
   `Image` vs `BudgetedImage`.
3. Report decoded bytes and total RSS together, plus the device model and
   refresh rate.
