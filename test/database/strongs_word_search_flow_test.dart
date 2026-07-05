import 'package:flutter_test/flutter_test.dart';
import 'package:selah/database/strongs_database.dart';
import 'package:selah/services/strongs_search_worker.dart';

void main() {
  test('combined word search resolves ambassage to G4242 only', () {
    final wordData =
        StrongsDatabase.searchByWordWithStrongsNumbers('ambassage');

    final results = StrongsDatabase.searchByStrongsNumbers(
      wordData.foundStrongsNumbers.keys.toList(),
    );
    final phraseSummary = StrongsDatabase.extractPhraseSummary(
      results,
      wordData.foundStrongsNumbers.keys.toList(),
    );

    expect(wordData.wordVerses, hasLength(1));
    expect(wordData.foundStrongsNumbers.keys, ['G4242']);
    expect(results, hasLength(2));
    expect(phraseSummary, {'an ambassage': 1, 'a message': 1});
  });

  test('combined word search only collects numbers attached to Samuel', () {
    final wordData = StrongsDatabase.searchByWordWithStrongsNumbers('samuel');

    expect(wordData.foundStrongsNumbers.keys, containsAll(['H8050', 'G4545']));
    expect(wordData.foundStrongsNumbers.keys, isNot(contains('H559')));
    expect(wordData.foundStrongsNumbers.keys, isNot(contains('H1696')));
  });

  test('reference search falls back to the nearest phrase tag on the right',
      () {
    final result = runReferenceSearch(const ReferenceSearchTaskData(
      book: 'Exo',
      chapter: 34,
      verse: 10,
      word: 'terrible',
    ));

    expect(result.error, isNull);
    expect(result.strongsNumbers, ['H3372']);
    expect(result.searchResults, isNotEmpty);
  });
}
