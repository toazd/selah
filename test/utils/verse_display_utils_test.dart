import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:selah/utils/verse_display_utils.dart';
import 'package:selah/utils/verse_text_parser.dart';

void main() {
  group('applyHighlightsToText', () {
    test('highlights a word in plain verse text', () {
      const raw = 'and let them choose one bullock';
      final plain = VerseTextParser.toPlainVerseText(raw, removePilcrow: true);
      final cleanStart = plain.indexOf('one');
      final cleanEnd = cleanStart + 'one'.length;

      final spans = applyHighlightsToText(
        raw, plain, const TextStyle(color: Colors.black, fontSize: 20), 1,
        Colors.white,
        [{'start': cleanStart, 'end': cleanEnd,
          'color': Colors.yellow.toARGB32()}],
        Colors.black, Colors.white,
      );

      expect(_highlightedText(spans), 'one');
    });

    test('uses clean text offsets with markup removed', () {
      const raw = 'And the LORD God took the man, and put him into the garden.';
      final plain = VerseTextParser.toPlainVerseText(raw, removePilcrow: true);
      final start = plain.indexOf('garden');
      final spans = applyHighlightsToText(
        raw, plain, const TextStyle(color: Colors.black, fontSize: 20), 15,
        Colors.white,
        [{'start': start, 'end': start + 'garden'.length,
          'color': Colors.yellow.toARGB32()}],
        Colors.black, Colors.white,
      );

      expect(_highlightedText(spans), 'garden');
      expect(_resolvedText(raw, start, start + 'garden'.length), 'garden');
    });

    test('uses offsets after removing pilcrow markers', () {
      const raw = '¶ And God said, Let there be';
      final plain = VerseTextParser.toPlainVerseText(raw, removePilcrow: true);
      final cleanStart = plain.indexOf('God');
      final cleanEnd = cleanStart + 'God'.length;

      final spans = applyHighlightsToText(
        raw, plain, const TextStyle(color: Colors.black, fontSize: 20), 3,
        Colors.white,
        [{'start': cleanStart, 'end': cleanEnd,
          'color': Colors.yellow.toARGB32()}],
        Colors.black, Colors.white,
      );

      expect(plain.startsWith('And'), isTrue);
      expect(_highlightedText(spans), 'God');
    });
  });
}

String _highlightedText(List<InlineSpan> spans) {
  final buffer = StringBuffer();

  for (final span in spans) {
    if (span is TextSpan) {
      if (span.style?.backgroundColor != null) {
        buffer.write(span.text);
      }
      final children = span.children;
      if (children != null) {
        buffer.write(_highlightedText(children));
      }
    }
  }

  return buffer.toString();
}

String? _resolvedText(String rawVerseText, int start, int end) {
  final range = resolveHighlightCleanTextRange(
    rawVerseText: rawVerseText,
    savedStart: start,
    savedEnd: end,
  );
  if (range == null) return null;

  final plainVerseText =
      VerseTextParser.toPlainVerseText(rawVerseText, removePilcrow: true);
  return plainVerseText.substring(range.start, range.end);
}
