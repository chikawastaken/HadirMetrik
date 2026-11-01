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

  /// `synced` and `rejected` are final; the outbox can drop them.
  /// `sync_failed` and `pending_review` stay queued for retry or review.
  bool get isSettled => status == 'synced' || status == 'rejected';

  factory SyncEventResult.fromJson(Map<String, dynamic> json) => SyncEventResult(
        id: json['id'] ?? 0,
        clientEventId: json['client_event_id'] ?? '',
        type: json['type'] ?? 'clock_in',
        occurredAt: json['occurred_at'],
        status: json['status'] ?? 'pending_sync',
        errorMessage: json['error_message'],
        clockRecordId: json['clock_record_id'],
      );
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

  factory SyncBatch.fromJson(Map<String, dynamic> json) => SyncBatch(
        id: json['id'] ?? 0,
        idempotencyKey: json['idempotency_key'] ?? '',
        status: json['status'] ?? 'received',
        deviceId: json['device_id'],
        totalEvents: json['total_events'] ?? 0,
        processedEvents: json['processed_events'] ?? 0,
        failedEvents: json['failed_events'] ?? 0,
        receivedAt: json['received_at'],
        processedAt: json['processed_at'],
        events: [
          for (final event in (json['events'] as List? ?? const []))
            SyncEventResult.fromJson(event as Map<String, dynamic>),
        ],
      );
}
