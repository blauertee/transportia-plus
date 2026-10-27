import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/utils/hyphenation.dart';

/// [word] with a hyphen at every place it may be broken.
String _marked(String word) {
  var marked = '', from = 0;
  for (final at in syllableBreaks(word)) {
    marked += '${word.substring(from, at)}-';
    from = at;
  }
  return marked + word.substring(from);
}

/// Fits a line of up to [chars] characters.
bool Function(String) _upTo(int chars) =>
    (line) => line.length <= chars;

void main() {
  group('syllableBreaks', () {
    test('breaks between syllables', () {
      expect(_marked('Intercity'), 'In-ter-ci-ty');
      expect(_marked('Northern'), 'Nor-thern');
      expect(_marked('Eurostar'), 'Eu-ro-star');
      expect(_marked('Regionalbahn'), 'Re-gio-nal-bahn');
    });

    test('breaks between words run together, not a letter from them', () {
      expect(_marked('FlixBus'), 'Flix-Bus');
      expect(_marked('BlaBlaCar'), 'Bla-Bla-Car');
    });

    test('leaves at least two letters either side', () {
      expect(syllableBreaks('Ulm'), isEmpty);
      expect(_marked('Anglia'), 'An-glia');
    });

    test('never breaks a number', () {
      expect(syllableBreaks('84284'), isEmpty);
      expect(syllableBreaks('N1309'), isEmpty);
    });
  });

  group('breakLines', () {
    test('keeps what fits on one line', () {
      expect(breakLines('ICE 1507', _upTo(8)), ['ICE 1507']);
    });

    test('breaks between words first', () {
      expect(breakLines('TGV INOUI 2465', _upTo(5)), ['TGV', 'INOUI', '2465']);
    });

    test('breaks a word too long at a syllable, with a hyphen', () {
      expect(breakLines('Great Northern', _upTo(5)), [
        'Great',
        'Nor-',
        'thern',
      ]);
    });

    test('breaks a number too long a digit at a time, without a hyphen', () {
      expect(breakLines('84284', _upTo(3)), ['842', '84']);
      expect(breakLines('N1309', _upTo(3)), ['N13', '09']);
    });

    test('breaks a word with no syllable that fits between letters', () {
      expect(breakLines('INOUI', _upTo(3)), ['IN-', 'OUI']);
    });

    test('loses nothing', () {
      for (final name in [
        'Hammersmith & City',
        'FlixBus N1309',
        'BlaBlaCar Bus',
        'TGV INOUI 2465',
      ]) {
        for (var width = 2; width < 12; width++) {
          final lines = breakLines(name, _upTo(width));
          expect(
            lines.join(' ').replaceAll('- ', '').replaceAll(' ', ''),
            name.replaceAll(' ', ''),
            reason: '$name at $width: $lines',
          );
        }
      }
    });
  });
}
