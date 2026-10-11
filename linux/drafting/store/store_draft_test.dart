// Store screenshots for fastlane: a heading over a scaled phone showing one
// widget, rendered from the captured Transitous responses in data/. Run it
// through render_store.sh, which renders the map backgrounds (MapLibre draws
// nothing in a test) and moves the capture to today; see README.md.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:transportia/api/transitous_client.dart';
import 'package:transportia/models/itinerary.dart';
import 'package:transportia/models/routing_options.dart';
import 'package:transportia/models/time_selection.dart';
import 'package:transportia/models/transitous/server_config.dart';
import 'package:transportia/screens/itinerary_detail_screen.dart';
import 'package:transportia/screens/itinerary_list_screen.dart';
import 'package:transportia/screens/itinerary_map_screen.dart';
import 'package:transportia/screens/location_search_screen.dart';
import 'package:transportia/services/favorites_service.dart';
import 'package:transportia/services/saved_places_service.dart';
import 'package:transportia/widgets/route_bottom_card.dart';

import '../draft_kit.dart';

final String _data = Platform.environment['STORE_DATA']!;
final String _maps = Platform.environment['STORE_MAPS']!;

const Size _kCanvas = Size(480, 1071);
const Size _kPhone = Size(400, 860);
const double _kPhoneScale = 0.96;
const double _kPhoneTop = 250;
const Color _kBackground = Color(0xFF007185);

// Itineraries of data/plan.json, and the legs the map images focus on. The
// map entries in render_store.sh name the same ones.
const int _kTrainOnly = 0;
const int _kViaParis = 4;
const int _kBercyWalk = 12;

Map<String, dynamic> _json(String name) =>
    jsonDecode(File('$_data/$name').readAsStringSync()) as Map<String, dynamic>;

Itinerary _itinerary(int index) => Itinerary.fromJson(
  (_json('plan.json')['itineraries'] as List)[index] as Map<String, dynamic>,
);

void _mockTransitous() {
  final client = MockClient((request) async {
    final path = request.url.path;
    String? file;
    if (path.endsWith('/plan')) file = 'plan.json';
    if (path.endsWith('/geocode')) file = 'geocode_decathlon.json';
    if (file == null) return http.Response('{}', 404);
    return http.Response.bytes(
      File('$_data/$file').readAsBytesSync(),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
  TransitousClient.instance = TransitousClient(httpClient: client);
}

/// The store image: [heading] on the brand colour, the phone below it,
/// running off the bottom edge.
class StoreFrame extends StatelessWidget {
  const StoreFrame({super.key, required this.heading, required this.phone});

  final String heading;
  final Widget phone;

  @override
  Widget build(BuildContext context) {
    final phoneWidth = _kPhone.width * _kPhoneScale;
    return ColoredBox(
      color: _kBackground,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            left: 36,
            right: 36,
            top: 64,
            height: _kPhoneTop - 64 - 24,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                heading,
                style: const TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 38,
                  height: 1.12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFFFFFFF),
                  letterSpacing: -0.6,
                ),
              ),
            ),
          ),
          Positioned(
            left: (_kCanvas.width - phoneWidth) / 2,
            top: _kPhoneTop,
            width: phoneWidth,
            height: _kPhone.height * _kPhoneScale,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(34),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x55000000),
                    blurRadius: 30,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(34),
                child: FittedBox(
                  fit: BoxFit.fill,
                  child: SizedBox.fromSize(
                    size: _kPhone,
                    child: MediaQuery(
                      data: MediaQueryData(
                        size: _kPhone,
                        padding: const EdgeInsets.only(top: 24),
                        viewPadding: const EdgeInsets.only(top: 24),
                      ),
                      child: Navigator(
                        onGenerateRoute: (settings) => PageRouteBuilder<void>(
                          settings: settings,
                          pageBuilder: (_, _, _) => ColoredBox(
                            color: const Color(0xFFFFFFFF),
                            child: phone,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<ui.Image> _map(WidgetTester tester, String name) async =>
    (await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(
        File('$_maps/$name').readAsBytesSync(),
      );
      return (await codec.getNextFrame()).image;
    }))!;

/// Where the journey map starts below its app bar, measured on the screen.
final ValueNotifier<double> _mapTop = ValueNotifier(0);

Widget _overMap(ui.Image map, Widget child) => Stack(
  children: [
    ValueListenableBuilder<double>(
      valueListenable: _mapTop,
      builder: (_, top, _) => Positioned.fill(
        top: top,
        child: RawImage(image: map, fit: BoxFit.cover),
      ),
    ),
    Positioned.fill(child: child),
  ],
);

class _SearchCard extends StatefulWidget {
  const _SearchCard();

  @override
  State<_SearchCard> createState() => _SearchCardState();
}

class _SearchCardState extends State<_SearchCard> {
  final fromCtrl = TextEditingController(text: 'Little Snoring');
  final toCtrl = TextEditingController(text: 'Prague');

  @override
  Widget build(BuildContext context) {
    final options = RoutingOptions.defaults.copyWith(
      firstMileModes: const [TransitMode.bike],
      maxFirstMileTime: const Duration(minutes: 30),
    );
    // No drag handle: the card as the whole page, as with the map turned off.
    return BottomCard(
      isCollapsed: false,
      fromCtrl: fromCtrl,
      toCtrl: toCtrl,
      onUnfocus: () {},
      onSwapRequested: () {},
      options: options,
      storedOptions: options,
      capabilities: ServerConfig.fallback,
      onOptionsChanged: (_) {},
      onResetOptions: () {},
      onSaveOptionsAsDefault: () {},
      onAddViaStop: () {},
      onFromPressed: () {},
      onToPressed: () {},
      routeFieldLink: LayerLink(),
      fromLoading: false,
      toLoading: false,
      onSearch: (_) {},
      timeSelectionLayerLink: LayerLink(),
      onTimeSelectionTap: () {},
      timeSelection: TimeSelection.now(),
      recentTrips: const [],
      onRecentTripTap: (_) {},
    );
  }
}

/// The journey map paints white under its map, where a device shows tiles;
/// clear it so the rendered map behind the screen shows through.
Future<void> _clearMapBackground(WidgetTester tester) async {
  final box = tester.renderObject(
    find
        .descendant(
          of: find.byType(ItineraryMapScreen),
          matching: find.byType(ColoredBox),
        )
        .first,
  );
  (box as dynamic).color = const Color(0x00000000);
  final screen = tester.getRect(find.byType(ItineraryMapScreen));
  final map = tester.getRect(find.byType(MapLibreMap));
  _mapTop.value = (map.top - screen.top) * _kPhone.height / screen.height;
  await tester.pump();
}

Future<void> _shoot(
  WidgetTester tester,
  String name,
  String heading,
  Widget phone, {
  Future<void> Function()? before,
}) async {
  await pumpDraft(
    tester,
    StoreFrame(heading: heading, phone: phone),
    size: _kCanvas,
  );
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  if (before != null) await before();
  await tester.pump(const Duration(seconds: 1));
  await saveDraft(tester, name);
}

void main() {
  setUpAll(loadDraftFonts);
  setUp(() {
    _mapTop.value = 0;
    resetDraftStorage();
    FavoritesService.favoritesListenable.value = const [];
    _mockTransitous();
  });

  testWidgets('1 search', (tester) async {
    await _shoot(
      tester,
      '1',
      'Rome to Rio? How about Little Snoring to Prague?',
      const SafeArea(child: _SearchCard()),
      before: () async {
        await tester.tap(find.text('TO THE STATION'));
        await tester.pump(const Duration(seconds: 1));
      },
    );
  });

  testWidgets('2 results', (tester) async {
    await _shoot(
      tester,
      '2',
      'Coach from Brussels to Prague, or train only?',
      ItineraryListScreen(
        fromLat: 52.87,
        fromLon: 0.918,
        toLat: 50.0833,
        toLon: 14.4231,
        timeSelection: TimeSelection.now(),
        options: RoutingOptions.defaults.copyWith(
          firstMileModes: const [TransitMode.bike],
        ),
      ),
    );
  });

  testWidgets('3 timeline', (tester) async {
    await _shoot(
      tester,
      '3',
      'Where do I change, and how long do I have?',
      ItineraryDetailScreen(
        itinerary: _itinerary(_kTrainOnly),
        fromName: 'Little Snoring',
        toName: 'Prague',
      ),
    );
  });

  testWidgets('4 transfer', (tester) async {
    await _shoot(
      tester,
      '4',
      'Métro to the Paris coach: which way?',
      _overMap(
        await _map(tester, 'transfer.png'),
        ItineraryMapScreen(
          itinerary: _itinerary(_kViaParis),
          initialLegIndex: _kBercyWalk,
        ),
      ),
      before: () => _clearMapBackground(tester),
    );
  });

  testWidgets('5 bike', (tester) async {
    await _shoot(
      tester,
      '5',
      'Can I cycle to the first bus?',
      _overMap(
        await _map(tester, 'bike.png'),
        ItineraryMapScreen(
          itinerary: _itinerary(_kTrainOnly),
          initialLegIndex: 0,
        ),
      ),
      before: () => _clearMapBackground(tester),
    );
  });

  testWidgets('6 places', (tester) async {
    await _shoot(
      tester,
      '6',
      "Where's the nearest Decathlon in Prague?",
      const LocationSearchScreen(
        title: 'Search',
        bucket: SavedPlacesBucket.search,
        placeBias: LatLng(50.0833, 14.4231),
      ),
      before: () async {
        await tester.enterText(find.byType(EditableText).first, 'Decathlon');
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
      },
    );
  });
}
