import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../database/strongs_database.dart';
import '../database/history_database.dart';
import '../utils/error_handler.dart';
import '../main.dart';
import '../services/strongs_search_worker.dart';
import '../utils/font_size_adjustments.dart';
import '../utils/preferences_constants.dart';
import '../utils/snackbar_notification.dart';
import '../utils/book_name_converter.dart';
import '../utils/bible_utils.dart';
import '../utils/verse_reference_detector.dart';
import '../utils/verse_text_parser.dart';
import '../screens/chapter_dialog.dart';
import '../screens/note_screen.dart';
import '../widgets/responsive_text.dart';
import '../widgets/strongs_definition_dialog.dart';
import '../widgets/strongs_definition_lookup_dialog.dart';

// Helper function to create a slightly different shade for bars
Color _adjustBarColor(Color backgroundColor) {
  final hsl = HSLColor.fromColor(backgroundColor);
  final adjustedLightness = hsl.lightness > 0.5
      ? (hsl.lightness - 0.03).clamp(0.0, 1.0)
      : (hsl.lightness + 0.03).clamp(0.0, 1.0);
  return hsl.withLightness(adjustedLightness).toColor();
}

class StrongsSearchScreen extends StatefulWidget {
  final int? sourceScreenIndex;

  const StrongsSearchScreen({
    super.key,
    this.sourceScreenIndex,
  });

  @override
  State<StrongsSearchScreen> createState() => _StrongsSearchScreenState();
}

class _StrongsSearchScreenState extends State<StrongsSearchScreen>
    with AutomaticKeepAliveClientMixin {
  static const double _phraseSummaryColumnHorizontalPadding = 16.0;
  static const double _phraseSummaryWidthBuffer = 4.0;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _controller = TextEditingController();
  final FocusNode _searchButtonFocusNode = FocusNode();
  final ScrollController _resultsScrollController = ScrollController();
  final List<TapGestureRecognizer> _verseReferenceRecognizers = [];

  bool _isResetting = false;
  bool _isRestoring = false;
  int _verseReferenceRecognizerIndex = 0;
  int? _verseReferenceRecognizerCleanupExpectedCount;

  List<Map<String, dynamic>> _searchResults = [];
  Map<String, Map<String, dynamic>> _foundStrongsNumbers = {};
  Map<String, int> _phraseSummary = {};
  int? _totalMatches;
  int? _totalVerses;
  String? _searchType;
  //String? _searchTerm;
  bool _isSearching = false;
  Timer? _scrollOffsetSaveTimer;
  int _activeSearchId = 0;

  static const String _lastSearchTermKey = 'lastStrongsSearchTerm';
  static const String _scrollOffsetKey = 'strongsSearchScrollOffset';

  @override
  bool get wantKeepAlive => true;

  /// Attempts to parse a reference search (e.g., "Gen 2:15 garden")
  /// Returns a ReferenceSearchTaskData if valid, null otherwise
  ReferenceSearchTaskData? _parseReferenceSearch(String input) {
    // Pattern: Book Chapter:Verse Word
    // Examples: Gen 2:15 garden, Mat 5:7 merciful
    final pattern = RegExp(r'^([A-Za-z0-9]+)\s+(\d+):(\d+)\s+(\w+)$');
    final match = pattern.firstMatch(input.trim());
    if (match == null) return null;

    final bookInput = match.group(1)!;
    final chapterStr = match.group(2)!;
    final verseStr = match.group(3)!;
    final word = match.group(4)!;

    // Normalize the book name to support case-insensitive and both short/long names
    final normalizedBook = BookNameConverter.normalizeBookName(bookInput);

    final chapter = int.tryParse(chapterStr);
    final verse = int.tryParse(verseStr);

    if (chapter == null || verse == null) return null;

    return ReferenceSearchTaskData(
      book: normalizedBook,
      chapter: chapter,
      verse: verse,
      word: word,
    );
  }

  void _showHelpDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? darkBackgroundColor.value : lightBackgroundColor.value;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        // insetPadding: EdgeInsets.all(0.0),
        // contentPadding: EdgeInsets.all(16.0),
        // actionsPadding: EdgeInsets.all(0.0),
        // titlePadding: EdgeInsets.all(0.0),
        backgroundColor: bgColor,
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Text(
              //   'Strong\'s Search',
              //   style: TextStyle(
              //       fontWeight: FontWeight.bold,
              //       fontSize: uiFontSize,
              //       fontFamily: uiFontFamily,
              //       color: getAdaptiveTextColor(context)),
              // ),
              // const SizedBox(height: 8),
              Text('You can search three ways:\n',
                  style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context))),
              Text(
                  '1. Word search - Enter a single word (e.g. "covenant") to find all Strong\'s numbers associated with that word and all verses containing them.',
                  style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context))),
              const SizedBox(height: 8),
              Text(
                  '    Note: Word search only supports single words. Additional words after the first will be ignored.',
                  style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      fontStyle: FontStyle.italic,
                      color: getAdaptiveTextColor(context))),
              const SizedBox(height: 8),
              Text(
                  '2. Strong\'s number search - Enter a Strong\'s number (e.g. H1285 or G1242) to find all verses containing that specific Strong\'s number.',
                  style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context))),
              const SizedBox(height: 8),
              Text(
                  '3. Reference search - Enter a verse reference with a word (e.g. "Gen 2:15 garden") to find the Strong\'s number(s) for that specific word and then show all the verses where that Strong\'s number appears.',
                  style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context))),
              const SizedBox(height: 8),
              Text(
                  '    When appropriate, a phrase summary will be generated from every verse where the Strong\'s number(s) appear. The second column represents the number of times that phrase appears in the verse results.',
                  style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      fontStyle: FontStyle.italic,
                      color: getAdaptiveTextColor(context))),
              const SizedBox(height: 8),
              Text(
                  '4. Definitions lookup - Tap the book icon in the toolbar to look up a Strong\'s number definition without running a search.',
                  style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context))),
            ],
          ),
        ),
        actions: [
          TextButton(
              child: Text('Close',
                  style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context))),
              onPressed: () => Navigator.pop(context))
        ],
      ),
    );
  }

  void _onSearch({bool showLoading = true, bool resetScroll = true}) {
    if (kDebugMode) {
      debugPrint('[_onSearch] Called with input="${_controller.text.trim()}"');
    }
    final input = _controller.text.trim();
    final searchId = ++_activeSearchId;
    if (input.isEmpty) {
      setState(() {
        _searchResults = [];
        _foundStrongsNumbers = {};
        _phraseSummary = {};
        _totalMatches = 0;
        _totalVerses = 0;
        _searchType = null;
        //_searchTerm = null;
        _isSearching = false;
      });
      _persistSearchState('');
      return;
    }

    setState(() {
      _searchResults = [];
      _foundStrongsNumbers = {};
      _phraseSummary = {};
      _totalMatches = null;
      _totalVerses = null;
      //_searchTerm = input;
      _isSearching = showLoading;
    });

    _persistSearchState(input);

    if (resetScroll && _resultsScrollController.hasClients) {
      _resultsScrollController.jumpTo(0.0);
    }

    // Try to parse as reference search first (e.g., "Gen 2:15 garden")
    final referenceSearch = _parseReferenceSearch(input);
    if (referenceSearch != null) {
      if (kDebugMode) {
        debugPrint('[_onSearch] Parsed as REFERENCE search');
      }
      _startSearchTask(
        searchId: searchId,
        showLoading: showLoading,
        task: () => _performReferenceSearch(referenceSearch, searchId),
      );
      return;
    }

    // Try to parse as Strong's number (e.g., "H1234")
    final words =
        input.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    String searchTerm = words[0];

    if (words.length > 1) {
      showStyledSnackBar(context,
          'Strong\'s search only supports single words. Extra words were ignored.');
    }

    final strongsNumber = StrongsDatabase.validateStrongsNumber(searchTerm);

    if (kDebugMode) {
      if (strongsNumber != null) {
        debugPrint(
            '[_onSearch] Parsed as STRONGS NUMBER search: "$strongsNumber"');
      } else {
        debugPrint('[_onSearch] Parsed as WORD search: "$searchTerm"');
      }
    }

    _startSearchTask(
      searchId: searchId,
      showLoading: showLoading,
      task: () {
        if (strongsNumber != null) {
          return _performStrongsNumberSearch(strongsNumber, searchId);
        } else {
          return _performWordSearch(searchTerm, searchId);
        }
      },
    );
  }

  void _startSearchTask({
    required int searchId,
    required bool showLoading,
    required Future<void> Function() task,
  }) {
    Future<void> runTask() async {
      if (!mounted || searchId != _activeSearchId) return;
      if (showLoading) {
        await _waitForNextFrame();
      }
      if (!mounted || searchId != _activeSearchId) return;
      await task();
    }

    unawaited(runTask());
  }

  Future<void> _performStrongsNumberSearch(
      String strongsNumber, int searchId) async {
    if (kDebugMode) {
      debugPrint(
          '[_performStrongsNumberSearch] START: strongsNumber="$strongsNumber"');
    }
    _unfocusSearchField(); // Don't wait or it flashes for a split second
    try {
      final searchResult = runStrongsNumberSearch(strongsNumber);
      if (!mounted) return;
      if (_isResetting) return;
      if (searchId != _activeSearchId) return;
      final results = searchResult.searchResults;
      final phraseSummary = searchResult.phraseSummary;
      if (kDebugMode) {
        debugPrint(
            '[_performStrongsNumberSearch] Got ${results.length} results and ${phraseSummary.length} phrases');
      }

      if (results.isEmpty) {
        setState(() {
          _searchResults = [];
          _foundStrongsNumbers = {};
          _phraseSummary = {};
          _totalMatches = 0;
          _totalVerses = 0;
          _searchType = 'strongs';
          _isRestoring = false;
          _isSearching = false;
        });
        return;
      }

      int totalMatches = 0;
      for (final count in phraseSummary.values) {
        totalMatches += count;
      }

      setState(() {
        _searchResults = results;
        _foundStrongsNumbers = {};
        _phraseSummary = phraseSummary;
        _totalMatches = totalMatches;
        _totalVerses = results.length;
        _searchType = 'strongs';
        _isRestoring = false;
        _isSearching = false;
      });
    } catch (e) {
      if (mounted) {
        if (!_isResetting) {
          if (searchId != _activeSearchId) return;
          setState(() {
            _isRestoring = false;
            _isSearching = false;
          });
          showStyledSnackBar(context, 'Search failed: ${e.toString()}');
        }
      }
    }
  }

  Future<void> _performWordSearch(String word, int searchId) async {
    if (kDebugMode) {
      debugPrint('[_performWordSearch] ===== START: word="$word" =====');
    }
    _unfocusSearchField(); // Don't wait or it flashes for a split second
    try {
      final wordSearchResult = runWordSearch(word);
      if (kDebugMode) {
        debugPrint(
            '[_performWordSearch] Word search done: ${wordSearchResult.wordVerseCount} word verses, ${wordSearchResult.foundStrongsNumbers.length} Strong\'s numbers, ${wordSearchResult.searchResults.length} result verses');
      }
      if (!mounted) return;
      if (_isResetting) return;
      if (searchId != _activeSearchId) return;

      final foundStrongs = wordSearchResult.foundStrongsNumbers;
      final results = wordSearchResult.searchResults;
      final phraseSummary = wordSearchResult.phraseSummary;

      if (wordSearchResult.wordVerseCount == 0 || foundStrongs.isEmpty) {
        setState(() {
          _searchResults = [];
          _foundStrongsNumbers = {};
          _phraseSummary = {};
          _totalMatches = 0;
          _totalVerses = 0;
          _searchType = 'word';
          _isRestoring = false;
          _isSearching = false;
        });
        return;
      }

      if (results.isEmpty) {
        setState(() {
          _searchResults = [];
          _foundStrongsNumbers = foundStrongs;
          _phraseSummary = {};
          _totalMatches = 0;
          _totalVerses = 0;
          _searchType = 'word';
          _isRestoring = false;
          _isSearching = false;
        });
        return;
      }

      int totalMatches = 0;
      for (final count in phraseSummary.values) {
        totalMatches += count;
      }

      setState(() {
        _searchResults = results;
        _foundStrongsNumbers = foundStrongs;
        _phraseSummary = phraseSummary;
        _totalMatches = totalMatches;
        _totalVerses = results.length;
        _searchType = 'word';
        _isRestoring = false;
        _isSearching = false;
      });
      if (kDebugMode) {
        debugPrint(
            '[_performWordSearch] ===== COMPLETE ($_totalMatches matches in $_totalVerses verses) =====');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[_performWordSearch] ERROR: $e');
      }
      if (mounted) {
        if (!_isResetting) {
          if (searchId != _activeSearchId) return;
          setState(() {
            _isRestoring = false;
            _isSearching = false;
          });
          showStyledSnackBar(context, 'Search failed: ${e.toString()}');
        }
      }
    }
  }

  Future<void> _performReferenceSearch(
      ReferenceSearchTaskData refSearch, int searchId) async {
    if (kDebugMode) {
      debugPrint(
          '[_performReferenceSearch] START: "${refSearch.book} ${refSearch.chapter}:${refSearch.verse} ${refSearch.word}"');
    }
    _unfocusSearchField();
    try {
      final result = runReferenceSearch(refSearch);
      if (kDebugMode) {
        debugPrint(
            '[_performReferenceSearch] Reference search done: error=${result.error}, strongsNumbers=${result.strongsNumbers}');
      }
      if (!mounted) return;
      if (_isResetting) return;
      if (searchId != _activeSearchId) return;

      // Check for errors
      if (result.error != null) {
        showStyledSnackBar(context, result.error!);
        setState(() {
          _searchResults = [];
          _foundStrongsNumbers = {};
          _phraseSummary = {};
          _totalMatches = 0;
          _totalVerses = 0;
          _searchType = 'reference';
          _isRestoring = false;
          _isSearching = false;
        });
        return;
      }

      final results = result.searchResults;
      final phraseSummary = result.phraseSummary;

      if (results.isEmpty) {
        setState(() {
          _searchResults = [];
          _foundStrongsNumbers = {};
          _phraseSummary = {};
          _totalMatches = 0;
          _totalVerses = 0;
          _searchType = 'reference';
          _isRestoring = false;
          _isSearching = false;
        });
        return;
      }

      int totalMatches = 0;
      for (final count in phraseSummary.values) {
        totalMatches += count;
      }

      setState(() {
        _searchResults = results;
        _foundStrongsNumbers = result.foundStrongsNumbers;
        _phraseSummary = phraseSummary;
        _totalMatches = totalMatches;
        _totalVerses = results.length;
        _searchType = 'reference';
        _isRestoring = false;
        _isSearching = false;
      });
      if (kDebugMode) {
        debugPrint(
            '[_performReferenceSearch] DONE ($_totalMatches matches in $_totalVerses verses)');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[_performReferenceSearch] ERROR: $e');
      }
      if (mounted) {
        if (!_isResetting) {
          if (searchId != _activeSearchId) return;
          setState(() {
            _isRestoring = false;
            _isSearching = false;
          });
          showStyledSnackBar(context, 'Search failed: ${e.toString()}');
        }
      }
    }
  }

  Color _getHighlightColor(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark
        ? darkHighlightColor.value
        : lightHighlightColor.value;
  }

  void _showStrongsDefinitionDialog(
      BuildContext context, String strongsNumber) {
    StrongsDefinitionDialog.show(context, strongsNumber);
  }

  void _showStrongsDefinitionLookupDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => const StrongsDefinitionLookupDialog(),
    );
  }

  TextSpan _buildVerseSpan(
      BuildContext context, Map<String, dynamic> verseData, double fontSize) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseStyle = TextStyle(
      fontSize: FontSizeAdjustments.getAdjustedSize(
          fontFamilyNotifier.value, fontSize),
      color: isDark ? darkTextColor.value : lightTextColor.value,
    );
    final highlightColor = _getHighlightColor(context);

    final text = verseData['text'] as String;
    final matchedStrongs =
        (verseData['matchedStrongs'] as List<dynamic>?)?.cast<String>() ?? [];

    return VerseTextParser.parseMatchedStrongsVerseText(
      text: text,
      baseStyle: baseStyle,
      matchedStrongs: matchedStrongs.toSet(),
      highlightColor: highlightColor,
      strongsColor: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
      onStrongsTap: (strongsNumber) =>
          _showStrongsDefinitionDialog(context, strongsNumber),
    );
  }

  String _formatNumber(int? number) {
    return number.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+($|\D))'),
        (match) => '${match.group(1)},');
  }

  InlineSpan _buildVerseReferenceSpan(
      BuildContext context, String refText, TextStyle refStyle) {
    final reference = VerseReferenceDetector.detectQuickJumpReference(refText);
    if (reference?.verse == null) {
      return TextSpan(
        text: refText,
        style: refStyle,
      );
    }

    final recognizer = _getVerseReferenceRecognizer(context, reference!);
    return TextSpan(
      text: refText,
      style: refStyle.copyWith(
        color: Theme.of(context).brightness == Brightness.dark
            ? darkVerseReferenceColor.value
            : lightVerseReferenceColor.value,
        decoration: TextDecoration.none,
      ),
      mouseCursor: SystemMouseCursors.click,
      recognizer: recognizer,
    );
  }

  TapGestureRecognizer _getVerseReferenceRecognizer(
      BuildContext context, VerseReference reference) {
    TapGestureRecognizer recognizer;
    if (_verseReferenceRecognizerIndex < _verseReferenceRecognizers.length) {
      recognizer = _verseReferenceRecognizers[_verseReferenceRecognizerIndex];
    } else {
      recognizer = TapGestureRecognizer();
      _verseReferenceRecognizers.add(recognizer);
    }

    recognizer.onTap = () => _openValidatedStrongReference(
          context,
          reference.book,
          reference.chapter,
          reference.verse!,
        );
    _verseReferenceRecognizerIndex++;
    return recognizer;
  }

  void _openValidatedStrongReference(
      BuildContext context, String book, int chapter, int verse) {
    // Book name is already in short format so no need to convert
    final referenceText = '$book $chapter:$verse';
    handleVerseLink(
      context,
      'v://$book/$chapter/$verse',
      referenceText,
      navigateToVerse: null,
      onVerseLinkRecursion: null,
      onNoteIconTap: null,
      onNoteEditTap: null,
    );
  }

  void _showStrongsVerseActionMenu(
      BuildContext context, Map<String, dynamic> result) {
    final book = result['book'] as String?;
    final chapter = result['chapter'] as int?;
    final verseNum = result['verse'] as int?;
    final isSuperscription = result['isSuperscription'] == true;
    final rawVerseText = result['text'] as String? ?? '';
    final cleanVerseText = VerseTextParser.toPlainVerseText(rawVerseText);
    final bookName =
        book == null ? '' : BookNameConverter.shortNameToLongName(book);
    final referenceText = isSuperscription
        ? 'Psalm $chapter Superscription'
        : '$bookName $chapter:$verseNum';
    final copyText = '$referenceText\n$cleanVerseText';

    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isSuperscription)
            ListTile(
              title: Center(
                  child: Text(
                'Goto Verse',
                style: TextStyle(
                    fontFamily: fontFamilyNotifier.value,
                    fontSize: uiFontSize + 8,
                    color: getAdaptiveTextColor(context)),
              )),
              onTap: () {
                Navigator.of(context).pop();
                _gotoVerse(book, chapter, verseNum);
              },
            ),
          if (!isSuperscription)
            ListTile(
              title: Center(
                  child: Text(
                'Show Context',
                style: TextStyle(
                    fontFamily: fontFamilyNotifier.value,
                    fontSize: uiFontSize + 8,
                    color: getAdaptiveTextColor(context)),
              )),
              onTap: () {
                Navigator.of(context).pop();
                _showContextDialog(book, chapter, verseNum);
              },
            ),
          ListTile(
            title: Center(
                child: Text(
              isSuperscription ? 'Copy Superscription' : 'Copy Verse $verseNum',
              style: TextStyle(
                  fontFamily: fontFamilyNotifier.value,
                  fontSize: uiFontSize + 8,
                  color: getAdaptiveTextColor(context)),
            )),
            onTap: () {
              Clipboard.setData(ClipboardData(text: copyText)).then((_) {
                if (!context.mounted) return;
                showStyledSnackBar(
                    context,
                    isSuperscription
                        ? 'Superscription copied to clipboard'
                        : 'Verse copied to clipboard');
                Navigator.of(context).pop();
              });
            },
          ),
        ],
      ),
    );
  }

  Future<void> _gotoVerse(String? book, int? chapter, int? verse) async {
    if (book == null || chapter == null || verse == null) {
      ErrorHandler.logError(
        '_gotoVerse null return: book:"$book" chapter:"$chapter" verse:"$verse"',
        context: {
          'class': 'StrongsSearchScreen',
          'method': '_gotoVerse',
          'book': book,
          'chapter': chapter,
          'verse': verse
        },
      );
      return;
    }

    final result = {
      'verseLocation': {
        'book': book,
        'chapter': chapter,
        'verse': verse,
      },
      'targetScreenIndex': widget.sourceScreenIndex ?? 0,
    };

    if (mounted) {
      Navigator.of(context).pop(result);
    }

    try {
      await HistoryDatabase.addHistory(
          book, chapter, verse, DateTime.now().millisecondsSinceEpoch, false);
    } catch (e) {
      ErrorHandler.logError(
        e,
        customMessage: '_gotoVerse addHistory exception',
        context: {
          'class': 'StrongsSearchScreen',
          'method': '_gotoVerse',
          'book': book,
          'chapter': chapter,
          'verse': verse
        },
      );
    }
  }

  Future<void> _showContextDialog(
      String? book, int? chapter, int? verseNum) async {
    if (book == null || chapter == null || verseNum == null) return;

    final normalizedShortBookName = BookNameConverter.normalizeShortName(book);
    final fullBookName =
        BookNameConverter.shortNameToLongName(normalizedShortBookName);
    final referenceText = '$fullBookName $chapter:$verseNum';

    showDialog(
      context: context,
      builder: (context) => ChapterDialog(
        book: normalizedShortBookName,
        chapter: chapter,
        verse: verseNum,
        referenceText: referenceText,
        onNavigateToVerse: (verse) =>
            _gotoVerse(normalizedShortBookName, chapter, verse),
        onNoteIconTap: (int verse, String? noteText) => _openNoteFromContext(
            normalizedShortBookName, chapter, verse, noteText),
        onNoteEditTap: (int verse, String? noteText) => _openNoteFromContext(
            normalizedShortBookName, chapter, verse, noteText),
        onVerseLink: (link, referenceText) => handleVerseLink(
          context,
          link,
          referenceText,
          navigateToVerse: _gotoVerse,
          onVerseLinkRecursion: null,
          onNoteIconTap: _openNoteFromContext,
          onNoteEditTap: _openNoteFromContext,
        ),
      ),
    );
  }

  Future<void> _openNoteFromContext(
      String book, int chapter, int verse, String? existingNote) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => NoteScreen(
                book: book,
                chapter: chapter,
                verse: verse,
                existingNote: existingNote)));
  }

  void _unfocusSearchField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searchButtonFocusNode.canRequestFocus) {
        _searchButtonFocusNode.requestFocus();
      }
    });
  }

  void _resetVerseReferenceRecognizers() {
    _verseReferenceRecognizerIndex = 0;
  }

  void _scheduleVerseReferenceRecognizerCleanup(int expectedCount) {
    _verseReferenceRecognizerCleanupExpectedCount = expectedCount;
    if (expectedCount >= _verseReferenceRecognizers.length) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_verseReferenceRecognizerCleanupExpectedCount != expectedCount) {
        return;
      }

      for (int i = expectedCount; i < _verseReferenceRecognizers.length; i++) {
        final recognizer = _verseReferenceRecognizers[i];
        recognizer.onTap = null;
        recognizer.dispose();
      }
      _verseReferenceRecognizers.removeRange(
          expectedCount, _verseReferenceRecognizers.length);
      _verseReferenceRecognizerCleanupExpectedCount = null;
    });
  }

  void _disposeVerseReferenceRecognizers() {
    for (final recognizer in _verseReferenceRecognizers) {
      recognizer.onTap = null;
      recognizer.dispose();
    }
    _verseReferenceRecognizers.clear();
    _verseReferenceRecognizerCleanupExpectedCount = null;
  }

  @override
  void initState() {
    super.initState();
    _resultsScrollController.addListener(_scheduleScrollOffsetSave);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_restoreSearchState());
    });
  }

  @override
  void dispose() {
    _disposeVerseReferenceRecognizers();
    _searchButtonFocusNode.dispose();
    _persistSearchState(_controller.text.trim());
    _scrollOffsetSaveTimer?.cancel();
    if (_resultsScrollController.hasClients) {
      unawaited(_saveScrollOffset(_resultsScrollController.offset));
    }
    _resultsScrollController.removeListener(_scheduleScrollOffsetSave);
    _controller.dispose();
    _resultsScrollController.dispose();
    super.dispose();
  }

  Future<void> _restoreSearchState() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSearch = prefs.getString(_lastSearchTermKey);
    if (!mounted) return;

    if (lastSearch == null || lastSearch.trim().isEmpty) {
      await prefs.setDouble(_scrollOffsetKey, 0.0);
      setState(() {
        _controller.text = '';
        _searchResults = [];
        _foundStrongsNumbers = {};
        _phraseSummary = {};
        _totalMatches = null;
        _totalVerses = null;
        _searchType = null;
        //_searchTerm = null;
        _isSearching = false;
      });
      return;
    }

    await _waitForRouteTransition();
    if (!mounted) return;
    setState(() {
      _controller.text = lastSearch;
      _isRestoring = true;
      _isSearching = false;
    });
    await _waitForFrames(2);
    if (!mounted) return;
    _onSearch(showLoading: false, resetScroll: false);
    await _loadScrollOffset();
  }

  Future<void> _waitForNextFrame() async {
    await _waitForFrames(1);
  }

  Future<void> _waitForFrames(int frameCount) async {
    for (int i = 0; i < frameCount; i++) {
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> _waitForRouteTransition() async {
    final route = ModalRoute.of(context);
    if (route == null) {
      await _waitForFrames(2);
      return;
    }

    final animation = route.animation;
    if (animation == null ||
        animation.status == AnimationStatus.completed ||
        animation.status == AnimationStatus.dismissed) {
      await _waitForFrames(2);
      return;
    }

    final completer = Completer<void>();
    late AnimationStatusListener listener;
    listener = (status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    };

    animation.addStatusListener(listener);
    try {
      if (animation.status != AnimationStatus.completed &&
          animation.status != AnimationStatus.dismissed) {
        final timeout =
            route.transitionDuration + const Duration(milliseconds: 100);
        await completer.future.timeout(timeout, onTimeout: () {});
      }
    } finally {
      animation.removeStatusListener(listener);
    }

    if (mounted) {
      await _waitForFrames(2);
    }
  }

  Future<void> _persistSearchState(String searchTerm) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSearchTermKey, searchTerm);
  }

  Future<void> _loadScrollOffset() async {
    final prefs = await SharedPreferences.getInstance();
    final offset = prefs.getDouble(_scrollOffsetKey) ?? 0.0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_resultsScrollController.hasClients && offset >= 0.0) {
        _resultsScrollController.jumpTo(offset);
      }
    });
  }

  void _scheduleScrollOffsetSave() {
    if (!_resultsScrollController.hasClients) return;
    final offset = _resultsScrollController.offset;
    _scrollOffsetSaveTimer?.cancel();
    _scrollOffsetSaveTimer = Timer(const Duration(milliseconds: 400), () {
      _scrollOffsetSaveTimer = null;
      unawaited(_saveScrollOffset(offset));
    });
  }

  Future<void> _saveScrollOffset(double offset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_scrollOffsetKey, offset);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showStrongNumbersTable =
        (_searchType == 'word' || _searchType == 'reference') &&
            _foundStrongsNumbers.isNotEmpty;
    if (!showStrongNumbersTable) {
      _resetVerseReferenceRecognizers();
      _scheduleVerseReferenceRecognizerCleanup(0);
    }
    final barColor = _adjustBarColor(
        Theme.of(context).brightness == Brightness.dark
            ? darkBackgroundColor.value
            : lightBackgroundColor.value);
    return Scaffold(
      resizeToAvoidBottomInset: false,
      key: _scaffoldKey,
      appBar: AppBar(
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(
          size: 32,
          color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
        ),
        elevation: 0,
        title: (_totalMatches != null && _totalVerses != null)
            ? Center(
                child: ResponsiveText(
                text:
                    '${_formatNumber(_totalMatches)} ${_totalMatches == 1 ? 'match' : 'matches'} in ${_formatNumber(_totalVerses)} ${_totalVerses == 1 ? 'verse' : 'verses'}',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context)),
                minFontSize: uiFontSize - 14,
              ))
            : Text('Strong\'s Search',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context))),
        toolbarHeight: 60,
        backgroundColor: barColor,
        actions: [
          IconButton(
            icon: Icon(
              Icons.menu_book,
              size: 32,
              color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
              semanticLabel: 'Show Definitions Lookup',
            ),
            tooltip: 'Strong\'s Definitions',
            color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
            onPressed: () => _showStrongsDefinitionLookupDialog(context),
          ),
          IconButton(
            icon: Icon(
              Icons.help_outline,
              size: 32,
              color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
              semanticLabel: 'Show Help Dialog',
            ),
            tooltip: 'Help',
            color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
            onPressed: _showHelpDialog,
          ),
        ],
      ),
      endDrawer: Drawer(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? darkBackgroundColor.value
            : lightBackgroundColor.value,
        child: SingleChildScrollView(
            child: Column(children: [
          AppBar(
            scrolledUnderElevation: 0,
            iconTheme: IconThemeData(
              size: 32,
              color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
            ),
            automaticallyImplyLeading: true,
            toolbarHeight: 60,
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? darkBackgroundColor.value
                : lightBackgroundColor.value,
          ),
          const SizedBox(height: 16),
        ])),
      ),
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? darkBackgroundColor.value
          : lightBackgroundColor.value,
      body: SafeArea(
        child: Container(
            color: barColor,
            child: Padding(
              padding:
                  const EdgeInsets.only(left: 16, top: 0, right: 16, bottom: 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    autofocus: true,
                    maxLength: 100,
                    maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    controller: _controller,
                    decoration: InputDecoration(
                      counter: SizedBox.shrink(),
                      hintText: 'Search for Strong\'s numbers',
                      hintStyle: TextStyle(
                          fontFamily: uiFontFamily, fontSize: uiFontSize),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.blueGrey),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.blueGrey),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            BorderSide(color: Colors.blueGrey, width: 2.0),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          Icons.clear,
                          color: isDark
                              ? darkPrimaryColor.value
                              : lightPrimaryColor.value,
                          semanticLabel: 'Clear Search Query',
                        ),
                        onPressed: () => _controller.clear(),
                        iconSize: 32,
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) {
                      if (!_isSearching) {
                        _onSearch();
                      }
                    },
                    style: TextStyle(
                        fontSize: uiFontSize,
                        fontFamily: fontFamilyNotifier.value),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                      alignment: WrapAlignment.end,
                      runAlignment: WrapAlignment.end,
                      children: [
                        ElevatedButton(
                          onPressed: _isResetting || _isSearching
                              ? null
                              : () async {
                                  if (_isResetting) return;
                                  setState(() => _isResetting = true);
                                  setState(() {
                                    _controller.clear();
                                    _searchResults = [];
                                    _foundStrongsNumbers = {};
                                    _phraseSummary = {};
                                    _totalMatches = null;
                                    _totalVerses = null;
                                    _searchType = null;
                                    //_searchTerm = null;
                                    _isRestoring = false;
                                    _isSearching = false;
                                  });

                                  Future.delayed(const Duration(seconds: 3),
                                      () {
                                    if (mounted) {
                                      setState(() => _isResetting = false);
                                    }
                                  });
                                },
                          style: ButtonStyle(
                            backgroundColor:
                                WidgetStateProperty.resolveWith<Color>(
                                    (states) {
                              if (states.contains(WidgetState.disabled)) {
                                return Colors.grey;
                              }
                              return Theme.of(context)
                                      .elevatedButtonTheme
                                      .style
                                      ?.backgroundColor
                                      ?.resolve(states) ??
                                  Colors.blue;
                            }),
                            foregroundColor:
                                WidgetStateProperty.resolveWith<Color>(
                                    (states) {
                              if (states.contains(WidgetState.disabled)) {
                                return Colors.white60;
                              }
                              return Theme.of(context)
                                      .elevatedButtonTheme
                                      .style
                                      ?.foregroundColor
                                      ?.resolve(states) ??
                                  Colors.white;
                            }),
                          ),
                          child: Text('Reset',
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: uiFontSize,
                                  fontFamily: uiFontFamily,
                                  color: getAdaptiveTextColor(context,
                                      usePrimaryColor: true))),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          focusNode: _searchButtonFocusNode,
                          onPressed: _isSearching ? null : () => _onSearch(),
                          child: Text('Search',
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: uiFontSize,
                                  fontFamily: uiFontFamily,
                                  color: getAdaptiveTextColor(context,
                                      usePrimaryColor: true))),
                        ),
                      ]),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _controller.text.trim().isEmpty
                        ? SizedBox.shrink()
                        //Center(
                        //     child: Text('Enter search terms above',
                        //         style: TextStyle(
                        //           fontSize: uiFontSize + 6,
                        //           fontFamily: uiFontFamily,
                        //           color: getAdaptiveTextColor(context),
                        //         )))
                        : _isRestoring
                            ? Center(
                                child: Text('Restoring search results...',
                                    style: TextStyle(
                                        fontSize: uiFontSize,
                                        fontFamily: uiFontFamily,
                                        color: getAdaptiveTextColor(context))))
                            : _isSearching
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // CircularProgressIndicator(
                                        //   strokeWidth: 4.0,
                                        //   valueColor:
                                        //       AlwaysStoppedAnimation<Color>(
                                        //     isDark
                                        //         ? darkPrimaryColor.value
                                        //         : lightPrimaryColor.value,
                                        //   ),
                                        // ),
                                        const SizedBox(height: 16),
                                        Text('Searching...',
                                            style: TextStyle(
                                                fontSize: uiFontSize + 2,
                                                fontFamily: uiFontFamily,
                                                color: getAdaptiveTextColor(
                                                    context))),
                                      ],
                                    ),
                                  )
                                : (_searchResults.isEmpty && _totalMatches == 0)
                                    ? Center(
                                        child: Text(
                                            'No results 🤷‍♂️\n\n⚪ Check your spelling\n⚪ Check the search options',
                                            style: TextStyle(
                                                fontSize: uiFontSize,
                                                fontFamily: uiFontFamily,
                                                color: getAdaptiveTextColor(
                                                    context))))
                                    : ValueListenableBuilder<double>(
                                        valueListenable: fontSizeNotifier,
                                        builder: (context, fontSize, child) {
                                          return RawScrollbar(
                                              minThumbLength: 80.0,
                                              interactive: true,
                                              thumbVisibility: false,
                                              trackVisibility: false,
                                              thickness: 22.0,
                                              thumbColor: isDark
                                                  ? darkPrimaryColor.value
                                                      .withValues(alpha: 0.8)
                                                  : lightPrimaryColor.value
                                                      .withValues(alpha: 0.8),
                                              controller:
                                                  _resultsScrollController,
                                              radius: Radius.circular(8.0),
                                              child: ScrollConfiguration(
                                                  behavior: ScrollConfiguration
                                                          .of(context)
                                                      .copyWith(
                                                          scrollbars: false),
                                                  child: CustomScrollView(
                                                    controller:
                                                        _resultsScrollController,
                                                    slivers: [
                                                      if (showStrongNumbersTable)
                                                        SliverPadding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .only(
                                                                  right: 24.0),
                                                          sliver:
                                                              SliverToBoxAdapter(
                                                            child:
                                                                _buildStrongNumbersTableSection(
                                                                    context,
                                                                    fontSize),
                                                          ),
                                                        ),
                                                      if (_phraseSummary
                                                          .isNotEmpty)
                                                        ..._buildPhraseSummarySlivers(
                                                            context, fontSize),
                                                      if (_searchResults
                                                          .isNotEmpty)
                                                        SliverPadding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .only(
                                                                  bottom: 100.0,
                                                                  right: 24.0),
                                                          sliver:
                                                              _buildVerseResultsSliver(
                                                                  context,
                                                                  fontSize,
                                                                  barColor),
                                                        ),
                                                    ],
                                                  )));
                                        },
                                      ),
                  ),
                ],
              ),
            )),
      ),
    );
  }

  Widget _buildStrongNumbersTableSection(
      BuildContext context, double fontSize) {
    _resetVerseReferenceRecognizers();

    final strongsEntries = _foundStrongsNumbers.entries.toList();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final refStyle = _getPrimaryTextStyle(context, fontSize);
    final snStyle = _getTextStyle(context, fontSize);
    final phraseColumnMaxWidth = _strongNumbersPhraseColumnMaxWidth(context);
    final tableRows = <TableRow>[];

    for (var index = 0; index < strongsEntries.length; index++) {
      final entry = strongsEntries[index];
      final isLastRow = index == strongsEntries.length - 1;
      final ref = entry.value;
      final refText = '${ref['book']} ${ref['chapter']}:${ref['verse']}';
      final phrase =
          StrongsDatabase.extractPhraseBeforeStrongs(refText, entry.key);

      tableRows.add(_buildTableRow(
        [
          Text.rich(_buildVerseReferenceSpan(context, refText, refStyle)),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _showStrongsDefinitionDialog(context, entry.key),
              child: Text(
                entry.key,
                style: snStyle.copyWith(
                  color:
                      isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: phraseColumnMaxWidth),
            child: Text(
              phrase,
              style: snStyle,
              textAlign: TextAlign.left,
            ),
          ),
        ],
        const [TextAlign.left, TextAlign.center, TextAlign.left],
        showBottomBorder: !isLastRow,
      ));
    }

    _scheduleVerseReferenceRecognizerCleanup(_verseReferenceRecognizerIndex);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // _buildSectionHeader(context,
        //     'Strong\'s numbers associated with "${_searchTerm ?? ''}"'),
        _buildSectionHeader(context, 'Strong\'s Summary'),
        _buildCenteredTable(tableRows),
        _buildSectionDivider(),
      ],
    );
  }

  double _strongNumbersPhraseColumnMaxWidth(BuildContext context) {
    final maxWidth = MediaQuery.sizeOf(context).width - 310.0;
    return maxWidth < 96.0 ? 96.0 : maxWidth;
  }

  List<Widget> _buildPhraseSummarySlivers(
      BuildContext context, double fontSize) {
    final sortedPhrases = _phraseSummary.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final phraseStyle = _getTextStyle(context, fontSize);
    final countStyle = _getTextStyle(context, fontSize);
    final totalPhraseStyle = _getTextStyle(context, fontSize, bold: true);
    final totalCountStyle = _getTextStyle(context, fontSize, bold: true);
    final phraseColumnMaxWidth = _phraseSummaryPhraseColumnMaxWidth(context);
    final total =
        _phraseSummary.values.fold<int>(0, (sum, count) => sum + count);
    final phraseColumnWidth = _phraseSummaryColumnWidth(
      context,
      sortedPhrases.map((entry) => entry.key),
      phraseStyle,
      totalPhraseStyle,
      phraseColumnMaxWidth,
    );
    final countColumnWidth = _phraseSummaryCountColumnWidth(
      context,
      sortedPhrases.map((entry) => '${entry.value}'),
      '$total',
      countStyle,
      totalCountStyle,
    );
    return [
      SliverPadding(
        padding: const EdgeInsets.only(right: 24.0),
        sliver: SliverToBoxAdapter(
          child: _buildSectionHeader(context, 'Phrase Summary'),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.only(right: 24.0),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final isTotalRow = index == sortedPhrases.length;
              final String phraseText;
              final TextStyle phraseTextStyle;
              final String countText;
              final TextStyle countTextStyle;
              final List<TextAlign> alignments;

              if (isTotalRow) {
                phraseText = 'Total';
                phraseTextStyle = totalPhraseStyle;
                countText = '$total';
                countTextStyle = totalCountStyle;
                alignments = const [TextAlign.left, TextAlign.right];
              } else {
                final entry = sortedPhrases[index];
                phraseText = entry.key;
                phraseTextStyle = phraseStyle;
                countText = '${entry.value}';
                countTextStyle = countStyle;
                alignments = const [TextAlign.left, TextAlign.right];
              }

              return Padding(
                padding: const EdgeInsets.only(right: 22.0),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    var fittedPhraseColumnWidth = phraseColumnWidth;
                    final availablePhraseWidth =
                        constraints.maxWidth - countColumnWidth;
                    if (availablePhraseWidth <= 0.0) {
                      fittedPhraseColumnWidth = 1.0;
                    } else if (fittedPhraseColumnWidth > availablePhraseWidth) {
                      fittedPhraseColumnWidth = availablePhraseWidth;
                    }
                    final assignedPhraseTextWidth = fittedPhraseColumnWidth >
                            _phraseSummaryColumnHorizontalPadding
                        ? fittedPhraseColumnWidth -
                            _phraseSummaryColumnHorizontalPadding
                        : 0.0;
                    final phraseShouldWrap = !isTotalRow &&
                        _measureTextWidth(
                              context,
                              phraseText,
                              phraseTextStyle,
                            ) >
                            assignedPhraseTextWidth;
                    final phraseCell = isTotalRow
                        ? SizedBox(
                            width: assignedPhraseTextWidth,
                            child: Text(
                              phraseText,
                              style: phraseTextStyle,
                              textAlign: TextAlign.left,
                              softWrap: false,
                            ),
                          )
                        : ConstrainedBox(
                            constraints:
                                BoxConstraints(maxWidth: phraseColumnMaxWidth),
                            child: SizedBox(
                              width: assignedPhraseTextWidth,
                              child: Text(
                                phraseText,
                                style: phraseTextStyle,
                                textAlign: TextAlign.left,
                                softWrap: phraseShouldWrap,
                                overflow: phraseShouldWrap
                                    ? TextOverflow.clip
                                    : TextOverflow.visible,
                              ),
                            ),
                          );
                    final countCell = Text(
                      countText,
                      style: countTextStyle,
                      //textAlign: isTotalRow ? TextAlign.left : TextAlign.right,
                      textAlign: TextAlign.right,
                      softWrap: false,
                    );

                    return Align(
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: fittedPhraseColumnWidth + countColumnWidth,
                        child: Table(
                          columnWidths: {
                            0: FixedColumnWidth(fittedPhraseColumnWidth),
                            1: FixedColumnWidth(countColumnWidth),
                          },
                          defaultVerticalAlignment:
                              TableCellVerticalAlignment.middle,
                          children: [
                            _buildTableRow(
                              [phraseCell, countCell],
                              alignments,
                              showBottomBorder: !isTotalRow,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
            childCount: sortedPhrases.length + 1,
            addAutomaticKeepAlives: false,
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.only(right: 24.0),
        sliver: SliverToBoxAdapter(child: _buildSectionDivider()),
      ),
    ];
  }

  double _phraseSummaryColumnWidth(
    BuildContext context,
    Iterable<String> phrases,
    TextStyle phraseStyle,
    TextStyle totalStyle,
    double maxContentWidth,
  ) {
    var contentWidth = _measureTextWidth(context, 'Total', totalStyle);
    for (final phrase in phrases) {
      final width = _measureTextWidth(context, phrase, phraseStyle);
      if (width > contentWidth) contentWidth = width;
    }
    return contentWidth.clamp(0.0, maxContentWidth) +
        _phraseSummaryColumnHorizontalPadding;
  }

  double _phraseSummaryCountColumnWidth(
    BuildContext context,
    Iterable<String> counts,
    String total,
    TextStyle countStyle,
    TextStyle totalStyle,
  ) {
    var contentWidth = _measureTextWidth(context, total, totalStyle);
    for (final count in counts) {
      final width = _measureTextWidth(context, count, countStyle);
      if (width > contentWidth) contentWidth = width;
    }
    return contentWidth + _phraseSummaryColumnHorizontalPadding;
  }

  double _measureTextWidth(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    // Table cells receive this value as a hard max width. Verify the rounded
    // candidate against finite-width paragraph layout so phrases do not wrap
    // just because the measured intrinsic width landed on a break boundary.
    var width = painter.width.ceilToDouble() + _phraseSummaryWidthBuffer;
    final maxVerifiedWidth = width + 16.0;
    while (width <= maxVerifiedWidth) {
      painter.layout(maxWidth: width);
      if (painter.computeLineMetrics().length <= 1) return width;
      width += 1.0;
    }

    return width;
  }

  double _phraseSummaryPhraseColumnMaxWidth(BuildContext context) {
    final maxWidth = MediaQuery.sizeOf(context).width - 120.0;
    return maxWidth < 96.0 ? 96.0 : maxWidth;
  }

  Widget _buildCenteredTable(List<TableRow> tableRows) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(right: 22.0),
      child: Center(
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: tableRows,
        ),
      ),
    );
  }

  TableRow _buildTableRow(List<Widget> cells, List<TextAlign> alignments,
      {bool showBottomBorder = true}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return TableRow(
      decoration: showBottomBorder
          ? BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? darkPrimaryColor.value.withAlpha(64)
                      : lightPrimaryColor.value.withAlpha(64),
                  width: 0.5,
                ),
              ),
            )
          : null,
      children: List.generate(cells.length, (index) {
        return _buildTableCell(cells[index], alignments[index]);
      }),
    );
  }

  Widget _buildTableCell(Widget child, TextAlign alignment) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 1.0),
      child: child,
    );
  }

  TextStyle _getPrimaryTextStyle(BuildContext context, double fontSize) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
      fontSize: fontSize - 2,
      //fontFamily: noteFontFamilyNotifier.value,
      color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
    );
  }

  TextStyle _getTextStyle(BuildContext context, double fontSize,
      {bool bold = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
      fontSize: fontSize - 2,
      //fontFamily: noteFontFamilyNotifier.value,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      color: isDark ? darkTextColor.value : lightTextColor.value,
    );
  }

  Widget _buildSectionDivider() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8.0),
      child: Divider(thickness: 1),
    );
  }

  SliverList _buildVerseResultsSliver(
      BuildContext context, double fontSize, Color barColor) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, resultIndex) {
          return _buildVerseResult(context, _searchResults[resultIndex],
              resultIndex, fontSize, barColor);
        },
        childCount: _searchResults.length,
      ),
    );
  }

  Widget _buildVerseResult(BuildContext context, Map<String, dynamic> result,
      int resultIndex, double fontSize, Color barColor) {
    final bookShort = result['book'] as String;
    final chapter = result['chapter'] as int;
    final verse = result['verse'] as int?;
    final isSuperscription = result['isSuperscription'] == true;
    final bookLongName = BookNameConverter.shortNameToLongName(bookShort);
    final referenceText =
        isSuperscription ? 'Psalm $chapter:0' : '$bookLongName $chapter:$verse';

    return GestureDetector(
      onTap: () => _showStrongsVerseActionMenu(context, result),
      child: Container(
        color: barColor,
        width: double.infinity,
        padding: const EdgeInsets.only(
            left: 0.0, top: 0.0, bottom: 0.0, right: 18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(TextSpan(children: [
              TextSpan(
                text: '$referenceText\n',
                style: TextStyle(
                    fontSize: FontSizeAdjustments.getAdjustedSize(
                        fontFamilyNotifier.value, fontSize),
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? darkPrimaryColor.value
                        : lightPrimaryColor.value),
              ),
              _buildVerseSpan(context, result, fontSize),
            ])),
            if (resultIndex < _searchResults.length - 1)
              Divider(
                thickness: 1,
                height: 16,
                indent: MediaQuery.of(context).size.width * 0.01,
                endIndent: MediaQuery.of(context).size.width * 0.01,
                color: const Color.fromARGB(47, 158, 158, 158),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding:
          const EdgeInsets.only(top: 4.0, bottom: 8.0, left: 0.0, right: 22.0),
      child: Text(title,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: uiFontSize,
              fontFamily: uiFontFamily,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).brightness == Brightness.dark
                  ? darkPrimaryColor.value
                  : lightPrimaryColor.value)),
    );
  }
}
