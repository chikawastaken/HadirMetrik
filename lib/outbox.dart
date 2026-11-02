import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// A clock event captured on the device before the server has accepted it.
class OutboxEvent {
  static const typeClockIn = 'clock_in';
  static const typeClockOut = 'clock_out';

  OutboxEvent({
    required this.clientEventId,
    required this.type,
    required this.occurredAt,
    this.latitude,
    this.longitude,
    this.attempts = 0,
    this.lastError,
    this.nextAttemptAt,
  });

  final String clientEventId;
  final String type;
  final DateTime occurredAt;
  final double? latitude;
  final double? longitude;
  int attempts;
  String? lastError;

  /// Earliest time an automatic retry may send this event again.
  DateTime? nextAttemptAt;

  Map<String, dynamic> toJson() => {
        'client_event_id': clientEventId,
        'type': type,
        'occurred_at': occurredAt.toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        'attempts': attempts,
        'last_error': lastError,
        'next_attempt_at': nextAttemptAt?.toUtc().toIso8601String(),
      };

  /// Shape expected by `POST /sync/attendance`.
  ///
  /// Always send an explicit UTC offset; a naive local timestamp can be read
  /// as UTC by the server and shift the attendance to another day.
  Map<String, dynamic> toApiJson() => {
        'client_event_id': clientEventId,
        'type': type,
        'occurred_at': occurredAt.toUtc().toIso8601String(),
        'latitude': ?latitude,
        'longitude': ?longitude,
      };

  factory OutboxEvent.fromJson(Map<String, dynamic> json) => OutboxEvent(
        clientEventId: json['client_event_id'] as String,
        type: json['type'] as String,
        occurredAt: DateTime.parse(json['occurred_at'] as String),
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        attempts: _asInt(json['attempts']),
        lastError: json['last_error'] as String?,
        nextAttemptAt: _asTime(json['next_attempt_at']),
      );
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

DateTime? _asTime(dynamic value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toLocal();
}

/// Persistence seam so tests can run without platform plugins.
abstract class OutboxStore {
  Future<String?> read();
  Future<void> write(String value);
}

class PrefsOutboxStore implements OutboxStore {
  static const _key = 'hadirmetrik.attendance_outbox.v1';

  @override
  Future<String?> read() async => (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> write(String value) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(_key, value);
    if (!saved) {
      throw const OutboxStorageException('Gagal menyimpan antrean presensi di perangkat.');
    }
  }
}

class OutboxStorageException implements Exception {
  const OutboxStorageException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MemoryOutboxStore implements OutboxStore {
  MemoryOutboxStore([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
}

/// Durable queue of attendance events that still need a server round-trip.
///
/// The batch idempotency key is persisted until the server answers, so a
/// timeout followed by a retry replays the same batch instead of creating
/// duplicate attendance.
class Outbox {
  Outbox({OutboxStore? store}) : _store = store ?? PrefsOutboxStore();

  /// Automatic flushes stop retrying an event after this many attempts; the
  /// user can still force a manual retry.
  static const maxAutoAttempts = 5;

  final OutboxStore _store;
  final List<OutboxEvent> _events = [];
  final Random _random = Random.secure();
  String? _batchKey;
  String? _owner;
  bool _loaded = false;
  Future<void>? _loading;

  List<OutboxEvent> get events => List.unmodifiable(_events);

  int get length => _events.length;

  bool get isEmpty => _events.isEmpty;

  /// Account that owns the queued events; null until the first login.
  String? get owner => _owner;

  /// Total retry attempts across queued events, for the sync card.
  int get pendingAttempts => _events.fold(0, (total, event) => total + event.attempts);

  /// Earliest future retry, or null when something is ready right away.
  DateTime? get nextAttemptAt {
    DateTime? earliest;
    for (final event in _events) {
      final next = event.nextAttemptAt;
      if (next == null || !next.isAfter(DateTime.now())) continue;
      if (earliest == null || next.isBefore(earliest)) earliest = next;
    }
    return earliest;
  }

  /// Events that may be sent by an automatic flush right now.
  ///
  /// Only a leading, causally ordered run is returned: never send a clock-out
  /// while the clock-in before it is still backing off.
  List<OutboxEvent> dueEvents({int limit = 100, bool force = false}) {
    final now = DateTime.now();
    final due = <OutboxEvent>[];
    for (final event in _events) {
      if (!force) {
        if (event.attempts >= maxAutoAttempts) break;
        final next = event.nextAttemptAt;
        if (next != null && next.isAfter(now)) break;
      }
      due.add(event);
      if (due.length >= limit) break;
    }
    return due;
  }

  String get batchKey {
    if (_batchKey != null) return _batchKey!;
    _batchKey = _newBatchKey();
    if (_events.isNotEmpty) {
      _persist();
    }
    return _batchKey!;
  }

  /// Awaits persistence before the key is used for a request, so a crash
  /// cannot lose it and make the retry look like a new batch.
  Future<String> ensureBatchKey() async {
    await load();
    if (_batchKey == null) {
      _batchKey = _newBatchKey();
      await _persist();
    }
    return _batchKey!;
  }

  Future<void> load() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final raw = await _store.read();
      if (raw == null || raw.isEmpty) {
        _loaded = true;
        return;
      }

      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _owner = decoded['owner'] as String?;
      _batchKey = decoded['batch_key'] as String?;
      for (final item in (decoded['events'] as List? ?? const [])) {
        try {
          _events.add(OutboxEvent.fromJson(item as Map<String, dynamic>));
        } catch (_) {
          // Skip one malformed event instead of discarding the whole queue.
        }
      }
      _sort();
      _loaded = true;
    } catch (_) {
      // Corrupt payload: start clean instead of blocking every future sync.
      _events.clear();
      _batchKey = null;
      _loaded = true;
      try {
        await _persist();
      } catch (_) {
        // Storage may be unavailable; the in-memory queue is still usable.
      }
    } finally {
      _loading = null;
    }
  }

  /// Binds the queue to an account. A different account never inherits
  /// another employee's unsynced attendance.
  Future<void> setOwner(String? owner) async {
    await load();
    final normalized = owner?.trim().toLowerCase();
    if (_owner == normalized) return;
    _owner = normalized;
    _events.clear();
    _batchKey = null;
    await _persist();
  }

  Future<OutboxEvent> add({
    required String type,
    required DateTime occurredAt,
    double? latitude,
    double? longitude,
  }) async {
    await load();
    final event = OutboxEvent(
      clientEventId: _newClientEventId(),
      type: type,
      occurredAt: occurredAt,
      latitude: latitude,
      longitude: longitude,
    );
    _events.add(event);
    _sort();
    await _persist();
    return event;
  }

  Future<void> removeSettled(Iterable<String> clientEventIds) async {
    final settled = clientEventIds.toSet();
    if (settled.isEmpty) return;
    _events.removeWhere((event) => settled.contains(event.clientEventId));
    await _persist();
  }

  /// Records one failure per event, so each event keeps its own reason and
  /// retry schedule instead of inheriting the first event's error.
  Future<void> recordAttempts(Map<String, String> errors, {bool schedule = true}) async {
    if (errors.isEmpty) return;
    final now = DateTime.now();
    for (final event in _events) {
      final error = errors[event.clientEventId];
      if (error == null) continue;
      event.attempts++;
      event.lastError = error;
      event.nextAttemptAt = schedule ? now.add(_retryDelay(event.attempts)) : null;
    }
    await _persist();
  }

  /// Convenience for a single message applied to several events.
  Future<void> recordAttempt(Iterable<String> clientEventIds, String error) =>
      recordAttempts({for (final id in clientEventIds) id: error});

  /// 5s, 10s, 20s, ... capped at 5 minutes.
  static Duration _retryDelay(int attempts) {
    final exponent = attempts.clamp(1, 7).toInt() - 1;
    final seconds = 5 * (1 << exponent);
    return Duration(seconds: seconds > 300 ? 300 : seconds);
  }

  Future<void> clearBatchKey() async {
    _batchKey = null;
    await _persist();
  }

  /// Drops every queued event. Used on logout so one account never syncs
  /// another account's attendance.
  Future<void> clear() async {
    _events.clear();
    _batchKey = null;
    await _persist();
  }

  Future<void> _persist() => _store.write(jsonEncode({
        'owner': _owner,
        'batch_key': _batchKey,
        'events': [for (final event in _events) event.toJson()],
      }));

  void _sort() => _events.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

  String _newClientEventId() {
    final micros = DateTime.now().microsecondsSinceEpoch;
    final suffix = _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    return 'evt-$micros-$suffix';
  }

  String _newBatchKey() {
    final micros = DateTime.now().microsecondsSinceEpoch;
    final suffix = _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    return 'batch-$micros-$suffix';
  }
}
