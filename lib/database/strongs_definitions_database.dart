import '../data/strongs_definitions.dart';

class StrongsDefinitionsDatabase {
  static String? getDefinition(String strongsNumber) {
    final normalized = _normalizeStrongNumber(strongsNumber);
    if (normalized == null) return null;

    final prefix = normalized[0];
    final number = int.tryParse(normalized.substring(1));
    if (number == null) return null;

    return strongsDefinitions[prefix]?[number];
  }

  /// Strips HTML tags from a definition string, converting <br> to newlines.
  static String stripHtml(String html) {
    String result = html
        .replaceAll(RegExp(r'<br>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '');
    // result = result.replaceAll(RegExp(r'<[^>]*>'), '');
    // result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    // // Decode common HTML entities
    // result = result.replaceAll('&', '&');
    // result = result.replaceAll('<', '<');
    // result = result.replaceAll('>', '>');
    // result = result.replaceAll('"', '"');
    // result = result.replaceAll('&#39;', "'");
    // result = result.replaceAll('&nbsp;', ' ');
    return result.trim();
  }

  static String? _normalizeStrongNumber(String strongsNumber) {
    final trimmed = strongsNumber.trim();
    if (trimmed.length < 2) return null;

    final prefix = trimmed[0].toUpperCase();
    if (prefix != 'H' && prefix != 'G') return null;

    final suffix = trimmed.substring(1);
    if (int.tryParse(suffix) == null) return null;

    return '$prefix$suffix';
  }
}
