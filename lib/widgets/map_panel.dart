import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolonia_design_tokens/geolonia_design_tokens.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../models/map_config.dart';
import '../screens/home_screen.dart';

enum MapStyle {
  stdPc('std_pc', 'Standard'),
  stdSp('std_sp', 'Mobile'),
  grayPc('gray_pc', 'Gray');

  const MapStyle(this.value, this.label);
  final String value;
  final String label;
}

class MapPanel extends StatefulWidget {
  const MapPanel({super.key});

  @override
  State<MapPanel> createState() => _MapPanelState();
}

class _MapPanelState extends State<MapPanel> {
  final _mapController = MapController();
  final LayerHitNotifier<MapPolygon> _polygonHitNotifier = ValueNotifier(null);
  MapConfig? _lastConfig;
  MapStyle _mapStyle = MapStyle.stdPc;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _showPolygonPopup(MapPolygon polygon) {
    if (polygon.popupInfo == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GeoloniaRadii.card),
        ),
        title: Text(polygon.label ?? 'Area Info'),
        content: SingleChildScrollView(child: Text(polygon.popupInfo!)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _animateTo(MapConfig config) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _mapController.move(
          LatLng(config.centerLat, config.centerLng),
          config.zoom,
        );
      }
    });
  }

  String get _tileUrl =>
      'https://api-map.mapfan.com/v1/map'
      '?key=${AppConfig.mapfanApiKey}'
      '&tilematrix=EPSG%3A900913%3A{z}'
      '&tilerow={y}'
      '&tilecol={x}'
      '&format=image%2Fpng'
      '&lang=ja'
      '&logo=off'
      '&resolution=1'
      '&mapstyle=${_mapStyle.value}';

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AppState>().mapConfig;

    if (_lastConfig != config) {
      _lastConfig = config;
      _animateTo(config);
    }

    final theme = Theme.of(context);

    return Column(
      children: [
        // Header
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outline),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.map_outlined,
                color: theme.colorScheme.primary,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  config.title ?? 'Map',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (config.markers.isNotEmpty) ...[
                _StatBadge(
                  icon: Icons.place,
                  label:
                      '${config.markers.length} marker'
                      '${config.markers.length == 1 ? '' : 's'}',
                  surface: GeoloniaColors.statusInfoSurface,
                  text: GeoloniaColors.statusInfoText,
                ),
                const SizedBox(width: 6),
              ],
              if (config.routes.isNotEmpty) ...[
                _StatBadge(
                  icon: Icons.route,
                  label:
                      '${config.routes.length} route'
                      '${config.routes.length == 1 ? '' : 's'}',
                  surface: GeoloniaColors.statusSuccessSurface,
                  text: GeoloniaColors.statusSuccessText,
                ),
                const SizedBox(width: 6),
              ],
              if (config.circles.isNotEmpty) ...[
                _StatBadge(
                  icon: Icons.circle_outlined,
                  label:
                      '${config.circles.length} circle'
                      '${config.circles.length == 1 ? '' : 's'}',
                  surface: GeoloniaColors.statusWarningSurface,
                  text: GeoloniaColors.statusWarningText,
                ),
                const SizedBox(width: 6),
              ],
              // Map style selector
              DropdownButtonHideUnderline(
                child: DropdownButton<MapStyle>(
                  value: _mapStyle,
                  isDense: true,
                  borderRadius: BorderRadius.circular(GeoloniaRadii.control),
                  items: MapStyle.values
                      .map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text(
                            s.label,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (s) {
                    if (s != null) setState(() => _mapStyle = s);
                  },
                ),
              ),
            ],
          ),
        ),
        // Map
        Expanded(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(config.centerLat, config.centerLng),
              initialZoom: config.zoom,
              minZoom: 2,
              maxZoom: 19,
              onTap: (tapPos, latLng) {
                final hit = _polygonHitNotifier.value;
                if (hit != null && hit.hitValues.isNotEmpty) {
                  _showPolygonPopup(hit.hitValues.first);
                }
              },
            ),
            children: [
              TileLayer(
                key: ValueKey(_mapStyle),
                urlTemplate: _tileUrl,
                userAgentPackageName: 'com.example.flutter_map_agent',
                maxNativeZoom: 19,
              ),
              if (config.circles.isNotEmpty)
                CircleLayer(
                  circles: config.circles
                      .map(
                        (c) => CircleMarker(
                          point: c.latLng,
                          radius: c.radiusMeters,
                          useRadiusInMeter: true,
                          color: c.resolvedFillColor,
                          borderColor: c.resolvedStrokeColor,
                          borderStrokeWidth: 1.5,
                        ),
                      )
                      .toList(),
                ),
              if (config.polygons.isNotEmpty)
                PolygonLayer(
                  hitNotifier: _polygonHitNotifier,
                  polygons: config.polygons
                      .where((poly) => poly.points.length >= 3)
                      .map(
                        (poly) => Polygon(
                          points: poly.points.map((p) => p.latLng).toList(),
                          color: poly.resolvedFillColor,
                          borderColor: Colors.black12,
                          borderStrokeWidth: 1.5,
                          label: poly.label,
                          hitValue: poly,
                          labelStyle: const TextStyle(
                            color: Colors.black,
                            fontSize: 11.8,
                            shadows: [
                              // Create a 360-degree halo effect using 4-8 shadows
                              Shadow(
                                blurRadius: 2.0,
                                color: Colors.white,
                                offset: Offset(1.0, 1.0),
                              ),
                              Shadow(
                                blurRadius: 2.0,
                                color: Colors.white,
                                offset: Offset(-1.0, 1.0),
                              ),
                              Shadow(
                                blurRadius: 2.0,
                                color: Colors.white,
                                offset: Offset(1.0, -1.0),
                              ),
                              Shadow(
                                blurRadius: 2.0,
                                color: Colors.white,
                                offset: Offset(-1.0, -1.0),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              if (config.routes.isNotEmpty)
                PolylineLayer(
                  polylines: config.routes
                      .where((route) => route.points.length >= 2)
                      .map(
                        (route) => Polyline(
                          points: route.points.map((p) => p.latLng).toList(),
                          strokeWidth: 6,
                          color: route.resolvedColor,
                        ),
                      )
                      .toList(),
                ),
              if (config.markers.isNotEmpty)
                MarkerLayer(
                  markers: config.markers
                      .map(
                        (m) => Marker(
                          point: m.latLng,
                          width: 130,
                          height: 60,
                          alignment: Alignment.topCenter,
                          child: _MarkerWidget(
                            label: m.label,
                            color: m.pinColor,
                          ),
                        ),
                      )
                      .toList(),
                ),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('MapFan', prependCopyright: true),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MarkerWidget extends StatelessWidget {
  final String label;
  final Color color;

  const _MarkerWidget({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withAlpha(80), width: 1),
            boxShadow: const [
              BoxShadow(
                blurRadius: 6,
                offset: Offset(0, 2),
                color: Colors.black26,
              ),
            ],
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Icon(Icons.location_pin, color: color, size: 30),
      ],
    );
  }
}

class _StatBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color surface;
  final Color text;

  const _StatBadge({
    required this.icon,
    required this.label,
    required this.surface,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GeoloniaSpacing.space2,
        vertical: GeoloniaSpacing.space1,
      ),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(GeoloniaRadii.tight),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: text),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: GeoloniaFontWeights.bold,
              color: text,
            ),
          ),
        ],
      ),
    );
  }
}
