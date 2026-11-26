import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/models/itinerary.dart';
import 'package:transportia/services/recent_trips_service.dart';
import 'package:transportia/services/saved_trips_service.dart';

import '../support/plan_fixtures.dart';

final DateTime _monday = DateTime.utc(2026, 9, 28, 8);

Itinerary _connection({String tripId = 'trip-re7', DateTime? departure}) =>
    Itinerary.fromJson(
      planItineraryJson(tripId: tripId, departure: departure ?? _monday),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SavedTripsService.savedTripsListenable.value = const [];
  });

  test('nothing opened yet is an empty list', () async {
    expect(await RecentTripsService.getRecentTrips(), isEmpty);
  });

  test('the connection opened last comes first', () async {
    await RecentTripsService.record(_connection(tripId: 'first'));
    await RecentTripsService.record(_connection(tripId: 'second'));

    final trips = await RecentTripsService.getRecentTrips();

    expect(trips.map((t) => t.itinerary.legs[1].tripId), ['second', 'first']);
  });

  test('reopening a connection moves it up instead of repeating it', () async {
    await RecentTripsService.record(_connection(tripId: 'a'));
    await RecentTripsService.record(_connection(tripId: 'b'));
    await RecentTripsService.record(_connection(tripId: 'a'));

    final trips = await RecentTripsService.getRecentTrips();

    expect(trips.map((t) => t.itinerary.legs[1].tripId), ['a', 'b']);
  });

  test('the same two places at another time are another trip', () async {
    await RecentTripsService.record(_connection());
    await RecentTripsService.record(
      _connection(departure: _monday.add(const Duration(hours: 1))),
    );

    expect(await RecentTripsService.getRecentTrips(), hasLength(2));
  });

  test('keeps only the most recent few, dropping the oldest', () async {
    const extra = 2;
    for (var i = 0; i < RecentTripsService.maxTrips + extra; i++) {
      await RecentTripsService.record(_connection(tripId: 'trip-$i'));
    }

    final trips = await RecentTripsService.getRecentTrips();

    expect(trips, hasLength(RecentTripsService.maxTrips));
    expect(trips.first.itinerary.legs[1].tripId, 'trip-6');
    expect(
      trips.map((t) => t.itinerary.legs[1].tripId),
      isNot(contains('trip-0')),
    );
  });

  test(
    'keeps the searched names, as saving from the same place would',
    () async {
      await RecentTripsService.record(
        _connection(),
        fromName: 'Home',
        toName: 'Airport',
      );

      final trip = (await RecentTripsService.getRecentTrips()).single;

      expect(trip.fromName, 'Home');
      expect(trip.toName, 'Airport');
      expect(trip.departureTime, _connection().startTime);
    },
  );

  test('a recent trip is not a saved one', () async {
    // They share a shape, not a list: the saved trips screen shows only what
    // the rider chose to keep.
    await RecentTripsService.record(_connection());

    expect(await SavedTripsService.getSavedTrips(), isEmpty);
    expect(await RecentTripsService.getRecentTrips(), hasLength(1));
  });

  test('an unreadable entry is skipped, not the whole list', () async {
    await RecentTripsService.record(_connection());
    final good = (await RecentTripsService.getRecentTrips()).single;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({
          // Literal, as a released build would have written it.
          'recent_trips': jsonEncode([
            {'fromName': 'My Location', 'toName': 'Alexanderplatz'},
            good.toJson(),
          ]),
        });

    final trips = await RecentTripsService.getRecentTrips();

    expect(trips.map((t) => t.id), [good.id]);
  });

  test('connections opened at once are all kept', () async {
    await Future.wait([
      RecentTripsService.record(_connection()),
      RecentTripsService.record(
        _connection(departure: DateTime.utc(2026, 8, 5, 9)),
      ),
    ]);

    expect(await RecentTripsService.getRecentTrips(), hasLength(2));
  });
}
