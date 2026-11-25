# 0001: Scope the package to decoded images and the image cache

- Status: accepted
- Date: 2026-11-25

## Context

Flutter apps often decode full-resolution photos into small widgets. The
decoded bitmap costs `width × height × 4` bytes, so a 12 MP photo costs about
48 MB even when displayed in a small card. Flutter provides `ResizeImage`,
`cacheWidth`, and `cacheHeight`, but the developer must compute the target
size, handle `BoxFit`, and decide on a cache budget.

There is also a broader memory problem: engine baseline, Dart heap, GPU
buffers, platform-view textures, and leaks. A package cannot control all of
those from Dart.

## Decision

1. Scope v0.1 to **decoded image sizing** and **Flutter's shared image
   cache**. Do not claim total app memory reduction.
2. Make cache configuration **explicit and opt-in**. Do not silently change
   global cache limits when a widget is constructed.
3. Support `BoxFit.cover` in v0.1. Use an optional `sourcePixelSize` for an
   exact cover target. Fall back to a documented `coverOverscan` multiplier
   when the source size is unknown.
4. Use Flutter's existing `ResizeImage` and `ImageCache` instead of a custom
   codec, isolate, or platform channel. This keeps the package pure Dart,
   testable headlessly, and compatible with all Flutter platforms.
5. Report decoded bytes, not process RSS. Add a real-device RSS and frame
   timing follow-up rather than implying that decoded-byte savings equal
   total memory savings.

## Consequences

- The package is small and easy to audit.
- `BoxFit.cover` without `sourcePixelSize` may over-decode or upscale
  extreme aspect ratios. This is documented and can be fixed by passing the
  intrinsic size or by a future crop-aware decoder.
- The cache limit is global. Apps that call `ImageBudget.configure` affect
  every image in the process, which is why it is opt-in.
- The package cannot reduce APK size, engine memory, or leaks. Those remain
  separate projects.
