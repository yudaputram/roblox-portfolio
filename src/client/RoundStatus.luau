-- Teks status ronde untuk HUD. Fungsi murni: semua input berasal dari atribut
-- RoundState, jam server, dan atribut pemain, jadi bisa dites tanpa menjalankan ronde.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

export type Round = {
	phase: string?,
	endsAt: number?, -- waktu server; 0 saat Intermission = menunggu pemain
	winners: string?, -- nama akun pemenang dipisah koma, ditulis server
	winningScore: number?,
}

local MAX_NAMES = 3 -- seri besar: sisanya diringkas supaya baris tidak memanjang

local RoundStatus = {}

function RoundStatus.text(round: Round, now: number, me: string, myScore: number): string?
	local seconds = math.max(0, math.ceil((round.endsAt or 0) - now))
	if round.phase == "Intermission" then
		if round.endsAt == 0 then
			return "Menunggu pemain lain"
		end
		return `Ronde mulai dalam {seconds} detik`
	elseif round.phase == "Round" then
		return `Ronde: {seconds} detik lagi. Skor kamu: {myScore}`
	elseif round.phase == "Result" then
		local names = if round.winners and round.winners ~= "" then string.split(round.winners, ",") else {}
		if #names == 0 then
			return "Ronde selesai. Tidak ada pemenang."
		elseif table.find(names, me) then
			-- Fakta yang sama dengan yang dipakai server untuk membayar hadiah.
			return `Kamu menang! +{Config.Round.WinnerReward} koin (skor {round.winningScore})`
		end
		local shown = table.concat(names, ", ", 1, math.min(#names, MAX_NAMES))
		if #names > MAX_NAMES then
			shown ..= ` dan {#names - MAX_NAMES} lainnya`
		end
		return `Pemenang: {shown} (skor {round.winningScore})`
	end
	return nil -- status belum sampai dari server
end

return RoundStatus
