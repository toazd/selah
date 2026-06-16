import 'package:flutter/material.dart';

class VerseTextParser {
  static final RegExp _markupTokenRegex = RegExp(
    r'<r>|</r>|\{\{[GH]\d{1,4}\}\}|\{[GH]\d{1,4}\}',
    caseSensitive: false,
  );

  /// Strips all red-letter tags from the text, returning plain text.
  static String stripRedLetterTags(String text) {
    if (!text.contains('<r>')) return text;
    return text.replaceAll('<r>', '').replaceAll('</r>', '');
  }

  /// Parses verse text handling red-letter tags and optionally Strong's numbers.
  ///
  /// [text] - The raw verse text which may contain `<r>` tags and/or Strong's tags.
  /// [baseStyle] - The base TextStyle for unstyled portions.
  /// [showStrongsNumbers] - If true, Strong's numbers are rendered as superscripts.
  /// [strongsColor] - Color for regular Strong's number superscripts.
  /// [tvmColor] - Color for TVM code superscripts.
  /// [onStrongsTap] - Optional callback when a Strong's number is tapped.
  static TextSpan parseVerseText(
    String text,
    TextStyle baseStyle, {
    bool showStrongsNumbers = false,
    Color strongsColor = Colors.blue,
    Color tvmColor = const Color(0xFF8B4513),
    void Function(String strongsNumber)? onStrongsTap,
  }) {
    if (!text.contains('<r>') && !hasStrongsTags(text)) {
      return TextSpan(children: [TextSpan(text: text, style: baseStyle)]);
    }

    final spans = <InlineSpan>[];
    final redStyle = baseStyle.copyWith(color: Colors.red);
    var lastEnd = 0;
    var isRed = false;
    var previousInlineStrong = false;

    void addText(String value) {
      if (value.isEmpty) return;
      spans.add(TextSpan(text: value, style: isRed ? redStyle : baseStyle));
      previousInlineStrong = false;
    }

    for (final match in _markupTokenRegex.allMatches(text)) {
      addText(text.substring(lastEnd, match.start));

      final token = match.group(0)!;
      final lowerToken = token.toLowerCase();
      if (lowerToken == '<r>') {
        isRed = true;
      } else if (lowerToken == '</r>') {
        isRed = false;
      } else if (showStrongsNumbers) {
        if (previousInlineStrong) {
          spans.add(TextSpan(text: ' ', style: baseStyle));
        }
        spans.add(_buildStrongsSuperscript(
          token: token,
          strongsColor: strongsColor,
          tvmColor: tvmColor,
          onStrongsTap: onStrongsTap,
          baseFontSize: baseStyle.fontSize ?? 22.0,
        ));
        previousInlineStrong = true;
      }

      lastEnd = match.end;
    }

    addText(text.substring(lastEnd));
    return TextSpan(children: spans);
  }

  /// Parses verse text for Strong's Search results.
  ///
  /// This path highlights the visible word/phrase associated with any matched
  /// Strong's number and displays the matched Strong's superscripts. It uses the
  /// same tag parsing and superscript builder as the regular Bible display path.
  static TextSpan parseMatchedStrongsVerseText({
    required String text,
    required TextStyle baseStyle,
    required Set<String> matchedStrongs,
    required Color highlightColor,
    required Color strongsColor,
    Color tvmColor = const Color(0xFF8B4513),
    void Function(String strongsNumber)? onStrongsTap,
  }) {
    if (matchedStrongs.isEmpty) {
      return TextSpan(text: toPlainVerseText(text), style: baseStyle);
    }

    final normalizedMatched =
        matchedStrongs.map((sn) => sn.toUpperCase()).toSet();
    final spans = <InlineSpan>[];
    final redStyle = baseStyle.copyWith(color: Colors.red);
    final tokenPattern = RegExp(
      r"([A-Za-z'\-]+(?:\s+[A-Za-z'\-]+)*)"
      r"((?:\s*(?:\{\{[GH]\d{1,4}\}\}|\{[GH]\d{1,4}\}))+)"
      r"|"
      r"<r>|</r>"
      r"|"
      r"\{\{[GH]\d{1,4}\}\}|\{[GH]\d{1,4}\}"
      r"|"
      r".",
      caseSensitive: false,
    );

    var isRed = false;
    var lastEnd = 0;

    void addText(String value) {
      if (value.isEmpty) return;
      spans.add(TextSpan(text: value, style: isRed ? redStyle : baseStyle));
    }

    void addStrongTag(_StrongTag tag) {
      spans.add(_buildStrongsSuperscript(
        token: tag.rawTag,
        strongsColor: strongsColor,
        tvmColor: tvmColor,
        onStrongsTap: onStrongsTap,
        baseFontSize: baseStyle.fontSize ?? 22.0,
      ));
    }

    for (final match in tokenPattern.allMatches(text)) {
      addText(text.substring(lastEnd, match.start));

      final token = match.group(0)!;
      final lowerToken = token.toLowerCase();
      final wordsGroup = match.group(1);
      final tagGroup = match.group(2);

      if (wordsGroup != null && tagGroup != null) {
        final tags = _extractStrongTags(tagGroup);
        final anyMatched =
            tags.any((tag) => normalizedMatched.contains(tag.strongsNumber));
        if (anyMatched) {
          spans.add(TextSpan(
            text: wordsGroup,
            style: (isRed ? redStyle : baseStyle).copyWith(
              backgroundColor: highlightColor,
            ),
          ));
          for (var i = 0; i < tags.length; i++) {
            if (i > 0) {
              spans.add(TextSpan(text: ' ', style: baseStyle));
            }
            addStrongTag(tags[i]);
          }
        } else {
          addText(wordsGroup);
        }
      } else if (lowerToken == '<r>') {
        isRed = true;
      } else if (lowerToken == '</r>') {
        isRed = false;
      } else {
        final strongTag = _parseStrongTag(token);
        if (strongTag != null) {
          if (normalizedMatched.contains(strongTag.strongsNumber)) {
            _highlightPreviousTextSpan(spans, baseStyle, highlightColor);
            addStrongTag(strongTag);
          }
        } else {
          addText(token);
        }
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
    var result = stripStrongsTags(text);
    result = stripRedLetterTags(result);
    if (removePilcrow) {
      result = result.replaceAll('¶ ', '').replaceAll('¶', '');
    }
    return trim ? result.trim() : result;
  }

  static WidgetSpan _buildStrongsSuperscript({
    required String token,
    required Color strongsColor,
    required Color tvmColor,
    required void Function(String strongsNumber)? onStrongsTap,
    required double baseFontSize,
  }) {
    final isTvm = token.startsWith('{{');
    final strongsNumber = token.replaceAll(RegExp(r'[{}]'), '').toUpperCase();
    final color = isTvm ? tvmColor : strongsColor;
    final text = Text(
      strongsNumber,
      style: TextStyle(
        fontSize: baseFontSize * 0.8,
        color: color,
      ),
    );

    final child = Transform.translate(
      offset: Offset(0, -baseFontSize * 0.5),
      child: onStrongsTap == null
          ? text
          : MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => onStrongsTap(strongsNumber),
                child: text,
              ),
            ),
    );

    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: child,
    );
  }

  /// Strips all Strong's and TVM tags from the text, returning clean text.
  static String stripStrongsTags(String text) {
    String result = text.replaceAll(_tvmRegex, '');
    result = result.replaceAll(_strongTagRegex, '');
    return result;
  }

  /// Checks if text contains any Strong's or TVM tags.
  static bool hasStrongsTags(String text) {
    return _strongTagRegex.hasMatch(text) || _tvmRegex.hasMatch(text);
  }

  /// Regex for any Strong's marker, with TVM markers matched before regular ones.
  static final RegExp _strongTagRegex = RegExp(
    r'\{\{[GH]\d{1,4}\}\}|\{[GH]\d{1,4}\}',
    caseSensitive: false,
  );

  /// Regex for TVM (tense/voice/mood) codes: {{H8804}} or {{G1234}}
  static final RegExp _tvmRegex =
      RegExp(r'\{\{[GH]\d{1,4}\}\}', caseSensitive: false);

  static List<_StrongTag> _extractStrongTags(String text) {
    return _strongTagRegex
        .allMatches(text)
        .map((match) => _parseStrongTag(match.group(0)!))
        .whereType<_StrongTag>()
        .toList();
  }

  static _StrongTag? _parseStrongTag(String token) {
    if (!_strongTagRegex.hasMatch(token)) return null;
    final strongsNumber = token.replaceAll(RegExp(r'[{}]'), '').toUpperCase();
    return _StrongTag(rawTag: token, strongsNumber: strongsNumber);
  }

  static void _highlightPreviousTextSpan(
    List<InlineSpan> spans,
    TextStyle baseStyle,
    Color highlightColor,
  ) {
    for (var i = spans.length - 1; i >= 0; i--) {
      final span = spans[i];
      if (span is! TextSpan ||
          span.text == null ||
          !RegExp(r'[A-Za-z0-9]').hasMatch(span.text!)) {
        continue;
      }

      spans[i] = TextSpan(
        text: span.text,
        style: (span.style ?? baseStyle).copyWith(
          backgroundColor: highlightColor,
        ),
      );

      if (i + 1 < spans.length) {
        final nextSpan = spans[i + 1];
        if (nextSpan is TextSpan &&
            nextSpan.text != null &&
            nextSpan.text!.trim().isEmpty) {
          spans.removeAt(i + 1);
        }
      }
      return;
    }
  }
}

class _StrongTag {
  final String rawTag;
  final String strongsNumber;

  const _StrongTag({
    required this.rawTag,
    required this.strongsNumber,
  });
}
