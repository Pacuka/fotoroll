// Interactive 360° / 180° panorama viewer (web: PhotoSphereViewer). Shows the
// preview at once, then swaps in the original for full sharpness; the original's
// GPano XMP says how much of the sphere a partial panorama covers.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../i18n.dart';
import '../panorama.dart';

/// Largest texture we decode to; ~8k wide is plenty for a 360° view and keeps
/// GPU memory sane (an 8192×4096 RGBA texture is 128 MB).
const _maxTextureWidth = 8192;

ui.FragmentProgram? _program;
Future<ui.FragmentProgram> _loadProgram() async =>
    _program ??= await ui.FragmentProgram.fromAsset('shaders/panorama.frag');

Future<ui.Image> _decode(Uint8List bytes) async {
  final probe = await ui.ImmutableBuffer.fromUint8List(bytes);
  final desc = await ui.ImageDescriptor.encoded(probe);
  final w = desc.width;
  desc.dispose();
  probe.dispose();
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: w > _maxTextureWidth ? _maxTextureWidth : null);
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

class PanoramaViewer extends StatefulWidget {
  final ImmichApi api;
  final String assetId;
  const PanoramaViewer({super.key, required this.api, required this.assetId});

  @override
  State<PanoramaViewer> createState() => _PanoramaViewerState();
}

class _PanoramaViewerState extends State<PanoramaViewer> {
  ui.FragmentShader? _shader;
  ui.Image? _image;
  PanoView? _view;
  Object? _error;
  double? _originalProgress; // null once the original is in (or failed)
  Size _size = Size.zero;
  double _fovAtScaleStart = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _image?.dispose();
    _shader?.dispose();
    super.dispose();
  }

  double get _aspect => _size.height > 0 ? _size.width / _size.height : 16 / 9;

  Future<void> _load() async {
    final api = widget.api;
    try {
      final program = await _loadProgram();
      final preview = await _decode(await api.previewBytes(widget.assetId));
      if (!mounted) return preview.dispose();
      setState(() {
        _shader = program.fragmentShader();
        _image = preview;
        _view = PanoView(PanoCrop.guess(preview.width, preview.height), aspect: _aspect);
        _originalProgress = 0;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
      return;
    }
    try {
      final bytes = await api.originalBytes(widget.assetId, onProgress: (p) {
        if (mounted) setState(() => _originalProgress = p);
      });
      final image = await _decode(bytes);
      if (!mounted) return image.dispose();
      final crop = panoCropFromXmp(bytes) ?? PanoCrop.guess(image.width, image.height);
      setState(() {
        _image?.dispose();
        _image = image;
        final old = _view!;
        final crops = old.crop.toString() == crop.toString();
        _view = crops ? old : (PanoView(crop, aspect: _aspect)); // the XMP may change the geometry
        _originalProgress = null;
      });
    } catch (_) {
      // The preview stays; it's just softer.
      if (mounted) setState(() => _originalProgress = null);
    }
  }

  void _rotate(Offset delta) {
    final v = _view;
    if (v == null || _size.height == 0) return;
    // Drag moves the picture with the pointer: one screen height = the vertical fov.
    final perPx = v.fov / _size.height;
    setState(() {
      v.yaw -= delta.dx * perPx;
      v.pitch += delta.dy * perPx;
      v.clamp(_aspect);
    });
  }

  void _zoom(double factor) {
    final v = _view;
    if (v == null) return;
    setState(() {
      v.fov *= factor;
      v.clamp(_aspect);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text('${t('errors.failed_to_load_asset')}\n$_error',
          textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)));
    }
    final image = _image, shader = _shader, view = _view;
    if (image == null || shader == null || view == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return LayoutBuilder(builder: (context, c) {
      if (_size != c.biggest) {
        _size = c.biggest;
        view.clamp(_aspect);
      }
      return Stack(fit: StackFit.expand, children: [
        Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) _zoom(math.pow(1.0015, e.scrollDelta.dy).toDouble());
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: (_) => _fovAtScaleStart = view.fov,
            onScaleUpdate: (d) {
              if (d.pointerCount > 1) {
                setState(() {
                  view.fov = _fovAtScaleStart / d.scale;
                  view.clamp(_aspect);
                });
              } else {
                _rotate(d.focalPointDelta);
              }
            },
            onDoubleTap: () => setState(() {
              final reset = PanoView(view.crop, aspect: _aspect);
              final zoomedIn = view.fov < reset.fov * 0.8;
              view.fov = zoomedIn ? reset.fov : reset.fov / 2.5;
              view.clamp(_aspect);
            }),
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: CustomPaint(painter: _PanoramaPainter(shader, image, view)),
            ),
          ),
        ),
        Positioned(
          left: 16,
          bottom: 16,
          child: _Badge(
            label: view.crop.isFull360 && view.crop.height > 0.999
                ? '360°'
                : '${(view.crop.width * 360).round()}° × ${(view.crop.height * 180).round()}°',
            progress: _originalProgress,
          ),
        ),
      ]);
    });
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final double? progress;
  const _Badge({required this.label, required this.progress});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.threesixty, color: Colors.white, size: 18),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white)),
          if (progress != null) ...[
            const SizedBox(width: 10),
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: progress! > 0 ? progress : null,
                color: Colors.white70,
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

class _PanoramaPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final ui.Image image;
  final PanoView view;
  // Snapshot so shouldRepaint sees changes to the (mutable) view.
  final List<double> _state;

  _PanoramaPainter(this.shader, this.image, this.view)
      : _state = [view.yaw, view.pitch, view.fov, view.crop.left, view.crop.top, view.crop.width, view.crop.height];

  @override
  void paint(Canvas canvas, Size size) {
    final c = view.crop;
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, view.yaw)
      ..setFloat(3, view.pitch)
      ..setFloat(4, view.fov)
      ..setFloat(5, c.left)
      ..setFloat(6, c.top)
      ..setFloat(7, c.width)
      ..setFloat(8, c.height)
      ..setImageSampler(0, image);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_PanoramaPainter old) {
    if (!identical(old.image, image) || !identical(old.shader, shader)) return true;
    for (var i = 0; i < _state.length; i++) {
      if (old._state[i] != _state[i]) return true;
    }
    return false;
  }
}
