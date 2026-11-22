import 'package:flutter_test/flutter_test.dart';
import 'package:hadirmetrik/data.dart';

void main() {
  group('Person.fromApi', () {
    test('parses employee payload from GET /hr/employees', () {
      final json = {
        'id': 10,
        'employee_number': 'HM-0010',
        'full_name': 'Rina Pratiwi',
        'work_email': 'rina@sinarmetrik.co.id',
        'phone_e164': '+6281234567890',
        'division': 'Operasional',
        'division_id': 1,
        'job_title': 'Staf Gudang',
        'manager': 'Dimas Ardiansyah',
        'manager_id': 2,
        'employment_status': 'active',
        'employment_start': '2025-10-15',
        'face_registered_at': '2026-11-01T08:00:00+07:00',
        'has_face': true,
        'location': 'Gudang Kalasan',
      };

      final person = Person.fromApi(json);

      expect(person.dbId, 10);
      expect(person.id, 'HM-0010');
      expect(person.name, 'Rina Pratiwi');
      expect(person.role, 'Staf Gudang');
      expect(person.division, 'Operasional');
      expect(person.location, 'Gudang Kalasan');
      expect(person.faceOk, isTrue);
      expect(person.status, Att.hadir);
      expect(person.initials, 'RP');
    });

    test('maps probation status to Att.menunggu', () {
      final json = {
        'id': 11,
        'employee_number': 'HM-0011',
        'full_name': 'Budi Baru',
        'job_title': 'Magang',
        'division': 'IT',
        'employment_status': 'probation',
        'face_registered_at': null,
        'has_face': false,
      };

      final person = Person.fromApi(json);

      expect(person.status, Att.menunggu);
      expect(person.faceOk, isFalse);
    });
  });
}
