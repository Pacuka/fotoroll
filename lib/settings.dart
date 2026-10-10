// App preferences (web: "App Settings"), stored in ~/.config/fotoroll/settings.json.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'app_dirs.dart';

class AppSettings extends ChangeNotifier {
  final String _dir;
  String language = 'en';
  ThemeMode themeMode = ThemeMode.system;
  String mapStyle = 'auto';

  AppSettings({String? configDir})
      : _dir = configDir ?? appConfigDir();

  File get _file => File(p.join(_dir, 'settings.json'));

  Future<void> load() async {
    try {
      final j = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      language = j['language'] as String? ?? 'en';
      themeMode = ThemeMode.values.asNameMap()[j['theme']] ?? ThemeMode.system;
      mapStyle = j['mapStyle'] as String? ?? 'auto';
    } catch (_) {}
  }

  Future<void> update({String? language, ThemeMode? themeMode, String? mapStyle}) async {
    if (language != null) this.language = language;
    if (themeMode != null) this.themeMode = themeMode;
    if (mapStyle != null) this.mapStyle = mapStyle;
    notifyListeners();
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(jsonEncode({
        'language': this.language,
        'theme': this.themeMode.name,
        'mapStyle': this.mapStyle,
      }));
    } catch (_) {}
  }
}

final settings = AppSettings();
