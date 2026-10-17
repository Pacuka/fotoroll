// Comments and likes in shared albums (web: activity-manager, ActivityStatus and
// ActivityViewer): for the album itself or for one photo of it.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../i18n.dart';
import 'user_avatar.dart';

/// The activity of [album] (or of one photo, [assetId]) and what the user can do with it.
class ActivityState extends ChangeNotifier {
  final ImmichApi api;
  /// Replaced when the album changes (e.g. comments switched off).
  Album album;
  final String? assetId;
  ActivityState(this.api, this.album, {this.assetId});

  List<Map<String, dynamic>> items = const [];
  bool loaded = false;
  String? myId;

  /// Web: the status pill shows in shared albums with comments on, or with comments to read.
  bool get visible => album.albumUsers.isNotEmpty && loaded && (album.isActivityEnabled || commentCount > 0);
  bool get enabled => album.isActivityEnabled;
  int get commentCount => items.where((a) => a['type'] == 'comment').length;
  int get likeCount => items.where((a) => a['type'] == 'like' && a['assetId'] == assetId).length;
  Map<String, dynamic>? get myLike => items
      .where((a) => a['type'] == 'like' && a['assetId'] == assetId && a['user']?['id'] == myId)
      .firstOrNull;

  /// Web: the author and the album owner may delete.
  bool canDelete(Map<String, dynamic> a) => a['user']?['id'] == myId || album.ownerId == myId;

  Future<void> load() async {
    myId ??= await api.myId();
    items = await api.activities(album.id, assetId: assetId);
    loaded = true;
    notifyListeners();
  }

  Future<void> toggleLike() async {
    final like = myLike;
    if (like != null) {
      await api.deleteActivity(like['id']);
    } else {
      await api.addActivity(album.id, 'like', assetId: assetId);
    }
    await load();
  }

  Future<void> comment(String text) async {
    await api.addActivity(album.id, 'comment', assetId: assetId, comment: text);
    await load();
  }

  Future<void> delete(Map<String, dynamic> a) async {
    await api.deleteActivity(a['id']);
    await load();
  }
}

/// Like and comment buttons with their counts (web: ActivityStatus).
class ActivityStatusPill extends StatelessWidget {
  final ActivityState state;
  final VoidCallback onComments;
  const ActivityStatusPill({super.key, required this.state, required this.onComments});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final liked = state.myLike != null;
    return Material(
      color: scheme.surfaceContainerHigh.withValues(alpha: 0.9),
      shape: const StadiumBorder(),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          TextButton.icon(
            onPressed: state.enabled ? () => _run(context, state.toggleLike) : null,
            icon: Icon(liked ? Icons.thumb_up : Icons.thumb_up_outlined),
            label: Text(state.likeCount == 0 ? '' : '${state.likeCount}'),
            style: TextButton.styleFrom(foregroundColor: liked ? scheme.primary : scheme.onSurface),
          ),
          Tooltip(
            message: t('comments_and_likes'),
            child: TextButton.icon(
              onPressed: onComments,
              icon: const Icon(Icons.mode_comment_outlined),
              label: Text(state.commentCount == 0 ? '' : '${state.commentCount}'),
              style: TextButton.styleFrom(foregroundColor: scheme.onSurface),
            ),
          ),
        ]),
      ),
    );
  }
}

Future<void> _run(BuildContext context, Future<void> Function() f) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await f();
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('${t('error')}: $e')));
  }
}

/// The comments and likes, newest at the bottom, and a field to comment (web: ActivityViewer).
class ActivityPanel extends StatefulWidget {
  final ActivityState state;
  final VoidCallback onClose;
  const ActivityPanel({super.key, required this.state, required this.onClose});

  @override
  State<ActivityPanel> createState() => _ActivityPanelState();
}

class _ActivityPanelState extends State<ActivityPanel> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  ActivityState get state => widget.state;

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    await _run(context, () async {
      await state.comment(text);
      _text.clear();
    });
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _delete(Map<String, dynamic> a) async {
    final messenger = ScaffoldMessenger.of(context);
    await _run(context, () async {
      await state.delete(a);
      messenger.showSnackBar(SnackBar(content: Text(t(a['type'] == 'like' ? 'like_deleted' : 'comment_deleted'))));
    });
  }

  Widget _item(BuildContext context, Map<String, dynamic> a) {
    final theme = Theme.of(context);
    final user = (a['user'] as Map?)?.cast<String, dynamic>() ?? const {};
    final when = DateTime.tryParse(a['createdAt'] ?? '')?.toLocal();
    final isLike = a['type'] == 'like';
    // In the album's panel, activity on a photo shows that photo.
    final photo = state.assetId == null ? a['assetId'] as String? : null;
    return ListTile(
      key: ValueKey('activity-${a['id']}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: isLike
          ? Icon(Icons.thumb_up, color: theme.colorScheme.primary)
          : UserAvatar(api: state.api, user: user, radius: 16),
      title: Text(isLike ? t('user_liked', {'user': user['name'] ?? '', 'type': photo == null && state.assetId == null ? 'other' : 'photo'}) : '${a['comment'] ?? ''}'),
      subtitle: Text([
        if (!isLike) user['name'] ?? '',
        if (when != null) DateFormat.yMMMd(i18n.dateLocale).add_Hm().format(when),
      ].join(' · ')),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (photo != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.network(state.api.thumbnailUrl(photo),
                headers: state.api.headers, width: 40, height: 40, fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox(width: 40)),
          ),
        if (state.canDelete(a))
          MenuAnchor(
            menuChildren: [
              MenuItemButton(
                leadingIcon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(a),
                child: Text(t('delete')),
              ),
            ],
            builder: (context, ctl, _) => IconButton(
              tooltip: t(isLike ? 'reaction_options' : 'comment_options'),
              icon: const Icon(Icons.more_vert, size: 20),
              onPressed: () => ctl.isOpen ? ctl.close() : ctl.open(),
            ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ListTile(
            title: Text(t('activity'), style: theme.textTheme.titleMedium),
            trailing: IconButton(tooltip: t('close'), icon: const Icon(Icons.close), onPressed: widget.onClose),
          ),
          const Divider(height: 1),
          Expanded(
            child: !state.loaded
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    controller: _scroll,
                    reverse: true, // newest at the bottom, next to the field
                    children: [for (final a in state.items.reversed) _item(context, a)],
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: state.enabled
                ? TextField(
                    controller: _text,
                    enabled: !_sending,
                    decoration: InputDecoration(
                      hintText: t('say_something'),
                      suffixIcon: IconButton(
                        tooltip: t('send_message'),
                        icon: const Icon(Icons.send),
                        onPressed: _send,
                      ),
                    ),
                    onSubmitted: (_) => _send(),
                  )
                : Text(t('comments_are_disabled'), style: theme.textTheme.bodySmall),
          ),
        ]),
      ),
    );
  }
}
