# 📝 Catatan Pembaruan & Fitur Baru: Hopr

Dokumen ini mendokumentasikan serangkaian pembaruan, peningkatan, dan perbaikan bug terbaru yang diimplementasikan pada **Hopr**. Pembaruan ini meningkatkan stabilitas interaksi, pengalaman visual, dan fleksibilitas kontrol keyboard.

---

## 🚀 Ringkasan Pembaruan

Berikut adalah lima pembaruan utama yang telah ditambahkan ke dalam codebase:

1. **Sembunyikan Petunjuk Sementara (Temporary Hint Hide)** via *Double-Tap Shift*.
2. **Peralihan Mode Langsung & Toggle Pintasan** dari mode aktif mana pun.
3. **Simulasi Hover Mouse yang Akurat** dengan pergeseran 1-piksel (*1-pixel transition delta*).
4. **Peningkatan Deduplikasi Elemen Tumpang Tindih** berbasis jarak titik pusat.
5. **Animasi Transisi Memudar (Fade Animation)** untuk overlay petunjuk.

---

## 🔍 Detail Implementasi Teknis

### 1. Sembunyikan Petunjuk Sementara (Temporary Hint Hide)
*   **Tujuan**: Memungkinkan pengguna menyembunyikan balon petunjuk (*hints*) secara sementara untuk melihat teks atau elemen di bawahnya, tanpa harus keluar dari **Hint Mode**.
*   **Mekanisme**:
    *   `HotkeyManager` mendengarkan event tipe `.flagsChanged` untuk mendeteksi penekanan tombol `Shift` (Left Shift `56` atau Right Shift `60`).
    *   Jika pengguna melakukan ketukan ganda (*double-tap*) pada tombol `Shift` dengan selang waktu kurang dari **500ms** (`0.5 detik`), sistem akan memicu status `isTemporarilyDisabled` pada `HintMode`.
    *   Selama status ini aktif:
        *   Jendela overlay petunjuk disembunyikan menggunakan efek transisi memudar.
        *   Pencegatan input keyboard dihentikan sementara (`handleKeyPress` mengembalikan `false`), sehingga tombol yang ditekan dikirimkan langsung ke aplikasi target.
        *   Indikator mode HUD (`ModeIndicator`) disembunyikan agar layar bersih.
    *   Ketukan ganda tombol `Shift` berikutnya akan memulihkan tampilan petunjuk dan kembali mengaktifkan pencegatan tombol.
    *   Setiap penekanan tombol akselerator petunjuk (seperti mengetik kombinasi huruf label) akan mereset riwayat ketukan ganda `Shift` untuk mencegah aktivasi yang tidak disengaja.

---

### 2. Peralihan Mode Langsung & Toggle Pintasan (Direct Mode Switch & Toggle)
*   **Tujuan**: Membuka fleksibilitas bagi pengguna untuk langsung berpindah mode atau menonaktifkan mode yang sedang berjalan tanpa harus kembali ke status `.idle` secara manual.
*   **Mekanisme**:
    *   Pencegatan pintasan global (`Cmd+Shift+Space`, `Cmd+Shift+J`, `Cmd+Shift+M`, `Cmd+Shift+/`) kini diproses secara global di luar kondisi mode `.idle`.
    *   **Perilaku Toggle**: Jika pintasan yang ditekan sesuai dengan mode yang sedang aktif (misalnya menekan `Cmd+Shift+Space` saat sedang berada di *Hint Mode*), sistem akan langsung menonaktifkan mode tersebut (kembali ke `.idle`).
    *   **Perilaku Peralihan Langsung**: Jika pintasan yang ditekan berbeda dengan mode aktif (misalnya menekan `Cmd+Shift+J` saat berada di *Hint Mode*), sistem akan menonaktifkan mode aktif secara bersih dan langsung mengaktifkan mode baru yang diminta (*Scroll Mode*).

---

### 3. Simulasi Hover Mouse yang Akurat (Mouse Hover Transition Fix)
*   **Tujuan**: Memperbaiki masalah pada beberapa aplikasi (terutama browser berbasis Chromium/Safari dan elemen web) yang tidak merespons perubahan status hover (`:hover` di CSS atau `mouseover`/`mouseenter` di JavaScript) saat kursor dipindahkan secara instan menggunakan warping koordinat.
*   **Mekanisme**:
    *   Pada `UIElement.swift` di dalam fungsi `moveCursorTo()`, kursor tidak lagi dipindahkan ke koordinat tujuan dalam satu event tunggal.
    *   Sistem sekarang membagi pemindahan menjadi 4 tahap:
        1. Memindahkan kursor fisik ke koordinat target (`centerPoint`) menggunakan `CGWarpMouseCursorPosition`.
        2. Mengirimkan event `mouseMoved` dengan koordinat ter-offset 1 piksel ke kiri (`x - 1, y`).
        3. Menjeda jalannya utas selama **10ms** (`Thread.sleep(forTimeInterval: 0.01)`) untuk memberi waktu bagi sistem operasi memproses event pertama.
        4. Mengirimkan event `mouseMoved` kedua tepat di koordinat target asli.
    *   Transisi sejauh 1 piksel ini disimulasikan sebagai pergerakan fisik nyata oleh macOS, sehingga memicu event hover pada elemen web/GUI target.

---

### 4. Deduplikasi Elemen Tumpang Tindih yang Lebih Cerdas (Euclidean Center-point Check)
*   **Tujuan**: Mencegah terbuangnya elemen UI kecil yang berada di dalam atau sangat dekat dengan elemen penampung besar (misalnya tombol "Menu" kecil di dalam kartu link besar) karena aturan tumpang tindih area.
*   **Mekanisme**:
    *   Sebelumnya, jika dua elemen bertabrakan dengan rasio luas area interseksi lebih dari `40%`, salah satunya akan dibuang karena dianggap duplikat.
    *   Di dalam `AccessibilityService.swift`, logika ini diperluas dengan menambahkan perhitungan **jarak Euclidean** antara titik pusat (`centerPoint`) kedua elemen:
        $$\text{Jarak} = \sqrt{(x_2 - x_1)^2 + (y_2 - y_1)^2}$$
    *   Jika jarak antara kedua titik pusat lebih dari **8.0 piksel**, sistem menganggap kedua elemen tersebut adalah kontrol fungsional yang berbeda (bukan representasi duplikat), sehingga keduanya tetap dipertahankan dan diberi label petunjuk secara terpisah.

---

### 5. Animasi Transisi Memudar (Fade-in / Fade-out Overlay Animation)
*   **Tujuan**: Memberikan efek visual yang premium dan mulus saat menampilkan atau menyembunyikan overlay petunjuk.
*   **Mekanisme**:
    *   Metode baru `setOverlayVisible(_:)` ditambahkan pada `OverlayWindowController`.
    *   **Animasi Tampil (Fade-In)**: Mengubah `alphaValue` jendela menjadi `0.0`, menampilkan jendela di depan (`orderFront`), lalu menggunakan `NSAnimationContext.runAnimationGroup` untuk mengomposisikan animasi perubahan `alphaValue` ke `1.0` dengan durasi **0.12 detik** dan kurva akselerasi `.easeOut`.
    *   **Animasi Sembunyi (Fade-Out)**: Mengubah `alphaValue` jendela dari `1.0` ke `0.0` dengan durasi **0.10 detik** dan kurva akselerasi `.easeIn`. Setelah durasi selesai, jendela dikeluarkan dari daftar rendering (`orderOut`).

---

### 6. Perbaikan Koordinat Multi-Monitor (Multi-Monitor Coordinate Fix)
*   **Tujuan**: Memastikan balon petunjuk (*hint labels*) dan kotak sorot (*highlight boxes*) digambar tepat di atas elemen UI yang sesungguhnya di monitor mana pun pada sistem multi-monitor.
*   **Mekanisme**:
    *   Mengganti kalkulasi pembalikan sumbu-$y$ Cocoa asinkron dari menggunakan tinggi monitor lokal (`screen.frame.height`) menjadi tinggi layar utama (`NSScreen.screens.first?.frame.height`), yang berfungsi sebagai basis pembalikan global di seluruh monitor.
    *   Mengubah pembuatan jendela overlay transparan (`NSPanel`) di `OverlayWindowController` agar membentang di seluruh area gabungan semua monitor (`unionFrame`), mencegah pemotongan (*clipping*) visual pada monitor sekunder.
    *   Menyesuaikan `determinePosition` dan `resolveOverlap` agar menggunakan dimensi layar lokal elemen terkait, memastikan pergeseran tabrakan label tetap terikat pada batas fisik monitor masing-masing.

---

## 📁 Pemetaan Berkas yang Diubah

| Jalur Berkas | Deskripsi Modifikasi |
| :--- | :--- |
| [`Sources/Hopr/App/AppDelegate.swift`](file:///Users/macbook/Documents/Project/clone_hopr/Sources/Hopr/App/AppDelegate.swift) | Menghubungkan callback pemantauan Shift dan visibility change dari `HintMode` untuk menampilkan/menyembunyikan HUD `ModeIndicator`. |
| [`Sources/Hopr/Core/AccessibilityService.swift`](file:///Users/macbook/Documents/Project/clone_hopr/Sources/Hopr/Core/AccessibilityService.swift) | Menambahkan pengecualian jarak titik pusat (> 8px) pada fungsi `deduplicateOverlapping` untuk menjaga elemen tumpang tindih yang valid, serta menggunakan basis tinggi layar utama untuk koordinat area scroll. |
| [`Sources/Hopr/Core/ScrollableArea.swift`](file:///Users/macbook/Documents/Project/clone_hopr/Sources/Hopr/Core/ScrollableArea.swift) | Menggunakan tinggi layar utama untuk kalkulasi pembalikan koordinat global. |
| [`Sources/Hopr/Core/UIElement.swift`](file:///Users/macbook/Documents/Project/clone_hopr/Sources/Hopr/Core/UIElement.swift) | Memperbaiki simulasi pemindahan kursor (`moveCursorTo`) menggunakan offset 1-piksel dan jeda 10ms untuk memicu hover state secara andal. |
| [`Sources/Hopr/Input/HotkeyManager.swift`](file:///Users/macbook/Documents/Project/clone_hopr/Sources/Hopr/Input/HotkeyManager.swift) | Menambahkan penanganan event `.flagsChanged` untuk mendeteksi penekanan tombol Shift serta memperbarui pintasan global agar dapat di-toggle/di-switch secara langsung. |
| [`Sources/Hopr/Modes/HintMode.swift`](file:///Users/macbook/Documents/Project/clone_hopr/Sources/Hopr/Modes/HintMode.swift) | Menerapkan logika *double-tap Shift* untuk menyembunyikan/menampilkan petunjuk sementara (`isTemporarilyDisabled`) dan menangguhkan pencegatan tombol. |
| [`Sources/Hopr/Modes/ModeController.swift`](file:///Users/macbook/Documents/Project/clone_hopr/Sources/Hopr/Modes/ModeController.swift) | Menyediakan delegasi penanganan event penekanan Shift (`handleShiftKeyChanged`) ke mode aktif, serta mengaktifkan penonaktifan otomatis mode aktif sebelum memulai mode baru. |
| [`Sources/Hopr/Overlay/OverlayWindowController.swift`](file:///Users/macbook/Documents/Project/clone_hopr/Sources/Hopr/Overlay/OverlayWindowController.swift) | Menambahkan fungsi `setOverlayVisible` dengan animasi, memperluas jendela overlay ke seluruh gabungan layar monitor, dan mengoreksi pembalikan koordinat multi-monitor dengan tinggi monitor utama. |
