# Changelog

## 0.1.0-dev

- Initial package skeleton.
- `BudgetedImage` with display-size and DPR-aware decoding.
- `BoxFit.cover` support with optional `sourcePixelSize`.
- `ImageBudget` cache configuration and statistics.
- `sourceFormat` and `qualityMargin` for codec-aware sizing.
- JPEG native 1/8 scaling with a known source size.
- Optional `decodeSizeStep` quantization. Default stays `1`; step `32`
  helped resize animations but not static feeds.
- `ImageVariant` pre-sized sources with automatic selection and manual
  override.
- `tool/generate_variants.dart` for width-bucketed PNG variants.
- JPEG and PNG decode matrix, pre-sized PNG, static feed, and resize
  animation benchmarks.
- Android profile benchmark in the example app, validated on an Android 15
  phone. Exact PNG resize targets retained 99.90 MiB of cache, step 32 kept
  27.75 MiB, and stock kept 14.65 MiB.
- Headless tests for sizing, cache behavior, and decoded-byte reduction.
- Headless benchmark for 26 decode scenarios, sizing overhead, and cache
  retention.
- Example app, Android scaffold, and documentation.
- App integration guide in `docs/using-in-an-app.md`.
