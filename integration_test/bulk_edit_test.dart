// Editing several photos at once from the selection bar's "⋮" menu (web: change
// date / description / location, tag), and no menu when a partner's photo is picked.
//   flutter test integration_test/bulk_edit_test.dart -d linux   (SHOTDIR=... saves screenshots)
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
import 'package:fotoroll/settings.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';

import 'fake_server.dart';
import 'focus.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('bulk edit selected photos', (tester) async {
    MediaKit.ensureInitialized();
    await i18n.load('en');
    BackupService.overrideRoot = Directory.systemTemp.createTempSync('fotoroll_bulk').path;
    settings.useDir(Directory.systemTemp.createTempSync('fotoroll_bulk_settings').path);
    final server = FakeImmich();
    // A partner's photo in the timeline: it can't be edited.
    final anna = server.otherUsers[0]['id'];
    server.assets[5]['ownerId'] = anna;
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
    // Tall enough for every photo: after the date change two of them sit at the bottom.
    tester.view.physicalSize = const Size(1300, 1400);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(RepaintBoundary(
      key: root,
      child: MaterialApp(theme: ThemeData(brightness: Brightness.dark), home: HomeScreen(api: api, onLogout: () {})),
    ));
    final tiles = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Tile');
    await waitFor(tiles);
    String tileId(int i) => (tester.widget(tiles.at(i)) as dynamic).asset.id as String;

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    Future<void> select(List<String> ids) async {
      for (final id in ids) {
        final i = [for (var k = 0; k < tiles.evaluate().length; k++) tileId(k)].indexOf(id);
        await mouse.addPointer(location: tester.getCenter(tiles.at(i)));
        await wait(const Duration(milliseconds: 600));
        await tap(find.descendant(of: tiles.at(i), matching: find.byTooltip('Select')));
        await mouse.removePointer();
      }
      await waitFor(find.text('${ids.length} selected'));
    }

    Future<void> menu(String item) async {
      await tap(find.byTooltip('Menu'));
      await tap(find.text(item));
    }

    final a = uid(1), b = uid(3);
    Map<String, dynamic> exif(String id) => server.asset(id)['exifInfo'] as Map<String, dynamic>;

    // 1. Shift the date by -1 day: both photos move from Oct 9 to Oct 8 (the timeline reloads).
    expect(find.text('Thu, Oct 8'), findsNothing);
    await select([a, b]);
    await menu('Change date');
    await waitFor(find.text('Change date by offset'));
    await tap(find.text('Change date by offset'));
    await tester.enterText(find.widgetWithText(TextField, 'Days'), '-1');
    // Confirm stays disabled while the offset is 0.
    await until(() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirm')).onPressed != null,
        'confirm enabled');
    await shot('bulk_date_offset');
    await tap(find.text('Confirm'));
    await until(() => server.bulkUpdates.isNotEmpty, 'date sent');
    expect(server.bulkUpdates.last['ids'], unorderedEquals([a, b]));
    expect(server.bulkUpdates.last['dateTimeRelative'], -24 * 60);
    expect(server.bulkUpdates.last.containsKey('dateTimeOriginal'), isFalse);
    await waitFor(find.text('Updated 2 items'));
    await waitFor(find.text('Thu, Oct 8'));
    await shot('bulk_date_moved');
    expect(find.text('2 selected'), findsNothing);

    // 2. A fixed date: the dialog starts at the first photo's date; Confirm sends it with an offset.
    await select([a]);
    await menu('Change date');
    await waitFor(find.text('Date and Time'));
    await tap(find.text('Confirm'));
    await until(() => server.bulkUpdates.length == 2, 'fixed date sent');
    expect(server.bulkUpdates.last['dateTimeOriginal'], matches(RegExp(r'^2026-10-08T\d\d:00:00\.000[+-]\d\d:\d\d$')));

    // 3. One description for both.
    await select([a, b]);
    await menu('Change description');
    await tester.enterText(find.widgetWithText(TextField, 'Description'), 'Lake Balaton');
    await tap(find.text('Confirm'));
    await until(() => exif(a)['description'] == 'Lake Balaton' && exif(b)['description'] == 'Lake Balaton',
        'description saved');

    // 4. One location for both.
    await select([a, b]);
    await menu('Change location');
    await tester.enterText(find.widgetWithText(TextField, 'Latitude'), '46.9');
    await tester.enterText(find.widgetWithText(TextField, 'Longitude'), '17.9');
    await wait(const Duration(milliseconds: 300));
    await shot('bulk_location');
    await tap(find.text('Save'));
    await until(() => exif(a)['latitude'] == 46.9 && exif(b)['longitude'] == 17.9, 'location saved');

    // 5. A new tag on both.
    await select([a, b]);
    await menu('Tag');
    await tester.enterText(find.byType(TextField).last, 'Summer');
    await wait(const Duration(milliseconds: 300));
    await tap(find.textContaining('Create tag'));
    await until(
        () => [a, b].every((id) => (server.asset(id)['tags'] as List).any((t) => t['value'] == 'Summer')), 'tagged');
    await waitFor(find.text('Tagged 2 assets'));

    // 6. With a partner's photo in the selection there is no edit menu.
    await select([a, uid(5)]);
    await shot('bulk_partner_no_menu');
    expect(find.byTooltip('Menu'), findsNothing);
    // Like the web: only share, add to album and download.
    for (final hidden in ['Favorite', 'Archive', 'Delete', 'Move to locked folder']) {
      expect(find.byTooltip(hidden), findsNothing, reason: hidden);
    }
    for (final shown in ['Share', 'Add to album', 'Download']) {
      expect(find.byTooltip(shown), findsOneWidget, reason: shown);
    }
    await tap(find.byTooltip('Clear selection (Esc)'));
    await select([a]);
    expect(find.byTooltip('Menu'), findsOneWidget);

    expect(errors, isEmpty);
    FlutterError.onError = previous;
    await server.stop();
  });
}
