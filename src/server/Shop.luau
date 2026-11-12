-- Toko: memvalidasi permintaan client, lalu menyerahkan transaksi ke PlayerData.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

-- Hanya hasil yang wajar dialami pemain jujur yang dibalas ke client.
local REPLY_REASONS = { Ok = true, NotEnoughCoins = true, AlreadyOwned = true }

type Bucket = { tokens: number, updatedAt: number }

local Shop = {}
Shop.__index = Shop

function Shop.new(playerData)
	local self = setmetatable({}, Shop)
	self._playerData = playerData
	self._buckets = {} :: { [Player]: Bucket }
	return self
end

-- Token bucket per pemain: request yang kelewat batas dibuang.
function Shop:_allowRequest(player: Player): boolean
	local now = os.clock()
	local bucket = self._buckets[player]
	if not bucket then
		bucket = { tokens = Config.Shop.BurstLimit, updatedAt = now }
		self._buckets[player] = bucket
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
-- Mengembalikan (berhasil, alasan) supaya bisa dites langsung tanpa remote.
function Shop:buy(player: Player, itemId: unknown): (boolean, string)
	if not self:_allowRequest(player) then
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
	self._buckets[player] = nil
end

return Shop
