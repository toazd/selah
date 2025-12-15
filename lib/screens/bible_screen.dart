import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'; // for Clipboard
import 'package:selah/utils/snackbar_notification.dart';
import '../database/bible_database.dart';
import '../utils/preferences_constants.dart';
import '../database/history_database.dart';
import '../main.dart'; // For color notifiers
import '../services/firestore_sync_service.dart';
import 'verse_chooser_dialog.dart'; // <-- new import
import 'note_screen.dart'; // <-- new import
import 'dart:async'; // For StreamSubscription
import '../services/local_data_change_notifier.dart';
import '../utils/verse_display_utils.dart'; // <-- new import for shared verse display utilities
import '../utils/book_name_converter.dart';
import '../utils/bible_utils.dart'; // <-- shared utility functions
import '../utils/data_loaders.dart'; // <-- shared data loading functions
import '../utils/dialog_utils.dart'; // <-- shared dialog functions
import '../utils/font_size_adjustments.dart';
import 'bible_screen_header.dart'; // Import custom header

// Helper function to create a slightly different shade for bars
Color _adjustBarColor(Color backgroundColor, BuildContext context) {
  final hsl = HSLColor.fromColor(backgroundColor);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  // If dark mode / dark colors, adjust slightly more than light mode / light colors
  if (isDark) {
    final adjustedLightness = hsl.lightness > 0.5
        ? (hsl.lightness - 0.05).clamp(0.0, 1.0) // Darker for light backgrounds
        : (hsl.lightness + 0.05).clamp(0.0, 1.0); // Lighter for dark backgrounds
    return hsl.withLightness(adjustedLightness).toColor();
  } else {
    final adjustedLightness = hsl.lightness > 0.5
        ? (hsl.lightness - 0.02).clamp(0.0, 1.0) // Darker for light backgrounds
        : (hsl.lightness + 0.02).clamp(0.0, 1.0); // Lighter for dark backgrounds
    return hsl.withLightness(adjustedLightness).toColor();
  }
}

class BibleScreen extends StatefulWidget {
  final String? initialBook;
  final int? initialChapter;
  final int? initialVerse;
  final bool showViewMenu;
  final void Function(String?, int?, int?)? onLocationChanged;
  final VoidCallback? onOpenDrawer;
  final VoidCallback? onShowHistory;
  final Future<void> Function()? onShowSearch;
  // Add: external notes inline mode toggle (default: false => "Icon mode")
  final ValueListenable<bool>? showNotesInline;

  const BibleScreen({
    super.key,
    this.initialBook,
    this.initialChapter,
    this.initialVerse,
    this.showViewMenu = false,
    this.onLocationChanged,
    this.onOpenDrawer,
    this.onShowHistory,
    this.onShowSearch,
    this.showNotesInline, // optional listenable for notes display mode
  });
  @override
  State<BibleScreen> createState() => _BibleScreenState();
}

class _BibleScreenState extends State<BibleScreen> {
  List<String> _books = [];
  List<int> _chapters = [];
  List<Map<String, dynamic>> _verses = [];
  String? _selectedBook;
  int? _selectedChapter;
  int? _selectedVerse;
  bool _loading = true;
  String? _bookTitle;
  String? _bookColophon;
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _verseKeys = {}; // key per verse
  // Local fallback for notes inline mode
  late final ValueNotifier<bool> _localShowNotesInlineFallback = ValueNotifier<bool>(true);
  Map<int, Map<String, dynamic>> _notes = {};
  Map<int, List<Map<String, dynamic>>> _highlights = {};

  // Scroll management to prevent overshooting
  bool _isScrolling = false;
  DateTime? _lastScrollTime;
  // Navigation management to prevent rapid successive navigation
  bool _isNavigating = false;

  // Stream subscriptions for real-time updates
  late StreamSubscription _highlightsSubscription;
  late StreamSubscription _notesSubscription;

  @override
  void initState() {
    super.initState();

    _loadInitialLocation();

    // this dual notifier stream system is required to support ui updates
    // whether the user is logged in or not

    // Listen to local data change notifier streams for immediate updates during local operations
    LocalDataChangeNotifier.highlightsChangedStream.listen((_) async {
      await _loadHighlights();

      if (mounted) {
        setState(() {});
      }
    });

    // Listen to sync service streams for real-time updates
    _highlightsSubscription = FirestoreSyncService.highlightsChangedStream.listen((_) async {
      await _loadHighlights();

      if (mounted) {
        setState(() {});
      } else {}
    });

    // local
    LocalDataChangeNotifier.notesChangedStream.listen((_) async {
      await _loadNotes();
      if (mounted) setState(() {});
    });

    // remote
    _notesSubscription = FirestoreSyncService.notesChangedStream.listen((_) async {
      await _loadNotes();
      if (mounted) setState(() {});
      // Add this debug print
    });
  }

  Future<void> _loadInitialLocation() async {
    _books = await BibleDatabase.getBooks();
    _selectedBook = (widget.initialBook != null && _books.contains(widget.initialBook)) ? widget.initialBook : (_books.isNotEmpty ? _books.first : null);
    _chapters = _selectedBook != null ? await BibleDatabase.getChapters(_selectedBook!) : [];
    _selectedChapter = (widget.initialChapter != null && _chapters.contains(widget.initialChapter)) ? widget.initialChapter : (_chapters.isNotEmpty ? _chapters.first : null);
    await _loadVerses();
    // Load book metadata after setting the initial book
    await _loadBookMetadata();
    _selectedVerse = (widget.initialVerse != null && _verses.any((v) => v['verse'] == widget.initialVerse)) ? widget.initialVerse : null;

    setState(() {
      _loading = false;
    });
    // Scroll after first build
    _scrollToSelected();
  }

  Future<void> _loadVerses() async {
    if (_selectedBook != null && _selectedChapter != null) {
      _verses = await BibleDatabase.getVerses(_selectedBook!, _selectedChapter!);
      // Enforce database order: first by `id` if present, otherwise by `verse`
      if (_verses.isNotEmpty) {
        final hasId = _verses.first.containsKey('id');
        _verses.sort((a, b) {
          final left = hasId ? toInt(a['id']) : toInt(a['verse']);
          final right = hasId ? toInt(b['id']) : toInt(b['verse']);
          return left.compareTo(right);
        });
      }
      // Rebuild verse keys
      _verseKeys.clear();
      for (final v in _verses) {
        final n = toInt(v['verse'], orElse: 0);
        if (n > 0) _verseKeys[n] = GlobalKey();
      }
      await _loadNotes();
      await _loadHighlights();
    } else {
      _verses = [];
      _verseKeys.clear();
      _notes.clear();
      _highlights.clear();
    }
  }

  Future<void> _loadNotes() async {
    if (_selectedBook != null && _selectedChapter != null) {
      _notes = await loadNotesForChapter(_selectedBook!, _selectedChapter!);
    } else {
      _notes.clear();
    }
  }

  Future<void> _loadHighlights() async {
    if (_selectedBook != null && _selectedChapter != null) {
      _highlights = await loadHighlightsForChapter(_selectedBook!, _selectedChapter!);
    } else {
      _highlights.clear();
    }
  }

  Future<void> _loadBookMetadata() async {
    if (_selectedBook != null) {
      Map<String, dynamic>? metadata;

      //debugPrint('_selectedBook: $_selectedBook');

      // Only pass chapter parameter for Psalms
      if (_selectedBook == 'Psa') {
        metadata = await BibleDatabase.getBookMetadata(
          _selectedBook as String,
          chapter: _selectedChapter,
        );
      } else {
        metadata = await BibleDatabase.getBookMetadata(_selectedBook as String);
      }

      _bookTitle = metadata?['title'] as String?;
      _bookColophon = metadata?['colophon'] as String?;

      if (mounted) {
        setState(() {});
      }
    } else {
      setState(() {
        _bookTitle = null;
        _bookColophon = null;
      });
    }
  }

  Future<void> _recordHistory() async {
    if (_selectedBook != null && _selectedChapter != null) {
      HistoryDatabase.addHistory(_selectedBook!, _selectedChapter!, _selectedVerse ?? 1, DateTime.now().millisecondsSinceEpoch, false);
      // Note: Sync is handled automatically by the database operation
    }
  }

  Future<void> _onChapterChanged(int? chapter, {bool recordHistory = true}) async {
    if (_isNavigating || chapter == null) {
      return;
    }
    _isNavigating = true;
    try {
      setState(() {
        _loading = true;
      });
      _selectedChapter = chapter;

      // Reload metadata for Psalm superscriptions (titles)
      if (_selectedBook == 'Psa') {
        await _loadBookMetadata();
      }

      await _loadVerses();

      setState(() {
        // Set to null for chapter 1 OR for Psalms with titles (scroll to top), verse 1 otherwise
        final shouldScrollToTop = chapter == 1 || (_selectedBook == 'Psa' && _bookTitle != null);
        _selectedVerse = shouldScrollToTop ? null : 1;
        _loading = false;
      });
      if (widget.onLocationChanged != null) {
        widget.onLocationChanged!(_selectedBook, _selectedChapter, _selectedVerse);
      }
      if (recordHistory) {
        _recordHistory();
      }
      // Scroll to selected verse (or top for chapter 1) after chapter navigation
      _scrollToSelected();
    } finally {
      _isNavigating = false;
    }
  }

  // Handle next chapter navigation (used by swipe gestures and buttons)
  Future<void> _handleNextChapter() async {
    if (_isNavigating) {
      return;
    }
    if (_selectedChapter != null && _chapters.isNotEmpty && _selectedChapter! < _chapters.last) {
      // Next chapter in same book
      await _onChapterChanged(_selectedChapter! + 1, recordHistory: false);
    } else if (_selectedChapter == _chapters.last && _books.indexOf(_selectedBook!) < _books.length - 1 && _selectedBook != _books.last) {
      // Next book, first chapter - use atomic navigation to prevent race conditions
      final nextBookIndex = _books.indexOf(_selectedBook!) + 1;
      final nextBook = _books[nextBookIndex];
      await _navigateToNextBook(nextBook, recordHistory: false);
    }
  }

  // Atomic navigation to next book to prevent race conditions
  Future<void> _navigateToNextBook(String nextBook, {bool recordHistory = true}) async {
    if (!mounted) return;

    // Perform all operations atomically in a single setState block
    setState(() {
      _loading = true;
    });

    try {
      // Update book and load metadata
      _selectedBook = nextBook;
      await _loadBookMetadata();

      // Load chapters for the new book
      _chapters = await BibleDatabase.getChapters(nextBook);

      if (_chapters.isNotEmpty) {
        // Set to first chapter of new book
        _selectedChapter = _chapters.first;
        await _loadVerses();

        // Set verse to null for chapter 1 (scroll to top), verse 1 otherwise
        _selectedVerse = _chapters.first == 1 ? null : 1;

        if (widget.onLocationChanged != null) {
          widget.onLocationChanged!(_selectedBook, _selectedChapter, _selectedVerse);
        }

        if (recordHistory) {
          await _recordHistory();
        }

        // Scroll to selected verse after state is updated
        _scrollToSelected();
      } else {
        // Handle case where book has no chapters (shouldn't happen but being defensive)
        _selectedChapter = null;
        _selectedVerse = null;
        _verses = [];
        _verseKeys.clear();
      }
    } catch (e) {
      // Handle any errors during navigation
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // Atomic navigation to previous book to prevent race conditions
  Future<void> _navigateToPreviousBook(String prevBook, {bool recordHistory = true}) async {
    if (!mounted) return;

    // Perform all operations atomically in a single setState block
    setState(() {
      _loading = true;
    });

    try {
      // Update book and load metadata
      _selectedBook = prevBook;
      await _loadBookMetadata();

      // Load chapters for the new book
      _chapters = await BibleDatabase.getChapters(prevBook);

      if (_chapters.isNotEmpty) {
        // Set to last chapter of previous book
        _selectedChapter = _chapters.last;
        await _loadVerses();

        // Set verse to null for chapter 1 (scroll to top), verse 1 otherwise
        _selectedVerse = _chapters.last == 1 ? null : 1;

        if (widget.onLocationChanged != null) {
          widget.onLocationChanged!(_selectedBook, _selectedChapter, _selectedVerse);
        }

        if (recordHistory) {
          _recordHistory();
        }

        // Scroll to selected verse (or top for chapter 1) after state is updated
        _scrollToSelected();
      } else {
        // Handle case where book has no chapters (shouldn't happen but being defensive)
        _selectedChapter = null;
        _selectedVerse = null;
        _verses = [];
        _verseKeys.clear();
      }
    } catch (e) {
      // Handle any errors during navigation
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // Handle previous chapter navigation (used by swipe gestures and buttons)
  Future<void> _handlePreviousChapter() async {
    if (_isNavigating) {
      return;
    }
    if (_selectedChapter != null && _chapters.isNotEmpty && _selectedChapter! > _chapters.first) {
      // Previous chapter in same book
      await _onChapterChanged(_selectedChapter! - 1, recordHistory: false);
    } else if (_selectedChapter == _chapters.first && _books.indexOf(_selectedBook!) > 0 && _selectedBook != _books.first) {
      // Previous book, last chapter - use atomic navigation to prevent race conditions
      final prevBookIndex = _books.indexOf(_selectedBook!) - 1;
      final prevBook = _books[prevBookIndex];
      await _navigateToPreviousBook(prevBook, recordHistory: false);
    }
  }

  void _scrollToSelected({bool animate = true}) {
    // Prevent rapid successive scroll calls that cause overshooting
    final now = DateTime.now();
    if (_isScrolling && _lastScrollTime != null) {
      final timeSinceLastScroll = now.difference(_lastScrollTime!);
      if (timeSinceLastScroll.inMilliseconds < 500) {
        return;
      }
    }

    _isScrolling = true;
    _lastScrollTime = now;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // If no verse is selected (null), scroll to the top of the scroll view
      if (_selectedVerse == null) {
        if (animate) {
          _scrollController
              .animateTo(
            0.0,
            duration: Duration(milliseconds: 500),
            curve: Curves.easeOut,
          )
              .then((_) {
            _isScrolling = false;
          }).catchError((error) {
            _isScrolling = false;
          });
        } else {
          _scrollController.jumpTo(0.0);
          _isScrolling = false;
        }

        return;
      }

      // Otherwise, scroll to the selected verse
      final key = _verseKeys[_selectedVerse!];

      final ctx = key?.currentContext;
      if (ctx != null) {
        try {
          // Use different alignment values based on layout mode
          // In horizontal layout (stacked vertically), use smaller alignment to prevent overshooting
          // In vertical layout (side by side), keep the original alignment
          final alignment = isVerticalTile.value ? 0.005 : 0.025; // 0.025 for vertical, 0.015 for horizontal

          Scrollable.ensureVisible(
            ctx,
            alignment: alignment,
            duration: Duration(milliseconds: animate ? 250 : 0), // Slightly faster animation
            curve: Curves.easeOut, // Use easeOut for more natural feel
          ).then((_) {
            // Reset scrolling flag after animation completes
            Future.delayed(Duration(milliseconds: animate ? 250 : 0), () {
              _isScrolling = false;
            });
          }).catchError((error) {
            // Reset flag on error too
            _isScrolling = false;
          });
        } catch (e) {
          // Reset flag if ensureVisible fails
          _isScrolling = false;
        }
      } else {
        // Reset flag if context is not available
        _isScrolling = false;
      }
    });
  }

  @override
  void didUpdateWidget(covariant BibleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    /*
    debugPrint('=== didUpdateWidget COMPARISON ===');
    debugPrint(
        'initialBook: ${oldWidget.initialBook} → ${widget.initialBook} (${oldWidget.initialBook != widget.initialBook})');
    debugPrint(
        'initialChapter: ${oldWidget.initialChapter} → ${widget.initialChapter} (${oldWidget.initialChapter != widget.initialChapter})');
    debugPrint(
        'initialVerse: ${oldWidget.initialVerse} → ${widget.initialVerse} (${oldWidget.initialVerse != widget.initialVerse})');
    debugPrint(
        'showViewMenu: ${oldWidget.showViewMenu} → ${widget.showViewMenu} (${oldWidget.showViewMenu != widget.showViewMenu})');
    debugPrint(
        'onLocationChanged: ${oldWidget.onLocationChanged} → ${widget.onLocationChanged} (${oldWidget.onLocationChanged != widget.onLocationChanged})');
    debugPrint(
        'onOpenDrawer: ${oldWidget.onOpenDrawer} → ${widget.onOpenDrawer} (${oldWidget.onOpenDrawer != widget.onOpenDrawer})');
    debugPrint(
        'onShowHistory: ${oldWidget.onShowHistory} → ${widget.onShowHistory} (${oldWidget.onShowHistory != widget.onShowHistory})');
    debugPrint(
        'onShowSearch: ${oldWidget.onShowSearch} → ${widget.onShowSearch} (${oldWidget.onShowSearch != widget.onShowSearch})');
    debugPrint(
        'showNotesInline: ${oldWidget.showNotesInline} → ${widget.showNotesInline} (${oldWidget.showNotesInline != widget.showNotesInline})');
    debugPrint('================================');
    */

    // If navigation props changed, update state
    if (widget.initialBook != oldWidget.initialBook || widget.initialChapter != oldWidget.initialChapter || widget.initialVerse != oldWidget.initialVerse) {
      _navigateToLocation();
    }
  }

  Future<void> _navigateToLocation() async {
    if (widget.initialBook != null) {
      _books = await BibleDatabase.getBooks();
      _selectedBook = widget.initialBook;
      _chapters = await BibleDatabase.getChapters(_selectedBook!);
      _selectedChapter = widget.initialChapter ?? (_chapters.isNotEmpty ? _chapters.first : null);
      await _loadVerses();

      // When chapter 1 and verse 1 is chosen, set _selectedVerse to NULL so the book title is shown
      _selectedVerse = (widget.initialChapter == 1 && widget.initialVerse == 1) ? null : widget.initialVerse;
      setState(() {});
      _scrollToSelected();
    }
  }

  // Add: transactional apply to avoid intermediate callbacks resetting chapter to 1
  Future<void> _applyLocation(String book, int chapter, int? verse, {bool notify = true}) async {
    setState(() {
      _loading = true;
    });

    // Ensure books are loaded
    if (_books.isEmpty) {
      _books = await BibleDatabase.getBooks();
    }

    // Update book
    _selectedBook = book;
    await _loadBookMetadata();

    // Load chapters for book and clamp chapter
    _chapters = await BibleDatabase.getChapters(book);
    if (_chapters.isEmpty) {
      _selectedChapter = null;
      _verses = [];
      _verseKeys.clear();
    } else {
      if (!_chapters.contains(chapter)) {
        chapter = _chapters.first;
      }
      _selectedChapter = chapter;
      await _loadVerses();
    }

    // Set verse only if it exists in the loaded verses
    if (verse != null && _verses.any((v) => toInt(v['verse'], orElse: -1) == verse)) {
      _selectedVerse = (chapter == 1 && verse == 1) ? null : verse;
    } else {
      _selectedVerse = null;
    }

    setState(() {
      _loading = false;
    });

    if (notify) {
      widget.onLocationChanged?.call(_selectedBook, _selectedChapter, _selectedVerse);
      await _recordHistory();
    }

    _scrollToSelected();
  }

  // Verse chooser dialog
  Future<void> _openVerseChooser() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      useSafeArea: true,
      builder: (context) => VerseChooserDialog(
          // initialBook: _selectedBook,
          // initialChapter: _selectedChapter,
          // initialVerse: _selectedVerse,
          ),
    );
    if (result != null) {
      final String book = result['book'] as String;
      final int chapter = result['chapter'] as int;
      final int verse = result['verse'] as int;
      // Apply atomically to prevent chapter being reset to 1 via intermediate callbacks
      await _applyLocation(book, chapter, verse);
    }
  }

  void _showAddNoteMenu(BuildContext context, int vn) {
    final verseData = _verses.firstWhere((v) => toInt(v['verse'], orElse: -1) == vn, orElse: () => <String, Object>{});
    final verseText = verseData['text'] as String? ?? '';

    // Filter out red letter tags <r> and </r>, and pilcrow symbols
    final redLetterRegex = RegExp(r'</?r>');
    final cleanVerseText = verseText.replaceAll(redLetterRegex, '').replaceAll('¶ ', '');
    final bookName = BookNameConverter.shortNameToLongName(_selectedBook!);
    final copyText = '$bookName ${_selectedChapter!}:$vn\n$cleanVerseText';

    showModalBottomSheet(
        context: context,
        builder: (context) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Center(
                      child: Text(
                    _notes.containsKey(vn) ? 'Edit Note' : 'Add Note',
                    style: TextStyle(fontFamily: fontFamilyNotifier.value, fontSize: uiFontSize + 10, color: getAdaptiveTextColor(context)),
                  )),
                  onTap: () {
                    Navigator.of(context).pop();
                    _openNote(vn, _notes[vn]?['note_text']);
                  },
                ),
                ListTile(
                  title: Center(
                      child: Text(
                    'Copy Verse $vn',
                    style: TextStyle(fontFamily: fontFamilyNotifier.value, fontSize: uiFontSize + 10, color: getAdaptiveTextColor(context)),
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
                        showStyledSnackBar(context, 'Copy failed', isError: true);
                      }
                    }
                  },
                ),
                ListTile(
                  title: Center(
                      child: Text(
                    'Copy Multiple Verses',
                    style: TextStyle(fontFamily: fontFamilyNotifier.value, fontSize: uiFontSize + 10, color: getAdaptiveTextColor(context)),
                  )),
                  onTap: () {
                    Navigator.of(context).pop();
                    _openMultipleVersesDialog(vn);
                  },
                ),
              ],
            ));
  }

  Future<void> _openNote(int vn, [String? existingNote, String? book, int? chapter]) async {
    final noteBook = book ?? _selectedBook!;
    final noteChapter = chapter ?? _selectedChapter!;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => NoteScreen(book: noteBook, chapter: noteChapter, verse: vn, existingNote: existingNote)));
    await _loadNotes();
    // Note: sync operations are handled by database update methods, no need for additional marking
    if (mounted) setState(() {});
  }

  void _openMultipleVersesDialog(int vn) {
    showMultipleVersesDialog(
      context: context,
      book: _selectedBook!,
      chapter: _selectedChapter!,
      initialVerse: vn,
      verses: _verses,
    );
  }

  void _enterHighlightMode(BuildContext context, int vn) async {
    final verseData = _verses.firstWhere((v) => toInt(v['verse'], orElse: -1) == vn, orElse: () => <String, Object>{});
    final rawVerseText = verseData['text'] as String? ?? '';

    await showHighlightDialog(
      context: context,
      rawVerseText: rawVerseText,
      verseNumber: vn,
      book: _selectedBook!,
      chapter: _selectedChapter!,
      onFinished: () {
        // Refresh highlights when dialog closes
        _loadHighlights();
        if (mounted) {
          setState(() {});
        }
      },
    );
  }

  // Build Widget for verse mode
  Widget _buildVerseModeWidget({
    required BuildContext context,
    required double lineHeight,
    required Color verseNumberColor,
    required Color verseTextColor,
    required bool showNotesInline,
    required Color backgroundColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: buildVerseListWidget(
        context: context,
        verses: _verses,
        verseKeys: _verseKeys,
        notes: _notes,
        highlights: _highlights,
        textColor: verseTextColor,
        verseNumberColor: verseNumberColor,
        backgroundColor: backgroundColor,
        lineHeight: lineHeightNotifier.value,
        showNotesInline: showNotesInline,
        fontFamily: fontFamilyNotifier.value,
        lightHighlightTextColor: lightTextColor.value,
        darkHighlightTextColor: darkTextColor.value,
        onVerseTap: (verseNum) => _showAddNoteMenu(context, verseNum),
        onVerseLongPress: (verseNum) => _enterHighlightMode(context, verseNum),
        onLinkTap: (link, referenceText) => handleVerseLink(
          context,
          link,
          referenceText,
          navigateToVerse: _applyLocation,
          onVerseLinkRecursion: null, // Infinite recursion enabled by default in handleVerseLink
          onNoteIconTap: (book, chapter, verse, noteText) => _openNote(verse, noteText, book, chapter),
          onNoteEditTap: (book, chapter, verse, noteText) => _openNote(verse, noteText, book, chapter),
        ),
        lightVerseReferenceColor: lightVerseReferenceColor,
        darkVerseReferenceColor: darkVerseReferenceColor,
        onNoteIconTap: (vn, noteText) => _openNote(vn, noteText),
        onNoteEditTap: (vn, noteText) => _openNote(vn, noteText),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final verseTextColor = isDark ? darkTextColor.value : lightTextColor.value;
    //final textColor = isDark ? darkTextColor.value : lightTextColor.value;
    final bibleBgColor = isDark ? darkBackgroundColor.value : lightBackgroundColor.value;
    //final biblePrimaryColor = isDark ? darkPrimaryColor.value : lightPrimaryColor.value;
    // Derived verse number color from primary color
    final verseNumberColor = isDark ? darkPrimaryColor.value : lightPrimaryColor.value; //_deriveVerseNumberColor(verseTextColor, background: bibleBgColor);
    // Adjusted color for bars (app bar and bottom navigation)
    final barColor = _adjustBarColor(bibleBgColor, context);

    // return SafeArea(
    //   bottom: false,
    //   child:
    return Column(
      //mainAxisSize: MainAxisSize.min,
      children: [
        // Custom header to replace AppBar
        BibleScreenHeader(
          showViewMenu: widget.showViewMenu,
          onOpenDrawer: widget.onOpenDrawer,
          onShowHistory: widget.onShowHistory,
          onShowSearch: widget.onShowSearch,
          onTitlePressed: _openVerseChooser,
          selectedBook: _selectedBook,
          selectedChapter: _selectedChapter,
        ),
        Expanded(
          child: Container(
            color: bibleBgColor,
            child: _loading
                ? Center(child: CircularProgressIndicator())
                : ValueListenableBuilder<bool>(
                    valueListenable: widget.showNotesInline ?? _localShowNotesInlineFallback,
                    builder: (context, showNotesInline, _) {
                      return ValueListenableBuilder<bool>(
                        valueListenable: showNavigationBarNotifier,
                        builder: (context, showNavBar, _) {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onHorizontalDragEnd: (DragEndDetails details) {
                                    // Only process if not currently navigating
                                    if (_isNavigating) return;

                                    // Swipe navigation minimum velocity for changing chapters
                                    const minVelocity = 300.0;

                                    // Ensure the swipe is primarily horizontal
                                    final horizontalVelocity = details.velocity.pixelsPerSecond.dx.abs();
                                    final verticalVelocity = details.velocity.pixelsPerSecond.dy.abs();

                                    if (horizontalVelocity > minVelocity && horizontalVelocity > verticalVelocity * 2) {
                                      if (details.velocity.pixelsPerSecond.dx > 0) {
                                        _handlePreviousChapter();
                                      } else {
                                        _handleNextChapter();
                                      }
                                    }
                                  },
                                  child: Builder(
                                    builder: (context) {
                                      //final lineHeight = lineHeightNotifier.value;

                                      return RawScrollbar(
                                          thumbColor: isDark ? darkPrimaryColor.value.withValues(alpha: 0.3) : lightPrimaryColor.value.withValues(alpha: 0.5),
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
                                                    // Leave a large blank gap at the bottom for when reading while laying down
                                                    padding: EdgeInsets.only(left: 0.0, top: 8.0, bottom: 300.0, right: 16.0),
                                                    child: Column(
                                                      mainAxisSize: MainAxisSize.min,
                                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                                      // Add book title and colophon
                                                      children: [
                                                        // Show book title only on Chapter 1, or for Psalms (superscriptions)
                                                        if (_bookTitle != null && (_selectedChapter == 1 || _selectedBook == 'Psa'))
                                                          Padding(
                                                            padding: const EdgeInsets.only(bottom: 16.0),
                                                            child: Center(
                                                              child: Text(
                                                                _bookTitle!,
                                                                textAlign: TextAlign.center,
                                                                style: TextStyle(
                                                                  fontWeight: FontWeight.bold,
                                                                  fontSize: FontSizeAdjustments.getAdjustedSize(fontFamilyNotifier.value, fontSizeNotifier.value + 1),
                                                                  color: isDark ? darkTextColor.value : lightTextColor.value,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        // Always use verse mode
                                                        _buildVerseModeWidget(
                                                          context: context,
                                                          lineHeight: lineHeightNotifier.value,
                                                          verseNumberColor: verseNumberColor,
                                                          verseTextColor: verseTextColor,
                                                          showNotesInline: showNotesInline,
                                                          backgroundColor: bibleBgColor,
                                                        ),
                                                        // Show colophon only on the last chapter
                                                        if (_bookColophon != null && _bookColophon!.isNotEmpty && _chapters.isNotEmpty && _selectedChapter == _chapters.last)
                                                          Padding(
                                                            padding: const EdgeInsets.only(top: 16.0),
                                                            child: Text(
                                                              _bookColophon!,
                                                              textAlign: TextAlign.left,
                                                              style: TextStyle(
                                                                fontStyle: FontStyle.italic,
                                                                fontSize: FontSizeAdjustments.getAdjustedSize(fontFamilyNotifier.value, fontSizeNotifier.value - 1),
                                                                color: isDark ? darkTextColor.value : lightTextColor.value,
                                                              ),
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ))));
                                    },
                                  ),
                                ),
                              ),
                              if (showNavBar)
                                Container(
                                  margin: EdgeInsetsGeometry.all(0),
                                  padding: EdgeInsetsGeometry.all(0),
                                  // decoration: BoxDecoration(
                                  //   border: Border.all(
                                  //     color: Colors.red, // The color of the border
                                  //     width: 2.0, // The thickness of the border (optional)
                                  //   ),
                                  // ),
                                  width: double.infinity,
                                  height: 40,
                                  color: barColor,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Expanded(
                                        // child: Container(
                                        //   decoration: BoxDecoration(
                                        //     border: Border.all(
                                        //       color: Colors.red, // The color of the border
                                        //       width: 2.0, // The thickness of the border (optional)
                                        //     ),
                                        //   ),
                                        child: Center(
                                          child: IconButton(
                                            icon: Icon(
                                              Icons.arrow_back_ios_new,
                                              color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
                                              semanticLabel: 'Navigate to the Previous Chapter',
                                              size: 24.0,
                                            ),
                                            tooltip: 'Previous Chapter',
                                            color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
                                            onPressed: _selectedChapter != null && _chapters.isNotEmpty && _selectedChapter! > _chapters.first
                                                ? () => _onChapterChanged(_selectedChapter! - 1, recordHistory: false)
                                                : (_selectedChapter == _chapters.first && _books.indexOf(_selectedBook!) > 0 && _selectedBook != _books.first)
                                                    ? () => _handlePreviousChapter()
                                                    : null,
                                          ),
                                        ),
                                        //),
                                      ),
                                      Expanded(
                                        child: Center(
                                          child: IconButton(
                                            icon: Icon(
                                              Icons.arrow_forward_ios,
                                              color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
                                              semanticLabel: 'Navigate to the next chapter',
                                              size: 24.0,
                                            ),
                                            tooltip: 'Next Chapter',
                                            color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
                                            onPressed: _selectedChapter != null && _chapters.isNotEmpty && _selectedChapter! < _chapters.last
                                                ? () => _onChapterChanged(_selectedChapter! + 1, recordHistory: false)
                                                : (_selectedChapter == _chapters.last && _books.indexOf(_selectedBook!) < _books.length - 1 && _selectedBook != _books.last)
                                                    ? () => _handleNextChapter()
                                                    : null,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          );
                        },
                      );
                    },
                  ),
          ),
        ),
      ],
      //),
    );
  }

  @override
  void dispose() {
    // Reset scroll state to prevent issues if widget is rebuilt
    _isScrolling = false;
    _lastScrollTime = null;

    // Cancel stream subscriptions
    _highlightsSubscription.cancel();
    _notesSubscription.cancel();

    // Dispose controllers to prevent memory leaks
    _scrollController.dispose();
    _localShowNotesInlineFallback.dispose();

    super.dispose();
  }
}
