import 'package:flutter/material.dart';

/// Regex for regular Strong's numbers: {H1234} or {G5678}
final RegExp strongsRegex = RegExp(r'\{[GH]\d{1,4}\}', caseSensitive: false);

/// Regex for TVM (tense/voice/mood) codes: {{H8804}} or {{G1234}}
final RegExp tvmRegex = RegExp(r'\{\{[GH]\d{1,4}\}\}', caseSensitive: false);

/// Regex for any Strong's marker, with TVM markers matched before regular ones.
final RegExp anyStrongsTagRegex =
    RegExp(r'\{\{[GH]\d{1,4}\}\}|\{[GH]\d{1,4}\}', caseSensitive: false);

/// Utility for parsing Strong's numbers and TVM codes from verse text.
///
/// Handles the format where Strong's tags appear consecutively after the word
/// they represent, e.g.: `created{H1254}{H853}{{H8804}}`
class StrongsTextParser {
  /// Parses verse text and returns a list of InlineSpans with clickable
  /// Strong's numbers as superscripts.
  ///
  /// [text] - The raw verse text containing Strong's and/or TVM tags.
  /// [baseStyle] - The base text style for unstyled portions.
  /// [strongsColor] - Color for regular Strong's number superscripts.
  /// [tvmColor] - Color for TVM code superscripts (slightly different from strongsColor).
  /// [onStrongsTap] - Callback when a Strong's number is tapped.
  /// [baseFontSize] - The base font size for calculating superscript offset.
  ///
  /// This does NOT handle red-letter tags; those are expected to be applied
  /// afterward by RedLetterParser.
  static List<InlineSpan> parseStrongsText({
    required String text,
    required TextStyle baseStyle,
    required Color strongsColor,
    required Color tvmColor,
    required void Function(String strongsNumber) onStrongsTap,
    required double baseFontSize,
  }) {
    final spans = <InlineSpan>[];
    int lastEnd = 0;

    // Token pattern: match word groups followed by consecutive Strong's/TVM tags,
    // OR standalone tags, OR any single character
    //
    // Group 1: Word(s) — sequence of word characters, apostrophes, hyphens
    // Group 2: Consecutive Strong's/TVM tags following the words
    //
    // The alternation handles:
    //   a) words + tags: `created{H1254}{H853}{{H8804}}`
    //   b) standalone tag: `{H1234}` with no preceding words
    //   c) any other single character (punctuation, space, etc.)
    final tokenPattern = RegExp(
      r"([A-Za-z'\-]+(?:\s+[A-Za-z'\-]+)*)"
      r"((?:\s*\{[GH]\d{1,4}\}|\s*\{\{[GH]\d{1,4}\}\})+)"
      r"|"
      r"\{[GH]\d{1,4}\}|\{\{[GH]\d{1,4}\}\}"
      r"|"
      r".",
      caseSensitive: false,
    );

    for (final match in tokenPattern.allMatches(text)) {
      // Emit any text between matches
      if (match.start > lastEnd) {
        final between = text.substring(lastEnd, match.start);
        if (between.isNotEmpty) {
          spans.add(TextSpan(text: between, style: baseStyle));
        }
      }

      final wordsGroup = match.group(1);
      final tagGroup = match.group(2);

      if (wordsGroup != null && tagGroup != null) {
        // Pattern a): words followed by one or more consecutive Strong's/TVM tags
        spans.add(TextSpan(text: wordsGroup, style: baseStyle));
        spans.addAll(_buildTagsSpans(
          tagGroup: tagGroup,
          baseStyle: baseStyle,
          strongsColor: strongsColor,
          tvmColor: tvmColor,
          onStrongsTap: onStrongsTap,
          baseFontSize: baseFontSize,
        ));
      } else if (strongsRegex.hasMatch(match.group(0)!) ||
          tvmRegex.hasMatch(match.group(0)!)) {
        // Pattern b): standalone Strong's or TVM tag with no preceding words
        final tagText = match.group(0)!;
        spans.addAll(_buildSingleTagSpan(
          tagText: tagText,
          baseStyle: baseStyle,
          strongsColor: strongsColor,
          tvmColor: tvmColor,
          onStrongsTap: onStrongsTap,
          baseFontSize: baseFontSize,
        ));
      } else {
        // Pattern c): any other character
        spans.add(TextSpan(text: match.group(0), style: baseStyle));
      }

      lastEnd = match.end;
    }

    // Any remaining text after the last match
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd), style: baseStyle));
    }

    return spans;
  }

  /// Strips all Strong's and TVM tags from the text, returning clean text.
  static String stripStrongsTags(String text) {
    String result = text.replaceAll(tvmRegex, '');
    result = result.replaceAll(strongsRegex, '');
    return result;
  }

  /// Checks if text contains any Strong's or TVM tags.
  static bool hasStrongsTags(String text) {
    return strongsRegex.hasMatch(text) || tvmRegex.hasMatch(text);
  }

  /// Builds spans for one or more consecutive Strong's/TVM tags.
  static List<InlineSpan> _buildTagsSpans({
    required String tagGroup,
    required TextStyle baseStyle,
    required Color strongsColor,
    required Color tvmColor,
    required void Function(String strongsNumber) onStrongsTap,
    required double baseFontSize,
  }) {
    final spans = <InlineSpan>[];
    // Extract all individual tags from the group
    // Match either {{...}} or {...}, preferring {{...}} first due to order
    final tagRegex = RegExp(r'\{\{[GH]\d{1,4}\}\}|\{[GH]\d{1,4}\}');
    final tagMatches = tagRegex.allMatches(tagGroup).toList();

    for (int i = 0; i < tagMatches.length; i++) {
      // Add a space before each tag except the first one for readability
      if (i > 0) {
        spans.add(TextSpan(text: ' ', style: baseStyle));
      }

      final tagText = tagMatches[i].group(0)!;
      final isTvm = tagText.startsWith('{{');
      // Extract the number part (remove braces and prefix letter)
      final innerMatch = isTvm
          ? RegExp(r'\{\{([GH]\d{1,4})\}\}').firstMatch(tagText)
          : RegExp(r'\{([GH]\d{1,4})\}').firstMatch(tagText);
      final strongsNumber = innerMatch?.group(1)?.toUpperCase() ?? tagText;

      spans.add(_buildClickableSuperscript(
        strongsNumber: strongsNumber,
        color: isTvm ? tvmColor : strongsColor,
        onStrongsTap: onStrongsTap,
        baseFontSize: baseFontSize,
        baseStyle: baseStyle,
      ));
    }

    return spans;
  }

  /// Builds a single standalone tag span (when no preceding words).
  static List<InlineSpan> _buildSingleTagSpan({
    required String tagText,
    required TextStyle baseStyle,
    required Color strongsColor,
    required Color tvmColor,
    required void Function(String strongsNumber) onStrongsTap,
    required double baseFontSize,
  }) {
    final isTvm = tagText.startsWith('{{');
    final innerMatch = isTvm
        ? RegExp(r'\{\{([GH]\d{1,4})\}\}').firstMatch(tagText)
        : RegExp(r'\{([GH]\d{1,4})\}').firstMatch(tagText);
    final strongsNumber = innerMatch?.group(1)?.toUpperCase() ?? tagText;

    return [
      _buildClickableSuperscript(
        strongsNumber: strongsNumber,
        color: isTvm ? tvmColor : strongsColor,
        onStrongsTap: onStrongsTap,
        baseFontSize: baseFontSize,
        baseStyle: baseStyle,
      ),
    ];
  }

  /// Builds a clickable superscript WidgetSpan for a Strong's number or TVM code.
  static WidgetSpan _buildClickableSuperscript({
    required String strongsNumber,
    required Color color,
    required void Function(String strongsNumber) onStrongsTap,
    required double baseFontSize,
    required TextStyle baseStyle,
  }) {
    final adjustedFontSize = baseStyle.fontSize ?? baseFontSize;
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => onStrongsTap(strongsNumber),
          child: Transform.translate(
            offset: Offset(0, -adjustedFontSize * 0.5),
            child: Text(
              strongsNumber,
              style: TextStyle(
                fontSize: adjustedFontSize * 0.65,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
