import 'dart:ui' show lerpDouble;

import 'package:flutter/animation.dart';

enum VideoTransitionMode { homeCard, detailRelated }

/// One coordinate system for both directions and interrupted gestures. Track
/// intervals refer to visible expansion, rather than to elapsed route time.
class VideoTransitionGeometry {
  VideoTransitionGeometry({
    required this.source,
    required this.viewport,
    required double progress,
    this.mode = VideoTransitionMode.homeCard,
    this.returnStart,
    this.contentTop = 0,
  }) : expansion =
           (mode == VideoTransitionMode.detailRelated
                   ? Curves.easeInOut
                   : Curves.easeInOutCubic)
               .transform(progress.clamp(0, 1));

  final Rect source;
  final Size viewport;
  final double expansion;
  final VideoTransitionMode mode;
  final double? returnStart;
  final double contentTop;

  double get _startExpansion => Curves.easeInOut.transform(returnStart ?? 1);
  bool get returning =>
      mode == VideoTransitionMode.detailRelated &&
      returnStart != null &&
      expansion <= _startExpansion;
  double get returnProgress => returning
      ? (1 - expansion / _startExpansion.clamp(0.000001, 1)).clamp(0, 1)
      : 0;
  Rect get contentBounds => Rect.fromLTWH(
    0,
    paintContentTop,
    viewport.width,
    (viewport.height - paintContentTop).clamp(0, double.infinity),
  );
  // Interrupted entry releases its already-moving chrome continuously.
  double get paintContentTop => returning && _startExpansion < 1
      ? contentTop * _returnTrack(0, .20)
      : contentTop;
  bool get separateChrome => returning && paintContentTop > 0;
  Rect get bannerRect =>
      container.topLeft & (source.size * (container.width / source.width));
  double _returnTrack(double a, double b) =>
      Interval(a, b, curve: Curves.easeInOutCubic).transform(returnProgress);
  double get mediaOpacity => 1 - _returnTrack(.04, .62);
  double get bodyOpacity => 1 - _returnTrack(0, .45);
  double get panelOpacity => 1 - _returnTrack(.35, .78);
  double get bannerOpacity => returning
      ? lerpDouble(
          1 -
              const Interval(
                0,
                .12,
                curve: Curves.easeInOutCubic,
              ).transform(_startExpansion),
          1,
          _returnTrack(.08, .48),
        )!
      : relatedSourceOpacity;

  Rect get container {
    if (!returning) {
      return Rect.lerp(source, Offset.zero & viewport, expansion)!;
    }
    final start = Rect.lerp(source, Offset.zero & viewport, _startExpansion)!;
    final inset = paintContentTop * start.width / viewport.width;
    final effective = Rect.fromLTRB(
      start.left,
      start.top + inset,
      start.right,
      start.bottom,
    );
    return Rect.lerp(effective, source, returnProgress)!;
  }

  double get scale => container.width / viewport.width;
  double get radius => 12 * (1 - expansion) + 64 * expansion * (1 - expansion);
  double get remainderOpacity => 1 - _track(0.04, 0.28);
  double get coverOpacity => 1 - _track(0.05, 0.28);
  double get sourceTitleOpacity => 1 - _track(0, 0.50);
  double get targetTitleOpacity => _track(0.18, 0.50);
  double get sourceInformationOpacity => 1 - _track(0, 0.20);
  double get targetInformationOpacity => _track(0.20, 0.38);
  Offset get informationTravel => Offset(0, -16 * _track(0, 0.20));
  double get relatedSourceOpacity => 1 - _track(0, 0.12);
  double get titleTravel => _track(0, 0.30);
  double get titleScale => lerpDouble(1, 1.30, _track(0, 0.50))!;
  double get informationOpacity => _track(0, 0.32);
  double get tabsOpacity => _track(0, 0.24);
  double get lowerReveal => _track(0.18, 0.92);
  double get lowerOpacity => _track(0.18, 0.48);

  /// Both the source image and the live player paint into this single slot.
  /// The source follows the carrier from the first frame, even for a horizontal
  /// card whose cover occupies only part of its width.
  Rect mediaRect({required Rect sourceCover, required Rect targetCover}) {
    final cardScale = container.width / source.width;
    final from =
        (container.topLeft +
            (sourceCover.topLeft - source.topLeft) * cardScale) &
        (sourceCover.size * cardScale);
    return Rect.lerp(from, mapRect(targetCover), _track(0, 0.28))!;
  }

  double _track(double begin, double end) =>
      Interval(begin, end, curve: Curves.easeInOutCubic).transform(expansion);

  Offset mapPoint(Offset point) =>
      container.topLeft +
      (point - (returning ? contentBounds.topLeft : Offset.zero)) * scale;
  Rect mapRect(Rect rect) => mapPoint(rect.topLeft) & (rect.size * scale);
}
