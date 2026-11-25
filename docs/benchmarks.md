# Benchmarks

## What's measured

Two headless Flutter tests:

- `benchmark/image_budget_benchmark_test.dart`: cold decodes for 26 layout
  scenarios, JPEG and PNG, sizing overhead, and cache retention.
- `benchmark/session_benchmark_test.dart`: pre-sized PNG, a two-pass static
  feed, and a 100-frame resize animation.

Decoded bytes are `image.width * image.height * 4` from the actual
`ui.Image`. They are not process RSS, GPU memory, or file size. Timing is
report-only; counts, dimensions, and bytes are asserted.

## Run them

```sh
flutter test benchmark/image_budget_benchmark_test.dart --reporter expanded
flutter test benchmark/session_benchmark_test.dart --reporter expanded
```

The first writes `benchmark/results/latest.json` and `latest.md`. The second
writes `session.json` and `session.md`. That directory is gitignored.

The default cold-decode run does 1 warmup and 5 measured decodes per
scenario. The session run does 24 images for the static feed and 100 frames
per animation pass.

## Test environment

| | |
|---|---|
| Date | 2026-11-25 |
| Flutter | 3.50.1 |
| Dart | 3.14.0 |
| OS | Linux 6.12 (Debian 13), x64 |
| CPU | Intel Core i3-8145U, 2.10 GHz, 4 logical CPUs |
| Mode | `flutter test`, JIT, headless |
| Fixtures | synthetic PNGs, generated JPEGs cached under `benchmark/.cache/` |

## Fixtures

| Fixture | Source pixels | Format | Encoded bytes | Decoded bytes | Full decode ms |
|---|---|---:|---:|---:|---:|
| landscape | 4000 × 3000 | PNG | 8,891,251 | 48,000,000 | 105.2 |
| portrait | 3000 × 4000 | PNG | 8,852,407 | 48,000,000 | 106.8 |
| small | 800 × 600 | PNG | 639,480 | 1,920,000 | 8.9 |
| landscape-jpeg | 4000 × 3000 | JPEG | 3,169,729 | 48,000,000 | 154.4 |
| portrait-jpeg | 3000 × 4000 | JPEG | 3,106,433 | 48,000,000 | 167.3 |

The JPEGs are generated once and cached under `benchmark/.cache/`.

## Cold decodes

A 4000 × 3000 source drawn in a 400 × 300 logical card at 3× DPR:

| Path | Decoded | MiB | Saved | Decode ms | Full ms | Speed |
|---|---:|---:|---:|---:|---:|---:|
| JPEG, `sourceFormat: jpeg` | 1500 × 1125 | 6.44 | 85.9% | 61.3 | 154.4 | 2.52× |
| JPEG, margin 1 | 1500 × 1125 | 6.44 | 85.9% | 61.8 | 154.4 | 2.50× |
| JPEG, cover | 1500 × 1125 | 6.44 | 85.9% | 66.4 | 154.4 | 2.33× |
| PNG, exact | 1200 × 900 | 4.12 | 91.0% | 133.5 | 105.3 | 0.79× |
| PNG, step 32 | 1216 × 912 | 4.23 | 90.8% | 125.8 | 105.3 | 0.84× |
| PNG, `auto` margin 1.25 | 1500 × 1125 | 6.44 | 85.9% | 127.7 | 105.3 | 0.82× |

The JPEG path cuts both decoded bytes and cold decode time. It snaps to the
next native 1/8 source scale: 1500 × 1125 is 3/8 of 4000 × 3000, and the
codec decodes that directly.

The PNG path cuts decoded bytes. It does not cut cold decode time in this
harness: the codec decodes the full PNG, then `ResizeImage` resizes it. A
pre-sized PNG variant is the time win.

The `auto` row shows why PNG sources should pass `sourceFormat: png`. Without
the hint, the default 1.25 quality margin asks for 1500 × 1125 instead of
1200 × 900, and decoded bytes grow by 56%.

All 26 scenarios are in the generated `latest.md`. Other fits (`fill`,
`fitWidth`, `fitHeight`), DPR 1/2/3, cover overscan, and sources smaller
than the decode bounds are covered there.

## Pre-sized PNG

The session benchmark compares a 4000 × 3000 PNG with a 1200 × 900 PNG. Both
are decoded directly, without a `ResizeImage` wrapper.

| Source | Decoded | MiB | Decode ms |
|---|---:|---:|---:|
| Original 4000 × 3000 | 4000 × 3000 | 45.78 | 39.3 |
| Pre-sized 1200 × 900 | 1200 × 900 | 4.12 | 4.9 |

This is the PNG path that wins on both decoded bytes and decode time. The
tradeoff is build tooling: `tool/generate_variants.dart` produces the
smaller files.

## Static feed

24 unique images, 200 × 150 logical at 3×, 64 MiB cache cap, two passes:

| Mode | Decodes | Cache hits | Total ms | Retained MiB | Peak MiB |
|---|---:|---:|---:|---:|---:|
| stock | 48 | 0 | 2711 | 45.78 | 45.78 |
| exact | 24 | 24 | 1322 | 24.72 | 24.72 |
| step 32 | 24 | 24 | 1313 | 25.38 | 25.38 |

Full-size images do not fit under the cap, so every pass re-decodes. The
display-sized entries fit, so the second pass is all cache hits. Step 32
targets are 2.7% larger; static timing did not show a reliable difference
between exact and step 32.

## Resize animation

100 frames, two passes, one source image. The display width varies from 200
to 230 logical pixels, the height from 150 to 172.

| Step | Unique sizes | Decodes | Cache hits | Total ms | Retained MiB | Peak MiB |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 41 | 41 | 159 | 2031 | 49.50 | 49.50 |
| 32 | 5 | 5 | 195 | 252 | 6.27 | 6.27 |
| 64 | 3 | 3 | 197 | 157 | 3.92 | 3.92 |

Step 32 meets the animation gate: at least 2× fewer unique sizes and
decodes, at least 10% lower total time, and no more than 10% extra retained
bytes. Step 64 is also better on this animation.

The default stays `decodeSizeStep: 1`. Step 32 rounds small 1× targets up
sharply, and the static feed did not show a reliable win. Use 32 for layouts
that resize continuously.

## Cache retention

120 unique 400 × 300 images, 54.9 MiB total, through Flutter's shared
`ImageCache`:

| Limits | Retained entries | Retained MiB | Evicted | Peak MiB |
|---|---:|---:|---:|---:|
| stock 100 MiB / 1000 entries | 120 / 120 | 54.93 | 0 | 54.93 |
| 32 MiB byte cap | 69 / 120 | 31.59 | 51 | 31.59 |
| 8 MiB byte cap | 17 / 120 | 7.78 | 103 | 7.78 |
| 24 entry cap | 24 / 120 | 10.99 | 96 | 10.99 |

The byte cap settles just below the limit. Eviction is LRU, and the cache
counts its own retained image bytes, not RSS.

## Sizing overhead

`computeDecodeTarget` runs once per `BudgetedImage` layout. One call is tens
of nanoseconds. See `latest.md` for the table. The decode is the cost, not
the arithmetic.

## Method

- `image_budget_benchmark_test.dart` pumps a real `BudgetedImage`, extracts
  the provider it built, and checks the provider dimensions against
  `computeDecodeTarget`.
- The widget is unmounted before timing, so its first decode does not
  compete with the measured runs.
- Each cold decode starts with `ImageCache.clear()` and
  `clearLiveImages()`.
- Timing starts before `resolve()` and stops in the image listener. It
  includes codec decode and cache insertion.
- Each scenario reports the median of 5 samples after 1 warmup.
- `session_benchmark_test.dart` resolves providers directly, counts
  synchronous cache hits, and reads `ImageCache.currentSizeBytes`.
- `flutter test` runs JIT, so absolute milliseconds are machine-specific.
  Compare ratios on one machine, not across machines or with release builds.

## What this doesn't prove

- Total app RSS. The engine, Skia/Impeller caches, codec scratch space, GPU
  buffers, and the Dart heap can dominate.
- Release or AOT performance.
- GPU upload or raster cost.
- Peak decode memory. A codec can decode the full source and then scale.
- Real photo content. The fixtures are synthetic.
- Scrolling, live images, or eviction under a real feed's working set.
- Web, iOS, or a second Android device.

## Android profile run

The example has a 1.67 s resize benchmark. Run it in profile mode:

```sh
cd example
flutter run --profile --dart-define=IMAGE_BUDGET_BENCH=true
```

It prints one `IMAGE_BUDGET_BENCH` line per mode with build/raster averages,
p90 total frame time, jank count, and cache bytes. A warmup pass runs before
the measured modes, and the image cache is cleared at the start of each mode.

Measured on an `A063` (`Spacewar`, Qualcomm) running Android 15 (SDK 35).
The display is 1080 × 2400 and supports 60, 90, and 120 Hz. The app reports
DPR 2.344. The run below locked the display to 60 Hz with
`settings put system peak_refresh_rate 60` and a screen off/on cycle, then
restored the setting. Jank means a frame missed the 16.7 ms budget.

Source images are a 2400 × 1600 PNG and JPEG. A 16:9 card animates from
320 to 520 logical pixels wide, or 750 to 1219 device pixels, over 1.67 s.
Two runs produced the same cache bytes and 126 frames per mode:

| Mode | Build ms | Raster ms | p90 ms | Jank | Retained MiB | Entries |
|---|---:|---:|---:|---:|---:|---:|
| stock PNG | 2.17–2.24 | 2.80–2.91 | 8.52–8.79 | 0 | 14.65 | 1 |
| PNG, exact | 1.57–1.64 | 4.42–4.52 | 9.81–9.96 | 0 | 99.90 | 45 |
| PNG, step 32 | 1.79 | 4.30–4.95 | 10.44–11.03 | 1–2 | 27.75 | 13 |
| stock JPEG | 2.00–2.10 | 3.58–3.77 | 8.88–9.22 | 0 | 14.65 | 1 |
| budgeted JPEG | 2.29–2.32 | 4.13–4.21 | 9.96–10.07 | 0 | 9.38 | 2 |

No mode showed sustained jank: stock and exact had none, and step 32 missed
one or two frames. The differences are raster averages and cache retention,
not a broken feed.

Exact PNG resizing is the worst case on this device. It retains 45 decoded
bitmaps at the end and fills 99.90 MiB of the 100 MiB cache, versus 14.65
MiB for one full-size PNG. Step 32 cuts that to 27.75 MiB and 13 entries, a 72%
reduction, but it is still about twice the stock bytes and is not faster
than stock at this display size. The GPU downscale in stock mode is cheaper
than decoding a new size every frame. This is why `decodeSizeStep` remains
`1` by default and `32` is only for continuously resizing layouts.

Budgeted JPEG retains 9.38 MiB, 36% less than the 14.65 MiB stock JPEG, but
its raster average is higher. The byte win can still matter for cache
pressure, but this run does not show a frame-time win.

An unlocked 120 Hz run showed more missed 120 Hz deadlines, and the phone
switched between 60 and 120 Hz during repeated runs. The 60 Hz numbers are
the repeatable set. Treat all frame timings as diagnostics, not a
release-mode promise. These numbers are cache bytes, not process RSS.
