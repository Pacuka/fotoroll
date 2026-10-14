// Account Settings (web: /user-settings): account, password, PIN code, API keys,
// authorized devices and sharing (sharing_settings.dart).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../i18n.dart';
import 'app_settings.dart' show AppSettingsBody;
import 'sharing_settings.dart';

class AccountSettingsScreen extends StatelessWidget {
  final ImmichApi api;
  const AccountSettingsScreen({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    Widget section(IconData icon, String title, String subtitle, Widget child) => Card(
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            leading: Icon(icon),
            title: Text(title),
            subtitle: Text(subtitle),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            children: [child],
          ),
        );
    // Same sections, order and texts as the web's UserSettingsList.
    return ListView(padding: const EdgeInsets.all(24), children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(children: [
            section(Icons.settings_outlined, t('app_settings'), t('manage_the_app_settings'),
                const AppSettingsBody()),
            section(Icons.person_outline, t('account'), t('manage_your_account'), _AccountSection(api: api)),
            section(Icons.bar_chart, t('user_usage_stats'), t('user_usage_stats_description'),
                _UsageSection(api: api)),
            section(Icons.key_outlined, t('api_keys'), t('manage_your_api_keys'), _ApiKeysSection(api: api)),
            section(Icons.devices_outlined, t('authorized_devices'), t('manage_your_devices'),
                _SessionsSection(api: api)),
            section(Icons.download_outlined, t('download_settings'), t('download_settings_description'),
                _PrefsSection(api: api, groups: _downloadPrefs)),
            section(Icons.extension_outlined, t('features'), t('features_setting_description'),
                _PrefsSection(api: api, groups: _featurePrefs)),
            section(Icons.notifications_outlined, t('notifications'), t('notifications_setting_description'),
                _PrefsSection(api: api, groups: _notificationPrefs)),
            section(Icons.password, t('password'), t('change_your_password'), _PasswordSection(api: api)),
            section(Icons.pin_outlined, t('user_pin_code_settings'), t('user_pin_code_settings_description'),
                _PinSection(api: api)),
            section(Icons.workspace_premium_outlined, t('user_purchase_settings'),
                t('user_purchase_settings_description'), _PurchaseSection(api: api)),
            section(Icons.share_outlined, t('sharing'), t('manage_sharing_with_other_users'),
                SharingSection(api: api)),
          ]),
        ),
      ),
    ]);
  }
}

// ---- Preferences (web: DownloadSettings / FeatureSettings / NotificationsSettings) ----

enum _Kind { toggle, number, gib, order, choice }

class _Pref {
  final String path; // e.g. 'folders.enabled'
  final String label;
  final String? desc;
  final _Kind kind;
  final String? requires; // only shown when this path is true (web: {#if enabled})
  /// [_Kind.choice]: (value, label key). Hidden when the server doesn't have the preference.
  final List<(String, String)> options;
  const _Pref(this.path, this.label, this.kind, {this.desc, this.requires, this.options = const []});
}

class _PrefGroup {
  final String? title;
  final String? subtitle;
  final List<_Pref> prefs;
  const _PrefGroup(this.title, this.subtitle, this.prefs);
}

const _downloadPrefs = [
  _PrefGroup(null, null, [
    _Pref('download.archiveSize', 'archive_size', _Kind.gib, desc: 'archive_size_description'),
    _Pref('download.includeEmbeddedVideos', 'download_include_embedded_motion_videos', _Kind.toggle,
        desc: 'download_include_embedded_motion_videos_description'),
  ]),
];

const _featurePrefs = [
  _PrefGroup('albums', 'albums_feature_description', [
    _Pref('albums.defaultAssetOrder', 'albums_default_sort_order', _Kind.order,
        desc: 'albums_default_sort_order_description'),
  ]),
  _PrefGroup('folders', 'folders_feature_description', [
    _Pref('folders.enabled', 'enable', _Kind.toggle),
    _Pref('folders.sidebarWeb', 'sidebar', _Kind.toggle,
        desc: 'sidebar_display_description', requires: 'folders.enabled'),
  ]),
  _PrefGroup('time_based_memories', 'photos_from_previous_years', [
    _Pref('memories.enabled', 'enable', _Kind.toggle),
    _Pref('memories.duration', 'duration', _Kind.number, desc: 'time_based_memories_duration'),
  ]),
  _PrefGroup('people', 'people_feature_description', [
    _Pref('people.enabled', 'enable', _Kind.toggle),
    _Pref('people.sidebarWeb', 'sidebar', _Kind.toggle,
        desc: 'sidebar_display_description', requires: 'people.enabled'),
    _Pref('people.minimumFaces', 'minFaces', _Kind.number,
        desc: 'minFaces_description', requires: 'people.enabled'),
    _Pref('people.updateStrategy', 'person_update_strategy', _Kind.choice,
        desc: 'person_update_strategy_description', requires: 'people.enabled', options: [
          ('everyone', 'person_update_strategy_everyone'),
          ('self', 'person_update_strategy_self'),
        ]),
  ]),
  _PrefGroup('rating', 'rating_description', [
    _Pref('ratings.enabled', 'enable', _Kind.toggle),
  ]),
  _PrefGroup('shared_links', 'shared_links_description', [
    _Pref('sharedLinks.enabled', 'enable', _Kind.toggle),
    _Pref('sharedLinks.sidebarWeb', 'sidebar', _Kind.toggle,
        desc: 'sidebar_display_description', requires: 'sharedLinks.enabled'),
  ]),
  _PrefGroup('tags', 'tag_feature_description', [
    _Pref('tags.enabled', 'enable', _Kind.toggle),
    _Pref('tags.sidebarWeb', 'sidebar', _Kind.toggle,
        desc: 'sidebar_display_description', requires: 'tags.enabled'),
  ]),
  _PrefGroup('cast', 'cast_description', [
    _Pref('cast.gCastEnabled', 'gcast_enabled', _Kind.toggle, desc: 'gcast_enabled_description'),
  ]),
  _PrefGroup('recently_added', 'recently_added_description', [
    _Pref('recentlyAdded.sidebarWeb', 'sidebar', _Kind.toggle, desc: 'sidebar_display_description'),
  ]),
];

const _notificationPrefs = [
  _PrefGroup(null, null, [
    _Pref('emailNotifications.enabled', 'enable', _Kind.toggle,
        desc: 'notification_toggle_setting_description'),
    _Pref('emailNotifications.albumInvite', 'album_added', _Kind.toggle,
        desc: 'album_added_notification_setting_description', requires: 'emailNotifications.enabled'),
    _Pref('emailNotifications.albumUpdate', 'album_updated', _Kind.toggle,
        desc: 'album_updated_setting_description', requires: 'emailNotifications.enabled'),
  ]),
];

class _PrefsSection extends StatefulWidget {
  final ImmichApi api;
  final List<_PrefGroup> groups;
  const _PrefsSection({required this.api, required this.groups});

  @override
  State<_PrefsSection> createState() => _PrefsSectionState();
}

class _PrefsSectionState extends State<_PrefsSection> {
  Map<String, dynamic>? _prefs;
  int _loads = 0;

  @override
  void initState() {
    super.initState();
    widget.api.preferences().then((p) {
      if (!mounted) return;
      setState(() {
        _prefs = p;
        _loads++;
      });
    });
  }

  dynamic _get(String path) {
    final parts = path.split('.');
    return (_prefs?[parts[0]] as Map?)?[parts[1]];
  }

  void _set(String path, dynamic v) {
    final parts = path.split('.');
    setState(() => ((_prefs![parts[0]] ??= <String, dynamic>{}) as Map)[parts[1]] = v);
  }

  Future<void> _save() async {
    final update = <String, dynamic>{};
    for (final g in widget.groups) {
      for (final p in g.prefs) {
        final parts = p.path.split('.');
        final v = _get(p.path);
        if (v == null && p.kind == _Kind.choice) continue; // not on this server version
        (update[parts[0]] ??= <String, dynamic>{})[parts[1]] = v;
      }
    }
    await _guard(context, () async {
      final saved = await widget.api.updatePreferences(update);
      setState(() {
        _prefs = saved;
        _loads++;
      });
      if (mounted) _toast(context, t('saved_settings'));
    });
  }

  Widget _pref(_Pref p) {
    final v = _get(p.path);
    final desc = p.desc == null ? null : Text(t(p.desc!));
    switch (p.kind) {
      case _Kind.toggle:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t(p.label)),
          subtitle: desc,
          value: v == true,
          onChanged: (x) => _set(p.path, x),
        );
      case _Kind.order:
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t(p.label)),
          subtitle: desc,
          trailing: DropdownButton<String>(
            value: v as String? ?? 'desc',
            items: [
              DropdownMenuItem(value: 'asc', child: Text(t('oldest_first'))),
              DropdownMenuItem(value: 'desc', child: Text(t('newest_first'))),
            ],
            onChanged: (x) => _set(p.path, x),
          ),
        );
      case _Kind.choice:
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t(p.label)),
          subtitle: desc,
          trailing: DropdownButton<String>(
            value: v as String?,
            items: [for (final (value, label) in p.options) DropdownMenuItem(value: value, child: Text(t(label)))],
            onChanged: (x) => _set(p.path, x),
          ),
        );
      case _Kind.number:
      case _Kind.gib:
        final gib = p.kind == _Kind.gib;
        final shown = v == null ? '' : (gib ? '${(v as num) / (1 << 30)}' : '$v');
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t(p.label)),
          subtitle: desc,
          trailing: SizedBox(
            width: 120,
            child: TextFormField(
              key: ValueKey('${p.path}:$_loads'), // re-created only when prefs (re)load
              initialValue: shown.replaceAll(RegExp(r'\.0$'), ''),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
              onChanged: (x) {
                final n = num.tryParse(x);
                if (n != null) _set(p.path, gib ? (n * (1 << 30)).round() : n.round());
              },
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_prefs == null) return const Center(child: CircularProgressIndicator());
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final g in widget.groups) ...[
        if (g.title != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t(g.title!), style: theme.textTheme.titleSmall),
              if (g.subtitle != null) Text(t(g.subtitle!), style: theme.textTheme.bodySmall),
            ]),
          ),
        for (final p in g.prefs)
          if ((p.requires == null || _get(p.requires!) == true) && (p.kind != _Kind.choice || _get(p.path) != null))
            _pref(p),
      ],
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton(onPressed: _save, child: Text(t('save'))),
      ),
    ]);
  }
}

class _UsageSection extends StatefulWidget {
  final ImmichApi api;
  const _UsageSection({required this.api});

  @override
  State<_UsageSection> createState() => _UsageSectionState();
}

class _UsageSectionState extends State<_UsageSection> {
  // Same four queries as the web's UserUsageStatistic.
  late final Future<List<Map<String, dynamic>>> _stats = Future.wait([
    widget.api.assetStatistics(visibility: 'timeline'),
    widget.api.assetStatistics(isFavorite: true),
    widget.api.assetStatistics(visibility: 'archive'),
    widget.api.assetStatistics(isTrashed: true),
  ]);

  @override
  Widget build(BuildContext context) {
    final nf = NumberFormat.decimalPattern(i18n.dateLocale);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _stats,
      builder: (context, snap) {
        if (snap.hasError) return Text('${t('error')}: ${snap.error}');
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final names = [t('timeline'), t('favorites'), t('archive'), t('trash')];
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('photos_and_videos'), style: Theme.of(context).textTheme.titleSmall),
          DataTable(columns: [
            DataColumn(label: Text(t('view_name'))),
            DataColumn(label: Text(t('photos')), numeric: true),
            DataColumn(label: Text(t('videos')), numeric: true),
            DataColumn(label: Text(t('total')), numeric: true),
          ], rows: [
            for (var i = 0; i < 4; i++)
              DataRow(cells: [
                DataCell(Text(names[i])),
                DataCell(Text(nf.format(snap.data![i]['images'] ?? 0))),
                DataCell(Text(nf.format(snap.data![i]['videos'] ?? 0))),
                DataCell(Text(nf.format(snap.data![i]['total'] ?? 0))),
              ]),
          ]),
        ]);
      },
    );
  }
}

class _PurchaseSection extends StatefulWidget {
  final ImmichApi api;
  const _PurchaseSection({required this.api});

  @override
  State<_PurchaseSection> createState() => _PurchaseSectionState();
}

class _PurchaseSectionState extends State<_PurchaseSection> {
  late final Future<Map<String, dynamic>?> _license = widget.api.license();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _license,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final l = snap.data;
        if (l == null) return Text(t('linux_no_license'));
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.verified_outlined),
          title: Text(t('purchase_activated_title')),
          subtitle: Text(t('purchase_activated_time', {'date': _date(l['activatedAt'])})),
        );
      },
    );
  }
}

void _toast(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

Future<void> _guard(BuildContext context, Future<void> Function() f) async {
  try {
    await f();
  } catch (e) {
    if (context.mounted) _toast(context, '${t('error')}: $e');
  }
}

String _date(String? iso) {
  final d = DateTime.tryParse(iso ?? '')?.toLocal();
  return d == null ? '' : DateFormat.yMMMd(i18n.dateLocale).add_Hm().format(d);
}

class _AccountSection extends StatefulWidget {
  final ImmichApi api;
  const _AccountSection({required this.api});

  @override
  State<_AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<_AccountSection> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    widget.api.me().then((u) {
      if (!mounted) return;
      setState(() {
        _name.text = u['name'] ?? '';
        _email.text = u['email'] ?? '';
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(controller: _name, decoration: InputDecoration(labelText: t('name'))),
      const SizedBox(height: 12),
      TextField(controller: _email, decoration: InputDecoration(labelText: t('email'))),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          onPressed: () => _guard(context, () async {
            await widget.api.updateMe(name: _name.text.trim(), email: _email.text.trim());
            if (context.mounted) _toast(context, t('saved_settings'));
          }),
          child: Text(t('save')),
        ),
      ),
    ]);
  }
}

class _PasswordSection extends StatefulWidget {
  final ImmichApi api;
  const _PasswordSection({required this.api});

  @override
  State<_PasswordSection> createState() => _PasswordSectionState();
}

class _PasswordSectionState extends State<_PasswordSection> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _logoutOthers = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
          controller: _current,
          obscureText: true,
          decoration: InputDecoration(labelText: t('linux_current_password'))),
      const SizedBox(height: 12),
      TextField(
          controller: _next, obscureText: true, decoration: InputDecoration(labelText: t('new_password'))),
      const SizedBox(height: 12),
      TextField(
          controller: _confirm,
          obscureText: true,
          decoration: InputDecoration(labelText: t('confirm_password'))),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: _logoutOthers,
        onChanged: (v) => setState(() => _logoutOthers = v!),
        title: Text(t('linux_logout_others')),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          onPressed: () {
            if (_next.text != _confirm.text) return _toast(context, t('password_does_not_match'));
            _guard(context, () async {
              await widget.api.changePassword(_current.text, _next.text, logoutOthers: _logoutOthers);
              _current.clear();
              _next.clear();
              _confirm.clear();
              if (context.mounted) _toast(context, t('linux_password_changed'));
            });
          },
          child: Text(t('change_password')),
        ),
      ),
    ]);
  }
}

class _PinSection extends StatefulWidget {
  final ImmichApi api;
  const _PinSection({required this.api});

  @override
  State<_PinSection> createState() => _PinSectionState();
}

class _PinSectionState extends State<_PinSection> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  late Future<Map<String, dynamic>> _status = widget.api.authStatus();

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget pin(TextEditingController c, String label) => TextField(
          controller: c,
          obscureText: true,
          maxLength: 6,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: label, counterText: ''),
        );
    return FutureBuilder<Map<String, dynamic>>(
      future: _status,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final hasPin = snap.data!['pinCode'] == true;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (hasPin) ...[pin(_current, t('current_pin_code')), const SizedBox(height: 12)],
          pin(_next, t('new_pin_code')),
          const SizedBox(height: 12),
          pin(_confirm, t('confirm_new_pin_code')),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () {
                if (_next.text != _confirm.text) return _toast(context, t('password_does_not_match'));
                _guard(context, () async {
                  if (hasPin) {
                    await widget.api.changePinCode(_current.text, _next.text);
                  } else {
                    await widget.api.setupPinCode(_next.text);
                  }
                  _current.clear();
                  _next.clear();
                  _confirm.clear();
                  // After first-time setup the form must switch to "change PIN".
                  if (!hasPin && mounted) setState(() => _status = widget.api.authStatus());
                  if (context.mounted) {
                    _toast(context,
                        hasPin ? t('pin_code_changed_successfully') : t('pin_code_setup_successfully'));
                  }
                });
              },
              child: Text(hasPin ? t('change_pin_code') : t('create')),
            ),
          ),
        ]);
      },
    );
  }
}

class _ApiKeysSection extends StatefulWidget {
  final ImmichApi api;
  const _ApiKeysSection({required this.api});

  @override
  State<_ApiKeysSection> createState() => _ApiKeysSectionState();
}

class _ApiKeysSectionState extends State<_ApiKeysSection> {
  late Future<List<Map<String, dynamic>>> _keys = widget.api.apiKeys();

  void _reload() => setState(() => _keys = widget.api.apiKeys());

  Future<void> _create() async {
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('new_api_key')),
        content: TextField(
            controller: name, autofocus: true, decoration: InputDecoration(labelText: t('linux_key_name'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('create'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (name.text.trim().isEmpty) return _toast(context, t('api_key_empty'));
    await _guard(context, () async {
      final secret = await widget.api.createApiKey(name.text.trim());
      _reload();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('api_key')),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('api_key_description')),
            const SizedBox(height: 12),
            SelectableText(secret, style: const TextStyle(fontFamily: 'monospace')),
          ]),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: secret));
                _toast(context, t('copied_to_clipboard'));
              },
              child: Text(t('linux_copy')),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(t('linux_close'))),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _keys,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final keys = snap.data!;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (keys.isEmpty) Text(t('linux_no_api_keys')),
          for (final k in keys)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.key),
              title: Text(k['name'] ?? ''),
              subtitle: Text('${t('created')}: ${_date(k['createdAt'])}'),
              trailing: IconButton(
                tooltip: t('delete'),
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _guard(context, () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      content: Text(t('delete_api_key_prompt')),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('delete'))),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await widget.api.deleteApiKey(k['id']);
                    _reload();
                  }
                }),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
                onPressed: _create, icon: const Icon(Icons.add), label: Text(t('new_api_key'))),
          ),
        ]);
      },
    );
  }
}

class _SessionsSection extends StatefulWidget {
  final ImmichApi api;
  const _SessionsSection({required this.api});

  @override
  State<_SessionsSection> createState() => _SessionsSectionState();
}

class _SessionsSectionState extends State<_SessionsSection> {
  late Future<List<Map<String, dynamic>>> _sessions = widget.api.sessions();

  void _reload() => setState(() => _sessions = widget.api.sessions());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _sessions,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final list = snap.data!;
        if (list.isEmpty) return Text(t('no_devices'));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final s in list)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(s['current'] == true ? Icons.computer : Icons.devices_other),
              title: Text([s['deviceOS'], s['deviceType']]
                  .whereType<String>()
                  .where((x) => x.isNotEmpty)
                  .join(' · ')),
              subtitle: Text(s['current'] == true
                  ? t('current_device')
                  : '${t('last_seen')}: ${_date(s['updatedAt'])}'),
              trailing: s['current'] == true
                  ? null
                  : TextButton(
                      onPressed: () => _guard(context, () async {
                        await widget.api.deleteSession(s['id']);
                        if (context.mounted) _toast(context, t('logged_out_device'));
                        _reload();
                      }),
                      child: Text(t('log_out')),
                    ),
            ),
          if (list.length > 1)
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: () => _guard(context, () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      content: Text(t('logout_all_device_confirmation')),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('log_out'))),
                      ],
                    ),
                  );
                  if (ok != true) return;
                  await widget.api.deleteOtherSessions();
                  if (context.mounted) _toast(context, t('logged_out_all_devices'));
                  _reload();
                }),
                child: Text(t('log_out_all_devices')),
              ),
            ),
        ]);
      },
    );
  }
}
