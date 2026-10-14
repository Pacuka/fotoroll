// Account Settings → Sharing → People cluster group (Immich v3.2+): accept an
// invitation, invite and un-invite a user, reset facial recognition, leave.
//   flutter test integration_test/sharing_test.dart -d linux   (SHOTDIR=... saves screenshots)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotoroll/api.dart';
import 'package:fotoroll/i18n.dart';
import 'package:fotoroll/screens/account_settings.dart';
import 'package:integration_test/integration_test.dart';

import 'fake_server.dart';
import 'focus.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('people cluster group', (tester) async {
    await i18n.load('en');
    final server = FakeImmich();
    final me = server.me['id'] as String;
    final annaGroup = server.clusterGroupOf[uid(901)]!;
    server.clusterRequests.add(
        {'id': uid(500), 'clusterGroupId': annaGroup, 'userId': me, 'createdAt': '2026-10-14T00:00:00.000Z'});
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
      await tester.ensureVisible(f.first);
      await wait(const Duration(milliseconds: 200));
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

    ignoreOsFocusLoss(tester);
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(RepaintBoundary(
      key: root,
      child: MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(body: AccountSettingsScreen(api: api)),
      ),
    ));

    await tap(find.text('Sharing'));
    await tap(find.text('People cluster group'));
    await waitFor(find.text('Tester (You)'));
    expect(find.text('Leave'), findsNothing, reason: 'alone in the group: nothing to leave');

    // 1. A received invitation: view the group, accept.
    await waitFor(find.text('You have been invited to another group'));
    await shot('sharing_invited');
    await tap(find.text('View group'));
    await waitFor(find.text('anna@example.com'));
    await shot('sharing_view_group');
    await tap(find.text('Accept'));
    await until(() => server.clusterGroupOf[me] == annaGroup, 'joined Anna\'s group');
    await waitFor(find.text('Anna'));
    await waitFor(find.text('Leave'));
    await gone(find.text('You have been invited to another group'));

    // 2. Invite Bence, then cancel the invitation.
    await tap(find.text('Add user'));
    await waitFor(find.text('Csilla'));
    expect(find.text('anna@example.com'), findsOneWidget, reason: 'members are not offered again');
    await tap(find.text('Bence'));
    await tap(find.widgetWithText(FilledButton, 'Add'));
    await until(() => server.clusterRequests.any((r) => r['userId'] == uid(902) && r['clusterGroupId'] == annaGroup),
        'invitation sent');
    await waitFor(find.text('Pending'));
    await waitFor(find.text('bence@example.com'));
    await tester.ensureVisible(find.text('Add user'));
    await shot('sharing_pending');
    await tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await until(() => server.clusterRequests.isEmpty, 'invitation cancelled');
    await gone(find.text('Pending'));

    // 3. Reset facial recognition (confirmed).
    await tap(find.text('Reset facial recognition'));
    await waitFor(find.textContaining('delete all people for all users in this group'));
    await tap(find.text('Confirm'));
    await until(() => server.regeneratedGroups.contains(annaGroup), 'facial recognition reset');

    // 4. Leave the group.
    await tap(find.text('Leave'));
    await waitFor(find.text('Leave group'));
    await tap(find.text('Confirm'));
    await until(() => server.clusterGroupOf[me] != annaGroup, 'left the group');
    await gone(find.text('Anna'));
    await gone(find.text('Leave'));
    await shot('sharing_left');

    expect(errors, isEmpty);
    FlutterError.onError = previous;
    await server.stop();
  });
}
