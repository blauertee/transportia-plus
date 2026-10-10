import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/providers/theme_provider.dart';
import 'package:transportia/widgets/gtfs_fields_row.dart';

/// A provider that has read its settings. Storage is real async work, so it
/// runs outside the test's fake clock.
Future<ThemeProvider> _loaded(WidgetTester tester, {bool gtfs = false}) async {
  final provider = (await tester.runAsync(() async {
    final provider = ThemeProvider();
    while (!provider.isInitialized) {
      await Future<void>.delayed(Duration.zero);
    }
    if (gtfs) await provider.setShowGtfsFields(true);
    return provider;
  }))!;
  return provider;
}

Widget _host(ThemeProvider provider, Map<String, String?> fields) =>
    ChangeNotifierProvider<ThemeProvider>.value(
      value: provider,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: GtfsFieldsRow(fields: fields),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('prints nothing while the setting is off', (tester) async {
    final provider = await _loaded(tester);

    await tester.pumpWidget(_host(provider, {'trip': 'abc'}));

    expect(find.byType(Text), findsNothing);
  });

  testWidgets('joins the fields that have a value', (tester) async {
    final provider = await _loaded(tester, gtfs: true);

    await tester.pumpWidget(
      _host(provider, {'trip': 'abc', 'from stop': null, 'to stop': ''}),
    );

    expect(find.text('trip: abc'), findsOneWidget);
  });

  testWidgets('prints nothing when no field has a value', (tester) async {
    final provider = await _loaded(tester, gtfs: true);

    await tester.pumpWidget(_host(provider, {'trip': null, 'stop': ''}));

    expect(find.byType(Text), findsNothing);
  });

  testWidgets('follows the setting while on screen', (tester) async {
    final provider = await _loaded(tester);
    await tester.pumpWidget(_host(provider, {'trip': 'abc'}));
    expect(find.byType(Text), findsNothing);

    await tester.runAsync(() => provider.setShowGtfsFields(true));
    await tester.pump();

    expect(find.text('trip: abc'), findsOneWidget);
  });
}
