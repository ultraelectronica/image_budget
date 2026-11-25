# 0002: JPEG, PNG, variants, and opt-in quantization

- Status: accepted
- Date: 2026-11-25

## Context

The first scope covered decoded sizing and the shared cache but did not say
which codecs to optimize. PNG and JPEG behave differently in Flutter's
engine:

- JPEG can decode at native 1/8 scales. A display-sized request can cut both
  decoded bytes and cold decode time.
- PNG decodes the full source and then resizes. `ResizeImage` cuts retained
  bytes but not cold decode time.

A resize animation also creates a new cache key for every pixel size. The
cache can churn even when each bitmap is small.

## Decision

1. JPEG and PNG are both in scope.
2. `sourceFormat` and `qualityMargin` are explicit options. The default
   margin is `1.25`. PNG ignores the margin. JPEG with a known source size
   snaps up to a native 1/8 scale.
3. Pre-sized PNG variants are supported through `ImageVariant`, with
   automatic smallest-covering selection and a manual `selectedVariant`
   override. The generator lives in `tool/`; generated fixtures are not
   committed.
4. `decodeSizeStep` stays `1` by default. Quantization becomes a default only
   if session evidence shows all three:
   - at least 2× fewer unique decodes over a 100-frame resize animation,
   - at least 10% lower total decode time over two passes,
   - no more than 10% extra retained bytes.
5. No WebP or AVIF in v0.1. The Android/mobile path comes first.
6. Report decoded bytes and measured RSS separately. Never claim total app
   memory savings from decoded-byte numbers.

## Evidence

The session benchmark measured a 100-frame animation, two passes:

| Step | Unique sizes | Decodes | Total ms | Peak MiB |
|---:|---:|---:|---:|---:|
| 1 | 41 | 41 | 2031 | 49.50 |
| 32 | 5 | 5 | 252 | 6.27 |

Step 32 clears the animation gate. The static two-pass feed did not show a
reliable time win, and step 32 rounds small 1× targets up sharply. So the
default stays `1`, and `32` is documented for continuously resizing layouts.

A pre-sized 1200 × 900 PNG decoded 4.12 MiB in 4.9 ms, versus 45.78 MiB and
39.3 ms for the 4000 × 3000 original. That makes variants the PNG time win.

An Android 15 profile run on an `A063` at 60 Hz confirmed the cache side.
During a 1.67 s resize of a 2400 × 1600 PNG, exact targets retained 99.90
MiB, step 32 retained 27.75 MiB, and stock retained 14.65 MiB. Step 32 did
not beat stock frame time at that display size, so the default stays `1`.

## Consequences

- JPEG sizing needs the real source size; without it, native scaling is
  skipped.
- PNG sizing needs `sourceFormat: png` to avoid the default margin.
- Variants cost build tooling and asset size. They are optional.
- `decodeSizeStep` remains opt-in, so default cache keys stay exact.
- Headless numbers are desktop JIT results. Device numbers are one profile
  build on one phone. Neither is a release-mode promise.
- A wider Android device matrix is still open.
