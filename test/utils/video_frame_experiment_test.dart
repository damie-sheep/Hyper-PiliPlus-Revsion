import 'package:PiliPlus/utils/android/video_surface_bridge.dart';
import 'package:PiliPlus/utils/video_frame_experiment.dart';
import 'package:PiliPlus/utils/video_transition_trace.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('compile-time experiment and native handshake agree', (
    tester,
  ) async {
    const requested = String.fromEnvironment('VIDEO_FRAME_EXPERIMENT');
    const trace = bool.fromEnvironment('VIDEO_TRANSITION_TRACE');
    final active = trace && ['X0', 'X1', 'X2', 'X3'].contains(requested);
    expect(videoFrameExperiment, active ? requested : '');
    expect(
      videoFrameExperimentLivePaint,
      active && ['X1', 'X3'].contains(requested),
    );
    expect(
      videoFrameExperimentDefaultListener,
      active && ['X2', 'X3'].contains(requested),
    );
    const channel = MethodChannel('com.alexmercerind/media_kit_video');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    var status = 'candidate';
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method.endsWith('ConfigureExperiment')) {
        expect(call.arguments['variant'], videoFrameExperiment);
        return {'version': 2, 'variant': videoFrameExperiment};
      }
      if (call.method.endsWith('AwaitSourceFrame2')) {
        return {
          'version': 2,
          'generation': call.arguments['generation'],
          'outputEpoch': 9,
          'signal': videoFrameExperimentDefaultListener
              ? 'diagnostic-consumed-proxy'
              : 'available-proxy',
          'status': status,
          'sourceIdentityProven': false,
        };
      }
      return null;
    });
    await VideoSurfaceBridge.configureExperiment();
    await VideoSurfaceBridge.configureExperiment();
    expect(
      calls.where((name) => name.endsWith('ConfigureExperiment')).length,
      active ? 1 : 0,
    );
    if (active) {
      expect(await VideoSurfaceBridge.waitForSourceFrame(5, 1), isTrue);
      status = 'unavailable';
      expect(await VideoSurfaceBridge.waitForSourceFrame(5, 2), isFalse);
      expect(
        calls.any(
          (name) => name.endsWith('AwaitSourceFrame') && !name.endsWith('2'),
        ),
        isFalse,
      );
    }
    if (trace) {
      beginVideoTransitionTrace('probe');
      endVideoTransitionTrace('probe');
      await tester.pump(const Duration(seconds: 9));
      await tester.pump();
    }
    messenger.setMockMethodCallHandler(channel, null);
  });
}
