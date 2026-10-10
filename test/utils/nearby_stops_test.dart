import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:transportia/models/stop_time.dart';
import 'package:transportia/models/transitous/place.dart';
import 'package:transportia/services/transitous_map_service.dart';
import 'package:transportia/utils/geo_utils.dart';
import 'package:transportia/utils/nearby_stops.dart';

/// The real capture of `/map/stops` over central Berlin.
List<MapStop> _berlinStops() => [
  for (final json
      in jsonDecode(
            File('test/fixtures/transitous/map_stops.json').readAsStringSync(),
          )
          as List)
    MapStop.fromPlace(TransitPlace.fromJson(json as Map<String, dynamic>)),
];

List<StopTime> _departures() => StopTimesResponse.fromJson(
  jsonDecode(File('test/fixtures/transitous/stoptimes.json').readAsStringSync())
      as Map<String, dynamic>,
).stopTimes;

const LatLng _neumannsgasse = LatLng(52.5155, 13.4039);

void main() {
  group('nearbyStopsBounds', () {
    test('surrounds the centre by the search radius', () {
      final bounds = nearbyStopsBounds(_neumannsgasse);

      final north = coordinateDistanceInMeters(
        _neumannsgasse.latitude,
        _neumannsgasse.longitude,
        bounds.northeast.latitude,
        _neumannsgasse.longitude,
      );
      final east = coordinateDistanceInMeters(
        _neumannsgasse.latitude,
        _neumannsgasse.longitude,
        _neumannsgasse.latitude,
        bounds.northeast.longitude,
      );
      expect(north, closeTo(kNearbyStopsRadiusMetres, 5));
      // A degree of longitude is shorter here than at the equator, and the
      // box makes up for it: it is as wide in metres as it is tall.
      expect(east, closeTo(kNearbyStopsRadiusMetres, 5));
    });

    test('stays finite at the pole', () {
      final bounds = nearbyStopsBounds(const LatLng(90, 0));

      expect(bounds.northeast.longitude.isFinite, isTrue);
    });
  });

  group('nearestStops', () {
    test('lists the closest first and stops at the limit', () {
      final result = nearestStops(_berlinStops(), _neumannsgasse, limit: 3);

      expect(result, hasLength(3));
      final distances = [
        for (final stop in result)
          coordinateDistanceInMeters(
            _neumannsgasse.latitude,
            _neumannsgasse.longitude,
            stop.lat,
            stop.lon,
          ),
      ];
      expect(distances, [...distances]..sort());
    });

    test('is empty with nothing to choose from', () {
      expect(nearestStops(const [], _neumannsgasse), isEmpty);
    });

    test('leaves out a stop with no id, however near', () {
      const unnamed = MapStop(
        id: 'stop-here',
        name: 'Here',
        lat: 52.5155,
        lon: 13.4039,
      );

      final result = nearestStops([unnamed, ..._berlinStops()], _neumannsgasse);

      expect(result.map((s) => s.id), isNot(contains('stop-here')));
      expect(result, isNotEmpty);
    });
  });

  group('departuresSignature', () {
    test('is the same for the same departures at a stop of the same name', () {
      expect(
        departuresSignature(' Neumannsgasse ', _departures()),
        departuresSignature('neumannsgasse', _departures()),
      );
    });

    test('differs by name', () {
      expect(
        departuresSignature('Neumannsgasse', _departures()),
        isNot(departuresSignature('Marienkirche', _departures())),
      );
    });

    test('differs by what leaves', () {
      expect(
        departuresSignature('Neumannsgasse', _departures()),
        isNot(
          departuresSignature('Neumannsgasse', _departures().skip(1).toList()),
        ),
      );
    });
  });

  group('departureKey', () {
    test('prefers the real-time departure', () {
      final first = _departures().first;

      expect(departureKey(first), DateTime.utc(2026, 8, 8, 9, 38));
    });
  });

  group('lineNames', () {
    test('names each line once, soonest first', () {
      final names = lineNames(_departures());
      expect(names.toSet().length, names.length);
      expect(names.first, _departures().first.displayName);
    });

    test('is empty without departures', () {
      expect(lineNames(const []), isEmpty);
    });
  });
}
