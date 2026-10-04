/// A no-break space: wraps never fall on it.
const String _noBreak = ' ';

/// A search stage's one-line summary: what it uses, then its limit.
///
/// The summary may wrap onto a second line when many sections are on, so
/// the limit is held together and to the last word before it: a wrap moves
/// "other · 1 h 30" down whole, rather than leaving "30" or a lone "·" on
/// a line of its own.
String stageSummary(String what, String limit) =>
    '$what$_noBreak·$_noBreak${limit.replaceAll(' ', _noBreak)}';
