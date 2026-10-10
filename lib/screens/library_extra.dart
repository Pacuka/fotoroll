// Tags, Folders and Shared links pages (web: /tags, /folders, /shared-links).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../i18n.dart';
import '../sources.dart';
import '../widgets/loader.dart';
import '../widgets/shared_link_dialog.dart';
import '../widgets/timeline_view.dart';

/// A path tree ("a/b/c") rendered with expandable rows; [onSelect] gets the full path.
class _PathTree extends StatefulWidget {
  final List<String> paths;
  final String? selected;
  final ValueChanged<String> onSelect;
  final IconData icon;
  const _PathTree({required this.paths, required this.selected, required this.onSelect, required this.icon});

  @override
  State<_PathTree> createState() => _PathTreeState();
}

class _PathTreeState extends State<_PathTree> {
  final _open = <String>{};

  @override
  Widget build(BuildContext context) {
    // children[parent] = sorted child paths; '' is the root.
    final children = <String, Set<String>>{};
    for (final full in widget.paths) {
      final parts = full.split('/').where((p) => p.isNotEmpty).toList();
      var parent = full.startsWith('/') ? '/' : '';
      for (var i = 0; i < parts.length; i++) {
        final node = parent == '' ? parts[i] : (parent == '/' ? '/${parts[i]}' : '$parent/${parts[i]}');
        children.putIfAbsent(parent, () => {}).add(node);
        parent = node;
      }
    }
    final rows = <Widget>[];
    void walk(String parent, int depth) {
      final kids = (children[parent]?.toList() ?? [])..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      for (final k in kids) {
        final hasKids = children.containsKey(k);
        final open = _open.contains(k);
        final selected = k == widget.selected;
        rows.add(ListTile(
          dense: true,
          selected: selected,
          contentPadding: EdgeInsets.only(left: 8.0 + depth * 16, right: 8),
          leading: hasKids
              ? IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(open ? Icons.expand_more : Icons.chevron_right),
                  onPressed: () => setState(() => open ? _open.remove(k) : _open.add(k)),
                )
              : const SizedBox(width: 40),
          title: Row(children: [
            Icon(widget.icon, size: 18),
            const SizedBox(width: 6),
            Flexible(child: Text(k.split('/').last, overflow: TextOverflow.ellipsis)),
          ]),
          onTap: () {
            setState(() => _open.add(k));
            widget.onSelect(k);
          },
        ));
        if (hasKids && open) walk(k, depth + 1);
      }
    }

    walk(children.containsKey('') ? '' : '/', 0);
    return ListView(children: rows);
  }
}

class TagsScreen extends StatefulWidget {
  final ImmichApi api;
  const TagsScreen({super.key, required this.api});

  @override
  State<TagsScreen> createState() => _TagsScreenState();
}

class _TagsScreenState extends State<TagsScreen> {
  late Future<List<Map<String, dynamic>>> _tags = widget.api.tags();
  Map<String, dynamic>? _selected;
  Future<TimelineSource>? _source;

  void _reload() => setState(() => _tags = widget.api.tags());

  void _select(List<Map<String, dynamic>> tags, String value) {
    final tag = tags.firstWhere((t) => t['value'] == value, orElse: () => {});
    if (tag.isEmpty) return;
    setState(() {
      _selected = tag;
      _source = TimelineSource.create(widget.api, TimelineQuery(tagId: tag['id'], visibility: null));
    });
  }

  Future<void> _create() async {
    final ctl = TextEditingController(text: _selected != null ? '${_selected!['value']}/' : '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('create_tag')),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: InputDecoration(labelText: t('name'), hintText: t('linux_new_tag_hint')),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: Text(t('create'))),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      await widget.api.upsertTags([name.trim()]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('tag_created', {'tag': name.trim()}))));
      }
      _reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t('error')}: $e')));
    }
  }

  Future<void> _delete() async {
    final tag = _selected;
    if (tag == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('delete_tag')),
        content: Text(t('delete_tag_confirmation_prompt', {'tagName': tag['value']})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('delete'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.deleteTag(tag['id']);
      setState(() {
        _selected = null;
        _source = null;
      });
      _reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t('error')}: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Loader<List<Map<String, dynamic>>>(
      future: _tags,
      onRetry: _reload,
      builder: (tags) => Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 260,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                      onPressed: _create, icon: const Icon(Icons.add), label: Text(t('create_tag'))),
                ),
                if (_selected != null)
                  IconButton(tooltip: t('delete_tag'), icon: const Icon(Icons.delete_outline), onPressed: _delete),
              ]),
            ),
            Expanded(
              child: _PathTree(
                paths: [for (final t in tags) t['value'] as String],
                selected: _selected?['value'],
                icon: Icons.sell_outlined,
                onSelect: (v) => _select(tags, v),
              ),
            ),
          ]),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _source == null
              ? Center(child: Text(tags.isEmpty ? t('no_results') : t('tags')))
              : Loader<TimelineSource>(
                  key: ValueKey(_selected?['id']),
                  future: _source!,
                  onRetry: () => _select(tags, _selected!['value']),
                  builder: (src) => TimelineView(api: widget.api, source: src),
                ),
        ),
      ]),
    );
  }
}

class FoldersScreen extends StatefulWidget {
  final ImmichApi api;
  const FoldersScreen({super.key, required this.api});

  @override
  State<FoldersScreen> createState() => _FoldersScreenState();
}

class _FoldersScreenState extends State<FoldersScreen> {
  late Future<List<String>> _paths = widget.api.folderPaths();
  String? _selected;
  SearchSource? _source;

  @override
  void dispose() {
    _source?.dispose();
    super.dispose();
  }

  void _open(String path) {
    final old = _source;
    final api = widget.api;
    setState(() {
      _selected = path;
      _source = SearchSource((page) async =>
          SearchPage(page == 1 ? await api.folderAssets(path) : const [], null))
        ..loadMore();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
  }

  @override
  Widget build(BuildContext context) {
    return Loader<List<String>>(
      future: _paths,
      onRetry: () => setState(() => _paths = widget.api.folderPaths()),
      builder: (paths) {
        final sub = _selected == null
            ? <String>[]
            : ({
                for (final p in paths)
                  if (p.startsWith('$_selected/'))
                    '$_selected/${p.substring(_selected!.length + 1).split('/').first}',
              }.toList()
              ..sort());
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 300,
            child: _PathTree(paths: paths, selected: _selected, icon: Icons.folder_outlined, onSelect: _open),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _selected == null
                ? Center(child: Text(t('folders')))
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(_selected!, style: Theme.of(context).textTheme.titleMedium),
                    ),
                    if (sub.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final s in sub)
                            ActionChip(
                              avatar: const Icon(Icons.folder_outlined, size: 18),
                              label: Text(s.split('/').last),
                              onPressed: () => _open(s),
                            ),
                        ]),
                      ),
                    Expanded(
                      child: ListenableBuilder(
                        listenable: _source!,
                        builder: (context, _) => _source!.length == 0 && _source!.hasMore
                            ? const Center(child: CircularProgressIndicator())
                            : TimelineView(key: ObjectKey(_source), api: widget.api, source: _source!),
                      ),
                    ),
                  ]),
          ),
        ]);
      },
    );
  }
}

class SharedLinksScreen extends StatefulWidget {
  final ImmichApi api;
  const SharedLinksScreen({super.key, required this.api});

  @override
  State<SharedLinksScreen> createState() => _SharedLinksScreenState();
}

class _SharedLinksScreenState extends State<SharedLinksScreen> {
  late Future<List<Map<String, dynamic>>> _links = widget.api.sharedLinks();

  void _reload() => setState(() => _links = widget.api.sharedLinks());

  @override
  Widget build(BuildContext context) {
    final api = widget.api;
    return Loader<List<Map<String, dynamic>>>(
      future: _links,
      onRetry: _reload,
      builder: (links) {
        if (links.isEmpty) return Center(child: Text(t('no_results')));
        return ListView(padding: const EdgeInsets.all(16), children: [
          for (final l in links) _card(context, api, l),
        ]);
      },
    );
  }

  Widget _card(BuildContext context, ImmichApi api, Map<String, dynamic> l) {
    final theme = Theme.of(context);
    final album = l['album'] as Map<String, dynamic>?;
    final assets = (l['assets'] as List?) ?? const [];
    final coverId = album?['albumThumbnailAssetId'] ?? (assets.isNotEmpty ? assets.first['id'] : null);
    final expires = DateTime.tryParse(l['expiresAt'] ?? '');
    final expired = expires != null && expires.isBefore(DateTime.now());
    final url = api.sharedLinkUrl(l);
    return Card(
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 64,
            height: 64,
            child: coverId == null
                ? const Icon(Icons.link)
                : Image(
                    image: NetworkImage(api.thumbnailUrl(coverId), headers: api.headers),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(Icons.link),
                  ),
          ),
        ),
        title: Text(album?['albumName'] ?? (l['description'] as String?) ?? t('shared_link_individual_shared')),
        subtitle: Text([
          if ((l['description'] as String?)?.isNotEmpty ?? false) l['description'],
          expired
              ? t('expired')
              : expires == null
                  ? t('shared_link_expires_never')
                  : t('expires_date', {'date': DateFormat.yMMMd(i18n.dateLocale).add_Hm().format(expires.toLocal())}),
          url,
        ].join('\n')),
        isThreeLine: true,
        trailing: Wrap(children: [
          IconButton(
            tooltip: t('copy_link'),
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(t('shared_link_clipboard_copied_massage'))));
            },
          ),
          IconButton(
            tooltip: t('edit_link'),
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              await showSharedLinkDialog(context, api, existing: l);
              _reload();
            },
          ),
          IconButton(
            tooltip: t('delete_link'),
            icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(t('delete_shared_link')),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('delete'))),
                  ],
                ),
              );
              if (ok != true) return;
              await api.deleteSharedLink(l['id']);
              _reload();
            },
          ),
        ]),
      ),
    );
  }
}
