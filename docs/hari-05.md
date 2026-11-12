# Hari 5: UI toko

File baru: `src/client/ShopView.luau` (tampilan). Ditulis ulang: `src/client/init.client.luau` (controller: state, input, remote). Server tidak diubah.

## 1. Tujuan

Sampai Hari 4, pemain membeli lewat tombol keyboard J/K/L dan hasilnya hanya muncul di Output. Hari ini ada UI sungguhan: saldo koin, daftar item dengan status (bisa dibeli, kurang koin, dimiliki), tombol beli yang mengirim request ke server, dan pemberitahuan kalau progres tidak disimpan (`DataStatus` dari Hari 4). UI harus aman di HP: tidak tertutup notch atau tombol sistem, target sentuh cukup besar, dan tetap utuh setelah karakter mati.

Aturan Hari 2 tetap berlaku: server sumber kebenaran, UI hanya mencerminkan. UI tidak pernah menghitung saldo sendiri.

Analogi Laravel/JS:

- `ShopView` seperti komponen Vue atau React yang hanya menerima props: `render(state)` menggambar ulang dari satu table state. Dia tidak memanggil API dan tidak menyimpan data sendiri.
- `init.client.luau` seperti store/controller di sisi frontend (Pinia, Redux): memegang state, mendengar event, dan memanggil "API" (RemoteEvent).
- `leaderstats.Coins` dan folder `Inventory` adalah respons API yang selalu segar (server yang menulis, Roblox yang mereplikasi). `BuyResult` hanya seperti flash message `session()->flash('status', ...)`: untuk teks pemberitahuan, bukan untuk data.
- Status "Memproses..." dengan batas waktu mirip tombol submit yang di-disable selama `fetch` berjalan, plus `AbortController` dengan timeout.

## 2. Konsep inti

### ScreenGui, PlayerGui, dan respawn

UI 2D di Roblox hidup di `ScreenGui` di dalam `Player.PlayerGui`. Kalau `ResetOnSpawn = true` (bawaan), Roblox menghapus dan membuat ulang ScreenGui setiap karakter respawn. Toko ini dibuat dari LocalScript di `StarterPlayerScripts` yang hanya jalan sekali per sesi, jadi `ResetOnSpawn = false`. Kalau tidak, setelah mati pertama kali UI hilang dan tidak pernah dibuat lagi.

Brief mengizinkan UI dibuat dari kode client atau dari model Rojo. Dipilih kode, supaya semua bisa dibaca dan di-diff di satu tempat. Harganya: di Explorer, `ShopGui` baru muncul saat Play.

### Area aman

`ScreenInsets = CoreUISafeInsets` (bawaan untuk ScreenGui baru) menaruh UI di bawah topbar Roblox dan di luar notch. `DeviceSafeInsets` hanya menghindari notch, sedangkan `None` memakai layar penuh. Tes device di bagian 5 mengukur bahwa area `CoreUISafeInsets` memang di dalam area aman perangkat, termasuk iPhone landscape yang notch-nya memakan 62 px di kiri dan kanan.

### Ukuran: skala, offset, dan batas

`UDim2.new(skalaX, offsetX, skalaY, offsetY)`. Panel memakai skala (90% x 90% layar) dengan `UISizeConstraint` maksimum 420x300 piksel, jadi di desktop ukurannya tetap dan di HP pendek ikut mengecil. Daftar item ada di `ScrollingFrame` dengan `AutomaticCanvasSize = Y`, jadi kalau layar terlalu pendek daftarnya bisa di-scroll, bukan terpotong.

`UIListLayout` menyusun anak berurutan seperti flexbox satu arah. `UIFlexItem` dengan `FlexMode = Fill` membuat satu anak mengisi sisa ruang (judul "Toko" mendorong tombol Tutup ke kanan, daftar mengisi sisa tinggi panel).

### Input

- Tombol GUI memakai `Activated`, bukan `MouseButton1Click`, karena `Activated` juga terpicu oleh sentuhan dan tombol A gamepad.
- Pintasan B (keyboard) dan Y (gamepad) dipasang lewat `ContextActionService`. Saat pemain mengetik di chat, aksi CAS tidak terpicu. Dengan `UserInputService.InputBegan` kamu harus mengecek `gameProcessedEvent` sendiri.
- `UserInputService.PreferredInput` memberi tahu perangkat utama pemain. Petunjuk "(B)" hanya ditampilkan untuk keyboard dan mouse. `TouchEnabled` tidak dipakai karena laptop layar sentuh juga `true`.
- Fokus gamepad: panel memakai `SelectionGroup = true` dan `SelectionBehavior* = Stop` supaya fokus tidak keluar dari panel. Saat panel dibuka dengan gamepad, fokus diletakkan di tombol Beli pertama yang aktif, atau Tutup kalau tidak ada.

### Desain

Tidak ada arahan desain dari brief, jadi ini draft tanpa arahan desain: HUD dan panel gelap sederhana gaya Roblox, tanpa animasi, satu warna aksen emas khusus untuk jumlah koin dan tombol Beli. Token warna dan ukuran ada di table `THEME` di `ShopView`.

Kontras dicek dengan `contrast-check.py` (WCAG AA, minimal 4.5:1 untuk teks):

| Teks | Latar | Rasio |
|---|---|---|
| Putih `#FFFFFF` | panel `#1B2130` | 16.07 |
| Abu muda `#C5CCD8` (harga) | panel | 9.95 |
| Emas `#F2C14E` (koin) | panel | 9.58 |
| Panel `#1B2130` (teks Beli) | emas | 9.58 |
| Hijau `#7FD49B` (Dimiliki) | panel | 9.02 |
| Oranye `#FFB86B` (pemberitahuan) | panel | 9.43 |
| Abu `#AEB6C4` (tombol nonaktif) | tombol `#2C3446` | 6.10 |
| Putih (Tutup) | tombol | 12.45 |
| Abu `#8A94A6` | tombol | 4.07, gagal |

Pasangan terakhir gagal untuk teks, jadi `#8A94A6` hanya dipakai untuk garis tepi dan scrollbar. Klaim awal "semua lolos" salah dan dikoreksi saat review desain.

## 3. Penjelasan kode

### `ShopView`: hanya menggambar

`ShopView.new(parent, handlers)` membuat pohon UI sekali. Tombol hanya memanggil `handlers.onBuy(itemId)` atau `handlers.onToggle()`. `ShopView:render(state)` mengatur teks, warna, dan visibilitas dari state, tanpa membaca `leaderstats` atau memanggil remote. Karena itu modul ini bisa dites dengan state palsu dan parent di luar `PlayerGui` (bagian 5).

Status tiap baris ditentukan `ShopView.rowState(itemId, state)` dengan urutan prioritas: data gagal dimuat, masih memuat, dimiliki, sedang diproses, kurang koin, bisa dibeli. Hanya jenis `buy` yang membuat tombol `Interactable`, `Selectable`, dan berwarna emas.

Baris dibuat dari `Config.Items` diurutkan dengan `Order`. Menambah item di Config otomatis menambah baris.

Satu jebakan saat membangun: `AutomaticSize` hanya menambah ukuran, tidak pernah mengecilkan di bawah `Size`. Frame baru punya `Size` bawaan 100x100 dan TextLabel 200x50, jadi label dengan `AutomaticSize` tetap selebar 200 piksel walaupun teksnya pendek. Semua elemen dengan `AutomaticSize` diberi `Size = UDim2.new()` dulu.

### `init.client.luau`: controller

State:

```lua
local state = {
    loaded = false, failed = false, -- cermin server sudah sampai / tidak sampai dalam 60 detik
    coins = 0, owned = {},          -- hanya dari leaderstats.Coins dan folder Inventory
    pending = {},                   -- itemId -> token request yang menunggu balasan
    status = player:GetAttribute("DataStatus"),
    message = nil, open = false, keyHint = false,
}
```

Alur beli:

1. `buy(itemId)` memeriksa `rowState` lagi. Kalau bukan `buy`, berhenti. Ini pagar kedua selain `Interactable = false`, karena event tombol tetap bisa terpicu lewat jalur lain (misalnya tombol yang sedang dipilih lalu ditekan Enter).
2. Item ditandai `pending` dengan token baru, lalu `BuyItem:FireServer(itemId)`. Harga tidak dikirim.
3. Status pending hilang oleh yang datang lebih dulu: balasan `BuyResult`, item muncul di `Inventory`, atau batas waktu 3 detik. Server sengaja tidak membalas request yang kena rate limit (Hari 2), jadi tanpa batas waktu tombol bisa macet di "Memproses..." selamanya.
4. Timeout hanya menghapus pending kalau tokennya masih sama. Kalau balasan sudah datang lalu pemain membeli lagi, timeout lama tidak boleh menghapus request yang baru.

`BuyResult` hanya mengisi pesan ("Sepatu Kilat dibeli."). Koin dan kepemilikan datang dari cermin, karena koin juga berubah tanpa `BuyResult` (pickup), dan dua sumber data untuk hal yang sama cepat atau lambat akan bertentangan.

Setiap `render()` juga memeriksa fokus: kalau tombol yang sedang dipilih berubah jadi tidak bisa dipilih (misalnya baru saja jadi "Dimiliki"), fokus dipindah ke `focusTarget()`. Tanpa ini, pemain gamepad kehilangan fokus setelah membeli.

Cermin menunggu `leaderstats`, `Coins`, dan `Inventory` dengan batas 60 detik, karena load DataStore Hari 4 bisa mencoba ulang beberapa kali. Selama itu UI menampilkan "Memuat...". Kalau tidak datang, UI menampilkan "Data tidak termuat. Coba masuk ulang." dan semua tombol beli nonaktif.

## 4. Jebakan dan celah yang ditutup

- Client mengubah koin lokal. Exploiter bisa mengubah `leaderstats.Coins` di client jadi 999, dan UI ikut menampilkan 999 lalu mengaktifkan tombol Mahkota Emas. Itu tidak masalah: server menghitung dari datanya sendiri dan membalas `NotEnoughCoins`. UI yang bisa dibohongi tidak apa-apa, selama server tidak.
- Menghitung saldo di client setelah beli (`coins -= price`). Kalau request ditolak atau tidak dibalas, angka di layar salah sampai server mengirim nilai baru. Cermin server cukup cepat; jangan menebak.
- `ResetOnSpawn = true` untuk UI yang dibuat dari `StarterPlayerScripts`: UI hilang setelah mati pertama kali.
- Pintasan keyboard yang terpicu saat mengetik di chat. Dengan `ContextActionService` ini tidak terjadi (dites di bagian 5).
- Escape tidak dipakai untuk menutup panel. Di Roblox, Escape dipakai untuk menu sistem dan untuk melepas fokus chat (terlihat di tes 9), jadi tidak diikat ke panel. Ini penyimpangan yang disengaja dari kebiasaan "Escape menutup modal". Panel ditutup dengan tombol Tutup, B, atau Y.
- Klik yang tembus panel. Frame dengan `Active = false` (bawaan) tidak menahan input: klik atau sentuhan di latar panel tetap sampai ke game dengan `gameProcessed = false`, jadi kamera bisa ikut berputar atau Tool yang dipegang (pedang Hari 8) bisa ikut terayun. Yang diukur di sini hanya `gameProcessed`; efek ke pedang dites di Hari 8. HUD dan panel diberi `Active = true` (tes 13).
- `GuiService.SelectedObject` diisi tombol yang tidak `Selectable` atau tidak tampil: Studio menulis warning `Setting GuiService.SelectedObject to invalid GuiObject`. Kode hanya memilih hasil `focusTarget()`, yang selalu tombol aktif atau Tutup.
- Tes klik yang lolos palsu. Tes "klik tombol nonaktif tidak mengirim request" juga lolos kalau kliknya tidak sampai sama sekali. Karena itu setiap batch klik negatif ditutup dengan klik kontrol (Tutup) yang harus berhasil, dan request dihitung di server, bukan di client.

## 5. Bukti tes

Sinkron: `SYNC OK 11 script` (ditambah `ShopView`). Gate statis: `selene src` 0 error 0 warning, `stylua --check src` lolos.

### Probe sebelum desain

- `screen_capture` saat Play menangkap `PlayerGui`, jadi UI bisa dilihat dan diukur.
- `user_mouse_input` hanya mengenai tombol GUI kalau jendela Studio sedang di depan. Saat Studio di belakang, input sampai ke `UserInputService` (`InputBegan`, `gameProcessed = true`) tapi `Activated` tidak pernah terpicu. Setiap batch klik di bawah didahului memindahkan Studio ke depan dan memeriksa judul jendela depan (`Place1 - Roblox Studio`).
- `GuiService.SelectedObject = tombol` lalu tombol Enter lewat `user_keyboard_input` memicu `Activated` walaupun Studio di belakang. Ini jalur keyboard/gamepad, bukan klik.

### Tes unit (datamodel Client, `ShopView` dengan parent `Folder` di luar `PlayerGui`)

Hasil: `49 cek, 0 gagal` (dijalankan ulang setelah perubahan terakhir pada `ShopView`). Mencakup: semua cabang `rowState` (gagal, memuat, dimiliki mengalahkan pending, pending hanya memblok item itu, kurang 1 koin, pas harga), semua teks `noticeText` (`Ok`, belum ada status, `Offline`, `Locked`, `Error`, status tak dikenal, data gagal), `ResetOnSpawn = false`, `ScreenInsets`, `Active` pada HUD dan panel, urutan baris, HUD/panel bergantian tampil, petunjuk "(B)" hanya untuk keyboard, warna dan `Interactable`/`Selectable` per jenis baris, `focusTarget` (Beli pertama yang aktif, Tutup kalau tidak ada, item pertama kalau semua bisa), tampilan memuat dan gagal, dan render tidak pernah memanggil handler.

### Tes live (Play, desktop, `DataStatus = Offline`)

Penghitung request dipasang di server: koneksi kedua ke `BuyItem.OnServerEvent` yang mencatat setiap request.

1. Panel dibuka dengan B: judul, "0 koin", Tutup, pemberitahuan offline, tiga baris "Kurang 5/15/50 koin" nonaktif. Baris rata atas.
2. Klik negatif, koin 0: klik Sepatu Kilat dan Mahkota Emas (nonaktif), lalu klik Tutup sebagai kontrol. Panel tertutup (klik sampai), server menerima 0 request.
3. Pickup sampai 6 koin, klik Toko di HUD lalu Beli Sepatu Kilat: server 1 request `SpeedBoots`, koin 6 menjadi 1, `Inventory.SpeedBoots` ada. Layar: "Dimiliki" hijau, "1 koin", pesan "Sepatu Kilat dibeli.".
4. Klik negatif setelah beli: dua klik pada "Dimiliki" dan satu pada Pegas Lompat (kurang koin), lalu Tutup. Panel tertutup, request di server tetap 1.
5. Tamper: client mengubah `Coins` lokal jadi 999. UI menampilkan "999 koin" dan Mahkota Emas "Beli". Klik Beli: server menerima request `GoldCrown`, membalas `NotEnoughCoins`, koin server tetap 1, Inventory tetap. Pesan "Koin belum cukup untuk Mahkota Emas.". Satu pickup kemudian, cermin kembali ke nilai server (2 koin, "Kurang 48 koin").
6. Timeout: client mengirim argumen sampah (`123`) 10x per detik untuk menghabiskan rate limit (`BadType` memakai token tapi tidak dibalas), lalu klik Beli Mahkota Emas dengan 50 koin. Saat itu: "Memproses...", tombol nonaktif. 3,5 detik kemudian: tombol "Beli" lagi, pesan "Server tidak membalas. Coba lagi.". Server: request `GoldCrown` sampai, koin tetap 50, Inventory tidak berubah. Percobaan pertama gagal karena spam (90 request) sudah selesai sebelum klik masuk; cap waktu di server menunjukkan jaraknya, lalu tes diulang dengan spam 400 request.
7. Coba lagi lewat keyboard setelah spam selesai: `SelectedObject` = tombol Mahkota Emas, Enter. Server request kedua `GoldCrown`, koin 50 menjadi 0, "Dimiliki", pesan "Mahkota Emas dibeli.", dan fokus pindah otomatis ke Tutup.
8. Keyboard negatif: `SelectedObject` = tombol "Dimiliki", Enter dua kali: request beli di server tetap 2 (log dikosongkan sebelum tes 6). Kontrol: `SelectedObject` = Tutup, Enter: panel tertutup, `SelectedObject` kosong.
9. Chat: tekan `/` untuk membuka chat, tekan B, ketik "beli b". `InputBegan` mencatat `B` dengan `gameProcessed = true` dan TextBox chat fokus, isi chat "beli b", panel tetap tertutup. Kontrol: Escape (chat lepas), B: panel terbuka.
10. Gamepad sintetis: `DPadDown` dan `ButtonY` lewat `user_keyboard_input` sampai sebagai `UserInputType.Keyboard` dengan KeyCode gamepad. `ButtonY` menutup panel lewat CAS. `PreferredInput` tetap `KeyboardAndMouse`.
11. Respawn dengan panel terbuka: karakter dibunuh dari server, respawn 5,3 detik. Satu `ShopGui` di `PlayerGui`, panel tetap terbuka, "0 koin", tiga baris "Dimiliki". B setelah respawn menutup panel.
12. Output: satu warning DataStore Hari 4 dan baris `ContentId ... 203785492` yang sudah ada sebelum kurikulum ini. Satu warning `invalid GuiObject` berasal dari tes 8, yang sengaja memilih tombol nonaktif. Untuk memastikan kode produksi tidak menulis warning itu, jalur pindah fokus diulang dengan penanda di Output: `print` sebelum Enter pada Beli Sepatu Kilat, `print` setelah render. Di antara kedua penanda tidak ada warning, tombol menjadi "Dimiliki", dan fokus pindah ke Tutup.
13. Input tidak tembus panel: logger `InputBegan` di client, klik di latar judul, di teks pemberitahuan, di Tutup, dan di HUD: semuanya `gameProcessed = true`. Klik kontrol di dunia (di luar UI): `gameProcessed = false`. Sebelum `Active = true` ditambahkan, klik di latar panel tercatat `gameProcessed = false`.

### Matriks device (Device Simulator, diukur dengan kode)

Device dipasang di datamodel Edit sebelum Play (setter-nya error saat Play), lalu `StopSimulationAsync` di akhir. Untuk setiap layar, kode memeriksa:

- HUD atau panel di dalam area `ShopGui`.
- Setiap elemen di luar daftar ada di dalam HUD atau panel.
- Isi daftar tidak keluar ke samping dari jendela daftar. Ke bawah memang boleh, karena di-scroll.
- `TextFits` untuk semua teks yang tampil, dan setiap tombol minimal 44x44.
- Baris terakhir daftar masih bisa dicapai setelah di-scroll ke bawah.

| Preset | Viewport | Area ShopGui | Panel | Daftar (tinggi/isi) | Masalah |
|---|---|---|---|---|---|
| iPhone 17 Pro landscape | 750x381 (layar 874x401, notch 62 px kiri dan kanan) | 750x323 | 420x290 | 164/164 | 0 |
| iPhone 17 Pro portrait | 401x778 | 401x720 | 360x300 | 173/173 | 0 |
| Galaxy A06 landscape | 705x338 | 705x280 | 420x252 | 125/148, scroll | 0 |
| Galaxy A06 portrait | 359x718 | 359x660 | 323x300 | 173/173 | 0 |
| iPad A16 portrait | 819x1179 | 819x1121 | 420x300 | 173/173 | 0 |
| Xbox One | 1919x1079 | 1919x992 | 420x300 | 173/173 | 0 |

HUD di semua preset 304x78 di tengah atas, jauh dari thumbstick dan tombol lompat (dilihat di screenshot iPhone). Di preset sentuh `PreferredInput = Touch` dan tombol HUD tertulis "Toko" tanpa "(B)".

Galaxy A06 landscape awalnya diukur dengan panel 0.8 tinggi layar: daftar hanya 97 px (dua baris). Panel dinaikkan ke 0.9, lalu semua baris tabel yang tingginya bergantung skala diukur ulang. Di A06 landscape daftar menjadi 125 px, dan baris ketiga terlihat sebagian sebagai tanda bisa di-scroll.

Cek samping daftar ditambahkan belakangan dan dijalankan di iPhone landscape dan A06 portrait, yaitu panel terlebar (420 px) dan tersempit (323 px). Preset lain lebar panelnya di antara keduanya.

### Yang belum bisa dites

- Gamepad sungguhan. Input gamepad sintetis datang sebagai keyboard, dan preset Xbox tetap `PreferredInput = KeyboardAndMouse` dengan `GamepadEnabled = false`. Cabang "fokus otomatis saat panel dibuka dengan gamepad" belum pernah jalan. Yang sudah dites: `focusTarget` (unit), pemindahan fokus setelah beli (tes 7), `ButtonY` lewat CAS (tes 10).
- Sentuhan. Di Device Simulator, klik `user_mouse_input` dikirim sebagai `Touch` dengan koordinat meleset (target tengah tombol (345,38), yang diterima (283,18) dan (467,227)), jadi tap pada tombol tidak bisa dites. Panel di preset sentuh dibuka dengan B.
- TV dari jarak jauh. Di Xbox panel hanya 420x300 di layar 1920x1080 dan teks terkecil 15 px. Belum ada skala khusus konsol (latihan 2).
- Pemberitahuan `Locked` dan `Error` di game live. Studio selalu `Offline`; teks lain hanya dites di unit.
- Pagar token timeout (alur beli langkah 4): balasan datang, pemain membeli lagi, lalu timeout lama jatuh. Urutan ini butuh tiga peristiwa dalam 3 detik dan hanya diperiksa dengan membaca kode.
- Dua client sekaligus.

## 6. Latihan mandiri

1. Tambahkan item keempat di `Config.Items`. Apa yang harus diubah di UI supaya item itu muncul?
   Petunjuk: lihat cara `ShopView.new` membuat baris.
2. Di konsol (TV), perbesar seluruh UI 1.5x.
   Petunjuk: `GuiService:IsTenFootInterface()` dan `UIScale`.
3. Kenapa jumlah koin di UI tidak diperbarui dari balasan `BuyResult`, padahal balasan itu datang tepat setelah beli?
   Petunjuk: koin bisa berubah tanpa ada pembelian, dan tidak semua request dibalas.

<details>
<summary>Kunci jawaban</summary>

1. Tidak ada. Baris dibuat dari `Config.Items` dan diurutkan dengan `Order`, dan daftar ada di `ScrollingFrame` dengan `AutomaticCanvasSize`, jadi baris keempat muncul dan daftar bisa di-scroll kalau tidak muat. Yang perlu diisi hanya `Name`, `Price`, dan `Order` yang unik.
2. Di `ShopView.new`, setelah `hud` dan `panel` dibuat:
   ```lua
   if GuiService:IsTenFootInterface() then
       make("UIScale", { Scale = 1.5, Parent = hud })
       make("UIScale", { Scale = 1.5, Parent = panel })
   end
   ```
   `UIScale` memperbesar hasil akhir, termasuk batas `UISizeConstraint`, jadi panel menjadi 630x450. Ukur lagi dengan preset Xbox: panel harus tetap di dalam area `ShopGui` (992 px tinggi).
3. Koin juga berubah karena pickup, dan nanti karena hadiah ronde dan dev product, tanpa `BuyResult`. Request yang kena rate limit tidak dibalas sama sekali. Kalau UI mengambil koin dari dua sumber, keduanya bisa bertentangan dan yang terakhir datang menang. Dengan satu sumber (`leaderstats.Coins` yang ditulis server), angka di layar selalu sama dengan angka server begitu replikasi sampai.

</details>
