import 'dart:async';

// Use the SDK Material export for compatibility with Flutter 3.24.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:image_budget/image_budget.dart';

void main() => runApp(const ImageBudgetDemo());

enum _ImageMode { stock, budgeted }

class ImageBudgetDemo extends StatelessWidget {
  const ImageBudgetDemo({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Image Budget Demo',
        theme: ThemeData(colorSchemeSeed: Colors.teal),
        home: const _Feed(),
      );
}

class _Feed extends StatefulWidget {
  const _Feed();

  @override
  State<_Feed> createState() => _FeedState();
}

class _FeedState extends State<_Feed> {
  _ImageMode _mode = _ImageMode.stock;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Image Budget Demo')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                children: [
                  SegmentedButton<_ImageMode>(
                    segments: const [
                      ButtonSegment(
                          value: _ImageMode.stock, label: Text('Stock')),
                      ButtonSegment(
                        value: _ImageMode.budgeted,
                        label: Text('Budgeted'),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (selection) {
                      setState(() => _mode = selection.single);
                    },
                  ),
                  const _CacheReadout(),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: 24,
                      itemBuilder: (context, index) => _FeedCard(
                        index: index,
                        fixture: index.isEven ? _landscape : _portrait,
                        mode: _mode,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

typedef _Fixture = ({AssetImage image, Size size, String label});

const _Fixture _landscape = (
  image: AssetImage('assets/landscape.png'),
  size: Size(2400, 1600),
  label: 'Illustrated teal landscape with an amber sun',
);

const _Fixture _portrait = (
  image: AssetImage('assets/portrait.png'),
  size: Size(1600, 2400),
  label: 'Illustrated purple landscape with a pink sun',
);

class _FeedCard extends StatelessWidget {
  const _FeedCard({
    required this.index,
    required this.fixture,
    required this.mode,
  });

  final int index;
  final _Fixture fixture;
  final _ImageMode mode;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 16),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: switch (mode) {
                _ImageMode.stock => Image(
                    image: fixture.image,
                    fit: BoxFit.cover,
                    semanticLabel: fixture.label,
                  ),
                _ImageMode.budgeted => BudgetedImage(
                    image: fixture.image,
                    fit: BoxFit.cover,
                    sourcePixelSize: fixture.size,
                    semanticLabel: fixture.label,
                  ),
              },
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '${index + 1}. ${index.isEven ? 'Landscape' : 'Portrait'} '
                '· ${fixture.size.width.toInt()} × ${fixture.size.height.toInt()} px',
              ),
            ),
          ],
        ),
      );
}

class _CacheReadout extends StatefulWidget {
  const _CacheReadout();

  @override
  State<_CacheReadout> createState() => _CacheReadoutState();
}

class _CacheReadoutState extends State<_CacheReadout> {
  late final Timer _timer;
  late ImageBudgetStats _stats;

  @override
  void initState() {
    super.initState();
    _stats = ImageBudget.stats;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _stats = ImageBudget.stats);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String _mib(int bytes) => (bytes / (1 << 20)).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          'Shared Flutter cache: ${_mib(_stats.cachedBytes)} / '
          '${_mib(_stats.maxCachedBytes)} MiB\n'
          '${_stats.cachedEntries} cached · ${_stats.liveImages} live · '
          '${_stats.pendingImages} pending',
          textAlign: TextAlign.center,
        ),
      );
}
