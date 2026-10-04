import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/models/itinerary.dart';
import 'package:transportia/providers/theme_provider.dart';
import 'package:transportia/screens/itinerary_detail_screen.dart';

FareLegInfo _fare({String? ticketUrl, String? fareUrl}) => FareLegInfo(
  routeBadges: [RouteBadge(name: 'RE7')],
  options: [
    FareOption(
      products: [
        TicketProduct(name: 'Single ticket', amount: 4.4, currency: 'EUR'),
      ],
    ),
  ],
  ticketUrl: ticketUrl,
  fareUrl: fareUrl,
);

Future<void> _pumpExpanded(WidgetTester tester, FareLegInfo fare) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeProvider>(
      create: (_) => ThemeProvider(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(900, 1600)),
          child: TicketInfoCard(ticketInfo: [fare]),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Ticket information'));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('a ticket link says Buy tickets', (tester) async {
    await _pumpExpanded(tester, _fare(ticketUrl: 'https://t.example/buy'));

    expect(find.text('Buy tickets'), findsOneWidget);
    expect(find.text('More info'), findsNothing);
  });

  testWidgets('a fare page says More info', (tester) async {
    await _pumpExpanded(tester, _fare(fareUrl: 'https://a.example/fares'));

    expect(find.text('More info'), findsOneWidget);
    expect(find.text('Buy tickets'), findsNothing);
  });

  testWidgets('with both only the ticket link is offered', (tester) async {
    await _pumpExpanded(
      tester,
      _fare(
        ticketUrl: 'https://t.example/buy',
        fareUrl: 'https://a.example/fares',
      ),
    );

    expect(find.text('Buy tickets'), findsOneWidget);
    expect(find.text('More info'), findsNothing);
  });

  testWidgets('with neither the card looks as it always did', (tester) async {
    await _pumpExpanded(tester, _fare());

    expect(find.text('Buy tickets'), findsNothing);
    expect(find.text('More info'), findsNothing);
    expect(find.text('Single ticket'), findsOneWidget);
    expect(find.text('4.40 EUR'), findsOneWidget);
  });

  testWidgets('the link is not shown until the card is opened', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: TicketInfoCard(
            ticketInfo: [_fare(ticketUrl: 'https://t.example/buy')],
          ),
        ),
      ),
    );

    expect(find.text('Ticket information'), findsOneWidget);
    expect(find.text('Buy tickets'), findsNothing);
  });
}
