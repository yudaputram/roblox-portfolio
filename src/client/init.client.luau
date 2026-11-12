-- CLIENT: menampilkan cermin data dari server dan mengirim permintaan beli.
-- Tidak pernah mengubah Coins atau Inventory; keputusan tetap di server.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local RoundStatus = require(script.RoundStatus)
local ShopView = require(script.ShopView)
local Sword = require(script.Sword)

local REPLY_TIMEOUT = 3 -- detik; server tidak membalas request yang kena rate limit
local LOAD_TIMEOUT = 60 -- load DataStore bisa mencoba ulang beberapa kali

local MESSAGES = {
	Ok = "%s dibeli.",
	NotEnoughCoins = "Koin belum cukup untuk %s.",
	AlreadyOwned = "%s sudah kamu miliki.",
}

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local buyItem = remotes:WaitForChild("BuyItem") :: RemoteEvent
local buyResult = remotes:WaitForChild("BuyResult") :: RemoteEvent

local state: ShopView.State = {
	loaded = false,
	failed = false,
	coins = 0,
	owned = {},
	pending = {},
	status = player:GetAttribute("DataStatus"),
	message = nil,
	open = false,
	keyHint = false,
	round = nil,
}
local view
local nextToken = 0

local function usesDirectionalFocus(): boolean
	local preferred = UserInputService.PreferredInput
	return preferred == Enum.PreferredInput.Gamepad or preferred == Enum.PreferredInput.MicroGamepad
end

local function render()
	view:render(state)
	-- Tombol yang sedang dipilih gamepad bisa berubah jadi nonaktif (mis. "Dimiliki").
	local selected = GuiService.SelectedObject
	if state.open and selected and selected:IsDescendantOf(view.panel) and not selected.Selectable then
		GuiService.SelectedObject = view:focusTarget()
	end
end

local function toggle()
	state.open = not state.open
	render()
	if state.open then
		task.spawn(function()
			RunService.RenderStepped:Wait() -- target harus sudah tergambar supaya bisa dipilih
			if state.open and usesDirectionalFocus() then
				GuiService.SelectedObject = view:focusTarget()
			end
		end)
	elseif GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(view.panel) then
		GuiService.SelectedObject = nil
	end
end

local function buy(itemId: string)
	local _, kind = ShopView.rowState(itemId, state)
	if kind ~= "buy" then
		return -- tombol nonaktif: jangan kirim apa pun walau event tetap terpicu
	end
	nextToken += 1
	local token = nextToken
	state.pending[itemId] = token
	state.message = nil
	render()
	buyItem:FireServer(itemId)
	task.delay(REPLY_TIMEOUT, function()
		-- Token beda berarti balasan sudah datang atau ada request yang lebih baru.
		if state.pending[itemId] == token then
			state.pending[itemId] = nil
			state.message = "Server tidak membalas. Coba lagi."
			render()
		end
	end)
end

view = ShopView.new(player:WaitForChild("PlayerGui"), { onToggle = toggle, onBuy = buy })
render()

Sword.start(player, remotes:WaitForChild("Attack") :: RemoteEvent)

-- Status ronde dibaca dari atribut yang ditulis server. Dicek ulang 5x per detik untuk
-- hitung mundur; render hanya kalau teksnya berubah.
task.spawn(function()
	local roundState = ReplicatedStorage:WaitForChild("RoundState")
	while true do
		local text = RoundStatus.text({
			phase = roundState:GetAttribute("Phase"),
			endsAt = roundState:GetAttribute("EndsAt"),
			winners = roundState:GetAttribute("Winners"),
			winningScore = roundState:GetAttribute("WinningScore"),
		}, workspace:GetServerTimeNow(), player.Name, player:GetAttribute("RoundScore") or 0)
		if text ~= state.round then
			state.round = text
			render()
		end
		task.wait(0.2)
	end
end)

-- BuyResult hanya mengisi pesan. Koin dan kepemilikan datang dari cermin server di bawah.
buyResult.OnClientEvent:Connect(function(itemId: string, result: string)
	local item = Config.Items[itemId]
	state.pending[itemId] = nil
	state.message = string.format(MESSAGES[result] or "%s: " .. tostring(result), if item then item.Name else itemId)
	render()
end)

player:GetAttributeChangedSignal("DataStatus"):Connect(function()
	state.status = player:GetAttribute("DataStatus")
	render()
end)

local function updateKeyHint()
	state.keyHint = UserInputService.PreferredInput == Enum.PreferredInput.KeyboardAndMouse
	render()
end
UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(updateKeyHint)
updateKeyHint()

-- B di keyboard, Y di gamepad. ContextActionService tidak memicu aksi saat pemain mengetik di chat.
ContextActionService:BindAction("ToggleShop", function(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		toggle()
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.B, Enum.KeyCode.ButtonY)

-- Cermin dibuat server setelah data dimuat (bisa beberapa detik kalau DataStore lambat).
local stats = player:WaitForChild("leaderstats", LOAD_TIMEOUT)
local coins = stats and stats:WaitForChild("Coins", LOAD_TIMEOUT) :: IntValue?
local inventory = coins and player:WaitForChild("Inventory", LOAD_TIMEOUT)
if not (coins and inventory) then
	state.failed = true
	render()
	return
end

local function onOwned(child: Instance)
	state.owned[child.Name] = true
	state.pending[child.Name] = nil
	render()
end
for _, child in inventory:GetChildren() do
	state.owned[child.Name] = true
end
inventory.ChildAdded:Connect(onOwned)

coins:GetPropertyChangedSignal("Value"):Connect(function()
	state.coins = coins.Value
	render()
end)
state.coins = coins.Value
state.loaded = true
render()
