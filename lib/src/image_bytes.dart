import 'dart:ui' as ui;

/// Raw RGBA bytes used by a decoded [ui.Image].
///
/// This is `width * height * 4`. It approximates the pixel buffer held by
/// Flutter and intentionally excludes row padding, GPU copies, cache
/// bookkeeping, the engine, and the Dart heap.
int decodedBytesFor(ui.Image image) {
  return image.width * image.height * 4;
}
