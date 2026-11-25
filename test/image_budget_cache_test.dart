import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_budget/image_budget.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final cache = binding.imageCache;
  late int previousEntries;
  late int previousBytes;

  setUp(() {
    ImageBudget.reset();
    previousEntries = cache.maximumSize;
    previousBytes = cache.maximumSizeBytes;
    cache.clear();
    cache.clearLiveImages();
    // Non-default app limits demonstrate that configuring is opt-in and
    // resetting restores the app's limits, not Flutter's defaults.
    cache.maximumSize = 8;
    cache.maximumSizeBytes = 4096;
  });

  tearDown(() {
    ImageBudget.reset();
    cache.clear();
    cache.clearLiveImages();
    cache.maximumSize = previousEntries;
    cache.maximumSizeBytes = previousBytes;
  });

  testWidgets('reading stats and resetting before configure are opt-in', (
    tester,
  ) async {
    final stats = ImageBudget.stats;
    ImageBudget.reset();

    expect(stats.maxEntries, 8);
    expect(stats.maxCachedBytes, 4096);
    expect(cache.maximumSize, 8);
    expect(cache.maximumSizeBytes, 4096);
  });

  testWidgets('lower entry and byte limits immediately evict cached images', (
    tester,
  ) async {
    _cacheImage(cache, 'first');
    _cacheImage(cache, 'second');
    _cacheImage(cache, 'third');
    expect(ImageBudget.stats.cachedEntries, 3);
    expect(ImageBudget.stats.cachedBytes, 3 * _imageBytes);
    expect(ImageBudget.stats.pendingImages, 0);

    ImageBudget.configure(maxEntries: 2);
    expect(cache.statusForKey('first').keepAlive, isFalse);
    expect(cache.statusForKey('second').keepAlive, isTrue);
    expect(cache.statusForKey('third').keepAlive, isTrue);
    expect(ImageBudget.stats.cachedEntries, 2);
    expect(ImageBudget.stats.maxCachedBytes, 4096);

    ImageBudget.configure(maxCachedBytes: _imageBytes + 1);
    final stats = ImageBudget.stats;
    expect(cache.statusForKey('second').keepAlive, isFalse);
    expect(cache.statusForKey('third').keepAlive, isTrue);
    expect(stats.cachedEntries, 1);
    expect(stats.cachedBytes, _imageBytes);
    expect(stats.maxEntries, 2);
    expect(stats.maxCachedBytes, _imageBytes + 1);
    expect(stats.isOverBudget, isFalse);
  });

  for (final memoryPressure in [true, false]) {
    testWidgets(
      '${memoryPressure ? 'memory pressure' : 'clear'} drops cached bytes '
      'without evicting live images or changing limits',
      (tester) async {
        ImageBudget.configure(maxEntries: 4, maxCachedBytes: 2048);
        final listener = ImageStreamListener((info, _) => info.dispose());
        final live = _cacheImage(cache, 'live', listener: listener);
        try {
          _cacheImage(cache, 'inactive');
          expect(ImageBudget.stats.liveImages, 1);
          expect(ImageBudget.stats.cachedBytes, 2 * _imageBytes);

          if (memoryPressure) {
            await binding.handleSystemMessage({'type': 'memoryPressure'});
          } else {
            ImageBudget.clear();
          }

          final stats = ImageBudget.stats;
          expect(stats.cachedEntries, 0);
          expect(stats.cachedBytes, 0);
          expect(stats.liveImages, 1);
          expect(stats.maxEntries, 4);
          expect(stats.maxCachedBytes, 2048);
          expect(cache.statusForKey('inactive').untracked, isTrue);
          expect(cache.statusForKey('live').live, isTrue);
          expect(cache.statusForKey('live').keepAlive, isFalse);

          // A newly attached listener still receives the original decoded image.
          ImageInfo? retained;
          final probe = ImageStreamListener((info, _) => retained = info);
          live.addListener(probe);
          try {
            expect(retained?.sizeBytes, _imageBytes);
          } finally {
            live.removeListener(probe);
            retained?.dispose();
          }
        } finally {
          live.removeListener(listener);
        }
        expect(ImageBudget.stats.liveImages, 0);
      },
    );
  }

  testWidgets('reset restores the first saved limits and keeps cached images', (
    tester,
  ) async {
    ImageBudget.configure(maxEntries: 4);
    ImageBudget.configure(maxEntries: 3, maxCachedBytes: 2048);
    _cacheImage(cache, 'retained');

    ImageBudget.reset();
    final stats = ImageBudget.stats;
    expect(stats.maxEntries, 8);
    expect(stats.maxCachedBytes, 4096);
    expect(stats.cachedEntries, 1);
    expect(stats.cachedBytes, _imageBytes);
    expect(cache.statusForKey('retained').keepAlive, isTrue);

    cache.maximumSize = 7;
    ImageBudget.configure(maxEntries: 2);
    ImageBudget.reset();
    expect(cache.maximumSize, 7);
  });
}

const _imageSide = 8;
const _imageBytes = _imageSide * _imageSide * 4;

ImageStreamCompleter _cacheImage(
  ImageCache cache,
  Object key, {
  ImageStreamListener? listener,
}) {
  final completer = _TestImageCompleter();
  cache.putIfAbsent(key, () => completer);
  if (listener != null) {
    completer.addListener(listener);
  }
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xff336699), ui.BlendMode.src);
  final picture = recorder.endRecording();
  try {
    completer.complete(picture.toImageSync(_imageSide, _imageSide));
  } finally {
    picture.dispose();
  }
  return completer;
}

class _TestImageCompleter extends ImageStreamCompleter {
  void complete(ui.Image image) => setImage(ImageInfo(image: image));
}
