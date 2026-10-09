import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/models/itinerary.dart';
import 'package:transportia/screens/itinerary_detail_screen.dart';

import '../support/app_shell.dart';
import '../support/plan_fixtures.dart';

Itinerary _itinerary({FareInfo? fare, bool withTickets = true}) {
  final planned = Itinerary.fromJson(
    planItineraryJson(departure: DateTime.now().add(const Duration(hours: 1))),
  );
  return Itinerary(
    duration: planned.duration,
    startTime: planned.startTime,
    endTime: planned.endTime,
    transfers: planned.transfers,
    legs: planned.legs,
    fare: fare,
    ticketInfo: [
      if (withTickets)
        FareLegInfo(
          routeBadges: [RouteBadge(name: 'RE7')],
          options: [
            FareOption(
              products: [
                TicketProduct(
                  name: 'Single ticket',
                  amount: 4.4,
                  currency: 'EUR',
                ),
              ],
            ),
          ],
          ticketUrl: 'https://t.example/buy',
        ),
    ],
  );
}

final FareInfo _total = FareInfo(amount: 4.4, currency: 'EUR');

void main() {
  testWidgets('the fares stay folded until the price is tapped', (
    tester,
  ) async {
    await pumpInAppShell(
      tester,
      ItineraryDetailScreen(itinerary: _itinerary(fare: _total)),
    );

    expect(find.text('4.40 EUR'), findsOne);
    expect(find.text('Single ticket'), findsNothing);
    expect(find.text('Ticket information'), findsNothing);

    await tester.tap(find.text('4.40 EUR'));
    await tester.pumpAndSettle();
    expect(find.text('Single ticket'), findsOne);
    expect(find.text('Buy tickets'), findsOne);

    await tester.tap(find.text('4.40 EUR').first);
    await tester.pumpAndSettle();
    expect(find.text('Single ticket'), findsNothing);
  });

  testWidgets('a screen reader hears what the price opens', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpInAppShell(
      tester,
      ItineraryDetailScreen(itinerary: _itinerary(fare: _total)),
    );

    expect(find.bySemanticsLabel('Ticket information, 4.40 EUR'), findsOne);
    semantics.dispose();
  });

  testWidgets('fares without a total still open, from "Tickets"', (
    tester,
  ) async {
    await pumpInAppShell(
      tester,
      ItineraryDetailScreen(itinerary: _itinerary()),
    );

    await tester.tap(find.text('Tickets'));
    await tester.pumpAndSettle();

    expect(find.text('Single ticket'), findsOne);
  });

  testWidgets('a total without fares is a plain chip', (tester) async {
    await pumpInAppShell(
      tester,
      ItineraryDetailScreen(
        itinerary: _itinerary(fare: _total, withTickets: false),
      ),
    );

    expect(find.text('4.40 EUR'), findsOne);
    expect(
      find.ancestor(
        of: find.text('4.40 EUR'),
        matching: find.byType(GestureDetector),
      ),
      findsNothing,
    );
  });
}
