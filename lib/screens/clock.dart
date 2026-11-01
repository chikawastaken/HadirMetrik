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
  Widget build(BuildContext context) => Screen(
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
          gap16,
          Btn(
            app.clockIn == null ? 'Masuk Sekarang' : 'Keluar Sekarang',
            icon: app.clockIn == null ? LucideIcons.logIn : LucideIcons.logOut,
            onTap: () => app.recordClock(),
          ),
          gap12,
          Text('Status: ${app.clockIn == null ? 'Belum masuk' : app.clockOut == null ? 'Masuk (belum keluar)' : 'Selesai'}', style: T.caption),
        ],
      );
}
