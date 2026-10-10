// Runs in the real Linux app (flutter test integration_test -d linux): hovers
// video tiles with a mouse and checks the muted preview starts, stops and moves
// between tiles without stalling the UI.
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotoroll/api.dart';
import 'package:fotoroll/i18n.dart';
import 'package:fotoroll/sources.dart';
import 'package:fotoroll/widgets/hover_preview.dart';
import 'package:fotoroll/widgets/timeline_view.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';

String id(int i) => '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}';

Future<HttpServer> fakeServer() async {
  final clip = File('integration_test/fixtures/clip.mp4').readAsBytesSync();
  final thumb = File('integration_test/fixtures/thumb.jpg').readAsBytesSync();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    final res = req.response;
    final path = req.uri.path;
    if (path == '/api/timeline/buckets') {
      res.write(jsonEncode([
        {'timeBucket': '2026-10-01', 'count': 12},
      ]));
    } else if (path == '/api/timeline/bucket') {
      res.write(jsonEncode({
        'id': [for (var i = 0; i < 12; i++) id(i)],
        'isImage': [for (var i = 0; i < 12; i++) i.isOdd],
        'ratio': List.filled(12, 1.0),
        'isFavorite': List.filled(12, false),
        'duration': [for (var i = 0; i < 12; i++) i.isOdd ? null : 3000],
        'fileCreatedAt': List.filled(12, '2026-10-09T12:00:00.000Z'),
        'localOffsetHours': List.filled(12, 0),
      }));
    } else if (path.endsWith('/thumbnail')) {
      res.headers.contentType = ContentType('image', 'jpeg');
      res.add(thumb);
    } else if (path.endsWith('/video/playback')) {
      // Byte ranges, like the Immich server.
      res.headers.set('accept-ranges', 'bytes');
      res.headers.contentType = ContentType('video', 'mp4');
      final range = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(req.headers.value('range') ?? '');
      if (range != null) {
        final start = int.parse(range[1]!);
        final end = range[2]!.isEmpty ? clip.length - 1 : int.parse(range[2]!);
        res.statusCode = 206;
        res.headers.set('content-range', 'bytes $start-$end/${clip.length}');
        res.contentLength = end - start + 1;
        res.add(clip.sublist(start, end + 1));
      } else {
        res.contentLength = clip.length;
        res.add(clip);
      }
    } else {
      res.statusCode = 404;
      res.write('{}');
    }
    await res.close();
  });
  return server;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('hover preview starts, stops and moves between tiles without stalling', (tester) async {
    MediaKit.ensureInitialized();
    await i18n.load('en');
    final server = await fakeServer();
    final api = ImmichApi(Credentials(serverUrl: 'http://127.0.0.1:${server.port}', apiKey: 'k'));
    final source = await TimelineSource.create(api);

    final slowFrames = <Duration>[];
    void onTimings(List<FrameTiming> timings) {
      for (final t in timings) {
        if (t.totalSpan > const Duration(milliseconds: 250)) slowFrames.add(t.totalSpan);
      }
    }

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TimelineView(api: api, source: source))));
    Future<void> wait(Duration d) async {
      final end = DateTime.now().add(d);
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 16));
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
    }

    await wait(const Duration(seconds: 2)); // bucket + thumbnails
    final tiles = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Tile');
    expect(tiles, findsNWidgets(12));
    WidgetsBinding.instance.addTimingsCallback(onTimings);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);

    // Video tiles are the even indices.
    for (final i in [0, 2, 4, 0, 6]) {
      await mouse.moveTo(tester.getCenter(tiles.at(i)));
      final deadline = DateTime.now().add(const Duration(seconds: 6));
      while (HoverPreview.showing.value != id(i) && DateTime.now().isBefore(deadline)) {
        await wait(const Duration(milliseconds: 100));
      }
      expect(HoverPreview.showing.value, id(i), reason: 'preview for tile $i should start');
      await wait(const Duration(milliseconds: 800)); // let it play

      // Move onto an image tile: the preview must stop promptly.
      await mouse.moveTo(tester.getCenter(tiles.at(i + 1)));
      await wait(const Duration(milliseconds: 300));
      expect(HoverPreview.showing.value, isNull, reason: 'preview for tile $i should stop');
    }

    // Quick sweeps across many tiles must not leave anything playing.
    for (var r = 0; r < 3; r++) {
      for (var i = 0; i < 12; i++) {
        await mouse.moveTo(tester.getCenter(tiles.at(i)));
        await wait(const Duration(milliseconds: 120));
      }
    }
    await mouse.moveTo(const Offset(1, 1));
    await wait(const Duration(seconds: 1));
    expect(HoverPreview.showing.value, isNull);

    WidgetsBinding.instance.removeTimingsCallback(onTimings);
    expect(slowFrames, isEmpty, reason: 'UI stalled: $slowFrames');
    await mouse.removePointer();
    await server.close(force: true);
  });
}
