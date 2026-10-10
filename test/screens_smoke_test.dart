// Builds every settings/admin/utility screen against a fake server with realistic
// v3.1.0 responses and fails on any exception (release builds would show a grey box).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fotoroll/api.dart';
import 'package:fotoroll/screens/account_settings.dart';
import 'package:fotoroll/screens/admin.dart';
import 'package:fotoroll/screens/admin_user.dart';
import 'package:fotoroll/screens/locked_folder.dart';
import 'package:fotoroll/screens/utilities.dart';
import 'package:intl/date_symbol_data_local.dart';

const _id = '11111111-1111-4111-8111-111111111111';
final _asset = {
  'id': _id, 'type': 'IMAGE', 'originalFileName': 'a.jpg', 'width': 400, 'height': 300,
  'isFavorite': false, 'duration': null, 'fileCreatedAt': '2026-01-01T00:00:00.000Z',
  'localDateTime': '2026-01-01T00:00:00.000Z',
  'exifInfo': {'fileSizeInByte': 123456, 'exifImageWidth': 400, 'exifImageHeight': 300},
};
final _user = {
  'id': _id, 'name': 'Pacuka', 'email': 'p@example.com', 'isAdmin': true, 'deletedAt': null,
  'quotaUsageInBytes': 1000, 'quotaSizeInBytes': null, 'profileChangedAt': '2026-01-01T00:00:00.000Z',
  'createdAt': '2026-01-01T00:00:00.000Z', 'updatedAt': '2026-01-02T00:00:00.000Z', 'storageLabel': null,
};
final _routes = <String, Object?>{
  '/api/users/me': _user,
  '/api/users': [_user],
  '/api/users/me/preferences': {
    'albums': {'defaultAssetOrder': 'desc'}, 'cast': {'gCastEnabled': false},
    'download': {'archiveSize': 4294967296, 'includeEmbeddedVideos': false},
    'emailNotifications': {'enabled': true, 'albumInvite': true, 'albumUpdate': true},
    'folders': {'enabled': true, 'sidebarWeb': false}, 'memories': {'enabled': true, 'duration': 5},
    'people': {'enabled': true, 'sidebarWeb': false, 'minimumFaces': 3}, 'ratings': {'enabled': false},
    'recentlyAdded': {'sidebarWeb': false}, 'sharedLinks': {'enabled': true, 'sidebarWeb': false},
    'tags': {'enabled': false, 'sidebarWeb': false}, 'purchase': {'showSupportBadge': true},
  },
  '/api/assets/statistics': {'images': 10, 'videos': 2, 'total': 12},
  '/api/api-keys': [
    {'id': _id, 'name': 'cli', 'createdAt': '2026-01-01T00:00:00.000Z', 'permissions': ['all']},
  ],
  '/api/sessions': [
    {'id': _id, 'current': true, 'deviceOS': 'Linux', 'deviceType': 'Desktop', 'updatedAt': '2026-01-01T00:00:00.000Z'},
    {'id': '2$_id', 'current': false, 'deviceOS': 'Android', 'deviceType': 'Phone', 'updatedAt': '2026-01-01T00:00:00.000Z'},
  ],
  '/api/partners': [
    {'id': _id, 'name': 'Anna', 'email': 'a@example.com', 'inTimeline': true},
  ],
  '/api/auth/status': {'pinCode': false, 'password': true, 'isElevated': false},
  '/api/admin/users/$_id': _user,
  '/api/admin/users/$_id/statistics': {'images': 3, 'videos': 1, 'total': 4},
  '/api/admin/users/$_id/sessions': [],
  '/api/admin/users/$_id/preferences': {'folders': {'enabled': true}, 'cast': {'gCastEnabled': false}},
  '/api/admin/users': [_user, {..._user, 'id': '2$_id', 'isAdmin': false, 'deletedAt': '2026-01-03T00:00:00.000Z'}],
  '/api/queues': [
    {'name': 'thumbnailGeneration', 'isPaused': false,
     'statistics': {'active': 1, 'waiting': 2, 'failed': 0, 'completed': 0, 'delayed': 0, 'paused': 0}},
    {'name': 'library', 'isPaused': true,
     'statistics': {'active': 0, 'waiting': 0, 'failed': 1, 'completed': 0, 'delayed': 0, 'paused': 0}},
  ],
  '/api/server/statistics': {
    'photos': 10, 'videos': 2, 'usage': 999999, 'usagePhotos': 1, 'usageVideos': 1,
    'usageByUser': [{'userId': _id, 'userName': 'Pacuka', 'photos': 10, 'videos': 2, 'usage': 999999, 'usagePhotos': 1, 'usageVideos': 1, 'quotaSizeInBytes': null}],
  },
  '/api/libraries': [
    {'id': _id, 'name': 'NAS', 'ownerId': _id, 'importPaths': ['/mnt/photos'], 'exclusionPatterns': [], 'assetCount': 3},
  ],
  '/api/admin/database-backups': {'backups': [{'filename': 'dump.sql.gz', 'filesize': 2048, 'timezone': 'UTC'}]},
  '/api/duplicates': [
    {'duplicateId': _id, 'assets': [_asset, {..._asset, 'id': '2$_id'}], 'suggestedKeepAssetIds': [_id]},
  ],
  '/api/search/large-assets': [_asset],
  '/api/system-config': jsonDecode(File('test/fixtures/system_config.json').readAsStringSync()),
  '/api/system-config/defaults': jsonDecode(File('test/fixtures/system_config.json').readAsStringSync()),
};

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 40)));
    await tester.pump();
  }
}

Future<void> _expandAll(WidgetTester tester) async {
  final n = find.byType(ExpansionTile).evaluate().length;
  for (var i = 0; i < n; i++) {
    await tester.ensureVisible(find.byType(ExpansionTile).at(i));
    await tester.tap(find.byType(ExpansionTile).at(i));
    await _settle(tester);
  }
}

void main() {
  late HttpServer server;
  late ImmichApi api;

  setUpAll(() => initializeDateFormatting('en'));
  setUp(() async {
    HttpOverrides.global = null;
  });

  Future<void> start(WidgetTester tester) async {
    await tester.runAsync(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        await req.drain<void>();
        final body = _routes[req.uri.path];
        if (req.uri.path == '/api/users/me/license' || body == null) {
          req.response.statusCode = 404;
          req.response.write('{}');
        } else {
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode(body));
        }
        await req.response.close();
      });
    });
    api = ImmichApi(Credentials(serverUrl: 'http://127.0.0.1:${server.port}', apiKey: 'k'));
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
  }

  Future<void> finish(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
    await tester.runAsync(() => server.close(force: true));
  }

  Widget app(Widget child) => MaterialApp(home: Scaffold(body: child));

  test('generated passwords match the web alphabet', () {
    final p = generatePassword();
    expect(p.length, 16);
    expect(RegExp(r'^[0-9a-zA-Z,.\-{}+!#$%/()=?]+$').hasMatch(p), isTrue);
    expect(generatePassword(), isNot(p));
  });

  testWidgets('account settings: every section opens', (tester) async {
    await start(tester);
    await tester.pumpWidget(app(AccountSettingsScreen(api: api)));
    await _settle(tester);
    await _expandAll(tester);
    expect(find.byType(DataTable), findsOneWidget); // usage statistics
    await finish(tester);
  });

  testWidgets('administration: every tab builds', (tester) async {
    await start(tester);
    await tester.pumpWidget(app(AdminScreen(api: api)));
    await _settle(tester);
    final tabs = find.descendant(of: find.byType(AdminScreen), matching: find.byType(ListTile));
    final n = tabs.evaluate().length;
    expect(n, greaterThanOrEqualTo(6));
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.descendant(of: find.byType(AdminScreen), matching: find.byType(ListTile)).at(i));
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: 'admin tab $i');
    }
    await finish(tester);
  });

  testWidgets('utilities, duplicates, large files, locked folder build', (tester) async {
    await start(tester);
    for (final w in [
      UtilitiesScreen(api: api),
      DuplicatesScreen(api: api),
      LargeFilesScreen(api: api),
      LockedFolderScreen(api: api),
      AdminUserScreen(api: api, userId: _id, currentUserId: _id),
    ]) {
      await tester.pumpWidget(app(w));
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: '${w.runtimeType}');
    }
    await finish(tester);
  });
}
