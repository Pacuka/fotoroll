import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotoroll/api.dart';
import 'package:fotoroll/screens/system_settings.dart';

void main() {
  testWidgets('system settings render and expand without errors', (tester) async {
    final cfg = File('test/fixtures/system_config.json').readAsStringSync();
    HttpOverrides.global = null; // testWidgets fakes all HTTP with 400s; use the local server
    late HttpServer server;
    await tester.runAsync(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response.headers.contentType = ContentType.json;
        req.response.write(cfg);
        await req.response.close();
      });
    });
    final api = ImmichApi(Credentials(serverUrl: 'http://127.0.0.1:${server.port}', apiKey: 'k'));
    tester.view.physicalSize = const Size(1600, 4000);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SystemSettingsScreen(api: api))));
    for (var i = 0; i < 40 && find.byType(ExpansionTile).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    for (final w in find.byType(Text).evaluate().take(5)) {
      // ignore: avoid_print
      print('TEXT: ${(w.widget as Text).data}');
    }
    expect(find.byType(ExpansionTile), findsWidgets);
    // Expand every section and make sure each field kind builds.
    final tiles = find.byType(ExpansionTile);
    final n = tiles.evaluate().length;
    for (var i = 0; i < n; i++) {
      await tester.tap(find.byType(ExpansionTile).at(i));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
    expect(find.byType(SwitchListTile), findsWidgets);
    expect(find.byType(DropdownButton<Object>), findsWidgets);
    // Let the HTTP client's idle-connection timer expire before the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
    await tester.runAsync(() => server.close(force: true));
  });
}
