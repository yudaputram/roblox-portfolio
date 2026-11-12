# Hari 6: Monetisasi (gamepass dan developer product)

File baru: `src/server/Monetization.luau`. Diubah: `src/shared/Config.luau` (ID gamepass dan product), `src/server/PlayerData.luau` (schema 2, `Receipts`, `grantPurchase`), `src/server/CoinPickup.luau` (pengali hadiah), `src/server/init.server.luau` (pasang `ProcessReceipt` dan event gamepass). Client tidak diubah.

## 1. Tujuan

Dua cara menjual sesuatu dengan Robux:

- Gamepass "2x Koin": dibeli sekali, berlaku selamanya. Pemiliknya mendapat 2 koin per pickup.
- Developer product "+100 Koin": bisa dibeli berkali-kali. Setiap pembelian menambah 100 koin.

Hari ini belum ada tombol beli di game. Yang dikerjakan sisi server: setiap pembelian harus diberikan tepat satu kali, walaupun save gagal, server mati, atau Roblox mengirim receipt yang sama dua kali.

Analogi Laravel/JS:

- `ProcessReceipt` mirip webhook pembayaran (Midtrans, Stripe). Roblox memanggil server dengan receipt, lalu server menjawab `PurchaseGranted` (seperti HTTP 200, "sudah diproses") atau `NotProcessedYet` (seperti 5xx, "kirim lagi nanti").
- Webhook bisa datang lebih dari sekali, jadi handler yang benar mencatat idempotency key di database dalam transaksi yang sama dengan perubahan saldo. Di sini idempotency key-nya `PurchaseId`, dan "transaksi yang sama" artinya satu tulisan `UpdateAsync` yang berisi koin dan `PurchaseId` sekaligus.
- Bedanya dengan webhook biasa: Roblox tidak mengirim ulang berdasarkan waktu (lihat bagian 2).
- Cek gamepass mirip cek langganan aktif saat login, lalu hasilnya disimpan di session.
- ID bernilai 0 di `Config` mirip nilai `.env` yang masih kosong karena produknya belum dibuat di dashboard.

Place ini belum dipublish, jadi belum ada gamepass dan product sungguhan. Semua logika dites dengan receipt palsu, pemain palsu, dan fungsi Roblox yang disuntik.

## 2. Konsep inti

### Gamepass dan developer product

| | Gamepass | Developer product |
|---|---|---|
| Dibeli | Sekali | Berkali-kali |
| Siapa yang mencatat | Roblox (kepemilikan) | Kamu sendiri (apa yang sudah diberikan) |
| Cara cek | `UserOwnsGamePassAsync` | Callback `ProcessReceipt` |
| Kalau kode salah | Pemain tidak dapat 2x | Pemain dapat dobel, atau bayar tapi tidak dapat apa-apa |

### Siklus receipt

Kutipan berikut dari dokumentasi `MarketplaceService`, bukan hasil pengamatan di place ini (place belum dipublish):

- "`ProcessReceipt` has no time-based retry mechanism." Setelah jawaban `NotProcessedYet`, callback hanya dipanggil lagi kalau pemain memulai pembelian product lain, atau masuk ulang ke server mana pun di experience ini.
- Callback boleh yield selama server hidup, dan jawabannya tetap diterima.
- "If you don't implement a `ProcessReceipt` callback, your receipts will be auto-acknowledged. You can't get a receipt back after it has been acknowledged."
- Callback untuk satu pembelian bisa berjalan di dua server sekaligus kalau pemain pindah server sebelum callback di server pertama selesai.
- Jawaban `PurchaseGranted` pun bisa gagal tercatat di backend Roblox. Pembelian itu tetap belum selesai dan receipt yang sama akan datang lagi.

Akibatnya untuk kode:

1. Catatan "PurchaseId ini sudah diberikan" harus tersimpan di DataStore, bukan hanya di memori server. Receipt yang sama bisa datang lagi di server lain atau setelah pemain masuk ulang.
2. Koin dan `PurchaseId` harus masuk di tulisan yang sama. Kalau dicatat di dua tempat, server yang mati di antara dua tulisan meninggalkan koin tanpa catatan (nanti diberikan lagi) atau catatan tanpa koin (pemain bayar, tidak dapat apa-apa).
3. `PurchaseGranted` hanya boleh dijawab setelah tulisan itu berhasil.

### Aturan jawaban

`PurchaseGranted` hanya kalau koin dan `PurchaseId` sudah tersimpan di DataStore. Selain itu `NotProcessedYet`:

- `ProductId` tidak ada di `Config.Products`.
- Pembeli tidak ada di server ini.
- Data pemain belum termuat setelah ditunggu 60 detik, atau pemain keluar saat ditunggu.
- Sesi pemain tidak disimpan (`Offline`, `Locked`, `Error` dari Hari 4).
- Save gagal.

Dua server yang menerima receipt yang sama tidak bisa sama-sama memberi. Session lock Hari 4 hanya mengizinkan server pemegang lock menulis rekaman pemain itu. Server lain mendapat sesi `Locked`, jadi menjawab `NotProcessedYet` (tes R11).

### Schema 2

`Receipts` adalah field baru di data pemain, dan `SCHEMA` naik dari 1 ke 2. Latihan Hari 4 bilang field baru yang punya default tidak perlu menaikkan `SCHEMA`. Itu benar kalau semua server sudah memakai kode baru. Setelah publish, server lama masih hidup beberapa saat. Server lama tidak mengenal `Receipts`, jadi `reconcile`-nya membuang field itu dan save berikutnya menulis data tanpa `Receipts`. Catatan pembelian hilang, dan receipt yang datang lagi akan diberikan kedua kalinya.

Dengan `SCHEMA = 2`, server lama melihat rekaman schema 2 sebagai "lebih baru dari kode saya", memberi status `Error`, dan tidak menulis apa pun (aturan yang sama dengan tes 11 Hari 4). Data v1 tetap terbaca oleh server baru: `reconcile` mengisi `Receipts` kosong.

Nomor schema baru ditulis saat data ditulis (`_write`), bukan saat lock diambil (`_claim`). Nomor itu menyatakan bentuk data di rekaman. Kalau pemain keluar saat load masih berjalan, lock dilepas tanpa menulis data. Rekamannya tetap data v1, jadi tetap berlabel 1, dan server lama masih bisa membacanya kalau versi baru ditarik sebelum data pemain itu ditulis ulang (tes S3).

### Gamepass: cek saat masuk, cache satu arah

- `UserOwnsGamePassAsync` adalah request jaringan: bisa yield dan bisa gagal. Dipanggil di `pcall`, dicoba lagi setelah 1, 2, 4 detik, lalu menyerah dengan satu warning. Kalau gagal, pemain mendapat pengali 1, bukan error.
- Hasil disimpan di cache per pemain. Pickup hanya membaca cache, tidak menunggu jaringan.
- Cache hanya pernah diisi `true`. Cek saat masuk bisa berjalan lama (retry). Kalau pemain membeli gamepass di tengah cek itu, `PromptGamePassPurchaseFinished` mengisi `true`, lalu cek lama selesai dengan jawaban `false`. Kalau `false` ikut ditulis, pembelian itu terhapus dari cache (tes G7).
- Kalau pemain keluar saat cek berjalan, hasil cek dibuang (token di `_checking`), supaya tidak ada sisa data untuk pemain yang sudah pergi.
- ID 0 (belum publish): cek dilewati, pengali 1.

## 3. Penjelasan kode

### `Config`

```lua
-- ID dibuat di Creator Dashboard setelah place dipublish. 0 = belum ada.
GamePasses = table.freeze({
    DoubleCoins = 0, -- "2x Koin": isi setelah publish
}),
Products = table.freeze({
    Coins100 = table.freeze({ Id = 0, Coins = 100 }), -- "+100 Koin": isi setelah publish
}),
```

Jumlah koin per product ada di `Config`, bukan di kode `ProcessReceipt`. Product baru cukup menambah satu baris.

### `PlayerData:grantPurchase`

```lua
function PlayerData:grantPurchase(player: Player, purchaseId: string, coins: number): boolean
    local session = self._sessions[player]
    if not session or not session.persisted then
        return false -- belum termuat, atau sesi ini memang tidak disimpan
    end
    if not session.data.Receipts[purchaseId] then
        session.data.Receipts[purchaseId] = true
        session.data.Coins += coins
        self:_notify(player, session)
    end
    return self:save(player)
end
```

- Antara cek `Receipts[purchaseId]` dan pengisiannya tidak ada yield. Luau di satu server tidak menjalankan dua thread bersamaan, jadi dua panggilan untuk receipt yang sama tidak bisa sama-sama lolos cek.
- `save` dipanggil walaupun `PurchaseId` sudah tercatat. Bisa jadi panggilan sebelumnya mencatat di memori tapi save-nya gagal, lalu Roblox mengirim receipt itu lagi. Jawaban yang benar bergantung pada apakah catatan itu sekarang sudah tersimpan, bukan apakah sudah ada di memori (tes R7).
- Kalau receipt yang sama datang lagi saat save pertama masih berjalan, panggilan kedua tidak menambah koin, lalu `save`-nya menunggu save pertama lewat `_lockKey` (Hari 4) dan menulis keadaan yang sama. Keduanya `PurchaseGranted`, koin bertambah sekali (tes R14).
- Sesi yang tidak `persisted` langsung `false`. Memberi koin yang tidak akan tersimpan lalu menjawab `PurchaseGranted` sama dengan menerima uang tanpa mengirim barang.

### `Monetization:processReceipt`

```lua
function Monetization:processReceipt(info): Enum.ProductPurchaseDecision
    local notYet = Enum.ProductPurchaseDecision.NotProcessedYet
    local product = findProduct(info.ProductId)
    if not product then
        self._log("[Monetization] ProductId tidak dikenal: " .. tostring(info.ProductId))
        return notYet
    end
    local player = self._getPlayer(info.PlayerId)
    if not player then
        return notYet -- pembeli tidak ada di server ini
    end
    local waited = 0
    while not self._playerData:get(player) do
        if waited >= self._loadTimeout or self._getPlayer(info.PlayerId) ~= player then
            return notYet
        end
        self._wait(POLL_SECONDS)
        waited += POLL_SECONDS
    end
    if self._playerData:grantPurchase(player, info.PurchaseId, product.Coins) then
        return Enum.ProductPurchaseDecision.PurchaseGranted
    end
    return notYet
end
```

Brief Hari 6 meminta "pemain belum termuat → NotProcessedYet". Kode ini menunggu dulu sampai 60 detik, baru menjawab `NotProcessedYet`. Alasannya kutipan dokumentasi di bagian 2: tidak ada retry berdasarkan waktu. Receipt pembelian yang tertunda biasanya datang tepat saat pemain masuk, saat data masih dimuat. Kalau langsung dijawab `NotProcessedYet`, pembelian itu menggantung sampai pemain membeli lagi atau masuk ulang. Callback boleh yield, jadi menunggu aman. Perilaku di batas tetap sesuai brief: tidak termuat sampai batas waktu, atau pemain keluar saat ditunggu, jawabannya `NotProcessedYet` (tes R5 dan R13).

`getPlayer`, `wait`, `ownsPass`, dan `log` bisa disuntik lewat `Monetization.new(playerData, options)`, sama seperti `PlayerData` di Hari 4. Tes memakai `wait` palsu, jadi menunggu 60 detik tidak benar-benar ditunggu.

### Perakit

```lua
local monetization = Monetization.new(playerData)
-- Dipasang sebelum apa pun yang bisa yield. Tanpa callback, Roblox menganggap receipt
-- sudah diproses, dan pembelian itu tidak bisa diberikan lagi.
MarketplaceService.ProcessReceipt = function(info)
    return monetization:processReceipt(info)
end
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
    monetization:onPassPurchased(player, passId, wasPurchased)
end)

local coinPickup = CoinPickup.new(playerData, function(player: Player)
    return monetization:coinMultiplier(player)
end)
```

- `ProcessReceipt` dipasang di bagian atas script, sebelum ada yang yield. Pemain yang masuk dengan pembelian tertunda tidak boleh sempat kena auto-acknowledge.
- `checkPass` dijalankan dengan `task.spawn` saat pemain masuk, supaya `playerData:load` tidak ikut menunggu jawaban gamepass.
- `monetization:removePlayer` ditambahkan ke `PlayerRemoving`, sesuai aturan Hari 3: setiap modul yang menyimpan data per pemain dibersihkan di sana.
- `CoinPickup.new` menerima pengali sebagai fungsi opsional. Tanpa itu pengalinya 1, jadi tes Hari 3 yang memanggil `CoinPickup.new(pd)` tetap jalan tanpa diubah.

## 4. Jebakan dan celah yang ditutup

- Menjawab `PurchaseGranted` sebelum save berhasil. Kalau server mati setelah itu, Roblox menganggap pembelian selesai, padahal koinnya tidak pernah tersimpan. Pemain kehilangan Robux. Di sini jawaban mengikuti hasil `save` (mutasi M2 membuktikan tes menangkapnya).
- Cek idempotensi hanya di memori (`local granted = {}`). Receipt yang sama datang lagi di server lain atau setelah masuk ulang dan diberikan lagi. Di sini catatannya ada di rekaman DataStore (tes R8: receipt dikirim ulang di server B tidak dobel).
- Lupa memasang `ProcessReceipt`, atau memasangnya setelah `WaitForChild` atau load yang yield. Receipt yang masuk di jeda itu di-auto-acknowledge dan hilang.
- Mempercayai client. Client bisa memanggil event-nya sendiri dan mengirim remote apa pun. Tidak ada remote "saya sudah beli" di kode ini. `PromptGamePassPurchaseFinished` didengarkan di server, dan dokumentasi juga menyarankan event itu hanya didengarkan di server.
- Menulis `false` ke cache gamepass. Cek lama yang selesai setelah pemain membeli menghapus pembelian itu dari cache (mutasi M3).
- Server lama setelah publish. Setelah versi ini dipublish, server versi lama yang masih hidup memberi status `Error` ke pemain yang datanya sudah schema 2. Pemain itu bermain tanpa simpan. Setelah publish, restart server versi lama lewat Creator Dashboard (langkah ini belum dicoba di kurikulum ini, karena place belum dipublish).
- Mencoba membaca `MarketplaceService.ProcessReceipt` dari script lain untuk memastikan sudah terpasang. Hasilnya error `ProcessReceipt is a callback member of MarketplaceService; you can only set the callback value, get is not available` (terjadi saat probe tes live hari ini). Pemasangannya hanya bisa dipastikan dengan membaca kode.
- `Receipts` tumbuh satu entri per pembelian dan tidak pernah dipangkas. Perkiraan kasar, belum diukur: satu entri sekitar 50 byte JSON (`PurchaseId` berupa string panjang ditambah `:true`), jadi batas 4 MB per key baru tercapai setelah puluhan ribu pembelian. Ditandai `shortcut:` di kode.
- Gamepass yang dibeli di website saat pemain sedang di server. Cache di sini hanya diisi saat masuk dan dari `PromptGamePassPurchaseFinished`, jadi pemain itu baru mendapat 2x setelah masuk ulang. Belum ditangani.
- `BindReceiptHandler` adalah API yang lebih baru untuk developer product. Kalau ada handler terpasang yang cocok, handler itu didahulukan dan `ProcessReceipt` tidak dipanggil. Kalau suatu hari dipakai, pastikan handler baru memakai `grantPurchase` yang sama, jangan memberi koin dengan jalur kedua.

## 5. Bukti tes

Sinkron: `SYNC OK 12 script` (checksum FNV-1a, `Monetization` ikut terhitung). Gate statis: `selene src` 0 error 0 warning, `stylua --check src` lolos.

### Tes unit (datamodel Server saat Play, memory store, pemain palsu)

Receipt palsu memakai `ProductId = Config.Products.Coins100.Id` (masih 0), pembeli dicari lewat `getPlayer` palsu. Hasil: `SEMUA LULUS 34 cek`.

Receipt:

- R1. Receipt pertama: `PurchaseGranted`, Coins 100, dan store sudah berisi Coins 100 + `Receipts["R-1"]` + schema 2 sebelum pemain keluar.
- R2. `PurchaseId` sama: `PurchaseGranted`, koin tetap 100 di memori dan di store.
- R3. `PurchaseId` baru: Coins 200, dua receipt tercatat.
- R4. Pembeli tidak ada di server: `NotProcessedYet` tanpa menunggu, store tidak disentuh.
- R5. Pemain ada tapi tidak pernah termuat, batas 2 detik: `NotProcessedYet` setelah 4 kali tunggu 0,5 detik.
- R6. Data termuat saat menunggu: `PurchaseGranted` setelah 3 kali tunggu, tersimpan.
- R7. Save gagal (4 kali `503`): `NotProcessedYet`, memori sudah +100, store belum berisi data. Receipt dikirim ulang setelah store pulih: `PurchaseGranted`, koin tetap 100.
- R8. Save gagal lalu pemain keluar: `unload` menyimpan koin dan receipt. Receipt dikirim ulang di server B: `PurchaseGranted`, Coins 100 (tidak dobel).
- R9. Sesi `Offline` (tanpa store): `NotProcessedYet`, koin tidak berubah.
- R10. Lock diambil server lain di tengah sesi: `NotProcessedYet`, status `Locked`, JSON store byte-identik. Receipt berikutnya juga `NotProcessedYet`.
- R11. Dua server, A memegang lock, receipt datang di B: B `Locked`, `NotProcessedYet`, store byte-identik.
- R12. `ProductId` tidak dikenal: `NotProcessedYet`, satu log, koin tetap.
- R13. Pemain keluar saat ditunggu: `NotProcessedYet` setelah 2 kali tunggu.
- R14. Receipt yang sama datang lagi saat save pertama masih berjalan: keduanya `PurchaseGranted`, Coins 100, satu receipt di store.

Gamepass (`ownsPass` palsu, ID pass 777):

- G1. ID 0: `ownsPass` tidak dipanggil, pengali 1. Nilai default di `Config` masih 0.
- G2. Pemilik pengali 2, bukan pemilik 1.
- G3. Gagal 2 kali lalu berhasil: menunggu 1, 2, pengali 2, tanpa log.
- G4. Selalu gagal: menunggu 1, 2, 4, satu log, pengali 1, tidak ada sisa token.
- G5. Pemain keluar saat `ownsPass` berjalan, atau saat menunggu retry: tidak ada sisa di cache.
- G6. `onPassPurchased`: beli jadi 2, batal tetap 1, pass lain tetap 1.
- G7. Cek lama menjawab `false` setelah pemain membeli: pengali tetap 2.
- G8. Pickup lewat `CoinPickup` dengan pengali: pemilik +2, bukan pemilik +1. `CoinPickup` tanpa pengali tetap +1.
- G9. `removePlayer` membersihkan cache.

Schema:

- S1. Pemain baru: schema 2, `Receipts` ada.
- S2. Rekaman v1 `{ Coins = 12, Inventory = { SpeedBoots = true } }`: setelah lock diambil schema masih 1. Data terbaca Coins 12, SpeedBoots, `Receipts` kosong. Setelah save schema 2, data utuh.
- S3. Pemain keluar saat load rekaman v1: lock dilepas, data tidak ditulis, schema tetap 1.

### Tes mutasi

Setiap mutasi dipasang di instance modul hasil `require` di `execute_luau` (cache `require` di sana terpisah dari game, jadi game live tidak ikut berubah), lalu tes yang relevan dijalankan ulang. Semua mutasi membuat tesnya gagal:

| Mutasi | Tes yang gagal |
|---|---|
| M1. Tanpa cek `PurchaseId` | R2 |
| M2. Hasil save diabaikan, selalu `true` | R7 |
| M3. Cache gamepass ikut menulis `false` | G7 |
| M4. Tanpa menunggu data termuat | R6 |
| M5. `_claim` menstempel schema | S2 |

### Regresi

- Suite Hari 4: `SEMUA LULUS 47 cek`. Satu asersi diubah dari `schema == 1` ke `schema == 2`, sesuai kenaikan schema. Tidak ada asersi lain yang disentuh.
- Suite Hari 3: `SEMUA LULUS 36 cek`, tanpa perubahan.
- Kunci jawaban latihan 3 dijalankan di datamodel Server: `true`. Kontrolnya, receipt yang sama ke sesi A (pemegang lock), dijawab `PurchaseGranted` dengan Coins 100.

### Tes live (Play, pemain asli, DataStore asli yang belum tersedia)

1. Output saat Play: satu warning `[PlayerData] DataStore tidak tersedia ...` dan baris `ContentId: rbxassetid://203785492 failed` yang sudah ada sejak Hari 1 (bukan dari kode kita). Satu-satunya error datang dari probe kita sendiri yang mencoba membaca `ProcessReceipt` (lihat bagian 4), bukan dari kode game.
2. `DataStatus = Offline`.
3. Pickup nyata 6 kali dengan jeda: Coins `0,1,2,3,4,5,6`. Tetap +1 karena ID gamepass masih 0.
4. Beli lewat remote asli dari client: `BuyItem("SpeedBoots")` dibalas `Ok`, Coins 6 jadi 1. Diulang: `AlreadyOwned`.

### Tes integrasi (pemain asli, `getPlayer` bawaan, cermin asli, memory store)

Semua tes unit memakai pemain palsu dan `getPlayer` palsu. Untuk menutup celah itu, saat Play di datamodel Server dibuat `PlayerData` baru dengan memory store dan `onChanged = StatsMirror.sync`, lalu `Monetization.new(pd)` tanpa options (jadi `Players:GetPlayerByUserId` dan `task.wait` asli). Hasil:

- Sebelum: `leaderstats.Coins` 0, `DataStatus = Offline`.
- Receipt `LIVE-1` dengan `UserId` pemain asli: `PurchaseGranted`, `leaderstats.Coins` 100.
- `LIVE-1` lagi: `PurchaseGranted`, `leaderstats.Coins` tetap 100.
- Receipt dengan `PlayerId = 1` (tidak ada di server): `NotProcessedYet` seketika (0,000 detik).
- Store: Coins 100, `Receipts["LIVE-1"]`, schema 2. Setelah `unload`, lock dilepas.
- Output Play kedua ini hanya berisi warning DataStore dan baris `ContentId`, tanpa error.

### Yang belum bisa dites di place ini

- Belum ada kode yang memanggil `PromptProductPurchase` atau `PromptGamePassPurchase`, jadi pemain belum bisa memulai pembelian dari dalam game. Brief Hari 6 tidak memintanya, dan tombol beli baru berguna setelah ID terisi.
- Pembelian sungguhan: prompt, Robux, dan receipt yang dikirim Roblox. Test purchase di Studio juga butuh ID gamepass dan product yang sudah dibuat, dan itu butuh place yang dipublish.
- `UserOwnsGamePassAsync` sungguhan dan cache bawaannya.
- Receipt yang sama di dua server sungguhan. Yang dites adalah logikanya dengan dua instance `PlayerData` di satu server (R8, R11).
- Bahwa `ProcessReceipt` terpasang sebelum yield di game live. Callback itu tidak bisa dibaca dari script lain, jadi baru dicek dengan membaca kode.
- Server versi lama yang menolak rekaman schema 2. Logikanya sama dengan tes 11 Hari 4 (schema 99), tapi tidak dites dengan dua versi kode sungguhan.

## 6. Latihan mandiri

1. Tambahkan developer product "+500 Koin". Apa saja yang harus diubah?
   Petunjuk: lihat `findProduct`.
2. Kenapa `grantPurchase` tetap memanggil `save` walaupun `PurchaseId` sudah ada di `Receipts`? Apa yang salah kalau baris itu diganti `return true`?
   Petunjuk: tes R7.
3. Tulis tes: sesi `Locked` menerima receipt, jawabannya `NotProcessedYet` dan koin tidak bertambah.
   Petunjuk: dua `PlayerData` dengan satu memory store, seperti tes 2 Hari 4.

<details>
<summary>Kunci jawaban</summary>

1. Satu baris di `Config.Products`:
   ```lua
   Coins500 = table.freeze({ Id = 0, Coins = 500 }), -- "+500 Koin": isi setelah publish
   ```
   `findProduct` mencari di semua isi `Config.Products`, jadi `processReceipt` dan `grantPurchase` tidak perlu diubah. Setelah publish, buat product di Creator Dashboard dan isi `Id`.
   Hati-hati: selama dua product sama-sama ber-`Id` 0, `findProduct(0)` mengembalikan yang ketemu duluan, dan urutan iterasi table dengan key string tidak tentu. Receipt palsu di tes Hari 6 memakai `Id` 0, jadi tes R1 bisa mendapat +500. Isi `Id` sungguhan dulu, atau beri product kedua `Id` palsu yang berbeda selama tes.
2. Receipt pertama mencatat `PurchaseId` di memori, lalu save gagal dan jawabannya `NotProcessedYet`. Saat receipt itu datang lagi, `PurchaseId` sudah ada di memori. Kalau langsung `return true`, jawabannya `PurchaseGranted` padahal catatan dan koinnya belum pernah tersimpan. Kalau server mati sebelum autosave berikutnya, pemain kehilangan pembelian itu dan Roblox tidak akan mengirim receipt-nya lagi. Dengan `save`, jawaban `PurchaseGranted` hanya keluar setelah catatan benar-benar tersimpan.
3. ```lua
   local S = game.ServerScriptService.Server
   local Store = require(S.Store)
   local PlayerData = require(S.PlayerData)
   local Monetization = require(S.Monetization)
   local Config = require(game.ReplicatedStorage.Shared.Config)
   local mem = Store.memory()
   local quiet = { log = function() end, wait = function() end }
   local A = PlayerData.new({ store = mem, sessionId = "A", log = quiet.log, wait = quiet.wait })
   local B = PlayerData.new({ store = mem, sessionId = "B", log = quiet.log, wait = quiet.wait })
   local p = { UserId = 888, Name = "Tes" }
   A:load(p)
   local p2 = { UserId = 888, Name = "Tes" }
   B:load(p2) -- lock masih milik A: sesi Locked
   local m = Monetization.new(B, { getPlayer = function() return p2 end, wait = function() end })
   local d = m:processReceipt({ PurchaseId = "X", PlayerId = 888, ProductId = Config.Products.Coins100.Id })
   return d == Enum.ProductPurchaseDecision.NotProcessedYet and B:get(p2).Coins == 0
   ```
   `B:get(p2)` ada (sesi `Locked` tetap bisa dimainkan di memori), jadi `processReceipt` tidak menunggu. `grantPurchase` menolak karena sesi tidak `persisted`.

</details>
