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
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local GPControlKit = require(script.Parent.Parent.Framework.GPControlKit)
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

-- "dailyRewards" -> "Daily Rewards". The arcade dock shouts the raw id; the GP
-- row prints the readable name AND keeps the exact id beside it, so the dev
-- tool gains information rather than losing it to a softer look.
local function gpScreenName(id: string): string
	local spaced = (string.gsub(id, "(%l)(%u)", "%1 %2"))
	return string.upper(string.sub(spaced, 1, 1)) .. string.sub(spaced, 2)
end

-- "PROGRESSION" -> "Progression". Pack law 5 forbids all-caps copy.
local function gpTitle(text: string): string
	return (string.gsub(string.lower(text), "(%a[%w']*)", function(word: string)
		return string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2)
	end))
end

function ScreenDockScreen.new()
	local self = UIScreenBase.new("ScreenDockScreen", 24)
	self._rows = {}
	self._order = {}
	self._index = 0
	self._collapsed = false
	-- GP branch state: the flag _RefreshStates reads, plus the shadow sink.
	self._gp = false
	self._gpShadows = nil :: { any }?
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
	local gp = self._gp
	-- The dock is always on screen, so its build-time accent colours must
	-- follow live palette swaps (Theme & Style presets) — repaint the stored
	-- chrome labels from the CURRENT theme on every refresh.
	if self._title then
		-- Butter gold measures ~1.6:1 on this pack's cream; ink carries the
		-- title instead and the colour lives in the plate's own hue-matched
		-- shade. (Arcade.IceBlue already resolves to the pack's soft ink.)
		self._title.TextColor3 = if gp then theme.Colors.TextPrimary else theme.Arcade.Gold
	end
	if self._counter then
		self._counter.TextColor3 = if gp then theme.Colors.TextSecondary else theme.Arcade.IceBlue
	end
	local controller = self.ScreenController
	local openId: string? = nil
	for id, row in self._rows do
		local open = controller and controller:IsVisible(id) or false
		if open and not openId then
			openId = id
		end
		if gp then
			-- OPEN reads FORWARD: a rose fill, a solid butter notch and a
			-- retinted shadow-matched rim. Never a butter LABEL — that would be
			-- 1.5:1 on the row and the open row is the one you must be able to
			-- read at a glance.
			local fill = if open then theme.Colors.Primary else theme.Colors.Surface
			row.surface.BackgroundColor3 = fill
			row.surface.BackgroundTransparency = 0
			row.label.TextColor3 = if open then theme.Colors.TextPrimary else theme.Colors.TextSecondary
			if row.stroke then
				row.stroke.Color = GPLayoutKit.Deepen(theme, fill, 1)
			end
			if row.notch then
				row.notch.BackgroundColor3 = theme.Colors.Accent
				row.notch.BackgroundTransparency = if open then 0 else 0.55
			end
			if row.idLabel then
				row.idLabel.TextColor3 = theme.Colors.TextSecondary
			end
		else
			row.label.TextColor3 = open and theme.Arcade.Gold or theme.Colors.TextPrimary
			row.surface.BackgroundColor3 = open and theme.Arcade.Row or theme.Arcade.NearBlack2
			row.surface.BackgroundTransparency = open and 0 or 0.35
		end
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
		if gp then
			self._counter.Text = if openId
				then string.format("%d / %d  ·  %s", self._index, #self._order, gpScreenName(openId))
				else string.format("%d screens  ·  none open", #self._order)
		else
			self._counter.Text = if openId
				then string.format("%d / %d  %s", self._index, #self._order, string.upper(openId))
				else string.format("%d SCREENS  ·  NONE OPEN", #self._order)
		end
	end
end

-- ========================================================================
-- GIRLY POP
-- ========================================================================
-- The dock stays a DOCK: same right-edge strip, same width, same row height,
-- same grouped catalog order, same PREV / NEXT walk, same collapse chip and the
-- same two footer escape hatches. Dense and functional is the brief — this is
-- the tool you drive the whole library from, and softening it into a shorter
-- list would break it. What changes is only the anatomy: cream plate, petal
-- rows, a butter notch on the open one, hue-matched shade.
--
-- Rows are deliberately SHADOW-FREE. Sixty of them would eat most of the
-- engine's ~100-shadow budget on their own and turn a control surface into a
-- sticker sheet; depth here comes from the petal silhouette and the rim.
--
-- _RefreshStates keeps painting rows, labels and the counter from the CURRENT
-- theme, so a live palette swap still lands.
function ScreenDockScreen:_BuildGPLayout()
	local theme = self:GetTheme()
	self:_BuildOrder()
	table.clear(self._rows)
	self._gpShadows = {}

	local dockFill = theme.Colors.Background
	local dock = UIStyler.Frame("GPDock")
	dock.BackgroundColor3 = dockFill
	dock.AnchorPoint = Vector2.new(1, 0.5)
	dock.Position = UDim2.new(1, -16, 0.5, 0)
	dock.Size = UDim2.fromOffset(DOCK_W, DOCK_H)
	dock.ZIndex = 24
	dock.Parent = self.Root
	GPLayoutKit.CornerSet(theme, dock, "Petal")
	GPLayoutKit.SoftStroke(theme, dock, theme.Colors.Primary)
	GPLayoutKit.Shadow(theme, dock, "lg", self._gpShadows, dockFill)
	self._dock = dock

	local studio = ((theme :: any).DialectTokens and (theme :: any).DialectTokens.studio) or {}
	local grain = GPLayoutKit.Tile(
		theme,
		studio.patternKey or "speckle",
		GPLayoutKit.Deepen(theme, dockFill, 1),
		studio.speckleTransparency or 0.94,
		"ClayGrain"
	)
	grain.ZIndex = 24
	grain.Parent = dock

	local title = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "Title")
	title.Text = "Screens"
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(38, 8)
	title.Size = UDim2.new(1, -80, 0, 26)
	title.ZIndex = 25
	title.Parent = dock
	-- Stored so _RefreshStates can repaint it on a live palette swap; the
	-- arcade build leaves this nil and the guard there covers both.
	self._title = title

	local mark = GPControlKit.Icon(theme, dock, "menu", 22, GPLayoutKit.Deepen(theme, theme.Colors.Primary, 1))
	mark.Position = UDim2.fromOffset(10, 10)
	mark.ZIndex = 25

	-- Collapse to just the header, for when the dock is in the way of the very
	-- screen you are inspecting.
	self._collapse = GPControlKit.Button(theme, dock, {
		text = "–",
		fill = theme.Colors.Surface,
		index = 1,
		size = UDim2.fromOffset(34, 26),
		position = UDim2.new(1, -8, 0, 8),
		anchorPoint = Vector2.new(1, 0),
		zIndex = 25,
		sink = self._gpShadows,
		onClick = function()
			self:_SetCollapsed(not self._collapsed)
		end,
	})

	local counter = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Counter")
	counter.Text = string.format("%d screens", #self._order)
	counter.TextXAlignment = Enum.TextXAlignment.Left
	counter.TextTruncate = Enum.TextTruncate.AtEnd
	counter.Position = UDim2.fromOffset(10, 38)
	counter.Size = UDim2.new(1, -20, 0, 18)
	counter.ZIndex = 25
	counter.Parent = dock
	self._counter = counter

	self._prev = GPControlKit.Button(theme, dock, {
		text = "‹ Prev",
		fill = theme.Arcade.Blue,
		index = 0,
		textSize = theme.TextSizes.Small,
		size = UDim2.fromOffset(104, 30),
		position = UDim2.fromOffset(10, 60),
		zIndex = 25,
		sink = self._gpShadows,
		onClick = function()
			self:_Step(-1)
		end,
	})
	self._next = GPControlKit.Button(theme, dock, {
		text = "Next ›",
		fill = theme.Arcade.Blue,
		index = 1,
		textSize = theme.TextSizes.Small,
		size = UDim2.fromOffset(104, 30),
		position = UDim2.fromOffset(DOCK_W - 114, 60),
		zIndex = 25,
		sink = self._gpShadows,
		onClick = function()
			self:_Step(1)
		end,
	})

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(8, HEADER_H)
	scroll.Size = UDim2.new(1, -16, 1, -(HEADER_H + FOOTER_H))
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = GPLayoutKit.Deepen(theme, theme.Colors.Primary, 1)
	-- Scrolled rows must never spill past the plate (a known past bug here).
	scroll.ClipsDescendants = true
	scroll.ZIndex = 25
	scroll.Parent = dock
	self._scroll = scroll

	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 3),
	}).Parent = scroll

	local order = 0
	local placed: { [string]: boolean } = {}

	local function addRow(id: string)
		order += 1
		local fill = theme.Colors.Surface
		local surface = UIStyler.Frame("Row_" .. id)
		surface.BackgroundColor3 = fill
		surface.Size = UDim2.new(1, -6, 0, ROW_H)
		surface.LayoutOrder = order
		surface.ZIndex = 26
		surface.Parent = scroll
		GPLayoutKit.Petal(theme, surface, order)
		local stroke = GPLayoutKit.SoftStroke(theme, surface, fill)

		-- The butter notch: a second, non-colour-only signal of "this one is
		-- open" (it goes from 0.55 to solid), so state never rides on hue alone.
		local notch = UIStyler.Frame("Notch")
		notch.BackgroundColor3 = theme.Colors.Accent
		notch.BackgroundTransparency = 0.55
		notch.Position = UDim2.new(0, 4, 0, 6)
		notch.Size = UDim2.new(0, 4, 1, -12)
		notch.ZIndex = 27
		notch.Parent = surface
		UIStyler.Corner(theme.Radii.Pill).Parent = notch

		local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Label")
		label.Text = gpScreenName(id)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Position = UDim2.fromOffset(14, 0)
		label.Size = UDim2.new(1, -110, 1, 0)
		label.ZIndex = 27
		label.Parent = surface

		-- The exact manifest id, kept: the pretty name must never cost you the
		-- string you actually have to type.
		local idLabel = GPLayoutKit.BodyText(theme, 11, theme.Colors.TextSecondary, "Id")
		idLabel.Text = id
		idLabel.RichText = false
		idLabel.TextXAlignment = Enum.TextXAlignment.Right
		idLabel.TextTruncate = Enum.TextTruncate.AtEnd
		idLabel.AnchorPoint = Vector2.new(1, 0.5)
		idLabel.Position = UDim2.new(1, -8, 0.5, 0)
		idLabel.Size = UDim2.fromOffset(94, ROW_H)
		idLabel.ZIndex = 27
		idLabel.Parent = surface

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

		self._rows[id] = { surface = surface, label = label, stroke = stroke, notch = notch, idLabel = idLabel }
	end

	local function addHeading(text: string, icon: string)
		order += 1
		local row = UIStyler.Frame("Heading_" .. text)
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, -6, 0, 26)
		row.LayoutOrder = order
		row.ZIndex = 26
		row.Parent = scroll

		local glyph = GPControlKit.Icon(theme, row, icon, 16, GPLayoutKit.Deepen(theme, theme.Colors.Primary, 1))
		glyph.AnchorPoint = Vector2.new(0, 0.5)
		glyph.Position = UDim2.new(0, 2, 0.5, 0)
		glyph.ZIndex = 27

		local heading = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "Heading")
		heading.Text = gpTitle(text)
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

	-- Footer: the same two escape hatches as classic.
	self._browse = GPControlKit.Button(theme, dock, {
		text = "Browse all",
		fill = theme.Arcade.Gold,
		index = 0,
		size = UDim2.fromOffset(DOCK_W - 20, 38),
		position = UDim2.new(0, 10, 1, -FOOTER_H + 8),
		zIndex = 25,
		sink = self._gpShadows,
		onClick = function()
			self.ScreenController:ShowScreen("screenCatalog")
		end,
	})
	self._closeAll = GPControlKit.Button(theme, dock, {
		text = "Close the open panel",
		fill = theme.Arcade.Red,
		index = 1,
		size = UDim2.fromOffset(DOCK_W - 20, 38),
		position = UDim2.new(0, 10, 1, -FOOTER_H + 54),
		zIndex = 25,
		sink = self._gpShadows,
		onClick = function()
			self.ScreenController:CloseTopmost()
			self:_RefreshStates()
		end,
	})

	self:_RefreshStates()
end

function ScreenDockScreen:_BuildContent()
	if self:LayoutKit() == "AC" then
		self._gp = false
		self:_BuildACLayout()
		return
	end
	if self:LayoutKit() == "GP" then
		self._gp = true
		self:_BuildGPLayout()
		return
	end
	self._gp = false
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

-- A style rebuild destroys the Gui but NOT the shadow budget count. The dock is
-- persistent HUD furniture, so it survives more style swaps than any other
-- screen here and its handles matter more.
function ScreenDockScreen:_OnTeardown()
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	self._gpShadows = nil
	table.clear(self._rows)
	self._dock = nil
	self._scroll = nil
	self._title = nil
	self._counter = nil
	self._prev = nil
	self._next = nil
	self._browse = nil
	self._closeAll = nil
	self._collapse = nil
end

function ScreenDockScreen:Destroy()
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	self._gpShadows = nil
	for _, button in { self._prev, self._next, self._browse, self._closeAll, self._collapse } do
		if button then
			button:Destroy()
		end
	end
	table.clear(self._rows)
	UIScreenBase.Destroy(self)
end

return ScreenDockScreen
