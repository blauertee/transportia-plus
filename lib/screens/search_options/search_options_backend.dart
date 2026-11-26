import 'package:flutter/cupertino.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../api/nominatim_client.dart';
import '../../api/transitous_endpoint.dart';
import '../../providers/backend_provider.dart';
import '../../theme/app_colors.dart';
import '../../utils/host_input.dart';
import 'search_options_rows.dart';

/// Which servers the app talks to, and which MOTIS API version it asks for.
///
/// A debugging aid for pointing the app at a different MOTIS instance, so it
/// sits at the foot of the screen; the version lives with the routing server
/// because that is the only server it applies to.
class SearchOptionsBackendGroups extends StatefulWidget {
  const SearchOptionsBackendGroups({super.key});

  @override
  State<SearchOptionsBackendGroups> createState() =>
      _SearchOptionsBackendGroupsState();
}

class _SearchOptionsBackendGroupsState
    extends State<SearchOptionsBackendGroups> {
  bool _endpointVersionsExpanded = false;
  late final TextEditingController _hostController;
  late final FocusNode _hostFocusNode;
  late final TextEditingController _versionController;
  late final FocusNode _versionFocusNode;
  late final TextEditingController _nominatimController;
  late final FocusNode _nominatimFocusNode;

  /// Why the host last typed in each field was not kept.
  String? _hostError;
  String? _nominatimError;

  /// Held from initState: the focus listeners and dispose run when the
  /// card may already be out of the tree, where looking it up is unsafe.
  late final BackendProvider _backend;

  @override
  void initState() {
    super.initState();
    final backend = _backend = context.read<BackendProvider>();
    _hostController = TextEditingController(text: backend.host);
    _versionController = TextEditingController(
      text: backend.isCustomApiVersion ? backend.apiVersion : '',
    );
    _nominatimController = TextEditingController(text: backend.nominatimHost);
    _hostFocusNode = FocusNode()
      ..addListener(() {
        if (!_hostFocusNode.hasFocus) _submitHost(_hostController.text);
      });
    _versionFocusNode = FocusNode()
      ..addListener(() {
        if (!_versionFocusNode.hasFocus) {
          _backend.setApiVersion(_versionController.text);
        }
      });
    _nominatimFocusNode = FocusNode()
      ..addListener(() {
        if (!_nominatimFocusNode.hasFocus) {
          _submitNominatimHost(_nominatimController.text);
        }
      });
    backend.addListener(_syncBackendControllers);
  }

  Future<void> _submitHost(String input) async {
    final kept = await _backend.setHost(input);
    // Also called as the field loses focus on the way out of the tree.
    if (!mounted) return;
    if (kept) _hostController.text = _backend.host;
    setState(() => _hostError = kept ? null : _whyNotAHost(input));
  }

  Future<void> _submitNominatimHost(String input) async {
    final kept = await _backend.setNominatimHost(input);
    if (!mounted) return;
    if (kept) _nominatimController.text = _backend.nominatimHost;
    setState(() => _nominatimError = kept ? null : _whyNotAHost(input));
  }

  static String _whyNotAHost(String input) => isPlainHttpAddress(input)
      ? 'Not kept: only https:// servers can be reached.'
      : 'Not kept: not a host name. Like motis.example.org, or with a '
            'port, motis.example.org:8080.';

  void _syncBackendControllers() {
    final backend = _backend;
    if (!_hostFocusNode.hasFocus) _hostController.text = backend.host;
    if (!_nominatimFocusNode.hasFocus) {
      _nominatimController.text = backend.nominatimHost;
    }
    if (!_versionFocusNode.hasFocus) {
      _versionController.text = backend.isCustomApiVersion
          ? backend.apiVersion
          : '';
    }
  }

  @override
  void dispose() {
    _backend.removeListener(_syncBackendControllers);
    _hostController.dispose();
    _hostFocusNode.dispose();
    _versionController.dispose();
    _versionFocusNode.dispose();
    _nominatimController.dispose();
    _nominatimFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backend = context.watch<BackendProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OptionsGroup(
          title: 'Routing server · MOTIS',
          footnote:
              'Hostname, optionally with a port; reached over https. The API '
              'version applies to '
              'routes, trips, stop times, stops and vehicles on the map; '
              'place search and rentals stay on v1. Empty means automatic: '
              'v6.',
          children: [
            OptionsTextRow(
              label: 'Host',
              controller: _hostController,
              focusNode: _hostFocusNode,
              placeholder: BackendProvider.defaultHost,
              keyboardType: TextInputType.url,
              onSubmitted: _submitHost,
              isCustom: backend.isCustomHost,
              onReset: () => _submitHost(''),
              errorText: _hostError,
            ),
            OptionsTextRow(
              label: 'API version',
              controller: _versionController,
              focusNode: _versionFocusNode,
              placeholder: '${backend.apiVersion} (automatic)',
              onSubmitted: backend.setApiVersion,
              isCustom: backend.isCustomApiVersion,
              onReset: backend.resetApiVersion,
            ),
            _buildEndpointVersions(backend),
          ],
        ),
        const SizedBox(height: 20),
        OptionsGroup(
          title: 'Place details server · Nominatim',
          footnote:
              'For the details of a result tapped on the map. Hostname only.',
          children: [
            OptionsTextRow(
              label: 'Host',
              controller: _nominatimController,
              focusNode: _nominatimFocusNode,
              placeholder: NominatimClient.defaultHost,
              keyboardType: TextInputType.url,
              onSubmitted: _submitNominatimHost,
              isCustom: backend.isCustomNominatimHost,
              onReset: () => _submitNominatimHost(''),
              errorText: _nominatimError,
            ),
          ],
        ),
      ],
    );
  }

  /// Overrides for single endpoints, folded away: fifteen rows a rider never
  /// needs, and a debugging aid even among the debugging aids.
  Widget _buildEndpointVersions(BackendProvider backend) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(
            () => _endpointVersionsExpanded = !_endpointVersionsExpanded,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Per-endpoint versions',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.black.withValues(alpha: 0.65),
                    ),
                  ),
                ),
                Icon(
                  _endpointVersionsExpanded
                      ? LucideIcons.chevronUp
                      : LucideIcons.chevronDown,
                  size: 16,
                  color: AppColors.black.withValues(alpha: 0.35),
                ),
              ],
            ),
          ),
        ),
        if (_endpointVersionsExpanded)
          for (final endpoint in TransitousEndpoint.values)
            _EndpointVersionField(
              endpoint: endpoint,
              defaultVersion: backend.defaultVersionFor(endpoint),
            ),
      ],
    );
  }
}

class _EndpointVersionField extends StatefulWidget {
  const _EndpointVersionField({
    required this.endpoint,
    required this.defaultVersion,
  });

  final TransitousEndpoint endpoint;
  final String defaultVersion;

  @override
  State<_EndpointVersionField> createState() => _EndpointVersionFieldState();
}

class _EndpointVersionFieldState extends State<_EndpointVersionField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  /// Held from initState, for the same reason as the group's.
  late final BackendProvider _backend;

  @override
  void initState() {
    super.initState();
    final backend = _backend = context.read<BackendProvider>();
    _controller = TextEditingController(
      text: backend.endpointVersionOverride(widget.endpoint) ?? '',
    );
    _focusNode = FocusNode()
      ..addListener(() {
        if (!_focusNode.hasFocus) {
          _backend.setEndpointVersion(widget.endpoint, _controller.text);
        }
      });
    backend.addListener(_sync);
  }

  void _sync() {
    if (_focusNode.hasFocus) return;
    final newText = _backend.endpointVersionOverride(widget.endpoint) ?? '';
    if (_controller.text != newText) _controller.text = newText;
  }

  @override
  void dispose() {
    _backend.removeListener(_sync);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backend = context.watch<BackendProvider>();
    return OptionsTextRow(
      label: widget.endpoint.label,
      labelWidth: 132,
      controller: _controller,
      focusNode: _focusNode,
      placeholder: widget.defaultVersion,
      onSubmitted: (v) => backend.setEndpointVersion(widget.endpoint, v),
      isCustom: backend.isEndpointOverridden(widget.endpoint),
      onReset: () => backend.resetEndpointVersion(widget.endpoint),
    );
  }
}
