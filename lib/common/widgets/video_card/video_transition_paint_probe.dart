import 'package:PiliPlus/utils/video_transition_trace.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// One diagnostic event when the retained image actually joins a painted frame.
class VideoTransitionPaintProbe extends SingleChildRenderObjectWidget {
  const VideoTransitionPaintProbe({
    super.key,
    required this.owner,
    required this.token,
    this.event = 'retained:first-paint',
    required super.child,
  });
  final Object owner;
  final Object token;
  final String event;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _PaintProbe(owner, token, event);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderProxyBox renderObject,
  ) => (renderObject as _PaintProbe).update(owner, token, event);
}

class _PaintProbe extends RenderProxyBox {
  _PaintProbe(this.traceOwner, this.token, this.event);
  Object traceOwner;
  Object token;
  String event;
  bool recorded = false;
  void update(Object owner, Object token, String event) {
    traceOwner = owner;
    if (!identical(this.token, token) || this.event != event) {
      this.token = token;
      this.event = event;
      recorded = false;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (videoTransitionTraceEnabled && !recorded) {
      recorded = true;
      recordVideoTransition(traceOwner, event, {
        'image': identityHashCode(token),
      });
    }
  }
}
