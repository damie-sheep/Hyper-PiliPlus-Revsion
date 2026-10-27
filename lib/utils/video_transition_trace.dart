import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/scheduler.dart';

/// Opt-in device diagnostics. Never log media URLs, account data or tokens.
const videoTransitionTraceEnabled = bool.fromEnvironment(
  'VIDEO_TRANSITION_TRACE',
);
final _transitionClock = Stopwatch()..start();
final _tracedTransitions = <Object?>{};
final _lastProgress = <Object?, int>{};

void _traceFrames(List<FrameTiming> frames) {
  for (final frame in frames) {
    debugPrint(
      'VideoTransition t=${_transitionClock.elapsedMilliseconds}ms '
      'frame buildUs=${frame.buildDuration.inMicroseconds} '
      'rasterUs=${frame.rasterDuration.inMicroseconds} '
      'totalUs=${frame.totalSpan.inMicroseconds}',
    );
  }
}

void beginVideoTransitionTrace(Object? owner) {
  if (!videoTransitionTraceEnabled) return;
  if (_tracedTransitions.isEmpty) {
    SchedulerBinding.instance.addTimingsCallback(_traceFrames);
  }
  _tracedTransitions.add(owner);
}

void endVideoTransitionTrace(Object? owner) {
  if (!videoTransitionTraceEnabled) return;
  _lastProgress.remove(owner);
  if (!_tracedTransitions.remove(owner)) return;
  if (_tracedTransitions.isEmpty) {
    SchedulerBinding.instance.removeTimingsCallback(_traceFrames);
  }
}

void traceVideoTransitionProgress(Object? owner, double progress) {
  if (!videoTransitionTraceEnabled) return;
  final now = _transitionClock.elapsedMilliseconds;
  final previous = _lastProgress[owner];
  _lastProgress[owner] = now;
  traceVideoTransition(
    owner,
    'route:progress value=${progress.toStringAsFixed(3)} '
    'gapMs=${previous == null ? 0 : now - previous}',
  );
}

void traceVideoTransition(Object? owner, String event) {
  if (!videoTransitionTraceEnabled) return;
  debugPrint(
    'VideoTransition t=${_transitionClock.elapsedMilliseconds}ms '
    'owner=${identityHashCode(owner)} $event',
  );
}
