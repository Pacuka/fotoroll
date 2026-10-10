// "Search options" dialog (web: SearchFilterModal): people, text mode, tags, place,
// camera, date range, rating, media type and display options.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../i18n.dart';
import '../screens/explore.dart' show PersonAvatar;

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

class _SearchFilterDialogState extends State<_SearchFilterDialog> {
  late SearchFilter f = widget.initial.copy();
  late final _query = TextEditingController(text: f.query);
  late final Future<List<Person>> _people =
      widget.api.people().then((l) => l.where((p) => p.name.isNotEmpty).toList());
  late final Future<List<Map<String, dynamic>>> _tags = widget.api.tags();
  late final Future<bool> _ratings =
      widget.api.preferences().then((p) => (p['ratings'] as Map?)?['enabled'] == true, onError: (_) => false);
  String _personFilter = '';
  bool _allPeople = false;
  int _rev = 0; // bumps on "Clear all" so dropdowns rebuild empty

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _clear() => setState(() {
        f = SearchFilter(mode: f.mode); // the web keeps the chosen text mode
        _query.clear();
        _rev++;
      });

  void _submit() {
    f.query = _query.text;
    Navigator.pop(context, f);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget title(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
        );
    return AlertDialog(
      icon: const Icon(Icons.tune),
      title: Text(t('search_options')),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _peopleSection(title),
            const SizedBox(height: 20),
            _textSection(title),
            _tagsSection(title),
            const SizedBox(height: 20),
            title(t('place')),
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
            const SizedBox(height: 20),
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
            const SizedBox(height: 20),
            title(t('date_range')),
            _row([
              _DateField(
                label: t('start_date'),
                value: f.takenAfter,
                onChanged: (d) => setState(() => f.takenAfter = d),
              ),
              _DateField(
                label: t('end_date'),
                value: f.takenBefore,
                onChanged: (d) => setState(() => f.takenBefore = d),
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
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  title(t('media_type')),
                  RadioGroup<String?>(
                    groupValue: f.type,
                    onChanged: (v) => setState(() => f.type = v),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (final (v, k) in [(null, 'all'), ('IMAGE', 'image'), ('VIDEO', 'video')])
                        RadioListTile<String?>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: v,
                          title: Text(t(k)),
                        ),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  title(t('display_options')),
                  for (final (k, get, set) in [
                    ('not_in_any_album', () => f.notInAlbum, (bool v) => f.notInAlbum = v),
                    ('in_archive', () => f.inArchive, (bool v) => f.inArchive = v),
                    ('only_favorites', () => f.isFavorite, (bool v) => f.isFavorite = v),
                  ])
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: get(),
                      title: Text(t(k)),
                      onChanged: (v) => setState(() => set(v ?? false)),
                    ),
                ]),
              ),
            ]),
          ]),
        ),
      ),
      actions: [
        OutlinedButton(onPressed: _clear, child: Text(t('clear_all'))),
        FilledButton(onPressed: _submit, child: Text(t('search'))),
      ],
    );
  }

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

  Widget _textSection(Widget Function(String) title) {
    const hints = {
      SearchMode.smart: 'sunrise_on_the_beach',
      SearchMode.filename: 'search_by_filename_example',
      SearchMode.description: 'search_by_description_example',
      SearchMode.path: 'search_by_full_path_example',
      SearchMode.ocr: 'search_by_ocr_example',
    };
    const labels = {
      SearchMode.smart: 'context',
      SearchMode.filename: 'file_name_or_extension',
      SearchMode.description: 'description',
      SearchMode.path: 'path',
      SearchMode.ocr: 'ocr',
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      title(t('search_type')),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final m in SearchMode.values)
          ChoiceChip(
            label: Text(t(labels[m]!)),
            selected: f.mode == m,
            onSelected: (_) => setState(() => f.mode = m),
          ),
      ]),
      const SizedBox(height: 10),
      TextField(
        controller: _query,
        autofocus: true,
        decoration: InputDecoration(hintText: t(hints[f.mode]!), border: const OutlineInputBorder()),
        onSubmitted: (_) => _submit(),
      ),
    ]);
  }

  Widget _tagsSection(Widget Function(String) title) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _tags,
      builder: (context, snap) {
        final tags = snap.data ?? const <Map<String, dynamic>>[];
        if (tags.isEmpty) return const SizedBox.shrink();
        String name(String id) => (tags.firstWhere((x) => x['id'] == id, orElse: () => {'value': id})['value']) as String;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 20),
          title(t('tags')),
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
