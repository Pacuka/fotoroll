// Desktop integration: drag & drop upload (as the GTK runner reports it), the
// "drop to upload" hint, the tray icon and its "Back up now" action.
//   flutter test integration_test/desktop_test.dart -d linux
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotoroll/api.dart';
import 'package:fotoroll/backup.dart';
import 'package:fotoroll/i18n.dart';
import 'package:fotoroll/screens/home.dart';
import 'package:fotoroll/window.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';

import 'fake_server.dart';
import 'focus.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desktop: drop to upload, tray', (tester) async {
    MediaKit.ensureInitialized();
    await i18n.load('en');
    final tmp = Directory.systemTemp.createTempSync('fotoroll_desktop');
    BackupService.overrideRoot = tmp.path;
    final server = FakeImmich();
    await server.start();
    final api = ImmichApi(Credentials(serverUrl: server.url, apiKey: 'k'));

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

    /// What the GTK runner sends on the "fotoroll/window" channel.
    Future<void> fromRunner(String method, [Object? args]) =>
        tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            'fotoroll/window', const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)), (_) {});

    ignoreOsFocusLoss(tester);
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: HomeScreen(api: api, onLogout: () {}),
    ));
    final tiles = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Tile');
    await until(() => tiles.evaluate().isNotEmpty, 'timeline');

    // Tray: an AppIndicator library is installed on this machine.
    final hasIndicator = File('/usr/lib/libappindicator3.so.1').existsSync() ||
        File('/usr/lib/libayatana-appindicator3.so.1').existsSync();
    await until(() => trayAvailable.value == hasIndicator, 'tray availability matches the system');

    // Drag over: hint appears; leave: it goes.
    await fromRunner('onDragOver');
    await wait(const Duration(milliseconds: 300));
    expect(find.text('Drop photos and videos to upload'), findsOneWidget);
    expect(dragHovering.value, isTrue);
    await fromRunner('onDragLeave');
    await wait(const Duration(milliseconds: 300));
    expect(dragHovering.value, isFalse);

    // Drop a folder: its photos / videos are uploaded, other files ignored.
    final drop = Directory('${tmp.path}/drop/trip')..createSync(recursive: true);
    File('${drop.path}/a.jpg').writeAsBytesSync(File('integration_test/fixtures/thumb.jpg').readAsBytesSync());
    File('${drop.path}/b.mp4').writeAsBytesSync(File('integration_test/fixtures/clip.mp4').readAsBytesSync());
    File('${drop.path}/readme.txt').writeAsStringSync('not media');
    await fromRunner('onDrop', [drop.path]);
    await until(() => server.uploads.length == 2, 'both media files uploaded');
    expect(server.uploads.toSet(), {'a.jpg', 'b.mp4'});
    await until(() => find.widgetWithText(FilledButton, 'OK').evaluate().isNotEmpty, 'upload summary');
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await wait(const Duration(milliseconds: 500));

    // Tray "Back up now" reaches the backup service without errors.
    await fromRunner('onTray', 'backup');
    await wait(const Duration(seconds: 1));

    expect(find.byType(ErrorWidget), findsNothing);
    expect(errors, isEmpty, reason: '$errors');
    FlutterError.onError = previous;
    await server.stop();
  });
}
