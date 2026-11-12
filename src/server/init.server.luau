-- SERVER: sumber kebenaran. Script ini hanya merakit: membuat remote dan
-- menyambungkan modul-modul di folder ini. Logikanya ada di modul.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CoinPickup = require(script.CoinPickup)
local PlayerData = require(script.PlayerData)
local Shop = require(script.Shop)
local StatsMirror = require(script.StatsMirror)
local Store = require(script.Store)

-- Client hanya boleh meminta lewat remote ini; keputusannya tetap di server.
local function makeRemote(parent: Instance, name: string): RemoteEvent
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local buyItem = makeRemote(remotes, "BuyItem") -- client -> server: (itemId: string)
local buyResult = makeRemote(remotes, "BuyResult") -- server -> satu client: (itemId, "Ok" | "NotEnoughCoins" | "AlreadyOwned")
remotes.Parent = ReplicatedStorage

local playerData = PlayerData.new({
	store = Store.datastore("PlayerData"),
	onChanged = StatsMirror.sync,
	-- Dibaca client (UI Hari 5) untuk memberi tahu kalau progres tidak disimpan.
	onStatus = function(player: Player, status: string)
		player:SetAttribute("DataStatus", status)
	end,
})
local shop = Shop.new(playerData)
local coinPickup = CoinPickup.new(playerData)

shop:connect(buyItem, buyResult)
coinPickup:start()
playerData:startAutosave()
game:BindToClose(function()
	playerData:closeAll()
end)

local function onPlayerAdded(player: Player)
	playerData:load(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do -- pemain yang sudah masuk sebelum script ini jalan
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	-- Tiap modul yang menyimpan data per pemain wajib dibersihkan di sini.
	-- unload terakhir karena menunggu save ke DataStore (yield).
	shop:removePlayer(player)
	coinPickup:removePlayer(player)
	playerData:unload(player)
end)
