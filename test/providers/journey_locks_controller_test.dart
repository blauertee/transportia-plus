import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/models/itinerary.dart';
import 'package:transportia/models/itinerary_response.dart';
import 'package:transportia/models/time_selection.dart';
import 'package:transportia/providers/journey_locks_controller.dart';
import 'package:transportia/services/journey_graph_service.dart';
import 'package:transportia/utils/journey_graph.dart';

List<Itinerary> _load(String name) => ItineraryResponse.fromJson(
  jsonDecode(File('test/fixtures/transitous/$name.json').readAsStringSync())
      as Map<String, dynamic>,
).itineraries;

final _query = JourneyQuery(
  fromLat: 52.29,
  fromLon: 13.63,
  toLat: 47.54,
  toLon: 9.68,
  time: TimeSelection(
    dateTime: DateTime.utc(2026, 10, 27, 9, 40),
    isArriveBy: false,
  ),
);

GraphStation _station(String name) =>
    GraphStation(id: 'feed_$name', name: name);

void main() {
  final results = _load('plan_journey_graph');
  final onward = _load('plan_journey_graph_onward');
  final viaIngolstadt = results.firstWhere(
    (it) => it.legs.any((leg) => leg.displayName == 'ICE 1009'),
  );
  final ice1009 = viaIngolstadt.legs.firstWhere(
    (leg) => leg.displayName == 'ICE 1009',
  );

  late List<JourneyGraphSearch> searches;
  late JourneyLocksController controller;

  setUp(() {
    searches = [];
    controller = JourneyLocksController(
      query: () => _query,
      search: (search) async {
        searches.add(search);
        final lock = search.lock;
        if (lock == null) return JourneyGraphPage(results);
        return JourneyGraphPage(
          continueAfter(lock.itinerary, lock.upTo, onward),
        );
      },
    );
  });

  tearDown(() => controller.dispose());

  test('starts with nothing locked and nothing searched', () {
    expect(controller.isLocked, isFalse);
    expect(controller.results, isNull);
    expect(searches, isEmpty);
  });

  test('sends locked stations as via stops', () async {
    controller.toggleStation(_station('Ulm'));
    await pumpEventQueue();

    expect(searches.single.via.single.name, 'Ulm');
    expect(controller.results, results);
  });

  test('refuses a station past what the planner takes', () async {
    controller.toggleStation(_station('Ulm'));
    controller.toggleStation(_station('Augsburg'));
    await pumpEventQueue();
    searches.clear();

    controller.toggleStation(_station('Kempten'));
    await pumpEventQueue();

    expect(searches, isEmpty);
    expect(controller.stations.map((s) => s.name), ['Ulm', 'Augsburg']);
    expect(controller.problem, contains('At most 2'));
  });

  test('does not send a station the fixed part already passes', () async {
    controller.lockRide(viaIngolstadt, ice1009);
    controller.toggleStation(GraphStation.of(ice1009, arriving: true));
    await pumpEventQueue();

    expect(searches.last.lock?.key, GraphRide.keyOf(ice1009));
    expect(searches.last.via, isEmpty);
  });

  test('a ride lock shows what goes on from where it gets off', () async {
    controller.lockRide(viaIngolstadt, ice1009);
    await pumpEventQueue();

    expect(controller.results, hasLength(onward.length));
    expect(
      controller.results!.first.legs.map((leg) => leg.displayName),
      contains('ICE 1009'),
    );
  });

  test('clearing drops every lock without searching', () async {
    controller.lockRide(viaIngolstadt, ice1009);
    controller.toggleStation(_station('Ulm'));
    await pumpEventQueue();
    searches.clear();

    controller.clear();
    await pumpEventQueue();

    expect(controller.isLocked, isFalse);
    expect(controller.lock, isNull);
    expect(controller.stations, isEmpty);
    expect(controller.results, isNull);
    expect(searches, isEmpty);
  });

  test('opens on a fixed journey and searches on from it at once', () async {
    final opened = JourneyLocksController(
      query: () => _query,
      initialLock: RideLock(viaIngolstadt, ice1009),
      search: (search) async {
        searches.add(search);
        return JourneyGraphPage(continueAfter(viaIngolstadt, ice1009, onward));
      },
    );
    addTearDown(opened.dispose);

    expect(opened.results, [viaIngolstadt]);
    expect(opened.searching, isTrue);
    await pumpEventQueue();

    expect(opened.searching, isFalse);
    expect(opened.results, hasLength(onward.length));
  });

  group('pages', () {
    late List<JourneyGraphSearch> asked;
    JourneyLocksController paged() {
      asked = [];
      final controller = JourneyLocksController(
        query: () => _query,
        search: (search) async {
          asked.add(search);
          return switch (search.pageCursor) {
            null => JourneyGraphPage(
              [results[1]],
              earlier: search.lock == null ? 'before' : null,
              later: 'after',
            ),
            'before' => JourneyGraphPage([results[0]], earlier: 'before-2'),
            _ => JourneyGraphPage([results[2]]),
          };
        },
      );
      addTearDown(controller.dispose);
      return controller;
    }

    test('adds the page after, with the cursor the search gave', () async {
      final controller = paged()..toggleStation(_station('Ulm'));
      await pumpEventQueue();

      await controller.loadLater();

      expect(asked.last.pageCursor, 'after');
      expect(asked.last.via.single.name, 'Ulm');
      expect(controller.results, [results[1], results[2]]);
      expect(controller.hasLater, isFalse);
    });

    test('adds the page before in front', () async {
      final controller = paged()..toggleStation(_station('Ulm'));
      await pumpEventQueue();

      await controller.loadEarlier();

      expect(controller.results, [results[0], results[1]]);
      expect(controller.hasEarlier, isTrue);
    });

    test('has nothing earlier on from a locked ride', () async {
      final controller = paged()..lockRide(viaIngolstadt, ice1009);
      await pumpEventQueue();

      expect(controller.hasEarlier, isFalse);
      expect(controller.hasLater, isTrue);
    });

    test('drops a page that lands after the locks changed', () async {
      final controller = paged()..toggleStation(_station('Ulm'));
      await pumpEventQueue();

      final page = controller.loadLater();
      controller.toggleStation(_station('Ulm'));
      await page;
      await pumpEventQueue();

      expect(controller.isLocked, isFalse);
      expect(controller.results, isNull);
    });
  });
}
