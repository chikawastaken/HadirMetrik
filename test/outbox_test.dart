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

    final key = outbox.batchKey;

    final retry = Outbox(store: store);
    await retry.load();
    expect(retry.batchKey, key);

    await retry.clearBatchKey();
    expect(retry.batchKey, isNot(key));
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
  });
}
