import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

import '../supabase_config.dart';
import '../utils/platform_paths.dart';

/// Moves sessions written by the former Windows-only auth storage into the
/// normal Supabase SharedPreferences key. This is a one-time compatibility
/// migration; all active session reads and writes use Supabase's default
/// storage on every platform.
Future<void> migrateLegacyWindowsAuthSession() async {
  if (kIsWeb || !Platform.isWindows) return;

  const legacySessionFileName = 'supabase_auth.json';
  final persistSessionKey =
      'sb-${Uri.parse(SupabaseConfig.supabaseUrl).host.split('.').first}-auth-token';

  try {
    final preferences = await SharedPreferences.getInstance();

    // Do not replace a session already managed by Supabase's standard storage.
    if (preferences.containsKey(persistSessionKey)) {
      debugPrint(
          '[AuthTrace] Windows legacy session migration skipped: shared session already exists');
      return;
    }

    final userDataDirectory = await PlatformPaths.getUserDataDirectory();
    final sessionFile =
        File(path.join(userDataDirectory, legacySessionFileName));
    if (!await sessionFile.exists()) return;

    final session = await sessionFile.readAsString();
    if (!_isSessionJson(session)) {
      debugPrint(
          '[AuthTrace] Windows legacy session migration skipped: file contents were invalid');
      return;
    }

    final saved = await preferences.setString(persistSessionKey, session);
    if (!saved) {
      debugPrint(
          '[AuthTrace] Windows legacy session migration failed: SharedPreferences rejected the session');
      return;
    }

    // The session is now owned by the standard storage. Remove only the old
    // active file; an interrupted migration leaves it available for retry.
    await sessionFile.delete();
    final backupFile = File('${sessionFile.path}.bak');
    if (await backupFile.exists()) await backupFile.delete();
    debugPrint(
        '[AuthTrace] Windows legacy session migrated to SharedPreferences');
  } catch (error, stackTrace) {
    debugPrint('[AuthTrace] Windows legacy session migration error: $error');
    debugPrint(stackTrace.toString());
  }
}

bool _isSessionJson(String value) {
  try {
    final decoded = jsonDecode(value);
    return decoded is Map<String, dynamic> &&
        decoded['access_token'] is String &&
        (decoded['access_token'] as String).isNotEmpty;
  } catch (_) {
    return false;
  }
}
