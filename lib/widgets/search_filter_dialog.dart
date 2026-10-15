// "Search options" panel (web v3.3 SearchFilters): recent searches, then "Filter by"
// buttons for search type, people, date, places, tags and media (one section shown at
// a time), and "Advanced filters" for camera, rating and display options.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../i18n.dart';
import '../screens/explore.dart' show PersonAvatar;
import '../settings.dart';

/// Opens the dialog; returns the new filter, or null when cancelled.
Future<SearchFilter?> showSearchFilterDialog(BuildContext context, ImmichApi api, SearchFilter initial) =>
    showDialog<SearchFilter>(
      context: context,
      builder: (_) => _SearchFilterDialog(api: api, initial: initial),
    );

class _SearchFilterDialog extends StatefulWidget {
  final ImmichApi api;
  final SearchFilter initial;
  const _SearchFilterDialog({required this.api, required this.initial});

  @override
  State<_SearchFilterDialog> createState() => _SearchFilterDialogState();
}

enum _Section { type, people, date, places, tags, media }

/// Date presets of the web's SearchDateSection.
enum _DatePreset { thisYear, lastYear, last30Days, custom }

class _SearchFilterDialogState extends State<_SearchFilterDialog> {
  late SearchFilter f = widget.initial.copy();
  late final _query = TextEditingController(text: f.query);
  late final Future<List<Person>> _people =
      widget.api.people().then((l) => l.where((p) => p.name.isNotEmpty).toList());
  late final Future<List<Map<String, dynamic>>> _tags = widget.api.tags();
  late final Future<bool> _ratings =
      widget.api.preferences().then((p) => (p['ratings'] as Map?)?['enabled'] == true, onError: (_) => false);
  List<Person> _peopleList = const [];
  List<Map<String, dynamic>> _tagList = const [];
  String _personFilter = '';
  bool _allPeople = false;
  int _rev = 0; // bumps on "Clear all" so dropdowns rebuild empty
  _Section _section = _Section.type;
  late bool _advanced = _advancedSet;
  late bool _customDate = _datePreset == _DatePreset.custom;

  @override
  void initState() {
    super.initState();
    _people.then((l) {
      if (mounted) setState(() => _peopleList = l);
    }, onError: (_) {});
    _tags.then((l) {
      if (mounted) setState(() => _tagList = l);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  bool get _advancedSet =>
      f.make != null || f.model != null || f.lensModel != null || f.rating != null || f.isFavorite ||
      f.inArchive || f.notInAlbum;

  void _clear() => setState(() {
        f = SearchFilter(mode: f.mode); // the web keeps the chosen text mode
        _query.clear();
        _customDate = false;
        _rev++;
      });

  void _submit([String? term]) {
    if (term != null) _query.text = term;
    f.query = _query.text;
    Navigator.pop(context, f);
  }

  // ---- Titles on the "Filter by" buttons (web: search-bar-utils) ----

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static (DateTime, DateTime) _presetRange(_DatePreset p) {
    final today = _today();
    return switch (p) {
      _DatePreset.thisYear => (DateTime(today.year), DateTime(today.year, 12, 31)),
      _DatePreset.lastYear => (DateTime(today.year - 1), DateTime(today.year - 1, 12, 31)),
      _ => (today.subtract(const Duration(days: 30)), today),
    };
  }

  _DatePreset? get _datePreset {
    if (f.takenAfter == null && f.takenBefore == null) return null;
    for (final p in [_DatePreset.thisYear, _DatePreset.lastYear, _DatePreset.last30Days]) {
      final (a, b) = _presetRange(p);
      if (f.takenAfter == a && f.takenBefore == b) return p;
    }
    return _DatePreset.custom;
  }

  String? _title(_Section s) {
    switch (s) {
      case _Section.type:
        return f.mode == SearchMode.smart ? null : t(_modeLabels[f.mode]!);
      case _Section.people:
        if (f.personIds.isEmpty) return null;
        final name = _peopleList.where((p) => f.personIds.contains(p.id)).firstOrNull?.name;
        if (name == null) return t('people_count', {'count': f.personIds.length});
        return f.personIds.length == 1 ? name : t('name_plus_more_people', {'name': name, 'count': f.personIds.length - 1});
      case _Section.date:
        final preset = _datePreset;
        if (preset == null) return null;
        if (preset != _DatePreset.custom) return t(_presetLabels[preset]!);
        final fmt = DateFormat.yMMMd(i18n.dateLocale);
        final a = f.takenAfter == null ? null : fmt.format(f.takenAfter!);
        final b = f.takenBefore == null ? null : fmt.format(f.takenBefore!);
        return a != null && b != null ? t('search_filter_date_interval', {'start': a, 'end': b}) : a ?? b;
      case _Section.places:
        final p = [f.city, f.state, f.country].whereType<String>().join(', ');
        return p.isEmpty ? null : p;
      case _Section.tags:
        if (f.tagIds.isEmpty) return null;
        final tag = _tagList.where((x) => x['id'] == f.tagIds.first).firstOrNull?['name'] as String?;
        if (tag == null) return null;
        return f.tagIds.length == 1 ? tag : t('tag_plus_more_tags', {'tag': tag, 'count': f.tagIds.length - 1});
      case _Section.media:
        return switch (f.type) { 'IMAGE' => t('image'), 'VIDEO' => t('video'), _ => null };
    }
  }

  static const _modeLabels = {
    SearchMode.smart: 'context',
    SearchMode.filename: 'file_name_or_extension',
    SearchMode.description: 'description',
    SearchMode.path: 'path',
    SearchMode.ocr: 'ocr',
  };
  static const _presetLabels = {
    _DatePreset.thisYear: 'search_filter_date_this_year',
    _DatePreset.lastYear: 'search_filter_date_last_year',
    _DatePreset.last30Days: 'search_filter_date_last_30_days',
    _DatePreset.custom: 'search_filter_date_custom',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget title(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
        );
    Widget hint(String key) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(t(key), style: theme.textTheme.bodySmall),
        );
    const hints = {
      SearchMode.smart: 'sunrise_on_the_beach',
      SearchMode.filename: 'search_by_filename_example',
      SearchMode.description: 'search_by_description_example',
      SearchMode.path: 'search_by_full_path_example',
      SearchMode.ocr: 'search_by_ocr_example',
    };
    final sections = [
      (_Section.type, Icons.search, t('search_type')),
      (_Section.people, Icons.person_outline, t('people')),
      (_Section.date, Icons.calendar_today_outlined, t('date')),
      (_Section.places, Icons.place_outlined, t('places')),
      if (_tagList.isNotEmpty || f.tagIds.isNotEmpty) (_Section.tags, Icons.sell_outlined, t('tags')),
      (_Section.media, Icons.image_outlined, t('media')),
    ];
    final q = _query.text.trim().toLowerCase();
    final history = settings.searchHistory.where((h) => h.toLowerCase().contains(q)).toList();
    final divider = Divider(height: 32, color: theme.dividerColor);

    // Like the web's panel under the search bar: anchored at the top, not centered.
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
      child: SizedBox(
        width: 760,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: TextField(
              controller: _query,
              autofocus: true,
              decoration: InputDecoration(
                hintText: t(hints[f.mode]!),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (history.isNotEmpty) ...[
                  Row(children: [
                    Expanded(child: Text(t('recent_searches'), style: theme.textTheme.titleSmall)),
                    if (q.isEmpty)
                      TextButton(
                        onPressed: () {
                          settings.update(searchHistory: []);
                          setState(() {});
                        },
                        child: Text(t('clear_all_recent_searches')),
                      ),
                  ]),
                  for (final h in history)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.history),
                      title: Text(h),
                      onTap: () => _submit(h),
                      trailing: IconButton(
                        tooltip: t('remove'),
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          settings.update(searchHistory: settings.searchHistory.where((x) => x != h).toList());
                          setState(() {});
                        },
                      ),
                    ),
                ],
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 12),
                  child: Text(t('filter_by'), style: theme.textTheme.titleSmall),
                ),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final (s, icon, label) in sections)
                    FilterChip(
                      avatar: Icon(icon, size: 18),
                      label: Text(_title(s) ?? label),
                      selected: _section == s || _title(s) != null,
                      showCheckmark: false,
                      side: _section == s ? BorderSide(color: theme.colorScheme.primary, width: 2) : null,
                      onSelected: (_) => setState(() => _section = s),
                    ),
                ]),
                const SizedBox(height: 20),
                switch (_section) {
                  _Section.type => _typeSection(hint),
                  _Section.people => _peopleSection(title),
                  _Section.date => _dateSection(hint),
                  _Section.places => _placesSection(hint),
                  _Section.tags => _tagsSection(title, hint),
                  _Section.media => _mediaSection(hint),
                },
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  alignment: Alignment.topCenter,
                  child: _advanced ? _advancedSection(title, divider) : const SizedBox(width: double.infinity),
                ),
              ]),
            ),
          ),
          divider,
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Row(children: [
              (_advancedSet ? OutlinedButton.icon : TextButton.icon)(
                onPressed: () => setState(() => _advanced = !_advanced),
                icon: const Icon(Icons.tune),
                label: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(t('advanced_filters')),
                  Icon(_advanced ? Icons.expand_less : Icons.expand_more, size: 18),
                ]),
              ),
              const Spacer(),
              OutlinedButton(onPressed: _clear, child: Text(t('clear_all'))),
              const SizedBox(width: 8),
              FilledButton(onPressed: _submit, child: Text(t('search'))),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _typeSection(Widget Function(String) hint) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        hint('search_type_description'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final m in SearchMode.values)
            ChoiceChip(
              label: Text(t(_modeLabels[m]!)),
              selected: f.mode == m,
              onSelected: (_) => setState(() => f.mode = m),
            ),
        ]),
      ]);

  Widget _dateSection(Widget Function(String) hint) {
    final preset = _customDate ? _DatePreset.custom : _datePreset;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      hint('search_filter_date_description'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final p in _DatePreset.values)
          ChoiceChip(
            label: Text(t(_presetLabels[p]!)),
            selected: preset == p,
            onSelected: (on) => setState(() {
              _customDate = on && p == _DatePreset.custom;
              if (!on) {
                f.takenAfter = f.takenBefore = null;
              } else if (p != _DatePreset.custom) {
                final (after, before) = _presetRange(p);
                f
                  ..takenAfter = after
                  ..takenBefore = before;
              }
            }),
          ),
      ]),
      if (preset == _DatePreset.custom) ...[
        const SizedBox(height: 12),
        _row([
          _DateField(label: t('start_date'), value: f.takenAfter, onChanged: (d) => setState(() => f.takenAfter = d)),
          _DateField(label: t('end_date'), value: f.takenBefore, onChanged: (d) => setState(() => f.takenBefore = d)),
        ]),
      ],
    ]);
  }

  Widget _placesSection(Widget Function(String) hint) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        hint('search_filter_location_description'),
        _row([
          _Suggest(
            key: ValueKey('country$_rev'),
            label: t('country'),
            value: f.country,
            load: () => widget.api.searchSuggestions('country'),
            onChanged: (v) => setState(() {
              f.country = v;
              f.state = null;
              f.city = null;
            }),
          ),
          _Suggest(
            key: ValueKey('state$_rev${f.country}'),
            label: t('state'),
            value: f.state,
            load: () => widget.api.searchSuggestions('state', country: f.country),
            onChanged: (v) => setState(() {
              f.state = v;
              f.city = null;
            }),
          ),
          _Suggest(
            key: ValueKey('city$_rev${f.country}${f.state}'),
            label: t('city'),
            value: f.city,
            load: () => widget.api.searchSuggestions('city', country: f.country, state: f.state),
            onChanged: (v) => setState(() => f.city = v),
          ),
        ]),
      ]);

  Widget _mediaSection(Widget Function(String) hint) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        hint('media_type_description'),
        Wrap(spacing: 8, children: [
          for (final (v, k) in [(null, 'all'), ('IMAGE', 'image'), ('VIDEO', 'video')])
            ChoiceChip(label: Text(t(k)), selected: f.type == v, onSelected: (_) => setState(() => f.type = v)),
        ]),
      ]);

  Widget _advancedSection(Widget Function(String) title, Widget divider) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        divider,
        title(t('camera')),
        _row([
          _Suggest(
            key: ValueKey('make$_rev'),
            label: t('make'),
            value: f.make,
            load: () => widget.api.searchSuggestions('camera-make'),
            onChanged: (v) => setState(() {
              f.make = v;
              f.model = null;
              f.lensModel = null;
            }),
          ),
          _Suggest(
            key: ValueKey('model$_rev${f.make}'),
            label: t('model'),
            value: f.model,
            load: () => widget.api.searchSuggestions('camera-model', make: f.make),
            onChanged: (v) => setState(() {
              f.model = v;
              f.lensModel = null;
            }),
          ),
          _Suggest(
            key: ValueKey('lens$_rev${f.make}${f.model}'),
            label: t('lens_model'),
            value: f.lensModel,
            load: () => widget.api.searchSuggestions('camera-lens-model', make: f.make, model: f.model),
            onChanged: (v) => setState(() => f.lensModel = v),
          ),
        ]),
        FutureBuilder<bool>(
          future: _ratings,
          builder: (context, snap) => snap.data == true || f.rating != null
              ? Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    title(t('rating')),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final r in [null, 0, 1, 2, 3, 4, 5])
                        ChoiceChip(
                          label: Text(r == null ? t('all') : t('rating_count', {'count': r})),
                          selected: f.rating == r,
                          onSelected: (_) => setState(() => f.rating = r),
                        ),
                    ]),
                  ]),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 20),
        title(t('display_options')),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (k, get, set) in [
            ('not_in_any_album', () => f.notInAlbum, (bool v) => f.notInAlbum = v),
            ('in_archive', () => f.inArchive, (bool v) => f.inArchive = v),
            ('only_favorites', () => f.isFavorite, (bool v) => f.isFavorite = v),
          ])
            FilterChip(label: Text(t(k)), selected: get(), onSelected: (v) => setState(() => set(v))),
        ]),
      ]);

  Widget _row(List<Widget> children) => Row(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: children[i]),
        ],
      ]);

  Widget _peopleSection(Widget Function(String) title) {
    return FutureBuilder<List<Person>>(
      future: _people,
      builder: (context, snap) {
        final all = snap.data ?? const <Person>[];
        if (all.isEmpty) return const SizedBox.shrink();
        final q = _personFilter.toLowerCase();
        // Selected people first, like the web.
        final matching = [
          ...all.where((p) => f.personIds.contains(p.id)),
          ...all.where((p) => !f.personIds.contains(p.id)),
        ].where((p) => q.isEmpty || p.name.toLowerCase().contains(q)).toList();
        final shown = _allPeople ? matching : matching.take(10).toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: title(t('people'))),
            SizedBox(
              width: 220,
              child: TextField(
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: t('search_people'),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _personFilter = v),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in shown)
              Stack(children: [
                Opacity(
                  opacity: f.personIds.isEmpty || f.personIds.contains(p.id) ? 1 : 0.5,
                  child: PersonAvatar(
                    api: widget.api,
                    person: p,
                    size: 64,
                    onTap: () => setState(() =>
                        f.personIds.contains(p.id) ? f.personIds.remove(p.id) : f.personIds.add(p.id)),
                  ),
                ),
                if (f.personIds.contains(p.id))
                  Positioned(
                    right: 4,
                    top: 0,
                    child: Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary, size: 22),
                  ),
              ]),
          ]),
          if (matching.length > 10)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _allPeople = !_allPeople),
                child: Text(_allPeople ? t('show_less') : t('show_all_people')),
              ),
            ),
        ]);
      },
    );
  }

  Widget _tagsSection(Widget Function(String) title, Widget Function(String) hint) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _tags,
      builder: (context, snap) {
        final tags = snap.data ?? const <Map<String, dynamic>>[];
        if (tags.isEmpty) return const SizedBox.shrink();
        String name(String id) => (tags.firstWhere((x) => x['id'] == id, orElse: () => {'value': id})['value']) as String;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          hint('search_filter_tags_description'),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final id in f.tagIds)
              InputChip(
                label: Text(name(id)),
                onDeleted: () => setState(() => f.tagIds.remove(id)),
              ),
            SizedBox(
              width: 260,
              child: DropdownMenu<String>(
                key: ValueKey('tags$_rev${f.tagIds.length}'),
                width: 260,
                hintText: t('search_tags'),
                enableFilter: true,
                requestFocusOnTap: true,
                menuHeight: 300,
                dropdownMenuEntries: [
                  for (final tag in tags)
                    if (!f.tagIds.contains(tag['id']))
                      DropdownMenuEntry(value: tag['id'] as String, label: tag['value'] as String),
                ],
                onSelected: (id) {
                  if (id != null) setState(() => f.tagIds.add(id));
                },
              ),
            ),
          ]),
        ]);
      },
    );
  }
}

/// A dropdown with type-to-filter whose options come from /search/suggestions.
class _Suggest extends StatefulWidget {
  final String label;
  final String? value;
  final Future<List<String>> Function() load;
  final ValueChanged<String?> onChanged;
  const _Suggest({super.key, required this.label, required this.value, required this.load, required this.onChanged});

  @override
  State<_Suggest> createState() => _SuggestState();
}

class _SuggestState extends State<_Suggest> {
  late final Future<List<String>> _options = widget.load().catchError((_) => <String>[]);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: _options,
      builder: (context, snap) {
        final options = snap.data ?? const <String>[];
        // DropdownMenu reads initialSelection once, so build it only when the options are in.
        return LayoutBuilder(
          builder: (context, c) => DropdownMenu<String?>(
            key: ValueKey(snap.hasData),
            width: c.maxWidth,
            label: Text(widget.label),
            initialSelection: snap.hasData ? widget.value : null,
            enableFilter: true,
            requestFocusOnTap: true,
            menuHeight: 320,
            enabled: snap.hasData,
            dropdownMenuEntries: [
              DropdownMenuEntry<String?>(value: null, label: t('all')),
              for (final o in options) DropdownMenuEntry<String?>(value: o, label: o),
            ],
            onSelected: widget.onChanged,
          ),
        );
      },
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  const _DateField({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: value == null
            ? null
            : IconButton(tooltip: t('clear'), icon: const Icon(Icons.close, size: 18), onPressed: () => onChanged(null)),
      ),
      child: InkWell(
        onTap: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: DateTime(1800),
            lastDate: DateTime(2200),
          );
          if (d != null) onChanged(d);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(value == null ? '—' : DateFormat.yMMMd(i18n.dateLocale).format(value!)),
        ),
      ),
    );
  }
}
