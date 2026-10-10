import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fotoroll/widgets/upload_dialog.dart';
import 'package:fotoroll/window.dart';
import 'package:path/path.dart' as p;

void main() {
  test('dropped folders are searched for media; hidden folders and other files are skipped', () async {
    final tmp = await Directory.systemTemp.createTemp('fotoroll_drop');
    Future<String> put(String rel) async {
      final f = File(p.join(tmp.path, rel));
      await f.create(recursive: true);
      return f.path;
    }

    final single = await put('loose/a.JPG');
    await put('trip/b.jpg');
    await put('trip/day2/c.mp4');
    await put('trip/notes.txt');
    await put('trip/.thumbnails/d.jpg');
    final files = await mediaFilesIn([single, p.join(tmp.path, 'trip'), p.join(tmp.path, 'missing')], {'.jpg', '.mp4'});
    expect(files.map((f) => p.relative(f, from: tmp.path)), ['loose/a.JPG', 'trip/b.jpg', 'trip/day2/c.mp4']);
    await tmp.delete(recursive: true);
  });

  test('autostart entry starts the app hidden in the tray', () {
    final e = autostartEntry('/home/x/.local/lib/fotoroll/fotoroll');
    expect(e, contains('Exec="/home/x/.local/lib/fotoroll/fotoroll" --hidden'));
    expect(e, contains('Type=Application'));
    expect(e, contains('Icon=io.github.pacuka.Fotoroll'));
  });
}
