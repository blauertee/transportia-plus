import '../utils/app_icons.dart';
import 'street_leg_choice.dart';
import 'transit_mode_group.dart';
import 'transitous/enums.dart';

/// One section of the search card: a heading with an icon, and the things a
/// tap on that icon switches together.
///
/// A shortcut over the leg's own selection, never a coarser model behind it:
/// every item stays individually switchable under its heading.
class QuickGroup<T> {
  const QuickGroup({
    required this.id,
    required this.title,
    required this.iconName,
    required this.items,
  });

  /// Stable across renames, so a stored layout finds its section again.
  final String id;
  final String title;

  /// A name [AppIcons] resolves.
  final String iconName;
  final List<T> items;

  AppIcon get icon => AppIcons.resolve(iconName);

  QuickGroup<T> copyWith({String? title, String? iconName, List<T>? items}) =>
      QuickGroup(
        id: id,
        title: title ?? this.title,
        iconName: iconName ?? this.iconName,
        items: items ?? this.items,
      );
}

/// How the search card groups the modes into sections: four for the ride,
/// five for the way to and from the station, and on each side an Other for
/// whatever none of them holds.
///
/// Other is never stored. It is the remainder, so moving an item between
/// sections can never lose it.
class QuickAccessLayout {
  const QuickAccessLayout({required this.transit, required this.street});

  final List<QuickGroup<TransitMode>> transit;
  final List<QuickGroup<StreetItem>> street;

  static const String otherId = 'other';
  static const String otherTitle = 'Other';
  static const String otherIconName = 'shapes';

  static final QuickAccessLayout defaults = QuickAccessLayout(
    transit: [
      for (final group in TransitModeGroup.values)
        QuickGroup(
          id: group.name,
          title: group.label,
          iconName: _transitIconNames[group]!,
          items: group.modes,
        ),
    ],
    street: const [
      QuickGroup(
        id: 'walk',
        title: 'Walk',
        iconName: 'footprints',
        items: [StreetMode(TransitMode.walk)],
      ),
      QuickGroup(
        id: 'own-bike',
        title: 'Own bike',
        iconName: 'bike',
        items: [StreetMode(TransitMode.bike)],
      ),
      QuickGroup(
        id: 'shared-light',
        title: 'Shared bikes & scooters',
        iconName: 'scooter',
        items: [
          SharedVehicle(RentalFormFactor.bicycle),
          SharedVehicle(RentalFormFactor.cargoBicycle),
          SharedVehicle(RentalFormFactor.scooterStanding),
          SharedVehicle(RentalFormFactor.scooterSeated),
          SharedVehicle(RentalFormFactor.other),
        ],
      ),
      // Own and shared cars apart: together, one tap switched both on, and
      // a rider with a car to hand would always take their own.
      QuickGroup(
        id: 'own-car',
        title: 'Own car',
        iconName: 'car',
        items: [
          StreetMode(TransitMode.car),
          StreetMode(TransitMode.carParking),
          StreetMode(TransitMode.carDropoff),
        ],
      ),
      // Mopeds with the cars: both need a driving licence, which is the
      // line a rider actually draws.
      QuickGroup(
        id: 'shared-car',
        title: 'Shared cars & mopeds',
        iconName: AppIcons.carKeyName,
        items: [
          SharedVehicle(RentalFormFactor.car),
          SharedVehicle(RentalFormFactor.moped),
        ],
      ),
    ],
  );

  static const Map<TransitModeGroup, String> _transitIconNames = {
    TransitModeGroup.rail: 'train-front',
    TransitModeGroup.metro: 'train-front-tunnel',
    TransitModeGroup.bus: 'bus',
    TransitModeGroup.boat: 'ship',
  };

  /// Transit modes no section holds.
  List<TransitMode> get otherTransit => [
    for (final mode in TransitModeGroup.allSelectable)
      if (!transit.any((g) => g.items.contains(mode))) mode,
  ];

  /// Street items no section holds.
  List<StreetItem> get otherStreet => [
    for (final item in StreetItem.all)
      if (!street.any((g) => g.items.contains(item))) item,
  ];

  /// Every transit section, Other last.
  List<QuickGroup<TransitMode>> get transitSections => [
    ...transit,
    QuickGroup(
      id: otherId,
      title: otherTitle,
      iconName: otherIconName,
      items: otherTransit,
    ),
  ];

  /// Every street section, Other last.
  List<QuickGroup<StreetItem>> get streetSections => [
    ...street,
    QuickGroup(
      id: otherId,
      title: otherTitle,
      iconName: otherIconName,
      items: otherStreet,
    ),
  ];
}
