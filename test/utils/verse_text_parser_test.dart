import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selah/utils/highlight_text_color_adjustments.dart';
import 'package:selah/utils/preferences_constants.dart';
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

  group('Strong search highlights', () {
    const baseStyle = TextStyle(color: Colors.black, fontSize: 20);
    const highlightColor = Colors.yellow;

    TextSpan parse(String text) {
      return VerseTextParser.parseMatchedStrongsVerseText(
        text: text,
        baseStyle: baseStyle,
        matchedStrongs: {'G1'},
        highlightColor: highlightColor,
        lightModeTextColor: Colors.black,
        darkModeTextColor: Colors.white,
        strongsColor: Colors.blue,
      );
    }

    void expectReadableHighlight(TextSpan span, {String? text}) {
      TextSpan? highlighted;

      void visit(InlineSpan candidate) {
        if (candidate is! TextSpan) return;
        if ((text == null || candidate.text == text) &&
            candidate.style?.backgroundColor != null) {
          highlighted = candidate;
          return;
        }
        for (final child in candidate.children ?? const <InlineSpan>[]) {
          visit(child);
          if (highlighted != null) return;
        }
      }

      visit(span);
      expect(highlighted, isNotNull);
      final style = highlighted!.style!;
      final background =
          highlightColor.withValues(alpha: defaultHighlightAlpha);

      expect(style.backgroundColor, background);
      expect(
        calculateContrastRatio(style.color!, background),
        greaterThanOrEqualTo(4.5),
      );
    }

    test('adjusts the matched word foreground color', () {
      expectReadableHighlight(parse('word{G1}'), text: 'word');
    });

    test('adjusts the previous word when the tag follows punctuation', () {
      expectReadableHighlight(parse('word,{G1}'));
    });
  });
}
