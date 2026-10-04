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
  static const String otherIconName = 'lucide:shapes';

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
        iconName: 'lucide:footprints',
        items: [StreetMode(TransitMode.walk)],
      ),
      QuickGroup(
        id: 'own-bike',
        title: 'Own bike',
        iconName: 'lucide:bike',
        items: [StreetMode(TransitMode.bike)],
      ),
      QuickGroup(
        id: 'shared-light',
        title: 'Shared bikes & scooters',
        iconName: 'lucide:scooter',
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
        iconName: 'lucide:car',
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
    TransitModeGroup.rail: 'lucide:train-front',
    TransitModeGroup.metro: 'lucide:train-front-tunnel',
    TransitModeGroup.bus: 'lucide:bus',
    TransitModeGroup.boat: 'lucide:ship',
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

  /// This layout with the transit section of [group]'s id replaced by it:
  /// a rename or a new icon.
  QuickAccessLayout withTransitGroup(QuickGroup<TransitMode> group) =>
      QuickAccessLayout(
        transit: [for (final g in transit) g.id == group.id ? group : g],
        street: street,
      );

  /// [withTransitGroup] for a street section.
  QuickAccessLayout withStreetGroup(QuickGroup<StreetItem> group) =>
      QuickAccessLayout(
        transit: transit,
        street: [for (final g in street) g.id == group.id ? group : g],
      );

  /// [mode] moved into the transit section [toId], or into Other when that
  /// is [otherId]. Sections keep the modes in the pickers' order, so where it
  /// lands within one is not the rider's to choose.
  QuickAccessLayout moveTransit(TransitMode mode, String toId) =>
      QuickAccessLayout(
        transit: [
          for (final g in transit)
            g.copyWith(
              items: [
                for (final m in TransitModeGroup.allSelectable)
                  if (m == mode ? g.id == toId : g.items.contains(m)) m,
              ],
            ),
        ],
        street: street,
      );

  /// [item] moved into the street section [toId], or into Other.
  QuickAccessLayout moveStreet(StreetItem item, String toId) =>
      QuickAccessLayout(
        transit: transit,
        street: [
          for (final g in street)
            g.copyWith(
              items: [
                for (final i in StreetItem.all)
                  if (i == item ? g.id == toId : g.items.contains(i)) i,
              ],
            ),
        ],
      );

  Map<String, dynamic> toJson() => {
    'transit': [
      for (final g in transit)
        _groupJson(g, [for (final mode in g.items) mode.wireName]),
    ],
    'street': [
      for (final g in street)
        _groupJson(g, [for (final item in g.items) item.key]),
    ],
  };

  static Map<String, dynamic> _groupJson(QuickGroup g, List<String> items) => {
    'id': g.id,
    'title': g.title,
    'icon': g.iconName,
    'items': items,
  };

  /// Reads a stored layout section by section: a section that is missing or
  /// unreadable takes its default, without the rest following it. The
  /// sections and their order are always the defaults'; an item claimed by
  /// an earlier section is not claimed again, so nothing sits in two.
  factory QuickAccessLayout.fromJson(Map<String, dynamic> json) {
    final fallback = QuickAccessLayout.defaults;
    return QuickAccessLayout(
      transit: _readGroups(
        json['transit'],
        fallback.transit,
        (raw) => switch (TransitMode.fromWire(raw)) {
          final mode? => TransitModeGroup.canonical(mode),
          null => null,
        },
      ),
      street: _readGroups(
        json['street'],
        fallback.street,
        (raw) => raw is String ? StreetItem.fromKey(raw) : null,
      ),
    );
  }

  static List<QuickGroup<T>> _readGroups<T>(
    Object? raw,
    List<QuickGroup<T>> defaults,
    T? Function(Object?) readItem,
  ) {
    final stored = {
      if (raw is List)
        for (final entry in raw)
          if (entry is Map<String, dynamic> && entry['id'] is String)
            entry['id'] as String: entry,
    };
    final read = [
      for (final fallback in defaults)
        _readGroup(stored[fallback.id], fallback, readItem),
    ];
    // Stored sections claim their items first; a section that fell back to
    // its default must not take back an item the rider moved elsewhere.
    final claimed = <T>{
      for (final (i, g) in read.indexed)
        if (stored.containsKey(defaults[i].id)) ...g.items,
    };
    final seen = <T>{};
    return [
      for (final (i, g) in read.indexed)
        g.copyWith(
          items: [
            for (final item in g.items)
              if ((stored.containsKey(defaults[i].id) ||
                      !claimed.contains(item)) &&
                  seen.add(item))
                item,
          ],
        ),
    ];
  }

  static QuickGroup<T> _readGroup<T>(
    Map<String, dynamic>? json,
    QuickGroup<T> fallback,
    T? Function(Object?) readItem,
  ) {
    if (json == null) return fallback;
    final title = json['title'];
    final icon = json['icon'];
    final items = json['items'];
    return fallback.copyWith(
      title: title is String && title.trim().isNotEmpty ? title : null,
      iconName: icon is String && icon.isNotEmpty ? icon : null,
      items: items is List
          ? [
              for (final entry in items)
                if (readItem(entry) case final item?) item,
            ]
          : null,
    );
  }

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
