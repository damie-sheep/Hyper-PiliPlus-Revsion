import 'dart:async';

import 'package:PiliPlus/utils/video_source_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('next open waits until old Surface image is committed', () async {
    final sources = VideoSourceCoordinator();
    final captured = Completer<void>();
    final painted = Completer<void>();
    final retaining = sources.retain(() async {
      await captured.future;
      await painted.future;
    });
    final next = sources.request();
    var started = false;
    final open = next.start(() => true).then((value) => started = value);
    await Future<void>.delayed(Duration.zero);
    expect(started, isFalse);
    captured.complete();
    await Future<void>.delayed(Duration.zero);
    expect(
      started,
      isFalse,
      reason: 'A decoded image is not yet a painted replacement',
    );
    painted.complete();
    await retaining;
    await open;
    expect(started, isTrue);
    next.release();
  });

  test(
    'rapid A to B to C never overlaps native opens or attaches stale B',
    () async {
      final sources = VideoSourceCoordinator();
      final a = sources.request();
      expect(await a.start(null), isTrue);
      final b = sources.request();
      final c = sources.request();
      var cStarted = false;
      final bStart = b.start(() => true);
      final cStart = c.start(() => true).then((ready) => cStarted = ready);
      await Future<void>.delayed(Duration.zero);
      expect(cStarted, isFalse);
      expect(a.isCurrent, isFalse);
      a.release();
      expect(await bStart, isFalse);
      expect(cStarted, isFalse);
      b.release();
      await cStart;
      expect(cStarted, isTrue);
      c.release();
    },
  );

  test('pop, background and disposal reject pending ownership', () async {
    final sources = VideoSourceCoordinator();
    final background = sources.request();
    expect(await background.start(() => false), isFalse);
    background.release();
    final disposed = sources.request();
    sources.invalidate();
    expect(await disposed.start(null), isFalse);
    disposed
      ..release()
      ..release(); // Cleanup is idempotent.
  });

  test('a failed capture cannot deadlock later source operations', () async {
    final sources = VideoSourceCoordinator();
    await sources.retain(() async => throw StateError('capture failed'));
    final request = sources.request();
    expect(await request.start(null), isTrue);
    request.release();
  });
}
