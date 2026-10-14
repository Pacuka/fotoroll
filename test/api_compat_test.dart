// Endpoints that moved in Immich v3.3: the client uses the new ones and falls
// back to the v3.1 ones when the server answers 404.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fotoroll/api.dart';
import 'package:fotoroll/i18n.dart';

const _p1 = '11111111-1111-4111-8111-111111111111';
const _p2 = '22222222-2222-4222-8222-222222222222';
const _p3 = '33333333-3333-4333-8333-333333333333';

void main() {
  late HttpServer server;
  late ImmichApi api;
  final calls = <String>[];
  var v33 = true;
  var broken = false;

  setUpAll(() => i18n.setMessages({}, {}, 'en'));

  setUp(() async {
    calls.clear();
    broken = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    api = ImmichApi(Credentials(serverUrl: 'http://127.0.0.1:${server.port}', apiKey: 'k'));
    server.listen((req) async {
      final body = await utf8.decodeStream(req);
      final key = '${req.method} ${req.uri.path}';
      calls.add(body.isEmpty ? key : '$key $body');
      final res = req.response..headers.contentType = ContentType.json;
      final config = {'trash': {'enabled': true, 'days': 30}};
      final Object? out = switch (key) {
        'GET /api/config' when v33 => {'trash': {'enabled': true, 'days': 45}},
        'GET /api/server/config' => {'trashDays': 30},
        'GET /api/admin/config' || 'GET /api/admin/config/defaults' || 'PUT /api/admin/config' when v33 =>
          config,
        'GET /api/system-config' || 'GET /api/system-config/defaults' || 'PUT /api/system-config' => config,
        'POST /api/people/merge' when v33 => [],
        'POST /api/people/$_p1/merge' => [],
        _ => null,
      };
      if (broken) {
        res.statusCode = 500;
        res.write('{}');
      } else if (out == null) {
        res.statusCode = 404;
        res.write(jsonEncode({'message': 'Cannot $key'}));
      } else {
        res.write(jsonEncode(out));
      }
      await res.close();
    });
  });

  tearDown(() => server.close(force: true));

  test('v3.3 server: new endpoints only', () async {
    v33 = true;
    expect(await api.trashDays(), 45);
    expect((await api.systemConfig())['trash'], isNotNull);
    await api.systemConfigDefaults();
    await api.updateSystemConfig({'trash': {'enabled': true, 'days': 30}});
    await api.mergePeople(_p1, [_p2, _p3]);
    expect(calls, [
      'GET /api/config',
      'GET /api/admin/config',
      'GET /api/admin/config/defaults',
      'PUT /api/admin/config {"trash":{"enabled":true,"days":30}}',
      'POST /api/people/merge {"ids":["$_p1","$_p2","$_p3"]}',
    ]);
  });

  test('v3.1 server: falls back after 404', () async {
    v33 = false;
    expect(await api.trashDays(), 30);
    expect((await api.systemConfig())['trash'], isNotNull);
    await api.mergePeople(_p1, [_p2, _p3]);
    expect(calls, [
      'GET /api/config',
      'GET /api/server/config',
      'GET /api/admin/config',
      'GET /api/system-config',
      'POST /api/people/merge {"ids":["$_p1","$_p2","$_p3"]}',
      'POST /api/people/$_p1/merge {"ids":["$_p2","$_p3"]}',
    ]);
  });

  test('other errors are not retried on the old endpoint', () async {
    broken = true;
    await expectLater(api.trashDays(), throwsA(isA<ApiException>().having((e) => e.status, 'status', 500)));
    expect(calls, ['GET /api/config']);
  });
}
