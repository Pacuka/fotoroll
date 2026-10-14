// Memories: the lane on /photos, the /memories page (v3.2+) and the viewer.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../api.dart';
import '../i18n.dart';
import '../settings.dart';
import 'hover_preview.dart';

/// Web: memoryLaneTitle. "x years ago" on the day itself, otherwise the date;
/// birthday memories (v3.3) are "{name}'s birthday".
String memoryTitle(Map<String, dynamic> m, {DateTime? now}) {
  final data = (m['data'] as Map?) ?? const {};
  final today = now ?? DateTime.now();
  if (m['type'] == 'on_this_day' && data['year'] is int) {
    final at = DateTime.tryParse(m['memoryAt'] as String? ?? '')?.toUtc();
    if (at == null || (at.day == today.day && at.month == today.month)) {
      return t('years_ago', {'years': today.year - (data['year'] as int)});
    }
    return DateFormat.yMMMd(i18n.dateLocale).format(at);
  }
  if (m['type'] == 'birthday' && (data['personName'] as String? ?? '').isNotEmpty) {
    return t('birthday_memory_title', {'name': data['personName']});
  }
  return t('unknown');
}

bool _isBirthday(Map<String, dynamic> m) => m['type'] == 'birthday';

/// Birthday memories first, like the web's lane.
List<Map<String, dynamic>> birthdaysFirst(List<Map<String, dynamic>> memories) =>
    [...memories.where(_isBirthday), ...memories.where((m) => !_isBirthday(m))];

void openMemory(BuildContext context, ImmichApi api, List<Map<String, dynamic>> memories, int index) {
  HoverPreview.stopAll();
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => MemoryViewer(api: api, memories: memories, initial: index),
  ));
}

/// Web: MemoryCard (cover photo, heart when saved, cake for birthdays, title).
class MemoryCard extends StatelessWidget {
  final ImmichApi api;
  final Map<String, dynamic> memory;
  final VoidCallback onTap;
  final double fontSize;
  const MemoryCard({super.key, required this.api, required this.memory, required this.onTap, this.fontSize = 14});

  @override
  Widget build(BuildContext context) {
    final first = (memory['assets'] as List).first as Map<String, dynamic>;
    const shadow = [Shadow(blurRadius: 6)];
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Material(
        child: InkWell(
          onTap: onTap,
          child: Stack(fit: StackFit.expand, children: [
            Image(
              image: NetworkImage(api.thumbnailUrl(first['id']), headers: api.headers),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox(),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.center,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
            ),
            if (memory['isSaved'] == true)
              Positioned(
                left: 8,
                top: 8,
                child: Tooltip(
                  message: t('favorite'),
                  child: const Icon(Icons.favorite, color: Colors.white, size: 24, shadows: shadow),
                ),
              ),
            Positioned(
              left: 10,
              bottom: 10,
              right: 10,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (_isBirthday(memory)) ...[
                  Icon(Icons.cake, color: Colors.white, size: fontSize * 1.3, shadows: shadow),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(memoryTitle(memory),
                      style: TextStyle(
                          color: Colors.white, fontSize: fontSize, fontWeight: FontWeight.w600, shadows: shadow)),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Horizontal strip of memory cards shown above the Photos timeline.
class MemoryLane extends StatelessWidget {
  final ImmichApi api;
  final List<Map<String, dynamic>> memories;
  const MemoryLane({super.key, required this.api, required this.memories});

  @override
  Widget build(BuildContext context) {
    final list = birthdaysFirst(memories);
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, i) => SizedBox(
        width: 150,
        child: MemoryCard(api: api, memory: list[i], onTap: () => openMemory(context, api, list, i)),
      ),
    );
  }
}

/// The memories page (web: /memories, v3.2+): every memory newest first, with
/// "Upcoming" ones (generated ahead of time) on top when shown.
class MemoriesScreen extends StatefulWidget {
  final ImmichApi api;
  const MemoriesScreen({super.key, required this.api});

  @override
  State<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends State<MemoriesScreen> {
  static const _pageSize = 50;
  final _memories = <Map<String, dynamic>>[];
  int? _total;
  int _page = 1;
  bool _loading = false;
  Object? _error;

  bool? get _isSaved => settings.memoriesOnlyFavorites ? true : null;
  bool? get _isUpcoming => settings.memoriesShowUpcoming ? null : false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _memories.clear();
    _total = null;
    _page = 1;
    _error = null;
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || (_total != null && _memories.length >= _total!)) return;
    setState(() => _loading = true);
    try {
      final r = await Future.wait([
        widget.api.searchMemories(page: _page, size: _pageSize, isSaved: _isSaved, isUpcoming: _isUpcoming),
        if (_total == null) widget.api.memoryCount(isSaved: _isSaved, isUpcoming: _isUpcoming),
      ]);
      final items = (r[0] as List<Map<String, dynamic>>).where((m) => (m['assets'] as List?)?.isNotEmpty ?? false);
      final seen = {for (final m in _memories) m['id']};
      if (!mounted) return;
      setState(() {
        _memories.addAll(items.where((m) => !seen.contains(m['id'])));
        if (r.length > 1) _total = r[1] as int;
        // Stop when the server has nothing more (empty memories are skipped above).
        if ((r[0] as List).length < _pageSize) _total = _memories.length;
        _page++;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _filters() async {
    var upcoming = settings.memoriesShowUpcoming;
    var favorites = settings.memoriesOnlyFavorites;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(t('filters')),
          content: SizedBox(
            width: 360,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t('memories_show_upcoming')),
                value: upcoming,
                onChanged: (v) => setState(() => upcoming = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t('only_favorites')),
                value: favorites,
                onChanged: (v) => setState(() => favorites = v),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('save'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await settings.update(memoriesShowUpcoming: upcoming, memoriesOnlyFavorites: favorites);
    setState(_reload);
  }

  static bool _upcoming(Map<String, dynamic> m) {
    final at = DateTime.tryParse(m['showAt'] as String? ?? '');
    return at != null && at.isAfter(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Upcoming ones (generated ahead, not shown yet) on top, whatever order the server used.
    final shown = [..._memories.where(_upcoming), ..._memories.where((m) => !_upcoming(m))];
    final upcoming = _memories.where(_upcoming).length;
    final filtered = settings.memoriesShowUpcoming || settings.memoriesOnlyFavorites;
    Widget header(String text) => SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
            child: Text(text, style: theme.textTheme.titleMedium),
          ),
        );
    Widget grid(int from, int to) => SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 420, mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 16 / 9),
          itemCount: to - from,
          itemBuilder: (context, i) => MemoryCard(
            api: widget.api,
            memory: shown[from + i],
            fontSize: 18,
            onTap: () => openMemory(context, widget.api, shown, from + i),
          ),
        );
    return Scaffold(
      appBar: AppBar(
        title: Text(_total == null ? t('memories') : '${t('memories')} ($_total)'),
        actions: [
          IconButton(
            tooltip: t('filters'),
            onPressed: _filters,
            icon: Badge(isLabelVisible: filtered, smallSize: 8, child: const Icon(Icons.tune)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 600) _loadMore();
          return false;
        },
        child: _error != null && _memories.isEmpty
            ? Center(child: Text('${t('error')}: $_error'))
            : _memories.isEmpty
                ? Center(
                    child: _loading ? const CircularProgressIndicator() : Text(t('no_results')),
                  )
                : CustomScrollView(slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.all(16),
                      sliver: SliverMainAxisGroup(slivers: [
                        if (upcoming > 0) ...[
                          header(t('memories_upcoming')),
                          grid(0, upcoming),
                          header(t('memories_current')),
                        ],
                        grid(upcoming, shown.length),
                        if (_loading)
                          const SliverToBoxAdapter(
                            child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
                          ),
                      ]),
                    ),
                  ]),
      ),
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

  /// Web: the person's age on this photo (taken year − birth year) for birthday memories.
  int? get _birthdayAge {
    final born = (_m['data'] as Map?)?['year'] as int?;
    final taken = DateTime.tryParse(_current['localDateTime'] as String? ?? '');
    if (_m['type'] != 'birthday' || born == null || taken == null) return null;
    final age = taken.year - born;
    return age >= 0 ? age : null;
  }

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
      if (!mounted) return;
      setState(() => _m['isSaved'] = !saved);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(!saved ? t('added_to_favorites') : t('removed_from_favorites'))));
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
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(memoryTitle(_m),
                              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                          if (_birthdayAge case final age?)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: const Color(0xFFFFB800), borderRadius: BorderRadius.circular(4)),
                              child: Text(t('birthday_memory_age', {'age': age}),
                                  style: const TextStyle(color: Colors.black, fontSize: 13)),
                            ),
                        ]),
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
