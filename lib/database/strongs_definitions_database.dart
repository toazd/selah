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
