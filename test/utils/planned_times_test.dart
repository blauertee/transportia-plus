import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/models/itinerary.dart';
import 'package:transportia/utils/planned_times.dart';

import '../support/plan_fixtures.dart';

/// Local, so the times read the same on any machine.
final _departure = DateTime(2026, 10, 2, 16, 20);

String _shift(Object? at, Duration by) =>
    DateTime.parse(at! as String).add(by).toUtc().toIso8601String();

/// The plan as a live check would return it with every time [by] late, the
/// timetable fields left as planned.
Map<String, dynamic> _late(Map<String, dynamic> json, Duration by) {
  json['startTime'] = _shift(json['startTime'], by);
  json['endTime'] = _shift(json['endTime'], by);
  for (final leg in json['legs'] as List) {
    final map = leg as Map<String, dynamic>;
    map['startTime'] = _shift(map['startTime'], by);
    map['endTime'] = _shift(map['endTime'], by);
    final from = map['from'] as Map<String, dynamic>;
    final to = map['to'] as Map<String, dynamic>;
    if (from['departure'] != null) {
      from['departure'] = _shift(from['departure'], by);
    }
    if (to['arrival'] != null) to['arrival'] = _shift(to['arrival'], by);
  }
  return json;
}

List<DateTime> _starts(List<PlannedTimes> times) => [
  for (final t in times) t.start.toLocal(),
];

void main() {
  test('a trip on time is planned as it runs', () {
    final trip = Itinerary.fromJson(planItineraryJson(departure: _departure));
    final times = plannedLegTimes(trip);

    expect(_starts(times), [
      _departure,
      _departure.add(const Duration(minutes: 5)),
      _departure.add(const Duration(minutes: 20)),
    ]);
    expect(
      times.last.end.toLocal(),
      _departure.add(const Duration(minutes: 23)),
    );
  });

  test('a delay never moves the plan', () {
    final late = Itinerary.fromJson(
      _late(
        planItineraryJson(departure: _departure),
        const Duration(minutes: 7),
      ),
    );
    final times = plannedLegTimes(late);

    expect(
      late.legs[1].startTime.toLocal(),
      isNot(_departure.add(const Duration(minutes: 5))),
    );
    expect(_starts(times), [
      _departure,
      _departure.add(const Duration(minutes: 5)),
      _departure.add(const Duration(minutes: 20)),
    ]);
  });

  test('walks end where the ride starts and start where it ends', () {
    final trip = Itinerary.fromJson(planItineraryJson(departure: _departure));
    final times = plannedLegTimes(trip);

    expect(times[0].end, times[1].start);
    expect(times[2].start, times[1].end);
    expect(times[0].end.difference(times[0].start), const Duration(minutes: 5));
    expect(times[2].end.difference(times[2].start), const Duration(minutes: 3));
  });

  test('a leg\'s own timetable wins over its stops\'', () {
    final json = planItineraryJson(departure: _departure);
    final ride = (json['legs'] as List)[1] as Map<String, dynamic>;
    ride['scheduledStartTime'] = _shift(
      ride['startTime'],
      const Duration(minutes: -2),
    );
    ride['scheduledEndTime'] = _shift(
      ride['endTime'],
      const Duration(minutes: -2),
    );

    final times = plannedLegTimes(Itinerary.fromJson(json));

    expect(
      times[1].start.toLocal(),
      _departure.add(const Duration(minutes: 3)),
    );
    expect(
      times[0].start.toLocal(),
      _departure.subtract(const Duration(minutes: 2)),
    );
  });

  test('a ride without a timetable keeps its own times', () {
    final json = planItineraryJson(departure: _departure, withEdgeWalks: false);
    final ride = (json['legs'] as List).single as Map<String, dynamic>;
    (ride['from'] as Map).remove('scheduledDeparture');
    (ride['to'] as Map).remove('scheduledArrival');

    final times = plannedLegTimes(Itinerary.fromJson(json));

    expect(times.single.start.toLocal(), _departure);
  });

  test('a walk with no ride keeps its own times', () {
    final json = planItineraryJson(departure: _departure);
    json['legs'] = [(json['legs'] as List).first];
    final walk = Itinerary.fromJson(json);

    final times = plannedLegTimes(walk);

    expect(times.single.start, walk.legs.single.startTime);
    expect(times.single.end, walk.legs.single.endTime);
  });

  test('a trip with no legs has no times', () {
    final json = planItineraryJson(departure: _departure);
    json['legs'] = <Object>[];

    expect(plannedLegTimes(Itinerary.fromJson(json)), isEmpty);
  });
}
