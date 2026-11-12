# Kurikulum scripter Roblox (Hari 1 sampai 10)

Satu game kecil "simulator koin" yang tumbuh tiap hari. Tiap dokumen menjelaskan tujuan, konsep, alasan di balik kode, jebakan, bukti tes, dan latihan.

| Hari | Topik | Dokumen |
|---|---|---|
| 1 | Koin pertama, leaderstats, Touched + cooldown | [hari-01.md](hari-01.md) |
| 2 | RemoteEvent dan toko server-authoritative | [hari-02.md](hari-02.md) |
| 3 | ModuleScript dan OOP (refactor) | [hari-03.md](hari-03.md) |
| 4 | DataStore: load, save, session lock | [hari-04.md](hari-04.md) |
| 5 | UI toko | [hari-05.md](hari-05.md) |
| 6 | Monetisasi: gamepass dan developer product | [hari-06.md](hari-06.md) |
| 7 | Sistem ronde (state machine) | [hari-07.md](hari-07.md) |
| 8 | Combat: pedang dengan validasi server | [hari-08.md](hari-08.md) |
| 9 | Anti-exploit dan performa | [hari-09.md](hari-09.md), [keamanan-checklist.md](keamanan-checklist.md) |
| 10 | Koin respawn, regresi semua hari, portofolio | [hari-10.md](hari-10.md), [rekam-demo.md](rekam-demo.md) |

## Cara pakai

1. Jalankan `rojo serve` di folder repo, buka Studio, connect plugin Rojo.
2. Baca dokumen hari itu, lalu buka kodenya di `src/`.
3. Kerjakan latihan di akhir dokumen sebelum membuka kunci jawaban.

Gate sebelum commit: `selene src` (0 error, 0 warning) dan `stylua --check src`.
