-- Koin di dunia. Sentuh = tambah Coins lewat PlayerData, dengan cooldown per pemain.
-- Setiap BasePart bertag "Koin" adalah koin, termasuk yang ditambah setelah server jalan.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local COIN_TAG = "Koin"

local CoinPickup = {}
CoinPickup.__index = CoinPickup
CoinPickup.TAG = COIN_TAG

-- multiplier: pengali hadiah per pemain (gamepass 2x Koin). Tanpa itu selalu 1.
-- onCollected: dipanggil setiap pickup yang sah (skor ronde Hari 7).
function CoinPickup.new(playerData, multiplier: ((Player) -> number)?, onCollected: ((Player) -> ())?)
	local self = setmetatable({}, CoinPickup)
	self._playerData = playerData
	self._multiplier = multiplier or function()
		return 1
	end
	self._onCollected = onCollected
	self._cooling = {} :: { [Player]: boolean }
	self._touched = {} :: { [Instance]: RBXScriptConnection }
	return self
end

-- Dipisah dari Touched supaya aturan cooldown bisa dites tanpa menggerakkan karakter.
function CoinPickup:collect(player: Player): boolean
	if self._cooling[player] then
		return false
	end
	if not self._playerData:addCoins(player, Config.Coin.Reward * self._multiplier(player)) then
		return false -- data pemain belum termuat
	end
	self._cooling[player] = true
	task.delay(Config.Coin.Cooldown, function()
		self._cooling[player] = nil
	end)
	-- Paling akhir: kalau callback error, koin dan cooldown sudah tercatat.
	if self._onCollected then
		self._onCollected(player)
	end
	return true
end

-- Satu koneksi Touched per koin, disimpan supaya bisa diputus saat koin dilepas.
function CoinPickup:bind(part: Instance)
	if not part:IsA("BasePart") or self._touched[part] then
		return -- tag di Model atau objek lain diabaikan; bind dua kali juga
	end
	self._touched[part] = part.Touched:Connect(function(hit: BasePart)
		-- Touched terpicu untuk tiap bagian tubuh. Cari pemilik karakternya.
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if player then
			self:collect(player)
		end
	end)
end

-- Dipanggil saat tag dilepas atau part keluar dari DataModel (termasuk Destroy).
function CoinPickup:unbind(part: Instance)
	local connection = self._touched[part]
	if connection then
		connection:Disconnect()
		self._touched[part] = nil
	end
end

local function makeCoin(position: Vector3)
	local coinPart = Instance.new("Part")
	coinPart.Name = "Koin"
	coinPart.Size = Vector3.new(2, 2, 2)
	coinPart.Color = Color3.fromRGB(255, 200, 0)
	coinPart.Anchored = true -- tidak jatuh kena gravitasi
	coinPart.CanCollide = false -- bisa ditembus, tapi Touched tetap jalan
	coinPart.Position = position
	coinPart:AddTag(COIN_TAG)
	coinPart.Parent = workspace
end

function CoinPickup:start()
	CollectionService:GetInstanceAddedSignal(COIN_TAG):Connect(function(part)
		self:bind(part)
	end)
	CollectionService:GetInstanceRemovedSignal(COIN_TAG):Connect(function(part)
		self:unbind(part)
	end)
	for _, part in CollectionService:GetTagged(COIN_TAG) do -- koin yang sudah ada di place
		self:bind(part)
	end
	for _, position in Config.Coin.Positions do
		makeCoin(position)
	end
end

function CoinPickup:removePlayer(player: Player)
	self._cooling[player] = nil
end

return CoinPickup
