import 'dart:async';

// Use the SDK Material export for compatibility with Flutter 3.24.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:image_budget/image_budget.dart';

const _sourceSize = Size(2400, 1600);
const _startWidth = 320.0;
const _endWidth = 520.0;
const _duration = Duration(milliseconds: 1667);

enum _BenchmarkMode {
  stockPng('stock png', 'assets/landscape.png', ImageSourceFormat.png, 1),
  exactPng(
      'budgeted png exact', 'assets/landscape.png', ImageSourceFormat.png, 1),
  quantizedPng('budgeted png step 32', 'assets/landscape.png',
      ImageSourceFormat.png, 32),
  stockJpeg('stock jpeg', 'assets/landscape.jpg', ImageSourceFormat.jpeg, 1),
  budgetedJpeg(
      'budgeted jpeg', 'assets/landscape.jpg', ImageSourceFormat.jpeg, 1);

  const _BenchmarkMode(
      this.label, this.asset, this.format, this.decodeSizeStep);

  final String label;
  final String asset;
  final ImageSourceFormat format;
  final int decodeSizeStep;

  bool get budgeted => this != stockPng && this != stockJpeg;
}

/// Runs a 1.67-second resize animation for stock, exact, and quantized images.
///
/// Run this on a device in profile mode:
///
///   flutter run --profile --dart-define=IMAGE_BUDGET_BENCH=true
///
/// The app prints one `IMAGE_BUDGET_BENCH` line per mode. Frame timings are
/// diagnostic only. They are not a release-mode benchmark.
class ResizeBenchmark extends StatefulWidget {
  const ResizeBenchmark({super.key});

  @override
  State<ResizeBenchmark> createState() => _ResizeBenchmarkState();
}

class _ResizeBenchmarkState extends State<ResizeBenchmark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final List<_BenchmarkResult> _results = [];
  _BenchmarkMode? _active;
  String _status = 'Starting';

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration);
    WidgetsBinding.instance.addPostFrameCallback((_) => _runAll());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _runAll() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) {
      return;
    }
    setState(() {
      _active = _BenchmarkMode.stockPng;
      _status = 'Warming up';
    });
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await _runPass(_BenchmarkMode.stockPng, log: false);
    for (final mode in _BenchmarkMode.values) {
      if (!mounted) {
        return;
      }
      setState(() {
        _active = mode;
        _status = 'Running ${mode.label}';
      });
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final result = await _runPass(mode);
      if (!mounted) {
        return;
      }
      setState(() {
        _results.add(result);
        _status = 'Finished ${mode.label}';
      });
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _active = null;
      _status = 'Done. Check the profile log for IMAGE_BUDGET_BENCH lines.';
    });
  }

  Future<_BenchmarkResult> _runPass(
    _BenchmarkMode mode, {
    bool log = true,
  }) async {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final refreshRate = View.of(context).display.refreshRate;
    final frameBudgetUs = 1000000 / refreshRate;
    final startSize = Size(_startWidth, _startWidth * 9 / 16);
    final startProvider = _providerFor(mode, startSize, dpr);
    final cache = PaintingBinding.instance.imageCache;

    ImageBudget.clear();
    cache.clear();
    cache.clearLiveImages();
    try {
      await precacheImage(startProvider, context);
    } on Object {
      // A decode failure appears as a blank frame. Keep the benchmark moving.
    }

    _controller.value = 0;
    await WidgetsBinding.instance.endOfFrame;

    final timings = <FrameTiming>[];
    void onTimings(List<FrameTiming> batch) => timings.addAll(batch);
    SchedulerBinding.instance.addTimingsCallback(onTimings);
    try {
      await _controller.animateTo(1, duration: _duration);
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      SchedulerBinding.instance.removeTimingsCallback(onTimings);
    }

    final stats = ImageBudget.stats;
    final build = [
      for (final timing in timings) timing.buildDuration.inMicroseconds
    ]..sort();
    final raster = [
      for (final timing in timings) timing.rasterDuration.inMicroseconds,
    ]..sort();
    final total = [
      for (final timing in timings) timing.totalSpan.inMicroseconds,
    ]..sort();
    final result = _BenchmarkResult(
      label: mode.label,
      dpr: dpr,
      refreshRate: refreshRate,
      frames: timings.length,
      buildAverageMs: _averageMs(build),
      rasterAverageMs: _averageMs(raster),
      totalP90Ms: _p90Ms(total),
      jankFrames: timings
          .where((timing) => timing.totalSpan.inMicroseconds > frameBudgetUs)
          .length,
      cachedBytes: stats.cachedBytes,
      cachedEntries: stats.cachedEntries,
    );
    if (log) {
      debugPrint(result.toLogLine());
    }
    return result;
  }

  ImageProvider<Object> _providerFor(
    _BenchmarkMode mode,
    Size logicalSize,
    double dpr,
  ) {
    final asset = AssetImage(mode.asset);
    if (!mode.budgeted) {
      return asset;
    }
    final target = computeDecodeTarget(
      logicalSize: logicalSize,
      devicePixelRatio: dpr,
      fit: BoxFit.cover,
      sourcePixelSize: _sourceSize,
      sourceFormat: mode.format,
      qualityMargin: mode.format == ImageSourceFormat.jpeg ? 1.25 : 1,
      decodeSizeStep: mode.decodeSizeStep,
    );
    return ResizeImage(
      asset,
      width: target.width,
      height: target.height,
      policy: target.policy,
      allowUpscaling: target.allowUpscaling,
    );
  }

  Widget _image(_BenchmarkMode mode) {
    final asset = AssetImage(mode.asset);
    if (!mode.budgeted) {
      return Image(image: asset, fit: BoxFit.cover);
    }
    return BudgetedImage(
      image: asset,
      fit: BoxFit.cover,
      sourcePixelSize: _sourceSize,
      sourceFormat: mode.format,
      qualityMargin: mode.format == ImageSourceFormat.jpeg ? 1.25 : 1,
      decodeSizeStep: mode.decodeSizeStep,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mode = _active;
    return Scaffold(
      appBar: AppBar(title: const Text('Resize benchmark')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'A 1.67-second width animation. Watch the profile log for one '
              'IMAGE_BUDGET_BENCH line per mode.',
            ),
            const SizedBox(height: 12),
            Text(_status),
            if (mode != null) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
              Center(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final width = _startWidth +
                        (_endWidth - _startWidth) * _controller.value;
                    return SizedBox(
                      width: width,
                      height: width * 9 / 16,
                      child: _image(mode),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 24),
            for (final result in _results)
              Card(
                child: ListTile(
                  title: Text(result.label),
                  subtitle: Text(result.details),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BenchmarkResult {
  const _BenchmarkResult({
    required this.label,
    required this.dpr,
    required this.refreshRate,
    required this.frames,
    required this.buildAverageMs,
    required this.rasterAverageMs,
    required this.totalP90Ms,
    required this.jankFrames,
    required this.cachedBytes,
    required this.cachedEntries,
  });

  final String label;
  final double dpr;
  final double refreshRate;
  final int frames;
  final double buildAverageMs;
  final double rasterAverageMs;
  final double totalP90Ms;
  final int jankFrames;
  final int cachedBytes;
  final int cachedEntries;

  String get details => '$frames frames · build avg '
      '${buildAverageMs.toStringAsFixed(2)} ms · raster avg '
      '${rasterAverageMs.toStringAsFixed(2)} ms · p90 '
      '${totalP90Ms.toStringAsFixed(2)} ms · $jankFrames jank at '
      '${refreshRate.toStringAsFixed(0)} Hz · '
      '${(cachedBytes / (1 << 20)).toStringAsFixed(1)} MiB cached';

  String toLogLine() => 'IMAGE_BUDGET_BENCH '
      'mode=${label.replaceAll(' ', '_')} '
      'dpr=${dpr.toStringAsFixed(3)} '
      'refresh_hz=${refreshRate.toStringAsFixed(1)} '
      'frames=$frames '
      'build_avg_ms=${buildAverageMs.toStringAsFixed(2)} '
      'raster_avg_ms=${rasterAverageMs.toStringAsFixed(2)} '
      'total_p90_ms=${totalP90Ms.toStringAsFixed(2)} '
      'jank_frames=$jankFrames '
      'cached_mib=${(cachedBytes / (1 << 20)).toStringAsFixed(2)} '
      'cached_entries=$cachedEntries';
}

double _averageMs(List<int> micros) {
  if (micros.isEmpty) {
    return 0;
  }
  return micros.reduce((a, b) => a + b) / micros.length / 1000;
}

double _p90Ms(List<int> micros) {
  if (micros.isEmpty) {
    return 0;
  }
  return micros[((micros.length - 1) * 0.9).round()] / 1000;
}
