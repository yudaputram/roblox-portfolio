-- Menyamakan leaderstats dan folder Inventory dengan data server.
-- Nilai di sini hanya tampilan: server tidak pernah membacanya untuk mengambil keputusan.
local StatsMirror = {}

function StatsMirror.sync(player: Player, data: { Coins: number, Inventory: { [string]: boolean } })
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats" -- nama wajib persis ini supaya muncul di papan skor
		local coins = Instance.new("IntValue")
		coins.Name = "Coins"
		coins.Parent = stats
	end

	local inventory = player:FindFirstChild("Inventory")
	if not inventory then
		inventory = Instance.new("Folder")
		inventory.Name = "Inventory"
	end

	(stats :: any).Coins.Value = data.Coins
	for itemId in data.Inventory do
		if not inventory:FindFirstChild(itemId) then
			local owned = Instance.new("BoolValue")
			owned.Name = itemId
			owned.Value = true
			owned.Parent = inventory
		end
	end

	-- Parent paling akhir: saat pertama dibuat, folder dikirim ke client sudah lengkap
	inventory.Parent = player
	stats.Parent = player
end

return StatsMirror
