// Administration (web: /admin): users, job queues and server statistics.
// System settings stay in the web interface.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../i18n.dart';
import 'admin_extra.dart';
import 'admin_user.dart';
import 'system_settings.dart';
import 'utilities.dart' show formatBytes;

class AdminScreen extends StatefulWidget {
  final ImmichApi api;
  const AdminScreen({super.key, required this.api});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final api = widget.api;
    // Same entries and order as the web admin sidebar.
    final tabs = <(String, IconData, Widget Function())>[
      (t('users'), Icons.people_outline, () => _UsersTab(api: api)),
      (t('external_libraries'), Icons.folder_shared_outlined, () => LibrariesScreen(api: api)),
      (t('admin.queues'), Icons.work_history_outlined, () => _QueuesTab(api: api)),
      (t('settings'), Icons.settings_outlined, () => SystemSettingsScreen(api: api)),
      (t('admin.maintenance_settings'), Icons.build_outlined, () => MaintenanceScreen(api: api)),
      (t('server_stats'), Icons.bar_chart, () => _StatsTab(api: api)),
    ];
    final scheme = Theme.of(context).colorScheme;
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        width: 220,
        child: ListView(padding: const EdgeInsets.only(top: 12, right: 12), children: [
          for (var i = 0; i < tabs.length; i++)
            Material(
              color: i == _tab ? scheme.secondaryContainer.withValues(alpha: 0.6) : Colors.transparent,
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(24)),
              child: ListTile(
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.horizontal(right: Radius.circular(24))),
                leading: Icon(tabs[i].$2, color: i == _tab ? scheme.primary : null),
                title: Text(tabs[i].$1,
                    style: TextStyle(color: i == _tab ? scheme.primary : null)),
                onTap: () => setState(() => _tab = i),
              ),
            ),
        ]),
      ),
      const VerticalDivider(width: 1),
      Expanded(child: KeyedSubtree(key: ValueKey(_tab), child: tabs[_tab].$3())),
    ]);
  }
}

void _toast(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

class _UsersTab extends StatefulWidget {
  final ImmichApi api;
  const _UsersTab({required this.api});

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  late Future<List<Map<String, dynamic>>> _users = widget.api.adminUsers();
  late final Future<String?> _meId =
      widget.api.me().then((m) => m['id'] as String?).catchError((_) => null);

  void _reload() => setState(() { _users = widget.api.adminUsers(); });

  Future<void> _run(Future<void> Function() f, [String? ok]) async {
    try {
      await f();
      if (mounted && ok != null) _toast(context, ok);
      _reload();
    } catch (e) {
      if (mounted) _toast(context, '${t('error')}: $e');
    }
  }

  Future<void> _create() async {
    final name = TextEditingController();
    final email = TextEditingController();
    final pass = TextEditingController();
    var admin = false;
    var mustChange = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(t('create_user')),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: email,
                  decoration: InputDecoration(labelText: t('email')),
                ),
                TextField(
                  controller: pass,
                  obscureText: true,
                  decoration: InputDecoration(labelText: t('password')),
                ),
                TextField(
                  controller: name,
                  decoration: InputDecoration(labelText: t('name')),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: mustChange,
                  onChanged: (v) => set(() => mustChange = v!),
                  title: Text(t('admin.require_password_change_on_login')),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: admin,
                  onChanged: (v) => set(() => admin = v!),
                  title: Text(t('admin.admin_user')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('create')),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _run(
      () => widget.api.createUser(
        name: name.text.trim(),
        email: email.text.trim(),
        password: pass.text,
        isAdmin: admin,
        shouldChangePassword: mustChange,
      ),
      t('linux_user_created'),
    );
  }

  Future<void> _delete(Map<String, dynamic> u) async {
    var now = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(t('delete_user')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                now
                    ? t('admin.user_delete_immediately', {'user': u['name']})
                    : t('admin.user_delete_delay', {
                        'user': u['name'],
                        'delay': 7,
                      }),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: now,
                onChanged: (v) => set(() => now = v!),
                title: Text(t('admin.user_delete_immediately_checkbox')),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('cancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('delete')),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _run(
      () => widget.api.deleteUser(u['id'], force: now),
      t('admin.user_successfully_removed', {'email': u['email']}),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _users,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('${t('error')}: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final users = snap.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _create,
                icon: const Icon(Icons.person_add),
                label: Text(t('create_user')),
              ),
            ),
            const SizedBox(height: 8),
            for (final u in users)
              Card(
                child: ListTile(
                  leading: Icon(
                    u['isAdmin'] == true
                        ? Icons.admin_panel_settings
                        : Icons.person,
                  ),
                  title: Text(u['name'] ?? ''),
                  subtitle: Text(
                    [
                      u['email'] ?? '',
                      if (u['quotaUsageInBytes'] != null)
                        '${t('usage')}: ${formatBytes(u['quotaUsageInBytes'])}'
                            '${u['quotaSizeInBytes'] != null ? ' / ${formatBytes(u['quotaSizeInBytes'])}' : ''}',
                      if (u['deletedAt'] != null) t('linux_scheduled_deletion'),
                    ].join('\n'),
                  ),
                  isThreeLine: true,
                  onTap: () async {
                    final me = await _meId;
                    if (!context.mounted) return;
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => AdminUserScreen(
                        api: widget.api,
                        userId: u['id'],
                        currentUserId: me,
                        onDelete: _delete,
                      ),
                    ));
                    _reload();
                  },
                  trailing: u['deletedAt'] != null
                      ? TextButton(
                          onPressed: () =>
                              _run(() => widget.api.restoreUser(u['id'])),
                          child: Text(t('restore_user')),
                        )
                      : IconButton(
                          tooltip: t('delete_user'),
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(u),
                        ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Queue cards like the web's QueuePanel: title, counters and the same buttons.
class _QueuesTab extends StatefulWidget {
  final ImmichApi api;
  const _QueuesTab({required this.api});

  @override
  State<_QueuesTab> createState() => _QueuesTabState();
}

class _QueuesTabState extends State<_QueuesTab> {
  List<Map<String, dynamic>>? _queues;
  Object? _error;
  Timer? _timer;

  // Web: queue.service.ts asQueueItem + QueuePanel button labels.
  static const _titles = queueTitleKeys;
  // name → (allLabel, missingLabel); null = no such button
  static const _buttons = <String, (String?, String)>{
    'thumbnailGeneration': ('all', 'missing'),
    'metadataExtraction': ('all', 'missing'),
    'library': (null, 'rescan'),
    'sidecar': ('sync', 'discover'),
    'smartSearch': ('all', 'missing'),
    'duplicateDetection': ('all', 'missing'),
    'faceDetection': ('reset', 'missing'),
    'facialRecognition': ('reset', 'missing'),
    'ocr': ('all', 'missing'),
    'videoConversion': ('all', 'missing'),
    'storageTemplateMigration': (null, 'start'),
    'migration': (null, 'start'),
  };

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final q = await widget.api.queues();
      if (mounted) setState(() => _queues = q);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _cmd(String name, String command, {bool? force}) async {
    try {
      await widget.api.queueCommand(name, command, force: force);
      await _load();
    } catch (e) {
      if (mounted) _toast(context, '${t('error')}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final queues = _queues;
    if (queues == null) {
      return Center(
        child: _error != null
            ? Text('${t('error')}: $_error')
            : const CircularProgressIndicator(),
      );
    }
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(t('linux_server_settings_web'), style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        for (final q in queues)
          if (_titles.containsKey(q['name']))
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t(_titles[q['name']]!),
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            t('linux_jobs_counts', {
                              'active': q['statistics']?['active'] ?? 0,
                              'waiting': q['statistics']?['waiting'] ?? 0,
                              'failed': q['statistics']?['failed'] ?? 0,
                            }),
                          ),
                          if (q['isPaused'] == true)
                            Text(
                              t('paused'),
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                        ],
                      ),
                    ),
                    if (q['isPaused'] == true)
                      TextButton(
                        onPressed: () => _cmd(q['name'], 'resume'),
                        child: Text(t('resume')),
                      )
                    else if ((q['statistics']?['active'] ?? 0) > 0 ||
                        (q['statistics']?['waiting'] ?? 0) > 0)
                      TextButton(
                        onPressed: () => _cmd(q['name'], 'pause'),
                        child: Text(t('pause')),
                      ),
                    if (_buttons[q['name']] case (
                      final all,
                      final missing,
                    )) ...[
                      if (all != null)
                        TextButton(
                          onPressed: () =>
                              _cmd(q['name'], 'start', force: true),
                          child: Text(t(all)),
                        ),
                      FilledButton.tonal(
                        onPressed: () => _cmd(q['name'], 'start', force: false),
                        child: Text(t(missing)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

class _StatsTab extends StatefulWidget {
  final ImmichApi api;
  const _StatsTab({required this.api});

  @override
  State<_StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<_StatsTab> {
  late final Future<Map<String, dynamic>> _stats = widget.api
      .serverStatistics();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nf = NumberFormat.decimalPattern(i18n.dateLocale);
    return FutureBuilder<Map<String, dynamic>>(
      future: _stats,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('${t('error')}: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final s = snap.data!;
        Widget tile(String label, String value, IconData icon) => Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(icon, size: 32),
                  const SizedBox(height: 8),
                  Text(value, style: theme.textTheme.headlineSmall),
                  Text(label),
                ],
              ),
            ),
          ),
        );
        final users = (s['usageByUser'] as List? ?? [])
            .cast<Map<String, dynamic>>();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                tile(
                  t('photos'),
                  nf.format(s['photos'] ?? 0),
                  Icons.photo_outlined,
                ),
                tile(
                  t('videos'),
                  nf.format(s['videos'] ?? 0),
                  Icons.videocam_outlined,
                ),
                tile(
                  t('total_usage'),
                  formatBytes(s['usage'] ?? 0),
                  Icons.storage,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(t('user_usage_detail'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            DataTable(
              columns: [
                DataColumn(label: Text(t('user'))),
                DataColumn(label: Text(t('photos')), numeric: true),
                DataColumn(label: Text(t('videos')), numeric: true),
                DataColumn(label: Text(t('usage')), numeric: true),
              ],
              rows: [
                for (final u in users)
                  DataRow(
                    cells: [
                      DataCell(Text(u['userName'] ?? '')),
                      DataCell(Text(nf.format(u['photos'] ?? 0))),
                      DataCell(Text(nf.format(u['videos'] ?? 0))),
                      DataCell(Text(formatBytes(u['usage'] ?? 0))),
                    ],
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// Web: queue.service.ts asQueueItem — queue name → title key.
const queueTitleKeys = {
  'thumbnailGeneration': 'admin.thumbnail_generation_job',
  'metadataExtraction': 'admin.metadata_extraction_job',
  'library': 'external_libraries',
  'sidecar': 'admin.sidecar_job',
  'smartSearch': 'admin.machine_learning_smart_search',
  'duplicateDetection': 'admin.machine_learning_duplicate_detection',
  'faceDetection': 'admin.face_detection',
  'facialRecognition': 'admin.machine_learning_facial_recognition',
  'ocr': 'admin.machine_learning_ocr',
  'videoConversion': 'admin.video_conversion_job',
  'storageTemplateMigration': 'admin.storage_template_migration',
  'migration': 'admin.migration_job',
  'backgroundTask': 'admin.background_task_job',
  'search': 'search',
  'notifications': 'notifications',
  'backupDatabase': 'admin.backup_database',
  'workflow': 'workflows',
  'integrityCheck': 'integrity_checks',
  'editor': 'editor',
};
