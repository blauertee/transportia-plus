import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Where the app's one way of navigating is kept, and the only place the
/// lower-level pieces below may be used.
const String _kNavigationDir = 'lib/navigation/';

/// What is not used outside [_kNavigationDir], and what to use instead.
const Map<String, String> _kRules = {
  r'\b(Cupertino|Material)PageRoute\b|\bPageRouteBuilder\b|\bPageRoute<':
      'open screens with context.openScreen (lib/navigation/routes.dart)',
  r'\b(Raw)?DialogRoute\b|\bshowGeneralDialog\b':
      'open sheets with context.openSheet (lib/navigation/routes.dart)',
  r'\.(push|pushReplacement|pushAndRemoveUntil|pushNamed)\s*[<(]':
      'open screens with context.openScreen or replaceScreen',
  r'\b(PopScope|WillPopScope)\b':
      'catch back with BackStep (lib/navigation/back_step.dart)',
  r'\brootNavigator\s*:':
      'the app has one navigator; Navigator.of(context) is it',
};

/// [source] with its comments blanked out, so documentation may name what
/// code may not use.
String _code(String source) => source
    .split('\n')
    .map((line) => line.replaceFirst(RegExp(r'//.*$'), ''))
    .join('\n');

void main() {
  test('screens are opened, and back is caught, only through '
      'lib/navigation', () {
    final offences = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => !file.path.startsWith(_kNavigationDir));
    for (final file in files) {
      final lines = _code(file.readAsStringSync()).split('\n');
      for (var i = 0; i < lines.length; i++) {
        for (final rule in _kRules.entries) {
          if (RegExp(rule.key).hasMatch(lines[i])) {
            offences.add('${file.path}:${i + 1}: ${rule.value}');
          }
        }
      }
    }
    expect(offences, isEmpty, reason: offences.join('\n'));
  });
}
