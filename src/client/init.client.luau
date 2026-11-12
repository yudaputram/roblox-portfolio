-- CLIENT: hanya menampilkan. Tidak mengubah Coins, itu urusan server.
local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- WaitForChild: leaderstats dibuat server, bisa belum sampai saat script ini mulai
local coins = player:WaitForChild("leaderstats"):WaitForChild("Coins") :: IntValue

coins:GetPropertyChangedSignal("Value"):Connect(function()
	print("Koin kamu: " .. coins.Value)
end)
