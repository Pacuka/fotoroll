// Memory titles like the web's memoryLaneTitle, and birthdays first in the lane.
import 'package:flutter_test/flutter_test.dart';
import 'package:fotoroll/i18n.dart';
import 'package:fotoroll/widgets/memories.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    i18n.setMessages({
      'years_ago': '{years, plural, one {# year} other {# years}} ago',
      'birthday_memory_title': "{name}'s birthday",
      'unknown': 'Unknown',
    }, {}, 'en');
  });

  final now = DateTime(2026, 10, 14, 12);

  test('on this day: "x years ago" on the day, the date otherwise', () {
    expect(memoryTitle({'type': 'on_this_day', 'data': {'year': 2023}, 'memoryAt': '2026-10-14T00:00:00.000Z'}, now: now),
        '3 years ago');
    expect(memoryTitle({'type': 'on_this_day', 'data': {'year': 2023}, 'memoryAt': '2026-03-05T00:00:00.000Z'}, now: now),
        'Mar 5, 2026');
    // Older servers send no memoryAt.
    expect(memoryTitle({'type': 'on_this_day', 'data': {'year': 2025}}, now: now), '1 year ago');
  });

  test('birthday memories', () {
    expect(memoryTitle({'type': 'birthday', 'data': {'year': 2020, 'personName': 'Dani'}}, now: now), "Dani's birthday");
    expect(memoryTitle({'type': 'birthday', 'data': {'year': 2020}}, now: now), 'Unknown');
    final list = [
      {'id': 'a', 'type': 'on_this_day'},
      {'id': 'b', 'type': 'birthday'},
      {'id': 'c', 'type': 'on_this_day'},
    ];
    expect(birthdaysFirst(list).map((m) => m['id']), ['b', 'a', 'c']);
  });
}
