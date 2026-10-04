import '../api/endpoints/trip_endpoint.dart';
import '../api/params/plan_params.dart';
import 'transit_mode_group.dart';
import 'transitous/enums.dart';

/// A stop the user wants the journey to pass through.
class ViaStopOption {
  const ViaStopOption({
    required this.stopId,
    required this.name,
    this.minimumStay = Duration.zero,
  });

  /// Feed-prefixed stop id, as the geocoder returns it. A bare GTFS id is
  /// rejected by the server.
  final String stopId;

  /// Shown in the UI; not sent to the server.
  final String name;

  /// Zero lets the journey pass through without stopping, which often finds
  /// better connections than requiring a wait.
  final Duration minimumStay;

  ViaStopOption copyWith({Duration? minimumStay}) => ViaStopOption(
    stopId: stopId,
    name: name,
    minimumStay: minimumStay ?? this.minimumStay,
  );

  Map<String, dynamic> toJson() => {
    'stopId': stopId,
    'name': name,
    'minimumStayMinutes': minimumStay.inMinutes,
  };

  static ViaStopOption? fromJson(Map<String, dynamic> json) {
    final stopId = json['stopId'];
    if (stopId is! String || stopId.isEmpty) return null;
    return ViaStopOption(
      stopId: stopId,
      name: json['name'] as String? ?? stopId,
      minimumStay: Duration(minutes: json['minimumStayMinutes'] as int? ?? 0),
    );
  }
}

/// The user's routing preferences, as offered by the Transit options screen.
///
/// Everything here maps onto a `/plan` parameter. Defaults match what the
/// server does when the parameter is absent, so an untouched configuration
/// produces the same query the app sent before these options existed.
class RoutingOptions {
  const RoutingOptions({
    this.transitModes = const [],
    this.useRoutedTransfers = true,
    this.wheelchairAccessibleOnly = false,
    this.bikeCarriageOverride,
    this.carCarriageOverride,
    this.noCompulsoryReservation = false,
    this.via = const [],
    this.maxTransfers,
    this.additionalTransferTime = Duration.zero,
    this.firstMileModes = const [TransitMode.walk],
    this.maxFirstMileTime = const Duration(minutes: 15),
    this.lastMileModes = const [TransitMode.walk],
    this.maxLastMileTime = const Duration(minutes: 15),
    this.firstMileRentalFormFactors = const [],
    this.lastMileRentalFormFactors = const [],
    this.lastMileSameAsFirst = false,
    this.walkingSpeedKmh = _defaultWalkingSpeedKmh,
    this.cyclingSpeedKmh = _defaultCyclingSpeedKmh,
    this.elevationCosts = ElevationCosts.none,
  });

  /// MOTIS's own default pedestrian speed, 1.34 m/s.
  static const double _defaultWalkingSpeedKmh = 4.8;

  /// MOTIS's own default cycling speed, 4.2 m/s.
  static const double _defaultCyclingSpeedKmh = 15.1;

  static const RoutingOptions defaults = RoutingOptions();

  /// Transit modes to use. Empty means all of them.
  final List<TransitMode> transitModes;

  /// Route transfers over the street network rather than using the feed's
  /// transfer times.
  final bool useRoutedTransfers;

  /// Restrict street legs to step-free paths.
  final bool wheelchairAccessibleOnly;

  /// Whether to demand a service that carries bicycles.
  ///
  /// Null means "follow [bikeAtBothEnds]" — picking a bike at both ends says
  /// the bike is travelling with you, so carriage follows without being asked
  /// for. Non-null means the rider decided, and their choice holds until the
  /// mile modes stop implying anything.
  ///
  /// Turning it off with a bike at both ends is a real request: the bike is
  /// coming, but you would rather walk it onto a service that does not
  /// advertise carriage.
  final bool? bikeCarriageOverride;

  /// Same rule for taking a car aboard, where carriage means motorail.
  final bool? carCarriageOverride;

  /// A bike is among the modes at both ends, so it travels with the rider
  /// rather than being left at the origin station.
  bool get bikeAtBothEnds =>
      firstMileModes.contains(TransitMode.bike) &&
      lastMileModesInUse.contains(TransitMode.bike);

  bool get carAtBothEnds =>
      firstMileModes.contains(TransitMode.car) &&
      lastMileModesInUse.contains(TransitMode.car);

  /// The value actually sent.
  ///
  /// The derivation is the default, not a gate: a bike at both ends turns
  /// carriage on without being asked, and the rider can still turn it off, or
  /// on for a journey where the derivation does not apply.
  bool get requireBikeTransport => bikeCarriageOverride ?? bikeAtBothEnds;

  bool get requireCarTransport => carCarriageOverride ?? carAtBothEnds;

  /// True when the rider set carriage by hand rather than inheriting it.
  bool get bikeCarriageIsManual => bikeCarriageOverride != null;

  /// Exclude services that require a reservation.
  final bool noCompulsoryReservation;

  final List<ViaStopOption> via;

  /// Null leaves it to the server.
  final int? maxTransfers;

  /// Buffer added to every transfer on top of the feed's own time.
  final Duration additionalTransferTime;

  /// How to reach the first stop, and the budget for it.
  ///
  /// A list because the server takes one: offering several says "any of
  /// these", which is how someone who might walk or might grab a bike
  /// actually travels. Never empty — a mile with no mode routes nothing.
  final List<TransitMode> firstMileModes;
  final Duration maxFirstMileTime;

  /// How to travel from the last stop, and the budget for it, as the rider
  /// set them for that leg. While [lastMileSameAsFirst] holds they are
  /// kept but not used; read the `…InUse` getters for what is sent.
  final List<TransitMode> lastMileModes;
  final Duration maxLastMileTime;

  /// The way from the last stop is the way to the first one: its modes,
  /// shared vehicles and budget all follow the first mile, and change with
  /// it.
  final bool lastMileSameAsFirst;

  /// The last mile as it is searched with.
  List<TransitMode> get lastMileModesInUse =>
      lastMileSameAsFirst ? firstMileModes : lastMileModes;

  Duration get maxLastMileTimeInUse =>
      lastMileSameAsFirst ? maxFirstMileTime : maxLastMileTime;

  List<RentalFormFactor> get lastMileRentalFormFactorsInUse =>
      lastMileSameAsFirst
      ? firstMileRentalFormFactors
      : lastMileRentalFormFactors;

  /// Linked to the first mile, or set apart from it again.
  ///
  /// Unlinking starts the last mile from what it was just searched with, so
  /// the tap alone changes nothing about the journey; the rider then edits
  /// it from there.
  RoutingOptions withLastMileSameAsFirst(bool same) => same
      ? copyWith(lastMileSameAsFirst: true)
      : copyWith(
          lastMileSameAsFirst: false,
          lastMileModes: lastMileModesInUse,
          maxLastMileTime: maxLastMileTimeInUse,
          lastMileRentalFormFactors: lastMileRentalFormFactorsInUse,
        );

  /// How a journey with no transit at all may travel: however the rider
  /// would reach the station, plus walking.
  ///
  /// Taken from the way there rather than set on its own, because it is the
  /// same question — a rider with their bike can ride it all the way. Park
  /// & ride means a car to hand, so it becomes driving; being dropped off
  /// does not carry over, since whoever drives is only going to the station.
  List<TransitMode> get directModes => [
    for (final mode in RoutingOptions.streetModeChoices)
      if (mode == TransitMode.walk ||
          (_directCapable(mode) && firstMileModes.contains(mode)) ||
          (mode == TransitMode.car &&
              firstMileModes.contains(TransitMode.carParking)))
        mode,
  ];

  static bool _directCapable(TransitMode mode) =>
      mode != TransitMode.carParking && mode != TransitMode.carDropoff;

  /// Budget for a journey with no transit: as long as the two street legs of
  /// a transit journey together. The server clamps it to its own limit.
  Duration get maxDirectTime => maxFirstMileTime + maxLastMileTimeInUse;

  /// Which shared vehicles each mile's rental leg may use.
  ///
  /// One list per mile, because the server takes one per mile: the filters go
  /// out as `preTransitRentalFormFactors` and `postTransitRentalFormFactors`,
  /// and a single shared list made picking a vehicle for the way there
  /// silently change the way back.
  ///
  /// Empty means the mile has no rentals — every control that offers a
  /// vehicle also puts [TransitMode.rental] in that mile's modes, and taking
  /// the last vehicle away takes the mode with it. So an empty list never
  /// travels with rentals switched on, and the permissive "no filter at all"
  /// state the server would read from one is not reachable.
  final List<RentalFormFactor> firstMileRentalFormFactors;
  final List<RentalFormFactor> lastMileRentalFormFactors;

  /// Stored in km/h because that is what the UI shows; converted to m/s on
  /// the way out.
  final double walkingSpeedKmh;
  final double cyclingSpeedKmh;

  /// How hard to avoid inclines. Needs a server with elevation data.
  final ElevationCosts elevationCosts;

  /// Slider range for a mile budget. The upper bound matches the server's own
  /// `maxPrePostTransitTimeLimit`; read the live value from
  /// `ServerCapabilitiesService` where one is available.
  static const Duration maxMileBudget = Duration(hours: 2);
  static const Duration mileBudgetStep = Duration(minutes: 5);

  /// Highest transfer count offered before the slider reads "unlimited".
  ///
  /// Unlimited omits `maxTransfers` rather than sending a large number, so the
  /// server keeps deciding.
  static const int maxTransferChoice = 5;

  /// Slider position standing for unlimited, one past the last real number.
  static const int unlimitedTransfersSliderValue = maxTransferChoice + 1;

  /// Slider position for the current transfer limit.
  int get transfersSliderValue => maxTransfers ?? unlimitedTransfersSliderValue;

  /// The transit selection as a set of modes.
  TransitSelection get transitSelection =>
      TransitSelection.fromModes(transitModes);

  RoutingOptions withTransitSelection(TransitSelection selection) =>
      copyWith(transitModes: selection.toModes());

  /// Transfer limit from a slider position, where the top stop means
  /// unlimited.
  RoutingOptions withTransfersSliderValue(int value) =>
      value >= unlimitedTransfersSliderValue
      ? copyWith(clearMaxTransfers: true)
      : copyWith(maxTransfers: value);

  /// Every mode a street leg may use, in the order the pickers read.
  ///
  /// The search card files each of them under a `StreetSection`; a journey
  /// without transit picks from the same list.
  static const List<TransitMode> streetModeChoices = [
    TransitMode.walk,
    TransitMode.bike,
    TransitMode.rental,
    TransitMode.car,
    TransitMode.carParking,
    TransitMode.carDropoff,
    TransitMode.hgv,
    TransitMode.odm,
    TransitMode.flex,
  ];

  /// These options with the settings-screen-only fields taken from [stored].
  ///
  /// The search screen keeps its own copy of the options, and once the rider
  /// changes something there it stops following the stored defaults. These
  /// fields cannot be changed on the search screen, so a change to them in
  /// the settings must still reach a search in progress — otherwise "Save as
  /// default" would quietly write the old values back. A field belongs here
  /// exactly when the search screen does not offer it.
  RoutingOptions withSettingsFrom(RoutingOptions stored) => copyWith(
    useRoutedTransfers: stored.useRoutedTransfers,
    additionalTransferTime: stored.additionalTransferTime,
    elevationCosts: stored.elevationCosts,
  );

  RoutingOptions copyWith({
    List<TransitMode>? transitModes,
    bool? useRoutedTransfers,
    bool? wheelchairAccessibleOnly,
    bool? bikeCarriageOverride,
    bool? carCarriageOverride,
    bool clearCarriageOverrides = false,
    bool? noCompulsoryReservation,
    List<ViaStopOption>? via,
    int? maxTransfers,
    bool clearMaxTransfers = false,
    Duration? additionalTransferTime,
    List<TransitMode>? firstMileModes,
    Duration? maxFirstMileTime,
    List<TransitMode>? lastMileModes,
    Duration? maxLastMileTime,
    List<RentalFormFactor>? firstMileRentalFormFactors,
    List<RentalFormFactor>? lastMileRentalFormFactors,
    bool? lastMileSameAsFirst,
    double? walkingSpeedKmh,
    double? cyclingSpeedKmh,
    ElevationCosts? elevationCosts,
  }) {
    // A mile with no mode routes nothing, so deselecting the last one falls
    // back to walking rather than producing a query that cannot answer.
    final nextFirst = _atLeastWalking(firstMileModes ?? this.firstMileModes);
    final nextLast = _atLeastWalking(lastMileModes ?? this.lastMileModes);

    return RoutingOptions(
      transitModes: transitModes ?? this.transitModes,
      useRoutedTransfers: useRoutedTransfers ?? this.useRoutedTransfers,
      wheelchairAccessibleOnly:
          wheelchairAccessibleOnly ?? this.wheelchairAccessibleOnly,
      bikeCarriageOverride: clearCarriageOverrides
          ? null
          : (bikeCarriageOverride ?? this.bikeCarriageOverride),
      carCarriageOverride: clearCarriageOverrides
          ? null
          : (carCarriageOverride ?? this.carCarriageOverride),
      noCompulsoryReservation:
          noCompulsoryReservation ?? this.noCompulsoryReservation,
      via: via ?? this.via,
      maxTransfers: clearMaxTransfers
          ? null
          : (maxTransfers ?? this.maxTransfers),
      additionalTransferTime:
          additionalTransferTime ?? this.additionalTransferTime,
      firstMileModes: nextFirst,
      maxFirstMileTime: maxFirstMileTime ?? this.maxFirstMileTime,
      lastMileModes: nextLast,
      maxLastMileTime: maxLastMileTime ?? this.maxLastMileTime,
      firstMileRentalFormFactors:
          firstMileRentalFormFactors ?? this.firstMileRentalFormFactors,
      lastMileRentalFormFactors:
          lastMileRentalFormFactors ?? this.lastMileRentalFormFactors,
      lastMileSameAsFirst: lastMileSameAsFirst ?? this.lastMileSameAsFirst,
      walkingSpeedKmh: walkingSpeedKmh ?? this.walkingSpeedKmh,
      cyclingSpeedKmh: cyclingSpeedKmh ?? this.cyclingSpeedKmh,
      elevationCosts: elevationCosts ?? this.elevationCosts,
    );
  }

  /// Builds the `/plan` query for a journey between two coordinates.
  ///
  /// Values left at their default are omitted, so the server keeps deciding
  /// them and a future change upstream is not pinned by this app.
  PlanParams toPlanParams({
    required String fromPlace,
    required String toPlace,
    DateTime? time,
    bool? arriveBy,
    String? pageCursor,
    List<String> rentalProviderGroups = const [],
  }) {
    return PlanParams(
      fromPlace: fromPlace,
      toPlace: toPlace,
      time: time,
      arriveBy: arriveBy,
      pageCursor: pageCursor,
      withFares: true,
      useRoutedTransfers: useRoutedTransfers,
      pedestrianProfile: wheelchairAccessibleOnly
          ? PedestrianProfile.wheelchair
          : null,
      requireBikeTransport: requireBikeTransport ? true : null,
      requireCarTransport: requireCarTransport ? true : null,
      noCompulsoryReservation: noCompulsoryReservation ? true : null,
      via: [
        for (final stop in via)
          ViaStop(stopId: stop.stopId, minimumStay: stop.minimumStay),
      ],
      maxTransfers: maxTransfers,
      additionalTransferTime: additionalTransferTime > Duration.zero
          ? additionalTransferTime
          : null,
      transitModes: transitModes,
      preTransitModes: firstMileModes,
      maxPreTransitTime: maxFirstMileTime,
      postTransitModes: lastMileModesInUse,
      maxPostTransitTime: maxLastMileTimeInUse,
      directModes: directModes,
      maxDirectTime: maxDirectTime,
      directRentals: _rentalFilters(
        firstMileRentalFormFactors,
        rentalProviderGroups,
      ),
      preTransitRentals: _rentalFilters(
        firstMileRentalFormFactors,
        rentalProviderGroups,
      ),
      postTransitRentals: _rentalFilters(
        lastMileRentalFormFactorsInUse,
        rentalProviderGroups,
      ),
      pedestrianSpeed: _msFrom(walkingSpeedKmh, _defaultWalkingSpeedKmh),
      cyclingSpeed: _msFrom(cyclingSpeedKmh, _defaultCyclingSpeedKmh),
      elevationCosts: elevationCosts == ElevationCosts.none
          ? null
          : elevationCosts,
    );
  }

  /// The same journey, re-checked against current real-time data.
  ///
  /// `/refresh-itinerary` re-plans rather than merely re-times, so it takes
  /// most of `/plan`'s knobs — and omitting them does not mean "keep what the
  /// search asked for", it means "use the server's defaults". That is how a
  /// refreshed walking leg comes back as a straight line: without
  /// `useRoutedTransfers` and the pedestrian settings, the street legs are no
  /// longer routed over the network and arrive with no geometry at all.
  ///
  /// `requireDisplayNameMatch` is the other half: it makes the server refuse
  /// to substitute a different journey, rather than handing back a re-plan
  /// that happens to have the same number of legs.
  RefreshItineraryOptions toRefreshParams({
    List<String> rentalProviderGroups = const [],
  }) => RefreshItineraryOptions(
    requireDisplayNameMatch: true,
    detailedTransfers: true,
    detailedLegs: true,
    withFares: true,
    useRoutedTransfers: useRoutedTransfers,
    pedestrianProfile: wheelchairAccessibleOnly
        ? PedestrianProfile.wheelchair
        : null,
    requireBikeTransport: requireBikeTransport ? true : null,
    requireCarTransport: requireCarTransport ? true : null,
    noCompulsoryReservation: noCompulsoryReservation ? true : null,
    transitModes: transitModes,
    preTransitModes: firstMileModes,
    maxPreTransitTime: maxFirstMileTime,
    postTransitModes: lastMileModesInUse,
    maxPostTransitTime: maxLastMileTimeInUse,
    preTransitRentals: _rentalFilters(
      firstMileRentalFormFactors,
      rentalProviderGroups,
    ),
    postTransitRentals: _rentalFilters(
      lastMileRentalFormFactorsInUse,
      rentalProviderGroups,
    ),
    pedestrianSpeed: _msFrom(walkingSpeedKmh, _defaultWalkingSpeedKmh),
    cyclingSpeed: _msFrom(cyclingSpeedKmh, _defaultCyclingSpeedKmh),
    elevationCosts: elevationCosts == ElevationCosts.none
        ? null
        : elevationCosts,
  );

  /// One mile's rental filter: the vehicles picked for it, and the
  /// provider groups the rider limited rentals to (empty for any). A mile
  /// with nothing to rent gets no filter at all.
  static RentalFilters _rentalFilters(
    List<RentalFormFactor> factors,
    List<String> providerGroups,
  ) => factors.isEmpty
      ? const RentalFilters()
      : RentalFilters(formFactors: factors, providerGroups: providerGroups);

  /// A mile always has somewhere to start from.
  static List<TransitMode> _atLeastWalking(List<TransitMode> modes) =>
      modes.isEmpty ? const [TransitMode.walk] : modes;

  /// Below this much difference in km/h the value is the default, allowing
  /// for the rounding a slider does on the way there and back.
  static const double _speedEqualityToleranceKmh = 0.05;

  static const double _kmhPerMetrePerSecond = 3.6;

  /// Millimetres per second is as fine as the wire needs; more digits only
  /// make two identical requests look different.
  static const int _speedWireDecimals = 3;

  /// km/h to m/s, or null when the value is the server's own default.
  static double? _msFrom(double kmh, double defaultKmh) {
    if ((kmh - defaultKmh).abs() < _speedEqualityToleranceKmh) return null;
    return double.parse(
      (kmh / _kmhPerMetrePerSecond).toStringAsFixed(_speedWireDecimals),
    );
  }

  Map<String, dynamic> toJson() => {
    'transitModes': [for (final mode in transitModes) mode.wireName],
    'useRoutedTransfers': useRoutedTransfers,
    'wheelchairAccessibleOnly': wheelchairAccessibleOnly,
    'bikeCarriageOverride': bikeCarriageOverride,
    'carCarriageOverride': carCarriageOverride,
    'noCompulsoryReservation': noCompulsoryReservation,
    'via': [for (final stop in via) stop.toJson()],
    'maxTransfers': maxTransfers,
    'additionalTransferTimeMinutes': additionalTransferTime.inMinutes,
    'firstMileModes': [for (final mode in firstMileModes) mode.wireName],
    'maxFirstMileTimeMinutes': maxFirstMileTime.inMinutes,
    'lastMileModes': [for (final mode in lastMileModes) mode.wireName],
    'maxLastMileTimeMinutes': maxLastMileTime.inMinutes,
    'firstMileRentalFormFactors': [
      for (final f in firstMileRentalFormFactors) f.wireName,
    ],
    'lastMileRentalFormFactors': [
      for (final f in lastMileRentalFormFactors) f.wireName,
    ],
    'lastMileSameAsFirst': lastMileSameAsFirst,
    'walkingSpeedKmh': walkingSpeedKmh,
    'cyclingSpeedKmh': cyclingSpeedKmh,
    'elevationCosts': elevationCosts.wireName,
  };

  /// Reads stored options, falling back per field rather than as a whole, so
  /// a value written by a different version cannot reset everything else.
  factory RoutingOptions.fromJson(Map<String, dynamic> json) {
    const fallback = RoutingOptions.defaults;
    return RoutingOptions(
      transitModes: _modes(json['transitModes']),
      useRoutedTransfers:
          json['useRoutedTransfers'] as bool? ?? fallback.useRoutedTransfers,
      wheelchairAccessibleOnly:
          json['wheelchairAccessibleOnly'] as bool? ??
          fallback.wheelchairAccessibleOnly,
      bikeCarriageOverride: json['bikeCarriageOverride'] as bool?,
      carCarriageOverride: json['carCarriageOverride'] as bool?,
      noCompulsoryReservation:
          json['noCompulsoryReservation'] as bool? ??
          fallback.noCompulsoryReservation,
      via: _via(json['via']),
      maxTransfers: json['maxTransfers'] as int?,
      additionalTransferTime: _minutes(
        json['additionalTransferTimeMinutes'],
        fallback.additionalTransferTime,
      ),
      firstMileModes: _mileModes(
        json['firstMileModes'],
        fallback.firstMileModes,
      ),
      maxFirstMileTime: _minutes(
        json['maxFirstMileTimeMinutes'],
        fallback.maxFirstMileTime,
      ),
      lastMileModes: _mileModes(json['lastMileModes'], fallback.lastMileModes),
      maxLastMileTime: _minutes(
        json['maxLastMileTimeMinutes'],
        fallback.maxLastMileTime,
      ),
      walkingSpeedKmh:
          (json['walkingSpeedKmh'] as num?)?.toDouble() ??
          fallback.walkingSpeedKmh,
      cyclingSpeedKmh:
          (json['cyclingSpeedKmh'] as num?)?.toDouble() ??
          fallback.cyclingSpeedKmh,
      elevationCosts:
          ElevationCosts.fromWire(json['elevationCosts']) ??
          fallback.elevationCosts,
      firstMileRentalFormFactors: _formFactors(
        json['firstMileRentalFormFactors'],
      ),
      lastMileRentalFormFactors: _formFactors(
        json['lastMileRentalFormFactors'],
      ),
      lastMileSameAsFirst:
          json['lastMileSameAsFirst'] as bool? ?? fallback.lastMileSameAsFirst,
    );
  }

  static List<TransitMode> _modes(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final entry in raw)
        if (TransitMode.fromWire(entry) case final mode?) mode,
    ];
  }

  /// A stored mile list, falling back when it is absent or unreadable — an
  /// empty list here would mean "route nothing", not "use the default".
  static List<TransitMode> _mileModes(Object? raw, List<TransitMode> fallback) {
    final modes = _modes(raw);
    return modes.isEmpty ? fallback : modes;
  }

  static List<RentalFormFactor> _formFactors(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final entry in raw)
        if (RentalFormFactor.fromWire(entry) case final factor?) factor,
    ];
  }

  static Duration _minutes(Object? raw, Duration fallback) =>
      raw is int ? Duration(minutes: raw) : fallback;

  /// Value equality, so a screen can tell whether anything actually changed
  /// before writing. Compares the serialised form rather than field by field,
  /// which keeps it correct as options are added.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RoutingOptions &&
          _encoded(toJson()) == _encoded(other.toJson()));

  @override
  int get hashCode => _encoded(toJson()).hashCode;

  static String _encoded(Map<String, dynamic> json) =>
      json.entries.map((e) => '${e.key}=${_stringify(e.value)}').join('&');

  static String _stringify(Object? value) {
    if (value is List) return value.map(_stringify).join(',');
    if (value is Map) {
      return value.entries.map((e) => '${e.key}:${e.value}').join('|');
    }
    return '$value';
  }

  static List<ViaStopOption> _via(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final entry in raw)
        if (entry is Map<String, dynamic>)
          if (ViaStopOption.fromJson(entry) case final stop?) stop,
    ];
  }
}
