import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/models/itinerary.dart';
import 'package:transportia/models/saved_trip.dart';
import 'package:transportia/services/itinerary_refresh_service.dart';
import 'package:transportia/services/saved_trips_service.dart';
import 'package:transportia/services/stored_list_store.dart';

import 'support/plan_fixtures.dart';

/// Keeping a journey means keeping *that* journey. A live check may update the
/// times on it; it may not quietly replace it with a different connection.
SavedTrip _trip({required DateTime departure}) => SavedTrip.fromItinerary(
  itinerary: Itinerary.fromJson(planItineraryJson(departure: departure)),
);

Itinerary _refreshed({required DateTime departure}) =>
    Itinerary.fromJson(planItineraryJson(departure: departure));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('what may be written over a saved trip', () {
    test('a live check that reached data may', () {
      expect(
        SavedTripsService.shouldStoreLiveResult(
          didRefresh: true,
          freshness: ItineraryFreshness.live,
        ),
        isTrue,
      );
    });

    test('a check that reached nothing may not', () {
      // Nothing was learned, so there is nothing to keep.
      expect(
        SavedTripsService.shouldStoreLiveResult(
          didRefresh: false,
          freshness: ItineraryFreshness.live,
        ),
        isFalse,
      );
    });

    test('a check that came back with a different connection may not', () {
      // This is the one that matters: overwriting here would destroy the
      // journey the rider chose to keep.
      expect(
        SavedTripsService.shouldStoreLiveResult(
          didRefresh: true,
          freshness: ItineraryFreshness.changed,
        ),
        isFalse,
      );
    });
  });

  group('storing a live result', () {
    test('updates the stored times and stamps when', () async {
      final departure = DateTime.now().add(const Duration(hours: 2));
      final trip = _trip(departure: departure);
      await SavedTripsService.saveTrip(trip);

      final later = departure.add(const Duration(minutes: 6));
      final at = DateTime.now();
      await SavedTripsService.storeLiveItinerary(
        id: trip.id,
        refreshed: _refreshed(departure: later),
        didRefresh: true,
        freshness: ItineraryFreshness.live,
        at: at,
      );

      final stored = (await SavedTripsService.getSavedTrips()).single;
      expect(stored.liveUpdatedAt, at);
      expect(stored.itinerary.startTime.toUtc(), later.toUtc());
      // Reopening reads the kept snapshot, so the new times survive a restart.
      expect(stored.departureTime.toUtc(), later.toUtc());
    });

    test('a changed connection leaves the trip exactly as it was', () async {
      final departure = DateTime.now().add(const Duration(hours: 2));
      final trip = _trip(departure: departure);
      await SavedTripsService.saveTrip(trip);

      await SavedTripsService.storeLiveItinerary(
        id: trip.id,
        refreshed: _refreshed(
          departure: departure.add(const Duration(days: 1)),
        ),
        didRefresh: true,
        freshness: ItineraryFreshness.changed,
      );

      final stored = (await SavedTripsService.getSavedTrips()).single;
      expect(stored.liveUpdatedAt, isNull);
      expect(stored.departureTime, trip.departureTime);
    });

    test('a trip that is not saved is not created by a refresh', () async {
      await SavedTripsService.storeLiveItinerary(
        id: 'never-saved',
        refreshed: _refreshed(
          departure: DateTime.now().add(const Duration(hours: 2)),
        ),
        didRefresh: true,
        freshness: ItineraryFreshness.live,
      );

      expect(await SavedTripsService.getSavedTrips(), isEmpty);
    });

    test('the stamp survives a round trip through storage', () async {
      final departure = DateTime.now().add(const Duration(hours: 2));
      final trip = _trip(departure: departure);
      await SavedTripsService.saveTrip(trip);

      final at = DateTime.now();
      await SavedTripsService.storeLiveItinerary(
        id: trip.id,
        refreshed: _refreshed(departure: departure),
        didRefresh: true,
        freshness: ItineraryFreshness.live,
        at: at,
      );

      // Re-read from scratch, which is what a restart does.
      final reread = SavedTrip.fromJson(
        (await SavedTripsService.getSavedTrips()).single.toJson(),
      );
      expect(reread.liveUpdatedAt?.toIso8601String(), at.toIso8601String());
    });
  });

  group('a live result and a rename at once', () {
    // The detail screen stores a live result without waiting for it, so the
    // rider can rename the trip while that write is still on its way.
    Future<void> storeLive(SavedTrip trip, DateTime later) =>
        SavedTripsService.storeLiveItinerary(
          id: trip.id,
          refreshed: _refreshed(departure: later),
          didRefresh: true,
          freshness: ItineraryFreshness.live,
          at: later,
        );

    for (final renameFirst in [false, true]) {
      final order = renameFirst ? 'rename first' : 'live result first';
      test('both land, $order', () async {
        final departure = DateTime.now().add(const Duration(hours: 2));
        final trip = _trip(departure: departure);
        await SavedTripsService.saveTrip(trip);
        final later = departure.add(const Duration(minutes: 6));

        await Future.wait([
          if (renameFirst) SavedTripsService.renameTrip(trip.id, 'Work'),
          storeLive(trip, later),
          if (!renameFirst) SavedTripsService.renameTrip(trip.id, 'Work'),
        ]);

        final stored = (await SavedTripsService.getSavedTrips()).single;
        expect(stored.label, 'Work');
        expect(stored.departureTime.toUtc(), later.toUtc());
        expect(stored.liveUpdatedAt, later);
      });
    }
  });

  group('saved trips this build cannot read', () {
    // Literal, as a released build would have written it.
    const key = 'saved_trips';
    const raw = '[{"id":"cut off mid-write"';

    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({key: raw});
    });

    Future<String?> stored() => SharedPreferencesAsync().getString(key);

    test('are not written over by a save', () async {
      final trip = _trip(
        departure: DateTime.now().add(const Duration(hours: 2)),
      );
      await expectLater(
        SavedTripsService.saveTrip(trip),
        throwsA(isA<StoredListUnreadable>()),
      );
      expect(await stored(), raw);
    });

    test(
      'are not written over by a live result, which fails quietly',
      () async {
        await SavedTripsService.storeLiveItinerary(
          id: 'any',
          refreshed: _refreshed(departure: DateTime.now()),
          didRefresh: true,
          freshness: ItineraryFreshness.live,
        );
        expect(await stored(), raw);
      },
    );

    test('are not written over by pruning, which reports none', () async {
      expect(await SavedTripsService.pruneExpired(), 0);
      expect(await stored(), raw);
    });

    test('show as none', () async {
      expect(await SavedTripsService.getSavedTrips(), isEmpty);
    });
  });
}
