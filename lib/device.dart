import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stable per-install device identifier used by attendance sync batches.
///
/// The value is generated once and persisted so the same installation is
/// recognisable across app restarts. When storage is unavailable the value is
/// still stable for the current process instead of failing the sync request.
class DeviceIdentity {
  static const _key = 'hadirmetrik.device_id.v1';
  static String? _cached;

  static Future<String> get() async {
    final cached = _cached;
    if (cached != null) return cached;

    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_key);
      if (stored != null && stored.trim().isNotEmpty) {
        _cached = stored.trim();
        return _cached!;
      }

      final created = _newId();
      // Keep the id for this session even if persisting it fails.
      _cached = created;
      await prefs.setString(_key, created);
    } catch (_) {
      _cached ??= _newId();
    }
    return _cached!;
  }

  static String _newId() {
    final random = Random.secure();
    final suffix = List.generate(16, (_) => random.nextInt(16).toRadixString(16)).join();
    return 'flutter-$suffix';
  }

  @visibleForTesting
  static void clearCacheForTests() => _cached = null;
}
