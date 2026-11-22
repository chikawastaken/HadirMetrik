import 'package:flutter_test/flutter_test.dart';
import 'package:hadirmetrik/data.dart';

void main() {
  group('leavePayload', () {
    test('maps annual leave to cuti/tahunan', () {
      final payload = leavePayload(
        type: LeaveType.tahunan,
        start: DateTime(2026, 11, 23),
        end: DateTime(2026, 11, 25),
        reason: 'Acara keluarga besar di luar kota.',
      );

      expect(payload['request_type'], 'cuti');
      expect(payload['category'], 'tahunan');
      expect(payload['start_date'], '2026-11-23');
      expect(payload['end_date'], '2026-11-25');
      expect(payload['day_portion'], 'full');
      expect(payload.containsKey('special_reason'), isFalse);
    });

    test('maps sick permission to izin/sakit with half day', () {
      final payload = leavePayload(
        type: LeaveType.sakit,
        start: DateTime(2026, 11, 24),
        reason: 'Demam dan perlu istirahat di rumah.',
        portion: 1,
      );

      expect(payload['request_type'], 'izin');
      expect(payload['category'], 'sakit');
      expect(payload['end_date'], '2026-11-24');
      expect(payload['day_portion'], 'morning');
    });

    test('maps special leave with the selected reason', () {
      final payload = leavePayload(
        type: LeaveType.khusus,
        start: DateTime(2026, 11, 24),
        reason: 'Menghadiri acara pernikahan keluarga.',
        specialReason: 'menikah',
      );

      expect(payload['request_type'], 'cuti');
      expect(payload['category'], 'khusus');
      expect(payload['special_reason'], 'menikah');
    });

    test('maps overtime without day fields', () {
      final payload = leavePayload(
        type: LeaveType.lembur,
        start: DateTime(2026, 11, 24),
        reason: 'Menyelesaikan rekonsiliasi stok akhir bulan.',
        overtimeHours: 3.5,
      );

      expect(payload['request_type'], 'lembur');
      expect(payload['overtime_date'], '2026-11-24');
      expect(payload['overtime_hours'], 3.5);
      expect(payload.containsKey('category'), isFalse);
      expect(payload.containsKey('start_date'), isFalse);
    });
  });

  group('LeaveReq.fromApi', () {
    test('maps an approved annual leave with its approval steps', () {
      final req = LeaveReq.fromApi({
        'id': 7,
        'employee_id': 3,
        'employee_name': 'Rina Pratiwi',
        'division': 'Operasional',
        'request_type': 'cuti',
        'category': 'tahunan',
        'start_date': '2026-11-23',
        'end_date': '2026-11-25',
        'day_portion': 'full',
        'day_count': 3,
        'reason': 'Acara keluarga besar di luar kota.',
        'status': 'approved',
        'submitted_at': '2026-11-20T09:00:00+07:00',
        'approvals': [
          {
            'id': 1,
            'round': 1,
            'step_order': 1,
            'approver_role': 'supervisor',
            'approver_name': 'Dimas Ardiansyah',
            'status': 'approved',
            'decided_at': '2026-11-20T10:00:00+07:00',
          },
          {
            'id': 2,
            'round': 1,
            'step_order': 2,
            'approver_role': 'hr',
            'approver_name': 'Sari Wulandari',
            'status': 'approved',
            'decided_at': '2026-11-21T08:00:00+07:00',
          },
        ],
      });

      expect(req.id, 7);
      expect(req.type, LeaveType.tahunan);
      expect(req.status, LeaveStatus.disetujui);
      expect(req.canCancel, isFalse);
      expect(req.range, contains('23'));
      expect(req.range, contains('3 hari'));
      expect(req.steps, hasLength(3));
      expect(req.steps.last.$1, contains('HR'));
    });

    test('maps a submitted sick permission as pending and cancellable', () {
      final req = LeaveReq.fromApi({
        'id': 9,
        'employee_name': 'Rina Pratiwi',
        'request_type': 'izin',
        'category': 'sakit',
        'start_date': '2026-11-24',
        'end_date': '2026-11-24',
        'day_portion': 'morning',
        'day_count': 0.5,
        'reason': 'Demam dan perlu istirahat di rumah.',
        'status': 'submitted',
        'submitted_at': '2026-11-22T09:00:00+07:00',
        'approvals': [],
      });

      expect(req.type, LeaveType.sakit);
      expect(req.status, LeaveStatus.menunggu);
      expect(req.canCancel, isTrue);
      expect(req.range, contains('setengah hari'));
    });

    test('maps overtime and a revision request', () {
      final req = LeaveReq.fromApi({
        'id': 11,
        'employee_name': 'Rina Pratiwi',
        'request_type': 'lembur',
        'overtime_date': '2026-11-24',
        'overtime_hours': 3.5,
        'reason': 'Menyelesaikan rekonsiliasi stok akhir bulan.',
        'status': 'needs_revision',
        'approvals': [
          {
            'id': 3,
            'round': 1,
            'step_order': 1,
            'approver_role': 'supervisor',
            'status': 'needs_revision',
            'note': 'Lampirkan surat tugas.',
          },
        ],
      });

      expect(req.type, LeaveType.lembur);
      expect(req.status, LeaveStatus.revisi);
      expect(req.range, contains('3,5 jam'));
      expect(req.note, contains('Lampirkan surat tugas.'));
    });
  });
}
