import 'package:flutter_test/flutter_test.dart';
import 'package:selah/database/strongs_database.dart';

void main() {
  group('StrongsDatabase word associations', () {
    test('excludes TVM codes from word-associated Strong numbers', () {
      final strongs = StrongsDatabase.findStrongsNumbersForWordInVerse(
        'Mat',
        27,
        50,
        'cried',
      );

      expect(strongs, contains('G2896'));
      expect(strongs, isNot(contains('G5660')));
    });

    test('excludes standalone Strong numbers after pilcrow markers', () {
      final strongs = StrongsDatabase.findStrongsNumbersForWordInVerse(
        'Mat',
        27,
        50,
        'Jesus',
      );

      expect(strongs, contains('G2424'));
      expect(strongs, isNot(contains('G1161')));
    });

    test('matches words within a tagged phrase', () {
      final strongs = StrongsDatabase.findStrongsNumbersForWordInVerse(
        'Mat',
        27,
        50,
        'yielded',
      );

      expect(strongs, contains('G863'));
      expect(strongs, isNot(contains('G5656')));
    });

    test('excludes tags separated from words by punctuation only', () {
      final strongs = StrongsDatabase.findStrongsNumbersForWordInVerse(
        'Rom',
        3,
        8,
        'say',
      );

      expect(strongs, contains('G3004'));
      expect(strongs, isNot(contains('G5721')));
      expect(strongs, isNot(contains('G3754')));
    });

    test('bulk Strong number search ignores unassociated standalone tags', () {
      final references = StrongsDatabase.searchByStrongsNumbers(['G1161'])
          .map((result) =>
              '${result['book']} ${result['chapter']}:${result['verse']}')
          .toSet();

      expect(references, contains('Mat 3:7'));
      expect(references, isNot(contains('Mat 27:50')));
    });

    test('phrase summary can include TVM codes only when requested', () {
      final verse = {
        'book': 'Mat',
        'chapter': 27,
        'verse': 50,
        'text': StrongsDatabase.getVerseText('Mat', 27, 50)!,
      };

      final regularSummary =
          StrongsDatabase.extractPhraseSummary([verse], ['G5656']);
      final tvmSummary = StrongsDatabase.extractPhraseSummary(
        [verse],
        ['G5656'],
        includeTvm: true,
      );

      expect(regularSummary, isEmpty);
      expect(tvmSummary['yielded up'], 1);
    });
  });
}
