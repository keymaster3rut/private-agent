# Patch PrivateAgent: Hot word "Hey Jarvis", pengaturan TTS, mute/unmute

## Isi patch (path sama dengan di repo)
| File | Status |
|---|---|
| `pubspec.yaml` | diubah (3 plugin baru + folder assets/models/) |
| `android/app/src/main/AndroidManifest.xml` | diubah (izin + layanan latar depan mikrofon) |
| `lib/services/voice_service.dart` | diubah (logika asli tetap, ditambah TTS options + mute) |
| `lib/services/voice_settings.dart` | BARU |
| `lib/services/wake_word_service.dart` | BARU |
| `lib/widgets/voice_settings_section.dart` | BARU (kartu "Text-to-Speech" dan "Hot word") |
| `lib/screens/home_screen.dart` | diubah (ikon mute + sambungan hot word) |
| `lib/screens/settings_screen.dart` | diubah (2 baris: impor + sisipan kartu) |
| `assets/models/README.txt` | BARU (agar folder ada) |

## Langkah 1: Unggah file ke fork GitHub-mu (dari browser HP)
Buka fork-mu. Untuk tiap folder di bawah: masuk ke folder itu, tekan
**Add file → Upload files**, pilih file dari HP, lalu **Commit changes**.
File dengan nama yang sama akan tertimpa otomatis.

1. Folder utama (root): `pubspec.yaml`
2. `android/app/src/main/`: `AndroidManifest.xml`
3. `lib/services/`: `voice_service.dart`, `voice_settings.dart`, `wake_word_service.dart`
4. `lib/screens/`: `home_screen.dart`, `settings_screen.dart`
5. `lib/widgets/`: `voice_settings_section.dart`
6. `assets/models/`: hanya file `README.txt` (3 file model diunduh otomatis saat build, lihat Langkah 2)
7. `.github/workflows/android-release.yml`: ganti isinya dengan file `android-release.yml` dari patch ini (buka file di GitHub, ketuk ikon pensil, tempel isi baru, Commit)

> Folder `assets/models/` belum ada di repo. Cara membuatnya: masuk ke folder
> `assets`, tekan **Add file → Create new file**, ketik `models/README.txt` di
> kolom nama, isi apa saja, lalu Commit. Setelah itu unggah 3 file model ke sana.

## Langkah 2: Model hot word (otomatis)
Kamu TIDAK perlu mengunduh file model sendiri. Workflow yang sudah diperbarui
mengunduh `melspectrogram.onnx`, `embedding_model.onnx`, dan
`hey_jarvis_v0.1.onnx` dari openWakeWord saat build. Kalau kamu tetap ingin
memakai file sendiri, taruh di `assets/models/` dan workflow akan melewatinya.

## Langkah 3: Build APK
1. Tab **Actions** di fork → tekan tombol hijau "I understand my workflows..." bila muncul.
2. Pilih **Android release artifacts** → **Run workflow**.
3. Tunggu centang hijau. Bila gagal (silang merah), buka run-nya, salin pesan error, kirim ke Claude.
4. Unduh dari bagian **Artifacts** → ekstrak → pasang `app-universal-release.apk`.

## Langkah 4: Memakai fiturnya
- **Mute/unmute:** ikon speaker di pojok kanan atas layar utama, atau di kartu "Text-to-Speech".
- **TTS:** Settings → kartu "Text-to-Speech" (mesin, bahasa, suara, kecepatan, nada, tombol Test voice).
- **Hot word:** Settings → kartu "Hot word" → aktifkan. Beri izin mikrofon dan notifikasi.
  Muncul notifikasi tetap dengan tombol Mute/Unmute. Ucapkan "Hey Jarvis", lalu
  ucapkan perintahmu. Atur "Detection threshold" bila terlalu sering salah picu
  (naikkan) atau sulit terdeteksi (turunkan).
- Agar tahan lama di latar belakang: matikan optimasi baterai untuk PrivateAgent
  (Setelan HP → Aplikasi → PrivateAgent → Baterai → Tanpa batasan).

## Catatan jujur
Kode ini belum pernah dikompilasi atau diuji (tidak ada Flutter di lingkungan
pembuatnya). Build pertama bisa gagal; kirim log error-nya untuk diperbaiki.
Bagian yang paling mungkin perlu penyesuaian: versi 3 plugin baru, dan perilaku
mikrofon di latar belakang pada versi Android tertentu.
