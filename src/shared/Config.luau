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
		Cooldown = 1, -- detik, per pemain
	}),

	Shop = table.freeze({
		-- Token bucket per pemain: boleh beruntun 5 request, lalu 1 request per detik.
		BurstLimit = 5,
		RefillPerSecond = 1,
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
