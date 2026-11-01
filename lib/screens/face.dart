import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/face.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'auth.dart';

// ------------------------------------------------------- profile: face card

/// Profile summary for the latest face template. Tapping opens the full
/// management screen; a pending template is never shown as verified.
class FaceDataCard extends StatefulWidget {
  const FaceDataCard({super.key});

  @override
  State<FaceDataCard> createState() => _FaceDataCardState();
}

class _FaceDataCardState extends State<FaceDataCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => app.loadFaceState());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final template = app.currentFaceTemplate;
          final pending = template?.isPending ?? false;
          final active = template?.isActive ?? false;
          final title = template == null ? 'Belum terdaftar' : 'Template v${template.version}';
          final caption = switch (template?.status) {
            'active' => 'Wajah terverifikasi · terenkripsi',
            'pending' => 'Menunggu verifikasi model wajah',
            'revoked' => 'Template dicabut · daftarkan ulang',
            'deleted' => 'Template dihapus',
            _ => 'Daftarkan wajah untuk absensi',
          };
          final tone = active ? Tone.success : pending ? Tone.warning : Tone.neutral;

          return AppCard(
            onTap: () => push(context, const FaceEnrollmentScreen()),
            child: Column(children: [
              Row(children: [
                IconTile(LucideIcons.scanFace, tone: tone, size: 48),
                gap12,
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: T.title),
                    Text(caption, style: T.caption),
                  ]),
                ),
                if (app.faceBusy)
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  Pill(template?.label ?? 'Belum ada', icon: active ? LucideIcons.circleCheck : pending ? LucideIcons.hourglass : LucideIcons.circleDashed, tone: tone),
              ]),
              gap16,
              Btn(
                template == null ? 'Daftarkan Wajah' : 'Kelola Data Wajah',
                kind: BtnKind.soft,
                icon: template == null ? LucideIcons.scanFace : LucideIcons.settings2,
                height: 48,
                onTap: () => push(context, const FaceEnrollmentScreen()),
              ),
            ]),
          );
        },
      );
}

// ------------------------------------------------------- profile: sync card

/// Offline outbox summary plus a manual sync trigger.
class SyncCard extends StatefulWidget {
  const SyncCard({super.key});

  @override
  State<SyncCard> createState() => _SyncCardState();
}

class _SyncCardState extends State<SyncCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => app.flushOutbox());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final pending = app.pendingSyncCount;
          final last = app.lastSync;
          final title = app.syncing
              ? 'Menyinkronkan presensi...'
              : pending == 0
                  ? 'Semua presensi tersinkron'
                  : '$pending presensi menunggu';
          final caption = app.syncError != null
              ? app.syncError!
              : last == null
                  ? 'Presensi offline dikirim otomatis saat online.'
                  : 'Batch #${last.id} · ${last.processedEvents}/${last.totalEvents} diproses';

          return AppCard(
            child: Column(children: [
              Row(children: [
                IconTile(
                  pending == 0 ? LucideIcons.cloudCheck : LucideIcons.cloudUpload,
                  tone: app.syncError != null ? Tone.danger : pending == 0 ? Tone.success : Tone.warning,
                  size: 48,
                ),
                gap12,
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: T.title),
                    Text(caption, style: T.caption),
                  ]),
                ),
                if (pending > 0) Pill('$pending', tone: Tone.warning),
              ]),
              gap16,
              Btn(
                app.syncing ? 'Menyinkronkan...' : 'Sinkronkan Sekarang',
                kind: BtnKind.light,
                icon: LucideIcons.refreshCw,
                height: 48,
                busy: app.syncing,
                onTap: app.syncing ? null : () => app.flushOutbox(),
              ),
            ]),
          );
        },
      );
}

// ------------------------------------------------------- face management

class FaceEnrollmentScreen extends StatefulWidget {
  const FaceEnrollmentScreen({super.key});

  @override
  State<FaceEnrollmentScreen> createState() => _FaceEnrollmentScreenState();
}

class _FaceEnrollmentScreenState extends State<FaceEnrollmentScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => app.loadFaceState());
  }

  Future<void> _revoke(FaceTemplate template) async {
    final ok = await confirm(
      context,
      title: 'Cabut template v${template.version}?',
      message: 'Template ini tidak lagi dipakai untuk verifikasi. Kamu bisa mendaftarkan wajah baru kapan saja.',
      action: 'Cabut',
      icon: LucideIcons.shieldX,
      danger: true,
    );
    if (!ok || !mounted) return;
    final done = await app.revokeFaceTemplate(template.id);
    if (!mounted) return;
    toast(
      context,
      done ? 'Template wajah dicabut.' : app.faceError ?? 'Gagal mencabut template.',
      icon: done ? LucideIcons.circleCheck : LucideIcons.triangleAlert,
      aboveNav: true,
    );
  }

  Future<void> _delete(FaceTemplate template) async {
    final ok = await confirm(
      context,
      title: 'Hapus template v${template.version}?',
      message: 'Template ditandai terhapus dan tidak bisa dipakai lagi. Tindakan ini tercatat di audit log.',
      action: 'Hapus',
      icon: LucideIcons.trash2,
      danger: true,
    );
    if (!ok || !mounted) return;
    final done = await app.deleteFaceTemplate(template.id);
    if (!mounted) return;
    toast(
      context,
      done ? 'Template wajah dihapus.' : app.faceError ?? 'Gagal menghapus template.',
      icon: done ? LucideIcons.circleCheck : LucideIcons.triangleAlert,
      aboveNav: true,
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final current = app.currentFaceTemplate;
          final enrollment = app.faceEnrollment;
          final active = current?.isActive ?? false;
          final pending = current?.isPending ?? false;
          final tone = active ? Tone.success : pending ? Tone.warning : Tone.neutral;

          return Screen(
            header: const PageHeader('Data Wajah', subtitle: 'Verifikasi biometrik', back: true),
            children: [
              AppCard(
                child: Column(children: [
                  IconTile(
                    active ? LucideIcons.scanFace : pending ? LucideIcons.hourglass : LucideIcons.scanFace,
                    tone: tone,
                    size: 64,
                  ),
                  gap12,
                  Text(
                    active ? 'Wajah terverifikasi' : pending ? 'Menunggu verifikasi' : 'Belum ada wajah terdaftar',
                    style: T.h2,
                    textAlign: TextAlign.center,
                  ),
                  gap4,
                  Text(
                    current == null
                        ? 'Daftarkan wajah agar absensi bisa diverifikasi.'
                        : 'Template versi ${current.version}${current.provider == null ? '' : ' · ${current.provider}'}',
                    style: T.caption,
                    textAlign: TextAlign.center,
                  ),
                  gap12,
                  if (current != null)
                    Pill(current.label, icon: active ? LucideIcons.circleCheck : pending ? LucideIcons.hourglass : LucideIcons.circleDashed, tone: tone),
                  if (enrollment != null) ...[
                    gap12,
                    InfoRow('Permintaan terakhir', '#${enrollment.id} · ${enrollment.status}', icon: LucideIcons.history),
                    if (enrollment.sampleCount > 0)
                      InfoRow('Sampel terekam', '${enrollment.sampleCount} sudut', icon: LucideIcons.camera),
                  ],
                ]),
              ),
              gap12,
              const Banner2(
                'Verifikasi wajah belum aktif',
                body: 'Model wajah belum tersedia. Pendaftaran disimpan sebagai menunggu verifikasi dan tidak dipakai untuk keputusan absensi.',
                tone: Tone.info,
                icon: LucideIcons.info,
              ),
              if (app.faceError != null) ...[
                gap12,
                Banner2(
                  'Data wajah belum tersinkron',
                  body: app.faceError,
                  tone: Tone.warning,
                  icon: LucideIcons.cloudOff,
                  trailing: TextButton(
                    onPressed: app.faceBusy ? null : () => app.loadFaceState(),
                    child: const Text('Coba lagi'),
                  ),
                ),
              ],
              const Overline('TINDAKAN'),
              Btn(
                active || pending ? 'Daftarkan Ulang Wajah' : 'Daftarkan Wajah',
                icon: LucideIcons.scanFace,
                busy: app.faceBusy,
                onTap: app.faceBusy ? null : () => push(context, const FaceTips()),
              ),
              const Overline('RIWAYAT TEMPLATE'),
              if (app.faceTemplates.isEmpty)
                AppCard(
                  color: C.sageSoft,
                  child: Row(children: [
                    const IconTile(LucideIcons.folderOpen, tone: Tone.neutral),
                    gap12,
                    Expanded(child: Text('Belum ada template wajah. Riwayat versi akan muncul di sini.', style: T.body)),
                  ]),
                )
              else
                for (final template in app.faceTemplates)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      padding: const EdgeInsets.all(14),
                      radius: 20,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          IconTile(
                            template.isActive ? LucideIcons.shieldCheck : template.isPending ? LucideIcons.hourglass : LucideIcons.shieldOff,
                            tone: template.isActive ? Tone.success : template.isPending ? Tone.warning : Tone.neutral,
                          ),
                          gap12,
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Versi ${template.version}', style: T.title),
                              Text(
                                [
                                  template.label,
                                  if (template.provider != null) template.provider!,
                                  if (template.revokedAt != null) 'dicabut',
                                  if (template.deletedAt != null) 'dihapus',
                                ].join(' · '),
                                style: T.caption,
                              ),
                            ]),
                          ),
                          if (template.canRevoke)
                            TextButton(
                              onPressed: app.faceBusy ? null : () => _revoke(template),
                              child: const Text('Cabut'),
                            ),
                          if (template.canDelete)
                            TextButton(
                              onPressed: app.faceBusy ? null : () => _delete(template),
                              style: TextButton.styleFrom(foregroundColor: C.dangerText),
                              child: const Text('Hapus'),
                            ),
                        ]),
                      ]),
                    ),
                  ),
              gap16,
              Row(children: [
                const Icon(LucideIcons.lock, size: 16, color: C.text3),
                gap8,
                Expanded(child: Text('Template disimpan sebagai referensi buram. Foto dan embedding tidak disimpan di server.', style: T.caption)),
              ]),
            ],
          );
        },
      );
}
