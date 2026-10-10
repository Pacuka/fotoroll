// Face editing in the viewer (web: PersonSidePanel, AssignFaceSidePanel, FaceEditor):
// reassign / unassign faces, tag a new face by drawing a box, and highlight faces.
import 'package:flutter/material.dart';

import '../api.dart';
import '../i18n.dart';
import '../screens/explore.dart' show PersonAvatar;

/// A face cut out of the asset's preview (like the web's face thumbnails).
class FaceCrop extends StatelessWidget {
  final ImmichApi api;
  final String assetId;
  final AssetFace face;
  final double size;
  const FaceCrop({super.key, required this.api, required this.assetId, required this.face, this.size = 64});

  @override
  Widget build(BuildContext context) {
    final r = face.rel;
    // Square around the box's centre, a little larger than the face.
    final side = (r.width > r.height * face.imageHeight / face.imageWidth.clamp(1, 1 << 30)
            ? r.width
            : r.height * face.imageHeight / face.imageWidth.clamp(1, 1 << 30)) *
        1.3;
    final cx = r.left + r.width / 2, cy = r.top + r.height / 2;
    final scale = size / side; // image width in px at this zoom
    final imgW = scale, imgH = scale * face.imageHeight / face.imageWidth.clamp(1, 1 << 30);
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(clipBehavior: Clip.hardEdge, children: [
          Positioned(
            left: size / 2 - cx * imgW,
            top: size / 2 - cy * imgH,
            width: imgW,
            height: imgH,
            child: Image(
              image: NetworkImage(api.thumbnailUrl(assetId, size: 'preview'), headers: api.headers),
              fit: BoxFit.fill,
              errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black26),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Result of [showPersonPicker]: an existing person, or a new one (optionally named).
class PersonPick {
  final Person? person;
  final String? newName;
  const PersonPick.existing(Person this.person) : newName = null;
  const PersonPick.create(this.newName) : person = null;
  bool get isNew => person == null;
}

Future<PersonPick?> showPersonPicker(BuildContext context, ImmichApi api, {required String title}) =>
    showDialog<PersonPick>(context: context, builder: (_) => _PersonPicker(api: api, title: title));

class _PersonPicker extends StatefulWidget {
  final ImmichApi api;
  final String title;
  const _PersonPicker({required this.api, required this.title});

  @override
  State<_PersonPicker> createState() => _PersonPickerState();
}

class _PersonPickerState extends State<_PersonPicker> {
  late final Future<List<Person>> _people = widget.api.people();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        height: 460,
        child: Column(children: [
          TextField(
            autofocus: true,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: t('search_people'),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
            onSubmitted: (_) {},
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_add_alt)),
            title: Text(_query.isEmpty ? t('create_new_person') : '${t('create_new_person')}: $_query'),
            onTap: () => Navigator.pop(context, PersonPick.create(_query.isEmpty ? null : _query)),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<Person>>(
              future: _people,
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final q = _query.toLowerCase();
                final list = snap.data!
                    .where((p) => q.isEmpty || p.name.toLowerCase().contains(q))
                    .toList()
                  ..sort((a, b) => (a.name.isEmpty ? 1 : 0) - (b.name.isEmpty ? 1 : 0));
                return GridView.extent(
                  maxCrossAxisExtent: 96,
                  padding: const EdgeInsets.only(top: 8),
                  childAspectRatio: 0.8,
                  children: [
                    for (final p in list)
                      PersonAvatar(
                        api: widget.api,
                        person: p,
                        size: 64,
                        onTap: () => Navigator.pop(context, PersonPick.existing(p)),
                      ),
                  ],
                );
              },
            ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(t('cancel')))],
    );
  }
}

/// Resolves a pick to a person id, creating the person if needed.
Future<String> personIdFor(ImmichApi api, PersonPick pick) async =>
    pick.person?.id ?? (await api.createPerson(name: pick.newName)).id;

/// "Edit faces" side panel: each face can go to another (or a new) person, or be
/// deleted. Changes apply on Done, like the web.
class EditFacesPanel extends StatefulWidget {
  final ImmichApi api;
  final String assetId;
  final VoidCallback onClose;
  /// Called after changes were saved, so the viewer reloads the asset.
  final VoidCallback onChanged;
  final ValueChanged<AssetFace?> onHover;
  const EditFacesPanel({
    super.key,
    required this.api,
    required this.assetId,
    required this.onClose,
    required this.onChanged,
    required this.onHover,
  });

  @override
  State<EditFacesPanel> createState() => _EditFacesPanelState();
}

class _EditFacesPanelState extends State<EditFacesPanel> {
  late Future<List<AssetFace>> _faces = widget.api.faces(widget.assetId);
  final _changes = <String, PersonPick>{}; // face id -> new person
  bool _saving = false;

  ImmichApi get api => widget.api;

  Future<void> _pick(AssetFace face) async {
    final pick = await showPersonPicker(context, api, title: t('select_person'));
    if (pick != null && mounted) setState(() => _changes[face.id] = pick);
  }

  Future<void> _delete(AssetFace face) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(t('confirm_delete_face', {'name': face.person?.name ?? ''})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('delete'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await api.deleteFace(face.id);
      setState(() {
        _changes.remove(face.id);
        _faces = api.faces(widget.assetId);
      });
      widget.onChanged();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t('error')}: $e')));
    }
  }

  Future<void> _done() async {
    if (_changes.isEmpty) return widget.onClose();
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      for (final MapEntry(key: faceId, value: pick) in _changes.entries) {
        await api.reassignFace(faceId, await personIdFor(api, pick));
      }
      messenger.showSnackBar(SnackBar(content: Text(t('people_edits_count', {'count': _changes.length}))));
      widget.onChanged();
      widget.onClose();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('${t('error')}: $e')));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Material (not a ColoredBox) so the list tiles' ink shows.
    return Material(
      color: theme.colorScheme.surface,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
          child: Row(children: [
            IconButton(tooltip: t('back'), icon: const Icon(Icons.arrow_back), onPressed: widget.onClose),
            Expanded(child: Text(t('edit_faces'), style: theme.textTheme.titleMedium)),
            _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : FilledButton(onPressed: _done, child: Text(t('done'))),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder<List<AssetFace>>(
            future: _faces,
            builder: (context, snap) {
              if (snap.hasError) return Center(child: Text('${t('error')}: ${snap.error}'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final faces = snap.data!;
              if (faces.isEmpty) return Center(child: Text(t('no_results')));
              return ListView(children: [
                for (final face in faces) _faceTile(face),
              ]);
            },
          ),
        ),
      ]),
    );
  }

  Widget _faceTile(AssetFace face) {
    final change = _changes[face.id];
    final name = change == null
        ? (face.person == null
            ? t('face_unassigned')
            : (face.person!.name.isEmpty ? t('add_a_name') : face.person!.name))
        : (change.isNew ? (change.newName ?? t('new_person')) : (change.person!.name.isEmpty ? t('add_a_name') : change.person!.name));
    return MouseRegion(
      onEnter: (_) => widget.onHover(face),
      onExit: (_) => widget.onHover(null),
      child: ListTile(
        leading: FaceCrop(api: api, assetId: widget.assetId, face: face, size: 48),
        title: Text(name, style: change != null ? TextStyle(color: Theme.of(context).colorScheme.primary) : null),
        subtitle: change != null && face.person != null ? Text('← ${face.person!.name.isEmpty ? t('face_unassigned') : face.person!.name}') : null,
        onTap: () => _pick(face),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (change != null)
            IconButton(
              tooltip: t('reset'),
              icon: const Icon(Icons.restart_alt),
              onPressed: () => setState(() => _changes.remove(face.id)),
            ),
          IconButton(tooltip: t('edit_people'), icon: const Icon(Icons.edit_outlined), onPressed: () => _pick(face)),
          if (face.person != null)
            IconButton(tooltip: t('delete_face'), icon: const Icon(Icons.delete_outline), onPressed: () => _delete(face)),
        ]),
      ),
    );
  }
}

/// Face boxes drawn over the image (fractions of its size).
class FaceBoxesPainter extends CustomPainter {
  final List<({double left, double top, double width, double height})> boxes;
  final Color color;
  FaceBoxesPainter(this.boxes, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final shade = Paint()..color = Colors.black.withValues(alpha: 0.25);
    for (final b in boxes) {
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(b.left * size.width, b.top * size.height, b.width * size.width, b.height * size.height),
        const Radius.circular(6),
      );
      canvas.drawRRect(r.inflate(2), shade..style = PaintingStyle.stroke..strokeWidth = 2);
      canvas.drawRRect(r, stroke);
    }
  }

  @override
  bool shouldRepaint(FaceBoxesPainter old) => old.boxes != boxes || old.color != color;
}

/// A movable, resizable box for tagging a face by hand (web: FaceEditor). Works
/// in fractions of the image so it doesn't care about zoom.
class FaceTagBox extends StatefulWidget {
  final Rect initial; // fractions
  final ValueChanged<Rect> onChanged;
  const FaceTagBox({super.key, required this.initial, required this.onChanged});

  @override
  State<FaceTagBox> createState() => _FaceTagBoxState();
}

class _FaceTagBoxState extends State<FaceTagBox> {
  late Rect _r = widget.initial;
  static const _minSize = 0.03;

  void _set(Rect r) {
    final w = r.width.clamp(_minSize, 1.0), h = r.height.clamp(_minSize, 1.0);
    final left = r.left.clamp(0.0, 1 - w), top = r.top.clamp(0.0, 1 - h);
    setState(() => _r = Rect.fromLTWH(left, top, w, h));
    widget.onChanged(_r);
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return LayoutBuilder(builder: (context, c) {
      final W = c.maxWidth, H = c.maxHeight;
      Offset rel(Offset d) => Offset(d.dx / W, d.dy / H);
      Widget handle(Alignment a, Rect Function(Rect r, Offset d) resize) => Align(
            alignment: a,
            child: GestureDetector(
              onPanUpdate: (e) => _set(resize(_r, rel(e.delta))),
              child: MouseRegion(
                cursor: a.x == a.y ? SystemMouseCursors.resizeUpLeftDownRight : SystemMouseCursors.resizeUpRightDownLeft,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                ),
              ),
            ),
          );
      return Stack(children: [
        // Darken everything but the box.
        IgnorePointer(
          child: CustomPaint(size: Size(W, H), painter: _ShadePainter(_r)),
        ),
        Positioned(
          left: _r.left * W - 8,
          top: _r.top * H - 8,
          width: _r.width * W + 16,
          height: _r.height * H + 16,
          child: Stack(children: [
            Positioned.fill(
              left: 8,
              top: 8,
              right: 8,
              bottom: 8,
              child: GestureDetector(
                onPanUpdate: (e) => _set(_r.shift(rel(e.delta))),
                child: MouseRegion(
                  cursor: SystemMouseCursors.move,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: color, width: 3),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            ),
            handle(Alignment.topLeft, (r, d) => Rect.fromLTRB(r.left + d.dx, r.top + d.dy, r.right, r.bottom)),
            handle(Alignment.topRight, (r, d) => Rect.fromLTRB(r.left, r.top + d.dy, r.right + d.dx, r.bottom)),
            handle(Alignment.bottomLeft, (r, d) => Rect.fromLTRB(r.left + d.dx, r.top, r.right, r.bottom + d.dy)),
            handle(Alignment.bottomRight, (r, d) => Rect.fromLTRB(r.left, r.top, r.right + d.dx, r.bottom + d.dy)),
          ]),
        ),
      ]);
    });
  }
}

class _ShadePainter extends CustomPainter {
  final Rect box;
  _ShadePainter(this.box);

  @override
  void paint(Canvas canvas, Size size) {
    final hole = Rect.fromLTWH(box.left * size.width, box.top * size.height, box.width * size.width, box.height * size.height);
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(6)));
    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.45));
  }

  @override
  bool shouldRepaint(_ShadePainter old) => old.box != box;
}
