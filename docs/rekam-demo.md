# Skenario rekam video demo (sekitar 90 detik)

Video ini untuk calon klien: menunjukkan game berjalan, lalu satu percobaan curang yang ditolak server. Semua adegan direkam di Studio, Play solo, place yang belum dipublish. Skenario ini sudah dijalankan sekali di Play dengan pencatat waktu di server; angka di bawah berasal dari jalan uji itu.

## Persiapan (tidak direkam)

1. `rojo serve` di folder repo, plugin Rojo di Studio tersambung.
2. Tutup panel yang tidak perlu supaya viewport game besar. Resolusi rekaman 1280x720 atau lebih.
3. Siapkan perekam layar: Xbox Game Bar (`Win + Alt + R` untuk mulai dan berhenti) atau OBS.
4. Buka Command Bar (View > Command Bar). Dipakai di adegan 6. Saat jalan uji, perintah adegan 6 dijalankan lewat MCP di datamodel Client, bukan lewat Command Bar. Kalau perintah itu jalan di sisi Server, yang berubah adalah cermin `leaderstats` milik server (tes E2E 5 di hari-10). Layarnya terlihat mirip, tapi itu bukan percobaan curang dari client, jadi pastikan tampilan Client yang aktif.
5. Progres tidak disimpan (`DataStatus` `Offline`), jadi setiap Play mulai dari 0 koin. Kalau satu take gagal, Stop lalu Play lagi.

## Rute koin

Lima koin emas di (0, 3, 10), (20, 3, 10), (20, 3, 30), (-20, 3, 30), (-20, 3, 10). Boneka latihan di (0, 2, -20), di arah berlawanan dengan koin. Rute yang dipakai saat uji: koin depan, kanan, kanan jauh, kiri jauh, kiri.

## Daftar adegan

Kolom Waktu adalah perkiraan yang diambil dari jalan uji di bawah, jadi mengikuti pencatat server yang mulai sekitar 8 detik setelah Play, bukan jam video. Ronde berjalan sendiri (Intermission 15 detik, Round 45, Result 6), jadi adegan mengikuti fase, bukan sebaliknya.

| Waktu | Adegan | Yang dilakukan | Yang harus terlihat | Caption (Inggris) |
|---|---|---|---|---|
| 0:00 | 1. Spawn | Play, mulai rekam saat karakter muncul. Diam. | HUD "Ronde mulai dalam N detik", 0 koin, "Mode offline: progres tidak disimpan." | Coin simulator in Luau, synced with Rojo. The server owns every coin. |
| 0:07 | 2. Kumpulkan koin | Tunggu HUD berganti "Ronde: N detik lagi", lalu jalan lewat kelima koin. | Koin hilang begitu disentuh, angka koin naik satu per koin, skor ronde ikut naik. | Coins disappear when collected and come back after 8 seconds. |
| 0:21 | 3. Toko | Keluar dari koin terakhir dulu. Tekan B atau klik "Toko (B)", klik Beli di Sepatu Kilat, lalu Tutup. | Panel menulis "Dimiliki" dan "Sepatu Kilat dibeli.", Mahkota Emas menulis "Kurang N koin". | The client sends an item id. The server checks the price and the balance. |
| 0:35 | 4. Pedang | Jalan ke boneka, tekan 1 untuk memegang Pedang, klik 4 kali dari jarak dekat dengan jeda (cooldown ayunan 0,6 detik; klik yang lebih cepat diabaikan server). | Boneka mati setelah 4 pukulan, koin +5. Boneka muncul lagi sekitar 5 sampai 6 detik kemudian (setelan `DummyRespawn` 5 detik). | Every hit is checked on the server: range, cooldown, rate limit. |
| 0:52 | 5. Hasil ronde | Diam, tunggu fase Result. | "Kamu menang! +10 koin (skor N)", koin +10. | Round loop: intermission, round, result. The winner is paid by the server. |
| 0:58 | (potong) | Intermission 15 detik. Potong di editor, atau biarkan dengan caption. | | |
| 1:05 | 6. Coba curang | Di tab Test pastikan tampilan Client, lalu di Command Bar: `game.Players.LocalPlayer.leaderstats.Coins.Value = 999`. Buka toko, klik Beli di Mahkota Emas. | HUD "999 koin", tombol Mahkota Emas berubah "Beli", lalu pesan "Koin belum cukup untuk Mahkota Emas." Angka 999 tetap di layar. | The client changes its own coin value to 999. The purchase still fails: the server checks its own balance. |
| 1:20 | 7. Nilai asli kembali | Tutup toko, jalan ke koin terdekat yang terlihat. | HUD langsung kembali ke nilai sebenarnya ditambah 1. | The next pickup overwrites the fake value with the server's number. |
| 1:28 | Selesai | Stop rekam, lalu Stop Play. | | |

## Hasil jalan uji (sesi Play kedua)

Detik dihitung dari pencatat server, yang mulai sekitar 8 detik setelah tombol Play ditekan.

| Detik | Kejadian |
|---|---|
| 0,00 | Intermission, sisa 6,6 detik; koin 0; status Offline |
| 6,62 | Round mulai |
| 9,57, 11,78, 14,07, 17,58, 19,73 | lima koin diambil, satu per koin |
| 27,81, 35,88 | +1 tambahan: karakter masih berdiri di koin terakhir saat adegan toko, dan koin itu muncul lagi |
| 32,88 | Sepatu Kilat dibeli lewat klik UI (6 menjadi 1) |
| sekitar 46 sampai 50 | 4 pukulan dari 4,8 stud: boneka 100, 75, 50, 25, 0; +5 pada 49,86 |
| 51,63 | Result, +10 (7 menjadi 17) |
| 57,65 | Intermission |
| 72,66 | Round berikutnya |
| sekitar 75 sampai 80 | client menyetel 999; Mahkota Emas menulis "Beli"; klik memberi "Koin belum cukup untuk Mahkota Emas."; HUD tetap "999 koin", server tetap 17 |
| setelahnya | koin di (0, 3, 10) diambil, HUD menjadi "18 koin" |

Output selama jalan uji hanya berisi baris yang sudah dikenal (peringatan DataStore, noise `ContentId`).

## Catatan saat merekam

- Keluar dari koin sebelum membuka toko. Saat uji, karakter yang tetap berdiri di koin terakhir dibayar lagi tiap koin itu muncul (detik 27,81 dan 35,88), jadi angka di layar bergeser saat adegan toko.
- Ambil koin setelah HUD berganti ke Round. Koin yang diambil saat Intermission tetap dibayar tapi tidak masuk skor ronde, dan ronde tanpa skor berakhir dengan "Ronde selesai. Tidak ada pemenang."
- Klik Beli Sepatu Kilat butuh 5 koin. Kalau satu koin terlewat di rute, ambil koin pertama yang sudah muncul lagi.
- Angka 999 tetap di HUD sampai server mengubah koin lagi. Itu memang bagian yang mau ditunjukkan di adegan 7, jadi jangan menutup adegan 6 dengan pickup.
- Jangan tulis angka koin pasti di caption. Angkanya bergantung pada urutan pickup di tiap take.
- Adegan dua pemain (berebut koin, PvP) butuh Test > Server & Clients dan tidak ada di skenario ini.
