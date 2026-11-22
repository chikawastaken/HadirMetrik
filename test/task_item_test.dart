import 'package:flutter_test/flutter_test.dart';
import 'package:hadirmetrik/data.dart';

void main() {
  group('TaskItem.fromApi', () {
    test('parses list shape with assignment and task keys', () {
      final json = {
        'assignment': {
          'id': 101,
          'task_id': 12,
          'status': 'in_progress',
          'progress_percent': 65,
          'checklist': [
            {'key': 'c1', 'label': 'Cek stok barang', 'done': true},
            {'key': 'c2', 'label': 'Foto rak display', 'done': false},
          ],
        },
        'task': {
          'id': 12,
          'title': 'Audit Stok Kalasan',
          'description': 'Lakukan audit stok harian.',
          'priority': 'high',
          'status': 'assigned',
          'requires_photo_proof': true,
          'due_at': '2026-11-25T17:00:00+07:00',
          'created_at': '2026-11-20T08:00:00+07:00',
          'created_by': 'Sari Wulandari',
        },
      };

      final item = TaskItem.fromApi(json);

      expect(item.id, 12);
      expect(item.title, 'Audit Stok Kalasan');
      expect(item.desc, 'Lakukan audit stok harian.');
      expect(item.prio, Prio.tinggi);
      expect(item.status, TaskStatus.proses);
      expect(item.progress, 0.65);
      expect(item.checklist, hasLength(2));
      expect(item.checklist.first.label, 'Cek stok barang');
      expect(item.checklist.first.done, isTrue);
      expect(item.checklist.last.label, 'Foto rak display');
      expect(item.checklist.last.done, isFalse);
      expect(item.requiresPhotoProof, isTrue);
      expect(item.from, 'Sari Wulandari');
    });

    test('parses detail shape with submissions, comments, and attachments', () {
      final json = {
        'id': 15,
        'title': 'Pembersihan Area Bongkar Muat',
        'description': 'Pastikan jalur forklift bersih.',
        'priority': 'medium',
        'status': 'in_progress',
        'requires_photo_proof': false,
        'due_at': '2026-11-22T15:00:00+07:00',
        'created_at': '2026-11-21T09:00:00+07:00',
        'created_by': 'Budi HR',
        'assignments': [
          {
            'id': 202,
            'employee_name': 'Rina Pratiwi',
            'status': 'revision_required',
            'progress_percent': 80,
            'checklist': [
              {'key': 'c1', 'label': 'Sapu lantai', 'done': true},
            ],
          },
        ],
        'submissions': [
          {
            'id': 50,
            'note': 'Mohon review',
            'review_status': 'revision_requested',
            'review_note': 'Jalur timur masih ada palet.',
          },
        ],
        'comments': [
          {
            'author_name': 'Budi HR',
            'body': 'Segera bereskan sebelum jam 15 ya.',
            'created_at': '2026-11-21T10:00:00+07:00',
          },
        ],
        'attachments': [
          {
            'original_name': 'sop_kebersihan.pdf',
            'size_bytes': 204800,
          },
        ],
      };

      final item = TaskItem.fromApi(json);

      expect(item.id, 15);
      expect(item.title, 'Pembersihan Area Bongkar Muat');
      expect(item.status, TaskStatus.revisi);
      expect(item.progress, 0.8);
      expect(item.revisionNote, 'Jalur timur masih ada palet.');
      expect(item.latestSubmissionId, 50);
      expect(item.comments, hasLength(1));
      expect(item.comments.first.who, 'Budi HR');
      expect(item.comments.first.text, 'Segera bereskan sebelum jam 15 ya.');
      expect(item.attachments, hasLength(1));
      expect(item.attachments.first.$1, 'sop_kebersihan.pdf');
      expect(item.requiresPhotoProof, isFalse);
    });

    test('maps status correctly from assignment status', () {
      final reviewJson = {
        'title': 'Test Review',
        'assignments': [
          {'status': 'submitted', 'progress_percent': 100},
        ],
      };
      final selesaiJson = {
        'title': 'Test Selesai',
        'assignments': [
          {'status': 'completed', 'progress_percent': 100},
        ],
      };

      expect(TaskItem.fromApi(reviewJson).status, TaskStatus.review);
      expect(TaskItem.fromApi(selesaiJson).status, TaskStatus.selesai);
    });
  });
}
