import 'dart:async';
import 'dart:ui' as ui;

import 'package:PiliPlus/utils/video_transition_trace.dart';
import 'package:PiliPlus/utils/video_frame_experiment.dart';

import 'package:flutter/services.dart';

/// The repository Android overlay extends the pinned plugin without changing
/// its Dart API or the Pub cache. No URL or media identity crosses this bridge.
abstract final class VideoSurfaceBridge {
  static const _channel = MethodChannel('com.alexmercerind/media_kit_video');
  static Future<void>? _configuration;

  static Future<void> configureExperiment() async {
    if (videoFrameExperiment.isEmpty) return;
    await (_configuration ??= () async {
      final response = await _channel
          .invokeMapMethod<String, Object?>(
            'VideoOutputManager.ConfigureExperiment',
            {'variant': videoFrameExperiment},
          )
          .timeout(const Duration(seconds: 2));
      if (response?['version'] != 2 ||
          response?['variant'] != videoFrameExperiment) {
        throw StateError('Stage A native experiment configuration mismatch');
      }
      recordVideoTransition(null, 'experiment:configured', {
        ...?response,
      });
    }());
  }

  static Future<ui.Image?> captureFrame(int handle) async {
    traceVideoTransition(handle, 'capture:request');
    try {
      final bytes = await _channel
          .invokeMethod<Uint8List>(
            'VideoOutputManager.CaptureFrame',
            {'handle': '$handle', 'traceOwner': identityHashCode(handle)},
          )
          .timeout(const Duration(milliseconds: 250));
      recordVideoTransition(handle, 'capture:reply', {
        'bytes': bytes?.length ?? 0,
      });
      if (bytes == null || bytes.isEmpty) return null;
      traceVideoTransition(handle, 'capture:decode-start');
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final image = (await codec.getNextFrame()).image;
        recordVideoTransition(handle, 'capture:decode-end', {
          'width': image.width,
          'height': image.height,
        });
        if (image.width <= 1 || image.height <= 1) {
          image.dispose();
          return null;
        }
        return image;
      } finally {
        codec.dispose();
      }
    } catch (_) {
      traceVideoTransition(handle, 'capture:failed-or-timeout');
      return null;
    }
  }

  static Future<bool?> waitForSourceFrame(int handle, int generation) async {
    final outcome = await waitForSourceFrameOutcome(handle, generation);
    return outcome.status == 'candidate';
  }

  static Future<VideoSourceFrameOutcome> waitForSourceFrameOutcome(
    int handle,
    int generation,
  ) async {
    try {
      final value = await _channel
          .invokeMethod<Object?>(
            'VideoOutputManager.AwaitSourceFrame2',
            {
              'handle': '$handle',
              'generation': generation,
              'traceOwner': identityHashCode(handle),
            },
          )
          .timeout(const Duration(milliseconds: 3200));
      final outcome = VideoSourceFrameOutcome.parse(value, generation);
      recordVideoTransition(handle, 'frame:outcome', {
        'generation': generation,
        'status': outcome.status,
        ...outcome.fields,
      });
      return outcome;
    } on TimeoutException {
      recordVideoTransition(handle, 'frame:outcome', {
        'generation': generation,
        'status': 'bridge-timeout',
      });
      return const VideoSourceFrameOutcome('bridge-timeout');
    } catch (_) {
      recordVideoTransition(handle, 'frame:outcome', {
        'generation': generation,
        'status': 'unavailable',
      });
      return const VideoSourceFrameOutcome('unavailable');
    }
  }

  static Future<void> cancelSourceFrame(int handle, int generation) async {
    try {
      await _channel.invokeMethod<void>(
        'VideoOutputManager.CancelSourceFrame',
        {'handle': '$handle', 'generation': generation},
      );
    } catch (_) {
      // Output disposal also cancels native waiters.
    }
  }

  static Future<bool> isSourceFrameCurrent(
    int handle,
    int generation,
    VideoSourceFrameOutcome outcome,
  ) async {
    try {
      return await _channel
              .invokeMethod<bool>(
                'VideoOutputManager.IsSourceFrameCurrent',
                {
                  'handle': '$handle',
                  'generation': generation,
                  'outputEpoch': outcome.fields['outputEpoch'],
                  'surfaceEpoch': outcome.fields['surfaceEpoch'],
                },
              )
              .timeout(const Duration(milliseconds: 200)) ==
          true;
    } catch (_) {
      return false;
    }
  }
}

class VideoSourceFrameOutcome {
  const VideoSourceFrameOutcome(this.status, [this.fields = const {}]);
  final String status;
  final Map<String, Object?> fields;

  static VideoSourceFrameOutcome parse(Object? value, int generation) {
    if (value == null) return const VideoSourceFrameOutcome('unavailable');
    if (value is! Map ||
        value['version'] != 2 ||
        value['generation'] != generation ||
        value['status'] is! String ||
        value['outputEpoch'] is! int ||
        value['signal'] is! String) {
      return const VideoSourceFrameOutcome('protocol-mismatch');
    }
    const statuses = {
      'candidate',
      'cancelled',
      'timeout',
      'superseded',
      'disposed',
      'rejected',
      'unavailable',
    };
    if (!statuses.contains(value['status'])) {
      return const VideoSourceFrameOutcome('protocol-mismatch');
    }
    // Both are diagnostic proxies. Neither establishes new-source ownership.
    if (value['signal'] != 'available-proxy' &&
        value['signal'] != 'diagnostic-consumed-proxy') {
      return const VideoSourceFrameOutcome('protocol-mismatch');
    }
    return VideoSourceFrameOutcome(value['status'] as String, {
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    });
  }
}
