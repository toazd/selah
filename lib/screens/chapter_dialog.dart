import 'package:material_ui/material_ui.dart';
import 'package:screen_retriever/screen_retriever.dart';
import '../database/bible_database.dart';
import '../utils/preferences_constants.dart';
import '../main.dart';
import '../utils/book_name_converter.dart';
import '../utils/font_size_adjustments.dart';
import '../utils/verse_display_utils.dart';
import '../services/local_data_change_notifier.dart';
import '../services/supabase_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import '../utils/snackbar_notification.dart';
import '../utils/bible_utils.dart';
import '../utils/data_loaders.dart';
import '../utils/dialog_utils.dart';
import '../utils/verse_text_parser.dart';
import '../data/tsk_data.dart';
import '../models/verse_display_data.dart';
import '../widgets/strongs_definition_dialog.dart';

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
  bool _isOptionsDrawerOpen = false;
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _verseKeys = {};
  Size? _dialogSize;

  // Cached verse data used by the dialog scroll view.
  List<VerseDisplayData> _verseDataList = [];
  int _targetVerseScrollAttempts = 0;
  bool _targetVerseScrollCompleted = false;

  // Real-time data for notes and highlights
  Map<int, Map<String, dynamic>> _notes = {};
  Map<int, List<Map<String, dynamic>>> _highlights = {};

  // Stream subscriptions for real-time updates
  late final StreamSubscription<void> _highlightsSubscription;
  late final StreamSubscription<void> _notesSubscription;
  late final StreamSubscription<void> _localHighlightsSubscription;
  late final StreamSubscription<void> _localNotesSubscription;

  // Local fallback for notes inline mode
  late final ValueNotifier<bool> _localShowNotesInlineFallback =
      ValueNotifier<bool>(false);

  // Cached long name for the book
  late final String bookLongName;
  String? _bookTitle;
  String? _bookColophon;
  bool _isLastChapter = false;

  String get _normalizedBook =>
      BookNameConverter.normalizeShortName(widget.book);

  bool get _shouldShowBookTitle =>
      _bookTitle != null &&
      _bookTitle!.isNotEmpty &&
      (widget.chapter == 1 || _normalizedBook == 'Psa');

  bool get _shouldShowBookColophon =>
      _bookColophon != null && _bookColophon!.isNotEmpty && _isLastChapter;

  int? get _initialScrollVerse {
    if (widget.verse != null && widget.verse! > 0) {
      return widget.verse;
    }

    final targetVerses = widget.targetVerses;
    if (targetVerses != null) {
      for (final verse in targetVerses) {
        if (verse > 0) return verse;
      }
    }

    return null;
  }

  List<int> get _highlightedVerses {
    // First, check if targetVerses was explicitly provided
    if (widget.targetVerses != null && widget.targetVerses!.isNotEmpty) {
      return _filterSingleOpeningVerseHighlight(widget.targetVerses!);
    }

    // Second, try parsing from referenceText (may contain ranges like "1-5" or lists like "1,3,5")
    if (widget.referenceText != null) {
      final parsed = _parseReferenceText(widget.referenceText!);
      if (parsed.isNotEmpty) {
        return _filterSingleOpeningVerseHighlight(parsed);
      }
    }

    // Finally, check for verse/endVerse range (used for scrolling, may only have single verse)
    if (widget.verse != null) {
      final start = widget.verse!;
      final end = widget.endVerse ?? start;
      return _filterSingleOpeningVerseHighlight(
        List.generate(end - start + 1, (i) => start + i),
      );
    }

    return [];
  }

  List<int> _filterSingleOpeningVerseHighlight(List<int> verses) {
    if (verses.length == 1 && (verses.single == 0 || verses.single == 1)) {
      return [];
    }
    return verses;
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
      if (!mounted) return;
      _rebuildVerseDataList();
      setState(() {});
    });

    _notesSubscription =
        SupabaseSyncService.notesChangedStream.listen((_) async {
      await _loadNotes();
      if (!mounted) return;
      _rebuildVerseDataList();
      setState(() {});
    });

    // Listen to local data change notifier streams for immediate updates during local operations
    _localHighlightsSubscription =
        LocalDataChangeNotifier.highlightsChangedStream.listen((_) async {
      await _loadHighlights();
      if (!mounted) return;
      _rebuildVerseDataList();
      setState(() {});
    });

    _localNotesSubscription =
        LocalDataChangeNotifier.notesChangedStream.listen((_) async {
      await _loadNotes();
      if (!mounted) return;
      _rebuildVerseDataList();
      setState(() {});
    });
  }

  Future<void> _initializeDialogSize() async {
    _dialogSize = await _getDialogSize(context);
    if (mounted) {
      setState(() {});
      if (!_loading && _initialScrollVerse != null) {
        _scheduleTargetVerseScroll(force: true);
      }
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

      final normalizedBook = _normalizedBook;
      final metadata = normalizedBook == 'Psa'
          ? await BibleDatabase.getBookMetadata(
              normalizedBook,
              chapter: widget.chapter,
            )
          : await BibleDatabase.getBookMetadata(normalizedBook);
      _bookTitle = metadata?['title'] as String?;
      _bookColophon = metadata?['colophon'] as String?;

      final bookChapters = await BibleDatabase.getChapters(normalizedBook);
      _isLastChapter =
          bookChapters.isNotEmpty && widget.chapter == bookChapters.last;

      // Create keys for verse scrolling
      _verseKeys.clear();
      for (final verse in _verses) {
        final verseNum = verse['verse'] as int;
        _verseKeys[verseNum] = GlobalKey();
      }

      if (!mounted) return;

      // Load notes and highlights after verses are loaded
      await _loadNotes();
      await _loadHighlights();

      if (!mounted) return;

      // Build the verse data list for rendering
      _rebuildVerseDataList();

      setState(() {
        _loading = false;
      });

      _scheduleTargetVerseScroll();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  /// Rebuilds the cached verse data list for rendering.
  /// Called when verses, notes, highlights, or display settings change.
  void _rebuildVerseDataList() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? darkBackgroundColor.value : lightBackgroundColor.value;
    final textColor = isDark ? darkTextColor.value : lightTextColor.value;
    final normalizedBook = BookNameConverter.normalizeShortName(widget.book);
    final tskReferences =
        tskData[normalizedBook]?[widget.chapter] ?? const <int, String>{};

    _verseDataList = buildVerseDataList(
      context: context,
      verses: _verses,
      verseKeys: _verseKeys,
      notes: _notes,
      highlights: _highlights,
      textColor: textColor,
      verseNumberColor:
          (isDark ? darkPrimaryColor.value : lightPrimaryColor.value)
              .withValues(alpha: 0.9),
      backgroundColor: bgColor,
      lineHeight: lineHeightNotifier.value,
      showNotesInline: showNotesInlineNotifier.value,
      showTskReferences: showDialogTskNotifier.value,
      showStrongsNumbers: showDialogStrongsNotifier.value,
      tskReferences: tskReferences,
      fontFamily: fontFamilyNotifier.value,
      lightHighlightTextColor: lightTextColor.value,
      darkHighlightTextColor: darkTextColor.value,
      highlightedVerses: _highlightedVerses,
      highlightedVerseBackgroundColor: _getHighlightedVerseBackgroundColor(),
    );
  }

  void _scheduleTargetVerseScroll({bool force = false}) {
    final verseNumber = _initialScrollVerse;
    if (verseNumber == null) return;
    if (_targetVerseScrollCompleted && !force) return;

    if (force) {
      _targetVerseScrollCompleted = false;
    }
    _targetVerseScrollAttempts = 0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryScrollToTargetVerse(verseNumber);
    });
  }

  void _tryScrollToTargetVerse(int verseNumber) {
    if (!mounted || _targetVerseScrollCompleted) return;

    if (_scrollToVerse(verseNumber)) {
      _targetVerseScrollCompleted = true;
      return;
    }

    _targetVerseScrollAttempts++;
    if (_targetVerseScrollAttempts >= 10) return;

    Future<void>.delayed(const Duration(milliseconds: 16), () {
      if (!mounted || _targetVerseScrollCompleted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tryScrollToTargetVerse(verseNumber);
      });
    });
  }

  bool _scrollToVerse(int verseNumber) {
    final key = _verseKeys[verseNumber];
    final targetContext = key?.currentContext;
    if (_scrollController.hasClients && targetContext != null) {
      Scrollable.ensureVisible(
        targetContext,
        alignment: 0.4, // Center the verse in the viewport
        duration: Duration.zero,
      );
      return true;
    }
    return false;
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

  Widget _buildBookTitleWidget(bool isDark, bool showStrongsNumbers) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8.0, 8.0, 22.0, 8.0),
      child: Center(
        child: RichText(
          textAlign: TextAlign.center,
          text: VerseTextParser.parseVerseText(
            _bookTitle!,
            TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: FontSizeAdjustments.getAdjustedSize(
                fontFamilyNotifier.value,
                fontSizeNotifier.value + 1,
              ),
              fontFamily: fontFamilyNotifier.value,
              height: showStrongsNumbers
                  ? lineHeightNotifier.value + 0.35
                  : lineHeightNotifier.value,
              color: isDark ? darkTextColor.value : lightTextColor.value,
            ),
            showStrongsNumbers: showStrongsNumbers,
            expandStrongsTapTarget: true,
            strongsColor:
                isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
            onStrongsTap: _showStrongsDefinitionDialog,
          ),
        ),
      ),
    );
  }

  Widget _buildBookColophonWidget(bool isDark, bool showStrongsNumbers) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8.0, 8.0, 22.0, 0.0),
      child: RichText(
        textAlign: TextAlign.left,
        text: VerseTextParser.parseVerseText(
          _bookColophon!,
          TextStyle(
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.normal,
            fontSize: FontSizeAdjustments.getAdjustedSize(
              fontFamilyNotifier.value,
              fontSizeNotifier.value - 1,
            ),
            fontFamily: fontFamilyNotifier.value,
            height: showStrongsNumbers
                ? lineHeightNotifier.value + 0.35
                : lineHeightNotifier.value,
            color: isDark ? darkTextColor.value : lightTextColor.value,
          ),
          showStrongsNumbers: showStrongsNumbers,
          expandStrongsTapTarget: true,
          strongsColor:
              isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
          onStrongsTap: _showStrongsDefinitionDialog,
        ),
      ),
    );
  }

  Widget _buildOptionsDrawer(Color bgColor, Color primaryColor) {
    final textStyle = TextStyle(
      fontSize: uiFontSize,
      fontFamily: uiFontFamily,
      color: getAdaptiveTextColor(context),
    );

    return Material(
      color: bgColor,
      elevation: 16,
      child: SafeArea(
        top: false,
        bottom: false,
        child: SingleChildScrollView(
          child: Column(
            children: [
              SizedBox(
                height: 60,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: Icon(
                      Icons.menu_open,
                      color: primaryColor,
                      size: 32,
                      semanticLabel: 'Close chapter options',
                    ),
                    tooltip: 'Close',
                    onPressed: () {
                      setState(() => _isOptionsDrawerOpen = false);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<bool>(
                valueListenable: showDialogTskNotifier,
                builder: (context, showDialogTsk, _) {
                  return SwitchListTile(
                    title: Text(
                      showDialogTsk ? 'Show TSK' : 'Hide TSK',
                      style: textStyle,
                    ),
                    value: showDialogTsk,
                    onChanged: (val) async {
                      showDialogTskNotifier.value = val;
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('showDialogTskReferences', val);
                    },
                  );
                },
              ),
              ValueListenableBuilder<bool>(
                valueListenable: showDialogStrongsNotifier,
                builder: (context, showDialogStrongs, _) {
                  return SwitchListTile(
                    title: Text(
                      showDialogStrongs ? 'Show Strong\'s' : 'Hide Strong\'s',
                      style: textStyle,
                    ),
                    value: showDialogStrongs,
                    onChanged: (val) async {
                      showDialogStrongsNotifier.value = val;
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('showDialogStrongs', val);
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? darkBackgroundColor.value : lightBackgroundColor.value;
    final primaryColor =
        isDark ? darkPrimaryColor.value : lightPrimaryColor.value;
    final dialogBorderRadius = BorderRadius.circular(16.0);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: dialogBorderRadius),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: _dialogSize?.width ?? MediaQuery.of(context).size.width * 0.5,
        height: _dialogSize?.height ?? MediaQuery.of(context).size.height * 0.5,
        child: ClipRRect(
          borderRadius: dialogBorderRadius,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // final drawerWidth = constraints.maxWidth <= 304
              //     ? constraints.maxWidth
              //     : (constraints.maxWidth * 0.5).clamp(304.0, 380.0).toDouble();
              final drawerWidth =
                  constraints.maxWidth < 265 ? constraints.maxWidth : 265.0;

              return Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Column(
                    children: [
                      // Header with options menu, book title, and close button
                      Container(
                        decoration: BoxDecoration(
                          color: _adjustBarColor(bgColor),
                        ),
                        // padding: const EdgeInsets.symmetric(
                        //     horizontal: 4, vertical: 4),
                        child: Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.menu,
                                color: primaryColor,
                                size: 32,
                                semanticLabel: 'Chapter options',
                              ),
                              tooltip: 'Options',
                              onPressed: () {
                                setState(() => _isOptionsDrawerOpen = true);
                              },
                            ),
                            Expanded(
                              child: Text(
                                '$bookLongName ${widget.chapter}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: uiFontSize,
                                  fontWeight: FontWeight.bold,
                                  color: getAdaptiveTextColor(context),
                                  fontFamily: uiFontFamily,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.close,
                                color: primaryColor,
                                size: 32,
                                semanticLabel: 'Close',
                              ),
                              tooltip: 'Close',
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                      ),

                      // Chapter content
                      Expanded(
                        child: Container(
                          color: bgColor,
                          child: _loading
                              ? Center(child: CircularProgressIndicator())
                              : ValueListenableBuilder<bool>(
                                  valueListenable: showNotesInlineNotifier,
                                  builder: (context, showNotesInline, _) {
                                    return ValueListenableBuilder<bool>(
                                      valueListenable: showDialogTskNotifier,
                                      builder: (context, showDialogTsk, _) {
                                        return ValueListenableBuilder<bool>(
                                          valueListenable:
                                              showDialogStrongsNotifier,
                                          builder:
                                              (context, showDialogStrongs, _) {
                                            // Rebuild data list when display settings change
                                            _rebuildVerseDataList();
                                            final showBookTitle =
                                                _shouldShowBookTitle;
                                            final showBookColophon =
                                                _shouldShowBookColophon;
                                            final children = <Widget>[
                                              if (showBookTitle)
                                                _buildBookTitleWidget(
                                                    isDark, showDialogStrongs),
                                              ..._verseDataList.map((data) {
                                                return Padding(
                                                  padding:
                                                      EdgeInsetsGeometry.only(
                                                          left: 8.0),
                                                  child:
                                                      buildVerseWidgetFromData(
                                                    context,
                                                    data,
                                                    (verseNum) =>
                                                        _showChapterVerseMenu(
                                                            context, verseNum),
                                                    (verseNum) =>
                                                        _enterHighlightMode(
                                                            context, verseNum),
                                                    _handleVerseLink,
                                                    widget.onNoteIconTap != null
                                                        ? (vn, noteText) =>
                                                            widget.onNoteIconTap!(
                                                                vn, noteText)
                                                        : null,
                                                    widget.onNoteEditTap != null
                                                        ? (vn, noteText) =>
                                                            widget.onNoteEditTap!(
                                                                vn, noteText)
                                                        : null,
                                                    lightTextColor.value,
                                                    darkTextColor.value,
                                                    _showStrongsDefinitionDialog,
                                                    expandStrongsTapTarget:
                                                        true,
                                                  ),
                                                );
                                              }),
                                              if (showBookColophon)
                                                _buildBookColophonWidget(
                                                    isDark, showDialogStrongs),
                                              const SizedBox(height: 16.0),
                                            ];
                                            return ScrollConfiguration(
                                              behavior: ScrollConfiguration.of(
                                                      context)
                                                  .copyWith(scrollbars: false),
                                              child: RawScrollbar(
                                                thumbColor: isDark
                                                    ? darkPrimaryColor.value
                                                        .withValues(alpha: 0.9)
                                                    : lightPrimaryColor.value
                                                        .withValues(alpha: 0.9),
                                                thumbVisibility: false,
                                                trackVisibility: false,
                                                thickness: 22.0,
                                                radius: Radius.circular(8.0),
                                                controller: _scrollController,
                                                child: SingleChildScrollView(
                                                  controller: _scrollController,
                                                  padding:
                                                      const EdgeInsets.only(
                                                          right: 22),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: children,
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: !_isOptionsDrawerOpen,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 180),
                        opacity: _isOptionsDrawerOpen ? 1 : 0,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            setState(() => _isOptionsDrawerOpen = false);
                          },
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: 0.54),
                          ),
                        ),
                      ),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 246),
                    curve: Curves.easeOutCubic,
                    top: 0,
                    bottom: 0,
                    left: _isOptionsDrawerOpen ? 0 : -drawerWidth,
                    width: drawerWidth,
                    child: _buildOptionsDrawer(bgColor, primaryColor),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _showChapterVerseMenu(BuildContext context, int verseNumber) {
    final verseData = _verses.firstWhere(
        (v) => toInt(v['verse'], orElse: -1) == verseNumber,
        orElse: () => <String, Object>{});
    final verseText = verseData['text'] as String? ?? '';

    final cleanVerseText = VerseTextParser.toPlainVerseText(verseText);
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
                    'Goto Verse $verseNumber',
                    style: TextStyle(
                        fontFamily: uiFontFamily,
                        fontSize: uiFontSize + 8,
                        color: getAdaptiveTextColor(context)),
                  )),
                  onTap: () {
                    Navigator.of(context).pop();
                    _gotoVerseAndCloseAllChapterDialogs(verseNumber);
                  },
                ),
                ListTile(
                  title: Center(
                      child: Text(
                    _notes.containsKey(verseNumber) ? 'Edit Note' : 'Add Note',
                    style: TextStyle(
                        fontFamily: uiFontFamily,
                        fontSize: uiFontSize + 8,
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
                        fontSize: uiFontSize + 8,
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
                        fontSize: uiFontSize + 8,
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

  void _gotoVerseAndCloseAllChapterDialogs(int verseNumber) {
    // Capture callback before popping routes, as this dialog state may be disposed.
    final navigateToVerse = widget.onNavigateToVerse;

    // Close all currently open popup routes (bottom sheets + nested chapter dialogs).
    Navigator.of(context, rootNavigator: true)
        .popUntil((route) => route is! PopupRoute);

    // Navigate the originating Bible screen using the standard callback.
    if (navigateToVerse != null) {
      navigateToVerse(verseNumber);
    }
  }

  void _openMultipleVersesDialog(int verseNumber) {
    showMultipleVersesDialog(
      context: context,
      book: bookLongName,
      chapter: widget.chapter,
      initialVerse: verseNumber,
      verses: _verses,
    );
  }

  void _showStrongsDefinitionDialog(String strongsNumber) {
    StrongsDefinitionDialog.show(context, strongsNumber);
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
        if (!mounted) return;
        _rebuildVerseDataList();
        setState(() {});
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
    _localHighlightsSubscription.cancel();
    _localNotesSubscription.cancel();

    // Dispose controllers
    _scrollController.dispose();
    _localShowNotesInlineFallback.dispose();

    super.dispose();
  }
}
