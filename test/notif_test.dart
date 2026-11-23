import 'package:flutter_test/flutter_test.dart';
import 'package:hadirmetrik/data.dart';

void main() {
  group('Notif.fromApi', () {
    final now = DateTime(2026, 11, 23, 15, 30);

    test('maps an unread notification from today', () {
      final n = Notif.fromApi({
        'id': 12,
        'category': 'pengajuan',
        'title': 'Cuti disetujui',
        'body': 'Cuti Tahunan 23 sampai 25 Nov disetujui.',
        'read_at': null,
        'created_at': '2026-11-23T09:05:00+07:00',
      }, now: now);

      expect(n.id, 12);
      expect(n.cat, NCat.pengajuan);
      expect(n.title, 'Cuti disetujui');
      expect(n.body, contains('disetujui'));
      expect(n.read, isFalse);
      expect(n.group, 'HARI INI');
      expect(n.time, hm(DateTime.parse('2026-11-23T09:05:00+07:00').toLocal()));
    });

    test('marks a notification with read_at as read', () {
      final n = Notif.fromApi({
        'id': 13,
        'category': 'tugas',
        'title': 'Tugas baru',
        'read_at': '2026-11-23T10:00:00+07:00',
        'created_at': '2026-11-23T08:00:00+07:00',
      }, now: now);

      expect(n.cat, NCat.tugas);
      expect(n.read, isTrue);
      expect(n.group, 'HARI INI');
    });

    test('groups yesterday and older notifications', () {
      final yesterday = Notif.fromApi({
        'id': 14,
        'category': 'absensi',
        'title': 'Terlambat',
        'created_at': '2026-11-22T08:15:00+07:00',
      }, now: now);
      expect(yesterday.group, 'KEMARIN');
      expect(yesterday.time, hm(DateTime.parse('2026-11-22T08:15:00+07:00').toLocal()));

      final older = Notif.fromApi({
        'id': 15,
        'category': 'info',
        'title': 'Pengumuman',
        'created_at': '2026-11-10T08:15:00+07:00',
      }, now: now);
      expect(older.group, 'SEBELUMNYA');
      expect(older.time, 'Sel, 10 Nov');
    });

    test('falls back to the info category and an empty body', () {
      final n = Notif.fromApi({
        'id': 16,
        'category': 'tidak-dikenal',
        'title': 'Halo',
        'created_at': '2026-11-23T07:00:00+07:00',
      }, now: now);

      expect(n.cat, NCat.info);
      expect(n.body, '');
    });
  });
}
