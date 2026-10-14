// Admin: external libraries and maintenance (web: /admin/library-management, /admin/maintenance).
import 'package:flutter/material.dart';

import '../api.dart';
import '../i18n.dart';
import 'utilities.dart' show formatBytes;

void _toast(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

Future<bool> _confirm(BuildContext context, String text, String ok) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ok),
          ),
        ],
      ),
    ) ??
    false;

class LibrariesScreen extends StatefulWidget {
  final ImmichApi api;
  const LibrariesScreen({super.key, required this.api});

  @override
  State<LibrariesScreen> createState() => _LibrariesScreenState();
}

class _LibrariesScreenState extends State<LibrariesScreen> {
  late Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)> _data = _load();

  Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)> _load() async =>
      (await widget.api.libraries(), await widget.api.adminUsers());

  void _reload() => setState(() { _data = _load(); });

  Future<void> _run(Future<void> Function() f, [String? ok]) async {
    try {
      await f();
      if (mounted && ok != null) _toast(context, ok);
      _reload();
    } catch (e) {
      if (mounted) _toast(context, '${t('error')}: $e');
    }
  }

  Future<void> _edit(List<Map<String, dynamic>> users, [Map<String, dynamic>? lib]) async {
    final name = TextEditingController(text: lib?['name'] ?? '');
    final paths = TextEditingController(text: ((lib?['importPaths'] as List?) ?? []).join('\n'));
    final excl = TextEditingController(text: ((lib?['exclusionPatterns'] as List?) ?? []).join('\n'));
    String? owner = lib?['ownerId'] ?? (users.isNotEmpty ? users.first['id'] : null);
    List<String> lines(TextEditingController c) =>
        c.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(lib == null ? t('create_library') : t('edit')),
          content: SizedBox(
            width: 480,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: InputDecoration(labelText: t('name'))),
              if (lib == null)
                DropdownButtonFormField<String>(
                  initialValue: owner,
                  decoration: InputDecoration(labelText: t('owner')),
                  items: [
                    for (final u in users)
                      DropdownMenuItem(value: u['id'] as String, child: Text(u['name'] ?? u['email'])),
                  ],
                  onChanged: (v) => set(() => owner = v),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: paths,
                maxLines: 4,
                decoration: InputDecoration(labelText: t('linux_import_paths')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: excl,
                maxLines: 3,
                decoration: InputDecoration(labelText: t('linux_exclusion_patterns')),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(lib == null ? t('create') : t('save'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (lib == null) {
      await _run(
        () => widget.api.createLibrary(
          ownerId: owner!,
          name: name.text.trim(),
          importPaths: lines(paths),
          exclusionPatterns: lines(excl),
        ),
        t('admin.library_created', {'library': name.text.trim()}),
      );
    } else {
      await _run(
        () => widget.api.updateLibrary(lib['id'],
            name: name.text.trim(), importPaths: lines(paths), exclusionPatterns: lines(excl)),
        t('admin.library_updated'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _data,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('${t('error')}: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final (libs, users) = snap.data!;
        String ownerName(String? id) =>
            users.firstWhere((u) => u['id'] == id, orElse: () => {'name': ''})['name'] ?? '';
        return ListView(padding: const EdgeInsets.all(16), children: [
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => _edit(users),
              icon: const Icon(Icons.add),
              label: Text(t('create_library')),
            ),
          ),
          const SizedBox(height: 8),
          for (final lib in libs)
            Card(
              child: ListTile(
                leading: const Icon(Icons.folder_shared_outlined),
                title: Text(lib['name'] ?? ''),
                subtitle: Text([
                  '${t('owner')}: ${ownerName(lib['ownerId'])}',
                  '${t('assets')}: ${lib['assetCount'] ?? 0}',
                  ...((lib['importPaths'] as List?) ?? []).map((p) => '📁 $p'),
                ].join('\n')),
                isThreeLine: true,
                trailing: Wrap(children: [
                  IconButton(
                    tooltip: t('scan'),
                    icon: const Icon(Icons.refresh),
                    onPressed: () => _run(() => widget.api.scanLibrary(lib['id']), t('admin.scanning_library')),
                  ),
                  IconButton(
                    tooltip: t('edit'),
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _edit(users, lib),
                  ),
                  IconButton(
                    tooltip: t('delete_library'),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final count = (lib['assetCount'] as num?)?.toInt() ?? 0;
                      if (await _confirm(
                          context,
                          count > 0
                              ? t('admin.confirm_delete_library_assets', {'count': count})
                              : t('admin.confirm_delete_library', {'library': lib['name']}),
                          t('delete'))) {
                        await _run(() => widget.api.deleteLibrary(lib['id']), t('admin.library_deleted'));
                      }
                    },
                  ),
                ]),
              ),
            ),
        ]);
      },
    );
  }
}

class MaintenanceScreen extends StatefulWidget {
  final ImmichApi api;
  const MaintenanceScreen({super.key, required this.api});

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  late Future<List<Map<String, dynamic>>> _backups = widget.api.databaseBackups();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        child: ListTile(
          leading: const Icon(Icons.build_outlined),
          title: Text(t('admin.maintenance_settings')),
          subtitle: Text(t('admin.maintenance_settings_description')),
          trailing: FilledButton.tonal(
            onPressed: () async {
              if (!await _confirm(context, t('linux_maintenance_confirm'), t('admin.maintenance_start'))) {
                return;
              }
              try {
                await widget.api.setMaintenanceMode('start');
              } catch (e) {
                if (context.mounted) _toast(context, '${t('admin.maintenance_start_error')} $e');
              }
            },
            child: Text(t('admin.maintenance_start')),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Text(t('admin.maintenance_backup_management'), style: theme.textTheme.titleMedium),
      const SizedBox(height: 8),
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _backups,
        builder: (context, snap) {
          if (snap.hasError) return Text('${t('error')}: ${snap.error}');
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!;
          if (list.isEmpty) return Text(t('linux_no_backups'));
          return Column(children: [
            for (final b in list)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.storage_outlined),
                  title: Text(b['filename'] ?? ''),
                  subtitle: Text([
                    if (b['filesize'] != null) formatBytes(b['filesize']),
                    if (b['timezone'] != null) '${b['timezone']}',
                  ].join(' · ')),
                  trailing: IconButton(
                    tooltip: t('admin.maintenance_delete_backup'),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (!await _confirm(
                          context, t('admin.maintenance_delete_backup_description'), t('delete'))) {
                        return;
                      }
                      try {
                        await widget.api.deleteDatabaseBackups([b['filename']]);
                        setState(() => _backups = widget.api.databaseBackups());
                      } catch (e) {
                        if (context.mounted) _toast(context, '${t('error')}: $e');
                      }
                    },
                  ),
                ),
              ),
          ]);
        },
      ),
    ]);
  }
}

