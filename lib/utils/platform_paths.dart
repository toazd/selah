import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class PlatformPaths {
  // Get the appropriate user data directory for the current platform
  static Future<String> getUserDataDirectory() async {
    if (kIsWeb) {
      // Web: Use browser's local storage (handled by Flutter)
      return 'web_storage';
    }

    if (Platform.isWindows) {
      // Windows: Use %APPDATA%/com.selah.holybible/selah
      final appData = Platform.environment['APPDATA'] ??
          join(
              Platform.environment['USERPROFILE'] ??
                  Platform.environment['HOME'] ??
                  '',
              'AppData',
              'Roaming');
      return join(appData, 'com.selah.holybible', 'selah');
    } else if (Platform.isLinux) {
      // Linux: Use ~/.config/selah
      final homeDir = Platform.environment['HOME'] ?? '';
      return join(homeDir, '.config', 'selah');
    } else if (Platform.isMacOS) {
      // macOS: Use ~/Library/Application Support/Selah
      final appSupport = await getApplicationSupportDirectory();
      return join(appSupport.path, 'Selah');
    } else if (Platform.isAndroid || Platform.isIOS) {
      // Mobile: Use app-specific directory
      final appSupport = await getApplicationSupportDirectory();
      return appSupport.path;
    } else {
      throw Exception('Unsupported platform: ${Platform.operatingSystem}');
    }
  }

  // Get the appropriate shared preferences path
  static Future<String> getSharedPreferencesPath() async {
    if (kIsWeb) {
      // Web: Use browser's local storage (handled by Flutter)
      return 'web_shared_preferences';
    }

    final userDataDir = await getUserDataDirectory();
    return join(userDataDir, 'shared_preferences.json');
  }

  // Ensure the user data directory exists
  static Future<void> ensureUserDataDirectory() async {
    if (kIsWeb) return;

    final userDataDir = await getUserDataDirectory();
    if (userDataDir == 'web_storage') return; // Skip for web

    final directory = Directory(userDataDir);

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
  }

  // Get database path for a specific database name
  static Future<String> getDatabasePath(String dbName) async {
    if (kIsWeb) {
      return '$dbName.db';
    }

    final userDataDir = await getUserDataDirectory();
    if (userDataDir == 'web_storage') return '$dbName.db'; // Skip for web

    await ensureUserDataDirectory();
    return join(userDataDir, '$dbName.sqlite');
  }

  // Get asset path (for bundled assets that need to be copied)
  static Future<String> getAssetPath(String assetPath) async {
    if (kIsWeb) {
      return assetPath;
    }

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // Desktop: Check current directory first, then assets
      final currentDir = Directory.current.path;
      final path1 = join(currentDir, 'assets', assetPath);
      final path2 =
          join(currentDir, 'data', 'flutter_assets', 'assets', assetPath);

      if (await File(path1).exists()) {
        return path1;
      } else if (await File(path2).exists()) {
        return path2;
      } else {
        // Return the assets path as fallback
        return path2;
      }
    } else {
      // Mobile: Use the asset path directly
      return assetPath;
    }
  }
}
