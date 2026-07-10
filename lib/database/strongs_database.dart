import 'package:flutter/foundation.dart';
import "../data/bible_data_strongs.dart";
import "../data/book_metadata.dart";
import "../utils/verse_reference_detector.dart";

class StrongsWordSearchData {
  final List<Map<String, dynamic>> wordVerses;
  final int wordVerseCount;
  final Map<String, Map<String, dynamic>> foundStrongsNumbers;

  const StrongsWordSearchData({
    required this.wordVerses,
    required this.wordVerseCount,
    required this.foundStrongsNumbers,
  });
}

class StrongsBulkSearchData {
  final List<Map<String, dynamic>> searchResults;
  final Map<String, int> phraseSummary;

  const StrongsBulkSearchData({
    required this.searchResults,
    required this.phraseSummary,
  });
}

/// Helper class for searching Strong's Concordance data from bible_data_strongs.dart
class StrongsDatabase {
  static final RegExp _strongTagRegex = RegExp(
    r"\{\{([A-Za-z]\d+)\}\}|\{([A-Za-z]\d+)\}",
    caseSensitive: false,
  );
  static final RegExp _redLetterTagRegex =
      RegExp(r"</?r>", caseSensitive: false);
  static final RegExp _extraSpacesRegex = RegExp(r" +");
  static final RegExp _whitespaceRegex = RegExp(r"\s+");
  static final RegExp _phraseBoundaryRegex = RegExp(r"[.,:;?!¶]+");
  static final RegExp _wordEndingRegex = RegExp(r"[A-Za-z0-9'\-]$");
  static final RegExp _englishWordRegex = RegExp(r"[A-Za-z0-9][A-Za-z0-9'\-]*");
  static final RegExp _strongsNumberInputRegex = RegExp(r"^[HhGg]\d+$");
  static final RegExp _removedMarkupBetweenWordCharactersRegex = RegExp(
    r"[A-Za-z0-9'\-](?:(?:\{\{?[A-Za-z]\d+\}\}?|</?r>))+(?=[A-Za-z0-9'\-])",
    caseSensitive: false,
  );
  static const int _rawTagPrefilterLimit = 8;
  static bool get _verboseSearchLogging => false;

  /// Validates if the input is a Strong's number (HXXXX or GXXXX format)
  /// Returns the normalized Strong's number (uppercase) or null
  static String? validateStrongsNumber(String input) {
    final trimmed = input.trim();
    final match = _strongsNumberInputRegex.firstMatch(trimmed);
    if (match != null) {
      return match.group(0)!.toUpperCase();
    }
    return null;
  }

  static RegExp _wordBoundaryRegex(String word) {
    return RegExp(
      '(^|[^A-Za-z0-9])${RegExp.escape(word)}([^A-Za-z0-9]|\$)',
      caseSensitive: false,
    );
  }

  static _ParsedStrongsTag? _parseStrongTag(RegExpMatch match) {
    final tvmNumber = match.group(1);
    final regularNumber = match.group(2);
    final number = tvmNumber ?? regularNumber;
    if (number == null) return null;
    return _ParsedStrongsTag(
      number: number.toUpperCase(),
      isTvm: tvmNumber != null,
    );
  }

  static String _plainSearchText(String text) {
    var result = text.replaceAll(_strongTagRegex, "");
    result = result.replaceAll(_redLetterTagRegex, "");
    result = result.replaceAll("¶", " ");
    result = result.replaceAll(_extraSpacesRegex, " ");
    return result.trim();
  }

  static bool _plainTextContainsWord(String text, RegExp wordPattern) {
    final rawMatch = wordPattern.hasMatch(text);
    if (!rawMatch && !_removedMarkupBetweenWordCharactersRegex.hasMatch(text)) {
      return false;
    }
    return wordPattern.hasMatch(_plainSearchText(text));
  }

  static String _extractTrailingPhrase(String textBeforeTagGroup) {
    var text = textBeforeTagGroup.replaceAll(_redLetterTagRegex, " ");
    text = text.replaceAll("¶", " ¶ ");
    text = text.replaceAll(_whitespaceRegex, " ");

    final trimmedRight = text.trimRight();
    if (trimmedRight.isEmpty || !_wordEndingRegex.hasMatch(trimmedRight)) {
      return "";
    }

    var phraseStart = 0;
    for (final boundary in _phraseBoundaryRegex.allMatches(trimmedRight)) {
      phraseStart = boundary.end;
    }
    final phraseSegment = trimmedRight.substring(phraseStart);
    return _englishWordRegex
        .allMatches(phraseSegment)
        .map((match) => match.group(0)!)
        .join(" ")
        .trim();
  }

  static List<_StrongsPhraseAssociation> _parsePhraseAssociations(String text) {
    final associations = <_StrongsPhraseAssociation>[];
    _visitPhraseAssociations(text, associations.add);
    return associations;
  }

  static void _visitPhraseAssociations(
    String text,
    void Function(_StrongsPhraseAssociation association) visitor, {
    Set<String>? targetStrongsNumbers,
    bool includeTvm = true,
  }) {
    final tagMatches = _strongTagRegex.allMatches(text).toList();
    var searchStart = 0;
    var index = 0;

    while (index < tagMatches.length) {
      final firstTagMatch = tagMatches[index];
      final groupTags = <_ParsedStrongsTag>[];
      final firstTag = _parseStrongTag(firstTagMatch);
      if (firstTag != null) groupTags.add(firstTag);
      var groupEnd = firstTagMatch.end;
      index++;

      while (index < tagMatches.length) {
        final betweenTags = text.substring(groupEnd, tagMatches[index].start);
        if (betweenTags.trim().isNotEmpty) break;
        final tag = _parseStrongTag(tagMatches[index]);
        if (tag != null) groupTags.add(tag);
        groupEnd = tagMatches[index].end;
        index++;
      }

      final containsTarget = targetStrongsNumbers == null ||
          groupTags.any((tag) =>
              (includeTvm || !tag.isTvm) &&
              targetStrongsNumbers.contains(tag.number));
      if (containsTarget && groupTags.isNotEmpty) {
        final phrase = _extractTrailingPhrase(
            text.substring(searchStart, firstTagMatch.start));
        if (phrase.isNotEmpty) {
          visitor(_StrongsPhraseAssociation(
            phrase: phrase,
            tags: groupTags,
          ));
        }
      }

      searchStart = groupEnd;
    }
  }

  static Set<String> _matchingStrongsInText(
    String text,
    Set<String> strongsNumbers, {
    bool includeTvm = true,
    bool associatedOnly = false,
    Map<String, int>? phraseCounts,
  }) {
    if (strongsNumbers.isEmpty) return {};

    if (associatedOnly) {
      final matched = <String>{};
      _visitPhraseAssociations(
        text,
        (association) {
          var matchCount = 0;
          for (final tag in association.tags) {
            if (!includeTvm && tag.isTvm) continue;
            if (!strongsNumbers.contains(tag.number)) continue;
            matched.add(tag.number);
            matchCount++;
          }
          if (matchCount > 0 && phraseCounts != null) {
            phraseCounts[association.phrase] =
                (phraseCounts[association.phrase] ?? 0) + matchCount;
          }
        },
        targetStrongsNumbers: strongsNumbers,
        includeTvm: includeTvm,
      );
      return matched;
    }

    final matched = <String>{};
    for (final match in _strongTagRegex.allMatches(text)) {
      final tag = _parseStrongTag(match);
      if (tag == null || (!includeTvm && tag.isTvm)) continue;
      if (strongsNumbers.contains(tag.number)) matched.add(tag.number);
    }
    if (matched.isNotEmpty && phraseCounts != null) {
      _addPhraseCountsForText(
        text,
        strongsNumbers,
        phraseCounts,
        includeTvm: includeTvm,
      );
    }
    return matched;
  }

  static void _addPhraseCountsForText(
    String text,
    Set<String> strongsNumbers,
    Map<String, int> phraseCounts, {
    required bool includeTvm,
  }) {
    _visitPhraseAssociations(
      text,
      (association) {
        final matchCount = association.matchingCount(
          strongsNumbers,
          includeTvm: includeTvm,
        );
        if (matchCount == 0) return;
        phraseCounts[association.phrase] =
            (phraseCounts[association.phrase] ?? 0) + matchCount;
      },
      targetStrongsNumbers: strongsNumbers,
      includeTvm: includeTvm,
    );
  }

  static String? _psalmSuperscriptionForChapter(int chapter) {
    final metadata = bookMetadata['Psa $chapter'];
    final title = metadata?['title']?.trim();
    if (title == null || title.isEmpty) return null;

    // Psalm 1 carries the book title in metadata, not a superscription.
    if (chapter == 1 && title == 'THE BOOK OF PSALMS.') return null;
    return title;
  }

  static Map<String, dynamic> _psalmSuperscriptionResult(
    int chapter,
    String text, {
    Iterable<String> matchedStrongs = const [],
  }) {
    return {
      "book": "Psa",
      "chapter": chapter,
      "verse": 0,
      "text": text,
      "isSuperscription": true,
      if (matchedStrongs.isNotEmpty) "matchedStrongs": matchedStrongs.toList(),
    };
  }

  /// Returns all verses that contain a specific Strong's number.
  /// Returns a list of maps with 'book', 'chapter', 'verse', 'text', and 'matchedStrongs' keys.
  static List<Map<String, dynamic>> searchByStrongsNumber(
      String strongsNumber) {
    if (kDebugMode) {
      debugPrint(
          '[_StrongsDatabase] searchByStrongsNumber: starting for "$strongsNumber"');
    }
    final results = <Map<String, dynamic>>[];
    final normalized = strongsNumber.toUpperCase();
    final tagNeedle = '{$normalized}';

    for (final bookEntry in bibleDataStrongs.entries) {
      final book = bookEntry.key;
      final bookData = bookEntry.value;
      for (final chapterEntry in bookData.entries) {
        final chapter = chapterEntry.key;
        if (book == 'Psa') {
          final superscription = _psalmSuperscriptionForChapter(chapter);
          if (superscription != null && superscription.contains(tagNeedle)) {
            results.add(_psalmSuperscriptionResult(
              chapter,
              superscription,
              matchedStrongs: [normalized],
            ));
          }
        }
        for (final verseEntry in chapterEntry.value.entries) {
          final verse = verseEntry.key;
          final text = verseEntry.value;
          if (text.contains(tagNeedle)) {
            results.add({
              "book": book,
              "chapter": chapter,
              "verse": verse,
              "text": text,
              "matchedStrongs": [normalized],
            });
          }
        }
      }
    }
    if (kDebugMode) {
      debugPrint(
          '[_StrongsDatabase] searchByStrongsNumber: found ${results.length} verses for "$strongsNumber"');
    }
    return results;
  }

  /// Searches for a word in the Strong's data and returns all verses containing that word.
  /// Performs case-insensitive search on the text portion (excluding Strong's numbers in braces).
  // static List<Map<String, dynamic>> searchByWord(String word) {
  //   return _searchByWordData(
  //     word,
  //     collectStrongNumbers: false,
  //     collectWordVerses: true,
  //     debugLabel: 'searchByWord',
  //   ).wordVerses;
  // }

  /// Searches for literal word matches and collects the Strong's numbers
  /// directly associated with that word during the same Bible scan.
  static StrongsWordSearchData searchByWordWithStrongsNumbers(
    String word, {
    bool includeWordVerses = true,
  }) {
    return _searchByWordData(
      word,
      collectStrongNumbers: true,
      collectWordVerses: includeWordVerses,
      debugLabel: 'searchByWordWithStrongsNumbers',
    );
  }

  static StrongsWordSearchData _searchByWordData(
    String word, {
    required bool collectStrongNumbers,
    required bool collectWordVerses,
    required String debugLabel,
  }) {
    if (kDebugMode) {
      debugPrint('[_StrongsDatabase] $debugLabel: starting for "$word"');
    }
    final wordVerses = <Map<String, dynamic>>[];
    var wordVerseCount = 0;
    final foundStrongsNumbers = <String, Map<String, dynamic>>{};
    final searchWord = word.toLowerCase().trim();
    if (searchWord.isEmpty) {
      return StrongsWordSearchData(
        wordVerses: wordVerses,
        wordVerseCount: wordVerseCount,
        foundStrongsNumbers: foundStrongsNumbers,
      );
    }
    final wordPattern = _wordBoundaryRegex(searchWord);

    int bookCount = 0;
    for (final bookEntry in bibleDataStrongs.entries) {
      bookCount++;
      final book = bookEntry.key;
      final bookData = bookEntry.value;
      if (kDebugMode && _verboseSearchLogging) {
        debugPrint(
            '[_StrongsDatabase] $debugLabel: scanning book #$bookCount "$book" (${bookData.length} chapters)');
      }
      int chapterCount = 0;
      for (final chapterEntry in bookData.entries) {
        chapterCount++;
        final chapter = chapterEntry.key;
        if (book == 'Psa') {
          final superscription = _psalmSuperscriptionForChapter(chapter);
          if (superscription != null &&
              _plainTextContainsWord(superscription, wordPattern)) {
            wordVerseCount++;
            if (collectWordVerses) {
              wordVerses.add(_psalmSuperscriptionResult(
                chapter,
                superscription,
              ));
            }
            if (collectStrongNumbers) {
              _collectAssociatedStrongsForWord(
                text: superscription,
                wordPattern: wordPattern,
                result: foundStrongsNumbers,
                book: book,
                chapter: chapter,
                verse: 0,
                isSuperscription: true,
              );
            }
          }
        }
        for (final verseEntry in chapterEntry.value.entries) {
          final verse = verseEntry.key;
          final text = verseEntry.value;
          if (!_plainTextContainsWord(text, wordPattern)) continue;

          wordVerseCount++;
          if (collectWordVerses) {
            wordVerses.add({
              "book": book,
              "chapter": chapter,
              "verse": verse,
              "text": text,
            });
          }
          if (collectStrongNumbers) {
            _collectAssociatedStrongsForWord(
              text: text,
              wordPattern: wordPattern,
              result: foundStrongsNumbers,
              book: book,
              chapter: chapter,
              verse: verse,
            );
          }
        }
      }
      if (kDebugMode && _verboseSearchLogging) {
        debugPrint(
            '[_StrongsDatabase] $debugLabel: book "$book" scanned ($chapterCount chapters, $wordVerseCount total matches so far)');
      }
    }
    if (kDebugMode) {
      debugPrint(
          '[_StrongsDatabase] $debugLabel: finished for "$word" — found $wordVerseCount verses and ${foundStrongsNumbers.length} Strong\'s numbers across $bookCount books');
    }
    return StrongsWordSearchData(
      wordVerses: wordVerses,
      wordVerseCount: wordVerseCount,
      foundStrongsNumbers: foundStrongsNumbers,
    );
  }

  /// Extracts the word(s) immediately preceding a Strong's number tag {XXXXX}
  /// in the verse identified by verseReference (e.g., "Gen 1:30").
  /// Returns the phrase (word(s) before the tag) with leading/trailing punctuation and spaces trimmed.
  static String extractPhraseBeforeStrongs(
      String verseReference, String strongsNumber) {
    // Parse the verse reference (e.g., "Gen 1:30")
    final ref = VerseReferenceDetector.detectQuickJumpReference(verseReference);
    if (ref == null) return "";
    if (ref.verse == null) return ""; // Require a specific verse
    final verseText = ref.book == 'Psa' && ref.verse == 0
        ? _psalmSuperscriptionForChapter(ref.chapter)
        : StrongsDatabase.getVerseText(ref.book, ref.chapter, ref.verse!);
    if (verseText == null) return "";
    final normalized = strongsNumber.toUpperCase();
    for (final association in _parsePhraseAssociations(verseText)) {
      if (association.containsStrongsNumber(
        normalized,
        includeTvm: true,
      )) {
        return association.phrase;
      }
    }
    return "";
  }

  /// Finds all unique Strong's numbers associated with a word in the given verses.
  /// Returns a map of Strong's number -> map of (book, chapter, verse) where first found.
  // static Map<String, Map<String, dynamic>> findStrongsNumbersForWord(
  //     String word, List<Map<String, dynamic>> verses) {
  //   if (kDebugMode) {
  //     debugPrint(
  //         '[_StrongsDatabase] findStrongsNumbersForWord: starting for "$word" across ${verses.length} verses');
  //   }
  //   final result = <String, Map<String, dynamic>>{};
  //   final searchWord = word.toLowerCase().trim();
  //   if (searchWord.isEmpty) return result;
  //   final wordPattern = _wordBoundaryRegex(searchWord);

  //   for (final verseData in verses) {
  //     final text = verseData["text"] as String;
  //     final book = verseData["book"] as String;
  //     final chapter = verseData["chapter"] as int;
  //     final isSuperscription = verseData["isSuperscription"] == true;
  //     final verse = isSuperscription ? 0 : verseData["verse"] as int?;

  //     _collectAssociatedStrongsForWord(
  //       text: text,
  //       wordPattern: wordPattern,
  //       result: result,
  //       book: book,
  //       chapter: chapter,
  //       verse: verse,
  //       isSuperscription: isSuperscription,
  //     );
  //   }
  //   if (kDebugMode) {
  //     debugPrint(
  //         '[_StrongsDatabase] findStrongsNumbersForWord: found ${result.length} unique Strong\'s numbers for "$word"');
  //   }
  //   return result;
  // }

  static void _collectAssociatedStrongsForWord({
    required String text,
    required RegExp wordPattern,
    required Map<String, Map<String, dynamic>> result,
    required String book,
    required int chapter,
    required int? verse,
    bool isSuperscription = false,
  }) {
    _visitPhraseAssociations(text, (association) {
      if (!association.hasTrailingWord(wordPattern)) return;

      for (final strongsNum in association.regularStrongsNumbers) {
        result.putIfAbsent(strongsNum, () {
          return {
            "book": book,
            "chapter": chapter,
            "verse": verse,
            if (isSuperscription) "isSuperscription": true,
          };
        });
      }
    });
  }

  /// Returns all verses that contain ANY of the given Strong's numbers.
  /// Returns a list of maps with "book", "chapter", "verse", "text", and "matchedStrongs" keys.
  // static List<Map<String, dynamic>> searchByStrongsNumbers(
  //   List<String> strongsNumbers, {
  //   bool includeTvm = false,
  //   bool associatedOnly = true,
  // }) {
  //   return _searchByStrongsNumbersData(
  //     strongsNumbers,
  //     includeTvm: includeTvm,
  //     associatedOnly: associatedOnly,
  //     includePhraseSummary: false,
  //   ).searchResults;
  // }

  /// Searches for all requested Strong's numbers and accumulates the phrase
  /// summary during the same association traversal.
  static StrongsBulkSearchData searchByStrongsNumbersWithPhraseSummary(
    List<String> strongsNumbers, {
    bool includeTvm = false,
    bool associatedOnly = true,
  }) {
    return _searchByStrongsNumbersData(
      strongsNumbers,
      includeTvm: includeTvm,
      associatedOnly: associatedOnly,
      includePhraseSummary: true,
    );
  }

  static StrongsBulkSearchData _searchByStrongsNumbersData(
    List<String> strongsNumbers, {
    required bool includeTvm,
    required bool associatedOnly,
    required bool includePhraseSummary,
  }) {
    if (kDebugMode) {
      debugPrint(
          '[_StrongsDatabase] searchByStrongsNumbers: starting for ${strongsNumbers.length} Strong\'s numbers: $strongsNumbers (includeTvm=$includeTvm, associatedOnly=$associatedOnly)');
    }
    final results = <Map<String, dynamic>>[];
    final phraseSummary = <String, int>{};
    final normalized = strongsNumbers.map((s) => s.toUpperCase()).toSet();
    if (normalized.isEmpty) {
      return StrongsBulkSearchData(
        searchResults: results,
        phraseSummary: phraseSummary,
      );
    }

    final rawTagPrefilter = normalized.length <= _rawTagPrefilterLimit
        ? RegExp(
            '\\{\\{?(?:${normalized.map(RegExp.escape).join('|')})\\}\\}?',
            caseSensitive: false,
          )
        : null;

    int bookCount = 0;
    for (final bookEntry in bibleDataStrongs.entries) {
      bookCount++;
      final book = bookEntry.key;
      final bookData = bookEntry.value;
      if (kDebugMode && _verboseSearchLogging) {
        debugPrint(
            '[_StrongsDatabase] searchByStrongsNumbers: scanning book #$bookCount "$book" (${bookData.length} chapters, ${results.length} results so far)');
      }
      int chapterCount = 0;
      int matchCountThisBook = 0;
      for (final chapterEntry in bookData.entries) {
        chapterCount++;
        final chapter = chapterEntry.key;
        if (book == 'Psa') {
          final superscription = _psalmSuperscriptionForChapter(chapter);
          if (superscription != null &&
              (rawTagPrefilter == null ||
                  rawTagPrefilter.hasMatch(superscription))) {
            final matchedStrongs = _matchingStrongsInText(
              superscription,
              normalized,
              includeTvm: includeTvm,
              associatedOnly: associatedOnly,
              phraseCounts: includePhraseSummary ? phraseSummary : null,
            );
            if (matchedStrongs.isNotEmpty) {
              matchCountThisBook++;
              results.add(_psalmSuperscriptionResult(
                chapter,
                superscription,
                matchedStrongs: matchedStrongs,
              ));
            }
          }
        }
        for (final verseEntry in chapterEntry.value.entries) {
          final verse = verseEntry.key;
          final text = verseEntry.value;
          if (rawTagPrefilter != null && !rawTagPrefilter.hasMatch(text)) {
            continue;
          }
          final matchedStrongs = _matchingStrongsInText(
            text,
            normalized,
            includeTvm: includeTvm,
            associatedOnly: associatedOnly,
            phraseCounts: includePhraseSummary ? phraseSummary : null,
          );
          if (matchedStrongs.isNotEmpty) {
            matchCountThisBook++;
            results.add({
              "book": book,
              "chapter": chapter,
              "verse": verse,
              "text": text,
              "matchedStrongs": matchedStrongs.toList(),
            });
          }
        }
      }
      if (kDebugMode && _verboseSearchLogging) {
        debugPrint(
            '[_StrongsDatabase] searchByStrongsNumbers: book "$book" done ($chapterCount chapters, $matchCountThisBook matching verses, ${results.length} total)');
      }
    }
    if (kDebugMode) {
      debugPrint(
          '[_StrongsDatabase] searchByStrongsNumbers: finished — found ${results.length} verses across $bookCount books');
    }
    return StrongsBulkSearchData(
      searchResults: results,
      phraseSummary: phraseSummary,
    );
  }

  /// Extracts all phrase occurrences (word(s) before each matched Strong's number)
  /// from a list of verses. Returns phrases exactly as they appear in the data,
  /// mapped to their occurrence counts.
  /// Phrases are the word(s) immediately preceding a Strong's number tag,
  /// with leading/trailing punctuation and extra whitespace stripped.
  static Map<String, int> extractPhraseSummary(
    List<Map<String, dynamic>> verses,
    List<String> strongsNumbers, {
    bool includeTvm = false,
  }) {
    if (kDebugMode) {
      debugPrint(
          '[_StrongsDatabase] extractPhraseSummary: starting for ${strongsNumbers.length} Strong\'s numbers across ${verses.length} verses (includeTvm=$includeTvm)');
    }
    final phraseCounts = <String, int>{};
    final normalizedSet = strongsNumbers.map((s) => s.toUpperCase()).toSet();

    for (final verseData in verses) {
      final text = verseData["text"] as String;
      _addPhraseCountsForText(
        text,
        normalizedSet,
        phraseCounts,
        includeTvm: includeTvm,
      );
    }
    if (kDebugMode) {
      debugPrint(
          '[_StrongsDatabase] extractPhraseSummary: finished — ${phraseCounts.length} unique phrases');
    }
    return phraseCounts;
  }

  /// Strips ALL Strong's number tags from verse text (e.g., {H1285} -> "").
  /// Also collapses multiple spaces left behind from adjacent strongs tags.
  // static String stripAllStrongsTags(String text) {
  //   String result = text.replaceAll(_strongTagRegex, "");
  //   // Remove extra spaces from adjacent removed tags (e.g., "{H1916} {H7272}" -> "  " -> " ")
  //   result = result.replaceAll(_extraSpacesRegex, " ");
  //   return result.trim();
  // }

  /// Returns all valid book names in the bible data.
  static List<String> getAvailableBooks() {
    return bibleDataStrongs.keys.toList();
  }

  /// Returns all valid chapter numbers for a given book.
  /// Returns empty list if book is invalid.
  static List<int> getAvailableChapters(String book) {
    final bookData = bibleDataStrongs[book];
    if (bookData == null) return [];
    return bookData.keys.toList()..sort();
  }

  /// Returns all valid verse numbers for a given book and chapter.
  /// Returns empty list if book or chapter is invalid.
  static List<int> getAvailableVerses(String book, int chapter) {
    final bookData = bibleDataStrongs[book];
    if (bookData == null) return [];
    final chapterData = bookData[chapter];
    if (chapterData == null) return [];
    return chapterData.keys.toList()..sort();
  }

  /// Gets the verse text for a specific reference.
  /// Returns null if any part of the reference is invalid.
  static String? getVerseText(String book, int chapter, int verse) {
    final bookData = bibleDataStrongs[book];
    if (bookData == null) return null;
    final chapterData = bookData[chapter];
    if (chapterData == null) return null;
    return chapterData[verse];
  }

  /// Finds Strong's numbers for a specific word in a specific verse.
  /// Returns a list of Strong's numbers found, or empty list if word not found.
  static List<String> findStrongsNumbersForWordInVerse(
    String book,
    int chapter,
    int verse,
    String word, {
    bool usePhraseFallback = false,
  }) {
    final verseText = getVerseText(book, chapter, verse);
    if (verseText == null) return [];

    final searchWord = word.toLowerCase().trim();
    if (searchWord.isEmpty) return [];

    final result = <String>{};
    final wordPattern = _wordBoundaryRegex(searchWord);
    final associations = _parsePhraseAssociations(verseText);

    for (final association in associations) {
      if (!association.hasTrailingWord(wordPattern)) continue;

      for (final strongsNum in association.regularStrongsNumbers) {
        result.add(strongsNum);
      }
    }

    if (result.isEmpty && usePhraseFallback) {
      for (final association in associations) {
        if (!association.containsWord(wordPattern)) continue;

        for (final strongsNum in association.regularStrongsNumbers) {
          result.add(strongsNum);
        }
      }
    }

    return result.toList();
  }

  /// Validates if a word exists in a specific verse.
  static bool wordExistsInVerse(
      String book, int chapter, int verse, String word) {
    final verseText = getVerseText(book, chapter, verse);
    if (verseText == null) return false;

    final searchWord = word.toLowerCase().trim();
    if (searchWord.isEmpty) return false;
    return _wordBoundaryRegex(searchWord).hasMatch(_plainSearchText(verseText));
  }
}

class _ParsedStrongsTag {
  final String number;
  final bool isTvm;

  const _ParsedStrongsTag({
    required this.number,
    required this.isTvm,
  });
}

class _StrongsPhraseAssociation {
  final String phrase;
  final List<_ParsedStrongsTag> tags;

  const _StrongsPhraseAssociation({
    required this.phrase,
    required this.tags,
  });

  Iterable<String> get regularStrongsNumbers =>
      tags.where((tag) => !tag.isTvm).map((tag) => tag.number);

  bool hasTrailingWord(RegExp wordPattern) {
    final words = StrongsDatabase._englishWordRegex.allMatches(phrase);
    if (words.isEmpty) return false;
    return wordPattern.hasMatch(words.last.group(0)!);
  }

  bool containsWord(RegExp wordPattern) => wordPattern.hasMatch(phrase);

  bool containsStrongsNumber(
    String strongsNumber, {
    required bool includeTvm,
  }) {
    return tags.any(
        (tag) => tag.number == strongsNumber && (includeTvm || !tag.isTvm));
  }

  int matchingCount(
    Set<String> strongsNumbers, {
    required bool includeTvm,
  }) {
    var count = 0;
    for (final tag in tags) {
      if (!includeTvm && tag.isTvm) continue;
      if (strongsNumbers.contains(tag.number)) {
        count++;
      }
    }
    return count;
  }
}
