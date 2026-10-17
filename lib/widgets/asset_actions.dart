// Selection and bulk actions, matching the web client's asset-select control bar:
// favorite, add to album, download, archive, delete — and restore / delete
// permanently in the bin.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;

import '../api.dart';
import '../i18n.dart';
import '../sources.dart';
import 'bulk_edit.dart';
import 'info_panel.dart' show LocationDialog, TagPicker;
import 'shared_link_dialog.dart';
import '../host.dart';

/// Which actions a timeline offers.
enum TimelineMode { normal, archive, trash, locked, readOnly }

enum AssetAction {
  favorite('to_favorite', Icons.favorite_border),
  unfavorite('unfavorite', Icons.favorite),
  share('share', Icons.share_outlined),
  addToAlbum('add_to_album', Icons.library_add_outlined),
  removeFromAlbum('remove_from_album', Icons.playlist_remove),
  setAlbumCover('set_as_album_cover', Icons.image_outlined),
  download('download', Icons.download_outlined),
  archive('to_archive', Icons.archive_outlined),
  unarchive('unarchive', Icons.unarchive_outlined),
  lock('move_to_locked_folder', Icons.lock_outline),
  unlock('remove_from_locked_folder', Icons.lock_open_outlined),
  trash('delete', Icons.delete_outline),
  restore('restore', Icons.restore_from_trash_outlined),
  deleteForever('permanently_delete', Icons.delete_forever_outlined),
  changeDate('change_date', Icons.edit_calendar_outlined),
  changeDescription('change_description', Icons.notes),
  changeLocation('change_location', Icons.edit_location_alt_outlined),
  tag('tag', Icons.sell_outlined),
  stack('stack', Icons.burst_mode_outlined),
  unstack('unstack', Icons.layers_clear_outlined);

  final String labelKey;
  final IconData icon;
  const AssetAction(this.labelKey, this.icon);
  String get label => t(labelKey);
}

List<AssetAction> actionsFor(TimelineMode mode,
    {required bool allFavorite, String? albumId, int count = 0, bool allOwned = true}) {
  final fav = allFavorite ? AssetAction.unfavorite : AssetAction.favorite;
  // A partner's photos (web: !isAllUserOwned): only what doesn't change them.
  if (!allOwned && albumId == null && (mode == TimelineMode.normal || mode == TimelineMode.archive)) {
    return const [AssetAction.share, AssetAction.addToAlbum, AssetAction.download];
  }
  return switch (mode) {
    TimelineMode.normal => [
        AssetAction.share,
        fav,
        AssetAction.addToAlbum,
        if (albumId != null) AssetAction.removeFromAlbum,
        if (albumId != null && count == 1) AssetAction.setAlbumCover,
        AssetAction.download,
        AssetAction.archive,
        AssetAction.lock,
        AssetAction.trash,
      ],
    TimelineMode.archive => [
        AssetAction.share,
        fav,
        AssetAction.addToAlbum,
        AssetAction.download,
        AssetAction.unarchive,
        AssetAction.trash,
      ],
    TimelineMode.trash => [AssetAction.restore, AssetAction.deleteForever],
    TimelineMode.locked => [AssetAction.download, AssetAction.unlock, AssetAction.deleteForever],
    TimelineMode.readOnly => [AssetAction.download],
  };
}

/// The selection bar's menu (web: the "⋮" menu, only when every photo is the user's own).
List<AssetAction> menuActionsFor(TimelineMode mode, List<AssetRef> selected, {required bool allOwned}) =>
    allOwned && (mode == TimelineMode.normal || mode == TimelineMode.archive)
        ? [
            if (selected.length > 1) AssetAction.stack,
            if (selected.isNotEmpty && selected.every((a) => a.stackId != null)) AssetAction.unstack,
            AssetAction.changeDate,
            AssetAction.changeDescription,
            AssetAction.changeLocation,
            AssetAction.tag,
          ]
        : const [];

class AssetSelection extends ChangeNotifier {
  final Map<String, AssetRef> _selected = {};
  int? anchor; // global index of the last click, for shift-range selection

  bool get isEmpty => _selected.isEmpty;
  int get length => _selected.length;
  List<AssetRef> get assets => _selected.values.toList();
  bool contains(String id) => _selected.containsKey(id);

  void toggle(AssetRef a) {
    if (_selected.remove(a.id) == null) _selected[a.id] = a;
    notifyListeners();
  }

  void setAll(Iterable<AssetRef> list, bool selected) {
    for (final a in list) {
      if (selected) {
        _selected[a.id] = a;
      } else {
        _selected.remove(a.id);
      }
    }
    notifyListeners();
  }

  void clear() {
    _selected.clear();
    anchor = null;
    notifyListeners();
  }
}

Future<Directory> downloadsDir() async {
  try {
    final r = await runHost('xdg-user-dir', ['DOWNLOAD']);
    final path = (r.stdout as String).trim();
    if (r.exitCode == 0 && path.isNotEmpty) return Directory(path);
  } catch (_) {}
  return Directory(p.join(Platform.environment['HOME'] ?? '.', 'Downloads'));
}

/// An OK / Cancel question; true when confirmed.
Future<bool> confirmDialog(BuildContext context, String title, String body, String ok) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Runs [action] on [assets], updates [source] in place and reports the result.
/// Returns true if the action went through.
Future<bool> performAction(
  BuildContext context,
  ImmichApi api,
  AssetSource source,
  AssetAction action,
  List<AssetRef> assets, {
  String? albumId,
}) async {
  if (assets.isEmpty) return false;
  final messenger = ScaffoldMessenger.of(context);
  final ids = [for (final a in assets) a.id];
  final idSet = ids.toSet();
  final n = ids.length;
  void say(String msg) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(msg)));
  }

  try {
    switch (action) {
      case AssetAction.favorite:
      case AssetAction.unfavorite:
        final v = action == AssetAction.favorite;
        await api.updateAssets(ids, isFavorite: v);
        source.updateAssets(idSet, (a) => a.copyWith(isFavorite: v));
        say(v ? t('added_to_favorites_count', {'count': n}) : t('removed_from_favorites_count', {'count': n}));
      case AssetAction.archive:
        await api.updateAssets(ids, visibility: 'archive');
        source.removeAssets(idSet);
        say(t('archived_count', {'count': n}));
      case AssetAction.unarchive:
        await api.updateAssets(ids, visibility: 'timeline');
        source.removeAssets(idSet);
        say(t('unarchived_count', {'count': n}));
      case AssetAction.lock:
        await api.updateAssets(ids, visibility: 'locked');
        source.removeAssets(idSet);
        say(t('linux_locked_count', {'count': n}));
      case AssetAction.unlock:
        await api.updateAssets(ids, visibility: 'timeline');
        source.removeAssets(idSet);
        say(t('linux_unlocked_count', {'count': n}));
      case AssetAction.trash:
        await api.deleteAssets(ids);
        source.removeAssets(idSet);
        say(t('assets_moved_to_trash_count', {'count': n}));
      case AssetAction.restore:
        await api.restoreAssets(ids);
        source.removeAssets(idSet);
        say(t('assets_restored_count', {'count': n}));
      case AssetAction.deleteForever:
        if (!await confirmDialog(context, t('permanently_delete'),
            t('permanently_delete_assets_prompt', {'count': n}), t('delete'))) {
          return false;
        }
        await api.deleteAssets(ids, force: true);
        source.removeAssets(idSet);
        say(t('permanently_deleted_assets_count', {'count': n}));
      case AssetAction.setAlbumCover:
        await api.updateAlbum(albumId!, thumbnailAssetId: ids.first);
        say(t('album_cover_updated'));
      case AssetAction.removeFromAlbum:
        await api.removeFromAlbum(albumId!, ids);
        source.removeAssets(idSet);
        say(t('linux_removed_from_album_count', {'count': n}));
      case AssetAction.share:
        // Web: "Create link to share" (an individual shared link for the picked photos).
        if (!context.mounted) return false;
        return await showSharedLinkDialog(context, api, assetIds: ids) != null;
      case AssetAction.changeDate:
        if (!context.mounted) return false;
        final change = await showChangeDateDialog(context, initial: assets.first.localDate);
        if (change == null) return false;
        await api.updateAssets(ids, dateTimeOriginal: change.iso, dateTimeRelative: change.minutes);
        libraryChanged.value++; // the photos move to their new day
        say(t('linux_updated_count', {'count': n}));
      case AssetAction.changeDescription:
        if (!context.mounted) return false;
        final text = await showChangeDescriptionDialog(context);
        if (text == null) return false;
        await api.updateAssets(ids, description: text);
        say(t('linux_updated_count', {'count': n}));
      case AssetAction.changeLocation:
        if (!context.mounted) return false;
        final point = await showDialog<LatLng>(context: context, builder: (_) => const LocationDialog());
        if (point == null) return false;
        await api.updateAssets(ids, latitude: point.latitude, longitude: point.longitude);
        say(t('linux_updated_count', {'count': n}));
      case AssetAction.tag:
        if (!context.mounted) return false;
        final name = await showDialog<String>(context: context, builder: (_) => TagPicker(api: api));
        if (name == null || name.trim().isEmpty) return false;
        final tags = await api.upsertTags([name.trim()]);
        await api.tagAssets([for (final t in tags) t['id'] as String], ids);
        say(t('tagged_assets', {'count': n}));
      case AssetAction.stack:
        // Web: the first selected photo becomes the primary one.
        await api.createStack(ids);
        libraryChanged.value++; // only the primary photo stays in the timeline
        say(t('stacked_assets_count', {'count': n}));
      case AssetAction.unstack:
        await api.deleteStacks({for (final a in assets) ?a.stackId}.toList());
        libraryChanged.value++;
        say(t('unstacked_assets_count', {'count': assets.fold<int>(0, (s, a) => s + (a.stackCount ?? 1))}));
      case AssetAction.addToAlbum:
        if (!context.mounted) return false;
        final msg = await showDialog<String>(
          context: context,
          builder: (_) => _AddToAlbumDialog(api: api, ids: ids),
        );
        if (msg == null) return false;
        say(msg);
      case AssetAction.download:
        final dir = await downloadsDir();
        await dir.create(recursive: true);
        say(t('linux_download_preparing', {'count': n}));
        final files = await api.downloadZip(ids, dir);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(
          content: Text(t('linux_saved_to', {'files': files.map((f) => p.basename(f.path)).join(', ')})),
          action: SnackBarAction(
            label: t('linux_open_folder'),
            onPressed: () => runHost('xdg-open', [dir.path]),
          ),
        ));
    }
    return true;
  } catch (e) {
    say('${t('error')}: $e');
    return false;
  }
}

class _AddToAlbumDialog extends StatefulWidget {
  final ImmichApi api;
  final List<String> ids;
  const _AddToAlbumDialog({required this.api, required this.ids});

  @override
  State<_AddToAlbumDialog> createState() => _AddToAlbumDialogState();
}

class _AddToAlbumDialogState extends State<_AddToAlbumDialog> {
  late final Future<List<Album>> _albums = widget.api.albums();
  final _name = TextEditingController();
  String _filter = '';
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String> Function() f) async {
    setState(() => _busy = true);
    try {
      final msg = await f();
      if (mounted) Navigator.pop(context, msg);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t('error')}: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = widget.api;
    return AlertDialog(
      title: Text(t('add_to_album')),
      content: SizedBox(
        width: 420,
        height: 460,
        child: Column(children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: t('new_album'),
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _busy || _name.text.trim().isEmpty
                  ? null
                  : () => _run(() async {
                        final a = await api.createAlbum(_name.text.trim(), widget.ids);
                        return t('linux_album_created', {'name': a.name, 'count': widget.ids.length});
                      }),
              child: Text(t('create')),
            ),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: FutureBuilder<List<Album>>(
              future: _albums,
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final list = snap.data!
                    .where((a) => _filter.isEmpty || a.name.toLowerCase().contains(_filter))
                    .toList();
                if (list.isEmpty) return Center(child: Text(t('no_albums_found')));
                return ListView(children: [
                  for (final a in list)
                    ListTile(
                      enabled: !_busy,
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: a.thumbnailAssetId == null
                              ? const Icon(Icons.photo_album_outlined)
                              : Image(
                                  image: NetworkImage(api.thumbnailUrl(a.thumbnailAssetId!),
                                      headers: api.headers),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const Icon(Icons.photo_album_outlined),
                                ),
                        ),
                      ),
                      title: Text(a.name),
                      subtitle: Text(t('items_count', {'count': a.assetCount})),
                      onTap: () => _run(() async {
                        final added = await api.addToAlbum(a.id, widget.ids);
                        final skipped = widget.ids.length - added;
                        return t('linux_added_to_album', {'count': added, 'album': a.name}) +
                            (skipped > 0
                                ? ' (${t('linux_already_in_album', {'count': skipped})})'
                                : '');
                      }),
                    ),
                ]);
              },
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t('cancel'))),
      ],
    );
  }
}

/// Bar shown over the timeline while something is selected (web: control bar).
class SelectionBar extends StatelessWidget {
  final AssetSelection selection;
  final List<AssetAction> actions;
  /// Behind the "⋮" button.
  final List<AssetAction> menu;
  final void Function(AssetAction) onAction;
  final Widget? trailing;

  const SelectionBar({
    super.key,
    required this.selection,
    required this.actions,
    this.menu = const [],
    required this.onAction,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 3,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(children: [
          IconButton(
            tooltip: t('linux_clear_selection'),
            icon: const Icon(Icons.close),
            onPressed: selection.clear,
          ),
          const SizedBox(width: 8),
          Text(t('selected_count', {'count': selection.length}), style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          for (final a in actions)
            IconButton(
              tooltip: a.label,
              icon: Icon(a.icon,
                  color: a == AssetAction.deleteForever || a == AssetAction.trash
                      ? scheme.error
                      : null),
              onPressed: () => onAction(a),
            ),
          if (menu.isNotEmpty)
            MenuAnchor(
              menuChildren: [
                for (final a in menu)
                  MenuItemButton(leadingIcon: Icon(a.icon), onPressed: () => onAction(a), child: Text(a.label)),
              ],
              builder: (context, ctl, _) => IconButton(
                tooltip: t('menu'),
                icon: const Icon(Icons.more_vert),
                onPressed: () => ctl.isOpen ? ctl.close() : ctl.open(),
              ),
            ),
          ?trailing,
        ]),
      ),
    );
  }
}
