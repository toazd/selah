import 'package:flutter_test/flutter_test.dart';
import 'package:selah/database/websters_1828_definitions_database.dart';

void main() {
  group('Websters1828DefinitionsDatabase', () {
    test('finds headwords case-insensitively', () {
      expect(
        Websters1828DefinitionsDatabase.findHeadword('abandon'),
        'Abandon',
      );

      expect(
        Websters1828DefinitionsDatabase.getDefinition('abandon'),
        contains('To forsake entirely'),
      );
    });

    test('matches punctuation-heavy headwords with plain input', () {
      expect(
        Websters1828DefinitionsDatabase.findHeadword('abc'),
        'A.B.C.',
      );
    });

    test('strips definition HTML for copying', () {
      expect(
        Websters1828DefinitionsDatabase.stripHtml(
          '<b>ABANDON</b><br><br>To forsake entirely.',
        ),
        'ABANDON\n\nTo forsake entirely.',
      );
    });
  });
}
