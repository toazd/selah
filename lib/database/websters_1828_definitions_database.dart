import 'package:flutter/foundation.dart';

import '../data/websters_1828_definitions.dart';

class Websters1828DefinitionsDatabase {
  static final List<String> _headwords = _buildHeadwords();
  static final Map<String, String> _caseInsensitiveHeadwords =
      _buildCaseInsensitiveHeadwords();
  static final Map<String, String> _normalizedHeadwords =
      _buildNormalizedHeadwords();

  static String? getDefinition(String input) {
    final headword = findHeadword(input);
    if (headword == null) return null;

    final definition = websters1828[headword]?['definition'];
    if (kDebugMode) {
      debugPrint(
          "Websters1828DefinitionsDatabase.getDefinition returning: $definition");
    }
    return definition is String ? definition : null;
  }

  static String? findHeadword(String input) {
    final cleaned = _cleanInput(input);
    if (cleaned.isEmpty) return null;

    if (websters1828.containsKey(cleaned)) {
      return cleaned;
    }

    final caseInsensitive = _caseInsensitiveHeadwords[cleaned.toLowerCase()];
    if (caseInsensitive != null) {
      return caseInsensitive;
    }

    final normalized = _normalizationKey(cleaned);
    if (normalized.isEmpty) return null;

    final normalizedMatch = _normalizedHeadwords[normalized];
    if (normalizedMatch != null) {
      return normalizedMatch;
    }

    final partialMatches = searchHeadwords(cleaned, limit: 1);
    return partialMatches.isEmpty ? null : partialMatches.first;
  }

  static List<String> getHeadwords() => _headwords;

  static List<String> searchHeadwords(String input, {int? limit}) {
    final cleaned = _cleanInput(input);
    if (cleaned.isEmpty) {
      return limit == null
          ? _headwords
          : _headwords.take(limit).toList(growable: false);
    }

    final lower = cleaned.toLowerCase();
    final normalized = _normalizationKey(cleaned);
    if (normalized.isEmpty) return const [];

    final startsWith = <String>[];
    final contains = <String>[];

    for (final headword in _headwords) {
      final headwordLower = headword.toLowerCase();
      final headwordNormalized = _normalizationKey(headword);
      if (headwordLower.startsWith(lower) ||
          headwordNormalized.startsWith(normalized)) {
        startsWith.add(headword);
      } else if (headwordLower.contains(lower) ||
          headwordNormalized.contains(normalized)) {
        contains.add(headword);
      }
    }

    final results = [...startsWith, ...contains];
    if (limit != null && results.length > limit) {
      return results.take(limit).toList(growable: false);
    }
    return results;
  }

  /// Strips HTML tags from a definition string, converting breaks to newlines.
  static String stripHtml(String html) {
    var result = html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");

    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return result.trim();
  }

  static List<String> _buildHeadwords() {
    final result = websters1828.keys.toList();
    result.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return List.unmodifiable(result);
  }

  static Map<String, String> _buildCaseInsensitiveHeadwords() {
    final result = <String, String>{};
    for (final headword in _headwords) {
      result.putIfAbsent(headword.toLowerCase(), () => headword);
    }
    return Map.unmodifiable(result);
  }

  static Map<String, String> _buildNormalizedHeadwords() {
    final result = <String, String>{};
    for (final headword in _headwords) {
      final key = _normalizationKey(headword);
      if (key.isNotEmpty) {
        result.putIfAbsent(key, () => headword);
      }
    }
    return Map.unmodifiable(result);
  }

  static String _cleanInput(String input) {
    var cleaned = input.trim();
    if (cleaned.startsWith('dict://')) {
      cleaned = cleaned.substring('dict://'.length);
    }

    try {
      cleaned = Uri.decodeComponent(cleaned);
    } on FormatException {
      // Keep the original text when a legacy dictionary link is malformed.
    }

    cleaned = cleaned
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'^[\[\(\s]+'), '')
        .replaceAll(RegExp(r'[\]\)\s.,;:]+$'), '');
    return cleaned.trim();
  }

  static String _normalizationKey(String input) {
    return input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }
}
