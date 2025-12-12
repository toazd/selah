import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'preferences_constants.dart';

/// Utility for mapping Olive Tree highlight colors to Selah app highlight colors
class ColorMapper {
  // Common color names and their RGB values
  static const Map<String, Color> commonColors = {
    'yellow': Color(0xFFFFFF00),
    'blue': Color(0xFF0000FF),
    'red': Color(0xFFFF0000),
    'green': Color(0xFF00FF00),
    'cyan': Color(0xFF00FFFF),
    'teal': Color(0xFF008080),
    'orange': Color(0xFFFFA500),
    'purple': Color(0xFF800080),
    'indigo': Color(0xFF4B0082),
    'bluegrey': Color(0xFF607D8B),
    'lime': Color(0xFF00FF00),
    'brown': Color(0xFFDEB887),
    'black': Color(0xFF000000),
    'white': Color(0xFFFFFFFF),
    'gray': Color(0xFF808080),
    'grey': Color(0xFF808080),
    'pink': Color(0xFFFFC0CB),
    'magenta': Color(0xFFFF00FF),
    'violet': Color(0xFFEE82EE),
  };

  /// Load current highlight colors from shared preferences, fallback to defaults
  static Future<List<Color>> getCurrentHighlightColors() async {
    final prefs = await SharedPreferences.getInstance();
    final highlightColorsRaw = prefs.getStringList('highlightColors');
    if (highlightColorsRaw != null && highlightColorsRaw.isNotEmpty) {
      try {
        final parsedColors = highlightColorsRaw.map((v) {
          try {
            return Color(int.parse(v));
          } catch (e) {
            return Colors.yellow; // fallback for invalid color
          }
        }).toList();
        if (parsedColors.isNotEmpty) {
          return parsedColors;
        }
      } catch (_) {}
    }
    return defaultHighlightColors;
  }

  /// Generate suggested color mappings for Olive Tree colors
  static Future<Map<String, int>> generateColorMappings(List<String> oliveTreeColors) async {
    final selahColors = await getCurrentHighlightColors();
    return _generateMappings(oliveTreeColors, selahColors);
  }

  /// Internal method to generate mappings with given colors
  static Map<String, int> _generateMappings(List<String> oliveTreeColors, List<Color> selahColors) {
    final mappings = <String, int>{};

    for (final otColor in oliveTreeColors) {
      final normalizedColor = otColor.toLowerCase().trim();
      final selahIndex = _findBestMatch(normalizedColor, selahColors);
      mappings[otColor] = selahIndex;
    }

    return mappings;
  }

  /// Find the best matching Selah color index for an Olive Tree color name
  static int _findBestMatch(String oliveTreeColor, List<Color> selahColors) {
    // First try exact name match
    if (commonColors.containsKey(oliveTreeColor)) {
      final otColor = commonColors[oliveTreeColor]!;
      return _findClosestColorIndex(otColor, selahColors);
    }

    // Try partial matches
    for (final entry in commonColors.entries) {
      if (entry.key.contains(oliveTreeColor) || oliveTreeColor.contains(entry.key)) {
        return _findClosestColorIndex(entry.value, selahColors);
      }
    }

    // Default to first color for unknown colors
    return 0;
  }

  /// Find the index of the closest color in Selah's palette
  static int _findClosestColorIndex(Color targetColor, List<Color> selahColors) {
    int bestIndex = 0;
    double bestDistance = double.infinity;

    for (int i = 0; i < selahColors.length; i++) {
      final distance = _colorDistance(targetColor, selahColors[i]);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }

    return bestIndex;
  }

  /// Calculate Euclidean distance between two colors in RGB space
  static double _colorDistance(Color c1, Color c2) {
    final r1 = c1.r;
    final g1 = c1.g;
    final b1 = c1.b;
    final r2 = c2.r;
    final g2 = c2.g;
    final b2 = c2.b;

    return math.sqrt(
      math.pow(r1 - r2, 2) + math.pow(g1 - g2, 2) + math.pow(b1 - b2, 2),
    );
  }

  /// Get all unique color names from Olive Tree highlights
  static List<String> extractUniqueColors(List<String> highlighterNames) {
    final colors = <String>{};
    for (final name in highlighterNames) {
      if (name.trim().isNotEmpty) {
        colors.add(name.trim());
      }
    }
    return colors.toList()..sort();
  }
}
