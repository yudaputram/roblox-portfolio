# Hari 8: Combat (pedang dengan validasi server)

File baru: `src/server/Combat.luau`, `src/client/Sword.luau`. Diubah: `src/shared/Config.luau` (`Config.Combat`), `src/server/init.server.luau` (remote `Attack`, perakitan), `src/client/init.client.luau` (`Sword.start`).

## 1. Tujuan

Setiap pemain memegang pedang. Klik atau ketuk untuk mengayun. Kalau ada pemain lain atau boneka latihan dalam jangkauan, target kena 25 damage. Pukulan yang membunuh memberi penyerang 5 koin. Boneka latihan berdiri 20 stud dari titik spawn dan hidup lagi 5 detik setelah mati, jadi pedang bisa dicoba sendirian.

Semua keputusan ada di server: kena atau tidak, berapa damage, siapa dapat koin. Client hanya bilang "saya mengayun, kira-kira ke model ini".

Kalau dari Laravel, bayangkan endpoint `POST /attack` dengan body `{ target_id }`. Controller yang benar tidak membaca `damage` atau `posisi` dari request. Ia memakai middleware `throttle`, mengecek target ada dan boleh diserang (seperti Policy), mengukur jarak dari data miliknya sendiri, lalu menghitung damage dari config. Di JS: jangan pernah percaya `req.body.damage`.

## 2. Konsep inti

### Client mengusulkan, server memutuskan

Remote `Attack` membawa satu argumen: model target, atau `nil` kalau ayunan meleset. Tidak ada damage, posisi, atau waktu di dalamnya. Semua angka itu dibaca server dari `Config.Combat` dan dari posisi karakter yang dilihat server.

Saat client mengirim Instance, yang terkirim adalah referensi. Server menerimanya sebagai objek miliknya sendiri kalau objek itu ada di server. Objek yang hanya dibuat di client tiba sebagai `nil` (tes live 6).

### Urutan cek: dari yang paling murah

| Urutan | Cek | Ditolak dengan |
|---|---|---|
| 1 | ayunan terakhir pemain ini kurang dari 0,6 detik lalu | `Cooldown` |
| 2 | penyerang punya karakter, Humanoid, HumanoidRootPart, dan masih hidup | `Dead` |
| 3 | pedang ada di karakter (sedang dipegang), bukan di Backpack | `NotEquipped` |
| | mulai di sini ayunan sah: waktu dicatat, animasi diputar | |
| 4 | target tidak `nil` | `NoTarget` |
| 5 | target Instance, kelas `Model`, ada di Workspace | `BadTarget` |
| 6 | target karakter pemain aktif atau model bertag `CombatDummy` | `BadTarget` |
| 7 | target bukan karakter sendiri | `Self` |
| 8 | target punya Humanoid dan HumanoidRootPart | `BadTarget` |
| 9 | target masih hidup | `TargetDead` |
| 10 | jarak HumanoidRootPart penyerang ke target paling jauh 9 stud | `TooFar` |

Lolos semua: `TakeDamage(25)`. Kalau nyawa target jadi 0, penyerang dapat 5 koin.

Cek 1 sampai 3 tidak memakai jatah cooldown. Klik ganda pemain jujur dan klik saat pedang masih di Backpack tidak menunda ayunan berikutnya. Mulai cek 4, request memakai jatah walaupun meleset atau ditolak. Exploiter yang mengirim sampah tetap dibatasi satu request yang diperiksa per 0,6 detik.

### Allowlist target

Cek 6 adalah daftar putih: hanya karakter pemain (`Players:GetPlayerFromCharacter`) dan model yang diberi tag oleh server. Tanpa cek ini, model apa pun yang punya Humanoid bisa dipukul, misalnya NPC toko yang mungkin ditambahkan nanti (mutan M7).

Tag dipasang server. Tag yang ditambahkan client tidak tersalin ke server, jadi exploiter tidak bisa menjadikan NPC sebagai target dengan memberi tag sendiri (dibuktikan di latihan 3).

### Jarak diukur dari posisi yang dilihat server

Angka 9 stud diukur di server, dari `Position` HumanoidRootPart kedua karakter. Pedang sekitar 5 stud; sisanya kelonggaran karena target sudah bergerak sedikit saat request sampai.

Tapi posisi karakter pemain dimiliki client (network ownership). Client mengirim posisinya, server menyalinnya. Exploiter yang memindahkan karakternya ke samping target lalu menunggu sebentar akan lolos cek jarak (tes live 10). Cek jarak menghentikan serangan dari jauh tanpa bergerak; ia tidak menghentikan teleport. Repo ini belum memeriksa gerakan karakter di server. Hari 9 memutuskan belum membuatnya; alasannya ada di bagian "Validasi gerak: sengaja belum dibuat" di [hari-09.md](hari-09.md).

### Hadiah kill dibayar tepat sekali

Hadiah hanya dibayar kalau target masih hidup saat dicek (cek 9) dan mati oleh pukulan ini. Di antara cek dan `TakeDamage` tidak ada `task.wait` atau panggilan lain yang bisa yield, jadi tidak ada request lain yang bisa menyela. Pukulan kedua ke target yang sudah mati berhenti di cek 9 (T10, M5).

### Animasi ayunan tanpa aset sendiri

Script `Animate` bawaan karakter memutar animasi tebasan saat ada `StringValue` bernama `toolanim` dengan nilai `"Slash"` di dalam Tool yang dipegang. Server membuatnya di setiap ayunan sah, jadi semua pemain melihat ayunan yang sama. Client hanya menghapus salinannya sendiri; salinan di server tetap ada. Tanpa `task.delay(1, anim.Destroy, anim)`, server menumpuk satu `StringValue` per ayunan (terlihat saat probe: 10 ayunan, 10 objek).

## 3. Penjelasan kode

### `Config.Combat`

```lua
Combat = table.freeze({
	Damage = 25,
	Cooldown = 0.6, -- detik antar ayunan, per pemain
	-- Stud antara HumanoidRootPart penyerang dan target, diukur di server. Pedang sekitar
	-- 5 stud; sisanya kelonggaran karena target sudah bergerak saat request tiba.
	Range = 9,
	KillReward = 5, -- koin; tidak digandakan gamepass 2x Koin, sama seperti hadiah ronde
	DummyRespawn = 5, -- detik setelah boneka latihan mati
}),
```

Hadiah kill tidak dikali pengali gamepass. Gamepass 2x Koin (Hari 6) menggandakan pickup koin saja, sama seperti hadiah ronde di Hari 7. Pengalinya dipasang di `CoinPickup` (`Config.Coin.Reward * multiplier`), bukan di `PlayerData:addCoins`, jadi `Combat` yang memanggil `addCoins` langsung tidak ikut tergandakan. Ini dicek dengan membaca kode; akun tes tidak punya gamepass (ID masih 0).

### `Combat:attack(player, target, now)`

Satu fungsi berisi seluruh tabel di bagian 2. Bentuknya mengikuti `Rounds:step` di Hari 7:

- `target` bertipe `unknown`, karena client exploit bisa mengirim apa saja.
- `now` adalah argumen, bukan dibaca di dalam. Tes memakai jam buatan (1000, 1000.3, 1000.6) tanpa menunggu.
- Fungsi mengembalikan `(kena, alasan)`. Remote handler membuang hasilnya; tes memeriksa alasannya satu per satu.

```lua
local last = self._lastSwing[player]
if last and now - last < Config.Combat.Cooldown then
	return false, "Cooldown"
end
-- ... cek penyerang dan pedang ...
self._lastSwing[player] = now
playSlash(sword)

if target == nil then
	return false, "NoTarget"
end
if typeof(target) ~= "Instance" or not target:IsA("Model") or not target:IsDescendantOf(Workspace) then
	return false, "BadTarget"
end
if not (Players:GetPlayerFromCharacter(target) or target:HasTag(DUMMY_TAG)) then
	return false, "BadTarget"
end
```

`typeof(target) ~= "Instance"` harus dicek lebih dulu. Memanggil `:IsA` pada string atau angka langsung error, dan error di handler remote membuat request itu berhenti di tengah. `IsDescendantOf(Workspace)` menolak model yang disimpan di ReplicatedStorage. `Tool` juga turunan `Model`, jadi pedang sendiri lolos cek kelas; ia berhenti di allowlist.

```lua
targetHumanoid:TakeDamage(Config.Combat.Damage)
if targetHumanoid.Health > 0 then
	return true, "Hit"
end
self._playerData:addCoins(player, Config.Combat.KillReward)
return true, "Kill"
```

`addCoins` mengembalikan `false` kalau data penyerang belum termuat. Kill tetap terjadi, hanya koinnya tidak masuk (T11).

### Pedang dan boneka dibuat oleh server

`makeSword()` membuat `Tool` bernama `Pedang` dengan satu `Handle` dari kode. Tidak ada aset atau file model; seluruh game tetap berupa Luau di `src/` yang bisa direview, sama seperti `Koin`, `Remotes`, dan `RoundState` di hari sebelumnya.

Backpack diganti baru setiap kali karakter spawn, jadi pedang diberikan ulang lewat `CharacterAdded`:

```lua
function Combat:addPlayer(player: Player)
	self._characterAdded[player] = player.CharacterAdded:Connect(function()
		self:giveSword(player)
	end)
	if player.Character then
		self:giveSword(player)
	end
end
```

`giveSword` tidak memberi pedang kedua kalau pedang sudah ada di Backpack atau di tangan. Kedua jalur di atas bisa jalan untuk karakter yang sama. Koneksi disimpan supaya `removePlayer` bisa memutusnya saat pemain keluar.

Alternatif yang lebih pendek: taruh Tool di StarterPack, dan Roblox menyalinnya ke Backpack setiap spawn. Kode server dipilih karena aturan "siapa boleh memegang pedang" bisa ditambah nanti di satu tempat, misalnya hanya saat Round.

`spawnDummy()` membuat model `BonekaLatihan`: HumanoidRootPart dan Head yang di-anchor, Humanoid, dan tag `CombatDummy`. Saat `Died`, boneka dihapus dan dibuat ulang setelah `DummyRespawn` detik.

### Perakit (`init.server.luau`)

```lua
local attack = makeRemote(remotes, "Attack") -- client -> server: (target: Model?), tanpa balasan
-- ...
local combat = Combat.new(playerData)
combat:start(attack)
```

`combat:addPlayer(player)` dipanggil di `onPlayerAdded`, `combat:removePlayer(player)` di `PlayerRemoving` sebelum `playerData:unload`. Remote ini tidak punya balasan. Hasil serangan terlihat dari nyawa target dan koin, yang memang sudah tersalin dari server.

### Client: `Sword.pickTarget` dan `Sword.start`

```lua
function Sword.pickTarget(character: Model): Model?
	-- part dalam radius Range di sekitar HumanoidRootPart sendiri, karakter sendiri dikecualikan
	for _, part in Workspace:GetPartBoundsInRadius(root.Position, Config.Combat.Range, params) do
		local model = part:FindFirstAncestorOfClass("Model")
		-- model dengan Humanoid hidup dan HumanoidRootPart, ambil yang terdekat
	end
	return best
end
```

Client memilih model hidup terdekat dalam 9 stud dan mengirimnya. Ini hanya usulan; server mengecek semuanya lagi. Client tidak memakai `.Touched` pada pedang, karena sentuhan dilaporkan oleh pemilik fisika (client) dan sering terlewat saat pedang bergerak cepat.

`Sword.start` menghubungkan `Tool.Activated` sekali per pedang. Pedang baru dibuat setiap spawn, dan pindah antara Backpack dan karakter setiap kali dipegang atau dilepas. Tabel `hooked` (kunci lemah) mencegah koneksi ganda pada pedang yang sama tanpa menahan pedang lama di memori.

## 4. Jebakan dan celah yang ditutup

- Percaya damage, posisi, atau hasil dari client. Remote hanya membawa target; sisanya dibaca server.
- Tanpa cek jarak, client bisa memukul dari mana saja (M1, tes live 2).
- Tanpa cooldown server, spam 50 request memberi 50 pukulan (M2, tes live 4). Cooldown di client saja tidak cukup: exploiter memanggil `FireServer` langsung.
- Request yang ditolak cooldown memperbarui waktu terakhir. Klik ganda pemain jujur lalu menunda ayunan berikutnya (M3, T2).
- Tanpa cek diri sendiri, pemain bisa memukul karakternya sendiri (M4, T5).
- Hadiah dibayar setiap kali nyawa 0 setelah pukulan, tanpa cek target masih hidup. Memukul mayat boneka membayar terus (M5, T10).
- Tanpa cek pedang dipegang, exploiter bisa memukul dengan pedang di Backpack (M6, T8).
- Tanpa allowlist, model apa pun dengan Humanoid bisa jadi target (M7, T7). Sebaliknya, allowlist yang hanya menerima boneka bertag membuat pedang tidak bisa memukul pemain lain (M9, T14).
- Jatah cooldown diambil sebelum cek pedang. Request saat pedang belum dipegang menunda ayunan pertama (M8, T8).
- Referensi karakter lama setelah respawn. Model lama sudah tidak di Workspace dan bukan karakter pemain mana pun, jadi ditolak `BadTarget` (tes respawn).
- `toolanim` menumpuk di server kalau tidak dihapus.
- Klik tombol toko saat pedang dipegang. Diukur: klik pada GUI tidak memicu `Activated`, jadi pedang tidak perlu dimatikan saat toko terbuka (tes live 11).
- Celah yang masih ada: teleport. Posisi penyerang dimiliki client, jadi exploiter bisa pindah ke samping target lalu menyerang (tes live 10). Celah yang sama dengan pickup koin di Hari 7. Belum ditutup; Hari 9 memutuskan cek kecepatan gerak di server belum dibuat (lihat [hari-09.md](hari-09.md)).
- Celah yang masih ada: arah dan halangan. Server tidak mengecek arah hadap atau dinding di antara penyerang dan target. Latihan 1 menambahkan cek arah.
- Farming boneka. Satu kill butuh 4 pukulan, pada detik 0; 0,6; 1,2; dan 1,8. Boneka hidup lagi 5 detik setelah mati, jadi hasilnya 5 koin per 6,8 detik, sekitar 0,74 koin per detik. Pickup koin memberi paling banyak 1 koin per detik (cooldown 1 detik), atau 2 dengan gamepass 2x Koin. Boneka tidak lebih menguntungkan dari koin.
- Dua pemain bisa saling bunuh bergantian untuk koin. Belum dibatasi.

## 5. Bukti tes

Gate: `selene src` 0 error 0 warning, `stylua --check src` lolos, sinkronisasi Rojo `SYNC OK 16 script`.

### Tes unit (datamodel Server saat Play)

`Combat.new` dengan PlayerData palsu, pemain asli yang HumanoidRootPart-nya di-anchor di (80, 5, 80), dan boneka buatan tes yang diletakkan relatif terhadap pemain. Jam disuntik. Hasil: 14/14 lolos.

| Tes | Yang dibuktikan |
|---|---|
| T1 | pukulan sah 5 stud: `Hit`, nyawa 100 menjadi 75, tidak ada koin |
| T2 | t=1000 `Hit`, t+0,3 dan t+0,59 `Cooldown`, t+0,6 `Hit`; nyawa 50 |
| T3 | cooldown per pemain: penyerang kedua (table palsu dengan karakter berpedang) bisa memukul 0,1 detik kemudian |
| T4 | 8,9 stud `Hit`, 9,1 stud dan 60 stud `TooFar`, nyawa target jauh tetap 100 |
| T5 | target karakter sendiri: `Self`, nyawa sendiri tetap |
| T6 | target nyawa 0: `TargetDead`, tidak ada koin |
| T7 | 15 argumen sampah: `nil` jadi `NoTarget`; string, angka, NaN, table, table mirip model, Baseplate, Model tanpa Humanoid, Humanoid tanpa tag, boneka di ReplicatedStorage, objek Player, Tool pedang sendiri, Workspace, Humanoid langsung, part boneka semuanya `BadTarget`; tidak ada nyawa berkurang, tidak ada koin |
| T8 | pedang di Backpack: `NotEquipped`; setelah dipegang, 0,1 detik kemudian `Hit` (jatah cooldown tidak terpakai) |
| T9 | penyerang tanpa karakter, mati, atau tanpa HumanoidRootPart: `Dead` |
| T10 | lima pukulan: Hit, Hit, Hit, Kill, TargetDead; `addCoins` dipanggil sekali dengan 5 untuk penyerang |
| T11 | `addCoins` mengembalikan `false`: tidak error, hasil tetap `Kill` |
| T12 | `removePlayer` menghapus cooldown (pukulan 0,1 detik kemudian `Hit`) dan memutus koneksi `CharacterAdded`; `addPlayer` saat pedang sudah ada tidak menambah pedang |
| T13 | `giveSword` dua kali saat dipegang dan sekali saat di Backpack: tetap 1 pedang |
| T14 | target karakter pemain asli, penyerang table palsu berpedang 5 stud darinya: `Hit`, nyawa pemain 100 menjadi 75 |

Setelah ayunan sah, pedang berisi `toolanim` dengan nilai `Slash`.

### Tes mutasi

Setiap mutan adalah salinan `attack` dengan satu aturan dimatikan, dipasang di memori, lalu seluruh suite dijalankan. Salinan tanpa perubahan lolos 14/14 sebagai kontrol. Setelah semua mutan, fungsi asli dikembalikan: 14/14 lagi.

| Mutan | Tertangkap oleh |
|---|---|
| M1 tanpa cek jarak | T4 |
| M2 tanpa cooldown | T2 |
| M3 request yang ditolak memperbarui waktu | T2 |
| M4 tanpa cek diri sendiri | T5 |
| M5 hadiah tanpa cek target masih hidup | T6, T10 |
| M6 tanpa cek pedang dipegang | T8 |
| M7 tanpa allowlist target | T7 |
| M8 jatah cooldown diambil sebelum cek pedang | T8 |
| M9 allowlist hanya boneka bertag (tanpa karakter pemain) | T14, juga T5 (karakter sendiri jadi `BadTarget`, bukan `Self`) |

### Respawn (datamodel Server)

- `LoadCharacterAsync` 5 kali, dicek 1 detik setelah setiap spawn: tepat 1 pedang di Backpack dan karakter, kelima kalinya.
- Karakter dari sebelum respawn dipakai sebagai target: `Parent` sudah `nil`, `GetPlayerFromCharacter` `nil`, hasil `BadTarget`. Kontrol dengan karakter baru dan boneka 5 stud: `Hit`, nyawa 75.

### Tes live (Play, satu pemain asli, lewat remote `Attack` sungguhan)

Server memasang koneksi kedua ke `Attack.OnServerEvent` yang mencatat setiap request dan jarak yang dilihat server saat request tiba, plus pencatat nyawa boneka. Client memindahkan karakternya sendiri dan memanggil `FireServer`.

1. Saat masuk: 1 pedang. Boneka ada, nyawa 100, bertag `CombatDummy`.
2. Dari jauh: di 15 stud client masih melihat boneka (jarak di client 15,1) dan mengirimnya; server mencatat jarak 15,1, nyawa tetap 100. Di 100 stud boneka masih ada di client; server mencatat 100,0, nyawa tetap 100.
3. Dekat: server mencatat 5,1 stud, nyawa 75.
4. Spam: 50 `FireServer` dalam satu loop. Server menerima ke-50-nya pada detik yang sama; nyawa hanya turun sekali, ke 50. Satu request 0,7 detik kemudian: 25. Total 54 request diterima, 3 pukulan masuk.
5. `toolanim` di pedang pada sisi server setelah semua ayunan itu: 0.
6. 13 argumen yang diutak-atik: tanpa argumen, string, angka, NaN, table, Workspace, Baseplate, objek Player, part boneka, Humanoid boneka, karakter sendiri, Tool pedang, dan model buatan client yang diberi Humanoid dan tag di client. Server menerima ke-13-nya; model buatan client tiba sebagai `nil`. Nyawa boneka tetap 25, nyawa pemain tetap 100.
7. Jalur client asli: `Sword.pickTarget` di 5 stud mengembalikan `Workspace.BonekaLatihan`. `sword:Activate()` dari client memutar track `ToolSlashAnim` (aset 522635514) di Animator pemain dan menghabisi boneka (nyawa 0). Setelah itu `pickTarget` mengembalikan `nil` untuk boneka mati, dan juga `nil` di 30 stud.
8. Hadiah kill: pengukuran pertama menunjukkan koin 0 menjadi 6. Satu koin ekstra berasal dari pickup: titik tes 30 stud tepat berada di posisi `Koin` (0, 3, 10). Diulang dengan pencatat perubahan koin dan karakter di 5 stud dari boneka, jauh dari koin: 4 pukulan, satu perubahan koin `+5` (16 menjadi 21) saat fase Round.
9. Respawn boneka: mati pada detik 93,33, boneka baru muncul pada 98,35 (5,02 detik), nyawa 100, bertag, hanya ada satu `BonekaLatihan`.
10. Teleport (celah yang diketahui): karakter dipindah dari client ke 100 stud, lalu ke 5 stud.
    - Kirim di frame yang sama: server masih mencatat 100,0 stud, ditolak.
    - Tunggu 0,3 detik: server mencatat 20,5 stud (posisi masih bergerak menuju titik baru), ditolak.
    - Tunggu 1 detik: server mencatat 5,1 stud, diterima, nyawa 75.
11. Klik GUI dengan pedang dipegang (`user_mouse_input` di datamodel Client). Kontrol: klik di area 3D sebelum tes menaikkan hitungan `Activated` jadi 1. Klik tombol Toko membuka panel; klik judul panel, tombol Mahkota Emas yang nonaktif (koin kurang), dan area kosong panel; lalu klik Tutup. Hitungan tetap 1. Klik area 3D setelahnya: 2.
12. Output: hanya peringatan DataStore yang sudah dikenal dan noise `ContentId` lama. Tidak ada error dari `Combat` atau `Sword`.

Di sesi yang sama, perakit lama tetap jalan: pickup koin +1 (tes 8), HUD ronde dan panel toko buka-tutup (tes 11). Di antara dua pengukuran koin naik dari 6 ke 16, sama dengan hadiah ronde 10, dan `Winners` saat itu berisi nama akun pemain; momen pembayarannya sendiri tidak dicatat. Modul hari sebelumnya tidak diubah hari ini, jadi suite unitnya tidak dijalankan ulang; regresi menyeluruh dijalankan di Hari 10 ([hari-10.md](hari-10.md)).

### Yang belum bisa dites live

- Pertarungan antar pemain asli: Play di Studio hanya satu client. Memukul karakter pemain hanya dibuktikan di tes unit T14 (penyerang palsu, target karakter pemain asli) dan mutan M9. Untuk mencobanya: Test > Server & Clients dengan 2 pemain.
- Ketukan layar sentuh untuk mengayun: Device Simulator di Studio ini tidak bisa mengirim ketukan.
- Bentuk pedang di tangan: layar terkunci saat tes, jadi viewport 3D tidak tergambar. Data dari server: `RightGrip` terpasang dan sumbu panjang bilah searah arah hadap karakter (dot 1,00).

## 6. Latihan mandiri

1. Tambahkan cek arah: target hanya kena kalau berada di depan penyerang (sudut sekitar 70 derajat ke kiri dan kanan). Di mana cek itu sebaiknya diletakkan dalam `Combat:attack`, dan kenapa?
2. Mutan M3 membuat request yang ditolak cooldown ikut memperbarui `_lastSwing`. Exploiter yang spam tidak diuntungkan. Lalu siapa yang dirugikan?
3. Exploiter memberi tag `CombatDummy` pada model NPC (punya Humanoid, tanpa tag) di client-nya, lalu mengirim model itu ke remote `Attack` dari 5 stud. Apa yang terjadi?

<details>
<summary>Kunci jawaban</summary>

1. Letakkan setelah cek `TooFar`, tepat sebelum `TakeDamage`. Cek arah lebih mahal sedikit dan hanya berarti untuk target yang sah dan dekat. Beda tinggi diabaikan supaya target yang lebih tinggi atau lebih rendah tetap bisa kena:
   ```lua
   local function inFront(root: BasePart, targetRoot: BasePart): boolean
   	-- Abaikan beda tinggi: yang dicek hanya arah di bidang datar.
   	local flat = (targetRoot.Position - root.Position) * Vector3.new(1, 0, 1)
   	return flat.Magnitude < 0.1 or root.CFrame.LookVector:Dot(flat.Unit) >= 0.3
   end
   ```
   Di `attack`: `if not inFront(root, targetRoot) then return false, "Behind" end`. Nilai 0,3 adalah cos sekitar 72 derajat. Diuji di Studio dengan Part yang menghadap -Z: target di depan `true`, di belakang `false`, tepat di samping `false`, depan agak serong `true`, posisi sama `true`.

   Arah hadap juga dikirim oleh client (bagian dari CFrame karakter), jadi cek ini menahan pemain jujur yang salah arah dan script sederhana, bukan exploiter yang memutar karakternya.

2. Pemain jujur. Klik ganda cepat (dua klik dalam 0,3 detik) membuat klik kedua ditolak dan sekaligus menggeser waktu terakhir ke klik kedua. Ayunan berikutnya baru boleh 0,6 detik setelah klik kedua, bukan setelah ayunan yang benar-benar terjadi. Pedang terasa macet. T2 menangkap ini: setelah request 0,3 detik ditolak, request pada 0,6 detik harus tetap diterima.

3. Ditolak `BadTarget`, nyawa NPC tetap. Tag yang ditambahkan client hanya ada di client itu. Server menerima referensi ke model yang sama, tapi `HasTag("CombatDummy")` di server tetap `false`. Diuji di Play: server membuat NPC tanpa tag 5 stud dari pemain, client memanggil `npc:AddTag("CombatDummy")` lalu `FireServer(npc)`. Di client `HasTag` `true`; server mencatat `HasTag` `false`, nyawa NPC 100.

</details>
