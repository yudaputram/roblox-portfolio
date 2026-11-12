# Hari 2: RemoteEvent dan toko server-authoritative

File: `src/shared/Config.luau` (baru), `src/server/init.server.luau`, `src/client/init.client.luau`.

## 1. Tujuan

Pemain bisa membeli item dengan Coins. Client cuma mengirim permintaan "aku mau beli SpeedBoots". Server yang mengecek harga, saldo, dan kepemilikan, lalu memutuskan.

Analogi Laravel: `RemoteEvent` itu seperti route `POST /shop/buy`. `OnServerEvent` adalah controller-nya, dan argumen dari client adalah `$request->input()`. Kamu tidak akan pernah menerima `price` dari form lalu memotong saldo pakai angka itu. Di sini sama: client hanya mengirim `itemId`, harganya diambil server dari config.

Bedanya dengan web: tidak ada middleware CSRF, auth, atau throttle bawaan yang bisa kamu andalkan. Roblox memang memberi tahu server siapa pengirimnya (`player` selalu asli, tidak bisa dipalsukan), tapi validasi isi request dan rate limit kamu tulis sendiri.

## 2. Konsep inti

### ModuleScript untuk config bersama

File `.luau` tanpa akhiran `.server`/`.client` jadi `ModuleScript`. Isinya dijalankan sekali saat pertama kali di-`require`, lalu hasilnya di-cache. Server dan tiap client punya salinan sendiri. `Config` ada di `ReplicatedStorage.Shared`, jadi dua-duanya bisa membaca.

```lua
local Config = require(ReplicatedStorage.Shared.Config)
print(Config.Items.SpeedBoots.Price) -- 5
```

`table.freeze` membuat table read-only. Kalau ada kode yang tidak sengaja menulis `Config.Items.SpeedBoots.Price = 0`, langsung error. Tanpa freeze, salinan di satu client bisa berubah diam-diam sementara server tetap memakai angka lama, dan bug seperti itu susah dilacak.

### RemoteEvent

Jalur pesan satu arah antara server dan client.

| Arah | Kirim | Terima |
|---|---|---|
| Client ke server | `remote:FireServer(args...)` | `remote.OnServerEvent:Connect(function(player, args...)` |
| Server ke satu client | `remote:FireClient(player, args...)` | `remote.OnClientEvent:Connect(function(args...)` |
| Server ke semua client | `remote:FireAllClients(args...)` | sama |

Argumen pertama di `OnServerEvent` selalu `player` pengirim, diisi engine. Argumen sisanya bebas dikirim client, termasuk sampah.

### Inventori sebagai Folder

Tiap pemain punya Folder `Inventory`. Item yang dimiliki = satu `BoolValue` bernama id item. Folder di bawah `Player` ikut tereplikasi ke semua client, jadi nanti UI bisa langsung membacanya. Inventori bukan rahasia, jadi tidak masalah pemain lain bisa melihat.

## 3. Penjelasan kode

### Config (`src/shared/Config.luau`)

Item disimpan sebagai map `id -> { Name, Price, Order }`. Id (`SpeedBoots`) dipakai di kode dan jaringan, `Name` untuk tampilan, `Order` untuk urutan tombol. Memisahkan id dari nama tampilan berarti kamu bisa mengganti teks tanpa merusak data pemain yang sudah tersimpan (penting di Hari 4).

Harga item termurah sengaja 5 supaya tes bisa membeli dengan koin hasil pickup sungguhan dalam beberapa detik.

### Remotes dibuat server

Server membuat `ReplicatedStorage.Remotes` berisi `BuyItem` dan `BuyResult`, Parent folder paling akhir. Client menunggu dengan `WaitForChild`. Remote dibuat server supaya satu sumber yang menentukan remote apa saja yang ada.

`BuyResult` dipakai untuk memberi tahu client hasil yang wajar terjadi pada pemain jujur: `Ok`, `NotEnoughCoins`, `AlreadyOwned`. Itu untuk tampilan saja. Kalau client exploit mengabaikan balasan ini, tidak ada yang rusak.

### Urutan validasi di `BuyItem.OnServerEvent`

Cek dari yang paling murah:

1. Rate limit (`allowRequest`). Kalau kelewat batas, langsung buang. Ini paling depan supaya spam tidak sempat memicu kerja lain.
2. `type(itemId) ~= "string"`. Parameter diberi tipe `unknown` karena memang tidak diketahui. Jangan beri tipe `string`: anotasi tipe di Luau tidak mengecek apa pun saat runtime.
3. `Config.Items[itemId]` harus ada. Ini allowlist: hanya id yang dikenal server yang lolos.
4. Data pemain siap (`leaderstats` dan `Inventory` ada).
5. Belum dimiliki, lalu koin cukup. Dua ini dibalas lewat `BuyResult`.

Input rusak (bukan string, item tak dikenal, kena rate limit) tidak dibalas. Client jujur tidak pernah mengirimnya, jadi tidak ada yang perlu diberi tahu, dan membalas spam hanya menambah lalu lintas.

### Token bucket

Tiap pemain punya "ember" berisi maksimal 5 token. Tiap request memakai 1 token, dan ember terisi lagi 1 token per detik. Hasilnya: pemain boleh klik cepat beberapa kali, tapi rata-ratanya dibatasi 1 request per detik. Ini lebih ramah daripada cooldown kaku "1 detik sekali", karena dua klik cepat dari pemain jujur tetap dilayani.

Isi ulang dihitung saat request datang (`(now - updatedAt) * RefillPerSecond`), jadi tidak perlu loop atau timer. Ember dihapus di `PlayerRemoving`.

### Tidak ada yield antara cek dan ubah

Dari cek "koin cukup" sampai `coins.Value -= item.Price` tidak ada `task.wait`, `WaitForChild`, atau panggilan jaringan. Handler RemoteEvent dimulai berurutan, tapi kalau satu handler yield di tengah, handler berikutnya bisa jalan dulu. Kalau ada yield di antara cek dan potong koin, dua request beruntun bisa sama-sama lolos cek lalu sama-sama memotong (double spend). Ingat aturan ini di Hari 4 saat DataStore masuk.

### Client: tombol J, K, L

Sementara (sampai UI Hari 5), tombol J/K/L membeli item urutan 1/2/3. Bukan 1/2/3 karena itu slot hotbar Tool, dan pedang di Hari 8 akan memakainya. `gameProcessed` dicek supaya mengetik "j" di chat tidak membeli apa-apa.

## 4. Jebakan dan celah yang ditutup

- Harga dari client. Kalau server menerima `FireServer("GoldCrown", 0)` dan memakai argumen kedua sebagai harga, exploiter bisa beli gratis. Server di sini mengabaikan argumen kedua (tes "harga palsu" di bawah).
- Saldo palsu di client. Client bisa menulis `Coins.Value = 999` di layarnya sendiri. Server membaca nilainya sendiri, jadi tetap menolak.
- Tipe tidak dicek. `Config.Items[{}]` memang mengembalikan nil, tapi kebiasaan cek tipe di depan mencegah error di kode yang lebih rumit, misalnya `itemId:lower()` pada angka akan error dan menghentikan handler.
- Spam. Tanpa rate limit, exploiter bisa mengirim sampai sekitar 500 request per detik (batas throttle engine untuk satu client) dan membuat server sibuk. Request Roblox yang kelewat throttle engine tidak dibuang, hanya ditunda, jadi rate limit sendiri tetap perlu.
- Beli dua kali. Cek `AlreadyOwned` + tanpa yield membuat 50 request beruntun hanya memotong koin sekali.
- `debounce` global. Rate limit dan cooldown selalu per pemain.

## 5. Bukti tes (Studio MCP, Play solo, satu sesi)

Sinkron dicek dulu: panjang source di Studio sama persis dengan file repo (server 4652, client 1735, Config 679 karakter).

Jenis bukti: semua tes di bawah end-to-end lewat remote dan instance asli di sesi Play, bukan tes unit.

1. Positif (pickup nyata + tombol). Server memindahkan karakter masuk-keluar koin sampai Coins = 6 (6,8 detik). Lalu `user_keyboard_input` menekan J dan L. Server: Coins 6 jadi 1, `Inventory` berisi `SpeedBoots`. Output client: `Berhasil membeli Sepatu Kilat`, lalu `Koin belum cukup untuk Mahkota Emas` (L, Coins 1 < 50).
2. Negatif, saldo palsu. Client menulis `Coins.Value = 999` lalu `FireServer("GoldCrown")`. Balasan: `GoldCrown:NotEnoughCoins`. Dibaca dari Server: Coins tetap 1.
3. Negatif, 10 argumen aneh dengan jeda 1,1 detik (supaya tidak kena rate limit): `nil`, `123`, `NaN`, `true`, `{}`, `{itemId = "SpeedBoots"}`, `workspace`, string 10.000 huruf, `"ItemPalsu"`, dan `("GoldCrown", 0)`. Hasil: hanya kasus terakhir dibalas (`NotEnoughCoins`, harga palsu diabaikan), sisanya tanpa balasan. Server: Coins tetap 1, `Inventory` tetap `SpeedBoots` saja. Output tanpa error baru.
   Catatan: tes ini membuktikan "tidak crash dan tidak ada perubahan state". Kasus `nil`/angka/table tetap akan ditolak oleh lookup `Config.Items` walaupun cek tipe dihapus, jadi tes ini bukan bukti bahwa cek tipe yang menolaknya.
4. Spam. Setup: server mengisi Coins = 40 (di Hari 2 IntValue masih sumber kebenaran, jadi ini setara admin memberi koin). Tunggu 6 detik supaya ember penuh, lalu client mengirim `FireServer("JumpCoil")` 50 kali tanpa jeda. Hasil: tepat 5 balasan (`Ok` x1, `AlreadyOwned` x4), 45 sisanya dibuang. Server: Coins 40 jadi 25 (dipotong sekali), jumlah BoolValue `JumpCoil` = 1.
5. Tidak terblokir permanen. 2 detik setelah spam, satu request `JumpCoil` lagi tetap dibalas (`AlreadyOwned`).
6. Gate statis: `selene src` 0 error 0 warning, `stylua --check src` lolos.

Belum dites: dua client sekaligus (MCP hanya menjalankan Play solo).

## 6. Latihan mandiri

1. Tambahkan item keempat `RedCape` seharga 30 yang bisa dibeli dengan tombol baru.
   Petunjuk: cukup ubah `Config` dan satu tabel di client. Server tidak perlu disentuh. Kenapa?
2. Tambahkan remote `SellItem` yang menjual item kembali dengan setengah harga.
   Petunjuk: pikirkan urutan validasi yang sama, dan apa yang terjadi kalau pemain menjual item yang tidak dimiliki.
3. Ubah rate limit jadi beruntun 3 request lalu 1 request per 2 detik. Berapa balasan yang kamu harapkan dari spam 50x?
   Petunjuk: lihat `Config.Shop`.

<details>
<summary>Kunci jawaban</summary>

1. Tambahkan `RedCape = table.freeze({ Name = "Jubah Merah", Price = 30, Order = 4 })` di `Config.Items`, lalu tambahkan tombol keempat di `KEYS` client (misalnya `Enum.KeyCode.Semicolon`). Server tidak perlu diubah karena semua aturannya membaca `Config`: item baru otomatis masuk allowlist dan harganya dibaca dari sana.
2. Server:
   ```lua
   sellItem.OnServerEvent:Connect(function(player, itemId: unknown)
       if not allowRequest(player) then return end
       if type(itemId) ~= "string" then return end
       local item = Config.Items[itemId]
       local inventory = player:FindFirstChild("Inventory")
       local owned = inventory and inventory:FindFirstChild(itemId)
       local stats = player:FindFirstChild("leaderstats")
       local coins = stats and stats:FindFirstChild("Coins")
       if not item or not owned or not coins then return end
       owned:Destroy()
       coins.Value += math.floor(item.Price / 2)
   end)
   ```
   Kalau pemain menjual item yang tidak dimiliki, `owned` nil dan request ditolak. Tanpa cek ini, exploiter bisa "menjual" item yang tidak pernah dibeli dan mencetak koin.
3. `BurstLimit = 3`, `RefillPerSecond = 0.5`. Spam 50x dalam waktu sangat singkat menghasilkan 3 balasan (ember awal), karena dalam sepersekian detik itu belum ada token baru.

</details>
