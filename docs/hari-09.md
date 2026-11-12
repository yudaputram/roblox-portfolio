# Hari 9: Anti-exploit dan performa

File baru: `src/server/RateLimit.luau`, `docs/keamanan-checklist.md`. Diubah: `src/server/Shop.luau`, `src/server/Combat.luau`, `src/server/CoinPickup.luau`, `src/shared/Config.luau` (`Coin.Positions`, `Combat.RequestBurst`, `Combat.RequestsPerSecond`), `src/client/Sword.luau`.

## 1. Tujuan

Hari ini tidak ada fitur baru untuk pemain. Yang dikerjakan adalah review keamanan sebelum game dirilis:

1. Daftar semua jalur data dari client ke server, lalu cek apa yang divalidasi dan berapa batasnya.
2. Satu helper rate limit yang dipakai bersama oleh `BuyItem` dan `Attack`.
3. Semua tabel per pemain dibersihkan saat pemain keluar, dan koneksi per karakter diputus saat respawn.
4. Koin menjadi objek bertag: setiap Part bertag `Koin` otomatis menjadi koin, termasuk yang ditambahkan belakangan.

Kalau dari Laravel: ini seperti review sebelum deploy. Jalankan `php artisan route:list`, pastikan setiap route punya FormRequest dan middleware `throttle`, pastikan listener dan job tidak menyimpan data user yang sudah logout. `RateLimit.luau` setara `RateLimiter::for(...)` yang dipakai beberapa route. CollectionService mirip observer Eloquent: perilaku dipasang pada setiap objek yang cocok, termasuk yang dibuat nanti.

## 2. Konsep inti

### Jalur masuk dari client bukan hanya RemoteEvent

Exploiter mengendalikan client sepenuhnya. Setiap jalur di bawah bisa ia isi dengan apa saja, kapan saja, sebanyak apa saja.

| Jalur | Arah | Yang dikirim client | Validasi di server | Batas | Dibersihkan di |
|---|---|---|---|---|---|
| `BuyItem` (RemoteEvent) | client ke server | `itemId` | rate limit dulu; `type(itemId) == "string"`; ada di `Config.Items`; harga dari Config; saldo dan kepemilikan dicek `PlayerData:purchase` | bucket 5, isi ulang 1 per detik | `shop:removePlayer` |
| `BuyResult` (RemoteEvent) | server ke satu client | tidak ada | hanya `Ok`, `NotEnoughCoins`, `AlreadyOwned` yang dibalas, lewat `FireClient` ke pembeli saja | paling banyak satu balasan per request yang lolos bucket | tidak perlu |
| `Attack` (RemoteEvent) | client ke server | `target` (Model atau `nil`) | rate limit dulu; lalu 10 cek Hari 8 (cooldown, penyerang hidup, pedang dipegang, tipe, allowlist, jarak dari posisi di server) | bucket 10, isi ulang 5 per detik; cooldown ayunan 0,6 detik | `combat:removePlayer` |
| `Touched` pada koin | dilaporkan pemilik fisika karakter, yaitu client | tidak ada argumen, hanya "bagian tubuh ini menyentuh koin" | `GetPlayerFromCharacter(hit.Parent)`; data pemain sudah termuat | cooldown 1 detik per pemain | `coinPickup:removePlayer`; koneksi per koin diputus `unbind` |
| `ProcessReceipt` | backend Roblox ke server | tidak ada | `ProductId` dikenal; `PurchaseId` belum tercatat; data termuat dan tersimpan sebelum `PurchaseGranted` | Roblox mengirim ulang sampai diberi `PurchaseGranted` | tidak perlu |
| `PromptGamePassPurchaseFinished` | engine ke server | tidak ada | `passId` sama dengan `Config.GamePasses.DoubleCoins` dan `wasPurchased` | tidak perlu | `monetization:removePlayer` |
| Atribut `RoundState`, `RoundScore`, `DataStatus`, leaderstats | server ke client | tidak ada | client hanya membaca; perubahan di client tidak tersalin ke server | tidak perlu | ikut objeknya |
| Posisi karakter | client ke server (network ownership) | CFrame karakter | belum ada | belum ada | tidak perlu |

Dua catatan:

- `PromptGamePassPurchaseFinished` boleh dipercaya di server. Halaman `MarketplaceService` di Creator Hub: event ini "should only be listened to in a server script. When used on the server, values such as `wasPurchased` reflect the final outcome of the purchase attempt." Event ini ditembakkan engine, bukan RemoteEvent, jadi tidak ada `FireServer` yang bisa memalsukannya. CONFIRMED dari dokumentasi; tidak bisa dites live karena ID gamepass masih 0.
- `Touched` adalah jalur client yang sering terlupa. Sentuhan dilaporkan oleh client yang memiliki fisika karakter. Client yang sudah dimodifikasi bisa melaporkan sentuhan tanpa benar-benar mendekat. Belum dicoba di sini karena butuh alat exploit; latihan 3 menambahkan cek jarak.

### Rate limit dan cooldown itu beda

| | Rate limit (`RateLimit.luau`) | Cooldown |
|---|---|---|
| Tujuan | melindungi server dari banjir request | aturan permainan |
| Letak | paling depan, sebelum validasi apa pun | di dalam aturan fitur (`Combat:attack`, `CoinPickup:collect`) |
| Request yang ditolak | dibuang, tidak dibalas | dibalas atau dicatat sebagai `Cooldown` |
| Dirasakan pemain jujur | tidak pernah, kalau angkanya di atas laju klik normal | ya, itu memang ritme permainannya |

`Attack` punya keduanya. Cooldown 0,6 detik sudah membatasi pukulan; tanpa rate limit, 50 request dalam satu frame tetap menghasilkan satu pukulan (Hari 8). Rate limit menambah satu hal: 40 dari 50 request itu dibuang sebelum menyentuh 10 cek (C1). Angkanya, bucket 10 dan isi ulang 5 per detik, sekitar tiga kali laju ayunan pemain jujur (1 per 0,6 detik), supaya klik ganda dan auto-clicker biasa tidak pernah kena.

`BuyItem` hanya punya rate limit, karena membeli tidak punya ritme permainan. Bucket per remote, bukan satu bucket global: spam toko tidak boleh membuat pedang macet.

Engine Roblox juga punya batas sendiri, sekitar 500 request per detik per client untuk semua RemoteEvent. Menurut dokumentasi remote event di Creator Hub, request di atas batas itu ditunda, bukan dibuang, jadi tetap sampai ke handler (belum diukur di sini). Bucket di kode kita tetap dibutuhkan.

### Token bucket: dua aturan yang mudah salah

```lua
local refilled = bucket.tokens + (now - bucket.updatedAt) * self._refill
bucket.tokens = math.min(self._capacity, refilled)
```

`math.min` membatasi isi. Tanpa itu, pemain yang diam 10 menit mengumpulkan 3.000 token untuk `Attack` lalu bisa spam tanpa batas (mutan N1, tes R5).

```lua
if bucket.tokens < 1 then
	return false
end
bucket.tokens -= 1
```

Request yang ditolak tidak mengurangi token. Kalau ikut mengurangi, token jadi negatif dan pemain yang panik mengklik terkunci jauh lebih lama dari seharusnya (mutan N2, tes R6).

### CollectionService: satu perilaku untuk banyak objek

Sebelumnya `CoinPickup:start` membuat satu Part di (0, 3, 10) dan menghubungkan `Touched` miliknya. Koin kedua berarti menyalin kode itu.

Sekarang setiap BasePart bertag `Koin` adalah koin:

- `GetTagged("Koin")` untuk yang sudah ada saat server mulai, termasuk Part yang ditandai builder di Studio lewat Tag Editor.
- `GetInstanceAddedSignal("Koin")` untuk yang ditambahkan belakangan, misalnya koin yang dipasang skrip lain saat server sudah jalan (tes live L4). Koin yang muncul lagi di Hari 10 tidak lewat sinyal ini, karena tagnya tidak pernah dilepas.
- `GetInstanceRemovedSignal("Koin")` untuk melepas koneksi saat koin tidak lagi menjadi koin.

Sinyal removed menyala pada tiga kejadian: `Destroy`, `RemoveTag`, dan `Parent = nil` (K4). Yang paling penting adalah `RemoveTag`. Part masih ada, jadi koneksi `Touched` lamanya tetap hidup dan tetap membayar kalau tidak diputus (mutan N4, tes live L2).

Tag yang dipasang client tidak tersalin ke server. Exploiter yang memberi tag `Koin` pada Baseplate di client-nya tidak mendapat apa-apa (tes live L5).

### Membersihkan state per pemain

Setiap tabel yang kuncinya `Player` harus dikosongkan saat pemain keluar. Kalau tidak, server yang hidup berjam-jam menyimpan satu entri untuk setiap pemain yang pernah masuk. Semua pembersihan dipanggil dari satu handler `PlayerRemoving` di `init.server.luau`.

| Modul | State per pemain | Dibersihkan oleh | Bukti |
|---|---|---|---|
| `Shop` | `_limit._buckets` | `removePlayer` | suite Hari 3: bucket ada, lalu hilang |
| `CoinPickup` | `_cooling` | `removePlayer` | suite Hari 3 |
| `Monetization` | `_doubleCoins`, `_checking` | `removePlayer` | suite Hari 6: G5a, G5b, G9 |
| `Rounds` | `_scores` | `removePlayer` | suite Hari 7: T9 |
| `Combat` | `_lastSwing`, `_requests._buckets`, `_characterAdded` (koneksi) | `removePlayer` | suite Hari 8: T12; suite Hari 9: C2 |
| `PlayerData` | sesi dan data | `unload` (terakhir, karena menunggu save) | suite Hari 4 |

`CoinPickup._touched` dikunci per koin, bukan per pemain, dan dibersihkan oleh `unbind` (K3).

Tabel milik modul yang sedang jalan tidak bisa dibaca dari luar: `require` di `execute_luau` punya cache sendiri dan memberi salinan modul yang berbeda dari milik game. Jadi pembersihan dibuktikan dengan instance baru di tes unit, plus membaca handler `PlayerRemoving`.

### Karakter lama tidak di-Destroy saat respawn

Diukur di Play (datamodel Client) setelah `LoadCharacterAsync`: karakter lama hanya dilepas (`Parent` menjadi `nil`), event `Destroying` tidak menyala. Pedang di Backpack lama ikut di-Destroy.

Akibatnya di `Sword.luau`: koneksi `character.ChildAdded` ke karakter lama tidak diputus oleh engine, satu koneksi per respawn. Kalau handler-nya memegang karakter, model lama ikut tertahan di memori. Handler `hook` di sini tidak memegangnya, dan penahanan memori tidak diukur. Perbaikannya tetap murah: simpan koneksi itu dan putus saat karakter baru datang.

Perilaku ini diatur `Workspace.PlayerCharacterDestroyBehavior`. Properti itu tidak bisa dibaca dari Luau di place ini, jadi yang dipakai adalah hasil pengukuran. Kalau properti itu diaktifkan nanti, Roblox akan men-Destroy karakter lama dan `Disconnect` manual ini tetap aman.

### Validasi gerak: sengaja belum dibuat

Hari 8 membuktikan celahnya: karakter dipindah dari client ke samping boneka, tunggu 1 detik, pukulan diterima. Celah yang sama berlaku untuk koin.

Cek kecepatan gerak di server tidak dibuat hari ini. Cek seperti itu butuh toleransi untuk lag jaringan. Toleransi itu harus diukur dengan pemain sungguhan berkoneksi buruk, sedangkan Play di Studio hanya satu client di mesin yang sama. Angka yang salah membuat pemain jujur ditarik balik atau di-kick. Celah ini tetap terbuka dan tercatat di checklist. Pilihan untuk nanti ada di bagian 4.

## 3. Penjelasan kode

### `RateLimit.luau`

```lua
function RateLimit.new(capacity: number, refillPerSecond: number)
function RateLimit:allow(player: Player, now: number): boolean
function RateLimit:removePlayer(player: Player)
```

Isinya token bucket yang dulu ada di dalam `Shop` (Hari 2), dipindah ke modul sendiri supaya `Combat` bisa memakainya. `now` adalah argumen, sama seperti `Combat:attack` dan `Rounds:step`, jadi tes memakai jam buatan.

Bucket dibuat saat request pertama datang, bukan saat pemain masuk. Pemain yang tidak pernah membeli tidak punya entri sama sekali.

### `Shop`

```lua
self._limit = RateLimit.new(Config.Shop.BurstLimit, Config.Shop.RefillPerSecond)
-- ...
if not self._limit:allow(player, os.clock()) then
	return false, "RateLimited"
end
```

Perilakunya sama persis dengan Hari 2. Bukti: suite Hari 3 tetap 36/36, termasuk spam 50 yang menghasilkan `Ok` 1, `AlreadyOwned` 4, `RateLimited` 45.

### `Combat:request`

```lua
function Combat:request(player: Player, target: unknown, now: number): (boolean, string)
	if not self._requests:allow(player, now) then
		return false, "RateLimited"
	end
	return self:attack(player, target, now)
end
```

Remote memanggil `request`; `attack` tidak berubah. Dengan begitu 14 tes Hari 8 tetap menguji aturan ayunan tanpa ikut menghabiskan bucket.

### `CoinPickup:bind` dan `unbind`

```lua
function CoinPickup:bind(part: Instance)
	if not part:IsA("BasePart") or self._touched[part] then
		return
	end
	self._touched[part] = part.Touched:Connect(function(hit: BasePart)
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if player then
			self:collect(player)
		end
	end)
end
```

Tag bisa dipasang pada objek apa saja. Model atau Folder bertag `Koin` diabaikan tanpa error (K2); memanggil `.Touched` pada Model akan error. `self._touched[part]` mencegah koneksi ganda kalau `bind` terpanggil dua kali untuk part yang sama (K1).

`start` menghubungkan sinyal added dan removed lebih dulu, lalu `GetTagged`, lalu membuat lima koin dari `Config.Coin.Positions`. Urutan ini memastikan tidak ada koin yang terlewat.

### `Sword.start` (client)

```lua
local childAdded: RBXScriptConnection? = nil
local function onCharacter(character: Model)
	if childAdded then
		childAdded:Disconnect()
	end
	childAdded = character.ChildAdded:Connect(hook)
	-- ...
end
```

## 4. Jebakan dan celah

- Rate limit diletakkan setelah validasi. Server tetap mengerjakan validasi untuk setiap request banjir. Cek bucket harus paling depan.
- Bucket tanpa batas kapasitas (N1, R5) atau yang tetap mengurangi token saat menolak (N2, R2, R6, C1).
- Satu bucket global untuk semua remote. Spam di satu fitur membuat fitur lain ikut macet.
- Lupa `removePlayer`. Tidak ada error, hanya memori yang naik pelan-pelan. Cari dengan `grep -n "\[Player\]" src` lalu cocokkan dengan handler `PlayerRemoving`.
- `Touched` per koin tanpa `unbind`. Saat koin di-`Destroy`, Roblox sudah memutus koneksinya sendiri, tapi entri di `_touched` tetap menahan part itu. Saat tag dilepas, koneksi lama tetap membayar (N4, K3, L2).
- Tag di Model. Builder yang memberi tag `Koin` pada Model (misalnya koin dari mesh) tidak mendapat error, tapi koinnya juga tidak bisa diambil. Tag dipasang pada BasePart-nya.
- Mempercayai tag atau atribut yang diubah client. Server selalu membaca miliknya sendiri (L5).
- Koneksi ke karakter lama di client (perbaikan `Sword.luau`).
- Celah yang masih terbuka: teleport. Posisi karakter dimiliki client. Pilihan untuk nanti:
  - Server mencatat posisi karakter tiap Heartbeat dan menarik balik karakter yang berpindah lebih jauh dari `WalkSpeed` kali waktu, ditambah toleransi. Toleransinya harus diukur dengan pemain sungguhan (Test > Server & Clients dengan Network Simulator).
  - Server Authority (`Workspace.AuthorityMode = Server`): server yang mensimulasikan gerak, client hanya memprediksi. Ini migrasi seluruh project, bukan perubahan kecil.
- Celah yang masih terbuka: sentuhan palsu. Client pemilik fisika bisa melaporkan sentuhan koin dari jauh. Cek jarak di handler `Touched` (latihan 3) menutup versi tanpa teleport.

## 5. Bukti tes

Gate: `selene src` 0 error 0 warning, `stylua --check src` lolos, sinkronisasi Rojo `SYNC OK 17 script`.

### Tes unit Hari 9 (datamodel Server saat Play)

Instance modul baru, PlayerData palsu, jam buatan. Hasil: 12/12.

| Tes | Yang dibuktikan |
|---|---|
| R1 | bucket 5: dari 7 request di detik yang sama, 5 lolos |
| R2 | setelah habis: t+0,5 ditolak, t+1,01 lolos, t+1,02 ditolak lagi |
| R3 | bucket per pemain: pemain lain tetap lolos |
| R4 | `removePlayer` menghapus bucket; request berikutnya mendapat bucket penuh |
| R5 | diam 1.000 detik dengan kapasitas 3: tetap hanya 3 yang lolos |
| R6 | 20 request ditolak dalam 0,2 detik tidak memakai jatah: request tepat 1 detik setelah jatah terakhir lolos |
| C1 | `Combat:request` 50 kali di waktu yang sama: `Hit` 1, `Cooldown` 9, `RateLimited` 40; satu request 0,7 detik kemudian `Hit`; nyawa boneka 50 |
| C2 | `Combat:removePlayer` menghapus bucket `Attack` |
| K1 | `bind` dua kali pada part yang sama: satu koneksi |
| K2 | `bind` pada Model dan Folder: tanpa error, tanpa koneksi |
| K3 | `unbind` memutus koneksi; `unbind` kedua tidak error |
| K4 | sinyal removed menyala untuk `Destroy`, `RemoveTag`, dan `Parent = nil` |

| Mutan | Tertangkap oleh |
|---|---|
| N1 bucket tanpa batas kapasitas | R5 |
| N2 request yang ditolak tetap memakai jatah | R2, R6, C1 |
| N3 `Attack` tanpa rate limit | C1, C2 |
| N4 `unbind` tidak memutus koneksi | K3 |
| N5 `bind` tanpa cek BasePart | K2 |

Setelah semua mutan, fungsi asli dikembalikan: 12/12 lagi.

### Regresi (sesi Play yang sama)

| Suite | Hasil |
|---|---|
| Hari 3 | 36/36. Cek bucket diganti dari `shop._buckets` ke `shop._limit._buckets` karena state-nya pindah ke `RateLimit`. |
| Hari 6 | 34/34 |
| Hari 7 | 19/19, 6 mutan tertangkap |
| Hari 8 | 14/14, 9 mutan tertangkap, kontrol lolos |

### Tes live (Play, satu pemain asli)

Server memasang pencatat perubahan `leaderstats.Coins` dan jumlah request `Attack`.

1. L1, jalan ke koin (20, 3, 10) dengan `character_navigation`: koin 0 menjadi 1, lalu 2 setelah 2,1 detik. Selama berdiri di dalam koin, pickup berulang kira-kira tiap 3,8 detik. Cooldown-nya 1 detik; penyebab jeda yang lebih panjang belum diukur. Ini catatan awal kurikulum yang tidak terulang di tes Hari 1 (di sana diam 15 detik hanya memberi +1). Jadi masalah Hari 1 terulang di sini, dan langkah L1 dipakai lagi untuk menguji perbaikannya di Hari 10 (koin hilang setelah diambil).
2. L2, server melepas tag koin itu, lalu karakter berjalan masuk lagi dan berdiri di dalamnya sekitar 12 detik: koin tetap 5. Lima pickup sebelumnya semuanya tercatat sebelum tag dilepas.
3. L3, kontrol: koin (-20, 3, 10) memberi +1. Di sesi yang sama ada +10 dari hadiah ronde (`WinningScore` 2, daftar pemenang terisi).
4. L4, Part bertag `Koin` yang dibuat server setelah `start` jalan, di (0, 3, 30): +1. Model bertag `Koin` yang dibuat bersamaan tidak menimbulkan error.
5. L5, client memberi tag `Koin` pada Baseplate dan membuat Part 6x6x6 bertag di posisi karakter. Di server: Baseplate tidak bertag, jumlah tag tetap 6, Part buatan client tidak ada. Karakter bergerak di atasnya selama 13 detik: koin tidak berubah.
6. L6, server men-`Destroy` koin runtime dan Model bertag: tag tersisa 4, tanpa error.
7. L7, `Attack` dari client: pedang dipegang 6,1 stud dari boneka, 50 `FireServer` dalam satu loop, lalu satu lagi 0,7 detik kemudian. Server menerima 51 request; nyawa boneka berubah dua kali, 100 menjadi 50.
8. L8, toko dari client: 50 `BuyItem("GoldCrown")` dengan koin 17. Client menerima 5 balasan `NotEnoughCoins`; 45 sisanya dibuang tanpa balasan.
9. L9, setelah dua kali `LoadCharacterAsync`: client memegang pedang baru dan memanggil `Activate` dua kali. Server menerima tepat 2 request, jadi pedang tetap terhubung dan tidak ada koneksi ganda. Ini cek tanpa regresi, bukan bukti perbaikan: tes yang sama juga lolos tanpa `Disconnect`, karena karakter lama tidak pernah mendapat child baru.
10. Output setelah semua tes: peringatan DataStore yang sudah dikenal, noise `ContentId` lama, dan baris "Hadiah ronde gagal" dari pemain palsu A dan B yang sengaja dibuat gagal di suite Hari 7 (T11, T12). Tidak ada error dari kode hari ini.

### Yang belum bisa dites

- Dua pemain sungguhan: bucket per pemain hanya dibuktikan di R3 dengan pemain palsu.
- Lag jaringan: angka rate limit belum diuji dengan paket yang tertahan lalu tiba bersamaan, selain simulasi di latihan 2.
- Sentuhan palsu dari alat exploit.
- Pembelian gamepass sungguhan: ID masih 0 karena place belum dipublish.

## 6. Latihan mandiri

1. Pemain jujur menekan tombol beli 3 kali per detik selama 10 detik (30 request) dengan batas toko sekarang (bucket 5, isi ulang 1 per detik). Kira-kira berapa yang diproses, dan kapan penolakan pertama terjadi?
2. Koneksi pemain tertahan, lalu 20 request `Attack` tiba di server pada saat yang sama. Berapa yang sampai ke `Combat:attack`, dan apakah pemain kehilangan ayunan dibanding tanpa rate limit?
3. Tambahkan cek jarak di handler `Touched` koin supaya sentuhan yang dilaporkan dari jauh tidak dibayar. Di mana cek itu diletakkan, dan berapa jaraknya?

<details>
<summary>Kunci jawaban</summary>

1. Sekitar 14 dari 30. Bucket mulai berisi 5, pemakaian 3 per detik, isi ulang 1 per detik, jadi bucket habis sekitar detik ke-2. Setelah itu hanya 1 per detik yang lolos: 5 + sekitar 9 = 14. Disimulasikan dengan `RateLimit` asli dan jam buatan (request pada t = 0, 1/3, 2/3, ...): 14 lolos, penolakan pertama pada t = 2,0. Secara hitungan murni request pada t = 2,0 masih tepat mendapat 1 token; pembulatan desimal membuatnya sedikit di bawah 1.

   Untuk toko ini wajar: setiap pembelian yang sah langsung mengubah koin dan kepemilikan, jadi 3 klik per detik selama 10 detik bukan pola pemain biasa.

2. 10 sampai ke `attack` (bucket 10), 10 dibuang. Disimulasikan dengan `RateLimit` dan angka `Config.Combat`: 10 dari 20 lolos. Pemain tidak kehilangan apa pun. Dari 10 yang sampai, hanya yang pertama bisa menjadi ayunan; sisanya ditolak `Cooldown` karena datang di saat yang sama. Tanpa rate limit hasilnya juga satu ayunan, hanya 19 request yang diperiksa, bukan 9. C1 membuktikan pola yang sama dengan 50 request.

3. Letakkan di dalam handler `Touched` di `bind`, sebelum `collect`. Di sana part koin dan bagian tubuh yang menyentuh sama-sama diketahui:
   ```lua
   self._touched[part] = part.Touched:Connect(function(hit: BasePart)
   	local character = hit.Parent
   	local player = Players:GetPlayerFromCharacter(character)
   	local root = character and character:FindFirstChild("HumanoidRootPart")
   	if not (player and root and root:IsA("BasePart")) then
   		return
   	end
   	-- Koin 2 stud, karakter sekitar 5 stud tinggi: 8 stud memberi kelonggaran untuk lag.
   	if (root.Position - part.Position).Magnitude > 8 then
   		return
   	end
   	self:collect(player)
   end)
   ```
   `collect` tidak diubah, jadi semua tes `collect` tetap berlaku. Jaraknya dibaca dari posisi di server, sama seperti cek `TooFar` di `Combat`. Cek ini menahan sentuhan palsu dari jauh, tapi tidak menahan teleport: karakter yang dipindah ke samping koin tetap lolos, sama seperti tes live 10 Hari 8. Diuji di Play dengan isi handler di atas, dipanggil langsung dengan `Head` karakter asli yang `HumanoidRootPart`-nya di-anchor: koin 50 stud jauhnya tidak membayar (0), koin 3 stud membayar (1), sentuhan dari Baseplate tidak membayar.

</details>
