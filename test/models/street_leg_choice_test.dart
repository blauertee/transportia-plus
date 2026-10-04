import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/models/quick_access_layout.dart';
import 'package:transportia/models/routing_options.dart';
import 'package:transportia/models/street_leg_choice.dart';
import 'package:transportia/models/transit_mode_group.dart';
import 'package:transportia/models/transitous/enums.dart';

const _walking = StreetLegChoice(modes: [TransitMode.walk], formFactors: []);

final _sections = QuickAccessLayout.defaults.streetSections;

List<StreetItem> _items(String id) =>
    _sections.firstWhere((s) => s.id == id).items;

void main() {
  group('street items', () {
    test('are every street mode but renting, and every shared vehicle', () {
      expect(
        [
          for (final item in StreetItem.all)
            if (item case StreetMode(:final mode)) mode,
        ],
        [
          for (final mode in RoutingOptions.streetModeChoices)
            if (mode != TransitMode.rental) mode,
        ],
      );
      expect([
        for (final item in StreetItem.all)
          if (item case SharedVehicle(:final factor)) factor,
      ], RentalFormFactor.values);
    });

    test('keep their key across a round trip', () {
      for (final item in StreetItem.all) {
        expect(StreetItem.fromKey(item.key), item);
      }
      expect(StreetItem.fromKey('mode:TELEPORT'), isNull);
    });
  });

  group('a section', () {
    test('is on, partly on or off', () {
      expect(_walking.stateOf(_items('walk')), GroupState.all);
      expect(_walking.stateOf(_items('own-car')), GroupState.none);
      final dropOff = _walking.toggleMode(TransitMode.carDropoff);
      expect(dropOff.stateOf(_items('own-car')), GroupState.some);
    });

    test('switches on whole, then off whole', () {
      final on = _walking.toggleAll(_items('shared-car'));
      expect(on.stateOf(_items('shared-car')), GroupState.all);
      expect(on.formFactors, [RentalFormFactor.car, RentalFormFactor.moped]);
      expect(on.modes, contains(TransitMode.rental));

      final off = on.toggleAll(_items('shared-car'));
      expect(off.stateOf(_items('shared-car')), GroupState.none);
      expect(off.modes, [TransitMode.walk]);
    });

    test('partly on is completed rather than cleared', () {
      final some = _walking.toggleFormFactor(RentalFormFactor.bicycle);
      final completed = some.toggleAll(_items('shared-light'));
      expect(completed.stateOf(_items('shared-light')), GroupState.all);
    });

    test('leaves the other sections as they were', () {
      final withBike = _walking.toggleMode(TransitMode.bike);
      final both = withBike.toggleAll(_items('shared-light'));
      expect(both.has(TransitMode.walk), isTrue);
      expect(both.has(TransitMode.bike), isTrue);
    });

    test('of nothing is off, and switching it changes nothing', () {
      expect(_walking.stateOf(const []), GroupState.none);
      final same = _walking.toggleAll(const []);
      expect(same.modes, _walking.modes);
      expect(same.formFactors, _walking.formFactors);
    });

    test('an item switches by itself, whichever kind it is', () {
      final driving = _walking.toggle(const StreetMode(TransitMode.car));
      expect(driving.uses(const StreetMode(TransitMode.car)), isTrue);
      final renting = driving.toggle(
        const SharedVehicle(RentalFormFactor.moped),
      );
      expect(renting.rents(RentalFormFactor.moped), isTrue);
      expect(renting.rentsAnything, isTrue);
    });
  });

  group('rentals follow the vehicles', () {
    test('the first shared vehicle brings rentals', () {
      final next = _walking.toggleFormFactor(RentalFormFactor.scooterStanding);
      expect(next.modes, contains(TransitMode.rental));
    });

    test('the last one takes them away', () {
      final next = _walking
          .toggleFormFactor(RentalFormFactor.scooterStanding)
          .toggleFormFactor(RentalFormFactor.scooterStanding);
      expect(next.modes, isNot(contains(TransitMode.rental)));
      expect(next.formFactors, isEmpty);
      expect(next.rentsAnything, isFalse);
    });
  });

  test('the modes keep the order the pickers read', () {
    final next = _walking
        .toggleMode(TransitMode.flex)
        .toggleMode(TransitMode.bike)
        .toggleFormFactor(RentalFormFactor.bicycle);
    expect(next.modes, [
      TransitMode.walk,
      TransitMode.bike,
      TransitMode.rental,
      TransitMode.flex,
    ]);
  });

  group('summary', () {
    test('names the sections on by their headings, as a sentence', () {
      final next = _walking
          .toggleFormFactor(RentalFormFactor.bicycle)
          .toggleMode(TransitMode.carParking);
      expect(next.summary(_sections), 'Walk, shared bikes & scooters, own car');
    });

    test('with nothing on it is still walking', () {
      const empty = StreetLegChoice(modes: [], formFactors: []);
      expect(empty.summary(_sections), 'Walk');
    });

    test('names Other when only its modes are on', () {
      const flexible = StreetLegChoice(
        modes: [TransitMode.flex],
        formFactors: [],
      );
      expect(flexible.summary(_sections), 'Other');
    });
  });
}
