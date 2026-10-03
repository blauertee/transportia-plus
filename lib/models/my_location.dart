import '../services/transitous_geocode_service.dart';

/// What the app calls the rider's current position.
///
/// Either field can hold it, as [myLocationSuggestion] under this name. It is
/// resolved to a position only when Search is pressed, so the trip is planned
/// from where you are then rather than where you were when you picked.
const String myLocationName = 'My Location';

/// My Location as a field's selection — recognised by id, so a place that
/// happens to share the name is not mistaken for it. It carries no
/// coordinates: they are read from the device when the search needs them.
final TransitousLocationSuggestion myLocationSuggestion =
    TransitousLocationSuggestion(
      id: 'my-location',
      name: myLocationName,
      lat: 0,
      lon: 0,
      type: 'PLACE',
    );

extension MyLocationSelection on TransitousLocationSuggestion? {
  /// Whether this selection stands for the rider's position rather than a
  /// place with coordinates of its own.
  bool get isMyLocation => this?.id == myLocationSuggestion.id;
}
