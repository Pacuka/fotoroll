// Index-addressable asset lists shared by the timeline view and the viewer.
// Assets come in "buckets": months for the timeline, one bucket for search.
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'i18n.dart';

abstract class AssetSource extends ChangeNotifier {
  bool _disposed = false;

  // Requests may complete after the source was replaced and disposed.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  int get length;

  int get bucketCount;
  int bucketStart(int b);
  int bucketSize(int b);

  /// Month label for the scrubber, if the source is chronological.
  String? bucketLabel(int b) => null;
  int? bucketYear(int b) => null;

  /// Assets of bucket [b], or null if not loaded yet. With [load], a missing
  /// bucket starts loading (listeners are notified when it arrives).
  List<AssetRef>? bucketAssets(int b, {bool load = true});

  /// Whether the view should insert per-day headers.
  bool get groupByDay => true;

  /// Called when the view reaches the end; paged sources fetch more.
  void onNearEnd() {}

  /// Returns the asset if already loaded; otherwise starts loading and returns null.
  AssetRef? at(int index);

  /// Loads (if needed) and returns the asset at [index].
  Future<AssetRef?> load(int index);

  /// Local edits after a successful server action, so the view updates in place.
  void updateAssets(Set<String> ids, AssetRef Function(AssetRef) change);
  void removeAssets(Set<String> ids);
}

/// Server timeline (all photos, an album, a person…), loaded lazily month by month.
class TimelineSource extends AssetSource {
  final ImmichApi api;
  final TimelineQuery query;
  final List<TimeBucket> _buckets;
  List<int> _offsets = [];
  final List<DateTime?> _dates = [];
  final Map<int, List<AssetRef>> _loaded = {};
  final Map<int, Future<void>> _loading = {};
  int _length = 0;

  TimelineSource._(this.api, this.query, this._buckets) {
    for (final b in _buckets) {
      _dates.add(DateTime.tryParse(b.timeBucket));
    }
    _recount();
  }

  void _recount() {
    _offsets = [];
    _length = 0;
    for (final b in _buckets) {
      _offsets.add(_length);
      _length += b.count;
    }
  }

  @override
  void updateAssets(Set<String> ids, AssetRef Function(AssetRef) change) {
    for (final list in _loaded.values) {
      for (var i = 0; i < list.length; i++) {
        if (ids.contains(list[i].id)) list[i] = change(list[i]);
      }
    }
    notifyListeners();
  }

  @override
  void removeAssets(Set<String> ids) {
    for (final e in _loaded.entries) {
      final before = e.value.length;
      e.value.removeWhere((a) => ids.contains(a.id));
      final removed = before - e.value.length;
      if (removed > 0) {
        final b = _buckets[e.key];
        _buckets[e.key] = TimeBucket(b.timeBucket, b.count - removed);
      }
    }
    _recount();
    notifyListeners();
  }

  static Future<TimelineSource> create(ImmichApi api,
      [TimelineQuery query = TimelineQuery.photos]) async {
    final buckets = await api.timeBuckets(query);
    return TimelineSource._(api, query, buckets);
  }

  @override
  int get length => _length;
  @override
  int get bucketCount => _buckets.length;
  @override
  int bucketStart(int b) => _offsets[b];
  @override
  int bucketSize(int b) => _buckets[b].count;

  @override
  String? bucketLabel(int b) {
    final d = _dates[b];
    if (d == null) return _buckets[b].timeBucket;
    final s = DateFormat.yMMMM(i18n.dateLocale).format(d);
    return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  }

  @override
  int? bucketYear(int b) => _dates[b]?.year;

  @override
  List<AssetRef>? bucketAssets(int b, {bool load = true}) {
    final list = _loaded[b];
    if (list == null && load) _ensure(b).catchError((_) {});
    return list;
  }

  int _bucketOf(int index) {
    var lo = 0, hi = _offsets.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_offsets[mid] <= index) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  Future<void> _ensure(int b) {
    if (_loaded.containsKey(b)) return Future.value();
    return _loading[b] ??= api.timeBucket(_buckets[b].timeBucket, query).then((assets) {
      _loaded[b] = assets;
      notifyListeners();
    }).whenComplete(() {
      // Block body: returning the removed future would make whenComplete await itself.
      _loading.remove(b);
    });
  }

  @override
  AssetRef? at(int index) {
    if (index < 0 || index >= _length) return null;
    final b = _bucketOf(index);
    final list = bucketAssets(b);
    if (list == null) return null;
    final i = index - _offsets[b];
    return i < list.length ? list[i] : null;
  }

  @override
  Future<AssetRef?> load(int index) async {
    if (index < 0 || index >= _length) return null;
    await _ensure(_bucketOf(index));
    return at(index);
  }
}

/// Paged search results; fetches the next page when the end is approached.
class SearchSource extends AssetSource {
  final Future<SearchPage> Function(int page) fetch;
  final List<AssetRef> _items = [];
  int? _nextPage = 1;
  Future<void>? _pending;
  Object? error;

  SearchSource(this.fetch);

  bool get hasMore => _nextPage != null;

  Future<void> loadMore() {
    if (_nextPage == null) return Future.value();
    return _pending ??= fetch(_nextPage!).then((page) {
      _items.addAll(page.assets);
      _nextPage = page.assets.isEmpty ? null : page.nextPage;
      notifyListeners();
    }).catchError((Object e) {
      error = e;
      _nextPage = null;
      notifyListeners();
    }).whenComplete(() => _pending = null);
  }

  @override
  void updateAssets(Set<String> ids, AssetRef Function(AssetRef) change) {
    for (var i = 0; i < _items.length; i++) {
      if (ids.contains(_items[i].id)) _items[i] = change(_items[i]);
    }
    notifyListeners();
  }

  @override
  void removeAssets(Set<String> ids) {
    _items.removeWhere((a) => ids.contains(a.id));
    notifyListeners();
  }

  @override
  int get length => _items.length;
  @override
  int get bucketCount => 1;
  @override
  int bucketStart(int b) => 0;
  @override
  int bucketSize(int b) => _items.length;
  @override
  List<AssetRef>? bucketAssets(int b, {bool load = true}) => _items;
  @override
  bool get groupByDay => false;
  @override
  void onNearEnd() => loadMore();

  @override
  AssetRef? at(int index) {
    if (index >= _items.length - 20) loadMore();
    return index < _items.length ? _items[index] : null;
  }

  @override
  Future<AssetRef?> load(int index) async {
    while (index >= _items.length && hasMore) {
      await loadMore();
    }
    return index < _items.length ? _items[index] : null;
  }
}
