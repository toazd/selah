import 'package:flutter/material.dart';
import '../main.dart'; // For global notifiers and colors
import '../data/tsk_data.dart';
import '../utils/verse_display_utils.dart';
import '../utils/bible_utils.dart';
import '../utils/font_size_adjustments.dart';

/// A widget that displays a single chapter's content with its own scroll state.
/// Used by PageView in BibleScreen for smooth chapter navigation animations.
class ChapterContentWidget extends StatefulWidget {
  final String book;
  final int chapter;
  final List<Map<String, dynamic>> verses;
  final Map<int, Map<String, dynamic>> notes;
  final Map<int, List<Map<String, dynamic>>> highlights;
  final String? bookTitle;
  final String? bookColophon;
  final bool isLastChapter;
  final bool showNotesInline;
  final bool showTskReferences;
  final Color backgroundColor;
  final Color textColor;
  final Color verseNumberColor;
  final Function(int)? onVerseTap;
  final Function(int)? onVerseLongPress;
  final Function(String, String?)? onLinkTap;
  final Function(int, String?)? onNoteIconTap;
  final Function(int, String?)? onNoteEditTap;
  final int? initialScrollToVerse;

  const ChapterContentWidget({
    super.key,
    required this.book,
    required this.chapter,
    required this.verses,
    required this.notes,
    required this.highlights,
    this.bookTitle,
    this.bookColophon,
    this.isLastChapter = false,
    required this.showNotesInline,
    required this.showTskReferences,
    required this.backgroundColor,
    required this.textColor,
    required this.verseNumberColor,
    this.onVerseTap,
    this.onVerseLongPress,
    this.onLinkTap,
    this.onNoteIconTap,
    this.onNoteEditTap,
    this.initialScrollToVerse,
  });

  @override
  State<ChapterContentWidget> createState() => ChapterContentWidgetState();
}

class ChapterContentWidgetState extends State<ChapterContentWidget> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _verseKeys = {};

  @override
  void initState() {
    super.initState();
    _buildVerseKeys();

    // Scroll to initial verse if specified
    if (widget.initialScrollToVerse != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        scrollToVerse(widget.initialScrollToVerse!);
      });
    }
  }

  void _buildVerseKeys() {
    _verseKeys.clear();
    for (final v in widget.verses) {
      final n = toInt(v['verse'], orElse: 0);
      if (n > 0) _verseKeys[n] = GlobalKey();
    }
  }

  @override
  void didUpdateWidget(covariant ChapterContentWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Rebuild verse keys if verses changed
    if (widget.verses != oldWidget.verses) {
      _buildVerseKeys();
    }
  }

  /// Scrolls to a specific verse number within this chapter.
  /// Returns true if scroll was initiated, false if verse not found.
  bool scrollToVerse(int verseNumber, {bool animate = true}) {
    final key = _verseKeys[verseNumber];
    final ctx = key?.currentContext;

    if (ctx != null) {
      try {
        final alignment = isVerticalTile.value ? 0.005 : 0.025;
        Scrollable.ensureVisible(
          ctx,
          alignment: alignment,
          duration: Duration(milliseconds: animate ? 250 : 0),
          curve: Curves.easeOut,
        );
        return true;
      } catch (e) {
        return false;
      }
    }
    return false;
  }

  /// Scrolls to the top of the chapter content.
  void scrollToTop({bool animate = true}) {
    if (!_scrollController.hasClients) return;

    if (animate) {
      _scrollController.animateTo(
        0.0,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tskReferencesForChapter = tskData[widget.book]?[widget.chapter];

    return RawScrollbar(
      thumbColor: isDark
          ? darkPrimaryColor.value.withValues(alpha: 0.3)
          : lightPrimaryColor.value.withValues(alpha: 0.5),
      thumbVisibility: false,
      trackVisibility: false,
      thickness: 16.0,
      radius: Radius.circular(8.0),
      controller: _scrollController,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Padding(
            padding: EdgeInsets.only(
              left: 0.0,
              top: 8.0,
              bottom:
                  300.0, // Large gap at bottom for reading while laying down
              right: 16.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Show book title on Chapter 1, or for Psalms (superscriptions)
                if (widget.bookTitle != null &&
                    (widget.chapter == 1 || widget.book == 'Psa'))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Center(
                      child: Text(
                        widget.bookTitle!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: FontSizeAdjustments.getAdjustedSize(
                            fontFamilyNotifier.value,
                            fontSizeNotifier.value + 1,
                          ),
                          color: isDark
                              ? darkTextColor.value
                              : lightTextColor.value,
                        ),
                      ),
                    ),
                  ),
                // Verse list
                ...buildVerseListWidget(
                  context: context,
                  verses: widget.verses,
                  verseKeys: _verseKeys,
                  notes: widget.notes,
                  highlights: widget.highlights,
                  textColor: widget.textColor,
                  verseNumberColor: widget.verseNumberColor,
                  backgroundColor: widget.backgroundColor,
                  lineHeight: lineHeightNotifier.value,
                  showNotesInline: widget.showNotesInline,
                  showTskReferences: widget.showTskReferences,
                  tskReferences: tskReferencesForChapter ?? const {},
                  fontFamily: fontFamilyNotifier.value,
                  lightHighlightTextColor: lightTextColor.value,
                  darkHighlightTextColor: darkTextColor.value,
                  onVerseTap: widget.onVerseTap,
                  onVerseLongPress: widget.onVerseLongPress,
                  onLinkTap: widget.onLinkTap,
                  lightVerseReferenceColor: lightVerseReferenceColor,
                  darkVerseReferenceColor: darkVerseReferenceColor,
                  onNoteIconTap: widget.onNoteIconTap,
                  onNoteEditTap: widget.onNoteEditTap,
                ),
                // Show colophon only on the last chapter
                if (widget.bookColophon != null &&
                    widget.bookColophon!.isNotEmpty &&
                    widget.isLastChapter)
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: Text(
                      widget.bookColophon!,
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        fontSize: FontSizeAdjustments.getAdjustedSize(
                          fontFamilyNotifier.value,
                          fontSizeNotifier.value - 1,
                        ),
                        color:
                            isDark ? darkTextColor.value : lightTextColor.value,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
