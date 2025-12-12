import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'dart:io';
import '../services/firestore_sync_service.dart';
import '../utils/data_validation.dart';

class SearchDatabase {
  static Database? _database;

  // Database table name
  static const String searchHistoryTable = 'search_history';

  // Search history table columns
  static const String colId = 'id';
  static const String colQuery = 'query';
  static const String colUseRegex = 'useRegex';
  static const String colUseNearby = 'useNearby';
  static const String colUseWholeWord = 'useWholeWord';
  static const String colUseRedLetter = 'useRedLetter';
  static const String colCaseSensitive = 'caseSensitive';
  static const String colBookFilterType = 'bookFilterType';
  static const String colCustomBookFilter = 'customBookFilter';
  static const String colTimestamp = 'timestamp';

  // Initialize database
  static Future<Database> getDatabase() async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    String dbPath;
    try {
      if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        // FFI is already initialized in main.dart - just open the database
        // Try both locations (same as other databases)
        String path1 = join(Directory.current.path, 'assets/user_search.sqlite');
        String path2 = join(Directory.current.path, 'data/flutter_assets/assets/user_search.sqlite');

        if (await File(path1).exists()) {
          dbPath = path1;
        } else if (await File(path2).exists()) {
          dbPath = path2;
        } else {
          // Use the flutter_assets location as default for new databases
          dbPath = path2;
          // Ensure directory exists
          await Directory(join(Directory.current.path, 'data/flutter_assets/assets')).create(recursive: true);
        }

        _database = await databaseFactory.openDatabase(dbPath);

        // Create search history table if it doesn't exist
        await _database!.execute('''
          CREATE TABLE IF NOT EXISTS $searchHistoryTable (
            $colId INTEGER PRIMARY KEY AUTOINCREMENT,
            $colQuery TEXT NOT NULL,
            $colUseRegex INTEGER NOT NULL,
            $colUseNearby INTEGER NOT NULL,
            $colUseWholeWord INTEGER NOT NULL,
            $colUseRedLetter INTEGER NOT NULL,
            $colCaseSensitive INTEGER NOT NULL,
            $colBookFilterType TEXT NOT NULL,
            $colCustomBookFilter TEXT NOT NULL,
            $colTimestamp INTEGER UNIQUE
          )
        ''');

        return _database!;
      } else if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        // Mobile: use database path
        final databasesPath = await getDatabasesPath();
        dbPath = join(databasesPath, 'user_search.sqlite');
        return await openDatabase(
          dbPath,
          version: 1,
          onCreate: _onCreate,
        );
      } else if (kIsWeb) {
        // Simple names for Web
        dbPath = 'search.db';

        _database = await openDatabase(
          dbPath,
          version: 1,
          onCreate: _onCreate,
        );

        return _database!;
      } else {
        throw Exception('Unsupported platform');
      }
    } catch (e) {
      throw Exception('Database error: $e');
    }
  }

  static Future<void> _onCreate(Database db, int version) async {
    // Create search history table
    await db.execute('''
    CREATE TABLE $searchHistoryTable (
      $colId INTEGER PRIMARY KEY AUTOINCREMENT,
      $colQuery TEXT NOT NULL,
      $colUseRegex INTEGER NOT NULL,
      $colUseNearby INTEGER NOT NULL,
      $colUseWholeWord INTEGER NOT NULL,
      $colUseRedLetter INTEGER NOT NULL,
      $colCaseSensitive INTEGER NOT NULL,
      $colBookFilterType TEXT NOT NULL,
      $colCustomBookFilter TEXT NOT NULL,
      $colTimestamp INTEGER UNIQUE
    )
  ''');
  }

  // Get all search history
  static Future<List<Map<String, dynamic>>> getSearchHistory() async {
    Database db = await getDatabase();

    final result = await db.query(searchHistoryTable, orderBy: '$colTimestamp DESC');

    // Convert int boolean fields back to bool values for the rest of the app
    final results = result.map((item) {
      return {
        'id': item[colId],
        'query': item[colQuery],
        'useRegex': (item[colUseRegex] as int) == 1,
        'useNearby': (item[colUseNearby] as int) == 1,
        'useWholeWord': (item[colUseWholeWord] as int) == 1,
        'useRedLetter': (item[colUseRedLetter] as int) == 1,
        'caseSensitive': (item[colCaseSensitive] as int) == 1,
        'bookFilterType': item[colBookFilterType],
        'customBookFilter': item[colCustomBookFilter],
        'timestamp': item[colTimestamp],
      };
    }).toList();

    // Validate and filter out corrupt records
    final validResults = <Map<String, dynamic>>[];
    final corruptIds = <int>[];

    for (final record in results) {
      final isValid =
          await DataValidation.validateDatabaseRecord(record, 'search_history', context: 'database query');
      if (isValid) {
        validResults.add(record);
      } else {
        corruptIds.add(record['id'] as int);
      }
    }

    // Delete corrupt records
    if (corruptIds.isNotEmpty) {
      await db.delete(searchHistoryTable,
          where: 'id IN (${corruptIds.map((_) => '?').join(',')})', whereArgs: corruptIds);
    }

    return validResults;
  }

  // Get search history with pagination
  static Future<List<Map<String, dynamic>>> getSearchHistoryPaginated(int offset, int limit) async {
    Database db = await getDatabase();

    try {
      final result = await db.query(
        searchHistoryTable,
        orderBy: '$colTimestamp DESC',
        limit: limit,
        offset: offset,
      );

      // Convert int boolean fields back to bool values for the rest of the app
      final results = result.map((item) {
        return {
          'id': item[colId],
          'query': item[colQuery],
          'useRegex': (item[colUseRegex] as int) == 1,
          'useNearby': (item[colUseNearby] as int) == 1,
          'useWholeWord': (item[colUseWholeWord] as int) == 1,
          'useRedLetter': (item[colUseRedLetter] as int) == 1,
          'caseSensitive': (item[colCaseSensitive] as int) == 1,
          'bookFilterType': item[colBookFilterType],
          'customBookFilter': item[colCustomBookFilter],
          'timestamp': item[colTimestamp],
        };
      }).toList();

      // Validate and filter out corrupt records
      final validResults = <Map<String, dynamic>>[];
      final corruptIds = <int>[];

      for (final record in results) {
        final isValid =
            await DataValidation.validateDatabaseRecord(record, 'search_history', context: 'database query');
        if (isValid) {
          validResults.add(record);
        } else {
          corruptIds.add(record['id'] as int);
        }
      }

      // Delete corrupt records
      if (corruptIds.isNotEmpty) {
        await db.delete(searchHistoryTable,
            where: 'id IN (${corruptIds.map((_) => '?').join(',')})', whereArgs: corruptIds);
      }

      return validResults;
    } catch (e) {
      rethrow;
    }
  }

  // Add search history
  static Future<void> addSearchHistory(
    String query,
    bool useRegex,
    bool useNearby,
    bool useWholeWord,
    bool useRedLetter,
    bool caseSensitive,
    String bookFilterType,
    String customBookFilter,
    int timestamp, {
    bool skipSync = false,
  }) async {
    // Validate data before saving to database
    final searchHistoryData = {
      'query': query,
      'useRegex': useRegex,
      'useNearby': useNearby,
      'useWholeWord': useWholeWord,
      'useRedLetter': useRedLetter,
      'caseSensitive': caseSensitive,
      'bookFilterType': bookFilterType,
      'customBookFilter': customBookFilter,
      'timestamp': timestamp,
    };

    final isValid = await DataValidation.validateBeforeDatabaseWrite(searchHistoryData, 'search_history');
    if (!isValid) {
      throw Exception('Invalid search history data - failed validation. Operation rejected.');
    }

    Database db = await getDatabase();
    await db.insert(searchHistoryTable, {
      colQuery: query,
      colUseRegex: useRegex ? 1 : 0,
      colUseNearby: useNearby ? 1 : 0,
      colUseWholeWord: useWholeWord ? 1 : 0,
      colUseRedLetter: useRedLetter ? 1 : 0,
      colCaseSensitive: caseSensitive ? 1 : 0,
      colBookFilterType: bookFilterType,
      colCustomBookFilter: customBookFilter,
      colTimestamp: timestamp,
    });

    if (!skipSync) {
      // Queue create operation for sync service
      final syncData = {
        'query': query,
        'useRegex': useRegex,
        'useNearby': useNearby,
        'useWholeWord': useWholeWord,
        'useRedLetter': useRedLetter,
        'caseSensitive': caseSensitive,
        'bookFilterType': bookFilterType,
        'customBookFilter': customBookFilter,
        'timestamp': timestamp,
      };
      FirestoreSyncService().markOperation('search_history', timestamp, 'create', syncData);
    }

    // Add a 1ms delay to ensure no two records have the same timestamp
    await Future.delayed(Duration(milliseconds: 1));
  }

  // Delete search history item
  static Future<void> deleteSearchHistoryItem(int id, {skipSync = false}) async {
    // Get the search history item data before deletion for sync
    final db = await getDatabase();
    final searchHistoryItem = await db.query(searchHistoryTable, where: '$colId = ?', whereArgs: [id]);

    // Delete locally first
    await db.delete(searchHistoryTable, where: '$colId = ?', whereArgs: [id]);

    // Queue delete operation for sync service if not skipped
    if (!skipSync && searchHistoryItem.isNotEmpty) {
      try {
        // Convert raw database data to proper types for sync service
        final item = searchHistoryItem.first;
        final syncData = {
          'id': item[colId],
          'query': item[colQuery],
          'useRegex': (item[colUseRegex] as int) == 1,
          'useNearby': (item[colUseNearby] as int) == 1,
          'useWholeWord': (item[colUseWholeWord] as int) == 1,
          'useRedLetter': (item[colUseRedLetter] as int) == 1,
          'caseSensitive': (item[colCaseSensitive] as int) == 1,
          'bookFilterType': item[colBookFilterType],
          'customBookFilter': item[colCustomBookFilter],
          'timestamp': item[colTimestamp],
        };

        FirestoreSyncService().markOperation('search_history', item[colTimestamp] as int, 'delete', syncData);
      } catch (e) {
        if (kDebugMode) debugPrint('deleteSearchHistoryItem markOperation exception: $e');
      }
    }
  }

  // Clear all search history
  static Future<void> clearSearchHistory() async {
    // Search history is local with sync, delete all directly
    Database db = await getDatabase();
    await db.delete(searchHistoryTable);
  }

// Check for exact duplicate search histories
  static Future<Map<String, dynamic>?> getSearchHistoryByParams({
    required String query,
    required bool useRegex,
    required bool useNearby,
    required bool useWholeWord,
    required bool useRedLetter,
    required bool caseSensitive,
    required String bookFilterType,
    required String customBookFilter,
  }) async {
    Database db = await getDatabase();

    // Build WHERE conditions and arguments dynamically
    List<String> whereConditions = [
      'query = ?',
      'useRegex = ?',
      'useNearby = ?',
      'useWholeWord = ?',
      'useRedLetter = ?',
      'caseSensitive = ?',
      'bookFilterType = ?',
    ];

    List<dynamic> whereArgs = [
      query,
      useRegex ? 1 : 0,
      useNearby ? 1 : 0,
      useWholeWord ? 1 : 0,
      useRedLetter ? 1 : 0,
      caseSensitive ? 1 : 0,
      bookFilterType,
    ];

    // Only include customBookFilter in duplicate check when using Custom Range
    if (bookFilterType == 'Custom Range') {
      whereConditions.add('customBookFilter = ?');
      whereArgs.add(customBookFilter);
    }

    final whereClause = whereConditions.join(' AND ');

    final result = await db.query(
      searchHistoryTable,
      where: whereClause,
      whereArgs: whereArgs,
      limit: 1, // We only need to know if one exists
    );

    return result.isNotEmpty ? result.first : null;
  }
}
