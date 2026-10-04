import '../models/itinerary.dart';
import 'duration_formatter.dart';

/// Under this, the countdown stops counting and says "now".
const int _kDepartNowSeconds = 60;

/// What a result says about when to leave.
class DepartureLabel {
  const DepartureLabel(this.text, {required this.hasDeparted});

  final String text;

  /// The departure is behind [now]: the connection has gone.
  final bool hasDeparted;
}

/// The countdown a result shows, or null when there is nothing to say.
///
/// A journey with no ride in it has no departure to miss: walking or cycling
/// leaves whenever the rider does. The planner starts such a journey at the
/// searched minute, so a search for "now" is already behind the clock by the
/// time it is drawn, and calling it departed would be wrong. Once its start is
/// past it says nothing; before that it counts down like any other.
DepartureLabel? departureLabel(Itinerary itinerary, {required DateTime now}) {
  final secondsUntil = itinerary.startTime.difference(now).inSeconds;
  if (secondsUntil <= 0) {
    if (!itinerary.hasTransit) return null;
    return const DepartureLabel('Departed', hasDeparted: true);
  }
  if (secondsUntil < _kDepartNowSeconds) {
    return const DepartureLabel('Depart now', hasDeparted: false);
  }
  return DepartureLabel(
    'Depart in ${formatDuration(secondsUntil)}',
    hasDeparted: false,
  );
}
