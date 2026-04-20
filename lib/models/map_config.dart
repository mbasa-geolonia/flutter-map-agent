import 'package:latlong2/latlong.dart';

class MapMarker {
  final double lat;
  final double lng;
  final String label;

  const MapMarker({
    required this.lat,
    required this.lng,
    required this.label,
  });

  factory MapMarker.fromJson(Map<String, dynamic> json) => MapMarker(
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        label: json['label'] as String? ?? '',
      );

  LatLng get latLng => LatLng(lat, lng);
}

class MapPolygon {
  final List<MapMarker> points;
  final String? label;

  const MapPolygon({required this.points, this.label});

  factory MapPolygon.fromJson(Map<String, dynamic> json) {
    final pts = (json['points'] as List)
        .map((p) => MapMarker.fromJson(p as Map<String, dynamic>))
        .toList();
    return MapPolygon(
      points: pts,
      label: json['label'] as String?,
    );
  }
}

class MapCircle {
  final double lat;
  final double lng;
  final double radiusMeters;
  final String? label;

  const MapCircle({
    required this.lat,
    required this.lng,
    required this.radiusMeters,
    this.label,
  });

  factory MapCircle.fromJson(Map<String, dynamic> json) => MapCircle(
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        radiusMeters: (json['radius_m'] as num).toDouble(),
        label: json['label'] as String?,
      );

  LatLng get latLng => LatLng(lat, lng);
}

class MapConfig {
  final double centerLat;
  final double centerLng;
  final double zoom;
  final String? title;
  final List<MapMarker> markers;
  final List<MapPolygon> polygons;
  final List<List<MapMarker>> routes;
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
      routes: rawRoutes.map((route) {
        final pts = route as List;
        return pts
            .map((p) => MapMarker.fromJson(p as Map<String, dynamic>))
            .toList();
      }).toList(),
      circles: rawCircles
          .map((c) => MapCircle.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }
}
