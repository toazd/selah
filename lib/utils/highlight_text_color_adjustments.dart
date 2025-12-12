import 'dart:math';
import 'package:flutter/material.dart';

/// Utility functions for adjusting text colors to ensure proper contrast
/// against highlight backgrounds, following WCAG accessibility guidelines.
///
/// That's a fancy way of saying that when the user chooses a particular highlight
/// (background) color for any particular text, this adjusts the color of the
/// text itself to ensure that it is still readable. So, the user can choose or
/// customize the highlight colors and text colors to their hearts desire and the text won't
/// become unreadable.

/// Calculate the relative luminance of a color (WCAG formula)
double calculateRelativeLuminance(Color color) {
  double toLinear(double channel) {
    return channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = toLinear(color.r);
  final g = toLinear(color.g);
  final b = toLinear(color.b);

  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// Calculate WCAG contrast ratio between two colors
double calculateContrastRatio(Color color1, Color color2) {
  final lum1 = calculateRelativeLuminance(color1);
  final lum2 = calculateRelativeLuminance(color2);

  final lighter = max(lum1, lum2);
  final darker = min(lum1, lum2);

  return (lighter + 0.05) / (darker + 0.05);
}

/// Gradually adjust a color towards a target to achieve minimum contrast
Color adjustColorTowards(Color current, Color target, double minContrast, Color background) {
  // If target already meets contrast, return it immediately
  if (calculateContrastRatio(target, background) >= minContrast) {
    return target;
  }

  // If current already meets contrast, return it
  if (calculateContrastRatio(current, background) >= minContrast) {
    return current;
  }

  final hslCurrent = HSLColor.fromColor(current);
  final hslTarget = HSLColor.fromColor(target);

  // Binary search for optimal interpolation factor
  double low = 0.0;
  double high = 1.0;
  Color bestColor = target; // Default to target if nothing better found

  for (int i = 0; i < 8; i++) {
    // Max 8 iterations for precision
    double mid = (low + high) / 2.0;

    final interpolatedHsl = HSLColor.fromAHSL(
      1.0,
      hslCurrent.hue + (hslTarget.hue - hslCurrent.hue) * mid,
      hslCurrent.saturation + (hslTarget.saturation - hslCurrent.saturation) * mid,
      hslCurrent.lightness + (hslTarget.lightness - hslCurrent.lightness) * mid,
    );

    final testColor = interpolatedHsl.toColor();
    final contrast = calculateContrastRatio(testColor, background);

    if (contrast >= minContrast) {
      bestColor = testColor;
      high = mid; // Try smaller factor (closer to current)
    } else {
      low = mid; // Need larger factor (closer to target)
    }
  }

  return bestColor;
}

/// Adjust text color for optimal contrast against a highlight background
Color adjustTextColorForHighlight(
    Color originalTextColor, Color highlightBackground, Color darkTextColor, Color lightTextColor) {
  Color adjustedTextColor = originalTextColor;
  final currentContrast = calculateContrastRatio(originalTextColor, highlightBackground);

  // Only adjust if contrast is below 4.5:1 (WCAG AA normal text threshold)
  // This is more conservative and avoids changing already readable combinations
  if (currentContrast < 4.5) {
    // Try adjusting towards white first (better for dark themes), then black
    final contrastWithDarkTextColor = calculateContrastRatio(darkTextColor, highlightBackground);
    final contrastWithLightTextColor = calculateContrastRatio(lightTextColor, highlightBackground);

    Color targetColor;
    if (contrastWithDarkTextColor > contrastWithLightTextColor) {
      targetColor = darkTextColor;
    } else {
      targetColor = lightTextColor;
    }

    // Gradually adjust the current text color towards the target with more subtle steps
    adjustedTextColor = adjustColorTowards(originalTextColor, targetColor, 4.5, highlightBackground);
  }

  return adjustedTextColor;
}
