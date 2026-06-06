# Hopr 🎹🖱️

**Hopr** adalah aplikasi utilitas macOS yang dirancang untuk mempercepat alur kerja dengan memungkinkan kontrol keyboard penuh atas antarmuka pengguna grafis (GUI) tanpa menyentuh mouse. Terinspirasi oleh aplikasi *Hopr*, proyek ini menggunakan **Accessibility API (ApplicationServices)** dan **CoreGraphics Event Taps** untuk berinteraksi dengan elemen UI di layar secara instan.

Aplikasi ini berjalan sebagai aplikasi latar belakang tanpa ikon Dock (tipe `.accessory`) dengan ikon menu bar yang elegan, dan siap digunakan kapan saja melalui pintasan keyboard global.

---

## 🚀 Fitur Utama

Aplikasi ini menyediakan 3 mode utama yang dioptimalkan untuk efisiensi pengetikan:

1. **Hint Mode (`Cmd+Shift+Space`)**
   - Menampilkan label teks (*hint*) di atas seluruh elemen UI yang dapat diklik (tombol, tautan, bidang teks, dll.).
   - Mengetik urutan huruf label langsung melakukan simulasi klik kiri atau memfokuskan elemen secara instan.
   - Dilengkapi *smart delay* 400ms jika terdapat label yang tumpang tindih secara prefiks (misal `A` vs `AB`), memungkinkan pengetikan huruf berikutnya sebelum aksi otomatis dijalankan.

2. **Scroll Mode (`Cmd+Shift+J`)**
   - Mendeteksi seluruh area yang dapat di-scroll di jendela aktif (termasuk editor teks, halaman web, atau terminal).
   - Pengguna memilih area target menggunakan angka `1-9`, kemudian melakukan scrolling menggunakan tombol navigasi Vim:
     - `J` : Scroll ke bawah
     - `K` : Scroll ke atas
     - `H` : Scroll ke kiri
     - `L` : Scroll ke kanan
   - Tahan tombol `Shift` untuk kecepatan scroll turbo (*Dash Speed*).

3. **Search Mode (`Cmd+Shift+/`)**
   - Membuka panel pencarian HUD transparan berbasis `NSVisualEffectView` di tengah layar dengan animasi masuk/keluar yang halus.
   - Pencarian elemen UI secara real-time berdasarkan judul (*title*) atau tipe/peran aksesibilitas (*role*).
   - Menampilkan dropdown hasil pencarian (maksimal 6 elemen teratas) menggunakan komponen baris kustom `SearchResultRowView` dengan indikator badge label huruf.
   - Navigasi hasil pencarian dengan tombol arah `Up` / `Down` untuk memindahkan fokus.
   - Kotak sorotan premium (`HighlightBoxView`) berpindah secara dinamis di layar untuk menandai elemen UI yang sedang dipilih di latar belakang.
   - Menekan `Enter` akan mengonfirmasi pilihan, menutup panel secara instan, dan mensimulasikan klik pada elemen yang disorot.

4. **HUD Mode Indicator & Menu Bar**
   - Indikator visual melayang di bagian atas layar menunjukkan mode aktif saat ini menggunakan visualisasi efek kaca (*vibrancy*).
   - Menu bar menyediakan akses cepat untuk mengaktifkan mode, membuka preferensi, atau menutup aplikasi.

5. **Audio & Sound Feedback**
   - Integrasi efek suara taktil instan ketika berpindah mode (memainkan `click7.m4a`) dan mengeksekusi klik atau aktivasi elemen (memainkan `click1.m4a`).
   - Pustaka audio menggunakan `NSSound` dengan mekanisme resolusi path yang fleksibel (lokal maupun absolut).

---

## 🛠️ Persyaratan Sistem

- **Sistem Operasi**: macOS 13.0 (Ventura) atau versi yang lebih baru.
- **Izin Akses (Permissions)**: Aplikasi memerlukan izin **Accessibility (Aksesibilitas)** untuk membaca hierarki UI dan mengirimkan input klik. Aplikasi akan otomatis meminta izin ini saat pertama kali dijalankan.

---

## ⚙️ Cara Menjalankan & Membangun Proyek

Proyek ini dibangun menggunakan **Swift Package Manager (SPM)** dengan arsitektur modular yang rapi.

### Menjalankan secara Lokal
Untuk menjalankan aplikasi dalam mode pengembangan langsung dari terminal:
```bash
swift run
```

### Membangun Rilis Produksi
Untuk mengompilasi biner rilis teroptimasi:
```bash
swift build -c release
```
Biner hasil kompilasi akan berada di direktori `.build/release/Hopr`.

---

## 🪵 Debugging Hierarki UI (AX Tree)

Tersedia skrip pembantu untuk membaca struktur *Accessibility Tree* dari aplikasi yang sedang berjalan (seperti VSCode):
```bash
swift debug_ax.swift
```
Skrip ini mempermudah proses analisis dan debugging elemen UI mana saja yang dapat dideteksi oleh aplikasi.

---

## 📁 Struktur Kode Sumber

```
.
├── Resources/                     # Aset suara (click1.m4a, click7.m4a, dll.)
└── Sources/Hopr/
    ├── App/
    │   ├── main.swift                 # Entry point aplikasi & konfigurasi tipe .accessory
    │   └── AppDelegate.swift          # Pengelolaan lifecycle, status bar menu, & koordinasi mode
    ├── Core/
    │   ├── AccessibilityService.swift # Pemindaian pohon aksesibilitas, filtering, & caching
    │   ├── UIElement.swift            # Wrapper AXUIElement & penanganan aksi klik (simulasi & native)
    │   ├── ScrollableArea.swift       # Representasi area scrollable
    │   └── Permissions.swift          # Utilitas pemeriksaan izin Aksesibilitas macOS
    ├── Input/
    │   ├── HotkeyManager.swift        # Intersepsi input keyboard global melalui Event Taps
    │   └── KeyMapper.swift            # Penghasil label huruf dinamis (A-Z, AA-ZZ)
    ├── Modes/
    │   ├── ModeController.swift       # State machine pengelola mode aktif (.idle, .hint, .scroll, .search)
    │   ├── HintMode.swift             # Logika pencocokan input string label & eksekusi klik
    │   ├── ScrollMode.swift           # Mekanisme navigasi scroll & timer perulangan scroll
    │   └── SearchMode.swift           # Pencarian elemen UI berbasis teks & HUD pencarian
    ├── Models/
    │   └── AppSettings.swift          # Model preferensi pengguna berbasis @AppStorage
    ├── Overlay/
    │   ├── OverlayWindowController.swift # Manajer rendering jendela overlay di atas semua aplikasi
    │   ├── LabelView.swift            # Gambar balon label penunjuk elemen UI (tema kuning premium)
    │   ├── ScrollAreaBoxView.swift    # Border visual dan badge nomor untuk area scroll
    │   └── ModeIndicator.swift        # Pill HUD penanda status mode aktif dengan visual efek kaca
    └── Utils/
        ├── Logger.swift               # Utilitas pencatatan log
        ├── Notifications.swift        # Hub observasi notifikasi antar mode
        └── SoundManager.swift         # Pengelola audio/umpan balik efek suara asinkron
```

---

## 📄 Dokumentasi Tambahan

Untuk analisis sistem yang mendalam mengenai alur kerja, pengoptimalan kinerja, dan detail implementasi teknis, silakan merujuk pada dokumen:
*   [ARCHITECTURAL_DOCUMENTATION.md](file:///Users/macbook/Documents/Project/clone_hopr/ARCHITECTURAL_DOCUMENTATION.md)

---

## 📜 Lisensi

Hak Cipta © 2026. Dikembangkan untuk efisiensi kontrol macOS menggunakan keyboard.
