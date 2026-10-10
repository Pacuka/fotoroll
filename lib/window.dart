// Native window controls from the GTK runner (linux/runner/my_application.cc):
// full screen, system tray, close-to-tray, files dropped on the window.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

const _channel = MethodChannel('fotoroll/window');

final _tray = StreamController<String>.broadcast();
final _drops = StreamController<List<String>>.broadcast();

/// Tray menu actions the runner doesn't handle itself (e.g. "backup").
Stream<String> get trayActions => _tray.stream;

/// Local paths of files / folders dropped on the window.
Stream<List<String>> get droppedFiles => _drops.stream;

/// True while files are dragged over the window (for a "drop to upload" hint).
final dragHovering = ValueNotifier<bool>(false);
Timer? _dragTimeout;

bool _listening = false;
void _listen() {
  if (_listening) return;
  _listening = true;
  _channel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'onTray':
        _tray.add(call.arguments as String);
      case 'onDrop':
        dragHovering.value = false;
        _drops.add((call.arguments as List).cast<String>());
      case 'onDragOver':
        dragHovering.value = true;
        // GTK sends no leave event in some cases (e.g. Esc); fall back to a timeout.
        _dragTimeout?.cancel();
        _dragTimeout = Timer(const Duration(seconds: 1), () => dragHovering.value = false);
      case 'onDragLeave':
        dragHovering.value = false;
    }
    return null;
  });
}

Future<T?> _invoke<T>(String method, [Object? args]) async {
  _listen();
  try {
    return await _channel.invokeMethod<T>(method, args);
  } on MissingPluginException {
    return null; // widget tests / other embedders: no native window
  }
}

Future<void> setFullScreen(bool on) => _invoke<void>('setFullScreen', on);

Future<bool> isFullScreen() async => await _invoke<bool>('isFullScreen') ?? false;

Future<void> toggleFullScreen() async => setFullScreen(!await isFullScreen());

/// Shows the tray icon with [items] ([id, label]; id '' = separator). The runner
/// handles "open" and "quit"; other ids arrive on [trayActions]. Returns false
/// when no AppIndicator library is installed.
Future<bool> setTray(List<(String, String)> items) async {
  final ok = await _invoke<bool>('setTray', [for (final (id, label) in items) [id, label]]) ?? false;
  trayAvailable.value = ok;
  return ok;
}

/// Whether a tray icon could be shown (an AppIndicator library is installed).
final trayAvailable = ValueNotifier<bool>(false);

Future<void> setCloseToTray(bool on) => _invoke<void>('setCloseToTray', on);

Future<void> showWindow() => _invoke<void>('show');

/// Starts listening for drops and tray clicks (call once at startup).
void initWindowEvents() => _listen();

// ---- Autostart (XDG: ~/.config/autostart) ----

const appId = 'io.github.pacuka.Fotoroll';

String _autostartFile() => p.join(
    Platform.environment['XDG_CONFIG_HOME'] ?? p.join(Platform.environment['HOME'] ?? '.', '.config'),
    'autostart',
    '$appId.desktop');

bool get autostartEnabled => File(_autostartFile()).existsSync();

/// Starts the app at login, hidden in the tray (--hidden).
Future<void> setAutostart(bool on, {String? executable}) async {
  final f = File(_autostartFile());
  if (!on) {
    if (await f.exists()) await f.delete();
    return;
  }
  await f.parent.create(recursive: true);
  await f.writeAsString(autostartEntry(executable ?? Platform.resolvedExecutable));
}

@visibleForTesting
String autostartEntry(String executable) => '''[Desktop Entry]
Type=Application
Name=Fotoroll
Comment=Photo and video library for your Immich server
Exec="$executable" --hidden
Icon=$appId
Terminal=false
X-GNOME-Autostart-enabled=true
''';
