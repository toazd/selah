import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selah/utils/verse_display_utils.dart';
import 'package:selah/utils/verse_text_parser.dart';

void main() {
  group('applyHighlightsToText', () {
    test('keeps clean-position highlights aligned when Strong numbers display',
        () {
      const rawVerseText =
          'and let them choose{H977}{H8799} one{H259} bullock{H6499}';
      final plainVerseText =
          VerseTextParser.toPlainVerseText(rawVerseText, removePilcrow: true);
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
            'start': cleanStart,
            'end': cleanEnd,
            'color': Colors.yellow.toARGB32(),
          },
        ],
        Colors.black,
        Colors.white,
        showStrongsNumbers: true,
      );

      expect(_highlightedText(spans), 'one');
    });

    test('uses existing Gen 2:15 ranges as clean text offsets', () {
      const rawVerseText =
          'And the LORD{H3068} God{H430} took{H3947}{{H8799}} the man{H120}, and put him{H3240}{{H8686}} into the garden{H1588} of Eden{H5731} to dress{H5647}{{H8800}} it and to keep{H8104}{{H8800}} it.';
      final plainVerseText =
          VerseTextParser.toPlainVerseText(rawVerseText, removePilcrow: true);
      final highlights = [
        {
          'start': 52,
          'end': 58,
          'color': Colors.yellow.toARGB32(),
        },
        {
          'start': 67,
          'end': 78,
          'color': Colors.green.toARGB32(),
        },
        {
          'start': 83,
          'end': 93,
          'color': Colors.pink.toARGB32(),
        },
      ];

      final spans = applyHighlightsToText(
        rawVerseText,
        plainVerseText,
        const TextStyle(color: Colors.black, fontSize: 20),
        15,
        Colors.white,
        highlights,
        Colors.black,
        Colors.white,
        showStrongsNumbers: true,
      );

      expect(_highlightedText(spans), 'gardento dress itto keep it');
      expect(_resolvedText(rawVerseText, 52, 58), 'garden');
      expect(_resolvedText(rawVerseText, 67, 78), 'to dress it');
      expect(_resolvedText(rawVerseText, 83, 93), 'to keep it');
    });

    test('uses offsets after removing pilcrow markers', () {
      const rawVerseText = '¶ And God{H430} said{H559}{{H8799}}, Let there be';
      final plainVerseText =
          VerseTextParser.toPlainVerseText(rawVerseText, removePilcrow: true);
      final cleanStart = plainVerseText.indexOf('God');
      final cleanEnd = cleanStart + 'God'.length;

      final spans = applyHighlightsToText(
        rawVerseText,
        plainVerseText,
        const TextStyle(color: Colors.black, fontSize: 20),
        3,
        Colors.white,
        [
          {
            'start': cleanStart,
            'end': cleanEnd,
            'color': Colors.yellow.toARGB32(),
          },
        ],
        Colors.black,
        Colors.white,
        showStrongsNumbers: true,
      );

      expect(plainVerseText.startsWith('And'), isTrue);
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
