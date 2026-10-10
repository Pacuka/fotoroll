// "On this day" memories (web: memory lane on /photos and /memory viewer).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../api.dart';
import '../i18n.dart';
import 'hover_preview.dart';

String memoryTitle(Map<String, dynamic> m) {
  final year = (m['data'] as Map?)?['year'] as int?;
  if (m['type'] == 'on_this_day' && year != null) {
    return t('years_ago', {'years': DateTime.now().year - year});
  }
  return t('unknown');
}

/// Horizontal strip of memory cards shown above the Photos timeline.
class MemoryLane extends StatelessWidget {
  final ImmichApi api;
  final List<Map<String, dynamic>> memories;
  const MemoryLane({super.key, required this.api, required this.memories});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: memories.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, i) {
        final m = memories[i];
        final first = (m['assets'] as List).first as Map<String, dynamic>;
        return SizedBox(
          width: 150,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Material(
              child: InkWell(
                onTap: () {
                  HoverPreview.stopAll();
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => MemoryViewer(api: api, memories: memories, initial: i),
                  ));
                },
                child: Stack(fit: StackFit.expand, children: [
                  Image(
                    image: NetworkImage(api.thumbnailUrl(first['id']), headers: api.headers),
                    fit: BoxFit.cover,
                    color: Colors.black26,
                    colorBlendMode: BlendMode.darken,
                    errorBuilder: (_, _, _) => const SizedBox(),
                  ),
                  Positioned(
                    left: 10,
                    bottom: 10,
                    right: 10,
                    child: Text(memoryTitle(m),
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600, shadows: [Shadow(blurRadius: 6)])),
                  ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Full-screen memory player: photos advance after 5 s, videos when they end.
class MemoryViewer extends StatefulWidget {
  final ImmichApi api;
  final List<Map<String, dynamic>> memories;
  final int initial;
  const MemoryViewer({super.key, required this.api, required this.memories, required this.initial});

  @override
  State<MemoryViewer> createState() => _MemoryViewerState();
}

class _MemoryViewerState extends State<MemoryViewer> with SingleTickerProviderStateMixin {
  static const _photoDuration = Duration(seconds: 5);
  late int _memory = widget.initial;
  int _asset = 0;
  bool _paused = false;
  late final AnimationController _progress = AnimationController(vsync: this, duration: _photoDuration)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _next();
    });
  final _player = Player();
  late final _video = VideoController(_player);
  StreamSubscription<bool>? _completed;
  final _focus = FocusNode();

  Map<String, dynamic> get _m => widget.memories[_memory];
  List<Map<String, dynamic>> get _assets => (_m['assets'] as List).cast<Map<String, dynamic>>();
  Map<String, dynamic> get _current => _assets[_asset];

  @override
  void initState() {
    super.initState();
    _completed = _player.stream.completed.listen((done) {
      if (done && mounted) _next();
    });
    _show();
  }

  @override
  void dispose() {
    _completed?.cancel();
    _player.dispose();
    _progress.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _show() async {
    _progress.stop();
    _progress.value = 0;
    // Like the web: opening a memory marks it seen.
    if (_asset == 0 && _m['seenAt'] == null) {
      widget.api.updateMemory(_m['id'], {'seenAt': DateTime.now().toUtc().toIso8601String()}).catchError((_) {});
      _m['seenAt'] = 'now';
    }
    if (_current['type'] == 'VIDEO') {
      await _player.open(Media(widget.api.videoUrl(_current['id']), httpHeaders: widget.api.headers),
          play: !_paused);
    } else {
      await _player.stop();
      if (!_paused) _progress.forward();
    }
    if (mounted) setState(() {});
  }

  void _next() {
    if (_asset < _assets.length - 1) {
      _asset++;
    } else if (_memory < widget.memories.length - 1) {
      _memory++;
      _asset = 0;
    } else {
      Navigator.of(context).maybePop();
      return;
    }
    _show();
  }

  void _previous() {
    if (_asset > 0) {
      _asset--;
    } else if (_memory > 0) {
      _memory--;
      _asset = 0;
    }
    _show();
  }

  void _jumpMemory(int delta) {
    final m = _memory + delta;
    if (m < 0 || m >= widget.memories.length) return;
    _memory = m;
    _asset = 0;
    _show();
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    if (_current['type'] == 'VIDEO') {
      _paused ? _player.pause() : _player.play();
    } else {
      _paused ? _progress.stop() : _progress.forward();
    }
  }

  Future<void> _toggleSaved() async {
    final saved = _m['isSaved'] == true;
    try {
      await widget.api.updateMemory(_m['id'], {'isSaved': !saved});
      setState(() => _m['isSaved'] = !saved);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(!saved ? t('saved') : t('linux_saved'))));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t('error')}: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = widget.api;
    final isVideo = _current['type'] == 'VIDEO';
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): _next,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): _previous,
        const SingleActivator(LogicalKeyboardKey.space): _togglePause,
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop(),
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(fit: StackFit.expand, children: [
            GestureDetector(
              onTap: _togglePause,
              child: isVideo
                  ? Video(controller: _video, controls: NoVideoControls)
                  : Image(
                      key: ValueKey(_current['id']),
                      image: NetworkImage(api.thumbnailUrl(_current['id'], size: 'preview'), headers: api.headers),
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, color: Colors.white54),
                    ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  // One progress segment per asset, like the web.
                  Row(children: [
                    for (var i = 0; i < _assets.length; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: i == _asset && !isVideo
                              ? AnimatedBuilder(
                                  animation: _progress,
                                  builder: (_, _) => LinearProgressIndicator(
                                      value: _progress.value, minHeight: 3, color: Colors.white, backgroundColor: Colors.white24),
                                )
                              : LinearProgressIndicator(
                                  value: i < _asset ? 1 : (i == _asset ? null : 0),
                                  minHeight: 3,
                                  color: Colors.white,
                                  backgroundColor: Colors.white24,
                                ),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  IconTheme(
                    data: const IconThemeData(color: Colors.white),
                    child: Row(children: [
                      IconButton(
                        tooltip: t('linux_close'),
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(memoryTitle(_m),
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                      ),
                      IconButton(
                        tooltip: _paused ? t('play_memories') : t('pause_memories'),
                        icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                        onPressed: _togglePause,
                      ),
                      IconButton(
                        tooltip: t('save'),
                        icon: Icon(_m['isSaved'] == true ? Icons.favorite : Icons.favorite_border),
                        onPressed: _toggleSaved,
                      ),
                      IconButton(
                        tooltip: t('previous_memory'),
                        icon: const Icon(Icons.skip_previous),
                        onPressed: _memory > 0 ? () => _jumpMemory(-1) : null,
                      ),
                      IconButton(
                        tooltip: t('next_memory'),
                        icon: const Icon(Icons.skip_next),
                        onPressed: _memory < widget.memories.length - 1 ? () => _jumpMemory(1) : null,
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: const Icon(Icons.chevron_left, color: Colors.white, size: 40),
                onPressed: _previous,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: const Icon(Icons.chevron_right, color: Colors.white, size: 40),
                onPressed: _next,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
