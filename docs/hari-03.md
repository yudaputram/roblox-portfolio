# Hari 3: ModuleScript dan OOP (refactor)

File baru: `src/server/PlayerData.luau`, `Inventory.luau`, `Shop.luau`, `CoinPickup.luau`, `StatsMirror.luau`. Diubah: `src/server/init.server.luau` (jadi perakit saja), `src/shared/Config.luau` (tambah `Coin`). Client tidak diubah.

## 1. Tujuan

Script server Hari 2 sudah 143 baris dan mencampur semuanya: leaderstats, koin, rate limit, toko. Hari ini kodenya dipecah per tanggung jawab tanpa mengubah apa yang dirasakan pemain. Tes Hari 1 dan 2 dijalankan ulang untuk membuktikannya.

Analogi Laravel: `init.server.luau` sekarang seperti `routes/web.php` + service provider. Isinya cuma "remote ini disambungkan ke handler itu". Logikanya pindah ke kelas-kelas seperti service di `app/Services`. `PlayerData` mirip model + repository: satu-satunya tempat yang boleh mengubah data pemain.

Ada satu perubahan yang disengaja: `leaderstats.Coins` (IntValue) bukan lagi sumber kebenaran. Sumber kebenarannya table data di `PlayerData`, dan IntValue hanya cermin untuk ditampilkan. Pemain tidak merasakan bedanya, tapi kode server sekarang tidak pernah membaca IntValue untuk mengambil keputusan.

## 2. Konsep inti

### ModuleScript dan `require`

File `.luau` biasa jadi `ModuleScript`. Isinya dijalankan sekali saat `require` pertama, hasilnya di-cache, dan `require` berikutnya dari konteks yang sama mendapat table yang sama. Karena itu modul di sini tidak melakukan apa-apa saat di-`require` (tidak membuat Part, tidak connect event). Semua efek samping ada di method `start()`/`connect()` yang dipanggil perakit. Hasilnya: modul bisa di-`require` dari tes tanpa ikut menjalankan game kedua.

Fakta yang ditemukan saat menyiapkan tes (sudah dibuktikan dengan probe): kode yang dijalankan lewat MCP `execute_luau` punya cache `require` sendiri, terpisah dari script game. Jadi tes tidak bisa mengintip instance `PlayerData` milik game yang sedang jalan. Tes membuat instance baru sendiri, dan bukti bahwa perakitannya benar datang dari tes live lewat remote.

### OOP dengan metatable

Luau tidak punya `class`. Polanya:

```lua
local Inventory = {}
Inventory.__index = Inventory -- kalau field tidak ada di objek, cari di table Inventory

function Inventory.new(owned)
    return setmetatable({ _owned = owned }, Inventory)
end

function Inventory:has(itemId) -- titik dua = parameter self otomatis
    return self._owned[itemId] == true
end

local inv = Inventory.new({})
inv:has("SpeedBoots") -- sama dengan Inventory.has(inv, "SpeedBoots")
```

`__index` itu mirip prototype di JavaScript. `obj:method()` sama dengan `obj.method(obj)`, persis seperti `$this` yang diisi otomatis.

Kalau kamu buka `Inventory.luau`, method-nya ditulis `function Inventory.has(self: Inventory, itemId)`. Itu sama persis dengan `function Inventory:has(itemId)`; bedanya `self` ditulis eksplisit supaya bisa diberi tipe `Inventory`. Modul lain memakai bentuk titik dua yang lebih ringkas. Dua-duanya dipanggil dengan `inv:has(...)`.

Awalan `_` (`_owned`, `_sessions`) cuma konvensi "jangan disentuh dari luar". Luau tidak punya `private`.

### Dependency injection sederhana

`Shop.new(playerData)` dan `CoinPickup.new(playerData)` menerima `PlayerData` dari luar, tidak membuatnya sendiri. Di game, perakit memberi instance asli. Di tes, kita bisa memberi instance baru yang kosong. Sama seperti constructor injection di Laravel.

## 3. Penjelasan kode

### `PlayerData`: satu pintu untuk mengubah data

Data per pemain berupa table polos `{ Coins = 0, Inventory = { SpeedBoots = true } }`. Sengaja polos (tanpa Instance, tanpa metatable) supaya besok bisa langsung disimpan ke DataStore.

Method yang mengubah data (`load`, `addCoins`, `purchase`) memanggil `onChanged(player, data)` setelah selesai. Perakit mengisi `onChanged` dengan `StatsMirror.sync`, jadi leaderstats selalu ikut. Di tes, `onChanged` diisi fungsi pencatat (spy) untuk menghitung berapa kali dipanggil.

`purchase(player, itemId, price)` mengerjakan cek "sudah punya", cek koin, potong koin, tambah item, lalu memanggil `onChanged` satu kali. Kenapa tidak dipecah jadi `spendCoins` + `addItem` yang dipanggil `Shop`? Karena kalau dipecah, ada dua tempat yang bisa lupa memberi tahu cermin, dan ada celah di antara dua panggilan. Satu method tanpa yield = satu transaksi utuh.

`get(player)` mengembalikan data untuk dibaca. Semua perubahan tetap lewat method supaya cermin tidak ketinggalan.

### `Inventory`: kelas di atas set

`Inventory.new(data.Inventory)` tidak menyalin table, tapi membungkusnya. `inv:add("A")` menulis langsung ke `data.Inventory`. Jadi kelasnya memberi method yang enak dipakai (`has`, `add`, `list`), sementara datanya tetap table polos yang bisa disimpan.

### `StatsMirror`: cermin, bukan sumber

`sync` membuat `leaderstats`/`Inventory` kalau belum ada (Parent paling akhir, sama seperti Hari 1), lalu menyamakan nilainya dengan data. Ini satu-satunya kode yang menulis ke IntValue/BoolValue.

### `Shop`: validasi, lalu serahkan ke `PlayerData`

`shop:buy(player, itemId)` mengembalikan `(berhasil, alasan)`: `RateLimited`, `BadType`, `UnknownItem`, `NotLoaded`, `AlreadyOwned`, `NotEnoughCoins`, atau `Ok`. Nilai balik ini yang membuat validasi bisa dites satu per satu tanpa remote. `shop:connect(buyItem, buyResult)` menyambungkan remote dan hanya membalas tiga alasan yang wajar dialami pemain jujur, sama seperti Hari 2.

`NotLoaded` baru: request yang datang sebelum data pemain siap (misalnya klik sangat cepat saat baru masuk) ditolak dengan rapi, bukan error.

### `CoinPickup`: aturan dipisah dari event

`collect(player)` berisi aturan (cooldown, data harus termuat, tambah koin). Handler `Touched` hanya mencari pemain lalu memanggil `collect`. Dengan begitu aturan cooldown bisa dites tanpa menggerakkan karakter.

### Perakit dan pembersihan

`PlayerRemoving` di perakit memanggil `unload`, `shop:removePlayer`, dan `coinPickup:removePlayer`. Waktu kodenya masih satu file, satu handler membersihkan dua table sekaligus. Setelah dipecah, tiap modul yang menyimpan table per pemain punya `removePlayer` sendiri, dan perakit wajib memanggil semuanya. Kebocoran di sini tidak kelihatan di tes solo. Unit test membuktikan kedua `removePlayer` bekerja, tapi bahwa perakit benar-benar memanggilnya saat pemain keluar baru dicek dengan membaca kode, belum dijalankan (keluar dari Play solo menutup seluruh sesi).

## 4. Jebakan umum

- Modul dengan efek samping saat `require`. Kalau `Shop.luau` langsung connect remote di level atas, setiap `require` dari tes atau modul lain bisa menyambung handler kedua. Taruh efek samping di method yang dipanggil sekali oleh perakit.
- Membaca nilai dari cermin. Setelah refactor, kode server yang membaca `leaderstats.Coins.Value` untuk mengambil keputusan adalah bug: nilainya bisa diubah siapa saja di server (plugin, admin script) tanpa lewat `PlayerData`. Tes "tamper cermin" di bawah membuktikan server tidak tertipu.
- `require` siklik. Kalau `PlayerData` me-`require` `Shop` dan `Shop` me-`require` `PlayerData`, Luau error. Arah ketergantungan di sini satu arah: `Shop` dan `CoinPickup` bergantung pada `PlayerData`, tidak sebaliknya.
- Titik dan titik dua tertukar. `Inventory.has("SpeedBoots")` (titik, tanpa objek) membuat string `"SpeedBoots"` jadi `self` dan `itemId` jadi nil. Hasil nyata di Studio: `attempt to index nil with nil`. `Inventory.add("SpeedBoots")` malah error `attempt to call missing method 'has' of string`. Kalau melihat error aneh seperti itu, cek dulu titik vs titik dua.

## 5. Bukti tes

Sinkron dicek dengan checksum: snippet membandingkan panjang dan hash FNV-1a dari `Source` tiap script di Studio dengan byte file repo. Hasil: `SYNC OK 9 script`.

### Tes unit (instance modul baru di datamodel Server saat Play, pemain palsu `{ UserId, Name }`)

Hasil: `SEMUA LULUS 36 cek`. Yang penting:

- `Inventory`: add pertama true, kedua false, `list` terurut, dan table data aslinya ikut berubah.
- `PlayerData`: sebelum `load`, `get` nil, `addCoins` false, `purchase` = `NotLoaded`. `load` memanggil `onChanged` sekali dengan Coins 0. `purchase` sukses memanggil `onChanged` tepat sekali dengan data akhir (Coins 2). `AlreadyOwned` tidak memanggil `onChanged`. `NotEnoughCoins` tidak mengubah koin.
- `Shop` (pemain palsu baru per kasus supaya bucket tidak saling ganggu): sebelum load `NotLoaded`; `nil`, angka, `NaN`, table, Instance = `BadType`; item palsu dan string 10.000 huruf = `UnknownItem`; koin 10 untuk GoldCrown = `NotEnoughCoins`; koin 15 untuk JumpCoil = `Ok`.
- Spam 50x `JumpCoil` dengan koin 40: `Ok` 1, `AlreadyOwned` 4, `RateLimited` 45, koin jadi 25.
- Pembersihan: bucket ada lalu hilang setelah `shop:removePlayer`; cooldown koin ada lalu hilang setelah `coinPickup:removePlayer`. Pemanggilan keduanya dari `PlayerRemoving` di perakit hanya dicek dengan membaca kode.
- `CoinPickup`: sebelum load false, pertama true, saat cooldown false, setelah 1,1 detik true lagi.

### Tes live (end-to-end lewat remote asli, sesi Play yang sama)

Angka dibandingkan dengan hasil Hari 2.

1. Pickup nyata sampai 6 koin (6,9 detik), tekan J lalu L. Client melihat Coins 1 dan `Inventory` berisi `SpeedBoots`; Output `Berhasil membeli Sepatu Kilat`, `Koin belum cukup untuk Mahkota Emas`. Sama dengan Hari 2.
2. Client menulis Coins 999 lalu minta GoldCrown: `NotEnoughCoins`. Sama.
3. 10 argumen aneh dengan jeda 1,1 detik: hanya `("GoldCrown", 0)` yang dibalas (`NotEnoughCoins`). Sama.
4. Dana untuk spam dari pickup nyata, bukan diset server: 1 jadi 22 (25,4 detik) lalu 22 jadi 40 (21,8 detik). Spam 50x `JumpCoil`: 5 balasan (`Ok` x1, `AlreadyOwned` x4), Coins 25, satu BoolValue `JumpCoil`. Request 2 detik kemudian tetap dibalas. Sama.
5. Baru: tamper cermin dari server. Server menulis `leaderstats.Coins.Value = 999`, lalu client minta GoldCrown (harga 50). Balasan `NotEnoughCoins`, GoldCrown tidak dimiliki. Setelah satu pickup nyata, cermin kembali ke nilai asli + 1 = 26 (bukan 1000).
6. Output tanpa error baru. Gate statis: `selene src` 0 error 0 warning, `stylua --check src` lolos.

## 6. Latihan mandiri

1. Tambahkan method `PlayerData:getCoins(player): number?` dan pakai di tempat yang cocok. Apakah ada kode server yang sekarang butuh?
   Petunjuk: cari pemakaian `get(player).Coins`.
2. Tambahkan method `Inventory:count(): number` dan tulis tes kecil untuknya di `execute_luau`.
   Petunjuk: `Inventory.new({ A = true, B = true }):count()` harus 2.
3. Buat modul `Leaderboard` yang mencetak 3 pemain dengan koin terbanyak tiap 30 detik. Modul ini butuh apa dari `PlayerData`, dan di mana `start()`-nya dipanggil?
   Petunjuk: jangan baca `leaderstats`.

<details>
<summary>Kunci jawaban</summary>

1. ```lua
   function PlayerData:getCoins(player: Player): number?
       local data = self:get(player)
       return data and data.Coins
   end
   ```
   Saat ini belum ada kode server yang butuh, karena keputusan koin ada di dalam `purchase` dan `addCoins`. Method ini berguna nanti untuk sistem lain (ronde, UI admin). Menambah method yang belum dipakai boleh untuk latihan, tapi di proyek nyata tunggu sampai ada pemakainya.
2. ```lua
   function Inventory.count(self: Inventory): number
       local n = 0
       for _ in self._owned do
           n += 1
       end
       return n
   end
   ```
   Tes: `local inv = require(game.ServerScriptService.Server.Inventory).new({ A = true, B = true }); return inv:count() == 2`. Jalankan saat Play supaya `require` mengambil versi terbaru.
3. Modul butuh daftar pemain beserta koinnya. Tambahkan method di `PlayerData` yang mengembalikan pasangan `(player, coins)`, misalnya `PlayerData:each(callback)`. `Leaderboard.new(playerData)` dibuat dan `start()`-nya dipanggil di `init.server.luau`, sama seperti `CoinPickup`. Loop-nya `while true do task.wait(30) ... end` di dalam `task.spawn`, supaya `start()` tidak memblokir perakit.

</details>
