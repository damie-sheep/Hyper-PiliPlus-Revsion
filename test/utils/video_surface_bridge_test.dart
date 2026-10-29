import 'dart:ui' as ui;

import 'package:PiliPlus/utils/android/video_surface_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.alexmercerind/media_kit_video');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'every source registers independently; cancellation preserves its token',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method.endsWith('AwaitSourceFrame2')) {
          return {
            'version': 2,
            'generation': call.arguments['generation'],
            'outputEpoch': 8,
            'surfaceEpoch': 2,
            'signal': 'diagnostic-consumed-proxy',
            'status': call.arguments['generation'] == 2
                ? 'candidate'
                : 'timeout',
          };
        }
        return null;
      });
      expect(await VideoSurfaceBridge.waitForSourceFrame(100, 1), isFalse);
      expect(await VideoSurfaceBridge.waitForSourceFrame(100, 2), isTrue);
      await VideoSurfaceBridge.cancelSourceFrame(100, 2);
      expect(calls.map((c) => c.arguments['generation']), [1, 2, 2]);
      expect(calls.last.method, 'VideoOutputManager.CancelSourceFrame');
    },
  );

  test('missing backend is unconfirmed, not a rendered frame', () async {
    expect(await VideoSurfaceBridge.waitForSourceFrame(1, 1), isFalse);
    expect(await VideoSurfaceBridge.captureFrame(1), isNull);
    await VideoSurfaceBridge.cancelSourceFrame(1, 1);
  });

  test('v2 proxy outcome preserves reason and output identity', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => {
        'version': 2,
        'generation': call.arguments['generation'],
        'outputEpoch': 8,
        'surfaceEpoch': 2,
        'signal': 'diagnostic-consumed-proxy',
        'sourceIdentityProven': false,
        'status': 'cancelled',
      },
    );
    final outcome = await VideoSurfaceBridge.waitForSourceFrameOutcome(1, 3);
    expect(outcome.status, 'cancelled');
    expect(outcome.fields['outputEpoch'], 8);
    expect(outcome.fields['sourceIdentityProven'], isFalse);
  });

  test('old bool, wrong generation and unknown signal fail closed', () {
    expect(VideoSourceFrameOutcome.parse(true, 2).status, 'protocol-mismatch');
    final value = <String, Object?>{
      'version': 2,
      'generation': 1,
      'outputEpoch': 7,
      'signal': 'available-proxy',
      'status': 'candidate',
    };
    expect(VideoSourceFrameOutcome.parse(value, 2).status, 'protocol-mismatch');
    value['generation'] = 2;
    expect(VideoSourceFrameOutcome.parse(value, 2).status, 'candidate');
    value['signal'] = 'playing';
    expect(VideoSourceFrameOutcome.parse(value, 2).status, 'protocol-mismatch');
  });

  testWidgets('Surface capture decodes a bounded valid frame', (tester) async {
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder)
          .drawColor(const ui.Color(0xff336699), ui.BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(32, 18);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => png!.buffer.asUint8List(),
      );
      final copy = await VideoSurfaceBridge.captureFrame(20);
      expect(copy, isNotNull);
      expect(copy!.width, 32);
      expect(copy.height, 18);
      copy.dispose();
    });
  });

  testWidgets('invalid and idle 1x1 captures cannot replace the live frame', (
    tester,
  ) async {
    await tester.runAsync(() async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => Uint8List.fromList([1, 2, 3]),
      );
      expect(await VideoSurfaceBridge.captureFrame(1), isNull);
      final picture = ui.PictureRecorder();
      ui.Canvas(picture)
          .drawColor(const ui.Color(0xff000000), ui.BlendMode.src);
      final recorded = picture.endRecording();
      final image = await recorded.toImage(1, 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      recorded.dispose();
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => png!.buffer.asUint8List(),
      );
      expect(await VideoSurfaceBridge.captureFrame(1), isNull);
    });
  });
}
