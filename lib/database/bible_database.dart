import '../data/bible_data_strongs.dart';
import '../data/book_metadata.dart';

class BibleDatabase {
  // Get all book names in canonical order
  static Future<List<String>> getBooks() async {
    return bibleDataStrongs.keys.toList();
  }

  // Get all chapters for a book
  static Future<List<int>> getChapters(String bookShortName) async {
    final bookData = bibleDataStrongs[bookShortName];
    if (bookData == null) return [];
    return bookData.keys.toList();
  }

  // Get all verses for a book/chapter
  static Future<List<Map<String, dynamic>>> getVerses(
      String bookShortName, int chapter) async {
    final bookData = bibleDataStrongs[bookShortName];
    if (bookData == null) return [];

    final chapterData = bookData[chapter];
    if (chapterData == null) return [];

    return chapterData.entries.map((entry) {
      return {
        'book': bookShortName,
        'chapter': chapter,
        'verse': entry.key,
        'text': entry.value,
      };
    }).toList();
  }

  // Search verses with pre-filter keywords
  // static Future<List<Map<String, dynamic>>> searchVerses({
  //   List<String> preFilterKeywords = const [],
  //   bool useOrLogic = false,
  //   bool caseSensitive = false,
  // }) async {
  //   if (preFilterKeywords.isEmpty) return [];

  //   final results = <Map<String, dynamic>>[];

  //   for (final book in bibleDataStrongs.keys) {
  //     final bookData = bibleDataStrongs[book]!;
  //     for (final chapter in bookData.keys) {
  //       final chapterData = bookData[chapter]!;
  //       for (final verse in chapterData.keys) {
  //         final text = caseSensitive
  //             ? chapterData[verse]!
  //             : chapterData[verse]!.toLowerCase();

  //         bool matches = true;
  //         if (useOrLogic) {
  //           // OR logic: at least one keyword must be present
  //           matches = false;
  //           for (final keyword in preFilterKeywords) {
  //             final checkKeyword = caseSensitive
  //                 ? keyword
  //                 : keyword
  //                     .toLowerCase(); // Only lowercase keyword if not case-sensitive
  //             if (text.contains(checkKeyword)) {
  //               matches = true;
  //               break;
  //             }
  //           }
  //         } else {
  //           // AND logic: count occurrences of each keyword
  //           final keywordCounts = <String, int>{};
  //           for (final keyword in preFilterKeywords) {
  //             final key = caseSensitive ? keyword : keyword.toLowerCase();
  //             keywordCounts[key] = (keywordCounts[key] ?? 0) + 1;
  //           }

  //           for (final entry in keywordCounts.entries) {
  //             final keyword = entry.key;
  //             final requiredCount = entry.value;
  //             final actualCount = keyword.allMatches(text).length;
  //             if (actualCount < requiredCount) {
  //               matches = false;
  //               break;
  //             }
  //           }
  //         }

  //         if (matches) {
  //           results.add({
  //             'book': book,
  //             'chapter': chapter,
  //             'verse': verse,
  //             'text': chapterData[verse]!,
  //           });
  //         }
  //       }
  //     }
  //   }

  //   return results;
  // }

  // Get all verses
  static Future<List<Map<String, dynamic>>> getAllVerses() async {
    final results = <Map<String, dynamic>>[];

    for (final book in bibleDataStrongs.keys) {
      final bookData = bibleDataStrongs[book]!;
      for (final chapter in bookData.keys) {
        final chapterData = bookData[chapter]!;
        for (final verse in chapterData.keys) {
          results.add({
            'book': book,
            'chapter': chapter,
            'verse': verse,
            'text': chapterData[verse]!,
          });
        }
      }
    }

    return results;
  }

  // Get book metadata (title, colophon)
  static Future<Map<String, dynamic>?> getBookMetadata(String bookShortName,
      {int? chapter}) async {
    // Try the specific Psalm lookup first if chapter is provided and book starts with 'Psa'
    if (chapter != null && bookShortName == 'Psa') {
      final psalmSpecificKey = '$bookShortName $chapter';
      final psalmMetadata = bookMetadata[psalmSpecificKey];
      if (psalmMetadata != null) {
        return {
          'book': bookShortName,
          'title': psalmMetadata['title'],
          'colophon': psalmMetadata['colophon'],
        };
      }
      return null;
    }

    // Fallback to regular book lookup
    final metadata = bookMetadata[bookShortName];
    if (metadata == null) return null;

    return {
      'book': bookShortName,
      'title': metadata['title'],
      'colophon': metadata['colophon'],
    };
  }
}
