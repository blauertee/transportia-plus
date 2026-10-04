import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/providers/theme_provider.dart';
import 'package:transportia/services/place_bias_service.dart';
import 'package:transportia/utils/place_bias.dart';
import 'package:transportia/widgets/app_toggle_switch.dart';
import 'package:transportia/widgets/place_search_location_toggle.dart';

Future<void> _pump(WidgetTester tester, {double? stored}) async {
  SharedPreferencesAsyncPlatform.instance = stored == null
      ? InMemorySharedPreferencesAsync.empty()
      : InMemorySharedPreferencesAsync.withData({'place_bias': stored});
  PlaceBiasService.invalidate();
  if (stored != null) await tester.runAsync(PlaceBiasService.load);

  tester.view.physicalSize = const Size(900, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeProvider>(
      create: (_) => ThemeProvider(),
      child: const Directionality(
        textDirection: TextDirection.ltr,
        child: PlaceSearchLocationToggle(),
      ),
    ),
  );
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump();
}

bool _isOn(WidgetTester tester) =>
    tester.widget<AppToggleSwitch>(find.byType(AppToggleSwitch)).value;

/// Taps the switch and lets the stored value settle.
Future<void> _tap(WidgetTester tester) async {
  await tester.tap(find.byType(AppToggleSwitch));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('on for someone who never touched it, as before', (tester) async {
    await _pump(tester);

    expect(_isOn(tester), isTrue);
    expect(PlaceBiasService.biasListenable.value, PlaceBias.defaultValue);
  });

  testWidgets('shows off when the slider was already at Off', (tester) async {
    await _pump(tester, stored: PlaceBias.off);

    expect(_isOn(tester), isFalse);
    expect(find.textContaining('not sent'), findsOneWidget);
  });

  testWidgets('switching off stores the slider\'s Off', (tester) async {
    await _pump(tester);

    await _tap(tester);

    expect(_isOn(tester), isFalse);
    expect(PlaceBias.isOff(PlaceBiasService.biasListenable.value), isTrue);
    final stored = await tester.runAsync(
      () => SharedPreferencesAsync().getDouble('place_bias'),
    );
    expect(stored, PlaceBias.off);
  });

  testWidgets('switching back on restores the default', (tester) async {
    await _pump(tester);

    await _tap(tester);
    await _tap(tester);

    expect(_isOn(tester), isTrue);
    expect(PlaceBiasService.biasListenable.value, PlaceBias.defaultValue);
    final hasKey = await tester.runAsync(
      () => SharedPreferencesAsync().containsKey('place_bias'),
    );
    // The default is stored as nothing, as the slider does.
    expect(hasKey, isFalse);
  });

  testWidgets('switching back on restores a strength chosen on the slider', (
    tester,
  ) async {
    await _pump(tester, stored: 3.5);

    await _tap(tester);
    expect(_isOn(tester), isFalse);
    await _tap(tester);

    expect(PlaceBiasService.biasListenable.value, 3.5);
  });

  testWidgets('follows the slider moving it while on screen', (tester) async {
    await _pump(tester);

    await tester.runAsync(() => PlaceBiasService.save(PlaceBias.off));
    await tester.pump();

    expect(_isOn(tester), isFalse);
  });
}
