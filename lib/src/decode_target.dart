import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart' show BoxFit, ResizeImagePolicy;

/// The target dimensions and resize policy for one decoded image.
@immutable
class DecodeTarget {
  const DecodeTarget({
    this.width,
    this.height,
    this.policy = ResizeImagePolicy.fit,
    this.allowUpscaling = false,
  });

  /// Target width in physical pixels, or null to skip resizing.
  final int? width;

  /// Target height in physical pixels, or null to skip resizing.
  final int? height;

  /// How [width] and [height] should be interpreted by `ResizeImage`.
  final ResizeImagePolicy policy;

  /// Whether a source smaller than the target may be decoded larger.
  final bool allowUpscaling;

  /// Whether this target actually resizes the source.
  bool get resizes => width != null && height != null;

  @override
  bool operator ==(Object other) {
    return other is DecodeTarget &&
        other.width == width &&
        other.height == height &&
        other.policy == policy &&
        other.allowUpscaling == allowUpscaling;
  }

  @override
  int get hashCode => Object.hash(width, height, policy, allowUpscaling);

  @override
  String toString() {
    return 'DecodeTarget(width: $width, height: $height, '
        'policy: $policy, allowUpscaling: $allowUpscaling)';
  }
}

/// Computes the decode target for a logical display size and [BoxFit].
///
/// [sourcePixelSize] is the intrinsic pixel size of the source image, for
/// example `Size(4000, 3000)`. It is optional, but makes [BoxFit.cover],
/// [BoxFit.fitWidth], and [BoxFit.fitHeight] exact when supplied.
///
/// [coverOverscan] is used only for [BoxFit.cover] without a source size. It
/// expands the target box so common photo aspect ratios can be cropped
/// without upscaling. Values below 1 are rejected.
DecodeTarget computeDecodeTarget({
  required Size logicalSize,
  required double devicePixelRatio,
  required BoxFit fit,
  Size? sourcePixelSize,
  double coverOverscan = 2.0,
}) {
  _checkPositive(logicalSize.width, 'logicalSize.width');
  _checkPositive(logicalSize.height, 'logicalSize.height');
  _checkPositive(devicePixelRatio, 'devicePixelRatio');

  final source = _normalizedSource(sourcePixelSize);
  final boxWidth = math.max(1, (logicalSize.width * devicePixelRatio).ceil());
  final boxHeight = math.max(1, (logicalSize.height * devicePixelRatio).ceil());

  switch (fit) {
    case BoxFit.fill:
      return DecodeTarget(
        width: boxWidth,
        height: boxHeight,
        policy: ResizeImagePolicy.exact,
      );

    case BoxFit.none:
    case BoxFit.scaleDown:
      // These fits use the decoded bitmap's natural size during painting.
      return const DecodeTarget();

    case BoxFit.contain:
      return DecodeTarget(width: boxWidth, height: boxHeight);

    case BoxFit.cover:
      if (source != null) {
        final scale =
            math.max(boxWidth / source.width, boxHeight / source.height);
        return DecodeTarget(
          width: math.max(boxWidth, (source.width * scale).ceil()),
          height: math.max(boxHeight, (source.height * scale).ceil()),
        );
      }
      _checkCoverOverscan(coverOverscan);
      return DecodeTarget(
        width: math.max(1, (boxWidth * coverOverscan).ceil()),
        height: math.max(1, (boxHeight * coverOverscan).ceil()),
      );

    case BoxFit.fitWidth:
      if (source != null) {
        return DecodeTarget(
          width: boxWidth,
          height: math.max(1, (boxWidth * source.height / source.width).ceil()),
        );
      }
      return DecodeTarget(width: boxWidth, height: boxHeight);

    case BoxFit.fitHeight:
      if (source != null) {
        return DecodeTarget(
          width: math.max(1, (boxHeight * source.width / source.height).ceil()),
          height: boxHeight,
        );
      }
      return DecodeTarget(width: boxWidth, height: boxHeight);
  }
}

Size? _normalizedSource(Size? source) {
  if (source == null) {
    return null;
  }
  _checkPositive(source.width, 'sourcePixelSize.width');
  _checkPositive(source.height, 'sourcePixelSize.height');
  return source;
}

void _checkPositive(double value, String name) {
  if (!value.isFinite || value <= 0) {
    throw ArgumentError.value(value, name, 'must be finite and greater than 0');
  }
}

void _checkCoverOverscan(double value) {
  if (!value.isFinite || value < 1) {
    throw ArgumentError.value(
      value,
      'coverOverscan',
      'must be finite and at least 1',
    );
  }
}
