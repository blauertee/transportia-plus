import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../environment.dart';
import '../models/routing_options.dart';
import '../models/transitous/server_config.dart';
import '../services/location_service.dart';
import '../services/place_bias_service.dart';
import '../services/rental_providers_service.dart';
import '../services/routing_options_service.dart';
import '../services/server_capabilities_service.dart';
import '../theme/app_colors.dart';
import '../utils/custom_page_route.dart';
import '../utils/place_bias.dart';
import '../widgets/app_page_scaffold.dart';
import 'quick_access_screen.dart';
import 'search_options/search_options_backend.dart';
import 'search_options/search_options_place_bias.dart';
import 'search_options/search_options_rental_providers.dart';
import 'search_options/search_options_routing.dart';
import 'search_options/search_options_rows.dart';

/// The settings that apply to every search and are not offered on the search
/// screen itself.
///
/// Anything a rider changes for one trip lives on the search screen and is
/// made the default from there, so it is not repeated here.
class SearchOptionsScreen extends StatefulWidget {
  const SearchOptionsScreen({super.key});

  @override
  State<SearchOptionsScreen> createState() => _SearchOptionsScreenState();
}

class _SearchOptionsScreenState extends State<SearchOptionsScreen> {
  RoutingOptions _options = RoutingOptions.defaults;
  ServerConfig _capabilities = ServerConfig.fallback;
  bool _loaded = false;

  double _placeBias = PlaceBias.defaultValue;
  bool _catalogueLoading = true;
  Set<String> _nearby = const {};

  @override
  void initState() {
    super.initState();
    RentalProvidersService.prefsListenable.addListener(_rebuild);
    RentalProvidersService.catalogueListenable.addListener(_rebuild);
    _load();
  }

  @override
  void dispose() {
    RentalProvidersService.prefsListenable.removeListener(_rebuild);
    RentalProvidersService.catalogueListenable.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  /// The provider list, and what is near the rider to offer first.
  ///
  /// After the rest has loaded, so a slow or failing fetch never holds the
  /// screen up. The rider's position is only sent while place search may
  /// use it: switching that off means off for this too.
  Future<void> _loadProviders() async {
    await RentalProvidersService.loadPrefs();
    await RentalProvidersService.ensureCatalogue();
    if (!mounted) return;
    setState(() => _catalogueLoading = false);
    if (PlaceBias.isOff(_placeBias)) return;
    final position = await LocationService.loadLastLatLng();
    if (position == null) return;
    final nearby = await RentalProvidersService.nearbyGroupIds(position);
    if (!mounted) return;
    setState(() => _nearby = nearby);
  }

  Future<void> _load() async {
    final options = await RoutingOptionsService.load();
    // Falls back to the published Transitous limits when unavailable, so the
    // controls stay usable offline.
    final capabilities = await ServerCapabilitiesService.ensureLoaded();
    final placeBias = await PlaceBiasService.load();
    if (!mounted) return;
    setState(() {
      _options = options;
      _capabilities = capabilities;
      _placeBias = placeBias;
      _loaded = true;
    });
    unawaited(_loadProviders());
  }

  void _update(RoutingOptions options) {
    if (options == _options) return;
    setState(() => _options = options);
    RoutingOptionsService.save(options);
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: 'Search and routing options',
      scrollable: true,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 18),
            child: OptionsNote(
              'These apply to every search. Options for a single trip are '
              'on the search screen, where “Save as default” keeps them.',
            ),
          ),
          // Everything below reads stored values, so waiting avoids showing
          // defaults for a frame and writing them back on the first tap.
          if (!_loaded) const SizedBox(height: 200) else ..._buildSections(),
        ],
      ),
    );
  }

  List<Widget> _buildSections() {
    final sections = <Widget>[
      SearchOptionsPlaceBiasGroup(
        value: _placeBias,
        onChanged: (value) {
          if (value == _placeBias) return;
          setState(() => _placeBias = value);
          PlaceBiasService.save(value);
        },
      ),
      SearchOptionsRentalProvidersCard(
        prefs: RentalProvidersService.prefsListenable.value,
        catalogue: RentalProvidersService.catalogueListenable.value,
        loading: _catalogueLoading,
        nearby: _nearby,
        onAdd: RentalProvidersService.add,
        onRemove: RentalProvidersService.remove,
      ),
      SearchOptionsTransfersGroup(
        options: _options,
        capabilities: _capabilities,
        onChanged: _update,
      ),
      if (_capabilities.hasElevation)
        SearchOptionsInclineGroup(options: _options, onChanged: _update),
      OptionsGroup(
        title: 'Search card',
        children: [
          OptionsRow(
            icon: LucideIcons.layoutGrid,
            label: 'Quick access icons',
            trailing: Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: AppColors.black.withValues(alpha: 0.3),
            ),
            description:
                'Which modes each icon on the search card switches, and '
                'what the sections are called.',
            onTap: () => Navigator.of(
              context,
            ).push(CustomPageRoute<void>(child: const QuickAccessScreen())),
          ),
        ],
      ),
      if (Environment.showBackendSettings) const _AdvancedSection(),
    ];
    return [
      for (var i = 0; i < sections.length; i++) ...[
        if (i > 0) const SizedBox(height: 20),
        sections[i],
      ],
    ];
  }
}

/// The servers, set apart from everything above: only for pointing the app
/// at another MOTIS instance.
class _AdvancedSection extends StatelessWidget {
  const _AdvancedSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Container(height: 1, color: AppColors.black.withValues(alpha: 0.08)),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Advanced',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.black,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const SearchOptionsBackendGroups(),
      ],
    );
  }
}
