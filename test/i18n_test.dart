import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fotoroll/i18n.dart';
import 'package:intl/date_symbol_data_local.dart';

String fmt(String m, [Map<String, Object?> a = const {}, String l = 'en']) =>
    IcuFormat(m, a, l).format();

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('hu');
  });

  test('plain text, variables and apostrophes', () {
    expect(fmt('Photos'), 'Photos');
    expect(fmt('Hello {name}!', {'name': 'Anna'}), 'Hello Anna!');
    expect(fmt("You've got it"), "You've got it");
    expect(fmt("It''s '{literal}'"), "It's {literal}");
  });

  test('plural with #, exact matches and nesting', () {
    const m = '{count, plural, =0 {No items} one {# item} other {# items}}';
    expect(fmt(m, {'count': 0}), 'No items');
    expect(fmt(m, {'count': 1}), '1 item');
    expect(fmt(m, {'count': 1234}), '1,234 items');
    expect(fmt('{count, plural, other {# elem}}', {'count': 3}, 'hu'), '3 elem');
    expect(fmt('{a, select, x {X {n, plural, one {# one} other {# many}}} other {O}}',
        {'a': 'x', 'n': 2}), 'X 2 many');
  });

  test('selectordinal uses ordinal rules (Immich birthday_memory_age)', () {
    const m = '{age, selectordinal, one {#st} two {#nd} few {#rd} other {#th}} birthday';
    expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 103].map((n) => fmt(m, {'age': n})).toList(), [
      '1st birthday', '2nd birthday', '3rd birthday', '4th birthday', '11th birthday', '12th birthday',
      '13th birthday', '21st birthday', '22nd birthday', '103rd birthday',
    ]);
    expect(fmt('{age, selectordinal, one {#.} other {#.}} születésnapja', {'age': 2}, 'hu'), '2. születésnapja');
  });

  test('date and number styles', () {
    expect(fmt('on {date, date, long}', {'date': DateTime(2026, 3, 1)}), 'on March 1, 2026');
    expect(fmt('{n, number}', {'n': 1500}), '1,500');
  });

  test('real Immich files parse for every language', () {
    final dir = Directory('assets/i18n');
    final en = I18n.flatten(jsonDecode(File('assets/i18n/en.json').readAsStringSync()));
    expect(en['photos'], 'Photos');
    expect(en['admin.create_job'], isNotNull);
    var checked = 0;
    for (final f in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
      final code = f.uri.pathSegments.last.replaceAll('.json', '');
      expect(languageNames.containsKey(code), isTrue, reason: 'no name for $code');
      final m = I18n.flatten(jsonDecode(f.readAsStringSync()));
      for (final e in m.entries) {
        // Must not throw for typical arguments.
        fmt(e.value, {'count': 2, 'name': 'x', 'total': 3, 'number': 4}, 'en');
        checked++;
      }
    }
    expect(checked, greaterThan(50000));
  });

  test('missing translation falls back to English, then the key', () {
    final i = I18n()..setMessages({'a': 'A', 'b': 'B'}, {'a': 'Á', 'b': ''}, 'hu');
    expect(i.t('a'), 'Á');
    expect(i.t('b'), 'B');
    expect(i.t('nope'), 'nope');
  });
}
