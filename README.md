# hadirmetrik

A new Flutter project.

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

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
