import 'package:flutter_test/flutter_test.dart';
import 'package:hadirmetrik/outbox.dart';

void main() {
  test('events survive a reload through the same store', () async {
    final store = MemoryOutboxStore();
    final first = Outbox(store: store);
    await first.load();

    final event = await first.add(
      type: OutboxEvent.typeClockIn,
      occurredAt: DateTime.utc(2026, 11, 1, 1),
      latitude: -7.7,
      longitude: 110.4,
    );

    expect(event.clientEventId, isNotEmpty);
    expect(first.length, 1);

    final second = Outbox(store: store);
    await second.load();

    expect(second.length, 1);
    expect(second.events.single.clientEventId, event.clientEventId);
    expect(second.events.single.type, OutboxEvent.typeClockIn);
    expect(second.events.single.latitude, -7.7);
    expect(second.events.single.occurredAt.toUtc(), DateTime.utc(2026, 11, 1, 1));
  });

  test('batch key is stable across retries until cleared', () async {
    final store = MemoryOutboxStore();
    final outbox = Outbox(store: store);
    await outbox.load();
    await outbox.add(type: OutboxEvent.typeClockIn, occurredAt: DateTime.utc(2026, 11, 1, 1));

    final key = await outbox.ensureBatchKey();

    final retry = Outbox(store: store);
    await retry.load();
    expect(await retry.ensureBatchKey(), key);

    await retry.clearBatchKey();
    expect(await retry.ensureBatchKey(), isNot(key));
  });

  test('the batch key is persisted before the request is sent', () async {
    final store = MemoryOutboxStore();
    final outbox = Outbox(store: store);
    await outbox.load();
    await outbox.add(type: OutboxEvent.typeClockIn, occurredAt: DateTime.utc(2026, 11, 1, 1));

    await outbox.ensureBatchKey();

    // Read the store directly, without letting another load() hide a missing write.
    expect(store.value, contains('batch_key'));
  });

  test('switching account clears another account\'s queued attendance', () async {
    final store = MemoryOutboxStore();
    final outbox = Outbox(store: store);
    await outbox.setOwner('employee-a');
    await outbox.add(type: OutboxEvent.typeClockIn, occurredAt: DateTime.utc(2026, 11, 1, 1));

    await outbox.setOwner('employee-a');
    expect(outbox.length, 1);

    await outbox.setOwner('employee-b');
    expect(outbox.isEmpty, isTrue);

    final reloaded = Outbox(store: store);
    await reloaded.load();
    expect(reloaded.isEmpty, isTrue);
    expect(reloaded.owner, 'employee-b');
  });

  test('API payload sends an explicit UTC offset', () async {
    final event = OutboxEvent(
      clientEventId: 'evt-1',
      type: OutboxEvent.typeClockIn,
      occurredAt: DateTime(2026, 11, 1, 8),
    );

    expect(event.toApiJson()['occurred_at'], endsWith('Z'));
  });

  test('settled events are removed while failed ones stay queued', () async {
    final outbox = Outbox(store: MemoryOutboxStore());
    await outbox.load();

    final a = await outbox.add(type: OutboxEvent.typeClockIn, occurredAt: DateTime.utc(2026, 11, 1, 1));
    final b = await outbox.add(type: OutboxEvent.typeClockOut, occurredAt: DateTime.utc(2026, 11, 1, 9));

    await outbox.removeSettled([a.clientEventId]);

    expect(outbox.length, 1);
    expect(outbox.events.single.clientEventId, b.clientEventId);
  });

  test('events are ordered by occurrence so clock-in precedes clock-out', () async {
    final outbox = Outbox(store: MemoryOutboxStore());
    await outbox.load();

    await outbox.add(type: OutboxEvent.typeClockOut, occurredAt: DateTime.utc(2026, 11, 1, 9));
    await outbox.add(type: OutboxEvent.typeClockIn, occurredAt: DateTime.utc(2026, 11, 1, 1));

    expect(outbox.events.map((e) => e.type).toList(), [OutboxEvent.typeClockIn, OutboxEvent.typeClockOut]);
  });

  test('recordAttempt tracks retries for the next flush', () async {
    final store = MemoryOutboxStore();
    final outbox = Outbox(store: store);
    await outbox.load();

    final event = await outbox.add(type: OutboxEvent.typeClockIn, occurredAt: DateTime.utc(2026, 11, 1, 1));
    await outbox.recordAttempt([event.clientEventId], 'timeout');

    final reloaded = Outbox(store: store);
    await reloaded.load();
    expect(reloaded.events.single.attempts, 1);
    expect(reloaded.events.single.lastError, 'timeout');
    expect(reloaded.events.single.nextAttemptAt, isNotNull);
  });

  test('automatic retries back off and stop at the attempt cap', () async {
    final outbox = Outbox(store: MemoryOutboxStore());
    await outbox.load();
    final event = await outbox.add(type: OutboxEvent.typeClockIn, occurredAt: DateTime.utc(2026, 11, 1, 1));

    await outbox.recordAttempt([event.clientEventId], 'timeout');
    expect(outbox.dueEvents(), isEmpty);
    expect(outbox.dueEvents(force: true), hasLength(1));
    expect(outbox.nextAttemptAt, isNotNull);

    for (var i = 1; i < Outbox.maxAutoAttempts; i++) {
      await outbox.recordAttempt([event.clientEventId], 'timeout');
    }
    // The schedule has passed, but automatic retries stop after the cap.
    outbox.events.single.nextAttemptAt = DateTime.now().subtract(const Duration(minutes: 1));
    expect(outbox.dueEvents(), isEmpty);
    // A manual retry still sends it.
    expect(outbox.dueEvents(force: true), hasLength(1));
  });

  test('each event keeps its own failure reason', () async {
    final outbox = Outbox(store: MemoryOutboxStore());
    await outbox.load();
    final a = await outbox.add(type: OutboxEvent.typeClockIn, occurredAt: DateTime.utc(2026, 11, 1, 1));
    final b = await outbox.add(type: OutboxEvent.typeClockOut, occurredAt: DateTime.utc(2026, 11, 1, 9));

    await outbox.recordAttempts({
      a.clientEventId: 'masuk gagal',
      b.clientEventId: 'keluar gagal',
    });

    expect(outbox.events.first.lastError, 'masuk gagal');
    expect(outbox.events.last.lastError, 'keluar gagal');
  });

  test('a clock-out never overtakes a clock-in that is backing off', () async {
    final outbox = Outbox(store: MemoryOutboxStore());
    await outbox.load();
    final clockIn = await outbox.add(type: OutboxEvent.typeClockIn, occurredAt: DateTime.utc(2026, 11, 1, 1));
    await outbox.add(type: OutboxEvent.typeClockOut, occurredAt: DateTime.utc(2026, 11, 1, 9));

    await outbox.recordAttempt([clockIn.clientEventId], 'timeout');

    expect(outbox.dueEvents(), isEmpty);

    outbox.events.first.nextAttemptAt = DateTime.now().subtract(const Duration(seconds: 1));
    expect(outbox.dueEvents().map((e) => e.type), [OutboxEvent.typeClockIn, OutboxEvent.typeClockOut]);
  });

  test('a corrupt payload is reset and rewritten', () async {
    final store = MemoryOutboxStore('not-json');
    final outbox = Outbox(store: store);
    await outbox.load();

    expect(outbox.isEmpty, isTrue);
    expect(store.value, contains('"events":[]'));
  });

  test('a failed storage write is not silently ignored', () async {
    final outbox = Outbox(store: _ThrowingStore());
    await outbox.load();

    await expectLater(
      outbox.add(type: OutboxEvent.typeClockIn, occurredAt: DateTime.utc(2026, 11, 1, 1)),
      throwsA(isA<OutboxStorageException>()),
    );
  });
}

class _ThrowingStore implements OutboxStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async => throw const OutboxStorageException('disk penuh');
}
