// Faces in the viewer: hover highlight, "Edit faces" (assign an unassigned face
// to a new person, delete a face) and tagging a new face by drawing a box.
//   flutter test integration_test/faces_test.dart -d linux   (SHOTDIR=... saves screenshots)
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotoroll/api.dart';
import 'package:fotoroll/backup.dart';
import 'package:fotoroll/i18n.dart';
import 'package:fotoroll/screens/home.dart';
import 'package:fotoroll/screens/viewer.dart';
import 'package:fotoroll/widgets/faces.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';

import 'fake_server.dart';
import 'focus.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('faces', (tester) async {
    MediaKit.ensureInitialized();
    await i18n.load('en');
    BackupService.overrideRoot = Directory.systemTemp.createTempSync('fotoroll_faces').path;
    final server = FakeImmich();
    server.people.first['name'] = 'Anna';
    final anna = server.people.first['id'] as String;
    final annaFace = server.addFace(uid(1), personId: anna);
    final unassigned = server.addFace(uid(1), x: 200, y: 50);
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

    final root = GlobalKey();
    Future<void> shot(String name) async {
      final dir = Platform.environment['SHOTDIR'];
      if (dir == null) return;
      final b = root.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await tester.runAsync(() => b.toImage());
      final png = await tester.runAsync(() => img!.toByteData(format: ui.ImageByteFormat.png));
      File('$dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    }

    ignoreOsFocusLoss(tester);
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(RepaintBoundary(
      key: root,
      child: MaterialApp(theme: ThemeData(brightness: Brightness.dark), home: HomeScreen(api: api, onLogout: () {})),
    ));
    final tiles = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Tile');
    await waitFor(tiles);
    await tester.tap(tiles.at(1));
    await waitFor(find.byType(ViewerScreen));
    focusView(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await waitFor(find.text('Anna'));

    // 1. Hovering Anna outlines her face on the photo.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(5, 5));
    await mouse.moveTo(tester.getCenter(find.text('Anna').last));
    await waitFor(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is FaceBoxesPainter));
    final painter = (tester.widget<CustomPaint>(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is FaceBoxesPainter)).painter as FaceBoxesPainter);
    expect(painter.boxes.single.left, closeTo(100 / 320, 1e-9));
    await shot('faces_highlight');
    await mouse.moveTo(const Offset(5, 5));
    await wait(const Duration(milliseconds: 300));

    // 2. Edit faces: give the unassigned face to a new person "Bob".
    await tester.tap(find.byTooltip('Edit people'));
    await waitFor(find.byType(EditFacesPanel));
    await waitFor(find.text('Unassigned'));
    await shot('faces_edit_panel');
    await tester.tap(find.text('Unassigned'));
    await waitFor(find.text('Select person'));
    await tester.enterText(find.byType(TextField).last, 'Bob');
    await tester.pump();
    await tester.tap(find.text('Create new person: Bob'));
    await waitFor(find.text('Bob'));
    await wait(const Duration(milliseconds: 500)); // picker dialog closing
    await tester.tap(find.text('Done'));
    await until(() => server.people.any((p) => p['name'] == 'Bob'), 'Bob created');
    final bob = server.people.firstWhere((p) => p['name'] == 'Bob')['id'];
    await until(() => server.faces.firstWhere((f) => f['id'] == unassigned)['personId'] == bob, 'face → Bob');
    await waitFor(find.text('Bob')); // info panel reloaded

    // 2b. Hovering Bob's face on the photo outlines it and shows his name.
    final frame = tester.getRect(find.descendant(of: find.byType(ViewerScreen), matching: find.byType(AspectRatio)));
    final bobsFace = Offset(frame.left + frame.width * 230 / 320, frame.top + frame.height * 90 / 240);
    final namesBefore = find.text('Bob').evaluate().length;
    await mouse.moveTo(bobsFace);
    await until(() => find.text('Bob').evaluate().length == namesBefore + 1, 'name label on the photo');
    await shot('faces_hover_photo');
    await mouse.moveTo(Offset(frame.left + 10, frame.bottom - 10)); // no face there
    await until(() => find.text('Bob').evaluate().length == namesBefore, 'label gone off the face');

    // 3. Tag a new face: draw the box, pick Anna, confirm.
    await tester.tap(find.byTooltip('Tag People'));
    await waitFor(find.byType(FaceTagBox));
    final handle = find.descendant(of: find.byType(FaceTagBox), matching: find.byType(Container)).last; // bottom-right
    await tester.drag(handle, const Offset(40, 30));
    await wait(const Duration(milliseconds: 200));
    await shot('faces_tagging');
    final before = server.faces.length;
    await tester.tap(find.text('Select person'));
    await waitFor(find.text('Select a person to tag'));
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Anna')));
    await waitFor(find.text('Do you want to tag this face as Anna?'));
    await wait(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(FilledButton, 'Tag face'));
    await until(() => server.faces.length == before + 1, 'face created');
    final created = server.faces.last;
    expect(created['personId'], anna);
    expect(created['imageWidth'] / created['imageHeight'], closeTo(320 / 240, 0.01), reason: 'aspect of the photo');
    final w = created['boundingBoxX2'] - created['boundingBoxX1'];
    expect(w, greaterThan(0.25 * 4000), reason: 'box was enlarged by dragging');
    expect(find.byType(FaceTagBox), findsNothing);

    // 4. Delete Anna's original face.
    await tester.tap(find.byTooltip('Edit people'));
    await waitFor(find.byType(EditFacesPanel));
    await wait(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('Delete face').first);
    await waitFor(find.byType(AlertDialog));
    await wait(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await until(() => !server.faces.any((f) => f['id'] == annaFace), 'face deleted');

    // Esc leaves the panel first, then the viewer.
    focusView(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await wait(const Duration(milliseconds: 300));
    expect(find.byType(EditFacesPanel), findsNothing);
    expect(find.byType(ViewerScreen), findsOneWidget);

    await mouse.removePointer();
    expect(find.byType(ErrorWidget), findsNothing);
    expect(errors, isEmpty, reason: '$errors');
    FlutterError.onError = previous;
    await server.stop();
  });
}
