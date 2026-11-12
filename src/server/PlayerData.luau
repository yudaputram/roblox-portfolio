-- Data pemain di memori server, disimpan ke store (DataStore asli, atau memory untuk tes).
-- leaderstats dan folder Inventory hanya cermin, diperbarui lewat onChanged.
--
-- Rekaman per pemain: { schema, data = { Coins, Inventory }, lock = { owner, at } }.
-- lock = session lock: hanya server pemilik lock yang boleh menulis data pemain itu.
local HttpService = game:GetService("HttpService")

local Inventory = require(script.Parent.Inventory)

local SCHEMA = 1

export type Data = {
	Coins: number,
	Inventory: { [string]: boolean },
}

-- Ok = tersimpan. Selain itu sesi jalan di memori saja dan tidak pernah ditulis ke store.
export type Status = "Ok" | "Offline" | "Locked" | "Error"

type Session = {
	data: Data,
	inventory: Inventory.Inventory,
	persisted: boolean,
}

export type Options = {
	onChanged: ((player: Player, data: Data) -> ())?,
	onStatus: ((player: Player, status: Status) -> ())?,
	store: any?, -- tanpa store: sesi in-memory langsung, tanpa yield
	sessionId: string?,
	now: (() -> number)?,
	wait: ((seconds: number) -> ())?,
	retryDelays: { number }?,
	leaseSeconds: number?,
	autosaveSeconds: number?,
	log: ((message: string) -> ())?,
}

local PlayerData = {}
PlayerData.__index = PlayerData

local function defaultData(): Data
	return { Coins = 0, Inventory = {} }
end

-- Data dari store tidak dipercaya bentuknya: ambil field yang valid, sisanya default.
local function reconcile(saved: any): Data
	local data = defaultData()
	if type(saved) == "table" then
		if type(saved.Coins) == "number" then
			data.Coins = saved.Coins
		end
		if type(saved.Inventory) == "table" then
			for itemId, owned in saved.Inventory do
				if type(itemId) == "string" and owned == true then
					data.Inventory[itemId] = true
				end
			end
		end
	end
	return data
end

-- Error yang tidak akan sembuh dengan retry. Polanya sengaja sempit: salah tebak di sini
-- mematikan store untuk seluruh server. Pesan pertama terbukti di place yang belum
-- dipublish; yang kedua dari dokumentasi Roblox dan belum pernah muncul di sini.
local function isPermanent(err: string): boolean
	return string.find(err, "must publish this place", 1, true) ~= nil
		or string.find(err, "StudioAccessToApisNotAllowed", 1, true) ~= nil
end

local function keyFor(player: Player): string
	return "Player_" .. player.UserId
end

function PlayerData.new(options: Options?)
	local opts: Options = options or {}
	local self = setmetatable({}, PlayerData)
	self._sessions = {} :: { [Player]: Session }
	self._loading = {} :: { [Player]: {} }
	self._busy = {} :: { [string]: boolean }
	self._pending = 0
	self._storeDown = false
	self._onChanged = opts.onChanged
	self._onStatus = opts.onStatus
	self._store = opts.store
	self._sessionId = opts.sessionId or HttpService:GenerateGUID(false)
	self._now = opts.now or os.time
	self._wait = opts.wait or task.wait
	self._retryDelays = opts.retryDelays or { 1, 2, 4 }
	self._leaseSeconds = opts.leaseSeconds or 300
	self._autosaveSeconds = opts.autosaveSeconds or 60
	self._log = opts.log or warn
	return self
end

function PlayerData:_notify(player: Player, session: Session)
	if self._onChanged then
		self._onChanged(player, session.data)
	end
end

function PlayerData:_setStatus(player: Player, status: Status)
	if self._onStatus then
		self._onStatus(player, status)
	end
end

-- Satu operasi store per pemain dalam satu waktu. Tanpa ini, rejoin cepat saat save
-- unload masih berjalan bisa membaca data lama, lalu release itu menghapus lock sesi baru.
function PlayerData:_lockKey(key: string)
	while self._busy[key] do
		task.wait()
	end
	self._busy[key] = true
end

function PlayerData:_unlockKey(key: string)
	self._busy[key] = nil
end

-- store:update dengan retry + backoff. Error permanen mematikan store untuk server ini
-- (cukup satu warning, pemain berikutnya tidak memanggil store lagi).
function PlayerData:_update(key: string, transform: (any) -> any): (boolean, string?)
	if self._storeDown then
		return false, "StoreDown"
	end
	local attempt = 0
	while true do
		attempt += 1
		local ok, err = pcall(self._store.update, self._store, key, transform)
		if ok then
			return true, nil
		end
		local message = tostring(err)
		if isPermanent(message) then
			self._storeDown = true
			self._log("[PlayerData] DataStore tidak tersedia, progres di server ini tidak disimpan: " .. message)
			return false, message
		end
		local delay = self._retryDelays[attempt]
		if not delay then
			return false, message
		end
		self._wait(delay)
	end
end

-- Ambil lock untuk key. Hasil: "Ok" (plus data tersimpan), "Locked", "TooNew", atau "Error".
function PlayerData:_claim(key: string): (string, any)
	local result, saved = "Error", nil
	for attempt = 1, #self._retryDelays + 1 do
		local ok, err = self:_update(key, function(record)
			-- callback bisa dijalankan lebih dari sekali, jadi hasil di-reset tiap kali
			saved = nil
			record = record or { schema = SCHEMA }
			if (record.schema or SCHEMA) > SCHEMA then
				result = "TooNew" -- ditulis versi game yang lebih baru; jangan ditimpa
				return nil
			end
			local lock = record.lock
			if lock and lock.owner ~= self._sessionId and self._now() - lock.at < self._leaseSeconds then
				result = "Locked"
				return nil
			end
			record.schema = SCHEMA
			record.lock = { owner = self._sessionId, at = self._now() }
			result, saved = "Ok", record.data
			return record
		end)
		if not ok then
			return if self._storeDown then "Offline" else "Error", err
		end
		if result ~= "Locked" then
			break
		end
		local delay = self._retryDelays[attempt]
		if delay then
			self._wait(delay)
		end
	end
	return result, saved
end

-- Tulis data (kalau ada) lalu perpanjang atau lepas lock. Dibatalkan kalau lock
-- sudah bukan milik server ini, supaya snapshot basi tidak menimpa progres baru.
function PlayerData:_write(key: string, data: Data?, release: boolean): (boolean, boolean)
	local owned = false
	local ok = self:_update(key, function(record)
		owned = false
		if not record or not record.lock or record.lock.owner ~= self._sessionId then
			return nil
		end
		owned = true
		if data then
			record.data = data
		end
		record.schema = SCHEMA
		record.lock = if release then nil else { owner = self._sessionId, at = self._now() }
		return record
	end)
	return ok, owned
end

function PlayerData:_saveSession(player: Player, session: Session, key: string, release: boolean): boolean
	if not session.persisted then
		return false
	end
	local ok, owned = self:_write(key, session.data, release)
	if ok and not owned then
		session.persisted = false
		self:_setStatus(player, "Locked")
		self._log("[PlayerData] " .. key .. " diambil alih server lain, berhenti menyimpan")
	elseif not ok then
		self._log("[PlayerData] gagal menyimpan " .. key)
	end
	return ok and owned
end

function PlayerData:_start(player: Player, data: Data, persisted: boolean, status: Status)
	local session = { data = data, inventory = Inventory.new(data.Inventory), persisted = persisted }
	self._sessions[player] = session
	self:_setStatus(player, status)
	self:_notify(player, session)
end

-- Bisa yield (store). Selama belum selesai, get/addCoins/purchase menganggap belum termuat.
function PlayerData:load(player: Player)
	if not self._store then
		self:_start(player, defaultData(), false, "Offline")
		return
	end
	local token = {}
	self._loading[player] = token
	local key = keyFor(player)
	self:_lockKey(key)
	local result, saved = self:_claim(key)
	if self._loading[player] ~= token then
		-- pemain keluar saat load berjalan: lepas lock yang baru diambil, jangan buat sesi
		if result == "Ok" then
			self:_write(key, nil, true)
		end
		self:_unlockKey(key)
		return
	end
	self._loading[player] = nil
	self:_unlockKey(key)

	if result == "Ok" then
		self:_start(player, reconcile(saved), true, "Ok")
		return
	end
	if result == "Locked" then
		self._log("[PlayerData] " .. key .. " masih dipegang server lain, sesi ini tidak disimpan")
	elseif result == "TooNew" then
		self._log("[PlayerData] " .. key .. " ditulis versi game yang lebih baru, sesi ini tidak disimpan")
	elseif result == "Error" then
		self._log("[PlayerData] gagal memuat " .. key .. ": " .. tostring(saved) .. ", sesi ini tidak disimpan")
	end
	local status: Status = if result == "TooNew" then "Error" else result :: Status
	self:_start(player, defaultData(), false, status)
end

-- Sesi dihapus dari memori lebih dulu (pembelian setelahnya ditolak NotLoaded),
-- baru disimpan sambil melepas lock. Bisa yield.
function PlayerData:unload(player: Player)
	self._loading[player] = nil
	local session = self._sessions[player]
	self._sessions[player] = nil
	if not session or not session.persisted then
		return
	end
	local key = keyFor(player)
	self._pending += 1
	self:_lockKey(key)
	self:_saveSession(player, session, key, true)
	self:_unlockKey(key)
	self._pending -= 1
end

-- Simpan sekarang. false = tidak tersimpan (sesi in-memory, store gagal, atau lock hilang).
function PlayerData:save(player: Player): boolean
	local session = self._sessions[player]
	if not session or not session.persisted then
		return false
	end
	local key = keyFor(player)
	self._pending += 1
	self:_lockKey(key)
	local ok = self:_saveSession(player, session, key, false)
	self:_unlockKey(key)
	self._pending -= 1
	return ok
end

function PlayerData:isPersisted(player: Player): boolean
	local session = self._sessions[player]
	return session ~= nil and session.persisted
end

function PlayerData:saveAll()
	for player in self._sessions do
		task.spawn(self.save, self, player)
	end
end

function PlayerData:startAutosave()
	task.spawn(function()
		while true do
			task.wait(self._autosaveSeconds)
			self:saveAll()
		end
	end)
end

-- Untuk BindToClose: simpan dan lepas semua sesi, lalu tunggu semua save yang masih
-- berjalan (termasuk dari PlayerRemoving). Roblox memberi 30 dtk; sisakan ruang.
function PlayerData:closeAll()
	for player in self._sessions do
		task.spawn(self.unload, self, player)
	end
	local deadline = os.clock() + 25
	while self._pending > 0 and os.clock() < deadline do
		task.wait()
	end
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
