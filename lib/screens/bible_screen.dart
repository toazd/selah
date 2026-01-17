import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'; // for Clipboard
import 'package:selah/utils/snackbar_notification.dart';
import '../database/bible_database.dart';
import '../database/notes_database.dart';
import '../utils/preferences_constants.dart';
import '../database/history_database.dart';
import '../main.dart'; // For color notifiers
import '../services/supabase_sync_service.dart';
import 'verse_chooser_dialog.dart';
import 'note_screen.dart';
import 'note_search_screen.dart';
import 'dart:async'; // For StreamSubscription
import '../services/local_data_change_notifier.dart';
import '../utils/book_name_converter.dart';
import '../utils/bible_utils.dart'; // shared utility functions
import '../utils/data_loaders.dart'; // shared data loading functions
import '../utils/dialog_utils.dart'; // shared dialog functions
import 'bible_screen_header.dart'; // Import custom header
import '../widgets/chapter_content_widget.dart'; // For PageView chapter display

// Helper function to create a slightly different shade for bars
Color _adjustBarColor(Color backgroundColor, BuildContext context) {
  final hsl = HSLColor.fromColor(backgroundColor);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  // If dark mode / dark colors, adjust slightly more than light mode / light colors
  if (isDark) {
    final adjustedLightness = hsl.lightness > 0.5
        ? (hsl.lightness - 0.05).clamp(0.0, 1.0) // Darker for light backgrounds
        : (hsl.lightness + 0.05)
            .clamp(0.0, 1.0); // Lighter for dark backgrounds
    return hsl.withLightness(adjustedLightness).toColor();
  } else {
    final adjustedLightness = hsl.lightness > 0.5
        ? (hsl.lightness - 0.02).clamp(0.0, 1.0) // Darker for light backgrounds
        : (hsl.lightness + 0.02)
            .clamp(0.0, 1.0); // Lighter for dark backgrounds
    return hsl.withLightness(adjustedLightness).toColor();
  }
}

/// Data class to hold preloaded chapter information for PageView caching
class _ChapterData {
  final String book;
  final int chapter;
  final List<Map<String, dynamic>> verses;
  final Map<int, Map<String, dynamic>> notes;
  final Map<int, List<Map<String, dynamic>>> highlights;
  final String? bookTitle;
  final String? bookColophon;
  final bool isLastChapter;

  const _ChapterData({
    required this.book,
    required this.chapter,
    required this.verses,
    required this.notes,
    required this.highlights,
    this.bookTitle,
    this.bookColophon,
    this.isLastChapter = false,
  });

  /// Creates a copy with updated fields
  _ChapterData copyWith({
    Map<int, Map<String, dynamic>>? notes,
    Map<int, List<Map<String, dynamic>>>? highlights,
  }) {
    return _ChapterData(
      book: book,
      chapter: chapter,
      verses: verses,
      notes: notes ?? this.notes,
      highlights: highlights ?? this.highlights,
      bookTitle: bookTitle,
      bookColophon: bookColophon,
      isLastChapter: isLastChapter,
    );
  }
}

class BibleScreen extends StatefulWidget {
  final String? initialBook;
  final int? initialChapter;
  final int? initialVerse;
  //final bool showViewMenu;
  final void Function(String?, int?, int?)? onLocationChanged;
  final VoidCallback? onOpenDrawer;
  final VoidCallback? onShowHistory;
  final Future<void> Function()? onShowSearch;
  // Add: external notes inline mode toggle (default: false => "Icon mode")
  final ValueListenable<bool>? showNotesInline;
  final VoidCallback? onShowNotesSearch;
  //final VoidCallback? onShowBookmarksManager;
  final VoidCallback? onNoteScreenClosed;

  const BibleScreen({
    super.key,
    this.initialBook,
    this.initialChapter,
    this.initialVerse,
    //this.showViewMenu = false,
    this.onLocationChanged,
    this.onOpenDrawer,
    this.onShowHistory,
    this.onShowSearch,
    this.showNotesInline, // optional listenable for notes display mode
    this.onShowNotesSearch,
    //this.onShowBookmarksManager,
    this.onNoteScreenClosed,
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
  // Local fallback for notes inline mode
  late final ValueNotifier<bool> _localShowNotesInlineFallback =
      ValueNotifier<bool>(true);
  Map<int, Map<String, dynamic>> _notes = {};
  Map<int, List<Map<String, dynamic>>> _highlights = {};

  // Navigation management to prevent rapid successive navigation
  bool _isNavigating = false;

  // Stream subscriptions for real-time updates
  late StreamSubscription _highlightsSubscription;
  late StreamSubscription _notesSubscription;

  // ===== PageView Navigation System =====
  // Virtual index system for seamless chapter navigation across all books
  // Total chapters in KJV Bible: 1189 (Genesis 1 = index 0, Revelation 22 = index 1188)
  static const int _totalChapters = 1189;

  // PageController for chapter navigation with swipe animations
  late PageController _pageController;

  // Lookup tables for book/chapter ↔ virtual index mapping
  // Built once on initialization for O(1) lookups
  List<(String book, int chapter)>? _indexToLocation; // index → (book, chapter)
  Map<String, Map<int, int>>? _locationToIndex; // book → chapter → index

  // Cache for preloaded chapter data (verses, notes, highlights, metadata)
  // Key: real chapter index (0-1188), Value: chapter data
  final Map<int, _ChapterData> _chapterCache = {};

  // Track current page to detect direction changes (real index 0-1188)
  int _currentPageIndex = 0;

  // Keys to access ChapterContentWidget state for verse scrolling
  final Map<int, GlobalKey<ChapterContentWidgetState>> _chapterWidgetKeys = {};

  @override
  void initState() {
    super.initState();

    _loadInitialLocation();

    // this dual notifier stream system is required to support ui updates
    // whether the user is logged in or not

    // Listen to local data change notifier streams for immediate updates during local operations
    LocalDataChangeNotifier.highlightsChangedStream.listen((_) async {
      await _reloadCurrentChapterData();
      if (mounted) {
        setState(() {});
      }
    });

    // Listen to sync service streams for real-time updates
    _highlightsSubscription =
        SupabaseSyncService.highlightsChangedStream.listen((_) async {
      await _reloadCurrentChapterData();
      if (mounted) {
        setState(() {});
      }
    });

    // local
    LocalDataChangeNotifier.notesChangedStream.listen((_) async {
      await _reloadCurrentChapterData();
      if (mounted) setState(() {});
    });

    // remote
    _notesSubscription =
        SupabaseSyncService.notesChangedStream.listen((_) async {
      await _reloadCurrentChapterData();
      if (mounted) setState(() {});
    });
  }

  /// Reloads notes and highlights for the current chapter and updates cache
  Future<void> _reloadCurrentChapterData() async {
    if (_selectedBook == null || _selectedChapter == null) return;

    // Reload notes and highlights
    await _loadNotes();
    await _loadHighlights();

    // Update cache for current page
    if (_chapterCache.containsKey(_currentPageIndex)) {
      _chapterCache[_currentPageIndex] =
          _chapterCache[_currentPageIndex]!.copyWith(
        notes: Map.from(_notes),
        highlights: Map.from(_highlights),
      );
    }
  }

  /// Builds the virtual index lookup tables for O(1) book/chapter ↔ index conversion
  Future<void> _buildIndexLookupTables() async {
    if (_indexToLocation != null) return; // Already built

    _books = await BibleDatabase.getBooks();
    _indexToLocation = [];
    _locationToIndex = {};

    for (final book in _books) {
      final chapters = await BibleDatabase.getChapters(book);
      _locationToIndex![book] = {};
      for (final chapter in chapters) {
        final index = _indexToLocation!.length;
        _indexToLocation!.add((book, chapter));
        _locationToIndex![book]![chapter] = index;
      }
    }
  }

  /// Converts a chapter index (0-1188) to (book, chapter) tuple
  (String book, int chapter) _indexToBookChapter(int index) {
    if (_indexToLocation == null || _indexToLocation!.isEmpty) {
      return ('Gen', 1); // Fallback
    }
    // Clamp index to valid range
    final clampedIndex = index.clamp(0, _totalChapters - 1);
    return _indexToLocation![clampedIndex];
  }

  /// Converts (book, chapter) to index
  int _bookChapterToIndex(String book, int chapter) {
    if (_locationToIndex == null) return 0;
    return _locationToIndex![book]?[chapter] ?? 0;
  }

  Future<void> _loadInitialLocation() async {
    // Build lookup tables first
    await _buildIndexLookupTables();

    _selectedBook =
        (widget.initialBook != null && _books.contains(widget.initialBook))
            ? widget.initialBook
            : (_books.isNotEmpty ? _books.first : null);
    _chapters = _selectedBook != null
        ? await BibleDatabase.getChapters(_selectedBook!)
        : [];
    _selectedChapter = (widget.initialChapter != null &&
            _chapters.contains(widget.initialChapter))
        ? widget.initialChapter
        : (_chapters.isNotEmpty ? _chapters.first : null);

    // Calculate initial page index (0-1188)
    _currentPageIndex = _selectedBook != null && _selectedChapter != null
        ? _bookChapterToIndex(_selectedBook!, _selectedChapter!)
        : 0;

    // Initialize PageController at real index
    _pageController = PageController(initialPage: _currentPageIndex);

    await _loadVerses();
    _selectedVerse = (widget.initialVerse != null &&
            _verses.any((v) => v['verse'] == widget.initialVerse))
        ? widget.initialVerse
        : null;

    // Preload current chapter data into cache
    await _preloadChapterData(_currentPageIndex);

    setState(() {
      _loading = false;
    });

    // Scroll to initial verse after first build if specified
    if (_selectedVerse != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToVerseOnCurrentPage(_selectedVerse!);
      });
    }
  }

  /// Preloads chapter data for a given virtual index into the cache
  Future<_ChapterData> _preloadChapterData(int index) async {
    // Return cached data if available
    if (_chapterCache.containsKey(index)) {
      return _chapterCache[index]!;
    }

    final (book, chapter) = _indexToBookChapter(index);

    // Load verses
    final verses = await BibleDatabase.getVerses(book, chapter);
    // Sort verses
    if (verses.isNotEmpty) {
      final hasId = verses.first.containsKey('id');
      verses.sort((a, b) {
        final left = hasId ? toInt(a['id']) : toInt(a['verse']);
        final right = hasId ? toInt(b['id']) : toInt(b['verse']);
        return left.compareTo(right);
      });
    }

    // Load notes and highlights
    final notes = await loadNotesForChapter(book, chapter);
    final highlights = await loadHighlightsForChapter(book, chapter);

    // Load metadata
    String? title;
    String? colophon;
    if (book == 'Psa') {
      final metadata =
          await BibleDatabase.getBookMetadata(book, chapter: chapter);
      title = metadata?['title'] as String?;
      colophon = metadata?['colophon'] as String?;
    } else {
      final metadata = await BibleDatabase.getBookMetadata(book);
      title = metadata?['title'] as String?;
      colophon = metadata?['colophon'] as String?;
    }

    // Determine if this is the last chapter of the book
    final bookChapters = await BibleDatabase.getChapters(book);
    final isLastChapter =
        bookChapters.isNotEmpty && chapter == bookChapters.last;

    final chapterData = _ChapterData(
      book: book,
      chapter: chapter,
      verses: verses,
      notes: notes,
      highlights: highlights,
      bookTitle: title,
      bookColophon: colophon,
      isLastChapter: isLastChapter,
    );

    _chapterCache[index] = chapterData;

    // Limit cache size to prevent memory issues (keep ~5 chapters)
    if (_chapterCache.length > 5) {
      // Remove entries furthest from current page
      final keysToRemove = _chapterCache.keys
          .where((k) => (k - _currentPageIndex).abs() > 2)
          .toList();
      for (final key in keysToRemove) {
        _chapterCache.remove(key);
      }
    }

    return chapterData;
  }

  /// Scrolls to a specific verse on the currently visible page
  void _scrollToVerseOnCurrentPage(int verseNumber) {
    final key = _chapterWidgetKeys[_currentPageIndex];
    if (key?.currentState != null) {
      key!.currentState!.scrollToVerse(verseNumber);
    }
  }

  Future<void> _loadVerses() async {
    if (_selectedBook != null && _selectedChapter != null) {
      _verses =
          await BibleDatabase.getVerses(_selectedBook!, _selectedChapter!);
      // Enforce database order: first by `id` if present, otherwise by `verse`
      if (_verses.isNotEmpty) {
        final hasId = _verses.first.containsKey('id');
        _verses.sort((a, b) {
          final left = hasId ? toInt(a['id']) : toInt(a['verse']);
          final right = hasId ? toInt(b['id']) : toInt(b['verse']);
          return left.compareTo(right);
        });
      }
      await _loadNotes();
      await _loadHighlights();
    } else {
      _verses = [];
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
      _highlights =
          await loadHighlightsForChapter(_selectedBook!, _selectedChapter!);
    } else {
      _highlights.clear();
    }
  }

  Future<void> _recordHistory() async {
    if (_selectedBook != null && _selectedChapter != null) {
      HistoryDatabase.addHistory(_selectedBook!, _selectedChapter!,
          _selectedVerse ?? 1, DateTime.now().millisecondsSinceEpoch, false);
      // Note: Sync is handled automatically by the database operation
    }
  }

  /// Called when PageView page changes (via swipe or programmatic navigation)
  void _onPageChanged(int newPageIndex) {
    if (_isNavigating) return;

    // Update current page index (already in valid range 0-1188)
    _currentPageIndex = newPageIndex;

    // Get new location from real index
    final (book, chapter) = _indexToBookChapter(_currentPageIndex);

    // Update state
    _selectedBook = book;
    _selectedChapter = chapter;
    _selectedVerse = null; // Reset verse selection on page change

    // Update chapters list for the new book (used by some UI elements)
    BibleDatabase.getChapters(book).then((chapters) {
      _chapters = chapters;
    });

    // Notify parent of location change
    widget.onLocationChanged
        ?.call(_selectedBook, _selectedChapter, _selectedVerse);

    // Record history (swipe navigation doesn't record by default, but we do for consistency)
    // Note: We don't record history on every swipe to avoid cluttering history

    // Preload adjacent pages
    _preloadAdjacentPages();

    if (mounted) {
      setState(() {});
    }
  }

  /// Preloads chapter data for pages adjacent to the current page
  Future<void> _preloadAdjacentPages() async {
    // Preload previous page if not at start
    if (_currentPageIndex > 0) {
      _preloadChapterData(_currentPageIndex - 1);
    }

    // Preload next page if not at end
    if (_currentPageIndex < _totalChapters - 1) {
      _preloadChapterData(_currentPageIndex + 1);
    }
  }

  /// Navigate to previous chapter/page with animation
  void _navigateToPreviousPage() {
    if (!_pageController.hasClients) return;
    if (_currentPageIndex <= 0) return; // Already at first chapter

    _pageController.animateToPage(
      _currentPageIndex - 1,
      duration: Duration(milliseconds: 300),
      curve: Curves.fastEaseInToSlowEaseOut,
    );
  }

  /// Navigate to next chapter/page with animation
  void _navigateToNextPage() {
    if (!_pageController.hasClients) return;
    if (_currentPageIndex >= _totalChapters - 1) {
      return; // Already at last chapter
    }

    _pageController.animateToPage(
      _currentPageIndex + 1,
      duration: Duration(milliseconds: 300),
      //curve: Curves.easeOut,
      // curve: Curves.fastOutSlowIn,
      curve: Curves.fastEaseInToSlowEaseOut,
    );
  }

  @override
  void didUpdateWidget(covariant BibleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    // If navigation props changed, update state
    if (widget.initialBook != oldWidget.initialBook ||
        widget.initialChapter != oldWidget.initialChapter ||
        widget.initialVerse != oldWidget.initialVerse) {
      _navigateToLocation();
    }
  }

  Future<void> _navigateToLocation() async {
    // Enhanced protection against rapid successive navigation
    if (_isNavigating || !mounted || widget.initialBook == null) return;

    _isNavigating = true;

    try {
      // Ensure lookup tables are built
      await _buildIndexLookupTables();

      _selectedBook = widget.initialBook;
      _chapters = await BibleDatabase.getChapters(_selectedBook!);
      _selectedChapter = widget.initialChapter ??
          (_chapters.isNotEmpty ? _chapters.first : null);

      await _loadVerses();

      // When chapter 1 and verse 1 is chosen, set _selectedVerse to NULL so the book title is shown
      _selectedVerse = (widget.initialChapter == 1 && widget.initialVerse == 1)
          ? null
          : widget.initialVerse;

      // Calculate target page index and jump to it
      final targetIndex =
          _bookChapterToIndex(_selectedBook!, _selectedChapter!);
      _currentPageIndex = targetIndex;

      // Preload chapter data
      await _preloadChapterData(targetIndex);

      // Jump to page (no animation for external navigation)
      if (_pageController.hasClients) {
        _pageController.jumpToPage(targetIndex);
      }

      setState(() {});

      // Scroll to verse if specified
      if (_selectedVerse != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToVerseOnCurrentPage(_selectedVerse!);
        });
      }
    } finally {
      _isNavigating = false;
    }
  }

  // Add: transactional apply to avoid intermediate callbacks resetting chapter to 1
  Future<void> _applyLocation(String book, int chapter, int? verse,
      {bool notify = true}) async {
    // Enhanced protection against rapid successive navigation
    if (_isNavigating || !mounted) return;

    _isNavigating = true;

    setState(() {
      _loading = true;
    });

    try {
      // Ensure lookup tables are built
      await _buildIndexLookupTables();

      // Update book
      _selectedBook = book;

      // Load chapters for book and clamp chapter first
      _chapters = await BibleDatabase.getChapters(book);
      if (_chapters.isEmpty) {
        _selectedChapter = null;
        _verses = [];
      } else {
        if (!_chapters.contains(chapter)) {
          chapter = _chapters.first;
        }
        _selectedChapter = chapter;

        await _loadVerses();
      }

      // Set verse only if it exists in the loaded verses
      if (verse != null &&
          _verses.any((v) => toInt(v['verse'], orElse: -1) == verse)) {
        _selectedVerse = (chapter == 1 && verse == 1) ? null : verse;
      } else {
        _selectedVerse = null;
      }

      // Calculate target page index and navigate
      final targetIndex = _bookChapterToIndex(book, chapter);
      _currentPageIndex = targetIndex;

      // Preload chapter data
      await _preloadChapterData(targetIndex);

      // Jump to the page (no animation for dialog/external navigation)
      if (_pageController.hasClients) {
        _pageController.jumpToPage(targetIndex);
      }

      setState(() {
        _loading = false;
      });

      if (notify) {
        widget.onLocationChanged
            ?.call(_selectedBook, _selectedChapter, _selectedVerse);
        await _recordHistory();
      }

      // Scroll to verse if specified
      if (_selectedVerse != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToVerseOnCurrentPage(_selectedVerse!);
        });
      }
    } finally {
      _isNavigating = false;
    }
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
      final int? verse = result['verse'] as int?;
      // Apply atomically to prevent chapter being reset to 1 via intermediate callbacks
      await _applyLocation(book, chapter, verse);
    }
  }

  void _showAddNoteMenu(BuildContext context, int vn) {
    final verseData = _verses.firstWhere(
        (v) => toInt(v['verse'], orElse: -1) == vn,
        orElse: () => <String, Object>{});
    final verseText = verseData['text'] as String? ?? '';

    // Filter out red letter tags <r> and </r>, and pilcrow symbols
    final redLetterRegex = RegExp(r'</?r>');
    final cleanVerseText =
        verseText.replaceAll(redLetterRegex, '').replaceAll('¶ ', '');
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
                    style: TextStyle(
                        fontFamily: fontFamilyNotifier.value,
                        fontSize: uiFontSize + 10,
                        color: getAdaptiveTextColor(context)),
                  )),
                  onTap: () {
                    Navigator.of(context).pop();
                    _openNote(vn, _notes[vn]?['note_text']);
                  },
                ),
                if (_notes.containsKey(vn))
                  ListTile(
                    title: Center(
                        child: Text(
                      'Delete Note',
                      style: TextStyle(
                          fontFamily: fontFamilyNotifier.value,
                          fontSize: uiFontSize + 10,
                          color: Colors.red),
                    )),
                    onTap: () async {
                      Navigator.of(context).pop();
                      await _deleteNote(vn);
                    },
                  ),
                ListTile(
                  title: Center(
                      child: Text(
                    'Copy Verse $vn',
                    style: TextStyle(
                        fontFamily: fontFamilyNotifier.value,
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
                        fontFamily: fontFamilyNotifier.value,
                        fontSize: uiFontSize + 10,
                        color: getAdaptiveTextColor(context)),
                  )),
                  onTap: () {
                    Navigator.of(context).pop();
                    _openMultipleVersesDialog(vn);
                  },
                ),
              ],
            ));
  }

  Future<void> _openNote(int vn,
      [String? existingNote, String? book, int? chapter]) async {
    final noteBook = book ?? _selectedBook!;
    final noteChapter = chapter ?? _selectedChapter!;
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => NoteScreen(
                book: noteBook,
                chapter: noteChapter,
                verse: vn,
                existingNote: existingNote)));
    // Force focus to invisible button to prevent Windows OSK bug
    // if (kDebugMode) {
    //   debugPrint('>>> NoteScreen closed, calling onNoteScreenClosed callback');
    // }
    widget.onNoteScreenClosed?.call();
    await _loadNotes();
    // Note: sync operations are handled by database update methods, no need for additional marking
    if (mounted) setState(() {});
  }

  Future<void> _deleteNote(int vn) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 400),
        content: Text(
            'Are you sure you want to delete this note? This action cannot be undone.',
            style: TextStyle(
                fontSize: uiFontSize + 6,
                fontFamily: uiFontFamily,
                color: getAdaptiveTextColor(context))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context))),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: Colors.red)),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      final noteData = _notes[vn];
      if (noteData != null) {
        final noteId = noteData['id'];
        if (noteId != null) {
          await NotesDatabase.deleteNote(noteId);
          await _loadNotes();
          if (mounted) {
            setState(() {});
            showStyledSnackBar(context, 'Note deleted');
          }
        }
      }
    }
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
    final verseData = _verses.firstWhere(
        (v) => toInt(v['verse'], orElse: -1) == vn,
        orElse: () => <String, Object>{});
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

  void _showNotesSearch() {
    // Navigate to note search screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NoteSearchScreen(sourceScreenIndex: 0),
      ),
    ).then((result) {
      // Handle result from note search screen (verse navigation)
      if (result != null &&
          result is Map &&
          result.containsKey('verseLocation')) {
        final verseLocation = result['verseLocation'] as Map<String, dynamic>;
        final book = verseLocation['book'] as String;
        final chapter = verseLocation['chapter'] as int;
        final verse = verseLocation['verse'] as int;
        _applyLocation(book, chapter, verse);
      }
    });
  }

  // TODO: Implement bookmarks management functionality
  // void _showBookmarksManager() {
  //   if (context.mounted) {
  //     showStyledSnackBar(context, 'Bookmarks manager coming soon');
  //   }
  // }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final verseTextColor = isDark ? darkTextColor.value : lightTextColor.value;
    //final textColor = isDark ? darkTextColor.value : lightTextColor.value;
    final bibleBgColor =
        isDark ? darkBackgroundColor.value : lightBackgroundColor.value;
    //final biblePrimaryColor = isDark ? darkPrimaryColor.value : lightPrimaryColor.value;
    // Derived verse number color from primary color
    final verseNumberColor = isDark
        ? darkPrimaryColor.value
        : lightPrimaryColor
            .value; //_deriveVerseNumberColor(verseTextColor, background: bibleBgColor);
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
          //showViewMenu: widget.showViewMenu,
          onOpenDrawer: widget.onOpenDrawer,
          onShowHistory: widget.onShowHistory,
          onShowSearch: widget.onShowSearch,
          onTitlePressed: _openVerseChooser,
          selectedBook: _selectedBook,
          selectedChapter: _selectedChapter,
          onShowNotesSearch: widget.onShowNotesSearch ?? _showNotesSearch,
          //onShowBookmarksManager: widget.onShowBookmarksManager ?? _showBookmarksManager,
        ),
        Expanded(
          child: Container(
            color: bibleBgColor,
            child: _loading
                ? Center(child: CircularProgressIndicator())
                : ValueListenableBuilder<bool>(
                    valueListenable:
                        widget.showNotesInline ?? _localShowNotesInlineFallback,
                    builder: (context, showNotesInline, _) {
                      return ValueListenableBuilder<bool>(
                        valueListenable: showNavigationBarNotifier,
                        builder: (context, showNavBar, _) {
                          return Column(
                            //mainAxisSize: MainAxisSize.min,
                            children: [
                              Expanded(
                                // PageView for smooth chapter navigation with swipe gestures
                                // Using finite itemCount for simple wrap-around
                                child: PageView.builder(
                                  controller: _pageController,
                                  onPageChanged: _onPageChanged,
                                  itemCount: _totalChapters,
                                  itemBuilder: (context, index) {
                                    // index is already in valid range (0-1188)
                                    final realIndex = index;

                                    // Get or create a GlobalKey for this page's ChapterContentWidget
                                    // Use realIndex for the key to reuse widgets for same chapter
                                    _chapterWidgetKeys[realIndex] ??=
                                        GlobalKey<ChapterContentWidgetState>();

                                    // Build the chapter content widget
                                    return FutureBuilder<_ChapterData>(
                                      future: _preloadChapterData(realIndex),
                                      builder: (context, snapshot) {
                                        if (snapshot.connectionState ==
                                                ConnectionState.waiting &&
                                            !_chapterCache
                                                .containsKey(realIndex)) {
                                          return Center(
                                              child:
                                                  CircularProgressIndicator());
                                        }

                                        final chapterData = snapshot.data ??
                                            _chapterCache[realIndex];
                                        if (chapterData == null) {
                                          return Center(
                                              child:
                                                  CircularProgressIndicator());
                                        }

                                        return ChapterContentWidget(
                                          key: _chapterWidgetKeys[realIndex],
                                          book: chapterData.book,
                                          chapter: chapterData.chapter,
                                          verses: chapterData.verses,
                                          notes: chapterData.notes,
                                          highlights: chapterData.highlights,
                                          bookTitle: chapterData.bookTitle,
                                          bookColophon:
                                              chapterData.bookColophon,
                                          isLastChapter:
                                              chapterData.isLastChapter,
                                          showNotesInline: showNotesInline,
                                          backgroundColor: bibleBgColor,
                                          textColor: verseTextColor,
                                          verseNumberColor: verseNumberColor,
                                          onVerseTap: (verseNum) {
                                            // Update current state for menu operations
                                            _verses = chapterData.verses;
                                            _notes = chapterData.notes;
                                            _showAddNoteMenu(context, verseNum);
                                          },
                                          onVerseLongPress: (verseNum) {
                                            _verses = chapterData.verses;
                                            _enterHighlightMode(
                                                context, verseNum);
                                          },
                                          onLinkTap: (link, referenceText) =>
                                              handleVerseLink(
                                            context,
                                            link,
                                            referenceText,
                                            navigateToVerse: _applyLocation,
                                            onVerseLinkRecursion: null,
                                            onNoteIconTap: (book, chapter,
                                                    verse, noteText) =>
                                                _openNote(verse, noteText, book,
                                                    chapter),
                                            onNoteEditTap: (book, chapter,
                                                    verse, noteText) =>
                                                _openNote(verse, noteText, book,
                                                    chapter),
                                          ),
                                          onNoteIconTap: (vn, noteText) =>
                                              _openNote(vn, noteText),
                                          onNoteEditTap: (vn, noteText) =>
                                              _openNote(vn, noteText),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                              if (showNavBar)
                                Container(
                                  margin: EdgeInsetsGeometry.all(0),
                                  padding: EdgeInsetsGeometry.all(0),
                                  width: double.infinity,
                                  height: 40,
                                  color: barColor,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Center(
                                          child: IconButton(
                                            icon: Icon(
                                              Icons.arrow_back_ios_new,
                                              color: _currentPageIndex > 0
                                                  ? (isDark
                                                      ? darkPrimaryColor.value
                                                      : lightPrimaryColor.value)
                                                  : Colors.grey,
                                              semanticLabel:
                                                  'Navigate to the Previous Chapter',
                                              size: 24.0,
                                            ),
                                            tooltip: 'Previous Chapter',
                                            color: isDark
                                                ? darkPrimaryColor.value
                                                : lightPrimaryColor.value,
                                            // Disabled at Genesis 1
                                            onPressed: _currentPageIndex > 0
                                                ? _navigateToPreviousPage
                                                : null,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Center(
                                          child: IconButton(
                                            icon: Icon(
                                              Icons.arrow_forward_ios,
                                              color: _currentPageIndex <
                                                      _totalChapters - 1
                                                  ? (isDark
                                                      ? darkPrimaryColor.value
                                                      : lightPrimaryColor.value)
                                                  : Colors.grey,
                                              semanticLabel:
                                                  'Navigate to the next chapter',
                                              size: 24.0,
                                            ),
                                            tooltip: 'Next Chapter',
                                            color: isDark
                                                ? darkPrimaryColor.value
                                                : lightPrimaryColor.value,
                                            // Disabled at Revelation 22
                                            onPressed: _currentPageIndex <
                                                    _totalChapters - 1
                                                ? _navigateToNextPage
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
    );
  }

  @override
  void dispose() {
    // Cancel stream subscriptions
    _highlightsSubscription.cancel();
    _notesSubscription.cancel();

    // Dispose controllers to prevent memory leaks
    _pageController.dispose();
    _localShowNotesInlineFallback.dispose();

    super.dispose();
  }
}
