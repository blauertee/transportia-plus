import 'quick_access_layout.dart';
import 'transitous/enums.dart';

/// The four transport groups the search screen offers as icons.
///
/// MOTIS has two dozen transit modes, and a rider does not think in that
/// vocabulary — they think "train, metro, bus, boat". The groups are a
/// shorthand for picking several modes at once, not a replacement for them:
/// every mode is still individually selectable, so a search can ask for
/// intercity rail alone the way the server allows.
enum TransitModeGroup {
  rail('Rail', [
    TransitMode.highspeedRail,
    TransitMode.longDistance,
    TransitMode.nightRail,
    TransitMode.regionalRail,
    TransitMode.suburban,
  ]),

  /// Tram sits here rather than with [rail]: light rail and metro are the same
  /// kind of trip for a rider, and it keeps "Rail" meaning mainline.
  metro('Metro', [TransitMode.subway, TransitMode.tram]),

  bus('Bus', [TransitMode.bus, TransitMode.coach]),

  boat('Boat', [TransitMode.ferry]);

  const TransitModeGroup(this.label, this.modes);

  final String label;
  final List<TransitMode> modes;

  /// Modes worth offering but not worth an icon of their own.
  static const List<TransitMode> extras = [
    TransitMode.airplane,
    TransitMode.funicular,
    TransitMode.aerialLift,
    TransitMode.odm,
    TransitMode.rideSharing,
    TransitMode.flex,
    TransitMode.other,
  ];

  /// The trains and coaches that run between regions rather than within one:
  /// what a regional ticket such as the Deutschlandticket does not cover.
  static const Set<TransitMode> longDistance = {
    TransitMode.highspeedRail,
    TransitMode.longDistance,
    TransitMode.nightRail,
    TransitMode.coach,
  };

  /// Every mode a rider can pick, in the order the dropdown lists them.
  ///
  /// Excludes the server-side expanders (`TRANSIT`, `RAIL`), the debug routes,
  /// and the deprecated aliases: offering both "Metro" and "Subway" as ticks
  /// would be two names for one thing.
  static const List<TransitMode> allSelectable = [
    ...[
      TransitMode.highspeedRail,
      TransitMode.longDistance,
      TransitMode.nightRail,
      TransitMode.regionalRail,
      TransitMode.suburban,
    ],
    ...[TransitMode.subway, TransitMode.tram],
    ...[TransitMode.bus, TransitMode.coach],
    TransitMode.ferry,
    ...extras,
  ];

  /// Canonical mode for a stored one, folding the upstream aliases in.
  static TransitMode canonical(TransitMode mode) => switch (mode) {
    TransitMode.metro => TransitMode.subway,
    TransitMode.regionalFastRail => TransitMode.regionalRail,
    TransitMode.cableCar || TransitMode.arealLift => TransitMode.aerialLift,
    _ => mode,
  };

  /// Rider-facing name for any selectable mode.
  ///
  /// Names match the ones the reference web client uses, so a rider who has
  /// seen one recognises the other — "Intercity Rail" rather than
  /// `LONG_DISTANCE`.
  static String modeLabel(TransitMode mode) => switch (canonical(mode)) {
    TransitMode.highspeedRail => 'High-speed rail',
    TransitMode.longDistance => 'Intercity rail',
    TransitMode.nightRail => 'Night rail',
    TransitMode.regionalRail => 'Regional rail',
    TransitMode.suburban => 'Suburban rail',
    TransitMode.subway => 'Subway',
    TransitMode.tram => 'Tram',
    TransitMode.bus => 'Bus',
    TransitMode.coach => 'Long-distance bus',
    TransitMode.ferry => 'Ferry',
    TransitMode.airplane => 'Flights',
    TransitMode.funicular => 'Funicular',
    TransitMode.aerialLift => 'Cable car',
    TransitMode.odm => 'On demand',
    TransitMode.rideSharing => 'Ride share',
    TransitMode.flex => 'Flexible',
    _ => 'Other',
  };

  /// Which of this group's modes are selected.
  GroupState stateIn(Set<TransitMode> selected) =>
      GroupState.of(modes.where(selected.contains).length, modes.length);
}

/// How much of a group is switched on.
enum GroupState {
  none,
  some,
  all;

  /// [on] of [total] switched on.
  static GroupState of(int on, int total) {
    if (on == 0) return GroupState.none;
    return on == total ? GroupState.all : GroupState.some;
  }
}

/// The transit modes a search may use.
///
/// Held as one flat set rather than as group switches plus a handful of
/// extras: the server takes any subset, and a rider who wants intercity rail
/// but not regional should be able to say so. The groups are shortcuts over
/// this set, not a coarser model behind it.
///
/// Kept as one type so the icon row, the chips, the summary line and
/// `toPlanParams()` cannot disagree about what is selected.
class TransitSelection {
  const TransitSelection(this.modes);

  final Set<TransitMode> modes;

  /// Everything on — the state the server assumes when `transitModes` is
  /// absent.
  static final TransitSelection everything = TransitSelection(
    TransitModeGroup.allSelectable.toSet(),
  );

  bool get isEverything =>
      modes.length == TransitModeGroup.allSelectable.length;

  bool get isEmpty => modes.isEmpty;

  bool has(TransitMode mode) =>
      modes.contains(TransitModeGroup.canonical(mode));

  GroupState stateOf(TransitModeGroup group) => group.stateIn(modes);

  /// Turns a whole group on, or off when all of it is already on.
  ///
  /// Partly on counts as off for this purpose: tapping a half-lit icon should
  /// complete it rather than clear the modes you just picked by hand.
  TransitSelection toggleGroup(TransitModeGroup group) {
    final next = Set.of(modes);
    if (group.stateIn(modes) == GroupState.all) {
      next.removeAll(group.modes);
    } else {
      next.addAll(group.modes);
    }
    return TransitSelection(next);
  }

  /// How much of [section] is on: for sets that are not a
  /// [TransitModeGroup], such as the extras.
  GroupState stateOfModes(List<TransitMode> section) =>
      GroupState.of(section.where(modes.contains).length, section.length);

  /// [toggleGroup] for any set of modes.
  TransitSelection toggleModes(List<TransitMode> section) {
    final next = Set.of(modes);
    if (stateOfModes(section) == GroupState.all) {
      next.removeAll(section);
    } else {
      next.addAll(section);
    }
    return TransitSelection(next);
  }

  /// Nothing long-distance is on, and something else is.
  bool get isRegionalOnly =>
      modes.isNotEmpty && !modes.any(TransitModeGroup.longDistance.contains);

  /// Drops every long-distance mode, or brings them all back.
  ///
  /// Back means all four, whichever were on before: the switch says "not
  /// only regional", and any of them could be the one a rider was missing.
  TransitSelection toggleRegionalOnly() => TransitSelection(
    isRegionalOnly
        ? {...modes, ...TransitModeGroup.longDistance}
        : {
            for (final mode in modes)
              if (!TransitModeGroup.longDistance.contains(mode)) mode,
          },
  );

  TransitSelection toggleMode(TransitMode mode) {
    final canonical = TransitModeGroup.canonical(mode);
    final next = Set.of(modes);
    if (!next.remove(canonical)) next.add(canonical);
    return TransitSelection(next);
  }

  /// Modes that are on but that no lit section accounts for, so a summary
  /// has to name them one by one.
  ///
  /// A mode is covered when everything it belongs to is on: its section in
  /// [groups], or the modes no section holds taken together, which are all
  /// on unless somebody narrowed them.
  List<TransitMode> uncoveredModes(List<QuickGroup<TransitMode>> groups) => [
    for (final mode in TransitModeGroup.allSelectable)
      if (modes.contains(mode) && !_isCovered(mode, groups)) mode,
  ];

  bool _allOthersOn(List<QuickGroup<TransitMode>> groups) => TransitModeGroup
      .allSelectable
      .where((mode) => !groups.any((g) => g.items.contains(mode)))
      .every(modes.contains);

  bool get _isEverythingRegional =>
      isRegionalOnly &&
      TransitModeGroup.allSelectable.every(
        (mode) =>
            modes.contains(mode) ||
            TransitModeGroup.longDistance.contains(mode),
      );

  bool _isCovered(TransitMode mode, List<QuickGroup<TransitMode>> groups) {
    for (final group in groups) {
      if (group.items.contains(mode)) {
        return stateOfModes(group.items) == GroupState.all;
      }
    }
    return _allOthersOn(groups);
  }

  /// Flat mode list for `/plan`.
  ///
  /// Empty when everything is on, because sending the full list would pin the
  /// set to the modes this build happens to know about.
  List<TransitMode> toModes() {
    if (isEverything) return const [];
    return [
      for (final mode in TransitModeGroup.allSelectable)
        if (modes.contains(mode)) mode,
    ];
  }

  /// Rebuilds the selection from a stored flat list.
  ///
  /// Aliases fold onto their canonical mode, and anything this build does not
  /// recognise is dropped rather than discarding the whole list.
  factory TransitSelection.fromModes(List<TransitMode> modes) {
    if (modes.isEmpty) return everything;
    final canonical = modes.map(TransitModeGroup.canonical).toSet();
    return TransitSelection({
      for (final mode in TransitModeGroup.allSelectable)
        if (canonical.contains(mode)) mode,
    });
  }

  /// One line naming what is on, for the collapsed section.
  ///
  /// Says "All transport" rather than listing everything: enumerating twenty
  /// modes truncates mid-word in the common case where nothing is excluded.
  /// Whole sections are named by their heading, so narrowing to rail reads
  /// "Rail" rather than five rail modes. [groups] are the sections, Other
  /// left out: it is "more".
  String summary(List<QuickGroup<TransitMode>> groups) {
    if (isEverything) return 'All transport';
    if (isEmpty) return 'No transport';
    if (_isEverythingRegional) return 'Regional only';
    return [
      for (final group in groups)
        if (group.items.isNotEmpty &&
            stateOfModes(group.items) == GroupState.all)
          group.title,
      if (_allOthersOn(groups)) 'more',
      for (final mode in uncoveredModes(groups))
        TransitModeGroup.modeLabel(mode),
    ].join(', ');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TransitSelection &&
          other.modes.length == modes.length &&
          other.modes.containsAll(modes));

  @override
  int get hashCode => Object.hashAllUnordered(modes);
}
