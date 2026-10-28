import 'package:PiliPlus/common/widgets/video_card/video_transition_paint_probe.dart';
import 'package:flutter/widgets.dart';
import 'package:PiliPlus/utils/video_transition_trace.dart';

/// Separates paint participation from visibility for the stage A comparison.
/// An opaque sibling does not prove that the GPU consumes the covered texture.
class VideoFrameGate extends StatelessWidget {
  const VideoFrameGate({
    super.key,
    required this.ready,
    required this.livePaint,
    required this.fill,
    required this.owner,
    required this.child,
  });

  final bool ready;
  final bool livePaint;
  final Color fill;
  final Object owner;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    recordVideoTransition(owner, 'live:gate', {
      'ready': ready,
      'livePaint': livePaint,
    });
    if (!livePaint) return Opacity(opacity: ready ? 1 : 0, child: child);
    return Stack(
      fit: StackFit.passthrough,
      alignment: Alignment.topLeft,
      children: [
        VideoTransitionPaintProbe(
          owner: owner,
          token: owner,
          event: 'live:first-paint',
          child: child,
        ),
        if (!ready)
          Positioned.fill(
            child: IgnorePointer(child: ColoredBox(color: fill)),
          ),
      ],
    );
  }
}
