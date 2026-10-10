import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/models/itinerary.dart';
import 'package:transportia/models/routing_options.dart';

import '../support/plan_fixtures.dart';

/// A real itinerary from `test/fixtures/transitous/`.
Itinerary _fixture(String name) => Itinerary.fromJson(
  jsonDecode(File('test/fixtures/transitous/$name').readAsStringSync())
      as Map<String, dynamic>,
);

/// Transitous's published limit for a first or last mile.
const Duration _transitousLimit = Duration(hours: 2);

/// What a refresh of [itinerary] would send, nulls stripped.
Map<String, String> _refresh(
  Itinerary? itinerary, {
  RoutingOptions options = RoutingOptions.defaults,
  Duration serverLimit = _transitousLimit,
}) {
  final params = options.toRefreshParams(
    itinerary: itinerary,
    serverLimit: serverLimit,
  );
  return {
    for (final entry in params.toQuery().entries)
      if (entry.value != null) entry.key: entry.value!,
  };
}

void main() {
  // The journey from #35: 24 minutes by bike to Messe Süd, the S3, then 22
  // minutes by bike from Bellevue.
  final bike = _fixture('refresh_itinerary_bike.json');

  // A Dott scooter to Strausberger Platz — walk to it, ride, walk on — then
  // the U5 and a walk.
  final rental = _fixture('plan_itinerary_rental.json');

  group('the first and last mile', () {
    test('are the street legs either side of the rides', () {
      expect(bike.firstMileLegs.map((l) => l.mode), ['BIKE']);
      expect(bike.lastMileLegs.map((l) => l.mode), ['BIKE']);
      expect(rental.firstMileLegs.map((l) => l.mode), [
        'WALK',
        'RENTAL',
        'WALK',
      ]);
      expect(rental.lastMileLegs.map((l) => l.mode), ['WALK']);
    });

    test('are empty for a journey from station to station', () {
      final stationToStation = Itinerary.fromJson(
        planItineraryJson(
          departure: DateTime.utc(2026, 10, 4, 16),
          withEdgeWalks: false,
        ),
      );
      expect(stationToStation.firstMileLegs, isEmpty);
      expect(stationToStation.lastMileLegs, isEmpty);
    });
  });

  group('a refresh finds the street legs it planned', () {
    test('within the longest of them, plus headroom', () {
      final sent = _refresh(bike);
      // 1440 s by bike to the station, the longer end, and five minutes.
      expect(sent['maxPreTransitTime'], '${1440 + 300}');
      expect(sent['maxPostTransitTime'], '${1440 + 300}');
    });

    test('whatever the rider has set since', () {
      // The defaults allow a 15-minute walk: too short for either bike leg,
      // which is how the refresh came back with both of them cancelled.
      expect(RoutingOptions.defaults.maxFirstMileTime.inSeconds, 900);
      expect(_refresh(bike)['maxPreTransitTime'], '1740');
    });

    test('counting a shared vehicle and the walks to and from it', () {
      // 120 s to the scooter, 660 s on it, 240 s to the platform.
      expect(_refresh(rental)['maxPreTransitTime'], '${1020 + 300}');
    });

    test('never past what the server allows', () {
      final sent = _refresh(bike, serverLimit: const Duration(minutes: 20));
      expect(sent['maxPreTransitTime'], '1200');
      expect(sent['maxPostTransitTime'], '1200');
    });

    test('exactly at what the server allows', () {
      final sent = _refresh(bike, serverLimit: const Duration(seconds: 1740));
      expect(sent['maxPreTransitTime'], '1740');
    });

    test('uncapped when the server does not say', () {
      final sent = _refresh(bike, serverLimit: Duration.zero);
      expect(sent['maxPreTransitTime'], '1740');
    });

    test('sends no limit when there is no street leg to find', () {
      final sent = _refresh(
        Itinerary.fromJson(
          planItineraryJson(
            departure: DateTime.utc(2026, 10, 4, 16),
            withEdgeWalks: false,
          ),
        ),
      );
      expect(sent.containsKey('maxPreTransitTime'), isFalse);
      expect(sent.containsKey('maxPostTransitTime'), isFalse);
    });
  });

  group('a shared vehicle', () {
    test('is looked for again of the same kind, from the same provider', () {
      final sent = _refresh(rental);
      expect(sent['preTransitRentalFormFactors'], 'SCOOTER_STANDING');
      expect(sent['preTransitRentalProviders'], 'de-DottBerlin');
    });

    test('pins only the end that rents', () {
      final sent = _refresh(rental);
      expect(sent.containsKey('postTransitRentalProviders'), isFalse);
      expect(sent.containsKey('postTransitRentalFormFactors'), isFalse);
    });

    test('over whatever the rider rents by default', () {
      final options = RoutingOptions.defaults.copyWith(
        firstMileModes: const [TransitMode.rental],
        firstMileRentalFormFactors: const [RentalFormFactor.bicycle],
      );
      final sent = _refresh(rental, options: options);
      expect(sent['preTransitRentalFormFactors'], 'SCOOTER_STANDING');
    });
  });

  group('geometry', () {
    test('is not fetched again for legs that cannot have moved', () {
      final sent = _refresh(bike);
      expect(sent['detailedLegs'], 'false');
      expect(sent['detailedTransfers'], 'false');
    });

    test('is fetched when a shared vehicle may stand somewhere else', () {
      final sent = _refresh(rental);
      expect(sent['detailedLegs'], 'true');
      expect(sent['detailedTransfers'], 'false');
    });
  });

  group('a shared link, known only by its id', () {
    test('is found within everything the server allows', () {
      final sent = _refresh(null);
      expect(sent['maxPreTransitTime'], '${_transitousLimit.inSeconds}');
      expect(sent['maxPostTransitTime'], '${_transitousLimit.inSeconds}');
    });

    test('fetches every shape, since none is stored', () {
      final sent = _refresh(null);
      expect(sent['detailedLegs'], 'true');
      expect(sent['detailedTransfers'], 'true');
    });
  });

  group('what the alternatives search reads', () {
    // The endpoint can also return per-leg alternatives; these settings shape
    // that search, so they stay the rider's.
    test('stays the rider\'s', () {
      final options = RoutingOptions.defaults.copyWith(
        firstMileModes: const [TransitMode.bike],
        lastMileModes: const [TransitMode.bike],
        noCompulsoryReservation: true,
        transitModes: const [TransitMode.suburban, TransitMode.subway],
      );
      final sent = _refresh(bike, options: options);
      expect(sent['preTransitModes'], 'BIKE');
      expect(sent['postTransitModes'], 'BIKE');
      expect(sent['requireBikeTransport'], 'true');
      expect(sent['noCompulsoryReservation'], 'true');
      expect(sent['transitModes'], 'SUBURBAN,SUBWAY');
    });
  });
}
