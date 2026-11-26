import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/log_caught.dart';
import '../utils/stored_list.dart';

/// Thrown, with nothing written, when a change is asked of a list whose
/// stored value cannot be read: the read failed, or the value is not a JSON
/// array.
///
/// Writing the changed list would replace what is stored with the little
/// this build could make of it. Refused instead, the value stays where it
/// is for a later build to read.
class StoredListUnreadable implements Exception {
  const StoredListUnreadable(this.key);

  final String key;

  @override
  String toString() => 'StoredListUnreadable: $key';
}

/// A list kept in SharedPreferences as one JSON array under [key].
///
/// Every change reads the whole list, edits it and writes it all back. Two
/// of those running at once would each write their own edit over the
/// other's, so [update] runs them one at a time per key: the second reads
/// what the first wrote.
class StoredListStore<T> {
  const StoredListStore({
    required this.key,
    required this.fromJson,
    required this.toJson,
  });

  final String key;
  final T? Function(Map<String, dynamic> json) fromJson;
  final Map<String, dynamic> Function(T entry) toJson;

  /// When the last change queued on each key finishes, for keys with one
  /// still running. Static, so two stores on one key still take turns.
  static final Map<String, Future<void>> _queues = {};

  /// The list as stored, for showing. A value that cannot be read shows as
  /// empty; nothing is written from it.
  Future<List<T>> read() async {
    try {
      final raw = await SharedPreferencesAsync().getString(key);
      return decodeStoredList(raw, fromJson) ?? <T>[];
    } catch (e, stack) {
      logCaught(e, stack, name: 'StoredListStore', context: 'reading $key');
      return <T>[];
    }
  }

  /// Reads the list, lets [change] edit it in place, and writes it back,
  /// after every change queued before it on this key has landed.
  ///
  /// [change] returns false to write nothing. Returns the list as written,
  /// or null when nothing was. Throws [StoredListUnreadable] when the stored
  /// value cannot be read.
  Future<List<T>?> update(bool Function(List<T> entries) change) =>
      _queued(() async {
        final prefs = SharedPreferencesAsync();
        final String? raw;
        try {
          raw = await prefs.getString(key);
        } catch (e, stack) {
          logCaught(e, stack, name: 'StoredListStore', context: 'reading $key');
          throw StoredListUnreadable(key);
        }
        final entries = decodeStoredList(raw, fromJson);
        if (entries == null) throw StoredListUnreadable(key);
        if (!change(entries)) return null;
        await prefs.setString(
          key,
          jsonEncode([for (final entry in entries) toJson(entry)]),
        );
        return entries;
      });

  /// Removes the list, in turn with the changes queued before it.
  Future<void> clear() => _queued(() => SharedPreferencesAsync().remove(key));

  Future<R> _queued<R>(Future<R> Function() action) async {
    final previous = _queues[key];
    final done = Completer<void>();
    _queues[key] = done.future;
    try {
      // The change before this one has to finish, not to succeed.
      if (previous != null) await previous;
      return await action();
    } finally {
      done.complete();
      // Dropped as soon as the queue runs dry, so a later change never waits
      // on one that has long finished: a test's fake clock may never run
      // whatever was left to complete it.
      if (identical(_queues[key], done.future)) _queues.remove(key);
    }
  }
}
