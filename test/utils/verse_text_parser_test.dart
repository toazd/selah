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

  group('Strong annotated copy text', () {
    test('inlines Strong and TVM numbers after each word', () {
      // Matthew 28:16
      const text =
          '¶ Then{G1161} the eleven{G1733} disciples{G3101} went away{G4198}{{G5675}} into{G1519} Galilee{G1056}, into{G1519} a mountain{G3735} where{G3757} Jesus{G2424} had appointed{G5021}{{G5668}} them{G846}.';

      expect(
        VerseTextParser.toStrongsAnnotatedVerseText(text),
        'Then G1161 the eleven G1733 disciples G3101 went away G4198 G5675 '
        'into G1519 Galilee G1056, into G1519 a mountain G3735 where G3757 '
        'Jesus G2424 had appointed G5021 G5668 them G846.',
      );
    });

    test('hoists a leading Strong number in front of the verse', () {
      const text =
          '{G1161} <r>It hath been said{G4483}{G3754}{{G5681}}, Whosoever{G3739}{G302} shall put away{G630}{{G5661}} his{G846} wife{G1135}.</r>';

      expect(
        VerseTextParser.toStrongsAnnotatedVerseText(text),
        'G1161 It hath been said G4483 G3754 G5681, Whosoever G3739 G302 '
        'shall put away G630 G5661 his G846 wife G1135.',
      );
    });

    test('hoists a leading Strong number that follows a pilcrow', () {
      const text =
          '¶ {G1161} Jesus{G2424}, when he had cried{G2896}{{G5660}} again{G3825} with a loud{G3173} voice{G5456}, yielded up{G863}{{G5656}} the ghost{G4151}.';

      expect(
        VerseTextParser.toStrongsAnnotatedVerseText(text),
        'G1161 Jesus G2424, when he had cried G2896 G5660 again G3825 with a '
        'loud G3173 voice G5456, yielded up G863 G5656 the ghost G4151.',
      );
    });

    test('hoists contiguous leading Strong and TVM tags', () {
      const text = '{G2228}{{G5719}} Know ye not{G50}{{G5719}}, that so{G3754} many of us';

      expect(
        VerseTextParser.toStrongsAnnotatedVerseText(text),
        'G2228 G5719 Know ye not G50 G5719, that so G3754 many of us',
      );
    });

    test('handles Hebrew numbers', () {
      // Genesis 1:1
      const text =
          'In the beginning{H7225} God{H430} created{H1254}{H853}{{H8804}} the heaven{H8064} and{H853} the earth{H776}.';

      expect(
        VerseTextParser.toStrongsAnnotatedVerseText(text),
        'In the beginning H7225 God H430 created H1254 H853 H8804 the heaven '
        'H8064 and H853 the earth H776.',
      );
    });

    test('leaves text without Strong tags untouched', () {
      const text = 'Then the eleven disciples went away into Galilee.';

      expect(VerseTextParser.toStrongsAnnotatedVerseText(text), text);
    });

    test('hoists leading tags per line when perLine is set', () {
      // Mirrors how nearby search results bundle verses into one string.
      const text = '28 And{G1161} he{G846} came.\n29 {G1161} And{G2532} he{G846} went{G4198}.';

      expect(
        VerseTextParser.toStrongsAnnotatedVerseText(text, perLine: true),
        '28 And G1161 he G846 came.\n29 G1161 And G2532 he G846 went G4198.',
      );
    });

    test('does not introduce a double space at the start of the text', () {
      const text =
          '{G1161} It hath been said{G4483}, Whosoever shall put away his wife.';

      expect(
        VerseTextParser.toStrongsAnnotatedVerseText(text),
        'G1161 It hath been said G4483, Whosoever shall put away his wife.',
      );
    });
  });
}
