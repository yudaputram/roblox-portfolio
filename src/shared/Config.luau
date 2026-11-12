-- Dibaca server dan client. table.freeze membuat salah tulis jadi error,
-- bukan perbedaan diam-diam antara salinan server dan client.
local Config = {
	-- Harga hanya dibaca server saat transaksi; client memakainya untuk tampilan.
	Items = table.freeze({
		SpeedBoots = table.freeze({ Name = "Sepatu Kilat", Price = 5, Order = 1 }),
		JumpCoil = table.freeze({ Name = "Pegas Lompat", Price = 15, Order = 2 }),
		GoldCrown = table.freeze({ Name = "Mahkota Emas", Price = 50, Order = 3 }),
	}),

	Coin = table.freeze({
		Reward = 1,
		Cooldown = 1, -- detik, per pemain, berlaku untuk semua koin sekaligus
		RespawnSeconds = 8, -- koin yang diambil muncul lagi setelah ini
		-- Satu part bertag "Koin" per posisi. Jauh dari titik spawn dan boneka latihan.
		Positions = table.freeze({
			Vector3.new(0, 3, 10),
			Vector3.new(20, 3, 10),
			Vector3.new(-20, 3, 10),
			Vector3.new(20, 3, 30),
			Vector3.new(-20, 3, 30),
		}),
	}),

	Shop = table.freeze({
		-- Token bucket per pemain: boleh beruntun 5 request, lalu 1 request per detik.
		BurstLimit = 5,
		RefillPerSecond = 1,
	}),

	Round = table.freeze({
		IntermissionSeconds = 15,
		RoundSeconds = 45,
		ResultSeconds = 6,
		-- shortcut: 1 supaya bisa dites sendirian di Studio, naikkan ke 2 sebelum publish.
		MinPlayers = 1,
		WinnerReward = 10, -- koin untuk tiap pemenang
	}),

	Combat = table.freeze({
		Damage = 25,
		Cooldown = 0.6, -- detik antar ayunan, per pemain
		-- Stud antara HumanoidRootPart penyerang dan target, diukur di server. Pedang sekitar
		-- 5 stud; sisanya kelonggaran karena target sudah bergerak saat request tiba.
		Range = 9,
		KillReward = 5, -- koin; tidak digandakan gamepass 2x Koin, sama seperti hadiah ronde
		DummyRespawn = 5, -- detik setelah boneka latihan mati
		-- Batas request Attack per pemain, di atas laju klik pemain jujur (cooldown 0,6 detik).
		RequestBurst = 10,
		RequestsPerSecond = 5,
	}),

	-- ID dibuat di Creator Dashboard setelah place dipublish. 0 = belum ada.
	GamePasses = table.freeze({
		DoubleCoins = 0, -- "2x Koin": isi setelah publish
	}),
	Products = table.freeze({
		Coins100 = table.freeze({ Id = 0, Coins = 100 }), -- "+100 Koin": isi setelah publish
	}),
}

return table.freeze(Config)
