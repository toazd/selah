import 'package:material_ui/material_ui.dart';
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

/// Utility functions for displaying verses with notes and highlights
/// Extracted from bible_screen.dart for reusability

/// Builds a book colophon displayed after the final chapter's verses.
Widget buildColophonWidget({
  required BuildContext context,
  required String colophon,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return Padding(
    padding: const EdgeInsets.only(
      left: 16.0,
      top: 16.0,
      right: 32.0,
    ),
    child: Text(
      colophon.trim(),
      style: TextStyle(
        fontFamily: fontFamilyNotifier.value,
        fontSize: FontSizeAdjustments.getAdjustedSize(
          fontFamilyNotifier.value,
          fontSizeNotifier.value - 2,
        ),
        fontStyle: FontStyle.italic,
        height: lineHeightNotifier.value,
        color: isDark ? darkTextColor.value : lightTextColor.value,
      ),
    ),
  );
}

/// Builds a verse display widget with support for notes, highlights, and interactions
Widget buildVerseDisplayWidget({
  required BuildContext context,
  required int verseNumber,
  required String rawVerseText,
  required TextStyle baseTextStyle,
  required Color backgroundColor,
  required List<Map<String, dynamic>> highlightsForVerse,
  required String fontFamily,
  required Color lightModeTextColor,
  required Color darkModeTextColor,
  required Function(int)? onVerseTap,
  required Function(int)? onVerseLongPress,
  required Function(String, String?)? onLinkTap,
  required GlobalKey? verseKey,
  double? verseNumberWidth,
  Color? customBackgroundColor,
  bool displayVerseNumber = true,
}) {
  // Determine whether it's a dark theme or not
  final isDark = Theme.of(context).brightness == Brightness.dark;

  //String cleanVerseText = rawVerseText.replaceAll('¶ ', '');

  final verseNumberStyle = baseTextStyle.copyWith(
    // Verse number font size
    fontSize: baseTextStyle.fontSize,
    color: (isDark ? darkPrimaryColor.value : lightPrimaryColor.value),
    //   (isDark ? darkPrimaryColor.value : lightPrimaryColor.value).withValues(
    // alpha: 0.9,
    //),
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
  Color darkModeTextColor,
) {
  final displayVerseText = _removePilcrowMarkup(rawVerseText);

  // If no highlights, just parse the text normally
  if (highlights.isEmpty) {
    return VerseTextParser.parseVerseText(displayVerseText, baseStyle)
            .children ??
        [];
  }

  // Parse the raw verse text to get spans with markup removed from visible text.
  final parsedVerseText =
      VerseTextParser.parseVerseText(displayVerseText, baseStyle);
  final originalSpans = parsedVerseText.children ?? [];

  final adjustedHighlights = <Map<String, dynamic>>[];
  for (final highlight in highlights) {
    final rawStart = highlight['start'] as int;
    final rawEnd = highlight['end'] as int;

    final cleanRange = resolveHighlightCleanTextRange(
      rawVerseText: displayVerseText,
      savedStart: rawStart,
      savedEnd: rawEnd,
    );
    if (cleanRange == null) continue;

    adjustedHighlights.add({
      'start': cleanRange.start,
      'end': cleanRange.end,
      'color': highlight['color'],
    });
  }

  // Sort highlights by start position
  adjustedHighlights
      .sort((a, b) => (a['start'] as int).compareTo(b['start'] as int));

  return _applyHighlightsToParsedSpans(
    originalSpans: originalSpans,
    adjustedHighlights: adjustedHighlights,
    baseStyle: baseStyle,
    lightModeTextColor: lightModeTextColor,
    darkModeTextColor: darkModeTextColor,
  );
}

TextRange? resolveHighlightCleanTextRange({
  required String rawVerseText,
  required int savedStart,
  required int savedEnd,
}) {
  if (savedStart < 0 || savedEnd <= savedStart) return null;

  final visibleVerseText = VerseTextParser.toPlainVerseText(
    rawVerseText,
    removePilcrow: true,
  );

  if (savedEnd <= visibleVerseText.length) {
    return TextRange(start: savedStart, end: savedEnd);
  }

  return null;
}

/// Applies highlights while preserving the parsed display spans.
List<InlineSpan> _applyHighlightsToParsedSpans({
  required List<InlineSpan> originalSpans,
  required List<Map<String, dynamic>> adjustedHighlights,
  required TextStyle baseStyle,
  required Color lightModeTextColor,
  required Color darkModeTextColor,
}) {
  final spans = <InlineSpan>[];
  var cleanPosition = 0;
  var highlightIndex = 0;

  for (var spanIndex = 0; spanIndex < originalSpans.length; spanIndex++) {
    final span = originalSpans[spanIndex];

    if (span is! TextSpan) {
      spans.add(span);
      continue;
    }

    final spanText = span.text ?? '';
    if (spanText.isEmpty) {
      spans.add(span);
      continue;
    }

    final spanStart = cleanPosition;
    final spanEnd = spanStart + spanText.length;
    var localPosition = 0;

    while (highlightIndex < adjustedHighlights.length &&
        (adjustedHighlights[highlightIndex]['end'] as int) <= spanStart) {
      highlightIndex++;
    }

    var scanIndex = highlightIndex;
    while (scanIndex < adjustedHighlights.length) {
      final highlight = adjustedHighlights[scanIndex];
      final highlightStart = highlight['start'] as int;
      final highlightEnd = highlight['end'] as int;

      if (highlightStart >= spanEnd) {
        break;
      }

      if (highlightEnd <= spanStart) {
        scanIndex++;
        continue;
      }

      final beforeEnd =
          (highlightStart - spanStart).clamp(0, spanText.length).toInt();
      if (beforeEnd > localPosition) {
        spans.add(TextSpan(
          text: spanText.substring(localPosition, beforeEnd),
          style: span.style,
        ));
      }

      final highlightedStart = max(
        localPosition,
        (highlightStart - spanStart).clamp(0, spanText.length).toInt(),
      );
      final highlightedEnd =
          (highlightEnd - spanStart).clamp(0, spanText.length).toInt();
      if (highlightedEnd > highlightedStart) {
        spans.add(_buildHighlightedTextSpan(
          text: spanText.substring(highlightedStart, highlightedEnd),
          sourceStyle: span.style,
          baseStyle: baseStyle,
          highlightColor: Color(highlight['color'] as int),
          lightModeTextColor: lightModeTextColor,
          darkModeTextColor: darkModeTextColor,
        ));
      }

      localPosition = max(localPosition, highlightedEnd);

      if (highlightEnd > spanEnd) {
        break;
      }
      scanIndex++;
    }

    if (localPosition < spanText.length) {
      spans.add(TextSpan(
        text: spanText.substring(localPosition),
        style: span.style,
      ));
    }

    cleanPosition = spanEnd;
  }

  return spans;
}

TextSpan _buildHighlightedTextSpan({
  required String text,
  required TextStyle? sourceStyle,
  required TextStyle baseStyle,
  required Color highlightColor,
  required Color lightModeTextColor,
  required Color darkModeTextColor,
}) {
  final effectiveHighlightBackground =
      highlightColor.withValues(alpha: defaultHighlightAlpha);
  final originalTextColor =
      sourceStyle?.color ?? baseStyle.color ?? Colors.black;
  final adjustedTextColor = adjustTextColorForHighlight(
    originalTextColor,
    effectiveHighlightBackground,
    darkModeTextColor,
    lightModeTextColor,
  );

  return TextSpan(
    text: text,
    style: (sourceStyle ?? baseStyle).copyWith(
      backgroundColor: effectiveHighlightBackground,
      color: adjustedTextColor,
    ),
  );
}

String _removePilcrowMarkup(String text) {
  return text.replaceAll('¶ ', '').replaceAll('¶', '');
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
  Function(int, String?)? onNoteEditTap,
  Color lightHighlightTextColor,
  Color darkHighlightTextColor,
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
    highlightsForVerse: data.highlightsForVerse,
    fontFamily: data.fontFamily,
    lightModeTextColor: lightHighlightTextColor,
    darkModeTextColor: darkHighlightTextColor,
    onVerseTap: onVerseTap,
    onVerseLongPress: onVerseLongPress,
    onLinkTap: onLinkTap,
    verseKey: data.verseKey,
    verseNumberWidth: data.verseNumberWidth,
    customBackgroundColor: data.customBackgroundColor,
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

  // Display note content below the verse
  if (data.noteText.isNotEmpty) {
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
    crossAxisAlignment: CrossAxisAlignment.start,
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
  bool showTskReferences = false,
  Map<int, String> tskReferences = const {},
  required String fontFamily,
  required Color lightHighlightTextColor,
  required Color darkHighlightTextColor,
  List<int> highlightedVerses = const [],
  Color highlightedVerseBackgroundColor = Colors.transparent,
}) {
  final dataList = <VerseDisplayData>[];
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

    // Get note text if available
    final noteText =
        notes.containsKey(vn) ? (notes[vn]!['note_text'] as String? ?? '') : '';

    // Get TSK text if available
    final rawTskText = (tskReferences[vn] ?? '').trim();

    final customBgColor =
        highlightedVerses.contains(vn) ? highlightedVerseBackgroundColor : null;

    dataList.add(
      VerseDisplayData(
        verseNumber: vn,
        rawVerseText: rawVerseText,
        highlightsForVerse: highlights[vn] ?? [],
        fontFamily: fontFamily,
        textStyle: textStyle,
        //numStyle: numStyle,
        verseNumberWidth: verseNumberWidth,
        backgroundColor: backgroundColor,
        showTskReferences: showTskReferences,
        tskText: rawTskText,
        noteText: noteText,
        addParagraphBreak: addParagraphBreak,
        //customBgColor: customBgColor != null,
        customBackgroundColor: customBgColor,
        verseKey: verseKeys[vn],
      ),
    );
  }

  return dataList;
}
