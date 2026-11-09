import 'package:flutter/widgets.dart';

import '../models/itinerary.dart';
import '../theme/app_colors.dart';
import 'color_utils.dart';

export 'color_utils.dart' show contrastRatio, ensureContrast;

/// What a street leg is drawn in.
///
/// A walk or a ride on your own bike belongs to no line, so it borrows no
/// line's colour. Fixed rather than themed: it has to read as "not a service"
/// against both backgrounds, and a slate at this lightness clears 3:1 on
/// white and on the app's near-black alike.
const Color kStreetLegColor = Color(0xFF8A9299);

/// A time nobody is reporting on: the plan, and only the plan. The text
/// colour at two strengths rather than a fixed black, which vanished against
/// the dark theme.
const double _kPlannedDepartureAlpha = 0.9;
const double _kPlannedArrivalAlpha = 0.45;

/// Running late, and running to time or early — the strong pair for a
/// departure, the light pair for an arrival.
const Color kLateDeparture = Color(0xFFD32F2F);
const Color kLateArrival = Color(0xFFE57373);
const Color kOnTimeDeparture = Color(0xFF2E7D32);
const Color kOnTimeArrival = Color(0xFF81C784);

/// A change the journey can no longer make.
///
/// The same red as a late departure, named separately because it says
/// something else: late is a number, this is a journey that stops working.
/// Should the late reds ever be retuned, this must not follow them by
/// accident.
const Color kMissedChangeColor = Color(0xFFD32F2F);

/// What a time on the spine is printed in.
///
/// The colour says who is speaking, not just whether the service is late.
/// Green means the operator is reporting this time; black means nobody is and
/// the number is the timetable's. Without that difference a green clock would
/// be indistinguishable from having no information at all, which is the more
/// useful of the two things to know.
///
/// The delay itself is never coloured — see [delayNoteColor].
Color spineTimeColor({
  required bool isLive,
  required Duration? delay,
  required bool isArrival,
}) {
  if (!isLive) {
    return AppColors.black.withValues(
      alpha: isArrival ? _kPlannedArrivalAlpha : _kPlannedDepartureAlpha,
    );
  }
  // A delay under the threshold comes back null, which is "to the minute".
  final late = delay != null && !delay.isNegative;
  if (late) return isArrival ? kLateArrival : kLateDeparture;
  return isArrival ? kOnTimeArrival : kOnTimeDeparture;
}

/// What the delay beside a time is printed in: grey, always.
///
/// Never the red or green of the time it belongs to. That time is already
/// the real one, so a coloured "+5m" reads as five minutes still to add to a
/// number that has had them added. Grey makes it what it is: why the time
/// moved, not a correction to apply to it.
Color delayNoteColor() => AppColors.black.withValues(alpha: _kDelayNoteAlpha);

const double _kDelayNoteAlpha = 0.45;

/// The colour of one leg's stretch of the spine.
///
/// The line changes colour exactly where the mode changes, which is what makes
/// the ring read as a junction rather than as decoration sitting on a line.
Color legSpineColor({
  required Leg leg,
  required Color background,
  required Color accent,
  bool isTransfer = false,
}) {
  // A change between two services is not itself a service.
  if (isTransfer || isStreetLeg(leg.mode)) return kStreetLegColor;
  final routeColor = lineColor(leg.routeColor);
  if (routeColor == null) return accent;
  return ensureContrast(routeColor, background);
}

/// Modes the traveller covers under their own power or in their own vehicle.
///
/// These get a dotted, neutral stretch: no timetable, no line, no colour.
bool isStreetLeg(String mode) => kStreetModes.contains(mode);
