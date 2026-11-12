# Hari 1: Koin pertama dan leaderstats

File: `src/server/init.server.luau`, `src/client/init.client.luau` (commit `f9fbfa2`).

## 1. Tujuan

Bikin satu Part kuning bernama "Koin". Kalau pemain menyentuhnya, angka Coins di papan skor naik 1. Client cuma menampilkan perubahan di Output.

Analogi Laravel: server Roblox itu seperti controller + database kamu, client itu seperti browser. Browser boleh menampilkan saldo, tapi yang mengubah saldo selalu server. Di Roblox aturannya lebih keras lagi, karena pemain bisa memodifikasi client-nya sendiri (exploit). Anggap semua yang datang dari client sebagai input form yang belum divalidasi.

## 2. Konsep inti

### Script dan LocalScript

`init.server.luau` jadi `Script` (jalan di server), `init.client.luau` jadi `LocalScript` (jalan di komputer tiap pemain). Rojo menentukan jenisnya dari akhiran nama file.

### Services

Fitur engine diambil lewat `game:GetService("Players")`, `game:GetService("RunService")`, dan seterusnya. Mirip `app(Service::class)` di Laravel.

### Instance dan Parent

Objek di game (Part, Folder, IntValue) adalah `Instance`. Objek baru belum ada di dunia game sampai `Parent`-nya di-set ke sesuatu di dalam `game`.

```lua
local part = Instance.new("Part")
part.Size = Vector3.new(2, 2, 2)
part.Parent = workspace -- baru muncul di dunia pada baris ini
```

### Event

`part.Touched:Connect(fungsi)` itu seperti `addEventListener`. Fungsinya dipanggil tiap kali ada bagian tubuh yang mulai bersentuhan dengan part.

### leaderstats

Folder bernama persis `leaderstats` di dalam objek `Player` otomatis tampil di papan skor kanan atas. Isinya `IntValue` atau `NumberValue`.

## 3. Penjelasan kode

### leaderstats dibuat dulu, Parent paling akhir

Folder `leaderstats` diisi `Coins`, baru setelah itu `stats.Parent = player`. Kalau urutannya dibalik, client bisa menerima folder kosong dulu lalu `Coins` menyusul. Dengan Parent terakhir, objek dikirim ke client sekali dalam keadaan lengkap.

### Loop `Players:GetPlayers()` setelah `PlayerAdded:Connect`

Di Studio, pemain kadang sudah masuk sebelum script server selesai start. Event `PlayerAdded` untuk pemain itu sudah lewat, jadi tanpa loop ini dia tidak dapat leaderstats. Pola "connect event, lalu proses yang sudah ada" akan sering kamu lihat.

### `GetPlayerFromCharacter(hit.Parent)`

`Touched` memberi bagian tubuh yang menyentuh (kaki, tangan, kepala). Parent-nya adalah model karakter, dan dari karakter kita cari `Player`-nya. Kalau yang menyentuh Part lain, hasilnya `nil` dan diabaikan. `Handle` aksesori (topi, rambut) juga memicu `Touched`, tapi parent-nya `Accessory`, bukan karakter, jadi ikut diabaikan. Itu aman di sini, tapi ingat kalau suatu saat kamu butuh deteksi yang lebih teliti.

### Cooldown per pemain

`cooling[player] = true`, lalu `task.delay(1, ...)` menghapusnya. Satu kali masuk ke koin memicu belasan event `Touched` dalam sepersekian detik (tiap bagian tubuh satu event, lihat bukti tes), jadi tanpa cooldown satu kali masuk bisa memberi belasan koin. Cooldown-nya per pemain: kalau pakai satu variabel `debounce` untuk semua orang, pemain A yang sedang menyentuh akan memblokir pemain B.

### `PlayerRemoving` membersihkan tabel

Tabel yang key-nya objek `Player` menahan objek itu di memori. Pemain keluar, entrinya dihapus.

### Client hanya menunggu lalu print

`leaderstats` dibuat server dan butuh waktu sampai di client, jadi client memakai `WaitForChild`. Client tidak pernah menulis `coins.Value`. Kalaupun ditulis, perubahannya hanya ada di layar pemain itu dan tidak dikirim ke server.

## 4. Jebakan umum

- Koin bisa di-farm. Koin tidak pernah hilang, jadi pemain yang jalan bolak-balik menembus koin dapat sekitar 1 koin per detik (dibatasi cooldown). Di tes, cara ini memberi +8 dalam 10 detik. Catatan awal kurikulum menyebut koin juga naik tiap detik selama pemain berdiri di dalam part. Di tes MCP hari ini (jalan masuk lalu diam 15 detik) itu tidak terulang: koin hanya naik sekali. Di Hari 9 (tes live L1) itu terulang: berdiri di dalam koin memberi pickup kira-kira tiap 3,8 detik. Diperbaiki di Hari 10: koin hilang setelah diambil lalu muncul lagi 8 detik kemudian. Pemain yang berdiri di dalam koin kini dibayar sekali tiap koin muncul, dan farm 10 detik yang sama memberi +2, bukan +8. Lihat [hari-10.md](hari-10.md).
- Mengubah nilai dari LocalScript. Pemula sering menulis `coins.Value += 1` di LocalScript. Di layar sendiri angkanya naik, tapi server dan pemain lain tidak melihatnya. Tes negatif di bawah membuktikannya.
- Memakai `wait()`, `spawn()`, `delay()` versi lama. Pakai `task.wait`, `task.spawn`, `task.delay`.

## 5. Bukti tes (Studio MCP, Play solo)

Tes 1 sampai 3 berjalan dalam satu sesi Play, tes 4 di sesi Play baru.

Semua langkah dijalankan lewat MCP `Roblox_Studio`. Sinkron Rojo dicek dulu: `Baseplate.Size` di Studio = 512, 20, 512 (sama dengan `default.project.json`) dan panjang source `Server` = 1870 karakter, sama dengan file di repo.

1. Positif. `character_navigation` (Client) berjalan ke `game.Workspace.Koin`. Dibaca dari Server: `Coins = 1`, jarak ke koin 0,8 stud.
2. Negatif. Di datamodel Client: `leaderstats.Coins.Value = 999`. Client membaca 999 dan Output client mencetak `Koin kamu: 999`. Dibaca dari Server: tetap `1`. Begitu server mengubah Coins lagi, client ditimpa nilai server (`Koin kamu: 2`).
3. Farming. Server memindahkan karakter masuk dan keluar koin tiap 0,25 detik selama 10 detik. Hasil: Coins 2 jadi 10 (+8).
4. Diam di dalam koin (sesi Play baru). Koneksi `Touched` sementara di server mencatat waktu, nama part, `ClassName` parent, dan apakah `GetPlayerFromCharacter` menemukan pemain. Karakter berjalan masuk lewat `character_navigation` (tanpa teleport, `WalkSpeed` normal), lalu diam 15 detik. Hasil: 16 event `Touched`, semuanya antara detik 4,47 dan 4,80. Event pertama dari `Handle` dengan parent `Accessory` (pemain tidak ditemukan, diabaikan), sisanya bagian tubuh dengan parent `Model`. Coins 0 jadi 1 saat masuk, dan tetap 1 sampai 15 detik kemudian.
5. Output tidak berisi error dari script kita. Baris `ContentId: rbxassetid://203785492 failed ...` sudah muncul sebelum kode kita jalan (dari place/Studio).
6. Gate statis: `selene src` 0 error 0 warning, `stylua --check src` lolos.

Catatan: satu tes awal (karakter diteleport server ke dalam koin dengan `WalkSpeed = 0`) sempat mencatat 0 jadi 2 dalam 3,5 detik. Penyebab kenaikan kedua belum terbukti dan tidak terulang di tes 4.

## 6. Latihan mandiri

1. Ubah koin supaya memberi 5 Coins, tapi hanya untuk pemain yang akunnya lebih dari 30 hari. Sisanya tetap 1.
   Petunjuk: lihat properti `Player.AccountAge`.
2. Tambahkan stat kedua `Touches` di leaderstats yang menghitung berapa kali pemain mengambil koin.
   Petunjuk: buat di `onPlayerAdded` seperti `Coins`, dan ingat aturan Parent paling akhir.
3. Buat koin berputar pelan di tempat. Kenapa ini sebaiknya dilakukan di client, bukan di server?
   Petunjuk: `RunService.Heartbeat` memberi `dt` (detik sejak frame sebelumnya), dan `CFrame.Angles` membuat rotasi.

<details>
<summary>Kunci jawaban</summary>

1. Di handler `Touched`, setelah dapat `player`: `local amount = if player.AccountAge > 30 then 5 else 1`, lalu `coins.Value += amount`. Hitungannya tetap di server.
2. Di `onPlayerAdded` buat `IntValue` kedua bernama `Touches` dan Parent ke `stats` sebelum `stats.Parent = player`. Di handler tambahkan `touches.Value += 1` di tempat yang sama dengan `coins.Value += 1`.
3. Di LocalScript:
   ```lua
   local RunService = game:GetService("RunService")
   local koin = workspace:WaitForChild("Koin")
   RunService.Heartbeat:Connect(function(dt)
       koin.CFrame *= CFrame.Angles(0, math.rad(90) * dt, 0)
   end)
   ```
   Putaran hanya efek visual. Kalau server yang memutar, perubahan CFrame tiap frame dikirim ke semua pemain dan memakan bandwidth, dan di client gerakannya juga lebih halus. Posisi koin di server tidak berubah, jadi `Touched` di server tetap bekerja.

</details>
