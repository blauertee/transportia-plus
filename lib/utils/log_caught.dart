import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Where [logCaught] sends what it is given. Replaced in tests, to see
/// what was logged; the app logs as the rest of it does, through
/// `dart:developer`.
@visibleForTesting
void Function(
  String message, {
  required String name,
  required Object error,
  StackTrace? stackTrace,
})
logCaughtSink = _toDeveloperLog;

void _toDeveloperLog(
  String message, {
  required String name,
  required Object error,
  StackTrace? stackTrace,
}) => developer.log(message, name: name, error: error, stackTrace: stackTrace);

/// Leaves a trace of an [error] a catch block recovers from, so a failure
/// the rider never sees can still be found: what failed ([context]), in
/// which part of the app ([name], as `developer.log` names it elsewhere).
///
/// Never throws. It runs inside catch blocks, where a throw would replace
/// the error being handled with one about logging it.
void logCaught(
  Object error,
  StackTrace? stackTrace, {
  required String name,
  required String context,
}) {
  try {
    logCaughtSink(
      'Caught: $context',
      name: name,
      error: error,
      stackTrace: stackTrace,
    );
  } catch (_) {
    // Logging was the last thing to try; there is nowhere left to say so.
  }
}
