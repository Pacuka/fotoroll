// Every t('key') used in lib/ must exist in the Immich or app translation files,
// and every app-only string needs a Hungarian translation.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fotoroll/i18n.dart';

Map<String, String> load(String path) =>
    I18n.flatten(jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>);

void main() {
  test('all used translation keys exist', () {
    final known = {...load('assets/i18n/en.json'), ...load('assets/i18n_app/en.json')};
    final used = <String, String>{};
    final pattern = RegExp(r"""\bt\(\s*'([a-z0-9_.]+)'""");
    // Enum/nav labels, e.g. favorite('to_favorite', …) and _NavEntry(_Page.x, 'photos', …).
    final labelKeys = RegExp(r"""(?:_NavEntry\(_Page\.\w+, |^\s+[a-z]\w*\()'([a-z0-9_.]+)',""", multiLine: true);
    // Preference forms: _Pref('config.path', 'label', …, desc: 'key') and _PrefGroup('title', 'subtitle', …).
    final prefKeys = RegExp(r"""_Pref\('[^']+', '([a-z0-9_.]+)'|desc: '([a-z0-9_.]+)'|_PrefGroup\('([a-z0-9_.]+)', '([a-z0-9_.]+)'""");
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      for (final m in [...pattern.allMatches(src), ...labelKeys.allMatches(src)]) {
        used[m[1]!] = f.path;
      }
      for (final m in prefKeys.allMatches(src)) {
        for (var g = 1; g <= m.groupCount; g++) {
          if (m[g] != null) used[m[g]!] = f.path;
        }
      }
    }
    expect(used.length, greaterThan(100));
    final missing = used.entries.where((e) => !known.containsKey(e.key)).map((e) => '${e.key} (${e.value})');
    expect(missing, isEmpty);
  });

  test('app-only strings are translated to Hungarian', () {
    final en = load('assets/i18n_app/en.json');
    final hu = load('assets/i18n_app/hu.json');
    expect(en.keys.toSet().difference(hu.keys.toSet()), isEmpty);
  });
}
