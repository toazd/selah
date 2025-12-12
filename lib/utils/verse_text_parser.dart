import 'package:flutter/material.dart';

class VerseTextParser {
  static TextSpan parseVerseText(String text, TextStyle baseStyle) {
    // if (kDebugMode) {
    //   debugPrint('parseVerseText called\ntext: $text\nTextStyle: $baseStyle');
    // }

    // Performance optimization: early exit if no red letter tags
    if (!text.contains('<r>')) {
      return TextSpan(children: [TextSpan(text: text, style: baseStyle)]);
    }

    String cleanText = text;
    // Remove pilcrow symbols
    // if (text.contains('¶ ')) {
    //   cleanText = text.replaceAll('¶ ', '');
    // } else {
    //   cleanText = text;
    // }

    final spans = <InlineSpan>[];
    final redStyle = baseStyle.copyWith(color: Colors.red);
    final regExp = RegExp(r'<r>(.*?)</r>', dotAll: true);

    int lastMatchEnd = 0;
    for (final match in regExp.allMatches(cleanText)) {
      // Add text before the current match
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(text: cleanText.substring(lastMatchEnd, match.start), style: baseStyle));
      }
      // Add the red text, using group(1) to get the content inside the tags
      spans.add(TextSpan(
        text: match.group(1) ?? '!!! VerseTextParser.parseVerseText RegExp Matching Error !!!',
        style: redStyle,
      ));
      lastMatchEnd = match.end;
    }

    // Add any remaining text after the last match
    if (lastMatchEnd < cleanText.length) {
      spans.add(TextSpan(text: cleanText.substring(lastMatchEnd), style: baseStyle, spellOut: false));
    }

    return TextSpan(children: spans);
  }
}
