import 'package:flutter_test/flutter_test.dart';
import 'package:hadirmetrik/models/attendance_sync.dart';
import 'package:hadirmetrik/models/face.dart';

void main() {
  group('FaceEnrollment', () {
    test('parses the pending enrollment payload', () {
      final result = FaceEnrollmentResult.fromJson({
        'enrollment': {
          'id': 12,
          'status': 'pending',
          'provider': 'local_tflite',
          'sample_count': 5,
          'rejection_reason': null,
          'face_template_id': 8,
          'submitted_at': '2026-11-01T08:00:00+07:00',
          'processed_at': null,
        },
        'template': {
          'id': 8,
          'version': 2,
          'status': 'pending',
          'provider': 'local_tflite',
          'enrolled_at': null,
          'revoked_at': null,
          'deleted_at': null,
        },
      });

      expect(result.enrollment.id, 12);
      expect(result.enrollment.isPending, isTrue);
      expect(result.enrollment.sampleCount, 5);
      expect(result.template.version, 2);
      expect(result.template.isPending, isTrue);
      expect(result.template.canRevoke, isTrue);
    });
  });

  group('FaceTemplate', () {
    test('revoked and deleted templates cannot be revoked again', () {
      final revoked = FaceTemplate.fromJson({'id': 1, 'version': 1, 'status': 'revoked'});
      final deleted = FaceTemplate.fromJson({'id': 2, 'version': 1, 'status': 'deleted'});

      expect(revoked.canRevoke, isFalse);
      expect(deleted.canRevoke, isFalse);
      // The backend allows deleting a revoked template, but never a deleted one.
      expect(revoked.canDelete, isTrue);
      expect(deleted.canDelete, isFalse);
    });
  });

  group('SyncBatch', () {
    test('parses batch and per-event results', () {
      final batch = SyncBatch.fromJson({
        'id': 3,
        'idempotency_key': 'batch-001',
        'status': 'partial',
        'device_id': 'device-1',
        'total_events': 2,
        'processed_events': 1,
        'failed_events': 1,
        'received_at': '2026-11-01T08:00:00+07:00',
        'processed_at': '2026-11-01T08:00:01+07:00',
        'events': [
          {
            'id': 1,
            'client_event_id': 'evt-1',
            'type': 'clock_in',
            'occurred_at': '2026-11-01T08:00:00+07:00',
            'status': 'synced',
            'error_message': null,
            'clock_record_id': 9,
          },
          {
            'id': 2,
            'client_event_id': 'evt-2',
            'type': 'clock_out',
            'occurred_at': '2026-11-01T17:00:00+07:00',
            'status': 'rejected',
            'error_message': 'Tidak ada absen masuk aktif pada tanggal tersebut.',
            'clock_record_id': null,
          },
        ],
      });

      expect(batch.id, 3);
      expect(batch.isPartial, isTrue);
      expect(batch.events, hasLength(2));
      expect(batch.events.first.isSettled, isTrue);
      expect(batch.events.last.isSettled, isTrue);
      expect(batch.events.last.errorMessage, contains('Tidak ada'));
    });

    test('sync_failed events stay unsettled for retry', () {
      final event = SyncEventResult.fromJson({
        'client_event_id': 'evt-3',
        'type': 'clock_in',
        'status': 'sync_failed',
        'error_message': 'timeout',
      });

      expect(event.isSettled, isFalse);
    });

    test('pending_review is settled because the server already holds it', () {
      final event = SyncEventResult.fromJson({
        'client_event_id': 'evt-4',
        'type': 'clock_in',
        'status': 'pending_review',
      });

      expect(event.isSettled, isTrue);
      expect(event.isPendingReview, isTrue);
    });
  });
}
