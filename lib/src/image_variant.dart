import 'dart:ui' show Size;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart' show ImageProvider;

/// One pre-sized source for [BudgetedImage] to choose from.
///
/// Generate variants with `dart run tool/generate_variants.dart` and pass the
/// resulting providers with their intrinsic pixel sizes.
@immutable
class ImageVariant {
  const ImageVariant({
    required this.image,
    required this.pixelSize,
    this.label,
  });

  /// The provider for this variant.
  final ImageProvider<Object> image;

  /// Intrinsic pixel dimensions of [image].
  final Size pixelSize;

  /// Optional label for debugging and tooling.
  final String? label;

  @override
  String toString() {
    final size = '${pixelSize.width.toInt()}x${pixelSize.height.toInt()}';
    final name = label == null ? '' : ' $label';
    return 'ImageVariant($size$name)';
  }
}
