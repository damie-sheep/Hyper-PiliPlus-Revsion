import 'dart:ui' show lerpDouble;

import 'package:flutter/animation.dart';

/// One coordinate system for both directions and interrupted gestures. Track
/// intervals refer to visible expansion, rather than to elapsed route time.
class VideoTransitionGeometry {
  VideoTransitionGeometry({
    required this.source,
    required this.viewport,
    required double progress,
  }) : expansion = Curves.easeInOutCubic.transform(progress.clamp(0, 1));

  final Rect source;
  final Size viewport;
  final double expansion;

  Rect get container => Rect.lerp(source, Offset.zero & viewport, expansion)!;
  double get scale => container.width / viewport.width;
  double get radius => 12 * (1 - expansion) + 128 * expansion * (1 - expansion);
  double get remainderOpacity => 1 - _track(0, 0.18);
  double get coverOpacity => 1 - _track(0.05, 0.28);
  double get sourceTitleOpacity => 1 - _track(0.20, 0.50);
  double get targetTitleOpacity => _track(0.32, 0.50);
  double get titleTravel => _track(0, 0.30);
  double get titleScale => lerpDouble(1, 1.30, _track(0, 0.50))!;

  double _track(double begin, double end) =>
      Interval(begin, end, curve: Curves.easeInOutCubic).transform(expansion);

  Offset mapPoint(Offset point) => container.topLeft + point * scale;
  Rect mapRect(Rect rect) => mapPoint(rect.topLeft) & (rect.size * scale);
}
