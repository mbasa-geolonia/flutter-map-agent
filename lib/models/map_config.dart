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

  const MapPolygon({
    required this.points,
    this.label,
    this.fillColor,
  });

  factory MapPolygon.fromJson(Map<String, dynamic> json) {
    final pts = (json['points'] as List)
        .map((p) => MapMarker.fromJson(p as Map<String, dynamic>))
        .toList();
    return MapPolygon(
      points: pts,
      label: json['label'] as String?,
      fillColor: json['fill_color'] as String?,
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
          .toList(),
      routes: rawRoutes
          .map((r) => MapRoute.fromJson(r as Map<String, dynamic>))
          .toList(),
      circles: rawCircles
          .map((c) => MapCircle.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }
}
