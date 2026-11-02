import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hadirmetrik/api.dart';
import 'package:hadirmetrik/models/face.dart';
import 'package:hadirmetrik/outbox.dart';
import 'package:hadirmetrik/state.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

AppState _state() => AppState(outbox: Outbox(store: MemoryOutboxStore()));

void main() {
  tearDown(() {
    Api.client = http.Client();
    Api.token = null;
  });

  test('a network failure queues the clock event and keeps local time', () async {
    Api.client = MockClient((request) async => throw http.ClientException('offline'));
    final state = _state();

    await state.recordClock();

    expect(state.clockIn, isNotNull);
    expect(state.outbox.length, 1);
    expect(state.pendingSyncCount, 1);
    expect(state.outbox.events.single.type, OutboxEvent.typeClockIn);
    expect(state.clockNotice, contains('perangkat'));
  });

  test('a server rejection is surfaced instead of queued', () async {
    Api.client = MockClient((request) async => _json({
          'success': false,
          'message': 'Absen masuk sudah tercatat hari ini.',
        }, 422));
    final state = _state();

    await state.recordClock();

    expect(state.clockIn, isNull);
    expect(state.outbox.isEmpty, isTrue);
    expect(state.clockNotice, contains('sudah tercatat'));
  });

  test('flushing a batch drops settled events and records the result', () async {
    Api.client = MockClient((request) async {
      final sent = jsonDecode(request.body) as Map<String, dynamic>;
      final events = sent['events'] as List;
      return _json({
        'success': true,
        'data': {
          'id': 7,
          'idempotency_key': sent['idempotency_key'],
          'status': 'completed',
          'total_events': events.length,
          'processed_events': events.length,
          'failed_events': 0,
          'events': [
            for (final event in events)
              {
                'id': 1,
                'client_event_id': event['client_event_id'],
                'type': event['type'],
                'status': 'synced',
              },
          ],
        },
      }, 201);
    });

    final state = _state();
    await state.outbox.load();
    await state.outbox.add(type: OutboxEvent.typeClockIn, occurredAt: DateTime.utc(2026, 11, 1, 1));

    final batch = await state.flushOutbox();

    expect(batch, isNotNull);
    expect(batch!.isCompleted, isTrue);
    expect(state.outbox.isEmpty, isTrue);
    expect(state.pendingSyncCount, 0);
    expect(state.lastSync?.id, 7);
  });

  test('a failed flush keeps the events queued with an attempt count', () async {
    Api.client = MockClient((request) async => throw http.ClientException('offline'));
    final state = _state();
    await state.outbox.load();
    await state.outbox.add(type: OutboxEvent.typeClockIn, occurredAt: DateTime.utc(2026, 11, 1, 1));

    final batch = await state.flushOutbox();

    expect(batch, isNull);
    expect(state.outbox.length, 1);
    expect(state.outbox.events.single.attempts, 1);
    expect(state.pendingSyncCount, 1);
    expect(state.syncError, isNotNull);
  });

  test('a successful online clock-in does not queue anything', () async {
    Api.client = MockClient((request) async => _json({'success': true, 'data': {}}));
    final state = _state();

    await state.recordClock();

    expect(state.clockIn, isNotNull);
    expect(state.outbox.isEmpty, isTrue);
    expect(state.clockNotice, isNull);
  });

  test('a restored complete day cannot create a second clock-out', () async {
    var calls = 0;
    Api.client = MockClient((request) async {
      calls++;
      return _json({'success': true, 'data': {}});
    });
    final state = _state();
    state.clockIn = DateTime(state.now.year, state.now.month, state.now.day, 8);
    state.clockOut = DateTime(state.now.year, state.now.month, state.now.day, 17);

    await state.recordClock();

    expect(calls, 0);
    expect(state.clockNotice, contains('lengkap'));
  });

  test('restoring offline state rehydrates today\'s queued clock-in', () async {
    final state = _state();
    await state.outbox.load();
    final t = DateTime(state.now.year, state.now.month, state.now.day, 7, 50);
    await state.outbox.add(type: OutboxEvent.typeClockIn, occurredAt: t);

    await state.restoreOfflineState();

    expect(state.clockIn, t);
    expect(state.pendingSyncCount, 1);
  });

  test('a 5xx response is queued instead of treated as a refusal', () async {
    Api.client = MockClient((request) async => _json({
          'success': false,
          'message': 'Server sedang bermasalah.',
        }, 503));
    final state = _state();

    await state.recordClock();

    expect(state.outbox.length, 1);
    expect(state.pendingSyncCount, 1);
    expect(state.clockNotice, contains('perangkat'));
  });

  test('an incomplete batch response keeps the same idempotency key', () async {
    final keys = <String>[];
    Api.client = MockClient((request) async {
      if (request.method == 'POST') {
        final sent = jsonDecode(request.body) as Map<String, dynamic>;
        keys.add(sent['idempotency_key'] as String);
        return _json({
          'success': true,
          'data': {
            'id': 9,
            'idempotency_key': sent['idempotency_key'],
            'status': 'received',
            'total_events': (sent['events'] as List).length,
            'processed_events': 0,
            'failed_events': 0,
            'events': [],
          },
        }, 201);
      }
      return _json({'success': false, 'message': 'Belum selesai'}, 503);
    });

    final state = _state();
    await state.outbox.load();
    await state.outbox.add(type: OutboxEvent.typeClockIn, occurredAt: DateTime.utc(2026, 11, 1, 1));

    await state.flushOutbox();
    expect(state.outbox.length, 1);
    expect(state.syncError, isNotNull);

    await state.flushOutbox(force: true);
    expect(keys, hasLength(2));
    expect(keys.first, keys.last);
  });

  test('an automatic flush waits for the retry window', () async {
    var calls = 0;
    Api.client = MockClient((request) async {
      calls++;
      throw http.ClientException('offline');
    });
    final state = _state();
    await state.outbox.load();
    await state.outbox.add(type: OutboxEvent.typeClockIn, occurredAt: DateTime.utc(2026, 11, 1, 1));

    await state.flushOutbox();
    expect(calls, 1);

    await state.flushOutbox();
    expect(calls, 1);
    expect(state.syncError, contains('jadwal'));

    await state.flushOutbox(force: true);
    expect(calls, 2);
  });

  test('revoke falls back to the local template when the body is empty', () async {
    Api.client = MockClient((request) async => _json({'success': true, 'data': {}}));
    final state = _state();
    state.faceTemplates = [FaceTemplate(id: 3, version: 2, status: 'active')];
    state.faceEnrolled = true;

    final ok = await state.revokeFaceTemplate(3);

    expect(ok, isTrue);
    expect(state.faceTemplates.single.status, 'revoked');
    expect(state.faceEnrolled, isFalse);
  });

  test('delete falls back to the local template when the body is empty', () async {
    Api.client = MockClient((request) async => _json({'success': true, 'data': {}}));
    final state = _state();
    state.faceTemplates = [FaceTemplate(id: 4, version: 1, status: 'pending')];

    final ok = await state.deleteFaceTemplate(4);

    expect(ok, isTrue);
    expect(state.faceTemplates.single.status, 'deleted');
  });

  test('pending_review events leave the outbox but stay visible', () async {
    Api.client = MockClient((request) async {
      final sent = jsonDecode(request.body) as Map<String, dynamic>;
      return _json({
        'success': true,
        'data': {
          'id': 10,
          'idempotency_key': sent['idempotency_key'],
          'status': 'completed',
          'total_events': 1,
          'processed_events': 1,
          'failed_events': 0,
          'events': [
            {
              'id': 1,
              'client_event_id': (sent['events'] as List).first['client_event_id'],
              'type': 'clock_in',
              'status': 'pending_review',
            },
          ],
        },
      }, 201);
    });

    final state = _state();
    await state.outbox.load();
    await state.outbox.add(type: OutboxEvent.typeClockIn, occurredAt: DateTime.utc(2026, 11, 1, 1));

    await state.flushOutbox();

    expect(state.outbox.isEmpty, isTrue);
    expect(state.lastReview, hasLength(1));
  });

  test('rejected events are surfaced instead of silently dropped', () async {
    Api.client = MockClient((request) async {
      final sent = jsonDecode(request.body) as Map<String, dynamic>;
      return _json({
        'success': true,
        'data': {
          'id': 11,
          'idempotency_key': sent['idempotency_key'],
          'status': 'failed',
          'total_events': 1,
          'processed_events': 0,
          'failed_events': 1,
          'events': [
            {
              'id': 1,
              'client_event_id': (sent['events'] as List).first['client_event_id'],
              'type': 'clock_out',
              'status': 'rejected',
              'error_message': 'Tidak ada absen masuk aktif pada tanggal tersebut.',
            },
          ],
        },
      }, 201);
    });

    final state = _state();
    await state.outbox.load();
    await state.outbox.add(type: OutboxEvent.typeClockOut, occurredAt: DateTime.utc(2026, 11, 1, 9));

    await state.flushOutbox();

    expect(state.outbox.isEmpty, isTrue);
    expect(state.lastRejected, hasLength(1));
    expect(state.syncError, contains('Tidak ada absen masuk'));
  });

  test('logout clears queued attendance and phase 4 state', () async {
    final state = _state();
    await state.outbox.load();
    await state.outbox.add(type: OutboxEvent.typeClockIn, occurredAt: DateTime.utc(2026, 11, 1, 1));
    state.clockIn = DateTime.utc(2026, 11, 1, 1);
    state.pendingSyncCount = 1;

    await state.logout();

    expect(state.outbox.isEmpty, isTrue);
    expect(state.pendingSyncCount, 0);
    expect(state.clockIn, isNull);
    expect(state.faceTemplates, isEmpty);
  });

  test('a face response that lands after logout is ignored', () async {
    final completer = Completer<http.Response>();
    Api.client = MockClient((request) => completer.future);
    final state = _state();

    final pending = state.loadFaceState();
    await state.logout();
    completer.complete(_json({
      'success': true,
      'data': [
        {'id': 1, 'version': 1, 'status': 'active'},
      ],
    }));
    await pending;

    expect(state.faceTemplates, isEmpty);
  });
}
