import 'package:flutter/services.dart';

/// The status and navigation bars for the app's own background.
///
/// Both bars are transparent and the app draws under them, so their icons sit
/// straight on the app's background: dark icons on the light theme, light on
/// the dark. Fixing them to one brightness left white clock and battery icons
/// on a white screen, which reads as no status bar at all.
///
/// `statusBarBrightness` is iOS's half of the same setting, and it names the
/// background rather than the icons, so it runs the other way round.
SystemUiOverlayStyle systemBarsFor({required bool isDark}) {
  final icons = isDark ? Brightness.light : Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: const Color(0x00000000),
    statusBarIconBrightness: icons,
    statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: const Color(0x00000000),
    systemNavigationBarIconBrightness: icons,
  );
}

/// The bars on a screen whose map runs up under the status bar.
///
/// The status bar's icons sit on the map, so they follow the map's style — the
/// app theme and the map style are chosen separately, and a dark app over the
/// default map otherwise gets white icons on a pale map. The navigation bar
/// keeps the app's: Flutter reads it from what is at the bottom of the screen,
/// and there that is the sheet, not the map.
SystemUiOverlayStyle systemBarsOverMap({
  required bool appIsDark,
  required bool mapIsDark,
}) => systemBarsFor(isDark: appIsDark).copyWith(
  statusBarIconBrightness: mapIsDark ? Brightness.light : Brightness.dark,
  statusBarBrightness: mapIsDark ? Brightness.dark : Brightness.light,
);
