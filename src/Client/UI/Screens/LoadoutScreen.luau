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
	UIChrome.Pulse(self:GetTheme(), self._saveBtn.Root)
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

return LoadoutScreen
