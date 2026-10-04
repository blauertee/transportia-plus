import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/models/quick_access_layout.dart';
import 'package:transportia/models/street_leg_choice.dart';
import 'package:transportia/models/transit_mode_group.dart';
import 'package:transportia/models/transitous/enums.dart';
import 'package:transportia/utils/app_icons.dart';

final _defaults = QuickAccessLayout.defaults;

/// [layout] as storage hands it back: decoded JSON, loosely typed.
Map<String, dynamic> _stored(QuickAccessLayout layout) =>
    jsonDecode(jsonEncode(layout.toJson())) as Map<String, dynamic>;

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

  group('moving', () {
    test('takes an item out of its section and into another', () {
      final moved = _defaults.moveStreet(
        const SharedVehicle(RentalFormFactor.scooterSeated),
        'shared-car',
      );
      final shared = moved.street.firstWhere((s) => s.id == 'shared-car');
      final light = moved.street.firstWhere((s) => s.id == 'shared-light');
      expect(
        shared.items,
        contains(const SharedVehicle(RentalFormFactor.scooterSeated)),
      );
      expect(
        light.items,
        isNot(contains(const SharedVehicle(RentalFormFactor.scooterSeated))),
      );
    });

    test('keeps the pickers\' order inside a section', () {
      final moved = _defaults.moveStreet(
        const SharedVehicle(RentalFormFactor.bicycle),
        'shared-car',
      );
      expect(moved.street.firstWhere((s) => s.id == 'shared-car').items, const [
        SharedVehicle(RentalFormFactor.bicycle),
        SharedVehicle(RentalFormFactor.car),
        SharedVehicle(RentalFormFactor.moped),
      ]);
    });

    test('into Other takes it out of every section', () {
      final moved = _defaults.moveTransit(
        TransitMode.coach,
        QuickAccessLayout.otherId,
      );
      expect(moved.otherTransit, contains(TransitMode.coach));
      expect(
        moved.transit.expand((g) => g.items),
        isNot(contains(TransitMode.coach)),
      );
    });

    test('out of Other puts it in a section', () {
      final moved = _defaults.moveStreet(
        const StreetMode(TransitMode.hgv),
        'own-car',
      );
      expect(
        moved.otherStreet,
        isNot(contains(const StreetMode(TransitMode.hgv))),
      );
      expect(
        moved.street.firstWhere((s) => s.id == 'own-car').items,
        contains(const StreetMode(TransitMode.hgv)),
      );
    });
  });

  test('a rename or a new icon replaces only its own section', () {
    final walk = _defaults.street.first;
    final renamed = _defaults.withStreetGroup(
      walk.copyWith(title: 'On foot', iconName: 'lucide:person-standing'),
    );
    expect(renamed.street.first.title, 'On foot');
    expect(renamed.street.first.items, walk.items);
    expect(
      renamed.street.skip(1).map((s) => s.title),
      _defaults.street.skip(1).map((s) => s.title),
    );
  });

  group('storage', () {
    test('round-trips a rearranged layout', () {
      final layout = _defaults
          .moveStreet(
            const SharedVehicle(RentalFormFactor.moped),
            'shared-light',
          )
          .moveTransit(TransitMode.tram, 'rail')
          .withTransitGroup(_defaults.transit.first.copyWith(title: 'Trains'));
      final restored = QuickAccessLayout.fromJson(layout.toJson());
      expect(restored.toJson(), layout.toJson());
    });

    test('a missing or unreadable section takes its default alone', () {
      final json = _stored(
        _defaults.withStreetGroup(
          _defaults.street.first.copyWith(title: 'On foot'),
        ),
      );
      (json['street'] as List).removeAt(1);
      (json['transit'] as List)[0] = 'not a section';
      final restored = QuickAccessLayout.fromJson(json);
      expect(restored.street.first.title, 'On foot');
      expect(restored.street[1].title, 'Own bike');
      expect(restored.transit.first.title, 'Rail');
    });

    test('a default section does not take back what was moved out of it', () {
      final moved = _defaults.moveStreet(
        const StreetMode(TransitMode.bike),
        'walk',
      );
      final json = _stored(moved);
      // The own-bike section is lost; its default holds the bike again.
      (json['street'] as List).removeWhere(
        (g) => (g as Map)['id'] == 'own-bike',
      );
      final restored = QuickAccessLayout.fromJson(json);
      expect(
        restored.street.first.items,
        contains(const StreetMode(TransitMode.bike)),
      );
      expect(restored.street[1].items, isEmpty);
    });

    test('an item claimed twice stays with the first section', () {
      final json = _stored(_defaults);
      ((json['street'] as List)[1] as Map)['items'] = [
        'mode:WALK',
        'mode:BIKE',
      ];
      final restored = QuickAccessLayout.fromJson(json);
      expect(restored.street.first.items, const [StreetMode(TransitMode.walk)]);
      expect(restored.street[1].items, const [StreetMode(TransitMode.bike)]);
    });

    test('unknown items, empty titles and icons fall back quietly', () {
      final json = _stored(_defaults);
      final walk = (json['street'] as List).first as Map;
      walk['items'] = ['mode:WALK', 'mode:TELEPORT', 42];
      walk['title'] = '   ';
      walk['icon'] = '';
      final restored = QuickAccessLayout.fromJson(json);
      expect(restored.street.first.items, const [StreetMode(TransitMode.walk)]);
      expect(restored.street.first.title, 'Walk');
      expect(restored.street.first.iconName, 'lucide:footprints');
    });

    test('an old alias of a transit mode reads as the mode', () {
      final json = _stored(_defaults);
      ((json['transit'] as List)[1] as Map)['items'] = ['METRO', 'TRAM'];
      final restored = QuickAccessLayout.fromJson(json);
      expect(restored.transit[1].items, const [
        TransitMode.subway,
        TransitMode.tram,
      ]);
    });

    test('nothing readable at all is the defaults', () {
      expect(QuickAccessLayout.fromJson(const {}).toJson(), _defaults.toJson());
    });
  });
}
