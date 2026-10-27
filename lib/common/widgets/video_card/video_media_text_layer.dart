import 'dart:math' show min;

import 'package:PiliPlus/common/widgets/video_card/video_transition_geometry.dart';
import 'package:flutter/widgets.dart';

/// Only media text is clipped/faded. Controls, retry UI and gestures stay live.
class VideoMediaTextLayer extends StatefulWidget {
  const VideoMediaTextLayer({
    super.key,
    required this.ownsSource,
    required this.child,
  });
  final bool ownsSource;
  final Widget child;

  @override
  State<VideoMediaTextLayer> createState() => _VideoMediaTextLayerState();
}

class _VideoMediaTextLayerState extends State<VideoMediaTextLayer>
    with SingleTickerProviderStateMixin {
  late final _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 40),
  );
  ModalRoute<dynamic>? _route;
  bool _active = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (_route != route) {
      _listen(false);
      _route = route;
      _listen(true);
    }
    _update();
  }

  void _listen(bool add) {
    for (final animation in [_route?.animation, _route?.secondaryAnimation]) {
      if (add) {
        animation?.addListener(_update);
        animation?.addStatusListener(_status);
      } else {
        animation?.removeListener(_update);
        animation?.removeStatusListener(_status);
      }
    }
  }

  void _status(AnimationStatus status) => _update();

  @override
  void didUpdateWidget(VideoMediaTextLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  void _update() {
    final active =
        widget.ownsSource &&
        (_route == null ||
            (_route!.isCurrent &&
                _route!.animation?.status == AnimationStatus.completed &&
                (_route!.secondaryAnimation?.value ?? 0) == 0));
    if (_active != active) {
      _active = active;
      _fade.animateTo(active ? 1 : 0);
    }
    // Animation listeners can run without a parent rebuild (back gestures).
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _listen(false);
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => VideoMediaTextScope(
    active: _active,
    child: IgnorePointer(
      ignoring: !_active,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _fade,
          child: widget.child,
          builder: (context, child) {
            final expansion = VideoTransitionGeometry(
              source: Rect.zero,
              viewport: Size.zero,
              progress: _route?.animation?.value ?? 1,
            ).expansion;
            // Even a skipped frame cannot leave text over restored source info.
            final limit = widget.ownsSource && expansion > 0.38 ? 1.0 : 0.0;
            return Opacity(opacity: min(_fade.value, limit), child: child);
          },
        ),
      ),
    ),
  );
}

class VideoMediaTextScope extends InheritedWidget {
  const VideoMediaTextScope({
    super.key,
    required this.active,
    required super.child,
  });
  final bool active;
  static bool activeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<VideoMediaTextScope>()
          ?.active ??
      true;
  @override
  bool updateShouldNotify(VideoMediaTextScope oldWidget) =>
      active != oldWidget.active;
}
