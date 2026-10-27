import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/itinerary.dart';
import '../services/journey_graph_service.dart';
import '../utils/journey_graph.dart';

/// What is locked on a results screen, and what the searches those locks
/// started found. Shared by the screen's list and graph, so both show the
/// same journeys and a lock set in one holds in the other.
///
/// A locked station is a via stop. A locked ride fixes the journey up to
/// where it gets off, and the results become what goes on from there. Each
/// change of locks searches again and replaces what the last search found;
/// with nothing locked the screen's own results stand.
class JourneyLocksController extends ChangeNotifier {
  JourneyLocksController({
    required this.query,
    RideLock? initialLock,
    this.search = JourneyGraphService.search,
  }) {
    if (initialLock != null) {
      _lock = initialLock;
      _locks = JourneyLocks(rideKeys: {initialLock.key});
      // Until the search answers, the fixed journey on its own.
      _results = [initialLock.itinerary];
      unawaited(_search());
    }
  }

  /// The search being locked, read when a lock is set: the screen may only
  /// know where it starts once its first page has loaded.
  final JourneyQuery Function() query;

  final JourneyGraphSearcher search;

  JourneyLocks _locks = const JourneyLocks();
  JourneyLocks get locks => _locks;

  /// The locked stations, by [GraphStation.key], for their ids and names.
  final Map<String, GraphStation> _stations = {};
  Iterable<GraphStation> get stations => _stations.values;

  RideLock? _lock;
  RideLock? get lock => _lock;

  bool get isLocked => !_locks.isEmpty;

  /// What the latest search found; null with nothing locked, when the
  /// screen's own results are the ones to show.
  List<Itinerary>? _results;
  List<Itinerary>? get results => _results;

  bool _searching = false;
  bool get searching => _searching;

  /// Cursors to the pages around what the latest search found.
  String? _earlier;
  String? _later;
  bool get hasEarlier => _earlier != null;
  bool get hasLater => _later != null;

  bool _loadingEarlier = false;
  bool _loadingLater = false;
  bool get loadingEarlier => _loadingEarlier;
  bool get loadingLater => _loadingLater;

  /// Why the last lock changed nothing: a search that failed or found
  /// nothing, or a station too many.
  String? _problem;
  String? get problem => _problem;

  /// Bumped by every search, so an answer that arrives after a newer search
  /// began is dropped.
  int _generation = 0;
  bool _disposed = false;

  /// Locks the journey [on] up to [ride], replacing any ride locked before:
  /// locking another ride moves where the journey is fixed up to.
  void lockRide(Itinerary on, Leg ride) {
    _lock = RideLock(on, ride);
    _locks = JourneyLocks(
      stationKeys: _locks.stationKeys,
      rideKeys: {_lock!.key},
    );
    unawaited(_search());
  }

  void unlockRide() {
    _lock = null;
    _locks = JourneyLocks(stationKeys: _locks.stationKeys);
    unawaited(_search());
  }

  void toggleStation(GraphStation station) {
    if (_stations.remove(station.key) == null) {
      final passed = _lock?.passes(station.key) ?? false;
      if (!passed && _via.length >= JourneyGraphService.maxVia) {
        _problem =
            'At most ${JourneyGraphService.maxVia} stations can be locked.';
        notifyListeners();
        return;
      }
      _stations[station.key] = station;
    }
    _locks = _locks.toggleStation(station.key);
    unawaited(_search());
  }

  /// Drops every lock: back to the search from where the journey starts.
  void clear() {
    _lock = null;
    _stations.clear();
    _locks = const JourneyLocks();
    unawaited(_search());
  }

  /// Locked stations the fixed part does not already pass, as via stops.
  List<GraphStation> get _via => [
    for (final station in _stations.values)
      if (!(_lock?.passes(station.key) ?? false)) station,
  ];

  Future<void> _search() async {
    final generation = ++_generation;
    _problem = null;
    _earlier = _later = null;
    _loadingEarlier = _loadingLater = false;
    if (!isLocked) {
      _results = null;
      _searching = false;
      notifyListeners();
      return;
    }
    _searching = true;
    notifyListeners();
    try {
      final found = await search(
        JourneyGraphSearch(query: query(), via: _via, lock: _lock),
      );
      if (_disposed || generation != _generation) return;
      _searching = false;
      if (found.itineraries.isEmpty) {
        _problem = 'Nothing found that keeps these locks.';
      } else {
        _results = found.itineraries;
        _earlier = found.earlier;
        _later = found.later;
      }
    } catch (_) {
      if (_disposed || generation != _generation) return;
      _searching = false;
      _problem = 'Could not search again. Check your connection.';
    }
    notifyListeners();
  }

  /// Adds the page of results before what is shown.
  Future<void> loadEarlier() => _loadPage(earlier: true);

  /// Adds the page of results after what is shown.
  Future<void> loadLater() => _loadPage(earlier: false);

  Future<void> _loadPage({required bool earlier}) async {
    final cursor = earlier ? _earlier : _later;
    final shown = _results;
    if (cursor == null || shown == null || _searching) return;
    if (earlier ? _loadingEarlier : _loadingLater) return;
    final generation = _generation;
    void loading(bool value) {
      if (earlier) {
        _loadingEarlier = value;
      } else {
        _loadingLater = value;
      }
    }

    loading(true);
    notifyListeners();
    try {
      final page = await search(
        JourneyGraphSearch(
          query: query(),
          via: _via,
          lock: _lock,
          pageCursor: cursor,
        ),
      );
      // Locks changed meanwhile: this page belongs to a search now gone.
      if (_disposed || generation != _generation) return;
      if (earlier) {
        _results = [...page.itineraries, ..._results!];
        _earlier = page.earlier;
      } else {
        _results = [..._results!, ...page.itineraries];
        _later = page.later;
      }
    } catch (_) {
      if (_disposed || generation != _generation) return;
      _problem = 'Could not load more. Check your connection.';
    }
    loading(false);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
