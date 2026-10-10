import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/models/itinerary.dart';
import 'package:transportia/utils/changeover.dart';
import 'package:transportia/utils/itinerary_leg_utils.dart';
import 'package:transportia/utils/leg_notices.dart';

final DateTime _t0 = DateTime(2026, 6, 1, 10, 0);

String _at(int minutes) =>
    _t0.add(Duration(minutes: minutes)).toUtc().toIso8601String();

Map<String, dynamic> _alert(
  String? header, {
  String? body,
  String? effect,
  String? severity,
}) => {
  'headerText': ?header,
  'descriptionText': ?body,
  'effect': ?effect,
  'severityLevel': ?severity,
};

Map<String, dynamic> _place(
  String name, {
  bool cancelled = false,
  List<Map<String, dynamic>> alerts = const [],
  String? track,
}) => {
  'name': name,
  'lat': 49.0,
  'lon': 8.0,
  'cancelled': cancelled,
  'alerts': alerts,
  'track': ?track,
};

Leg _leg({
  String mode = 'REGIONAL_RAIL',
  bool cancelled = false,
  List<Map<String, dynamic>> alerts = const [],
  Map<String, dynamic>? from,
  Map<String, dynamic>? to,
  List<Map<String, dynamic>> stops = const [],
}) => Leg.fromJson({
  'mode': mode,
  'startTime': _at(0),
  'endTime': _at(20),
  'duration': 1200,
  'cancelled': cancelled,
  'alerts': alerts,
  'from': from ?? _place('A', track: '1'),
  'to': to ?? _place('B', track: '2'),
  'intermediateStops': stops,
});

List<String> _titles(List<LegNotice> notices) => [
  for (final n in notices) n.title,
];

void main() {
  test('a leg with nothing wrong has nothing to say', () {
    expect(legNotices(_leg()), isEmpty);
  });

  test('a cancelled service is a problem, said once', () {
    final notices = legNotices(
      _leg(
        cancelled: true,
        from: _place('A', cancelled: true),
        stops: [_place('X', cancelled: true)],
      ),
    );
    // The whole service going swallows its stops going.
    expect(_titles(notices), ['This service is cancelled.']);
    expect(notices.single.severity, NoticeSeverity.problem);
  });

  group('a cancelled street leg', () {
    // What a refresh sends for a stretch it could not route again: the
    // planned mode, cancelled, its only alert the server's error.
    Leg placeholder(String mode) => _leg(
      mode: mode,
      cancelled: true,
      alerts: [_alert('no offset found')],
      from: _place('', cancelled: true),
      to: _place('', cancelled: true),
    );

    test('on a shared vehicle means none is left within reach', () {
      final notices = legNotices(placeholder('RENTAL'));
      expect(_titles(notices), ['No shared vehicle is within reach any more.']);
      expect(notices.single.severity, NoticeSeverity.problem);
    });

    test('on foot means the way is gone, not a service', () {
      expect(_titles(legNotices(placeholder('WALK'))), [
        'There is no way through here any more.',
      ]);
    });

    test('keeps the stops\' own alerts', () {
      final notices = legNotices(
        _leg(
          mode: 'WALK',
          cancelled: true,
          alerts: [_alert('no offset found')],
          from: _place('Ostkreuz', alerts: [_alert('Lift out of order')]),
        ),
      );
      expect(_titles(notices), [
        'There is no way through here any more.',
        'Lift out of order',
      ]);
    });
  });

  test('losing the stop you board or leave at is a problem', () {
    final notices = legNotices(
      _leg(
        from: _place('A', cancelled: true),
        to: _place('B', cancelled: true),
      ),
    );
    expect(_titles(notices), [
      'It no longer stops at A.',
      'It no longer stops at B.',
    ]);
    expect(
      notices.map((n) => n.severity),
      everyElement(NoticeSeverity.problem),
    );
  });

  test('stops skipped on the way are counted, as a caution', () {
    final one = legNotices(_leg(stops: [_place('X', cancelled: true)]));
    expect(_titles(one), ['One stop on the way is skipped.']);
    expect(one.single.severity, NoticeSeverity.caution);

    final two = legNotices(
      _leg(
        stops: [
          _place('X', cancelled: true),
          _place('Y'),
          _place('Z', cancelled: true),
        ],
      ),
    );
    expect(_titles(two), ['2 stops on the way are skipped.']);
  });

  group('the operator\'s alerts', () {
    test('come from the leg and every stop it calls at', () {
      final notices = legNotices(
        _leg(
          alerts: [_alert('On the leg')],
          from: _place('A', alerts: [_alert('At the start')]),
          stops: [
            _place('X', alerts: [_alert('On the way')]),
          ],
          to: _place('B', alerts: [_alert('At the end')]),
        ),
      );
      expect(_titles(notices), [
        'On the leg',
        'At the start',
        'On the way',
        'At the end',
      ]);
    });

    test('a walk\'s are read like a ride\'s', () {
      final notices = legNotices(
        _leg(mode: 'WALK', alerts: [_alert('Lift out of service')]),
      );
      expect(_titles(notices), ['Lift out of service']);
    });

    test('the same alert on two stops is said once', () {
      final lift = _alert('Lift out', body: 'Use the ramp.');
      final notices = legNotices(
        _leg(
          alerts: [lift],
          to: _place('B', alerts: [lift]),
        ),
      );
      expect(_titles(notices), ['Lift out']);
      expect(notices.single.detail, 'Use the ramp.');
    });

    test('with no header the text becomes the title', () {
      final notices = legNotices(
        _leg(alerts: [_alert(null, body: 'Only a body')]),
      );
      expect(notices.single.title, 'Only a body');
      expect(notices.single.detail, isNull);
    });

    test('an alert with no text at all is dropped', () {
      expect(legNotices(_leg(alerts: [_alert(null)])), isEmpty);
    });
  });

  group('how severe an alert is', () {
    NoticeSeverity of(Map<String, dynamic> json) =>
        severityOf(Alert.fromJson(json));

    test('the feed\'s own level wins', () {
      expect(
        of(_alert('x', severity: 'SEVERE', effect: 'ADDITIONAL_SERVICE')),
        NoticeSeverity.problem,
      );
      expect(
        of(_alert('x', severity: 'WARNING', effect: 'NO_SERVICE')),
        NoticeSeverity.caution,
      );
      expect(
        of(_alert('x', severity: 'INFO', effect: 'NO_SERVICE')),
        NoticeSeverity.info,
      );
    });

    test('without one, the effect decides', () {
      expect(of(_alert('x', effect: 'NO_SERVICE')), NoticeSeverity.problem);
      expect(of(_alert('x', effect: 'DETOUR')), NoticeSeverity.caution);
      expect(
        of(_alert('x', effect: 'ACCESSIBILITY_ISSUE')),
        NoticeSeverity.caution,
      );
      expect(
        of(_alert('x', effect: 'ADDITIONAL_SERVICE')),
        NoticeSeverity.info,
      );
      expect(of(_alert('x', effect: 'NO_EFFECT')), NoticeSeverity.info);
    });

    test('an unknown level or no effect at all is a caution', () {
      // Unsure is not the same as harmless.
      expect(
        of(_alert('x', severity: 'UNKNOWN_SEVERITY')),
        NoticeSeverity.caution,
      );
      expect(of(_alert('x')), NoticeSeverity.caution);
    });
  });

  test('most severe first, found order kept within a level', () {
    final notices = legNotices(
      _leg(
        alerts: [
          _alert('info one', effect: 'ADDITIONAL_SERVICE'),
          _alert('caution one', effect: 'DETOUR'),
          _alert('problem', effect: 'NO_SERVICE'),
          _alert('caution two'),
          _alert('info two', effect: 'NO_EFFECT'),
        ],
      ),
    );
    expect(_titles(notices), [
      'problem',
      'caution one',
      'caution two',
      'info one',
      'info two',
    ]);
  });

  group('on a change', () {
    Changeover change({required int reDeparts, String? arrivalTrack}) =>
        changeoversOf(
          buildDisplayLegs([
            Leg.fromJson({
              'mode': 'HIGHSPEED_RAIL',
              'startTime': _at(-40),
              'endTime': _at(0),
              'duration': 2400,
              'realTime': true,
              'from': _place('S', track: '8'),
              'to': {..._place('M', track: arrivalTrack), 'arrival': _at(0)},
            }),
            Leg.fromJson({
              'mode': 'WALK',
              'startTime': _at(0),
              'endTime': _at(5),
              'duration': 300,
              'from': {..._place('M'), 'arrival': _at(0)},
              'to': _place('M'),
            }),
            Leg.fromJson({
              'mode': 'REGIONAL_RAIL',
              'startTime': _at(reDeparts),
              'endTime': _at(reDeparts + 20),
              'duration': 1200,
              'realTime': true,
              'from': {..._place('M', track: '4'), 'departure': _at(reDeparts)},
              'to': _place('H', track: '2'),
            }),
          ]),
        ).single;

    test('a missed change is a problem', () {
      final c = change(reDeparts: 2, arrivalTrack: '3');
      final notices = legNotices(c.transfer, changeover: c);
      expect(_titles(notices), [kMissedChangeMessage]);
      expect(notices.single.severity, NoticeSeverity.problem);
    });

    test('an unknown platform is a caution', () {
      final c = change(reDeparts: 10);
      final notices = legNotices(c.transfer, changeover: c);
      expect(_titles(notices), [kPlatformUnknownMessage]);
      expect(notices.single.severity, NoticeSeverity.caution);
    });

    test('missed outranks the platform, which is then beside the point', () {
      final c = change(reDeparts: 2);
      expect(_titles(legNotices(c.transfer, changeover: c)), [
        kMissedChangeMessage,
      ]);
    });
  });

  group('what the journey\'s summary counts', () {
    Leg walk({
      required int from,
      required int to,
      double lat = 49.0,
      List<Map<String, dynamic>> alerts = const [],
    }) => Leg.fromJson({
      'mode': 'WALK',
      'startTime': _at(from),
      'endTime': _at(to),
      'duration': (to - from) * 60,
      'alerts': alerts,
      'from': {'name': 'x', 'lat': lat, 'lon': 8.0},
      'to': {'name': 'y', 'lat': lat, 'lon': 8.0},
    });

    test('the blocks shown, not the feed\'s raw alerts', () {
      final lift = _alert('Lift out');
      final notices = journeyNotices([
        _leg(
          alerts: [lift],
          to: _place('B', alerts: [lift]),
          stops: [_place('X', cancelled: true)],
        ),
      ]);
      // One lift alert said twice is one block; the skipped stop is a block
      // though the feed sent no alert for it.
      expect(_titles(notices), ['One stop on the way is skipped.', 'Lift out']);
    });

    test('a walk the itinerary leaves out is not counted', () {
      // A few metres to the first stop is dropped from the screen, so an
      // alert on it is never a block.
      final notices = journeyNotices([
        walk(from: -1, to: 0, alerts: [_alert('Hidden')]),
        _leg(),
      ]);
      expect(notices, isEmpty);
    });

    test('an empty journey has nothing to count', () {
      expect(journeyNotices(const []), isEmpty);
    });
  });
}
