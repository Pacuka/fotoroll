// Native window controls from the GTK runner (linux/runner/my_application.cc).
import 'package:flutter/services.dart';

const _channel = MethodChannel('fotoroll/window');

Future<void> setFullScreen(bool on) async {
  try {
    await _channel.invokeMethod('setFullScreen', on);
  } on MissingPluginException {
    // Widget tests / other embedders: no native window to change.
  }
}

Future<bool> isFullScreen() async {
  try {
    return await _channel.invokeMethod<bool>('isFullScreen') ?? false;
  } on MissingPluginException {
    return false;
  }
}

Future<void> toggleFullScreen() async => setFullScreen(!await isFullScreen());
