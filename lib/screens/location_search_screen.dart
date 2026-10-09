import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/my_location.dart';
import '../models/saved_place.dart';
import '../services/favorites_service.dart';
import '../services/saved_places_service.dart';
import '../services/transitous_geocode_service.dart';
import '../theme/app_colors.dart';
import '../utils/custom_page_route.dart';
import '../utils/favorite_icons.dart';
import '../utils/haptics.dart';
import '../utils/list_reorder.dart';
import '../utils/place_icons.dart';
import '../widgets/app_page_scaffold.dart';
import '../widgets/buttons/heart_button.dart';
import '../widgets/edit_favorite_overlay.dart';
import 'map_place_picker/map_place_picker_screen.dart';
import '../theme/app_text.dart';

/// Picks a place, full screen.
///
/// A screen rather than a dropdown under the field: the list has favourites,
/// recent places and geocoder results to show, and an overlay capped at a few
/// hundred pixels has to fight the card it hangs from for the room.
///
/// Thin on purpose — it is [LocationSearchBody] on a page that pops the
/// answer. A screen that is itself a place search renders the body directly.
/// How long typing has to pause before a place lookup is sent.
const Duration _kSearchDebounce = Duration(milliseconds: 220);

/// How long a favourite, once lifted to be dragged, has to be held still
/// before its menu opens instead. The lift itself takes a long press; this is
/// the "even longer" on top, so a rider who meant to drag has started moving.
const Duration _kHoldPastLiftToEdit = Duration(milliseconds: 500);

/// The most results "Show more" asks for; the public server answers 100.
const int _kMaxResults = 100;

class LocationSearchScreen extends StatelessWidget {
  const LocationSearchScreen({
    super.key,
    required this.title,
    required this.bucket,
    this.initialQuery = '',
    this.placeBias,
    this.type,
    this.showFavourites = true,
    this.showMyLocation = false,
  });

  /// Names what is being picked: "Origin", "Destination", "Stop". The map
  /// picker opened from here asks for the same: "Select Origin".
  final String title;

  final SavedPlacesBucket bucket;
  final String initialQuery;
  final LatLng? placeBias;
  final String? type;
  final bool showFavourites;
  final bool showMyLocation;

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: title,
      padding: EdgeInsets.zero,
      body: LocationSearchBody(
        bucket: bucket,
        initialQuery: initialQuery,
        placeBias: placeBias,
        type: type,
        showFavourites: showFavourites,
        showMyLocation: showMyLocation,
        mapPickerTitle: 'Select $title',
        onPicked: (suggestion) => Navigator.of(context).pop(suggestion),
      ),
    );
  }
}

/// Picking a place: the field, the favourites, the recents and the results.
///
/// Everything except the page it sits on, so a screen that *is* a place
/// search — the timetable tab — can render it directly instead of keeping its
/// own field and its own copies of the same two lists.
class LocationSearchBody extends StatefulWidget {
  const LocationSearchBody({
    super.key,
    required this.bucket,
    required this.onPicked,
    this.autofocus = true,
    this.initialQuery = '',
    this.placeBias,
    this.type,
    this.showFavourites = true,
    this.showMyLocation = false,
    this.mapPickerTitle = 'Select a place',
    this.mapPickerConfirmLabel = 'Select',
    this.nearby,
  });

  /// Heading and button of the map picker the field's map icon opens.
  final String mapPickerTitle;
  final String mapPickerConfirmLabel;

  /// What to do with the place that was chosen. The pushed screen pops it;
  /// the timetable tab opens its departures.
  final ValueChanged<TransitousLocationSuggestion> onPicked;

  /// What is around the rider, listed under the favourites and above the
  /// recents. Only the timetable search has one: a departure is an answer
  /// there, and anywhere else it is not what was asked.
  final Widget? nearby;

  /// The pushed screen opens for the sake of typing, so it takes the keyboard.
  /// A tab that merely happens to start here should not.
  final bool autofocus;

  /// Which recents to learn from and offer.
  final SavedPlacesBucket bucket;

  final String initialQuery;

  /// Biases the geocoder towards where the rider is.
  final LatLng? placeBias;

  /// Restricts results, e.g. `STOP` for a timetable search.
  final String? type;

  final bool showFavourites;

  /// Offers where the rider is standing as the first answer.
  ///
  /// Only for a route endpoint: a coordinate is not a stop, so a timetable
  /// search has nothing to do with one. Not gated on location permission —
  /// the row is how a rider finds out the app can do this at all, and the
  /// caller asks for permission when it is tapped.
  final bool showMyLocation;

  @override
  State<LocationSearchBody> createState() => _LocationSearchBodyState();
}

class _LocationSearchBodyState extends State<LocationSearchBody> {
  // Opened on a filled field, the text is selected: typing replaces it, and
  // nothing has to be cleared first to get back to the lists.
  late final TextEditingController _controller =
      TextEditingController.fromValue(
        TextEditingValue(
          text: widget.initialQuery,
          selection: TextSelection(
            baseOffset: 0,
            extentOffset: widget.initialQuery.length,
          ),
        ),
      );

  /// False until the field holds something other than what it opened with.
  ///
  /// What a filled field opens with is the current answer, not a question:
  /// searching it would hide My Location, favourites and recents behind
  /// results for the place already chosen.
  bool _hasTyped = false;
  final FocusNode _focus = FocusNode();

  List<TransitousLocationSuggestion> _suggestions = const [];
  List<SavedPlace> _recents = const [];
  List<FavoritePlace> _favourites = const [];
  bool _isFetching = false;
  Timer? _debounce;

  /// How many results the current query asks for; grows by a page each time
  /// the rider asks for more.
  int _numResults = TransitousGeocodeService.pageSize;

  /// The last answer filled the page it was asked for, so more may exist.
  bool _mayHaveMore = false;
  bool _isLoadingMore = false;

  /// Guards against an earlier, slower search overwriting a later one.
  int _requestId = 0;

  final GlobalKey<SliverReorderableListState> _favouriteListKey = GlobalKey();

  /// Opens the menu of a favourite held still after it lifted; cancelled once
  /// the press moves, because then it is a drag.
  Timer? _holdToEdit;

  /// Where the current press went down, to tell a held favourite from a
  /// dragged one. Measured above the list: the lifted row is rebuilt in the
  /// overlay, and what was under the finger is gone.
  Offset? _pressOrigin;

  @override
  void initState() {
    super.initState();
    _favourites = FavoritesService.favoritesListenable.value;
    FavoritesService.favoritesListenable.addListener(_onFavouritesChanged);
    unawaited(FavoritesService.getFavorites());
    unawaited(_loadRecents());
    _controller.addListener(_onQueryChanged);
    // The keyboard is why the pushed screen opened; waiting for a second tap
    // on the field it already put focus on would be a step for nothing. A tab
    // that starts here has its lists to offer first.
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _focus.requestFocus(),
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _holdToEdit?.cancel();
    FavoritesService.favoritesListenable.removeListener(_onFavouritesChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onFavouritesChanged() {
    if (!mounted) return;
    setState(() => _favourites = FavoritesService.favoritesListenable.value);
  }

  Future<void> _loadRecents() async {
    final places = await SavedPlacesService.loadPlaces(bucket: widget.bucket);
    if (!mounted) return;
    setState(() => _recents = places);
  }

  /// True when this search can only answer with a timetabled stop.
  ///
  /// The geocoder is already told, but the two lists below the field were not,
  /// so a timetable search offered addresses it could not open a departure
  /// board for.
  bool get _stopsOnly => widget.type?.toUpperCase() == 'STOP';

  /// Being a station is not enough — a departure board needs the feed's id for
  /// it, and places kept before the app recorded that have none. Offering one
  /// would fail the moment it was tapped.
  List<FavoritePlace> get _offerableFavourites =>
      _favourites.where(_lists).toList();

  /// Whether Favourites here shows [favourite].
  bool _lists(FavoritePlace favourite) => !_stopsOnly || favourite.hasTimetable;

  /// A kept place is listed once, under Favourites, rather than again among
  /// the recents — but only when Favourites is actually showing it.
  List<SavedPlace> get _offerableRecents {
    final listedFavourites = widget.showFavourites
        ? {for (final favourite in _offerableFavourites) favourite.id}
        : const <String>{};
    return [
      for (final place in _recents)
        if (_canOffer(place) &&
            !listedFavourites.contains(
              FavoritesService.findAt(place.lat, place.lon)?.id,
            ))
          place,
    ];
  }

  bool _canOffer(SavedPlace place) =>
      !_stopsOnly ||
      (place.type.toUpperCase() == 'STOP' &&
          (place.stopId?.isNotEmpty ?? false));

  String get _query => _controller.text.trim();

  void _onQueryChanged() {
    // Selection changes arrive here too; only a changed text is typing.
    if (!_hasTyped) {
      if (_controller.text == widget.initialQuery) return;
      setState(() => _hasTyped = true);
    }
    _debounce?.cancel();
    _numResults = TransitousGeocodeService.pageSize;
    _mayHaveMore = false;
    _isLoadingMore = false;
    final query = _query;

    // A pasted coordinate is already an answer; there is nothing to look up.
    final coord = TransitousGeocodeService.tryParseLatLon(query);
    if (coord != null) {
      ++_requestId;
      setState(() {
        _suggestions = [TransitousLocationSuggestion.fromLatLon(coord)];
        _isFetching = false;
      });
      return;
    }

    if (query.length < 3) {
      ++_requestId;
      setState(() {
        _suggestions = const [];
        _isFetching = false;
      });
      return;
    }

    setState(() => _isFetching = true);
    _debounce = Timer(_kSearchDebounce, () => _search(query));
  }

  Future<void> _search(String query) async {
    final requestId = ++_requestId;
    final numResults = _numResults;
    try {
      final page = await TransitousGeocodeService.fetchSuggestionPage(
        text: query,
        placeBias: widget.placeBias,
        type: widget.type,
        numResults: numResults,
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _suggestions = _prioritiseRecents(page.suggestions);
        _mayHaveMore = page.isFull && numResults < _kMaxResults;
        _isFetching = false;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        // A failed "more" keeps what is listed: the server may cap results
        // below what was asked, and the first page is still right.
        if (!_isLoadingMore) _suggestions = const [];
        _mayHaveMore = false;
        _isFetching = false;
        _isLoadingMore = false;
      });
    }
  }

  /// Asks again for a page more. MOTIS has no offset, but a larger request
  /// answers the same order with more appended, so the list only grows.
  void _loadMore() {
    if (_isLoadingMore || !_mayHaveMore) return;
    setState(() {
      _isLoadingMore = true;
      _numResults += TransitousGeocodeService.pageSize;
    });
    unawaited(_search(_query));
  }

  /// Hoists places this rider has picked before, most-used first.
  ///
  /// The geocoder ranks by its own idea of importance, which cannot know that
  /// you go to one of two identically named stops every day.
  List<TransitousLocationSuggestion> _prioritiseRecents(
    List<TransitousLocationSuggestion> results,
  ) {
    if (_recents.isEmpty) return results;
    final importanceByKey = {
      for (final place in _recents) place.key: place.importance,
    };
    final originalIndex = {
      for (var i = 0; i < results.length; i++) results[i]: i,
    };
    return [...results]..sort((a, b) {
      final aImportance =
          importanceByKey[SavedPlace.buildKey(
            type: a.type,
            lat: a.lat,
            lon: a.lon,
          )];
      final bImportance =
          importanceByKey[SavedPlace.buildKey(
            type: b.type,
            lat: b.lat,
            lon: b.lon,
          )];
      if ((aImportance != null) != (bImportance != null)) {
        return aImportance != null ? -1 : 1;
      }
      if (aImportance != null && bImportance != null) {
        final diff = bImportance.compareTo(aImportance);
        if (diff != 0) return diff;
      }
      return originalIndex[a]!.compareTo(originalIndex[b]!);
    });
  }

  void _pick(TransitousLocationSuggestion suggestion) {
    Haptics.lightTick();
    // Where you are is not a place you searched for, so it does not belong
    // in the list of places you did.
    if (suggestion.id == myLocationSuggestion.id) {
      widget.onPicked(suggestion);
      return;
    }
    // The only place a pick is remembered, and with everything the list
    // needs of it later: the stop id that opens a departure board, and the
    // modes that draw its icon.
    _recents = SavedPlacesService.recordSelection(
      bucket: widget.bucket,
      places: _recents,
      suggestion: suggestion,
    );
    widget.onPicked(suggestion);
  }

  /// What the map would show: the results listed now, if any.
  List<TransitousLocationSuggestion> get _mapResults =>
      _hasTyped && _query.length >= 3 ? _suggestions : const [];

  /// The map offers the results listed, where there are any, and any point
  /// where a point will do.
  bool get _canOfferMap => !_stopsOnly || _mapResults.isNotEmpty;

  Future<void> _pickOnMap() async {
    final results = _mapResults;
    final picked = await Navigator.of(context)
        .push<TransitousLocationSuggestion>(
          CustomPageRoute(
            child: MapPlacePickerScreen.pick(
              title: results.isEmpty
                  ? widget.mapPickerTitle
                  : 'Results for “$_query”',
              confirmLabel: widget.mapPickerConfirmLabel,
              results: results,
              origin: widget.placeBias,
              query: results.isEmpty ? null : _query,
              type: widget.type,
              // A point is not a stop, so a timetable is not offered one.
              allowsPoint: !_stopsOnly,
            ),
          ),
        );
    if (!mounted || picked == null) return;
    _pick(picked);
  }

  /// Keeps the place, or lets it go, without picking it.
  ///
  /// A stop is kept with the icon the lists draw it with, so it looks the
  /// same above the line as it did below.
  Future<void> _toggleFavourite(TransitousLocationSuggestion place) async {
    final existing = FavoritesService.findAt(place.lat, place.lon);
    // Kept before stop ids were recorded, so the timetable cannot list it and
    // its heart reads empty here. Keeping it again fills the id in, which
    // lists it, rather than letting go of a place kept elsewhere.
    if (existing != null &&
        !_lists(existing) &&
        (place.stopId?.isNotEmpty ?? false)) {
      await FavoritesService.updateFavorite(
        existing.copyWith(type: place.type, stopId: place.stopId),
      );
      return;
    }
    final isStop = place.type.toUpperCase() == 'STOP';
    await FavoritesService.toggleAt(
      name: place.name,
      lat: place.lat,
      lon: place.lon,
      type: place.type,
      stopId: place.stopId,
      iconName: isStop ? favoriteIconNameForStop(place.modes) : null,
    );
  }

  /// Full only when the place is among the favourites this search lists, so
  /// a filled heart always has a row under Favourites to answer to.
  Widget _heartFor(TransitousLocationSuggestion place) {
    final favourite = FavoritesService.findAt(place.lat, place.lon);
    return HeartButton(
      kept: favourite != null && _lists(favourite),
      placeName: place.name,
      onPressed: () => unawaited(_toggleFavourite(place)),
    );
  }

  /// The row reports the slot before the moved one is taken out.
  void _reorderFavourites(List<FavoritePlace> shown, int from, int slot) {
    final to = slot > from ? slot - 1 : slot;
    final reordered = reorderWithin(_favourites, shown, from, to);
    setState(() => _favourites = reordered);
    unawaited(FavoritesService.reorderFavorites(reordered));
  }

  void _onFavouriteLifted(FavoritePlace favourite) {
    Haptics.lightTick();
    _holdToEdit?.cancel();
    _holdToEdit = Timer(_kHoldPastLiftToEdit, () {
      _holdToEdit = null;
      // Held, not dragged: it goes back down and its menu opens instead.
      _favouriteListKey.currentState?.cancelReorder();
      unawaited(_editFavourite(favourite));
    });
  }

  void _endHold() {
    _holdToEdit?.cancel();
    _holdToEdit = null;
  }

  void _onPointerMove(PointerMoveEvent event) {
    final origin = _pressOrigin;
    if (origin == null || _holdToEdit == null) return;
    if ((event.position - origin).distance > kTouchSlop) _endHold();
  }

  Future<void> _editFavourite(FavoritePlace favourite) async {
    Haptics.lightTick();
    await showCupertinoDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => EditFavoriteOverlay(
        favorite: favourite,
        onSaved: () {},
        onDeleted: () =>
            unawaited(FavoritesService.removeFavorite(favourite.id)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: _buildSearchField(context),
        ),
        Expanded(child: _buildResults(context)),
      ],
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final accent = AppColors.accentOf(context);
    return CupertinoTextField(
      controller: _controller,
      focusNode: _focus,
      placeholder: 'Search for a place',
      placeholderStyle: TextStyle(
        color: AppColors.black.withValues(alpha: 0.4),
        fontSize: 16,
      ),
      style: TextStyle(color: AppColors.black, fontSize: 16),
      cursorColor: accent,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.black.withValues(alpha: 0.12)),
      ),
      prefix: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Icon(
          LucideIcons.search,
          size: 17,
          color: AppColors.black.withValues(alpha: 0.4),
        ),
      ),
      suffix: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_query.isNotEmpty)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _controller.clear,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 14, 10),
                child: Icon(
                  LucideIcons.x,
                  size: 16,
                  color: AppColors.black.withValues(alpha: 0.4),
                ),
              ),
            ),
        ],
      ),
      textInputAction: TextInputAction.search,
    );
  }

  Widget _buildResults(BuildContext context) {
    final query = _query;
    final hasFullQuery = query.length >= 3;

    if (!_hasTyped || !hasFullQuery) return _buildLists();

    if (_isFetching && _suggestions.isEmpty) {
      return _hint('Searching…');
    }
    if (_suggestions.isEmpty) {
      return _hint('No matches for “$query”.');
    }

    // A place abroad says so; one at home does not repeat the country.
    final homeCountry = View.of(context).platformDispatcher.locale.countryCode;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        // At the top, where the keyboard cannot cover it.
        _buildMapRow(),
        const SizedBox(height: 8),
        _sectionHeading('Search results'),
        for (final suggestion in _suggestions)
          _buildPlaceRow(
            suggestion,
            subtitle: suggestion.caption(
              from: widget.placeBias,
              homeCountry: homeCountry,
            ),
          ),
        if (_mayHaveMore)
          _ShowMoreRow(isLoading: _isLoadingMore, onTap: _loadMore),
      ],
    );
  }

  /// The way to the map: the results where they are, or before a search,
  /// any point — some places are easier shown than named.
  Widget _buildMapRow() {
    final showsResults = _mapResults.isNotEmpty;
    return _ResultRow(
      icon: LucideIcons.map,
      title: showsResults ? 'Show results on map' : 'Pick a point on the map',
      subtitle: showsResults
          ? 'See where each one is'
          : 'For a place easier shown than named',
      onTap: _pickOnMap,
    );
  }

  /// What is offered before anything is typed: where you are, the
  /// favourites, which can be dragged into order, and the recents.
  Widget _buildLists() {
    final favourites = _offerableFavourites;
    final recents = _offerableRecents;
    final listsFavourites = widget.showFavourites && favourites.isNotEmpty;
    return Listener(
      onPointerDown: (event) => _pressOrigin = event.position,
      onPointerMove: _onPointerMove,
      onPointerUp: (_) => _endHold(),
      onPointerCancel: (_) => _endHold(),
      child: CustomScrollView(
        slivers: [
          _inGutter(
            SliverList.list(
              children: [
                if (widget.showMyLocation)
                  _ResultRow(
                    icon: LucideIcons.locateFixed,
                    title: myLocationName,
                    subtitle: 'Where you are now',
                    onTap: () => _pick(myLocationSuggestion),
                  ),
                // A point is not a stop, so a timetable is not offered one.
                if (_canOfferMap) _buildMapRow(),
                if (widget.showMyLocation || _canOfferMap)
                  const SizedBox(height: 8),
                if (widget.showFavourites) ...[
                  _sectionHeading('Favourites'),
                  // Two different emptinesses: nothing kept at all, or
                  // things kept that this search cannot use.
                  if (favourites.isEmpty)
                    _hint(
                      _stopsOnly && _favourites.isNotEmpty
                          ? 'None of your favourites is a stop.'
                          : 'Tap the heart on a place to keep it here.',
                    ),
                ],
              ],
            ),
          ),
          if (listsFavourites) _inGutter(_buildFavouriteList(favourites)),
          _inGutter(
            SliverList.list(
              children: [
                if (widget.showFavourites) const SizedBox(height: 20),
                if (widget.nearby case final nearby?) ...[
                  _sectionHeading('Near you'),
                  nearby,
                  const SizedBox(height: 8),
                ],
                if (recents.isNotEmpty) ...[
                  _sectionHeading('Recent'),
                  for (final place in recents.take(8))
                    _buildPlaceRow(
                      _savedToSuggestion(place),
                      subtitle: place.city,
                    ),
                ],
                if (favourites.isEmpty &&
                    recents.isEmpty &&
                    !widget.showFavourites)
                  _hint('Start typing to search for a place.'),
              ],
            ),
            bottom: 32,
          ),
        ],
      ),
    );
  }

  Widget _inGutter(Widget sliver, {double bottom = 0}) => SliverPadding(
    padding: EdgeInsets.fromLTRB(20, 0, 20, bottom),
    sliver: sliver,
  );

  /// Long press lifts a favourite to drag it; holding it still for longer
  /// opens its menu instead.
  Widget _buildFavouriteList(List<FavoritePlace> favourites) =>
      SliverReorderableList(
        key: _favouriteListKey,
        itemCount: favourites.length,
        onReorderStart: (index) => _onFavouriteLifted(favourites[index]),
        onReorderEnd: (_) => _endHold(),
        onReorder: (from, slot) => _reorderFavourites(favourites, from, slot),
        proxyDecorator: _liftedFavourite,
        itemBuilder: (context, index) {
          final favourite = favourites[index];
          return ReorderableDelayedDragStartListener(
            key: ValueKey(favourite.id),
            index: index,
            child: _FavouriteRow(
              favourite: favourite,
              onTap: () => _pick(_favouriteToSuggestion(favourite)),
              onEdit: () => unawaited(_editFavourite(favourite)),
              onMoveUp: index == 0
                  ? null
                  : () => _reorderFavourites(favourites, index, index - 1),
              onMoveDown: index == favourites.length - 1
                  ? null
                  : () => _reorderFavourites(favourites, index, index + 2),
            ),
          );
        },
      );

  /// The row in hand: a card under it, wider than the row so its icon does
  /// not sit on the edge, rising as it lifts.
  Widget _liftedFavourite(
    Widget child,
    int index,
    Animation<double> animation,
  ) => AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      final lift = Curves.easeOut.transform(animation.value);
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -12,
            right: -12,
            top: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.black.withValues(alpha: 0.14 * lift),
                    blurRadius: 18 * lift,
                    offset: Offset(0, 6 * lift),
                  ),
                ],
              ),
            ),
          ),
          child!,
        ],
      );
    },
  );

  /// A place that can be picked or kept: a recent, or a search result.
  Widget _buildPlaceRow(
    TransitousLocationSuggestion place, {
    String? subtitle,
  }) => _ResultRow(
    icon: placeIcon(place.type, modes: place.modes),
    title: place.name,
    subtitle: subtitle,
    onTap: () => _pick(place),
    trailing: _heartFor(place),
  );

  Widget _sectionHeading(String text) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 8),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.7,
        color: AppColors.black.withValues(alpha: 0.45),
      ),
    ),
  );

  Widget _hint(String text) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    child: Text(text, style: AppText.bodyMuted),
  );

  TransitousLocationSuggestion _favouriteToSuggestion(FavoritePlace f) =>
      TransitousLocationSuggestion(
        id: 'fav-${f.id}',
        stopId: f.stopId,
        name: f.displayName,
        lat: f.lat,
        lon: f.lon,
        type: f.type,
      );

  TransitousLocationSuggestion _savedToSuggestion(SavedPlace place) =>
      TransitousLocationSuggestion(
        id: 'saved-${place.key}',
        stopId: place.stopId,
        name: place.name,
        lat: place.lat,
        lon: place.lon,
        type: place.type,
        modes: place.modes,
      );
}

/// A kept place, with its name and the two ways to rename it.
class _FavouriteRow extends StatelessWidget {
  const _FavouriteRow({
    required this.favourite,
    required this.onTap,
    required this.onEdit,
    this.onMoveUp,
    this.onMoveDown,
  });

  final FavoritePlace favourite;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  /// The drag's order, for a screen reader, which cannot drag. Null at the
  /// end the row cannot move past.
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    return Semantics(
      button: true,
      label: favourite.displayName,
      customSemanticsActions: {
        if (onMoveUp case final moveUp?)
          const CustomSemanticsAction(label: 'Move up'): moveUp,
        if (onMoveDown case final moveDown?)
          const CustomSemanticsAction(label: 'Move down'): moveDown,
      },
      // A long press is the list's: it lifts the row to drag, and held
      // longer opens the same menu as the three dots.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.accentWash(accent),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  iconForFavorite(favourite.iconName),
                  size: 17,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      favourite.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.listTitle,
                    ),
                    // Only once the alias says something the name does not,
                    // so an unrenamed favourite is not printed twice.
                    if (favourite.hasAlias)
                      Text(
                        favourite.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.black.withValues(alpha: 0.55),
                        ),
                      ),
                  ],
                ),
              ),
              Semantics(
                button: true,
                label: 'Edit ${favourite.displayName}',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onEdit,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Icon(
                      LucideIcons.ellipsisVertical,
                      size: 18,
                      color: AppColors.black.withValues(alpha: 0.45),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.listTitle,
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.black.withValues(alpha: 0.55),
                        ),
                      ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// The last row of a result list that filled its page.
class _ShowMoreRow extends StatelessWidget {
  const _ShowMoreRow({required this.isLoading, required this.onTap});

  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isLoading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                isLoading ? 'Loading…' : 'Show more results',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
              if (!isLoading) ...[
                const SizedBox(width: 6),
                Icon(LucideIcons.chevronDown, size: 18, color: accent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
