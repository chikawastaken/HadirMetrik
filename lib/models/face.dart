/// Face enrollment contracts shared with the Laravel API (Phase 4).
///
/// Until a face model/provider is wired in, the backend keeps enrollments in
/// `pending`. The client must not present a pending template as verified.
class FaceEnrollment {
  final int id;
  final String status;
  final String? provider;
  final int sampleCount;
  final String? rejectionReason;
  final int? faceTemplateId;
  final String? submittedAt;
  final String? processedAt;

  FaceEnrollment({
    required this.id,
    required this.status,
    this.provider,
    required this.sampleCount,
    this.rejectionReason,
    this.faceTemplateId,
    this.submittedAt,
    this.processedAt,
  });

  bool get isPending => status == 'pending';
  bool get isProcessing => status == 'processing';
  bool get isCompleted => status == 'completed';
  bool get isRejected => status == 'rejected';
  bool get isFailed => status == 'failed';

  String get label => switch (status) {
        'pending' => 'Menunggu verifikasi',
        'processing' => 'Sedang diproses',
        'completed' => 'Terverifikasi',
        'rejected' => 'Ditolak',
        'failed' => 'Gagal',
        _ => status,
      };

  factory FaceEnrollment.fromJson(Map<String, dynamic> json) => FaceEnrollment(
        id: _faceInt(json['id']),
        status: _faceString(json['status'], 'pending'),
        provider: _faceStringOrNull(json['provider']),
        sampleCount: _faceInt(json['sample_count']),
        rejectionReason: _faceStringOrNull(json['rejection_reason']),
        faceTemplateId: _faceIntOrNull(json['face_template_id']),
        submittedAt: _faceStringOrNull(json['submitted_at']),
        processedAt: _faceStringOrNull(json['processed_at']),
      );
}

class FaceTemplate {
  final int id;
  final int version;
  final String status;
  final String? provider;
  final String? enrolledAt;
  final String? revokedAt;
  final String? deletedAt;

  FaceTemplate({
    required this.id,
    required this.version,
    required this.status,
    this.provider,
    this.enrolledAt,
    this.revokedAt,
    this.deletedAt,
  });

  bool get isPending => status == 'pending';
  bool get isActive => status == 'active';
  bool get isRevoked => status == 'revoked';
  bool get isDeleted => status == 'deleted';
  bool get canRevoke => isPending || isActive;
  bool get canDelete => isPending || isActive || isRevoked;

  String get label => switch (status) {
        'active' => 'Aktif',
        'pending' => 'Menunggu verifikasi',
        'revoked' => 'Dicabut',
        'deleted' => 'Dihapus',
        _ => status,
      };

  factory FaceTemplate.fromJson(Map<String, dynamic> json) => FaceTemplate(
        id: _faceInt(json['id']),
        version: _faceInt(json['version'], 1),
        status: _faceString(json['status'], 'pending'),
        provider: _faceStringOrNull(json['provider']),
        enrolledAt: _faceStringOrNull(json['enrolled_at']),
        revokedAt: _faceStringOrNull(json['revoked_at']),
        deletedAt: _faceStringOrNull(json['deleted_at']),
      );
}

int _faceInt(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

int? _faceIntOrNull(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

String _faceString(dynamic value, [String fallback = '']) {
  if (value is String) return value;
  if (value == null) return fallback;
  return value.toString();
}

String? _faceStringOrNull(dynamic value) {
  if (value is String) return value;
  if (value == null) return null;
  return value.toString();
}

class FaceEnrollmentResult {
  final FaceEnrollment enrollment;
  final FaceTemplate template;

  FaceEnrollmentResult({required this.enrollment, required this.template});

  factory FaceEnrollmentResult.fromJson(Map<String, dynamic> json) => FaceEnrollmentResult(
        enrollment: FaceEnrollment.fromJson(
          json['enrollment'] is Map<String, dynamic>
              ? json['enrollment'] as Map<String, dynamic>
              : const {},
        ),
        template: FaceTemplate.fromJson(
          json['template'] is Map<String, dynamic>
              ? json['template'] as Map<String, dynamic>
              : const {},
        ),
      );
}
