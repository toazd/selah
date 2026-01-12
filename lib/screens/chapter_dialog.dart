import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import '../database/bible_database.dart';
import '../utils/preferences_constants.dart';
import '../main.dart';
import '../utils/book_name_converter.dart';
import '../utils/verse_display_utils.dart';
import '../services/local_data_change_notifier.dart';
import '../services/supabase_sync_service.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import '../utils/snackbar_notification.dart';
import '../utils/bible_utils.dart';
import '../utils/data_loaders.dart';
import '../utils/dialog_utils.dart';

// Helper function to create a slightly different shade for bars
Color _adjustBarColor(Color backgroundColor) {
  final hsl = HSLColor.fromColor(backgroundColor);
  // If lightness > 0.5 (light color), make slightly darker; otherwise make slightly lighter
  final adjustedLightness = hsl.lightness > 0.5
      ? (hsl.lightness - 0.03).clamp(0.0, 1.0) // Darker for light backgrounds
      : (hsl.lightness + 0.03).clamp(0.0, 1.0); // Lighter for dark backgrounds
  return hsl.withLightness(adjustedLightness).toColor();
}

class ChapterDialog extends StatefulWidget {
  final String book;
  final int chapter;
  final int? verse; // Verse to scroll to (optional)
  final int? endVerse; // End verse for ranges (optional)
  final List<int>?
      targetVerses; // List of individual verses to highlight (optional)
  //final int? screenIdentifier; // Screen that opened this dialog for navigation targeting
  final Function(String, String?)?
      onVerseLink; // Callback for handling verse reference links
  final Function(int)?
      onNavigateToVerse; // Callback for "goto verse X" navigation
  final String? referenceText;
  final Function(int, String?)?
      onNoteIconTap; // Callback for when note icon is tapped
  final Function(int, String?)?
      onNoteEditTap; // Callback for when inline note is tapped for editing

  const ChapterDialog({
    super.key,
    required this.book,
    required this.chapter,
    this.verse,
    this.endVerse,
    this.targetVerses,
    //this.screenIdentifier,
    this.onVerseLink,
    this.onNavigateToVerse,
    this.referenceText,
    this.onNoteIconTap,
    this.onNoteEditTap,
  });

  @override
  State<ChapterDialog> createState() => _ChapterDialogState();
}

class _ChapterDialogState extends State<ChapterDialog> {
  List<Map<String, dynamic>> _verses = [];
  bool _loading = true;
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _verseKeys = {};
  Size? _dialogSize;

  // Real-time data for notes and highlights
  Map<int, Map<String, dynamic>> _notes = {};
  Map<int, List<Map<String, dynamic>>> _highlights = {};

  // Stream subscriptions for real-time updates
  late StreamSubscription _highlightsSubscription;
  late StreamSubscription _notesSubscription;

  // Local fallback for notes inline mode
  late final ValueNotifier<bool> _localShowNotesInlineFallback =
      ValueNotifier<bool>(false);

  // Cached long name for the book
  late final String bookLongName;

  List<int> get _highlightedVerses {
    // First, check if targetVerses was explicitly provided
    if (widget.targetVerses != null && widget.targetVerses!.isNotEmpty) {
      return widget.targetVerses!;
    }

    // Second, try parsing from referenceText (may contain ranges like "1-5" or lists like "1,3,5")
    if (widget.referenceText != null) {
      final parsed = _parseReferenceText(widget.referenceText!);
      if (parsed.isNotEmpty) {
        return parsed;
      }
    }

    // Finally, check for verse/endVerse range (used for scrolling, may only have single verse)
    if (widget.verse != null) {
      final start = widget.verse!;
      final end = widget.endVerse ?? start;
      return List.generate(end - start + 1, (i) => start + i);
    }

    return [];
  }

  @override
  void initState() {
    super.initState();
    bookLongName = BookNameConverter.shortNameToLongName(widget.book);
    _initializeDialogSize();
    _setupDataListeners();
    _loadChapter();
  }

// Parse reference text like "Gen 1:3-5,6, 7, 11" to extract verse numbers
  List<int> _parseReferenceText(String referenceText) {
    final verses = <int>[];

    // Find the part after the first colon
    final colonIndex = referenceText.indexOf(':');
    if (colonIndex == -1) return verses;

    final verseSpec = referenceText.substring(colonIndex + 1).trim();

    // Split by comma, then handle each part
    final parts = verseSpec.split(',');
    for (final part in parts) {
      final trimmedPart = part.trim();
      if (trimmedPart.contains('-')) {
        // Range like "3-5"
        final dashParts = trimmedPart.split('-');
        if (dashParts.length == 2) {
          final start = int.tryParse(dashParts[0].trim());
          final end = int.tryParse(dashParts[1].trim());
          if (start != null && end != null && start <= end) {
            for (int i = start; i <= end; i++) {
              verses.add(i);
            }
          }
        }
      } else {
        // Single verse
        final verse = int.tryParse(trimmedPart);
        if (verse != null) {
          verses.add(verse);
        }
      }
    }

    // Sort and remove duplicates
    verses.sort();
    return verses.toSet().toList();
  }

  Color _getHighlightedVerseBackgroundColor() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? darkBackgroundColor.value : lightBackgroundColor.value;

    final hsl = HSLColor.fromColor(bgColor);
    final adjustedLightness = hsl.lightness > 0.5
        ? (hsl.lightness - 0.03).clamp(0.0, 1.0)
        : (hsl.lightness + 0.03).clamp(0.0, 1.0);

    return hsl.withLightness(adjustedLightness).toColor();
  }

  void _setupDataListeners() {
    // Listen to sync service streams for real-time updates
    _highlightsSubscription =
        SupabaseSyncService.highlightsChangedStream.listen((_) async {
      await _loadHighlights();
      if (mounted) {
        setState(() {});
      }
    });

    _notesSubscription =
        SupabaseSyncService.notesChangedStream.listen((_) async {
      await _loadNotes();
      if (mounted) setState(() {});
    });

    // Listen to local data change notifier streams for immediate updates during local operations
    LocalDataChangeNotifier.highlightsChangedStream.listen((_) async {
      await _loadHighlights();
      if (mounted) {
        setState(() {});
      }
    });

    LocalDataChangeNotifier.notesChangedStream.listen((_) async {
      await _loadNotes();
      if (mounted) setState(() {});
    });
  }

  Future<void> _initializeDialogSize() async {
    _dialogSize = await _getDialogSize(context);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadChapter() async {
    try {
      // Load verses for the chapter
      _verses = await BibleDatabase.getVerses(
          BookNameConverter.normalizeShortName(widget.book), widget.chapter);

      if (_verses.isEmpty) {
        return;
      }

      // Load book metadata
      //final metadata = await BibleDatabase.getBookMetadata(widget.book);
      //_bookTitle = metadata?['title'] as String?;

      // Create keys for verse scrolling
      _verseKeys.clear();
      for (final verse in _verses) {
        final verseNum = verse['verse'] as int;
        _verseKeys[verseNum] = GlobalKey();
      }

      // Load notes and highlights after verses are loaded
      await _loadNotes();
      await _loadHighlights();

      setState(() {
        _loading = false;
      });

      // Scroll to the target verse after the build
      if (widget.verse != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToVerse(widget.verse!);
        });
      } else if (widget.targetVerses != null &&
          widget.targetVerses!.isNotEmpty) {
        // Scroll to the first target verse
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToVerse(widget.targetVerses!.first);
        });
      }
    } catch (e) {
      setState(() {
        _loading = false;
      });
      // Handle error - could show a snackbar or error message
    }
  }

  void _scrollToVerse(int verseNumber) {
    final key = _verseKeys[verseNumber];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        alignment: 0.4, // Center the verse in the viewport
        duration: Duration.zero, //const Duration(milliseconds: 500),
        //curve: Curves.easeInOut,
      );
    }
  }

  Future<Size> _getDialogSize(BuildContext context) async {
    try {
      // Get primary display size for screen-aware sizing
      final primaryDisplay = await screenRetriever.getPrimaryDisplay();
      final screenSize = primaryDisplay.size;

      // Define breakpoints and size factors
      double widthFactor;
      double heightFactor;

      if (screenSize.width < 800) {
        // Small screens (mobile/tablet)
        widthFactor = 0.8;
        heightFactor = 0.7;
      } else if (screenSize.width < 1200) {
        // Medium screens (small desktop)
        widthFactor = 0.5;
        heightFactor = 0.5;
      } else {
        // Large screens (large desktop)
        widthFactor = 0.4;
        heightFactor = 0.4;
      }

      // Calculate dialog size based on screen size
      final dialogWidth = screenSize.width * widthFactor;
      final dialogHeight = screenSize.height * heightFactor;

      return Size(dialogWidth, dialogHeight);
    } catch (e) {
      // Fallback to MediaQuery if screenRetriever fails
      // Needed for mobile
      if (context.mounted) {
        final mediaSize = MediaQuery.of(context).size;
        return Size(mediaSize.width * 0.8, mediaSize.height * 0.7);
      } else {
        return Size(320, 448);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? darkBackgroundColor.value : lightBackgroundColor.value;
    final textColor = isDark ? darkTextColor.value : lightTextColor.value;
    final primaryColor =
        isDark ? darkPrimaryColor.value : lightPrimaryColor.value;

    return Dialog(
      child: SizedBox(
        width: _dialogSize?.width ?? MediaQuery.of(context).size.width * 0.5,
        height: _dialogSize?.height ?? MediaQuery.of(context).size.height * 0.5,
        child: Column(
          children: [
            // Header with book title and close button
            Container(
              decoration: BoxDecoration(
                color: _adjustBarColor(bgColor),
                borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(16.0),
                    topRight: Radius.circular(16.0)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Center(
                    child: RichText(
                      text: TextSpan(
                        text: '$bookLongName ${widget.chapter}',
                        style: TextStyle(
                          fontSize: uiFontSize + 2,
                          fontWeight: FontWeight.bold,
                          color: getAdaptiveTextColor(context),
                          fontFamily: uiFontFamily,
                        ),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Positioned(
                    right: 0,
                    child: IconButton(
                      icon: Icon(
                        Icons.close,
                        color: primaryColor,
                        size: 32,
                        semanticLabel: 'Close',
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),

            // Chapter content
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(16.0),
                      bottomRight: Radius.circular(16.0)),
                ),
                child: _loading
                    ? Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _buildVerseWidgets(textColor),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showChapterVerseMenu(BuildContext context, int verseNumber) {
    final verseData = _verses.firstWhere(
        (v) => toInt(v['verse'], orElse: -1) == verseNumber,
        orElse: () => <String, Object>{});
    final verseText = verseData['text'] as String? ?? '';

    // Filter out red letter tags <r> and </r>, and pilcrow symbols
    final redLetterRegex = RegExp(r'</?r>');
    final cleanVerseText =
        verseText.replaceAll(redLetterRegex, '').replaceAll('¶ ', '');
    final bookName = bookLongName;
    final copyText =
        '$bookName ${widget.chapter}:$verseNumber\n$cleanVerseText';

    showModalBottomSheet(
        context: context,
        builder: (context) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Center(
                      child: Text(
                    _notes.containsKey(verseNumber) ? 'Edit Note' : 'Add Note',
                    style: TextStyle(
                        fontFamily: uiFontFamily,
                        fontSize: uiFontSize + 10,
                        color: getAdaptiveTextColor(context)),
                  )),
                  onTap: () {
                    Navigator.of(context).pop();
                    // Use note callback if provided, otherwise navigate to verse
                    if (widget.onNoteIconTap != null) {
                      widget.onNoteIconTap!(
                          verseNumber, _notes[verseNumber]?['note_text']);
                    } else {
                      _gotoVerse(verseNumber);
                    }
                  },
                ),
                ListTile(
                  title: Center(
                      child: Text(
                    'Copy Verse $verseNumber',
                    style: TextStyle(
                        fontFamily: uiFontFamily,
                        fontSize: uiFontSize + 10,
                        color: getAdaptiveTextColor(context)),
                  )),
                  onTap: () async {
                    Navigator.of(context).pop();
                    try {
                      await Clipboard.setData(ClipboardData(text: copyText));
                      if (context.mounted) {
                        showStyledSnackBar(context, 'Verse Copied');
                      }
                    } catch (e) {
                      if (context.mounted) {
                        showStyledSnackBar(context, 'Copy failed',
                            isError: true);
                      }
                    }
                  },
                ),
                ListTile(
                  title: Center(
                      child: Text(
                    'Copy Multiple Verses',
                    style: TextStyle(
                        fontFamily: uiFontFamily,
                        fontSize: uiFontSize + 10,
                        color: getAdaptiveTextColor(context)),
                  )),
                  onTap: () {
                    Navigator.of(context).pop();
                    _openMultipleVersesDialog(verseNumber);
                  },
                ),
              ],
            ));
  }

  void _gotoVerse(int verseNumber) {
    // Close this dialog and navigate the calling Bible screen to the target verse
    Navigator.of(context).pop();

    // Use callback to navigate the initiating screen to the selected verse
    if (widget.onNavigateToVerse != null) {
      widget.onNavigateToVerse!(verseNumber);
    }
  }

  /*
  void _openMultipleVersesDialog(int verseNumber) {
    showDialog(
      context: context,
      builder: (context) => MultipleVersesDialog(
          book: BookNameConverter.displayKeyForDb(widget.book),
          chapter: widget.chapter,
          initialVerse: verseNumber,
          verses: _verses.map((verseMap) {
            // 1. Safely retrieve the original text, defaulting to "" if null.
            String parsedVerse = (verseMap['text'] as String?) ?? '';

            // 2. Create the cleaned text.
            String cleanedText = parsedVerse.replaceAll('¶ ', '');

            // 3. Return a NEW Map with the original data, but with the
            //    'text' key updated with the cleaned string.
            return {
              ...verseMap, // Copies all existing key/value pairs from the original map
              'text': cleanedText, // Overwrites the 'text' key with the cleaned string
            };
          }).toList()),
    );
  }
  */

  void _openMultipleVersesDialog(int verseNumber) {
    showMultipleVersesDialog(
      context: context,
      book: bookLongName,
      chapter: widget.chapter,
      initialVerse: verseNumber,
      verses: _verses,
    );
  }

  void _enterHighlightMode(BuildContext context, int verseNumber) async {
    final verseData = _verses.firstWhere(
        (v) => toInt(v['verse'], orElse: -1) == verseNumber,
        orElse: () => <String, Object>{});
    final rawVerseText = verseData['text'] as String? ?? '';

    await showHighlightDialog(
      context: context,
      rawVerseText: rawVerseText,
      verseNumber: verseNumber,
      book: BookNameConverter.longNameToShortName(widget.book),
      chapter: widget.chapter,
      onFinished: () async {
        await _loadHighlights();
        if (mounted) {
          setState(() {});
        }
      },
    );
  }

  // Handle verse: scheme links by calling the callback
  void _handleVerseLink(String link, String? referenceText) {
    // Remove "unsafe:" prefix if present
    if (link.startsWith('unsafe:')) {
      link = link.replaceFirst('unsafe:', '');
    }

    // Use callback for navigation targeting
    if (widget.onVerseLink != null) {
      widget.onVerseLink!(link, referenceText);
    }
  }

  List<Widget> _buildVerseWidgets(Color textColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? darkBackgroundColor.value : lightBackgroundColor.value;

    return buildVerseListWidget(
      context: context,
      verses: _verses,
      verseKeys: _verseKeys,
      notes: _notes,
      highlights: _highlights,
      textColor: textColor,
      verseNumberColor:
          (isDark ? darkPrimaryColor.value : lightPrimaryColor.value)
              .withValues(alpha: 0.5),
      backgroundColor: bgColor,
      lineHeight: lineHeightNotifier.value,
      showNotesInline: showNotesInlineNotifier.value,
      fontFamily: fontFamilyNotifier.value,
      lightHighlightTextColor: lightTextColor.value,
      darkHighlightTextColor: darkTextColor.value,
      onVerseTap: (verseNum) => _showChapterVerseMenu(context, verseNum),
      onVerseLongPress: (verseNum) => _enterHighlightMode(context, verseNum),
      onLinkTap: _handleVerseLink,
      lightVerseReferenceColor: lightVerseReferenceColor,
      darkVerseReferenceColor: darkVerseReferenceColor,
      onNoteIconTap: widget.onNoteIconTap != null
          ? (vn, noteText) => widget.onNoteIconTap!(vn, noteText)
          : null,
      onNoteEditTap: widget.onNoteEditTap != null
          ? (vn, noteText) => widget.onNoteEditTap!(vn, noteText)
          : null,
      highlightedVerses: _highlightedVerses,
      highlightedVerseBackgroundColor: _getHighlightedVerseBackgroundColor(),
    );
  }

  Future<void> _loadNotes() async {
    if (_verses.isNotEmpty) {
      final bookKey = BookNameConverter.normalizeShortName(widget.book);
      _notes = await loadNotesForChapter(bookKey, widget.chapter);
    } else {
      _notes.clear();
    }
  }

  Future<void> _loadHighlights() async {
    if (_verses.isNotEmpty) {
      final bookKey = BookNameConverter.normalizeShortName(widget.book);
      _highlights = await loadHighlightsForChapter(bookKey, widget.chapter);
    } else {
      _highlights.clear();
    }
  }

  @override
  void dispose() {
    // Cancel stream subscriptions
    _highlightsSubscription.cancel();
    _notesSubscription.cancel();

    // Dispose controllers
    _scrollController.dispose();
    _localShowNotesInlineFallback.dispose();

    super.dispose();
  }
}
