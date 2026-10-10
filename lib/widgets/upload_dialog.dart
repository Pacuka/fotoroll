// "Upload" button flow: pick files, upload one by one with progress, show a summary.
import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../api.dart';
import '../i18n.dart';

/// Returns true if anything new was uploaded.
Future<bool> pickAndUpload(BuildContext context, ImmichApi api) async {
  final Set<String> exts;
  try {
    exts = await api.mediaExtensions();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t('error')}: $e')));
    }
    return false;
  }
  final files = await openFiles(
    acceptedTypeGroups: [
      XTypeGroup(
        label: t('linux_photos_and_videos'),
        extensions: [for (final e in exts) e.substring(1)],
      ),
    ],
    confirmButtonText: t('upload'),
  );
  if (files.isEmpty || !context.mounted) return false;
  final created = await showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UploadDialog(api: api, paths: [for (final f in files) f.path]),
  );
  return (created ?? 0) > 0;
}

class _UploadDialog extends StatefulWidget {
  final ImmichApi api;
  final List<String> paths;
  const _UploadDialog({required this.api, required this.paths});

  @override
  State<_UploadDialog> createState() => _UploadDialogState();
}

class _UploadDialogState extends State<_UploadDialog> {
  int _index = 0;
  double _fileProgress = 0;
  int _created = 0;
  int _duplicates = 0;
  final _failed = <String>[];
  bool _done = false;
  final _abort = Completer<void>();

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    for (; _index < widget.paths.length; _index++) {
      if (_abort.isCompleted) break;
      final path = widget.paths[_index];
      setState(() => _fileProgress = 0);
      try {
        final f = File(path);
        final st = await f.stat();
        final res = await widget.api.uploadAsset(
          f,
          createdAt: st.modified,
          modifiedAt: st.modified,
          abortTrigger: _abort.future,
          onProgress: (sent, total) {
            if (mounted && total > 0) setState(() => _fileProgress = sent / total);
          },
        );
        if (res.duplicate) {
          _duplicates++;
        } else {
          _created++;
        }
      } catch (e) {
        if (_abort.isCompleted) break;
        _failed.add('${p.basename(path)}: $e');
      }
    }
    if (mounted) setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.paths.length;
    return AlertDialog(
      title: Text(_done
          ? t('linux_upload_done')
          : t('linux_upload_progress', {'current': _index + 1, 'total': n})),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!_done) ...[
            Text(p.basename(widget.paths[_index.clamp(0, n - 1)]), overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _fileProgress),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: n == 0 ? 0 : _index / n, minHeight: 2),
          ] else ...[
            Text(t('linux_uploaded_count', {'count': _created})),
            if (_duplicates > 0) Text(t('linux_already_uploaded_count', {'count': _duplicates})),
            if (_failed.isNotEmpty) ...[
              Text(t('linux_failed_count', {'count': _failed.length}),
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: ListView(shrinkWrap: true, children: [
                  for (final f in _failed) Text(f, style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
            ],
          ],
        ]),
      ),
      actions: [
        if (!_done)
          TextButton(
            onPressed: () => _abort.isCompleted ? null : _abort.complete(),
            child: Text(t('cancel')),
          )
        else
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_created),
            child: Text(t('linux_ok')),
          ),
      ],
    );
  }
}
