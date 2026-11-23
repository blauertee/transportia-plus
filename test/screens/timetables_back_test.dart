import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/navigation/back_step.dart';
import 'package:transportia/providers/theme_provider.dart';
import 'package:transportia/screens/timetables_screen.dart';
import 'package:transportia/services/favorites_service.dart';
import 'package:transportia/services/transitous_geocode_service.dart';
import 'package:transportia/widgets/nearby_departures_section.dart';

const String _kStopName = 'Alexanderplatz';

TransitousLocationSuggestion _stop() => TransitousLocationSuggestion(
  id: 'stop-alex',
  name: _kStopName,
  lat: 52.5219,
  lon: 13.4132,
  type: 'STOP',
  stopId: 'de-DELFI_de:11000:900100003',
);

NearbySectionBuilder _noNearby(LatLng? center) =>
    (buildRow, buildMessage) => const SizedBox.shrink();

/// The Timetables tab inside a shell whose own step stands for going back
/// to the routing tab.
class _Shell extends StatefulWidget {
  const _Shell({required this.stop, required this.isOpen});

  final TransitousLocationSuggestion? stop;
  final bool isOpen;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int backToRouting = 0;

  @override
  Widget build(BuildContext context) => BackStep(
    canStepBack: true,
    onStepBack: () => setState(() => backToRouting++),
    child: TimetablesScreen(
      initialStop: widget.stop,
      isOpen: widget.isOpen,
      buildNearby: _noNearby,
    ),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  TransitousLocationSuggestion? stop,
  bool isOpen = true,
}) async {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('flutter.baseflow.com/permissions/methods'),
    (call) async => switch (call.method) {
      'checkPermissionStatus' => 0,
      'requestPermissions' => <int, int>{},
      _ => null,
    },
  );
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeProvider>(
      create: (_) => ThemeProvider(),
      child: CupertinoApp(
        home: _Shell(stop: stop, isOpen: isOpen),
      ),
    ),
  );
  // The departures are asked for after the first frame; the request never
  // gets an answer here, which leaves the stop picked and loading.
  await tester.pump();
  await tester.pump();
}

/// Back, then a frame: steps are instant.
Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pump();
}

int _backToRouting(WidgetTester tester) =>
    tester.state<_ShellState>(find.byType(_Shell)).backToRouting;

void main() {
  setUp(() => FavoritesService.favoritesListenable.value = const []);

  testWidgets('back clears a picked stop before it leaves the tab', (
    tester,
  ) async {
    await _pump(tester, stop: _stop());
    expect(find.text(_kStopName), findsWidgets);

    await _back(tester);

    expect(find.text(_kStopName), findsNothing);
    expect(_backToRouting(tester), 0, reason: 'still on Timetables');

    await _back(tester);

    expect(_backToRouting(tester), 1);
  });

  testWidgets('with no stop picked, back leaves the tab at once', (
    tester,
  ) async {
    await _pump(tester);

    await _back(tester);

    expect(_backToRouting(tester), 1);
  });

  testWidgets('back puts the keyboard away before it clears the stop', (
    tester,
  ) async {
    await _pump(tester, stop: _stop());
    // The stop's own field, above its departures. Read-only, so focused
    // directly rather than by a tap.
    final focus = tester
        .widget<CupertinoTextField>(
          find.byWidgetPredicate(
            (widget) => widget is CupertinoTextField && widget.readOnly,
          ),
        )
        .focusNode!;
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);

    await _back(tester);

    expect(focus.hasFocus, isFalse);
    expect(find.text(_kStopName), findsWidgets, reason: 'stop kept');
    expect(_backToRouting(tester), 0);
  });

  testWidgets('while another tab is showing, its back does not touch the '
      'stop', (tester) async {
    await _pump(tester, stop: _stop(), isOpen: false);

    await _back(tester);

    expect(find.text(_kStopName), findsWidgets);
    expect(_backToRouting(tester), 1);
  });
}
