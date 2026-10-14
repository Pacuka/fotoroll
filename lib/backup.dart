// Folder backup, modeled on the mobile app's backup flow:
// scan selected folders → hash (SHA1) → ask server which it already has
// (bulk-upload-check) → upload the rest one at a time.
// Runs inside the app while it is open; local files are never modified.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'api.dart';
import 'app_dirs.dart';
import 'i18n.dart';


class BackupSettings {
  bool enabled;
  List<String> folders;
  List<String> excluded;
  int scanIntervalMinutes;
  bool skipHidden;

  BackupSettings({
    this.enabled = false,
    List<String>? folders,
    List<String>? excluded,
    this.scanIntervalMinutes = 15,
    this.skipHidden = true,
  })  : folders = folders ?? [],
        excluded = excluded ?? [];

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'folders': folders,
        'excluded': excluded,
        'scanIntervalMinutes': scanIntervalMinutes,
        'skipHidden': skipHidden,
      };

  factory BackupSettings.fromJson(Map<String, dynamic> j) => BackupSettings(
        enabled: j['enabled'] ?? false,
        folders: (j['folders'] as List?)?.cast<String>(),
        excluded: (j['excluded'] as List?)?.cast<String>(),
        scanIntervalMinutes: j['scanIntervalMinutes'] ?? 15,
        skipHidden: j['skipHidden'] ?? true,
      );
}

/// What we know about one local file. Re-hashed only if size or mtime change.
class _FileRecord {
  int size;
  int mtime;
  String? sha1;
  bool done;
  String? remoteId;

  _FileRecord(this.size, this.mtime, {this.sha1, this.done = false, this.remoteId});

  Map<String, dynamic> toJson() =>
      {'s': size, 'm': mtime, 'h': sha1, 'd': done, if (remoteId != null) 'r': remoteId};

  factory _FileRecord.fromJson(Map<String, dynamic> j) =>
      _FileRecord(j['s'], j['m'], sha1: j['h'], done: j['d'] ?? false, remoteId: j['r']);
}

class BackupError {
  final String path;
  final String message;
  final DateTime at;
  BackupError(this.path, this.message) : at = DateTime.now();
}

enum BackupPhase { idle, scanning, hashing, checking, uploading, stopped, error }

/// Pure helper so the include/exclude rules can be tested.
bool isBackupCandidate(String path, String root, BackupSettings s, Set<String> extensions) {
  if (!extensions.contains(p.extension(path).toLowerCase())) return false;
  for (final ex in s.excluded) {
    if (p.isWithin(ex, path)) return false;
  }
  if (s.skipHidden && p.split(p.relative(path, from: root)).any((seg) => seg.startsWith('.'))) {
    return false;
  }
  return true;
}

class BackupService extends ChangeNotifier {
  final ImmichApi api;
  final String _stateKey;
  final String _configPath;
  final String _dataPath;
  BackupSettings settings = BackupSettings();

  BackupPhase phase = BackupPhase.idle;
  String? phaseMessage;
  int total = 0;
  int backedUp = 0;
  String? currentFile;
  int currentSent = 0;
  int currentTotal = 0;
  double bytesPerSecond = 0;
  DateTime? lastRun;
  final List<BackupError> errors = [];

  Map<String, _FileRecord> _records = {};
  Set<String>? _extensions;
  bool _running = false;
  bool _rerun = false;
  bool _retryLater = false;
  Timer? _retryTimer;
  bool _disposed = false;
  Completer<void>? _abort;
  Timer? _timer;
  Timer? _debounce;
  Future<void> _saving = Future.value();
  final List<StreamSubscription<FileSystemEvent>> _watches = [];
  int _dirtyRecords = 0;

  /// Tests point every service at a scratch folder instead of the user's config.
  static String? overrideRoot;

  BackupService(this.api, {required String userId, String? configDir, String? dataDir})
      : _configPath = configDir ?? (overrideRoot != null ? p.join(overrideRoot!, 'config') : appConfigDir()),
        _dataPath = dataDir ?? (overrideRoot != null ? p.join(overrideRoot!, 'data') : appDataDir()),
        _stateKey = sha1
            .convert(utf8.encode('${ImmichApi.normalizeServerUrl(api.creds.serverUrl)}|$userId'))
            .toString()
            .substring(0, 16);

  int get remaining => total - backedUp;
  bool get isRunning => _running;

  File get _settingsFile => File(p.join(_configPath, 'backup.json'));
  File get _stateFile => File(p.join(_dataPath, 'backup-$_stateKey.json'));

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Future<void> init() async {
    try {
      if (await _settingsFile.exists()) {
        settings = BackupSettings.fromJson(jsonDecode(await _settingsFile.readAsString()));
      }
    } catch (_) {}
    try {
      if (await _stateFile.exists()) {
        final j = jsonDecode(await _stateFile.readAsString()) as Map<String, dynamic>;
        _records = j.map((k, v) => MapEntry(k, _FileRecord.fromJson(v)));
      }
    } catch (_) {}
    _applySchedule();
    notifyListeners();
    if (settings.enabled) unawaited(runNow());
  }

  Future<void> updateSettings(void Function(BackupSettings s) change) async {
    change(settings);
    settings.folders = settings.folders.toSet().toList()..sort();
    settings.excluded = settings.excluded.toSet().toList()..sort();
    await _writeJson(_settingsFile, settings.toJson());
    _applySchedule();
    notifyListeners();
    if (settings.enabled) {
      unawaited(runNow());
    } else {
      stop();
    }
  }

  void _applySchedule() {
    _timer?.cancel();
    _debounce?.cancel();
    _retryTimer?.cancel();
    for (final w in _watches) {
      w.cancel();
    }
    _watches.clear();
    if (!settings.enabled) return;
    _timer = Timer.periodic(Duration(minutes: settings.scanIntervalMinutes), (_) => runNow());
    for (final f in settings.folders) {
      try {
        _watches.add(Directory(f).watch(recursive: true).listen((e) {
          // New files are often still being written; wait for things to settle.
          _debounce?.cancel();
          _debounce = Timer(const Duration(seconds: 30), runNow);
        }, onError: (_) {}));
      } catch (_) {}
    }
  }

  void stop() {
    _rerun = false;
    _abort?.complete();
    _abort = null;
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    _timer?.cancel();
    _debounce?.cancel();
    _retryTimer?.cancel();
    for (final w in _watches) {
      w.cancel();
    }
    super.dispose();
  }

  void _setPhase(BackupPhase ph, [String? msg]) {
    phase = ph;
    phaseMessage = msg;
    notifyListeners();
  }

  void _addError(String path, Object e) {
    errors.insert(0, BackupError(path, '$e'));
    if (errors.length > 100) errors.removeLast();
  }

  Future<void> runNow() async {
    if (_running) {
      _rerun = true;
      return;
    }
    _running = true;
    errors.clear(); // the list describes the latest run, not every run so far
    final abort = _abort = Completer<void>();
    try {
      do {
        _rerun = false;
        await _runOnce(abort);
      } while (_rerun && !abort.isCompleted && !_disposed);
      if (_retryLater && !abort.isCompleted && !_disposed) {
        _retryLater = false;
        _retryTimer?.cancel();
        _retryTimer = Timer(const Duration(seconds: 20), runNow);
      }
      if (!_disposed) {
        lastRun = DateTime.now();
        _setPhase(abort.isCompleted ? BackupPhase.stopped : BackupPhase.idle);
      }
    } catch (e) {
      _setPhase(BackupPhase.error, '$e');
    } finally {
      _running = false;
      currentFile = null;
      await _saveState();
      notifyListeners();
    }
  }

  Future<void> _runOnce(Completer<void> abort) async {
    if (settings.folders.isEmpty) return;
    _extensions ??= await api.mediaExtensions();

    // 1. Scan
    _setPhase(BackupPhase.scanning);
    final files = <String, FileStat>{};
    for (final root in settings.folders) {
      final dir = Directory(root);
      if (!await dir.exists()) {
        _addError(root, t('linux_folder_missing'));
        continue;
      }
      await for (final e in _walk(dir)) {
        if (abort.isCompleted) return;
        if (!isBackupCandidate(e.path, root, settings, _extensions!)) continue;
        try {
          files[e.path] = await e.stat();
        } catch (_) {}
      }
    }
    total = files.length;
    backedUp = files.keys.where((f) => _isDone(f, files[f]!)).length;
    notifyListeners();

    // 2. Hash + check in batches, then upload what the server lacks.
    final pending = files.keys.where((f) => !_isDone(f, files[f]!)).toList()..sort();
    final settleLimit = DateTime.now().subtract(const Duration(seconds: 10));
    for (var i = 0; i < pending.length; i += 100) {
      if (abort.isCompleted) return;
      final batch = <String, String>{};
      _setPhase(BackupPhase.hashing, '${i + 1}–${(i + 100).clamp(0, pending.length)} / ${pending.length}');
      for (final path in pending.skip(i).take(100)) {
        if (abort.isCompleted) return;
        final st = files[path]!;
        if (st.modified.isAfter(settleLimit)) {
          _retryLater = true; // still being written, try again shortly
          continue;
        }
        final hash = await _hash(path, st);
        if (hash != null) batch[path] = hash;
      }
      if (batch.isEmpty) continue;

      _setPhase(BackupPhase.checking);
      final checks = await api.bulkUploadCheck(batch);
      for (final path in batch.keys) {
        if (abort.isCompleted) return;
        final c = checks[path];
        final rec = _records[path]!;
        if (c != null && !c.accept) {
          if (c.reason == 'duplicate') {
            _markDone(rec, c.assetId);
          } else {
            _addError(path, t('linux_unsupported_format'));
          }
          continue;
        }
        await _upload(path, files[path]!, rec, abort);
      }
    }
  }

  /// Recursive file listing that skips excluded and (optionally) hidden folders
  /// instead of walking them and filtering afterwards.
  Stream<File> _walk(Directory dir) async* {
    final subdirs = <Directory>[];
    try {
      await for (final e in dir.list(followLinks: false)) {
        if (e is File) {
          yield e;
        } else if (e is Directory) {
          final name = p.basename(e.path);
          if (settings.skipHidden && name.startsWith('.')) continue;
          if (settings.excluded.any((ex) => p.equals(ex, e.path) || p.isWithin(ex, e.path))) continue;
          subdirs.add(e);
        }
      }
    } catch (_) {
      return; // unreadable folder
    }
    for (final d in subdirs) {
      yield* _walk(d);
    }
  }

  bool _isDone(String path, FileStat st) {
    final r = _records[path];
    return r != null && r.done && r.size == st.size && r.mtime == st.modified.millisecondsSinceEpoch;
  }

  Future<String?> _hash(String path, FileStat st) async {
    final mtime = st.modified.millisecondsSinceEpoch;
    var rec = _records[path];
    if (rec == null || rec.size != st.size || rec.mtime != mtime || rec.sha1 == null) {
      try {
        final digest = await sha1.bind(File(path).openRead()).first;
        rec = _records[path] = _FileRecord(st.size, mtime, sha1: digest.toString());
        _dirtyRecords++;
      } catch (e) {
        _addError(path, t('linux_unreadable', {'error': '$e'}));
        return null;
      }
    }
    return rec.sha1;
  }

  void _markDone(_FileRecord rec, String? remoteId) {
    rec.done = true;
    rec.remoteId = remoteId;
    backedUp++;
    if (++_dirtyRecords >= 25) unawaited(_saveState());
    notifyListeners();
  }

  Future<void> _upload(String path, FileStat st, _FileRecord rec, Completer<void> abort) async {
    currentFile = path;
    currentSent = 0;
    currentTotal = st.size;
    bytesPerSecond = 0;
    _setPhase(BackupPhase.uploading);
    final started = DateTime.now();
    var lastNotify = started;
    try {
      final res = await api.uploadAsset(
        File(path),
        // Linux has no reliable birth time here; the server prefers EXIF dates anyway.
        createdAt: st.modified,
        modifiedAt: st.modified,
        sha1: rec.sha1,
        abortTrigger: abort.future,
        onProgress: (sent, total) {
          currentSent = sent;
          currentTotal = total;
          final now = DateTime.now();
          if (now.difference(lastNotify).inMilliseconds > 250) {
            final secs = now.difference(started).inMilliseconds / 1000;
            if (secs > 0) bytesPerSecond = sent / secs;
            lastNotify = now;
            notifyListeners();
          }
        },
      );
      _markDone(rec, res.id);
    } catch (e) {
      if (abort.isCompleted) return;
      if (e is ApiException && e.status == 401) {
        stop();
        throw ApiException(t('linux_session_expired'));
      }
      _addError(path, e);
      notifyListeners();
    }
  }

  /// Writes are chained so two saves never touch the same .tmp file at once.
  Future<void> _saveState() {
    if (_dirtyRecords == 0) return _saving;
    _dirtyRecords = 0;
    return _saving = _saving.then((_) =>
        _writeJson(_stateFile, _records.map((k, v) => MapEntry(k, v.toJson()))).catchError((_) {}));
  }

  static Future<void> _writeJson(File f, Object data) async {
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(data));
    await tmp.rename(f.path);
  }
}
