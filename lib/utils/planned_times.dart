import '../models/itinerary.dart';

/// When a leg was planned to start and end.
typedef PlannedTimes = ({DateTime start, DateTime end});

/// When each leg of [itinerary] was planned to start and end, leaving out any
/// real-time data the snapshot picked up: a calendar is for planning, and a
/// delay seen once would otherwise stay in it for good.
///
/// Rides read their timetable. Walks, bikes and shared vehicles have no
/// timetable of their own, so they hang off the rides around them: those
/// before the first ride end where the next leg is planned to start, those
/// after it start where the leg before was planned to end, each lasting as
/// long as it was routed to. A trip with no ride has nothing live to leave
/// out and keeps its own times.
List<PlannedTimes> plannedLegTimes(Itinerary itinerary) {
  final legs = itinerary.legs;
  final times = <PlannedTimes?>[
    for (final leg in legs)
      if (leg.isRide)
        (
          start:
              leg.scheduledStartTime ??
              leg.from.scheduledDeparture ??
              leg.startTime,
          end: leg.scheduledEndTime ?? leg.to.scheduledArrival ?? leg.endTime,
        )
      else
        null,
  ];

  final firstRide = times.indexWhere((t) => t != null);
  if (firstRide < 0) {
    return [for (final leg in legs) (start: leg.startTime, end: leg.endTime)];
  }

  for (var i = firstRide - 1; i >= 0; i--) {
    final end = times[i + 1]!.start;
    times[i] = (start: end.subtract(_length(legs[i])), end: end);
  }
  for (var i = firstRide + 1; i < legs.length; i++) {
    if (times[i] != null) continue;
    final start = times[i - 1]!.end;
    times[i] = (start: start, end: start.add(_length(legs[i])));
  }
  return [for (final t in times) t!];
}

Duration _length(Leg leg) => Duration(seconds: leg.duration);
