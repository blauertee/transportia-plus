import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/models/my_location.dart';
import 'package:transportia/services/transitous_geocode_service.dart';

/// My Location is recognised by id. Getting that wrong is a silent failure:
/// a stop called "My Location" planned from the rider's position, or the
/// rider's position planned from 0,0.
void main() {
  test('the token is My Location', () {
    expect(myLocationSuggestion.isMyLocation, isTrue);
    expect(myLocationSuggestion.name, myLocationName);
  });

  test('a place merely named My Location is not', () {
    final lookalike = TransitousLocationSuggestion(
      id: 'some-stop',
      name: myLocationName,
      lat: 1,
      lon: 2,
      type: 'STOP',
    );
    expect(lookalike.isMyLocation, isFalse);
  });

  test('no selection is not My Location', () {
    const TransitousLocationSuggestion? none = null;
    expect(none.isMyLocation, isFalse);
  });
}
