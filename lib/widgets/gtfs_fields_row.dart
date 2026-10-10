import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../theme/app_colors.dart';

/// Small monospace line of raw GTFS identifiers (trip id, stop id, ...),
/// shown only when "Show GTFS fields" is on in the advanced settings. Renders
/// nothing while the setting is off or none of [fields] has a value.
class GtfsFieldsRow extends StatelessWidget {
  const GtfsFieldsRow({super.key, required this.fields});

  /// Label -> value. Entries with a null or empty value are skipped.
  final Map<String, String?> fields;

  @override
  Widget build(BuildContext context) {
    final enabled = context.select<ThemeProvider, bool>(
      (theme) => theme.showGtfsFields,
    );
    if (!enabled) return const SizedBox.shrink();

    final parts = [
      for (final entry in fields.entries)
        if (entry.value != null && entry.value!.isNotEmpty)
          '${entry.key}: ${entry.value}',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        parts.join('  ·  '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          fontFamily: 'monospace',
          color: AppColors.black.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}
