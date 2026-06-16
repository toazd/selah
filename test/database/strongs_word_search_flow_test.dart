import 'package:flutter_test/flutter_test.dart';
import 'package:selah/database/strongs_database.dart';

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
}
