import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/models/itinerary.dart';
import 'package:transportia/services/itinerary_refresh_service.dart';

/// A real response from `test/fixtures/transitous/`.
Itinerary _fixture(String name) => Itinerary.fromJson(
  jsonDecode(File('test/fixtures/transitous/$name').readAsStringSync())
      as Map<String, dynamic>,
);

Future<ItineraryRefreshResult> _refresh(Itinerary stored, Itinerary fresh) =>
    ItineraryRefreshService.refresh(
      stored,
      fetchItinerary: (_) async => fresh,
      fetchTripDetails: ({required String tripId}) async =>
          fail('should not fall back to /trip'),
    );

final DateTime _t0 = DateTime.utc(2026, 10, 4, 16);

Leg _leg(
  String mode, {
  String? tripId,
  required int from,
  required int to,
  bool cancelled = false,
  bool realTime = false,
  String? geometry,
}) => Leg(
  mode: mode,
  from: const TransitPlace(name: 'A', lat: 52.5, lon: 13.4),
  to: const TransitPlace(name: 'B', lat: 52.4, lon: 13.5),
  startTime: _t0.add(Duration(minutes: from)),
  endTime: _t0.add(Duration(minutes: to)),
  duration: (to - from) * 60,
  tripId: tripId,
  cancelled: cancelled,
  realTime: realTime,
  legGeometry: geometry == null
      ? null
      : EncodedPolyline(points: geometry, precision: 6, length: 2),
);

Itinerary _itinerary(List<Leg> legs) => Itinerary(
  duration: legs.last.endTime.difference(legs.first.startTime).inSeconds,
  startTime: legs.first.startTime,
  endTime: legs.last.endTime,
  transfers: 0,
  legs: legs,
);

void main() {
  group('the journey from #35', () {
    // Planned: 24 minutes by bike, the S3, 22 minutes by bike. Refreshed
    // within the rider's 15-minute default, so the server could not find
    // either bike leg again and sent cancelled placeholders.
    final planned = _fixture('refresh_itinerary_bike.json');
    final placeholders = _fixture('refresh_itinerary_bike_placeholders.json');

    test('the capture really is placeholders', () {
      final bikes = placeholders.legs.where((l) => l.mode == 'BIKE');
      expect(bikes.every((l) => l.cancelled), isTrue);
      expect(
        bikes.expand((l) => l.alerts).map((a) => a.headerText),
        everyElement('no offset found'),
      );
    });

    test('keeps both bike legs as planned', () async {
      final result = await _refresh(planned, placeholders);
      final legs = result.itinerary.legs;

      expect(legs.map((l) => l.mode), ['BIKE', 'SUBURBAN', 'BIKE']);
      // A bike to and from the station is no change of vehicle.
      expect(result.itinerary.transfers, 0);
      expect(legs.any((l) => l.cancelled), isFalse);
      expect(legs.expand((l) => l.alerts), isEmpty);
      expect(
        legs.first.legGeometry?.points,
        planned.legs.first.legGeometry?.points,
      );
      expect(legs.first.steps, isNotEmpty);
    });

    test('is not reported as a changed connection', () async {
      final result = await _refresh(planned, placeholders);
      expect(result.freshness, ItineraryFreshness.live);
      expect(result.didRefresh, isTrue);
    });

    test('keeps the ride\'s shape while taking its new data', () async {
      final result = await _refresh(planned, placeholders);
      final ride = result.itinerary.legs[1];
      expect(ride.tripId, planned.legs[1].tripId);
      expect(ride.legGeometry?.points, planned.legs[1].legGeometry?.points);
    });
  });

  group('a shared vehicle', () {
    // Planned: walk to a Dott scooter, ride it, walk to Strausberger Platz,
    // the U5, a walk.
    final planned = _fixture('plan_itinerary_rental.json');

    test('found again is taken as the server now has it', () async {
      final result = await _refresh(
        planned,
        _fixture('refresh_itinerary_rental.json'),
      );
      expect(result.freshness, ItineraryFreshness.live);
      expect(result.itinerary.legs[1].rental?.providerId, 'de-DottBerlin');
    });

    test('swapped for another, comes with its own way there', () async {
      // Refreshed without the rental filters: the server picked a Call a
      // Bike bicycle at a different spot.
      final swapped = _fixture('refresh_itinerary_rental_swapped.json');
      final result = await _refresh(planned, swapped);
      final firstMile = result.itinerary.firstMileLegs;

      expect(firstMile.map((l) => l.mode), ['WALK', 'RENTAL', 'WALK']);
      expect(firstMile[1].rental?.providerId, 'de-CallaBike');
      expect(
        firstMile.map((l) => l.legGeometry?.points),
        swapped.firstMileLegs.map((l) => l.legGeometry?.points),
      );
      expect(result.freshness, ItineraryFreshness.live);
    });

    test('out of reach is a changed connection', () async {
      final result = await _refresh(
        planned,
        _fixture('refresh_itinerary_rental_none.json'),
      );
      expect(result.freshness, ItineraryFreshness.changed);
    });

    test(
      'out of reach keeps the planned way there, vehicle cancelled',
      () async {
        // The server sends one nameless, pathless RENTAL placeholder for the
        // whole walk-ride-walk; the planned stretch says the same and more.
        final none = _fixture('refresh_itinerary_rental_none.json');
        expect(none.firstMileLegs.single.mode, 'RENTAL');
        expect(none.firstMileLegs.single.from.name, isEmpty);

        final result = await _refresh(planned, none);
        final firstMile = result.itinerary.firstMileLegs;

        expect(firstMile.map((l) => l.mode), ['WALK', 'RENTAL', 'WALK']);
        expect(firstMile.map((l) => l.cancelled), [false, true, false]);
        expect(firstMile[1].rental?.providerId, 'de-DottBerlin');
        expect(firstMile[1].alerts, isEmpty);
        expect(
          firstMile[1].legGeometry?.points,
          planned.firstMileLegs[1].legGeometry?.points,
        );
      },
    );

    test('out of reach leaves the walk at the other end alone', () async {
      // The same capture's last walk was a placeholder too, for the same
      // too-short limit; the rider's feet have not gone anywhere.
      final result = await _refresh(
        planned,
        _fixture('refresh_itinerary_rental_none.json'),
      );
      final lastMile = result.itinerary.lastMileLegs;

      expect(lastMile.single.mode, 'WALK');
      expect(lastMile.single.cancelled, isFalse);
      expect(
        lastMile.single.legGeometry?.points,
        planned.lastMileLegs.single.legGeometry?.points,
      );
    });
  });

  group('the rides and changes in between', () {
    final planned = _itinerary([
      _leg('WALK', from: 0, to: 5, geometry: 'walk-in'),
      _leg('SUBWAY', tripId: 'u5', from: 5, to: 15, geometry: 'u5'),
      _leg('WALK', from: 15, to: 18, geometry: 'change'),
      _leg('SUBURBAN', tripId: 's3', from: 20, to: 30, geometry: 's3'),
      _leg('WALK', from: 30, to: 34, geometry: 'walk-out'),
    ]);

    test('a ride the server cannot find again is a changed connection, '
        'not a different journey', () async {
      // `make_dummy_leg` keeps the mode and drops the trip id.
      final result = await _refresh(
        planned,
        _itinerary([
          _leg('WALK', from: 0, to: 5),
          _leg('SUBWAY', tripId: 'u5', from: 5, to: 15, realTime: true),
          _leg('WALK', from: 15, to: 18),
          _leg('SUBURBAN', from: 20, to: 30, cancelled: true),
          _leg('WALK', from: 30, to: 34),
        ]),
      );

      expect(result.freshness, ItineraryFreshness.changed);
      expect(result.itinerary.legs[3].cancelled, isTrue);
      expect(result.itinerary.legs[3].tripId, 's3');
    });

    test(
      'a ride the server cannot find again keeps the operator\'s say',
      () async {
        // The stand-in's only alert is the server's error text, which is not
        // something to show a rider.
        final withAlert = Leg.fromJson({
          'mode': 'SUBURBAN',
          'startTime': _t0.add(const Duration(minutes: 20)).toIso8601String(),
          'endTime': _t0.add(const Duration(minutes: 30)).toIso8601String(),
          'duration': 600,
          'cancelled': true,
          'alerts': [
            {'headerText': 'adjacent transit leg couldn\'t be reconstructed'},
          ],
          'from': {'name': '', 'lat': 52.5, 'lon': 13.4, 'cancelled': true},
          'to': {'name': '', 'lat': 52.4, 'lon': 13.5, 'cancelled': true},
        });
        final result = await _refresh(
          planned,
          _itinerary([
            _leg('WALK', from: 0, to: 5),
            _leg('SUBWAY', tripId: 'u5', from: 5, to: 15),
            _leg('WALK', from: 15, to: 18),
            withAlert,
            _leg('WALK', from: 30, to: 34),
          ]),
        );

        expect(result.itinerary.legs[3].cancelled, isTrue);
        expect(result.itinerary.legs[3].alerts, isEmpty);
      },
    );

    test(
      'a stand-in keeps the ride even when it has no stored shape',
      () async {
        final shapeless = _itinerary([
          _leg('SUBWAY', tripId: 'u5', from: 5, to: 15),
          _leg('WALK', from: 15, to: 18),
          _leg('SUBURBAN', tripId: 's3', from: 20, to: 30),
        ]);
        final result = await _refresh(
          shapeless,
          _itinerary([
            _leg('SUBWAY', tripId: 'u5', from: 5, to: 15),
            _leg('WALK', from: 15, to: 18),
            _leg('SUBURBAN', from: 20, to: 30, cancelled: true),
          ]),
        );
        final ride = result.itinerary.legs.last;

        expect(ride.tripId, 's3');
        expect(ride.cancelled, isTrue);
      },
    );

    test('a change with no way through is a changed connection', () async {
      // A footpath the server cannot route — a lift out of order on the only
      // step-free path — comes back cancelled. Unlike the first mile, that is
      // news.
      final result = await _refresh(
        planned,
        _itinerary([
          _leg('WALK', from: 0, to: 5),
          _leg('SUBWAY', tripId: 'u5', from: 5, to: 15),
          _leg('WALK', from: 15, to: 18, cancelled: true),
          _leg('SUBURBAN', tripId: 's3', from: 20, to: 30),
          _leg('WALK', from: 30, to: 34),
        ]),
      );

      expect(result.freshness, ItineraryFreshness.changed);
      expect(result.itinerary.legs[2].cancelled, isTrue);
    });

    test('a different ride is still a different journey', () async {
      var tripLookups = 0;
      final result = await ItineraryRefreshService.refresh(
        planned,
        fetchItinerary: (_) async => _itinerary([
          _leg('WALK', from: 0, to: 5),
          _leg('SUBWAY', tripId: 'u5', from: 5, to: 15),
          _leg('WALK', from: 15, to: 18),
          _leg('SUBURBAN', tripId: 's7', from: 20, to: 30),
          _leg('WALK', from: 30, to: 34),
        ]),
        fetchTripDetails: ({required String tripId}) async {
          tripLookups++;
          throw StateError('offline');
        },
      );

      expect(tripLookups, 2);
      expect(result.freshness, ItineraryFreshness.scheduled);
    });

    test(
      'a first mile that appears from nowhere is a different journey',
      () async {
        final stationToStation = _itinerary(planned.rideLegs);
        var tripLookups = 0;
        await ItineraryRefreshService.refresh(
          stationToStation,
          fetchItinerary: (_) async => planned,
          fetchTripDetails: ({required String tripId}) async {
            tripLookups++;
            throw StateError('offline');
          },
        );

        expect(tripLookups, 2);
      },
    );

    test(
      'a walk found again moves with a delayed ride and keeps its path',
      () async {
        final result = await _refresh(
          planned,
          _itinerary([
            _leg('WALK', from: 0, to: 5),
            _leg('SUBWAY', tripId: 'u5', from: 5, to: 15),
            _leg('WALK', from: 15, to: 18),
            _leg('SUBURBAN', tripId: 's3', from: 26, to: 36, realTime: true),
            _leg('WALK', from: 36, to: 40),
          ]),
        );
        final walkOut = result.itinerary.legs.last;

        expect(walkOut.startTime, _t0.add(const Duration(minutes: 36)));
        expect(walkOut.legGeometry?.points, 'walk-out');
        expect(result.freshness, ItineraryFreshness.live);
      },
    );
  });
}
