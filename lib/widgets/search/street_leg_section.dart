import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/quick_access_layout.dart';
import '../../models/routing_options.dart';
import '../../models/street_leg_choice.dart';
import '../../utils/app_icons.dart';
import '../app_icon_view.dart';
import '../options/icon_controls.dart';
import 'leg_panel.dart';

/// What a leg's ring shows with nothing on: it is still walking.
const AppIcon _walking = GlyphIcon(LucideIcons.footprints);

/// The icon standing for a whole leg: the last of [sections] that is on, as
/// the row reads — picking up a bike on the way out should change it; which
/// was chosen first should not decide it forever.
AppIcon streetLegIcon(
  StreetLegChoice choice,
  List<QuickGroup<StreetItem>> sections,
) {
  final on = choice.sectionsOn(sections);
  return on.isEmpty ? _walking : on.last.icon;
}

/// A budget spelled out: minutes below an hour, hours past it.
///
/// A raw `120` next to a clock reads as a bug when the line above says two
/// hours.
String budgetSummaryText(Duration budget) {
  final minutes = budget.inMinutes;
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours h' : '$hours h $rest';
}

/// One street leg — to the station or from it — as sections and a budget.
class StreetLegSection extends StatelessWidget {
  const StreetLegSection({
    super.key,
    required this.sections,
    required this.choice,
    required this.budget,
    required this.maxBudget,
    required this.view,
    required this.onViewChanged,
    required this.tooltips,
    required this.onChanged,
    required this.onBudgetChanged,
    required this.limitToMyProviders,
    required this.providerNames,
    required this.onLimitToMyProvidersPressed,
  });

  /// The street sections, Other last; see [QuickAccessLayout.streetSections].
  final List<QuickGroup<StreetItem>> sections;

  final StreetLegChoice choice;
  final Duration budget;

  /// The server's own ceiling, so the slider cannot offer what will be
  /// clamped away.
  final Duration maxBudget;

  final LegView view;
  final ValueChanged<LegView> onViewChanged;
  final OptionTooltipController tooltips;
  final ValueChanged<StreetLegChoice> onChanged;
  final ValueChanged<Duration> onBudgetChanged;

  /// Whether rentals keep to the providers named in the settings. One
  /// setting for the whole journey, shown on both legs because it sits with
  /// the rest of the rental choices.
  final bool limitToMyProviders;

  /// The providers named in the settings, empty when there are none.
  final List<String> providerNames;
  final VoidCallback onLimitToMyProvidersPressed;

  @override
  Widget build(BuildContext context) {
    return LegPanel(
      tooltips: tooltips,
      view: view,
      onViewChanged: onViewChanged,
      sections: [
        for (final section in sections)
          if (section.items.isNotEmpty) _section(section),
      ],
      options: [
        // Whichever sections the shared vehicles sit in, the limit applies
        // to all of them, so it shows whenever anything is rented.
        if (choice.rentsAnything)
          LegOption.switchRow(
            icon: LucideIcons.userCheck,
            title: 'Only my sharing providers',
            subtitle: providerNames.isEmpty
                ? 'None set yet'
                : providerNames.join(', '),
            on: limitToMyProviders,
            onToggle: onLimitToMyProvidersPressed,
          ),
        LegOption.value(
          icon: LucideIcons.clock,
          title: 'Time budget',
          value: budgetSummaryText(budget),
          slider: (onChangeEnd) => _BudgetSlider(
            budget: budget,
            maxBudget: maxBudget,
            onChanged: onBudgetChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ],
    );
  }

  LegSection _section(QuickGroup<StreetItem> section) => LegSection(
    mark: AppIconView(section.icon),
    title: section.title,
    state: choice.stateOf(section.items),
    onToggle: () => onChanged(choice.toggleAll(section.items)),
    // Lorries and on-demand rides are not one way of travelling, and no one
    // wants all of them at once: listed, but no quick icon.
    inCompactRow: section.id != QuickAccessLayout.otherId,
    // A section of one has nothing to choose between.
    choices: section.items.length < 2
        ? const []
        : [
            for (final item in section.items)
              LegChoice(
                label: item.label,
                selected: choice.uses(item),
                onPressed: () => onChanged(choice.toggle(item)),
              ),
          ],
  );
}

class _BudgetSlider extends StatelessWidget {
  const _BudgetSlider({
    required this.budget,
    required this.maxBudget,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final Duration budget;
  final Duration maxBudget;
  final ValueChanged<Duration> onChanged;
  final VoidCallback? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final maxMinutes = maxBudget.inMinutes.toDouble();
    final step = RoutingOptions.mileBudgetStep.inMinutes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OptionSlider(
          value: budget.inMinutes.toDouble().clamp(0, maxMinutes),
          max: maxMinutes,
          divisions: (maxMinutes / step).round(),
          semanticLabel: 'Minutes',
          onChangeEnd: onChangeEnd,
          onChanged: (value) =>
              onChanged(Duration(minutes: (value / step).round() * step)),
        ),
        SliderScaleLabels(
          labels: [
            '0',
            budgetSummaryText(maxBudget ~/ 2),
            budgetSummaryText(maxBudget),
          ],
        ),
      ],
    );
  }
}
