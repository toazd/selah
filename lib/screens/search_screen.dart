import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:selah/utils/tablet_mode_detector.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/bible_database.dart';
import '../main.dart';
import '../utils/verse_text_parser.dart';
import '../widgets/search_history_dialog.dart';
import '../utils/book_name_converter.dart'; // Import for book name conversion
import '../utils/book_filter.dart'; // Import for book filtering
import '../screens/chapter_dialog.dart'; // Import for ChapterDialog
import '../screens/note_screen.dart'; // Import for NoteScreen
import '../database/history_database.dart'; // Import for history tracking
import '../database/search_database.dart'; // Import for search history database
import 'package:flutter/services.dart'; // <-- added to request on-screen keyboard
import '../utils/preferences_constants.dart';
import '../../utils/snackbar_notification.dart';
import '../widgets/responsive_text.dart';
import '../services/local_data_change_notifier.dart';
import 'dart:async';
import '../utils/bible_utils.dart';
import '../utils/font_size_adjustments.dart';
import '../utils/error_handler.dart';
import 'strongs_search_screen.dart';

// Helper function to create a slightly different shade for bars
Color _adjustBarColor(Color backgroundColor) {
  final hsl = HSLColor.fromColor(backgroundColor);
  // If lightness > 0.5 (light color), make slightly darker; otherwise make slightly lighter
  final adjustedLightness = hsl.lightness > 0.5
      ? (hsl.lightness - 0.03).clamp(0.0, 1.0) // Darker for light backgrounds
      : (hsl.lightness + 0.03).clamp(0.0, 1.0); // Lighter for dark backgrounds
  return hsl.withLightness(adjustedLightness).toColor();
}

class SearchScreen extends StatefulWidget {
  final int? sourceScreenIndex;

  const SearchScreen({
    super.key,
    this.sourceScreenIndex,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with AutomaticKeepAliveClientMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _controller = TextEditingController();
  //final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _resultsScrollController = ScrollController();
  final FocusNode _searchButtonFocusNode = FocusNode();

  static const String _regexKey = 'searchRegex';
  static const String _nearbyKey = 'searchNearby';
  static const String _wholeWordKey = 'searchWholeWord';
  static const String _redLetterKey = 'searchRedLetter';
  static const String _caseSensitiveKey = 'searchCaseSensitive';
  static const String _bookFilterTypeKey = 'searchBookFilterType';
  static const String _bookFilterCustomKey = 'searchBookFilterCustom';

  bool _useRegex = false;
  bool _useNearby = false;
  bool _isNearbySearchActive =
      false; // Tracks if nearby search was actually performed
  bool _useWholeWord = false;
  bool _useRedLetter = false;
  bool _caseSensitive = false;
  //bool _isDisposing = false; // Flag to prevent operations during disposal
  bool _isResetting = false; // Flag to prevent spamming the reset button

  // Book filter state
  String _bookFilterType = 'All Books'; // Current selected filter type
  String _customBookFilter = ''; // Custom range specification
  List<String> _allowedBooks = []; // Parsed allowed books (short names)
  Map<String, Set<int>> _allowedChapters =
      {}; // Parsed allowed chapters per book
  late TextEditingController
      _customRangeController; // Controller for custom range input
  String? _customRangeError; // Error message for invalid custom range
  // Define the method channel, ensuring the name matches the C++ implementation.
  //static const _keyboardChannel = MethodChannel('com.selah.holybible/keyboard');

  // Search results
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  Timer? _onSearchDebounce;
  int? _totalMatches;
  int? _totalVerses;
  RegExp? _currentRegex;

  // Tracking when the user last input any character
  DateTime _lastInputTime = DateTime.now();

  // Cache for highlighted text spans to improve performance
  final Map<String, TextSpan> _highlightedSpansCache = {};

  @override
  bool get wantKeepAlive => true;

  // Generate a unique cache key for a verse based on its content and search options
  String _getVerseCacheKey(Map<String, dynamic> verse) {
    final verseText = verse['text'] as String;
    final book = verse['book'] as String;
    final chapter = verse['chapter'] as int;
    final verseNum = verse['verse'] as int;

    // Include search options in cache key to invalidate when options change
    return '$book:$chapter:$verseNum:${_useRegex}_$_useWholeWord}_$_useRedLetter}_$_caseSensitive}:$verseText';
  }

  // Get cached highlighted span or compute and cache it
  TextSpan _getHighlightedSpan(
      Map<String, dynamic> verse, TextStyle baseStyle) {
    final cacheKey = _getVerseCacheKey(verse);

    if (_highlightedSpansCache.containsKey(cacheKey)) {
      return _highlightedSpansCache[cacheKey]!;
    }

    // Remove pilcrow symbol from verse text before parsing for display
    String displayText = (verse['text'] as String).trim();
    // if (displayText.contains('¶ ')) {
    //   displayText = displayText.replaceAll('¶ ', '');
    // }

    // Compute the highlighted span
    final parsedSpan = VerseTextParser.parseVerseText(
      displayText,
      baseStyle,
    );

    final highlightedSpan = _highlightParsedSpan(
      parsedSpan,
      _currentRegex!,
      context,
      redLetterOnly: _useRedLetter,
    );

    // Cache the result
    _highlightedSpansCache[cacheKey] = highlightedSpan;
    return highlightedSpan;
  }

  // Clear cache when search options change
  void _clearHighlightCache() {
    _highlightedSpansCache.clear();
  }

  // Create RegExp with conditional unicode flag based on pattern content
  RegExp _createRegExp(String pattern, bool caseSensitive) {
    // Enable unicode mode if the pattern contains Unicode-aware regex features
    final hasUnicodePatterns = pattern.contains('\\p{P}') ||
        pattern.contains('\\p{L}') ||
        pattern.contains('\\p{N}') ||
        pattern.contains('\\p{S}') ||
        pattern.contains('\\p{Z}') ||
        pattern.contains('\\p{M}');
    return RegExp(pattern,
        caseSensitive: caseSensitive, unicode: hasUnicodePatterns);
  }

  // --- BEGIN: Ensure results are in DB/Biblical order ---
  Map<String, int>? _bookOrderIndex;

  String _normBook(dynamic b) => b.toString().trim().toUpperCase();

  Future<void> _buildBookOrderIndex() async {
    if (_bookOrderIndex != null) return;
    final books = await BibleDatabase.getBooks();
    final map = <String, int>{};
    for (int i = 0; i < books.length; i++) {
      final raw = books[i];
      map[raw] = i; // exact key
      map[_normBook(raw)] = i; // normalized key
    }
    _bookOrderIndex = map;
  }

  int _bookIdx(dynamic b) {
    final m = _bookOrderIndex;
    if (m == null) return 1 << 30;
    final norm = _normBook(b);
    return m[norm] ?? m[b] ?? (1 << 30);
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  void _sortResultsInBibleOrder(List<Map<String, dynamic>> list) {
    list.sort((a, b) {
      final ia = _bookIdx(a['book']);
      final ib = _bookIdx(b['book']);
      if (ia != ib) return ia.compareTo(ib);
      final ca = _asInt(a['chapter']);
      final cb = _asInt(b['chapter']);
      if (ca != cb) return ca.compareTo(cb);
      final va = _asInt(a['verse']);
      final vb = _asInt(b['verse']);
      return va.compareTo(vb);
    });
  }

  String _extractRedLetterText(String text) {
    final matches = RegExp(r'<r>(.*?)</r>', dotAll: true).allMatches(text);
    return matches.map((m) => m.group(1)!).join(' ');
  }

  String _stripRedLetterTags(String text) {
    return text.replaceAll(RegExp(r'</?r>'), '');
  }

  String _getSearchText(String verseText, bool useRedLetter) {
    String processedText = useRedLetter
        ? _extractRedLetterText(verseText)
        : _stripRedLetterTags(verseText);
    // Remove pilcrow symbol if present to exclude from regex processing
    if (processedText.contains('¶ ')) {
      processedText = processedText.replaceAll('¶ ', '');
    }
    return processedText;
  }

  // Check if input is valid for nearby search (>1 word, no quoted phrases)
  bool _isValidNearbyInput(String input) {
    if (!_useNearby || _useRegex) return false;

    // Parse input similar to _buildSearchPattern
    RegExp phraseRegExp = RegExp(r'"([^"]+)"');
    String withoutPhrases = input.replaceAll(phraseRegExp, '').trim();
    final words = withoutPhrases
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    return words.length > 1;
  }

  // Show warning when nearby search criteria aren't met
  void _showNearbyWarning(String input) {
    String reason = '';
    if (_useRegex) {
      reason = 'Nearby search does not work with Regex mode.';
    } else {
      RegExp phraseRegExp = RegExp(r'"([^"]+)"');
      String withoutPhrases = input.replaceAll(phraseRegExp, '').trim();
      final words = withoutPhrases
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();

      if (input.contains('"')) {
        reason = 'Nearby search does not work with phrases.';
      } else if (words.length <= 1) {
        reason = 'Nearby search requires more than one word.';
      }
    }

    showStyledSnackBar(context, reason);
  }

  // Perform nearby search - find clusters where all keywords appear within 7 verses
  Future<List<Map<String, dynamic>>> _searchVersesNearby(String input) async {
    // Parse input to get keywords (no phrases allowed in nearby search)
    RegExp phraseRegExp = RegExp(r'"([^"]+)"');
    String withoutPhrases = input.replaceAll(phraseRegExp, '').trim();
    final keywords = withoutPhrases
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((term) => term.replaceAll('*', '').trim())
        .where((t) => t.isNotEmpty)
        .toList();

    if (keywords.length <= 1) {
      return []; // Should not happen due to validation, but safety check
    }

    // Get all verses containing any of the keywords
    final allVerses = await BibleDatabase.searchVerses(
        preFilterKeywords: keywords, useOrLogic: true);

    // Apply book filtering
    final filteredVerses = allVerses.where((verse) {
      return BookFilter.verseMatchesFilter(
          verse, _allowedBooks, _allowedChapters);
    }).toList();

    // Group verses by book and chapter
    final chapterGroups = <String, List<Map<String, dynamic>>>{};
    for (final verse in filteredVerses) {
      final key = '${verse['book']}_${verse['chapter']}';
      chapterGroups.putIfAbsent(key, () => []).add(verse);
    }

    final results = <Map<String, dynamic>>[];

    // Process each chapter to find nearby clusters
    for (final chapterVerses in chapterGroups.values) {
      // Sort verses by verse number
      chapterVerses
          .sort((a, b) => (a['verse'] as int).compareTo(b['verse'] as int));

      // Find clusters where all keywords appear within 7 verses
      final clusters = _findNearbyClusters(chapterVerses, keywords);

      for (final cluster in clusters) {
        final startVerse = cluster.first['verse'] as int;
        final endVerse = cluster.last['verse'] as int;
        final book = cluster.first['book'] as String;
        final chapter = cluster.first['chapter'] as int;

        // Get all verses in the continuous range from startVerse to endVerse
        final allChapterVerses = await BibleDatabase.getVerses(book, chapter);
        final versesInRange = allChapterVerses
            .where((v) =>
                (v['verse'] as int) >= startVerse &&
                (v['verse'] as int) <= endVerse)
            .toList();

        // Combine all verse texts for display (remove pilcrow symbols)
        final combinedText = versesInRange.map((v) {
          String verseText = v['text'] as String;
          if (verseText.contains('¶ ')) {
            verseText = verseText.replaceAll('¶ ', '');
          }
          return '${v['verse']} $verseText';
        }).join('\n');

        results.add({
          'book': book,
          'chapter': chapter,
          'startVerse': startVerse,
          'endVerse': endVerse,
          'verses': versesInRange,
          'text': combinedText,
          'bookLongName': BookNameConverter.shortNameToLongName(book),
        });
      }
    }

    // Sort results in biblical order
    await _buildBookOrderIndex();
    results.sort((a, b) {
      final bookA = _bookIdx(a['book']);
      final bookB = _bookIdx(b['book']);
      if (bookA != bookB) return bookA.compareTo(bookB);
      final chapterA = a['chapter'] as int;
      final chapterB = b['chapter'] as int;
      if (chapterA != chapterB) return chapterA.compareTo(chapterB);
      final startA = a['startVerse'] as int;
      final startB = b['startVerse'] as int;
      return startA.compareTo(startB);
    });

    return results;
  }

  // Find clusters of verses within 7 verses that contain all keywords
  List<List<Map<String, dynamic>>> _findNearbyClusters(
      List<Map<String, dynamic>> chapterVerses, List<String> keywords) {
    final clusters = <List<Map<String, dynamic>>>[];

    for (int i = 0; i < chapterVerses.length; i++) {
      final startVerse = chapterVerses[i];
      final startVerseNum = startVerse['verse'] as int;

      // Look for the farthest verse within 7 verses that helps complete the keyword set
      int bestEndIndex = i;
      Set<String> foundKeywords = _getKeywordsInVerse(startVerse, keywords);

      for (int j = i + 1; j < chapterVerses.length; j++) {
        final currentVerse = chapterVerses[j];
        final currentVerseNum = currentVerse['verse'] as int;

        // If this verse is more than 3 verses away from start, stop looking
        if (currentVerseNum - startVerseNum > 3) {
          break;
        }

        // Add keywords found in this verse
        final newKeywords = _getKeywordsInVerse(currentVerse, keywords);
        foundKeywords.addAll(newKeywords);

        // If we now have all keywords, update best end index
        if (foundKeywords.length == keywords.length) {
          bestEndIndex = j;
        }
      }

      // If we found a complete cluster starting from this verse
      if (foundKeywords.length == keywords.length && bestEndIndex > i) {
        final cluster = chapterVerses.sublist(i, bestEndIndex + 1);

        // Check if this cluster overlaps with any existing cluster
        bool overlaps = false;
        for (final existingCluster in clusters) {
          if (_clustersOverlap(cluster, existingCluster)) {
            overlaps = true;
            break;
          }
        }

        if (!overlaps) {
          clusters.add(cluster);
        }

        // Skip verses that are part of this cluster to avoid duplicates
        i = bestEndIndex;
      }
    }
    return clusters;
  }

  // Get keywords present in a verse
  Set<String> _getKeywordsInVerse(
      Map<String, dynamic> verse, List<String> keywords) {
    final found = <String>{};
    final verseText = _getSearchText(verse['text'] as String, _useRedLetter);

    for (final keyword in keywords) {
      // Use word boundaries for whole word matching if enabled
      final pattern = _useWholeWord
          ? '\\b${RegExp.escape(keyword)}\\b'
          : RegExp.escape(keyword);
      final regex = _createRegExp(pattern, _caseSensitive);

      if (regex.hasMatch(verseText)) {
        found.add(keyword);
      }
    }
    return found;
  }

  // Extract keywords from search input (same logic as _searchVersesNearby)
  List<String> _getKeywordsFromInput(String input) {
    RegExp phraseRegExp = RegExp(r'"([^"]+)"');
    String withoutPhrases = input.replaceAll(phraseRegExp, '').trim();
    final keywords = withoutPhrases
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((term) => term.replaceAll('*', '').trim())
        .where((t) => t.isNotEmpty)
        .toList();
    return keywords;
  }

  // Highlight keywords in nearby search combined text, and also highlight verse numbers and red letters
  TextSpan _highlightNearbyText(BuildContext context, String combinedText,
      List<String> keywords, TextStyle baseStyle) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final verseNumberStyle = baseStyle.copyWith(
      fontSize: baseStyle.fontSize! - 2,
      color: (isDark ? darkPrimaryColor.value : lightPrimaryColor.value)
          .withValues(alpha: 0.5),
      fontWeight: FontWeight.normal,
      height: baseStyle.height,
    );

    // Create regex for keyword highlighting (same as regular search)
    final escapedKeywords = keywords
        .map((k) =>
            _useWholeWord ? '\\b${RegExp.escape(k)}\\b' : RegExp.escape(k))
        .toList();
    final pattern = '(${escapedKeywords.join('|')})';
    final keywordRegex = _createRegExp(pattern, _caseSensitive);

    final lines = combinedText.split('\n');
    final spans = <InlineSpan>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final match = RegExp(r'^(\d+)(\s+)(.*)$').firstMatch(line);
      if (match != null) {
        final number = match.group(1)!;
        final space = match.group(2)!;
        final verseText = match.group(3)!;

        // Add verse number with special styling
        spans.add(TextSpan(text: number, style: verseNumberStyle));
        spans.add(TextSpan(text: space, style: baseStyle));

        // Parse verse text for red letters, then apply keyword highlighting
        final parsedVerseSpan =
            VerseTextParser.parseVerseText(verseText, baseStyle);
        final highlightedVerseSpan = _highlightParsedSpan(
            parsedVerseSpan, keywordRegex, context,
            redLetterOnly: false);
        spans.add(highlightedVerseSpan);
      } else {
        // No verse number pattern, highlight keywords and handle red letters
        final parsedSpan = VerseTextParser.parseVerseText(line, baseStyle);
        final highlightedSpan = _highlightParsedSpan(
            parsedSpan, keywordRegex, context,
            redLetterOnly: false);
        spans.add(highlightedSpan);
      }

      // Add newline if not the last line
      if (i < lines.length - 1) {
        spans.add(TextSpan(text: '\n', style: baseStyle));
      }
    }

    return TextSpan(children: spans);
  }

  // Check if two clusters overlap
  bool _clustersOverlap(List<Map<String, dynamic>> cluster1,
      List<Map<String, dynamic>> cluster2) {
    final start1 = cluster1.first['verse'] as int;
    final end1 = cluster1.last['verse'] as int;
    final start2 = cluster2.first['verse'] as int;
    final end2 = cluster2.last['verse'] as int;

    return !(end1 < start2 || end2 < start1);
  }

  Future<List<Map<String, dynamic>>> _searchVersesOrdered(List<String> keywords,
      RegExp searchRegex, List<String> escapedTerms, String input) async {
    // Special handling for multi-term searches (except nearby): use AND logic
    if (escapedTerms.length > 1 && !_useNearby) {
      final results = await BibleDatabase.getAllVerses();
      await _buildBookOrderIndex();

      List<Map<String, dynamic>> filteredResults = results.where((verse) {
        String searchText =
            _getSearchText(verse['text'] as String, _useRedLetter);

        // Check that all terms match (with word boundaries only if whole word is enabled)
        return escapedTerms.every((term) {
          final pattern = _useWholeWord ? '\\b$term\\b' : term;
          final regex = _createRegExp(pattern, _caseSensitive);
          return regex.hasMatch(searchText);
        });
      }).where((verse) {
        // Apply book filtering after text search
        return BookFilter.verseMatchesFilter(
            verse, _allowedBooks, _allowedChapters);
      }).toList();

      filteredResults = filteredResults
          .map((result) => {
                ...result,
                'bookLongName': BookNameConverter.shortNameToLongName(
                    result['book'] as String),
              })
          .toList();

      _sortResultsInBibleOrder(filteredResults);
      return filteredResults;
    } else {
      // Normal logic: OR logic for regular searches
      // For wildcard searches (containing *), skip database prefiltering to avoid false negatives
      final hasWildcards = input.contains('*');
      final results = keywords.isEmpty || hasWildcards
          ? await BibleDatabase.getAllVerses()
          : await BibleDatabase.searchVerses(
              preFilterKeywords: keywords, caseSensitive: _caseSensitive);

      await _buildBookOrderIndex();

      List<Map<String, dynamic>> filteredResults = results.where((verse) {
        String searchText =
            _getSearchText(verse['text'] as String, _useRedLetter);
        return searchRegex.hasMatch(searchText);
      }).where((verse) {
        // Apply book filtering after text search
        return BookFilter.verseMatchesFilter(
            verse, _allowedBooks, _allowedChapters);
      }).toList();

      filteredResults = filteredResults
          .map((result) => {
                ...result,
                'bookLongName': BookNameConverter.shortNameToLongName(
                    result['book'] as String),
              })
          .toList();

      _sortResultsInBibleOrder(filteredResults);
      return filteredResults;
    }
  }

  Map<String, dynamic> _buildSearchPattern(
      bool useRegex, String input, bool useWholeWord) {
    if (useRegex) {
      RegExp searchRegex = _createRegExp(input, _caseSensitive);

      // For whole word, assume user includes \b in regex if needed
      return {
        'keywords': <String>[],
        'regex': searchRegex,
        'escapedTerms': <String>[]
      };
    } else {
      // parse phrases and words
      RegExp phraseRegExp = RegExp(r'"([^"]+)"');
      final phrases = phraseRegExp
          .allMatches(input)
          .map((m) => m.group(1)!)
          .where((p) => p.isNotEmpty)
          .toList();
      String queryWithoutPhrases = input.replaceAll(phraseRegExp, '').trim();
      final originalWords = queryWithoutPhrases
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();
      final allTerms = [...phrases, ...originalWords];
      if (allTerms.isEmpty) {
        return {
          'keywords': [],
          'regex': _createRegExp('.*', _caseSensitive),
          'escapedTerms': <String>[]
        };
      }

      // For keywords, remove * for broad LIKE queries
      List<String> keywords = allTerms
          .map((term) => term.replaceAll('*', '').trim())
          .where((t) => t.isNotEmpty)
          .toList();

      // Treat * as [A-Za-z]*
      List<String> escapedTerms = allTerms.map((term) {
        String escaped = RegExp.escape(term);
        escaped = escaped.replaceAll('\\*', '[A-Za-z]*');
        return escaped;
      }).toList();

      // Only use word boundaries when whole word search is enabled
      String pattern;
      if (useWholeWord) {
        pattern = '\\b(${escapedTerms.join('|')})\\b';
      } else {
        pattern = '(${escapedTerms.join('|')})';
      }
      return {
        'keywords': keywords,
        'regex': _createRegExp(pattern, _caseSensitive),
        'escapedTerms': escapedTerms
      };
    }
  }
  // --- END: Ensure results are in DB/Biblical order ---

  @override
  void initState() {
    super.initState();

    // Initialize controllers
    _customRangeController = TextEditingController(text: _customBookFilter);

    // Add a listener to the focus node to show/hide the on-screen keyboard.
    //_searchFocusNode.addListener(_onFocusChange);

    _restoreSearchState();
    _resultsScrollController.addListener(_saveScrollOffset);

    // Debug: dump semantics tree after TextField gets focus
    // if (kDebugMode) {
    //   WidgetsBinding.instance.addPostFrameCallback((_) {
    //     Future.delayed(const Duration(milliseconds: 500), () {
    //       debugDumpSemanticsTree();
    //     });
    //   });
    // }
  }

  @override
  void dispose() {
    _searchButtonFocusNode.dispose();
    //_isDisposing = true; // Set flag to prevent platform channel calls during disposal
    _saveLastSearchOnExit(); // Save search term only if different from saved one
    _controller.dispose();
    _customRangeController.dispose();
    _resultsScrollController.removeListener(_saveScrollOffset);
    _resultsScrollController.dispose();
    // Clean up the focus node listener.
    //_searchFocusNode.removeListener(_onFocusChange);
    //_searchFocusNode.dispose();
    //_keyboardChannel.setMethodCallHandler(null);
    _onSearchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _restoreSearchState() async {
    await _loadSearchOptions();
    await _loadLastSearch();
    await _loadScrollOffset();
  }

  /// Calls the native method channel to show/hide the keyboard on Windows.
  /*
  void _onFocusChange() {
    // Don't make platform channel calls if we're being disposed
    if (_isDisposing || !mounted) return;

    // This logic is specific to the Windows platform.
    if (!kIsWeb && Platform.isWindows) {
      if (_searchFocusNode.hasFocus) {
        // Use timeout to prevent hanging platform channel calls
        Future<void>(() async {
          if (_isDisposing || !mounted) return;
          try {
            await _keyboardChannel.invokeMethod('showKeyboard').timeout(const Duration(seconds: 1));
          } catch (e) {
            // Handle platform channel errors gracefully - platform may not be available
            // This prevents memory leaks from unanswered platform messages
            if (kDebugMode) debugPrint('_onFocusChange exception: $e');
          }
        });
      } else {
        // Use timeout to prevent hanging platform channel calls
        Future<void>(() async {
          if (_isDisposing || !mounted) return;
          try {
            await _keyboardChannel.invokeMethod('hideKeyboard').timeout(const Duration(seconds: 1));
          } catch (error) {
            // Handle platform channel errors gracefully - platform may not be available
            // This prevents memory leaks from unanswered platform messages
          }
        });
      }
    }
  }
  */

  Future<void> _loadSearchOptions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _useRegex = prefs.getBool(_regexKey) ?? false;
        _useNearby = prefs.getBool(_nearbyKey) ?? false;
        _useWholeWord = prefs.getBool(_wholeWordKey) ?? false;
        _useRedLetter = prefs.getBool(_redLetterKey) ?? false;
        _caseSensitive = prefs.getBool(_caseSensitiveKey) ?? false;
        _bookFilterType = prefs.getString(_bookFilterTypeKey) ?? 'All Books';
        _customBookFilter = prefs.getString(_bookFilterCustomKey) ?? '';
        // Update the text controller to reflect loaded custom range
        _customRangeController.text = _customBookFilter;
      });
      // Update parsed filter state
      await _updateBookFilter();
    } catch (e) {
      // If error, keep defaults
      await _updateBookFilter();
    }
  }

  Future<void> _persistSearchState({String? searchTerm}) async {
    final prefs = await SharedPreferences.getInstance();
    final currentSearchTerm = searchTerm ?? _controller.text;

    await prefs.setBool(_regexKey, _useRegex);
    await prefs.setBool(_nearbyKey, _useNearby);
    await prefs.setBool(_wholeWordKey, _useWholeWord);
    await prefs.setBool(_redLetterKey, _useRedLetter);
    await prefs.setBool(_caseSensitiveKey, _caseSensitive);
    await prefs.setString(_bookFilterTypeKey, _bookFilterType);
    await prefs.setString(_bookFilterCustomKey, _customBookFilter);

    await prefs.setString('lastSearchTerm', currentSearchTerm);
    await prefs.setBool('lastSearchUseRegex', _useRegex);
    await prefs.setBool('lastSearchUseNearby', _useNearby);
    await prefs.setBool('lastSearchUseWholeWord', _useWholeWord);
    await prefs.setBool('lastSearchRedOnly', _useRedLetter);
    await prefs.setBool('lastSearchCaseSensitive', _caseSensitive);
    await prefs.setString('lastSearchBookFilterType', _bookFilterType);
    await prefs.setString('lastSearchCustomBookFilter', _customBookFilter);
  }

  Future<void> _saveSearchOptions() async {
    await _persistSearchState();
  }

  // Update the parsed book filter state based on current filter type and custom input
  Future<void> _updateBookFilter() async {
    final result = await BookFilter.parseCustomRange(_customBookFilter);
    setState(() {
      if (_bookFilterType == 'Custom Range') {
        if (result.isSuccess) {
          _allowedBooks = result.books;
          _allowedChapters = result.chapters;
          _customRangeError = null; // Clear any previous error
        } else {
          _customRangeError = result.error;
          _allowedBooks = [];
          _allowedChapters = {};
        }
      } else {
        // Use predefined category
        _allowedBooks = BookFilter.predefinedCategories[_bookFilterType] ?? [];
        _allowedChapters = {};
        _customRangeError =
            null; // Clear error when switching away from Custom Range
      }
    });
  }

  Future<void> _loadLastSearch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSearch = prefs.getString('lastSearchTerm');

      if (lastSearch == null || lastSearch.trim().isEmpty || lastSearch == '') {
        await prefs.setDouble('searchScrollOffset', 0.0);
        setState(() {
          _controller.text = '';
          _searchResults = [];
          _currentRegex = null;
          _isNearbySearchActive = false;
        });
        // Only focus the text field when there's no saved search term
        //WidgetsBinding.instance.addPostFrameCallback((_) {
        //  _searchFocusNode.requestFocus();
        //});
        return;
      }

      // Load last search options and override the UI state with them
      final lastSearchUseRegex = prefs.containsKey(_regexKey)
          ? _useRegex
          : (prefs.getBool('lastSearchUseRegex') ?? false);
      final lastSearchUseNearby = prefs.containsKey(_nearbyKey)
          ? _useNearby
          : (prefs.getBool('lastSearchUseNearby') ?? false);
      final lastSearchUseWholeWord = prefs.containsKey(_wholeWordKey)
          ? _useWholeWord
          : (prefs.getBool('lastSearchUseWholeWord') ?? false);
      final lastSearchUseRedLetter = prefs.containsKey(_redLetterKey)
          ? _useRedLetter
          : (prefs.getBool('lastSearchRedOnly') ?? false);
      final lastSearchCaseSensitive = prefs.containsKey(_caseSensitiveKey)
          ? _caseSensitive
          : (prefs.getBool('lastSearchCaseSensitive') ?? false);
      final lastSearchBookFilterType = prefs.containsKey(_bookFilterTypeKey)
          ? _bookFilterType
          : (prefs.getString('lastSearchBookFilterType') ?? 'All Books');
      final lastSearchCustomBookFilter = prefs.containsKey(_bookFilterCustomKey)
          ? _customBookFilter
          : (prefs.getString('lastSearchCustomBookFilter') ?? '');
      final restoredSearchText =
          lastSearchUseRegex ? lastSearch : lastSearch.trim();

      setState(() {
        // Override search options with last search's options
        _useRegex = lastSearchUseRegex;
        _useNearby = lastSearchUseNearby;
        _useWholeWord = lastSearchUseWholeWord;
        _useRedLetter = lastSearchUseRedLetter;
        _caseSensitive = lastSearchCaseSensitive;
        _bookFilterType = lastSearchBookFilterType;
        _customBookFilter = lastSearchCustomBookFilter;
        _controller.text = lastSearch;
        _isSearching =
            true; // Set searching state immediately to show "Searching..." during load
        _isNearbySearchActive = false;
        _currentRegex = null;
      });

      // Update book filter controller and parsed state
      _customRangeController.text = _customBookFilter;
      await _updateBookFilter();

      // Skip loading results for invalid custom range (parsing error)
      if (_bookFilterType == 'Custom Range' &&
          (_customRangeError != null || _customBookFilter.isEmpty)) {
        setState(() {
          _searchResults = [];
          _setTotals(0, 0);
          _currentRegex = null;
          _isSearching = false;
          _isNearbySearchActive = false;
        });
        return;
      }

      if (_useNearby && !_isValidNearbyInput(restoredSearchText)) {
        setState(() {
          _searchResults = [];
          _setTotals(0, 0);
          _currentRegex = null;
          _isSearching = false;
          _isNearbySearchActive = false;
        });
        return;
      }

      // Load the last search results - use appropriate method based on search type
      List<Map<String, dynamic>> results;
      if (_useNearby) {
        // Perform nearby search
        results = await _searchVersesNearby(restoredSearchText);
        _isNearbySearchActive = true;

        // For nearby search, calculate totals differently
        int matchCount = 0;
        int verseCount = 0;
        final keywords = _getKeywordsFromInput(restoredSearchText);
        final escapedKeywords = keywords
            .map((k) =>
                _useWholeWord ? '\\b${RegExp.escape(k)}\\b' : RegExp.escape(k))
            .toList();
        final pattern = '(${escapedKeywords.join('|')})';
        final regex = _createRegExp(pattern, _caseSensitive);

        for (var result in results) {
          if (result.containsKey('verses')) {
            for (var verse in result['verses'] as List) {
              String text =
                  _getSearchText(verse['text'] as String, _useRedLetter);
              if (regex.hasMatch(text)) {
                verseCount++;
              }
            }
          }
          // Count keyword occurrences in the combined text
          final combinedText = result['text'] as String;
          matchCount += regex.allMatches(combinedText).length;
        }

        setState(() {
          _searchResults = results;
          _setTotals(matchCount, verseCount);
          _currentRegex = null; // Nearby search doesn't use regex highlighting
          _isSearching = false;
        });
      } else {
        // Perform regular search
        final patternData =
            _buildSearchPattern(_useRegex, restoredSearchText, _useWholeWord);
        final keywords = patternData['keywords'] as List<String>;
        final searchRegex = patternData['regex'] as RegExp;

        // Get all results at once
        results = await _searchVersesOrdered(keywords, searchRegex,
            patternData['escapedTerms'], restoredSearchText);

        // Calculate match and verse counts
        int verseCount = results.length;
        int matchCount = 0;
        for (var verse in results) {
          String text = _getSearchText(verse['text'] as String, _useRedLetter);
          matchCount += searchRegex.allMatches(text).length;
        }

        setState(() {
          _searchResults = results;
          _setTotals(matchCount, verseCount);
          _currentRegex = searchRegex;
          _isSearching = false;
        });
      }
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('searchScrollOffset', 0.0);
      setState(() {
        _controller.text = '';
        _searchResults = [];
        _currentRegex = null;
        _isNearbySearchActive = false;
        _isSearching = false;
      });
    }
  }

  Future<void> _saveLastSearch() async {
    await _persistSearchState();
  }

  Future<void> _saveLastSearchOnExit() async {
    try {
      await _persistSearchState();
    } catch (e) {
      ErrorHandler.logError(
        e,
        customMessage: '_saveLsatSearchOnExit exception',
        context: {'class': 'SearchScreen', 'method': '_saveLastSearchOnExit'},
      );
    }
  }

  Future<void> _loadScrollOffset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final offset = prefs.getDouble('searchScrollOffset');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_resultsScrollController.hasClients &&
            offset != null &&
            offset >= 0.0) {
          _resultsScrollController.jumpTo(offset);
        } else if (_resultsScrollController.hasClients) {
          _resultsScrollController.jumpTo(0.0);
        }
      });
    } catch (e) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_resultsScrollController.hasClients) {
          _resultsScrollController.jumpTo(0.0);
        }
      });
    }
  }

  Future<void> _saveScrollOffset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(
        'searchScrollOffset', _resultsScrollController.offset);
  }

  Future<void> _saveSearchHistory(String query, String? scope) async {
    try {
      // Check if this exact search (same query + all options) already exists
      final existingEntry = await SearchDatabase.getSearchHistoryByParams(
        query: query,
        useRegex: _useRegex,
        useNearby: _isNearbySearchActive,
        useWholeWord: _useWholeWord,
        useRedLetter: _useRedLetter,
        caseSensitive: _caseSensitive,
        bookFilterType: _bookFilterType,
        customBookFilter: _customBookFilter,
      );

      if (existingEntry != null) {
        if (mounted) {
          showStyledSnackBar(context, 'Saved Search Already Exists');
        }
        return; // Don't create duplicate - leave existing entry untouched
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      await SearchDatabase.addSearchHistory(
        query,
        _useRegex,
        _isNearbySearchActive,
        _useWholeWord,
        _useRedLetter,
        _caseSensitive,
        _bookFilterType,
        _customBookFilter,
        timestamp,
      );

      // Notify the search history dialog to refresh
      LocalDataChangeNotifier.notifySearchHistoryChanged();

      if (mounted) {
        showStyledSnackBar(context, 'Search saved');
      }
    } catch (e) {
      //
    }
  }

  // Reset results scroll position and stored offset to top for new searches.
  Future<void> _resetResultsScrollToTop() async {
    try {
      if (_resultsScrollController.hasClients) {
        _resultsScrollController.jumpTo(0.0);
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_resultsScrollController.hasClients) {
            _resultsScrollController.jumpTo(0.0);
          }
        });
      }
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('searchScrollOffset', 0.0);
    } catch (_) {}
  }

  Color _getHighlightColor(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark
        ? darkHighlightColor.value
        : lightHighlightColor.value;
  }

  Future<void> _onSearch() async {
    // Check for invalid custom range
    if (_bookFilterType == 'Custom Range' && _customRangeError != null) {
      // ErrorHandler.logError(
      //   'Invalid Custom Range',
      //   context: {
      //     'class': 'SearchScreen',
      //     'method': '_onSearch',
      //     'error': 'Invalid custom range'
      //   },
      // );
      return;
    }

    // Check for empty custom range
    if (_bookFilterType == 'Custom Range' && _customBookFilter.isEmpty) {
      // ErrorHandler.logError(
      //   'Custom range is empty',
      //   context: {
      //     'class': 'SearchScreen',
      //     'method': '_onSearch',
      //     'error': 'Custom range is empty'
      //   },
      // );
      return;
    }

    // Validate input - prevent empty searches that would cause freezing
    final searchText = _useRegex ? _controller.text : _controller.text.trim();
    if (searchText.isEmpty) {
      setState(() {
        _searchResults = [];
        _setTotals(0, 0);
      });
      return;
    }

    // Additional validation - check if search is too short
    //if (searchText.length < 2) {
    //  showStyledSnackBar(context, 'Search too short', isError: true);
    //  return;
    //}

    // Additional validation - check if 2-character search contains special characters
    //if (searchText.length == 2 && searchText.contains('*')) {
    //  showStyledSnackBar(context, 'Search too short');
    //  return;
    //}

    // Check if nearby search is enabled but input is invalid
    if (_useNearby && !_isValidNearbyInput(searchText)) {
      _showNearbyWarning(searchText);
      return;
    }

    // Reset nearby search state
    _isNearbySearchActive = false;

    // Show loading indicator
    setState(() {
      _isSearching = true;
      _searchResults = [];
      _setTotals(0, 0);
    });

    // Ensure results start at the top for each new search
    await _resetResultsScrollToTop();

    try {
      // Check if we should perform nearby search
      if (_isValidNearbyInput(searchText)) {
        // Perform nearby search
        final results = await _searchVersesNearby(searchText);
        _isNearbySearchActive = true;

        // For nearby search, calculate totals differently
        int matchCount = 0;
        int verseCount = 0;
        final keywords = _getKeywordsFromInput(searchText);
        final escapedKeywords = keywords
            .map((k) =>
                _useWholeWord ? '\\b${RegExp.escape(k)}\\b' : RegExp.escape(k))
            .toList();
        final pattern = '(${escapedKeywords.join('|')})';
        final regex = _createRegExp(pattern, _caseSensitive);

        for (var result in results) {
          if (result.containsKey('verses')) {
            for (var verse in result['verses'] as List) {
              String text =
                  _getSearchText(verse['text'] as String, _useRedLetter);
              if (regex.hasMatch(text)) {
                verseCount++;
              }
            }
          }
          // Count keyword occurrences in the combined text
          final combinedText = result['text'] as String;
          matchCount += regex.allMatches(combinedText).length;
        }

        setState(() {
          _searchResults = results;
          _setTotals(matchCount, verseCount);
          _currentRegex = null; // Nearby search doesn't use regex highlighting
          _isSearching = false;
        });
      } else {
        // Perform regular search
        final patternData =
            _buildSearchPattern(_useRegex, searchText, _useWholeWord);
        final keywords = patternData['keywords'] as List<String>;
        final searchRegex = patternData['regex'] as RegExp;

        // Get all results at once
        final results = await _searchVersesOrdered(
            keywords, searchRegex, patternData['escapedTerms'], searchText);

        // Calculate match and verse counts
        int verseCount = results.length;
        int matchCount = 0;
        for (var verse in results) {
          String text = _getSearchText(verse['text'] as String, _useRedLetter);
          matchCount += searchRegex.allMatches(text).length;
        }

        // Clear cache when new search results are loaded
        _clearHighlightCache();

        setState(() {
          _searchResults = results;
          _setTotals(matchCount, verseCount);
          _currentRegex = searchRegex;
          _isSearching = false;
        });

        // Show warning if nearby was enabled but criteria not met
        if (_useNearby && !_isNearbySearchActive) {
          _showNearbyWarning(searchText);
        }
      }

      await _saveLastSearch();

      // TODO: update this if web builds on windows have the OSK bug
      // Don't bother to use this bug-workaround if we aren't on windows
      // and we aren't in tablet mode because it can be frustrating having
      // the focus removed when we aren't done typing. when in tablet mode
      // we have to deal with it because the OSK bug is far more frustrating once
      // it is triggered (it opens the OSK on ANY UI interaction)
      //
      // Check that the device is touch capable and has a physical keyboard to attempt
      // to avoid triggering this when a 2-in-1 is in laptop mode (keyboard attached)
      // TODO: .isKeyboardAttached might not work as expected
      //
      if (!kIsWeb &&
          (Platform.isWindows &&
              TabletModeService().isTablet &&
              await TabletModeDetector.hasTouchScreen() &&
              await TabletModeDetector.isKeyboardAttached())) {
        // After a delay of 1s, check if any input was recieved in the last 1s, if not
        // then force the focus away to prevent the windows OSK bug
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (!_isSearching &&
              DateTime.now().difference(_lastInputTime).inMilliseconds >=
                  1000) {
            if (_searchResults.isNotEmpty) {
              // Request focus on the Search button this is required
              // to circumvent Windows OSK bug. Manually pushing the button
              // does not remove focus from the TextField which is evidently part
              // of the bug in that the focus becomes 'stuck' to the TextField and
              // then ANY subsequent UI interaction triggers the OSK popup
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _searchButtonFocusNode.canRequestFocus) {
                  _searchButtonFocusNode.requestFocus();
                }
              });
            }
          }
        });
      }
    } catch (e) {
      setState(() {
        _searchResults = [];
        _setTotals(0, 0);
        _isSearching = false;
      });
    }
  }

  TextSpan _highlightParsedSpan(
      TextSpan span, RegExp regex, BuildContext context,
      {bool redLetterOnly = false}) {
    final color = _getHighlightColor(context);

    // Performance optimization: if no children and no text, return as-is
    if (span.children == null && (span.text == null || span.text!.isEmpty)) {
      return span;
    }

    // Handle spans with children (from VerseTextParser)
    if (span.children != null && span.children!.isNotEmpty) {
      return TextSpan(
        style: span.style,
        children: span.children!.map((child) {
          if (child is TextSpan) {
            return _highlightParsedSpan(child, regex, context,
                redLetterOnly: redLetterOnly);
          }
          return child;
        }).toList(),
      );
    }

    // Handle simple text spans (most common case after optimization)
    if (span.text != null && span.text!.isNotEmpty) {
      if (redLetterOnly && span.style?.color != Colors.red) {
        return span;
      }

      final text = span.text!;
      final spans = <InlineSpan>[];
      int start = 0;

      // Performance optimization: early exit if no matches
      if (!regex.hasMatch(text)) {
        return span;
      }

      for (final match in regex.allMatches(text)) {
        if (match.start > start) {
          spans.add(TextSpan(
              text: text.substring(start, match.start), style: span.style));
        }
        spans.add(
          TextSpan(
            text: text.substring(match.start, match.end),
            style: (span.style ?? TextStyle())
                .copyWith(backgroundColor: color, fontWeight: FontWeight.bold),
          ),
        );
        start = match.end;
      }
      if (start < text.length) {
        spans.add(TextSpan(text: text.substring(start), style: span.style));
      }
      return TextSpan(style: span.style, children: spans);
    }

    return span;
  }

  // Show help dialog
  void _showHelpDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? darkBackgroundColor.value : lightBackgroundColor.value;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        insetPadding: EdgeInsets.all(0.0),
        contentPadding: EdgeInsets.all(16.0),
        actionsPadding: EdgeInsets.all(0.0),
        titlePadding: EdgeInsets.all(0.0),
        backgroundColor: bgColor,
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UnbreakableText('Regular search',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context))),
              const SizedBox(height: 8),
              //UnbreakableText(
              //  '• The default search enables partial word',
              //  style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context)),
              //),
              UnbreakableText(
                '• Exact phrases must be surrounded by quotes (eg. "love one another").',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context)),
              ),
              //UnbreakableText(
              //  '• Enable the whole word option to match complete words only (eg. "love" won\'t match "loved" or "lovely").',
              //  style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context)),
              //),
              UnbreakableText(
                '• The asterisk is a wild card and can be used with one or more words (eg. love* will match love, lovest, loved, etc.).',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context)),
              ),
              UnbreakableText(
                '• Check the search options menu for more ways to customize your searches.',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context)),
              ),
              UnbreakableText(
                '• You can mix and match the various search options but some of them are mututally exclusive.',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context)),
              ),
              const SizedBox(height: 16),
              UnbreakableText(
                  'Nearby search (must be enabled in search options)',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context))),
              const SizedBox(height: 8),
              UnbreakableText(
                '• Finds passages where all search words appear within 3 verses of each other.',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context)),
              ),
              UnbreakableText(
                '• Requires more than one word (does not support quotes or the asterisk).',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context)),
              ),
              UnbreakableText(
                '• Example: "graven carved" results: Judges 18:17-20, 2 Chronicles 33:19-22, 2 Chronicles 34:7.',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context)),
              ),
              const SizedBox(height: 16),
              UnbreakableText(
                  'Regular expression (must be enabled in search options)',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context))),
              const SizedBox(height: 8),
              UnbreakableText(
                '• Supports ECMAScript 2018 regular expressions with Unicode properties.',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context)),
              ),
              UnbreakableText(
                '• The caret symbol ^ matches the start of any line (eg. "^My" matches any verse that begins with My or my - since there are no verses that begin with a lowercase letter the case-sensitive toggle won\'t change the results).',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context)),
              ),
              UnbreakableText(
                '• The dollar symbol \$ matches the end of a line (eg. "!\$" matches any verse that ends with an exclamation mark).',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context)),
              ),
              UnbreakableText(
                '• The period character . matches any single character (eg. "S.chem"). Note that you need to add a quantifier if you want the period to match more than one character (eg. "S.+chem").',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context)),
              ),
              UnbreakableText(
                '• \\s matches any white-space character (eg. " ").',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context)),
              ),
              UnbreakableText(
                '• \\w is shorthand for the word character class [a-zA-Z0-9_] which is the same as any lower or uppercase character, any digit, and the underscore symbol.',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context)),
              ),
              UnbreakableText(
                '• Parenthesis can be used as a grouping construct and when combined with the alternation operator | they can be used together to match close variations of the same word (eg. "S(y|i|he)chem" will match "Sichem", "Shechem", and "Sychem"). Note that in grouping constructs the characters must appear in the order they are given to match (the same as an AND operator between each character).',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context)),
              ),
              UnbreakableText(
                '• Characters classes match any one of the characters in the set (eg. "[abc]" will match any ONE of a, b, or c which is the same as an OR operator between each character; "[abc]+" will match one or more of any character in the set; "[a-z]+" will match any one or more characters in the range a to z; "[a-z]+thite" will match Hamathite, Kohathite, Korathite, Gazathite, Ashdothite, and more).',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context)),
              ),
              UnbreakableText(
                '• The negation operator can be used inside of character classes to negate characters or ranges from matching (eg. "\\b[^gG]od\\b" will match any three-letter word that does not begin with "g" or "G" and ends with "od").',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context)),
              ),
              UnbreakableText(
                '• Positive/negative lookahead (?=)/(?!) and positive/negative lookbehinds (?<=)/(?<!) are fully supported (eg. "(?<!dark)ness" will match any word that ends with "ness" but does not begin with "dark").',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context)),
              ),
              UnbreakableText(
                '• Characters classes and the grouping construct can be used together (eg. "S([yi]|he)chem" will match "Sichem", "Shechem", and "Sychem").',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context)),
              ),
              UnbreakableText(
                '• Quantifiers can appear after any character, character class/set, or grouping construct to specify quantities. Quantifiers: * = zero or more, + = one or more, ? = zero or one, {n} = exactly n times, {n,} = n or more times, {n,m} = between n and m times inclusive. Note that quantifiers with no limit (* and +) are inherently greedy (they match as many as possible). Add a ? after any quantifier to make it lazy (match as few as possible). The range quantifier can be used to specify a precise amount or range that you are looking for "a{2}" will match sequences of exactly two a\'s (Naamah, Canaan, Balaam).',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context)),
              ),
              UnbreakableText(
                '• Unicode properties: \\p{P} = punctuation, \\p{L} = any letter, \\p{N} = any number, \\p{S} = any symbol, \\p{Z} = separators (spaces, line/paragraph breaks), \\p{M} = marks (accents, combining characters)',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context)),
              ),
              UnbreakableText(
                '• Example: "^Verily" (with Red Letter enabled) matches any sentence that Jesus spoke that begins with "Verily".',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context)),
              ),
              UnbreakableText(
                '• Example: "\\b(?!\\bwrit)\\w*ten\\b" will match all words that end with "ten" but do not begin with "writ".',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context)),
              ),
              UnbreakableText(
                '• Example: "(!|\\?)\$" matches any verse that ends with an exclamation mark or a question mark. Take note that if the character you are looking for is also a quantifier it needs to be escaped to become literal (by adding a backslash \\ before it).',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context)),
              ),
              UnbreakableText(
                '• Example: "horeb|sinai|mount of God|Sina" matches any verse that contains the text horeb, sinai, "mount of God", and Sina.',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              child: Text(
                'Close',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context)),
              ),
              onPressed: () => Navigator.pop(context))
        ],
      ),
    );
  }

  // Show action menu for search results (similar to bible screen's _showAddNoteMenu)
  void _showSearchResultActionMenu(
      BuildContext context, Map<String, dynamic> result) {
    final book = result['book'] as String;
    final chapter = result['chapter'] as int?;

    // Check if this is a nearby search result
    final isNearbyResult =
        result.containsKey('startVerse') && result.containsKey('endVerse');

    final verseNum =
        isNearbyResult ? result['startVerse'] as int? : result['verse'] as int?;
    final endVerseNum = isNearbyResult ? result['endVerse'] as int? : null;
    final rawVerseText = result['text'] as String? ?? '';

    // Filter out red letter tags <r> and </r>
    final redLetterRegex = RegExp(r'</?r>');
    final cleanVerseText =
        rawVerseText.replaceAll(redLetterRegex, '').replaceAll('¶ ', '');

    // Format for clipboard (same format as bible screen)
    final bookName = result['bookLongName'] as String;
    final verseRef = isNearbyResult
        ? '$chapter:$verseNum-$endVerseNum'
        : '$chapter:$verseNum';
    final copyText = '$bookName $verseRef\n$cleanVerseText';

    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Center(
                child: Text(
              'Goto Verse',
              style: TextStyle(
                  fontFamily: fontFamilyNotifier.value,
                  fontSize: uiFontSize + 10,
                  color: getAdaptiveTextColor(context)),
            )),
            onTap: () {
              Navigator.of(context).pop();
              _gotoVerse(book, chapter, verseNum);
            },
          ),
          ListTile(
            title: Center(
                child: Text(
              'Show Context',
              style: TextStyle(
                  fontFamily: fontFamilyNotifier.value,
                  fontSize: uiFontSize + 10,
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
              'Copy ${isNearbyResult ? 'Verses $verseNum-$endVerseNum' : 'Verse $verseNum'}',
              style: TextStyle(
                  fontFamily: fontFamilyNotifier.value,
                  fontSize: uiFontSize + 10,
                  color: getAdaptiveTextColor(context)),
            )),
            onTap: () {
              Clipboard.setData(ClipboardData(text: copyText)).then((_) {
                if (!context.mounted) return;
                showStyledSnackBar(context,
                    '${isNearbyResult ? 'Verses' : 'Verse'} copied to clipboard');
                Navigator.of(context).pop();
              });
            },
          ),
        ],
      ),
    );
  }

  // Navigate to verse in the source bible screen
  void _gotoVerse(String? book, int? chapter, int? verse) async {
    if (book == null || chapter == null || verse == null) {
      ErrorHandler.logError(
        '_gotoVerse null return: book:"$book" chapter:"$chapter" verse:"$verse"',
        context: {
          'class': 'SearchScreen',
          'method': '_gotoVerse',
          'book': book,
          'chapter': chapter,
          'verse': verse
        },
      );
      return;
    }

    // Return data to the source bible screen using short book name
    final result = {
      'verseLocation': {
        'book': book, // Use short name for database operations
        'chapter': chapter,
        'verse': verse,
      },
      'targetScreenIndex': widget.sourceScreenIndex ?? 0,
    };

    if (mounted) {
      Navigator.of(context).pop(result);
    }

    // Add verse to history with short book name (database format)
    try {
      await HistoryDatabase.addHistory(
          book, chapter, verse, DateTime.now().millisecondsSinceEpoch, false);
    } catch (e) {
      ErrorHandler.logError(
        e,
        customMessage: '_gotoVerse addHistory exception',
        context: {
          'class': 'SearchScreen',
          'method': '_gotoVerse',
          'book': book,
          'chapter': chapter,
          'verse': verse
        },
      );
    }
  }

  // Open NoteScreen for editing notes in search screen context
  Future<void> _openNoteFromSearch(
      String book, int chapter, int verse, String? existingNote) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => NoteScreen(
                book: book,
                chapter: chapter,
                verse: verse,
                existingNote: existingNote))); // Use provided existing note
  }

  // Show context dialog with chapter dialog
  Future<void> _showContextDialog(
      String? book, int? chapter, int? verseNum) async {
    if (book == null || chapter == null || verseNum == null) return;

    // Convert database book name to display key for ChapterDialog
    final normalizedShortBookName = BookNameConverter.normalizeShortName(book);
    // Create reference text to highlight the target verse
    final fullBookName =
        BookNameConverter.shortNameToLongName(normalizedShortBookName);
    final referenceText = '$fullBookName $chapter:$verseNum';

    // Show ChapterDialog with target verse highlighted
    showDialog(
      context: context,
      builder: (context) => ChapterDialog(
        book: normalizedShortBookName,
        chapter: chapter,
        verse: verseNum, // Focus on the target verse
        referenceText: referenceText, // Highlight the target verse
        onNavigateToVerse: (verse) => _gotoVerse(normalizedShortBookName,
            chapter, verse), // Navigate the bible screen to the verse
        onNoteIconTap: (int verse, String? noteText) => _openNoteFromSearch(
            normalizedShortBookName, chapter, verse, noteText),
        onNoteEditTap: (int verse, String? noteText) => _openNoteFromSearch(
            normalizedShortBookName, chapter, verse, noteText),
        onVerseLink: (link, referenceText) => handleVerseLink(
          context,
          link,
          referenceText,
          navigateToVerse: _gotoVerse,
          onVerseLinkRecursion:
              null, // Infinite recursion enabled by default in handleVerseLink
          onNoteIconTap: _openNoteFromSearch, // so notes work in nested dialogs
          onNoteEditTap: _openNoteFromSearch,
        ),
      ),
    );
  }

  String _formatNumber(int? number) {
    return number.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+($|\D))'),
        (match) => '${match.group(1)},');
  }

  // Update totals
  void _setTotals(int? matches, int? verses) {
    _totalMatches = matches;
    _totalVerses = verses;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                    fontSize: uiFontSize + 2,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context)),
                minFontSize: uiFontSize - 14,
              ))
            : Text(
                '',
                style: TextStyle(color: Colors.transparent),
              ),
        toolbarHeight: 60,
        backgroundColor: barColor,
        actions: [
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
          IconButton(
            icon: Icon(
              Icons.history,
              size: 32,
              color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
              semanticLabel: 'Show Search History Dialog',
            ),
            tooltip: 'Search History',
            color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => SearchHistoryDialog(
                  onUpdateSearchQuery: (searchOptions) {
                    setState(() {
                      _controller.text = searchOptions['query'] as String;
                      _useRegex = searchOptions['useRegex'] as bool;
                      _useNearby = searchOptions['useNearby'] as bool;
                      _useWholeWord = searchOptions['useWholeWord'] as bool;
                      _useRedLetter = searchOptions['useRedLetter'] as bool;
                      _caseSensitive = searchOptions['caseSensitive'] as bool;
                      _bookFilterType =
                          searchOptions['bookFilterType'] as String;
                      _customBookFilter =
                          searchOptions['customBookFilter'] as String;
                      _customRangeController.text = _customBookFilter;
                    });
                    _updateBookFilter();
                    unawaited(_saveSearchOptions());
                    _clearHighlightCache();
                    if (_controller.text.trim().isNotEmpty) {
                      _onSearch();
                    }
                  },
                ),
              );
            },
          ),
          IconButton(
            icon: Icon(
              Icons.manage_search,
              size: 32,
              color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
              semanticLabel: 'Open Strongs Search',
            ),
            tooltip: 'Strongs Search',
            color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
            onPressed: () async {
              final strongsResult = await Navigator.push<Map<String, dynamic>>(
                context,
                MaterialPageRoute(
                  builder: (_) => StrongsSearchScreen(
                    sourceScreenIndex: widget.sourceScreenIndex,
                  ),
                ),
              );

              if (strongsResult != null &&
                  strongsResult.containsKey('verseLocation') &&
                  context.mounted) {
                Navigator.pop(context, strongsResult);
              }
            },
          ),
          IconButton(
            icon: Icon(
              Icons.menu,
              size: 32,
              color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
              semanticLabel: 'Show Search Options Menu',
            ),
            tooltip: 'Search Options',
            color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
        ],
      ),
      endDrawer: Drawer(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? darkBackgroundColor.value
            : lightBackgroundColor.value,
        child: SingleChildScrollView(
            child: Column(
          children: [
            AppBar(
              scrolledUnderElevation: 0,
              iconTheme: IconThemeData(
                size: 32,
                color:
                    isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
              ),
              //title: Text('Search Options', style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily)),
              automaticallyImplyLeading: true,
              toolbarHeight: 60,
              backgroundColor: Theme.of(context).brightness == Brightness.dark
                  ? darkBackgroundColor.value
                  : lightBackgroundColor.value,
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: Text('Regex',
                  style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context))),
              value: _useRegex,
              onChanged: (val) async {
                setState(() {
                  _useRegex = val;
                  if (_useRegex) {
                    _useNearby = false;
                    _useWholeWord = false;
                  }
                });
                await _saveSearchOptions();
                // Clear cache when search options change
                _clearHighlightCache();
                if (_controller.text.trim().isNotEmpty) {
                  _onSearch();
                }
                // Removed Navigator.of(context).pop() - drawer stays open
              },
            ),
            SwitchListTile(
              title: Text('Nearby',
                  style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context))),
              value: _useNearby,
              onChanged: (val) async {
                setState(() {
                  _useNearby = val;
                  if (_useNearby) _useRegex = false;
                });
                await _saveSearchOptions();
                // Clear cache when search options change
                _clearHighlightCache();
                if (_controller.text.trim().isNotEmpty) {
                  _onSearch();
                }
                // Removed Navigator.of(context).pop() - drawer stays open
              },
            ),
            SwitchListTile(
              title: Text('Whole word',
                  style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context))),
              value: _useWholeWord,
              onChanged: (val) async {
                setState(() {
                  _useWholeWord = val;
                  if (_useWholeWord) _useRegex = false;
                });
                await _saveSearchOptions();
                // Clear cache when search options change
                _clearHighlightCache();
                if (_controller.text.trim().isNotEmpty) {
                  _onSearch();
                }
                // Removed Navigator.of(context).pop() - drawer stays open
              },
            ),
            SwitchListTile(
              title: Text('Red letter',
                  style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context))),
              value: _useRedLetter,
              onChanged: (val) async {
                setState(() {
                  _useRedLetter = val;
                });
                await _saveSearchOptions();
                // Clear cache when search options change
                _clearHighlightCache();
                if (_controller.text.trim().isNotEmpty) {
                  _onSearch();
                }
                // Removed Navigator.of(context).pop() - drawer stays open
              },
            ),
            SwitchListTile(
              title: Text('Case-sensitive',
                  style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context))),
              value: _caseSensitive,
              onChanged: (val) async {
                setState(() {
                  _caseSensitive = val;
                });
                await _saveSearchOptions();
                // Clear cache when search options change
                _clearHighlightCache();
                if (_controller.text.trim().isNotEmpty) {
                  _onSearch();
                }
                // Removed Navigator.of(context).pop() - drawer stays open
              },
            ),
            const SizedBox(height: 16),
            Divider(),
            const SizedBox(height: 8),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text(
                'Book Filter',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    fontWeight: FontWeight.normal,
                    color: getAdaptiveTextColor(context)),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: DropdownButton<String>(
                value: _bookFilterType,
                isExpanded: true,
                items: [
                  ...BookFilter.categoryDisplayNames.map((String category) {
                    return DropdownMenuItem<String>(
                      value: category,
                      child: Text(
                        category,
                        style: TextStyle(
                            fontSize: uiFontSize,
                            fontFamily: uiFontFamily,
                            color: getAdaptiveTextColor(context)),
                      ),
                    );
                  }),
                  DropdownMenuItem<String>(
                    value: 'Custom Range',
                    child: Text(
                      'Custom Range',
                      style: TextStyle(
                          fontSize: uiFontSize,
                          fontFamily: uiFontFamily,
                          color: getAdaptiveTextColor(context)),
                    ),
                  ),
                ],
                onChanged: (String? newValue) async {
                  if (newValue != null) {
                    setState(() {
                      _bookFilterType = newValue;
                      // When switching TO Custom Range, ensure controller shows preserved text
                      if (newValue == 'Custom Range') {
                        _customRangeController.text = _customBookFilter;
                      }
                    });
                    _updateBookFilter();
                    await _saveSearchOptions();
                    if (_controller.text.trim().isNotEmpty) {
                      _onSearch();
                    }
                  }
                },
              ),
            ),
            if (_bookFilterType == 'Custom Range')
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0),
                    child: //OnscreenKeyboardTextField(
                        TextField(
                      autofocus: true,
                      maxLength: 100,
                      maxLengthEnforcement: MaxLengthEnforcement.enforced,
                      controller: _customRangeController,
                      decoration: InputDecoration(
                        counter:
                            SizedBox.shrink(), // Hide the counter eg. 0/100
                        hintText: '',
                        hintStyle: TextStyle(
                            fontSize: uiFontSize - 4, fontFamily: uiFontFamily),
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        suffixIcon: IconButton(
                          icon: Icon(
                            Icons.clear,
                            color: isDark
                                ? darkPrimaryColor.value
                                : lightPrimaryColor.value,
                            semanticLabel: 'Clear Custom Range',
                          ),
                          onPressed: () async {
                            setState(() {
                              _customRangeController.clear();
                              _customBookFilter = ''; // Reset underlying state
                              _customRangeError =
                                  null; // Clear any lingering error
                            });
                            await _updateBookFilter();
                            await _saveSearchOptions();
                          },
                          iconSize: 32,
                        ),
                        errorText: _customRangeError,
                        errorMaxLines: 3,
                        errorStyle: TextStyle(
                          fontSize: uiFontSize - 4,
                          fontFamily: uiFontFamily,
                          color: Colors.red,
                        ),
                      ),
                      style: TextStyle(
                          fontSize: uiFontSize,
                          fontFamily: uiFontFamily,
                          color: getAdaptiveTextColor(context)),
                      onChanged: (value) {
                        _customBookFilter = value;
                        _updateBookFilter();
                        unawaited(_saveSearchOptions());
                      },
                      onSubmitted: (_) async {
                        await _saveSearchOptions();
                        if (_controller.text.trim().isNotEmpty) {
                          _onSearch();
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: ElevatedButton(
                      onPressed: () async {
                        await _saveSearchOptions();
                        if (_controller.text.trim().isNotEmpty) {
                          _onSearch();
                        }
                      },
                      child: Text('Apply',
                          style: TextStyle(
                              fontSize: uiFontSize,
                              fontFamily: uiFontFamily,
                              color: getAdaptiveTextColor(context,
                                  usePrimaryColor: true))),
                    ),
                  ),
                  if (_bookFilterType == 'Custom Range') ...[
                    const SizedBox(height: 16),
                    ListTile(
                        subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                          Text('Custom range help:',
                              style: TextStyle(
                                  fontSize: uiFontSize,
                                  fontFamily: uiFontFamily,
                                  color: getAdaptiveTextColor(context))),
                          const SizedBox(height: 16),
                          Text(
                              '• Both short and long book names are supported.',
                              style: TextStyle(
                                  fontSize: uiFontSize,
                                  fontFamily: uiFontFamily,
                                  color: getAdaptiveTextColor(context))),
                          const SizedBox(height: 8),
                          Text(
                              '• Book and chapter ranges must be separated by a dash and can optionally include chapter numbers\n(eg. Mat 22 - John).',
                              style: TextStyle(
                                  fontSize: uiFontSize,
                                  fontFamily: uiFontFamily,
                                  color: getAdaptiveTextColor(context))),
                          const SizedBox(height: 8),
                          Text(
                              '• Multiple ranges must be separated by a comma (,)',
                              style: TextStyle(
                                  fontSize: uiFontSize,
                                  fontFamily: uiFontFamily,
                                  color: getAdaptiveTextColor(context))),
                          const SizedBox(height: 8),
                          Text(
                              '• For example:\nGenesis, Num 10-20, Jud-Rev, Mat 22 - Joh 15',
                              style: TextStyle(
                                  fontSize: uiFontSize,
                                  fontFamily: uiFontFamily,
                                  color: getAdaptiveTextColor(context))),
                        ]))
                  ],
                ],
              ),
          ],
        )),
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
                crossAxisAlignment:
                    CrossAxisAlignment.stretch, // ensure full width
                children: [
                  TextField(
                    autofocus: true,
                    maxLength: 100,
                    maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    controller: _controller,
                    decoration: InputDecoration(
                      counter: SizedBox.shrink(),
                      hintText: 'Search',
                      hintStyle: TextStyle(
                          fontFamily: uiFontFamily, fontSize: uiFontSize + 4),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: Colors.blueGrey,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: Colors.blueGrey,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: Colors.blueGrey,
                          width: 2.0,
                        ),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          Icons.clear,
                          color: isDark
                              ? darkPrimaryColor.value
                              : lightPrimaryColor.value,
                          semanticLabel: 'Clear Search Query',
                        ),
                        onPressed: () async {
                          _controller.clear();
                          await _saveSearchOptions();
                        },
                        iconSize: 32,
                      ),
                    ),
                    onChanged: (_) {
                      _lastInputTime = DateTime.now();
                      unawaited(_saveSearchOptions());
                      if (_onSearchDebounce?.isActive ?? false) {
                        _onSearchDebounce?.cancel();
                      }
                      _onSearchDebounce =
                          Timer(Duration(milliseconds: 500), () {
                        if (_controller.text.isNotEmpty &&
                            _controller.text.length > 1 &&
                            (_controller.text.split('"').length - 1) % 2 == 0) {
                          _onSearch();
                        }
                      });
                    },
                    onSubmitted: (_) {
                      _onSearch();
                    },
                    style: TextStyle(
                        fontSize: uiFontSize + 4,
                        fontFamily: fontFamilyNotifier.value),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                      alignment: WrapAlignment.end,
                      runAlignment: WrapAlignment.end,
                      children: [
                        ElevatedButton(
                          onPressed: (_totalMatches != null &&
                                  _totalVerses != null &&
                                  _totalVerses! > 0)
                              ? () async {
                                  final searchText = _useRegex
                                      ? _controller.text
                                      : _controller.text.trim();
                                  await _saveSearchHistory(
                                      searchText,
                                      _isNearbySearchActive
                                          ? 'nearby'
                                          : (_useRegex ? 'regex' : null));
                                }
                              : null,
                          style: ButtonStyle(
                            backgroundColor:
                                WidgetStateProperty.resolveWith<Color>(
                                    (states) {
                              if (states.contains(WidgetState.disabled)) {
                                return Colors
                                    .grey; // Disabled/greyed out background
                              }
                              // Enabled state - use default elevated button background
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
                                return Colors
                                    .white60; // Less visible text for disabled
                              }
                              // Enabled state - use default elevated button text color
                              return Theme.of(context)
                                      .elevatedButtonTheme
                                      .style
                                      ?.foregroundColor
                                      ?.resolve(states) ??
                                  Colors.white;
                            }),
                          ),
                          child: Text('Save',
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
                          onPressed: _isResetting
                              ? null
                              : () async {
                                  if (_isResetting) return;
                                  setState(() => _isResetting = true);

                                  setState(() {
                                    // Clear search query text
                                    _controller.clear();
                                    // Reset all search option toggles to false
                                    _useRegex = false;
                                    _useNearby = false;
                                    _isNearbySearchActive = false;
                                    _useWholeWord = false;
                                    _useRedLetter = false;
                                    _caseSensitive = false;
                                    // Set book filter range to "All Books"
                                    _bookFilterType = 'All Books';
                                    // Reset custom range text entry box to empty string
                                    _customBookFilter = '';
                                    _customRangeController.text = '';
                                    // Clear search results and totals
                                    _searchResults = [];
                                    _totalMatches = null;
                                    _totalVerses = null;
                                  });
                                  // Clear highlight cache
                                  _clearHighlightCache();
                                  // Update book filter state
                                  _updateBookFilter();
                                  // Save reset options
                                  await _saveSearchOptions();

                                  if (context.mounted) {
                                    showStyledSnackBar(
                                        context, 'Search Options Reset');
                                  }

                                  // Enable button again after 3 seconds
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
                                return Colors
                                    .grey; // Disabled/greyed out background
                              }
                              // Enabled state - use default elevated button background
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
                                return Colors
                                    .white60; // Less visible text for disabled
                              }
                              // Enabled state - use default elevated button text color
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
                        ? Center(
                            child: Text(
                              'Enter search terms above',
                              style: TextStyle(
                                fontSize: uiFontSize + 6,
                                fontFamily: uiFontFamily,
                                color: getAdaptiveTextColor(context),
                              ),
                            ),
                          )
                        : _isSearching
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircularProgressIndicator(),
                                    const SizedBox(height: 16),
                                    Text('Searching...🔎',
                                        style: TextStyle(
                                            fontSize: uiFontSize + 8,
                                            fontFamily: uiFontFamily,
                                            color:
                                                getAdaptiveTextColor(context))),
                                  ],
                                ),
                              )
                            : (_searchResults.isEmpty &&
                                    (_controller.text.split('"').length - 1) %
                                            2 ==
                                        0)
                                ? Center(
                                    child: Text('No matches found 🧐',
                                        style: TextStyle(
                                            fontSize: uiFontSize + 8,
                                            fontFamily: uiFontFamily,
                                            color:
                                                getAdaptiveTextColor(context))))
                                : ValueListenableBuilder<double>(
                                    valueListenable: fontSizeNotifier,
                                    builder: (context, fontSize, child) {
                                      return RawScrollbar(
                                          thumbColor: isDark
                                              ? darkPrimaryColor.value
                                                  .withValues(alpha: 0.8)
                                              : lightPrimaryColor.value
                                                  .withValues(alpha: 0.8),
                                          thumbVisibility: false,
                                          trackVisibility: false,
                                          thickness: 16.0,
                                          controller: _resultsScrollController,
                                          radius: Radius.circular(8.0),
                                          child: ScrollConfiguration(
                                              behavior: ScrollConfiguration.of(
                                                      context)
                                                  .copyWith(scrollbars: false),
                                              child: ListView.builder(
                                                padding: EdgeInsets.only(
                                                    bottom:
                                                        100.0), // Allow the user to scroll below the results just like the bible screens
                                                controller:
                                                    _resultsScrollController,
                                                itemCount:
                                                    _searchResults.length,
                                                itemBuilder: (context, index) {
                                                  final result =
                                                      _searchResults[index];
                                                  final baseStyle = TextStyle(
                                                    fontSize: FontSizeAdjustments
                                                        .getAdjustedSize(
                                                            fontFamilyNotifier
                                                                .value,
                                                            fontSize),
                                                    color: Theme.of(context)
                                                                .brightness ==
                                                            Brightness.dark
                                                        ? darkTextColor.value
                                                        : lightTextColor.value,
                                                  );

                                                  // Check if this is a nearby search result (has startVerse/endVerse)
                                                  final isNearbyResult =
                                                      result.containsKey(
                                                              'startVerse') &&
                                                          result.containsKey(
                                                              'endVerse');

                                                  // Get keywords for highlighting (only available for nearby search)
                                                  final List<String> keywords =
                                                      isNearbyResult
                                                          ? _getKeywordsFromInput(
                                                              _controller.text)
                                                          : [];

                                                  return GestureDetector(
                                                    onTap: () =>
                                                        _showSearchResultActionMenu(
                                                            context, result),
                                                    child: Container(
                                                      //color: Theme.of(context).brightness == Brightness.dark ? darkBackgroundColor.value : lightBackgroundColor.value,
                                                      color: barColor,
                                                      width: double.infinity,
                                                      padding: EdgeInsets.only(
                                                          left: 0.0,
                                                          top: 0.0,
                                                          bottom: 0.0,
                                                          right: 18.0),
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text.rich(
                                                            TextSpan(
                                                              children: [
                                                                // Reference (bold)
                                                                TextSpan(
                                                                  text: isNearbyResult
                                                                      ? '${result['bookLongName'] as String? ?? 'ERROR'} ${result['chapter']}:${result['startVerse']}-${result['endVerse']}\n'
                                                                      : '${result['bookLongName'] as String? ?? 'ERROR'} ${result['chapter']}:${result['verse']}\n',
                                                                  style:
                                                                      TextStyle(
                                                                    fontSize: FontSizeAdjustments.getAdjustedSize(
                                                                        fontFamilyNotifier
                                                                            .value,
                                                                        fontSize),
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                    color: Theme.of(context).brightness ==
                                                                            Brightness
                                                                                .dark
                                                                        ? darkPrimaryColor
                                                                            .value // darkTextColor.value
                                                                        : lightPrimaryColor
                                                                            .value, // lightTextColor.value
                                                                  ),
                                                                ),
                                                                // Verse text with highlighting
                                                                if (isNearbyResult)
                                                                  _highlightNearbyText(
                                                                      context,
                                                                      result['text']
                                                                          as String,
                                                                      keywords,
                                                                      baseStyle)
                                                                else
                                                                  _getHighlightedSpan(
                                                                      result,
                                                                      baseStyle),
                                                              ],
                                                            ),
                                                          ),
                                                          if (index <
                                                              _searchResults
                                                                      .length -
                                                                  1)
                                                            Divider(
                                                              thickness: 1,
                                                              height: 16,
                                                              indent: MediaQuery.of(
                                                                          context)
                                                                      .size
                                                                      .width *
                                                                  0.01,
                                                              endIndent:
                                                                  MediaQuery.of(
                                                                              context)
                                                                          .size
                                                                          .width *
                                                                      0.01,
                                                              color: const Color
                                                                  .fromARGB(
                                                                  47,
                                                                  158,
                                                                  158,
                                                                  158),
                                                            ),
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                },
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
}

class UnbreakableText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  // Word Joiner (U+2060) – prevents line breaks at its position
  static const wordJoiner = '\u2060';

  const UnbreakableText(
    this.text, {
    super.key,
    this.style,
  });

  String _getModifiedText() {
    // Replace every non-space token with the same token
    // but with a Word Joiner between every character.
    return text.replaceAllMapped(
      RegExp(r'\S+'),
      (match) => match[0]!.split('').join(wordJoiner),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _getModifiedText(),
      style: style,
      softWrap: true, // normal wrapping allowed
      overflow: TextOverflow.visible,
    );
  }
}
