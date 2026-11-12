-- Siklus ronde di server: Intermission -> Round -> Result -> Intermission.
-- Status ditulis sebagai atribut di satu Folder di ReplicatedStorage. Atribut ikut
-- direplikasi ke semua client, jadi tidak perlu remote untuk mengabarkannya.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

export type Phase = "Intermission" | "Round" | "Result"

local Rounds = {}
Rounds.__index = Rounds

-- getPlayers disuntik supaya tes bisa memakai pemain palsu.
function Rounds.new(playerData, status: Instance, getPlayers: (() -> { Player })?)
	local self = setmetatable({}, Rounds)
	self._playerData = playerData
	self._status = status
	self._getPlayers = getPlayers or function()
		return Players:GetPlayers()
	end
	self._scores = {} :: { [Player]: number }
	self:_set("Intermission", 0) -- EndsAt 0 = menunggu pemain
	return self
end

-- EndsAt (waktu server, detik) ditulis sebelum Phase, supaya client yang membaca Phase baru
-- juga sudah punya waktu barunya. Client menghitung mundur sendiri dari EndsAt.
function Rounds:_set(phase: Phase, endsAt: number)
	self._phase = phase
	self._endsAt = endsAt
	self._status:SetAttribute("EndsAt", endsAt)
	self._status:SetAttribute("Phase", phase)
end

-- Dipanggil tiap Heartbeat. Waktu jadi argumen supaya tes bisa memajukan jam sendiri.
function Rounds:step(now: number)
	local enough = #self._getPlayers() >= Config.Round.MinPlayers
	if self._phase == "Intermission" then
		if not enough then
			if self._endsAt ~= 0 then
				self:_set("Intermission", 0)
			end
		elseif self._endsAt == 0 then
			self:_set("Intermission", now + Config.Round.IntermissionSeconds)
		elseif now >= self._endsAt then
			self:_startRound(now)
		end
	elseif self._phase == "Round" then
		if not enough then
			self:_finish(now, false) -- ronde batal: pemain kurang, tidak ada pemenang
		elseif now >= self._endsAt then
			self:_finish(now, true)
		end
	elseif now >= self._endsAt then -- Result selesai
		self:_set("Intermission", now + Config.Round.IntermissionSeconds)
	end
end

function Rounds:_startRound(now: number)
	table.clear(self._scores)
	for _, player in self._getPlayers() do
		player:SetAttribute("RoundScore", 0)
	end
	self:_set("Round", now + Config.Round.RoundSeconds)
end

function Rounds:_finish(now: number, completed: boolean)
	local winners, best = {}, 0
	if completed then
		for player, score in self._scores do
			if score > best then
				winners, best = { player }, score
			elseif score == best then
				table.insert(winners, player) -- seri: semua yang skornya tertinggi menang
			end
		end
	end
	table.sort(winners, function(a, b)
		return a.Name < b.Name
	end)
	local names = {}
	for i, player in winners do
		names[i] = player.Name
	end
	-- Selalu ditulis, juga saat kosong, supaya pemenang ronde lalu tidak ikut tampil.
	-- Nama akun Roblox tidak memuat koma, jadi koma aman sebagai pemisah.
	self._status:SetAttribute("Winners", table.concat(names, ","))
	self._status:SetAttribute("WinningScore", best)
	-- Fase berganti sebelum hadiah dibayar. Kalau satu pembayaran error, step berikutnya
	-- sudah di Result dan tidak membayar ulang.
	self:_set("Result", now + Config.Round.ResultSeconds)
	for _, player in winners do
		local ok, paid = pcall(self._playerData.addCoins, self._playerData, player, Config.Round.WinnerReward)
		if not (ok and paid) then
			warn(`Hadiah ronde gagal untuk {player.Name}: {if ok then "data belum termuat" else paid}`)
		end
	end
end

-- Skor = jumlah pickup selama Round, bukan jumlah koin, supaya gamepass 2x Koin
-- tidak ikut menentukan pemenang.
function Rounds:onCollected(player: Player)
	if self._phase ~= "Round" then
		return
	end
	local score = (self._scores[player] or 0) + 1
	self._scores[player] = score
	player:SetAttribute("RoundScore", score)
end

-- Pemain yang keluar tidak bisa menang ronde ini; masuk lagi berarti mulai dari 0.
function Rounds:removePlayer(player: Player)
	self._scores[player] = nil
end

function Rounds:start()
	RunService.Heartbeat:Connect(function()
		self:step(Workspace:GetServerTimeNow())
	end)
end

return Rounds
