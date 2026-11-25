import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_budget/image_budget.dart';

void main() {
  group('computeDecodeTarget', () {
    test('rounds fractional physical dimensions up', () {
      expect(
        computeDecodeTarget(
          logicalSize: const Size(101, 61),
          devicePixelRatio: 1.25,
          fit: BoxFit.contain,
        ),
        const DecodeTarget(width: 127, height: 77),
      );
    });

    test('cover expands only the axis needed to preserve the crop', () {
      DecodeTarget cover(Size source) => computeDecodeTarget(
            logicalSize: const Size(200, 200),
            devicePixelRatio: 3,
            fit: BoxFit.cover,
            sourcePixelSize: source,
          );

      expect(
        cover(const Size(4000, 3000)),
        const DecodeTarget(width: 800, height: 600),
      );
      expect(
        cover(const Size(3000, 4000)),
        const DecodeTarget(width: 600, height: 800),
      );
    });

    test('cover without dimensions uses a configurable overscan', () {
      DecodeTarget cover(double overscan) => computeDecodeTarget(
            logicalSize: const Size(100, 75),
            devicePixelRatio: 2,
            fit: BoxFit.cover,
            coverOverscan: overscan,
          );

      expect(cover(2), const DecodeTarget(width: 400, height: 300));
      expect(cover(1), const DecodeTarget(width: 200, height: 150));
      expect(() => cover(0.9), throwsArgumentError);
    });

    test('fill requests exact sizing without decode upscaling', () {
      expect(
        computeDecodeTarget(
          logicalSize: const Size(100, 50),
          devicePixelRatio: 2,
          fit: BoxFit.fill,
        ),
        const DecodeTarget(
          width: 200,
          height: 100,
          policy: ResizeImagePolicy.exact,
        ),
      );
    });

    test('paint modes that depend on intrinsic size do not resize', () {
      for (final fit in [BoxFit.none, BoxFit.scaleDown]) {
        final target = computeDecodeTarget(
          logicalSize: const Size(100, 50),
          devicePixelRatio: 2,
          fit: fit,
        );
        expect(target.resizes, isFalse, reason: '$fit');
      }
    });
  });

  testWidgets('uses actual constrained size and updates when DPR changes', (
    tester,
  ) async {
    final source = MemoryImage(Uint8List(0));
    Future<ResizeImage> showAt(double dpr) async {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(devicePixelRatio: dpr),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120, maxHeight: 80),
                child: BudgetedImage(
                  image: source,
                  displaySize: const Size(200, 100),
                  fit: BoxFit.cover,
                  sourcePixelSize: const Size(1000, 1000),
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(BudgetedImage)), const Size(120, 80));
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.fit, BoxFit.cover);
      return image.image as ResizeImage;
    }

    final regular = await showAt(1);
    final same = await showAt(1);
    final fractional = await showAt(1.25);
    expect((regular.width, regular.height), (120, 120));
    expect((fractional.width, fractional.height), (150, 150));
    const config = ImageConfiguration.empty;
    expect(await regular.obtainKey(config), await same.obtainKey(config));
    expect(await regular.obtainKey(config),
        isNot(await fractional.obtainKey(config)));
  });

  testWidgets('collapsed constraints do not resolve an image', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox.shrink(
              child: BudgetedImage(image: AssetImage('never-decoded.png')),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
