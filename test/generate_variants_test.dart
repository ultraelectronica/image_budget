import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../tool/generate_variants.dart';

void main() {
  test('generates width-bucketed PNG variants and skips upscaling', () {
    final directory = Directory.systemTemp.createTempSync('image-budget-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final source = File('${directory.path}/photo.png');
    final image = img.Image(width: 1000, height: 750);
    img.fill(image, color: img.ColorRgb8(20, 120, 200));
    source.writeAsBytesSync(img.encodePng(image));

    final outputs = generateVariants(
      sourcePath: source.path,
      widths: const [1200, 400, 800],
      outputDirectory: '${directory.path}/variants',
    );

    expect([for (final output in outputs) output.width], [400, 800]);
    expect([for (final output in outputs) output.height], [300, 600]);
    for (final output in outputs) {
      final decoded = img.decodePng(File(output.path).readAsBytesSync());
      expect(decoded, isNotNull);
      expect((decoded!.width, decoded.height), (output.width, output.height));
    }
    expect(
      outputs.map((output) => output.path),
      everyElement(endsWith('w.png')),
    );
  });

  test('rejects widths at or above a small source', () {
    final directory = Directory.systemTemp.createTempSync('image-budget-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final source = File('${directory.path}/small.png');
    source.writeAsBytesSync(img.encodePng(img.Image(width: 100, height: 100)));

    expect(
      () => generateVariants(
        sourcePath: source.path,
        widths: const [200],
      ),
      throwsArgumentError,
    );
  });
}
