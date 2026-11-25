# Image Budget demo

From `example/`, run `flutter run -d chrome` to open the demo or
`flutter build web` to compile it. Switch between **Stock** (`Image`) and
**Budgeted** (`BudgetedImage`) while scrolling the same feed. Both modes use
the same bundled images and the same `BoxFit.cover` crop. Budgeted mode
supplies each file's intrinsic pixel size and infers the display size from
the card's tight layout constraints.

The feed repeats two synthetic fixtures: a 2400 × 1600 landscape and a
1600 × 2400 portrait. To regenerate them, run `python3 tool/generate_fixtures.py`.

The readout reports Flutter's shared image cache, not total browser memory.
Changing modes does not clear that cache, and repeated cards reuse the same
assets. This is a usage demo, not a benchmark. Runtime savings on web have
not been verified.
