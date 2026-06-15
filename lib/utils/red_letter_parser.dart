import 'package:flutter/material.dart';

/// Utility for parsing red-letter text formatting using `<r>` and `</r>` tags.
class RedLetterParser {
  /// Parses text containing red-letter tags and returns a TextSpan with
  /// the tagged portions rendered in red.
  ///
  /// This operates on [cleanText] which should have Strong's tags already
  /// parsed/stripped so that red formatting only applies to actual words.
  static TextSpan parseRedLetterText(String cleanText, TextStyle baseStyle) {
    // Performance optimization: early exit if no red letter tags
    if (!cleanText.contains('<r>')) {
      return TextSpan(children: [TextSpan(text: cleanText, style: baseStyle)]);
    }

    final spans = <InlineSpan>[];
    final redStyle = baseStyle.copyWith(color: Colors.red);
    final regExp = RegExp(r'<r>(.*?)</r>', dotAll: true);

    int lastMatchEnd = 0;
    for (final match in regExp.allMatches(cleanText)) {
      // Add text before the current match
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
            text: cleanText.substring(lastMatchEnd, match.start),
            style: baseStyle));
      }
      // Add the red text, using group(1) to get the content inside the tags
      spans.add(TextSpan(
        text: match.group(1) ??
            '!!! RedLetterParser.parseRedLetterText RegExp Error !!!',
        style: redStyle,
      ));
      lastMatchEnd = match.end;
    }

    // Add any remaining text after the last match
    if (lastMatchEnd < cleanText.length) {
      spans.add(TextSpan(
          text: cleanText.substring(lastMatchEnd),
          style: baseStyle,
          spellOut: false));
    }

    return TextSpan(children: spans);
  }

  /// Strips all red-letter tags from the text, returning plain text.
  static String stripRedLetterTags(String text) {
    if (!text.contains('<r>')) return text;
    return text.replaceAll('<r>', '').replaceAll('</r>', '');
  }
}
