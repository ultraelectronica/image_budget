// Headless benchmark for image_budget.
//
// Run from the package root:
//
//   flutter test benchmark/image_budget_benchmark_test.dart --reporter expanded
//
// The file lives outside test/ so a plain `flutter test` does not run it.
// It measures decoded pixel bytes, decode latency, sizing overhead, and how
// the ImageCache limits retain bytes. It does not measure process RSS.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_budget/image_budget.dart';

const _defaultIterations = 5;
const _sizingIterations = 100000;
const _cacheImages = 120;
const _cacheImageWidth = 400;
const _cacheImageHeight = 300;

const _landscape = Size(4000, 3000);
const _portrait = Size(3000, 4000);
const _small = Size(800, 600);

void main() {
  testWidgets(
    'image_budget benchmark',
    (tester) async {
      final iterations =
          _envInt('IMAGE_BUDGET_BENCH_ITERATIONS', _defaultIterations);
      final warmup = _envInt('IMAGE_BUDGET_BENCH_WARMUP', 1);
      final startedAt = DateTime.now().toUtc();

      // Start from Flutter's stock cache limits so earlier tests in the same
      // process cannot influence retention measurements.
      final cache = PaintingBinding.instance.imageCache;
      ImageBudget.reset();
      cache.maximumSize = 1000;
      cache.maximumSizeBytes = 100 * 1024 * 1024;
      cache.clear();
      cache.clearLiveImages();

      final fixtures = (await tester.runAsync(_createFixtures))!;

      final fullResults = (await tester.runAsync(() async {
        final results = <String, _FullResult>{};
        for (final fixture in fixtures) {
          results[fixture.name] = await _measureFull(fixture, iterations);
        }
        return results;
      }))!;

      final scenarioResults = <_ScenarioResult>[];
      for (final scenario in _scenarios) {
        final fixture = fixtures.firstWhere((f) => f.name == scenario.fixture);
        final provider = await _extractProvider(tester, fixture, scenario);
        final full = fullResults[fixture.name]!;
        final result = (await tester.runAsync(
          () => _measureScenario(
              scenario, fixture, provider, full, iterations, warmup),
        ))!;
        scenarioResults.add(result);
      }

      final sizingResults = [
        for (final sizingCase in _sizingCases) _benchSizing(sizingCase),
      ];

      final cacheResults = <_CacheResult>[
        _runCache(
          label: 'stock 100 MiB / 1000 entries',
        ),
        _runCache(
          label: '32 MiB byte cap',
          maxCachedBytes: 32 << 20,
        ),
        _runCache(
          label: '8 MiB byte cap',
          maxCachedBytes: 8 << 20,
        ),
        _runCache(
          label: '24 entry cap',
          maxEntries: 24,
        ),
      ];

      final report = _Report(
        generatedAt: startedAt.toIso8601String(),
        environment: _environment(iterations, warmup),
        fixtures: fixtures,
        fullResults: fullResults,
        scenarios: scenarioResults,
        sizing: sizingResults,
        cache: cacheResults,
      );

      final markdown = _renderMarkdown(report);
      _printSummary(report);

      if (!_envFlag('IMAGE_BUDGET_BENCH_NO_WRITE')) {
        final outputDirectory = Directory(
          Platform.environment['IMAGE_BUDGET_BENCH_OUT'] ?? 'benchmark/results',
        );
        outputDirectory.createSync(recursive: true);
        final jsonFile = File('${outputDirectory.path}/latest.json');
        final markdownFile = File('${outputDirectory.path}/latest.md');
        jsonFile.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(_reportToJson(report)),
        );
        markdownFile.writeAsStringSync(markdown);
        stdout.writeln();
        stdout.writeln('Wrote ${jsonFile.path}');
        stdout.writeln('Wrote ${markdownFile.path}');
      }

      // Keep the benchmark honest: results are also assertions.
      for (final result in scenarioResults) {
        final target = result.target;
        final decode = result.decode;
        expect(decode.bytes, greaterThan(0), reason: result.scenario.name);
        expect(decode.width, greaterThan(0), reason: result.scenario.name);
        expect(decode.height, greaterThan(0), reason: result.scenario.name);
        if (target.resizes) {
          final maxWidth = math.min(target.width!, result.full.decode.width);
          final maxHeight = math.min(target.height!, result.full.decode.height);
          expect(decode.width, lessThanOrEqualTo(maxWidth + 1),
              reason: result.scenario.name);
          expect(decode.height, lessThanOrEqualTo(maxHeight + 1),
              reason: result.scenario.name);
        } else {
          expect(
            (decode.width, decode.height),
            (result.full.decode.width, result.full.decode.height),
            reason: result.scenario.name,
          );
          expect(decode.bytes, result.full.decode.bytes,
              reason: result.scenario.name);
        }
      }
      for (final result in scenarioResults) {
        expect(
          result.decode.bytes,
          lessThanOrEqualTo(result.full.decode.bytes),
          reason: result.scenario.name,
        );
      }
      final stockCache = cacheResults.first;
      expect(stockCache.retainedEntries, _cacheImages);
      for (final result in cacheResults.skip(1)) {
        expect(result.retainedBytes, lessThanOrEqualTo(result.maxBytes));
        expect(result.retainedEntries, lessThanOrEqualTo(result.maxEntries));
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

int _envInt(String name, int fallback) {
  final value = int.tryParse(Platform.environment[name] ?? '');
  return value == null || value <= 0 ? fallback : value;
}

bool _envFlag(String name) {
  final value = Platform.environment[name];
  return value == '1' || value == 'true';
}

Future<List<_Fixture>> _createFixtures() async {
  return [
    _Fixture(
      name: 'landscape',
      format: _FixtureFormat.png,
      size: _landscape,
      encoded: await _encodePng(_landscape, 0),
    ),
    _Fixture(
      name: 'portrait',
      format: _FixtureFormat.png,
      size: _portrait,
      encoded: await _encodePng(_portrait, 1),
    ),
    _Fixture(
      name: 'small',
      format: _FixtureFormat.png,
      size: _small,
      encoded: await _encodePng(_small, 2),
    ),
    _Fixture(
      name: 'landscape-jpeg',
      format: _FixtureFormat.jpeg,
      size: _landscape,
      encoded: await _encodeJpeg(_landscape, 0),
    ),
    _Fixture(
      name: 'portrait-jpeg',
      format: _FixtureFormat.jpeg,
      size: _portrait,
      encoded: await _encodeJpeg(_portrait, 1),
    ),
  ];
}

Future<Uint8List> _encodePng(Size size, int seed) async {
  final width = size.width.toInt();
  final height = size.height.toInt();
  final cacheDirectory = Directory('benchmark/.cache');
  final cacheFile = File(
    '${cacheDirectory.path}/fixture_${width}x${height}_$seed.png',
  );
  if (cacheFile.existsSync()) {
    return cacheFile.readAsBytesSync();
  }

  final image = await _renderDetailedImage(size, seed);
  try {
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final encoded = png.buffer.asUint8List(
      png.offsetInBytes,
      png.lengthInBytes,
    );
    cacheDirectory.createSync(recursive: true);
    cacheFile.writeAsBytesSync(encoded);
    return encoded;
  } finally {
    image.dispose();
  }
}

Future<Uint8List> _encodeJpeg(Size size, int seed) async {
  final width = size.width.toInt();
  final height = size.height.toInt();
  final cacheDirectory = Directory('benchmark/.cache');
  final cacheFile = File(
    '${cacheDirectory.path}/fixture_${width}x${height}_${seed}_q85.jpg',
  );
  if (cacheFile.existsSync()) {
    return cacheFile.readAsBytesSync();
  }

  final rgba = await _renderDetailedRgba(size, seed);
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    bytesOffset: rgba.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  final encoded = img.encodeJpg(image, quality: 85);
  cacheDirectory.createSync(recursive: true);
  cacheFile.writeAsBytesSync(encoded);
  return encoded;
}

Future<Uint8List> _renderDetailedRgba(Size size, int seed) async {
  final image = await _renderDetailedImage(size, seed);
  try {
    final data = await image.toByteData();
    return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}

Future<ui.Image> _renderDetailedImage(Size size, int seed) async {
  final width = size.width.toInt();
  final height = size.height.toInt();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final bounds = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  final background = Paint()
    ..shader = ui.Gradient.linear(
      Offset.zero,
      Offset(width.toDouble(), height.toDouble()),
      [
        Color.fromARGB(255, (30 + seed * 40) % 256, 80, 190),
        Color.fromARGB(255, 220, (120 + seed * 35) % 256, 40),
      ],
    );
  canvas.drawRect(bounds, background);

  const columns = 80;
  const rows = 60;
  final paint = Paint();
  for (var y = 0; y < rows; y++) {
    for (var x = 0; x < columns; x++) {
      paint.color = Color.fromARGB(
        210,
        (x * 37 + y * 11 + seed * 53) % 256,
        (x * 17 + y * 43 + seed * 29) % 256,
        ((x ^ y) * 23 + seed * 71) % 256,
      );
      canvas.drawRect(
        Rect.fromLTWH(
          x * width / columns,
          y * height / rows,
          width / columns + 1,
          height / rows + 1,
        ),
        paint,
      );
    }
  }

  paint
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  for (var i = 0; i < 240; i++) {
    paint.color = Color.fromARGB(
      120,
      (i * 31 + seed * 19) % 256,
      (i * 13 + seed * 47) % 256,
      (i * 7 + seed * 61) % 256,
    );
    final x = i * width / 240;
    canvas.drawLine(Offset(x, 0), Offset(width - x, height.toDouble()), paint);
  }

  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

Future<_FullResult> _measureFull(_Fixture fixture, int iterations) async {
  final provider = MemoryImage(fixture.encoded);
  final measured = await _timeProvider(
    provider,
    ImageConfiguration.empty,
    warmup: 1,
    iterations: iterations,
  );
  expect(
    (measured.decode.width, measured.decode.height),
    (fixture.size.width.toInt(), fixture.size.height.toInt()),
    reason: '${fixture.name} full decode',
  );
  return _FullResult(
    decode: measured.decode,
    timing: measured.timing,
    encodedBytes: fixture.encoded.length,
  );
}

Future<ImageProvider<Object>> _extractProvider(
  WidgetTester tester,
  _Fixture fixture,
  _Scenario scenario,
) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(devicePixelRatio: scenario.dpr),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: BudgetedImage(
            image: MemoryImage(fixture.encoded),
            displaySize: scenario.displaySize,
            fit: scenario.fit,
            sourcePixelSize: scenario.sourcePixelSize,
            coverOverscan: scenario.coverOverscan,
            sourceFormat: scenario.sourceFormat,
            qualityMargin: scenario.qualityMargin,
            decodeSizeStep: scenario.decodeSizeStep,
          ),
        ),
      ),
    ),
  );
  final exception = tester.takeException();
  expect(exception, isNull, reason: '${scenario.name}: $exception');
  expect(tester.getSize(find.byType(BudgetedImage)), scenario.displaySize);

  final imageWidget = tester.widget<Image>(find.byType(Image));
  expect(imageWidget.fit, scenario.fit, reason: scenario.name);
  final provider = imageWidget.image;

  final target = computeDecodeTarget(
    logicalSize: scenario.displaySize,
    devicePixelRatio: scenario.dpr,
    fit: scenario.fit,
    sourcePixelSize: scenario.sourcePixelSize,
    coverOverscan: scenario.coverOverscan,
    sourceFormat: scenario.sourceFormat,
    qualityMargin: scenario.qualityMargin,
    decodeSizeStep: scenario.decodeSizeStep,
  );
  if (target.resizes) {
    expect(provider, isA<ResizeImage>(), reason: scenario.name);
    final resize = provider as ResizeImage;
    expect(resize.width, target.width, reason: scenario.name);
    expect(resize.height, target.height, reason: scenario.name);
    expect(resize.policy, target.policy, reason: scenario.name);
    expect(resize.allowUpscaling, isFalse, reason: scenario.name);
  } else {
    expect(provider, isA<MemoryImage>(), reason: scenario.name);
  }

  // Unmount before timing. The initial widget decode is warmup noise and must
  // not compete with the measured decodes.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() async {
    final cache = PaintingBinding.instance.imageCache;
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (cache.pendingImageCount > 0 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    cache.clear();
    cache.clearLiveImages();
  });
  return provider;
}

Future<_ScenarioResult> _measureScenario(
  _Scenario scenario,
  _Fixture fixture,
  ImageProvider<Object> provider,
  _FullResult full,
  int iterations,
  int warmup,
) async {
  final target = computeDecodeTarget(
    logicalSize: scenario.displaySize,
    devicePixelRatio: scenario.dpr,
    fit: scenario.fit,
    sourcePixelSize: scenario.sourcePixelSize,
    coverOverscan: scenario.coverOverscan,
    sourceFormat: scenario.sourceFormat,
    qualityMargin: scenario.qualityMargin,
    decodeSizeStep: scenario.decodeSizeStep,
  );
  final measured = await _timeProvider(
    provider,
    ImageConfiguration(
      devicePixelRatio: scenario.dpr,
      size: scenario.displaySize,
    ),
    warmup: warmup,
    iterations: iterations,
  );
  return _ScenarioResult(
    scenario: scenario,
    fixture: fixture,
    target: target,
    decode: measured.decode,
    timing: measured.timing,
    full: full,
  );
}

Future<({_Decode decode, _Timing timing})> _timeProvider(
  ImageProvider<Object> provider,
  ImageConfiguration configuration, {
  required int warmup,
  required int iterations,
}) async {
  for (var i = 0; i < warmup; i++) {
    await _decodeOnce(provider, configuration);
  }
  final decodes = <_Decode>[];
  for (var i = 0; i < iterations; i++) {
    decodes.add(await _decodeOnce(provider, configuration));
  }
  final first = decodes.first;
  for (final decode in decodes) {
    if (decode.width != first.width || decode.height != first.height) {
      throw StateError(
        'Decode size changed between iterations: '
        '${first.width}x${first.height} vs ${decode.width}x${decode.height}',
      );
    }
  }
  return (decode: first, timing: _Timing.fromDecodes(decodes));
}

Future<_Decode> _decodeOnce(
  ImageProvider<Object> provider,
  ImageConfiguration configuration,
) async {
  // Force a fresh decode every iteration. This measures cold decode cost, not
  // ImageCache lookup cost.
  final cache = PaintingBinding.instance.imageCache;
  cache.clear();
  cache.clearLiveImages();

  final result = Completer<_Decode>();
  final stopwatch = Stopwatch();
  final stream = provider.resolve(configuration);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, synchronousCall) {
      stopwatch.stop();
      final image = info.image;
      final decode = (
        width: image.width,
        height: image.height,
        bytes: decodedBytesFor(image),
        elapsed: stopwatch.elapsed,
      );
      info.dispose();
      if (!result.isCompleted) {
        result.complete(decode);
      }
    },
    onError: (Object error, StackTrace? stackTrace) {
      if (!result.isCompleted) {
        result.completeError(error, stackTrace);
      }
    },
  );
  stopwatch.start();
  stream.addListener(listener);
  try {
    return await result.future;
  } finally {
    stream.removeListener(listener);
    await provider.evict(configuration: configuration);
    cache.clear();
    cache.clearLiveImages();
  }
}

_SizingResult _benchSizing(_SizingCase sizingCase) {
  var checksum = 0;
  void run(int count) {
    for (var i = 0; i < count; i++) {
      final target = computeDecodeTarget(
        logicalSize: sizingCase.logicalSize,
        devicePixelRatio: sizingCase.dpr,
        fit: sizingCase.fit,
        sourcePixelSize: sizingCase.sourcePixelSize,
        coverOverscan: sizingCase.coverOverscan,
      );
      checksum +=
          (target.width ?? 0) + (target.height ?? 0) + target.policy.index;
    }
  }

  run(_sizingIterations ~/ 10);
  final samples = <double>[];
  for (var sample = 0; sample < 3; sample++) {
    final stopwatch = Stopwatch()..start();
    run(_sizingIterations);
    stopwatch.stop();
    samples.add(stopwatch.elapsedMicroseconds * 1000 / _sizingIterations);
  }
  if (checksum < 0) {
    throw StateError('unreachable checksum: $checksum');
  }
  samples.sort();
  return _SizingResult(
    name: sizingCase.name,
    nanosecondsPerCall: samples[1],
  );
}

_CacheResult _runCache({
  required String label,
  int? maxCachedBytes,
  int? maxEntries,
}) {
  final cache = PaintingBinding.instance.imageCache;
  ImageBudget.reset();
  cache.clear();
  cache.clearLiveImages();
  cache.maximumSize = 1000;
  cache.maximumSizeBytes = 100 * 1024 * 1024;
  if (maxCachedBytes != null || maxEntries != null) {
    ImageBudget.configure(
      maxCachedBytes: maxCachedBytes,
      maxEntries: maxEntries,
    );
  }

  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const Color(0xFF336699), BlendMode.src);
  final picture = recorder.endRecording();
  final keys = <String>[];
  var peakBytes = 0;
  try {
    for (var i = 0; i < _cacheImages; i++) {
      final key = 'image-budget-cache-$label-$i';
      keys.add(key);
      final completer = _BenchCompleter();
      cache.putIfAbsent(key, () => completer);
      completer.complete(
        picture.toImageSync(_cacheImageWidth, _cacheImageHeight),
      );
      peakBytes = math.max(peakBytes, cache.currentSizeBytes);
    }
    var retainedEntries = 0;
    for (final key in keys) {
      if (cache.statusForKey(key).keepAlive) {
        retainedEntries++;
      }
    }
    return _CacheResult(
      label: label,
      maxBytes: cache.maximumSizeBytes,
      maxEntries: cache.maximumSize,
      loadedImages: _cacheImages,
      retainedEntries: retainedEntries,
      retainedBytes: cache.currentSizeBytes,
      evictedEntries: _cacheImages - retainedEntries,
      peakBytes: peakBytes,
    );
  } finally {
    picture.dispose();
    ImageBudget.reset();
    cache.clear();
    cache.clearLiveImages();
  }
}

void _printSummary(_Report report) {
  stdout.writeln();
  stdout.writeln('image_budget benchmark');
  stdout.writeln(
    'Flutter ${report.environment['flutter']} · '
    'Dart ${report.environment['dart']} · '
    '${report.environment['cpu']} (${report.environment['cpuCount']} threads)',
  );
  stdout.writeln(
    '${report.scenarios.length} scenarios · '
    '${report.environment['iterations']} iterations after '
    '${report.environment['warmupIterations']} warmup',
  );
  stdout.writeln();
  stdout.writeln(
    '${'scenario'.padRight(46)} ${'decoded'.padLeft(11)} '
    '${'vs full'.padLeft(9)} ${'ms'.padLeft(7)}',
  );
  for (final result in report.scenarios) {
    final name = result.scenario.name.padRight(46);
    final decoded = '${_mib(result.decode.bytes)} MiB'.padLeft(11);
    final saved = '${result.savedPercent.toStringAsFixed(1)}%'.padLeft(9);
    final elapsed = result.timing.medianMs.toStringAsFixed(1).padLeft(7);
    stdout.writeln(
      '$name $decoded $saved $elapsed',
    );
  }
  stdout.writeln();
  stdout.writeln('Sizing overhead:');
  for (final result in report.sizing) {
    stdout.writeln(
      '  ${result.name.padRight(42)} '
      '${result.nanosecondsPerCall.toStringAsFixed(0).padLeft(5)} ns/call',
    );
  }
  stdout.writeln();
  stdout.writeln('Cache retention ($_cacheImages images):');
  for (final result in report.cache) {
    final label = result.label.padRight(34);
    final entries = '${result.retainedEntries} entries'.padLeft(11);
    final retained = '${_mib(result.retainedBytes, 1)} MiB'.padLeft(9);
    stdout.writeln(
      '  $label $entries · $retained · ${result.evictedEntries} evicted',
    );
  }
}

String _renderMarkdown(_Report report) {
  final environment = report.environment;
  final buffer = StringBuffer()
    ..writeln('# image_budget benchmark results')
    ..writeln()
    ..writeln(
      'Generated ${report.generatedAt} on '
      '${environment['os']}.',
    )
    ..writeln()
    ..writeln('| Runtime | Value |')
    ..writeln('|---|---|')
    ..writeln('| Flutter | ${environment['flutter']} |')
    ..writeln('| Dart | ${environment['dart']} |')
    ..writeln('| CPU | ${environment['cpu']} |')
    ..writeln('| Logical CPUs | ${environment['cpuCount']} |')
    ..writeln('| Iterations | ${environment['iterations']} after '
        '${environment['warmupIterations']} warmup |')
    ..writeln()
    ..writeln('## Fixtures')
    ..writeln();
  _writeTable(
    buffer,
    [
      'Fixture',
      'Source pixels',
      'Format',
      'Encoded bytes',
      'Decoded bytes',
      'Full decode ms'
    ],
    [
      for (final fixture in report.fixtures)
        [
          fixture.name,
          '${fixture.size.width.toInt()} × ${fixture.size.height.toInt()}',
          fixture.format.name.toUpperCase(),
          _group(report.fullResults[fixture.name]!.encodedBytes),
          _group(_bytesFor(fixture.size)),
          report.fullResults[fixture.name]!.timing.medianMs.toStringAsFixed(1),
        ],
    ],
  );
  buffer
    ..writeln()
    ..writeln('## Decode scenarios')
    ..writeln()
    ..writeln(
      'Decoded bytes are `width × height × 4` from the actual `ui.Image`. '
      'The decode bounds are what `computeDecodeTarget` asks the codec for; '
      '`ResizeImage` fits inside them, and `allowUpscaling: false` clamps to '
      'the source.',
    )
    ..writeln();
  _writeTable(
    buffer,
    [
      'Scenario',
      'Fit',
      'Source',
      'Display @ DPR',
      'Decode bounds',
      'Decoded',
      'Decoded MiB',
      'Saved',
      'Decode ms',
      'Full ms',
      'Speed',
    ],
    [
      for (final result in report.scenarios)
        [
          result.scenario.name,
          result.scenario.fit.name,
          result.fixture.name,
          '${result.scenario.displaySize.width.toInt()} × '
              '${result.scenario.displaySize.height.toInt()} @ '
              '${result.scenario.dpr}×',
          result.target.resizes
              ? '${result.target.width} × ${result.target.height}'
              : 'none',
          '${result.decode.width} × ${result.decode.height}',
          _mib(result.decode.bytes),
          '${result.savedPercent.toStringAsFixed(1)}%',
          result.timing.medianMs.toStringAsFixed(2),
          result.full.timing.medianMs.toStringAsFixed(2),
          '${(result.full.timing.medianMs / result.timing.medianMs).toStringAsFixed(2)}×',
        ],
    ],
  );
  buffer
    ..writeln()
    ..writeln('## Sizing overhead')
    ..writeln()
    ..writeln(
      '`computeDecodeTarget` is CPU-only. One call happens per '
      '`BudgetedImage` layout. A thousand calls cost the same number in '
      'microseconds as one call costs in nanoseconds.',
    )
    ..writeln();
  _writeTable(
    buffer,
    ['Case', 'ns per call', 'µs per 1000 calls'],
    [
      for (final result in report.sizing)
        [
          result.name,
          result.nanosecondsPerCall.toStringAsFixed(1),
          result.nanosecondsPerCall.toStringAsFixed(1),
        ],
    ],
  );
  buffer
    ..writeln()
    ..writeln('## Cache retention')
    ..writeln()
    ..writeln(
      '$_cacheImages unique $_cacheImageWidth × $_cacheImageHeight '
      'images (${_mib(_cacheImageWidth * _cacheImageHeight * 4 * _cacheImages, 1)} MiB '
      'total) loaded through Flutter\'s `ImageCache`. Bytes are the cache\'s '
      'own accounting, not RSS.',
    )
    ..writeln();
  _writeTable(
    buffer,
    [
      'Limits',
      'Retained entries',
      'Retained MiB',
      'Evicted',
      'Peak MiB',
    ],
    [
      for (final result in report.cache)
        [
          result.label,
          '${result.retainedEntries} / ${result.loadedImages}',
          _mib(result.retainedBytes),
          '${result.evictedEntries}',
          _mib(result.peakBytes),
        ],
    ],
  );
  buffer
    ..writeln()
    ..writeln('## Notes')
    ..writeln()
    ..writeln(
      '- Fixtures are synthetic PNGs and generated JPEGs built in memory at '
      'test start. Decode cost is not representative of every photo.',
    )
    ..writeln(
      '- `flutter test` runs the VM in JIT mode, so absolute milliseconds are '
      'for comparison on this machine only. Treat the ratios as a signal, not '
      'a release-mode promise.',
    )
    ..writeln(
      '- JPEG with a known source size snaps to a native 1/8 scale. On this '
      'machine it cuts both decoded bytes and cold decode time.',
    )
    ..writeln(
      '- PNG resized decode cuts decoded bytes, but cold decode time can be '
      'higher than a full decode in this JIT harness because the codec decodes '
      'the source and then resizes. Pre-sized PNG variants cut both; see '
      '`session.md`.',
    )
    ..writeln(
      '- Decode time covers provider resolution through the first frame, '
      'including a cold codec decode and cache insertion. The cache is '
      'cleared before every iteration.',
    )
    ..writeln(
      '- Decoded bytes exclude row padding, GPU copies, codec scratch space, '
      'the engine, and the Dart heap. Peak decode memory can exceed the '
      'retained bitmap, especially for codecs without scaled decode.',
    )
    ..writeln(
      '- Cache retention exercises `ImageBudget.configure`; it does not '
      'simulate scrolling, eviction during use, or re-decode jank.',
    )
    ..writeln();
  return buffer.toString();
}

void _writeTable(
  StringBuffer buffer,
  List<String> headers,
  List<List<String>> rows,
) {
  buffer
    ..writeln('| ${headers.join(' | ')} |')
    ..writeln('|${headers.map((header) => '---').join('|')}|');
  for (final row in rows) {
    buffer.writeln('| ${row.join(' | ')} |');
  }
}

Map<String, Object?> _reportToJson(_Report report) {
  return {
    'format': 1,
    'package': 'image_budget',
    'generatedAt': report.generatedAt,
    'environment': report.environment,
    'fixtures': [
      for (final fixture in report.fixtures)
        {
          'name': fixture.name,
          'format': fixture.format.name,
          'width': fixture.size.width.toInt(),
          'height': fixture.size.height.toInt(),
          'fullDecodedBytes': _bytesFor(fixture.size),
          'encodedBytes': report.fullResults[fixture.name]!.encodedBytes,
          'fullDecodeMs': {
            'median': report.fullResults[fixture.name]!.timing.medianMs,
            'min': report.fullResults[fixture.name]!.timing.minMs,
            'p90': report.fullResults[fixture.name]!.timing.p90Ms,
          },
        },
    ],
    'scenarios': [
      for (final result in report.scenarios)
        {
          'name': result.scenario.name,
          'fixture': result.fixture.name,
          'fit': result.scenario.fit.name,
          'displayWidth': result.scenario.displaySize.width,
          'displayHeight': result.scenario.displaySize.height,
          'devicePixelRatio': result.scenario.dpr,
          'sourceWidth': result.scenario.sourcePixelSize?.width,
          'sourceHeight': result.scenario.sourcePixelSize?.height,
          'coverOverscan': result.scenario.coverOverscan,
          'sourceFormat': result.scenario.sourceFormat.name,
          'qualityMargin': result.scenario.qualityMargin,
          'decodeSizeStep': result.scenario.decodeSizeStep,
          'decodeBoundsWidth': result.target.width,
          'decodeBoundsHeight': result.target.height,
          'resizePolicy':
              result.target.resizes ? result.target.policy.name : null,
          'decodedWidth': result.decode.width,
          'decodedHeight': result.decode.height,
          'decodedBytes': result.decode.bytes,
          'fullDecodedBytes': result.full.decode.bytes,
          'savedBytes': result.savedBytes,
          'savedPercent': result.savedPercent,
          'sizeFactor': result.sizeFactor,
          'decodeMs': {
            'median': result.timing.medianMs,
            'min': result.timing.minMs,
            'p90': result.timing.p90Ms,
          },
          'fullDecodeMs': {
            'median': result.full.timing.medianMs,
            'min': result.full.timing.minMs,
            'p90': result.full.timing.p90Ms,
          },
          'decodeSpeedup': result.full.timing.medianMs / result.timing.medianMs,
        },
    ],
    'sizing': [
      for (final result in report.sizing)
        {
          'case': result.name,
          'nanosecondsPerCall': result.nanosecondsPerCall,
        },
    ],
    'cache': [
      for (final result in report.cache)
        {
          'label': result.label,
          'maxBytes': result.maxBytes,
          'maxEntries': result.maxEntries,
          'loadedImages': result.loadedImages,
          'retainedEntries': result.retainedEntries,
          'retainedBytes': result.retainedBytes,
          'evictedEntries': result.evictedEntries,
          'peakBytes': result.peakBytes,
        },
    ],
  };
}

Map<String, Object?> _environment(int iterations, int warmup) {
  return {
    'flutter': _flutterVersion(),
    'dart': Platform.version,
    'os': Platform.operatingSystemVersion,
    'cpu': _cpuModel(),
    'cpuCount': Platform.numberOfProcessors,
    'iterations': iterations,
    'warmupIterations': warmup,
  };
}

String _flutterVersion() {
  final roots = <String>[
    if (Platform.environment['FLUTTER_ROOT'] case final root?) root,
    if (_flutterRootFromExecutable() case final root?) root,
  ];
  for (final root in roots) {
    final versionFile = File('$root/version');
    if (versionFile.existsSync()) {
      final version = versionFile.readAsStringSync().trim();
      if (version.isNotEmpty) {
        return version;
      }
    }
    final versionJson = File('$root/bin/cache/flutter.version.json');
    if (!versionJson.existsSync()) {
      continue;
    }
    try {
      final decoded = jsonDecode(versionJson.readAsStringSync());
      if (decoded is Map<String, Object?>) {
        final version = decoded['frameworkVersion'];
        if (version is String && version.isNotEmpty) {
          return version;
        }
      }
    } on FormatException {
      // Try the next candidate.
    }
  }
  return 'unknown';
}

String? _flutterRootFromExecutable() {
  var directory = File(Platform.resolvedExecutable).parent;
  for (var depth = 0; depth < 8; depth++) {
    if (File('${directory.path}/version').existsSync() &&
        Directory('${directory.path}/bin/cache').existsSync()) {
      return directory.path;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      break;
    }
    directory = parent;
  }
  return null;
}

String _cpuModel() {
  final cpuInfo = File('/proc/cpuinfo');
  if (cpuInfo.existsSync()) {
    for (final line in cpuInfo.readAsLinesSync()) {
      if (line.startsWith('model name')) {
        final separator = line.indexOf(':');
        if (separator >= 0) {
          return line.substring(separator + 1).trim();
        }
      }
    }
  }
  return Platform.operatingSystem;
}

int _bytesFor(Size size) => size.width.toInt() * size.height.toInt() * 4;

String _mib(int bytes, [int fractionDigits = 2]) =>
    (bytes / (1 << 20)).toStringAsFixed(fractionDigits);

String _group(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

typedef _Decode = ({
  int width,
  int height,
  int bytes,
  Duration elapsed,
});

class _Timing {
  const _Timing({
    required this.medianMs,
    required this.minMs,
    required this.p90Ms,
  });

  factory _Timing.fromDecodes(List<_Decode> decodes) {
    final micros = [for (final decode in decodes) decode.elapsed.inMicroseconds]
      ..sort();
    return _Timing(
      medianMs: micros[micros.length ~/ 2] / 1000,
      minMs: micros.first / 1000,
      p90Ms: micros[((micros.length - 1) * 0.9).round()] / 1000,
    );
  }

  final double medianMs;
  final double minMs;
  final double p90Ms;
}

class _Fixture {
  const _Fixture({
    required this.name,
    required this.format,
    required this.size,
    required this.encoded,
  });

  final String name;
  final _FixtureFormat format;
  final Size size;
  final Uint8List encoded;
}

enum _FixtureFormat { png, jpeg }

class _FullResult {
  const _FullResult({
    required this.decode,
    required this.timing,
    required this.encodedBytes,
  });

  final _Decode decode;
  final _Timing timing;
  final int encodedBytes;
}

class _Scenario {
  const _Scenario({
    required this.name,
    required this.fixture,
    required this.displaySize,
    required this.dpr,
    required this.fit,
    this.sourcePixelSize,
    this.coverOverscan = 2.0,
    this.sourceFormat = ImageSourceFormat.png,
    this.qualityMargin = 1,
    this.decodeSizeStep = 1,
  });

  final String name;
  final String fixture;
  final Size displaySize;
  final double dpr;
  final BoxFit fit;
  final Size? sourcePixelSize;
  final double coverOverscan;
  final ImageSourceFormat sourceFormat;
  final double qualityMargin;
  final int decodeSizeStep;
}

class _ScenarioResult {
  const _ScenarioResult({
    required this.scenario,
    required this.fixture,
    required this.target,
    required this.decode,
    required this.timing,
    required this.full,
  });

  final _Scenario scenario;
  final _Fixture fixture;
  final DecodeTarget target;
  final _Decode decode;
  final _Timing timing;
  final _FullResult full;

  int get savedBytes => full.decode.bytes - decode.bytes;

  double get savedPercent => savedBytes / full.decode.bytes * 100;

  double get sizeFactor => full.decode.bytes / decode.bytes;
}

class _SizingCase {
  const _SizingCase({
    required this.name,
    required this.logicalSize,
    required this.dpr,
    required this.fit,
    this.sourcePixelSize,
    this.coverOverscan = 2.0,
  });

  final String name;
  final Size logicalSize;
  final double dpr;
  final BoxFit fit;
  final Size? sourcePixelSize;
  final double coverOverscan;
}

class _SizingResult {
  const _SizingResult({
    required this.name,
    required this.nanosecondsPerCall,
  });

  final String name;
  final double nanosecondsPerCall;
}

class _CacheResult {
  const _CacheResult({
    required this.label,
    required this.maxBytes,
    required this.maxEntries,
    required this.loadedImages,
    required this.retainedEntries,
    required this.retainedBytes,
    required this.evictedEntries,
    required this.peakBytes,
  });

  final String label;
  final int maxBytes;
  final int maxEntries;
  final int loadedImages;
  final int retainedEntries;
  final int retainedBytes;
  final int evictedEntries;
  final int peakBytes;
}

class _Report {
  const _Report({
    required this.generatedAt,
    required this.environment,
    required this.fixtures,
    required this.fullResults,
    required this.scenarios,
    required this.sizing,
    required this.cache,
  });

  final String generatedAt;
  final Map<String, Object?> environment;
  final List<_Fixture> fixtures;
  final Map<String, _FullResult> fullResults;
  final List<_ScenarioResult> scenarios;
  final List<_SizingResult> sizing;
  final List<_CacheResult> cache;
}

class _BenchCompleter extends ImageStreamCompleter {
  void complete(ui.Image image) {
    setImage(ImageInfo(image: image));
  }
}

const _scenarios = <_Scenario>[
  _Scenario(
    name: 'contain, card @3x, JPEG',
    fixture: 'landscape-jpeg',
    displaySize: Size(400, 300),
    dpr: 3,
    fit: BoxFit.contain,
    sourcePixelSize: _landscape,
    sourceFormat: ImageSourceFormat.jpeg,
    qualityMargin: 1.25,
  ),
  _Scenario(
    name: 'contain, card @3x, JPEG margin 1',
    fixture: 'landscape-jpeg',
    displaySize: Size(400, 300),
    dpr: 3,
    fit: BoxFit.contain,
    sourcePixelSize: _landscape,
    sourceFormat: ImageSourceFormat.jpeg,
    qualityMargin: 1,
  ),
  _Scenario(
    name: 'cover, card @3x, JPEG',
    fixture: 'landscape-jpeg',
    displaySize: Size(400, 300),
    dpr: 3,
    fit: BoxFit.cover,
    sourcePixelSize: _landscape,
    sourceFormat: ImageSourceFormat.jpeg,
    qualityMargin: 1.25,
  ),
  _Scenario(
    name: 'contain, portrait @3x, JPEG',
    fixture: 'portrait-jpeg',
    displaySize: Size(400, 300),
    dpr: 3,
    fit: BoxFit.contain,
    sourcePixelSize: _portrait,
    sourceFormat: ImageSourceFormat.jpeg,
    qualityMargin: 1.25,
  ),
  _Scenario(
    name: 'contain, card @3x, PNG exact',
    fixture: 'landscape',
    displaySize: Size(400, 300),
    dpr: 3,
    fit: BoxFit.contain,
    sourcePixelSize: _landscape,
  ),
  _Scenario(
    name: 'contain, card @3x, PNG step 32',
    fixture: 'landscape',
    displaySize: Size(400, 300),
    dpr: 3,
    fit: BoxFit.contain,
    sourcePixelSize: _landscape,
    decodeSizeStep: 32,
  ),
  _Scenario(
    name: 'contain, card @3x, auto margin 1.25',
    fixture: 'landscape',
    displaySize: Size(400, 300),
    dpr: 3,
    fit: BoxFit.contain,
    sourcePixelSize: _landscape,
    sourceFormat: ImageSourceFormat.auto,
    qualityMargin: 1.25,
  ),
  _Scenario(
    name: 'contain, card @3x',
    fixture: 'landscape',
    displaySize: Size(400, 300),
    dpr: 3,
    fit: BoxFit.contain,
    sourcePixelSize: _landscape,
  ),
  _Scenario(
    name: 'contain, card @2x',
    fixture: 'landscape',
    displaySize: Size(400, 300),
    dpr: 2,
    fit: BoxFit.contain,
    sourcePixelSize: _landscape,
  ),
  _Scenario(
    name: 'contain, card @1x',
    fixture: 'landscape',
    displaySize: Size(400, 300),
    dpr: 1,
    fit: BoxFit.contain,
    sourcePixelSize: _landscape,
  ),
  _Scenario(
    name: 'contain, thumbnail @2x',
    fixture: 'landscape',
    displaySize: Size(100, 100),
    dpr: 2,
    fit: BoxFit.contain,
    sourcePixelSize: _landscape,
  ),
  _Scenario(
    name: 'cover, square card @3x',
    fixture: 'landscape',
    displaySize: Size(200, 200),
    dpr: 3,
    fit: BoxFit.cover,
    sourcePixelSize: _landscape,
  ),
  _Scenario(
    name: 'cover, square card @3x, no source size',
    fixture: 'landscape',
    displaySize: Size(200, 200),
    dpr: 3,
    fit: BoxFit.cover,
  ),
  _Scenario(
    name: 'cover, square card @3x, overscan 3',
    fixture: 'landscape',
    displaySize: Size(200, 200),
    dpr: 3,
    fit: BoxFit.cover,
    coverOverscan: 3,
  ),
  _Scenario(
    name: 'cover, card @3x',
    fixture: 'landscape',
    displaySize: Size(400, 300),
    dpr: 3,
    fit: BoxFit.cover,
    sourcePixelSize: _landscape,
  ),
  _Scenario(
    name: 'cover, portrait in card @3x',
    fixture: 'portrait',
    displaySize: Size(400, 300),
    dpr: 3,
    fit: BoxFit.cover,
    sourcePixelSize: _portrait,
  ),
  _Scenario(
    name: 'cover, portrait @3x, no source size',
    fixture: 'portrait',
    displaySize: Size(400, 300),
    dpr: 3,
    fit: BoxFit.cover,
  ),
  _Scenario(
    name: 'fill, card @3x',
    fixture: 'landscape',
    displaySize: Size(400, 300),
    dpr: 3,
    fit: BoxFit.fill,
    sourcePixelSize: _landscape,
  ),
  _Scenario(
    name: 'fitWidth, banner @3x',
    fixture: 'landscape',
    displaySize: Size(400, 100),
    dpr: 3,
    fit: BoxFit.fitWidth,
    sourcePixelSize: _landscape,
  ),
  _Scenario(
    name: 'fitHeight, tall card @3x',
    fixture: 'landscape',
    displaySize: Size(100, 400),
    dpr: 3,
    fit: BoxFit.fitHeight,
    sourcePixelSize: _landscape,
  ),
  _Scenario(
    name: 'contain, portrait in card @3x',
    fixture: 'portrait',
    displaySize: Size(400, 300),
    dpr: 3,
    fit: BoxFit.contain,
    sourcePixelSize: _portrait,
  ),
  _Scenario(
    name: 'fitWidth, portrait @3x',
    fixture: 'portrait',
    displaySize: Size(400, 300),
    dpr: 3,
    fit: BoxFit.fitWidth,
    sourcePixelSize: _portrait,
  ),
  _Scenario(
    name: 'contain, small source @3x',
    fixture: 'small',
    displaySize: Size(400, 300),
    dpr: 3,
    fit: BoxFit.contain,
    sourcePixelSize: _small,
  ),
  _Scenario(
    name: 'fill, small source @3x',
    fixture: 'small',
    displaySize: Size(400, 300),
    dpr: 3,
    fit: BoxFit.fill,
    sourcePixelSize: _small,
  ),
  _Scenario(
    name: 'scaleDown, card @3x',
    fixture: 'landscape',
    displaySize: Size(400, 300),
    dpr: 3,
    fit: BoxFit.scaleDown,
    sourcePixelSize: _landscape,
  ),
  _Scenario(
    name: 'none, card @3x',
    fixture: 'landscape',
    displaySize: Size(400, 300),
    dpr: 3,
    fit: BoxFit.none,
    sourcePixelSize: _landscape,
  ),
];

const _sizingCases = <_SizingCase>[
  _SizingCase(
    name: 'contain, card @3x',
    logicalSize: Size(400, 300),
    dpr: 3,
    fit: BoxFit.contain,
  ),
  _SizingCase(
    name: 'cover with source size',
    logicalSize: Size(200, 200),
    dpr: 3,
    fit: BoxFit.cover,
    sourcePixelSize: _landscape,
  ),
  _SizingCase(
    name: 'cover without source size',
    logicalSize: Size(200, 200),
    dpr: 3,
    fit: BoxFit.cover,
  ),
  _SizingCase(
    name: 'cover without source, overscan 3',
    logicalSize: Size(200, 200),
    dpr: 3,
    fit: BoxFit.cover,
    coverOverscan: 3,
  ),
  _SizingCase(
    name: 'fill',
    logicalSize: Size(400, 300),
    dpr: 3,
    fit: BoxFit.fill,
  ),
  _SizingCase(
    name: 'fitWidth with source size',
    logicalSize: Size(400, 100),
    dpr: 3,
    fit: BoxFit.fitWidth,
    sourcePixelSize: _landscape,
  ),
  _SizingCase(
    name: 'fitHeight with source size',
    logicalSize: Size(100, 400),
    dpr: 3,
    fit: BoxFit.fitHeight,
    sourcePixelSize: _landscape,
  ),
  _SizingCase(
    name: 'scaleDown (no resize)',
    logicalSize: Size(400, 300),
    dpr: 3,
    fit: BoxFit.scaleDown,
  ),
  _SizingCase(
    name: 'contain, fractional DPR',
    logicalSize: Size(101, 61),
    dpr: 1.25,
    fit: BoxFit.contain,
  ),
];
