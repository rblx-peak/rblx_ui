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

function ScreenCatalogScreen.new()
	local self = UIScreenBase.new("ScreenCatalogScreen", 22)
	self._buttons = {}
	return setmetatable(self, ScreenCatalogScreen)
end

function ScreenCatalogScreen:_BuildContent()
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

function ScreenCatalogScreen:Destroy()
	for _, button in self._buttons do
		button:Destroy()
	end
	table.clear(self._buttons)
	UIScreenBase.Destroy(self)
end

return ScreenCatalogScreen
