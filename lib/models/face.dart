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

  factory FaceEnrollment.fromJson(Map<String, dynamic> json) => FaceEnrollment(
        id: json['id'] ?? 0,
        status: json['status'] ?? 'pending',
        provider: json['provider'],
        sampleCount: json['sample_count'] ?? 0,
        rejectionReason: json['rejection_reason'],
        faceTemplateId: json['face_template_id'],
        submittedAt: json['submitted_at'],
        processedAt: json['processed_at'],
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
        id: json['id'] ?? 0,
        version: json['version'] ?? 1,
        status: json['status'] ?? 'pending',
        provider: json['provider'],
        enrolledAt: json['enrolled_at'],
        revokedAt: json['revoked_at'],
        deletedAt: json['deleted_at'],
      );
}

class FaceEnrollmentResult {
  final FaceEnrollment enrollment;
  final FaceTemplate template;

  FaceEnrollmentResult({required this.enrollment, required this.template});

  factory FaceEnrollmentResult.fromJson(Map<String, dynamic> json) => FaceEnrollmentResult(
        enrollment: FaceEnrollment.fromJson(json['enrollment'] ?? {}),
        template: FaceTemplate.fromJson(json['template'] ?? {}),
      );
}
