import '../../models/itinerary.dart';
import '../../models/transitous/itinerary_id.dart';
import '../params/plan_params.dart';
import '../query.dart';
import '../transitous_client.dart';
import '../transitous_endpoint.dart';

/// `/trip` and `/refresh-itinerary`.
class TripEndpoint {
  const TripEndpoint._();

  /// The full run of one vehicle, as an itinerary with a single leg.
  static Future<Itinerary> trip({
    required String tripId,
    bool? withScheduledSkippedStops,
    bool? detailedLegs,
    bool? joinInterlinedLegs,
    List<String> languages = const [],
    TransitousClient? client,
  }) {
    return (client ?? TransitousClient.instance).get(
      TransitousEndpoint.trip,
      {
        'tripId': tripId,
        'withScheduledSkippedStops': Q.boolean(withScheduledSkippedStops),
        'detailedLegs': Q.boolean(detailedLegs),
        'joinInterlinedLegs': Q.boolean(joinInterlinedLegs),
        'language': Q.csv(languages),
      },
      (json) => Itinerary.fromJson(json as Map<String, dynamic>),
    );
  }

  /// Re-plans a whole itinerary against current real-time data in one call,
  /// using the opaque [Itinerary.id] from the original response.
  ///
  /// The id runs to roughly 1.7 KB, which still fits a URL comfortably. Note
  /// the two forms are not interchangeable: this opaque string is only
  /// accepted by the GET form, and the POST form only accepts the structured
  /// identifier — see [refreshItineraryById].
  ///
  /// [host] reads the id on another server than the rider's: the one a shared
  /// trip was planned on.
  static Future<Itinerary> refreshItinerary({
    required String itineraryId,
    RefreshItineraryOptions options = const RefreshItineraryOptions(),
    String? host,
    TransitousClient? client,
  }) {
    return (client ?? TransitousClient.instance).get(
      TransitousEndpoint.refreshItinerary,
      {'itineraryId': itineraryId, ...options.toQuery()},
      (json) => Itinerary.fromJson(json as Map<String, dynamic>),
      host: host,
    );
  }

  /// POST form, taking the structured identifier.
  ///
  /// Use this when the itinerary was rebuilt locally and no longer carries the
  /// opaque id, e.g. one restored from a saved trip: [ItineraryId] can be
  /// derived from the legs, whereas the opaque string cannot.
  static Future<Itinerary> refreshItineraryById({
    required ItineraryId id,
    RefreshItineraryOptions options = const RefreshItineraryOptions(),
    TransitousClient? client,
  }) {
    return (client ?? TransitousClient.instance).post(
      TransitousEndpoint.refreshItinerary,
      options.toQuery(),
      {'id': id.toJson()},
      (json) => Itinerary.fromJson(json as Map<String, dynamic>),
    );
  }
}

/// Options for `/refresh-itinerary`.
///
/// The refresh re-plans the itinerary, so it takes most of the same knobs as
/// `/plan`; passing the values the original search used keeps the refreshed
/// result comparable to it.
class RefreshItineraryOptions {
  const RefreshItineraryOptions({
    this.requireDisplayNameMatch,
    this.joinInterlinedLegs,
    this.detailedTransfers,
    this.detailedLegs,
    this.withFares,
    this.withScheduledSkippedStops,
    this.numLegAlternatives,
    this.transitModes = const [],
    this.preTransitModes = const [],
    this.postTransitModes = const [],
    this.pedestrianProfile,
    this.useRoutedTransfers,
    this.requireBikeTransport,
    this.requireCarTransport,
    this.noCompulsoryReservation,
    this.pedestrianSpeed,
    this.cyclingSpeed,
    this.elevationCosts,
    this.maxMatchingDistance,
    this.maxPreTransitTime,
    this.maxPostTransitTime,
    this.preTransitRentals = const RentalFilters(),
    this.postTransitRentals = const RentalFilters(),
    this.languages = const [],
  });

  /// Require the refreshed legs to keep the same display names, so a
  /// re-planned itinerary is rejected rather than silently substituted.
  final bool? requireDisplayNameMatch;

  final bool? joinInterlinedLegs;
  final bool? detailedTransfers;
  final bool? detailedLegs;
  final bool? withFares;
  final bool? withScheduledSkippedStops;
  final int? numLegAlternatives;
  final List<TransitMode> transitModes;
  final List<TransitMode> preTransitModes;
  final List<TransitMode> postTransitModes;
  final PedestrianProfile? pedestrianProfile;
  final bool? useRoutedTransfers;
  final bool? requireBikeTransport;
  final bool? requireCarTransport;
  final bool? noCompulsoryReservation;
  final double? pedestrianSpeed;
  final double? cyclingSpeed;
  final ElevationCosts? elevationCosts;
  final double? maxMatchingDistance;
  final Duration? maxPreTransitTime;
  final Duration? maxPostTransitTime;

  /// Which shared vehicles the street legs may use. Without them a refresh
  /// re-plans with any vehicle from any provider, and can hand back a
  /// different rental than the one searched for. There is no direct set:
  /// the endpoint re-plans journeys that use transit.
  final RentalFilters preTransitRentals;
  final RentalFilters postTransitRentals;

  final List<String> languages;

  Map<String, String?> toQuery() => {
    'requireDisplayNameMatch': Q.boolean(requireDisplayNameMatch),
    'joinInterlinedLegs': Q.boolean(joinInterlinedLegs),
    'detailedTransfers': Q.boolean(detailedTransfers),
    'detailedLegs': Q.boolean(detailedLegs),
    'withFares': Q.boolean(withFares),
    'withScheduledSkippedStops': Q.boolean(withScheduledSkippedStops),
    'numLegAlternatives': Q.integer(numLegAlternatives),
    'transitModes': Q.csv(transitModes.map((m) => m.wireName)),
    'preTransitModes': Q.csv(preTransitModes.map((m) => m.wireName)),
    'postTransitModes': Q.csv(postTransitModes.map((m) => m.wireName)),
    'pedestrianProfile': pedestrianProfile?.wireName,
    'useRoutedTransfers': Q.boolean(useRoutedTransfers),
    'requireBikeTransport': Q.boolean(requireBikeTransport),
    'requireCarTransport': Q.boolean(requireCarTransport),
    'noCompulsoryReservation': Q.boolean(noCompulsoryReservation),
    'pedestrianSpeed': Q.number(pedestrianSpeed),
    'cyclingSpeed': Q.number(cyclingSpeed),
    'elevationCosts': elevationCosts?.wireName,
    'maxMatchingDistance': Q.number(maxMatchingDistance),
    'maxPreTransitTime': Q.seconds(maxPreTransitTime),
    'maxPostTransitTime': Q.seconds(maxPostTransitTime),
    ...preTransitRentals.toQuery('preTransit'),
    ...postTransitRentals.toQuery('postTransit'),
    'language': Q.csv(languages),
  };
}
