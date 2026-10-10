// System settings (web: /admin/system-settings). The form layout — sections,
// groups, labels and config paths — is generated from the web source by
// tool/gen_system_settings.py into assets/admin/system_settings.json.
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../api.dart';
import '../i18n.dart';
import '../widgets/asset_actions.dart' show downloadsDir;
import 'admin.dart' show queueTitleKeys;

dynamic getPath(Map<String, dynamic> m, String path) {
  dynamic v = m;
  for (final k in path.split('.')) {
    if (v is! Map) return null;
    v = v[k];
  }
  return v;
}

void setPath(Map<String, dynamic> m, String path, dynamic value) {
  final parts = path.split('.');
  Map<String, dynamic> cur = m;
  for (final k in parts.take(parts.length - 1)) {
    cur = (cur[k] ??= <String, dynamic>{}) as Map<String, dynamic>;
  }
  cur[parts.last] = value;
}

Map<String, dynamic> _deepCopy(Map<String, dynamic> m) =>
    jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

class SystemSettingsScreen extends StatefulWidget {
  final ImmichApi api;
  const SystemSettingsScreen({super.key, required this.api});

  @override
  State<SystemSettingsScreen> createState() => _SystemSettingsScreenState();
}

class _SystemSettingsScreenState extends State<SystemSettingsScreen> {
  List<Map<String, dynamic>>? _sections;
  Map<String, dynamic>? _saved;
  Map<String, dynamic>? _edit;
  Map<String, dynamic>? _defaults;
  Object? _error;
  String _filter = '';
  // Bumped when values change from outside a text field (save/reset/import),
  // so the fields reload; typing must not rebuild them.
  int _rev = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final spec = jsonDecode(await rootBundle.loadString('assets/admin/system_settings.json'));
      final cfg = await widget.api.systemConfig();
      final defaults = await widget.api.systemConfigDefaults();
      setState(() {
        _sections = (spec['sections'] as List).cast<Map<String, dynamic>>();
        _saved = cfg;
        _edit = _deepCopy(cfg);
        _defaults = defaults;
      });
    } catch (e) {
      setState(() => _error = e);
    }
  }

  /// Concrete config paths for an item (expands job[queueName] per queue).
  List<String> _paths(Map<String, dynamic> item) {
    final path = item['path'] as String;
    final m = RegExp(r'^(\w+)\[\w+\]\.(\w+)$').firstMatch(path);
    if (m == null) return [path];
    final parent = getPath(_edit!, m[1]!) as Map? ?? {};
    return [for (final k in parent.keys) '${m[1]}.$k.${m[2]}'];
  }

  bool _matches(Map<String, dynamic> s) {
    if (_filter.isEmpty) return true;
    bool has(String? key) => key != null && t(key).toLowerCase().contains(_filter);
    return has(s['title']) ||
        has(s['subtitle']) ||
        (s['items'] as List).any((i) => has(i['title']) || has(i['group']) || has(i['desc']));
  }

  Future<void> _save([Map<String, dynamic>? section]) async {
    final messenger = ScaffoldMessenger.of(context);
    // Like the web, a section's Save sends only that section's changes; unsaved
    // edits in other sections stay pending in the form.
    final paths = section == null
        ? null
        : [
            for (final item in (section['items'] as List).cast<Map<String, dynamic>>())
              if (item['path'] != null) ..._paths(item),
          ];
    final payload = paths == null ? _edit! : _deepCopy(_saved!);
    for (final path in paths ?? const <String>[]) {
      setPath(payload, path, jsonDecode(jsonEncode(getPath(_edit!, path))));
    }
    try {
      final result = await widget.api.updateSystemConfig(payload);
      setState(() {
        final edit = paths == null ? _deepCopy(result) : _deepCopy(_edit!);
        for (final path in paths ?? const <String>[]) {
          setPath(edit, path, jsonDecode(jsonEncode(getPath(result, path))));
        }
        _saved = result;
        _edit = edit;
        _rev++;
      });
      messenger.showSnackBar(SnackBar(content: Text(t('settings_saved'))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('${t('errors.unable_to_update_settings')}: $e')));
    }
  }

  void _resetSection(Map<String, dynamic> section) {
    setState(() {
      _rev++;
      for (final item in (section['items'] as List).cast<Map<String, dynamic>>()) {
        if (item['path'] == null) continue;
        for (final path in _paths(item)) {
          setPath(_edit!, path, jsonDecode(jsonEncode(getPath(_defaults!, path))));
        }
      }
    });
  }

  Future<void> _export() async {
    final dir = await downloadsDir();
    final f = File(p.join(dir.path, 'immich-config.json'));
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(_saved));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t('linux_exported', {'path': f.path}))));
    }
  }

  Future<void> _import() async {
    final file = await openFile(acceptedTypeGroups: [
      const XTypeGroup(label: 'JSON', extensions: ['json']),
    ]);
    if (file == null) return;
    try {
      final cfg = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      setState(() {
        _edit = cfg;
        _rev++;
      });
      await _save();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t('error')}: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text('${t('error')}: $_error'));
    final sections = _sections;
    if (sections == null) return const Center(child: CircularProgressIndicator());
    return ListView(padding: const EdgeInsets.all(24), children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: t('search_settings'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(
                      text: const JsonEncoder.withIndent('  ').convert(_saved)));
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(t('copied_to_clipboard'))));
                },
                icon: const Icon(Icons.copy, size: 18),
                label: Text(t('copy_to_clipboard')),
              ),
              TextButton.icon(
                  onPressed: _export,
                  icon: const Icon(Icons.download, size: 18),
                  label: Text(t('export_as_json'))),
              TextButton.icon(
                  onPressed: _import,
                  icon: const Icon(Icons.upload, size: 18),
                  label: Text(t('import_from_json'))),
            ]),
            const SizedBox(height: 12),
            for (final s in sections.where(_matches)) _section(s),
          ]),
        ),
      ),
    ]);
  }

  Widget _section(Map<String, dynamic> s) {
    final items = (s['items'] as List).cast<Map<String, dynamic>>();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: ValueKey(s['key']),
        initiallyExpanded: _filter.isNotEmpty,
        title: Text(t(s['title'])),
        subtitle: Text(t(s['subtitle'])),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in items)
            if (item['group'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 20, bottom: 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t(item['group']), style: Theme.of(context).textTheme.titleSmall),
                  if (item['desc'] != null)
                    Text(t(item['desc']), style: Theme.of(context).textTheme.bodySmall),
                ]),
              )
            else
              for (final path in _paths(item)) _safeField(item, path),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => _resetSection(s), child: Text(t('reset_to_default'))),
            const SizedBox(width: 8),
            FilledButton(onPressed: () => _save(s), child: Text(t('save'))),
          ]),
        ],
      ),
    );
  }

  /// One unexpected value shape must not break the whole page: fall back to raw JSON.
  Widget _safeField(Map<String, dynamic> item, String path) {
    try {
      return _field(item, path);
    } catch (_) {
      final value = getPath(_edit!, path);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: _TextSetting(
          key: ValueKey('$path:$_rev:raw'),
          label: Text(item['title'] != null ? t(item['title']) : (item['label'] as String? ?? path)),
          desc: path,
          initial: jsonEncode(value),
          onChanged: (v) {
            try {
              setPath(_edit!, path, jsonDecode(v));
            } catch (_) {}
          },
        ),
      );
    }
  }

  Widget _field(Map<String, dynamic> item, String path) {
    final theme = Theme.of(context);
    final value = getPath(_edit!, path);
    final edited = jsonEncode(value) != jsonEncode(getPath(_saved!, path));
    var title = item['title'] != null ? t(item['title']) : (item['label'] as String? ?? path);
    // job.<queue>.concurrency → "<Queue name> concurrency", as on the web.
    final jobMatch = RegExp(r'^job\.(\w+)\.concurrency$').firstMatch(path);
    if (jobMatch != null) {
      final q = queueTitleKeys[jobMatch[1]];
      title = t('admin.job_concurrency', {'job': q != null ? t(q) : jobMatch[1]});
    }
    final desc = item['desc'] != null ? t(item['desc']) : null;
    void set(dynamic v) => setState(() => setPath(_edit!, path, v));
    final label = Row(children: [
      Flexible(child: Text(title)),
      if (edited) ...[
        const SizedBox(width: 6),
        Text(t('linux_edited'), style: TextStyle(color: theme.colorScheme.primary, fontSize: 12)),
      ],
    ]);
    Widget sub(Widget w) => Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: w);

    switch (item['kind']) {
      case 'bool':
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: label,
          subtitle: desc == null ? null : Text(desc),
          value: value == true,
          onChanged: set,
        );
      case 'enum':
        // Options are either plain values (OpenAPI enum) or {value, text|textKey} from the web form.
        final options = <(dynamic, String)>[
          for (final o in (item['options'] as List? ?? const []))
            o is Map
                ? (o['value'], o['textKey'] != null ? t(o['textKey']) : '${o['text']}')
                : (o, '$o'),
        ];
        return sub(Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              label,
              if (desc != null) Text(desc, style: theme.textTheme.bodySmall),
            ]),
          ),
          DropdownButton<Object>(
            value: options.any((o) => o.$1 == value) ? value as Object : null,
            items: [for (final o in options) DropdownMenuItem(value: o.$1 as Object, child: Text(o.$2))],
            onChanged: set,
          ),
        ]));
      case 'list':
        final options = item['options'] as List?;
        if (options != null) {
          // Keep original value types (strings or numbers) when toggling chips.
          final selected = List<dynamic>.from(value as List? ?? const []);
          return sub(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            label,
            if (desc != null) Text(desc, style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final o in options)
                FilterChip(
                  label: Text('$o'),
                  selected: selected.contains(o),
                  onSelected: (on) => set(on ? [...selected, o] : selected.where((x) => x != o).toList()),
                ),
            ]),
          ]));
        }
        final list = (value as List?)?.map((e) => '$e').toList() ?? [];
        return sub(_TextSetting(
          key: ValueKey('$path:$_rev'),
          label: label,
          desc: desc ?? t('linux_list_hint'),
          initial: list.join('\n'),
          maxLines: 4,
          onChanged: (v) => set(v.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()),
        ));
      case 'int':
      case 'num':
        return sub(_TextSetting(
          key: ValueKey('$path:$_rev'),
          label: label,
          desc: desc,
          initial: value == null ? '' : '$value',
          number: true,
          onChanged: (v) {
            final n = item['kind'] == 'int' ? int.tryParse(v) : num.tryParse(v);
            if (n != null) set(n);
          },
        ));
      default:
        return sub(_TextSetting(
          key: ValueKey('$path:$_rev'),
          label: label,
          desc: desc,
          initial: value == null ? '' : '$value',
          maxLines: item['kind'] == 'text' ? 6 : 1,
          onChanged: (v) => set(v),
        ));
    }
  }
}

/// Text field that keeps its own controller; rebuilt (via key) when the value
/// changes from outside (reset, import).
class _TextSetting extends StatefulWidget {
  final Widget label;
  final String? desc;
  final String initial;
  final bool number;
  final int maxLines;
  final ValueChanged<String> onChanged;

  const _TextSetting({
    super.key,
    required this.label,
    required this.desc,
    required this.initial,
    required this.onChanged,
    this.number = false,
    this.maxLines = 1,
  });

  @override
  State<_TextSetting> createState() => _TextSettingState();
}

class _TextSettingState extends State<_TextSetting> {
  late final _ctl = TextEditingController(text: widget.initial);
  late final _focus = FocusNode();

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      widget.label,
      if (widget.desc != null) Text(widget.desc!, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 6),
      TextField(
        controller: _ctl,
        focusNode: _focus,
        maxLines: widget.maxLines,
        keyboardType: widget.number ? TextInputType.number : null,
        decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
        onChanged: widget.onChanged,
      ),
    ]);
  }
}
