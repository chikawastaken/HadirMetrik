import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data.dart';
import '../state.dart';
import '../theme.dart';
import '../visuals.dart';
import '../widgets.dart';
import 'hr_main.dart';
import 'hr_work.dart';
import 'tasks.dart';

String _dec(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

const _shifts = ['Pagi 08.00-17.00', 'Siang 13.00-22.00', 'Malam 21.00-06.00'];

/// Demo shift assignment derived from the employee ID (0 pagi, 1 siang, 2 malam).
int shiftOf(Person p) => (int.tryParse(p.id.substring(3)) ?? 0) % 3;

String bossOf(Person p) => switch (p.division) {
      _ when p.role.contains('Supervisor') || p.role.contains('HR') => 'Direktur Operasional',
      'Operasional' => 'Dimas Ardiansyah',
      'Penjualan' => 'Hendra Kusuma',
      _ => 'Sari Wulandari',
    };

/// Bottom-sheet list picker; returns the chosen index.
Future<int?> pickOne(BuildContext context, String title, List<String> items, int current) => showSheet<int>(
      context,
      (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
        SheetHead(title),
        for (final (i, l) in items.indexed)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            title: Text(l, style: T.bodyM),
            trailing: RadioDot(i == current),
            onTap: () => Navigator.pop(ctx, i),
          ),
        gap16,
      ]),
    );

// ---------------------------------------------------------------- C05 karyawan

class Employees extends StatefulWidget {
  const Employees({super.key});
  @override
  State<Employees> createState() => _EmployeesState();
}

class _EmployeesState extends State<Employees> {
  String q = '';
  int div = 0, status = 0, shift = 0;
  static const _status = ['Semua status', 'Hadir', 'Terlambat', 'Absen', 'Cuti', 'Menunggu'];
  static const _shift = ['Semua shift', 'Pagi', 'Siang', 'Malam'];

  int get active => [div, status, shift].where((v) => v > 0).length;

  void filter() {
    var (d, s, h) = (div, status, shift);
    showSheet(
      context,
      (ctx) => StatefulBuilder(
        builder: (ctx, set) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SheetHead('Filter karyawan'),
          Flexible(
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 16), children: [
              Text('Divisi', style: T.title),
              gap8,
              ChipWrap(const ['Semua divisi', ...divisions], (i) => i == d, (i) => set(() => d = i)),
              gap16,
              Text('Status hari ini', style: T.title),
              gap8,
              ChipWrap(_status, (i) => i == s, (i) => set(() => s = i)),
              gap16,
              Text('Shift', style: T.title),
              gap8,
              ChipWrap(_shift, (i) => i == h, (i) => set(() => h = i)),
              gap20,
              Row(children: [
                Expanded(child: Btn('Reset', kind: BtnKind.light, onTap: () => set(() => (d, s, h) = (0, 0, 0)))),
                gap12,
                Expanded(
                  child: Btn('Terapkan', onTap: () {
                    setState(() {
                      div = d;
                      status = s;
                      shift = h;
                    });
                    Navigator.pop(ctx);
                  }),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final all = [...app.newEmployees, ...employees];
          final list = all.where((p) {
            if (q.isNotEmpty && !'${p.name} ${p.id} ${p.role}'.toLowerCase().contains(q.toLowerCase())) return false;
            if (div > 0 && p.division != divisions[div - 1]) return false;
            if (status > 0 && p.status != Att.values[status - 1]) return false;
            if (shift > 0 && shiftOf(p) != shift - 1) return false;
            return true;
          }).toList();
          return Stack(children: [
            Screen(
              inShell: true,
              header: PageHeader('Karyawan', subtitle: 'PT Sinar Metrik Nusantara · ${214 + app.newEmployees.length} karyawan', actions: [
                CircleBtn(LucideIcons.download, tooltip: 'Unduh data', onTap: () => toast(context, 'Data_Karyawan_Okt2026.xlsx diunduh.', aboveNav: true, icon: LucideIcons.download)),
              ]),
              children: [
                Row(children: [
                  Expanded(child: Field(hint: 'Cari nama, ID atau jabatan', icon: LucideIcons.search, onChanged: (v) => setState(() => q = v))),
                  gap8,
                  Badge(
                    isLabelVisible: active > 0,
                    label: Text('$active'),
                    backgroundColor: C.accent,
                    child: CircleBtn(LucideIcons.slidersHorizontal, size: 52, bg: active > 0 ? C.accentSubtle : Colors.white, tooltip: 'Filter', onTap: filter),
                  ),
                ]),
                if (active > 0) ...[
                  gap8,
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final (v, l, clear) in [
                      (div, div > 0 ? divisions[div - 1] : '', () => div = 0),
                      (status, _status[status], () => status = 0),
                      (shift, 'Shift ${_shift[shift]}', () => shift = 0),
                    ])
                      if (v > 0)
                        InkWell(
                          onTap: () => setState(clear),
                          borderRadius: BorderRadius.circular(99),
                          child: Pill(l, icon: LucideIcons.x, tone: Tone.sage),
                        ),
                  ]),
                ],
                gap12,
                Text(q.isEmpty && div + status + shift == 0 ? '${214 + app.newEmployees.length} karyawan · 186 hadir hari ini' : '${list.length} hasil', style: T.caption),
                gap8,
                if (list.isEmpty) const EmptyState(icon: LucideIcons.userSearch, title: 'Karyawan tidak ditemukan', message: 'Coba kata kunci atau filter lain.'),
                for (final p in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      padding: const EdgeInsets.all(14),
                      radius: 20,
                      onTap: () => push(context, EmployeeDetail(p), root: true),
                      child: Row(children: [
                        Avatar(p.initials, size: 44, dot: p.status.dot),
                        gap12,
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(p.name, style: T.title),
                            Text('${p.id} · ${p.role} · ${p.division}', style: T.small, maxLines: 1, overflow: TextOverflow.ellipsis),
                            gap4,
                            Row(children: [
                              Icon(p.faceOk ? LucideIcons.scanFace : LucideIcons.circleAlert, size: 13, color: p.faceOk ? C.accent : C.warningText),
                              gap4,
                              Text(p.faceOk ? 'Wajah terdaftar' : 'Wajah belum terdaftar', style: T.small.copyWith(color: p.faceOk ? C.text3 : C.warningText)),
                            ]),
                          ]),
                        ),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Pill(p.status.label, icon: p.status.icon, tone: p.status.tone),
                          if (p.score != null) ...[gap4, Text('Skor ${p.score}', style: T.small)],
                        ]),
                      ]),
                    ),
                  ),
              ],
            ),
            Positioned(
              right: 20,
              bottom: navClearance - 8,
              child: FloatingActionButton.extended(
                heroTag: 'emp',
                backgroundColor: C.primary,
                foregroundColor: Colors.white,
                onPressed: () => push(context, const AddEmployee(), root: true),
                icon: const Icon(LucideIcons.userPlus, size: 20),
                label: Text('Tambah Karyawan', style: T.button.copyWith(color: Colors.white)),
              ),
            ),
          ]);
        },
      );
}

class AddEmployee extends StatefulWidget {
  const AddEmployee({super.key});
  @override
  State<AddEmployee> createState() => _AddEmployeeState();
}

class _AddEmployeeState extends State<AddEmployee> {
  final name = TextEditingController(), email = TextEditingController(), phone = TextEditingController(), role = TextEditingController();
  final base = TextEditingController(text: '5.200.000'), transport = TextEditingController(text: '575.000'), meal = TextEditingController(text: '690.000');
  int div = 0, shift = 0, loc = 0, boss = 0, start = 19;
  bool invite = true, tried = false, busy = false;
  late final id = 'HM-0${315 + app.newEmployees.length}';

  static const _boss = ['Dimas Ardiansyah', 'Hendra Kusuma', 'Sari Wulandari'];

  int _n(TextEditingController c) => int.tryParse(c.text.replaceAll('.', '')) ?? 0;

  @override
  void dispose() {
    for (final c in [name, email, phone, role, base, transport, meal]) {
      c.dispose();
    }
    super.dispose();
  }

  String? get nameErr => tried && name.text.trim().length < 3 ? 'Nama lengkap wajib diisi' : null;
  String? get emailErr => tried && !RegExp(r'^\S+@\S+\.\S+$').hasMatch(email.text.trim()) ? 'Format email belum benar' : null;
  String? get phoneErr => tried && phone.text.replaceAll(RegExp(r'\D'), '').length < 10 ? 'Nomor WhatsApp minimal 10 digit' : null;
  String? get roleErr => tried && role.text.trim().isEmpty ? 'Jabatan wajib diisi' : null;

  Future<void> save() async {
    setState(() => tried = true);
    if ([nameErr, emailErr, phoneErr, roleErr].any((e) => e != null)) return;
    setState(() => busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    final n = name.text.trim();
    app.newEmployees.insert(0, Person(n, role.text.trim(), divisions[div], id, status: Att.menunggu, faceOk: false, location: ['Kantor Pusat', 'Gudang Kalasan'][loc]));
    app.touch();
    setState(() => busy = false);
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: IconTile(invite ? LucideIcons.send : LucideIcons.userCheck, tone: Tone.success, size: 52, round: true)),
            gap12,
            Text(invite ? 'Undangan terkirim' : 'Karyawan ditambahkan', style: T.h2, textAlign: TextAlign.center),
            gap4,
            Text(invite ? 'Tautan registrasi wajah dikirim ke WhatsApp dan email $n.' : '$n tersimpan tanpa undangan registrasi.', style: T.small, textAlign: TextAlign.center),
            gap12,
            Flexible(
              child: SingleChildScrollView(
                child: AppCard(
                  color: C.sageSoft,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: Divided([
                    for (final (l, v) in [
                      ('Nama', n),
                      ('ID', id),
                      ('Email', email.text.trim()),
                      ('WhatsApp', phone.text.trim()),
                      ('Divisi · jabatan', '${divisions[div]} · ${role.text.trim()}'),
                      ('Atasan', _boss[boss]),
                      ('Shift', _shifts[shift]),
                      ('Lokasi', ['Kantor Pusat Yogyakarta', 'Gudang Kalasan'][loc]),
                      ('Mulai', 'Senin, $start Oktober 2026'),
                      ('Total gaji', rp(_n(base) + _n(transport) + _n(meal))),
                    ])
                      InfoRow(l, v),
                  ]),
                ),
              ),
            ),
            gap16,
            Btn('Selesai', onTap: () => Navigator.pop(ctx)),
          ]),
        ),
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Screen(
        header: const TopBar('Tambah Karyawan'),
        bottom: BottomActions([
          Btn('Batal', kind: BtnKind.light, onTap: () => Navigator.pop(context)),
          Btn('Simpan & Undang', icon: LucideIcons.send, busy: busy, onTap: busy ? null : save),
        ]),
        children: [
          const Overline('DATA DIRI'),
          Field(label: 'Nama lengkap', hint: 'Sesuai KTP', icon: LucideIcons.user, controller: name, error: nameErr, onChanged: (_) => tried ? setState(() {}) : null),
          gap12,
          Field(label: 'ID karyawan', initial: id, icon: LucideIcons.idCard, readOnly: true, helper: 'Dibuat otomatis'),
          gap12,
          Field(label: 'Email kantor', hint: 'nama@sinarmetrik.co.id', icon: LucideIcons.mail, controller: email, keyboard: TextInputType.emailAddress, error: emailErr, onChanged: (_) => tried ? setState(() {}) : null),
          gap12,
          Field(label: 'No. WhatsApp', hint: '0812 3456 7890', icon: LucideIcons.phone, controller: phone, keyboard: TextInputType.phone, error: phoneErr, onChanged: (_) => tried ? setState(() {}) : null),
          const Overline('PEKERJAAN'),
          PickerBox(
            small: 'Divisi',
            value: divisions[div],
            icon: LucideIcons.building2,
            onTap: () async {
              final r = await pickOne(context, 'Divisi', divisions, div);
              if (r != null) setState(() => div = r);
            },
          ),
          gap12,
          Field(label: 'Jabatan', hint: 'Contoh: Staf Gudang', icon: LucideIcons.briefcase, controller: role, error: roleErr, onChanged: (_) => tried ? setState(() {}) : null),
          gap12,
          PickerBox(
            small: 'Atasan langsung',
            value: _boss[boss],
            icon: LucideIcons.userCheck,
            onTap: () async {
              final r = await pickOne(context, 'Atasan langsung', _boss, boss);
              if (r != null) setState(() => boss = r);
            },
          ),
          gap12,
          PickerBox(
            small: 'Tanggal mulai',
            value: 'Senin, $start Oktober 2026',
            icon: LucideIcons.calendar,
            onTap: () => showSheet(
              context,
              (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
                const SheetHead('Tanggal mulai'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: MonthGrid(year: 2026, month: 10, selected: start, onTap: (d) {
                    setState(() => start = d);
                    Navigator.pop(ctx);
                  }),
                ),
              ]),
            ),
          ),
          gap16,
          Text('Shift', style: T.title),
          gap8,
          ChipWrap(_shifts, (i) => i == shift, (i) => setState(() => shift = i)),
          gap16,
          Text('Lokasi kerja', style: T.title),
          gap8,
          ChipWrap(const ['Kantor Pusat Yogyakarta', 'Gudang Kalasan'], (i) => i == loc, (i) => setState(() => loc = i)),
          const Overline('GAJI'),
          Field(label: 'Gaji pokok', icon: LucideIcons.banknote, controller: base, keyboard: TextInputType.number, onChanged: (_) => setState(() {})),
          gap12,
          Row(children: [
            Expanded(child: Field(label: 'Transport', controller: transport, keyboard: TextInputType.number, onChanged: (_) => setState(() {}))),
            gap12,
            Expanded(child: Field(label: 'Makan', controller: meal, keyboard: TextInputType.number, onChanged: (_) => setState(() {}))),
          ]),
          gap12,
          AppCard(
            color: C.sageSoft,
            child: Row(children: [
              Expanded(child: Text('Total per bulan', style: T.bodyM)),
              Text(rp(_n(base) + _n(transport) + _n(meal)), style: T.numS.copyWith(color: C.primary)),
            ]),
          ),
          gap12,
          ToggleTile('Kirim undangan registrasi wajah', invite, (v) => setState(() => invite = v), subtitle: 'Lewat WhatsApp dan email kantor'),
        ],
      );
}

// ---------------------------------------------------------------- C06 detail karyawan

class EmployeeDetail extends StatefulWidget {
  const EmployeeDetail(this.p, {super.key});
  final Person p;
  @override
  State<EmployeeDetail> createState() => _EmployeeDetailState();
}

class _EmployeeDetailState extends State<EmployeeDetail> {
  int tab = 0;
  final notes = <String>[];

  Person get p => widget.p;
  int get score => p.score ?? 0;

  void addNote() {
    final c = TextEditingController();
    showSheet(
      context,
      (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SheetHead('Catatan untuk ${p.name.split(' ').first}', subtitle: 'Hanya terlihat oleh HR'),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(children: [
              Field(hint: 'Tulis catatan', controller: c, maxLines: 3),
              gap16,
              Btn('Simpan Catatan', onTap: () {
                if (c.text.trim().isEmpty) return;
                setState(() => notes.insert(0, c.text.trim()));
                Navigator.pop(ctx);
                toast(context, 'Catatan disimpan.');
              }),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _ringkasan() {
    final risk = p.name == 'Fajar Nugroho';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        child: Row(children: [
          Ring(score / 100, size: 84, stroke: 9, color: score >= 85 ? C.accent : (score >= 70 ? C.warning : C.danger), child: Text('$score', style: T.numM)),
          gap16,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Skor kehadiran', style: T.caption),
              Text('$score/100', style: T.h3),
              gap4,
              score >= 85
                  ? const Pill('Sangat baik', icon: LucideIcons.thumbsUp)
                  : (score >= 70 ? const Pill('Cukup', icon: LucideIcons.minus, tone: Tone.warning) : const Pill('Perlu perhatian', icon: LucideIcons.triangleAlert, tone: Tone.danger)),
            ]),
          ),
        ]),
      ),
      const Overline('INFORMASI PEKERJAAN'),
      AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Divided([
          InfoRow('Atasan langsung', bossOf(p), icon: LucideIcons.userCheck),
          InfoRow('Shift', _shifts[shiftOf(p)], icon: LucideIcons.clock),
          InfoRow('Lokasi kerja', p.location, icon: LucideIcons.mapPin),
          InfoRow('Divisi · jabatan', '${p.division} · ${p.role}', icon: LucideIcons.briefcase),
          const InfoRow('Bergabung', '3 Mar 2023', icon: LucideIcons.calendar),
        ]),
      ),
      Overline(risk ? 'PROFIL RISIKO [DL]' : 'PROFIL RISIKO'),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Tingkat risiko', style: T.bodyM)),
            risk || score < 70
                ? const Pill('Tinggi', icon: LucideIcons.triangleAlert, tone: Tone.danger)
                : (score < 85 ? const Pill('Sedang', icon: LucideIcons.minus, tone: Tone.warning) : const Pill('Rendah', icon: LucideIcons.shieldCheck)),
          ]),
          gap12,
          for (final (l, v) in risk
              ? const [('Lokasi palsu', .93), ('Pola absen', .64), ('Keterlambatan', .35), ('Kualitas tugas', .30)]
              : [('Lokasi palsu', .05), ('Pola absen', (100 - score) / 100), ('Keterlambatan', (100 - score) / 80), ('Kualitas tugas', (100 - score) / 120)])
            barRow(l, v, _dec(v), color: v >= .7 ? C.danger : (v >= .5 ? C.warning : C.primary)),
        ]),
      ),
      const Overline('30 HARI TERAKHIR'),
      AppCard(
        child: Row(children: [
          for (final (v, l, c) in risk ? const [('15', 'Hadir', C.accent), ('4', 'Terlambat', C.warningText), ('2', 'Absen', C.dangerText)] : const [('20', 'Hadir', C.accent), ('2', 'Terlambat', C.warningText), ('0', 'Absen', C.dangerText)])
            Expanded(child: Column(children: [Text(v, style: T.numM.copyWith(color: c)), Text(l, style: T.small)])),
        ]),
      ),
      gap12,
      Row(children: [
        Expanded(
          child: AppCard(
            radius: 20,
            onTap: () => setState(() => tab = 2),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Tugas tepat waktu', style: T.small),
              Text(risk ? '70%' : '88%', style: T.numM),
              gap8,
              Bar(risk ? .7 : .88),
            ]),
          ),
        ),
        gap12,
        Expanded(
          child: AppCard(
            radius: 20,
            onTap: () => setState(() => tab = 3),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Gaji Oktober', style: T.small),
              Text(risk ? 'Rp 5.221.000' : rp(app.payroll.where((r) => r.who == p).firstOrNull?.takeHome ?? 6450000), style: T.title),
              gap8,
              Text('Belum dipublikasikan', style: T.small.copyWith(color: C.warningText)),
            ]),
          ),
        ),
      ]),
      const Overline('RIWAYAT KEAMANAN'),
      AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Divided([
          for (final (icon, t, s, tone) in risk
              ? const [
                  (LucideIcons.mapPinOff, 'Terindikasi lokasi palsu', 'Rab, 7 Okt · 08.47 · skor 0,93', Tone.danger),
                  (LucideIcons.mapPinOff, 'Terindikasi lokasi palsu', 'Jum, 2 Okt · 08.52 · skor 0,88', Tone.danger),
                  (LucideIcons.smartphone, 'Ganti perangkat ditolak', 'Sen, 28 Sep · Vivo Y36', Tone.warning),
                ]
              : const [(LucideIcons.shieldCheck, 'Tidak ada kejadian', '90 hari terakhir', Tone.success)])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                IconTile(icon, tone: tone, size: 34, round: true),
                gap12,
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: T.bodyM), Text(s, style: T.small)])),
              ]),
            ),
        ]),
      ),
      if (notes.isNotEmpty) ...[
        const Overline('CATATAN HR'),
        for (final n in notes) Padding(padding: const EdgeInsets.only(bottom: 8), child: AppCard(color: C.sageSoft, child: Text(n, style: T.body))),
      ],
      const Overline('TINDAKAN AKUN'),
      AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(children: [
          MenuRow(LucideIcons.smartphone, 'Reset perangkat', subtitle: 'Karyawan harus login ulang di perangkat baru', onTap: () async {
            if (await confirm(context, title: 'Reset perangkat ${p.name}?', message: 'Perangkat lama akan keluar otomatis.', action: 'Reset', icon: LucideIcons.smartphone) && mounted) {
              toast(context, 'Perangkat ${p.name} direset.');
            }
          }),
          MenuRow(LucideIcons.userX, 'Nonaktifkan karyawan', danger: true, onTap: () async {
            if (await confirm(context, title: 'Nonaktifkan ${p.name}?', message: 'Karyawan tidak bisa clock-in sampai diaktifkan lagi.', action: 'Nonaktifkan', icon: LucideIcons.userX, danger: true) && mounted) {
              toast(context, '${p.name} dinonaktifkan.');
            }
          }),
        ]),
      ),
    ]);
  }

  Widget _kehadiran() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppCard(
          child: Column(children: [
            const CardTitle('Oktober 2026'),
            gap8,
            MonthGrid(
              year: 2026,
              month: 10,
              today: 7,
              dots: p.name == 'Fajar Nugroho'
                  ? const {1: C.accent, 2: C.danger, 5: C.warning, 6: C.accent, 7: C.danger}
                  : {for (final d in octDays.where((d) => d.day <= 7)) d.day: d.status.dot},
            ),
            gap12,
            const Legend([('Hadir', C.accent), ('Terlambat', C.warning), ('Absen', C.danger), ('Cuti', C.info)]),
          ]),
        ),
        gap12,
        AppCard(
          child: Column(children: [
            for (final (d, i, o) in const [('Rab, 7 Okt', '-', '-'), ('Sel, 6 Okt', '07.55', '17.04'), ('Sen, 5 Okt', '08.21', '17.10'), ('Jum, 2 Okt', '08.52', '17.00')])
              InfoRow(d, i == '-' ? 'Belum clock-in' : '$i - $o', icon: LucideIcons.calendarDays),
          ]),
        ),
      ]);

  Widget _tugas() {
    final mine = app.hrTasks.where((t) => t.assignees.contains(p.name)).toList();
    if (mine.isEmpty) return const EmptyState(icon: LucideIcons.clipboardList, title: 'Belum ada tugas', message: 'Tugas yang diberikan akan muncul di sini.');
    return Column(children: [
      for (final t in mine) Padding(padding: const EdgeInsets.only(bottom: 10), child: TaskCard(t, hr: true, onTap: () => push(context, TaskReview(t), root: true))),
    ]);
  }

  Widget _gaji() {
    final row = app.payroll.where((r) => r.who == p).firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        child: Column(children: [
          InfoRow('Gaji pokok', 'Rp 4.800.000', icon: LucideIcons.banknote),
          const InfoRow('Transport', 'Rp 575.000', icon: LucideIcons.bus),
          const InfoRow('Makan', 'Rp 690.000', icon: LucideIcons.utensils),
          const Divider(height: 20),
          InfoRow('Take-home Oktober', row != null ? rp(row.takeHome) : 'Rp 5.221.000'),
        ]),
      ),
      if (row != null) ...[
        gap12,
        Btn('Buka Detail Gaji', kind: BtnKind.soft, onTap: () => push(context, PayrollDetail(row))),
      ],
    ]);
  }

  Widget _izin() {
    final list = app.approvals.where((r) => r.who == p).toList();
    if (list.isEmpty) return const EmptyState(icon: LucideIcons.fileText, title: 'Belum ada pengajuan', message: 'Izin dan cuti karyawan muncul di sini.');
    return Column(children: [for (final r in list) Padding(padding: const EdgeInsets.only(bottom: 10), child: ApprovalCard(r))]);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) => Screen(
          header: TopBar('Detail Karyawan', actions: [CircleBtn(LucideIcons.ellipsisVertical, tooltip: 'Lainnya', onTap: addNote)]),
          children: [
            gap8,
            Center(child: Avatar(p.initials, size: 72, dot: p.status.dot)),
            gap12,
            Center(child: Text(p.name, style: T.h2)),
            Center(child: Text('${p.id} · ${p.role} · ${p.division}', style: T.caption)),
            gap8,
            Center(child: Pill('${p.status.label} hari ini', icon: p.status.icon, tone: p.status.tone)),
            gap16,
            Row(children: [
              for (final (icon, l, on) in [
                (LucideIcons.bellRing, 'Kirim pengingat', () => toast(context, 'Pengingat dikirim ke ${p.name}.')),
                (LucideIcons.clipboardPlus, 'Beri tugas', () => push(context, CreateTask(assignee: p.name))),
                (LucideIcons.notebookPen, 'Tambah catatan', addNote),
                (LucideIcons.phone, 'Hubungi', () => toast(context, 'Membuka WhatsApp ${p.name}.')),
              ])
                Expanded(
                  child: InkWell(
                    onTap: on,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(children: [IconTile(icon, size: 44, round: true), gap4, Text(l, style: T.small, textAlign: TextAlign.center)]),
                    ),
                  ),
                ),
            ]),
            gap16,
            ChipBar(const ['Ringkasan', 'Kehadiran', 'Tugas', 'Gaji', 'Izin'], tab, (i) => setState(() => tab = i), padding: EdgeInsets.zero),
            gap12,
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: KeyedSubtree(key: ValueKey(tab), child: [_ringkasan, _kehadiran, _tugas, _gaji, _izin][tab]()),
            ),
          ],
        ),
      );
}

// ---------------------------------------------------------------- C02 pantau lokasi

class LiveMonitor extends StatefulWidget {
  const LiveMonitor({super.key, this.tab = 0});
  final int tab;
  @override
  State<LiveMonitor> createState() => _LiveMonitorState();
}

class _LiveMonitorState extends State<LiveMonitor> {
  late int tab = widget.tab;
  String q = '';

  static const _pins = [
    MapPin(Alignment(-.1, -.05), C.accent),
    MapPin(Alignment(.12, .08), C.accent),
    MapPin(Alignment(-.2, .15), C.accent),
    MapPin(Alignment(.05, -.2), C.accent),
    MapPin(Alignment(.55, -.45), C.warning, size: 14),
    MapPin(Alignment(-.6, .4), C.danger, size: 16),
    MapPin(Alignment(.7, .3), C.danger, size: 16),
    MapPin(Alignment(-.45, -.55), C.danger, size: 16),
  ];

  Future<void> open(Incident inc) async {
    final r = await push<String>(context, IncidentDetail(inc));
    if (r == null || !mounted) return;
    final i = app.incidents.indexOf(inc);
    if (i < 0) return;
    app.incidents.removeAt(i);
    app.touch();
    toast(
      context,
      r == 'tolak' ? 'Absen ${inc.who.name} ditolak' : 'Absen ${inc.who.name} ditandai valid',
      action: 'Batalkan',
      onAction: () {
        app.incidents.insert(i.clamp(0, app.incidents.length), inc);
        app.touch();
      },
    );
  }

  bool _match(Person p) => q.isEmpty || p.name.toLowerCase().contains(q.toLowerCase());

  Widget _incidentCard(Incident inc) => AppCard(
        padding: const EdgeInsets.all(14),
        radius: 20,
        border: inc.high ? C.danger.withValues(alpha: .4) : null,
        onTap: () => open(inc),
        child: Row(children: [
          Avatar(inc.who.initials, size: 42, dot: C.danger),
          gap12,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(inc.who.name, style: T.title),
              Text(inc.reason, style: T.small, maxLines: 2, overflow: TextOverflow.ellipsis),
              gap4,
              Text('${inc.time} · ${inc.place}', style: T.small.copyWith(color: C.text3)),
            ]),
          ),
          gap8,
          Column(children: [
            Text(_dec(inc.risk), style: T.numS.copyWith(color: inc.high ? C.dangerText : C.warningText)),
            Text('risiko', style: T.small),
          ]),
        ]),
      );

  Widget _liveCard(LiveEntry e) => AppCard(
        padding: const EdgeInsets.all(14),
        radius: 20,
        onTap: () => push(context, EmployeeDetail(e.who)),
        child: Row(children: [
          Avatar(e.who.initials, size: 42, dot: e.state == 'luar' ? C.warning : C.accent),
          gap12,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.who.name, style: T.title),
              Text(e.distance ?? 'Di dalam area · ${e.place}', style: T.small),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(e.time, style: T.numS),
            e.state == 'luar' ? const Pill('Di luar area', tone: Tone.warning) : const Pill('Di dalam', icon: LucideIcons.check),
          ]),
        ]),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final inc = app.incidents.where((i) => _match(i.who)).toList();
          final live = liveEntries.where((e) => _match(e.who) && (tab != 1 || e.state == 'luar')).toList();
          return Scaffold(
            backgroundColor: C.bg,
            body: Stack(children: [
              const Positioned.fill(child: MapBox(height: double.infinity, radius: 0, fenceSize: .3, pins: _pins)),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(children: [
                    CircleBtn(LucideIcons.arrowLeft, bg: Colors.white, tooltip: 'Kembali', onTap: () => Navigator.pop(context)),
                    gap8,
                    Expanded(
                      child: Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        elevation: 2,
                        shadowColor: Colors.black12,
                        child: TextField(
                          onChanged: (v) => setState(() => q = v),
                          style: T.body,
                          decoration: InputDecoration(
                            hintText: 'Cari karyawan',
                            hintStyle: T.body.copyWith(color: C.text3),
                            prefixIcon: const Icon(LucideIcons.search, size: 18, color: C.text3),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                        ),
                      ),
                    ),
                    gap8,
                    CircleBtn(LucideIcons.slidersHorizontal, bg: Colors.white, tooltip: 'Filter', onTap: () async {
                      final r = await pickOne(context, 'Tampilkan', const ['Semua', 'Di luar area', 'Terindikasi palsu'], tab);
                      if (r != null) setState(() => tab = r);
                    }),
                  ]),
                ),
              ),
              DraggableScrollableSheet(
                initialChildSize: .52,
                minChildSize: .2,
                maxChildSize: .9,
                snap: true,
                builder: (context, sc) => Container(
                  decoration: const BoxDecoration(
                    color: C.bg,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                    boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 24, offset: Offset(0, -4))],
                  ),
                  child: ListView(controller: sc, padding: const EdgeInsets.fromLTRB(20, 10, 20, 32), children: [
                    Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: C.border, borderRadius: BorderRadius.circular(2)))),
                    gap12,
                    Text('Aktivitas lokasi hari ini', style: T.h3),
                    Text('195 clock-in · diperbarui 09.41', style: T.caption),
                    gap12,
                    ChipBar(['Semua 195', 'Di Luar Area 6', 'Terindikasi Palsu ${app.incidents.length}'], tab, (i) => setState(() => tab = i), padding: EdgeInsets.zero),
                    gap12,
                    if (tab != 1 && app.incidents.isNotEmpty) ...[
                      AppCard(
                        color: C.dangerSubtle,
                        padding: const EdgeInsets.all(14),
                        radius: 20,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            const Icon(LucideIcons.shieldAlert, size: 16, color: C.dangerText),
                            gap8,
                            Expanded(child: Text('Risiko lokasi palsu [DL]', style: T.title.copyWith(color: C.dangerText))),
                            Text('${app.incidents.where((i) => i.high).length} tinggi', style: T.small.copyWith(color: C.dangerText)),
                          ]),
                          gap8,
                          StackBar([for (final i in app.incidents) (1 / app.incidents.length, i.high ? C.danger : C.warning)], height: 8),
                        ]),
                      ),
                      gap12,
                    ],
                    if (tab == 2 && inc.isEmpty) const EmptyState(icon: LucideIcons.shieldCheck, title: 'Semua sudah ditinjau', message: 'Tidak ada lokasi palsu yang tersisa.'),
                    if (tab != 1) for (final i in inc) Padding(padding: const EdgeInsets.only(bottom: 10), child: _incidentCard(i)),
                    if (tab != 2) ...[
                      if (tab == 0) const Overline('CLOCK-IN TERBARU', padding: EdgeInsets.fromLTRB(4, 8, 4, 10)),
                      for (final e in live) Padding(padding: const EdgeInsets.only(bottom: 10), child: _liveCard(e)),
                    ],
                  ]),
                ),
              ),
            ]),
          );
        },
      );
}

class IncidentDetail extends StatefulWidget {
  const IncidentDetail(this.inc, {super.key});
  final Incident inc;
  @override
  State<IncidentDetail> createState() => _IncidentDetailState();
}

class _IncidentDetailState extends State<IncidentDetail> {
  final note = TextEditingController();

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inc = widget.inc;
    final name = inc.who.name;
    return Screen(
      header: const TopBar('Detail Kejadian'),
      bottom: BottomActions([
        Btn('Tandai Valid', kind: BtnKind.light, icon: LucideIcons.check, onTap: () => Navigator.pop(context, 'valid')),
        Btn('Tolak Absen', kind: BtnKind.danger, icon: LucideIcons.x, onTap: () async {
          final ok = await confirm(context, title: 'Tolak absen $name?', message: 'Clock-in pukul ${inc.time} dicatat sebagai absen dan $name mendapat notifikasi.', action: 'Tolak Absen', icon: LucideIcons.circleX, danger: true);
          if (ok && context.mounted) Navigator.pop(context, 'tolak');
        }),
      ]),
      children: [
        gap8,
        AppCard(
          color: inc.high ? C.dangerSubtle : C.warningSubtle,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Avatar(inc.who.initials, size: 44),
              gap12,
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: T.title), Text('${inc.who.id} · ${inc.who.role}', style: T.small)])),
            ]),
            gap16,
            Text('Terindikasi lokasi palsu', style: T.h3.copyWith(color: inc.high ? C.dangerText : C.warningText)),
            Text('${inc.time} · ${inc.place}', style: T.caption),
            gap12,
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_dec(inc.risk), style: T.numXL.copyWith(color: inc.high ? C.dangerText : C.warningText)),
              gap8,
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Pill(inc.high ? 'Risiko tinggi' : 'Risiko sedang', icon: LucideIcons.triangleAlert, tone: inc.high ? Tone.danger : Tone.warning, solid: true),
              ),
            ]),
            gap8,
            Bar(inc.risk, color: inc.high ? C.danger : C.warning, bg: Colors.white),
            gap4,
            Text('Skor model deteksi [DL]', style: T.small),
          ]),
        ),
        Overline('SINYAL TERDETEKSI · ${inc.signals.length} DARI 6'),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Divided([
            for (final (icon, t, s) in inc.signals)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  IconTile(icon, tone: t.startsWith('Wajah') ? Tone.success : Tone.danger, size: 34, round: true),
                  gap12,
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: T.bodyM), Text(s, style: T.small)])),
                ]),
              ),
          ]),
        ),
        const Overline('BUKTI CLOCK-IN'),
        Row(children: [
          Expanded(child: AspectRatio(aspectRatio: .8, child: ClipRRect(borderRadius: BorderRadius.circular(16), child: const FaceArt()))),
          gap12,
          const Expanded(child: AspectRatio(aspectRatio: .8, child: MapBox(height: double.infinity, fenceSize: .5, pins: [MapPin(Alignment(.7, -.6), C.danger, size: 16)]))),
        ]),
        gap8,
        Text('-7.7829, 110.3671 · akurasi 3 m · 2,3 km dari ${inc.place}', style: T.small),
        const Overline('PERANGKAT'),
        AppCard(
          child: Column(children: [
            InfoRow('Perangkat', inc.device, icon: LucideIcons.smartphone),
            InfoRow('Sistem', inc.os, icon: LucideIcons.cpu),
            const InfoRow('Terdaftar sejak', '12 Jan 2026', icon: LucideIcons.calendar),
            const InfoRow('Jaringan', 'Telkomsel 4G', icon: LucideIcons.signal),
          ]),
        ),
        const Overline('CATATAN AUDIT'),
        Field(hint: 'Opsional, tersimpan di log audit', controller: note, maxLines: 2),
      ],
    );
  }
}
