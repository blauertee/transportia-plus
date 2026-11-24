import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/models/map_render_profile.dart';
import 'package:transportia/services/map_rendering_service.dart';
import 'package:transportia/widgets/map/switchable_map.dart';

void main() {
  final service = MapRenderingService.instance;
  tearDown(() => service.debugState = MapRenderState.fallback);

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: SwitchableMap(builder: (_) => const Text('the map')),
    ),
  );

  testWidgets('builds the map while maps are on', (tester) async {
    await pump(tester);
    expect(find.text('the map'), findsOneWidget);
  });

  testWidgets('never builds the map while maps are off', (tester) async {
    service.debugState = MapRenderState.fallback.withMapsOff(true);
    await pump(tester);
    expect(find.text('the map'), findsNothing);
    expect(find.textContaining('turned off'), findsOneWidget);
  });

  testWidgets('follows the switch while on screen', (tester) async {
    await pump(tester);
    service.debugState = MapRenderState.fallback.withMapsOff(true);
    await tester.pump();
    expect(find.text('the map'), findsNothing);
    service.debugState = MapRenderState.fallback;
    await tester.pump();
    expect(find.text('the map'), findsOneWidget);
  });
}
