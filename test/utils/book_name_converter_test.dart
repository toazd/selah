import 'package:flutter_test/flutter_test.dart';
import 'package:selah/utils/book_name_converter.dart';

void main() {
  group('BookNameConverter', () {
    test('normalizes compact and spaced numbered book variants', () {
      expect(BookNameConverter.normalizeBookName('1thessalonians'), '1Th');
      expect(BookNameConverter.normalizeBookName('1 Thessalonians'), '1Th');
      expect(BookNameConverter.normalizeBookName('1thess'), '1Th');
      expect(BookNameConverter.normalizeBookName('1 thess'), '1Th');
      expect(BookNameConverter.normalizeBookName('First Thessalonians'), '1Th');
      expect(BookNameConverter.normalizeBookName('I Thessalonians'), '1Th');
    });

    test('normalizes common non-numbered abbreviations', () {
      expect(BookNameConverter.normalizeBookName('Mt'), 'Mat');
      expect(BookNameConverter.normalizeBookName('Jn'), 'Joh');
      expect(BookNameConverter.normalizeBookName('Jas'), 'Jam');
      expect(BookNameConverter.normalizeBookName('Rev.'), 'Rev');
    });
  });
}
