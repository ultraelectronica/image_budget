import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart' show BoxFit, ResizeImagePolicy;

import 'image_source_format.dart';

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
///
/// [qualityMargin] adds headroom so a codec that rounds a resize request down
/// still has enough pixels. It is applied for [ImageSourceFormat.auto] and
/// [ImageSourceFormat.jpeg], and ignored for [ImageSourceFormat.png]. Values
/// below 1 are rejected.
///
/// [sourceFormat] selects codec-aware rounding. For JPEG with a known source
/// size, the result is snapped up to a native 1/8 decode scale. For PNG, the
/// exact target is returned. For [ImageSourceFormat.auto], only the quality
/// margin is applied.
///
/// [decodeSizeStep] rounds the final target up to a multiple of this many
/// physical pixels. It is skipped for JPEG sources because native scales
/// already provide a small set of cache-friendly sizes, and an unknown source
/// size makes quantizing unsafe. Values below 1 are rejected.
DecodeTarget computeDecodeTarget({
  required Size logicalSize,
  required double devicePixelRatio,
  required BoxFit fit,
  Size? sourcePixelSize,
  double coverOverscan = 2.0,
  double qualityMargin = 1.0,
  ImageSourceFormat sourceFormat = ImageSourceFormat.auto,
  int decodeSizeStep = 1,
}) {
  _checkPositive(logicalSize.width, 'logicalSize.width');
  _checkPositive(logicalSize.height, 'logicalSize.height');
  _checkPositive(devicePixelRatio, 'devicePixelRatio');
  _checkQualityMargin(qualityMargin);
  _checkDecodeSizeStep(decodeSizeStep);

  final source = _normalizedSource(sourcePixelSize);
  final boxWidth = math.max(1, (logicalSize.width * devicePixelRatio).ceil());
  final boxHeight = math.max(1, (logicalSize.height * devicePixelRatio).ceil());

  final target = switch (fit) {
    BoxFit.fill => DecodeTarget(
        width: boxWidth,
        height: boxHeight,
        policy: ResizeImagePolicy.exact,
      ),
    BoxFit.none ||
    BoxFit.scaleDown =>
      // These fits use the decoded bitmap's natural size during painting.
      const DecodeTarget(),
    BoxFit.contain => DecodeTarget(width: boxWidth, height: boxHeight),
    BoxFit.cover => _coverTarget(
        boxWidth: boxWidth,
        boxHeight: boxHeight,
        source: source,
        coverOverscan: coverOverscan,
      ),
    BoxFit.fitWidth => _fitWidthTarget(
        boxWidth: boxWidth,
        source: source,
        boxHeight: boxHeight,
      ),
    BoxFit.fitHeight => _fitHeightTarget(
        boxHeight: boxHeight,
        source: source,
        boxWidth: boxWidth,
      ),
  };

  return _refineTarget(
    target,
    source: source,
    sourceFormat: sourceFormat,
    qualityMargin: qualityMargin,
    decodeSizeStep: decodeSizeStep,
  );
}

DecodeTarget _coverTarget({
  required int boxWidth,
  required int boxHeight,
  required Size? source,
  required double coverOverscan,
}) {
  if (source == null) {
    _checkCoverOverscan(coverOverscan);
    return DecodeTarget(
      width: math.max(1, (boxWidth * coverOverscan).ceil()),
      height: math.max(1, (boxHeight * coverOverscan).ceil()),
    );
  }
  final scale = math.max(boxWidth / source.width, boxHeight / source.height);
  return DecodeTarget(
    width: math.max(boxWidth, (source.width * scale).ceil()),
    height: math.max(boxHeight, (source.height * scale).ceil()),
  );
}

DecodeTarget _fitWidthTarget({
  required int boxWidth,
  required Size? source,
  required int boxHeight,
}) {
  if (source == null) {
    return DecodeTarget(width: boxWidth, height: boxHeight);
  }
  return DecodeTarget(
    width: boxWidth,
    height: math.max(1, (boxWidth * source.height / source.width).ceil()),
  );
}

DecodeTarget _fitHeightTarget({
  required int boxHeight,
  required Size? source,
  required int boxWidth,
}) {
  if (source == null) {
    return DecodeTarget(width: boxWidth, height: boxHeight);
  }
  return DecodeTarget(
    width: math.max(1, (boxHeight * source.width / source.height).ceil()),
    height: boxHeight,
  );
}

DecodeTarget _refineTarget(
  DecodeTarget target, {
  required Size? source,
  required ImageSourceFormat sourceFormat,
  required double qualityMargin,
  required int decodeSizeStep,
}) {
  if (!target.resizes) {
    return target;
  }

  var width = target.width!;
  var height = target.height!;

  // PNG never rounds a resize request down, so extra pixels only cost memory.
  if (sourceFormat != ImageSourceFormat.png && qualityMargin > 1) {
    width = (width * qualityMargin).ceil();
    height = (height * qualityMargin).ceil();
  }

  if (sourceFormat == ImageSourceFormat.jpeg) {
    if (source != null) {
      final native = _jpegNativeScale(width, height, source);
      width = native.width;
      height = native.height;
    }
    // Without a source size, quantizing could cross a native scale boundary
    // and silently overdecode. Leave the margin-adjusted target alone.
  } else if (decodeSizeStep > 1) {
    width = _quantizeUp(width, decodeSizeStep);
    height = _quantizeUp(height, decodeSizeStep);
  }

  return DecodeTarget(
    width: math.max(1, width),
    height: math.max(1, height),
    policy: target.policy,
    allowUpscaling: target.allowUpscaling,
  );
}

({int width, int height}) _jpegNativeScale(
  int targetWidth,
  int targetHeight,
  Size source,
) {
  var eighths = 1;
  while (eighths < 8) {
    final width = (source.width * eighths / 8).ceil();
    final height = (source.height * eighths / 8).ceil();
    if (width >= targetWidth && height >= targetHeight) {
      break;
    }
    eighths++;
  }
  return (
    width: math.max(1, (source.width * eighths / 8).ceil()),
    height: math.max(1, (source.height * eighths / 8).ceil()),
  );
}

int _quantizeUp(int value, int step) {
  if (step <= 1) {
    return value;
  }
  return ((value + step - 1) ~/ step) * step;
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

void _checkQualityMargin(double value) {
  if (!value.isFinite || value < 1) {
    throw ArgumentError.value(
      value,
      'qualityMargin',
      'must be finite and at least 1',
    );
  }
}

void _checkDecodeSizeStep(int value) {
  if (value < 1) {
    throw ArgumentError.value(
      value,
      'decodeSizeStep',
      'must be at least 1',
    );
  }
}
