--!strict
-- The screen catalog launcher — the way IN to the library.
--
-- Every window the system can build is declared in Manifests/ScreenManifest,
-- but a manifest entry has no door: nothing opens it until some game code does.
-- This screen IS that door. It lists the whole catalog grouped by tag, and each
-- row opens its screen, so the library is browsable in-game without wiring a
-- button for each one first.
--
-- Bound to ` (backquote) / gamepad Start. Ship it disabled in the manifest for
-- a live game — it is a dev tool, and it deliberately does NOT gate on
-- permissions itself.

local ScreenManifest = require(script.Parent.Parent.Manifests.ScreenManifest)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local GPControlKit = require(script.Parent.Parent.Framework.GPControlKit)
local UIScreenBase = require(script.Parent.UIScreenBase)

local ScreenCatalogScreen = setmetatable({}, { __index = UIScreenBase })
ScreenCatalogScreen.__index = ScreenCatalogScreen

local CARD = Vector2.new(1180, 780)
local ROW_H = 52
local COL_W = 366

-- Tag -> the heading it renders under, in the order a person would look for
-- them. Anything carrying no listed tag lands in "other".
local GROUPS = {
	{ tag = "core", title = "CORE", icon = "house" },
	{ tag = "economy", title = "ECONOMY", icon = "cart" },
	{ tag = "progression", title = "PROGRESSION", icon = "trophy" },
	{ tag = "social", title = "SOCIAL", icon = "friends" },
	{ tag = "match", title = "MATCH FLOW", icon = "swords" },
	{ tag = "system", title = "SYSTEM", icon = "settings" },
	{ tag = "reveal", title = "REVEALS", icon = "crate" },
	{ tag = "cosmetics", title = "COSMETICS", icon = "crown" },
	{ tag = "dev", title = "DEV TOOLS", icon = "controller" },
}

-- GP (Girly Pop) geometry: GPLayoutKit.Page spends 48px more vertical chrome
-- than the §7.4 card, so the GP card is authored 48px taller and its content
-- rect lands pixel-identical — the same two-column grid at the same COL_W.
local GP_CARD_GROW = 48
local GP_SCROLL_PAD = 8

-- "PROGRESSION" -> "Progression". Pack law 5 forbids all-caps copy.
local function gpTitle(text: string): string
	return (string.gsub(string.lower(text), "(%a[%w']*)", function(word: string)
		return string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2)
	end))
end

-- "dailyRewards" -> "Daily Rewards". The arcade row shouts the raw id; the GP
-- row prints the readable name AND keeps the exact id on a second line, so the
-- dev tool gets MORE to work with, not less.
local function gpScreenName(id: string): string
	local spaced = (string.gsub(id, "(%l)(%u)", "%1 %2"))
	return string.upper(string.sub(spaced, 1, 1)) .. string.sub(spaced, 2)
end

function ScreenCatalogScreen.new()
	local self = UIScreenBase.new("ScreenCatalogScreen", 22)
	self._buttons = {}
	-- GP branch state: the shadow sink the budget is released from.
	self._gpShadows = nil :: { any }?
	return setmetatable(self, ScreenCatalogScreen)
end

-- ========================================================================
-- GIRLY POP
-- ========================================================================
-- The whole catalog, still grouped, still counted, still one click per screen —
-- on cream paper with petal-cornered rows. Nothing is thinned out: this is a
-- DEV TOOL, and a dev tool that hides entries to look tidy is a broken one.
-- Each row gains a second line carrying the exact manifest id, so the pretty
-- name never costs you the string you actually need to type.

function ScreenCatalogScreen:_BuildGPLayout()
	local theme = self:GetTheme()
	local spacing = theme.Spacing

	local catalog = ScreenManifest.Ids()
	local page = GPLayoutKit.Page(theme, self.Root, {
		titleText = "Screen catalog",
		subtitleText = string.format("%d screens on the shelf", #catalog),
		sizePx = Vector2.new(CARD.X, CARD.Y + GP_CARD_GROW),
		onClose = function()
			self.ScreenController:HideScreen("screenCatalog")
		end,
	})
	self._modal = page
	-- The PAGE'S OWN sink, not a fresh table: the panel's lg shadow and the close
	-- chip's land in page.shadows, and a screen that starts its own array leaves
	-- those two handles unreleased on every teardown.
	self._gpShadows = page.shadows
	local content = page.content

	local subtitle = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Subtitle")
	subtitle.Text = string.format(
		"%d screens declared — each is built the first time it is opened. Press ` to reopen this list.",
		#catalog
	)
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Position = UDim2.fromOffset(4, 0)
	subtitle.Size = UDim2.new(1, -8, 0, 22)
	subtitle.Parent = content

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Catalog"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, 30)
	scroll.Size = UDim2.new(1, 0, 1, -30)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 10
	scroll.ScrollBarImageColor3 = GPLayoutKit.Deepen(theme, theme.Colors.Primary, 1)
	-- Scrolled rows must never spill onto the paper (a known past bug here).
	scroll.ClipsDescendants = true
	scroll.Parent = content
	UIStyler.Padding(GP_SCROLL_PAD).Parent = scroll

	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, spacing.M),
	}).Parent = scroll

	local placed: { [string]: boolean } = {}
	local order = 0

	local function addGroup(title: string, icon: string, ids: { string })
		if #ids == 0 then
			return
		end
		order += 1
		local section = UIStyler.Frame("Group_" .. title)
		section.BackgroundTransparency = 1
		section.Size = UDim2.new(1, -(14 + GP_SCROLL_PAD * 2), 0, 0)
		section.AutomaticSize = Enum.AutomaticSize.Y
		section.LayoutOrder = order
		section.Parent = scroll

		-- Icon and text as siblings, not an indented string: leading spaces in
		-- the display face don't reserve a predictable gap.
		local header = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "Header")
		header.Text = string.format("%s   (%d)", gpTitle(title), #ids)
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.Position = UDim2.fromOffset(34, 0)
		header.Size = UDim2.new(1, -34, 0, 30)
		header.Parent = section
		local mark = GPControlKit.Icon(theme, section, icon, 24, GPLayoutKit.Deepen(theme, theme.Colors.Primary, 1))
		mark.AnchorPoint = Vector2.new(0, 0.5)
		mark.Position = UDim2.new(0, 2, 0, 15)

		local grid = UIStyler.Frame("Rows")
		grid.BackgroundTransparency = 1
		grid.Position = UDim2.fromOffset(0, 34)
		grid.Size = UDim2.new(1, 0, 0, 0)
		grid.AutomaticSize = Enum.AutomaticSize.Y
		grid.Parent = section

		local gridLayout = UIStyler.GridLayout(
			UDim2.fromOffset(COL_W, ROW_H),
			UDim2.fromOffset(10, 10)
		)
		gridLayout.Parent = grid

		for i, id in ids do
			local entry = ScreenManifest.Get(id)
			local isDev = (entry and entry.tags and table.find(entry.tags, "dev")) ~= nil
			local button = GPControlKit.Button(theme, grid, {
				text = gpScreenName(id),
				-- Same split the arcade row makes (Blue vs Grey): live screens
				-- read rose, dev tooling reads the quiet blush well.
				fill = if isDev then theme.Colors.Surface else theme.Colors.Primary,
				index = i,
				size = UDim2.fromOffset(COL_W, ROW_H),
				layoutOrder = i,
				sink = self._gpShadows,
				onClick = function()
					-- Close the launcher first: most library screens are in the
					-- exclusive set, so leaving this one open would just make
					-- the controller close it a frame later anyway.
					self.ScreenController:HideScreen("screenCatalog")
					self.ScreenController:ShowScreen(id)
				end,
			})
			-- Two lines in the chip: the readable name, then the exact id.
			button.label.TextXAlignment = Enum.TextXAlignment.Left
			button.label.Position = UDim2.fromOffset(spacing.M, 5)
			button.label.Size = UDim2.new(1, -spacing.M * 2, 0, 24)

			local idLabel = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Id")
			idLabel.Text = id
			idLabel.RichText = false
			idLabel.TextXAlignment = Enum.TextXAlignment.Left
			idLabel.TextTruncate = Enum.TextTruncate.AtEnd
			idLabel.Position = UDim2.fromOffset(spacing.M, 27)
			idLabel.Size = UDim2.new(1, -spacing.M * 2, 0, 18)
			idLabel.ZIndex = button.chip.ZIndex + 1
			idLabel.Parent = button.chip

			table.insert(self._buttons, button)
		end
	end

	for _, group in GROUPS do
		local ids = {}
		for _, id in ScreenManifest.ByTag(group.tag) do
			if not placed[id] and id ~= "screenCatalog" then
				placed[id] = true
				table.insert(ids, id)
			end
		end
		addGroup(group.title, group.icon, ids)
	end

	local leftovers = {}
	for _, id in catalog do
		if not placed[id] and id ~= "screenCatalog" then
			table.insert(leftovers, id)
		end
	end
	addGroup("OTHER", "star", leftovers)
end

function ScreenCatalogScreen:_BuildContent()
	-- GP layout language: the catalog on cream paper.
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end

	local theme = self:GetTheme()

	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = "SCREEN CATALOG",
		sizePx = CARD,
		onClose = function()
			self.ScreenController:HideScreen("screenCatalog")
		end,
	})
	self._modal = modal

	local catalog = ScreenManifest.Ids()
	local subtitle = UIChrome.BodyText("Subtitle", 15, theme.Arcade.IceBlue)
	subtitle.Text = string.format(
		"%d screens declared — each is built the first time it is opened. Press ` to reopen this list.",
		#catalog
	)
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Position = UDim2.fromOffset(4, 0)
	subtitle.Size = UDim2.new(1, -8, 0, 22)
	subtitle.Parent = modal.content

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Catalog"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, 30)
	scroll.Size = UDim2.new(1, 0, 1, -30)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 10
	scroll.ScrollBarImageColor3 = theme.Arcade.Gold
	scroll.Parent = modal.content

	local layout = UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 14),
	})
	layout.Parent = scroll

	-- Track which ids have been rendered so a screen tagged twice (or tagged
	-- with nothing) still appears exactly once.
	local placed: { [string]: boolean } = {}
	local order = 0

	local function addGroup(title: string, icon: string, ids: { string })
		if #ids == 0 then
			return
		end
		order += 1
		local section = UIStyler.Frame("Group_" .. title)
		section.BackgroundTransparency = 1
		section.Size = UDim2.new(1, -14, 0, 0)
		section.AutomaticSize = Enum.AutomaticSize.Y
		section.LayoutOrder = order
		section.Parent = scroll

		-- Icon and text as siblings, not an indented string: leading spaces in
		-- FredokaOne don't reserve a predictable gap and the glyph collides
		-- with the first letter.
		local header = UIChrome.Text("Header", 20, theme.Arcade.Gold)
		header.Text = title .. "   (" .. #ids .. ")"
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.Position = UDim2.fromOffset(34, 0)
		header.Size = UDim2.new(1, -34, 0, 30)
		header.Parent = section
		local mark = IconArchive.Image(section, icon, 24)
		mark.AnchorPoint = Vector2.new(0, 0.5)
		mark.Position = UDim2.new(0, 2, 0, 15)

		local grid = UIStyler.Frame("Rows")
		grid.BackgroundTransparency = 1
		grid.Position = UDim2.fromOffset(0, 34)
		grid.Size = UDim2.new(1, 0, 0, 0)
		grid.AutomaticSize = Enum.AutomaticSize.Y
		grid.Parent = section

		local gridLayout = UIStyler.GridLayout(
			UDim2.fromOffset(COL_W, ROW_H),
			UDim2.fromOffset(10, 10)
		)
		gridLayout.Parent = grid

		for i, id in ids do
			local entry = ScreenManifest.Get(id)
			local button = UIButtonComponent.new()
			button:Create(grid, {
				text = string.upper(id),
				variant = (entry and entry.tags and table.find(entry.tags, "dev")) and "Grey" or "Blue",
				size = UDim2.fromOffset(COL_W, ROW_H),
				layoutOrder = i,
				onClick = function()
					-- Close the launcher first: most library screens are in the
					-- exclusive set, so leaving this one open would just make
					-- the controller close it a frame later anyway.
					self.ScreenController:HideScreen("screenCatalog")
					self.ScreenController:ShowScreen(id)
				end,
			})
			table.insert(self._buttons, button)
		end

		-- Two rows of buttons plus the header; AutomaticSize handles the rest.
		section.Size = UDim2.new(1, -14, 0, 0)
	end

	for _, group in GROUPS do
		local ids = {}
		for _, id in ScreenManifest.ByTag(group.tag) do
			if not placed[id] and id ~= "screenCatalog" then
				placed[id] = true
				table.insert(ids, id)
			end
		end
		addGroup(group.title, group.icon, ids)
	end

	local leftovers = {}
	for _, id in catalog do
		if not placed[id] and id ~= "screenCatalog" then
			table.insert(leftovers, id)
		end
	end
	addGroup("OTHER", "star", leftovers)
end

function ScreenCatalogScreen:_OnShow(_data: any?)
	if self._modal then
		UIChrome.PopIn(self:GetTheme(), self._modal.content)
	end
end

-- A style rebuild destroys the Gui but NOT the shadow budget count.
function ScreenCatalogScreen:_OnTeardown()
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	self._gpShadows = nil
	self._modal = nil
	table.clear(self._buttons)
end

function ScreenCatalogScreen:Destroy()
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	self._gpShadows = nil
	for _, button in self._buttons do
		button:Destroy()
	end
	table.clear(self._buttons)
	UIScreenBase.Destroy(self)
end

return ScreenCatalogScreen
