// Web-style timeline: justified rows, day headers, and a year scrubber on the right.
// Every list item has a known height, so the scrubber can jump precisely and
// only the visible rows are built (and their thumbnails fetched).
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../api.dart';
import '../i18n.dart';
import '../screens/viewer.dart';
import '../sources.dart';
import 'asset_actions.dart';
import 'hover_preview.dart';
import 'justified.dart';

const _rowGap = 4.0;
const _dayHeaderHeight = 52.0;
const _targetRowHeight = 235.0;

sealed class _Item {
  final int bucket;
  final double extent;
  const _Item(this.bucket, this.extent);
}

class _Placeholder extends _Item {
  const _Placeholder(super.bucket, super.extent);
}

class _DayHeader extends _Item {
  final String title;
  final List<AssetRef> assets;
  const _DayHeader(int bucket, this.title, this.assets) : super(bucket, _dayHeaderHeight);
}

class _RowItem extends _Item {
  final List<AssetRef> assets;
  final List<double> widths;
  final double height;
  final int firstIndex; // global index of assets[0]
  _RowItem(int bucket, this.assets, this.widths, this.height, this.firstIndex)
      : super(bucket, height + _rowGap);
}

String formatDuration(int ms) {
  final d = Duration(milliseconds: ms);
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (d.inHours > 0) {
    return '${d.inHours}:${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:$s';
  }
  return '${d.inMinutes}:$s';
}

class TimelineView extends StatefulWidget {
  final ImmichApi api;
  final AssetSource source;
  final String emptyText;
  final TimelineMode mode;
  final String? albumId; // enables "remove from album" and "set as album cover"
  /// Picker mode (e.g. "add photos to album"): taps select, and the bar shows one
  /// confirm button labelled [pickLabel] that returns the selection.
  final void Function(List<AssetRef>)? onPicked;
  final String? pickLabel;
  /// Scrolls with the timeline above the first day (e.g. the memory lane).
  final Widget? header;
  final double headerExtent;

  const TimelineView({
    super.key,
    required this.api,
    required this.source,
    this.emptyText = '',
    this.mode = TimelineMode.normal,
    this.albumId,
    this.onPicked,
    this.pickLabel,
    this.header,
    this.headerExtent = 0,
  });

  @override
  State<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends State<TimelineView> {
  final _scroll = ScrollController();
  final _selection = AssetSelection();
  final _focus = FocusNode();
  List<_Item> _items = const [];
  List<double> _bucketOffsets = const [];
  double _total = 0;
  double _width = -1;
  bool _dirty = true;

  @override
  void initState() {
    super.initState();
    widget.source.addListener(_onSource);
    _selection.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(TimelineView old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) {
      old.source.removeListener(_onSource);
      widget.source.addListener(_onSource);
      _dirty = true;
    }
    // The memory lane arrives after the timeline; every offset shifts by its height.
    if ((old.header == null) != (widget.header == null) || old.headerExtent != widget.headerExtent) {
      _dirty = true;
    }
  }

  @override
  void dispose() {
    widget.source.removeListener(_onSource);
    _scroll.dispose();
    _selection.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onSource() => setState(() => _dirty = true);

  double _estimate(int count, double width) {
    final perRow = math.max(1, (width / (_targetRowHeight * 1.1)).floor());
    final rows = (count / perRow).ceil();
    final days = widget.source.groupByDay ? math.min(count, (count / 8).ceil() + 1) : 0;
    return rows * (_targetRowHeight + _rowGap) + days * _dayHeaderHeight;
  }

  void _relayout(double width) {
    final src = widget.source;
    final items = <_Item>[];
    final offsets = <double>[];
    // The header sits before the first bucket, so offsets start after it.
    var total = widget.header != null ? widget.headerExtent : 0.0;
    final now = DateTime.now();
    for (var b = 0; b < src.bucketCount; b++) {
      offsets.add(total);
      final assets = src.bucketAssets(b, load: false);
      if (assets == null) {
        final item = _Placeholder(b, _estimate(src.bucketSize(b), width));
        items.add(item);
        total += item.extent;
        continue;
      }
      final starts = src.groupByDay ? dayRuns([for (final a in assets) a.localDate]) : [0];
      for (var g = 0; g < starts.length; g++) {
        final from = starts[g];
        final to = g + 1 < starts.length ? starts[g + 1] : assets.length;
        if (from >= to) continue;
        final date = assets[from].localDate;
        final group = assets.sublist(from, to);
        if (src.groupByDay && date != null) {
          final h = _DayHeader(b, dayTitle(date, now), group);
          items.add(h);
          total += h.extent;
        }
        for (final r in justify([for (final a in group) a.ratio], width,
            targetHeight: _targetRowHeight, gap: _rowGap)) {
          final row = _RowItem(b, group.sublist(r.start, r.start + r.widths.length), r.widths,
              r.height, src.bucketStart(b) + from + r.start);
          items.add(row);
          total += row.extent;
        }
      }
    }
    _items = items;
    _bucketOffsets = offsets;
    _total = total;
    _width = width;
    _dirty = false;
  }

  void _open(int index) {
    HoverPreview.stopAll();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ViewerScreen(
        api: widget.api,
        source: widget.source,
        initialIndex: index,
        mode: widget.mode,
        albumId: widget.albumId,
      ),
    ));
  }

  void _tap(AssetRef a, int index) {
    if (_selection.isEmpty && widget.onPicked == null) {
      _open(index);
    } else {
      _select(a, index);
    }
  }

  void _select(AssetRef a, int index) {
    final anchor = _selection.anchor;
    if (anchor != null && HardwareKeyboard.instance.isShiftPressed) {
      final lo = anchor < index ? anchor : index;
      final hi = anchor < index ? index : anchor;
      _selection.setAll([
        for (var i = lo; i <= hi; i++) ?widget.source.at(i),
      ], true);
    } else {
      _selection.toggle(a);
    }
    _selection.anchor = index;
    _focus.requestFocus();
  }

  /// Like the web, loads every month first so the selection really is "all".
  Future<void> _selectAll() async {
    final src = widget.source;
    final missing = [
      for (var b = 0; b < src.bucketCount; b++)
        if (src.bucketAssets(b, load: false) == null) b,
    ];
    for (var i = 0; i < missing.length; i += 8) {
      await Future.wait(missing.skip(i).take(8).map((b) => src.load(src.bucketStart(b))));
      if (!mounted) return;
    }
    final all = <AssetRef>[];
    for (var b = 0; b < src.bucketCount; b++) {
      all.addAll(src.bucketAssets(b, load: false) ?? const []);
    }
    _selection.setAll(all, true);
  }

  Future<void> _run(AssetAction action) async {
    final assets = _selection.assets;
    final ok = await performAction(context, widget.api, widget.source, action, assets,
        albumId: widget.albumId);
    // Favorite changes keep the selection (like the web); everything else clears it.
    if (ok && action != AssetAction.favorite && action != AssetAction.unfavorite) {
      _selection.clear();
    } else if (ok) {
      final fav = action == AssetAction.favorite;
      _selection.setAll(assets.map((a) => a.copyWith(isFavorite: fav)), true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final showScrubber = widget.source.bucketCount > 1 && widget.source.bucketLabel(0) != null;
      final listWidth = c.maxWidth - (showScrubber ? 64 : 0) - 16;
      if (_dirty || listWidth != _width) _relayout(listWidth);
      if (widget.source.length == 0) {
        return Center(
            child: Text(widget.emptyText.isEmpty ? t('no_assets_to_show') : widget.emptyText));
      }

      final list = CustomScrollView(
        controller: _scroll,
        slivers: [
          if (widget.header != null)
            SliverToBoxAdapter(child: SizedBox(height: widget.headerExtent, child: widget.header)),
          SliverPadding(
            padding: const EdgeInsets.only(left: 16, bottom: 24),
            sliver: SliverVariedExtentList.builder(
              itemCount: _items.length,
              itemExtentBuilder: (i, _) => i < _items.length ? _items[i].extent : 0,
              itemBuilder: (context, i) {
                if (i >= _items.length) return null;
                if (i >= _items.length - 3) {
                  WidgetsBinding.instance.addPostFrameCallback((_) => widget.source.onNearEnd());
                }
                return switch (_items[i]) {
                  _Placeholder p => _buildPlaceholder(p),
                  _DayHeader h => _DayHeaderView(header: h, selection: _selection),
                  _RowItem r => _buildRow(r),
                };
              },
            ),
          ),
        ],
      );
      final body = !showScrubber ? list : Row(children: [
        Expanded(child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: list,
        )),
        SizedBox(
          width: 64,
          child: _Scrubber(
            controller: _scroll,
            source: widget.source,
            bucketOffsets: _bucketOffsets,
            total: _total,
          ),
        ),
      ]);
      final selected = _selection.assets;
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _selection.clear,
          const SingleActivator(LogicalKeyboardKey.keyA, control: true): _selectAll,
          if (widget.mode == TimelineMode.normal || widget.mode == TimelineMode.archive)
            const SingleActivator(LogicalKeyboardKey.delete): () {
              if (!_selection.isEmpty) _run(AssetAction.trash);
            },
        },
        child: Focus(
          focusNode: _focus,
          autofocus: true,
          child: Stack(children: [
            Positioned.fill(child: body),
            if (!_selection.isEmpty)
              Positioned(
                left: 16,
                right: showScrubber ? 72 : 16,
                top: 8,
                child: SelectionBar(
                  selection: _selection,
                  actions: widget.onPicked != null
                      ? const []
                      : actionsFor(widget.mode,
                          allFavorite: selected.every((a) => a.isFavorite),
                          albumId: widget.albumId,
                          count: selected.length),
                  onAction: _run,
                  trailing: widget.onPicked == null
                      ? null
                      : FilledButton(
                          onPressed: () => widget.onPicked!(selected),
                          child: Text(widget.pickLabel ?? 'OK'),
                        ),
                ),
              ),
          ]),
        ),
      );
    });
  }

  Widget _buildPlaceholder(_Placeholder p) {
    widget.source.bucketAssets(p.bucket); // starts loading
    final color = Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4);
    return Padding(
      padding: const EdgeInsets.only(top: _dayHeaderHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      ),
    );
  }

  Widget _buildRow(_RowItem r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: _rowGap),
      child: Row(children: [
        for (var k = 0; k < r.assets.length; k++) ...[
          if (k > 0) const SizedBox(width: _rowGap),
          SizedBox(
            width: r.widths[k],
            height: r.height,
            child: _Tile(
              api: widget.api,
              asset: r.assets[k],
              selected: _selection.contains(r.assets[k].id),
              selecting: !_selection.isEmpty,
              onTap: () => _tap(r.assets[k], r.firstIndex + k),
              onSelect: () => _select(r.assets[k], r.firstIndex + k),
            ),
          ),
        ],
      ]),
    );
  }
}

class _Tile extends StatefulWidget {
  final ImmichApi api;
  final AssetRef asset;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onSelect;
  const _Tile({
    required this.api,
    required this.asset,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onSelect,
  });

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  bool _hover = false;
  // Muted hover preview for videos, like the web's video thumbnails.
  Timer? _previewTimer;

  void _enter() {
    setState(() => _hover = true);
    if (widget.asset.isImage) return;
    _previewTimer?.cancel();
    _previewTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted && _hover) HoverPreview.play(widget.api, widget.asset.id);
    });
  }

  void _exit() {
    _previewTimer?.cancel();
    if (!widget.asset.isImage) HoverPreview.stop(widget.asset.id);
    if (mounted) setState(() => _hover = false);
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    if (!widget.asset.isImage) HoverPreview.stop(widget.asset.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.asset;
    const shadow = [Shadow(blurRadius: 6, color: Colors.black54)];
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _enter(),
      onExit: (_) => _exit(),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Stack(fit: StackFit.expand, children: [
          ColoredBox(
            color: widget.selected
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          // Selected tiles shrink a little with rounded corners, like the web.
          AnimatedPadding(
            duration: const Duration(milliseconds: 120),
            padding: EdgeInsets.all(widget.selected ? 12 : 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.selected ? 10 : 0),
              child: Image(
                image: NetworkImage(widget.api.thumbnailUrl(a.id), headers: widget.api.headers),
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
          if (!a.isImage && !widget.selected)
            ValueListenableBuilder<String?>(
              valueListenable: HoverPreview.showing,
              builder: (context, id, _) => id != a.id
                  ? const SizedBox.shrink()
                  : IgnorePointer(
                      child: Video(
                        controller: HoverPreview.controller,
                        controls: NoVideoControls,
                        fit: BoxFit.cover,
                        fill: Colors.transparent,
                      ),
                    ),
            ),
          if (_hover && !widget.selected)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.center,
                  colors: [Colors.black45, Colors.transparent],
                ),
              ),
            ),
          if (!a.isImage)
            Positioned(
              right: 8,
              top: 6,
              child: Row(children: [
                if (a.durationMs != null)
                  Text(formatDuration(a.durationMs!),
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600, shadows: shadow)),
                const SizedBox(width: 4),
                const Icon(Icons.play_circle_outline, color: Colors.white, size: 22, shadows: shadow),
              ]),
            ),
          if (a.isPanorama)
            const Positioned(
              right: 8,
              top: 6,
              child: Icon(Icons.threesixty, color: Colors.white, size: 22, shadows: shadow),
            ),
          if (a.isFavorite)
            const Positioned(
              left: 8,
              bottom: 6,
              child: Icon(Icons.favorite, color: Colors.white, size: 20, shadows: shadow),
            ),
          if (_hover || widget.selecting || widget.selected)
            Positioned(
              left: 4,
              top: 4,
              child: IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: widget.selected ? t('unselect_all') : t('select'),
                onPressed: widget.onSelect,
                icon: Icon(
                  widget.selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: widget.selected ? Theme.of(context).colorScheme.primary : Colors.white,
                  shadows: shadow,
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Year labels along the right edge; click or drag to jump, hover to see the month.
class _Scrubber extends StatefulWidget {
  final ScrollController controller;
  final AssetSource source;
  final List<double> bucketOffsets;
  final double total;

  const _Scrubber({
    required this.controller,
    required this.source,
    required this.bucketOffsets,
    required this.total,
  });

  @override
  State<_Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<_Scrubber> {
  double? _hoverY;

  int _bucketAt(double offset) {
    final o = widget.bucketOffsets;
    var lo = 0, hi = o.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (o[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  void _jump(double y, double height) {
    if (!widget.controller.hasClients || widget.total <= 0) return;
    final pos = widget.controller.position;
    final target = (y / height).clamp(0.0, 1.0) * widget.total;
    pos.jumpTo(target.clamp(0.0, pos.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, c) {
      final h = c.maxHeight;
      final total = widget.total <= 0 ? 1.0 : widget.total;
      final src = widget.source;

      // Year labels where a new year begins; skip ones that would overlap.
      final labels = <Widget>[];
      double lastY = -100;
      for (var b = 0; b < src.bucketCount; b++) {
        final y = widget.bucketOffsets[b] / total * h;
        final year = src.bucketYear(b);
        final isNewYear = b == 0 || src.bucketYear(b - 1) != year;
        if (isNewYear && year != null && y - lastY > 22 && y < h - 16) {
          labels.add(Positioned(
            top: y,
            right: 10,
            child: Text('$year', style: theme.textTheme.labelSmall),
          ));
          lastY = y;
        } else if (y - lastY > 8) {
          labels.add(Positioned(
            top: y + 6,
            right: 14,
            child: Container(
              width: 3,
              height: 3,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
            ),
          ));
        }
      }

      return MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        onHover: (e) => setState(() => _hoverY = e.localPosition.dy),
        onExit: (_) => setState(() => _hoverY = null),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _jump(d.localPosition.dy, h),
          onVerticalDragUpdate: (d) {
            setState(() => _hoverY = d.localPosition.dy);
            _jump(d.localPosition.dy, h);
          },
          child: Stack(clipBehavior: Clip.none, children: [
            ...labels,
            // Current position marker.
            ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) {
                if (!widget.controller.hasClients) return const SizedBox();
                final y = (widget.controller.offset / total * h).clamp(0.0, h - 2);
                return Positioned(
                  top: y,
                  right: 0,
                  child: Container(width: 40, height: 2, color: theme.colorScheme.primary),
                );
              },
            ),
            if (_hoverY != null)
              Positioned(
                top: (_hoverY! - 14).clamp(0.0, h - 28),
                right: 4,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.inverseSurface,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      src.bucketLabel(_bucketAt(_hoverY! / h * total)) ?? '',
                      style: TextStyle(color: theme.colorScheme.onInverseSurface, fontSize: 12),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      );
    });
  }
}

class _DayHeaderView extends StatefulWidget {
  final _DayHeader header;
  final AssetSelection selection;
  const _DayHeaderView({required this.header, required this.selection});

  @override
  State<_DayHeaderView> createState() => _DayHeaderViewState();
}

class _DayHeaderViewState extends State<_DayHeaderView> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final sel = widget.selection;
    final all = widget.header.assets.every((a) => sel.contains(a.id));
    final show = _hover || !sel.isEmpty;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Text(widget.header.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(width: 4),
            Opacity(
              opacity: show ? 1 : 0,
              child: IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: all ? t('linux_deselect_day') : t('linux_select_day'),
                onPressed: show ? () => sel.setAll(widget.header.assets, !all) : null,
                icon: Icon(all ? Icons.check_circle : Icons.radio_button_unchecked, size: 20),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
