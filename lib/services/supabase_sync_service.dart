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
final ValueNotifier<SyncStatus> syncStatusNotifier = ValueNotifier(SyncStatus.offline);

// Prevent rapid initialize() calls
bool _isInitialized = false;

enum SyncStatus { offline, connecting, online, syncing, error }

class SyncOperation {
  final String id;
  final String type; // 'highlight', 'note', 'history'
  final String operation; // 'create', 'update', 'delete'
  final Map<String, dynamic> data;
  final DateTime timestamp;
  final int retryCount; // Track number of retry attempts

  SyncOperation({
    required this.id,
    required this.type,
    required this.operation,
    required this.data,
    required this.timestamp,
    this.retryCount = 0,
  });

  SyncOperation copyWith({int? retryCount, DateTime? timestamp}) {
    return SyncOperation(
      id: id,
      type: type,
      operation: operation,
      data: data,
      timestamp: timestamp ?? this.timestamp,
      retryCount: retryCount ?? this.retryCount,
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
    );
  }
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

  // Flag to prevent realtime listeners from firing during bulk operations
  bool _bulkOperationInProgress = false;
  int _bulkOperationDepth = 0; // Support nested bulk operations

  // Start a bulk operation - temporarily pause realtime listeners
  void _startBulkOperation() {
    if (_bulkOperationDepth == 0) {
      _bulkOperationInProgress = true;
      _pauseRealtimeListeners();
    }
    _bulkOperationDepth++;

    if (kDebugMode) {
      debugPrint(
          'Bulk operation started - depth: $_bulkOperationDepth, paused: $_bulkOperationInProgress');
    }
  }

  // End a bulk operation - resume realtime listeners when depth reaches zero
  void _endBulkOperation() {
    _bulkOperationDepth--;

    if (_bulkOperationDepth <= 0) {
      _bulkOperationInProgress = false;
      _bulkOperationDepth = 0;
      _resumeRealtimeListeners();
    }

    if (kDebugMode) {
      debugPrint(
          'Bulk operation ended - depth: $_bulkOperationDepth, paused: $_bulkOperationInProgress');
    }
  }

  // Temporarily pause all realtime listeners
  void _pauseRealtimeListeners() {
    _highlightsSubscription?.cancel();
    _notesSubscription?.cancel();
    _historySubscription?.cancel();
    _searchHistorySubscription?.cancel();

    // Clear subscription references
    _highlightsSubscription = null;
    _notesSubscription = null;
    _historySubscription = null;
    _searchHistorySubscription = null;

    if (kDebugMode) {
      debugPrint('Realtime listeners paused for bulk operation');
    }
  }

  // Resume all realtime listeners
  void _resumeRealtimeListeners() {
    if (!_isListening || _currentUserId == null) {
      return;
    }

    if (kDebugMode) {
      debugPrint('Resuming realtime listeners after bulk operation');
    }

    // Re-setup all listeners
    _setupRealtimeListeners();
  }

  // Check if bulk operation is in progress
  bool get _isBulkOperationInProgress => _bulkOperationInProgress;

  // Last sync timestamps to track changes
  DateTime? _lastHighlightsSync;
  DateTime? _lastNotesSync;
  DateTime? _lastHistorySync;
  DateTime? _lastSearchHistorySync;

  // Flags for pending changes
  bool _highlightsNeedSync = false;
  bool _notesNeedSync = false;
  bool _historyNeedSync = false;
  bool _searchHistoryNeedSync = false;

  // Last sync timestamps (now persisted)
  DateTime? _lastHighlightsSyncSaved;
  DateTime? _lastNotesSyncSaved;
  DateTime? _lastHistorySyncSaved;
  DateTime? _lastSearchHistorySyncSaved;

  // Listener subscriptions
  StreamSubscription<List<Map<String, dynamic>>>? _highlightsSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _notesSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _historySubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _searchHistorySubscription;
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

  // Flag to control whether failed retries should be preserved during sign out
  bool preserveRetriesOnSignOut = false;

  // Get current user ID
  String? get _currentUserId => _supabase.auth.currentUser?.id;

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
        await prefs.setInt('lastNotesSync', _lastNotesSync!.millisecondsSinceEpoch);
        _lastNotesSyncSaved = _lastNotesSync;
      }
    } else if (category == 'history') {
      if (_lastHistorySync != null) {
        await prefs.setInt('lastHistorySync', _lastHistorySync!.millisecondsSinceEpoch);
        _lastHistorySyncSaved = _lastHistorySync;
      }
    } else if (category == 'search_history') {
      if (_lastSearchHistorySync != null) {
        await prefs.setInt(
            'lastSearchHistorySync', _lastSearchHistorySync!.millisecondsSinceEpoch);
        _lastSearchHistorySyncSaved = _lastSearchHistorySync;
      }
    }
  }

  // Sync status getter
  bool get isOnline => _syncStatus == SyncStatus.online;

  // Public streams for UI to listen to - auto-recreate controllers if closed
  static Stream<void> get highlightsChangedStream {
    if (_highlightsChangedController == null || _highlightsChangedController!.isClosed) {
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
    if (_historyChangedController == null || _historyChangedController!.isClosed) {
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

    // Load and deserialize each queue
    final highlightsJson = prefs.getString(_highlightsQueueKey);
    if (highlightsJson != null) {
      try {
        final decoded = jsonDecode(highlightsJson) as List<dynamic>;
        _highlightsPendingQueue.addAll(
            decoded.map((op) => SyncOperation.fromMap(op as Map<String, dynamic>)));
      } catch (e) {
        // Invalid data, clear it
        await prefs.remove(_highlightsQueueKey);
      }
    }

    final notesJson = prefs.getString(_notesQueueKey);
    if (notesJson != null) {
      try {
        final decoded = jsonDecode(notesJson) as List<dynamic>;
        _notesPendingQueue.addAll(
            decoded.map((op) => SyncOperation.fromMap(op as Map<String, dynamic>)));
      } catch (e) {
        await prefs.remove(_notesQueueKey);
      }
    }

    final historyJson = prefs.getString(_historyQueueKey);
    if (historyJson != null) {
      try {
        final decoded = jsonDecode(historyJson) as List<dynamic>;
        _historyPendingQueue.addAll(
            decoded.map((op) => SyncOperation.fromMap(op as Map<String, dynamic>)));
      } catch (e) {
        await prefs.remove(_historyQueueKey);
      }
    }

    final searchHistoryJson = prefs.getString(_searchHistoryQueueKey);
    if (searchHistoryJson != null) {
      try {
        final decoded = jsonDecode(searchHistoryJson) as List<dynamic>;
        _searchHistoryPendingQueue.addAll(
            decoded.map((op) => SyncOperation.fromMap(op as Map<String, dynamic>)));
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
    await prefs.setString(
        _notesQueueKey, jsonEncode(_notesPendingQueue.map((op) => op.toMap()).toList()));
    await prefs.setString(_historyQueueKey,
        jsonEncode(_historyPendingQueue.map((op) => op.toMap()).toList()));
    await prefs.setString(_searchHistoryQueueKey,
        jsonEncode(_searchHistoryPendingQueue.map((op) => op.toMap()).toList()));
  }

  // Add operation to persistent queue by type (with enhanced deduplication)
  void _queueOperation(SyncOperation operation) {
    switch (operation.type) {
      case 'highlight':
        _processEnhancedDeduplication(
            operation, _highlightsPendingQueue, _matchesHighlight);
        break;
      case 'note':
        _processEnhancedDeduplication(operation, _notesPendingQueue, _matchesNote);
        break;
      case 'history':
        _processEnhancedDeduplication(operation, _historyPendingQueue, _matchesHistory);
        break;
      case 'search_history':
        _processEnhancedDeduplication(
            operation, _searchHistoryPendingQueue, _matchesSearchHistory);
        break;
    }
    _persistQueues();
  }

  // Enhanced de-duplication logic that handles operation conflicts intelligently
  void _processEnhancedDeduplication(SyncOperation newOperation,
      List<SyncOperation> queue, bool Function(SyncOperation, SyncOperation) matcher) {
    // Find matching operations in queue
    final matchingIndices = <int>[];
    for (int i = 0; i < queue.length; i++) {
      if (matcher(queue[i], newOperation)) {
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
            timestamp: newOperation.timestamp.isAfter(existingOperation.timestamp)
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
            timestamp: newOperation.timestamp.isAfter(existingOperation.timestamp)
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
            timestamp: newOperation.timestamp.isAfter(existingOperation.timestamp)
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
        final finalOperation = newOperation.timestamp.isAfter(existingOperation.timestamp)
            ? newOperation
            : existingOperation;
        queue[index] = finalOperation;
        return;
      }

      // Handle update + update = keep the most recent
      if (existingOperation.operation == 'update' && newOperation.operation == 'update') {
        final updatedOperation =
            newOperation.timestamp.isAfter(existingOperation.timestamp)
                ? newOperation
                : existingOperation;
        queue[index] = updatedOperation;
        return;
      }

      // Handle delete + delete = keep only one delete
      if (existingOperation.operation == 'delete' && newOperation.operation == 'delete') {
        // Remove the new delete since we already have one
        return;
      }

      // Handle create + create = keep the most recent
      if (existingOperation.operation == 'create' && newOperation.operation == 'create') {
        final finalOperation = newOperation.timestamp.isAfter(existingOperation.timestamp)
            ? newOperation
            : existingOperation;
        queue[index] = finalOperation;
        return;
      }
    }
  }

  // Matching functions for each data type
  bool _matchesHighlight(SyncOperation op1, SyncOperation op2) {
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
    return op1.type == 'note' &&
        op2.type == 'note' &&
        op1.data['book'] == op2.data['book'] &&
        op1.data['chapter'] == op2.data['chapter'] &&
        op1.data['verse'] == op2.data['verse'] &&
        op1.data['created_at'] == op2.data['created_at'];
  }

  bool _matchesHistory(SyncOperation op1, SyncOperation op2) {
    return op1.type == 'history' &&
        op2.type == 'history' &&
        op1.data['book'] == op2.data['book'] &&
        op1.data['chapter'] == op2.data['chapter'] &&
        op1.data['verse'] == op2.data['verse'] &&
        op1.data['timestamp'] == op2.data['timestamp'];
  }

  bool _matchesSearchHistory(SyncOperation op1, SyncOperation op2) {
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
        // Highlights are identified by created_at timestamp
        final createdAt = operationData['created_at'] as int;
        final localHighlights = await HighlightsDatabase.getHighlights();
        return localHighlights.where((h) => h['created_at'] == createdAt).firstOrNull;

      case 'note':
        // Notes are identified by created_at timestamp
        final createdAt = operationData['created_at'] as int;
        final localNotes = await NotesDatabase.getNotes();
        return localNotes.where((n) => n['created_at'] == createdAt).firstOrNull;

      case 'history':
        // History items are identified by timestamp and book/chapter/verse
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
        // Search history items are identified by exact match of all fields
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
      String operation, Map<String, dynamic> data) async {
    // Only queue operations when user is logged in but offline (can't sync immediately)
    if (_currentUserId == null) {
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
    final isDuplicate =
        existingOps.any((op) => op.id == operationKey && op.operation == operation);
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
    );

    _queueOperation(syncOperation);
  }

  // Process persistent queues when coming online
  Future<void> _processPendingQueues() async {
    if (!isOnline ||
        _currentUserId == null ||
        !await InternetAccessChecker.hasInternetAccess()) {
      return;
    }

    // Process each queue
    await _processPendingQueue(_highlightsPendingQueue);
    await _processPendingQueue(_notesPendingQueue);
    await _processPendingQueue(_historyPendingQueue);
    await _processPendingQueue(_searchHistoryPendingQueue);

    // Persist empty queues
    await _persistQueues();
  }

  // Process a specific pending queue
  Future<void> _processPendingQueue(List<SyncOperation> queue) async {
    if (queue.isEmpty) return;

    final operationsToProcess = List<SyncOperation>.from(queue);
    queue.clear();

    for (final operation in operationsToProcess) {
      // Determine what data to upload - use current local data for create/update if exists
      Map<String, dynamic>? uploadData = operation.data;

      if (operation.operation == 'create' || operation.operation == 'update') {
        final currentLocal = await _getCurrentLocalData(operation.type, operation.data);
        if (currentLocal == null) {
          // Item no longer exists locally - skip processing
          continue;
        }
        uploadData = currentLocal;
      }

      try {
        switch (operation.type) {
          case 'highlight':
            if (operation.operation == 'create' || operation.operation == 'update') {
              try {
                await _uploadHighlight(uploadData);
              } catch (e) {
                if (kDebugMode) {
                  debugPrint('_processPendingQueue exception: ${e.toString()}');
                }
              }
            } else if (operation.operation == 'delete') {
              try {
                await deleteRemoteHighlight(uploadData['created_at'] as int);
              } catch (e) {
                if (kDebugMode) {
                  debugPrint('_processPendingQueue exception: ${e.toString()}');
                }
              }
            }
            break;
          case 'note':
            if (operation.operation == 'create' || operation.operation == 'update') {
              try {
                await _uploadNote(uploadData);
              } catch (e) {
                if (kDebugMode) {
                  debugPrint('_processPendingQueue exception: ${e.toString()}');
                }
              }
            } else if (operation.operation == 'delete') {
              try {
                await deleteRemoteNote(uploadData['created_at'] as int);
              } catch (e) {
                if (kDebugMode) {
                  debugPrint('_processPendingQueue exception: ${e.toString()}');
                }
              }
            }
            break;
          case 'history':
            if (operation.operation == 'create' || operation.operation == 'update') {
              try {
                await _uploadHistoryItem(uploadData);
              } catch (e) {
                if (kDebugMode) {
                  debugPrint('_processPendingQueue exception: ${e.toString()}');
                }
              }
            } else if (operation.operation == 'delete') {
              try {
                await deleteRemoteHistoryItem(uploadData['timestamp']);
              } catch (e) {
                if (kDebugMode) {
                  debugPrint('_processPendingQueue exception: ${e.toString()}');
                }
              }
            }
            break;
          case 'search_history':
            if (operation.operation == 'create' || operation.operation == 'update') {
              try {
                await _uploadSearchHistoryItem(uploadData);
              } catch (e) {
                if (kDebugMode) {
                  debugPrint('_processPendingQueue exception: ${e.toString()}');
                }
              }
            } else if (operation.operation == 'delete') {
              try {
                await deleteRemoteSearchHistoryItem(uploadData['timestamp']);
              } catch (e) {
                if (kDebugMode) {
                  debugPrint('_processPendingQueue exception: ${e.toString()}');
                }
              }
            }
            break;
        }
      } catch (e) {
        // Re-queue failed operations
        try {
          queue.add(operation);
        } catch (e) {
          if (kDebugMode) debugPrint('_processPendingQueue exception: ${e.toString()}');
        }
      }
    }
  }

  // Initialize the sync service
  Future<void> initialize({bool isLoginResync = false}) async {
    if (_isInitialized) {
      if (kDebugMode) {
        debugPrint('SyncService.initialize() called but already initialized');
      }
      return;
    }

    if (kDebugMode) {
      debugPrint('SyncService.initialize() starting... isLoginResync: $isLoginResync');
    }

    if (_currentUserId == null) {
      return;
    }

    // Cancel existing first
    _highlightsSubscription?.cancel();
    _notesSubscription?.cancel();
    _historySubscription?.cancel();
    _searchHistorySubscription?.cancel();
    _retryTimer?.cancel();

    // Check actual connectivity status and set appropriate initial state
    try {
      final hasConnection = await InternetAccessChecker.hasInternetAccess();
      if (hasConnection && _currentUserId != null) {
        _syncStatus = SyncStatus.online; // Connected and have user, assume online
      } else {
        _syncStatus = SyncStatus.offline; // No connection or no user
      }
    } catch (_) {
      _syncStatus = SyncStatus.offline; // On error, assume offline
    }

    syncStatusNotifier.value = _syncStatus;
    _isListening = false;
    _highlightsNeedSync = false;
    _notesNeedSync = false;
    _historyNeedSync = false;
    _searchHistoryNeedSync = false;

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

    // Process any queued operations from offline changes
    if (isOnline) {
      await _processPendingQueues();
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
          if (kDebugMode) debugPrint('$e');
        }
        try {
          await syncNotes();
        } catch (e) {
          if (kDebugMode) debugPrint('$e');
        }
        try {
          await syncHistory();
        } catch (e) {
          if (kDebugMode) debugPrint('$e');
        }
        try {
          await syncSearchHistory();
        } catch (e) {
          if (kDebugMode) debugPrint('$e');
        }
      }
    } else if (!isLoginResync && _currentUserId != null && isOnline) {
      // App resume - do incremental sync to catch changes while backgrounded
      try {
        await _syncRecentChangesOnly();
      } catch (e) {
        // Continue with init even if sync fails
      }
    }

    // Start connection monitoring
    try {
      _startConnectionMonitoring();
    } catch (e) {
      if (kDebugMode) debugPrint('$e');
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
      final connectivityResult = await _connectivity.checkConnectivity();
      //final hasConnection = connectivityResult != ConnectivityResult.none;
      final hasConnection = !connectivityResult.contains(ConnectivityResult.none);

      if (hasConnection) {
        try {
          await _testSupabaseConnection();
          await _setupRealtimeListeners();
          _syncStatus = SyncStatus.online;
          syncStatusNotifier.value = _syncStatus;
          await _processPendingQueues();
        } catch (e) {
          // Connection test or setup failed - go offline but don't crash
          if (kDebugMode) debugPrint('Connection setup failed: ${e.toString()}');
          _syncStatus = SyncStatus.offline;
          syncStatusNotifier.value = _syncStatus;
        }
      } else {
        _syncStatus = SyncStatus.offline;
        syncStatusNotifier.value = _syncStatus;
      }
    } catch (e) {
      // Connectivity check failed - assume offline
      if (kDebugMode) debugPrint('Connectivity check failed: ${e.toString()}');
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
        final testQuery =
            _supabase.from('profiles').select().eq('id', _currentUserId!).single();
        await testQuery;
      } catch (e) {
        // Handle specific Supabase errors that can occur during network restoration
        if (kDebugMode) debugPrint('Supabase profile access failed: ${e.toString()}');
        rethrow;
      }
    } catch (e) {
      // Log the error but don't rethrow - let connectivity monitoring handle reconnection
      if (kDebugMode) debugPrint('Supabase connection test failed: ${e.toString()}');
      rethrow; // Still throw so calling code knows connection failed
    }
  }

  // Method 1: Try direct table access
  void _tryDirectTableAccess() async {
    try {
      // Try to select from the table to see what happens
      final result = await _supabase.from('search_history').select('*').limit(1);
      if (kDebugMode) {
        debugPrint(
            'Direct table access: SUCCESS - Table exists, found ${result.length} rows');
      }
      if (result.isNotEmpty) {
        final columns = result.first.keys.toList();
        if (kDebugMode) debugPrint('Available columns: $columns');

        // Check for missing columns
        final requiredColumns = ['bookFilterType', 'customBookFilter'];
        final missingColumns =
            requiredColumns.where((col) => !columns.contains(col)).toList();
        if (missingColumns.isNotEmpty) {
          if (kDebugMode) debugPrint('MISSING COLUMNS: $missingColumns');
        } else {
          if (kDebugMode) debugPrint('All required columns present');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Direct table access failed: ${e.toString()}');
      rethrow;
    }
  }

  // Method 2: Try information schema access
  void _tryInformationSchemaAccess() async {
    try {
      // Try to query information_schema.columns
      final result = await _supabase
          .from('information_schema.columns')
          .select('column_name, data_type, is_nullable')
          .eq('table_name', 'search_history');

      if (kDebugMode) debugPrint('Information schema access: SUCCESS');
      if (result.isNotEmpty) {
        final columns =
            result.map((col) => '${col['column_name']}:${col['data_type']}').join(', ');
        if (kDebugMode) debugPrint('Table structure: $columns');
      } else {
        if (kDebugMode) debugPrint('No columns found - table may not exist');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Information schema access failed: ${e.toString()}');
      rethrow;
    }
  }

  // Method 3: Try direct PostgreSQL query
  void _tryPostgresQuery() async {
    try {
      // Use RPC to query the table structure
      final result = await _supabase
          .rpc('get_table_columns', params: {'table_name': 'search_history'});
      if (kDebugMode) debugPrint('PostgreSQL query access: SUCCESS');
      if (kDebugMode) debugPrint('RPC result: $result');
    } catch (e) {
      if (kDebugMode) debugPrint('PostgreSQL query access failed: ${e.toString()}');
      rethrow;
    }
  }

  // Setup realtime listeners for user's data - only when all conditions are met
  Future<void> _setupRealtimeListeners() async {
    if (_currentUserId == null || _isListening) return;

    // Cancel existing listeners before setting up new ones
    _highlightsSubscription?.cancel();
    _notesSubscription?.cancel();
    _historySubscription?.cancel();
    _searchHistorySubscription?.cancel();

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
          _highlightsSubscription = _supabase
              .from('highlights')
              .stream(primaryKey: ['id'])
              .eq('user_id', _currentUserId!)
              .listen((List<Map<String, dynamic>> data) {
                _onHighlightsChanged(data);
              }, onError: (error) {
                _handleRealtimeSubscriptionError(error, 'highlights');
              });
        } catch (e) {
          if (kDebugMode) {
            debugPrint('Failed to setup highlights listener: ${e.toString()}');
          }
          // Don't rethrow - continue with other listeners
        }
      }

      // Listen for notes changes if enabled
      if (notesEnabled) {
        try {
          _notesSubscription = _supabase
              .from('notes')
              .stream(primaryKey: ['id'])
              .eq('user_id', _currentUserId!)
              .listen((List<Map<String, dynamic>> data) {
                _onNotesChanged(data);
              }, onError: (error) {
                _handleRealtimeSubscriptionError(error, 'notes');
              });
        } catch (e) {
          if (kDebugMode) debugPrint('Failed to setup notes listener: ${e.toString()}');
          // Don't rethrow - continue with other listeners
        }
      }

      // Listen for history changes if enabled
      if (historyEnabled) {
        try {
          _historySubscription = _supabase
              .from('history')
              .stream(primaryKey: ['id'])
              .eq('user_id', _currentUserId!)
              .listen((List<Map<String, dynamic>> data) {
                _onHistoryChanged(data);
              }, onError: (error) {
                _handleRealtimeSubscriptionError(error, 'history');
              });
        } catch (e) {
          if (kDebugMode) debugPrint('Failed to setup history listener: ${e.toString()}');
          // Don't rethrow - continue with other listeners
        }
      }

      // Listen for search history changes if enabled
      if (searchHistoryEnabled) {
        try {
          _searchHistorySubscription = _supabase
              .from('search_history')
              .stream(primaryKey: ['id'])
              .eq('user_id', _currentUserId!)
              .listen((List<Map<String, dynamic>> data) {
                _onSearchHistoryChanged(data);
              }, onError: (error) {
                _handleRealtimeSubscriptionError(error, 'search_history');
              });
        } catch (e) {
          if (kDebugMode) {
            debugPrint('Failed to setup search history listener: ${e.toString()}');
          }
          // Don't rethrow - continue with other listeners
        }
      }
    } catch (e) {
      _isListening = false;
      if (kDebugMode) debugPrint('Error setting up realtime listeners: ${e.toString()}');
      // Don't rethrow - let connectivity monitoring handle reconnection
    }
  }

  // Handle realtime subscription errors with automatic retry
  void _handleRealtimeSubscriptionError(dynamic error, String tableName) async {
    try {
      // Log the error for debugging
      if (kDebugMode) {
        debugPrint('Realtime subscription error for $tableName: ${error.toString()}');
      }

      // Enhanced context with operation details
      final context = {
        'table': tableName,
        'operation': 'realtime_subscription',
        'type': error.runtimeType.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Handle specific RealtimeSubscribeException
      if (error is RealtimeSubscribeException) {
        context['status'] = error.status.toString();
        context['details'] = error.details?.toString() ?? 'no details';
        await ErrorHandler.handleSyncError(error, context: context);

        // For channel errors, attempt to reconnect
        if (error.status == RealtimeSubscribeStatus.channelError) {
          await _retryRealtimeSubscription(tableName);
        }
      } else {
        // Handle other types of errors
        await ErrorHandler.handleSyncError(error, context: context);
      }
    } catch (e) {
      // Ensure we don't crash if error handling itself fails
      if (kDebugMode) {
        debugPrint('Error handling realtime subscription error: ${e.toString()}');
      }
    }
  }

  // Retry realtime subscription for a specific table
  Future<void> _retryRealtimeSubscription(String tableName) async {
    try {
      // Wait before retrying to avoid rapid reconnection attempts
      await Future.delayed(Duration(seconds: syncRetryDelay1Seconds));

      // Check if we're still supposed to be listening and online
      if (!_isListening || !isOnline || _currentUserId == null) {
        return;
      }

      // Check if sync is enabled for this table
      final isEnabled = await _getSyncEnabled('sync$tableName');
      if (!isEnabled) {
        return;
      }

      if (kDebugMode) debugPrint('Retrying realtime subscription for $tableName');

      // Cancel existing subscription if it exists
      switch (tableName) {
        case 'highlights':
          _highlightsSubscription?.cancel();
          _highlightsSubscription = null;
          break;
        case 'notes':
          _notesSubscription?.cancel();
          _notesSubscription = null;
          break;
        case 'history':
          _historySubscription?.cancel();
          _historySubscription = null;
          break;
        case 'search_history':
          _searchHistorySubscription?.cancel();
          _searchHistorySubscription = null;
          break;
      }

      // Attempt to re-subscribe
      try {
        switch (tableName) {
          case 'highlights':
            _highlightsSubscription = _supabase
                .from('highlights')
                .stream(primaryKey: ['id'])
                .eq('user_id', _currentUserId!)
                .listen((List<Map<String, dynamic>> data) {
                  _onHighlightsChanged(data);
                }, onError: (error) {
                  _handleRealtimeSubscriptionError(error, 'highlights');
                });
            break;
          case 'notes':
            _notesSubscription = _supabase
                .from('notes')
                .stream(primaryKey: ['id'])
                .eq('user_id', _currentUserId!)
                .listen((List<Map<String, dynamic>> data) {
                  _onNotesChanged(data);
                }, onError: (error) {
                  _handleRealtimeSubscriptionError(error, 'notes');
                });
            break;
          case 'history':
            _historySubscription = _supabase
                .from('history')
                .stream(primaryKey: ['id'])
                .eq('user_id', _currentUserId!)
                .listen((List<Map<String, dynamic>> data) {
                  _onHistoryChanged(data);
                }, onError: (error) {
                  _handleRealtimeSubscriptionError(error, 'history');
                });
            break;
          case 'search_history':
            _searchHistorySubscription = _supabase
                .from('search_history')
                .stream(primaryKey: ['id'])
                .eq('user_id', _currentUserId!)
                .listen((List<Map<String, dynamic>> data) {
                  _onSearchHistoryChanged(data);
                }, onError: (error) {
                  _handleRealtimeSubscriptionError(error, 'search_history');
                });
            break;
        }

        if (kDebugMode) {
          debugPrint('Successfully re-established realtime subscription for $tableName');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
              'Failed to retry realtime subscription for $tableName: ${e.toString()}');
        }
        // If retry fails, let connectivity monitoring handle it
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error in realtime subscription retry: ${e.toString()}');
    }
  }

  /// Update listener for a specific sync category without affecting others
  Future<void> updateListenerForCategory(String category, bool shouldEnable) async {
    if (_currentUserId == null || !isOnline || _isListening == false) return;

    switch (category) {
      case 'highlights':
        if (shouldEnable && _highlightsSubscription == null) {
          // Setup highlights listener
          try {
            _highlightsSubscription = _supabase
                .from('highlights')
                .stream(primaryKey: ['id'])
                .eq('user_id', _currentUserId!)
                .listen((List<Map<String, dynamic>> data) {
                  _onHighlightsChanged(data);
                }, onError: (error) {
                  _handleRealtimeSubscriptionError(error, 'highlights');
                });
          } catch (e) {
            if (kDebugMode) {
              debugPrint('_onHighlightsChanged Stream exception: ${e.toString()}');
            }
          }
        } else if (!shouldEnable && _highlightsSubscription != null) {
          // Cancel highlights listener
          _highlightsSubscription?.cancel();
          _highlightsSubscription = null;
        }
        break;

      case 'notes':
        if (shouldEnable && _notesSubscription == null) {
          // Setup notes listener
          try {
            _notesSubscription = _supabase
                .from('notes')
                .stream(primaryKey: ['id'])
                .eq('user_id', _currentUserId!)
                .listen((List<Map<String, dynamic>> data) {
                  _onNotesChanged(data);
                }, onError: (error) {
                  _handleRealtimeSubscriptionError(error, 'notes');
                });
          } catch (e) {
            if (kDebugMode) {
              debugPrint('_onNotesChanged Stream exception: ${e.toString()}');
            }
          }
        } else if (!shouldEnable && _notesSubscription != null) {
          // Cancel notes listener
          _notesSubscription?.cancel();
          _notesSubscription = null;
        }
        break;

      case 'history':
        if (shouldEnable && _historySubscription == null) {
          // Setup history listener
          try {
            _historySubscription = _supabase
                .from('history')
                .stream(primaryKey: ['id'])
                .eq('user_id', _currentUserId!)
                .listen((List<Map<String, dynamic>> data) {
                  _onHistoryChanged(data);
                }, onError: (error) {
                  _handleRealtimeSubscriptionError(error, 'history');
                });
          } catch (e) {
            if (kDebugMode) {
              debugPrint('_onHistoryChanged Stream exception: ${e.toString()}');
            }
          }
        } else if (!shouldEnable && _historySubscription != null) {
          // Cancel history listener
          _historySubscription?.cancel();
          _historySubscription = null;
        }
        break;

      case 'search_history':
        if (shouldEnable && _searchHistorySubscription == null) {
          // Setup search history listener
          try {
            _searchHistorySubscription = _supabase
                .from('search_history')
                .stream(primaryKey: ['id'])
                .eq('user_id', _currentUserId!)
                .listen((List<Map<String, dynamic>> data) {
                  _onSearchHistoryChanged(data);
                }, onError: (error) {
                  _handleRealtimeSubscriptionError(error, 'search_history');
                });
          } catch (e) {
            if (kDebugMode) {
              debugPrint('_onSearchHistoryChanged Stream exception: ${e.toString()}');
            }
          }
        } else if (!shouldEnable && _searchHistorySubscription != null) {
          // Cancel search history listener
          _searchHistorySubscription?.cancel();
          _searchHistorySubscription = null;
        }
        break;
      default:
    }
  }

  // Handle highlights changes from Supabase realtime
  void _onHighlightsChanged(List<Map<String, dynamic>> data) async {
    try {
      // Skip processing if bulk operation is in progress
      if (_isBulkOperationInProgress) {
        if (kDebugMode) {
          debugPrint('Skipping realtime highlights changes - bulk operation in progress');
        }
        return;
      }

      // Check if highlights sync is enabled
      final highlightsEnabled = await _getSyncEnabled('syncHighlights');

      if (!highlightsEnabled) {
        return;
      }

      // DEBUG: Log realtime handler invocation
      if (kDebugMode) {
        debugPrint('=== DEBUG _onHighlightsChanged REALTIME ===');
        debugPrint('Received ${data.length} realtime highlight changes');
      }

      // For realtime streams, we need to compare with local data
      await _downloadHighlights(data);
    } catch (e) {
      // Handle sync errors gracefully without throwing unhandled exceptions
      await ErrorHandler.handleSyncError(e, context: {
        'operation': 'download_highlights',
        'type': 'realtime_handler',
        'error_type': e.runtimeType.toString(),
      });
      // Don't rethrow - let the app continue working offline
    }
  }

  // Handle notes changes from Supabase realtime
  void _onNotesChanged(List<Map<String, dynamic>> data) async {
    try {
      // Skip processing if bulk operation is in progress
      if (_isBulkOperationInProgress) {
        if (kDebugMode) {
          debugPrint('Skipping realtime notes changes - bulk operation in progress');
        }
        return;
      }

      // Check if notes sync is enabled
      final notesEnabled = await _getSyncEnabled('syncNotes');

      if (!notesEnabled) {
        return;
      }

      // DEBUG: Log realtime handler invocation
      if (kDebugMode) {
        debugPrint('=== DEBUG _onNotesChanged REALTIME ===');
        debugPrint('Received ${data.length} realtime note changes');
      }

      await _downloadNotes(data);
    } catch (e) {
      // Handle sync errors gracefully without throwing unhandled exceptions
      await ErrorHandler.handleSyncError(e, context: {
        'operation': 'download_notes',
        'type': 'realtime_handler',
        'error_type': e.runtimeType.toString(),
      });
      // Don't rethrow - let the app continue working offline
    }
  }

  // Handle history changes from Supabase realtime
  void _onHistoryChanged(List<Map<String, dynamic>> data) async {
    try {
      // Skip processing if bulk operation is in progress
      if (_isBulkOperationInProgress) {
        if (kDebugMode) {
          debugPrint('Skipping realtime history changes - bulk operation in progress');
        }
        return;
      }

      // Check if history sync is enabled
      final historyEnabled = await _getSyncEnabled('syncHistory');

      if (!historyEnabled) {
        return;
      }

      // DEBUG: Log realtime handler invocation
      if (kDebugMode) {
        debugPrint('=== DEBUG _onHistoryChanged REALTIME ===');
        debugPrint('Received ${data.length} realtime history changes');
      }

      await _downloadHistory(data);
    } catch (e) {
      // Handle sync errors gracefully without throwing unhandled exceptions
      await ErrorHandler.handleSyncError(e, context: {
        'operation': 'download_history',
        'type': 'realtime_handler',
        'error_type': e.runtimeType.toString(),
      });
      // Don't rethrow - let the app continue working offline
    }
  }

  // Handle search history changes from Supabase realtime
  void _onSearchHistoryChanged(List<Map<String, dynamic>> data) async {
    try {
      // Skip processing if bulk operation is in progress
      if (_isBulkOperationInProgress) {
        if (kDebugMode) {
          debugPrint(
              'Skipping realtime search history changes - bulk operation in progress');
        }
        return;
      }

      // Check if search history sync is enabled
      final searchHistoryEnabled = await _getSyncEnabled('syncSearchHistory');

      if (!searchHistoryEnabled) {
        return;
      }

      // DEBUG: Log realtime handler invocation
      if (kDebugMode) {
        debugPrint('=== DEBUG _onSearchHistoryChanged REALTIME ===');
        debugPrint('Received ${data.length} realtime search history changes');
      }

      await _downloadSearchHistory(data);
    } catch (e) {
      // Handle sync errors gracefully without throwing unhandled exceptions
      await ErrorHandler.handleSyncError(e, context: {
        'operation': 'download_search_history',
        'type': 'realtime_handler',
        'error_type': e.runtimeType.toString(),
      });
      // Don't rethrow - let the app continue working offline
    }
  }

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

    // Start bulk operation to prevent listener interference
    _startBulkOperation();

    try {
      // DEBUG: Log sync operation start
      if (kDebugMode) {
        debugPrint('=== DEBUG syncHighlights START ===');
      }

      // Get the baseline time for filtering (highlights added after this will be synced next time)
      final baselineTime = _lastHighlightsSync ?? DateTime.fromMillisecondsSinceEpoch(0);

      // Get local highlights - all for sync logic
      final localHighlights = await HighlightsDatabase.getHighlights();

      // Filter for recent changes if not forced
      final highlightsToSync = localHighlights
          .where((h) =>
              (h['updated_at'] ?? h['created_at'] ?? 0) >
              baselineTime.millisecondsSinceEpoch)
          .toList();

      // Only skip sync if there are no changes to sync
      if (highlightsToSync.isEmpty && !_highlightsNeedSync) {
        // No changes, skip sync
        if (kDebugMode) {
          debugPrint('=== DEBUG syncHighlights SKIPPED === (no changes)');
        }
        return;
      }

      if (highlightsToSync.isNotEmpty) {
        // Get remote highlights for comparison
        final remoteHighlightsResponse =
            await _supabase.from('highlights').select().eq('user_id', _currentUserId!);
        final remoteHighlights =
            List<Map<String, dynamic>>.from(remoteHighlightsResponse);

        // Sync logic: collect highlights that need uploading
        final highlightsToUpload = <Map<String, dynamic>>[];

        for (final highlight in highlightsToSync) {
          final highlightId = highlight['created_at'];
          final remoteDoc =
              remoteHighlights.where((h) => h['created_at'] == highlightId).firstOrNull;

          if (remoteDoc == null) {
            // New highlight - needs upload
            highlightsToUpload.add(highlight);
          } else {
            // Check if local is newer
            final localTime = highlight['updated_at'] ?? highlight['created_at'] ?? 0;
            final remoteTime = remoteDoc['updated_at'] ?? remoteDoc['created_at'] ?? 0;

            if (localTime > remoteTime) {
              highlightsToUpload.add(highlight);
            }
          }
        }

        // Upload highlights
        if (highlightsToSync.isNotEmpty) {
          try {
            if (kDebugMode) {
              debugPrint('Uploading ${highlightsToSync.length} highlights');
            }
            await _batchUploadHighlights(highlightsToSync);
            _lastHighlightsSync = DateTime.now();
            _highlightsNeedSync = false;
          } catch (e) {
            if (kDebugMode) {
              debugPrint('_batchUploadHighlights exception: ${e.toString()}');
            }
            // If batch upload fails, queue each operation individually for retry
            for (final highlight in highlightsToSync) {
              _enqueueFailedOperation(SyncOperation(
                id: highlight['created_at'],
                type: 'highlight',
                operation: 'create',
                data: highlight,
                timestamp:
                    DateTime.fromMillisecondsSinceEpoch(highlight['created_at'] as int),
              ));
            }
          }
        }
      }

      // Download remote changes newer than last sync for bidirectional sync
      final lastSyncMs = _lastHighlightsSyncSaved?.millisecondsSinceEpoch ?? 0;
      final query = _supabase
          .from('highlights')
          .select()
          .eq('user_id', _currentUserId!)
          .gt('updated_at', lastSyncMs);
      final snapshot = await query;
      if (snapshot.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('Downloading ${snapshot.length} highlight changes from remote');
        }
        await _downloadHighlights(snapshot);
      }

      // Always update the sync timestamp after sync operations (both upload and download)
      _lastHighlightsSync = DateTime.now();

      // Save timestamps to preferences - only for highlights
      await _saveLastSyncTimestamps('highlights');

      if (kDebugMode) {
        debugPrint('=== DEBUG syncHighlights COMPLETE ===');
      }
    } finally {
      // End bulk operation to resume listeners
      _endBulkOperation();
    }
  }

  // Download highlights from Supabase to local database
  Future<void> _downloadHighlights(List<Map<String, dynamic>> docs) async {
    try {
      bool hasChanges = false;
      int processedCount = 0;
      int newCount = 0;
      int updateCount = 0;
      int skipCount = 0;

      // DEBUG: Log download operation start (only for problematic data types)
      if (kDebugMode) {
        debugPrint('DEBUG: _downloadHighlights processing ${docs.length} docs');
      }

      // Get local highlights - match by created_at timestamp only
      final localHighlights = await HighlightsDatabase.getHighlights();

      for (final data in docs) {
        // Validate data before processing
        if (!await DataValidation.validateHighlightData(data,
            context: 'download highlight')) {
          // Delete corrupt remote document
          final docId = data['created_at'] as int;

          await deleteRemoteHighlight(docId);

          continue; // Skip processing this document
        }

        final remoteTime = data['updated_at'] as int;
        final remoteCreatedAt = data['created_at'] as int;

        // Match highlights by created_at timestamp
        final localHighlight =
            localHighlights.where((h) => h['created_at'] == remoteCreatedAt).firstOrNull;
        final localTime =
            (localHighlight?['updated_at'] ?? localHighlight?['created_at'] ?? 0) as int;

        // Only update if remote is newer or new
        if (localHighlight == null || remoteTime > localTime) {
          final highlightData = Map<String, dynamic>.from({
            'book': data['book'] as String,
            'chapter': data['chapter'] as int,
            'verse': data['verse'] as int,
            'start': data['start'] as int,
            'end': data['end'] as int,
            'color': data['color'] as int,
            'created_at': remoteCreatedAt,
            'updated_at': remoteTime,
          });

          if (localHighlight == null) {
            // New highlight - add to local
            await HighlightsDatabase.addHighlight(
              book: highlightData['book'],
              chapter: highlightData['chapter'],
              verse: highlightData['verse'],
              start: highlightData['start'],
              end: highlightData['end'],
              color: highlightData['color'],
              createdAt: highlightData['created_at'] as int,
              updatedAt: highlightData['updated_at'] as int,
              skipSync: true,
            );
            newCount++;
          } else {
            // Update existing - use the local ID
            await HighlightsDatabase.updateHighlight(
              id: localHighlight['id'] as int,
              start: highlightData['start'],
              end: highlightData['end'],
              color: highlightData['color'],
              updateAt: highlightData['updated_at'] as int,
            );
            updateCount++;
          }

          hasChanges = true;
          processedCount++;
        } else {
          skipCount++;
        }
      }

      // DEBUG: Log download operation completion (only for problematic data types)
      if (kDebugMode) {
        debugPrint(
            'DEBUG: _downloadHighlights done - new:$newCount, update:$updateCount, skip:$skipCount');
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
      int newCount = 0;
      int updateCount = 0;
      int skipCount = 0;

      // DEBUG: Log download operation start (only for problematic data types)
      if (kDebugMode) {
        debugPrint('DEBUG: _downloadNotes processing ${docs.length} docs');
      }

      for (final data in docs) {
        // Validate data before processing
        if (!await DataValidation.validateNoteData(data, context: 'download note')) {
          // Delete corrupt remote document
          final docId = data['created_at'] as int;

          await deleteRemoteNote(docId);

          continue; // Skip processing this document
        }

        final remoteTime = (data['updated_at'] ?? data['created_at'] ?? 0) as int;

        // For notes, check by verse location since database uses book/chapter/verse
        final book = data['book'] as String;
        final chapter = data['chapter'] as int;
        final verse = data['verse'] as int;
        final noteText = data['note_text'] as String;

        final localNote = await NotesDatabase.getNoteForVerse(book, chapter, verse);
        final localTime =
            (localNote?['updated_at'] ?? localNote?['created_at'] ?? 0) as int;

        if (localNote == null || remoteTime > localTime) {
          // Convert to Delta format before storing
          final deltaNoteText = NoteStorageFormat.ensureDeltaFormat(noteText);

          if (localNote == null) {
            newCount++;
          } else {
            updateCount++;
          }

          await NotesDatabase.addOrUpdateNote(
              book: book,
              chapter: chapter,
              verse: verse,
              noteText: deltaNoteText,
              createdAt: data['created_at'] as int,
              skipSync: true);
          hasChanges = true;
          processedCount++;
        } else {
          skipCount++;
        }
      }

      // DEBUG: Log download operation completion (only for problematic data types)
      if (kDebugMode) {
        debugPrint(
            'DEBUG: _downloadNotes done - new:$newCount, update:$updateCount, skip:$skipCount');
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
      // Get all local history once for efficiency
      final localHistory = await HistoryDatabase.getHistory();
      final localTimestamps =
          Set<int>.from(localHistory.map((h) => h['timestamp'] as int));

      bool hasChanges = false;
      int processedCount = 0;

      for (final data in docs) {
        // Validate data before processing
        if (!await DataValidation.validateHistoryData(data,
            context: 'download history')) {
          // Delete corrupt remote document
          final docId = data['timestamp'];
          await deleteRemoteHistoryItem(docId);
          continue; // Skip processing this document
        }

        final remoteTime = (data['timestamp'] ?? 0) as int;

        // Only add remote history if no local item exists with exact same timestamp
        // If timestamps match, local takes precedence (no duplicate entries)
        if (!localTimestamps.contains(remoteTime)) {
          // Add remote history item with exact remote timestamp
          await HistoryDatabase.addHistory(
            data['book'] as String,
            data['chapter'] as int,
            data['verse'] as int?,
            remoteTime,
            true,
          );
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
      // Get all local search history once for efficiency
      final localSearchHistory = await SearchDatabase.getSearchHistory();
      final localTimestamps =
          Set<int>.from(localSearchHistory.map((h) => h['timestamp'] as int));

      bool hasChanges = false;
      int processedCount = 0;

      for (final data in docs) {
        // Validate data before processing
        if (!await DataValidation.validateSearchHistoryData(data,
            context: 'download search_history')) {
          // Delete corrupt remote document
          final docId = data['timestamp'];
          await deleteRemoteSearchHistoryItem(docId);
          continue; // Skip processing this document
        }

        final remoteTime = (data['timestamp'] ?? 0) as int;

        // Only add remote search history if no local item exists with exact same timestamp
        // If timestamps match, local takes precedence (no duplicate entries)
        if (!localTimestamps.contains(remoteTime)) {
          // Add remote search history item with exact remote timestamp and query
          // Use actual search options from remote data
          try {
            await SearchDatabase.addSearchHistory(
              data['query'] as String,
              data['useRegex'] as bool,
              data['useNearby'] as bool,
              data['useWholeWord'] as bool,
              data['useRedLetter'] as bool,
              data['caseSensitive'] as bool,
              data['bookFilterType'] as String,
              data['customBookFilter'] as String,
              remoteTime,
              skipSync: true, // Add skipSync to prevent feedback loops
            );
            hasChanges = true;
            processedCount++;
          } catch (e) {
            if (kDebugMode) {
              debugPrint(
                  '_downloadSearchHistory addSearchHistory exception: ${e.toString()}');
            }
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

  // Upload single highlight to Supabase
  Future<void> _uploadHighlight(Map<String, dynamic> highlight) async {
    if (_currentUserId == null) return;

    // Validate data before uploading to prevent sending corrupt data to Supabase
    final isValid = await DataValidation.validateBeforeUpload(highlight, 'highlight');
    if (!isValid) {
      return;
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

    try {
      await _supabase.from('highlights').upsert(dataToInsert);
    } catch (e) {
      if (kDebugMode) debugPrint('_uploadHighlight exception: ${e.toString()}');
    }
  }

  // Batch upload multiple highlights to Supabase
  Future<void> _batchUploadHighlights(List<Map<String, dynamic>> highlights) async {
    if (_currentUserId == null || highlights.isEmpty) return;

    // Validate all highlights first
    final validHighlights = <Map<String, dynamic>>[];
    for (final highlight in highlights) {
      final isValid = await DataValidation.validateBeforeUpload(highlight, 'highlight');
      if (isValid) {
        validHighlights.add(highlight);
      }
    }

    if (validHighlights.isEmpty) return;

    // Prepare data for batch insert
    final dataToInsert = validHighlights
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
            })
        .toList();

    try {
      await _supabase.from('highlights').upsert(dataToInsert, onConflict: 'created_at');
    } catch (e) {
      if (kDebugMode) debugPrint('_batchUploadHighlights exception: ${e.toString()}');

      // Re-throw the original error to trigger retry mechanism
      rethrow;
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

    // Start bulk operation to prevent listener interference
    _startBulkOperation();

    try {
      // Get local notes - all for deletion checks
      final localNotes = await NotesDatabase.getNotes();

      // Filter for recent changes if not forced
      final baselineTime = _lastNotesSync ?? DateTime.fromMillisecondsSinceEpoch(0);
      final notesToSync = localNotes
          .where((n) =>
              (n['updated_at'] ?? n['created_at'] ?? 0) >
              baselineTime.millisecondsSinceEpoch)
          .toList();

      // Only skip sync if there are no changes to sync
      if (notesToSync.isEmpty && !_notesNeedSync) {
        // No changes, skip sync
        return;
      }

      if (notesToSync.isNotEmpty) {
        // Get remote notes for comparison
        final remoteNotesResponse =
            await _supabase.from('notes').select().eq('user_id', _currentUserId!);
        final remoteNotes = List<Map<String, dynamic>>.from(remoteNotesResponse);

        // Sync logic: collect notes that need uploading
        final notesToUpload = <Map<String, dynamic>>[];

        for (final note in notesToSync) {
          final localTimestamp = note['created_at'] as int;
          final remoteDoc =
              remoteNotes.where((n) => n['created_at'] == localTimestamp).firstOrNull;

          if (remoteDoc == null) {
            // New note - needs upload
            notesToUpload.add(note);
          } else {
            // Check if local is newer
            final localTime = note['updated_at'] ?? note['created_at'] ?? 0;
            final remoteTime = remoteDoc['updated_at'] ?? remoteDoc['created_at'] ?? 0;

            if (localTime > remoteTime) {
              notesToUpload.add(note);
            }
          }
        }

        // Upload notes
        if (notesToUpload.isNotEmpty) {
          try {
            await _batchUploadNotes(notesToUpload);
            _lastNotesSync = DateTime.now();
            _notesNeedSync = false;
          } catch (e) {
            if (kDebugMode) debugPrint('_batchUploadNotes exception: ${e.toString()}');

            // If batch upload fails, queue each operation individually for retry
            for (final note in notesToUpload) {
              _enqueueFailedOperation(SyncOperation(
                id: note['created_at'],
                type: 'note',
                operation: 'create',
                data: note,
                timestamp: DateTime.fromMillisecondsSinceEpoch(note['created_at'] as int),
              ));
            }
          }
        }
      }

      // Download remote changes newer than last sync for bidirectional sync
      final lastSyncMs = _lastNotesSyncSaved?.millisecondsSinceEpoch ?? 0;
      final query = _supabase
          .from('notes')
          .select()
          .eq('user_id', _currentUserId!)
          .gt('updated_at', lastSyncMs);
      final snapshot = await query;
      if (snapshot.isNotEmpty) {
        await _downloadNotes(snapshot);
      }

      // Always update the sync timestamp after sync operations (both upload and download)
      _lastNotesSync = DateTime.now();

      // Save timestamps to preferences - only for notes
      await _saveLastSyncTimestamps('notes');
    } catch (e) {
      // For critical failures, don't retry - just log
    } finally {
      // End bulk operation to resume listeners
      _endBulkOperation();
    }
  }

  // Upload single note to Supabase
  Future<void> _uploadNote(Map<String, dynamic> note) async {
    if (_currentUserId == null) return;

    // Validate data before uploading to prevent sending corrupt data to Supabase
    final isValid = await DataValidation.validateBeforeUpload(note, 'note');
    if (!isValid) {
      return;
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
    try {
      await _supabase.from('notes').upsert(dataToInsert, onConflict: 'created_at');
    } catch (e) {
      if (kDebugMode) debugPrint('_uploadNote exception: ${e.toString()}');
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

  // Batch upload multiple notes to Supabase
  Future<void> _batchUploadNotes(List<Map<String, dynamic>> notes) async {
    if (_currentUserId == null || notes.isEmpty) return;

    // Validate all notes first
    final validNotes = <Map<String, dynamic>>[];
    for (final note in notes) {
      final isValid = await DataValidation.validateBeforeUpload(note, 'note');
      if (isValid) {
        validNotes.add(note);
      }
    }

    if (validNotes.isEmpty) return;

    // Prepare data for batch insert
    final dataToInsert = validNotes
        .map((note) => {
              'user_id': _currentUserId,
              'book': note['book'],
              'chapter': note['chapter'],
              'verse': note['verse'],
              'note_text': note['note_text'],
              'created_at': note['created_at'],
              'updated_at': note['updated_at'],
            })
        .toList();
    try {
      await _supabase.from('notes').upsert(dataToInsert, onConflict: 'created_at');
    } catch (e) {
      if (kDebugMode) debugPrint('_batchUploadNotes exception: ${e.toString()}');
    }
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

    // Start bulk operation to prevent listener interference
    _startBulkOperation();

    try {
      // Get local search history - all for deletion checks
      final localSearchHistory = await SearchDatabase.getSearchHistory();

      // Filter for recent changes if not forced
      final baselineTime =
          _lastSearchHistorySync ?? DateTime.fromMillisecondsSinceEpoch(0);
      final searchHistoryToSync = localSearchHistory
          .where((h) => (h['timestamp'] ?? 0) > baselineTime.millisecondsSinceEpoch)
          .toList();

      // Only skip sync if there are no changes to sync
      if (searchHistoryToSync.isEmpty && !_searchHistoryNeedSync) {
        // No changes, skip upload
        return;
      }

      if (searchHistoryToSync.isNotEmpty) {
        // Get remote search history
        final remoteSearchHistoryResponse = await _supabase
            .from('search_history')
            .select()
            .eq('user_id', _currentUserId!);
        final remoteSearchHistory =
            List<Map<String, dynamic>>.from(remoteSearchHistoryResponse);

        // Sync logic: collect search history items that need uploading
        final searchHistoryItemsToUpload = <Map<String, dynamic>>[];

        for (final searchHistoryItem in searchHistoryToSync) {
          final localTime = searchHistoryItem['timestamp'] ?? 0;
          final remoteDoc =
              remoteSearchHistory.where((s) => s['timestamp'] == localTime).firstOrNull;

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
            _lastSearchHistorySync = DateTime.now();
            _searchHistoryNeedSync = false;
          } catch (e) {
            if (kDebugMode) {
              debugPrint('_batchUploadSearchHistory exception: ${e.toString()}');
            }

            // If batch upload fails, queue each operation individually for retry
            for (final searchHistoryItem in searchHistoryItemsToUpload) {
              _enqueueFailedOperation(SyncOperation(
                id: searchHistoryItem['timestamp'],
                type: 'search_history',
                operation: 'create',
                data: searchHistoryItem,
                timestamp: DateTime.fromMillisecondsSinceEpoch(
                    searchHistoryItem['timestamp'] as int),
              ));
            }
          }
        }
      }

      // Download remote changes newer than last sync for bidirectional sync
      final lastSyncMs = _lastSearchHistorySyncSaved?.millisecondsSinceEpoch ?? 0;
      final query = _supabase
          .from('search_history')
          .select()
          .eq('user_id', _currentUserId!)
          .gt('timestamp', lastSyncMs);
      final snapshot = await query;
      if (snapshot.isNotEmpty) {
        await _downloadSearchHistory(snapshot);
      }

      // Always update the sync timestamp after sync operations (both upload and download)
      _lastSearchHistorySync = DateTime.now();

      // Save timestamps to preferences - only for search_history
      await _saveLastSyncTimestamps('search_history');
    } finally {
      // End bulk operation to resume listeners
      _endBulkOperation();
    }
  }

  // Batch upload multiple search history items to Supabase
  Future<void> _batchUploadSearchHistory(
      List<Map<String, dynamic>> searchHistoryItems) async {
    if (_currentUserId == null || searchHistoryItems.isEmpty) return;

    // Validate all search history items first
    final validSearchHistoryItems = <Map<String, dynamic>>[];
    for (final searchHistoryItem in searchHistoryItems) {
      final isValid =
          await DataValidation.validateBeforeUpload(searchHistoryItem, 'search_history');
      if (isValid) {
        validSearchHistoryItems.add(searchHistoryItem);
      }
    }

    if (validSearchHistoryItems.isEmpty) return;

    // Prepare data for batch insert
    final dataToInsert = validSearchHistoryItems
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
              'customBookFilter': searchHistoryItem['customBookFilter'] ?? '',
              'timestamp': searchHistoryItem['timestamp'],
            })
        .toList();
    try {
      await _supabase
          .from('search_history')
          .upsert(dataToInsert, onConflict: 'timestamp');
    } catch (e) {
      if (kDebugMode) debugPrint('_batchUploadSearchHistory exception: ${e.toString()}');

      // Re-throw the original error to trigger retry mechanism
      rethrow;
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

    // Start bulk operation to prevent listener interference
    _startBulkOperation();

    try {
      // Get local history - all for deletion checks
      final localHistory = await HistoryDatabase.getHistory();

      // Filter for recent changes if not forced
      final baselineTime = _lastHistorySync ?? DateTime.fromMillisecondsSinceEpoch(0);
      final historyToSync = localHistory
          .where((h) => (h['timestamp'] ?? 0) > baselineTime.millisecondsSinceEpoch)
          .toList();

      // Only skip sync if there are no changes to sync
      if (historyToSync.isEmpty && !_historyNeedSync) {
        // No changes, skip upload
        return;
      }

      if (historyToSync.isNotEmpty) {
        // Get remote history
        final remoteHistoryResponse =
            await _supabase.from('history').select().eq('user_id', _currentUserId!);
        final remoteHistory = List<Map<String, dynamic>>.from(remoteHistoryResponse);

        // Sync logic: collect history items that need uploading
        final historyItemsToUpload = <Map<String, dynamic>>[];

        for (final historyItem in historyToSync) {
          final localTime = historyItem['timestamp'] ?? 0;
          final remoteDoc =
              remoteHistory.where((h) => h['timestamp'] == localTime).firstOrNull;

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
            _lastHistorySync = DateTime.now();
            _historyNeedSync = false;
          } catch (e) {
            if (kDebugMode) debugPrint('_batchUploadHistory exception: ${e.toString()}');

            // If batch upload fails, queue each operation individually for retry
            for (final historyItem in historyItemsToUpload) {
              _enqueueFailedOperation(SyncOperation(
                id: historyItem['timestamp'],
                type: 'history',
                operation: 'create',
                data: historyItem,
                timestamp:
                    DateTime.fromMillisecondsSinceEpoch(historyItem['timestamp'] as int),
              ));
            }
          }
        }
      }

      // Download remote changes newer than last sync for bidirectional sync
      final lastSyncMs = _lastHistorySyncSaved?.millisecondsSinceEpoch ?? 0;
      final query = _supabase
          .from('history')
          .select()
          .eq('user_id', _currentUserId!)
          .gt('timestamp', lastSyncMs);
      final snapshot = await query;
      if (snapshot.isNotEmpty) {
        await _downloadHistory(snapshot);
      }

      // Always update the sync timestamp after sync operations (both upload and download)
      _lastHistorySync = DateTime.now();

      // Save timestamps to preferences - only for history
      await _saveLastSyncTimestamps('history');
    } finally {
      // End bulk operation to resume listeners
      _endBulkOperation();
    }
  }

  // Upload single history item to Supabase
  Future<void> _uploadHistoryItem(Map<String, dynamic> historyItem) async {
    if (_currentUserId == null) return;

    // Validate data before uploading to prevent sending corrupt data to Supabase
    final isValid = await DataValidation.validateBeforeUpload(historyItem, 'history');
    if (!isValid) {
      return;
    }

    final dataToInsert = {
      'user_id': _currentUserId,
      'book': historyItem['book'],
      'chapter': historyItem['chapter'],
      'verse': historyItem['verse'],
      'timestamp': historyItem['timestamp'],
    };

    try {
      await _supabase.from('history').upsert(dataToInsert, onConflict: 'timestamp');
    } catch (e) {
      if (kDebugMode) debugPrint('_uploadHistoryItem exception: ${e.toString()}');
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
  Future<void> _batchUploadHistory(List<Map<String, dynamic>> historyItems) async {
    if (_currentUserId == null || historyItems.isEmpty) return;

    // Validate all history items first
    final validHistoryItems = <Map<String, dynamic>>[];
    for (final historyItem in historyItems) {
      final isValid = await DataValidation.validateBeforeUpload(historyItem, 'history');
      if (isValid) {
        validHistoryItems.add(historyItem);
      }
    }

    if (validHistoryItems.isEmpty) return;

    // Prepare data for batch insert
    final dataToInsert = validHistoryItems
        .map((historyItem) => {
              'user_id': _currentUserId,
              'book': historyItem['book'],
              'chapter': historyItem['chapter'],
              'verse': historyItem['verse'],
              'timestamp': historyItem['timestamp'],
            })
        .toList();

    try {
      await _supabase.from('history').upsert(dataToInsert, onConflict: 'timestamp');
    } catch (e) {
      if (kDebugMode) debugPrint('_batchUploadHistory exception: ${e.toString()}');
    }
  }

  // Sync only recent remote changes since last local sync (app resume scenario)
  Future<void> _syncRecentChangesOnly() async {
    if (_currentUserId == null || !isOnline) return;

    // Start bulk operation to prevent listener interference during incremental sync
    _startBulkOperation();

    try {
      // Check sync settings and download recent changes only
      final highlightsEnabled = await _getSyncEnabled('syncHighlights');
      final notesEnabled = await _getSyncEnabled('syncNotes');
      final historyEnabled = await _getSyncEnabled('syncHistory');
      final searchHistoryEnabled = await _getSyncEnabled('syncSearchHistory');

      // Query and download highlights updated since last sync
      if (highlightsEnabled) {
        final baselineTime = _lastHighlightsSyncSaved?.millisecondsSinceEpoch ?? 0;
        final query = _supabase
            .from('highlights')
            .select()
            .eq('user_id', _currentUserId!)
            .gt('updated_at', baselineTime);
        final snapshot = await query;

        if (snapshot.isNotEmpty) {
          await _downloadHighlights(snapshot);
          _lastHighlightsSync = DateTime.now();
          await _saveLastSyncTimestamps('highlights');
        }
      }

      // Query and download notes updated since last sync
      if (notesEnabled) {
        final lastSyncMs = _lastNotesSyncSaved?.millisecondsSinceEpoch ?? 0;
        final query = _supabase
            .from('notes')
            .select()
            .eq('user_id', _currentUserId!)
            .gt('updated_at', lastSyncMs);
        final snapshot = await query;

        if (snapshot.isNotEmpty) {
          await _downloadNotes(snapshot);
          _lastNotesSync = DateTime.now();
          await _saveLastSyncTimestamps('notes');
        }
      }

      // Query and download history items since last sync
      if (historyEnabled) {
        final lastSyncMs = _lastHistorySyncSaved?.millisecondsSinceEpoch ?? 0;
        final query = _supabase
            .from('history')
            .select()
            .eq('user_id', _currentUserId!)
            .gt('timestamp', lastSyncMs);
        final snapshot = await query;

        if (snapshot.isNotEmpty) {
          await _downloadHistory(snapshot);
          _lastHistorySync = DateTime.now();
          await _saveLastSyncTimestamps('history');
        }
      }

      // Query and download search history items since last sync
      if (searchHistoryEnabled) {
        final lastSyncMs = _lastSearchHistorySyncSaved?.millisecondsSinceEpoch ?? 0;
        final query = _supabase
            .from('search_history')
            .select()
            .eq('user_id', _currentUserId!)
            .gt('timestamp', lastSyncMs);
        final snapshot = await query;

        if (snapshot.isNotEmpty) {
          await _downloadSearchHistory(snapshot);
          _lastSearchHistorySync = DateTime.now();
          await _saveLastSyncTimestamps('search_history');
        }
      }
    } finally {
      // End bulk operation to resume listeners
      _endBulkOperation();
    }
  }

  // Sync all data types
  Future<void> syncAll() async {
    if (_currentUserId == null) {
      if (kDebugMode) debugPrint('syncAll() called but _currentUserId is null');
      return;
    }

    if (kDebugMode) debugPrint('=== DEBUG syncAll() STARTING ===');

    // Start bulk operation to prevent listener interference during full sync
    _startBulkOperation();

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
      // SPECIAL DIAGNOSTIC for the "type 'int' is not a subtype of type 'String'" error
      if (kDebugMode) debugPrint('_syncAll exception: ${e.toString()}');
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

      // End bulk operation to resume listeners
      _endBulkOperation();
    }

    if (kDebugMode) {
      debugPrint('=== DEBUG syncAll() COMPLETE ===');
    }
  }

  // Start connection monitoring using event-driven connectivity changes
  void _startConnectionMonitoring() {
    // Avoid duplicate listeners
    if (_connectivitySubscription != null) return;

    // Listen to connectivity changes instead of polling
    _connectivitySubscription = _connectivity.onConnectivityChanged
        .listen((List<ConnectivityResult> result) async {
      try {
        // Debounce rapid connectivity changes (network fluctuations)
        await Future.delayed(const Duration(seconds: 2));

        final hasConnection = await InternetAccessChecker.hasInternetAccess();

        if (hasConnection && _syncStatus != SyncStatus.online) {
          // Connection restored - test and setup
          try {
            await _checkConnectionAndSetup();
          } catch (e) {
            // Handle connection setup errors gracefully
            if (kDebugMode) {
              debugPrint(
                  'Connection setup failed during connectivity change: ${e.toString()}');
            }
            _syncStatus = SyncStatus.offline;
            syncStatusNotifier.value = _syncStatus;
            await ErrorHandler.handleNetworkError(e);
          }
        } else if (!hasConnection && _syncStatus != SyncStatus.offline) {
          // Connection lost
          _syncStatus = SyncStatus.offline;
          syncStatusNotifier.value = _syncStatus;
          await ErrorHandler.handle('No network connection',
              type: ErrorType.network, severity: ErrorSeverity.medium);
        }
      } catch (e) {
        // Handle connectivity monitoring errors gracefully
        if (kDebugMode) debugPrint('Connectivity monitoring error: ${e.toString()}');
        await ErrorHandler.handleNetworkError(e);
        _syncStatus = SyncStatus.offline;
        syncStatusNotifier.value = _syncStatus;
      }
    });

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
        if (kDebugMode) debugPrint('Initial connectivity check failed: ${e.toString()}');
        _syncStatus = SyncStatus.offline;
        syncStatusNotifier.value = _syncStatus;
      }
    }).catchError((e) async {
      // Handle connectivity check errors gracefully
      if (kDebugMode) debugPrint('Connectivity check error: ${e.toString()}');
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
          .single();
      final remoteDoc = remoteDocResponse;

      // Remote document exists - compare timestamps
      final isValidRemote = await DataValidation.validateHighlightData(remoteDoc,
          context: 'single highlight sync');

      if (isValidRemote) {
        final localTime = highlight['updated_at'] ?? highlight['created_at'] ?? 0;
        final remoteTime = remoteDoc['updated_at'] ?? remoteDoc['created_at'] ?? 0;

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
        final isValid = await DataValidation.validateBeforeUpload(highlight, 'highlight');
        if (isValid) {
          await _uploadHighlight(highlight);
        }
      }
    } catch (e) {
      // Remote document doesn't exist - upload local version
      final isValid = await DataValidation.validateBeforeUpload(highlight, 'highlight');
      if (isValid) {
        await _uploadHighlight(highlight);
      }
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
          .single();
      final remoteDoc = remoteDocResponse;

      // Remote document exists - compare timestamps
      final isValidRemote =
          await DataValidation.validateNoteData(remoteDoc, context: 'single note sync');

      if (isValidRemote) {
        final localTime = note['updated_at'] ?? note['created_at'] ?? 0;
        final remoteTime = remoteDoc['updated_at'] ?? remoteDoc['created_at'] ?? 0;

        if (localTime > remoteTime) {
          // Local is newer - upload local version
          final isValid = await DataValidation.validateBeforeUpload(note, 'note');
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
          .single();

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
        final isValid = await DataValidation.validateBeforeUpload(historyItem, 'history');
        if (isValid) {
          await _uploadHistoryItem(historyItem);
        }
      }
    } catch (e) {
      // Remote document doesn't exist - upload local version
      final isValid = await DataValidation.validateBeforeUpload(historyItem, 'history');
      if (isValid) {
        await _uploadHistoryItem(historyItem);
      }
    }
  }

  // Sync single search history item efficiently with bidirectional conflict resolution
  Future<void> syncSingleSearchHistoryItem(Map<String, dynamic> searchHistoryItem) async {
    if (_currentUserId == null || !isOnline) return;

    final docId = searchHistoryItem['timestamp'] as int;

    try {
      // Query only the specific remote document
      final remoteDocResponse = await _supabase
          .from('search_history')
          .select()
          .eq('user_id', _currentUserId!)
          .eq('timestamp', docId)
          .single();

      final remoteDoc = remoteDocResponse;

      // Remote document exists - compare timestamps
      final isValidRemote = await DataValidation.validateSearchHistoryData(remoteDoc,
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
      final isValid =
          await DataValidation.validateBeforeUpload(searchHistoryItem, 'search_history');
      if (isValid) {
        await _uploadSearchHistoryItem(searchHistoryItem);
      }
    }
  }

  // Unified operation marking method (handles all sync categories: highlight, note, history, search_history)
  Future<void> markOperation(
      String type, int itemId, String operation, Map<String, dynamic> data) async {
    // Set appropriate sync flag based on type
    switch (type) {
      case 'highlight':
        _highlightsNeedSync = true;
        LocalDataChangeNotifier.notifyHighlightsChanged();
        break;
      case 'note':
        _notesNeedSync = true;
        LocalDataChangeNotifier.notifyNotesChanged();
        break;
      case 'history':
        _historyNeedSync = true;
        LocalDataChangeNotifier.notifyHistoryChanged();
        break;
      case 'search_history':
        _searchHistoryNeedSync = true;
        LocalDataChangeNotifier.notifySearchHistoryChanged();
        break;
    }

    // Handle offline queuing
    if (!isOnline || _currentUserId == null) {
      _queuePersistentOperation('${type}_$itemId', type, operation, data);
      _persistQueues();
      return;
    }

    // Handle online sync attempts
    try {
      if (operation == 'delete') {
        // Type-specific delete methods
        switch (type) {
          case 'highlight':
            await deleteRemoteHighlight(data['created_at'] as int);
            break;
          case 'note':
            try {
              await deleteRemoteNote(data['created_at'] as int);
            } catch (e) {
              //
            }
          case 'history':
            await deleteRemoteHistoryItem(itemId);
            break;
          case 'search_history':
            await deleteRemoteSearchHistoryItem(itemId);
            break;
        }
      } else {
        // Type-specific single-item sync methods for create/update
        switch (type) {
          case 'highlight':
            await syncSingleHighlight(data);
            break;
          case 'note':
            await syncSingleNote(data);
            break;
          case 'history':
            await syncSingleHistoryItem(data);
            break;
          case 'search_history':
            await syncSingleSearchHistoryItem(data);
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
          timestamp = DateTime.fromMillisecondsSinceEpoch(timestampValue as int);
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
      await _supabase.from('profiles').select('id').eq('id', _currentUserId!).single();
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

    await _supabase.from('search_history').delete().eq('user_id', _currentUserId!);
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
  Future<void> _uploadSearchHistoryItem(Map<String, dynamic> searchHistoryItem) async {
    if (_currentUserId == null) return;

    // Validate data before uploading to prevent sending corrupt data to Supabase
    final isValid =
        await DataValidation.validateBeforeUpload(searchHistoryItem, 'search_history');
    if (!isValid) {
      return;
    }

    final dataToInsert = {
      'user_id': _currentUserId,
      'query': searchHistoryItem['query'] ?? '',
      'useRegex':
          searchHistoryItem['useRegex'] is bool ? searchHistoryItem['useRegex'] : false,
      'useNearby':
          searchHistoryItem['useNearby'] is bool ? searchHistoryItem['useNearby'] : false,
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

    try {
      await _supabase
          .from('search_history')
          .upsert(dataToInsert, onConflict: 'timestamp');
    } catch (e) {
      if (kDebugMode) debugPrint('_uploadSearchHistoryItem exception: ${e.toString()}');

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
    final operationWithRetryCount =
        operation.copyWith(retryCount: operation.retryCount + 1);
    _retryQueue.add(operationWithRetryCount);

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
        delay = Duration(seconds: syncRetryDelay1Seconds); // First retry: 1 second
        break;
      case 2:
        delay = Duration(seconds: syncRetryDelay2Seconds); // Second retry: 15 seconds
        break;
      case 3:
        delay = Duration(seconds: syncRetryDelay3Seconds); // Third retry: 30 seconds
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

    final operationsToRetry = List<SyncOperation>.from(_retryQueue);
    _retryQueue.clear();

    for (final operation in operationsToRetry) {
      // Check if this operation has exceeded max retries
      if (operation.retryCount >= 3) {
        // Move to persistent queue instead of retrying
        _queuePersistentOperation(
            operation.id, operation.type, operation.operation, operation.data);
        continue;
      }

      try {
        switch (operation.type) {
          case 'highlight':
            if (operation.operation == 'create' || operation.operation == 'update') {
              await _uploadHighlight(operation.data);
            } else if (operation.operation == 'delete') {
              await deleteRemoteHighlight(operation.data['created_at'] as int);
            }
            break;
          case 'note':
            if (operation.operation == 'create' || operation.operation == 'update') {
              await _uploadNote(operation.data);
            } else if (operation.operation == 'delete') {
              await deleteRemoteNote(operation.data['created_at'] as int);
            }
            break;
          case 'history':
            if (operation.operation == 'create' || operation.operation == 'update') {
              await _uploadHistoryItem(operation.data);
            } else if (operation.operation == 'delete') {
              await deleteRemoteHistoryItem(operation.data['timestamp']);
            }
            break;
          case 'search_history':
            if (operation.operation == 'create' || operation.operation == 'update') {
              await _uploadSearchHistoryItem(operation.data);
            } else if (operation.operation == 'delete') {
              await deleteRemoteSearchHistoryItem(operation.data['timestamp']);
            }
            break;
        }

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
    if (_currentUserId != null) {
      for (final operation in _retryQueue) {
        _queueOperation(operation);
      }
    }

    _retryTimer?.cancel();

    // Cancel Supabase listeners
    _highlightsSubscription?.cancel();
    _notesSubscription?.cancel();
    _historySubscription?.cancel();
    _searchHistorySubscription?.cancel();

    // Stop connectivity monitoring
    stopConnectionMonitoring();

    _isListening = false;

    // Properly cleanup stream controllers
    _cleanupStreamControllers();

    _isInitialized = false;
  }

  // Prepare for sign-out - clean up listeners and reset state
  Future<void> prepareForSignOut() async {
    // If user chose to keep data, preserve failed retries by moving them to persistent queues
    if (preserveRetriesOnSignOut) {
      for (final operation in _retryQueue) {
        _queueOperation(operation);
      }
    }

    // Cancel all active listeners
    _highlightsSubscription?.cancel();
    _notesSubscription?.cancel();
    _historySubscription?.cancel();
    _searchHistorySubscription?.cancel();

    _retryTimer?.cancel();

    // Reset flags
    _isListening = false;
    _syncStatus = SyncStatus.offline;
    syncStatusNotifier.value = _syncStatus;
    _highlightsNeedSync = false;
    _notesNeedSync = false;
    _historyNeedSync = false;
    _searchHistoryNeedSync = false;

    // Clear sync timestamps and preferences
    _lastHighlightsSync = null;
    _lastNotesSync = null;
    _lastHistorySync = null;
    _lastSearchHistorySync = null;
    _lastHighlightsSyncSaved = null;
    _lastNotesSyncSaved = null;
    _lastHistorySyncSaved = null;
    _lastSearchHistorySyncSaved = null;

    // Clear persistent queues (they were already persisted above if we preserved retries)
    _highlightsPendingQueue.clear();
    _notesPendingQueue.clear();
    _historyPendingQueue.clear();
    _searchHistoryPendingQueue.clear();

    // Persist empty queues
    await _persistQueues();

    // Clear retry queue
    _retryQueue.clear();

    // Clear cached username on sign out
    await clearCachedUsername();

    // Reset the preservation flag
    preserveRetriesOnSignOut = false;

    _isInitialized = false;
  }

  void restartConnectionMonitoring() {
    _startConnectionMonitoring();
  }
}
