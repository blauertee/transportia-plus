import 'dart:developer' as developer;

import '../api/endpoints/plan_endpoint.dart';
import '../api/query.dart';
import '../api/transitous_api_exception.dart';
import '../models/itinerary.dart';
import '../models/itinerary_response.dart';
import '../models/routing_options.dart';
import '../models/time_selection.dart';
import 'rental_providers_service.dart';
import 'routing_options_service.dart';

class RoutingService {
  static Future<List<Itinerary>> findRoutes({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    TimeSelection? timeSelection,
    RoutingOptions? options,
  }) async {
    final response = await findRoutesPaginated(
      fromLat: fromLat,
      fromLon: fromLon,
      toLat: toLat,
      toLon: toLon,
      timeSelection: timeSelection,
      options: options,
    );
    return response.itineraries;
  }

  /// [options] are the ones configured for this search. Falling back to the
  /// stored defaults is for journeys nobody configured — a deep link, or a
  /// second opinion on an itinerary opened from history.
  ///
  /// [fromStopId] starts the search at that stop rather than at the
  /// coordinates, for going on from a station partway through a journey:
  /// the results then board there instead of walking in from its centre.
  static Future<ItineraryResponse> findRoutesPaginated({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    TimeSelection? timeSelection,
    String? pageCursor,
    RoutingOptions? options,
    String? fromStopId,
  }) async {
    final resolved = options ?? await RoutingOptionsService.load();
    final providerGroups = await RentalProvidersService.activeGroupIds();

    final params = resolved.toPlanParams(
      fromPlace: fromStopId ?? Q.latLonComma(fromLat, fromLon),
      toPlace: Q.latLonComma(toLat, toLon),
      pageCursor: pageCursor,
      rentalProviderGroups: providerGroups,
      time: timeSelection == null || timeSelection.isNow
          ? null
          : timeSelection.dateTime,
      arriveBy: timeSelection != null && !timeSelection.isNow
          ? timeSelection.isArriveBy
          : null,
    );

    try {
      return await PlanEndpoint.plan(params);
    } on TransitousApiException catch (e, stackTrace) {
      developer.log(
        'Failed to load routes',
        name: 'RoutingService',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
}
