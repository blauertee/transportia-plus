import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/prefs_keys.dart';
import '../models/quick_access_layout.dart';

/// How the rider has arranged the search card's sections.
///
/// Held in memory once read, so the card can follow edits as they are made
/// without reading storage on every build.
class QuickAccessService {
  const QuickAccessService._();

  static final ValueNotifier<QuickAccessLayout> layoutListenable =
      ValueNotifier<QuickAccessLayout>(QuickAccessLayout.defaults);

  static Future<QuickAccessLayout>? _inFlight;
  static bool _loaded = false;

  static Future<QuickAccessLayout> load() async {
    if (_loaded) return layoutListenable.value;
    return (_inFlight ??= _load());
  }

  static Future<QuickAccessLayout> _load() async {
    try {
      final stored = await SharedPreferencesAsync().getString(
        PrefsKeys.quickAccessLayout,
      );
      final decoded = stored == null ? null : json.decode(stored);
      layoutListenable.value = decoded is Map<String, dynamic>
          ? QuickAccessLayout.fromJson(decoded)
          : QuickAccessLayout.defaults;
    } catch (e, stackTrace) {
      developer.log(
        'Could not read the quick access layout, using the defaults',
        name: 'QuickAccessService',
        error: e,
        stackTrace: stackTrace,
      );
      layoutListenable.value = QuickAccessLayout.defaults;
    } finally {
      _loaded = true;
      _inFlight = null;
    }
    return layoutListenable.value;
  }

  static Future<void> save(QuickAccessLayout layout) async {
    layoutListenable.value = layout;
    _loaded = true;
    await SharedPreferencesAsync().setString(
      PrefsKeys.quickAccessLayout,
      json.encode(layout.toJson()),
    );
  }

  /// Back to the default sections, which are then followed as they change
  /// in later releases rather than pinned as they are today.
  static Future<void> reset() async {
    layoutListenable.value = QuickAccessLayout.defaults;
    _loaded = true;
    await SharedPreferencesAsync().remove(PrefsKeys.quickAccessLayout);
  }

  /// Forgets what is held in memory, so the next call reads storage again.
  @visibleForTesting
  static void invalidate() {
    _loaded = false;
    _inFlight = null;
    layoutListenable.value = QuickAccessLayout.defaults;
  }
}
