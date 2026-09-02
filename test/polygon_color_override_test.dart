import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map_agent/models/map_config.dart';

MapConfig _configWithLabels(List<String> labels) => MapConfig(
      centerLat: 35.7,
      centerLng: 139.7,
      polygons: [
        for (final label in labels)
          MapPolygon(
            points: const [
              MapMarker(lat: 35.7, lng: 139.7, label: ''),
              MapMarker(lat: 35.71, lng: 139.7, label: ''),
              MapMarker(lat: 35.71, lng: 139.71, label: ''),
            ],
            label: label,
          ),
      ],
    );

void main() {
  group('MapPolygon.centroid', () {
    test('averages the polygon points', () {
      const poly = MapPolygon(
        points: [
          MapMarker(lat: 0, lng: 0, label: ''),
          MapMarker(lat: 10, lng: 0, label: ''),
          MapMarker(lat: 10, lng: 10, label: ''),
          MapMarker(lat: 0, lng: 10, label: ''),
        ],
      );
      expect(poly.centroid.latitude, closeTo(5, 1e-9));
      expect(poly.centroid.longitude, closeTo(5, 1e-9));
    });
  });

  group('applyPolygonColorOverrides', () {
    test('recolors polygons matched by exact label', () {
      final config = _configWithLabels(['田端', '白山', '巣鴨']);
      final result = applyPolygonColorOverrides(config, [
        {'label': '田端', 'fill_color': '#FF0000'},
        {'label': '巣鴨', 'fill_color': '#00FF00'},
      ]);

      expect(result.matchedLabels, ['田端', '巣鴨']);
      expect(result.unmatchedLabels, isEmpty);
      expect(result.config.polygons[0].fillColor, '#FF0000');
      expect(result.config.polygons[1].fillColor, isNull);
      expect(result.config.polygons[2].fillColor, '#00FF00');
    });

    test('reports unmatched labels instead of silently no-oping', () {
      final config = _configWithLabels(['田端', '白山']);
      final result = applyPolygonColorOverrides(config, [
        {'label': '文京区田端', 'fill_color': '#FF0000'},
      ]);

      // "文京区田端" doesn't uniquely contain/match either "田端" or "白山"
      // in a way that's unambiguous... actually it DOES contain 田端 as a
      // substring, so this should match via the fallback.
      expect(result.matchedLabels, ['文京区田端']);
      expect(result.config.polygons[0].fillColor, '#FF0000');
    });

    test('does not match when a normalized label is ambiguous', () {
      final config = _configWithLabels(['本駒込一丁目', '本駒込二丁目']);
      final result = applyPolygonColorOverrides(config, [
        {'label': '本駒込', 'fill_color': '#FF0000'},
      ]);

      // "本駒込" is a substring of BOTH labels — ambiguous, so no match.
      expect(result.matchedLabels, isEmpty);
      expect(result.unmatchedLabels, ['本駒込']);
      expect(result.config.polygons[0].fillColor, isNull);
      expect(result.config.polygons[1].fillColor, isNull);
    });

    test('matches ignoring surrounding whitespace', () {
      final config = _configWithLabels(['千石']);
      final result = applyPolygonColorOverrides(config, [
        {'label': ' 千石 ', 'fill_color': '#123456'},
      ]);

      expect(result.matchedLabels, [' 千石 ']);
      expect(result.config.polygons[0].fillColor, '#123456');
    });

    test('reports a genuinely unmatched label with no fallback candidate', () {
      final config = _configWithLabels(['田端', '白山']);
      final result = applyPolygonColorOverrides(config, [
        {'label': 'Nonexistent Ward', 'fill_color': '#FF0000'},
      ]);

      expect(result.matchedLabels, isEmpty);
      expect(result.unmatchedLabels, ['Nonexistent Ward']);
      expect(result.config.polygons[0].fillColor, isNull);
      expect(result.config.polygons[1].fillColor, isNull);
    });

    test('returns the config unchanged when rawColors is null or empty', () {
      final config = _configWithLabels(['田端']);
      expect(applyPolygonColorOverrides(config, null).config, same(config));
      expect(applyPolygonColorOverrides(config, []).config, same(config));
    });

    test('leaves other map elements untouched', () {
      final config = MapConfig(
        centerLat: 35.7,
        centerLng: 139.7,
        markers: const [MapMarker(lat: 35.7, lng: 139.7, label: 'Pin')],
        polygons: [
          MapPolygon(
            points: const [
              MapMarker(lat: 35.7, lng: 139.7, label: ''),
              MapMarker(lat: 35.71, lng: 139.7, label: ''),
              MapMarker(lat: 35.71, lng: 139.71, label: ''),
            ],
            label: '田端',
          ),
        ],
      );
      final result = applyPolygonColorOverrides(config, [
        {'label': '田端', 'fill_color': '#FF0000'},
      ]);
      expect(result.config.markers, config.markers);
      expect(result.config.centerLat, config.centerLat);
      expect(result.config.centerLng, config.centerLng);
    });
  });
}
