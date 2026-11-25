import 'package:flutter/painting.dart';

import 'image_budget_stats.dart';

/// Explicit configuration for Flutter's shared decoded-image cache.
///
/// Flutter's default cache is 1000 entries and 100 MiB. Call [configure] once
/// during startup to set a tighter budget:
///
/// ```dart
/// WidgetsFlutterBinding.ensureInitialized();
/// ImageBudget.configure(maxCachedBytes: 48 << 20, maxEntries: 200);
/// ```
///
/// The cache is shared by the current Flutter binding. A tighter limit can reduce memory held by
/// decoded images, but it can also cause redecodes when the user scrolls
/// back. Tune it in a profile build on a real device.
class ImageBudget {
  ImageBudget._();

  static int? _originalMaxCachedBytes;
  static int? _originalMaxEntries;
  static bool _configured = false;

  static ImageCache get _cache => PaintingBinding.instance.imageCache;

  /// Sets one or both cache limits and returns nothing.
  ///
  /// At least one limit is required. Both values must be greater than zero.
  /// The first call records the previous limits so [reset] can restore them.
  static void configure({int? maxCachedBytes, int? maxEntries}) {
    if (maxCachedBytes == null && maxEntries == null) {
      throw ArgumentError(
        'Provide maxCachedBytes, maxEntries, or both.',
      );
    }
    if (maxCachedBytes != null && maxCachedBytes <= 0) {
      throw ArgumentError.value(
        maxCachedBytes,
        'maxCachedBytes',
        'must be greater than 0',
      );
    }
    if (maxEntries != null && maxEntries <= 0) {
      throw ArgumentError.value(
        maxEntries,
        'maxEntries',
        'must be greater than 0',
      );
    }

    if (!_configured) {
      _originalMaxCachedBytes = _cache.maximumSizeBytes;
      _originalMaxEntries = _cache.maximumSize;
      _configured = true;
    }

    if (maxCachedBytes != null) {
      _cache.maximumSizeBytes = maxCachedBytes;
    }
    if (maxEntries != null) {
      _cache.maximumSize = maxEntries;
    }
  }

  /// A snapshot of the current cache state.
  static ImageBudgetStats get stats {
    final cache = _cache;
    return ImageBudgetStats(
      cachedBytes: cache.currentSizeBytes,
      cachedEntries: cache.currentSize,
      liveImages: cache.liveImageCount,
      pendingImages: cache.pendingImageCount,
      maxCachedBytes: cache.maximumSizeBytes,
      maxEntries: cache.maximumSize,
    );
  }

  /// Clears cached images.
  ///
  /// Images still referenced by widgets remain alive. This does not dispose
  /// live images and does not reset the configured limits.
  static void clear() {
    _cache.clear();
  }

  /// Restores the cache limits that existed before the first [configure] call.
  ///
  /// Restoring a lower limit can evict entries. Previously evicted images are
  /// not restored. If [configure] was never called, this is a no-op.
  static void reset() {
    if (!_configured) {
      return;
    }
    _cache.maximumSizeBytes = _originalMaxCachedBytes!;
    _cache.maximumSize = _originalMaxEntries!;
    _originalMaxCachedBytes = null;
    _originalMaxEntries = null;
    _configured = false;
  }
}
