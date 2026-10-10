// One shared, muted player for hover previews. Creating and disposing a player
// (and its GL context) per hover blocks the UI, so tiles only hand this one around.
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../api.dart';

class HoverPreview {
  HoverPreview._();

  static Player? _player;
  static VideoController? _controller;

  /// Asset id whose preview is currently showing (after its first frame), or null.
  static final ValueNotifier<String?> showing = ValueNotifier(null);
  static String? _wanted;

  static VideoController get controller {
    _ensure();
    return _controller!;
  }

  static void _ensure() {
    if (_player != null) return;
    final p = Player(configuration: const PlayerConfiguration(title: 'preview', bufferSize: 8 << 20));
    p.setVolume(0);
    p.setPlaylistMode(PlaylistMode.single);
    _player = p;
    _controller = VideoController(p);
  }

  static Future<void> play(ImmichApi api, String assetId) async {
    _ensure();
    _wanted = assetId;
    showing.value = null;
    await _player!.open(Media(api.videoUrl(assetId), httpHeaders: api.headers));
    if (_wanted != assetId) return; // mouse already left
    try {
      await _controller!.waitUntilFirstFrameRendered.timeout(const Duration(seconds: 5));
    } catch (_) {
      return;
    }
    if (_wanted == assetId) showing.value = assetId;
  }

  static Future<void> stop(String assetId) async {
    if (_wanted != assetId) return;
    _wanted = null;
    showing.value = null;
    await _player?.stop();
  }

  /// Stop whatever is playing (e.g. when opening the full viewer).
  static Future<void> stopAll() async {
    _wanted = null;
    showing.value = null;
    await _player?.stop();
  }
}
