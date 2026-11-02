/// Offline attendance sync contracts (Phase 4).
class SyncEventResult {
  final int id;
  final String clientEventId;
  final String type;
  final String? occurredAt;
  final String status;
  final String? errorMessage;
  final int? clockRecordId;

  SyncEventResult({
    required this.id,
    required this.clientEventId,
    required this.type,
    this.occurredAt,
    required this.status,
    this.errorMessage,
    this.clockRecordId,
  });

  /// `synced`, `rejected`, and `pending_review` are final for the outbox: the
  /// server already holds the event. Only `sync_failed`/`pending_sync` retry.
  bool get isSettled => status == 'synced' || status == 'rejected' || status == 'pending_review';

  bool get isRejected => status == 'rejected';

  bool get isPendingReview => status == 'pending_review';

  factory SyncEventResult.fromJson(Map<String, dynamic> json) => SyncEventResult(
        id: _asInt(json['id']),
        clientEventId: _asString(json['client_event_id']),
        type: _asString(json['type'], 'clock_in'),
        occurredAt: _asStringOrNull(json['occurred_at']),
        status: _asString(json['status'], 'pending_sync'),
        errorMessage: _asStringOrNull(json['error_message']),
        clockRecordId: _asIntOrNull(json['clock_record_id']),
      );
}

int _asInt(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

int? _asIntOrNull(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

String _asString(dynamic value, [String fallback = '']) {
  if (value is String) return value;
  if (value == null) return fallback;
  return value.toString();
}

String? _asStringOrNull(dynamic value) {
  if (value is String) return value;
  if (value == null) return null;
  return value.toString();
}

class SyncBatch {
  final int id;
  final String idempotencyKey;
  final String status;
  final String? deviceId;
  final int totalEvents;
  final int processedEvents;
  final int failedEvents;
  final String? receivedAt;
  final String? processedAt;
  final List<SyncEventResult> events;

  SyncBatch({
    required this.id,
    required this.idempotencyKey,
    required this.status,
    this.deviceId,
    required this.totalEvents,
    required this.processedEvents,
    required this.failedEvents,
    this.receivedAt,
    this.processedAt,
    required this.events,
  });

  bool get isCompleted => status == 'completed';
  bool get isPartial => status == 'partial';
  bool get isFailed => status == 'failed';

  Set<String> get eventIds => {for (final event in events) event.clientEventId};

  factory SyncBatch.fromJson(Map<String, dynamic> json) => SyncBatch(
        id: _asInt(json['id']),
        idempotencyKey: _asString(json['idempotency_key']),
        status: _asString(json['status'], 'received'),
        deviceId: _asStringOrNull(json['device_id']),
        totalEvents: _asInt(json['total_events']),
        processedEvents: _asInt(json['processed_events']),
        failedEvents: _asInt(json['failed_events']),
        receivedAt: _asStringOrNull(json['received_at']),
        processedAt: _asStringOrNull(json['processed_at']),
        events: [
          for (final event in (json['events'] as List? ?? const []))
            if (event is Map<String, dynamic>) SyncEventResult.fromJson(event),
        ],
      );
}
