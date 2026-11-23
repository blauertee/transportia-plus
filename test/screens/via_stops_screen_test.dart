import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/models/routing_options.dart';
import 'package:transportia/navigation/routes.dart';
import 'package:transportia/providers/theme_provider.dart';
import 'package:transportia/screens/via_stops_screen.dart';

const RoutingOptions _kTwoStops = RoutingOptions(
  via: [
    ViaStopOption(stopId: 'de:1', name: 'Ostkreuz'),
    ViaStopOption(stopId: 'de:2', name: 'Südkreuz'),
  ],
);

Future<List<RoutingOptions>> _open(WidgetTester tester) async {
  final changes = <RoutingOptions>[];
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeProvider>(
      create: (_) => ThemeProvider(),
      child: const CupertinoApp(home: Text('Routing')),
    ),
  );
  tester
      .state<NavigatorState>(find.byType(Navigator))
      .openScreen<void>(
        ViaStopsScreen(options: _kTwoStops, onChanged: changes.add),
      );
  await tester.pumpAndSettle();
  return changes;
}

void main() {
  testWidgets('each change is handed over as it is made', (tester) async {
    final changes = await _open(tester);

    await tester.tap(find.byIcon(LucideIcons.trash2).first);
    await tester.pump();

    expect(changes, hasLength(1));
    expect(changes.single.via.map((v) => v.name), ['Südkreuz']);
    expect(find.text('Ostkreuz'), findsNothing);
  });

  testWidgets('back is an ordinary back, with nothing left to hand over', (
    tester,
  ) async {
    final changes = await _open(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(ViaStopsScreen), findsNothing);
    expect(find.text('Routing'), findsOneWidget);
    expect(changes, isEmpty);
  });
}
