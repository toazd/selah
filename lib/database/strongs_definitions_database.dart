import '../data/strongs_definitions.dart';

class StrongsDefinitionsDatabase {
  static String? getDefinition(String strongsNumber) {
    final normalized = normalizeStrongsNumber(strongsNumber);
    if (normalized == null) return null;

    final prefix = normalized[0];
    final number = int.tryParse(normalized.substring(1));
    if (number == null) return null;

    return strongsDefinitions[prefix]?[number];
  }

  static bool hasDefinition(String strongsNumber) {
    return getDefinition(strongsNumber) != null;
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

  static String? normalizeStrongsNumber(String strongsNumber) {
    final trimmed = strongsNumber.trim();
    final match = RegExp(r'^([HhGg])(\d{1,4})$').firstMatch(trimmed);
    if (match == null) return null;

    final prefix = match.group(1)!.toUpperCase();
    final suffix = match.group(2)!;
    final number = int.tryParse(suffix);
    if (number == null) return null;

    return '$prefix$number';
  }
}
