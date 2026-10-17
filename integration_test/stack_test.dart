// Stacks (web): stack / unstack from the selection menu, one tile per stack with a
// count, and in the viewer the stack strip plus primary / remove / keep / unstack.
//   flutter test integration_test/stack_test.dart -d linux   (SHOTDIR=... saves screenshots)
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

  testWidgets('stacks', (tester) async {
    MediaKit.ensureInitialized();
    await i18n.load('en');
    BackupService.overrideRoot = Directory.systemTemp.createTempSync('fotoroll_stack').path;
    settings.useDir(Directory.systemTemp.createTempSync('fotoroll_stack_settings').path);
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

    String fileName(String id) => server.asset(id)['originalFileName'] as String;
    Finder strip(String id) => find.byKey(ValueKey('stack-$id'));
    final p1 = uid(1), p3 = uid(3), p5 = uid(5), p7 = uid(7);

    // 1. Stack two photos: the timeline then shows one tile with "2".
    await select([p1, p3]);
    await menu('Stack');
    await until(() => server.stacks.length == 1, 'stack created');
    final st = server.stacks.values.single;
    expect((st['assetIds'] as List).toSet(), {p1, p3});
    final primary = st['primaryAssetId'] as String, other = primary == p1 ? p3 : p1;
    await waitFor(find.text('Stacked 2 assets'));
    await until(() => tiles.evaluate().length == 9, 'one tile for the stack');
    final i = [for (var k = 0; k < 9; k++) tileId(k)].indexOf(primary);
    expect(i, isNonNegative, reason: 'the primary photo stands for the stack');
    expect(find.descendant(of: tiles.at(i), matching: find.text('2')), findsOneWidget);
    expect(find.descendant(of: tiles.at(i), matching: find.byIcon(Icons.burst_mode_outlined)), findsOneWidget);
    await shot('stack_tile');

    // 2. Viewer: the strip shows both; clicking the other one shows it.
    await tester.tap(tiles.at(i));
    await waitFor(find.byType(ViewerScreen));
    await waitFor(strip(other));
    expect(strip(primary), findsOneWidget);
    await waitFor(find.text(fileName(primary)));
    await shot('stack_viewer');
    await tap(strip(other));
    await waitFor(find.text(fileName(other)));

    // 3. Make it the primary photo.
    await tap(find.byTooltip('View Stack'));
    await waitFor(find.text('Set as primary asset'));
    expect(find.text('Remove from Stack'), findsNothing, reason: 'a stack of two only unstacks');
    await shot('stack_menu');
    await tap(find.text('Set as primary asset'));
    await until(() => st['primaryAssetId'] == other, 'primary changed');
    await tap(find.byTooltip('View Stack'));
    await waitFor(find.text('Un-stack'));
    expect(find.text('Set as primary asset'), findsNothing, reason: 'already the primary');

    // 4. Unstack from the viewer: the strip goes; the timeline has every photo again after closing.
    await tap(find.text('Un-stack'));
    await until(() => server.stacks.isEmpty, 'unstacked');
    await waitFor(find.text('Un-stacked 2 assets'));
    expect(strip(primary), findsNothing);
    await tap(find.byTooltip('Back (Esc)'));
    await until(() => tiles.evaluate().length == 10, 'all photos back');

    // 5. Three photos, then "Keep this, delete others" in the viewer.
    await select([p5, p7, p3]);
    await menu('Stack');
    await until(() => server.stacks.length == 1, 'second stack');
    final st2 = server.stacks.values.single;
    final head = st2['primaryAssetId'] as String;
    await until(() => tiles.evaluate().length == 8, 'one tile for three');
    await tester.tap(tiles.at([for (var k = 0; k < 8; k++) tileId(k)].indexOf(head)));
    await waitFor(find.byType(ViewerScreen));
    final keep = (st2['assetIds'] as List).firstWhere((x) => x != head) as String;
    await waitFor(strip(keep));
    await tap(strip(keep));
    await waitFor(find.text(fileName(keep)));
    await tap(find.byTooltip('View Stack'));
    await waitFor(find.text('Remove from Stack'));
    await tap(find.text('Keep this, delete others'));
    await waitFor(find.text('Delete others'));
    await tap(find.text('Delete others'));
    await until(() => server.stacks.isEmpty, 'stack gone');
    for (final x in st2['assetIds'] as List) {
      expect(server.asset(x as String)['isTrashed'], x != keep, reason: 'only $keep kept');
    }
    await waitFor(find.textContaining('deleted 2 assets'));
    await tap(find.byTooltip('Back (Esc)'));
    await until(() => tiles.evaluate().length == 8, 'two photos in the trash');

    // 6. Unstack from the selection menu.
    await select([p1, keep]);
    await menu('Stack');
    await until(() => server.stacks.length == 1, 'third stack');
    await until(() => tiles.evaluate().length == 7, 'stacked');
    final h3 = server.stacks.values.single['primaryAssetId'] as String;
    await select([h3]);
    await tap(find.byTooltip('Menu'));
    expect(find.text('Stack'), findsNothing, reason: 'one photo');
    await tap(find.text('Un-stack'));
    await until(() => server.stacks.isEmpty, 'unstacked from the menu');
    await until(() => tiles.evaluate().length == 8, 'both back');

    expect(errors, isEmpty);
    FlutterError.onError = previous;
    await server.stop();
  });
}
