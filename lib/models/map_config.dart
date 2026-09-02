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

  /// The simple average of [points] — used to place the polygon's label.
  LatLng get centroid {
    final sumLat = points.fold<double>(0, (s, p) => s + p.lat);
    final sumLng = points.fold<double>(0, (s, p) => s + p.lng);
    return LatLng(sumLat / points.length, sumLng / points.length);
  }
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
      // Fallback popup body so tapping a polygon shows its real attributes
      // even when the source has no dedicated description/info property.
      final popupInfo = props.entries
          .where((e) => e.value != null && e.value.toString().trim().isNotEmpty)
          .map((e) => '${e.key}: ${e.value}')
          .join('\n');

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
              popupInfo: popupInfo.isNotEmpty ? popupInfo : null,
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
                popupInfo: popupInfo.isNotEmpty ? popupInfo : null,
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
  static const _labelColumnNames = [
    'name', 'label', 'title', 'id', 'mesh_code', 'meshcode', 'mesh_id',
  ];
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

    final geomIdx = _findCsvColumn(header, _wktColumnNames);
    if (geomIdx == -1) {
      return MapConfig(centerLat: 35.6762, centerLng: 139.6503, zoom: zoom, title: title);
    }
    final labelIdx = _findCsvColumn(header, _labelColumnNames);
    final colorIdx = _findCsvColumn(header, _colorColumnNames);
    final popupIdx = _findCsvColumn(header, _popupColumnNames);

    final markers = <MapMarker>[];
    final routes = <MapRoute>[];
    final polygons = <MapPolygon>[];
    int paletteIdx = paletteOffset;

    String? cell(List<String> row, int idx) {
      if (idx == -1 || idx >= row.length) return null;
      final v = row[idx].trim();
      return v.isEmpty ? null : v;
    }

    final dataRows = rows.skip(1).toList();
    for (var i = 0; i < dataRows.length; i++) {
      final row = dataRows[i];
      final wkt = cell(row, geomIdx);
      if (wkt == null) continue;

      // Always non-empty: falls back to a synthetic, stable identifier
      // (e.g. datasets like census mesh grids have no name/id column at
      // all) so every feature stays addressable via polygon_colors.
      final label = _resolveRowLabel(row, labelIdx, i + 1);
      final color = cell(row, colorIdx);
      // Most CSV+WKT datasets (census, population, etc.) have no dedicated
      // popup/description column — fall back to listing every attribute
      // column so tapping a polygon still shows its real data.
      final popup = cell(row, popupIdx) ??
          _buildAutoPopupInfo(rows.first, row, geomIdx: geomIdx);

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
                label: label,
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

  /// Returns [csv] with its geometry column values replaced by a short
  /// placeholder, keeping every other column (labels, statistics, etc.)
  /// intact. This lets the LLM see the attribute data it needs to build a
  /// genuine thematic/choropleth map (via `polygon_colors`) without ever
  /// having the expensive coordinate payload sent back to it.
  static String stripCsvWktGeometry(
    String csv, {
    String placeholder = '[geometry omitted — already rendered]',
  }) {
    final rows = _parseCsvRows(csv.trim());
    if (rows.isEmpty) return csv;
    final header = rows.first.map((h) => h.trim().toLowerCase()).toList();
    final geomIdx = _findCsvColumn(header, _wktColumnNames);
    if (geomIdx == -1) return csv;
    final labelIdx = _findCsvColumn(header, _labelColumnNames);

    final out = StringBuffer()
      ..writeln(['map_label', ...rows.first].map(_csvEscape).join(','));

    final dataRows = rows.skip(1).toList();
    for (var i = 0; i < dataRows.length; i++) {
      final row = dataRows[i];
      final cells = [
        _resolveRowLabel(row, labelIdx, i + 1),
        for (var c = 0; c < row.length; c++)
          c == geomIdx ? placeholder : row[c],
      ];
      out.writeln(cells.map(_csvEscape).join(','));
    }
    return out.toString().trimRight();
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

String _roundCoord(double v) => v.toStringAsFixed(5);

/// Removes duplicate markers (same rounded lat/lng, ~1m precision), keeping
/// the LAST occurrence. The LLM tends to repeat "the same" marker (e.g. a
/// search-center pin) across multiple show_map calls within one turn,
/// instead of relying on it having already been added.
List<MapMarker> dedupeMarkers(List<MapMarker> markers) {
  final byKey = <String, MapMarker>{};
  for (final m in markers) {
    byKey['${_roundCoord(m.lat)},${_roundCoord(m.lng)}'] = m;
  }
  return byKey.values.toList();
}

/// Removes duplicate circles (same rounded lat/lng and radius), keeping the
/// LAST occurrence — same rationale as [dedupeMarkers], for e.g. a repeated
/// search-radius circle.
List<MapCircle> dedupeCircles(List<MapCircle> circles) {
  final byKey = <String, MapCircle>{};
  for (final c in circles) {
    final key =
        '${_roundCoord(c.lat)},${_roundCoord(c.lng)},${c.radiusMeters.round()}';
    byKey[key] = c;
  }
  return byKey.values.toList();
}

/// Removes duplicate polygons (same label AND same first point, ~1m
/// precision), keeping the LAST occurrence. Keyed on label *and* location
/// (not label alone) so two different datasets that happen to share a
/// region name aren't incorrectly merged into one.
List<MapPolygon> dedupePolygons(List<MapPolygon> polygons) {
  final byKey = <String, MapPolygon>{};
  final unlabeled = <MapPolygon>[];
  for (final p in polygons) {
    if (p.label == null || p.label!.isEmpty) {
      unlabeled.add(p);
      continue;
    }
    final first = p.points.isNotEmpty ? p.points.first : null;
    final coord = first == null
        ? ''
        : '${_roundCoord(first.lat)},${_roundCoord(first.lng)}';
    byKey['${p.label}|$coord'] = p;
  }
  return [...byKey.values, ...unlabeled];
}

/// Result of [applyPolygonColorOverrides]: the updated config plus which
/// requested labels matched an existing polygon and which didn't — so the
/// caller can report back to the LLM instead of silently no-oping on a
/// label mismatch (which would otherwise let the model claim success when
/// nothing actually changed on the map).
class PolygonColorOverrideResult {
  final MapConfig config;
  final List<String> matchedLabels;
  final List<String> unmatchedLabels;
  const PolygonColorOverrideResult(
      this.config, this.matchedLabels, this.unmatchedLabels);
}

String _normalizeLabel(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

/// Applies `polygon_colors` (a list of `{label, fill_color}` maps) to
/// [config]'s polygons. Used for thematic/choropleth maps where each region
/// needs a different color without redrawing it.
///
/// Matching is intentionally lenient, since the LLM is reproducing label
/// text rather than passing back an opaque id: tries an exact match first,
/// then a whitespace/case-normalized match, then falls back to a unique
/// substring match (only applied when exactly one polygon qualifies, to
/// avoid mis-coloring an unrelated region).
PolygonColorOverrideResult applyPolygonColorOverrides(
  MapConfig config,
  List<dynamic>? rawColors,
) {
  if (rawColors == null || rawColors.isEmpty) {
    return PolygonColorOverrideResult(config, const [], const []);
  }

  final requested = <String, String>{};
  for (final entry in rawColors) {
    final m = entry as Map<String, dynamic>;
    final label = m['label'] as String?;
    final color = m['fill_color'] as String?;
    if (label != null && color != null) requested[label] = color;
  }
  if (requested.isEmpty) {
    return PolygonColorOverrideResult(config, const [], const []);
  }

  // label -> polygon index, plus a normalized lookup for fuzzy matching.
  final byExactLabel = <String, int>{};
  final byNormalizedLabel = <String, List<int>>{};
  for (var i = 0; i < config.polygons.length; i++) {
    final label = config.polygons[i].label;
    if (label == null) continue;
    byExactLabel[label] = i;
    byNormalizedLabel.putIfAbsent(_normalizeLabel(label), () => []).add(i);
  }

  final resolvedColors = List<String?>.filled(config.polygons.length, null);
  final matched = <String>[];
  final unmatched = <String>[];

  requested.forEach((requestedLabel, color) {
    int? idx = byExactLabel[requestedLabel];
    idx ??= byNormalizedLabel[_normalizeLabel(requestedLabel)]?.length == 1
        ? byNormalizedLabel[_normalizeLabel(requestedLabel)]!.first
        : null;
    idx ??= () {
      final norm = _normalizeLabel(requestedLabel);
      if (norm.isEmpty) return null;
      final candidates = <int>[];
      for (var i = 0; i < config.polygons.length; i++) {
        final label = config.polygons[i].label;
        if (label == null) continue;
        final normLabel = _normalizeLabel(label);
        if (normLabel.contains(norm) || norm.contains(normLabel)) {
          candidates.add(i);
        }
      }
      return candidates.length == 1 ? candidates.first : null;
    }();

    if (idx == null) {
      unmatched.add(requestedLabel);
    } else {
      resolvedColors[idx] = color;
      matched.add(requestedLabel);
    }
  });

  if (matched.isEmpty) {
    return PolygonColorOverrideResult(config, matched, unmatched);
  }

  final newPolygons = [
    for (var i = 0; i < config.polygons.length; i++)
      if (resolvedColors[i] == null)
        config.polygons[i]
      else
        MapPolygon(
          points: config.polygons[i].points,
          label: config.polygons[i].label,
          fillColor: resolvedColors[i],
          popupInfo: config.polygons[i].popupInfo,
        ),
  ];

  return PolygonColorOverrideResult(
    MapConfig(
      centerLat: config.centerLat,
      centerLng: config.centerLng,
      zoom: config.zoom,
      title: config.title,
      markers: config.markers,
      routes: config.routes,
      circles: config.circles,
      polygons: newPolygons,
    ),
    matched,
    unmatched,
  );
}

/// Finds the index of the first header column (case-insensitive, already
/// lowercased) matching any of [names], or -1 if none match.
int _findCsvColumn(List<String> header, List<String> names) {
  for (final name in names) {
    final idx = header.indexOf(name);
    if (idx != -1) return idx;
  }
  return -1;
}

/// Quotes [field] for CSV output if it contains a comma, quote, or newline.
String _csvEscape(String field) {
  if (field.contains(',') || field.contains('"') || field.contains('\n')) {
    return '"${field.replaceAll('"', '""')}"';
  }
  return field;
}

/// Resolves the label for data row [rowNumber] (1-based, among data rows):
/// the trimmed value at [labelIdx] if present and non-empty, otherwise a
/// synthetic `Item N` fallback. Some datasets (e.g. census mesh grids) have
/// no name/id column at all — without this fallback those features would
/// get a null/empty label and could never be targeted by polygon_colors.
///
/// Used identically by [MapConfig.fromCsvWkt] (to set MapPolygon.label) and
/// [MapConfig.stripCsvWktGeometry] (to show the LLM the exact same value up
/// front), so the two always agree on each feature's label.
String _resolveRowLabel(List<String> row, int labelIdx, int rowNumber) {
  if (labelIdx != -1 && labelIdx < row.length) {
    final v = row[labelIdx].trim();
    if (v.isNotEmpty) return v;
  }
  return 'Item $rowNumber';
}

/// Builds a default popup body ("column: value", one per line) from every
/// non-empty column in [row] except the geometry column, using [rawHeader]
/// (original casing) for the column names. Returns null if every remaining
/// cell is empty.
String? _buildAutoPopupInfo(
  List<String> rawHeader,
  List<String> row, {
  required int geomIdx,
}) {
  final lines = <String>[];
  for (var i = 0; i < rawHeader.length && i < row.length; i++) {
    if (i == geomIdx) continue;
    final value = row[i].trim();
    if (value.isEmpty) continue;
    lines.add('${rawHeader[i]}: $value');
  }
  return lines.isEmpty ? null : lines.join('\n');
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
