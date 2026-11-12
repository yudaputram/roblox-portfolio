# Checklist keamanan untuk review kode Roblox

Dipakai saat mereview kerjaan klien atau kode sendiri sebelum rilis. Setiap butir berisi pertanyaan, cara mengeceknya, dan contoh gagal yang pernah dibuktikan di repo ini. Jawaban "tidak tahu" dihitung "tidak".

Perintah di bawah jalan di Git Bash dari root repo. Ganti `src` dengan folder script klien.

## 0. Inventaris dulu (sekitar 10 menit)

```bash
grep -rn "OnServerEvent\|OnServerInvoke" src                  # pintu masuk dari client
grep -rn "FireClient\|FireAllClients\|InvokeClient" src         # yang dikirim server ke client
grep -rn "\.Touched\|ProcessReceipt\|Prompt.*PurchaseFinished" src
grep -rn "RemoteEvent\|RemoteFunction\|UnreliableRemoteEvent" src
grep -rn "\[Player\]" src                                       # state per pemain
grep -rn "PlayerRemoving" src                                    # tempat state itu dibersihkan
```

Isi satu baris per jalur:

| Jalur | Arah | Argumen dari client | Validasi | Batas | Dibersihkan di |
|---|---|---|---|---|---|

Contoh lengkap: tabel kontrak di `hari-09.md` bagian 2. Jalur yang tidak bisa diisi kolom validasinya adalah temuan pertama.

## 1. Remote

1. Apakah server menghitung sendiri setiap hasil (harga, damage, hadiah, posisi), bukan membacanya dari argumen?
   - Cek: baca parameter setiap handler. Nama seperti `price`, `damage`, `amount`, `reward`, `position`, `hitPart` adalah tanda bahaya.
   - Di repo ini: `BuyItem` hanya membawa `itemId`; harga dari `Config.Items` (Hari 2). `Attack` hanya membawa target (Hari 8).

2. Apakah tipe setiap argumen dicek sebelum dipakai, termasuk `nil`, NaN, table, string sangat panjang, dan Instance?
   - Cek: baris pertama handler harus `type(x) ~= "string"` atau `typeof(x) ~= "Instance"`. Memanggil `:IsA` pada string langsung error.
   - Contoh: suite Hari 3 (`nil`, angka, NaN, table, Instance, string 10.000 huruf) dan T7 Hari 8 (15 argumen sampah).

3. Kalau argumennya Instance: apakah kelas, lokasi (`IsDescendantOf`), dan izinnya (tag dari server, pemilik) dicek?
   - Contoh gagal: mutan M7 Hari 8, tanpa allowlist model apa pun yang punya Humanoid bisa dipukul.

4. Apakah ada rate limit per pemain, per remote, di depan semua validasi?
   - Cek: spam 50 request dari client dalam satu loop, hitung yang diproses server.
   - Contoh gagal: mutan N3 Hari 9 (`Attack` tanpa rate limit, tertangkap C1). Bucket tanpa batas kapasitas (N1) dan bucket yang mengurangi token saat menolak (N2).

5. Apakah handler yield (`...Async`, `WaitForChild`, `task.wait`) di antara cek dan penulisan state?
   - Cek: di setiap handler, cari panggilan yield sebelum state diklaim. Request kedua dari pemain yang sama bisa masuk saat yang pertama menunggu.
   - Contoh: R14 Hari 6, receipt yang sama datang lagi saat save pertama masih berjalan. Combat (Hari 8) tidak punya yield di antara cek nyawa dan `TakeDamage`.

6. Apakah balasan dikirim hanya ke pemain yang bersangkutan dengan isi minimal?
   - Cek: `FireAllClients` yang membawa data pribadi adalah temuan. `BuyResult` memakai `FireClient` dan hanya membalas alasan yang wajar untuk pemain jujur.

7. Apakah ada `InvokeClient` dari server?
   - Harus tidak ada. Client yang error, keluar, atau tidak menjawab membuat server error atau menunggu selamanya.

## 2. Ekonomi dan pembelian

1. `ProcessReceipt`: dipasang sekali, sebelum ada yield; aman dipanggil dua kali untuk `PurchaseId` yang sama; data disimpan sebelum mengembalikan `PurchaseGranted`; `NotProcessedYet` kalau ragu?
   - Contoh: R1 sampai R14 Hari 6 (ID sama tidak dobel, simpan gagal, pemain keluar, dua server).

2. Gamepass: kepemilikan dicek di server dengan `UserOwnsGamePassAsync` (pakai retry), dan `PromptGamePassPurchaseFinished` hanya dipercaya di server?
   - Dokumentasi `MarketplaceService`: di server, `wasPurchased` adalah hasil akhir pembelian; di client tidak boleh dipakai untuk logika.

3. Apakah setiap hadiah dibayar tepat sekali?
   - Contoh gagal: mutan M5 Hari 8 (hadiah kill dibayar setiap pukulan ke mayat). T6 Hari 7 (hadiah ronde tidak dibayar ulang selama fase Result).

4. Apakah pengali (2x Koin, VIP) dipasang di satu tempat saja?
   - Di repo ini hanya di `CoinPickup`. Hadiah kill dan ronde sengaja tidak digandakan (Hari 8).

## 3. Data

1. Apakah setiap panggilan DataStore dibungkus `pcall`, dan load yang gagal tidak diperlakukan sebagai pemain baru?
   - Contoh: Hari 4. Load gagal membuat sesi tidak disimpan, supaya data kosong tidak menimpa data asli.

2. Apakah ada session lock, save lewat `UpdateAsync`, autosave, dan `BindToClose`?
   - Cek: `grep -rn "SetAsync" src` pada key pemain harus punya alasan yang jelas.

3. Key berdasarkan `UserId`, bukan nama?

## 4. Fisika, posisi, dan sentuhan

1. Apakah jarak dan posisi dihitung dari posisi yang dilihat server?
   - Contoh gagal: mutan M1 Hari 8, tanpa cek jarak pedang mengenai boneka dari 60 stud.

2. Apakah handler `Touched` yang memberi hadiah punya cooldown per pemain dan cek jarak?
   - `Touched` dilaporkan oleh client pemilik fisika karakter. Cek jarak: latihan 3 Hari 9.

3. Apakah ada validasi gerak (teleport, kecepatan)?
   - Kalau tidak ada, tulis sebagai risiko yang diketahui, jangan dianggap aman. Repo ini belum punya: tes live 10 Hari 8 (pindah ke samping boneka, tunggu 1 detik, pukulan diterima).

4. Apakah tag, atribut, atau nilai leaderstats yang diubah client ikut dipercaya server?
   - Tidak tersalin. Contoh: tag `Koin` dari client (L5 Hari 9), tag `CombatDummy` dari client (latihan 3 Hari 8), leaderstats 999 di client tidak membuat pembelian lolos (Hari 2).

## 5. Lifecycle dan memori

1. Apakah setiap tabel yang kuncinya `Player` dibersihkan di `PlayerRemoving`?
   - Cek: cocokkan hasil `grep -rn "\[Player\]" src` dengan isi handler `PlayerRemoving`. Di repo ini grep menemukan 9 deklarasi, tetapi saat jalan ada 10 tabel karena `RateLimit` dipakai dua instance (Shop dan Combat). Semuanya dibersihkan lewat `removePlayer` atau `unload` (tabel di `hari-09.md`). Satu deklarasi bisa berarti lebih dari satu tabel.

2. Apakah koneksi ke karakter diputus saat respawn?
   - Karakter lama tidak selalu di-Destroy (diukur di Hari 9: `Parent` menjadi `nil`, `Destroying` tidak menyala). Koneksi ke karakter lama tetap hidup; kalau handler-nya memegang karakter, model lama ikut tertahan di memori (penahanan memori tidak diukur di repo ini). Tes "pedang tetap jalan setelah respawn" tidak membuktikan perbaikan ini, karena juga lolos tanpa `Disconnect`.

3. Objek yang berulang (koin, pintu, NPC): apakah perilakunya dipasang lewat CollectionService, dan dilepas di `GetInstanceRemovedSignal`?
   - Contoh gagal: mutan N4 Hari 9. Tag dilepas tapi koneksi `Touched` tidak diputus, jadi part itu tetap membayar.

4. Apakah instance sementara dihapus?
   - Contoh: `toolanim` di pedang (Hari 8). Tanpa `task.delay(1, anim.Destroy, anim)` server menumpuk satu objek per ayunan.

## 6. Bukti yang diminta dari klien (atau dari diri sendiri)

1. Untuk setiap aturan keamanan, ada tes yang gagal kalau aturan itu dimatikan (tes mutasi). Tes yang lolos untuk kode benar maupun salah tidak membuktikan apa-apa.
2. Minimal satu tes lewat remote sungguhan dari client, bukan hanya memanggil fungsi server.
3. Output bersih setelah tes, atau setiap peringatan yang tersisa punya penjelasan.
4. Daftar yang belum bisa dites: banyak pemain sekaligus, lag jaringan, pembelian sungguhan, perangkat sentuh.
