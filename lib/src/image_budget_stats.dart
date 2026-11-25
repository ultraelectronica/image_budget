import 'package:flutter/foundation.dart';

/// A snapshot of Flutter's shared decoded-image cache.
@immutable
class ImageBudgetStats {
  const ImageBudgetStats({
    required this.cachedBytes,
    required this.cachedEntries,
    required this.liveImages,
    required this.pendingImages,
    required this.maxCachedBytes,
    required this.maxEntries,
  });

  /// Bytes currently held by the image cache.
  final int cachedBytes;

  /// Number of entries currently held by the image cache.
  final int cachedEntries;

  /// Images still retained by widgets or listeners.
  final int liveImages;

  /// Images currently being loaded.
  final int pendingImages;

  /// Configured byte limit for the image cache.
  final int maxCachedBytes;

  /// Configured entry limit for the image cache.
  final int maxEntries;

  /// Whether the cache currently exceeds either configured limit.
  bool get isOverBudget =>
      cachedBytes > maxCachedBytes || cachedEntries > maxEntries;

  /// Fraction of the byte budget currently used, clamped to 0..1.
  double get byteUsage {
    if (maxCachedBytes <= 0) {
      return 0;
    }
    return (cachedBytes / maxCachedBytes).clamp(0.0, 1.0);
  }

  @override
  String toString() {
    return 'ImageBudgetStats(cachedBytes: $cachedBytes, '
        'cachedEntries: $cachedEntries, liveImages: $liveImages, '
        'pendingImages: $pendingImages, maxCachedBytes: $maxCachedBytes, '
        'maxEntries: $maxEntries)';
  }
}
