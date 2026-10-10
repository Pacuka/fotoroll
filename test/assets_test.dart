import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every assets/ folder is bundled via pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final dirs = Directory('assets').listSync().whereType<Directory>();
    for (final d in dirs) {
      final name = d.uri.pathSegments.where((s) => s.isNotEmpty).last;
      expect(pubspec.contains('- assets/$name/'), isTrue, reason: 'assets/$name/ missing in pubspec.yaml');
    }
  });
}
