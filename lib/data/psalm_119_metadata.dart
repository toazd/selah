/// Section headings for Psalm 119.
///
/// Each heading belongs immediately before the verse number listed in the
/// map. The text includes the punctuation used by the King James Version.
const Map<int, String> psalm119SectionTitles = {
  1: 'ALEPH',
  9: 'BETH',
  17: 'GIMEL',
  25: 'DALETH',
  33: 'HE',
  41: 'VAU',
  49: 'ZAIN',
  57: 'CHETH',
  65: 'TETH',
  73: 'JOD',
  81: 'CAPH',
  89: 'LAMED',
  97: 'MEM',
  105: 'NUN',
  113: 'SAMECH',
  121: 'AIN',
  129: 'PE',
  137: 'TZADDI',
  145: 'KOPH',
  153: 'RESH',
  161: 'SCHIN',
  169: 'TAU',
};

/// Returns the Psalm 119 section heading for a verse, if one starts there.
String? getPsalm119SectionTitle(String book, int chapter, int verse) {
  if (book != 'Psa' || chapter != 119) return null;
  return psalm119SectionTitles[verse];
}
