import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/models/itinerary.dart';
import 'package:transportia/models/itinerary_response.dart';
import 'package:transportia/models/saved_trip.dart';
import 'package:transportia/services/recent_trips_service.dart';
import 'package:transportia/services/saved_trips_service.dart';
import 'package:transportia/utils/journey_graph.dart';

List<Itinerary> _load(String name) => ItineraryResponse.fromJson(
  jsonDecode(File('test/fixtures/transitous/$name.json').readAsStringSync())
      as Map<String, dynamic>,
).itineraries;

/// Literal, as a released build has stored it.
const String _savedTripsKey = 'saved_trips';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Wildau → Lindau Insel over ICE 1009 to Ingolstadt, and the same
  // journey replanned on from Ingolstadt: the same departure on the same
  // first train, then other trains.
  final original = _load(
    'plan_journey_graph',
  ).firstWhere((it) => it.legs.any((leg) => leg.displayName == 'ICE 1009'));
  final ice1009 = original.legs.firstWhere(
    (leg) => leg.displayName == 'ICE 1009',
  );
  final replanned = continueAfter(
    original,
    ice1009,
    _load('plan_journey_graph_onward'),
  ).firstWhere((it) => it.legs.last.endTime != original.legs.last.endTime);

  SavedTrip trip(Itinerary itinerary) =>
      SavedTrip.fromItinerary(itinerary: itinerary);

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SavedTripsService.savedTripsListenable.value = const [];
  });

  test('a journey replanned on from one of its rides is another journey', () {
    expect(replanned.startTime, original.startTime);
    expect(trip(replanned).id, isNot(trip(original).id));
  });

  test('saving a journey does not save the one replanned from it', () async {
    await SavedTripsService.saveTrip(trip(original));

    expect(await SavedTripsService.isSaved(trip(original).id), isTrue);
    expect(await SavedTripsService.isSaved(trip(replanned).id), isFalse);
  });

  test('opening the replanned journey adds it to the recent ones', () async {
    await RecentTripsService.record(original);
    await RecentTripsService.record(replanned);

    final recent = await RecentTripsService.getRecentTrips();
    expect(recent.map((t) => t.id), [trip(replanned).id, trip(original).id]);
  });

  test('a journey saved with an older id still matches itself', () async {
    // Older ids ended on the first ride's trip alone.
    final json = trip(original).toJson();
    final firstTrip = original.legs.firstWhere((leg) => leg.isRide).tripId!;
    final id = json['id'] as String;
    json['id'] = '${id.substring(0, id.indexOf('#'))}#$firstTrip';
    await SharedPreferencesAsync().setString(
      _savedTripsKey,
      jsonEncode([json]),
    );

    expect(await SavedTripsService.isSaved(trip(original).id), isTrue);
    expect(await SavedTripsService.isSaved(trip(replanned).id), isFalse);
  });
}
