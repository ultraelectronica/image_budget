import 'dart:io';

import 'package:image/image.dart' as img;

/// Generates width-bucketed PNG variants for pre-sized image sources.
///
/// Usage:
///   dart run tool/generate_variants.dart assets/photo.png
///   dart run tool/generate_variants.dart assets/photo.png --widths=400,800,1200
///   dart run tool/generate_variants.dart assets/photo.png --out-dir=assets/variants
void main(List<String> arguments) {
  final options = _Options.parse(arguments);
  if (options.sourcePaths.isEmpty || options.showHelp) {
    stdout.writeln(_usage);
    if (options.showHelp) {
      return;
    }
    exitCode = 64;
    return;
  }

  for (final sourcePath in options.sourcePaths) {
    final outputs = generateVariants(
      sourcePath: sourcePath,
      widths: options.widths,
      outputDirectory: options.outputDirectory,
    );
    stdout.writeln('$sourcePath:');
    for (final output in outputs) {
      stdout.writeln(
        '  ${output.path} (${output.width} x ${output.height})',
      );
    }
    stdout.writeln();
    stdout.writeln('Dart snippet:');
    stdout.writeln('  imageVariants: [');
    for (final output in outputs) {
      final asset = output.path.replaceAll(r'\', '/');
      stdout.writeln(
        "    ImageVariant(image: AssetImage('$asset'), "
        'pixelSize: Size(${output.width}, ${output.height})),',
      );
    }
    stdout.writeln('  ],');
    stdout.writeln();
  }
}

/// One generated variant.
typedef VariantOutput = ({String path, int width, int height});

/// Resizes [sourcePath] to each width in [widths] and writes PNG files.
List<VariantOutput> generateVariants({
  required String sourcePath,
  required List<int> widths,
  String? outputDirectory,
}) {
  if (widths.isEmpty) {
    throw ArgumentError.value(widths, 'widths', 'must not be empty');
  }
  for (final width in widths) {
    if (width <= 0) {
      throw ArgumentError.value(widths, 'widths', 'must be positive');
    }
  }

  final sourceFile = File(sourcePath);
  if (!sourceFile.existsSync()) {
    throw ArgumentError.value(sourcePath, 'sourcePath', 'does not exist');
  }

  final decoded = img.decodeImage(sourceFile.readAsBytesSync());
  if (decoded == null) {
    throw ArgumentError.value(
      sourcePath,
      'sourcePath',
      'is not a supported image',
    );
  }

  final sourceName = _basenameWithoutExtension(sourceFile.path);
  final directory = Directory(outputDirectory ?? sourceFile.parent.path)
    ..createSync(recursive: true);
  final sortedWidths = widths.toSet().toList()..sort();
  final outputs = <VariantOutput>[];

  for (final width in sortedWidths) {
    if (width >= decoded.width) {
      stderr.writeln(
        'Skipping ${width}px: source is only ${decoded.width}px wide.',
      );
      continue;
    }
    final resized = img.copyResize(
      decoded,
      width: width,
      interpolation: img.Interpolation.average,
    );
    final path = '${directory.path}/${sourceName}_${width}w.png';
    File(path).writeAsBytesSync(img.encodePng(resized));
    outputs.add((path: path, width: resized.width, height: resized.height));
  }

  if (outputs.isEmpty) {
    throw ArgumentError.value(
      widths,
      'widths',
      'must include at least one width below the source width '
          '(${decoded.width})',
    );
  }
  return outputs;
}

String _basenameWithoutExtension(String path) {
  final name = path.split(Platform.pathSeparator).last;
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? name : name.substring(0, dot);
}

const _usage = '''
Generates width-bucketed PNG variants for image_budget.

Usage:
  dart run tool/generate_variants.dart <source>... [options]

Options:
  --widths=400,800,1200   Widths to generate (default: 400,800,1200)
  --out-dir=<dir>         Output directory (default: next to the source)
  --help                  Show this help

The source can be PNG or JPEG. Variants are written as PNG so transparency
and lossless detail are preserved. Widths at or above the source width are
skipped.''';

class _Options {
  const _Options({
    required this.sourcePaths,
    required this.widths,
    required this.outputDirectory,
    required this.showHelp,
  });

  factory _Options.parse(List<String> arguments) {
    final sourcePaths = <String>[];
    var widths = const [400, 800, 1200];
    String? outputDirectory;
    var showHelp = false;

    for (final argument in arguments) {
      if (argument == '--help' || argument == '-h') {
        showHelp = true;
      } else if (argument.startsWith('--widths=')) {
        final raw = argument.substring('--widths='.length);
        widths = raw
            .split(',')
            .map((value) => int.tryParse(value.trim()))
            .map((value) {
          if (value == null || value <= 0) {
            throw ArgumentError.value(
              argument,
              '--widths',
              'must be a comma-separated list of positive integers',
            );
          }
          return value;
        }).toList(growable: false);
      } else if (argument.startsWith('--out-dir=')) {
        outputDirectory = argument.substring('--out-dir='.length);
      } else if (argument.startsWith('-')) {
        throw ArgumentError.value(argument, 'argument', 'unknown option');
      } else {
        sourcePaths.add(argument);
      }
    }

    return _Options(
      sourcePaths: sourcePaths,
      widths: widths,
      outputDirectory: outputDirectory,
      showHelp: showHelp,
    );
  }

  final List<String> sourcePaths;
  final List<int> widths;
  final String? outputDirectory;
  final bool showHelp;
}
