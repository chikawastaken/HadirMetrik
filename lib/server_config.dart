import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Resolves the backend base URL at runtime so development can move between
/// networks without rebuilding the APK.
///
/// Priority:
/// 1. `--dart-define=API_URL=...` (explicit override, wins for the whole run)
/// 2. A URL saved from the in-app debug dialog (survives restarts)
/// 3. The platform default: `127.0.0.1` on Android, which works on any Wi-Fi
///    while `adb reverse tcp:8000 tcp:8000` is active; `localhost` on web.
class ServerConfig {
  ServerConfig._();

  static const _prefsKey = 'debug.api_base_url';

  static const _compileTime = String.fromEnvironment('API_URL');

  static const _platformDefault = kIsWeb
      ? 'http://localhost:8000/api/v1'
      : 'http://127.0.0.1:8000/api/v1';

  /// Active base URL, used by [Api]. Never has a trailing slash.
  static String baseUrl = _compileTime.isNotEmpty ? normalize(_compileTime) : _platformDefault;

  /// True when `--dart-define=API_URL` supplied the value; such a value wins
  /// on every launch, so a saved URL cannot override it.
  static bool get locked => _compileTime.isNotEmpty;

  static Future<void> load() async {
    if (locked) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved != null && saved.trim().isNotEmpty) {
        baseUrl = normalize(saved);
      }
    } catch (_) {
      // Preferences unavailable: keep the platform default.
    }
  }

  static Future<void> save(String raw) async {
    final url = normalize(raw);
    baseUrl = url;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, url);
    } catch (_) {
      // The in-memory value still applies for this run.
    }
  }

  static Future<void> reset() async {
    baseUrl = _platformDefault;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {
      // Nothing persisted to clear.
    }
  }

  /// Accepts a bare host, a host with a port, or a full `/api/v1` URL and
  /// returns a canonical base URL without a trailing slash.
  static String normalize(String raw) {
    var url = raw.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.isEmpty) return _platformDefault;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    if (!url.endsWith('/api/v1')) {
      url = '$url/api/v1';
    }
    return url;
  }

  /// Hits `/health` so the debug dialog can confirm a server before saving.
  static Future<bool> reachable(String raw, {Duration timeout = const Duration(seconds: 4)}) async {
    try {
      final response = await http.get(Uri.parse('${normalize(raw)}/health')).timeout(timeout);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}
