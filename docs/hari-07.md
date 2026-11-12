# Hari 7: Sistem ronde (state machine)

File baru: `src/server/Rounds.luau`, `src/client/RoundStatus.luau`. Diubah: `src/shared/Config.luau` (`Config.Round`), `src/server/CoinPickup.luau` (callback `onCollected`), `src/server/init.server.luau` (folder `RoundState`, perakitan), `src/client/ShopView.luau` (baris status ronde di HUD), `src/client/init.client.luau` (membaca status ronde).

## 1. Tujuan

Game berjalan dalam ronde yang berulang:

1. Intermission (15 detik): jeda sebelum ronde.
2. Round (45 detik): setiap pickup koin menambah skor ronde 1.
3. Result (6 detik): pemenang diumumkan dan menerima 10 koin dari server.

Lalu kembali ke Intermission.

Kalau dari Laravel, bayangkan kolom `status` di tabel `orders` (`pending`, `paid`, `shipped`) plus scheduler yang terus mengecek "sudah waktunya pindah status?". Di sini scheduler-nya adalah `RunService.Heartbeat` (setiap frame), dan statusnya disimpan di atribut yang ikut tersalin ke semua client.

Analogi JS: countdown flash sale yang benar mengirim `ends_at` dari server sekali, lalu browser menghitung mundur sendiri. Yang salah mengirim "sisa 14 detik", "sisa 13 detik", dan seterusnya setiap detik.

## 2. Konsep inti

### Tabel transisi

| Fase | Pindah kalau | Ke | Yang terjadi |
|---|---|---|---|
| Intermission, `EndsAt = 0` | pemain >= `MinPlayers` | Intermission berwaktu | hitung mundur dimulai |
| Intermission berwaktu | pemain < `MinPlayers` | Intermission, `EndsAt = 0` | hitung mundur berhenti, menunggu pemain |
| Intermission berwaktu | waktu habis | Round | skor dikosongkan, `RoundScore` semua pemain jadi 0 |
| Round | waktu habis | Result | pemenang dihitung, ditulis, lalu dibayar |
| Round | pemain < `MinPlayers` | Result | ronde batal, tanpa pemenang |
| Result | waktu habis | Intermission berwaktu | |

Seluruh tabel ini ada di satu fungsi, `Rounds:step(now)`. Setiap transisi bisa dites dengan memanggil `step` dan memajukan `now` sendiri, tanpa menunggu 45 detik.

### Waktu server

`Workspace:GetServerTimeNow()` memberi angka yang sama di server dan di semua client. Server menulis `EndsAt` sekali per fase, lalu setiap client menghitung `EndsAt - GetServerTimeNow()` sendiri.

Jangan pakai:

- `os.time()`: detik bulat, dan jam komputer pemain bisa salah.
- `os.clock()`: waktu CPU sejak proses mulai, berbeda di setiap mesin.

Diukur di Play: saat fase berganti, jam client menunjukkan 0,049 detik setelah `EndsAt`. Angka itu sudah termasuk jeda replikasi.

### Atribut sebagai saluran status

Server menulis atribut di folder `ReplicatedStorage.RoundState`:

| Atribut | Isi |
|---|---|
| `Phase` | `"Intermission"`, `"Round"`, atau `"Result"` |
| `EndsAt` | waktu server saat fase berakhir. 0 di Intermission berarti menunggu pemain |
| `Winners` | nama akun pemenang, dipisah koma. Kosong kalau tidak ada pemenang |
| `WinningScore` | skor pemenang, 0 kalau tidak ada |

Ditambah atribut `RoundScore` di setiap `Player`.

Atribut di ReplicatedStorage tersalin ke semua client secara otomatis, termasuk ke pemain yang baru masuk. Kalau status dikirim lewat `RemoteEvent` "RoundChanged", pemain yang masuk setelah event itu tidak pernah menerimanya dan butuh remote kedua untuk bertanya. Atribut juga satu arah: perubahan atribut dari client tidak tersalin ke server.

### Satu fakta untuk "siapa menang"

Server menulis `Winners`, lalu membayar orang yang sama. Client hanya mencari nama akunnya sendiri di daftar itu. Client tidak menghitung pemenang dari skor yang ia lihat, karena hasilnya bisa berbeda dengan keputusan server (misalnya karena skor pemain lain belum tersalin).

### Skor = jumlah pickup

Skor ronde menghitung pickup, bukan koin. Pemilik gamepass 2x Koin (Hari 6) tetap dapat 2 koin per pickup, tapi skornya tetap +1. Gamepass tidak membeli kemenangan.

## 3. Penjelasan kode

### `Config.Round`

```lua
Round = table.freeze({
	IntermissionSeconds = 15,
	RoundSeconds = 45,
	ResultSeconds = 6,
	-- shortcut: 1 supaya bisa dites sendirian di Studio, naikkan ke 2 sebelum publish.
	MinPlayers = 1,
	WinnerReward = 10, -- koin untuk tiap pemenang
}),
```

`MinPlayers = 1` supaya ronde bisa dites dengan satu pemain di Studio. Dengan nilai 1, cabang "menunggu pemain" hanya terlihat di server kosong.

### `Rounds:_set`: EndsAt dulu, baru Phase

```lua
function Rounds:_set(phase: Phase, endsAt: number)
	self._phase = phase
	self._endsAt = endsAt
	self._status:SetAttribute("EndsAt", endsAt)
	self._status:SetAttribute("Phase", phase)
end
```

Tujuannya: client yang bereaksi pada perubahan `Phase` sudah melihat `EndsAt` yang baru. Tes T14 mengunci urutan tulis di server; urutan tibanya di client tidak diukur di kurikulum ini. Client di repo ini membaca ulang semua atribut setiap 0,2 detik, jadi teksnya tetap benar paling lambat 0,2 detik kemudian, apa pun urutan tibanya.

### `Rounds:step(now)`

Dipanggil setiap Heartbeat dengan `Workspace:GetServerTimeNow()`. Waktu menjadi argumen, bukan dibaca di dalam, supaya tes bisa memakai jam palsu. Isinya tabel transisi di bagian 2, ditulis sebagai `if`.

### `Rounds:_finish`: fase berganti sebelum hadiah dibayar

```lua
self._status:SetAttribute("Winners", table.concat(names, ","))
self._status:SetAttribute("WinningScore", best)
self:_set("Result", now + Config.Round.ResultSeconds)
for _, player in winners do
	local ok, paid = pcall(self._playerData.addCoins, self._playerData, player, Config.Round.WinnerReward)
	if not (ok and paid) then
		warn(`Hadiah ronde gagal untuk {player.Name}: {if ok then "data belum termuat" else paid}`)
	end
end
```

Tiga keputusan di sini:

1. Fase berganti dulu. `step` dipanggil 60 kali per detik. Kalau hadiah dibayar dulu dan satu pembayaran error sebelum fase berganti, fase tetap Round. Frame berikutnya membayar pemenang yang sama lagi, 60 kali per detik. Tes T11 dan mutasi M1 membuktikannya.
2. Setiap pembayaran dibungkus `pcall`. Error pada satu pemenang tidak membatalkan hadiah pemenang lain.
3. `Winners` dan `WinningScore` selalu ditulis, juga saat kosong. Kalau hanya ditulis saat ada pemenang, ronde tanpa pemenang menampilkan pemenang ronde sebelumnya (T8, M3).

Aturan pemenang:

- Skor tertinggi menang.
- Seri: semua yang skornya tertinggi menang dan masing-masing dapat hadiah penuh.
- Tidak ada yang mengambil koin: tidak ada pemenang.
- Ronde batal (pemain di bawah `MinPlayers`): tidak ada pemenang, walaupun ada yang sudah punya skor. Ronde dianggap tidak sah tanpa cukup lawan. Ini pilihan desain; game lain memilih memberi hadiah ke pemain yang tersisa.

Nama dipisah koma karena nama akun Roblox hanya berisi huruf, angka, dan garis bawah. `DisplayName` tidak dipakai karena bisa sama antar pemain.

### `Rounds:onCollected` dan `removePlayer`

```lua
function Rounds:onCollected(player: Player)
	if self._phase ~= "Round" then
		return
	end
	local score = (self._scores[player] or 0) + 1
	self._scores[player] = score
	player:SetAttribute("RoundScore", score)
end

function Rounds:removePlayer(player: Player)
	self._scores[player] = nil
end
```

Pickup di Intermission dan Result tetap memberi koin (CoinPickup tidak berubah), tapi tidak menambah skor. Pemain yang keluar dihapus dari tabel skor, jadi tidak bisa menang. Tanpa itu, tabel juga terus memegang objek `Player` yang sudah pergi.

### `CoinPickup`: callback paling akhir

```lua
task.delay(Config.Coin.Cooldown, function()
	self._cooling[player] = nil
end)
-- Paling akhir: kalau callback error, koin dan cooldown sudah tercatat.
if self._onCollected then
	self._onCollected(player)
end
return true
```

Kalau callback dipanggil sebelum cooldown dipasang dan callback itu error, cooldown tidak pernah terpasang. Setiap sentuhan berikutnya memberi koin tanpa jeda (mutasi M6, tes C2). Parameter ketiga opsional, jadi `CoinPickup.new(pd)` dari Hari 3 dan `CoinPickup.new(pd, multiplier)` dari Hari 6 tetap jalan.

### Perakit (`init.server.luau`)

```lua
local roundState = Instance.new("Folder")
roundState.Name = "RoundState"
local rounds = Rounds.new(playerData, roundState)
roundState.Parent = ReplicatedStorage
```

`Rounds.new` mengisi atribut awal sebelum folder dipasang di ReplicatedStorage, jadi client tidak pernah melihat folder tanpa `Phase`. Callback skor diteruskan ke `CoinPickup.new`, `rounds:start()` dipanggil setelah `coinPickup:start()`, dan `rounds:removePlayer(player)` ditambahkan di `PlayerRemoving`.

### Client: `RoundStatus.text` dan baris di HUD

`RoundStatus.text(round, now, me, myScore)` fungsi murni: menerima nilai atribut, jam server, nama akun, dan skor, lalu mengembalikan satu kalimat:

| Keadaan | Teks |
|---|---|
| Intermission, `EndsAt = 0` | `Menunggu pemain lain` |
| Intermission | `Ronde mulai dalam 12 detik` |
| Round | `Ronde: 30 detik lagi. Skor kamu: 3` |
| Result, saya di `Winners` | `Kamu menang! +10 koin (skor 3)` |
| Result, orang lain menang | `Pemenang: Ann, Bob (skor 3)` |
| Result, lebih dari 3 pemenang | `Pemenang: A, B, C dan 2 lainnya (skor 1)` |
| Result, tanpa pemenang | `Ronde selesai. Tidak ada pemenang.` |
| atribut belum sampai | `nil`, baris disembunyikan |

Di `init.client.luau`, satu loop membaca atribut setiap 0,2 detik dan memanggil `render()` hanya kalau teksnya berubah, kira-kira sekali per detik. `ShopView` menaruh teks itu di baris paling atas HUD, lebar 280 px seperti baris Notice, dan membungkus teks panjang ke baris berikutnya.

## 4. Jebakan dan celah yang ditutup

- Hadiah dibayar sebelum fase berganti. Satu error membuat hadiah dibayar ulang setiap frame (M1, T11).
- Mengirim sisa detik setiap detik. Lalu lintas jaringan terus-menerus, dan angkanya meleset sebesar jeda jaringan. `EndsAt` ditulis sekali per fase.
- `os.time()` atau `tick()` di client untuk hitung mundur. Jam komputer pemain bisa salah beberapa menit.
- Pemenang lama tetap tampil. `Winners` harus ditulis ulang di setiap Result, juga saat kosong (M3, T8).
- Client menentukan menang sendiri dari skor yang ia lihat. Bisa berbeda dengan yang dibayar server. Client hanya membaca `Winners`.
- Pemain keluar di tengah ronde. Tanpa `removePlayer`, skornya tetap ada: pemain yang sudah pergi bisa "menang", lalu `addCoins` gagal karena datanya sudah di-unload (T9).
- Callback CoinPickup sebelum cooldown (M6, C2).
- Client mengubah atribut. `RoundScore` atau `Phase` yang diubah exploiter hanya berubah di layarnya sendiri; perubahan dari client tidak tersalin ke server (tes live 7). Skor dihitung server dari `Touched`. Celah yang masih ada: exploiter bisa memindahkan karakternya ke koin seperti pemain biasa, dan cooldown 1 detik membatasinya ke 1 pickup per detik. Repo ini belum memeriksa kecepatan gerak atau teleport karakter di server.
- Seri besar. Daftar nama diringkas jadi 3 nama plus "dan N lainnya", dan baris membungkus. Kasus terburuk yang diukur (tiga nama 20 huruf) membuat HUD setinggi 170 px, lebih dari separuh tinggi aman di Galaxy A06 landscape, selama 6 detik Result.
- HUD disembunyikan saat toko terbuka (aturan Hari 5), jadi status ronde tidak terlihat selama pemain belanja. Pilihan sengaja supaya panel toko tidak bertumpuk dengan HUD.
- `MinPlayers = 1` hanya untuk tes di Studio. Game sungguhan sebaiknya 2.

## 5. Bukti tes

Gate: `selene src` 0 error 0 warning, `stylua --check src` lolos, sinkronisasi Rojo `SYNC OK 14 script`.

### Tes unit (datamodel Server saat Play, jam palsu, pemain palsu)

`step(now)` dipanggil dengan angka waktu buatan. Pemain palsu adalah table dengan `Name` dan `SetAttribute`. PlayerData palsu mencatat pembayaran dan bisa diatur untuk error atau mengembalikan `false`. Hasil: 19/19 lolos.

| Tes | Yang dibuktikan |
|---|---|
| T1 | awal: Intermission, `EndsAt = 0` |
| T2 | 0 pemain: tetap menunggu, `EndsAt` tetap 0 |
| T3 | 1 pemain: hitung mundur 15 detik, lalu Round dengan `RoundScore = 0` |
| T4 | pickup di Intermission dan Result tidak menambah skor |
| T5 | skor 3 lawan 1: A menang, `WinningScore = 3`, A dibayar 10 sekali, B tidak |
| T6 | `step` berulang selama Result tidak membayar lagi, lalu Intermission |
| T7 | seri 2-2-1: `Winners = "Bob,Zed"` terurut, keduanya dibayar, yang skor 1 tidak |
| T8 | ronde tanpa pemenang tepat setelah ronde yang dimenangkan: `Winners` kosong, `WinningScore` 0, teks client "Ronde selesai. Tidak ada pemenang." |
| T9 | A (skor 5) keluar di tengah ronde: B (skor 1) menang, A tidak dibayar |
| T10 | semua pemain pergi di tengah ronde (tanpa `removePlayer`): Result tanpa pemenang, lalu menunggu pemain |
| T11 | seri tiga, pembayaran B error, `step` dipanggil 5 kali: A dan C dibayar tepat sekali, B tidak, total 3 panggilan |
| T12 | `addCoins` mengembalikan `false`: tidak crash, fase tetap Result |
| T13 | hitung mundur berhenti saat pemain pergi, mulai ulang saat ada pemain |
| T14 | urutan tulis atribut: `Winners`, `WinningScore`, `EndsAt`, `Phase` |
| C1 | callback dipanggil sekali per pickup sah, tidak saat cooldown, tidak saat data belum termuat |
| C2 | callback error: koin masuk sekali, cooldown tetap terpasang |
| C3 | `CoinPickup.new(pd)` tanpa callback tetap jalan |
| U1 | teks setiap fase, termasuk hitung mundur yang tidak pernah negatif |
| U2 | teks hasil: menang, kalah, nama mirip (`Ann` bukan `Anna`), seri 5 orang, kosong |

### Tes mutasi

Setiap mutan dipasang di memori (fungsi di tabel kelas diganti), seluruh suite dijalankan, lalu fungsi asli dikembalikan. Setelah semua mutan: 19/19 lagi.

| Mutan | Tertangkap oleh |
|---|---|
| M1 hadiah dibayar sebelum fase berganti, tanpa `pcall` | T11 |
| M2 skor dihitung di luar Round | T4 |
| M3 `Winners` tidak ditulis saat kosong | T4, T8, T10 |
| M4 ronde batal tetap memberi pemenang | T10 |
| M5 seri hanya satu pemenang | T7, T11 |
| M6 callback CoinPickup sebelum cooldown | C2 |

### Regresi

- Suite Hari 3: 36/36 (termasuk `CoinPickup.new(pd)` lama).
- Suite Hari 6: 34/34 (termasuk pengali gamepass di CoinPickup).
- Suite Hari 5 (datamodel Client): 55/55, yaitu 49 cek lama plus 6 cek baris ronde (tersembunyi saat `nil`, tampil dengan teks, di atas Bar, membungkus, warna teks utama).

### Tes live (Play, satu pemain asli)

1. Jam: client mencatat `GetServerTimeNow()` saat `Phase` berganti dari Round ke Result: 0,049 detik setelah `EndsAt` lama.
2. HUD selama Round: `Ronde: 24 detik lagi. Skor kamu: 0`.
3. Pickup saat Intermission: koin 0 menjadi 1, `RoundScore` tetap 0.
4. Pickup saat Round (karakter dipindah ke koin dari server): 3 pickup, koin 1 menjadi 4, `RoundScore = 3`.
5. Result: `Winners` berisi nama akun pemain, `WinningScore = 3`, HUD `Kamu menang! +10 koin (skor 3)`, leaderstats 4 menjadi 14.
6. Setelah Result: Intermission, HUD `Ronde mulai dalam 15 detik`.
7. Atribut diubah dari client (sesi Play baru, Round, skor 1, koin 1): datamodel Client menulis `RoundScore = 999`, `Winners` = nama akunnya sendiri, dan `Phase = "Result"`. Di layar pemain itu HUD langsung menulis `Kamu menang! +10 koin (skor nil)`, karena `WinningScore` tidak ikut diubah. Server tetap membaca `RoundScore = 1`, `Winners` belum ada (belum ada Result di sesi itu), `Phase = "Round"`, koin 1. Tidak ada hadiah.
8. Keluar di tengah ronde (sesi yang sama, Round tersisa 23 detik, skor 1): server memanggil `player:Kick()`. 1,2 detik kemudian daftar pemain kosong dan fase langsung Result dengan `Winners` kosong dan `WinningScore = 0`. Sekitar 6 detik setelahnya fase kembali ke Intermission dengan `EndsAt = 0` (menunggu pemain) dan tetap di situ sampai pengamatan berhenti 10 detik setelah kick. Ini jalur T10 dengan pemain asli.
9. Output: hanya peringatan DataStore yang sudah dikenal, noise `ContentId` lama, pesan kick dari tes 8, dan peringatan "Hadiah ronde gagal" yang memang dipicu tes T11 dan T12. Tidak ada error dari game.

### Device (Device Simulator, teks ronde terpanjang dipaksa)

Teks yang dipaksa ke baris ronde: `Pemenang: WWWWWWWWWWWWWWWWWWWW, WWWWWWWWWWWWWWWWWWWW, WWWWWWWWWWWWWWWWWWWW dan 47 lainnya (skor 120)`. Notice offline juga tampil.

| Preset | Viewport | Area ShopGui | Baris ronde | HUD | Masalah |
|---|---|---|---|---|---|
| Galaxy A06 portrait | 359x718 | 359x660 | 280x88 (4 baris) | (27,8)-(331,178) | tidak ada |
| Galaxy A06 landscape | 705x338 | 705x280 | 280x88 (4 baris) | (200,8)-(504,178) | tidak ada |

Cek per preset: HUD di dalam area aman, semua teks `TextFits`, tombol minimal 44 px. Screenshot dengan teks normal: HUD di tengah atas, jauh dari thumbstick dan tombol lompat.

### Yang belum bisa dites live

Play di Studio hanya satu client. Keluar di tengah ronde dan ronde batal sudah dites live dengan satu pemain (tes 8). Yang berikut butuh dua pemain asli dan hanya dibuktikan dengan tes unit:

- pemain keluar di tengah ronde lalu pemain lain yang menang (T9);
- seri antar pemain asli (T7, T11);
- `MinPlayers = 2`, termasuk ronde batal saat satu dari dua pemain keluar.

Di tes 8, `rounds:removePlayer` di `PlayerRemoving` berjalan tanpa error (Output bersih), tapi efeknya tidak terlihat: dengan satu pemain, ronde berakhir lewat cabang ronde batal yang memang tanpa pemenang, dengan atau tanpa skor dihapus. Efek `removePlayer` hanya dibuktikan oleh T9 dan pembacaan kode.

Untuk mencobanya: Test > Server & Clients dengan 2 pemain.

## 6. Latihan mandiri

1. Ubah aturan seri: pemenang seri berbagi hadiah (10 dibagi rata, dibulatkan ke bawah). Apa yang harus ikut berubah di client?
2. Kenapa server menulis `EndsAt` (waktu absolut) sekali per fase, dan tidak menulis atribut `SecondsLeft` setiap detik?
3. Bisakah pemain yang masuk di tengah ronde menang? Tulis tes unit yang membuktikan jawabanmu.

<details>
<summary>Kunci jawaban</summary>

1. Di `Rounds:_finish`, hitung bagian per pemenang dan tulis sebagai atribut sebelum `_set`, supaya client menampilkan angka yang sama dengan yang dibayar:
   ```lua
   local share = if #winners > 0 then math.floor(Config.Round.WinnerReward / #winners) else 0
   self._status:SetAttribute("Winners", table.concat(names, ","))
   self._status:SetAttribute("WinningScore", best)
   self._status:SetAttribute("Reward", share)
   self:_set("Result", now + Config.Round.ResultSeconds)
   for _, player in winners do
   	local ok, paid = pcall(self._playerData.addCoins, self._playerData, player, share)
   	-- warn seperti sebelumnya
   end
   ```
   Di client, `RoundStatus.text` membaca `round.reward` (dari atribut `Reward`) untuk teks "Kamu menang! +3 koin", bukan `Config.Round.WinnerReward`. Kalau client tetap memakai Config, layar menulis +10 padahal yang dibayar 3. Diuji di Play dengan mutan di memori: seri tiga pemain, masing-masing dibayar 3 dan `Reward = 3`; satu pemenang dibayar 10.

2. Tiga alasan:
   - Satu penulisan per fase, bukan 45 penulisan per ronde yang disalin ke semua client.
   - Sisa detik yang dikirim selalu terlambat sebesar jeda jaringan. Waktu absolut dibandingkan dengan `GetServerTimeNow()` di client tetap tepat.
   - Hitung mundur di client mulus (dicek 5 kali per detik), tidak meloncat mengikuti datangnya paket.

3. Bisa. `onCollected` menghitung siapa pun yang mengambil koin selama Round. `RoundScore` pemain itu masih `nil` sampai pickup pertama, dan client menampilkannya sebagai 0 lewat `or 0`. Tes lengkap, jalankan di datamodel Server saat Play (hasil `true`):
   ```lua
   local Rounds = require(game.ServerScriptService.Server.Rounds)
   local R = require(game.ReplicatedStorage.Shared.Config).Round

   -- Pemain palsu: Rounds hanya memakai Name dan SetAttribute.
   local function fake(name)
   	local p = { Name = name, attrs = {} }
   	function p:SetAttribute(k, v)
   		self.attrs[k] = v
   	end
   	return p
   end
   local paid = {}
   local pd = {} -- PlayerData palsu yang mencatat hadiah
   function pd:addCoins(player, amount)
   	paid[player.Name] = (paid[player.Name] or 0) + amount
   	return true
   end

   local A, B = fake("A"), fake("B")
   local list = { A }
   local st = Instance.new("Folder")
   local r = Rounds.new(pd, st, function()
   	return list
   end)
   r:step(100) -- hitung mundur Intermission mulai
   local t = 100 + R.IntermissionSeconds
   r:step(t) -- Round mulai, hanya A yang ada
   table.insert(list, B) -- B masuk di tengah ronde
   r:onCollected(B)
   r:onCollected(B)
   r:onCollected(A)
   r:step(t + R.RoundSeconds) -- Result
   return st:GetAttribute("Winners") == "B" and paid.B == R.WinnerReward and B.attrs.RoundScore == 2
   ```

</details>
