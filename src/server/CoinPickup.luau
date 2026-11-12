-- Part koin di dunia. Sentuh = tambah Coins lewat PlayerData, dengan cooldown per pemain.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local CoinPickup = {}
CoinPickup.__index = CoinPickup

function CoinPickup.new(playerData)
	local self = setmetatable({}, CoinPickup)
	self._playerData = playerData
	self._cooling = {} :: { [Player]: boolean }
	return self
end

-- Dipisah dari Touched supaya aturan cooldown bisa dites tanpa menggerakkan karakter.
function CoinPickup:collect(player: Player): boolean
	if self._cooling[player] then
		return false
	end
	if not self._playerData:addCoins(player, Config.Coin.Reward) then
		return false -- data pemain belum termuat
	end
	self._cooling[player] = true
	task.delay(Config.Coin.Cooldown, function()
		self._cooling[player] = nil
	end)
	return true
end

function CoinPickup:start()
	local coinPart = Instance.new("Part")
	coinPart.Name = "Koin"
	coinPart.Size = Vector3.new(2, 2, 2)
	coinPart.Color = Color3.fromRGB(255, 200, 0)
	coinPart.Anchored = true -- tidak jatuh kena gravitasi
	coinPart.CanCollide = false -- bisa ditembus, tapi Touched tetap jalan
	coinPart.Position = Vector3.new(0, 3, 10)
	coinPart.Parent = workspace

	coinPart.Touched:Connect(function(hit: BasePart)
		-- Touched terpicu untuk tiap bagian tubuh. Cari pemilik karakternya.
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if player then
			self:collect(player)
		end
	end)
end

function CoinPickup:removePlayer(player: Player)
	self._cooling[player] = nil
end

return CoinPickup
