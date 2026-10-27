/// Where [word] may be broken across lines with a hyphen, as indexes to
/// break before, earliest first: never fewer than two letters either side.
///
/// A rough rule of thumb, not a dictionary: between a lower and an upper
/// case letter ("Flix|Bus"), between letters and digits, before a lone
/// consonant between vowels ("In|ter|ci|ty"), before a pair a syllable
/// starts with ("Eu|ro|star"), else after the first of several consonants
/// ("Nor|thern"), keeping "ch", "ck", "sch", "sh", "th", "ph" and "qu"
/// together.
List<int> syllableBreaks(String word) {
  final chars = word.split('');
  final breaks = <int>{};
  const isLetter = _isLetter;
  bool isDigit(String c) => '0123456789'.contains(c);
  bool isVowel(String c) => 'aeiouyäöüéèêàâîôûAEIOUYÄÖÜÉÈÊÀÂÎÔÛ'.contains(c);
  bool isUpper(String c) => isLetter(c) && c == c.toUpperCase();

  for (var i = 1; i < chars.length; i++) {
    final a = chars[i - 1], b = chars[i];
    if (isLetter(a) && isLetter(b) && !isUpper(a) && isUpper(b)) breaks.add(i);
    if ((isLetter(a) && isDigit(b)) || (isDigit(a) && isLetter(b))) {
      breaks.add(i);
    }
  }

  final cases = {...breaks};
  const together = ['sch', 'ch', 'ck', 'sh', 'th', 'ph', 'qu'];
  // Pairs a syllable starts with, which go over to the next line together.
  const onsets = {
    'bl', 'br', 'cl', 'cr', 'dr', 'fl', 'fr', 'gl', 'gr', //
    'kl', 'kr', 'pl', 'pr', 'tr', 'sp', 'st',
  };
  var i = 0;
  while (i < chars.length) {
    if (!isVowel(chars[i])) {
      i++;
      continue;
    }
    // The end of this run of vowels, and the consonants after it.
    var end = i;
    while (end + 1 < chars.length && isVowel(chars[end + 1])) {
      end++;
    }
    var next = end + 1;
    while (next < chars.length &&
        isLetter(chars[next]) &&
        !isVowel(chars[next])) {
      next++;
    }
    if (next >= chars.length || !isVowel(chars[next])) {
      i = next + 1;
      continue;
    }
    final cluster = word.substring(end + 1, next).toLowerCase();
    final int at;
    if (cluster.length <= 1 || together.contains(cluster)) {
      at = end + 1;
    } else if (onsets.contains(cluster.substring(cluster.length - 2))) {
      at = next - 2;
    } else {
      final kept = together.firstWhere(
        cluster.startsWith,
        orElse: () => cluster.substring(0, 1),
      );
      at = end + 1 + (kept.length < cluster.length ? kept.length : 0);
    }
    // Not a letter away from a break between words run together.
    if (!cases.any((other) => (other - at).abs() < 2)) breaks.add(at);
    i = next;
  }

  return [
    for (final at in breaks.toList()..sort())
      if (at >= 2 && at <= chars.length - 2) at,
  ];
}

/// [text] as lines no wider than [fits] allows: broken between words where
/// they fit, else inside a word at a syllable with a hyphen, and only where
/// not even a syllable fits, between any two characters. Numbers are broken
/// without a hyphen, a digit at a time.
List<String> breakLines(String text, bool Function(String line) fits) {
  final lines = <String>[];
  var current = '';
  for (final word in text.split(' ').where((word) => word.isNotEmpty)) {
    final joined = current.isEmpty ? word : '$current $word';
    if (fits(joined)) {
      current = joined;
      continue;
    }
    if (current.isNotEmpty) lines.add(current);
    var rest = word;
    while (!fits(rest)) {
      // A hyphen only between two letters: a number broken with one would
      // read as a range.
      String piece(int at) => _isLetter(rest[at - 1]) && _isLetter(rest[at])
          ? '${rest.substring(0, at)}-'
          : rest.substring(0, at);
      var at = syllableBreaks(
        rest,
      ).lastWhere((at) => fits(piece(at)), orElse: () => 0);
      if (at == 0) {
        at = rest.length - 1;
        while (at > 1 && !fits(piece(at))) {
          at--;
        }
      }
      lines.add(piece(at));
      rest = rest.substring(at);
    }
    current = rest;
  }
  if (current.isNotEmpty) lines.add(current);
  return lines;
}

bool _isLetter(String c) => c.toLowerCase() != c.toUpperCase();
