import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:transportia/providers/theme_provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/api/transitous_client.dart';
import 'package:transportia/models/my_location.dart';
import 'package:transportia/models/transitous/enums.dart';
import 'package:transportia/screens/map_place_picker/map_place_picker_screen.dart';
import 'package:transportia/screens/location_search_screen.dart';
import 'package:transportia/services/favorites_service.dart';
import 'package:transportia/models/saved_place.dart';
import 'package:transportia/services/saved_places_service.dart';
import 'package:transportia/utils/place_icons.dart';

FavoritePlace _favourite({
  required String id,
  required String name,
  String? label,
  String type = 'STOP',
  double lat = 52.5,
  double lon = 13.4,
  // A stop is only offered when its feed id is known, so the default fixture
  // carries one; pass null to model a favourite kept before ids were stored.
  String? stopId = 'de-DELFI_de:11000:900100003',
  String iconName = FavoritePlace.defaultIconName,
}) => FavoritePlace(
  id: id,
  name: name,
  label: label,
  type: type,
  stopId: type.toUpperCase() == 'STOP' ? stopId : null,
  lat: lat,
  lon: lon,
  iconName: iconName,
  addedAt: DateTime.utc(2026, 1, 1),
);

/// Keeps [favourites] in the order given.
Future<void> _keep(List<FavoritePlace> favourites) async {
  for (final favourite in favourites) {
    await FavoritesService.saveFavorite(favourite);
  }
  await FavoritesService.reorderFavorites(favourites);
}

SavedPlace _recent(
  String name, {
  String type = 'STOP',
  double lat = 52.5,
  double lon = 13.46,
  List<TransitMode> modes = const [],
}) => SavedPlace(
  name: name,
  type: type,
  lat: lat,
  lon: lon,
  stopId: type == 'STOP' ? 'de-DELFI_$name' : null,
  importance: SavedPlacesService.initialImportance,
  modes: modes,
);

Future<void> _remember(SavedPlacesBucket bucket, List<SavedPlace> places) =>
    SavedPlacesService.savePlaces(bucket: bucket, places: places);

List<String> _storedOrder() => [
  for (final f in FavoritesService.favoritesListenable.value) f.id,
];

/// Holds a favourite still until it lifts to be dragged; [past] more keeps it
/// still after that.
Future<TestGesture> _press(
  WidgetTester tester,
  String text, {
  Duration past = Duration.zero,
}) async {
  final gesture = await tester.startGesture(tester.getCenter(find.text(text)));
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  if (past > Duration.zero) await tester.pump(past);
  return gesture;
}

/// Lifts a favourite and drags it [dy] down, in steps, as a finger would.
Future<void> _drag(WidgetTester tester, String text, double dy) async {
  final gesture = await _press(tester, text);
  const steps = 8;
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(Offset(0, dy / steps));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester, {
  bool showMyLocation = false,
  String? type,
  SavedPlacesBucket bucket = SavedPlacesBucket.search,
  LatLng? placeBias,
  String initialQuery = '',
}) async {
  tester.view.physicalSize = const Size(420, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // Pushed as a route rather than handed to WidgetsApp's builder, which sits
  // outside the Navigator: the screen focuses its field on open, and an
  // EditableText needs an Overlay to put its selection handles in.
  await tester.pumpWidget(
    // The map picker this screen opens reads the map style from it.
    ChangeNotifierProvider<ThemeProvider>(
      create: (_) => ThemeProvider(),
      child: WidgetsApp(
        color: const Color(0xFF000000),
        // The same delegates app.dart installs; showCupertinoDialog wants
        // CupertinoLocalizations for its barrier label.
        localizationsDelegates: const [
          DefaultWidgetsLocalizations.delegate,
          DefaultCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en', 'US')],
        onGenerateRoute: (settings) => PageRouteBuilder<void>(
          settings: settings,
          pageBuilder: (_, _, _) => LocationSearchScreen(
            title: 'Destination',
            bucket: bucket,
            type: type,
            showMyLocation: showMyLocation,
            placeBias: placeBias,
            initialQuery: initialQuery,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The result list's scroller; the field has one of its own.
final _resultList = find.descendant(
  of: find.byType(ListView),
  matching: find.byType(Scrollable),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    FavoritesService.favoritesListenable.value = const [];
  });

  testWidgets('favourites are there before a single character is typed', (
    tester,
  ) async {
    // The moment you want a favourite is when the field is empty; the old
    // dropdown deliberately withheld them until you started typing.
    await _keep([
      _favourite(id: 'a', name: 'Hauptbahnhof', label: 'Home'),
      _favourite(id: 'b', name: 'Alexanderplatz', lat: 52.52, lon: 13.41),
    ]);

    await _pump(tester);

    expect(find.text('FAVOURITES'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Alexanderplatz'), findsOneWidget);
  });

  testWidgets('a renamed place shows both names, an unrenamed one shows one', (
    tester,
  ) async {
    await _keep([
      _favourite(id: 'a', name: 'Hauptbahnhof', label: 'Home'),
      _favourite(id: 'b', name: 'Alexanderplatz', lat: 52.52, lon: 13.41),
    ]);

    await _pump(tester);

    // The alias leads, the searched name sits under it.
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Hauptbahnhof'), findsOneWidget);
    // Nothing renamed here, so the name is not printed twice.
    expect(find.text('Alexanderplatz'), findsOneWidget);
  });

  testWidgets('an empty list says how to fill it', (tester) async {
    await _pump(tester);
    expect(find.text('Tap the heart on a place to keep it here.'), findsOne);
  });

  testWidgets('the map is offered as a way to answer', (tester) async {
    // Some places are easier to point at than to name.
    await _pump(tester);
    expect(find.text('Pick a point on the map'), findsOne);
  });

  testWidgets('the map picker is headed and confirmed for this search', (
    tester,
  ) async {
    // It used to open as "Add Favourite" with a "Save" button, whatever the
    // search was for.
    await _pump(tester);

    await tester.tap(find.text('Pick a point on the map'));
    await tester.pumpAndSettle();

    final picker = tester.widget<MapPlacePickerScreen>(
      find.byType(MapPlacePickerScreen),
    );
    expect(picker.title, 'Select Destination');
    expect(picker.confirmLabel, 'Select');
    expect(find.text('Add Favourite'), findsNothing);
  });

  testWidgets('the map is the row under the field, above the lists', (
    tester,
  ) async {
    // Pinned to the foot of the screen, the keyboard hid it.
    await _keep([_favourite(id: 'a', name: 'Hauptbahnhof', label: 'Home')]);
    await _pump(tester, showMyLocation: true);

    final field = tester.getRect(find.byType(CupertinoTextField));
    final myLocation = tester.getRect(find.text(myLocationName));
    final map = tester.getRect(find.text('Pick a point on the map'));
    final favourites = tester.getRect(find.text('FAVOURITES'));
    expect(map.top, greaterThan(field.bottom));
    expect(map.top, greaterThan(myLocation.bottom));
    expect(map.bottom, lessThan(favourites.top));
    expect(
      find.descendant(
        of: find.byType(CupertinoTextField),
        matching: find.byIcon(LucideIcons.mapPlus),
      ),
      findsNothing,
    );
  });

  testWidgets('clearing the query leaves the map on offer', (tester) async {
    await _pump(tester);

    await tester.enterText(find.byType(CupertinoTextField), 'Al');
    await tester.pump();

    expect(find.byIcon(LucideIcons.x), findsOne);
    expect(find.text('Pick a point on the map'), findsOne);
  });

  group('the map with results', () {
    setUp(() {
      TransitousClient.instance = TransitousClient(
        httpClient: MockClient(
          (_) async => http.Response(
            File('test/fixtures/transitous/geocode.json').readAsStringSync(),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
    });
    tearDown(() => TransitousClient.instance = TransitousClient());

    Future<void> search(WidgetTester tester) async {
      await tester.enterText(find.byType(EditableText), 'Alexanderplatz');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    }

    testWidgets('results are headed, under the way to the map', (tester) async {
      await _pump(tester);
      await search(tester);

      final map = tester.getRect(find.text('Show results on map'));
      final heading = tester.getRect(find.text('SEARCH RESULTS'));
      final first = tester.getRect(find.text('Berlin Alexanderplatz').first);
      expect(map.bottom, lessThan(heading.top));
      expect(heading.bottom, lessThan(first.top));
    });

    testWidgets('once there are results, the map shows them', (tester) async {
      await _pump(tester, placeBias: const LatLng(52.52, 13.405));
      await search(tester);

      expect(find.text('Pick a point on the map'), findsNothing);
      await tester.tap(find.text('Show results on map'));
      await tester.pumpAndSettle();

      final picker = tester.widget<MapPlacePickerScreen>(
        find.byType(MapPlacePickerScreen),
      );
      expect(picker.title, 'Results for “Alexanderplatz”');
      expect(picker.results, isNotEmpty);
      expect(picker.results.first.name, 'Berlin Alexanderplatz');
      expect(picker.origin, const LatLng(52.52, 13.405));
      expect(picker.allowsPoint, isTrue);
      // To ask again from wherever the map is moved to.
      expect(picker.query, 'Alexanderplatz');
    });

    testWidgets('a timetable gets the map only for its results', (
      tester,
    ) async {
      await _pump(tester, type: 'STOP');
      expect(find.text('Pick a point on the map'), findsNothing);

      await search(tester);
      await tester.tap(find.text('Show results on map'));
      await tester.pumpAndSettle();

      final picker = tester.widget<MapPlacePickerScreen>(
        find.byType(MapPlacePickerScreen),
      );
      expect(picker.allowsPoint, isFalse);
    });
  });

  group('show more', () {
    late List<Uri> requests;

    /// Answers [available] distinct places, or as many as were asked for.
    void serve(int available, {bool failAfterFirst = false}) {
      requests = [];
      TransitousClient.instance = TransitousClient(
        httpClient: MockClient((request) async {
          requests.add(request.url);
          if (failAfterFirst && requests.length > 1) {
            return http.Response('{"error":"too many"}', 400);
          }
          final asked = int.parse(request.url.queryParameters['numResults']!);
          final count = asked < available ? asked : available;
          return http.Response(
            jsonEncode([
              for (var i = 0; i < count; i++)
                {
                  'type': 'PLACE',
                  'name': 'Lidl $i',
                  'id': 'node/[$i]',
                  'lat': 52.5 + i * 0.01,
                  'lon': 13.4,
                  'score': 0,
                  'areas': const [],
                  'tokens': const [],
                },
            ]),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
    }

    tearDown(() => TransitousClient.instance = TransitousClient());

    Future<void> search(WidgetTester tester) async {
      await tester.enterText(find.byType(EditableText), 'Lidl');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    }

    Future<void> tapMore(WidgetTester tester) async {
      await tester.scrollUntilVisible(
        find.text('Show more results'),
        200,
        scrollable: _resultList,
      );
      // A tap on a list still coasting only stops it.
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show more results'));
      await tester.pumpAndSettle();
    }

    testWidgets('a full page offers more, and more asks a page more', (
      tester,
    ) async {
      serve(100);
      await _pump(tester);
      await search(tester);

      expect(requests.single.queryParameters['numResults'], '20');
      await tapMore(tester);

      expect(requests.last.queryParameters['numResults'], '40');
      expect(requests.last.queryParameters['text'], 'Lidl');
      await tester.scrollUntilVisible(
        find.text('Lidl 39'),
        200,
        scrollable: _resultList,
      );
      expect(find.text('Lidl 39'), findsOne);
    });

    testWidgets('a short page is all there is', (tester) async {
      serve(12);
      await _pump(tester);
      await search(tester);

      expect(find.text('Show more results', skipOffstage: false), findsNothing);
    });

    testWidgets('stops offering at a hundred', (tester) async {
      serve(1000);
      await _pump(tester);
      await search(tester);
      for (var i = 0; i < 4; i++) {
        await tapMore(tester);
      }

      expect(requests.last.queryParameters['numResults'], '100');
      expect(find.text('Show more results', skipOffstage: false), findsNothing);
    });

    testWidgets('a failed "more" keeps what is listed', (tester) async {
      serve(100, failAfterFirst: true);
      await _pump(tester);
      await search(tester);
      await tapMore(tester);

      // The list is lazy: its last row is the one still built down here.
      expect(find.text('Lidl 19', skipOffstage: false), findsOne);
      expect(find.text('Show more results', skipOffstage: false), findsNothing);
    });

    testWidgets('a new query starts from one page again', (tester) async {
      serve(100);
      await _pump(tester);
      await search(tester);
      await tapMore(tester);

      await tester.enterText(find.byType(EditableText), 'Aldi');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(requests.last.queryParameters['numResults'], '20');
    });
  });

  testWidgets('a favourite offers its actions from the dots and a long hold', (
    tester,
  ) async {
    await _keep([_favourite(id: 'a', name: 'Hauptbahnhof')]);
    await _pump(tester);

    await tester.tap(find.bySemanticsLabel('Edit Hauptbahnhof'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Favourite'), findsOne);
    expect(find.text('Remove favourite'), findsOne);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Favourite'), findsNothing);

    // A long press lifts it to drag; held still past that, the menu opens.
    final gesture = await _press(
      tester,
      'Hauptbahnhof',
      past: const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();
    expect(find.text('Edit Favourite'), findsOne);
    await gesture.up();
  });

  testWidgets('renaming writes the alias and leaves the name alone', (
    tester,
  ) async {
    await _keep([_favourite(id: 'a', name: 'Hauptbahnhof')]);
    await _pump(tester);

    await tester.tap(find.bySemanticsLabel('Edit Hauptbahnhof'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).last, 'Home');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final stored = FavoritesService.favoritesListenable.value.single;
    expect(stored.label, 'Home');
    expect(stored.name, 'Hauptbahnhof');
    expect(stored.displayName, 'Home');
  });

  testWidgets('renaming a stop kept with its transport icon keeps the icon', (
    tester,
  ) async {
    // Its icon is not among the suggestions; saving a new name must not
    // take that as picking another.
    await _keep([_favourite(id: 'a', name: 'Hauptbahnhof', iconName: 'train')]);
    await _pump(tester);

    await tester.tap(find.bySemanticsLabel('Edit Hauptbahnhof'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).last, 'Work');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final stored = FavoritesService.favoritesListenable.value.single;
    expect(stored.label, 'Work');
    // The same icon, now under the name saves use from here on.
    expect(stored.iconName, 'lucide:train-front');
    expect(find.byIcon(LucideIcons.trainFront), findsOne);
  });

  group('opened on a filled field', () {
    late List<Uri> requests;
    setUp(() {
      requests = [];
      TransitousClient.instance = TransitousClient(
        httpClient: MockClient((request) async {
          requests.add(request.url);
          return http.Response(
            File('test/fixtures/transitous/geocode.json').readAsStringSync(),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
    });
    tearDown(() => TransitousClient.instance = TransitousClient());

    testWidgets('offers My Location, not results for the old answer', (
      tester,
    ) async {
      // Changing a filled origin to where you are is two taps, not three.
      await _pump(tester, showMyLocation: true, initialQuery: 'Berlin Hbf');
      await tester.pump(const Duration(seconds: 1));

      expect(find.text(myLocationName), findsOneWidget);
      expect(requests, isEmpty);
    });

    testWidgets('selects the text, so typing replaces it', (tester) async {
      await _pump(tester, initialQuery: 'Berlin Hbf');

      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.controller.selection.start, 0);
      expect(field.controller.selection.end, 'Berlin Hbf'.length);
    });

    testWidgets('searches once something new is typed', (tester) async {
      await _pump(tester, showMyLocation: true, initialQuery: 'Berlin Hbf');

      await tester.enterText(find.byType(EditableText), 'Alexanderplatz');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(requests.single.queryParameters['text'], 'Alexanderplatz');
      expect(find.text(myLocationName), findsNothing);
      expect(find.text('S+U Alexanderplatz Bhf (Berlin)'), findsOne);
    });

    testWidgets('an empty field still searches the first query', (
      tester,
    ) async {
      await _pump(tester);

      await tester.enterText(find.byType(EditableText), 'Alexanderplatz');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(requests, hasLength(1));
    });
  });

  testWidgets('My Location leads the list when it can answer', (tester) async {
    // Where you are is the commonest origin, and it is the one answer the
    // list can give without a search.
    await _keep([_favourite(id: 'a', name: 'Hauptbahnhof')]);
    await _pump(tester, showMyLocation: true);

    expect(find.text(myLocationName), findsOneWidget);

    final myLocation = tester.getRect(find.text(myLocationName));
    final favourite = tester.getRect(find.text('Hauptbahnhof'));
    expect(myLocation.top, lessThan(favourite.top));
  });

  testWidgets('a stop search does not offer it', (tester) async {
    // A coordinate is not a stop, so it could not answer a timetable.
    await _pump(tester);
    expect(find.text(myLocationName), findsNothing);
  });

  group('a stop search offers only stops', () {
    Future<void> keepBoth() async {
      await _keep([
        _favourite(id: 'a', name: 'Hauptbahnhof'),
        _favourite(
          id: 'b',
          name: 'Chausseestraße 12',
          type: 'ADDRESS',
          lat: 52.53,
          lon: 13.38,
        ),
      ]);
      await SavedPlacesService.savePlaces(
        bucket: SavedPlacesBucket.timetable,
        places: [
          SavedPlace(
            name: 'Ostkreuz',
            type: 'STOP',
            lat: 52.5,
            lon: 13.46,
            stopId: 'de-DELFI_de:11000:900120005',
            importance: SavedPlacesService.initialImportance,
          ),
          SavedPlace(
            name: 'Museumsinsel 2',
            type: 'ADDRESS',
            lat: 52.52,
            lon: 13.4,
            importance: SavedPlacesService.initialImportance,
          ),
        ],
      );
    }

    testWidgets('a favourite that is not a stop is left out', (tester) async {
      // Picking it could not answer a departure board, so offering it is a
      // dead end.
      await keepBoth();
      await _pump(tester, type: 'STOP', bucket: SavedPlacesBucket.timetable);

      expect(find.text('Hauptbahnhof'), findsOneWidget);
      expect(find.text('Chausseestraße 12'), findsNothing);
    });

    testWidgets('a recent that is not a stop is left out', (tester) async {
      await keepBoth();
      await _pump(tester, type: 'STOP', bucket: SavedPlacesBucket.timetable);

      expect(find.text('Ostkreuz'), findsOneWidget);
      expect(find.text('Museumsinsel 2'), findsNothing);
    });

    testWidgets('a route search still offers everything', (tester) async {
      // No type, so nothing is filtered — this is the picker the map screen
      // opens, where an address is a perfectly good answer.
      await _keep([
        _favourite(id: 'b', name: 'Chausseestraße 12', type: 'ADDRESS'),
      ]);
      await _pump(tester);

      expect(find.text('Chausseestraße 12'), findsOneWidget);
    });

    testWidgets('with no stop among the favourites it says so', (tester) async {
      await _keep([
        _favourite(id: 'b', name: 'Chausseestraße 12', type: 'ADDRESS'),
      ]);
      await _pump(tester, type: 'STOP', bucket: SavedPlacesBucket.timetable);

      expect(find.text('None of your favourites is a stop.'), findsOne);
    });
  });

  group('keeping a place from the lists', () {
    testWidgets('the heart on a recent keeps it without picking it', (
      tester,
    ) async {
      await _remember(SavedPlacesBucket.search, [
        _recent('Ostkreuz', modes: const [TransitMode.suburban]),
      ]);
      await _pump(tester);

      await tester.tap(find.bySemanticsLabel('Keep Ostkreuz'));
      await tester.pumpAndSettle();

      final kept = FavoritesService.favoritesListenable.value.single;
      expect(kept.name, 'Ostkreuz');
      expect(kept.stopId, 'de-DELFI_Ostkreuz');
      // Kept with the face the list drew it with.
      expect(kept.iconName, 'lucide:train-front');
      // Still here, not popped with an answer.
      expect(find.byType(LocationSearchScreen), findsOne);
    });

    testWidgets('a kept place moves up and is listed once', (tester) async {
      await _remember(SavedPlacesBucket.search, [_recent('Ostkreuz')]);
      await _pump(tester);
      expect(find.text('RECENT'), findsOne);

      await tester.tap(find.bySemanticsLabel('Keep Ostkreuz'));
      await tester.pumpAndSettle();

      expect(find.text('Ostkreuz'), findsOne);
      expect(find.text('RECENT'), findsNothing);
      final favouritesHeading = tester.getRect(find.text('FAVOURITES'));
      expect(
        tester.getRect(find.text('Ostkreuz')).top,
        greaterThan(favouritesHeading.top),
      );
    });

    testWidgets('letting a favourite go puts the recent back', (tester) async {
      await _remember(SavedPlacesBucket.search, [_recent('Ostkreuz')]);
      await _keep([_favourite(id: 'a', name: 'Ostkreuz', lon: 13.46)]);
      await _pump(tester);
      expect(find.text('RECENT'), findsNothing);

      await FavoritesService.removeFavorite('a');
      await tester.pumpAndSettle();

      expect(find.text('RECENT'), findsOne);
      expect(find.bySemanticsLabel('Keep Ostkreuz'), findsOne);
    });

    testWidgets('a place that is not a stop is kept with the pin', (
      tester,
    ) async {
      await _remember(SavedPlacesBucket.search, [
        _recent('Oranienstraße 25', type: 'ADDRESS'),
      ]);
      await _pump(tester);

      await tester.tap(find.bySemanticsLabel('Keep Oranienstraße 25'));
      await tester.pumpAndSettle();

      final kept = FavoritesService.favoritesListenable.value.single;
      expect(kept.type, 'ADDRESS');
      expect(kept.iconName, FavoritePlace.defaultIconName);
    });

    testWidgets('My Location has no heart', (tester) async {
      // Where you are moves; it is not a place to keep.
      await _pump(tester, showMyLocation: true);
      expect(find.bySemanticsLabel(RegExp('^Keep')), findsNothing);
    });

    group('from the search results', () {
      setUp(() {
        TransitousClient.instance = TransitousClient(
          httpClient: MockClient(
            (_) async => http.Response(
              File('test/fixtures/transitous/geocode.json').readAsStringSync(),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
          ),
        );
      });
      tearDown(() => TransitousClient.instance = TransitousClient());

      Future<void> search(WidgetTester tester) async {
        await tester.enterText(find.byType(EditableText), 'Alexanderplatz');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
      }

      testWidgets('a kept result reads kept, and letting it go empties it', (
        tester,
      ) async {
        // The coordinates the geocoder answers S+U Alexanderplatz with.
        await _keep([
          _favourite(
            id: 'a',
            name: 'S+U Alexanderplatz Bhf (Berlin)',
            lat: 52.521510000000006,
            lon: 13.411266999999999,
          ),
        ]);
        await _pump(tester);
        await search(tester);

        const name = 'S+U Alexanderplatz Bhf (Berlin)';
        expect(find.bySemanticsLabel('Remove $name from favourites'), findsOne);

        await tester.tap(find.bySemanticsLabel('Remove $name from favourites'));
        await tester.pumpAndSettle();

        expect(FavoritesService.favoritesListenable.value, isEmpty);
        expect(find.bySemanticsLabel('Keep $name'), findsOne);
      });

      testWidgets('results say how far, where, and which country abroad', (
        tester,
      ) async {
        // A phone set to Germany, standing near Alexanderplatz.
        tester.platformDispatcher.localeTestValue = const Locale('de', 'DE');
        addTearDown(tester.platformDispatcher.clearLocaleTestValue);
        await _pump(tester, placeBias: const LatLng(52.52, 13.405));
        await search(tester);

        // Berlin Alexanderplatz, 736 m off: at home, so no country.
        expect(find.text('740 m · Mitte, Berlin'), findsWidgets);
        // Chur has no district; its canton stands in, and it is abroad.
        expect(find.textContaining('Grisons, CH'), findsOne);
      });

      testWidgets('results are drawn by what serves them', (tester) async {
        await _pump(tester);
        await search(tester);

        // S+U Alexanderplatz: rail, and more.
        expect(find.byIcon(LucideIcons.trainFront), findsOne);
        // Chur and Idar: buses. The two long-distance coach stops.
        expect(find.byIcon(LucideIcons.busFront), findsNWidgets(2));
        expect(find.byIcon(LucideIcons.bus), findsNWidgets(2));
        // A stop the geocoder named nothing for.
        expect(find.byIcon(kUnknownStopIcon), findsOne);
      });
    });
  });

  testWidgets(
    'recents are drawn by what serves them, favourites their own way',
    (tester) async {
      await _keep([
        // A railway station, kept as home: the rider chose that face.
        _favourite(id: 'a', name: 'Ostbahnhof', lon: 13.43, iconName: 'home'),
      ]);
      await _remember(SavedPlacesBucket.search, [
        _recent(
          'Hauptbahnhof',
          lon: 13.36,
          modes: const [TransitMode.longDistance],
        ),
        _recent('Am Kupfergraben', lon: 13.39, modes: const [TransitMode.tram]),
        _recent('Warschauer', lon: 13.44),
      ]);
      await _pump(tester);

      expect(find.byIcon(LucideIcons.house), findsOne);
      expect(find.byIcon(LucideIcons.trainFront), findsOne);
      expect(find.byIcon(LucideIcons.tramFront), findsOne);
      expect(find.byIcon(kUnknownStopIcon), findsOne);
    },
  );

  group('a stop search', () {
    testWidgets('lists a recent whose favourite it cannot open', (
      tester,
    ) async {
      // Kept before stop ids were recorded: Favourites leaves it out here,
      // so Recent must not.
      await _keep([
        _favourite(id: 'a', name: 'Ostkreuz', lon: 13.46, stopId: null),
      ]);
      await _remember(SavedPlacesBucket.timetable, [_recent('Ostkreuz')]);
      await _pump(tester, type: 'STOP', bucket: SavedPlacesBucket.timetable);

      expect(find.text('RECENT'), findsOne);
      expect(find.bySemanticsLabel('Keep Ostkreuz'), findsOne);
    });

    testWidgets('keeping that recent fills the id in, not a second one', (
      tester,
    ) async {
      await _keep([
        _favourite(id: 'a', name: 'Ostkreuz', lon: 13.46, stopId: null),
      ]);
      await _remember(SavedPlacesBucket.timetable, [_recent('Ostkreuz')]);
      await _pump(tester, type: 'STOP', bucket: SavedPlacesBucket.timetable);

      await tester.tap(find.bySemanticsLabel('Keep Ostkreuz'));
      await tester.pumpAndSettle();

      final kept = FavoritesService.favoritesListenable.value.single;
      expect(kept.id, 'a');
      expect(kept.stopId, 'de-DELFI_Ostkreuz');
      expect(find.text('RECENT'), findsNothing);
    });
  });

  group('reordering favourites', () {
    Future<void> keepThree() => _keep([
      _favourite(id: 'a', name: 'Alpha', lon: 13.1),
      _favourite(id: 'b', name: 'Bravo', lon: 13.2),
      _favourite(id: 'c', name: 'Charlie', lon: 13.3),
    ]);

    testWidgets('a favourite is dragged into a new order', (tester) async {
      await keepThree();
      await _pump(tester);

      // Rows are 56 high: past Bravo's middle, short of Charlie's.
      await _drag(tester, 'Alpha', 70);

      expect(_storedOrder(), ['b', 'a', 'c']);
      final bravo = tester.getRect(find.text('Bravo')).top;
      expect(tester.getRect(find.text('Alpha')).top, greaterThan(bravo));
    });

    testWidgets('dragged up as well as down', (tester) async {
      await keepThree();
      await _pump(tester);

      await _drag(tester, 'Charlie', -126);

      expect(_storedOrder(), ['c', 'a', 'b']);
    });

    testWidgets('in a stop search, what it hides keeps its place', (
      tester,
    ) async {
      await _keep([
        _favourite(id: 'a', name: 'Alpha', lon: 13.1),
        _favourite(id: 'x', name: 'An address', type: 'ADDRESS', lon: 13.5),
        _favourite(id: 'b', name: 'Bravo', lon: 13.2),
      ]);
      await _pump(tester, type: 'STOP', bucket: SavedPlacesBucket.timetable);

      await _drag(tester, 'Alpha', 70);

      expect(_storedOrder(), ['b', 'x', 'a']);
    });

    testWidgets('held still, a favourite opens its menu and stays put', (
      tester,
    ) async {
      await keepThree();
      await _pump(tester);

      final gesture = await _press(
        tester,
        'Alpha',
        past: const Duration(milliseconds: 600),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Edit Favourite'), findsOne);

      // What the finger does after the menu opens is not a drag.
      await gesture.moveBy(const Offset(0, 120));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_storedOrder(), ['a', 'b', 'c']);
    });

    testWidgets('let go after the lift, it is only a lift', (tester) async {
      await keepThree();
      await _pump(tester);

      final gesture = await _press(tester, 'Alpha');
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Edit Favourite'), findsNothing);
      expect(_storedOrder(), ['a', 'b', 'c']);
    });

    testWidgets('moving after the lift is a drag, never the menu', (
      tester,
    ) async {
      await keepThree();
      await _pump(tester);

      final gesture = await _press(tester, 'Alpha');
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Edit Favourite'), findsNothing);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a screen reader moves one without dragging', (tester) async {
      final semantics = tester.ensureSemantics();
      await keepThree();
      await _pump(tester);

      tester.semantics.customAction(
        find.semantics.byLabel(RegExp('^Alpha')),
        const CustomSemanticsAction(label: 'Move down'),
      );
      await tester.pumpAndSettle();
      expect(_storedOrder(), ['b', 'a', 'c']);

      tester.semantics.customAction(
        find.semantics.byLabel(RegExp('^Charlie')),
        const CustomSemanticsAction(label: 'Move up'),
      );
      await tester.pumpAndSettle();
      expect(_storedOrder(), ['b', 'c', 'a']);

      // Nowhere past the ends to go.
      expect(
        tester.getSemantics(find.text('Bravo')),
        isNot(
          containsSemantics(
            customActions: [const CustomSemanticsAction(label: 'Move up')],
          ),
        ),
      );
      semantics.dispose();
    });
  });
}
