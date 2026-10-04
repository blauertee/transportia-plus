import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/models/quick_access_layout.dart';
import 'package:transportia/models/street_leg_choice.dart';
import 'package:transportia/models/transit_mode_group.dart';
import 'package:transportia/models/transitous/enums.dart';
import 'package:transportia/utils/app_icons.dart';

final _defaults = QuickAccessLayout.defaults;

void main() {
  group('the defaults', () {
    test('are four for the ride and five for the way there', () {
      expect(_defaults.transit, hasLength(4));
      expect(_defaults.street, hasLength(5));
    });

    test('hold every item exactly once, Other included', () {
      final street = [for (final s in _defaults.streetSections) ...s.items];
      expect(street.toSet(), StreetItem.all.toSet());
      expect(street, hasLength(StreetItem.all.length));

      final transit = [for (final s in _defaults.transitSections) ...s.items];
      expect(transit.toSet(), TransitModeGroup.allSelectable.toSet());
      expect(transit, hasLength(TransitModeGroup.allSelectable.length));
    });

    test('keep own and shared cars apart, mopeds with the cars', () {
      final ownCar = _defaults.street.firstWhere((s) => s.id == 'own-car');
      final shared = _defaults.street.firstWhere((s) => s.id == 'shared-car');
      expect(
        ownCar.items,
        isNot(contains(const SharedVehicle(RentalFormFactor.car))),
      );
      expect(shared.items, [
        const SharedVehicle(RentalFormFactor.car),
        const SharedVehicle(RentalFormFactor.moped),
      ]);
      expect(shared.icon, AppIcons.carKey);
    });

    test('leave on-demand, flexible and lorries to Other', () {
      expect(_defaults.otherStreet, const [
        StreetMode(TransitMode.hgv),
        StreetMode(TransitMode.odm),
        StreetMode(TransitMode.flex),
      ]);
      expect(_defaults.otherTransit, TransitModeGroup.extras);
    });

    test('have ids that are unique and icons that resolve', () {
      for (final sections in [
        _defaults.transitSections,
        _defaults.streetSections,
      ]) {
        final ids = [for (final s in sections) s.id];
        expect(ids.toSet(), hasLength(ids.length));
        for (final s in sections) {
          expect(AppIcons.isKnown(s.iconName), isTrue, reason: s.iconName);
        }
      }
    });
  });

  test('Other is whatever no section holds, so nothing is ever lost', () {
    final layout = QuickAccessLayout(
      transit: _defaults.transit,
      street: [
        for (final s in _defaults.street)
          s.id == 'walk' ? s.copyWith(items: const []) : s,
      ],
    );
    expect(layout.otherStreet, contains(const StreetMode(TransitMode.walk)));
    expect(layout.streetSections.last.id, QuickAccessLayout.otherId);
  });
}
