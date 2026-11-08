import 'package:flutter/foundation.dart';

import '../models/motis_request_record.dart';

/// The last MOTIS requests, newest first, held in memory only: the log is
/// for looking at what the app just sent, not a history worth keeping.
///
/// [TransitousClient] writes to it while [enabled] is on; the advanced
/// settings switch sets that, so the client never reads preferences itself.
class MotisRequestLog {
  const MotisRequestLog._();

  /// Enough for a search, its paging and the screens around it, without
  /// holding a long session's worth of map tiles.
  static const int capacity = 100;

  static bool enabled = false;

  static final ValueNotifier<List<MotisRequestRecord>> records = ValueNotifier(
    const [],
  );

  /// Adds [record] at the top, when logging is on. Returns whether it was
  /// kept, so the caller knows to [replace] it once the response is in.
  static bool add(MotisRequestRecord record) {
    if (!enabled) return false;
    final next = [record, ...records.value];
    records.value = next.length > capacity ? next.sublist(0, capacity) : next;
    return true;
  }

  /// Puts [finished] where [pending] was. Does nothing if [pending] has
  /// been cleared or pushed out of the log meanwhile.
  static void replace(MotisRequestRecord pending, MotisRequestRecord finished) {
    final current = records.value;
    final i = current.indexWhere((r) => identical(r, pending));
    if (i < 0) return;
    records.value = [...current]..[i] = finished;
  }

  static void clear() => records.value = const [];
}
