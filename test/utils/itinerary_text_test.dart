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
