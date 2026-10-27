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
}
