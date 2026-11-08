import '../models/itinerary.dart';
import 'geo_utils.dart';
import 'journey_colors.dart' show isStreetLeg;

const double kSmallWalkSegmentThresholdMeters = 35.0;

enum DisplayLegType { normal, transfer }

class DisplayLegInfo {
  final Leg leg;
  final int originalIndex;
  final DisplayLegType type;

  const DisplayLegInfo({
    required this.leg,
    required this.originalIndex,
    this.type = DisplayLegType.normal,
  });

  bool get isTransfer => type == DisplayLegType.transfer;
}

List<DisplayLegInfo> buildDisplayLegs(List<Leg> legs) {
  final result = <DisplayLegInfo>[];
  for (int i = 0; i < legs.length; i++) {
    final leg = legs[i];
    if (_shouldHideEdgeWalk(leg, i, legs.length)) continue;

    final type = _shouldShowAsTransfer(leg, i, legs.length)
        ? DisplayLegType.transfer
        : DisplayLegType.normal;

    result.add(DisplayLegInfo(leg: leg, originalIndex: i, type: type));
  }
  return result;
}

bool isShortWalkLeg(
  Leg leg, {
  double thresholdMeters = kSmallWalkSegmentThresholdMeters,
}) {
  if (leg.mode != 'WALK') return false;
  return areCoordsClose(
    leg.fromLat,
    leg.fromLon,
    leg.toLat,
    leg.toLon,
    thresholdInMeters: thresholdMeters,
  );
}

bool _shouldHideEdgeWalk(Leg leg, int index, int total) {
  if (leg.mode != 'WALK') return false;
  final isEdge = index == 0 || index == total - 1;
  if (!isEdge) return false;
  return isShortWalkLeg(leg);
}

/// A street leg with a ride on either side of it is a change, whatever the
/// distance.
///
/// Getting between two services is one act to the traveller — the question is
/// "have I time, and which platform", not "how far".
///
/// Being at an edge is the whole of the distinction: the leg that gets you
/// *to* the first stop, or home from the last, is your own journey rather
/// than a change between someone else's services.
bool _shouldShowAsTransfer(Leg leg, int index, int total) {
  if (!isStreetLeg(leg.mode)) return false;
  final isEdge = index == 0 || index == total - 1;
  return !isEdge;
}

/// Names the planner uses for the query's own origin and destination when
/// those were plain coordinates rather than stops.
///
/// A journey planned from a map pin to an address comes back as
/// `START → S+U Hauptbahnhof → Flughafen BER → END`: the real places are
/// there, just never on the outermost edges. Anything showing an endpoint
/// to a person has to look past them.
const Set<String> kPlaceholderEndpointNames = {'START', 'END'};

bool isPlaceholderEndpointName(String? name) {
  if (name == null) return true;
  final trimmed = name.trim();
  if (trimmed.isEmpty) return true;
  return kPlaceholderEndpointNames.contains(trimmed.toUpperCase());
}

/// What to call the start or the end of a journey, given the planner's
/// [name] for it: that, unless it is a placeholder, else the name the
/// journey was [searched] by, else [fallback].
String endpointLabel(
  String? name, {
  String? searched,
  required String fallback,
}) {
  if (!isPlaceholderEndpointName(name)) return name!.trim();
  if (!isPlaceholderEndpointName(searched)) return searched!.trim();
  return fallback;
}

/// What the end of [legs] is called on the journey's last row.
///
/// Where the walk from the last stop is too short to show, the journey
/// visibly ends at that stop, so that is its name; [searched] would name a
/// place nobody is seen to walk to.
String destinationLabel(List<Leg> legs, {String? searched}) {
  if (legs.isEmpty) return searched ?? 'Destination';
  final last = legs.last;
  if (_shouldHideEdgeWalk(last, legs.length - 1, legs.length)) {
    return endpointLabel(
      last.fromName,
      searched: searched,
      fallback: 'Destination',
    );
  }
  return endpointLabel(
    last.toName,
    searched: searched,
    fallback: 'Destination',
  );
}

/// The first real place name at the start of [legs] — normally the stop
/// where the traveller boards, when the journey opens with a walk from an
/// unnamed point.
///
/// Returns null when nothing in the itinerary is named, which happens for a
/// walk between two coordinates. Callers decide what to show instead.
String? resolveOriginName(List<Leg> legs) {
  for (final leg in legs) {
    for (final name in [leg.fromName, leg.toName]) {
      if (!isPlaceholderEndpointName(name)) return name.trim();
    }
  }
  return null;
}

/// The last real place name in [legs] — normally the stop where the
/// traveller gets off. See [resolveOriginName] for the null case.
String? resolveDestinationName(List<Leg> legs) {
  for (final leg in legs.reversed) {
    for (final name in [leg.toName, leg.fromName]) {
      if (!isPlaceholderEndpointName(name)) return name.trim();
    }
  }
  return null;
}

/// The stop id matching [resolveOriginName] — the first real stop the
/// journey touches. Null when it never touches one, since the coordinate
/// the journey starts from has no id.
String? resolveOriginStopId(List<Leg> legs) {
  for (final leg in legs) {
    for (final stopId in [leg.fromStopId, leg.toStopId]) {
      if (stopId != null && stopId.isNotEmpty) return stopId;
    }
  }
  return null;
}

/// The stop id matching [resolveDestinationName].
String? resolveDestinationStopId(List<Leg> legs) {
  for (final leg in legs.reversed) {
    for (final stopId in [leg.toStopId, leg.fromStopId]) {
      if (stopId != null && stopId.isNotEmpty) return stopId;
    }
  }
  return null;
}
