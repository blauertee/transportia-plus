import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/semantics.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/quick_access_layout.dart';
import '../models/street_leg_choice.dart';
import '../models/transit_mode_group.dart';
import '../models/transitous/enums.dart';
import '../services/quick_access_service.dart';
import '../theme/app_colors.dart';
import '../utils/app_icons.dart';
import '../utils/haptics.dart';
import '../widgets/app_icon_view.dart';
import '../widgets/app_page_scaffold.dart';
import '../widgets/name_icon_dialog.dart';
import '../widgets/search/leg_panel.dart';

/// Icons offered first when a transport section's icon is changed.
const List<String> _transitSuggestions = [
  'lucide:train-front',
  'lucide:train-front-tunnel',
  'lucide:tram-front',
  'lucide:bus',
  'lucide:ship',
  'lucide:plane',
  'lucide:cable-car',
];

/// Icons offered first when a street section's icon is changed.
const List<String> _streetSuggestions = [
  'lucide:footprints',
  'lucide:bike',
  'lucide:scooter',
  'lucide:car',
  AppIcons.carKeyName,
  'lucide:car-taxi-front',
  'lucide:truck',
  'lucide:key-round',
];

/// How close to the top or bottom edge a dragged mode starts the list
/// scrolling, and how far it scrolls each frame.
const double _kEdgeScrollZone = 72;
const double _kEdgeScrollStep = 9;
const Duration _kEdgeScrollTick = Duration(milliseconds: 16);

/// A mode on its way from one section to another.
class _Moving {
  const _Moving({
    required this.item,
    required this.fromId,
    required this.street,
  });

  /// A [TransitMode] or a [StreetItem].
  final Object item;
  final String fromId;

  /// Which half it belongs to: a mode can only move within its own.
  final bool street;
}

/// Rearranges the search card's sections: which modes each holds, and what
/// each is called and shows.
///
/// Laid out like the search card's full view, so what is edited here is
/// recognisably what is tapped there. Sections cannot be added or removed,
/// and Other is whatever is left: it cannot be renamed.
class QuickAccessScreen extends StatefulWidget {
  const QuickAccessScreen({super.key});

  @override
  State<QuickAccessScreen> createState() => _QuickAccessScreenState();
}

class _QuickAccessScreenState extends State<QuickAccessScreen> {
  final ScrollController _scroll = ScrollController();
  final GlobalKey _viewport = GlobalKey();
  Timer? _edgeScroll;

  @override
  void initState() {
    super.initState();
    unawaited(QuickAccessService.load());
  }

  @override
  void dispose() {
    _edgeScroll?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  QuickAccessLayout get _layout => QuickAccessService.layoutListenable.value;

  void _drop(_Moving moving, String toId) {
    Haptics.lightTick();
    unawaited(
      QuickAccessService.save(
        moving.street
            ? _layout.moveStreet(moving.item as StreetItem, toId)
            : _layout.moveTransit(moving.item as TransitMode, toId),
      ),
    );
  }

  Future<void> _edit<T>(QuickGroup<T> group, {required bool street}) =>
      showCupertinoDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (_) => NameIconDialog(
          title: 'Edit section',
          name: group.title,
          iconName: group.iconName,
          suggestions: street ? _streetSuggestions : _transitSuggestions,
          pickerTitle: 'Section icon',
          onSaved: (name, icon) {
            // A section needs a heading; clearing the field keeps the old one.
            final edited = group.copyWith(
              title: name.isEmpty ? group.title : name,
              iconName: icon,
            );
            unawaited(
              QuickAccessService.save(
                street
                    ? _layout.withStreetGroup(edited as QuickGroup<StreetItem>)
                    : _layout.withTransitGroup(
                        edited as QuickGroup<TransitMode>,
                      ),
              ),
            );
          },
        ),
      );

  /// Scrolls while a dragged mode is held near the top or bottom edge, so a
  /// section off screen can still be reached.
  void _onDragUpdate(DragUpdateDetails details) {
    final box = _viewport.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final y = details.globalPosition.dy;
    final direction = y < top + _kEdgeScrollZone
        ? -1
        : y > top + box.size.height - _kEdgeScrollZone
        ? 1
        : 0;
    if (direction == 0) return _stopEdgeScroll();
    _edgeScroll ??= Timer.periodic(_kEdgeScrollTick, (_) {
      final position = _scroll.position;
      _scroll.jumpTo(
        (position.pixels + direction * _kEdgeScrollStep).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    });
  }

  void _stopEdgeScroll() {
    _edgeScroll?.cancel();
    _edgeScroll = null;
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: 'Quick access icons',
      body: ValueListenableBuilder<QuickAccessLayout>(
        valueListenable: QuickAccessService.layoutListenable,
        builder: (context, layout, _) => SingleChildScrollView(
          key: _viewport,
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
                child: Text(
                  'The icons on the search card switch a whole section on or '
                  'off. Hold a mode and drag it to move it, or tap it to pick '
                  'where it goes; tap the pencil to rename a section or '
                  'change its icon.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: AppColors.black.withValues(alpha: 0.55),
                  ),
                ),
              ),
              const _HalfTitle('Public transport'),
              for (final group in layout.transitSections)
                _section(
                  group,
                  half: layout.transitSections,
                  street: false,
                  labelOf: (mode) => TransitModeGroup.modeLabel(mode),
                ),
              const SizedBox(height: 12),
              const _HalfTitle('To and from the station'),
              for (final group in layout.streetSections)
                _section(
                  group,
                  half: layout.streetSections,
                  street: true,
                  labelOf: (item) => item.label,
                ),
              const SizedBox(height: 8),
              Center(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => unawaited(QuickAccessService.reset()),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Reset to default',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accentOf(context),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Moves [item] without dragging: what a tap on it opens, and what a
  /// screen reader's actions do.
  void _moveTo<T extends Object>(T item, String toId, {required bool street}) =>
      _drop(_Moving(item: item, fromId: '', street: street), toId);

  /// Asks where [item] should go, offering every other section of its half.
  Future<void> _showMoveMenu<T extends Object>(
    T item,
    String label,
    List<QuickGroup<T>> others, {
    required bool street,
  }) async {
    final toId = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text('Move “$label” to'),
        actions: [
          for (final target in others)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(context).pop(target.id),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIconView(
                    target.icon,
                    size: 20,
                    color: AppColors.accentOf(context),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      target.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // The app's accent, not the platform's blue, to match
                      // the icon beside it.
                      style: TextStyle(color: AppColors.accentOf(context)),
                    ),
                  ),
                ],
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: TextStyle(color: AppColors.accentOf(context)),
          ),
        ),
      ),
    );
    if (toId != null) _moveTo(item, toId, street: street);
  }

  Widget _section<T extends Object>(
    QuickGroup<T> group, {
    required List<QuickGroup<T>> half,
    required bool street,
    required String Function(T) labelOf,
  }) {
    final isOther = group.id == QuickAccessLayout.otherId;
    final others = [
      for (final target in half)
        if (target.id != group.id) target,
    ];
    return _SectionTarget(
      group: group,
      street: street,
      onDrop: (moving) => _drop(moving, group.id),
      onEdit: isOther ? null : () => _edit(group, street: street),
      note: !isOther
          ? null
          : street
          ? 'No quick icon here: everything not in a section above'
          : 'Everything not in a section above',
      bubbles: [
        for (final item in group.items)
          LongPressDraggable<_Moving>(
            data: _Moving(item: item, fromId: group.id, street: street),
            onDragStarted: Haptics.lightTick,
            onDragUpdate: _onDragUpdate,
            onDragEnd: (_) => _stopEdgeScroll(),
            onDraggableCanceled: (_, _) => _stopEdgeScroll(),
            feedback: _Bubble(labelOf(item), lifted: true),
            childWhenDragging: _Bubble(labelOf(item), ghost: true),
            // Dragging needs a finger and a sighted eye. A tap asks where
            // to instead, and a screen reader gets one action per
            // section, so neither depends on the drag.
            child: Semantics(
              button: true,
              label: '${labelOf(item)}, in ${group.title}',
              hint: 'Moves to another section',
              excludeSemantics: true,
              customSemanticsActions: {
                for (final target in others)
                  CustomSemanticsAction(label: 'Move to ${target.title}'): () =>
                      _moveTo(item, target.id, street: street),
              },
              child: GestureDetector(
                onTap: () =>
                    _showMoveMenu(item, labelOf(item), others, street: street),
                child: _Bubble(labelOf(item)),
              ),
            ),
          ),
      ],
    );
  }
}

class _HalfTitle extends StatelessWidget {
  const _HalfTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.black,
      ),
    ),
  );
}

/// A section as a drop target: its heading, its modes, and a highlight
/// while a mode from elsewhere in the same half is held over it.
class _SectionTarget extends StatelessWidget {
  const _SectionTarget({
    required this.group,
    required this.street,
    required this.onDrop,
    required this.onEdit,
    required this.note,
    required this.bubbles,
  });

  final QuickGroup<Object> group;
  final bool street;
  final ValueChanged<_Moving> onDrop;
  final VoidCallback? onEdit;
  final String? note;
  final List<Widget> bubbles;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    final faint = AppColors.black.withValues(alpha: 0.5);
    return DragTarget<_Moving>(
      onWillAcceptWithDetails: (details) =>
          details.data.street == street && details.data.fromId != group.id,
      onAcceptWithDetails: (details) => onDrop(details.data),
      builder: (context, candidates, _) {
        final hovered = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(8, 2, 6, 10),
          decoration: BoxDecoration(
            color: hovered ? AppColors.accentWash(accent) : null,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hovered ? accent : const Color(0x00000000),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LegHeading(
                mark: AppIconView(group.icon),
                title: group.title,
                look: HeadingLook.value,
                trailing: onEdit == null
                    ? null
                    : _EditButton(group.title, onEdit!),
              ),
              if (note case final note?)
                Padding(
                  padding: const EdgeInsets.only(
                    left: LegHeading.textIndent,
                    bottom: 6,
                  ),
                  child: Text(
                    note,
                    style: TextStyle(fontSize: 12, color: faint),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(left: LegHeading.textIndent),
                child: bubbles.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          // An empty section has no quick icon on the card
                          // until something is dropped back in.
                          'Drop modes here',
                          style: TextStyle(
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                            color: faint,
                          ),
                        ),
                      )
                    : Wrap(spacing: 6, runSpacing: 6, children: bubbles),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EditButton extends StatelessWidget {
  const _EditButton(this.title, this.onTap);

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Edit $title',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          LucideIcons.pencil,
          size: 16,
          color: AppColors.accentOf(context),
        ),
      ),
    ),
  );
}

/// A mode as a movable bubble: a grip, its name, a pill.
class _Bubble extends StatelessWidget {
  const _Bubble(this.label, {this.ghost = false, this.lifted = false});

  final String label;

  /// Where it was lifted from, while it is being dragged.
  final bool ghost;

  /// Under the finger.
  final bool lifted;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    final pill = Container(
      padding: const EdgeInsets.fromLTRB(7, 6, 11, 6),
      decoration: BoxDecoration(
        color: lifted
            ? AppColors.white
            : AppColors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: lifted ? accent : AppColors.black.withValues(alpha: 0.12),
          width: lifted ? 1.5 : 1,
        ),
        boxShadow: lifted
            ? [
                BoxShadow(
                  color: AppColors.solidBlack.withValues(alpha: 0.18),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.gripVertical,
            size: 13,
            color: AppColors.black.withValues(alpha: 0.35),
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              decoration: TextDecoration.none,
              color: AppColors.black.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
    // The lifted copy is drawn in the overlay, outside any text style.
    return Opacity(
      opacity: ghost ? 0.3 : 1,
      child: lifted
          ? DefaultTextStyle(style: const TextStyle(), child: pill)
          : pill,
    );
  }
}
