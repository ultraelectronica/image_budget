# 0001: Scope the package to decoded images and the image cache

- Status: accepted
- Date: 2026-11-25

## Context

Flutter apps decode full-res photos into small widgets all the time. A decoded
bitmap costs `width × height × 4` bytes, so a 12 MP photo is about 48 MB even
in a tiny card. Flutter gives you `ResizeImage`, `cacheWidth`, and
`cacheHeight`, but you still have to work out the target size, handle
`BoxFit`, and pick a cache budget.

There's a bigger memory problem too: engine baseline, Dart heap, GPU buffers,
platform-view textures, and leaks. A Dart package can't fix all of that.

## Decision

1. v0.1 covers decoded image sizing and Flutter's shared image cache. It
   doesn't claim total app memory savings.
2. Cache configuration is explicit and opt-in. Building a widget never
   changes global cache limits.
3. v0.1 supports `BoxFit.cover`. An optional `sourcePixelSize` gives an exact
   target. Without it, use the documented `coverOverscan` multiplier.
4. Use Flutter's `ResizeImage` and `ImageCache`. No custom codec, isolate, or
   platform channel. That keeps the package pure Dart and testable
   headlessly. Browser decode behavior is unverified.
5. Report decoded bytes, not process RSS. Add a real-device RSS and
   frame-timing follow-up instead of implying the two are the same.

## Consequences

- The package stays small and easy to audit.
- `BoxFit.cover` without `sourcePixelSize` can over-decode or upscale extreme
  aspect ratios. Pass the intrinsic size, or wait for a crop-aware decoder.
- `ImageBudget.configure` changes the shared binding cache, so other widgets
  are affected too. That's why it's opt-in.
- APK size, engine memory, and leaks are out of scope. Those are separate
  projects.
