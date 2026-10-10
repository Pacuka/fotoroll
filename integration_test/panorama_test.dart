// 360° and 180° photo spheres open in the panorama viewer, load the original,
// read its GPano crop, and respond to drag / scroll without errors.
//   flutter test integration_test/panorama_test.dart -d linux   (SHOTDIR=... saves screenshots)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotoroll/api.dart';
import 'package:fotoroll/backup.dart';
import 'package:fotoroll/i18n.dart';
import 'package:fotoroll/screens/home.dart';
import 'package:fotoroll/widgets/panorama_viewer.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';

import 'fake_server.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('panorama viewer', (tester) async {
    MediaKit.ensureInitialized();
    await i18n.load('en');
    BackupService.overrideRoot = Directory.systemTemp.createTempSync('fotoroll_pano').path;
    final server = FakeImmich()
      ..makePanorama(uid(1), 'pano360.jpg')
      ..makePanorama(uid(3), 'pano180.jpg');
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

    final root = GlobalKey();
    Future<Uint8List> shot(String name) async {
      final b = root.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await tester.runAsync(() => b.toImage());
      final png = (await tester.runAsync(() => img!.toByteData(format: ui.ImageByteFormat.png)))!;
      final raw = (await tester.runAsync(() => img!.toByteData()))!;
      final dir = Platform.environment['SHOTDIR'];
      if (dir != null) File('$dir/$name.png').writeAsBytesSync(png.buffer.asUint8List());
      return raw.buffer.asUint8List();
    }

    int diff(Uint8List a, Uint8List b) {
      var n = 0;
      for (var i = 0; i < a.length; i += 4 * 97) {
        if ((a[i] - b[i]).abs() > 24) n++;
      }
      return n;
    }

    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(RepaintBoundary(
      key: root,
      child: MaterialApp(theme: ThemeData(brightness: Brightness.dark), home: HomeScreen(api: api, onLogout: () {})),
    ));

    final tiles = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Tile');
    await waitFor(tiles);
    await wait(const Duration(seconds: 1));
    expect(find.byIcon(Icons.threesixty), findsNWidgets(2), reason: '360 badge on both panorama tiles');

    // Full sphere: guessed from the 2:1 preview, then the original replaces it.
    await tester.tap(tiles.at(1));
    await waitFor(find.byType(PanoramaViewer));
    await waitFor(find.text('360°'));
    await wait(const Duration(seconds: 2));
    expect(server.requests, contains('GET /api/assets/${uid(1)}/original'));
    expect(find.byType(CircularProgressIndicator), findsNothing, reason: 'original loaded');
    final start = await shot('pano360_start');

    final center = tester.getCenter(find.byType(PanoramaViewer));
    await tester.dragFrom(center, const Offset(-300, 120));
    await wait(const Duration(milliseconds: 300));
    final dragged = await shot('pano360_dragged');
    expect(diff(start, dragged), greaterThan(50), reason: 'dragging rotates the view');

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: center);
    await tester.sendEventToBinding(PointerScrollEvent(position: center, scrollDelta: const Offset(0, -400)));
    await wait(const Duration(milliseconds: 300));
    final zoomed = await shot('pano360_zoomed');
    expect(diff(dragged, zoomed), greaterThan(50), reason: 'scrolling zooms');
    await mouse.removePointer();

    // 180° × 90° slice: the crop comes from the original's GPano XMP.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight); // video
    await wait(const Duration(seconds: 1));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight); // pano180
    await waitFor(find.byType(PanoramaViewer));
    await waitFor(find.text('180° × 90°'));
    await wait(const Duration(seconds: 1));
    await shot('pano180_start');
    // Dragging far must stop at the image edge (no black past a partial panorama).
    for (var i = 0; i < 4; i++) {
      await tester.dragFrom(center, const Offset(600, 300));
      await wait(const Duration(milliseconds: 100));
    }
    final edge = await shot('pano180_edge');
    final corner = (20 * 1400 + 20) * 4; // a pixel near the top-left corner
    expect(edge[corner] + edge[corner + 1] + edge[corner + 2], greaterThan(30), reason: 'no black outside the slice');

    expect(find.byType(ErrorWidget), findsNothing);
    expect(errors, isEmpty, reason: '$errors');
    FlutterError.onError = previous;
    await server.stop();
  });
}
