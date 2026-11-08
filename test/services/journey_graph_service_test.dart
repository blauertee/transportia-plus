import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/models/itinerary.dart';
import 'package:transportia/models/itinerary_response.dart';
import 'package:transportia/models/transitous/itinerary_id.dart';
import 'package:transportia/services/journey_graph_service.dart';
import 'package:transportia/utils/journey_graph.dart';

List<Itinerary> _load(String name) => ItineraryResponse.fromJson(
  jsonDecode(File('test/fixtures/transitous/$name.json').readAsStringSync())
      as Map<String, dynamic>,
).itineraries;

void main() {
  final results = _load('plan_journey_graph');
  final onward = _load('plan_journey_graph_onward');
  final viaIngolstadt = results.firstWhere(
    (it) => it.legs.any((leg) => leg.displayName == 'ICE 1009'),
  );
  final ice1009 = viaIngolstadt.legs.firstWhere(
    (leg) => leg.displayName == 'ICE 1009',
  );
  final joined = continueAfter(viaIngolstadt, ice1009, onward);

  /// [journey] as the planner gives it back: with an id.
  Itinerary planned(Itinerary journey, {String id = 'planned'}) =>
      Itinerary.fromJson({...journey.sourceJson!, 'id': id});

  group('planJoined', () {
    test('takes the planned journey, with its id', () async {
      final asked = <ItineraryId>[];
      var i = 0;
      final found = await JourneyGraphService.planJoined(
        joined,
        ice1009,
        fetch: (id) async {
          asked.add(id);
          return planned(joined[i++], id: 'id$i');
        },
      );

      expect(asked, hasLength(joined.length));
      expect(found.map((it) => it.id), ['id1', 'id2']);
    });

    test('keeps the joined journey when planning fails', () async {
      final found = await JourneyGraphService.planJoined(
        joined,
        ice1009,
        fetch: (_) async => throw Exception('offline'),
      );

      expect(found, joined);
    });

    test('keeps the joined journey when other rides come back', () async {
      final found = await JourneyGraphService.planJoined(
        joined,
        ice1009,
        fetch: (_) async => planned(joined.last),
      );

      expect(found.first, same(joined.first));
      expect(found.last.id, 'planned');
    });

    test('keeps the joined journey when no id comes back', () async {
      final found = await JourneyGraphService.planJoined(
        joined,
        ice1009,
        fetch: (_) async => Itinerary.fromJson(joined.first.sourceJson!),
      );

      expect(found.first, same(joined.first));
    });
  });

  group('staying on the locked ride', () {
    // ICE 1009 got off one stop before Ingolstadt: staying on to Ingolstadt
    // is the way on that a search from that stop cannot find.
    final stops = ice1009.intermediateStops;
    final before = stops.last;
    final short = ice1009.sliceBetween(ice1009.from, before);
    final lock = RideLock(
      viaIngolstadt.withLegs([
        for (final leg in viaIngolstadt.legs)
          if (leg == ice1009) short else leg,
      ]),
      short,
    );

    test('finds the stop after where the ride gets off', () {
      expect(stopAfter(ice1009, short)?.stopId, ice1009.to.stopId);
      expect(stopAfter(ice1009, ice1009), isNull);
    });

    test('rides on to the next stop and changes there', () {
      final (joined, ride) = stayOn(
        lock,
        ice1009,
        ice1009.to,
        onward.first,
        margin: JourneyGraphService.changeMargin,
      )!;

      expect(ride.to.stopId, ice1009.to.stopId);
      expect(ride.from.stopId, ice1009.from.stopId);
      expect(joined.legs, contains(ride));
      expect(joined.legs, isNot(contains(short)));
      expect(joined.endTime, onward.first.endTime);
    });

    test('drops a change at the next stop made in less than the margin', () {
      expect(
        stayOn(
          lock,
          ice1009,
          ice1009.to,
          onward.first,
          margin:
              onward.first.startTime.difference(ice1009.endTime) +
              const Duration(minutes: 1),
        ),
        isNull,
      );
    });

    test('carries on in the same ride when the search does', () async {
      // From the stop before Ingolstadt, the search boards ICE 1009 again.
      final again = Itinerary(
        duration: 0,
        startTime: before.timeAtStop!,
        endTime: onward.first.endTime,
        transfers: 1,
        legs: [ice1009.sliceBetween(before, ice1009.to), ...onward.first.legs],
      );

      final (joined, ride) = stayOn(
        lock,
        ice1009,
        before,
        again,
        margin: JourneyGraphService.changeMargin,
      )!;

      expect(ride.to.stopId, ice1009.to.stopId);
      expect(joined.legs.where((leg) => leg.tripId == ice1009.tripId), [ride]);
    });

    test('plans each as one journey, from the stop after', () async {
      DateTime? searchedAt;
      final found = await JourneyGraphService.stayingOn(
        lock,
        trip: (_) async => ice1009,
        plan: (from, at) async {
          expect(from.stopId, ice1009.to.stopId);
          searchedAt = at;
          return onward;
        },
        fetch: (id) async => throw Exception('offline'),
      );

      expect(searchedAt, ice1009.to.timeAtTerminus);
      expect(found, isNotEmpty);
      expect(found.first.legs.any((leg) => leg.tripId == ice1009.tripId), true);
    });

    test('finds nothing at the end of the line', () async {
      final found = await JourneyGraphService.stayingOn(
        RideLock(viaIngolstadt, ice1009),
        trip: (_) async => ice1009,
        plan: (_, _) async => fail('nothing to search'),
        fetch: (_) async => fail('nothing to plan'),
      );

      expect(found, isEmpty);
    });

    test('merges with the changes, by arrival, each journey once', () {
      final changing = joined;
      final merged = JourneyGraphService.mergeOnward(changing, [
        joined.last,
        // The way the lock was found: on the same vehicles as the first
        // change, and no sooner.
        lock.itinerary,
      ]);

      expect(merged, changing);
      final arrivals = merged.map((it) => it.endTime).toList();
      expect(arrivals, [...arrivals]..sort());
    });

    test('leaves out staying on for the same vehicles, a stop later', () {
      // Staying on to Ingolstadt and boarding the onward train there,
      // when changing a stop earlier boards the very same train.
      final (stayingOn, _) = stayOn(
        lock,
        ice1009,
        ice1009.to,
        onward.first,
        margin: JourneyGraphService.changeMargin,
      )!;
      final changing = stayingOn.withLegs([
        for (final leg in stayingOn.legs)
          if (leg.tripId == ice1009.tripId) short else leg,
      ]);

      expect(JourneyGraphService.mergeOnward([changing], [stayingOn]), [
        changing,
      ]);
    });

    test('keeps staying on that arrives earlier on the same vehicles', () {
      final (stayingOn, _) = stayOn(
        lock,
        ice1009,
        ice1009.to,
        onward.first,
        margin: JourneyGraphService.changeMargin,
      )!;
      final later = stayingOn.legs.last;
      final changing = Itinerary(
        duration: stayingOn.duration + 600,
        startTime: stayingOn.startTime,
        endTime: stayingOn.endTime.add(const Duration(minutes: 10)),
        transfers: stayingOn.transfers,
        legs: [
          for (final leg in stayingOn.legs)
            if (leg.tripId == ice1009.tripId) short else leg,
        ],
      );

      expect(later, isNotNull);
      expect(JourneyGraphService.mergeOnward([changing], [stayingOn]), [
        stayingOn,
        changing,
      ]);
    });
  });
}
