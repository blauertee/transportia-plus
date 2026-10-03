import 'package:flutter/foundation.dart';

import '../models/routing_options.dart';
import '../models/time_selection.dart';
import 'transitous_geocode_service.dart';

/// A journey one screen wants the routing screen to be holding.
///
/// Not a search: the fields are filled in and nothing is sent. A rider whose
/// connection has just broken is the last person to hand a fixed answer to —
/// they may want a different destination, a later train, or to walk it.
@immutable
class PlanRequest {
  const PlanRequest({
    required this.from,
    required this.to,
    required this.time,
    this.options,
  });

  final TransitousLocationSuggestion from;
  final TransitousLocationSuggestion to;
  final TimeSelection time;

  /// The options the journey was searched with. Null keeps whatever the
  /// routing screen holds.
  final RoutingOptions? options;
}

/// The one journey waiting to be shown on the routing screen.
///
/// The itinerary screen sits on a pushed route with the tabs underneath it, so
/// a callback would have to be threaded down through every screen between. A
/// single notifier the shell watches is how the app already moves a stop to
/// the timetable tab, and it keeps the sender ignorant of who is listening.
abstract final class PlanRequests {
  static final ValueNotifier<PlanRequest?> pending =
      ValueNotifier<PlanRequest?>(null);

  static void ask(PlanRequest request) => pending.value = request;

  /// Reads the request and clears it, so returning to the tab later does not
  /// overwrite whatever the rider has typed since.
  static PlanRequest? take() {
    final request = pending.value;
    pending.value = null;
    return request;
  }
}
