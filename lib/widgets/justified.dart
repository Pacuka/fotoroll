// Justified-rows layout like the web timeline: each row is scaled so it exactly
// fills the width, keeping every photo's aspect ratio.
import 'package:intl/intl.dart';

import '../i18n.dart';

class JustifiedRow {
  final int start; // index of first item within the group
  final List<double> widths;
  final double height;
  const JustifiedRow(this.start, this.widths, this.height);
}

List<JustifiedRow> justify(
  List<double> ratios,
  double width, {
  double targetHeight = 235,
  double gap = 4,
}) {
  final rows = <JustifiedRow>[];
  if (width <= 0) return rows;
  var start = 0;
  var sum = 0.0;
  for (var i = 0; i < ratios.length; i++) {
    // Clamp extreme panoramas/slivers so one photo can't dominate a row.
    sum += ratios[i].clamp(0.4, 3.5);
    final n = i - start + 1;
    if (sum * targetHeight + gap * (n - 1) >= width) {
      final h = (width - gap * (n - 1)) / sum;
      rows.add(JustifiedRow(start, [
        for (var k = start; k <= i; k++) ratios[k].clamp(0.4, 3.5) * h,
      ], h));
      start = i + 1;
      sum = 0;
    }
  }
  if (start < ratios.length) {
    // Last, incomplete row keeps the target height instead of stretching.
    rows.add(JustifiedRow(start, [
      for (var k = start; k < ratios.length; k++) ratios[k].clamp(0.4, 3.5) * targetHeight,
    ], targetHeight));
  }
  return rows;
}

/// Splits [dates] (already sorted) into runs of the same calendar day.
/// Returns start indices of each run. Unknown dates join the previous run.
List<int> dayRuns(List<DateTime?> dates) {
  final starts = <int>[];
  DateTime? prev;
  for (var i = 0; i < dates.length; i++) {
    final d = dates[i];
    final newDay = d != null &&
        prev != null &&
        (d.year != prev.year || d.month != prev.month || d.day != prev.day);
    if (i == 0 || newDay) starts.add(i);
    if (d != null) prev = d;
  }
  return starts;
}

/// Day header like the web's formatGroupTitle: Today, Yesterday, weekday name
/// within the last week, "Mon, Oct 5" this year, otherwise with the year.
String dayTitle(DateTime d, DateTime now) {
  final loc = i18n.dateLocale;
  final today = DateTime.utc(now.year, now.month, now.day);
  final day = DateTime.utc(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  String cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  if (diff == 0) return t('linux_today');
  if (diff == 1) return t('linux_yesterday');
  if (diff > 1 && diff <= 6) return cap(DateFormat.EEEE(loc).format(d));
  if (d.year == now.year) return cap(DateFormat.MMMEd(loc).format(d));
  return cap(DateFormat.yMMMEd(loc).format(d));
}
