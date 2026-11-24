# HadirMetrik

Aplikasi Flutter HadirMetrik untuk karyawan dan HR.

## Menjalankan dengan backend lokal

Build debug memakai `http://127.0.0.1:8000/api/v1` secara default. Jalankan
`adb reverse` supaya alamat itu diteruskan ke komputer, sehingga **tidak perlu
mengganti IP setiap kali pindah jaringan** (Wi-Fi kampus, hotspot, kos teman):

```bash
cd ../hadirmetrik-backend
php artisan serve --host=0.0.0.0 --port=8000

cd ../HadirMetrik
tool/dev_run.sh              # adb reverse + flutter run
```

Jika ada lebih dari satu perangkat terhubung:

```bash
ANDROID_SERIAL=192.168.18.126:37215 tool/dev_run.sh -d 192.168.18.126:37215
```

### Mengganti alamat tanpa rebuild

Di layar Login build debug ada tombol **Server: …**. Ketuk, isi alamat
(mis. `192.168.18.124:8000`), tekan **Tes**, lalu **Simpan**. Alamat tersimpan
dan dipakai lagi saat aplikasi dibuka.

`--dart-define=API_URL=...` tetap didukung dan mengunci alamat untuk sesi itu:

```bash
flutter run --dart-define=API_URL=http://192.168.18.124:8000/api/v1
```

> Cleartext HTTP hanya diizinkan di manifest debug. Build release tetap
> memblokir HTTP biasa dan harus memakai HTTPS.

## Deep link undangan

Email undangan berisi halaman perantara HTTP (`/invitations/<token>`) yang
menawarkan tombol **Buka Aplikasi**. Tombol itu mengirim intent
`hadirmetrik://invitations/<token>` ke aplikasi.

Aplikasi **harus dipasang ulang** setelah `android/app/src/main/AndroidManifest.xml`
berubah, karena Android hanya mengetahui skema dari manifest yang terpasang:

```bash
ANDROID_SERIAL=192.168.18.126:37215 tool/dev_run.sh -d 192.168.18.126:37215
```

Uji tanpa email:

```bash
adb -s 192.168.18.126:37215 shell am start -W \
  -a android.intent.action.VIEW \
  -d "hadirmetrik://invitations/<token>" \
  com.hadirmetrik.hadirmetrik
```

Jika aplikasi tidak terbuka dan browser malah membuka Play Store dengan pesan
**“Item tidak ditemukan”**, berarti build yang terpasang belum mendaftarkan
skema tersebut. Pasang ulang APK debug, lalu coba lagi.

Saat link dibuka:

- aplikasi tertutup → langsung ke layar **Buat Kata Sandi**;
- aplikasi sudah berjalan dan belum login → layar **Buat Kata Sandi**;
- aplikasi sudah login → layar konfirmasi undangan.

## Status integrasi layar

Per 2026-11-24. Kontrak API: `docs/openapi/app.yaml` di repo backend.

| Area | Status |
|---|---|
| Login, sesi, undangan, ganti kata sandi | API |
| Profil, ubah telepon, riwayat dan koreksi presensi | API |
| Absen masuk/keluar, outbox offline | API; verifikasi wajah belum memakai model nyata |
| Tugas karyawan dan HR | API |
| Cuti/izin/lembur dan persetujuan HR | API, tanpa lampiran |
| Notifikasi | API, tanpa push dan tanpa "belum dibaca" di server |
| Karyawan HR: daftar, tambah, reset kata sandi, kirim ulang undangan | API |
| Karyawan HR: kehadiran di detail, monitor langsung, insiden | Mock |
| Gaji dan slip (`me.dart`), penggajian HR (`hr_main.dart`) | Mock, menunggu Phase 7 backend |
| Dashboard, laporan, statistik HR (`hr_main.dart`) | Mock, menunggu Phase 8 backend |

Pekerjaan yang endpoint-nya sudah ada tetapi belum dipakai layar:
`leaveResubmit`, `taskStart`, `taskAttachment`, `hrTaskCancel`, `hrTaskOptions`,
`hrEmployeeDetail`, `hrRevokeInvitation`, `getFaceEnrollment`.

Pekerjaan yang menunggu backend: lampiran pengajuan, riwayat keputusan HR,
keputusan koreksi presensi, notifikasi "tandai belum dibaca", push, gaji, dan
dashboard HR.
