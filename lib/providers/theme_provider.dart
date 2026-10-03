import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/prefs_keys.dart';

enum AppThemeMode { light, dark, system }

/// How far the search card's options are open when the card appears. The
/// rider can open or close any of it from there.
enum SearchOptionsOpening {
  /// Each stage as its one-line summary.
  closed,

  /// Each stage open on its quick picks.
  stagesOpen,

  /// Each stage open on every option it has.
  everything,
}

class ThemeProvider extends ChangeNotifier with WidgetsBindingObserver {
  static const String _accentColorKey = PrefsKeys.accentColor;
  static const String _mapStyleKey = PrefsKeys.mapStyle;
  static const String _appThemeKey = PrefsKeys.appTheme;
  static const String _vibrationsEnabledKey = PrefsKeys.vibrationsEnabled;
  static const String _searchMapEnabledKey = PrefsKeys.searchMapEnabled;
  static const String _searchOptionsOpeningKey = PrefsKeys.searchOptionsOpening;
  static const String _showCaloriesKey = PrefsKeys.showCalories;

  static const Color defaultAccentColor = Color.fromARGB(255, 0, 113, 133);
  static const String defaultMapStyle = 'default';
  static const AppThemeMode defaultAppThemeMode = AppThemeMode.light;
  static const bool defaultVibrationsEnabled = true;
  static const bool defaultSearchMapEnabled = true;
  static const SearchOptionsOpening defaultSearchOptionsOpening =
      SearchOptionsOpening.closed;
  static const bool defaultShowCalories = true;

  static const Color lightBackground = Color(0xFFFFFFFF);
  static const Color darkBackground = Color(0xFF161616);
  static const Color lightText = Color(0xFF000000);
  static const Color darkText = Color(0xFFFFFFFF);

  static ThemeProvider? _instance;

  // TODO: Host remotely
  static const Map<String, String> mapStyleUrls = {
    'default': 'assets/styles/default.json',
    'light': 'assets/styles/light.json',
    'dark': 'assets/styles/dark.json',
  };

  Color _accentColor = defaultAccentColor;
  String _mapStyle = defaultMapStyle;
  AppThemeMode _appThemeMode = defaultAppThemeMode;
  bool _vibrationsEnabled = defaultVibrationsEnabled;
  bool _searchMapEnabled = defaultSearchMapEnabled;
  SearchOptionsOpening _searchOptionsOpening = defaultSearchOptionsOpening;
  bool _showCalories = defaultShowCalories;
  bool _isInitialized = false;

  static ThemeProvider? get instance => _instance;

  Color get accentColor => _accentColor;
  String get mapStyle => _mapStyle;

  /// Whether the map is drawn dark. Only the dark style is; the default style
  /// is a light map, whatever the app theme.
  bool get isMapDark => _mapStyle == 'dark';
  String get mapStyleUrl =>
      mapStyleUrls[_mapStyle] ?? mapStyleUrls[defaultMapStyle]!;
  AppThemeMode get appThemeMode => _appThemeMode;
  bool get vibrationsEnabled => _vibrationsEnabled;
  SearchOptionsOpening get searchOptionsOpening => _searchOptionsOpening;
  bool get showCalories => _showCalories;

  /// The rider's choice, as the appearance toggle shows it.
  bool get searchMapEnabled => _searchMapEnabled;

  /// Whether the search screen may build its map right now.
  ///
  /// False until the stored choice has been read, not just when it is off:
  /// the map starts fetching tiles the moment it is built, so a rider who
  /// turned it off to save data would otherwise pay for one map on every
  /// launch before the setting arrived.
  bool get showsSearchMap => _isInitialized && _searchMapEnabled;
  bool get isInitialized => _isInitialized;

  AppThemeMode get _effectiveAppThemeMode {
    if (_appThemeMode == AppThemeMode.system) {
      final brightness =
          WidgetsBinding.instance.platformDispatcher.platformBrightness;
      return brightness == Brightness.dark
          ? AppThemeMode.dark
          : AppThemeMode.light;
    }
    return _appThemeMode;
  }

  bool get isDark => _effectiveAppThemeMode == AppThemeMode.dark;

  Color get backgroundColor => isDark ? darkBackground : lightBackground;

  Color get textColor => isDark ? darkText : lightText;

  ThemeProvider() {
    _instance = this;
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = SharedPreferencesAsync();

    final colorValue = await prefs.getInt(_accentColorKey);
    if (colorValue != null) {
      _accentColor = Color(colorValue);
    }

    _mapStyle = await prefs.getString(_mapStyleKey) ?? defaultMapStyle;

    final savedTheme = await prefs.getString(_appThemeKey);
    if (savedTheme != null) {
      _appThemeMode = AppThemeMode.values.firstWhere(
        (mode) => mode.name == savedTheme,
        orElse: () => defaultAppThemeMode,
      );
    }

    _vibrationsEnabled =
        await prefs.getBool(_vibrationsEnabledKey) ?? defaultVibrationsEnabled;

    _searchMapEnabled =
        await prefs.getBool(_searchMapEnabledKey) ?? defaultSearchMapEnabled;

    final savedOpening = await prefs.getString(_searchOptionsOpeningKey);
    _searchOptionsOpening = SearchOptionsOpening.values.firstWhere(
      (opening) => opening.name == savedOpening,
      orElse: () => defaultSearchOptionsOpening,
    );

    _showCalories =
        await prefs.getBool(_showCaloriesKey) ?? defaultShowCalories;

    _isInitialized = true;
    notifyListeners();
  }

  Future<void> setAccentColor(Color color) async {
    if (_accentColor == color) return;

    _accentColor = color;
    notifyListeners();

    final prefs = SharedPreferencesAsync();
    await prefs.setInt(_accentColorKey, color.toARGB32());
  }

  Future<void> resetAccentColor() async {
    if (_accentColor == defaultAccentColor) return;

    _accentColor = defaultAccentColor;
    notifyListeners();

    final prefs = SharedPreferencesAsync();
    await prefs.remove(_accentColorKey);
  }

  Future<void> setMapStyle(String style) async {
    if (_mapStyle == style) return;
    if (!mapStyleUrls.containsKey(style)) return;

    _mapStyle = style;
    notifyListeners();

    final prefs = SharedPreferencesAsync();
    await prefs.setString(_mapStyleKey, style);
  }

  Future<void> setAppThemeMode(AppThemeMode mode) async {
    if (_appThemeMode == mode) return;

    _appThemeMode = mode;
    notifyListeners();

    final prefs = SharedPreferencesAsync();
    await prefs.setString(_appThemeKey, mode.name);
  }

  Future<void> setVibrationsEnabled(bool enabled) async {
    if (_vibrationsEnabled == enabled) return;

    _vibrationsEnabled = enabled;
    notifyListeners();

    final prefs = SharedPreferencesAsync();
    await prefs.setBool(_vibrationsEnabledKey, enabled);
  }

  Future<void> setSearchMapEnabled(bool enabled) async {
    if (_searchMapEnabled == enabled) return;

    _searchMapEnabled = enabled;
    notifyListeners();

    final prefs = SharedPreferencesAsync();
    await prefs.setBool(_searchMapEnabledKey, enabled);
  }

  Future<void> setSearchOptionsOpening(SearchOptionsOpening opening) async {
    if (_searchOptionsOpening == opening) return;

    _searchOptionsOpening = opening;
    notifyListeners();

    final prefs = SharedPreferencesAsync();
    await prefs.setString(_searchOptionsOpeningKey, opening.name);
  }

  Future<void> setShowCalories(bool show) async {
    if (_showCalories == show) return;

    _showCalories = show;
    notifyListeners();

    final prefs = SharedPreferencesAsync();
    await prefs.setBool(_showCaloriesKey, show);
  }

  @override
  void didChangePlatformBrightness() {
    if (_appThemeMode == AppThemeMode.system) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_instance == this) {
      _instance = null;
    }
    super.dispose();
  }
}
