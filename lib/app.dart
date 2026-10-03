import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:oktoast/oktoast.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'environment.dart';
import 'constants/prefs_keys.dart';
import 'models/my_location.dart';
import 'models/time_selection.dart';
import 'providers/backend_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/itinerary_list_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/shared_trip_screen.dart';
import 'screens/welcome_screen.dart';
import 'services/backend_reload_service.dart';
import 'services/location_service.dart';
import 'services/transitous_geocode_service.dart';
import 'theme/system_bars.dart';
import 'utils/trip_link.dart';
import 'widgets/offline_banner_shell.dart';

class Transportia extends StatelessWidget {
  const Transportia({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(
          create: (_) {
            final backend = BackendProvider();
            BackendReloadService.watch(backend);
            return backend;
          },
        ),
      ],
      child: OKToast(
        child: Consumer<ThemeProvider>(
          builder: (context, themeProvider, _) {
            final baseTextStyle = TextStyle(
              color: themeProvider.textColor,
              fontSize: 14,
            );
            return WidgetsApp(
              title: Environment.appName,
              color: themeProvider.backgroundColor,
              debugShowCheckedModeBanner: false,
              localizationsDelegates: const [
                DefaultWidgetsLocalizations.delegate,
                DefaultCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('en', 'US'), Locale('en')],
              pageRouteBuilder:
                  <T>(RouteSettings settings, WidgetBuilder builder) {
                    return PageRouteBuilder<T>(
                      settings: settings,
                      pageBuilder: (context, animation, secondaryAnimation) =>
                          builder(context),
                      transitionsBuilder:
                          (context, animation, secondaryAnimation, child) =>
                              child,
                    );
                  },
              textStyle: baseTextStyle,
              builder: (context, child) {
                final content = child ?? const SizedBox.shrink();
                // Above every route, so each screen gets bars that match the
                // theme without having to ask for them.
                return AnnotatedRegion<SystemUiOverlayStyle>(
                  value: systemBarsFor(isDark: themeProvider.isDark),
                  child: ColoredBox(
                    color: themeProvider.backgroundColor,
                    child: IconTheme(
                      data: IconThemeData(color: themeProvider.textColor),
                      child: OfflineBannerShell(child: content),
                    ),
                  ),
                );
              },
              home: const _RootGate(),
            );
          },
        ),
      ),
    );
  }
}

class _RootGate extends StatefulWidget {
  const _RootGate();

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  static const _kWelcomeSeenKey = PrefsKeys.welcomeSeen;
  bool? _seen;
  StreamSubscription<Uri>? _appLinkSubscription;

  @override
  void initState() {
    super.initState();
    // After the welcome flag is read: a link that opens the app has to know
    // whether there are tabs to land on.
    unawaited(
      _init().then((_) {
        if (mounted) return _initDeepLinks();
      }),
    );
  }

  Future<void> _initDeepLinks() async {
    try {
      final appLinks = AppLinks();

      final initialLink = await appLinks.getInitialLink();
      if (initialLink != null) {
        _handleIncomingDeepLink(initialLink);
      }

      _appLinkSubscription = appLinks.uriLinkStream.listen(
        (uri) {
          _handleIncomingDeepLink(uri);
        },
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Failed to process incoming app link: $error');
          debugPrint('$stackTrace');
        },
      );
    } catch (error, stackTrace) {
      debugPrint('Unable to initialize deep link handling: $error');
      debugPrint('$stackTrace');
    }
  }

  Future<void> _init() async {
    final prefs = SharedPreferencesAsync();
    final seen = await prefs.getBool(_kWelcomeSeenKey) ?? false;
    if (!mounted) return;
    setState(() {
      _seen = seen;
    });
  }

  void _handleWelcomeFinished() {
    if (!mounted) return;
    setState(() => _seen = true);
  }

  void _handleIncomingDeepLink(Uri uri) {
    if (uri.scheme == 'geo') {
      _handleGeoLink(uri);
      return;
    }
    final link = TripLink.tryParse(uri);
    if (link == null) return;
    Navigator.of(
      context,
    ).push(CupertinoPageRoute(builder: (_) => SharedTripScreen(link: link)));
  }

  void _handleGeoLink(Uri uri) {
    final destination = _parseGeoUri(uri);
    if (destination == null) {
      debugPrint('Unable to parse geo link: $uri');
      return;
    }
    debugPrint('Received geo link: $uri');

    if (_seen != true) {
      // No routing screen behind the welcome flow to land on.
      final currentPosition = LocationService.currentPosition();
      Navigator.of(context).push(
        CupertinoPageRoute(
          builder: (_) => ItineraryListScreen(
            fromLat: currentPosition.then((position) => position.latitude),
            fromLon: currentPosition.then((position) => position.longitude),
            toLat: destination.latitude,
            toLon: destination.longitude,
            timeSelection: TimeSelection.now(),
          ),
        ),
      );
      return;
    }
    unawaited(
      ItineraryListScreen.openOverRoutingScreen(
        Navigator.of(context),
        from: myLocationSuggestion,
        to: TransitousLocationSuggestion.fromLatLon(destination),
        time: TimeSelection.now(),
      ),
    );
  }

  /// Parses `geo:lat,lon` and `geo:0,0?q=lat,lon(label)` URIs, the two
  /// forms produced by Android/iOS when a `geo:` link is shared or tapped.
  LatLng? _parseGeoUri(Uri uri) {
    final direct = TransitousGeocodeService.tryParseLatLon(uri.path);
    if (direct != null && (direct.latitude != 0 || direct.longitude != 0)) {
      return direct;
    }

    final query = uri.queryParameters['q'];
    if (query != null) {
      final match = RegExp(
        r'^\s*(-?\d{1,3}(?:\.\d+)?)\s*,\s*(-?\d{1,3}(?:\.\d+)?)',
      ).firstMatch(query);
      if (match != null) {
        final lat = double.tryParse(match.group(1)!);
        final lon = double.tryParse(match.group(2)!);
        if (lat != null && lon != null) {
          return LatLng(lat, lon);
        }
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_seen == null) {
      return const SizedBox.expand();
    }
    final mainChild = _seen!
        ? const MainNavigationScreen()
        : WelcomeScreen(onFinished: _handleWelcomeFinished);

    return mainChild;
  }

  @override
  void dispose() {
    _appLinkSubscription?.cancel();
    super.dispose();
  }
}
