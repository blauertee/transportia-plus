import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../models/motis_request_record.dart';
import '../providers/theme_provider.dart';
import '../api/motis_request_log.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../utils/custom_page_route.dart';
import '../widgets/app_icon_header.dart';
import '../widgets/app_page_scaffold.dart';
import '../widgets/section_title.dart';
import '../widgets/settings_tile.dart';
import '../widgets/toggle_card.dart';
import 'request_log_screen.dart';

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
              const SizedBox(height: 12),
              ToggleCard(
                icon: LucideIcons.clipboardCopy,
                title: 'Show copy canvas data button',
                subtitle: theme.showGraphCopyButton
                    ? 'The journey graph has a button that copies what it draws'
                    : 'Copy what the journey graph draws, to report a drawing problem',
                value: theme.showGraphCopyButton,
                onChanged: theme.setShowGraphCopyButton,
              ),
              const SizedBox(height: 32),
              const SectionTitle(text: 'Requests'),
              const SizedBox(height: 8),
              Text(
                'What the app asks the server, to compare with other clients',
                style: AppText.bodyFaint,
              ),
              const SizedBox(height: 16),
              ToggleCard(
                icon: LucideIcons.fileClock,
                title: 'Log MOTIS requests',
                subtitle: theme.logMotisRequests
                    ? 'Requests to the server are kept until the app closes'
                    : 'Keep the requests sent to the server, to inspect them',
                value: theme.logMotisRequests,
                onChanged: theme.setLogMotisRequests,
              ),
              const SizedBox(height: 12),
              const _RequestLogCard(),
            ],
          ),
        ],
      ),
    );
  }
}

/// Opens the request log, with a count of what is in it.
///
/// Stays open while logging is off: what was logged before switching it off
/// is still worth reading.
class _RequestLogCard extends StatelessWidget {
  const _RequestLogCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.black.withValues(alpha: 0.04)),
      ),
      child: ValueListenableBuilder<List<MotisRequestRecord>>(
        valueListenable: MotisRequestLog.records,
        builder: (context, records, _) => SettingsTile(
          icon: LucideIcons.scrollText,
          title: 'Request log',
          subtitle: switch (records.length) {
            0 => 'No requests logged yet',
            1 => '1 request',
            final n => '$n requests',
          },
          onPressed: () => Navigator.of(
            context,
          ).push(CustomPageRoute(child: const RequestLogScreen())),
        ),
      ),
    );
  }
}
