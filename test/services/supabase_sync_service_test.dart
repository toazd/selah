import 'package:flutter_test/flutter_test.dart';
import 'package:selah/services/supabase_sync_service.dart';

void main() {
  group('SupabaseSyncService.buildReconciliationActions', () {
    test('repairs UUID when remote row exists and local UUID is missing', () {
      final actions = SupabaseSyncService.buildReconciliationActions(
        localRecords: const [
          {
            'id': 1,
            'created_at': 1773428773310,
            'uuid': null,
          }
        ],
        remoteUuidByNaturalKey: const {1773428773310: 'remote-note-uuid'},
        pendingNaturalKeys: const <int>{},
        naturalKeyColumn: 'created_at',
      );

      expect(actions, hasLength(1));
      expect(actions.single.operation, 'repair_uuid');
      expect(actions.single.uuid, 'remote-note-uuid');
    });

    test('uploads local record when remote row is missing and local UUID is missing', () {
      final actions = SupabaseSyncService.buildReconciliationActions(
        localRecords: const [
          {
            'id': 1,
            'created_at': 1773428773310,
            'uuid': '',
          }
        ],
        remoteUuidByNaturalKey: const <int, String>{},
        pendingNaturalKeys: const <int>{},
        naturalKeyColumn: 'created_at',
      );

      expect(actions, hasLength(1));
      expect(actions.single.operation, 'upload_local');
    });

    test('deletes local record when remote row is missing and local UUID exists', () {
      final actions = SupabaseSyncService.buildReconciliationActions(
        localRecords: const [
          {
            'id': 1,
            'created_at': 1773428773310,
            'uuid': 'local-note-uuid',
          }
        ],
        remoteUuidByNaturalKey: const <int, String>{},
        pendingNaturalKeys: const <int>{},
        naturalKeyColumn: 'created_at',
      );

      expect(actions, hasLength(1));
      expect(actions.single.operation, 'delete_local');
    });

    test('keeps pending local uploads out of reconciliation actions', () {
      final actions = SupabaseSyncService.buildReconciliationActions(
        localRecords: const [
          {
            'id': 1,
            'created_at': 1773428773310,
            'uuid': null,
          }
        ],
        remoteUuidByNaturalKey: const <int, String>{},
        pendingNaturalKeys: const {1773428773310},
        naturalKeyColumn: 'created_at',
      );

      expect(actions, isEmpty);
    });
  });

  group('SupabaseSyncService.shouldAdvanceSyncTimestamp', () {
    test('returns false when note uploads are still unresolved', () {
      final shouldAdvance = SupabaseSyncService.shouldAdvanceSyncTimestamp(
        failedRecoveryActions: const <SyncReconciliationAction>[],
        failedUploadNaturalKeys: const {1773428773310},
        pendingNaturalKeys: const <int>{},
      );

      expect(shouldAdvance, isFalse);
    });

    test('returns false when recovery work is still pending in the queue', () {
      final shouldAdvance = SupabaseSyncService.shouldAdvanceSyncTimestamp(
        failedRecoveryActions: const <SyncReconciliationAction>[],
        failedUploadNaturalKeys: const <int>{},
        pendingNaturalKeys: const {1773428773310},
      );

      expect(shouldAdvance, isFalse);
    });

    test('returns true when recovery and uploads are complete', () {
      final shouldAdvance = SupabaseSyncService.shouldAdvanceSyncTimestamp(
        failedRecoveryActions: const <SyncReconciliationAction>[],
        failedUploadNaturalKeys: const <int>{},
        pendingNaturalKeys: const <int>{},
      );

      expect(shouldAdvance, isTrue);
    });
  });
}
