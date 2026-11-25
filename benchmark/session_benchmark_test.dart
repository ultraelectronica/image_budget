// Session benchmark for image_budget.
//
// Run from the package root:
//
//   flutter test benchmark/session_benchmark_test.dart --reporter expanded
//
// This file measures three things the cold-decode benchmark cannot:
// 1. The cost of a pre-sized PNG source versus the original.
// 2. A two-pass static feed, where cache retention avoids re-decodes.
// 3. A resize animation, where decode-size quantization groups nearby sizes.
//
// It does not measure process RSS, GPU memory, or release-mode frame time.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_budget/image_budget.dart';

const _sourceSize = Size(4000, 3000);
const _preSizedSize = Size(1200, 900);
const _displaySize = Size(200, 150);
const _dpr = 3.0;
const _staticImages = 24;
const _animationFrames = 100;
const _cacheBytes = 64 << 20;
const _iterations = 5;

void main() {
  testWidgets(
    'image_budget session benchmark',
    (tester) async {
      final startedAt = DateTime.now().toUtc();
      final cache = PaintingBinding.instance.imageCache;
      ImageBudget.reset();
      cache.maximumSize = 1000;
      cache.maximumSizeBytes = _cacheBytes;
      cache.clear();
      cache.clearLiveImages();

      final fixtures = (await tester.runAsync(_createFixtures))!;
      final preSized = (await tester.runAsync(
        () => _measurePreSized(fixtures, _iterations),
      ))!;
      final staticResults = <_SessionResult>[
        for (final mode in _staticModes)
          (await tester.runAsync(
            () => _measureStatic(fixtures, mode),
          ))!,
      ];
      final animationResults = <_AnimationResult>[
        for (final step in const [1, 32, 64])
          (await tester.runAsync(
            () => _measureAnimation(fixtures, step),
          ))!,
      ];

      final report = _Report(
        generatedAt: startedAt.toIso8601String(),
        environment: _environment(),
        preSized: preSized,
        staticResults: staticResults,
        animationResults: animationResults,
      );
      _printSummary(report);

      if (!_envFlag('IMAGE_BUDGET_BENCH_NO_WRITE')) {
        final outputDirectory = Directory(
          Platform.environment['IMAGE_BUDGET_BENCH_OUT'] ?? 'benchmark/results',
        );
        outputDirectory.createSync(recursive: true);
        final jsonFile = File('${outputDirectory.path}/session.json');
        final markdownFile = File('${outputDirectory.path}/session.md');
        jsonFile.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(_reportToJson(report)),
        );
        markdownFile.writeAsStringSync(_renderMarkdown(report));
        stdout.writeln();
        stdout.writeln('Wrote ${jsonFile.path}');
        stdout.writeln('Wrote ${markdownFile.path}');
      }

      expect(
        preSized.preSized.decode.bytes,
        lessThan(preSized.original.decode.bytes),
        reason: 'pre-sized PNG should decode fewer bytes',
      );
      expect(
        (preSized.original.decode.width, preSized.original.decode.height),
        (4000, 3000),
      );
      expect(
        (preSized.preSized.decode.width, preSized.preSized.decode.height),
        (1200, 900),
      );

      final exactAnimation = animationResults.firstWhere((r) => r.step == 1);
      final quantizedAnimation =
          animationResults.firstWhere((r) => r.step == 32);
      expect(
        quantizedAnimation.uniqueSizes,
        lessThanOrEqualTo(exactAnimation.uniqueSizes ~/ 2),
        reason: 'quantization should cut unique sizes by at least 2x',
      );
      expect(
        quantizedAnimation.decodes,
        lessThanOrEqualTo(exactAnimation.decodes ~/ 2),
        reason: 'quantization should cut animation decodes by at least 2x',
      );
      expect(
        quantizedAnimation.peakBytes,
        lessThanOrEqualTo(exactAnimation.peakBytes * 1.1),
        reason: 'quantization should not grow peak cache bytes by over 10%',
      );

      final stock = staticResults.firstWhere((r) => r.mode == _Mode.stock);
      final exactStatic =
          staticResults.firstWhere((r) => r.mode == _Mode.exact);
      final quantizedStatic =
          staticResults.firstWhere((r) => r.mode == _Mode.quantized32);
      expect(
        exactStatic.decodes,
        lessThan(stock.decodes),
        reason: 'budgeted images should fit in cache for the second pass',
      );
      expect(
        quantizedStatic.retainedBytes,
        lessThanOrEqualTo(exactStatic.retainedBytes * 1.1),
        reason: 'quantized static images should not grow retained bytes by 10%',
      );
      expect(
        exactStatic.retainedBytes,
        lessThanOrEqualTo(_cacheBytes),
        reason: 'retained bytes must stay within the cache cap',
      );

      ImageBudget.reset();
      cache.clear();
      cache.clearLiveImages();
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

bool _envFlag(String name) {
  final value = Platform.environment[name];
  return value == '1' || value == 'true';
}

Future<_Fixtures> _createFixtures() async {
  return _Fixtures(
    original: await _encodePng(_sourceSize, 0),
    preSized: await _encodePng(_preSizedSize, 0),
  );
}

Future<Uint8List> _encodePng(Size size, int seed) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint();
  final width = size.width.toInt();
  final height = size.height.toInt();
  const columns = 16;
  const rows = 12;
  for (var y = 0; y < rows; y++) {
    for (var x = 0; x < columns; x++) {
      paint.color = Color.fromARGB(
        255,
        (x * 16 + seed * 40) % 256,
        (y * 21 + seed * 13) % 256,
        ((x ^ y) * 16 + seed * 29) % 256,
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
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(width, height);
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

Future<_PreSizedResult> _measurePreSized(
  _Fixtures fixtures,
  int iterations,
) async {
  final original = await _timeFull(
    MemoryImage(fixtures.original),
    iterations,
  );
  final preSized = await _timeFull(
    MemoryImage(fixtures.preSized),
    iterations,
  );
  return _PreSizedResult(original: original, preSized: preSized);
}

Future<_TimedDecode> _timeFull(
  ImageProvider<Object> provider,
  int iterations,
) async {
  final decodes = <_DecodeSample>[];
  for (var i = 0; i < iterations; i++) {
    decodes.add(await _decodeOnce(provider));
  }
  final first = decodes.first;
  for (final decode in decodes) {
    if (decode.decode.width != first.decode.width ||
        decode.decode.height != first.decode.height) {
      throw StateError('Decode size changed between iterations');
    }
  }
  final micros = [for (final decode in decodes) decode.elapsed.inMicroseconds]
    ..sort();
  return _TimedDecode(
    decode: first.decode,
    timing: _Timing(
      medianMs: micros[micros.length ~/ 2] / 1000,
      minMs: micros.first / 1000,
      p90Ms: micros[((micros.length - 1) * 0.9).round()] / 1000,
    ),
  );
}

Future<_DecodeSample> _decodeOnce(ImageProvider<Object> provider) async {
  final cache = PaintingBinding.instance.imageCache;
  cache.clear();
  cache.clearLiveImages();
  try {
    final result = await _resolve(provider, ImageConfiguration.empty);
    return (
      decode: result.decode,
      elapsed: result.elapsed,
    );
  } finally {
    await provider.evict();
    cache.clear();
    cache.clearLiveImages();
  }
}

Future<_SessionResult> _measureStatic(_Fixtures fixtures, _Mode mode) async {
  final cache = PaintingBinding.instance.imageCache;
  ImageBudget.configure(maxCachedBytes: _cacheBytes, maxEntries: 1000);
  cache.clear();
  cache.clearLiveImages();

  final providers = [
    for (var i = 0; i < _staticImages; i++) _staticProvider(fixtures, i, mode),
  ];
  final stopwatch = Stopwatch()..start();
  var decodes = 0;
  var cacheHits = 0;
  var peakBytes = 0;
  for (var pass = 0; pass < 2; pass++) {
    for (final provider in providers) {
      final result = await _resolve(
        provider,
        const ImageConfiguration(
          size: _displaySize,
          devicePixelRatio: _dpr,
        ),
      );
      if (result.cached) {
        cacheHits++;
      } else {
        decodes++;
      }
      peakBytes = math.max(peakBytes, cache.currentSizeBytes);
    }
  }
  stopwatch.stop();
  final retainedBytes = cache.currentSizeBytes;
  cache.clear();
  cache.clearLiveImages();
  ImageBudget.reset();
  return _SessionResult(
    mode: mode,
    frames: _staticImages * 2,
    decodes: decodes,
    cacheHits: cacheHits,
    totalMs: stopwatch.elapsedMicroseconds / 1000,
    retainedBytes: retainedBytes,
    peakBytes: peakBytes,
  );
}

ImageProvider<Object> _staticProvider(
  _Fixtures fixtures,
  int index,
  _Mode mode,
) {
  final source = MemoryImage(fixtures.original, scale: 1 + index * 0.001);
  if (mode == _Mode.stock) {
    return source;
  }
  final step = mode == _Mode.exact ? 1 : 32;
  final target = computeDecodeTarget(
    logicalSize: _displaySize,
    devicePixelRatio: _dpr,
    fit: BoxFit.cover,
    sourcePixelSize: _sourceSize,
    sourceFormat: ImageSourceFormat.png,
    qualityMargin: 1,
    decodeSizeStep: step,
  );
  return ResizeImage(
    source,
    width: target.width,
    height: target.height,
    policy: target.policy,
    allowUpscaling: target.allowUpscaling,
  );
}

Future<_AnimationResult> _measureAnimation(
  _Fixtures fixtures,
  int step,
) async {
  final cache = PaintingBinding.instance.imageCache;
  ImageBudget.configure(maxCachedBytes: _cacheBytes, maxEntries: 1000);
  cache.clear();
  cache.clearLiveImages();

  final source = MemoryImage(fixtures.original);
  final stopwatch = Stopwatch()..start();
  final uniqueSizes = <String>{};
  var decodes = 0;
  var cacheHits = 0;
  var peakBytes = 0;
  for (var pass = 0; pass < 2; pass++) {
    for (var frame = 0; frame < _animationFrames; frame++) {
      final width = 200 + (frame % 31);
      final height = 150 + (frame % 23);
      final target = computeDecodeTarget(
        logicalSize: Size(width.toDouble(), height.toDouble()),
        devicePixelRatio: _dpr,
        fit: BoxFit.cover,
        sourcePixelSize: _sourceSize,
        sourceFormat: ImageSourceFormat.png,
        qualityMargin: 1,
        decodeSizeStep: step,
      );
      uniqueSizes.add('${target.width}x${target.height}');
      final provider = ResizeImage(
        source,
        width: target.width,
        height: target.height,
        policy: target.policy,
        allowUpscaling: target.allowUpscaling,
      );
      final result = await _resolve(
        provider,
        ImageConfiguration(
          size: Size(width.toDouble(), height.toDouble()),
          devicePixelRatio: _dpr,
        ),
      );
      if (result.cached) {
        cacheHits++;
      } else {
        decodes++;
      }
      peakBytes = math.max(peakBytes, cache.currentSizeBytes);
    }
  }
  stopwatch.stop();
  final retainedBytes = cache.currentSizeBytes;
  cache.clear();
  cache.clearLiveImages();
  ImageBudget.reset();
  return _AnimationResult(
    step: step,
    frames: _animationFrames * 2,
    uniqueSizes: uniqueSizes.length,
    decodes: decodes,
    cacheHits: cacheHits,
    totalMs: stopwatch.elapsedMicroseconds / 1000,
    retainedBytes: retainedBytes,
    peakBytes: peakBytes,
  );
}

Future<_ResolveResult> _resolve(
  ImageProvider<Object> provider,
  ImageConfiguration configuration,
) async {
  final result = Completer<_ResolveResult>();
  final stopwatch = Stopwatch()..start();
  final stream = provider.resolve(configuration);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, synchronousCall) {
      stopwatch.stop();
      final decode = _Decoded(
        width: info.image.width,
        height: info.image.height,
        bytes: decodedBytesFor(info.image),
      );
      info.dispose();
      if (!result.isCompleted) {
        result.complete(
          _ResolveResult(
            decode: decode,
            elapsed: stopwatch.elapsed,
            cached: synchronousCall,
          ),
        );
      }
    },
    onError: (Object error, StackTrace? stackTrace) {
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

void _printSummary(_Report report) {
  stdout.writeln();
  stdout.writeln('image_budget session benchmark');
  stdout.writeln(
    'Flutter ${report.environment['flutter']} · '
    'Dart ${report.environment['dart']} · '
    '${report.environment['cpu']}',
  );
  stdout.writeln();
  stdout.writeln('Pre-sized PNG:');
  stdout.writeln(
    '  original ${report.preSized.original.decode.width}x'
    '${report.preSized.original.decode.height} '
    '${_mib(report.preSized.original.decode.bytes)} MiB '
    '${report.preSized.original.timing.medianMs.toStringAsFixed(1)} ms',
  );
  stdout.writeln(
    '  pre-sized ${report.preSized.preSized.decode.width}x'
    '${report.preSized.preSized.decode.height} '
    '${_mib(report.preSized.preSized.decode.bytes)} MiB '
    '${report.preSized.preSized.timing.medianMs.toStringAsFixed(1)} ms',
  );
  stdout.writeln();
  stdout.writeln('Static two-pass feed ($_staticImages images):');
  for (final result in report.staticResults) {
    stdout.writeln(
      '  ${result.mode.label.padRight(14)} '
      '${result.decodes} decodes · ${result.cacheHits} hits · '
      '${result.totalMs.toStringAsFixed(0)} ms · '
      '${_mib(result.retainedBytes)} MiB retained',
    );
  }
  stdout.writeln();
  stdout.writeln('Resize animation ($_animationFrames frames x 2 passes):');
  for (final result in report.animationResults) {
    stdout.writeln(
      '  step ${result.step.toString().padRight(3)} '
      '${result.uniqueSizes} sizes · ${result.decodes} decodes · '
      '${result.cacheHits} hits · ${result.totalMs.toStringAsFixed(0)} ms · '
      '${_mib(result.retainedBytes)} MiB retained',
    );
  }
}

String _renderMarkdown(_Report report) {
  final buffer = StringBuffer()
    ..writeln('# image_budget session benchmark')
    ..writeln()
    ..writeln('Generated ${report.generatedAt}.')
    ..writeln()
    ..writeln('| Runtime | Value |')
    ..writeln('|---|---|')
    ..writeln('| Flutter | ${report.environment['flutter']} |')
    ..writeln('| Dart | ${report.environment['dart']} |')
    ..writeln('| CPU | ${report.environment['cpu']} |')
    ..writeln()
    ..writeln('## Pre-sized PNG')
    ..writeln()
    ..writeln(
      'The original is 4000 × 3000. The pre-sized source is 1200 × 900. '
      'Both are decoded directly, without a `ResizeImage` wrapper.',
    )
    ..writeln()
    ..writeln('| Source | Decoded | Decoded MiB | Decode ms |')
    ..writeln('|---|---|---|---|')
    ..writeln(
      '| Original | ${report.preSized.original.decode.width} × '
      '${report.preSized.original.decode.height} | '
      '${_mib(report.preSized.original.decode.bytes)} | '
      '${report.preSized.original.timing.medianMs.toStringAsFixed(2)} |',
    )
    ..writeln(
      '| Pre-sized | ${report.preSized.preSized.decode.width} × '
      '${report.preSized.preSized.decode.height} | '
      '${_mib(report.preSized.preSized.decode.bytes)} | '
      '${report.preSized.preSized.timing.medianMs.toStringAsFixed(2)} |',
    )
    ..writeln()
    ..writeln('## Static two-pass feed')
    ..writeln()
    ..writeln(
      '$_staticImages unique images, 200 × 150 logical at $_dpr×. '
      'The cache cap is ${_mib(_cacheBytes)} MiB. Each mode resolves '
      'every image twice.',
    )
    ..writeln()
    ..writeln(
      '| Mode | Decodes | Cache hits | Total ms | Retained MiB | '
      'Peak MiB |',
    )
    ..writeln('|---|---|---|---|---|---|');
  for (final result in report.staticResults) {
    buffer.writeln(
      '| ${result.mode.label} | ${result.decodes} | ${result.cacheHits} | '
      '${result.totalMs.toStringAsFixed(0)} | '
      '${_mib(result.retainedBytes)} | ${_mib(result.peakBytes)} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Resize animation')
    ..writeln()
    ..writeln(
      '$_animationFrames frames, two passes, one source image. The display '
      'width varies from 200 to 230 logical pixels, the height from 150 to '
      '172. Exact sizing creates a new cache key for most frames. '
      'Quantization groups nearby sizes.',
    )
    ..writeln()
    ..writeln(
      '| Step | Unique sizes | Decodes | Cache hits | Total ms | '
      'Retained MiB | Peak MiB |',
    )
    ..writeln('|---|---|---|---|---|---|---|');
  for (final result in report.animationResults) {
    buffer.writeln(
      '| ${result.step} | ${result.uniqueSizes} | ${result.decodes} | '
      '${result.cacheHits} | ${result.totalMs.toStringAsFixed(0)} | '
      '${_mib(result.retainedBytes)} | ${_mib(result.peakBytes)} |',
    );
  }
  final exactAnimation = report.animationResults.firstWhere(
    (result) => result.step == 1,
  );
  final step32 = report.animationResults.firstWhere(
    (result) => result.step == 32,
  );
  final exactStatic = report.staticResults.firstWhere(
    (result) => result.mode == _Mode.exact,
  );
  final step32Static = report.staticResults.firstWhere(
    (result) => result.mode == _Mode.quantized32,
  );
  final staticTimeDelta =
      (step32Static.totalMs - exactStatic.totalMs) / exactStatic.totalMs * 100;
  final staticByteDelta =
      (step32Static.retainedBytes - exactStatic.retainedBytes) /
          exactStatic.retainedBytes *
          100;
  buffer
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      'Step 32 met the animation gate: '
      '${step32.uniqueSizes} unique sizes versus ${exactAnimation.uniqueSizes}, '
      '${step32.decodes} decodes versus ${exactAnimation.decodes}, '
      '${step32.totalMs.toStringAsFixed(0)} ms versus '
      '${exactAnimation.totalMs.toStringAsFixed(0)} ms, and '
      '${_mib(step32.peakBytes)} MiB peak versus '
      '${_mib(exactAnimation.peakBytes)} MiB.',
    )
    ..writeln()
    ..writeln(
      'The static feed was '
      '${exactStatic.totalMs.toStringAsFixed(0)} ms exact versus '
      '${step32Static.totalMs.toStringAsFixed(0)} ms at step 32 '
      '(${staticTimeDelta.toStringAsFixed(1)}%), with '
      '${_mib(exactStatic.retainedBytes)} MiB versus '
      '${_mib(step32Static.retainedBytes)} MiB retained '
      '(${staticByteDelta.toStringAsFixed(1)}%). Static timing varied between '
      'runs; treat that difference as noise, not a proven cost or win.',
    )
    ..writeln()
    ..writeln(
      'Decision: keep `decodeSizeStep: 1` as the default. The animation win is '
      'clear, but step 32 rounds small 1x targets up sharply and its static '
      'feed benefit is not established. Use `32` for layouts whose pixel size '
      'changes often. Revisit the default after a profile build on a real '
      'device.',
    )
    ..writeln()
    ..writeln('## Notes')
    ..writeln()
    ..writeln(
      '- `flutter test` runs in JIT mode. Absolute milliseconds are for '
      'comparison on this machine, not a release-mode promise.',
    )
    ..writeln(
      '- Decoded bytes exclude row padding, GPU copies, codec scratch space, '
      'the engine, and the Dart heap.',
    )
    ..writeln(
      '- The static feed is synthetic. A real feed has mixed source sizes, '
      'scrolling, and live images.',
    )
    ..writeln(
      '- Quantization helps layouts whose pixel size changes. It does not '
      'reduce a single cold decode.',
    );
  return buffer.toString();
}

Map<String, Object?> _reportToJson(_Report report) {
  return {
    'format': 1,
    'package': 'image_budget',
    'generatedAt': report.generatedAt,
    'environment': report.environment,
    'preSized': {
      'original': _timedDecodeToJson(report.preSized.original),
      'preSized': _timedDecodeToJson(report.preSized.preSized),
    },
    'static': [
      for (final result in report.staticResults)
        {
          'mode': result.mode.name,
          'frames': result.frames,
          'decodes': result.decodes,
          'cacheHits': result.cacheHits,
          'totalMs': result.totalMs,
          'retainedBytes': result.retainedBytes,
          'peakBytes': result.peakBytes,
        },
    ],
    'animation': [
      for (final result in report.animationResults)
        {
          'step': result.step,
          'frames': result.frames,
          'uniqueSizes': result.uniqueSizes,
          'decodes': result.decodes,
          'cacheHits': result.cacheHits,
          'totalMs': result.totalMs,
          'retainedBytes': result.retainedBytes,
          'peakBytes': result.peakBytes,
        },
    ],
  };
}

Map<String, Object?> _timedDecodeToJson(_TimedDecode result) {
  return {
    'width': result.decode.width,
    'height': result.decode.height,
    'bytes': result.decode.bytes,
    'medianMs': result.timing.medianMs,
    'minMs': result.timing.minMs,
    'p90Ms': result.timing.p90Ms,
  };
}

Map<String, Object?> _environment() {
  return {
    'flutter': _flutterVersion(),
    'dart': Platform.version,
    'os': Platform.operatingSystemVersion,
    'cpu': _cpuModel(),
    'cpuCount': Platform.numberOfProcessors,
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

String _mib(int bytes) => (bytes / (1 << 20)).toStringAsFixed(2);

typedef _DecodeSample = ({_Decoded decode, Duration elapsed});

class _Decoded {
  const _Decoded({
    required this.width,
    required this.height,
    required this.bytes,
  });

  final int width;
  final int height;
  final int bytes;
}

class _Timing {
  const _Timing({
    required this.medianMs,
    required this.minMs,
    required this.p90Ms,
  });

  final double medianMs;
  final double minMs;
  final double p90Ms;
}

class _TimedDecode {
  const _TimedDecode({required this.decode, required this.timing});

  final _Decoded decode;
  final _Timing timing;
}

class _Fixtures {
  const _Fixtures({required this.original, required this.preSized});

  final Uint8List original;
  final Uint8List preSized;
}

class _PreSizedResult {
  const _PreSizedResult({required this.original, required this.preSized});

  final _TimedDecode original;
  final _TimedDecode preSized;
}

enum _Mode {
  stock('stock'),
  exact('exact'),
  quantized32('step 32');

  const _Mode(this.label);

  final String label;
}

class _SessionResult {
  const _SessionResult({
    required this.mode,
    required this.frames,
    required this.decodes,
    required this.cacheHits,
    required this.totalMs,
    required this.retainedBytes,
    required this.peakBytes,
  });

  final _Mode mode;
  final int frames;
  final int decodes;
  final int cacheHits;
  final double totalMs;
  final int retainedBytes;
  final int peakBytes;
}

class _AnimationResult {
  const _AnimationResult({
    required this.step,
    required this.frames,
    required this.uniqueSizes,
    required this.decodes,
    required this.cacheHits,
    required this.totalMs,
    required this.retainedBytes,
    required this.peakBytes,
  });

  final int step;
  final int frames;
  final int uniqueSizes;
  final int decodes;
  final int cacheHits;
  final double totalMs;
  final int retainedBytes;
  final int peakBytes;
}

class _ResolveResult {
  const _ResolveResult({
    required this.decode,
    required this.elapsed,
    required this.cached,
  });

  final _Decoded decode;
  final Duration elapsed;
  final bool cached;
}

class _Report {
  const _Report({
    required this.generatedAt,
    required this.environment,
    required this.preSized,
    required this.staticResults,
    required this.animationResults,
  });

  final String generatedAt;
  final Map<String, Object?> environment;
  final _PreSizedResult preSized;
  final List<_SessionResult> staticResults;
  final List<_AnimationResult> animationResults;
}

const _staticModes = <_Mode>[_Mode.stock, _Mode.exact, _Mode.quantized32];
