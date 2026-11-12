-- SERVER: sumber kebenaran. Coins dan inventori hanya boleh berubah di sini.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local COOLDOWN = 1 -- detik, dihitung per pemain

-- Client hanya boleh meminta lewat remote ini; keputusannya tetap di server.
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"

local buyItem = Instance.new("RemoteEvent")
buyItem.Name = "BuyItem" -- client -> server: (itemId: string)
buyItem.Parent = remotes

local buyResult = Instance.new("RemoteEvent")
buyResult.Name = "BuyResult" -- server -> satu client: (itemId, "Ok" | "NotEnoughCoins" | "AlreadyOwned")
buyResult.Parent = remotes

remotes.Parent = ReplicatedStorage

-- 1. leaderstats + Inventory untuk tiap pemain
local function onPlayerAdded(player: Player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats" -- nama wajib persis ini supaya muncul di papan skor

	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = stats

	-- Satu BoolValue per item yang dimiliki. Ikut tereplikasi, jadi client bisa menampilkannya.
	local inventory = Instance.new("Folder")
	inventory.Name = "Inventory"

	inventory.Parent = player
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

-- 4. Toko. Rate limit token bucket per pemain: request yang kelewat batas dibuang diam-diam.
type Bucket = { tokens: number, updatedAt: number }
local buckets: { [Player]: Bucket } = {}

local function allowRequest(player: Player): boolean
	local now = os.clock()
	local bucket = buckets[player]
	if not bucket then
		bucket = { tokens = Config.Shop.BurstLimit, updatedAt = now }
		buckets[player] = bucket
	end
	local refilled = bucket.tokens + (now - bucket.updatedAt) * Config.Shop.RefillPerSecond
	bucket.tokens = math.min(Config.Shop.BurstLimit, refilled)
	bucket.updatedAt = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

-- itemId bertipe unknown: client exploit bisa mengirim apa saja (nil, angka, table, Instance).
buyItem.OnServerEvent:Connect(function(player: Player, itemId: unknown)
	-- Cek termurah dulu. Input rusak tidak dibalas karena client jujur tidak pernah mengirimnya.
	if not allowRequest(player) then
		return
	end
	if type(itemId) ~= "string" then
		return
	end
	local item = Config.Items[itemId]
	if not item then
		return
	end

	local stats = player:FindFirstChild("leaderstats")
	local coins = stats and stats:FindFirstChild("Coins") :: IntValue?
	local inventory = player:FindFirstChild("Inventory")
	if not coins or not inventory then
		return -- data pemain belum siap
	end

	if inventory:FindFirstChild(itemId) then
		buyResult:FireClient(player, itemId, "AlreadyOwned")
		return
	end
	-- Harga diambil dari Config di server, tidak pernah dari argumen client.
	if coins.Value < item.Price then
		buyResult:FireClient(player, itemId, "NotEnoughCoins")
		return
	end

	-- Tidak ada yield antara cek dan perubahan, jadi dua request beruntun tidak bisa sama-sama lolos.
	coins.Value -= item.Price
	local owned = Instance.new("BoolValue")
	owned.Name = itemId
	owned.Value = true
	owned.Parent = inventory
	buyResult:FireClient(player, itemId, "Ok")
end)

Players.PlayerRemoving:Connect(function(player: Player)
	-- jangan simpan referensi pemain yang sudah keluar
	cooling[player] = nil
	buckets[player] = nil
end)
