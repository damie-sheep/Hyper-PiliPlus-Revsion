import 'package:flutter/foundation.dart' show debugPrint;

/// Opt-in device diagnostics. Never log media URLs, account data or tokens.
const videoTransitionTraceEnabled = bool.fromEnvironment(
  'VIDEO_TRANSITION_TRACE',
);
final _transitionClock = Stopwatch()..start();

void traceVideoTransition(Object? owner, String event) {
  if (!videoTransitionTraceEnabled) return;
  debugPrint(
    'VideoTransition t=${_transitionClock.elapsedMilliseconds}ms '
    'owner=${identityHashCode(owner)} $event',
  );
}
