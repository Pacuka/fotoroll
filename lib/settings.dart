// App preferences (web: "App Settings"), stored in ~/.config/fotoroll/settings.json.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'app_dirs.dart';

/// Slideshow options (web: SlideshowSettingsModal, kept in localStorage there).
class SlideshowPrefs {
  String direction; // forward | backward | shuffle
  String look; // contain | cover | blurred
  int seconds;
  bool progressBar, transition, autoplay, repeat, overlay;
  String overlayMode; // full | description

  SlideshowPrefs({
    this.direction = 'forward',
    this.look = 'contain',
    this.seconds = 5,
    this.progressBar = true,
    this.transition = true,
    this.autoplay = true,
    this.repeat = false,
    this.overlay = false,
    this.overlayMode = 'full',
  });

  factory SlideshowPrefs.fromJson(Map<String, dynamic> j) => SlideshowPrefs(
        direction: j['direction'] as String? ?? 'forward',
        look: j['look'] as String? ?? 'contain',
        seconds: (j['seconds'] as num?)?.toInt().clamp(1, 600) ?? 5,
        progressBar: j['progressBar'] as bool? ?? true,
        transition: j['transition'] as bool? ?? true,
        autoplay: j['autoplay'] as bool? ?? true,
        repeat: j['repeat'] as bool? ?? false,
        overlay: j['overlay'] as bool? ?? false,
        overlayMode: j['overlayMode'] as String? ?? 'full',
      );

  Map<String, dynamic> toJson() => {
        'direction': direction, 'look': look, 'seconds': seconds, 'progressBar': progressBar,
        'transition': transition, 'autoplay': autoplay, 'repeat': repeat, 'overlay': overlay,
        'overlayMode': overlayMode,
      };

  SlideshowPrefs copy() => SlideshowPrefs.fromJson(toJson());
}

class AppSettings extends ChangeNotifier {
  String _dir;
  String language = 'en';
  ThemeMode themeMode = ThemeMode.system;
  String mapStyle = 'auto';
  SlideshowPrefs slideshow = SlideshowPrefs();
  /// Closing the window keeps the app (and folder backup) running in the tray.
  bool closeToTray = true;
  /// The AppImage asked once whether to add itself to the app menu.
  bool menuEntryAsked = false;
  /// Memories page filters (web: MemoriesSettingsModal, kept in localStorage there).
  bool memoriesShowUpcoming = false;
  bool memoriesOnlyFavorites = false;

  AppSettings({String? configDir})
      : _dir = configDir ?? appConfigDir();

  File get _file => File(p.join(_dir, 'settings.json'));

  /// Tests point the global settings at a scratch folder, never the user's config.
  void useDir(String dir) => _dir = dir;

  Future<void> load() async {
    try {
      final j = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      language = j['language'] as String? ?? 'en';
      themeMode = ThemeMode.values.asNameMap()[j['theme']] ?? ThemeMode.system;
      mapStyle = j['mapStyle'] as String? ?? 'auto';
      slideshow = SlideshowPrefs.fromJson((j['slideshow'] as Map?)?.cast<String, dynamic>() ?? {});
      closeToTray = j['closeToTray'] as bool? ?? true;
      menuEntryAsked = j['menuEntryAsked'] as bool? ?? false;
      memoriesShowUpcoming = j['memoriesShowUpcoming'] as bool? ?? false;
      memoriesOnlyFavorites = j['memoriesOnlyFavorites'] as bool? ?? false;
    } catch (_) {}
  }

  Future<void> update({
    String? language,
    ThemeMode? themeMode,
    String? mapStyle,
    SlideshowPrefs? slideshow,
    bool? closeToTray,
    bool? menuEntryAsked,
    bool? memoriesShowUpcoming,
    bool? memoriesOnlyFavorites,
  }) async {
    if (memoriesShowUpcoming != null) this.memoriesShowUpcoming = memoriesShowUpcoming;
    if (memoriesOnlyFavorites != null) this.memoriesOnlyFavorites = memoriesOnlyFavorites;
    if (menuEntryAsked != null) this.menuEntryAsked = menuEntryAsked;
    if (slideshow != null) this.slideshow = slideshow;
    if (closeToTray != null) this.closeToTray = closeToTray;
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
        'slideshow': this.slideshow.toJson(),
        'closeToTray': this.closeToTray,
        'menuEntryAsked': this.menuEntryAsked,
        'memoriesShowUpcoming': this.memoriesShowUpcoming,
        'memoriesOnlyFavorites': this.memoriesOnlyFavorites,
      }));
    } catch (_) {}
  }
}

final settings = AppSettings();
