// Shared links for photos (web: "Create link to share"): from the selection bar
// for several photos, and from the viewer for the one shown.
//   flutter test integration_test/share_link_test.dart -d linux   (SHOTDIR=... saves screenshots)
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotoroll/api.dart';
import 'package:fotoroll/backup.dart';
import 'package:fotoroll/i18n.dart';
import 'package:fotoroll/screens/home.dart';
import 'package:fotoroll/screens/viewer.dart';
import 'package:fotoroll/settings.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';

import 'fake_server.dart';
import 'focus.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('share photos with a link', (tester) async {
    MediaKit.ensureInitialized();
    await i18n.load('en');
    BackupService.overrideRoot = Directory.systemTemp.createTempSync('fotoroll_share').path;
    settings.useDir(Directory.systemTemp.createTempSync('fotoroll_share_settings').path);
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

    Future<void> waitFor(Finder f) async {
      final end = DateTime.now().add(const Duration(seconds: 10));
      while (f.evaluate().isEmpty && DateTime.now().isBefore(end)) {
        await wait(const Duration(milliseconds: 100));
      }
      expect(f, findsWidgets, reason: 'waiting for $f');
    }

    Future<void> until(bool Function() ok, String what) async {
      final end = DateTime.now().add(const Duration(seconds: 10));
      while (!ok() && DateTime.now().isBefore(end)) {
        await wait(const Duration(milliseconds: 100));
      }
      expect(ok(), isTrue, reason: what);
    }

    Future<void> tap(Finder f) async {
      await waitFor(f);
      await tester.tap(f.first);
      await wait(const Duration(milliseconds: 300));
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

    ignoreOsFocusLoss(tester);
    tester.view.physicalSize = const Size(1300, 850);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(RepaintBoundary(
      key: root,
      child: MaterialApp(theme: ThemeData(brightness: Brightness.dark), home: HomeScreen(api: api, onLogout: () {})),
    ));
    final tiles = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Tile');
    await waitFor(tiles);

    // 1. Select two photos: "Share" in the bar makes one link for both.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    for (final i in [1, 3]) {
      await mouse.addPointer(location: tester.getCenter(tiles.at(i)));
      await wait(const Duration(milliseconds: 600));
      await tap(find.byTooltip('Select'));
      await mouse.removePointer();
    }
    await waitFor(find.text('2 selected'));
    await tap(find.byTooltip('Share'));
    await waitFor(find.text('Create link to share'));
    await waitFor(find.text('Let anyone with the link see the selected photo(s)'));
    await tester.enterText(find.widgetWithText(TextField, 'Description'), 'Beach day');
    await shot('share_link_dialog');
    await tap(find.text('Create link'));
    await until(() => server.sharedLinks.length == 1, 'link created');
    final link = server.sharedLinks.single;
    expect(link['type'], 'INDIVIDUAL');
    expect((link['assetIds'] as List).toSet(), hasLength(2));
    expect(link['description'], 'Beach day');
    expect(link.containsKey('albumId'), isFalse);
    await waitFor(find.text('${server.url}/share/key0'));
    await shot('share_link_created');
    await tap(find.text('Done'));
    // Like the other actions, the selection ends; the photos stay.
    await until(() => find.text('2 selected').evaluate().isEmpty, 'selection cleared');
    expect(tiles, findsNWidgets(10));

    // 2. Viewer: "Share" makes a link for the photo shown, and the viewer stays on it.
    await tester.tap(tiles.at(1));
    await waitFor(find.byType(ViewerScreen));
    await wait(const Duration(seconds: 1));
    await tap(find.descendant(of: find.byType(ViewerScreen), matching: find.byTooltip('Share')));
    await waitFor(find.text('Create link to share'));
    await tap(find.text('Create link'));
    await until(() => server.sharedLinks.length == 2, 'second link');
    expect(server.sharedLinks.last['assetIds'], [uid(1)]);
    await waitFor(find.text('${server.url}/share/key1'));
    await shot('share_link_viewer');
    await tap(find.text('Done'));
    expect(find.byType(ViewerScreen), findsOneWidget);
    await waitFor(find.text('photo1.jpg'));

    expect(errors, isEmpty);
    FlutterError.onError = previous;
    await server.stop();
  });
}
