/// Source format hint for decode planning.
enum ImageSourceFormat {
  /// Unknown format. The quality margin is applied, but native codec scales
  /// are not assumed.
  auto,

  /// JPEG. Skia can decode at 1/8 through 8/8 scales, so [BudgetedImage] can
  /// ask for a native scale that still covers the display target.
  jpeg,

  /// PNG. The codec always decodes the full source, so the quality margin is
  /// ignored and the exact target is requested.
  png,
}
