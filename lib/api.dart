import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'server_config.dart';
import 'session.dart';

/// Resolved at runtime by [ServerConfig] so the address can change without a
/// rebuild (see the server dialog on the Login screen in debug builds).
String get baseUrl => ServerConfig.baseUrl;

class ApiError implements Exception {
  ApiError(this.message, [this.errors, this.statusCode]);
  final String message;
  final Map<String, dynamic>? errors;
  final int? statusCode;

  /// 5xx and gateway failures are transient: the event should be queued.
  bool get isServerError => statusCode != null && statusCode! >= 500;

  /// Machine-readable reason from `errors.code`, e.g. `INVITATION_NOT_OWNED`.
  String? get code {
    final value = errors?['code'];
    if (value is List && value.isNotEmpty) return value.first.toString();
    if (value is String) return value;
    return null;
  }

  @override
  String toString() => message;
}

class Api {
  static String? _token;

  static String? get token => _token;

  /// Clears the "session expired" latch whenever the token changes.
  static set token(String? value) {
    _token = value;
    _sessionExpiryNotified = false;
  }

  /// Identifier of the signed-in account, used to scope the offline outbox.
  static String? accountKey;

  /// Called once when a protected request is rejected with `401`. The app
  /// clears the stored session and returns to Login.
  static Future<void> Function()? onSessionExpired;

  static bool _sessionExpiryNotified = false;

  /// Overridable for tests.
  static http.Client client = http.Client();

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  static dynamic _decode(http.Response r) {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiError('Respons server tidak valid (${r.statusCode})', null, r.statusCode);
    }
    if (r.statusCode >= 200 && r.statusCode < 300 && body['success'] == true) {
      return body['data'];
    }

    if (r.statusCode == 401 && _token != null && !_sessionExpiryNotified) {
      _sessionExpiryNotified = true;
      final callback = onSessionExpired;
      if (callback != null) unawaited(callback());
    }

    throw ApiError(body['message'] ?? 'Terjadi kesalahan', body['errors'], r.statusCode);
  }

  static Map<String, dynamic> _handle(http.Response r) {
    final data = _decode(r);
    return data is Map<String, dynamic> ? data : {};
  }

  /// Some endpoints return a bare list in `data` (e.g. face templates), while
  /// paginated endpoints nest it under `data.data`. Anything else is invalid.
  static List<dynamic> _handleList(http.Response r) {
    final data = _decode(r);
    if (data is List) return data;
    if (data is Map<String, dynamic>) {
      final nested = data['data'];
      if (nested is List) return nested;
    }
    throw ApiError('Respons server tidak valid (${r.statusCode})', null, r.statusCode);
  }

  static Future<Map<String, dynamic>> post(String path, Map<String, dynamic> data) async =>
      _handle(await client
          .post(Uri.parse('$baseUrl$path'), headers: _headers, body: jsonEncode(data))
          .timeout(const Duration(seconds: 15)));

  static Future<Map<String, dynamic>> get(String path) async =>
      _handle(await client
          .get(Uri.parse('$baseUrl$path'), headers: _headers)
          .timeout(const Duration(seconds: 15)));

  static Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> data) async =>
      _handle(await client
          .patch(Uri.parse('$baseUrl$path'), headers: _headers, body: jsonEncode(data))
          .timeout(const Duration(seconds: 15)));

  static Future<Map<String, dynamic>> delete(String path) async =>
      _handle(await client
          .delete(Uri.parse('$baseUrl$path'), headers: _headers)
          .timeout(const Duration(seconds: 15)));

  static Future<Map<String, dynamic>> me() async => get('/me');

  static Future<Map<String, dynamic>> getProfile() async => get('/me/profile');
  static Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) async => patch('/me/profile', data);

  static Future<Map<String, dynamic>> clockIn() async => post('/clock-in', {});
  static Future<Map<String, dynamic>> clockOut() async => post('/clock-out', {});
  static Future<Map<String, dynamic>> getSchedule() async => get('/schedule');
  static Future<Map<String, dynamic>> getHistory() async => get('/history');
  static Future<Map<String, dynamic>> correctHistory(int id) async => patch('/history/$id/correction', {});

  /// Reserves the invitation for the signed-in employee (architecture §4.8).
  static Future<Map<String, dynamic>> acceptInvitation(String token) => post('/invitations/$token/accept', {});

  /// Chooses the permanent password straight from the invitation link and
  /// receives a session in return (architecture §4.8).
  static Future<Map<String, dynamic>> setPasswordFromInvitation(String invitation, String next) async {
    final data = await post('/invitations/$invitation/password', {
      'new_password': next,
      'new_password_confirmation': next,
    });
    token = data['token'] as String?;
    // No identifier was typed here; scope the outbox to the created user.
    _rememberAccount(data['user'], 'invitation-$invitation');
    await _persistSession(data);
    return data;
  }

  static Future<Map<String, dynamic>> changePassword({required String current, required String next}) =>
      post('/auth/change-password', {
        'current_password': current,
        'new_password': next,
        'new_password_confirmation': next,
      });

  static Future<Map<String, dynamic>> login(String identifier, String password) async {
    final data = await post('/login', {
      'identifier': identifier,
      'password': password,
      'device_name': 'Flutter Android',
    });
    token = data['token'] as String?;
    _rememberAccount(data['user'], identifier);
    await _persistSession(data);
    return data;
  }

  /// Saves the token and minimal user payload so the next launch can restore
  /// the session without asking for credentials again.
  static Future<void> _persistSession(Map<String, dynamic> data) async {
    try {
      await Session.saveFromAuth(data, accountKey: accountKey);
    } catch (_) {
      // A platform storage failure must not block an otherwise valid login.
    }
  }

  /// Stable key for the offline outbox. Prefer the user id so the same person
  /// keeps their queue whether they sign in by email, NIK, or invitation.
  static void _rememberAccount(dynamic user, [String? fallback]) {
    String? key;
    if (user is Map) {
      final id = user['id'];
      final email = user['email'];
      if (id != null) {
        key = 'u:$id';
      } else if (email is String && email.trim().isNotEmpty) {
        key = email.trim().toLowerCase();
      }
    }
    key ??= fallback?.trim().toLowerCase();
    accountKey = (key == null || key.isEmpty) ? null : key;
  }

  static Future<void> logout() async {
    try {
      await post('/logout', {});
    } finally {
      token = null;
      accountKey = null;
      try {
        await Session.clear();
      } catch (_) {
        // Nothing else to do: the in-memory token is already gone.
      }
    }
  }

  static Future<Map<String, dynamic>> createEmployee(Map<String, dynamic> body) =>
      post('/hr/employees', body);

  static Future<Map<String, dynamic>> hrEmployeeList({String? search, int? divisionId, String? status}) async {
    final params = <String, String>{};
    if (search != null && search.isNotEmpty) params['search'] = search;
    if (divisionId != null) params['division_id'] = divisionId.toString();
    if (status != null && status.isNotEmpty) params['status'] = status;
    final query = params.isEmpty ? '' : '?${Uri(queryParameters: params).query}';
    return get('/hr/employees$query');
  }

  static Future<Map<String, dynamic>> hrEmployeeDetail(int id) => get('/hr/employees/$id');

  static Future<Map<String, dynamic>> hrResendInvitation(int id, {List<String>? channels, int? expiresInDays}) =>
      post('/hr/employees/$id/invitations', {
        'channels': ?channels,
        'expires_in_days': ?expiresInDays,
      });

  static Future<Map<String, dynamic>> hrResetPassword(int id) => post('/hr/employees/$id/reset-password', {});

  static Future<Map<String, dynamic>> hrRevokeInvitation(int id) => delete('/hr/invitations/$id');

  // ------------------------------------------------------------ Phase 4

  /// Submits an enrollment attempt. The backend keeps it `pending` until a
  /// face model/provider is wired in, so this never means "verified".
  static Future<Map<String, dynamic>> submitFaceEnrollment({
    int sampleCount = 5,
    String? provider,
    String? templateRef,
    Map<String, dynamic>? metadata,
  }) =>
      post('/face/enroll', {
        'sample_count': sampleCount,
        'provider': ?provider,
        'template_ref': ?templateRef,
        'metadata': ?metadata,
      });

  static Future<Map<String, dynamic>> getFaceEnrollment(int id) => get('/face/enrollments/$id');

  static Future<List<dynamic>> getFaceTemplates() async =>
      _handleList(await client
          .get(Uri.parse('$baseUrl/face/templates'), headers: _headers)
          .timeout(const Duration(seconds: 15)));

  static Future<Map<String, dynamic>> revokeFaceTemplate(int id) => post('/face/templates/$id/revoke', {});

  static Future<Map<String, dynamic>> deleteFaceTemplate(int id) => delete('/face/templates/$id');

  static Future<Map<String, dynamic>> syncAttendance({
    required String idempotencyKey,
    String? deviceId,
    required List<Map<String, dynamic>> events,
  }) =>
      post('/sync/attendance', {
        'idempotency_key': idempotencyKey,
        'device_id': ?deviceId,
        'events': events,
      });

  static Future<Map<String, dynamic>> getSyncBatch(int id) => get('/sync/attendance/$id');

  // ------------------------------------------------------------ Phase 5

  static Future<Map<String, dynamic>> taskList({String? status, String? search}) async {
    final params = <String, String>{};
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (search != null && search.isNotEmpty) params['search'] = search;
    final query = params.isEmpty ? '' : '?${Uri(queryParameters: params).query}';
    return get('/tasks$query');
  }

  static Future<Map<String, dynamic>> taskDetail(int id) async => get('/tasks/$id');

  static Future<Map<String, dynamic>> taskStart(int id) async => post('/tasks/$id/start', {});

  static Future<Map<String, dynamic>> taskProgress(int id, {required int progressPercent, dynamic checklist}) async {
    final body = <String, dynamic>{'progress_percent': progressPercent};
    if (checklist != null) body['checklist'] = checklist;
    return patch('/tasks/$id/progress', body);
  }

  static Future<Map<String, dynamic>> taskSubmit(
    int id, {
    String? note,
    dynamic checklist,
    List<int>? attachmentIds,
    List<http.MultipartFile>? evidence,
  }) async {
    final body = <String, dynamic>{};
    if (note != null) body['note'] = note;
    if (checklist != null) body['checklist'] = checklist;
    if (attachmentIds != null) body['attachment_ids'] = attachmentIds;
    if (evidence != null && evidence.isNotEmpty) {
      // Multipart request needed for file uploads.
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/tasks/$id/submissions'));
      request.headers.addAll(_headers.map((k, v) => MapEntry(k, v)));
      request.fields.addAll(body.map((k, v) => MapEntry(k, jsonEncode(v))));
      for (final f in evidence) {
        request.files.add(f);
      }
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      return _handle(response);
    }
    return post('/tasks/$id/submissions', body);
  }

  static Future<Map<String, dynamic>> taskComment(int id, String body) async => post('/tasks/$id/comments', {'body': body});

  static Future<Map<String, dynamic>> taskAttachment(int id, {required String kind, required String originalName, required String mimeType, required int sizeBytes, http.MultipartFile? file}) async {
    final body = <String, dynamic>{
      'kind': kind,
      'original_name': originalName,
      'mime_type': mimeType,
      'size_bytes': sizeBytes,
    };
    if (file != null) {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/tasks/$id/attachments'));
      request.headers.addAll(_headers.map((k, v) => MapEntry(k, v)));
      request.fields.addAll(body.map((k, v) => MapEntry(k, v.toString())));
      request.files.add(file);
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      return _handle(response);
    }
    return post('/tasks/$id/attachments', body);
  }

  // ------------------------------------------------------------ HR Tasks

  static Future<Map<String, dynamic>> hrTaskList({String? status, int? page}) async {
    final params = <String, String>{};
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (page != null) params['page'] = page.toString();
    final query = params.isEmpty ? '' : '?${Uri(queryParameters: params).query}';
    return get('/hr/tasks$query');
  }

  static Future<Map<String, dynamic>> hrTaskOptions() async => get('/hr/tasks/options');

  static Future<Map<String, dynamic>> hrTaskCreate({
    required String title,
    String? description,
    required String priority,
    required List<int> assigneeIds,
    int? divisionId,
    bool requiresPhotoProof = false,
    List<Map<String, String>>? checklistTemplate,
    String? dueAt,
  }) async {
    final body = <String, dynamic>{
      'title': title,
      'description': ?description,
      'priority': priority,
      'assignee_ids': assigneeIds,
      'division_id': ?divisionId,
      'requires_photo_proof': requiresPhotoProof,
      'checklist_template': ?checklistTemplate,
      'due_at': ?dueAt,
    };
    return post('/hr/tasks', body);
  }

  static Future<Map<String, dynamic>> hrTaskCancel(int id) async => post('/hr/tasks/$id/cancel', {});

  static Future<Map<String, dynamic>> hrTaskReview(
    int submissionId, {
    required String decision,
    int? rating,
    String? note,
  }) async {
    final body = <String, dynamic>{
      'decision': decision,
      'rating': ?rating,
      'note': ?note,
    };
    return post('/hr/task-submissions/$submissionId/review', body);
  }
}