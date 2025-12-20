// ignore_for_file: no_leading_underscores_for_local_identifiers

//import 'package:selah/utils/tablet_mode_test_example.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'screens/bible_screen.dart';
import 'screens/search_screen.dart';
import 'screens/auth_screen.dart';
import 'database/history_database.dart';
import 'database/highlights_database.dart';
import 'database/notes_database.dart';
import 'widgets/sync_dialog.dart';
import 'widgets/verse_history_dialog.dart';
import 'utils/preferences_constants.dart';
import 'utils/snackbar_notification.dart';
import 'services/supabase_sync_service.dart';
import 'services/auth_service.dart';
import 'services/selah_import_service.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'services/local_data_change_notifier.dart';
import 'services/olive_tree_import_service.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'utils/internet_access_checker.dart';
import 'database/search_database.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'utils/tablet_mode_detector.dart';
//import 'package:flutter_onscreen_keyboard/flutter_onscreen_keyboard.dart';

final appVersion = "0.7.0";

final bool _isDesktop = (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux));
final ValueNotifier<bool> isVerticalTile = ValueNotifier(
  () {
    if (_isDesktop || kIsWeb) {
      return true;
    }
    return false;
  }(), // <--- The crucial '()' executes the function immediately
);

final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(
  ThemeMode.system,
); // Default to Auto
bool _isTimeBasedThemeEnabled = false; // Track if time-based theme is enabled
Timer? _timeBasedThemeTimer; // Track the time-based theme timer
final ValueNotifier<double> fontSizeNotifier = ValueNotifier(defaultFontSize);
final ValueNotifier<String> fontFamilyNotifier = ValueNotifier(defaultFontFamily);
final ValueNotifier<String> noteFontFamilyNotifier = ValueNotifier(defaultNoteFontFamily); // Default note font
final ValueNotifier<double> lineHeightNotifier = ValueNotifier(defaultLineHeight);

const List<String> availableFonts = [
  'Arimo',
  'Open Sans',
  'Daddy Time Mono',
  'Inconsolata',
  'Roboto Mono',
  'Gabriela',
  'Caveat',
  'Dancing Script',
  'Lobster Two',
  'Ubuntu',
  'Liberation Sans',
  'Tinos',
  'Merriweather',
  'Liberation Serif',
  'Special Gothic',
  'Rosemartin',
  'Playfair Display',
  'Morris Roman',
  'JSL Ancient',
  'Louis George Cafe',
  'Comfortaa',
  'King Sans',
  'Fauna One',
  'Hepta Slab',
  'IBM Plex Sans',
  'Libertinus Sans',
  'Montserrat',
  'Noto Sans',
  'Old Standard',
  'Sanchez',
  'Scope One',
  'Solway',
];

final ValueNotifier<Color> lightPrimaryColor = ValueNotifier(Colors.blueGrey);
final ValueNotifier<Color> lightBackgroundColor = ValueNotifier(const Color.fromARGB(255, 255, 247, 203));
final ValueNotifier<Color> lightTextColor = ValueNotifier(Colors.black);
final ValueNotifier<Color> darkPrimaryColor = ValueNotifier(Colors.blueGrey);
final ValueNotifier<Color> darkBackgroundColor = ValueNotifier(const Color(0xFF000010));
final ValueNotifier<Color> darkTextColor = ValueNotifier(Colors.white);
final ValueNotifier<bool> fullscreenNotifier = ValueNotifier(false);
final ValueNotifier<int> maxVerticalScreens = ValueNotifier(defaultMaxVerticalScreens);
final ValueNotifier<int> maxHorizontalScreens = ValueNotifier(defaultMaxHorizontalScreens);
final ValueNotifier<List<Color>> highlightColorsNotifier = ValueNotifier<List<Color>>(defaultHighlightColors);
final ValueNotifier<Color> lightHighlightColor = ValueNotifier(defaultLightHighlightColor);
final ValueNotifier<Color> darkHighlightColor = ValueNotifier(defaultDarkHighlightColor);
final ValueNotifier<Color> lightVerseReferenceColor = ValueNotifier(defaultLightVerseReferenceColor);
final ValueNotifier<Color> darkVerseReferenceColor = ValueNotifier(defaultDarkVerseReferenceColor);
// Add: notes display mode (false = icon next to verse [default], true = inline below verse)
final ValueNotifier<bool> showNotesInlineNotifier = ValueNotifier(defaultShowNotesInline);

// Add: navigation bar display mode (false = hidden, true = visible [default])
final ValueNotifier<bool> showNavigationBarNotifier = ValueNotifier(defaultShowNavigationBar);

// Time-based theme preferences (configurable)
final ValueNotifier<int> dayStartHourNotifier = ValueNotifier(defaultDayStartHour);
final ValueNotifier<int> nightStartHourNotifier = ValueNotifier(defaultNightStartHour);

// Sync category enablement toggles
final ValueNotifier<bool> syncHighlightsNotifier = ValueNotifier(defaultSyncHighlights);
final ValueNotifier<bool> syncNotesNotifier = ValueNotifier(defaultSyncNotes);
final ValueNotifier<bool> syncHistoryNotifier = ValueNotifier(defaultSyncHistory);
final ValueNotifier<bool> syncSearchHistoryNotifier = ValueNotifier(defaultSyncSearchHistory);

// Supabase auth state
final ValueNotifier<bool> isSignedIn = ValueNotifier(false);
final ValueNotifier<User?> currentUser = ValueNotifier(null);

// Global navigator key for showing dialogs from window manager
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Global scaffold messenger key for showing snackbars globally
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

// Global tablet mode detection service
// Only used on Windows desktop to circumvent
// a bug that can be triggered with the OSK
class TabletModeService {
  static final TabletModeService _instance = TabletModeService._internal();
  factory TabletModeService() => _instance;
  TabletModeService._internal();

  ValueNotifier<bool>? _tabletModeNotifier;

  void initializeNotifier() {
    if (!kIsWeb && Platform.isWindows) {
      _tabletModeNotifier = TabletModeDetector.createTabletModeNotifier();
      _tabletModeNotifier!.addListener(() {
        final isTablet = _tabletModeNotifier!.value;
        if (kDebugMode) {
          debugPrint('Tablet Mode Listener: ($isTablet) - ${isTablet ? "Tablet Mode" : "Laptop Mode"}');
        }
      });
    }
  }

  ValueNotifier<bool>? get notifier => _tabletModeNotifier;
  bool get isTablet => _tabletModeNotifier?.value ?? false;
}

// Global shutdown coordination to prevent race conditions during app exit
class ShutdownCoordinator {
  static final ShutdownCoordinator _instance = ShutdownCoordinator._internal();
  factory ShutdownCoordinator() => _instance;
  ShutdownCoordinator._internal();

  bool _isShuttingDown = false;
  final Completer<void> _shutdownCompleter = Completer<void>();

  Future<void> beginShutdown() async {
    if (_isShuttingDown) {
      return _shutdownCompleter.future;
    }

    _isShuttingDown = true;
    if (kDebugMode) {
      debugPrint('Beginning coordinated shutdown');
    }

    return _shutdownCompleter.future;
  }

  bool get isShuttingDown => _isShuttingDown;

  void completeShutdown() {
    if (!_shutdownCompleter.isCompleted) {
      _shutdownCompleter.complete();
    }
  }
}

final shutdownCoordinator = ShutdownCoordinator();

// Add: color hex helpers
String _colorToHex(Color c) => '#${(c.toARGB32() & 0x00FFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

Color _parseHexColor(String? hex, Color fallback) {
  if (hex == null) return fallback;
  var h = hex.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 6) h = 'FF$h';
  if (h.length == 8) {
    try {
      return Color(int.parse(h, radix: 16));
    } catch (e) {
      if (kDebugMode) debugPrint('_parseHexColor exception: ${e.toString()}');
    }
  }
  return fallback;
}

// Replace: loader supports only hex string; no legacy int handling
Color _loadColorPref(SharedPreferences prefs, String key, Color fallback) {
  final s = prefs.getString(key);
  return _parseHexColor(s, fallback);
}

// Adaptive color for some UI elements to always keep them readable
Color getAdaptiveTextColor(
  BuildContext context, {
  Color? backgroundColor,
  bool usePrimaryColor = false,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  Color bgColor;
  if (backgroundColor != null) {
    // Custom background color provided
    bgColor = backgroundColor;
  } else if (usePrimaryColor) {
    // Use primary color (for buttons)
    bgColor = isDark ? darkPrimaryColor.value : lightPrimaryColor.value;
  } else {
    // Use background color (default behavior)
    bgColor = isDark ? darkBackgroundColor.value : lightBackgroundColor.value;
  }

  return bgColor.computeLuminance() > 0.5 ? Colors.black : Colors.white;
}

// Initialize sqflite FFI once at startup to prevent memory leaks
void _initializeSqflite() {
  if (kIsWeb) {
    // Web: Use IndexedDB via sqflite_common_ffi_web
    databaseFactory = databaseFactoryFfiWeb;
  } else if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    // Initialize FFI for desktop - only do this once
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}

// Initialize time-based theme switching
void _initializeTimeBasedTheme() async {
  //final prefs = await SharedPreferences.getInstance();
  //final modeIndex = prefs.getInt('themeMode') ?? defaultThemeMode;

  // Only set up time-based switching if time-based theme is selected
  //if (modeIndex == 3) {
  if (_isTimeBasedThemeEnabled) {
    // Cancel any existing timer first
    _timeBasedThemeTimer?.cancel();
    _timeBasedThemeTimer = null;

    // Check theme immediately
    _updateThemeBasedOnTime();

    // Set up periodic timer to check every 5 minutes
    _timeBasedThemeTimer = Timer.periodic(const Duration(minutes: 5), (
      Timer timer,
    ) {
      _updateThemeBasedOnTime();
    });
  }
}

// Update theme based on current time
void _updateThemeBasedOnTime() {
  final now = DateTime.now();
  final currentHour = now.hour;

  // Determine if it's day or night using configurable hours
  final isDayTime = currentHour >= dayStartHourNotifier.value && currentHour < nightStartHourNotifier.value;

  // Update theme mode accordingly
  final newThemeMode = isDayTime ? ThemeMode.light : ThemeMode.dark;

  // Only update if different from current
  if (themeModeNotifier.value != newThemeMode) {
    themeModeNotifier.value = newThemeMode;
  }
}

// Get time-based theme status text
String _getTimeBasedThemeStatus() {
  final now = DateTime.now();
  final currentHour = now.hour;

  // Determine if it's day or night using configurable hours
  final isDayTime = currentHour >= dayStartHourNotifier.value && currentHour < nightStartHourNotifier.value;

  if (isDayTime) {
    // Currently in light mode, show when dark mode starts
    final nightHour = nightStartHourNotifier.value;
    return 'Light mode until ${nightHour.toString().padLeft(2, '0')}:00';
  } else {
    // Currently in dark mode, show when light mode starts
    final dayHour = dayStartHourNotifier.value;
    return 'Dark mode until ${dayHour.toString().padLeft(2, '0')}:00';
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details);
  };

  // Initialize sqflite once at startup to prevent memory leaks
  _initializeSqflite();

  // Initialize Supabase
  try {
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      anonKey: SupabaseConfig.supabaseAnonKey,
    );
  } catch (e) {
    if (kDebugMode) {
      debugPrint('Supabase initialize exception: ${e.toString()}');
    }
  }

  // Listen to auth state changes
  Supabase.instance.client.auth.onAuthStateChange.listen((AuthState data) async {
    final user = data.session?.user;
    isSignedIn.value = user != null;
    currentUser.value = user;

    // Maintain Supabase sync services based on authentication state
    if (isSignedIn.value) {
      // Check if this is a fresh login (no existing session) vs app restart (existing session)
      final prefs = await SharedPreferences.getInstance();
      final lastLoginTime = prefs.getInt('lastLoginTime');

      if (lastLoginTime == null) {
        // Fresh login - store login time but DON'T initialize sync yet
        // Let AuthScreen handle sync initialization after user confirms preferences
        await prefs.setInt('lastLoginTime', DateTime.now().millisecondsSinceEpoch);
        if (kDebugMode) {
          debugPrint('Fresh login detected - sync initialization deferred for user preference confirmation');
        }
      } else {
        // App restart - initialize sync normally since preferences are already set
        if (kDebugMode) {
          debugPrint('App restart detected - initializing sync service normally');
        }
        await SupabaseSyncService().initialize(isLoginResync: true);
      }
    } else {
      // Sign out - clear last login time and dispose sync service
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('lastLoginTime');
      SupabaseSyncService().dispose(); // Handles sign-out
    }
  });

  await _loadAllPrefs();
  final prefs = await SharedPreferences.getInstance();
  // Only save max screens prefs if not mobile
  if (!(!kIsWeb && (Platform.isAndroid || Platform.isIOS))) {
    if (!prefs.containsKey('maxVerticalScreens')) {
      await prefs.setInt('maxVerticalScreens', maxVerticalScreens.value);
    }
    if (!prefs.containsKey('maxHorizontalScreens')) {
      await prefs.setInt('maxHorizontalScreens', maxHorizontalScreens.value);
    }
  }

  // Initialize time-based theme switching if needed
  _initializeTimeBasedTheme();

  runApp(BibleStudyApp());

  //final isTabletMode = await TabletModeDetector.isTabletMode();
  //debugPrint('isTabletMode: $isTabletMode');
  //TabletModeDetector.testTabletModeDetection();

  // Initialize tablet mode detection service
  TabletModeService().initializeNotifier();
}

Future<bool> checkAtLeastOneSyncEnabled() {
  return Future.value(
    syncHighlightsNotifier.value ||
        syncNotesNotifier.value ||
        syncHistoryNotifier.value ||
        syncSearchHistoryNotifier.value,
  );
}

Future<bool> showNoSyncWarningDialog() async {
  final navigator = navigatorKey.currentState!;
  final result = await showDialog<bool>(
    context: navigator.overlay!.context,
    barrierDismissible: false,
    builder: (context) => Center(
      child: AlertDialog(
        constraints: const BoxConstraints(maxWidth: 400),
        //title: Text('No Sync Selected', style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily)),
        content: Text(
          'You have chosen to not sync any data categories. This means that no data will be synced but your account information will remain.\n\nYou can freely toggle which categories are or aren\'t synced later in the main options menu under "Sync Options".\n\nAre you sure?',
          style: TextStyle(
            fontSize: uiFontSize,
            fontFamily: uiFontFamily,
            color: getAdaptiveTextColor(context),
          ),
        ),
        actions: [
          TextButton(
            child: Text(
              'Go back',
              style: TextStyle(
                fontSize: uiFontSize,
                fontFamily: uiFontFamily,
                color: getAdaptiveTextColor(context),
              ),
            ),
            onPressed: () => Navigator.pop(context, false),
          ),
          TextButton(
            child: Text(
              'Continue',
              style: TextStyle(
                fontSize: uiFontSize,
                fontFamily: uiFontFamily,
                color: getAdaptiveTextColor(context),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}

Future<void> _loadAllPrefs() async {
  try {
    final prefs = await SharedPreferences.getInstance();

    // Load from individual SharedPreferences keys only
    // Theme
    final modeIndex = prefs.getInt('themeMode') ?? defaultThemeMode;
    switch (modeIndex) {
      case 1:
        themeModeNotifier.value = ThemeMode.light;
        _isTimeBasedThemeEnabled = false;
        break;
      case 2:
        themeModeNotifier.value = ThemeMode.dark;
        _isTimeBasedThemeEnabled = false;
        break;
      case 3:
        // Time-based theme - we'll handle this specially
        themeModeNotifier.value = ThemeMode.light; // Default to light, will be updated by time check
        _isTimeBasedThemeEnabled = true;
        break;
      default:
        themeModeNotifier.value = ThemeMode.system;
        _isTimeBasedThemeEnabled = false;
    }

    // Font
    double fontSize = prefs.getDouble('fontSize') ?? defaultFontSize;
    if (fontSize < 12.0 || fontSize > 36.0) fontSize = defaultFontSize;
    String fontFamily = prefs.getString('fontFamily') ?? defaultFontFamily;
    String noteFontFamily = prefs.getString('noteFontFamily') ?? defaultNoteFontFamily;
    fontSizeNotifier.value = fontSize;
    fontFamilyNotifier.value = fontFamily;
    noteFontFamilyNotifier.value = noteFontFamily;

    // Colors: load from hex strings
    lightPrimaryColor.value = _loadColorPref(
      prefs,
      'lightPrimaryColor',
      hexToColor(defaultLightPrimaryColorHex),
    );
    lightBackgroundColor.value = _loadColorPref(
      prefs,
      'lightBackgroundColor',
      hexToColor(defaultLightBackgroundColorHex),
    );
    lightTextColor.value = _loadColorPref(
      prefs,
      'lightTextColor',
      hexToColor(defaultLightTextColorHex),
    );
    darkPrimaryColor.value = _loadColorPref(
      prefs,
      'darkPrimaryColor',
      hexToColor(defaultDarkPrimaryColorHex),
    );
    darkBackgroundColor.value = _loadColorPref(
      prefs,
      'darkBackgroundColor',
      hexToColor(defaultDarkBackgroundColorHex),
    );
    darkTextColor.value = _loadColorPref(
      prefs,
      'darkTextColor',
      hexToColor(defaultDarkTextColorHex),
    );

    // Fullscreen
    fullscreenNotifier.value = prefs.getBool('fullscreen') ?? defaultFullscreen;

    // Max screens
    final bool isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final int defaultVertical = isMobile ? 1 : defaultMaxVerticalScreens;
    final int defaultHorizontal = isMobile ? 3 : defaultMaxHorizontalScreens;

    // Load and validate max screens with range checking
    int maxVertical = prefs.getInt('maxVerticalScreens') ?? defaultVertical;
    if (maxVertical < 1 || maxVertical > 10) maxVertical = defaultVertical;

    int maxHorizontal = prefs.getInt('maxHorizontalScreens') ?? defaultHorizontal;
    if (maxHorizontal < 1 || maxHorizontal > 10) {
      maxHorizontal = defaultHorizontal;
    }

    maxVerticalScreens.value = maxVertical;
    maxHorizontalScreens.value = maxHorizontal;

    // Highlight colors (list of int color values)
    final highlightColorsRaw = prefs.getStringList('highlightColors');
    if (highlightColorsRaw != null && highlightColorsRaw.isNotEmpty) {
      try {
        final parsedColors = highlightColorsRaw.map((v) {
          try {
            return Color(int.parse(v));
          } catch (_) {
            return Colors.yellow; // fallback for invalid color
          }
        }).toList();

        if (parsedColors.isNotEmpty) {
          highlightColorsNotifier.value = parsedColors;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('prefs.getStringList(\'highlightColors\') exception: ${e.toString()}');
        }
      }
    }

    // Highlight single colors from hex strings
    lightHighlightColor.value = _loadColorPref(
      prefs,
      'lightHighlightColor',
      defaultLightHighlightColor,
    );
    darkHighlightColor.value = _loadColorPref(
      prefs,
      'darkHighlightColor',
      defaultDarkHighlightColor,
    );

    // Verse reference colors from hex strings
    lightVerseReferenceColor.value = _loadColorPref(
      prefs,
      'lightVerseReferenceColor',
      defaultLightVerseReferenceColor,
    );
    darkVerseReferenceColor.value = _loadColorPref(
      prefs,
      'darkVerseReferenceColor',
      defaultDarkVerseReferenceColor,
    );

    // Notes inline mode
    showNotesInlineNotifier.value = prefs.getBool('showNotesInline') ?? defaultShowNotesInline;

    // Navigation bar display mode
    showNavigationBarNotifier.value = prefs.getBool('showNavigationBar') ?? defaultShowNavigationBar;

    // Time-based theme preferences
    dayStartHourNotifier.value = prefs.getInt('dayStartHour') ?? defaultDayStartHour;
    nightStartHourNotifier.value = prefs.getInt('nightStartHour') ?? defaultNightStartHour;

    // Sync settings
    syncHighlightsNotifier.value = prefs.getBool('syncHighlights') ?? defaultSyncHighlights;
    syncNotesNotifier.value = prefs.getBool('syncNotes') ?? defaultSyncNotes;
    syncHistoryNotifier.value = prefs.getBool('syncHistory') ?? defaultSyncHistory;
    syncSearchHistoryNotifier.value = prefs.getBool('syncSearchHistory') ?? defaultSyncSearchHistory;

    // Layout preference
    isVerticalTile.value = prefs.getBool('isVerticalTile') ?? isVerticalTile.value;
  } catch (e) {
    if (kDebugMode) debugPrint('_loadAllPrefs exception: ${e.toString()}');
  }
}

Future<void> _saveAllCurrentPrefs() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    bool? isMaximized;
    Size? size;

    // Add try-catch for windowManager calls to prevent crashes during shutdown on Linux
    // This guards against GTK window being destroyed while trying to query its state
    if (!kIsWeb && (!(Platform.isAndroid || Platform.isIOS))) {
      try {
        isMaximized = await windowManager.isMaximized();
      } catch (e) {
        // Window may be destroyed during shutdown, use default value
        if (kDebugMode) {
          debugPrint('Failed to get window maximized state during shutdown: ${e.toString()}');
        }
        isMaximized = false;
      }

      try {
        size = await windowManager.getSize();
      } catch (e) {
        // Window may be destroyed during shutdown, use default value
        if (kDebugMode) {
          debugPrint('Failed to get window size during shutdown: ${e.toString()}');
        }

        size = const Size(900, 700);
      }
    }

    // Determine theme mode value
    int themeModeValue;
    if (_isTimeBasedThemeEnabled) {
      // Time-based theme is enabled, save as 3
      themeModeValue = 3;
    } else if (themeModeNotifier.value == ThemeMode.light) {
      themeModeValue = 1;
    } else if (themeModeNotifier.value == ThemeMode.dark) {
      themeModeValue = 2;
    } else {
      themeModeValue = 0; // System
    }

    // Save individual preference keys concurently instead of one at a time
    // 1. Create a List of Future<bool> objects representing all save operations.
    List<Future<bool>> saveOperations = [
      prefs.setInt('themeMode', themeModeValue),
      prefs.setDouble('fontSize', fontSizeNotifier.value),
      prefs.setString('fontFamily', fontFamilyNotifier.value),
      prefs.setString('noteFontFamily', noteFontFamilyNotifier.value),
      prefs.setString('lightPrimaryColor', _colorToHex(lightPrimaryColor.value)),
      prefs.setString(
        'lightBackgroundColor',
        _colorToHex(lightBackgroundColor.value),
      ),
      prefs.setString('lightTextColor', _colorToHex(lightTextColor.value)),
      prefs.setString('darkPrimaryColor', _colorToHex(darkPrimaryColor.value)),
      prefs.setString(
        'darkBackgroundColor',
        _colorToHex(darkBackgroundColor.value),
      ),
      prefs.setString('darkTextColor', _colorToHex(darkTextColor.value)),
      prefs.setString(
        'lightHighlightColor',
        _colorToHex(lightHighlightColor.value),
      ),
      prefs.setString(
        'darkHighlightColor',
        _colorToHex(darkHighlightColor.value),
      ),
      prefs.setString(
        'lightVerseReferenceColor',
        _colorToHex(lightVerseReferenceColor.value),
      ),
      prefs.setString(
        'darkVerseReferenceColor',
        _colorToHex(darkVerseReferenceColor.value),
      ),
      prefs.setBool('fullscreen', fullscreenNotifier.value),
      prefs.setBool('showNotesInline', showNotesInlineNotifier.value),
      prefs.setBool('showNavigationBar', showNavigationBarNotifier.value),
      prefs.setInt('maxVerticalScreens', maxVerticalScreens.value),
      prefs.setInt('maxHorizontalScreens', maxHorizontalScreens.value),
      prefs.setStringList(
        'highlightColors',
        highlightColorsNotifier.value.map((c) => c.toARGB32().toString()).toList(),
      ),
      prefs.setBool('syncHighlights', syncHighlightsNotifier.value),
      prefs.setBool('syncNotes', syncNotesNotifier.value),
      prefs.setBool('syncHistory', syncHistoryNotifier.value),
      prefs.setBool('syncSearchHistory', syncSearchHistoryNotifier.value),
      prefs.setBool('isVerticalTile', isVerticalTile.value),
      prefs.setInt('dayStartHour', dayStartHourNotifier.value),
      prefs.setInt('nightStartHour', nightStartHourNotifier.value),
    ];

    // Only save window state if not mobile and we have valid values
    if (!kIsWeb && !(Platform.isAndroid || Platform.isIOS) && isMaximized != null && size != null) {
      prefs.setDouble('windowWidth', size.width);
      prefs.setDouble('windowHeight', size.height);
      prefs.setBool('windowMaximized', isMaximized);
    }

    // 2. Await the completion of ALL operations concurrently.
    // This line replaces all the individual `await` keywords
    await Future.wait(saveOperations);
  } catch (e) {
    if (kDebugMode) {
      debugPrint('_saveAllCurrentPrefs exception: ${e.toString()}');
    }
  }
}

class BibleStudyApp extends StatelessWidget {
  const BibleStudyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        return ValueListenableBuilder<double>(
          valueListenable: fontSizeNotifier,
          builder: (context, fontSize, _) {
            return ValueListenableBuilder<String>(
              valueListenable: fontFamilyNotifier,
              builder: (context, fontFamily, _) {
                return ValueListenableBuilder<Color>(
                  valueListenable: lightBackgroundColor,
                  builder: (context, lightBg, _) {
                    return ValueListenableBuilder<Color>(
                      valueListenable: lightTextColor,
                      builder: (context, lightTxt, _) {
                        return ValueListenableBuilder<Color>(
                          valueListenable: lightPrimaryColor,
                          builder: (context, lightPrimary, _) {
                            return ValueListenableBuilder<Color>(
                              valueListenable: darkBackgroundColor,
                              builder: (context, darkBg, _) {
                                return ValueListenableBuilder<Color>(
                                  valueListenable: darkTextColor,
                                  builder: (context, darkTxt, _) {
                                    return ValueListenableBuilder<Color>(
                                      valueListenable: darkPrimaryColor,
                                      builder: (context, darkPrimary, _) {
                                        return MaterialApp(
                                          title: 'Selah',
                                          localizationsDelegates: const [
                                            GlobalMaterialLocalizations.delegate,
                                            GlobalWidgetsLocalizations.delegate,
                                            GlobalCupertinoLocalizations.delegate,
                                            FlutterQuillLocalizations.delegate,
                                          ],
                                          // supportedLocales: [
                                          //   const Locale('en', 'US') // English, US
                                          // ],
                                          // // 2. Add a localeResolutionCallback to handle failures
                                          // localeResolutionCallback: (
                                          //   Locale? locale,
                                          //   Iterable<Locale> supportedLocales,
                                          // ) {
                                          //   // Check if the current device locale is supported
                                          //   if (locale != null) {
                                          //     for (var supportedLocale in supportedLocales) {
                                          //       if (supportedLocale.languageCode == locale.languageCode) {
                                          //         return supportedLocale;
                                          //       }
                                          //     }
                                          //   }

                                          //   // If the device locale is null or not supported, use a fallback
                                          //   return supportedLocales.first; // e.g., default to 'en_US'
                                          // },
                                          theme: ThemeData(
                                            primaryColor: lightPrimary,
                                            scaffoldBackgroundColor: lightBg,
                                            appBarTheme: AppBarTheme(
                                              backgroundColor: lightBg,
                                              foregroundColor: lightTxt,
                                              scrolledUnderElevation: 0,
                                            ),
                                            dialogTheme: DialogThemeData(
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(16.0),
                                                side: BorderSide(
                                                  color: lightPrimaryColor.value,
                                                  width: 1.0,
                                                ),
                                              ),
                                              backgroundColor: lightBackgroundColor.value,
                                            ),
                                            tooltipTheme: TooltipThemeData(
                                              decoration: BoxDecoration(
                                                color: (lightBackgroundColor.value),
                                                borderRadius: const BorderRadius.all(
                                                  Radius.circular(8.0),
                                                ),
                                              ),
                                              textStyle: TextStyle(
                                                fontSize: uiFontSize,
                                                fontFamily: uiFontFamily,
                                                color: getAdaptiveTextColor(context, usePrimaryColor: false),
                                              ),
                                            ),
                                            switchTheme: SwitchThemeData(
                                              thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
                                                if (states.contains(
                                                  WidgetState.selected,
                                                )) {
                                                  return lightPrimaryColor.value;
                                                }
                                                return Colors.grey;
                                              }),
                                              trackColor: WidgetStateProperty.resolveWith<Color>((states) {
                                                if (states.contains(
                                                  WidgetState.selected,
                                                )) {
                                                  return lightPrimaryColor.value.withValues(
                                                    alpha: 0.5,
                                                  );
                                                }
                                                return Colors.grey.withValues(alpha: 0.5);
                                              }),
                                            ),
                                            sliderTheme: SliderThemeData(
                                              activeTrackColor: lightPrimaryColor.value,
                                              inactiveTrackColor: lightPrimaryColor.value.withValues(alpha: 0.3),
                                              thumbColor: lightPrimaryColor.value,
                                              valueIndicatorColor: lightPrimaryColor.value,
                                            ),
                                            checkboxTheme: CheckboxThemeData(
                                              fillColor: WidgetStateProperty.resolveWith<Color>((states) {
                                                if (states.contains(
                                                  WidgetState.selected,
                                                )) {
                                                  return lightPrimaryColor.value;
                                                }
                                                return Colors.transparent;
                                              }),
                                              checkColor: WidgetStateProperty.all(
                                                Colors.white,
                                              ),
                                            ),
                                            elevatedButtonTheme: ElevatedButtonThemeData(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: lightPrimaryColor.value,
                                                foregroundColor: lightPrimaryColor.value.computeLuminance() > 0.5
                                                    ? Colors.black
                                                    : Colors.white,
                                              ),
                                            ),
                                            textButtonTheme: TextButtonThemeData(
                                              style: TextButton.styleFrom(
                                                foregroundColor: lightPrimaryColor.value,
                                              ),
                                            ),
                                            textSelectionTheme: TextSelectionThemeData(
                                              cursorColor: lightPrimaryColor.value,
                                              selectionColor: lightPrimaryColor.value.withValues(
                                                alpha: 0.3,
                                              ),
                                              selectionHandleColor: lightPrimaryColor.value,
                                            ),
                                            textTheme: TextTheme(
                                              bodyMedium: TextStyle(
                                                color: lightTxt,
                                                fontSize: fontSizeNotifier.value,
                                                fontFamily: fontFamily,
                                              ),
                                              bodyLarge: TextStyle(
                                                color: lightTxt,
                                                fontSize: fontSizeNotifier.value + 2,
                                                fontFamily: fontFamily,
                                              ),
                                              titleLarge: TextStyle(
                                                color: lightTxt,
                                                fontSize: fontSizeNotifier.value + 4,
                                                fontFamily: fontFamily,
                                              ),
                                            ),
                                          ),
                                          darkTheme: ThemeData.dark().copyWith(
                                            primaryColor: darkPrimary,
                                            scaffoldBackgroundColor: darkBg,
                                            appBarTheme: AppBarTheme(
                                              backgroundColor: darkBg,
                                              foregroundColor: darkTxt,
                                              scrolledUnderElevation: 0,
                                            ),
                                            dialogTheme: DialogThemeData(
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(16.0),
                                                side: BorderSide(
                                                  color: darkPrimaryColor.value,
                                                  width: 1.0,
                                                ),
                                              ),
                                              backgroundColor: darkBackgroundColor.value,
                                            ),
                                            tooltipTheme: TooltipThemeData(
                                              decoration: BoxDecoration(
                                                color: (darkBackgroundColor.value),
                                                borderRadius: const BorderRadius.all(
                                                  Radius.circular(8.0),
                                                ),
                                              ),
                                              textStyle: TextStyle(
                                                fontSize: uiFontSize,
                                                fontFamily: uiFontFamily,
                                                color: getAdaptiveTextColor(context, usePrimaryColor: true),
                                              ),
                                            ),
                                            switchTheme: SwitchThemeData(
                                              thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
                                                if (states.contains(
                                                  WidgetState.selected,
                                                )) {
                                                  return darkPrimaryColor.value;
                                                }
                                                return Colors.grey;
                                              }),
                                              trackColor: WidgetStateProperty.resolveWith<Color>((states) {
                                                if (states.contains(
                                                  WidgetState.selected,
                                                )) {
                                                  return darkPrimaryColor.value.withValues(
                                                    alpha: 0.5,
                                                  );
                                                }
                                                return Colors.grey.withValues(alpha: 0.5);
                                              }),
                                            ),
                                            sliderTheme: SliderThemeData(
                                              activeTrackColor: darkPrimaryColor.value,
                                              inactiveTrackColor: darkPrimaryColor.value.withValues(alpha: 0.3),
                                              thumbColor: darkPrimaryColor.value,
                                              valueIndicatorColor: darkPrimaryColor.value,
                                            ),
                                            checkboxTheme: CheckboxThemeData(
                                              fillColor: WidgetStateProperty.resolveWith<Color>((states) {
                                                if (states.contains(
                                                  WidgetState.selected,
                                                )) {
                                                  return darkPrimaryColor.value;
                                                }
                                                return Colors.transparent;
                                              }),
                                              checkColor: WidgetStateProperty.all(
                                                Colors.white,
                                              ),
                                            ),
                                            elevatedButtonTheme: ElevatedButtonThemeData(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: darkPrimaryColor.value,
                                                foregroundColor: darkPrimaryColor.value.computeLuminance() > 0.5
                                                    ? Colors.black
                                                    : Colors.white,
                                              ),
                                            ),
                                            textButtonTheme: TextButtonThemeData(
                                              style: TextButton.styleFrom(
                                                foregroundColor: darkPrimaryColor.value,
                                              ),
                                            ),
                                            textSelectionTheme: TextSelectionThemeData(
                                              cursorColor: darkPrimaryColor.value,
                                              selectionColor: darkPrimaryColor.value.withValues(
                                                alpha: 0.3,
                                              ),
                                              selectionHandleColor: darkPrimaryColor.value,
                                            ),
                                            textTheme: TextTheme(
                                              bodyMedium: TextStyle(
                                                color: darkTxt,
                                                fontSize: fontSizeNotifier.value,
                                                fontFamily: fontFamily,
                                              ),
                                              bodyLarge: TextStyle(
                                                color: darkTxt,
                                                fontSize: fontSizeNotifier.value + 2,
                                                fontFamily: fontFamily,
                                              ),
                                              titleLarge: TextStyle(
                                                color: darkTxt,
                                                fontSize: fontSizeNotifier.value + 4,
                                                fontFamily: fontFamily,
                                              ),
                                            ),
                                          ),
                                          builder: (context, child) {
                                            // This ensures the current, resolved theme is available to the Overlay
                                            return Theme(
                                              data: Theme.of(context),
                                              child: child!,
                                            );
                                          },
                                          themeMode: mode,
                                          navigatorKey: navigatorKey,
                                          scaffoldMessengerKey: scaffoldMessengerKey,
                                          home: ValueListenableBuilder<Color>(
                                            valueListenable: lightVerseReferenceColor,
                                            builder: (context, lightVerseRef, _) {
                                              return ValueListenableBuilder<Color>(
                                                valueListenable: darkVerseReferenceColor,
                                                builder: (context, darkVerseRef, _) {
                                                  return MultiBibleView();
                                                },
                                              );
                                            },
                                          ),
                                          debugShowCheckedModeBanner: false,
                                        );
                                      },
                                    );
                                  },
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class MultiBibleView extends StatefulWidget {
  const MultiBibleView({super.key});
  @override
  State<MultiBibleView> createState() => _MultiBibleViewState();
}

// Save window state to shared preferences on close
class _WindowManagerListener extends WindowListener {
  @override
  Future<bool> onWindowEvent(String eventName) async {
    if (eventName == 'close') {
      final BuildContext? currentContext = navigatorKey.currentContext;

      if (currentContext == null) {
        //await windowManager.destroy();
        // await windowManager.setPreventClose(false);
        // windowManager.close();
        exit(0);
      }

      // Save all current app preferences
      try {
        await _saveAllCurrentPrefs();
      } catch (e) {
        // Continue closing even if saving preferences fails
        if (kDebugMode) {
          debugPrint('Failed to save preferences during shutdown: ${e.toString()}');
        }
      }

      // Check and perform Supabase Sync only if there are pending changes
      if (Supabase.instance.client.auth.currentUser != null) {
        final syncService = SupabaseSyncService();
        bool canConnect = await syncService.checkSupabaseConnection();

        if (canConnect) {
          // Show sync dialog
          if (navigatorKey.currentContext != null) {
            showDialog(
              context: navigatorKey.currentContext!,
              barrierDismissible: false,
              builder: (context) => const SyncDialog(),
            );
          }

          // Perform sync (Awaited blocking operation 2)
          try {
            await syncService.syncAll();
          } catch (e) {
            // Continue closing even if sync fails
            if (kDebugMode) {
              debugPrint('Sync failed during shutdown: ${e.toString()}');
            }
          } finally {
            // Dismiss the sync dialog after sync completes
            if (navigatorKey.currentState?.canPop() ?? false) {
              navigatorKey.currentState?.pop();
            }
          }
        }

        // Properly dispose sync service to handle retry queues
        syncService.dispose();
      }

      // Properly dispose the listeners
      LocalDataChangeNotifier.dispose();

      // This only runs after all saving and syncing is complete.
      //await windowManager.destroy();
      // await windowManager.setPreventClose(false);
      // await windowManager.close();
      exit(0);
    } else {
      // For all other window events, allow default behavior
      return true;
    }
  }
}

class _MultiBibleViewState extends State<MultiBibleView> with WidgetsBindingObserver {
  List<Map<String, dynamic>> _screenLocations = [];
  bool _windowManagerInitialized = false;
  bool _fullscreenChanging = false;
  _WindowManagerListener? _windowListener;
  bool _wasMaximizedBeforeFullscreen = false; // Track maximized state before fullscreen
  final FocusNode _invisibleElevatedButtonNode = FocusNode();

  // TODO: test to make sure this isn't needed on mobile
  // @override
  // void didChangeMetrics() {
  //   super.didChangeMetrics();

  //   // Reapply fullscreen if keyboard appeared and fullscreen is enabled
  //   if (!kIsWeb &&
  //       (fullscreenNotifier.value && (Platform.isAndroid || Platform.isIOS))) {
  //     // Small delay to ensure keyboard animation is complete
  //     Future.delayed(Duration(milliseconds: 100), () {
  //       if (mounted && fullscreenNotifier.value) {
  //         SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  //       }
  //     });
  //   }
  // }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      super.didChangeAppLifecycleState(state);

      // Handle mobile app termination/backgrounding to ensure sync service cleanup
      if (state == AppLifecycleState.detached) {
        if (kDebugMode) debugPrint('AppLifecycleState.detached');
        // App is being terminated/killed - save preferences and dispose sync service
        _saveAllCurrentPrefs(); // Save preferences like desktop close handler does

        // Properly dispose the listeners
        LocalDataChangeNotifier.dispose();

        // Properly dispose sync service to handle retry queues
        if (Supabase.instance.client.auth.currentUser != null) {
          SupabaseSyncService().dispose();
        }
      } else if (state == AppLifecycleState.inactive) {
        if (kDebugMode) debugPrint('AppLifecycleState.inactive');
        // App in inactive state
      }
      // Note: We handle paused separately in case the app gets suspended but not detached
      else if (state == AppLifecycleState.paused) {
        if (kDebugMode) debugPrint('AppLifecycleState.paused');
        // App is going to background - stop connectivity monitoring to save battery
        if (Supabase.instance.client.auth.currentUser != null) {
          SupabaseSyncService().stopConnectionMonitoring();
        }
      }
      // Handle app returning to foreground - re-establish realtime listeners
      else if (state == AppLifecycleState.resumed) {
        if (kDebugMode) debugPrint('AppLifecycleState.resumed');

        // App is coming back to foreground - restart sync service for realtime listeners
        if (Supabase.instance.client.auth.currentUser != null) {
          try {
            SupabaseSyncService().restartConnectionMonitoring();
          } catch (e) {
            if (kDebugMode) {
              debugPrint(
                  'AppLifecycleState.resumed SupabaseSyncService().restartConnectionMonitoring exception: ${e.toString()}');
            }
          }

          try {
            SupabaseSyncService().syncRecentChangesOnly();
          } catch (e) {
            if (kDebugMode) {
              debugPrint(
                  'AppLifecycleState.resumed SupabaseSyncService().syncRecentChangesOnly exception: ${e.toString()}');
            }
          }
        }
      }
    }
  }

  // MultiBibleView widget
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initWindowManager();
    _loadScreensFromPrefs();
    themeModeNotifier.addListener(_saveThemeMode);
    fullscreenNotifier.addListener(_applyFullscreen);
  }

  @override
  void dispose() {
    // Remove listeners to prevent memory leaks
    themeModeNotifier.removeListener(_saveThemeMode);
    fullscreenNotifier.removeListener(_applyFullscreen);

    // Remove window listener if it exists
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS) && _windowListener != null) {
      windowManager.removeListener(_windowListener!);
    }

    // Remove binding observer
    WidgetsBinding.instance.removeObserver(this);

    _invisibleElevatedButtonNode.dispose();

    super.dispose();
  }

  void _initWindowManager() async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      windowManager.ensureInitialized();

      // Get primary display size for screen-aware sizing
      final primaryDisplay = await screenRetriever.getPrimaryDisplay();
      final screenSize = primaryDisplay.size;

      // Only load saved window size and maximized state from preferences if not mobile
      final prefs = await SharedPreferences.getInstance();
      double? width, height;
      bool maximized = false;
      if (!(Platform.isAndroid || Platform.isIOS)) {
        maximized = prefs.getBool('windowMaximized') ?? false; // Default to un-maximized for better UX
        if (!maximized) {
          width = prefs.getDouble('windowWidth') ?? (screenSize.width * 0.9);
          height = prefs.getDouble('windowHeight') ?? (screenSize.height * 0.8);
        }
      }

      final options = WindowOptions(
        size: (!maximized && width != null && height != null) ? Size(width, height) : const Size(900, 700),
        center: true,
        //backgroundColor: Colors.transparent, // enabling this causes problems with shading on desktop
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.normal,
      );
      await windowManager.waitUntilReadyToShow(options, () async {
        await windowManager.show();
        await windowManager.focus();
        // Restore maximized state if needed
        if (maximized) {
          await windowManager.maximize();
        }
      });

      // Keep a reference to the listener
      _windowListener ??= _WindowManagerListener();
      windowManager.addListener(_windowListener!);
      _windowManagerInitialized = true;

      // Optionally, override the window close event to ensure preferences are saved
      windowManager.setPreventClose(true);
    }
  }

  bool _shouldForceHorizontal() {
    if (_screenLocations.length <= 1) return false;
    if (!mounted) return true; // assume narrow if not mounted
    final screenWidth = MediaQuery.of(context).size.width;
    return screenWidth <= 800.0;
  }

  Future<void> _loadScreensFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final screensJson = prefs.getString('screens');
    if (screensJson != null && screensJson.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(screensJson);
        _screenLocations = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (e) {
        _screenLocations = [
          {'book': null, 'chapter': null, 'verse': null},
        ];
      }
    } else {
      _screenLocations = [
        {'book': null, 'chapter': null, 'verse': null},
      ];
    }
    if (_screenLocations.isEmpty) {
      _screenLocations = [
        {'book': null, 'chapter': null, 'verse': null},
      ];
    }
    // Enforce horizontal mode if screen is narrow and more than one screen is present
    if (_shouldForceHorizontal()) {
      if (isVerticalTile.value) {
        isVerticalTile.value = false;
        _saveTileState();
      }
    }
    if (mounted) {
      setState(() {}); // only call setState if mounted
    }
  }

  Future<void> _saveScreensToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('screens', jsonEncode(_screenLocations));
  }

  Future<void> _saveNavigationbarPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('showNavigationBar', showNavigationBarNotifier.value);
  }

  Future<void> _saveInlineNotesPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('showNotesInline', showNotesInlineNotifier.value);
  }

  void _addView() {
    final isVertical = isVerticalTile.value;
    final maxScreens = isVertical ? maxVerticalScreens.value : maxHorizontalScreens.value;
    if (_screenLocations.length >= maxScreens) return;
    setState(() {
      _screenLocations.add({'book': null, 'chapter': null, 'verse': null});
    });
    _saveScreensToPrefs();
    // If narrow screen and more than one screen, switch to horizontal
    if (_shouldForceHorizontal() && isVerticalTile.value) {
      isVerticalTile.value = false;
      _saveTileState();
      // Optional feedback
      showStyledSnackBar(context, 'Vertical mode requires a wider screen');
    }
  }

  void _removeView(int index) {
    if (_screenLocations.length > 1) {
      setState(() {
        _screenLocations.removeAt(index);
      });
      _saveScreensToPrefs();
    }
  }

  void _updateLocation(int index, String? book, int? chapter, int? verse) {
    setState(() {
      _screenLocations[index] = {
        'book': book,
        'chapter': chapter,
        'verse': verse,
        'navigationTimestamp': DateTime.now().millisecondsSinceEpoch,
      };
    });
    _saveScreensToPrefs();
  }

  void _toggleTile() async {
    final wasVertical = isVerticalTile.value;
    final newVertical = !wasVertical;

    // Block switching to vertical if narrow screen and more than one screen exists
    if (newVertical && _shouldForceHorizontal()) {
      showStyledSnackBar(context, 'Vertical mode requires a wider screen');
      return;
    }

    if (newVertical && _screenLocations.length > maxVerticalScreens.value) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          constraints: const BoxConstraints(maxWidth: 400),
          title: Text(
            'Warning',
            style: TextStyle(
              fontSize: uiFontSize,
              fontFamily: uiFontFamily,
              color: Colors.red,
            ),
          ),
          content: Text(
            'Switching to vertical mode will remove the last Bible screen to enforce the maximum of ${maxVerticalScreens.value}. Are you sure?',
            style: TextStyle(
              fontSize: uiFontSize,
              fontFamily: uiFontFamily,
              color: getAdaptiveTextColor(context),
            ),
          ),
          actions: [
            TextButton(
              child: Text(
                'No',
                style: TextStyle(
                  fontSize: uiFontSize,
                  fontFamily: uiFontFamily,
                  color: getAdaptiveTextColor(context),
                ),
              ),
              onPressed: () => Navigator.pop(context, false),
            ),
            TextButton(
              child: Text(
                'Yes',
                style: TextStyle(
                  fontSize: uiFontSize,
                  fontFamily: uiFontFamily,
                  color: Colors.red,
                ),
              ),
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      setState(() {
        while (_screenLocations.length > maxVerticalScreens.value) {
          _screenLocations.removeLast();
        }
      });
      _saveScreensToPrefs();
    } else if (!newVertical && _screenLocations.length > maxHorizontalScreens.value) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          constraints: const BoxConstraints(maxWidth: 400),
          title: Text(
            'Warning',
            style: TextStyle(
              fontSize: uiFontSize,
              fontFamily: uiFontFamily,
              color: Colors.red,
            ),
          ),
          content: Text(
            'Switching to horizontal mode will remove the last Bible screen to enforce the maximum of ${maxHorizontalScreens.value}. Are you sure?',
            style: TextStyle(
              fontSize: uiFontSize,
              fontFamily: uiFontFamily,
              color: getAdaptiveTextColor(context),
            ),
          ),
          actions: [
            TextButton(
              child: Text(
                'No',
                style: TextStyle(
                  fontSize: uiFontSize,
                  fontFamily: uiFontFamily,
                  color: getAdaptiveTextColor(context),
                ),
              ),
              onPressed: () => Navigator.pop(context, false),
            ),
            TextButton(
              child: Text(
                'Yes',
                style: TextStyle(
                  fontSize: uiFontSize,
                  fontFamily: uiFontFamily,
                  color: Colors.red,
                ),
              ),
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      setState(() {
        while (_screenLocations.length > maxHorizontalScreens.value) {
          _screenLocations.removeLast();
        }
      });
      _saveScreensToPrefs();
    }
    isVerticalTile.value = newVertical;
    _saveTileState();
  }

  Future<void> _saveTileState() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('isVerticalTile', isVerticalTile.value);
  }

  Future<void> _saveFontPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setDouble('fontSize', fontSizeNotifier.value);
    prefs.setString('fontFamily', fontFamilyNotifier.value);
    prefs.setString('noteFontFamily', noteFontFamilyNotifier.value);
  }

  Future<void> _saveCustomColors() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('lightPrimaryColor', _colorToHex(lightPrimaryColor.value));
    prefs.setString(
      'lightBackgroundColor',
      _colorToHex(lightBackgroundColor.value),
    );
    prefs.setString('lightTextColor', _colorToHex(lightTextColor.value));
    prefs.setString('darkPrimaryColor', _colorToHex(darkPrimaryColor.value));
    prefs.setString(
      'darkBackgroundColor',
      _colorToHex(darkBackgroundColor.value),
    );
    prefs.setString('darkTextColor', _colorToHex(darkTextColor.value));
    prefs.setString(
      'lightHighlightColor',
      _colorToHex(lightHighlightColor.value),
    );
    prefs.setString(
      'darkHighlightColor',
      _colorToHex(darkHighlightColor.value),
    );
    prefs.setString(
      'lightVerseReferenceColor',
      _colorToHex(lightVerseReferenceColor.value),
    );
    prefs.setString(
      'darkVerseReferenceColor',
      _colorToHex(darkVerseReferenceColor.value),
    );
  }

  void _resetCustomColors() {
    lightPrimaryColor.value = hexToColor(defaultLightPrimaryColorHex);
    lightBackgroundColor.value = hexToColor(defaultLightBackgroundColorHex);
    lightTextColor.value = hexToColor(defaultLightTextColorHex);
    darkPrimaryColor.value = hexToColor(defaultDarkPrimaryColorHex);
    darkBackgroundColor.value = hexToColor(defaultDarkBackgroundColorHex);
    darkTextColor.value = hexToColor(defaultDarkTextColorHex);
    lightHighlightColor.value = hexToColor(defaultLightHighlightColorHex);
    darkHighlightColor.value = hexToColor(defaultDarkHighlightColorHex);
    lightVerseReferenceColor.value = hexToColor(defaultLightVerseReferenceColorHex);
    darkVerseReferenceColor.value = hexToColor(defaultDarkVerseReferenceColorHex);
  }

  Future<void> _saveHighlightColorsPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setStringList(
      'highlightColors',
      highlightColorsNotifier.value.map((c) => c.toARGB32().toString()).toList(),
    );
  }

  Future<void> _saveThemeMode() async {
    final prefs = await SharedPreferences.getInstance();

    // Determine theme mode value
    int themeModeValue;
    if (_isTimeBasedThemeEnabled) {
      // Time-based theme is enabled, save as 3
      themeModeValue = 3;
    } else if (themeModeNotifier.value == ThemeMode.light) {
      themeModeValue = 1;
    } else if (themeModeNotifier.value == ThemeMode.dark) {
      themeModeValue = 2;
    } else {
      themeModeValue = 0; // System
    }

    prefs.setInt('themeMode', themeModeValue);
  }

  Future<void> _saveSyncPrefs(String category) async {
    if (category.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();

      switch (category) {
        case 'highlights':
          prefs.setBool('syncHighlights', syncHighlightsNotifier.value);
        case 'notes':
          prefs.setBool('syncNotes', syncNotesNotifier.value);
        case 'history':
          prefs.setBool('syncHistory', syncHistoryNotifier.value);
        case 'search_history':
          prefs.setBool('syncSearchHistory', syncSearchHistoryNotifier.value);
      }
    }
  }

  Future<void> _saveFullscreenPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    prefs.setBool('fullscreen', fullscreenNotifier.value);
  }

  void _showHistoryDialog(BuildContext context, int screenIndex) async {
    // Guard: avoid using the provided BuildContext after async gap
    if (!context.mounted) return;

    showDialog(
      context: context,
      useSafeArea: true,
      builder: (context) {
        return VerseHistoryDialog(
          //screenIndex: screenIndex,
          onUpdateLocation: (book, chapter, verse) => _updateLocation(screenIndex, book, chapter, verse),
        );
      },
    );
  }

  void _showCustomizeHighlightColorsDialog(BuildContext context) {
    showDialog(
      context: context,
      useSafeArea: true,
      builder: (context) => Dialog(
        child: Container(
          width: 500,
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: Center(
                    child: Text(
                      'Customize highlight colors',
                      style: TextStyle(
                        fontSize: uiFontSize,
                        fontFamily: uiFontFamily,
                        fontWeight: FontWeight.bold,
                        color: getAdaptiveTextColor(context),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                ValueListenableBuilder<List<Color>>(
                  valueListenable: highlightColorsNotifier,
                  builder: (context, colors, _) {
                    return Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        runAlignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: colors.asMap().entries.map((entry) {
                          final index = entry.key;
                          final color = entry.value;
                          return GestureDetector(
                            onTap: () async {
                              Color? picked = await _showColorPickerDialog(
                                context,
                                color,
                              );
                              if (picked != color) {
                                final newColors = List<Color>.from(colors);
                                newColors[index] = picked;
                                highlightColorsNotifier.value = newColors;
                                _saveHighlightColorsPrefs();
                              }
                            },
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: color,
                                border: Border.all(
                                  color: Colors.grey.shade400,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 51),
                                    blurRadius: 2,
                                    offset: Offset(1, 1),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                                    fontWeight: FontWeight.normal,
                                    fontSize: uiFontSize,
                                    fontFamily: uiFontFamily,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'Tap any color above to change it.',
                  style: TextStyle(
                    fontSize: uiFontSize - 4,
                    fontFamily: uiFontFamily,
                    fontStyle: FontStyle.italic,
                    color: getAdaptiveTextColor(context),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      child: Text(
                        'Reset',
                        style: TextStyle(
                          fontSize: uiFontSize,
                          fontFamily: uiFontFamily,
                          color: Colors.red,
                        ),
                      ),
                      onPressed: () {
                        highlightColorsNotifier.value = defaultHighlightColors;
                        _saveHighlightColorsPrefs();
                      },
                    ),
                    Row(
                      children: [
                        TextButton(
                          child: Text(
                            'Close',
                            style: TextStyle(
                              fontSize: uiFontSize,
                              fontFamily: uiFontFamily,
                              color: getAdaptiveTextColor(context),
                            ),
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCustomizeColorsDialog(BuildContext context) {
    showDialog(
      context: context,
      useSafeArea: true,
      builder: (context) => Dialog(
        child: Container(
          width: 350,
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: Center(
                    child: Text(
                      'Light Mode',
                      style: TextStyle(
                        fontSize: uiFontSize,
                        fontFamily: uiFontFamily,
                        fontWeight: FontWeight.bold,
                        color: getAdaptiveTextColor(context),
                      ),
                    ),
                  ),
                ),
                _colorPickerRow('Primary', lightPrimaryColor),
                _colorPickerRow('Background', lightBackgroundColor),
                _colorPickerRow('Text', lightTextColor),
                _colorPickerRow('Search Highlight', lightHighlightColor),
                _colorPickerRow('Verse References', lightVerseReferenceColor),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: Center(
                    child: Text(
                      'Dark Mode',
                      style: TextStyle(
                        fontSize: uiFontSize,
                        fontFamily: uiFontFamily,
                        fontWeight: FontWeight.bold,
                        color: getAdaptiveTextColor(context),
                      ),
                    ),
                  ),
                ),
                _colorPickerRow('Primary', darkPrimaryColor),
                _colorPickerRow('Background', darkBackgroundColor),
                _colorPickerRow('Text', darkTextColor),
                _colorPickerRow('Search Highlight', darkHighlightColor),
                _colorPickerRow('Verse Reference', darkVerseReferenceColor),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      child: Text(
                        'Reset',
                        style: TextStyle(
                          fontSize: uiFontSize,
                          fontFamily: uiFontFamily,
                          color: Colors.red,
                        ),
                      ),
                      onPressed: () {
                        _resetCustomColors();
                      },
                    ),
                    TextButton(
                      child: Text(
                        'Save',
                        style: TextStyle(
                          fontSize: uiFontSize,
                          fontFamily: uiFontFamily,
                          color: getAdaptiveTextColor(context),
                        ),
                      ),
                      onPressed: () async {
                        _saveCustomColors();
                        // Guard: dialog's BuildContext after await
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                    ),
                    TextButton(
                      child: Text(
                        'Close',
                        style: TextStyle(
                          fontSize: uiFontSize,
                          fontFamily: uiFontFamily,
                          color: getAdaptiveTextColor(context),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _colorPickerRow(String label, ValueNotifier<Color> colorNotifier) {
    return ValueListenableBuilder<Color>(
      valueListenable: colorNotifier,
      builder: (context, color, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context),
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 1,
                child: Center(
                  child: GestureDetector(
                    onTap: () async {
                      Color picked = await _showColorPickerDialog(
                        context,
                        colorNotifier.value,
                      );
                      colorNotifier.value = picked;
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color,
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<Color> _showColorPickerDialog(
    BuildContext context,
    Color currentColor,
  ) async {
    Color tempColor = currentColor;
    return await showDialog<Color>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text(
                'Choose a color',
                style: TextStyle(
                  fontSize: uiFontSize,
                  fontFamily: uiFontFamily,
                  color: getAdaptiveTextColor(context),
                ),
                textAlign: TextAlign.center,
              ),
              content: StatefulBuilder(
                builder: (context, setState) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Slider(
                        value: (tempColor.r * 255.0),
                        min: 0,
                        max: 255,
                        label: 'R',
                        activeColor: Colors.red,
                        onChanged: (v) {
                          setState(() {
                            tempColor = tempColor.withRed(v.toInt());
                          });
                        },
                      ),
                      Slider(
                        value: (tempColor.g * 255.0),
                        min: 0,
                        max: 255,
                        label: 'G',
                        activeColor: Colors.green,
                        onChanged: (v) {
                          setState(() {
                            tempColor = tempColor.withGreen(v.toInt());
                          });
                        },
                      ),
                      Slider(
                        value: (tempColor.b * 255.0),
                        min: 0,
                        max: 255,
                        label: 'B',
                        activeColor: Colors.blue,
                        onChanged: (v) {
                          setState(() {
                            tempColor = tempColor.withBlue(v.toInt());
                          });
                        },
                      ),
                      Container(
                        width: 48,
                        height: 48,
                        margin: EdgeInsets.only(top: 8),
                        decoration: BoxDecoration(
                          color: tempColor,
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  );
                },
              ),
              actions: [
                TextButton(
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context, currentColor),
                ),
                TextButton(
                  child: Text(
                    'Select',
                    style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context, tempColor),
                ),
              ],
            );
          },
        ) ??
        currentColor;
  }

  void _applyFullscreen() async {
    if (_fullscreenChanging) return; // Prevent re-entrancy
    _fullscreenChanging = true;
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      if (!_windowManagerInitialized) {
        _initWindowManager();
      }

      // Only proceed if window manager is still valid
      if (!_windowManagerInitialized) {
        if (kDebugMode) {
          debugPrint('Window manager not ready, skipping fullscreen change');
        }
        return;
      }

      if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        if (fullscreenNotifier.value) {
          // Save maximized state before entering fullscreen
          _wasMaximizedBeforeFullscreen = await windowManager.isMaximized();

          bool isMaximized = _wasMaximizedBeforeFullscreen;
          if (isMaximized) {
            await windowManager.setFullScreen(false);
            await windowManager.unmaximize();
          }
        } else {
          // Exiting fullscreen: restore maximized state if needed
          await windowManager.setFullScreen(false);

          if (_wasMaximizedBeforeFullscreen) {
            //await Future.delayed(Duration(milliseconds: 150));
            await windowManager.show();
            // TODO: this needs testing on linux and mac desktop
            await windowManager.maximize();
            _wasMaximizedBeforeFullscreen = false;
          }
        }

        await windowManager.setFullScreen(fullscreenNotifier.value);
      }
    } else {
      // Determine brightness for icon colors when toggling on mobile
      // TODO: test on android/ios, no idea why this is here or if it's needed
      final systemBrightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
      final bool isDarkTheme = themeModeNotifier.value == ThemeMode.dark ||
          (themeModeNotifier.value == ThemeMode.system && systemBrightness == Brightness.dark);

      if (fullscreenNotifier.value) {
        // Use immersiveSticky mode for more persistent fullscreen that resists keyboard appearance
        await SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.immersiveSticky,
        );
        // changed: setSystemUIOverlayStyle returns void; do not await
        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            statusBarIconBrightness: isDarkTheme ? Brightness.light : Brightness.dark,
            systemNavigationBarIconBrightness: isDarkTheme ? Brightness.light : Brightness.dark,
          ),
        );
      } else {
        // Restore system UI overlays when exiting fullscreen
        await SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: SystemUiOverlay.values,
        );
      }
    }
    _saveFullscreenPrefs();

    _fullscreenChanging = false;
  }

  // Main options drawer
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      drawer: Drawer(
        backgroundColor:
            Theme.of(context).brightness == Brightness.dark ? darkBackgroundColor.value : lightBackgroundColor.value,
        child: ValueListenableBuilder<String>(
          valueListenable: fontFamilyNotifier,
          builder: (context, fontFamily, _) {
            return SingleChildScrollView(
              child: Column(
                //mainAxisSize: MainAxisSize.min,
                children: [
                  // This invisible ElevatedButton is necessary to circumvent a bug
                  // on windows desktop where the OSK will pop up for nearly any
                  // ui event after entering a TextField. It's focusNode must be
                  // forced after any interaction with a TextField to circumvent
                  // the bug.
                  ElevatedButton(
                    onPressed: () {},
                    focusNode: _invisibleElevatedButtonNode,
                    style: ElevatedButton.styleFrom(
                        //minimumSize: Size(1, 1), // DO NOT SET THIS OR THE BUG CIRCUMVENTION WILL NOT WORK
                        //maximumSize: Size(1, 1),
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        overlayColor:
                            Colors.transparent, // required or the button can be seen under certain circumstances
                        iconColor: Colors.transparent,
                        disabledIconColor: Colors.transparent,
                        disabledBackgroundColor: Colors.transparent,
                        disabledForegroundColor: Colors.transparent,
                        surfaceTintColor: Colors.transparent),
                    child: SizedBox.shrink(),
                  ),
                  //const SizedBox(height: 8),
                  SizedBox(
                    height: 50,
                    child: ValueListenableBuilder<bool>(
                      valueListenable: isVerticalTile,
                      builder: (context, isVertical, _) {
                        return SwitchListTile(
                          title: Text(
                            isVertical ? 'Vertical layout' : 'Horizontal layout',
                            style: TextStyle(
                              fontSize: uiFontSize,
                              fontFamily: uiFontFamily,
                              color: getAdaptiveTextColor(context),
                            ),
                          ),
                          value: isVertical,
                          onChanged: (val) {
                            _toggleTile();
                          },
                        );
                      },
                    ),
                  ),
                  if (!kIsWeb)
                    SizedBox(
                      height: 50,
                      child: ValueListenableBuilder<bool>(
                        valueListenable: fullscreenNotifier,
                        builder: (context, fullscreen, _) {
                          return SwitchListTile(
                            title: Text(
                              'Fullscreen',
                              style: TextStyle(
                                fontSize: uiFontSize,
                                fontFamily: uiFontFamily,
                                color: getAdaptiveTextColor(context),
                              ),
                            ),
                            value: fullscreen,
                            onChanged: (val) {
                              fullscreenNotifier.value = val;
                            },
                          );
                        },
                      ),
                    ),
                  // Add: navigation bar display mode toggle
                  SizedBox(
                    height: 50,
                    child: ValueListenableBuilder<bool>(
                      valueListenable: showNavigationBarNotifier,
                      builder: (context, showNavBar, _) {
                        return SwitchListTile(
                          title: Text(
                            'Navigation Bar', //showNavBar ? 'Show navigation bar' : 'Hide navigation bar',
                            style: TextStyle(
                              fontSize: uiFontSize,
                              fontFamily: uiFontFamily,
                              color: getAdaptiveTextColor(context),
                            ),
                          ),
                          value: showNavBar,
                          onChanged: (val) async {
                            showNavigationBarNotifier.value = val;
                            _saveNavigationbarPrefs();
                          },
                        );
                      },
                    ),
                  ),
                  // Add: notes display mode toggle
                  SizedBox(
                    height: 50,
                    child: ValueListenableBuilder<bool>(
                      valueListenable: showNotesInlineNotifier,
                      builder: (context, showInline, _) {
                        return SwitchListTile(
                          title: Text(
                            'Inline Notes', //showInline ? 'Inline Notes' : 'Notes as Icons',
                            style: TextStyle(
                              fontSize: uiFontSize,
                              fontFamily: uiFontFamily,
                              color: getAdaptiveTextColor(context),
                            ),
                          ),
                          value: showInline,
                          onChanged: (val) async {
                            showNotesInlineNotifier.value = val;
                            _saveInlineNotesPrefs();
                          },
                        );
                      },
                    ),
                  ),
                  Divider(),
                  Text(
                    'Screens',
                    style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      _addView();
                    },
                    label: Text(
                      'Add Bible View',
                      style: TextStyle(
                        fontSize: uiFontSize,
                        fontFamily: uiFontFamily,
                        color: getAdaptiveTextColor(
                          context,
                          usePrimaryColor: true,
                        ),
                      ),
                    ),
                    icon: Icon(
                      Icons.add_box,
                      color: getAdaptiveTextColor(
                        context,
                        usePrimaryColor: true,
                      ),
                      semanticLabel: 'Add Bible View',
                    ),
                  ),
                  ..._screenLocations.length > 1
                      ? _screenLocations.asMap().entries.where((entry) => entry.key != 0).map(
                            (entry) => Column(
                              children: [
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    _removeView(entry.key);
                                  },
                                  label: Text(
                                    'Remove View ${entry.key + 1}',
                                    style: TextStyle(
                                      fontSize: uiFontSize,
                                      fontFamily: uiFontFamily,
                                      color: getAdaptiveTextColor(
                                        context,
                                        usePrimaryColor: true,
                                      ),
                                    ),
                                  ),
                                  icon: Icon(
                                    Icons.remove,
                                    color: getAdaptiveTextColor(
                                      context,
                                      usePrimaryColor: true,
                                    ),
                                    semanticLabel: 'Remove Bible View ${entry.key + 1}',
                                  ),
                                ),
                              ],
                            ),
                          )
                      : [],
                  const SizedBox(height: 16),
                  Divider(),
                  Text(
                    'Bible Font',
                    style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context),
                    ),
                  ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return SizedBox(
                        width: constraints.maxWidth * 0.70,
                        child: DropdownButton<String>(
                          value: fontFamilyNotifier.value,
                          items: availableFonts
                              .map(
                                (fontPreview) => DropdownMenuItem(
                                  value: fontPreview,
                                  child: Text(
                                    fontPreview,
                                    style: TextStyle(
                                      fontSize: uiFontSize,
                                      fontFamily: fontPreview,
                                      color: getAdaptiveTextColor(context),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              fontFamilyNotifier.value = val;
                              _saveFontPrefs();
                            }
                          },
                          isExpanded: true,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          fontSizeNotifier.value = (fontSizeNotifier.value - 1).clamp(12.0, 36.0);
                          _saveFontPrefs();
                        },
                        //child: Text('-', style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily)),
                        child: Icon(
                          Icons.remove,
                          color: getAdaptiveTextColor(
                            context,
                            usePrimaryColor: true,
                          ),
                          semanticLabel: 'Decrease Font Size',
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '${fontSizeNotifier.value.toInt()}',
                        style: TextStyle(
                          fontSize: uiFontSize,
                          fontFamily: uiFontFamily,
                          color: getAdaptiveTextColor(context),
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: () {
                          fontSizeNotifier.value = (fontSizeNotifier.value + 1).clamp(12.0, 36.0);
                          _saveFontPrefs();
                        },
                        child: Icon(
                          Icons.add,
                          color: getAdaptiveTextColor(
                            context,
                            usePrimaryColor: true,
                          ),
                          semanticLabel: 'Increase Font Size',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Note Font',
                    style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context),
                    ),
                  ),
                  ValueListenableBuilder<String>(
                    valueListenable: noteFontFamilyNotifier,
                    builder: (context, noteFontFamily, _) {
                      return LayoutBuilder(
                        builder: (context, constraints) {
                          return SizedBox(
                            width: constraints.maxWidth * 0.70,
                            child: DropdownButton<String>(
                              value: noteFontFamily,
                              items: availableFonts
                                  .map(
                                    (fontPreview) => DropdownMenuItem(
                                      value: fontPreview,
                                      child: Text(
                                        fontPreview,
                                        style: TextStyle(
                                          fontSize: uiFontSize,
                                          fontFamily: fontPreview,
                                          color: getAdaptiveTextColor(context),
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  noteFontFamilyNotifier.value = val;
                                  _saveFontPrefs();
                                }
                              },
                              isExpanded: true,
                            ),
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Divider(),
                  Text(
                    'Theme',
                    style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context),
                    ),
                  ),
                  SizedBox(
                    height: 40,
                    child: CheckboxListTile(
                      title: Text(
                        'Auto',
                        style: TextStyle(
                          fontSize: uiFontSize,
                          fontFamily: uiFontFamily,
                          color: getAdaptiveTextColor(context),
                        ),
                      ),
                      value: _isTimeBasedThemeEnabled ? false : themeModeNotifier.value == ThemeMode.system,
                      visualDensity: VisualDensity.compact,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 0.0,
                        horizontal: 50.0,
                      ),
                      onChanged: (val) {
                        themeModeNotifier.value = ThemeMode.system;
                        _isTimeBasedThemeEnabled = false;
                        _timeBasedThemeTimer?.cancel();
                        _timeBasedThemeTimer = null;
                      },
                    ),
                  ),
                  SizedBox(
                    height: 40,
                    child: CheckboxListTile(
                      title: Text(
                        'Light',
                        style: TextStyle(
                          fontSize: uiFontSize,
                          fontFamily: uiFontFamily,
                          color: getAdaptiveTextColor(context),
                        ),
                      ),
                      value: _isTimeBasedThemeEnabled ? false : themeModeNotifier.value == ThemeMode.light,
                      visualDensity: VisualDensity.compact,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 0.0,
                        horizontal: 50.0,
                      ),
                      onChanged: (val) {
                        themeModeNotifier.value = ThemeMode.light;
                        _isTimeBasedThemeEnabled = false;
                        _timeBasedThemeTimer?.cancel();
                        _timeBasedThemeTimer = null;
                      },
                    ),
                  ),
                  SizedBox(
                    height: 40,
                    child: CheckboxListTile(
                      title: Text(
                        'Dark',
                        style: TextStyle(
                          fontSize: uiFontSize,
                          fontFamily: uiFontFamily,
                          color: getAdaptiveTextColor(context),
                        ),
                      ),
                      value: _isTimeBasedThemeEnabled ? false : themeModeNotifier.value == ThemeMode.dark,
                      visualDensity: VisualDensity.compact,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 0.0,
                        horizontal: 50.0,
                      ),
                      onChanged: (val) {
                        themeModeNotifier.value = ThemeMode.dark;
                        _isTimeBasedThemeEnabled = false;
                        _timeBasedThemeTimer?.cancel();
                        _timeBasedThemeTimer = null;
                      },
                    ),
                  ),
                  SizedBox(
                    height: 40,
                    child: CheckboxListTile(
                      title: Text(
                        'Time-based',
                        style: TextStyle(
                          fontSize: uiFontSize,
                          fontFamily: uiFontFamily,
                          color: getAdaptiveTextColor(context),
                        ),
                      ),
                      value: _isTimeBasedThemeSelected(),
                      visualDensity: VisualDensity.compact,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 0.0,
                        horizontal: 50.0,
                      ),
                      onChanged: (val) async {
                        if (val == true) {
                          // Enable time-based theme
                          _isTimeBasedThemeEnabled = true;
                          //final prefs = await SharedPreferences.getInstance();
                          //await prefs.setInt('themeMode', 3); // 3 = time-based
                          _initializeTimeBasedTheme();
                          // Update theme immediately based on current time
                          _updateThemeBasedOnTime();
                        } else {
                          // Disable time-based theme - revert to system
                          _isTimeBasedThemeEnabled = false;
                          themeModeNotifier.value = ThemeMode.system;
                        }
                        _saveThemeMode();
                      },
                    ),
                  ),
                  // Time-based theme status (only show when time-based theme is enabled)
                  if (_isTimeBasedThemeEnabled)
                    ValueListenableBuilder<int>(
                      valueListenable: dayStartHourNotifier,
                      builder: (context, dayStartHour, _) {
                        return ValueListenableBuilder<int>(
                          valueListenable: nightStartHourNotifier,
                          builder: (context, nightStartHour, _) {
                            return ListTile(
                              title: Center(
                                child: Text(
                                  _getTimeBasedThemeStatus(),
                                  style: TextStyle(
                                    fontSize: uiFontSize - 2,
                                    fontFamily: uiFontFamily,
                                    color: getAdaptiveTextColor(context),
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  // Time-based theme settings (only show when time-based theme is enabled)
                  if (_isTimeBasedThemeEnabled)
                    ListTile(
                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.schedule,
                            color: getAdaptiveTextColor(context),
                            semanticLabel: 'Configure Time Based Theme Color Options',
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Configure',
                            style: TextStyle(
                              fontSize: uiFontSize,
                              fontFamily: uiFontFamily,
                              color: getAdaptiveTextColor(context),
                            ),
                          ),
                        ],
                      ),
                      onTap: () => _showTimeBasedThemeSettingsDialog(context),
                    ),
                  Divider(),
                  ListTile(
                    title: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.highlight,
                          color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
                          semanticLabel: 'Customize Highlights',
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Customize Highlights',
                          style: TextStyle(
                            fontSize: uiFontSize,
                            fontFamily: uiFontFamily,
                            color: getAdaptiveTextColor(context),
                          ),
                        ),
                      ],
                    ),
                    onTap: () => _showCustomizeHighlightColorsDialog(context),
                  ),

                  ListTile(
                    title: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.color_lens,
                          color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
                          semanticLabel: 'Customize Colors',
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Customize Colors',
                          style: TextStyle(
                            fontSize: uiFontSize,
                            fontFamily: uiFontFamily,
                            color: getAdaptiveTextColor(context),
                          ),
                        ),
                      ],
                    ),
                    onTap: () => _showCustomizeColorsDialog(context),
                  ),

                  Divider(),
                  // Authentication UI
                  ValueListenableBuilder<bool>(
                    valueListenable: isSignedIn,
                    builder: (context, signedIn, _) {
                      if (signedIn) {
                        return ValueListenableBuilder<User?>(
                          valueListenable: currentUser,
                          builder: (context, user, _) {
                            return FutureBuilder<String?>(
                              future: _getUsername(user),
                              builder: (context, snapshot) {
                                final username = snapshot.data ?? 'Unknown';
                                return ListTile(
                                  title: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      //Icon(Icons.cloud_done, color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '✅ Signed in as $username',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: uiFontSize,
                                            fontFamily: uiFontFamily,
                                            color: getAdaptiveTextColor(
                                              context,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  onTap: () => _showAccountOptionsDialog(context),
                                );
                              },
                            );
                          },
                        );
                      } else {
                        return ListTile(
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.sync,
                                color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
                                semanticLabel: 'Sign in to Sync Data',
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Sign in to Sync Data',
                                style: TextStyle(
                                  fontSize: uiFontSize,
                                  fontFamily: uiFontFamily,
                                  color: getAdaptiveTextColor(context),
                                ),
                              ),
                            ],
                          ),
                          onTap: () => _showAuthScreen(context),
                        );
                      }
                    },
                  ),
                  ListTile(
                    title: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.save,
                          color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
                          semanticLabel: 'Export Selah Data',
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Export Data',
                          style: TextStyle(
                            fontSize: uiFontSize,
                            fontFamily: uiFontFamily,
                            color: getAdaptiveTextColor(context),
                          ),
                        ),
                      ],
                    ),
                    onTap: () => _exportData(),
                  ),
                  ListTile(
                    title: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.drive_file_move,
                          color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
                          semanticLabel: 'Import Data',
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Import Data',
                          style: TextStyle(
                            fontSize: uiFontSize,
                            fontFamily: uiFontFamily,
                            color: getAdaptiveTextColor(context),
                          ),
                        ),
                      ],
                    ),
                    onTap: () => _showImportTypeDialog(),
                  ),
                  ExpansionTile(
                    title: Text(
                      'Sync Options',
                      style: TextStyle(
                        fontSize: uiFontSize,
                        fontFamily: uiFontFamily,
                        color: getAdaptiveTextColor(context),
                      ),
                    ),
                    initiallyExpanded: false,
                    childrenPadding: EdgeInsets.all(8),
                    children: [
                      ValueListenableBuilder<bool>(
                        valueListenable: syncHighlightsNotifier,
                        builder: (context, value, child) => SwitchListTile(
                          title: Text(
                            'Highlights',
                            style: TextStyle(
                              fontSize: uiFontSize,
                              fontFamily: uiFontFamily,
                              color: getAdaptiveTextColor(context),
                            ),
                          ),
                          value: value,
                          onChanged: (val) async {
                            // Temporarily set the value to show immediate UI feedback
                            syncHighlightsNotifier.value = val;

                            _saveSyncPrefs('highlights');

                            // Update listener state
                            await SupabaseSyncService().updateListenerForCategory('highlights', val);

                            if (!val) {
                              // Disabling sync - only show confirmation dialog if user is signed in
                              if (isSignedIn.value) {
                                // Show confirmation dialog with data options
                                if (!context.mounted) return;
                                final result = await showDialog<String>(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (context) => Center(
                                    child: AlertDialog(
                                      constraints: const BoxConstraints(
                                        maxWidth: 400,
                                      ),
                                      //title: Text('Disable Sync for Highlights', style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily)),
                                      content: Text(
                                        'Choose what to do with your synced highlights. Your local highlights are not affected by this action.',
                                        style: TextStyle(
                                          fontSize: uiFontSize,
                                          fontFamily: uiFontFamily,
                                          color: getAdaptiveTextColor(context),
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          child: Text(
                                            'Cancel',
                                            style: TextStyle(
                                              fontSize: uiFontSize,
                                              fontFamily: uiFontFamily,
                                              color: getAdaptiveTextColor(
                                                context,
                                              ),
                                            ),
                                          ),
                                          onPressed: () => Navigator.pop(context, 'cancel'),
                                        ),
                                        TextButton(
                                          child: Text(
                                            'Keep Synced Data',
                                            style: TextStyle(
                                              fontSize: uiFontSize,
                                              fontFamily: uiFontFamily,
                                              color: getAdaptiveTextColor(
                                                context,
                                              ),
                                            ),
                                          ),
                                          onPressed: () => Navigator.pop(context, 'keep'),
                                        ),
                                        TextButton(
                                          child: Text(
                                            'Delete Synced Data',
                                            style: TextStyle(
                                              fontSize: uiFontSize,
                                              fontFamily: uiFontFamily,
                                              color: Colors.red,
                                            ),
                                          ),
                                          onPressed: () => Navigator.pop(context, 'delete'),
                                        ),
                                      ],
                                    ),
                                  ),
                                );

                                if (result == 'cancel') {
                                  // Cancelled - revert the toggle back to ON
                                  syncHighlightsNotifier.value = true;
                                  _saveSyncPrefs('highlights');
                                  return;
                                } else if (result == 'delete') {
                                  // Delete remote data
                                  await SupabaseSyncService().deleteAllRemoteHighlights();
                                } else if (result == 'keep') {
                                  // Keep remote data - do nothing, sync already disabled
                                }
                              }
                              // If not signed in, just leave sync disabled without dialog
                            } else {
                              // Enabling sync - upload existing local data
                              await SupabaseSyncService().syncHighlights();
                            }
                          },
                        ),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: syncNotesNotifier,
                        builder: (context, value, child) => SwitchListTile(
                          title: Text(
                            'Notes',
                            style: TextStyle(
                              fontSize: uiFontSize,
                              fontFamily: uiFontFamily,
                              color: getAdaptiveTextColor(context),
                            ),
                          ),
                          value: value,
                          onChanged: (val) async {
                            // Temporarily set the value to show immediate UI feedback
                            syncNotesNotifier.value = val;

                            _saveSyncPrefs('notes');

                            // Update listener state
                            await SupabaseSyncService().updateListenerForCategory('notes', val);

                            if (!val) {
                              // Disabling sync - only show confirmation dialog if user is signed in
                              if (isSignedIn.value) {
                                // Show confirmation dialog with data options
                                if (!context.mounted) return;
                                final result = await showDialog<String>(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (context) => Center(
                                    child: AlertDialog(
                                      constraints: const BoxConstraints(
                                        maxWidth: 400,
                                      ),
                                      //title: Text('Disable Sync for Notes', style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily)),
                                      content: Text(
                                        'Choose what to do with your synced notes. Your local notes are not affected by this action.',
                                        style: TextStyle(
                                          fontSize: uiFontSize,
                                          fontFamily: uiFontFamily,
                                          color: getAdaptiveTextColor(context),
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          child: Text(
                                            'Cancel',
                                            style: TextStyle(
                                              fontSize: uiFontSize,
                                              fontFamily: uiFontFamily,
                                              color: getAdaptiveTextColor(
                                                context,
                                              ),
                                            ),
                                          ),
                                          onPressed: () => Navigator.pop(context, 'cancel'),
                                        ),
                                        TextButton(
                                          child: Text(
                                            'Keep Synced Data',
                                            style: TextStyle(
                                              fontSize: uiFontSize,
                                              fontFamily: uiFontFamily,
                                              color: getAdaptiveTextColor(
                                                context,
                                              ),
                                            ),
                                          ),
                                          onPressed: () => Navigator.pop(context, 'keep'),
                                        ),
                                        TextButton(
                                          child: Text(
                                            'Delete Synced Data',
                                            style: TextStyle(
                                              fontSize: uiFontSize,
                                              fontFamily: uiFontFamily,
                                              color: Colors.red,
                                            ),
                                          ),
                                          onPressed: () => Navigator.pop(context, 'delete'),
                                        ),
                                      ],
                                    ),
                                  ),
                                );

                                if (result == 'cancel') {
                                  // Cancelled - revert the toggle back to ON
                                  syncNotesNotifier.value = true;
                                  _saveSyncPrefs('notes');
                                  return;
                                } else if (result == 'delete') {
                                  // Delete remote data
                                  await SupabaseSyncService().deleteAllRemoteNotes();
                                } else if (result == 'keep') {
                                  // Keep remote data - do nothing, sync already disabled
                                }
                              }
                              // If not signed in, just leave sync disabled without dialog
                            } else {
                              // Enabling sync - upload existing local data
                              await SupabaseSyncService().syncNotes();
                            }
                          },
                        ),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: syncHistoryNotifier,
                        builder: (context, value, child) => SwitchListTile(
                          title: Text(
                            'History',
                            style: TextStyle(
                              fontSize: uiFontSize,
                              fontFamily: uiFontFamily,
                              color: getAdaptiveTextColor(context),
                            ),
                          ),
                          value: value,
                          onChanged: (val) async {
                            // Temporarily set the value to show immediate UI feedback
                            syncHistoryNotifier.value = val;

                            _saveSyncPrefs('history');

                            // Update listener state
                            await SupabaseSyncService().updateListenerForCategory('history', val);

                            if (!val) {
                              // Disabling sync - only show confirmation dialog if user is signed in
                              if (isSignedIn.value) {
                                // Show confirmation dialog with data options
                                if (!context.mounted) return;
                                final result = await showDialog<String>(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (context) => Center(
                                    child: AlertDialog(
                                      constraints: const BoxConstraints(
                                        maxWidth: 400,
                                      ),
                                      //title: Text('Disable Sync for History', style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily)),
                                      content: Text(
                                        'Choose what to do with your synced history. Your local history are not affected by this action.',
                                        style: TextStyle(
                                          fontSize: uiFontSize,
                                          fontFamily: uiFontFamily,
                                          color: getAdaptiveTextColor(context),
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          child: Text(
                                            'Cancel',
                                            style: TextStyle(
                                              fontSize: uiFontSize,
                                              fontFamily: uiFontFamily,
                                              color: getAdaptiveTextColor(
                                                context,
                                              ),
                                            ),
                                          ),
                                          onPressed: () => Navigator.pop(context, 'cancel'),
                                        ),
                                        TextButton(
                                          child: Text(
                                            'Keep Synced Data',
                                            style: TextStyle(
                                              fontSize: uiFontSize,
                                              fontFamily: uiFontFamily,
                                              color: getAdaptiveTextColor(
                                                context,
                                              ),
                                            ),
                                          ),
                                          onPressed: () => Navigator.pop(context, 'keep'),
                                        ),
                                        TextButton(
                                          child: Text(
                                            'Delete Synced Data',
                                            style: TextStyle(
                                              fontSize: uiFontSize,
                                              fontFamily: uiFontFamily,
                                              color: Colors.red,
                                            ),
                                          ),
                                          onPressed: () => Navigator.pop(context, 'delete'),
                                        ),
                                      ],
                                    ),
                                  ),
                                );

                                if (result == 'cancel') {
                                  // Cancelled - revert the toggle back to ON
                                  syncHistoryNotifier.value = true;

                                  _saveSyncPrefs('history');

                                  return;
                                } else if (result == 'delete') {
                                  // Delete remote data
                                  await SupabaseSyncService().deleteAllRemoteHistory();
                                } else if (result == 'keep') {
                                  // Keep remote data - do nothing, sync already disabled
                                }
                              }
                              // If not signed in, just leave sync disabled without dialog
                            } else {
                              // Enabling sync - upload existing local data
                              await SupabaseSyncService().syncHistory();
                            }
                          },
                        ),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: syncSearchHistoryNotifier,
                        builder: (context, value, child) => SwitchListTile(
                          title: Text(
                            'Search History',
                            style: TextStyle(
                              fontSize: uiFontSize,
                              fontFamily: uiFontFamily,
                              color: getAdaptiveTextColor(context),
                            ),
                          ),
                          value: value,
                          onChanged: (val) async {
                            // Temporarily set the value to show immediate UI feedback
                            syncSearchHistoryNotifier.value = val;

                            _saveSyncPrefs('search_history');

                            // Update listener state
                            await SupabaseSyncService().updateListenerForCategory(
                              'searchHistory',
                              val,
                            );

                            if (!val) {
                              // Disabling sync - only show confirmation dialog if user is signed in
                              if (isSignedIn.value) {
                                // Show confirmation dialog with data options
                                if (!context.mounted) return;
                                final result = await showDialog<String>(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (context) => Center(
                                    child: AlertDialog(
                                      constraints: const BoxConstraints(
                                        maxWidth: 400,
                                      ),
                                      //title: Text('Disable Sync for Search History', style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily)),
                                      content: Text(
                                        'Choose what to do with your synced search history. Your local search history is not affected by this action.',
                                        style: TextStyle(
                                          fontSize: uiFontSize,
                                          fontFamily: uiFontFamily,
                                          color: getAdaptiveTextColor(context),
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          child: Text(
                                            'Cancel',
                                            style: TextStyle(
                                              fontSize: uiFontSize,
                                              fontFamily: uiFontFamily,
                                              color: getAdaptiveTextColor(
                                                context,
                                              ),
                                            ),
                                          ),
                                          onPressed: () => Navigator.pop(context, 'cancel'),
                                        ),
                                        TextButton(
                                          child: Text(
                                            'Keep Synced Data',
                                            style: TextStyle(
                                              fontSize: uiFontSize,
                                              fontFamily: uiFontFamily,
                                              color: getAdaptiveTextColor(
                                                context,
                                              ),
                                            ),
                                          ),
                                          onPressed: () => Navigator.pop(context, 'keep'),
                                        ),
                                        TextButton(
                                          child: Text(
                                            'Delete Synced Data',
                                            style: TextStyle(
                                              fontSize: uiFontSize,
                                              fontFamily: uiFontFamily,
                                              color: Colors.red,
                                            ),
                                          ),
                                          onPressed: () => Navigator.pop(context, 'delete'),
                                        ),
                                      ],
                                    ),
                                  ),
                                );

                                if (result == 'cancel') {
                                  // Cancelled - revert the toggle back to ON
                                  syncSearchHistoryNotifier.value = true;
                                  _saveSyncPrefs('search_history');
                                  return;
                                } else if (result == 'delete') {
                                  // Delete remote data
                                  await SupabaseSyncService().deleteAllRemoteSearchHistory();
                                } else if (result == 'keep') {
                                  // Keep remote data - do nothing, sync already disabled
                                }
                              }
                              // If not signed in, just leave sync disabled without dialog
                            } else {
                              // Enabling sync - upload existing local data
                              await SupabaseSyncService().syncSearchHistory();
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  ExpansionTile(
                    title: Text(
                      'Advanced',
                      style: TextStyle(
                        fontSize: uiFontSize,
                        fontFamily: uiFontFamily,
                        color: getAdaptiveTextColor(context),
                      ),
                    ),
                    initiallyExpanded: false,
                    childrenPadding: EdgeInsets.all(8),
                    children: [
                      SizedBox(
                        height: 50,
                        child: ListTile(
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.sync,
                                color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
                                semanticLabel: 'Advanced - Execute Manual Sync',
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Manual Sync',
                                style: TextStyle(
                                  fontSize: uiFontSize - 2,
                                  fontFamily: uiFontFamily,
                                  color: getAdaptiveTextColor(context),
                                ),
                              ),
                            ],
                          ),
                          onTap: () async {
                            if (!isSignedIn.value) {
                              showStyledSnackBar(
                                context,
                                'You must be signed in to perform a sync',
                                isError: true,
                              );
                              return;
                            }
                            if (!(await InternetAccessChecker.hasInternetAccess())) {
                              if (context.mounted) {
                                showStyledSnackBar(
                                  context,
                                  'No internet connection available',
                                  isError: true,
                                );
                              }
                              return;
                            }

                            // Show progress dialog
                            if (context.mounted) {
                              showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (context) => const SyncDialog(),
                              );
                            }

                            try {
                              // Perform sync operation
                              await SupabaseSyncService().triggerManualSync();

                              if (context.mounted) {
                                Navigator.pop(context); // Close progress dialog
                                showStyledSnackBar(
                                  context,
                                  'Sync completed successfully',
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                showStyledSnackBar(
                                  context,
                                  'Sync failed: ${e.toString()}',
                                  isError: true,
                                );
                              }
                            }
                          },
                        ),
                      ),
                      SizedBox(
                        height: 50,
                        child: ListTile(
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.edit,
                                color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
                                semanticLabel: 'Advanced - Edit Saved Shared Preferences',
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Edit Preferences',
                                style: TextStyle(
                                  fontSize: uiFontSize - 2,
                                  fontFamily: uiFontFamily,
                                  color: getAdaptiveTextColor(context),
                                ),
                              ),
                            ],
                          ),
                          onTap: () async {
                            await _showEditPreferencesDialog(context);
                          },
                        ),
                      ),
                      //SizedBox(height: 8),
                      SizedBox(
                        height: 50,
                        child: ListTile(
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.settings_backup_restore,
                                color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
                                semanticLabel:
                                    'Advanced - Reset Preferences and exit. A Restart is required for the changes to take effect.',
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Reset Preferences',
                                style: TextStyle(
                                  fontSize: uiFontSize - 2,
                                  fontFamily: uiFontFamily,
                                  color: getAdaptiveTextColor(context),
                                ),
                              ),
                            ],
                          ),
                          onTap: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                constraints: const BoxConstraints(
                                  maxWidth: 400,
                                ),
                                title: Text(
                                  'Warning',
                                  style: TextStyle(
                                    fontSize: uiFontSize,
                                    fontFamily: uiFontFamily,
                                    color: Colors.red,
                                  ),
                                ),
                                content: Text(
                                  'This will reset all of the saved preferences to the defaults. The app will then exit because a restart is required for the changes to take effect. Are you sure?',
                                  style: TextStyle(
                                    fontSize: uiFontSize,
                                    fontFamily: uiFontFamily,
                                    color: getAdaptiveTextColor(context),
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    child: Text(
                                      'No',
                                      style: TextStyle(
                                        fontSize: uiFontSize,
                                        fontFamily: uiFontFamily,
                                        color: getAdaptiveTextColor(context),
                                      ),
                                    ),
                                    onPressed: () => Navigator.pop(context, false),
                                  ),
                                  TextButton(
                                    child: Text(
                                      'Yes',
                                      style: TextStyle(
                                        fontSize: uiFontSize,
                                        fontFamily: uiFontFamily,
                                        color: Colors.red,
                                      ),
                                    ),
                                    onPressed: () => Navigator.pop(context, true),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await _resetPreferencesAndExit();
                            }
                          },
                        ),
                      ),
                      //SizedBox(height: 8),
                      SizedBox(
                        height: 50,
                        child: ListTile(
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.highlight_off,
                                color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
                                semanticLabel: 'Advanced - Reset Highlights',
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Reset Highlights',
                                style: TextStyle(
                                  fontSize: uiFontSize - 2,
                                  fontFamily: uiFontFamily,
                                  color: getAdaptiveTextColor(context),
                                ),
                              ),
                            ],
                          ),
                          onTap: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                constraints: const BoxConstraints(
                                  maxWidth: 400,
                                ),
                                title: Text(
                                  'Warning',
                                  style: TextStyle(
                                    fontSize: uiFontSize,
                                    fontFamily: uiFontFamily,
                                    color: Colors.red,
                                  ),
                                ),
                                content: Text(
                                  'This action cannot be undone! If you are logged in then your remote data will also be removed during sync (which is automatic and occurs immediately when you are online).\n\nYou can use the "Export Data" option to backup your data locally.\n\nAre you sure you want to clear all highlights?',
                                  style: TextStyle(
                                    fontSize: uiFontSize,
                                    fontFamily: uiFontFamily,
                                    color: getAdaptiveTextColor(context),
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    child: Text(
                                      'No',
                                      style: TextStyle(
                                        fontSize: uiFontSize,
                                        fontFamily: uiFontFamily,
                                        color: getAdaptiveTextColor(context),
                                      ),
                                    ),
                                    onPressed: () => Navigator.pop(context, false),
                                  ),
                                  TextButton(
                                    child: Text(
                                      'Yes',
                                      style: TextStyle(
                                        fontSize: uiFontSize,
                                        fontFamily: uiFontFamily,
                                        color: Colors.red,
                                      ),
                                    ),
                                    onPressed: () => Navigator.pop(context, true),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              final syncService = SupabaseSyncService();

                              // Delete remote data first if logged in
                              if (Supabase.instance.client.auth.currentUser != null) {
                                await syncService.deleteAllRemoteHighlights();
                              }

                              final dbHighlights = await HighlightsDatabase.getDatabase();
                              await dbHighlights.delete('user_highlights');

                              // Update the ui
                              LocalDataChangeNotifier.notifyHighlightsChanged();
                            }
                          },
                        ),
                      ),
                      SizedBox(
                        height: 50,
                        child: ListTile(
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.note_alt,
                                color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
                                semanticLabel: 'Advanced - Reset Notes',
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Reset Notes',
                                style: TextStyle(
                                  fontSize: uiFontSize - 2,
                                  fontFamily: uiFontFamily,
                                  color: getAdaptiveTextColor(context),
                                ),
                              ),
                            ],
                          ),
                          onTap: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                constraints: const BoxConstraints(
                                  maxWidth: 400,
                                ),
                                title: Text(
                                  'Warning',
                                  style: TextStyle(
                                    fontSize: uiFontSize,
                                    fontFamily: uiFontFamily,
                                    color: Colors.red,
                                  ),
                                ),
                                content: Text(
                                  'This action cannot be undone! If you are logged in then your remote data will also be removed during sync (which is automatic and occurs immediately when you are online).\n\nYou can use the "Export Data" option to backup your data locally.\n\nAre you sure you want to clear all notes?',
                                  style: TextStyle(
                                    fontSize: uiFontSize,
                                    fontFamily: uiFontFamily,
                                    color: getAdaptiveTextColor(context),
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    child: Text(
                                      'No',
                                      style: TextStyle(
                                        fontSize: uiFontSize,
                                        fontFamily: uiFontFamily,
                                        color: getAdaptiveTextColor(context),
                                      ),
                                    ),
                                    onPressed: () => Navigator.pop(context, false),
                                  ),
                                  TextButton(
                                    child: Text(
                                      'Yes',
                                      style: TextStyle(
                                        fontSize: uiFontSize,
                                        fontFamily: uiFontFamily,
                                        color: Colors.red,
                                      ),
                                    ),
                                    onPressed: () => Navigator.pop(context, true),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              final syncService = SupabaseSyncService();

                              // Delete remote data first if logged in
                              if (Supabase.instance.client.auth.currentUser != null) {
                                await syncService.deleteAllRemoteNotes();
                              }

                              final db = await NotesDatabase.getDatabase();
                              await db.delete('user_notes');

                              // Notify UI
                              LocalDataChangeNotifier.notifyNotesChanged();
                            }
                          },
                        ),
                      ),
                      SizedBox(
                        height: 50,
                        child: ListTile(
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.history,
                                color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
                                semanticLabel: 'Advanced - Reset Verse Reference History',
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Reset Verse History',
                                style: TextStyle(
                                  fontSize: uiFontSize - 2,
                                  fontFamily: uiFontFamily,
                                  color: getAdaptiveTextColor(context),
                                ),
                              ),
                            ],
                          ),
                          onTap: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                constraints: const BoxConstraints(
                                  maxWidth: 400,
                                ),
                                title: Text(
                                  'Warning',
                                  style: TextStyle(
                                    fontSize: uiFontSize,
                                    fontFamily: uiFontFamily,
                                    color: Colors.red,
                                  ),
                                ),
                                content: Text(
                                  'This action cannot be undone! If you are logged in then your remote data will also be removed during sync (which is automatic and occurs immediately when you are online).\n\nYou can use the "Export Data" option to backup your data locally.\n\nAre you sure you want to clear all history?',
                                  style: TextStyle(
                                    fontSize: uiFontSize,
                                    fontFamily: uiFontFamily,
                                    color: getAdaptiveTextColor(context),
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    child: Text(
                                      'No',
                                      style: TextStyle(
                                        fontSize: uiFontSize,
                                        fontFamily: uiFontFamily,
                                        color: getAdaptiveTextColor(context),
                                      ),
                                    ),
                                    onPressed: () => Navigator.pop(context, false),
                                  ),
                                  TextButton(
                                    child: Text(
                                      'Yes',
                                      style: TextStyle(
                                        fontSize: uiFontSize,
                                        fontFamily: uiFontFamily,
                                        color: Colors.red,
                                      ),
                                    ),
                                    onPressed: () => Navigator.pop(context, true),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              final syncService = SupabaseSyncService();

                              // Delete remote data first if logged in
                              if (Supabase.instance.client.auth.currentUser != null) {
                                await syncService.deleteAllRemoteHistory();
                              }

                              final db = await HistoryDatabase.getDatabase();
                              await db.delete('history');
                            }
                          },
                        ),
                      ),
                      SizedBox(
                        height: 50,
                        child: ListTile(
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.history,
                                color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
                                semanticLabel: 'Advanced - Reset Saved Searches',
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Reset Saved Searches',
                                style: TextStyle(
                                  fontSize: uiFontSize - 2,
                                  fontFamily: uiFontFamily,
                                  color: getAdaptiveTextColor(context),
                                ),
                              ),
                            ],
                          ),
                          onTap: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                constraints: const BoxConstraints(
                                  maxWidth: 400,
                                ),
                                title: Text(
                                  'Warning',
                                  style: TextStyle(
                                    fontSize: uiFontSize,
                                    fontFamily: uiFontFamily,
                                    color: Colors.red,
                                  ),
                                ),
                                content: Text(
                                  'This action cannot be undone! If you are logged in then your remote data will also be removed during sync (which is automatic and occurs immediately when you are online).\n\nYou can use the "Export Data" option to backup your data locally.\n\nAre you sure you want to clear all saved searches?',
                                  style: TextStyle(
                                    fontSize: uiFontSize,
                                    fontFamily: uiFontFamily,
                                    color: getAdaptiveTextColor(context),
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    child: Text(
                                      'No',
                                      style: TextStyle(
                                        fontSize: uiFontSize,
                                        fontFamily: uiFontFamily,
                                        color: getAdaptiveTextColor(context),
                                      ),
                                    ),
                                    onPressed: () => Navigator.pop(context, false),
                                  ),
                                  TextButton(
                                    child: Text(
                                      'Yes',
                                      style: TextStyle(
                                        fontSize: uiFontSize,
                                        fontFamily: uiFontFamily,
                                        color: Colors.red,
                                      ),
                                    ),
                                    onPressed: () => Navigator.pop(context, true),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              final syncService = SupabaseSyncService();

                              // Delete remote data first if logged in
                              if (Supabase.instance.client.auth.currentUser != null) {
                                await syncService.deleteAllRemoteSearchHistory();
                              }

                              final db = await SearchDatabase.getDatabase();
                              await db.delete('search_history');
                            }
                          },
                        ),
                      ),
                      SizedBox(
                        height: 50,
                        child: ListTile(
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.restore_from_trash,
                                color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
                                semanticLabel:
                                    'Advanced - Reset Preferences, Highlights, History, Notes, and exit. A restart is required for the changes to take effect.',
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Reset Everything',
                                style: TextStyle(
                                  fontSize: uiFontSize - 2,
                                  fontFamily: uiFontFamily,
                                  color: getAdaptiveTextColor(context),
                                ),
                              ),
                            ],
                          ),
                          onTap: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                constraints: const BoxConstraints(
                                  maxWidth: 400,
                                ),
                                title: Text(
                                  'Warning',
                                  style: TextStyle(
                                    fontSize: uiFontSize,
                                    fontFamily: uiFontFamily,
                                    color: Colors.red,
                                  ),
                                ),
                                content: Text(
                                  'This will reset all preferences, highlights, history, notes, and search history. This action cannot be undone. The app will then exit because a restart is required for all of the changes to take effect. Are you sure?',
                                  style: TextStyle(
                                    fontSize: uiFontSize,
                                    fontFamily: uiFontFamily,
                                    color: getAdaptiveTextColor(context),
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    child: Text(
                                      'No',
                                      style: TextStyle(
                                        fontSize: uiFontSize,
                                        fontFamily: uiFontFamily,
                                        color: getAdaptiveTextColor(context),
                                      ),
                                    ),
                                    onPressed: () => Navigator.pop(context, false),
                                  ),
                                  TextButton(
                                    child: Text(
                                      'Yes',
                                      style: TextStyle(
                                        fontSize: uiFontSize,
                                        fontFamily: uiFontFamily,
                                        color: Colors.red,
                                      ),
                                    ),
                                    onPressed: () => Navigator.pop(context, true),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await _resetEverythingAndExit();
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
      body: SafeArea(
        //Row(
        //mainAxisSize: MainAxisSize.min,
        //children: [
        //Expanded(
        //child:
        child: ValueListenableBuilder<bool>(
          valueListenable: isVerticalTile,
          builder: (context, vertical, _) {
            if (vertical) {
              return Row(
                // Main Bible screen row
                //mainAxisSize: MainAxisSize.min,
                children: List.generate(_screenLocations.length, (i) {
                  return Expanded(
                    child: BibleScreen(
                      initialBook: _screenLocations[i]['book'],
                      initialChapter: _screenLocations[i]['chapter'],
                      initialVerse: _screenLocations[i]['verse'],
                      onLocationChanged: (book, chapter, verse) => _updateLocation(i, book, chapter, verse),
                      onOpenDrawer: () => Scaffold.of(context).openDrawer(),
                      onShowHistory: () => _showHistoryDialog(context, i),
                      onShowSearch: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => SearchScreen(
                              sourceScreenIndex: i, // Pass the current screen index
                            ),
                            settings: RouteSettings(name: '/search'),
                          ),
                        ).then((searchResult) {
                          // Handle returned verse location from search screen
                          if (searchResult != null && searchResult is Map<String, dynamic>) {
                            final verseLocation = searchResult['verseLocation'] as Map<String, dynamic>?;
                            final targetScreenIndex = searchResult['targetScreenIndex'] as int?;

                            if (verseLocation != null && targetScreenIndex != null) {
                              final book = verseLocation['book'] as String?;
                              final chapter = verseLocation['chapter'] as int?;
                              final verse = verseLocation['verse'] as int?;

                              if (book != null && chapter != null && verse != null) {
                                // Update the target bible screen with the verse location
                                setState(() {
                                  _updateLocation(
                                    targetScreenIndex,
                                    book,
                                    chapter,
                                    verse,
                                  );
                                });
                              }
                            }
                          }
                        });
                      },
                      // Show options on the first screen explicitly
                      showViewMenu: i == 0,
                      // Add: pass notes inline mode
                      showNotesInline: showNotesInlineNotifier,
                    ),
                  );
                }),
              );
            } else {
              return Column(
                mainAxisSize: MainAxisSize.max,
                children: List.generate(_screenLocations.length, (i) {
                  return Expanded(
                    child: BibleScreen(
                      initialBook: _screenLocations[i]['book'],
                      initialChapter: _screenLocations[i]['chapter'],
                      initialVerse: _screenLocations[i]['verse'],
                      onLocationChanged: (book, chapter, verse) => _updateLocation(i, book, chapter, verse),
                      onOpenDrawer: () => Scaffold.of(context).openDrawer(),
                      onShowHistory: () => _showHistoryDialog(context, i),
                      onShowSearch: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => SearchScreen(
                              sourceScreenIndex: i, // Pass the current screen index
                            ),
                            settings: RouteSettings(name: '/search'),
                          ),
                        ).then((searchResult) {
                          // Handle returned verse location from search screen
                          if (searchResult != null && searchResult is Map<String, dynamic>) {
                            final verseLocation = searchResult['verseLocation'] as Map<String, dynamic>?;
                            final targetScreenIndex = searchResult['targetScreenIndex'] as int?;

                            if (verseLocation != null && targetScreenIndex != null) {
                              final book = verseLocation['book'] as String?;
                              final chapter = verseLocation['chapter'] as int?;
                              final verse = verseLocation['verse'] as int?;

                              if (book != null && chapter != null && verse != null) {
                                // Update the target bible screen with the verse location
                                setState(() {
                                  _updateLocation(
                                    targetScreenIndex,
                                    book,
                                    chapter,
                                    verse,
                                  );
                                });
                              }
                            }
                          }
                        });
                      },
                      // Show options menu on the first screen only
                      showViewMenu: i == 0,
                      // Add: pass notes inline mode
                      showNotesInline: showNotesInlineNotifier,
                    ),
                  );
                }),
              );
            }
          },
        ),
      ),
      //],
      //),
    );
  }

  Future<void> _clearPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  Future<void> _resetPreferencesAndExit() async {
    await _clearPreferences();
    // Exit the app immediately
    if (Platform.isAndroid || Platform.isIOS) {
      SystemNavigator.pop();
    } else {
      exit(0);
    }
  }

  Future<void> _resetEverythingAndExit() async {
    try {
      final syncService = SupabaseSyncService();

      // Delete remote data first if logged in
      if (Supabase.instance.client.auth.currentUser != null) {
        await syncService.deleteAllRemoteHighlights();
        await syncService.deleteAllRemoteNotes();
        await syncService.deleteAllRemoteHistory();
        await syncService.deleteAllRemoteSearchHistory();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('_resetEverythingAndExit Firestore/sync exception: ${e.toString()}');
      }
    }

    try {
      await _clearPreferences();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('_resetEverythingAndExit _clearPreferences exception: ${e.toString()}');
      }
    }

    try {
      final dbHighlights = await HighlightsDatabase.getDatabase();
      await dbHighlights.delete('user_highlights');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('_resetEverythingAndExit dbHighlights exception: ${e.toString()}');
      }
    }

    try {
      final dbHistory = await HistoryDatabase.getDatabase();
      await dbHistory.delete('history');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('_resetEverythingAndExit dbHistory exception: ${e.toString()}');
      }
    }

    try {
      final dbNotes = await NotesDatabase.getDatabase();
      await dbNotes.delete('user_notes');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('_resetEverythingAndExit dbNotes exception: ${e.toString()}');
      }
    }

    try {
      final dbSearchHistory = await SearchDatabase.getDatabase();
      await dbSearchHistory.delete('search_history');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('_resetEverythingAndExit dbSearchHistory exception: ${e.toString()}');
      }
    }

    // Exit the app immediately (no need for UI refresh since app exits)
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      SystemNavigator.pop();
    } else {
      exit(0);
    }
  }

  Future<void> _showEditPreferencesDialog(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    // Guard: avoid using the provided BuildContext after async gap
    if (!context.mounted) return;
    final Map<String, Object> allPrefs = {};
    final keys = prefs.getKeys();
    for (final k in keys) {
      allPrefs[k] = prefs.get(k) ?? '';
    }
    final controller = TextEditingController(
      text: JsonEncoder.withIndent('  ').convert(allPrefs),
    );

    final result = await showDialog<bool>(
      context: context,
      useSafeArea: true,
      builder: (context) {
        return AlertDialog(
          //title: Text('WARNING: edit with caution!', style: TextStyle(fontFamily: uiFontFamily, fontSize: uiFontSize, color: Colors.red)),
          content: SizedBox(
            width: 600,
            child: //OnscreenKeyboardTextField(
                TextField(
              controller: controller,
              maxLines: 30,
              minLines: 10,
              decoration: InputDecoration(border: OutlineInputBorder()),
              // use selected font and selected font size
              style: TextStyle(
                fontFamily: uiFontFamily,
                fontSize: uiFontSize + 2,
              ),
            ),
          ),
          actions: [
            TextButton(
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontSize: uiFontSize,
                  fontFamily: uiFontFamily,
                  color: getAdaptiveTextColor(context),
                ),
              ),
              onPressed: () => Navigator.pop(context, false),
            ),
            TextButton(
              child: Text(
                'Save',
                style: TextStyle(
                  fontSize: uiFontSize,
                  fontFamily: uiFontFamily,
                  color: getAdaptiveTextColor(context),
                ),
              ),
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        );
      },
    );

    if (result == true) {
      try {
        final Map<String, dynamic> newPrefs = jsonDecode(controller.text) as Map<String, dynamic>;
        await prefs.clear();
        for (final entry in newPrefs.entries) {
          final k = entry.key;
          final v = entry.value;
          if (v is int) {
            await prefs.setInt(k, v);
          } else if (v is double) {
            await prefs.setDouble(k, v);
          } else if (v is bool) {
            await prefs.setBool(k, v);
          } else if (v is String) {
            await prefs.setString(k, v);
          } else if (v is List) {
            // handle List<String>
            if (v.every((e) => e is String)) {
              await prefs.setStringList(k, List<String>.from(v));
            }
          }
        }
        // Reload max screens after saving (platform-specific defaults)
        final bool isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
        maxVerticalScreens.value = prefs.getInt('maxVerticalScreens') ?? (isMobile ? 1 : 4);
        maxHorizontalScreens.value = prefs.getInt('maxHorizontalScreens') ?? (isMobile ? 3 : 4);
      } catch (e) {
        // Guard: use context.mounted for the provided BuildContext
        if (!context.mounted) return;
        showStyledSnackBar(
          context,
          'Error saving preferences: ${e.toString()}',
          isError: true,
        );
      }
    }

    // THIS IS THE KEY ADDITION: Force focus away from the TextField after dialog closes
    // This executes no matter how the dialog was closed (Cancel, Save, or other means)
    // This is to circumvent a bug on windows desktop touchscreens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _invisibleElevatedButtonNode.canRequestFocus) {
        if (kDebugMode) debugPrint('Changing focus to fix bug');
        _invisibleElevatedButtonNode.requestFocus();
      } else {
        if (kDebugMode) {
          debugPrint(
              'Changing focus failed:\nmounted: $mounted\ncanRequestFocus: ${_invisibleElevatedButtonNode.canRequestFocus}');
        }
      }
    });
  }

  Future<bool> _requestStoragePermission() async {
    if (Platform.isAndroid || Platform.isIOS) {
      PermissionStatus status = await Permission.storage.request();
      return status.isGranted;
    }
    return true; // For desktop, no need
  }

  // Show export selection dialog
  Future<Set<String>?> _showExportSelectionDialog(BuildContext context) async {
    final availableTypes = ['highlights', 'notes', 'history', 'searchHistory'];
    final selectedTypes = Set<String>.from(
      availableTypes,
    ); // Default all selected

    return await showDialog<Set<String>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              constraints: const BoxConstraints(maxWidth: 400),
              //title: Text('Select Data to Export', style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily, color: getAdaptiveTextColor(context))),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose which data types to include in the export:',
                    style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...availableTypes.map((type) {
                    return CheckboxListTile(
                      title: Text(
                        _getDataTypeDisplayName(type),
                        style: TextStyle(
                          fontSize: uiFontSize,
                          fontFamily: uiFontFamily,
                          color: getAdaptiveTextColor(context),
                        ),
                      ),
                      value: selectedTypes.contains(type),
                      onChanged: (selected) {
                        setState(() {
                          if (selected == true) {
                            selectedTypes.add(type);
                          } else {
                            selectedTypes.remove(type);
                          }
                        });
                      },
                    );
                  }),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, selectedTypes),
                  child: Text(
                    'Export Selected',
                    style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Get display name for a data type
  String _getDataTypeDisplayName(String type) {
    switch (type) {
      case 'highlights':
        return 'Highlights';
      case 'notes':
        return 'Notes';
      case 'history':
        return 'History';
      case 'searchHistory':
        return 'Search History';
      default:
        return type;
    }
  }

  Future<void> _exportData() async {
    Set<String>? selectedTypes;
    Map<String, dynamic>? exportData;

    // --- 1. Show Export Selection Dialog ---
    try {
      selectedTypes = await _showExportSelectionDialog(context);
      if (selectedTypes == null || selectedTypes.isEmpty) return;
    } catch (e) {
      return;
    }

    if (!mounted) return;

    // --- 2. Request storage permission BEFORE showing progress dialog ---
    // This prevents permission issues during data collection on iOS
    bool hasPermission = await _requestStoragePermission();
    if (!hasPermission) {
      if (mounted) {
        showStyledSnackBar(
          context,
          'Storage permission is required for export',
          isError: true,
        );
      }
      return;
    }

    // --- 3. Show Progress Dialog (Non-Blocking) ---
    // The showDialog returns a Future that completes when the dialog is dismissed.
    // We do NOT await it here. This allows the code to continue execution
    // and start the long process immediately after the dialog is requested to show.
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Collecting your data...',
                style: TextStyle(
                  fontSize: uiFontSize,
                  fontFamily: uiFontFamily,
                  color: getAdaptiveTextColor(context),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // --- 4. Execute Long Process Immediately After Dialog is Queued ---
    // This Future ensures the code is executed outside of the immediate build cycle,
    // allowing the dialog to actually render before the long synchronous task blocks the UI.
    // We use .then() to handle the result and ensure the dialog is closed.
    await Future.value().then((_) async {
      try {
        // A. Collect selected data (Long synchronous task)
        // This is still the core blocking operation.
        exportData = await Future.delayed(Duration.zero, () {
          return _collectAllData(selectedTypes!);
        });

        // B. Let user choose export location
        final timestamp = DateTime.now().toString().replaceAll(RegExp(r'[:.]'), '-').substring(0, 19);
        final fileName = 'Selah_$timestamp.zip';

        // This is an awaitable user interaction that keeps the dialog on screen
        String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Choose Export Location',
        );

        if (selectedDirectory == null) {
          if (mounted) {
            showStyledSnackBar(
              context,
              'Invalid Path Selected!',
              isError: true,
            );
          }
          return;
        }

        if (exportData == null) {
          if (mounted) {
            showStyledSnackBar(context, 'exportData is Null!', isError: true);
          }
          return;
        }

        // C. Create and Write zip file
        final zipFile = File(path.join(selectedDirectory, fileName));
        final encoder = ZipEncoder();
        final archive = Archive();
        final jsonBytes = utf8.encode(jsonEncode(exportData));

        archive.addFile(
          ArchiveFile('selah_data.json', jsonBytes.length, jsonBytes),
        );
        final zipBytes = encoder.encode(archive);
        await zipFile.writeAsBytes(zipBytes);

        // D. Show success message
        if (mounted) {
          showStyledSnackBar(context, '✅ Data exported to $fileName');
        }
      } catch (e) {
        // E. Handle errors during data collection or saving
        if (mounted) {
          // Close progress dialog first to prevent stuck UI
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }

          // Show error dialog
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              constraints: const BoxConstraints(maxWidth: 400),
              title: const Text(
                'Export Failed',
                style: TextStyle(color: Colors.red),
              ),
              content: Text(
                'Failed to export data: ${e.toString()}',
                style: TextStyle(
                  fontSize: uiFontSize,
                  fontFamily: uiFontFamily,
                  color: getAdaptiveTextColor(context),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Ok',
                    style: TextStyle(
                      fontSize: uiFontSize,
                      fontFamily: uiFontFamily,
                      color: getAdaptiveTextColor(context),
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return; // Exit early to prevent finally block from running again
      } finally {
        // --- 5. Close Progress Dialog (Guaranteed to Run LAST) ---
        // This runs after the entire chain of Future.value().then() completes.
        if (mounted) {
          // We MUST pop the dialog we showed in step 3.
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        }
      }
    }); // End of Future.value().then()
  }

  Future<Map<String, dynamic>> _collectAllData(
    Set<String> selectedTypes,
  ) async {
    final data = <String, dynamic>{};

    // Collect highlights if selected
    if (selectedTypes.contains('highlights')) {
      data['highlights'] = await HighlightsDatabase.getHighlights();
    }

    // Collect notes if selected
    if (selectedTypes.contains('notes')) {
      data['notes'] = await NotesDatabase.getNotes();
    }

    // Collect history if selected
    if (selectedTypes.contains('history')) {
      data['history'] = await HistoryDatabase.getHistory();
    }

    // Collect search history if selected
    if (selectedTypes.contains('searchHistory')) {
      data['searchHistory'] = await SearchDatabase.getSearchHistory();
    }

    data['exportInfo'] = {
      'appVersion': appVersion,
      'exportDate': DateTime.now().toIso8601String(),
      'dataTypes': selectedTypes.toList(),
    };

    return data;
  }

  Future<void> _showImportTypeDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? darkBackgroundColor.value : lightBackgroundColor.value;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.0),
          side: BorderSide(
            color: isDark ? darkPrimaryColor.value : lightPrimaryColor.value,
            width: 1.0,
          ),
        ),
        backgroundColor: bgColor,
        constraints: const BoxConstraints(maxWidth: 400),
        title: Text(
          'Select Import Type',
          style: TextStyle(
            fontSize: uiFontSize,
            fontFamily: uiFontFamily,
            color: getAdaptiveTextColor(context),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                'Selah',
                style: TextStyle(
                  fontSize: uiFontSize,
                  fontFamily: uiFontFamily,
                  color: getAdaptiveTextColor(context),
                ),
              ),
              subtitle: Text(
                'Import data exported from Selah app',
                style: TextStyle(
                  fontSize: uiFontSize - 2,
                  fontFamily: uiFontFamily,
                  color: getAdaptiveTextColor(context),
                ),
              ),
              onTap: () => Navigator.pop(context, 'selah'),
            ),
            ListTile(
              title: Text(
                'Olive Tree Bible',
                style: TextStyle(
                  fontSize: uiFontSize,
                  fontFamily: uiFontFamily,
                  color: getAdaptiveTextColor(context),
                ),
              ),
              subtitle: Text(
                'Import data from Olive Tree Bible app',
                style: TextStyle(
                  fontSize: uiFontSize - 2,
                  fontFamily: uiFontFamily,
                  color: getAdaptiveTextColor(context),
                ),
              ),
              onTap: () => Navigator.pop(context, 'olive_tree_bible'),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      await _importData(result);
    }
  }

  Future<void> _importData(String importType) async {
    if (importType == 'selah') {
      await SelahImportService.importSelahData(context);
    } else if (importType == 'olive_tree_bible') {
      // Import Olive Tree data
      await OliveTreeImportService.importOliveTreeData(context);
    }
  }

  void _showAuthScreen(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AuthScreen()),
    );
  }

  void _showAccountOptionsDialog(BuildContext outerContext) async {
    await showDialog(
      context: outerContext,
      builder: (dialogContext) => AlertDialog(
        title: Center(
          child: Text(
            'Account Options',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: uiFontSize,
              fontFamily: uiFontFamily,
              color: getAdaptiveTextColor(context),
            ),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: Icon(
                Icons.lock_reset,
                color: getAdaptiveTextColor(context),
                semanticLabel: 'Change Password',
              ),
              title: Text(
                'Change Password',
                style: TextStyle(
                  fontSize: uiFontSize,
                  fontFamily: uiFontFamily,
                  color: getAdaptiveTextColor(context),
                ),
              ),
              onTap: () {
                Navigator.pop(dialogContext);
                _showChangePasswordDialog(outerContext);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_forever,
                color: Colors.red,
                semanticLabel: 'Delete Account',
              ),
              title: Text(
                'Delete Account',
                style: TextStyle(
                  fontSize: uiFontSize,
                  fontFamily: uiFontFamily,
                  color: Colors.red,
                ),
              ),
              onTap: () {
                Navigator.pop(dialogContext);
                _showDeleteAccountDialog(outerContext);
              },
            ),
            Divider(),
            ListTile(
              leading: Icon(
                Icons.logout,
                color: getAdaptiveTextColor(context),
                semanticLabel: 'Sign out',
              ),
              title: Text(
                'Sign Out',
                style: TextStyle(
                  fontSize: uiFontSize,
                  fontFamily: uiFontFamily,
                  color: getAdaptiveTextColor(context),
                ),
              ),
              onTap: () {
                Navigator.pop(dialogContext);
                _showSignOutDialog(outerContext);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            child: Text(
              'Cancel',
              style: TextStyle(
                fontSize: uiFontSize,
                fontFamily: uiFontFamily,
                color: getAdaptiveTextColor(context),
              ),
            ),
            onPressed: () => Navigator.pop(dialogContext),
          ),
        ],
      ),
    );
  }

  void _showSignOutDialog(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 400),
        title: Text(
          'Sign Out',
          style: TextStyle(
            fontSize: uiFontSize,
            fontFamily: uiFontFamily,
            color: getAdaptiveTextColor(context),
          ),
        ),
        content: Text(
          'Do you want to keep your local data or erase them (notes, highlights, and history)?',
          style: TextStyle(
            fontSize: uiFontSize,
            fontFamily: uiFontFamily,
            color: getAdaptiveTextColor(context),
          ),
        ),
        actions: [
          TextButton(
            child: Text(
              'Keep Data',
              style: TextStyle(
                fontSize: uiFontSize,
                fontFamily: uiFontFamily,
                color: getAdaptiveTextColor(context),
              ),
            ),
            onPressed: () => Navigator.pop(context, false),
          ),
          TextButton(
            child: Text(
              'Erase Data',
              style: TextStyle(
                fontSize: uiFontSize,
                fontFamily: uiFontFamily,
                color: Colors.red,
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
          ),
          TextButton(
            child: Text(
              'Cancel',
              style: TextStyle(
                fontSize: uiFontSize,
                fontFamily: uiFontFamily,
                color: getAdaptiveTextColor(context),
              ),
            ),
            onPressed: () => Navigator.pop(context, null),
          ),
        ],
      ),
    );

    if (confirm == null) return; // Cancelled

    try {
      await AuthService().signOut();
      SupabaseSyncService().dispose();
      if (confirm) {
        // Erase data
        final dbHighlights = await HighlightsDatabase.getDatabase();
        await dbHighlights.delete('user_highlights');

        final dbHistory = await HistoryDatabase.getDatabase();
        await dbHistory.delete('history');

        final dbNotes = await NotesDatabase.getDatabase();
        await dbNotes.delete('user_notes');

        final dbSearchHistory = await SearchDatabase.getDatabase();
        await dbSearchHistory.delete('search_history');

        // Notify UI to refresh
        LocalDataChangeNotifier.notifyHighlightsChanged();
        LocalDataChangeNotifier.notifyNotesChanged();

        if (context.mounted) {
          showStyledSnackBar(context, 'Signed out');
        }
      } else {
        if (context.mounted) {
          showStyledSnackBar(context, 'Signed out');
        }
      }
    } catch (e) {
      if (context.mounted) {
        showStyledSnackBar(context, 'Sign out failed: ${e.toString()}', isError: true);
      }
    }
  }

  // Change Password - Split into two separate dialogs
  Future<Map<String, String>?> _showChangePasswordConfirmationDialog(
    BuildContext context,
  ) async {
    final _currentPasswordController = TextEditingController();
    final _newPasswordController = TextEditingController();
    final _confirmPasswordController = TextEditingController();
    String? _errorMessage;

    final result = await showDialog<Map<String, String>?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          constraints: const BoxConstraints(maxWidth: 400),
          title: Center(
            child: Text(
              'Change Password',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: uiFontSize,
                fontFamily: uiFontFamily,
                color: getAdaptiveTextColor(context),
              ),
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              //OnscreenKeyboardTextField(
              TextField(
                maxLength: 100,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                controller: _currentPasswordController,
                decoration: InputDecoration(
                  counter: SizedBox.shrink(), // Hide the counter eg. 0/100
                  labelText: 'Current Password',
                  labelStyle: TextStyle(
                    fontSize: uiFontSize + 2,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context),
                  ),
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              //OnscreenKeyboardTextField(
              TextField(
                maxLength: 100,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                controller: _newPasswordController,
                decoration: InputDecoration(
                  counter: SizedBox.shrink(), // Hide the counter eg. 0/100
                  labelText: 'New Password',
                  labelStyle: TextStyle(
                    fontSize: uiFontSize + 2,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context),
                  ),
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              //OnscreenKeyboardTextField(
              TextField(
                maxLength: 100,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                controller: _confirmPasswordController,
                decoration: InputDecoration(
                  counter: SizedBox.shrink(), // Hide the counter eg. 0/100
                  labelText: 'Confirm New Password',
                  labelStyle: TextStyle(
                    fontSize: uiFontSize + 2,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context),
                  ),
                  border: OutlineInputBorder(),
                  errorText: _errorMessage,
                ),
                obscureText: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontSize: uiFontSize,
                  fontFamily: uiFontFamily,
                  color: getAdaptiveTextColor(context),
                ),
              ),
              onPressed: () => Navigator.pop(context, null),
            ),
            TextButton(
              onPressed: () {
                // Validate passwords
                if (_currentPasswordController.text.isEmpty ||
                    _newPasswordController.text.isEmpty ||
                    _confirmPasswordController.text.isEmpty) {
                  return;
                }

                Navigator.pop(context, {
                  'current': _currentPasswordController.text,
                  'new': _newPasswordController.text,
                });
              },
              child: Text(
                'Change Password',
                style: TextStyle(
                  fontSize: uiFontSize,
                  fontFamily: uiFontFamily,
                  color: getAdaptiveTextColor(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return result;
  }

  void _showChangePasswordProgressDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Please wait...',
              style: TextStyle(
                fontSize: uiFontSize,
                fontFamily: uiFontFamily,
                color: getAdaptiveTextColor(context),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) async {
    // Show confirmation dialog first
    final passwords = await _showChangePasswordConfirmationDialog(context);
    if (passwords == null || !context.mounted) return;

    // Show progress dialog
    _showChangePasswordProgressDialog(context);

    bool success = false;
    String? errorMessage;

    try {
      await _performPasswordChange(
        context,
        passwords['current']!,
        passwords['new']!,
      );
      success = true; // Both normal AND backup paths get here
    } catch (e) {
      errorMessage = e.toString().replaceAll('Exception: ', '');
    }

    if (context.mounted) {
      // Always close progress dialog
      Navigator.pop(context);

      if (success) {
        showStyledSnackBar(context, 'Password changed successfully');
      } else {
        showStyledSnackBar(
          context,
          'Password change failed: $errorMessage',
          isError: true,
        );
      }
    }
  }

  // Delete Account - Split into two separate dialogs
  Future<String?> _showDeleteConfirmationDialog(BuildContext context) async {
    final _passwordController = TextEditingController();
    String? _errorMessage;

    final result = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          //title: Text('Delete Account', style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily, color: Colors.red)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.warning,
                color: Colors.red,
                size: 48,
                semanticLabel: 'Delete Account Warning Dialog - this action cannot be undone.',
              ),
              const SizedBox(height: 16),
              Text(
                'This action cannot be undone.',
                style: TextStyle(
                  fontSize: uiFontSize + 2,
                  fontFamily: uiFontFamily,
                  color: Colors.red,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              //OnscreenKeyboardTextField(
              TextField(
                maxLength: 100,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                controller: _passwordController,
                decoration: InputDecoration(
                  counter: SizedBox.shrink(), // Hide the counter eg. 0/100
                  labelText: 'Confirm your password',
                  labelStyle: TextStyle(
                    fontSize: uiFontSize + 2,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context),
                  ),
                  border: OutlineInputBorder(),
                  errorText: _errorMessage,
                ),
                obscureText: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontSize: uiFontSize,
                  fontFamily: uiFontFamily,
                  color: getAdaptiveTextColor(context),
                ),
              ),
              onPressed: () => Navigator.pop(context, null),
            ),
            TextButton(
              onPressed: () {
                if (_passwordController.text.isEmpty) {
                  setState(() {
                    _errorMessage = 'Password is required';
                  });
                  return;
                }
                Navigator.pop(context, _passwordController.text);
              },
              child: Text(
                'Delete Account',
                style: TextStyle(
                  fontSize: uiFontSize,
                  fontFamily: uiFontFamily,
                  color: Colors.red,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return result;
  }

  void _showDeleteProgressDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Please wait...',
              style: TextStyle(
                fontSize: uiFontSize,
                fontFamily: uiFontFamily,
                color: getAdaptiveTextColor(context),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context) async {
    // Show confirmation dialog first
    final password = await _showDeleteConfirmationDialog(context);
    if (password == null || !context.mounted) return;

    // Show progress dialog
    _showDeleteProgressDialog(context);

    bool success = false;
    String? errorMessage;

    try {
      await AuthService().deleteAccount(password);
      success = true; // Both normal AND backup paths get here
    } catch (e) {
      errorMessage = e.toString().replaceAll('Exception: ', '');
    }

    // Always close progress dialog using global navigator key to ensure it works even if context is invalid
    if (navigatorKey.currentState?.canPop() ?? false) {
      navigatorKey.currentState?.pop();
    }

    if (context.mounted) {
      if (success) {
        showStyledSnackBar(context, 'Account deleted successfully');
      } else {
        showStyledSnackBar(
          context,
          'Account deletion failed: $errorMessage',
          isError: true,
        );
      }
    }
  }

  Future<void> _performPasswordChange(
    BuildContext context,
    String currentPassword,
    String newPassword,
  ) async {
    // New simplified approach: just pass current password - AuthService creates credential internally
    await AuthService().changePassword(currentPassword, newPassword);
  }

  bool _isTimeBasedThemeSelected() {
    // Return the cached state of time-based theme
    return _isTimeBasedThemeEnabled;
  }

  void _showTimeBasedThemeSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: 350,
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  /*child: Center(
                    child: Text('Time-based Theme Settings', style: TextStyle(fontSize: uiFontSize, fontFamily: uiFontFamily, fontWeight: FontWeight.bold, color: getAdaptiveTextColor(context))),
                  ),*/
                ),
                //SizedBox(height: 24),
                Text(
                  'Configure when the theme should switch between light and dark modes.',
                  style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'Day Start Time (Light Mode):',
                  style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context),
                  ),
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<int>(
                  valueListenable: dayStartHourNotifier,
                  builder: (context, dayStartHour, _) {
                    return Row(
                      children: [
                        Expanded(
                          child: Slider(
                            value: dayStartHour.toDouble(),
                            min: 0,
                            max: 23,
                            divisions: 24,
                            label: '${dayStartHour.toString().padLeft(2, '0')}:00',
                            onChanged: (value) {
                              dayStartHourNotifier.value = value.toInt();
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          '${dayStartHour.toString().padLeft(2, '0')}:00',
                          style: TextStyle(
                            fontSize: uiFontSize,
                            fontFamily: uiFontFamily,
                            color: getAdaptiveTextColor(context),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
                Text(
                  'Night Start Time (Dark Mode):',
                  style: TextStyle(
                    fontSize: uiFontSize,
                    fontFamily: uiFontFamily,
                    color: getAdaptiveTextColor(context),
                  ),
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<int>(
                  valueListenable: nightStartHourNotifier,
                  builder: (context, nightStartHour, _) {
                    return Row(
                      children: [
                        Expanded(
                          child: Slider(
                            value: nightStartHour.toDouble(),
                            min: 0,
                            max: 23,
                            divisions: 24,
                            label: '${nightStartHour.toString().padLeft(2, '0')}:00',
                            onChanged: (value) {
                              nightStartHourNotifier.value = value.toInt();
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          '${nightStartHour.toString().padLeft(2, '0')}:00',
                          style: TextStyle(
                            fontSize: uiFontSize,
                            fontFamily: uiFontFamily,
                            color: getAdaptiveTextColor(context),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
                //Text('Current theme will update immediately when you change these settings.', style: TextStyle(fontSize: uiFontSize - 2, fontFamily: uiFontFamily, fontStyle: FontStyle.italic, color: getAdaptiveTextColor(context))),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      child: Text(
                        'Reset',
                        style: TextStyle(
                          fontSize: uiFontSize,
                          fontFamily: uiFontFamily,
                          color: getAdaptiveTextColor(context),
                        ),
                      ),
                      onPressed: () {
                        dayStartHourNotifier.value = defaultDayStartHour;
                        nightStartHourNotifier.value = defaultNightStartHour;
                        _updateThemeBasedOnTime(); // Update theme immediately
                      },
                    ),
                    TextButton(
                      child: Text(
                        'Close',
                        style: TextStyle(
                          fontSize: uiFontSize,
                          fontFamily: uiFontFamily,
                          color: getAdaptiveTextColor(context),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    TextButton(
                      child: Text(
                        'Save',
                        style: TextStyle(
                          fontSize: uiFontSize,
                          fontFamily: uiFontFamily,
                          color: getAdaptiveTextColor(context),
                        ),
                      ),
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setInt(
                          'dayStartHour',
                          dayStartHourNotifier.value,
                        );
                        await prefs.setInt(
                          'nightStartHour',
                          nightStartHourNotifier.value,
                        );
                        _updateThemeBasedOnTime(); // Update theme immediately
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<String?> _getUsername(User? user) async {
    if (user == null) return null;

    // First check the cached username
    final cachedUsername = await SupabaseSyncService.getCachedUsername();

    // If cached username is available and not "Unknown", return it
    if (cachedUsername != null && cachedUsername != 'Unknown') {
      return cachedUsername;
    }

    // If cached is "Unknown", check if we can access Supabase before trying
    if (cachedUsername == 'Unknown') {
      final canConnect = await SupabaseSyncService().checkSupabaseConnection();
      if (!canConnect) {
        return 'Unknown'; // Can't access, show Unknown
      }
    }

    // Try to fetch from Supabase and cache it
    try {
      final response = await Supabase.instance.client.from('profiles').select('username').eq('id', user.id).single();
      final username = response['username'];
      // Cache the username for offline use
      await SupabaseSyncService().setCachedUsername(username ?? 'Unknown');
      return username;
    } catch (e) {
      return cachedUsername ?? 'Unknown';
    }
  }

  // tablet detection mode testing
  // Add this to any widget's initState() or call from main()
  Future<void> testTabletMode() async {
    final isTablet = await TabletModeDetector.isTabletMode();
    final hasKeyboard = await TabletModeDetector.isKeyboardAttached();
    final hasTouch = await TabletModeDetector.hasTouchScreen();
    final maxTouchPoints = await TabletModeDetector.getMaximumTouchPoints();
    final deviceInfo = await TabletModeDetector.getDeviceInfo();

    if (kDebugMode) debugPrint('=== Tablet Mode Detection ===');
    if (kDebugMode) debugPrint('Tablet Mode: $isTablet');
    if (kDebugMode) debugPrint('Keyboard Attached: $hasKeyboard');
    if (kDebugMode) debugPrint('Touch Screen: $hasTouch');
    if (kDebugMode) debugPrint('Max Touch Points: $maxTouchPoints');
    if (kDebugMode) debugPrint('Device Info: $deviceInfo');
  }
}
