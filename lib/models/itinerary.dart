import 'dart:developer' as developer;

import 'transitous/alert.dart';
import 'transitous/enums.dart';
import 'transitous/json.dart';
import 'transitous/leg_details.dart';
import 'transitous/place.dart';
import 'transitous/rental.dart';
import 'transitous/step_instruction.dart';
import '../utils/duration_formatter.dart';

export 'transitous/alert.dart' show Alert;
export 'transitous/enums.dart';
export 'transitous/leg_details.dart' show Category, TicketUrls;
export 'transitous/place.dart' show TransitPlace;
export 'transitous/rental.dart' show Rental, RentalVehicleType;
export 'transitous/step_instruction.dart' show StepInstruction;

/// A stop a leg passes through without the rider boarding or alighting.
///
/// MOTIS returns the same `Place` object here as for leg endpoints, so this is
/// an alias rather than a separate model.
typedef IntermediateStop = TransitPlace;

class FareInfo {
  final double amount;
  final String currency;

  FareInfo({required this.amount, required this.currency});

  factory FareInfo.fromJson(Map<String, dynamic> json) {
    return FareInfo(
      amount: json['amount']?.toDouble() ?? 0.0,
      currency: json['currency'] ?? '',
    );
  }
}

class TicketProduct {
  final String name;
  final double amount;
  final String currency;
  final String? fareMediaName;
  final String? fareMediaType;

  TicketProduct({
    required this.name,
    required this.amount,
    required this.currency,
    this.fareMediaName,
    this.fareMediaType,
  });

  factory TicketProduct.fromJson(Map<String, dynamic> json) {
    final media = json['media'];
    final Map<String, dynamic> mediaMap = media is Map<String, dynamic>
        ? media
        : {};
    return TicketProduct(
      name: json['name'] ?? '',
      amount: json['amount']?.toDouble() ?? 0.0,
      currency: json['currency'] ?? '',
      fareMediaName: mediaMap['fareMediaName'],
      fareMediaType: mediaMap['fareMediaType'],
    );
  }
}

class FareOption {
  final List<TicketProduct> products;

  FareOption({required this.products});

  factory FareOption.fromJson(List<dynamic> json) {
    return FareOption(
      products: json
          .whereType<Map<String, dynamic>>()
          .map((p) => TicketProduct.fromJson(p))
          .toList(),
    );
  }
}

class RouteBadge {
  final String name;
  final String? routeColor;
  final String? routeTextColor;

  RouteBadge({required this.name, this.routeColor, this.routeTextColor});
}

class FareLegInfo {
  final List<RouteBadge> routeBadges;
  final List<FareOption> options;

  /// A deep link straight to buying this fare, when the agency exposes one
  /// (GTFS `ticketUrls`). Preferred to [fareUrl] wherever both exist.
  final String? ticketUrl;

  /// The agency's general fare-information page (GTFS `agencyFareUrl`), shown
  /// only when there is no more specific [ticketUrl].
  final String? fareUrl;

  FareLegInfo({
    required this.routeBadges,
    required this.options,
    this.ticketUrl,
    this.fareUrl,
  });

  String get _optionsKey => options
      .map(
        (o) => o.products
            .map(
              (p) =>
                  '${p.name}|${p.amount}|${p.currency}|${p.fareMediaName}|${p.fareMediaType}',
            )
            .join(','),
      )
      .join(';');
}

class EncodedPolyline {
  final String points;
  final int precision;
  final int length;

  EncodedPolyline({
    required this.points,
    required this.precision,
    required this.length,
  });

  factory EncodedPolyline.fromJson(Map<String, dynamic> json) {
    return EncodedPolyline(
      points: json['points'] ?? '',
      precision: json['precision'] ?? 5,
      length: json['length'] ?? 0,
    );
  }
}

class Itinerary {
  final int duration;
  final DateTime startTime;
  final DateTime endTime;
  final int transfers;

  /// Opaque handle identifying this exact itinerary, used to refresh it in a
  /// single request via `/refresh-itinerary`.
  ///
  /// Runs to roughly 1.3 KB, which is why the refresh call uses POST. Null for
  /// itineraries parsed from a snapshot saved before the app started reading
  /// this field.
  final String? id;
  final List<Leg> legs;
  final bool isDirect;
  final FareInfo? fare;
  final List<FareLegInfo> ticketInfo;

  /// The raw API object this itinerary was parsed from, kept so the
  /// itinerary can be persisted and re-parsed without hand-written
  /// serializers for the whole model tree. Null for itineraries that were
  /// not built from an API response.
  ///
  /// This is always the *planned* snapshot: [withLegs] carries it over
  /// unchanged, so a real-time refresh does not rewrite it. That is
  /// deliberate — live times are re-derived on load, and the schedule is
  /// what is worth storing.
  final Map<String, dynamic>? sourceJson;

  Itinerary({
    required this.duration,
    required this.startTime,
    required this.endTime,
    required this.transfers,
    required this.legs,
    this.id,
    this.isDirect = false,
    this.fare,
    this.ticketInfo = const [],
    this.sourceJson,
  });

  bool get hasTicketInfo => ticketInfo.isNotEmpty;

  /// Whether any leg is a ride on a scheduled service. Walking, cycling and
  /// shared vehicles carry no trip id.
  bool get hasTransit => legs.any((leg) => leg.isRide);

  /// The street legs before the first ride: the way to the first station, on
  /// foot, by bike or on a shared vehicle (a walk to it, the ride, a walk on).
  ///
  /// This is the stretch the planner calls the pre-transit offset, and which a
  /// refresh has to find again. Empty when the journey starts on a ride or has
  /// none at all.
  List<Leg> get firstMileLegs {
    final firstRide = legs.indexWhere((leg) => leg.isRide);
    return firstRide <= 0 ? const [] : legs.sublist(0, firstRide);
  }

  /// The street legs after the last ride, as [firstMileLegs] at the other end.
  List<Leg> get lastMileLegs {
    final lastRide = legs.lastIndexWhere((leg) => leg.isRide);
    if (lastRide < 0 || lastRide == legs.length - 1) return const [];
    return legs.sublist(lastRide + 1);
  }

  /// Returns a copy of this itinerary with [newLegs] substituted in,
  /// recomputing the fields derived from the leg list (e.g. after a
  /// real-time refresh updates individual legs).
  Itinerary withLegs(List<Leg> newLegs) {
    if (newLegs.isEmpty) return this;
    final transitLegCount = newLegs.where((l) => l.mode != 'WALK').length;
    return Itinerary(
      duration: newLegs.last.endTime
          .difference(newLegs.first.startTime)
          .inSeconds,
      startTime: newLegs.first.startTime,
      endTime: newLegs.last.endTime,
      transfers: transitLegCount > 0 ? transitLegCount - 1 : 0,
      legs: newLegs,
      id: id,
      isDirect: isDirect,
      fare: fare,
      ticketInfo: ticketInfo,
      sourceJson: sourceJson,
    );
  }

  double get walkingDistance {
    double totalDistance = 0.0;
    for (final leg in legs) {
      if (leg.mode == 'WALK' && leg.distance != null) {
        totalDistance += leg.distance!;
      }
    }
    return totalDistance;
  }

  /// Rule-of-thumb energy cost of walking a kilometre, for an average adult
  /// at an average pace. A real figure would need the traveller's weight and
  /// stride, which the app does not ask for.
  static const double _caloriesPerWalkedKilometre = 50;

  int get calories {
    final walkingKm = walkingDistance / kMetresPerKilometre;
    return (walkingKm * _caloriesPerWalkedKilometre).round();
  }

  factory Itinerary.fromJson(
    Map<String, dynamic> json, {
    bool isDirect = false,
  }) {
    final legs = (json['legs'] as List)
        .map((leg) => Leg.fromJson(leg))
        .toList();

    FareInfo? fare;
    var ticketInfo = <FareLegInfo>[];
    if (json['fareTransfers'] != null &&
        (json['fareTransfers'] as List).isNotEmpty) {
      final fareTransfer = (json['fareTransfers'] as List).first;
      if (fareTransfer['transferProducts'] != null &&
          (fareTransfer['transferProducts'] as List).isNotEmpty) {
        fare = FareInfo.fromJson(
          (fareTransfer['transferProducts'] as List).first,
        );
      }

      try {
        final routeBadgesByFareLeg = <String, List<RouteBadge>>{};
        // A leg's own ticketing deep link is preferred to its agency's
        // general fare page. Both are keyed like the badges above, so they
        // land on the same fare leg below.
        final ticketUrlByFareLeg = <String, String>{};
        final fareUrlByFareLeg = <String, String>{};
        for (final leg in legs) {
          if (leg.fareTransferIndex == null ||
              leg.effectiveFareLegIndex == null) {
            continue;
          }
          final key = '${leg.fareTransferIndex}:${leg.effectiveFareLegIndex}';
          final ticketUrl = leg.ticketUrls?.web;
          if (ticketUrl != null && ticketUrl.isNotEmpty) {
            ticketUrlByFareLeg.putIfAbsent(key, () => ticketUrl);
          }
          final fareUrl = leg.agencyFareUrl;
          if (fareUrl != null && fareUrl.isNotEmpty) {
            fareUrlByFareLeg.putIfAbsent(key, () => fareUrl);
          }

          final name = leg.routeShortName ?? leg.displayName;
          if (name == null || name.isEmpty) continue;
          final badges = routeBadgesByFareLeg.putIfAbsent(key, () => []);
          if (!badges.any((b) => b.name == name)) {
            badges.add(
              RouteBadge(
                name: name,
                routeColor: leg.routeColor,
                routeTextColor: leg.routeTextColor,
              ),
            );
          }
        }

        final rawTicketInfo = <FareLegInfo>[];
        final transfers = json['fareTransfers'] as List;
        for (var t = 0; t < transfers.length; t++) {
          final legProducts = transfers[t]['effectiveFareLegProducts'];
          if (legProducts is! List) continue;
          for (var i = 0; i < legProducts.length; i++) {
            final legOptions = legProducts[i];
            if (legOptions is! List) continue;
            final options = legOptions
                .whereType<List<dynamic>>()
                .map((o) => FareOption.fromJson(o))
                .where((o) => o.products.isNotEmpty)
                .toList();
            if (options.isEmpty) continue;
            final key = '$t:$i';
            rawTicketInfo.add(
              FareLegInfo(
                routeBadges: routeBadgesByFareLeg[key] ?? const [],
                options: options,
                ticketUrl: ticketUrlByFareLeg[key],
                fareUrl: fareUrlByFareLeg[key],
              ),
            );
          }
        }

        // Merge fare legs that share identical ticket options.
        final mergedByKey = <String, FareLegInfo>{};
        final order = <String>[];
        for (final entry in rawTicketInfo) {
          final key = entry._optionsKey;
          final existing = mergedByKey[key];
          if (existing == null) {
            mergedByKey[key] = entry;
            order.add(key);
          } else {
            final combinedBadges = [...existing.routeBadges];
            for (final badge in entry.routeBadges) {
              if (!combinedBadges.any((b) => b.name == badge.name)) {
                combinedBadges.add(badge);
              }
            }
            mergedByKey[key] = FareLegInfo(
              routeBadges: combinedBadges,
              options: existing.options,
              ticketUrl: existing.ticketUrl ?? entry.ticketUrl,
              fareUrl: existing.fareUrl ?? entry.fareUrl,
            );
          }
        }
        ticketInfo = order.map((key) => mergedByKey[key]!).toList();
      } catch (e, stackTrace) {
        developer.log(
          'Error parsing ticket info',
          name: 'Itinerary',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }

    return Itinerary(
      duration: asInt(json['duration']) ?? 0,
      startTime: DateTime.parse(json['startTime']),
      endTime: DateTime.parse(json['endTime']),
      transfers: asInt(json['transfers']) ?? 0,
      legs: legs,
      id: asString(json['id']),
      isDirect: isDirect,
      fare: fare,
      ticketInfo: ticketInfo,
      sourceJson: json,
    );
  }
}

class Leg {
  /// Travel mode as returned by the API. Kept as a string because the app
  /// compares it against feed-specific values in several places; use
  /// [transitMode] for the typed form.
  final String mode;

  /// Where the leg starts and ends. MOTIS returns a full `Place` here, so
  /// times, tracks, alerts and flex windows all live on these.
  final TransitPlace from;
  final TransitPlace to;

  final DateTime startTime;
  final DateTime endTime;
  final DateTime? scheduledStartTime;
  final DateTime? scheduledEndTime;
  final int duration;
  final double? distance;

  /// True when this leg is backed by real-time data.
  final bool realTime;

  /// True when the leg exists in the published schedule, as opposed to being
  /// an added or unscheduled service.
  final bool scheduled;

  final String? routeShortName;
  final String? routeLongName;
  final String? displayName;
  final String? headsign;
  final String? routeId;
  final String? routeUrl;
  final String? routeColor;
  final String? routeTextColor;
  final int? routeType;

  /// GTFS direction the trip runs in, used to tell the two ends of a line
  /// apart.
  final String? directionId;

  final String? agencyName;
  final String? agencyUrl;
  final String? agencyFareUrl;
  final String? agencyId;
  final String? tripId;
  final String? tripShortName;

  /// First and last stop of the whole trip, which usually extend beyond this
  /// leg. Useful for showing where a service starts and terminates.
  final TransitPlace? tripFrom;
  final TransitPlace? tripTo;

  /// Vehicle category, e.g. `IC` / `InterCity`. NeTEx datasets only.
  final Category? category;

  /// Dataset the leg came from, for attribution.
  final String? source;

  final bool cancelled;
  final List<IntermediateStop> intermediateStops;
  final List<Alert> alerts;
  final EncodedPolyline? legGeometry;

  /// Turn-by-turn instructions for street legs, when detailed legs are
  /// requested.
  final List<StepInstruction> steps;

  /// Vehicle-sharing details, set on `RENTAL` legs.
  final Rental? rental;

  /// Other departures serving the same connection, when leg alternatives are
  /// requested.
  final List<Leg> alternatives;

  final bool interlineWithPreviousLeg;
  final int? fareTransferIndex;
  final int? effectiveFareLegIndex;

  /// Set when the trip repeats on a looped calendar; the value is the date the
  /// loop started, meaning the times are extrapolated rather than published.
  final DateTime? loopedCalendarSince;

  final bool? bikesAllowed;
  final WheelchairAccessibility? wheelchairAccessible;

  /// Whether boarding requires a reservation.
  final Reservation? reservation;

  final TicketUrls? ticketUrls;

  Leg({
    required this.mode,
    required this.from,
    required this.to,
    required this.startTime,
    required this.endTime,
    required this.duration,
    this.scheduledStartTime,
    this.scheduledEndTime,
    this.distance,
    this.realTime = false,
    this.scheduled = true,
    this.routeShortName,
    this.routeLongName,
    this.displayName,
    this.headsign,
    this.routeId,
    this.routeUrl,
    this.routeColor,
    this.routeTextColor,
    this.routeType,
    this.directionId,
    this.agencyName,
    this.agencyUrl,
    this.agencyFareUrl,
    this.agencyId,
    this.tripId,
    this.tripShortName,
    this.tripFrom,
    this.tripTo,
    this.category,
    this.source,
    this.cancelled = false,
    this.intermediateStops = const [],
    this.alerts = const [],
    this.legGeometry,
    this.steps = const [],
    this.rental,
    this.alternatives = const [],
    this.interlineWithPreviousLeg = false,
    this.fareTransferIndex,
    this.effectiveFareLegIndex,
    this.loopedCalendarSince,
    this.bikesAllowed,
    this.wheelchairAccessible,
    this.reservation,
    this.ticketUrls,
  });

  /// Typed form of [mode]; null when the server sends a mode this build does
  /// not know.
  TransitMode? get transitMode => TransitMode.fromWire(mode);

  /// A ride on a scheduled service, which is what carries a trip id. Street
  /// legs and shared vehicles have none.
  bool get isRide => tripId?.isNotEmpty ?? false;

  String get fromName => from.name;
  String get toName => to.name;
  double get fromLat => from.lat;
  double get fromLon => from.lon;
  double get toLat => to.lat;
  double get toLon => to.lon;
  String? get fromStopId => from.stopId;
  String? get toStopId => to.stopId;
  String? get fromTrack => from.track;
  String? get toTrack => to.track;
  String? get fromScheduledTrack => from.scheduledTrack;
  String? get toScheduledTrack => to.scheduledTrack;

  /// Returns a copy of this leg with the real-time fields (times, delay,
  /// cancellation, track, intermediate stops, alerts) refreshed from
  /// [fresh], while keeping itinerary-specific context (fare indices,
  /// geometry) from this leg.
  Leg withRealTimeFrom(Leg fresh) {
    return Leg(
      mode: mode,
      from: from.mergeRealTime(fresh.from),
      to: to.mergeRealTime(fresh.to),
      startTime: fresh.startTime,
      endTime: fresh.endTime,
      scheduledStartTime: fresh.scheduledStartTime ?? scheduledStartTime,
      scheduledEndTime: fresh.scheduledEndTime ?? scheduledEndTime,
      duration: fresh.duration,
      distance: distance,
      realTime: fresh.realTime,
      scheduled: fresh.scheduled,
      routeShortName: routeShortName,
      routeLongName: routeLongName,
      displayName: displayName,
      headsign: headsign,
      routeId: routeId,
      routeUrl: routeUrl,
      routeColor: routeColor,
      routeTextColor: routeTextColor,
      routeType: routeType,
      directionId: directionId,
      agencyName: agencyName,
      agencyUrl: agencyUrl,
      agencyFareUrl: agencyFareUrl,
      agencyId: agencyId,
      tripId: tripId,
      tripShortName: tripShortName,
      tripFrom: fresh.tripFrom ?? tripFrom,
      tripTo: fresh.tripTo ?? tripTo,
      category: category,
      source: source,
      cancelled: fresh.cancelled,
      intermediateStops: fresh.intermediateStops.isNotEmpty
          ? fresh.intermediateStops
          : intermediateStops,
      alerts: fresh.alerts.isNotEmpty ? fresh.alerts : alerts,
      legGeometry: legGeometry,
      steps: steps,
      rental: rental,
      alternatives: fresh.alternatives.isNotEmpty
          ? fresh.alternatives
          : alternatives,
      interlineWithPreviousLeg: interlineWithPreviousLeg,
      fareTransferIndex: fareTransferIndex,
      effectiveFareLegIndex: effectiveFareLegIndex,
      loopedCalendarSince: fresh.loopedCalendarSince ?? loopedCalendarSince,
      bikesAllowed: bikesAllowed,
      wheelchairAccessible: wheelchairAccessible,
      reservation: reservation,
      ticketUrls: ticketUrls,
    );
  }

  /// The part of this leg that [from] → [to] actually travels.
  ///
  /// `/trip` answers with the service end to end — the S7 from Ahrensfelde to
  /// Potsdam — whatever slice of it a journey uses. Taken whole it put every
  /// station on the line into an expanded leg, and moved the leg's own
  /// departure to the start of the line.
  ///
  /// Returns this leg untouched when either endpoint is not on it. A wrong
  /// slice is worse than an unsliced one: the times would then belong to
  /// somewhere the traveller never goes.
  Leg sliceBetween(TransitPlace from, TransitPlace to) {
    final sequence = [this.from, ...intermediateStops, this.to];

    final start = sequence.indexWhere((place) => _samePlace(place, from));
    if (start < 0) return this;

    // Searched backwards: a line that calls at a stop twice — a loop, or a
    // service that reverses — should give the later visit, or the slice
    // would end before it began.
    var end = -1;
    for (var i = sequence.length - 1; i > start; i--) {
      if (_samePlace(sequence[i], to)) {
        end = i;
        break;
      }
    }
    if (end < 0) return this;
    if (start == 0 && end == sequence.length - 1) return this;

    final origin = sequence[start];
    final destination = sequence[end];
    final departs = origin.timeAtStop ?? startTime;
    final arrives = destination.timeAtTerminus ?? endTime;

    return Leg(
      mode: mode,
      from: origin,
      to: destination,
      startTime: departs,
      endTime: arrives,
      scheduledStartTime: origin.scheduledDeparture ?? scheduledStartTime,
      scheduledEndTime: destination.scheduledArrival ?? scheduledEndTime,
      duration: arrives.difference(departs).inSeconds,
      distance: distance,
      realTime: realTime,
      scheduled: scheduled,
      routeShortName: routeShortName,
      routeLongName: routeLongName,
      displayName: displayName,
      headsign: headsign,
      routeId: routeId,
      routeUrl: routeUrl,
      routeColor: routeColor,
      routeTextColor: routeTextColor,
      routeType: routeType,
      directionId: directionId,
      agencyName: agencyName,
      agencyUrl: agencyUrl,
      agencyFareUrl: agencyFareUrl,
      agencyId: agencyId,
      tripId: tripId,
      tripShortName: tripShortName,
      // The whole service either side of the slice, which is exactly what
      // these two are for.
      tripFrom: tripFrom ?? sequence.first,
      tripTo: tripTo ?? sequence.last,
      category: category,
      source: source,
      cancelled: cancelled,
      intermediateStops: sequence.sublist(start + 1, end),
      alerts: alerts,
      legGeometry: legGeometry,
      steps: steps,
      rental: rental,
      alternatives: alternatives,
      interlineWithPreviousLeg: interlineWithPreviousLeg,
      fareTransferIndex: fareTransferIndex,
      effectiveFareLegIndex: effectiveFareLegIndex,
      loopedCalendarSince: loopedCalendarSince,
      bikesAllowed: bikesAllowed,
      wheelchairAccessible: wheelchairAccessible,
      reservation: reservation,
      ticketUrls: ticketUrls,
    );
  }

  /// Whether two places are the same station.
  ///
  /// A stop id may name a platform (`…:900170004:2:52`) where the other side
  /// names the station (`…:900170004`), so the parent counts as an id too.
  /// Names decide it when no id matches, which is what makes two platforms of
  /// one station meet.
  static bool _samePlace(TransitPlace a, TransitPlace b) {
    Set<String> keys(TransitPlace p) => {
      for (final key in [p.stopId, p.parentId])
        if (key != null && key.isNotEmpty) key,
    };

    final aKeys = keys(a);
    final bKeys = keys(b);
    if (aKeys.intersection(bKeys).isNotEmpty) return true;
    return a.name.isNotEmpty && a.name == b.name;
  }

  factory Leg.fromJson(Map<String, dynamic> json) {
    try {
      final legGeometry = asMap(json['legGeometry']);
      final tripFrom = asMap(json['tripFrom']);
      final tripTo = asMap(json['tripTo']);
      final category = asMap(json['category']);
      final rental = asMap(json['rental']);
      final ticketUrls = asMap(json['ticketUrls']);

      return Leg(
        mode: asString(json['mode']) ?? 'WALK',
        from: TransitPlace.fromJson(asMap(json['from']) ?? const {}),
        to: TransitPlace.fromJson(asMap(json['to']) ?? const {}),
        startTime: DateTime.parse(json['startTime']),
        endTime: DateTime.parse(json['endTime']),
        scheduledStartTime: asDateTime(json['scheduledStartTime']),
        scheduledEndTime: asDateTime(json['scheduledEndTime']),
        duration: asInt(json['duration']) ?? 0,
        distance: asDouble(json['distance']),
        realTime: asBool(json['realTime']) ?? false,
        scheduled: asBool(json['scheduled']) ?? true,
        routeShortName: asString(json['routeShortName']),
        routeLongName: asString(json['routeLongName']),
        displayName: asString(json['displayName']),
        headsign: asString(json['headsign']),
        routeId: asString(json['routeId']),
        routeUrl: asString(json['routeUrl']),
        routeColor: asString(json['routeColor']),
        routeTextColor: asString(json['routeTextColor']),
        routeType: asInt(json['routeType']),
        directionId: asString(json['directionId']),
        agencyName: asString(json['agencyName']),
        agencyUrl: asString(json['agencyUrl']),
        agencyFareUrl: asString(json['agencyFareUrl']),
        agencyId: asString(json['agencyId']),
        tripId: asString(json['tripId']),
        tripShortName: asString(json['tripShortName']),
        tripFrom: tripFrom == null ? null : TransitPlace.fromJson(tripFrom),
        tripTo: tripTo == null ? null : TransitPlace.fromJson(tripTo),
        category: category == null ? null : Category.fromJson(category),
        source: asString(json['source']),
        cancelled: asBool(json['cancelled']) ?? false,
        intermediateStops: asList(
          json['intermediateStops'],
          IntermediateStop.fromJson,
        ),
        alerts: asList(json['alerts'], Alert.fromJson),
        legGeometry: legGeometry == null || legGeometry.isEmpty
            ? null
            : EncodedPolyline.fromJson(legGeometry),
        steps: asList(json['steps'], StepInstruction.fromJson),
        rental: rental == null ? null : Rental.fromJson(rental),
        alternatives: asList(json['alternatives'], Leg.fromJson),
        interlineWithPreviousLeg:
            asBool(json['interlineWithPreviousLeg']) ?? false,
        fareTransferIndex: asInt(json['fareTransferIndex']),
        effectiveFareLegIndex: asInt(json['effectiveFareLegIndex']),
        loopedCalendarSince: asDateTime(json['loopedCalendarSince']),
        bikesAllowed: asBool(json['bikesAllowed']),
        wheelchairAccessible: WheelchairAccessibility.fromWire(
          json['wheelchairAccessible'],
        ),
        reservation: Reservation.fromWire(json['reservation']),
        ticketUrls: ticketUrls == null ? null : TicketUrls.fromJson(ticketUrls),
      );
    } catch (e, stackTrace) {
      developer.log(
        'Error parsing Leg',
        name: 'Itinerary',
        error: e,
        stackTrace: stackTrace,
      );
      developer.log('Leg JSON: $json', name: 'Itinerary');
      rethrow;
    }
  }
}
