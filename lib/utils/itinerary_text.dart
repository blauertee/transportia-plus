import '../models/itinerary.dart';
import 'duration_formatter.dart';
import 'itinerary_leg_utils.dart';
import 'journey_colors.dart';
import 'leg_helper.dart';
import 'planned_times.dart';
import 'time_utils.dart';

/// Lines under a leg's time line sit under its text, not under the time.
const String _kIndent = '       ';

/// An itinerary written out for a message: what to take, from where, when.
///
/// Plain text, since a share goes wherever the rider sends it, and most of
/// those places show nothing else. [fromName] and [toName] are the places the
/// rider searched for; without them the first and last named stops stand in,
/// because the planner calls a coordinate endpoint "START" or "END".
///
/// [planned] writes the timetable instead of what the snapshot last heard:
/// planned times and platforms, and no cancellations. See [plannedLegTimes].
String itineraryAsText(
  Itinerary itinerary, {
  String? fromName,
  String? toName,
  bool planned = false,
}) {
  final legs = itinerary.legs;
  final from = itineraryOriginName(itinerary, fromName: fromName);
  final to = itineraryDestinationName(itinerary, toName: toName);
  final times = planned
      ? plannedLegTimes(itinerary)
      : [for (final leg in legs) (start: leg.startTime, end: leg.endTime)];
  final departs = planned && times.isNotEmpty
      ? times.first.start
      : itinerary.startTime;
  final arrives = planned && times.isNotEmpty
      ? times.last.end
      : itinerary.endTime;
  final duration = planned
      ? arrives.difference(departs).inSeconds
      : itinerary.duration;
  final start = departs.toLocal();

  final lines = <String>[
    '$from → $to',
    [
      '${formatWeekday(start)} ${formatDayMonth(start)}',
      '${formatTime(departs)}–${formatTime(arrives)}',
      formatDuration(duration),
      _changes(itinerary.transfers),
    ].join(' · '),
    '',
    for (var i = 0; i < legs.length; i++)
      ..._legLines(
        legs[i],
        times[i],
        isLast: i == legs.length - 1,
        to: to,
        planned: planned,
      ),
    '${formatTime(arrives)}  Arrive at $to',
  ];
  return lines.join('\n');
}

/// What to call where [itinerary] starts: the place the rider searched for
/// ([fromName]), else the first named stop, since the planner calls a
/// coordinate start "START".
String itineraryOriginName(Itinerary itinerary, {String? fromName}) =>
    _named(fromName) ?? resolveOriginName(itinerary.legs) ?? 'Start';

/// What to call where [itinerary] ends; see [itineraryOriginName].
String itineraryDestinationName(Itinerary itinerary, {String? toName}) =>
    _named(toName) ?? resolveDestinationName(itinerary.legs) ?? 'Destination';

String _changes(int transfers) => switch (transfers) {
  0 => 'direct',
  1 => '1 change',
  _ => '$transfers changes',
};

List<String> _legLines(
  Leg leg,
  PlannedTimes times, {
  required bool isLast,
  required String to,
  required bool planned,
}) {
  if (leg.duration <= 0) return const [];
  final time = formatTime(times.start);
  final cancelled = leg.cancelled && !planned ? ' (cancelled)' : '';
  final fromTrack = planned
      ? leg.fromScheduledTrack ?? leg.fromTrack
      : leg.fromTrack;
  final toTrack = planned ? leg.toScheduledTrack ?? leg.toTrack : leg.toTrack;
  final rideSeconds = planned
      ? times.end.difference(times.start).inSeconds
      : leg.duration;

  if (isStreetLeg(leg.mode)) {
    final target = isLast ? to : _named(leg.toName) ?? 'the next stop';
    return [
      '$time  ${getTransitModeName(leg.mode)} ${formatDuration(leg.duration)} '
          'to $target$cancelled',
    ];
  }

  final service =
      _named(leg.displayName) ??
      _named(leg.routeShortName) ??
      getTransitModeName(leg.mode);
  final headsign = _named(leg.headsign);
  return [
    '$time  $service${headsign == null ? '' : ' towards $headsign'}$cancelled',
    '${_kIndent}from ${_stop(leg.fromName, fromTrack)}',
    '${_kIndent}to ${_stop(leg.toName, toTrack)}, '
        'arrives ${formatTime(times.end)}',
    '$_kIndent${_rideSize(leg, rideSeconds)}',
  ];
}

/// How long a ride is and how many stops it makes, for a rider who wants to
/// count them off. The stop they get off at is one of them: it is the last
/// one to count, and the one that matters.
String _rideSize(Leg leg, int seconds) {
  final stops = leg.intermediateStops.length + 1;
  final noun = stops == 1 ? 'stop' : 'stops';
  return '${formatDuration(seconds)}, $stops $noun '
      'counting where you get off';
}

String _stop(String name, String? track) {
  final platform = _named(track);
  return platform == null ? name : '$name, platform $platform';
}

/// [name], unless it is empty or one of the planner's placeholders.
String? _named(String? name) =>
    isPlaceholderEndpointName(name) ? null : name!.trim();
