import 'dart:io';
import 'dart:math' as math;

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

// Top-level functions for compute() to keep expensive search work off the UI
// isolate on native platforms.
Future<BibleSearchComputationResult> _computeBibleSearch(
    BibleSearchTaskData data) async {
  if (data.useNearby) {
    return _computeNearbyBibleSearch(data);
  }
  return _computeRegularBibleSearch(data);
}

Future<BibleSearchComputationResult> _computeRegularBibleSearch(
    BibleSearchTaskData data) async {
  final patternData = _buildBibleSearchPattern(data);
  final results = await _searchBibleVersesOrdered(data, patternData);

  int matchCount = 0;
  for (final verse in results) {
    final text =
        _getBibleSearchText(verse['text'] as String, data.useRedLetter);
    matchCount += patternData.regex.allMatches(text).length;
  }

  return BibleSearchComputationResult(
    searchResults: results,
    totalMatches: matchCount,
    totalVerses: results.length,
    isNearbySearchActive: false,
    regexPattern: patternData.pattern,
    regexCaseSensitive: data.caseSensitive,
    regexUnicode: patternData.unicode,
  );
}

Future<BibleSearchComputationResult> _computeNearbyBibleSearch(
    BibleSearchTaskData data) async {
  final results = await _searchBibleVersesNearby(data);
  final keywords = _getBibleKeywordsFromInput(data.input);
  if (keywords.isEmpty) {
    return BibleSearchComputationResult(
      searchResults: results,
      totalMatches: 0,
      totalVerses: 0,
      isNearbySearchActive: true,
    );
  }

  final escapedKeywords = keywords
      .map((k) =>
          data.useWholeWord ? '\\b${RegExp.escape(k)}\\b' : RegExp.escape(k))
      .toList();
  final pattern = '(${escapedKeywords.join('|')})';
  final regex = _createBibleSearchRegExp(pattern, data.caseSensitive);

  int matchCount = 0;
  int verseCount = 0;
  for (final result in results) {
    if (result.containsKey('verses')) {
      for (final verse in result['verses'] as List) {
        final text =
            _getBibleSearchText(verse['text'] as String, data.useRedLetter);
        if (regex.hasMatch(text)) {
          verseCount++;
        }
      }
    }
    final combinedText =
        (result['searchText'] as String?) ?? (result['text'] as String);
    matchCount += regex.allMatches(combinedText).length;
  }

  return BibleSearchComputationResult(
    searchResults: results,
    totalMatches: matchCount,
    totalVerses: verseCount,
    isNearbySearchActive: true,
  );
}

class BibleSearchTaskData {
  final String input;
  final bool useRegex;
  final bool useNearby;
  final bool useWholeWord;
  final bool useRedLetter;
  final bool caseSensitive;
  final List<String> allowedBooks;
  final Map<String, Set<int>> allowedChapters;

  const BibleSearchTaskData({
    required this.input,
    required this.useRegex,
    required this.useNearby,
    required this.useWholeWord,
    required this.useRedLetter,
    required this.caseSensitive,
    required this.allowedBooks,
    required this.allowedChapters,
  });
}

class BibleSearchComputationResult {
  final List<Map<String, dynamic>> searchResults;
  final int totalMatches;
  final int totalVerses;
  final bool isNearbySearchActive;
  final String? regexPattern;
  final bool regexCaseSensitive;
  final bool regexUnicode;

  const BibleSearchComputationResult({
    required this.searchResults,
    required this.totalMatches,
    required this.totalVerses,
    required this.isNearbySearchActive,
    this.regexPattern,
    this.regexCaseSensitive = false,
    this.regexUnicode = false,
  });
}

class _BibleSearchPatternData {
  final List<String> keywords;
  final RegExp regex;
  final List<String> escapedTerms;
  final String pattern;
  final bool unicode;

  const _BibleSearchPatternData({
    required this.keywords,
    required this.regex,
    required this.escapedTerms,
    required this.pattern,
    required this.unicode,
  });
}

class _BibleHighlightRange {
  final int start;
  final int end;

  const _BibleHighlightRange(this.start, this.end);
}

class _BibleHighlightSegment {
  final int start;
  final int end;
  final bool eligible;

  const _BibleHighlightSegment({
    required this.start,
    required this.end,
    required this.eligible,
  });
}

class _BibleHighlightOffset {
  int value = 0;
}

RegExp _createBibleSearchRegExp(String pattern, bool caseSensitive) {
  final unicode = _usesUnicodeSearchPatterns(pattern);
  return RegExp(pattern, caseSensitive: caseSensitive, unicode: unicode);
}

bool _usesUnicodeSearchPatterns(String pattern) {
  return pattern.contains('\\p{P}') ||
      pattern.contains('\\p{L}') ||
      pattern.contains('\\p{N}') ||
      pattern.contains('\\p{S}') ||
      pattern.contains('\\p{Z}') ||
      pattern.contains('\\p{M}');
}

String _extractBibleRedLetterText(String text) {
  final matches = RegExp(r'<r>(.*?)</r>', dotAll: true).allMatches(text);
  return matches
      .map((m) => VerseTextParser.toPlainVerseText(m.group(1)!))
      .join(' ');
}

String _cleanBibleVerseTextForSearch(String text) {
  return VerseTextParser.toPlainVerseText(text, removePilcrow: false);
}

String _getBibleSearchText(String verseText, bool useRedLetter) {
  String processedText = useRedLetter
      ? _extractBibleRedLetterText(verseText)
      : _cleanBibleVerseTextForSearch(verseText);
  if (processedText.contains('¶ ')) {
    processedText = processedText.replaceAll('¶ ', '');
  }
  return processedText;
}

final RegExp _bibleSearchPhraseRegExp = RegExp(r'"([^"]+)"');

bool _isEffectiveBibleSearchTerm(String term) {
  return term.replaceAll('*', '').trim().isNotEmpty;
}

List<String> _getEffectiveBibleSearchTerms(String input) {
  final phrases = _bibleSearchPhraseRegExp
      .allMatches(input)
      .map((m) => m.group(1)!)
      .where(_isEffectiveBibleSearchTerm)
      .toList();
  final queryWithoutPhrases =
      input.replaceAll(_bibleSearchPhraseRegExp, '').trim();
  final words = queryWithoutPhrases
      .split(RegExp(r'\s+'))
      .where(_isEffectiveBibleSearchTerm)
      .toList();
  return [...phrases, ...words];
}

bool _hasEffectiveBibleSearchInput(String input, {required bool useRegex}) {
  final searchText = useRegex ? input : input.trim();
  if (searchText.isEmpty) return false;

  if (!useRegex) {
    return _getEffectiveBibleSearchTerms(searchText).isNotEmpty;
  }

  try {
    final regex = _createBibleSearchRegExp(searchText, false);
    return !regex.hasMatch('');
  } on FormatException {
    return false;
  }
}

List<String> _getBibleKeywordsFromInput(String input) {
  final withoutPhrases = input.replaceAll(_bibleSearchPhraseRegExp, '').trim();
  return withoutPhrases
      .split(RegExp(r'\s+'))
      .where(_isEffectiveBibleSearchTerm)
      .map((term) => term.replaceAll('*', '').trim())
      .where((t) => t.isNotEmpty)
      .toList();
}

List<String> _getBiblePreFilterKeywords(List<String> terms) {
  return terms.expand((term) {
    final cleanTerm = term.replaceAll('*', '').trim();
    if (cleanTerm.isEmpty) return const Iterable<String>.empty();

    final words = cleanTerm
        .split(RegExp(r"[^A-Za-z0-9'\-]+"))
        .where((word) => word.isNotEmpty)
        .toList();
    return words.isEmpty ? [cleanTerm] : words;
  }).toList();
}

Future<List<Map<String, dynamic>>> _searchBibleVersesByCleanKeywords(
  BibleSearchTaskData data, {
  required List<String> preFilterKeywords,
  bool useOrLogic = false,
}) async {
  if (preFilterKeywords.isEmpty) return [];

  final results = <Map<String, dynamic>>[];
  final allVerses = await BibleDatabase.getAllVerses();

  final keywordCounts = <String, int>{};
  if (!useOrLogic) {
    for (final keyword in preFilterKeywords) {
      final key = data.caseSensitive ? keyword : keyword.toLowerCase();
      keywordCounts[key] = (keywordCounts[key] ?? 0) + 1;
    }
  }

  for (final verse in allVerses) {
    final text = _getBibleSearchText(
      verse['text'] as String,
      data.useRedLetter,
    );
    final searchText = data.caseSensitive ? text : text.toLowerCase();

    var matches = true;
    if (useOrLogic) {
      matches = false;
      for (final keyword in preFilterKeywords) {
        final checkKeyword =
            data.caseSensitive ? keyword : keyword.toLowerCase();
        if (searchText.contains(checkKeyword)) {
          matches = true;
          break;
        }
      }
    } else {
      for (final entry in keywordCounts.entries) {
        final actualCount = entry.key.allMatches(searchText).length;
        if (actualCount < entry.value) {
          matches = false;
          break;
        }
      }
    }

    if (matches) {
      results.add(verse);
    }
  }

  return results;
}

_BibleSearchPatternData _buildBibleSearchPattern(BibleSearchTaskData data) {
  if (data.useRegex) {
    final regex = _createBibleSearchRegExp(data.input, data.caseSensitive);
    return _BibleSearchPatternData(
      keywords: const [],
      regex: regex,
      escapedTerms: const [],
      pattern: data.input,
      unicode: _usesUnicodeSearchPatterns(data.input),
    );
  }

  final allTerms = _getEffectiveBibleSearchTerms(data.input);
  if (allTerms.isEmpty) {
    final regex = _createBibleSearchRegExp(r'\b\B', data.caseSensitive);
    return _BibleSearchPatternData(
      keywords: const [],
      regex: regex,
      escapedTerms: const [],
      pattern: r'\b\B',
      unicode: false,
    );
  }

  final keywords = _getBiblePreFilterKeywords(allTerms);

  final escapedTerms = allTerms.map((term) {
    String escaped = RegExp.escape(term);
    escaped = escaped.replaceAll('\\*', '[A-Za-z]*');
    return escaped;
  }).toList();

  final pattern = data.useWholeWord
      ? '\\b(${escapedTerms.join('|')})\\b'
      : '(${escapedTerms.join('|')})';
  final regex = _createBibleSearchRegExp(pattern, data.caseSensitive);
  return _BibleSearchPatternData(
    keywords: keywords,
    regex: regex,
    escapedTerms: escapedTerms,
    pattern: pattern,
    unicode: _usesUnicodeSearchPatterns(pattern),
  );
}

Future<List<Map<String, dynamic>>> _searchBibleVersesOrdered(
    BibleSearchTaskData data, _BibleSearchPatternData patternData) async {
  final bookOrderIndex =
      _buildBibleBookOrderIndex(await BibleDatabase.getBooks());

  if (patternData.escapedTerms.length > 1 && !data.useNearby) {
    final results = await BibleDatabase.getAllVerses();
    final termRegexes = patternData.escapedTerms.map((term) {
      final pattern = data.useWholeWord ? '\\b$term\\b' : term;
      return _createBibleSearchRegExp(pattern, data.caseSensitive);
    }).toList();

    final filteredResults = results.where((verse) {
      final searchText =
          _getBibleSearchText(verse['text'] as String, data.useRedLetter);
      return termRegexes.every((regex) => regex.hasMatch(searchText));
    }).where((verse) {
      return BookFilter.verseMatchesFilter(
          verse, data.allowedBooks, data.allowedChapters);
    }).map((result) {
      return {
        ...result,
        'bookLongName':
            BookNameConverter.shortNameToLongName(result['book'] as String),
      };
    }).toList();

    _sortBibleResultsInBibleOrder(filteredResults, bookOrderIndex);
    return filteredResults;
  }

  final hasWildcards =
      patternData.escapedTerms.any((term) => term.contains('[A-Za-z]*'));
  final results = patternData.keywords.isEmpty || hasWildcards
      ? await BibleDatabase.getAllVerses()
      : await _searchBibleVersesByCleanKeywords(
          data,
          preFilterKeywords: patternData.keywords,
        );

  final filteredResults = results.where((verse) {
    final searchText =
        _getBibleSearchText(verse['text'] as String, data.useRedLetter);
    return patternData.regex.hasMatch(searchText);
  }).where((verse) {
    return BookFilter.verseMatchesFilter(
        verse, data.allowedBooks, data.allowedChapters);
  }).map((result) {
    return {
      ...result,
      'bookLongName':
          BookNameConverter.shortNameToLongName(result['book'] as String),
    };
  }).toList();

  _sortBibleResultsInBibleOrder(filteredResults, bookOrderIndex);
  return filteredResults;
}

Future<List<Map<String, dynamic>>> _searchBibleVersesNearby(
    BibleSearchTaskData data) async {
  final keywords = _getBibleKeywordsFromInput(data.input);
  if (keywords.length <= 1) {
    return [];
  }

  final allVerses = await _searchBibleVersesByCleanKeywords(
    data,
    preFilterKeywords: keywords,
    useOrLogic: true,
  );
  final filteredVerses = allVerses.where((verse) {
    return BookFilter.verseMatchesFilter(
        verse, data.allowedBooks, data.allowedChapters);
  }).toList();

  final chapterGroups = <String, List<Map<String, dynamic>>>{};
  for (final verse in filteredVerses) {
    final key = '${verse['book']}_${verse['chapter']}';
    chapterGroups.putIfAbsent(key, () => []).add(verse);
  }

  final results = <Map<String, dynamic>>[];
  for (final chapterVerses in chapterGroups.values) {
    chapterVerses
        .sort((a, b) => (a['verse'] as int).compareTo(b['verse'] as int));

    final clusters = _findNearbyBibleClusters(chapterVerses, keywords, data);
    for (final cluster in clusters) {
      final startVerse = cluster.first['verse'] as int;
      final endVerse = cluster.last['verse'] as int;
      final book = cluster.first['book'] as String;
      final chapter = cluster.first['chapter'] as int;
      final allChapterVerses = await BibleDatabase.getVerses(book, chapter);
      final versesInRange = allChapterVerses
          .where((v) =>
              (v['verse'] as int) >= startVerse &&
              (v['verse'] as int) <= endVerse)
          .toList();

      final combinedText = versesInRange.map((v) {
        String verseText = v['text'] as String;
        if (verseText.contains('¶ ')) {
          verseText = verseText.replaceAll('¶ ', '');
        }
        return '${v['verse']} $verseText';
      }).join('\n');
      final combinedSearchText = versesInRange.map((v) {
        final verseText =
            _getBibleSearchText(v['text'] as String, data.useRedLetter);
        return '${v['verse']} $verseText';
      }).join('\n');

      results.add({
        'book': book,
        'chapter': chapter,
        'startVerse': startVerse,
        'endVerse': endVerse,
        'verses': versesInRange,
        'text': combinedText,
        'searchText': combinedSearchText,
        'bookLongName': BookNameConverter.shortNameToLongName(book),
      });
    }
  }

  final bookOrderIndex =
      _buildBibleBookOrderIndex(await BibleDatabase.getBooks());
  results.sort((a, b) {
    final bookA = _bibleBookIdx(a['book'], bookOrderIndex);
    final bookB = _bibleBookIdx(b['book'], bookOrderIndex);
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

List<List<Map<String, dynamic>>> _findNearbyBibleClusters(
  List<Map<String, dynamic>> chapterVerses,
  List<String> keywords,
  BibleSearchTaskData data,
) {
  final clusters = <List<Map<String, dynamic>>>[];

  for (int i = 0; i < chapterVerses.length; i++) {
    final startVerse = chapterVerses[i];
    final startVerseNum = startVerse['verse'] as int;
    int bestEndIndex = i;
    final foundKeywords = _getBibleKeywordsInVerse(startVerse, keywords, data);

    for (int j = i + 1; j < chapterVerses.length; j++) {
      final currentVerse = chapterVerses[j];
      final currentVerseNum = currentVerse['verse'] as int;
      if (currentVerseNum - startVerseNum > 3) {
        break;
      }

      final newKeywords =
          _getBibleKeywordsInVerse(currentVerse, keywords, data);
      foundKeywords.addAll(newKeywords);
      if (foundKeywords.length == keywords.length) {
        bestEndIndex = j;
      }
    }

    if (foundKeywords.length == keywords.length && bestEndIndex > i) {
      final cluster = chapterVerses.sublist(i, bestEndIndex + 1);
      final overlaps = clusters.any(
          (existingCluster) => _bibleClustersOverlap(cluster, existingCluster));
      if (!overlaps) {
        clusters.add(cluster);
      }
      i = bestEndIndex;
    }
  }
  return clusters;
}

Set<String> _getBibleKeywordsInVerse(
  Map<String, dynamic> verse,
  List<String> keywords,
  BibleSearchTaskData data,
) {
  final found = <String>{};
  final verseText =
      _getBibleSearchText(verse['text'] as String, data.useRedLetter);

  for (final keyword in keywords) {
    final pattern = data.useWholeWord
        ? '\\b${RegExp.escape(keyword)}\\b'
        : RegExp.escape(keyword);
    final regex = _createBibleSearchRegExp(pattern, data.caseSensitive);
    if (regex.hasMatch(verseText)) {
      found.add(keyword);
    }
  }
  return found;
}

bool _bibleClustersOverlap(
    List<Map<String, dynamic>> cluster1, List<Map<String, dynamic>> cluster2) {
  final start1 = cluster1.first['verse'] as int;
  final end1 = cluster1.last['verse'] as int;
  final start2 = cluster2.first['verse'] as int;
  final end2 = cluster2.last['verse'] as int;
  return !(end1 < start2 || end2 < start1);
}

Map<String, int> _buildBibleBookOrderIndex(List<String> books) {
  final map = <String, int>{};
  for (int i = 0; i < books.length; i++) {
    final raw = books[i];
    map[raw] = i;
    map[_normBibleBook(raw)] = i;
  }
  return map;
}

String _normBibleBook(dynamic book) => book.toString().trim().toUpperCase();

int _bibleBookIdx(dynamic book, Map<String, int> bookOrderIndex) {
  final norm = _normBibleBook(book);
  return bookOrderIndex[norm] ?? bookOrderIndex[book] ?? (1 << 30);
}

int _asBibleInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

void _sortBibleResultsInBibleOrder(
    List<Map<String, dynamic>> list, Map<String, int> bookOrderIndex) {
  list.sort((a, b) {
    final ia = _bibleBookIdx(a['book'], bookOrderIndex);
    final ib = _bibleBookIdx(b['book'], bookOrderIndex);
    if (ia != ib) return ia.compareTo(ib);
    final ca = _asBibleInt(a['chapter']);
    final cb = _asBibleInt(b['chapter']);
    if (ca != cb) return ca.compareTo(cb);
    final va = _asBibleInt(a['verse']);
    final vb = _asBibleInt(b['verse']);
    return va.compareTo(vb);
  });
}

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
  int _activeSearchId = 0;
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

  // Check if input is valid for nearby search (>1 word, no quoted phrases)
  bool _isValidNearbyInput(String input) {
    if (!_useNearby || _useRegex) return false;
    if (input.contains('"')) return false;

    return _getBibleKeywordsFromInput(input).length > 1;
  }

  // Show warning when nearby search criteria aren't met
  void _showNearbyWarning(String input) {
    String reason = '';
    if (_useRegex) {
      reason = 'Nearby search does not work with Regex mode.';
    } else {
      final keywords = _getBibleKeywordsFromInput(input);

      if (input.contains('"')) {
        reason = 'Nearby search does not work with phrases.';
      } else if (keywords.length <= 1) {
        reason = 'Nearby search requires more than one word.';
      }
    }

    showStyledSnackBar(context, reason);
  }

  // Extract keywords from search input (same logic as _searchVersesNearby)
  List<String> _getKeywordsFromInput(String input) {
    return _getBibleKeywordsFromInput(input);
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
    final keywordRegex = _createBibleSearchRegExp(pattern, _caseSensitive);

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
    _activeSearchId++;
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

  BibleSearchTaskData _buildBibleSearchTask(String input) {
    return BibleSearchTaskData(
      input: input,
      useRegex: _useRegex,
      useNearby: _useNearby,
      useWholeWord: _useWholeWord,
      useRedLetter: _useRedLetter,
      caseSensitive: _caseSensitive,
      allowedBooks: List<String>.from(_allowedBooks),
      allowedChapters: _allowedChapters.map(
        (book, chapters) => MapEntry(book, Set<int>.from(chapters)),
      ),
    );
  }

  Future<BibleSearchComputationResult> _runBibleSearchTask(
      BibleSearchTaskData taskData) {
    if (kIsWeb) {
      return _computeBibleSearch(taskData);
    }
    return compute(_computeBibleSearch, taskData);
  }

  RegExp? _buildHighlightRegex(BibleSearchComputationResult result) {
    final pattern = result.regexPattern;
    if (pattern == null) return null;
    return RegExp(
      pattern,
      caseSensitive: result.regexCaseSensitive,
      unicode: result.regexUnicode,
    );
  }

  void _applyBibleSearchResult(BibleSearchComputationResult result) {
    _clearHighlightCache();
    setState(() {
      _searchResults = result.searchResults;
      _setTotals(result.totalMatches, result.totalVerses);
      _currentRegex =
          result.isNearbySearchActive ? null : _buildHighlightRegex(result);
      _isNearbySearchActive = result.isNearbySearchActive;
      _isSearching = false;
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

      if (!_hasEffectiveBibleSearchInput(
        restoredSearchText,
        useRegex: _useRegex,
      )) {
        setState(() {
          _searchResults = [];
          _setTotals(null, null);
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

      final searchId = ++_activeSearchId;
      final result =
          await _runBibleSearchTask(_buildBibleSearchTask(restoredSearchText));
      if (!mounted || searchId != _activeSearchId) return;
      _applyBibleSearchResult(result);
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
    final searchId = ++_activeSearchId;

    // Check for invalid custom range
    if (_bookFilterType == 'Custom Range' && _customRangeError != null) {
      return;
    }

    // Check for empty custom range
    if (_bookFilterType == 'Custom Range' && _customBookFilter.isEmpty) {
      return;
    }

    // Validate input - prevent empty searches that would cause freezing or return
    // a lot of results that aren't useful
    final searchText = _useRegex ? _controller.text : _controller.text.trim();
    if (!_hasEffectiveBibleSearchInput(searchText, useRegex: _useRegex)) {
      setState(() {
        _searchResults = [];
        _setTotals(null, null);
        _currentRegex = null;
        _isNearbySearchActive = false;
        _isSearching = false;
      });
      return;
    }

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
    if (!mounted || searchId != _activeSearchId) return;

    try {
      final result =
          await _runBibleSearchTask(_buildBibleSearchTask(searchText));
      if (!mounted || searchId != _activeSearchId) return;
      _applyBibleSearchResult(result);

      await _saveLastSearch();
      if (!mounted || searchId != _activeSearchId) return;

      // Don't bother to use this bug-workaround if we aren't on windows
      // and we aren't in tablet mode because it can be frustrating having
      // the focus removed when we aren't done typing. when in tablet mode
      // we have to deal with it because the OSK bug is far more frustrating once
      // it is triggered (it opens the OSK on ANY UI interaction)
      //
      // Check that the device is touch capable and has a physical keyboard to attempt
      // to avoid triggering this when a 2-in-1 is in laptop mode (keyboard attached)
      //
      // .isKeyboardAttached might not work as expected
      if (!kIsWeb &&
          (Platform.isWindows &&
              TabletModeService().isTablet &&
              await TabletModeDetector.hasTouchScreen() &&
              await TabletModeDetector.isKeyboardAttached())) {
        // After a delay of 1s, check if any input was recieved in the last 1s, if not
        // then force the focus away to prevent the windows OSK bug
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (!mounted || searchId != _activeSearchId) return;
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
      if (!mounted || searchId != _activeSearchId) return;
      setState(() {
        _searchResults = [];
        _setTotals(0, 0);
        _currentRegex = null;
        _isNearbySearchActive = false;
        _isSearching = false;
      });
    }
  }

  TextSpan _highlightParsedSpan(
      TextSpan span, RegExp regex, BuildContext context,
      {bool redLetterOnly = false}) {
    final color = _getHighlightColor(context);
    final visibleText = StringBuffer();
    final segments = <_BibleHighlightSegment>[];
    _collectHighlightSegments(
      span,
      visibleText,
      segments,
      redLetterOnly: redLetterOnly,
    );

    if (visibleText.isEmpty) {
      return span;
    }

    final ranges = _getHighlightRanges(
      visibleText.toString(),
      regex,
      segments,
      redLetterOnly: redLetterOnly,
    );
    if (ranges.isEmpty) {
      return span;
    }

    return _applyHighlightRanges(
      span,
      ranges,
      color,
      _BibleHighlightOffset(),
    );
  }

  void _collectHighlightSegments(
    InlineSpan span,
    StringBuffer visibleText,
    List<_BibleHighlightSegment> segments, {
    required bool redLetterOnly,
    TextStyle? inheritedStyle,
  }) {
    if (span is! TextSpan) return;

    final effectiveStyle = span.style ?? inheritedStyle;
    final text = span.text;
    if (text != null && text.isNotEmpty) {
      final start = visibleText.length;
      visibleText.write(text);
      final end = visibleText.length;
      segments.add(_BibleHighlightSegment(
        start: start,
        end: end,
        eligible: !redLetterOnly || effectiveStyle?.color == Colors.red,
      ));
    }

    for (final child in span.children ?? const <InlineSpan>[]) {
      _collectHighlightSegments(
        child,
        visibleText,
        segments,
        redLetterOnly: redLetterOnly,
        inheritedStyle: effectiveStyle,
      );
    }
  }

  List<_BibleHighlightRange> _getHighlightRanges(
    String text,
    RegExp regex,
    List<_BibleHighlightSegment> segments, {
    required bool redLetterOnly,
  }) {
    if (!redLetterOnly) {
      return _getHighlightRangesInText(text, regex);
    }

    final ranges = <_BibleHighlightRange>[];
    int? runStart;
    int? runEnd;

    void flushRun() {
      if (runStart == null || runEnd == null || runStart == runEnd) return;
      ranges.addAll(_getHighlightRangesInText(
        text.substring(runStart!, runEnd!),
        regex,
        offset: runStart!,
      ));
      runStart = null;
      runEnd = null;
    }

    for (final segment in segments) {
      if (!segment.eligible || segment.start == segment.end) {
        flushRun();
        continue;
      }

      if (runStart == null) {
        runStart = segment.start;
        runEnd = segment.end;
      } else if (segment.start == runEnd) {
        runEnd = segment.end;
      } else {
        flushRun();
        runStart = segment.start;
        runEnd = segment.end;
      }
    }

    flushRun();
    return ranges;
  }

  List<_BibleHighlightRange> _getHighlightRangesInText(
    String text,
    RegExp regex, {
    int offset = 0,
  }) {
    return regex
        .allMatches(text)
        .where((match) => match.start < match.end)
        .map((match) =>
            _BibleHighlightRange(offset + match.start, offset + match.end))
        .toList();
  }

  TextSpan _applyHighlightRanges(
    TextSpan span,
    List<_BibleHighlightRange> ranges,
    Color color,
    _BibleHighlightOffset offset, {
    TextStyle? inheritedStyle,
  }) {
    final effectiveStyle = span.style ?? inheritedStyle;
    final children = <InlineSpan>[];
    final text = span.text;

    if (text != null && text.isNotEmpty) {
      children.addAll(_buildHighlightedTextSpans(
        text,
        span.style,
        effectiveStyle,
        offset.value,
        ranges,
        color,
      ));
      offset.value += text.length;
    }

    for (final child in span.children ?? const <InlineSpan>[]) {
      if (child is TextSpan) {
        children.add(_applyHighlightRanges(
          child,
          ranges,
          color,
          offset,
          inheritedStyle: effectiveStyle,
        ));
      } else {
        children.add(child);
      }
    }

    if (children.isEmpty) return span;
    return TextSpan(style: span.style, children: children);
  }

  List<InlineSpan> _buildHighlightedTextSpans(
    String text,
    TextStyle? spanStyle,
    TextStyle? effectiveStyle,
    int globalStart,
    List<_BibleHighlightRange> ranges,
    Color color,
  ) {
    final spans = <InlineSpan>[];
    final globalEnd = globalStart + text.length;
    var localStart = 0;

    for (final range in ranges) {
      if (range.end <= globalStart) continue;
      if (range.start >= globalEnd) break;

      final highlightStart = math.max(range.start, globalStart) - globalStart;
      final highlightEnd = math.min(range.end, globalEnd) - globalStart;
      if (highlightStart > localStart) {
        spans.add(TextSpan(
          text: text.substring(localStart, highlightStart),
          style: spanStyle,
        ));
      }
      if (highlightEnd > highlightStart) {
        spans.add(TextSpan(
          text: text.substring(highlightStart, highlightEnd),
          style: (effectiveStyle ?? spanStyle ?? const TextStyle()).copyWith(
            backgroundColor: color,
            fontWeight: FontWeight.bold,
          ),
        ));
      }
      localStart = math.max(localStart, highlightEnd);
    }

    if (localStart < text.length) {
      spans.add(TextSpan(text: text.substring(localStart), style: spanStyle));
    }
    return spans;
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

    final cleanVerseText = VerseTextParser.toPlainVerseText(rawVerseText);

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
                  fontSize: uiFontSize + 8,
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
              'Copy ${isNearbyResult ? 'Verses $verseNum-$endVerseNum' : 'Verse $verseNum'}',
              style: TextStyle(
                  fontFamily: fontFamilyNotifier.value,
                  fontSize: uiFontSize + 8,
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
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context)),
                minFontSize: uiFontSize - 14,
              ))
            : Text(
                'Bible Search',
                style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context)),
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
                      hintText: 'Search the Holy Bible',
                      hintStyle: TextStyle(
                          fontFamily: uiFontFamily, fontSize: uiFontSize),
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
                          _onSearchDebounce?.cancel();
                          _activeSearchId++;
                          setState(() {
                            _controller.clear();
                            _searchResults = [];
                            _totalMatches = null;
                            _totalVerses = null;
                            _currentRegex = null;
                            _isNearbySearchActive = false;
                            _isSearching = false;
                          });
                          await _saveSearchOptions();
                        },
                        iconSize: 32,
                      ),
                    ),
                    onChanged: (_) {
                      _lastInputTime = DateTime.now();
                      unawaited(_saveSearchOptions());
                      _activeSearchId++;
                      if (_onSearchDebounce?.isActive ?? false) {
                        _onSearchDebounce?.cancel();
                      }
                      final canLiveSearch = _controller.text.isNotEmpty &&
                          _controller.text.length > 3 &&
                          (_controller.text.split('"').length - 1) % 2 == 0;
                      if (kIsWeb || !canLiveSearch) {
                        if (_isSearching) {
                          setState(() => _isSearching = false);
                        }
                        return;
                      }
                      _onSearchDebounce =
                          Timer(Duration(milliseconds: 500), () {
                        _onSearch();
                      });
                    },
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
                                  _onSearchDebounce?.cancel();
                                  _activeSearchId++;
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
                                    _currentRegex = null;
                                    _isSearching = false;
                                    _totalMatches = null;
                                    _totalVerses = null;
                                  });
                                  // Clear highlight cache
                                  _clearHighlightCache();
                                  // Update book filter state
                                  _updateBookFilter();
                                  // Save reset options
                                  await _saveSearchOptions();

                                  // if (context.mounted) {
                                  //   showStyledSnackBar(
                                  //       context, 'Search Options Reset');
                                  // }

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
                        ? SizedBox.shrink()
                        // Center(
                        //     child: Text(
                        //       'Enter search terms above',
                        //       style: TextStyle(
                        //         fontSize: uiFontSize + 6,
                        //         fontFamily: uiFontFamily,
                        //         color: getAdaptiveTextColor(context),
                        //       ),
                        //     ),
                        //   )
                        : _isSearching
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircularProgressIndicator(),
                                    //const SizedBox(height: 16),
                                    Text('Searching...',
                                        style: TextStyle(
                                            fontSize: uiFontSize + 4,
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
                                    child: Text(
                                        'No results 🤷‍♂️\n\n⚪ Check your spelling\n⚪ Check the search options',
                                        style: TextStyle(
                                            fontSize: uiFontSize + 4,
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
