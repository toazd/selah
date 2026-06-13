import 'package:flutter/foundation.dart';
import "../data/bible_data_strongs.dart";
import "../utils/verse_reference_detector.dart";

/// Helper class for searching Strong's Concordance data from bible_data_strongs.dart
class StrongsDatabase {
  /// Validates if the input is a Strong's number (HXXXX or GXXXX format)
  /// Returns the normalized Strong's number (uppercase) or null
  static String? validateStrongsNumber(String input) {
    final trimmed = input.trim();
    final match = RegExp(r"^[HhGg]\d+$").firstMatch(trimmed);
    if (match != null) {
      return match.group(0)!.toUpperCase();
    }
    return null;
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

    for (final book in bibleDataStrongs.keys) {
      final bookData = bibleDataStrongs[book]!;
      for (final chapter in bookData.keys) {
        final chapterData = bookData[chapter]!;
        for (final verse in chapterData.keys) {
          final text = chapterData[verse]!;
          if (text.contains("{$normalized}")) {
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
  static List<Map<String, dynamic>> searchByWord(String word) {
    if (kDebugMode) {
      debugPrint('[_StrongsDatabase] searchByWord: starting for "$word"');
    }
    final results = <Map<String, dynamic>>[];
    final searchWord = word.toLowerCase().trim();
    if (searchWord.isEmpty) return results;

    int bookCount = 0;
    for (final book in bibleDataStrongs.keys) {
      bookCount++;
      final bookData = bibleDataStrongs[book]!;
      if (kDebugMode) {
        debugPrint(
            '[_StrongsDatabase] searchByWord: scanning book #$bookCount "$book" (${bookData.length} chapters)');
      }
      int chapterCount = 0;
      for (final chapter in bookData.keys) {
        chapterCount++;
        final chapterData = bookData[chapter]!;
        for (final verse in chapterData.keys) {
          final text = chapterData[verse]!;
          // Strip Strong's numbers for word search
          final cleanText = text.replaceAll(RegExp(r"\{[A-Za-z]\d+\}"), "");
          // Also handle curly braces that may have leading spaces
          final searchableText = cleanText.toLowerCase();

          // Use word boundary matching for the search word
          if (RegExp(r"\b" + RegExp.escape(searchWord) + r"\b")
              .hasMatch(searchableText)) {
            results.add({
              "book": book,
              "chapter": chapter,
              "verse": verse,
              "text": text,
            });
          }
        }
      }
      if (kDebugMode) {
        debugPrint(
            '[_StrongsDatabase] searchByWord: book "$book" scanned ($chapterCount chapters, ${results.length} total matches so far)');
      }
    }
    if (kDebugMode) {
      debugPrint(
          '[_StrongsDatabase] searchByWord: finished for "$word" — found ${results.length} verses across $bookCount books');
    }
    return results;
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
    final verseText =
        StrongsDatabase.getVerseText(ref.book, ref.chapter, ref.verse!);
    if (verseText == null) return "";
    final normalized = strongsNumber.toUpperCase();
    final escaped = RegExp.escape(normalized);
    final pattern = RegExp(
      "([A-Za-z'\\-]+(?:\\s+[A-Za-z'\\-]+)*)" // words
      "(?:\\s*\\{[A-Za-z]\\d+\\}\\s*)*" // optional other Strong's tags
      "\\{$escaped\\}", // the target Strong's number
    );
    final match = pattern.firstMatch(verseText);
    if (match != null) {
      var phrase = match.group(1)!.trim();
      // Remove leading/trailing punctuation (non-alphanumeric and non-apostrophe)
      phrase =
          phrase.replaceAll(RegExp(r"^[^A-Za-z0-9']+|[^A-Za-z0-9']+$"), "");
      return phrase;
    }
    return "";
  }

  /// Finds all unique Strong's numbers associated with a word in the given verses.
  /// Returns a map of Strong's number -> map of (book, chapter, verse) where first found.
  static Map<String, Map<String, dynamic>> findStrongsNumbersForWord(
      String word, List<Map<String, dynamic>> verses) {
    if (kDebugMode) {
      debugPrint(
          '[_StrongsDatabase] findStrongsNumbersForWord: starting for "$word" across ${verses.length} verses');
    }
    final result = <String, Map<String, dynamic>>{};
    final searchWord = word.toLowerCase().trim();
    if (searchWord.isEmpty) return result;

    for (final verseData in verses) {
      final text = verseData["text"] as String;
      final book = verseData["book"] as String;
      final chapter = verseData["chapter"] as int;
      final verse = verseData["verse"] as int;

      // Find all instances of the word followed by one or more consecutive
      // Strong's numbers and capture ALL of them.
      // Pattern: word {SN} {SN} {SN}...
      final pattern = RegExp(
        RegExp.escape(searchWord) + r"((?:\s*\{[A-Za-z]\d+\})+)",
        caseSensitive: false,
      );

      for (final match in pattern.allMatches(text)) {
        final tagGroup = match.group(1)!;
        final snMatches = RegExp(r'\{([A-Za-z]\d+)\}').allMatches(tagGroup);
        for (final snMatch in snMatches) {
          final strongsNum = snMatch.group(1)!.toUpperCase();
          if (!result.containsKey(strongsNum)) {
            result[strongsNum] = {
              "book": book,
              "chapter": chapter,
              "verse": verse,
            };
          }
        }
      }
    }
    if (kDebugMode) {
      debugPrint(
          '[_StrongsDatabase] findStrongsNumbersForWord: found ${result.length} unique Strong\'s numbers for "$word"');
    }
    return result;
  }

  /// Returns all verses that contain ANY of the given Strong's numbers.
  /// Returns a list of maps with "book", "chapter", "verse", "text", and "matchedStrongs" keys.
  static List<Map<String, dynamic>> searchByStrongsNumbers(
      List<String> strongsNumbers) {
    if (kDebugMode) {
      debugPrint(
          '[_StrongsDatabase] searchByStrongsNumbers: starting for ${strongsNumbers.length} Strong\'s numbers: $strongsNumbers');
    }
    final results = <Map<String, dynamic>>[];
    final normalized = strongsNumbers.map((s) => s.toUpperCase()).toSet();

    int bookCount = 0;
    for (final book in bibleDataStrongs.keys) {
      bookCount++;
      final bookData = bibleDataStrongs[book]!;
      if (kDebugMode) {
        debugPrint(
            '[_StrongsDatabase] searchByStrongsNumbers: scanning book #$bookCount "$book" (${bookData.length} chapters, ${results.length} results so far)');
      }
      int chapterCount = 0;
      int matchCountThisBook = 0;
      for (final chapter in bookData.keys) {
        chapterCount++;
        final chapterData = bookData[chapter]!;
        for (final verse in chapterData.keys) {
          final text = chapterData[verse]!;
          final matchedStrongs = <String>{};
          for (final sn in normalized) {
            if (text.contains("{$sn}")) {
              matchedStrongs.add(sn);
            }
          }
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
      if (kDebugMode) {
        debugPrint(
            '[_StrongsDatabase] searchByStrongsNumbers: book "$book" done ($chapterCount chapters, $matchCountThisBook matching verses, ${results.length} total)');
      }
    }
    if (kDebugMode) {
      debugPrint(
          '[_StrongsDatabase] searchByStrongsNumbers: finished — found ${results.length} verses across $bookCount books');
    }
    return results;
  }

  /// Extracts all phrase occurrences (word(s) before each matched Strong's number)
  /// from a list of verses. Returns a map of lowercase phrase -> count.
  /// Phrases are the word(s) immediately preceding a Strong's number tag,
  /// with leading/trailing punctuation and extra whitespace stripped.
  static Map<String, int> extractPhraseSummary(
      List<Map<String, dynamic>> verses, List<String> strongsNumbers) {
    if (kDebugMode) {
      debugPrint(
          '[_StrongsDatabase] extractPhraseSummary: starting for ${strongsNumbers.length} Strong\'s numbers across ${verses.length} verses');
    }
    final phraseCounts = <String, int>{};
    final normalizedSet = strongsNumbers.map((s) => s.toUpperCase()).toSet();

    for (final verseData in verses) {
      final text = verseData["text"] as String;
      for (final sn in normalizedSet) {
        final escaped = RegExp.escape(sn);
        // This pattern captures words before a Strong's number, allowing other
        // Strong's number tags (e.g., {H1167}) between the words and the target.
        // It matches: (words) followed by optional {OTHER_STRONG}* followed by {TARGET}
        final pattern = RegExp(
          "([A-Za-z'\\-]+(?:\\s+[A-Za-z'\\-]+)*)" // words
          "(?:\\s*\\{[A-Za-z]\\d+\\}\\s*)*" // optional other Strong's tags
          "\\{$escaped\\}", // the target Strong's number
        );
        for (final match in pattern.allMatches(text)) {
          String phrase = match.group(1)!.trim();
          //debugPrint(phrase);
          // remove common words to help collapse large lists
          //phrase = phrase.replaceAll(RegExp(r"\bAnd\b"), "");
          //phrase = phrase.replaceAll(RegExp(r"\bA\b"), "");
          // Strip leading/trailing punctuation, commas, hyphens
          phrase =
              phrase.replaceAll(RegExp(r"^[^A-Za-z0-9]+|[^A-Za-z0-9]+$"), "");
          if (phrase.isNotEmpty) {
            phraseCounts[phrase.toLowerCase()] =
                (phraseCounts[phrase.toLowerCase()] ?? 0) + 1;
          }
        }
      }
    }
    if (kDebugMode) {
      debugPrint(
          '[_StrongsDatabase] extractPhraseSummary: finished — ${phraseCounts.length} unique phrases');
    }
    return phraseCounts;
  }

  /// Strips ALL Strong's number tags from verse text (e.g., {H1285} -> "").
  /// Also collapses multiple spaces left behind from adjacent strongs tags.
  static String stripAllStrongsTags(String text) {
    String result = text.replaceAll(RegExp(r"\{[A-Za-z]\d+\}"), "");
    // Remove extra spaces from adjacent removed tags (e.g., "{H1916} {H7272}" -> "  " -> " ")
    result = result.replaceAll(RegExp(r" +"), " ");
    return result.trim();
  }

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
      String book, int chapter, int verse, String word) {
    final verseText = getVerseText(book, chapter, verse);
    if (verseText == null) return [];

    final searchWord = word.toLowerCase().trim();
    if (searchWord.isEmpty) return [];

    final result = <String>{};

    // Find all instances of the word followed by one or more consecutive
    // Strong's numbers and capture ALL of them.
    final pattern = RegExp(
      RegExp.escape(searchWord) + r"((?:\s*\{[A-Za-z]\d+\})+)",
      caseSensitive: false,
    );

    for (final match in pattern.allMatches(verseText)) {
      final tagGroup = match.group(1)!;
      final snMatches = RegExp(r'\{([A-Za-z]\d+)\}').allMatches(tagGroup);
      for (final snMatch in snMatches) {
        final strongsNum = snMatch.group(1)!.toUpperCase();
        result.add(strongsNum);
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

    // Strip Strong's numbers for word search
    final cleanText = verseText.replaceAll(RegExp(r"\{[A-Za-z]\d+\}"), "");
    final searchableText = cleanText.toLowerCase();

    // Use word boundary matching
    return RegExp(r"\b" + RegExp.escape(searchWord) + r"\b")
        .hasMatch(searchableText);
  }
}
