// Shared people (Immich v3.3): manage who can access a person, share many
// people with a user at once, and filter the people page by sharing.
// Web: PersonEditAccessModal, PersonBulkShareModal, PeopleSelectionModal, PeopleFilterModal.
import 'package:flutter/material.dart';

import '../api.dart';
import '../i18n.dart';
import 'user_avatar.dart';

void _error(BuildContext context, Object e) {
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t('error')}: $e')));
  }
}

Widget personThumb(ImmichApi api, Person p, {double size = 40}) => ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image(
          image: NetworkImage(api.personThumbnailUrl(p), headers: api.headers),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Icon(Icons.person, size: size / 2),
        ),
      ),
    );

// ---- One person: who has access (web: PersonEditAccessModal) ----

Future<void> showPersonAccessDialog(BuildContext context, ImmichApi api, Person person) =>
    showDialog<void>(context: context, builder: (_) => _PersonAccessDialog(api: api, person: person));

class _Access {
  final List<Map<String, dynamic>> sharedByMe; // users I gave access
  final List<Map<String, dynamic>> sharedWithMe; // users who gave me access (and I haven't back)
  final List<Map<String, dynamic>> group; // other cluster group members
  _Access(this.sharedByMe, this.sharedWithMe, this.group);
}

class _PersonAccessDialog extends StatefulWidget {
  final ImmichApi api;
  final Person person;
  const _PersonAccessDialog({required this.api, required this.person});

  @override
  State<_PersonAccessDialog> createState() => _PersonAccessDialogState();
}

class _PersonAccessDialogState extends State<_PersonAccessDialog> {
  late Future<_Access> _data = _load();
  ImmichApi get api => widget.api;
  String get id => widget.person.id;

  Future<_Access> _load() async {
    final r = await Future.wait([
      api.personUsers(personId: id, direction: 'shared-by'),
      api.personUsers(personId: id, direction: 'shared-with'),
      api.clusterGroupOthers(),
    ]);
    final byMe = [for (final e in r[0]) e['sharedWith'] as Map<String, dynamic>];
    final byMeIds = {for (final u in byMe) u['id']};
    final withMe = [
      for (final e in r[1])
        if (!byMeIds.contains(e['sharedById'])) e['sharedBy'] as Map<String, dynamic>,
    ];
    return _Access(byMe, withMe, r[2]);
  }

  Future<void> _run(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (mounted) _error(context, e);
    }
    if (mounted) {
      setState(() {
        _data = _load();
      });
    }
  }

  Future<void> _add(_Access a) async {
    final excluded = {...a.sharedByMe.map((u) => u['id']), ...a.sharedWithMe.map((u) => u['id'])};
    final users = await pickUsers(context, api, [for (final u in a.group) if (!excluded.contains(u['id'])) u],
        emptyMessage: t('person_share_no_users'));
    if (users == null || users.isEmpty) return;
    await _run(() => api.sharePeople([for (final u in users) u['id'] as String], personIds: [id]));
  }

  Widget _row(Map<String, dynamic> u, Widget trailing) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: UserAvatar(api: api, user: u),
        title: Text(u['name'] ?? ''),
        subtitle: Text(u['email'] ?? ''),
        trailing: trailing,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.group_outlined),
        const SizedBox(width: 12),
        Text(t('manage_person_access')),
      ]),
      content: SizedBox(
        width: 460,
        child: FutureBuilder<_Access>(
          future: _data,
          builder: (context, snap) {
            if (snap.hasError) return Text('${t('error')}: ${snap.error}');
            if (!snap.hasData) {
              return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
            }
            final a = snap.data!;
            return ListView(shrinkWrap: true, children: [
              Text(t('manage_people_access_description_v2', {'count': 1}), style: theme.textTheme.bodySmall),
              const SizedBox(height: 16),
              Text(t('shared_by_me'), style: theme.textTheme.titleSmall),
              if (a.sharedByMe.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(t('linux_person_not_shared'), style: theme.textTheme.bodySmall),
                ),
              for (final u in a.sharedByMe)
                _row(
                  u,
                  IconButton(
                    tooltip: t('stop_sharing_person_with_user'),
                    icon: const Icon(Icons.close),
                    onPressed: () => _run(() => api.unsharePeople([(id, u['id'] as String)])),
                  ),
                ),
              if (a.sharedWithMe.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(t('shared_with_me'), style: theme.textTheme.titleSmall),
                for (final u in a.sharedWithMe)
                  _row(
                    u,
                    FilledButton.tonalIcon(
                      onPressed: () => _run(() => api.sharePeople([u['id'] as String], personIds: [id])),
                      icon: const Icon(Icons.share_outlined),
                      label: Text(t('share_back')),
                    ),
                  ),
              ],
            ]);
          },
        ),
      ),
      actions: [
        FutureBuilder<_Access>(
          future: _data,
          builder: (context, snap) => snap.hasData
              ? TextButton.icon(
                  onPressed: () => _add(snap.data!),
                  icon: const Icon(Icons.person_add_outlined),
                  label: Text(t('add_user')),
                )
              : const SizedBox.shrink(),
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: Text(t('done'))),
      ],
    );
  }
}

// ---- Many people with one user (web: PersonBulkShareModal) ----

/// [users]: who can be given access (the first is selected); [people]: all my people if known.
Future<bool?> showBulkShareDialog(BuildContext context, ImmichApi api, List<Map<String, dynamic>> users) =>
    showDialog<bool>(context: context, builder: (_) => _BulkShareDialog(api: api, users: users));

class _BulkShareDialog extends StatefulWidget {
  final ImmichApi api;
  final List<Map<String, dynamic>> users;
  const _BulkShareDialog({required this.api, required this.users});

  @override
  State<_BulkShareDialog> createState() => _BulkShareDialogState();
}

class _BulkShareDialogState extends State<_BulkShareDialog> {
  ImmichApi get api => widget.api;
  late String _userId = widget.users.first['id'];
  Future<void>? _loading;
  List<Person> _all = [];
  Set<String> _initial = {};
  Set<String> _selected = {};
  bool _everyone = false;
  bool _saving = false;

  Map<String, dynamic> get _user => widget.users.firstWhere((u) => u['id'] == _userId);

  @override
  void initState() {
    super.initState();
    _loading = _load();
  }

  Future<void> _load() async {
    final me = (await api.me())['id'] as String;
    final r = await Future.wait([
      api.people(withHidden: true, sharedById: me, sharedWithId: _userId),
      api.people(withHidden: true),
    ]);
    if (!mounted) return;
    setState(() {
      _initial = {for (final p in r[0]) p.id};
      _selected = {..._initial};
      _all = r[1];
      _everyone = _initial.isNotEmpty && _all.every((p) => _initial.contains(p.id));
    });
  }

  Future<void> _editPeople() async {
    final picked = await pickPeople(context, api, _all, _selected);
    if (picked == null || !mounted) return;
    setState(() {
      if (!picked.containsAll(_selected)) _everyone = false;
      _selected = picked;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      if (_everyone) {
        await api.sharePeople([_userId], everyone: true);
      } else {
        final added = _selected.difference(_initial);
        final removed = _initial.difference(_selected);
        if (added.isNotEmpty) await api.sharePeople([_userId], personIds: added.toList());
        if (removed.isNotEmpty) await api.unsharePeople([for (final id in removed) (id, _userId)]);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('saved'))));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        _error(context, e);
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = [for (final p in _all) if (_selected.contains(p.id)) p];
    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.group_outlined),
        const SizedBox(width: 12),
        Text(t('manage_person_access')),
      ]),
      content: SizedBox(
        width: 460,
        child: FutureBuilder<void>(
          future: _loading,
          builder: (context, snap) {
            final loaded = snap.connectionState == ConnectionState.done;
            return ListView(shrinkWrap: true, children: [
              Text(t('manage_people_access_description_v2', {'count': _selected.length}),
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 16),
              if (widget.users.length > 1)
                DropdownButtonFormField<String>(
                  initialValue: _userId,
                  decoration: InputDecoration(labelText: t('share_with'), border: const OutlineInputBorder()),
                  items: [
                    for (final u in widget.users) DropdownMenuItem(value: u['id'] as String, child: Text(u['name'] ?? '')),
                  ],
                  onChanged: (v) => setState(() {
                    _userId = v!;
                    _loading = _load();
                  }),
                )
              else
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: UserAvatar(api: api, user: _user),
                  title: Text(_user['name'] ?? ''),
                  subtitle: Text(_user['email'] ?? ''),
                ),
              if (snap.hasError) Text('${t('error')}: ${snap.error}'),
              if (!loaded)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
              else ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t('share_everyone')),
                  subtitle: Text(t('share_everyone_description', {'user': _user['name'] ?? ''})),
                  value: _everyone,
                  onChanged: (v) => setState(() => _everyone = v),
                ),
                if (!_everyone) ...[
                  Row(children: [
                    Expanded(
                      child: Text(t('shared_with_count', {'count': _selected.length}),
                          style: theme.textTheme.titleSmall),
                    ),
                    TextButton.icon(
                      onPressed: _editPeople,
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(t('edit_people')),
                    ),
                  ]),
                  if (shown.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(t('no_people_found'), style: theme.textTheme.bodySmall),
                    ),
                  for (final p in shown)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: personThumb(api, p),
                      title: Text(p.name.isEmpty ? t('linux_unnamed_person') : p.name),
                    ),
                ],
              ],
            ]);
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t('cancel'))),
        FilledButton(
          onPressed: _saving || (!_everyone && _selected.isEmpty && _initial.isEmpty) ? null : _save,
          child: Text(t('save')),
        ),
      ],
    );
  }
}

/// Multi-select people with search (web: PeopleSelectionModal). Returns the new selection.
Future<Set<String>?> pickPeople(BuildContext context, ImmichApi api, List<Person> all, Set<String> selected) =>
    showDialog<Set<String>>(
      context: context,
      builder: (ctx) {
        final picked = {...selected};
        var query = '';
        return StatefulBuilder(
          builder: (ctx, setState) {
            final shown = query.isEmpty ? all : all.where((p) => p.name.toLowerCase().contains(query)).toList();
            return AlertDialog(
              title: Text(t('select_people')),
              content: SizedBox(
                width: 560,
                height: 480,
                child: Column(children: [
                  TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: t('search_people'),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => query = v.trim().toLowerCase()),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: shown.isEmpty
                        ? Center(child: Text(t('no_people_found')))
                        : GridView.builder(
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 100, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.8),
                            itemCount: shown.length,
                            itemBuilder: (_, i) {
                              final p = shown[i];
                              final on = picked.contains(p.id);
                              return InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => setState(() => on ? picked.remove(p.id) : picked.add(p.id)),
                                child: Column(children: [
                                  Stack(children: [
                                    personThumb(api, p, size: 72),
                                    if (on)
                                      Positioned(
                                        right: 0,
                                        bottom: 0,
                                        child: CircleAvatar(
                                          radius: 12,
                                          backgroundColor: Theme.of(ctx).colorScheme.primary,
                                          child: Icon(Icons.check, size: 16, color: Theme.of(ctx).colorScheme.onPrimary),
                                        ),
                                      ),
                                  ]),
                                  const SizedBox(height: 4),
                                  Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                ]),
                              );
                            },
                          ),
                  ),
                ]),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'))),
                FilledButton(onPressed: () => Navigator.pop(ctx, picked), child: Text(t('done'))),
              ],
            );
          },
        );
      },
    );

// ---- People page filter (web: PeopleFilterModal) ----

class PeopleFilter {
  final String? sharedById;
  final String? sharedWithId;
  final bool? isFavorite;
  final bool? isHidden;
  const PeopleFilter({this.sharedById, this.sharedWithId, this.isFavorite, this.isHidden});
  bool get isEmpty => sharedById == null && sharedWithId == null && isFavorite == null && isHidden == null;
}

/// [me]: my user; [others]: the other cluster group members.
Future<PeopleFilter?> showPeopleFilterDialog(BuildContext context, PeopleFilter current,
        {required Map<String, dynamic> me, required List<Map<String, dynamic>> others}) =>
    showDialog<PeopleFilter>(
      context: context,
      builder: (ctx) {
        var sharedBy = current.sharedById;
        var sharedWith = current.sharedWithId;
        var favorite = current.isFavorite;
        var hidden = current.isHidden;
        List<DropdownMenuItem<String?>> items() => [
              DropdownMenuItem(value: null, child: Text(t('no_filter'))),
              DropdownMenuItem(value: me['id'] as String, child: Text(t('you'))),
              for (final u in others) DropdownMenuItem(value: u['id'] as String, child: Text(u['name'] ?? '')),
            ];
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: Row(children: [const Icon(Icons.tune), const SizedBox(width: 12), Text(t('filters'))]),
            content: SizedBox(
              width: 380,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                DropdownButtonFormField<String?>(
                  key: ValueKey('by$sharedBy'),
                  initialValue: sharedBy,
                  decoration: InputDecoration(labelText: t('shared_by'), border: const OutlineInputBorder()),
                  items: items(),
                  onChanged: (v) => setState(() => sharedBy = v),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  key: ValueKey('with$sharedWith'),
                  initialValue: sharedWith,
                  decoration: InputDecoration(labelText: t('shared_with'), border: const OutlineInputBorder()),
                  items: items(),
                  onChanged: (v) => setState(() => sharedWith = v),
                ),
                const SizedBox(height: 8),
                // Three states like the web: any (dash) → yes → no.
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  tristate: true,
                  title: Text(t('favorite')),
                  value: favorite,
                  onChanged: (_) => setState(() => favorite = favorite == null ? true : (favorite! ? false : null)),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  tristate: true,
                  title: Text(t('hidden')),
                  value: hidden,
                  onChanged: (_) => setState(() => hidden = hidden == null ? true : (hidden! ? false : null)),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton(
                    onPressed: () => setState(() => sharedBy = sharedWith = favorite = hidden = null),
                    child: Text(t('reset')),
                  ),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'))),
              FilledButton(
                onPressed: () => Navigator.pop(
                    ctx,
                    PeopleFilter(
                        sharedById: sharedBy, sharedWithId: sharedWith, isFavorite: favorite, isHidden: hidden)),
                child: Text(t('save')),
              ),
            ],
          ),
        );
      },
    );
