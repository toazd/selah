import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:selah/database/history_database.dart';
import 'package:selah/database/notes_database.dart';
import 'package:selah/database/search_database.dart';
import 'package:selah/services/supabase_sync_service.dart';
import 'package:selah/utils/platform_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('selah_sync_test_');
    PlatformPaths.debugSetUserDataDirectoryOverride(tempDir.path);
  });

  tearDownAll(() {
    PlatformPaths.debugSetUserDataDirectoryOverride(null);
  });

  setUp(() async {
    final notesDb = await NotesDatabase.getDatabase();
    await notesDb.delete('user_notes');

    final historyDb = await HistoryDatabase.getDatabase();
    await historyDb.delete('history');
    await historyDb.delete('user_cache');

    final searchDb = await SearchDatabase.getDatabase();
    await searchDb.delete('search_history');
  });

  test('upsertNoteFromSync backfills UUID onto existing note', () async {
    const createdAt = 1700000000000;
    const remoteUpdatedAt = 1700000001000;

    await NotesDatabase.addOrUpdateNote(
      book: 'Gen',
      chapter: 1,
      verse: 1,
      noteText: 'Initial note',
      createdAt: createdAt,
      skipSync: true,
    );

    await NotesDatabase.upsertNoteFromSync(
      book: 'Gen',
      chapter: 1,
      verse: 1,
      noteText: 'Initial note',
      createdAt: createdAt,
      updatedAt: remoteUpdatedAt,
      uuid: 'note-uuid',
    );

    final note = await NotesDatabase.getNoteForVerse('Gen', 1, 1);
    expect(note, isNotNull);
    expect(note!['uuid'], 'note-uuid');
    expect(note['created_at'], createdAt);
    expect(note['updated_at'], remoteUpdatedAt);
    expect((await NotesDatabase.getNotes()).length, 1);
  });

  test('upsertHistoryFromSync updates UUID on existing timestamp row',
      () async {
    const timestamp = 1700000002000;

    await HistoryDatabase.addHistory('Gen', 1, 2, timestamp, true);
    await HistoryDatabase.upsertHistoryFromSync(
      'Gen',
      1,
      2,
      timestamp,
      uuid: 'history-uuid',
    );

    final history = await HistoryDatabase.getHistory();
    expect(history, hasLength(1));
    expect(history.single['timestamp'], timestamp);
    expect(history.single['uuid'], 'history-uuid');
  });

  test(
      'upsertSearchHistoryFromSync updates existing timestamp row without duplicate insert',
      () async {
    const timestamp = 1700000003000;

    await SearchDatabase.addSearchHistory(
      'grace',
      false,
      false,
      true,
      false,
      false,
      'All Books',
      '',
      timestamp,
      skipSync: true,
    );

    await SearchDatabase.upsertSearchHistoryFromSync(
      'mercy',
      true,
      false,
      true,
      false,
      false,
      'Custom Range',
      'Gen-Exo',
      timestamp,
      uuid: 'search-uuid',
    );

    final searchHistory = await SearchDatabase.getSearchHistory();
    expect(searchHistory, hasLength(1));
    expect(searchHistory.single['query'], 'mercy');
    expect(searchHistory.single['useRegex'], isTrue);
    expect(searchHistory.single['bookFilterType'], 'Custom Range');
    expect(searchHistory.single['customBookFilter'], 'Gen-Exo');
    expect(searchHistory.single['uuid'], 'search-uuid');
  });

  test(
      'buildReconciliationActions repairs missing UUID when remote match exists',
      () {
    final actions = SupabaseSyncService.buildReconciliationActions(
      localRecords: const [
        {'id': 1, 'created_at': 1700, 'uuid': null},
      ],
      remoteUuidByNaturalKey: const {1700: 'remote-uuid'},
      pendingNaturalKeys: const <int>{},
      naturalKeyColumn: 'created_at',
    );

    expect(actions, hasLength(1));
    expect(actions.single.operation, 'repair_uuid');
    expect(actions.single.localId, 1);
    expect(actions.single.uuid, 'remote-uuid');
  });

  test(
      'buildReconciliationActions preserves missing UUID row when create is pending',
      () {
    final actions = SupabaseSyncService.buildReconciliationActions(
      localRecords: const [
        {'id': 2, 'timestamp': 1800, 'uuid': null},
      ],
      remoteUuidByNaturalKey: const {},
      pendingNaturalKeys: const {1800},
      naturalKeyColumn: 'timestamp',
    );

    expect(actions, isEmpty);
  });

  test(
      'buildReconciliationActions deletes missing UUID row when remote is absent',
      () {
    final actions = SupabaseSyncService.buildReconciliationActions(
      localRecords: const [
        {'id': 3, 'timestamp': 1900, 'uuid': null},
      ],
      remoteUuidByNaturalKey: const {},
      pendingNaturalKeys: const <int>{},
      naturalKeyColumn: 'timestamp',
    );

    expect(actions, hasLength(1));
    expect(actions.single.operation, 'delete_local');
    expect(actions.single.localId, 3);
    expect(actions.single.uuid, isNull);
  });
}
