import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ui' show FramePhase;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Compile-time opt in. Never record media URLs, account identifiers or tokens.
const videoTransitionTraceEnabled = bool.fromEnvironment(
  'VIDEO_TRANSITION_TRACE',
);
const videoTransitionMarkerEnabled = bool.fromEnvironment(
  'VIDEO_TRANSITION_MARKER',
);
final _clock = Stopwatch()..start();
final _owners = <Object?>{};
final _lastProgress = <Object?, int>{};
final _buffer = VideoTransitionTraceBuffer();
Timer? _flush;
bool _listening = false;
bool get videoTransitionTraceCollecting =>
    videoTransitionTraceEnabled && _listening;
int _action = 0;

class VideoTransitionTraceBuffer {
  VideoTransitionTraceBuffer({this.capacity = 1024});
  final int capacity;
  final _events = ListQueue<Map<String, Object?>>();
  int dropped = 0;
  void add(Map<String, Object?> event) {
    if (_events.length >= capacity) {
      _events.removeFirst();
      dropped++;
    }
    _events.addLast(event);
  }

  Map<String, Object?> drain() {
    final result = <String, Object?>{
      'dropped': dropped,
      'events': _events.toList(),
    };
    _events.clear();
    dropped = 0;
    return result;
  }
}

void recordVideoTransition(
  Object? owner,
  String event, [
  Map<String, Object?>? fields,
]) {
  if (!videoTransitionTraceEnabled) return;
  _buffer.add({
    'tUs': _clock.elapsedMicroseconds,
    'action': _action,
    'owner': identityHashCode(owner),
    'event': event,
    ...?fields,
  });
  if (_owners.isEmpty) _scheduleFlush();
}

void _traceFrames(List<FrameTiming> frames) {
  for (final frame in frames) {
    recordVideoTransition(null, 'frame', {
      'frame': frame.frameNumber,
      for (final phase in FramePhase.values)
        phase.name: frame.timestampInMicroseconds(phase),
      'buildUs': frame.buildDuration.inMicroseconds,
      'rasterUs': frame.rasterDuration.inMicroseconds,
      'totalUs': frame.totalSpan.inMicroseconds,
    });
  }
}

Future<void> _nativeDiagnostics({
  required bool enabled,
  required bool drain,
}) async {
  final sent = _clock.elapsedMicroseconds;
  try {
    final result =
        await const MethodChannel('com.alexmercerind/media_kit_video')
            .invokeMethod<Object?>('VideoOutputManager.Diagnostics', {
              'enabled': enabled,
              'drain': drain,
            })
            .timeout(const Duration(milliseconds: 200));
    final received = _clock.elapsedMicroseconds;
    final native = result is Map ? result : null;
    recordVideoTransition(null, 'native:clock-and-events', {
      'sentUs': sent,
      'receivedUs': received,
      'midpointUs': (sent + received) ~/ 2,
      'uncertaintyUs': (received - sent) ~/ 2,
      'nativeUs': native?['nativeUs'],
      'dropped': native?['dropped'],
    });
    if (native?['events'] case final List events) {
      for (final event in events) {
        recordVideoTransition(null, 'native:event', {'native': event});
      }
    }
  } catch (_) {
    recordVideoTransition(null, 'native:diagnostics-unavailable');
  }
}

void _scheduleFlush() {
  _flush ??= Timer(const Duration(milliseconds: 500), () async {
    if (_owners.isNotEmpty) {
      _flush = null;
      return;
    }
    if (_listening) {
      SchedulerBinding.instance.removeTimingsCallback(_traceFrames);
      _listening = false;
    }
    await _nativeDiagnostics(enabled: false, drain: true);
    _flush = null;
    if (_owners.isNotEmpty) {
      unawaited(_nativeDiagnostics(enabled: true, drain: false));
      return;
    }
    final batch = _buffer.drain();
    debugPrint('VideoTransition batch dropped=${batch['dropped']}');
    // Format and export after navigation, never inside paint.
    for (final event in batch['events']! as List) {
      debugPrint('VideoTransition ${jsonEncode(event)}');
    }
  });
}

void beginVideoTransitionTrace(Object? owner) {
  if (!videoTransitionTraceEnabled) return;
  _flush?.cancel();
  _flush = null;
  if (_owners.isEmpty) {
    _action++;
    if (!_listening) {
      SchedulerBinding.instance.addTimingsCallback(_traceFrames);
      _listening = true;
    }
    unawaited(_nativeDiagnostics(enabled: true, drain: false));
  }
  _owners.add(owner);
}

void endVideoTransitionTrace(Object? owner) {
  if (!videoTransitionTraceEnabled) return;
  _lastProgress.remove(owner);
  _owners.remove(owner);
  if (_owners.isEmpty) _scheduleFlush();
}

void traceVideoTransitionProgress(Object? owner, double progress) {
  if (!videoTransitionTraceEnabled) return;
  final now = _clock.elapsedMicroseconds;
  final previous = _lastProgress[owner];
  _lastProgress[owner] = now;
  recordVideoTransition(owner, 'route:progress', {
    'raw': progress,
    'gapUs': previous == null ? 0 : now - previous,
    'engineUs':
        SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds,
  });
}

void traceVideoTransition(Object? owner, String event) =>
    recordVideoTransition(owner, event);
