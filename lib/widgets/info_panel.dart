// Asset info panel (web: DetailPanel): description, date, file, camera, location,
// rating, people, albums and tags — editable like on the web when [canEdit].
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../api.dart';
import '../i18n.dart';
import '../screens/albums.dart';
import '../screens/explore.dart';
import '../screens/utilities.dart' show formatBytes;

class InfoPanel extends StatefulWidget {
  final ImmichApi api;
  final Map<String, dynamic>? detail;
  final List<Album>? albums;
  final bool canEdit;
  final ValueChanged<Map<String, dynamic>> onChanged;
  /// Called when an edit finishes, so the viewer can take keyboard focus back
  /// (arrow keys page again, like on the web).
  final VoidCallback? onEditingDone;

  const InfoPanel({
    super.key,
    required this.api,
    required this.detail,
    required this.albums,
    required this.canEdit,
    required this.onChanged,
    this.onEditingDone,
  });

  @override
  State<InfoPanel> createState() => _InfoPanelState();
}

class _InfoPanelState extends State<InfoPanel> {
  final _desc = TextEditingController();
  final _descFocus = FocusNode();
  String? _descFor;

  ImmichApi get api => widget.api;

  @override
  void initState() {
    super.initState();
    _descFocus.addListener(() {
      if (!_descFocus.hasFocus) _saveDescription();
    });
  }

  @override
  void didUpdateWidget(InfoPanel old) {
    super.didUpdateWidget(old);
    // Moving to another photo while typing: save the text to the photo it was typed for.
    final prev = old.detail;
    if (prev != null && prev['id'] == _descFor && widget.detail?['id'] != _descFor) {
      final before = ((prev['exifInfo'] as Map?)?['description'] as String?) ?? '';
      final text = _desc.text;
      if (text != before) {
        api.updateAsset(prev['id'], {'description': text}).catchError((Object e) {
          if (mounted) _toast('${t('error')}: $e');
          return <String, dynamic>{};
        });
      }
    }
  }

  @override
  void dispose() {
    _desc.dispose();
    _descFocus.dispose();
    super.dispose();
  }

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  /// Applies a change on the server, then reloads the asset so the panel shows saved state.
  Future<void> _apply(Future<void> Function(String id) f) async {
    final d = widget.detail;
    if (d == null) return;
    try {
      await f(d['id']);
      final fresh = await api.asset(d['id']);
      if (mounted) widget.onChanged(fresh);
    } catch (e) {
      if (mounted) _toast('${t('error')}: $e');
    }
  }

  Map<String, dynamic> get _exif => (widget.detail?['exifInfo'] as Map?)?.cast<String, dynamic>() ?? {};

  Future<void> _saveDescription() async {
    final current = (_exif['description'] as String?) ?? '';
    if (_desc.text == current) return;
    await _apply((id) => api.updateAsset(id, {'description': _desc.text}));
  }

  Future<void> _editDate(DateTime local) async {
    final day = await showDatePicker(
      context: context,
      initialDate: local,
      firstDate: DateTime(1800),
      lastDate: DateTime(2200),
      helpText: t('edit_date_and_time'),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(local));
    widget.onEditingDone?.call();
    if (time == null) return;
    // Keep the photo's own UTC offset (local capture time − UTC time), like the web default.
    final d = widget.detail!;
    final utc = DateTime.tryParse(d['fileCreatedAt'] ?? '')?.toUtc();
    final naiveLocal = DateTime.tryParse((d['localDateTime'] as String? ?? '').replaceAll('Z', ''));
    final offset = utc != null && naiveLocal != null
        ? DateTime.utc(naiveLocal.year, naiveLocal.month, naiveLocal.day, naiveLocal.hour, naiveLocal.minute,
                naiveLocal.second)
            .difference(utc)
        : DateTime.now().timeZoneOffset;
    final picked = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    String two(int v) => v.abs().toString().padLeft(2, '0');
    final sign = offset.isNegative ? '-' : '+';
    final iso = '${DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(picked)}.000'
        '$sign${two(offset.inHours)}:${two(offset.inMinutes.remainder(60))}';
    await _apply((id) => api.updateAsset(id, {'dateTimeOriginal': iso}));
  }

  Future<void> _editLocation() async {
    final lat = (_exif['latitude'] as num?)?.toDouble();
    final lon = (_exif['longitude'] as num?)?.toDouble();
    final picked = await showDialog<LatLng>(
      context: context,
      builder: (_) => _LocationDialog(initial: lat != null && lon != null ? LatLng(lat, lon) : null),
    );
    widget.onEditingDone?.call();
    if (picked == null) return;
    await _apply((id) => api.updateAsset(id, {'latitude': picked.latitude, 'longitude': picked.longitude}));
  }

  Future<void> _setRating(int? current, int value) async {
    widget.onEditingDone?.call();
    await _apply((id) => api.updateAsset(id, {'rating': current == value ? null : value}));
  }

  Future<void> _addTag() async {
    final picked = await showDialog<String>(context: context, builder: (_) => _TagPicker(api: api));
    widget.onEditingDone?.call();
    if (picked == null || picked.trim().isEmpty) return;
    await _apply((id) async {
      final tags = await api.upsertTags([picked.trim()]);
      await api.tagAssets([for (final t in tags) t['id'] as String], [id]);
    });
  }

  void _push(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = widget.detail;
    if (d == null) {
      return ColoredBox(color: theme.colorScheme.surface, child: const Center(child: CircularProgressIndicator()));
    }
    final exif = _exif;
    if (_descFor != d['id'] || !_descFocus.hasFocus) {
      _descFor = d['id'];
      _desc.text = (exif['description'] as String?) ?? '';
    }
    final taken = DateTime.tryParse((d['localDateTime'] as String? ?? d['fileCreatedAt'] ?? '').replaceAll('Z', ''));
    final size = (exif['fileSizeInByte'] as num?)?.toInt();
    final w = exif['exifImageWidth'] ?? d['width'];
    final h = exif['exifImageHeight'] ?? d['height'];
    final camera = [exif['make'], exif['model']].whereType<String>().join(' ');
    final shot = [
      if (exif['fNumber'] != null) 'ƒ/${exif['fNumber']}',
      if (exif['exposureTime'] != null) '${exif['exposureTime']} s',
      if (exif['focalLength'] != null) '${exif['focalLength']} mm',
      if (exif['iso'] != null) 'ISO ${exif['iso']}',
    ].join('  ·  ');
    final place = [exif['city'], exif['state'], exif['country']].whereType<String>().join(', ');
    final people = ((d['people'] as List?) ?? [])
        .map((e) => Person.fromJson(e as Map<String, dynamic>))
        .where((p) => !p.isHidden)
        .toList();
    final tags = ((d['tags'] as List?) ?? []).cast<Map<String, dynamic>>();
    final rating = (exif['rating'] as num?)?.toInt();
    final edit = widget.canEdit;

    Widget row(IconData icon, String title, {String? sub, VoidCallback? onTap}) => ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: sub == null || sub.isEmpty ? null : Text(sub),
          trailing: onTap != null ? const Icon(Icons.edit_outlined, size: 18) : null,
          onTap: onTap,
        );

    return Material(
      color: theme.colorScheme.surface,
      child: ListView(padding: const EdgeInsets.symmetric(vertical: 16), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(t('info'), style: theme.textTheme.titleLarge),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _desc,
            focusNode: _descFocus,
            enabled: edit,
            minLines: 1,
            maxLines: 5,
            decoration: InputDecoration(hintText: t('add_a_description'), border: InputBorder.none),
            onSubmitted: (_) {
              _saveDescription();
              widget.onEditingDone?.call();
            },
          ),
        ),
        if (taken != null)
          row(Icons.calendar_today, DateFormat.yMMMMEEEEd(i18n.dateLocale).format(taken),
              sub: DateFormat.Hm(i18n.dateLocale).format(taken), onTap: edit ? () => _editDate(taken) : null),
        row(Icons.image_outlined, d['originalFileName'] ?? '',
            sub: [if (w != null && h != null) '$w × $h', if (size != null) formatBytes(size)].join('  ·  ')),
        if (camera.isNotEmpty) row(Icons.camera_alt_outlined, camera, sub: shot),
        if (exif['lensModel'] != null) row(Icons.camera, exif['lensModel']),
        if (place.isNotEmpty || edit)
          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: Text(place.isNotEmpty ? place : t('add_a_location')),
            subtitle: exif['latitude'] != null
                ? Text('${(exif['latitude'] as num).toStringAsFixed(5)}, '
                    '${(exif['longitude'] as num).toStringAsFixed(5)}')
                : null,
            trailing: edit
                ? IconButton(
                    tooltip: t('edit_location'), icon: const Icon(Icons.edit_location_alt_outlined), onPressed: _editLocation)
                : null,
            onTap: exif['city'] != null
                ? () => _push(PlaceScreen(api: api, place: Place(exif['city'], exif['country'], d['id'])))
                : (edit ? _editLocation : null),
          ),
        ListTile(
          leading: const Icon(Icons.star_outline),
          title: Row(children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '$i',
                onPressed: edit ? () => _setRating(rating, i) : null,
                icon: Icon(rating != null && i <= rating ? Icons.star : Icons.star_border,
                    color: rating != null && i <= rating ? Colors.amber : null),
              ),
          ]),
        ),
        if (people.isNotEmpty) ...[
          _heading(t('linux_people_in_photo')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 12, runSpacing: 12, children: [
              for (final person in people)
                SizedBox(
                  width: 84,
                  child: PersonAvatar(
                    api: api,
                    person: person,
                    size: 72,
                    subtitle: person.birthDate == null || taken == null ? null : ageAt(person.birthDate!, taken),
                    onTap: () => _push(PersonScreen(api: api, person: person)),
                  ),
                ),
            ]),
          ),
        ],
        if (widget.albums?.isNotEmpty ?? false) ...[
          _heading(t('linux_in_albums')),
          for (final album in widget.albums!)
            ListTile(
              leading: const Icon(Icons.photo_album_outlined),
              title: Text(album.name),
              subtitle: Text(t('items_count', {'count': album.assetCount})),
              onTap: () => _push(AlbumScreen(api: api, album: album)),
            ),
        ],
        if (tags.isNotEmpty || edit) ...[
          _heading(t('tags')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final tag in tags)
                InputChip(
                  avatar: const Icon(Icons.sell_outlined, size: 16),
                  label: Text((tag['value'] ?? tag['name'] ?? '') as String),
                  deleteButtonTooltipMessage: t('remove_tag'),
                  onDeleted: edit ? () => _apply((id) => api.untagAssets(tag['id'], [id])) : null,
                ),
              if (edit)
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: Text(t('add_tag')),
                  onPressed: _addTag,
                ),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}

/// Pick a point on an OpenStreetMap map (web: change location modal).
class _LocationDialog extends StatefulWidget {
  final LatLng? initial;
  const _LocationDialog({this.initial});

  @override
  State<_LocationDialog> createState() => _LocationDialogState();
}

class _LocationDialogState extends State<_LocationDialog> {
  late LatLng? _point = widget.initial;
  late final _lat = TextEditingController(text: widget.initial?.latitude.toStringAsFixed(6) ?? '');
  late final _lon = TextEditingController(text: widget.initial?.longitude.toStringAsFixed(6) ?? '');

  void _set(LatLng p) => setState(() {
        _point = p;
        _lat.text = p.latitude.toStringAsFixed(6);
        _lon.text = p.longitude.toStringAsFixed(6);
      });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t('edit_location')),
      content: SizedBox(
        width: 640,
        height: 460,
        child: Column(children: [
          Text(t('linux_pick_on_map')),
          const SizedBox(height: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: widget.initial ?? const LatLng(47.5, 19.05),
                  initialZoom: widget.initial != null ? 13 : 4,
                  onTap: (_, p) => _set(p),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'io.github.pacuka.Fotoroll',
                  ),
                  if (_point != null)
                    MarkerLayer(markers: [
                      Marker(
                        point: _point!,
                        width: 40,
                        height: 40,
                        alignment: Alignment.topCenter,
                        child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                      ),
                    ]),
                  const SimpleAttributionWidget(source: Text('© OpenStreetMap')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _lat,
                decoration: InputDecoration(labelText: t('latitude')),
                onChanged: (v) {
                  final lat = double.tryParse(v);
                  final lon = double.tryParse(_lon.text);
                  if (lat != null && lon != null) setState(() => _point = LatLng(lat.clamp(-90, 90), lon));
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _lon,
                decoration: InputDecoration(labelText: t('longitude')),
                onChanged: (v) {
                  final lat = double.tryParse(_lat.text);
                  final lon = double.tryParse(v);
                  if (lat != null && lon != null) setState(() => _point = LatLng(lat, lon.clamp(-180, 180)));
                },
              ),
            ),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t('cancel'))),
        FilledButton(
          onPressed: _point == null ? null : () => Navigator.pop(context, _point),
          child: Text(t('save')),
        ),
      ],
    );
  }
}

/// Choose an existing tag or type a new one (slashes make nested tags, like the web).
class _TagPicker extends StatefulWidget {
  final ImmichApi api;
  const _TagPicker({required this.api});

  @override
  State<_TagPicker> createState() => _TagPickerState();
}

class _TagPickerState extends State<_TagPicker> {
  late final Future<List<Map<String, dynamic>>> _tags = widget.api.tags();
  final _ctl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final q = _ctl.text.trim().toLowerCase();
    return AlertDialog(
      title: Text(t('add_tag')),
      content: SizedBox(
        width: 400,
        height: 420,
        child: Column(children: [
          TextField(
            controller: _ctl,
            autofocus: true,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: t('linux_new_tag_hint'),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _tags,
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final list = snap.data!
                    .map((e) => (e['value'] ?? e['name'] ?? '') as String)
                    .where((v) => q.isEmpty || v.toLowerCase().contains(q))
                    .toList()
                  ..sort();
                return ListView(children: [
                  if (q.isNotEmpty && !list.any((v) => v.toLowerCase() == q))
                    ListTile(
                      leading: const Icon(Icons.add),
                      title: Text('${t('create_tag')}: ${_ctl.text.trim()}'),
                      onTap: () => Navigator.pop(context, _ctl.text.trim()),
                    ),
                  for (final v in list)
                    ListTile(
                      leading: const Icon(Icons.sell_outlined),
                      title: Text(v),
                      onTap: () => Navigator.pop(context, v),
                    ),
                ]);
              },
            ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(t('cancel')))],
    );
  }
}
