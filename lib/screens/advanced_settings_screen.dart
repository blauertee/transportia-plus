import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../models/map_render_profile.dart';
import '../models/motis_request_record.dart';
import '../providers/theme_provider.dart';
import '../api/motis_request_log.dart';
import '../services/map_rendering_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../navigation/routes.dart';
import '../widgets/app_screen.dart';
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

    return AppScreen.page(
      icon: LucideIcons.terminal,
      title: 'Advanced',
      subtitle: 'Technical details for debugging and development',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          if (MapRenderingService.instance.isSupported) ...[
            const SizedBox(height: 32),
            const _MapRenderingSection(),
          ],
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
          onPressed: () => context.openScreen(const RequestLogScreen()),
        ),
      ),
    );
  }
}

/// How maps are drawn: chosen by the app from the phone's GPU, or by hand
/// when a map stays blank or the app closes as one opens.
class _MapRenderingSection extends StatelessWidget {
  const _MapRenderingSection();

  @override
  Widget build(BuildContext context) {
    final service = MapRenderingService.instance;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final state = service.state;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle(text: 'Map rendering'),
            const SizedBox(height: 8),
            Text(
              'Worth changing only if a map stays blank, or the app closes '
              'as a map opens',
              style: AppText.bodyFaint,
            ),
            const SizedBox(height: 16),
            ToggleCard(
              icon: LucideIcons.map,
              title: 'Show maps',
              subtitle: state.mapsOff
                  ? 'Maps stay blank and load nothing, for phones where they '
                        'make the app close'
                  : 'Turn off if maps keep making the app close; they then '
                        'stay blank and load nothing',
              value: !state.mapsOff,
              onChanged: (on) => service.setMapsOff(!on),
            ),
            if (!state.mapsOff) ..._renderingChoices(service, state),
          ],
        );
      },
    );
  }

  /// How maps are drawn, while they are drawn at all.
  List<Widget> _renderingChoices(
    MapRenderingService service,
    MapRenderState state,
  ) {
    return [
      const SizedBox(height: 12),
      ToggleCard(
        icon: LucideIcons.wandSparkles,
        title: 'Choose automatically',
        subtitle: state.isAutomatic
            ? _detectedSummary(state)
            : 'The choices below apply instead',
        value: state.isAutomatic,
        onChanged: (automatic) =>
            service.setOverride(automatic ? null : state.detected),
      ),
      if (!state.isAutomatic) ..._manualChoices(service, state.effective),
      if (state.needsRestart) ...[
        const SizedBox(height: 12),
        Text(
          'Restart the app to switch to '
          '${_rendererName(state.effective.renderer)}',
          style: AppText.bodyMuted,
        ),
      ],
    ];
  }

  static String _detectedSummary(MapRenderState state) => state.detectedStandard
      ? 'Maps are drawn the standard way on this phone'
      : 'This phone has no Vulkan, so maps are drawn the compatible way';

  static String _rendererName(FlutterRenderer renderer) => switch (renderer) {
    FlutterRenderer.impeller => 'Impeller',
    FlutterRenderer.skia => 'Skia',
  };

  List<Widget> _manualChoices(
    MapRenderingService service,
    MapRenderProfile profile,
  ) {
    return [
      const SizedBox(height: 12),
      ToggleCard(
        icon: LucideIcons.cpu,
        title: 'Impeller',
        subtitle: profile.renderer == FlutterRenderer.impeller
            ? 'The app draws with Impeller, its newer renderer'
            : 'The app draws with Skia, its older renderer',
        value: profile.renderer == FlutterRenderer.impeller,
        onChanged: (on) => service.setOverride(
          profile.copyWith(
            renderer: on ? FlutterRenderer.impeller : FlutterRenderer.skia,
          ),
        ),
      ),
      const SizedBox(height: 12),
      ToggleCard(
        icon: LucideIcons.layers,
        title: 'Hybrid composition',
        subtitle: profile.composition == MapComposition.hybrid
            ? 'Android draws the map as a view of its own'
            : 'The map is copied into the app\'s picture',
        value: profile.composition == MapComposition.hybrid,
        onChanged: (on) => service.setOverride(
          profile.copyWith(
            composition: on ? MapComposition.hybrid : MapComposition.texture,
          ),
        ),
      ),
      const SizedBox(height: 12),
      ToggleCard(
        icon: LucideIcons.frame,
        title: 'SurfaceView',
        subtitle: profile.surface == MapSurface.surfaceView
            ? 'MapLibre draws into a SurfaceView'
            : 'MapLibre draws into a TextureView',
        value: profile.surface == MapSurface.surfaceView,
        onChanged: (on) => service.setOverride(
          profile.copyWith(
            surface: on ? MapSurface.surfaceView : MapSurface.textureView,
          ),
        ),
      ),
    ];
  }
}
