import 'package:flutter/foundation.dart';
import 'api.dart';

import 'data.dart';
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
  String? faceError;
  bool syncing = false;
  SyncBatch? lastSync;
  String? syncError;
  int pendingSyncCount = 0;
  String? clockNotice;
  bool clockBusy = false;

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
    faceBusy = true;
    faceError = null;
    notifyListeners();
    try {
      final rows = await Api.getFaceTemplates();
      faceTemplates = [
        for (final row in rows) FaceTemplate.fromJson(row as Map<String, dynamic>),
      ];
      faceEnrolled = faceTemplates.any((template) => template.isActive || template.isPending);
    } catch (error) {
      faceError = error is ApiError ? error.message : 'Tidak bisa memuat data wajah.';
    } finally {
      faceBusy = false;
      notifyListeners();
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
    faceBusy = true;
    faceError = null;
    notifyListeners();
    try {
      final result = FaceEnrollmentResult.fromJson(await Api.submitFaceEnrollment(
        sampleCount: sampleCount,
        provider: provider,
        templateRef: templateRef,
      ));
      faceEnrollment = result.enrollment;
      faceTemplates = [
        result.template,
        ...faceTemplates.where((template) => template.id != result.template.id),
      ];
      faceEnrolled = true;
      return result;
    } catch (error) {
      faceError = error is ApiError
          ? error.message
          : 'Pendaftaran belum terkirim. Coba lagi saat koneksi tersedia.';
      return null;
    } finally {
      faceBusy = false;
      notifyListeners();
    }
  }

  Future<bool> revokeFaceTemplate(int id) async {
    faceBusy = true;
    faceError = null;
    notifyListeners();
    try {
      _replaceTemplate(FaceTemplate.fromJson(await Api.revokeFaceTemplate(id)));
      return true;
    } catch (error) {
      faceError = error is ApiError ? error.message : 'Tidak bisa mencabut template wajah.';
      return false;
    } finally {
      faceBusy = false;
      notifyListeners();
    }
  }

  Future<bool> deleteFaceTemplate(int id) async {
    faceBusy = true;
    faceError = null;
    notifyListeners();
    try {
      _replaceTemplate(FaceTemplate.fromJson(await Api.deleteFaceTemplate(id)));
      faceEnrolled = faceTemplates.any((template) => template.isActive || template.isPending);
      return true;
    } catch (error) {
      faceError = error is ApiError ? error.message : 'Tidak bisa menghapus template wajah.';
      return false;
    } finally {
      faceBusy = false;
      notifyListeners();
    }
  }

  void _replaceTemplate(FaceTemplate template) {
    faceTemplates = [
      template,
      ...faceTemplates.where((existing) => existing.id != template.id),
    ]..sort((a, b) => b.version.compareTo(a.version));
  }

  /// Uploads queued offline events. The batch key is kept until the server
  /// answers, so a timeout followed by a retry cannot create duplicates.
  Future<SyncBatch?> flushOutbox() async {
    if (syncing) return lastSync;

    await outbox.load();
    pendingSyncCount = outbox.length;
    if (outbox.isEmpty) {
      notifyListeners();
      return lastSync;
    }

    syncing = true;
    syncError = null;
    notifyListeners();

    final batchEvents = outbox.events.take(100).toList();

    try {
      final batch = SyncBatch.fromJson(await Api.syncAttendance(
        idempotencyKey: outbox.batchKey,
        deviceId: 'flutter-android',
        events: [for (final event in batchEvents) event.toApiJson()],
      ));

      await outbox.removeSettled(
        batch.events.where((event) => event.isSettled).map((event) => event.clientEventId),
      );

      final unsettled = batch.events.where((event) => !event.isSettled).toList();
      if (unsettled.isNotEmpty) {
        await outbox.recordAttempt(
          unsettled.map((event) => event.clientEventId),
          unsettled.first.errorMessage ?? 'Belum tersinkron.',
        );
      }

      // The server has answered for this batch; the next flush needs a new key.
      await outbox.clearBatchKey();
      lastSync = batch;
      return batch;
    } catch (error) {
      final message = error is ApiError ? error.message : 'Tidak bisa terhubung ke server.';
      await outbox.recordAttempt(
        batchEvents.map((event) => event.clientEventId),
        message,
      );
      syncError = message;
      return null;
    } finally {
      pendingSyncCount = outbox.length;
      syncing = false;
      notifyListeners();
    }
  }

  void login(Role r) {
    role = r;
    notifyListeners();
  }

  void logout() {
    clockIn = null;
    clockOut = null;
    sim = Sim.normal;
    // Queued attendance belongs to the signed-in account; never let the next
    // account sync it.
    outbox.clear();
    pendingSyncCount = 0;
    faceTemplates = [];
    faceEnrollment = null;
    lastSync = null;
    syncError = null;
    clockNotice = null;
    clockBusy = false;
    notifyListeners();
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

    // Drain older offline events first; otherwise an online clock-in could be
    // recorded before the offline clock-in that logically precedes it.
    await outbox.load();
    if (!outbox.isEmpty) {
      await flushOutbox();
      if (!outbox.isEmpty) {
        await _queueClock(type, t);
        clockNotice = 'Tersimpan di perangkat. Akan disinkronkan saat online.';
        notifyListeners();
        return;
      }
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
      // The server answered and refused; queueing would replay a bad event.
      clockNotice = error.message;
    } catch (_) {
      await _queueClock(type, t);
      clockNotice = 'Tersimpan di perangkat. Akan disinkronkan saat online.';
      notifs.insert(0, Notif(
        NCat.absensi,
        type == OutboxEvent.typeClockIn ? 'Clock-in disimpan offline' : 'Clock-out disimpan offline',
        'Akan disinkronkan otomatis saat koneksi tersedia',
        hm(t),
        'HARI INI',
      ));
    }
    notifyListeners();
  }

  Future<void> _queueClock(String type, DateTime t) async {
    await outbox.add(type: type, occurredAt: t);
    if (type == OutboxEvent.typeClockIn) {
      clockIn = t;
    } else {
      clockOut = t;
    }
    pendingSyncCount = outbox.length;
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
