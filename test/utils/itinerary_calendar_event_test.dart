import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/models/itinerary.dart';
import 'package:transportia/models/saved_trip.dart';
import 'package:transportia/models/time_selection.dart';
import 'package:transportia/utils/itinerary_calendar_event.dart';

import '../support/plan_fixtures.dart';

/// Local, so the written-out times do not depend on the machine's zone.
final _departure = DateTime(2026, 10, 2, 16, 20);

Itinerary _planned({DateTime? departure, bool cancelled = false}) =>
    Itinerary.fromJson(
      planItineraryJson(
        departure: departure ?? _departure,
        cancelled: cancelled,
      ),
    );

void main() {
  test('the entry runs from the first departure to the last arrival', () {
    final trip = _planned();
    final event = itineraryAsCalendarEvent(trip);

    expect(event.start, trip.startTime);
    expect(event.end, trip.endTime);
    // Walks included: the rider is busy from leaving the door.
    expect(event.start.toLocal(), _departure);
    expect(event.end.difference(event.start), const Duration(minutes: 23));
  });

  test('the title says where the trip goes, and starts the entry there', () {
    final event = itineraryAsCalendarEvent(_planned());

    expect(event.title, 'S+U Berlin Hauptbahnhof → Flughafen BER');
    expect(event.location, 'S+U Berlin Hauptbahnhof');
  });

  test('the places searched for name the title and the location', () {
    final event = itineraryAsCalendarEvent(
      _planned(),
      fromName: 'Home',
      toName: 'Terminal 1',
    );

    expect(event.title, 'Home → Terminal 1');
    expect(event.location, 'Home');
  });

  test('the planner\'s START and END never show', () {
    final event = itineraryAsCalendarEvent(
      _planned(),
      fromName: 'START',
      toName: 'END',
    );

    expect(event.title, 'S+U Berlin Hauptbahnhof → Flughafen BER');
    expect(event.location, 'S+U Berlin Hauptbahnhof');
    expect(event.description, isNot(contains('START')));
  });

  test('the description is the trip written out, without the title', () {
    final event = itineraryAsCalendarEvent(_planned());

    expect(
      event.description,
      'Fri 2 Oct · 16:20–16:43 · 23m · direct\n'
      '\n'
      '16:20  Walk 5m to S+U Berlin Hauptbahnhof\n'
      '16:25  RE7 towards Flughafen BER\n'
      '       from S+U Berlin Hauptbahnhof, platform 12\n'
      '       to Flughafen BER, arrives 16:40\n'
      '       15m, 3 stops counting where you get off\n'
      '16:40  Walk 3m to Flughafen BER\n'
      '16:43  Arrive at Flughafen BER',
    );
  });

  test('a link goes last, apart from the steps', () {
    final link = Uri.parse('https://blauertee.github.io/fw/?itineraryId=x');
    final event = itineraryAsCalendarEvent(_planned(), link: link);

    expect(event.description, endsWith('Arrive at Flughafen BER\n\n$link'));
  });

  test('a trip past midnight ends on the next day', () {
    final event = itineraryAsCalendarEvent(
      _planned(departure: DateTime(2026, 10, 2, 23, 50)),
    );

    expect(event.end.toLocal(), DateTime(2026, 10, 3, 0, 13));
  });

  test('a cancellation seen once stays out of the entry', () {
    final event = itineraryAsCalendarEvent(_planned(cancelled: true));
    expect(event.description, isNot(contains('cancelled')));
  });

  test('a delay seen while saving stays out of the entry', () {
    final json = planItineraryJson(departure: _departure);
    final ride = (json['legs'] as List)[1] as Map<String, dynamic>;
    String late(Object? at) => DateTime.parse(
      at! as String,
    ).add(const Duration(minutes: 9)).toUtc().toIso8601String();
    ride['startTime'] = late(ride['startTime']);
    ride['endTime'] = late(ride['endTime']);
    json['endTime'] = late(json['endTime']);

    final event = itineraryAsCalendarEvent(Itinerary.fromJson(json));

    expect(event.end.toLocal(), DateTime(2026, 10, 2, 16, 43));
    expect(event.description, contains('16:25  RE7'));
    expect(event.description, contains('arrives 16:40'));
  });

  group('a saved trip', () {
    SavedTrip saved({String? label}) => SavedTrip.fromItinerary(
      itinerary: _planned(),
      timeSelection: TimeSelection(dateTime: _departure, isArriveBy: false),
      label: label,
    );

    test('is named after its route', () {
      expect(
        savedTripAsCalendarEvent(saved()).title,
        'S+U Berlin Hauptbahnhof → Flughafen BER',
      );
    });

    test('is named what the rider called it', () {
      expect(
        savedTripAsCalendarEvent(saved(label: '  Airport run ')).title,
        'Airport run',
      );
    });

    test('a blank name falls back to the route', () {
      expect(
        savedTripEventTitle(saved(label: '   '), fallback: 'Route'),
        'Route',
      );
    });
  });
}
