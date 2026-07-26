--!strict
-- BUILD INVENTORY — the palette panel of the build pair (BuildPaletteState is
-- the one source of truth; HotbarScreen is the other surface). A bottom-anchored
-- sheet that opens ALIGNED ABOVE the persistent toolbar — deliberately NOT a
-- ModalCard, so it stays a sheet in BOTH layout languages instead of going
-- full-bleed under AC. Anatomy, top to bottom:
--
--   header ("INVENTORY" + 32px close X)
--   category tabs (one per BuildPaletteState.Categories() entry)
--   item grid (76px tiles, 8px gaps, name caption under the icon)
--   mirror hotbar (live 9-slot strip — SlotsChanged/SelectionChanged)
--   one-line swap hint
--
-- SWAP LOGIC is click-click with ONE armed thing at a time (an accent Selection
-- ring marks it): tile→arm item, slot while item armed→SetSlot, slot→arm slot,
-- second slot→SwapSlots, tile while slot armed→SetSlot. State mutates ONLY
-- through BuildPaletteState's API and every slot repaint flows back from its
-- signals — the mirror never edits its own cells directly.
--
-- Both styles are first-class for free: every fill/stroke/corner/font routes
-- through theme tokens + UIChrome policy, and the screen rebuilds on style
-- change, so the same build reads arcade slate under Classic and hairline
-- terminal chrome under AC (which additionally gets corner brackets).
--
-- Fixed px at the 1650×1020 baseline (UIScreenBase attaches the UIScale).

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local BuildPaletteState = require(script.Parent.Parent.Framework.BuildPaletteState)
local ACLayoutKit = require(script.Parent.Parent.Framework.ACLayoutKit)
local UIScreenBase = require(script.Parent.UIScreenBase)

-- Panel geometry: the sheet sits just above the 58px hotbar strip (doc: the
-- toolbar stays visible under this screen — hidesHUD = false in the manifest).
local PANEL_W = 660
local PANEL_H = 460
local PAD = 14
local CONTENT_W = PANEL_W - PAD * 2 -- 632
local HEADER_H = 44
local TAB_W = 150
local TAB_H = 36
local TABS_Y = HEADER_H + 8
local GRID_Y = TABS_Y + TAB_H + 8
local TILE = 76
local TILE_GAP = 8
local TILE_ICON = 36
local SLOT_PX = 60
local SLOT_GAP = 6
local SLOT_ICON = 32
local MIRROR_Y = PANEL_H - 26 - SLOT_PX -- hint line lives in the last 26px
local GRID_H = MIRROR_Y - 8 - GRID_Y

-- One square cell, shared by the grid tiles AND the mirror slots (the slot
-- rendering rule both build surfaces follow). Rings are created ONCE and only
-- ever toggle .Enabled; icons swap only when the item id actually changes.
type SlotCell = {
	root: Frame,
	hit: TextButton,
	well: Frame,
	ring: UIStroke, -- outer Selection ring (armed on tiles, selected on slots)
	armedRing: UIStroke?, -- mirror only: inner ring marking the armed SLOT
	icon: GuiObject?,
	itemId: string?,
}

local BuildInventoryScreen = setmetatable({}, { __index = UIScreenBase })
BuildInventoryScreen.__index = BuildInventoryScreen

function BuildInventoryScreen.new()
	local self = UIScreenBase.new("BuildInventoryScreen", 6)
	self._categoryIndex = 1
	-- Exactly one of these is ever non-nil: the click-click swap arm.
	self._armedItem = nil :: BuildPaletteState.Item?
	self._armedSlot = nil :: number?
	-- UISignal handles ({ Disconnect(self) } shape) — live only while shown.
	self._connections = {} :: { any }
	-- Pooled per-build instance tables; _OnTeardown clears them all.
	self._tabs = {} :: { { ring: UIStroke, label: TextLabel } }
	self._gridCells = {} :: { SlotCell }
	self._mirrorCells = {} :: { SlotCell }
	self._panel = nil :: Frame?
	self._gridScroll = nil :: ScrollingFrame?
	return setmetatable(self, BuildInventoryScreen)
end

-- ========================================================================
-- The shared slot cell (grid tile + mirror slot)
-- ========================================================================

-- Transparent fixed root in the layout, whole-cell hit button UNDER the visual
-- subtree (frames/labels never sink input, so every pixel answers — doc §11.6),
-- policy-chromed well, and the Selection ring on its own outset frame so the
-- hover scale on the well never moves it.
local function buildSlotCell(theme: Types.UITheme, parent: Instance, sizePx: number, order: number): SlotCell
	local root = UIStyler.Frame("Slot")
	root.BackgroundTransparency = 1
	root.LayoutOrder = order
	root.Size = UDim2.fromOffset(sizePx, sizePx)
	root.Parent = parent

	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 1
	hit.Parent = root

	local well = UIStyler.Frame("Well")
	well.BackgroundColor3 = theme.Arcade.NearBlack
	well.BackgroundTransparency = 0.35
	well.AnchorPoint = Vector2.new(0.5, 0.5)
	well.Position = UDim2.fromScale(0.5, 0.5)
	well.Size = UDim2.fromScale(1, 1)
	well.ZIndex = 2
	UIChrome.Corner("Arcade").Parent = well
	UIChrome.Stroke(theme, "Arcade", "Button").Parent = well
	UIChrome.GlassGradient().Parent = well
	well.Parent = root

	local ringFrame = UIStyler.Frame("SelRing")
	ringFrame.BackgroundTransparency = 1
	ringFrame.Position = UDim2.fromOffset(-3, -3)
	ringFrame.Size = UDim2.new(1, 6, 1, 6)
	ringFrame.ZIndex = 3
	local ring = UIChrome.Stroke(theme, "Arcade", "Selection")
	ring.Enabled = false
	ring.Parent = ringFrame
	ringFrame.Parent = root

	UIChrome.Animate(theme, hit, well)

	return { root = root, hit = hit, well = well, ring = ring }
end

-- The slot rule's paint half: item tile = item.color backdrop at low
-- saturation + icon; empty = neutral dim well; selected = ring + a subtle
-- brighter fill. Icons rebuild only when the occupying item id changes.
local function paintSlotCell(theme: Types.UITheme, cell: SlotCell, entry: BuildPaletteState.Item?, selected: boolean, iconPx: number)
	local itemId = if entry then entry.id else nil
	if cell.itemId ~= itemId then
		cell.itemId = itemId
		if cell.icon then
			cell.icon:Destroy()
			cell.icon = nil
		end
		if entry then
			local icon = IconArchive.Image(cell.well, entry.icon, iconPx)
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.fromScale(0.5, 0.5)
			icon.ZIndex = 4
			cell.icon = icon
		end
	end
	if entry then
		cell.well.BackgroundColor3 = entry.color
		cell.well.BackgroundTransparency = if selected then 0.2 else 0.35
	else
		cell.well.BackgroundColor3 = theme.Arcade.NearBlack
		cell.well.BackgroundTransparency = if selected then 0.15 else 0.35
	end
	cell.ring.Enabled = selected
end

-- ========================================================================
-- Build
-- ========================================================================

-- Slim horizontal separator: classic gets a 2px near-black bar, the AC polish
-- branch gets the terminal's quiet accent hairline instead.
function BuildInventoryScreen:_AddRule(theme: Types.UITheme, panel: Frame, y: number)
	if self:LayoutKit() == "AC" then
		local rule = ACLayoutKit.Rule(theme, panel)
		rule.Position = UDim2.fromOffset(PAD, y)
		rule.Size = UDim2.new(0, CONTENT_W, 0, 1)
	else
		local rule = UIStyler.Frame("Rule")
		rule.BackgroundColor3 = theme.Arcade.NearBlack
		rule.Position = UDim2.fromOffset(PAD, y)
		rule.Size = UDim2.fromOffset(CONTENT_W, 2)
		rule.Parent = panel
	end
end

function BuildInventoryScreen:_BuildContent()
	local theme = self:GetTheme()

	-- The bottom-anchored sheet, aligned above the hotbar strip. Everything on
	-- it comes from UIChrome policy, so the SAME build reads native in both
	-- styles; AC additionally gets its corner brackets (screens rebuild on
	-- style change, so this branch re-evaluates live).
	local panel = UIChrome.Panel(theme, "Arcade", "Palette")
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -92)
	panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
	panel.Parent = self.Root
	self._panel = panel
	if self:LayoutKit() == "AC" then
		ACLayoutKit.Brackets(theme, panel)
	end

	-- Header: title left, small close X right.
	local header = UIStyler.Frame("Header")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, HEADER_H)
	header.Parent = panel

	local title = UIChrome.Text("Title", 22, theme.Colors.TextPrimary)
	title.Text = "INVENTORY"
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Position = UDim2.fromOffset(PAD, 0)
	title.Size = UDim2.new(1, -(PAD + 56), 1, 0)
	title.Parent = header

	-- Hand-rolled 32px close (the 48px house X is too big for this sheet),
	-- built from the same policy pieces makeCloseButton uses.
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Size = UDim2.fromOffset(32, 32)
	close.BackgroundColor3 = theme.Arcade.Red
	close.BorderSizePixel = 0
	close.Text = "X"
	close.FontFace = theme.Fonts.Title
	close.TextSize = 18
	close.TextColor3 = theme.Colors.TextPrimary
	UIChrome.TextOutline(close)
	UIChrome.Stroke(theme, "Arcade", "Button").Parent = close
	UIChrome.ArcadeBevel().Parent = close
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.new(1, -10, 0.5, 0)
	close.Parent = header
	close.Activated:Connect(function()
		self.ScreenController:HideScreen("buildInventory")
	end)
	UIChrome.Animate(theme, close)

	self:_AddRule(theme, panel, HEADER_H)

	self:_BuildTabs(theme, panel)

	-- Item grid: 76px tiles, 8px gaps. Small inner padding keeps the hover
	-- pop from clipping on the scroll edges.
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Grid"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(PAD, GRID_Y)
	scroll.Size = UDim2.fromOffset(CONTENT_W, GRID_H)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = theme.Colors.Accent
	scroll.ClipsDescendants = true
	scroll.Parent = panel
	UIStyler.PaddingXY(4, 4).Parent = scroll
	UIStyler.GridLayout(UDim2.fromOffset(TILE, TILE), UDim2.fromOffset(TILE_GAP, TILE_GAP)).Parent = scroll
	self._gridScroll = scroll

	self:_AddRule(theme, panel, MIRROR_Y - 6)

	-- Mirror hotbar: the LIVE 9-slot loadout, centred at the panel bottom.
	local mirror = UIStyler.Frame("MirrorBar")
	mirror.BackgroundTransparency = 1
	mirror.Position = UDim2.fromOffset(PAD, MIRROR_Y)
	mirror.Size = UDim2.fromOffset(CONTENT_W, SLOT_PX)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, SLOT_GAP),
	}).Parent = mirror
	mirror.Parent = panel

	for i = 1, BuildPaletteState.SLOT_COUNT do
		local cell = buildSlotCell(theme, mirror, SLOT_PX, i)
		cell.root.Name = "MirrorSlot" .. i

		-- Inner armed ring: distinct from the outer live-selection ring, so a
		-- slot can read "selected in the hotbar" and "armed for a swap" at once.
		local armedFrame = UIStyler.Frame("ArmedRing")
		armedFrame.BackgroundTransparency = 1
		armedFrame.Position = UDim2.fromOffset(4, 4)
		armedFrame.Size = UDim2.new(1, -8, 1, -8)
		armedFrame.ZIndex = 3
		local armed = UIChrome.Stroke(theme, "Arcade", "Selection")
		armed.Enabled = false
		armed.Parent = armedFrame
		armedFrame.Parent = cell.root
		cell.armedRing = armed

		-- Number chip (hotbar only): the 1-9 keybind tag, micro badge tier.
		local chip = UIStyler.Frame("Chip")
		chip.BackgroundColor3 = theme.Arcade.NearBlack2
		chip.Position = UDim2.fromOffset(3, 3)
		chip.Size = UDim2.fromOffset(18, 14)
		chip.ZIndex = 5
		UIChrome.Corner("Arcade").Parent = chip
		chip.Parent = cell.well
		local number = UIChrome.Text("N", 10, theme.Arcade.IceBlue)
		number.RichText = false
		number.Text = tostring(i)
		number.Size = UDim2.fromScale(1, 1)
		number.ZIndex = 6
		number.Parent = chip

		local index = i
		cell.hit.Activated:Connect(function()
			self:_OnMirrorClicked(index)
		end)
		self._mirrorCells[i] = cell
	end

	-- The swap hint, dim on the panel's bottom edge.
	local hint = UIChrome.BodyText("Hint", 11, theme.Colors.TextSecondary)
	hint.Text = "CLICK AN ITEM, THEN A SLOT - CLICK TWO SLOTS TO SWAP"
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -6)
	hint.Size = UDim2.new(1, -PAD * 2, 0, 14)
	hint.Parent = panel

	self:_SyncTabs()
	self:_RenderGrid()
	self:_RenderMirror()
end

-- ========================================================================
-- Category tabs
-- ========================================================================

function BuildInventoryScreen:_BuildTabs(theme: Types.UITheme, panel: Frame)
	local bar = UIStyler.Frame("Tabs")
	bar.BackgroundTransparency = 1
	bar.Position = UDim2.fromOffset(PAD, TABS_Y)
	bar.Size = UDim2.fromOffset(CONTENT_W, TAB_H)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
	}).Parent = bar
	bar.Parent = panel

	for index, category in BuildPaletteState.Categories() do
		-- Fixed transparent footprint; the hover scale rides the inner surface
		-- so the tab row never reflows (doc §5.1).
		local root = UIStyler.Frame("Tab_" .. category.name)
		root.BackgroundTransparency = 1
		root.LayoutOrder = index
		root.Size = UDim2.fromOffset(TAB_W, TAB_H)
		root.Parent = bar

		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Text = ""
		hit.BackgroundTransparency = 1
		hit.AutoButtonColor = false
		hit.Size = UDim2.fromScale(1, 1)
		hit.ZIndex = 1
		hit.Parent = root

		local surface = UIStyler.Frame("Surface")
		surface.BackgroundColor3 = theme.Arcade.NearBlack
		surface.AnchorPoint = Vector2.new(0.5, 0.5)
		surface.Position = UDim2.fromScale(0.5, 0.5)
		surface.Size = UDim2.fromScale(1, 1)
		surface.ZIndex = 2
		UIChrome.Corner("Arcade").Parent = surface
		UIChrome.Stroke(theme, "Arcade", "Button").Parent = surface
		UIChrome.GlassGradient().Parent = surface
		surface.Parent = root

		local label = UIChrome.Text("Label", 16, theme.Colors.TextPrimary)
		label.RichText = false
		label.Text = string.upper(category.name)
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Size = UDim2.fromScale(1, 1)
		label.ZIndex = 3
		label.Parent = surface

		-- The active tab wears the Selection stroke: created once, toggled.
		local ringFrame = UIStyler.Frame("ActiveRing")
		ringFrame.BackgroundTransparency = 1
		ringFrame.Position = UDim2.fromOffset(-3, -3)
		ringFrame.Size = UDim2.new(1, 6, 1, 6)
		ringFrame.ZIndex = 3
		local ring = UIChrome.Stroke(theme, "Arcade", "Selection")
		ring.Enabled = false
		ring.Parent = ringFrame
		ringFrame.Parent = root

		local categoryIndex = index
		hit.Activated:Connect(function()
			self:_SelectCategory(categoryIndex)
		end)
		UIChrome.Animate(theme, hit, surface)

		self._tabs[index] = { ring = ring, label = label }
	end
end

function BuildInventoryScreen:_SelectCategory(index: number)
	if index == self._categoryIndex then
		return
	end
	self._categoryIndex = index
	-- An armed ITEM's ring lives in the outgoing grid: switching category would
	-- leave it armed but unmarked, and the next slot click would place an
	-- invisible item. The ring-marks-what-is-armed invariant wins — a tab
	-- switch drops an item arm (a slot arm keeps its ring in the mirror).
	self._armedItem = nil
	self:_SyncTabs()
	self:_RenderGrid()
end

function BuildInventoryScreen:_SyncTabs()
	local theme = self:GetTheme()
	for index, tab in self._tabs do
		local active = index == self._categoryIndex
		tab.ring.Enabled = active
		tab.label.TextColor3 = if active then theme.Semantic.Selection else theme.Colors.TextPrimary
		-- Re-apply the text emphasis so a glow style (AC) follows the recolour;
		-- under the classic outline this is an idempotent no-op.
		UIChrome.TextOutline(tab.label)
	end
end

-- ========================================================================
-- Item grid
-- ========================================================================

function BuildInventoryScreen:_RenderGrid()
	local scroll = self._gridScroll :: ScrollingFrame?
	if not scroll then
		return
	end
	local theme = self:GetTheme()
	for _, cell in self._gridCells do
		cell.root:Destroy()
	end
	table.clear(self._gridCells)

	local category = BuildPaletteState.Categories()[self._categoryIndex]
	if not category then
		return
	end
	for order, entry in category.items do
		local cell = buildSlotCell(theme, scroll, TILE, order)
		cell.root.Name = "Tile_" .. entry.id
		cell.itemId = entry.id

		-- The item tile per the slot rule, with the icon lifted to leave the
		-- caption strip clear at the bottom of the square cell.
		cell.well.BackgroundColor3 = entry.color
		cell.well.BackgroundTransparency = 0.35
		local icon = IconArchive.Image(cell.well, entry.icon, TILE_ICON)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 8)
		icon.ZIndex = 4
		cell.icon = icon

		local caption = UIChrome.BodyText("Caption", 11, theme.Colors.TextPrimary)
		caption.RichText = false
		caption.Text = entry.name
		caption.TextTruncate = Enum.TextTruncate.AtEnd
		caption.Position = UDim2.new(0, 4, 1, -18)
		caption.Size = UDim2.new(1, -8, 0, 14)
		caption.ZIndex = 4
		caption.Parent = cell.well

		local item = entry
		cell.hit.Activated:Connect(function()
			self:_OnTileClicked(item)
		end)
		table.insert(self._gridCells, cell)
	end
	self:_SyncArmed()
end

-- ========================================================================
-- Mirror hotbar
-- ========================================================================

-- Repaint every mirror slot from the model. Fired by SlotsChanged AND
-- SelectionChanged — the itemId diff inside paintSlotCell keeps a pure
-- selection move from churning icons.
function BuildInventoryScreen:_RenderMirror()
	local theme = self:GetTheme()
	local selectedIndex = BuildPaletteState.GetSelectedIndex()
	for i, cell in self._mirrorCells do
		paintSlotCell(theme, cell, BuildPaletteState.GetSlot(i), i == selectedIndex, SLOT_ICON)
	end
end

-- ========================================================================
-- Click-click swap
-- ========================================================================

function BuildInventoryScreen:_OnTileClicked(entry: BuildPaletteState.Item)
	local armedSlot = self._armedSlot
	if armedSlot then
		-- A SLOT is armed: this tile fills it.
		BuildPaletteState.SetSlot(armedSlot, entry)
		self:_Disarm()
		return
	end
	local armedItem = self._armedItem
	if armedItem and armedItem.id == entry.id then
		self:_Disarm()
		return
	end
	self._armedItem = entry
	self._armedSlot = nil
	self:_SyncArmed()
end

function BuildInventoryScreen:_OnMirrorClicked(index: number)
	local armedItem = self._armedItem
	if armedItem then
		-- An ITEM is armed: it lands in this slot.
		BuildPaletteState.SetSlot(index, armedItem)
		self:_Disarm()
		return
	end
	local armedSlot = self._armedSlot
	if armedSlot then
		-- Two armed slots swap; re-clicking the armed slot just disarms.
		if armedSlot ~= index then
			BuildPaletteState.SwapSlots(armedSlot, index)
		end
		self:_Disarm()
		return
	end
	self._armedSlot = index
	self._armedItem = nil
	self:_SyncArmed()
end

function BuildInventoryScreen:_Disarm()
	self._armedItem = nil
	self._armedSlot = nil
	self:_SyncArmed()
end

-- Move the armed marker rings to whatever is currently armed (never repaints
-- slot contents — those only ever flow from SlotsChanged).
function BuildInventoryScreen:_SyncArmed()
	local armedItem = self._armedItem
	local armedSlot = self._armedSlot
	for _, cell in self._gridCells do
		cell.ring.Enabled = armedItem ~= nil and cell.itemId == armedItem.id
	end
	for i, cell in self._mirrorCells do
		local armed = cell.armedRing
		if armed then
			armed.Enabled = armedSlot == i
		end
	end
end

-- ========================================================================
-- Lifecycle
-- ========================================================================

function BuildInventoryScreen:_OnShow(_data: any?)
	-- Idempotence guard: ShowScreen can land on an already-visible screen
	-- without a Hide in between, so drop any live handles before reconnecting.
	self:_DisconnectSignals()
	-- Every open starts with nothing armed, and with the mirror re-read from
	-- the model (the hotbar can change freely while this panel is hidden).
	self._armedItem = nil
	self._armedSlot = nil
	self:_RenderMirror()
	self:_SyncArmed()

	table.insert(self._connections, BuildPaletteState.SlotsChanged:Connect(function()
		self:_RenderMirror()
	end))
	table.insert(self._connections, BuildPaletteState.SelectionChanged:Connect(function()
		self:_RenderMirror()
	end))

	local panel = self._panel :: Frame?
	if panel then
		UIChrome.PopIn(self:GetTheme(), panel)
	end
end

function BuildInventoryScreen:_OnHide()
	self:_DisconnectSignals()
	self._armedItem = nil
	self._armedSlot = nil
end

-- Swap-and-clear FIRST so the hide→teardown pair (a style rebuild runs both)
-- can never walk the same handle list twice.
function BuildInventoryScreen:_DisconnectSignals()
	local connections = self._connections
	self._connections = {}
	for _, connection in connections do
		connection:Disconnect()
	end
end

function BuildInventoryScreen:_OnTeardown()
	self:_DisconnectSignals()
	table.clear(self._gridCells)
	table.clear(self._mirrorCells)
	table.clear(self._tabs)
	self._panel = nil
	self._gridScroll = nil
end

return BuildInventoryScreen
