import 'package:flutter_test/flutter_test.dart';
import 'package:fotoroll/api.dart';

void main() {
  test('text modes map to the web\'s fields; only "context" with text is a smart search', () {
    expect(SearchFilter(query: 'dog').toJson()['query'], 'dog');
    expect(SearchFilter(query: 'dog').isSmart, isTrue);
    expect(SearchFilter().isSmart, isFalse); // no text: metadata search with filters only
    final modes = {
      SearchMode.filename: 'originalFileName',
      SearchMode.description: 'description',
      SearchMode.path: 'originalPath',
      SearchMode.ocr: 'ocr',
    };
    modes.forEach((mode, field) {
      final f = SearchFilter(query: ' x ', mode: mode);
      expect(f.isSmart, isFalse);
      expect(f.toJson()[field], 'x');
      expect(f.toJson().containsKey('query'), isFalse);
    });
  });

  test('filters: people, tags, place, camera, type, display, rating', () {
    final f = SearchFilter(
      personIds: {'p1'},
      tagIds: {'t1'},
      country: 'Hungary',
      city: 'Budapest',
      make: 'Sony',
      type: 'VIDEO',
      isFavorite: true,
      inArchive: true,
      notInAlbum: true,
      rating: 4,
    );
    final j = f.toJson();
    expect(j['personIds'], ['p1']);
    expect(j['tagIds'], ['t1']);
    expect(j['country'], 'Hungary');
    expect(j['city'], 'Budapest');
    expect(j.containsKey('state'), isFalse);
    expect(j['make'], 'Sony');
    expect(j['type'], 'VIDEO');
    expect(j['isFavorite'], isTrue);
    expect(j['isNotInAlbum'], isTrue);
    expect(j['visibility'], 'archive');
    expect(j['rating'], 4);
    expect(f.filterCount, 9);
    expect(SearchFilter().toJson(), {'visibility': 'timeline'});
  });

  test('date range covers whole local days', () {
    final f = SearchFilter(takenAfter: DateTime(2024, 5, 1), takenBefore: DateTime(2024, 5, 3));
    final j = f.toJson();
    expect(DateTime.parse(j['takenAfter']).toLocal(), DateTime(2024, 5, 1));
    expect(DateTime.parse(j['takenBefore']).toLocal(), DateTime(2024, 5, 3, 23, 59, 59, 999));
  });

  test('copy is independent', () {
    final a = SearchFilter(personIds: {'p1'});
    final b = a.copy()..personIds.add('p2');
    expect(a.personIds, {'p1'});
    expect(b.personIds, {'p1', 'p2'});
  });
}
