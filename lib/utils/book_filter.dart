import 'book_name_converter.dart';
import '../database/bible_database.dart';

/// Utility class for parsing and validating book filter specifications
class BookFilter {
  /// Predefined book categories with their short name ranges
  static const Map<String, List<String>> predefinedCategories = {
    'All Books': [], // Empty list means no filtering
    'Old Testament': [
      'Gen',
      'Exo',
      'Lev',
      'Num',
      'Deu',
      'Jos',
      'Jdg',
      'Rth',
      '1Sa',
      '2Sa',
      '1Ki',
      '2Ki',
      '1Ch',
      '2Ch',
      'Ezr',
      'Neh',
      'Est',
      'Job',
      'Psa',
      'Pro',
      'Ecc',
      'Son',
      'Isa',
      'Jer',
      'Lam',
      'Eze',
      'Dan',
      'Hos',
      'Joe',
      'Amo',
      'Oba',
      'Jon',
      'Mic',
      'Nah',
      'Hab',
      'Zep',
      'Hag',
      'Zec',
      'Mal'
    ],
    'New Testament': [
      'Mat',
      'Mar',
      'Luk',
      'Joh',
      'Act',
      'Rom',
      '1Co',
      '2Co',
      'Gal',
      'Eph',
      'Phi',
      'Col',
      '1Th',
      '2Th',
      '1Ti',
      '2Ti',
      'Tit',
      'Phm',
      'Heb',
      'Jam',
      '1Pe',
      '2Pe',
      '1Jo',
      '2Jo',
      '3Jo',
      'Jud',
      'Rev'
    ],
    'Pentateuch/Torah': ['Gen', 'Exo', 'Lev', 'Num', 'Deu'],
    'Historical Books': [
      'Jos',
      'Jdg',
      'Rth',
      '1Sa',
      '2Sa',
      '1Ki',
      '2Ki',
      '1Ch',
      '2Ch',
      'Ezr',
      'Neh',
      'Est'
    ],
    'Poetry': ['Job', 'Psa', 'Pro', 'Ecc', 'Son'],
    'Major Prophets': ['Isa', 'Jer', 'Lam', 'Eze', 'Dan'],
    'Minor Prophets': [
      'Hos',
      'Joe',
      'Amo',
      'Oba',
      'Jon',
      'Mic',
      'Nah',
      'Hab',
      'Zep',
      'Hag',
      'Zec',
      'Mal'
    ],
    'Gospels': ['Mat', 'Mar', 'Luk', 'Joh'],
    'Acts': ['Act'],
    'Pauline Epistles': [
      'Rom',
      '1Co',
      '2Co',
      'Gal',
      'Eph',
      'Phi',
      'Col',
      '1Th',
      '2Th',
      '1Ti',
      '2Ti',
      'Tit',
      'Phm',
      'Heb'
    ],
    'General Epistles': ['Jam', '1Pe', '2Pe', '1Jo', '2Jo', '3Jo', 'Jud'],
    'Revelation': ['Rev'],
    'Law': ['Gen', 'Exo', 'Lev', 'Num', 'Deu'],
    'Prophets': [
      'Isa',
      'Jer',
      'Lam',
      'Eze',
      'Dan',
      'Hos',
      'Joe',
      'Amo',
      'Oba',
      'Jon',
      'Mic',
      'Nah',
      'Hab',
      'Zep',
      'Hag',
      'Zec',
      'Mal'
    ],
    'Wisdom': ['Job', 'Psa', 'Pro', 'Ecc'],
  };

  /// Get display names for dropdown options
  static List<String> get categoryDisplayNames =>
      predefinedCategories.keys.toList();

  /// Parse a custom range specification and return list of allowed book short names
  /// Supports formats like: "Psa 119, Pro 1-20, Gen-Deu, Mat 22 - John 21"
  static Future<BookFilterResult> parseCustomRange(String input) async {
    if (input.trim().isEmpty) {
      return BookFilterResult.error('Invalid book/range');
    }

    final specifications = input
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final allowedBooks = <String>{};
    final allowedChapters =
        <String, Set<int>>{}; // book -> set of allowed chapters

    for (final spec in specifications) {
      final parseResult = await _parseSingleSpecification(spec);
      if (parseResult.error != null) {
        return BookFilterResult.error(parseResult.error!);
      }

      allowedBooks.addAll(parseResult.books);
      // Merge chapter restrictions
      for (final entry in parseResult.chapters.entries) {
        allowedChapters[entry.key] ??= {};
        allowedChapters[entry.key]!.addAll(entry.value);
      }
    }

    return BookFilterResult.success(allowedBooks.toList(), allowedChapters);
  }

  /// Parse a single specification (e.g., "Psa 119", "Pro 1-20", "Gen-Deu")
  static Future<_ParseResult> _parseSingleSpecification(String spec) async {
    // Pattern 1: Single-book chapter range (e.g., "Num 10-20", "Psa 1-150")
    if (spec.contains(' ')) {
      final spaceIndex = spec.indexOf(' ');
      final afterSpace = spec.substring(spaceIndex + 1);
      if (afterSpace.contains('-') &&
          RegExp(r'^\d+-\d+$').hasMatch(afterSpace)) {
        return _parseBookWithChapters(spec);
      }
    }

    // Pattern 2: Book range (e.g., "Gen-Deu", "Mat 22 - John 21")
    if (spec.contains('-')) {
      return _parseBookRange(spec);
    }

    // Pattern 3: Book with a single chapter
    if (spec.contains(' ')) {
      return _parseBookWithChapters(spec);
    }

    // Pattern 4: Single book name
    return _parseSingleBook(spec);
  }

  /// Parse book range like "Gen-Deu", "Mat 22 - John 21", "Mat 22 - John 8-10"
  static Future<_ParseResult> _parseBookRange(String range) async {
    // Find the first dash that's NOT part of a chapter range (\d-\d+)
    int? separatorIndex;
    for (int i = 0; i < range.length; i++) {
      if (range[i] == '-') {
        // Check if this dash is part of a chapter range (digits on both sides)
        bool isChapterRange = (i > 0 && i < range.length - 1) &&
            RegExp(r'\d').hasMatch(range[i - 1]) &&
            RegExp(r'\d').hasMatch(range[i + 1]);
        if (!isChapterRange) {
          // Found the range separator!
          separatorIndex = i;
          break;
        }
      }
    }

    if (separatorIndex == null) {
      return _ParseResult.error('No valid range separator found in: $range');
    }

    // Split on the separator
    final leftSpec = range.substring(0, separatorIndex).trim();
    final rightSpec = range.substring(separatorIndex + 1).trim();

    // Parse each side as a book spec
    final startSpecResult = _parseBookSpec(leftSpec);
    final endSpecResult = _parseBookSpec(rightSpec);

    if (startSpecResult.error != null) {
      return _ParseResult.error(startSpecResult.error!);
    }
    if (endSpecResult.error != null) {
      return _ParseResult.error(endSpecResult.error!);
    }

    final startBook = startSpecResult.book!;
    final endBook = endSpecResult.book!;
    final startChapter = startSpecResult.startChapter;
    final endChapter = endSpecResult.endChapter;

    final allBooks = predefinedCategories['Old Testament']! +
        predefinedCategories['New Testament']!;
    final startIndex = allBooks.indexOf(startBook);
    final endIndex = allBooks.indexOf(endBook);

    if (startIndex == -1 || endIndex == -1) {
      return _ParseResult.error('Book not found in Bible: $range');
    }

    if (startIndex > endIndex) {
      return _ParseResult.error('Start book must come before end book: $range');
    }

    // Validate chapter numbers if specified
    if (startChapter != null) {
      final startBookChapters = await BibleDatabase.getChapters(startBook);
      if (!startBookChapters.contains(startChapter)) {
        return _ParseResult.error(
            'Invalid chapter number for $startBook: $startChapter');
      }
    }

    if (endChapter != null) {
      final endBookChapters = await BibleDatabase.getChapters(endBook);
      if (!endBookChapters.contains(endChapter)) {
        return _ParseResult.error(
            'Invalid chapter number for $endBook: $endChapter');
      }
    }

    // Get all books in range
    final booksInRange = allBooks.sublist(startIndex, endIndex + 1);

    // Create chapter restrictions for partial books
    final chapters = <String, Set<int>>{};

    if (startIndex == endIndex && startChapter != null && endChapter != null) {
      // Same book with chapter range: add all chapters between start and end
      final bookChapters = await BibleDatabase.getChapters(startBook);
      chapters[startBook] = bookChapters
          .where((ch) => ch >= startChapter && ch <= endChapter)
          .toSet();
    } else {
      // Different books or partial chapter specs
      // Start book: restrict to chapters >= startChapter if specified
      if (startChapter != null) {
        final startBookChapters = await BibleDatabase.getChapters(startBook);
        chapters[startBook] =
            startBookChapters.where((ch) => ch >= startChapter).toSet();
      }

      // Middle books: no restrictions (include all chapters)

      // End book: restrict to chapters <= endChapter if specified
      if (endChapter != null && (startBook != endBook)) {
        final endBookChapters = await BibleDatabase.getChapters(endBook);
        chapters[endBook] =
            endBookChapters.where((ch) => ch <= endChapter).toSet();
      }
    }

    return _ParseResult.success(booksInRange, chapters);
  }

  /// Parse a book specification that may include a chapter or chapter range
  /// Accepts formats like "Gen", "Mat 22", "Mat 8-10", "Genesis 1", etc.
  static _BookSpecResult _parseBookSpec(String spec) {
    // Check if spec contains spaces (indicating chapter specification)
    final parts = spec.split(' ');
    if (parts.length == 1) {
      // Just book name
      final bookName = _normalizeBookName(spec);
      if (bookName == null) {
        return _BookSpecResult.error('Invalid book name: $spec');
      }
      return _BookSpecResult.success(bookName);
    } else if (parts.length == 2) {
      // Book name + chapter or chapter range
      final bookName = _normalizeBookName(parts[0]);
      if (bookName == null) {
        return _BookSpecResult.error('Invalid book name: ${parts[0]}');
      }

      final chapterSpec = parts[1];
      if (chapterSpec.contains('-')) {
        // Chapter range like "8-10"
        final rangeParts = chapterSpec.split('-');
        if (rangeParts.length != 2) {
          return _BookSpecResult.error('Invalid chapter range: $chapterSpec');
        }
        final startChapter = int.tryParse(rangeParts[0]);
        final endChapter = int.tryParse(rangeParts[1]);
        if (startChapter == null || endChapter == null) {
          return _BookSpecResult.error('Invalid chapter numbers: $chapterSpec');
        }
        if (startChapter > endChapter) {
          return _BookSpecResult.error(
              'Start chapter must be before end chapter: $chapterSpec');
        }
        return _BookSpecResult.success(bookName, startChapter, endChapter);
      } else {
        // Single chapter
        final chapter = int.tryParse(chapterSpec);
        if (chapter == null) {
          return _BookSpecResult.error('Invalid chapter number: $chapterSpec');
        }
        return _BookSpecResult.success(bookName, chapter, chapter);
      }
    } else {
      return _BookSpecResult.error('Invalid book specification: $spec');
    }
  }

  /// Parse book with chapter specification like "Psa 119" or "Pro 1-20"
  static _ParseResult _parseBookWithChapters(String spec) {
    final parts = spec.split(' ');
    if (parts.length != 2) {
      return _ParseResult.error('Invalid book chapter format: $spec');
    }

    final bookName = _normalizeBookName(parts[0].trim());
    if (bookName == null) {
      return _ParseResult.error('Invalid book name: ${parts[0]}');
    }

    final chapterSpec = parts[1].trim();
    final chapters = <int>{};

    if (chapterSpec.contains('-')) {
      // Chapter range like "1-20"
      final rangeParts = chapterSpec.split('-');
      if (rangeParts.length != 2) {
        return _ParseResult.error('Invalid chapter range: $chapterSpec');
      }

      final startChapter = int.tryParse(rangeParts[0].trim());
      final endChapter = int.tryParse(rangeParts[1].trim());

      if (startChapter == null || endChapter == null) {
        return _ParseResult.error('Invalid chapter numbers: $chapterSpec');
      }

      if (startChapter > endChapter) {
        return _ParseResult.error(
            'Start chapter must be before end chapter: $chapterSpec');
      }

      for (int i = startChapter; i <= endChapter; i++) {
        chapters.add(i);
      }
    } else {
      // Single chapter like "119"
      final chapter = int.tryParse(chapterSpec);
      if (chapter == null) {
        return _ParseResult.error('Invalid chapter number: $chapterSpec');
      }
      chapters.add(chapter);
    }

    return _ParseResult.success([bookName], {bookName: chapters});
  }

  /// Parse single book like "Psa" or "Genesis"
  static _ParseResult _parseSingleBook(String bookName) {
    final normalized = _normalizeBookName(bookName.trim());
    if (normalized == null) {
      return _ParseResult.error('Invalid book name: $bookName');
    }
    return _ParseResult.success([normalized]);
  }

  /// Normalize book name to database short name using BookNameConverter
  /// Handles common variations and abbreviations
  static String? _normalizeBookName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;

    // First, check if input matches any canonical short name (case-insensitive)
    final allBooks = predefinedCategories['Old Testament']! +
        predefinedCategories['New Testament']!;
    for (final shortName in allBooks) {
      if (shortName.toLowerCase() == trimmed.toLowerCase()) {
        return shortName; // Return canonical case
      }
    }

    // Try full name conversion via BookNameConverter
    try {
      final result = BookNameConverter.longNameToShortName(trimmed);
      if (result != trimmed) {
        // If it was successfully converted (full name to short name)
        return result;
      }
    } catch (e) {
      // Continue to try variations
    }

    // Try common variations and abbreviations
    final variations = _getBookNameVariations(trimmed);
    for (final variation in variations) {
      // Check if variation is already a canonical short name
      for (final shortName in allBooks) {
        if (shortName.toLowerCase() == variation.toLowerCase()) {
          return shortName;
        }
      }

      // Try full name conversion on variation
      try {
        final result = BookNameConverter.longNameToShortName(variation);
        if (result != variation) {
          return result;
        }
      } catch (e) {
        continue;
      }
    }

    return null; // No valid book name found
  }

  /// Get common variations for a book name to try
  static List<String> _getBookNameVariations(String name) {
    final lower = name.toLowerCase();
    final variations = <String>[name]; // Include original

    // Comprehensive mapping of abbreviations and variations to canonical short names
    final abbreviationMap = {
      // Old Testament
      'gen': 'Gen',
      'genesis': 'Gen',
      'exo': 'Exo',
      'exod': 'Exo',
      'exodus': 'Exo',
      'lev': 'Lev',
      'leviticus': 'Lev',
      'num': 'Num',
      'numbers': 'Num',
      'deu': 'Deu',
      'deut': 'Deu',
      'deuteronomy': 'Deu',
      'jos': 'Jos',
      'josh': 'Jos',
      'joshua': 'Jos',
      'jdg': 'Jdg',
      'judg': 'Jdg',
      'judges': 'Jdg',
      'rth': 'Rth',
      'ruth': 'Rth',
      '1sa': '1Sa',
      '1sam': '1Sa',
      '1samuel': '1Sa',
      '2sa': '2Sa',
      '2sam': '2Sa',
      '2samuel': '2Sa',
      '1ki': '1Ki',
      '1kings': '1Ki',
      '2ki': '2Ki',
      '2kings': '2Ki',
      '1ch': '1Ch',
      '1chron': '1Ch',
      '1chronicles': '1Ch',
      '2ch': '2Ch',
      '2chron': '2Ch',
      '2chronicles': '2Ch',
      'ezr': 'Ezr',
      'ezra': 'Ezr',
      'neh': 'Neh',
      'nehemiah': 'Neh',
      'est': 'Est',
      'esther': 'Est',
      'job': 'Job',
      'ps': 'Psa',
      'psa': 'Psa',
      'psalm': 'Psa',
      'psalms': 'Psa',
      'pro': 'Pro',
      'prov': 'Pro',
      'proverbs': 'Pro',
      'ecc': 'Ecc',
      'eccl': 'Ecc',
      'ecclesiastes': 'Ecc',
      'son': 'Son',
      'song': 'Son',
      'songsolomon': 'Son',
      'songofsongs': 'Son',
      'song of solomon': 'Son',
      'isa': 'Isa',
      'isaiah': 'Isa',
      'jer': 'Jer',
      'jeremiah': 'Jer',
      'lam': 'Lam',
      'lamentations': 'Lam',
      'eze': 'Eze',
      'ezek': 'Eze',
      'ezekiel': 'Eze',
      'dan': 'Dan',
      'daniel': 'Dan',
      'hos': 'Hos',
      'hosea': 'Hos',
      'joe': 'Joe',
      'joel': 'Joe',
      'amo': 'Amo',
      'amos': 'Amo',
      'oba': 'Oba',
      'obad': 'Oba',
      'obadiah': 'Oba',
      'jon': 'Jon',
      'jonah': 'Jon',
      'mic': 'Mic',
      'micah': 'Mic',
      'nah': 'Nah',
      'nahum': 'Nah',
      'hab': 'Hab',
      'habakkuk': 'Hab',
      'zep': 'Zep',
      'zeph': 'Zep',
      'zephaniah': 'Zep',
      'hag': 'Hag',
      'haggai': 'Hag',
      'zec': 'Zec',
      'zech': 'Zec',
      'zechariah': 'Zec',
      'mal': 'Mal',
      'malachi': 'Mal',

      // New Testament
      'mat': 'Mat',
      'matt': 'Mat',
      'matthew': 'Mat',
      'mar': 'Mar',
      'mark': 'Mar',
      'luk': 'Luk',
      'luke': 'Luk',
      'joh': 'Joh',
      'john': 'Joh',
      'act': 'Act',
      'acts': 'Act',
      'rom': 'Rom',
      'romans': 'Rom',
      '1co': '1Co',
      '1cor': '1Co',
      '1corinthians': '1Co',
      '2co': '2Co',
      '2cor': '2Co',
      '2corinthians': '2Co',
      'gal': 'Gal',
      'galatians': 'Gal',
      'eph': 'Eph',
      'ephesians': 'Eph',
      'phi': 'Phi',
      'phil': 'Phi',
      'philippians': 'Phi',
      'col': 'Col',
      'colossians': 'Col',
      '1th': '1Th',
      '1thes': '1Th',
      '1thessalonians': '1Th',
      '2th': '2Th',
      '2thes': '2Th',
      '2thessalonians': '2Th',
      '1ti': '1Ti',
      '1tim': '1Ti',
      '1timothy': '1Ti',
      '2ti': '2Ti',
      '2tim': '2Ti',
      '2timothy': '2Ti',
      'tit': 'Tit',
      'titus': 'Tit',
      'phm': 'Phm',
      'philemon': 'Phm',
      'heb': 'Heb',
      'hebrews': 'Heb',
      'jam': 'Jam',
      'james': 'Jam',
      '1pe': '1Pe',
      '1pet': '1Pe',
      '1peter': '1Pe',
      '2pe': '2Pe',
      '2pet': '2Pe',
      '2peter': '2Pe',
      '1jo': '1Jo',
      '1john': '1Jo',
      '2jo': '2Jo',
      '2john': '2Jo',
      '3jo': '3Jo',
      '3john': '3Jo',
      'jud': 'Jud',
      'jude': 'Jud',
      'rev': 'Rev',
      'revelation': 'Rev',
    };

    // Add the canonical short name if found in the map
    if (abbreviationMap.containsKey(lower)) {
      variations.add(abbreviationMap[lower]!);
    }

    // Also try uppercase version of the abbreviation
    final upper = name.toUpperCase();
    if (abbreviationMap.containsKey(upper.toLowerCase())) {
      variations.add(abbreviationMap[upper.toLowerCase()]!);
    }

    // Handle plural/singular variations for Psalms
    if (lower == 'psalm') variations.add('Psa');
    if (lower == 'psalms') variations.add('Psa');

    return variations;
  }

  /// Check if a verse matches the current book filter
  static bool verseMatchesFilter(Map<String, dynamic> verse,
      List<String> allowedBooks, Map<String, Set<int>> allowedChapters) {
    final bookShortName = verse['book'] as String;

    // If no books are allowed, allow all
    if (allowedBooks.isEmpty) {
      return true;
    }

    // Check if book is in allowed list
    if (!allowedBooks.contains(bookShortName)) {
      return false;
    }

    // If no chapter restrictions for this book, allow all chapters
    if (!allowedChapters.containsKey(bookShortName)) {
      return true;
    }

    // Check chapter restriction
    final chapter = verse['chapter'] as int;
    return allowedChapters[bookShortName]!.contains(chapter);
  }
}

/// Result of parsing a book filter specification
class BookFilterResult {
  final List<String> books;
  final Map<String, Set<int>> chapters;
  final String? error;

  BookFilterResult._(this.books, this.chapters, this.error);

  factory BookFilterResult.success(List<String> books,
      [Map<String, Set<int>> chapters = const {}]) {
    return BookFilterResult._(books, chapters, null);
  }

  factory BookFilterResult.error(String error) {
    return BookFilterResult._([], {}, error);
  }

  bool get isSuccess => error == null;
}

/// Internal parse result
class _ParseResult {
  final List<String> books;
  final Map<String, Set<int>> chapters;
  final String? error;

  _ParseResult._(this.books, this.chapters, this.error);

  factory _ParseResult.success(List<String> books,
      [Map<String, Set<int>> chapters = const {}]) {
    return _ParseResult._(books, chapters, null);
  }

  factory _ParseResult.error(String error) {
    return _ParseResult._([], {}, error);
  }
}

/// Result of parsing a single book specification (may include chapter or chapter range)
class _BookSpecResult {
  final String? book;
  final int?
      startChapter; // Start of chapter range (null if no chapters specified)
  final int? endChapter; // End of chapter range (null if no chapters specified)
  final String? error;

  _BookSpecResult._(this.book, this.startChapter, this.endChapter, this.error);

  factory _BookSpecResult.success(String book,
      [int? startChapter, int? endChapter]) {
    return _BookSpecResult._(book, startChapter, endChapter, null);
  }

  factory _BookSpecResult.error(String error) {
    return _BookSpecResult._(null, null, null, error);
  }
}
