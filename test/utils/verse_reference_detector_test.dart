import 'package:flutter_test/flutter_test.dart';
import 'package:selah/utils/verse_reference_detector.dart';

void main() {
  group('VerseReferenceDetector', () {
    test('detects chapter-only short book references as verse 1', () {
      final references = VerseReferenceDetector.detectReferences('See Mat 23.');

      expect(references, hasLength(1));
      expect(references.single.book, 'Mat');
      expect(references.single.chapter, 23);
      expect(references.single.verse, 1);
      expect(references.single.originalText, 'Mat 23');
    });

    test('detects chapter-only long book references as verse 1', () {
      final references =
          VerseReferenceDetector.detectReferences('Read Matthew 23.');

      expect(references, hasLength(1));
      expect(references.single.book, 'Mat');
      expect(references.single.chapter, 23);
      expect(references.single.verse, 1);
      expect(references.single.originalText, 'Matthew 23');
    });

    test('does not match a chapter-only reference inside a verse reference',
        () {
      final references =
          VerseReferenceDetector.detectReferences('The text is Mat 1:11.');

      expect(references, hasLength(1));
      expect(references.single.book, 'Mat');
      expect(references.single.chapter, 1);
      expect(references.single.verse, 11);
      expect(references.single.originalText, 'Mat 1:11');
    });

    test('does not match a single verse inside a range reference', () {
      final references =
          VerseReferenceDetector.detectReferences('Read Mat 1:1-3.');

      expect(references, hasLength(1));
      expect(references.single.book, 'Mat');
      expect(references.single.chapter, 1);
      expect(references.single.verse, 1);
      expect(references.single.endVerse, 3);
      expect(references.single.originalText, 'Mat 1:1-3');
    });

    test('keeps chapter-only and verse references distinct when both exist',
        () {
      final references = VerseReferenceDetector.detectReferences(
        'Compare Mat 23 with Mat 1:11.',
      );

      expect(references, hasLength(2));
      expect(references[0].originalText, 'Mat 1:11');
      expect(references[0].verse, 11);
      expect(references[1].originalText, 'Mat 23');
      expect(references[1].verse, 1);
    });

    test('detects multiple chapter-only references in Webster definitions', () {
      final references = VerseReferenceDetector.detectReferences(
        'Those that walk in pride he is able to abase. Dan 4. '
        'Whosoever exalteth himself shall be abased, Mat 23. Job 40. '
        '2 Cor 11.',
      );

      expect(
        references.map((reference) => reference.originalText),
        containsAllInOrder(['Dan 4', 'Mat 23', 'Job 40', '2 Cor 11']),
      );
      expect(references.map((reference) => reference.book), [
        'Dan',
        'Mat',
        'Job',
        '2Co',
      ]);
      expect(references.map((reference) => reference.verse), everyElement(1));
    });

    test('ignores invalid chapter-only references', () {
      final references =
          VerseReferenceDetector.detectReferences('See Mat 999.');

      expect(references, isEmpty);
    });

    test('detects common abbreviated references from definition data', () {
      final references = VerseReferenceDetector.detectReferences(
        'Compare Mt 18:6, Ro 5:14, Php 2:7, and 1Pe 3:21.',
      );

      expect(
        references.map((reference) => reference.originalText),
        containsAllInOrder(['Mt 18:6', 'Ro 5:14', 'Php 2:7', '1Pe 3:21']),
      );
      expect(references.map((reference) => reference.book), [
        'Mat',
        'Rom',
        'Phi',
        '1Pe',
      ]);
    });

    test('detects compact and spaced numbered book names', () {
      final references = VerseReferenceDetector.detectReferences(
        'Compare 1thessalonians 5:21 with 1 thess 5:21.',
      );

      expect(
        references.map((reference) => reference.originalText),
        containsAllInOrder(['1thessalonians 5:21', '1 thess 5:21']),
      );
      expect(references.map((reference) => reference.book), ['1Th', '1Th']);
    });
  });
}
