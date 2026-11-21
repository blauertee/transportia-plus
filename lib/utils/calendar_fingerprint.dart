import 'dart:convert';

/// FNV-1a's 32-bit offset basis and prime.
const int _kFnvOffset = 0x811c9dc5;
const int _kFnvPrime = 0x01000193;
const int _kLow32Bits = 0xffffffff;

/// Separates the fields hashed, so moving text from one into the next
/// changes the fingerprint.
const String _kFieldSeparator = '\u0000';

/// A short stand-in for a calendar event exactly as the app wrote it, so it
/// can later tell whether the event is still untouched without storing the
/// whole text.
///
/// Any edit to the title, the description or either time changes it. Not a
/// security measure: it only has to notice the rider's own changes.
String calendarEventFingerprint({
  required String title,
  required String description,
  required int startMillis,
  required int endMillis,
}) {
  final text = [
    title,
    description,
    '$startMillis',
    '$endMillis',
  ].join(_kFieldSeparator);
  var hash = _kFnvOffset;
  for (final byte in utf8.encode(text)) {
    hash = ((hash ^ byte) * _kFnvPrime) & _kLow32Bits;
  }
  // The length as well, so two texts colliding in 32 bits must also be the
  // same length to be mistaken for each other.
  return '${hash.toRadixString(16)}-${text.length}';
}
