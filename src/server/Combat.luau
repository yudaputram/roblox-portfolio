-- Pedang: server memutuskan setiap serangan. Client hanya mengusulkan target lewat remote
-- Attack; posisi dan nyawa selalu dibaca dari sisi server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local RateLimit = require(script.Parent.RateLimit)

local SWORD = "Pedang"
local DUMMY_TAG = "CombatDummy"
local DUMMY_POSITION = Vector3.new(0, 2, -20) -- 20 stud dari titik spawn, di dalam radius streaming

local Combat = {}
Combat.__index = Combat
Combat.SWORD = SWORD
Combat.DUMMY_TAG = DUMMY_TAG

-- Tanpa efek samping: tes bisa membuat instance baru tanpa pedang kedua atau boneka kedua.
function Combat.new(playerData)
	local self = setmetatable({}, Combat)
	self._playerData = playerData
	self._lastSwing = {} :: { [Player]: number }
	self._characterAdded = {} :: { [Player]: RBXScriptConnection }
	self._requests = RateLimit.new(Config.Combat.RequestBurst, Config.Combat.RequestsPerSecond)
	return self
end

-- Animate bawaan di client memainkan ayunan saat melihat StringValue "toolanim". Client hanya
-- menghapus salinannya sendiri, jadi salinan server dihapus di sini supaya tidak menumpuk.
local function playSlash(sword: Tool)
	local anim = Instance.new("StringValue")
	anim.Name = "toolanim"
	anim.Value = "Slash"
	anim.Parent = sword
	task.delay(1, anim.Destroy, anim)
end

-- target bertipe unknown: client exploit bisa mengirim apa saja. Cek dari yang paling murah.
-- Mengembalikan (kena, alasan) supaya bisa dites langsung tanpa remote; now disuntik oleh tes.
function Combat:attack(player: Player, target: unknown, now: number): (boolean, string)
	-- Request yang ditolak cooldown tidak memperbarui waktu, jadi spam tidak memperpanjang jeda.
	local last = self._lastSwing[player]
	if last and now - last < Config.Combat.Cooldown then
		return false, "Cooldown"
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and humanoid and root and root:IsA("BasePart") and humanoid.Health > 0) then
		return false, "Dead"
	end
	local sword = character:FindFirstChild(SWORD)
	if not (sword and sword:IsA("Tool")) then
		return false, "NotEquipped" -- pedang masih di Backpack
	end
	-- Mulai di sini ayunan sah: meleset atau ditolak tetap memakai jatah cooldown.
	self._lastSwing[player] = now
	playSlash(sword)

	if target == nil then
		return false, "NoTarget"
	end
	if typeof(target) ~= "Instance" or not target:IsA("Model") or not target:IsDescendantOf(Workspace) then
		return false, "BadTarget"
	end
	-- Hanya karakter pemain yang sedang aktif atau boneka yang ditandai server.
	if not (Players:GetPlayerFromCharacter(target) or target:HasTag(DUMMY_TAG)) then
		return false, "BadTarget"
	end
	if target == character then
		return false, "Self"
	end
	local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
	local targetRoot = target:FindFirstChild("HumanoidRootPart")
	if not (targetHumanoid and targetRoot and targetRoot:IsA("BasePart")) then
		return false, "BadTarget"
	end
	if targetHumanoid.Health <= 0 then
		return false, "TargetDead"
	end
	-- Jarak dari posisi yang dilihat server, bukan dari angka kiriman client.
	if (targetRoot.Position - root.Position).Magnitude > Config.Combat.Range then
		return false, "TooFar"
	end

	targetHumanoid:TakeDamage(Config.Combat.Damage)
	if targetHumanoid.Health > 0 then
		return true, "Hit"
	end
	-- Target hidup sebelum pukulan ini dan tidak ada yield sejak dicek, jadi hanya pukulan
	-- ini yang membunuhnya: hadiah dibayar tepat sekali per kill.
	self._playerData:addCoins(player, Config.Combat.KillReward)
	return true, "Kill"
end

local function makeSword(): Tool
	local tool = Instance.new("Tool")
	tool.Name = SWORD
	tool.CanBeDropped = false
	tool.ToolTip = "Klik atau ketuk untuk menyerang"
	tool.GripPos = Vector3.new(0, 0, -1.5) -- pegang di pangkal, bilah ke depan
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 0.8, 4)
	handle.Color = Color3.fromRGB(200, 205, 215)
	handle.Material = Enum.Material.Metal
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool
	return tool
end

-- Backpack diganti baru setiap spawn, jadi pedang diberikan ulang per karakter.
function Combat:giveSword(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end
	-- Jalur CharacterAdded dan karakter yang sudah ada bisa jalan dua-duanya.
	local character = player.Character
	if backpack:FindFirstChild(SWORD) or (character and character:FindFirstChild(SWORD)) then
		return
	end
	makeSword().Parent = backpack
end

function Combat:addPlayer(player: Player)
	self._characterAdded[player] = player.CharacterAdded:Connect(function()
		self:giveSword(player)
	end)
	if player.Character then
		self:giveSword(player)
	end
end

function Combat:removePlayer(player: Player)
	self._lastSwing[player] = nil
	self._requests:removePlayer(player)
	local connection = self._characterAdded[player]
	if connection then
		connection:Disconnect()
		self._characterAdded[player] = nil
	end
end

-- Boneka latihan: target untuk mencoba pedang sendirian. Hidup lagi beberapa detik setelah mati.
local function spawnDummy()
	local model = Instance.new("Model")
	model.Name = "BonekaLatihan"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 4, 1)
	root.Position = DUMMY_POSITION
	root.Anchored = true
	root.Color = Color3.fromRGB(150, 110, 70)
	root.Parent = model
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2, 1, 1)
	head.Position = DUMMY_POSITION + Vector3.new(0, 2.5, 0)
	head.Anchored = true
	head.Color = root.Color
	head.Parent = model
	local humanoid = Instance.new("Humanoid")
	humanoid.DisplayName = "Boneka Latihan"
	humanoid.Parent = model
	model.PrimaryPart = root
	model:AddTag(DUMMY_TAG)
	model.Parent = Workspace

	humanoid.Died:Once(function()
		task.delay(Config.Combat.DummyRespawn, function()
			model:Destroy()
			spawnDummy()
		end)
	end)
end

-- Pintu remote: banjir request dibuang sebelum validasi apa pun. Cooldown di attack tetap
-- aturan ayunannya; batas ini hanya melindungi server dari request yang tidak perlu.
function Combat:request(player: Player, target: unknown, now: number): (boolean, string)
	if not self._requests:allow(player, now) then
		return false, "RateLimited"
	end
	return self:attack(player, target, now)
end

function Combat:start(attack: RemoteEvent)
	attack.OnServerEvent:Connect(function(player: Player, target: unknown)
		self:request(player, target, os.clock())
	end)
	spawnDummy()
end

return Combat
