-- Gamepass "2x Koin" dan developer product "+100 Koin". ID ada di Config (0 sampai dipublish).
-- Semua panggilan ke Roblox bisa disuntik, jadi logikanya bisa dites di place yang belum dipublish.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local POLL_SECONDS = 0.5

export type Options = {
	doubleCoinsPass: number?,
	ownsPass: ((userId: number, passId: number) -> boolean)?,
	getPlayer: ((userId: number) -> Player?)?,
	wait: ((seconds: number) -> ())?,
	retryDelays: { number }?,
	loadTimeout: number?, -- detik menunggu data pemain termuat sebelum menjawab NotProcessedYet
	log: ((message: string) -> ())?,
}

local Monetization = {}
Monetization.__index = Monetization

function Monetization.new(playerData, options: Options?)
	local opts: Options = options or {}
	local self = setmetatable({}, Monetization)
	self._playerData = playerData
	self._passId = opts.doubleCoinsPass or Config.GamePasses.DoubleCoins
	self._ownsPass = opts.ownsPass
		or function(userId: number, passId: number): boolean
			return MarketplaceService:UserOwnsGamePassAsync(userId, passId)
		end
	self._getPlayer = opts.getPlayer
		or function(userId: number): Player?
			return Players:GetPlayerByUserId(userId)
		end
	self._wait = opts.wait or task.wait
	self._retryDelays = opts.retryDelays or { 1, 2, 4 }
	self._loadTimeout = opts.loadTimeout or 60
	self._log = opts.log or warn
	self._doubleCoins = {} :: { [Player]: boolean } -- cache, hanya pernah diisi true
	self._checking = {} :: { [Player]: {} }
	return self
end

-- Cek kepemilikan saat join. Bisa yield. Hasil false tidak ditulis: cek yang mulai sebelum
-- pemain membeli tidak boleh menimpa true dari onPassPurchased.
function Monetization:checkPass(player: Player)
	if self._passId == 0 then
		return -- belum dipublish, belum ada gamepass untuk dicek
	end
	local token = {}
	self._checking[player] = token
	local attempt = 0
	while true do
		attempt += 1
		local ok, result = pcall(self._ownsPass, player.UserId, self._passId)
		if self._checking[player] ~= token then
			return -- pemain keluar saat menunggu jawaban
		end
		local delay = self._retryDelays[attempt]
		if ok or not delay then
			self._checking[player] = nil
			if ok and result == true then
				self._doubleCoins[player] = true
			elseif not ok then
				self._log("[Monetization] cek gamepass gagal untuk " .. player.UserId .. ": " .. tostring(result))
			end
			return
		end
		self._wait(delay)
	end
end

-- Dari PromptGamePassPurchaseFinished di server. Di client nilai ini tidak boleh dipercaya.
function Monetization:onPassPurchased(player: Player, passId: number, wasPurchased: boolean)
	if wasPurchased and passId == self._passId then
		self._doubleCoins[player] = true
	end
end

-- Dibaca saat pickup. Tidak yield, hanya membaca cache.
function Monetization:coinMultiplier(player: Player): number
	return if self._doubleCoins[player] then 2 else 1
end

function Monetization:removePlayer(player: Player)
	self._doubleCoins[player] = nil
	self._checking[player] = nil
end

local function findProduct(productId: number)
	for _, product in Config.Products do
		if product.Id == productId then
			return product
		end
	end
	return nil
end

-- Callback ProcessReceipt. Roblox tidak mengirim ulang receipt berdasarkan waktu, hanya saat
-- pemain membeli lagi atau masuk ulang. Karena itu receipt yang datang saat data pemain masih
-- dimuat ditunggu dulu, bukan langsung ditolak. Callback ini boleh yield selama apa pun.
function Monetization:processReceipt(info): Enum.ProductPurchaseDecision
	local notYet = Enum.ProductPurchaseDecision.NotProcessedYet
	local product = findProduct(info.ProductId)
	if not product then
		self._log("[Monetization] ProductId tidak dikenal: " .. tostring(info.ProductId))
		return notYet
	end
	local player = self._getPlayer(info.PlayerId)
	if not player then
		return notYet -- pembeli tidak ada di server ini
	end
	local waited = 0
	while not self._playerData:get(player) do
		if waited >= self._loadTimeout or self._getPlayer(info.PlayerId) ~= player then
			return notYet
		end
		self._wait(POLL_SECONDS)
		waited += POLL_SECONDS
	end
	if self._playerData:grantPurchase(player, info.PurchaseId, product.Coins) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return notYet
end

return Monetization
