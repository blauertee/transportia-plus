import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/models/routing_options.dart';
import 'package:transportia/models/transit_mode_group.dart';
import 'package:transportia/models/transitous/enums.dart';

/// Query the options would produce, nulls stripped.
Map<String, String> _query(RoutingOptions options) {
  final params = options.toPlanParams(fromPlace: '0,0', toPlace: '1,1');
  return {
    for (final entry in params.toQuery().entries)
      if (entry.value != null) entry.key: entry.value!,
  };
}

const _bikeBothEnds = RoutingOptions(
  firstMileModes: [TransitMode.bike],
  lastMileModes: [TransitMode.bike],
);

void main() {
  group('a mile can take several modes', () {
    test('every chosen mode reaches the query', () {
      const options = RoutingOptions(
        firstMileModes: [TransitMode.walk, TransitMode.hgv],
        lastMileModes: [TransitMode.walk],
      );
      final query = _query(options);

      expect(query['preTransitModes'], 'WALK,HGV');
      expect(query['postTransitModes'], 'WALK');
    });

    test('a mile always has somewhere to start from', () {
      // An empty list would ask the server to route a leg with no way to
      // travel it, which answers nothing.
      final emptied = RoutingOptions.defaults.copyWith(
        firstMileModes: const [],
      );
      expect(emptied.firstMileModes, [TransitMode.walk]);
    });
  });

  group('carriage starts from the modes but stays the rider\'s', () {
    test('a bike only to the station leaves it there', () {
      const options = RoutingOptions(firstMileModes: [TransitMode.bike]);
      expect(options.bikeAtBothEnds, isFalse);
      expect(options.requireBikeTransport, isFalse);
      expect(_query(options).containsKey('requireBikeTransport'), isFalse);
    });

    test('a bike at both ends carries it aboard without being asked', () {
      expect(_bikeBothEnds.bikeAtBothEnds, isTrue);
      expect(_bikeBothEnds.requireBikeTransport, isTrue);
      expect(_bikeBothEnds.bikeCarriageIsManual, isFalse);
      expect(_query(_bikeBothEnds)['requireBikeTransport'], 'true');
    });

    test('a bike among other modes at both ends still counts', () {
      const eitherWay = RoutingOptions(
        firstMileModes: [TransitMode.walk, TransitMode.bike],
        lastMileModes: [TransitMode.bike, TransitMode.walk],
      );
      expect(eitherWay.requireBikeTransport, isTrue);
    });

    test('turning carriage off with a bike at both ends is honoured', () {
      // The bike is coming, but they would rather walk it onto a service
      // that does not advertise carriage.
      final off = _bikeBothEnds.copyWith(bikeCarriageOverride: false);
      expect(off.requireBikeTransport, isFalse);
      expect(off.bikeCarriageIsManual, isTrue);
      expect(_query(off).containsKey('requireBikeTransport'), isFalse);
    });

    test('turning it on without a bike at both ends is honoured too', () {
      // The control is always on screen, so asking for a service that carries
      // bicycles is a request in its own right rather than a stray value.
      const asked = RoutingOptions(bikeCarriageOverride: true);
      expect(asked.bikeAtBothEnds, isFalse);
      expect(asked.requireBikeTransport, isTrue);
      expect(_query(asked)['requireBikeTransport'], 'true');
    });

    test('a manual choice survives edits elsewhere', () {
      final off = _bikeBothEnds
          .copyWith(bikeCarriageOverride: false)
          .copyWith(maxTransfers: 2)
          .copyWith(noCompulsoryReservation: true);
      expect(off.requireBikeTransport, isFalse);
      expect(off.bikeCarriageIsManual, isTrue);
    });

    test('a manual choice outlives a change of mile mode', () {
      // The icon no longer comes and goes with the modes, so the decision has
      // somewhere to live and something to undo it.
      final off = _bikeBothEnds
          .copyWith(bikeCarriageOverride: false)
          .copyWith(firstMileModes: const [TransitMode.walk]);
      expect(off.bikeCarriageIsManual, isTrue);
      expect(off.requireBikeTransport, isFalse);
    });

    test('clearing hands it back to the derivation', () {
      final cleared = _bikeBothEnds
          .copyWith(bikeCarriageOverride: false)
          .copyWith(clearCarriageOverrides: true);
      expect(cleared.bikeCarriageIsManual, isFalse);
      expect(cleared.requireBikeTransport, isTrue);
    });
  });

  group('car carriage works the same way', () {
    test('a car at both ends means motorail', () {
      const motorail = RoutingOptions(
        firstMileModes: [TransitMode.car],
        lastMileModes: [TransitMode.car],
      );
      expect(_query(motorail)['requireCarTransport'], 'true');
    });

    test('park and ride is not motorail', () {
      const parkAndRide = RoutingOptions(
        firstMileModes: [TransitMode.carParking],
        lastMileModes: [TransitMode.carParking],
      );
      expect(parkAndRide.requireCarTransport, isFalse);
    });
  });

  group('shared vehicles', () {
    test('no filter asks for no particular kind', () {
      expect(
        _query(
          RoutingOptions.defaults,
        ).containsKey('preTransitRentalFormFactors'),
        isFalse,
      );
    });

    test('a chosen kind reaches its own street leg', () {
      const options = RoutingOptions(
        firstMileModes: [TransitMode.rental],
        lastMileModes: [TransitMode.rental],
        firstMileRentalFormFactors: [
          RentalFormFactor.cargoBicycle,
          RentalFormFactor.moped,
        ],
        lastMileRentalFormFactors: [RentalFormFactor.bicycle],
      );
      final query = _query(options);

      expect(query['preTransitRentalFormFactors'], 'CARGO_BICYCLE,MOPED');
      expect(query['postTransitRentalFormFactors'], 'BICYCLE');
    });

    test('the two miles filter independently', () {
      // The server has always taken these separately. Holding one list for
      // both meant asking for a cargo bike to the station silently asked for
      // one on the way back too — and refusing one back refused it there.
      const options = RoutingOptions(
        firstMileModes: [TransitMode.rental],
        lastMileModes: [TransitMode.walk],
        firstMileRentalFormFactors: [RentalFormFactor.cargoBicycle],
      );
      final query = _query(options);

      expect(query['preTransitRentalFormFactors'], 'CARGO_BICYCLE');
      expect(query.containsKey('postTransitRentalFormFactors'), isFalse);
    });
  });

  group('storage', () {
    test('mile modes round-trip', () {
      const options = RoutingOptions(
        firstMileModes: [TransitMode.walk, TransitMode.rental],
        lastMileModes: [TransitMode.carParking, TransitMode.rental],
        firstMileRentalFormFactors: [RentalFormFactor.bicycle],
        lastMileRentalFormFactors: [RentalFormFactor.moped],
      );
      final restored = RoutingOptions.fromJson(options.toJson());

      expect(restored.firstMileModes, options.firstMileModes);
      expect(restored.lastMileModes, options.lastMileModes);
      // Stored apart, or a restart would put the two miles back on one list.
      expect(restored.firstMileRentalFormFactors, [RentalFormFactor.bicycle]);
      expect(restored.lastMileRentalFormFactors, [RentalFormFactor.moped]);
    });

    test('a manual carriage choice round-trips', () {
      final off = _bikeBothEnds.copyWith(bikeCarriageOverride: false);
      final restored = RoutingOptions.fromJson(off.toJson());
      expect(restored.bikeCarriageIsManual, isTrue);
      expect(restored.requireBikeTransport, isFalse);
    });

    test('an unreadable mile list falls back rather than routing nothing', () {
      final restored = RoutingOptions.fromJson(const {'firstMileModes': []});
      expect(restored.firstMileModes, [TransitMode.walk]);
    });
  });

  group('slider ranges', () {
    test('unlimited transfers omits the parameter', () {
      // A large number would still be a limit; the server should keep
      // deciding.
      final unlimited = const RoutingOptions(
        maxTransfers: 2,
      ).withTransfersSliderValue(RoutingOptions.unlimitedTransfersSliderValue);
      expect(unlimited.maxTransfers, isNull);
      expect(_query(unlimited).containsKey('maxTransfers'), isFalse);
    });

    test('the slider round-trips a real limit', () {
      for (var i = 0; i <= RoutingOptions.maxTransferChoice; i++) {
        final withLimit = RoutingOptions.defaults.withTransfersSliderValue(i);
        expect(withLimit.maxTransfers, i);
        expect(withLimit.transfersSliderValue, i);
      }
    });

    test('no limit reads as the top slider position', () {
      expect(
        RoutingOptions.defaults.transfersSliderValue,
        RoutingOptions.unlimitedTransfersSliderValue,
      );
    });

    test('the mile budget tops out at the server ceiling', () {
      expect(RoutingOptions.maxMileBudget, const Duration(hours: 2));
    });
  });

  group('transit selection', () {
    test('untouched options mean every mode', () {
      expect(RoutingOptions.defaults.transitSelection.isEverything, isTrue);
      expect(
        _query(RoutingOptions.defaults).containsKey('transitModes'),
        false,
      );
    });

    test('a narrowed selection survives a round trip', () {
      final narrowed = RoutingOptions.defaults.withTransitSelection(
        TransitSelection.everything.toggleGroup(TransitModeGroup.boat),
      );
      expect(
        narrowed.transitSelection.stateOf(TransitModeGroup.boat),
        GroupState.none,
      );
      expect(
        narrowed.transitSelection.stateOf(TransitModeGroup.rail),
        GroupState.all,
      );
    });

    test('a single mode reaches the query on its own', () {
      final intercityOnly = RoutingOptions.defaults.withTransitSelection(
        TransitSelection({TransitMode.longDistance}),
      );
      expect(_query(intercityOnly)['transitModes'], 'LONG_DISTANCE');
    });
  });

  group('journeys without transit', () {
    test('walk only by default, for as long as both street legs', () {
      final query = _query(RoutingOptions.defaults);

      expect(query['directModes'], 'WALK');
      expect(query['maxDirectTime'], '1800');
    });

    test('a bike taken to the station can be ridden all the way', () {
      const options = RoutingOptions(firstMileModes: [TransitMode.bike]);

      expect(options.directModes, [TransitMode.walk, TransitMode.bike]);
    });

    test('follows the way there, not the way back', () {
      const options = RoutingOptions(lastMileModes: [TransitMode.bike]);

      expect(options.directModes, [TransitMode.walk]);
    });

    test('park and ride drives; a drop-off does not carry over', () {
      expect(
        const RoutingOptions(
          firstMileModes: [TransitMode.carParking],
        ).directModes,
        [TransitMode.walk, TransitMode.car],
      );
      expect(
        const RoutingOptions(
          firstMileModes: [TransitMode.carDropoff],
        ).directModes,
        [TransitMode.walk],
      );
    });

    test('rents the vehicles picked for the way there', () {
      final options = RoutingOptions.defaults.copyWith(
        firstMileModes: const [TransitMode.walk, TransitMode.rental],
        firstMileRentalFormFactors: const [RentalFormFactor.bicycle],
      );
      final query = _query(options);

      expect(query['directModes'], 'WALK,RENTAL');
      expect(query['directRentalFormFactors'], 'BICYCLE');
    });

    test('budget is the sum of both street legs', () {
      const options = RoutingOptions(
        maxFirstMileTime: Duration(minutes: 20),
        maxLastMileTime: Duration(minutes: 10),
      );

      expect(options.maxDirectTime, const Duration(minutes: 30));
      expect(_query(options)['maxDirectTime'], '1800');
    });
  });

  group('withSettingsFrom', () {
    const stored = RoutingOptions(
      useRoutedTransfers: false,
      additionalTransferTime: Duration(minutes: 7),
      elevationCosts: ElevationCosts.high,
      wheelchairAccessibleOnly: true,
      maxTransfers: 1,
    );
    final search = RoutingOptions.defaults.copyWith(
      firstMileModes: const [TransitMode.bike],
      walkingSpeedKmh: 5.5,
    );

    test('takes the settings-only fields', () {
      final merged = search.withSettingsFrom(stored);

      expect(merged.useRoutedTransfers, isFalse);
      expect(merged.additionalTransferTime, const Duration(minutes: 7));
      expect(merged.elevationCosts, ElevationCosts.high);
    });

    test('keeps everything the search screen offers', () {
      final merged = search.withSettingsFrom(stored);

      expect(merged.firstMileModes, [TransitMode.bike]);
      expect(merged.walkingSpeedKmh, 5.5);
      expect(merged.wheelchairAccessibleOnly, isFalse);
      expect(merged.maxTransfers, isNull);
    });

    test('changes nothing when the settings already agree', () {
      expect(search.withSettingsFrom(RoutingOptions.defaults), search);
    });
  });

  group('rental providers', () {
    Map<String, String> query(RoutingOptions options) {
      final params = options.toPlanParams(
        fromPlace: '0,0',
        toPlace: '1,1',
        rentalProviderGroups: const ['Dott berlin', 'VOI'],
      );
      return {
        for (final entry in params.toQuery().entries)
          if (entry.value != null) entry.key: entry.value!,
      };
    }

    test('go with every leg that rents', () {
      final options = RoutingOptions.defaults.copyWith(
        firstMileModes: const [TransitMode.rental],
        firstMileRentalFormFactors: const [RentalFormFactor.bicycle],
        lastMileModes: const [TransitMode.rental],
        lastMileRentalFormFactors: const [RentalFormFactor.scooterStanding],
      );
      final sent = query(options);

      expect(sent['preTransitRentalProviderGroups'], 'Dott berlin,VOI');
      expect(sent['postTransitRentalProviderGroups'], 'Dott berlin,VOI');
      expect(sent['directRentalProviderGroups'], 'Dott berlin,VOI');
    });

    test('stay off legs with nothing to rent', () {
      final sent = query(RoutingOptions.defaults);

      expect(sent.keys.where((k) => k.contains('ProviderGroups')), isEmpty);
    });

    test('a refresh keeps the same vehicles and providers', () {
      final options = RoutingOptions.defaults.copyWith(
        firstMileModes: const [TransitMode.rental],
        firstMileRentalFormFactors: const [RentalFormFactor.bicycle],
      );
      final sent = options
          .toRefreshParams(
            serverLimit: const Duration(hours: 2),
            rentalProviderGroups: const ['VOI'],
          )
          .toQuery();

      expect(sent['preTransitRentalFormFactors'], 'BICYCLE');
      expect(sent['preTransitRentalProviderGroups'], 'VOI');
      expect(sent['postTransitRentalProviderGroups'], isNull);
    });
  });

  group('the way from the station can follow the way there', () {
    final linked = RoutingOptions.defaults.copyWith(
      firstMileModes: const [TransitMode.bike, TransitMode.rental],
      firstMileRentalFormFactors: const [RentalFormFactor.scooterStanding],
      maxFirstMileTime: const Duration(minutes: 25),
      lastMileModes: const [TransitMode.car],
      maxLastMileTime: const Duration(minutes: 5),
      lastMileSameAsFirst: true,
    );

    test('off unless asked for', () {
      expect(RoutingOptions.defaults.lastMileSameAsFirst, isFalse);
      expect(RoutingOptions.fromJson(const {}).lastMileSameAsFirst, isFalse);
    });

    test('a search sends the first mile as the last mile too', () {
      final sent = _query(linked);
      expect(sent['postTransitModes'], sent['preTransitModes']);
      expect(sent['maxPostTransitTime'], '${25 * 60}');
      expect(sent['postTransitRentalFormFactors'], 'SCOOTER_STANDING');
    });

    test('so does a refresh', () {
      final sent = linked
          .toRefreshParams(serverLimit: const Duration(hours: 2))
          .toQuery();
      expect(sent['postTransitModes'], sent['preTransitModes']);
      expect(sent['maxPostTransitTime'], sent['maxPreTransitTime']);
    });

    test('the rider\'s own last mile is kept while linked', () {
      expect(linked.lastMileModes, [TransitMode.car]);
      expect(linked.lastMileModesInUse, [TransitMode.bike, TransitMode.rental]);
    });

    test('a bike at the start is a bike at both ends', () {
      // Carriage follows the modes searched with, not the ones set aside.
      expect(linked.bikeAtBothEnds, isTrue);
      expect(linked.requireBikeTransport, isTrue);
      expect(linked.carAtBothEnds, isFalse);
    });

    test('a journey without transit gets both budgets as searched', () {
      expect(linked.maxDirectTime, const Duration(minutes: 50));
    });

    test('unlinking keeps what was searched, to edit from there', () {
      final unlinked = linked.withLastMileSameAsFirst(false);
      expect(unlinked.lastMileSameAsFirst, isFalse);
      expect(unlinked.lastMileModes, linked.firstMileModes);
      expect(unlinked.maxLastMileTime, linked.maxFirstMileTime);
      expect(
        unlinked.lastMileRentalFormFactors,
        linked.firstMileRentalFormFactors,
      );
      expect(_query(unlinked), _query(linked));
    });

    test('linking leaves the stored last mile alone', () {
      final relinked = linked
          .withLastMileSameAsFirst(false)
          .copyWith(lastMileModes: const [TransitMode.walk])
          .withLastMileSameAsFirst(true);
      expect(relinked.lastMileModes, [TransitMode.walk]);
      expect(relinked.lastMileModesInUse, linked.firstMileModes);
    });

    test('round-trips through storage', () {
      final restored = RoutingOptions.fromJson(linked.toJson());
      expect(restored.lastMileSameAsFirst, isTrue);
      expect(restored, linked);
      expect(restored == linked.withLastMileSameAsFirst(false), isFalse);
    });
  });
}
