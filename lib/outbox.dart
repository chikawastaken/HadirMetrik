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
  });

  final String clientEventId;
  final String type;
  final DateTime occurredAt;
  final double? latitude;
  final double? longitude;
  int attempts;
  String? lastError;

  Map<String, dynamic> toJson() => {
        'client_event_id': clientEventId,
        'type': type,
        'occurred_at': occurredAt.toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        'attempts': attempts,
        'last_error': lastError,
      };

  /// Shape expected by `POST /sync/attendance`.
  Map<String, dynamic> toApiJson() => {
        'client_event_id': clientEventId,
        'type': type,
        'occurred_at': occurredAt.toIso8601String(),
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      };

  factory OutboxEvent.fromJson(Map<String, dynamic> json) => OutboxEvent(
        clientEventId: json['client_event_id'] as String,
        type: json['type'] as String,
        occurredAt: DateTime.parse(json['occurred_at'] as String),
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        attempts: json['attempts'] as int? ?? 0,
        lastError: json['last_error'] as String?,
      );
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
    await (await SharedPreferences.getInstance()).setString(_key, value);
  }
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

  final OutboxStore _store;
  final List<OutboxEvent> _events = [];
  final Random _random = Random.secure();
  String? _batchKey;
  bool _loaded = false;

  List<OutboxEvent> get events => List.unmodifiable(_events);

  int get length => _events.length;

  bool get isEmpty => _events.isEmpty;

  String get batchKey {
    if (_batchKey != null) return _batchKey!;
    _batchKey = _newBatchKey();
    if (_events.isNotEmpty) {
      _persist();
    }
    return _batchKey!;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;

    final raw = await _store.read();
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _batchKey = decoded['batch_key'] as String?;
      for (final item in (decoded['events'] as List? ?? const [])) {
        _events.add(OutboxEvent.fromJson(item as Map<String, dynamic>));
      }
      _sort();
    } catch (_) {
      // Corrupt payload: start clean instead of blocking every future sync.
      _events.clear();
      _batchKey = null;
    }
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

  Future<void> recordAttempt(Iterable<String> clientEventIds, String error) async {
    final ids = clientEventIds.toSet();
    if (ids.isEmpty) return;
    for (final event in _events) {
      if (ids.contains(event.clientEventId)) {
        event.attempts++;
        event.lastError = error;
      }
    }
    await _persist();
  }

  Future<void> clearBatchKey() async {
    _batchKey = null;
    await _persist();
  }

  Future<void> _persist() => _store.write(jsonEncode({
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
