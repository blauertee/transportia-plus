import 'dart:convert';

/// Reads a list kept in storage as one JSON array, entry by entry.
///
/// An entry [parse] cannot read — written by another schema, or damaged —
/// costs that entry and no other. [parse] may throw or return null to skip
/// one. Nothing stored is an empty list.
///
/// Returns null when the value is not a JSON array at all. That is not an
/// empty list: writing one back would replace whatever is there, so a caller
/// about to write has to tell the two apart.
///
/// The list is growable, so a caller can change it and write it back.
List<T>? decodeStoredList<T>(
  String? encoded,
  T? Function(Map<String, dynamic> json) parse,
) {
  if (encoded == null || encoded.isEmpty) return <T>[];
  final Object? decoded;
  try {
    decoded = jsonDecode(encoded);
  } on FormatException {
    return null;
  }
  if (decoded is! List) return null;

  final entries = <T>[];
  for (final item in decoded) {
    if (item is! Map<String, dynamic>) continue;
    try {
      final entry = parse(item);
      if (entry != null) entries.add(entry);
    } catch (_) {
      continue;
    }
  }
  return entries;
}
