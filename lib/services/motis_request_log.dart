import 'package:flutter/foundation.dart';

import '../models/motis_request_record.dart';

/// The last MOTIS requests, newest first, held in memory only: the log is
/// for looking at what the app just sent, not a history worth keeping.
class MotisRequestLog {
  const MotisRequestLog._();

  /// Enough for a search, its paging and the screens around it, without
  /// holding a long session's worth of map tiles.
  static const int capacity = 100;

  static final ValueNotifier<List<MotisRequestRecord>> records = ValueNotifier(
    const [],
  );

  static void add(MotisRequestRecord record) {
    final next = [record, ...records.value];
    records.value = next.length > capacity ? next.sublist(0, capacity) : next;
  }

  static void clear() => records.value = const [];
}
