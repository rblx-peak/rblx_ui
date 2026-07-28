--!strict
-- LOADOUT — saved builds, Pottery Clash arcade family (doc §7.4 modal card).
--
-- Top-left: three preset tabs (A/B/C). The ACTIVE tab's name line is a live
-- TextBox (tap the active tab again to rename; inactive tabs render plain
-- labels so a switch-click never steals text focus). Selection is stroke-only
-- (§4.3): the active tab wears the gold ring, fills never change.
--
-- Left: the equipment grid — six named slots (PRIMARY/SECONDARY/ARMOR/
-- TRINKET/CONSUMABLE/COMPANION), each a near-black well showing the equipped
-- item inside a rarity-tinted ring (the inventory screen's ring recipe:
-- selection-stroke policy re-tinted to the rarity colour) or a muted EMPTY
-- state. Clicking a slot marks it with the gold ring and fills the right-hand
-- picker with every owned candidate for that slot; EQUIP swaps in place.
--
-- Bottom-left: SAVE PRESET (green) plus a "COPY TO" row targeting the other
-- two presets. Show(data) = { presets = {{id, name, slots}}, owned = {{id,
-- name, icon, rarity, slot}}, onSave = function(preset)? }.
--
-- Fixed px at the 1650×1020 baseline (UIScreenBase attaches the UIScale).

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UIScreenBase = require(script.Parent.UIScreenBase)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)

type OwnedItem = {
	id: string,
	name: string,
	icon: string?,
	rarity: string?,
	slot: string,
}
type Preset = {
	id: string,
	name: string,
	slots: { [string]: string }, -- slotId -> owned item id
}

local WHITE = Color3.new(1, 1, 1)

-- Card 1240×680 → content 1212×592 after the §7.4 inset.
local CARD = Vector2.new(1240, 680)
local CONTENT_W, CONTENT_H = 1212, 592
local TAB_W, TAB_H = 220, 72
local TAB_GAP = 12
local GRID_Y = 88
local CELL_W, CELL_H = 220, 198
local CELL_GAP = 12
local FOOT_Y = 516
local PICKER_X = 712
local PICKER_W = CONTENT_W - PICKER_X
local PICKER_ROW_H = 76
local NAME_MAX = 14

-- The six equipment slots. SECONDARY carries the target crosshair (the
-- archive ships no gun) — it reads "ranged sidearm" cleanly.
local SLOT_DEFS = {
	{ id = "primary", label = "PRIMARY", icon = "sword" },
	{ id = "secondary", label = "SECONDARY", icon = "target" },
	{ id = "armor", label = "ARMOR", icon = "shield" },
	{ id = "trinket", label = "TRINKET", icon = "key" },
	{ id = "consumable", label = "CONSUMABLE", icon = "potion" },
	{ id = "companion", label = "COMPANION", icon = "paw" },
}

local RARITY_RANK: { [string]: number } = {
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
}

-- The rarity ramp climbs the ShopAccents rotation (doc §3.2) for the tiers
-- that shout, and stays on OWNED grey / arcade green for the quiet ones —
-- the same mapping the inventory screen ships.
local function rarityColor(theme: Types.UITheme, rarity: string?): Color3
	local accents = theme.Arcade.ShopAccents
	if rarity == "Legendary" then
		return accents[2]
	elseif rarity == "Epic" then
		return accents[4]
	elseif rarity == "Rare" then
		return accents[3]
	elseif rarity == "Uncommon" then
		return theme.Arcade.Green
	end
	return theme.Arcade.GreyOwned
end

local function demoOwned(): { OwnedItem }
	return {
		{ id = "emberBlade", name = "EMBER BLADE", icon = "sword", rarity = "Epic", slot = "primary" },
		{ id = "kilnSaber", name = "KILN SABER", icon = "sword", rarity = "Rare", slot = "primary" },
		{ id = "clayCleaver", name = "CLAY CLEAVER", icon = "axe", rarity = "Common", slot = "primary" },
		{ id = "shardSling", name = "SHARD SLING", icon = "target", rarity = "Rare", slot = "secondary" },
		{ id = "mudMortar", name = "MUD MORTAR", icon = "target", rarity = "Common", slot = "secondary" },
		{ id = "stonewarePlate", name = "STONEWARE PLATE", icon = "shield", rarity = "Epic", slot = "armor" },
		{ id = "bisqueGuard", name = "BISQUE GUARD", icon = "shield", rarity = "Uncommon", slot = "armor" },
		{ id = "glazeCharm", name = "GLAZE CHARM", icon = "sparkle", rarity = "Legendary", slot = "trinket" },
		{ id = "pottersKey", name = "POTTER'S KEY", icon = "key", rarity = "Uncommon", slot = "trinket" },
		{ id = "firingFlask", name = "FIRING FLASK", icon = "potion", rarity = "Rare", slot = "consumable" },
		{ id = "slipTonic", name = "SLIP TONIC", icon = "potion", rarity = "Common", slot = "consumable" },
		{ id = "kilnCat", name = "KILN CAT", icon = "paw", rarity = "Legendary", slot = "companion" },
		{ id = "dustPup", name = "DUST PUP", icon = "paw", rarity = "Uncommon", slot = "companion" },
	}
end

local function demoPresets(): { Preset }
	return {
		{
			id = "A",
			name = "STRIKER",
			slots = { primary = "emberBlade", secondary = "shardSling", armor = "bisqueGuard", consumable = "firingFlask" },
		},
		{
			id = "B",
			name = "BULWARK",
			slots = { primary = "clayCleaver", armor = "stonewarePlate", trinket = "pottersKey", companion = "dustPup" },
		},
		{
			id = "C",
			name = "FARM RUN",
			slots = { consumable = "slipTonic", companion = "kilnCat" },
		},
	}
end

local LoadoutScreen = setmetatable({}, { __index = UIScreenBase })
LoadoutScreen.__index = LoadoutScreen

function LoadoutScreen.new()
	local self = UIScreenBase.new("LoadoutScreen", 7)
	self._presets = demoPresets() :: { Preset }
	self._owned = demoOwned() :: { OwnedItem }
	self._onSave = nil :: ((Preset) -> ())?
	self._active = 1
	self._pickerSlot = nil :: string?
	-- Component instances rebuilt with their sections, destroyed before clear.
	self._pickerButtons = {} :: { any }
	self._copyButtons = {} :: { any }
	return setmetatable(self, LoadoutScreen)
end

function LoadoutScreen:_Toast(text: string, variant: string)
	local hud = self.ScreenController and self.ScreenController:GetScreen("hud")
	if hud then
		hud:PushToast({ text = text, variant = variant })
	end
end

function LoadoutScreen:_Ingest(data: any)
	if type(data) ~= "table" then
		return
	end
	if type(data.presets) == "table" and #data.presets > 0 then
		self._presets = data.presets
		self._active = 1
		self._pickerSlot = nil
	end
	if type(data.owned) == "table" then
		self._owned = data.owned
	end
	if type(data.onSave) == "function" then
		self._onSave = data.onSave
	end
end

function LoadoutScreen:_ActivePreset(): Preset
	return (self._presets :: { Preset })[self._active]
end

function LoadoutScreen:_ItemById(id: string?): OwnedItem?
	for _, item in self._owned :: { OwnedItem } do
		if item.id == id then
			return item
		end
	end
	return nil
end

function LoadoutScreen:_OwnedForSlot(slotId: string): { OwnedItem }
	local out = {}
	for _, item in self._owned :: { OwnedItem } do
		if item.slot == slotId then
			table.insert(out, item)
		end
	end
	table.sort(out, function(a, b)
		local ra = RARITY_RANK[a.rarity or ""] or 0
		local rb = RARITY_RANK[b.rarity or ""] or 0
		if ra ~= rb then
			return ra > rb
		end
		return a.name < b.name
	end)
	return out
end

function LoadoutScreen:_EquippedCount(preset: Preset): number
	local n = 0
	for _, def in SLOT_DEFS do
		if preset.slots[def.id] then
			n += 1
		end
	end
	return n
end

-- ========================================================================
-- Build
-- ========================================================================

function LoadoutScreen:_BuildContent()
	-- GP layout language: the pastel SHELF of saved builds (cream page, rose
	-- ribbon, petal slot cells alternating mirror, rarity chips off the pack's
	-- glaze ramp) — see _BuildGPLayout below.
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end

	local theme = self:GetTheme()

	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = "LOADOUT",
		sizePx = CARD,
		onClose = function()
			self.ScreenController:HideScreen("loadout")
		end,
	})
	self._modal = modal
	local content = modal.content

	local tabs = UIStyler.Frame("Tabs")
	tabs.BackgroundTransparency = 1
	tabs.Size = UDim2.fromOffset((TAB_W + TAB_GAP) * 3, TAB_H)
	tabs.ZIndex = 43
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, TAB_GAP),
	}).Parent = tabs
	tabs.Parent = content
	self._tabs = tabs

	local grid = UIStyler.Frame("Grid")
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.fromOffset(0, GRID_Y)
	grid.Size = UDim2.fromOffset(CELL_W * 3 + CELL_GAP * 2, CELL_H * 2 + CELL_GAP)
	grid.ZIndex = 43
	grid.Parent = content
	self._grid = grid

	self._saveBtn = UIButtonComponent.new()
	self._saveBtn:Create(content, {
		text = "SAVE PRESET",
		variant = "Green",
		size = UDim2.fromOffset(220, 56),
		position = UDim2.fromOffset(0, FOOT_Y),
		onClick = function()
			self:_SavePreset()
		end,
	})
	self._saveBtn.Root.ZIndex = 44

	local copyLabel = UIChrome.Text("CopyLabel", 18, WHITE)
	copyLabel.Text = "COPY TO:"
	copyLabel.TextXAlignment = Enum.TextXAlignment.Left
	copyLabel.Position = UDim2.fromOffset(244, FOOT_Y)
	copyLabel.Size = UDim2.fromOffset(96, 56)
	copyLabel.ZIndex = 44
	copyLabel.Parent = content

	local copyRow = UIStyler.Frame("CopyRow")
	copyRow.BackgroundTransparency = 1
	copyRow.Position = UDim2.fromOffset(344, FOOT_Y)
	copyRow.Size = UDim2.fromOffset(200, 56)
	copyRow.ZIndex = 44
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
	}).Parent = copyRow
	copyRow.Parent = content
	self._copyRow = copyRow

	self:_BuildPicker(theme, content)

	self:_RenderTabs()
	self:_RenderGrid()
	self:_RenderCopyRow()
	self:_RenderPicker()
end

function LoadoutScreen:_BuildPicker(theme: Types.UITheme, content: Frame)
	local panel = UIChrome.Panel(theme, "Arcade", "Picker")
	panel.Position = UDim2.fromOffset(PICKER_X, 0)
	panel.Size = UDim2.fromOffset(PICKER_W, CONTENT_H)
	panel.ZIndex = 43
	panel.Parent = content
	self._pickerPanel = panel

	local title = UIChrome.Text("PickerTitle", 22, theme.Arcade.Gold)
	title.Text = "PICK A SLOT"
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Position = UDim2.fromOffset(14, 12)
	title.Size = UDim2.new(1, -28, 0, 28)
	title.ZIndex = 44
	title.Parent = panel
	self._pickerTitle = title

	local hint = UIChrome.BodyText("PickerHint", 14, theme.Colors.TextSecondary)
	hint.Text = "Click any slot on the left to see everything you own for it."
	hint.TextWrapped = true
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextYAlignment = Enum.TextYAlignment.Top
	hint.Position = UDim2.fromOffset(14, 48)
	hint.Size = UDim2.new(1, -28, 0, 60)
	hint.ZIndex = 44
	hint.Parent = panel
	self._pickerHint = hint

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "PickerList"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(14, 52)
	scroll.Size = UDim2.new(1, -22, 1, -66)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = theme.Arcade.Gold
	scroll.ZIndex = 44
	UIStyler.ListLayout({
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 8),
	}).Parent = scroll
	scroll.Parent = panel
	self._pickerList = scroll
end

-- ========================================================================
-- Tabs
-- ========================================================================

function LoadoutScreen:_RenderTabs()
	-- GP pastel shelf: the same three preset plates, keeping the live rename
	-- box on the active one (see _GPRenderTabs).
	if self:LayoutKit() == "GP" then
		self:_GPRenderTabs()
		return
	end

	local theme = self:GetTheme()
	for _, child in self._tabs:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	for index, preset in self._presets :: { Preset } do
		local active = index == self._active

		local tab = UIStyler.Frame("Tab_" .. preset.id)
		tab.BackgroundTransparency = 1
		tab.Size = UDim2.fromOffset(TAB_W, TAB_H)
		tab.LayoutOrder = index
		tab.Parent = self._tabs

		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Text = ""
		hit.BackgroundTransparency = 1
		hit.AutoButtonColor = false
		hit.Size = UDim2.fromScale(1, 1)
		hit.ZIndex = 1
		hit.Parent = tab

		-- Selection is stroke-only (§4.3): fill identical either way.
		local surface = UIStyler.Frame("Surface")
		surface.BackgroundColor3 = theme.Arcade.Row
		surface.BackgroundTransparency = theme.Arcade.RowTransparency
		surface.AnchorPoint = Vector2.new(0.5, 0.5)
		surface.Position = UDim2.fromScale(0.5, 0.5)
		surface.Size = UDim2.fromScale(1, 1)
		surface.ZIndex = 2
		UIChrome.Stroke(theme, "Arcade", if active then "Selection" else "Panel").Parent = surface
		UIChrome.GlassGradient().Parent = surface
		surface.Parent = tab

		local chip = UIStyler.Frame("Letter")
		chip.BackgroundColor3 = if active then theme.Arcade.Gold else theme.Arcade.NearBlack
		chip.Position = UDim2.fromOffset(12, 14)
		chip.Size = UDim2.fromOffset(44, 44)
		chip.ZIndex = 3
		UIChrome.Stroke(theme, "Arcade", "Panel").Parent = chip
		UIChrome.GlassGradient().Parent = chip
		chip.Parent = surface

		local letter = UIChrome.Text("A", 24, if active then theme.Arcade.NearBlack else WHITE)
		letter.Text = preset.id
		letter.Size = UDim2.fromScale(1, 1)
		letter.ZIndex = 4
		letter.Parent = chip

		-- Only the ACTIVE tab gets a live TextBox — an inactive tab's click
		-- must switch presets, never capture text focus.
		if active then
			local box = Instance.new("TextBox")
			box.Name = "NameBox"
			box.BackgroundTransparency = 1
			box.BorderSizePixel = 0
			box.ClearTextOnFocus = false
			box.Text = preset.name
			box.PlaceholderText = "NAME ME"
			box.PlaceholderColor3 = theme.Arcade.GreyOwned
			box.FontFace = theme.Fonts.Title
			box.TextSize = 18
			box.TextColor3 = WHITE
			box.TextXAlignment = Enum.TextXAlignment.Left
			box.TextTruncate = Enum.TextTruncate.AtEnd
			box.Position = UDim2.fromOffset(68, 10)
			box.Size = UDim2.fromOffset(TAB_W - 80, 26)
			box.ZIndex = 3
			UIChrome.TextOutline(box)
			box.Parent = surface
			box:GetPropertyChangedSignal("Text"):Connect(function()
				local up = string.upper(box.Text)
				if #up > NAME_MAX then
					up = string.sub(up, 1, NAME_MAX)
				end
				if box.Text ~= up then
					box.Text = up
				end
			end)
			box.FocusLost:Connect(function()
				local name = string.upper((string.gsub(box.Text, "^%s*(.-)%s*$", "%1")))
				if name == "" then
					name = "LOADOUT " .. preset.id
				end
				box.Text = name
				if preset.name ~= name then
					preset.name = name
					self:_Toast(string.format("Renamed to %s.", name), "Success")
					UIChrome.Pulse(theme, surface)
				end
			end)
			self._nameBox = box
		else
			local name = UIChrome.Text("Name", 18, WHITE)
			name.Text = preset.name
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.TextTruncate = Enum.TextTruncate.AtEnd
			name.Position = UDim2.fromOffset(68, 10)
			name.Size = UDim2.fromOffset(TAB_W - 80, 26)
			name.ZIndex = 3
			name.Parent = surface
		end

		local sub = UIChrome.BodyText("Sub", 12, theme.Colors.TextSecondary)
		sub.Text = if active
			then "TAP NAME TO RENAME"
			else string.format("%d/%d EQUIPPED", self:_EquippedCount(preset), #SLOT_DEFS)
		sub.TextXAlignment = Enum.TextXAlignment.Left
		sub.Position = UDim2.fromOffset(68, 42)
		sub.Size = UDim2.fromOffset(TAB_W - 80, 18)
		sub.ZIndex = 3
		sub.Parent = surface

		hit.Activated:Connect(function()
			if index == self._active then
				-- Rename affordance: re-tapping the active tab focuses the box.
				if self._nameBox then
					self._nameBox:CaptureFocus()
				end
			else
				self:_SetActive(index)
			end
		end)
		UIChrome.Animate(theme, hit, surface)
	end
end

function LoadoutScreen:_SetActive(index: number)
	self._active = index
	self._pickerSlot = nil
	self:_RenderTabs()
	self:_RenderGrid()
	self:_RenderCopyRow()
	self:_RenderPicker()
end

-- ========================================================================
-- Equipment grid
-- ========================================================================

function LoadoutScreen:_RenderGrid()
	-- GP pastel shelf: the same six slot cells (see _GPRenderGrid).
	if self:LayoutKit() == "GP" then
		self:_GPRenderGrid()
		return
	end

	local theme = self:GetTheme()
	for _, child in self._grid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local preset = self:_ActivePreset()
	for index, def in SLOT_DEFS do
		self:_BuildSlotCell(theme, preset, def, index)
	end
end

function LoadoutScreen:_BuildSlotCell(theme: Types.UITheme, preset: Preset, def: { id: string, label: string, icon: string }, index: number)
	local col = (index - 1) % 3
	local row = (index - 1) // 3
	local picking = self._pickerSlot == def.id
	local item = self:_ItemById(preset.slots[def.id])

	local cell = UIStyler.Frame("Slot_" .. def.id)
	cell.BackgroundTransparency = 1
	cell.Position = UDim2.fromOffset(col * (CELL_W + CELL_GAP), row * (CELL_H + CELL_GAP))
	cell.Size = UDim2.fromOffset(CELL_W, CELL_H)
	cell.Parent = self._grid

	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 1
	hit.Parent = cell

	local surface = UIStyler.Frame("Surface")
	surface.BackgroundColor3 = theme.Arcade.NearBlack
	surface.AnchorPoint = Vector2.new(0.5, 0.5)
	surface.Position = UDim2.fromScale(0.5, 0.5)
	surface.Size = UDim2.fromScale(1, 1)
	surface.ZIndex = 2
	UIChrome.Stroke(theme, "Arcade", if picking then "Selection" else "Panel").Parent = surface
	UIChrome.GlassGradient().Parent = surface
	surface.Parent = cell

	local slotName = UIChrome.Text("SlotName", 15, theme.Arcade.Gold)
	slotName.Text = def.label
	slotName.Position = UDim2.fromOffset(6, 8)
	slotName.Size = UDim2.new(1, -12, 0, 20)
	slotName.ZIndex = 3
	slotName.Parent = surface

	if item then
		-- Rarity ring: the selection-stroke policy re-tinted to the rarity
		-- colour (the inventory screen's recipe, doc §3.3 rarity-tints-stroke).
		local ring = UIStyler.Frame("RarityRing")
		ring.BackgroundTransparency = 1
		ring.AnchorPoint = Vector2.new(0.5, 0)
		ring.Position = UDim2.new(0.5, 0, 0, 36)
		ring.Size = UDim2.fromOffset(100, 100)
		ring.ZIndex = 3
		local ringStroke = UIChrome.Stroke(theme, "Arcade", "Selection")
		ringStroke.Color = rarityColor(theme, item.rarity)
		ringStroke.Parent = ring
		ring.Parent = surface

		local icon = IconArchive.Image(ring, item.icon or def.icon, 72, { golden = item.rarity == "Legendary" })
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.ZIndex = 4

		local name = UIChrome.Text("ItemName", 15, WHITE)
		name.Text = item.name
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Position = UDim2.fromOffset(6, 144)
		name.Size = UDim2.new(1, -12, 0, 20)
		name.ZIndex = 3
		name.Parent = surface

		local rarity = UIChrome.Text("Rarity", 12, rarityColor(theme, item.rarity))
		rarity.Text = string.upper(item.rarity or "COMMON")
		rarity.Position = UDim2.fromOffset(6, 166)
		rarity.Size = UDim2.new(1, -12, 0, 16)
		rarity.ZIndex = 3
		rarity.Parent = surface
	else
		-- EMPTY state: muted slot glyph + labels, dimmed in place — the well
		-- keeps its chrome and stays fully tappable (§11.2).
		local ghost = IconArchive.Image(surface, def.icon, 56)
		ghost.AnchorPoint = Vector2.new(0.5, 0)
		ghost.Position = UDim2.new(0.5, 0, 0, 48)
		ghost.ZIndex = 3
		if ghost:IsA("ImageLabel") then
			ghost.ImageTransparency = 0.6
		elseif ghost:IsA("TextLabel") then
			ghost.TextTransparency = 0.6
		end

		local empty = UIChrome.Text("Empty", 16, theme.Arcade.GreyOwned)
		empty.Text = "- EMPTY -"
		empty.Position = UDim2.fromOffset(6, 118)
		empty.Size = UDim2.new(1, -12, 0, 22)
		empty.ZIndex = 3
		empty.Parent = surface

		local tap = UIChrome.BodyText("Tap", 12, theme.Colors.TextSecondary)
		tap.Text = "TAP TO EQUIP"
		tap.Position = UDim2.fromOffset(6, 146)
		tap.Size = UDim2.new(1, -12, 0, 16)
		tap.ZIndex = 3
		tap.Parent = surface
	end

	hit.Activated:Connect(function()
		self:_OpenPicker(def.id)
	end)
	UIChrome.Animate(theme, hit, surface)
end

-- ========================================================================
-- Picker
-- ========================================================================

function LoadoutScreen:_SlotDef(slotId: string?): { id: string, label: string, icon: string }?
	for _, def in SLOT_DEFS do
		if def.id == slotId then
			return def
		end
	end
	return nil
end

function LoadoutScreen:_OpenPicker(slotId: string)
	self._pickerSlot = slotId
	self:_RenderGrid()
	self:_RenderPicker()
	UIChrome.Pulse(self:GetTheme(), self._pickerPanel)
end

function LoadoutScreen:_RenderPicker()
	-- GP pastel shelf: the same candidate ledger (see _GPRenderPicker).
	if self:LayoutKit() == "GP" then
		self:_GPRenderPicker()
		return
	end

	local theme = self:GetTheme()
	for _, component in self._pickerButtons do
		component:Destroy()
	end
	table.clear(self._pickerButtons)
	for _, child in self._pickerList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local def = self:_SlotDef(self._pickerSlot)
	if not def then
		self._pickerTitle.Text = "PICK A SLOT"
		self._pickerHint.Text = "Click any slot on the left to see everything you own for it."
		self._pickerHint.Visible = true
		return
	end

	local candidates = self:_OwnedForSlot(def.id)
	self._pickerTitle.Text = string.format("EQUIP  ·  %s", def.label)
	self._pickerHint.Visible = #candidates == 0
	if #candidates == 0 then
		self._pickerHint.Text = string.format("You own nothing for the %s slot yet.", def.label)
		return
	end

	local preset = self:_ActivePreset()
	for order, item in candidates do
		self:_BuildPickerRow(theme, preset, def, item, order)
	end
end

function LoadoutScreen:_BuildPickerRow(theme: Types.UITheme, preset: Preset, def: { id: string, label: string, icon: string }, item: OwnedItem, order: number)
	local equipped = preset.slots[def.id] == item.id
	local rowW = PICKER_W - 36 -- panel padding + scrollbar reserve

	local row = UIStyler.Frame("Row" .. order)
	-- Zebra by list position (doc §9 row grammar), both fills at 0.15.
	row.BackgroundColor3 = if order % 2 == 1 then theme.Arcade.NearBlack2 else theme.Arcade.Row
	row.BackgroundTransparency = 0.15
	row.LayoutOrder = order
	row.Size = UDim2.fromOffset(rowW, PICKER_ROW_H)
	row.ZIndex = 44
	UIChrome.Corner("Arcade").Parent = row
	UIChrome.Stroke(theme, "Arcade", "Panel").Parent = row
	UIChrome.GlassGradient().Parent = row
	row.Parent = self._pickerList

	local icon = IconArchive.Image(row, item.icon or def.icon, 44, { golden = item.rarity == "Legendary" })
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 12, 0.5, 0)
	icon.ZIndex = 45

	local name = UIChrome.Text("Name", 18, WHITE)
	name.Text = item.name
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(68, 12)
	name.Size = UDim2.fromOffset(rowW - 200, 24)
	name.ZIndex = 45
	name.Parent = row

	local rarity = UIChrome.Text("Rarity", 13, rarityColor(theme, item.rarity))
	rarity.Text = string.upper(item.rarity or "COMMON")
	rarity.TextXAlignment = Enum.TextXAlignment.Left
	rarity.Position = UDim2.fromOffset(68, 40)
	rarity.Size = UDim2.fromOffset(rowW - 200, 18)
	rarity.ZIndex = 45
	rarity.Parent = row

	-- EQUIPPED recolours grey in place (§11.2); the tap still answers.
	local button = UIButtonComponent.new()
	button:Create(row, {
		text = if equipped then "EQUIPPED" else "EQUIP",
		variant = if equipped then "Grey" else "Green",
		size = UDim2.fromOffset(112, 44),
		position = UDim2.new(1, -10, 0.5, 0),
		anchorPoint = Vector2.new(1, 0.5),
		onClick = function()
			if preset.slots[def.id] == item.id then
				self:_Toast(string.format("%s is already equipped.", item.name), "Info")
				return
			end
			self:_Equip(def, item)
		end,
	})
	button.Root.ZIndex = 46
	table.insert(self._pickerButtons, button)
end

function LoadoutScreen:_Equip(def: { id: string, label: string, icon: string }, item: OwnedItem)
	local preset = self:_ActivePreset()
	preset.slots[def.id] = item.id
	self:_Toast(string.format("%s equipped to %s.", item.name, def.label), "Success")
	self:_RenderGrid()
	self:_RenderPicker()
	self:_RenderTabs() -- the inactive tabs' equipped counts
end

-- ========================================================================
-- Save / copy
-- ========================================================================

function LoadoutScreen:_RenderCopyRow()
	-- GP pastel shelf: the same copy targets as petal chips (see _GPRenderCopyRow).
	if self:LayoutKit() == "GP" then
		self:_GPRenderCopyRow()
		return
	end

	for _, component in self._copyButtons do
		component:Destroy()
	end
	table.clear(self._copyButtons)

	for index, preset in self._presets :: { Preset } do
		if index ~= self._active then
			local targetIndex = index
			local button = UIButtonComponent.new()
			button:Create(self._copyRow, {
				text = preset.id,
				variant = "Blue",
				size = UDim2.fromOffset(64, 56),
				layoutOrder = index,
				onClick = function()
					self:_CopyTo(targetIndex)
				end,
			})
			button.Root.ZIndex = 45
			table.insert(self._copyButtons, button)
		end
	end
end

function LoadoutScreen:_CopyTo(targetIndex: number)
	local source = self:_ActivePreset()
	local target = (self._presets :: { Preset })[targetIndex]
	if not target then
		return
	end
	target.slots = table.clone(source.slots)
	self:_Toast(string.format("Copied %s onto %s (%s).", source.name, target.name, target.id), "Success")
	self:_RenderTabs()
end

function LoadoutScreen:_SavePreset()
	local preset = self:_ActivePreset()
	-- A real game persists here (remote); the screen just reports through the
	-- optional onSave hook and confirms.
	if self._onSave then
		pcall(self._onSave, preset)
	end
	self:_Toast(string.format("%s (%s) saved.", preset.name, preset.id), "Success")
	-- The GP branch builds its own save control; _saveBtn is nil there and
	-- _gpSave is nil everywhere else, so the arcade pulse is untouched.
	local saveBtn = self._saveBtn
	if saveBtn then
		UIChrome.Pulse(self:GetTheme(), saveBtn.Root)
	elseif self._gpSave then
		UIChrome.Pulse(self:GetTheme(), self._gpSave.root)
	end
end

-- ========================================================================
-- Lifecycle
-- ========================================================================

function LoadoutScreen:_OnShow(data: any?)
	local hadData = type(data) == "table"
	self:_Ingest(data)
	if self._built and hadData then
		self:_RenderTabs()
		self:_RenderGrid()
		self:_RenderCopyRow()
		self:_RenderPicker()
	end
	if self._modal then
		UIChrome.PopIn(self:GetTheme(), self._modal.content)
	elseif self._gpPage then
		-- Same POP_IN contract, on the pack's own plate (theme.Motion tokens).
		UIChrome.PopIn(self:GetTheme(), self._gpPage.panel)
	end
end

function LoadoutScreen:Update(data: any)
	self:_Ingest(data)
	if self._built then
		self:_RenderTabs()
		self:_RenderGrid()
		self:_RenderCopyRow()
		self:_RenderPicker()
	end
end

function LoadoutScreen:Destroy()
	for _, component in self._pickerButtons do
		component:Destroy()
	end
	table.clear(self._pickerButtons)
	for _, component in self._copyButtons do
		component:Destroy()
	end
	table.clear(self._copyButtons)
	if self._saveBtn then
		self._saveBtn:Destroy()
		self._saveBtn = nil
	end
	UIScreenBase.Destroy(self)
end

-- ======================================================================
-- GP layout (theme.LayoutKit == "GP") — saved builds as a pastel SHELF,
-- composed from GPLayoutKit: a cream Page under a rose ribbon, three preset
-- plates across the top, the six equipment slots as petal cells whose
-- corners ALTERNATE mirror across the grid (pack law 4), and the candidate
-- ledger on the right. Rarity is a chip and a WELL TINT off the pack's own
-- glaze ramp (DialectTokens.rarity: cream → sage → sky → lavender →
-- rose-gold), and every plate casts a shadow deepened from its OWN fill
-- (pack law 2).
--
-- Presentation only: the same presets, the same owned list, the same rarity
-- sort, the same equip / save / copy handlers, the same rename box with the
-- same NAME_MAX cap and the same uppercase input transform — so a preset
-- renamed here and a preset renamed on the arcade page produce byte-identical
-- data.
--
-- DENSITY (pack law 6): every field the arcade build shows is here — per tab
-- the letter, the name (live TextBox on the active one), and either the
-- rename hint or the n/6 equipped count; per slot the slot label, the item
-- art, the item name, the rarity word and the rarity colour, or the full
-- EMPTY state with its ghost glyph and tap hint; per candidate the art, the
-- name, the rarity and the equip / equipped control; plus save and both copy
-- targets. Each tab GAINS its equipped count on the ACTIVE plate too, where
-- the arcade build replaces it with the rename hint.
-- ======================================================================

local GP_PAGE = Vector2.new(1240, 720)
local GP_TAB_W, GP_TAB_H = 236, 76
local GP_TAB_GAP = 12
local GP_GRID_Y = 92
local GP_CELL_W, GP_CELL_H = 228, 206
local GP_CELL_GAP = 12
local GP_PICKER_X = 724
local GP_PICKER_ROW_H = 84
local GP_FOOT_Y = 524
local GP_FOOT_H = 56
local GP_WELL = 100

-- The pack's glaze ramp IS its rarity language, so the loadout's tiers ride
-- the same ladder the shop's chips do: cream → sage → sky → lavender →
-- rose-gold, indexed by the screen's own RARITY_RANK.
local function gpRarityColor(theme: Types.UITheme, rarity: string?): Color3
	local tokens = (theme :: any).DialectTokens
	local ramp = tokens and tokens.rarity
	local rank = RARITY_RANK[rarity or ""] or 1
	local color = if type(ramp) == "table" then ramp[math.clamp(rank, 1, #ramp)] else nil
	return if typeof(color) == "Color3" then color else theme.Colors.Surface
end

-- GP never shouts (pack law 5). Slot labels, rarity tiers, preset names and
-- item names all arrive in arcade caps ("PRIMARY", "STRIKER", "EMBER BLADE"),
-- so the SAME strings are retitled for DISPLAY only — one capital per word,
-- ids and slot maps untouched. This is the rule the other GP screens use
-- (ShopScreen, CodexScreen, MapScreen, CharacterCreatorScreen).
local function gpTitle(text: string): string
	if string.find(text, "<", 1, true) then
		return text
	end
	-- Only SHOUTED copy is retitled. A string already carrying a lowercase
	-- letter was cased deliberately by its author ("Epic", "2x Cash"), and
	-- flattening it would do real damage. The law is "never shout", not
	-- "always title-case" — which also makes this idempotent, so the rename
	-- box can re-normalise its own text without ever fighting itself.
	if string.find(text, "%l") then
		return text
	end
	local retitled = string.gsub(string.lower(text), "[%a][%w']*", function(word: string): string
		return string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2)
	end)
	return retitled
end

-- The icon archive's GLYPH FALLBACK is born pure-white with a black text
-- stroke — both banned outright by pack law 1. Every archive placement in
-- this branch goes through here so a pending upload cannot punch a hole in
-- the palette.
local function gpArt(theme: Types.UITheme, parent: Instance, key: string, sizePx: number, query: any?): GuiObject
	local art = IconArchive.Image(parent, key, sizePx, query)
	if art:IsA("TextLabel") then
		art.TextColor3 = theme.Colors.TextPrimary
		art.TextStrokeTransparency = 1
	end
	return art
end

-- A painted petal plate. UIStyler.Frame is born PURE WHITE, so nothing in
-- this branch is ever left unpainted. Shadow is opt-in: three tabs, six
-- cells and a full candidate ledger would otherwise spend a third of the
-- engine's ~100-shadow budget on furniture.
local function gpPlate(theme: Types.UITheme, parent: Instance, fill: Color3, index: number, sink: { any }?): Frame
	local plate = UIStyler.Frame("Plate")
	plate.BackgroundColor3 = fill
	plate.Parent = parent
	GPLayoutKit.Petal(theme, plate, index)
	GPLayoutKit.SoftStroke(theme, plate, fill)
	if sink then
		GPLayoutKit.Shadow(theme, plate, "sm", sink, fill)
	end
	return plate
end

-- A rarity / state chip: pastel plate, INK copy. Colors.TextOnPrimary
-- (near-white) measures 2.14:1 on these tints and is legal only for LARGE
-- display text on a deepened one, so nothing small here ever uses it. The
-- FILL carries the tier and the WORD carries it too — never hue alone.
local function gpChip(theme: Types.UITheme, parent: Instance, fill: Color3, text: string, index: number): Frame
	local root = gpPlate(theme, parent, fill, index)
	root.Name = "Chip"
	root.ZIndex = 4

	local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "ChipText")
	label.Text = text
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 5
	label.Parent = root
	return root
end

type GPButton = { root: TextButton, shape: Frame, label: TextLabel, stroke: UIStroke, shadow: any }

-- GPLayoutKit ships no action button, so this is the local one: a petal plate
-- in a pack colour, a deepened-tint stroke, its own hue-matched shadow and
-- the shared hover/press juice. The BUTTON stays transparent and the fill
-- lives on a child — UIStyleEnforcer backstops any SOLID GuiButton with a
-- BLACK 2px stroke, which would break pack law 1 on sight.
local function gpButton(
	theme: Types.UITheme,
	parent: Instance,
	text: string,
	fill: Color3,
	index: number,
	sink: { any }?,
	onClick: () -> ()
): GPButton
	local root = Instance.new("TextButton")
	root.Name = "GPButton"
	root.BackgroundTransparency = 1
	root.Text = ""
	root.AutoButtonColor = false
	root.ZIndex = 5
	root.Parent = parent

	local shape = UIStyler.Frame("Shape")
	shape.BackgroundColor3 = fill
	shape.Size = UDim2.fromScale(1, 1)
	shape.ZIndex = 5
	shape.Parent = root
	GPLayoutKit.Petal(theme, shape, index)
	local stroke = GPLayoutKit.SoftStroke(theme, shape, fill)
	local shadow = GPLayoutKit.Shadow(theme, shape, "sm", sink, fill)

	local label = GPLayoutKit.Text(theme, theme.TextSizes.Button, theme.Colors.TextPrimary, "Label")
	label.Text = text
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 6
	label.Parent = shape

	root.Activated:Connect(onClick)
	UIChrome.Animate(theme, root, shape)
	return { root = root, shape = shape, label = label, stroke = stroke, shadow = shadow }
end

function LoadoutScreen:_BuildGPLayout()
	local theme = self:GetTheme()

	-- Arcade leftovers must not leak into the pastel page: _OnShow pops
	-- self._modal if present and _SavePreset pulses self._saveBtn.
	self._modal = nil
	self._saveBtn = nil
	self._gpShadows = {} :: { any }
	-- Section sinks: tabs, grid and picker are each destroyed and rebuilt on
	-- every render, so their handles are released at the TOP of their own
	-- render. A destroyed UIShadow still owes the budget until then.
	self._gpTabShadows = {} :: { any }
	self._gpGridShadows = {} :: { any }
	self._gpPickerShadows = {} :: { any }
	self._gpCopyShadows = {} :: { any }

	local page = GPLayoutKit.Page(theme, self.Root, {
		titleText = "Loadout",
		subtitleText = "Three saved builds, six slots each",
		sizePx = GP_PAGE,
		onClose = function()
			self.ScreenController:HideScreen("loadout")
		end,
	})
	for _, handle in page.shadows do
		table.insert(self._gpShadows, handle)
	end
	self._gpPage = page
	local content = page.content

	local tabs = UIStyler.Frame("Tabs")
	tabs.BackgroundColor3 = theme.Colors.Background
	tabs.BackgroundTransparency = 1
	tabs.Size = UDim2.fromOffset((GP_TAB_W + GP_TAB_GAP) * 3, GP_TAB_H)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, GP_TAB_GAP),
	}).Parent = tabs
	tabs.Parent = content
	self._tabs = tabs

	local grid = UIStyler.Frame("Grid")
	grid.BackgroundColor3 = theme.Colors.Background
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.fromOffset(0, GP_GRID_Y)
	grid.Size = UDim2.fromOffset(GP_CELL_W * 3 + GP_CELL_GAP * 2, GP_CELL_H * 2 + GP_CELL_GAP)
	grid.Parent = content
	self._grid = grid

	self._gpSave = gpButton(theme, content, "Save preset", theme.Colors.Secondary, 0, self._gpShadows, function()
		self:_SavePreset()
	end)
	self._gpSave.root.Position = UDim2.fromOffset(0, GP_FOOT_Y)
	self._gpSave.root.Size = UDim2.fromOffset(228, GP_FOOT_H)

	local copyLabel = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "CopyLabel")
	copyLabel.Text = "Copy onto"
	copyLabel.TextXAlignment = Enum.TextXAlignment.Left
	copyLabel.Position = UDim2.fromOffset(248, GP_FOOT_Y)
	copyLabel.Size = UDim2.fromOffset(110, GP_FOOT_H)
	copyLabel.Parent = content

	local copyRow = UIStyler.Frame("CopyRow")
	copyRow.BackgroundColor3 = theme.Colors.Background
	copyRow.BackgroundTransparency = 1
	copyRow.Position = UDim2.fromOffset(362, GP_FOOT_Y)
	copyRow.Size = UDim2.fromOffset(200, GP_FOOT_H)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
	}).Parent = copyRow
	copyRow.Parent = content
	self._copyRow = copyRow

	-- ---- right: the candidate ledger ------------------------------------
	local panelFill = theme.Colors.Surface
	local panel = gpPlate(theme, content, panelFill, 1, self._gpShadows)
	panel.Name = "Picker"
	panel.Position = UDim2.fromOffset(GP_PICKER_X, 0)
	panel.Size = UDim2.new(1, -GP_PICKER_X, 1, 0)
	self._pickerPanel = panel

	local title = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "PickerTitle")
	title.Text = "Pick a slot"
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Position = UDim2.fromOffset(16, 14)
	title.Size = UDim2.new(1, -32, 0, 28)
	title.ZIndex = 3
	title.Parent = panel
	self._pickerTitle = title

	local hint = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "PickerHint")
	hint.Text = "Tap any slot on the left to see everything you own for it."
	hint.TextWrapped = true
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextYAlignment = Enum.TextYAlignment.Top
	hint.Position = UDim2.fromOffset(16, 48)
	hint.Size = UDim2.new(1, -32, 0, 60)
	hint.ZIndex = 3
	hint.Parent = panel
	self._pickerHint = hint

	local list = Instance.new("ScrollingFrame")
	list.Name = "PickerList"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(10, 52)
	list.Size = UDim2.new(1, -20, 1, -66)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = theme.Colors.Primary
	-- MUST clip: unclipped rows spilling past the frame is a known past bug
	-- here. The padding keeps a row's SOFT shadow off the clip edge so a plate
	-- is never sliced flat on the boundary.
	list.ClipsDescendants = true
	local pad = Instance.new("UIPadding")
	pad.Name = "gpPickerPad"
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 16)
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = list
	UIStyler.ListLayout({
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 8),
	}).Parent = list
	list.ZIndex = 3
	list.Parent = panel
	self._pickerList = list

	self:_RenderTabs()
	self:_RenderGrid()
	self:_RenderCopyRow()
	self:_RenderPicker()
end

function LoadoutScreen:_GPRenderTabs()
	-- _gpPage is the definitive "was this tree built under GP" test. A style
	-- change flips LayoutKit() one frame BEFORE the deferred rebuild lands, so
	-- a render can arrive against the previous layout's instances.
	if not self._gpPage or not self._tabs then
		return
	end
	local theme = self:GetTheme()
	GPLayoutKit.ReleaseShadows(self._gpTabShadows)
	for _, child in self._tabs:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	self._nameBox = nil

	for index, preset in self._presets :: { Preset } do
		local active = index == self._active
		-- ACTIVE lifts the plate to the blush surface and lights a butter
		-- letter chip; inactive sits on the raised cream. Shape AND fill carry
		-- it, never a stroke recolour alone.
		local tabFill = if active then theme.Colors.Surface else theme.Colors.SurfaceRaised
		local tab = gpPlate(theme, self._tabs, tabFill, index, self._gpTabShadows)
		tab.Name = "Tab_" .. preset.id
		tab.LayoutOrder = index
		tab.Size = UDim2.fromOffset(GP_TAB_W, GP_TAB_H)

		local chipFill = if active then theme.Colors.Accent else theme.Colors.Background
		local chip = gpPlate(theme, tab, chipFill, index + 1)
		chip.Name = "Letter"
		chip.Position = UDim2.fromOffset(14, 16)
		chip.Size = UDim2.fromOffset(44, 44)
		chip.ZIndex = 3

		-- Ink on butter AND on cream: both measure well past 4.5:1, and the
		-- near-white TextOnPrimary would vanish on either.
		local letter = GPLayoutKit.Text(theme, 24, theme.Colors.TextPrimary, "Letter")
		letter.Text = preset.id
		letter.Size = UDim2.fromScale(1, 1)
		letter.ZIndex = 4
		letter.Parent = chip

		-- Only the ACTIVE tab gets a live TextBox — an inactive tab's click
		-- must switch presets, never capture text focus.
		if active then
			local box = Instance.new("TextBox")
			box.Name = "NameBox"
			box.BackgroundTransparency = 1
			box.BorderSizePixel = 0
			box.ClearTextOnFocus = false
			box.Text = gpTitle(preset.name)
			box.PlaceholderText = "Name me"
			box.PlaceholderColor3 = theme.Colors.TextSecondary
			box.FontFace = theme.Fonts.Title
			box.TextSize = 18
			box.TextColor3 = theme.Colors.TextPrimary
			box.TextXAlignment = Enum.TextXAlignment.Left
			box.TextTruncate = Enum.TextTruncate.AtEnd
			box.Position = UDim2.fromOffset(70, 12)
			box.Size = UDim2.fromOffset(GP_TAB_W - 84, 26)
			box.ZIndex = 4
			-- No UIChrome.TextOutline here: the pack sets TextOutline = false
			-- and the enforcer's outline is BLACK (pack law 1).
			box.Parent = tab
			-- The arcade build's NAME_MAX cap and trim, kept exactly; only the
			-- CASE rule differs, because the arcade transform is a string.upper
			-- and pack law 5 forbids this branch from producing shouted copy.
			-- gpTitle is idempotent, so re-assigning settles in one pass and an
			-- identical string never re-fires the signal.
			box:GetPropertyChangedSignal("Text"):Connect(function()
				local cased = gpTitle(box.Text)
				if #cased > NAME_MAX then
					cased = string.sub(cased, 1, NAME_MAX)
				end
				if box.Text ~= cased then
					box.Text = cased
				end
			end)
			box.FocusLost:Connect(function()
				local name = gpTitle((string.gsub(box.Text, "^%s*(.-)%s*$", "%1")))
				if name == "" then
					name = "Loadout " .. preset.id
				end
				box.Text = name
				-- Compared against the DISPLAYED form of the stored name, not
				-- the stored name itself: a preset seeded as "STRIKER" shows as
				-- "Striker", and focusing then blurring without typing must not
				-- read as a rename (no write, no toast, no pulse).
				if gpTitle(preset.name) ~= name then
					preset.name = name
					self:_Toast(string.format("Renamed to %s.", name), "Success")
					UIChrome.Pulse(theme, tab)
				end
			end)
			self._nameBox = box
		else
			local name = GPLayoutKit.Text(theme, 18, theme.Colors.TextPrimary, "Name")
			name.Text = gpTitle(preset.name)
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.TextTruncate = Enum.TextTruncate.AtEnd
			name.Position = UDim2.fromOffset(70, 12)
			name.Size = UDim2.fromOffset(GP_TAB_W - 84, 26)
			name.ZIndex = 4
			name.Parent = tab
		end

		-- Density: the ACTIVE plate carries BOTH the equipped count and the
		-- rename hint, where the arcade tab trades one away for the other.
		local sub = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Sub")
		sub.Text = if active
			then string.format("%d/%d equipped · tap the name to rename", self:_EquippedCount(preset), #SLOT_DEFS)
			else string.format("%d/%d equipped", self:_EquippedCount(preset), #SLOT_DEFS)
		sub.TextXAlignment = Enum.TextXAlignment.Left
		sub.TextTruncate = Enum.TextTruncate.AtEnd
		sub.Position = UDim2.fromOffset(70, 44)
		sub.Size = UDim2.fromOffset(GP_TAB_W - 84, 18)
		sub.ZIndex = 4
		sub.Parent = tab

		-- Whole-plate hit control (doc §11.6 — no dead zones inside a card).
		-- It sits UNDER the TextBox's ZIndex so the rename box still takes its
		-- own clicks first on the active tab.
		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Text = ""
		hit.BackgroundTransparency = 1
		hit.AutoButtonColor = false
		hit.Size = UDim2.fromScale(1, 1)
		hit.ZIndex = 2
		hit.Parent = tab
		hit.Activated:Connect(function()
			if index == self._active then
				-- Rename affordance: re-tapping the active tab focuses the box.
				if self._nameBox then
					self._nameBox:CaptureFocus()
				end
			else
				self:_SetActive(index)
			end
		end)
		UIChrome.Animate(theme, hit, tab)
	end
end

function LoadoutScreen:_GPRenderGrid()
	if not self._gpPage or not self._grid then
		return
	end
	local theme = self:GetTheme()
	GPLayoutKit.ReleaseShadows(self._gpGridShadows)
	for _, child in self._grid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local preset = self:_ActivePreset()
	for index, def in SLOT_DEFS do
		self:_GPBuildSlotCell(theme, preset, def, index)
	end
end

function LoadoutScreen:_GPBuildSlotCell(
	theme: Types.UITheme,
	preset: Preset,
	def: { id: string, label: string, icon: string },
	index: number
)
	local col = (index - 1) % 3
	local row = (index - 1) // 3
	local picking = self._pickerSlot == def.id
	local item = self:_ItemById(preset.slots[def.id])

	local cellFill = if picking then theme.Colors.Surface else theme.Colors.SurfaceRaised
	local cell = gpPlate(theme, self._grid, cellFill, index, self._gpGridShadows)
	cell.Name = "Slot_" .. def.id
	cell.Position = UDim2.fromOffset(col * (GP_CELL_W + GP_CELL_GAP), row * (GP_CELL_H + GP_CELL_GAP))
	cell.Size = UDim2.fromOffset(GP_CELL_W, GP_CELL_H)

	if picking then
		-- The pack's "chosen" state is an AURA, not a ring: Glow blooms the
		-- fill's own hue instead of deepening it. One at a time by construction
		-- — only one slot is ever the picker's target.
		GPLayoutKit.Glow(theme, cell, theme.Colors.Primary, self._gpGridShadows)
	end

	-- Sentence case for the pack's own label (pack law 5); SLOT_DEFS keeps its
	-- arcade all-caps data untouched.
	local slotName = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "SlotName")
	slotName.Text = gpTitle(def.label)
	slotName.TextXAlignment = Enum.TextXAlignment.Left
	slotName.Position = UDim2.fromOffset(14, 8)
	slotName.Size = UDim2.new(1, -28, 0, 20)
	slotName.ZIndex = 3
	slotName.Parent = cell

	-- The rarity WELL replaces the arcade rarity ring: this pack states a tier
	-- with a tinted surface, not a coloured hairline. The well takes the
	-- MIRROR of the cell's petal so the two silhouettes nest.
	local wellFill = if item then gpRarityColor(theme, item.rarity) else theme.Colors.Background
	local well = gpPlate(theme, cell, wellFill, index + 1)
	well.Name = "RarityWell"
	well.AnchorPoint = Vector2.new(0.5, 0)
	well.Position = UDim2.new(0.5, 0, 0, 32)
	well.Size = UDim2.fromOffset(GP_WELL, GP_WELL)
	well.ZIndex = 3

	if item then
		local icon = gpArt(theme, well, item.icon or def.icon, 72, { golden = item.rarity == "Legendary" })
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.ZIndex = 4

		-- Item names arrive SHOUTED from the owned list; retitled for display
		-- only, the id in preset.slots is what the equip path actually reads.
		local name = GPLayoutKit.Text(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "ItemName")
		name.Text = gpTitle(item.name)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Position = UDim2.fromOffset(10, 140)
		name.Size = UDim2.new(1, -20, 0, 22)
		name.ZIndex = 3
		name.Parent = cell

		local rarityChip = gpChip(theme, cell, gpRarityColor(theme, item.rarity), gpTitle(item.rarity or "Common"), index)
		rarityChip.Position = UDim2.fromOffset(10, 166)
		rarityChip.Size = UDim2.new(1, -20, 0, 26)
		rarityChip.ZIndex = 3
	else
		-- EMPTY state: the ghost glyph and both labels the arcade cell prints,
		-- dimmed in place — the well keeps its chrome and stays fully tappable.
		local ghost = gpArt(theme, well, def.icon, 56)
		ghost.AnchorPoint = Vector2.new(0.5, 0.5)
		ghost.Position = UDim2.fromScale(0.5, 0.5)
		ghost.ZIndex = 4
		if ghost:IsA("ImageLabel") then
			ghost.ImageTransparency = 0.55
		elseif ghost:IsA("TextLabel") then
			ghost.TextTransparency = 0.55
		end

		local empty = GPLayoutKit.Text(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Empty")
		empty.Text = "Empty"
		empty.Position = UDim2.fromOffset(10, 140)
		empty.Size = UDim2.new(1, -20, 0, 22)
		empty.ZIndex = 3
		empty.Parent = cell

		local tap = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Tap")
		tap.Text = "Tap to fill it"
		tap.Position = UDim2.fromOffset(10, 168)
		tap.Size = UDim2.new(1, -20, 0, 20)
		tap.ZIndex = 3
		tap.Parent = cell
	end

	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 6
	hit.Parent = cell
	hit.Activated:Connect(function()
		self:_OpenPicker(def.id)
	end)
	UIChrome.Animate(theme, hit, cell)
end

function LoadoutScreen:_GPRenderPicker()
	if not self._gpPage or not self._pickerList then
		return
	end
	local theme = self:GetTheme()
	GPLayoutKit.ReleaseShadows(self._gpPickerShadows)
	for _, child in self._pickerList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local def = self:_SlotDef(self._pickerSlot)
	if not def then
		self._pickerTitle.Text = "Pick a slot"
		self._pickerHint.Text = "Tap any slot on the left to see everything you own for it."
		self._pickerHint.Visible = true
		return
	end

	local candidates = self:_OwnedForSlot(def.id)
	self._pickerTitle.Text = string.format("Equip  ·  %s", gpTitle(def.label))
	self._pickerHint.Visible = #candidates == 0
	if #candidates == 0 then
		self._pickerHint.Text = string.format("You own nothing for the %s slot yet.", string.lower(def.label))
		return
	end

	local preset = self:_ActivePreset()
	for order, item in candidates do
		self:_GPBuildPickerRow(theme, preset, def, item, order)
	end
end

function LoadoutScreen:_GPBuildPickerRow(
	theme: Types.UITheme,
	preset: Preset,
	def: { id: string, label: string, icon: string },
	item: OwnedItem,
	order: number
)
	local equipped = preset.slots[def.id] == item.id

	local row = gpPlate(theme, self._pickerList, theme.Colors.SurfaceRaised, order, self._gpPickerShadows)
	row.Name = "Row" .. order
	row.LayoutOrder = order
	row.Size = UDim2.new(1, -14, 0, GP_PICKER_ROW_H)

	local icon = gpArt(theme, row, item.icon or def.icon, 44, { golden = item.rarity == "Legendary" })
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 14, 0.5, 0)
	icon.ZIndex = 3

	local name = GPLayoutKit.Text(theme, 18, theme.Colors.TextPrimary, "Name")
	name.Text = gpTitle(item.name)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(72, 12)
	name.Size = UDim2.new(1, -204, 0, 24)
	name.ZIndex = 3
	name.Parent = row

	local rarityChip = gpChip(theme, row, gpRarityColor(theme, item.rarity), gpTitle(item.rarity or "Common"), order + 1)
	rarityChip.Position = UDim2.fromOffset(72, 42)
	rarityChip.Size = UDim2.fromOffset(126, 26)
	rarityChip.ZIndex = 3

	-- EQUIPPED quietens IN PLACE (doc §11.2); the tap still answers.
	local button = gpButton(
		theme,
		row,
		if equipped then "Equipped" else "Equip",
		if equipped then theme.Colors.Disabled else theme.Colors.Secondary,
		order,
		self._gpPickerShadows,
		function()
			if preset.slots[def.id] == item.id then
				self:_Toast(string.format("%s is already equipped.", item.name), "Info")
				return
			end
			self:_Equip(def, item)
		end
	)
	button.root.AnchorPoint = Vector2.new(1, 0.5)
	button.root.Position = UDim2.new(1, -12, 0.5, 0)
	button.root.Size = UDim2.fromOffset(122, 46)
end

function LoadoutScreen:_GPRenderCopyRow()
	if not self._gpPage or not self._copyRow then
		return
	end
	local theme = self:GetTheme()
	-- Release BEFORE the destroy: this row is rebuilt on every preset switch,
	-- and a destroyed UIShadow still owes the budget until its handle goes.
	GPLayoutKit.ReleaseShadows(self._gpCopyShadows)
	for _, child in self._copyRow:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	for index, preset in self._presets :: { Preset } do
		if index ~= self._active then
			local targetIndex = index
			local button = gpButton(theme, self._copyRow, preset.id, theme.Colors.Surface, index, self._gpCopyShadows, function()
				self:_CopyTo(targetIndex)
			end)
			button.root.LayoutOrder = index
			button.root.Size = UDim2.fromOffset(68, GP_FOOT_H)
		end
	end
end

-- A style rebuild destroys the Gui, but UIShadow BUDGET counts live in
-- StyleKit.Capabilities and only fall when a handle is released — so every
-- GP shadow handle is handed back here.
function LoadoutScreen:_OnTeardown()
	GPLayoutKit.ReleaseShadows(self._gpCopyShadows)
	GPLayoutKit.ReleaseShadows(self._gpPickerShadows)
	GPLayoutKit.ReleaseShadows(self._gpGridShadows)
	GPLayoutKit.ReleaseShadows(self._gpTabShadows)
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	self._gpPage = nil
	self._gpSave = nil
	self._nameBox = nil
end

return LoadoutScreen
