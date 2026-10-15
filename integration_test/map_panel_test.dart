// Map (web v3.3 "Show photos in this area"): the panel with the photos in the
// visible area can be closed and opened, and whether it opens by default is a
// setting. A closed panel loads nothing while the map moves.
//   flutter test integration_test/map_panel_test.dart -d linux   (SHOTDIR=... saves screenshots)
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotoroll/api.dart';
import 'package:fotoroll/i18n.dart';
import 'package:fotoroll/screens/map_screen.dart';
import 'package:fotoroll/settings.dart';
import 'package:fotoroll/widgets/timeline_view.dart';
import 'package:integration_test/integration_test.dart';

import 'fake_server.dart';
import 'focus.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('map photo panel', (tester) async {
    await i18n.load('en');
    final dir = Directory.systemTemp.createTempSync('fotoroll_map');
    settings.useDir(dir.path);
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

    // describeSelf: printing the matches of a finder whose widgets are gone throws.
    String what(Finder f) => f.toString(describeSelf: true);
    Future<void> waitFor(Finder f) => until(() => f.evaluate().isNotEmpty, 'waiting for ${what(f)}');
    Future<void> gone(Finder f) => until(() => f.evaluate().isEmpty, 'waiting for ${what(f)} to go');
    Future<void> tap(Finder f) async {
      await waitFor(f);
      await tester.tap(f.first);
      await wait(const Duration(milliseconds: 400));
    }

    final root = GlobalKey();
    Future<void> shot(String name) async {
      final d = Platform.environment['SHOTDIR'];
      if (d == null) return;
      await wait(const Duration(milliseconds: 500));
      final b = root.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await tester.runAsync(() => b.toImage());
      final png = await tester.runAsync(() => img!.toByteData(format: ui.ImageByteFormat.png));
      File('$d/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    }

    int panelLoads() => server.requests.where((r) => r == 'GET /api/timeline/buckets').length;
    Future<void> open(Key key) async {
      await tester.pumpWidget(RepaintBoundary(
        key: root,
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Scaffold(body: MapScreen(key: key, api: api)),
        ),
      ));
      await until(() => server.requests.contains('GET /api/map/markers'), 'markers loaded');
    }

    final panelButton = find.byTooltip('Show photos in this area');
    Finder panel() => find.byType(TimelineView);
    Future<void> pan() async {
      await tester.dragFrom(const Offset(500, 250), const Offset(-150, 60));
      await wait(const Duration(milliseconds: 900)); // past the 500 ms debounce
    }

    ignoreOsFocusLoss(tester);
    tester.view.physicalSize = const Size(1300, 850);
    tester.view.devicePixelRatio = 1;

    // 1. Open by default: the panel lists the photos in the area and follows the map.
    await open(const ValueKey(1));
    await waitFor(panel());
    await until(() => panelLoads() > 0, 'panel loaded');
    await waitFor(find.textContaining('assets'));
    await shot('map_panel_open');
    var n = panelLoads();
    await pan();
    await until(() => panelLoads() > n, 'panel follows the map');

    // 2. Close it: no panel, no loads while the map moves; open it again.
    await tap(panelButton);
    await gone(panel());
    await shot('map_panel_closed');
    n = panelLoads();
    await pan();
    expect(panelLoads(), n, reason: 'closed panel loads nothing');
    await tap(panelButton);
    await waitFor(panel());
    await until(() => panelLoads() > n, 'reopened panel loads the area');

    // 3. "Show asset panel by default" off: saved, and a new map starts without the panel.
    await tap(find.byTooltip('Settings'));
    await tap(find.text('Show asset panel by default'));
    expect(settings.mapShowPanel, isFalse);
    final saved = jsonDecode(File('${dir.path}/settings.json').readAsStringSync());
    expect(saved['mapShowPanel'], isFalse);
    await tap(find.byTooltip('Settings'));
    await wait(const Duration(milliseconds: 300));
    n = panelLoads();
    await open(const ValueKey(2));
    await wait(const Duration(seconds: 1));
    expect(panel(), findsNothing);
    expect(panelLoads(), n);
    await tap(panelButton);
    await waitFor(panel());

    expect(errors, isEmpty);
    FlutterError.onError = previous;
    await server.stop();
    dir.deleteSync(recursive: true);
  });
}
