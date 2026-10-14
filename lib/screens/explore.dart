// Explore page modeled on the web client's /explore, /people and /places routes.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../i18n.dart';
import '../sources.dart';
import '../widgets/asset_actions.dart';
import '../widgets/timeline_view.dart';
import '../widgets/loader.dart';
import '../widgets/memories.dart';
import '../widgets/person_access.dart';

class _ExploreData {
  final List<Person> people;
  final List<Place> places;
  final List<Map<String, dynamic>> memories;
  const _ExploreData(this.people, this.places, this.memories);
}

class ExploreScreen extends StatefulWidget {
  final ImmichApi api;
  const ExploreScreen({super.key, required this.api});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  late Future<_ExploreData> _data = _load();

  Future<_ExploreData> _load() async {
    final r = await Future.wait([
      widget.api.people(),
      widget.api.explorePlaces(),
      // The memories page exists since v3.2; older servers just show no section.
      widget.api
          .searchMemories(size: 20, isUpcoming: false)
          .catchError((_) => <Map<String, dynamic>>[]),
    ]);
    final memories = [
      for (final m in r[2] as List<Map<String, dynamic>>)
        if ((m['assets'] as List?)?.isNotEmpty ?? false) m,
    ];
    return _ExploreData(r[0] as List<Person>, r[1] as List<Place>, memories);
  }

  void _push(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final api = widget.api;
    return Loader<_ExploreData>(
      future: _data,
      onRetry: () => setState(() { _data = _load(); }),
      builder: (d) => ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          if (d.people.isNotEmpty) ...[
            _SectionHeader(t('people'), onAll: () => _push(PeopleScreen(api: api))),
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: d.people.length,
                separatorBuilder: (_, _) => const SizedBox(width: 16),
                itemBuilder: (_, i) => SizedBox(
                  width: 110,
                  child: PersonAvatar(
                    api: api,
                    person: d.people[i],
                    size: 110,
                    onTap: () => _push(PersonScreen(api: api, person: d.people[i])),
                  ),
                ),
              ),
            ),
          ],
          if (d.places.isNotEmpty) ...[
            _SectionHeader(t('places'), onAll: () => _push(PlacesScreen(api: api))),
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: d.places.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, i) => SizedBox(
                  width: 150,
                  child: PlaceCard(
                    api: api,
                    place: d.places[i],
                    onTap: () => _push(PlaceScreen(api: api, place: d.places[i])),
                  ),
                ),
              ),
            ),
          ],
          if (d.memories.isNotEmpty) ...[
            _SectionHeader(t('memories'), onAll: () => _push(MemoriesScreen(api: api))),
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: d.memories.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, i) => SizedBox(
                  width: 240,
                  child: MemoryCard(
                    api: api,
                    memory: d.memories[i],
                    onTap: () => openMemory(context, api, d.memories, i),
                  ),
                ),
              ),
            ),
          ],
          _SectionHeader(t('recently_added'),
              onAll: () => _push(TimelineScreen(
                    api: api,
                    title: t('recently_added'),
                    query: TimelineQuery.recent,
                  ))),
          if (d.people.isEmpty && d.places.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(t('linux_no_people_places'), textAlign: TextAlign.center),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback onAll;
  const _SectionHeader(this.title, {required this.onAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      child: Row(children: [
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
        TextButton(onPressed: onAll, child: Text(t('view_all'))),
      ]),
    );
  }
}

class PersonAvatar extends StatelessWidget {
  final ImmichApi api;
  final Person person;
  final double size;
  final String? subtitle;
  final VoidCallback onTap;

  const PersonAvatar({
    super.key,
    required this.api,
    required this.person,
    required this.size,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Stack(children: [
          ClipOval(
            child: Container(
              width: size,
              height: size,
              color: theme.colorScheme.surfaceContainerHighest,
              child: Image(
                image: NetworkImage(api.personThumbnailUrl(person), headers: api.headers),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Icon(Icons.person, size: size / 2),
              ),
            ),
          ),
          // Web: PersonIndicator (favorite, shared with me).
          if (person.isFavorite || person.isShared)
            Positioned(
              left: 4,
              top: 4,
              child: Row(children: [
                if (person.isFavorite)
                  Tooltip(message: t('favorite'), child: const Icon(Icons.favorite, color: Colors.white, size: 18,
                      shadows: [Shadow(blurRadius: 4)])),
                if (person.isShared)
                  Tooltip(message: t('shared_with_me'), child: const Icon(Icons.group, color: Colors.white, size: 18,
                      shadows: [Shadow(blurRadius: 4)])),
              ]),
            ),
        ]),
        const SizedBox(height: 6),
        if (person.name.isNotEmpty)
          Text(person.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium),
        if (subtitle != null)
          Text(subtitle!, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
      ]),
    );
  }
}

class PlaceCard extends StatelessWidget {
  final ImmichApi api;
  final Place place;
  final VoidCallback onTap;
  const PlaceCard({super.key, required this.api, required this.place, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: InkWell(
          onTap: onTap,
          child: Stack(fit: StackFit.expand, children: [
            Image(
              image: NetworkImage(api.thumbnailUrl(place.assetId), headers: api.headers),
              fit: BoxFit.cover,
              color: Colors.black26,
              colorBlendMode: BlendMode.darken,
              errorBuilder: (_, _, _) => const SizedBox(),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  place.city,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(blurRadius: 6)],
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class PeopleScreen extends StatefulWidget {
  final ImmichApi api;
  const PeopleScreen({super.key, required this.api});

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  late Future<List<Person>> _people = _fetch();
  String _filter = '';
  bool _manage = false; // web: "Show & hide people"
  PeopleFilter _peopleFilter = const PeopleFilter();
  /// Me and the other cluster group members (no group on servers before v3.2).
  late final Future<(Map<String, dynamic>, List<Map<String, dynamic>>)> _group = () async {
    final me = await widget.api.me();
    return (me, me['clusterGroupId'] == null ? <Map<String, dynamic>>[] : await widget.api.clusterGroupOthers());
  }();

  /// Hidden people only show in "Show & hide" mode or when filtering for them (like the web).
  Future<List<Person>> _fetch() {
    final f = _peopleFilter;
    return widget.api.people(
      withHidden: _manage || f.isHidden != null,
      sharedById: f.sharedById,
      sharedWithId: f.sharedWithId,
      isFavorite: f.isFavorite,
      isHidden: f.isHidden,
    );
  }

  void _refetch() => setState(() {
        _people = _fetch();
      });

  void _setManage(bool v) {
    _manage = v;
    _refetch();
  }

  Future<void> _editFilter() async {
    final (me, others) = await _group;
    if (!mounted) return;
    final f = await showPeopleFilterDialog(context, _peopleFilter, me: me, others: others);
    if (f == null) return;
    _peopleFilter = f;
    _refetch();
  }

  Future<void> _manageAccess() async {
    final (_, others) = await _group;
    if (!mounted || others.isEmpty) return;
    if (await showBulkShareDialog(context, widget.api, others) == true) _refetch();
  }

  Future<void> _toggleHidden(Person p) async {
    try {
      await widget.api.updatePerson(p.id, isHidden: !p.isHidden);
      _refetch();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t('error')}: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = widget.api;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('people')),
        actions: [
          SizedBox(
            width: 260,
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: t('search_people'),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
            ),
          ),
          const SizedBox(width: 8),
          FutureBuilder(
            future: _group,
            builder: (context, snap) => (snap.data?.$2.isNotEmpty ?? false)
                ? TextButton.icon(
                    onPressed: _manageAccess,
                    icon: const Icon(Icons.group_outlined),
                    label: Text(t('manage_person_access')),
                  )
                : const SizedBox.shrink(),
          ),
          IconButton(
            tooltip: t('filters'),
            onPressed: _editFilter,
            icon: Badge(isLabelVisible: !_peopleFilter.isEmpty, smallSize: 8, child: const Icon(Icons.tune)),
          ),
          const SizedBox(width: 8),
          _manage
              ? FilledButton(onPressed: () => _setManage(false), child: Text(t('linux_show_people')))
              : TextButton.icon(
                  onPressed: () => _setManage(true),
                  icon: const Icon(Icons.visibility_outlined),
                  label: Text(t('show_and_hide_people')),
                ),
          const SizedBox(width: 16),
        ],
      ),
      body: Loader<List<Person>>(
        future: _people,
        onRetry: _refetch,
        builder: (all) {
          final people = _filter.isEmpty
              ? all
              : all.where((p) => p.name.toLowerCase().contains(_filter)).toList();
          if (people.isEmpty) return Center(child: Text(t('no_results')));
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 150,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.8,
            ),
            itemCount: people.length,
            itemBuilder: (_, i) => LayoutBuilder(
              builder: (context, c) => Stack(children: [
                Opacity(
                  opacity: _manage && people[i].isHidden ? 0.35 : 1,
                  child: PersonAvatar(
                    api: api,
                    person: people[i],
                    size: c.maxWidth,
                    onTap: _manage
                        ? () => _toggleHidden(people[i])
                        : () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => PersonScreen(api: api, person: people[i]),
                            )),
                  ),
                ),
                if (_manage)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: IconButton.filledTonal(
                      tooltip: people[i].isHidden ? t('unhide_person') : t('hide_person'),
                      icon: Icon(people[i].isHidden ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => _toggleHidden(people[i]),
                    ),
                  ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class PlacesScreen extends StatefulWidget {
  final ImmichApi api;
  const PlacesScreen({super.key, required this.api});

  @override
  State<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends State<PlacesScreen> {
  late Future<List<Place>> _places = widget.api.places();
  String _filter = '';
  bool _byCountry = false;

  @override
  Widget build(BuildContext context) {
    final api = widget.api;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('places')),
        actions: [
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(t('group_no'))),
              ButtonSegment(value: true, label: Text(t('group_country'))),
            ],
            selected: {_byCountry},
            onSelectionChanged: (s) => setState(() => _byCountry = s.first),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 240,
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: t('search_places'),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Loader<List<Place>>(
        future: _places,
        onRetry: () => setState(() { _places = api.places(); }),
        builder: (all) {
          final places = _filter.isEmpty
              ? all
              : all.where((p) => p.city.toLowerCase().contains(_filter)).toList();
          if (places.isEmpty) return Center(child: Text(t('no_places')));

          final groups = <String, List<Place>>{};
          for (final p in places) {
            groups.putIfAbsent(_byCountry ? (p.country ?? t('unknown_country')) : '', () => []).add(p);
          }
          final keys = groups.keys.toList()..sort();

          Widget grid(List<Place> list) => SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => PlaceCard(
                      api: api,
                      place: list[i],
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => PlaceScreen(api: api, place: list[i]),
                      )),
                    ),
                    childCount: list.length,
                  ),
                ),
              );

          return CustomScrollView(slivers: [
            for (final k in keys) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: k.isEmpty
                      ? const SizedBox()
                      : Text('$k (${groups[k]!.length})',
                          style: Theme.of(context).textTheme.titleMedium),
                ),
              ),
              grid(groups[k]!),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ]);
        },
      ),
    );
  }
}

/// A full-page timeline with a title, e.g. one person or "recently added".
class TimelineScreen extends StatefulWidget {
  final ImmichApi api;
  final String title;
  final String? subtitle;
  final TimelineQuery query;
  final TimelineMode mode;
  final List<Widget> actions;

  const TimelineScreen({
    super.key,
    required this.api,
    required this.title,
    required this.query,
    this.subtitle,
    this.mode = TimelineMode.normal,
    this.actions = const [],
  });

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  late Future<TimelineSource> _source = TimelineSource.create(widget.api, widget.query);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.title),
          if (widget.subtitle != null)
            Text(widget.subtitle!, style: Theme.of(context).textTheme.bodySmall),
        ]),
        actions: widget.actions,
      ),
      body: Loader<TimelineSource>(
        future: _source,
        onRetry: () => setState(() {
          _source = TimelineSource.create(widget.api, widget.query);
        }),
        builder: (src) => src.length == 0
            ? Center(child: Text(t('linux_no_items')))
            : TimelineView(api: widget.api, source: src, mode: widget.mode),
      ),
    );
  }
}

class PersonScreen extends StatefulWidget {
  final ImmichApi api;
  final Person person;
  const PersonScreen({super.key, required this.api, required this.person});

  @override
  State<PersonScreen> createState() => _PersonScreenState();
}

/// Person page with the web's actions: name, birth date, favorite, hide, merge.
class _PersonScreenState extends State<PersonScreen> {
  late Person _person = widget.person;
  ImmichApi get api => widget.api;
  /// Sharing people needs a cluster group with others (v3.3).
  late final Future<bool> _canShare = api.clusterGroupOthers().then((o) => o.isNotEmpty, onError: (_) => false);

  @override
  void initState() {
    super.initState();
    // The people list may not carry the sharing fields; the person endpoint does.
    api.person(_person.id).then((p) {
      if (mounted) setState(() => _person = p);
    }, onError: (_) {});
  }

  Future<void> _access() async {
    await showPersonAccessDialog(context, api, _person);
    try {
      final p = await api.person(_person.id);
      if (mounted) setState(() => _person = p);
    } catch (_) {}
  }

  Future<void> _update(Future<Person> Function() f, [String? ok]) async {
    try {
      final p = await f();
      setState(() => _person = p);
      if (mounted && ok != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t('error')}: $e')));
    }
  }

  /// Web: PersonEditModal (name, date of birth, "only change for me" for shared people).
  Future<void> _edit() async {
    final r = await showDialog<_PersonEdit>(
      context: context,
      builder: (_) => _PersonEditDialog(api: api, person: _person),
    );
    if (r == null) return;
    await _update(() async {
      await api.updatePerson(_person.id,
          name: r.name, birthDate: r.birthDate, clearBirthDate: r.birthDate == null, userId: r.userId);
      return api.person(_person.id);
    }, t('saved'));
  }

  Future<void> _merge() async {
    final others = (await api.people(withHidden: true)).where((p) => p.id != _person.id).toList();
    if (!mounted) return;
    final picked = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _MergeDialog(api: api, target: _person, candidates: others),
    );
    if (picked == null || picked.isEmpty) return;
    try {
      await api.mergePeople(_person.id, picked.toList());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('merge_people_successfully'))));
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => PersonScreen(api: api, person: _person),
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t('error')}: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _person;
    final age = p.birthDate == null ? null : ageAt(p.birthDate!, DateTime.now());
    return TimelineScreen(
      key: ValueKey(p.id),
      api: api,
      title: p.name.isEmpty ? t('linux_unnamed_person') : p.name,
      subtitle: [
        ?age,
        if (p.otherNames.isNotEmpty) '${t('also_known_as')} ${p.otherNames.join(', ')}',
      ].join(' · ').nullIfEmpty,
      query: TimelineQuery(personId: p.id),
      actions: [
        IconButton(tooltip: t('edit_person'), icon: const Icon(Icons.edit_outlined), onPressed: _edit),
        IconButton(
          tooltip: p.isFavorite ? t('remove_from_favorites') : t('to_favorite'),
          icon: Icon(p.isFavorite ? Icons.favorite : Icons.favorite_border),
          onPressed: () => _update(() => api.updatePerson(p.id, isFavorite: !p.isFavorite)),
        ),
        IconButton(
          tooltip: p.isHidden ? t('unhide_person') : t('hide_person'),
          icon: Icon(p.isHidden ? Icons.visibility : Icons.visibility_off_outlined),
          onPressed: () => _update(() => api.updatePerson(p.id, isHidden: !p.isHidden)),
        ),
        IconButton(tooltip: t('merge_people'), icon: const Icon(Icons.merge_type), onPressed: _merge),
        FutureBuilder<bool>(
          future: _canShare,
          builder: (context, snap) => snap.data == true || p.sharedBy.isNotEmpty || p.sharedWith.isNotEmpty
              ? IconButton(
                  tooltip: t('manage_person_access'),
                  icon: const Icon(Icons.group_outlined),
                  onPressed: _access,
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

class _PersonEdit {
  final String name;
  final String? birthDate; // yyyy-MM-dd or null to clear
  final String? userId;
  _PersonEdit(this.name, this.birthDate, this.userId);
}

class _PersonEditDialog extends StatefulWidget {
  final ImmichApi api;
  final Person person;
  const _PersonEditDialog({required this.api, required this.person});

  @override
  State<_PersonEditDialog> createState() => _PersonEditDialogState();
}

class _PersonEditDialogState extends State<_PersonEditDialog> {
  late final _name = TextEditingController(text: widget.person.name);
  late DateTime? _birth = widget.person.birthDate;
  bool _onlyForMe = false;
  String? _myId;

  @override
  void initState() {
    super.initState();
    if (widget.person.otherPeople.isEmpty) return;
    // Default from Features → People → "Apply changes to" (web: updateStrategy, default everyone).
    Future.wait([widget.api.me(), widget.api.preferences()]).then((r) {
      if (!mounted) return;
      setState(() {
        _myId = r[0]['id'];
        _onlyForMe = (r[1]['people'] as Map?)?['updateStrategy'] == 'self';
      });
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _birth ?? DateTime(2000),
      firstDate: DateTime(1850),
      lastDate: DateTime.now(),
      helpText: t('date_of_birth'),
    );
    if (d != null) setState(() => _birth = d);
  }

  void _submit() => Navigator.pop(
      context,
      _PersonEdit(_name.text.trim(), _birth == null ? null : _iso(_birth!),
          _onlyForMe && _myId != null ? _myId : null));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shared = widget.person.otherPeople.isNotEmpty;
    return AlertDialog(
      title: Row(children: [const Icon(Icons.edit_outlined), const SizedBox(width: 12), Text(t('edit_person'))]),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: InputDecoration(labelText: t('name'), border: const OutlineInputBorder()),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          InputDecorator(
            decoration: InputDecoration(
              labelText: t('date_of_birth'),
              helperText: t('birthdate_set_description'),
              helperMaxLines: 3,
              border: const OutlineInputBorder(),
            ),
            child: Row(children: [
              Expanded(
                child: Text(_birth == null ? '—' : DateFormat.yMMMMd(i18n.dateLocale).format(_birth!)),
              ),
              if (_birth != null)
                IconButton(
                  tooltip: t('clear'),
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() => _birth = null),
                ),
              IconButton(
                tooltip: t('edit_birthday'),
                icon: const Icon(Icons.calendar_month_outlined),
                onPressed: _pickDate,
              ),
            ]),
          ),
          if (shared) ...[
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(t('person_edit_only_change_for_me')),
              subtitle: Text(t('person_edit_only_change_for_me_description'), style: theme.textTheme.bodySmall),
              value: _onlyForMe,
              onChanged: _myId == null ? null : (v) => setState(() => _onlyForMe = v!),
            ),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t('cancel'))),
        FilledButton(onPressed: _submit, child: Text(t('save'))),
      ],
    );
  }
}

class _MergeDialog extends StatefulWidget {
  final ImmichApi api;
  final Person target;
  final List<Person> candidates;
  const _MergeDialog({required this.api, required this.target, required this.candidates});

  @override
  State<_MergeDialog> createState() => _MergeDialogState();
}

class _MergeDialogState extends State<_MergeDialog> {
  final _picked = <String>{};
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final list = widget.candidates
        .where((p) => _filter.isEmpty || p.name.toLowerCase().contains(_filter))
        .toList();
    return AlertDialog(
      title: Text(t('merge_people')),
      content: SizedBox(
        width: 560,
        height: 480,
        child: Column(children: [
          Text(t('linux_merge_into', {
            'name': widget.target.name.isEmpty ? t('linux_unnamed_person') : widget.target.name,
          })),
          const SizedBox(height: 8),
          TextField(
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t('search_people')),
            onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 110,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.8,
              ),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final p = list[i];
                final on = _picked.contains(p.id);
                return Stack(children: [
                  PersonAvatar(
                    api: widget.api,
                    person: p,
                    size: 90,
                    onTap: () => setState(() => on ? _picked.remove(p.id) : _picked.add(p.id)),
                  ),
                  if (on)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
                    ),
                ]);
              },
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t('cancel'))),
        FilledButton(
          onPressed: _picked.isEmpty ? null : () => Navigator.pop(context, _picked),
          child: Text(t('merge')),
        ),
      ],
    );
  }
}

class PlaceScreen extends StatefulWidget {
  final ImmichApi api;
  final Place place;
  const PlaceScreen({super.key, required this.api, required this.place});

  @override
  State<PlaceScreen> createState() => _PlaceScreenState();
}

class _PlaceScreenState extends State<PlaceScreen> {
  late final SearchSource _source =
      SearchSource((page) => widget.api.citySearch(widget.place.city, page: page))..loadMore();

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.place;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.city),
          if (p.country != null) Text(p.country!, style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
      body: ListenableBuilder(
        listenable: _source,
        builder: (context, _) {
          if (_source.error != null && _source.length == 0) {
            return Center(child: Text('${t('error')}: ${_source.error}'));
          }
          if (_source.length == 0) {
            return _source.hasMore
                ? const Center(child: CircularProgressIndicator())
                : Center(child: Text(t('linux_no_items')));
          }
          return TimelineView(api: widget.api, source: _source);
        },
      ),
    );
  }
}

/// Age text like the web client: months under two years, otherwise years.
String? ageAt(DateTime birth, DateTime when) {
  var months = (when.year - birth.year) * 12 + when.month - birth.month;
  if (when.day < birth.day) months--;
  if (months < 0) return null;
  if (months < 12) return t('age_months', {'months': months});
  if (months < 24 && months > 12) return t('age_year_months', {'months': months - 12});
  return t('age_years', {'years': months ~/ 12});
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
