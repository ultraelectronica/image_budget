import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_budget/image_budget.dart';

const _sourceWidth = 1600;
const _sourceHeight = 1200;
const _referenceWidth = 800;
const _referenceHeight = 600;

void main() {
  testWidgets('JPEG native scaling protects detail below the display target', (
    tester,
  ) async {
    final result = await tester.runAsync(_runQualityCheck);
    final safe = result!.safe;
    final unsafe = result.unsafe;

    expect(
      safe.width,
      greaterThanOrEqualTo(result.requestedWidth),
      reason: 'safe JPEG decode should cover the requested width',
    );
    expect(
      safe.height,
      greaterThanOrEqualTo(result.requestedHeight),
      reason: 'safe JPEG decode should cover the requested height',
    );
    // The native JPEG scale is not pixel-identical to a full decode followed
    // by a high-quality scale, but it should retain more detail than decoding
    // below the target and letting paint upscale.
    expect(
      safe.psnr,
      greaterThan(unsafe.psnr + 1),
      reason: 'safe PSNR ${safe.psnr}, unsafe PSNR ${unsafe.psnr}',
    );
    expect(
      safe.mae,
      lessThan(unsafe.mae),
      reason: 'safe MAE ${safe.mae}, unsafe MAE ${unsafe.mae}',
    );
    expect(
      safe.psnr,
      greaterThan(24),
      reason: 'safe PSNR ${safe.psnr} is below the regression threshold',
    );
  });
}

Future<_QualityResult> _runQualityCheck() async {
  final encoded = _encodeJpeg();
  final source = await _decode(MemoryImage(encoded));
  try {
    final requested = computeDecodeTarget(
      logicalSize: const Size(500, 375),
      devicePixelRatio: 1,
      fit: BoxFit.contain,
      sourcePixelSize: const Size(
        _sourceWidth * 1.0,
        _sourceHeight * 1.0,
      ),
    );
    final safeTarget = computeDecodeTarget(
      logicalSize: const Size(500, 375),
      devicePixelRatio: 1,
      fit: BoxFit.contain,
      sourcePixelSize: const Size(
        _sourceWidth * 1.0,
        _sourceHeight * 1.0,
      ),
      sourceFormat: ImageSourceFormat.jpeg,
      qualityMargin: 1.25,
    );
    final unsafeTarget = requested;

    final safeImage = await _decode(
      ResizeImage(
        MemoryImage(encoded),
        width: safeTarget.width,
        height: safeTarget.height,
        policy: safeTarget.policy,
        allowUpscaling: safeTarget.allowUpscaling,
      ),
    );
    final unsafeImage = await _decode(
      ResizeImage(
        MemoryImage(encoded),
        width: unsafeTarget.width,
        height: unsafeTarget.height,
        policy: unsafeTarget.policy,
        allowUpscaling: unsafeTarget.allowUpscaling,
      ),
    );
    try {
      final reference = await _drawTo(
        source,
        _referenceWidth,
        _referenceHeight,
      );
      final safe = await _drawTo(
        safeImage,
        _referenceWidth,
        _referenceHeight,
      );
      final unsafe = await _drawTo(
        unsafeImage,
        _referenceWidth,
        _referenceHeight,
      );
      try {
        final referenceBytes = await _rgba(reference);
        final safeBytes = await _rgba(safe);
        final unsafeBytes = await _rgba(unsafe);
        final safeMetrics = _compare(referenceBytes, safeBytes);
        final unsafeMetrics = _compare(referenceBytes, unsafeBytes);
        return (
          requestedWidth: requested.width!,
          requestedHeight: requested.height!,
          safe: (
            width: safeImage.width,
            height: safeImage.height,
            mae: safeMetrics.mae,
            psnr: safeMetrics.psnr,
          ),
          unsafe: (
            width: unsafeImage.width,
            height: unsafeImage.height,
            mae: unsafeMetrics.mae,
            psnr: unsafeMetrics.psnr,
          ),
        );
      } finally {
        reference.dispose();
        safe.dispose();
        unsafe.dispose();
      }
    } finally {
      safeImage.dispose();
      unsafeImage.dispose();
    }
  } finally {
    source.dispose();
  }
}

Uint8List _encodeJpeg() {
  final image = img.Image(width: _sourceWidth, height: _sourceHeight);
  for (var y = 0; y < _sourceHeight; y++) {
    for (var x = 0; x < _sourceWidth; x++) {
      final checker = ((x ~/ 6) + (y ~/ 6)).isEven ? 255 : 96;
      final red = (x * 255 ~/ _sourceWidth);
      final green = (y * 255 ~/ _sourceHeight);
      image.setPixelRgb(x, y, red, green, checker);
    }
  }
  return img.encodeJpg(image, quality: 88);
}

Future<ui.Image> _decode(ImageProvider<Object> provider) async {
  final cache = PaintingBinding.instance.imageCache;
  cache.clear();
  cache.clearLiveImages();

  final result = Completer<ui.Image>();
  final configuration = ImageConfiguration.empty;
  final stream = provider.resolve(configuration);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, synchronousCall) {
      final image = info.image.clone();
      info.dispose();
      if (!result.isCompleted) {
        result.complete(image);
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
    await provider.evict(configuration: configuration);
    cache.clear();
    cache.clearLiveImages();
  }
}

Future<ui.Image> _drawTo(ui.Image source, int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImageRect(
    source,
    Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..filterQuality = FilterQuality.high,
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

Future<Uint8List> _rgba(ui.Image image) async {
  final data = await image.toByteData();
  return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

({double mae, double psnr}) _compare(Uint8List reference, Uint8List actual) {
  var absolute = 0;
  var squared = 0;
  var channels = 0;
  for (var i = 0; i < reference.length; i += 4) {
    for (var channel = 0; channel < 3; channel++) {
      final difference = reference[i + channel] - actual[i + channel];
      absolute += difference.abs();
      squared += difference * difference;
      channels++;
    }
  }
  final mae = absolute / channels;
  final mse = squared / channels;
  final psnr = mse == 0 ? 99.0 : 10 * (math.log(255 * 255 / mse) / math.ln10);
  return (mae: mae, psnr: psnr);
}

typedef _QualityResult = ({
  int requestedWidth,
  int requestedHeight,
  ({
    int width,
    int height,
    double mae,
    double psnr,
  }) safe,
  ({
    int width,
    int height,
    double mae,
    double psnr,
  }) unsafe,
});
