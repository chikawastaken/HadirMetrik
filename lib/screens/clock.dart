import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

void startClock(BuildContext context) {
  if (app.onLeave) {
    return toast(context, 'Hari ini kamu cuti. Absen tidak diperlukan.',
        icon: LucideIcons.plane, aboveNav: true);
  }
  if (app.dayDone) {
    return toast(context, 'Absen hari ini sudah lengkap.', aboveNav: true);
  }
  Navigator.of(context, rootNavigator: true)
      .push(MaterialPageRoute(builder: (_) => const ClockScreen()));
}

class ClockScreen extends StatelessWidget {
  const ClockScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) => Screen(
          inShell: true,
          header: const PageHeader('Absen Hari Ini'),
          children: [
            AppCard(
              child: Column(children: [
                const Icon(LucideIcons.clock, size: 48, color: Colors.black),
                gap12,
                Text(app.clockIn == null ? 'Belum masuk' : 'Masuk ${app.now.hour}:${app.now.minute.toString().padLeft(2, '0')}', style: T.h2),
              ]),
            ),
            if (app.clockNotice != null) ...[
              gap12,
              Banner2(
                app.pendingSyncCount > 0 ? 'Presensi menunggu sinkron' : 'Presensi belum tercatat',
                body: app.clockNotice,
                tone: app.pendingSyncCount > 0 ? Tone.warning : Tone.danger,
                icon: app.pendingSyncCount > 0 ? LucideIcons.cloudOff : LucideIcons.triangleAlert,
              ),
            ],
            gap16,
            Btn(
              app.clockIn == null ? 'Masuk Sekarang' : 'Keluar Sekarang',
              icon: app.clockIn == null ? LucideIcons.logIn : LucideIcons.logOut,
              busy: app.clockBusy,
              onTap: app.clockBusy ? null : () => app.recordClock(),
            ),
            gap12,
            Text('Status: ${app.clockIn == null ? 'Belum masuk' : app.clockOut == null ? 'Masuk (belum keluar)' : 'Selesai'}', style: T.caption),
            if (app.pendingSyncCount > 0) ...[
              gap12,
              AppCard(
                color: C.warningSubtle,
                border: C.warning.withValues(alpha: .2),
                child: Row(children: [
                  const IconTile(LucideIcons.cloudUpload, tone: Tone.warning),
                  gap12,
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${app.pendingSyncCount} presensi di perangkat', style: T.title),
                      Text('Dikirim saat aplikasi dibuka atau lewat tombol Sinkronkan.', style: T.caption),
                    ]),
                  ),
                  Btn(
                    'Sinkronkan',
                    expand: false,
                    height: 40,
                    kind: BtnKind.soft,
                    busy: app.syncing,
                    onTap: app.syncing ? null : () => app.flushOutbox(),
                  ),
                ]),
              ),
            ],
          ],
        ),
      );
}
