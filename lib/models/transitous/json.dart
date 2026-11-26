/// Helpers for reading MOTIS JSON.
///
/// The API encodes every number in exponential form (`5.2521E1`), so a field
/// that looks like an `int` in the spec arrives as a `double` and a plain
/// `as int` cast throws. These readers normalise that, and return null for
/// absent or wrongly typed values so a single unexpected field cannot fail a
/// whole response.
library;

double? asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}

bool? asBool(Object? value) {
  if (value is bool) return value;
  if (value is String) {
    if (value == 'true') return true;
    if (value == 'false') return false;
  }
  return null;
}

String? asString(Object? value) => value is String ? value : null;

DateTime? asDateTime(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}

/// Seconds as MOTIS reports every duration.
Duration? asDuration(Object? value) {
  final seconds = asDouble(value);
  return seconds == null ? null : Duration(seconds: seconds.round());
}

Map<String, dynamic>? asMap(Object? value) =>
    value is Map<String, dynamic> ? value : null;

/// [json] without its null entries: a patched snapshot leaves out what
/// neither side had, rather than adding keys the server never sent.
Map<String, dynamic> withoutNulls(Map<String, dynamic> json) => {
  for (final MapEntry(:key, :value) in json.entries)
    if (value != null) key: value,
};

List<String> asStringList(Object? value) => value is List
    ? value.whereType<String>().toList(growable: false)
    : const <String>[];

/// Maps a JSON array through [parse], skipping entries that fail.
///
/// A malformed intermediate stop should cost that stop, not the itinerary it
/// belongs to — the same tolerance the existing itinerary parser applies.
List<T> asList<T>(Object? value, T Function(Map<String, dynamic> json) parse) {
  if (value is! List) return const [];
  final result = <T>[];
  for (final entry in value) {
    if (entry is! Map<String, dynamic>) continue;
    try {
      result.add(parse(entry));
    } catch (_) {
      // Left unlogged: this runs over every stop, alert and step of a
      // response, and a field the server gets wrong is wrong in all of
      // them, which would be one line per entry.
      continue;
    }
  }
  return List.unmodifiable(result);
}
