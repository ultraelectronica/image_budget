# Use image_budget in an app

This guide adds `image_budget` to a Flutter app and replaces one image with
`BudgetedImage`.

The package is `0.1.0-dev` and is not on pub.dev. It has been profiled on one
Android phone, not iOS or web. Start with one screen.

## Add the dependency

If the package and app are sibling directories:

```yaml
# my_app/pubspec.yaml
dependencies:
  flutter:
    sdk: flutter
  image_budget:
    path: ../image_budget
```

For a Git dependency, use a commit or tag. The example uses `main`:

```yaml
dependencies:
  image_budget:
    git:
      url: https://github.com/ultraelectronica/image_budget.git
      ref: main # replace with a commit or tag
```

Run `flutter pub get`. No Android or iOS platform setup is required.

## Add an image

Put the file in the app and declare it:

```yaml
flutter:
  assets:
    - assets/photo.jpg
```

## Replace one image

```dart
import 'package:flutter/material.dart';
import 'package:image_budget/image_budget.dart';

void main() => runApp(const PhotoApp());

class PhotoApp extends StatelessWidget {
  const PhotoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: BudgetedImage(
                image: const AssetImage('assets/photo.jpg'),
                sourcePixelSize: const Size(4000, 3000),
                sourceFormat: ImageSourceFormat.jpeg,
                fit: BoxFit.cover,
                semanticLabel: 'A sample photo',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

`BudgetedImage` measures the box it receives, multiplies by the device pixel
ratio, and asks the codec for a bitmap near that size.

## Give it the source facts

Set `sourcePixelSize` to the image's real pixel dimensions. With it,
`BoxFit.cover`, `fitWidth`, and `fitHeight` can pick a decode size that keeps
the crop sharp. Without it, `cover` guesses and decodes extra pixels.

For an API image, keep the dimensions in the response:

```dart
BudgetedImage(
  image: NetworkImage(photo.url),
  sourcePixelSize: Size(photo.width, photo.height),
  sourceFormat: ImageSourceFormat.jpeg,
  fit: BoxFit.cover,
)
```

If the dimensions are unknown, omit `sourcePixelSize`. It still works, but
the decode is less precise.

Set `sourceFormat` to match the file:

| Source | Value | Effect |
|---|---|---|
| JPEG with known size | `ImageSourceFormat.jpeg` | Snaps to a native 1/8 scale. Can cut decode time. |
| PNG | `ImageSourceFormat.png` | Uses the exact target. Skips the quality margin. |
| Unknown | `ImageSourceFormat.auto` | Applies the margin without assuming a codec scale. |

`auto` is the default. Pass `png` for PNG or the default `qualityMargin` of
`1.25` asks for about 56% more pixels than needed.

PNG resizing still decodes the full source. If cold decode time matters,
generate smaller variants.

## Keep the layout bounded

`BudgetedImage` needs a finite size. `SizedBox`, `AspectRatio`, and `GridView`
tiles work. A bare `Column` child does not, because its height is unbounded.
Pass `displaySize` when the parent cannot provide one:

```dart
BudgetedImage(
  image: const AssetImage('assets/photo.jpg'),
  displaySize: const Size(400, 300),
  sourcePixelSize: const Size(4000, 3000),
  sourceFormat: ImageSourceFormat.jpeg,
  fit: BoxFit.cover,
)
```

## Set a cache limit, if needed

Flutter's decoded-image cache defaults to 100 MiB and 1000 entries. To set a
different limit, configure it once at startup:

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  ImageBudget.configure(
    maxCachedBytes: 48 << 20,
    maxEntries: 200,
  );

  runApp(const PhotoApp());
}
```

This changes the cache for the whole app. A tight limit can cause redecodes
when the user scrolls back, so start without it and set it after measuring.
`ImageBudget.stats` returns the current byte and entry counts.

## Generate PNG variants for decode-time wins

Pre-sized PNG files avoid decoding the full source. From the package root:

```sh
dart run tool/generate_variants.dart assets/photo.png --widths 400,800,1200
```

Add the generated files to the app and pass them as variants:

```dart
BudgetedImage(
  image: const AssetImage('assets/photo_1200w.png'),
  imageVariants: [
    ImageVariant(
      image: const AssetImage('assets/photo_400w.png'),
      pixelSize: const Size(400, 300),
    ),
    ImageVariant(
      image: const AssetImage('assets/photo_800w.png'),
      pixelSize: const Size(800, 600),
    ),
    ImageVariant(
      image: const AssetImage('assets/photo_1200w.png'),
      pixelSize: const Size(1200, 900),
    ),
  ],
  sourceFormat: ImageSourceFormat.png,
  qualityMargin: 1,
  fit: BoxFit.cover,
)
```

The widget uses the smallest variant that covers the target, or the largest
if none covers it. This adds build tooling and asset size. Use it only where
PNG decode time matters.

## Measure before rollout

Run in profile mode, not debug:

```sh
flutter run --profile
```

Compare `BudgetedImage` with your current image widget on the same screen,
with the same images and cache settings. Check decoded cache bytes, first
visible image time, scroll frame times, process RSS, and image sharpness
separately. A release build is the final check.
