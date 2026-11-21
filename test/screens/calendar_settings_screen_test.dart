import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oktoast/oktoast.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/models/device_calendar.dart';
import 'package:transportia/models/itinerary.dart';
import 'package:transportia/models/saved_trip.dart';
import 'package:transportia/models/time_selection.dart';
import 'package:transportia/providers/theme_provider.dart';
import 'package:transportia/screens/calendar_settings_screen.dart';
import 'package:transportia/screens/settings_screen.dart';
import 'package:transportia/services/calendar_sync_service.dart';
import 'package:transportia/services/saved_trips_service.dart';
import 'package:transportia/widgets/app_toggle_switch.dart';
import 'package:transportia/widgets/overlay_dialog.dart';

import '../support/fake_calendar_bridge.dart';
import '../support/plan_fixtures.dart';

/// Android's answers about the calendar permission, scripted.
class _FakePermission extends CalendarPermission {
  _FakePermission({required this.answer});

  /// What asking returns, and what the permission is from then on.
  final CalendarAccess answer;
  CalendarAccess current = CalendarAccess.denied;
  int settingsOpened = 0;

  @override
  Future<CalendarAccess> status() async => current;

  @override
  Future<CalendarAccess> request() async => current = answer;

  @override
  Future<void> openSettings() async => settingsOpened++;
}

const _nextcloud = DeviceCalendar(
  id: 7,
  name: 'Trips',
  accountName: 'me@cloud.example.org',
  accountType: 'bitfire.at.davdroid',
  color: 0xFF8E5BD0,
);

/// Far enough ahead to stay upcoming.
final _departure = DateTime(2030, 3, 4, 8, 15);

SavedTrip _trip() => SavedTrip.fromItinerary(
  itinerary: Itinerary.fromJson(planItineraryJson(departure: _departure)),
  timeSelection: TimeSelection(dateTime: _departure, isArriveBy: false),
);

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeProvider>(
      create: (_) => ThemeProvider(),
      child: OKToast(child: CupertinoApp(home: screen)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapToggle(WidgetTester tester) async {
  await tester.tap(find.byType(AppToggleSwitch));
  await tester.pumpAndSettle();
}

/// Lets a toast run out, so no timer outlives the test. Toasts are shown
/// for a day and closed early, and the day's timer still runs.
Future<void> _outlastToast(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(days: 2));
}

void main() {
  late FakeCalendarBridge bridge;
  late _FakePermission permission;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SavedTripsService.savedTripsListenable.value = const [];
    bridge = FakeCalendarBridge(calendars: [_nextcloud]);
    permission = _FakePermission(answer: CalendarAccess.granted);
    CalendarSyncService.bridge = bridge;
    CalendarSyncService.hasAccess = () async =>
        permission.current == CalendarAccess.granted;
  });

  testWidgets('is off to begin with, and says what it would do', (
    tester,
  ) async {
    await _pump(tester, CalendarSettingsScreen(permission: permission));

    expect(find.text('Off: saved trips stay in the app'), findsOne);
    expect(find.text('Saved trips go to'), findsNothing);
    expect(find.textContaining('Only trips you save'), findsOne);
  });

  testWidgets('switching on asks, then uses the app\'s own calendar', (
    tester,
  ) async {
    await _pump(tester, CalendarSettingsScreen(permission: permission));
    await _tapToggle(tester);

    expect(find.text('On, saved trips go to Transportia+'), findsOne);
    expect(find.text('Saved trips go to'), findsOne);
    // Nothing saved yet, so nothing to make a calendar for.
    expect(bridge.calendars.values.where((c) => c.isLocal), isEmpty);
  });

  testWidgets('a refusal leaves it off', (tester) async {
    permission = _FakePermission(answer: CalendarAccess.denied);
    await _pump(tester, CalendarSettingsScreen(permission: permission));
    await _tapToggle(tester);

    expect(find.text('Off: saved trips stay in the app'), findsOne);
    expect(find.text('Calendar access was not allowed'), findsOne);
    expect(bridge.calls, isEmpty);
    await _outlastToast(tester);
  });

  testWidgets('a lasting refusal points to Android\'s settings', (
    tester,
  ) async {
    permission = _FakePermission(answer: CalendarAccess.permanentlyDenied);
    await _pump(tester, CalendarSettingsScreen(permission: permission));
    await _tapToggle(tester);

    expect(find.text('Calendar access is off'), findsOne);
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    expect(permission.settingsOpened, 1);
  });

  testWidgets('access revoked while on shows as off, with the way back', (
    tester,
  ) async {
    await CalendarSyncService.enable(const []);
    permission.current = CalendarAccess.denied;
    await _pump(tester, CalendarSettingsScreen(permission: permission));

    expect(find.text('Off: calendar access is turned off'), findsOne);
    expect(find.text('Calendar access is off'), findsOne);
  });

  testWidgets('switching on adds the trips already saved, unasked', (
    tester,
  ) async {
    await SavedTripsService.saveTrip(_trip());
    await _pump(tester, CalendarSettingsScreen(permission: permission));
    await _tapToggle(tester);

    expect(find.byType(OverlayDialogCard), findsNothing);
    expect(bridge.events, hasLength(1));
    expect(bridge.calendars.values.where((c) => c.isLocal), hasLength(1));
  });

  testWidgets('switching off can remove the app\'s own calendar', (
    tester,
  ) async {
    permission.current = CalendarAccess.granted;
    await CalendarSyncService.enable([_trip()]);
    await _pump(tester, CalendarSettingsScreen(permission: permission));
    await _tapToggle(tester);

    expect(find.text('Remove the calendar?'), findsOne);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.text('Off: saved trips stay in the app'), findsOne);
    expect(bridge.calendars.values.where((c) => c.isLocal), isEmpty);
  });

  testWidgets('switching off with nothing added asks nothing', (tester) async {
    permission.current = CalendarAccess.granted;
    await CalendarSyncService.enable(const []);
    await _pump(tester, CalendarSettingsScreen(permission: permission));
    await _tapToggle(tester);

    expect(find.byType(OverlayDialogCard), findsNothing);
    expect(find.text('Off: saved trips stay in the app'), findsOne);
  });

  testWidgets('picking another calendar takes the trips along, unasked', (
    tester,
  ) async {
    permission.current = CalendarAccess.granted;
    await SavedTripsService.saveTrip(_trip());
    await CalendarSyncService.enable(await SavedTripsService.getSavedTrips());
    await _pump(tester, CalendarSettingsScreen(permission: permission));

    await tester.tap(find.text('Saved trips go to'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a calendar'), findsOne);
    await tester.tap(find.text('Trips'));
    await tester.pumpAndSettle();

    expect(find.byType(OverlayDialogCard), findsNothing);
    expect(find.text('On, saved trips go to Trips'), findsOne);
    expect(bridge.eventsIn(_nextcloud.id), hasLength(1));
    expect(bridge.calendars.values.where((c) => c.isLocal), isEmpty);
  });

  testWidgets('settings lists it under Synchronization', (tester) async {
    await _pump(tester, const SettingsScreen());

    expect(find.text('SYNCHRONIZATION'), findsOne);
    expect(find.text(CalendarSettingsScreen.title), findsOne);
  });
}
