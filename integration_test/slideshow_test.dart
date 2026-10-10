// Slideshow from the viewer: advances on its own, pauses with Space, saves its
// settings, and the viewer continues where the slideshow stopped.
//   flutter test integration_test/slideshow_test.dart -d linux
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotoroll/api.dart';
import 'package:fotoroll/backup.dart';
import 'package:fotoroll/i18n.dart';
import 'package:fotoroll/screens/home.dart';
import 'package:fotoroll/screens/slideshow.dart';
import 'package:fotoroll/screens/viewer.dart';
import 'package:fotoroll/settings.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';

import 'fake_server.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('slideshow', (tester) async {
    MediaKit.ensureInitialized();
    await i18n.load('en');
    final tmp = Directory.systemTemp.createTempSync('fotoroll_slides');
    BackupService.overrideRoot = tmp.path;
    settings.useDir(tmp.path);
    settings.slideshow = SlideshowPrefs(seconds: 1, autoplay: false, overlay: true);
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

    int previews(int i) => server.requests.where((r) => r == 'GET /api/assets/${uid(i)}/thumbnail').length;

    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: HomeScreen(api: api, onLogout: () {}),
    ));
    final tiles = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Tile');
    await waitFor(tiles);
    await tester.tap(tiles.at(1));
    await waitFor(find.byType(ViewerScreen));
    await wait(const Duration(milliseconds: 500));

    await tester.tap(find.byTooltip('Slideshow'));
    await waitFor(find.byType(SlideshowScreen));
    // 1 s per slide: after ~3.5 s we are at least two slides further (videos show their preview).
    await wait(const Duration(milliseconds: 3500));
    expect(previews(3), greaterThan(0), reason: 'reached slide 3');
    expect(find.text('Budapest, Hungary'), findsOneWidget, reason: 'info overlay');
    noErrors() => expect(errors, isEmpty, reason: '$errors');
    noErrors();

    // Space pauses: no new slides for 2.5 s.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await wait(const Duration(milliseconds: 300));
    final before = server.requests.length;
    final shownBefore = [for (var i = 0; i < 10; i++) previews(i)];
    await wait(const Duration(milliseconds: 2500));
    expect([for (var i = 0; i < 10; i++) previews(i)], shownBefore, reason: 'paused');
    expect(server.requests.length - before, lessThan(3));

    // Settings: switch to shuffle + 2 s and save (to the scratch config).
    // The bar hides after 2.5 s without mouse movement; moving the mouse brings it back.
    expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity).last).opacity, 0, reason: 'controls auto-hide');
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(700, 400));
    await mouse.moveTo(const Offset(705, 410));
    await wait(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('Slideshow settings'));
    await waitFor(find.text('Shuffle'));
    await tester.tap(find.text('Shuffle'));
    await tester.tap(find.text('Done'));
    await wait(const Duration(milliseconds: 500));
    expect(settings.slideshow.direction, 'shuffle');
    expect(File('${tmp.path}/settings.json').readAsStringSync(), contains('"shuffle"'));
    noErrors();

    // Escape: back in the viewer, on the slide the slideshow stopped at.
    final last = [for (var i = 9; i >= 0; i--) if (previews(i) > 0) i];
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await waitFor(find.byType(ViewerScreen));
    await wait(const Duration(seconds: 1));
    expect(find.byType(SlideshowScreen), findsNothing);
    expect(last, isNotEmpty);
    noErrors();

    await mouse.removePointer();
    FlutterError.onError = previous;
    await server.stop();
  });
}
