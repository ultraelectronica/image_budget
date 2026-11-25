import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_budget/image_budget.dart';

const _sourceSize = Size(4000, 3000);
const _displaySize = Size(400, 300);
const _dpr = 3.0;

typedef _Decode = ({int width, int height, int bytes});

void main() {
  testWidgets('BudgetedImage matches manual sizing and preserves cover pixels',
      (
    tester,
  ) async {
    final encoded = (await tester.runAsync(_encodeFixture))!;
    final original = MemoryImage(encoded);
    const configuration = ImageConfiguration(
      devicePixelRatio: _dpr,
      size: _displaySize,
    );
    final expectedLimits = (
      ImageBudget.stats.maxCachedBytes,
      ImageBudget.stats.maxEntries,
    );

    // Run the baselines first and evict each one so the widget cannot hit a
    // previously resized cache entry instead of exercising its own decode.
    final full = await tester.runAsync(() async {
      try {
        return await _measure(original, configuration);
      } finally {
        await original.evict(configuration: configuration);
      }
    });
    const cacheWidth = 1200;
    const cacheHeight = 900;
    final manualProvider = ResizeImage(
      original,
      width: cacheWidth,
      height: cacheHeight,
    );
    final manual = await tester.runAsync(() async {
      try {
        return await _measure(manualProvider, configuration);
      } finally {
        await manualProvider.evict(configuration: configuration);
      }
    });

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: _dpr),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: BudgetedImage(
              image: original,
              displaySize: _displaySize,
              sourcePixelSize: _sourceSize,
            ),
          ),
        ),
      ),
    );
    try {
      final provider = tester.widget<Image>(find.byType(Image)).image;
      final budgeted = await tester.runAsync(
        () => _measure(provider, configuration),
      );
      await tester.pump();

      expect(full, (width: 4000, height: 3000, bytes: 48000000));
      expect(manual, (width: 1200, height: 900, bytes: 4320000));
      expect(budgeted, manual);
      // Measure the painted image too, rather than just a separate resolution
      // of the same provider.
      final rendered = tester.widget<RawImage>(find.byType(RawImage)).image;
      expect(rendered, isNotNull);
      expect(_decoded(rendered!), budgeted);

      // The same landscape image needs an extra 200 physical pixels of width
      // for a square cover crop, even though only 600 pixels are visible.
      const coverSize = Size(200, 200);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(devicePixelRatio: _dpr),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: BudgetedImage(
                image: original,
                displaySize: coverSize,
                sourcePixelSize: _sourceSize,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
      );
      final coverProvider = tester.widget<Image>(find.byType(Image)).image;
      const coverConfiguration = ImageConfiguration(
        devicePixelRatio: _dpr,
        size: coverSize,
      );
      final cover = await tester.runAsync(
        () => _measure(coverProvider, coverConfiguration),
      );
      await tester.pump();
      final coverImage = tester.widget<RawImage>(find.byType(RawImage));
      expect(coverImage.fit, BoxFit.cover);
      expect(cover, (width: 800, height: 600, bytes: 1920000));
      expect(_decoded(coverImage.image!), cover);

      final biggerThanSource = ResizeImage(
        original,
        width: 5000,
        height: 5000,
        policy: ResizeImagePolicy.fit,
      );
      final unscaled = await tester.runAsync(() async {
        try {
          return await _measure(biggerThanSource, configuration);
        } finally {
          await biggerThanSource.evict(configuration: configuration);
        }
      });
      expect(unscaled, full);

      expect(
        (ImageBudget.stats.maxCachedBytes, ImageBudget.stats.maxEntries),
        expectedLimits,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      ImageBudget.clear();
    }
  });
}

Future<Uint8List> _encodeFixture() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint();
  // Deterministic colored blocks keep the PNG small on disk/in memory while
  // still exercising the real codec at 4000 by 3000 pixels.
  for (var y = 0; y < 12; y++) {
    for (var x = 0; x < 16; x++) {
      paint.color = Color.fromARGB(255, x * 16, y * 21, (x ^ y) * 16);
      canvas.drawRect(Rect.fromLTWH(x * 250, y * 250, 250, 250), paint);
    }
  }
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(
      _sourceSize.width.toInt(),
      _sourceSize.height.toInt(),
    );
    try {
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

Future<_Decode> _measure(
  ImageProvider provider,
  ImageConfiguration configuration,
) async {
  final stream = provider.resolve(configuration);
  final result = Completer<_Decode>();
  final listener = ImageStreamListener(
    (info, _) {
      try {
        if (!result.isCompleted) {
          result.complete(_decoded(info.image));
        }
      } finally {
        info.dispose();
      }
    },
    onError: (error, stackTrace) {
      if (!result.isCompleted) {
        result.completeError(error, stackTrace);
      }
    },
  );
  stream.addListener(listener);
  try {
    return await result.future;
  } finally {
    stream.removeListener(listener);
  }
}

_Decode _decoded(ui.Image image) => (
      width: image.width,
      height: image.height,
      bytes: decodedBytesFor(image),
    );
