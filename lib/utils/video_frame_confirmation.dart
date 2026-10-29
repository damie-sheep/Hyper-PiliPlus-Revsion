import 'dart:async';

/// One bounded confirmation per open, including the Flutter drawing handoff.
/// A native consumption candidate does not establish source identity.
Future<bool> confirmVideoFrame({
  required Future<bool> Function() observeAndSubmit,
  required bool Function() isCurrent,
  Duration timeout = const Duration(milliseconds: 3500),
}) async {
  try {
    return await observeAndSubmit().timeout(timeout) && isCurrent();
  } catch (_) {
    return false;
  }
}
