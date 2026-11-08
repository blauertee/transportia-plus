import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/models/itinerary.dart';
import 'package:transportia/utils/itinerary_leg_utils.dart';

Leg _leg({
  required String mode,
  required String from,
  required String to,
  String? tripId,
  String? fromStopId,
  String? toStopId,
  double toLat = 52.4,
  double toLon = 13.5,
}) {
  final start = DateTime.parse('2026-08-05T07:00:00Z');
  return Leg(
    mode: mode,
    from: TransitPlace(name: from, lat: 52.5, lon: 13.4, stopId: fromStopId),
    to: TransitPlace(name: to, lat: toLat, lon: toLon, stopId: toStopId),
    startTime: start,
    endTime: start.add(const Duration(minutes: 10)),
    duration: 600,
    tripId: tripId,
  );
}

/// A walk whose ends are metres apart, which is what the planner returns for
/// stepping across a platform.
Leg _shortWalk({required String from, required String to}) =>
    _leg(mode: 'WALK', from: from, to: to, toLat: 52.50005, toLon: 13.40005);

/// The shape the planner actually returns for a journey between two
/// coordinates: placeholder edges wrapping the real stops.
List<Leg> _coordinateToCoordinate() => [
  _leg(
    mode: 'WALK',
    from: 'START',
    to: 'S+U Berlin Hauptbahnhof',
    toStopId: 'stop-hbf',
  ),
  _leg(
    mode: 'REGIONAL_RAIL',
    from: 'S+U Berlin Hauptbahnhof',
    to: 'Flughafen BER',
    tripId: 'trip-1',
    fromStopId: 'stop-hbf',
    toStopId: 'stop-ber',
  ),
  _leg(mode: 'WALK', from: 'Flughafen BER', to: 'END', fromStopId: 'stop-ber'),
];

void main() {
  group('isPlaceholderEndpointName', () {
    test('recognises the planner placeholders', () {
      expect(isPlaceholderEndpointName('START'), isTrue);
      expect(isPlaceholderEndpointName('END'), isTrue);
      expect(isPlaceholderEndpointName('start'), isTrue);
      expect(isPlaceholderEndpointName('  END  '), isTrue);
    });

    test('treats missing and blank names as placeholders', () {
      expect(isPlaceholderEndpointName(null), isTrue);
      expect(isPlaceholderEndpointName(''), isTrue);
      expect(isPlaceholderEndpointName('   '), isTrue);
    });

    test('leaves real names alone', () {
      expect(isPlaceholderEndpointName('Flughafen BER'), isFalse);
      expect(isPlaceholderEndpointName('Startbahn West'), isFalse);
      expect(isPlaceholderEndpointName('Ende'), isFalse);
    });
  });

  group('endpoint name resolution', () {
    test('looks past the placeholder edges to the real stops', () {
      final legs = _coordinateToCoordinate();

      expect(resolveOriginName(legs), 'S+U Berlin Hauptbahnhof');
      expect(resolveDestinationName(legs), 'Flughafen BER');
    });

    test('uses the endpoints directly when both are real stops', () {
      final legs = [
        _leg(
          mode: 'REGIONAL_RAIL',
          from: 'Ostkreuz',
          to: 'Flughafen BER',
          tripId: 'trip-1',
        ),
      ];

      expect(resolveOriginName(legs), 'Ostkreuz');
      expect(resolveDestinationName(legs), 'Flughafen BER');
    });

    test('spans transfers to reach the outermost real names', () {
      final legs = [
        _leg(mode: 'WALK', from: 'START', to: 'Alexanderplatz'),
        _leg(
          mode: 'METRO',
          from: 'Alexanderplatz',
          to: 'Hauptbahnhof',
          tripId: 'a',
        ),
        _leg(mode: 'WALK', from: 'Hauptbahnhof', to: 'Hauptbahnhof'),
        _leg(
          mode: 'REGIONAL_RAIL',
          from: 'Hauptbahnhof',
          to: 'Flughafen BER',
          tripId: 'b',
        ),
        _leg(mode: 'WALK', from: 'Flughafen BER', to: 'END'),
      ];

      expect(resolveOriginName(legs), 'Alexanderplatz');
      expect(resolveDestinationName(legs), 'Flughafen BER');
    });

    test('returns null when nothing in the journey is named', () {
      final legs = [_leg(mode: 'WALK', from: 'START', to: 'END')];

      expect(resolveOriginName(legs), isNull);
      expect(resolveDestinationName(legs), isNull);
    });

    test('finds the stop ids for those same endpoints', () {
      final legs = _coordinateToCoordinate();

      expect(resolveOriginStopId(legs), 'stop-hbf');
      expect(resolveDestinationStopId(legs), 'stop-ber');
    });

    test('returns null stop ids when the journey touches no stop', () {
      final legs = [_leg(mode: 'WALK', from: 'START', to: 'END')];

      expect(resolveOriginStopId(legs), isNull);
      expect(resolveDestinationStopId(legs), isNull);
    });

    test('returns null for an empty leg list', () {
      expect(resolveOriginName(const []), isNull);
      expect(resolveDestinationName(const []), isNull);
    });

    test('skips blank names as well as placeholders', () {
      final legs = [
        _leg(mode: 'WALK', from: 'START', to: '   '),
        _leg(mode: 'BUS', from: '', to: 'Rathaus', tripId: 'trip-1'),
        _leg(mode: 'WALK', from: 'Rathaus', to: ''),
      ];

      expect(resolveOriginName(legs), 'Rathaus');
      expect(resolveDestinationName(legs), 'Rathaus');
    });
  });

  group('buildDisplayLegs marks the changes', () {
    /// Walk → metro → walk between stations → train → walk.
    List<Leg> journey({required Leg middle}) => [
      _leg(mode: 'WALK', from: 'START', to: 'Alexanderplatz'),
      _leg(mode: 'METRO', from: 'Alexanderplatz', to: 'Hbf', tripId: 'a'),
      middle,
      _leg(mode: 'REGIONAL_RAIL', from: 'Hbf', to: 'BER', tripId: 'b'),
      _leg(mode: 'WALK', from: 'BER', to: 'END'),
    ];

    test('a long walk between two rides is a change', () {
      // It used to need to be under 35m, which told a rider nothing: getting
      // between two services is one act however far it is.
      final legs = journey(
        middle: _leg(mode: 'WALK', from: 'Hbf', to: 'Hbf (S)'),
      );

      expect(buildDisplayLegs(legs)[2].isTransfer, isTrue);
    });

    test('a step across a platform is still a change', () {
      final legs = journey(
        middle: _shortWalk(from: 'Hbf', to: 'Hbf'),
      );
      final display = buildDisplayLegs(legs);

      expect(
        display.firstWhere((e) => e.originalIndex == 2).isTransfer,
        isTrue,
      );
    });

    test('the legs to and from the station stay your own', () {
      final legs = journey(
        middle: _leg(mode: 'WALK', from: 'Hbf', to: 'Hbf (S)'),
      );
      final display = buildDisplayLegs(legs);

      expect(display.first.isTransfer, isFalse);
      expect(display.last.isTransfer, isFalse);
    });

    test('a bike between two rides is a change too', () {
      // The rule is about where the leg sits, not how you cover it.
      final legs = journey(
        middle: _leg(mode: 'BIKE', from: 'Hbf', to: 'Hbf (S)'),
      );

      expect(buildDisplayLegs(legs)[2].isTransfer, isTrue);
    });

    test('a ride is never a change', () {
      final legs = journey(
        middle: _leg(mode: 'BUS', from: 'Hbf', to: 'Hbf (S)', tripId: 'c'),
      );

      expect(buildDisplayLegs(legs)[2].isTransfer, isFalse);
    });

    test('a journey that is only a walk is left alone', () {
      final display = buildDisplayLegs([
        _leg(mode: 'WALK', from: 'START', to: 'END'),
      ]);

      expect(display.single.isTransfer, isFalse);
    });
  });

  group('endpointLabel', () {
    test('keeps a real name', () {
      expect(
        endpointLabel('Pankow', searched: 'Home', fallback: 'Start'),
        'Pankow',
      );
    });

    test('takes the searched name for a placeholder', () {
      expect(
        endpointLabel('START', searched: 'Home', fallback: 'Start'),
        'Home',
      );
    });

    test('falls back when nothing is named', () {
      expect(
        endpointLabel('END', searched: 'END', fallback: 'Destination'),
        'Destination',
      );
      expect(endpointLabel(null, fallback: 'Start'), 'Start');
    });
  });

  group('destinationLabel', () {
    test('names the searched place at the end of a walk', () {
      expect(
        destinationLabel(_coordinateToCoordinate(), searched: 'Terminal 1'),
        'Terminal 1',
      );
      expect(destinationLabel(_coordinateToCoordinate()), 'Destination');
    });

    test('names the last stop where the walk from it is not shown', () {
      final legs = [
        ..._coordinateToCoordinate().take(2),
        _shortWalk(from: 'Flughafen BER', to: 'END'),
      ];

      expect(destinationLabel(legs, searched: 'Terminal 1'), 'Flughafen BER');
    });

    test('names the last stop of a journey that ends on a ride', () {
      expect(
        destinationLabel(_coordinateToCoordinate().take(2).toList()),
        'Flughafen BER',
      );
    });
  });
}
