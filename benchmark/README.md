# Benchmarks

The benchmark is a headless Flutter test. It lives outside `test/`, so a
plain `flutter test` does not run it.

## Run it

```sh
flutter test benchmark/image_budget_benchmark_test.dart --reporter expanded
```

Results are written to `benchmark/results/latest.json` and
`benchmark/results/latest.md`. The directory is gitignored. The command also
prints a short summary.

The default run does 1 warmup and 5 measured decodes per scenario. It tries
to finish in under a minute on a laptop. To change that:

```sh
IMAGE_BUDGET_BENCH_ITERATIONS=10 \
IMAGE_BUDGET_BENCH_WARMUP=2 \
flutter test benchmark/image_budget_benchmark_test.dart --reporter expanded
```

Other environment variables:

- `IMAGE_BUDGET_BENCH_OUT`: output directory. Default `benchmark/results`.
- `IMAGE_BUDGET_BENCH_NO_WRITE=1`: print the summary but write no files.

## What it measures

1. **Decode scenarios.** Pumps a real `BudgetedImage` to get the provider it
   would use, then resolves that provider repeatedly with a cold image cache.
   Records the actual decoded `ui.Image` dimensions, decoded bytes
   (`width * height * 4`), and wall-clock decode time. A full-size decode of
   the same source is the baseline. Scenarios cover every `BoxFit`,
   DPR 1/2/3, `cover` with and without `sourcePixelSize`, custom overscan,
   and sources smaller than the decode bounds.

2. **Sizing overhead.** Calls `computeDecodeTarget` 100,000 times per sample
   and reports nanoseconds per call. This is the CPU cost a
   `BudgetedImage` adds per layout, separate from decoding.

3. **Cache retention.** Loads 120 unique 400 × 300 images through
   `ImageCache` under stock Flutter limits, two byte caps, and an entry cap.
   Reports retained entries, retained bytes, evictions, and peak bytes from
   the cache's own accounting.

## What it does not measure

- Process RSS, GPU memory, codec scratch space, or the Dart heap.
- Release-mode or AOT performance. `flutter test` runs JIT.
- Scrolling, frame timings, or re-decode jank after eviction.
- JPEG, WebP, or network decode behavior. Fixtures are synthetic PNGs.
- Web or mobile platform differences.

See `docs/benchmarks.md` for the current results and the longer caveat list.
