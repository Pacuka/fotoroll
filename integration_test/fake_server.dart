// In-memory Immich v3.3.3 stand-in for integration tests: serves a small
// library (photos + videos), records edits, and supports the endpoints the app uses.
import 'dart:convert';
import 'dart:io';

String uid(int i) => '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}';

class FakeImmich {
  late HttpServer _server;
  final clip = File('integration_test/fixtures/clip.mp4').readAsBytesSync();
  final thumb = File('integration_test/fixtures/thumb.jpg').readAsBytesSync();
  final requests = <String>[];
  final searches = <(String, Map<String, dynamic>)>[]; // (endpoint, body)
  /// Asset id -> image bytes served as its preview and original; marked EQUIRECTANGULAR.
  final panoramas = <String, List<int>>{};
  final panoramaVideos = <String>{};
  /// Faces: id, assetId, personId (nullable), imageWidth/Height, boundingBox*.
  final faces = <Map<String, dynamic>>[];
  /// File names received by POST /api/assets.
  final uploads = <String>[];
  int _nextId = 700;

  /// Adds a face to [assetId] (box in a 320×240 image), optionally of [personId].
  String addFace(String assetId, {String? personId, int x = 100, int y = 60, int w = 60, int h = 80}) {
    final id = uid(_nextId++);
    faces.add({'id': id, 'assetId': assetId, 'personId': personId, 'imageWidth': 320, 'imageHeight': 240,
      'boundingBoxX1': x, 'boundingBoxY1': y, 'boundingBoxX2': x + w, 'boundingBoxY2': y + h});
    _syncPeople(assetId);
    return id;
  }

  Map<String, dynamic>? _person(String? id) => id == null ? null : people.where((p) => p['id'] == id).firstOrNull;

  /// The asset's `people` follows its faces, like the server.
  void _syncPeople(String assetId) {
    final ids = {for (final f in faces) if (f['assetId'] == assetId && f['personId'] != null) f['personId']};
    asset(assetId)['people'] = [for (final id in ids) ?_person(id as String)];
  }

  /// Makes photo [id] a live photo whose motion part is video [videoId] (served as the test clip).
  void makeLivePhoto(String id, String videoId) => asset(id)['livePhotoVideoId'] = videoId;

  /// Turns photo or video [id] into a panorama backed by [fixture] (.jpg or .mp4).
  void makePanorama(String id, String fixture) {
    panoramas[id] = File('integration_test/fixtures/$fixture').readAsBytesSync();
    if (fixture.endsWith('.mp4')) panoramaVideos.add(id);
    final a = asset(id);
    a['originalFileName'] = fixture;
    (a['exifInfo'] as Map)['projectionType'] = 'EQUIRECTANGULAR';
  }

  /// Other users of the server (GET /api/users), e.g. for invitations.
  final otherUsers = [
    for (final (i, name) in [(901, 'Anna'), (902, 'Bence'), (903, 'Csilla')])
      {'id': uid(i), 'name': name, 'email': '${name.toLowerCase()}@example.com', 'avatarColor': 'green',
       'profileImagePath': '', 'profileChangedAt': '2026-01-01T00:00:00.000Z'},
  ];
  /// User id -> cluster group id (v3.2+). Everyone starts in a group of their own.
  late final clusterGroupOf = {for (final u in [me, ...otherUsers]) u['id'] as String: 'g-${u['id']}'};
  /// Pending invitations: id, clusterGroupId, userId, createdAt.
  final clusterRequests = <Map<String, dynamic>>[];
  /// Shared people (v3.3): {personId, sharedById, sharedWithId, role}.
  final personAccess = <Map<String, dynamic>>[];
  /// Bodies of PUT /api/people/{id}, in order.
  final personUpdates = <Map<String, dynamic>>[];
  /// Person id -> the same person in other users' libraries (otherPeople).
  final otherPeopleOf = <String, List<Map<String, dynamic>>>{};

  /// PersonResponseDto with the v3.3 sharing fields.
  Map<String, dynamic> personJson(Map<String, dynamic> p) {
    final myId = me['id'];
    Map<String, dynamic> userRole(String id, String role) => {..._user(id), 'role': role};
    return {
      ...p,
      'sharedWith': [
        for (final a in personAccess)
          if (a['personId'] == p['id'] && a['sharedById'] == myId) userRole(a['sharedWithId'], a['role']),
      ],
      'sharedBy': [
        for (final a in personAccess)
          if (a['personId'] == p['id'] && a['sharedWithId'] == myId) userRole(a['sharedById'], a['role']),
      ],
      'otherPeople': otherPeopleOf[p['id']] ?? [],
    };
  }

  /// Cluster groups whose facial recognition was reset.
  final regeneratedGroups = <String>[];
  Map<String, dynamic> _user(String id) => [me, ...otherUsers].firstWhere((u) => u['id'] == id);

  final me = {
    'id': uid(900), 'name': 'Tester', 'email': 't@example.com', 'isAdmin': true,
    'profileChangedAt': '2026-01-01T00:00:00.000Z', 'quotaUsageInBytes': 1000, 'quotaSizeInBytes': null,
    'createdAt': '2026-01-01T00:00:00.000Z', 'updatedAt': '2026-01-01T00:00:00.000Z', 'deletedAt': null,
  };

  /// 10 assets: even = video, odd = photo; all on 2026-10-09.
  late final List<Map<String, dynamic>> assets = [
    for (var i = 0; i < 10; i++)
      {
        'id': uid(i),
        'type': i.isEven ? 'VIDEO' : 'IMAGE',
        'originalFileName': i.isEven ? 'clip$i.mp4' : 'photo$i.jpg',
        'width': 320, 'height': 240,
        'isFavorite': false, 'isTrashed': false, 'visibility': 'timeline',
        'duration': i.isEven ? 3000 : null,
        'fileCreatedAt': '2026-10-09T${(20 - i).toString().padLeft(2, '0')}:00:00.000Z',
        'localDateTime': '2026-10-09T${(20 - i).toString().padLeft(2, '0')}:00:00.000Z',
        'ownerId': uid(900),
        'exifInfo': <String, dynamic>{
          'description': '', 'rating': null, 'fileSizeInByte': 12345,
          'city': 'Budapest', 'country': 'Hungary', 'latitude': 47.5, 'longitude': 19.05,
        },
        'people': <dynamic>[],
        'tags': <Map<String, dynamic>>[],
      },
  ];
  final tags = <Map<String, dynamic>>[];
  final people = <Map<String, dynamic>>[
    {'id': uid(600), 'name': '', 'birthDate': null, 'isHidden': false, 'isFavorite': false,
     'thumbnailPath': '/x', 'updatedAt': '2026-01-01T00:00:00.000Z'},
  ];
  late final memories = <Map<String, dynamic>>[
    {'id': uid(800), 'type': 'on_this_day', 'data': {'year': 2025}, 'isSaved': false, 'seenAt': null,
     'assets': [assets[1], assets[3]]},
  ];
  final albums = <Map<String, dynamic>>[];
  /// API keys; `secret` is what a client sends in x-api-key.
  final apiKeys = <Map<String, dynamic>>[];
  /// Reject requests whose x-api-key isn't a secret in [apiKeys] (off: any key works).
  bool enforceApiKeys = false;
  /// Behave like Immich v3.1: no POST /api-keys/:id/rotate, tag updates ignore `name`.
  bool v31 = false;
  /// What GET /server/version reports (v31 makes it 3.1.0).
  List<int> version = [3, 3, 3];

  int get port => _server.port;
  String get url => 'http://127.0.0.1:$port';
  Map<String, dynamic> asset(String id) => assets.firstWhere((a) => a['id'] == id);

  List<Map<String, dynamic>> _visible(Map<String, String> q) => assets.where((a) {
        if (q['isTrashed'] == 'true') return a['isTrashed'] == true;
        if (a['isTrashed'] == true) return false;
        if (q['isFavorite'] == 'true' && a['isFavorite'] != true) return false;
        if (q['visibility'] != null && a['visibility'] != q['visibility']) return false;
        if (q['albumId'] != null) {
          final al = albums.firstWhere((x) => x['id'] == q['albumId'], orElse: () => {'assetIds': []});
          if (!(al['assetIds'] as List).contains(a['id'])) return false;
        }
        return true;
      }).toList();

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    final path = req.uri.path;
    final q = req.uri.queryParameters;
    final bytes = await req.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
    final multipart = req.headers.contentType?.mimeType == 'multipart/form-data';
    final raw = multipart ? latin1.decode(bytes) : utf8.decode(bytes, allowMalformed: true);
    final body = raw.isEmpty || multipart ? null : jsonDecode(raw);
    requests.add('${req.method} $path');
    Object? out;
    var status = 200;
    final m = req.method;

    RegExpMatch? match(String pattern) => RegExp('^$pattern\$').firstMatch(path);

    final apiKey = req.headers.value('x-api-key');
    Map<String, dynamic>? myKey() => apiKeys.where((k) => k['secret'] == apiKey).firstOrNull;
    Map<String, dynamic> keyJson(Map<String, dynamic> k) => {...k}..remove('secret');
    if (enforceApiKeys && myKey() == null) {
      res.statusCode = 401;
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode({'message': 'Invalid API key'}));
      return res.close();
    }

    final pano = panoramas[RegExp(r'/api/assets/([\w-]+)/').firstMatch(path)?[1]];
    if (pano != null && panoramaVideos.contains(RegExp(r'/api/assets/([\w-]+)/').firstMatch(path)?[1]) &&
        path.endsWith('/video/playback')) {
      res.headers.contentType = ContentType('video', 'mp4');
      res.headers.contentLength = pano.length;
      res.add(pano);
      return res.close();
    }
    if (pano != null && !path.endsWith('/video/playback') &&
        (path.endsWith('/thumbnail') || path.endsWith('/original'))) {
      res.headers.contentType = ContentType('image', 'jpeg');
      res.headers.contentLength = pano.length;
      res.add(pano);
      return res.close();
    }
    if (path.endsWith('/thumbnail') || path.endsWith('/profile-image')) {
      res.headers.contentType = ContentType('image', 'jpeg');
      res.add(thumb);
      return res.close();
    }
    if (path.endsWith('/video/playback') || path.endsWith('/original')) {
      res.headers.set('accept-ranges', 'bytes');
      res.headers.contentType = ContentType('video', 'mp4');
      final r = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(req.headers.value('range') ?? '');
      if (r != null) {
        final s = int.parse(r[1]!);
        final e = r[2]!.isEmpty ? clip.length - 1 : int.parse(r[2]!);
        res.statusCode = 206;
        res.headers.set('content-range', 'bytes $s-$e/${clip.length}');
        res.contentLength = e - s + 1;
        res.add(clip.sublist(s, e + 1));
      } else {
        res.contentLength = clip.length;
        res.add(clip);
      }
      return res.close();
    }

    if (path == '/api/api-keys' && m == 'GET') {
      out = apiKeys.map(keyJson).toList();
    } else if (path == '/api/api-keys/me' && m == 'GET') {
      final k = myKey();
      (status, out) = k == null ? (400, {'message': 'Not an API key'}) : (200, keyJson(k));
    } else if (match(r'/api/api-keys/([\w-]+)/rotate') case final r? when m == 'POST' && !v31) {
      final k = apiKeys.firstWhere((k) => k['id'] == r[1]);
      k['secret'] = 'secret-${DateTime.now().microsecondsSinceEpoch}';
      out = {...keyJson(k), 'secret': k['secret'], 'apiKey': keyJson(k)};
    } else if (path == '/api/users/me' && m == 'GET') {
      out = {...me, 'clusterGroupId': clusterGroupOf[me['id']]};
    } else if (path == '/api/users' && m == 'GET') {
      out = [me, ...otherUsers];
    } else if (match(r'/api/cluster-groups/([\w-]+)/users') case final g?) {
      out = [for (final e in clusterGroupOf.entries) if (e.value == g[1]) _user(e.key)];
    } else if (path == '/api/cluster-groups/requests' && m == 'GET') {
      out = clusterRequests.where((r) => r['userId'] == me['id']).toList();
    } else if (match(r'/api/cluster-groups/([\w-]+)/requests') case final g?) {
      if (m == 'PUT') {
        final r = {'id': uid(_nextId++), 'clusterGroupId': g[1], 'userId': body['userId'],
          'createdAt': '2026-10-14T00:00:00.000Z'};
        clusterRequests.add(r);
        out = r;
      } else {
        out = clusterRequests.where((r) => r['clusterGroupId'] == g[1]).toList();
      }
    } else if (match(r'/api/cluster-groups/requests/([\w-]+)/accept') case final g?) {
      final r = clusterRequests.firstWhere((r) => r['id'] == g[1]);
      clusterRequests.remove(r);
      clusterGroupOf[r['userId']] = r['clusterGroupId'];
      status = 204;
    } else if (match(r'/api/cluster-groups/requests/([\w-]+)') case final g? when m == 'DELETE') {
      clusterRequests.removeWhere((r) => r['id'] == g[1]);
      status = 204;
    } else if (match(r'/api/cluster-groups/([\w-]+)/leave') != null) {
      clusterGroupOf[me['id'] as String] = 'g-new-${_nextId++}';
      status = 204;
    } else if (match(r'/api/cluster-groups/([\w-]+)/regenerate-people') case final g?) {
      regeneratedGroups.add(g[1]!);
      status = 204;
    } else if (path == '/api/server/storage') {
      out = {'diskUse': '1 GiB', 'diskSize': '10 GiB', 'diskUsagePercentage': 10};
    } else if (path == '/api/server/version') {
      final v = v31 ? [3, 1, 0] : version;
      out = {'major': v[0], 'minor': v[1], 'patch': v[2]};
    } else if (path == '/api/config') {
      out = {'trash': {'enabled': true, 'days': 30}};
    } else if (path == '/api/server/media-types') {
      out = {'image': ['.jpg'], 'video': ['.mp4'], 'sidecar': []};
    } else if (path == '/api/timeline/buckets') {
      final n = _visible(q).length;
      out = n == 0 ? [] : [{'timeBucket': '2026-10-01', 'count': n}];
    } else if (path == '/api/timeline/bucket') {
      final v = _visible(q);
      out = {
        'id': [for (final a in v) a['id']],
        'isImage': [for (final a in v) a['type'] == 'IMAGE'],
        'ratio': [for (final _ in v) 320 / 240],
        'isFavorite': [for (final a in v) a['isFavorite']],
        'duration': [for (final a in v) a['duration']],
        'fileCreatedAt': [for (final a in v) a['fileCreatedAt']],
        'localOffsetHours': [for (final _ in v) 0],
        'projectionType': [for (final a in v) (a['exifInfo'] as Map)['projectionType']],
        'livePhotoVideoId': [for (final a in v) a['livePhotoVideoId']],
      };
    } else if (match(r'/api/assets/([\w-]+)') != null && m == 'GET') {
      out = asset(match(r'/api/assets/([\w-]+)')![1]!);
    } else if (match(r'/api/assets/([\w-]+)') != null && m == 'PUT') {
      final a = asset(match(r'/api/assets/([\w-]+)')![1]!);
      final exif = a['exifInfo'] as Map<String, dynamic>;
      for (final k in ['description', 'rating', 'latitude', 'longitude']) {
        if ((body as Map).containsKey(k)) exif[k] = body[k];
      }
      if (body.containsKey('dateTimeOriginal')) a['localDateTime'] = body['dateTimeOriginal'];
      out = a;
    } else if (path == '/api/assets' && m == 'POST') {
      // Multipart upload: remember the file name.
      final name = RegExp(r'filename="([^"]*)"').firstMatch(raw)?[1] ?? '?';
      uploads.add(name);
      status = 201;
      out = {'id': uid(_nextId++), 'status': 'created'};
    } else if (path == '/api/assets' && m == 'PUT') {
      for (final id in body['ids']) {
        final a = asset(id);
        if (body.containsKey('isFavorite')) a['isFavorite'] = body['isFavorite'];
        if (body.containsKey('visibility')) a['visibility'] = body['visibility'];
      }
      status = 204;
    } else if (path == '/api/assets' && m == 'DELETE') {
      for (final id in body['ids']) {
        asset(id)['isTrashed'] = true;
      }
      status = 204;
    } else if (path == '/api/trash/restore/assets') {
      for (final id in body['ids']) {
        asset(id)['isTrashed'] = false;
      }
      out = {'count': (body['ids'] as List).length};
    } else if (path == '/api/tags' && m == 'GET') {
      out = tags;
    } else if (path == '/api/tags' && m == 'PUT') {
      out = [
        for (final name in body['tags'])
          tags.firstWhere((t) => t['value'] == name, orElse: () {
            final t = {'id': uid(500 + tags.length), 'name': name, 'value': name};
            tags.add(t);
            return t;
          }),
      ];
    } else if (match(r'/api/tags/([\w-]+)') case final r? when m == 'PUT' && r[1] != 'assets') {
      final tag = tags.firstWhere((t) => t['id'] == r[1]);
      if (body.containsKey('color')) tag['color'] = body['color'];
      if (body['name'] != null && !v31) {
        // Renames the last part; children follow (tag.repository update).
        final old = tag['value'] as String;
        final value = [...old.split('/')..removeLast(), body['name']].join('/');
        for (final t in tags) {
          final v = t['value'] as String;
          if (v == old || v.startsWith('$old/')) t['value'] = value + v.substring(old.length);
        }
        tag['name'] = body['name'];
      }
      out = tag;
    } else if (path == '/api/tags/assets' && m == 'PUT') {
      for (final aid in body['assetIds']) {
        for (final tid in body['tagIds']) {
          (asset(aid)['tags'] as List).add(tags.firstWhere((t) => t['id'] == tid));
        }
      }
      out = {'count': 1};
    } else if (match(r'/api/tags/([\w-]+)/assets') != null && m == 'DELETE') {
      final tid = match(r'/api/tags/([\w-]+)/assets')![1];
      for (final aid in body['ids']) {
        (asset(aid)['tags'] as List).removeWhere((t) => t['id'] == tid);
      }
      out = [];
    } else if (path == '/api/albums' && m == 'GET') {
      out = q['assetId'] != null
          ? albums.where((a) => (a['assetIds'] as List).contains(q['assetId'])).map(_album).toList()
          : albums.map(_album).toList();
    } else if (path == '/api/albums' && m == 'POST') {
      final a = {
        'id': uid(700 + albums.length), 'albumName': body['albumName'], 'description': '',
        'ownerId': uid(900), 'assetIds': List<String>.from(body['assetIds'] ?? []), 'order': 'desc',
      };
      albums.add(a);
      out = _album(a);
      status = 201;
    } else if (match(r'/api/albums/([\w-]+)/assets') != null && m == 'PUT') {
      final a = albums.firstWhere((x) => x['id'] == match(r'/api/albums/([\w-]+)/assets')![1]);
      out = [
        for (final id in body['ids'])
          {'id': id, 'success': !(a['assetIds'] as List).contains(id) && ((a['assetIds'] as List)..add(id)).isNotEmpty},
      ];
    } else if (match(r'/api/albums/([\w-]+)') != null && m == 'GET') {
      out = _album(albums.firstWhere((x) => x['id'] == match(r'/api/albums/([\w-]+)')![1]));
    } else if (match(r'/api/albums/([\w-]+)') != null && m == 'PATCH') {
      final a = albums.firstWhere((x) => x['id'] == match(r'/api/albums/([\w-]+)')![1]);
      // Server: AlbumUpdate = owner or a shared user with the editor role.
      final canEdit = a['ownerId'] == me['id'] ||
          [...?a['albumUsers'] as List?].any((u) => u['user']['id'] == me['id'] && u['role'] == 'editor');
      if (!canEdit) {
        status = 403;
        out = {'message': 'Not found or no album.update access'};
      } else {
        if (body['albumName'] != null) a['albumName'] = body['albumName'];
        if (body['description'] != null) a['description'] = body['description'];
        if (body['order'] != null) a['order'] = body['order'];
        out = _album(a);
      }
    } else if (path == '/api/memories' || path == '/api/memories/statistics') {
      // `for` = today's lane; otherwise the memories page with its filters (v3.2+).
      final now = DateTime.now();
      final list = [
        for (final mem in memories)
          if (q['for'] != null
              ? mem['lane'] != false
              : (q['isSaved'] == null || '${mem['isSaved']}' == q['isSaved']) &&
                  (q['isUpcoming'] != 'false' ||
                      !(DateTime.tryParse(mem['showAt'] as String? ?? '')?.isAfter(now) ?? false)))
            mem,
      ];
      if (path.endsWith('statistics')) {
        out = {'total': list.length};
      } else {
        final size = int.tryParse(q['size'] ?? '') ?? list.length;
        final page = int.tryParse(q['page'] ?? '') ?? 1;
        out = list.skip((page - 1) * size).take(size).toList();
      }
    } else if (match(r'/api/memories/([\w-]+)') != null && m == 'PUT') {
      final mem = memories.firstWhere((x) => x['id'] == match(r'/api/memories/([\w-]+)')![1]);
      (body as Map).forEach((k, v) => mem[k] = v);
      out = mem;
    } else if (path == '/api/map/markers') {
      out = [for (final a in assets) {'id': a['id'], 'lat': 47.5, 'lon': 19.05, 'city': 'Budapest', 'state': null, 'country': 'Hungary'}];
    } else if (path == '/api/search/explore') {
      out = [
        {'fieldName': 'exifInfo.city', 'items': [{'value': 'Budapest', 'data': assets[1]}]},
      ];
    } else if (path == '/api/search/smart' || path == '/api/search/metadata') {
      final b = (body as Map).cast<String, dynamic>();
      searches.add((path, b));
      final hits = assets.where((a) => b['type'] == null || a['type'] == b['type']).take(3).toList();
      out = {'albums': {'items': []}, 'assets': {'items': hits, 'nextPage': null, 'count': hits.length, 'total': hits.length}};
    } else if (path == '/api/search/suggestions') {
      out = switch (q['type']) {
        'country' => ['Austria', 'Hungary', null],
        'state' => q['country'] == 'Hungary' ? ['Budapest'] : ['Vienna'],
        'city' => ['Budapest'],
        'camera-make' => ['Canon', 'Sony'],
        'camera-model' => q['make'] == 'Sony' ? ['A7 IV'] : ['EOS R6'],
        _ => <String>[],
      };
    } else if (path == '/api/faces' && m == 'GET') {
      out = [
        for (final f in faces)
          if (f['assetId'] == q['id']) {...f, 'person': _person(f['personId'] as String?)},
      ];
    } else if (path == '/api/faces' && m == 'POST') {
      final b = (body as Map).cast<String, dynamic>();
      final id = uid(_nextId++);
      faces.add({'id': id, 'assetId': b['assetId'], 'personId': b['personId'], 'imageWidth': b['imageWidth'],
        'imageHeight': b['imageHeight'], 'boundingBoxX1': b['x'], 'boundingBoxY1': b['y'],
        'boundingBoxX2': b['x'] + b['width'], 'boundingBoxY2': b['y'] + b['height']});
      _syncPeople(b['assetId']);
      out = null;
      status = 201;
    } else if (match(r'/api/faces/([\w-]+)') != null && m == 'PUT') {
      final personId = match(r'/api/faces/([\w-]+)')![1];
      final f = faces.firstWhere((x) => x['id'] == (body as Map)['id']);
      f['personId'] = personId;
      _syncPeople(f['assetId']);
      out = _person(personId);
    } else if (match(r'/api/faces/([\w-]+)') != null && m == 'DELETE') {
      final f = faces.firstWhere((x) => x['id'] == match(r'/api/faces/([\w-]+)')![1]);
      faces.remove(f);
      _syncPeople(f['assetId']);
      status = 204;
    } else if (path == '/api/people' && m == 'POST') {
      final p = {'id': uid(_nextId++), 'name': (body as Map?)?['name'] ?? '', 'birthDate': null, 'isHidden': false,
        'isFavorite': false, 'thumbnailPath': '/x', 'updatedAt': '2026-01-01T00:00:00.000Z'};
      people.add(p);
      out = p;
      status = 201;
    } else if (path == '/api/people/users' && m == 'GET') {
      final myId = me['id'];
      out = [
        for (final a in personAccess)
          if ((q['personId'] == null || a['personId'] == q['personId']) &&
              (q['direction'] == 'shared-by' ? a['sharedById'] == myId : a['sharedWithId'] == myId))
            {...a, 'sharedBy': _user(a['sharedById']), 'sharedWith': _user(a['sharedWithId'])},
      ];
    } else if (path == '/api/people/users' && m == 'PUT') {
      final ids = body['type'] == 'everyone' ? [for (final p in people) p['id']] : body['personIds'] as List;
      for (final personId in ids) {
        for (final userId in body['sharedWithIds'] as List) {
          personAccess.removeWhere((a) =>
              a['personId'] == personId && a['sharedById'] == me['id'] && a['sharedWithId'] == userId);
          personAccess.add(
              {'personId': personId, 'sharedById': me['id'], 'sharedWithId': userId, 'role': body['role']});
        }
      }
      status = 204;
    } else if (path == '/api/people/users' && m == 'DELETE') {
      for (final d in body as List) {
        personAccess.removeWhere((a) =>
            a['personId'] == d['personId'] && a['sharedWithId'] == d['sharedWithId'] &&
            a['sharedById'] == (d['sharedById'] ?? me['id']));
      }
      status = 204;
    } else if (path == '/api/people') {
      // sharedById = people that user gave access to; sharedWithId = people that user was given.
      bool shared(Map p) => personAccess.any((a) =>
          a['personId'] == p['id'] &&
          (q['sharedById'] == null || a['sharedById'] == q['sharedById']) &&
          (q['sharedWithId'] == null || a['sharedWithId'] == q['sharedWithId']));
      final list = [
        for (final p in people)
          if ((q['withHidden'] == 'true' || p['isHidden'] != true) &&
              (q['isHidden'] == null || '${p['isHidden']}' == q['isHidden']) &&
              (q['isFavorite'] == null || '${p['isFavorite']}' == q['isFavorite']) &&
              (q['sharedById'] == null && q['sharedWithId'] == null || shared(p)))
            personJson(p),
      ];
      out = {'people': list, 'total': list.length, 'hidden': 0, 'hasNextPage': false};
    } else if (match(r'/api/people/([\w-]+)') != null && m == 'GET') {
      out = personJson(people.firstWhere((x) => x['id'] == match(r'/api/people/([\w-]+)')![1]));
    } else if (match(r'/api/people/([\w-]+)') != null && m == 'PUT') {
      final pe = people.firstWhere((x) => x['id'] == match(r'/api/people/([\w-]+)')![1]);
      personUpdates.add({...body as Map<String, dynamic>});
      // userId only picks whose record changes; the fake keeps one record.
      body.forEach((k, v) => k == 'userId' ? null : pe[k] = v);
      out = personJson(pe);
    } else if (path == '/api/view/folder/unique-paths') {
      out = ['/photos/2026/october', '/photos/2025'];
    } else if (path == '/api/view/folder') {
      out = assets.take(4).toList();
    } else if (path == '/api/partners' || path == '/api/sessions' ||
        path == '/api/libraries' || path == '/api/duplicates' || path == '/api/shared-links') {
      out = [];
    } else if (path == '/api/auth/status') {
      out = {'pinCode': false, 'password': true, 'isElevated': false};
    } else if (path == '/api/assets/statistics') {
      out = {'images': 5, 'videos': 5, 'total': 10};
    } else if (path == '/api/users/me/preferences') {
      // Every optional sidebar entry on, so the test visits them all.
      out = {
        'folders': {'enabled': true, 'sidebarWeb': true}, 'memories': {'enabled': true, 'sidebarWeb': true},
        'people': {'enabled': true, 'sidebarWeb': true, 'updateStrategy': 'self'}, 'ratings': {'enabled': true},
        'tags': {'enabled': true, 'sidebarWeb': true}, 'sharedLinks': {'enabled': true, 'sidebarWeb': true},
        'recentlyAdded': {'sidebarWeb': true},
      };
    } else {
      status = 404;
      out = {'message': 'not found'};
    }
    res.statusCode = status;
    if (status != 204) {
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode(out));
    }
    await res.close();
  }

  Map<String, dynamic> _album(Map<String, dynamic> a) => {
        'id': a['id'], 'albumName': a['albumName'], 'description': a['description'], 'ownerId': a['ownerId'],
        'assetCount': (a['assetIds'] as List).length, 'shared': (a['albumUsers'] as List?)?.isNotEmpty ?? false,
        'albumUsers': a['albumUsers'] ?? [], 'order': a['order'],
        'isActivityEnabled': false, 'albumThumbnailAssetId': (a['assetIds'] as List).isEmpty ? null : a['assetIds'][0],
        'createdAt': '2026-10-09T00:00:00.000Z', 'updatedAt': '2026-10-09T00:00:00.000Z',
        'startDate': '2026-10-09T00:00:00.000Z', 'endDate': '2026-10-09T00:00:00.000Z', 'hasSharedLink': false,
      };
}
