import 'package:PiliPlus/utils/video_transition_trace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bounded trace retains latest window and reports lost records', () {
    final buffer = VideoTransitionTraceBuffer(capacity: 3);
    for (var i = 0; i < 5; i++) {
      buffer.add({'paint': i});
    }
    final batch = buffer.drain();
    expect(batch['dropped'], 2);
    expect((batch['events']! as List).map((e) => e['paint']), [2, 3, 4]);
    expect(buffer.drain(), {'dropped': 0, 'events': []});
  });

  test('late timing batches belong to their original engine-time window', () {
    final windows = [
      VideoTimingWindow(1, 100)..endUs = 300,
      VideoTimingWindow(2, 300)..endUs = 600,
      VideoTimingWindow(3, 700),
    ];
    expect(videoTimingAction(windows, 99), isNull);
    expect(videoTimingAction(windows, 299), 1);
    expect(videoTimingAction(windows, 300), 2);
    expect(videoTimingAction(windows, 600), isNull);
    expect(videoTimingAction(windows, 750), 3);
    expect(videoTimingAction(windows, 150), 1);
  });

  test(
    'high refresh tail preserves a bounded entry sample and total count',
    () {
      final window = VideoTimingWindow(1, 0);
      var retained = 0;
      for (var i = 0; i < 1200; i++) {
        if (window.sampleFrame()) retained++;
      }
      expect(retained, 180);
      expect(window.frames, 1200);
      expect(window.frames - window.sampledFrames, 1020);
      expect(VideoTimingWindow(2, 100).sampleFrame(), isTrue);
    },
  );
}
