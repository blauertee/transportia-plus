import 'package:flutter/cupertino.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/rental_provider_prefs.dart';
import '../../models/street_leg_choice.dart';
import '../../models/transitous/rentals_response.dart';
import '../../theme/app_colors.dart';
import '../../utils/rental_provider_search.dart';
import '../../widgets/options/icon_controls.dart';
import 'search_options_rows.dart';

/// The rental providers the rider has an account with, picked by name.
///
/// A field rather than a list: the server knows a few hundred groups, and
/// most are in cities the rider will never visit.
class SearchOptionsRentalProvidersCard extends StatefulWidget {
  const SearchOptionsRentalProvidersCard({
    super.key,
    required this.prefs,
    required this.catalogue,
    required this.nearby,
    this.loading = false,
    required this.onAdd,
    required this.onRemove,
    this.initialQuery = '',
  });

  final RentalProviderPrefs prefs;

  /// Every group the server lists. Null while it has never been fetched, so
  /// the field can say why it offers nothing.
  final List<RentalProviderGroup>? catalogue;

  /// Whether the list is still being fetched for the first time, so a
  /// missing one is not yet a failure.
  final bool loading;

  /// Ids of the groups around the rider, offered first.
  final Set<String> nearby;

  final ValueChanged<PickedProviderGroup> onAdd;
  final ValueChanged<String> onRemove;

  /// Text already in the field, for drafts.
  final String initialQuery;

  @override
  State<SearchOptionsRentalProvidersCard> createState() =>
      _SearchOptionsRentalProvidersCardState();
}

class _SearchOptionsRentalProvidersCardState
    extends State<SearchOptionsRentalProvidersCard> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialQuery,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _pick(RentalProviderGroup group) {
    widget.onAdd(PickedProviderGroup(id: group.id, name: group.name.trim()));
    _controller.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final catalogue = widget.catalogue;
    final listed = {for (final group in catalogue ?? const []) group.id};
    final suggestions = catalogue == null
        ? const <RentalProviderGroup>[]
        : suggestProviders(
            _controller.text,
            catalogue,
            picked: {for (final group in widget.prefs.groups) group.id},
            nearby: widget.nearby,
          );
    return OptionsGroup(
      title: 'Rental providers',
      footnote: _helpText(catalogue == null),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildField(enabled: catalogue != null),
              for (final group in suggestions)
                _SuggestionRow(
                  group: group,
                  nearby: widget.nearby.contains(group.id),
                  onTap: () => _pick(group),
                ),
              if (widget.prefs.groups.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final group in widget.prefs.groups)
                      ModeChip(
                        label: catalogue == null || listed.contains(group.id)
                            ? group.name
                            : '${group.name} · no longer listed',
                        onRemove: () => widget.onRemove(group.id),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _helpText(bool unavailable) {
    if (unavailable && widget.loading) return 'Loading the provider list…';
    if (unavailable) {
      return 'The provider list could not be loaded. Connect to the '
          'internet to add providers.';
    }
    if (widget.prefs.groups.isEmpty) {
      return 'Add the providers you have an account with. Some companies '
          'are listed once per city, so add each one you use.';
    }
    return 'Turn “Limit to my providers” on or off under Shared vehicles '
        'when planning a trip.';
  }

  Widget _buildField({required bool enabled}) {
    final hint = AppColors.black.withValues(alpha: 0.35);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.search, size: 15, color: hint),
          const SizedBox(width: 8),
          Expanded(
            child: CupertinoTextField.borderless(
              controller: _controller,
              enabled: enabled,
              placeholder: 'Add a provider',
              style: TextStyle(fontSize: 14.5, color: AppColors.black),
              placeholderStyle: TextStyle(fontSize: 14.5, color: hint),
              padding: const EdgeInsets.symmetric(vertical: 9),
              autocorrect: false,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.group,
    required this.nearby,
    required this.onTap,
  });

  final RentalProviderGroup group;
  final bool nearby;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    final vehicles = [
      for (final factor in group.formFactors)
        StreetItem.formFactorLabel(factor),
    ].join(' · ');
    final details = [if (nearby) 'Near you', if (vehicles.isNotEmpty) vehicles];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.black.withValues(alpha: 0.06)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name.trim(),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.black,
                    ),
                  ),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      details.join(' · '),
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.black.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(LucideIcons.plus, size: 16, color: accent),
          ],
        ),
      ),
    );
  }
}
