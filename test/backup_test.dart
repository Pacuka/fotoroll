// End-to-end backup run against a fake server.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotoroll/api.dart';
import 'package:fotoroll/backup.dart';
import 'package:path/path.dart' as p;

void main() {
  late HttpServer server;
  late Directory tmp;
  late ImmichApi api;
  final serverHashes = <String>{}; // checksums the server "already has"
  final uploads = <Map<String, String>>[];

  setUp(() async {
    serverHashes.clear();
    uploads.clear();
    tmp = await Directory.systemTemp.createTemp('immich_backup');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    api = ImmichApi(Credentials(serverUrl: 'http://127.0.0.1:${server.port}', apiKey: 'k'));
    server.listen((req) async {
      final res = req.response..headers.contentType = ContentType.json;
      switch (req.uri.path) {
        case '/api/server/media-types':
          res.write(jsonEncode({'image': ['.jpg', '.png'], 'video': ['.mp4'], 'sidecar': ['.xmp']}));
        case '/api/assets/bulk-upload-check':
          final j = jsonDecode(await utf8.decodeStream(req));
          res.write(jsonEncode({
            'results': [
              for (final a in j['assets'])
                serverHashes.contains(a['checksum'])
                    ? {'id': a['id'], 'action': 'reject', 'reason': 'duplicate', 'assetId': 'x'}
                    : {'id': a['id'], 'action': 'accept'},
            ],
          }));
        case '/api/assets':
          final body = await utf8.decodeStream(req);
          final fields = <String, String>{};
          for (final m in RegExp(r'name="(\w+)"(?:; filename="([^"]*)")?\r\n(?:[^\r\n]+\r\n)*\r\n([^\r]*)')
              .allMatches(body)) {
            fields[m[1]!] = m[2] ?? m[3]!;
          }
          final content = RegExp(r'filename="[^"]*"\r\n(?:[^\r\n]+\r\n)*\r\n([^\r]*)').firstMatch(body)![1]!;
          serverHashes.add(sha1.convert(utf8.encode(content)).toString());
          uploads.add(fields);
          res.statusCode = 201;
          res.write(jsonEncode({'id': 'new-${uploads.length}', 'status': 'created'}));
        default:
          res.statusCode = 404;
      }
      await res.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await tmp.delete(recursive: true);
  });

  Future<File> write(String rel, String content) async {
    final f = File(p.join(tmp.path, 'photos', rel));
    await f.parent.create(recursive: true);
    await f.writeAsString(content);
    // Older than the "still being written" window.
    await f.setLastModified(DateTime.now().subtract(const Duration(minutes: 5)));
    return f;
  }

  BackupService make() => BackupService(api,
      userId: 'u1', configDir: p.join(tmp.path, 'cfg'), dataDir: p.join(tmp.path, 'data'));

  test('candidate filter honours extensions, exclusions and hidden dirs', () {
    final s = BackupSettings(folders: ['/r'], excluded: ['/r/skip']);
    final ext = {'.jpg'};
    expect(isBackupCandidate('/r/a/b.JPG', '/r', s, ext), isTrue);
    expect(isBackupCandidate('/r/a/b.txt', '/r', s, ext), isFalse);
    expect(isBackupCandidate('/r/skip/b.jpg', '/r', s, ext), isFalse);
    expect(isBackupCandidate('/r/skipper/b.jpg', '/r', s, ext), isTrue);
    expect(isBackupCandidate('/r/.cache/b.jpg', '/r', s, ext), isFalse);
    s.skipHidden = false;
    expect(isBackupCandidate('/r/.cache/b.jpg', '/r', s, ext), isTrue);
  });

  test('uploads new files, skips duplicates, remembers state, reuploads changes', () async {
    await write('a.jpg', 'AAA');
    await write('sub/b.mp4', 'BBB');
    await write('notes.txt', 'ignored');
    await write('.hidden/c.jpg', 'CCC');
    await write('skip/d.jpg', 'DDD');
    serverHashes.add(sha1.convert(utf8.encode('BBB')).toString()); // already on server

    final b = make();
    await b.init();
    await b.updateSettings((s) {
      s.folders.add(p.join(tmp.path, 'photos'));
      s.excluded.add(p.join(tmp.path, 'photos', 'skip'));
    });
    await b.runNow();

    expect(b.phase, BackupPhase.idle, reason: '${b.phaseMessage} ${b.errors.map((e) => e.message)}');
    expect(b.total, 2);
    expect(b.backedUp, 2);
    expect(uploads, hasLength(1));
    expect(uploads.single['filename'], 'a.jpg');
    expect(uploads.single['assetData'], 'a.jpg');
    expect(uploads.single.containsKey('fileCreatedAt'), isTrue);
    b.dispose();

    // A fresh service (app restart) trusts the saved state: no uploads, no re-hash needed.
    final b2 = make();
    await b2.init();
    await b2.runNow();
    expect(uploads, hasLength(1));
    expect(b2.remaining, 0);

    // A changed file is uploaded again.
    await write('a.jpg', 'AAA2');
    await b2.runNow();
    expect(uploads, hasLength(2));
    expect(b2.backedUp, 2);
    b2.dispose();
  });

  test('freshly written files wait for the next pass', () async {
    final f = await write('new.jpg', 'NEW');
    await f.setLastModified(DateTime.now());
    final b = make();
    await b.init();
    await b.updateSettings((s) => s.folders.add(p.join(tmp.path, 'photos')));
    await b.runNow();
    expect(uploads, isEmpty);
    expect(b.remaining, 1);
    b.dispose();
  });

  test('many duplicates in one batch leave a valid state file (saves never overlap)', () async {
    for (var i = 0; i < 120; i++) {
      await write('dup$i.jpg', 'D$i');
      serverHashes.add(sha1.convert(utf8.encode('D$i')).toString());
    }
    final b = make();
    await b.init();
    await b.updateSettings((s) => s.folders.add(p.join(tmp.path, 'photos')));
    await b.runNow();
    expect(b.backedUp, 120);
    expect(b.errors, isEmpty);
    b.dispose();

    final b2 = make();
    await b2.init();
    await b2.runNow();
    expect(b2.remaining, 0, reason: 'state file was written intact');
    expect(uploads, isEmpty);
    b2.dispose();
  });
}
