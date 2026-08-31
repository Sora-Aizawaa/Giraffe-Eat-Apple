# Jerapah Lapar Apel — Panduan

Game Flutter: jerapah menjulurkan lidah untuk memakan apel yang cepat
tumbuh di pohon, atau langsung menyentuhnya dengan kepala (drag mouse
/mousepad). Apel **merah/segar** menambah skor & sedikit nyawa. Apel
**busuk** (coklat, ada bintik) mengurangi nyawa. Jerapah makin
**gendut** seiring banyak apel segar yang dimakan, ada musik latar
ceria, teks reaksi ("Yummy!", "Yuck!", dst), dan cerita mini tentang
si jerapah (Georgie) yang terbuka setiap mencapai skor tertentu.
Menang kalau seluruh "kolam suplai" apel (32 buah) sudah tumbuh dan
habis dimakan sebelum nyawa habis.

> **Catatan jujur:** saya menulis kode ini tanpa Flutter SDK terpasang
> di sandbox saya (tidak ada akses ke pub.dev/flutter storage di sini),
> jadi saya **belum bisa `flutter run` untuk verifikasi otomatis**.
> Saya sudah teliti soal sintaks Dart & API Flutter yang dipakai, tapi
> tolong jalankan di komputer Leo dan kabari kalau ada error — saya
> bantu perbaiki cepat.

## 1. Penempatan file

| File yang saya buat | Taruh di mana |
|---|---|
| `pubspec.yaml` | Root project baru, mis. `C:\laragon\www\jerapah_lapar_apel\pubspec.yaml` |
| `lib/main.dart` | `...\jerapah_lapar_apel\lib\main.dart` |
| `assets/audio/bg_music.wav` | `...\jerapah_lapar_apel\assets\audio\bg_music.wav` (buat folder `assets\audio` kalau belum ada) |

**Penting soal `pubspec.yaml`**: saya menambahkan dependency baru
(`audioplayers`) dan bagian `assets:`. Kalau Leo cuma menimpa
`lib/main.dart` saja dan tetap pakai `pubspec.yaml` versi lama, game
akan error karena package `audioplayers` tidak ditemukan. Pastikan
`pubspec.yaml` juga ditimpa dengan yang baru dari zip ini, lalu
jalankan `flutter pub get` sebelum `flutter run`.

## 1b. Tentang musik latar

File `assets/audio/bg_music.wav` itu **komposisi asli** yang saya
susun sendiri lewat sintesis gelombang (kode Python, bukan rekaman
atau transkripsi dari lagu berhak cipta). Gayanya terinspirasi musik
game farming/village yang ceria (semacam suasana Harvest Moon), tapi
melodinya bukan lagu Harvest Moon yang asli — supaya aman dipakai
bebas tanpa masalah hak cipta. Kalau nanti Leo mau ganti dengan musik
lain (mis. beli dari situs royalty-free atau bikin sendiri), tinggal
timpa file `bg_music.wav` itu (format WAV, mono/stereo, 44.1kHz) tanpa
perlu ubah kode sama sekali.

Karena ini project Flutter baru (bukan tambahan ke kredit-app), paling
gampang: buat project kosong dulu pakai `flutter create`, lalu timpa
`pubspec.yaml` dan `lib/main.dart` dengan punya saya.

## 2. Cara menjalankan (CMD Windows)

```cmd
cd C:\laragon\www
flutter create jerapah_lapar_apel
cd jerapah_lapar_apel
```

Setelah itu, timpa isi `pubspec.yaml` dan `lib\main.dart` dengan file
dari zip ini (replace, bukan digabung manual). Lalu:

```cmd
flutter pub get
flutter devices
flutter run
```

Kalau muncul device Chrome, `flutter run -d chrome` juga jalan (game
ini murni Dart/Flutter, tidak pakai plugin native apa pun).

## 3. Kalau ada error saat run

Kirim saja pesan error lengkapnya ke saya — kemungkinan besar cuma
soal versi Flutter SDK Leo (misalnya Flutter versi lama yang belum
support beberapa API `Curves`/`AnimatedContainer`). File ini menyasar
Flutter dengan Dart SDK `>=3.0.0`.

## 4. Kenapa tidak ada file gambar (aset) sama sekali?

Semua "aset" (jerapah, apel, pohon, langit) digambar langsung lewat
kode pakai `CustomPainter` — semacam menggambar vektor manual di atas
`Canvas`. Ini pilihan arsitektur yang saya ambil, bukan keterbatasan:

- **Tidak perlu urus folder `assets/`, `pubspec.yaml` assets section,
  atau file `.png` yang gampang ke-skip pas dikirim.** Zip ini langsung
  jalan begitu ditempel.
- Animasi (lidah menjulur, badan gendut) jadi lebih presisi karena
  bentuknya memang parametrik (lebar badan, panjang lidah, dsb tinggal
  dikalikan angka 0..1 dari `AnimationController`), bukan swap gambar.
- Trade-off: tampilannya bergaya kartun sederhana (mirip ilustrasi
  vektor), bukan sprite/pixel art detail. Kalau nanti Leo mau ganti ke
  gambar PNG/sprite sheet asli, strukturnya gampang diubah — tinggal
  ganti isi method `paint()` di masing-masing `*Painter` dengan
  `canvas.drawImage(...)`, atau ganti widget `CustomPaint` apel/jerapah
  jadi `Image.asset(...)`.

## 5. Peta arsitektur (buat belajar)

Semua di satu file `lib/main.dart` supaya gampang ditempel & dibaca
runtut (untuk project besar biasanya dipecah per-file, tapi untuk
single-screen game ini saya sengaja gabung dulu):

| Bagian | Peran | Analoginya di Next.js (kredit-app) |
|---|---|---|
| `GamePage` (`StatefulWidget`) | "Otak" game — state score/health/slots apel, timer spawn, logika makan | Mirip komponen client `"use client"` yang pegang `useState`/`useEffect` |
| `AnimationController` (`_tongueCtrl`, dll) | Mesin animasi berbasis waktu, di-drive lewat `TickerProviderStateMixin` | Kurang lebih peran library animasi (mis. Framer Motion) di React |
| `_ScenePainter`, `_ApplePainter`, `_GiraffePainter` (`CustomPainter`) | Layer "rendering" murni — cuma tahu cara menggambar berdasarkan angka yang dikasih, tidak menyimpan state sendiri | Mirip komponen presentational / SVG murni yang menerima props |
| `Timer.periodic` (`_spawnTimer`) | Job berkala yang menumbuhkan apel baru ke slot kosong | Mirip `setInterval` di frontend, atau job cron kecil |
| `AppleData` | Model data 1 apel (jenis, status dimakan) | Mirip 1 row/record di state, bukan di database |
| `Ticker` (`_followTicker`, via `createTicker`) | Loop per-frame terpisah dari `AnimationController` biasa — dipakai supaya kepala jerapah bisa "mengejar" posisi drag mouse/mousepad secara halus (interpolasi berbasis waktu), bukan cuma animasi 0→1 sekali jalan | Mirip `requestAnimationFrame` loop manual di web, dipakai untuk physics/following ringan |

### Fitur baru: kepala jerapah mengikuti drag mouse/mousepad

- `GestureDetector` membungkus seluruh layar dengan `onPanUpdate` /
  `onPanEnd`. Saat pemain klik-tahan-geser (atau geser jari), posisi
  target (`_headDragTarget`) berubah, dibatasi radius maksimum supaya
  kepala tidak "copot" dari badan (radius dihitung proporsional dari
  ukuran layar, `_canvasSize.shortestSide * 0.16`).
- `_followTicker` jalan tiap frame, menghitung `_headDragCurrent` yang
  perlahan mengejar `_headDragTarget` pakai `Offset.lerp` — ini yang
  bikin gerakannya terasa halus/kenyal, bukan loncat kaku ikut posisi
  mouse persis.
- Saat drag dilepas (`onPanEnd`), target dikembalikan ke `Offset.zero`
  sehingga kepala "pegas" balik ke posisi semula secara halus juga
  (karena tetap lewat ticker yang sama).
- `_GiraffePainter` menerima `headOffset` ini dan menambahkannya ke
  posisi mulut dasar (`kMouthFraction`), jadi seluruh leher, kepala,
  dan titik pangkal lidah otomatis mengikuti tanpa perlu logika
  tambahan di tempat lain — cukup satu titik `mouth` yang berubah,
  kurva leher (`quadraticBezierTo`) menyesuaikan sendiri.
- Tap apel tetap berfungsi normal karena `GestureDetector` drag
  bersifat `translucent`: gesture tap pada apel (yang punya
  `GestureDetector` sendiri, lebih spesifik) tetap menang lewat
  mekanisme "gesture arena" Flutter selama gerakannya minim (tap
  murni), sementara gesekan/drag ditangkap oleh detector layar penuh.

### Alur "makan apel" (`_eatApple`)

1. Tap apel → cek tidak sedang sibuk (`giraffeBusy`) & apel belum
   ditarget → tandai `targeted = true` supaya tidak bisa di-tap dobel.
2. `_tongueCtrl.forward()` → lidah menjulur dari mulut ke posisi apel
   (di-interpolasi tiap frame lewat `Offset.lerp`).
3. Setelah lidah sampai: apel ditandai `consumed = true` (memicu
   animasi mengecil di widget apel lewat `TweenAnimationBuilder`), lalu
   skor/nyawa diupdate sesuai jenis apel.
4. `_fatnessCtrl.animateTo(...)` menaikkan level "gendut" jerapah
   secara halus berdasarkan proporsi apel segar yang sudah dimakan.
5. `_swallowCtrl` jalan bersamaan (gumpalan bergerak dari mulut ke
   badan menyusuri kurva leher) sambil lidah ditarik balik.
6. Slot apel dikosongkan lagi → `_checkGameEnd()` cek kondisi
   menang/kalah.

### Kondisi menang/kalah

- **Kalah**: `health <= 0` (apel busuk mengurangi 20 nyawa per gigitan).
- **Menang**: `applePoolRemaining == 0` DAN semua slot pohon kosong —
  artinya seluruh 32 apel di "kolam suplai" sudah tumbuh & habis
  dimakan.

### Fitur baru: musik latar & cerita reward

- **Musik**: pakai package `audioplayers`. Musik baru mulai diputar
  setelah gestur pertama dari pemain (`onPanDown` di `GestureDetector`
  layar-penuh memanggil `_ensureMusicStarted()`), bukan langsung di
  `initState`. Ini penting karena browser (Chrome/Edge) memblokir
  autoplay audio sebelum ada interaksi pengguna — kalau langsung
  diputar di `initState`, kemungkinan besar musiknya diam saja pas
  dijalankan di web. Ada tombol speaker kecil di HUD untuk mute/unmute
  (`_toggleMute`).
- **Cerita reward**: daftar `kStoryMilestones` berisi ambang skor
  (30/70/120/170/220) beserta judul & narasi singkat tentang jerapah
  bernama "Georgie". Tiap kali skor melewati satu ambang yang belum
  pernah ditampilkan (`_shownMilestones`), `_checkStoryMilestones()`
  menjeda spawn apel sebentar dan menampilkan kartu cerita
  (`_buildStoryOverlay`). Pemain tekan "Continue" (`_dismissStory`)
  untuk lanjut main lagi.

## 6. Tes manual yang saya sarankan

1. `flutter pub get` dulu (wajib, karena ada dependency baru
   `audioplayers`), baru `flutter run` → pastikan langit, tanah,
   pohon, dan jerapah kurus muncul tanpa error merah di layar (red
   screen of death).
2. Tunggu ±1 detik → apel mulai tumbuh satu-satu di kanopi pohon,
   sedikit bergoyang.
3. **Klik-tahan lalu geser mouse (atau geser jari di mousepad/layar
   sentuh) di mana saja pada layar** → kepala & leher jerapah harus
   ikut bergerak halus ke arah geseran itu, dibatasi radius tertentu
   supaya kepalanya tidak lepas dari badan. Lepas klik/geseran → kepala
   pelan-pelan "pegas" balik ke posisi semula. Musik latar juga harus
   mulai terdengar begitu drag pertama dilakukan.
4. Tap satu apel merah (atau tempelkan kepala jerapah langsung ke
   apelnya lewat drag) → lidah menjulur dari posisi kepala saat itu ke
   apel itu, apel mengecil/hilang, teks "Yummy!"/dst muncul melayang,
   skor naik +10, nyawa naik dikit (maks 100).
5. Tap tombol speaker di HUD → musik harus mute/unmute.
6. Tap satu apel coklat/busuk (kalau muncul) → nyawa berkurang 20,
   teks "Yuck!"/dst muncul; coba sampai nyawa 0 → overlay "Jerapah
   Kelaparan..." muncul dengan tombol **Main Lagi**.
7. Restart, lalu kumpulkan skor sampai 30 → kartu cerita "A New
   Friend" tentang Georgie harus muncul, spawn apel berhenti sebentar,
   tekan "Continue" untuk lanjut. Ulangi sampai skor 220 untuk lihat
   semua 5 cerita.
8. Fokus makan banyak apel segar → badan jerapah harus terlihat makin
   lebar/gendut secara bertahap.
9. Biarkan main sampai "Akan tumbuh: 0" dan pohon kosong → overlay
   "Semua Apel Habis! Menang!" harus muncul.

## 7. Ide pengembangan lanjutan (kalau mau)

- Ganti gambar vektor jadi sprite PNG asli (lihat poin 4).
- Tambah efek suara (paket `audioplayers`) saat menggigit apel.
- Tambah level kesulitan (interval spawn makin cepat seiring skor).
- Simpan skor tertinggi pakai `shared_preferences`.
