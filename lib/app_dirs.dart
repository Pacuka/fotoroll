// Where Fotoroll keeps its files (XDG base dirs), plus a one-time move from the
// folders used while the app was still called "immich-linux".
import 'dart:io';

import 'package:path/path.dart' as p;

const appDirName = 'fotoroll';
const _legacyDirName = 'immich-linux';

String _home() => Platform.environment['HOME'] ?? '.';
String _configBase() => Platform.environment['XDG_CONFIG_HOME'] ?? p.join(_home(), '.config');
String _dataBase() => Platform.environment['XDG_DATA_HOME'] ?? p.join(_home(), '.local', 'share');

/// ~/.config/fotoroll: app settings, backup settings, credentials fallback.
String appConfigDir() => p.join(_configBase(), appDirName);

/// ~/.local/share/fotoroll: backup state (which files were already uploaded).
String appDataDir() => p.join(_dataBase(), appDirName);

/// Moves our own files from the legacy folders; anything else there (e.g. an old
/// install of the app itself) is left alone. Never overwrites newer files.
Future<void> migrateLegacyDirs({String? configBase, String? dataBase}) async {
  Future<void> move(String base, bool Function(String name) ours) async {
    final from = Directory(p.join(base, _legacyDirName));
    if (!await from.exists()) return;
    final to = Directory(p.join(base, appDirName));
    try {
      await for (final e in from.list()) {
        final name = p.basename(e.path);
        if (e is! File || !ours(name)) continue;
        final target = File(p.join(to.path, name));
        if (await target.exists()) continue;
        await to.create(recursive: true);
        await e.rename(target.path);
      }
    } catch (_) {}
  }

  await move(configBase ?? _configBase(),
      (n) => n == 'settings.json' || n == 'backup.json' || n == 'credentials.json');
  await move(dataBase ?? _dataBase(), (n) => n.startsWith('backup-') && n.endsWith('.json'));
}
