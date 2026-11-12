-- Data pemain di memori server. leaderstats dan folder Inventory hanya cermin
-- dari data ini, diperbarui lewat onChanged setiap kali data berubah.
local Inventory = require(script.Parent.Inventory)

export type Data = {
	Coins: number,
	Inventory: { [string]: boolean },
}

type Session = {
	data: Data,
	inventory: Inventory.Inventory,
}

export type Options = {
	onChanged: ((player: Player, data: Data) -> ())?,
}

local PlayerData = {}
PlayerData.__index = PlayerData

local function defaultData(): Data
	return { Coins = 0, Inventory = {} }
end

function PlayerData.new(options: Options?)
	local self = setmetatable({}, PlayerData)
	self._sessions = {} :: { [Player]: Session }
	self._onChanged = options and options.onChanged
	return self
end

function PlayerData:_notify(player: Player, session: Session)
	if self._onChanged then
		self._onChanged(player, session.data)
	end
end

function PlayerData:load(player: Player)
	local data = defaultData()
	local session = { data = data, inventory = Inventory.new(data.Inventory) }
	self._sessions[player] = session
	self:_notify(player, session)
end

function PlayerData:unload(player: Player)
	self._sessions[player] = nil
end

-- Untuk dibaca saja. Semua perubahan lewat method di bawah supaya cermin ikut diperbarui.
function PlayerData:get(player: Player): Data?
	local session = self._sessions[player]
	return session and session.data
end

function PlayerData:addCoins(player: Player, amount: number): boolean
	local session = self._sessions[player]
	if not session then
		return false -- belum termuat (atau sudah keluar)
	end
	session.data.Coins += amount
	self:_notify(player, session)
	return true
end

-- Cek, potong koin, tambah item, lalu kabari cermin sekali.
-- Tidak boleh ada yield di dalamnya: itu yang mencegah double spend.
function PlayerData:purchase(player: Player, itemId: string, price: number): (boolean, string)
	local session = self._sessions[player]
	if not session then
		return false, "NotLoaded"
	end
	if session.inventory:has(itemId) then
		return false, "AlreadyOwned"
	end
	if session.data.Coins < price then
		return false, "NotEnoughCoins"
	end
	session.data.Coins -= price
	session.inventory:add(itemId)
	self:_notify(player, session)
	return true, "Ok"
end

return PlayerData
