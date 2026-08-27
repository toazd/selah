import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_config.dart';
import '../utils/platform_paths.dart';

/// Windows session storage that is isolated from the app's preferences file.
///
/// The default Supabase Flutter storage uses SharedPreferences. On Windows,
/// SharedPreferences is one JSON file containing every app preference, and
/// writes replace that file in its entirety. Auth recovery, token refreshes,
/// shutdown saves, and settings changes can therefore overwrite one another.
/// Keeping the session in its own file prevents those unrelated writes from
/// logging a user out after an installer upgrade.
class WindowsAuthStorage extends LocalStorage {
  static const String _sessionFileName = 'supabase_auth.json';

  final String _legacyPersistSessionKey =
      'sb-${Uri.parse(SupabaseConfig.supabaseUrl).host.split('.').first}-auth-token';

  File? _sessionFile;
  File? _backupFile;
  String? _session;
  Future<void>? _initialization;
  Future<void> _writeChain = Future<void>.value();

  @override
  Future<void> initialize() {
    final existingInitialization = _initialization;
    if (existingInitialization != null) return existingInitialization;

    final initialization = _initializeInternal();
    _initialization = initialization;
    return initialization.whenComplete(() {
      if (identical(_initialization, initialization)) {
        _initialization = null;
      }
    });
  }

  Future<void> _initializeInternal() async {
    if (!Platform.isWindows) return;

    final userDataDirectory = await PlatformPaths.getUserDataDirectory();
    final directory = Directory(userDataDirectory);
    await directory.create(recursive: true);

    _sessionFile = File(path.join(userDataDirectory, _sessionFileName));
    _backupFile = File('${_sessionFile!.path}.bak');

    final sessionFileValue = await _readValidSession(_sessionFile!);
    if (sessionFileValue != null) {
      _session = sessionFileValue;
      return;
    }

    // Recover from a previous interrupted replacement before looking at the
    // legacy SharedPreferences token.
    final backupValue = await _readValidSession(_backupFile!);
    if (backupValue != null) {
      _session = backupValue;
      await _enqueueWrite(() => _writeSessionFile(backupValue));
      return;
    }

    // One-time migration from releases that used SharedPreferencesLocalStorage.
    final preferences = await SharedPreferences.getInstance();
    final legacyValue = preferences.getString(_legacyPersistSessionKey);
    if (_isValidSession(legacyValue)) {
      _session = legacyValue;
      await _enqueueWrite(() => _writeSessionFile(legacyValue!));

      // Once the isolated file is safely written, remove the token from the
      // shared preferences file so old auth state cannot be mistaken for the
      // current session by a later migration.
      await preferences.remove(_legacyPersistSessionKey);
    }
  }

  @override
  Future<bool> hasAccessToken() async {
    await _ensureInitialized();
    return _session != null;
  }

  @override
  Future<String?> accessToken() async {
    await _ensureInitialized();
    return _session;
  }

  @override
  Future<void> removePersistedSession() async {
    if (!Platform.isWindows) return;
    await _ensureInitialized();
    _session = null;
    await _enqueueWrite(_removeSessionFile);
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    if (!Platform.isWindows) return;
    if (!_isValidSession(persistSessionString)) {
      throw const FormatException('Invalid Supabase session');
    }

    await _ensureInitialized();
    _session = persistSessionString;
    await _enqueueWrite(() => _writeSessionFile(persistSessionString));
  }

  /// Wait until the last auth write has reached disk before the process exits.
  Future<void> flush() async {
    await _writeChain;
  }

  Future<void> _ensureInitialized() async {
    if (_sessionFile == null) await initialize();
  }

  Future<void> _enqueueWrite(Future<void> Function() operation) {
    final next = _writeChain.then((_) => operation());
    // A failed write must not prevent a later sign-in or sign-out write from
    // running. The original future still reports the failure to its caller.
    _writeChain = next.catchError((Object _) {});
    return next;
  }

  Future<void> _writeSessionFile(String value) async {
    final sessionFile = _sessionFile;
    final backupFile = _backupFile;
    if (sessionFile == null || backupFile == null) return;

    final temporaryFile = File(
      '${sessionFile.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      if (await sessionFile.exists()) {
        if (await backupFile.exists()) await backupFile.delete();
        await sessionFile.copy(backupFile.path);
      }

      await temporaryFile.writeAsString(value, flush: true);
      try {
        await temporaryFile.rename(sessionFile.path);
      } on FileSystemException {
        // Windows may reject rename-over-existing. Keep the replacement small
        // and restore the previous session if the second rename fails.
        if (await sessionFile.exists()) await sessionFile.delete();
        await temporaryFile.rename(sessionFile.path);
      }

      if (await backupFile.exists()) await backupFile.delete();
    } catch (_) {
      if (await temporaryFile.exists()) await temporaryFile.delete();
      if (!await sessionFile.exists() && await backupFile.exists()) {
        try {
          await backupFile.copy(sessionFile.path);
        } catch (_) {
          // Preserve the original write error for the caller.
        }
      }
      rethrow;
    }
  }

  Future<void> _removeSessionFile() async {
    final sessionFile = _sessionFile;
    final backupFile = _backupFile;
    if (sessionFile != null && await sessionFile.exists()) {
      await sessionFile.delete();
    }
    if (backupFile != null && await backupFile.exists()) {
      await backupFile.delete();
    }
  }

  Future<String?> _readValidSession(File file) async {
    try {
      if (!await file.exists()) return null;
      final value = await file.readAsString();
      return _isValidSession(value) ? value : null;
    } catch (_) {
      return null;
    }
  }

  bool _isValidSession(String? value) {
    if (value == null || value.isEmpty) return false;
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> &&
          decoded['access_token'] is String &&
          (decoded['access_token'] as String).isNotEmpty &&
          decoded['refresh_token'] is String &&
          (decoded['refresh_token'] as String).isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}

final WindowsAuthStorage windowsAuthStorage = WindowsAuthStorage();
