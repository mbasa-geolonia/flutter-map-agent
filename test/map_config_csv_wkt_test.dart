import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map_agent/models/map_config.dart';

void main() {
  group('MapConfig.looksLikeCsvWkt', () {
    test('detects a header with a geom column', () {
      const csv = 'id,name,geom\n1,Tokyo,"POINT(139.1 35.1)"';
      expect(MapConfig.looksLikeCsvWkt(csv), isTrue);
    });

    test('detects via WKT token fallback when header name is unusual', () {
      const csv = 'id,name,shape_wkt\n1,Tokyo,"POLYGON((139.1 35.1, 139.2 35.1, 139.2 35.2, 139.1 35.1))"';
      expect(MapConfig.looksLikeCsvWkt(csv), isTrue);
    });

    test('rejects JSON text', () {
      const json = '{"type":"FeatureCollection","features":[]}';
      expect(MapConfig.looksLikeCsvWkt(json), isFalse);
    });

    test('rejects plain prose', () {
      const text = 'Tokyo is the capital of Japan.';
      expect(MapConfig.looksLikeCsvWkt(text), isFalse);
    });
  });

  group('MapConfig.fromCsvWkt', () {
    test('parses POLYGON rows into filled polygons', () {
      const csv = 'id,name,value,geom\n'
          '1,Chiyoda,500,"POLYGON((139.75 35.69, 139.76 35.69, 139.76 35.70, 139.75 35.70, 139.75 35.69))"\n'
          '2,Chuo,300,"POLYGON((139.77 35.67, 139.78 35.67, 139.78 35.68, 139.77 35.68, 139.77 35.67))"\n';

      final config = MapConfig.fromCsvWkt(csv, title: 'Wards');

      expect(config.polygons.length, 2);
      expect(config.polygons[0].points.length, 5);
      expect(config.polygons[0].points.first.lat, closeTo(35.69, 1e-9));
      expect(config.polygons[0].points.first.lng, closeTo(139.75, 1e-9));
      // Distinct auto-assigned colors from the shared palette.
      expect(config.polygons[0].fillColor, isNotNull);
      expect(config.polygons[1].fillColor, isNotNull);
      expect(config.polygons[0].fillColor, isNot(config.polygons[1].fillColor));
    });

    test('parses POINT rows into markers with explicit color', () {
      const csv = 'id,name,geom,color\n'
          '1,Tokyo Station,"POINT(139.767 35.681)",#1E88E5\n';

      final config = MapConfig.fromCsvWkt(csv);

      expect(config.markers.length, 1);
      expect(config.markers.first.lat, closeTo(35.681, 1e-9));
      expect(config.markers.first.lng, closeTo(139.767, 1e-9));
      expect(config.markers.first.color, '#1E88E5');
    });

    test('parses LINESTRING rows into routes', () {
      const csv = 'id,geom\n'
          '1,"LINESTRING(139.70 35.65, 139.71 35.66, 139.72 35.67)"\n';

      final config = MapConfig.fromCsvWkt(csv);

      expect(config.routes.length, 1);
      expect(config.routes.first.points.length, 3);
    });

    test('parses MULTIPOLYGON rows into one polygon per part', () {
      const csv = 'id,geom\n'
          '1,"MULTIPOLYGON(((139.1 35.1, 139.2 35.1, 139.2 35.2, 139.1 35.1)), '
          '((139.3 35.3, 139.4 35.3, 139.4 35.4, 139.3 35.3)))"\n';

      final config = MapConfig.fromCsvWkt(csv);

      expect(config.polygons.length, 2);
      expect(config.polygons[0].points.length, 4);
      expect(config.polygons[1].points.length, 4);
    });

    test('handles quoted fields with embedded commas correctly', () {
      const csv = 'id,name,geom\n'
          '1,"Ward, A","POLYGON((139.1 35.1, 139.2 35.1, 139.2 35.2, 139.1 35.1))"\n';

      final config = MapConfig.fromCsvWkt(csv);

      expect(config.polygons.length, 1);
      expect(config.polygons.first.label, 'Ward, A');
    });

    test('returns an empty config when there is no geometry column', () {
      const csv = 'id,name,value\n1,Chiyoda,500\n';
      final config = MapConfig.fromCsvWkt(csv);
      expect(config.polygons, isEmpty);
      expect(config.markers, isEmpty);
      expect(config.routes, isEmpty);
    });
  });
}
