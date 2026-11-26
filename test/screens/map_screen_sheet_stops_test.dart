import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/providers/theme_provider.dart';
import 'package:transportia/screens/map_screen.dart';
import 'package:transportia/widgets/floating_nav_bar.dart';
import 'package:transportia/widgets/route_bottom_card.dart';

/// Literal, as a released build will have written it.
const String _searchMapEnabled = 'search_map_enabled';

const double _kStatusBar = 24;
const Size _kPhone = Size(400, 860);
const Size _kSmallPhone = Size(360, 640);

/// The map asks the platform for a native view, which a test cannot make.
/// Left pending, its area stays blank and the card draws over it as usual.
void _leaveMapPending(WidgetTester tester) {
  const channel = SystemChannels.platform_views;
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    channel,
    (call) => call.method == 'create'
        ? Completer<Object?>().future
        : Future<Object?>.value(),
  );
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpOverMap(WidgetTester tester, Size size) async {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.withData({_searchMapEnabled: true});
  _leaveMapPending(tester);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: _kStatusBar);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);

  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeProvider>(
      create: (_) => ThemeProvider(),
      child: WidgetsApp(
        color: const Color(0xFF000000),
        localizationsDelegates: const [
          DefaultWidgetsLocalizations.delegate,
          DefaultCupertinoLocalizations.delegate,
        ],
        onGenerateRoute: (settings) => PageRouteBuilder<void>(
          settings: settings,
          // Deferred, so the screen does not ask for the location on its own.
          pageBuilder: (_, _, _) => const MapScreen(deferInit: true),
        ),
      ),
    ),
  );
  await _settle(tester);
}

double _cardTop(WidgetTester tester) =>
    tester.getRect(find.byType(BottomCard)).top;

/// Drags the card's body up by [dy], slowly enough not to be a fling.
Future<void> _dragBodyUp(WidgetTester tester, double dy) async {
  final body = find.descendant(
    of: find.byType(BottomCard),
    matching: find.byType(SingleChildScrollView),
  );
  final gesture = await tester.startGesture(
    tester.getRect(body.first).topCenter + const Offset(0, 60),
  );
  const steps = 20;
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(Offset(0, -dy / steps));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pump(const Duration(milliseconds: 200));
  await gesture.up();
  await _settle(tester);
}

SystemUiOverlayStyle _statusBar(WidgetTester tester) => tester
    .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
    )
    .value;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('on a phone with room, the card rests with the map keeping a '
      'quarter', (tester) async {
    await _pumpOverMap(tester, _kPhone);

    expect(_cardTop(tester), _kPhone.height / 4);
  });

  testWidgets('where a quarter would hide Search under the nav bar, the card '
      'rests higher, below the status bar', (tester) async {
    await _pumpOverMap(tester, _kSmallPhone);

    final search = tester.getRect(find.text('Search'));
    expect(
      search.bottom,
      lessThanOrEqualTo(_kSmallPhone.height - FloatingNavBar.reservedHeight),
      reason: 'Search is under the nav bar',
    );
    expect(_cardTop(tester), lessThan(_kSmallPhone.height / 4));
    expect(_cardTop(tester), greaterThanOrEqualTo(_kStatusBar));
  });

  testWidgets('dragging the body up raises the card to just below the status '
      'bar, never under it', (tester) async {
    await _pumpOverMap(tester, _kPhone);

    await _dragBodyUp(tester, 500);

    expect(_cardTop(tester), _kStatusBar);
  });

  testWidgets('raised, the map behind is dimmed, so the status bar turns '
      'light', (tester) async {
    await _pumpOverMap(tester, _kPhone);
    expect(_statusBar(tester).statusBarIconBrightness, Brightness.dark);

    await _dragBodyUp(tester, 500);

    expect(_statusBar(tester).statusBarIconBrightness, Brightness.light);
  });

  testWidgets('back lowers a raised card to where it rests', (tester) async {
    await _pumpOverMap(tester, _kPhone);
    await _dragBodyUp(tester, 500);

    await tester.binding.handlePopRoute();
    await _settle(tester);

    expect(_cardTop(tester), _kPhone.height / 4);
  });
}
