// Passkeys in Account Settings (Immich v3.4, feature level 2): list, rename,
// delete. Hidden when the server is older or the admin turned passkeys off.
//   flutter test integration_test/passkeys_test.dart -d linux   (SHOTDIR=... saves screenshots)
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

  testWidgets('passkeys', (tester) async {
    await i18n.load('en');
    final server = FakeImmich();
    server.passkeys.addAll([
      {'id': uid(960), 'name': 'YubiKey', 'createdAt': '2026-11-01T10:00:00.000Z',
       'updatedAt': '2026-11-01T10:00:00.000Z', 'usedAt': '2026-11-20T08:30:00.000Z'},
      {'id': uid(961), 'name': null, 'createdAt': '2026-11-02T10:00:00.000Z',
       'updatedAt': '2026-11-02T10:00:00.000Z', 'usedAt': null},
    ]);
    await server.start();
    final api = ImmichApi(Credentials(serverUrl: server.url, apiKey: 'k'));
    await api.loadServerVersion();

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

    Finder inRow(String name, Finder f) =>
        find.descendant(of: find.ancestor(of: find.text(name), matching: find.byType(ListTile)), matching: f);

    ignoreOsFocusLoss(tester);
    tester.view.physicalSize = const Size(1300, 1000);
    tester.view.devicePixelRatio = 1;
    Future<void> open() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(RepaintBoundary(
        key: root,
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Scaffold(body: AccountSettingsScreen(api: api)),
        ),
      ));
      await waitFor(find.text('API Keys'));
      await wait(const Duration(milliseconds: 500));
    }

    // 1. The list: names (no name → "Passkey"), created, last used / never.
    await open();
    await tap(find.text('Passkeys'));
    await waitFor(find.text('YubiKey'));
    expect(find.text('Passkey'), findsOneWidget);
    expect(find.textContaining('Last used: Never'), findsOneWidget);
    expect(find.textContaining("this app can't create them"), findsOneWidget);
    await shot('passkeys_list');

    // 2. Rename.
    await tap(inRow('YubiKey', find.byTooltip('Edit passkey')));
    await waitFor(find.widgetWithText(TextField, 'Name'));
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Work key');
    await tap(find.widgetWithText(FilledButton, 'Save'));
    await until(() => server.passkeys.first['name'] == 'Work key', 'renamed');
    await waitFor(find.text('Work key'));

    // 3. Delete, after the confirmation.
    await tap(inRow('Passkey', find.byTooltip('Delete passkey')));
    await waitFor(find.text('Are you sure you want to delete this passkey?'));
    await shot('passkeys_delete');
    await tap(find.widgetWithText(FilledButton, 'Delete'));
    await until(() => server.passkeys.length == 1, 'deleted');
    await waitFor(find.text('Removed passkey: Passkey'));
    await shot('passkeys_after');

    // 4. Passkey login off on the server, or a server without feature level 2: no section.
    final listed = server.requests.where((r) => r.contains('/passkeys')).length;
    server.passkeyLogin = false;
    await open();
    expect(find.text('Passkeys'), findsNothing);
    server.passkeyLogin = true;
    server.featureLevel = null;
    await api.loadServerVersion();
    await open();
    expect(find.text('Passkeys'), findsNothing);
    expect(server.requests.where((r) => r.contains('/passkeys')).length, listed, reason: 'not even asked');

    expect(errors, isEmpty);
    FlutterError.onError = previous;
    await server.stop();
  });
}
