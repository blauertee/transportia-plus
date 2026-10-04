import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/utils/stage_summary.dart';

void main() {
  const noBreak = ' ';

  test('joins what and limit with a dot', () {
    expect(
      stageSummary('Walk', '15 min').replaceAll(noBreak, ' '),
      'Walk · 15 min',
    );
  });

  test('a wrap can fall between sections but not inside the limit', () {
    final summary = stageSummary('Walk, bike, car', '1 h 30');
    expect(summary, startsWith('Walk, bike, car$noBreak'));
    expect(summary.substring('Walk, bike, car'.length), isNot(contains(' ')));
  });

  test('an empty limit still reads', () {
    expect(stageSummary('Walk', ''), 'Walk$noBreak·$noBreak');
  });
}
