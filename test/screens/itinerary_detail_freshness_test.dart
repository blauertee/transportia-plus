import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/api/transitous_client.dart';
import 'package:transportia/models/itinerary.dart';
import 'package:transportia/models/saved_trip.dart';
import 'package:transportia/providers/theme_provider.dart';
import 'package:transportia/screens/itinerary_detail_screen.dart';

import '../support/plan_fixtures.dart';

/// Far enough ahead that the trip has not happened whenever this runs.
final DateTime _departure = DateTime.utc(2099, 3, 2, 9);

const String _scheduledNotice = 'Scheduled times';

/// A saved trip whose ride carries live times, or only the timetable.
SavedTrip _trip({required bool live}) {
  final json = planItineraryJson(departure: _departure);
  for (final leg in json['legs'] as List) {
    (leg as Map<String, dynamic>)['realTime'] = live;
  }
  return SavedTrip.fromItinerary(
    itinerary: Itinerary.fromJson(json),
    savedAt: _departure.subtract(const Duration(days: 1)),
  );
}

/// No network at all: every request fails before a response.
http.Client _offline() =>
    MockClient((_) async => throw http.ClientException('offline'));

/// A server that answers, and has nothing on the trip.
http.Client _emptyFeed() => MockClient(
  (_) async => http.Response(
    jsonEncode({'error': 'trip not found'}),
    404,
    headers: {'content-type': 'application/json'},
  ),
);

Future<void> _open(WidgetTester tester, SavedTrip trip) async {
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeProvider>(
      create: (_) => ThemeProvider(),
      child: CupertinoApp(
        home: ItineraryDetailScreen(itinerary: trip.itinerary, savedTrip: trip),
      ),
    ),
  );
  // The check on open runs over the (mock) network.
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  tearDown(() => TransitousClient.instance = TransitousClient());

  testWidgets('offline, a trip that stored live times is not called '
      'scheduled', (tester) async {
    TransitousClient.instance = TransitousClient(httpClient: _offline());

    await _open(tester, _trip(live: true));

    expect(find.textContaining(_scheduledNotice), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('offline, a trip that only ever had the timetable says so', (
    tester,
  ) async {
    TransitousClient.instance = TransitousClient(httpClient: _offline());

    await _open(tester, _trip(live: false));

    expect(find.textContaining(_scheduledNotice), findsOne);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a feed with nothing on a trip with no live times says '
      'scheduled', (tester) async {
    TransitousClient.instance = TransitousClient(httpClient: _emptyFeed());

    await _open(tester, _trip(live: false));

    expect(find.textContaining(_scheduledNotice), findsOne);
    await tester.pumpWidget(const SizedBox());
  });
}
