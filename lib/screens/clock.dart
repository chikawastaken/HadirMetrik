import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons_flutter.dart';

import '../main.dart';
import '../state.dart';
import '../theme.dart';
import '../visuals.dart';
import '../widgets.dart';

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
