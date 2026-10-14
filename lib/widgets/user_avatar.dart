// Round user picture like the web's UserAvatar: the profile image, or the
// initial on the user's avatar colour when there is none; and a user picker.
import 'package:flutter/material.dart';

import '../api.dart';
import '../i18n.dart';

const _avatarColors = {
  'primary': Color(0xFF4250AF),
  'pink': Color(0xFFDB2777),
  'red': Color(0xFFDC2626),
  'yellow': Color(0xFFCA8A04),
  'blue': Color(0xFF2563EB),
  'green': Color(0xFF16A34A),
  'purple': Color(0xFF9333EA),
  'orange': Color(0xFFEA580C),
  'gray': Color(0xFF4B5563),
  'amber': Color(0xFFD97706),
};

class UserAvatar extends StatelessWidget {
  final ImmichApi api;
  /// UserResponseDto map: id, name, profileImagePath, profileChangedAt, avatarColor.
  final Map<String, dynamic> user;
  final double radius;
  const UserAvatar({super.key, required this.api, required this.user, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final name = (user['name'] as String?) ?? '';
    final hasImage = ((user['profileImagePath'] as String?) ?? '').isNotEmpty;
    final color = _avatarColors[user['avatarColor']] ?? Theme.of(context).colorScheme.primary;
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      foregroundImage: hasImage
          ? NetworkImage(api.profileImageUrl(user['id'], changedAt: user['profileChangedAt']),
              headers: api.headers)
          : null,
      onForegroundImageError: hasImage ? (_, _) {} : null,
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(color: Colors.white, fontSize: radius * 0.8, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Multi-select user picker (web: ClusterGroupUserSelectionModal / AddUsersModal).
Future<List<Map<String, dynamic>>?> pickUsers(
  BuildContext context,
  ImmichApi api,
  List<Map<String, dynamic>> users, {
  String? title,
  String? emptyMessage,
}) =>
    showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (ctx) {
        final picked = <String>{};
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: Text(title ?? t('add_user')),
            content: SizedBox(
              width: 400,
              child: users.isEmpty
                  ? Text(emptyMessage ?? t('partner_page_no_more_users'))
                  : ListView(shrinkWrap: true, children: [
                      for (final u in users)
                        CheckboxListTile(
                          value: picked.contains(u['id']),
                          onChanged: (v) =>
                              setState(() => v! ? picked.add(u['id']) : picked.remove(u['id'])),
                          secondary: UserAvatar(api: api, user: u),
                          title: Text(u['name'] ?? ''),
                          subtitle: Text(u['email'] ?? ''),
                        ),
                    ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'))),
              FilledButton(
                onPressed: picked.isEmpty
                    ? null
                    : () => Navigator.pop(ctx, [for (final u in users) if (picked.contains(u['id'])) u]),
                child: Text(t('add')),
              ),
            ],
          ),
        );
      },
    );
