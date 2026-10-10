import 'package:flutter_test/flutter_test.dart';
import 'package:fotoroll/api.dart';
import 'package:fotoroll/i18n.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:fotoroll/widgets/justified.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    i18n.setMessages({'linux_today': 'Today', 'linux_yesterday': 'Yesterday'}, {}, 'en');
  });

  test('justified rows fill the width exactly and keep ratios', () {
    final rows = justify([1.5, 1.5, 0.75, 1, 1, 1, 1, 1.5], 1000, targetHeight: 200, gap: 4);
    for (final r in rows.take(rows.length - 1)) {
      final w = r.widths.fold(0.0, (a, b) => a + b) + 4 * (r.widths.length - 1);
      expect(w, closeTo(1000, 0.01));
      expect(r.height, greaterThan(150));
    }
    // Every item placed exactly once, in order.
    expect(rows.fold(0, (n, r) => n + r.widths.length), 8);
    expect(rows.first.start, 0);
    // 1.5+1.5+0.75+1 = 4.75*200 + 3 gaps = 962 < 1000, so a fifth item joins the row.
    expect(rows.first.widths.length, 5);
    expect(rows.first.widths[0] / rows.first.height, closeTo(1.5, 0.001));
  });

  test('incomplete last row is not stretched', () {
    final rows = justify([1, 1], 1000, targetHeight: 200);
    expect(rows.single.height, 200);
    expect(rows.single.widths, [200, 200]);
  });

  test('day runs split on calendar day changes', () {
    final d = [
      DateTime(2026, 10, 9, 22), DateTime(2026, 10, 9, 8), null,
      DateTime(2026, 10, 8, 23), DateTime(2026, 9, 30),
    ];
    expect(dayRuns(d), [0, 3, 4]);
    expect(dayRuns([]), isEmpty);
  });

  test('day titles follow the web format', () {
    final now = DateTime(2026, 10, 9, 12);
    expect(dayTitle(DateTime(2026, 10, 9, 1), now), 'Today');
    expect(dayTitle(DateTime(2026, 10, 8, 23), now), 'Yesterday');
    expect(dayTitle(DateTime(2026, 10, 5), now), 'Monday');
    expect(dayTitle(DateTime(2026, 9, 1), now), 'Tue, Sep 1');
    expect(dayTitle(DateTime(2025, 3, 1), now), 'Sat, Mar 1, 2025');
    // DST change (Oct 25 → 26 in Europe) must not make "yesterday" look like today.
    expect(dayTitle(DateTime(2026, 10, 25), DateTime(2026, 10, 26, 0, 30)), 'Yesterday');
  });

  test('library queries match the web routes', () {
    expect(TimelineQuery.photos.params['visibility'], 'timeline');
    expect(TimelineQuery.favorites.params['isFavorite'], 'true');
    expect(TimelineQuery.favorites.params['visibility'], isNull);
    expect(TimelineQuery.archive.params['visibility'], 'archive');
    expect(TimelineQuery.trash.params['isTrashed'], 'true');
    expect(TimelineQuery.trash.params['visibility'], isNull);
    expect(const TimelineQuery(userId: 'p').params['userId'], 'p');
  });
}
