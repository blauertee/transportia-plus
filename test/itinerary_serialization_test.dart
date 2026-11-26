import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/models/itinerary.dart';
import 'package:transportia/models/time_selection.dart';

/// A trimmed-down but structurally faithful `/plan` itinerary object: one
/// walk leg feeding a transit leg, with the fields the parser reads.
const String _planItineraryJson = '''
{
  "duration": 1500,
  "startTime": "2026-08-05T07:04:00Z",
  "endTime": "2026-08-05T07:29:00Z",
  "transfers": 0,
  "legs": [
    {
      "mode": "WALK",
      "startTime": "2026-08-05T07:04:00Z",
      "endTime": "2026-08-05T07:10:00Z",
      "duration": 360,
      "distance": 420.5,
      "from": {"name": "Home", "lat": 52.52, "lon": 13.405},
      "to": {
        "name": "Hauptbahnhof",
        "lat": 52.525,
        "lon": 13.369,
        "stopId": "de:11000:900003201"
      }
    },
    {
      "mode": "RAIL",
      "startTime": "2026-08-05T07:14:00Z",
      "endTime": "2026-08-05T07:29:00Z",
      "scheduledStartTime": "2026-08-05T07:14:00Z",
      "scheduledEndTime": "2026-08-05T07:28:00Z",
      "duration": 900,
      "realTime": true,
      "tripId": "trip-re7-0714",
      "routeShortName": "RE7",
      "displayName": "RE7",
      "routeColor": "1F4E9C",
      "headsign": "Airport",
      "from": {
        "name": "Hauptbahnhof",
        "lat": 52.525,
        "lon": 13.369,
        "stopId": "de:11000:900003201",
        "track": "12"
      },
      "to": {
        "name": "Airport",
        "lat": 52.366,
        "lon": 13.503,
        "stopId": "de:12072:900260005"
      },
      "intermediateStops": [
        {"name": "Ostkreuz", "lat": 52.503, "lon": 13.469}
      ]
    }
  ]
}
''';

Map<String, dynamic> _decodePlanItinerary() =>
    jsonDecode(_planItineraryJson) as Map<String, dynamic>;

void main() {
  group('Itinerary.sourceJson', () {
    test('is captured when parsing an API itinerary', () {
      final json = _decodePlanItinerary();
      final itinerary = Itinerary.fromJson(json);

      expect(itinerary.sourceJson, isNotNull);
      expect(itinerary.sourceJson, same(json));
    });

    test('round-trips through encode/decode into an equivalent itinerary', () {
      final original = Itinerary.fromJson(_decodePlanItinerary());

      final encoded = jsonEncode(original.sourceJson);
      final restored = Itinerary.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );

      expect(restored.duration, original.duration);
      expect(restored.startTime, original.startTime);
      expect(restored.endTime, original.endTime);
      expect(restored.transfers, original.transfers);
      expect(restored.legs.length, original.legs.length);
      expect(restored.walkingDistance, original.walkingDistance);

      for (var i = 0; i < original.legs.length; i++) {
        final a = original.legs[i];
        final b = restored.legs[i];
        expect(b.mode, a.mode);
        expect(b.fromName, a.fromName);
        expect(b.toName, a.toName);
        expect(b.startTime, a.startTime);
        expect(b.endTime, a.endTime);
        expect(b.scheduledStartTime, a.scheduledStartTime);
        expect(b.tripId, a.tripId);
        expect(b.routeShortName, a.routeShortName);
        expect(b.fromStopId, a.fromStopId);
        expect(b.toStopId, a.toStopId);
        expect(b.fromTrack, a.fromTrack);
        expect(b.realTime, a.realTime);
        expect(b.intermediateStops.length, a.intermediateStops.length);
        // The street path a leg was routed over. Losing it draws a walk as a
        // straight line from origin to station.
        expect(b.legGeometry?.points, a.legGeometry?.points);
        expect(b.legGeometry?.precision, a.legGeometry?.precision);
      }
    });

    test('carries the live times through a refresh via withLegs', () {
      final original = Itinerary.fromJson(_decodePlanItinerary());

      // The refresh path: the ride comes back from the server five minutes
      // late, on another platform.
      final rideJson = Map<String, dynamic>.of(
        (_decodePlanItinerary()['legs'] as List).last as Map<String, dynamic>,
      );
      rideJson
        ..['startTime'] = '2026-08-05T07:19:00Z'
        ..['endTime'] = '2026-08-05T07:34:00Z'
        ..['from'] = {
          ...rideJson['from'] as Map<String, dynamic>,
          'track': '14',
        };
      final refreshed = original.withLegs([
        original.legs.first,
        original.legs.last.withRealTimeFrom(Leg.fromJson(rideJson)),
      ]);

      // What is stored is what is on screen, so a trip reopened offline
      // shows the live times rather than the plan under a live stamp.
      final reopened = Itinerary.fromJson(
        jsonDecode(jsonEncode(refreshed.sourceJson)) as Map<String, dynamic>,
      );
      expect(reopened.endTime, DateTime.parse('2026-08-05T07:34:00Z'));
      expect(reopened.duration, refreshed.duration);
      expect(reopened.legs.last.startTime, refreshed.legs.last.startTime);
      expect(reopened.legs.last.fromTrack, '14');
      // What the refresh does not touch stays as planned.
      expect(
        reopened.legs.last.scheduledEndTime,
        original.legs.last.scheduledEndTime,
      );
      expect(reopened.legs.last.routeColor, '1F4E9C');
      expect(reopened.legs.first.endTime, original.legs.first.endTime);
      // And the connection still knows when it was first meant to leave.
      expect(reopened.plannedStartTime, original.startTime);
    });

    test('is dropped by withLegs when a leg has none to give', () {
      final original = Itinerary.fromJson(_decodePlanItinerary());
      final builtInCode = Leg(
        mode: 'RAIL',
        from: const TransitPlace(
          name: 'Hauptbahnhof',
          lat: 52.525,
          lon: 13.369,
        ),
        to: const TransitPlace(name: 'Airport', lat: 52.366, lon: 13.503),
        startTime: DateTime.parse('2026-08-05T07:19:00Z'),
        endTime: DateTime.parse('2026-08-05T07:34:00Z'),
        duration: 900,
        realTime: true,
      );

      // Keeping the old snapshot would store the plan as if it were live.
      final refreshed = original.withLegs([
        original.legs.first,
        original.legs.last.withRealTimeFrom(builtInCode),
      ]);
      expect(refreshed.endTime, DateTime.parse('2026-08-05T07:34:00Z'));
      expect(refreshed.sourceJson, isNull);
    });

    test('is null for itineraries built in code rather than parsed', () {
      final itinerary = Itinerary(
        duration: 60,
        startTime: DateTime.parse('2026-08-05T07:04:00Z'),
        endTime: DateTime.parse('2026-08-05T07:05:00Z'),
        transfers: 0,
        legs: const [],
      );

      expect(itinerary.sourceJson, isNull);
    });
  });

  group('TimeSelection serialization', () {
    test('round-trips an explicit depart-at selection', () {
      final original = TimeSelection(
        dateTime: DateTime(2026, 8, 5, 7, 14),
        isArriveBy: false,
      );

      final restored = TimeSelection.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );

      expect(restored.dateTime, original.dateTime);
      expect(restored.isArriveBy, isFalse);
      expect(restored.isNow, isFalse);
    });

    test('round-trips an arrive-by selection', () {
      final original = TimeSelection(
        dateTime: DateTime(2026, 8, 5, 9, 0),
        isArriveBy: true,
      );

      final restored = TimeSelection.fromJson(original.toJson());

      expect(restored.dateTime, original.dateTime);
      expect(restored.isArriveBy, isTrue);
    });

    test('preserves the "now" flag', () {
      final restored = TimeSelection.fromJson(TimeSelection.now().toJson());

      expect(restored.isNow, isTrue);
      expect(restored.toDisplayString(), 'Now');
    });
  });
}
