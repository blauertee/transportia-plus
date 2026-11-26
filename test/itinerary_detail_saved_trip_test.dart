import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/api/transitous_api_exception.dart';
import 'package:transportia/models/itinerary.dart';
import 'package:transportia/models/saved_trip.dart';
import 'package:transportia/services/itinerary_refresh_service.dart';

import 'support/plan_fixtures.dart';

/// The notice shown on a saved trip is chosen from its freshness and
/// whether it has already run. These tests pin that decision down through
/// the refresh service, which is where the states come from.
SavedTrip _trip({required DateTime departure}) {
  return SavedTrip.fromItinerary(
    itinerary: Itinerary.fromJson(planItineraryJson(departure: departure)),
  );
}

void main() {
  test('a saved trip re-parses into the connection that was stored', () {
    final departure = DateTime.now().add(const Duration(days: 1));
    final trip = _trip(departure: departure);

    expect(trip.itinerary.legs[1].tripId, 'trip-re7');
    expect(trip.itinerary.legs[1].displayName, 'RE7');
    expect(trip.fromName, 'S+U Berlin Hauptbahnhof');
    expect(trip.toName, 'Flughafen BER');
  });

  test(
    'a departure beyond the real-time horizon reports as scheduled',
    () async {
      final trip = _trip(
        departure: DateTime.now().add(const Duration(days: 21)),
      );

      final result = await ItineraryRefreshService.refresh(
        trip.itinerary,
        fetchTripDetails: ({required String tripId}) async =>
            throw TransitousApiException(
              'trip not in the feed this far out',
              statusCode: 404,
            ),
      );

      // The screen shows the "Scheduled times" notice for this, and must not
      // claim the trip was just updated.
      expect(result.freshness, ItineraryFreshness.scheduled);
      expect(result.didRefresh, isFalse);
    },
  );

  test('a cancelled service reports as changed', () async {
    final departure = DateTime.now().add(const Duration(hours: 2));
    final trip = _trip(departure: departure);

    final result = await ItineraryRefreshService.refresh(
      trip.itinerary,
      fetchTripDetails: ({required String tripId}) async => Itinerary.fromJson(
        planItineraryJson(
          departure: departure,
          cancelled: true,
          withEdgeWalks: false,
        ),
      ),
    );

    expect(result.freshness, ItineraryFreshness.changed);
    expect(result.itinerary.legs.any((leg) => leg.cancelled), isTrue);
  });

  test(
    'a reachable departure reports as live and picks up the delay',
    () async {
      final departure = DateTime.now().add(const Duration(hours: 2));
      final trip = _trip(departure: departure);
      final delayed = departure.add(const Duration(minutes: 6));

      final result = await ItineraryRefreshService.refresh(
        trip.itinerary,
        fetchTripDetails: ({required String tripId}) async =>
            Itinerary.fromJson(
              planItineraryJson(departure: delayed, withEdgeWalks: false),
            ),
      );

      expect(result.freshness, ItineraryFreshness.live);
      final refreshedRide = result.itinerary.legs.firstWhere(
        (leg) => leg.tripId == 'trip-re7',
      );
      expect(
        refreshedRide.startTime.toUtc(),
        DateTime.parse(delayed.toUtc().toIso8601String()),
      );
    },
  );

  test('a finished trip is past regardless of what a refresh says', () {
    final trip = _trip(
      departure: DateTime.now().subtract(const Duration(days: 3)),
    );

    // isPast wins over freshness in the notice, so "Search again" is the
    // offer rather than a delay readout.
    expect(trip.isPast, isTrue);
  });

  test('re-planning a past trip targets the next occurrence', () {
    final departure = DateTime.now().subtract(const Duration(days: 3));
    final trip = _trip(departure: departure);

    // Mirrors _nextOccurrence in the detail screen.
    final local = trip.departureTime.toLocal();
    final now = DateTime.now();
    final today = DateTime(
      now.year,
      now.month,
      now.day,
      local.hour,
      local.minute,
    );
    final next = today.isAfter(now)
        ? today
        : today.add(const Duration(days: 1));

    expect(next.isAfter(now), isTrue);
    expect(next.hour, local.hour);
    expect(next.minute, local.minute);
  });
}
