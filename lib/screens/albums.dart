// Albums (web: /albums and /albums/[id]): list with search/filter/sort and
// create; album page with add photos, share, download, edit, order, comments, delete.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../api.dart';
import '../i18n.dart';
import '../sources.dart';
import 'slideshow.dart';
import '../widgets/asset_actions.dart';
import '../widgets/loader.dart';
import '../widgets/shared_link_dialog.dart';
import '../widgets/timeline_view.dart';

enum _Filter { all, owned, shared }

enum _Sort { title, items, modified, created, recent, oldest }

const _sortKeys = {
  _Sort.title: 'sort_title',
  _Sort.items: 'sort_items',
  _Sort.modified: 'sort_modified',
  _Sort.created: 'sort_created',
  _Sort.recent: 'sort_recent',
  _Sort.oldest: 'sort_oldest',
};

class AlbumsScreen extends StatefulWidget {
  final ImmichApi api;
  final bool sharedOnly;
  const AlbumsScreen({super.key, required this.api, this.sharedOnly = false});

  @override
  State<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends State<AlbumsScreen> {
  late Future<(List<Album>, String)> _data = _load();
  String _search = '';
  _Filter _filter = _Filter.all;
  _Sort _sort = _Sort.recent;

  Future<(List<Album>, String)> _load() async =>
      (await widget.api.albums(), (await widget.api.me())['id'] as String);

  void _reload() => setState(() { _data = _load(); });

  Future<void> _create() async {
    final album = await createAlbumDialog(context, widget.api);
    if (album == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AlbumScreen(api: widget.api, album: album, startWithPicker: true),
    ));
    _reload();
  }

  List<Album> _apply(List<Album> all, String me) {
    final list = all.where((a) {
      if (widget.sharedOnly && !a.shared) return false;
      if (_filter == _Filter.owned && a.ownerId != me) return false;
      if (_filter == _Filter.shared && a.ownerId == me) return false;
      return _search.isEmpty || a.name.toLowerCase().contains(_search);
    }).toList();
    DateTime d(String? iso) => DateTime.tryParse(iso ?? '') ?? DateTime(0);
    int cmp(Album a, Album b) => switch (_sort) {
          _Sort.title => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          _Sort.items => b.assetCount.compareTo(a.assetCount),
          _Sort.modified => d(b.raw['updatedAt']).compareTo(d(a.raw['updatedAt'])),
          _Sort.created => d(b.raw['createdAt']).compareTo(d(a.raw['createdAt'])),
          _Sort.recent => (b.endDate ?? DateTime(0)).compareTo(a.endDate ?? DateTime(0)),
          _Sort.oldest => (a.startDate ?? DateTime(9999)).compareTo(b.startDate ?? DateTime(9999)),
        };
    list.sort(cmp);
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Loader<(List<Album>, String)>(
      future: _data,
      onRetry: _reload,
      builder: (data) {
        final (all, me) = data;
        final albums = _apply(all, me);
        final grid = albums.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(widget.sharedOnly ? t('no_shared_albums_message') : t('no_albums_message'),
                      textAlign: TextAlign.center),
                ),
              )
            : GridView.builder(
                shrinkWrap: widget.sharedOnly,
                physics: widget.sharedOnly ? const NeverScrollableScrollPhysics() : null,
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.8,
                ),
                itemCount: albums.length,
                itemBuilder: (context, i) => _AlbumCard(
                  api: widget.api,
                  album: albums[i],
                  me: me,
                  onClosed: _reload,
                ),
              );
        if (widget.sharedOnly) return grid;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SizedBox(
                width: 260,
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: t('search_albums'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
                ),
              ),
              SegmentedButton<_Filter>(
                segments: [
                  ButtonSegment(value: _Filter.all, label: Text(t('all'))),
                  ButtonSegment(value: _Filter.owned, label: Text(t('my_albums'))),
                  ButtonSegment(value: _Filter.shared, label: Text(t('shared_with_me'))),
                ],
                selected: {_filter},
                onSelectionChanged: (s) => setState(() => _filter = s.first),
              ),
              DropdownButton<_Sort>(
                value: _sort,
                items: [
                  for (final s in _Sort.values) DropdownMenuItem(value: s, child: Text(t(_sortKeys[s]!))),
                ],
                onChanged: (v) => setState(() => _sort = v!),
              ),
              FilledButton.icon(
                onPressed: _create,
                icon: const Icon(Icons.add),
                label: Text(t('create_album')),
              ),
            ]),
          ),
          Expanded(child: grid),
        ]);
      },
    );
  }
}

/// Asks for a name (and description) and creates an album with [assetIds].
Future<Album?> createAlbumDialog(BuildContext context, ImmichApi api, {List<String> assetIds = const []}) async {
  final name = TextEditingController();
  final desc = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('create_album')),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, autofocus: true, decoration: InputDecoration(labelText: t('album_name'))),
          TextField(controller: desc, decoration: InputDecoration(labelText: t('description'))),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('create'))),
      ],
    ),
  );
  if (ok != true) return null;
  try {
    var album = await api.createAlbum(name.text.trim().isEmpty ? t('unnamed_album') : name.text.trim(), assetIds);
    if (desc.text.trim().isNotEmpty) album = await api.updateAlbum(album.id, description: desc.text.trim());
    return album;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t('error')}: $e')));
    }
    return null;
  }
}

class _AlbumCard extends StatelessWidget {
  final ImmichApi api;
  final Album album;
  final String me;
  final VoidCallback onClosed;
  const _AlbumCard({required this.api, required this.album, required this.me, required this.onClosed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AlbumScreen(api: api, album: album),
        ));
        onClosed();
      },
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              color: theme.colorScheme.surfaceContainerHighest,
              width: double.infinity,
              child: album.thumbnailAssetId == null
                  ? const Icon(Icons.photo_album_outlined, size: 48)
                  : Image(
                      image: NetworkImage(api.thumbnailUrl(album.thumbnailAssetId!), headers: api.headers),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(album.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
        Text(
          [
            t('items_count', {'count': album.assetCount}),
            if (album.shared) album.ownerId == me ? t('shared_by_you') : t('shared'),
          ].join(' · '),
          style: theme.textTheme.bodySmall,
        ),
      ]),
    );
  }
}

class AlbumScreen extends StatefulWidget {
  final ImmichApi api;
  final Album album;
  /// Open the photo picker right away (after creating an album, like the web).
  final bool startWithPicker;
  const AlbumScreen({super.key, required this.api, required this.album, this.startWithPicker = false});

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  late Album _album = widget.album;
  late Future<TimelineSource> _source = _load();
  String? _me;

  ImmichApi get api => widget.api;

  Future<TimelineSource> _load() =>
      TimelineSource.create(api, TimelineQuery.album(_album.id, order: _album.order));

  @override
  void initState() {
    super.initState();
    _refreshAlbum();
    api.me().then((m) {
      if (mounted) setState(() => _me = m['id']);
    }).catchError((_) {});
    if (widget.startWithPicker) WidgetsBinding.instance.addPostFrameCallback((_) => _addPhotos());
  }

  Future<void> _refreshAlbum() async {
    try {
      final a = await api.album(_album.id);
      if (mounted) setState(() => _album = a);
    } catch (_) {}
  }

  void _reloadAll() {
    _refreshAlbum();
    setState(() { _source = _load(); });
  }

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _guard(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (mounted) _toast('${t('error')}: $e');
    }
  }

  Future<void> _addPhotos() async {
    final picked = await Navigator.of(context).push<List<AssetRef>>(MaterialPageRoute(
      builder: (_) => AssetPickerScreen(api: api, title: t('add_photos'), confirmLabel: t('add')),
    ));
    if (picked == null || picked.isEmpty) return;
    await _guard(() async {
      final n = await api.addToAlbum(_album.id, [for (final a in picked) a.id]);
      _toast(t('linux_added_photos', {'count': n}));
      _reloadAll();
    });
  }

  Future<void> _edit() async {
    final name = TextEditingController(text: _album.name);
    final desc = TextEditingController(text: _album.description);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('edit_album')),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: InputDecoration(labelText: t('album_name'))),
            TextField(controller: desc, maxLines: 3, decoration: InputDecoration(labelText: t('description'))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('save'))),
        ],
      ),
    );
    if (ok != true) return;
    await _guard(() async {
      final a = await api.updateAlbum(_album.id, name: name.text.trim(), description: desc.text.trim());
      if (!mounted) return;
      setState(() => _album = a);
      _toast(t('album_info_updated'));
    });
  }

  Future<void> _setOrder(String order) => _guard(() async {
        final a = await api.updateAlbum(_album.id, order: order);
        if (!mounted) return;
        setState(() {
          _album = a;
          _source = _load();
        });
      });

  Future<void> _toggleActivity() => _guard(() async {
        final a = await api.updateAlbum(_album.id, isActivityEnabled: !_album.isActivityEnabled);
        if (mounted) setState(() => _album = a);
      });

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('delete_album')),
        content: Text('${t('album_delete_confirmation', {'album': _album.name})}\n\n'
            '${t('album_delete_confirmation_description')}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _guard(() async {
      await api.deleteAlbum(_album.id);
      if (!mounted) return;
      _toast(t('linux_album_deleted'));
      Navigator.of(context).pop();
    });
  }

  Future<void> _leave() => _guard(() async {
        await api.removeAlbumUser(_album.id, 'me');
        if (mounted) Navigator.of(context).pop();
      });

  Future<void> _download() => _guard(() async {
        final dir = await downloadsDir();
        await dir.create(recursive: true);
        _toast(t('linux_download_preparing', {'count': _album.assetCount}));
        final files = await api.downloadZip(const [], dir, albumId: _album.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('linux_saved_to', {'files': files.map((f) => p.basename(f.path)).join(', ')})),
          action: SnackBarAction(label: t('linux_open_folder'), onPressed: () => Process.run('xdg-open', [dir.path])),
        ));
      });

  Future<void> _share() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ShareAlbumDialog(api: api, album: _album, onChanged: _refreshAlbum),
    );
    _refreshAlbum();
  }

  @override
  Widget build(BuildContext context) {
    final a = _album;
    final theme = Theme.of(context);
    final owner = _me != null && a.ownerId == _me;
    // Editors may change the title and description too (Immich v3.3, web isAlbumEditor).
    final editor = owner || a.albumUsers.any((u) => u['user']?['id'] == _me && u['role'] == 'editor');
    final fmt = DateFormat.yMMMd(i18n.dateLocale);
    final range = a.startDate == null
        ? null
        : a.endDate == null || fmt.format(a.startDate!) == fmt.format(a.endDate!)
            ? fmt.format(a.startDate!)
            : '${fmt.format(a.startDate!)} – ${fmt.format(a.endDate!)}';
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
              tooltip: t('add_photos'), icon: const Icon(Icons.add_photo_alternate_outlined), onPressed: _addPhotos),
          IconButton(
            tooltip: t('slideshow'),
            icon: const Icon(Icons.slideshow_outlined),
            onPressed: () async {
              final src = await _source;
              if (context.mounted && src.length > 0) await openSlideshow(context, api, src, 0);
            },
          ),
          if (owner) IconButton(tooltip: t('share'), icon: const Icon(Icons.person_add_alt), onPressed: _share),
          IconButton(tooltip: t('download'), icon: const Icon(Icons.download_outlined), onPressed: _download),
          MenuAnchor(
            menuChildren: [
              if (owner) ...[
                MenuItemButton(
                    leadingIcon: const Icon(Icons.edit_outlined), onPressed: _edit, child: Text(t('edit_album'))),
                SubmenuButton(
                  leadingIcon: const Icon(Icons.sort),
                  menuChildren: [
                    CheckboxMenuButton(
                      value: a.order == 'desc',
                      onChanged: (_) => _setOrder('desc'),
                      child: Text(t('newest_first')),
                    ),
                    CheckboxMenuButton(
                      value: a.order == 'asc',
                      onChanged: (_) => _setOrder('asc'),
                      child: Text(t('oldest_first')),
                    ),
                  ],
                  child: Text(t('display_order')),
                ),
                CheckboxMenuButton(
                  value: a.isActivityEnabled,
                  onChanged: (_) => _toggleActivity(),
                  child: Text(t('comments_and_likes')),
                ),
                MenuItemButton(
                  leadingIcon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                  onPressed: _delete,
                  child: Text(t('delete_album')),
                ),
              ] else ...[
                if (editor)
                  MenuItemButton(
                      leadingIcon: const Icon(Icons.edit_outlined), onPressed: _edit, child: Text(t('edit_album'))),
                MenuItemButton(
                    leadingIcon: const Icon(Icons.logout), onPressed: _leave, child: Text(t('leave_album'))),
              ],
            ],
            builder: (context, ctl, _) => IconButton(
              tooltip: t('album_options'),
              icon: const Icon(Icons.more_vert),
              onPressed: () => ctl.isOpen ? ctl.close() : ctl.open(),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            InkWell(
              onTap: editor ? _edit : null,
              child: Text(a.name, style: theme.textTheme.headlineMedium),
            ),
            const SizedBox(height: 4),
            Text(
              [?range, t('items_count', {'count': a.assetCount})].join(' · '),
              style: theme.textTheme.bodyMedium,
            ),
            if (a.albumUsers.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, children: [
                for (final u in a.albumUsers)
                  Tooltip(
                    message: '${u['user']?['name'] ?? ''} · '
                        '${t(u['role'] == 'editor' ? 'role_editor' : 'role_viewer')}',
                    child: CircleAvatar(
                      radius: 14,
                      child: Text(((u['user']?['name'] as String?) ?? '?').characters.first.toUpperCase()),
                    ),
                  ),
              ]),
            ],
            if (a.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(a.description),
            ],
          ]),
        ),
        Expanded(
          child: Loader<TimelineSource>(
            future: _source,
            onRetry: _reloadAll,
            builder: (src) => src.length == 0
                ? Center(
                    child: FilledButton.icon(
                      onPressed: _addPhotos,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(t('add_photos')),
                    ),
                  )
                : TimelineView(api: api, source: src, albumId: a.id),
          ),
        ),
      ]),
    );
  }
}

/// Full timeline in picker mode; returns the selected assets.
class AssetPickerScreen extends StatefulWidget {
  final ImmichApi api;
  final String title;
  final String confirmLabel;
  const AssetPickerScreen({super.key, required this.api, required this.title, required this.confirmLabel});

  @override
  State<AssetPickerScreen> createState() => _AssetPickerScreenState();
}

class _AssetPickerScreenState extends State<AssetPickerScreen> {
  late Future<TimelineSource> _source = TimelineSource.create(widget.api);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Loader<TimelineSource>(
        future: _source,
        onRetry: () => setState(() { _source = TimelineSource.create(widget.api); }),
        builder: (src) => TimelineView(
          api: widget.api,
          source: src,
          onPicked: (assets) => Navigator.of(context).pop(assets),
          pickLabel: widget.confirmLabel,
        ),
      ),
    );
  }
}

/// Share an album with users (editor/viewer) and create a link (web: AlbumShareModal).
class _ShareAlbumDialog extends StatefulWidget {
  final ImmichApi api;
  final Album album;
  final Future<void> Function() onChanged;
  const _ShareAlbumDialog({required this.api, required this.album, required this.onChanged});

  @override
  State<_ShareAlbumDialog> createState() => _ShareAlbumDialogState();
}

class _ShareAlbumDialogState extends State<_ShareAlbumDialog> {
  late Album _album = widget.album;
  late final Future<List<Map<String, dynamic>>> _users = widget.api.users();
  final Map<String, String> _pending = {}; // userId → role to add

  Future<void> _refresh() async {
    await widget.onChanged();
    final a = await widget.api.album(_album.id);
    if (mounted) setState(() => _album = a);
  }

  Future<void> _guard(Future<void> Function() f) async {
    try {
      await f();
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t('error')}: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final members = {for (final u in _album.albumUsers) u['user']?['id'] as String?};
    return AlertDialog(
      title: Text(t('share')),
      content: SizedBox(
        width: 460,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _users,
          builder: (context, snap) {
            if (!snap.hasData) {
              return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
            }
            final candidates =
                snap.data!.where((u) => u['id'] != _album.ownerId && !members.contains(u['id'])).toList();
            Widget roleMenu(String value, ValueChanged<String> onChanged) => DropdownButton<String>(
                  value: value,
                  items: [
                    DropdownMenuItem(value: 'editor', child: Text(t('role_editor'))),
                    DropdownMenuItem(value: 'viewer', child: Text(t('role_viewer'))),
                  ],
                  onChanged: (v) => onChanged(v!),
                );
            return ListView(shrinkWrap: true, children: [
              for (final u in _album.albumUsers)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(u['user']?['name'] ?? ''),
                  subtitle: Text(u['user']?['email'] ?? ''),
                  trailing: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                    roleMenu(u['role'] ?? 'editor',
                        (r) => _guard(() => widget.api.updateAlbumUser(_album.id, u['user']['id'], r))),
                    IconButton(
                      tooltip: t('remove_user'),
                      icon: const Icon(Icons.person_remove_outlined),
                      onPressed: () => _guard(() => widget.api.removeAlbumUser(_album.id, u['user']['id'])),
                    ),
                  ]),
                ),
              if (candidates.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(t('album_share_no_users'), style: theme.textTheme.bodySmall),
                ),
              for (final u in candidates)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _pending.containsKey(u['id']),
                  onChanged: (v) =>
                      setState(() => v == true ? _pending[u['id']] = 'editor' : _pending.remove(u['id'])),
                  title: Text(u['name'] ?? ''),
                  subtitle: Text(u['email'] ?? ''),
                  secondary: _pending.containsKey(u['id'])
                      ? roleMenu(_pending[u['id']]!, (r) => setState(() => _pending[u['id']] = r))
                      : null,
                ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.link),
                title: Text(t('create_link')),
                subtitle: Text(t('album_with_link_access')),
                onTap: () => showSharedLinkDialog(context, widget.api, albumId: _album.id),
              ),
            ]);
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t('linux_close'))),
        FilledButton(
          onPressed: _pending.isEmpty
              ? null
              : () async {
                  final add = Map.of(_pending);
                  _pending.clear();
                  await _guard(() => widget.api.addAlbumUsers(_album.id, add));
                },
          child: Text(t('add')),
        ),
      ],
    );
  }
}
