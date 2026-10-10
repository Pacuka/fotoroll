// Backup page, laid out like the mobile app's: folder selection, counters,
// current upload, options, and failed files.
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../backup.dart';
import '../i18n.dart';

class BackupScreen extends StatelessWidget {
  final BackupService service;
  const BackupScreen({super.key, required this.service});

  Future<void> _pick(BuildContext context, {required bool exclude}) async {
    final home = Platform.environment['HOME'];
    final dir = await getDirectoryPath(
      initialDirectory: exclude && service.settings.folders.isNotEmpty
          ? service.settings.folders.first
          : home,
      confirmButtonText: t('select'),
    );
    if (dir == null) return;
    if (exclude && !service.settings.folders.any((f) => p.isWithin(f, dir))) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('linux_exclude_outside')),
        ));
      }
      return;
    }
    await service.updateSettings((s) => (exclude ? s.excluded : s.folders).add(dir));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final s = service.settings;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _statusCard(context),
                  const SizedBox(height: 16),
                  _foldersCard(context, s),
                  const SizedBox(height: 16),
                  _countersRow(context),
                  if (service.currentFile != null) ...[
                    const SizedBox(height: 16),
                    _currentUploadCard(context),
                  ],
                  const SizedBox(height: 16),
                  _optionsCard(context, s),
                  if (service.errors.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _errorsCard(context),
                  ],
                ]),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _statusCard(BuildContext context) {
    final theme = Theme.of(context);
    final s = service.settings;
    final (icon, text) = switch (service.phase) {
      _ when !s.enabled => (Icons.cloud_off, t('linux_backup_off')),
      _ when s.folders.isEmpty => (Icons.folder_off, t('linux_backup_no_folders')),
      BackupPhase.scanning => (Icons.manage_search, t('linux_backup_scanning')),
      BackupPhase.hashing => (Icons.fingerprint, t('linux_backup_hashing', {'progress': service.phaseMessage ?? ''})),
      BackupPhase.checking => (Icons.cloud_sync, t('linux_backup_checking')),
      BackupPhase.uploading => (Icons.cloud_upload, t('uploading')),
      BackupPhase.stopped => (Icons.pause_circle, t('linux_backup_stopped')),
      BackupPhase.error => (Icons.error_outline, '${t('error')}: ${service.phaseMessage}'),
      BackupPhase.idle => (
          Icons.cloud_done,
          service.remaining == 0 && service.total > 0
              ? t('linux_backup_all_done')
              : service.lastRun == null
                  ? t('waiting')
                  : t('linux_backup_last_check', {'time': DateFormat.Hm(i18n.dateLocale).format(service.lastRun!)})
        ),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(t('linux_backup_auto'), style: theme.textTheme.titleMedium),
            subtitle: Text(t('linux_backup_auto_sub')),
            value: s.enabled,
            onChanged: (v) => service.updateSettings((s) => s.enabled = v),
          ),
          const Divider(),
          Row(children: [
            if (service.isRunning)
              const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
            else
              Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
            if (service.isRunning)
              OutlinedButton.icon(
                onPressed: service.stop,
                icon: const Icon(Icons.stop),
                label: Text(t('linux_backup_stop')),
              )
            else
              FilledButton.icon(
                onPressed: s.folders.isEmpty ? null : service.runNow,
                icon: const Icon(Icons.backup),
                label: Text(t('linux_backup_now')),
              ),
          ]),
        ]),
      ),
    );
  }

  Widget _foldersCard(BuildContext context, BackupSettings s) {
    final theme = Theme.of(context);
    String short(String path) {
      final home = Platform.environment['HOME'];
      return home != null && p.isWithin(home, path) ? '~/${p.relative(path, from: home)}' : path;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('linux_backup_folders'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(t('linux_backup_folders_sub'),
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final f in s.folders)
              InputChip(
                avatar: const Icon(Icons.folder, size: 18),
                label: Text(short(f)),
                backgroundColor: theme.colorScheme.primaryContainer,
                onDeleted: () => service.updateSettings((s) => s.folders.remove(f)),
              ),
            for (final f in s.excluded)
              InputChip(
                avatar: const Icon(Icons.block, size: 18),
                label: Text(short(f)),
                backgroundColor: theme.colorScheme.errorContainer,
                onDeleted: () => service.updateSettings((s) => s.excluded.remove(f)),
              ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            FilledButton.tonalIcon(
              onPressed: () => _pick(context, exclude: false),
              icon: const Icon(Icons.create_new_folder_outlined),
              label: Text(t('linux_add_folder')),
            ),
            TextButton.icon(
              onPressed: s.folders.isEmpty ? null : () => _pick(context, exclude: true),
              icon: const Icon(Icons.block),
              label: Text(t('linux_exclude_folder')),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _countersRow(BuildContext context) {
    Widget counter(String label, int value, IconData icon) => Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Icon(icon),
                const SizedBox(height: 8),
                Text(NumberFormat.decimalPattern(i18n.dateLocale).format(value),
                    style: Theme.of(context).textTheme.headlineSmall),
                Text(label),
              ]),
            ),
          ),
        );
    return Row(children: [
      counter(t('total'), service.total, Icons.photo_library_outlined),
      const SizedBox(width: 8),
      counter(t('linux_backed_up'), service.backedUp, Icons.cloud_done_outlined),
      const SizedBox(width: 8),
      counter(t('backup_controller_page_remainder'), service.remaining, Icons.pending_outlined),
    ]);
  }

  Widget _currentUploadCard(BuildContext context) {
    final total = service.currentTotal;
    final frac = total > 0 ? service.currentSent / total : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('uploading'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(p.basename(service.currentFile!), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: frac),
          const SizedBox(height: 6),
          Text('${_fmt(service.currentSent)} / ${_fmt(total)}'
              '${service.bytesPerSecond > 0 ? '  ·  ${_fmt(service.bytesPerSecond.round())}/s' : ''}'),
        ]),
      ),
    );
  }

  Widget _optionsCard(BuildContext context, BackupSettings s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(children: [
          ListTile(
            title: Text(t('linux_scan_interval')),
            subtitle: Text(t('linux_scan_interval_sub')),
            trailing: DropdownButton<int>(
              value: s.scanIntervalMinutes,
              items: [
                for (final m in const [5, 15, 30])
                  DropdownMenuItem(value: m, child: Text(t('linux_minutes', {'count': m}))),
                DropdownMenuItem(value: 60, child: Text(t('interval.hours', {'hours': 1}))),
              ],
              onChanged: (v) => service.updateSettings((s) => s.scanIntervalMinutes = v!),
            ),
          ),
          SwitchListTile(
            title: Text(t('linux_skip_hidden')),
            subtitle: Text(t('linux_skip_hidden_sub')),
            value: s.skipHidden,
            onChanged: (v) => service.updateSettings((s) => s.skipHidden = v),
          ),
        ]),
      ),
    );
  }

  Widget _errorsCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ExpansionTile(
        leading: Icon(Icons.warning_amber, color: theme.colorScheme.error),
        title: Text(t('linux_failed_files', {'count': service.errors.length})),
        children: [
          for (final e in service.errors.take(50))
            ListTile(
              dense: true,
              title: Text(p.basename(e.path)),
              subtitle: Text('${e.message}\n${e.path}'),
              isThreeLine: true,
            ),
        ],
      ),
    );
  }

  static String _fmt(int b) {
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}
