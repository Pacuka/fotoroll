// "App Settings" (web: user settings → App Settings): language and theme.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n.dart';
import '../settings.dart';
import '../window.dart';

/// Language and theme controls (web: App Settings).
class AppSettingsBody extends StatelessWidget {
  const AppSettingsBody({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([settings, i18n]),
      builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.language),
          title: Text(t('language')),
          subtitle: Text(t('language_setting_description')),
          trailing: OutlinedButton(
            onPressed: () => _pickLanguage(context),
            child: Text(languageNames[settings.language] ?? settings.language),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.brightness_6_outlined),
          title: Text(t('theme')),
          subtitle: Text(t('theme_selection')),
        ),
        // Below the title, so long translations never squeeze it.
        Padding(
          padding: const EdgeInsets.only(left: 40),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(value: ThemeMode.system, label: Text(t('linux_theme_system'))),
                ButtonSegment(value: ThemeMode.light, label: Text(t('light'))),
                ButtonSegment(value: ThemeMode.dark, label: Text(t('dark'))),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (s) => settings.update(themeMode: s.first),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const _DesktopSettings(),
        const SizedBox(height: 8),
        FutureBuilder<String>(
          future: rootBundle.loadString('assets/i18n/VERSION').catchError((_) => ''),
          builder: (context, snap) => Text(
            t('linux_translations_source', {'version': (snap.data ?? '').trim()}),
            style: theme.textTheme.bodySmall,
          ),
        ),
      ]),
    );
  }

  Future<void> _pickLanguage(BuildContext context) async {
    final code = await showDialog<String>(context: context, builder: (_) => const _LanguageDialog());
    if (code != null) await settings.update(language: code);
  }
}

class _LanguageDialog extends StatefulWidget {
  const _LanguageDialog();

  @override
  State<_LanguageDialog> createState() => _LanguageDialogState();
}

class _LanguageDialogState extends State<_LanguageDialog> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final entries = languageNames.entries
        .where((e) =>
            _filter.isEmpty ||
            e.value.toLowerCase().contains(_filter) ||
            e.key.toLowerCase().contains(_filter))
        .toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    return AlertDialog(
      title: Text(t('language')),
      content: SizedBox(
        width: 380,
        height: 480,
        child: Column(children: [
          TextField(
            autofocus: true,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: t('language_search_hint'),
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: entries.isEmpty
                ? Center(child: Text(t('language_no_results_title')))
                : RadioGroup<String>(
                    groupValue: settings.language,
                    onChanged: (v) => Navigator.pop(context, v),
                    child: ListView(children: [
                      for (final e in entries)
                        RadioListTile<String>(value: e.key, title: Text(e.value)),
                    ]),
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

/// Tray and autostart (desktop only, no web equivalent).
class _DesktopSettings extends StatefulWidget {
  const _DesktopSettings();

  @override
  State<_DesktopSettings> createState() => _DesktopSettingsState();
}

class _DesktopSettingsState extends State<_DesktopSettings> {
  bool _autostart = autostartEnabled;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: trayAvailable,
      builder: (context, tray, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.vertical_align_bottom),
          title: Text(t('linux_close_to_tray')),
          subtitle: Text(tray ? t('linux_close_to_tray_desc') : t('linux_no_tray')),
          value: tray && settings.closeToTray,
          onChanged: tray ? (v) => settings.update(closeToTray: v) : null,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.power_settings_new),
          title: Text(t('linux_autostart')),
          subtitle: Text(t('linux_autostart_desc')),
          value: _autostart,
          onChanged: (v) async {
            await setAutostart(v);
            if (mounted) setState(() => _autostart = autostartEnabled);
          },
        ),
      ]),
    );
  }
}
