import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import '../api.dart';
import '../i18n.dart';
import '../sources.dart';
import '../window.dart';
import 'slideshow.dart';
import '../widgets/faces.dart';
import '../widgets/panorama_viewer.dart';
import '../widgets/asset_actions.dart';
import '../widgets/info_panel.dart';

class ViewerScreen extends StatefulWidget {
  final ImmichApi api;
  final AssetSource source;
  final int initialIndex;
  final TimelineMode mode;
  final String? albumId;

  const ViewerScreen({
    super.key,
    required this.api,
    required this.source,
    required this.initialIndex,
    this.mode = TimelineMode.normal,
    this.albumId,
  });

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  late int _index = widget.initialIndex;
  AssetRef? _asset;
  Map<String, dynamic>? _detail;
  List<Album>? _albums;
  bool _showInfo = false;
  final _transform = TransformationController();
  final _player = Player();
  late final _video = VideoController(_player);
  final _focus = FocusNode();
  bool _motion = false; // a live photo's video is playing over the still
  // Faces: boxes to highlight, the "Edit faces" panel, and tagging a new face.
  List<AssetFace>? _faces;
  List<({double left, double top, double width, double height})> _highlight = const [];
  bool _editFaces = false;
  Rect? _tagBox; // fractions of the image while tagging a face
  AssetFace? _hoverFace; // a named face under the mouse on the photo
  StreamSubscription<bool>? _motionDone;

  ImmichApi get api => widget.api;

  @override
  void initState() {
    super.initState();
    _motionDone = _player.stream.completed.listen((done) {
      if (done && _motion && mounted) setState(() => _motion = false); // back to the still, like the web
    });
    _go(_index);
  }

  /// From the timeline row, or the asset details (search results lack it).
  String? get _liveVideoId {
    final a = _asset;
    if (a == null || !a.isImage) return null;
    final d = _detail;
    return a.livePhotoVideoId ?? (d != null && d['id'] == a.id ? d['livePhotoVideoId'] as String? : null);
  }

  Future<void> _toggleMotion() async {
    final id = _liveVideoId;
    if (id == null) return;
    if (_motion) {
      setState(() => _motion = false);
      await _player.stop();
    } else {
      setState(() => _motion = true);
      await _player.open(Media(api.videoUrl(id), httpHeaders: api.headers));
    }
  }

  @override
  void dispose() {
    _motionDone?.cancel();
    _player.dispose();
    _transform.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<List<AssetFace>> _loadFaces() async {
    final id = _asset?.id;
    if (id == null) return const [];
    final faces = _faces ?? await api.faces(id);
    if (mounted && _asset?.id == id) _faces = faces;
    return faces;
  }

  /// Hovering a person in the info panel outlines their face(s) on the photo.
  Future<void> _highlightPerson(String? personId) async {
    if (personId == null) return setState(() => _highlight = const []);
    final faces = await _loadFaces();
    if (!mounted) return;
    setState(() => _highlight = [for (final f in faces) if (f.person?.id == personId) f.rel]);
  }

  /// Mouse over the photo: a known (named) face under the pointer gets its box
  /// and name, like hovering a person in the info panel. [rel] is in fractions.
  Future<void> _hoverPhoto(Offset? rel) async {
    if (rel == null || _tagBox != null) {
      if (_hoverFace != null) setState(() => _hoverFace = null);
      return;
    }
    final faces = _faces ?? await _loadFaces();
    if (!mounted) return;
    AssetFace? hit;
    for (final f in faces) {
      final b = f.rel;
      if ((f.person?.name.isNotEmpty ?? false) &&
          rel.dx >= b.left && rel.dx <= b.left + b.width && rel.dy >= b.top && rel.dy <= b.top + b.height) {
        hit = f;
        break;
      }
    }
    if (hit?.id != _hoverFace?.id) setState(() => _hoverFace = hit);
  }

  Future<void> _reloadDetail() async {
    final a = _asset;
    if (a == null) return;
    _faces = null;
    try {
      final d = await api.asset(a.id);
      if (mounted && _asset?.id == a.id) setState(() => _detail = d);
    } catch (_) {}
  }

  void _startTagging() {
    _transform.value = Matrix4.identity();
    ScaffoldMessenger.of(context).hideCurrentSnackBar(); // it would cover the tagging bar
    setState(() {
      _showInfo = true;
      _editFaces = false;
      _tagBox = const Rect.fromLTWH(0.375, 0.3, 0.25, 0.3);
    });
  }

  Future<void> _finishTagging() async {
    final a = _asset, box = _tagBox;
    if (a == null || box == null) return;
    final pick = await showPersonPicker(context, api, title: t('select_person_to_tag'));
    if (pick == null || !mounted) return;
    final name = pick.person?.name ?? pick.newName ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(name.isEmpty ? t('confirm_tag_face_unnamed') : t('confirm_tag_face', {'name': name})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('tag_face'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final personId = await personIdFor(api, pick);
      await api.createFace(a.id, personId, a.ratio,
          left: box.left, top: box.top, width: box.width, height: box.height);
      if (mounted) setState(() => _tagBox = null);
      await _reloadDetail();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('${t('error')}: $e')));
    }
    _focus.requestFocus();
  }

  /// Plays a slideshow from here; afterwards the viewer shows where it stopped.
  Future<void> _slideshow() async {
    await _player.pause();
    if (!mounted) return;
    final end = await openSlideshow(context, api, widget.source, _index);
    if (mounted && end != null && end != _index) _go(end);
    _focus.requestFocus();
  }

  Future<void> _go(int index) async {
    if (index < 0 || index >= widget.source.length) return;
    setState(() {
      _index = index;
      _asset = widget.source.at(index);
      _detail = null;
      _motion = false;
      _faces = null;
      _highlight = const [];
      _editFaces = false;
      _tagBox = null;
      _hoverFace = null;
      _albums = null;
      _transform.value = Matrix4.identity();
    });
    final a = _asset ?? await widget.source.load(index);
    if (!mounted || _index != index || a == null) return;
    setState(() => _asset = a);

    if (a.isImage || a.isPanorama) {
      await _player.stop(); // 360° videos play in their own viewer
    } else {
      await _player.open(Media(api.videoUrl(a.id), httpHeaders: api.headers));
    }
    _prefetch(index + 1);
    _prefetch(index - 1);
    try {
      final d = await api.asset(a.id);
      if (mounted && _index == index) setState(() => _detail = d);
      // Search results lack the projection; a 360° video found only now leaves the flat player.
      if (mounted && _index == index && !a.isImage && _isPanorama(a)) await _player.stop();
    } catch (_) {}
    try {
      final albums = await api.albumsOf(a.id);
      if (mounted && _index == index) setState(() => _albums = albums);
    } catch (_) {}
  }

  void _prefetch(int index) {
    final a = widget.source.at(index);
    if (a == null || !a.isImage || !mounted) return;
    precacheImage(
      NetworkImage(api.thumbnailUrl(a.id, size: 'preview'), headers: api.headers),
      context,
      onError: (_, _) {},
    );
  }

  Future<void> _act(AssetAction action) async {
    final a = _asset;
    if (a == null) return;
    final ok = await performAction(context, api, widget.source, action, [a],
        albumId: widget.albumId);
    if (!ok || !mounted) return;
    switch (action) {
      case AssetAction.favorite:
      case AssetAction.unfavorite:
        setState(() => _asset = a.copyWith(isFavorite: action == AssetAction.favorite));
      case AssetAction.addToAlbum:
        final albums = await api.albumsOf(a.id).catchError((_) => <Album>[]);
        if (mounted) setState(() => _albums = albums);
      case AssetAction.download:
        break;
      default:
        // The asset left this list: show the next one, or close when empty.
        if (widget.source.length == 0) {
          Navigator.of(context).maybePop();
        } else {
          _go(_index.clamp(0, widget.source.length - 1));
        }
    }
  }

  Future<void> _download() async {
    final a = _asset;
    if (a == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final detail = _detail ?? await api.asset(a.id);
      final dir = await downloadsDir();
      await dir.create(recursive: true);
      final name = p.basename(detail['originalFileName'] ?? '${a.id}.bin');
      var target = File(p.join(dir.path, name));
      for (var n = 1; await target.exists(); n++) {
        target = File(p.join(dir.path,
            '${p.basenameWithoutExtension(name)} ($n)${p.extension(name)}'));
      }
      messenger.showSnackBar(SnackBar(content: Text(t('linux_downloading_file', {'name': name}))));
      await api.downloadOriginal(a.id, target);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text(t('linux_saved_to', {'files': target.path})),
        action: SnackBarAction(
          label: t('linux_open_folder'),
          onPressed: () => Process.run('xdg-open', [dir.path]),
        ),
      ));
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('${t('error')}: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _asset;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(_index + 1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(_index - 1),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          // Esc first leaves face tagging / editing, then the viewer.
          if (_tagBox != null || _editFaces) {
            setState(() {
              _tagBox = null;
              _editFaces = false;
            });
          } else {
            Navigator.of(context).maybePop();
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyI): () =>
            setState(() => _showInfo = !_showInfo),
        const SingleActivator(LogicalKeyboardKey.keyD): _download,
        const SingleActivator(LogicalKeyboardKey.f11): toggleFullScreen,
        if (widget.mode == TimelineMode.normal || widget.mode == TimelineMode.archive) ...{
          const SingleActivator(LogicalKeyboardKey.keyF): () => _act(
              _asset?.isFavorite == true ? AssetAction.unfavorite : AssetAction.favorite),
          const SingleActivator(LogicalKeyboardKey.keyA): () => _act(
              widget.mode == TimelineMode.archive ? AssetAction.unarchive : AssetAction.archive),
          const SingleActivator(LogicalKeyboardKey.delete): () => _act(AssetAction.trash),
        },
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Row(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (a == null)
                      const Center(child: CircularProgressIndicator())
                    else if (a.isImage && _motion)
                      Video(controller: _video, controls: NoVideoControls)
                    else if (a.isImage && _isPanorama(a))
                      PanoramaViewer(key: ValueKey(a.id), api: api, assetId: a.id)
                    else if (a.isImage)
                      _buildImage(a)
                    else if (_isPanorama(a))
                      PanoramaVideoViewer(key: ValueKey(a.id), api: api, assetId: a.id)
                    else
                      Video(controller: _video, controls: MaterialDesktopVideoControls),
                    _buildTopBar(),
                    if (_tagBox != null) _taggingBar(),
                    if (_index > 0)
                      _navButton(Alignment.centerLeft, Icons.chevron_left, () => _go(_index - 1)),
                    if (_index < widget.source.length - 1)
                      _navButton(
                          Alignment.centerRight, Icons.chevron_right, () => _go(_index + 1)),
                  ],
                ),
              ),
              if (_showInfo)
                SizedBox(
                  width: 340,
                  child: _editFaces && a != null
                      ? EditFacesPanel(
                          key: ValueKey('faces${a.id}'),
                          api: api,
                          assetId: a.id,
                          onClose: () => setState(() {
                            _editFaces = false;
                            _highlight = const [];
                            _focus.requestFocus();
                          }),
                          onChanged: _reloadDetail,
                          onHover: (f) => setState(() => _highlight = f == null ? const [] : [f.rel]),
                        )
                      : InfoPanel(
                          api: api,
                          detail: _detail,
                          albums: _albums,
                          canEdit: widget.mode == TimelineMode.normal || widget.mode == TimelineMode.archive,
                          onChanged: (d) => setState(() => _detail = d),
                          onEditingDone: _focus.requestFocus,
                          onHighlightPerson: _highlightPerson,
                          onEditFaces: a != null && a.isImage ? () => setState(() => _editFaces = true) : null,
                          onTagFace: a != null && a.isImage && !_isPanorama(a) ? _startTagging : null,
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// From the timeline row, or the asset details once they arrive (search results).
  bool _isPanorama(AssetRef a) {
    if (a.isPanorama) return true;
    final d = _detail;
    return d != null &&
        d['id'] == a.id &&
        AssetRef.panoramaFrom(d['exifInfo']?['projectionType'] as String?, d['originalPath'] as String?);
  }

  Widget _buildImage(AssetRef a) {
    // Exactly the photo's shape, so face boxes (fractions) line up at any zoom.
    final framed = Center(
      child: AspectRatio(
        aspectRatio: a.ratio > 0 ? a.ratio : 1,
        child: LayoutBuilder(
          builder: (context, c) => MouseRegion(
            onHover: (e) => _hoverPhoto(Offset(e.localPosition.dx / c.maxWidth, e.localPosition.dy / c.maxHeight)),
            onExit: (_) => _hoverPhoto(null),
            child: Stack(fit: StackFit.expand, children: [
              _photo(a),
              if ((_highlight.isNotEmpty || _hoverFace != null) && _tagBox == null)
                IgnorePointer(
                  child: CustomPaint(
                    painter: FaceBoxesPainter(
                        [..._highlight, if (_hoverFace != null) _hoverFace!.rel], Theme.of(context).colorScheme.primary),
                  ),
                ),
              if (_hoverFace != null && _tagBox == null) _faceLabel(_hoverFace!, c.biggest),
              if (_tagBox != null)
                FaceTagBox(
                  key: ValueKey('tag${a.id}'),
                  initial: _tagBox!,
                  onChanged: (r) => _tagBox = r,
                ),
            ]),
          ),
        ),
      ),
    );
    // While a face box is drawn the zoom is reset and off, so drags reach the box
    // (InteractiveViewer's recognizers compete for them even when disabled).
    if (_tagBox != null) return framed;
    return GestureDetector(
      onDoubleTap: () => setState(() {
        _transform.value = _transform.value.getMaxScaleOnAxis() > 1
            ? Matrix4.identity()
            : (Matrix4.identity()..scaleByDouble(2.5, 2.5, 2.5, 1));
      }),
      child: InteractiveViewer(transformationController: _transform, maxScale: 8, child: framed),
    );
  }

  /// The name under a hovered face box (above it when the face is near the bottom).
  Widget _faceLabel(AssetFace f, Size size) {
    final b = f.rel;
    final below = b.top + b.height < 0.9;
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      left: b.left * size.width,
      top: below ? (b.top + b.height) * size.height + 6 : null,
      bottom: below ? null : (1 - b.top) * size.height + 6,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Text(f.person!.name, style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }

  /// Shown while drawing a face box (web: FaceEditor's bar).
  Widget _taggingBar() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 72),
        child: Material(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.face_retouching_natural, color: Colors.white),
              const SizedBox(width: 10),
              Text(t('tag_face'), style: const TextStyle(color: Colors.white)),
              const SizedBox(width: 20),
              TextButton(
                onPressed: () => setState(() => _tagBox = null),
                child: Text(t('cancel')),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _finishTagging,
                icon: const Icon(Icons.person_search),
                label: Text(t('select_person')),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _photo(AssetRef a) {
    return Image(
            // Low-res thumbnail shows instantly, then the preview replaces it.
            image: NetworkImage(api.thumbnailUrl(a.id, size: 'preview'), headers: api.headers),
            fit: BoxFit.fill,
            gaplessPlayback: true,
            frameBuilder: (context, child, frame, sync) => frame == null && !sync
                ? Image(
                    image: NetworkImage(api.thumbnailUrl(a.id), headers: api.headers),
                    fit: BoxFit.contain,
                    width: double.infinity,
                    height: double.infinity,
                  )
                : child,
            errorBuilder: (_, _, _) =>
                const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
    );
  }

  Widget _buildTopBar() {
    final name = _detail?['originalFileName'] as String?;
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black54, Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
        child: IconTheme(
          data: const IconThemeData(color: Colors.white),
          child: Row(children: [
            IconButton(
              tooltip: t('linux_back_esc'),
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name ?? '',
                style: const TextStyle(color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_liveVideoId != null)
              IconButton(
                tooltip: _motion ? t('stop_motion_photo') : t('play_motion_photo'),
                icon: Icon(_motion ? Icons.motion_photos_pause_outlined : Icons.motion_photos_on_outlined),
                onPressed: _toggleMotion,
              ),
            IconButton(
              tooltip: t('slideshow'),
              icon: const Icon(Icons.slideshow_outlined),
              onPressed: _slideshow,
            ),
            ..._actionButtons(),
            IconButton(
              tooltip: t('linux_download_key'),
              icon: const Icon(Icons.download),
              onPressed: _download,
            ),
            IconButton(
              tooltip: t('linux_info_key'),
              icon: Icon(_showInfo ? Icons.info : Icons.info_outline),
              onPressed: () => setState(() => _showInfo = !_showInfo),
            ),
          ]),
        ),
      ),
    );
  }

  List<Widget> _actionButtons() {
    final a = _asset;
    if (a == null) return const [];
    Widget btn(AssetAction action, String key, {IconData? icon, Color? color}) => IconButton(
          tooltip: key.isEmpty ? action.label : '${action.label} ($key)',
          icon: Icon(icon ?? action.icon, color: color),
          onPressed: () => _act(action),
        );
    return switch (widget.mode) {
      TimelineMode.normal || TimelineMode.archive => [
          a.isFavorite
              ? btn(AssetAction.unfavorite, 'F', icon: Icons.favorite, color: Colors.redAccent)
              : btn(AssetAction.favorite, 'F'),
          btn(AssetAction.addToAlbum, ''),
          if (widget.albumId != null) btn(AssetAction.removeFromAlbum, ''),
          widget.mode == TimelineMode.archive
              ? btn(AssetAction.unarchive, 'A')
              : btn(AssetAction.archive, 'A'),
          if (widget.mode == TimelineMode.normal) btn(AssetAction.lock, ''),
          btn(AssetAction.trash, 'Delete'),
        ],
      TimelineMode.trash => [
          btn(AssetAction.restore, ''),
          btn(AssetAction.deleteForever, '', color: Colors.redAccent),
        ],
      TimelineMode.locked => [
          btn(AssetAction.unlock, ''),
          btn(AssetAction.deleteForever, '', color: Colors.redAccent),
        ],
      TimelineMode.readOnly => const [],
    };
  }

  Widget _navButton(Alignment align, IconData icon, VoidCallback onTap) {
    return Align(
      alignment: align,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: IconButton.filledTonal(
          style: IconButton.styleFrom(backgroundColor: Colors.black38),
          icon: Icon(icon, color: Colors.white, size: 32),
          onPressed: onTap,
        ),
      ),
    );
  }
}
