// Map like the mobile app: OpenStreetMap tiles with a glowing dot per photo,
// and a panel below listing only the photos inside the visible area (web v3.3:
// "Show photos in this area", which can be toggled and opened by default).
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../api.dart';
import '../i18n.dart';
import '../settings.dart';
import '../sources.dart';
import '../widgets/timeline_view.dart';

/// "west,south,east,north", clamped to what the server accepts.
String bboxOf(LatLngBounds b) {
  double lon(double v) => v.clamp(-180.0, 180.0);
  double lat(double v) => v.clamp(-90.0, 90.0);
  String f(double v) => v.toStringAsFixed(6);
  // Zoomed out past a full world width, or panned across the ±180° line: ask for
  // every longitude rather than dropping the part beyond the line.
  // (flutter_map clamps east/west at the line but keeps the true center and width.)
  final half = b.longitudeWidth / 2;
  if (b.longitudeWidth >= 360 || b.longitudeCenter - half < -180 || b.longitudeCenter + half > 180) return '-180.000000,${f(lat(b.south))},180.000000,${f(lat(b.north))}';
  return '${f(lon(b.west))},${f(lat(b.south))},${f(lon(b.east))},${f(lat(b.north))}';
}

/// Tile sources that need no API key and no Google services.
class MapStyle {
  final String id;
  final String labelKey;
  final String url;
  final String attribution;
  final List<String> subdomains;
  final int maxNativeZoom;
  final bool invertInDark; // only for 'auto'
  final bool invert;
  const MapStyle(this.id, this.labelKey, this.url, this.attribution,
      {this.subdomains = const [], this.maxNativeZoom = 19, this.invertInDark = false, this.invert = false});
}

const _osm = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const mapStyles = [
  MapStyle('auto', 'linux_map_auto', _osm, '© OpenStreetMap', invertInDark: true),
  MapStyle('osm', 'linux_map_osm', _osm, '© OpenStreetMap'),
  MapStyle('osm_dark', 'linux_map_osm_dark', _osm, '© OpenStreetMap', invert: true),
  MapStyle('hot', 'linux_map_hot', 'https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
      '© OpenStreetMap · HOT · OSM France', subdomains: ['a', 'b', 'c']),
  MapStyle('topo', 'linux_map_topo', 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
      '© OpenStreetMap · SRTM · © OpenTopoMap (CC-BY-SA)', subdomains: ['a', 'b', 'c'], maxNativeZoom: 17),
  MapStyle('cycle', 'linux_map_cycle', 'https://{s}.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png',
      '© OpenStreetMap · CyclOSM', subdomains: ['a', 'b', 'c'], maxNativeZoom: 18),
  MapStyle('sat', 'linux_map_sat',
      'https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2020_3857/default/g/{z}/{y}/{x}.jpg',
      'Sentinel-2 cloudless by EOX (Copernicus Sentinel data 2020)', maxNativeZoom: 15),
  MapStyle('sat_hd', 'linux_map_sat_hd',
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      'Esri, Maxar, Earthstar Geographics', maxNativeZoom: 19),
];

class MapScreen extends StatefulWidget {
  final ImmichApi api;
  const MapScreen({super.key, required this.api});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _map = MapController();
  List<MapMarker>? _markers;
  Object? _error;
  TimelineSource? _source;
  Timer? _debounce;
  int _request = 0;
  double _panelFraction = 0.42;
  bool _panel = settings.mapShowPanel;

  bool _favoritesOnly = false;
  bool _includeArchived = false;
  bool _withPartners = false;

  @override
  void initState() {
    super.initState();
    _loadMarkers();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _source?.dispose();
    _map.dispose();
    super.dispose();
  }

  Future<void> _loadMarkers({bool fit = true}) async {
    try {
      final m = await widget.api.mapMarkers(
        favoritesOnly: _favoritesOnly,
        includeArchived: _includeArchived,
        withPartners: _withPartners,
      );
      if (!mounted) return;
      setState(() {
        _markers = m;
        _error = null;
      });
      if (fit) WidgetsBinding.instance.addPostFrameCallback((_) => _fitAll());
      _scheduleReload();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _fitAll() {
    final m = _markers;
    if (m == null || m.isEmpty) return;
    if (m.length == 1) {
      _map.move(LatLng(m.first.lat, m.first.lon), 12);
    } else {
      _map.fitCamera(CameraFit.coordinates(
        coordinates: [for (final x in m) LatLng(x.lat, x.lon)],
        padding: const EdgeInsets.all(48),
        maxZoom: 14,
      ));
    }
    _scheduleReload();
  }

  void _scheduleReload() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _reloadPanel);
  }

  void _togglePanel() {
    setState(() => _panel = !_panel);
    if (_panel) {
      _reloadPanel();
    } else {
      _request++; // drop a load in flight
      final old = _source;
      setState(() => _source = null);
      WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
    }
  }

  Future<void> _reloadPanel() async {
    if (!_panel) return;
    final MapCamera camera;
    try {
      camera = _map.camera;
    } catch (_) {
      return; // map not laid out yet
    }
    final req = ++_request;
    final query = TimelineQuery(
      bbox: bboxOf(camera.visibleBounds),
      isFavorite: _favoritesOnly ? true : null,
      visibility: _includeArchived ? null : 'timeline',
      withPartners: _withPartners ? true : null,
    );
    try {
      final src = await TimelineSource.create(widget.api, query);
      if (!mounted || req != _request) {
        src.dispose();
        return;
      }
      final old = _source;
      setState(() => _source = src);
      WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
    } catch (_) {}
  }

  void _zoomTo(Offset local, MapCamera camera) {
    // Clicking near a dot zooms in on it, like tapping a cluster on the phone.
    final markers = _markers ?? const [];
    MapMarker? best;
    var bestD = 24.0;
    for (final m in markers) {
      final p = camera.latLngToScreenOffset(LatLng(m.lat, m.lon));
      final d = (p - local).distance;
      if (d < bestD) {
        bestD = d;
        best = m;
      }
    }
    if (best != null) {
      _map.move(LatLng(best.lat, best.lon), math.min(camera.zoom + 3, 18));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final style = mapStyles.firstWhere((m) => m.id == settings.mapStyle, orElse: () => mapStyles.first);
    if (_error != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${t('error')}: $_error'),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: _loadMarkers, child: Text(t('linux_retry'))),
      ]));
    }
    return LayoutBuilder(builder: (context, c) {
      final panelH = (c.maxHeight * _panelFraction).clamp(72.0, c.maxHeight - 120);
      return Column(children: [
        Expanded(
          child: Stack(children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: const LatLng(47.2, 19.4),
                initialZoom: 4,
                minZoom: 2,
                maxZoom: 19,
                backgroundColor: dark ? const Color(0xFF0B0D12) : const Color(0xFFE8ECEF),
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onPositionChanged: (_, _) => _scheduleReload(),
                onTap: (tap, _) => _zoomTo(tap.relative ?? Offset.zero, _map.camera),
              ),
              children: [
                TileLayer(
                  key: ValueKey(style.id),
                  urlTemplate: style.url,
                  subdomains: style.subdomains,
                  maxNativeZoom: style.maxNativeZoom,
                  userAgentPackageName: 'io.github.pacuka.Fotoroll',
                  // OSM has no dark style; invert it like flutter_map's dark mode helper.
                  tileBuilder: style.invert || (style.invertInDark && dark) ? darkModeTileBuilder : null,
                ),
                if (_markers != null) _GlowLayer(markers: _markers!),
                SimpleAttributionWidget(source: Text(style.attribution)),
              ],
            ),
            if (_markers == null) const Center(child: CircularProgressIndicator()),
            Positioned(
              right: 16,
              top: 16,
              child: Column(children: [
                _MapButton(icon: Icons.add, tooltip: t('linux_zoom_in'), onTap: () {
                  final cam = _map.camera;
                  _map.move(cam.center, math.min(cam.zoom + 1, 19));
                }),
                const SizedBox(height: 8),
                _MapButton(icon: Icons.remove, tooltip: t('linux_zoom_out'), onTap: () {
                  final cam = _map.camera;
                  _map.move(cam.center, math.max(cam.zoom - 1, 2));
                }),
                const SizedBox(height: 8),
                _MapButton(icon: Icons.fit_screen, tooltip: t('linux_fit_all'), onTap: _fitAll),
                const SizedBox(height: 8),
                _MapButton(
                  icon: Icons.photo_library_outlined,
                  tooltip: t('show_photos_in_area'),
                  selected: _panel,
                  onTap: _togglePanel,
                ),
                const SizedBox(height: 8),
                MenuAnchor(
                  menuChildren: [
                    for (final m in mapStyles)
                      CheckboxMenuButton(
                        value: m.id == style.id,
                        onChanged: (_) => settings.update(mapStyle: m.id),
                        child: Text(t(m.labelKey)),
                      ),
                  ],
                  builder: (context, ctl, _) => _MapButton(
                    icon: Icons.layers_outlined,
                    tooltip: t('linux_map_style'),
                    onTap: () => ctl.isOpen ? ctl.close() : ctl.open(),
                  ),
                ),
                const SizedBox(height: 8),
                MenuAnchor(
                  menuChildren: [
                    CheckboxMenuButton(
                      value: _favoritesOnly,
                      onChanged: (v) {
                        setState(() => _favoritesOnly = v!);
                        _loadMarkers(fit: false);
                      },
                      child: Text(t('linux_favorites_only')),
                    ),
                    CheckboxMenuButton(
                      value: _includeArchived,
                      onChanged: (v) {
                        setState(() => _includeArchived = v!);
                        _loadMarkers(fit: false);
                      },
                      child: Text(t('include_archived')),
                    ),
                    CheckboxMenuButton(
                      value: _withPartners,
                      onChanged: (v) {
                        setState(() => _withPartners = v!);
                        _loadMarkers(fit: false);
                      },
                      child: Text(t('linux_with_partners')),
                    ),
                    const Divider(),
                    CheckboxMenuButton(
                      value: settings.mapShowPanel,
                      onChanged: (v) {
                        settings.update(mapShowPanel: v!);
                        setState(() {});
                      },
                      child: Text(t('show_asset_panel_on_map')),
                    ),
                  ],
                  builder: (context, ctl, _) => _MapButton(
                    icon: Icons.more_vert,
                    tooltip: t('settings'),
                    onTap: () => ctl.isOpen ? ctl.close() : ctl.open(),
                  ),
                ),
              ]),
            ),
          ]),
        ),
        // Drag handle to resize the photo panel, like the phone's bottom sheet.
        if (_panel) GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (d) => setState(() {
            _panelFraction = (_panelFraction - d.delta.dy / c.maxHeight).clamp(0.08, 0.85);
          }),
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeRow,
            child: Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Column(children: [
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 8),
                _source == null
                    ? const SizedBox(height: 28)
                    : ListenableBuilder(
                        listenable: _source!,
                        builder: (context, _) => Text(
                          t('assets_count', {'count': _source!.length}),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
              ]),
            ),
          ),
        ),
        if (_panel) SizedBox(
          height: panelH,
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: _source == null
                ? const Center(child: CircularProgressIndicator())
                : TimelineView(
                    key: ObjectKey(_source),
                    api: widget.api,
                    source: _source!,
                    emptyText: t('linux_no_photos_here'),
                  ),
          ),
        ),
      ]);
    });
  }
}

class _MapButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  /// A toggle that is on.
  final bool selected;
  const _MapButton({required this.icon, required this.tooltip, required this.onTap, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton.filled(
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: selected ? scheme.primary : scheme.primaryContainer,
        foregroundColor: selected ? scheme.onPrimary : scheme.onPrimaryContainer,
      ),
      onPressed: onTap,
      icon: Icon(icon),
    );
  }
}

/// Draws every photo location as a soft orange dot (the mobile app's circle style:
/// radius 10, rgba(150,86,34,0.7), fully blurred). Overlapping dots glow brighter.
class _GlowLayer extends StatelessWidget {
  final List<MapMarker> markers;
  const _GlowLayer({required this.markers});

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: IgnorePointer(
        child: CustomPaint(
          size: Size.infinite,
          painter: _GlowPainter(markers, camera),
        ),
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  final List<MapMarker> markers;
  final MapCamera camera;
  _GlowPainter(this.markers, this.camera);

  static final _glow = Paint()
    ..color = const Color.fromRGBO(203, 70, 25, 0.55)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
  static final _core = Paint()
    ..color = const Color.fromRGBO(230, 90, 40, 0.5)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Merge dots that land on the same pixel to keep drawing cheap.
    final seen = <int>{};
    for (final m in markers) {
      final p = camera.latLngToScreenOffset(LatLng(m.lat, m.lon));
      if (!rect.inflate(20).contains(p)) continue;
      if (!seen.add((p.dx ~/ 3) * 100000 + (p.dy ~/ 3))) continue;
      canvas.drawCircle(p, 12, _glow);
      canvas.drawCircle(p, 6, _core);
    }
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.camera != camera || old.markers != markers;
}
