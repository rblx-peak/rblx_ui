--!strict
-- The screen dock — a persistent HUD strip that can open EVERY screen the
-- manifest declares, so the whole library is clickable in-game.
--
-- Lives on the HUD band and is NOT exclusive: it stays up while panels come and
-- go, which is the point — you click straight from one screen to the next
-- without closing anything first. Doc §7.2 puts a vertical feature bar on the
-- right edge (210px strip at x=-16); this is that strip.
--
-- Three ways through the catalog:
--   * the category list — every screen, grouped, one click each
--   * PREV / NEXT — walk the catalog in order without hunting
--   * BROWSE ALL — the full-screen ScreenCatalog
--
-- It is a dev/demo surface: ship it disabled in the manifest for a live game.

local ScreenManifest = require(script.Parent.Parent.Manifests.ScreenManifest)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local ACLayoutKit = require(script.Parent.Parent.Framework.ACLayoutKit)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIScreenBase = require(script.Parent.UIScreenBase)

local ScreenDockScreen = setmetatable({}, { __index = UIScreenBase })
ScreenDockScreen.__index = ScreenDockScreen

local DOCK_W = 240
local DOCK_H = 720
local ROW_H = 34
local HEADER_H = 96
local FOOTER_H = 104

-- Group order + the icon each heading wears. Matches ScreenCatalogScreen so the
-- two surfaces read as one system.
local GROUPS = {
	{ tag = "core", title = "CORE", icon = "house" },
	{ tag = "economy", title = "ECONOMY", icon = "cart" },
	{ tag = "progression", title = "PROGRESSION", icon = "trophy" },
	{ tag = "social", title = "SOCIAL", icon = "friends" },
	{ tag = "match", title = "MATCH", icon = "swords" },
	{ tag = "reveal", title = "REVEALS", icon = "crate" },
	{ tag = "cosmetics", title = "COSMETICS", icon = "crown" },
	{ tag = "system", title = "SYSTEM", icon = "settings" },
	{ tag = "dev", title = "DEV", icon = "controller" },
}

-- Screens the dock must never try to open from a list row: the dock itself, and
-- the HUD (which is always up and is not a panel).
local SKIP = { screenDock = true, hud = true }

function ScreenDockScreen.new()
	local self = UIScreenBase.new("ScreenDockScreen", 24)
	self._rows = {}
	self._order = {}
	self._index = 0
	self._collapsed = false
	return setmetatable(self, ScreenDockScreen)
end

-- The catalog in a stable, human order (grouped, then alphabetical within a
-- group) — this is what PREV/NEXT walks.
function ScreenDockScreen:_BuildOrder()
	local placed: { [string]: boolean } = {}
	local order = {}
	for _, group in GROUPS do
		for _, id in ScreenManifest.ByTag(group.tag) do
			if not placed[id] and not SKIP[id] then
				placed[id] = true
				table.insert(order, id)
			end
		end
	end
	for _, id in ScreenManifest.Ids() do
		if not placed[id] and not SKIP[id] then
			placed[id] = true
			table.insert(order, id)
		end
	end
	self._order = order
end

function ScreenDockScreen:_OpenById(id: string)
	local controller = self.ScreenController
	if not controller then
		return
	end
	local index = table.find(self._order, id)
	if index then
		self._index = index
	end
	-- Toggle: clicking the screen that is already open closes it, so the dock
	-- doubles as the way back out.
	if controller:IsVisible(id) then
		controller:HideScreen(id)
	else
		controller:ShowScreen(id)
	end
	self:_RefreshStates()
end

-- Walk the catalog. Wraps at both ends, closes whatever the dock opened last,
-- and opens the next one — so you can hold the button and see everything.
function ScreenDockScreen:_Step(delta: number)
	if #self._order == 0 then
		return
	end
	local previous = self._order[self._index]
	if previous and self.ScreenController:IsVisible(previous) then
		self.ScreenController:HideScreen(previous)
	end
	self._index = ((self._index - 1 + delta) % #self._order) + 1
	local id = self._order[self._index]
	self.ScreenController:ShowScreen(id)
	self:_RefreshStates()
end

-- Open rows read gold; everything else sits quiet. Called after every open or
-- close so the dock always reflects the truth.
function ScreenDockScreen:_RefreshStates()
	local theme = self:GetTheme()
	-- The dock is always on screen, so its build-time accent colours must
	-- follow live palette swaps (Theme & Style presets) — repaint the stored
	-- chrome labels from the CURRENT theme on every refresh.
	if self._title then
		self._title.TextColor3 = theme.Arcade.Gold
	end
	if self._counter then
		self._counter.TextColor3 = theme.Arcade.IceBlue
	end
	local controller = self.ScreenController
	local openId: string? = nil
	for id, row in self._rows do
		local open = controller and controller:IsVisible(id) or false
		if open and not openId then
			openId = id
		end
		row.label.TextColor3 = open and theme.Arcade.Gold or theme.Colors.TextPrimary
		row.surface.BackgroundColor3 = open and theme.Arcade.Row or theme.Arcade.NearBlack2
		row.surface.BackgroundTransparency = open and 0 or 0.35
	end
	-- Track whatever is actually open, however it was opened (dock row, HUD
	-- button, hotkey, debug seam) — so PREV/NEXT always continues from what you
	-- are looking at rather than from the dock's own last click.
	if openId then
		local index = table.find(self._order, openId)
		if index then
			self._index = index
		end
	end
	if self._counter then
		self._counter.Text = if openId
			then string.format("%d / %d  %s", self._index, #self._order, string.upper(openId))
			else string.format("%d SCREENS  ·  NONE OPEN", #self._order)
	end
end

function ScreenDockScreen:_BuildContent()
	if self:LayoutKit() == "AC" then
		self:_BuildACLayout()
		return
	end
	local theme = self:GetTheme()
	self:_BuildOrder()

	-- Right-edge strip (doc §7.2): anchored to the true screen edge at x=-16 so
	-- it stays glued there at any viewport, with px sizing inside.
	local dock = UIChrome.Panel(theme, "Arcade", "Dock")
	dock.AnchorPoint = Vector2.new(1, 0.5)
	dock.Position = UDim2.new(1, -16, 0.5, 0)
	dock.Size = UDim2.fromOffset(DOCK_W, DOCK_H)
	dock.ZIndex = 24
	dock.Parent = self.Root
	self._dock = dock

	local title = UIChrome.Text("Title", 22, theme.Arcade.Gold)
	title.Text = "SCREENS"
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(38, 8)
	title.Size = UDim2.new(1, -80, 0, 26)
	title.ZIndex = 25
	title.Parent = dock
	IconArchive.Image(dock, "menu", 22).Position = UDim2.fromOffset(10, 10)

	-- Collapse to just the header, for when the dock is in the way of the very
	-- screen you are inspecting.
	local collapse = UIButtonComponent.new()
	collapse:Create(dock, {
		text = "–",
		variant = "Grey",
		size = UDim2.fromOffset(34, 26),
		position = UDim2.new(1, -8, 0, 8),
		anchorPoint = Vector2.new(1, 0),
		onClick = function()
			self:_SetCollapsed(not self._collapsed)
		end,
	})
	self._collapse = collapse

	local counter = UIChrome.Text("Counter", 14, theme.Arcade.IceBlue)
	counter.Text = string.format("%d SCREENS", #self._order)
	counter.TextXAlignment = Enum.TextXAlignment.Left
	counter.TextTruncate = Enum.TextTruncate.AtEnd
	counter.Position = UDim2.fromOffset(10, 38)
	counter.Size = UDim2.new(1, -20, 0, 18)
	counter.ZIndex = 25
	counter.Parent = dock
	self._counter = counter

	-- PREV / NEXT step through the whole catalog in order.
	local prev = UIButtonComponent.new()
	prev:Create(dock, {
		text = "< PREV",
		variant = "Blue",
		size = UDim2.fromOffset(104, 30),
		position = UDim2.fromOffset(10, 60),
		onClick = function()
			self:_Step(-1)
		end,
	})
	local nextButton = UIButtonComponent.new()
	nextButton:Create(dock, {
		text = "NEXT >",
		variant = "Blue",
		size = UDim2.fromOffset(104, 30),
		position = UDim2.fromOffset(DOCK_W - 114, 60),
		onClick = function()
			self:_Step(1)
		end,
	})
	self._prev, self._next = prev, nextButton

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(8, HEADER_H)
	scroll.Size = UDim2.new(1, -16, 1, -(HEADER_H + FOOTER_H))
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = theme.Arcade.Gold
	scroll.ZIndex = 25
	scroll.Parent = dock
	self._scroll = scroll

	local layout = UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 3),
	})
	layout.Parent = scroll

	local order = 0
	local placed: { [string]: boolean } = {}

	local function addRow(id: string)
		order += 1
		local surface = UIStyler.Frame("Row_" .. id)
		surface.BackgroundColor3 = theme.Arcade.NearBlack2
		surface.BackgroundTransparency = 0.35
		surface.Size = UDim2.new(1, -6, 0, ROW_H)
		surface.LayoutOrder = order
		surface.ZIndex = 26
		UIChrome.Corner("Arcade").Parent = surface
		surface.Parent = scroll

		local label = UIChrome.Text("Label", 15, theme.Colors.TextPrimary)
		label.Text = string.upper(id)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Position = UDim2.fromOffset(10, 0)
		label.Size = UDim2.new(1, -18, 1, 0)
		label.ZIndex = 27
		label.Parent = surface

		-- Whole row is one invisible button (doc §11.6: no dead zones).
		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.Size = UDim2.fromScale(1, 1)
		hit.AutoButtonColor = false
		hit.ZIndex = 28
		hit.Parent = surface
		hit.Activated:Connect(function()
			self:_OpenById(id)
		end)
		UIChrome.Animate(theme, hit, surface)

		self._rows[id] = { surface = surface, label = label }
	end

	local function addHeading(text: string, icon: string)
		order += 1
		-- Icon and text are separate children of a transparent row rather than
		-- an indented string: leading spaces don't reserve a reliable amount of
		-- room in FredokaOne, so the glyph landed on top of the first letter.
		local row = UIStyler.Frame("Heading_" .. text)
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, -6, 0, 24)
		row.LayoutOrder = order
		row.ZIndex = 26
		row.Parent = scroll

		local mark = IconArchive.Image(row, icon, 16)
		mark.AnchorPoint = Vector2.new(0, 0.5)
		mark.Position = UDim2.new(0, 2, 0.5, 0)
		mark.ZIndex = 27

		local heading = UIChrome.Text("Heading", 13, theme.Arcade.Gold)
		heading.Text = text
		heading.TextXAlignment = Enum.TextXAlignment.Left
		heading.Position = UDim2.fromOffset(24, 0)
		heading.Size = UDim2.new(1, -28, 1, 0)
		heading.ZIndex = 27
		heading.Parent = row
	end

	for _, group in GROUPS do
		local ids = {}
		for _, id in ScreenManifest.ByTag(group.tag) do
			if not placed[id] and not SKIP[id] then
				placed[id] = true
				table.insert(ids, id)
			end
		end
		if #ids > 0 then
			addHeading(group.title, group.icon)
			for _, id in ids do
				addRow(id)
			end
		end
	end
	local leftovers = {}
	for _, id in ScreenManifest.Ids() do
		if not placed[id] and not SKIP[id] then
			table.insert(leftovers, id)
		end
	end
	if #leftovers > 0 then
		addHeading("OTHER", "star")
		for _, id in leftovers do
			addRow(id)
		end
	end

	-- Footer: the full-screen browser, and a close-everything escape hatch.
	local browse = UIButtonComponent.new()
	browse:Create(dock, {
		text = "BROWSE ALL",
		variant = "Gold",
		size = UDim2.fromOffset(DOCK_W - 20, 38),
		position = UDim2.new(0, 10, 1, -FOOTER_H + 8),
		onClick = function()
			self.ScreenController:ShowScreen("screenCatalog")
		end,
	})
	local closeAll = UIButtonComponent.new()
	closeAll:Create(dock, {
		text = "CLOSE OPEN PANEL",
		variant = "Red",
		size = UDim2.fromOffset(DOCK_W - 20, 38),
		position = UDim2.new(0, 10, 1, -FOOTER_H + 54),
		onClick = function()
			self.ScreenController:CloseTopmost()
			self:_RefreshStates()
		end,
	})
	self._browse, self._closeAll = browse, closeAll

	self:_RefreshStates()
end

-- ARMORED CORE layout: the dock becomes a compact left terminal rail — quiet
-- token-black backing, one hairline right edge, dense mono rows wearing the
-- accent notch. Same catalog order, same open/toggle callbacks, same PREV/NEXT
-- walk and footer escape hatches as classic; only the anatomy changes.
-- _RefreshStates keeps painting rows/labels/counter from the CURRENT theme, so
-- the open row reads accent (Arcade.Gold rides the accent under AC).
function ScreenDockScreen:_BuildACLayout()
	local theme = self:GetTheme()
	self:_BuildOrder()
	table.clear(self._rows)

	local AC_W = 190
	local AC_H = 560
	local LIST_TOP = 78
	local AC_FOOTER = 56

	-- Left edge, vertically centred — clear of the top HUD strip.
	local dock = UIStyler.Frame("ACDock")
	dock.BackgroundColor3 = theme.Colors.Background
	dock.BackgroundTransparency = 0.35
	dock.AnchorPoint = Vector2.new(0, 0.5)
	dock.Position = UDim2.new(0, 0, 0.5, 0)
	dock.Size = UDim2.fromOffset(AC_W, AC_H)
	dock.ZIndex = 24
	dock.Parent = self.Root
	self._dock = dock
	-- No collapse affordance in this layout; nil the classic handle so
	-- Destroy never touches a stale component from a previous style build.
	self._collapse = nil

	-- The one hairline right edge (the kit's Rule turned vertical).
	local edge = ACLayoutKit.Rule(theme, dock, 0.5)
	edge.AnchorPoint = Vector2.new(1, 0)
	edge.Position = UDim2.new(1, 0, 0, 0)
	edge.Size = UDim2.new(0, 1, 1, 0)

	local header = ACLayoutKit.SectionLabel(theme, dock, "SCREENS")
	header.Position = UDim2.fromOffset(12, 8)
	header.Size = UDim2.new(1, -24, 0, 16)
	header.ZIndex = 25

	-- Same counter contract as classic (_RefreshStates rewrites it live).
	local counter = UIChrome.BodyText("Counter", 10, theme.Arcade.IceBlue)
	counter.Text = string.format("%d SCREENS", #self._order)
	counter.TextXAlignment = Enum.TextXAlignment.Left
	counter.TextTruncate = Enum.TextTruncate.AtEnd
	counter.Position = UDim2.fromOffset(12, 26)
	counter.Size = UDim2.new(1, -24, 0, 14)
	counter.ZIndex = 25
	counter.Parent = dock
	self._counter = counter

	-- Mono pagers: the same catalog walk as classic PREV / NEXT.
	local prev = ACLayoutKit.ActionButton(theme, dock, "< PREV", function()
		self:_Step(-1)
	end)
	prev.TextSize = 11
	prev.Position = UDim2.fromOffset(12, 46)
	prev.Size = UDim2.fromOffset(80, 24)
	prev.ZIndex = 25
	local nextButton = ACLayoutKit.ActionButton(theme, dock, "NEXT >", function()
		self:_Step(1)
	end)
	nextButton.TextSize = 11
	nextButton.Position = UDim2.fromOffset(AC_W - 92, 46)
	nextButton.Size = UDim2.fromOffset(80, 24)
	nextButton.ZIndex = 25
	self._prev, self._next = prev, nextButton

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(6, LIST_TOP)
	scroll.Size = UDim2.new(1, -12, 1, -(LIST_TOP + AC_FOOTER))
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 3
	scroll.ScrollBarImageColor3 = theme.Colors.Accent
	scroll.ZIndex = 25
	scroll.Parent = dock
	self._scroll = scroll

	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 1),
	}).Parent = scroll

	local order = 0
	local placed: { [string]: boolean } = {}

	local function addRow(id: string)
		order += 1
		local surface = UIStyler.Frame("Row_" .. id)
		surface.BackgroundColor3 = theme.Arcade.NearBlack2
		surface.BackgroundTransparency = 0.35
		surface.Size = UDim2.new(1, -4, 0, 22)
		surface.LayoutOrder = order
		surface.ZIndex = 26
		surface.Parent = scroll

		-- The accent notch every terminal row wears; the OPEN read (bright
		-- surface + accent ink) still comes from _RefreshStates.
		local notch = UIStyler.Frame("Notch")
		notch.BackgroundColor3 = theme.Colors.Accent
		notch.BackgroundTransparency = 0.5
		notch.Position = UDim2.new(0, 0, 0, 4)
		notch.Size = UDim2.new(0, 2, 1, -8)
		notch.ZIndex = 27
		notch.Parent = surface

		local label = UIChrome.BodyText("Label", 11, theme.Colors.TextPrimary)
		label.Text = string.upper(id)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Position = UDim2.fromOffset(10, 0)
		label.Size = UDim2.new(1, -16, 1, 0)
		label.ZIndex = 27
		label.Parent = surface

		-- Whole row is one invisible button (doc §11.6: no dead zones).
		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.Size = UDim2.fromScale(1, 1)
		hit.AutoButtonColor = false
		hit.ZIndex = 28
		hit.Parent = surface
		hit.Activated:Connect(function()
			self:_OpenById(id)
		end)
		UIChrome.Animate(theme, hit, surface)

		self._rows[id] = { surface = surface, label = label }
	end

	-- Numbers over icons (the AC creed): headings are dim mono section labels,
	-- no glyphs.
	local function addHeading(text: string)
		order += 1
		local heading = ACLayoutKit.SectionLabel(theme, scroll, text, order)
		heading.Size = UDim2.new(1, -4, 0, 18)
		heading.ZIndex = 26
	end

	for _, group in GROUPS do
		local ids = {}
		for _, id in ScreenManifest.ByTag(group.tag) do
			if not placed[id] and not SKIP[id] then
				placed[id] = true
				table.insert(ids, id)
			end
		end
		if #ids > 0 then
			addHeading(group.title)
			for _, id in ids do
				addRow(id)
			end
		end
	end
	local leftovers = {}
	for _, id in ScreenManifest.Ids() do
		if not placed[id] and not SKIP[id] then
			table.insert(leftovers, id)
		end
	end
	if #leftovers > 0 then
		addHeading("OTHER")
		for _, id in leftovers do
			addRow(id)
		end
	end

	-- Footer: the same two escape hatches as classic, as hairline mono actions.
	local browse = ACLayoutKit.ActionButton(theme, dock, "BROWSE ALL", function()
		self.ScreenController:ShowScreen("screenCatalog")
	end)
	browse.TextSize = 11
	browse.Position = UDim2.new(0, 12, 1, -AC_FOOTER + 4)
	browse.Size = UDim2.new(1, -24, 0, 22)
	browse.ZIndex = 25
	local closeAll = ACLayoutKit.ActionButton(theme, dock, "CLOSE OPEN PANEL", function()
		self.ScreenController:CloseTopmost()
		self:_RefreshStates()
	end)
	closeAll.TextSize = 11
	closeAll.Position = UDim2.new(0, 12, 1, -AC_FOOTER + 30)
	closeAll.Size = UDim2.new(1, -24, 0, 22)
	closeAll.ZIndex = 25
	self._browse, self._closeAll = browse, closeAll

	self:_RefreshStates()
end

function ScreenDockScreen:_SetCollapsed(collapsed: boolean)
	self._collapsed = collapsed
	if self._dock then
		self._dock.Size = UDim2.fromOffset(DOCK_W, collapsed and HEADER_H or DOCK_H)
	end
	if self._scroll then
		self._scroll.Visible = not collapsed
	end
	for _, button in { self._browse, self._closeAll } do
		if button then
			button.Root.Visible = not collapsed
		end
	end
	if self._collapse then
		self._collapse:SetContent({ text = collapsed and "+" or "–" })
	end
end

function ScreenDockScreen:_OnShow(_data: any?)
	-- Re-sync on every show: panels may have opened or closed while the dock
	-- was hidden.
	self:_RefreshStates()
	if self._dock then
		UIChrome.PopIn(self:GetTheme(), self._dock)
	end
end

-- Screens that open/close outside the dock (hotkeys, HUD buttons, a screen
-- closing itself) still need the dock to catch up.
function ScreenDockScreen:Update(_data: any)
	self:_RefreshStates()
end

function ScreenDockScreen:Destroy()
	for _, button in { self._prev, self._next, self._browse, self._closeAll, self._collapse } do
		if button then
			button:Destroy()
		end
	end
	table.clear(self._rows)
	UIScreenBase.Destroy(self)
end

return ScreenDockScreen
