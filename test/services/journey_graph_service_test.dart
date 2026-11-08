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
}
