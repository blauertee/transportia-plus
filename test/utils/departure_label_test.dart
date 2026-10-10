import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/models/itinerary.dart';
import 'package:transportia/utils/departure_label.dart';

import '../support/plan_fixtures.dart';

final DateTime _start = DateTime(2026, 10, 4, 18, 6);

Itinerary _transit() =>
    Itinerary.fromJson(planItineraryJson(departure: _start));

/// A bike ride straight to the destination, as the planner returns it in
/// `direct`: one street leg, no trip id.
Itinerary _bikeOnly() => Itinerary.fromJson({
  'duration': 1440,
  'startTime': _start.toUtc().toIso8601String(),
  'endTime': _start.add(const Duration(minutes: 24)).toUtc().toIso8601String(),
  'transfers': 0,
  'legs': [
    {
      'mode': 'BIKE',
      'startTime': _start.toUtc().toIso8601String(),
      'endTime': _start
          .add(const Duration(minutes: 24))
          .toUtc()
          .toIso8601String(),
      'duration': 1440,
      'from': {'name': 'START', 'lat': 52.466, 'lon': 13.214},
      'to': {'name': 'END', 'lat': 52.545, 'lon': 13.385},
    },
  ],
}, isDirect: true);

void main() {
  group('a journey with a ride', () {
    test('has departed once its start is behind the clock', () {
      final label = departureLabel(
        _transit(),
        now: _start.add(const Duration(seconds: 1)),
      );
      expect(label?.text, 'Departed');
      expect(label?.hasDeparted, isTrue);
    });

    test('has departed at the very second it leaves', () {
      expect(departureLabel(_transit(), now: _start)?.text, 'Departed');
    });

    test('says now inside the last minute', () {
      final label = departureLabel(
        _transit(),
        now: _start.subtract(const Duration(seconds: 59)),
      );
      expect(label?.text, 'Depart now');
      expect(label?.hasDeparted, isFalse);
    });

    test('counts down from a minute out', () {
      final label = departureLabel(
        _transit(),
        now: _start.subtract(const Duration(minutes: 12)),
      );
      expect(label?.text, 'Depart in 12m');
      expect(label?.hasDeparted, isFalse);
    });
  });

  group('a journey without a ride', () {
    test('knows it has none', () {
      expect(_bikeOnly().hasTransit, isFalse);
      expect(_transit().hasTransit, isTrue);
    });

    // The planner starts a direct journey at the searched minute, so a
    // search for "now" is behind the clock by the time it is drawn.
    test('says nothing once its start has passed', () {
      expect(
        departureLabel(
          _bikeOnly(),
          now: _start.add(const Duration(seconds: 40)),
        ),
        isNull,
      );
    });

    test('says nothing at the very second it starts', () {
      expect(departureLabel(_bikeOnly(), now: _start), isNull);
    });

    test('still counts down to a later start', () {
      final label = departureLabel(
        _bikeOnly(),
        now: _start.subtract(const Duration(hours: 2)),
      );
      expect(label?.text, 'Depart in 2h 0m');
      expect(label?.hasDeparted, isFalse);
    });
  });
}
