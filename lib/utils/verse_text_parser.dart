import 'package:material_ui/material_ui.dart';

class VerseTextParser {
  static final RegExp _markupTokenRegex = RegExp(
    r'<r>|</r>|<i>|</i>',
    caseSensitive: false,
  );

  static final RegExp _italicsTagRegex = RegExp(
    r'</?i>',
    caseSensitive: false,
  );

  /// Strips all red-letter tags from the text, returning plain text.
  static String stripRedLetterTags(String text) {
    if (!text.contains('<r>')) return text;
    return text.replaceAll('<r>', '').replaceAll('</r>', '');
  }

  /// Strips all italics tags from the text, returning plain text.
  /// Tags are removed without adding spaces so highlight offsets stay stable.
  static String stripItalicsTags(String text) {
    if (!_italicsTagRegex.hasMatch(text)) return text;
    return text.replaceAll(_italicsTagRegex, '');
  }

  /// Parses verse text handling red-letter and italics tags.
  ///
  /// [text] - The raw verse text which may contain `<r>` and/or `<i>` tags.
  /// [baseStyle] - The base TextStyle for unstyled portions.
  static TextSpan parseVerseText(
    String text,
    TextStyle baseStyle,
  ) {
    if (!text.contains('<r>') && !text.contains('<i>')) {
      return TextSpan(
        children: [TextSpan(text: text, style: baseStyle)],
      );
    }

    final spans = <InlineSpan>[];
    final redStyle = baseStyle.copyWith(color: Colors.red);
    var lastEnd = 0;
    var isRed = false;
    var isItalic = false;

    TextStyle currentStyle() {
      var style = isRed ? redStyle : baseStyle;
      if (isItalic) style = style.copyWith(fontStyle: FontStyle.italic);
      return style;
    }

    void addText(String value) {
      if (value.isEmpty) return;
      spans.add(TextSpan(text: value, style: currentStyle()));
    }

    for (final match in _markupTokenRegex.allMatches(text)) {
      addText(text.substring(lastEnd, match.start));

      final lowerToken = match.group(0)!.toLowerCase();
      if (lowerToken == '<r>') {
        isRed = true;
      } else if (lowerToken == '</r>') {
        isRed = false;
      } else if (lowerToken == '<i>') {
        isItalic = true;
      } else if (lowerToken == '</i>') {
        isItalic = false;
      }

      lastEnd = match.end;
    }

    addText(text.substring(lastEnd));
    return TextSpan(children: spans);
  }

  /// Removes display markup from a verse while keeping the readable words.
  static String toPlainVerseText(
    String text, {
    bool removePilcrow = true,
    bool trim = false,
  }) {
    var result = stripRedLetterTags(text);
    result = stripItalicsTags(result);
    if (removePilcrow) {
      result = result.replaceAll('¶ ', '').replaceAll('¶', '');
    }
    return trim ? result.trim() : result;
  }
}
