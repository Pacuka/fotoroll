// API key rotation (Immich v3.2+): a new secret for a key; rotating the key the
// app signs in with switches the app to the new secret. On v3.1 servers the
// endpoint is missing and the app says so.
//   flutter test integration_test/api_key_rotate_test.dart -d linux   (SHOTDIR=... saves screenshots)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotoroll/api.dart';
import 'package:fotoroll/i18n.dart';
import 'package:fotoroll/screens/account_settings.dart';
import 'package:integration_test/integration_test.dart';

import 'fake_server.dart';
import 'focus.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('rotate API keys', (tester) async {
    await i18n.load('en');
    final server = FakeImmich()
      ..enforceApiKeys = true
      ..apiKeys.addAll([
        {'id': uid(950), 'name': 'Fotoroll', 'secret': 'own-secret', 'permissions': ['all'],
         'createdAt': '2026-01-01T00:00:00.000Z', 'updatedAt': '2026-01-01T00:00:00.000Z'},
        {'id': uid(951), 'name': 'cli', 'secret': 'cli-secret', 'permissions': ['all'],
         'createdAt': '2026-02-01T00:00:00.000Z', 'updatedAt': '2026-02-01T00:00:00.000Z'},
      ]);
    await server.start();
    final saved = <Credentials>[];
    final api = ImmichApi(Credentials(serverUrl: server.url, apiKey: 'own-secret'))
      ..onCredentialsChanged = saved.add;

    final errors = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (d) {
      errors.add(d.exceptionAsString());
      previous?.call(d);
    };

    Future<void> wait(Duration d) async {
      final end = DateTime.now().add(d);
      while (DateTime.now().isBefore(end)) {
        keepViewFocused(tester);
        await tester.pump(const Duration(milliseconds: 16));
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
    }

    Future<void> until(bool Function() ok, String what) async {
      final end = DateTime.now().add(const Duration(seconds: 10));
      while (!ok() && DateTime.now().isBefore(end)) {
        await wait(const Duration(milliseconds: 100));
      }
      expect(ok(), isTrue, reason: what);
    }

    Future<void> waitFor(Finder f) => until(() => f.evaluate().isNotEmpty, 'waiting for $f');
    Future<void> tap(Finder f) async {
      await waitFor(f);
      await tester.tap(f.first);
      await wait(const Duration(milliseconds: 400));
    }

    final root = GlobalKey();
    Future<void> shot(String name) async {
      final dir = Platform.environment['SHOTDIR'];
      if (dir == null) return;
      await wait(const Duration(milliseconds: 500));
      final b = root.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await tester.runAsync(() => b.toImage());
      final png = await tester.runAsync(() => img!.toByteData(format: ui.ImageByteFormat.png));
      File('$dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    }

    Map<String, dynamic> key(String name) => server.apiKeys.firstWhere((k) => k['name'] == name);
    Finder rotateButton(String name) => find.descendant(
        of: find.ancestor(of: find.text(name), matching: find.byType(ListTile)), matching: find.byTooltip('Rotate key'));
    Future<void> rotate(String name) async {
      await tap(rotateButton(name));
      await waitFor(find.textContaining('The current key will stop working immediately'));
      await tap(find.widgetWithText(FilledButton, 'Rotate key'));
    }

    ignoreOsFocusLoss(tester);
    tester.view.physicalSize = const Size(1300, 850);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(RepaintBoundary(
      key: root,
      child: MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(body: AccountSettingsScreen(api: api)),
      ),
    ));

    await tap(find.text('API Keys'));
    await waitFor(find.text('cli'));
    await waitFor(find.text('Fotoroll'));
    await shot('api_keys');

    // 1. Another key: the new secret is shown once; the app keeps its own key.
    await rotate('cli');
    await until(() => key('cli')['secret'] != 'cli-secret', 'cli rotated');
    await waitFor(find.text(key('cli')['secret']));
    await shot('api_key_rotated_secret');
    await tap(find.text('Close'));
    expect(api.creds.apiKey, 'own-secret');
    expect(saved, isEmpty);

    // 2. The app's own key: the app switches to the new secret and saves it, and keeps working.
    await rotate('Fotoroll');
    await until(() => key('Fotoroll')['secret'] != 'own-secret', 'own key rotated');
    await waitFor(find.text('Fotoroll signs in with this key, it now uses the new one'));
    expect(api.creds.apiKey, key('Fotoroll')['secret']);
    expect(saved.single.apiKey, key('Fotoroll')['secret']);
    expect(saved.single.serverUrl, server.url);
    await waitFor(find.text(key('Fotoroll')['secret']));
    await shot('api_key_rotated_own');
    await tap(find.text('Close'));
    // The list reloads with the new key (the old one would get 401).
    final n = server.requests.where((r) => r == 'GET /api/api-keys').length;
    await rotate('cli');
    await until(() => server.requests.where((r) => r == 'GET /api/api-keys').length > n, 'list reloaded');
    await tap(find.text('Close'));
    expect(find.textContaining('Error'), findsNothing);

    // 3. Immich v3.1: no rotate endpoint → a clear message, nothing changes.
    server.v31 = true;
    final before = key('cli')['secret'];
    await rotate('cli');
    await waitFor(find.text('Rotating API keys needs Immich v3.2 or newer'));
    await shot('api_key_rotate_unsupported');
    expect(key('cli')['secret'], before);
    expect(find.text('Close'), findsNothing);

    expect(errors, isEmpty);
    FlutterError.onError = previous;
    await server.stop();
  });
}
