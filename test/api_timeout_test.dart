// A server that stops answering must not hang the app: JSON calls and stalled
// downloads/uploads fail with a readable timeout error.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fotoroll/api.dart';
import 'package:fotoroll/i18n.dart';

void main() {
  late HttpServer server;
  late ImmichApi api;
  late Directory tmp;

  setUpAll(() => i18n.setMessages({}, {'linux_err_timeout': 'timed out'}, 'en'));

  setUp(() async {
    ImmichApi.requestTimeout = const Duration(milliseconds: 500);
    ImmichApi.stallTimeout = const Duration(milliseconds: 500);
    tmp = Directory.systemTemp.createTempSync('fotoroll_timeout');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final path = req.uri.path;
      if (path.endsWith('/original')) {
        // Headers and a first chunk, then nothing more.
        req.response.contentLength = 1000;
        req.response.add(List.filled(10, 1));
        await req.response.flush();
      } else if (path == '/api/assets' && req.method == 'POST') {
        // Read the whole upload, then never answer.
        await req.drain<void>();
      }
      // Everything else: never answers.
    });
    api = ImmichApi(Credentials(serverUrl: 'http://127.0.0.1:${server.port}', apiKey: 'k'));
  });

  tearDown(() async {
    api.close();
    await server.close(force: true);
    tmp.deleteSync(recursive: true);
  });

  Matcher timedOut() => throwsA(isA<ApiException>().having((e) => e.message, 'message', 'timed out'));

  test('JSON call', () async {
    final sw = Stopwatch()..start();
    await expectLater(api.me(), timedOut());
    expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('stalled download leaves no file behind', () async {
    final target = File('${tmp.path}/x.jpg');
    await expectLater(api.downloadOriginal('a', target), timedOut());
    expect(target.existsSync(), isFalse);
    expect(File('${target.path}.part').existsSync(), isFalse);
  });

  test('upload whose response never comes', () async {
    final f = File('${tmp.path}/up.jpg')..writeAsBytesSync(List.filled(2048, 7));
    await expectLater(
        api.uploadAsset(f, createdAt: DateTime(2026), modifiedAt: DateTime(2026)), timedOut());
  });
}
