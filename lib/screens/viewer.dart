import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import '../api.dart';
import '../i18n.dart';
import '../sources.dart';
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

  ImmichApi get api => widget.api;

  @override
  void initState() {
    super.initState();
    _go(_index);
  }

  @override
  void dispose() {
    _player.dispose();
    _transform.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _go(int index) async {
    if (index < 0 || index >= widget.source.length) return;
    setState(() {
      _index = index;
      _asset = widget.source.at(index);
      _detail = null;
      _albums = null;
      _transform.value = Matrix4.identity();
    });
    final a = _asset ?? await widget.source.load(index);
    if (!mounted || _index != index || a == null) return;
    setState(() => _asset = a);

    if (a.isImage) {
      await _player.stop();
    } else {
      await _player.open(Media(api.videoUrl(a.id), httpHeaders: api.headers));
    }
    _prefetch(index + 1);
    _prefetch(index - 1);
    try {
      final d = await api.asset(a.id);
      if (mounted && _index == index) setState(() => _detail = d);
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
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop(),
        const SingleActivator(LogicalKeyboardKey.keyI): () =>
            setState(() => _showInfo = !_showInfo),
        const SingleActivator(LogicalKeyboardKey.keyD): _download,
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
                    else if (a.isImage)
                      _buildImage(a)
                    else
                      Video(controller: _video, controls: MaterialDesktopVideoControls),
                    _buildTopBar(),
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
                  child: InfoPanel(
                    api: api,
                    detail: _detail,
                    albums: _albums,
                    canEdit: widget.mode == TimelineMode.normal || widget.mode == TimelineMode.archive,
                    onChanged: (d) => setState(() => _detail = d),
                    onEditingDone: _focus.requestFocus,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImage(AssetRef a) {
    return GestureDetector(
      onDoubleTap: () => setState(() {
        _transform.value = _transform.value.getMaxScaleOnAxis() > 1
            ? Matrix4.identity()
            : (Matrix4.identity()..scaleByDouble(2.5, 2.5, 2.5, 1));
      }),
      child: InteractiveViewer(
        transformationController: _transform,
        maxScale: 8,
        child: Center(
          child: Image(
            // Low-res thumbnail shows instantly, then the preview replaces it.
            image: NetworkImage(api.thumbnailUrl(a.id, size: 'preview'), headers: api.headers),
            fit: BoxFit.contain,
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
          ),
        ),
      ),
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
