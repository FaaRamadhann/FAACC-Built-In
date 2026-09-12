# FAACC Standalone — Faa Agresive App Cache Cleaner (Build-in)

Versi **mandiri** dari [FAACC](https://github.com/FaaRamadhann/FAACC) — cleaner **built-in di dalam APK**, tanpa module Magisk, tanpa CLI eksternal. Install langsung jalan (butuh root untuk scan & clean).

## Fitur

- **Cleaner built-in** — engine `assets/engine.sh` dieksekusi via root langsung dari aplikasi, ala SD Maid
- **Agresif** — cache internal + `code_cache` + cache eksternal (`/sdcard/Android/data`), tanpa `pm clear`, tanpa hapus data
- **Dashboard + daftar aplikasi** — search, Select All, sort (cache/nama), filter (All/User/System), detail per aplikasi
- **Cleaning progress** — konfirmasi, progres per aplikasi, hasil (`A → B`, cleared, apps processed)
- **Settings** — tema (System/Light/Dark), Dynamic Color, include system apps, auto scan
- **Build tanpa Gradle / Android Studio** — cukup JDK + SDK build-tools (`build.bat` / `build.py`)

## Syarat

- **Android:** 7.0+ (API 24+)
- **Root** — untuk scan & clean. Tanpa root: cuma daftar aplikasi yang tampil

> Tidak butuh module FAACC / Magisk tertentu — cukup root (Magisk, KernelSU, APatch, dsb).

## Install

Download `FAACC.apk` dari repo ini, install langsung di HP:

```
adb install -r FAACC.apk
```

> Paket `com.faa.faaccapp`, key sendiri — aplikasi terpisah dari manager versi module (`com.faa.faacc`), bisa koeksis.

## Build sendiri (tanpa Gradle)

```
cd Fork-FAACC
build.bat        # Windows, atau:
python build.py  # butuh Python 3.8+
```

Hasil: `build/FAACC.apk` (paket `com.faa.faaccapp`, sudah zipalign + signed). Butuh: JDK 17+ (`javac`, `keytool`) + Android SDK build-tools + 1 platform (`aapt`, `d8`, `zipalign`, `apksigner`) — lihat blok `KONFIG` di script.

> **Backup `debug.keystore`!** Update APK wajib pakai key yang sama.

## Struktur

```
Fork-FAACC/
├── FAACC.apk                 # APK siap install (com.faa.faaccapp)
├── AndroidManifest.xml
├── build.bat / build.py      # Build tanpa Gradle
├── com.faa.faaccapp.jpg      # Source icon
├── assets/engine.sh          # Engine cleaner (scan + clean agresif)
├── src/com/faa/faaccapp/
│   ├── MainActivity.java     # UI (Home / Apps / Settings)
│   ├── FaaccEngine.java      # Bridge: extract asset + exec via root
│   └── RootShell.java        # Eksekusi su -c (anti-deadlock, timeout)
└── res/drawable/icon.png     # Icon app
```

## Cara kerja

APK menyalin `assets/engine.sh` ke filesDir lalu menjalankannya via `su -c`:

- `--scan pkg...` — daftar package dari PackageManager, ukuran per jenis via 1× `du` per package (output `pkg|total|internal|code_cache|external`)
- `--clean pkg` — hapus isi direktori tervalidasi (output `pkg|freed|rc`)

Tiap target path divalidasi pola milik package-nya (gagal = abort). Package sistem kritis (`android`, `com.android.systemui`, `com.android.phone`) dikecualikan.

## Troubleshooting

Masalah | Solusi
Angka cache strip / notice butuh root | Beri akses root ke aplikasi (Magisk/KernelSU prompt)
Scan lama | Wajar untuk ratusan app — progress tampil per 100 app, timeout per chunk 2 menit
`signatures do not match` saat update | Keystore beda — backup `debug.keystore`, update wajib key yang sama
App lemot setelah clean | Wajar untuk code_cache (recompile) — buka app sekali, normal lagi

## Lisensi

[MIT License](LICENSE) — © 2026 Faa Ramadhan

---

## ⚠️ WARNING — MODE AGRESIF

1. **Code cache ikut dihapus** — app recompile ulang saat pertama dibuka (lebih lambat & hangat, normal).
2. **Cache eksternal ikut dihapus** — game/medsos bisa download ulang data (map offline, artwork, dsb).
3. **Cleaner on-demand** (tanpa scheduler) — tidak ada auto-clean di versi standalone.
