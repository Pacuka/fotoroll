// Exercises the API client against a fake server that returns
// Immich v3.1.0-shaped responses.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:fotoroll/api.dart';
import 'package:fotoroll/i18n.dart';
import 'package:fotoroll/screens/explore.dart' show ageAt;
import 'package:fotoroll/sources.dart';

const _a1 = '11111111-1111-4111-8111-111111111111';
const _a2 = '22222222-2222-4222-8222-222222222222';
const _a3 = '33333333-3333-4333-8333-333333333333';

void main() {
  late HttpServer server;
  late String url;
  final requests = <HttpRequest>[];
  final bodies = <String>[];

  setUpAll(() async {
    await initializeDateFormatting('en');
    i18n.setMessages({}, {}, 'en');
  });

  setUp(() async {
    requests.clear();
    bodies.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    url = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      requests.add(req);
      final body = await utf8.decodeStream(req);
      bodies.add('${req.method} ${req.uri.path} $body');
      final res = req.response;
      res.headers.contentType = ContentType.json;
      final auth = req.headers.value('authorization') ?? req.headers.value('x-api-key');
      final path = req.uri.path;
      if (path == '/api/auth/login') {
        final j = jsonDecode(body);
        if (j['password'] != 'jo') {
          res.statusCode = 401;
          res.write(jsonEncode({'message': 'Incorrect email or password'}));
        } else {
          res.statusCode = 201;
          res.write(jsonEncode({'accessToken': 'tok', 'userId': 'u', 'userEmail': j['email']}));
        }
      } else if (auth == null) {
        res.statusCode = 401;
        res.write('{}');
      } else if (path == '/api/timeline/buckets') {
        res.write(jsonEncode([
          {'timeBucket': '2026-07-01', 'count': 2},
          {'timeBucket': '2026-05-01', 'count': 1},
        ]));
      } else if (path == '/api/timeline/bucket') {
        final b = req.uri.queryParameters['timeBucket'];
        res.write(jsonEncode(b == '2026-07-01'
            ? {
                'id': [_a1, _a2],
                'isImage': [true, false],
                'ratio': [1.5, 0.75],
                'isFavorite': [false, true],
                'duration': [null, 65000],
                'thumbhash': [null, null],
                'fileCreatedAt': ['2026-07-10T22:30:00.000Z', '2026-07-09T10:00:00.000Z'],
                'localOffsetHours': [2, 0],
              }
            : {
                'id': [_a3],
                'isImage': [true],
                'ratio': [1],
                'isFavorite': [false],
                'duration': [null],
                'thumbhash': [null],
              }));
      } else if (path == '/api/search/smart') {
        final page = jsonDecode(body)['page'];
        res.write(jsonEncode({
          'albums': {'items': [], 'count': 0, 'total': 0, 'facets': []},
          'assets': {
            'items': [
              {'id': page == 1 ? _a1 : _a2, 'type': 'IMAGE', 'width': 400, 'height': 200,
               'isFavorite': false, 'duration': null},
            ],
            'count': 1,
            'total': 2,
            'facets': [],
            'nextPage': page == 1 ? '2' : null,
          },
        }));
      } else if (path == '/api/albums') {
        final shared = req.uri.queryParameters['isShared'] == 'true';
        res.write(jsonEncode([
          {'id': _a1, 'albumName': 'Nyár', 'albumThumbnailAssetId': _a1, 'assetCount': 2,
           'shared': shared, 'endDate': '2026-07-10T10:00:00.000Z'},
        ]));
      } else if (path == '/api/people') {
        final page = req.uri.queryParameters['page'];
        res.write(jsonEncode({
          'total': 2,
          'hidden': 0,
          'hasNextPage': page == '1',
          'people': [
            {'id': page == '1' ? _a1 : _a2, 'name': page == '1' ? 'Anna' : '', 'birthDate': '2020-03-15',
             'isHidden': false, 'thumbnailPath': '/x', 'updatedAt': '2026-01-01T00:00:00.000Z'},
          ],
        }));
      } else if (path == '/api/search/explore') {
        res.write(jsonEncode([
          {'fieldName': 'exifInfo.city', 'items': [
            {'value': 'Budapest', 'data': {'id': _a3, 'exifInfo': {'city': 'Budapest', 'country': 'Hungary'}}},
          ]},
          {'fieldName': 'tags', 'items': []},
        ]));
      } else if (path == '/api/search/cities') {
        res.write(jsonEncode([
          {'id': _a1, 'exifInfo': {'city': 'Szeged', 'country': 'Hungary'}},
          {'id': _a2, 'exifInfo': {'city': 'budapest', 'country': 'Hungary'}},
          {'id': _a3, 'exifInfo': {'city': null}},
        ]));
      } else if (path == '/api/search/metadata') {
        final j = jsonDecode(body);
        res.write(jsonEncode({
          'albums': {'items': []},
          'assets': {
            'items': j['city'] == 'Szeged'
                ? [{'id': _a1, 'type': 'VIDEO', 'width': 100, 'height': 100, 'duration': 3000}]
                : [],
            'nextPage': null,
          },
        }));
      } else if (path == '/api/assets' && (req.method == 'PUT' || req.method == 'DELETE')) {
        res.statusCode = 204;
      } else if (path == '/api/trash/restore/assets') {
        res.write(jsonEncode({'count': 1}));
      } else if (path == '/api/albums/$_a3/assets') {
        res.write(jsonEncode([
          {'id': _a1, 'success': true},
          {'id': _a2, 'success': false, 'error': 'duplicate'},
        ]));
      } else if (path == '/api/download/info') {
        res.statusCode = 201;
        res.write(jsonEncode({'totalSize': 4, 'archives': [{'assetIds': [_a1, _a2], 'size': 4}]}));
      } else if (path == '/api/download/archive') {
        res.headers.contentType = ContentType.binary;
        res.add([0x50, 0x4b, 3, 4]);
      } else if (path == '/api/assets/$_a1/original') {
        res.headers.contentType = ContentType.binary;
        res.contentLength = 1000;
        res.add(List.filled(1000, 7));
      } else {
        res.statusCode = 404;
        res.write('{}');
      }
      await res.close();
    });
  });

  tearDown(() => server.close(force: true));

  test('normalizes server URLs', () {
    expect(ImmichApi.normalizeServerUrl('photos.x.hu/'), 'https://photos.x.hu');
    expect(ImmichApi.normalizeServerUrl('http://h:2283/api/'), 'http://h:2283');
  });

  test('login returns bearer token, wrong password gives readable error', () async {
    final c = await ImmichApi.login('$url/', 'a@b.hu', 'jo');
    expect(c.headers['Authorization'], 'Bearer tok');
    expect(
      () => ImmichApi.login(url, 'a@b.hu', 'rossz'),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
    );
  });

  test('timeline source pages through columnar buckets', () async {
    final api = ImmichApi(Credentials(serverUrl: url, apiKey: 'k'));
    final src = await TimelineSource.create(api);
    expect(src.length, 3);
    expect([src.bucketStart(0), src.bucketStart(1)], [0, 2]);
    expect(src.bucketLabel(0), 'July 2026');
    expect(src.bucketYear(1), 2026);
    expect(src.bucketAssets(1, load: false), isNull);
    expect(src.at(0), isNull); // not loaded yet
    final video = await src.load(1);
    expect(video!.id, _a2);
    expect(video.isImage, isFalse);
    expect(video.durationMs, 65000);
    expect(video.isFavorite, isTrue);
    // 22:30 UTC at +2h is already the next day locally.
    expect((await src.load(0))!.localDate, DateTime(2026, 7, 11, 0, 30));
    expect(video.localDate, DateTime(2026, 7, 9, 10));
    expect((await src.load(2))!.id, _a3);
    expect(requests.first.headers.value('x-api-key'), 'k');
    expect(requests.first.uri.queryParameters['visibility'], 'timeline');
  });

  test('search source follows nextPage', () async {
    final api = ImmichApi(Credentials(serverUrl: url, apiKey: 'k'));
    final src = SearchSource((p) => api.search(SearchFilter(query: 'kutya'), page: p));
    await src.loadMore();
    expect(src.length, 1);
    expect(src.hasMore, isTrue);
    expect((await src.load(1))!.id, _a2);
    expect(src.hasMore, isFalse);
    expect(src.at(0)!.ratio, 2);
  });

  test('albums merges owned and shared without duplicates', () async {
    final api = ImmichApi(Credentials(serverUrl: url, apiKey: 'k'));
    final albums = await api.albums();
    expect(albums, hasLength(1));
    expect(albums.single.name, 'Nyár');
  });

  test('downloads original to file', () async {
    final api = ImmichApi(Credentials(serverUrl: url, apiKey: 'k'));
    final dir = await Directory.systemTemp.createTemp('immich_test');
    final f = File('${dir.path}/x.jpg');
    double last = 0;
    await api.downloadOriginal(_a1, f, onProgress: (p) => last = p);
    expect(await f.length(), 1000);
    expect(last, 1.0);
    expect(File('${f.path}.part').existsSync(), isFalse);
    await dir.delete(recursive: true);
  });

  test('people pages through hasNextPage', () async {
    final api = ImmichApi(Credentials(serverUrl: url, apiKey: 'k'));
    final people = await api.people();
    expect(people.map((p) => p.id), [_a1, _a2]);
    expect(people.first.birthDate, DateTime(2020, 3, 15));
    expect(api.personThumbnailUrl(people.first), contains('/api/people/$_a1/thumbnail?updatedAt='));
  });

  test('explore and cities return places', () async {
    final api = ImmichApi(Credentials(serverUrl: url, apiKey: 'k'));
    final explore = await api.explorePlaces();
    expect(explore.single.city, 'Budapest');
    expect(explore.single.country, 'Hungary');
    expect(explore.single.assetId, _a3);
    final places = await api.places();
    expect(places.map((p) => p.city), ['budapest', 'Szeged']); // sorted, nulls skipped
    final hits = await api.citySearch('Szeged');
    expect(hits.assets.single.isImage, isFalse);
    expect(hits.nextPage, isNull);
  });

  test('timeline query sends person and createdAt ordering', () async {
    final api = ImmichApi(Credentials(serverUrl: url, apiKey: 'k'));
    await api.timeBuckets(const TimelineQuery(personId: _a1));
    await api.timeBuckets(const TimelineQuery(byUploadDate: true));
    await api.timeBuckets(TimelineQuery.album(_a2));
    final q = requests.map((r) => r.uri.queryParameters).toList();
    expect(q[0]['personId'], _a1);
    expect(q[0]['visibility'], 'timeline');
    expect(q[1]['orderBy'], 'createdAt');
    expect(q[2]['albumId'], _a2);
    expect(q[2].containsKey('visibility'), isFalse);
  });

  test('age formatting uses the Immich strings', () {
    i18n.setMessages({
      'age_months': 'Age {months, plural, one {# month} other {# months}}',
      'age_year_months': 'Age 1 year, {months, plural, one {# month} other {# months}}',
      'age_years': '{years, plural, other {Age #}}',
    }, {}, 'en');
    final b = DateTime(2020, 3, 15);
    expect(ageAt(b, DateTime(2020, 9, 20)), 'Age 6 months');
    expect(ageAt(b, DateTime(2021, 3, 15)), 'Age 1');
    expect(ageAt(b, DateTime(2021, 7, 15)), 'Age 1 year, 4 months');
    expect(ageAt(b, DateTime(2026, 3, 14)), 'Age 5');
    expect(ageAt(b, DateTime(2019, 1, 1)), isNull);
  });

  test('edit calls use the right methods and bodies', () async {
    final api = ImmichApi(Credentials(serverUrl: url, apiKey: 'k'));
    await api.updateAssets([_a1], isFavorite: true);
    await api.updateAssets([_a2], visibility: 'archive');
    await api.deleteAssets([_a1]);
    await api.deleteAssets([_a2], force: true);
    await api.restoreAssets([_a1]);
    expect(await api.addToAlbum(_a3, [_a1, _a2]), 1);
    expect(bodies, [
      'PUT /api/assets {"ids":["$_a1"],"isFavorite":true}',
      'PUT /api/assets {"ids":["$_a2"],"visibility":"archive"}',
      'DELETE /api/assets {"ids":["$_a1"],"force":false}',
      'DELETE /api/assets {"ids":["$_a2"],"force":true}',
      'POST /api/trash/restore/assets {"ids":["$_a1"]}',
      'PUT /api/albums/$_a3/assets {"ids":["$_a1","$_a2"]}',
    ]);
  });

  test('zip download writes the archive', () async {
    final api = ImmichApi(Credentials(serverUrl: url, apiKey: 'k'));
    final dir = await Directory.systemTemp.createTemp('immich_zip');
    final files = await api.downloadZip([_a1, _a2], dir);
    expect(files.single.path, endsWith('.zip'));
    expect(await files.single.readAsBytes(), [0x50, 0x4b, 3, 4]);
    await dir.delete(recursive: true);
  });

  test('removing assets updates counts and offsets in place', () async {
    final api = ImmichApi(Credentials(serverUrl: url, apiKey: 'k'));
    final src = await TimelineSource.create(api);
    await src.load(0);
    await src.load(2);
    var notified = 0;
    src.addListener(() => notified++);
    src.updateAssets({_a1}, (a) => a.copyWith(isFavorite: true));
    expect(src.at(0)!.isFavorite, isTrue);
    src.removeAssets({_a1});
    expect(src.length, 2);
    expect(src.bucketSize(0), 1);
    expect(src.bucketStart(1), 1);
    expect(src.at(0)!.id, _a2);
    expect(src.at(1)!.id, _a3);
    expect(notified, 2);
  });
}
