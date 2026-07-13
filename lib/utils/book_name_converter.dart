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

  static const Map<String, String> _commonBookAliases = {
    'ge': 'Gen',
    'gn': 'Gen',
    'ex': 'Exo',
    'exod': 'Exo',
    'le': 'Lev',
    'lv': 'Lev',
    'nu': 'Num',
    'nm': 'Num',
    'nb': 'Num',
    'dt': 'Deu',
    'deut': 'Deu',
    'josh': 'Jos',
    'judg': 'Jdg',
    'jg': 'Jdg',
    'ru': 'Rth',
    '1sam': '1Sa',
    '2sam': '2Sa',
    '1kgs': '1Ki',
    '1king': '1Ki',
    '2kgs': '2Ki',
    '2king': '2Ki',
    '1chr': '1Ch',
    '1chron': '1Ch',
    '2chr': '2Ch',
    '2chron': '2Ch',
    'ps': 'Psa',
    'pss': 'Psa',
    'psalm': 'Psa',
    'prov': 'Pro',
    'pr': 'Pro',
    'eccl': 'Ecc',
    'song': 'Son',
    'sos': 'Son',
    'cant': 'Son',
    'canticles': 'Son',
    'is': 'Isa',
    'ezek': 'Eze',
    'dn': 'Dan',
    'jl': 'Joe',
    'am': 'Amo',
    'ob': 'Oba',
    'obad': 'Oba',
    'jnh': 'Jon',
    'mi': 'Mic',
    'na': 'Nah',
    'hbk': 'Hab',
    'zeph': 'Zep',
    'zp': 'Zep',
    'hg': 'Hag',
    'zech': 'Zec',
    'zc': 'Zec',
    'ml': 'Mal',
    'matt': 'Mat',
    'mt': 'Mat',
    'mrk': 'Mar',
    'mk': 'Mar',
    'mr': 'Mar',
    'lk': 'Luk',
    'lu': 'Luk',
    'jn': 'Joh',
    'jhn': 'Joh',
    'ac': 'Act',
    'ro': 'Rom',
    'rm': 'Rom',
    '1cor': '1Co',
    '2cor': '2Co',
    'ga': 'Gal',
    'ep': 'Eph',
    'phil': 'Phi',
    'php': 'Phi',
    '1thes': '1Th',
    '1thess': '1Th',
    '2thes': '2Th',
    '2thess': '2Th',
    '1tim': '1Ti',
    '2tim': '2Ti',
    'phlm': 'Phm',
    'philem': 'Phm',
    'jas': 'Jam',
    '1pet': '1Pe',
    '2pet': '2Pe',
    '1joh': '1Jo',
    '1jn': '1Jo',
    '2joh': '2Jo',
    '2jn': '2Jo',
    '3joh': '3Jo',
    '3jn': '3Jo',
    're': 'Rev',
  };

  static final Map<String, String> _bookAliases = _buildBookAliases();

  static Map<String, String> _buildBookAliases() {
    final aliases = <String, String>{};

    void addAlias(String alias, String shortName) {
      final key = _bookAliasKey(alias);
      if (key.isNotEmpty) {
        aliases[key] = shortName;
      }
    }

    for (final entry in _shortToLong.entries) {
      addAlias(entry.key, entry.key);
      addAlias(entry.value, entry.key);
    }

    for (final entry in _commonBookAliases.entries) {
      addAlias(entry.key, entry.value);
    }

    return aliases;
  }

  static String _bookAliasKey(String bookName) {
    final cleaned =
        bookName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    if (cleaned.isEmpty) return '';

    final parts =
        cleaned.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return '';

    parts[0] = _normalizeLeadingOrdinal(parts[0]);
    return parts.join();
  }

  static String _normalizeLeadingOrdinal(String token) {
    const ordinalWords = {
      'first': '1',
      'second': '2',
      'third': '3',
      'i': '1',
      'ii': '2',
      'iii': '3',
    };

    final ordinal = ordinalWords[token];
    if (ordinal != null) return ordinal;

    final ordinalSuffix = RegExp(r'^([1-3])(?:st|nd|rd)$').firstMatch(token);
    if (ordinalSuffix != null) return ordinalSuffix.group(1)!;

    final compactOrdinal =
        RegExp(r'^([1-3])(?:st|nd|rd)([a-z].*)$').firstMatch(token);
    if (compactOrdinal != null) {
      return '${compactOrdinal.group(1)!}${compactOrdinal.group(2)!}';
    }

    for (final entry in const {
      'first': '1',
      'second': '2',
      'third': '3',
    }.entries) {
      if (token.startsWith(entry.key) && token.length > entry.key.length) {
        return '${entry.value}${token.substring(entry.key.length)}';
      }
    }

    return token;
  }

  /// Normalizes a short book name string (e.g., 'gEn' or '1co')
  /// to the exact capitalization used as a key in the short-to-long map (e.g., 'Gen' or '1Co').
  static String normalizeShortName(String shortName) {
    if (shortName.isEmpty) return shortName;

    // If starts with digit, don't modify the rest (already correct format)
    if ('0123456789'.contains(shortName[0])) {
      final digitPart = shortName[0]; // "1"
      final letterPart = shortName.substring(1); // "co"
      if (letterPart.isEmpty) return shortName;
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
    if (shortName.isEmpty) return shortName;

    final normalizedShortName = normalizeShortName(shortName);

    // Returns the long name or the original input if not found.
    final returnValue = _shortToLong[normalizedShortName];

    return returnValue ?? shortName;
  }

  /// Normalizes any book name (short or long) to the short name key used in the database.
  /// Supports both short names (e.g., 'deu', '1co') and long names (e.g., 'deuteronomy', '1 corinthians').
  static String normalizeBookName(String bookName) {
    if (bookName.isEmpty) return bookName;

    final aliasMatch = tryNormalizeBookName(bookName);
    if (aliasMatch != null) {
      return aliasMatch;
    }

    // Try normalizing as short name first
    final normalizedShort = normalizeShortName(bookName);
    if (_shortToLong.containsKey(normalizedShort)) {
      return normalizedShort;
    }

    // Try normalizing as long name
    final normalizedLong = normalizeLongName(bookName);
    final shortFromLong = _longToShort[normalizedLong];
    if (shortFromLong != null) {
      return shortFromLong;
    }

    // If neither worked, return the short normalization attempt
    // This will still fail validation but gives the best effort
    return normalizedShort;
  }

  /// Returns the canonical short book name for recognized long names,
  /// abbreviations, compact names, and common numbered-book variants.
  static String? tryNormalizeBookName(String bookName) {
    if (bookName.trim().isEmpty) return null;
    return _bookAliases[_bookAliasKey(bookName)];
  }

  /// Converts a full book name (e.g., 'Genesis', '1 Corinthians') back to its short name.
  static String longNameToShortName(String longName) {
    if (longName.isEmpty) return longName;

    // Uses the new helper method for consistent capitalization.
    final normalizedLongName = normalizeLongName(longName);

    // Returns the short name or the original input if not found.
    final returnValue = _longToShort[normalizedLongName];

    return returnValue ?? longName;
  }
}
