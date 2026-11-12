# Hari 10: Koin respawn dan rapikan jadi portofolio

Diubah: `src/server/CoinPickup.luau`, `src/shared/Config.luau` (`Coin.RespawnSeconds`). File baru: `docs/hari-10.md`, `docs/rekam-demo.md`. `README.md` di root diganti dari template Rojo menjadi README portofolio berbahasa Inggris. Dokumen lama yang dirapikan: `hari-01.md`, `hari-04.md`, `hari-08.md`, `hari-09.md`, `docs/README.md`.

## 1. Tujuan

1. Koin hilang setelah diambil, lalu muncul lagi 8 detik kemudian. Ini perbaikan masalah Hari 1: koin yang tidak pernah hilang bisa di-farm.
2. Uji regresi semua hari dalam satu sesi Play, setelah edit kode terakhir.
3. README bahasa Inggris untuk calon klien, dan skenario rekam video demo 1 sampai 2 menit.

Kalau dari Laravel: koin seperti stok flash sale. Setelah satu orang checkout, stok dikunci di database, bukan dengan tombol yang di-disable di browser. Tombol disabled hanya UX; yang menentukan adalah baris di database. Stok dibuka lagi oleh job yang di-dispatch dengan `->delay(8)`. Job itu membawa token versi, supaya job lama tidak membuka kunci yang sudah dipasang ulang oleh checkout berikutnya. Regresi menyeluruh setara `php artisan test` penuh sebelum rilis, bukan hanya test untuk fitur yang baru disentuh.

## 2. Konsep inti

### Siapa yang memutuskan koin sedang tersembunyi

Saat koin diambil, server mengubah tiga hal. Hanya satu yang dipakai untuk memutuskan bayar.

| Yang diubah | Untuk siapa | Dipakai untuk memutuskan bayar? |
|---|---|---|
| `Transparency = 1` | mata pemain | tidak |
| `CanTouch = false` | engine berhenti mengirim `Touched` untuk part ini | tidak |
| `self._hidden[part]` | server | ya |

`Transparency` dan `CanTouch` tersalin ke client, dan client bisa mengubah salinannya sendiri. Kode lain di server, atau builder di Studio, juga bisa mengubahnya. Kalau `take` memutuskan dari `CanTouch`, koin yang kebetulan disetel `CanTouch = true` oleh skrip lain bisa dibayar dua kali (mutan M2, tes U7). Tabel `_hidden` hanya bisa diubah oleh `CoinPickup` di server.

### `Touched` menyala lagi saat koin muncul

Diukur di tes live L1: pemain yang diam di dalam koin dibayar lagi setiap kali koin muncul. Pickup tercatat 0,05 sampai 0,11 detik setelah server mengembalikan `CanTouch = true`, sementara karakter diam di tempat. Jadi sentuhan baru muncul begitu `CanTouch` kembali, tanpa pemain berjalan.

Kriteria lulus perbaikan Hari 1 adalah paling banyak satu pickup per koin per jendela respawn. Itu terpenuhi: pemain yang berdiri di satu koin dapat 1 koin tiap sekitar 8,1 detik. Bandingkan dengan Hari 9 (sekitar tiap 3,8 detik) dan farm bolak-balik Hari 1 (+8 dalam 10 detik). Kalau pemain harus keluar dulu sebelum dibayar lagi oleh koin yang sama, itu butuh aturan tambahan; repo ini sengaja tidak membuatnya, karena berdiri diam memberi jauh lebih sedikit daripada berkeliling lima koin.

### Kenapa disembunyikan, bukan di-Destroy lalu dibuat baru

| | Sembunyikan lalu tampilkan (dipakai) | `Destroy` lalu clone baru |
|---|---|---|
| Instance | tetap sama | baru setiap respawn |
| Koneksi `Touched` | tetap satu per koin | dilepas lalu dibuat lagi lewat sinyal tag |
| Koin buatan builder (ukuran, mesh, warna) | utuh | harus disimpan sebagai template dulu |
| Skrip lain yang memegang referensi koin | tetap valid | menunjuk part yang sudah hancur |
| Kelemahan | Decal atau efek di dalam koin tetap terlihat | lebih banyak kode dan alokasi |

Karena instance tidak pernah dilepas, tag `Koin` juga tidak pernah dilepas lalu dipasang ulang. `GetInstanceAddedSignal` tidak menyala saat koin muncul lagi.

### Jadwal sisa dari pengambilan lama

Setiap `hide` menjadwalkan `show` 8 detik kemudian. Urutan ini bisa terjadi:

1. Detik 0: koin diambil. Jadwal A: tampilkan di detik 8.
2. Sesaat kemudian: tag dilepas (`unbind` langsung menampilkannya), lalu dipasang lagi.
3. Detik 4: koin diambil lagi. Jadwal B: tampilkan di detik 12.
4. Detik 8: jadwal A jatuh tempo.

Tanpa pengecekan, jadwal A menampilkan koin 4 detik terlalu cepat. Karena itu setiap `hide` membuat record baru, dan jadwalnya hanya boleh menampilkan koin kalau record yang tersimpan masih record miliknya. Tes berwaktu T2 menjalankan urutan ini; mutan M5 (tanpa cek record) tertangkap.

### Angka ekonomi

`RespawnSeconds = 8` dipilih dari waktu jalan, bukan ditebak. Di demo, lima koin terkumpul dalam 10,2 detik (9,57 sampai 19,73). Satu putaran lebih lama dari 8 detik, jadi pemain yang berkeliling tidak pernah menunggu koin pertama muncul lagi. Pemain yang diam di satu koin mendapat 1 per 8 detik, kira-kira lima kali lebih sedikit.

Hitungan dari `Config` dan putaran demo (bukan pengukuran pembelian): sekitar 29 koin per menit. `SpeedBoots` (5) terbeli setelah putaran pertama. Dari nol, 15 koin untuk `JumpCoil` butuh sekitar 30 detik dan 50 koin untuk `GoldCrown` sekitar 100 detik. Membeli ketiganya (70 koin) sekitar 140 detik, lebih cepat dengan hadiah ronde (10) dan kill boneka (5). Skill `roblox-simulator-economy` dibaca sebelum angka ini dikunci. Kalkulatornya untuk kurva harga upgrade dan rebirth; toko ini hanya punya tiga harga tetap, jadi kalkulator itu tidak dipakai.

## 3. Penjelasan kode

### `take`: urutan cek

```lua
function CoinPickup:take(part: BasePart, player: Player): boolean
	if self._hidden[part] or not self:collect(player) then
		return false
	end
	self:hide(part)
	return true
end
```

Koin disembunyikan hanya kalau `collect` berhasil. Pemain yang masih cooldown, atau yang datanya belum termuat, tidak menghabiskan koin untuk pemain lain (U3, U4). Kalau urutannya dibalik (sembunyikan dulu, baru `collect`), koin hilang tanpa ada yang dibayar (mutan M3).

Handler `Touched` di `bind` sekarang memanggil `take`, bukan `collect`. `collect` tidak berubah, jadi semua tes `collect` dari Hari 3, 7, dan 9 tetap berlaku.

### `hide` dan `show`

```lua
function CoinPickup:hide(part: BasePart)
	local hidden = { transparency = part.Transparency }
	self._hidden[part] = hidden
	part.Transparency = 1
	part.CanTouch = false
	task.delay(Config.Coin.RespawnSeconds, function()
		if self._hidden[part] == hidden then
			self:show(part)
		end
	end)
end
```

`hidden` menyimpan `Transparency` asli. Koin yang dibuat builder setengah transparan kembali ke nilainya sendiri, bukan ke 0 (U5, mutan M6). Perbandingan `==` di dalam jadwal membandingkan identitas tabel: record yang dibuat `hide` berikutnya adalah tabel lain, walaupun isinya sama.

`show` hanya bekerja kalau koin memang sedang tersembunyi, jadi memanggilnya dua kali aman.

### `unbind` ikut memanggil `show`

```lua
function CoinPickup:unbind(part: Instance)
	local connection = self._touched[part]
	if connection then
		connection:Disconnect()
		self._touched[part] = nil
		self:show(part :: BasePart)
	end
end
```

Part yang tagnya dilepas saat sedang tersembunyi bukan koin lagi. Tanpa `show`, part itu tidak terlihat dan tidak bisa disentuh selamanya (mutan M4). Saat koin di-`Destroy`, sinyal removed juga memanggil `unbind`; mengubah properti part yang sudah di-Destroy tidak error, dan entrinya terhapus (U6).

### `shortcut` yang ditulis di kode

```lua
-- shortcut: hanya part ini yang disembunyikan; Decal atau efek di dalamnya tetap terlihat.
-- Kalau builder memakai koin berhias, sembunyikan anak-anaknya juga.
```

Koin di repo ini Part polos, jadi itu cukup. Batasannya ditulis di tempat orang berikutnya akan membaca.

## 4. Jebakan dan celah

- Memutuskan dari `CanTouch` atau `Transparency` (M2). Keduanya bisa diubah pihak lain.
- Tanpa guard sama sekali (M1). Dua `Touched` dari dua pemain di frame yang sama membayar keduanya.
- Menyembunyikan sebelum `collect` berhasil (M3).
- Jadwal `show` tanpa cek record (M5). Bug ini hanya muncul kalau koin dilepas lalu dipasang lagi di tengah jendela respawn, jadi tidak terlihat di tes biasa.
- `unbind` tanpa `show` (M4), dan `show` yang memasang `Transparency = 0` alih-alih nilai asli (M6).
- Koin berhias: Decal di dalam part tetap terlihat saat part disembunyikan.
- Pemain yang diam di dalam koin dibayar tiap kali koin muncul. Ini sesuai kriteria (satu per jendela respawn), tapi tetap perilaku yang harus diketahui pembaca kode.
- Celah lama tetap terbuka: teleport (Hari 8) dan sentuhan palsu dari jauh (Hari 9, latihan 3). Respawn membatasi kerugiannya. Exploiter yang berteleport ke kelima koin tetap dibatasi 5 koin per jendela respawn, sama dengan pemain jujur yang paling cepat (hitungan, lihat latihan 1).

## 5. Bukti tes

Gate: `selene src` 0 error 0 warning, `stylua --check src` lolos, sinkronisasi Rojo `SYNC OK 17 script`. Semua tes di bawah, kecuali jalan demo, berjalan dalam satu sesi Play setelah edit `src` terakhir.

### Tes unit Hari 10 (datamodel Server saat Play)

Instance modul baru, PlayerData palsu, pemain palsu berupa table. Hasil: 7/7.

| Tes | Yang dibuktikan |
|---|---|
| U1 | pickup sah: `addCoins` dipanggil sekali, koin `Transparency` 1, `CanTouch` false, tercatat di `_hidden` |
| U2 | koin tersembunyi tidak bisa diambil pemain lain: `take` kedua `false`, `addCoins` tetap 1 kali |
| U3 | pemain yang masih cooldown tidak menghabiskan koin kedua: koin kedua tetap terlihat |
| U4 | data pemain belum termuat: `take` `false`, koin tetap terlihat |
| U5 | `unbind` saat tersembunyi: `Transparency` kembali 0,3 (nilai asli), `CanTouch` true |
| U6 | `Destroy` saat tersembunyi lalu `unbind`: tanpa error, entri `_hidden` dan `_touched` hilang |
| U7 | `CanTouch` disetel true dari luar: `take` kedua tetap `false` |

Tes berwaktu (12,33 detik): 2/2.

| Tes | Yang dibuktikan |
|---|---|
| T1 | koin tersembunyi 0,2 detik sebelum 8 detik, terlihat 0,3 detik sesudahnya, dan bisa diambil lagi |
| T2 | urutan jadwal sisa di bagian 2: setelah jadwal lama jatuh tempo koin masih tersembunyi, lalu muncul sesuai jadwal baru |

| Mutan | Tertangkap oleh |
|---|---|
| M1 `take` tanpa guard `_hidden` | U2, U7 |
| M2 guard memakai `CanTouch` | U7 |
| M3 sembunyikan sebelum `collect` | U3, U4 |
| M4 `unbind` tanpa `show` | U5, U6 |
| M5 jadwal `show` tanpa cek record | T2 |
| M6 `show` memasang `Transparency = 0` | U5 |

Setelah mutan, fungsi asli dikembalikan: 7/7 lagi. M5 dipasang per instance dan berjalan bersamaan dengan versi asli.

### Tes live (pemain asli, pencatat di server)

`DataStatus` pemain `Offline` (place belum dipublish), jadi koin hanya ada di memori sesi. Server mencatat setiap perubahan `leaderstats.Coins` dan setiap perubahan `Transparency` koin dengan stempel waktu.

1. L1, ulangan tes Hari 9: karakter berjalan ke koin (20, 3, 10) dengan `character_navigation` lalu diam. Pickup pada detik 9,73, 17,80, 25,93, dan 34,02; koin muncul lagi pada 17,75, 25,82, dan 33,93. Koin 0 menjadi 4 dalam sekitar 32 detik, satu per jendela respawn. Datamodel Client membaca koin itu `Transparency` 1 dan `CanTouch` false setelah pickup pertama, jadi penyembunyian di server tersalin ke client.
2. Farm, skrip yang sama dengan Hari 1: server memindahkan karakter masuk dan keluar koin (20, 3, 10) tiap 0,25 detik selama 10 detik. Dua pickup, pada detik 105,88 dan 114,11. Hari 1 memberi +8. Angka total di sesi itu 18 menjadi 30 karena ada hadiah ronde +10 pada detik 113,81 di antara keduanya; pencatat menunjukkan hadiah itu tidak berasal dari koin.
3. Negatif, client mengubah koin secara lokal. Percobaan pertama tidak sah: karakter berdiri di dalam koin, jadi +1 yang muncul (16 menjadi 17) bisa berasal dari koin yang muncul lagi di server. Diulang dengan jendela lebih pendek dari 8 detik: setelah koin tersembunyi, client menyetel `CanTouch = true` dan `Transparency = 0` di salinannya, lalu memindah karakternya sendiri lewat `CFrame` di client, masuk-keluar koin 10 kali selama 6 detik. Koin tetap 18. Di akhir tes client masih melihat koin itu utuh, server tidak membayar.

### Regresi semua hari (sesi Play yang sama)

Hari 1 dan 2 tidak punya suite unit karena kodenya dipecah menjadi modul di Hari 3; perilakunya dicakup suite Hari 3 dan tes E2E di bawah.

| Suite | Hasil |
|---|---|
| Hari 3 (modul, toko, PlayerData, koin) | 36/36 |
| Hari 4 (DataStore, sesi, lease) | 47/47 |
| Hari 5 (UI toko, datamodel Client) | 55/55. Cek tata letak di viewport 1094x616: HUD tertutup dan panel terbuka tanpa masalah; daftar 173 px, isi 173 px, baris terakhir terjangkau |
| Hari 6 (receipt, gamepass, schema 2) | 34/34 |
| Hari 7 (ronde) | 19/19, 6 mutan tertangkap |
| Hari 8 (combat) | 14/14, 9 mutan tertangkap, kontrol lolos |
| Hari 9 (rate limit, tag koin) | 12/12, mutan N1 sampai N5 tertangkap |
| Hari 10 | 7/7 dan 2/2 berwaktu, mutan M1 sampai M6 tertangkap |

### E2E per hari (pemain asli, satu sesi Play)

1. Hari 5, klik UI dengan `user_mouse_input` di datamodel Client: membeli `Sepatu Kilat` mengirim tepat 1 request, koin 30 menjadi 25. Panel menulis "Dimiliki", pesan "Sepatu Kilat dibeli.", dan `Mahkota Emas` menulis "Kurang 25 koin".
2. Hari 2 dan 3, spam `BuyItem("JumpCoil")` dari client: 5 balasan (1 `Ok`, 4 `AlreadyOwned`), koin 25 menjadi 10. Satu request 2 detik kemudian mendapat balasan lagi karena bucket sudah terisi.
3. Hari 1 dan 2, client menyetel koinnya sendiri ke 999 lalu membeli `GoldCrown`: balasan `NotEnoughCoins`.
4. Argumen sampah, dikirim berjeda 1,1 detik supaya tiap request lolos rate limit dan sampai ke validasi: 10 request dengan `nil`, angka, `NaN`, boolean, table kosong, table berisi id, Instance, string 10.000 karakter, item palsu, dan `GoldCrown` plus argumen harga 0. Hanya satu balasan, untuk yang terakhir: `GoldCrown` `NotEnoughCoins`. Harga dari client diabaikan.
5. Hari 3, server menimpa `leaderstats.Coins` (cermin) menjadi 999: pembelian `GoldCrown` tetap `NotEnoughCoins`, dan pickup berikutnya mengembalikan cermin ke nilai sebenarnya ditambah 1 (10 + 1 = 11).
6. Hari 4: `DataStatus` `Offline`, peringatan DataStore muncul sekali, pemain tidak di-kick dan game tetap jalan.
7. Hari 7: fase terukur Round 44,97 detik, Result 5,97, Intermission 14,97; client melihat pergantian sekitar 0,05 detik setelah `EndsAt`. HUD menampilkan "Ronde mulai dalam N detik", "Ronde: N detik lagi. Skor kamu: N", "Kamu menang! +10 koin (skor 4)", dan "Ronde selesai. Tidak ada pemenang.". Hadiah ronde +10 tercatat dua kali.
8. Hari 8: `Activate` pedang dari 5,10 stud, boneka 100 menjadi 75. `FireServer` dari 30,01 stud: tetap 75. Tiga `Activate` lagi: 0, koin +5 (27 menjadi 32), boneka kembali 100 sekitar 6 detik kemudian.
9. Hari 9: 51 request `Attack`, nyawa boneka berubah dua kali (100, 75, 50). 50 `BuyItem` saat koin kurang: 5 balasan `NotEnoughCoins`. Tag `Koin` dari client pada Baseplate dan Part buatan client: server tetap 5 koin bertag, koin pemain tidak berubah. Setelah dua `LoadCharacterAsync`: satu pedang, 2 `Activate` menjadi tepat 2 request.
10. Output: peringatan DataStore yang sudah dikenal, noise `ContentId` lama, baris "Hadiah ronde gagal" dari pemain palsu suite Hari 7, dan satu error dari kode tes saya (referensi boneka lama setelah boneka respawn). Tidak ada error dari kode game.

Di sesi Play kedua, skenario `rekam-demo.md` dijalankan sekali dengan stempel waktu. Hasilnya ada di dokumen itu.

### Yang belum bisa dites

- Dua pemain sungguhan berebut satu koin. U2 membuktikannya dengan pemain palsu.
- Lag jaringan. Jeda antara `CanTouch` kembali dan pickup (0,05 sampai 0,11 detik) diukur di satu mesin.
- Sentuhan palsu dari alat exploit.
- DataStore dan pembelian sungguhan: place belum dipublish, ID gamepass dan produk masih 0.
- Koin berhias (Decal, efek partikel).

## 6. Latihan mandiri

1. Dengan angka sekarang (5 koin, muncul lagi tiap sekitar 8,1 detik, cooldown 1 detik), berapa koin per menit maksimum untuk pemain jujur yang berkeliling, dan untuk exploiter yang berteleport ke setiap koin begitu koin itu muncul?
2. Pemain A dan B menyentuh koin yang sama di frame yang sama. Siapa yang dapat? Bagaimana kalau A masih cooldown dari koin lain?
3. Kenapa jadwal di `hide` membandingkan `self._hidden[part] == hidden`, bukan cukup `if self._hidden[part] then`? Tulis urutan kejadian yang membuat versi kedua salah.

<details>
<summary>Kunci jawaban</summary>

1. Batasnya respawn, bukan cooldown. Satu koin paling banyak membayar sekali per sekitar 8,1 detik, jadi lima koin memberi paling banyak 5 per 8,1 detik, sekitar 37 koin per menit. Cooldown 1 detik mengizinkan 60 per menit, jadi bukan batas yang menentukan. Pemain jujur di demo butuh 10,2 detik untuk satu putaran, sekitar 29 koin per menit. Exploiter yang berteleport bisa mencapai sekitar 37, kira-kira seperempat lebih banyak, dan tidak lebih dari itu. Tanpa respawn (Hari 1 sampai 9), yang membatasi hanya cooldown: paling banyak 60 per menit dari satu koin. Farm Hari 1 mengukur +8 dalam 10 detik, sekitar 48 per menit.

2. Handler `Touched` di server berjalan bergantian. `take` pertama yang berjalan memanggil `collect`, berhasil, lalu mencatat koin di `_hidden`. `take` kedua melihat `_hidden` dan mengembalikan `false` (U2). Siapa yang pertama ditentukan urutan event yang tiba di server, bukan oleh kode kita. Kalau A masih cooldown, `collect` milik A gagal sebelum koin disembunyikan, jadi koin tetap tersedia dan B yang dapat (U3).

3. Versi kedua hanya bertanya "apakah koin sedang tersembunyi?", bukan "apakah masih tersembunyi oleh pengambilan yang menjadwalkan saya?". Urutannya: koin diambil di detik 0 (jadwal A untuk detik 8); tag dilepas dan dipasang lagi sesaat kemudian, jadi koin terlihat lagi; koin diambil lagi di detik 4 (jadwal B untuk detik 12). Di detik 8, jadwal A melihat koin tersembunyi dan menampilkannya, 4 detik lebih cepat. Dengan perbandingan record, jadwal A melihat record milik B dan tidak melakukan apa-apa. Tes T2 menjalankan urutan ini; mutan M5 adalah versi kedua dan tertangkap.

</details>
