import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fotoroll/api.dart';
import 'package:fotoroll/panorama.dart';

Uint8List _jpegWith(String xmp) =>
    Uint8List.fromList([0xFF, 0xD8, ...latin1.encode('http://ns.adobe.com/xap/1.0/\x00$xmp'), 0xFF, 0xD9]);

void main() {
  test('GPano crop from XMP attributes (Pixel / Photo Sphere style)', () {
    final crop = panoCropFromXmp(_jpegWith(
        '<rdf:Description GPano:FullPanoWidthPixels="8000" GPano:FullPanoHeightPixels="4000" '
        'GPano:CroppedAreaImageWidthPixels="4000" GPano:CroppedAreaImageHeightPixels="2000" '
        'GPano:CroppedAreaLeftPixels="2000" GPano:CroppedAreaTopPixels="1000"/>'))!;
    expect([crop.left, crop.top, crop.width, crop.height], [0.25, 0.25, 0.5, 0.5]);
    expect(crop.isFull360, isFalse);
  });

  test('GPano crop from XMP elements; missing top means vertically centred', () {
    final crop = panoCropFromXmp(_jpegWith(
        '<GPano:FullPanoWidthPixels>6000</GPano:FullPanoWidthPixels>'
        '<GPano:FullPanoHeightPixels>3000</GPano:FullPanoHeightPixels>'
        '<GPano:CroppedAreaImageWidthPixels>6000</GPano:CroppedAreaImageWidthPixels>'
        '<GPano:CroppedAreaImageHeightPixels>1000</GPano:CroppedAreaImageHeightPixels>'))!;
    expect(crop.isFull360, isTrue);
    expect(crop.top, closeTo(1 / 3, 1e-9));
    expect(crop.height, closeTo(1 / 3, 1e-9));
  });

  test('no GPano: 2:1 is a full sphere, wider images are a centred band', () {
    expect(panoCropFromXmp(_jpegWith('<x:xmpmeta/>')), isNull);
    final full = PanoCrop.guess(4000, 2000);
    expect([full.left, full.top, full.width, full.height], [0, 0, 1, 1]);
    final band = PanoCrop.guess(4000, 1000);
    expect(band.top, 0.25);
    expect(band.height, 0.5);
  });

  test('full sphere: yaw wraps, pitch reaches the zenith', () {
    final v = PanoView(PanoCrop.full)
      ..yaw = 4 * math.pi + 0.5
      ..pitch = 3;
    v.clamp(16 / 9);
    expect(v.yaw, closeTo(0.5, 1e-9));
    expect(v.pitch, math.pi / 2);
  });

  test('partial panorama: the view never leaves the image', () {
    const crop = PanoCrop(0.25, 0.25, 0.5, 0.5); // 180° × 90°
    final v = PanoView(crop);
    expect(v.maxFov, closeTo(math.pi / 2, 1e-9));
    v
      ..yaw = 10
      ..pitch = 10
      ..fov = 3;
    v.clamp(16 / 9);
    // The top-right corner of the view must still be on the image.
    expect(v.yaw, lessThan(crop.lonMax));
    expect(v.pitch, lessThan(crop.latMax));
    expect(v.fov, lessThanOrEqualTo(v.maxFov));
  });

  test('panorama flag from projection type or .insp, never for videos', () {
    expect(AssetRef.panoramaFrom('EQUIRECTANGULAR'), isTrue);
    expect(AssetRef.panoramaFrom(null, '/x/IMG.INSP'), isTrue);
    expect(AssetRef.panoramaFrom(null, '/x/a.jpg'), isFalse);
    final video = AssetRef.fromAssetJson({'id': 'v', 'type': 'VIDEO', 'exifInfo': {'projectionType': 'EQUIRECTANGULAR'}});
    expect(video.isPanorama, isFalse);
  });
}
