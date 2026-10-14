// Utilities (web: /utilities): review duplicates and large files.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../i18n.dart';
import '../sources.dart';
import '../widgets/loader.dart';
import 'viewer.dart';

String formatBytes(num b) {
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  var v = b.toDouble();
  var u = 0;
  while (v >= 1024 && u < units.length - 1) {
    v /= 1024;
    u++;
  }
  return '${v.toStringAsFixed(u == 0 ? 0 : 1)} ${units[u]}';
}

class UtilitiesScreen extends StatelessWidget {
  final ImmichApi api;
  const UtilitiesScreen({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    void push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    return ListView(padding: const EdgeInsets.all(24), children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(t('organize_your_library'), style: Theme.of(context).textTheme.labelLarge),
              ),
              ListTile(
                leading: const Icon(Icons.content_copy_outlined),
                title: Text(t('review_duplicates')),
                onTap: () => push(DuplicatesScreen(api: api)),
              ),
              ListTile(
                leading: const Icon(Icons.photo_size_select_large_outlined),
                title: Text(t('review_large_files')),
                onTap: () => push(LargeFilesScreen(api: api)),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }
}

class DuplicatesScreen extends StatefulWidget {
  final ImmichApi api;
  const DuplicatesScreen({super.key, required this.api});

  @override
  State<DuplicatesScreen> createState() => _DuplicatesScreenState();
}

class _DuplicatesScreenState extends State<DuplicatesScreen> {
  late Future<List<DuplicateGroup>> _groups = widget.api.duplicates();
  int _index = 0;
  Set<String> _keep = {};
  bool _busy = false;

  void _select(List<DuplicateGroup> groups, int i) {
    _index = i;
    _keep = i < groups.length ? {...groups[i].suggestedKeep} : {};
    if (_keep.isEmpty && i < groups.length && groups[i].assets.isNotEmpty) {
      _keep = {groups[i].assets.first['id'] as String};
    }
  }

  Future<void> _resolve(List<DuplicateGroup> groups, {required bool keepAll}) async {
    final g = groups[_index];
    setState(() => _busy = true);
    try {
      if (keepAll) {
        await widget.api.dismissDuplicate(g.id);
      } else {
        final all = [for (final a in g.assets) a['id'] as String];
        await widget.api.resolveDuplicate(
            g.id, _keep.toList(), all.where((id) => !_keep.contains(id)).toList());
      }
      groups.removeAt(_index);
      setState(() => _select(groups, _index.clamp(0, groups.isEmpty ? 0 : groups.length - 1)));
      if (groups.isEmpty && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t('resolved_all_duplicates'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t('error')}: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('review_duplicates'))),
      body: Loader<List<DuplicateGroup>>(
        future: _groups,
        onRetry: () => setState(() { _groups = widget.api.duplicates(); }),
        builder: (groups) {
          if (groups.isEmpty) return Center(child: Text(t('no_duplicates_found')));
          if (_keep.isEmpty) _select(groups, _index);
          final g = groups[_index];
          final theme = Theme.of(context);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t('duplicates_description'), style: theme.textTheme.bodyMedium),
                    Text(t('linux_keep_hint'), style: theme.textTheme.bodySmall),
                  ]),
                ),
                IconButton(
                  tooltip: t('previous'),
                  onPressed: _index > 0 ? () => setState(() => _select(groups, _index - 1)) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(t('linux_duplicate_progress', {'current': _index + 1, 'total': groups.length})),
                IconButton(
                  tooltip: t('next'),
                  onPressed: _index < groups.length - 1
                      ? () => setState(() => _select(groups, _index + 1))
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ]),
            ),
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(16),
                children: [
                  for (final a in g.assets)
                    _DuplicateCard(
                      api: widget.api,
                      asset: a,
                      keep: _keep.contains(a['id']),
                      suggested: g.suggestedKeep.contains(a['id']),
                      onToggle: () => setState(() {
                        final id = a['id'] as String;
                        _keep.contains(id) ? _keep.remove(id) : _keep.add(id);
                      }),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(alignment: WrapAlignment.end, spacing: 12, children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _resolve(groups, keepAll: true),
                  icon: const Icon(Icons.done_all),
                  label: Text(t('linux_not_duplicates')),
                ),
                FilledButton.icon(
                  onPressed: _busy || _keep.isEmpty ? null : () => _resolve(groups, keepAll: false),
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: Text(t('linux_keep_selected')),
                ),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}

class _DuplicateCard extends StatelessWidget {
  final ImmichApi api;
  final Map<String, dynamic> asset;
  final bool keep;
  final bool suggested;
  final VoidCallback onToggle;

  const _DuplicateCard({
    required this.api,
    required this.asset,
    required this.keep,
    required this.suggested,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exif = (asset['exifInfo'] as Map?)?.cast<String, dynamic>() ?? {};
    final size = exif['fileSizeInByte'] as num?;
    final w = exif['exifImageWidth'] ?? asset['width'];
    final h = exif['exifImageHeight'] ?? asset['height'];
    final date = DateTime.tryParse(asset['localDateTime'] ?? asset['fileCreatedAt'] ?? '');
    final color = keep ? theme.colorScheme.primary : theme.colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: SizedBox(
        width: 300,
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
                  child: Image(
                    image: NetworkImage(api.thumbnailUrl(asset['id'], size: 'preview'),
                        headers: api.headers),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
              Container(
                color: color,
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  keep ? t('keep') : t('to_trash'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: keep ? theme.colorScheme.onPrimary : theme.colorScheme.onError,
                      fontWeight: FontWeight.w600),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(asset['originalFileName'] ?? '',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                  if (size != null) Text('${t('file_size')}: ${formatBytes(size)}'),
                  if (w != null && h != null) Text('${t('resolution')}: $w × $h'),
                  if (date != null)
                    Text('${t('date')}: ${DateFormat.yMMMd(i18n.dateLocale).add_Hm().format(date)}'),
                  if (suggested)
                    Text(t('linux_suggested'), style: TextStyle(color: theme.colorScheme.primary)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class LargeFilesScreen extends StatefulWidget {
  final ImmichApi api;
  const LargeFilesScreen({super.key, required this.api});

  @override
  State<LargeFilesScreen> createState() => _LargeFilesScreenState();
}

class _LargeFilesScreenState extends State<LargeFilesScreen> {
  late Future<List<Map<String, dynamic>>> _items = widget.api.largeAssets();
  SearchSource? _source; // lets the viewer page through the same list

  @override
  void dispose() {
    _source?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final api = widget.api;
    return Scaffold(
      appBar: AppBar(title: Text(t('large_files'))),
      body: Loader<List<Map<String, dynamic>>>(
        future: _items,
        onRetry: () => setState(() {
          _source?.dispose();
          _source = null;
          _items = api.largeAssets();
        }),
        builder: (items) {
          if (items.isEmpty) return Center(child: Text(t('no_results')));
          final source = _source ??= SearchSource((page) async => SearchPage(
              page == 1 ? [for (final a in items) AssetRef.fromAssetJson(a)] : const [], null))
            ..loadMore();
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length + 1,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(t('linux_large_files_sub')),
                );
              }
              final a = items[i - 1];
              final size = (a['exifInfo']?['fileSizeInByte'] as num?) ?? 0;
              return ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: Image(
                      image: NetworkImage(api.thumbnailUrl(a['id']), headers: api.headers),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
                title: Text(a['originalFileName'] ?? ''),
                subtitle: Text(a['type'] == 'VIDEO' ? t('videos') : t('photos')),
                trailing: Text(formatBytes(size), style: Theme.of(context).textTheme.titleMedium),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ViewerScreen(api: api, source: source, initialIndex: i - 1),
                )),
              );
            },
          );
        },
      ),
    );
  }
}
