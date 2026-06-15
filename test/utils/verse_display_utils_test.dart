import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selah/utils/verse_display_utils.dart';
import 'package:selah/utils/verse_text_parser.dart';

void main() {
  group('applyHighlightsToText', () {
    test('keeps highlights aligned when Strong numbers are displayed', () {
      const rawVerseText =
          'and let them choose{H977}{H8799} one{H259} bullock{H6499}';
      final plainVerseText =
          VerseTextParser.toPlainVerseText(rawVerseText, removePilcrow: false);
      final cleanStart = plainVerseText.indexOf('one');
      final cleanEnd = cleanStart + 'one'.length;

      final spans = applyHighlightsToText(
        rawVerseText,
        plainVerseText,
        const TextStyle(color: Colors.black, fontSize: 20),
        1,
        Colors.white,
        [
          {
            'start': convertCleanPositionToRaw(rawVerseText, cleanStart),
            'end': convertCleanPositionToRaw(rawVerseText, cleanEnd),
            'color': Colors.yellow.toARGB32(),
          },
        ],
        Colors.black,
        Colors.white,
        showStrongsNumbers: true,
      );

      expect(_highlightedText(spans), 'one');
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
