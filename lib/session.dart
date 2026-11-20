import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A signed-in session as it survives an app restart.
class StoredSession {
  const StoredSession({
    required this.token,
    required this.user,
    this.accountKey,
    this.expiresAt,
    this.onboarded = false,
  });

  final String token;
  final Map<String, dynamic> user;
  final String? accountKey;
  final DateTime? expiresAt;
  final bool onboarded;

  bool get isHr => user['role'] == 'hr' || user['role'] == 'admin';

  bool get mustChangePassword => user['must_change_password'] == true;

  StoredSession copyWith({Map<String, dynamic>? user, bool? onboarded}) =>
      StoredSession(
        token: token,
        user: user ?? this.user,
        accountKey: accountKey,
        expiresAt: expiresAt,
        onboarded: onboarded ?? this.onboarded,
      );

  Map<String, dynamic> toJson() => {
        'token': token,
        'user': user,
        'account_key': accountKey,
        'expires_at': expiresAt?.toUtc().toIso8601String(),
        'onboarded': onboarded,
      };

  factory StoredSession.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    if (user is! Map) {
      throw const FormatException('Session user is missing.');
    }

    return StoredSession(
      token: json['token'] as String,
      user: Map<String, dynamic>.from(user),
      accountKey: json['account_key'] as String?,
      expiresAt: DateTime.tryParse((json['expires_at'] as String?) ?? ''),
      onboarded: json['onboarded'] == true,
    );
  }
}

enum SessionRestore { none, expired, ready }

/// Decides what a cold start should do with a stored session. Kept pure so
/// the boot decision is testable without touching the platform.
SessionRestore resolveRestore(StoredSession? session, DateTime now) {
  if (session == null) return SessionRestore.none;
  final expiresAt = session.expiresAt;
  if (expiresAt != null && !expiresAt.isAfter(now)) return SessionRestore.expired;
  return SessionRestore.ready;
}

abstract class SessionStore {
  Future<StoredSession?> read();
  Future<void> write(StoredSession session);
  Future<void> clear();
}

class SecureSessionStore implements SessionStore {
  SecureSessionStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'hadirmetrik.session.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<StoredSession?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return StoredSession.fromJson(decoded);
      }
    } catch (_) {
      // A corrupt or outdated record is treated as no session.
    }
    return null;
  }

  @override
  Future<void> write(StoredSession session) =>
      _storage.write(key: _key, value: jsonEncode(session.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// Facade over the storage used by [Api] and the boot gate.
class Session {
  static SessionStore store = SecureSessionStore();

  static Future<StoredSession?> read() => store.read();

  /// Persists the token, expiry, and minimal user payload returned by login or
  /// invitation password setup.
  static Future<void> saveFromAuth(
    Map<String, dynamic> data, {
    String? accountKey,
  }) async {
    final token = data['token'];
    final user = data['user'];
    if (token is! String || user is! Map) return;

    await store.write(StoredSession(
      token: token,
      user: Map<String, dynamic>.from(user),
      accountKey: accountKey,
      expiresAt: DateTime.tryParse('${data['expires_at'] ?? ''}'),
    ));
  }

  /// Replaces the cached identity after a successful `/me` validation.
  static Future<void> refreshUser(Map<String, dynamic> user) async {
    final current = await store.read();
    if (current == null) return;
    await store.write(current.copyWith(user: Map<String, dynamic>.from(user)));
  }

  static Future<void> markOnboarded() async {
    final current = await store.read();
    if (current == null) return;
    await store.write(current.copyWith(onboarded: true));
  }

  static Future<void> clear() => store.clear();
}
