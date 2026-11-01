import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hadirmetrik/api.dart';
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
}
