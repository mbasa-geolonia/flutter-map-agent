import 'dart:ui';

import 'package:latlong2/latlong.dart';

/// Parse a `#RRGGBB` or `#AARRGGBB` hex string into a [Color].
/// Returns [fallback] when [hex] is null, empty, or malformed.
Color hexToColor(String? hex, Color fallback) {
  if (hex == null || hex.isEmpty) return fallback;
  final clean = hex.replaceAll('#', '');
  if (clean.length == 6) {
    final value = int.tryParse('FF$clean', radix: 16);
    return value != null ? Color(value) : fallback;
  }
  if (clean.length == 8) {
    final value = int.tryParse(clean, radix: 16);
    return value != null ? Color(value) : fallback;
  }
  return fallback;
}

class MapMarker {
  final double lat;
  final double lng;
  final String label;

  /// Optional pin color as a hex string, e.g. `"#E53935"`.
  final String? color;

  const MapMarker({
    required this.lat,
    required this.lng,
    required this.label,
    this.color,
  });

  factory MapMarker.fromJson(Map<String, dynamic> json) => MapMarker(
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        label: json['label'] as String? ?? '',
        color: json['color'] as String?,
      );

  LatLng get latLng => LatLng(lat, lng);

  /// Resolved pin color (defaults to red).
  Color get pinColor =>
      hexToColor(color, const Color(0xFFE53935));
}

class MapPolygon {
  final List<MapMarker> points;
  final String? label;

  /// Fill color as hex, e.g. `"#FF9800"`.
  final String? fillColor;

  /// Optional info text shown in a popup when the user taps this polygon.
  final String? popupInfo;

  const MapPolygon({
    required this.points,
    this.label,
    this.fillColor,
    this.popupInfo,
  });

  factory MapPolygon.fromJson(Map<String, dynamic> json) {
    final pts = (json['points'] as List)
        .map((p) => MapMarker.fromJson(p as Map<String, dynamic>))
        .toList();
    return MapPolygon(
      points: pts,
      label: json['label'] as String?,
      fillColor: json['fill_color'] as String?,
      popupInfo: json['popup_info'] as String?,
    );
  }

  /// Fill with 47% opacity (alpha 120/255).
  Color get resolvedFillColor =>
      hexToColor(fillColor, const Color(0xFFFF9800)).withAlpha(120);
}

class MapCircle {
  final double lat;
  final double lng;
  final double radiusMeters;
  final String? label;

  /// Fill color as hex, e.g. `"#1E88E5"`.
  final String? fillColor;

  /// Border color as hex. Defaults to [fillColor] if omitted.
  final String? strokeColor;

  const MapCircle({
    required this.lat,
    required this.lng,
    required this.radiusMeters,
    this.label,
    this.fillColor,
    this.strokeColor,
  });

  factory MapCircle.fromJson(Map<String, dynamic> json) => MapCircle(
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        radiusMeters: (json['radius_m'] as num).toDouble(),
        label: json['label'] as String?,
        fillColor: json['fill_color'] as String?,
        strokeColor: json['stroke_color'] as String?,
      );

  LatLng get latLng => LatLng(lat, lng);

  /// Fill with ~20% opacity (alpha 50/255).
  Color get resolvedFillColor =>
      hexToColor(fillColor, const Color(0xFFE53935)).withAlpha(50);

  /// Stroke defaults to fill color at full opacity.
  Color get resolvedStrokeColor =>
      hexToColor(strokeColor ?? fillColor, const Color(0xFFE53935));
}

class MapRoute {
  final List<MapMarker> points;

  /// Stroke color as hex, e.g. `"#43A047"`.
  final String? color;

  const MapRoute({required this.points, this.color});

  factory MapRoute.fromJson(Map<String, dynamic> json) {
    final pts = (json['points'] as List)
        .map((p) => MapMarker.fromJson(p as Map<String, dynamic>))
        .toList();
    return MapRoute(
      points: pts,
      color: json['color'] as String?,
    );
  }

  /// Stroke defaults to deep-orange.
  Color get resolvedColor =>
      hexToColor(color, const Color(0xFFFF6F00));
}

class MapConfig {
  final double centerLat;
  final double centerLng;
  final double zoom;
  final String? title;
  final List<MapMarker> markers;
  final List<MapPolygon> polygons;
  final List<MapRoute> routes;
  final List<MapCircle> circles;

  const MapConfig({
    required this.centerLat,
    required this.centerLng,
    this.zoom = 12.0,
    this.title,
    this.markers = const [],
    this.polygons = const [],
    this.routes = const [],
    this.circles = const [],
  });

  static const MapConfig defaultConfig = MapConfig(
    centerLat: 35.6762,
    centerLng: 139.6503,
    zoom: 10,
    title: 'Tokyo',
  );

  /// Returns true when [data] looks like a GeoJSON object.
  static bool isGeoJson(Map<String, dynamic> data) {
    const types = {
      'FeatureCollection', 'Feature', 'Point', 'MultiPoint',
      'LineString', 'MultiLineString', 'Polygon', 'MultiPolygon',
      'GeometryCollection',
    };
    return types.contains(data['type']);
  }

  /// Parse a GeoJSON FeatureCollection (or single Feature/geometry) into a
  /// [MapConfig].  GeoJSON coordinates are [longitude, latitude] — this
  /// factory swaps them into the [lat, lng] convention used everywhere else.
  factory MapConfig.fromGeoJson(
    Map<String, dynamic> geojson, {
    String? title,
    double zoom = 13.0,
    int paletteOffset = 0,
  }) {
    final markers = <MapMarker>[];
    final routes = <MapRoute>[];
    final polygons = <MapPolygon>[];

    // Distinct colours for up to 8 separate features/paths.
    const palette = [
      '#E53935', '#1E88E5', '#43A047', '#FB8C00',
      '#8E24AA', '#00ACC1', '#F4511E', '#6D4C41',
    ];
    int paletteIdx = paletteOffset;

    List<Map<String, dynamic>> features = [];
    if (geojson['type'] == 'FeatureCollection') {
      features = (geojson['features'] as List).cast<Map<String, dynamic>>();
    } else if (geojson['type'] == 'Feature') {
      features = [geojson];
    } else {
      // Bare geometry object (e.g. {"type":"Point","coordinates":[...]}) —
      // wrap it in a synthetic Feature so the loop below handles it uniformly.
      features = [
        {'type': 'Feature', 'geometry': geojson, 'properties': <String, dynamic>{}}
      ];
    }

    for (final feature in features) {
      final geometry = feature['geometry'] as Map<String, dynamic>?;
      if (geometry == null) continue;

      final props = (feature['properties'] as Map<String, dynamic>?) ?? {};
      final propColor = props['color'] as String? ?? props['stroke'] as String?;
      final label = [props['name'], props['label'], props['id']]
          .whereType<Object>()
          .map((e) => e.toString())
          .firstWhere((_) => true, orElse: () => '');

      final geomType = geometry['type'] as String?;

      if (geomType == 'Point') {
        final c = geometry['coordinates'] as List;
        markers.add(MapMarker(
          lat: (c[1] as num).toDouble(),
          lng: (c[0] as num).toDouble(),
          label: label,
          color: propColor,
        ));
      } else if (geomType == 'LineString') {
        final color = propColor ?? palette[paletteIdx++ % palette.length];
        final coords = (geometry['coordinates'] as List).cast<List>();
        if (coords.length >= 2) {
          routes.add(MapRoute(
            points: coords
                .map((c) => MapMarker(
                      lat: (c[1] as num).toDouble(),
                      lng: (c[0] as num).toDouble(),
                      label: '',
                    ))
                .toList(),
            color: color,
          ));
        }
      } else if (geomType == 'MultiLineString') {
        // Each Feature gets one colour; its segments share that colour.
        final color = propColor ?? palette[paletteIdx++ % palette.length];
        final lines = (geometry['coordinates'] as List).cast<List>();
        for (final line in lines) {
          final coords = line.cast<List>();
          if (coords.length >= 2) {
            routes.add(MapRoute(
              points: coords
                  .map((c) => MapMarker(
                        lat: (c[1] as num).toDouble(),
                        lng: (c[0] as num).toDouble(),
                        label: '',
                      ))
                  .toList(),
              color: color,
            ));
          }
        }
      } else if (geomType == 'Polygon') {
        final fillColor = props['fill'] as String? ??
            palette[paletteIdx++ % palette.length];
        final rings = (geometry['coordinates'] as List).cast<List>();
        if (rings.isNotEmpty) {
          final exterior = rings[0].cast<List>();
          if (exterior.length >= 3) {
            polygons.add(MapPolygon(
              points: exterior
                  .map((c) => MapMarker(
                        lat: (c[1] as num).toDouble(),
                        lng: (c[0] as num).toDouble(),
                        label: '',
                      ))
                  .toList(),
              label: label.isNotEmpty ? label : null,
              fillColor: fillColor,
            ));
          }
        }
      } else if (geomType == 'MultiPolygon') {
        final fillColor = props['fill'] as String? ??
            palette[paletteIdx++ % palette.length];
        for (final poly in (geometry['coordinates'] as List).cast<List>()) {
          if (poly.isNotEmpty) {
            final exterior = (poly[0] as List).cast<List>();
            if (exterior.length >= 3) {
              polygons.add(MapPolygon(
                points: exterior
                    .map((c) => MapMarker(
                          lat: (c[1] as num).toDouble(),
                          lng: (c[0] as num).toDouble(),
                          label: '',
                        ))
                    .toList(),
                label: label.isNotEmpty ? label : null,
                fillColor: fillColor,
              ));
            }
          }
        }
      }
    }

    // Derive map center from bounding box of all collected points.
    final allLats = [
      ...markers.map((m) => m.lat),
      ...routes.expand((r) => r.points).map((p) => p.lat),
      ...polygons.expand((p) => p.points).map((p) => p.lat),
    ];
    final allLngs = [
      ...markers.map((m) => m.lng),
      ...routes.expand((r) => r.points).map((p) => p.lng),
      ...polygons.expand((p) => p.points).map((p) => p.lng),
    ];

    final centerLat = allLats.isNotEmpty
        ? (allLats.reduce((a, b) => a < b ? a : b) +
               allLats.reduce((a, b) => a > b ? a : b)) /
              2
        : 35.6762;
    final centerLng = allLngs.isNotEmpty
        ? (allLngs.reduce((a, b) => a < b ? a : b) +
               allLngs.reduce((a, b) => a > b ? a : b)) /
              2
        : 139.6503;

    return MapConfig(
      centerLat: centerLat,
      centerLng: centerLng,
      zoom: zoom,
      title: title,
      markers: markers,
      routes: routes,
      polygons: polygons,
    );
  }

  factory MapConfig.fromToolInput(Map<String, dynamic> input) {
    final rawMarkers = input['markers'] as List? ?? [];
    final rawPolygons = input['polygons'] as List? ?? [];
    final rawRoutes = input['routes'] as List? ?? [];
    final rawCircles = input['circles'] as List? ?? [];

    return MapConfig(
      centerLat: (input['center_lat'] as num).toDouble(),
      centerLng: (input['center_lng'] as num).toDouble(),
      zoom: (input['zoom'] as num?)?.toDouble() ?? 12.0,
      title: input['title'] as String?,
      markers: rawMarkers
          .map((m) => MapMarker.fromJson(m as Map<String, dynamic>))
          .toList(),
      polygons: rawPolygons
          .map((p) => MapPolygon.fromJson(p as Map<String, dynamic>))
          .where((p) => p.points.length >= 3)
          .toList(),
      routes: rawRoutes
          .map((r) => MapRoute.fromJson(r as Map<String, dynamic>))
          .where((r) => r.points.length >= 2)
          .toList(),
      circles: rawCircles
          .map((c) => MapCircle.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }
}
