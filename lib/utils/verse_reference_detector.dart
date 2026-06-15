import '../data/bible_data_strongs.dart';

class VerseReference {
  final String book;
  final int chapter;
  final int? verse;
  final int? endVerse; // For ranges like "Gen 1:1-3"
  final String originalText;
  final int startIndex;
  //final int endIndex;

  VerseReference({
    required this.book,
    required this.chapter,
    this.verse,
    this.endVerse,
    required this.originalText,
    required this.startIndex,
    //required this.endIndex,
  });

  bool get isValid {
    // Validate existence using bibleDataStrongs (book -> chapter -> verse)
    final bookData = bibleDataStrongs[book];
    if (bookData == null || !bookData.containsKey(chapter)) {
      return false;
    }

    final chapterData = bookData[chapter];
    if (chapterData == null) {
      return false;
    }

    final isPsalmSuperscription = book == 'Psa' && verse == 0;

    // If verse is specified, check if it exists. Psalm superscriptions are
    // represented by verse 0 for navigation/search references only.
    if (verse != null &&
        !isPsalmSuperscription &&
        !chapterData.containsKey(verse)) {
      return false;
    }

    // If endVerse is specified (range), check if it exists and is valid
    if (endVerse != null) {
      if (!chapterData.containsKey(endVerse)) {
        return false;
      }
      // Ensure endVerse is after start verse
      if (verse != null && endVerse! < verse!) {
        return false;
      }
    }

    return true;
  }

  @override
  String toString() {
    return 'VerseReference(book: $book, chapter: $chapter, verse: $verse, endVerse: $endVerse, text: "$originalText")';
  }
}

class VerseReferenceDetector {
  // Book name mappings for detection
  static final Map<String, String> _bookMappings = {
    // Short names to database keys
    'gen': 'Gen', 'genesis': 'Gen',
    'exo': 'Exo', 'exodus': 'Exo',
    'lev': 'Lev', 'leviticus': 'Lev',
    'num': 'Num', 'numbers': 'Num',
    'deu': 'Deu', 'deuteronomy': 'Deu', 'deut': 'Deu',
    'jos': 'Jos', 'joshua': 'Jos',
    'jdg': 'Jdg', 'judges': 'Jdg',
    'rth': 'Rth', 'ruth': 'Rth',
    '1sa': '1Sa', '1 samuel': '1Sa', '1 Sam': '1Sa',
    '2sa': '2Sa', '2 samuel': '2Sa', '2 Sam': '2Sa',
    '1ki': '1Ki', '1 kings': '1Ki', '1Kings': '1Ki',
    '2ki': '2Ki', '2 kings': '2Ki', '2Kings': '2Ki',
    '1ch': '1Ch', '1 chronicles': '1Ch', '1Chr': '1Ch',
    '2ch': '2Ch', '2 chronicles': '2Ch', '2Chr': '2Ch',
    'ezr': 'Ezr', 'ezra': 'Ezr',
    'neh': 'Neh', 'nehemiah': 'Neh',
    'est': 'Est', 'esther': 'Est',
    'job': 'Job',
    'psa': 'Psa', 'psalms': 'Psa', 'psalm': 'Psa', 'Psa': 'Psa',
    'pro': 'Pro', 'proverbs': 'Pro',
    'ecc': 'Ecc', 'ecclesiastes': 'Ecc',
    'son': 'Son', 'song of solomon': 'Son', 'song of songs': 'Son',
    'canticles': 'Son', 'cant': 'Son', 'Sos': 'Son', 'sos': 'Son',
    'isa': 'Isa', 'isaiah': 'Isa',
    'jer': 'Jer', 'jeremiah': 'Jer',
    'lam': 'Lam', 'lamentations': 'Lam',
    'eze': 'Eze', 'ezekiel': 'Eze',
    'dan': 'Dan', 'daniel': 'Dan',
    'hos': 'Hos', 'hosea': 'Hos',
    'joe': 'Joe', 'joel': 'Joe',
    'amo': 'Amo', 'amos': 'Amo',
    'oba': 'Oba', 'obadiah': 'Oba',
    'jon': 'Jon', 'jonah': 'Jon',
    'mic': 'Mic', 'micah': 'Mic',
    'nah': 'Nah', 'nahum': 'Nah',
    'hab': 'Hab', 'habakkuk': 'Hab',
    'zep': 'Zep', 'zephaniah': 'Zep',
    'hag': 'Hag', 'haggai': 'Hag',
    'zec': 'Zec', 'zechariah': 'Zec', 'zech': 'Zec',
    'mal': 'Mal', 'malachi': 'Mal',
    'mat': 'Mat', 'matthew': 'Mat',
    'mar': 'Mar', 'mark': 'Mar',
    'luk': 'Luk', 'luke': 'Luk',
    'joh': 'Joh', 'john': 'Joh',
    'act': 'Act', 'acts': 'Act',
    'rom': 'Rom', 'romans': 'Rom',
    '1co': '1Co', '1 corinthians': '1Co', '1cor': '1Co',
    '2co': '2Co', '2 corinthians': '2Co', '2cor': '2Co',
    'gal': 'Gal', 'galatians': 'Gal',
    'eph': 'Eph', 'ephesians': 'Eph',
    'phi': 'Phi', 'philippians': 'Phi',
    'col': 'Col', 'colossians': 'Col',
    '1th': '1Th', '1 thessalonians': '1Th', '1thess': '1Th', '1 thess': '1Th',
    '2th': '2Th', '2 thessalonians': '2Th', '2thess': '2Th', '2 thess': '2Th',
    '1ti': '1Ti', '1 timothy': '1Ti', '1timothy': '1Ti', '1tim': '1Ti',
    '1 tim': '1Ti',
    '2ti': '2Ti', '2 timothy': '2Ti', '2timothy': '2Ti', '2tim': '2Ti',
    '2 tim': '2Ti',
    'tit': 'Tit', 'titus': 'Tit',
    'phm': 'Phm', 'philemon': 'Phm', 'Phil': 'Phm',
    'heb': 'Heb', 'hebrews': 'Heb',
    'jam': 'Jam', 'james': 'Jam',
    '1pe': '1Pe', '1 peter': '1Pe', '1peter': '1Pe', '1pet': '1Pe',
    '1 pet': '1Pe',
    '2pe': '2Pe', '2 peter': '2Pe', '2peter': '2Pe', '2pet': '2Pe',
    '2 pet': '2Pe',
    '1jo': '1Jo', '1 john': '1Jo', '1john': '1Jo', '1joh': '1Jo',
    '1 joh': '1Jo',
    '2jo': '2Jo', '2 john': '2Jo', '2john': '2Jo', '2joh': '2Jo',
    '2 joh': '2Jo',
    '3jo': '3Jo', '3 john': '3Jo', '3john': '3Jo', '3joh': '3Jo',
    '3 joh': '3Jo',
    'jud': 'Jud', 'jude': 'Jud',
    'rev': 'Rev', 'revelation': 'Rev',
  };

  // HIGHEST PRIORITY PATTERNS - Spaced references (matches longer references first)
  // Pattern 1: Spaced mixed ranges (e.g., "Gen 1:1-4, 6" or "Gen 1:1, 4-6")
  // Added negative lookaheads to prevent matching across chapter boundaries
  static final RegExp _spacedMixedRangePattern = RegExp(
    r'\b([1-3]?\s?[a-zA-Z]+)\s+(\d+):(\d+(?:-\d+)?(?:,\s+\d+(?:-\d+)?(?!\:\d+))+)(?!,\s*\d+:)\b',
    caseSensitive: false,
  );

  // Pattern 2: Long flexible comma ranges (3+ additional verses: "Gen 1:4,9,10", "Gen 1:4, 9,10, 11")
  // Added negative lookaheads to prevent matching across chapter boundaries
  static final RegExp _spacedCommaRangePattern = RegExp(
    r'\b([1-3]?\s?[a-zA-Z]+)\s+(\d+):(\d+(?:,\s*\d+(?!\:\d+)){3,})(?!,\s*\d+:)\b',
    caseSensitive: false,
  );

  // LOWER PRIORITY PATTERNS - Original patterns (non-spaced or single space)
  // Pattern 3: Mixed ranges with dashes and commas (e.g., "Gen 1:1-4,6" or "Gen 1:1,4-6")
  // Added negative lookaheads to prevent matching across chapter boundaries
  static final RegExp _mixedRangePattern = RegExp(
    r'\b([1-3]?\s?[a-zA-Z]+)\s+(\d+):(\d+(?:-\d+)?(?:,\s*\d+(?:-\d+)?(?!\:\d+))+)(?!,\s*\d+:)\b',
    caseSensitive: false,
  );

  // Pattern 2: Ranges with dash (e.g., "Gen 1:1-3") - make dash required
  static final RegExp _rangePattern = RegExp(
    r'\b([1-3]?\s?[a-zA-Z]+)\s+(\d+):(\d+)-(\d+)\b',
    caseSensitive: false,
  );

  // Pattern 3: Single verses (checked last to avoid overlap)
  static final RegExp _singleVersePattern = RegExp(
    r'\b([1-3]?\s?[a-zA-Z]+)\s+(\d+):(\d+)\b',
    caseSensitive: false,
  );

  static List<VerseReference> detectReferences(String text) {
    final allReferences = <VerseReference>[];
    final usedPositions =
        <int>{}; // Track positions that are already part of a reference

    // Helper function to check if a position range conflicts with existing references
    bool hasConflict(int start, int end) {
      for (int pos = start; pos < end; pos++) {
        if (usedPositions.contains(pos)) {
          return true;
        }
      }
      return false;
    }

    // Helper function to mark positions as used
    void markUsed(int start, int end) {
      for (int pos = start; pos < end; pos++) {
        usedPositions.add(pos);
      }
    }

    // Helper function to create reference from match
    VerseReference? createReferenceFromMatch(
        Match match, int offset, String patternType) {
      final fullMatch = match.group(0)!;
      final bookPart = match.group(1)?.trim() ?? '';
      final chapterStr = match.group(2);
      final versesStr = match.group(3)!;

      // For dash ranges, we need groups 3 and 4 (start verse and end verse separately)
      final dashEndVerseStr =
          patternType.contains('dash_range') ? match.group(4) : null;

      if (chapterStr == null) {
        return null;
      }

      final chapter = int.tryParse(chapterStr);
      if (chapter == null) {
        return null;
      }

      // Normalize book name
      final normalizedBook = normalizeBookName(bookPart);
      if (normalizedBook == null) {
        return null;
      }

      final startIndex = offset;
      final endIndex = offset + match.end;

      // Check for conflicts with already used positions
      if (hasConflict(startIndex, endIndex)) {}

      // Parse verse specification based on pattern type
      final allVerseNumbers = <int>[];
      if (patternType.contains('mixed') || patternType.contains('comma')) {
        // Handle comma-separated parsing
        final verseParts = versesStr.split(',');
        for (final part in verseParts) {
          final trimmedPart = part.trim();
          if (trimmedPart.contains('-')) {
            // Handle dash range like "4-6" -> [4,5,6]
            final dashParts = trimmedPart.split('-');
            if (dashParts.length == 2) {
              final start = int.tryParse(dashParts[0].trim());
              final end = int.tryParse(dashParts[1].trim());
              if (start != null && end != null && start <= end) {
                for (int v = start; v <= end; v++) {
                  allVerseNumbers.add(v);
                }
              } else {
                return null;
              }
            } else {
              return null;
            }
          } else {
            // Handle single verse like "1" -> [1]
            final verse = int.tryParse(trimmedPart);
            if (verse != null) {
              allVerseNumbers.add(verse);
            } else {
              return null;
            }
          }
        }
      } else if (patternType.contains('range')) {
        // Simple dash range - use separate regex groups for start/end verses
        final start = int.tryParse(versesStr);
        final end =
            dashEndVerseStr != null ? int.tryParse(dashEndVerseStr) : null;
        if (start != null && end != null && start <= end) {
          for (int v = start; v <= end; v++) {
            allVerseNumbers.add(v);
          }
        } else {
          return null;
        }
      } else if (patternType.contains('single')) {
        // Single verse
        final verse = int.tryParse(versesStr.trim());
        if (verse != null) {
          allVerseNumbers.add(verse);
        } else {
          return null;
        }
      }

      // Validate all verses exist in chapter
      final bookData = bibleDataStrongs[normalizedBook];
      if (bookData == null || !bookData.containsKey(chapter)) {
        return null;
      }

      final chapterData = bookData[chapter];
      if (chapterData == null) {
        return null;
      }

      for (final v in allVerseNumbers) {
        if (!chapterData.containsKey(v)) {
          return null;
        }
      }

      // Create appropriate reference type
      VerseReference reference;
      if (allVerseNumbers.length == 1) {
        // Single verse
        reference = VerseReference(
          book: normalizedBook,
          chapter: chapter,
          verse: allVerseNumbers[0],
          endVerse: null,
          originalText: fullMatch,
          startIndex: startIndex,
        );
      } else if (patternType.contains('dash_range') ||
          (versesStr.contains('-') && !versesStr.contains(','))) {
        // Simple dash range - check pattern type OR versesStr contains dash
        // Note: For dash_range pattern, versesStr is just the start verse (no dash),
        // so we must also check the pattern type
        reference = VerseReference(
          book: normalizedBook,
          chapter: chapter,
          verse: allVerseNumbers[0],
          endVerse: allVerseNumbers.last,
          originalText: fullMatch,
          startIndex: startIndex,
        );
      } else {
        // Mixed or comma ranges - use first as primary
        reference = VerseReference(
          book: normalizedBook,
          chapter: chapter,
          verse: allVerseNumbers[0],
          endVerse: null,
          originalText: fullMatch,
          startIndex: startIndex,
        );
      }

      if (!reference.isValid) {
        return null;
      }

      markUsed(startIndex, endIndex);
      return reference;
    }

    // PRIORITY ORDER: Process references from MOST SPECIFIC to LEAST SPECIFIC
    // This ensures longer/more complex patterns match before simpler substrings

    // 1. SPACED MIXED RANGES (highest priority - longest patterns)
    for (int i = 0; i < text.length; i++) {
      final substring = text.substring(i);
      final match = _spacedMixedRangePattern.matchAsPrefix(substring);
      if (match != null) {
        final reference =
            createReferenceFromMatch(match, i, 'spaced_mixed_range');
        if (reference != null) {
          allReferences.add(reference);
        }
      }
    }

    // 2. SPACED LONG COMMA RANGES
    for (int i = 0; i < text.length; i++) {
      final substring = text.substring(i);
      final match = _spacedCommaRangePattern.matchAsPrefix(substring);
      if (match != null) {
        final reference =
            createReferenceFromMatch(match, i, 'spaced_comma_range');
        if (reference != null) {
          allReferences.add(reference);
        }
      }
    }

    // 3. MIXED RANGES (original)
    for (int i = 0; i < text.length; i++) {
      final substring = text.substring(i);
      final match = _mixedRangePattern.matchAsPrefix(substring);
      if (match != null) {
        final reference = createReferenceFromMatch(match, i, 'mixed_range');
        if (reference != null) {
          allReferences.add(reference);
        }
      }
    }

    // 4. LONG COMMA RANGES (handle mixed spacing - find longest comma sequences)
    final commaCandidates = <Map<String, dynamic>>[];
    // Added negative lookaheads to prevent matching across chapter boundaries
    final allCommasPattern = RegExp(
        r'\b([1-3]?\s?[a-zA-Z]+)\s+(\d+):(\d+(?:,\s*\d+(?!:\d+))+)(?!,\s*\d+:)\b');
    for (int i = 0; i < text.length; i++) {
      final substring = text.substring(i);
      final match = allCommasPattern.matchAsPrefix(substring);
      if (match != null) {
        commaCandidates.add({
          'match': match,
          'offset': i,
          'text': match.group(0)!,
          'versesCount': match.group(3)!.split(',').length,
        });
      }
    }

    // Sort by verse count descending (most verses first), then by position
    commaCandidates.sort((a, b) {
      final aVerses = a['versesCount'] as int;
      final bVerses = b['versesCount'] as int;
      final versesCompare = bVerses - aVerses;
      if (versesCompare != 0) return versesCompare;
      final aOffset = a['offset'] as int;
      final bOffset = b['offset'] as int;
      return aOffset.compareTo(bOffset);
    });

    // Process sorted candidates with conflict checking during processing
    for (final candidate in commaCandidates) {
      final reference = createReferenceFromMatch(
          candidate['match'], candidate['offset'], 'comma_range');
      if (reference != null) {
        allReferences.add(reference);
      }
    }

    // 5. DASH RANGES
    for (int i = 0; i < text.length; i++) {
      final substring = text.substring(i);
      final match = _rangePattern.matchAsPrefix(substring);
      if (match != null) {
        final reference = createReferenceFromMatch(match, i, 'dash_range');
        if (reference != null) {
          allReferences.add(reference);
        }
      }
    }

    // 6. SINGLE VERSES (lowest priority)
    for (int i = 0; i < text.length; i++) {
      final substring = text.substring(i);
      final match = _singleVersePattern.matchAsPrefix(substring);
      if (match != null) {
        final reference = createReferenceFromMatch(match, i, 'single_verse');
        if (reference != null) {
          allReferences.add(reference);
        }
      }
    }

    return allReferences;
  }

  // For quick jump functionality - allows references without verses (e.g., "Joh 3")
  static VerseReference? detectQuickJumpReference(String text) {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty) return null;

    // Pattern for book chapter with optional verse: "Book Chapter" or "Book Chapter:Verse"
    final RegExp quickJumpPattern = RegExp(
        r'^([1-3]?\s?[a-zA-Z]+)\s+(\d+)(?::(\d+))?$',
        caseSensitive: false);

    final match = quickJumpPattern.firstMatch(trimmedText);
    if (match == null) return null;

    final bookPart = match.group(1)?.trim() ?? '';
    final chapterStr = match.group(2);
    final verseStr = match.group(3);

    if (chapterStr == null) return null;

    final chapter = int.tryParse(chapterStr);
    final verse = verseStr != null ? int.tryParse(verseStr) : null;

    if (chapter == null) return null;

    // Normalize book name
    final normalizedBook = normalizeBookName(bookPart);
    if (normalizedBook == null) return null;

    // Validate book and chapter exist
    final bookData = bibleDataStrongs[normalizedBook];
    if (bookData == null || !bookData.containsKey(chapter)) return null;

    // Validate verse if provided
    final chapterData = bookData[chapter];
    if (chapterData == null) return null;

    final isPsalmSuperscription = normalizedBook == 'Psa' && verse == 0;
    if (verse != null &&
        !isPsalmSuperscription &&
        !chapterData.containsKey(verse)) {
      return null;
    }

    return VerseReference(
      book: normalizedBook,
      chapter: chapter,
      verse: verse,
      endVerse: null,
      originalText: trimmedText,
      startIndex: 0,
    );
  }

  static String? normalizeBookName(String bookPart) {
    final lowerBook = bookPart.toLowerCase().trim();

    // Direct lookup
    if (_bookMappings.containsKey(lowerBook)) {
      return _bookMappings[lowerBook];
    }

    return null;
  }
}
