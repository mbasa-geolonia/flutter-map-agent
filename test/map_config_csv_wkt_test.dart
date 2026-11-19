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

    test('auto-builds popupInfo from attribute columns when there is no dedicated one', () {
      const csv = 'id,name,人口総数,世帯総数,geom\n'
          '1,Chiyoda,500,200,"POLYGON((139.75 35.69, 139.76 35.69, 139.76 35.70, 139.75 35.70, 139.75 35.69))"\n';

      final config = MapConfig.fromCsvWkt(csv);

      expect(config.polygons.single.popupInfo, isNotNull);
      expect(config.polygons.single.popupInfo, contains('id: 1'));
      expect(config.polygons.single.popupInfo, contains('name: Chiyoda'));
      expect(config.polygons.single.popupInfo, contains('人口総数: 500'));
      expect(config.polygons.single.popupInfo, contains('世帯総数: 200'));
      // The geometry column itself must never leak into the popup.
      expect(config.polygons.single.popupInfo, isNot(contains('POLYGON')));
    });

    test('prefers a dedicated popup/description column when present', () {
      const csv = 'id,name,description,geom\n'
          '1,Chiyoda,"A historic ward",'
          '"POLYGON((139.75 35.69, 139.76 35.69, 139.76 35.70, 139.75 35.70, 139.75 35.69))"\n';

      final config = MapConfig.fromCsvWkt(csv);

      expect(config.polygons.single.popupInfo, 'A historic ward');
    });

    test('assigns synthetic labels when there is no name/id column (e.g. census mesh)', () {
      // Real shape: 500m mesh census data has only statistic columns plus
      // a bare "geometry" column — no name/label/id anywhere.
      const csv = '人口総数,世帯総数,geometry\n'
          '5188,2620,"POLYGON((139.7375 35.72083,139.74375 35.72083,139.74375 35.72500,139.7375 35.72500,139.7375 35.72083))"\n'
          '4964,2500,"POLYGON((139.74375 35.72083,139.75 35.72083,139.75 35.72500,139.74375 35.72500,139.74375 35.72083))"\n';

      final config = MapConfig.fromCsvWkt(csv);

      expect(config.polygons.length, 2);
      expect(config.polygons[0].label, 'Item 1');
      expect(config.polygons[1].label, 'Item 2');
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

  group('MapConfig.stripCsvWktGeometry', () {
    test('replaces geometry cells but keeps every other column', () {
      const csv = 'id,name,households,geom\n'
          '1,Chiyoda,500,"POLYGON((139.75 35.69, 139.76 35.69, 139.76 35.70, 139.75 35.70, 139.75 35.69))"\n'
          '2,Chuo,300,"POLYGON((139.77 35.67, 139.78 35.67, 139.78 35.68, 139.77 35.68, 139.77 35.67))"\n';

      final stripped = MapConfig.stripCsvWktGeometry(csv);

      expect(stripped, isNot(contains('POLYGON')));
      expect(stripped, contains('Chiyoda'));
      expect(stripped, contains('500'));
      expect(stripped, contains('Chuo'));
      expect(stripped, contains('300'));
      expect(stripped, contains('geometry omitted'));
      expect(stripped.length, lessThan(csv.length));
    });

    test('prepends a map_label column to the header, keeping the rest', () {
      const csv = 'id,name,geom\n1,Tokyo,"POINT(139.1 35.1)"\n';
      final stripped = MapConfig.stripCsvWktGeometry(csv);
      expect(stripped.split('\n').first, 'map_label,id,name,geom');
    });

    test('resolves map_label from the name column when present', () {
      const csv = 'id,name,geom\n1,Tokyo,"POINT(139.1 35.1)"\n';
      final stripped = MapConfig.stripCsvWktGeometry(csv);
      expect(stripped.split('\n')[1], startsWith('Tokyo,'));
    });

    test('falls back to a synthetic map_label when there is no name/id column', () {
      const csv = '人口総数,geometry\n'
          '5188,"POLYGON((139.7375 35.72083,139.74375 35.72083,139.74375 35.72500,139.7375 35.72500,139.7375 35.72083))"\n'
          '4964,"POLYGON((139.74375 35.72083,139.75 35.72083,139.75 35.72500,139.74375 35.72500,139.74375 35.72083))"\n';
      final stripped = MapConfig.stripCsvWktGeometry(csv);
      final lines = stripped.split('\n');
      expect(lines[1], startsWith('Item 1,'));
      expect(lines[2], startsWith('Item 2,'));
    });

    test('returns the input unchanged when there is no geometry column', () {
      const csv = 'id,name,value\n1,Chiyoda,500';
      expect(MapConfig.stripCsvWktGeometry(csv), csv);
    });
  });
}
