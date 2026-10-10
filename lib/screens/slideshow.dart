// Full-screen slideshow (web: SlideshowBar + SlideshowSettingsModal): forward,
// backward or shuffled, contain / cover / blurred-background look, progress bar,
// fade transition, video autoplay, repeat and an info overlay.
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../api.dart';
import '../i18n.dart';
import '../settings.dart';
import '../sources.dart';
import '../window.dart';

/// Opens the slideshow at [startIndex] of [source]; returns the index it ended on.
Future<int?> openSlideshow(BuildContext context, ImmichApi api, AssetSource source, int startIndex) =>
    Navigator.of(context).push<int>(PageRouteBuilder(
      opaque: true,
      pageBuilder: (_, _, _) => SlideshowScreen(api: api, source: source, startIndex: startIndex),
      transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
    ));

/// Index order of a slideshow. Shuffle is a random permutation that starts at [start].
class SlideshowOrder {
  final int length;
  final String direction;
  final List<int>? _shuffled;

  SlideshowOrder(this.length, int start, this.direction, {math.Random? random})
      : _shuffled = direction == 'shuffle'
            ? ([for (var i = 0; i < length; i++) if (i != start) i]..shuffle(random)).toList()
            : null {
    _shuffled?.insert(0, start);
  }

  /// The slide after [index], or null at the end (wrapping when [repeat]).
  int? next(int index, {bool repeat = false}) {
    if (length == 0) return null;
    final s = _shuffled;
    if (s != null) {
      final pos = s.indexOf(index) + 1;
      return pos < s.length ? s[pos] : (repeat ? s.first : null);
    }
    final n = direction == 'backward' ? index - 1 : index + 1;
    if (n >= 0 && n < length) return n;
    return repeat ? (direction == 'backward' ? length - 1 : 0) : null;
  }

  int? previous(int index) {
    final s = _shuffled;
    if (s != null) {
      final pos = s.indexOf(index) - 1;
      return pos >= 0 ? s[pos] : null;
    }
    final p = direction == 'backward' ? index + 1 : index - 1;
    return p >= 0 && p < length ? p : null;
  }
}

class SlideshowScreen extends StatefulWidget {
  final ImmichApi api;
  final AssetSource source;
  final int startIndex;
  const SlideshowScreen({super.key, required this.api, required this.source, required this.startIndex});

  @override
  State<SlideshowScreen> createState() => _SlideshowScreenState();
}

class _SlideshowScreenState extends State<SlideshowScreen> with SingleTickerProviderStateMixin {
  late SlideshowPrefs _prefs = settings.slideshow.copy();
  late SlideshowOrder _order = SlideshowOrder(widget.source.length, widget.startIndex, _prefs.direction);
  late final AnimationController _timer = AnimationController(vsync: this)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _advance();
    });
  final _focus = FocusNode();
  final _player = Player();
  late final _video = VideoController(_player);
  StreamSubscription<bool>? _videoDone;

  late int _index = widget.startIndex;
  AssetRef? _asset;
  Map<String, dynamic>? _detail;
  bool _playing = true;
  bool _videoSlide = false;
  bool _controls = true;
  bool _overControls = false;
  Timer? _hideTimer;
  bool _wasFullScreen = false;
  int _generation = 0;

  ImmichApi get api => widget.api;

  @override
  void initState() {
    super.initState();
    _videoDone = _player.stream.completed.listen((done) {
      if (done && _videoSlide && mounted) _advance();
    });
    isFullScreen().then((v) {
      _wasFullScreen = v;
      setFullScreen(true);
    });
    _showControls();
    _show(_index);
  }

  @override
  void dispose() {
    if (!_wasFullScreen) setFullScreen(false);
    _hideTimer?.cancel();
    _videoDone?.cancel();
    _player.dispose();
    _timer.dispose();
    _focus.dispose();
    super.dispose();
  }

  ImageProvider _preview(String id) => NetworkImage(api.thumbnailUrl(id, size: 'preview'), headers: api.headers);

  /// Loads slide [index]; the timer starts once its image is ready, like the web.
  Future<void> _show(int index) async {
    final gen = ++_generation;
    _timer.stop();
    _timer.value = 0;
    final a = await widget.source.load(index);
    if (!mounted || gen != _generation || a == null) return;
    final isVideo = !a.isImage && _prefs.autoplay;
    if (!isVideo) {
      try {
        await precacheImage(_preview(a.id), context);
      } catch (_) {}
    }
    if (!mounted || gen != _generation) return;
    setState(() {
      _index = index;
      _asset = a;
      _detail = null;
      _videoSlide = isVideo;
    });
    if (_prefs.overlay) {
      api.asset(a.id).then((d) {
        if (mounted && gen == _generation) setState(() => _detail = d);
      }).catchError((_) {});
    }
    if (isVideo) {
      await _player.open(Media(api.videoUrl(a.id), httpHeaders: api.headers), play: _playing);
    } else {
      await _player.stop();
      _timer.duration = Duration(seconds: _prefs.seconds);
      if (_playing) _timer.forward(from: 0);
    }
    // Warm up the next image so the change is instant.
    final n = _order.next(index, repeat: _prefs.repeat);
    if (n != null) {
      widget.source.load(n).then((next) {
        if (next != null && next.isImage && mounted) precacheImage(_preview(next.id), context).catchError((_) {});
      });
    }
  }

  void _advance() {
    final n = _order.next(_index, repeat: _prefs.repeat);
    if (n == null) {
      setState(() => _playing = false); // the end: stay on the last slide
      return;
    }
    _show(n);
  }

  void _back() {
    final p = _order.previous(_index);
    if (p != null) _show(p);
  }

  void _togglePlay() {
    setState(() => _playing = !_playing);
    if (_videoSlide) {
      _playing ? _player.play() : _player.pause();
    } else if (_playing) {
      _timer.forward();
    } else {
      _timer.stop();
    }
    _showControls();
  }

  void _showControls() {
    _hideTimer?.cancel();
    if (!_controls) setState(() => _controls = true);
    _hideTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted && !_overControls) setState(() => _controls = false);
    });
  }

  Future<void> _openSettings() async {
    final wasPlaying = _playing;
    if (wasPlaying) _togglePlay();
    final p = await showDialog<SlideshowPrefs>(
      context: context,
      builder: (_) => SlideshowSettingsDialog(initial: _prefs),
    );
    if (p != null && mounted) {
      final reorder = p.direction != _prefs.direction;
      _prefs = p;
      await settings.update(slideshow: p);
      if (reorder) _order = SlideshowOrder(widget.source.length, _index, p.direction);
      setState(() {});
    }
    if (wasPlaying && mounted) {
      _togglePlay();
      if (!_videoSlide) _show(_index); // apply a new duration / look right away
    }
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final a = _asset;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop(_index),
        const SingleActivator(LogicalKeyboardKey.arrowRight): _advance,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): _back,
        const SingleActivator(LogicalKeyboardKey.space): _togglePlay,
        const SingleActivator(LogicalKeyboardKey.f11): toggleFullScreen,
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: MouseRegion(
          cursor: _controls ? MouseCursor.defer : SystemMouseCursors.none,
          onHover: (_) => _showControls(),
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(fit: StackFit.expand, children: [
              AnimatedSwitcher(
                duration: Duration(milliseconds: _prefs.transition ? 500 : 0),
                child: a == null
                    ? const Center(child: CircularProgressIndicator())
                    : KeyedSubtree(key: ValueKey('${a.id}$_videoSlide${_prefs.look}'), child: _slide(a)),
              ),
              if (_prefs.progressBar && !_videoSlide)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedBuilder(
                    animation: _timer,
                    builder: (_, _) => LinearProgressIndicator(
                      value: _timer.value,
                      minHeight: 3,
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                ),
              if (_prefs.overlay && _detail != null) _overlay(_detail!),
              _controlBar(),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _slide(AssetRef a) {
    if (_videoSlide) return Video(controller: _video, controls: NoVideoControls);
    final fit = _prefs.look == 'cover' ? BoxFit.cover : BoxFit.contain;
    final image = Image(image: _preview(a.id), fit: fit, width: double.infinity, height: double.infinity);
    if (_prefs.look != 'blurred') return image;
    return Stack(fit: StackFit.expand, children: [
      ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40, tileMode: TileMode.decal),
        child: Image(image: _preview(a.id), fit: BoxFit.cover),
      ),
      const ColoredBox(color: Colors.black26),
      image,
    ]);
  }

  Widget _overlay(Map<String, dynamic> d) {
    final exif = (d['exifInfo'] as Map?) ?? const {};
    final description = (exif['description'] as String?)?.trim() ?? '';
    final full = _prefs.overlayMode == 'full';
    final date = DateTime.tryParse((d['localDateTime'] as String? ?? '').replaceAll('Z', ''));
    final place = [exif['city'], exif['country']].whereType<String>().where((s) => s.isNotEmpty).join(', ');
    final lines = [
      if (description.isNotEmpty) description,
      if (full && date != null) DateFormat.yMMMMd(i18n.dateLocale).add_Hm().format(date),
      if (full && place.isNotEmpty) place,
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    const shadow = [Shadow(blurRadius: 6, color: Colors.black)];
    return Positioned(
      left: 32,
      bottom: 32,
      right: 32,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < lines.length; i++)
          Text(lines[i],
              style: TextStyle(
                color: Colors.white,
                fontSize: i == 0 && description.isNotEmpty ? 22 : 15,
                shadows: shadow,
              )),
      ]),
    );
  }

  Widget _controlBar() {
    Widget button(IconData icon, String tip, VoidCallback onTap) =>
        IconButton(tooltip: tip, icon: Icon(icon, color: Colors.white), onPressed: onTap);
    return Positioned(
      top: 16,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: _controls ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: !_controls,
          child: Center(
            child: MouseRegion(
              onEnter: (_) => _overControls = true,
              onExit: (_) => _overControls = false,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(28)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    button(Icons.close, t('exit_slideshow'), () => Navigator.of(context).maybePop(_index)),
                    button(Icons.chevron_left, t('previous'), _back),
                    button(_playing ? Icons.pause : Icons.play_arrow, _playing ? t('pause') : t('play'), _togglePlay),
                    button(Icons.chevron_right, t('next'), _advance),
                    button(Icons.settings_outlined, t('slideshow_settings'), _openSettings),
                    button(Icons.fullscreen, 'F11', toggleFullScreen),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SlideshowSettingsDialog extends StatefulWidget {
  final SlideshowPrefs initial;
  const SlideshowSettingsDialog({super.key, required this.initial});

  @override
  State<SlideshowSettingsDialog> createState() => _SlideshowSettingsDialogState();
}

class _SlideshowSettingsDialogState extends State<SlideshowSettingsDialog> {
  late final SlideshowPrefs p = widget.initial.copy();

  @override
  Widget build(BuildContext context) {
    Widget choice(String label, String value, List<(String, String)> options, ValueChanged<String> onChanged) =>
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t(label)),
          trailing: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [for (final (v, k) in options) ButtonSegment(value: v, label: Text(t(k)))],
            selected: {value},
            onSelectionChanged: (s) => setState(() => onChanged(s.first)),
          ),
        );
    Widget toggle(String label, bool value, ValueChanged<bool> onChanged, {String? subtitle}) => SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t(label)),
          subtitle: subtitle == null ? null : Text(t(subtitle)),
          value: value,
          onChanged: (v) => setState(() => onChanged(v)),
        );
    return AlertDialog(
      icon: const Icon(Icons.slideshow),
      title: Text(t('slideshow_settings')),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            choice('direction', p.direction, [('shuffle', 'shuffle'), ('forward', 'forward'), ('backward', 'backward')],
                (v) => p.direction = v),
            choice('look', p.look, [('contain', 'contain'), ('cover', 'cover'), ('blurred', 'blurred_background')],
                (v) => p.look = v),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t('duration')),
              subtitle: Text(t('admin.slideshow_duration_description')),
              trailing: SizedBox(
                width: 220,
                child: Row(children: [
                  Expanded(
                    child: Slider(
                      min: 1,
                      max: 60,
                      divisions: 59,
                      value: p.seconds.clamp(1, 60).toDouble(),
                      onChanged: (v) => setState(() => p.seconds = v.round()),
                    ),
                  ),
                  SizedBox(width: 40, child: Text('${p.seconds} s')),
                ]),
              ),
            ),
            toggle('show_progress_bar', p.progressBar, (v) => p.progressBar = v),
            toggle('show_slideshow_transition', p.transition, (v) => p.transition = v),
            toggle('autoplay_slideshow', p.autoplay, (v) => p.autoplay = v),
            toggle('slideshow_repeat', p.repeat, (v) => p.repeat = v, subtitle: 'slideshow_repeat_description'),
            toggle('show_slideshow_metadata_overlay', p.overlay, (v) => p.overlay = v),
            if (p.overlay)
              choice('slideshow_metadata_overlay_mode', p.overlayMode,
                  [('description', 'slideshow_metadata_overlay_mode_description_only'), ('full', 'slideshow_metadata_overlay_mode_full')],
                  (v) => p.overlayMode = v),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, p), child: Text(t('done'))),
      ],
    );
  }
}
