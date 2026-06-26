import 'package:flutter_test/flutter_test.dart';
import 'package:selah/widgets/strongs_definition_dialog.dart';

void main() {
  group('StrongsDefinitionDialog', () {
    test('links Strong numbers and verse references in definition html', () {
      final html = StrongsDefinitionDialog.linkDefinitionReferencesForTesting(
        'Compare H1 with Mat 23:1 and G25.',
      );

      expect(html, contains('<a href="strongs://H1">H1</a>'));
      expect(
        html,
        contains(
          '<a href="v://Mat/23/1" data-reference-text="Mat 23:1">'
          'Mat 23:1</a>',
        ),
      );
      expect(html, contains('<a href="strongs://G25">G25</a>'));
    });

    test('does not link text inside existing anchors or html tags', () {
      final html = StrongsDefinitionDialog.linkDefinitionReferencesForTesting(
        '<a href="https://example.com">Mat 23:1 and H1</a>'
        '<B title="G25">Ro 5:14</B>',
      );

      expect(
        html,
        contains('<a href="https://example.com">Mat 23:1 and H1</a>'),
      );
      expect(html, contains('<B title="G25">'));
      expect(
        html,
        contains(
          '<a href="v://Rom/5/14" data-reference-text="Ro 5:14">'
          'Ro 5:14</a>',
        ),
      );
      expect(html, isNot(contains('strongs://H1')));
      expect(html, isNot(contains('strongs://G25')));
    });
  });
}
