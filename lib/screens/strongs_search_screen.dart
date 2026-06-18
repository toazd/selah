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

// Top-level functions for compute() to enable off-main-thread execution
Future<List<Map<String, dynamic>>> _computeStrongsNumberSearch(
    String strongsNumber) async {
  if (kDebugMode) {
    debugPrint(
        '[_computeStrongsNumberSearch] START: strongsNumber="$strongsNumber"');
  }
  final result = StrongsDatabase.searchByStrongsNumber(strongsNumber);
  if (kDebugMode) {
    debugPrint('[_computeStrongsNumberSearch] DONE: ${result.length} verses');
  }
  return result;
}

Future<WordSearchComputationResult> _computeWordSearchResult(
    String word) async {
  if (kDebugMode) {
    debugPrint('[_computeWordSearchResult] START: word="$word"');
  }
  final wordData = StrongsDatabase.searchByWordWithStrongsNumbers(word);
  final foundStrongs = wordData.foundStrongsNumbers;
  if (wordData.wordVerses.isEmpty || foundStrongs.isEmpty) {
    if (kDebugMode) {
      debugPrint(
          '[_computeWordSearchResult] DONE: ${wordData.wordVerses.length} word verses, ${foundStrongs.length} Strong\'s numbers');
    }
    return WordSearchComputationResult(
      wordVerseCount: wordData.wordVerses.length,
      foundStrongsNumbers: foundStrongs,
      searchResults: const [],
      phraseSummary: const {},
    );
  }

  final strongsList = foundStrongs.keys.toList();
  final results = StrongsDatabase.searchByStrongsNumbers(strongsList);
  final phraseSummary = results.isEmpty
      ? <String, int>{}
      : StrongsDatabase.extractPhraseSummary(results, strongsList);
  if (kDebugMode) {
    debugPrint(
        '[_computeWordSearchResult] DONE: ${wordData.wordVerses.length} word verses, ${foundStrongs.length} Strong\'s numbers, ${results.length} result verses, ${phraseSummary.length} phrases');
  }
  return WordSearchComputationResult(
    wordVerseCount: wordData.wordVerses.length,
    foundStrongsNumbers: foundStrongs,
    searchResults: results,
    phraseSummary: phraseSummary,
  );
}

Future<List<Map<String, dynamic>>> _computeSearchByStrongsNumbers(
    SearchTaskData data) async {
  if (kDebugMode) {
    debugPrint(
        '[_computeSearchByStrongsNumbers] START: ${data.strongsList.length} Strong\'s numbers: ${data.strongsList}');
  }
  final result = StrongsDatabase.searchByStrongsNumbers(data.strongsList);
  if (kDebugMode) {
    debugPrint(
        '[_computeSearchByStrongsNumbers] DONE: ${result.length} verses');
  }
  return result;
}

Future<Map<String, int>> _computeExtractPhraseSummary(
    SummaryTaskData data) async {
  if (kDebugMode) {
    debugPrint(
        '[_computeExtractPhraseSummary] START: ${data.strongsList.length} SNs, ${data.results.length} results');
  }
  final result = StrongsDatabase.extractPhraseSummary(
    data.results,
    data.strongsList,
    includeTvm: data.includeTvmMatches,
  );
  if (kDebugMode) {
    debugPrint(
        '[_computeExtractPhraseSummary] DONE: ${result.length} unique phrases');
  }
  return result;
}

Future<ReferenceSearchResult> _computeReferenceSearch(
    ReferenceSearchTaskData data) async {
  // Validate book, chapter, verse
  final availableBooks = StrongsDatabase.getAvailableBooks();
  if (!availableBooks.contains(data.book)) {
    return ReferenceSearchResult(error: 'Invalid book: ${data.book}');
  }

  final availableChapters = StrongsDatabase.getAvailableChapters(data.book);
  if (!availableChapters.contains(data.chapter)) {
    return ReferenceSearchResult(
        error: 'Invalid chapter ${data.chapter} for ${data.book}');
  }

  final availableVerses =
      StrongsDatabase.getAvailableVerses(data.book, data.chapter);
  if (!availableVerses.contains(data.verse)) {
    return ReferenceSearchResult(
        error: 'Invalid verse ${data.verse} for ${data.book} ${data.chapter}');
  }

  // Check if word exists in verse
  if (!StrongsDatabase.wordExistsInVerse(
      data.book, data.chapter, data.verse, data.word)) {
    return ReferenceSearchResult(
        error:
            'Word "${data.word}" not found in ${data.book} ${data.chapter}:${data.verse}');
  }

  // Get Strong's numbers for the word in this verse
  final strongsNumbers = StrongsDatabase.findStrongsNumbersForWordInVerse(
      data.book, data.chapter, data.verse, data.word);

  if (strongsNumbers.isEmpty) {
    return ReferenceSearchResult(
        error:
            'No Strong\'s numbers found for "${data.word}" in ${data.book} ${data.chapter}:${data.verse}');
  }

  // Get the verse text
  // final verseText =
  //     StrongsDatabase.getVerseText(data.book, data.chapter, data.verse);

  return ReferenceSearchResult(
    strongsNumbers: strongsNumbers,
    //verseText: verseText,
    book: data.book,
    chapter: data.chapter,
    verse: data.verse,
    word: data.word,
  );
}

// Helper data classes for passing data to compute()
class SearchTaskData {
  final String word;
  final List<Map<String, dynamic>> wordVerses;
  final List<String> strongsList;

  SearchTaskData({
    required this.word,
    required this.wordVerses,
    required this.strongsList,
  });
}

class SummaryTaskData {
  final List<Map<String, dynamic>> results;
  final List<String> strongsList;
  final bool includeTvmMatches;

  SummaryTaskData({
    required this.results,
    required this.strongsList,
    this.includeTvmMatches = false,
  });
}

class ReferenceSearchTaskData {
  final String book;
  final int chapter;
  final int verse;
  final String word;

  ReferenceSearchTaskData({
    required this.book,
    required this.chapter,
    required this.verse,
    required this.word,
  });
}

class ReferenceSearchResult {
  final List<String>? strongsNumbers;
  //final String? verseText;
  final String? book;
  final int? chapter;
  final int? verse;
  final String? word;
  final String? error;

  ReferenceSearchResult({
    this.strongsNumbers,
    //this.verseText,
    this.book,
    this.chapter,
    this.verse,
    this.word,
    this.error,
  });
}

class WordSearchComputationResult {
  final int wordVerseCount;
  final Map<String, Map<String, dynamic>> foundStrongsNumbers;
  final List<Map<String, dynamic>> searchResults;
  final Map<String, int> phraseSummary;

  const WordSearchComputationResult({
    required this.wordVerseCount,
    required this.foundStrongsNumbers,
    required this.searchResults,
    required this.phraseSummary,
  });
}

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
  bool _isSearchingWeb = false;
  bool _isLoadingDialogVisible = false;
  bool _searchTimedOut = false;
  Timer? _searchTimeoutTimer;
  int _activeSearchId = 0;

  static const String _lastSearchTermKey = 'lastStrongsSearchTerm';
  static const String _scrollOffsetKey = 'strongsSearchScrollOffset';

  @override
  bool get wantKeepAlive => true;

  void _showLoadingDialog(int searchId) {
    _searchTimedOut = false;
    _searchTimeoutTimer?.cancel();
    if (!kIsWeb) {
      _searchTimeoutTimer = Timer(const Duration(seconds: 60), () {
        if (searchId != _activeSearchId) return;
        if (kDebugMode) {
          debugPrint('[_searchTimeoutTimer] 60s search timeout reached');
        }
        _searchTimedOut = true;
        _hideLoadingDialog(searchId: searchId);
        if (mounted) {
          setState(() {
            _searchResults = [];
            _foundStrongsNumbers = {};
            _phraseSummary = {};
            _totalMatches = null;
            _totalVerses = null;
            _searchType = null;
            //_searchTerm = null;
          });
          showStyledSnackBar(context,
              'Maximum search time exceeded. Please try a different word.');
        }
      });
    }
    _isLoadingDialogVisible = true;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? darkBackgroundColor.value : lightBackgroundColor.value;

    showDialog(
      animationStyle: AnimationStyle(duration: Duration(seconds: 0)),
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: bgColor,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              padding: EdgeInsetsGeometry.all(0),
              constraints: BoxConstraints.tight(Size(72, 72)),
              strokeWidth: 7.0,
              semanticsLabel: "Searching",
              strokeCap: StrokeCap.round,
              valueColor: AlwaysStoppedAnimation<Color>(
                isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Searching...',
              style: TextStyle(
                fontSize: uiFontSize,
                fontFamily: uiFontFamily,
                color: getAdaptiveTextColor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _hideLoadingDialog({int? searchId}) {
    if (searchId != null && searchId != _activeSearchId) return;
    _searchTimeoutTimer?.cancel();
    _searchTimeoutTimer = null;
    if (_isLoadingDialogVisible && mounted && Navigator.canPop(context)) {
      _isLoadingDialogVisible = false;
      Navigator.pop(context);
    }
  }

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
    _searchTimedOut = false;
    if (input.isEmpty) {
      _hideLoadingDialog(searchId: searchId);
      setState(() {
        _searchResults = [];
        _foundStrongsNumbers = {};
        _phraseSummary = {};
        _totalMatches = 0;
        _totalVerses = 0;
        _searchType = null;
        //_searchTerm = null;
        _isSearchingWeb = false;
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
      _isSearchingWeb = kIsWeb && showLoading;
    });

    _persistSearchState(input);

    if (resetScroll && _resultsScrollController.hasClients) {
      _resultsScrollController.jumpTo(0.0);
    }

    if (showLoading && !kIsWeb) {
      _showLoadingDialog(searchId);
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
          _performStrongsNumberSearch(strongsNumber, searchId);
        } else {
          _performWordSearch(searchTerm, searchId);
        }
      },
    );
  }

  void _startSearchTask({
    required int searchId,
    required bool showLoading,
    required VoidCallback task,
  }) {
    void runTask() {
      if (!mounted || searchId != _activeSearchId) return;
      task();
    }

    if (kIsWeb && showLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future<void>.delayed(Duration.zero, runTask);
      });
    } else {
      Future.microtask(runTask);
    }
  }

  void _performStrongsNumberSearch(String strongsNumber, int searchId) async {
    if (kDebugMode) {
      debugPrint(
          '[_performStrongsNumberSearch] START: strongsNumber="$strongsNumber"');
    }
    _unfocusSearchField(); // Don't wait or it flashes for a split second
    try {
      final results = await compute(_computeStrongsNumberSearch, strongsNumber);
      if (!mounted) return;
      if (_isResetting) return;
      if (searchId != _activeSearchId) return;
      if (_searchTimedOut) return;
      if (kDebugMode) {
        debugPrint(
            '[_performStrongsNumberSearch] Got ${results.length} results from compute');
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
          _isSearchingWeb = false;
        });
        _hideLoadingDialog(searchId: searchId);
        return;
      }

      if (_searchTimedOut) return;

      if (kDebugMode) {
        debugPrint(
            '[_performStrongsNumberSearch] Calling extractPhraseSummary...');
      }
      final summaryData = SummaryTaskData(
        results: results,
        strongsList: [strongsNumber],
        includeTvmMatches: true,
      );
      final phraseSummary =
          await compute(_computeExtractPhraseSummary, summaryData);
      if (kDebugMode) {
        debugPrint(
            '[_performStrongsNumberSearch] extractPhraseSummary done: ${phraseSummary.length} phrases');
      }
      if (!mounted) return;
      if (_isResetting) return;
      if (searchId != _activeSearchId) return;
      if (_searchTimedOut) return;

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
        _isSearchingWeb = false;
      });
      _hideLoadingDialog(searchId: searchId);
    } catch (e) {
      if (mounted) {
        if (!_isResetting) {
          if (searchId != _activeSearchId) return;
          setState(() {
            _isRestoring = false;
            _isSearchingWeb = false;
          });
          _hideLoadingDialog(searchId: searchId);
          showStyledSnackBar(context, 'Search failed: ${e.toString()}');
        }
      }
    }
  }

  void _performWordSearch(String word, int searchId) async {
    if (kDebugMode) {
      debugPrint('[_performWordSearch] ===== START: word="$word" =====');
    }
    _unfocusSearchField(); // Don't wait or it flashes for a split second
    try {
      final wordSearchResult = await compute(_computeWordSearchResult, word);
      if (kDebugMode) {
        debugPrint(
            '[_performWordSearch] Word search compute done: ${wordSearchResult.wordVerseCount} word verses, ${wordSearchResult.foundStrongsNumbers.length} Strong\'s numbers, ${wordSearchResult.searchResults.length} result verses');
      }
      if (!mounted) return;
      if (_isResetting) return;
      if (searchId != _activeSearchId) return;
      if (_searchTimedOut) return;

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
          _isSearchingWeb = false;
        });
        _hideLoadingDialog(searchId: searchId);
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
          _isSearchingWeb = false;
        });
        _hideLoadingDialog(searchId: searchId);
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
        _isSearchingWeb = false;
      });
      _hideLoadingDialog(searchId: searchId);
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
            _isSearchingWeb = false;
          });
          _hideLoadingDialog(searchId: searchId);
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
      final result = await compute(_computeReferenceSearch, refSearch);
      if (kDebugMode) {
        debugPrint(
            '[_performReferenceSearch] Reference search done: error=${result.error}, strongsNumbers=${result.strongsNumbers}');
      }
      if (!mounted) return;
      if (_isResetting) return;
      if (searchId != _activeSearchId) return;
      if (_searchTimedOut) return;

      // Check for errors
      if (result.error != null) {
        _hideLoadingDialog(searchId: searchId);
        showStyledSnackBar(context, result.error!);
        setState(() {
          _searchResults = [];
          _foundStrongsNumbers = {};
          _phraseSummary = {};
          _totalMatches = 0;
          _totalVerses = 0;
          _searchType = 'reference';
          _isRestoring = false;
          _isSearchingWeb = false;
        });
        return;
      }

      final strongsNumbers = result.strongsNumbers!;

      final foundStrongs = <String, Map<String, dynamic>>{};
      for (final sn in strongsNumbers) {
        foundStrongs[sn] = {
          'book': result.book!,
          'chapter': result.chapter!,
          'verse': result.verse!,
        };
      }

      setState(() {
        _foundStrongsNumbers = foundStrongs;
      });

      if (_searchTimedOut) return;

      // Search the entire bible for all these Strong's numbers
      if (kDebugMode) {
        debugPrint(
            '[_performReferenceSearch] Searching all verses for ${strongsNumbers.length} Strong\'s numbers: $strongsNumbers');
      }
      final searchData = SearchTaskData(
        word: result.word!,
        wordVerses: [],
        strongsList: strongsNumbers,
      );
      final results = await compute(_computeSearchByStrongsNumbers, searchData);
      if (kDebugMode) {
        debugPrint(
            '[_performReferenceSearch] searchByStrongsNumbers done: ${results.length} verses');
      }
      if (!mounted) return;
      if (_isResetting) return;
      if (searchId != _activeSearchId) return;
      if (_searchTimedOut) return;

      if (results.isEmpty) {
        setState(() {
          _searchResults = [];
          _foundStrongsNumbers = {};
          _phraseSummary = {};
          _totalMatches = 0;
          _totalVerses = 0;
          _searchType = 'reference';
          _isRestoring = false;
          _isSearchingWeb = false;
        });
        _hideLoadingDialog(searchId: searchId);
        return;
      }

      if (kDebugMode) {
        debugPrint('[_performReferenceSearch] Extracting phrase summary...');
      }
      final summaryData = SummaryTaskData(
        results: results,
        strongsList: strongsNumbers,
      );
      final phraseSummary =
          await compute(_computeExtractPhraseSummary, summaryData);
      if (kDebugMode) {
        debugPrint(
            '[_performReferenceSearch] extractPhraseSummary done: ${phraseSummary.length} phrases');
      }
      if (!mounted) return;
      if (_isResetting) return;
      if (searchId != _activeSearchId) return;
      if (_searchTimedOut) return;

      int totalMatches = 0;
      for (final count in phraseSummary.values) {
        totalMatches += count;
      }

      setState(() {
        _searchResults = results;
        _phraseSummary = phraseSummary;
        _totalMatches = totalMatches;
        _totalVerses = results.length;
        _searchType = 'reference';
        _isRestoring = false;
        _isSearchingWeb = false;
      });
      _hideLoadingDialog(searchId: searchId);
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
            _isSearchingWeb = false;
          });
          _hideLoadingDialog(searchId: searchId);
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
      return TextSpan(text: refText, style: refStyle);
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
    _searchTimeoutTimer?.cancel();
    _searchTimeoutTimer = null;
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
    _restoreSearchState();
    _resultsScrollController.addListener(_saveScrollOffset);
  }

  @override
  void dispose() {
    _disposeVerseReferenceRecognizers();
    _searchButtonFocusNode.dispose();
    _persistSearchState(_controller.text.trim());
    _resultsScrollController.removeListener(_saveScrollOffset);
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
        _isSearchingWeb = false;
      });
      return;
    }

    setState(() {
      _controller.text = lastSearch;
      _isRestoring = true;
      _isSearchingWeb = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _onSearch(showLoading: false, resetScroll: false);
      await _loadScrollOffset();
    });
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

  Future<void> _saveScrollOffset() async {
    if (!_resultsScrollController.hasClients) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_scrollOffsetKey, _resultsScrollController.offset);
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
                      _onSearch();
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
                          onPressed: _isResetting
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
                                    _isSearchingWeb = false;
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
                          onPressed: () => _onSearch(),
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
                            : _isSearchingWeb
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CircularProgressIndicator(
                                          strokeWidth: 4.0,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                            isDark
                                                ? darkPrimaryColor.value
                                                : lightPrimaryColor.value,
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        Text('Searching...',
                                            style: TextStyle(
                                                fontSize: uiFontSize,
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
                                                        SliverPadding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .only(
                                                                  right: 24.0),
                                                          sliver:
                                                              SliverToBoxAdapter(
                                                            child:
                                                                _buildPhraseSummaryTableSection(
                                                                    context,
                                                                    fontSize),
                                                          ),
                                                        ),
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

    for (final entry in strongsEntries) {
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

  Widget _buildPhraseSummaryTableSection(
      BuildContext context, double fontSize) {
    final sortedPhrases = _phraseSummary.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final phraseStyle = _getTextStyle(context, fontSize);
    final countStyle = _getTextStyle(context, fontSize);
    final totalPhraseStyle = _getTextStyle(context, fontSize, bold: true);
    final totalCountStyle = _getTextStyle(context, fontSize, bold: true);
    final phraseColumnMaxWidth = _phraseSummaryPhraseColumnMaxWidth(context);
    final tableRows = <TableRow>[];

    for (final entry in sortedPhrases) {
      tableRows.add(_buildTableRow(
        [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: phraseColumnMaxWidth),
            child: Text(
              entry.key,
              style: phraseStyle,
              textAlign: TextAlign.left,
            ),
          ),
          Text(
            '${entry.value}',
            style: countStyle,
            textAlign: TextAlign.right,
          ),
        ],
        const [TextAlign.left, TextAlign.right],
      ));
    }

    final total =
        _phraseSummary.values.fold<int>(0, (sum, count) => sum + count);
    tableRows.add(_buildTableRow(
      [
        Text(
          'Total',
          style: totalPhraseStyle,
          textAlign: TextAlign.left,
        ),
        Text(
          '$total',
          style: totalCountStyle,
          textAlign: TextAlign.left,
        ),
      ],
      const [TextAlign.left, TextAlign.left],
    ));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildSectionHeader(context, 'Phrase Summary'),
        _buildCenteredTable(tableRows),
        _buildSectionDivider(),
      ],
    );
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

  TableRow _buildTableRow(List<Widget> cells, List<TextAlign> alignments) {
    return TableRow(
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
      fontSize: fontSize,
      fontFamily: noteFontFamilyNotifier.value,
      color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
    );
  }

  TextStyle _getTextStyle(BuildContext context, double fontSize,
      {bool bold = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextStyle(
      fontSize: fontSize,
      fontFamily: noteFontFamilyNotifier.value,
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
