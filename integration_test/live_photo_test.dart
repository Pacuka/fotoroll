// Live / motion photos: badge and hover playback on the tile, "Play Motion Photo"
// in the viewer, which returns to the still when the clip ends.
//   flutter test integration_test/live_photo_test.dart -d linux
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotoroll/api.dart';
import 'package:fotoroll/backup.dart';
import 'package:fotoroll/i18n.dart';
import 'package:fotoroll/screens/home.dart';
import 'package:fotoroll/screens/viewer.dart';
import 'package:fotoroll/widgets/hover_preview.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'fake_server.dart';
import 'focus.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('live photo', (tester) async {
    MediaKit.ensureInitialized();
    await i18n.load('en');
    BackupService.overrideRoot = Directory.systemTemp.createTempSync('fotoroll_live').path;
    final server = FakeImmich()..makeLivePhoto(uid(1), uid(101));
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

    Future<void> until(bool Function() ok, String what, {int seconds = 10}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!ok() && DateTime.now().isBefore(end)) {
        await wait(const Duration(milliseconds: 100));
      }
      expect(ok(), isTrue, reason: what);
    }

    ignoreOsFocusLoss(tester);
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: HomeScreen(api: api, onLogout: () {}),
    ));
    final tiles = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Tile');
    await until(() => tiles.evaluate().isNotEmpty, 'timeline');
    await wait(const Duration(seconds: 1));
    expect(find.byIcon(Icons.motion_photos_on_outlined), findsOneWidget, reason: 'motion badge on the live photo');

    // Hover: the tile plays the motion clip (not the photo itself).
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(tiles.at(1)));
    await until(() => HoverPreview.showing.value == uid(1), 'hover preview playing');
    await until(() => server.requests.contains('GET /api/assets/${uid(101)}/video/playback'),
        'the motion clip (not the photo) was requested');
    await mouse.moveTo(const Offset(5, 400));
    await wait(const Duration(milliseconds: 300));
    await mouse.removePointer();

    // Viewer: Play Motion Photo shows the clip; at its end the still comes back.
    await tester.tap(tiles.at(1));
    await until(() => find.byType(ViewerScreen).evaluate().isNotEmpty, 'viewer');
    await until(() => find.byTooltip('Play Motion Photo').evaluate().isNotEmpty, 'motion button');
    await tester.tap(find.byTooltip('Play Motion Photo'));
    await wait(const Duration(milliseconds: 300));
    expect(find.byTooltip('Stop Motion Photo'), findsOneWidget);
    expect(find.byType(Video), findsOneWidget);
    await until(() => find.byTooltip('Play Motion Photo').evaluate().isNotEmpty, 'back to the still after the clip',
        seconds: 8);
    expect(find.byType(Video), findsNothing);

    // A photo without motion has no button.
    await tester.tap(find.byIcon(Icons.chevron_right));
    await wait(const Duration(seconds: 1));
    await tester.tap(find.byIcon(Icons.chevron_right));
    await wait(const Duration(seconds: 1));
    expect(find.byTooltip('Play Motion Photo'), findsNothing);

    expect(errors, isEmpty, reason: '$errors');
    FlutterError.onError = previous;
    await server.stop();
  });
}
