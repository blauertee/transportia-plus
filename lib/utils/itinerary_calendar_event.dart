import 'package:flutter/foundation.dart';

import '../models/itinerary.dart';
import 'itinerary_text.dart';

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
/// the entry can open the trip again with live times; the entry itself keeps
/// the planned times it was made with.
CalendarEvent itineraryAsCalendarEvent(
  Itinerary itinerary, {
  String? fromName,
  String? toName,
  Uri? link,
}) {
  final text = itineraryAsText(itinerary, fromName: fromName, toName: toName);
  final firstBreak = text.indexOf('\n');
  final body = firstBreak < 0 ? '' : text.substring(firstBreak + 1);
  return CalendarEvent(
    title: firstBreak < 0 ? text : text.substring(0, firstBreak),
    description: link == null ? body : '$body\n\n$link',
    location: itineraryOriginName(itinerary, fromName: fromName),
    start: itinerary.startTime,
    end: itinerary.endTime,
  );
}
