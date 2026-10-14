// Shared people (Immich v3.3): shared indicator, filter by "shared by",
// share people in bulk, and a person's access dialog (share back, stop
// sharing, add a user) plus the "aka" name from another user's library.
//   flutter test integration_test/people_sharing_test.dart -d linux   (SHOTDIR=... saves screenshots)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotoroll/api.dart';
import 'package:fotoroll/i18n.dart';
import 'package:fotoroll/screens/explore.dart';
import 'package:integration_test/integration_test.dart';

import 'fake_server.dart';
import 'focus.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shared people', (tester) async {
    await i18n.load('en');
    final server = FakeImmich();
    final me = server.me['id'] as String;
    final anna = uid(901), bence = uid(902);
    // Anna and Bence are in my cluster group.
    server.clusterGroupOf[anna] = server.clusterGroupOf[me]!;
    server.clusterGroupOf[bence] = server.clusterGroupOf[me]!;
    server.people.first['name'] = 'Dani';
    final dani = server.people.first['id'] as String;
    final emma = uid(601);
    server.people.add({'id': emma, 'name': 'Emma', 'birthDate': null, 'isHidden': false, 'isFavorite': false,
      'thumbnailPath': '/x', 'updatedAt': '2026-01-01T00:00:00.000Z'});
    // Anna shares Emma with me; in Anna's library she is "Emmi".
    server.personAccess.add({'personId': emma, 'sharedById': anna, 'sharedWithId': me, 'role': 'admin'});
    server.otherPeopleOf[emma] = [{'name': 'Emmi', 'birthDate': null, 'role': 'admin', 'sharedById': anna}];
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

    bool access(String personId, String by, String withId) => server.personAccess
        .any((a) => a['personId'] == personId && a['sharedById'] == by && a['sharedWithId'] == withId);

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
      child: MaterialApp(theme: ThemeData(brightness: Brightness.dark), home: PeopleScreen(api: api)),
    ));

    // 1. Emma carries the "shared with me" indicator, Dani doesn't.
    await waitFor(find.text('Emma'));
    await waitFor(find.text('Dani'));
    expect(find.byTooltip('Shared with me'), findsOneWidget);
    await shot('people_shared_indicator');

    // 2. Filter: shared by Anna → only Emma.
    await tap(find.byTooltip('Filters'));
    await tap(find.text('No filter').first);
    await tap(find.text('Anna').last);
    await tap(find.text('Save'));
    await gone(find.text('Dani'));
    expect(find.text('Emma'), findsOneWidget);
    expect(server.requests.where((r) => r.startsWith('GET /api/people')), isNotEmpty);
    await tap(find.byTooltip('Filters'));
    await tap(find.text('Reset'));
    await tap(find.text('Save'));
    await waitFor(find.text('Dani'));

    // 3. Bulk: share Dani with Anna.
    await tap(find.text('Manage access'));
    await waitFor(find.text('Share everyone'));
    await shot('people_bulk_share');
    await tap(find.text('Edit people'));
    await waitFor(find.text('Select people'));
    await tap(find.descendant(of: find.byType(AlertDialog).last, matching: find.text('Dani')));
    await tap(find.text('Done'));
    await waitFor(find.text('Shared (1)'));
    await tap(find.text('Save'));
    await until(() => access(dani, me, anna), 'Dani shared with Anna');
    expect(access(emma, me, anna), isFalse, reason: 'only the picked person');

    // 4. Emma's page: "aka Emmi", then her access dialog.
    await tap(find.text('Emma'));
    await waitFor(find.textContaining('aka Emmi'));
    await tap(find.byTooltip('Manage access'));
    await waitFor(find.text('Shared with me'));
    await waitFor(find.text('Share back'));
    await shot('person_access');
    await tap(find.text('Share back'));
    await until(() => access(emma, me, anna), 'shared back with Anna');
    await gone(find.text('Share back'));
    await waitFor(find.byTooltip('Stop sharing this person with this user'));
    await tap(find.byTooltip('Stop sharing this person with this user'));
    await until(() => !access(emma, me, anna), 'stopped sharing with Anna');
    await waitFor(find.text('Share back'));
    await tap(find.text('Add user'));
    await waitFor(find.text('bence@example.com'));
    await tap(find.text('Bence'));
    await tap(find.widgetWithText(FilledButton, 'Add'));
    await until(() => access(emma, me, bence), 'shared with Bence');
    await waitFor(find.text('bence@example.com'));
    await shot('person_access_after');
    await tap(find.text('Done'));

    // 5. Edit Emma: "Only change for me" starts checked (Features → Apply changes to: Only me).
    await tap(find.byTooltip('Edit person'));
    await waitFor(find.text('Only change for me'));
    await until(() => tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value == true,
        'only for me from the preference');
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Emma B');
    await shot('person_edit');
    await tap(find.text('Save'));
    await until(() => server.personUpdates.isNotEmpty, 'person updated');
    expect(server.personUpdates.last['name'], 'Emma B');
    expect(server.personUpdates.last['userId'], me);
    await waitFor(find.text('Emma B'));
    // Unchecked: the change goes to everyone with access (no userId).
    await tap(find.byTooltip('Edit person'));
    await waitFor(find.text('Only change for me'));
    await until(() => tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value == true, 'checked');
    await tap(find.text('Only change for me'));
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Emma C');
    await tap(find.text('Save'));
    await until(() => server.personUpdates.length == 2, 'second update');
    expect(server.personUpdates.last.containsKey('userId'), isFalse);

    expect(errors, isEmpty);
    FlutterError.onError = previous;
    await server.stop();
  });
}
