// Minimal Immich API client (targets server v3.3; falls back to older endpoints for v3.1+).
// Only the endpoints the app uses; see open-api/immich-openapi-specs.json upstream.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'i18n.dart';

class ApiException implements Exception {
  final int? status;
  final String message;
  ApiException(this.message, [this.status]);
  @override
  String toString() => status == null ? message : '$message (HTTP $status)';
}

/// Credentials for one server. Either [accessToken] (from password login) or [apiKey].
class Credentials {
  final String serverUrl;
  final String? accessToken;
  final String? apiKey;

  const Credentials({required this.serverUrl, this.accessToken, this.apiKey});

  Map<String, String> get headers => {
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        'x-api-key': ?apiKey,
      };

  Map<String, dynamic> toJson() =>
      {'serverUrl': serverUrl, 'accessToken': accessToken, 'apiKey': apiKey};

  factory Credentials.fromJson(Map<String, dynamic> j) => Credentials(
        serverUrl: j['serverUrl'],
        accessToken: j['accessToken'],
        apiKey: j['apiKey'],
      );
}

/// One asset as shown in grids. Built from either timeline buckets or search results.
class AssetRef {
  final String id;
  final bool isImage;
  final double ratio;
  final bool isFavorite;
  final int? durationMs;
  /// Capture date in the photo's own timezone (used for day grouping).
  final DateTime? localDate;
  /// Equirectangular (360° / 180° photo sphere or 360° video), shown in a panorama viewer.
  final bool isPanorama;
  /// The short video of a live / motion photo.
  final String? livePhotoVideoId;

  const AssetRef({
    required this.id,
    required this.isImage,
    this.ratio = 1,
    this.isFavorite = false,
    this.durationMs,
    this.localDate,
    this.isPanorama = false,
    this.livePhotoVideoId,
  });

  AssetRef copyWith({bool? isFavorite}) => AssetRef(
        id: id,
        isImage: isImage,
        ratio: ratio,
        isFavorite: isFavorite ?? this.isFavorite,
        durationMs: durationMs,
        localDate: localDate,
        isPanorama: isPanorama,
        livePhotoVideoId: livePhotoVideoId,
      );

  /// Web: projectionType EQUIRECTANGULAR, or an Insta360 .insp file.
  static bool panoramaFrom(String? projectionType, [String? path]) =>
      projectionType?.toUpperCase() == 'EQUIRECTANGULAR' || (path?.toLowerCase().endsWith('.insp') ?? false);

  factory AssetRef.fromAssetJson(Map<String, dynamic> j) {
    final w = (j['width'] as num?)?.toDouble();
    final h = (j['height'] as num?)?.toDouble();
    return AssetRef(
      id: j['id'],
      isImage: j['type'] == 'IMAGE',
      ratio: (w != null && h != null && h > 0) ? w / h : 1,
      isFavorite: j['isFavorite'] ?? false,
      durationMs: (j['duration'] as num?)?.toInt(),
      localDate: DateTime.tryParse(j['localDateTime'] ?? ''),
      isPanorama: panoramaFrom(j['exifInfo']?['projectionType'] as String?, j['originalPath'] as String?),
      livePhotoVideoId: j['type'] == 'IMAGE' ? j['livePhotoVideoId'] as String? : null,
    );
  }
}

class TimeBucket {
  final String timeBucket; // YYYY-MM-DD
  final int count;
  const TimeBucket(this.timeBucket, this.count);
}

/// Filters shared by /timeline/buckets and /timeline/bucket.
/// Mirrors the `options` each web route passes to its timeline.
class TimelineQuery {
  final String? albumId;
  final String? personId;
  final String? userId; // partner timeline
  final bool? isFavorite;
  final bool? isTrashed;
  final String? visibility;
  final bool byUploadDate; // "recently added" orders by createdAt
  final bool? withPartners;
  /// Map area as "west,south,east,north".
  final String? bbox;
  final String order; // desc (newest first) | asc
  final String? tagId;

  const TimelineQuery({
    this.albumId,
    this.personId,
    this.userId,
    this.isFavorite,
    this.isTrashed,
    this.visibility = 'timeline',
    this.byUploadDate = false,
    this.withPartners,
    this.bbox,
    this.order = 'desc',
    this.tagId,
  });

  // Web /photos and /recently-added include partners shown "in timeline".
  static const photos = TimelineQuery(withPartners: true);
  static const favorites = TimelineQuery(isFavorite: true, visibility: null);
  static const archive = TimelineQuery(visibility: 'archive');
  static const trash = TimelineQuery(isTrashed: true, visibility: null);
  static const locked = TimelineQuery(visibility: 'locked');
  static const recent = TimelineQuery(byUploadDate: true, withPartners: true);
  factory TimelineQuery.album(String id, {String order = 'desc'}) =>
      TimelineQuery(albumId: id, visibility: null, order: order);

  Map<String, String?> get params => {
        'albumId': albumId,
        'personId': personId,
        'userId': userId,
        'isFavorite': isFavorite?.toString(),
        'isTrashed': isTrashed?.toString(),
        'visibility': visibility,
        'orderBy': byUploadDate ? 'createdAt' : null,
        'withPartners': withPartners?.toString(),
        'bbox': bbox,
        'tagId': tagId,
        'order': order,
      };
}

class Partner {
  final String id;
  final String name;
  final String email;
  final bool inTimeline;
  Partner.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        name = j['name'] ?? '',
        email = j['email'] ?? '',
        inTimeline = j['inTimeline'] ?? false;
}

/// A detected or manually tagged face on an asset (GET /faces?id=assetId).
class AssetFace {
  final String id;
  final Person? person;
  final int imageWidth, imageHeight;
  final int x1, y1, x2, y2;
  const AssetFace({
    required this.id,
    required this.person,
    required this.imageWidth,
    required this.imageHeight,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });

  AssetFace.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        person = j['person'] == null ? null : Person.fromJson(j['person'] as Map<String, dynamic>),
        imageWidth = (j['imageWidth'] as num?)?.toInt() ?? 0,
        imageHeight = (j['imageHeight'] as num?)?.toInt() ?? 0,
        x1 = (j['boundingBoxX1'] as num).toInt(),
        y1 = (j['boundingBoxY1'] as num).toInt(),
        x2 = (j['boundingBoxX2'] as num).toInt(),
        y2 = (j['boundingBoxY2'] as num).toInt();

  /// The box as fractions (0..1) of the image, which is how the viewer draws it.
  ({double left, double top, double width, double height}) get rel {
    final w = imageWidth > 0 ? imageWidth : 1, h = imageHeight > 0 ? imageHeight : 1;
    return (left: x1 / w, top: y1 / h, width: (x2 - x1) / w, height: (y2 - y1) / h);
  }
}

class MapMarker {
  final String id;
  final double lat;
  final double lon;
  const MapMarker(this.id, this.lat, this.lon);
}

class DuplicateGroup {
  final String id;
  final List<Map<String, dynamic>> assets;
  final Set<String> suggestedKeep;
  DuplicateGroup.fromJson(Map<String, dynamic> j)
      : id = j['duplicateId'],
        assets = (j['assets'] as List).cast<Map<String, dynamic>>(),
        suggestedKeep = ((j['suggestedKeepAssetIds'] as List?) ?? const []).cast<String>().toSet();
}

class ServerStorage {
  final String used;
  final String size;
  final double percent;
  ServerStorage.fromJson(Map<String, dynamic> j)
      : used = j['diskUse'] ?? '',
        size = j['diskSize'] ?? '',
        percent = (j['diskUsagePercentage'] as num?)?.toDouble() ?? 0;
}

class Person {
  final String id;
  final String name;
  final DateTime? birthDate;
  final bool isHidden;
  final bool isFavorite;
  final String? updatedAt;
  /// v3.3 shared people: users I gave access to / who gave me access (UserResponseDto + role).
  final List<Map<String, dynamic>> sharedWith;
  final List<Map<String, dynamic>> sharedBy;
  /// The same person in other users' libraries: {name, birthDate, role, sharedById}.
  final List<Map<String, dynamic>> otherPeople;

  Person.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        name = j['name'] ?? '',
        birthDate = DateTime.tryParse(j['birthDate'] ?? ''),
        isHidden = j['isHidden'] ?? false,
        isFavorite = j['isFavorite'] ?? false,
        updatedAt = j['updatedAt'],
        sharedWith = ((j['sharedWith'] as List?) ?? const []).cast<Map<String, dynamic>>(),
        sharedBy = ((j['sharedBy'] as List?) ?? const []).cast<Map<String, dynamic>>(),
        otherPeople = ((j['otherPeople'] as List?) ?? const []).cast<Map<String, dynamic>>();

  /// Someone else also has this person (web: PersonIndicator "Shared with me").
  bool get isShared => otherPeople.isNotEmpty;

  /// Names other users gave this person (web: "aka").
  List<String> get otherNames => {
        for (final o in otherPeople)
          if ((o['name'] as String? ?? '').isNotEmpty && o['name'] != name) o['name'] as String,
      }.toList();
}

/// A city with one representative asset (from /search/cities or /search/explore).
class Place {
  final String city;
  final String? country;
  final String assetId;
  const Place(this.city, this.country, this.assetId);
}

class Album {
  final String id;
  final String name;
  final String description;
  final String ownerId;
  final String order; // asc | desc
  final bool isActivityEnabled;
  /// [{role, user: {id, name, email}}]
  final List<Map<String, dynamic>> albumUsers;
  final Map<String, dynamic> raw;
  final String? thumbnailAssetId;
  final int assetCount;
  final bool shared;
  final DateTime? startDate;
  final DateTime? endDate;

  Album.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        name = j['albumName'] ?? '',
        description = j['description'] ?? '',
        ownerId = j['ownerId'] ?? j['owner']?['id'] ?? '',
        order = j['order'] ?? 'desc',
        isActivityEnabled = j['isActivityEnabled'] ?? false,
        albumUsers = ((j['albumUsers'] as List?) ?? const []).cast<Map<String, dynamic>>(),
        raw = j,
        thumbnailAssetId = j['albumThumbnailAssetId'],
        assetCount = (j['assetCount'] as num?)?.toInt() ?? 0,
        shared = j['shared'] ?? false,
        startDate = DateTime.tryParse(j['startDate'] ?? ''),
        endDate = DateTime.tryParse(j['endDate'] ?? '');
}

/// Result of POST /assets/bulk-upload-check for one file.
class UploadCheck {
  final bool accept;
  final String? reason; // 'duplicate' | 'unsupported-format'
  final String? assetId;
  const UploadCheck(this.accept, this.reason, this.assetId);
}

/// Multipart upload that reports bytes sent and can be aborted.
class _ProgressMultipartRequest extends http.MultipartRequest with http.Abortable {
  @override
  final Future<void>? abortTrigger;
  final void Function(int sent, int total)? onProgress;
  _ProgressMultipartRequest(super.method, super.url, {this.abortTrigger, this.onProgress});

  @override
  http.ByteStream finalize() {
    final stream = super.finalize();
    if (onProgress == null) return stream;
    final total = contentLength;
    var sent = 0;
    return http.ByteStream(stream.transform(StreamTransformer.fromHandlers(
      handleData: (List<int> data, EventSink<List<int>> sink) {
        sent += data.length;
        onProgress!(sent, total);
        sink.add(data);
      },
    )));
  }
}

/// Text search modes of the web's search options (SearchTextSection).
enum SearchMode { smart, filename, description, path, ocr }

/// Everything the web's "Search options" dialog can filter on.
class SearchFilter {
  String query;
  SearchMode mode;
  Set<String> personIds;
  Set<String> tagIds;
  String? country, state, city;
  String? make, model, lensModel;
  DateTime? takenAfter, takenBefore; // whole days, local time
  String? type; // IMAGE | VIDEO | null (all)
  bool isFavorite, inArchive, notInAlbum;
  int? rating;

  SearchFilter({
    this.query = '',
    this.mode = SearchMode.smart,
    Set<String>? personIds,
    Set<String>? tagIds,
    this.country,
    this.state,
    this.city,
    this.make,
    this.model,
    this.lensModel,
    this.takenAfter,
    this.takenBefore,
    this.type,
    this.isFavorite = false,
    this.inArchive = false,
    this.notInAlbum = false,
    this.rating,
  })  : personIds = personIds ?? {},
        tagIds = tagIds ?? {};

  SearchFilter copy() => SearchFilter(
        query: query, mode: mode, personIds: {...personIds}, tagIds: {...tagIds},
        country: country, state: state, city: city, make: make, model: model, lensModel: lensModel,
        takenAfter: takenAfter, takenBefore: takenBefore, type: type, isFavorite: isFavorite,
        inArchive: inArchive, notInAlbum: notInAlbum, rating: rating,
      );

  bool get isEmpty => query.trim().isEmpty && filterCount == 0;

  /// Filters besides the text query (shown as a badge on the options button).
  int get filterCount => [
        personIds.isNotEmpty, tagIds.isNotEmpty, country != null || state != null || city != null,
        make != null || model != null || lensModel != null, takenAfter != null || takenBefore != null,
        type != null, isFavorite, inArchive, notInAlbum, rating != null,
      ].where((x) => x).length;

  /// Like the web: a text query in "context" mode uses CLIP search, all else is metadata.
  bool get isSmart => mode == SearchMode.smart && query.trim().isNotEmpty;

  static String _day(DateTime d, {bool end = false}) {
    final local = end ? DateTime(d.year, d.month, d.day, 23, 59, 59, 999) : DateTime(d.year, d.month, d.day);
    return local.toUtc().toIso8601String();
  }

  Map<String, dynamic> toJson() {
    final q = query.trim();
    return {
      if (q.isNotEmpty) ...switch (mode) {
        SearchMode.smart => {'query': q},
        SearchMode.filename => {'originalFileName': q},
        SearchMode.description => {'description': q},
        SearchMode.path => {'originalPath': q},
        SearchMode.ocr => {'ocr': q},
      },
      if (personIds.isNotEmpty) 'personIds': personIds.toList(),
      if (tagIds.isNotEmpty) 'tagIds': tagIds.toList(),
      'country': ?country,
      'state': ?state,
      'city': ?city,
      'make': ?make,
      'model': ?model,
      'lensModel': ?lensModel,
      if (takenAfter != null) 'takenAfter': _day(takenAfter!),
      if (takenBefore != null) 'takenBefore': _day(takenBefore!, end: true),
      'type': ?type,
      if (isFavorite) 'isFavorite': true,
      if (notInAlbum) 'isNotInAlbum': true,
      'visibility': inArchive ? 'archive' : 'timeline',
      'rating': ?rating,
    };
  }
}

class SearchPage {
  final List<AssetRef> assets;
  final int? nextPage;
  const SearchPage(this.assets, this.nextPage);
}

class ImmichApi {
  /// Changes only when the API key the app signs in with is rotated.
  Credentials creds;
  /// Persists [creds] after such a change (set by the app; tests leave it null).
  void Function(Credentials creds)? onCredentialsChanged;
  final http.Client _client = _newClient();

  // Without limits a dead connection (after suspend, a Wi-Fi switch) waits forever,
  // and a stuck folder-backup upload would block every later backup run.
  static Duration connectTimeout = const Duration(seconds: 15);
  /// For JSON calls: the whole response.
  static Duration requestTimeout = const Duration(seconds: 90);
  /// For downloads / uploads: how long the transfer may stall (no bytes moving).
  static Duration stallTimeout = const Duration(seconds: 60);

  static http.Client _newClient() => IOClient(HttpClient()..connectionTimeout = connectTimeout);

  /// Frees the connections (after logout).
  void close() => _client.close();

  ImmichApi(this.creds);

  String get base => '${normalizeServerUrl(creds.serverUrl)}/api';
  Map<String, String> get headers => creds.headers;

  /// Accepts "photos.example.com", "https://host:2283/", "https://host/api" etc.
  static String normalizeServerUrl(String input) {
    var url = input.trim();
    if (!url.startsWith(RegExp(r'https?://'))) url = 'https://$url';
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.endsWith('/api')) url = url.substring(0, url.length - 4);
    return url;
  }

  static Future<Credentials> login(String serverUrl, String email, String password) async {
    final server = normalizeServerUrl(serverUrl);
    final res = await _send(() => http.post(
          Uri.parse('$server/api/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email.trim(), 'password': password}),
        ));
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return Credentials(serverUrl: server, accessToken: j['accessToken']);
  }

  Uri _uri(String path, [Map<String, String?>? query]) {
    final q = <String, String>{};
    query?.forEach((k, v) {
      if (v != null) q[k] = v;
    });
    return Uri.parse('$base$path').replace(queryParameters: q.isEmpty ? null : q);
  }

  static Future<http.Response> _send(Future<http.Response> Function() req) async {
    final http.Response res;
    try {
      res = await req().timeout(requestTimeout);
    } on TimeoutException {
      throw ApiException(t('linux_err_timeout'));
    } on SocketException catch (e) {
      throw ApiException(t('linux_err_unreachable', {'error': e.message}));
    } on HandshakeException {
      throw ApiException(t('linux_err_tls'));
    } on http.ClientException catch (e) {
      throw ApiException(t('linux_err_network', {'error': e.message}));
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return res;
    String msg = t('linux_err_server');
    try {
      final j = jsonDecode(res.body);
      if (j is Map && j['message'] != null) {
        msg = j['message'] is List ? (j['message'] as List).join(', ') : '${j['message']}';
      }
    } catch (_) {}
    if (res.statusCode == 401) msg = t('linux_err_unauthorized');
    throw ApiException(msg, res.statusCode);
  }

  Future<dynamic> _getJson(String path, [Map<String, String?>? query]) async {
    final res = await _send(() => _client.get(_uri(path, query), headers: headers));
    return jsonDecode(res.body);
  }

  /// Calls [current]; if the server doesn't know that endpoint (404, older server) calls [older].
  Future<T> _orOlder<T>(Future<T> Function() current, Future<T> Function() older) async {
    try {
      return await current();
    } on ApiException catch (e) {
      if (e.status != 404) rethrow;
      return older();
    }
  }

  Future<dynamic> _postJson(String path, Map<String, dynamic> body) async {
    final res = await _send(() => _client.post(
          _uri(path),
          headers: {...headers, 'Content-Type': 'application/json'},
          body: jsonEncode(body),
        ));
    return jsonDecode(res.body);
  }

  Future<dynamic> _sendJson(String method, String path, [Object? body]) async {
    final req = http.Request(method, _uri(path))..headers.addAll(headers);
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final res = await _send(() async => http.Response.fromStream(await _client.send(req)));
    return res.body.isEmpty ? null : jsonDecode(res.body);
  }

  // ---- Editing (web: asset-utils / trash / album actions) ----

  Future<void> updateAssets(List<String> ids, {bool? isFavorite, String? visibility}) =>
      _sendJson('PUT', '/assets', {
        'ids': ids,
        'isFavorite': ?isFavorite,
        'visibility': ?visibility,
      });

  /// Moves to the bin, or deletes permanently with [force].
  Future<void> deleteAssets(List<String> ids, {bool force = false}) =>
      _sendJson('DELETE', '/assets', {'ids': ids, 'force': force});

  Future<void> restoreAssets(List<String> ids) =>
      _sendJson('POST', '/trash/restore/assets', {'ids': ids});

  Future<void> restoreAllTrash() => _sendJson('POST', '/trash/restore');

  Future<void> emptyTrash() => _sendJson('POST', '/trash/empty');

  Future<Album> createAlbum(String name, List<String> assetIds) async =>
      Album.fromJson(await _sendJson('POST', '/albums', {'albumName': name, 'assetIds': assetIds}));

  /// Returns how many were newly added (the rest were already in the album).
  Future<int> addToAlbum(String albumId, List<String> ids) async {
    final list = await _sendJson('PUT', '/albums/$albumId/assets', {'ids': ids}) as List;
    return list.where((r) => r['success'] == true).length;
  }

  Future<Album> album(String id) async => Album.fromJson(await _getJson('/albums/$id'));

  Future<Album> updateAlbum(String id,
          {String? name, String? description, String? thumbnailAssetId, String? order, bool? isActivityEnabled}) async =>
      Album.fromJson(await _sendJson('PATCH', '/albums/$id', {
        'albumName': ?name,
        'description': ?description,
        'albumThumbnailAssetId': ?thumbnailAssetId,
        'order': ?order,
        'isActivityEnabled': ?isActivityEnabled,
      }));

  Future<void> deleteAlbum(String id) => _sendJson('DELETE', '/albums/$id');

  /// role: editor | viewer
  Future<void> addAlbumUsers(String id, Map<String, String> roleByUserId) =>
      _sendJson('PUT', '/albums/$id/users', {
        'albumUsers': [
          for (final e in roleByUserId.entries) {'userId': e.key, 'role': e.value},
        ],
      });
  Future<void> updateAlbumUser(String id, String userId, String role) =>
      _sendJson('PUT', '/albums/$id/user/$userId', {'role': role});
  Future<void> removeAlbumUser(String id, String userId) =>
      _sendJson('DELETE', '/albums/$id/user/$userId');

  // ---- Shared links ----

  Future<List<Map<String, dynamic>>> sharedLinks() async =>
      (await _getJson('/shared-links') as List).cast<Map<String, dynamic>>();
  Future<Map<String, dynamic>> createSharedLink({
    String? albumId,
    List<String>? assetIds,
    String? description,
    String? password,
    DateTime? expiresAt,
    bool allowDownload = true,
    bool allowUpload = false,
    bool showMetadata = true,
    String? slug,
  }) async =>
      await _sendJson('POST', '/shared-links', {
        'type': albumId != null ? 'ALBUM' : 'INDIVIDUAL',
        'albumId': ?albumId,
        'assetIds': ?assetIds,
        'description': ?description,
        'password': ?password,
        'expiresAt': ?expiresAt?.toUtc().toIso8601String(),
        'allowDownload': allowDownload,
        'allowUpload': allowUpload,
        'showMetadata': showMetadata,
        'slug': ?slug,
      });
  Future<Map<String, dynamic>> updateSharedLink(String id, Map<String, dynamic> changes) async =>
      await _sendJson('PATCH', '/shared-links/$id', changes);
  Future<void> deleteSharedLink(String id) => _sendJson('DELETE', '/shared-links/$id');

  /// Public URL of a shared link, like the web's copy button.
  String sharedLinkUrl(Map<String, dynamic> link) {
    final server = normalizeServerUrl(creds.serverUrl);
    final slug = link['slug'] as String?;
    return slug != null && slug.isNotEmpty ? '$server/s/$slug' : '$server/share/${link['key']}';
  }

  Future<void> removeFromAlbum(String albumId, List<String> ids) =>
      _sendJson('DELETE', '/albums/$albumId/assets', {'ids': ids});

  /// Downloads [ids] as one or more zip files (the server splits big selections).
  Future<List<File>> downloadZip(List<String> ids, Directory dir,
      {void Function(int done, int total)? onProgress, String? albumId}) async {
    final info = await _sendJson(
        'POST', '/download/info', albumId != null ? {'albumId': albumId} : {'assetIds': ids});
    final archives = (info['archives'] as List).cast<Map<String, dynamic>>();
    final total = (info['totalSize'] as num?)?.toInt() ?? 0;
    final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-').substring(0, 19);
    final files = <File>[];
    var done = 0;
    for (var i = 0; i < archives.length; i++) {
      final req = http.Request('POST', _uri('/download/archive'))
        ..headers.addAll({...headers, 'Content-Type': 'application/json'})
        ..body = jsonEncode({'assetIds': archives[i]['assetIds']});
      final res = await _sendStream(req);
      final name = archives.length == 1 ? 'immich-$stamp.zip' : 'immich-$stamp-${i + 1}.zip';
      final f = File('${dir.path}/$name');
      await _saveStream(res, f, (n) {
        done += n;
        onProgress?.call(done, total);
      });
      files.add(f);
    }
    return files;
  }

  // ---- Single-asset edits (viewer info panel) ----

  /// description, dateTimeOriginal (ISO with offset), latitude/longitude, rating (null clears).
  Future<Map<String, dynamic>> updateAsset(String id, Map<String, dynamic> changes) async =>
      await _sendJson('PUT', '/assets/$id', changes);

  // ---- Tags ----

  Future<List<Map<String, dynamic>>> tags() async =>
      (await _getJson('/tags') as List).cast<Map<String, dynamic>>();
  /// Creates missing tags for slash-separated paths like "Travel/Greece"; returns them.
  Future<List<Map<String, dynamic>>> upsertTags(List<String> names) async =>
      (await _sendJson('PUT', '/tags', {'tags': names}) as List).cast<Map<String, dynamic>>();
  Future<void> tagAssets(List<String> tagIds, List<String> assetIds) =>
      _sendJson('PUT', '/tags/assets', {'tagIds': tagIds, 'assetIds': assetIds});
  Future<void> untagAssets(String tagId, List<String> assetIds) =>
      _sendJson('DELETE', '/tags/$tagId/assets', {'ids': assetIds});
  Future<void> deleteTag(String id) => _sendJson('DELETE', '/tags/$id');

  // ---- Stacks ----

  /// The first id becomes the primary asset.
  Future<Map<String, dynamic>> createStack(List<String> assetIds) async =>
      await _sendJson('POST', '/stacks', {'assetIds': assetIds});
  Future<Map<String, dynamic>> stack(String id) async => await _getJson('/stacks/$id');
  Future<void> deleteStacks(List<String> ids) => _sendJson('DELETE', '/stacks', {'ids': ids});

  // ---- Memories ----

  /// "On this day" memories for [forDate] (web: searchMemories({ for: 'yyyy-MM-dd' })).
  Future<List<Map<String, dynamic>>> memories({DateTime? forDate}) async {
    final d = forDate ?? DateTime.now();
    final day = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    return (await _getJson('/memories', {'for': day}) as List).cast<Map<String, dynamic>>();
  }
  /// All memories, newest first (v3.2+ memories page). [isUpcoming]: false hides ones not shown yet.
  Future<List<Map<String, dynamic>>> searchMemories(
          {int page = 1, int size = 50, bool? isSaved, bool? isUpcoming}) async =>
      (await _getJson('/memories', {
        'order': 'desc',
        'page': '$page',
        'size': '$size',
        'isSaved': isSaved?.toString(),
        'isUpcoming': isUpcoming?.toString(),
      }) as List)
          .cast<Map<String, dynamic>>();
  /// Number of memories matching the same filters.
  Future<int> memoryCount({bool? isSaved, bool? isUpcoming}) async =>
      ((await _getJson('/memories/statistics', {
        'order': 'desc',
        'isSaved': isSaved?.toString(),
        'isUpcoming': isUpcoming?.toString(),
      }))['total'] as num)
          .toInt();
  Future<void> updateMemory(String id, Map<String, dynamic> changes) =>
      _sendJson('PUT', '/memories/$id', changes);

  // ---- Folders ----

  Future<List<String>> folderPaths() async =>
      (await _getJson('/view/folder/unique-paths') as List).cast<String>();
  Future<List<AssetRef>> folderAssets(String path) async =>
      [for (final a in (await _getJson('/view/folder', {'path': path}) as List)) AssetRef.fromAssetJson(a)];

  // ---- People management ----

  /// [userId] (v3.3): only change that user's record of a shared person ("Only change for me").
  Future<Person> updatePerson(String id,
          {String? name,
          bool? isHidden,
          bool? isFavorite,
          String? birthDate,
          bool clearBirthDate = false,
          String? userId}) async =>
      Person.fromJson(await _sendJson('PUT', '/people/$id', {
        'name': ?name,
        'isHidden': ?isHidden,
        'isFavorite': ?isFavorite,
        if (birthDate != null || clearBirthDate) 'birthDate': birthDate,
        'userId': ?userId,
      }));
  /// Merges [otherIds] into person [id].
  // ---- Faces (web: PersonSidePanel / FaceEditor) ----

  Future<List<AssetFace>> faces(String assetId) async =>
      ((await _getJson('/faces', {'id': assetId})) as List)
          .map((e) => AssetFace.fromJson(e as Map<String, dynamic>))
          .toList();

  /// Tags a face by hand. The box is given as fractions of the image; it is sent
  /// in a virtual [_faceSpace]-pixel space with the image's aspect ratio, which the
  /// server scales to the real image (the web uses the preview's pixel size).
  Future<void> createFace(String assetId, String personId, double imageRatio,
      {required double left, required double top, required double width, required double height}) {
    const space = 4000;
    final iw = imageRatio >= 1 ? space : (space * imageRatio).round();
    final ih = imageRatio >= 1 ? (space / imageRatio).round() : space;
    return _sendJson('POST', '/faces', {
      'assetId': assetId,
      'personId': personId,
      'imageWidth': iw,
      'imageHeight': ih,
      'x': (left * iw).floor(),
      'y': (top * ih).floor(),
      'width': (width * iw).floor(),
      'height': (height * ih).floor(),
    });
  }

  /// Moves face [faceId] to person [personId] (PUT /faces/{personId}, body {id: faceId}).
  Future<void> reassignFace(String faceId, String personId) =>
      _sendJson('PUT', '/faces/$personId', {'id': faceId});

  Future<void> deleteFace(String faceId) => _sendJson('DELETE', '/faces/$faceId', {'force': false});

  Future<Person> createPerson({String? name}) async =>
      Person.fromJson(await _sendJson('POST', '/people', {if (name != null && name.isNotEmpty) 'name': name}));

  /// Merges [otherIds] into [id] (POST /people/merge with [id] first; servers before v3.3 only
  /// have POST /people/{id}/merge).
  Future<void> mergePeople(String id, List<String> otherIds) => _orOlder(
      () => _sendJson('POST', '/people/merge', {'ids': [id, ...otherIds]}),
      () => _sendJson('POST', '/people/$id/merge', {'ids': otherIds}));

  // ---- Activity (comments & likes in shared albums) ----

  Future<List<Map<String, dynamic>>> activities(String albumId, {String? assetId}) async =>
      (await _getJson('/activities', {'albumId': albumId, 'assetId': assetId}) as List)
          .cast<Map<String, dynamic>>();
  /// type: comment | like
  Future<Map<String, dynamic>> addActivity(String albumId, String type, {String? assetId, String? comment}) async =>
      await _sendJson('POST', '/activities', {
        'albumId': albumId,
        'type': type,
        'assetId': ?assetId,
        'comment': ?comment,
      });
  Future<void> deleteActivity(String id) => _sendJson('DELETE', '/activities/$id');

  // ---- Utilities ----

  Future<List<DuplicateGroup>> duplicates() async {
    final list = await _getJson('/duplicates') as List;
    return list.map((e) => DuplicateGroup.fromJson(e)).toList();
  }

  /// Keeps [keep] and moves the rest of the group to the bin (web: "keep").
  Future<void> resolveDuplicate(String groupId, List<String> keep, List<String> trash) =>
      _sendJson('POST', '/duplicates/resolve', {
        'groups': [
          {'duplicateId': groupId, 'keepAssetIds': keep, 'trashAssetIds': trash},
        ],
      });

  /// Marks the group as "not duplicates" and keeps everything.
  Future<void> dismissDuplicate(String groupId) => _sendJson('DELETE', '/duplicates/$groupId');

  Future<List<Map<String, dynamic>>> largeAssets({int size = 250}) async {
    final res = await _send(() => _client.post(
        _uri('/search/large-assets', {'size': '$size', 'withExif': 'true'}),
        headers: headers));
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }

  // ---- Locked folder (PIN) ----

  Future<Map<String, dynamic>> authStatus() async => await _getJson('/auth/status');
  Future<void> setupPinCode(String pin) => _sendJson('POST', '/auth/pin-code', {'pinCode': pin});
  Future<void> changePinCode(String oldPin, String newPin) =>
      _sendJson('PUT', '/auth/pin-code', {'pinCode': oldPin, 'newPinCode': newPin});
  Future<void> unlockSession(String pin) =>
      _sendJson('POST', '/auth/session/unlock', {'pinCode': pin});
  Future<void> lockSession() => _sendJson('POST', '/auth/session/lock');

  // ---- Account ----

  Future<Map<String, dynamic>> updateMe({String? name, String? email}) async =>
      await _sendJson('PUT', '/users/me', {'name': ?name, 'email': ?email});

  Future<void> changePassword(String current, String next, {bool logoutOthers = false}) =>
      _sendJson('POST', '/auth/change-password',
          {'password': current, 'newPassword': next, 'invalidateSessions': logoutOthers});

  Future<List<Map<String, dynamic>>> apiKeys() async =>
      (await _getJson('/api-keys') as List).cast<Map<String, dynamic>>();

  /// Returns the secret, which the server shows only once.
  Future<String> createApiKey(String name) async =>
      (await _sendJson('POST', '/api-keys', {'name': name, 'permissions': ['all']}))['secret'];

  Future<void> deleteApiKey(String id) => _sendJson('DELETE', '/api-keys/$id');

  /// New secret for a key (Immich v3.2+); the old one stops working at once. Rotating the key
  /// this app signs in with switches the app to the new secret. Returns (secret, wasOwnKey).
  Future<(String, bool)> rotateApiKey(String id) async {
    final own = creds.apiKey != null && (await _getJson('/api-keys/me'))['id'] == id;
    final secret = (await _postJson('/api-keys/$id/rotate', {}))['secret'] as String;
    if (own) {
      creds = Credentials(serverUrl: creds.serverUrl, apiKey: secret);
      onCredentialsChanged?.call(creds);
    }
    return (secret, own);
  }

  Future<List<Map<String, dynamic>>> sessions() async =>
      (await _getJson('/sessions') as List).cast<Map<String, dynamic>>();
  Future<void> deleteSession(String id) => _sendJson('DELETE', '/sessions/$id');
  Future<void> deleteOtherSessions() => _sendJson('DELETE', '/sessions');

  /// Users this account can share with (for partner sharing).
  Future<List<Map<String, dynamic>>> users() async =>
      (await _getJson('/users') as List).cast<Map<String, dynamic>>();
  // ---- Shared people (v3.3: access to my people for users in my cluster group) ----

  /// GET /people/users: {personId, sharedById, sharedWithId, sharedBy, sharedWith, role}.
  /// [direction]: 'shared-by' = I gave access, 'shared-with' = I was given access.
  Future<List<Map<String, dynamic>>> personUsers({String? personId, String? direction}) async =>
      (await _getJson('/people/users', {'personId': personId, 'direction': direction}) as List)
          .cast<Map<String, dynamic>>();
  /// Gives [userIds] access to [personIds], or to all my people with [everyone].
  Future<void> sharePeople(List<String> userIds, {List<String> personIds = const [], bool everyone = false}) =>
      _sendJson('PUT', '/people/users', {
        'sharedWithIds': userIds,
        'role': 'admin',
        if (everyone) 'type': 'everyone' else 'personIds': personIds,
      });
  /// Removes access: one (personId, sharedWithId) pair per entry.
  Future<void> unsharePeople(List<(String, String)> pairs) => _sendJson('DELETE', '/people/users',
      [for (final (personId, userId) in pairs) {'personId': personId, 'sharedWithId': userId}]);

  /// The other members of my people cluster group ([] on servers before v3.2).
  Future<List<Map<String, dynamic>>> clusterGroupOthers() async {
    final me = await this.me();
    final groupId = me['clusterGroupId'] as String?;
    if (groupId == null) return [];
    return [for (final u in await clusterGroupUsers(groupId)) if (u['id'] != me['id']) u];
  }

  // ---- People cluster group (v3.2+: faces are clustered across the group's users) ----

  /// Members of cluster group [groupId] (UserResponseDto maps).
  Future<List<Map<String, dynamic>>> clusterGroupUsers(String groupId) async =>
      (await _getJson('/cluster-groups/$groupId/users') as List).cast<Map<String, dynamic>>();
  /// Invitations sent from group [groupId]: {id, clusterGroupId, userId, createdAt}.
  Future<List<Map<String, dynamic>>> clusterGroupSentRequests(String groupId) async =>
      (await _getJson('/cluster-groups/$groupId/requests') as List).cast<Map<String, dynamic>>();
  /// Invitations the current user received to join other groups.
  Future<List<Map<String, dynamic>>> clusterGroupReceivedRequests() async =>
      (await _getJson('/cluster-groups/requests') as List).cast<Map<String, dynamic>>();
  Future<void> inviteToClusterGroup(String groupId, String userId) =>
      _sendJson('PUT', '/cluster-groups/$groupId/requests', {'userId': userId});
  Future<void> acceptClusterGroupRequest(String requestId) =>
      _sendJson('POST', '/cluster-groups/requests/$requestId/accept');
  /// Declines a received invitation or cancels a sent one.
  Future<void> deleteClusterGroupRequest(String requestId) =>
      _sendJson('DELETE', '/cluster-groups/requests/$requestId');
  Future<void> leaveClusterGroup(String groupId) => _sendJson('POST', '/cluster-groups/$groupId/leave');
  Future<void> regenerateClusterGroupPeople(String groupId) =>
      _sendJson('POST', '/cluster-groups/$groupId/regenerate-people');

  Future<void> addPartner(String userId) =>
      _sendJson('POST', '/partners', {'sharedWithId': userId});
  Future<void> removePartner(String userId) => _sendJson('DELETE', '/partners/$userId');
  Future<void> setPartnerInTimeline(String userId, bool v) =>
      _sendJson('PUT', '/partners/$userId', {'inTimeline': v});

  // ---- Administration ----

  Future<List<Map<String, dynamic>>> adminUsers() async =>
      (await _getJson('/admin/users') as List).cast<Map<String, dynamic>>();
  Future<void> createUser({
    required String name,
    required String email,
    required String password,
    bool isAdmin = false,
    bool shouldChangePassword = true,
  }) =>
      _sendJson('POST', '/admin/users', {
        'name': name,
        'email': email,
        'password': password,
        'isAdmin': isAdmin,
        'shouldChangePassword': shouldChangePassword,
      });
  Future<Map<String, dynamic>> adminUser(String id) async => await _getJson('/admin/users/$id');
  Future<Map<String, dynamic>> adminUserStatistics(String id) async =>
      await _getJson('/admin/users/$id/statistics');
  Future<List<Map<String, dynamic>>> adminUserSessions(String id) async =>
      (await _getJson('/admin/users/$id/sessions') as List).cast<Map<String, dynamic>>();
  Future<Map<String, dynamic>> adminUserPreferences(String id) async =>
      await _getJson('/admin/users/$id/preferences');

  /// Fields are sent as given, so a null value clears it (e.g. pinCode, quotaSizeInBytes).
  Future<Map<String, dynamic>> updateUserAdmin(String id, Map<String, dynamic> update) async =>
      await _sendJson('PUT', '/admin/users/$id', update);

  Future<void> deleteUser(String id, {bool force = false}) =>
      _sendJson('DELETE', '/admin/users/$id', {'force': force});
  Future<void> restoreUser(String id) => _sendJson('POST', '/admin/users/$id/restore');

  Future<Map<String, dynamic>> serverStatistics() async => await _getJson('/server/statistics');

  Future<List<Map<String, dynamic>>> queues() async =>
      (await _getJson('/queues') as List).cast<Map<String, dynamic>>();

  /// command: start | pause | resume | empty | clear-failed (web still uses this endpoint).
  Future<void> queueCommand(String name, String command, {bool? force}) =>
      _sendJson('PUT', '/jobs/$name', {'command': command, 'force': ?force});

  // ---- Server & user settings ----

  // /admin/config since v3.3, /system-config before (same body).
  Future<Map<String, dynamic>> systemConfig() async =>
      await _orOlder<dynamic>(() => _getJson('/admin/config'), () => _getJson('/system-config'));
  Future<Map<String, dynamic>> systemConfigDefaults() async => await _orOlder<dynamic>(
      () => _getJson('/admin/config/defaults'), () => _getJson('/system-config/defaults'));
  Future<Map<String, dynamic>> updateSystemConfig(Map<String, dynamic> config) async => await _orOlder<dynamic>(
      () => _sendJson('PUT', '/admin/config', config), () => _sendJson('PUT', '/system-config', config));

  Future<Map<String, dynamic>> preferences() async => await _getJson('/users/me/preferences');
  Future<Map<String, dynamic>> updatePreferences(Map<String, dynamic> update) async =>
      await _sendJson('PUT', '/users/me/preferences', update);

  /// {images, videos, total} for the given filter (web: account usage statistics).
  Future<Map<String, dynamic>> assetStatistics({bool? isFavorite, bool? isTrashed, String? visibility}) async =>
      await _getJson('/assets/statistics', {
        'isFavorite': isFavorite?.toString(),
        'isTrashed': isTrashed?.toString(),
        'visibility': visibility,
      });

  Future<Map<String, dynamic>?> license() async {
    try {
      return await _getJson('/users/me/license');
    } on ApiException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  // ---- External libraries ----

  Future<List<Map<String, dynamic>>> libraries() async =>
      (await _getJson('/libraries') as List).cast<Map<String, dynamic>>();
  Future<Map<String, dynamic>> createLibrary(
          {required String ownerId, required String name, List<String> importPaths = const [], List<String> exclusionPatterns = const []}) async =>
      await _sendJson('POST', '/libraries', {
        'ownerId': ownerId,
        'name': name,
        'importPaths': importPaths,
        'exclusionPatterns': exclusionPatterns,
      });
  Future<void> updateLibrary(String id,
          {String? name, List<String>? importPaths, List<String>? exclusionPatterns}) =>
      _sendJson('PUT', '/libraries/$id', {
        'name': ?name,
        'importPaths': ?importPaths,
        'exclusionPatterns': ?exclusionPatterns,
      });
  Future<void> deleteLibrary(String id) => _sendJson('DELETE', '/libraries/$id');
  Future<void> scanLibrary(String id) => _sendJson('POST', '/libraries/$id/scan');
  Future<Map<String, dynamic>> libraryStatistics(String id) async =>
      await _getJson('/libraries/$id/statistics');

  // ---- Maintenance ----

  Future<Map<String, dynamic>> maintenanceStatus() async =>
      await _getJson('/admin/maintenance/status');
  Future<void> setMaintenanceMode(String action) =>
      _sendJson('POST', '/admin/maintenance', {'action': action});
  Future<List<Map<String, dynamic>>> databaseBackups() async {
    final j = await _getJson('/admin/database-backups');
    final list = j is Map ? (j['backups'] as List? ?? const []) : j as List;
    return list.cast<Map<String, dynamic>>();
  }
  Future<void> deleteDatabaseBackups(List<String> names) =>
      _sendJson('DELETE', '/admin/database-backups', {'backups': names});

  Future<Map<String, dynamic>> me() async => await _getJson('/users/me');

  Future<void> logout() async {
    if (creds.accessToken == null) return;
    try {
      await _send(() => _client.post(_uri('/auth/logout'), headers: headers));
    } catch (_) {}
  }

  Future<List<TimeBucket>> timeBuckets(TimelineQuery q) async {
    final list = await _getJson('/timeline/buckets', q.params) as List;
    return list
        .map((e) => TimeBucket(e['timeBucket'], (e['count'] as num).toInt()))
        .toList();
  }

  /// The bucket response is columnar: every field is an array indexed by asset.
  Future<List<AssetRef>> timeBucket(String bucket, TimelineQuery q) async {
    final j = await _getJson('/timeline/bucket', {...q.params, 'timeBucket': bucket})
        as Map<String, dynamic>;
    final ids = (j['id'] as List).cast<String>();
    final isImage = (j['isImage'] as List);
    final ratio = (j['ratio'] as List);
    final fav = (j['isFavorite'] as List);
    final dur = (j['duration'] as List);
    final created = (j['fileCreatedAt'] as List?) ?? const [];
    final offset = (j['localOffsetHours'] as List?) ?? const [];
    final projection = (j['projectionType'] as List?) ?? const [];
    final live = (j['livePhotoVideoId'] as List?) ?? const [];
    DateTime? local(int i) {
      if (i >= created.length) return null;
      final utc = DateTime.tryParse('${created[i]}')?.toUtc();
      if (utc == null) return null;
      final h = i < offset.length ? (offset[i] as num?) ?? 0 : 0;
      // Shift into the photo's timezone, then drop the UTC flag.
      final t = utc.add(Duration(minutes: (h * 60).round()));
      return DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second);
    }
    return [
      for (var i = 0; i < ids.length; i++)
        AssetRef(
          id: ids[i],
          isImage: isImage[i] == true,
          ratio: (ratio[i] as num?)?.toDouble() ?? 1,
          isFavorite: fav[i] == true,
          durationMs: (dur[i] as num?)?.toInt(),
          localDate: local(i),
          isPanorama: i < projection.length && AssetRef.panoramaFrom(projection[i] as String?),
          livePhotoVideoId: isImage[i] == true && i < live.length ? live[i] as String? : null,
        ),
    ];
  }

  Future<Map<String, dynamic>> asset(String id) async => await _getJson('/assets/$id');

  Future<List<Album>> albums() async {
    final owned = await _getJson('/albums') as List;
    final shared = await _getJson('/albums', {'isShared': 'true'}) as List;
    final seen = <String>{};
    final all = <Album>[];
    for (final e in [...owned, ...shared]) {
      final a = Album.fromJson(e);
      if (seen.add(a.id)) all.add(a);
    }
    all.sort((a, b) => (b.endDate ?? DateTime(0)).compareTo(a.endDate ?? DateTime(0)));
    return all;
  }

  /// Albums containing [assetId].
  Future<List<Album>> albumsOf(String assetId) async {
    final list = await _getJson('/albums', {'assetId': assetId}) as List;
    return list.map((e) => Album.fromJson(e)).toList();
  }

  /// [sharedById] / [sharedWithId] (v3.3): only people that user shared with me / I shared with them.
  Future<List<Person>> people(
      {bool withHidden = false, String? sharedById, String? sharedWithId, bool? isFavorite, bool? isHidden}) async {
    final all = <Person>[];
    for (var page = 1;; page++) {
      final j = await _getJson('/people', {
        'withHidden': '$withHidden',
        'page': '$page',
        'size': '500',
        'sharedById': sharedById,
        'sharedWithId': sharedWithId,
        'isFavorite': isFavorite?.toString(),
        'isHidden': isHidden?.toString(),
      }) as Map<String, dynamic>;
      all.addAll((j['people'] as List).map((e) => Person.fromJson(e)));
      if (j['hasNextPage'] != true) break;
    }
    return all;
  }

  Future<Person> person(String id) async => Person.fromJson(await _getJson('/people/$id'));

  /// Cities from the explore endpoint, in the order the server ranks them.
  Future<List<Place>> explorePlaces() async {
    final list = await _getJson('/search/explore') as List;
    final field = list.cast<Map<String, dynamic>>().where((f) => f['fieldName'] == 'exifInfo.city');
    if (field.isEmpty) return [];
    return [
      for (final item in field.first['items'] as List)
        Place(item['value'], item['data']?['exifInfo']?['country'], item['data']['id']),
    ];
  }

  /// Every city with one asset each, sorted by name.
  Future<List<Place>> places() async {
    final list = await _getJson('/search/cities') as List;
    final places = [
      for (final a in list.cast<Map<String, dynamic>>())
        if (a['exifInfo']?['city'] != null)
          Place(a['exifInfo']['city'], a['exifInfo']['country'], a['id']),
    ];
    places.sort((a, b) => a.city.toLowerCase().compareTo(b.city.toLowerCase()));
    return places;
  }

  Future<SearchPage> citySearch(String city, {int page = 1, int size = 100}) async {
    final j = await _postJson('/search/metadata', {
      'city': city,
      'visibility': 'timeline',
      'page': page,
      'size': size,
    });
    return _searchPage(j);
  }

  String personThumbnailUrl(Person p) =>
      _uri('/people/${p.id}/thumbnail', {'updatedAt': p.updatedAt}).toString();

  /// Search with the web's "Search options" filters (smart or metadata endpoint).
  Future<SearchPage> search(SearchFilter f, {int page = 1, int size = 100}) async {
    final j = await _postJson(f.isSmart ? '/search/smart' : '/search/metadata', {
      ...f.toJson(),
      'page': page,
      'size': size,
      if (f.isSmart) 'language': i18n.code,
    });
    return _searchPage(j);
  }

  /// Values the server knows for a filter field: type is country, state, city,
  /// camera-make, camera-model or camera-lens-model.
  Future<List<String>> searchSuggestions(String type,
      {String? country, String? state, String? make, String? model}) async {
    final list = await _getJson('/search/suggestions', {
      'type': type,
      'country': country,
      'state': state,
      'make': make,
      'model': model,
    }) as List;
    return list.whereType<String>().where((s) => s.isNotEmpty).toList()..sort();
  }

  SearchPage _searchPage(dynamic j) {
    final assets = j['assets'] as Map<String, dynamic>;
    final items = (assets['items'] as List)
        .map((e) => AssetRef.fromAssetJson(e as Map<String, dynamic>))
        .toList();
    return SearchPage(items, int.tryParse('${assets['nextPage']}'));
  }

  Future<ServerStorage> serverStorage() async =>
      ServerStorage.fromJson(await _getJson('/server/storage'));

  Future<String> serverVersion() async {
    final j = await _getJson('/server/version');
    return 'v${j['major']}.${j['minor']}.${j['patch']}';
  }

  Future<int> trashDays() async => await _orOlder(
      () async => ((await _getJson('/config'))['trash']['days'] as num).toInt(),
      () async => ((await _getJson('/server/config'))['trashDays'] as num).toInt());

  /// direction: 'shared-with' = partners sharing with me, 'shared-by' = I share with them.
  Future<List<Partner>> partners(String direction) async {
    final list = await _getJson('/partners', {'direction': direction}) as List;
    return list.map((e) => Partner.fromJson(e)).toList();
  }

  Future<List<MapMarker>> mapMarkers({
    bool favoritesOnly = false,
    bool includeArchived = false,
    bool withPartners = false,
  }) async {
    final list = await _getJson('/map/markers', {
      'isFavorite': favoritesOnly ? 'true' : null,
      // Server: true = timeline + own archive, false = timeline only.
      'isArchived': '$includeArchived',
      'withPartners': '$withPartners',
    }) as List;
    return [
      for (final m in list.cast<Map<String, dynamic>>())
        if (m['lat'] != null && m['lon'] != null)
          MapMarker(m['id'], (m['lat'] as num).toDouble(), (m['lon'] as num).toDouble()),
    ];
  }

  String profileImageUrl(String userId, {String? changedAt}) =>
      _uri('/users/$userId/profile-image', {'updatedAt': changedAt}).toString();

  /// Lowercase extensions (with dot) the server accepts, e.g. {'.jpg', '.mp4'}.
  Future<Set<String>> mediaExtensions() async {
    final j = await _getJson('/server/media-types') as Map<String, dynamic>;
    return {
      for (final k in ['image', 'video'])
        for (final e in (j[k] as List? ?? [])) (e as String).toLowerCase(),
    };
  }

  /// Asks the server which checksums it already has. Keys are client-side ids.
  Future<Map<String, UploadCheck>> bulkUploadCheck(Map<String, String> sha1ById) async {
    final j = await _postJson('/assets/bulk-upload-check', {
      'assets': [
        for (final e in sha1ById.entries) {'id': e.key, 'checksum': e.value},
      ],
    });
    return {
      for (final r in (j['results'] as List).cast<Map<String, dynamic>>())
        r['id'] as String: UploadCheck(r['action'] == 'accept', r['reason'], r['assetId']),
    };
  }

  /// Uploads one file (same fields the mobile app sends). Returns the asset id and
  /// whether the server already had it.
  Future<({String id, bool duplicate})> uploadAsset(
    File file, {
    required DateTime createdAt,
    required DateTime modifiedAt,
    String? sha1,
    void Function(int sent, int total)? onProgress,
    Future<void>? abortTrigger,
  }) async {
    final name = file.uri.pathSegments.last;
    // Abort when no bytes moved for [stallTimeout] (or the server sits on the response).
    final stalled = Completer<void>();
    Timer? watchdog;
    void arm(Duration d) {
      watchdog?.cancel();
      watchdog = Timer(d, () {
        if (!stalled.isCompleted) stalled.complete();
      });
    }

    arm(stallTimeout);
    final req = _ProgressMultipartRequest('POST', _uri('/assets'),
        abortTrigger: Future.any([stalled.future, ?abortTrigger]), onProgress: (sent, total) {
      // Once the body is out, the server still stores the file before answering.
      arm(sent >= total ? requestTimeout : stallTimeout);
      onProgress?.call(sent, total);
    })
      ..headers.addAll(headers)
      ..fields.addAll({
        'fileCreatedAt': createdAt.toUtc().toIso8601String(),
        'fileModifiedAt': modifiedAt.toUtc().toIso8601String(),
        'filename': name,
        'isFavorite': 'false',
      })
      ..files.add(http.MultipartFile('assetData', file.openRead(), await file.length(),
          filename: name));
    if (sha1 != null) req.headers['x-immich-checksum'] = sha1;
    final http.StreamedResponse res;
    final String body;
    try {
      res = await _client.send(req);
      arm(stallTimeout);
      body = await res.stream.bytesToString();
    } on SocketException catch (e) {
      throw ApiException(t('linux_err_unreachable', {'error': e.message}));
    } on http.RequestAbortedException {
      if (stalled.isCompleted) throw ApiException(t('linux_err_timeout'));
      rethrow;
    } finally {
      watchdog?.cancel();
    }
    if (res.statusCode == 413) throw ApiException(t('linux_err_too_large'), 413);
    if (res.statusCode != 200 && res.statusCode != 201) {
      String msg = t('linux_err_upload');
      try {
        final m = jsonDecode(body)['message'];
        if (m != null) msg = m is List ? m.join(', ') : '$m';
      } catch (_) {}
      throw ApiException(msg, res.statusCode);
    }
    final j = jsonDecode(body) as Map<String, dynamic>;
    return (id: j['id'] as String, duplicate: j['status'] == 'duplicate');
  }

  /// size: 'thumbnail' (~250px webp) or 'preview' (~1440px jpeg).
  String thumbnailUrl(String id, {String size = 'thumbnail'}) =>
      _uri('/assets/$id/thumbnail', {'size': size}).toString();

  String videoUrl(String id) => _uri('/assets/$id/video/playback').toString();

  /// Streams the original file to [target]. Reports progress 0..1 when size is known.
  Future<void> downloadOriginal(String id, File target, {void Function(double)? onProgress}) async {
    final req = http.Request('GET', _uri('/assets/$id/original'))..headers.addAll(headers);
    final res = await _sendStream(req);
    final total = res.contentLength;
    var got = 0;
    await _saveStream(res, target, (n) {
      got += n;
      if (total != null && total > 0) onProgress?.call(got / total);
    });
  }

  /// Whole file in memory (panoramas need the original's pixels and XMP).
  Future<Uint8List> originalBytes(String id, {void Function(double)? onProgress}) =>
      _bytes(http.Request('GET', _uri('/assets/$id/original'))..headers.addAll(headers), onProgress);

  Future<Uint8List> previewBytes(String id) =>
      _bytes(http.Request('GET', Uri.parse(thumbnailUrl(id, size: 'preview')))..headers.addAll(headers), null);

  Future<Uint8List> _bytes(http.BaseRequest req, void Function(double)? onProgress) async {
    final res = await _sendStream(req);
    final total = res.contentLength;
    final out = BytesBuilder(copy: false);
    await for (final chunk in res.stream) {
      out.add(chunk);
      if (total != null && total > 0) onProgress?.call(out.length / total);
    }
    return out.takeBytes();
  }

  /// Sends a streamed download request; a non-200 response is drained (freeing the
  /// connection) and turned into an [ApiException].
  Future<http.StreamedResponse> _sendStream(http.BaseRequest req) async {
    final http.StreamedResponse res;
    try {
      res = await _client.send(req).timeout(requestTimeout);
    } on TimeoutException {
      throw ApiException(t('linux_err_timeout'));
    } on SocketException catch (e) {
      throw ApiException(t('linux_err_unreachable', {'error': e.message}));
    }
    if (res.statusCode != 200) {
      await res.stream.drain<void>().catchError((_) {});
      throw ApiException(t('linux_err_download'), res.statusCode);
    }
    // A transfer that stops moving fails instead of hanging.
    return http.StreamedResponse(
      res.stream.timeout(stallTimeout, onTimeout: (sink) {
        sink.addError(ApiException(t('linux_err_timeout')));
        sink.close();
      }),
      res.statusCode,
      contentLength: res.contentLength,
      request: res.request,
      headers: res.headers,
      reasonPhrase: res.reasonPhrase,
    );
  }

  /// Writes [res] to "[target].part" and renames it when complete, so an interrupted
  /// download never leaves a file that looks finished.
  static Future<void> _saveStream(http.StreamedResponse res, File target, void Function(int) onChunk) async {
    final tmp = File('${target.path}.part');
    final sink = tmp.openWrite();
    try {
      await for (final chunk in res.stream) {
        sink.add(chunk);
        onChunk(chunk.length);
      }
      await sink.close();
      await tmp.rename(target.path);
    } catch (e) {
      await sink.close();
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
  }
}
