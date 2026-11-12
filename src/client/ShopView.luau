-- Tampilan toko. Hanya menggambar state yang diberikan controller (init.client):
-- tidak membaca data pemain dan tidak memanggil remote.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

export type State = {
	loaded: boolean, -- leaderstats dan Inventory sudah sampai dari server
	failed: boolean, -- data tidak sampai dalam batas waktu
	coins: number,
	owned: { [string]: boolean },
	pending: { [string]: number }, -- itemId -> token request yang menunggu balasan
	status: string?, -- atribut DataStatus dari server
	message: string?,
	open: boolean,
	keyHint: boolean,
}

export type RowKind = "buy" | "owned" | "disabled"

-- Token desain. Kontras dicek dengan contrast-check.py (WCAG AA).
local THEME = {
	surface = Color3.fromHex("1B2130"),
	control = Color3.fromHex("2C3446"),
	-- Hanya untuk garis tepi: 5.25:1 di atas surface, tapi 4.07:1 di atas control (gagal untuk teks).
	stroke = Color3.fromHex("8A94A6"),
	text = Color3.fromHex("FFFFFF"),
	textMuted = Color3.fromHex("C5CCD8"),
	textDisabled = Color3.fromHex("AEB6C4"),
	gold = Color3.fromHex("F2C14E"), -- aksen: hanya untuk jumlah koin dan tombol Beli
	owned = Color3.fromHex("7FD49B"),
	warning = Color3.fromHex("FFB86B"),
	font = "rbxasset://fonts/families/BuilderSans.json", -- font UI Roblox sendiri
	textTitle = 22,
	textBody = 18,
	textMeta = 15,
	target = 44, -- tinggi minimum target sentuh
}

local NOTICES = {
	Offline = "Mode offline: progres tidak disimpan.",
	Locked = "Data dipakai server lain: progres sesi ini tidak disimpan.",
	Error = "Data gagal dimuat: progres sesi ini tidak disimpan.",
}

local ShopView = {}
ShopView.__index = ShopView

function ShopView.rowState(itemId: string, state: State): (string, RowKind)
	local price = Config.Items[itemId].Price
	if state.failed then
		return "Tidak tersedia", "disabled"
	elseif not state.loaded then
		return "Memuat...", "disabled"
	elseif state.owned[itemId] then
		return "Dimiliki", "owned"
	elseif state.pending[itemId] then
		return "Memproses...", "disabled"
	elseif state.coins < price then
		return `Kurang {price - state.coins} koin`, "disabled"
	end
	return "Beli", "buy"
end

function ShopView.noticeText(state: State): string?
	if state.failed then
		return "Data tidak termuat. Coba masuk ulang."
	elseif state.status == nil or state.status == "Ok" then
		return nil
	end
	return NOTICES[state.status] or "Progres sesi ini tidak disimpan."
end

local function coinsText(state: State): string
	if state.failed then
		return "Koin: -"
	elseif not state.loaded then
		return "Memuat..."
	end
	return `{state.coins} koin`
end

local function make(className: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(className)
	for key, value in props do
		(inst :: any)[key] = value
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	return inst
end

local function list(direction: Enum.FillDirection, gap: number): UIListLayout
	return make("UIListLayout", {
		FillDirection = direction,
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = if direction == Enum.FillDirection.Horizontal
			then Enum.VerticalAlignment.Center
			else Enum.VerticalAlignment.Top,
	})
end

local function padding(vertical: number, horizontal: number): UIPadding
	return make("UIPadding", {
		PaddingTop = UDim.new(0, vertical),
		PaddingBottom = UDim.new(0, vertical),
		PaddingLeft = UDim.new(0, horizontal),
		PaddingRight = UDim.new(0, horizontal),
	})
end

local function label(name: string, size: number, bold: boolean, color: Color3, order: number): TextLabel
	return make("TextLabel", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.new(), -- AutomaticSize hanya menambah, tidak pernah mengecilkan Size bawaan
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		FontFace = Font.new(THEME.font, if bold then Enum.FontWeight.Bold else Enum.FontWeight.Regular),
		TextSize = size,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})
end

-- Label yang membungkus teks: lebar penuh, tinggi mengikuti isi.
local function paragraph(name: string, color: Color3, order: number): TextLabel
	local text = label(name, THEME.textMeta, false, color, order)
	text.Size = UDim2.fromScale(1, 0)
	text.AutomaticSize = Enum.AutomaticSize.Y
	text.TextWrapped = true
	return text
end

local function button(name: string, order: number, minWidth: number): TextButton
	return make("TextButton", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.fromOffset(0, THEME.target),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = THEME.control,
		FontFace = Font.new(THEME.font, Enum.FontWeight.Bold),
		TextSize = THEME.textBody,
		TextColor3 = THEME.text,
		Text = "",
	}, {
		make("UICorner", { CornerRadius = UDim.new(0, 6) }),
		make("UIStroke", { Color = THEME.stroke, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
		make("UISizeConstraint", { MinSize = Vector2.new(minWidth, THEME.target) }),
		padding(0, 12),
	})
end

-- Satu tombol per baris; tampilannya berganti sesuai kind. Interactable=false
-- mematikan klik dan Selectable=false membuat fokus gamepad melewatinya.
local function applyKind(action: TextButton, kind: RowKind)
	local stroke = action:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Enabled = false
	action.Interactable = kind == "buy"
	action.Selectable = kind == "buy"
	action.AutoButtonColor = kind == "buy"
	action.BackgroundTransparency = if kind == "owned" then 1 else 0
	if kind == "buy" then
		action.BackgroundColor3 = THEME.gold
		action.TextColor3 = THEME.surface
	elseif kind == "owned" then
		action.TextColor3 = THEME.owned
	else
		action.BackgroundColor3 = THEME.control
		action.TextColor3 = THEME.textDisabled
	end
end

export type Handlers = {
	onToggle: () -> (),
	onBuy: (itemId: string) -> (),
}

function ShopView.new(parent: Instance, handlers: Handlers)
	local self = setmetatable({}, ShopView)
	self._actions = {} :: { [string]: TextButton }

	local hudCoins = label("Coins", THEME.textBody, true, THEME.gold, 1)
	local shopButton = button("ShopButton", 2, 88)
	local hudNotice = paragraph("Notice", THEME.warning, 2)
	hudNotice.Size = UDim2.fromOffset(280, 0)
	local hud = make("Frame", {
		Name = "Hud",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = THEME.surface,
		Active = true, -- sentuhan di latar HUD tidak ikut memutar kamera
	}, {
		make("UICorner", { CornerRadius = UDim.new(0, 8) }),
		padding(8, 12),
		list(Enum.FillDirection.Vertical, 4),
		make("Frame", {
			Name = "Bar",
			LayoutOrder = 1,
			Size = UDim2.new(),
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundTransparency = 1,
		}, { list(Enum.FillDirection.Horizontal, 12), hudCoins, shopButton }),
		hudNotice,
	})

	local title = label("Title", THEME.textTitle, true, THEME.text, 1)
	title.Text = "Toko"
	local panelCoins = label("Coins", THEME.textBody, true, THEME.gold, 2)
	local closeButton = button("CloseButton", 3, 88)
	closeButton.Text = "Tutup"
	local rows = make("ScrollingFrame", {
		Name = "List",
		LayoutOrder = 3,
		Size = UDim2.fromScale(1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = THEME.stroke,
	}, {
		list(Enum.FillDirection.Vertical, 8),
		make("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }), -- daftar mengisi sisa tinggi panel
	})
	local panelNotice = paragraph("Notice", THEME.warning, 2)
	local message = paragraph("Message", THEME.text, 4)
	-- Satu baris dipesan supaya daftar tidak bergeser saat pesan muncul.
	make("UISizeConstraint", { MinSize = Vector2.new(0, 20), Parent = message })
	local panel = make("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.9),
		BackgroundColor3 = THEME.surface,
		Active = true, -- klik/sentuhan di latar panel tidak tembus ke kamera dan karakter
		Visible = false,
		-- Fokus gamepad tidak keluar dari panel selama terbuka.
		SelectionGroup = true,
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	}, {
		make("UICorner", { CornerRadius = UDim.new(0, 8) }),
		-- 300 cukup untuk 3 baris + notice dua baris; layar lebih pendek memakai skala 0.9 dan daftar di-scroll.
		make("UISizeConstraint", { MaxSize = Vector2.new(420, 300) }),
		padding(12, 12),
		list(Enum.FillDirection.Vertical, 8),
		make("Frame", {
			Name = "Header",
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, THEME.target),
			BackgroundTransparency = 1,
		}, {
			list(Enum.FillDirection.Horizontal, 12),
			title,
			panelCoins,
			closeButton,
		}),
		panelNotice,
		rows,
		message,
	})
	make("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = title }) -- dorong Tutup ke kanan

	local ids = {}
	for itemId in Config.Items do
		table.insert(ids, itemId)
	end
	table.sort(ids, function(a, b)
		return Config.Items[a].Order < Config.Items[b].Order
	end)
	for _, itemId in ids do
		local item = Config.Items[itemId]
		local name = paragraph("ItemName", THEME.text, 1)
		name.TextSize = THEME.textBody
		name.FontFace = Font.new(THEME.font, Enum.FontWeight.Bold)
		local price = label("Price", THEME.textMeta, false, THEME.textMuted, 2)
		name.Text = item.Name
		price.Text = `{item.Price} koin`
		local action = button("Action", 2, 120)
		make("Frame", {
			Name = itemId,
			LayoutOrder = item.Order,
			Size = UDim2.new(1, -10, 0, 0), -- sisakan ruang scrollbar
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Parent = rows,
		}, {
			list(Enum.FillDirection.Horizontal, 12),
			make("Frame", {
				Name = "Info",
				LayoutOrder = 1,
				Size = UDim2.new(),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
			}, {
				list(Enum.FillDirection.Vertical, 2),
				make("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }),
				name,
				price,
			}),
			action,
		})
		action.Activated:Connect(function()
			handlers.onBuy(itemId)
		end)
		self._actions[itemId] = action
	end
	self._ids = ids

	shopButton.Activated:Connect(handlers.onToggle)
	closeButton.Activated:Connect(handlers.onToggle)

	self.gui = make("ScreenGui", {
		Name = "ShopGui",
		ResetOnSpawn = false, -- dibuat sekali oleh script ini; respawn tidak boleh menghapusnya
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, { hud, panel })
	self.panel = panel
	self._hud = hud
	self._hudCoins = hudCoins
	self._hudNotice = hudNotice
	self._shopButton = shopButton
	self._panelCoins = panelCoins
	self._panelNotice = panelNotice
	self._message = message
	self._closeButton = closeButton
	self.gui.Parent = parent
	return self
end

function ShopView:render(state: State)
	local notice = ShopView.noticeText(state)
	self._hud.Visible = not state.open
	self.panel.Visible = state.open
	self._hudCoins.Text = coinsText(state)
	self._panelCoins.Text = coinsText(state)
	self._shopButton.Text = if state.keyHint then "Toko (B)" else "Toko"
	self._hudNotice.Text = notice or ""
	self._hudNotice.Visible = notice ~= nil
	self._panelNotice.Text = notice or ""
	self._panelNotice.Visible = notice ~= nil
	self._message.Text = state.message or ""
	for itemId, action in self._actions do
		local text, kind = ShopView.rowState(itemId, state)
		action.Text = text
		applyKind(action, kind)
	end
end

-- Target fokus gamepad: tombol Beli pertama menurut urutan toko, atau Tutup.
function ShopView:focusTarget(): GuiObject
	for _, itemId in self._ids do
		if self._actions[itemId].Selectable then
			return self._actions[itemId]
		end
	end
	return self._closeButton
end

return ShopView
