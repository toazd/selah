import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:selah/utils/verse_text_parser.dart';

void main() {
  group('plain verse text', () {
    test('strips red-letter tags', () {
      const text = '<r>It hath been said</r>, Whosoever.';
      expect(VerseTextParser.toPlainVerseText(text),
          'It hath been said, Whosoever.');
    });

    test('strips italics tags', () {
      const text = 'and darkness <i>was</i> upon the deep.';
      expect(VerseTextParser.toPlainVerseText(text),
          'and darkness was upon the deep.');
    });

    test('removes pilcrow markers by default', () {
      const text = '¶ Then the eleven went away.';
      expect(VerseTextParser.toPlainVerseText(text),
          'Then the eleven went away.');
    });

    test('keeps pilcrow when removePilcrow is false', () {
      const text = '¶ Then the eleven went away.';
      expect(
          VerseTextParser.toPlainVerseText(text, removePilcrow: false), text);
    });

    test('leaves plain text untouched', () {
      const text = 'Then the eleven went away.';
      expect(VerseTextParser.toPlainVerseText(text), text);
    });
  });

  group('parseVerseText', () {
    test('parses red-letter and italics markup', () {
      const text = '<r>It hath been said</r>, and darkness <i>was</i>.';
      final parsed = VerseTextParser.parseVerseText(text, const TextStyle());
      expect(parsed.toPlainText(), 'It hath been said, and darkness was.');
    });

    test('returns plain text as a single span', () {
      const text = 'Then the eleven went away.';
      final parsed = VerseTextParser.parseVerseText(text, const TextStyle());
      expect(parsed.toPlainText(), text);
    });
  });
}
