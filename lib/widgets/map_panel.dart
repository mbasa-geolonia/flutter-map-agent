import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
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
  MapConfig? _lastConfig;
  MapStyle _mapStyle = MapStyle.stdPc;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
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
              bottom: BorderSide(color: theme.dividerColor),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.map_outlined,
                  color: theme.colorScheme.primary, size: 22),
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
                Chip(
                  label: Text('${config.markers.length} marker'
                      '${config.markers.length == 1 ? '' : 's'}'),
                  avatar: const Icon(Icons.place, size: 14),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  labelPadding:
                      const EdgeInsets.symmetric(horizontal: 4),
                ),
                const SizedBox(width: 6),
              ],
              if (config.routes.isNotEmpty) ...[
                Chip(
                  label: Text('${config.routes.length} route'
                      '${config.routes.length == 1 ? '' : 's'}'),
                  avatar: const Icon(Icons.route, size: 14),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  labelPadding:
                      const EdgeInsets.symmetric(horizontal: 4),
                ),
                const SizedBox(width: 6),
              ],
              // Map style selector
              DropdownButtonHideUnderline(
                child: DropdownButton<MapStyle>(
                  value: _mapStyle,
                  isDense: true,
                  borderRadius: BorderRadius.circular(8),
                  items: MapStyle.values
                      .map((s) => DropdownMenuItem(
                            value: s,
                            child: Text(s.label,
                                style: const TextStyle(fontSize: 13)),
                          ))
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
              initialCenter:
                  LatLng(config.centerLat, config.centerLng),
              initialZoom: config.zoom,
              minZoom: 2,
              maxZoom: 19,
            ),
            children: [
              TileLayer(
                key: ValueKey(_mapStyle),
                urlTemplate: _tileUrl,
                userAgentPackageName: 'com.example.flutter_map_agent',
                maxNativeZoom: 19,
              ),
              if (config.polygons.isNotEmpty)
                PolygonLayer(
                  polygons: config.polygons
                      .map(
                        (poly) => Polygon(
                          points: poly.points
                              .map((p) => p.latLng)
                              .toList(),
                          color: theme.colorScheme.primary
                              .withAlpha(38),
                          borderColor: theme.colorScheme.primary,
                          borderStrokeWidth: 2,
                          label: poly.label,
                        ),
                      )
                      .toList(),
                ),
              if (config.routes.isNotEmpty)
                PolylineLayer(
                  polylines: config.routes
                      .map(
                        (route) => Polyline(
                          points: route
                              .map((p) => p.latLng)
                              .toList(),
                          strokeWidth: 4,
                          color: Colors.deepOrange,
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
                          child: _MarkerWidget(label: m.label),
                        ),
                      )
                      .toList(),
                ),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(
                    'MapFan',
                    prependCopyright: true,
                  ),
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

  const _MarkerWidget({required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
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
        const Icon(Icons.location_pin, color: Colors.red, size: 30),
      ],
    );
  }
}
