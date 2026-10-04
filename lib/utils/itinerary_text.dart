import '../models/itinerary.dart';
import 'duration_formatter.dart';
import 'itinerary_leg_utils.dart';
import 'journey_colors.dart';
import 'leg_helper.dart';
import 'time_utils.dart';

/// Lines under a leg's time line sit under its text, not under the time.
const String _kIndent = '       ';

/// An itinerary written out for a message: what to take, from where, when.
///
/// Plain text, since a share goes wherever the rider sends it, and most of
/// those places show nothing else. [fromName] and [toName] are the places the
/// rider searched for; without them the first and last named stops stand in,
/// because the planner calls a coordinate endpoint "START" or "END".
String itineraryAsText(
  Itinerary itinerary, {
  String? fromName,
  String? toName,
}) {
  final legs = itinerary.legs;
  final from = _named(fromName) ?? resolveOriginName(legs) ?? 'Start';
  final to = _named(toName) ?? resolveDestinationName(legs) ?? 'Destination';
  final start = itinerary.startTime.toLocal();

  final lines = <String>[
    '$from → $to',
    [
      '${formatWeekday(start)} ${formatDayMonth(start)}',
      '${formatTime(itinerary.startTime)}–${formatTime(itinerary.endTime)}',
      formatDuration(itinerary.duration),
      _changes(itinerary.transfers),
    ].join(' · '),
    '',
    for (var i = 0; i < legs.length; i++)
      ..._legLines(legs[i], isLast: i == legs.length - 1, to: to),
    '${formatTime(itinerary.endTime)}  Arrive at $to',
  ];
  return lines.join('\n');
}

String _changes(int transfers) => switch (transfers) {
  0 => 'direct',
  1 => '1 change',
  _ => '$transfers changes',
};

List<String> _legLines(Leg leg, {required bool isLast, required String to}) {
  if (leg.duration <= 0) return const [];
  final time = formatTime(leg.startTime);
  final cancelled = leg.cancelled ? ' (cancelled)' : '';

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
    '${_kIndent}from ${_stop(leg.fromName, leg.fromTrack)}',
    '${_kIndent}to ${_stop(leg.toName, leg.toTrack)}, '
        'arrives ${formatTime(leg.endTime)}',
    '$_kIndent${_rideSize(leg)}',
  ];
}

/// How long a ride is and how many stops it makes, for a rider who wants to
/// count them off. The stop they get off at is one of them: it is the last
/// one to count, and the one that matters.
String _rideSize(Leg leg) {
  final stops = leg.intermediateStops.length + 1;
  final noun = stops == 1 ? 'stop' : 'stops';
  return '${formatDuration(leg.duration)}, $stops $noun '
      'counting where you get off';
}

String _stop(String name, String? track) {
  final platform = _named(track);
  return platform == null ? name : '$name, platform $platform';
}

/// [name], unless it is empty or one of the planner's placeholders.
String? _named(String? name) =>
    isPlaceholderEndpointName(name) ? null : name!.trim();
