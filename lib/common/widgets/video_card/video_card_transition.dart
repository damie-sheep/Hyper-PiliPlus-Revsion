import 'dart:async' show Completer, unawaited;
import 'dart:ui' as ui show Image;

import 'package:PiliPlus/common/widgets/video_card/video_transition_geometry.dart';
import 'package:PiliPlus/utils/android/android_helper.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show SchedulerPhase;
import 'package:get/get.dart' show GetPageRoute;
import 'package:material_ui/material_ui.dart';

const int videoCoverDecodeWidth = 640;
const Duration videoPageTransitionDuration = Duration(milliseconds: 680);
const Duration videoPageReverseTransitionDuration = Duration(milliseconds: 320);
({Object tag, _VideoCardHeroState source, DateTime time})? _pendingTransition;
final _enteringVideoPages = <Object, Completer<bool>>{};

Future<bool> waitForVideoPageEntry(Object? tag) async =>
    await _enteringVideoPages[tag]?.future ?? true;

bool hasPendingVideoCardTransition(Object tag) {
  final pending = _pendingTransition;
  return pending != null &&
      pending.tag == tag &&
      pending.source.mounted &&
      pending.source.widget.tag == tag &&
      DateTime.now().difference(pending.time) < const Duration(seconds: 2);
}

Color transitionBackgroundOf(BuildContext context) {
  Color? result;
  context.visitAncestorElements((element) {
    final Color? color = switch (element.widget) {
      Material(:final type, :final color)
          when type != MaterialType.transparency =>
        color ?? Theme.of(element).canvasColor,
      ColoredBox(:final color) => color,
      DecoratedBox(decoration: BoxDecoration(:final color)) => color,
      _ => null,
    };
    if (color != null && color.a == 1) {
      result = color;
      return false;
    }
    return true;
  });
  return result ?? Theme.of(context).scaffoldBackgroundColor;
}

/// Retain GetX controller ownership and native predictive-back integration.
class VideoPageTransitionRoute<T> extends GetPageRoute<T> {
  VideoPageTransitionRoute({required WidgetBuilder builder, super.settings})
    : super(page: () => Builder(builder: builder));

  bool _gestureCommitted = false;
  AnimationStatusListener? _gestureCompletion;
  final _entryReady = Completer<bool>();
  Object? get _entryTag => (settings.arguments as Map?)?['heroTag'];

  @override
  void install() {
    super.install();
    if (_entryTag case final tag?) _enteringVideoPages[tag] = _entryReady;
    controller
      ?..addStatusListener(_entryStatus)
      ..addListener(_entryProgress);
  }

  void _entryProgress() {
    if (controller?.status == AnimationStatus.forward &&
        controller!.value >= 0.08) {
      _finishEntry(true);
    }
  }

  void _entryStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _finishEntry(true);
  }

  void _finishEntry(bool entered) {
    if (!_entryReady.isCompleted) _entryReady.complete(entered);
  }

  @override
  bool didPop(T? result) {
    final popped = super.didPop(result);
    if (popped) _finishEntry(false);
    return popped;
  }

  @override
  void handleStartBackGesture({double progress = 0.0}) {
    _gestureCommitted = false;
    super.handleStartBackGesture(progress: progress);
  }

  @override
  void handleCommitBackGesture() {
    if (_gestureCommitted || !popGestureInProgress) return;
    _gestureCommitted = true;
    final owner = navigator;
    if (isCurrent) owner?.pop();
    // Continue from the dragged value; the SDK default restarts from 1.
    final animationController = controller;
    void finish() {
      if (_gestureCompletion case final listener?) {
        animationController?.removeStatusListener(listener);
        _gestureCompletion = null;
      }
      if (owner?.userGestureInProgress == true) owner!.didStopUserGesture();
    }

    if (animationController?.isAnimating ?? false) {
      _gestureCompletion = (status) {
        if (status == AnimationStatus.dismissed ||
            status == AnimationStatus.completed) {
          finish();
        }
      };
      animationController!.addStatusListener(_gestureCompletion!);
    } else {
      finish();
    }
  }

  @override
  void dispose() {
    _finishEntry(false);
    controller
      ?..removeStatusListener(_entryStatus)
      ..removeListener(_entryProgress);
    if (identical(_enteringVideoPages[_entryTag], _entryReady)) {
      _enteringVideoPages.remove(_entryTag);
    }
    if (_gestureCompletion case final listener?) {
      controller?.removeStatusListener(listener);
    }
    super.dispose();
  }

  @override
  Duration get transitionDuration => videoPageTransitionDuration;
  @override
  Duration get reverseTransitionDuration => videoPageReverseTransitionDuration;
  @override
  DelegatedTransitionBuilder? get delegatedTransition => null;
  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

enum VideoTransitionPart { cover, tabs, owner, title }

/// Marks the actual painted child, preserving rich text, line breaks and scale.
class VideoTransitionSourcePart extends SingleChildRenderObjectWidget {
  const VideoTransitionSourcePart({
    super.key,
    required this.part,
    required super.child,
  });
  final VideoTransitionPart part;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSourcePart(part);
  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderSourcePart).part = part;
  }
}

class _RenderSourcePart extends RenderRepaintBoundary {
  _RenderSourcePart(this.part);
  VideoTransitionPart part;
}

class _SourceCardBoundary extends SingleChildRenderObjectWidget {
  const _SourceCardBoundary({super.key, required super.child});
  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSourceCard();
}

class _RenderSourceCard extends RenderRepaintBoundary {}

class VideoTransitionTargetPart extends SingleChildRenderObjectWidget {
  const VideoTransitionTargetPart({
    super.key,
    required this.part,
    required super.child,
  });
  final VideoTransitionPart part;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTargetPart(part);
  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderTargetPart).part = part;
  }
}

class _RenderTargetPart extends RenderProxyBox {
  _RenderTargetPart(this.part);
  VideoTransitionPart part;
  _RenderVideoStage? _stage;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void performLayout() {
    super.performLayout();
    _unregister();
    RenderObject? ancestor = parent;
    while (ancestor != null && ancestor is! _RenderVideoStage) {
      ancestor = ancestor.parent;
    }
    if (ancestor is _RenderVideoStage) {
      _stage = ancestor;
      ancestor.targets[part] = this;
    }
  }

  void _unregister() {
    if (identical(_stage?.targets[part], this)) _stage?.targets.remove(part);
    _stage = null;
  }

  @override
  void detach() {
    _unregister();
    super.detach();
  }

  double get _opacity =>
      part == VideoTransitionPart.title &&
          _stage?.snapshot?.parts[VideoTransitionPart.title] != null
      ? _stage!.geometry.targetTitleOpacity
      : 1;

  @override
  void paint(PaintingContext context, Offset offset) {
    final opacity = _opacity;
    if (opacity == 1) {
      super.paint(context, offset);
    } else if (opacity > 0) {
      context.pushOpacity(offset, (opacity * 255).round(), super.paint);
    }
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      _opacity > 0 && super.hitTest(result, position: position);
}

RenderParagraph? _paragraphOf(RenderObject root) {
  if (root is RenderParagraph) return root;
  RenderParagraph? paragraph;
  root.visitChildren((child) => paragraph ??= _paragraphOf(child));
  return paragraph;
}

double _baselineOf(RenderBox box) {
  final paragraph = _paragraphOf(box);
  if (paragraph == null) return 0;
  return paragraph.localToGlobal(Offset.zero, ancestor: box).dy +
      (paragraph.getDryBaseline(
            paragraph.constraints,
            TextBaseline.alphabetic,
          ) ??
          0);
}

class _PartImage {
  _PartImage(this.image, this.rect, this.baseline);
  final ui.Image image;
  final Rect rect;
  final double baseline;
}

class _CardSnapshot {
  _CardSnapshot(this.image, this.rect, this.color, this.parts);
  final ui.Image image;
  final Rect rect;
  final Color color;
  final Map<VideoTransitionPart, _PartImage> parts;

  void dispose() {
    image.dispose();
    for (final part in parts.values) {
      part.image.dispose();
    }
  }
}

/// Legacy public name, now a source recorder with no card/cover Hero flights.
/// Image-preview Heroes inside the child keep their original ownership.
class VideoCardHero extends StatefulWidget {
  const VideoCardHero({
    super.key,
    required this.tag,
    required this.surfaceColor,
    required this.child,
  });
  final Object tag;
  final Color surfaceColor;
  final Widget child;

  @override
  State<VideoCardHero> createState() => _VideoCardHeroState();
}

class _VideoCardHeroState extends State<VideoCardHero> {
  final _boundary = GlobalKey();
  bool _covered = false;

  RenderRepaintBoundary? get _box =>
      _boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;

  Rect? get rect {
    final box = _box;
    return box != null && box.attached && box.hasSize
        ? MatrixUtils.transformRect(
            box.getTransformTo(null),
            Offset.zero & box.size,
          )
        : null;
  }

  _CardSnapshot? capture() {
    final box = _box;
    final bounds = rect;
    if (box == null || bounds == null || bounds.isEmpty) return null;
    // Capture only the clicked card. Bound texture size even for tall dynamics.
    final ratio = (1200 / box.size.longestSide).clamp(0.1, 2.0);
    ui.Image? image;
    final parts = <VideoTransitionPart, _PartImage>{};
    try {
      image = box.toImageSync(pixelRatio: ratio);
      void visit(RenderObject object) {
        // A dynamic may itself contain a video card. Its parts belong to that
        // card, not to the outer dynamic/article transition.
        if (object is _RenderSourceCard) return;
        if (object is _RenderSourcePart &&
            object.hasSize &&
            !object.size.isEmpty) {
          final image = object.toImageSync(pixelRatio: ratio);
          final rect = MatrixUtils.transformRect(
            object.getTransformTo(null),
            Offset.zero & object.size,
          );
          parts.remove(object.part)?.image.dispose();
          parts[object.part] = _PartImage(
            image,
            rect,
            object.localToGlobal(Offset(0, _baselineOf(object))).dy - rect.top,
          );
        } else {
          object.visitChildren(visit);
        }
      }

      box.visitChildren(visit);
      return _CardSnapshot(image, bounds, widget.surfaceColor, parts);
    } catch (error) {
      assert(() {
        debugPrint('Video transition source unavailable: $error');
        return true;
      }());
      image?.dispose();
      for (final part in parts.values) {
        part.image.dispose();
      }
      // Unpainted / invalid sources fall back to the live detail page.
      return null;
    }
  }

  void cover(bool value) {
    void update() {
      if (mounted && _covered != value) setState(() => _covered = value);
    }

    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => update());
    } else {
      update();
    }
  }

  @override
  void dispose() {
    if (identical(_pendingTransition?.source, this)) _pendingTransition = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _pendingTransition = (
      tag: widget.tag,
      source: this,
      time: DateTime.now(),
    ),
    child: IgnorePointer(
      ignoring: _covered,
      child: Opacity(
        opacity: _covered ? 0 : 1,
        child: _SourceCardBoundary(key: _boundary, child: widget.child),
      ),
    ),
  );
}

/// Late lists stay mounted; the first-screen skeleton is outside this layer.
class VideoTransitionLayer extends StatelessWidget {
  const VideoTransitionLayer({
    super.key,
    required this.child,
    this.sliver = false,
  });
  final Widget child;
  final bool sliver;

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    final animation = route is VideoPageTransitionRoute
        ? route.animation
        : null;
    if (animation == null) return child;
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final expansion = Curves.easeInOutCubic.transform(animation.value);
        final opacity = const Interval(0.55, 0.95).transform(expansion);
        return sliver
            ? SliverOpacity(opacity: opacity, sliver: child!)
            : IgnorePointer(
                ignoring: opacity == 0,
                child: Opacity(opacity: opacity, child: child),
              );
      },
    );
  }
}

class VideoPageHeroTarget extends StatefulWidget {
  const VideoPageHeroTarget({
    super.key,
    required this.tag,
    required this.surfaceColor,
    required this.child,
  });
  final Object tag;
  final Color surfaceColor;
  final Widget child;

  @override
  State<VideoPageHeroTarget> createState() => _VideoPageHeroTargetState();
}

class _VideoPageHeroTargetState extends State<VideoPageHeroTarget> {
  _VideoCardHeroState? _source;
  _CardSnapshot? _snapshot;
  Animation<double>? _animation;
  ModalRoute<dynamic>? _route;
  Rect? _returnRect;
  Size? _viewport;
  bool _entryCompleted = false;
  bool _returnAnchored = false;
  bool _fallback = false;
  bool _samplingPaused = false;

  @override
  void initState() {
    super.initState();
    if (hasPendingVideoCardTransition(widget.tag)) {
      _source = _pendingTransition!.source;
      _pendingTransition = null;
      _snapshot = _source!.capture();
      if (_snapshot != null) _source!.cover(true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    final animation = _route is VideoPageTransitionRoute
        ? _route!.animation
        : null;
    if (identical(animation, _animation)) return;
    _animation?.removeStatusListener(_status);
    _animation = animation;
    animation?.addStatusListener(_status);
    if (animation != null) _status(animation.status);
  }

  void _status(AnimationStatus status) {
    if (status == AnimationStatus.completed && _route?.offstage == false) {
      _entryCompleted = true;
      _returnAnchored = false;
    }
    final pause =
        _snapshot != null &&
        (status == AnimationStatus.forward ||
            status == AnimationStatus.reverse);
    if (pause != _samplingPaused) {
      _samplingPaused = pause;
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        unawaited(PiliAndroidHelper.setMiuixBackdropSamplingPaused(pause));
      }
    }
  }

  void _anchorReturn(Size viewport) {
    if (!_entryCompleted || _returnAnchored) return;
    _returnAnchored = true;
    final source = _source;
    final rect = source?.mounted == true && source!.widget.tag == widget.tag
        ? source.rect
        : null;
    final stageBox = context.findRenderObject();
    final origin = stageBox is RenderBox && stageBox.hasSize
        ? stageBox.localToGlobal(Offset.zero)
        : Offset.zero;
    if (rect == null ||
        rect.intersect(origin & viewport).isEmpty ||
        rect.size != _snapshot?.rect.size) {
      _fallback = true;
      _source?.cover(false);
    } else {
      _returnRect = rect;
    }
  }

  @override
  void dispose() {
    _animation?.removeStatusListener(_status);
    _source?.cover(false);
    _snapshot?.dispose();
    if (_samplingPaused &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      unawaited(PiliAndroidHelper.setMiuixBackdropSamplingPaused(false));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      if (_viewport != null && _viewport != size) {
        _fallback = true;
        _source?.cover(false);
      }
      _viewport = size;
      return AnimatedBuilder(
        animation: _animation ?? const AlwaysStoppedAnimation(1.0),
        child: RepaintBoundary(child: widget.child),
        builder: (context, child) {
          final animation = _animation;
          if (animation?.status == AnimationStatus.reverse ||
              (_route?.popGestureInProgress ?? false)) {
            _anchorReturn(size);
          }
          return _VideoStage(
            key: const ValueKey('video-transition-stage'),
            snapshot: _animation == null || _fallback ? null : _snapshot,
            sourceRect: _returnRect ?? _snapshot?.rect,
            progress: animation?.value ?? 1,
            fallback: _fallback,
            color: widget.surfaceColor,
            child: child!,
          );
        },
      );
    },
  );
}

class _VideoStage extends SingleChildRenderObjectWidget {
  const _VideoStage({
    super.key,
    required this.snapshot,
    required this.sourceRect,
    required this.progress,
    required this.fallback,
    required this.color,
    required super.child,
  });
  final _CardSnapshot? snapshot;
  final Rect? sourceRect;
  final double progress;
  final bool fallback;
  final Color color;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderVideoStage()..configure(this);
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderVideoStage renderObject,
  ) => renderObject.configure(this);
}

class _RenderVideoStage extends RenderProxyBox {
  final targets = <VideoTransitionPart, _RenderTargetPart>{};
  _CardSnapshot? snapshot;
  Rect? _sourceRect;
  double _progress = 1;
  bool _fallback = false;
  Color _color = Colors.transparent;

  void configure(_VideoStage widget) {
    snapshot = widget.snapshot;
    _sourceRect = widget.sourceRect;
    _progress = widget.progress;
    _fallback = widget.fallback;
    _color = widget.color;
    targets[VideoTransitionPart.title]?.markNeedsPaint();
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  @override
  bool get alwaysNeedsCompositing => true;

  VideoTransitionGeometry get geometry => VideoTransitionGeometry(
    source: (_sourceRect ?? (localToGlobal(Offset.zero) & size)).shift(
      -localToGlobal(Offset.zero),
    ),
    viewport: size,
    progress: _progress,
  );

  Matrix4 get _transform {
    if (snapshot == null) return Matrix4.identity();
    final frame = geometry;
    return Matrix4.identity()
      ..translateByDouble(frame.container.left, frame.container.top, 0, 1)
      ..scaleByDouble(frame.scale, frame.scale, 1, 1);
  }

  ({Rect rect, double baseline})? _target(VideoTransitionPart part) {
    final target = targets[part];
    if (target == null ||
        !target.attached ||
        !target.hasSize ||
        child == null) {
      return null;
    }
    RenderObject? ancestor = target.parent;
    while (ancestor != null && ancestor != child) {
      if (ancestor is RenderOffstage && ancestor.offstage) return null;
      ancestor = ancestor.parent;
    }
    final rect = MatrixUtils.transformRect(
      target.getTransformTo(child),
      Offset.zero & target.size,
    );
    if (rect.isEmpty || !rect.overlaps(Offset.zero & size)) return null;
    return (
      rect: rect,
      baseline: _baselineOf(target),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final source = snapshot;
    if (source == null) {
      if (_fallback && _progress < 1) {
        context.pushOpacity(offset, (_progress * 255).round(), super.paint);
      } else {
        super.paint(context, offset);
      }
      return;
    }
    final frame = geometry;
    final rect = frame.container;
    if (frame.expansion < 1) {
      context.canvas.drawRect(
        offset & size,
        Paint()..color = Colors.black.withValues(alpha: 0.16 * frame.expansion),
      );
    }
    context.pushClipRRect(
      needsCompositing,
      offset,
      rect,
      RRect.fromRectAndRadius(rect, Radius.circular(frame.radius)),
      (context, offset) {
        context.canvas.drawRect(rect.shift(offset), Paint()..color = _color);
        context.pushTransform(
          needsCompositing,
          offset,
          _transform,
          super.paint,
        );
        // Sources contain pixels only; never clone controllers or a live player.
        final canvas = context.canvas
          ..save()
          ..translate(offset.dx, offset.dy);
        _paintSource(canvas, source, frame);
        canvas.restore();
      },
    );
  }

  void _draw(Canvas canvas, ui.Image image, Rect rect, double opacity) {
    if (opacity <= 0 || rect.isEmpty) return;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      rect,
      Paint()
        ..color = Colors.white.withValues(alpha: opacity)
        ..filterQuality = FilterQuality.low,
    );
  }

  void _paintSource(
    Canvas canvas,
    _CardSnapshot source,
    VideoTransitionGeometry frame,
  ) {
    final rect = frame.container;
    final cardScale = rect.width / source.rect.width;
    final card = rect.topLeft & (source.rect.size * cardScale);
    final sourceShift =
        (_sourceRect ?? source.rect).topLeft -
        source.rect.topLeft -
        localToGlobal(Offset.zero);
    Rect inCard(Rect part) =>
        (rect.topLeft + (part.topLeft - source.rect.topLeft) * cardScale) &
        (part.size * cardScale);
    if (frame.remainderOpacity > 0) {
      // Preserve the source card's own surface behind transparent text at the
      // start, including light-list -> dark-detail transitions. It exits with
      // the other card decorations, before title handoff.
      canvas.drawRect(
        card,
        Paint()
          ..color = source.color.withValues(
            alpha: source.color.a * frame.remainderOpacity,
          ),
      );
      var remaining = Path()..addRect(card);
      for (final part in source.parts.values) {
        remaining = Path.combine(
          PathOperation.difference,
          remaining,
          Path()..addRect(inCard(part.rect)),
        );
      }
      canvas
        ..save()
        ..clipPath(remaining);
      _draw(canvas, source.image, card, frame.remainderOpacity);
      canvas.restore();
    }
    final cover = source.parts[VideoTransitionPart.cover];
    if (cover != null && frame.coverOpacity > 0) {
      final target = _target(VideoTransitionPart.cover);
      final from = cover.rect.shift(sourceShift);
      final destination = target == null
          ? inCard(cover.rect)
          : frame.mapRect(target.rect);
      final flight = Rect.lerp(
        from,
        destination,
        (frame.expansion / 0.28).clamp(0, 1),
      )!;
      // Uniform width scale, cropped to the moving cover slot when necessary.
      final imageRect =
          flight.topLeft &
          (cover.rect.size * (flight.width / cover.rect.width));
      canvas
        ..save()
        ..clipRect(flight);
      _draw(canvas, cover.image, imageRect, frame.coverOpacity);
      canvas.restore();
    }
    final title = source.parts[VideoTransitionPart.title];
    if (title != null && frame.sourceTitleOpacity > 0) {
      final target = _target(VideoTransitionPart.title);
      final from = title.rect.topLeft + sourceShift + Offset(0, title.baseline);
      final to = target == null
          ? inCard(title.rect).topLeft +
                Offset(0, title.baseline * frame.titleScale)
          : frame.mapPoint(target.rect.topLeft + Offset(0, target.baseline));
      final baseline = Offset.lerp(from, to, frame.titleTravel)!;
      final top = baseline - Offset(0, title.baseline * frame.titleScale);
      _draw(
        canvas,
        title.image,
        top & (title.rect.size * frame.titleScale),
        frame.sourceTitleOpacity,
      );
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (snapshot != null &&
        !RRect.fromRectAndRadius(
          geometry.container,
          Radius.circular(geometry.radius),
        ).contains(position)) {
      return false;
    }
    return result.addWithPaintTransform(
      transform: _transform,
      position: position,
      hitTest: (result, position) =>
          super.hitTestChildren(result, position: position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      transform.multiply(_transform);
}
