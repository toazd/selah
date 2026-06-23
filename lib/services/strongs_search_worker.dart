import 'package:flutter/foundation.dart';

import '../database/strongs_database.dart';

Future<StrongsNumberSearchComputationResult> computeStrongsNumberSearchResult(
    String strongsNumber) async {
  if (kDebugMode) {
    debugPrint(
        '[computeStrongsNumberSearchResult] START: strongsNumber="$strongsNumber"');
  }

  final results = StrongsDatabase.searchByStrongsNumber(strongsNumber);
  final phraseSummary = results.isEmpty
      ? <String, int>{}
      : StrongsDatabase.extractPhraseSummary(
          results,
          [strongsNumber],
          includeTvm: true,
        );

  if (kDebugMode) {
    debugPrint(
        '[computeStrongsNumberSearchResult] DONE: ${results.length} verses, ${phraseSummary.length} phrases');
  }

  return StrongsNumberSearchComputationResult(
    searchResults: results,
    phraseSummary: phraseSummary,
  );
}

Future<WordSearchComputationResult> computeWordSearchResult(String word) async {
  if (kDebugMode) {
    debugPrint('[computeWordSearchResult] START: word="$word"');
  }

  final wordData = StrongsDatabase.searchByWordWithStrongsNumbers(word);
  final foundStrongs = wordData.foundStrongsNumbers;
  if (wordData.wordVerses.isEmpty || foundStrongs.isEmpty) {
    if (kDebugMode) {
      debugPrint(
          '[computeWordSearchResult] DONE: ${wordData.wordVerses.length} word verses, ${foundStrongs.length} Strong\'s numbers');
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
        '[computeWordSearchResult] DONE: ${wordData.wordVerses.length} word verses, ${foundStrongs.length} Strong\'s numbers, ${results.length} result verses, ${phraseSummary.length} phrases');
  }

  return WordSearchComputationResult(
    wordVerseCount: wordData.wordVerses.length,
    foundStrongsNumbers: foundStrongs,
    searchResults: results,
    phraseSummary: phraseSummary,
  );
}

Future<ReferenceSearchComputationResult> computeReferenceSearchResult(
    ReferenceSearchTaskData data) async {
  if (kDebugMode) {
    debugPrint(
        '[computeReferenceSearchResult] START: "${data.book} ${data.chapter}:${data.verse} ${data.word}"');
  }

  final availableBooks = StrongsDatabase.getAvailableBooks();
  if (!availableBooks.contains(data.book)) {
    return ReferenceSearchComputationResult(
        error: 'Invalid book: ${data.book}');
  }

  final availableChapters = StrongsDatabase.getAvailableChapters(data.book);
  if (!availableChapters.contains(data.chapter)) {
    return ReferenceSearchComputationResult(
      error: 'Invalid chapter ${data.chapter} for ${data.book}',
    );
  }

  final availableVerses =
      StrongsDatabase.getAvailableVerses(data.book, data.chapter);
  if (!availableVerses.contains(data.verse)) {
    return ReferenceSearchComputationResult(
      error: 'Invalid verse ${data.verse} for ${data.book} ${data.chapter}',
    );
  }

  if (!StrongsDatabase.wordExistsInVerse(
      data.book, data.chapter, data.verse, data.word)) {
    return ReferenceSearchComputationResult(
      error:
          'Word "${data.word}" not found in ${data.book} ${data.chapter}:${data.verse}',
    );
  }

  final strongsNumbers = StrongsDatabase.findStrongsNumbersForWordInVerse(
    data.book,
    data.chapter,
    data.verse,
    data.word,
  );
  if (strongsNumbers.isEmpty) {
    return ReferenceSearchComputationResult(
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

  final results = StrongsDatabase.searchByStrongsNumbers(strongsNumbers);
  final phraseSummary = results.isEmpty
      ? <String, int>{}
      : StrongsDatabase.extractPhraseSummary(results, strongsNumbers);

  if (kDebugMode) {
    debugPrint(
        '[computeReferenceSearchResult] DONE: ${strongsNumbers.length} Strong\'s numbers, ${results.length} verses, ${phraseSummary.length} phrases');
  }

  return ReferenceSearchComputationResult(
    strongsNumbers: strongsNumbers,
    foundStrongsNumbers: foundStrongs,
    searchResults: results,
    phraseSummary: phraseSummary,
  );
}

class StrongsNumberSearchComputationResult {
  final List<Map<String, dynamic>> searchResults;
  final Map<String, int> phraseSummary;

  const StrongsNumberSearchComputationResult({
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

class ReferenceSearchComputationResult {
  final List<String> strongsNumbers;
  final Map<String, Map<String, dynamic>> foundStrongsNumbers;
  final List<Map<String, dynamic>> searchResults;
  final Map<String, int> phraseSummary;
  final String? error;

  const ReferenceSearchComputationResult({
    this.strongsNumbers = const [],
    this.foundStrongsNumbers = const {},
    this.searchResults = const [],
    this.phraseSummary = const {},
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
