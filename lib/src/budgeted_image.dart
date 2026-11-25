import 'package:flutter/widgets.dart';

import 'decode_target.dart';
import 'image_source_format.dart';
import 'image_variant.dart';

/// Uses the display box and device pixel ratio to size an image decode.
///
/// Supply [displaySize] or give this widget a parent that bounds both axes.
/// The resulting box stays the same size while the image loads.
class BudgetedImage extends StatelessWidget {
  const BudgetedImage({
    super.key,
    required this.image,
    this.displaySize,
    this.fit = BoxFit.contain,
    this.sourcePixelSize,
    this.coverOverscan = 2.0,
    this.imageVariants,
    this.selectedVariant,
    this.decodeSizeStep = 1,
    this.sourceFormat = ImageSourceFormat.auto,
    this.qualityMargin = 1.25,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.medium,
    this.semanticLabel,
    this.excludeFromSemantics = false,
    this.frameBuilder,
    this.loadingBuilder,
    this.errorBuilder,
  })  : assert(decodeSizeStep > 0),
        assert(qualityMargin >= 1);

  /// The source provider. An existing [ResizeImage] is left unchanged.
  final ImageProvider<Object> image;

  /// The requested logical size before applying the parent's constraints.
  final Size? displaySize;

  /// How the bitmap is painted inside the display box.
  final BoxFit fit;

  /// Intrinsic pixel dimensions, used for their aspect ratio when cropping.
  ///
  /// Ignored when [imageVariants] or [selectedVariant] supplies a size.
  final Size? sourcePixelSize;

  /// Multiplier for the decode bounds when cover is used without a source size.
  final double coverOverscan;

  /// Optional pre-sized sources for this image.
  ///
  /// The smallest variant that covers the decode target is selected. Pass
  /// [selectedVariant] to choose one manually. If none covers, the largest
  /// variant is used. When empty, [image] is used. Variants should share the
  /// same aspect ratio as [image]; sizing uses each variant's own pixel size.
  /// Natural-size fits ([BoxFit.none] and [BoxFit.scaleDown]) keep the largest
  /// variant.
  final List<ImageVariant>? imageVariants;

  /// Forces one pre-sized source instead of automatic selection.
  final ImageVariant? selectedVariant;

  /// Rounds the decode target up to a multiple of this many physical pixels.
  ///
  /// A value of 1 keeps exact sizing. Grouping nearby layout sizes reduces
  /// re-decodes during resize animations. Ignored for JPEG, because native
  /// scales already group sizes and an unknown source size makes quantizing
  /// unsafe.
  final int decodeSizeStep;

  /// Hint for codec-aware sizing.
  ///
  /// JPEG with a known source size snaps to a native 1/8 decode scale. PNG
  /// ignores [qualityMargin]. Auto applies the margin without assuming a
  /// native scale.
  final ImageSourceFormat sourceFormat;

  /// Extra decode headroom to avoid codec rounding below the display target.
  ///
  /// The default of 1.25 is quality-safe. PNG ignores it.
  final double qualityMargin;

  final AlignmentGeometry alignment;
  final FilterQuality filterQuality;
  final String? semanticLabel;
  final bool excludeFromSemantics;
  final ImageFrameBuilder? frameBuilder;
  final ImageLoadingBuilder? loadingBuilder;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final requestedSize = displaySize ?? constraints.biggest;
        if (!requestedSize.isFinite ||
            requestedSize.width < 0 ||
            requestedSize.height < 0) {
          throw FlutterError(
            'BudgetedImage needs a finite, non-negative displaySize or a '
            'parent that bounds both axes. Wrap it in a SizedBox or set '
            'displaySize.',
          );
        }
        final size = constraints.constrain(requestedSize);
        if (size.isEmpty) {
          return SizedBox.fromSize(size: size);
        }

        final variant = _selectVariant(size, dpr);
        final sourceSize = variant?.pixelSize ?? sourcePixelSize;
        final target = computeDecodeTarget(
          logicalSize: size,
          devicePixelRatio: dpr,
          fit: fit,
          sourcePixelSize: sourceSize,
          coverOverscan: coverOverscan,
          qualityMargin: qualityMargin,
          sourceFormat: sourceFormat,
          decodeSizeStep: decodeSizeStep,
        );
        final baseProvider = variant?.image ?? image;
        final provider = target.resizes && baseProvider is! ResizeImage
            ? ResizeImage(
                baseProvider,
                width: target.width,
                height: target.height,
                policy: target.policy,
                allowUpscaling: target.allowUpscaling,
              )
            : baseProvider;
        return SizedBox.fromSize(
          size: size,
          child: Image(
            image: provider,
            width: size.width,
            height: size.height,
            fit: fit,
            alignment: alignment,
            filterQuality: filterQuality,
            semanticLabel: semanticLabel,
            excludeFromSemantics: excludeFromSemantics,
            frameBuilder: frameBuilder,
            loadingBuilder: loadingBuilder,
            errorBuilder: errorBuilder,
          ),
        );
      },
    );
  }

  ImageVariant? _selectVariant(Size size, double devicePixelRatio) {
    final override = selectedVariant;
    if (override != null) {
      _checkVariant(override);
      return override;
    }
    final variants = imageVariants;
    if (variants == null || variants.isEmpty) {
      return null;
    }

    final ordered = [...variants]..sort(
        (a, b) => (a.pixelSize.width * a.pixelSize.height)
            .compareTo(b.pixelSize.width * b.pixelSize.height),
      );
    for (final variant in ordered) {
      _checkVariant(variant);
    }
    if (fit == BoxFit.none || fit == BoxFit.scaleDown) {
      // Natural-size painting has no useful small target. Keep the largest
      // variant available unless the caller forces one.
      return ordered.last;
    }

    final boxWidth =
        (size.width * devicePixelRatio).ceil().clamp(1, 1 << 31).toInt();
    final boxHeight =
        (size.height * devicePixelRatio).ceil().clamp(1, 1 << 31).toInt();
    for (final variant in ordered) {
      final target = computeDecodeTarget(
        logicalSize: size,
        devicePixelRatio: devicePixelRatio,
        fit: fit,
        sourcePixelSize: variant.pixelSize,
        coverOverscan: coverOverscan,
        // Check the display need, not each variant's own native scale.
        qualityMargin:
            sourceFormat == ImageSourceFormat.png ? 1 : qualityMargin,
        decodeSizeStep:
            sourceFormat == ImageSourceFormat.jpeg ? 1 : decodeSizeStep,
      );
      final requiredWidth = target.width ?? boxWidth;
      final requiredHeight = target.height ?? boxHeight;
      if (variant.pixelSize.width >= requiredWidth &&
          variant.pixelSize.height >= requiredHeight) {
        return variant;
      }
    }
    return ordered.last;
  }

  void _checkVariant(ImageVariant variant) {
    final size = variant.pixelSize;
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0 ||
        size.height <= 0) {
      throw ArgumentError.value(
        size,
        'imageVariants',
        'variant pixelSize must be finite and greater than 0',
      );
    }
  }
}
