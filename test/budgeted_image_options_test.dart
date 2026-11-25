import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_budget/image_budget.dart';

void main() {
  testWidgets('applies the quality-safe margin by default', (tester) async {
    final provider = await _show(
      tester,
      displaySize: const Size(100, 75),
      dpr: 2,
      sourcePixelSize: const Size(4000, 3000),
    );

    final resize = provider as ResizeImage;
    expect((resize.width, resize.height), (250, 188));
    expect(resize.policy, ResizeImagePolicy.fit);
    expect(resize.allowUpscaling, isFalse);
  });

  testWidgets('PNG ignores the default margin', (tester) async {
    final provider = await _show(
      tester,
      displaySize: const Size(100, 75),
      dpr: 2,
      sourcePixelSize: const Size(4000, 3000),
      sourceFormat: ImageSourceFormat.png,
    );

    final resize = provider as ResizeImage;
    expect((resize.width, resize.height), (200, 150));
  });

  group('variants', () {
    late ImageVariant small;
    late ImageVariant medium;
    late ImageVariant large;

    setUp(() {
      small = ImageVariant(
        image: MemoryImage(Uint8List.fromList([1])),
        pixelSize: const Size(400, 300),
        label: 'small',
      );
      medium = ImageVariant(
        image: MemoryImage(Uint8List.fromList([2])),
        pixelSize: const Size(800, 600),
        label: 'medium',
      );
      large = ImageVariant(
        image: MemoryImage(Uint8List.fromList([3])),
        pixelSize: const Size(1200, 900),
        label: 'large',
      );
    });

    testWidgets('picks the smallest variant that covers the target', (
      tester,
    ) async {
      final variants = [large, small, medium];
      for (final (dpr, expected) in [
        (1.0, small),
        (2.0, medium),
        (3.0, large),
      ]) {
        final provider = await _show(
          tester,
          displaySize: const Size(400, 300),
          dpr: dpr,
          variants: variants,
          qualityMargin: 1,
        );
        final resize = provider as ResizeImage;
        expect(resize.imageProvider, same(expected.image), reason: 'DPR $dpr');
        expect((resize.width, resize.height), (400 * dpr, 300 * dpr));
      }
    });

    testWidgets('uses cover when choosing a variant', (tester) async {
      final provider = await _show(
        tester,
        displaySize: const Size(200, 200),
        dpr: 2,
        fit: BoxFit.cover,
        variants: [small, medium, large],
        qualityMargin: 1,
      );
      final resize = provider as ResizeImage;
      expect(resize.imageProvider, same(medium.image));
    });

    testWidgets('JPEG variants cover the display target', (tester) async {
      final provider = await _show(
        tester,
        displaySize: const Size(400, 300),
        variants: [small, medium, large],
        sourceFormat: ImageSourceFormat.jpeg,
      );
      final resize = provider as ResizeImage;
      expect(resize.imageProvider, same(medium.image));
      expect((resize.width, resize.height), (500, 375));
    });

    testWidgets('manual selection wins over automatic selection', (
      tester,
    ) async {
      final provider = await _show(
        tester,
        displaySize: const Size(100, 75),
        dpr: 1,
        variants: [small, medium, large],
        selectedVariant: large,
        qualityMargin: 1,
      );
      final resize = provider as ResizeImage;
      expect(resize.imageProvider, same(large.image));
      expect((resize.width, resize.height), (100, 75));
    });

    testWidgets('falls back to the largest variant when none covers', (
      tester,
    ) async {
      final provider = await _show(
        tester,
        displaySize: const Size(1000, 750),
        dpr: 2,
        variants: [small, medium],
        qualityMargin: 1,
      );
      final resize = provider as ResizeImage;
      expect(resize.imageProvider, same(medium.image));
    });

    testWidgets('natural-size fits keep the largest variant', (tester) async {
      for (final fit in [BoxFit.none, BoxFit.scaleDown]) {
        final provider = await _show(
          tester,
          displaySize: const Size(400, 300),
          fit: fit,
          variants: [small, medium, large],
          qualityMargin: 1,
        );
        expect(provider, same(large.image), reason: '$fit');
      }
    });
  });
}

Future<ImageProvider<Object>> _show(
  WidgetTester tester, {
  required Size displaySize,
  double dpr = 1,
  BoxFit fit = BoxFit.contain,
  Size? sourcePixelSize,
  List<ImageVariant>? variants,
  ImageVariant? selectedVariant,
  ImageSourceFormat sourceFormat = ImageSourceFormat.auto,
  double qualityMargin = 1.25,
  int decodeSizeStep = 1,
}) async {
  final fallback = MemoryImage(Uint8List.fromList([0]));
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(devicePixelRatio: dpr),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: displaySize.width,
            height: displaySize.height,
            child: BudgetedImage(
              image: fallback,
              fit: fit,
              sourcePixelSize: sourcePixelSize,
              imageVariants: variants,
              selectedVariant: selectedVariant,
              sourceFormat: sourceFormat,
              qualityMargin: qualityMargin,
              decodeSizeStep: decodeSizeStep,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    ),
  );
  return tester.widget<Image>(find.byType(Image)).image;
}
