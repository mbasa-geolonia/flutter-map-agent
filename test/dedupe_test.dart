import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map_agent/models/map_config.dart';

void main() {
  group('dedupeMarkers', () {
    test('collapses markers at the same rounded coordinates, keeping the last', () {
      final markers = [
        const MapMarker(lat: 35.72982, lng: 139.74741, label: 'Search center'),
        const MapMarker(lat: 35.72982, lng: 139.74741, label: 'Search center'),
        const MapMarker(lat: 35.72982, lng: 139.74742, label: 'Nearby'),
      ];
      final result = dedupeMarkers(markers);
      expect(result.length, 2);
    });

    test('treats markers as distinct once coordinates differ meaningfully', () {
      final markers = [
        const MapMarker(lat: 35.0, lng: 139.0, label: 'A'),
        const MapMarker(lat: 36.0, lng: 140.0, label: 'B'),
      ];
      expect(dedupeMarkers(markers).length, 2);
    });
  });

  group('dedupeCircles', () {
    test('collapses circles with the same location and radius', () {
      final circles = [
        const MapCircle(lat: 35.72982, lng: 139.74741, radiusMeters: 800),
        const MapCircle(lat: 35.72982, lng: 139.74741, radiusMeters: 800),
      ];
      expect(dedupeCircles(circles).length, 1);
    });

    test('keeps circles distinct when radius differs', () {
      final circles = [
        const MapCircle(lat: 35.72982, lng: 139.74741, radiusMeters: 500),
        const MapCircle(lat: 35.72982, lng: 139.74741, radiusMeters: 800),
      ];
      expect(dedupeCircles(circles).length, 2);
    });
  });

  group('dedupePolygons', () {
    MapPolygon poly(String label, double lat, double lng) => MapPolygon(
          points: [
            MapMarker(lat: lat, lng: lng, label: ''),
            MapMarker(lat: lat + 0.01, lng: lng, label: ''),
            MapMarker(lat: lat + 0.01, lng: lng + 0.01, label: ''),
          ],
          label: label,
        );

    test('collapses same label at the same location, keeping the last', () {
      final polygons = [
        poly('田端', 35.73, 139.76),
        poly('田端', 35.73, 139.76),
      ];
      expect(dedupePolygons(polygons).length, 1);
    });

    test('keeps two different-but-same-labeled regions distinct', () {
      final polygons = [
        poly('本駒込', 35.72, 139.74),
        poly('本駒込', 35.80, 139.90),
      ];
      expect(dedupePolygons(polygons).length, 2);
    });

    test('always keeps unlabeled polygons (no dedup key)', () {
      final polygons = [
        MapPolygon(
          points: const [
            MapMarker(lat: 0, lng: 0, label: ''),
            MapMarker(lat: 1, lng: 0, label: ''),
            MapMarker(lat: 1, lng: 1, label: ''),
          ],
        ),
        MapPolygon(
          points: const [
            MapMarker(lat: 0, lng: 0, label: ''),
            MapMarker(lat: 1, lng: 0, label: ''),
            MapMarker(lat: 1, lng: 1, label: ''),
          ],
        ),
      ];
      expect(dedupePolygons(polygons).length, 2);
    });
  });
}
