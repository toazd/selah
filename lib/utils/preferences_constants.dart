import 'package:flutter/material.dart';

// Centralized default values for all preferences

const int defaultThemeMode = 0; // ThemeMode.system
const double defaultFontSize = 22.0;
const String defaultFontFamily = 'IBM Plex Sans';
const String defaultNoteFontFamily = 'Scope One';
const double defaultLineHeight = 1.2;
const double defaultHighlightAlpha = 0.90; // Not user-configurable

// Color defaults in hex
const String defaultLightPrimaryColorHex = '#FF607D8B';
const String defaultLightBackgroundColorHex = '#FFFFF7CB';
const String defaultLightTextColorHex = '#FF000000';
const String defaultDarkPrimaryColorHex = '#FF607D8B';
const String defaultDarkBackgroundColorHex = '#FF242424'; //'#FF000010';
const String defaultDarkTextColorHex = '#FFC2C5C7'; //'#FF6D6866';
const String defaultLightHighlightColorHex = '#FFFFD400';
const String defaultDarkHighlightColorHex = '#FF1B295F'; //'#FF383F41';
const String defaultLightVerseReferenceColorHex = '#FF2196F3'; // Colors.blue
const String defaultDarkVerseReferenceColorHex =
    '#FF09610C'; // Color.fromARGB(255, 9, 97, 12)
// Hex => Integer conversions for ValueNotifiers that require colors as ints
Color get defaultLightPrimaryColor => hexToColor(defaultLightPrimaryColorHex);
Color get defaultLightBackgroundColor =>
    hexToColor(defaultLightBackgroundColorHex);
Color get defaultLightTextColor => hexToColor(defaultLightTextColorHex);
Color get defaultDarkPrimaryColor => hexToColor(defaultDarkPrimaryColorHex);
Color get defaultDarkBackgroundColor =>
    hexToColor(defaultDarkBackgroundColorHex);
Color get defaultDarkTextColor => hexToColor(defaultDarkTextColorHex);
Color get defaultLightHighlightColor =>
    hexToColor(defaultLightHighlightColorHex);
Color get defaultDarkHighlightColor => hexToColor(defaultDarkHighlightColorHex);
Color get defaultLightVerseReferenceColor =>
    hexToColor(defaultLightVerseReferenceColorHex);
Color get defaultDarkVerseReferenceColor =>
    hexToColor(defaultDarkVerseReferenceColorHex);

// Helper function to convert hex string to Color
Color hexToColor(String hexString) {
  final buffer = StringBuffer();
  if (hexString.length == 6 || hexString.length == 7) buffer.write('FF');
  buffer.write(hexString.replaceFirst('#', ''));
  return Color(int.parse(buffer.toString(), radix: 16));
}

const bool defaultFullscreen = false;

// Only user-configurable through the advanced -> edit preferences dialog
const int defaultMaxVerticalScreens = 4;
const int defaultMaxHorizontalScreens = 3;

const List<Color> defaultHighlightColors = [
  Colors.yellow,
  Colors.blue,
  Colors.blueAccent,
  Colors.red,
  Colors.green,
  Colors.greenAccent,
  Colors.cyan,
  Colors.teal,
  Colors.orange,
  Colors.deepOrangeAccent,
  Colors.purple,
  Colors.indigo,
  Colors.blueGrey,
  Colors.lime,
  Colors.brown,
  Colors.pinkAccent,
];

const bool defaultShowNotesInline = true;
const bool defaultShowNavigationBar = true;
const bool defaultShowTskReferences = false;

// Sync retry delay constants (shared by all sync retry systems)
const int syncRetryDelay1Seconds = 1; // First retry delay
const int syncRetryDelay2Seconds = 3; // Second retry delay
const int syncRetryDelay3Seconds = 5; // Third retry delay

const bool defaultSyncHighlights = true;
const bool defaultSyncNotes = true;
const bool defaultSyncHistory = true;
const bool defaultSyncSearchHistory = true;

// Time-based theme preferences
const int defaultDayStartHour = 7; // 7 AM
const int defaultNightStartHour = 18; // 6 PM

// UI constants (non-user customizable)
const double uiFontSize = 18.0;
const String uiFontFamily = 'IBM Plex Sans';

// Notes (quill_note_display.dart) and TSK references (tsk_reference_display.dart) display at a slightly smaller sizes
const double fontSizeAdjustmentDesktop = 4.0;
const double fontSizeAdjustmentMobile = 2.0;

// use getAdaptiveTextColor instead of hard-coded
// colors because it adapts to any color that the user chooses
//
//const Color uiLightColor = Colors.black;
//const Color uiDarkColor = Colors.white;

// Toggle to enable/disable Bible screen restrictions (vertical and horizontal limits)
// Set to false to allow unlimited screens
const bool enableScreenLimitations = false;
