import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selah/utils/verse_text_parser.dart';

void main() {
  group('leading Strong tags', () {
    test('removes one following space when Strong numbers are hidden', () {
      const text =
          '{G2228} Know ye not{G50}{{G5719}}, that so{G3754} many of us';

      final parsed = VerseTextParser.parseVerseText(
        text,
        const TextStyle(),
      );

      expect(parsed.toPlainText(), 'Know ye not, that so many of us');
      expect(
        VerseTextParser.toPlainVerseText(text),
        'Know ye not, that so many of us',
      );
    });

    test('handles contiguous regular and TVM tags at the boundary', () {
      const text = '{G2228}{{G5719}} Know ye not';

      expect(VerseTextParser.stripStrongsTags(text), 'Know ye not');
    });

    test('does not consume spaces following tags within the text', () {
      const text = 'Know{G50} ye not';

      expect(VerseTextParser.stripStrongsTags(text), 'Know ye not');
    });

    test('keeps the boundary space when Strong numbers are displayed', () {
      const text = '{G2228} Know ye not';

      final parsed = VerseTextParser.parseVerseText(
        text,
        const TextStyle(),
        showStrongsNumbers: true,
      );
      final visibleText = parsed.children!
          .whereType<TextSpan>()
          .map((span) => span.text ?? '')
          .join();

      expect(visibleText, ' Know ye not');
    });
  });
}
