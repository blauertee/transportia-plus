import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/models/itinerary.dart';
import 'package:transportia/models/saved_trip.dart';
import 'package:transportia/services/itinerary_refresh_service.dart';

/// A real response from `test/fixtures/transitous/`.
Map<String, dynamic> _json(String name) =>
    jsonDecode(File('test/fixtures/transitous/$name').readAsStringSync())
        as Map<String, dynamic>;

Itinerary _fixture(String name) => Itinerary.fromJson(_json(name));

Future<Itinerary> _refreshWhole(Itinerary stored, Itinerary fresh) async {
  final result = await ItineraryRefreshService.refresh(
    stored,
    fetchItinerary: (_) async => fresh,
    fetchTripDetails: ({required String tripId}) async =>
        fail('should not fall back to /trip'),
  );
  return result.itinerary;
}

/// [itinerary]'s snapshot as a saved trip reads it back: through a string,
/// as SharedPreferences stores it.
Itinerary _reopened(Itinerary itinerary) {
  expect(itinerary.sourceJson, isNotNull);
  return Itinerary.fromJson(
    jsonDecode(jsonEncode(itinerary.sourceJson)) as Map<String, dynamic>,
  );
}

/// The snapshot says what the merged itinerary says, leg for leg.
void _expectSnapshotMatches(Itinerary merged) {
  final reopened = _reopened(merged);
  expect(reopened.startTime, merged.startTime);
  expect(reopened.endTime, merged.endTime);
  expect(reopened.duration, merged.duration);
  expect(reopened.transfers, merged.transfers);
  expect(reopened.legs, hasLength(merged.legs.length));
  for (final (i, leg) in merged.legs.indexed) {
    final back = reopened.legs[i];
    final where = 'leg $i (${leg.mode})';
    expect(back.mode, leg.mode, reason: where);
    expect(back.tripId, leg.tripId, reason: where);
    expect(back.startTime, leg.startTime, reason: where);
    expect(back.endTime, leg.endTime, reason: where);
    expect(back.duration, leg.duration, reason: where);
    expect(back.scheduledStartTime, leg.scheduledStartTime, reason: where);
    expect(back.scheduledEndTime, leg.scheduledEndTime, reason: where);
    expect(back.realTime, leg.realTime, reason: where);
    expect(back.cancelled, leg.cancelled, reason: where);
    expect(back.fromName, leg.fromName, reason: where);
    expect(back.toName, leg.toName, reason: where);
    expect(back.fromTrack, leg.fromTrack, reason: where);
    expect(back.toTrack, leg.toTrack, reason: where);
    expect(back.from.departure, leg.from.departure, reason: where);
    expect(back.to.arrival, leg.to.arrival, reason: where);
    expect(back.from.cancelled, leg.from.cancelled, reason: where);
    expect(
      back.intermediateStops.map((s) => s.name),
      leg.intermediateStops.map((s) => s.name),
      reason: where,
    );
    expect(
      back.alerts.map((a) => a.headerText),
      leg.alerts.map((a) => a.headerText),
      reason: where,
    );
    expect(back.legGeometry?.points, leg.legGeometry?.points, reason: where);
    expect(back.rental?.providerId, leg.rental?.providerId, reason: where);
    expect(back.tripFrom?.name, leg.tripFrom?.name, reason: where);
    expect(back.tripTo?.name, leg.tripTo?.name, reason: where);
  }
}

void main() {
  group('the snapshot after a whole-itinerary refresh', () {
    final planned = _fixture('plan_itinerary_rental.json');

    test('says what the merged legs say', () async {
      final merged = await _refreshWhole(
        planned,
        _fixture('refresh_itinerary_rental.json'),
      );
      _expectSnapshotMatches(merged);
    });

    test('takes a swapped vehicle and its new times', () async {
      final merged = await _refreshWhole(
        planned,
        _fixture('refresh_itinerary_rental_swapped.json'),
      );
      _expectSnapshotMatches(merged);
      expect(_reopened(merged).startTime, isNot(planned.startTime));
    });

    test('marks a vehicle out of reach cancelled', () async {
      final merged = await _refreshWhole(
        planned,
        _fixture('refresh_itinerary_rental_none.json'),
      );
      _expectSnapshotMatches(merged);
      expect(_reopened(merged).legs.any((leg) => leg.cancelled), isTrue);
    });

    test('keeps legs the server could not find again as planned', () async {
      final bikes = _fixture('refresh_itinerary_bike.json');
      final merged = await _refreshWhole(
        bikes,
        _fixture('refresh_itinerary_bike_placeholders.json'),
      );
      _expectSnapshotMatches(merged);
      expect(_reopened(merged).legs.any((leg) => leg.cancelled), isFalse);
    });
  });

  group('the snapshot after a per-trip refresh', () {
    test('holds only the stops the journey rides', () async {
      final planned = Itinerary.fromJson(
        (_json('plan.json')['itineraries'] as List).first
            as Map<String, dynamic>,
      );
      final trip = _fixture('trip.json');

      final result = await ItineraryRefreshService.refresh(
        planned,
        fetchTripDetails: ({required String tripId}) async =>
            tripId == trip.legs.single.tripId ? trip : throw StateError(''),
      );

      expect(result.didRefresh, isTrue);
      _expectSnapshotMatches(result.itinerary);
      final ride = _reopened(
        result.itinerary,
      ).legs.firstWhere((leg) => leg.tripId == trip.legs.single.tripId);
      // `/trip` answered with the line from Ahrensfelde to Potsdam.
      expect(ride.fromName, planned.legs[1].fromName);
      expect(ride.toName, planned.legs[1].toName);
      expect(
        ride.intermediateStops.length,
        lessThan(trip.legs.single.intermediateStops.length),
      );
    });
  });

  group('a stop merged as JSON', () {
    test('agrees with the stop merged as a model', () {
      final plannedRide = _json('plan_itinerary_rental.json')['legs'] as List;
      final freshRide = _json('refresh_itinerary_rental.json')['legs'] as List;
      for (final end in ['from', 'to']) {
        final planned = (plannedRide[3] as Map)[end] as Map<String, dynamic>;
        final fresh = Map<String, dynamic>.of(
          (freshRide[3] as Map)[end] as Map<String, dynamic>,
        );
        // What a refresh moves, so both merges have something to choose.
        fresh['track'] = '9';
        fresh['departure'] = '2026-10-04T20:57:00Z';
        fresh.remove('scheduledTrack');

        final asModel = TransitPlace.fromJson(
          planned,
        ).mergeRealTime(TransitPlace.fromJson(fresh));
        final asJson = TransitPlace.fromJson(
          TransitPlace.mergeRealTimeJson(planned, fresh),
        );
        expect(asJson.name, asModel.name);
        expect(asJson.stopId, asModel.stopId);
        expect(asJson.track, '9');
        expect(asJson.track, asModel.track);
        expect(asJson.scheduledTrack, asModel.scheduledTrack);
        expect(asJson.departure, asModel.departure);
        expect(asJson.arrival, asModel.arrival);
        expect(asJson.scheduledDeparture, asModel.scheduledDeparture);
        expect(asJson.scheduledArrival, asModel.scheduledArrival);
        expect(asJson.cancelled, asModel.cancelled);
        expect(asJson.alerts.length, asModel.alerts.length);
      }
    });

    test('adds no keys that neither side had', () {
      final merged = TransitPlace.mergeRealTimeJson(
        {'name': 'A', 'lat': 52.5, 'lon': 13.4},
        {'name': 'A'},
      );
      expect(merged, {'name': 'A', 'lat': 52.5, 'lon': 13.4});
    });
  });

  group('a saved trip kept live', () {
    final planned = _fixture('plan_itinerary_rental.json');
    final saved = SavedTrip.fromItinerary(
      itinerary: planned,
      savedAt: DateTime.utc(2026, 10, 4, 20),
    );

    test('reopens on the live times', () async {
      final merged = await _refreshWhole(
        planned,
        _fixture('refresh_itinerary_rental_swapped.json'),
      );
      final at = DateTime.utc(2026, 10, 4, 20, 30);
      final live = saved.withLiveItinerary(merged, at: at);

      final reopened = SavedTrip.fromJson(
        jsonDecode(jsonEncode(live.toJson())) as Map<String, dynamic>,
      );
      expect(reopened.liveUpdatedAt, at);
      expect(reopened.departureTime, merged.startTime);
      expect(reopened.itinerary.startTime, merged.startTime);
      expect(
        reopened.itinerary.legs.map((leg) => leg.startTime),
        merged.legs.map((leg) => leg.startTime),
      );
    });

    test('is still the same connection once its times move', () async {
      final merged = await _refreshWhole(
        planned,
        _fixture('refresh_itinerary_rental_swapped.json'),
      );
      expect(merged.startTime, isNot(planned.startTime));

      // Saving the refreshed itinerary again, or reopening the live one,
      // has to find the trip already saved rather than offer a second.
      expect(SavedTrip.fromItinerary(itinerary: merged).id, saved.id);
      final live = saved.withLiveItinerary(merged, at: DateTime.utc(2026));
      expect(SavedTrip.fromItinerary(itinerary: live.itinerary).id, saved.id);
      // A second refresh does not lose where it started.
      final again = await _refreshWhole(
        live.itinerary,
        _fixture('refresh_itinerary_rental.json'),
      );
      expect(again.plannedStartTime, planned.startTime);
    });

    test('a trip stored before snapshots went live still reads', () {
      // Saved trips written by earlier builds carry the plan's JSON and no
      // planned-start key; their ids were built from its start time.
      final stored = SavedTrip.fromJson(
        jsonDecode(jsonEncode(saved.toJson())) as Map<String, dynamic>,
      );
      expect(
        stored.itinerary.sourceJson!.containsKey('plannedStartTime'),
        isFalse,
      );
      expect(stored.itinerary.plannedStartTime, planned.startTime);
      expect(SavedTrip.fromItinerary(itinerary: stored.itinerary).id, saved.id);
    });
  });
}
