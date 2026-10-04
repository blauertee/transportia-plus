import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../theme/app_text.dart';
import '../widgets/app_icon_header.dart';
import '../widgets/app_page_scaffold.dart';
import '../widgets/section_title.dart';
import '../widgets/toggle_card.dart';

/// Switches for people who read the raw data: off by default, since none of
/// it helps anyone just planning a trip.
class AdvancedSettingsScreen extends StatelessWidget {
  const AdvancedSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();

    return AppPageScaffold(
      title: 'Advanced',
      scrollable: true,
      padding: const EdgeInsets.all(20),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const AppIconHeader(
            icon: LucideIcons.terminal,
            title: 'Advanced',
            subtitle: 'Technical details for debugging and development',
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),
              const SectionTitle(text: 'Data'),
              const SizedBox(height: 8),
              Text(
                'What the server calls things, next to what the app calls them',
                style: AppText.bodyFaint,
              ),
              const SizedBox(height: 16),
              ToggleCard(
                icon: LucideIcons.codeXml,
                title: 'Show GTFS fields',
                subtitle: theme.showGtfsFields
                    ? 'Trip and stop ids are shown on trips and departures'
                    : 'Show raw trip and stop ids on trips and departures',
                value: theme.showGtfsFields,
                onChanged: theme.setShowGtfsFields,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
