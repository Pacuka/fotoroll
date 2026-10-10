// Panorama geometry: where an equirectangular image sits on the sphere (from its
// GPano XMP, like Photo Sphere Viewer on the web) and the view limits that follow.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// The image's area within the full 360°×180° sphere, as fractions (0..1).
class PanoCrop {
  final double left, top, width, height;
  const PanoCrop(this.left, this.top, this.width, this.height);

  static const full = PanoCrop(0, 0, 1, 1);

  bool get isFull360 => width > 0.999;
  double get hRange => width * 2 * math.pi; // radians of longitude covered
  double get vRange => height * math.pi; // radians of latitude covered
  double get lonMin => (left - 0.5) * 2 * math.pi;
  double get lonMax => (left + width - 0.5) * 2 * math.pi;
  double get latMax => (0.5 - top) * math.pi;
  double get latMin => (0.5 - top - height) * math.pi;

  /// Without GPano data: the image spans 360° and is centred vertically (the
  /// Photo Sphere Viewer default), so a 2:1 image is a full sphere.
  factory PanoCrop.guess(int w, int h) {
    final fullH = math.max(h.toDouble(), w / 2);
    return PanoCrop(0, (fullH - h) / 2 / fullH, 1, h / fullH);
  }

  @override
  String toString() => 'PanoCrop($left, $top, $width, $height)';
}

/// Reads GPano crop data from the XMP packet of a JPEG (or any file with plain XMP).
/// Returns null when the file has no usable GPano fields.
PanoCrop? panoCropFromXmp(Uint8List bytes) {
  // XMP sits near the start of the file; latin1 keeps byte offsets and never throws.
  final head = latin1.decode(bytes.sublist(0, math.min(bytes.length, 1 << 20)));
  double? field(String name) {
    final m = RegExp('GPano:$name(?:="([^"]*)"|>([^<]*)<)').firstMatch(head);
    return m == null ? null : double.tryParse((m[1] ?? m[2])!.trim());
  }

  final fullW = field('FullPanoWidthPixels');
  final fullH = field('FullPanoHeightPixels');
  final w = field('CroppedAreaImageWidthPixels');
  final h = field('CroppedAreaImageHeightPixels');
  if (fullW == null || fullH == null || w == null || h == null || fullW <= 0 || fullH <= 0) return null;
  final left = field('CroppedAreaLeftPixels') ?? 0;
  final top = field('CroppedAreaTopPixels') ?? (fullH - h) / 2;
  return PanoCrop(left / fullW, top / fullH, math.min(1, w / fullW), math.min(1, h / fullH));
}

/// Camera state with limits that keep a cropped panorama on screen.
class PanoView {
  final PanoCrop crop;
  double yaw, pitch, fov; // radians; fov is vertical

  static const minFov = 10 * math.pi / 180;
  static const _maxFov = 110 * math.pi / 180;

  PanoView(this.crop, {double aspect = 16 / 9})
      : yaw = crop.isFull360 ? 0 : (crop.lonMin + crop.lonMax) / 2,
        pitch = 0,
        fov = 0 {
    fov = math.min(75 * math.pi / 180, maxFov);
    clamp(aspect);
  }

  /// Zooming out further would show black above / below a partial panorama.
  double get maxFov => math.max(minFov, math.min(_maxFov, crop.vRange));

  static double hFov(double vFov, double aspect) => 2 * math.atan(math.tan(vFov / 2) * aspect);

  void clamp(double aspect) {
    fov = fov.clamp(minFov, maxFov);
    pitch = pitch.clamp(-math.pi / 2, math.pi / 2);
    if (crop.isFull360) yaw = (yaw + math.pi) % (2 * math.pi) - math.pi;
    if (crop.isFull360 && crop.height > 0.999) return; // whole sphere: anything goes
    if (_fits(yaw, pitch, aspect)) return;

    // Back off toward the middle of the image until the whole view is on it; if
    // even the middle doesn't fit, zoom in first.
    final cy = crop.isFull360 ? yaw : (crop.lonMin + crop.lonMax) / 2;
    final cp = crop.height > 0.999 ? pitch : (crop.latMin + crop.latMax) / 2;
    while (!_fits(cy, cp, aspect) && fov > minFov) {
      fov = math.max(minFov, fov * 0.95);
    }
    var lo = 0.0, hi = 1.0;
    for (var i = 0; i < 14; i++) {
      final mid = (lo + hi) / 2;
      if (_fits(cy + (yaw - cy) * mid, cp + (pitch - cp) * mid, aspect)) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    yaw = cy + (yaw - cy) * lo;
    pitch = cp + (pitch - cp) * lo;
  }

  /// Whether every point on the view's border lands inside the image (the same
  /// projection as shaders/panorama.frag).
  bool _fits(double yaw, double pitch, double aspect) {
    final t = math.tan(fov / 2);
    final cosP = math.cos(pitch), sinP = math.sin(pitch), cosY = math.cos(yaw), sinY = math.sin(yaw);
    const n = 8;
    for (var i = 0; i <= n; i++) {
      final a = -1 + 2 * i / n;
      for (final (sx, sy) in [(a, -1.0), (a, 1.0), (-1.0, a), (1.0, a)]) {
        var x = sx * t * aspect, y = sy * t, z = 1.0;
        final y1 = y * cosP + z * sinP, z1 = -y * sinP + z * cosP;
        y = y1;
        z = z1;
        final x2 = x * cosY + z * sinY, z2 = -x * sinY + z * cosY;
        x = x2;
        z = z2;
        final lon = math.atan2(x, z);
        final lat = math.asin((y / math.sqrt(x * x + y * y + z * z)).clamp(-1.0, 1.0));
        if (crop.height <= 0.999 && (lat < crop.latMin - 1e-6 || lat > crop.latMax + 1e-6)) return false;
        if (!crop.isFull360 && (lon < crop.lonMin - 1e-6 || lon > crop.lonMax + 1e-6)) return false;
      }
    }
    return true;
  }
}
