// The memories page (Immich v3.2+): every memory newest first, filters
// (upcoming, only favorites), birthday memories (v3.3) with the age in the viewer.
//   flutter test integration_test/memories_test.dart -d linux   (SHOTDIR=... saves screenshots)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotoroll/api.dart';
import 'package:fotoroll/i18n.dart';
import 'package:fotoroll/settings.dart';
import 'package:fotoroll/widgets/memories.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/intl.dart';
import 'package:media_kit/media_kit.dart';

import 'fake_server.dart';
import 'focus.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('memories page', (tester) async {
    MediaKit.ensureInitialized();
    await i18n.load('en');
    settings.useDir(Directory.systemTemp.createTempSync('fotoroll_memories').path);
    final server = FakeImmich();
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day).toIso8601String();
    server.memories.first['memoryAt'] = today;
    server.memories.addAll([
      {'id': uid(801), 'type': 'birthday', 'data': {'year': 2020, 'personName': 'Dani', 'personId': uid(600)},
       'isSaved': false, 'seenAt': null, 'memoryAt': today, 'assets': [server.assets[5]]},
      {'id': uid(802), 'type': 'on_this_day', 'data': {'year': 2024}, 'isSaved': true, 'seenAt': '2026-03-05',
       'memoryAt': '2026-03-05T00:00:00.000Z', 'lane': false, 'assets': [server.assets[7]]},
      {'id': uid(803), 'type': 'on_this_day', 'data': {'year': 2023}, 'isSaved': false, 'seenAt': null,
       'memoryAt': now.add(const Duration(days: 3)).toIso8601String(),
       'showAt': now.add(const Duration(days: 3)).toIso8601String(), 'lane': false, 'assets': [server.assets[9]]},
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
      await wait(const Duration(milliseconds: 800));
      final b = root.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await tester.runAsync(() => b.toImage());
      final png = await tester.runAsync(() => img!.toByteData(format: ui.ImageByteFormat.png));
      File('$dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    }

    ignoreOsFocusLoss(tester);
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(RepaintBoundary(
      key: root,
      child: MaterialApp(theme: ThemeData(brightness: Brightness.dark), home: MemoriesScreen(api: api)),
    ));

    // 1. Default: upcoming hidden; birthday, today's and the saved older memory.
    await waitFor(find.text('Memories (3)'));
    await waitFor(find.text("Dani's birthday"));
    expect(find.text('1 year ago'), findsOneWidget);
    expect(find.text('Mar 5, 2026'), findsOneWidget);
    expect(find.byIcon(Icons.cake), findsOneWidget);
    expect(find.byTooltip('Favorite'), findsOneWidget);
    expect(find.text('Upcoming'), findsNothing);
    await shot('memories_page');

    // 2. Show upcoming: an "Upcoming" and a "Current" section.
    await tap(find.byTooltip('Filters'));
    await tap(find.text('Show upcoming memories'));
    await tap(find.text('Save'));
    await waitFor(find.text('Memories (4)'));
    await waitFor(find.text('Upcoming'));
    expect(find.text('Current'), findsOneWidget);
    // The future memory is the one under "Upcoming", above "Current".
    final upcomingDate = DateFormat.yMMMd('en').format(now.add(const Duration(days: 3)));
    expect(tester.getTopLeft(find.text(upcomingDate)).dy, lessThan(tester.getTopLeft(find.text('Current')).dy));
    expect(tester.getTopLeft(find.text('1 year ago')).dy, greaterThan(tester.getTopLeft(find.text('Current')).dy));
    expect(settings.memoriesShowUpcoming, isTrue);
    await shot('memories_upcoming');

    // 3. Only favorites.
    await tap(find.byTooltip('Filters'));
    await tap(find.text('Show upcoming memories'));
    await tap(find.text('Only favorites'));
    await tap(find.text('Save'));
    await waitFor(find.text('Memories (1)'));
    await gone(find.text("Dani's birthday"));
    expect(find.text('Mar 5, 2026'), findsOneWidget);
    await tap(find.byTooltip('Filters'));
    await tap(find.text('Only favorites'));
    await tap(find.text('Save'));
    await waitFor(find.text('Memories (3)'));

    // 4. The birthday memory in the viewer shows the age on that photo.
    await tap(find.text("Dani's birthday"));
    await waitFor(find.text('6th birthday'));
    await shot('memories_birthday_viewer');
    await tap(find.byTooltip('Close'));
    await waitFor(find.text('Memories (3)'));

    expect(errors, isEmpty);
    FlutterError.onError = previous;
    await server.stop();
  });
}
