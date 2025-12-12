import 'package:flutter/material.dart';
import 'dart:math';
import '../utils/verse_text_parser.dart';
import '../utils/highlight_text_color_adjustments.dart';
import '../main.dart'; // For global notifiers and colors
import '../utils/preferences_constants.dart';
import '../widgets/html_note_display.dart';
import '../utils/bible_utils.dart';
import '../utils/font_size_adjustments.dart';

/// Utility functions for displaying verses with notes and highlights
/// Extracted from bible_screen.dart for reusability

/// Builds a verse display widget with support for notes, highlights, and interactions
Widget buildVerseDisplayWidget({
  required BuildContext context,
  required int verseNumber,
  required String rawVerseText,
  required TextStyle baseTextStyle,
  required Color backgroundColor,
  required Map<String, dynamic> noteForVerse,
  required List<Map<String, dynamic>> highlightsForVerse,
  required bool showNotesInline,
  required String fontFamily,
  required Color lightModeTextColor,
  required Color darkModeTextColor,
  required Function(int)? onVerseTap,
  required Function(int)? onVerseLongPress,
  required Function(String, String?)? onLinkTap,
  required GlobalKey? verseKey,
  required Function(int, String?)? onNoteIconTap,
  double? verseNumberWidth,
  Color? customBackgroundColor,
}) {
  // Determine whether it's a dark theme or not
  final isDark = Theme.of(context).brightness == Brightness.dark;

  //String cleanVerseText = rawVerseText.replaceAll('¶ ', '');

  // Use provided verse number width or default
  final effectiveVerseNumberWidth = verseNumberWidth ?? 40.0;

  // Build the right column spans (verse text with highlights)
  final rightSpans = <InlineSpan>[];

  // Only show icon inline in verse if not showNotesInline and note exists
  if (!showNotesInline && noteForVerse.isNotEmpty) {
    rightSpans.add(WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.only(right: 8.0), // add a little space between the icon and the text
        child: GestureDetector(
          onTap: onNoteIconTap != null ? () => onNoteIconTap(verseNumber, noteForVerse['note_text']) : null,
          child: Icon(
            Icons.text_snippet_outlined,
            size: FontSizeAdjustments.getAdjustedSize(fontFamilyNotifier.value, fontSizeNotifier.value),
            color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
            semanticLabel: 'Verse note',
          ),
        ),
      ),
    ));
  }

  // Apply highlights to the verse text
  final highlightedSpans = applyHighlightsToText(
    rawVerseText,
    rawVerseText, //cleanVerseText,
    baseTextStyle,
    verseNumber,
    backgroundColor,
    highlightsForVerse,
    lightModeTextColor,
    darkModeTextColor,
  );
  rightSpans.addAll(highlightedSpans);

  // Each verse is a GestureDetector with Row to enable tap and long press
  return GestureDetector(
    onTap: onVerseTap != null ? () => onVerseTap(verseNumber) : null,
    onLongPress: onVerseLongPress != null ? () => onVerseLongPress(verseNumber) : null,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left column: verse number with fixed width
        Container(
          width: effectiveVerseNumberWidth,
          alignment: Alignment.centerRight,
          child: verseKey != null
              ? Container(
                  key: verseKey,
                  child: Text(
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    '$verseNumber',
                    style: baseTextStyle.copyWith(
                      fontSize: baseTextStyle.fontSize! - 2,
                      color: (isDark ? darkPrimaryColor.value : lightPrimaryColor.value).withValues(alpha: 0.8),
                      fontWeight: FontWeight.normal,
                    ),
                    //textHeightBehavior: const TextHeightBehavior(
                    //  applyHeightToFirstAscent: false,
                    //  applyHeightToLastDescent: false,
                    //  leadingDistribution: TextLeadingDistribution.even,
                    //),
                  ))
              : Text(
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  '$verseNumber',
                  style: baseTextStyle.copyWith(
                    fontSize: baseTextStyle.fontSize! - 2,
                    color: (isDark ? darkPrimaryColor.value : lightPrimaryColor.value).withValues(alpha: 0.8),
                    fontWeight: FontWeight.normal,
                  ),
                  //textHeightBehavior: const TextHeightBehavior(
                  //  applyHeightToFirstAscent: false,
                  //  applyHeightToLastDescent: false,
                  //  leadingDistribution: TextLeadingDistribution.even,
                  //),
                ),
        ),
        const SizedBox(width: 8),
        // Right column: verse text with inline icon
        Expanded(
          child: Container(
            //padding: EdgeInsets.all(4.0),
            //margin: EdgeInsets.all(0),
            decoration: BoxDecoration(
              color: customBackgroundColor,
              //borderRadius: BorderRadius.circular(8.0),
            ),
            child: RichText(
              softWrap: true,
              text: TextSpan(
                style: baseTextStyle,
                children: rightSpans,
              ),
              //textHeightBehavior: const TextHeightBehavior(
              //  applyHeightToFirstAscent: false,
              //  applyHeightToLastDescent: false,
              //  leadingDistribution: TextLeadingDistribution.even,
              //),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Applies highlights to verse text by creating spans with background colors
/// Returns list of spans that can be used in a RichText widget
List<InlineSpan> applyHighlightsToText(
  String rawVerseText,
  String cleanVerseText,
  TextStyle baseStyle,
  int verseNumber,
  Color backgroundColor,
  List<Map<String, dynamic>> highlights,
  Color lightModeTextColor,
  Color darkModeTextColor,
) {
  // If no highlights, just parse the text normally
  if (highlights.isEmpty) {
    return VerseTextParser.parseVerseText(cleanVerseText, baseStyle).children ?? [];
  }

  // Parse the clean verse text to get the original spans (including <r> tags)
  final parsedVerseText = VerseTextParser.parseVerseText(cleanVerseText, baseStyle);
  final originalSpans = parsedVerseText.children ?? [];

  // Convert highlight positions from raw text to clean text positions
  final adjustedHighlights = <Map<String, dynamic>>[];
  for (final highlight in highlights) {
    final rawStart = highlight['start'] as int;
    final rawEnd = highlight['end'] as int;

    // Convert raw positions to clean positions
    final cleanStart = convertRawPositionToClean(rawVerseText, rawStart);
    final cleanEnd = convertRawPositionToClean(rawVerseText, rawEnd);

    if (cleanStart >= 0 && cleanEnd > cleanStart) {
      adjustedHighlights.add({
        'start': cleanStart,
        'end': cleanEnd,
        'color': highlight['color'],
      });
    }
  }

  // Sort highlights by start position
  adjustedHighlights.sort((a, b) => (a['start'] as int).compareTo(b['start'] as int));

  final spans = <InlineSpan>[];
  int currentPosition = 0;

  for (final highlight in adjustedHighlights) {
    final start = highlight['start'] as int;
    final end = highlight['end'] as int;
    final color = Color(highlight['color'] as int);

    // Add unhighlighted spans before this highlight
    if (start > currentPosition) {
      final beforeSpans = extractSpansForRange(originalSpans, currentPosition, start, baseStyle);
      spans.addAll(beforeSpans);
    }

    // Calculate the effective highlight background
    final effectiveHighlightBackground = color.withValues(alpha: defaultHighlightAlpha);

    // Add highlighted spans
    final highlightSpans = extractSpansForRange(originalSpans, start, end, baseStyle);
    for (final span in highlightSpans) {
      if (span is TextSpan) {
        // Get the original text color from the span or base style
        final originalTextColor = span.style?.color ?? baseStyle.color ?? Colors.black;

        // Check if we need to adjust the text color for contrast using the passed parameters
        final adjustedTextColor = adjustTextColorForHighlight(
          originalTextColor,
          effectiveHighlightBackground,
          darkModeTextColor,
          lightModeTextColor,
        );

        spans.add(TextSpan(
          text: span.text,
          style: span.style?.copyWith(
                backgroundColor: color.withValues(alpha: defaultHighlightAlpha),
                color: adjustedTextColor,
              ) ??
              baseStyle.copyWith(
                backgroundColor: color.withValues(alpha: defaultHighlightAlpha),
                color: adjustedTextColor,
              ),
        ));
      } else {
        spans.add(span);
      }
    }

    currentPosition = end;
  }

  // Add remaining unhighlighted spans
  if (currentPosition < cleanVerseText.length) {
    final remainingSpans = extractSpansForRange(originalSpans, currentPosition, cleanVerseText.length, baseStyle);
    spans.addAll(remainingSpans);
  }

  return spans;
}

/// Helper method to extract spans for a specific character range from parsed text
List<InlineSpan> extractSpansForRange(List<InlineSpan> originalSpans, int start, int end, TextStyle baseStyle) {
  final extractedSpans = <InlineSpan>[];
  int currentPosition = 0;

  for (final span in originalSpans) {
    if (span is TextSpan) {
      final spanText = span.text ?? '';
      final spanLength = spanText.length;

      // Check if this span overlaps with our desired range
      final spanStart = currentPosition;
      final spanEnd = currentPosition + spanLength;

      // If span is completely before our range, skip it
      if (spanEnd <= start) {
        currentPosition += spanLength;
        continue;
      }

      // If span is completely after our range, we're done
      if (spanStart >= end) {
        break;
      }

      // Calculate the overlap
      final overlapStart = max(start, spanStart);
      final overlapEnd = min(end, spanEnd);

      if (overlapStart < overlapEnd) {
        // Extract the overlapping portion of this span
        final extractedText = spanText.substring(overlapStart - spanStart, overlapEnd - spanStart);

        // If extracted text contains <r> tags, re-parse it to handle them correctly
        if (extractedText.contains('<r>') || extractedText.contains('</r>')) {
          final reParsed = VerseTextParser.parseVerseText(extractedText, baseStyle);
          if (reParsed.children != null) {
            extractedSpans.addAll(reParsed.children!);
          }
        } else {
          // No <r> tags, use the original span style
          extractedSpans.add(TextSpan(
            text: extractedText,
            style: span.style,
          ));
        }
      }

      currentPosition += spanLength;

      // If we've reached the end of our range, we're done
      if (currentPosition >= end) {
        break;
      }
    } else {
      // For non-TextSpan widgets, include them if they're in range
      if (currentPosition >= start && currentPosition < end) {
        extractedSpans.add(span);
      }
      // WidgetSpans don't contribute to character position
    }
  }

  return extractedSpans;
}

/// Convert a position in clean text to raw text position
int convertCleanPositionToRaw(String rawText, int cleanPosition) {
  if (cleanPosition <= 0) return 0;

  // Handle red letter and pilcrow filtering
  final openingRedTagRegex = RegExp(r'<r>');
  final closingRedTagRegex = RegExp(r'</r>');

  if (cleanPosition >= rawText.length) {
    return rawText.length;
  }

  // Find the character at the clean position and locate it in the raw text
  int rawPosition = 0;
  int cleanCharsFound = 0;

  for (int i = 0; i < rawText.length && cleanCharsFound < cleanPosition; i++) {
    final remainingText = rawText.substring(i);

    // Check if this character is part of an opening <r> tag
    if (openingRedTagRegex.hasMatch(rawText[i])) {
      final match = openingRedTagRegex.matchAsPrefix(remainingText);
      if (match != null) {
        i += match.end - 1; // -1 because loop will increment i
        continue;
      }
    }
    // Check if this character is part of a closing </r> tag
    else if (closingRedTagRegex.hasMatch(rawText[i])) {
      final match = closingRedTagRegex.matchAsPrefix(remainingText);
      if (match != null) {
        i += match.end - 1; // -1 because loop will increment i
        continue;
      }
    }
    // Check if this is a pilcrow
    // else if (rawText[i] == '¶' && i + 1 < rawText.length && rawText[i + 1] == ' ') {
    //   i += 1; // skip the space
    //   continue;
    // }

    // Regular character - count it
    cleanCharsFound++;
    rawPosition = i + 1;
  }

  return rawPosition;
}

/// Convert a position in raw text to clean text position
int convertRawPositionToClean(String rawText, int rawPosition) {
  if (rawPosition <= 0) return 0;

  // Handle red letter and pilcrow filtering
  final openingRedTagRegex = RegExp(r'<r>');
  final closingRedTagRegex = RegExp(r'</r>');

  if (rawPosition >= rawText.length) {
    // Calculate what the clean position would be at the end of the text
    String tempText = rawText.replaceAll(openingRedTagRegex, '');
    tempText = tempText.replaceAll(closingRedTagRegex, '');
    //tempText = tempText.replaceAll('¶ ', '');
    return tempText.length;
  }

  // Count characters in clean text up to the raw position
  int cleanPosition = 0;
  for (int i = 0; i < rawPosition && i < rawText.length; i++) {
    final remainingText = rawText.substring(i);

    // Skip <r> tags - they don't count in clean position
    if (openingRedTagRegex.hasMatch(rawText[i])) {
      final match = openingRedTagRegex.matchAsPrefix(remainingText);
      if (match != null) {
        i += match.end - 1; // -1 because loop will increment i
        continue;
      }
    }
    // Skip </r> tags - they don't count in clean position
    else if (closingRedTagRegex.hasMatch(rawText[i])) {
      final match = closingRedTagRegex.matchAsPrefix(remainingText);
      if (match != null) {
        i += match.end - 1; // -1 because loop will increment i
        continue;
      }
    }
    // Skip pilcrow symbols - they don't count in clean position
    // else if (rawText[i] == '¶' && i + 1 < rawText.length && rawText[i + 1] == ' ') {
    //   i += 1; // skip the space
    //   continue;
    // }

    cleanPosition++;
  }

  return cleanPosition;
}

/// Calculate dynamic width for verse number column based on verses in a list
/// This ensures the verse number column is sized appropriately for the maximum verse number
double calculateVerseNumberWidth(List<Map<String, dynamic>> verses, TextStyle numStyle) {
  int maxVerseNumber = 0;
  for (final verse in verses) {
    final verseNum = toInt(verse['verse'], orElse: 0);
    if (verseNum > maxVerseNumber) {
      maxVerseNumber = verseNum;
    }
  }

  // Create a string with enough characters for the max verse number
  final maxDigits = maxVerseNumber.toString().length;
  final sampleText = '9' * maxDigits; // e.g., "99" for 2-digit, "999" for 3-digit

  final textPainter = TextPainter(
    text: TextSpan(text: sampleText, style: numStyle),
    maxLines: 1,
    textDirection: TextDirection.ltr,
  )..layout();
  return textPainter.size.width + 5.0;
}

/// Builds a list of verse widgets with common display logic
/// Consolidated from bible_screen.dart and chapter_dialog.dart to eliminate duplication
List<Widget> buildVerseListWidget({
  required BuildContext context,
  required List<Map<String, dynamic>> verses,
  required Map<int, GlobalKey> verseKeys,
  required Map<int, Map<String, dynamic>> notes,
  required Map<int, List<Map<String, dynamic>>> highlights,
  required Color textColor,
  required Color verseNumberColor,
  required Color backgroundColor,
  required double lineHeight,
  required bool showNotesInline,
  required String fontFamily,
  required Color lightHighlightTextColor,
  required Color darkHighlightTextColor,
  required Function(int)? onVerseTap,
  required Function(int)? onVerseLongPress,
  required Function(String, String?)? onLinkTap,
  required ValueNotifier<Color> lightVerseReferenceColor,
  required ValueNotifier<Color> darkVerseReferenceColor,
  required Function(int, String?)? onNoteIconTap,
  required Function(int, String?)? onNoteEditTap,
  List<int> highlightedVerses = const [],
  Color highlightedVerseBackgroundColor = Colors.transparent,
}) {
  final widgets = <Widget>[];
  bool pilcrowSeen = false;

  // Different styles whether it is the verse number or the text itself
  final numStyle = TextStyle(
    fontSize: FontSizeAdjustments.getAdjustedSize(fontFamily, fontSizeNotifier.value),
    fontFamily: fontFamily,
    color: verseNumberColor,
    fontWeight: FontWeight.normal,
    height: lineHeight,
  );
  final textStyle = TextStyle(
    fontSize: FontSizeAdjustments.getAdjustedSize(fontFamily, fontSizeNotifier.value),
    fontFamily: fontFamily,
    color: textColor,
    height: lineHeight,
  );

  // Calculate dynamic width for verse number column based on current chapter's verses
  final verseNumberWidth = calculateVerseNumberWidth(verses, numStyle);

  for (final verse in verses) {
    final vn = toInt(verse['verse'], orElse: 0);
    if (vn <= 0) continue;

    String rawVerseText = verse['text'];

    final hasPilcrow = rawVerseText.contains('¶');

    // Add paragraph break before verse if it's a new section (has a pilcrow)
    final addParagraphBreak = (pilcrowSeen && hasPilcrow);
    if (hasPilcrow && !pilcrowSeen) {
      pilcrowSeen = true;
    }

    if (addParagraphBreak) {
      widgets.add(const SizedBox(height: 16));
    }

    final customBgColor = highlightedVerses.contains(vn) ? highlightedVerseBackgroundColor : null;

    // Use the shared verse display widget
    final verseWidget = buildVerseDisplayWidget(
      context: context,
      verseNumber: vn,
      rawVerseText: rawVerseText,
      baseTextStyle: textStyle,
      backgroundColor: backgroundColor,
      noteForVerse: notes[vn] ?? {},
      highlightsForVerse: highlights[vn] ?? [],
      showNotesInline: showNotesInline,
      fontFamily: fontFamily,
      lightModeTextColor: lightHighlightTextColor,
      darkModeTextColor: darkHighlightTextColor,
      onVerseTap: onVerseTap,
      onVerseLongPress: onVerseLongPress,
      onLinkTap: onLinkTap,
      verseKey: verseKeys[vn],
      onNoteIconTap: onNoteIconTap,
      verseNumberWidth: verseNumberWidth,
      customBackgroundColor: customBgColor,
    );

    widgets.add(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          verseWidget,
          //SizedBox(height: lineHeight),
        ],
      ),
    );

    // If showNotesInline, display note content below the verse
    if (showNotesInline && notes.containsKey(vn)) {
      final noteText = notes[vn]!['note_text'] as String? ?? '';
      if (noteText.isNotEmpty) {
        widgets.add(
          Container(
            margin: EdgeInsets.only(left: 80.0, right: 16.0, top: 8.0, bottom: 8.0),
            padding: EdgeInsets.all(0.0),
            child: GestureDetector(
              onTap: onNoteEditTap != null ? () => onNoteEditTap(vn, noteText) : null,
              behavior: HitTestBehavior.translucent,
              child: HtmlNoteDisplay(
                noteText: noteText,
                onLinkTap: onLinkTap,
              ),
            ),
          ),
        );
      }
    }
  }

  return widgets;
}
