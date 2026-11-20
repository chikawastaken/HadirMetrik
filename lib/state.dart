import 'dart:async';

import 'package:flutter/foundation.dart';
import 'api.dart';

import 'data.dart';
import 'device.dart';
import 'models/attendance_sync.dart';
import 'models/employee_profile.dart';
import 'models/face.dart';
import 'outbox.dart';

enum Role { karyawan, hr }

/// Demo scenarios for states that a real device would produce on its own
/// (outside geofence, fake GPS, liveness failure, ...). Picked from the
/// "Mode demo" sheet (long-press the clock on Beranda).
enum Sim {
  normal('Normal', 'Semua pemeriksaan lolos'),
  luarArea('Di luar area kantor', '1,2 km dari Kantor Pusat'),
  fakeGps('Lokasi palsu', 'Aplikasi Fake GPS aktif'),
  developer('Mode developer aktif', 'Mock location menyala'),
  root('Perangkat di-root', 'Atau berjalan di emulator'),
  gpsLemah('GPS lemah', 'Akurasi 68 m'),
  lompat('Perjalanan tidak wajar', 'Pindah 80 km dalam 3 menit'),
  wajah('Wajah tidak cocok', 'Gagal mencocokkan wajah'),
  liveness('Liveness gagal', 'Gerakan tidak terdeteksi'),
  gelap('Cahaya kurang', 'Wajah terlalu gelap'),
  banyakWajah('Lebih dari satu wajah', 'Ada orang lain di bingkai'),
  cuti('Hari cuti', 'Hari ini kamu cuti');

  const Sim(this.label, this.desc);
  final String label, desc;
}

class AppState extends ChangeNotifier {
  AppState({Outbox? outbox}) : outbox = outbox ?? Outbox();

  Role role = Role.karyawan;
  bool onboarded = false;
  bool faceEnrolled = false;
  Sim sim = Sim.normal;
  bool hideSalary = true;
  EmployeeProfile? profile;

  // Phase 4 — face enrollment and offline attendance sync.
  final Outbox outbox;
  List<FaceTemplate> faceTemplates = [];
  FaceEnrollment? faceEnrollment;
  bool faceBusy = false;
  bool faceEnrollmentFailed = false;
  String? faceError;
  bool syncing = false;
  SyncBatch? lastSync;
  List<SyncEventResult> lastRejected = [];
  List<SyncEventResult> lastReview = [];
  String? syncError;
  int pendingSyncCount = 0;
  String? clockNotice;
  bool clockBusy = false;
  int _session = 0;

  int get pendingAttempts => outbox.pendingAttempts;
  DateTime? get nextSyncAt => outbox.nextAttemptAt;

  FaceTemplate? get latestFaceTemplate => faceTemplates.isEmpty ? null : faceTemplates.first;

  /// The template that currently represents the user, if any.
  FaceTemplate? get currentFaceTemplate =>
      faceTemplates.where((template) => template.isActive || template.isPending).firstOrNull ??
      latestFaceTemplate;

  // Demo clock: the prototype day is Rabu, 7 Oktober 2026, starting 07.52.
  DateTime _base = DateTime(2026, 10, 7, 7, 52);
  DateTime _anchor = DateTime.now();
  DateTime get now => _base.add(DateTime.now().difference(_anchor));
  void setTime(int h, int m) {
    _base = DateTime(2026, 10, 7, h, m);
    _anchor = DateTime.now();
    notifyListeners();
  }

  DateTime? clockIn, clockOut;
  double faceScore = 97.4;
  int faceAttempts = 0;

  bool get insideArea => sim != Sim.luarArea;
  bool get onLeave => sim == Sim.cuti;
  bool get dayDone => clockOut != null;
  Duration get worked => clockIn == null ? Duration.zero : (clockOut ?? now).difference(clockIn!);

  /// Minutes relative to the 08.00 shift start; negative = early.
  int lateMinutes(DateTime t) => t.difference(DateTime(t.year, t.month, t.day, 8)).inMinutes;

  final tasks = seedTasks();
  late final hrTasks = seedHrTasks(tasks);
  final notifs = seedNotifs();
  final approvals = seedApprovals();
  late final leaves = [approvals[1], ...seedLeaves()];
  final incidents = [...seedIncidents];
  final payroll = seedPayroll();
  final newEmployees = <Person>[];
  int payrollStep = 1; // 0 Draft, 1 Ditinjau, 2 Disetujui, 3 Dipublikasikan

  int get unread => notifs.where((n) => !n.read).length;

  void touch() => notifyListeners();

  Future<void> fetchProfile() async {
    profile = null; // reset lama sebelum fetch baru
    notifyListeners();
    try {
      final res = await Api.getProfile();
      profile = EmployeeProfile.fromJson(res);
      notifyListeners();
    } catch (_) {}
  }

  /// Loads template versions from the API. Failures stay non-fatal so the
  /// profile still renders while the device is offline.
  Future<void> loadFaceState() async {
    final session = _session;
    faceBusy = true;
    faceError = null;
    notifyListeners();
    try {
      final rows = await Api.getFaceTemplates();
      if (session != _session) return;
      faceTemplates = [
        for (final row in rows) FaceTemplate.fromJson(row as Map<String, dynamic>),
      ]..sort((a, b) => b.version.compareTo(a.version));
      faceEnrolled = faceTemplates.any((template) => template.isActive);
    } catch (error) {
      if (session != _session) return;
      faceError = error is ApiError ? error.message : 'Tidak bisa memuat data wajah.';
    } finally {
      if (session == _session) {
        faceBusy = false;
        notifyListeners();
      }
    }
  }

  /// Sends a capture session to the backend. It stays `pending` until a face
  /// model/provider exists; a failed upload is reported but never shown as
  /// verified.
  Future<FaceEnrollmentResult?> submitFaceEnrollment({
    int sampleCount = 5,
    String? provider,
    String? templateRef,
  }) async {
    final session = _session;
    faceBusy = true;
    faceEnrollmentFailed = false;
    faceError = null;
    notifyListeners();
    try {
      final result = FaceEnrollmentResult.fromJson(await Api.submitFaceEnrollment(
        sampleCount: sampleCount,
        provider: provider,
        templateRef: templateRef,
      ));
      if (session != _session) return null;
      faceEnrollment = result.enrollment;
      faceTemplates = [
        result.template,
        ...faceTemplates.where((template) => template.id != result.template.id),
      ]..sort((a, b) => b.version.compareTo(a.version));
      faceEnrolled = result.template.isActive;
      return result;
    } catch (error) {
      if (session != _session) return null;
      faceEnrollmentFailed = true;
      faceError = error is ApiError
          ? error.message
          : 'Pendaftaran belum terkirim. Coba lagi saat koneksi tersedia.';
      return null;
    } finally {
      if (session == _session) {
        faceBusy = false;
        notifyListeners();
      }
    }
  }

  Future<bool> revokeFaceTemplate(int id) async {
    final session = _session;
    faceBusy = true;
    faceError = null;
    notifyListeners();
    try {
      final data = await Api.revokeFaceTemplate(id);
      if (session != _session) return false;
      var template = FaceTemplate.fromJson(data);
      if (template.id == 0) {
        // Some proxies/gateways strip the body; fall back to the local row.
        final current = _templateById(id);
        if (current == null) {
          faceError = 'Respons server tidak valid.';
          return false;
        }
        template = _copyWithStatus(
          current,
          'revoked',
          revokedAt: DateTime.now().toUtc().toIso8601String(),
        );
      }
      _replaceTemplate(template);
      faceEnrolled = faceTemplates.any((existing) => existing.isActive);
      return true;
    } catch (error) {
      if (session != _session) return false;
      faceError = error is ApiError ? error.message : 'Tidak bisa mencabut template wajah.';
      return false;
    } finally {
      if (session == _session) {
        faceBusy = false;
        notifyListeners();
      }
    }
  }

  Future<bool> deleteFaceTemplate(int id) async {
    final session = _session;
    faceBusy = true;
    faceError = null;
    notifyListeners();
    try {
      final data = await Api.deleteFaceTemplate(id);
      if (session != _session) return false;
      var template = FaceTemplate.fromJson(data);
      if (template.id == 0) {
        // Some proxies/gateways strip the body; fall back to the local row.
        final current = _templateById(id);
        if (current == null) {
          faceError = 'Respons server tidak valid.';
          return false;
        }
        template = _copyWithStatus(
          current,
          'deleted',
          deletedAt: DateTime.now().toUtc().toIso8601String(),
        );
      }
      _replaceTemplate(template);
      faceEnrolled = faceTemplates.any((existing) => existing.isActive);
      return true;
    } catch (error) {
      if (session != _session) return false;
      faceError = error is ApiError ? error.message : 'Tidak bisa menghapus template wajah.';
      return false;
    } finally {
      if (session == _session) {
        faceBusy = false;
        notifyListeners();
      }
    }
  }

  FaceTemplate? _templateById(int id) {
    for (final template in faceTemplates) {
      if (template.id == id) return template;
    }
    return null;
  }

  FaceTemplate _copyWithStatus(
    FaceTemplate source,
    String status, {
    String? revokedAt,
    String? deletedAt,
  }) =>
      FaceTemplate(
        id: source.id,
        version: source.version,
        status: status,
        provider: source.provider,
        enrolledAt: source.enrolledAt,
        revokedAt: revokedAt ?? source.revokedAt,
        deletedAt: deletedAt ?? source.deletedAt,
      );

  void _replaceTemplate(FaceTemplate template) {
    faceTemplates = [
      template,
      ...faceTemplates.where((existing) => existing.id != template.id),
    ]..sort((a, b) => b.version.compareTo(a.version));
  }

  /// Uploads queued offline events. The batch key is kept until the server
  /// answers, so a timeout followed by a retry cannot create duplicates.
  Future<SyncBatch?> flushOutbox({bool force = false}) async {
    if (syncing) return lastSync;

    final session = _session;
    syncing = true;
    syncError = null;
    notifyListeners();

    List<OutboxEvent> batchEvents = const [];

    try {
      await outbox.load();
      if (session != _session) return null;
      pendingSyncCount = outbox.length;
      if (outbox.isEmpty) return lastSync;

      batchEvents = outbox.dueEvents(force: force);
      if (batchEvents.isEmpty) {
        syncError = 'Menunggu jadwal coba ulang. Tekan Sinkronkan untuk mencoba sekarang.';
        return lastSync;
      }

      final deviceId = await DeviceIdentity.get();
      final key = await outbox.ensureBatchKey();

      var batch = SyncBatch.fromJson(await Api.syncAttendance(
        idempotencyKey: key,
        deviceId: deviceId,
        events: [for (final event in batchEvents) event.toApiJson()],
      ));
      if (session != _session) return null;

      final sentIds = batchEvents.map((event) => event.clientEventId).toSet();

      // A batch that is still processing may return no events. Poll the batch
      // endpoint before rotating the key; otherwise the same events would be
      // uploaded again under a new key.
      if (batch.id > 0 && !sentIds.every(batch.eventIds.contains)) {
        try {
          final polled = SyncBatch.fromJson(await Api.getSyncBatch(batch.id));
          if (polled.events.isNotEmpty) batch = polled;
        } catch (_) {
          // Keep the key and retry the poll on the next flush.
        }
      }
      if (session != _session) return null;

      final accounted = batch.eventIds;
      final allAccounted = sentIds.every(accounted.contains);

      final settled = batch.events.where((event) => event.isSettled).toList();
      final unsettled = batch.events.where((event) => !event.isSettled).toList();

      var persisted = true;
      try {
        await outbox.removeSettled(settled.map((event) => event.clientEventId));
      } catch (_) {
        persisted = false;
      }
      if (unsettled.isNotEmpty) {
        try {
          await outbox.recordAttempts({
            for (final event in unsettled)
              event.clientEventId: event.errorMessage ?? 'Belum tersinkron.',
          });
        } catch (_) {
          persisted = false;
        }
      }

      lastRejected = settled.where((event) => event.isRejected).toList();
      lastReview = settled.where((event) => event.isPendingReview).toList();
      lastSync = batch;

      if (allAccounted && persisted) {
        try {
          await outbox.clearBatchKey();
        } catch (_) {
          persisted = false;
        }
      } else if (!allAccounted) {
        syncError = 'Server belum mengembalikan hasil lengkap. Coba sinkronkan lagi.';
      }

      if (!persisted) {
        syncError = 'Server menjawab, tetapi hasil gagal disimpan di perangkat.';
      }
      if (lastRejected.isNotEmpty) {
        syncError = lastRejected.first.errorMessage ?? 'Ada presensi yang ditolak server.';
        clockNotice = syncError;
      }
      if (outbox.isEmpty && lastRejected.isEmpty && lastReview.isEmpty) {
        clockNotice = null;
      }

      return batch;
    } catch (error) {
      if (session != _session) return null;
      final message = switch (error) {
        ApiError apiError => apiError.message,
        OutboxStorageException storageError => storageError.message,
        _ => 'Tidak bisa terhubung ke server.',
      };
      if (batchEvents.isNotEmpty) {
        try {
          await outbox.recordAttempts({
            for (final event in batchEvents) event.clientEventId: message,
          });
        } catch (_) {
          // Keep the original error; the queue is still in memory.
        }
      }
      syncError = message;
      return null;
    } finally {
      if (session == _session) {
        try {
          await outbox.load();
        } catch (_) {
          // Keep the last known count if storage is temporarily unavailable.
        }
        pendingSyncCount = outbox.length;
        syncing = false;
        notifyListeners();
      }
    }
  }

  /// Loads the durable queue on startup and rebuilds today's clock state so a
  /// restart cannot turn an offline clock-in into a second clock-in.
  Future<void> restoreOfflineState() async {
    try {
      await outbox.load();
    } catch (_) {
      return;
    }
    pendingSyncCount = outbox.length;
    _hydrateClockFromOutbox();
    notifyListeners();
  }

  void _hydrateClockFromOutbox() {
    final today = DateTime(now.year, now.month, now.day);
    for (final event in outbox.events) {
      final day = DateTime(event.occurredAt.year, event.occurredAt.month, event.occurredAt.day);
      if (day != today) continue;
      if (event.type == OutboxEvent.typeClockIn) {
        if (clockIn == null || event.occurredAt.isAfter(clockIn!)) clockIn = event.occurredAt;
      } else if (event.type == OutboxEvent.typeClockOut) {
        if (clockOut == null || event.occurredAt.isAfter(clockOut!)) clockOut = event.occurredAt;
      }
    }
  }

  Future<void> login(Role r) async {
    role = r;
    // Scope the queue to this account, then restore anything it left behind.
    await outbox.setOwner(Api.accountKey);
    await restoreOfflineState();
    notifyListeners();
    // The token is available by now; drain the previous session's queue.
    unawaited(flushOutbox());
  }

  Future<void> logout({bool clearOutbox = true}) async {
    _session++;
    clockIn = null;
    clockOut = null;
    sim = Sim.normal;
    pendingSyncCount = 0;
    faceTemplates = [];
    faceEnrollment = null;
    faceBusy = false;
    faceEnrollmentFailed = false;
    faceError = null;
    lastSync = null;
    lastRejected = [];
    lastReview = [];
    syncError = null;
    clockNotice = null;
    clockBusy = false;
    syncing = false;
    // Queued attendance belongs to the signed-in account; never let the next
    // account sync it. On session expiry we keep it so the same employee can
    // flush after signing in again. Await so a fast re-login cannot race the clear.
    try {
      if (clearOutbox) await outbox.clear();
    } finally {
      notifyListeners();
    }
  }

  void setSim(Sim s) {
    sim = s;
    notifyListeners();
  }

  Future<void> recordClock() async {
    if (clockBusy) return;
    clockBusy = true;
    notifyListeners();
    try {
      await _recordClock();
    } finally {
      clockBusy = false;
      notifyListeners();
    }
  }

  Future<void> _recordClock() async {
    final t = now;
    final type = clockIn == null ? OutboxEvent.typeClockIn : OutboxEvent.typeClockOut;
    clockNotice = null;

    // A restored queue can already contain today's clock-out; do not create a
    // second one just because the clock screen still offers the button.
    if (type == OutboxEvent.typeClockOut && clockOut != null) {
      clockNotice = 'Presensi hari ini sudah lengkap.';
      return;
    }

    // Drain older offline events first; otherwise an online clock-in could be
    // recorded before the offline clock-in that logically precedes it.
    try {
      await outbox.load();
      if (!outbox.isEmpty) {
        await flushOutbox();
        if (!outbox.isEmpty) {
          final saved = await _queueClock(type, t);
          clockNotice = saved
              ? 'Tersimpan di perangkat. Akan disinkronkan saat online.'
              : 'Tidak bisa menyimpan presensi di perangkat.';
          notifyListeners();
          return;
        }
      }
    } catch (_) {
      // Local storage unavailable; still let the online path try.
    }

    try {
      if (type == OutboxEvent.typeClockIn) {
        await Api.clockIn();
        clockIn = t;
        notifs.insert(0, Notif(NCat.absensi, 'Clock-in tercatat ${hm(t)}', 'Kantor Pusat Yogyakarta · wajah dan lokasi valid', hm(t), 'HARI INI'));
      } else {
        await Api.clockOut();
        clockOut = t;
        notifs.insert(0, Notif(NCat.absensi, 'Clock-out tercatat ${hm(t)}', 'Total kerja hari ini ${dur(worked)}', hm(t), 'HARI INI'));
      }
    } on ApiError catch (error) {
      if (error.isServerError) {
        // 5xx/gateway failures are transient: keep the event for retry.
        final saved = await _queueClock(type, t);
        clockNotice = saved
            ? 'Server sedang bermasalah. Presensi disimpan di perangkat.'
            : 'Server sedang bermasalah dan presensi gagal disimpan.';
      } else {
        // The server answered and refused; queueing would replay a bad event.
        clockNotice = error.message;
      }
    } catch (_) {
      final saved = await _queueClock(type, t);
      clockNotice = saved
          ? 'Tersimpan di perangkat. Akan disinkronkan saat online.'
          : 'Tidak bisa menyimpan presensi di perangkat.';
      notifs.insert(0, Notif(
        NCat.absensi,
        type == OutboxEvent.typeClockIn ? 'Clock-in disimpan offline' : 'Clock-out disimpan offline',
        'Akan disinkronkan saat kamu membuka Profil atau menekan Sinkronkan',
        hm(t),
        'HARI INI',
      ));
    }
    notifyListeners();
  }

  Future<bool> _queueClock(String type, DateTime t) async {
    try {
      await outbox.add(type: type, occurredAt: t);
    } catch (_) {
      return false;
    }
    if (type == OutboxEvent.typeClockIn) {
      clockIn = t;
    } else {
      clockOut = t;
    }
    pendingSyncCount = outbox.length;
    return true;
  }

  void toggleSalary() {
    hideSalary = !hideSalary;
    notifyListeners();
  }

  List<bool> markAllRead() {
    final before = [for (final n in notifs) n.read];
    for (final n in notifs) {
      n.read = true;
    }
    notifyListeners();
    return before;
  }

  void restoreRead(List<bool> before) {
    for (var i = 0; i < before.length && i < notifs.length; i++) {
      notifs[i].read = before[i];
    }
    notifyListeners();
  }
}

final app = AppState();
