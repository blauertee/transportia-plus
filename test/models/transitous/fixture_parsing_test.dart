import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/models/itinerary.dart';
import 'package:transportia/models/stop_time.dart';
import 'package:transportia/models/transitous/match.dart';
import 'package:transportia/models/transitous/reachability.dart';
import 'package:transportia/models/transitous/rentals_response.dart';
import 'package:transportia/models/transitous/route_info.dart';
import 'package:transportia/models/transitous/server_config.dart';
import 'package:transportia/services/transitous_geocode_service.dart';

/// Parses the real captures in `test/fixtures/transitous/`.
///
/// Hand-written JSON tends to agree with whatever the parser already assumes;
/// these are what the server actually sends, exponential numbers and absent
/// optional fields included.
dynamic _fixture(String name) =>
    json.decode(File('test/fixtures/transitous/$name').readAsStringSync());

void main() {
  group('plan.json', () {
    late Map<String, dynamic> plan;

    setUpAll(() => plan = _fixture('plan.json') as Map<String, dynamic>);

    test('parses every itinerary', () {
      final itineraries = (plan['itineraries'] as List)
          .map((i) => Itinerary.fromJson(i as Map<String, dynamic>))
          .toList();

      expect(itineraries, isNotEmpty);
      for (final itinerary in itineraries) {
        expect(itinerary.legs, isNotEmpty);
        expect(itinerary.endTime.isAfter(itinerary.startTime), isTrue);
      }
    });

    test('carries the itinerary id needed to refresh it', () {
      final itinerary = Itinerary.fromJson(
        (plan['itineraries'] as List).first as Map<String, dynamic>,
      );
      // This is the handle /refresh-itinerary takes, and the reason that call
      // has to be a POST.
      expect(itinerary.id, isNotNull);
      expect(itinerary.id!.length, greaterThan(100));
    });

    test('reads leg endpoints as full places', () {
      final itinerary = Itinerary.fromJson(
        (plan['itineraries'] as List).first as Map<String, dynamic>,
      );
      final leg = itinerary.legs.first;

      expect(leg.from.name, isNotEmpty);
      expect(leg.from.lat, isNot(0.0));
      expect(leg.fromName, leg.from.name);
      expect(leg.fromLat, leg.from.lat);
    });

    test('reads the transit leg details the app previously dropped', () {
      final itinerary = (plan['itineraries'] as List)
          .map((i) => Itinerary.fromJson(i as Map<String, dynamic>))
          .firstWhere((i) => i.legs.any((l) => l.tripId != null));
      final transit = itinerary.legs.firstWhere((l) => l.tripId != null);

      expect(transit.routeId, isNotNull);
      expect(transit.source, isNotNull);
      expect(transit.tripFrom, isNotNull);
      expect(transit.tripTo, isNotNull);
      expect(transit.transitMode, isNotNull);
    });

    test('reads walking steps when detailed legs are requested', () {
      final legs = (plan['itineraries'] as List)
          .expand((i) => Itinerary.fromJson(i as Map<String, dynamic>).legs)
          .toList();
      final withSteps = legs.where((l) => l.steps.isNotEmpty);

      expect(withSteps, isNotEmpty, reason: 'detailedLegs=true was requested');
      final step = withSteps.first.steps.first;
      expect(step.distance, greaterThanOrEqualTo(0));
      expect(step.polyline, isNotNull);
    });

    test('reads leg alternatives as journeys of their own', () {
      // Captured with numLegAlternatives=2: each ride carries up to two
      // stand-ins, each a footpath, a ride and a footpath. The ride may be
      // another line or mode altogether — an S-Bahn's stand-in can be a
      // U-Bahn.
      final rides = (plan['itineraries'] as List)
          .expand((i) => Itinerary.fromJson(i as Map<String, dynamic>).legs)
          .where((l) => l.alternatives.isNotEmpty)
          .toList();

      expect(rides, hasLength(4));
      for (final ride in rides) {
        expect(ride.alternatives, hasLength(2));
        for (final alternative in ride.alternatives) {
          expect(alternative.map((l) => l.isStreet), [true, false, true]);
          expect(alternative[1].tripId, isNotEmpty);
        }
      }
    });

    test('keeps the raw payload so an itinerary stays saveable', () {
      final itinerary = Itinerary.fromJson(
        (plan['itineraries'] as List).first as Map<String, dynamic>,
      );
      expect(itinerary.sourceJson, isNotNull);
      expect(
        Itinerary.fromJson(itinerary.sourceJson!).startTime,
        itinerary.startTime,
      );
    });
  });

  group('trip.json', () {
    test('parses as an itinerary', () {
      final trip = Itinerary.fromJson(_fixture('trip.json'));
      expect(trip.legs, isNotEmpty);
      expect(trip.legs.first.intermediateStops, isNotEmpty);
    });
  });

  group('stoptimes.json', () {
    test('parses the response and its places', () {
      final response = StopTimesResponse.fromJson(
        _fixture('stoptimes.json') as Map<String, dynamic>,
      );

      expect(response.stopTimes, isNotEmpty);
      final stopTime = response.stopTimes.first;
      expect(stopTime.place.name, isNotEmpty);
      expect(stopTime.tripId, isNotEmpty);
      expect(response.nextPageCursor, isNotNull);
    });

    test('names what serves the stop the board is for', () {
      // How a recent picked from the list, which never asks the geocoder
      // again, learns its icon.
      final response = StopTimesResponse.fromJson(
        _fixture('stoptimes.json') as Map<String, dynamic>,
      );

      expect(response.place?.modes, contains(TransitMode.subway));
    });
  });

  group('stop.json', () {
    test('parses as a place', () {
      final json = _fixture('stop.json') as Map<String, dynamic>;
      final place = TransitPlace.fromJson(
        json['place'] as Map<String, dynamic>,
      );

      expect(place.name, isNotEmpty);
      expect(place.isStop, isTrue);
      // /stop is the endpoint that reports which modes serve a stop.
      expect(place.modes, isNotEmpty);
      expect(place.modes, everyElement(isA<TransitMode>()));
    });
  });

  group('geocode.json', () {
    test('parses matches with their areas and tokens', () {
      final matches = (_fixture('geocode.json') as List)
          .map((m) => Match.fromJson(m as Map<String, dynamic>))
          .toList();

      expect(matches, isNotEmpty);
      final match = matches.first;
      expect(match.name, isNotEmpty);
      expect(match.id, isNotEmpty);
      expect(match.type, isNotNull);
      expect(match.areas, isNotEmpty);
      expect(match.tokens, isNotEmpty);
      // The distinguishing area is what a suggestion row should show.
      expect(match.displayArea, isNotNull);
    });

    test('a shop sits in a district of its city', () {
      final rewe = Match.fromJson(
        (_fixture('geocode_rewe.json') as List).first as Map<String, dynamic>,
      );

      expect(rewe.isSettlement, isFalse);
      expect(rewe.cityArea?.name, 'Berlin');
      // Prenzlauer Berg (10) over Pankow (9): the finest district.
      expect(rewe.districtArea?.name, 'Prenzlauer Berg');
      expect(rewe.regionArea?.name, 'Berlin');
    });

    test('a city is not placed in a district of itself', () {
      final paris = (_fixture('geocode_paris.json') as List)
          .map((m) => Match.fromJson(m as Map<String, dynamic>))
          .toList();

      final city = paris.first;
      expect(city.country, 'FR');
      expect(city.isSettlement, isTrue);
      expect(city.districtArea, isNull);
      expect(city.regionArea?.name, 'Île-de-France');
      // A Paris in Texas is told apart by its state.
      final texas = paris.firstWhere((m) => m.regionArea?.name == 'Texas');
      expect(texas.country, 'US');
      expect(texas.districtArea, isNull);
    });

    test('with no default area there is no city and no district', () {
      const match = Match(
        type: LocationType.place,
        name: 'Somewhere',
        id: '',
        lat: 0,
        lon: 0,
        score: 0,
        areas: [Area(name: 'Mitte', adminLevel: 9)],
      );

      expect(match.cityArea, isNull);
      expect(match.districtArea, isNull);
      expect(match.regionArea, isNull);
    });

    test('a stop suggestion carries what serves it', () {
      // What the recents draw a station by.
      final suggestions = [
        for (final m in _fixture('geocode.json') as List)
          TransitousLocationSuggestion.fromMatch(
            Match.fromJson(m as Map<String, dynamic>),
          ),
      ];

      final alex = suggestions.firstWhere(
        (s) => s.stopId == 'de-DELFI_de:11000:900100003',
      );
      expect(alex.modes, [
        TransitMode.regionalRail,
        TransitMode.suburban,
        TransitMode.subway,
        TransitMode.bus,
      ]);
      // A place is served by nothing.
      expect(suggestions.firstWhere((s) => s.type == 'PLACE').modes, isEmpty);
    });

    test('reverse geocode results parse the same way', () {
      final matches = (_fixture('reverse_geocode.json') as List)
          .map((m) => Match.fromJson(m as Map<String, dynamic>))
          .toList();
      expect(matches, isNotEmpty);
      expect(matches.first.lat, isNot(0.0));
    });
  });

  group('map_initial.json', () {
    test('parses the server capabilities that bound the routing options', () {
      final view = InitialMapView.fromJson(
        _fixture('map_initial.json') as Map<String, dynamic>,
      );
      final config = view.serverConfig;

      expect(config.motisVersion, isNotEmpty);
      expect(config.hasStreetRouting, isTrue);
      expect(config.maxPrePostTransitTime, const Duration(seconds: 7200));
      expect(config.maxDirectTime, const Duration(seconds: 21600));
      expect(config.maxOneToManySize, greaterThan(0));
    });
  });

  group('health.json', () {
    test('parses the feed status', () {
      final health = HealthStatus.fromJson(
        _fixture('health.json') as Map<String, dynamic>,
      );
      expect(health.realtime, isTrue);
      expect(health.gbfs, isTrue);
    });
  });

  group('one_to_all.json', () {
    test('parses reachable places', () {
      final reachable = Reachable.fromJson(
        _fixture('one_to_all.json') as Map<String, dynamic>,
      );

      expect(reachable.all, isNotEmpty);
      final first = reachable.all.first;
      expect(first.place.name, isNotEmpty);
      expect(first.duration, greaterThan(Duration.zero));
      expect(first.transfers, greaterThanOrEqualTo(0));
    });
  });

  group('one_to_many.json', () {
    test('parses durations and distances positionally', () {
      final durations = StreetDuration.listFromJson(
        _fixture('one_to_many.json'),
      );

      // The array is aligned with the requested coordinates, so length has to
      // be preserved even for unreachable destinations.
      expect(durations, hasLength(2));
      expect(durations.first.isReachable, isTrue);
      expect(durations.first.distance, isNotNull);
    });

    test('parses the intermodal variant', () {
      final result = OneToManyIntermodal.fromJson(
        _fixture('one_to_many_intermodal.json') as Map<String, dynamic>,
      );
      expect(result.streetDurations, isNotEmpty);
      expect(result.transitDurations, isNotEmpty);
      expect(result.transitDurations.first.first.transfers, 0);
    });
  });

  group('rentals.json', () {
    test('parses providers, stations, vehicles and zones', () {
      final rentals = RentalsResponse.fromJson(
        _fixture('rentals.json') as Map<String, dynamic>,
      );

      expect(rentals.providerGroups, isNotEmpty);
      expect(rentals.providers, isNotEmpty);
      expect(rentals.stations, isNotEmpty);
      expect(rentals.vehicles, isNotEmpty);
      expect(rentals.zones, isNotEmpty);

      expect(rentals.providers.first.bbox, isNotNull);
      expect(rentals.providers.first.vehicleTypes, isNotEmpty);
      expect(rentals.stations.first.formFactors, isNotEmpty);
      expect(rentals.zones.first.area, isNotEmpty);
      expect(rentals.zones.first.rules, isNotEmpty);
    });
  });

  group('map_routes.json', () {
    test('parses routes and their shared polylines', () {
      final response = MapRoutesResponse.fromJson(
        _fixture('map_routes.json') as Map<String, dynamic>,
      );

      expect(response.routes, isNotEmpty);
      expect(response.polylines, isNotEmpty);
      expect(response.stops, isNotEmpty);

      final route = response.routes.first;
      expect(route.mode, isNotNull);
      expect(route.transitRoutes, isNotEmpty);
      expect(route.pathSource, isNotNull);
      expect(response.polylines.first.routeIndexes, isNotEmpty);
    });
  });

  group('debug_transfers.json', () {
    test('parses per-profile transfer times', () {
      final response = TransfersDebugResponse.fromJson(
        _fixture('debug_transfers.json') as Map<String, dynamic>,
      );

      expect(response.place.name, isNotEmpty);
      expect(response.transfers, isNotEmpty);

      final withFoot = response.transfers.firstWhere((t) => t.foot != null);
      // Reported in minutes, unlike the seconds used almost everywhere else.
      expect(withFoot.foot, greaterThan(Duration.zero));
      expect(withFoot.foot!.inMinutes, lessThan(60));
    });
  });

  group('numbers', () {
    test('exponential integers survive parsing', () {
      // MOTIS writes every number in exponential form, so `duration` arrives
      // as 8.46E3 rather than 8460 and a plain `as int` cast would throw.
      final raw = json.encode({
        'duration': 8.46e3,
        'startTime': '2026-08-08T09:20:00Z',
        'endTime': '2026-08-08T11:41:00Z',
        'transfers': 2.0,
        'id': 'abc',
        'legs': <Object>[],
      });
      final itinerary = Itinerary.fromJson(
        json.decode(raw) as Map<String, dynamic>,
      );

      expect(itinerary.duration, 8460);
      expect(itinerary.transfers, 2);
    });
  });
}
