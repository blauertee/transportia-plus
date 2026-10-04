import '../../models/transitous/enums.dart';
import '../query.dart';

/// A stop to route through, with how long to stay there.
class ViaStop {
  const ViaStop({required this.stopId, this.minimumStay = Duration.zero});

  /// Feed-prefixed stop id, e.g. `de-DELFI_de:11000:900100003`.
  ///
  /// A bare GTFS id is rejected with `unknown feed id ""`. Geocode results
  /// already carry the prefixed form.
  final String stopId;

  /// Zero means the itinerary may pass through without stopping.
  final Duration minimumStay;
}

/// Which vehicle to route lorry legs for.
///
/// Only meaningful with the `HGV` mode; MOTIS ignores these otherwise.
class VehicleProfile {
  const VehicleProfile({
    this.height,
    this.width,
    this.length,
    this.weight,
    this.axleCount,
    this.axleLoad,
    this.topSpeed,
    this.hazmat,
    this.hazmatWater,
    this.trailer,
    this.lezAccess,
  });

  /// Metres.
  final double? height;
  final double? width;
  final double? length;

  /// Tonnes.
  final double? weight;

  final int? axleCount;

  /// Tonnes per axle.
  final double? axleLoad;

  /// km/h.
  final double? topSpeed;

  /// Carrying dangerous goods, which closes some roads and tunnels.
  final bool? hazmat;

  /// Carrying goods hazardous to water, which closes water-protection areas.
  final bool? hazmatWater;

  final bool? trailer;

  /// Permitted to enter low-emission zones.
  final bool? lezAccess;

  bool get isEmpty =>
      height == null &&
      width == null &&
      length == null &&
      weight == null &&
      axleCount == null &&
      axleLoad == null &&
      topSpeed == null &&
      hazmat == null &&
      hazmatWater == null &&
      trailer == null &&
      lezAccess == null;

  Map<String, String?> toQuery() => {
    'vehicleHeight': Q.number(height),
    'vehicleWidth': Q.number(width),
    'vehicleLength': Q.number(length),
    'vehicleWeight': Q.number(weight),
    'vehicleAxleCount': Q.integer(axleCount),
    'vehicleAxleLoad': Q.number(axleLoad),
    'vehicleTopSpeed': Q.number(topSpeed),
    'vehicleHazmat': Q.boolean(hazmat),
    'vehicleHazmatWater': Q.boolean(hazmatWater),
    'vehicleTrailer': Q.boolean(trailer),
    'vehicleLezAccess': Q.boolean(lezAccess),
  };
}

/// Which shared vehicles may be used for one part of a journey.
///
/// The same five filters exist for the direct, pre-transit and post-transit
/// portions; [prefix] picks which set of parameter names to emit.
class RentalFilters {
  const RentalFilters({
    this.formFactors = const [],
    this.propulsionTypes = const [],
    this.providers = const [],
    this.providerGroups = const [],
    this.ignoreReturnConstraints,
  });

  final List<RentalFormFactor> formFactors;
  final List<RentalPropulsionType> propulsionTypes;

  /// Provider ids, e.g. `de-NextbikeBerlin`.
  final List<String> providers;

  /// Provider group ids, e.g. `nextbike Berlin`.
  final List<String> providerGroups;

  /// Allow itineraries that drop a vehicle somewhere the provider does not
  /// permit. Useful for exploring options, not for a bookable trip.
  final bool? ignoreReturnConstraints;

  bool get isEmpty =>
      formFactors.isEmpty &&
      propulsionTypes.isEmpty &&
      providers.isEmpty &&
      providerGroups.isEmpty &&
      ignoreReturnConstraints == null;

  /// [prefix] is `direct`, `preTransit` or `postTransit`.
  Map<String, String?> toQuery(String prefix) {
    final capitalised = prefix[0].toUpperCase() + prefix.substring(1);
    return {
      '${prefix}RentalFormFactors': Q.csv(formFactors.map((f) => f.wireName)),
      '${prefix}RentalPropulsionTypes': Q.csv(
        propulsionTypes.map((p) => p.wireName),
      ),
      '${prefix}RentalProviders': Q.csv(providers),
      '${prefix}RentalProviderGroups': Q.csv(providerGroups),
      'ignore${capitalised}RentalReturnConstraints': Q.boolean(
        ignoreReturnConstraints,
      ),
    };
  }
}

/// Every parameter `/plan` accepts.
///
/// Null means "leave it out and let the server decide", so the defaults
/// documented on each field are MOTIS's, not values this class sends. That
/// matters because the server's defaults change between versions and a
/// hardcoded copy would silently pin old behaviour.
class PlanParams {
  const PlanParams({
    required this.fromPlace,
    required this.toPlace,
    this.radius,
    this.via = const [],
    this.time,
    this.arriveBy,
    this.searchWindow,
    this.timetableView,
    this.numItineraries,
    this.maxItineraries,
    this.pageCursor,
    this.maxTransfers,
    this.maxTravelTime,
    this.minTransferTime,
    this.additionalTransferTime,
    this.transferTimeFactor,
    this.maxMatchingDistance,
    this.pedestrianProfile,
    this.pedestrianSpeed,
    this.cyclingSpeed,
    this.elevationCosts,
    this.vehicle = const VehicleProfile(),
    this.useRoutedTransfers,
    this.detailedTransfers,
    this.detailedLegs,
    this.joinInterlinedLegs,
    this.transitModes = const [],
    this.directModes = const [],
    this.preTransitModes = const [],
    this.postTransitModes = const [],
    this.directRentals = const RentalFilters(),
    this.preTransitRentals = const RentalFilters(),
    this.postTransitRentals = const RentalFilters(),
    this.requireBikeTransport,
    this.requireCarTransport,
    this.noCompulsoryReservation,
    this.maxPreTransitTime,
    this.maxPostTransitTime,
    this.maxDirectTime,
    this.fastestDirectFactor,
    this.slowDirect,
    this.fastestSlowDirectFactor,
    this.timeout,
    this.passengers,
    this.luggage,
    this.withFares,
    this.numLegAlternatives,
    this.withScheduledSkippedStops,
    this.realtimeMode,
    this.languages = const [],
    this.algorithm,
  });

  /// `lat,lon` or a stop id. Placeholder names `START`/`END` come back on
  /// legs when a plain coordinate was given.
  final String fromPlace;
  final String toPlace;

  /// Metres to search around [fromPlace] and [toPlace] for a matching stop.
  final double? radius;

  /// Stops to route through, in order.
  final List<ViaStop> via;

  /// Departure time, or arrival time when [arriveBy] is set. Defaults to now.
  final DateTime? time;
  final bool? arriveBy;

  /// How far past [time] to search for departures. Ignored when
  /// [timetableView] is false.
  final Duration? searchWindow;

  /// True returns a timetable-like set of departures; false returns only the
  /// itineraries optimal at [time]. MOTIS defaults to true.
  final bool? timetableView;

  /// Minimum itineraries to return before the search stops. MOTIS default 5.
  final int? numItineraries;

  /// Hard cap on returned itineraries.
  final int? maxItineraries;

  /// Cursor from a previous response, for paging earlier or later.
  final String? pageCursor;

  final int? maxTransfers;
  final Duration? maxTravelTime;

  /// Floor applied to every transfer.
  final Duration? minTransferTime;

  /// Added to every transfer on top of the feed's own time — the buffer a
  /// rider wants for comfort.
  final Duration? additionalTransferTime;

  /// Multiplies transfer times; above 1.0 favours itineraries with roomier
  /// connections.
  final double? transferTimeFactor;

  /// Metres to search for a street to snap a coordinate onto.
  final double? maxMatchingDistance;

  /// `WHEELCHAIR` restricts street legs to step-free paths.
  final PedestrianProfile? pedestrianProfile;

  /// Metres per second. The Transitous UI shows this as km/h.
  final double? pedestrianSpeed;

  /// Metres per second.
  final double? cyclingSpeed;

  /// Penalty for inclines. Requires a server with elevation data.
  final ElevationCosts? elevationCosts;

  /// Lorry dimensions, for `HGV` legs.
  final VehicleProfile vehicle;

  /// Route transfers over the street network instead of using the feed's
  /// transfer times. Requires a server with routed transfers.
  final bool? useRoutedTransfers;

  /// Include the full transfer path in the response.
  final bool? detailedTransfers;

  /// Include turn-by-turn steps on street legs. MOTIS defaults to true.
  final bool? detailedLegs;

  /// Merge consecutive legs of the same physical vehicle. MOTIS defaults to
  /// true.
  final bool? joinInterlinedLegs;

  /// Transit modes allowed. Empty leaves the server default (all of them).
  final List<TransitMode> transitModes;

  /// Modes allowed for a direct, transit-free itinerary.
  final List<TransitMode> directModes;

  /// Modes allowed to reach the first stop.
  final List<TransitMode> preTransitModes;

  /// Modes allowed from the last stop.
  final List<TransitMode> postTransitModes;

  final RentalFilters directRentals;
  final RentalFilters preTransitRentals;
  final RentalFilters postTransitRentals;

  /// Only itineraries whose vehicles carry bikes.
  final bool? requireBikeTransport;

  /// Only itineraries whose vehicles carry cars.
  final bool? requireCarTransport;

  /// Exclude services that require a reservation.
  final bool? noCompulsoryReservation;

  /// Budget for reaching the first stop. Capped by the server's
  /// `maxPrePostTransitTimeLimit`.
  final Duration? maxPreTransitTime;

  /// Budget from the last stop, capped the same way.
  final Duration? maxPostTransitTime;

  /// Budget for a direct itinerary. Capped by `maxDirectTimeLimit`.
  final Duration? maxDirectTime;

  /// Discards direct itineraries longer than this multiple of the fastest one.
  final double? fastestDirectFactor;

  /// Also compute slow direct connections, e.g. walking a distance most
  /// riders would not.
  final bool? slowDirect;
  final double? fastestSlowDirectFactor;

  /// Server-side search timeout.
  final Duration? timeout;

  /// Party size, used by demand-responsive services.
  final int? passengers;
  final int? luggage;

  /// Include ticket prices. The app's fare display depends on this.
  final bool? withFares;

  /// How many stand-in connections to attach to each ride; see
  /// `Leg.alternatives`.
  final int? numLegAlternatives;

  /// Include stops the vehicle skips, rather than omitting them.
  final bool? withScheduledSkippedStops;

  /// Whether real-time data affects routing, annotation only, or neither.
  final RealtimeMode? realtimeMode;

  /// Preferred languages for translated names, most preferred first.
  final List<String> languages;

  /// Routing algorithm. MOTIS defaults to `PONG`; `RAPTOR` is the alternative
  /// and is markedly slower.
  final String? algorithm;

  PlanParams copyWith({String? pageCursor, DateTime? time, bool? arriveBy}) =>
      PlanParams(
        fromPlace: fromPlace,
        toPlace: toPlace,
        radius: radius,
        via: via,
        time: time ?? this.time,
        arriveBy: arriveBy ?? this.arriveBy,
        searchWindow: searchWindow,
        timetableView: timetableView,
        numItineraries: numItineraries,
        maxItineraries: maxItineraries,
        pageCursor: pageCursor ?? this.pageCursor,
        maxTransfers: maxTransfers,
        maxTravelTime: maxTravelTime,
        minTransferTime: minTransferTime,
        additionalTransferTime: additionalTransferTime,
        transferTimeFactor: transferTimeFactor,
        maxMatchingDistance: maxMatchingDistance,
        pedestrianProfile: pedestrianProfile,
        pedestrianSpeed: pedestrianSpeed,
        cyclingSpeed: cyclingSpeed,
        elevationCosts: elevationCosts,
        vehicle: vehicle,
        useRoutedTransfers: useRoutedTransfers,
        detailedTransfers: detailedTransfers,
        detailedLegs: detailedLegs,
        joinInterlinedLegs: joinInterlinedLegs,
        transitModes: transitModes,
        directModes: directModes,
        preTransitModes: preTransitModes,
        postTransitModes: postTransitModes,
        directRentals: directRentals,
        preTransitRentals: preTransitRentals,
        postTransitRentals: postTransitRentals,
        requireBikeTransport: requireBikeTransport,
        requireCarTransport: requireCarTransport,
        noCompulsoryReservation: noCompulsoryReservation,
        maxPreTransitTime: maxPreTransitTime,
        maxPostTransitTime: maxPostTransitTime,
        maxDirectTime: maxDirectTime,
        fastestDirectFactor: fastestDirectFactor,
        slowDirect: slowDirect,
        fastestSlowDirectFactor: fastestSlowDirectFactor,
        timeout: timeout,
        passengers: passengers,
        luggage: luggage,
        withFares: withFares,
        numLegAlternatives: numLegAlternatives,
        withScheduledSkippedStops: withScheduledSkippedStops,
        realtimeMode: realtimeMode,
        languages: languages,
        algorithm: algorithm,
      );

  Map<String, String?> toQuery() => {
    'fromPlace': fromPlace,
    'toPlace': toPlace,
    'radius': Q.number(radius),
    'via': Q.csv(via.map((v) => v.stopId)),
    // Positional: the nth stay applies to the nth via stop, so this is only
    // sent when there are via stops to align it with.
    'viaMinimumStay': via.isEmpty
        ? null
        : Q.csvNum(via.map((v) => v.minimumStay.inMinutes)),
    'time': Q.dateTime(time),
    'arriveBy': Q.boolean(arriveBy),
    'searchWindow': Q.seconds(searchWindow),
    'timetableView': Q.boolean(timetableView),
    'numItineraries': Q.integer(numItineraries),
    'maxItineraries': Q.integer(maxItineraries),
    'pageCursor': pageCursor,
    'maxTransfers': Q.integer(maxTransfers),
    'maxTravelTime': Q.minutes(maxTravelTime),
    'minTransferTime': Q.minutes(minTransferTime),
    'additionalTransferTime': Q.minutes(additionalTransferTime),
    'transferTimeFactor': Q.number(transferTimeFactor),
    'maxMatchingDistance': Q.number(maxMatchingDistance),
    'pedestrianProfile': pedestrianProfile?.wireName,
    'pedestrianSpeed': Q.number(pedestrianSpeed),
    'cyclingSpeed': Q.number(cyclingSpeed),
    'elevationCosts': elevationCosts?.wireName,
    ...vehicle.toQuery(),
    'useRoutedTransfers': Q.boolean(useRoutedTransfers),
    'detailedTransfers': Q.boolean(detailedTransfers),
    'detailedLegs': Q.boolean(detailedLegs),
    'joinInterlinedLegs': Q.boolean(joinInterlinedLegs),
    'transitModes': Q.csv(transitModes.map((m) => m.wireName)),
    'directModes': Q.csv(directModes.map((m) => m.wireName)),
    'preTransitModes': Q.csv(preTransitModes.map((m) => m.wireName)),
    'postTransitModes': Q.csv(postTransitModes.map((m) => m.wireName)),
    ...directRentals.toQuery('direct'),
    ...preTransitRentals.toQuery('preTransit'),
    ...postTransitRentals.toQuery('postTransit'),
    'requireBikeTransport': Q.boolean(requireBikeTransport),
    'requireCarTransport': Q.boolean(requireCarTransport),
    'noCompulsoryReservation': Q.boolean(noCompulsoryReservation),
    'maxPreTransitTime': Q.seconds(maxPreTransitTime),
    'maxPostTransitTime': Q.seconds(maxPostTransitTime),
    'maxDirectTime': Q.seconds(maxDirectTime),
    'fastestDirectFactor': Q.number(fastestDirectFactor),
    'slowDirect': Q.boolean(slowDirect),
    'fastestSlowDirectFactor': Q.number(fastestSlowDirectFactor),
    'timeout': Q.seconds(timeout),
    'passengers': Q.integer(passengers),
    'luggage': Q.integer(luggage),
    'withFares': Q.boolean(withFares),
    'numLegAlternatives': Q.integer(numLegAlternatives),
    'withScheduledSkippedStops': Q.boolean(withScheduledSkippedStops),
    'realtimeMode': realtimeMode?.wireName,
    'language': Q.csv(languages),
    'algorithm': algorithm,
  };
}
