-- CLIENT: hanya menampilkan dan meminta. Tidak mengubah Coins, itu urusan server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer

-- WaitForChild: leaderstats dan Remotes dibuat server, bisa belum sampai saat script ini mulai
local coins = player:WaitForChild("leaderstats"):WaitForChild("Coins") :: IntValue
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local buyItem = remotes:WaitForChild("BuyItem") :: RemoteEvent
local buyResult = remotes:WaitForChild("BuyResult") :: RemoteEvent

coins:GetPropertyChangedSignal("Value"):Connect(function()
	print("Koin kamu: " .. coins.Value)
end)

-- Kontrol sementara sampai UI toko ada di Hari 5. Bukan 1/2/3 karena itu slot hotbar Tool.
local KEYS = { Enum.KeyCode.J, Enum.KeyCode.K, Enum.KeyCode.L }
local itemIdByKey: { [Enum.KeyCode]: string } = {}
for itemId, item in Config.Items do
	local key = KEYS[item.Order]
	if key then
		itemIdByKey[key] = itemId
	end
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return -- tombol sedang dipakai UI lain, misalnya mengetik di chat
	end
	local itemId = itemIdByKey[input.KeyCode]
	if itemId then
		buyItem:FireServer(itemId)
	end
end)

local MESSAGES = {
	Ok = "Berhasil membeli",
	NotEnoughCoins = "Koin belum cukup untuk",
	AlreadyOwned = "Sudah punya",
}

buyResult.OnClientEvent:Connect(function(itemId: string, result: string)
	local item = Config.Items[itemId]
	print(`{MESSAGES[result] or result} {if item then item.Name else itemId}`)
end)
