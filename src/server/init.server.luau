-- SERVER: sumber kebenaran. Coins hanya boleh berubah di sini.
local Players = game:GetService("Players")

local COOLDOWN = 1 -- detik, dihitung per pemain

-- 1. leaderstats untuk tiap pemain
local function onPlayerAdded(player: Player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats" -- nama wajib persis ini supaya muncul di papan skor

	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = stats

	stats.Parent = player -- Parent paling akhir: objek dikirim ke client sekali, sudah lengkap
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do -- pemain yang sudah masuk sebelum script ini jalan
	task.spawn(onPlayerAdded, player)
end

-- 2. Part koin, dibuat lewat kode
local coinPart = Instance.new("Part")
coinPart.Name = "Koin"
coinPart.Size = Vector3.new(2, 2, 2)
coinPart.Color = Color3.fromRGB(255, 200, 0)
coinPart.Anchored = true -- tidak jatuh kena gravitasi
coinPart.CanCollide = false -- bisa ditembus, tapi Touched tetap jalan
coinPart.Position = Vector3.new(0, 3, 10)
coinPart.Parent = workspace

-- 3. Sentuh = +1 Coins, cooldown per pemain
local cooling: { [Player]: boolean } = {}

coinPart.Touched:Connect(function(hit: BasePart)
	-- Touched terpicu untuk tiap bagian tubuh (kaki, tangan, ...). Cari pemilik karakternya.
	local player = Players:GetPlayerFromCharacter(hit.Parent)
	if not player or cooling[player] then
		return -- bukan pemain, atau pemain ini masih cooldown
	end

	local stats = player:FindFirstChild("leaderstats")
	local coins = stats and stats:FindFirstChild("Coins")
	if not coins then
		return
	end

	cooling[player] = true
	coins.Value += 1
	task.delay(COOLDOWN, function()
		cooling[player] = nil
	end)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	cooling[player] = nil -- jangan simpan referensi pemain yang sudah keluar
end)
