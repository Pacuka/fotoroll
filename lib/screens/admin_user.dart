// Admin user detail (web: /admin/users/[id] and /edit): profile, features,
// storage quota, devices, and actions — edit, reset password, reset PIN, delete/restore.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../i18n.dart';
import 'utilities.dart' show formatBytes;

/// Same alphabet and length as the web's generatePassword().
String generatePassword([int length = 16]) {
  const chars = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ,.-{}+!#\$%/()=?';
  final r = Random.secure();
  return List.generate(length, (_) => chars[r.nextInt(chars.length)]).join();
}

class AdminUserScreen extends StatefulWidget {
  final ImmichApi api;
  final String userId;
  final String? currentUserId;
  final Future<void> Function(Map<String, dynamic> user)? onDelete;

  const AdminUserScreen({
    super.key,
    required this.api,
    required this.userId,
    this.currentUserId,
    this.onDelete,
  });

  @override
  State<AdminUserScreen> createState() => _AdminUserScreenState();
}

class _AdminUserScreenState extends State<AdminUserScreen> {
  late Future<_Data> _data = _load();

  Future<_Data> _load() async {
    final api = widget.api;
    final r = await Future.wait([
      api.adminUser(widget.userId),
      api.adminUserStatistics(widget.userId),
      api.adminUserPreferences(widget.userId),
      api.adminUserSessions(widget.userId),
    ]);
    return _Data(r[0] as Map<String, dynamic>, r[1] as Map<String, dynamic>,
        r[2] as Map<String, dynamic>, (r[3] as List).cast<Map<String, dynamic>>());
  }

  void _reload() => setState(() { _data = _load(); });

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<bool> _confirm(String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(text),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('confirm'))),
          ],
        ),
      ) ??
      false;

  Future<void> _run(Future<void> Function() f, [String? ok]) async {
    try {
      await f();
      if (mounted && ok != null) _toast(ok);
      _reload();
    } catch (e) {
      if (mounted) _toast('${t('error')}: $e');
    }
  }

  Future<void> _edit(Map<String, dynamic> u) async {
    final email = TextEditingController(text: u['email'] ?? '');
    final name = TextEditingController(text: u['name'] ?? '');
    final quota = u['quotaSizeInBytes'] as num?;
    final quotaCtl = TextEditingController(
        text: quota == null ? '' : (quota / (1 << 30)).toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), ''));
    final label = TextEditingController(text: u['storageLabel'] ?? '');
    var isAdmin = u['isAdmin'] == true;
    final self = u['id'] == widget.currentUserId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(t('edit_user')),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(controller: email, decoration: InputDecoration(labelText: t('email'))),
              TextField(controller: name, decoration: InputDecoration(labelText: t('name'))),
              TextField(
                controller: quotaCtl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: t('admin.quota_size_gib'), hintText: t('unlimited')),
              ),
              TextField(controller: label, decoration: InputDecoration(labelText: t('storage_label'))),
              const SizedBox(height: 6),
              Text('${t('admin.note_apply_storage_label_previous_assets')} '
                  '${t('admin.storage_template_migration_job')}',
                  style: Theme.of(ctx).textTheme.bodySmall),
              if (!self)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t('admin.admin_user')),
                  value: isAdmin,
                  onChanged: (v) => set(() => isAdmin = v),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('save'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final gib = num.tryParse(quotaCtl.text.trim().replaceAll(',', '.'));
    await _run(
      () => widget.api.updateUserAdmin(u['id'], {
        'email': email.text.trim(),
        'name': name.text.trim(),
        'storageLabel': label.text.trim(),
        'quotaSizeInBytes': gib == null ? null : (gib * (1 << 30)).round(),
        if (!self) 'isAdmin': isAdmin,
      }),
      t('saved_settings'),
    );
  }

  Future<void> _resetPassword(Map<String, dynamic> u) async {
    if (!await _confirm(t('admin.confirm_user_password_reset', {'user': u['name']}))) return;
    final password = generatePassword();
    try {
      await widget.api.updateUserAdmin(u['id'], {'password': password, 'shouldChangePassword': true});
    } catch (e) {
      return _toast('${t('errors.unable_to_reset_password')}: $e');
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle_outline),
        title: Text(t('password_reset_success')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('admin.user_password_has_been_reset')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: SelectableText(password, style: const TextStyle(fontFamily: 'monospace', fontSize: 16))),
            IconButton(
              tooltip: t('copy_password'),
              icon: const Icon(Icons.copy),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: password));
                _toast(t('copied_to_clipboard'));
              },
            ),
          ]),
          const SizedBox(height: 8),
          Text(t('admin.user_password_reset_description')),
        ]),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(t('done')))],
      ),
    );
    _reload();
  }

  Future<void> _resetPin(Map<String, dynamic> u) async {
    if (!await _confirm(t('admin.confirm_user_pin_code_reset', {'user': u['name']}))) return;
    await _run(() => widget.api.updateUserAdmin(u['id'], {'pinCode': null}), t('pin_code_reset_successfully'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<_Data>(
      future: _data,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(appBar: AppBar(), body: Center(child: Text('${t('error')}: ${snap.error}')));
        }
        if (!snap.hasData) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
        final d = snap.data!;
        final u = d.user;
        final deleted = u['deletedAt'] != null;
        final used = (u['quotaUsageInBytes'] as num?) ?? 0;
        final quota = u['quotaSizeInBytes'] as num?;
        String date(String? iso) {
          final x = DateTime.tryParse(iso ?? '')?.toLocal();
          return x == null ? '' : DateFormat.yMMMMd(i18n.dateLocale).add_jm().format(x);
        }

        Widget card(IconData icon, String title, Widget child) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(icon, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(title, style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary)),
                  ]),
                  const SizedBox(height: 12),
                  child,
                ]),
              ),
            );
        Widget kv(String k, String v) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(k, style: theme.textTheme.labelMedium),
                SelectableText(v),
              ]),
            );
        Widget feature(String label, bool? on) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Icon(on == true ? Icons.check_circle : Icons.cancel_outlined,
                    size: 18, color: on == true ? Colors.green : theme.colorScheme.outline),
                const SizedBox(width: 8),
                Text(label),
              ]),
            );
        bool? pref(String a, String b) => (d.prefs[a] as Map?)?[b] as bool?;
        Widget stat(IconData icon, String label, String value) => Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Icon(icon, size: 32),
                    const SizedBox(width: 12),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(label),
                      Text(value, style: theme.textTheme.headlineSmall),
                    ]),
                  ]),
                ),
              ),
            );
        final nf = NumberFormat.decimalPattern(i18n.dateLocale);

        return Scaffold(
          appBar: AppBar(
            title: Text('${t('admin.user_management')} › ${u['name'] ?? ''}'),
            actions: [
              TextButton.icon(onPressed: () => _resetPassword(u), icon: const Icon(Icons.lock_reset), label: Text(t('reset_password'))),
              TextButton.icon(onPressed: () => _resetPin(u), icon: const Icon(Icons.pin_outlined), label: Text(t('reset_pin_code'))),
              TextButton.icon(onPressed: () => _edit(u), icon: const Icon(Icons.edit_outlined), label: Text(t('edit'))),
              if (deleted)
                TextButton.icon(
                  onPressed: () => _run(() => widget.api.restoreUser(u['id'])),
                  icon: const Icon(Icons.restore),
                  label: Text(t('restore')),
                )
              else if (widget.onDelete != null && u['id'] != widget.currentUserId)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                  onPressed: () async {
                    await widget.onDelete!(u);
                    _reload();
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: Text(t('delete')),
                ),
              const SizedBox(width: 8),
            ],
          ),
          body: ListView(padding: const EdgeInsets.all(24), children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (deleted)
                    Card(
                      color: theme.colorScheme.errorContainer,
                      child: ListTile(
                        leading: const Icon(Icons.delete_outline),
                        title: Text(t('user_has_been_deleted')),
                      ),
                    ),
                  Row(children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundImage: NetworkImage(
                          widget.api.profileImageUrl(u['id'], changedAt: u['profileChangedAt']),
                          headers: widget.api.headers),
                      onBackgroundImageError: (_, _) {},
                    ),
                    const SizedBox(width: 16),
                    Text(u['name'] ?? '', style: theme.textTheme.headlineMedium),
                    if (u['isAdmin'] == true) ...[
                      const SizedBox(width: 12),
                      Chip(label: Text(t('admin.admin_user'))),
                    ],
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    stat(Icons.camera, t('photos'), nf.format(d.stats['images'] ?? 0)),
                    stat(Icons.play_circle_outline, t('videos'), nf.format(d.stats['videos'] ?? 0)),
                    stat(Icons.pie_chart_outline, t('storage'), formatBytes(used)),
                  ]),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final w in [
                      card(Icons.person_outline, t('profile'), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        kv(t('name'), u['name'] ?? ''),
                        kv(t('email'), u['email'] ?? ''),
                        kv(t('created_at'), date(u['createdAt'])),
                        kv(t('updated_at'), date(u['updatedAt'])),
                        kv(t('id'), u['id'] ?? ''),
                      ])),
                      card(Icons.manage_search, t('features'), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        feature(t('email_notifications'), pref('emailNotifications', 'enabled')),
                        feature(t('folders'), pref('folders', 'enabled')),
                        feature(t('memories'), pref('memories', 'enabled')),
                        feature(t('people'), pref('people', 'enabled')),
                        feature(t('rating'), pref('ratings', 'enabled')),
                        feature(t('shared_links'), pref('sharedLinks', 'enabled')),
                        feature(t('show_supporter_badge'), pref('purchase', 'showSupportBadge')),
                        feature(t('tags'), pref('tags', 'enabled')),
                        feature(t('gcast_enabled'), pref('cast', 'gCastEnabled')),
                      ])),
                      card(Icons.pie_chart, t('storage_quota'), quota != null && quota >= 0
                          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(t('storage_usage', {'used': formatBytes(used), 'available': formatBytes(quota)})),
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: quota == 0 ? 1 : (used / quota).clamp(0, 1).toDouble(),
                                minHeight: 8,
                                borderRadius: BorderRadius.circular(4),
                                color: quota > 0 && used / quota >= .95
                                    ? theme.colorScheme.error
                                    : quota > 0 && used / quota >= .8
                                        ? Colors.orange
                                        : null,
                              ),
                            ])
                          : Row(children: [
                              const Icon(Icons.check_circle, color: Colors.green, size: 20),
                              const SizedBox(width: 6),
                              Text(t('unlimited')),
                            ])),
                      card(Icons.devices, t('authorized_devices'), d.sessions.isEmpty
                          ? Text(t('no_devices'))
                          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              for (final s in d.sessions)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.devices_other),
                                  title: Text([s['deviceOS'], s['deviceType']]
                                      .whereType<String>()
                                      .where((x) => x.isNotEmpty)
                                      .join(' · ')),
                                  subtitle: Text('${t('last_seen')}: ${date(s['updatedAt'])}'),
                                ),
                            ])),
                    ])
                      SizedBox(width: 520, child: w),
                  ]),
                ]),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _Data {
  final Map<String, dynamic> user;
  final Map<String, dynamic> stats;
  final Map<String, dynamic> prefs;
  final List<Map<String, dynamic>> sessions;
  _Data(this.user, this.stats, this.prefs, this.sessions);
}
