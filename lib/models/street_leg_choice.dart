import 'quick_access_layout.dart';
import 'routing_options.dart';
import 'transit_mode_group.dart';
import 'transitous/enums.dart';

/// One thing a street leg can use: a way of getting about, or a kind of
/// shared vehicle.
///
/// Both kinds sit side by side in the search card's sections, so a section
/// can hold driving and shared cars alike. Renting itself is not an item: it
/// follows the vehicles (see [StreetLegChoice]).
sealed class StreetItem {
  const StreetItem();

  /// Every item, in the order the pickers read: the modes, then the shared
  /// vehicles.
  static final List<StreetItem> all = [
    for (final mode in RoutingOptions.streetModeChoices)
      if (mode != TransitMode.rental) StreetMode(mode),
    for (final factor in RentalFormFactor.values) SharedVehicle(factor),
  ];

  /// What a choice is called under its section's heading.
  String get label;

  /// How it is stored: stable across releases, unlike its position.
  String get key;

  /// The item stored as [key], if this build knows it.
  static StreetItem? fromKey(String key) {
    for (final item in all) {
      if (item.key == key) return item;
    }
    return null;
  }

  static String modeLabel(TransitMode mode) => switch (mode) {
    TransitMode.walk => 'Walk',
    TransitMode.bike => 'Bike',
    TransitMode.car => 'Drive',
    TransitMode.carParking => 'Park & ride',
    TransitMode.carDropoff => 'Drop-off',
    TransitMode.odm => 'On demand',
    TransitMode.flex => 'Flexible',
    TransitMode.hgv => 'Lorry',
    TransitMode.rental => 'Rental',
    _ => 'Walk',
  };

  static String formFactorLabel(RentalFormFactor factor) => switch (factor) {
    RentalFormFactor.bicycle => 'Bike',
    RentalFormFactor.cargoBicycle => 'Cargo bike',
    RentalFormFactor.scooterStanding => 'E-scooter',
    RentalFormFactor.scooterSeated => 'Seated scooter',
    RentalFormFactor.moped => 'Moped',
    RentalFormFactor.car => 'Shared car',
    RentalFormFactor.other => 'Other',
  };
}

final class StreetMode extends StreetItem {
  const StreetMode(this.mode);

  final TransitMode mode;

  @override
  String get label => StreetItem.modeLabel(mode);

  @override
  String get key => 'mode:${mode.wireName}';

  @override
  bool operator ==(Object other) => other is StreetMode && other.mode == mode;

  @override
  int get hashCode => mode.hashCode;
}

final class SharedVehicle extends StreetItem {
  const SharedVehicle(this.factor);

  final RentalFormFactor factor;

  @override
  String get label => StreetItem.formFactorLabel(factor);

  @override
  String get key => 'vehicle:${factor.wireName}';

  @override
  bool operator ==(Object other) =>
      other is SharedVehicle && other.factor == factor;

  @override
  int get hashCode => factor.hashCode;
}

/// What one street leg may use: its modes and which shared vehicles count.
///
/// One value rather than two, because the rental mode follows the vehicles —
/// picking the first shared vehicle turns rentals on, dropping the last turns
/// them off — and two separate edits would let one overwrite the other.
class StreetLegChoice {
  const StreetLegChoice({required this.modes, required this.formFactors});

  final List<TransitMode> modes;
  final List<RentalFormFactor> formFactors;

  bool has(TransitMode mode) => modes.contains(mode);
  bool rents(RentalFormFactor factor) => formFactors.contains(factor);

  bool uses(StreetItem item) => switch (item) {
    StreetMode(:final mode) => has(mode),
    SharedVehicle(:final factor) => rents(factor),
  };

  /// How much of a section is on.
  GroupState stateOf(List<StreetItem> items) =>
      GroupState.of(items.where(uses).length, items.length);

  /// Switches a whole section: off when all of it is on, otherwise all on,
  /// so a partly-on section is completed rather than cleared.
  StreetLegChoice toggleAll(List<StreetItem> items) {
    final on = stateOf(items) != GroupState.all;
    final modes = {
      for (final item in items)
        if (item case StreetMode(:final mode)) mode,
    };
    final factors = {
      for (final item in items)
        if (item case SharedVehicle(:final factor)) factor,
    };
    return _with(
      modes: {
        for (final m in this.modes)
          if (!modes.contains(m)) m,
        if (on) ...modes,
      },
      formFactors: {
        for (final f in formFactors)
          if (!factors.contains(f)) f,
        if (on) ...factors,
      },
    );
  }

  StreetLegChoice toggle(StreetItem item) => switch (item) {
    StreetMode(:final mode) => toggleMode(mode),
    SharedVehicle(:final factor) => toggleFormFactor(factor),
  };

  StreetLegChoice toggleMode(TransitMode mode) => _with(
    modes: has(mode) ? ({...modes}..remove(mode)) : {...modes, mode},
    formFactors: formFactors.toSet(),
  );

  StreetLegChoice toggleFormFactor(RentalFormFactor factor) => _with(
    modes: modes.toSet(),
    formFactors: rents(factor)
        ? ({...formFactors}..remove(factor))
        : {...formFactors, factor},
  );

  /// Puts both lists in their canonical order and moves the rental mode with
  /// the vehicles: rentals are exactly the vehicles picked for them.
  static StreetLegChoice _with({
    required Set<TransitMode> modes,
    required Set<RentalFormFactor> formFactors,
  }) {
    final renting = formFactors.isNotEmpty;
    return StreetLegChoice(
      modes: [
        for (final m in RoutingOptions.streetModeChoices)
          if (m == TransitMode.rental ? renting : modes.contains(m)) m,
      ],
      formFactors: [
        for (final f in RentalFormFactor.values)
          if (formFactors.contains(f)) f,
      ],
    );
  }

  /// Whether any shared vehicle is picked, so a provider limit applies.
  bool get rentsAnything => formFactors.isNotEmpty;

  /// The sections of [sections] that are at least partly on, in card order.
  List<QuickGroup<StreetItem>> sectionsOn(
    List<QuickGroup<StreetItem>> sections,
  ) => [
    for (final section in sections)
      if (section.items.isNotEmpty && stateOf(section.items) != GroupState.none)
        section,
  ];

  /// The leg in a line, as the collapsed stage shows it: the sections on,
  /// named by their headings.
  String summary(List<QuickGroup<StreetItem>> sections) {
    final on = sectionsOn(sections);
    if (on.isEmpty) return StreetItem.modeLabel(TransitMode.walk);
    // A list in a sentence: only its first word is capitalised.
    return [
      on.first.title,
      for (final section in on.skip(1)) section.title.toLowerCase(),
    ].join(', ');
  }
}
