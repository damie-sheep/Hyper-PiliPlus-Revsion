import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' show FramePhase;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:PiliPlus/utils/video_frame_experiment.dart';

/// Compile-time opt in. Never record media URLs, account identifiers or tokens.
const videoTransitionTraceEnabled = bool.fromEnvironment(
  'VIDEO_TRANSITION_TRACE',
);
const videoTransitionMarkerEnabled = bool.fromEnvironment(
  'VIDEO_TRANSITION_MARKER',
);
final _clock = Stopwatch()..start();
final _session = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
final _owners = <Object?>{};
final _lastProgress = <Object?, int>{};
final _buffer = VideoTransitionTraceBuffer();
Timer? _flush;
int _flushSerial = 0;
bool _listening = false;
bool get videoTransitionTraceCollecting =>
    videoTransitionTraceEnabled && _listening;
int _action = 0;
final _timingWindows = <VideoTimingWindow>[];

/// FrameTiming may arrive in a later action's batch. Attribute by engine time,
/// never by the action current when the callback happens to be delivered.
class VideoTimingWindow {
  VideoTimingWindow(this.action, this.startUs);
  final int action;
  final int startUs;
  int? endUs;
  int frames = 0;
  int sampledFrames = 0;
  bool sampleFrame() {
    frames++;
    // Preserve entry evidence on 120/144 Hz displays during the 8 s tail.
    // This is a declared prefix sample, never a full-window P95 claim.
    if (sampledFrames >= 180) return false;
    sampledFrames++;
    return true;
  }

  bool contains(int timestamp) =>
      timestamp >= startUs && (endUs == null || timestamp < endUs!);
}

int? videoTimingAction(List<VideoTimingWindow> windows, int timestamp) {
  for (final window in windows.reversed) {
    if (window.contains(timestamp)) return window.action;
  }
  return null;
}

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
    'session': _session,
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
    final engineUs = frame.timestampInMicroseconds(FramePhase.vsyncStart);
    final action = videoTimingAction(_timingWindows, engineUs);
    if (action == null) continue;
    final window = _timingWindows.firstWhere((w) => w.action == action);
    if (!window.sampleFrame()) continue;
    recordVideoTransition(null, 'frame', {
      'action': action,
      'callbackAction': _action,
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
  if (_flush != null) return;
  final serial = ++_flushSerial;
  // Includes native's 3 s wait and >=5 s of post-transition playback. Fixed,
  // bounded tail; stable per-frame events do not keep extending this timer.
  _flush = Timer(const Duration(seconds: 8), () async {
    if (serial != _flushSerial) return;
    if (_owners.isNotEmpty) {
      _flush = null;
      return;
    }
    if (_listening) {
      SchedulerBinding.instance.removeTimingsCallback(_traceFrames);
      _listening = false;
    }
    final closedAt = developer.Timeline.now;
    for (final window in _timingWindows) {
      window.endUs ??= closedAt;
      recordVideoTransition(null, 'timing:window', {
        'action': window.action,
        'startEngineUs': window.startUs,
        'endEngineUs': window.endUs,
        'frames': window.frames,
        'sampledFrames': window.sampledFrames,
        'omittedFrames': window.frames - window.sampledFrames,
        'sampling': 'first-180-per-action',
        'support': window.frames > 0 ? 'observed' : 'no-samples',
      });
    }
    await _nativeDiagnostics(enabled: false, drain: true);
    if (serial != _flushSerial) {
      if (_listening) {
        unawaited(_nativeDiagnostics(enabled: true, drain: false));
      }
      return;
    }
    _flush = null;
    if (_owners.isNotEmpty) {
      unawaited(_nativeDiagnostics(enabled: true, drain: false));
      return;
    }
    final batch = _buffer.drain();
    _timingWindows.clear();
    debugPrint('VideoTransition batch dropped=${batch['dropped']}');
    // Format and export after navigation, never inside paint.
    for (final event in batch['events']! as List) {
      debugPrint('VideoTransition ${jsonEncode(event)}');
    }
    debugPrint(
      'VideoTransition batch complete session=$_session events=${(batch['events']! as List).length}',
    );
  });
}

void beginVideoTransitionTrace(Object? owner) {
  if (!videoTransitionTraceEnabled) return;
  _flushSerial++;
  _flush?.cancel();
  _flush = null;
  if (_owners.isEmpty) {
    final start = developer.Timeline.now;
    if (_timingWindows.isNotEmpty) _timingWindows.last.endUs ??= start;
    _action++;
    _timingWindows.add(VideoTimingWindow(_action, start));
    // Keep metadata bounded even when the user navigates without waiting.
    if (_timingWindows.length > 32) _timingWindows.removeAt(0);
    if (!_listening) {
      SchedulerBinding.instance.addTimingsCallback(_traceFrames);
      _listening = true;
    }
    unawaited(_nativeDiagnostics(enabled: true, drain: false));
    recordVideoTransition(owner, 'timing:begin', {
      'startEngineUs': start,
      'variant': videoFrameExperiment.isEmpty
          ? 'baseline'
          : videoFrameExperiment,
      'tailMs': 8000,
    });
  }
  _owners.add(owner);
}

void endVideoTransitionTrace(Object? owner) {
  if (!videoTransitionTraceEnabled) return;
  recordVideoTransition(owner, 'timing:end');
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
