// AppImage desktop integration: an AppImage ships no .desktop file, so GNOME and
// other Wayland shells show a generic icon and the raw app id in the dock. This
// adds (and keeps current) a menu entry + icon under ~/.local/share.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'window.dart' show appId, desktopExecArg;

/// Path of the running AppImage file (set by the AppImage runtime), or null.
String? get appImagePath => Platform.environment['APPIMAGE'];

String _dataHome() =>
    Platform.environment['XDG_DATA_HOME'] ?? p.join(Platform.environment['HOME'] ?? '.', '.local', 'share');

File get _desktopFile => File(p.join(_dataHome(), 'applications', '$appId.desktop'));
File get _iconFile => File(p.join(_dataHome(), 'icons', 'hicolor', '512x512', 'apps', '$appId.png'));

/// The menu entry for [executable].
String desktopEntry(String executable) => '''[Desktop Entry]
Type=Application
Name=Fotoroll
GenericName=Photo Library
Comment=Browse, back up and manage the photos on your Immich server
Exec=${desktopExecArg(executable)} %U
Icon=$appId
Terminal=false
Categories=Graphics;Photography;
Keywords=immich;photos;gallery;backup;
StartupWMClass=$appId
X-Fotoroll-AppImage=true
''';

enum MenuEntryState { notAppImage, missing, outdated, current }

/// Whether this AppImage has an up-to-date menu entry. An entry installed by
/// install.sh (not an AppImage one) counts as current: it is left alone.
Future<MenuEntryState> menuEntryState() async {
  final image = appImagePath;
  if (image == null) return MenuEntryState.notAppImage;
  if (!await _desktopFile.exists()) return MenuEntryState.missing;
  final text = await _desktopFile.readAsString();
  if (!text.contains('X-Fotoroll-AppImage=true')) return MenuEntryState.current;
  return text.contains('Exec=${desktopExecArg(image)} ') ? MenuEntryState.current : MenuEntryState.outdated;
}

/// Writes the menu entry and icon for the running AppImage.
Future<void> installMenuEntry() async {
  final image = appImagePath;
  if (image == null) return;
  await _desktopFile.parent.create(recursive: true);
  await _desktopFile.writeAsString(desktopEntry(image));
  final icon = await rootBundle.load('assets/branding/fotoroll.png');
  await _iconFile.parent.create(recursive: true);
  await _iconFile.writeAsBytes(icon.buffer.asUint8List());
  // Best effort: refresh the menu / icon caches where the tools exist.
  for (final cmd in [
    ['update-desktop-database', _desktopFile.parent.path],
    ['gtk-update-icon-cache', '-q', '-t', p.join(_dataHome(), 'icons', 'hicolor')],
  ]) {
    try {
      await Process.run(cmd.first, cmd.sublist(1));
    } catch (_) {}
  }
}

Future<void> removeMenuEntry() async {
  if (await _desktopFile.exists()) await _desktopFile.delete();
  if (await _iconFile.exists()) await _iconFile.delete();
}
