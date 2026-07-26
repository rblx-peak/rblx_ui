--!strict
-- HotbarScreen — the persistent bottom-centre build toolbar (manifest id
-- "hotbar", HUD band, Minecraft-style): nine square slot cells rendering
-- BuildPaletteState, selection by click or the 1-9 keys, and the palette
-- panel (buildInventory) on B or the strip's INV button.
--
-- State flows ONE way (see BuildPaletteState): this screen only ever READS
-- the shared model and mutates it through Select; it re-renders on the
-- model's SlotsChanged/SelectionChanged signals, which is also how it stays
-- in sync with BuildInventoryScreen without either surface knowing the other.
--
-- Arcade family: dim slate wells, 3px black strokes + bevel — all from
-- UIChrome policy, so a styled chrome (Armored Core: hairline accent frames,
-- mono fonts, glow) restyles the SAME build on the style-change rebuild.
-- Fixed px at the 1650×1020 baseline (UIScreenBase attaches the UIScale).

local UserInputService = game:GetService("UserInputService")

local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local BuildPaletteState = require(script.Parent.Parent.Framework.BuildPaletteState)
local UIScreenBase = require(script.Parent.UIScreenBase)

local CELL = 58 -- square slot cell, px at the authoring baseline
local GAP = 6 -- gap between cells (and before the INV button)
local ICON = 40 -- icon art inside a tile
local TILE_INSET = 8 -- item tile sits 4px inside the cell on every side

-- Main-row digit keys -> slot index (the Minecraft muscle memory).
local KEY_TO_SLOT: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9,
}

type SlotEntry = {
	button: TextButton,
	tile: Frame,
	ring: UIStroke,
	icon: GuiObject?,
}

local HotbarScreen = setmetatable({}, { __index = UIScreenBase })
HotbarScreen.__index = HotbarScreen

function HotbarScreen.new()
	local self = UIScreenBase.new("HotbarScreen", 4)
	-- Pooled slot frames — rebuilt from zero on every style rebuild (see
	-- _OnTeardown), re-rendered in place on every model change.
	self._slots = {} :: { SlotEntry }
	-- Everything _OnShow connects (model signals + UserInputService); both
	-- handle shapes expose :Disconnect(), so one list drops them all.
	self._conns = {} :: { any }
	self._caption = nil :: TextLabel?
	return setmetatable(self, HotbarScreen)
end

function HotbarScreen:_BuildContent()
	local theme = self:GetTheme()

	-- Auto-sized transparent holder pinned bottom-centre; the horizontal
	-- list lays the nine cells + the INV button with 6px gaps.
	local strip = UIStyler.Frame("Strip")
	strip.BackgroundTransparency = 1
	strip.AnchorPoint = Vector2.new(0.5, 1)
	strip.Position = UDim2.new(0.5, 0, 1, -12)
	strip.Size = UDim2.new()
	strip.AutomaticSize = Enum.AutomaticSize.XY
	strip.Parent = self.Root
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, GAP),
	}).Parent = strip

	for index = 1, BuildPaletteState.SLOT_COUNT do
		self._slots[index] = self:_BuildSlot(strip, index)
	end

	-- INV, at the strip's right end: a square arcade button at cell height
	-- that toggles the palette panel — same act as the B key.
	local inv = Instance.new("TextButton")
	inv.Name = "InvButton"
	inv.Size = UDim2.fromOffset(CELL, CELL)
	inv.BackgroundColor3 = theme.Arcade.Blue
	inv.BorderSizePixel = 0
	inv.Text = "INV"
	inv.FontFace = theme.Fonts.Title
	inv.TextSize = 16
	inv.TextColor3 = theme.Colors.TextPrimary
	inv.LayoutOrder = BuildPaletteState.SLOT_COUNT + 1
	UIChrome.TextOutline(inv)
	UIChrome.Corner(self.Family, "Button").Parent = inv
	UIChrome.Stroke(theme, self.Family, "Button").Parent = inv
	UIChrome.ArcadeBevel().Parent = inv
	inv.Parent = strip
	inv.Activated:Connect(function()
		self.ScreenController:ToggleScreen("buildInventory")
	end)
	UIChrome.Animate(theme, inv)

	-- The floating caption naming the held item. It parents to whichever cell
	-- is selected (_RefreshSelection) — a cell's children sit outside the
	-- strip's list flow, so it floats above the cell without reflowing it.
	local caption = UIChrome.Text("Caption", 16, theme.Colors.TextPrimary)
	caption.AnchorPoint = Vector2.new(0.5, 1)
	caption.Position = UDim2.new(0.5, 0, 0, -8)
	caption.Size = UDim2.fromOffset(0, 20)
	caption.AutomaticSize = Enum.AutomaticSize.X
	caption.TextXAlignment = Enum.TextXAlignment.Center
	caption.Visible = false
	caption.ZIndex = 5
	self._caption = caption
end

-- One square cell: neutral dim well (the button itself), the item tile +
-- (re)created icon above it, a small number chip, and the selection ring
-- built ONCE and toggled — never recreated per render.
function HotbarScreen:_BuildSlot(parent: Instance, index: number): SlotEntry
	local theme = self:GetTheme()

	local button = Instance.new("TextButton")
	button.Name = "Slot" .. index
	button.Size = UDim2.fromOffset(CELL, CELL)
	button.BackgroundColor3 = theme.Arcade.NearBlack
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = ""
	button.LayoutOrder = index
	UIChrome.Corner(self.Family, "Tool").Parent = button
	UIChrome.Stroke(theme, self.Family, "Button").Parent = button
	button.Parent = parent

	-- Selection ring above the base stroke (added after it, so it wins).
	local ring = UIChrome.Stroke(theme, self.Family, "Selection")
	ring.Enabled = false
	ring.Parent = button

	-- Item tile: the item.color backdrop at low saturation; hidden = empty.
	local tile = UIStyler.Frame("Tile")
	tile.AnchorPoint = Vector2.new(0.5, 0.5)
	tile.Position = UDim2.fromScale(0.5, 0.5)
	tile.Size = UDim2.new(1, -TILE_INSET, 1, -TILE_INSET)
	tile.BackgroundTransparency = 0.35
	tile.Visible = false
	tile.ZIndex = 2
	UIChrome.Corner(self.Family, "Sub").Parent = tile
	tile.Parent = button

	-- Number chip, top-left: quiet body ink so it never fights the art.
	local chip = UIChrome.BodyText("Chip", 10, theme.Colors.TextSecondary)
	chip.Text = tostring(index)
	chip.Position = UDim2.fromOffset(4, 2)
	chip.Size = UDim2.fromOffset(12, 12)
	chip.TextXAlignment = Enum.TextXAlignment.Left
	chip.ZIndex = 4
	chip.Parent = button

	button.Activated:Connect(function()
		BuildPaletteState.Select(index)
	end)

	return { button = button, tile = tile, ring = ring, icon = nil }
end

-- Re-render every slot from the model. SlotsChanged fires with an index or
-- with nothing (bulk swap); at nine cells re-rendering all of them IS the
-- diff (per the model's own contract). Icons are recreated because
-- IconArchive.Image returns an image OR a glyph fallback; everything else in
-- the cell is pooled and patched in place.
function HotbarScreen:_RenderSlots()
	for index, entry in self._slots do
		local item = BuildPaletteState.GetSlot(index)
		if entry.icon then
			entry.icon:Destroy()
			entry.icon = nil
		end
		if item then
			entry.tile.Visible = true
			entry.tile.BackgroundColor3 = item.color
			local icon = IconArchive.Image(entry.tile, item.icon, ICON)
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.fromScale(0.5, 0.5)
			icon.ZIndex = 3
			entry.icon = icon
		else
			entry.tile.Visible = false
		end
	end
	-- A slot change can fill/empty/replace the SELECTED slot: caption follows.
	self:_RefreshSelection()
end

-- Move the ring + brighter fill and the floating caption onto the selected
-- cell. Rings toggle .Enabled (created once per slot in _BuildSlot).
function HotbarScreen:_RefreshSelection()
	local theme = self:GetTheme()
	local selected = BuildPaletteState.GetSelectedIndex()
	local well = theme.Arcade.NearBlack
	for index, entry in self._slots do
		local on = index == selected
		entry.ring.Enabled = on
		entry.button.BackgroundColor3 = on and UIStyler.Lighten(well, 0.14) or well
	end
	local caption = self._caption
	local entry = self._slots[selected]
	if not caption or not entry then
		return
	end
	caption.Parent = entry.button
	local item = BuildPaletteState.GetSelected()
	if item then
		caption.Text = item.name
		caption.Visible = true
	else
		caption.Visible = false
	end
end

function HotbarScreen:_OnShow(_data: any?)
	-- Live from show to hide only: the shared model's signals + the 1-9/B keys.
	self:_DropConnections()
	table.insert(self._conns, BuildPaletteState.SlotsChanged:Connect(function()
		self:_RenderSlots()
	end))
	table.insert(self._conns, BuildPaletteState.SelectionChanged:Connect(function()
		self:_RefreshSelection()
	end))
	table.insert(self._conns, UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
		if gameProcessedEvent then
			return
		end
		local slot = KEY_TO_SLOT[input.KeyCode]
		if slot then
			BuildPaletteState.Select(slot)
		elseif input.KeyCode == Enum.KeyCode.B then
			self.ScreenController:ToggleScreen("buildInventory")
		end
	end))
	-- Full refresh on every show: a rebuild under a new style — or state that
	-- moved while hidden — restores slots + selection instantly from the model.
	self:_RenderSlots()
end

function HotbarScreen:_OnHide()
	self:_DropConnections()
end

-- Idempotent (guards the double-disconnect): a style rebuild runs _OnHide and
-- then _OnTeardown, and both land here.
function HotbarScreen:_DropConnections()
	for _, conn in self._conns do
		conn:Disconnect()
	end
	table.clear(self._conns)
end

function HotbarScreen:_OnTeardown()
	-- The shell (and every pooled instance under it) is destroyed right after
	-- this hook — drop our references so the next build starts from zero.
	self:_DropConnections()
	table.clear(self._slots)
	self._caption = nil
end

return HotbarScreen
