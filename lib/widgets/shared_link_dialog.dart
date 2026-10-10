// Create or edit a shared link (web: SharedLinkCreateModal / shared-links/[id]/edit).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../i18n.dart';

/// Expiry choices offered by the web, as durations from now (null = never).
final _expiries = <(Duration?, String Function())>[
  (null, () => t('never')),
  (const Duration(minutes: 30), () => t('shared_link_edit_expire_after_option_minutes', {'count': 30})),
  (const Duration(hours: 1), () => t('shared_link_edit_expire_after_option_hour')),
  (const Duration(hours: 6), () => t('shared_link_edit_expire_after_option_hours', {'count': 6})),
  (const Duration(days: 1), () => t('shared_link_edit_expire_after_option_day')),
  (const Duration(days: 7), () => t('shared_link_edit_expire_after_option_days', {'count': 7})),
  (const Duration(days: 30), () => t('shared_link_edit_expire_after_option_days', {'count': 30})),
  (const Duration(days: 90), () => t('shared_link_edit_expire_after_option_months', {'count': 3})),
  (const Duration(days: 365), () => t('shared_link_edit_expire_after_option_year', {'count': 1})),
];

/// Creates a link for [albumId] or [assetIds], or edits [existing]. Returns the link.
Future<Map<String, dynamic>?> showSharedLinkDialog(
  BuildContext context,
  ImmichApi api, {
  String? albumId,
  List<String>? assetIds,
  Map<String, dynamic>? existing,
}) =>
    showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _SharedLinkDialog(api: api, albumId: albumId, assetIds: assetIds, existing: existing),
    );

class _SharedLinkDialog extends StatefulWidget {
  final ImmichApi api;
  final String? albumId;
  final List<String>? assetIds;
  final Map<String, dynamic>? existing;
  const _SharedLinkDialog({required this.api, this.albumId, this.assetIds, this.existing});

  @override
  State<_SharedLinkDialog> createState() => _SharedLinkDialogState();
}

class _SharedLinkDialogState extends State<_SharedLinkDialog> {
  late final _desc = TextEditingController(text: widget.existing?['description'] ?? '');
  late final _slug = TextEditingController(text: widget.existing?['slug'] ?? '');
  late final _password = TextEditingController(text: widget.existing?['password'] ?? '');
  late bool _download = widget.existing?['allowDownload'] ?? true;
  late bool _upload = widget.existing?['allowUpload'] ?? false;
  late bool _metadata = widget.existing?['showMetadata'] ?? true;
  int _expiry = 0;
  bool _changeExpiry = false;
  Map<String, dynamic>? _created;
  bool _busy = false;

  @override
  void dispose() {
    _desc.dispose();
    _slug.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final d = _expiries[_expiry].$1;
    final expiresAt = d == null ? null : DateTime.now().add(d);
    try {
      if (widget.existing != null) {
        final link = await widget.api.updateSharedLink(widget.existing!['id'], {
          'description': _desc.text,
          'slug': _slug.text.trim().isEmpty ? null : _slug.text.trim(),
          'password': _password.text.isEmpty ? null : _password.text,
          'allowDownload': _download,
          'allowUpload': _upload,
          'showMetadata': _metadata,
          if (_changeExpiry) 'expiresAt': expiresAt?.toUtc().toIso8601String(),
        });
        if (mounted) Navigator.pop(context, link);
      } else {
        final link = await widget.api.createSharedLink(
          albumId: widget.albumId,
          assetIds: widget.assetIds,
          description: _desc.text.isEmpty ? null : _desc.text,
          password: _password.text.isEmpty ? null : _password.text,
          slug: _slug.text.trim().isEmpty ? null : _slug.text.trim(),
          expiresAt: expiresAt,
          allowDownload: _download,
          allowUpload: _upload,
          showMetadata: _metadata,
        );
        setState(() => _created = link);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${t('shared_link_create_error')}: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final created = _created;
    if (created != null) {
      final url = widget.api.sharedLinkUrl(created);
      return AlertDialog(
        title: Text(t('linux_link_created')),
        content: SizedBox(
          width: 460,
          child: Row(children: [
            Expanded(child: SelectableText(url)),
            IconButton(
              tooltip: t('copy_link_to_clipboard'),
              icon: const Icon(Icons.copy),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: url));
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(t('shared_link_clipboard_copied_massage'))));
              },
            ),
          ]),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(context, created), child: Text(t('done')))],
      );
    }
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? t('edit_link') : t('create_link_to_share')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.albumId != null || widget.existing?['type'] == 'ALBUM'
                ? t('album_with_link_access')
                : t('create_link_to_share_description')),
            const SizedBox(height: 12),
            TextField(
              controller: _desc,
              decoration: InputDecoration(labelText: t('description'), hintText: t('shared_link_edit_description_hint')),
            ),
            TextField(
              controller: _slug,
              decoration: InputDecoration(
                labelText: t('shared_link_custom_url_title'),
                helperText: t('shared_link_custom_url_description'),
              ),
            ),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(
                labelText: t('password'),
                helperText: t('shared_link_password_description'),
              ),
            ),
            const SizedBox(height: 8),
            if (editing)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _changeExpiry,
                onChanged: (v) => setState(() => _changeExpiry = v!),
                title: Text(t('expire_after')),
              ),
            if (!editing || _changeExpiry)
              DropdownButtonFormField<int>(
                initialValue: _expiry,
                decoration: InputDecoration(labelText: t('expire_after')),
                items: [
                  for (var i = 0; i < _expiries.length; i++)
                    DropdownMenuItem(value: i, child: Text(_expiries[i].$2())),
                ],
                onChanged: (v) => setState(() => _expiry = v!),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t('show_metadata')),
              value: _metadata,
              onChanged: (v) => setState(() => _metadata = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t('allow_public_user_to_download')),
              value: _download,
              onChanged: (v) => setState(() => _download = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t('allow_public_user_to_upload')),
              value: _upload,
              onChanged: (v) => setState(() => _upload = v),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t('cancel'))),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(editing ? t('shared_link_edit_submit_button') : t('create_link')),
        ),
      ],
    );
  }
}
