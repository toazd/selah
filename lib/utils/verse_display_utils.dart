import 'package:flutter/material.dart';
import 'dart:math';
import '../utils/verse_text_parser.dart';
import '../utils/highlight_text_color_adjustments.dart';
import '../main.dart'; // For global notifiers and colors
import '../utils/preferences_constants.dart';
import '../widgets/quill_note_display.dart';
import '../widgets/tsk_reference_display.dart';
import '../utils/bible_utils.dart';
import '../utils/font_size_adjustments.dart';
import '../models/verse_display_data.dart';

// const _verseTextHeightBehavior = TextHeightBehavior(
//   applyHeightToFirstAscent: true, //false,
//   applyHeightToLastDescent: true, //false,
//   leadingDistribution:
//       TextLeadingDistribution.proportional, //TextLeadingDistribution.even,
// );

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
  bool displayVerseNumber = true,
  bool showStrongsNumbers = false,
  void Function(String strongsNumber)? onStrongsTap,
}) {
  // Determine whether it's a dark theme or not
  final isDark = Theme.of(context).brightness == Brightness.dark;

  //String cleanVerseText = rawVerseText.replaceAll('¶ ', '');

  final verseNumberStyle = baseTextStyle.copyWith(
    // Verse number font size
    fontSize: baseTextStyle.fontSize! - 2,
    color:
        (isDark ? darkPrimaryColor.value : lightPrimaryColor.value).withValues(
      alpha: 0.9,
    ),
    fontWeight: FontWeight.normal,
  );

  // Use provided verse number width or default
  final effectiveVerseNumberWidth = verseNumberWidth ??
      _calculateSingleVerseNumberWidth(
        context,
        verseNumber.toString(),
        verseNumberStyle,
      );
  final textScaler = MediaQuery.textScalerOf(context);
  final verseStrutStyle = StrutStyle.fromTextStyle(
    baseTextStyle,
    forceStrutHeight: true,
  );

  // Build the right column spans (verse text with highlights)
  final rightSpans = <InlineSpan>[];

  // Only show icon inline in verse if not showNotesInline and note exists
  if (!showNotesInline && noteForVerse.isNotEmpty) {
    rightSpans.add(WidgetSpan(
      alignment: PlaceholderAlignment.bottom,
      child: Padding(
        padding: const EdgeInsets.only(
            right: 8.0), // add a little space between the icon and the text
        child: GestureDetector(
          onTap: onNoteIconTap != null
              ? () => onNoteIconTap(verseNumber, noteForVerse['note_text'])
              : null,
          child: Icon(
            applyTextScaling: true,
            Icons.text_snippet_outlined,
            size: FontSizeAdjustments.getAdjustedSize(
                fontFamilyNotifier.value, fontSizeNotifier.value - 2),
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
    showStrongsNumbers: showStrongsNumbers,
    onStrongsTap: onStrongsTap,
  );
  rightSpans.addAll(highlightedSpans);

  // Each verse is a GestureDetector with Row to enable tap and long press
  return GestureDetector(
    onTap: onVerseTap != null ? () => onVerseTap(verseNumber) : null,
    onLongPress:
        onVerseLongPress != null ? () => onVerseLongPress(verseNumber) : null,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left column: verse number with fixed width
        if (displayVerseNumber)
          Container(
            width: effectiveVerseNumberWidth,
            alignment: Alignment.bottomRight,
            child: verseKey != null
                ? Container(
                    key: verseKey,
                    child: RichText(
                      textAlign: TextAlign.right,
                      textScaler: textScaler,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      text: TextSpan(
                        text: '$verseNumber',
                        style: verseNumberStyle,
                      ),
                      //textHeightBehavior: _verseTextHeightBehavior,
                      strutStyle: verseStrutStyle,
                    ),
                  )
                : RichText(
                    textAlign: TextAlign.right,
                    textScaler: textScaler,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    text: TextSpan(
                      text: '$verseNumber',
                      style: verseNumberStyle,
                    ),
                    //textHeightBehavior: _verseTextHeightBehavior,
                    strutStyle: verseStrutStyle,
                  ),
          ),
        if (displayVerseNumber) const SizedBox(width: 8),
        // Right column: verse text with inline icon
        Expanded(
          child: Container(
            alignment: Alignment.topLeft,
            //padding: EdgeInsets.all(4.0),
            //margin: EdgeInsets.all(0),
            decoration: BoxDecoration(
              color: customBackgroundColor,
              //borderRadius: BorderRadius.circular(8.0),
            ),
            child: RichText(
              textAlign: TextAlign.left,
              textScaler: textScaler,
              softWrap: true,
              text: TextSpan(
                style: baseTextStyle,
                children: rightSpans,
              ),
              //textHeightBehavior: _verseTextHeightBehavior,
              strutStyle: verseStrutStyle,
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
  Color darkModeTextColor, {
  bool showStrongsNumbers = false,
  void Function(String strongsNumber)? onStrongsTap,
}) {
  final visibleVerseText = VerseTextParser.toPlainVerseText(
    rawVerseText,
    removePilcrow: false,
  );

  // If no highlights, just parse the text normally
  if (highlights.isEmpty) {
    return VerseTextParser.parseVerseText(rawVerseText, baseStyle,
                showStrongsNumbers: showStrongsNumbers,
                onStrongsTap: onStrongsTap)
            .children ??
        [];
  }

  // Parse the raw verse text to get spans with markup removed from visible text.
  final parsedVerseText = VerseTextParser.parseVerseText(
      rawVerseText, baseStyle,
      showStrongsNumbers: showStrongsNumbers, onStrongsTap: onStrongsTap);
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
  adjustedHighlights
      .sort((a, b) => (a['start'] as int).compareTo(b['start'] as int));

  final spans = <InlineSpan>[];
  int currentPosition = 0;

  for (final highlight in adjustedHighlights) {
    final start = highlight['start'] as int;
    final end = highlight['end'] as int;
    final color = Color(highlight['color'] as int);

    // Add unhighlighted spans before this highlight
    if (start > currentPosition) {
      final beforeSpans = extractSpansForRange(
          originalSpans, currentPosition, start, baseStyle);
      spans.addAll(beforeSpans);
    }

    // Calculate the effective highlight background
    final effectiveHighlightBackground =
        color.withValues(alpha: defaultHighlightAlpha);

    // Add highlighted spans
    final highlightSpans =
        extractSpansForRange(originalSpans, start, end, baseStyle);
    for (final span in highlightSpans) {
      if (span is TextSpan) {
        // Get the original text color from the span or base style
        final originalTextColor =
            span.style?.color ?? baseStyle.color ?? Colors.black;

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
  if (currentPosition < visibleVerseText.length) {
    final remainingSpans = extractSpansForRange(
        originalSpans, currentPosition, visibleVerseText.length, baseStyle);
    spans.addAll(remainingSpans);
  }

  return spans;
}

/// Helper method to extract spans for a specific character range from parsed text
List<InlineSpan> extractSpansForRange(
    List<InlineSpan> originalSpans, int start, int end, TextStyle baseStyle) {
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
        final extractedText = spanText.substring(
            overlapStart - spanStart, overlapEnd - spanStart);

        // If extracted text contains <r> tags, re-parse it to handle them correctly
        if (extractedText.contains('<r>') || extractedText.contains('</r>')) {
          final reParsed =
              VerseTextParser.parseVerseText(extractedText, baseStyle);
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

  int rawPosition = 0;
  int cleanCharsFound = 0;

  for (int i = 0; i < rawText.length && cleanCharsFound < cleanPosition; i++) {
    final markupMatch = _matchDisplayMarkupAt(rawText, i);
    if (markupMatch != null) {
      i += markupMatch.end - 1;
      continue;
    }

    // Regular character - count it
    cleanCharsFound++;
    rawPosition = i + 1;
  }

  return rawPosition;
}

/// Convert a position in raw text to clean text position
int convertRawPositionToClean(String rawText, int rawPosition) {
  if (rawPosition <= 0) return 0;

  if (rawPosition >= rawText.length) {
    return VerseTextParser.toPlainVerseText(rawText, removePilcrow: false)
        .length;
  }

  // Count characters in clean text up to the raw position
  int cleanPosition = 0;
  for (int i = 0; i < rawPosition && i < rawText.length; i++) {
    final markupMatch = _matchDisplayMarkupAt(rawText, i);
    if (markupMatch != null) {
      i += markupMatch.end - 1;
      continue;
    }

    cleanPosition++;
  }

  return cleanPosition;
}

final RegExp _displayMarkupRegex = RegExp(
  r'<r>|</r>|\{\{[GH]\d{1,4}\}\}|\{[GH]\d{1,4}\}',
  caseSensitive: false,
);

Match? _matchDisplayMarkupAt(String text, int index) {
  return _displayMarkupRegex.matchAsPrefix(text.substring(index));
}

/// Calculate dynamic width for verse number column based on verses in a list
/// This ensures the verse number column is sized appropriately for the maximum verse number
double calculateVerseNumberWidth(BuildContext context,
    List<Map<String, dynamic>> verses, TextStyle numStyle) {
  int maxVerseNumber = 0;
  for (final verse in verses) {
    final verseNum = toInt(verse['verse'], orElse: 0);
    if (verseNum > maxVerseNumber) {
      maxVerseNumber = verseNum;
    }
  }

  // Create a string with enough characters for the max verse number
  final maxDigits = maxVerseNumber.toString().length;
  final sampleText =
      '9' * maxDigits; // e.g., "99" for 2-digit, "999" for 3-digit

  final textPainter = TextPainter(
    text: TextSpan(text: sampleText, style: numStyle),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
    textDirection: TextDirection.ltr,
  )..layout();
  return textPainter.size.width; // + 10.0;
}

double _calculateSingleVerseNumberWidth(
    BuildContext context, String verseLabel, TextStyle style) {
  final textPainter = TextPainter(
    text: TextSpan(text: verseLabel, style: style),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
    textDirection: TextDirection.ltr,
    //textHeightBehavior: _verseTextHeightBehavior,
  )..layout();
  return textPainter.size.width; // + 10.0;
}

/// Builds a single verse widget from VerseDisplayData
/// Used by ListView.builder to lazily render verses
Widget buildVerseWidgetFromData(
  BuildContext context,
  VerseDisplayData data,
  Function(int)? onVerseTap,
  Function(int)? onVerseLongPress,
  Function(String, String?)? onLinkTap,
  Function(int, String?)? onNoteIconTap,
  Function(int, String?)? onNoteEditTap,
  Color lightHighlightTextColor,
  Color darkHighlightTextColor,
  void Function(String strongsNumber)? onStrongsTap,
) {
  final widgets = <Widget>[];

  // Add paragraph break if needed
  if (data.addParagraphBreak) {
    widgets.add(const SizedBox(height: 16));
  }

  // Build the verse display widget
  final verseWidget = buildVerseDisplayWidget(
    context: context,
    verseNumber: data.verseNumber,
    rawVerseText: data.rawVerseText,
    baseTextStyle: data.textStyle,
    backgroundColor: data.backgroundColor,
    noteForVerse: data.noteForVerse,
    highlightsForVerse: data.highlightsForVerse,
    showNotesInline: data.showNotesInline,
    fontFamily: data.fontFamily,
    lightModeTextColor: lightHighlightTextColor,
    darkModeTextColor: darkHighlightTextColor,
    onVerseTap: onVerseTap,
    onVerseLongPress: onVerseLongPress,
    onLinkTap: onLinkTap,
    verseKey: data.verseKey,
    onNoteIconTap: onNoteIconTap,
    verseNumberWidth: data.verseNumberWidth,
    customBackgroundColor: data.customBackgroundColor,
    showStrongsNumbers: data.showStrongsNumbers,
    onStrongsTap: onStrongsTap,
  );

  widgets.add(
    Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        verseWidget,
      ],
    ),
  );

  // If enabled, display TSK references below the verse and above notes.
  if (data.showTskReferences && data.tskText.isNotEmpty) {
    widgets.add(
      Container(
        margin: EdgeInsets.all(0.0),
        padding:
            EdgeInsets.only(left: 65.0, right: 32.0, top: 8.0, bottom: 8.0),
        child: TskReferenceDisplay(
          noteText: data.tskText,
          onLinkTap: onLinkTap,
        ),
      ),
    );
  }

  // If showNotesInline, display note content below the verse
  if (data.showNotesInline && data.noteText.isNotEmpty) {
    widgets.add(
      Container(
        margin: EdgeInsets.all(0.0),
        padding:
            EdgeInsets.only(left: 65.0, right: 32.0, top: 8.0, bottom: 8.0),
        child: QuillNoteDisplay(
          noteText: data.noteText,
          onLinkTap: onLinkTap,
          onTap: onNoteEditTap != null
              ? () => onNoteEditTap(data.verseNumber, data.noteText)
              : null,
        ),
      ),
    );
  }

  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: widgets,
  );
}

/// Builds a list of verse data with common display logic
/// Returns data instead of widgets, allowing ListView.builder to lazily render verses
List<VerseDisplayData> buildVerseDataList({
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
  bool showTskReferences = false,
  bool showStrongsNumbers = false,
  Map<int, String> tskReferences = const {},
  required String fontFamily,
  required Color lightHighlightTextColor,
  required Color darkHighlightTextColor,
  List<int> highlightedVerses = const [],
  Color highlightedVerseBackgroundColor = Colors.transparent,
}) {
  final dataList = <VerseDisplayData>[];
  bool pilcrowSeen = false;
  final effectiveLineHeight =
      showStrongsNumbers ? lineHeight + 0.35 : lineHeight;

  // Different styles whether it is the verse number or the text itself
  final numStyle = TextStyle(
    fontSize:
        FontSizeAdjustments.getAdjustedSize(fontFamily, fontSizeNotifier.value),
    fontFamily: fontFamily,
    color: verseNumberColor,
    fontWeight: FontWeight.normal,
    height: effectiveLineHeight,
  );
  final textStyle = TextStyle(
    fontSize:
        FontSizeAdjustments.getAdjustedSize(fontFamily, fontSizeNotifier.value),
    fontFamily: fontFamily,
    color: textColor,
    height: effectiveLineHeight,
  );

  // Calculate dynamic width for verse number column based on current chapter's verses
  final verseNumberWidth = calculateVerseNumberWidth(context, verses, numStyle);

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

    // Get note text if available
    final noteText = (showNotesInline && notes.containsKey(vn))
        ? (notes[vn]!['note_text'] as String? ?? '')
        : '';

    // Get TSK text if available
    final rawTskText = (tskReferences[vn] ?? '').trim();

    final customBgColor =
        highlightedVerses.contains(vn) ? highlightedVerseBackgroundColor : null;

    dataList.add(
      VerseDisplayData(
        verseNumber: vn,
        rawVerseText: rawVerseText,
        noteForVerse: notes[vn] ?? {},
        highlightsForVerse: highlights[vn] ?? [],
        fontFamily: fontFamily,
        textStyle: textStyle,
        numStyle: numStyle,
        verseNumberWidth: verseNumberWidth,
        backgroundColor: backgroundColor,
        showNotesInline: showNotesInline,
        showTskReferences: showTskReferences,
        showStrongsNumbers: showStrongsNumbers,
        tskText: rawTskText,
        noteText: noteText,
        addParagraphBreak: addParagraphBreak,
        customBgColor: customBgColor != null,
        customBackgroundColor: customBgColor,
        verseKey: verseKeys[vn],
      ),
    );
  }

  return dataList;
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
  bool showTskReferences = false,
  Map<int, String> tskReferences = const {},
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
    fontSize:
        FontSizeAdjustments.getAdjustedSize(fontFamily, fontSizeNotifier.value),
    fontFamily: fontFamily,
    color: verseNumberColor,
    fontWeight: FontWeight.normal,
    height: lineHeight,
  );
  final textStyle = TextStyle(
    fontSize:
        FontSizeAdjustments.getAdjustedSize(fontFamily, fontSizeNotifier.value),
    fontFamily: fontFamily,
    color: textColor,
    height: lineHeight,
  );

  // Calculate dynamic width for verse number column based on current chapter's verses
  final verseNumberWidth = calculateVerseNumberWidth(context, verses, numStyle);

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

    final customBgColor =
        highlightedVerses.contains(vn) ? highlightedVerseBackgroundColor : null;

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

    // If enabled, display TSK references below the verse and above notes.
    if (showTskReferences) {
      final rawTskText = (tskReferences[vn] ?? '').trim();
      if (rawTskText.isNotEmpty) {
        widgets.add(
          Container(
            margin: EdgeInsets.all(0.0),
            padding:
                EdgeInsets.only(left: 65.0, right: 32.0, top: 8.0, bottom: 8.0),
            child: TskReferenceDisplay(
              noteText: rawTskText,
              onLinkTap: onLinkTap,
            ),
          ),
        );
      }
    }

    // If showNotesInline, display note content below the verse
    if (showNotesInline && notes.containsKey(vn)) {
      final noteText = notes[vn]!['note_text'] as String? ?? '';
      if (noteText.isNotEmpty) {
        widgets.add(
          Container(
            margin: EdgeInsets.all(0.0),
            padding:
                EdgeInsets.only(left: 65.0, right: 32.0, top: 8.0, bottom: 8.0),
            child: QuillNoteDisplay(
              noteText: noteText,
              onLinkTap: onLinkTap,
              onTap: onNoteEditTap != null
                  ? () => onNoteEditTap(vn, noteText)
                  : null,
            ),
          ),
        );
      }
    }
  }

  return widgets;
}
