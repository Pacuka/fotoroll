#!/usr/bin/env python3
"""Builds the panorama test images in integration_test/fixtures (needs ImageMagick):
pano360.jpg  full 360x180 sphere, no XMP (the viewer must guess "full sphere")
pano180.jpg  180x90 slice of a sphere with GPano XMP describing the crop
Both show a lat/long grid: 30 deg lines, the equator in red, compass labels."""
import os, subprocess, sys, tempfile

out = os.path.join(os.path.dirname(__file__), '..', 'integration_test', 'fixtures')

def grid(path, w, h, lon0, lon1, lat0, lat1, bg):
    """Equirectangular grid covering lon0..lon1 / lat1..lat0 (degrees)."""
    x = lambda lon: (lon - lon0) / (lon1 - lon0) * (w - 1)
    y = lambda lat: (lat1 - lat) / (lat1 - lat0) * (h - 1)
    draw = []
    for lon in range(-180, 181, 30):
        if lon0 <= lon <= lon1:
            draw += ['-stroke', 'white', '-strokewidth', '3', '-draw', f'line {x(lon):.1f},0 {x(lon):.1f},{h}']
    for lat in range(-60, 61, 30):
        if lat0 <= lat <= lat1:
            color = 'red' if lat == 0 else 'yellow'
            draw += ['-stroke', color, '-strokewidth', '4' if lat == 0 else '3', '-draw', f'line 0,{y(lat):.1f} {w},{y(lat):.1f}']
    for lon, label in [(-180, 'S'), (-90, 'W'), (0, 'N'), (90, 'E')]:
        if lon0 <= lon <= lon1:
            draw += ['-stroke', 'none', '-fill', 'white', '-pointsize', str(h // 8), '-annotate',
                     f'+{x(lon) + 8:.0f}+{y(10):.0f}', label]
    subprocess.check_call(['magick', '-size', f'{w}x{h}', f'gradient:{bg}', *draw, '-quality', '85', path])

def add_gpano(path, full_w, full_h, w, h, left, top):
    xmp = (f'<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
           f'<rdf:Description xmlns:GPano="http://ns.google.com/photos/1.0/panorama/" '
           f'GPano:ProjectionType="equirectangular" GPano:FullPanoWidthPixels="{full_w}" '
           f'GPano:FullPanoHeightPixels="{full_h}" GPano:CroppedAreaImageWidthPixels="{w}" '
           f'GPano:CroppedAreaImageHeightPixels="{h}" GPano:CroppedAreaLeftPixels="{left}" '
           f'GPano:CroppedAreaTopPixels="{top}"/></rdf:RDF></x:xmpmeta>').encode()
    payload = b'http://ns.adobe.com/xap/1.0/\x00' + xmp
    seg = b'\xff\xe1' + (len(payload) + 2).to_bytes(2, 'big') + payload
    data = open(path, 'rb').read()
    assert data[:2] == b'\xff\xd8'
    open(path, 'wb').write(data[:2] + seg + data[2:])

grid(os.path.join(out, 'pano360.jpg'), 1600, 800, -180, 180, -90, 90, 'skyblue-seagreen')
p = os.path.join(out, 'pano180.jpg')
grid(p, 1200, 600, -90, 90, -45, 45, 'steelblue-sienna')
add_gpano(p, 2400, 1200, 1200, 600, 600, 300)  # 180x90 deg, centred
print('ok')
