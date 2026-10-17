// Comments and likes in a shared album (web: ActivityStatus / ActivityViewer): on the
// album and on a photo in the viewer; delete; and comments switched off.
//   flutter test integration_test/activity_test.dart -d linux   (SHOTDIR=... saves screenshots)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotoroll/api.dart';
import 'package:fotoroll/i18n.dart';
import 'package:fotoroll/screens/albums.dart';
import 'package:fotoroll/widgets/activity.dart';
import 'package:fotoroll/screens/viewer.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';

import 'fake_server.dart';
import 'focus.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('comments and likes in a shared album', (tester) async {
    MediaKit.ensureInitialized();
    await i18n.load('en');
    final server = FakeImmich();
    final me = server.me;
    final anna = server.otherUsers[0];
    Map<String, dynamic> member(Map<String, dynamic> u, String role) => {'user': u, 'role': role};
    // My album, shared with Anna, comments on; Anna already commented and liked photo 1.
    server.albums.add({'id': uid(700), 'albumName': 'Trip', 'description': '', 'ownerId': me['id'], 'order': 'desc',
       'assetIds': [server.assets[1]['id'], server.assets[3]['id']], 'isActivityEnabled': true,
       'albumUsers': [member(anna, 'editor')]});
    server.activities.addAll([
      {'id': uid(1290), 'albumId': uid(700), 'assetId': null, 'type': 'comment', 'comment': 'Great trip!',
       'createdAt': '2026-10-10T10:00:00.000Z', 'user': anna},
      {'id': uid(1291), 'albumId': uid(700), 'assetId': uid(1), 'type': 'like', 'comment': null,
       'createdAt': '2026-10-10T10:05:00.000Z', 'user': anna},
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

    Map<String, dynamic> mine(String type) =>
        server.activities.lastWhere((a) => a['type'] == type && a['user']['id'] == me['id'], orElse: () => {});
    final pill = find.byType(ActivityStatusPill);

    ignoreOsFocusLoss(tester);
    tester.view.physicalSize = const Size(1300, 850);
    tester.view.devicePixelRatio = 1;

    // 1. The album's pill: 1 comment; the panel shows Anna's comment and takes a new one.
    await open(uid(700));
    await waitFor(pill);
    expect(find.descendant(of: pill, matching: find.text('1')), findsOneWidget, reason: 'one comment');
    await tap(find.byTooltip('Comments & likes'));
    await waitFor(find.text('Great trip!'));
    await tester.enterText(find.widgetWithText(TextField, 'Say something'), 'Thanks, Anna');
    await tap(find.byTooltip('Send message'));
    await until(() => mine('comment')['comment'] == 'Thanks, Anna', 'comment sent');
    expect(mine('comment')['albumId'], uid(700));
    expect(mine('comment')['assetId'], isNull, reason: "the album's own comment");
    await waitFor(find.text('Thanks, Anna'));
    await shot('activity_album_panel');

    // 2. Delete it (the author / album owner may).
    final myComment = mine('comment')['id'];
    await tap(find.descendant(of: find.byKey(ValueKey('activity-$myComment')), matching: find.byTooltip('Comment options')));
    await tap(find.text('Delete'));
    await until(() => server.activities.every((a) => a['id'] != myComment), 'comment deleted');
    await waitFor(find.text('Comment deleted'));
    await gone(find.text('Thanks, Anna'));
    await tap(find.byTooltip('Close'));

    // 3. Like the album from the pill.
    await waitFor(pill);
    await tap(find.descendant(of: pill, matching: find.byIcon(Icons.thumb_up_outlined)));
    await until(() => mine('like').isNotEmpty, 'album liked');
    expect(mine('like')['assetId'], isNull);
    await waitFor(find.descendant(of: pill, matching: find.byIcon(Icons.thumb_up)));

    // 4. A photo in the viewer: Anna's like counts; my comment goes to that photo.
    final tiles = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Tile');
    await waitFor(tiles);
    final first = (tester.widget(tiles.first) as dynamic).asset.id as String;
    await tester.tap(tiles.first);
    await waitFor(find.byType(ViewerScreen));
    final viewerPill = find.descendant(of: find.byType(ViewerScreen), matching: find.byType(ActivityStatusPill));
    await waitFor(viewerPill);
    if (first == uid(1)) expect(find.descendant(of: viewerPill, matching: find.text('1')), findsOneWidget);
    await tap(find.descendant(of: viewerPill, matching: find.byTooltip('Comments & likes')));
    final field = find.widgetWithText(TextField, 'Say something');
    await waitFor(field);
    // Keys typed into the comment field must not reach the viewer's shortcuts (F = favorite, I = info).
    await tester.tap(field);
    await wait(const Duration(milliseconds: 300));
    for (final k in [LogicalKeyboardKey.keyF, LogicalKeyboardKey.keyI, LogicalKeyboardKey.keyA]) {
      await tester.sendKeyEvent(k);
    }
    await wait(const Duration(milliseconds: 500));
    expect(server.asset(first)['isFavorite'], isFalse, reason: 'F typed in the field');
    expect(server.asset(first)['visibility'], 'timeline', reason: 'A typed in the field');
    expect(field, findsOneWidget, reason: 'I typed in the field keeps the panel');
    await tester.enterText(field, 'Lovely light');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await until(() => mine('comment')['comment'] == 'Lovely light', 'photo comment sent');
    expect(mine('comment')['assetId'], first);
    await waitFor(find.text('Lovely light'));
    await shot('activity_viewer_panel');

    // 5. Comments off: the album panel says so, the like button is disabled.
    await tap(find.byTooltip('Back (Esc)'));
    await tap(find.byTooltip('Album options'));
    await tap(find.text('Comments & likes'));
    await until(() => server.albums.first['isActivityEnabled'] == false, 'comments off');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await wait(const Duration(milliseconds: 500));
    await waitFor(pill);
    await tap(find.descendant(of: pill, matching: find.byTooltip('Comments & likes')));
    await waitFor(find.text('Comments are disabled'));
    await waitFor(find.text('Lovely light')); // the photo's comment shows in the album's list too
    expect(find.widgetWithText(TextField, 'Say something'), findsNothing);
    await shot('activity_disabled');

    expect(errors, isEmpty);
    FlutterError.onError = previous;
    await server.stop();
  });
}
