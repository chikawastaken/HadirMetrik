import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hadirmetrik/api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  tearDown(() {
    Api.client = http.Client();
    Api.token = null;
  });

  test('getFaceTemplates accepts the list envelope', () async {
    Api.client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/face/templates');
      return _json({
        'success': true,
        'data': [
          {'id': 8, 'version': 2, 'status': 'pending'},
        ],
      });
    });

    final templates = await Api.getFaceTemplates();

    expect(templates, hasLength(1));
    expect((templates.first as Map<String, dynamic>)['version'], 2);
  });

  test('submitFaceEnrollment posts the sample count and provider', () async {
    late Map<String, dynamic> sent;
    Api.client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/face/enroll');
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return _json({
        'success': true,
        'data': {
          'enrollment': {'id': 1, 'status': 'pending', 'sample_count': 5},
          'template': {'id': 2, 'version': 1, 'status': 'pending'},
        },
      }, 201);
    });

    final result = await Api.submitFaceEnrollment(sampleCount: 5, provider: 'local_tflite');

    expect(sent['sample_count'], 5);
    expect(sent['provider'], 'local_tflite');
    expect(result['enrollment']['status'], 'pending');
  });

  test('deleteFaceTemplate uses DELETE', () async {
    Api.client = MockClient((request) async {
      expect(request.method, 'DELETE');
      expect(request.url.path, '/api/v1/face/templates/2');
      return _json({
        'success': true,
        'data': {'id': 2, 'version': 1, 'status': 'deleted'},
      });
    });

    final deleted = await Api.deleteFaceTemplate(2);

    expect(deleted['status'], 'deleted');
  });

  test('syncAttendance posts the batch key and events', () async {
    late Map<String, dynamic> sent;
    Api.client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/sync/attendance');
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return _json({
        'success': true,
        'data': {
          'id': 3,
          'idempotency_key': sent['idempotency_key'],
          'status': 'completed',
          'total_events': 1,
          'processed_events': 1,
          'failed_events': 0,
          'events': [
            {'id': 1, 'client_event_id': 'evt-1', 'type': 'clock_in', 'status': 'synced'},
          ],
        },
      }, 201);
    });

    final batch = await Api.syncAttendance(
      idempotencyKey: 'batch-1',
      deviceId: 'device-1',
      events: [
        {
          'client_event_id': 'evt-1',
          'type': 'clock_in',
          'occurred_at': '2026-11-01T08:00:00+07:00',
        },
      ],
    );

    expect(sent['idempotency_key'], 'batch-1');
    expect(sent['device_id'], 'device-1');
    expect(sent['events'], hasLength(1));
    expect(batch['status'], 'completed');
  });

  test('server error envelope becomes ApiError with its status', () async {
    Api.client = MockClient((request) async => _json({
          'success': false,
          'message': 'Template wajah tidak ditemukan.',
        }, 404));

    expect(
      () => Api.revokeFaceTemplate(99),
      throwsA(isA<ApiError>()
          .having((e) => e.message, 'message', contains('tidak ditemukan'))
          .having((e) => e.statusCode, 'statusCode', 404)
          .having((e) => e.isServerError, 'isServerError', isFalse)),
    );
  });

  test('5xx responses are marked retryable', () async {
    Api.client = MockClient((request) async => _json({
          'success': false,
          'message': 'Gateway timeout',
        }, 504));

    expect(
      () => Api.clockIn(),
      throwsA(isA<ApiError>()
          .having((e) => e.statusCode, 'statusCode', 504)
          .having((e) => e.isServerError, 'isServerError', isTrue)),
    );
  });

  test('login remembers the account key used to scope the outbox', () async {
    Api.client = MockClient((request) async => _json({
          'success': true,
          'data': {'token': 't', 'user': {'role': 'employee'}},
        }));

    await Api.login('  Karyawan@Example.com ', 'secret');

    expect(Api.accountKey, 'karyawan@example.com');
  });

  test('login prefers the user id so the queue survives a different identifier', () async {
    Api.client = MockClient((request) async => _json({
          'success': true,
          'data': {
            'token': 't',
            'user': {'id': 42, 'email': 'karyawan@example.com', 'role': 'employee'},
          },
        }));

    await Api.login('12345678', 'secret');

    expect(Api.accountKey, 'u:42');
  });
}
