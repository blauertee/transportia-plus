import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/models/itinerary.dart';
import 'package:transportia/models/itinerary_response.dart';
import 'package:transportia/utils/journey_graph.dart';

List<Itinerary> _load(String name) => ItineraryResponse.fromJson(
  jsonDecode(File('test/fixtures/transitous/$name.json').readAsStringSync())
      as Map<String, dynamic>,
).itineraries;

void main() {
  // Wildau → Lindau Insel: two results that both take ICE 1507 to München,
  // one over ICE 1009 to Ingolstadt; and the search on from Ingolstadt.
  final results = _load('plan_journey_graph');
  final onward = _load('plan_journey_graph_onward');
  final viaIngolstadt = results.firstWhere(
    (it) => it.legs.any((leg) => leg.displayName == 'ICE 1009'),
  );
  final ice1009 = viaIngolstadt.legs.firstWhere(
    (leg) => leg.displayName == 'ICE 1009',
  );

  group('JourneyGraph.build', () {
    test('draws a ride two results share once, between their columns', () {
      final graph = JourneyGraph.build(results);
      final ice1507 = graph.rides.where(
        (ride) => ride.leg.displayName == 'ICE 1507',
      );

      expect(ice1507, hasLength(1));
      expect(ice1507.single.itineraries, hasLength(2));
      expect(ice1507.single.slot, 0.5);
    });

    test('orders the results by departure', () {
      final graph = JourneyGraph.build(results.reversed.toList());
      final starts = graph.itineraries.map((it) => it.startTime).toList();

      expect(starts, [...starts]..sort());
    });
  });

  group('continueAfter', () {
    final joined = continueAfter(viaIngolstadt, ice1009, onward);

    test('keeps the journey up to the ride, then each onward result', () {
      expect(joined, hasLength(onward.length));
      for (var i = 0; i < joined.length; i++) {
        final legs = joined[i].legs;
        final cut = legs.indexWhere((leg) => leg.displayName == 'ICE 1009');
        expect(legs.sublist(0, cut + 1), [
          for (final leg in viaIngolstadt.legs.take(cut + 1)) leg,
        ]);
        expect(legs.sublist(cut + 1), onward[i].legs);
        expect(joined[i].startTime, viaIngolstadt.startTime);
        expect(joined[i].endTime, onward[i].endTime);
      }
    });

    test('carries no server id and no fare from either half', () {
      for (final itinerary in joined) {
        expect(itinerary.id, isNull);
        expect(itinerary.fare, isNull);
        expect(itinerary.ticketInfo, isEmpty);
      }
    });

    test('counts the changes of the whole journey', () {
      for (final itinerary in joined) {
        final rides = itinerary.legs.where((leg) => !leg.isStreet).length;
        expect(itinerary.transfers, rides - 1);
      }
    });

    test('has a snapshot that parses back into the same journey', () {
      for (final itinerary in joined) {
        final snapshot = Itinerary.fromJson(itinerary.sourceJson!);
        expect(snapshot.legs, hasLength(itinerary.legs.length));
        expect(snapshot.startTime, itinerary.startTime);
        expect(snapshot.endTime, itinerary.endTime);
        expect(snapshot.transfers, itinerary.transfers);
      }
    });

    test('joins nothing to a journey that does not take the ride', () {
      final other = results.firstWhere((it) => it != viaIngolstadt);

      expect(continueAfter(other, ice1009, onward), isEmpty);
    });
  });

  group('RideLock', () {
    final lock = RideLock(viaIngolstadt, ice1009);

    test('passes the stations up to where the ride gets off', () {
      final ingolstadt = GraphStation.of(ice1009, arriving: true);
      final boarding = GraphStation.of(ice1009, arriving: false);

      expect(lock.passes(ingolstadt.key), isTrue);
      expect(lock.passes(boarding.key), isTrue);
    });

    test('does not pass stations after it', () {
      final later = viaIngolstadt.legs.lastWhere((leg) => leg.isRide);

      expect(lock.passes(GraphStation.of(later, arriving: true).key), isFalse);
    });
  });

  group('GraphScale', () {
    final graph = JourneyGraph.build(results);

    test('is linear where every ride has room for its name', () {
      final scale = GraphScale(graph, 10);

      expect(scale.stretchedSpans, isEmpty);
      final minutes = graph.end.difference(graph.start).inMinutes;
      expect(scale.height, closeTo(minutes * 10, 1));
    });

    test('stretches short stretches when zoomed out', () {
      final scale = GraphScale(graph, 0.3);

      expect(scale.stretchedSpans, isNotEmpty);
      for (final ride in graph.rides) {
        final height =
            scale.yOf(ride.leg.endTime) - scale.yOf(ride.leg.startTime);
        expect(height, greaterThanOrEqualTo(18 - 1e-9));
      }
    });

    test('makes room for a badge under a ride', () {
      final ride = graph.rides.firstWhere(
        (ride) => ride.leg.displayName == 'S46',
      );
      final badges = RideBadges(keys: {ride.key}, rideHeight: 28, overhang: 9);
      final scale = GraphScale(graph, 0.3, badges: badges);
      final height =
          scale.yOf(ride.leg.endTime) - scale.yOf(ride.leg.startTime);

      expect(height, greaterThanOrEqualTo(28 - 1e-9));
    });

    test('takes a change that cannot be made, boarding before arriving', () {
      // ICE 1009 into Ingolstadt 25 minutes late: the next train leaves
      // before it gets in.
      final json =
          jsonDecode(jsonEncode(viaIngolstadt.sourceJson))
              as Map<String, dynamic>;
      final ice = (json['legs'] as List).firstWhere(
        (leg) => leg['displayName'] == 'ICE 1009',
      );
      ice['endTime'] = DateTime.parse(
        ice['endTime'] as String,
      ).add(const Duration(minutes: 25)).toUtc().toIso8601String();
      final late = JourneyGraph.build([Itinerary.fromJson(json)]);

      expect(() => GraphScale(late, 0.3), returnsNormally);
      expect(GraphScale(late, 0.3).height, greaterThan(0));
    });

    test('fits the first arrival into the height it is given', () {
      final zoom = graph.fitPxPerMinute(graph.firstArrival, 600);
      final scale = GraphScale(graph, zoom);

      expect(scale.yOf(graph.firstArrival), lessThanOrEqualTo(600));
      expect(scale.yOf(graph.firstArrival), greaterThan(590));
    });
  });
}
