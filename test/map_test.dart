import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotoroll/api.dart';
import 'package:fotoroll/screens/map_screen.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('bbox is west,south,east,north', () {
    final b = LatLngBounds(const LatLng(46.5, 17.2), const LatLng(47.9, 19.3));
    expect(bboxOf(b), '17.200000,46.500000,19.300000,47.900000');
  });

  test('zoomed-out bounds are clamped to valid ranges', () {
    // flutter_map clamps bounds itself; the widest case is the whole world.
    final world = LatLngBounds.unsafe(north: 85, south: -85, east: 180, west: -180);
    expect(bboxOf(world), '-180.000000,-85.000000,180.000000,85.000000');
  });

  test('bounds across the ±180° line ask for every longitude', () {
    final b = LatLngBounds.worldSafe(north: 10, south: -10, longitudeCenter: 175, longitudeWidth: 20);
    expect(bboxOf(b), '-180.000000,-10.000000,180.000000,10.000000');
  });

  test('map timeline query carries the bbox and filters', () {
    const q = TimelineQuery(bbox: '1,2,3,4', isFavorite: true, withPartners: true);
    expect(q.params['bbox'], '1,2,3,4');
    expect(q.params['isFavorite'], 'true');
    expect(q.params['withPartners'], 'true');
    expect(q.params['visibility'], 'timeline');
  });

  test('map styles: unique ids, {z}/{x}/{y} templates, attribution, no Google', () {
    final ids = mapStyles.map((m) => m.id).toSet();
    expect(ids.length, mapStyles.length);
    expect(ids, contains('auto'));
    for (final m in mapStyles) {
      expect(m.url, allOf(contains('{z}'), contains('{x}'), contains('{y}')));
      expect(m.url.contains('google'), isFalse);
      expect(m.attribution, isNotEmpty);
      if (m.url.contains('{s}')) expect(m.subdomains, isNotEmpty);
    }
  });
}
