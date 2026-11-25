import 'package:flutter/widgets.dart';

import 'decode_target.dart';

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
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.medium,
    this.semanticLabel,
    this.excludeFromSemantics = false,
    this.frameBuilder,
    this.loadingBuilder,
    this.errorBuilder,
  });

  /// The source provider. An existing [ResizeImage] is left unchanged.
  final ImageProvider<Object> image;

  /// The requested logical size before applying the parent's constraints.
  final Size? displaySize;

  /// How the bitmap is painted inside the display box.
  final BoxFit fit;

  /// Intrinsic pixel dimensions, used for their aspect ratio when cropping.
  final Size? sourcePixelSize;

  /// Multiplier for the decode bounds when cover is used without a source size.
  final double coverOverscan;

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

        final target = computeDecodeTarget(
          logicalSize: size,
          devicePixelRatio: dpr,
          fit: fit,
          sourcePixelSize: sourcePixelSize,
          coverOverscan: coverOverscan,
        );
        final provider = target.resizes && image is! ResizeImage
            ? ResizeImage(
                image,
                width: target.width,
                height: target.height,
                policy: target.policy,
                allowUpscaling: target.allowUpscaling,
              )
            : image;
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
}
