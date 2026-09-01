import 'dart:ui';

import 'package:latlong2/latlong.dart';

/// Distinct colours for up to 8 separate features/paths, shared by the
/// GeoJSON and CSV+WKT auto-render paths.
const _palette = [
  '#E53935', '#1E88E5', '#43A047', '#FB8C00',
  '#8E24AA', '#00ACC1', '#F4511E', '#6D4C41',
];

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
        final color = propColor ?? _palette[paletteIdx++ % _palette.length];
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
        final color = propColor ?? _palette[paletteIdx++ % _palette.length];
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
            _palette[paletteIdx++ % _palette.length];
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
            _palette[paletteIdx++ % _palette.length];
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

  /// Returns true when [text] looks like a CSV table with a WKT geometry
  /// column, e.g. `id,name,geom\n1,Tokyo,"POLYGON((139.1 35.1, ...))"`.
  static bool looksLikeCsvWkt(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return false;
    }
    final firstLineEnd = trimmed.indexOf('\n');
    final header =
        (firstLineEnd == -1 ? trimmed : trimmed.substring(0, firstLineEnd))
            .toLowerCase();
    if (!header.contains(',')) return false;
    final headerCols = header.split(',').map((h) => h.trim());
    if (_wktColumnNames.any(headerCols.contains)) return true;
    // Fallback: header didn't literally match, but the body clearly
    // contains WKT geometry tokens.
    return RegExp(
      r'\b(POLYGON|MULTIPOLYGON|LINESTRING|MULTILINESTRING|POINT)\s*[Z]?\s*\(',
      caseSensitive: false,
    ).hasMatch(trimmed);
  }

  static const _wktColumnNames = ['geom', 'geometry', 'wkt', 'the_geom', 'shape'];
  static const _labelColumnNames = ['name', 'label', 'title', 'id'];
  static const _colorColumnNames = ['color', 'fill', 'fill_color'];
  static const _popupColumnNames = ['popup_info', 'description', 'info'];

  /// Parse a CSV table (header row + data rows) whose geometry column holds
  /// WKT strings (POINT/LINESTRING/MULTILINESTRING/POLYGON/MULTIPOLYGON)
  /// into a [MapConfig]. Mirrors [fromGeoJson]: coordinates are consumed
  /// entirely client-side so the LLM never has to re-emit them.
  factory MapConfig.fromCsvWkt(
    String csv, {
    String? title,
    double zoom = 13.0,
    int paletteOffset = 0,
  }) {
    final rows = _parseCsvRows(csv.trim());
    if (rows.isEmpty) {
      return MapConfig(centerLat: 35.6762, centerLng: 139.6503, zoom: zoom, title: title);
    }

    final header = rows.first.map((h) => h.trim().toLowerCase()).toList();
    int findColumn(List<String> names) {
      for (final name in names) {
        final idx = header.indexOf(name);
        if (idx != -1) return idx;
      }
      return -1;
    }

    final geomIdx = findColumn(_wktColumnNames);
    if (geomIdx == -1) {
      return MapConfig(centerLat: 35.6762, centerLng: 139.6503, zoom: zoom, title: title);
    }
    final labelIdx = findColumn(_labelColumnNames);
    final colorIdx = findColumn(_colorColumnNames);
    final popupIdx = findColumn(_popupColumnNames);

    final markers = <MapMarker>[];
    final routes = <MapRoute>[];
    final polygons = <MapPolygon>[];
    int paletteIdx = paletteOffset;

    String? cell(List<String> row, int idx) {
      if (idx == -1 || idx >= row.length) return null;
      final v = row[idx].trim();
      return v.isEmpty ? null : v;
    }

    for (final row in rows.skip(1)) {
      final wkt = cell(row, geomIdx);
      if (wkt == null) continue;

      final label = cell(row, labelIdx) ?? '';
      final color = cell(row, colorIdx);
      final popup = cell(row, popupIdx);

      for (final geom in _parseWkt(wkt)) {
        switch (geom.kind) {
          case _WktKind.point:
            markers.add(MapMarker(
              lat: geom.points.first.lat,
              lng: geom.points.first.lng,
              label: label,
              color: color,
            ));
            break;
          case _WktKind.line:
            if (geom.points.length >= 2) {
              routes.add(MapRoute(
                points: geom.points,
                color: color ?? _palette[paletteIdx++ % _palette.length],
              ));
            }
            break;
          case _WktKind.polygon:
            if (geom.points.length >= 3) {
              polygons.add(MapPolygon(
                points: geom.points,
                label: label.isNotEmpty ? label : null,
                fillColor: color ?? _palette[paletteIdx++ % _palette.length],
                popupInfo: popup,
              ));
            }
            break;
        }
      }
    }

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

/// Parse RFC4180-ish CSV text into rows of string cells, honoring quoted
/// fields (so a WKT geometry cell containing commas, e.g.
/// `"POLYGON((1 2, 3 4))"`, stays a single field).
List<List<String>> _parseCsvRows(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  var field = StringBuffer();
  var inQuotes = false;
  var i = 0;
  final len = text.length;

  while (i < len) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < len && text[i + 1] == '"') {
          field.write('"');
          i += 2;
        } else {
          inQuotes = false;
          i++;
        }
      } else {
        field.write(ch);
        i++;
      }
      continue;
    }
    switch (ch) {
      case '"':
        inQuotes = true;
        i++;
        break;
      case ',':
        row.add(field.toString());
        field = StringBuffer();
        i++;
        break;
      case '\r':
        i++;
        break;
      case '\n':
        row.add(field.toString());
        field = StringBuffer();
        rows.add(row);
        row = [];
        i++;
        break;
      default:
        field.write(ch);
        i++;
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}

/// Splits a WKT coordinate expression into its parenthesised top-level
/// groups, e.g. `(a),(b)` -> `['a', 'b']`. Used to peel one nesting level
/// at a time off POLYGON/MULTIPOLYGON/MULTILINESTRING bodies.
List<String> _splitTopLevelGroups(String s) {
  final groups = <String>[];
  var depth = 0;
  var start = -1;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == '(') {
      if (depth == 0) start = i + 1;
      depth++;
    } else if (c == ')') {
      depth--;
      if (depth == 0 && start != -1) {
        groups.add(s.substring(start, i));
        start = -1;
      }
    }
  }
  return groups;
}

/// Parses a flat `"lng lat, lng lat, ..."` coordinate list (optionally with
/// a trailing Z/M ordinate, which is ignored) into [MapMarker] points.
List<MapMarker> _parseWktCoordList(String s) {
  final points = <MapMarker>[];
  for (final pair in s.split(',')) {
    final parts = pair.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) continue;
    final lng = double.tryParse(parts[0]);
    final lat = double.tryParse(parts[1]);
    if (lng == null || lat == null) continue;
    points.add(MapMarker(lat: lat, lng: lng, label: ''));
  }
  return points;
}

enum _WktKind { point, line, polygon }

class _WktGeom {
  final _WktKind kind;
  final List<MapMarker> points;
  const _WktGeom(this.kind, this.points);
}

/// Parses a WKT geometry string into zero or more [_WktGeom]s. Only the
/// exterior ring of each polygon is kept (holes are ignored, matching
/// [MapConfig.fromGeoJson]'s behavior).
List<_WktGeom> _parseWkt(String wkt) {
  final trimmed = wkt.trim();
  final typeMatch = RegExp(r'^([A-Za-z]+)').firstMatch(trimmed);
  if (typeMatch == null) return const [];
  final type = typeMatch.group(1)!.toUpperCase();
  final openIdx = trimmed.indexOf('(');
  final closeIdx = trimmed.lastIndexOf(')');
  if (openIdx == -1 || closeIdx == -1 || closeIdx <= openIdx) return const [];
  final body = trimmed.substring(openIdx + 1, closeIdx);

  switch (type) {
    case 'POINT':
      final pts = _parseWktCoordList(body);
      return pts.isNotEmpty ? [_WktGeom(_WktKind.point, [pts.first])] : const [];

    case 'LINESTRING':
      final pts = _parseWktCoordList(body);
      return pts.length >= 2 ? [_WktGeom(_WktKind.line, pts)] : const [];

    case 'MULTILINESTRING':
      return _splitTopLevelGroups(body)
          .map(_parseWktCoordList)
          .where((pts) => pts.length >= 2)
          .map((pts) => _WktGeom(_WktKind.line, pts))
          .toList();

    case 'POLYGON':
      final rings = _splitTopLevelGroups(body);
      if (rings.isEmpty) return const [];
      final exterior = _parseWktCoordList(rings.first);
      return exterior.length >= 3
          ? [_WktGeom(_WktKind.polygon, exterior)]
          : const [];

    case 'MULTIPOLYGON':
      final result = <_WktGeom>[];
      for (final poly in _splitTopLevelGroups(body)) {
        final rings = _splitTopLevelGroups(poly);
        if (rings.isEmpty) continue;
        final exterior = _parseWktCoordList(rings.first);
        if (exterior.length >= 3) {
          result.add(_WktGeom(_WktKind.polygon, exterior));
        }
      }
      return result;

    default:
      return const [];
  }
}
