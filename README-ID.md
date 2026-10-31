# EvoPad — Fase 1 + Fase 2 (3-Finger Drag + 4-Finger System Gestures)

Paket proyek Xcode lengkap untuk controller trackpad iPad dan Mac Helper.

## Pemetaan gesture final

| Jari | Gesture | Fungsi di Mac |
|---|---|---|
| 1 | Gerakkan | Gerakkan pointer |
| 1 | Tap | Klik kiri |
| 1 | Tahan 0,42 detik lalu geser | Drag alternatif |
| 2 | Gerakkan | Scroll vertikal/horizontal |
| 2 | Tap | Klik kanan |
| 3 | Gerakkan ketiga jari bersama | 3-finger drag (klik kiri ditahan selama drag) |
| 4 | Swipe ke atas | Mission Control — Control + ↑ |
| 4 | Swipe ke bawah | App Exposé — Control + ↓ |
| 4 | Swipe ke kiri | Desktop sebelumnya — Control + ← |
| 4 | Swipe ke kanan | Desktop berikutnya — Control + → |

## Perubahan utama pada versi ini

### Three-finger drag
- Tiga sentuhan dikenali sebagai drag, bukan shortcut arah.
- Drag mulai saat gerakan gabungan melewati ambang kecil; tidak perlu menahan 0,42 detik.
- Mac menerima `leftMouseDown`, pergerakan pointer saat tombol kiri ditahan, lalu `leftMouseUp` ketika satu dari tiga jari diangkat.
- Jika sentuhan dibatalkan, view ditutup, atau koneksi terputus, Mac Helper melepas tombol mouse.
- Drag satu jari dengan long-press tetap tersedia sebagai alternatif.

### Four-finger system gestures
- Empat sentuhan direkam secara terpisah menggunakan identitas masing-masing `UITouch`.
- Minimal tiga dari empat jari harus bergerak melewati ambang jarak dan ke arah yang sama.
- Atas/bawah/kiri/kanan diteruskan sebagai perintah gesture ke Mac Helper.
- Mac Helper tetap menerjemahkan perintah tersebut menjadi Control + panah sesuai pemetaan di panel.
- Sentuhan kelima membatalkan gesture agar tidak salah terpicu oleh telapak tangan.

### Dua jari
- Tap dua jari tetap menjadi klik kanan.
- Gerakan dua jari tetap menjadi scroll. Sumbu horizontal dan vertikal dikirim terpisah.

## Pengaturan penting di iPad

Sistem iPadOS memiliki gesture multitasking empat/lima jari dan gesture produktivitas tiga jari sendiri. Sistem dapat mengambil alih atau membatalkan sentuhan sebelum aplikasi menerimanya.

Untuk memberi EvoPad kesempatan menangkap gesture kustom:
1. Buka Settings → Multitasking & Gestures.
2. Matikan `Four & Five Finger App Switching`.
3. Matikan `Productivity Gestures` jika swipe tiga jari masih dibatalkan oleh iPadOS.
4. Tutup dan buka ulang EvoPad.

Apple mendokumentasikan bahwa opsi tersebut mengaktifkan swipe/pinch empat atau lima jari untuk berpindah aplikasi serta gesture produktivitas tiga jari. Lihat: https://support.apple.com/guide/ipad/change-multitasking-gestures-settings-ipad-ipad2q9j404h2/ipados

## Pengaturan shortcut di Mac

Pastikan shortcut keyboard ini aktif di System Settings → Keyboard → Keyboard Shortcuts → Mission Control:
- Mission Control: Control + Up
- Application windows: Control + Down
- Move left a space: Control + Left
- Move right a space: Control + Right

Perpindahan desktop membutuhkan setidaknya dua Spaces. Tes di Mac Helper dapat digunakan tanpa melakukan swipe di iPad.

## Cara menguji

### 3-finger drag
1. Pastikan iPad terhubung ke Mac.
2. Letakkan tiga jari pada area trackpad.
3. Geser ketiga jari bersama-sama. Tidak perlu menunggu long-press.
4. Di iPad harus muncul `3-finger drag aktif`.
5. Di Mac Helper, `Input terakhir` harus menunjukkan tombol kiri ditahan.
6. Angkat satu atau semua jari. Mac Helper harus menunjukkan tombol mouse dilepas.

### 4-finger swipe
1. Pastikan pengaturan multitasking gesture iPadOS di atas sudah disesuaikan.
2. Letakkan empat jari pada area trackpad.
3. Geser ke atas, bawah, kiri, atau kanan secara bersamaan sekitar 1–2 cm.
4. Angkat jari.
5. iPad harus menampilkan arah swipe empat jari yang terdeteksi.
6. Mac Helper harus menampilkan arah shortcut yang dikirim.
7. Pastikan macOS menjalankan Mission Control, App Exposé, atau berpindah Spaces.

## Instalasi
Paket ini adalah proyek lengkap, bukan patch folder parsial.
1. Tutup Xcode.
2. Backup folder EvoPad lama.
3. Ekstrak folder `EvoPad` dari ZIP ini ke lokasi proyek.
4. Buka `EvoPad.xcodeproj`.
5. Build dan jalankan scheme `EvoPad Mac`.
6. Build dan jalankan scheme `EvoPad iPad` pada iPad Air 5.
7. Pertahankan Apple Development Team / Signing yang sesuai di Xcode.
8. Setelah mengganti source, lakukan Product → Clean Build Folder bila diperlukan.

## Verifikasi yang dilakukan
- Sintaks seluruh file Swift diperiksa menggunakan Swift frontend parser.
- Struktur `project.pbxproj` dan kedua file `Info.plist` diperiksa.
- Referensi file proyek harus mengarah ke file fisik yang tersedia.
- Build Xcode dan pengujian runtime tetap harus dilakukan pada Mac dan iPad fisik.

## Keamanan
Transport masih TCP lokal tanpa TLS maupun autentikasi pairing. Gunakan hanya di jaringan lokal tepercaya. Jangan port-forward TCP 49321 ke internet.


## Optimasi input 60 Hz (versi perbaikan)

- Pointer dan scroll dikumpulkan lalu dikirim maksimum sekali per frame melalui `CADisplayLink` dengan target 60 Hz.
- Sentuhan terbaru menggunakan `UIEvent.coalescedTouches(for:)` agar posisi yang diterima lebih akurat.
- TCP `noDelay` diaktifkan untuk mengurangi latensi paket pointer kecil.
- Mac Helper memproses parsing perintah dan `CGEvent` pada serial queue berprioritas `userInteractive`, terpisah dari UI.
- Empat jari dikenali lebih awal begitu tiga dari empat jari melewati ambang gerak yang searah. Jika UIKit membatalkan touch sequence, posisi terakhir tetap dievaluasi sebelum gesture dianggap gagal.

### Jika gesture empat jari tetap dibatalkan

Pada iPad, buka **Settings → Multitasking & Gestures** dan matikan **Four & Five Finger App Switching**. Fitur sistem tersebut memakai kombinasi empat/lima jari yang sama dan dapat mengambil alih touch sequence aplikasi.

Catatan performa: target pengiriman adalah 60 Hz pada iPad Air 5. Throughput aktual tetap dipengaruhi Wi-Fi, beban Mac, dan jadwal event sistem; kode tidak dapat menjamin 60 frame per detik pada setiap kondisi jaringan.

## Build optimasi 60 Hz dan pemulihan gesture empat jari

Lihat `PERFORMANCE-GESTURE-FIX.md`. Build ini mengirim gerakan pointer/scroll maksimal sekali per frame pada target 60 Hz, memakai TCP no-delay, memindahkan parsing/event posting Mac dari UI thread, dan menampilkan pointer input rate yang terukur di Mac Helper. Gesture empat jari kini dieksekusi saat threshold terdeteksi serta dievaluasi lagi jika UIKit membatalkan touch sequence.

Pada iPad, nonaktifkan **Settings → Multitasking & Gestures → Four & Five Finger App Switching** agar iPadOS tidak mengambil alih gesture empat jari yang sama.


## Diagnostik gesture 4 jari dan shortcut macOS

1. Pada iPad, buka Settings → Multitasking & Gestures. Matikan **Four & Five Finger App Switching** supaya iPadOS tidak mengambil swipe empat jari yang sedang dipakai EvoPad. Apple mendokumentasikan toggle ini sebagai pengendali swipe/pinch empat atau lima jari.
2. Swipe dengan tepat empat jari pada permukaan trackpad EvoPad, bukan dari tepi layar.
3. Lihat baris **Mac:** di aplikasi iPad. Jika belum berubah, perintah belum mendapat acknowledgement dari Mac Helper.
4. Jika baris Mac menyatakan event dipost tetapi Mission Control tidak terbuka, klik tombol **Tes** di baris Atas pada Mac Helper. Bila tes Mac juga tidak bekerja, periksa System Settings → Keyboard → Keyboard Shortcuts → Mission Control dan pastikan Control + Up aktif.
5. Mac Helper memakai CGEventSource `.combinedSessionState` dan mem-post ke `.cgSessionEventTap`, sesuai pemakaian aplikasi GUI pada sesi login.

Catatan: ACK memastikan Mac Helper menerima arah gesture dan berhasil membuat/mem-post event. macOS tidak menyediakan konfirmasi publik bahwa Mission Control/Spaces benar-benar tampil.


### Jika swipe 4 jari tetap tidak bereaksi

- Pastikan Settings iPad → Multitasking & Gestures → **Four & Five Finger App Switching** dalam posisi OFF. Bila ON, iPadOS sendiri memakai swipe empat/lima jari untuk berpindah aplikasi dan dapat membatalkan sentuhan aplikasi.
- Setelah swipe, lihat baris **Mac:** pada aplikasi iPad. Jika belum berubah, gesture tidak mendapat ACK dari Mac Helper.
- Jika ACK Mac muncul tetapi Mission Control tidak terbuka, pada jendela Mac Helper klik **Tes** di baris Atas. Jika tes langsung ini juga tidak bekerja, periksa shortcut Control + Up di macOS Keyboard Shortcuts → Mission Control dan pastikan Mac Helper masih diberi Accessibility.
- Event keyboard kini memakai `CGEventSource(stateID: .combinedSessionState)` dan dikirim ke `.cgSessionEventTap`, yaitu jalur event untuk sesi login aplikasi GUI.
