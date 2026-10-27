import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

/// The repository Android overlay extends the pinned plugin without changing
/// its Dart API or the Pub cache. No URL or media identity crosses this bridge.
abstract final class VideoSurfaceBridge {
  static const _channel = MethodChannel('com.alexmercerind/media_kit_video');

  static Future<ui.Image?> captureFrame(int handle) async {
    try {
      final bytes = await _channel
          .invokeMethod<Uint8List>(
            'VideoOutputManager.CaptureFrame',
            {'handle': '$handle'},
          )
          .timeout(const Duration(milliseconds: 250));
      if (bytes == null || bytes.isEmpty) return null;
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final image = (await codec.getNextFrame()).image;
        if (image.width <= 1 || image.height <= 1) {
          image.dispose();
          return null;
        }
        return image;
      } finally {
        codec.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  static Future<bool?> waitForSourceFrame(int handle, int generation) async {
    try {
      return await _channel
          .invokeMethod<bool>(
            'VideoOutputManager.AwaitSourceFrame',
            {'handle': '$handle', 'generation': generation},
          )
          .timeout(const Duration(milliseconds: 3200));
    } on TimeoutException {
      return false;
    } catch (_) {
      return null;
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
}
