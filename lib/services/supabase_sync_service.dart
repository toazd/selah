import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart'; // for kDebugMode
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import '../database/highlights_database.dart';
import '../database/notes_database.dart';
import '../database/history_database.dart';
import '../database/search_database.dart';
import 'local_data_change_notifier.dart';
import '../utils/note_storage_format.dart';
import '../utils/error_handler.dart';
import '../utils/preferences_constants.dart';
import '../utils/internet_access_checker.dart';
import '../utils/data_validation.dart';
import '../supabase_config.dart';

// Add streams for notifying UI of data changes
StreamController<void>? _highlightsChangedController;
StreamController<void>? _notesChangedController;
StreamController<void>? _historyChangedController;
StreamController<void>? _searchHistoryChangedController;

/// Global notifier for UI to listen to sync status changes
final ValueNotifier<SyncStatus> syncStatusNotifier =
    ValueNotifier(SyncStatus.offline);

// Prevent rapid initialize() calls
bool _isInitialized = false;

const int _remoteSyncPageSize = 500;

enum SyncStatus { offline, connecting, online, syncing, error }

class SyncOperation {
  final String id;
  final String type; // 'highlight', 'note', 'history'
  final String operation; // 'create', 'update', 'delete'
  final Map<String, dynamic> data;
  final DateTime timestamp;
  final int retryCount; // Track number of retry attempts
  final String?
      userId; // Owner account for safe cross-account queue persistence

  SyncOperation({
    required this.id,
    required this.type,
    required this.operation,
    required this.data,
    required this.timestamp,
    this.retryCount = 0,
    this.userId,
  });

  SyncOperation copyWith(
      {int? retryCount, DateTime? timestamp, String? userId}) {
    return SyncOperation(
      id: id,
      type: type,
      operation: operation,
      data: data,
      timestamp: timestamp ?? this.timestamp,
      retryCount: retryCount ?? this.retryCount,
      userId: userId ?? this.userId,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'operation': operation,
      'data': data,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'retryCount': retryCount,
      'userId': userId,
    };
  }

  factory SyncOperation.fromMap(Map<String, dynamic> map) {
    return SyncOperation(
      id: map['id'],
      type: map['type'],
      operation: map['operation'],
      data: Map<String, dynamic>.from(map['data']),
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
      retryCount: map['retryCount'] ?? 0,
      userId: map['userId'] as String?,
    );
  }
}

class SyncReconciliationAction {
  final int localId;
  final int naturalKey;
  final String operation;
  final String? uuid;

  const SyncReconciliationAction({
    required this.localId,
    required this.naturalKey,
    required this.operation,
    this.uuid,
  });
}

class _SyncReconciliationSnapshot {
  final List<Map<String, dynamic>> localRecords;
  final List<SyncReconciliationAction> actions;

  const _SyncReconciliationSnapshot({
    required this.localRecords,
    required this.actions,
  });
}

class SupabaseSyncService {
  /// Simple, fault-tolerant sync service for multi-device Bible study app.
  /// Uploads local changes immediately, downloads remote changes incrementally.
  /// No automatic deletion of remote data to prevent data loss (unless it is found to be corrupt)
  static final SupabaseSyncService _instance = SupabaseSyncService._internal();
  factory SupabaseSyncService() => _instance;
  SupabaseSyncService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final Connectivity _connectivity = Connectivity();

  SyncStatus _syncStatus = SyncStatus.offline;
  bool _isListening = false;

  // Last sync timestamps to track changes
  DateTime? _lastHighlightsSync;
  DateTime? _lastNotesSync;
  DateTime? _lastHistorySync;
  DateTime? _lastSearchHistorySync;

  // Last sync timestamps (now persisted)
  DateTime? _lastHighlightsSyncSaved;
  DateTime? _lastNotesSyncSaved;
  DateTime? _lastHistorySyncSaved;
  DateTime? _lastSearchHistorySyncSaved;

  // Listener subscriptions - changed to RealtimeChannel for onPostgresChanges
  RealtimeChannel? _highlightsChannel;
  RealtimeChannel? _notesChannel;
  RealtimeChannel? _historyChannel;
  RealtimeChannel? _searchHistoryChannel;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // Persistent queues for offline changes (persist across app restarts)
  final List<SyncOperation> _highlightsPendingQueue = [];
  final List<SyncOperation> _notesPendingQueue = [];
  final List<SyncOperation> _historyPendingQueue = [];
  final List<SyncOperation> _searchHistoryPendingQueue = [];

  // Preferences keys for persistent queues
  static const String _highlightsQueueKey = 'pendingHighlightsQueue';
  static const String _notesQueueKey = 'pendingNotesQueue';
  static const String _historyQueueKey = 'pendingHistoryQueue';
  static const String _searchHistoryQueueKey = 'pendingSearchHistoryQueue';

  // Retry queue for failed sync operations
  final List<SyncOperation> _retryQueue = [];
  Timer? _retryTimer;
  final Map<String, Future<List<SyncReconciliationAction>>>
      _recoveryOperationsByType = {};

  // Get current user ID
  String? get _currentUserId => _supabase.auth.currentUser?.id;

  @visibleForTesting
  static List<SyncReconciliationAction> buildReconciliationActions({
    required Iterable<Map<String, dynamic>> localRecords,
    required Map<int, String> remoteUuidByNaturalKey,
    required Set<int> pendingNaturalKeys,
    required String naturalKeyColumn,
  }) {
    final actions = <SyncReconciliationAction>[];

    for (final record in localRecords) {
      final localId = record['id'] as int?;
      final naturalKey = record[naturalKeyColumn] as int?;
      if (localId == null || naturalKey == null) {
        continue;
      }

      final localUuid = record['uuid'] as String?;
      final remoteUuid = remoteUuidByNaturalKey[naturalKey];
      final hasLocalUuid = localUuid != null && localUuid.isNotEmpty;

      if (remoteUuid != null) {
        if (!hasLocalUuid || localUuid != remoteUuid) {
          actions.add(SyncReconciliationAction(
            localId: localId,
            naturalKey: naturalKey,
            operation: 'repair_uuid',
            uuid: remoteUuid,
          ));
        }
        continue;
      }

      if (!pendingNaturalKeys.contains(naturalKey)) {
        actions.add(SyncReconciliationAction(
          localId: localId,
          naturalKey: naturalKey,
          operation: hasLocalUuid ? 'delete_local' : 'upload_local',
        ));
      }
    }

    return actions;
  }

  @visibleForTesting
  static bool shouldAdvanceSyncTimestamp({
    required Iterable<SyncReconciliationAction> failedRecoveryActions,
    required Set<int> failedUploadNaturalKeys,
    required Set<int> pendingNaturalKeys,
  }) {
    return failedRecoveryActions.isEmpty &&
        failedUploadNaturalKeys.isEmpty &&
        pendingNaturalKeys.isEmpty;
  }

  Future<List<Map<String, dynamic>>> _fetchRemoteRows({
    required String table,
    String columns = '*',
    required String orderColumn,
    String? secondaryOrderColumn,
    String? greaterThanColumn,
    int? greaterThanValue,
  }) async {
    if (_currentUserId == null) return [];

    final rows = <Map<String, dynamic>>[];
    var from = 0;

    while (true) {
      dynamic query =
          _supabase.from(table).select(columns).eq('user_id', _currentUserId!);

      if (greaterThanColumn != null && greaterThanValue != null) {
        query = query.gt(greaterThanColumn, greaterThanValue);
      }

      query = query.order(orderColumn, ascending: false);

      if (secondaryOrderColumn != null && secondaryOrderColumn != orderColumn) {
        query = query.order(secondaryOrderColumn, ascending: false);
      }

      query = query.range(from, from + _remoteSyncPageSize - 1);

      final page = List<Map<String, dynamic>>.from(await query);
      rows.addAll(page);

      if (page.length < _remoteSyncPageSize) {
        break;
      }

      from += _remoteSyncPageSize;
    }

    return rows;
  }

  // Helper method to get sync enabled status from individual preferences
  Future<bool> _getSyncEnabled(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? true;
  }

  // Load persisted last sync timestamps
  Future<void> _loadLastSyncTimestamps() async {
    final prefs = await SharedPreferences.getInstance();
    final highlightsTs = prefs.getInt('lastHighlightsSync');
    final notesTs = prefs.getInt('lastNotesSync');
    final historyTs = prefs.getInt('lastHistorySync');
    final searchHistoryTs = prefs.getInt('lastSearchHistorySync');

    if (highlightsTs != null) {
      _lastHighlightsSyncSaved = await DataValidation.validateTimeStamp(
          DateTime.fromMillisecondsSinceEpoch(highlightsTs));
    }
    if (notesTs != null) {
      _lastNotesSyncSaved = await DataValidation.validateTimeStamp(
          DateTime.fromMillisecondsSinceEpoch(notesTs));
    }
    if (historyTs != null) {
      _lastHistorySyncSaved = await DataValidation.validateTimeStamp(
          DateTime.fromMillisecondsSinceEpoch(historyTs));
    }
    if (searchHistoryTs != null) {
      _lastSearchHistorySyncSaved = await DataValidation.validateTimeStamp(
          DateTime.fromMillisecondsSinceEpoch(searchHistoryTs));
    }

    // Initialize current session timestamps from persisted values
    _lastHighlightsSync = _lastHighlightsSyncSaved;
    _lastNotesSync = _lastNotesSyncSaved;
    _lastHistorySync = _lastHistorySyncSaved;
    _lastSearchHistorySync = _lastSearchHistorySyncSaved;
  }

  // Save last sync timestamps to preferences - MUST specify category (no optional parameter)
  Future<void> _saveLastSyncTimestamps(String category) async {
    final prefs = await SharedPreferences.getInstance();

    if (category == 'highlights') {
      if (_lastHighlightsSync != null) {
        await prefs.setInt(
            'lastHighlightsSync', _lastHighlightsSync!.millisecondsSinceEpoch);
        _lastHighlightsSyncSaved = _lastHighlightsSync;
      }
    } else if (category == 'notes') {
      if (_lastNotesSync != null) {
        await prefs.setInt(
            'lastNotesSync', _lastNotesSync!.millisecondsSinceEpoch);
        _lastNotesSyncSaved = _lastNotesSync;
      }
    } else if (category == 'history') {
      if (_lastHistorySync != null) {
        await prefs.setInt(
            'lastHistorySync', _lastHistorySync!.millisecondsSinceEpoch);
        _lastHistorySyncSaved = _lastHistorySync;
      }
    } else if (category == 'search_history') {
      if (_lastSearchHistorySync != null) {
        await prefs.setInt('lastSearchHistorySync',
            _lastSearchHistorySync!.millisecondsSinceEpoch);
        _lastSearchHistorySyncSaved = _lastSearchHistorySync;
      }
    }
  }

  /// Reset sync timestamps to force a full sync for specific data types.
  /// This is useful after importing data, as imported records may have
  /// updated_at timestamps older than the last sync time.
  ///
  /// [categories] - Set of category names to reset: 'highlights', 'notes', 'history', 'search_history'
  Future<void> resetSyncTimestampsForImport(Set<String> categories) async {
    final prefs = await SharedPreferences.getInstance();

    if (categories.contains('highlights')) {
      _lastHighlightsSync = null;
      _lastHighlightsSyncSaved = null;
      await prefs.remove('lastHighlightsSync');
    }
    if (categories.contains('notes')) {
      _lastNotesSync = null;
      _lastNotesSyncSaved = null;
      await prefs.remove('lastNotesSync');
    }
    if (categories.contains('history')) {
      _lastHistorySync = null;
      _lastHistorySyncSaved = null;
      await prefs.remove('lastHistorySync');
    }
    if (categories.contains('searchHistory') ||
        categories.contains('search_history')) {
      _lastSearchHistorySync = null;
      _lastSearchHistorySyncSaved = null;
      await prefs.remove('lastSearchHistorySync');
    }
  }

  // Sync status getter
  bool get isOnline => _syncStatus == SyncStatus.online;

  // Public streams for UI to listen to - auto-recreate controllers if closed
  static Stream<void> get highlightsChangedStream {
    if (_highlightsChangedController == null ||
        _highlightsChangedController!.isClosed) {
      _highlightsChangedController = StreamController<void>.broadcast();
    }
    return _highlightsChangedController!.stream;
  }

  static Stream<void> get notesChangedStream {
    if (_notesChangedController == null || _notesChangedController!.isClosed) {
      _notesChangedController = StreamController<void>.broadcast();
    }
    return _notesChangedController!.stream;
  }

  static Stream<void> get historyChangedStream {
    if (_historyChangedController == null ||
        _historyChangedController!.isClosed) {
      _historyChangedController = StreamController<void>.broadcast();
    }
    return _historyChangedController!.stream;
  }

  static Stream<void> get searchHistoryChangedStream {
    if (_searchHistoryChangedController == null ||
        _searchHistoryChangedController!.isClosed) {
      _searchHistoryChangedController = StreamController<void>.broadcast();
    }
    return _searchHistoryChangedController!.stream;
  }

  // Helper method to safely close a stream controller
  void _closeStreamController(StreamController<void>? controller) {
    if (controller != null && !controller.isClosed) {
      controller.close();
    }
  }

  // Cleanup all stream controllers before recreating them
  void _cleanupStreamControllers() {
    _closeStreamController(_highlightsChangedController);
    _closeStreamController(_notesChangedController);
    _closeStreamController(_historyChangedController);
    _closeStreamController(_searchHistoryChangedController);
    _highlightsChangedController = null;
    _notesChangedController = null;
    _historyChangedController = null;
    _searchHistoryChangedController = null;
  }

  // Load persisted change queues from SharedPreferences
  Future<void> _loadPersistedQueues() async {
    final prefs = await SharedPreferences.getInstance();

    // Clear in-memory queues to avoid duplicate loading after re-initialization.
    _highlightsPendingQueue.clear();
    _notesPendingQueue.clear();
    _historyPendingQueue.clear();
    _searchHistoryPendingQueue.clear();

    // Load and deserialize each queue
    final highlightsJson = prefs.getString(_highlightsQueueKey);
    if (highlightsJson != null) {
      try {
        final decoded = jsonDecode(highlightsJson) as List<dynamic>;
        _highlightsPendingQueue.addAll(decoded
            .map((op) => SyncOperation.fromMap(op as Map<String, dynamic>)));
      } catch (e) {
        // Invalid data, clear it
        await prefs.remove(_highlightsQueueKey);
      }
    }

    final notesJson = prefs.getString(_notesQueueKey);
    if (notesJson != null) {
      try {
        final decoded = jsonDecode(notesJson) as List<dynamic>;
        _notesPendingQueue.addAll(decoded
            .map((op) => SyncOperation.fromMap(op as Map<String, dynamic>)));
      } catch (e) {
        await prefs.remove(_notesQueueKey);
      }
    }

    final historyJson = prefs.getString(_historyQueueKey);
    if (historyJson != null) {
      try {
        final decoded = jsonDecode(historyJson) as List<dynamic>;
        _historyPendingQueue.addAll(decoded
            .map((op) => SyncOperation.fromMap(op as Map<String, dynamic>)));
      } catch (e) {
        await prefs.remove(_historyQueueKey);
      }
    }

    final searchHistoryJson = prefs.getString(_searchHistoryQueueKey);
    if (searchHistoryJson != null) {
      try {
        final decoded = jsonDecode(searchHistoryJson) as List<dynamic>;
        _searchHistoryPendingQueue.addAll(decoded
            .map((op) => SyncOperation.fromMap(op as Map<String, dynamic>)));
      } catch (e) {
        // Invalid data, clear it
        await prefs.remove(_searchHistoryQueueKey);
      }
    }
  }

  // Persist queues to SharedPreferences
  Future<void> _persistQueues() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_highlightsQueueKey,
        jsonEncode(_highlightsPendingQueue.map((op) => op.toMap()).toList()));
    await prefs.setString(_notesQueueKey,
        jsonEncode(_notesPendingQueue.map((op) => op.toMap()).toList()));
    await prefs.setString(_historyQueueKey,
        jsonEncode(_historyPendingQueue.map((op) => op.toMap()).toList()));
    await prefs.setString(
        _searchHistoryQueueKey,
        jsonEncode(
            _searchHistoryPendingQueue.map((op) => op.toMap()).toList()));
  }

  // Add operation to persistent queue by type (with enhanced deduplication)
  void _queueOperation(SyncOperation operation) {
    switch (operation.type) {
      case 'highlight':
        _processEnhancedDeduplication(
            operation, _highlightsPendingQueue, _matchesHighlight);
        break;
      case 'note':
        _processEnhancedDeduplication(
            operation, _notesPendingQueue, _matchesNote);
        break;
      case 'history':
        _processEnhancedDeduplication(
            operation, _historyPendingQueue, _matchesHistory);
        break;
      case 'search_history':
        _processEnhancedDeduplication(
            operation, _searchHistoryPendingQueue, _matchesSearchHistory);
        break;
    }
  }

  // Enhanced de-duplication logic that handles operation conflicts intelligently
  void _processEnhancedDeduplication(
      SyncOperation newOperation,
      List<SyncOperation> queue,
      bool Function(SyncOperation, SyncOperation) matcher) {
    // Find matching operations in queue
    final matchingIndices = <int>[];
    for (int i = 0; i < queue.length; i++) {
      if (matcher(queue[i], newOperation) &&
          queue[i].userId == newOperation.userId) {
        matchingIndices.add(i);
      }
    }

    if (matchingIndices.isEmpty) {
      // No matching operations - add new one
      queue.add(newOperation);
      return;
    }

    // Handle conflicts with existing operations
    for (final index in matchingIndices) {
      final existingOperation = queue[index];

      // Handle create + delete = cancel both operations
      if ((existingOperation.operation == 'create' &&
              newOperation.operation == 'delete') ||
          (existingOperation.operation == 'delete' &&
              newOperation.operation == 'create')) {
        // Remove both operations (cancel them out)
        queue.removeAt(index);
        return; // Both operations are cancelled
      }

      // Handle create + update = merge into updated create
      if ((existingOperation.operation == 'create' &&
              newOperation.operation == 'update') ||
          (existingOperation.operation == 'update' &&
              newOperation.operation == 'create')) {
        // Keep the more recent one with updated timestamp
        final updatedOperation = newOperation.copyWith(
            timestamp:
                newOperation.timestamp.isAfter(existingOperation.timestamp)
                    ? newOperation.timestamp
                    : existingOperation.timestamp);
        queue[index] = updatedOperation;
        return;
      }

      // Handle update + delete = convert to delete
      if ((existingOperation.operation == 'update' &&
              newOperation.operation == 'delete') ||
          (existingOperation.operation == 'delete' &&
              newOperation.operation == 'update')) {
        // Convert to delete operation with the most recent timestamp
        final deleteOperation = SyncOperation(
            id: newOperation.id,
            type: newOperation.type,
            operation: 'delete',
            data: newOperation.data,
            userId: newOperation.userId,
            timestamp:
                newOperation.timestamp.isAfter(existingOperation.timestamp)
                    ? newOperation.timestamp
                    : existingOperation.timestamp);
        queue[index] = deleteOperation;
        return;
      }

      // Handle delete + create = convert to create
      if ((existingOperation.operation == 'delete' &&
              newOperation.operation == 'create') ||
          (existingOperation.operation == 'create' &&
              newOperation.operation == 'delete')) {
        // Convert to create operation with the most recent timestamp
        final createOperation = SyncOperation(
            id: newOperation.id,
            type: newOperation.type,
            operation: 'create',
            data: newOperation.data,
            userId: newOperation.userId,
            timestamp:
                newOperation.timestamp.isAfter(existingOperation.timestamp)
                    ? newOperation.timestamp
                    : existingOperation.timestamp);
        queue[index] = createOperation;
        return;
      }

      // Handle update + create = keep the most recent
      if ((existingOperation.operation == 'update' &&
              newOperation.operation == 'create') ||
          (existingOperation.operation == 'create' &&
              newOperation.operation == 'update')) {
        final finalOperation =
            newOperation.timestamp.isAfter(existingOperation.timestamp)
                ? newOperation
                : existingOperation;
        queue[index] = finalOperation;
        return;
      }

      // Handle update + update = keep the most recent
      if (existingOperation.operation == 'update' &&
          newOperation.operation == 'update') {
        final updatedOperation =
            newOperation.timestamp.isAfter(existingOperation.timestamp)
                ? newOperation
                : existingOperation;
        queue[index] = updatedOperation;
        return;
      }

      // Handle delete + delete = keep only one delete
      if (existingOperation.operation == 'delete' &&
          newOperation.operation == 'delete') {
        // Remove the new delete since we already have one
        return;
      }

      // Handle create + create = keep the most recent
      if (existingOperation.operation == 'create' &&
          newOperation.operation == 'create') {
        final finalOperation =
            newOperation.timestamp.isAfter(existingOperation.timestamp)
                ? newOperation
                : existingOperation;
        queue[index] = finalOperation;
        return;
      }
    }
  }

  // Matching functions for each data type
  bool _matchesHighlight(SyncOperation op1, SyncOperation op2) {
    // Use uuid for comparison if both operations have it (for sync operations only)
    final uuid1 = op1.data['uuid'] as String?;
    final uuid2 = op2.data['uuid'] as String?;

    if (uuid1 != null &&
        uuid2 != null &&
        uuid1.isNotEmpty &&
        uuid2.isNotEmpty) {
      return uuid1 == uuid2;
    }

    // Fallback to existing comparison logic for non-sync or when uuid is not available
    return op1.type == 'highlight' &&
        op2.type == 'highlight' &&
        op1.data['book'] == op2.data['book'] &&
        op1.data['chapter'] == op2.data['chapter'] &&
        op1.data['verse'] == op2.data['verse'] &&
        op1.data['start'] == op2.data['start'] &&
        op1.data['end'] == op2.data['end'] &&
        op1.data['created_at'] == op2.data['created_at'];
  }

  bool _matchesNote(SyncOperation op1, SyncOperation op2) {
    // Use uuid for comparison if both operations have it (for sync operations only)
    final uuid1 = op1.data['uuid'] as String?;
    final uuid2 = op2.data['uuid'] as String?;

    if (uuid1 != null &&
        uuid2 != null &&
        uuid1.isNotEmpty &&
        uuid2.isNotEmpty) {
      return uuid1 == uuid2;
    }

    // Fallback to existing comparison logic for non-sync or when uuid is not available
    return op1.type == 'note' &&
        op2.type == 'note' &&
        op1.data['book'] == op2.data['book'] &&
        op1.data['chapter'] == op2.data['chapter'] &&
        op1.data['verse'] == op2.data['verse'] &&
        op1.data['created_at'] == op2.data['created_at'];
  }

  bool _matchesHistory(SyncOperation op1, SyncOperation op2) {
    // Use uuid for comparison if both operations have it (for sync operations only)
    final uuid1 = op1.data['uuid'] as String?;
    final uuid2 = op2.data['uuid'] as String?;

    if (uuid1 != null &&
        uuid2 != null &&
        uuid1.isNotEmpty &&
        uuid2.isNotEmpty) {
      return uuid1 == uuid2;
    }

    // Fallback to existing comparison logic for non-sync or when uuid is not available
    return op1.type == 'history' &&
        op2.type == 'history' &&
        op1.data['book'] == op2.data['book'] &&
        op1.data['chapter'] == op2.data['chapter'] &&
        op1.data['verse'] == op2.data['verse'] &&
        op1.data['timestamp'] == op2.data['timestamp'];
  }

  bool _matchesSearchHistory(SyncOperation op1, SyncOperation op2) {
    // Use uuid for comparison if both operations have it (for sync operations only)
    final uuid1 = op1.data['uuid'] as String?;
    final uuid2 = op2.data['uuid'] as String?;

    if (uuid1 != null &&
        uuid2 != null &&
        uuid1.isNotEmpty &&
        uuid2.isNotEmpty) {
      return uuid1 == uuid2;
    }

    // Fallback to existing comparison logic for non-sync or when uuid is not available
    return op1.type == 'search_history' &&
        op2.type == 'search_history' &&
        op1.data['query'] == op2.data['query'] &&
        op1.data['useRegex'] == op2.data['useRegex'] &&
        op1.data['useNearby'] == op2.data['useNearby'] &&
        op1.data['useWholeWord'] == op2.data['useWholeWord'] &&
        op1.data['useRedLetter'] == op2.data['useRedLetter'] &&
        op1.data['caseSensitive'] == op2.data['caseSensitive'] &&
        op1.data['bookFilterType'] == op2.data['bookFilterType'] &&
        op1.data['customBookFilter'] == op2.data['customBookFilter'] &&
        op1.data['timestamp'] == op2.data['timestamp'];
  }

  // Get current local data for an operation type - returns null if item no longer exists locally
  Future<Map<String, dynamic>?> _getCurrentLocalData(
      String type, Map<String, dynamic> operationData) async {
    switch (type) {
      case 'highlight':
        // Use uuid for lookup if available (for sync operations)
        final uuid = operationData['uuid'] as String?;
        if (uuid != null && uuid.isNotEmpty) {
          final localHighlights = await HighlightsDatabase.getHighlights();
          return localHighlights.where((h) => h['uuid'] == uuid).firstOrNull;
        }

        // Fallback to created_at timestamp
        final createdAt = operationData['created_at'] as int;
        final localHighlights = await HighlightsDatabase.getHighlights();
        return localHighlights
            .where((h) => h['created_at'] == createdAt)
            .firstOrNull;

      case 'note':
        // Use uuid for lookup if available (for sync operations)
        final uuid = operationData['uuid'] as String?;
        if (uuid != null && uuid.isNotEmpty) {
          final localNotes = await NotesDatabase.getNotes();
          return localNotes.where((n) => n['uuid'] == uuid).firstOrNull;
        }

        // Fallback to created_at timestamp
        final createdAt = operationData['created_at'] as int;
        final localNotes = await NotesDatabase.getNotes();
        return localNotes
            .where((n) => n['created_at'] == createdAt)
            .firstOrNull;

      case 'history':
        // Use uuid for lookup if available (for sync operations)
        final uuid = operationData['uuid'] as String?;
        if (uuid != null && uuid.isNotEmpty) {
          final localHistory = await HistoryDatabase.getHistory();
          return localHistory.where((h) => h['uuid'] == uuid).firstOrNull;
        }

        // Fallback to timestamp and book/chapter/verse
        final timestamp = operationData['timestamp'] as int;
        final book = operationData['book'] as String;
        final chapter = operationData['chapter'] as int;
        final verse = operationData['verse'] as int?;
        final localHistory = await HistoryDatabase.getHistory();
        return localHistory
            .where((h) =>
                h['timestamp'] == timestamp &&
                h['book'] == book &&
                h['chapter'] == chapter &&
                h['verse'] == verse)
            .firstOrNull;

      case 'search_history':
        // Use uuid for lookup if available (for sync operations)
        final uuid = operationData['uuid'] as String?;
        if (uuid != null && uuid.isNotEmpty) {
          final localSearchHistory = await SearchDatabase.getSearchHistory();
          return localSearchHistory.where((s) => s['uuid'] == uuid).firstOrNull;
        }

        // Fallback to exact match of all fields
        final timestamp = operationData['timestamp'] as int;
        final query = operationData['query'] as String;
        final useRegex = operationData['useRegex'] as bool?;
        final useNearby = operationData['useNearby'] as bool?;
        final useWholeWord = operationData['useWholeWord'] as bool?;
        final useRedLetter = operationData['useRedLetter'] as bool?;
        final caseSensitive = operationData['caseSensitive'] as bool?;
        final bookFilterType = operationData['bookFilterType'] as String?;
        final customBookFilter = operationData['customBookFilter'] as String?;

        final localSearchHistory = await SearchDatabase.getSearchHistory();
        return localSearchHistory
            .where((s) =>
                s['timestamp'] == timestamp &&
                s['query'] == query &&
                s['useRegex'] == useRegex &&
                s['useNearby'] == useNearby &&
                s['useWholeWord'] == useWholeWord &&
                s['useRedLetter'] == useRedLetter &&
                s['caseSensitive'] == caseSensitive &&
                s['bookFilterType'] == bookFilterType &&
                s['customBookFilter'] == customBookFilter)
            .firstOrNull;

      default:
        return null;
    }
  }

  // Queue a specific operation persistently (replaces old queuing methods)
  Future<void> _queuePersistentOperation(String operationKey, String type,
      String operation, Map<String, dynamic> data,
      {String? userId}) async {
    // Only queue operations when user is logged in but offline (can't sync immediately)
    final ownerId = userId ?? _currentUserId;
    if (ownerId == null) {
      return;
    }

    // Check if operation already exists to avoid duplicates
    final List<SyncOperation> existingOps;
    final DateTime operationTimestamp;
    switch (type) {
      case 'highlight':
        existingOps = _highlightsPendingQueue;
        operationTimestamp =
            DateTime.fromMillisecondsSinceEpoch(data['created_at'] as int);
        break;
      case 'note':
        existingOps = _notesPendingQueue;
        operationTimestamp =
            DateTime.fromMillisecondsSinceEpoch(data['created_at'] as int);
        break;
      case 'history':
        existingOps = _historyPendingQueue;
        operationTimestamp =
            DateTime.fromMillisecondsSinceEpoch(data['timestamp'] as int);
        break;
      case 'search_history':
        existingOps = _searchHistoryPendingQueue;
        operationTimestamp =
            DateTime.fromMillisecondsSinceEpoch(data['timestamp'] as int);
        break;
      default:
        operationTimestamp = DateTime.now();
        throw ArgumentError('Unknown operation type: $type');
    }

    // Don't add duplicate operations
    final isDuplicate = existingOps.any((op) =>
        op.id == operationKey &&
        op.operation == operation &&
        (op.userId ?? ownerId) == ownerId);
    if (isDuplicate) {
      return;
    }

    // Create and queue the operation
    final syncOperation = SyncOperation(
      id: operationKey,
      type: type,
      operation: operation,
      data: data,
      timestamp: operationTimestamp,
      userId: ownerId,
    );

    _queueOperation(syncOperation);
    await _persistQueues();
  }

  // Process persistent queues when coming online
  Future<void> _processPendingQueues() async {
    if (!isOnline ||
        _currentUserId == null ||
        !await InternetAccessChecker.hasInternetAccess()) {
      return;
    }

    // Process each queue for the current user only.
    await _processPendingQueue(_highlightsPendingQueue);
    await _processPendingQueue(_notesPendingQueue);
    await _processPendingQueue(_historyPendingQueue);
    await _processPendingQueue(_searchHistoryPendingQueue);

    // Persist queue updates.
    await _persistQueues();
  }

  // Flush in-memory retry queue and persistent queue after connectivity restoration.
  Future<void> _flushQueuedOperations() async {
    if (!isOnline || _currentUserId == null) return;

    // First, retry fast-fail operations that were attempted while status was stale.
    await _processRetryQueue();

    // Then process persisted offline queue.
    await _processPendingQueues();

    // Run retry queue once more in case anything was re-enqueued during processing.
    if (_retryQueue.isNotEmpty) {
      await _processRetryQueue();
    }
  }

  // Process a specific pending queue
  Future<void> _processPendingQueue(List<SyncOperation> queue) async {
    if (queue.isEmpty || _currentUserId == null) return;

    final queuedForOtherUsers = <SyncOperation>[];
    final operationsToProcess = <SyncOperation>[];

    for (final operation in queue) {
      final ownerId = operation.userId ?? _currentUserId;
      if (ownerId != _currentUserId) {
        queuedForOtherUsers.add(operation);
        continue;
      }

      // Backfill missing ownership metadata for legacy queued operations.
      operationsToProcess.add(operation.userId == ownerId
          ? operation
          : operation.copyWith(userId: ownerId));
    }

    queue
      ..clear()
      ..addAll(queuedForOtherUsers);

    for (final operation in operationsToProcess) {
      // Determine what data to upload - use current local data for create/update if exists
      Map<String, dynamic> uploadData = operation.data;

      if (operation.operation == 'create' || operation.operation == 'update') {
        final currentLocal =
            await _getCurrentLocalData(operation.type, operation.data);
        if (currentLocal == null) {
          // Item no longer exists locally - skip processing
          continue;
        }
        uploadData = currentLocal;
      }

      try {
        await _processSingleSyncOperation(operation, dataOverride: uploadData);
      } catch (e) {
        ErrorHandler.logError(
          e,
          customMessage: '_processPendingQueue failed - re-queueing operation',
          context: {
            'operationId': operation.id,
            'type': operation.type,
            'operation': operation.operation
          },
        );
        queue.add(
            operation.copyWith(userId: operation.userId ?? _currentUserId));
      }
    }
  }

  Future<void> _processSingleSyncOperation(SyncOperation operation,
      {Map<String, dynamic>? dataOverride}) async {
    final data = dataOverride ?? operation.data;

    switch (operation.type) {
      case 'highlight':
        if (operation.operation == 'create' ||
            operation.operation == 'update') {
          await _uploadHighlight(data);
        } else if (operation.operation == 'delete') {
          await deleteRemoteHighlight(data['created_at'] as int);
        } else {
          throw ArgumentError(
              'Unknown operation "${operation.operation}" for highlight');
        }
        break;
      case 'note':
        if (operation.operation == 'create' ||
            operation.operation == 'update') {
          await _uploadNote(data);
        } else if (operation.operation == 'delete') {
          await deleteRemoteNote(data['created_at'] as int);
        } else {
          throw ArgumentError(
              'Unknown operation "${operation.operation}" for note');
        }
        break;
      case 'history':
        if (operation.operation == 'create' ||
            operation.operation == 'update') {
          await _uploadHistoryItem(data);
        } else if (operation.operation == 'delete') {
          await deleteRemoteHistoryItem(data['timestamp'] as int);
        } else {
          throw ArgumentError(
              'Unknown operation "${operation.operation}" for history');
        }
        break;
      case 'search_history':
        if (operation.operation == 'create' ||
            operation.operation == 'update') {
          await _uploadSearchHistoryItem(data);
        } else if (operation.operation == 'delete') {
          await deleteRemoteSearchHistoryItem(data['timestamp'] as int);
        } else {
          throw ArgumentError(
              'Unknown operation "${operation.operation}" for search_history');
        }
        break;
      default:
        throw ArgumentError('Unknown operation type: ${operation.type}');
    }
  }

  // Initialize the sync service
  Future<void> initialize({bool isLoginResync = false}) async {
    if (_isInitialized) {
      return;
    }

    if (_currentUserId == null) {
      return;
    }

    // Cancel existing first
    _highlightsChannel?.unsubscribe();
    _notesChannel?.unsubscribe();
    _historyChannel?.unsubscribe();
    _searchHistoryChannel?.unsubscribe();
    _retryTimer?.cancel();

    // Check actual connectivity status and set appropriate initial state
    try {
      final hasConnection = await InternetAccessChecker.hasInternetAccess();
      if (hasConnection && _currentUserId != null) {
        _syncStatus =
            SyncStatus.online; // Connected and have user, assume online
      } else {
        _syncStatus = SyncStatus.offline; // No connection or no user
      }
    } catch (_) {
      _syncStatus = SyncStatus.offline; // On error, assume offline
    }

    syncStatusNotifier.value = _syncStatus;
    _isListening = false;

    // Initialize stream controllers to ensure they exist for immediate use
    _highlightsChangedController ??= StreamController<void>.broadcast();
    _notesChangedController ??= StreamController<void>.broadcast();
    _historyChangedController ??= StreamController<void>.broadcast();
    _searchHistoryChangedController ??= StreamController<void>.broadcast();

    // Load persisted last sync timestamps
    await _loadLastSyncTimestamps();

    // Load persisted change queues
    await _loadPersistedQueues();

    // Setup listeners and connection monitoring
    await _checkConnectionAndSetup();

    // Process any queued operations from offline or retry queues
    if (isOnline) {
      await _flushQueuedOperations();
    }

    // Perform full sync on login (download all remote + upload local changes)
    // if we are not resuming (switching from paused to resumed state on mobile)
    if (isLoginResync && _currentUserId != null && isOnline) {
      try {
        // Try to sync all
        await syncAll();
      } catch (e) {
        // If that fails sync what we can
        try {
          await syncHighlights();
        } catch (e) {
          ErrorHandler.logError(
            e,
            customMessage: 'syncHighlights() failed',
          );
        }
        try {
          await syncNotes();
        } catch (e) {
          ErrorHandler.logError(
            e,
            customMessage: 'syncNotes() failed',
          );
        }
        try {
          await syncHistory();
        } catch (e) {
          ErrorHandler.logError(
            e,
            customMessage: 'syncHistory() failed',
          );
        }
        try {
          await syncSearchHistory();
        } catch (e) {
          ErrorHandler.logError(
            e,
            customMessage: 'syncSearchHistory() failed',
          );
        }
      }
    } else if (!isLoginResync && _currentUserId != null && isOnline) {
      // App resume - do incremental sync to catch changes while backgrounded
      try {
        await syncRecentChangesOnly();
      } catch (e) {
        // Continue with init even if sync fails
      }
    }

    // Start connection monitoring
    try {
      _startConnectionMonitoring();
    } catch (e) {
      ErrorHandler.logError(
        e,
        customMessage: '_startConnectionMonitoring failed',
      );
    }

    // Cache the username after initialization
    if (_currentUserId != null) {
      await cacheUsername();
    }

    _isInitialized = true;
  }

  // Check connection and setup listeners
  Future<void> _checkConnectionAndSetup() async {
    try {
      final wasOnline = _syncStatus == SyncStatus.online;
      final hasConnection = await InternetAccessChecker.hasInternetAccess();

      if (hasConnection) {
        try {
          await _testSupabaseConnection();
          await _setupRealtimeListeners();
          _syncStatus = SyncStatus.online;
          syncStatusNotifier.value = _syncStatus;
          await _flushQueuedOperations();
          if (!wasOnline) {
            await syncRecentChangesOnly();
          }
        } catch (e) {
          // Connection test or setup failed - go offline but don't crash
          ErrorHandler.logError(
            e,
            customMessage: 'Connection setup failed',
          );
          _syncStatus = SyncStatus.offline;
          syncStatusNotifier.value = _syncStatus;
        }
      } else {
        _syncStatus = SyncStatus.offline;
        syncStatusNotifier.value = _syncStatus;
      }
    } catch (e) {
      // Connectivity check failed - assume offline
      ErrorHandler.logError(
        e,
        customMessage: 'Connectivity check failed',
      );
      _syncStatus = SyncStatus.offline;
      syncStatusNotifier.value = SyncStatus.offline;
    }
  }

  // Test Supabase connection
  Future<void> _testSupabaseConnection() async {
    if (_currentUserId == null) return;

    try {
      // First test DNS resolution
      final uri = Uri.parse(SupabaseConfig.supabaseUrl);
      try {
        uri.resolve('/');
      } catch (e) {
        throw Exception('DNS resolution failed: ${e.toString()}');
      }

      // Try to access user's profile
      try {
        final testQuery = _supabase
            .from('profiles')
            .select()
            .eq('id', _currentUserId!)
            .single();
        await testQuery;
      } catch (e) {
        // Handle specific Supabase errors that can occur during network restoration
        ErrorHandler.logError(
          e,
          customMessage: 'Supabase profile access failed',
        );
        rethrow;
      }
    } catch (e) {
      ErrorHandler.logError(
        e,
        customMessage: 'Supabase connection test failed',
      );
      rethrow;
    }
  }

  // Method 1: Try direct table access
  // void _tryDirectTableAccess() async {
  //   try {
  //     // Try to select from the table to see what happens
  //     final result =
  //         await _supabase.from('search_history').select('*').limit(1);
  //     if (kDebugMode) {
  //       debugPrint(
  //           'Direct table access: SUCCESS - Table exists, found ${result.length} rows');
  //     }
  //     if (result.isNotEmpty) {
  //       final columns = result.first.keys.toList();
  //       if (kDebugMode) debugPrint('Available columns: $columns');

  //       // Check for missing columns
  //       final requiredColumns = ['bookFilterType', 'customBookFilter'];
  //       final missingColumns =
  //           requiredColumns.where((col) => !columns.contains(col)).toList();
  //       if (missingColumns.isNotEmpty) {
  //         if (kDebugMode) debugPrint('MISSING COLUMNS: $missingColumns');
  //       } else {
  //         if (kDebugMode) debugPrint('All required columns present');
  //       }
  //     }
  //   } catch (e) {
  //     if (kDebugMode) debugPrint('Direct table access failed: ${e.toString()}');
  //     rethrow;
  //   }
  // }

  // Method 2: Try information schema access
  // void _tryInformationSchemaAccess() async {
  //   try {
  //     // Try to query information_schema.columns
  //     final result = await _supabase
  //         .from('information_schema.columns')
  //         .select('column_name, data_type, is_nullable')
  //         .eq('table_name', 'search_history');

  //     if (kDebugMode) debugPrint('Information schema access: SUCCESS');
  //     if (result.isNotEmpty) {
  //       final columns = result
  //           .map((col) => '${col['column_name']}:${col['data_type']}')
  //           .join(', ');
  //       if (kDebugMode) debugPrint('Table structure: $columns');
  //     } else {
  //       if (kDebugMode) debugPrint('No columns found - table may not exist');
  //     }
  //   } catch (e) {
  //     if (kDebugMode) {
  //       debugPrint('Information schema access failed: ${e.toString()}');
  //     }
  //     rethrow;
  //   }
  // }

  // Method 3: Try direct PostgreSQL query
  // void _tryPostgresQuery() async {
  //   try {
  //     // Use RPC to query the table structure
  //     final result = await _supabase
  //         .rpc('get_table_columns', params: {'table_name': 'search_history'});
  //     if (kDebugMode) debugPrint('PostgreSQL query access: SUCCESS');
  //     if (kDebugMode) debugPrint('RPC result: $result');
  //   } catch (e) {
  //     if (kDebugMode) {
  //       debugPrint('PostgreSQL query access failed: ${e.toString()}');
  //     }
  //     rethrow;
  //   }
  // }

  // Setup realtime listeners for user's data - only when all conditions are met
  Future<void> _setupRealtimeListeners() async {
    if (_currentUserId == null || _isListening) return;

    // Cancel existing listeners before setting up new ones
    _highlightsChannel?.unsubscribe();
    _notesChannel?.unsubscribe();
    _historyChannel?.unsubscribe();
    _searchHistoryChannel?.unsubscribe();

    _isListening = true;

    try {
      // Only setup listeners for enabled sync types
      final highlightsEnabled = await _getSyncEnabled('syncHighlights');
      final notesEnabled = await _getSyncEnabled('syncNotes');
      final historyEnabled = await _getSyncEnabled('syncHistory');
      final searchHistoryEnabled = await _getSyncEnabled('syncSearchHistory');

      // Listen for highlights changes if enabled
      if (highlightsEnabled) {
        try {
          _highlightsChannel = _supabase
              .channel('public:highlights')
              .onPostgresChanges(
                event: PostgresChangeEvent.all,
                schema: 'public',
                table: 'highlights',
                filter: PostgresChangeFilter(
                  type: PostgresChangeFilterType.eq,
                  column: 'user_id',
                  value: _currentUserId,
                ),
                callback: (PostgresChangePayload payload) {
                  _handleHighlightsChange(payload);
                },
              )
              .subscribe();
        } catch (e) {
          ErrorHandler.logError(
            e,
            customMessage: 'Failed to setup highlights listener',
            context: {'table': 'highlights'},
          );
          // Don't rethrow - continue with other listeners
        }
      }

      // Listen for notes changes if enabled
      if (notesEnabled) {
        try {
          _notesChannel = _supabase
              .channel('public:notes')
              .onPostgresChanges(
                event: PostgresChangeEvent.all,
                schema: 'public',
                table: 'notes',
                filter: PostgresChangeFilter(
                  type: PostgresChangeFilterType.eq,
                  column: 'user_id',
                  value: _currentUserId,
                ),
                callback: (PostgresChangePayload payload) {
                  _handleNotesChange(payload);
                },
              )
              .subscribe();
        } catch (e) {
          ErrorHandler.logError(
            e,
            customMessage: 'Failed to setup notes listener',
            context: {'table': 'notes'},
          );
          // Don't rethrow - continue with other listeners
        }
      }

      // Listen for history changes if enabled
      if (historyEnabled) {
        try {
          _historyChannel = _supabase
              .channel('public:history')
              .onPostgresChanges(
                event: PostgresChangeEvent.all,
                schema: 'public',
                table: 'history',
                filter: PostgresChangeFilter(
                  type: PostgresChangeFilterType.eq,
                  column: 'user_id',
                  value: _currentUserId,
                ),
                callback: (PostgresChangePayload payload) {
                  _handleHistoryChange(payload);
                },
              )
              .subscribe();
        } catch (e) {
          ErrorHandler.logError(
            e,
            customMessage: 'Failed to setup history listener',
            context: {'table': 'history'},
          );
          // Don't rethrow - continue with other listeners
        }
      }

      // Listen for search history changes if enabled
      if (searchHistoryEnabled) {
        try {
          _searchHistoryChannel = _supabase
              .channel('public:search_history')
              .onPostgresChanges(
                event: PostgresChangeEvent.all,
                schema: 'public',
                table: 'search_history',
                filter: PostgresChangeFilter(
                  type: PostgresChangeFilterType.eq,
                  column: 'user_id',
                  value: _currentUserId,
                ),
                callback: (PostgresChangePayload payload) {
                  _handleSearchHistoryChange(payload);
                },
              )
              .subscribe();
        } catch (e) {
          ErrorHandler.logError(
            e,
            customMessage: 'Failed to setup search history listener',
            context: {'table': 'search_history'},
          );
          // Don't rethrow - continue with other listeners
        }
      }
    } catch (e) {
      _isListening = false;
      ErrorHandler.logError(
        e,
        customMessage: 'Error setting up realtime listeners',
      );
      // Don't rethrow - let connectivity monitoring handle reconnection
    }
  }

  // Handle realtime subscription errors with automatic retry
  // void _handleRealtimeSubscriptionError(dynamic error, String tableName) async {
  //   try {
  //     // Log the error for debugging
  //     if (kDebugMode) {
  //       debugPrint(
  //           'Realtime subscription error for $tableName: ${error.toString()}');
  //     }

  //     // Enhanced context with operation details
  //     final context = {
  //       'table': tableName,
  //       'operation': 'realtime_subscription',
  //       'type': error.runtimeType.toString(),
  //       'timestamp': DateTime.now().toIso8601String(),
  //     };

  //     // Handle specific RealtimeSubscribeException
  //     if (error is RealtimeSubscribeException) {
  //       context['status'] = error.status.toString();
  //       context['details'] = error.details?.toString() ?? 'no details';
  //       await ErrorHandler.handleSyncError(error, context: context);

  //       // For channel errors, attempt to reconnect
  //       if (error.status == RealtimeSubscribeStatus.channelError) {
  //         await _retryRealtimeSubscription(tableName);
  //       }
  //     } else {
  //       // Handle other types of errors
  //       await ErrorHandler.handleSyncError(error, context: context);
  //     }
  //   } catch (e) {
  //     // Ensure we don't crash if error handling itself fails
  //     if (kDebugMode) {
  //       debugPrint(
  //           'Error handling realtime subscription error: ${e.toString()}');
  //     }
  //   }
  // }

  // Retry realtime subscription for a specific table
  // Future<void> _retryRealtimeSubscription(String tableName) async {
  //   try {
  //     // Wait before retrying to avoid rapid reconnection attempts
  //     await Future.delayed(Duration(seconds: syncRetryDelay1Seconds));

  //     // Check if we're still supposed to be listening and online
  //     if (!_isListening || !isOnline || _currentUserId == null) {
  //       return;
  //     }

  //     // Check if sync is enabled for this table
  //     final isEnabled = await _getSyncEnabled('sync$tableName');
  //     if (!isEnabled) {
  //       return;
  //     }

  //     if (kDebugMode) {
  //       debugPrint('Retrying realtime subscription for $tableName');
  //     }

  //     // Cancel existing subscription if it exists
  //     switch (tableName) {
  //       case 'highlights':
  //         _highlightsChannel?.unsubscribe();
  //         _highlightsChannel = null;
  //         break;
  //       case 'notes':
  //         _notesChannel?.unsubscribe();
  //         _notesChannel = null;
  //         break;
  //       case 'history':
  //         _historyChannel?.unsubscribe();
  //         _historyChannel = null;
  //         break;
  //       case 'search_history':
  //         _searchHistoryChannel?.unsubscribe();
  //         _searchHistoryChannel = null;
  //         break;
  //     }

  //     // Attempt to re-subscribe
  //     try {
  //       switch (tableName) {
  //         case 'highlights':
  //           _highlightsChannel = _supabase
  //               .channel('public:highlights')
  //               .onPostgresChanges(
  //                 event: PostgresChangeEvent.all,
  //                 schema: 'public',
  //                 table: 'highlights',
  //                 filter: PostgresChangeFilter(
  //                   type: PostgresChangeFilterType.eq,
  //                   column: 'user_id',
  //                   value: _currentUserId,
  //                 ),
  //                 callback: (PostgresChangePayload payload) {
  //                   _handleHighlightsChange(payload);
  //                 },
  //               )
  //               .subscribe();
  //           break;
  //         case 'notes':
  //           _notesChannel = _supabase
  //               .channel('public:notes')
  //               .onPostgresChanges(
  //                 event: PostgresChangeEvent.all,
  //                 schema: 'public',
  //                 table: 'notes',
  //                 filter: PostgresChangeFilter(
  //                   type: PostgresChangeFilterType.eq,
  //                   column: 'user_id',
  //                   value: _currentUserId,
  //                 ),
  //                 callback: (PostgresChangePayload payload) {
  //                   _handleNotesChange(payload);
  //                 },
  //               )
  //               .subscribe();
  //           break;
  //         case 'history':
  //           _historyChannel = _supabase
  //               .channel('public:history')
  //               .onPostgresChanges(
  //                 event: PostgresChangeEvent.all,
  //                 schema: 'public',
  //                 table: 'history',
  //                 filter: PostgresChangeFilter(
  //                   type: PostgresChangeFilterType.eq,
  //                   column: 'user_id',
  //                   value: _currentUserId,
  //                 ),
  //                 callback: (PostgresChangePayload payload) {
  //                   _handleHistoryChange(payload);
  //                 },
  //               )
  //               .subscribe();
  //           break;
  //         case 'search_history':
  //           _searchHistoryChannel = _supabase
  //               .channel('public:search_history')
  //               .onPostgresChanges(
  //                 event: PostgresChangeEvent.all,
  //                 schema: 'public',
  //                 table: 'search_history',
  //                 filter: PostgresChangeFilter(
  //                   type: PostgresChangeFilterType.eq,
  //                   column: 'user_id',
  //                   value: _currentUserId,
  //                 ),
  //                 callback: (PostgresChangePayload payload) {
  //                   _handleSearchHistoryChange(payload);
  //                 },
  //               )
  //               .subscribe();
  //           break;
  //       }

  //       if (kDebugMode) {
  //         debugPrint(
  //             'Successfully re-established realtime subscription for $tableName');
  //       }
  //     } catch (e) {
  //       if (kDebugMode) {
  //         debugPrint(
  //             'Failed to retry realtime subscription for $tableName: ${e.toString()}');
  //       }
  //       // If retry fails, let connectivity monitoring handle it
  //     }
  //   } catch (e) {
  //     if (kDebugMode) {
  //       debugPrint('Error in realtime subscription retry: ${e.toString()}');
  //     }
  //   }
  // }

  /// Update listener for a specific sync category without affecting others
  Future<void> updateListenerForCategory(
      String category, bool shouldEnable) async {
    if (_currentUserId == null || !isOnline || _isListening == false) return;

    switch (category) {
      case 'highlights':
        if (shouldEnable && _highlightsChannel == null) {
          // Setup highlights listener
          try {
            _highlightsChannel = _supabase
                .channel('public:highlights')
                .onPostgresChanges(
                  event: PostgresChangeEvent.all,
                  schema: 'public',
                  table: 'highlights',
                  filter: PostgresChangeFilter(
                    type: PostgresChangeFilterType.eq,
                    column: 'user_id',
                    value: _currentUserId,
                  ),
                  callback: (PostgresChangePayload payload) {
                    _handleHighlightsChange(payload);
                  },
                )
                .subscribe();
          } catch (e) {
            ErrorHandler.logError(
              e,
              customMessage: '_handleHighlightsChange exception',
            );
          }
        } else if (!shouldEnable && _highlightsChannel != null) {
          // Cancel highlights listener
          _highlightsChannel?.unsubscribe();
          _highlightsChannel = null;
        }
        break;

      case 'notes':
        if (shouldEnable && _notesChannel == null) {
          // Setup notes listener
          try {
            _notesChannel = _supabase
                .channel('public:notes')
                .onPostgresChanges(
                  event: PostgresChangeEvent.all,
                  schema: 'public',
                  table: 'notes',
                  filter: PostgresChangeFilter(
                    type: PostgresChangeFilterType.eq,
                    column: 'user_id',
                    value: _currentUserId,
                  ),
                  callback: (PostgresChangePayload payload) {
                    _handleNotesChange(payload);
                  },
                )
                .subscribe();
          } catch (e) {
            ErrorHandler.logError(
              e,
              customMessage: '_handleNotesChange exception',
            );
          }
        } else if (!shouldEnable && _notesChannel != null) {
          // Cancel notes listener
          _notesChannel?.unsubscribe();
          _notesChannel = null;
        }
        break;

      case 'history':
        if (shouldEnable && _historyChannel == null) {
          // Setup history listener
          try {
            _historyChannel = _supabase
                .channel('public:history')
                .onPostgresChanges(
                  event: PostgresChangeEvent.all,
                  schema: 'public',
                  table: 'history',
                  filter: PostgresChangeFilter(
                    type: PostgresChangeFilterType.eq,
                    column: 'user_id',
                    value: _currentUserId,
                  ),
                  callback: (PostgresChangePayload payload) {
                    _handleHistoryChange(payload);
                  },
                )
                .subscribe();
          } catch (e) {
            ErrorHandler.logError(
              e,
              customMessage: '_handleHistoryChange exception',
            );
          }
        } else if (!shouldEnable && _historyChannel != null) {
          // Cancel history listener
          _historyChannel?.unsubscribe();
          _historyChannel = null;
        }
        break;

      case 'search_history':
        if (shouldEnable && _searchHistoryChannel == null) {
          // Setup search history listener
          try {
            _searchHistoryChannel = _supabase
                .channel('public:search_history')
                .onPostgresChanges(
                  event: PostgresChangeEvent.all,
                  schema: 'public',
                  table: 'search_history',
                  filter: PostgresChangeFilter(
                    type: PostgresChangeFilterType.eq,
                    column: 'user_id',
                    value: _currentUserId,
                  ),
                  callback: (PostgresChangePayload payload) {
                    _handleSearchHistoryChange(payload);
                  },
                )
                .subscribe();
          } catch (e) {
            ErrorHandler.logError(
              e,
              customMessage: '_handleSearchHistoryChange exception',
            );
          }
        } else if (!shouldEnable && _searchHistoryChannel != null) {
          // Cancel search history listener
          _searchHistoryChannel?.unsubscribe();
          _searchHistoryChannel = null;
        }
        break;
      default:
    }
  }

  // Handle highlights changes from Supabase realtime using onPostgresChanges
  void _handleHighlightsChange(PostgresChangePayload payload) async {
    try {
      // Check if highlights sync is enabled
      final highlightsEnabled = await _getSyncEnabled('syncHighlights');

      if (!highlightsEnabled) {
        return;
      }

      // Handle different event types
      switch (payload.eventType) {
        case PostgresChangeEvent.insert:
        case PostgresChangeEvent.update:
          // Convert to List format expected by _downloadHighlights
          final data = [payload.newRecord];
          await _downloadHighlights(data);
          break;
        case PostgresChangeEvent.delete:
          // Handle deletion by removing from local database
          final deletedRecord = payload.oldRecord;

          // Use uuid to find and delete the local record (only data available from Supabase realtime with RLS)
          final uuid =
              deletedRecord['id'] as String?; // Supabase returns id as UUID

          if (uuid != null && uuid.isNotEmpty) {
            // Use uuid to find and delete the local record
            final localHighlights = await HighlightsDatabase.getHighlights();

            final highlightToDelete = localHighlights.firstWhere(
                (h) => h['uuid'] == uuid,
                orElse: () => <String, dynamic>{});
            if (highlightToDelete.isNotEmpty) {
              await HighlightsDatabase.deleteHighlight(
                  highlightToDelete['id'] as int,
                  skipSync: true);
              LocalDataChangeNotifier.notifyHighlightsChanged();
              _highlightsChangedController?.add(null);
            } else if (kDebugMode) {
              debugPrint(
                  'Realtime highlight delete could not match local UUID: $uuid');
            }
          } else if (kDebugMode) {
            debugPrint('Realtime highlight delete payload missing UUID.');
          }
          break;
        default:
      }
    } catch (e) {
      // Handle sync errors gracefully without throwing unhandled exceptions
      await ErrorHandler.handleSyncError(e, context: {
        'operation': 'handle_highlights_change',
        'type': 'realtime_handler',
        'error_type': e.runtimeType.toString(),
      });
      // Don't rethrow - let the app continue working offline
    }
  }

  // Handle notes changes from Supabase realtime using onPostgresChanges
  void _handleNotesChange(PostgresChangePayload payload) async {
    try {
      // Check if notes sync is enabled
      final notesEnabled = await _getSyncEnabled('syncNotes');

      if (!notesEnabled) {
        return;
      }

      // Handle different event types
      switch (payload.eventType) {
        case PostgresChangeEvent.insert:
        case PostgresChangeEvent.update:
          // Convert to List format expected by _downloadNotes
          final data = [payload.newRecord];
          await _downloadNotes(data);
          break;
        case PostgresChangeEvent.delete:
          // Handle deletion by removing from local database
          final deletedRecord = payload.oldRecord;

          // Use uuid to find and delete the local record (only data available from Supabase realtime with RLS)
          final uuid =
              deletedRecord['id'] as String?; // Supabase returns id as UUID

          if (uuid != null && uuid.isNotEmpty) {
            // Use uuid to find and delete the local record
            final localNotes = await NotesDatabase.getNotes();
            final noteToDelete = localNotes.firstWhere((n) => n['uuid'] == uuid,
                orElse: () => <String, dynamic>{});
            if (noteToDelete.isNotEmpty) {
              await NotesDatabase.deleteNote(noteToDelete['id'] as int,
                  skipSync: true);
              LocalDataChangeNotifier.notifyNotesChanged();
              _notesChangedController?.add(null);
            } else if (kDebugMode) {
              debugPrint(
                  'Realtime note delete could not match local UUID: $uuid');
            }
          } else if (kDebugMode) {
            debugPrint('Realtime note delete payload missing UUID.');
          }
          break;
        default:
      }
    } catch (e) {
      // Handle sync errors gracefully without throwing unhandled exceptions
      await ErrorHandler.handleSyncError(e, context: {
        'operation': 'handle_notes_change',
        'type': 'realtime_handler',
        'error_type': e.runtimeType.toString(),
      });
      // Don't rethrow - let the app continue working offline
    }
  }

  // Handle history changes from Supabase realtime using onPostgresChanges
  void _handleHistoryChange(PostgresChangePayload payload) async {
    try {
      // Check if history sync is enabled
      final historyEnabled = await _getSyncEnabled('syncHistory');

      if (!historyEnabled) {
        return;
      }

      // Handle different event types
      switch (payload.eventType) {
        case PostgresChangeEvent.insert:
        case PostgresChangeEvent.update:
          // Convert to List format expected by _downloadHistory
          final data = [payload.newRecord];
          await _downloadHistory(data);
          break;
        case PostgresChangeEvent.delete:
          // Handle deletion by removing from local database
          final deletedRecord = payload.oldRecord;

          // Use uuid to find and delete the local record (only data available from Supabase realtime with RLS)
          final uuid =
              deletedRecord['id'] as String?; // Supabase returns id as UUID

          if (uuid != null && uuid.isNotEmpty) {
            // Use uuid to find and delete the local record
            final localHistory = await HistoryDatabase.getHistory();
            final historyToDelete = localHistory.firstWhere(
                (h) => h['uuid'] == uuid,
                orElse: () => <String, dynamic>{});
            if (historyToDelete.isNotEmpty) {
              await HistoryDatabase.deleteHistoryItem(
                  historyToDelete['id'] as int,
                  skipSync: true);
              LocalDataChangeNotifier.notifyHistoryChanged();
              _historyChangedController?.add(null);
            } else if (kDebugMode) {
              debugPrint(
                  'Realtime history delete could not match local UUID: $uuid');
            }
          } else if (kDebugMode) {
            debugPrint('Realtime history delete payload missing UUID.');
          }
          break;
        default:
      }
    } catch (e) {
      // Handle sync errors gracefully without throwing unhandled exceptions
      await ErrorHandler.handleSyncError(e, context: {
        'operation': 'handle_history_change',
        'type': 'realtime_handler',
        'error_type': e.runtimeType.toString(),
      });
      // Don't rethrow - let the app continue working offline
    }
  }

  // Handle search history changes from Supabase realtime using onPostgresChanges
  void _handleSearchHistoryChange(PostgresChangePayload payload) async {
    try {
      // Check if search history sync is enabled
      final searchHistoryEnabled = await _getSyncEnabled('syncSearchHistory');

      if (!searchHistoryEnabled) {
        return;
      }

      // Handle different event types
      switch (payload.eventType) {
        case PostgresChangeEvent.insert:
        case PostgresChangeEvent.update:
          // Convert to List format expected by _downloadSearchHistory
          final data = [payload.newRecord];
          await _downloadSearchHistory(data);
          break;
        case PostgresChangeEvent.delete:
          // Handle deletion by removing from local database
          final deletedRecord = payload.oldRecord;

          // Try to use uuid first (from Supabase), fall back to timestamp
          final uuid =
              deletedRecord['id'] as String?; // Supabase returns id as UUID

          if (uuid != null && uuid.isNotEmpty) {
            // Use uuid to find and delete the local record (only data available from Supabase realtime with RLS)
            final localSearchHistory = await SearchDatabase.getSearchHistory();
            final searchHistoryToDelete = localSearchHistory.firstWhere(
                (s) => s['uuid'] == uuid,
                orElse: () => <String, dynamic>{});
            if (searchHistoryToDelete.isNotEmpty) {
              await SearchDatabase.deleteSearchHistoryItem(
                  searchHistoryToDelete['id'] as int,
                  skipSync: true);
              LocalDataChangeNotifier.notifySearchHistoryChanged();
              _searchHistoryChangedController?.add(null);
            } else if (kDebugMode) {
              debugPrint(
                  'Realtime search_history delete could not match local UUID: $uuid');
            }
          } else if (kDebugMode) {
            debugPrint('Realtime search_history delete payload missing UUID.');
          }
          break;
        default:
      }
    } catch (e) {
      // Handle sync errors gracefully without throwing unhandled exceptions
      await ErrorHandler.handleSyncError(e, context: {
        'operation': 'handle_search_history_change',
        'type': 'realtime_handler',
        'error_type': e.runtimeType.toString(),
      });
      // Don't rethrow - let the app continue working offline
    }
  }

  // Handle notes changes from Supabase realtime
  // void _onNotesChanged(List<Map<String, dynamic>> data) async {
  //   try {
  //     // Check if notes sync is enabled
  //     final notesEnabled = await _getSyncEnabled('syncNotes');

  //     if (!notesEnabled) {
  //       return;
  //     }

  //     await _downloadNotes(data);
  //   } catch (e) {
  //     // Handle sync errors gracefully without throwing unhandled exceptions
  //     await ErrorHandler.handleSyncError(e, context: {
  //       'operation': 'download_notes',
  //       'type': 'realtime_handler',
  //       'error_type': e.runtimeType.toString(),
  //     });
  //     // Don't rethrow - let the app continue working offline
  //   }
  // }

  // Handle history changes from Supabase realtime
  // void _onHistoryChanged(List<Map<String, dynamic>> data) async {
  //   try {
  //     // Check if history sync is enabled
  //     final historyEnabled = await _getSyncEnabled('syncHistory');

  //     if (!historyEnabled) {
  //       return;
  //     }

  //     await _downloadHistory(data);
  //   } catch (e) {
  //     // Handle sync errors gracefully without throwing unhandled exceptions
  //     await ErrorHandler.handleSyncError(e, context: {
  //       'operation': 'download_history',
  //       'type': 'realtime_handler',
  //       'error_type': e.runtimeType.toString(),
  //     });
  //     // Don't rethrow - let the app continue working offline
  //   }
  // }

  // Handle search history changes from Supabase realtime
  // void _onSearchHistoryChanged(List<Map<String, dynamic>> data) async {
  //   try {
  //     // Check if search history sync is enabled
  //     final searchHistoryEnabled = await _getSyncEnabled('syncSearchHistory');

  //     if (!searchHistoryEnabled) {
  //       return;
  //     }

  //     await _downloadSearchHistory(data);
  //   } catch (e) {
  //     // Handle sync errors gracefully without throwing unhandled exceptions
  //     await ErrorHandler.handleSyncError(e, context: {
  //       'operation': 'download_search_history',
  //       'type': 'realtime_handler',
  //       'error_type': e.runtimeType.toString(),
  //     });
  //     // Don't rethrow - let the app continue working offline
  //   }
  // }

  // Sync highlights to Supabase
  Future<void> syncHighlights() async {
    // Check if highlights sync is enabled
    final highlightsEnabled = await _getSyncEnabled('syncHighlights');

    if (!highlightsEnabled) {
      return;
    }

    if (_currentUserId == null) {
      return;
    }

    if (_syncStatus == SyncStatus.offline) {
      return;
    }

    try {
      // Always perform bi-directional sync regardless of local changes
      // Upload local changes first
      final baselineTime =
          _lastHighlightsSync ?? DateTime.fromMillisecondsSinceEpoch(0);

      // Get local highlights - all for sync logic
      final localHighlights = await HighlightsDatabase.getHighlights();

      // Filter for recent changes if not forced
      final highlightsToSync = localHighlights
          .where((h) =>
              (h['updated_at'] ?? h['created_at'] ?? 0) >
              baselineTime.millisecondsSinceEpoch)
          .toList();

      // Upload local changes
      if (highlightsToSync.isNotEmpty) {
        // Get remote highlights for comparison
        final remoteHighlights = await _fetchRemoteRows(
          table: 'highlights',
          orderColumn: 'created_at',
        );

        // Sync logic: collect highlights that need uploading
        final highlightsToUpload = <Map<String, dynamic>>[];

        for (final highlight in highlightsToSync) {
          final highlightId = highlight['created_at'];
          final remoteDoc = remoteHighlights
              .where((h) => h['created_at'] == highlightId)
              .firstOrNull;

          if (remoteDoc == null) {
            // New highlight - needs upload
            highlightsToUpload.add(highlight);
          } else {
            // Check if local is newer
            final localTime =
                highlight['updated_at'] ?? highlight['created_at'] ?? 0;
            final remoteTime =
                remoteDoc['updated_at'] ?? remoteDoc['created_at'] ?? 0;

            if (localTime > remoteTime) {
              highlightsToUpload.add(highlight);
            }
          }
        }

        // Upload highlights
        if (highlightsToUpload.isNotEmpty) {
          try {
            await _batchUploadHighlights(highlightsToUpload);
          } catch (e) {
            ErrorHandler.logError(
              e,
              customMessage: '_batchUploadHighlights exception',
            );
            // If batch upload fails, queue each operation individually for retry
            for (final highlight in highlightsToUpload) {
              _enqueueFailedOperation(SyncOperation(
                id: highlight['created_at'],
                type: 'highlight',
                operation: 'create',
                data: highlight,
                timestamp: DateTime.fromMillisecondsSinceEpoch(
                    highlight['created_at'] as int),
                userId: _currentUserId,
              ));
            }
          }
        }
      }

      // Download remote changes newer than last sync for bidirectional sync
      final lastSyncMs = _lastHighlightsSyncSaved?.millisecondsSinceEpoch ?? 0;
      final snapshot = await _fetchRemoteRows(
        table: 'highlights',
        orderColumn: 'updated_at',
        secondaryOrderColumn: 'created_at',
        greaterThanColumn: 'updated_at',
        greaterThanValue: lastSyncMs,
      );
      if (snapshot.isNotEmpty) {
        await _downloadHighlights(snapshot);
      }

      // Detect remote deletions
      await _detectRemoteDeletions('highlight');

      // Always update the sync timestamp after sync operations (both upload and download)
      _lastHighlightsSync = DateTime.now();

      // Save timestamps to preferences - only for highlights
      await _saveLastSyncTimestamps('highlights');
    } catch (e) {
      ErrorHandler.logError(
        e,
        customMessage: 'syncHighlights exception',
      );
    }
  }

  // Download highlights from Supabase to local database
  Future<void> _downloadHighlights(List<Map<String, dynamic>> docs) async {
    try {
      bool hasChanges = false;
      int processedCount = 0;

      final localHighlights = await HighlightsDatabase.getHighlights();
      final localByCreatedAt = <int, Map<String, dynamic>>{
        for (final highlight in localHighlights)
          highlight['created_at'] as int: Map<String, dynamic>.from(highlight),
      };

      for (final data in docs) {
        // Validate data before processing
        if (!await DataValidation.validateHighlightData(data,
            context: 'download highlight')) {
          // Delete corrupt remote document
          final docId = data['created_at'] as int;

          await deleteRemoteHighlight(docId);
          if (kDebugMode) {
            debugPrint(
                '_downloadHighlights: data validation failure detected: ${data.toString()}');
          }
          continue; // Skip processing this document
        }

        final remoteTime = data['updated_at'] as int;
        final remoteCreatedAt = data['created_at'] as int;
        final remoteUuid = data['id'] as String?;

        final localHighlight = localByCreatedAt[remoteCreatedAt];
        final localTime = (localHighlight?['updated_at'] ??
            localHighlight?['created_at'] ??
            0) as int;
        final shouldApplyRemote =
            localHighlight == null || remoteTime > localTime;
        final shouldRepairUuid = remoteUuid != null &&
            remoteUuid.isNotEmpty &&
            (localHighlight == null ||
                (localHighlight['uuid'] as String?) != remoteUuid);

        if (shouldApplyRemote || shouldRepairUuid) {
          final highlightToPersist = shouldApplyRemote
              ? {
                  'book': data['book'] as String,
                  'chapter': data['chapter'] as int,
                  'verse': data['verse'] as int,
                  'start': data['start'] as int,
                  'end': data['end'] as int,
                  'color': data['color'] as int,
                  'created_at': remoteCreatedAt,
                  'updated_at': remoteTime,
                  'uuid': remoteUuid,
                }
              : {
                  'book': localHighlight['book'] as String,
                  'chapter': localHighlight['chapter'] as int,
                  'verse': localHighlight['verse'] as int,
                  'start': localHighlight['start'] as int,
                  'end': localHighlight['end'] as int,
                  'color': localHighlight['color'] as int,
                  'created_at': localHighlight['created_at'] as int,
                  'updated_at': localTime,
                  'uuid': remoteUuid,
                };

          final localId = await HighlightsDatabase.upsertHighlightFromSync(
            book: highlightToPersist['book'] as String,
            chapter: highlightToPersist['chapter'] as int,
            verse: highlightToPersist['verse'] as int,
            start: highlightToPersist['start'] as int,
            end: highlightToPersist['end'] as int,
            color: highlightToPersist['color'] as int,
            createdAt: highlightToPersist['created_at'] as int,
            updatedAt: highlightToPersist['updated_at'] as int,
            uuid: highlightToPersist['uuid'] as String?,
          );
          localByCreatedAt[remoteCreatedAt] = {
            ...highlightToPersist,
            'id': localId,
          };
          hasChanges = true;
          processedCount++;
        }
      }

      // Only notify if there were actual changes
      if (hasChanges && processedCount > 0) {
        // Notify UI that highlights have been updated
        LocalDataChangeNotifier.notifyHighlightsChanged();
        // Also notify SupabaseSyncService stream listeners (for remote sync notifications)
        _highlightsChangedController?.add(null);
      }
    } catch (e) {
      await ErrorHandler.handleSyncError(e, context: {
        'operation': 'download_highlights_batch',
        'type': 'data_sync',
        'error_type': e.runtimeType.toString(),
      });
    }
  }

  // Download notes from Supabase to local database
  Future<void> _downloadNotes(List<Map<String, dynamic>> docs) async {
    try {
      bool hasChanges = false;
      int processedCount = 0;
      final localNotes = await NotesDatabase.getNotes();
      final localByCreatedAt = <int, Map<String, dynamic>>{
        for (final note in localNotes)
          note['created_at'] as int: Map<String, dynamic>.from(note),
      };
      final localByVerse = <String, Map<String, dynamic>>{
        for (final note in localNotes)
          '${note['book']}:${note['chapter']}:${note['verse']}':
              Map<String, dynamic>.from(note),
      };

      for (final data in docs) {
        // Validate data before processing
        if (!await DataValidation.validateNoteData(data,
            context: 'download note')) {
          // Delete corrupt remote document
          final docId = data['created_at'] as int;

          await deleteRemoteNote(docId);
          if (kDebugMode) {
            debugPrint(
                '_downloadNotes: data validation failure detected: ${data.toString()}');
          }
          continue; // Skip processing this document
        }

        final remoteTime =
            (data['updated_at'] ?? data['created_at'] ?? 0) as int;

        // For notes, check by verse location since database uses book/chapter/verse
        final book = data['book'] as String;
        final chapter = data['chapter'] as int;
        final verse = data['verse'] as int;
        final noteText =
            NoteStorageFormat.ensureDeltaFormat(data['note_text'] as String);
        final createdAt = data['created_at'] as int;
        final remoteUuid = data['id'] as String?;
        final verseKey = '$book:$chapter:$verse';

        final localNote = localByCreatedAt[createdAt] ?? localByVerse[verseKey];
        final localTime =
            (localNote?['updated_at'] ?? localNote?['created_at'] ?? 0) as int;
        final shouldApplyRemote = localNote == null || remoteTime > localTime;
        final shouldRepairUuid = remoteUuid != null &&
            remoteUuid.isNotEmpty &&
            localNote != null &&
            (localNote['uuid'] as String?) != remoteUuid;

        if (shouldApplyRemote || shouldRepairUuid) {
          final noteToPersist = shouldApplyRemote
              ? {
                  'book': book,
                  'chapter': chapter,
                  'verse': verse,
                  'note_text': noteText,
                  'created_at': createdAt,
                  'updated_at': remoteTime,
                  'uuid': remoteUuid,
                }
              : {
                  'book': localNote['book'] as String,
                  'chapter': localNote['chapter'] as int,
                  'verse': localNote['verse'] as int,
                  'note_text': localNote['note_text'] as String,
                  'created_at': localNote['created_at'] as int,
                  'updated_at': localTime,
                  'uuid': remoteUuid,
                };

          final localId = await NotesDatabase.upsertNoteFromSync(
            book: noteToPersist['book'] as String,
            chapter: noteToPersist['chapter'] as int,
            verse: noteToPersist['verse'] as int,
            noteText: noteToPersist['note_text'] as String,
            createdAt: noteToPersist['created_at'] as int,
            updatedAt: noteToPersist['updated_at'] as int,
            uuid: noteToPersist['uuid'] as String?,
          );
          localByCreatedAt[noteToPersist['created_at'] as int] = {
            ...noteToPersist,
            'id': localId,
          };
          localByVerse[verseKey] = {
            ...noteToPersist,
            'id': localId,
          };
          hasChanges = true;
          processedCount++;
        }
      }

      // Only notify if there were actual changes
      if (hasChanges && processedCount > 0) {
        // Notify UI that notes have been updated
        LocalDataChangeNotifier.notifyNotesChanged();
        // Also notify SupabaseSyncService stream listeners (for remote sync notifications)
        _notesChangedController?.add(null);
      }
    } catch (e) {
      await ErrorHandler.handleSyncError(e, context: {
        'operation': 'download_notes_batch',
        'type': 'data_sync',
        'error_type': e.runtimeType.toString(),
      });
    }
  }

  // Download history from Supabase to local database
  Future<void> _downloadHistory(List<Map<String, dynamic>> docs) async {
    try {
      final localHistory = await HistoryDatabase.getHistory();
      final localByTimestamp = <int, Map<String, dynamic>>{
        for (final historyItem in localHistory)
          historyItem['timestamp'] as int:
              Map<String, dynamic>.from(historyItem),
      };

      bool hasChanges = false;
      int processedCount = 0;

      for (final data in docs) {
        // Validate data before processing
        if (!await DataValidation.validateHistoryData(data,
            context: 'download history')) {
          // Delete corrupt remote document
          final docId = data['timestamp'];
          await deleteRemoteHistoryItem(docId);
          if (kDebugMode) {
            debugPrint(
                '_downloadHistory: data validation failure detected: ${data.toString()}');
          }
          continue; // Skip processing this document
        }

        final remoteTime = (data['timestamp'] ?? 0) as int;
        final remoteUuid = data['id'] as String?;
        final localHistoryItem = localByTimestamp[remoteTime];
        final shouldUpsert = localHistoryItem == null ||
            (remoteUuid != null &&
                remoteUuid.isNotEmpty &&
                (localHistoryItem['uuid'] as String?) != remoteUuid) ||
            localHistoryItem['book'] != data['book'] ||
            localHistoryItem['chapter'] != data['chapter'] ||
            localHistoryItem['verse'] != data['verse'];

        if (shouldUpsert) {
          await HistoryDatabase.upsertHistoryFromSync(
            data['book'] as String,
            data['chapter'] as int,
            data['verse'] as int?,
            remoteTime,
            uuid: remoteUuid,
          );
          localByTimestamp[remoteTime] = {
            'book': data['book'],
            'chapter': data['chapter'],
            'verse': data['verse'],
            'timestamp': remoteTime,
            'uuid': remoteUuid,
          };
          hasChanges = true;
          processedCount++;
        }
      }

      // Only notify if there were actual changes
      if (hasChanges && processedCount > 0) {
        // Notify UI that history has been updated (though not used in BibleScreen)
        LocalDataChangeNotifier.notifyHistoryChanged();
        // Also notify SupabaseSyncService stream listeners (for remote sync notifications)
        _historyChangedController?.add(null);
      }
    } catch (e) {
      await ErrorHandler.handleSyncError(e, context: {
        'operation': 'download_history_batch',
        'type': 'data_sync',
        'error_type': e.runtimeType.toString(),
      });
    }
  }

  // Download search history from Supabase to local database
  Future<void> _downloadSearchHistory(List<Map<String, dynamic>> docs) async {
    try {
      final localSearchHistory = await SearchDatabase.getSearchHistory();
      final localByTimestamp = <int, Map<String, dynamic>>{
        for (final item in localSearchHistory)
          item['timestamp'] as int: Map<String, dynamic>.from(item),
      };

      bool hasChanges = false;
      int processedCount = 0;

      for (final data in docs) {
        // Validate data before processing
        if (!await DataValidation.validateSearchHistoryData(data,
            context: 'download search_history')) {
          // Delete corrupt remote document
          final docId = data['timestamp'];
          await deleteRemoteSearchHistoryItem(docId);
          if (kDebugMode) {
            debugPrint(
                '_downloadSearchHistory: data validation failure detected: ${data.toString()}');
          }
          continue; // Skip processing this document
        }

        final remoteTime = (data['timestamp'] ?? 0) as int;
        final remoteUuid = data['id'] as String?;
        final localSearchHistoryItem = localByTimestamp[remoteTime];
        final shouldUpsert = localSearchHistoryItem == null ||
            (remoteUuid != null &&
                remoteUuid.isNotEmpty &&
                (localSearchHistoryItem['uuid'] as String?) != remoteUuid) ||
            localSearchHistoryItem['query'] != data['query'] ||
            localSearchHistoryItem['useRegex'] != data['useRegex'] ||
            localSearchHistoryItem['useNearby'] != data['useNearby'] ||
            localSearchHistoryItem['useWholeWord'] != data['useWholeWord'] ||
            localSearchHistoryItem['useRedLetter'] != data['useRedLetter'] ||
            localSearchHistoryItem['caseSensitive'] != data['caseSensitive'] ||
            localSearchHistoryItem['bookFilterType'] !=
                data['bookFilterType'] ||
            localSearchHistoryItem['customBookFilter'] !=
                data['customBookFilter'];

        if (shouldUpsert) {
          try {
            await SearchDatabase.upsertSearchHistoryFromSync(
              data['query'] as String,
              data['useRegex'] as bool,
              data['useNearby'] as bool,
              data['useWholeWord'] as bool,
              data['useRedLetter'] as bool,
              data['caseSensitive'] as bool,
              data['bookFilterType'] as String,
              data['customBookFilter'] as String,
              remoteTime,
              uuid: remoteUuid,
            );
            localByTimestamp[remoteTime] = {
              'query': data['query'],
              'useRegex': data['useRegex'],
              'useNearby': data['useNearby'],
              'useWholeWord': data['useWholeWord'],
              'useRedLetter': data['useRedLetter'],
              'caseSensitive': data['caseSensitive'],
              'bookFilterType': data['bookFilterType'],
              'customBookFilter': data['customBookFilter'],
              'timestamp': remoteTime,
              'uuid': remoteUuid,
            };
            hasChanges = true;
            processedCount++;
          } catch (e) {
            ErrorHandler.logError(
              e,
              customMessage:
                  '_downloadSearchHistory upsertSearchHistoryFromSync exception',
            );
          }
        }
      }

      // Only notify if there were actual changes
      if (hasChanges && processedCount > 0) {
        // Notify UI that search history has been updated
        LocalDataChangeNotifier.notifySearchHistoryChanged();
        // Also notify SupabaseSyncService stream listeners (for remote sync notifications)
        _searchHistoryChangedController?.add(null);
      }
    } catch (e) {
      await ErrorHandler.handleSyncError(e, context: {
        'operation': 'download_search_history_batch',
        'type': 'data_sync',
        'error_type': e.runtimeType.toString(),
      });
    }
  }

  // Detect remote deletions by comparing local UUIDs with remote UUIDs
  Future<_SyncReconciliationSnapshot> _buildReconciliationSnapshot(
      String type) async {
    final naturalKeyColumn = _getNaturalKeyColumn(type);

    final remoteResponse = await _fetchRemoteRows(
      table: _getTableName(type),
      columns: 'id, $naturalKeyColumn',
      orderColumn: naturalKeyColumn,
    );
    final remoteUuidByNaturalKey = <int, String>{};
    for (final record in remoteResponse) {
      final naturalKey = record[naturalKeyColumn] as int?;
      final uuid = record['id'] as String?;
      if (naturalKey != null && uuid != null && uuid.isNotEmpty) {
        remoteUuidByNaturalKey[naturalKey] = uuid;
      }
    }

    final localRecords = await _getLocalRecords(type);
    final pendingNaturalKeys = _getPendingNaturalKeys(type);
    final actions = buildReconciliationActions(
      localRecords: localRecords,
      remoteUuidByNaturalKey: remoteUuidByNaturalKey,
      pendingNaturalKeys: pendingNaturalKeys,
      naturalKeyColumn: naturalKeyColumn,
    );

    return _SyncReconciliationSnapshot(
      localRecords: localRecords,
      actions: actions,
    );
  }

  Future<List<SyncReconciliationAction>> _recoverMissingOrStaleRecords(
      String type) async {
    final inFlight = _recoveryOperationsByType[type];
    if (inFlight != null) {
      return await inFlight;
    }

    final future = _recoverMissingOrStaleRecordsInternal(type);
    _recoveryOperationsByType[type] = future;

    try {
      return await future;
    } finally {
      if (identical(_recoveryOperationsByType[type], future)) {
        _recoveryOperationsByType.remove(type);
      }
    }
  }

  Future<List<SyncReconciliationAction>> _recoverMissingOrStaleRecordsInternal(
      String type) async {
    if (_currentUserId == null) return const <SyncReconciliationAction>[];

    final failedActions = <SyncReconciliationAction>[];

    try {
      final snapshot = await _buildReconciliationSnapshot(type);
      final recoveryActions = snapshot.actions
          .where((action) =>
              action.operation == 'repair_uuid' ||
              action.operation == 'upload_local')
          .toList();

      if (recoveryActions.isEmpty) {
        return failedActions;
      }

      bool hasChanges = false;

      for (final action in recoveryActions) {
        final snapshotLocalRecord = snapshot.localRecords.firstWhere(
            (record) => record['id'] == action.localId,
            orElse: () => <String, dynamic>{});
        if (snapshotLocalRecord.isEmpty) {
          continue;
        }

        final currentLocalRecord =
            await _getLocalRecordById(type, action.localId) ??
                snapshotLocalRecord;

        try {
          if (action.operation == 'repair_uuid' &&
              action.uuid != null &&
              action.uuid!.isNotEmpty) {
            final currentUuid = currentLocalRecord['uuid'] as String?;
            if (currentUuid == action.uuid) {
              continue;
            }

            await _repairLocalRecordUuid(type, currentLocalRecord, action.uuid!);
            hasChanges = true;
            if (kDebugMode) {
              debugPrint(
                  'Reconciled missing/stale UUID for $type naturalKey=${action.naturalKey}');
            }
          } else if (action.operation == 'upload_local') {
            final currentUuid = currentLocalRecord['uuid'] as String?;
            if (currentUuid != null && currentUuid.isNotEmpty) {
              continue;
            }

            await _uploadLocalRecord(type, currentLocalRecord);
            hasChanges = true;
            if (kDebugMode) {
              debugPrint(
                  'Recovered unsynced local $type record during reconciliation naturalKey=${action.naturalKey}');
            }
          }
        } catch (e) {
          failedActions.add(action);
          if (action.operation == 'upload_local') {
            await _queuePersistentOperation(
              '${type}_${action.naturalKey}',
              type,
              'create',
              currentLocalRecord,
              userId: _currentUserId,
            );
          }
          ErrorHandler.logError(
            e,
            customMessage:
                '_recoverMissingOrStaleRecords failed for $type naturalKey=${action.naturalKey}',
            context: {'type': type, 'operation': action.operation},
          );
        }
      }

      if (hasChanges) {
        _notifyChange(type);
      }
    } catch (e) {
      ErrorHandler.logError(
        e,
        customMessage: '_recoverMissingOrStaleRecords exception for $type',
        context: {'type': type},
      );
    }

    return failedActions;
  }

  Future<Map<String, dynamic>?> _getLocalRecordById(String type, int id) async {
    final localRecords = await _getLocalRecords(type);
    return localRecords.where((record) => record['id'] == id).firstOrNull;
  }

  Future<void> _detectRemoteDeletions(String type) async {
    if (_currentUserId == null) return;

    try {
      final snapshot = await _buildReconciliationSnapshot(type);
      final deleteActions = snapshot.actions
          .where((action) => action.operation == 'delete_local')
          .toList();

      if (deleteActions.isNotEmpty) {
        for (final action in deleteActions) {
          final localRecord = snapshot.localRecords.firstWhere(
              (record) => record['id'] == action.localId,
              orElse: () => <String, dynamic>{});
          if (localRecord.isEmpty) {
            continue;
          }

          await _deleteLocalRecord(type, action.localId);
          if (kDebugMode) {
            debugPrint(
                'Deleted stale local $type record during reconciliation naturalKey=${action.naturalKey}');
          }
        }

        _notifyChange(type);
      }
    } catch (e) {
      ErrorHandler.logError(
        e,
        customMessage: '_detectRemoteDeletions exception for $type',
        context: {'type': type},
      );
    }
  }

  Future<void> _uploadLocalRecord(
      String type, Map<String, dynamic> localRecord) async {
    switch (type) {
      case 'highlight':
        await _uploadHighlight(localRecord);
        break;
      case 'note':
        await _uploadNote(localRecord);
        break;
      case 'history':
        await _uploadHistoryItem(localRecord);
        break;
      case 'search_history':
        await _uploadSearchHistoryItem(localRecord);
        break;
      default:
        throw ArgumentError('Unknown type: $type');
    }
  }

  Future<void> _queueMissingUuidRecordsForLaterSync(String type) async {
    if (_currentUserId == null) return;

    final localRecords = await _getLocalRecords(type);
    final pendingNaturalKeys = _getPendingNaturalKeys(type);
    final naturalKeyColumn = _getNaturalKeyColumn(type);

    for (final localRecord in localRecords) {
      final naturalKey = localRecord[naturalKeyColumn] as int?;
      final uuid = localRecord['uuid'] as String?;
      final hasLocalUuid = uuid != null && uuid.isNotEmpty;
      if (naturalKey == null ||
          hasLocalUuid ||
          pendingNaturalKeys.contains(naturalKey)) {
        continue;
      }

      await _queuePersistentOperation(
        '${type}_$naturalKey',
        type,
        'create',
        localRecord,
        userId: _currentUserId,
      );
    }
  }

  // Helper: Get table name for type
  String _getTableName(String type) {
    switch (type) {
      case 'highlight':
        return 'highlights';
      case 'note':
        return 'notes';
      case 'history':
        return 'history';
      case 'search_history':
        return 'search_history';
      default:
        throw ArgumentError('Unknown type: $type');
    }
  }

  String _getNaturalKeyColumn(String type) {
    switch (type) {
      case 'highlight':
      case 'note':
        return 'created_at';
      case 'history':
      case 'search_history':
        return 'timestamp';
      default:
        throw ArgumentError('Unknown type: $type');
    }
  }

  // Helper: Get local records for type
  Future<List<Map<String, dynamic>>> _getLocalRecords(String type) async {
    switch (type) {
      case 'highlight':
        return await HighlightsDatabase.getHighlights();
      case 'note':
        return await NotesDatabase.getNotes();
      case 'history':
        return await HistoryDatabase.getHistory();
      case 'search_history':
        return await SearchDatabase.getSearchHistory();
      default:
        return [];
    }
  }

  Set<int> _getPendingNaturalKeys(String type) {
    if (_currentUserId == null) return <int>{};

    final pendingNaturalKeys = <int>{};
    final queues = [
      ..._highlightsPendingQueue,
      ..._notesPendingQueue,
      ..._historyPendingQueue,
      ..._searchHistoryPendingQueue,
      ..._retryQueue,
    ];

    for (final operation in queues) {
      if (operation.type != type ||
          (operation.userId ?? _currentUserId) != _currentUserId ||
          (operation.operation != 'create' &&
              operation.operation != 'update')) {
        continue;
      }

      final keyColumn = _getNaturalKeyColumn(type);
      final naturalKey = operation.data[keyColumn] as int?;
      if (naturalKey != null) {
        pendingNaturalKeys.add(naturalKey);
      }
    }

    return pendingNaturalKeys;
  }

  Future<void> _repairLocalRecordUuid(
      String type, Map<String, dynamic> localRecord, String uuid) async {
    switch (type) {
      case 'highlight':
        await HighlightsDatabase.upsertHighlightFromSync(
          book: localRecord['book'] as String,
          chapter: localRecord['chapter'] as int,
          verse: localRecord['verse'] as int,
          start: localRecord['start'] as int,
          end: localRecord['end'] as int,
          color: localRecord['color'] as int,
          createdAt: localRecord['created_at'] as int,
          updatedAt: localRecord['updated_at'] as int,
          uuid: uuid,
        );
        break;
      case 'note':
        await NotesDatabase.upsertNoteFromSync(
          book: localRecord['book'] as String,
          chapter: localRecord['chapter'] as int,
          verse: localRecord['verse'] as int,
          noteText: localRecord['note_text'] as String,
          createdAt: localRecord['created_at'] as int,
          updatedAt: localRecord['updated_at'] as int,
          uuid: uuid,
        );
        break;
      case 'history':
        await HistoryDatabase.upsertHistoryFromSync(
          localRecord['book'] as String,
          localRecord['chapter'] as int,
          localRecord['verse'] as int?,
          localRecord['timestamp'] as int,
          uuid: uuid,
        );
        break;
      case 'search_history':
        await SearchDatabase.upsertSearchHistoryFromSync(
          localRecord['query'] as String,
          localRecord['useRegex'] as bool,
          localRecord['useNearby'] as bool,
          localRecord['useWholeWord'] as bool,
          localRecord['useRedLetter'] as bool,
          localRecord['caseSensitive'] as bool,
          localRecord['bookFilterType'] as String,
          localRecord['customBookFilter'] as String,
          localRecord['timestamp'] as int,
          uuid: uuid,
        );
        break;
    }
  }

  // Helper: Delete local record by type and id
  Future<void> _deleteLocalRecord(String type, int id) async {
    switch (type) {
      case 'highlight':
        await HighlightsDatabase.deleteHighlight(id, skipSync: true);
        break;
      case 'note':
        await NotesDatabase.deleteNote(id, skipSync: true);
        break;
      case 'history':
        await HistoryDatabase.deleteHistoryItem(id, skipSync: true);
        break;
      case 'search_history':
        await SearchDatabase.deleteSearchHistoryItem(id, skipSync: true);
        break;
    }
  }

  // Helper: Notify UI of changes
  void _notifyChange(String type) {
    switch (type) {
      case 'highlight':
        LocalDataChangeNotifier.notifyHighlightsChanged();
        _highlightsChangedController?.add(null);
        break;
      case 'note':
        LocalDataChangeNotifier.notifyNotesChanged();
        _notesChangedController?.add(null);
        break;
      case 'history':
        LocalDataChangeNotifier.notifyHistoryChanged();
        _historyChangedController?.add(null);
        break;
      case 'search_history':
        LocalDataChangeNotifier.notifySearchHistoryChanged();
        _searchHistoryChangedController?.add(null);
        break;
    }
  }

  // Upload single highlight to Supabase
  Future<void> _uploadHighlight(Map<String, dynamic> highlight) async {
    if (_currentUserId == null) return;

    // Validate data before uploading to prevent sending corrupt data to Supabase
    final isValid =
        await DataValidation.validateBeforeUpload(highlight, 'highlight');
    if (!isValid) {
      throw StateError('Invalid highlight data for upload');
    }

    final dataToInsert = {
      'user_id': _currentUserId,
      'book': highlight['book'],
      'chapter': highlight['chapter'],
      'verse': highlight['verse'],
      'start': highlight['start'],
      'end': highlight['end'],
      'color': highlight['color'] ?? 0,
      'created_at': highlight['created_at'],
      'updated_at': highlight['updated_at'],
    };

    // Include UUID if it exists to preserve the same record ID across syncs
    if (highlight['uuid'] != null && highlight['uuid'].isNotEmpty) {
      dataToInsert['id'] = highlight['uuid'];
    }

    try {
      final response = await _supabase
          .from('highlights')
          .upsert(dataToInsert, onConflict: 'created_at')
          .select('id')
          .maybeSingle();

      // If the local highlight didn't have a UUID, update it with the one from Supabase
      final supabaseUuid = response?['id'] as String?;
      if (supabaseUuid != null &&
          (highlight['uuid'] == null || highlight['uuid'].isEmpty)) {
        await HighlightsDatabase.upsertHighlightFromSync(
          book: highlight['book'] as String,
          chapter: highlight['chapter'] as int,
          verse: highlight['verse'] as int,
          start: highlight['start'] as int,
          end: highlight['end'] as int,
          color: highlight['color'] as int,
          createdAt: highlight['created_at'] as int,
          updatedAt: highlight['updated_at'] as int,
          uuid: supabaseUuid,
        );
      }
    } catch (e) {
      ErrorHandler.logError(
        e,
        customMessage: '_uploadHighlight exception',
      );
      rethrow;
    }
  }

  // Batch upload multiple highlights to Supabase
  Future<void> _batchUploadHighlights(
      List<Map<String, dynamic>> highlights) async {
    if (_currentUserId == null || highlights.isEmpty) return;

    // Validate all highlights first
    final validHighlights = <Map<String, dynamic>>[];
    for (final highlight in highlights) {
      final isValid =
          await DataValidation.validateBeforeUpload(highlight, 'highlight');
      if (isValid) {
        validHighlights.add(highlight);
      }
    }

    if (validHighlights.isEmpty) return;

    // Separate highlights into two groups:
    // 1. Highlights WITH UUIDs (already synced to Supabase before) - can be upserted
    // 2. Highlights WITHOUT UUIDs (new, created locally while offline) - must be inserted to get UUID from Supabase
    final highlightsWithUuids = validHighlights
        .where((h) => h['uuid'] != null && (h['uuid'] as String).isNotEmpty)
        .toList();
    final highlightsWithoutUuids = validHighlights
        .where((h) => h['uuid'] == null || (h['uuid'] as String).isEmpty)
        .toList();

    // Upload highlights with UUIDs using upsert (updates existing or inserts if new)
    if (highlightsWithUuids.isNotEmpty) {
      try {
        final dataToUpsert = highlightsWithUuids
            .map((highlight) => {
                  'id': highlight['uuid'],
                  'user_id': _currentUserId,
                  'book': highlight['book'],
                  'chapter': highlight['chapter'],
                  'verse': highlight['verse'],
                  'start': highlight['start'],
                  'end': highlight['end'],
                  'color': highlight['color'],
                  'created_at': highlight['created_at'],
                  'updated_at': highlight['updated_at'],
                })
            .toList();

        await _supabase
            .from('highlights')
            .upsert(dataToUpsert, onConflict: 'created_at')
            .select('id, created_at');
      } catch (e) {
        ErrorHandler.logError(
          e,
          customMessage: '_batchUploadHighlights exception (upsert with UUIDs)',
        );
      }
    }

    // Upsert highlights without UUIDs (let Supabase generate UUID or return existing one)
    // Using upsert instead of insert handles the case where a record with the same
    // created_at already exists (e.g., importing a backup to the same account)
    if (highlightsWithoutUuids.isNotEmpty) {
      try {
        final dataToUpsert = highlightsWithoutUuids
            .map((highlight) => {
                  'user_id': _currentUserId,
                  'book': highlight['book'],
                  'chapter': highlight['chapter'],
                  'verse': highlight['verse'],
                  'start': highlight['start'],
                  'end': highlight['end'],
                  'color': highlight['color'],
                  'created_at': highlight['created_at'],
                  'updated_at': highlight['updated_at'],
                  // DO NOT include 'id' field - let Supabase DEFAULT generate it or use existing
                })
            .toList();

        final response = await _supabase
            .from('highlights')
            .upsert(dataToUpsert, onConflict: 'created_at')
            .select('id, created_at');

        // Update local highlights with UUIDs from Supabase
        for (final uploadedRecord in response) {
          final supabaseUuid = uploadedRecord['id'] as String?;
          final createdAt = uploadedRecord['created_at'] as int;

          // Find the corresponding local highlight
          final localHighlight = highlightsWithoutUuids.firstWhere(
              (h) => h['created_at'] == createdAt,
              orElse: () => <String, dynamic>{});

          if (localHighlight.isNotEmpty && supabaseUuid != null) {
            await HighlightsDatabase.upsertHighlightFromSync(
              book: localHighlight['book'] as String,
              chapter: localHighlight['chapter'] as int,
              verse: localHighlight['verse'] as int,
              start: localHighlight['start'] as int,
              end: localHighlight['end'] as int,
              color: localHighlight['color'] as int,
              createdAt: localHighlight['created_at'] as int,
              updatedAt: localHighlight['updated_at'] as int,
              uuid: supabaseUuid,
            );
          }
        }
      } catch (e) {
        ErrorHandler.logError(
          e,
          customMessage:
              '_batchUploadHighlights exception (insert new highlights)',
        );
      }
    }
  }

  // Delete highlight from Supabase
  Future<void> deleteRemoteHighlight(int createdAt) async {
    if (_currentUserId == null) return;

    await _supabase
        .from('highlights')
        .delete()
        .eq('user_id', _currentUserId!)
        .eq('created_at', createdAt);
  }

  // Sync notes to Supabase
  Future<void> syncNotes() async {
    // Check if notes sync is enabled
    final notesEnabled = await _getSyncEnabled('syncNotes');

    if (!notesEnabled) {
      return;
    }

    if (_currentUserId == null) {
      return;
    }

    if (_syncStatus == SyncStatus.offline) {
      return;
    }

    try {
      final failedRecoveryActions = await _recoverMissingOrStaleRecords('note');
      final failedUploadNaturalKeys = <int>{};

      // Get local notes - all for deletion checks
      final localNotes = await NotesDatabase.getNotes();

      // Filter for recent changes if not forced
      final baselineTime =
          _lastNotesSync ?? DateTime.fromMillisecondsSinceEpoch(0);
      final notesToSync = localNotes
          .where((n) =>
              (n['updated_at'] ?? n['created_at'] ?? 0) >
              baselineTime.millisecondsSinceEpoch)
          .toList();

      // Always perform bi-directional sync regardless of local changes

      if (notesToSync.isNotEmpty) {
        // Get remote notes for comparison
        final remoteNotes = await _fetchRemoteRows(
          table: 'notes',
          orderColumn: 'created_at',
        );

        // Sync logic: collect notes that need uploading
        final notesToUpload = <Map<String, dynamic>>[];

        for (final note in notesToSync) {
          final localTimestamp = note['created_at'] as int;
          final remoteDoc = remoteNotes
              .where((n) => n['created_at'] == localTimestamp)
              .firstOrNull;

          if (remoteDoc == null) {
            // New note - needs upload
            notesToUpload.add(note);
          } else {
            // Check if local is newer
            final localTime = note['updated_at'] ?? note['created_at'] ?? 0;
            final remoteTime =
                remoteDoc['updated_at'] ?? remoteDoc['created_at'] ?? 0;

            if (localTime > remoteTime) {
              notesToUpload.add(note);
            }
          }
        }

        // Upload notes
        if (notesToUpload.isNotEmpty) {
          final failedUploads = await _batchUploadNotes(notesToUpload);
          failedUploadNaturalKeys.addAll(failedUploads);

          for (final note in notesToUpload
              .where((note) => failedUploads.contains(note['created_at']))) {
            _enqueueFailedOperation(SyncOperation(
              id: note['created_at'].toString(),
              type: 'note',
              operation: ((note['uuid'] as String?)?.isNotEmpty ?? false)
                  ? 'update'
                  : 'create',
              data: note,
              timestamp:
                  DateTime.fromMillisecondsSinceEpoch(note['created_at'] as int),
              userId: _currentUserId,
            ));
          }
        }
      }

      // Download remote changes newer than last sync for bidirectional sync
      final lastSyncMs = _lastNotesSyncSaved?.millisecondsSinceEpoch ?? 0;
      final snapshot = await _fetchRemoteRows(
        table: 'notes',
        orderColumn: 'updated_at',
        secondaryOrderColumn: 'created_at',
        greaterThanColumn: 'updated_at',
        greaterThanValue: lastSyncMs,
      );
      if (snapshot.isNotEmpty) {
        await _downloadNotes(snapshot);
      }

      // Detect remote deletions
      await _detectRemoteDeletions('note');

      final shouldAdvanceTimestamp = shouldAdvanceSyncTimestamp(
        failedRecoveryActions: failedRecoveryActions,
        failedUploadNaturalKeys: failedUploadNaturalKeys,
        pendingNaturalKeys: _getPendingNaturalKeys('note'),
      );

      if (shouldAdvanceTimestamp) {
        _lastNotesSync = DateTime.now();

        // Save timestamps to preferences - only for notes
        await _saveLastSyncTimestamps('notes');
      }
    } catch (e) {
      // For critical failures, don't retry - just log
    }
  }

  // Upload single note to Supabase
  Future<void> _uploadNote(Map<String, dynamic> note) async {
    if (_currentUserId == null) return;

    // Validate data before uploading to prevent sending corrupt data to Supabase
    final isValid = await DataValidation.validateBeforeUpload(note, 'note');
    if (!isValid) {
      throw StateError('Invalid note data for upload');
    }

    final dataToInsert = {
      'user_id': _currentUserId,
      'book': note['book'],
      'chapter': note['chapter'],
      'verse': note['verse'],
      'note_text': note['note_text'],
      'created_at': note['created_at'],
      'updated_at': note['updated_at'],
    };

    // Include UUID if it exists to preserve the same record ID across syncs
    if (note['uuid'] != null && note['uuid'].isNotEmpty) {
      dataToInsert['id'] = note['uuid'];
    }

    try {
      final response = await _supabase
          .from('notes')
          .upsert(dataToInsert, onConflict: 'created_at')
          .select('id')
          .maybeSingle();

      // If the local note didn't have a UUID, update it with the one from Supabase
      final supabaseUuid = response?['id'] as String?;
      if (supabaseUuid != null &&
          (note['uuid'] == null || note['uuid'].isEmpty)) {
        await NotesDatabase.upsertNoteFromSync(
          book: note['book'] as String,
          chapter: note['chapter'] as int,
          verse: note['verse'] as int,
          noteText: note['note_text'] as String,
          createdAt: note['created_at'] as int,
          updatedAt: note['updated_at'] as int,
          uuid: supabaseUuid,
        );
      }
    } catch (e) {
      ErrorHandler.logError(
        e,
        customMessage: '_uploadNote exception',
      );
      rethrow;
    }
  }

  // Delete note from Supabase
  Future<void> deleteRemoteNote(int createdAt) async {
    if (_currentUserId == null) return;

    await _supabase
        .from('notes')
        .delete()
        .eq('user_id', _currentUserId!)
        .eq('created_at', createdAt);
  }

  Future<void> recoverNoteSyncState() async {
    if (_currentUserId == null) return;

    final notesEnabled = await _getSyncEnabled('syncNotes');
    if (!notesEnabled) return;

    if (!isOnline) {
      await _queueMissingUuidRecordsForLaterSync('note');
      return;
    }

    await _recoverMissingOrStaleRecords('note');
  }

  // Batch upload multiple notes to Supabase
  Future<Set<int>> _batchUploadNotes(List<Map<String, dynamic>> notes) async {
    if (_currentUserId == null || notes.isEmpty) return <int>{};

    // Validate all notes first
    final validNotes = <Map<String, dynamic>>[];
    for (final note in notes) {
      final isValid = await DataValidation.validateBeforeUpload(note, 'note');
      if (isValid) {
        validNotes.add(note);
      }
    }

    if (validNotes.isEmpty) return <int>{};

    final failedCreatedAt = <int>{};

    // Separate notes into two groups:
    // 1. Notes WITH UUIDs (already synced to Supabase before) - can be upserted
    // 2. Notes WITHOUT UUIDs (new, created locally while offline) - must be inserted to get UUID from Supabase
    final notesWithUuids = validNotes
        .where((note) =>
            note['uuid'] != null && (note['uuid'] as String).isNotEmpty)
        .toList();
    final notesWithoutUuids = validNotes
        .where(
            (note) => note['uuid'] == null || (note['uuid'] as String).isEmpty)
        .toList();

    // Upload notes with UUIDs using upsert (updates existing or inserts if new)
    if (notesWithUuids.isNotEmpty) {
      try {
        final dataToUpsert = notesWithUuids
            .map((note) => {
                  'id': note['uuid'],
                  'user_id': _currentUserId,
                  'book': note['book'],
                  'chapter': note['chapter'],
                  'verse': note['verse'],
                  'note_text': note['note_text'],
                  'created_at': note['created_at'],
                  'updated_at': note['updated_at'],
                })
            .toList();

        await _supabase
            .from('notes')
            .upsert(dataToUpsert, onConflict: 'created_at')
            .select('id, created_at');
      } catch (e) {
        failedCreatedAt
            .addAll(notesWithUuids.map((note) => note['created_at'] as int));
        ErrorHandler.logError(
          e,
          customMessage: '_batchUploadNotes exception (upsert with UUIDs)',
        );
      }
    }

    // Upsert notes without UUIDs (let Supabase generate UUID or return existing one)
    // Using upsert instead of insert handles the case where a record with the same
    // created_at already exists (e.g., importing a backup to the same account)
    if (notesWithoutUuids.isNotEmpty) {
      try {
        final dataToUpsert = notesWithoutUuids
            .map((note) => {
                  'user_id': _currentUserId,
                  'book': note['book'],
                  'chapter': note['chapter'],
                  'verse': note['verse'],
                  'note_text': note['note_text'],
                  'created_at': note['created_at'],
                  'updated_at': note['updated_at'],
                  // DO NOT include 'id' field - let Supabase DEFAULT generate it or use existing
                })
            .toList();

        final response = await _supabase
            .from('notes')
            .upsert(dataToUpsert, onConflict: 'created_at')
            .select('id, created_at');

        final createdAtWithResponse = <int>{};

        // Update local notes with UUIDs from Supabase
        for (final uploadedRecord in response) {
          final supabaseUuid = uploadedRecord['id'] as String?;
          final createdAt = uploadedRecord['created_at'] as int;
          createdAtWithResponse.add(createdAt);

          // Find the corresponding local note
          final localNote = notesWithoutUuids.firstWhere(
              (n) => n['created_at'] == createdAt,
              orElse: () => <String, dynamic>{});

          if (localNote.isNotEmpty && supabaseUuid != null) {
            await NotesDatabase.upsertNoteFromSync(
              book: localNote['book'] as String,
              chapter: localNote['chapter'] as int,
              verse: localNote['verse'] as int,
              noteText: localNote['note_text'] as String,
              createdAt: localNote['created_at'] as int,
              updatedAt: localNote['updated_at'] as int,
              uuid: supabaseUuid,
            );
          }
        }

        failedCreatedAt.addAll(notesWithoutUuids
            .where(
                (note) => !createdAtWithResponse.contains(note['created_at']))
            .map((note) => note['created_at'] as int));
      } catch (e) {
        failedCreatedAt.addAll(
            notesWithoutUuids.map((note) => note['created_at'] as int));
        ErrorHandler.logError(
          e,
          customMessage: '_batchUploadNotes exception (insert new notes)',
        );
      }
    }

    return failedCreatedAt;
  }

  // Sync search history to Supabase
  Future<void> syncSearchHistory() async {
    // Check if search history sync is enabled
    final searchHistoryEnabled = await _getSyncEnabled('syncSearchHistory');

    if (!searchHistoryEnabled) {
      return;
    }

    if (_currentUserId == null) {
      return;
    }

    if (_syncStatus == SyncStatus.offline) {
      return;
    }

    try {
      // Always perform bi-directional sync regardless of local changes
      // Upload local changes first
      final baselineTime =
          _lastSearchHistorySync ?? DateTime.fromMillisecondsSinceEpoch(0);
      final localSearchHistory = await SearchDatabase.getSearchHistory();

      // Filter for recent changes if not forced
      final searchHistoryToSync = localSearchHistory
          .where((h) =>
              (h['timestamp'] ?? 0) > baselineTime.millisecondsSinceEpoch)
          .toList();

      // Upload local changes
      if (searchHistoryToSync.isNotEmpty) {
        // Get remote search history
        final remoteSearchHistory = await _fetchRemoteRows(
          table: 'search_history',
          orderColumn: 'timestamp',
        );

        // Sync logic: collect search history items that need uploading
        final searchHistoryItemsToUpload = <Map<String, dynamic>>[];

        for (final searchHistoryItem in searchHistoryToSync) {
          final localTime = searchHistoryItem['timestamp'] ?? 0;
          final remoteDoc = remoteSearchHistory
              .where((s) => s['timestamp'] == localTime)
              .firstOrNull;

          if (remoteDoc == null) {
            // New search history item - needs upload
            searchHistoryItemsToUpload.add(searchHistoryItem);
          } else {
            // Check if local is newer
            final remoteTime = remoteDoc['timestamp'] ?? 0;

            if (localTime > remoteTime) {
              searchHistoryItemsToUpload.add(searchHistoryItem);
            }
          }
        }

        // Upload search history
        if (searchHistoryItemsToUpload.isNotEmpty) {
          try {
            await _batchUploadSearchHistory(searchHistoryItemsToUpload);
          } catch (e) {
            ErrorHandler.logError(
              e,
              customMessage: '_batchUploadSearchHistory exception',
            );

            // If batch upload fails, queue each operation individually for retry
            for (final searchHistoryItem in searchHistoryItemsToUpload) {
              _enqueueFailedOperation(SyncOperation(
                id: searchHistoryItem['timestamp'],
                type: 'search_history',
                operation: 'create',
                data: searchHistoryItem,
                timestamp: DateTime.fromMillisecondsSinceEpoch(
                    searchHistoryItem['timestamp'] as int),
                userId: _currentUserId,
              ));
            }
          }
        }
      }

      // Download remote changes newer than last sync for bidirectional sync
      final lastSyncMs =
          _lastSearchHistorySyncSaved?.millisecondsSinceEpoch ?? 0;
      final snapshot = await _fetchRemoteRows(
        table: 'search_history',
        orderColumn: 'timestamp',
        greaterThanColumn: 'timestamp',
        greaterThanValue: lastSyncMs,
      );
      if (snapshot.isNotEmpty) {
        await _downloadSearchHistory(snapshot);
      }

      // Detect remote deletions
      await _detectRemoteDeletions('search_history');

      // Always update the sync timestamp after sync operations (both upload and download)
      _lastSearchHistorySync = DateTime.now();

      // Save timestamps to preferences - only for search_history
      await _saveLastSyncTimestamps('search_history');
    } catch (e) {
      ErrorHandler.logError(
        e,
        customMessage: 'syncSearchHistory exception',
      );
    }
  }

  // Batch upload multiple search history items to Supabase
  Future<void> _batchUploadSearchHistory(
      List<Map<String, dynamic>> searchHistoryItems) async {
    if (_currentUserId == null || searchHistoryItems.isEmpty) return;

    // Validate all search history items first
    final validSearchHistoryItems = <Map<String, dynamic>>[];
    for (final searchHistoryItem in searchHistoryItems) {
      final isValid = await DataValidation.validateBeforeUpload(
          searchHistoryItem, 'search_history');
      if (isValid) {
        validSearchHistoryItems.add(searchHistoryItem);
      }
    }

    if (validSearchHistoryItems.isEmpty) return;

    // Separate search history items into two groups:
    // 1. Items WITH UUIDs (already synced to Supabase before) - can be upserted
    // 2. Items WITHOUT UUIDs (new, created locally while offline) - must be inserted to get UUID from Supabase
    final itemsWithUuids = validSearchHistoryItems
        .where((s) => s['uuid'] != null && (s['uuid'] as String).isNotEmpty)
        .toList();
    final itemsWithoutUuids = validSearchHistoryItems
        .where((s) => s['uuid'] == null || (s['uuid'] as String).isEmpty)
        .toList();

    // Upload search history items with UUIDs using upsert (updates existing or inserts if new)
    if (itemsWithUuids.isNotEmpty) {
      try {
        final dataToUpsert = itemsWithUuids
            .map((searchHistoryItem) => {
                  'id': searchHistoryItem['uuid'],
                  'user_id': _currentUserId,
                  'query': searchHistoryItem['query'] ?? '',
                  'useRegex': searchHistoryItem['useRegex'] is bool
                      ? searchHistoryItem['useRegex']
                      : false,
                  'useNearby': searchHistoryItem['useNearby'] is bool
                      ? searchHistoryItem['useNearby']
                      : false,
                  'useWholeWord': searchHistoryItem['useWholeWord'] is bool
                      ? searchHistoryItem['useWholeWord']
                      : false,
                  'useRedLetter': searchHistoryItem['useRedLetter'] is bool
                      ? searchHistoryItem['useRedLetter']
                      : false,
                  'caseSensitive': searchHistoryItem['caseSensitive'] is bool
                      ? searchHistoryItem['caseSensitive']
                      : false,
                  'bookFilterType': searchHistoryItem['bookFilterType'] ?? '',
                  'customBookFilter':
                      searchHistoryItem['customBookFilter'] ?? '',
                  'timestamp': searchHistoryItem['timestamp'],
                })
            .toList();

        await _supabase
            .from('search_history')
            .upsert(dataToUpsert, onConflict: 'timestamp')
            .select('id, timestamp');
      } catch (e) {
        ErrorHandler.logError(
          e,
          customMessage:
              '_batchUploadSearchHistory exception (upsert with UUIDs)',
        );
      }
    }

    // Upsert search history items without UUIDs (let Supabase generate UUID or return existing one)
    // Using upsert instead of insert handles the case where a record with the same
    // timestamp already exists (e.g., importing a backup to the same account)
    if (itemsWithoutUuids.isNotEmpty) {
      try {
        final dataToUpsert = itemsWithoutUuids
            .map((searchHistoryItem) => {
                  'user_id': _currentUserId,
                  'query': searchHistoryItem['query'] ?? '',
                  'useRegex': searchHistoryItem['useRegex'] is bool
                      ? searchHistoryItem['useRegex']
                      : false,
                  'useNearby': searchHistoryItem['useNearby'] is bool
                      ? searchHistoryItem['useNearby']
                      : false,
                  'useWholeWord': searchHistoryItem['useWholeWord'] is bool
                      ? searchHistoryItem['useWholeWord']
                      : false,
                  'useRedLetter': searchHistoryItem['useRedLetter'] is bool
                      ? searchHistoryItem['useRedLetter']
                      : false,
                  'caseSensitive': searchHistoryItem['caseSensitive'] is bool
                      ? searchHistoryItem['caseSensitive']
                      : false,
                  'bookFilterType': searchHistoryItem['bookFilterType'] ?? '',
                  'customBookFilter':
                      searchHistoryItem['customBookFilter'] ?? '',
                  'timestamp': searchHistoryItem['timestamp'],
                  // DO NOT include 'id' field - let Supabase DEFAULT generate it or use existing
                })
            .toList();

        final response = await _supabase
            .from('search_history')
            .upsert(dataToUpsert, onConflict: 'timestamp')
            .select('id, timestamp');

        // Update local search history items with UUIDs from Supabase
        for (final uploadedRecord in response) {
          final supabaseUuid = uploadedRecord['id'] as String?;
          final timestamp = uploadedRecord['timestamp'] as int;

          // Find the corresponding local search history item
          final localSearchHistoryItem = itemsWithoutUuids.firstWhere(
              (s) => s['timestamp'] == timestamp,
              orElse: () => <String, dynamic>{});

          if (localSearchHistoryItem.isNotEmpty && supabaseUuid != null) {
            await SearchDatabase.upsertSearchHistoryFromSync(
              localSearchHistoryItem['query'] as String,
              localSearchHistoryItem['useRegex'] as bool,
              localSearchHistoryItem['useNearby'] as bool,
              localSearchHistoryItem['useWholeWord'] as bool,
              localSearchHistoryItem['useRedLetter'] as bool,
              localSearchHistoryItem['caseSensitive'] as bool,
              localSearchHistoryItem['bookFilterType'] as String,
              localSearchHistoryItem['customBookFilter'] as String,
              localSearchHistoryItem['timestamp'] as int,
              uuid: supabaseUuid,
            );
          }
        }
      } catch (e) {
        ErrorHandler.logError(
          e,
          customMessage:
              '_batchUploadSearchHistory exception (insert new items)',
        );
      }
    }
  }

  // Sync history to Supabase
  Future<void> syncHistory() async {
    // Check if history sync is enabled
    final historyEnabled = await _getSyncEnabled('syncHistory');

    if (!historyEnabled) {
      return;
    }

    if (_currentUserId == null) {
      return;
    }

    if (_syncStatus == SyncStatus.offline) {
      return;
    }

    try {
      // Always perform bi-directional sync regardless of local changes
      // Upload local changes first
      final baselineTime =
          _lastHistorySync ?? DateTime.fromMillisecondsSinceEpoch(0);
      final localHistory = await HistoryDatabase.getHistory();

      // Filter for recent changes if not forced
      final historyToSync = localHistory
          .where((h) =>
              (h['timestamp'] ?? 0) > baselineTime.millisecondsSinceEpoch)
          .toList();

      // Upload local changes
      if (historyToSync.isNotEmpty) {
        // Get remote history
        final remoteHistory = await _fetchRemoteRows(
          table: 'history',
          orderColumn: 'timestamp',
        );

        // Sync logic: collect history items that need uploading
        final historyItemsToUpload = <Map<String, dynamic>>[];

        for (final historyItem in historyToSync) {
          final localTime = historyItem['timestamp'] ?? 0;
          final remoteDoc = remoteHistory
              .where((h) => h['timestamp'] == localTime)
              .firstOrNull;

          if (remoteDoc == null) {
            // New history item - needs upload
            historyItemsToUpload.add(historyItem);
          } else {
            // Check if local is newer
            final remoteTime = remoteDoc['timestamp'] ?? 0;

            if (localTime > remoteTime) {
              historyItemsToUpload.add(historyItem);
            }
          }
        }

        // Upload history
        if (historyItemsToUpload.isNotEmpty) {
          try {
            await _batchUploadHistory(historyItemsToUpload);
          } catch (e) {
            ErrorHandler.logError(
              e,
              customMessage: '_batchUploadHistory exception',
            );

            // If batch upload fails, queue each operation individually for retry
            for (final historyItem in historyItemsToUpload) {
              _enqueueFailedOperation(SyncOperation(
                id: historyItem['timestamp'],
                type: 'history',
                operation: 'create',
                data: historyItem,
                timestamp: DateTime.fromMillisecondsSinceEpoch(
                    historyItem['timestamp'] as int),
                userId: _currentUserId,
              ));
            }
          }
        }
      }

      // Download remote changes newer than last sync for bidirectional sync
      final lastSyncMs = _lastHistorySyncSaved?.millisecondsSinceEpoch ?? 0;
      final snapshot = await _fetchRemoteRows(
        table: 'history',
        orderColumn: 'timestamp',
        greaterThanColumn: 'timestamp',
        greaterThanValue: lastSyncMs,
      );
      if (snapshot.isNotEmpty) {
        await _downloadHistory(snapshot);
      }

      // Detect remote deletions
      await _detectRemoteDeletions('history');

      // Always update the sync timestamp after sync operations (both upload and download)
      _lastHistorySync = DateTime.now();

      // Save timestamps to preferences - only for history
      await _saveLastSyncTimestamps('history');
    } catch (e) {
      ErrorHandler.logError(
        e,
        customMessage: 'syncHistory exception',
      );
    }
  }

  // Upload single history item to Supabase
  Future<void> _uploadHistoryItem(Map<String, dynamic> historyItem) async {
    if (_currentUserId == null) return;

    // Validate data before uploading to prevent sending corrupt data to Supabase
    final isValid =
        await DataValidation.validateBeforeUpload(historyItem, 'history');
    if (!isValid) {
      throw StateError('Invalid history data for upload');
    }

    final dataToInsert = {
      'user_id': _currentUserId,
      'book': historyItem['book'],
      'chapter': historyItem['chapter'],
      'verse': historyItem['verse'],
      'timestamp': historyItem['timestamp'],
    };

    // Include UUID if it exists to preserve the same record ID across syncs
    if (historyItem['uuid'] != null && historyItem['uuid'].isNotEmpty) {
      dataToInsert['id'] = historyItem['uuid'];
    }

    try {
      final response = await _supabase
          .from('history')
          .upsert(dataToInsert, onConflict: 'timestamp')
          .select('id')
          .maybeSingle();

      // If the local history item didn't have a UUID, update it with the one from Supabase
      final supabaseUuid = response?['id'] as String?;
      if (supabaseUuid != null &&
          (historyItem['uuid'] == null || historyItem['uuid'].isEmpty)) {
        await HistoryDatabase.upsertHistoryFromSync(
          historyItem['book'] as String,
          historyItem['chapter'] as int,
          historyItem['verse'] as int?,
          historyItem['timestamp'] as int,
          uuid: supabaseUuid,
        );
      }
    } catch (e) {
      ErrorHandler.logError(
        e,
        customMessage: '_uploadHistoryItem exception',
      );
      rethrow;
    }
  }

  // Delete history item from Supabase
  Future<void> deleteRemoteHistoryItem(int historyId) async {
    if (_currentUserId == null) return;

    await _supabase
        .from('history')
        .delete()
        .eq('user_id', _currentUserId!)
        .eq('timestamp', historyId);
  }

  // Batch upload multiple history items to Supabase
  Future<void> _batchUploadHistory(
      List<Map<String, dynamic>> historyItems) async {
    if (_currentUserId == null || historyItems.isEmpty) return;

    // Validate all history items first
    final validHistoryItems = <Map<String, dynamic>>[];
    for (final historyItem in historyItems) {
      final isValid =
          await DataValidation.validateBeforeUpload(historyItem, 'history');
      if (isValid) {
        validHistoryItems.add(historyItem);
      }
    }

    if (validHistoryItems.isEmpty) return;

    // Separate history items into two groups:
    // 1. Items WITH UUIDs (already synced to Supabase before) - can be upserted
    // 2. Items WITHOUT UUIDs (new, created locally while offline) - must be inserted to get UUID from Supabase
    final itemsWithUuids = validHistoryItems
        .where((h) => h['uuid'] != null && (h['uuid'] as String).isNotEmpty)
        .toList();
    final itemsWithoutUuids = validHistoryItems
        .where((h) => h['uuid'] == null || (h['uuid'] as String).isEmpty)
        .toList();

    // Upload history items with UUIDs using upsert (updates existing or inserts if new)
    if (itemsWithUuids.isNotEmpty) {
      try {
        final dataToUpsert = itemsWithUuids
            .map((historyItem) => {
                  'id': historyItem['uuid'],
                  'user_id': _currentUserId,
                  'book': historyItem['book'],
                  'chapter': historyItem['chapter'],
                  'verse': historyItem['verse'],
                  'timestamp': historyItem['timestamp'],
                })
            .toList();

        await _supabase
            .from('history')
            .upsert(dataToUpsert, onConflict: 'timestamp')
            .select('id, timestamp');
      } catch (e) {
        ErrorHandler.logError(
          e,
          customMessage: '_batchUploadHistory exception (upsert with UUIDs)',
        );
      }
    }

    // Upsert history items without UUIDs (let Supabase generate UUID or return existing one)
    // Using upsert instead of insert handles the case where a record with the same
    // timestamp already exists (e.g., importing a backup to the same account)
    if (itemsWithoutUuids.isNotEmpty) {
      try {
        final dataToUpsert = itemsWithoutUuids
            .map((historyItem) => {
                  'user_id': _currentUserId,
                  'book': historyItem['book'],
                  'chapter': historyItem['chapter'],
                  'verse': historyItem['verse'],
                  'timestamp': historyItem['timestamp'],
                  // DO NOT include 'id' field - let Supabase DEFAULT generate it or use existing
                })
            .toList();

        final response = await _supabase
            .from('history')
            .upsert(dataToUpsert, onConflict: 'timestamp')
            .select('id, timestamp');

        // Update local history items with UUIDs from Supabase
        for (final uploadedRecord in response) {
          final supabaseUuid = uploadedRecord['id'] as String?;
          final timestamp = uploadedRecord['timestamp'] as int;

          // Find the corresponding local history item
          final localHistoryItem = itemsWithoutUuids.firstWhere(
              (h) => h['timestamp'] == timestamp,
              orElse: () => <String, dynamic>{});

          if (localHistoryItem.isNotEmpty && supabaseUuid != null) {
            await HistoryDatabase.upsertHistoryFromSync(
              localHistoryItem['book'] as String,
              localHistoryItem['chapter'] as int,
              localHistoryItem['verse'] as int?,
              localHistoryItem['timestamp'] as int,
              uuid: supabaseUuid,
            );
          }
        }
      } catch (e) {
        ErrorHandler.logError(
          e,
          customMessage: '_batchUploadHistory exception (insert new items)',
        );
      }
    }
  }

  // Sync only recent remote changes since last local sync (app resume scenario)
  Future<void> syncRecentChangesOnly() async {
    if (_currentUserId == null || !isOnline) return;

    try {
      // Check sync settings and download recent changes only
      final highlightsEnabled = await _getSyncEnabled('syncHighlights');
      final notesEnabled = await _getSyncEnabled('syncNotes');
      final historyEnabled = await _getSyncEnabled('syncHistory');
      final searchHistoryEnabled = await _getSyncEnabled('syncSearchHistory');

      // Query and download highlights updated since last sync
      if (highlightsEnabled) {
        final baselineTime =
            _lastHighlightsSyncSaved?.millisecondsSinceEpoch ?? 0;
        final snapshot = await _fetchRemoteRows(
          table: 'highlights',
          orderColumn: 'updated_at',
          secondaryOrderColumn: 'created_at',
          greaterThanColumn: 'updated_at',
          greaterThanValue: baselineTime,
        );

        if (snapshot.isNotEmpty) {
          await _downloadHighlights(snapshot);
          _lastHighlightsSync = DateTime.now();
          await _saveLastSyncTimestamps('highlights');
        }
        // Detect remote deletions
        await _detectRemoteDeletions('highlight');
      }

      // Query and download notes updated since last sync
      if (notesEnabled) {
        final failedRecoveryActions = await _recoverMissingOrStaleRecords('note');
        final lastSyncMs = _lastNotesSyncSaved?.millisecondsSinceEpoch ?? 0;
        final snapshot = await _fetchRemoteRows(
          table: 'notes',
          orderColumn: 'updated_at',
          secondaryOrderColumn: 'created_at',
          greaterThanColumn: 'updated_at',
          greaterThanValue: lastSyncMs,
        );

        if (snapshot.isNotEmpty) {
          await _downloadNotes(snapshot);
        }
        // Detect remote deletions
        await _detectRemoteDeletions('note');

        if (snapshot.isNotEmpty &&
            shouldAdvanceSyncTimestamp(
              failedRecoveryActions: failedRecoveryActions,
              failedUploadNaturalKeys: const <int>{},
              pendingNaturalKeys: _getPendingNaturalKeys('note'),
            )) {
          _lastNotesSync = DateTime.now();
          await _saveLastSyncTimestamps('notes');
        }
      }

      // Query and download history items since last sync
      if (historyEnabled) {
        final lastSyncMs = _lastHistorySyncSaved?.millisecondsSinceEpoch ?? 0;
        final snapshot = await _fetchRemoteRows(
          table: 'history',
          orderColumn: 'timestamp',
          greaterThanColumn: 'timestamp',
          greaterThanValue: lastSyncMs,
        );

        if (snapshot.isNotEmpty) {
          await _downloadHistory(snapshot);
          _lastHistorySync = DateTime.now();
          await _saveLastSyncTimestamps('history');
        }
        // Detect remote deletions
        await _detectRemoteDeletions('history');
      }

      // Query and download search history items since last sync
      if (searchHistoryEnabled) {
        final lastSyncMs =
            _lastSearchHistorySyncSaved?.millisecondsSinceEpoch ?? 0;
        final snapshot = await _fetchRemoteRows(
          table: 'search_history',
          orderColumn: 'timestamp',
          greaterThanColumn: 'timestamp',
          greaterThanValue: lastSyncMs,
        );

        if (snapshot.isNotEmpty) {
          await _downloadSearchHistory(snapshot);
          _lastSearchHistorySync = DateTime.now();
          await _saveLastSyncTimestamps('search_history');
        }
        // Detect remote deletions
        await _detectRemoteDeletions('search_history');
      }
    } catch (e) {
      ErrorHandler.logError(
        e,
        customMessage: '_syncRecentChangesOnly exception',
      );
    }
  }

  // Sync all data types
  Future<void> syncAll() async {
    if (_currentUserId == null) {
      return;
    }

    // Set syncing status to show progress dialog
    final previousStatus = _syncStatus;
    if (isOnline) {
      _syncStatus = SyncStatus.syncing;
      syncStatusNotifier.value = _syncStatus;
    }

    try {
      await syncHighlights();
      await syncNotes();
      await syncHistory();
      await syncSearchHistory();
    } catch (e) {
      ErrorHandler.logError(
        e,
        customMessage: '_syncAll exception',
      );
    } finally {
      // Restore previous status
      _syncStatus = previousStatus;
      // Update notifier to reflect completion
      if (isOnline) {
        // If was syncing, restore to online status
        syncStatusNotifier.value = SyncStatus.online;
      } else {
        // If was offline, keep offline
        syncStatusNotifier.value = _syncStatus;
      }
    }
  }

  // Start connection monitoring using event-driven connectivity changes
  void _startConnectionMonitoring() {
    // Avoid duplicate listeners
    if (_connectivitySubscription != null) return;

    // Listen to connectivity changes instead of polling
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> result) async {
        try {
          // Debounce rapid connectivity changes (network fluctuations)
          await Future.delayed(const Duration(seconds: 1));

          final hasConnection = await InternetAccessChecker.hasInternetAccess();

          if (hasConnection) {
            if (_syncStatus != SyncStatus.online) {
              // Connection restored - test and setup
              try {
                await _checkConnectionAndSetup();
              } catch (e) {
                // Handle connection setup errors gracefully
                ErrorHandler.logError(
                  e,
                  customMessage:
                      'Connection setup failed during connectivity change',
                );
                _syncStatus = SyncStatus.offline;
                syncStatusNotifier.value = _syncStatus;
                await ErrorHandler.handleNetworkError(e);
              }
            } else {
              // Status may be stale "online" after transient drops. Flush queued work anyway.
              await _flushQueuedOperations();
            }
          } else if (_syncStatus != SyncStatus.offline) {
            // Connection lost
            _syncStatus = SyncStatus.offline;
            syncStatusNotifier.value = _syncStatus;
            await ErrorHandler.handle('No network connection',
                type: ErrorType.network, severity: ErrorSeverity.medium);
          }
        } catch (e) {
          // Handle connectivity monitoring errors gracefully
          ErrorHandler.logError(
            e,
            customMessage: 'Connectivity monitoring error',
          );
          await ErrorHandler.handleNetworkError(e);
          _syncStatus = SyncStatus.offline;
          syncStatusNotifier.value = _syncStatus;
        }
      },
      onError: (Object error, StackTrace stackTrace) async {
        ErrorHandler.logError(
          error,
          customMessage:
              'Connectivity change stream unavailable; using Supabase probe',
          context: {'stackTrace': stackTrace.toString()},
        );
        await _checkConnectionAndSetup();
      },
    );

    // Also perform initial connectivity check
    _connectivity.checkConnectivity().then((result) async {
      try {
        final hasConnection = await InternetAccessChecker.hasInternetAccess();
        if (hasConnection) {
          await _checkConnectionAndSetup();
        } else {
          _syncStatus = SyncStatus.offline;
          syncStatusNotifier.value = _syncStatus;
          await ErrorHandler.handle('No network connection',
              type: ErrorType.network, severity: ErrorSeverity.medium);
        }
      } catch (e) {
        // Handle initial connectivity check errors gracefully
        ErrorHandler.logError(
          e,
          customMessage: 'Initial connectivity check failed',
        );
        _syncStatus = SyncStatus.offline;
        syncStatusNotifier.value = _syncStatus;
      }
    }).catchError((e) async {
      // Handle connectivity check errors gracefully
      ErrorHandler.logError(
        e,
        customMessage: 'Connectivity check error',
      );
      _syncStatus = SyncStatus.offline;
      syncStatusNotifier.value = _syncStatus;
    });
  }

  // Stop connection monitoring (for Android background optimization)
  void stopConnectionMonitoring() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }

  // Sync single highlight efficiently with bidirectional conflict resolution
  Future<void> syncSingleHighlight(Map<String, dynamic> highlight) async {
    if (_currentUserId == null || !isOnline) return;

    final docId = highlight['created_at'];

    try {
      // Query only the specific remote document
      final remoteDocResponse = await _supabase
          .from('highlights')
          .select()
          .eq('user_id', _currentUserId!)
          .eq('created_at', docId)
          .maybeSingle();

      if (remoteDocResponse == null) {
        // Remote document doesn't exist - upload local version
        final isValid =
            await DataValidation.validateBeforeUpload(highlight, 'highlight');
        if (isValid) {
          await _uploadHighlight(highlight);
        }
        return;
      }

      final remoteDoc = remoteDocResponse;

      // Remote document exists - compare timestamps
      final isValidRemote = await DataValidation.validateHighlightData(
          remoteDoc,
          context: 'single highlight sync');

      if (isValidRemote) {
        final localTime =
            highlight['updated_at'] ?? highlight['created_at'] ?? 0;
        final remoteTime =
            remoteDoc['updated_at'] ?? remoteDoc['created_at'] ?? 0;

        if (localTime > remoteTime) {
          // Local is newer - upload local version
          final isValid =
              await DataValidation.validateBeforeUpload(highlight, 'highlight');
          if (isValid) {
            await _uploadHighlight(highlight);
          }
        } else if (remoteTime > localTime) {
          // Remote is newer - download to update local
          await _downloadHighlights([remoteDoc]);
        }
        // If timestamps equal, no action needed (already in sync)
      } else {
        // Invalid remote data - upload local to overwrite
        final isValid =
            await DataValidation.validateBeforeUpload(highlight, 'highlight');
        if (isValid) {
          await _uploadHighlight(highlight);
        }
      }
    } catch (e) {
      // Remote document doesn't exist - upload local version
      // final isValid = await DataValidation.validateBeforeUpload(highlight, 'highlight');
      // if (isValid) {
      //   await _uploadHighlight(highlight);
      // }
      ErrorHandler.logError(
        e,
        customMessage: 'syncSingleHighlight exception',
      );
      rethrow;
    }
  }

  // Sync single note efficiently with bidirectional conflict resolution
  Future<void> syncSingleNote(Map<String, dynamic> note) async {
    if (_currentUserId == null || !isOnline) return;

    final docId = note['created_at'];

    try {
      // Query only the specific remote document
      final remoteDocResponse = await _supabase
          .from('notes')
          .select()
          .eq('user_id', _currentUserId!)
          .eq('created_at', docId)
          .maybeSingle();

      if (remoteDocResponse == null) {
        // Remote document doesn't exist - upload local version
        final isValid = await DataValidation.validateBeforeUpload(note, 'note');
        if (isValid) {
          await _uploadNote(note);
        }
        return;
      }

      final remoteDoc = remoteDocResponse;

      // Remote document exists - compare timestamps
      final isValidRemote = await DataValidation.validateNoteData(remoteDoc,
          context: 'single note sync');

      if (isValidRemote) {
        final localTime = note['updated_at'] ?? note['created_at'] ?? 0;
        final remoteTime =
            remoteDoc['updated_at'] ?? remoteDoc['created_at'] ?? 0;

        if (localTime > remoteTime) {
          // Local is newer - upload local version
          final isValid =
              await DataValidation.validateBeforeUpload(note, 'note');
          if (isValid) {
            await _uploadNote(note);
          }
        } else if (remoteTime > localTime) {
          // Remote is newer - download to update local
          await _downloadNotes([remoteDoc]);
        }
        // If timestamps equal, no action needed (already in sync)
      } else {
        // Invalid remote data - upload local to overwrite
        final isValid = await DataValidation.validateBeforeUpload(note, 'note');
        if (isValid) {
          await _uploadNote(note);
        }
      }
    } catch (e) {
      // Remote document doesn't exist - upload local version
      final isValid = await DataValidation.validateBeforeUpload(note, 'note');
      if (isValid) {
        await _uploadNote(note);
      }
      rethrow;
    }
  }

  // Sync single history item efficiently with bidirectional conflict resolution
  Future<void> syncSingleHistoryItem(Map<String, dynamic> historyItem) async {
    if (_currentUserId == null || !isOnline) return;

    final docId = historyItem['timestamp'] as int;

    try {
      // Query only the specific remote document
      final remoteDocResponse = await _supabase
          .from('history')
          .select()
          .eq('user_id', _currentUserId!)
          .eq('timestamp', docId)
          .maybeSingle();

      if (remoteDocResponse == null) {
        // Remote document doesn't exist - upload local version
        final isValid =
            await DataValidation.validateBeforeUpload(historyItem, 'history');
        if (isValid) {
          await _uploadHistoryItem(historyItem);
        }
        return;
      }

      final remoteDoc = remoteDocResponse;

      // Remote document exists - compare timestamps
      final isValidRemote = await DataValidation.validateHistoryData(remoteDoc,
          context: 'single history sync');

      if (isValidRemote) {
        final localTime = historyItem['timestamp'] ?? 0;
        final remoteTime = remoteDoc['timestamp'] ?? 0;

        if (localTime > remoteTime) {
          // Local is newer - upload local version
          final isValid =
              await DataValidation.validateBeforeUpload(historyItem, 'history');
          if (isValid) {
            await _uploadHistoryItem(historyItem);
          }
        } else if (remoteTime > localTime) {
          // Remote is newer - download to update local
          await _downloadHistory([remoteDoc]);
        }
        // If timestamps equal, no action needed (already in sync)
      } else {
        // Invalid remote data - upload local to overwrite
        final isValid =
            await DataValidation.validateBeforeUpload(historyItem, 'history');
        if (isValid) {
          await _uploadHistoryItem(historyItem);
        }
      }
    } catch (e) {
      // Remote document doesn't exist - upload local version
      // final isValid = await DataValidation.validateBeforeUpload(historyItem, 'history');
      // if (isValid) {
      //   await _uploadHistoryItem(historyItem);
      // }
      ErrorHandler.logError(
        e,
        customMessage: 'syncSingleHistoryItem exception',
      );
      rethrow;
    }
  }

  // Sync single search history item efficiently with bidirectional conflict resolution
  Future<void> syncSingleSearchHistoryItem(
      Map<String, dynamic> searchHistoryItem) async {
    if (_currentUserId == null || !isOnline) return;

    final docId = searchHistoryItem['timestamp'] as int;

    try {
      // Query only the specific remote document
      final remoteDocResponse = await _supabase
          .from('search_history')
          .select()
          .eq('user_id', _currentUserId!)
          .eq('timestamp', docId)
          .maybeSingle();

      if (remoteDocResponse == null) {
        // Remote document doesn't exist - upload local version
        final isValid = await DataValidation.validateBeforeUpload(
            searchHistoryItem, 'search_history');
        if (isValid) {
          await _uploadSearchHistoryItem(searchHistoryItem);
        }
        return;
      }

      final remoteDoc = remoteDocResponse;

      // Remote document exists - compare timestamps
      final isValidRemote = await DataValidation.validateSearchHistoryData(
          remoteDoc,
          context: 'single search_history sync');

      if (isValidRemote) {
        final localTime = searchHistoryItem['timestamp'] ?? 0;
        final remoteTime = remoteDoc['timestamp'] ?? 0;

        if (localTime > remoteTime) {
          // Local is newer - upload local version
          final isValid = await DataValidation.validateBeforeUpload(
              searchHistoryItem, 'search_history');
          if (isValid) {
            await _uploadSearchHistoryItem(searchHistoryItem);
          }
        } else if (remoteTime > localTime) {
          // Remote is newer - download to update local
          await _downloadSearchHistory([remoteDoc]);
        }
        // If timestamps equal, no action needed (already in sync)
      } else {
        // Invalid remote data - upload local to overwrite
        final isValid = await DataValidation.validateBeforeUpload(
            searchHistoryItem, 'search_history');
        if (isValid) {
          await _uploadSearchHistoryItem(searchHistoryItem);
        }
      }
    } catch (e) {
      // Remote document doesn't exist - upload local version
      // final isValid =
      //     await DataValidation.validateBeforeUpload(searchHistoryItem, 'search_history');
      // if (isValid) {
      //   await _uploadSearchHistoryItem(searchHistoryItem);
      // }
      ErrorHandler.logError(
        e,
        customMessage: 'syncSingleSearchHistoryItem exception',
      );
      rethrow;
    }
  }

  // Unified operation marking method (handles all sync categories: highlight, note, history, search_history)
  Future<void> markOperation(String type, int itemId, String operation,
      Map<String, dynamic> data) async {
    // Set appropriate sync flag based on type
    switch (type) {
      case 'highlight':
        LocalDataChangeNotifier.notifyHighlightsChanged();
        break;
      case 'note':
        LocalDataChangeNotifier.notifyNotesChanged();
        break;
      case 'history':
        LocalDataChangeNotifier.notifyHistoryChanged();
        break;
      case 'search_history':
        LocalDataChangeNotifier.notifySearchHistoryChanged();
        break;
    }

    // Handle offline queuing
    if (!isOnline || _currentUserId == null) {
      await _queuePersistentOperation('${type}_$itemId', type, operation, data);
      return;
    }

    // Handle online sync attempts
    try {
      if (operation == 'delete') {
        // Type-specific delete methods
        switch (type) {
          case 'highlight':
            try {
              await deleteRemoteHighlight(data['created_at'] as int);
            } catch (e) {
              ErrorHandler.logError(
                e,
                customMessage: 'deleteRemoteHighlight exception',
              );
              rethrow;
            }
            break;
          case 'note':
            try {
              await deleteRemoteNote(data['created_at'] as int);
            } catch (e) {
              ErrorHandler.logError(
                e,
                customMessage: 'deleteRemoteNote exception',
              );
              rethrow;
            }
            break;
          case 'history':
            try {
              await deleteRemoteHistoryItem(itemId);
            } catch (e) {
              ErrorHandler.logError(
                e,
                customMessage: 'deleteRemoteHistoryItem exception',
              );
              rethrow;
            }
            break;
          case 'search_history':
            try {
              await deleteRemoteSearchHistoryItem(itemId);
            } catch (e) {
              ErrorHandler.logError(
                e,
                customMessage: 'deleteRemoteSearchHistoryItem exception',
              );
              rethrow;
            }
            break;
        }
      } else {
        // Type-specific single-item sync methods for create/update
        switch (type) {
          case 'highlight':
            try {
              await syncSingleHighlight(data);
            } catch (e) {
              ErrorHandler.logError(
                e,
                customMessage: 'syncSingleHighlight exception',
              );
              rethrow;
            }
            break;
          case 'note':
            try {
              await syncSingleNote(data);
            } catch (e) {
              ErrorHandler.logError(
                e,
                customMessage: 'syncSingleNote exception',
              );
              rethrow;
            }
            break;
          case 'history':
            try {
              await syncSingleHistoryItem(data);
            } catch (e) {
              ErrorHandler.logError(
                e,
                customMessage: 'syncSingleHistoryItem exception',
              );
              rethrow;
            }
            break;
          case 'search_history':
            try {
              await syncSingleSearchHistoryItem(data);
            } catch (e) {
              ErrorHandler.logError(
                e,
                customMessage: 'syncSingleSearchHistoryItem exception',
              );
              rethrow;
            }
            break;
        }
      }
    } catch (e) {
      // Prepare failed operation data with type-specific ID and timestamp extraction
      String id;
      DateTime timestamp;
      switch (type) {
        case 'highlight':
        case 'note':
          final createdAt = data['created_at'];
          id = createdAt.toString();
          timestamp = DateTime.fromMillisecondsSinceEpoch(createdAt as int);
          break;
        case 'history':
        case 'search_history':
          final timestampValue = data['timestamp'];
          id = timestampValue.toString();
          timestamp =
              DateTime.fromMillisecondsSinceEpoch(timestampValue as int);
          break;
        default:
          id = '0';
          timestamp = DateTime.now();
      }

      _enqueueFailedOperation(SyncOperation(
        id: id,
        type: type,
        operation: operation,
        data: data,
        timestamp: timestamp,
        userId: _currentUserId,
      ));
    }

    // Notify appropriate change notifier based on type
    switch (type) {
      case 'highlight':
        LocalDataChangeNotifier.notifyHighlightsChanged();
        _highlightsChangedController?.add(null);
        break;
      case 'note':
        LocalDataChangeNotifier.notifyNotesChanged();
        _notesChangedController?.add(null);
        break;
      case 'history':
        LocalDataChangeNotifier.notifyHistoryChanged();
        _historyChangedController?.add(null);
        break;
      case 'search_history':
        LocalDataChangeNotifier.notifySearchHistoryChanged();
        _searchHistoryChangedController?.add(null);
        break;
    }
  }

  // Manual sync trigger
  Future<void> triggerManualSync() async {
    await syncAll();
    LocalDataChangeNotifier.notifyHighlightsChanged();
    LocalDataChangeNotifier.notifyNotesChanged();
    LocalDataChangeNotifier.notifyHistoryChanged();
    LocalDataChangeNotifier.notifySearchHistoryChanged();
    // Also trigger SupabaseSyncService streams for consistency
    _highlightsChangedController?.add(null);
    _notesChangedController?.add(null);
    _historyChangedController?.add(null);
    _searchHistoryChangedController?.add(null);
  }

  // Public method to check Supabase connection for exit dialogs
  Future<bool> checkSupabaseConnection() async {
    if (_currentUserId == null) return false;

    try {
      // Test basic Supabase connectivity by attempting a small read
      await _supabase
          .from('profiles')
          .select('id')
          .eq('id', _currentUserId!)
          .single();
      return true;
    } catch (e) {
      return false;
    }
  }

  // Delete all remote highlights when sync is disabled
  Future<void> deleteAllRemoteHighlights() async {
    if (_currentUserId == null) return;

    await _supabase.from('highlights').delete().eq('user_id', _currentUserId!);
  }

  Future<void> deleteAllRemoteNotes() async {
    if (_currentUserId == null) return;

    await _supabase.from('notes').delete().eq('user_id', _currentUserId!);
  }

  Future<void> deleteAllRemoteHistory() async {
    if (_currentUserId == null) return;

    await _supabase.from('history').delete().eq('user_id', _currentUserId!);
  }

  Future<void> deleteAllRemoteSearchHistory() async {
    if (_currentUserId == null) return;

    await _supabase
        .from('search_history')
        .delete()
        .eq('user_id', _currentUserId!);
  }

  // Cache the username locally for offline display
  Future<void> cacheUsername() async {
    if (_currentUserId == null) return;

    try {
      final response = await _supabase
          .from('profiles')
          .select('username')
          .eq('id', _currentUserId!)
          .single();
      final username = response['username'] as String?;
      await HistoryDatabase.setCachedUsername(username ?? 'Unknown');
    } catch (e) {
      await HistoryDatabase.setCachedUsername('Unknown');
    }
  }

  // Set cached username (for manual updates)
  Future<void> setCachedUsername(String username) async {
    await HistoryDatabase.setCachedUsername(username);
  }

  // Clear cached username (called on sign out)
  Future<void> clearCachedUsername() async {
    await HistoryDatabase.setCachedUsername('Unknown');
  }

  // Get cached username (for main.dart display)
  static Future<String?> getCachedUsername() async {
    return await HistoryDatabase.getCachedUsername();
  }

  // Upload single search history item to Supabase
  Future<void> _uploadSearchHistoryItem(
      Map<String, dynamic> searchHistoryItem) async {
    if (_currentUserId == null) return;

    // Validate data before uploading to prevent sending corrupt data to Supabase
    final isValid = await DataValidation.validateBeforeUpload(
        searchHistoryItem, 'search_history');
    if (!isValid) {
      throw StateError('Invalid search history data for upload');
    }

    final dataToInsert = {
      'user_id': _currentUserId,
      'query': searchHistoryItem['query'] ?? '',
      'useRegex': searchHistoryItem['useRegex'] is bool
          ? searchHistoryItem['useRegex']
          : false,
      'useNearby': searchHistoryItem['useNearby'] is bool
          ? searchHistoryItem['useNearby']
          : false,
      'useWholeWord': searchHistoryItem['useWholeWord'] is bool
          ? searchHistoryItem['useWholeWord']
          : false,
      'useRedLetter': searchHistoryItem['useRedLetter'] is bool
          ? searchHistoryItem['useRedLetter']
          : false,
      'caseSensitive': searchHistoryItem['caseSensitive'] is bool
          ? searchHistoryItem['caseSensitive']
          : false,
      'bookFilterType': searchHistoryItem['bookFilterType'] ?? '',
      'customBookFilter': searchHistoryItem['customBookFilter'] ?? '',
      'timestamp': searchHistoryItem['timestamp'] ?? 0,
    };

    // Include UUID if it exists to preserve the same record ID across syncs
    if (searchHistoryItem['uuid'] != null &&
        searchHistoryItem['uuid'].isNotEmpty) {
      dataToInsert['id'] = searchHistoryItem['uuid'];
    }

    try {
      final response = await _supabase
          .from('search_history')
          .upsert(dataToInsert, onConflict: 'timestamp')
          .select('id')
          .maybeSingle();

      // If the local search history item didn't have a UUID, update it with the one from Supabase
      final supabaseUuid = response?['id'] as String?;
      if (supabaseUuid != null &&
          (searchHistoryItem['uuid'] == null ||
              searchHistoryItem['uuid'].isEmpty)) {
        await SearchDatabase.upsertSearchHistoryFromSync(
          searchHistoryItem['query'] as String,
          searchHistoryItem['useRegex'] as bool,
          searchHistoryItem['useNearby'] as bool,
          searchHistoryItem['useWholeWord'] as bool,
          searchHistoryItem['useRedLetter'] as bool,
          searchHistoryItem['caseSensitive'] as bool,
          searchHistoryItem['bookFilterType'] as String,
          searchHistoryItem['customBookFilter'] as String,
          searchHistoryItem['timestamp'] as int,
          uuid: supabaseUuid,
        );
      }
    } catch (e) {
      ErrorHandler.logError(
        e,
        customMessage: '_uploadSearchHistoryItem exception',
      );

      // Re-throw the original error
      rethrow;
    }
  }

  // Delete search history item from Supabase
  Future<void> deleteRemoteSearchHistoryItem(int searchHistoryId) async {
    if (_currentUserId == null) return;

    await _supabase
        .from('search_history')
        .delete()
        .eq('user_id', _currentUserId!)
        .eq('timestamp', searchHistoryId);
  }

  // Add failed operation to retry queue for later retry
  void _enqueueFailedOperation(SyncOperation operation) {
    final ownerId = operation.userId ?? _currentUserId;
    if (ownerId == null) {
      return;
    }

    final operationWithRetryCount = operation.copyWith(
        retryCount: operation.retryCount + 1, userId: ownerId);
    final existingIndex = _retryQueue.indexWhere((queued) =>
        queued.id == operationWithRetryCount.id &&
        queued.type == operationWithRetryCount.type &&
        queued.operation == operationWithRetryCount.operation &&
        (queued.userId ?? ownerId) == ownerId);

    if (existingIndex == -1) {
      _retryQueue.add(operationWithRetryCount);
    } else {
      final existing = _retryQueue[existingIndex];
      _retryQueue[existingIndex] =
          operationWithRetryCount.retryCount > existing.retryCount
              ? operationWithRetryCount
              : existing.copyWith(userId: existing.userId ?? ownerId);
    }

    _startRetryTimer();
  }

  // Start or restart retry timer with fixed intervals based on retry attempt
  void _startRetryTimer() {
    _retryTimer?.cancel();

    if (_retryQueue.isEmpty) return;

    // Use shared retry delay constants: syncRetryDelay1Seconds, syncRetryDelay2Seconds, syncRetryDelay3Seconds
    final nextRetry = _retryQueue.first;
    final Duration delay;
    switch (nextRetry.retryCount) {
      case 1:
        delay =
            Duration(seconds: syncRetryDelay1Seconds); // First retry: 1 second
        break;
      case 2:
        delay = Duration(
            seconds: syncRetryDelay2Seconds); // Second retry: 15 seconds
        break;
      case 3:
        delay = Duration(
            seconds: syncRetryDelay3Seconds); // Third retry: 30 seconds
        break;
      default:
        delay = Duration
            .zero; // After 3 retries, process immediately to move to persistent queue
    }

    _retryTimer = Timer(delay, _processRetryQueue);
  }

  // Process operations in retry queue
  Future<void> _processRetryQueue() async {
    if (_retryQueue.isEmpty || _currentUserId == null || !isOnline) {
      return;
    }

    final queuedForOtherUsers = <SyncOperation>[];
    final operationsToRetry = <SyncOperation>[];

    for (final operation in _retryQueue) {
      final ownerId = operation.userId ?? _currentUserId;
      if (ownerId != _currentUserId) {
        queuedForOtherUsers.add(operation);
        continue;
      }

      operationsToRetry.add(operation.userId == ownerId
          ? operation
          : operation.copyWith(userId: ownerId));
    }

    _retryQueue
      ..clear()
      ..addAll(queuedForOtherUsers);

    for (final operation in operationsToRetry) {
      // Check if this operation has exceeded max retries
      if (operation.retryCount >= 3) {
        // Move to persistent queue instead of retrying
        await _queuePersistentOperation(
            operation.id, operation.type, operation.operation, operation.data,
            userId: operation.userId);
        continue;
      }

      try {
        await _processSingleSyncOperation(operation);

        // Success - operation complete, no need to re-queue
      } catch (e) {
        // Re-queue for another attempt
        _enqueueFailedOperation(operation);
      }
    }
  }

  // Cleanup - called when user signs out or app is terminated
  void dispose() {
    // Move any remaining retry operations to persistent queues before cleanup
    if (_currentUserId != null && _retryQueue.isNotEmpty) {
      for (final operation in _retryQueue) {
        _queueOperation(operation);
      }
      unawaited(_persistQueues());
    }

    _retryTimer?.cancel();
    _recoveryOperationsByType.clear();

    // Cancel Supabase listeners
    _highlightsChannel?.unsubscribe();
    _notesChannel?.unsubscribe();
    _historyChannel?.unsubscribe();
    _searchHistoryChannel?.unsubscribe();

    // Stop connectivity monitoring
    stopConnectionMonitoring();

    _isListening = false;

    // Properly cleanup stream controllers
    _cleanupStreamControllers();

    _isInitialized = false;
  }

  // Prepare for sign-out - clean up listeners and reset state
  Future<void> prepareForSignOut(
      {bool preservePendingOperations = true}) async {
    final currentUserId = _currentUserId;

    if (preservePendingOperations && currentUserId != null) {
      for (final operation in _retryQueue) {
        _queueOperation(
            operation.copyWith(userId: operation.userId ?? currentUserId));
      }
    }

    // Cancel all active listeners
    _highlightsChannel?.unsubscribe();
    _notesChannel?.unsubscribe();
    _historyChannel?.unsubscribe();
    _searchHistoryChannel?.unsubscribe();

    _retryTimer?.cancel();
    _recoveryOperationsByType.clear();
    stopConnectionMonitoring();

    // Reset flags
    _isListening = false;
    _syncStatus = SyncStatus.offline;
    syncStatusNotifier.value = _syncStatus;

    // Clear sync timestamps and shared preferences for sync
    _lastHighlightsSync = null;
    _lastNotesSync = null;
    _lastHistorySync = null;
    _lastSearchHistorySync = null;
    _lastHighlightsSyncSaved = null;
    _lastNotesSyncSaved = null;
    _lastHistorySyncSaved = null;
    _lastSearchHistorySyncSaved = null;

    // Clear sync timestamps from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('lastHighlightsSync');
    await prefs.remove('lastNotesSync');
    await prefs.remove('lastHistorySync');
    await prefs.remove('lastSearchHistorySync');

    if (!preservePendingOperations) {
      _highlightsPendingQueue.clear();
      _notesPendingQueue.clear();
      _historyPendingQueue.clear();
      _searchHistoryPendingQueue.clear();
    }

    // Persist queue state.
    await _persistQueues();

    // Clear retry queue
    _retryQueue.clear();

    // Clear cached username on sign out
    await clearCachedUsername();

    _isInitialized = false;
  }

  void restartConnectionMonitoring() {
    _startConnectionMonitoring();
  }

  // Handle app resume from pause - sync recent changes and restart monitoring
  Future<void> onAppResumed() async {
    if (_currentUserId == null) return;
    try {
      // Sync any changes that occurred while app was paused
      await syncRecentChangesOnly();
    } catch (e) {
      ErrorHandler.logError(
        e,
        customMessage: 'onAppResumed _syncRecentChangesOnly exception',
      );
    }
  }
}
