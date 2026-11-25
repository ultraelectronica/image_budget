import 'dart:io';

import 'package:image/image.dart' as img;

/// Converts the example PNG into a JPEG for the device benchmark.
///
///   dart run tool/make_example_jpeg.dart
void main(List<String> arguments) {
  final inputPath =
      arguments.isNotEmpty ? arguments[0] : 'example/assets/landscape.png';
  final outputPath =
      arguments.length > 1 ? arguments[1] : 'example/assets/landscape.jpg';

  final input = File(inputPath);
  if (!input.existsSync()) {
    stderr.writeln('Missing $inputPath');
    exitCode = 1;
    return;
  }
  final decoded = img.decodeImage(input.readAsBytesSync());
  if (decoded == null) {
    stderr.writeln('Could not decode $inputPath');
    exitCode = 1;
    return;
  }
  final output = File(outputPath)
    ..writeAsBytesSync(
      img.encodeJpg(decoded, quality: 85),
    );
  stdout.writeln('Wrote ${output.path}');
}
