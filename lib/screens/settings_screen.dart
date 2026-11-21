import 'dart:async';

import 'package:transportia/screens/advanced_settings_screen.dart';
import 'package:transportia/screens/appearance_screen.dart';
import 'package:transportia/screens/calendar_settings_screen.dart';
import 'package:transportia/services/calendar_service.dart';
import 'package:transportia/screens/developer_info_screen.dart';
import 'package:transportia/screens/info_screen.dart';
import 'package:transportia/screens/legal_screen.dart';
import 'package:transportia/screens/location_settings_screen.dart';
import 'package:transportia/utils/custom_page_route.dart';
import 'package:transportia/screens/search_options_screen.dart';
import 'package:transportia/environment.dart';
import 'package:flutter/cupertino.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../widgets/settings_section.dart';
import '../utils/app_version.dart';
import '../widgets/settings_tile.dart';
import '../widgets/app_screen.dart';
import '../theme/app_text.dart';

/// How long the version line has to be held to open the developer screen.
/// Long enough that nobody reaches it by resting a thumb there.
const Duration _kDebugUnlockHold = Duration(seconds: 5);

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Timer? _debugHoldTimer;
  bool _debugOpened = false;

  @override
  void dispose() {
    _debugHoldTimer?.cancel();
    super.dispose();
  }

  void _startDebugHold() {
    _debugHoldTimer?.cancel();
    _debugOpened = false;
    _debugHoldTimer = Timer(_kDebugUnlockHold, _openDeveloperInfo);
  }

  void _cancelDebugHold() {
    _debugHoldTimer?.cancel();
    _debugHoldTimer = null;
  }

  void _openDeveloperInfo() {
    if (!mounted || _debugOpened) return;
    _debugOpened = true;
    Navigator.of(
      context,
    ).push(CustomPageRoute(child: const DeveloperInfoScreen()));
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    return AppScreen.tab(
      icon: LucideIcons.settings,
      title: 'Settings',
      subtitle: 'User Preferences & Information',
      // The sections carry their own side padding.
      padding: const EdgeInsets.only(top: 4),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsSection(
            title: 'Preferences',
            children: [
              SettingsTile(
                icon: LucideIcons.mapPin,
                title: 'Location',
                subtitle: 'Location permissions',
                onPressed: () {
                  Navigator.of(context).push(
                    CustomPageRoute(child: const LocationSettingsScreen()),
                  );
                },
              ),
              SettingsTile(
                icon: LucideIcons.palette,
                title: 'Appearance',
                subtitle: 'Theme and display',
                onPressed: () {
                  Navigator.of(
                    context,
                  ).push(CustomPageRoute(child: const AppearanceScreen()));
                },
              ),
              SettingsTile(
                icon: LucideIcons.settings2,
                title: 'Search and routing options',
                subtitle: 'Place search, rental providers, transfers',
                onPressed: () {
                  Navigator.of(
                    context,
                  ).push(CustomPageRoute(child: const SearchOptionsScreen()));
                },
              ),
              SettingsTile(
                icon: LucideIcons.terminal,
                title: 'Advanced',
                subtitle: 'Technical details for debugging',
                onPressed: () {
                  Navigator.of(context).push(
                    CustomPageRoute(child: const AdvancedSettingsScreen()),
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 12),

          if (CalendarService.isSupported) ...[
            SettingsSection(
              title: 'Synchronization',
              children: [
                SettingsTile(
                  icon: LucideIcons.calendarSync,
                  title: CalendarSettingsScreen.title,
                  subtitle: 'Add saved trips to your calendar',
                  onPressed: () {
                    Navigator.of(context).push(
                      CustomPageRoute(child: const CalendarSettingsScreen()),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],

          SettingsSection(
            title: 'About',
            children: [
              SettingsTile(
                icon: LucideIcons.info,
                title: 'About ${Environment.appName}',
                subtitle: 'About, credits, and more',
                onPressed: () {
                  Navigator.of(
                    context,
                  ).push(CustomPageRoute(child: const InfoScreen()));
                },
              ),
              SettingsTile(
                icon: LucideIcons.scale,
                title: 'Legal',
                subtitle: 'Privacy policy and terms of service',
                onPressed: () {
                  Navigator.of(
                    context,
                  ).push(CustomPageRoute(child: const LegalScreen()));
                },
              ),
            ],
          ),

          const SizedBox(height: 32),

          Center(
            child: Column(
              children: [
                GestureDetector(
                  onTapDown: (_) => _startDebugHold(),
                  onTapUp: (_) => _cancelDebugHold(),
                  onTapCancel: _cancelDebugHold,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/branding/logo_rounded_min.png',
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(Environment.appName, style: AppText.heading),
                const SizedBox(height: 4),
                Text('Version ${AppVersion.current}', style: AppText.subtitle),
                const SizedBox(height: 4),
                Text(
                  'Created by Wafler.one, plussed by blauertee',
                  style: AppText.subtitle.copyWith(fontSize: 12),
                ),
                const SizedBox(height: 112),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
