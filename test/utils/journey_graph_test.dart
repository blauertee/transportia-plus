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

    test(
      'puts results leaving together next to those they share rides with',
      () {
        // EST 9036 first; then two on EST 9040, one of which takes the same
        // TGV on as the first. That one goes next to it.
        final graph = JourneyGraph.build(_load('plan_same_departure'));
        final tgv = graph.rides.singleWhere(
          (ride) => ride.leg.displayName == 'TGV INOUI 2465',
        );
        final est9040 = graph.rides.singleWhere(
          (ride) => ride.leg.displayName == 'EST 9040',
        );

        expect(tgv.itineraries, [0, 1]);
        expect(est9040.itineraries, [1, 2]);
      },
    );
  });

  group('JourneyGraph.build, results that share rides apart', () {
    // Köln → Amsterdam: four results by coach over Rotterdam, all on the
    // same coach. The first and last take the Intercity on to Amsterdam
    // Centraal; the two between change at Leiden.
    final graph = JourneyGraph.build(_load('plan_split_ride'));
    Iterable<GraphRide> rides(String to) => graph.rides.where(
      (ride) => ride.leg.mode == 'REGIONAL_RAIL' && ride.leg.to.name == to,
    );

    test('draws a ride once across the results side by side on it', () {
      expect(rides('Leiden Centraal').single.itineraries, [1, 2]);
    });

    test('draws a ride again for results with others between them', () {
      final intercity = rides('Amsterdam Centraal').toList();

      expect(
        [for (final ride in intercity) ride.itineraries],
        [
          [0],
          [3],
        ],
      );
      // Still one ride, to lock.
      expect(intercity.map((ride) => ride.key).toSet(), hasLength(1));
    });

    test('changes onto each of its bars from its own results', () {
      final [first, last] = rides('Amsterdam Centraal').toList();
      final onto = graph.changes.where(
        (change) => change.to == first || change.to == last,
      );

      expect(onto.map((change) => change.to), [first, last]);
      expect(onto.map((change) => change.from).toSet(), hasLength(1));
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
        expect(height, greaterThanOrEqualTo(20 - 1e-9));
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

    test('makes a ride as tall as its name needs', () {
      final ride = graph.rides.firstWhere(
        (ride) => ride.leg.displayName == 'S46',
      );
      final scale = GraphScale(
        graph,
        0.3,
        badges: RideBadges(heights: {ride.key: 48}),
      );
      final height =
          scale.yOf(ride.leg.endTime) - scale.yOf(ride.leg.startTime);

      expect(height, greaterThanOrEqualTo(48 - 1e-9));
    });

    test('makes room for a badge under a long name', () {
      final ride = graph.rides.firstWhere(
        (ride) => ride.leg.displayName == 'S46',
      );
      final scale = GraphScale(
        graph,
        0.3,
        badges: RideBadges(
          keys: {ride.key},
          rideHeight: 28,
          overhang: 9,
          heights: {ride.key: 48},
        ),
      );
      final height =
          scale.yOf(ride.leg.endTime) - scale.yOf(ride.leg.startTime);

      // The badge needs 8 more than the shortest bar's 20.
      expect(height, greaterThanOrEqualTo(48 + 8 - 1e-9));
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

  group('packColumns', () {
    final graph = JourneyGraph.build(results);
    GraphRide ride(String name, int column) => graph.rides.firstWhere(
      (ride) =>
          ride.leg.displayName == name && ride.itineraries.contains(column),
    );
    GraphBox box(
      GraphRide ride,
      double top,
      double bottom, {
      double half = 15,
    }) => GraphBox(ride, left: half, right: half, top: top, bottom: bottom);
    const gaps = [0.0, 40.0, 40.0];

    test('puts columns with nothing side by side as close as allowed', () {
      final xs = packColumns(
        3,
        [box(ride('S46', 0), 0, 50), box(ride('S46', 1), 60, 90)],
        minGaps: gaps,
        margin: 8,
      );

      expect(xs, [0, 40, 80]);
    });

    test('keeps what is side by side at the same time apart', () {
      final xs = packColumns(
        3,
        [
          box(ride('S46', 0), 0, 50),
          // A wide name beside it in the next column.
          box(ride('RE2', 1), 20, 35, half: 40),
        ],
        minGaps: gaps,
        margin: 8,
      );

      expect(xs[1], 15 + 40 + 8);
      expect(xs[2], xs[1] + 40);
    });

    test('moves a shared ride with the last column that takes it', () {
      final ice1507 = ride('ICE 1507', 0);
      final xs = packColumns(
        3,
        [box(ice1507, 0, 200), box(ride('ICE 1009', 2), 100, 300, half: 50)],
        minGaps: gaps,
        margin: 8,
      );

      final centre = (xs[0] + xs[1]) / 2;
      expect(xs[2] - centre, 15 + 50 + 8);
    });

    test('keeps apart two rides ending in the same column', () {
      // The coach all four take, and a train only the last two take into
      // the stop it leaves from: its name there is beside the coach's.
      final split = JourneyGraph.build(_load('plan_split_ride'));
      final coach = split.rides.firstWhere((ride) => ride.leg.mode == 'COACH');
      final train = split.rides.firstWhere(
        (ride) => ride.itineraries.length == 2 && ride.firstColumn == 2,
      );
      final xs = packColumns(
        4,
        [box(coach, 100, 300), box(train, 50, 110, half: 60)],
        minGaps: const [0, 40, 40, 40],
        margin: 8,
      );

      double centre(GraphRide ride) =>
          (xs[ride.firstColumn] + xs[ride.lastColumn]) / 2;
      expect(centre(train) - centre(coach), 15 + 60 + 8);
    });

    test('keeps every pair of bars clear in the real results', () {
      final scale = GraphScale(graph, 1);
      final bars = [
        for (final ride in graph.rides)
          box(ride, scale.yOf(ride.leg.startTime), scale.yOf(ride.leg.endTime)),
      ];
      final xs = packColumns(
        graph.columnCount,
        bars,
        minGaps: List.filled(graph.columnCount, 0),
        margin: 8,
      );

      double centre(GraphRide ride) =>
          (xs[ride.firstColumn] + xs[ride.lastColumn]) / 2;
      for (final a in bars) {
        for (final b in bars) {
          if (a.ride.slot >= b.ride.slot || !a.overlapsInTime(b)) continue;
          expect(centre(b.ride) - centre(a.ride), greaterThanOrEqualTo(38));
        }
      }
    });
  });
}
