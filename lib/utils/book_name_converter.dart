// Book name conversion utility for converting between short and long book names
// And normalizing case in both short and long book names

class BookNameConverter {
  // Base map: Short name -> Full name
  static const Map<String, String> _shortToLong = {
    'Gen': 'Genesis',
    'Exo': 'Exodus',
    'Lev': 'Leviticus',
    'Num': 'Numbers',
    'Deu': 'Deuteronomy',
    'Jos': 'Joshua',
    'Jdg': 'Judges',
    'Rth': 'Ruth',
    '1Sa': '1 Samuel',
    '2Sa': '2 Samuel',
    '1Ki': '1 Kings',
    '2Ki': '2 Kings',
    '1Ch': '1 Chronicles',
    '2Ch': '2 Chronicles',
    'Ezr': 'Ezra',
    'Neh': 'Nehemiah',
    'Est': 'Esther',
    'Job': 'Job',
    'Psa': 'Psalms',
    'Pro': 'Proverbs',
    'Ecc': 'Ecclesiastes',
    'Son': 'Song of Solomon',
    'Isa': 'Isaiah',
    'Jer': 'Jeremiah',
    'Lam': 'Lamentations',
    'Eze': 'Ezekiel',
    'Dan': 'Daniel',
    'Hos': 'Hosea',
    'Joe': 'Joel',
    'Amo': 'Amos',
    'Oba': 'Obadiah',
    'Jon': 'Jonah',
    'Mic': 'Micah',
    'Nah': 'Nahum',
    'Hab': 'Habakkuk',
    'Zep': 'Zephaniah',
    'Hag': 'Haggai',
    'Zec': 'Zechariah',
    'Mal': 'Malachi',
    'Mat': 'Matthew',
    'Mar': 'Mark',
    'Luk': 'Luke',
    'Joh': 'John',
    'Act': 'Acts',
    'Rom': 'Romans',
    '1Co': '1 Corinthians',
    '2Co': '2 Corinthians',
    'Gal': 'Galatians',
    'Eph': 'Ephesians',
    'Phi': 'Philippians',
    'Col': 'Colossians',
    '1Th': '1 Thessalonians',
    '2Th': '2 Thessalonians',
    '1Ti': '1 Timothy',
    '2Ti': '2 Timothy',
    'Tit': 'Titus',
    'Phm': 'Philemon',
    'Heb': 'Hebrews',
    'Jam': 'James',
    '1Pe': '1 Peter',
    '2Pe': '2 Peter',
    '1Jo': '1 John',
    '2Jo': '2 John',
    '3Jo': '3 John',
    'Jud': 'Jude',
    'Rev': 'Revelation',
  };

  // Reverse map: Full name -> Short name
  static final Map<String, String> _longToShort =
      _shortToLong.map((key, value) => MapEntry(value, key));

  // --- PRIVATE DEBUG HELPER METHOD ---
  /// Helper method to extract the function name and simplified location from a raw stack frame.
  /*
  static String _extractCallerName(String rawFrame) {
    // Attempt to capture the function name (Group 1) and the full path (Group 2)
    final regex = RegExp(r'\s*#\d+\s+([\w.<>]+)\s+\(([^)]+)\)$');
    final match = regex.firstMatch(rawFrame);

    if (match != null && match.groupCount >= 2) {
      final functionName = match.group(1)!;
      final location = match.group(2)!;

      // If it's a project file or non-Flutter library, return function name + file:line
      if (location.startsWith('package:selah/') || !location.contains('package:flutter/')) {
        // Extracts the simplified file:line:col part
        final pathMatch = RegExp(r'([^/]+:\d+:\d+)$').firstMatch(location);
        final lineInfo = pathMatch != null ? pathMatch.group(1) : location;
        return '$functionName ($lineInfo)';
      }
      // For Flutter or Dart internal calls, just return the location path for brevity.
      return location;
    }

    // Fallback: Use the original raw line if parsing fails.
    return rawFrame.split('(').first.trim();
  }
  */

  /// Normalizes a short book name string (e.g., 'gEn' or '1co')
  /// to the exact capitalization used as a key in the short-to-long map (e.g., 'Gen' or '1Co').
  static String normalizeShortName(String shortName) {
    if (shortName.isEmpty) return shortName;

    // If starts with digit, don't modify the rest (already correct format)
    if ('0123456789'.contains(shortName[0])) {
      final digitPart = shortName[0]; // "1"
      final letterPart = shortName.substring(1); // "co"
      return digitPart +
          letterPart[0].toUpperCase() +
          letterPart.substring(1).toLowerCase();
    }

    // Regular case: first char uppercase, rest lowercase
    return shortName[0].toUpperCase() + shortName.substring(1).toLowerCase();
  }

  /// Normalizes a long book name string (e.g., 'song of solomon' or '1 corinthians')
  /// to Title Case (e.g., 'Song of Solomon' or '1 Corinthians') for map key matching.
  static String normalizeLongName(String longName) {
    if (longName.isEmpty) return longName;

    // Normalize input by capitalizing the first letter of every word.
    final normalizedLongName = longName
        .split(' ')
        .map((word) => word.isNotEmpty
            ? word[0].toUpperCase() + word.substring(1).toLowerCase()
            : word)
        .join(' ');

    return normalizedLongName;
  }

  /// Converts a short book name (e.g., 'Gen', '1co', '2sa') to its full name.
  static String shortNameToLongName(String shortName) {
    // final stackTrace = StackTrace.current;
    // final frames = stackTrace.toString().split('\n');
    // debugPrint('--- Call Chain (Last 3 Callers) ---');
    // debugPrint('Current function shortName: $shortName');
    // const startFrameIndex = 1;
    // for (int i = startFrameIndex + 1; i <= startFrameIndex + 3; i++) {
    //   if (i < frames.length) {
    //     final callerFrame = frames[i].trim();
    //     final callerName = _extractCallerName(callerFrame);
    //     debugPrint('Caller ${i - startFrameIndex}: $callerName');
    //   } else {
    //     break;
    //   }
    // }

    if (shortName.isEmpty) return shortName;

    final normalizedShortName = normalizeShortName(shortName);

    // Returns the long name or the original input if not found.
    final returnValue = _shortToLong[normalizedShortName];

    // if (kDebugMode) {
    //   debugPrint('BookNameConverter.shortNameToLongName: "$shortName" => "$returnValue"');
    // }

    // if (kDebugMode && (returnValue ?? shortName) != shortName && returnValue == null) {
    //   debugPrint('BookNameConverter.shortNameToLongName returning original (not found): $shortName');
    // }

    return returnValue ?? shortName;
  }

  /// Converts a full book name (e.g., 'Genesis', '1 Corinthians') back to its short name.
  static String longNameToShortName(String longName) {
    // final stackTrace = StackTrace.current;
    // final frames = stackTrace.toString().split('\n');
    // debugPrint('--- Call Chain (Last 3 Callers) ---');
    // debugPrint('Current function longName: $longName');
    // const startFrameIndex = 1;
    // for (int i = startFrameIndex + 1; i <= startFrameIndex + 3; i++) {
    //   if (i < frames.length) {
    //     final callerFrame = frames[i].trim();
    //     final callerName = _extractCallerName(callerFrame);
    //     debugPrint('Caller ${i - startFrameIndex}: $callerName');
    //   } else {
    //     break;
    //   }
    // }

    if (longName.isEmpty) return longName;

    // Uses the new helper method for consistent capitalization.
    final normalizedLongName = normalizeLongName(longName);

    // Returns the short name or the original input if not found.
    final returnValue = _longToShort[normalizedLongName];

    // if (kDebugMode) {
    //   debugPrint('BookNameConverter.longNameToShortName: "$longName" => "$returnValue"');
    // }

    // if (kDebugMode && (returnValue ?? longName) != longName && returnValue == null) {
    //   debugPrint('BookNameConverter.longNameToShortName returning original (not found): $longName');
    // }

    return returnValue ?? longName;
  }
}
