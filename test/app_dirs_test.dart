import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fotoroll/app_dirs.dart';
import 'package:path/path.dart' as p;

void main() {
  test('moves our files from the legacy immich-linux folders, nothing else, never overwriting', () async {
    final tmp = await Directory.systemTemp.createTemp('fotoroll_dirs');
    final cfg = p.join(tmp.path, 'config'), data = p.join(tmp.path, 'data');
    Future<void> put(String path, String text) async {
      await File(path).create(recursive: true);
      await File(path).writeAsString(text);
    }

    await put(p.join(cfg, 'immich-linux', 'settings.json'), 'old-settings');
    await put(p.join(cfg, 'immich-linux', 'backup.json'), 'old-backup');
    await put(p.join(cfg, 'fotoroll', 'backup.json'), 'new-backup'); // already migrated
    await put(p.join(data, 'immich-linux', 'backup-abc.json'), 'state');
    await put(p.join(data, 'immich-linux', 'immich_linux'), 'old app binary');

    await migrateLegacyDirs(configBase: cfg, dataBase: data);

    expect(await File(p.join(cfg, 'fotoroll', 'settings.json')).readAsString(), 'old-settings');
    expect(await File(p.join(cfg, 'fotoroll', 'backup.json')).readAsString(), 'new-backup');
    expect(await File(p.join(data, 'fotoroll', 'backup-abc.json')).readAsString(), 'state');
    expect(File(p.join(data, 'fotoroll', 'immich_linux')).existsSync(), isFalse);
    expect(File(p.join(data, 'immich-linux', 'immich_linux')).existsSync(), isTrue);

    await migrateLegacyDirs(configBase: cfg, dataBase: data); // second run is a no-op
    await tmp.delete(recursive: true);
  });
}
