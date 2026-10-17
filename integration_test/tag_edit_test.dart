// Tag editing (web TagEditModal): colour and name. Renaming (Immich v3.3+)
// changes the last part of the path, children follow; v3.1 servers ignore the
// name and the app says so.
//   flutter test integration_test/tag_edit_test.dart -d linux   (SHOTDIR=... saves screenshots)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotoroll/api.dart';
import 'package:fotoroll/i18n.dart';
import 'package:fotoroll/screens/library_extra.dart';
import 'package:integration_test/integration_test.dart';

import 'fake_server.dart';
import 'focus.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('edit tags', (tester) async {
    await i18n.load('en');
    final server = FakeImmich();
    server.tags.addAll([
      {'id': uid(500), 'name': 'Travel', 'value': 'Travel'},
      {'id': uid(501), 'name': 'Greece', 'value': 'Travel/Greece'},
      {'id': uid(502), 'name': 'Athens', 'value': 'Travel/Greece/Athens'},
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

    Map<String, dynamic> tag(int n) => server.tags.firstWhere((t) => t['id'] == uid(n));
    Finder tree(String name) =>
        find.descendant(of: find.byType(ListTile), matching: find.text(name, findRichText: true));
    Color? iconColor(String name) => tester
        .widget<Icon>(find.descendant(
            of: find.ancestor(of: tree(name), matching: find.byType(ListTile)), matching: find.byIcon(Icons.sell_outlined)))
        .color;
    final nameField = find.widgetWithText(TextField, 'Name');
    bool saveEnabled() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed != null;

    ignoreOsFocusLoss(tester);
    tester.view.physicalSize = const Size(1300, 850);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(RepaintBoundary(
      key: root,
      child: MaterialApp(theme: ThemeData(brightness: Brightness.dark), home: Scaffold(body: TagsScreen(api: api))),
    ));

    // 1. Rename a child tag and give it a colour.
    await tap(tree('Travel'));
    await tap(tree('Greece'));
    await tap(find.byTooltip('Edit tag'));
    await waitFor(nameField);
    expect(find.text('Full path: Travel/Greece'), findsOneWidget);
    await tester.enterText(nameField, 'Hellas');
    await wait(const Duration(milliseconds: 200));
    expect(find.text('Full path: Travel/Hellas'), findsOneWidget);
    // A slash isn't allowed in a name.
    await tester.enterText(nameField, 'Hel/las');
    await waitFor(find.textContaining('cannot contain'));
    expect(saveEnabled(), isFalse);
    await tester.enterText(nameField, 'Hellas');
    await tap(find.byTooltip('#1e88e5'));
    await shot('tag_edit_dialog');
    await tap(find.text('Save'));
    await until(() => tag(501)['value'] == 'Travel/Hellas', 'renamed');
    expect(tag(501)['color'], '#1e88e5');
    expect(tag(502)['value'], 'Travel/Hellas/Athens', reason: 'children follow');
    await waitFor(find.text('Updated tag: Travel/Hellas'));
    await waitFor(tree('Hellas'));
    expect(tree('Greece'), findsNothing);
    expect(iconColor('Hellas'), const Color(0xFF1E88E5));
    expect(iconColor('Travel'), isNull);
    await shot('tag_edited');

    // 2. Rename the parent: the renamed tag stays selected and open, its children move along.
    await tap(tree('Travel'));
    await tap(find.byTooltip('Edit tag'));
    await waitFor(nameField);
    expect(find.textContaining('Full path'), findsNothing, reason: 'top-level tag');
    await tester.enterText(nameField, 'Trips');
    await tap(find.text('Save'));
    await until(() => tag(500)['value'] == 'Trips', 'parent renamed');
    expect(tag(501)['value'], 'Trips/Hellas');
    expect(tag(502)['value'], 'Trips/Hellas/Athens');
    await waitFor(tree('Trips'));
    await waitFor(tree('Hellas'));
    expect(tree('Travel'), findsNothing);
    // Removing the colour.
    await tap(tree('Hellas'));
    await tap(find.byTooltip('Edit tag'));
    await waitFor(nameField);
    await tap(find.byTooltip('No color'));
    await tap(find.text('Save'));
    await until(() => tag(501)['color'] == null, 'colour removed');
    await until(() => iconColor('Hellas') == null, 'icon uncoloured');

    // 3. Immich v3.1 ignores the name: the app says renaming needs v3.3; the colour still works.
    server.v31 = true;
    await tap(find.byTooltip('Edit tag'));
    await waitFor(nameField);
    await tester.enterText(nameField, 'Greece');
    await tap(find.byTooltip('#43a047'));
    await tap(find.text('Save'));
    await waitFor(find.text('Renaming tags needs Immich v3.3 or newer'));
    expect(tag(501)['value'], 'Trips/Hellas');
    expect(tag(501)['color'], '#43a047');
    await shot('tag_rename_unsupported');
    await gone(nameField);

    // 4. Once the app knows the server is v3.1, the name can't be edited and the dialog says why.
    await api.loadServerVersion();
    await tap(find.byTooltip('Edit tag'));
    await waitFor(find.text('Needs Immich v3.3 or newer'));
    expect(tester.widget<TextField>(nameField).enabled, isFalse);
    await shot('tag_rename_needs_v33');
    await tap(find.byTooltip('#1e88e5'));
    await tap(find.text('Save'));
    await until(() => tag(501)['color'] == '#1e88e5', 'colour still saved');
    expect(tag(501)['value'], 'Trips/Hellas');

    expect(errors, isEmpty);
    FlutterError.onError = previous;
    await server.stop();
  });
}
