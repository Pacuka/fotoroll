// Persists credentials in the system keyring (libsecret / Secret Service).
// Falls back to a 0600 file in ~/.config if no keyring is available.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;

import 'api.dart';
import 'app_dirs.dart';

class SessionStore {
  static const _key = 'immich_credentials';
  final _secure = const FlutterSecureStorage();

  File get _fallbackFile => File(p.join(appConfigDir(), 'credentials.json'));

  Future<Credentials?> load() async {
    String? raw;
    try {
      raw = await _secure.read(key: _key);
    } catch (_) {}
    if (raw == null && await _fallbackFile.exists()) {
      raw = await _fallbackFile.readAsString();
    }
    if (raw == null) return null;
    try {
      return Credentials.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> save(Credentials c) async {
    final raw = jsonEncode(c.toJson());
    try {
      await _secure.write(key: _key, value: raw);
      return;
    } catch (_) {}
    final f = _fallbackFile;
    await f.parent.create(recursive: true);
    // Restrict permissions before any secret is written; never write it if that fails.
    await f.writeAsString('');
    final chmod = await Process.run('chmod', ['600', f.path]);
    if (chmod.exitCode != 0) {
      await f.delete();
      throw const FileSystemException('Could not protect the credentials file');
    }
    await f.writeAsString(raw);
  }

  Future<void> clear() async {
    try {
      await _secure.delete(key: _key);
    } catch (_) {}
    if (await _fallbackFile.exists()) await _fallbackFile.delete();
  }
}
