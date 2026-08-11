import 'package:flutter/foundation.dart';

import '../database/strongs_database.dart';

StrongsNumberSearchResult runStrongsNumberSearch(String strongsNumber) {
  final stopwatch = Stopwatch()..start();
  if (kDebugMode) {
    debugPrint(
        '[runStrongsNumberSearch] START: strongsNumber="$strongsNumber"');
  }

  final results = StrongsDatabase.searchByStrongsNumber(strongsNumber);
  if (kDebugMode) {
    debugPrint(
        '[runStrongsNumberSearch] verse scan finished in ${stopwatch.elapsedMilliseconds}ms: ${results.length} verses');
  }
  final phraseSummary = results.isEmpty
      ? <String, int>{}
      : StrongsDatabase.extractPhraseSummary(
          results,
          [strongsNumber],
          includeTvm: true,
        );

  if (kDebugMode) {
    debugPrint(
        '[runStrongsNumberSearch] DONE in ${stopwatch.elapsedMilliseconds}ms: ${results.length} verses, ${phraseSummary.length} phrases');
  }

  return StrongsNumberSearchResult(
    searchResults: results,
    phraseSummary: phraseSummary,
  );
}

WordSearchResult runWordSearch(String word) {
  final stopwatch = Stopwatch()..start();
  if (kDebugMode) {
    debugPrint('[runWordSearch] START: word="$word"');
  }

  final wordData = StrongsDatabase.searchByWordWithStrongsNumbers(
    word,
    includeWordVerses: false,
  );
  final foundStrongs = wordData.foundStrongsNumbers;
  if (kDebugMode) {
    debugPrint(
        '[runWordSearch] word scan finished in ${stopwatch.elapsedMilliseconds}ms: ${wordData.wordVerseCount} word verses, ${foundStrongs.length} Strong\'s numbers');
  }
  if (wordData.wordVerseCount == 0 || foundStrongs.isEmpty) {
    if (kDebugMode) {
      debugPrint(
          '[runWordSearch] DONE in ${stopwatch.elapsedMilliseconds}ms: ${wordData.wordVerseCount} word verses, ${foundStrongs.length} Strong\'s numbers');
    }
    return WordSearchResult(
      wordVerseCount: wordData.wordVerseCount,
      foundStrongsNumbers: foundStrongs,
      searchResults: const [],
      phraseSummary: const {},
    );
  }

  final strongsList = foundStrongs.keys.toList();
  final strongsSearch =
      StrongsDatabase.searchByStrongsNumbersWithPhraseSummary(strongsList);
  final results = strongsSearch.searchResults;
  final phraseSummary = strongsSearch.phraseSummary;
  if (kDebugMode) {
    debugPrint(
        '[runWordSearch] Strong\'s scan finished in ${stopwatch.elapsedMilliseconds}ms: ${results.length} result verses');
  }

  if (kDebugMode) {
    debugPrint(
        '[runWordSearch] DONE in ${stopwatch.elapsedMilliseconds}ms: ${wordData.wordVerseCount} word verses, ${foundStrongs.length} Strong\'s numbers, ${results.length} result verses, ${phraseSummary.length} phrases');
  }

  return WordSearchResult(
    wordVerseCount: wordData.wordVerseCount,
    foundStrongsNumbers: foundStrongs,
    searchResults: results,
    phraseSummary: phraseSummary,
  );
}

ReferenceSearchResult runReferenceSearch(ReferenceSearchTaskData data) {
  final stopwatch = Stopwatch()..start();
  if (kDebugMode) {
    debugPrint(
        '[runReferenceSearch] START: "${data.book} ${data.chapter}:${data.verse} ${data.word}"');
  }

  final availableBooks = StrongsDatabase.getAvailableBooks();
  if (!availableBooks.contains(data.book)) {
    if (kDebugMode) {
      debugPrint(
          '[runReferenceSearch] DONE in ${stopwatch.elapsedMilliseconds}ms: invalid book');
    }
    return ReferenceSearchResult(error: 'Invalid book: ${data.book}');
  }

  final availableChapters = StrongsDatabase.getAvailableChapters(data.book);
  if (!availableChapters.contains(data.chapter)) {
    if (kDebugMode) {
      debugPrint(
          '[runReferenceSearch] DONE in ${stopwatch.elapsedMilliseconds}ms: invalid chapter');
    }
    return ReferenceSearchResult(
      error: 'Invalid chapter ${data.chapter} for ${data.book}',
    );
  }

  final availableVerses =
      StrongsDatabase.getAvailableVerses(data.book, data.chapter);
  if (!availableVerses.contains(data.verse)) {
    if (kDebugMode) {
      debugPrint(
          '[runReferenceSearch] DONE in ${stopwatch.elapsedMilliseconds}ms: invalid verse');
    }
    return ReferenceSearchResult(
      error: 'Invalid verse ${data.verse} for ${data.book} ${data.chapter}',
    );
  }

  if (!StrongsDatabase.wordExistsInVerse(
      data.book, data.chapter, data.verse, data.word)) {
    if (kDebugMode) {
      debugPrint(
          '[runReferenceSearch] DONE in ${stopwatch.elapsedMilliseconds}ms: word missing from verse');
    }
    return ReferenceSearchResult(
      error:
          'Word "${data.word}" not found in ${data.book} ${data.chapter}:${data.verse}',
    );
  }

  final strongsNumbers = StrongsDatabase.findStrongsNumbersForWordInVerse(
    data.book,
    data.chapter,
    data.verse,
    data.word,
    usePhraseFallback: false,
  );
  if (strongsNumbers.isEmpty) {
    if (kDebugMode) {
      debugPrint(
          '[runReferenceSearch] DONE in ${stopwatch.elapsedMilliseconds}ms: no Strong\'s numbers found');
    }
    return ReferenceSearchResult(
      error:
          'No Strong\'s numbers found for "${data.word}" in ${data.book} ${data.chapter}:${data.verse}',
    );
  }

  final foundStrongs = <String, Map<String, dynamic>>{};
  for (final sn in strongsNumbers) {
    foundStrongs[sn] = {
      'book': data.book,
      'chapter': data.chapter,
      'verse': data.verse,
    };
  }

  final strongsSearch =
      StrongsDatabase.searchByStrongsNumbersWithPhraseSummary(strongsNumbers);
  final results = strongsSearch.searchResults;
  final phraseSummary = strongsSearch.phraseSummary;
  if (kDebugMode) {
    debugPrint(
        '[runReferenceSearch] Strong\'s scan finished in ${stopwatch.elapsedMilliseconds}ms: ${results.length} result verses');
  }

  if (kDebugMode) {
    debugPrint(
        '[runReferenceSearch] DONE in ${stopwatch.elapsedMilliseconds}ms: ${strongsNumbers.length} Strong\'s numbers, ${results.length} verses, ${phraseSummary.length} phrases');
  }

  return ReferenceSearchResult(
    strongsNumbers: strongsNumbers,
    foundStrongsNumbers: foundStrongs,
    searchResults: results,
    phraseSummary: phraseSummary,
  );
}

class StrongsNumberSearchResult {
  final List<Map<String, dynamic>> searchResults;
  final Map<String, int> phraseSummary;

  const StrongsNumberSearchResult({
    required this.searchResults,
    required this.phraseSummary,
  });
}

class ReferenceSearchTaskData {
  final String book;
  final int chapter;
  final int verse;
  final String word;

  const ReferenceSearchTaskData({
    required this.book,
    required this.chapter,
    required this.verse,
    required this.word,
  });
}

class ReferenceSearchResult {
  final List<String> strongsNumbers;
  final Map<String, Map<String, dynamic>> foundStrongsNumbers;
  final List<Map<String, dynamic>> searchResults;
  final Map<String, int> phraseSummary;
  final String? error;

  const ReferenceSearchResult({
    this.strongsNumbers = const [],
    this.foundStrongsNumbers = const {},
    this.searchResults = const [],
    this.phraseSummary = const {},
    this.error,
  });
}

class WordSearchResult {
  final int wordVerseCount;
  final Map<String, Map<String, dynamic>> foundStrongsNumbers;
  final List<Map<String, dynamic>> searchResults;
  final Map<String, int> phraseSummary;

  const WordSearchResult({
    required this.wordVerseCount,
    required this.foundStrongsNumbers,
    required this.searchResults,
    required this.phraseSummary,
  });
}
