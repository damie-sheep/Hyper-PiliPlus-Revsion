import 'dart:async';

/// One native open at a time, with latest-request ownership and a separate
/// barrier for committing the previous page's retained Surface image.
class VideoSourceCoordinator {
  int _generation = 0;
  int get generation => _generation;
  Future<void> _opens = Future<void>.value();
  Future<void> _retention = Future<void>.value();

  VideoSourceRequest request() {
    final released = Completer<void>();
    final request = VideoSourceRequest._(this, ++_generation, _opens, released);
    _opens = released.future;
    return request;
  }

  Future<void> retain(Future<void> Function() commit) {
    _retention = _retention
        .then((_) => commit())
        .catchError((Object _, StackTrace _) {});
    return _retention;
  }

  void invalidate() => _generation++;
}

class VideoSourceRequest {
  VideoSourceRequest._(
    this._owner,
    this.generation,
    this._previous,
    this._released,
  );
  final VideoSourceCoordinator _owner;
  final int generation;
  final Future<void> _previous;
  final Completer<void> _released;

  bool get isCurrent => generation == _owner.generation;

  Future<bool> start(bool Function()? canAttach) async {
    await _previous;
    await _owner._retention;
    return isCurrent && (canAttach == null || canAttach());
  }

  void release() {
    if (!_released.isCompleted) _released.complete();
  }
}
