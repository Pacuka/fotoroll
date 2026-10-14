// End-to-end run of the real desktop app against FakeImmich:
//   flutter test integration_test/app_flow_test.dart -d linux
// Visits every sidebar page, uses the viewer (keys, video, info edits) and
// selection actions, and checks the server received the changes.

import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotoroll/api.dart';
import 'package:fotoroll/backup.dart';
import 'package:fotoroll/i18n.dart';
import 'package:fotoroll/screens/explore.dart' show PersonAvatar;
import 'package:fotoroll/screens/home.dart';
import 'package:fotoroll/screens/viewer.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';

import 'fake_server.dart';
import 'focus.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('full app flow', (tester) async {
    MediaKit.ensureInitialized();
    await i18n.load('en');
    BackupService.overrideRoot = Directory.systemTemp.createTempSync('immich_it').path;
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

    Future<void> waitFor(Finder f, {Duration timeout = const Duration(seconds: 8)}) async {
      final end = DateTime.now().add(timeout);
      while (f.evaluate().isEmpty && DateTime.now().isBefore(end)) {
        await wait(const Duration(milliseconds: 100));
      }
      expect(f, findsWidgets, reason: 'waiting for $f');
    }

    Future<void> until(bool Function() ok, String what) async {
      final end = DateTime.now().add(const Duration(seconds: 8));
      while (!ok() && DateTime.now().isBefore(end)) {
        await wait(const Duration(milliseconds: 100));
      }
      expect(ok(), isTrue, reason: what);
    }

    void noErrors(String where) {
      expect(find.byType(ErrorWidget), findsNothing, reason: 'error widget on $where');
      expect(errors, isEmpty, reason: 'errors on $where: $errors');
    }

    ignoreOsFocusLoss(tester);
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: HomeScreen(api: api, onLogout: () {}),
    ));

    final tiles = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Tile');
    await waitFor(tiles);
    await wait(const Duration(seconds: 1));
    expect(tiles, findsNWidgets(10));
    noErrors('photos');

    // 0. Memory lane: open the memory, let it advance, check it was marked seen.
    await waitFor(find.text('1 year ago'));
    await tester.tap(find.text('1 year ago'));
    await until(() => server.memories.first['seenAt'] != null, 'memory marked seen');
    await wait(const Duration(seconds: 6)); // first photo advances after 5 s
    noErrors('memory viewer');
    focusView(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await waitFor(tiles);
    await wait(const Duration(milliseconds: 500));

    // 1. Every sidebar page builds.
    for (final page in [
      'Explore', 'Map', 'People', 'Shared links', 'Sharing', 'Favorites', 'Albums', 'Tags',
      'Recently added', 'Folders', 'Utilities', 'Archive', 'Locked Folder', 'Trash', 'Backup', 'Photos',
    ]) {
      final item = find.text(page, skipOffstage: false).first;
      await tester.ensureVisible(item);
      await wait(const Duration(milliseconds: 200));
      await tester.tap(item);
      await wait(const Duration(milliseconds: 1500));
      noErrors(page);
    }
    await waitFor(tiles);
    // The trash page reads the retention from v3.3's /config, not the deprecated /server/config.
    expect(server.requests.where((r) => r.endsWith('/api/config')), isNotEmpty);
    expect(server.requests.where((r) => r.endsWith('/server/config')), isEmpty);

    // 1b. Folders: open a folder from the tree.
    await tester.tap(find.text('Folders').first);
    await waitFor(find.text('photos'));
    await tester.tap(find.text('photos').first);
    await wait(const Duration(seconds: 1));
    await waitFor(find.text('2025'));
    await tester.tap(find.text('2025').first);
    await waitFor(find.text('/photos/2025'));
    noErrors('folders');

    // 1c. People: rename a person from their page.
    await tester.tap(find.text('People').first);
    await wait(const Duration(seconds: 1));
    await waitFor(find.byType(PersonAvatar));
    await tester.tap(find.byType(PersonAvatar).first);
    await waitFor(find.byTooltip('Edit person'));
    await tester.tap(find.byTooltip('Edit person'));
    await wait(const Duration(milliseconds: 500));
    expect(find.text('Only change for me'), findsNothing, reason: 'not a shared person');
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Anna');
    await tester.tap(find.text('Save'));
    await until(() => server.people.first['name'] == 'Anna', 'person renamed');
    noErrors('person rename');
    await tester.pageBack();
    await wait(const Duration(milliseconds: 500));
    await tester.tap(find.text('Photos').first);
    await waitFor(tiles);

    // 2. Viewer: open a photo, edit description / rating / tags from the info panel.
    await tester.tap(tiles.at(1));
    await waitFor(find.byType(ViewerScreen));
    await wait(const Duration(seconds: 1));
    focusView(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await waitFor(find.text('Info'));
    await waitFor(find.text('photo1.jpg'));

    await tester.enterText(find.widgetWithText(TextField, 'Add a description'), 'Hello from Linux');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await until(() => server.asset(uid(1))['exifInfo']['description'] == 'Hello from Linux', 'description saved');

    await tester.tap(find.byTooltip('4'));
    await until(() => server.asset(uid(1))['exifInfo']['rating'] == 4, 'rating saved');

    await tester.tap(find.text('Add tag'));
    await wait(const Duration(milliseconds: 500));
    await tester.enterText(find.byType(TextField).last, 'Trip');
    await wait(const Duration(milliseconds: 300));
    await tester.tap(find.textContaining('Create tag'));
    await until(() => (server.asset(uid(1))['tags'] as List).any((t) => t['value'] == 'Trip'), 'tag added');
    noErrors('viewer edits');

    // 3. Next item is a video: it must play in the viewer without errors.
    focusView(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await waitFor(find.text('clip2.mp4'));
    await wait(const Duration(seconds: 3));
    noErrors('video playback');
    expect(server.requests.where((r) => r.endsWith('/video/playback')), isNotEmpty);

    focusView(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await waitFor(tiles);
    await wait(const Duration(milliseconds: 500));

    // 4. Selection: select a photo and favorite it from the bar.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(tiles.at(3)));
    await wait(const Duration(milliseconds: 600));
    await tester.tap(find.byTooltip('Select').first);
    await waitFor(find.text('1 selected'));
    await tester.tap(find.byTooltip('Favorite'));
    await until(() => server.asset(uid(3))['isFavorite'] == true, 'favorite saved');
    noErrors('selection');
    await mouse.removePointer();

    // 4b. Search: a typed query is a smart search; "Search options" filters use metadata search.
    await tester.enterText(find.widgetWithText(TextField, 'Search your photos'), 'beach');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await until(() => server.searches.isNotEmpty, 'smart search sent');
    expect(server.searches.last.$1, '/api/search/smart');
    expect(server.searches.last.$2['query'], 'beach');
    await waitFor(tiles);
    noErrors('smart search');

    await tester.tap(find.byTooltip('Search options').first);
    await waitFor(find.text('Search options'));
    await wait(const Duration(milliseconds: 800));
    final dialog = find.byType(AlertDialog);
    await tester.tap(find.descendant(of: dialog, matching: find.byType(PersonAvatar)).first);
    await tester.pump();
    await tester.tap(find.descendant(of: dialog, matching: find.text('Context')));
    await tester.pump();
    await tester.enterText(find.descendant(of: dialog, matching: find.byType(TextField)).at(1), '');
    await tester.tap(find.descendant(of: dialog, matching: find.widgetWithText(DropdownMenu<String?>, 'Country')));
    await wait(const Duration(milliseconds: 500));
    await tester.tap(find.text('Hungary').last);
    await wait(const Duration(milliseconds: 500));
    await tester.ensureVisible(find.descendant(of: dialog, matching: find.text('Video')));
    await tester.tap(find.descendant(of: dialog, matching: find.text('Video')));
    await tester.pump();
    final before = server.searches.length;
    await tester.tap(find.descendant(of: dialog, matching: find.widgetWithText(FilledButton, 'Search')));
    await until(() => server.searches.length > before, 'filtered search sent');
    final (endpoint, body) = server.searches.last;
    expect(endpoint, '/api/search/metadata');
    expect(body['personIds'], [server.people.first['id']]);
    expect(body['country'], 'Hungary');
    expect(body['type'], 'VIDEO');
    expect(body.containsKey('query'), isFalse);
    await waitFor(tiles);
    expect(find.text('3'), findsWidgets, reason: 'badge counts person, place, type');
    noErrors('filtered search');
    await tester.tap(find.text('Photos').first);
    await waitFor(tiles);

    // 5. A narrow window (< 1100 px) collapses the sidebar to an icon rail; nothing may overflow.
    tester.view.physicalSize = const Size(1000, 800);
    await waitFor(find.byTooltip('Albums'));
    await tester.tap(find.byTooltip('Albums').first);
    await wait(const Duration(seconds: 1));
    await tester.tap(find.byTooltip('Photos').first);
    await waitFor(tiles);
    noErrors('narrow window');

    FlutterError.onError = previous;
    await server.stop();
  });
}
