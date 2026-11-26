import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/utils/log_caught.dart';

/// An error that cannot even say what it is.
class _Unprintable implements Exception {
  @override
  String toString() => throw StateError('no words');
}

void main() {
  final original = logCaughtSink;
  tearDown(() => logCaughtSink = original);

  test('passes on the error, its stack and what failed', () {
    final logged = <(String, String, Object, StackTrace?)>[];
    logCaughtSink = (message, {required name, required error, stackTrace}) =>
        logged.add((message, name, error, stackTrace));
    final error = StateError('gone');
    final stack = StackTrace.current;

    logCaught(error, stack, name: 'MapScreen', context: 'loading vehicles');

    expect(logged.single, (
      'Caught: loading vehicles',
      'MapScreen',
      error,
      stack,
    ));
  });

  test('takes a missing stack', () {
    StackTrace? seen = StackTrace.current;
    logCaughtSink = (message, {required name, required error, stackTrace}) =>
        seen = stackTrace;

    logCaught('plain', null, name: 'X', context: 'y');

    expect(seen, isNull);
  });

  test('never throws, even when logging does', () {
    logCaughtSink = (message, {required name, required error, stackTrace}) =>
        throw StateError('the log is broken');

    expect(
      () => logCaught(StateError('x'), null, name: 'X', context: 'y'),
      returnsNormally,
    );
  });

  test('never throws through the real log, for an error that cannot print', () {
    expect(
      () => logCaught(
        _Unprintable(),
        StackTrace.current,
        name: 'X',
        context: 'an unprintable error',
      ),
      returnsNormally,
    );
  });
}
