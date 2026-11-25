# Benchmarks

The benchmarks are headless Flutter tests. They live outside `test/`, so a
plain `flutter test` does not run them.

## Run them

```sh
flutter test benchmark/image_budget_benchmark_test.dart --reporter expanded
flutter test benchmark/session_benchmark_test.dart --reporter expanded
```

The first writes `benchmark/results/latest.json` and `latest.md`. The second
writes `session.json` and `session.md`. The directory is gitignored.

The cold-decode run does 1 warmup and 5 measured decodes per scenario. To
change that:

```sh
IMAGE_BUDGET_BENCH_ITERATIONS=10 \
IMAGE_BUDGET_BENCH_WARMUP=2 \
flutter test benchmark/image_budget_benchmark_test.dart --reporter expanded
```

Other environment variables:

- `IMAGE_BUDGET_BENCH_OUT`: output directory. Default `benchmark/results`.
- `IMAGE_BUDGET_BENCH_NO_WRITE=1`: print the summary but write no files.

## What the cold benchmark measures

1. **Decode scenarios.** Pumps a real `BudgetedImage` to get the provider it
   would use, then resolves that provider repeatedly with a cold image cache.
   Records the actual decoded `ui.Image` dimensions, decoded bytes
   (`width * height * 4`), and wall-clock decode time. A full-size decode of
   the same source is the baseline. Scenarios cover every `BoxFit`,
   DPR 1/2/3, `cover` with and without `sourcePixelSize`, custom overscan,
   sources smaller than the decode bounds, JPEG native scaling, quality
   margins, and decode-size steps.

2. **Sizing overhead.** Calls `computeDecodeTarget` 100,000 times per sample
   and reports nanoseconds per call. This is the CPU cost a
   `BudgetedImage` adds per layout, separate from decoding.

3. **Cache retention.** Loads 120 unique 400 × 300 images through
   `ImageCache` under stock Flutter limits, two byte caps, and an entry cap.
   Reports retained entries, retained bytes, evictions, and peak bytes from
   the cache's own accounting.

## What the session benchmark measures

1. **Pre-sized PNG.** Decodes a 4000 × 3000 PNG and a 1200 × 900 PNG
   directly, with no `ResizeImage`.
2. **Static feed.** Resolves 24 unique images twice under a 64 MiB cap.
   Compares stock, exact, and step-32 targets.
3. **Resize animation.** Resolves 100 changing display sizes twice. Compares
   step 1, 32, and 64 on unique sizes, decodes, cache hits, total time,
   retained bytes, and peak bytes.

## What they do not measure

- Process RSS, GPU memory, codec scratch space, or the Dart heap.
- Release-mode or AOT performance. `flutter test` runs JIT.
- GPU upload or raster cost.
- Real photo content. Fixtures are synthetic.
- Web, iOS, or a second Android device.

See `docs/benchmarks.md` for current results, the decision on quantization,
and the longer caveat list.
