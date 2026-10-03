import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/api/transitous_client.dart';
import 'package:transportia/providers/theme_provider.dart';
import 'package:transportia/screens/shared_trip_screen.dart';
import 'package:transportia/utils/trip_link.dart';

final _trip = File('test/fixtures/transitous/trip.json').readAsStringSync();

/// Answers `/refresh-itinerary` with [status], recording where each request
/// went. 200 answers with the captured trip.
List<Uri> _serve({int status = 200}) {
  final requests = <Uri>[];
  TransitousClient.instance = TransitousClient(
    httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/refresh-itinerary')) {
        requests.add(request.url);
        return status == 200
            ? http.Response(
                _trip,
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              )
            : http.Response(
                '{"error":"Failed to decode itinerary-id"}',
                status,
              );
      }
      return http.Response('{}', 200);
    }),
  );
  return requests;
}

Future<void> _pump(WidgetTester tester, TripLink link) async {
  tester.view.physicalSize = const Size(400, 860);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeProvider>(
      create: (_) => ThemeProvider(),
      child: WidgetsApp(
        color: const Color(0xFF000000),
        localizationsDelegates: const [
          DefaultWidgetsLocalizations.delegate,
          DefaultCupertinoLocalizations.delegate,
        ],
        home: SharedTripScreen(link: link),
        pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (context, _, _) => builder(context),
        ),
      ),
    ),
  );
}

/// Lets the request run outside the fake clock, then the screen react.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  tearDown(() => TransitousClient.instance = TransitousClient());

  testWidgets('a link from the rider\'s server is read there straight away', (
    tester,
  ) async {
    final requests = _serve(status: 400);
    await _pump(
      tester,
      const TripLink(itineraryId: 'abc', host: 'api.transitous.org'),
    );
    await _settle(tester);

    expect(requests.single.host, 'api.transitous.org');
    expect(requests.single.queryParameters['itineraryId'], 'abc');
    expect(find.textContaining('This trip is from'), findsNothing);
  });

  testWidgets('a link from another server asks before any request', (
    tester,
  ) async {
    final requests = _serve();
    await _pump(
      tester,
      const TripLink(itineraryId: 'abc', host: 'motis.example'),
    );
    await _settle(tester);

    expect(find.text('This trip is from motis.example'), findsOneWidget);
    expect(requests, isEmpty);
  });

  testWidgets('agreeing reads the trip on the server that planned it', (
    tester,
  ) async {
    final requests = _serve(status: 400);
    await _pump(
      tester,
      const TripLink(itineraryId: 'abc', host: 'motis.example'),
    );
    await tester.tap(find.text('Open with motis.example'));
    await _settle(tester);

    expect(requests.single.host, 'motis.example');
  });

  testWidgets('declining reads it on the rider\'s own server', (tester) async {
    final requests = _serve(status: 400);
    await _pump(
      tester,
      const TripLink(itineraryId: 'abc', host: 'motis.example'),
    );
    await tester.tap(find.text('Try api.transitous.org instead'));
    await _settle(tester);

    expect(requests.single.host, 'api.transitous.org');
    // Failing there, the planning server is still offered.
    expect(find.text('Open with motis.example'), findsOneWidget);
  });

  testWidgets('an id the server cannot read says so, and can be retried', (
    tester,
  ) async {
    final requests = _serve(status: 400);
    await _pump(tester, const TripLink(itineraryId: 'abc'));
    await _settle(tester);

    expect(
      find.text("This link doesn't hold a trip api.transitous.org can read."),
      findsOneWidget,
    );
    await tester.tap(find.text('Try again'));
    await _settle(tester);
    expect(requests, hasLength(2));
  });

  testWidgets('a readable trip gives way to the trip itself', (tester) async {
    _serve();
    await _pump(tester, const TripLink(itineraryId: 'abc'));
    await _settle(tester);
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(SharedTripScreen), findsNothing);
  });
}
