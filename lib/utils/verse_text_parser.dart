import 'package:material_ui/material_ui.dart';
import 'package:selah/utils/highlight_text_color_adjustments.dart';
import 'package:selah/utils/preferences_constants.dart';

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
  /// [expandStrongsTapTarget] - If true, whitespace below superscripts also
  /// triggers the Strong's tap handler.
  /// [onStrongsTap] - Optional callback when a Strong's number is tapped.
  static TextSpan parseVerseText(
    String text,
    TextStyle baseStyle, {
    bool showStrongsNumbers = false,
    Color strongsColor = Colors.blue,
    Color tvmColor = const Color(0xFF8B4513),
    bool expandStrongsTapTarget = false,
    void Function(String strongsNumber)? onStrongsTap,
  }) {
    final displayText =
        showStrongsNumbers ? text : _removeSpaceAfterLeadingStrongsTags(text);

    if (!displayText.contains('<r>') && !hasStrongsTags(displayText)) {
      return TextSpan(
        children: [TextSpan(text: displayText, style: baseStyle)],
      );
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

    for (final match in _markupTokenRegex.allMatches(displayText)) {
      addText(displayText.substring(lastEnd, match.start));

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
          baseStyle: baseStyle,
          baseFontSize: baseStyle.fontSize ?? defaultFontSize,
          expandTapTarget: expandStrongsTapTarget,
        ));
        previousInlineStrong = true;
      }

      lastEnd = match.end;
    }

    addText(displayText.substring(lastEnd));
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
    required Color lightModeTextColor,
    required Color darkModeTextColor,
    required Color strongsColor,
    Color tvmColor = const Color(0xFF8B4513),
    bool expandStrongsTapTarget = false,
    void Function(String strongsNumber)? onStrongsTap,
  }) {
    if (matchedStrongs.isEmpty) {
      return TextSpan(text: toPlainVerseText(text), style: baseStyle);
    }

    final normalizedMatched =
        matchedStrongs.map((sn) => sn.toUpperCase()).toSet();
    final spans = <InlineSpan>[];
    final redStyle = baseStyle.copyWith(color: Colors.red);
    final effectiveHighlightBackground =
        highlightColor.withValues(alpha: defaultHighlightAlpha);

    TextStyle highlightedStyle(TextStyle sourceStyle) {
      final adjustedTextColor = adjustTextColorForHighlight(
        sourceStyle.color ?? baseStyle.color ?? Colors.black,
        effectiveHighlightBackground,
        darkModeTextColor,
        lightModeTextColor,
      );
      return sourceStyle.copyWith(
        backgroundColor: effectiveHighlightBackground,
        color: adjustedTextColor,
      );
    }

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
        baseStyle: baseStyle,
        baseFontSize: baseStyle.fontSize ?? defaultFontSize,
        expandTapTarget: expandStrongsTapTarget,
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
            style: highlightedStyle(isRed ? redStyle : baseStyle),
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
            _highlightPreviousTextSpan(
              spans,
              baseStyle,
              highlightedStyle,
            );
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

  /// Formats a verse for copying, inserting each Strong's number after the word
  /// it annotates, e.g. `Then{G1161} the eleven{G1733}` becomes
  /// `Then G1161 the eleven G1733`.
  ///
  /// TVM codes (e.g. `{{G5675}}`) are included alongside the regular Strong's
  /// numbers, while red letter tags and the pilcrow are removed.
  ///
  /// [perLine] - When true, leading Strong's tags are hoisted per
  /// newline-separated line instead of only at the start of [text]. Use this
  /// for multi-verse payloads (e.g. nearby search results) where a verse can
  /// begin in the middle of the string.
  static String toStrongsAnnotatedVerseText(
    String text, {
    bool perLine = false,
  }) {
    var result = stripRedLetterTags(text);
    result = result.replaceAll('¶ ', '').replaceAll('¶', '');

    if (perLine) {
      return result
          .split('\n')
          .map(_annotateVerseNumberPrefixedLine)
          .join('\n');
    }
    return _annotateStrongsInLine(result);
  }

  /// Annotates a single line that carries a leading verse number, such as the
  /// `28 ` prefix used on every line of a nearby search result. The prefix is
  /// kept in front of the line so a verse's leading Strong's tags stay attached
  /// to their own verse rather than to the previous one.
  static String _annotateVerseNumberPrefixedLine(String line) {
    final prefix = _verseNumberPrefixRegex.firstMatch(line);
    if (prefix == null) return _annotateStrongsInLine(line);
    return prefix.group(0)! +
        _annotateStrongsInLine(line.substring(prefix.end));
  }

  /// Matches a leading verse number plus its trailing space, e.g. `28 `.
  static final RegExp _verseNumberPrefixRegex = RegExp(r'^\d+\s+');

  /// Inlines Strong's numbers into a single line of verse text.
  static String _annotateStrongsInLine(String text) {
    // Strong's tags that precede the first word annotate the verse as a whole,
    // so hoist them in front of it rather than gluing them onto that word.
    final leadingTags = StringBuffer();
    var body = text.trimLeft();
    var match = _strongTagRegex.matchAsPrefix(body);
    while (match != null) {
      leadingTags.write('${_normalizeStrongsToken(match.group(0)!)} ');
      body = body.substring(match.end).trimLeft();
      match = _strongTagRegex.matchAsPrefix(body);
    }

    final annotated = body.replaceAllMapped(
      _strongTagRegex,
      (match) => ' ${_normalizeStrongsToken(match.group(0)!)}',
    );

    return '$leadingTags$annotated'.trim();
  }

  /// Converts a Strong's tag token (`{G1161}` or `{{G5675}}`) to its display
  /// number (`G1161` / `G5675`).
  static String _normalizeStrongsToken(String token) {
    return token.replaceAll(RegExp(r'[{}]'), '').toUpperCase();
  }

  static WidgetSpan _buildStrongsSuperscript({
    required String token,
    required Color strongsColor,
    required Color tvmColor,
    required void Function(String strongsNumber)? onStrongsTap,
    required TextStyle baseStyle,
    required double baseFontSize,
    bool expandTapTarget = false,
  }) {
    final isTvm = token.startsWith('{{');
    final strongsNumber = _normalizeStrongsToken(token);
    final color = isTvm ? tvmColor : strongsColor;
    final superscriptOffset = baseFontSize * 0.5;
    final text = Text(
      strongsNumber,
      // Without the following, system font scaling above 1.00 causes the strongs
      // numbers to receive "duplicate" scaling and they become disproportionately
      // larger than the verse text
      textScaler: TextScaler.noScaling,
      style: baseStyle.copyWith(
        fontSize: baseFontSize * 0.8,
        color: color,
      ),
    );

    Widget child = Transform.translate(
      offset: Offset(0, -superscriptOffset),
      child: text,
    );
    if (expandTapTarget) {
      child = Padding(
        padding: EdgeInsets.only(top: superscriptOffset),
        child: child,
      );
    }
    if (onStrongsTap != null) {
      child = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: expandTapTarget
              ? HitTestBehavior.opaque
              : HitTestBehavior.deferToChild,
          onTap: () => onStrongsTap(strongsNumber),
          child: child,
        ),
      );
    }

    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: child,
    );
  }

  /// Strips all Strong's and TVM tags from the text, returning clean text.
  static String stripStrongsTags(String text) {
    String result = _removeSpaceAfterLeadingStrongsTags(text);
    result = result.replaceAll(_tvmRegex, '');
    result = result.replaceAll(_strongTagRegex, '');
    return result;
  }

  /// Removes the single display space after Strong's tags at the text boundary.
  static String _removeSpaceAfterLeadingStrongsTags(String text) {
    var tagEnd = 0;
    var match = _strongTagRegex.matchAsPrefix(text, tagEnd);
    if (match == null) return text;

    while (match != null) {
      tagEnd = match.end;
      match = _strongTagRegex.matchAsPrefix(text, tagEnd);
    }

    if (tagEnd < text.length && text.codeUnitAt(tagEnd) == 0x20) {
      return text.replaceRange(tagEnd, tagEnd + 1, '');
    }
    return text;
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
    final strongsNumber = _normalizeStrongsToken(token);
    return _StrongTag(rawTag: token, strongsNumber: strongsNumber);
  }

  static void _highlightPreviousTextSpan(
    List<InlineSpan> spans,
    TextStyle baseStyle,
    TextStyle Function(TextStyle) highlightedStyle,
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
        style: highlightedStyle(span.style ?? baseStyle),
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
