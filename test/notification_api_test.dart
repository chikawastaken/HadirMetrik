import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hadirmetrik/api.dart';
import 'package:hadirmetrik/session.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/memory_session_store.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  setUp(() {
    Session.store = MemorySessionStore();
    Api.onSessionExpired = null;
  });

  tearDown(() {
    Api.client = http.Client();
    Api.token = null;
    Api.onSessionExpired = null;
    Session.store = SecureSessionStore();
  });

  test('notificationList unwraps the notifications envelope', () async {
    Api.client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/notifications');
      return _json({
        'success': true,
        'data': {
          'notifications': [
            {'id': 1, 'category': 'tugas', 'title': 'Tugas baru'},
          ],
          'unread_count': 1,
        },
      });
    });

    final data = await Api.notificationList();

    expect(data['notifications'], hasLength(1));
    expect(data['unread_count'], 1);
  });

  test('notificationRead posts to the read endpoint', () async {
    Api.client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/notifications/7/read');
      return _json({
        'success': true,
        'data': {
          'notification': {'id': 7, 'read_at': '2026-11-23T08:00:00+00:00'},
        },
      });
    });

    final data = await Api.notificationRead(7);

    expect(data['notification'], isA<Map>());
  });

  test('notificationReadAll posts to the read-all endpoint', () async {
    Api.client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/notifications/read-all');
      return _json({
        'success': true,
        'data': {'updated': 3},
      });
    });

    final data = await Api.notificationReadAll();

    expect(data['updated'], 3);
  });
}
