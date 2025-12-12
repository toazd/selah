import '../utils/verse_reference_detector.dart';

DateTime _parseDateTime(String dateStr) {
  try {
    return DateTime.parse(dateStr);
  } catch (e) {
    return DateTime.now();
  }
}

/// Represents a parsed highlight from Olive Tree CSV export
class OliveTreeHighlight {
  final String categoryName;
  final String type; // Should be "Highlight"
  final String highlighterName; // Color name like "Yellow"
  final String title;
  final String content; // Contains verse ref + highlighted text
  final String referenceStart; // Like "Genesis:3:6"
  final String referenceEnd; // Usually same as referenceStart
  final String associatedProduct;
  final DateTime dateCreated;
  final DateTime lastModified;
  final String tags;

  // Parsed data
  final VerseReference? verseReference;
  final String highlightedText;
  //final String verseText;

  OliveTreeHighlight({
    required this.categoryName,
    required this.type,
    required this.highlighterName,
    required this.title,
    required this.content,
    required this.referenceStart,
    required this.referenceEnd,
    required this.associatedProduct,
    required this.dateCreated,
    required this.lastModified,
    required this.tags,
  })  : verseReference = _parseVerseReference(content, referenceStart, title),
        highlightedText = _parseHighlightedText(content, referenceStart);

  factory OliveTreeHighlight.fromCsvRow(Map<String, String> row) {
    return OliveTreeHighlight(
      categoryName: row['category_name'] ?? '',
      type: row['type'] ?? '',
      highlighterName: row['highlighter_name'] ?? '',
      title: row['title'] ?? '',
      content: row['content'] ?? '',
      referenceStart: row['reference_start'] ?? '',
      referenceEnd: row['reference_end'] ?? '',
      associatedProduct: row['associated_product'] ?? '',
      dateCreated: _parseDateTime(row['date_created'] ?? ''),
      lastModified: _parseDateTime(row['last_modified'] ?? ''),
      tags: row['tags'] ?? '',
    );
  }

  static VerseReference? _parseVerseReference(String content, String referenceStart, String title) {
    final cleanedContent = _cleanContent(content);
    if (cleanedContent.isEmpty) {
      return _parseVerseReferenceFromTitle(title);
    }

    final convertedRef = referenceStart.replaceFirst(':', ' ');
    final parsedRef = VerseReferenceDetector.detectReferences(convertedRef).firstOrNull;
    return _isVerseRange(convertedRef) ? null : parsedRef;
  }

  static String _parseHighlightedText(String content, String referenceStart) {
    final cleanedContent = _cleanContent(content);
    if (cleanedContent.isEmpty) {
      return '';
    }

    final convertedRef = referenceStart.replaceFirst(':', ' ');
    final contentLines = cleanedContent.split('\n');
    final firstLine = contentLines[0].trim();
    final shouldRemoveRefLine = firstLine == convertedRef.trim();

    if (shouldRemoveRefLine && contentLines.length > 1) {
      return contentLines.sublist(1).join('\n').trim();
    } else if (shouldRemoveRefLine && contentLines.length == 1) {
      return '';
    } else {
      return cleanedContent.trim();
    }
  }

  static VerseReference? _parseVerseReferenceFromTitle(String title) {
    final titleParts = title.split(' ');
    if (titleParts.length >= 2) {
      final versePart = titleParts.sublist(1).join(' ');
      return VerseReferenceDetector.detectReferences(versePart).firstOrNull;
    }
    return null;
  }

  static String _cleanContent(String content) {
    // Normalize line endings - replace any sequence of \r or \n with single \n
    return content.replaceAll(RegExp(r'[\r\n]+'), '\n');
  }

  static bool _isVerseRange(String verseRef) {
    final colonIndex = verseRef.lastIndexOf(':');
    if (colonIndex == -1) return false;
    final versePart = verseRef.substring(colonIndex + 1);
    return versePart.contains('-');
  }
}

/// Represents a parsed note from Olive Tree CSV export
class OliveTreeNote {
  final String categoryName;
  final String type; // Should be "Note"
  final String highlighterName; // Usually empty for notes
  final String title;
  final String content; // The note text
  final String referenceStart; // Like "Genesis:3:6"
  final String referenceEnd; // Usually same as referenceStart
  final String associatedProduct;
  final DateTime dateCreated;
  final DateTime lastModified;
  final String tags;

  // Parsed data
  final VerseReference? verseReference;
  final String noteText;

  OliveTreeNote({
    required this.categoryName,
    required this.type,
    required this.highlighterName,
    required this.title,
    required this.content,
    required this.referenceStart,
    required this.referenceEnd,
    required this.associatedProduct,
    required this.dateCreated,
    required this.lastModified,
    required this.tags,
  })  : verseReference = _parseVerseReference(referenceStart, title),
        noteText = _cleanContent(content).trim();

  factory OliveTreeNote.fromCsvRow(Map<String, String> row) {
    return OliveTreeNote(
      categoryName: row['category_name'] ?? '',
      type: row['type'] ?? '',
      highlighterName: row['highlighter_name'] ?? '',
      title: row['title'] ?? '',
      content: row['content'] ?? '',
      referenceStart: row['reference_start'] ?? '',
      referenceEnd: row['reference_end'] ?? '',
      associatedProduct: row['associated_product'] ?? '',
      dateCreated: _parseDateTime(row['date_created'] ?? ''),
      lastModified: _parseDateTime(row['last_modified'] ?? ''),
      tags: row['tags'] ?? '',
    );
  }

  static VerseReference? _parseVerseReference(String referenceStart, String title) {
    // Parse verse reference from reference_start using Olive Tree's colon format
    var verseRef = OliveTreeData._parseColonReference(referenceStart);

    // If reference_start failed, try to extract reference from title (fallback for Notes only)
    verseRef ??= VerseReferenceDetector.detectReferences(title).firstOrNull;

    return verseRef;
  }

  static String _cleanContent(String content) {
    // Normalize line endings - replace any sequence of \r or \n with single \n
    return content.replaceAll(RegExp(r'[\r\n]+'), '\n');
  }
}

/// Container for parsed Olive Tree data
class OliveTreeData {
  final List<OliveTreeHighlight> highlights;
  final List<OliveTreeNote> notes;
  final List<FailedRow> failedRows;

  OliveTreeData({
    required this.highlights,
    required this.notes,
    required this.failedRows,
  });

  factory OliveTreeData.fromCsvRows(List<Map<String, String>> rows) {
    final highlights = <OliveTreeHighlight>[];
    final notes = <OliveTreeNote>[];
    final failedRows = <FailedRow>[];

    for (final row in rows) {
      final type = row['type'] ?? '';
      if (type == 'Highlight') {
        try {
          final highlight = OliveTreeHighlight.fromCsvRow(row);
          highlights.add(highlight); // Add all, validation happens in import service
        } catch (e) {
          failedRows.add(FailedRow(
            rowData: row,
            reason: 'Parsing error: $e',
          ));
        }
      } else if (type == 'Note') {
        try {
          final note = OliveTreeNote.fromCsvRow(row);
          notes.add(note); // Add all, validation happens in import service
        } catch (e) {
          failedRows.add(FailedRow(
            rowData: row,
            reason: 'Parsing error: $e',
          ));
        }
      }
    }

    return OliveTreeData(
      highlights: highlights,
      notes: notes,
      failedRows: failedRows,
    );
  }

  int get highlightCount => highlights.length;
  int get noteCount => notes.length;

  /// Parse Olive Tree's colon-separated reference format (e.g., "Genesis:3:6")
  static VerseReference? _parseColonReference(String reference) {
    final parts = reference.split(':');
    if (parts.length < 2 || parts.length > 3) return null;

    final bookPart = parts[0].trim();
    final chapterStr = parts[1].trim();
    final verseStr = parts.length > 2 ? parts[2].trim() : null;

    final chapter = int.tryParse(chapterStr);
    if (chapter == null) return null;

    final verse = verseStr != null ? int.tryParse(verseStr) : null;

    // Normalize book name using existing logic
    final normalizedBook = _normalizeBookName(bookPart);
    if (normalizedBook == null) return null;

    final verseRef = VerseReference(
      book: normalizedBook,
      chapter: chapter,
      verse: verse,
      endVerse: null,
      originalText: reference,
      startIndex: 0,
      //endIndex: reference.length,
    );

    return verseRef.isValid ? verseRef : null;
  }

  /// Book name mappings for normalization (copied from VerseReferenceDetector)
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
    'psa': 'Psa', 'psalms': 'Psa', 'psalm': 'Psa',
    'pro': 'Pro', 'proverbs': 'Pro',
    'ecc': 'Ecc', 'ecclesiastes': 'Ecc',
    'son': 'Son', 'song of solomon': 'Son', 'song of songs': 'Son', 'canticles': 'Son', 'cant': 'Son',
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
    'zec': 'Zec', 'zechariah': 'Zec',
    'mal': 'Mal', 'malachi': 'Mal',
    'mat': 'Mat', 'matthew': 'Mat',
    'mar': 'Mar', 'mark': 'Mar',
    'luk': 'Luk', 'luke': 'Luk',
    'joh': 'Joh', 'john': 'Joh',
    'act': 'Act', 'acts': 'Act',
    'rom': 'Rom', 'romans': 'Rom',
    '1co': '1Co', '1 corinthians': '1Co',
    '2co': '2Co', '2 corinthians': '2Co',
    'gal': 'Gal', 'galatians': 'Gal',
    'eph': 'Eph', 'ephesians': 'Eph',
    'phi': 'Phi', 'philippians': 'Phi',
    'col': 'Col', 'colossians': 'Col',
    '1th': '1Th', '1 thessalonians': '1Th',
    '2th': '2Th', '2 thessalonians': '2Th',
    '1ti': '1Ti', '1 timothy': '1Ti',
    '2ti': '2Ti', '2 timothy': '2Ti',
    'tit': 'Tit', 'titus': 'Tit',
    'phm': 'Phm', 'philemon': 'Phm', 'Phil': 'Phm',
    'heb': 'Heb', 'hebrews': 'Heb',
    'jam': 'Jam', 'james': 'Jam',
    '1pe': '1Pe', '1 peter': '1Pe',
    '2pe': '2Pe', '2 peter': '2Pe',
    '1jo': '1Jo', '1 john': '1Jo',
    '2jo': '2Jo', '2 john': '2Jo',
    '3jo': '3Jo', '3 john': '3Jo',
    'jud': 'Jud', 'jude': 'Jud',
    'rev': 'Rev', 'revelation': 'Rev',
  };

  /// Normalize book name using the same logic as VerseReferenceDetector
  static String? _normalizeBookName(String bookPart) {
    final lowerBook = bookPart.toLowerCase().trim();

    // Direct lookup in book mappings
    if (_bookMappings.containsKey(lowerBook)) {
      return _bookMappings[lowerBook];
    }

    // Try partial matches
    for (final entry in _bookMappings.entries) {
      if (entry.key.contains(lowerBook) || lowerBook.contains(entry.key)) {
        return entry.value;
      }
    }

    return null;
  }
}

/// Helper class for failed row data during import
class FailedRow {
  final Map<String, String> rowData;
  final String reason;

  FailedRow({required this.rowData, required this.reason});
}
