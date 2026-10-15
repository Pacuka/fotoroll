// Album editors (Immich v3.3): a shared user with the editor role can change
// the album title and description; a viewer can't.
//   flutter test integration_test/album_editor_test.dart -d linux   (SHOTDIR=... saves screenshots)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotoroll/api.dart';
import 'package:fotoroll/i18n.dart';
import 'package:fotoroll/screens/albums.dart';
import 'package:integration_test/integration_test.dart';

import 'fake_server.dart';
import 'focus.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('album editor can edit title and description', (tester) async {
    await i18n.load('en');
    final server = FakeImmich();
    final me = server.me;
    final anna = server.otherUsers[0], bence = server.otherUsers[1];
    Map<String, dynamic> member(Map<String, dynamic> u, String role) => {'user': u, 'role': role};
    // Both albums belong to Anna; I'm an editor of the first, a viewer of the second.
    server.albums.addAll([
      {'id': uid(700), 'albumName': 'Trip', 'description': 'Old text', 'ownerId': anna['id'], 'order': 'desc',
       'assetIds': [server.assets[0]['id'], server.assets[1]['id']],
       'albumUsers': [member(me, 'editor'), member(bence, 'viewer')]},
      {'id': uid(701), 'albumName': 'Party', 'description': '', 'ownerId': anna['id'], 'order': 'desc',
       'assetIds': [server.assets[2]['id']], 'albumUsers': [member(me, 'viewer')]},
    ]);
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

    Future<void> waitFor(Finder f) => until(() => f.evaluate().isNotEmpty, 'waiting for $f');
    Future<void> gone(Finder f) => until(() => f.evaluate().isEmpty, 'waiting for $f to go');
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

    Future<void> open(String id) async {
      final album = (await tester.runAsync(() => api.album(id)))!;
      await tester.pumpWidget(RepaintBoundary(
        key: root,
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: AlbumScreen(key: ValueKey(id), api: api, album: album),
        ),
      ));
      // Wait until my user id is known (the menu depends on it).
      await until(() => server.requests.contains('GET /api/users/me'), 'me loaded');
      await wait(const Duration(milliseconds: 300));
    }

    int patches() => server.requests.where((r) => r.startsWith('PATCH /api/albums')).length;

    ignoreOsFocusLoss(tester);
    tester.view.physicalSize = const Size(1300, 850);
    tester.view.devicePixelRatio = 1;

    // 1. Editor: "Edit album" next to "Leave album", but no owner-only items.
    await open(uid(700));
    await waitFor(find.text('Trip'));
    await tap(find.byTooltip('Album options'));
    await waitFor(find.text('Edit album'));
    expect(find.text('Leave album'), findsOneWidget);
    expect(find.text('Delete album'), findsNothing);
    expect(find.byTooltip('Add photos'), findsOneWidget);
    expect(find.text('Display order'), findsNothing);
    await shot('album_editor_menu');
    await tap(find.text('Edit album'));
    await waitFor(find.widgetWithText(TextField, 'Album Name'));
    await tester.enterText(find.widgetWithText(TextField, 'Album Name'), 'Trip to Tokaj');
    await tester.enterText(find.widgetWithText(TextField, 'Description'), 'Wine and hills');
    await shot('album_editor_dialog');
    await tap(find.text('Save'));
    await until(() => server.albums[0]['albumName'] == 'Trip to Tokaj', 'title saved');
    expect(server.albums[0]['description'], 'Wine and hills');
    await waitFor(find.text('Trip to Tokaj'));
    await waitFor(find.text('Wine and hills'));
    await waitFor(find.text('Album info updated'));
    await shot('album_editor_saved');

    // Clicking the title opens the editor too.
    await tap(find.text('Trip to Tokaj'));
    await waitFor(find.widgetWithText(TextField, 'Album Name'));
    await tap(find.text('Cancel'));
    await gone(find.widgetWithText(TextField, 'Album Name'));

    // 2. Viewer: no "Edit album", and the title isn't clickable.
    final before = patches();
    await open(uid(701));
    await waitFor(find.text('Party'));
    await tap(find.byTooltip('Album options'));
    await waitFor(find.text('Leave album'));
    expect(find.text('Edit album'), findsNothing);
    expect(find.byTooltip('Add photos'), findsNothing, reason: "viewers can't add photos");
    await shot('album_viewer_menu');
    await tap(find.byTooltip('Album options'));
    await gone(find.text('Leave album'));
    await tap(find.text('Party'));
    expect(find.widgetWithText(TextField, 'Album Name'), findsNothing);
    expect(patches(), before);

    expect(errors, isEmpty);
    FlutterError.onError = previous;
    await server.stop();
  });
}
