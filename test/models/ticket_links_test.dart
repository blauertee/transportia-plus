import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/models/itinerary.dart';

import '../support/plan_fixtures.dart';

/// The ride of [planItineraryJson] with fares attached, as `/plan` returns
/// them: each leg says which fare leg it belongs to, and the itinerary lists
/// what each fare leg can be bought as.
Itinerary _withFares({
  Map<String, dynamic>? ticketUrls,
  String? agencyFareUrl,
}) {
  final json = planItineraryJson(
    departure: DateTime.utc(2026, 9, 28, 8),
    withEdgeWalks: false,
  );
  final legs = json['legs'] as List;
  final ride = legs.single as Map<String, dynamic>;
  ride['fareTransferIndex'] = 0;
  ride['effectiveFareLegIndex'] = 0;
  if (ticketUrls != null) ride['ticketUrls'] = ticketUrls;
  if (agencyFareUrl != null) ride['agencyFareUrl'] = agencyFareUrl;

  json['fareTransfers'] = [
    {
      'transferProducts': [
        {'amount': 4.4, 'currency': 'EUR'},
      ],
      'effectiveFareLegProducts': [
        [
          [
            {
              'name': 'Single ticket',
              'amount': 4.4,
              'currency': 'EUR',
              'media': {'fareMediaName': 'App', 'fareMediaType': 'APP'},
            },
          ],
        ],
      ],
    },
  ];
  return Itinerary.fromJson(json);
}

void main() {
  group('the link on a fare', () {
    test('a ticket link is kept', () {
      final fare = _withFares(
        ticketUrls: {'web': 'https://tickets.example/buy'},
      ).ticketInfo.single;

      expect(fare.ticketUrl, 'https://tickets.example/buy');
      expect(fare.fareUrl, isNull);
    });

    test('the agency fare page is kept when there is no ticket link', () {
      final fare = _withFares(
        agencyFareUrl: 'https://agency.example/fares',
      ).ticketInfo.single;

      expect(fare.ticketUrl, isNull);
      expect(fare.fareUrl, 'https://agency.example/fares');
    });

    test('both are kept, for the screen to choose between', () {
      final fare = _withFares(
        ticketUrls: {'web': 'https://tickets.example/buy'},
        agencyFareUrl: 'https://agency.example/fares',
      ).ticketInfo.single;

      expect(fare.ticketUrl, isNotNull);
      expect(fare.fareUrl, isNotNull);
    });

    test('an empty link is no link', () {
      // The planner sends "" for an agency with no fare page.
      final fare = _withFares(
        ticketUrls: {'web': ''},
        agencyFareUrl: '',
      ).ticketInfo.single;

      expect(fare.ticketUrl, isNull);
      expect(fare.fareUrl, isNull);
    });

    test('no link changes nothing about the fare itself', () {
      final fare = _withFares().ticketInfo.single;

      expect(fare.ticketUrl, isNull);
      expect(fare.fareUrl, isNull);
      expect(fare.options.single.products.single.name, 'Single ticket');
      expect(fare.routeBadges.single.name, 'RE7');
    });

    test('an app-only ticket link is not offered as a web link', () {
      final fare = _withFares(
        ticketUrls: {'android': 'app://buy'},
      ).ticketInfo.single;

      expect(fare.ticketUrl, isNull);
    });
  });
}
