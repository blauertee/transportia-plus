import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/models/itinerary.dart';
import 'package:transportia/utils/itinerary_text.dart';

import '../support/plan_fixtures.dart';

/// Local, so the printed times do not depend on the machine's zone.
final _departure = DateTime(2026, 10, 2, 16, 20);

Itinerary _planned({bool withEdgeWalks = true, bool cancelled = false}) =>
    Itinerary.fromJson(
      planItineraryJson(
        departure: _departure,
        withEdgeWalks: withEdgeWalks,
        cancelled: cancelled,
      ),
    );

void main() {
  test('a journey reads as what to take, from where, when', () {
    final text = itineraryAsText(_planned());

    expect(
      text,
      'S+U Berlin Hauptbahnhof → Flughafen BER\n'
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

  test('the places searched for name the ends', () {
    final text = itineraryAsText(
      _planned(),
      fromName: 'Home',
      toName: 'Terminal 1',
    );
    expect(text, startsWith('Home → Terminal 1\n'));
    // The last walk ends where the rider is going, not at the stop.
    expect(text, contains('Walk 3m to Terminal 1'));
    expect(text, endsWith('Arrive at Terminal 1'));
  });

  test('the planner\'s START and END never show', () {
    final text = itineraryAsText(_planned(), fromName: 'START', toName: 'END');
    expect(text, isNot(contains('START')));
    expect(text, isNot(contains('END')));
  });

  test('a cancelled service says so', () {
    expect(
      itineraryAsText(_planned(cancelled: true)),
      contains('RE7 towards Flughafen BER (cancelled)'),
    );
  });

  test('a journey without walks is just the ride', () {
    final lines = itineraryAsText(_planned(withEdgeWalks: false)).split('\n');
    expect(lines.where((l) => l.contains('Walk')), isEmpty);
    expect(lines[3], '16:20  RE7 towards Flughafen BER');
  });

  group('how big a ride is', () {
    Leg ride({required int between, int minutes = 12}) {
      final start = _departure;
      final end = start.add(Duration(minutes: minutes));
      return Leg(
        mode: 'BUS',
        from: const TransitPlace(name: 'A', lat: 1, lon: 1),
        to: const TransitPlace(name: 'B', lat: 2, lon: 2),
        intermediateStops: [
          for (var i = 0; i < between; i++)
            TransitPlace(name: 'Between $i', lat: 1.5, lon: 1.5),
        ],
        startTime: start,
        endTime: end,
        duration: end.difference(start).inSeconds,
        displayName: '42',
      );
    }

    String textFor(Leg leg) => itineraryAsText(
      Itinerary(
        duration: leg.duration,
        startTime: leg.startTime,
        endTime: leg.endTime,
        transfers: 0,
        legs: [leg],
      ),
    );

    test(
      'says how long and how many stops, the last being where you get off',
      () {
        expect(
          textFor(ride(between: 4)),
          contains('\n       12m, 5 stops counting where you get off\n'),
        );
      },
    );

    test('a ride with nothing between is one stop, not "1 stops"', () {
      expect(
        textFor(ride(between: 0)),
        contains('12m, 1 stop counting where you get off'),
      );
    });

    test('a long ride is in hours and minutes', () {
      expect(
        textFor(ride(between: 9, minutes: 95)),
        contains('1h 35m, 10 stops'),
      );
    });

    test('every service in a journey has its own count', () {
      final json = jsonDecode(
        File('test/fixtures/transitous/plan.json').readAsStringSync(),
      );
      final itinerary = Itinerary.fromJson(json['itineraries'][0]);
      final text = itineraryAsText(itinerary);

      final rides = itinerary.legs.where((l) => l.mode != 'WALK').length;
      expect(
        RegExp('counting where you get off').allMatches(text),
        hasLength(rides),
      );
    });

    test('a walk has no stops to count', () {
      final text = itineraryAsText(_planned());

      expect(
        RegExp('counting where you get off').allMatches(text),
        hasLength(1),
      );
      expect(text, contains('Walk 5m to S+U Berlin Hauptbahnhof\n'));
    });
  });

  test('the real Berlin–Hamburg capture lists every service', () {
    final json = jsonDecode(
      File('test/fixtures/transitous/plan.json').readAsStringSync(),
    );
    final itinerary = Itinerary.fromJson(json['itineraries'][0]);
    final text = itineraryAsText(itinerary);

    for (final leg in itinerary.legs.where((l) => l.mode != 'WALK')) {
      expect(text, contains(leg.displayName!));
    }
    expect(text, isNot(contains('START')));
    expect(text, isNot(contains('null')));
  });
}
