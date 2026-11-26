import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/api/transitous_api_exception.dart';
import 'package:transportia/models/itinerary.dart';
import 'package:transportia/services/itinerary_refresh_service.dart';

Leg _leg({
  required String mode,
  String? tripId,
  required DateTime startTime,
  required DateTime endTime,
  bool cancelled = false,
  bool realTime = false,
  String? geometry,
}) {
  return Leg(
    mode: mode,
    from: const TransitPlace(name: 'A', lat: 52.5, lon: 13.4),
    to: const TransitPlace(name: 'B', lat: 52.4, lon: 13.5),
    startTime: startTime,
    endTime: endTime,
    duration: endTime.difference(startTime).inSeconds,
    tripId: tripId,
    cancelled: cancelled,
    realTime: realTime,
    legGeometry: geometry == null
        ? null
        : EncodedPolyline(points: geometry, precision: 6, length: 2),
  );
}

Itinerary _itinerary(List<Leg> legs) {
  return Itinerary(
    duration: legs.last.endTime.difference(legs.first.startTime).inSeconds,
    startTime: legs.first.startTime,
    endTime: legs.last.endTime,
    transfers: 0,
    legs: legs,
  );
}

final DateTime _depart = DateTime.parse('2026-08-05T07:14:00Z');
final DateTime _arrive = DateTime.parse('2026-08-05T07:29:00Z');

void main() {
  group('ItineraryRefreshService.refresh', () {
    test('reports notRefreshable for a walk-only itinerary', () async {
      final itinerary = _itinerary([
        _leg(mode: 'WALK', startTime: _depart, endTime: _arrive),
      ]);

      final result = await ItineraryRefreshService.refresh(
        itinerary,
        fetchTripDetails: ({required String tripId}) async =>
            fail('should not fetch anything for a walk-only itinerary'),
      );

      expect(result.freshness, ItineraryFreshness.notRefreshable);
      expect(result.didRefresh, isFalse);
      expect(result.itinerary, same(itinerary));
    });

    test('reports scheduled when the server has nothing on the trip', () async {
      final itinerary = _itinerary([
        _leg(
          mode: 'RAIL',
          tripId: 'trip-1',
          startTime: _depart,
          endTime: _arrive,
        ),
      ]);

      final result = await ItineraryRefreshService.refresh(
        itinerary,
        fetchTripDetails: ({required String tripId}) async =>
            throw TransitousApiException('trip not found', statusCode: 404),
      );

      // This is the far-future case: nothing was learned, so the caller must
      // not be told the itinerary was just updated.
      expect(result.freshness, ItineraryFreshness.scheduled);
      expect(result.didRefresh, isFalse);
      expect(result.itinerary, same(itinerary));
    });

    for (final (what, error) in [
      ('no response', TransitousApiException('timed out')),
      ('a socket that would not open', Exception('offline')),
    ]) {
      test('reports unreachable for $what, keeping what it had', () async {
        final itinerary = _itinerary([
          _leg(
            mode: 'RAIL',
            tripId: 'trip-1',
            startTime: _depart,
            endTime: _arrive,
            realTime: true,
          ),
        ]);

        final result = await ItineraryRefreshService.refresh(
          itinerary,
          fetchTripDetails: ({required String tripId}) async => throw error,
        );

        // Not "scheduled": the live times it carries are still the last
        // known, and nothing said otherwise.
        expect(result.freshness, ItineraryFreshness.unreachable);
        expect(result.didRefresh, isFalse);
        expect(result.itinerary, same(itinerary));
      });
    }

    test('one answer among failures is an answer', () async {
      final itinerary = _itinerary([
        _leg(
          mode: 'RAIL',
          tripId: 'trip-1',
          startTime: _depart,
          endTime: _arrive,
        ),
        _leg(
          mode: 'RAIL',
          tripId: 'trip-2',
          startTime: _arrive,
          endTime: _arrive,
        ),
      ]);

      final result = await ItineraryRefreshService.refresh(
        itinerary,
        fetchTripDetails: ({required String tripId}) async =>
            throw tripId == 'trip-1'
                ? TransitousApiException('trip not found', statusCode: 404)
                : Exception('offline'),
      );

      expect(result.freshness, ItineraryFreshness.scheduled);
    });

    test('reports live and merges fresh times when lookups succeed', () async {
      final itinerary = _itinerary([
        _leg(
          mode: 'RAIL',
          tripId: 'trip-1',
          startTime: _depart,
          endTime: _arrive,
        ),
      ]);

      final delayedDepart = _depart.add(const Duration(minutes: 5));
      final delayedArrive = _arrive.add(const Duration(minutes: 5));

      final result = await ItineraryRefreshService.refresh(
        itinerary,
        fetchTripDetails: ({required String tripId}) async => _itinerary([
          _leg(
            mode: 'RAIL',
            tripId: tripId,
            startTime: delayedDepart,
            endTime: delayedArrive,
            realTime: true,
          ),
        ]),
      );

      expect(result.freshness, ItineraryFreshness.live);
      expect(result.didRefresh, isTrue);
      expect(result.itinerary.startTime, delayedDepart);
      expect(result.itinerary.endTime, delayedArrive);
      expect(result.itinerary.legs.single.realTime, isTrue);
    });

    test('reports changed when a refreshed leg is cancelled', () async {
      final itinerary = _itinerary([
        _leg(
          mode: 'RAIL',
          tripId: 'trip-1',
          startTime: _depart,
          endTime: _arrive,
        ),
      ]);

      final result = await ItineraryRefreshService.refresh(
        itinerary,
        fetchTripDetails: ({required String tripId}) async => _itinerary([
          _leg(
            mode: 'RAIL',
            tripId: tripId,
            startTime: _depart,
            endTime: _arrive,
            cancelled: true,
          ),
        ]),
      );

      expect(result.freshness, ItineraryFreshness.changed);
      // Still counts as a refresh: we did learn the current state.
      expect(result.didRefresh, isTrue);
      expect(result.itinerary.legs.single.cancelled, isTrue);
    });

    test('merges only the legs whose trip resolved', () async {
      final itinerary = _itinerary([
        _leg(
          mode: 'RAIL',
          tripId: 'trip-1',
          startTime: _depart,
          endTime: _arrive,
        ),
        _leg(
          mode: 'BUS',
          tripId: 'trip-2',
          startTime: _arrive,
          endTime: _arrive.add(const Duration(minutes: 10)),
        ),
      ]);

      final result = await ItineraryRefreshService.refresh(
        itinerary,
        fetchTripDetails: ({required String tripId}) async {
          if (tripId == 'trip-2') throw Exception('no data');
          return _itinerary([
            _leg(
              mode: 'RAIL',
              tripId: tripId,
              startTime: _depart,
              endTime: _arrive,
              realTime: true,
            ),
          ]);
        },
      );

      expect(result.freshness, ItineraryFreshness.live);
      expect(result.itinerary.legs.first.realTime, isTrue);
      expect(result.itinerary.legs.last.realTime, isFalse);
    });
  });

  group('the single-request refresh path', () {
    final itinerary = _itinerary([
      _leg(
        mode: 'RAIL',
        tripId: 'trip-1',
        startTime: _depart,
        endTime: _arrive,
      ),
    ]);

    test(
      'uses the whole-itinerary refresh rather than per-trip lookups',
      () async {
        var itineraryFetches = 0;
        final result = await ItineraryRefreshService.refresh(
          itinerary,
          fetchItinerary: (source) async {
            itineraryFetches++;
            return _itinerary([
              _leg(
                mode: 'RAIL',
                tripId: 'trip-1',
                startTime: _depart.add(const Duration(minutes: 4)),
                endTime: _arrive.add(const Duration(minutes: 4)),
                realTime: true,
              ),
            ]);
          },
        );

        expect(itineraryFetches, 1);
        expect(result.freshness, ItineraryFreshness.live);
        expect(result.didRefresh, isTrue);
        expect(
          result.itinerary.legs.single.startTime,
          _depart.add(const Duration(minutes: 4)),
        );
      },
    );

    test('reports changed when the refreshed journey is cancelled', () async {
      final result = await ItineraryRefreshService.refresh(
        itinerary,
        fetchItinerary: (source) async => _itinerary([
          _leg(
            mode: 'RAIL',
            tripId: 'trip-1',
            startTime: _depart,
            endTime: _arrive,
            cancelled: true,
            realTime: true,
          ),
        ]),
      );

      expect(result.freshness, ItineraryFreshness.changed);
    });

    test('falls back to per-trip lookups when the refresh fails', () async {
      var tripFetches = 0;
      final result = await ItineraryRefreshService.refresh(
        itinerary,
        fetchItinerary: (source) async => throw StateError('endpoint down'),
        fetchTripDetails: ({required String tripId}) async {
          tripFetches++;
          return _itinerary([
            _leg(
              mode: 'RAIL',
              tripId: tripId,
              startTime: _depart.add(const Duration(minutes: 2)),
              endTime: _arrive.add(const Duration(minutes: 2)),
              realTime: true,
            ),
          ]);
        },
      );

      expect(tripFetches, 1);
      expect(result.freshness, ItineraryFreshness.live);
    });

    test('falls back when the server re-plans instead of refreshing', () async {
      // A different number of legs means the journey on screen no longer
      // matches; swapping it out silently would be worse than not refreshing.
      var tripFetches = 0;
      await ItineraryRefreshService.refresh(
        itinerary,
        fetchItinerary: (source) async => _itinerary([
          _leg(
            mode: 'WALK',
            startTime: _depart,
            endTime: _depart.add(const Duration(minutes: 5)),
          ),
          _leg(
            mode: 'RAIL',
            tripId: 'trip-9',
            startTime: _depart.add(const Duration(minutes: 5)),
            endTime: _arrive,
          ),
        ]),
        fetchTripDetails: ({required String tripId}) async {
          tripFetches++;
          throw StateError('no data');
        },
      );

      expect(tripFetches, 1);
    });

    test('still skips everything for a walk-only itinerary', () async {
      final walkOnly = _itinerary([
        _leg(mode: 'WALK', startTime: _depart, endTime: _arrive),
      ]);

      final result = await ItineraryRefreshService.refresh(
        walkOnly,
        fetchItinerary: (source) async =>
            fail('should not refresh a walk-only itinerary'),
      );

      expect(result.freshness, ItineraryFreshness.notRefreshable);
    });
  });

  group('a refresh must not quietly become a different journey', () {
    test(
      'keeps the planned geometry when the refresh answers without it',
      () async {
        // A street leg with no geometry is drawn as a straight line from origin
        // to station, which is not where anybody walks.
        final stored = _itinerary([
          _leg(
            mode: 'WALK',
            startTime: _depart,
            endTime: _depart.add(const Duration(minutes: 4)),
            geometry: 'srufHi~mpA',
          ),
          _leg(
            mode: 'SUBWAY',
            tripId: 'trip-1',
            startTime: _depart.add(const Duration(minutes: 4)),
            endTime: _arrive,
          ),
        ]);

        final result = await ItineraryRefreshService.refresh(
          stored,
          fetchItinerary: (_) async => _itinerary([
            _leg(
              mode: 'WALK',
              startTime: _depart.add(const Duration(minutes: 1)),
              endTime: _depart.add(const Duration(minutes: 5)),
            ),
            _leg(
              mode: 'SUBWAY',
              tripId: 'trip-1',
              startTime: _depart.add(const Duration(minutes: 5)),
              endTime: _arrive,
              realTime: true,
            ),
          ]),
        );

        expect(result.itinerary.legs.first.legGeometry?.points, 'srufHi~mpA');
        // And it is still a refresh: the new times came through.
        expect(
          result.itinerary.legs.first.startTime,
          _depart.add(const Duration(minutes: 1)),
        );
        expect(result.freshness, ItineraryFreshness.live);
      },
    );

    test('rejects a re-plan that happens to have the same leg count', () async {
      // Walk legs carry no tripId for the server to pin them by, so they are
      // exactly the ones it is free to replace — and a substituted journey
      // would surface as "this connection has changed".
      final stored = _itinerary([
        _leg(
          mode: 'SUBWAY',
          tripId: 'trip-1',
          startTime: _depart,
          endTime: _arrive,
        ),
      ]);

      final result = await ItineraryRefreshService.refresh(
        stored,
        fetchItinerary: (_) async => _itinerary([
          _leg(
            mode: 'BUS',
            tripId: 'trip-9',
            startTime: _depart,
            endTime: _arrive,
            cancelled: true,
          ),
        ]),
        fetchTripDetails: ({required String tripId}) async => _itinerary([
          _leg(
            mode: 'SUBWAY',
            tripId: 'trip-1',
            startTime: _depart,
            endTime: _arrive,
          ),
        ]),
      );

      expect(result.itinerary.legs.single.mode, 'SUBWAY');
      expect(result.freshness, isNot(ItineraryFreshness.changed));
    });
  });

  group('the per-trip fallback', () {
    test('keeps the stops the journey rides, not the whole line', () async {
      // `/trip` answers with the service end to end. Taken whole, an expanded
      // leg listed every station on the line and the leg reported the line's
      // own first departure as its own.
      final ride = Leg(
        mode: 'SUBURBAN',
        tripId: 'trip-1',
        from: const TransitPlace(name: 'Middle', lat: 52.5, lon: 13.4),
        to: const TransitPlace(name: 'Near the end', lat: 52.4, lon: 13.5),
        startTime: _depart,
        endTime: _arrive,
        duration: _arrive.difference(_depart).inSeconds,
      );

      TransitPlace stop(String name, Duration offset) => TransitPlace(
        name: name,
        lat: 52.45,
        lon: 13.45,
        arrival: _depart.add(offset),
        departure: _depart.add(offset),
      );

      final result = await ItineraryRefreshService.refresh(
        _itinerary([ride]),
        fetchTripDetails: ({required String tripId}) async => _itinerary([
          Leg(
            mode: 'SUBURBAN',
            tripId: 'trip-1',
            realTime: true,
            from: TransitPlace(
              name: 'First on the line',
              lat: 52.6,
              lon: 13.3,
              departure: _depart.subtract(const Duration(minutes: 40)),
            ),
            to: TransitPlace(
              name: 'Last on the line',
              lat: 52.3,
              lon: 13.6,
              arrival: _arrive.add(const Duration(minutes: 40)),
            ),
            startTime: _depart.subtract(const Duration(minutes: 40)),
            endTime: _arrive.add(const Duration(minutes: 40)),
            duration: 5400,
            intermediateStops: [
              stop('Before you got on', const Duration(minutes: -20)),
              stop('Middle', Duration.zero),
              stop('One you pass', const Duration(minutes: 5)),
              stop('Near the end', const Duration(minutes: 15)),
              stop('After you got off', const Duration(minutes: 25)),
            ],
          ),
        ]),
      );

      final leg = result.itinerary.legs.single;
      expect(leg.intermediateStops.map((s) => s.name), ['One you pass']);
      expect(leg.fromName, 'Middle');
      expect(leg.toName, 'Near the end');
      expect(leg.startTime, _depart);
      expect(leg.endTime, _depart.add(const Duration(minutes: 15)));
    });

    test(
      'merges the leg for the trip it asked about, not the first one',
      () async {
        // A /trip response that leads with a walk would otherwise lend its
        // times and its cancellation to every transit leg.
        final stored = _itinerary([
          _leg(
            mode: 'SUBWAY',
            tripId: 'trip-1',
            startTime: _depart,
            endTime: _arrive,
          ),
        ]);

        final result = await ItineraryRefreshService.refresh(
          stored,
          fetchTripDetails: ({required String tripId}) async => _itinerary([
            _leg(
              mode: 'WALK',
              startTime: _depart.subtract(const Duration(minutes: 9)),
              endTime: _depart,
              cancelled: true,
            ),
            _leg(
              mode: 'SUBWAY',
              tripId: 'trip-1',
              startTime: _depart.add(const Duration(minutes: 2)),
              endTime: _arrive,
              realTime: true,
            ),
          ]),
        );

        final leg = result.itinerary.legs.single;
        expect(leg.cancelled, isFalse, reason: 'the walk leg is not this trip');
        expect(leg.startTime, _depart.add(const Duration(minutes: 2)));
        expect(result.freshness, ItineraryFreshness.live);
      },
    );
  });
}
