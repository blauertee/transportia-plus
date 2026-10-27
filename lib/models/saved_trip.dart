import 'itinerary.dart';
import 'time_selection.dart';
import '../utils/geo_utils.dart';
import '../utils/itinerary_leg_utils.dart';
import '../utils/time_utils.dart';

/// Last resort when a journey has no named place anywhere in it — a walk
/// between two coordinates.
String _coordinateLabel(double lat, double lon) => coordLabel(lat, lon);

/// Picks the best available name for one end of a journey: what the user
/// searched for, else the stop they board or leave from, else coordinates.
String _resolveEndpointName({
  required String? searched,
  required String? derived,
  required double lat,
  required double lon,
}) {
  if (!isPlaceholderEndpointName(searched)) return searched!.trim();
  if (!isPlaceholderEndpointName(derived)) return derived!.trim();
  return _coordinateLabel(lat, lon);
}

/// A connection kept for later: one the user chose to save, or one
/// `RecentTripsService` kept because it was opened recently. The two are
/// stored apart, so only the first kind is listed as saved.
///
/// It holds two things, and needs both:
///
/// * the **snapshot** — the raw planner output for the itinerary that was
///   chosen, so the exact departure can be shown again;
/// * the **intent** — where the user was going and when, so the app can
///   re-plan when the snapshot no longer holds (cancelled leg, timetable
///   change, or simply a departure too far out for the real-time feed).
class SavedTrip {
  SavedTrip({
    required this.id,
    required this.fromName,
    required this.fromLat,
    required this.fromLon,
    required this.toName,
    required this.toLat,
    required this.toLon,
    required this.timeSelection,
    required this.departureTime,
    required this.arrivalTime,
    required this.savedAt,
    required this.itineraryJson,
    this.liveUpdatedAt,
    this.label,
    this.fromStopId,
    this.toStopId,
    this.isDirect = false,
  });

  final String id;
  final String? label;

  final String fromName;
  final double fromLat;
  final double fromLon;
  final String? fromStopId;

  final String toName;
  final double toLat;
  final double toLon;
  final String? toStopId;

  /// What the user searched for. Used to re-plan when the snapshot dies.
  final TimeSelection timeSelection;

  /// Denormalised from the snapshot so lists can sort and group without
  /// parsing every stored itinerary.
  final DateTime departureTime;
  final DateTime arrivalTime;

  final DateTime savedAt;
  final bool isDirect;

  /// The raw planner output, straight from `Itinerary.sourceJson`.
  ///
  /// Refreshed in place when a live check comes back with the same
  /// connection, so reopening the app shows the times the operator last
  /// reported rather than the plan it was saved under.
  final Map<String, dynamic> itineraryJson;

  /// When [itineraryJson] last picked up real-time data. Null while the trip
  /// has only ever been the plan.
  final DateTime? liveUpdatedAt;

  Itinerary? _itinerary;

  /// The stored connection. Parsed on first access and cached, since list
  /// views only need [departureTime] and the names.
  Itinerary get itinerary =>
      _itinerary ??= Itinerary.fromJson(itineraryJson, isDirect: isDirect);

  bool get isPast => arrivalTime.isBefore(DateTime.now());

  String get displayLabel =>
      label?.trim().isNotEmpty == true ? label!.trim() : defaultLabel;

  String get defaultLabel =>
      '$fromName → $toName · ${formatRelativeDay(departureTime)} '
      '${formatTime(departureTime)}';

  /// Identity of a saved connection: the same departure, on the same rides,
  /// between the same two points. Re-saving one replaces it rather than
  /// piling up duplicates.
  ///
  /// Every ride counts, not just the first: a journey replanned on from one
  /// of its rides leaves at the same time on the same first train, and is
  /// still another journey.
  /// Four decimals is ~10 m: the same street corner counts as the same
  /// endpoint, so re-saving a trip planned from a slightly different tap
  /// replaces it rather than piling up near-identical rows.
  static const int _identityDecimals = 4;

  static String buildId({
    required Itinerary itinerary,
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) {
    final from = coordKey(fromLat, fromLon, decimals: _identityDecimals);
    final to = coordKey(toLat, toLon, decimals: _identityDecimals);
    final departure = itinerary.startTime.toUtc().toIso8601String();
    return '$from>$to@$departure#${_rides(itinerary.legs.map((leg) => leg.tripId))}';
  }

  /// The trips ridden, in order, as the end of an id; "walk" for none.
  static String _rides(Iterable<String?> tripIds) {
    final rides = [
      for (final tripId in tripIds)
        if (tripId != null && tripId.isNotEmpty) tripId,
    ];
    return rides.isEmpty ? 'walk' : rides.join('#');
  }

  /// [stored] as [buildId] makes it now, from the snapshot's legs.
  ///
  /// Ids stored before every ride counted end on the first ride's trip
  /// alone. Read back unchanged, a saved journey would no longer match
  /// itself and could be saved twice; with only one ride there is nothing
  /// to change.
  static String _currentId(String stored, Map<String, dynamic> itinerary) {
    final hash = stored.indexOf('#');
    if (hash < 0) return stored;
    final legs = itinerary['legs'];
    if (legs is! List) return stored;
    final tripIds = [
      for (final leg in legs)
        if (leg is Map && leg['tripId'] is String) leg['tripId'] as String,
    ];
    return '${stored.substring(0, hash)}#${_rides(tripIds)}';
  }

  /// Builds a saved trip from a chosen [itinerary].
  ///
  /// The itinerary must have come from the API — [Itinerary.sourceJson] is
  /// what gets persisted, so an itinerary assembled in code cannot be saved.
  ///
  /// [fromName] and [toName] are the places the user searched for, when
  /// there were any. Each falls back to the stop the traveller boards or
  /// leaves from, and finally to coordinates.
  ///
  /// The fallback matters as much as the preference. The planner names the
  /// query's own endpoints "START" and "END" whenever they were plain
  /// coordinates, so the outermost leg names are frequently useless — see
  /// [resolveOriginName]. And an origin of "My Location" means nothing when
  /// the trip is reopened from somewhere else, whereas the boarding stop
  /// still does.
  factory SavedTrip.fromItinerary({
    required Itinerary itinerary,
    String? fromName,
    double? fromLat,
    double? fromLon,
    String? toName,
    double? toLat,
    double? toLon,
    TimeSelection? timeSelection,
    String? label,
    DateTime? savedAt,
  }) {
    final json = itinerary.sourceJson;
    if (json == null) {
      throw ArgumentError(
        'Only itineraries parsed from the planner can be saved.',
      );
    }

    // Read the schedule back out of the snapshot rather than off the
    // in-memory itinerary, which may already carry real-time offsets.
    final snapshot = Itinerary.fromJson(json, isDirect: itinerary.isDirect);
    final firstLeg = snapshot.legs.firstOrNull;
    final lastLeg = snapshot.legs.lastOrNull;

    if (firstLeg == null || lastLeg == null) {
      throw ArgumentError('An itinerary without legs cannot be saved.');
    }

    final resolvedFromLat = fromLat ?? firstLeg.fromLat;
    final resolvedFromLon = fromLon ?? firstLeg.fromLon;
    final resolvedToLat = toLat ?? lastLeg.toLat;
    final resolvedToLon = toLon ?? lastLeg.toLon;

    return SavedTrip(
      id: buildId(
        itinerary: snapshot,
        fromLat: resolvedFromLat,
        fromLon: resolvedFromLon,
        toLat: resolvedToLat,
        toLon: resolvedToLon,
      ),
      label: label,
      fromName: _resolveEndpointName(
        searched: fromName,
        derived: resolveOriginName(snapshot.legs),
        lat: resolvedFromLat,
        lon: resolvedFromLon,
      ),
      fromLat: resolvedFromLat,
      fromLon: resolvedFromLon,
      fromStopId: resolveOriginStopId(snapshot.legs),
      toName: _resolveEndpointName(
        searched: toName,
        derived: resolveDestinationName(snapshot.legs),
        lat: resolvedToLat,
        lon: resolvedToLon,
      ),
      toLat: resolvedToLat,
      toLon: resolvedToLon,
      toStopId: resolveDestinationStopId(snapshot.legs),
      timeSelection:
          timeSelection ??
          TimeSelection(dateTime: snapshot.startTime, isArriveBy: false),
      departureTime: snapshot.startTime,
      arrivalTime: snapshot.endTime,
      savedAt: savedAt ?? DateTime.now(),
      isDirect: itinerary.isDirect,
      itineraryJson: json,
    );
  }

  /// Returns a copy carrying [label] as the user-set name. Pass null to
  /// clear it and fall back to [defaultLabel].
  ///
  /// Deliberately not a general `copyWith`: the label is the only mutable
  /// part of a saved trip, and a nullable `copyWith` parameter cannot tell
  /// "leave it alone" from "clear it".
  SavedTrip withLabel(String? label) {
    return SavedTrip(
      id: id,
      label: label,
      fromName: fromName,
      fromLat: fromLat,
      fromLon: fromLon,
      fromStopId: fromStopId,
      toName: toName,
      toLat: toLat,
      toLon: toLon,
      toStopId: toStopId,
      timeSelection: timeSelection,
      departureTime: departureTime,
      arrivalTime: arrivalTime,
      savedAt: savedAt,
      isDirect: isDirect,
      itineraryJson: itineraryJson,
      liveUpdatedAt: liveUpdatedAt,
    );
  }

  /// The same trip carrying newer real-time data.
  ///
  /// Everything identifying the connection is kept — only the snapshot and
  /// the stamp move. The caller decides whether a refresh is *the same*
  /// connection; a different one is not an update to this trip.
  ///
  /// Returns this trip untouched when [refreshed] has no raw JSON to store.
  /// Stamping it fresh over the old snapshot would claim times the trip does
  /// not actually carry.
  SavedTrip withLiveItinerary(Itinerary refreshed, {required DateTime at}) {
    final json = refreshed.sourceJson;
    if (json == null) return this;

    return SavedTrip(
      id: id,
      label: label,
      fromName: fromName,
      fromLat: fromLat,
      fromLon: fromLon,
      fromStopId: fromStopId,
      toName: toName,
      toLat: toLat,
      toLon: toLon,
      toStopId: toStopId,
      timeSelection: timeSelection,
      departureTime: refreshed.startTime,
      arrivalTime: refreshed.endTime,
      savedAt: savedAt,
      isDirect: isDirect,
      itineraryJson: json,
      liveUpdatedAt: at,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    if (label != null) 'label': label,
    'fromName': fromName,
    'fromLat': fromLat,
    'fromLon': fromLon,
    if (fromStopId != null) 'fromStopId': fromStopId,
    'toName': toName,
    'toLat': toLat,
    'toLon': toLon,
    if (toStopId != null) 'toStopId': toStopId,
    'timeSelection': timeSelection.toJson(),
    'departureTime': departureTime.toIso8601String(),
    'arrivalTime': arrivalTime.toIso8601String(),
    'savedAt': savedAt.toIso8601String(),
    'isDirect': isDirect,
    'itinerary': itineraryJson,
    if (liveUpdatedAt != null)
      'liveUpdatedAt': liveUpdatedAt!.toIso8601String(),
  };

  factory SavedTrip.fromJson(Map<String, dynamic> json) {
    final fromLat = (json['fromLat'] as num).toDouble();
    final fromLon = (json['fromLon'] as num).toDouble();
    final toLat = (json['toLat'] as num).toDouble();
    final toLon = (json['toLon'] as num).toDouble();
    final itineraryJson = json['itinerary'] as Map<String, dynamic>;
    final isDirect = json['isDirect'] as bool? ?? false;

    var fromName = json['fromName'] as String;
    var toName = json['toName'] as String;

    // Trips stored before endpoint names were resolved properly kept the
    // planner's "START"/"END" placeholders. Repair them from the snapshot
    // on read, so an existing list heals itself instead of needing every
    // trip saved again. Only broken entries pay the parse.
    if (isPlaceholderEndpointName(fromName) ||
        isPlaceholderEndpointName(toName)) {
      final legs = Itinerary.fromJson(itineraryJson, isDirect: isDirect).legs;
      fromName = _resolveEndpointName(
        searched: fromName,
        derived: resolveOriginName(legs),
        lat: fromLat,
        lon: fromLon,
      );
      toName = _resolveEndpointName(
        searched: toName,
        derived: resolveDestinationName(legs),
        lat: toLat,
        lon: toLon,
      );
    }

    return SavedTrip(
      id: _currentId(json['id'] as String, itineraryJson),
      label: json['label'] as String?,
      fromName: fromName,
      fromLat: fromLat,
      fromLon: fromLon,
      fromStopId: json['fromStopId'] as String?,
      toName: toName,
      toLat: toLat,
      toLon: toLon,
      toStopId: json['toStopId'] as String?,
      timeSelection: TimeSelection.fromJson(
        json['timeSelection'] as Map<String, dynamic>,
      ),
      departureTime: DateTime.parse(json['departureTime'] as String),
      arrivalTime: DateTime.parse(json['arrivalTime'] as String),
      savedAt: DateTime.parse(json['savedAt'] as String),
      isDirect: isDirect,
      itineraryJson: itineraryJson,
      liveUpdatedAt: switch (json['liveUpdatedAt']) {
        final String at => DateTime.tryParse(at),
        _ => null,
      },
    );
  }
}
