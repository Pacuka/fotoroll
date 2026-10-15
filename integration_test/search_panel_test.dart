// The search panel (web v3.3 SearchFilters): recent searches, "Filter by"
// buttons that show the active value, date presets and "Advanced filters".
//   flutter test integration_test/search_panel_test.dart -d linux   (SHOTDIR=... saves screenshots)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotoroll/api.dart';
import 'package:fotoroll/i18n.dart';
import 'package:fotoroll/settings.dart';
import 'package:fotoroll/widgets/search_filter_dialog.dart';
import 'package:integration_test/integration_test.dart';

import 'fake_server.dart';
import 'focus.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('search panel', (tester) async {
    await i18n.load('en');
    final dir = Directory.systemTemp.createTempSync('fotoroll_search');
    settings.useDir(dir.path);
    await settings.update(searchHistory: ['beach', 'sunset', 'Budapest']);
    final server = FakeImmich();
    server.people.first['name'] = 'Anna';
    server.people.add({'id': uid(601), 'name': 'Bence', 'birthDate': null, 'isHidden': false, 'isFavorite': false,
      'thumbnailPath': '/x', 'updatedAt': '2026-01-01T00:00:00.000Z'});
    server.tags.addAll([
      {'id': uid(500), 'name': 'Travel', 'value': 'Travel'},
      {'id': uid(501), 'name': 'Greece', 'value': 'Travel/Greece'},
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

    String what(Finder f) => f.toString(describeSelf: true);
    Future<void> waitFor(Finder f) => until(() => f.evaluate().isNotEmpty, 'waiting for ${what(f)}');
    Future<void> gone(Finder f) => until(() => f.evaluate().isEmpty, 'waiting for ${what(f)} to go');
    Future<void> tap(Finder f) async {
      await waitFor(f);
      await tester.ensureVisible(f.first);
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

    SearchFilter? result;
    var closed = 0;
    ignoreOsFocusLoss(tester);
    tester.view.physicalSize = const Size(1300, 850);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(RepaintBoundary(
      key: root,
      child: MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  result = await showSearchFilterDialog(context, api, result ?? SearchFilter());
                  closed++;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));

    final panel = find.byType(Dialog);
    Finder inPanel(Finder f) => find.descendant(of: panel, matching: f);
    Finder recent(String term) => inPanel(find.widgetWithText(ListTile, term));
    Finder chip(String label) => inPanel(find.widgetWithText(FilterChip, label));
    Future<void> open() async {
      await tap(find.text('open'));
      await waitFor(find.text('Filter by'));
    }

    // 1. Recent searches: filtered by the typed text, removable, a click searches.
    await open();
    for (final t in ['beach', 'sunset', 'Budapest']) {
      expect(recent(t), findsOneWidget);
    }
    expect(find.text('Clear all recent searches'), findsOneWidget);
    await shot('search_panel');
    await tester.enterText(inPanel(find.byType(TextField)).first, 'b');
    await wait(const Duration(milliseconds: 200));
    expect(recent('beach'), findsOneWidget);
    expect(recent('Budapest'), findsOneWidget);
    expect(recent('sunset'), findsNothing);
    expect(find.text('Clear all recent searches'), findsNothing, reason: 'only with an empty query');
    await tester.enterText(inPanel(find.byType(TextField)).first, '');
    await tap(find.descendant(of: recent('sunset'), matching: find.byTooltip('Remove')));
    expect(recent('sunset'), findsNothing);
    expect(settings.searchHistory, ['beach', 'Budapest']);
    await tap(recent('Budapest'));
    await until(() => closed == 1, 'a recent search closes the panel');
    expect(result!.query, 'Budapest');
    await settings.addSearch('Budapest');
    expect(settings.searchHistory, ['Budapest', 'beach'], reason: 'used term moves to the top');

    // 2. "Filter by": each button shows its value.
    await open();
    await tester.enterText(inPanel(find.byType(TextField)).first, '');
    await tap(chip('People'));
    await waitFor(inPanel(find.text('Anna')));
    await tap(inPanel(find.text('Anna')));
    await tap(inPanel(find.text('Bence')));
    await waitFor(chip('Anna + 1 person'));
    await tap(chip('Date'));
    await tap(inPanel(find.widgetWithText(ChoiceChip, 'This year')));
    await waitFor(chip('This year'));
    await tap(inPanel(find.widgetWithText(ChoiceChip, 'Custom')));
    await waitFor(inPanel(find.text('Start date')));
    await tap(chip('Tags'));
    await tap(inPanel(find.byType(DropdownMenu<String>)));
    await tap(find.text('Travel/Greece').last);
    await waitFor(chip('Greece'));
    await tap(chip('Media'));
    await tap(inPanel(find.widgetWithText(ChoiceChip, 'Video')));
    await waitFor(chip('Video'));
    await tap(chip('Search type'));
    await tap(inPanel(find.widgetWithText(ChoiceChip, 'OCR')));
    await waitFor(chip('OCR'));

    // 3. Advanced filters: camera, rating, display options.
    expect(inPanel(find.text('Camera')), findsNothing);
    await tap(inPanel(find.text('Advanced filters')));
    await waitFor(inPanel(find.text('Camera')));
    await tap(inPanel(find.widgetWithText(FilterChip, 'Only favorites')));
    await shot('search_panel_filters');
    await tap(inPanel(find.widgetWithText(FilledButton, 'Search')));
    await until(() => closed == 2, 'search');
    final f = result!;
    final now = DateTime.now();
    expect(f.personIds, {uid(600), uid(601)});
    expect(f.takenAfter, DateTime(now.year));
    expect(f.takenBefore, DateTime(now.year, 12, 31));
    expect(f.tagIds, {uid(501)});
    expect(f.type, 'VIDEO');
    expect(f.mode, SearchMode.ocr);
    expect(f.isFavorite, isTrue);

    // 4. Reopened with advanced filters set: they start expanded. Clear all recent searches.
    await open();
    await waitFor(inPanel(find.text('Camera')));
    await tap(find.text('Clear all recent searches'));
    expect(settings.searchHistory, isEmpty);
    await gone(find.text('Recent searches'));
    await tap(inPanel(find.text('Clear all')));
    await waitFor(chip('People'));
    expect(chip('This year'), findsNothing);

    expect(errors, isEmpty);
    FlutterError.onError = previous;
    await server.stop();
    dir.deleteSync(recursive: true);
  });
}
