-- Toko: memvalidasi permintaan client, lalu menyerahkan transaksi ke PlayerData.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local RateLimit = require(script.Parent.RateLimit)

-- Hanya hasil yang wajar dialami pemain jujur yang dibalas ke client.
local REPLY_REASONS = { Ok = true, NotEnoughCoins = true, AlreadyOwned = true }

local Shop = {}
Shop.__index = Shop

function Shop.new(playerData)
	local self = setmetatable({}, Shop)
	self._playerData = playerData
	self._limit = RateLimit.new(Config.Shop.BurstLimit, Config.Shop.RefillPerSecond)
	return self
end

-- itemId bertipe unknown: client exploit bisa mengirim apa saja (nil, angka, table, Instance).
-- Mengembalikan (berhasil, alasan) supaya bisa dites langsung tanpa remote.
function Shop:buy(player: Player, itemId: unknown): (boolean, string)
	if not self._limit:allow(player, os.clock()) then
		return false, "RateLimited"
	end
	if type(itemId) ~= "string" then
		return false, "BadType"
	end
	local item = Config.Items[itemId]
	if not item then
		return false, "UnknownItem"
	end
	-- Harga diambil dari Config di server, tidak pernah dari argumen client.
	return self._playerData:purchase(player, itemId, item.Price)
end

function Shop:connect(buyItem: RemoteEvent, buyResult: RemoteEvent): RBXScriptConnection
	return buyItem.OnServerEvent:Connect(function(player: Player, itemId: unknown)
		local _, reason = self:buy(player, itemId)
		if REPLY_REASONS[reason] then
			buyResult:FireClient(player, itemId, reason)
		end
	end)
end

function Shop:removePlayer(player: Player)
	self._limit:removePlayer(player)
end

return Shop
