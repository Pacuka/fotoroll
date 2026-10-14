// Account Settings → Sharing (web: user-settings/SharingSettings.svelte):
// the people cluster group (v3.2+) and partner sharing.
import 'package:flutter/material.dart';

import '../api.dart';
import '../i18n.dart';
import '../widgets/user_avatar.dart';

Future<void> _guard(BuildContext context, Future<void> Function() f) async {
  try {
    await f();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t('error')}: $e')));
    }
  }
}

Future<bool> _confirm(BuildContext context, String title, String prompt, {bool danger = false}) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: Text(prompt)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
          FilledButton(
            style: danger ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error) : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('confirm')),
          ),
        ],
      ),
    ) ==
    true;

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

class SharingSection extends StatelessWidget {
  final ImmichApi api;
  const SharingSection({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    Widget sub(String title, String subtitle, Widget child) => ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(title),
          subtitle: Text(subtitle),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          childrenPadding: const EdgeInsets.only(bottom: 12),
          children: [child],
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClusterGroupSection(api: api, wrap: (child) => sub(t('people_cluster_group'), t('cluster_group_description'), child)),
      sub(t('partners'), t('partners_description'), _PartnersSection(api: api)),
    ]);
  }
}

class _ClusterData {
  final String groupId;
  final String myId;
  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> sent;
  final List<Map<String, dynamic>> received;
  /// All users of the server by id (invitees are outside the group).
  final Map<String, Map<String, dynamic>> users;
  _ClusterData(this.groupId, this.myId, this.members, this.sent, this.received, this.users);
}

/// Hidden on servers before v3.2 (no clusterGroupId on the user).
class ClusterGroupSection extends StatefulWidget {
  final ImmichApi api;
  final Widget Function(Widget child) wrap;
  const ClusterGroupSection({super.key, required this.api, required this.wrap});

  @override
  State<ClusterGroupSection> createState() => _ClusterGroupSectionState();
}

class _ClusterGroupSectionState extends State<ClusterGroupSection> {
  late Future<_ClusterData?> _data = _load();

  ImmichApi get api => widget.api;

  Future<_ClusterData?> _load() async {
    final me = await api.me();
    final groupId = me['clusterGroupId'] as String?;
    if (groupId == null) return null;
    final r = await Future.wait([
      api.clusterGroupUsers(groupId),
      api.clusterGroupSentRequests(groupId),
      api.clusterGroupReceivedRequests(),
      api.users(),
    ]);
    return _ClusterData(groupId, me['id'], r[0], r[1], r[2], {for (final u in r[3]) u['id'] as String: u});
  }

  void _reload() => setState(() {
        _data = _load();
      });

  Future<void> _invite(_ClusterData d) async {
    final excluded = {d.myId, ...d.members.map((u) => u['id']), ...d.sent.map((r) => r['userId'])};
    final picked =
        await pickUsers(context, api, [for (final u in d.users.values) if (!excluded.contains(u['id'])) u]);
    if (picked == null || !mounted) return;
    await _guard(context, () async {
      for (final u in picked) {
        await api.inviteToClusterGroup(d.groupId, u['id']);
      }
    });
    _reload();
  }

  Future<void> _viewGroup(Map<String, dynamic> request) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('people_cluster_group')),
        content: SizedBox(
          width: 400,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: api.clusterGroupUsers(request['clusterGroupId']),
            builder: (ctx, snap) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t('cluster_group_invite_description')),
                const SizedBox(height: 16),
                Text(t('users'), style: Theme.of(ctx).textTheme.titleSmall),
                if (!snap.hasData)
                  const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
                else
                  for (final u in snap.data!)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: UserAvatar(api: api, user: u),
                      title: Text(u['name'] ?? ''),
                      subtitle: Text(u['email'] ?? ''),
                    ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('decline'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('accept'))),
        ],
      ),
    );
    if (result == null || !mounted) return;
    await _guard(context, () => result
        ? api.acceptClusterGroupRequest(request['id'])
        : api.deleteClusterGroupRequest(request['id']));
    _reload();
  }

  Future<void> _leave(_ClusterData d) async {
    if (!await _confirm(context, t('leave_group'), t('leave_group_description'))) return;
    if (!mounted) return;
    await _guard(context, () => api.leaveClusterGroup(d.groupId));
    _reload();
  }

  Future<void> _resetFaces(_ClusterData d) async {
    if (!await _confirm(context, t('cluster_group_facial_recognition'),
        t('cluster_group_facial_recognition_prompt'), danger: true)) {
      return;
    }
    if (!mounted) return;
    await _guard(context, () => api.regenerateClusterGroupPeople(d.groupId));
  }

  Widget _userRow(Map<String, dynamic> u, {String? suffix, Widget? trailing}) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: UserAvatar(api: api, user: u),
        title: Text([u['name'] ?? '', ?suffix].join(' ')),
        subtitle: Text(u['email'] ?? ''),
        trailing: trailing,
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ClusterData?>(
      future: _data,
      builder: (context, snap) {
        if (snap.hasError) {
          return widget.wrap(Text(t('errors.unable_to_load_cluster_group')));
        }
        if (snap.connectionState != ConnectionState.done) {
          return widget.wrap(const Center(child: CircularProgressIndicator()));
        }
        final d = snap.data;
        if (d == null) return const SizedBox.shrink();
        final theme = Theme.of(context);
        final canLeave = d.members.length > 1;
        return widget.wrap(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(children: [
                for (final u in d.members)
                  _userRow(
                    u,
                    suffix: u['id'] == d.myId ? '(${t('you')})' : null,
                    trailing: u['id'] == d.myId && canLeave
                        ? OutlinedButton(onPressed: () => _leave(d), child: Text(t('leave')))
                        : null,
                  ),
              ]),
            ),
          ),
          if (d.sent.isNotEmpty || d.received.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(t('pending'), style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(children: [
                  for (final r in d.received)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.mail_outline),
                      title: Text(t('request_received_description')),
                      trailing: OutlinedButton(onPressed: () => _viewGroup(r), child: Text(t('view_group'))),
                    ),
                  for (final r in d.sent)
                    _userRow(
                      d.users[r['userId']] ?? {'id': r['userId'], 'name': r['userId']},
                      trailing: OutlinedButton(
                        onPressed: () async {
                          await _guard(context, () => api.deleteClusterGroupRequest(r['id']));
                          _reload();
                        },
                        child: Text(t('cancel')),
                      ),
                    ),
                ]),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: () => _resetFaces(d),
              icon: const Icon(Icons.face_retouching_off_outlined),
              label: Text(t('cluster_group_facial_recognition')),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _invite(d),
              icon: const Icon(Icons.person_add_outlined),
              label: Text(t('add_user')),
            ),
          ]),
        ]));
      },
    );
  }
}

class _PartnersSection extends StatefulWidget {
  final ImmichApi api;
  const _PartnersSection({required this.api});

  @override
  State<_PartnersSection> createState() => _PartnersSectionState();
}

class _PartnersSectionState extends State<_PartnersSection> {
  late Future<List<List<Partner>>> _data = _load();

  Future<List<List<Partner>>> _load() =>
      Future.wait([widget.api.partners('shared-by'), widget.api.partners('shared-with')]);

  void _reload() => setState(() {
        _data = _load();
      });

  Future<void> _add(List<Partner> existing) async {
    await _guard(context, () async {
      final me = await widget.api.me();
      final users = (await widget.api.users())
          .where((u) => u['id'] != me['id'] && !existing.any((p) => p.id == u['id']))
          .toList();
      if (!mounted) return;
      final picked = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(t('linux_choose_user')),
          children: [
            for (final u in users)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, u['id'] as String),
                child: ListTile(title: Text(u['name'] ?? ''), subtitle: Text(u['email'] ?? '')),
              ),
          ],
        ),
      );
      if (picked == null) return;
      await widget.api.addPartner(picked);
      _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<List<Partner>>>(
      future: _data,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final sharedBy = snap.data![0];
        final sharedWith = snap.data![1];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t('linux_you_share_with'), style: theme.textTheme.titleSmall),
          if (sharedBy.isEmpty) Text(t('linux_no_partners')),
          for (final p in sharedBy)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(p.name),
              subtitle: Text(p.email),
              trailing: IconButton(
                tooltip: t('delete'),
                icon: const Icon(Icons.person_remove_outlined),
                onPressed: () => _guard(context, () async {
                  await widget.api.removePartner(p.id);
                  _reload();
                }),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: () => _add(sharedBy),
              icon: const Icon(Icons.person_add_outlined),
              label: Text(t('add_partner')),
            ),
          ),
          if (sharedWith.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(t('linux_shared_with_you'), style: theme.textTheme.titleSmall),
            for (final p in sharedWith)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(p.name),
                subtitle: Text(t('show_in_timeline')),
                value: p.inTimeline,
                onChanged: (v) => _guard(context, () async {
                  await widget.api.setPartnerInTimeline(p.id, v);
                  _reload();
                }),
              ),
          ],
        ]);
      },
    );
  }
}
