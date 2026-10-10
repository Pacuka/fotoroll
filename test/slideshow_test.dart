import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:fotoroll/screens/slideshow.dart';
import 'package:fotoroll/settings.dart';

void main() {
  test('forward and backward stop at the ends unless repeating', () {
    final f = SlideshowOrder(3, 1, 'forward');
    expect(f.next(1), 2);
    expect(f.next(2), isNull);
    expect(f.next(2, repeat: true), 0);
    expect(f.previous(1), 0);
    expect(f.previous(0), isNull);
    final b = SlideshowOrder(3, 1, 'backward');
    expect(b.next(1), 0);
    expect(b.next(0), isNull);
    expect(b.next(0, repeat: true), 2);
    expect(b.previous(1), 2);
  });

  test('shuffle starts at the chosen slide and visits every slide once', () {
    final s = SlideshowOrder(20, 7, 'shuffle', random: math.Random(1));
    final seen = [7];
    int? i = 7;
    while ((i = s.next(i!)) != null) {
      seen.add(i!);
    }
    expect(seen.length, 20);
    expect(seen.toSet().length, 20);
    expect(s.previous(seen[3]), seen[2]);
    expect(s.next(seen.last, repeat: true), 7);
  });

  test('prefs survive a save/load round trip and clamp bad durations', () {
    final p = SlideshowPrefs(direction: 'shuffle', look: 'blurred', seconds: 12, repeat: true, overlay: true);
    final back = SlideshowPrefs.fromJson(p.toJson());
    expect(back.toJson(), p.toJson());
    expect(SlideshowPrefs.fromJson({'seconds': 0}).seconds, 1);
    expect(SlideshowPrefs.fromJson({}).direction, 'forward');
  });
}
