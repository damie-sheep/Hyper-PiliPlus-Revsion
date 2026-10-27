import 'package:PiliPlus/utils/video_transition_trace.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// One diagnostic event when the retained image actually joins a painted frame.
class VideoTransitionPaintProbe extends SingleChildRenderObjectWidget {
  const VideoTransitionPaintProbe({
    super.key,
    required this.owner,
    required this.token,
    required super.child,
  });
  final Object owner;
  final Object token;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _PaintProbe(owner, token);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderProxyBox renderObject,
  ) => (renderObject as _PaintProbe).update(owner, token);
}

class _PaintProbe extends RenderProxyBox {
  _PaintProbe(this.traceOwner, this.token);
  Object traceOwner;
  Object token;
  bool recorded = false;
  void update(Object owner, Object token) {
    traceOwner = owner;
    if (!identical(this.token, token)) {
      this.token = token;
      recorded = false;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (videoTransitionTraceEnabled && !recorded) {
      recorded = true;
      recordVideoTransition(traceOwner, 'retained:first-paint', {
        'image': identityHashCode(token),
      });
    }
  }
}
