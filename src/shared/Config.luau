-- Dibaca server dan client. table.freeze membuat salah tulis jadi error,
-- bukan perbedaan diam-diam antara salinan server dan client.
local Config = {
	-- Harga hanya dibaca server saat transaksi; client memakainya untuk tampilan.
	Items = table.freeze({
		SpeedBoots = table.freeze({ Name = "Sepatu Kilat", Price = 5, Order = 1 }),
		JumpCoil = table.freeze({ Name = "Pegas Lompat", Price = 15, Order = 2 }),
		GoldCrown = table.freeze({ Name = "Mahkota Emas", Price = 50, Order = 3 }),
	}),

	Shop = table.freeze({
		-- Token bucket per pemain: boleh beruntun 5 request, lalu 1 request per detik.
		BurstLimit = 5,
		RefillPerSecond = 1,
	}),
}

return table.freeze(Config)
