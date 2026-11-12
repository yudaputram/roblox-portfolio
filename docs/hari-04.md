# Hari 4: DataStore (load, save, session lock)

File baru: `src/server/Store.luau`. Diubah: `src/server/PlayerData.luau` (load/save ke store, session lock, retry), `src/server/init.server.luau` (pasang store, autosave, `BindToClose`, atribut `DataStatus`). Client tidak diubah.

## 1. Tujuan

Sampai Hari 3, koin dan item hilang setiap kali pemain keluar. Hari ini data pemain disimpan ke DataStore: dimuat saat masuk, disimpan saat keluar, tiap 60 detik, dan saat server mati. Yang lebih penting dari "bisa simpan" adalah tidak pernah merusak data: data default tidak boleh menimpa data asli, dan dua server tidak boleh saling menimpa.

Analogi Laravel:

- DataStore itu seperti tabel key-value di database yang diakses lewat jaringan. Setiap panggilan bisa gagal atau kena rate limit, jadi perlakukan seperti memanggil API pihak ketiga, bukan seperti Eloquent ke MySQL lokal.
- `UpdateAsync` mirip optimistic locking (kolom `version` yang dicek saat `UPDATE`, lalu coba lagi kalau bentrok), bukan `lockForUpdate()` yang mengunci baris. Callback menerima nilai terbaru dan kamu putuskan nilai barunya. Kalau ada server lain menulis duluan, Roblox menjalankan callback lagi dengan nilai yang lebih baru. Kalau callback mengembalikan `nil`, tulis dibatalkan.
- Session lock mirip `Cache::lock("user:1", 300)`: hanya pemegang lock yang boleh menulis, dan lock punya TTL (lease) supaya tidak terkunci selamanya kalau server pemegangnya crash.
- Retry dengan backoff sama dengan `$tries` dan `$backoff` di queued job.
- Nomor `schema` di rekaman mirip tabel `migrations`: kode tahu versi bentuk data yang sedang dibaca.

Place ini belum dipublish, jadi DataStore asli selalu error. Seluruh logika dites dengan store palsu di memori; game asli tetap jalan dengan data di memori dan memberi tahu bahwa progres tidak disimpan.

## 2. Konsep inti

### Rekaman per pemain

Key: `Player_<UserId>` (UserId, bukan nama, karena nama bisa diganti). Nilainya:

```lua
{
    schema = 1,
    data = { Coins = 12, Inventory = { SpeedBoots = true } },
    lock = { owner = "<GUID server>", at = 1731400000 }, -- nil kalau tidak ada yang memegang
}
```

### Session lock dan lease

Pemain bisa sebentar ada di dua server (teleport, keluar lalu cepat masuk lagi). Tanpa lock, server lama bisa menyimpan snapshot basi setelah server baru menyimpan progres terbaru. Aturannya:

1. Saat load, server mengambil lock lewat `UpdateAsync`, tapi hanya kalau lock kosong, milik sendiri, atau sudah kedaluwarsa (lebih dari 300 detik sejak diperbarui).
2. Setiap save memeriksa di dalam callback bahwa lock masih milik server ini. Kalau bukan, tulis dibatalkan.
3. Save terakhir saat pemain keluar melepas lock di tulisan yang sama.

Lease 300 detik dipilih jauh di atas interval autosave (60 detik), jadi server yang sehat selalu memperpanjang lock sebelum kedaluwarsa. ID server memakai `HttpService:GenerateGUID`, karena `game.JobId` kosong di Studio.

### Error sementara dan error permanen

Throttle atau error 5xx bisa sembuh kalau dicoba lagi: tunggu 1, 2, lalu 4 detik. Error "You must publish this place to the web to access DataStore." tidak akan sembuh. Mencobanya lagi hanya membuang waktu pemain dan memenuhi Output. Untuk error seperti itu kode langsung berhenti memakai store di server ini dan menulis satu warning saja.

### Kalau load gagal, jangan pernah save

Ini aturan terpenting hari ini. Kalau load gagal lalu kode menganggap "pemain baru" dan menyimpan data default, koin asli pemain hilang. Jadi setiap sesi punya flag `persisted`. Hanya sesi yang berhasil mengambil lock yang `persisted = true`. Sesi lain (Offline, Locked, Error) tetap bisa dimainkan di memori, tapi tidak pernah menulis ke store.

Statusnya ditaruh di atribut pemain `DataStatus` (`Ok`, `Offline`, `Locked`, `Error`) supaya UI Hari 5 bisa memberi tahu pemain.

Ada harga yang dibayar. Pemain dengan sesi `Locked` atau `Error` melihat 0 koin dan progres sesi itu hilang saat keluar. `Locked` bisa terjadi kalau server lama butuh lebih dari 7 detik (1+2+4) untuk menyimpan dan melepas lock saat pemain pindah server. Banyak game memilih menendang pemain dengan pesan "coba masuk lagi" daripada membiarkannya bermain tanpa simpan. Kurikulum ini tidak menendang karena aturannya untuk DataStore yang gagal adalah "jangan crash, jangan kick pemain". Yang memberi tahu pemain adalah UI Hari 5.

### Kapan menyimpan

Saat keluar (`PlayerRemoving`), tiap 60 detik (autosave), dan saat server mati (`game:BindToClose`, Roblox memberi 30 detik). Tidak menyimpan setiap kali koin berubah, karena DataStore punya batas request per menit.

## 3. Penjelasan kode

### `Store`: satu bentuk, dua backend

Semua akses lewat `store:update(key, transform)`, bentuknya sama dengan `UpdateAsync`.

`Store.datastore(name)` memanggil `GetDataStore` di dalam `update`, bukan saat dibuat. Alasannya hasil probe di place ini: `GetDataStore` sendiri sudah error kalau place belum dipublish. Kalau dipanggil di level atas script, script server berhenti di baris itu dan handler toko, koin, dan pemain tidak pernah tersambung. Dengan cara ini errornya masuk `pcall` di `PlayerData` seperti error lain.

`Store.memory()` adalah store palsu untuk tes:

- Nilai disimpan sebagai string JSON, bukan table. Kalau store menyimpan table yang sama dengan sesi, mengubah koin setelah save ikut mengubah isi store, dan tes "data tersimpan" lolos padahal tidak ada yang tersimpan.
- `failNext(n, pesan)` membuat n panggilan berikutnya error dengan pesan itu.
- `onUpdate(key)` adalah hook yang dipanggil sebelum transform dan boleh yield. Dengan hook ini tes bisa menyisipkan kejadian di tengah operasi, misalnya pemain keluar saat load masih berjalan.
- Transform dijalankan dua kali dan hasil pertama dibuang. `UpdateAsync` asli boleh menjalankan callback lebih dari sekali, jadi kode yang punya efek samping di dalam callback akan ketahuan di tes.

### `PlayerData:load`

1. Tanpa store (dipakai tes Hari 3): sesi in-memory langsung, tanpa yield.
2. Ambil lock lewat `_claim`. Di dalam callback, variabel hasil di-reset di awal karena callback bisa jalan lebih dari sekali.
3. Lock milik server lain yang masih hidup: tunggu 1, 2, 4 detik dan coba lagi. Masih terkunci: sesi `Locked`.
4. Rekaman dengan `schema` lebih besar dari versi kode (ditulis versi game yang lebih baru): jangan disentuh, sesi `Error`.
5. Berhasil: data dibersihkan lewat `reconcile` (field yang hilang diisi default, field yang tipenya salah dibuang), sesi `Ok` dan `persisted`.

Pemain bisa keluar saat load masih menunggu store. `unload` menandai load itu batal. Setelah lock didapat, `load` melihat tandanya, langsung melepas lock lagi, dan tidak membuat sesi.

### `save`, `unload`, dan satu operasi per pemain

`unload` menghapus sesi dari memori dulu, baru menyimpan sambil melepas lock. Setelah baris pertama itu, pembelian yang datang terlambat ditolak `NotLoaded`, jadi snapshot yang ditulis adalah keadaan akhir.

Bug yang ditemukan saat review desain: pemain keluar, save `unload` lambat, pemain masuk lagi ke server yang sama. `load` yang baru melihat lock milik server ini sendiri, mengambil data lama (sebelum save selesai), lalu release dari `unload` menghapus lock sesi baru. Sejak itu semua save sesi baru batal tanpa suara. Solusinya `_lockKey`: satu operasi store per UserId dalam satu waktu, jadi `load` kedua menunggu `unload` selesai.

Kalau save mendapati lock sudah milik server lain (lease diambil alih), sesi diubah jadi tidak `persisted`, status `Locked`, dan tidak mencoba menulis lagi.

`save(player)` mengembalikan `true` hanya kalau data benar-benar tertulis. Hari 6 butuh ini: pembelian Robux baru boleh dianggap selesai setelah tersimpan.

### Perakit

```lua
local playerData = PlayerData.new({
    store = Store.datastore("PlayerData"),
    onChanged = StatsMirror.sync,
    onStatus = function(player, status)
        player:SetAttribute("DataStatus", status)
    end,
})
playerData:startAutosave()
game:BindToClose(function()
    playerData:closeAll()
end)
```

`closeAll` menyimpan semua sesi secara paralel lalu menunggu sampai semua save selesai (termasuk yang dimulai `PlayerRemoving`), dengan batas 25 detik supaya tidak melewati jatah 30 detik. Di `PlayerRemoving`, `unload` dipanggil paling akhir karena dia yang menunggu jaringan.

Semua yang perlu diganti saat tes (store, jam, fungsi tunggu, ID sesi, logger) masuk lewat `PlayerData.new(options)`. Tes memakai `wait` palsu, jadi backoff 1+2+4 detik tidak benar-benar ditunggu, dan jam palsu untuk melompat 301 detik ke depan.

## 4. Jebakan dan celah yang ditutup

- Data default menimpa data asli. Load gagal dianggap pemain baru, lalu save menulis Coins 0. Ditutup oleh flag `persisted`. Tes 2, 3, 11 membuktikan JSON di store tetap byte-identik, tes 4 dan 6 bahwa tidak ada yang tertulis sama sekali.
- `SetAsync` buta. Dua server menulis bergantian, yang terakhir menang. Semua tulis di sini lewat `UpdateAsync` yang memeriksa lock.
- Efek samping di callback `UpdateAsync`. Callback bisa dijalankan ulang. Jangan memberi item atau memanggil remote di dalamnya. Lakukan setelah `update` selesai.
- Retry untuk error permanen. Mencoba ulang "must publish" dengan jeda 1+2+4 detik membuat setiap pemain menunggu 7 detik sebelum bisa bermain, dan Output penuh warning. Cukup sekali, lalu store dimatikan untuk server ini.
- Save di setiap perubahan. Kena batas request lalu request dibuang. Simpan saat keluar, berkala, dan saat shutdown.
- Studio memakai data asli. Kalau place sudah dipublish dan akses API dinyalakan, tes di Studio membaca dan menulis data pemain sungguhan. Untuk tes, pakai place terpisah.
- Tes yang lolos tapi tidak menguji apa-apa. Versi pertama tes rejoin cepat tetap lolos walaupun mutex dimatikan, karena hook memperlambat semua request sama rata sehingga urutannya tidak pernah tertukar. Tesnya diperbaiki supaya hanya request `unload` yang lambat. Baru setelah itu versi tanpa mutex gagal.

## 5. Bukti tes

Sinkron: `SYNC OK 10 script` (checksum FNV-1a, `Store` ikut terhitung).

### Probe sebelum menulis kode (datamodel Edit)

`DataStoreService:GetDataStore("PlayerData")` di place ini: `pcall` gagal dengan `You must publish this place to the web to access DataStore.` Frasa "must publish this place" dipakai untuk mengenali error permanen (terbukti). Pola kedua di `isPermanent`, `StudioAccessToApisNotAllowed`, diambil dari dokumentasi dan belum pernah muncul di sini, jadi masih dugaan.

Polanya sengaja sempit. Salah mengenali error sementara sebagai permanen mematikan store untuk seluruh server, termasuk save dan pelepasan lock pemain yang sudah termuat. Salah ke arah sebaliknya hanya membuang 7 detik retry. Versi awal juga mencocokkan `403` di mana saja dalam pesan. Itu dibuang saat review karena angka itu bisa muncul di pesan apa pun, dan tes 17 memastikan `403: Forbidden` sekarang di-retry, bukan mematikan store.

### Tes unit (memory store, dua `PlayerData` = dua server, jam dan `wait` palsu)

Hasil: `SEMUA LULUS 47 cek`.

1. Masuk, ubah (Coins 7, beli SpeedBoots), keluar: rekaman berisi Coins 2 + SpeedBoots, `schema` 1, lock kosong. Server B memuat pemain yang sama: Coins 2 + SpeedBoots, membeli SpeedBoots lagi `AlreadyOwned`.
2. Lock aktif: server B mendapat `Locked` setelah menunggu 1, 2, 4, data default, `save` false. Setelah B menambah 50 koin, `save`, `saveAll`, `unload`, `closeAll`, JSON store byte-identik. Server A tetap bisa save (Coins 8, lock milik A).
3. Lease: pada detik ke-299 B masih `Locked`. Pada detik ke-301 B mengambil alih dan mendapat Coins 5. Save dari A setelah itu `false`, status A jadi `Locked`, JSON tidak berubah walaupun A menambah koin lalu `saveAll` dan `unload`.
4. Error "must publish": status `Offline`, tanpa retry, pemain kedua tidak memanggil store sama sekali (total panggilan 1), warning tepat 1x, koin tetap bisa bertambah di memori, tidak ada yang tertulis.
5. Dua kali `502` lalu sukses: `Ok`, menunggu 1 lalu 2.
6. Empat kali `502`: `Error`, menunggu 1, 2, 4, satu log "gagal memuat", tidak ada yang tertulis.
7. Save dengan satu `502`: retry, tersimpan.
8. Aliasing: setelah save Coins 3, menambah 100 di sesi tidak mengubah store.
9. Keluar saat load berjalan: tidak ada sesi, lock dilepas.
10. Rejoin cepat saat save `unload` lambat: pembelian saat `unload` berjalan `NotLoaded`; load kedua menunggu dan mendapat Coins 9; save berikutnya tersimpan (Coins 10, lock milik sesi ini).
11. Rekaman `schema = 99`: `Error`, data default, JSON byte-identik setelah keluar.
12. Rekaman tanpa `Inventory` terisi kosong. Rekaman rusak (`Coins = "banyak"`, `SpeedBoots = "ya"`) jadi Coins 0 dan hanya `JumpCoil` yang dipertahankan. Pembelian tetap jalan.
13. `closeAll` dengan 3 pemain: semua tersimpan, lock dilepas, sesi hilang.
14. `saveAll` (autosave) memperpanjang lock: `lock.at` ikut jam palsu (110).
15. Tanpa store: load langsung tanpa yield, `onChanged` 1x, `save` false.
16. `Store.datastore` dengan service palsu: `GetDataStore` belum dipanggil saat dibuat; error-nya diteruskan ke pemanggil; setelah sukses dicache (2 panggilan untuk 3 update).
17. Empat kali `403: Forbidden`: di-retry 1, 2, 4 lalu `Error`, store tidak dimatikan.

Tes mutasi untuk kasus 10: `_lockKey` dimatikan di satu instance. Hasil: load kedua Coins 0, `save` false, lock di store hilang. Dengan mutex: Coins 9, `save` true, lock milik sesi. Jadi tes 10 memang menangkap bug ini.

Suite Hari 3 dijalankan ulang: `SEMUA LULUS 36 cek` (`PlayerData.new()` tanpa store masih sinkron).

### Tes integrasi jalur `Ok` (Player asli, cermin asli, memory store)

Semua tes unit memakai pemain palsu tanpa cermin, dan game live selalu `Offline`. Untuk menutup celah itu, saat Play di datamodel Server dibuat `PlayerData` baru dengan memory store yang sudah diisi `{ Coins = 33, Inventory = { GoldCrown = true } }` untuk key pemain asli, `onChanged = StatsMirror.sync`, dan `onStatus` yang menulis atribut. Hasil:

- Sebelum: Coins 0, `DataStatus = Offline`, tidak ada BoolValue GoldCrown.
- Setelah `load`: `leaderstats.Coins` 33, BoolValue `GoldCrown` true, `DataStatus = Ok`, lock milik sesi tes.
- Setelah `addCoins(2)`: cermin 35.
- Setelah `unload`: store berisi Coins 35 + GoldCrown, lock dilepas.

### Tes live (DataStore asli, place belum dipublish)

1. Play: Output berisi tepat satu baris `[PlayerData] DataStore tidak tersedia, progres di server ini tidak disimpan: You must publish this place to the web to access DataStore.` Atribut pemain `DataStatus = Offline`, leaderstats ada.
2. Pickup nyata sampai 6 koin (6,9 detik), tekan J lalu L: Coins 1, `Inventory` berisi `SpeedBoots`, Output `Berhasil membeli Sepatu Kilat` dan `Koin belum cukup untuk Mahkota Emas`. Sama dengan Hari 2 dan 3.
3. Restart Play, lalu tes tamper dan argumen aneh Hari 2 dari client: Coins diubah lokal jadi 999 lalu minta GoldCrown dibalas `NotEnoughCoins`; dari 10 argumen aneh hanya `("GoldCrown", 0)` yang dibalas (`NotEnoughCoins`). Server tetap Coins 0, Inventory kosong. Sama dengan Hari 2 dan 3. Tes spam 50x tidak diulang live (logika `Shop` tidak berubah dan sudah tercakup suite Hari 3).
4. Stop: tidak ada error baru di Output. Di mode `Offline`, `closeAll` dan `unload` tidak menyimpan apa-apa, jadi ini hanya membuktikan Stop tidak error, bukan bahwa `BindToClose` menyimpan data.
5. Gate statis: `selene src` 0 error 0 warning, `stylua --check src` lolos.

### Yang belum bisa dites di place ini

- Jalur sukses `Store.datastore` dengan DataStore asli (`UpdateAsync` sungguhan, data tetap ada setelah Stop lalu Play lagi). Butuh place yang dipublish dengan akses API Studio dinyalakan.
- Lock antar dua server sungguhan dan perilaku throttle. Yang dites adalah logikanya dengan dua instance `PlayerData` di satu server.
- `BindToClose` yang benar-benar menyimpan saat server mati. Di sini sesi `Offline`, jadi tidak ada yang disimpan. Logika `closeAll` dites di unit (kasus 13), tapi sambungan `BindToClose -> closeAll` dan urutan `PlayerRemoving -> unload` di perakit baru dicek dengan membaca kode.

## 6. Latihan mandiri

1. Tambahkan field `Level` (default 1) ke data pemain. Apa saja yang harus diubah supaya pemain yang datanya sudah tersimpan tetap termuat dengan benar? Apakah `SCHEMA` perlu naik?
   Petunjuk: lihat `defaultData` dan `reconcile`.
2. Tulis tes dengan memory store: setelah error "must publish", `saveAll` dan `closeAll` tidak menulis apa pun.
   Petunjuk: `mem:failNext(1, "You must publish this place to the web to access DataStore.")`, lalu cek `mem.calls` dan `mem:raw(key)`.
3. Di `unload`, kenapa sesi dihapus dari memori sebelum save, bukan sesudahnya?
   Petunjuk: pikirkan request beli yang datang saat save masih menunggu jaringan.

<details>
<summary>Kunci jawaban</summary>

1. Tambahkan `Level = 1` di `defaultData`, dan di `reconcile` salin `saved.Level` kalau tipenya number. Data lama yang belum punya `Level` otomatis mendapat 1. `SCHEMA` tidak perlu naik, karena field baru yang punya default bisa diisi oleh `reconcile`. Naikkan `SCHEMA` kalau arti data lama berubah (misalnya `Coins` dipecah jadi dua mata uang) dan perlu fungsi migrasi.
2. ```lua
   local S = game.ServerScriptService.Server
   local Store = require(S.Store)
   local PlayerData = require(S.PlayerData)
   local mem = Store.memory()
   mem:failNext(1, "You must publish this place to the web to access DataStore.")
   local pd = PlayerData.new({ store = mem, log = function() end, wait = function() end })
   local p = { UserId = 777, Name = "Tes" }
   pd:load(p)
   pd:addCoins(p, 10)
   pd:saveAll()
   pd:closeAll()
   return mem.calls == 1 and mem:raw("Player_777") == nil
   ```
   `calls == 1` adalah panggilan load yang gagal. Tidak ada panggilan lain.
3. Kalau sesi dihapus sesudah save, ada jeda saat save menunggu jaringan. Pembelian yang datang di jeda itu masih diterima dan mengubah data di memori. Apakah perubahan itu ikut tersimpan tergantung kapan callback `UpdateAsync` dijalankan dibanding pembelian tersebut: bisa ikut, bisa hilang. Perilaku yang bergantung pada waktu jaringan seperti itu sulit dites dan sulit dilacak saat ada laporan "item saya hilang". Dengan menghapus sesi lebih dulu, request terlambat selalu ditolak `NotLoaded` dan yang disimpan pasti keadaan akhir.

</details>
