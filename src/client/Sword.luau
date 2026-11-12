-- Pedang di client: saat pemain mengayun, usulkan target terdekat ke server. Server yang
-- memutuskan kena atau tidak; client tidak pernah mengubah nyawa siapa pun.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local SWORD = "Pedang" -- nama Tool yang dibuat server (Combat.luau)

local Sword = {}

-- Model hidup terdekat dalam jangkauan, atau nil. Hanya usulan: server mengecek ulang semuanya.
function Sword.pickTarget(character: Model): Model?
	local root = character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return nil
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local best, bestDistance = nil, math.huge
	for _, part in Workspace:GetPartBoundsInRadius(root.Position, Config.Combat.Range, params) do
		local model = part:FindFirstAncestorOfClass("Model")
		local humanoid = model and model:FindFirstChildOfClass("Humanoid")
		local targetRoot = model and model:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and targetRoot and targetRoot:IsA("BasePart") then
			local distance = (targetRoot.Position - root.Position).Magnitude
			if distance <= Config.Combat.Range and distance < bestDistance then
				best, bestDistance = model, distance
			end
		end
	end
	return best
end

function Sword.start(player: Player, attack: RemoteEvent)
	-- Pedang baru dibuat tiap spawn; satu koneksi per Tool walau dipegang dan dilepas berkali-kali.
	local hooked = setmetatable({}, { __mode = "k" }) :: { [Instance]: boolean }
	local function hook(child: Instance)
		if child:IsA("Tool") and child.Name == SWORD and not hooked[child] then
			hooked[child] = true
			child.Activated:Connect(function()
				local character = player.Character
				if character then
					-- nil berarti ayunan meleset; server tetap memainkan animasi dan cooldown.
					attack:FireServer(Sword.pickTarget(character))
				end
			end)
		end
	end
	-- Karakter lama tidak di-Destroy saat respawn (diukur Hari 9), jadi koneksinya diputus sendiri.
	local childAdded: RBXScriptConnection? = nil
	local function onCharacter(character: Model)
		if childAdded then
			childAdded:Disconnect()
		end
		childAdded = character.ChildAdded:Connect(hook) -- Tool pindah ke karakter saat dipegang
		for _, child in character:GetChildren() do
			hook(child)
		end
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
end

return Sword
