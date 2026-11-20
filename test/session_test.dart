import 'package:flutter_test/flutter_test.dart';
import 'package:hadirmetrik/session.dart';

import 'support/memory_session_store.dart';

void main() {
  test('stored session round-trips through JSON', () {
    final session = StoredSession(
      token: '3|token',
      accountKey: 'u:2',
      expiresAt: DateTime.utc(2026, 11, 27, 10),
      onboarded: true,
      user: const {
        'id': 2,
        'name': 'Karyawan Contoh',
        'email': 'karyawan@example.com',
        'role': 'employee',
        'must_change_password': false,
      },
    );

    final restored = StoredSession.fromJson(session.toJson());

    expect(restored.token, session.token);
    expect(restored.accountKey, session.accountKey);
    expect(restored.expiresAt, session.expiresAt);
    expect(restored.onboarded, isTrue);
    expect(restored.user['role'], 'employee');
    expect(restored.isHr, isFalse);
  });

  test('admin role is treated as HR', () {
    final session = StoredSession(
      token: 't',
      user: const {'role': 'admin'},
    );

    expect(session.isHr, isTrue);
  });

  test('session with a past expiry is expired', () {
    final session = StoredSession(
      token: 't',
      user: const {'role': 'employee'},
      expiresAt: DateTime.utc(2026, 11, 1),
    );

    expect(
      resolveRestore(session, DateTime.utc(2026, 11, 20)),
      SessionRestore.expired,
    );
  });

  test('session without expiry is ready', () {
    final session = StoredSession(
      token: 't',
      user: const {'role': 'employee'},
    );

    expect(
      resolveRestore(session, DateTime.utc(2026, 11, 20)),
      SessionRestore.ready,
    );
  });

  test('missing session needs login', () {
    expect(resolveRestore(null, DateTime.utc(2026, 11, 20)), SessionRestore.none);
  });

  test('memory store saves, marks onboarding, and clears', () async {
    final store = MemorySessionStore();
    final session = StoredSession(
      token: 't',
      user: const {'role': 'employee'},
    );

    await store.write(session);
    expect((await store.read())?.token, 't');

    await store.clear();
    expect(await store.read(), isNull);
  });
}
