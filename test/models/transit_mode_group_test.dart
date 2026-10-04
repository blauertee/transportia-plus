import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/models/quick_access_layout.dart';
import 'package:transportia/models/transit_mode_group.dart';
import 'package:transportia/models/transitous/enums.dart';

TransitSelection _of(List<TransitMode> modes) =>
    TransitSelection(modes.toSet());

final _groups = QuickAccessLayout.defaults.transit;

void main() {
  group('the selectable list', () {
    test('leaves out the expanders, the aliases and the debug routes', () {
      const excluded = [
        // Expand server-side, so offering them as ticks would double up with
        // the modes they expand to.
        TransitMode.transit,
        TransitMode.rail,
        // Deprecated aliases: two names for one thing.
        TransitMode.metro,
        TransitMode.regionalFastRail,
        TransitMode.cableCar,
        TransitMode.arealLift,
        TransitMode.debugBusRoute,
        TransitMode.debugRailwayRoute,
        TransitMode.debugFerryRoute,
      ];
      for (final mode in excluded) {
        expect(
          TransitModeGroup.allSelectable,
          isNot(contains(mode)),
          reason: '${mode.wireName} should not be pickable',
        );
      }
    });

    test('covers every group and every extra', () {
      for (final group in TransitModeGroup.values) {
        for (final mode in group.modes) {
          expect(TransitModeGroup.allSelectable, contains(mode));
        }
      }
      for (final mode in TransitModeGroup.extras) {
        expect(TransitModeGroup.allSelectable, contains(mode));
      }
    });

    test('every mode has a name of its own', () {
      final labels = <String>{};
      for (final mode in TransitModeGroup.allSelectable) {
        final label = TransitModeGroup.modeLabel(mode);
        expect(label, isNotEmpty);
        expect(labels.add(label), isTrue, reason: '$label is used twice');
      }
    });
  });

  group('groups', () {
    test('read as all, some or none', () {
      expect(
        TransitSelection.everything.stateOf(TransitModeGroup.rail),
        GroupState.all,
      );
      expect(
        _of([TransitMode.longDistance]).stateOf(TransitModeGroup.rail),
        GroupState.some,
      );
      expect(
        _of([TransitMode.bus]).stateOf(TransitModeGroup.rail),
        GroupState.none,
      );
    });

    test('a half-lit group completes rather than clearing', () {
      // Tapping a partial icon should finish the job; clearing the modes just
      // picked by hand would be the opposite of what the tap looks like.
      final partial = _of([TransitMode.longDistance]);
      final tapped = partial.toggleGroup(TransitModeGroup.rail);

      expect(tapped.stateOf(TransitModeGroup.rail), GroupState.all);
      expect(
        tapped
            .toggleGroup(TransitModeGroup.rail)
            .stateOf(TransitModeGroup.rail),
        GroupState.none,
      );
    });

    test('tram belongs to metro, not rail', () {
      expect(TransitModeGroup.metro.modes, contains(TransitMode.tram));
      expect(TransitModeGroup.rail.modes, isNot(contains(TransitMode.tram)));
    });
  });

  group('what the icons cannot show', () {
    test('a fully lit group contributes no chips', () {
      final rail = _of(TransitModeGroup.rail.modes);
      expect(rail.uncoveredModes(_groups), isEmpty);
    });

    test('a partial group names its selected members', () {
      final selection = _of([TransitMode.longDistance, TransitMode.nightRail]);
      expect(selection.uncoveredModes(_groups), [
        TransitMode.longDistance,
        TransitMode.nightRail,
      ]);
    });

    test('extras always name themselves', () {
      final selection = _of([
        ...TransitModeGroup.rail.modes,
        TransitMode.airplane,
      ]);
      expect(selection.uncoveredModes(_groups), [TransitMode.airplane]);
    });
  });

  group('the wire list', () {
    test('everything on sends nothing', () {
      // Sending the full list would pin the set to the modes this build
      // happens to know about.
      expect(TransitSelection.everything.toModes(), isEmpty);
      expect(TransitSelection.everything.isEverything, isTrue);
    });

    test('a single mode reaches the wire alone', () {
      expect(_of([TransitMode.longDistance]).toModes(), [
        TransitMode.longDistance,
      ]);
    });

    test('an empty stored list means everything', () {
      expect(TransitSelection.fromModes(const []), TransitSelection.everything);
    });

    test('round-trips a narrowed selection', () {
      final selection = _of([
        TransitMode.longDistance,
        TransitMode.tram,
        TransitMode.airplane,
      ]);
      expect(TransitSelection.fromModes(selection.toModes()), selection);
    });

    test('folds the deprecated aliases onto the real mode', () {
      final restored = TransitSelection.fromModes([
        TransitMode.metro,
        TransitMode.regionalFastRail,
        TransitMode.cableCar,
      ]);

      expect(restored.has(TransitMode.subway), isTrue);
      expect(restored.has(TransitMode.regionalRail), isTrue);
      expect(restored.has(TransitMode.aerialLift), isTrue);
      expect(restored.toModes(), isNot(contains(TransitMode.metro)));
    });

    test('drops a mode this build does not recognise rather than the list', () {
      final restored = TransitSelection.fromModes([
        TransitMode.bus,
        TransitMode.transit,
      ]);
      expect(restored.has(TransitMode.bus), isTrue);
      expect(restored.toModes(), [TransitMode.bus]);
    });
  });

  group('summary', () {
    test('says all transport rather than listing everything', () {
      expect(TransitSelection.everything.summary(_groups), 'All transport');
    });

    test('names a whole group by its group', () {
      expect(_of(TransitModeGroup.rail.modes).summary(_groups), 'Rail');
    });

    test('names the modes when a group is only partly on', () {
      expect(
        _of([TransitMode.longDistance]).summary(_groups),
        'Intercity rail',
      );
    });

    test('mixes group names and mode names', () {
      final selection = _of([
        ...TransitModeGroup.bus.modes,
        TransitMode.airplane,
      ]);
      expect(selection.summary(_groups), 'Bus, Flights');
    });

    test('says so when nothing is on', () {
      expect(_of(const []).summary(_groups), 'No transport');
    });
  });

  group('regional only', () {
    final everything = TransitSelection.everything;

    test('drops the four long-distance services and nothing else', () {
      final regional = everything.toggleRegionalOnly();
      expect(regional.isRegionalOnly, isTrue);
      for (final mode in TransitModeGroup.longDistance) {
        expect(regional.has(mode), isFalse, reason: mode.name);
      }
      expect(
        regional.modes.length,
        TransitModeGroup.allSelectable.length -
            TransitModeGroup.longDistance.length,
      );
    });

    test('turning it off brings all four back', () {
      final back = everything.toggleRegionalOnly().toggleRegionalOnly();
      expect(back.isEverything, isTrue);
    });

    test('unticking them by hand reads as regional only too', () {
      var selection = everything;
      for (final mode in TransitModeGroup.longDistance) {
        selection = selection.toggleMode(mode);
      }
      expect(selection.isRegionalOnly, isTrue);
    });

    test('nothing at all is not regional only', () {
      expect(const TransitSelection({}).isRegionalOnly, isFalse);
    });

    test('says so in the summary, but only for the full regional set', () {
      expect(everything.toggleRegionalOnly().summary(_groups), 'Regional only');
      final narrower = everything.toggleRegionalOnly().toggleMode(
        TransitMode.ferry,
      );
      expect(narrower.summary(_groups), isNot('Regional only'));
    });
  });

  group('any set of modes as a section', () {
    test('is on, partly on or off', () {
      const extras = TransitModeGroup.extras;
      expect(TransitSelection.everything.stateOfModes(extras), GroupState.all);
      expect(
        TransitSelection({extras.first}).stateOfModes(extras),
        GroupState.some,
      );
      expect(const TransitSelection({}).stateOfModes(extras), GroupState.none);
    });

    test('a partly-on section is completed, a full one cleared', () {
      const extras = TransitModeGroup.extras;
      final some = TransitSelection({extras.first});
      expect(some.toggleModes(extras).stateOfModes(extras), GroupState.all);
      expect(
        TransitSelection.everything.toggleModes(extras).stateOfModes(extras),
        GroupState.none,
      );
    });
  });
}
