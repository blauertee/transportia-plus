import 'package:flutter/foundation.dart';

import '../models/itinerary.dart';
import '../models/saved_trip.dart';
import 'itinerary_text.dart';
import 'planned_times.dart';

/// A calendar entry for a trip, as the rider's calendar app is handed it.
@immutable
class CalendarEvent {
  const CalendarEvent({
    required this.title,
    required this.description,
    required this.location,
    required this.start,
    required this.end,
  });

  final String title;
  final String description;
  final String location;
  final DateTime start;
  final DateTime end;
}

/// [itinerary] as one calendar entry, from its first departure to its last
/// arrival: one entry per trip, since one per leg clutters the day.
///
/// The description is the trip written out as for a text share, without its
/// first line, which is the title. [link], when there is one, goes under it so
/// the entry can open the trip again with live times.
///
/// The entry holds the timetable, never live data: a calendar is for
/// planning, and a delay seen while saving would otherwise stay in it for
/// good. See [plannedLegTimes].
CalendarEvent itineraryAsCalendarEvent(
  Itinerary itinerary, {
  String? fromName,
  String? toName,
  Uri? link,
}) {
  final text = itineraryAsText(
    itinerary,
    fromName: fromName,
    toName: toName,
    planned: true,
  );
  final times = plannedLegTimes(itinerary);
  final firstBreak = text.indexOf('\n');
  final body = firstBreak < 0 ? '' : text.substring(firstBreak + 1);
  return CalendarEvent(
    title: firstBreak < 0 ? text : text.substring(0, firstBreak),
    description: link == null ? body : '$body\n\n$link',
    location: itineraryOriginName(itinerary, fromName: fromName),
    start: times.isEmpty ? itinerary.startTime : times.first.start,
    end: times.isEmpty ? itinerary.endTime : times.last.end,
  );
}

/// [trip] as its calendar entry: [itineraryAsCalendarEvent] of the stored
/// connection, under the name the rider gave the trip when there is one.
CalendarEvent savedTripAsCalendarEvent(SavedTrip trip, {Uri? link}) {
  final event = itineraryAsCalendarEvent(
    trip.itinerary,
    fromName: trip.fromName,
    toName: trip.toName,
    link: link,
  );
  return CalendarEvent(
    title: savedTripEventTitle(trip, fallback: event.title),
    description: event.description,
    location: event.location,
    start: event.start,
    end: event.end,
  );
}

/// The calendar title for [trip]: the name the rider gave it, else
/// [fallback], the route the entry is otherwise named after.
String savedTripEventTitle(SavedTrip trip, {required String fallback}) {
  final label = trip.label?.trim();
  return label == null || label.isEmpty ? fallback : label;
}
