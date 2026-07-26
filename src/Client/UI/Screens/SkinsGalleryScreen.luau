--!strict
-- SKINS GALLERY — the cosmetics browser, ported from Brick Game's
-- SkinsGallery.client.luau (+ ChairConfig's rarity ladder and the LobbyHud
-- skins panel) onto the Pottery Clash chrome.
--
-- The source is a WORLD gallery of pedestals; this is its menu form: one §7.4
-- modal card holding a category tab row, a scrolling grid of skin tiles on the
-- left, and a detail pane on the right. The source's grammar survives intact —
-- rarity tints the tile ring AND the rarity label (doc §3.3), OWNED recolours
-- in place instead of disappearing (§11.2), and the whole tile is one hit
-- target so there are no dead zones inside a card (§11.6).
--
-- Layout is fixed px at the 1650×1020 baseline; the grid's cell width is
-- derived from the scroll's live width (divided back through the baseline
-- UIScale) so three columns always fit exactly.

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIAssets = require(script.Parent.Parent.Config.UIAssets)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UIScreenBase = require(script.Parent.UIScreenBase)

export type Skin = {
	id: string,
	name: string,
	icon: string?,
	rarity: string?,
	owned: boolean?,
	equipped: boolean?,
	price: number?,
	currency: string?,
}

-- Card 1100×700 → content 1072×612 after the §7.4 insets.
local CARD = Vector2.new(1100, 700)
local TABS_H = 44
local GRID_W = 690
local DETAIL_W = 366
local BODY_Y = TABS_H + 12
local COLUMNS = 3
local CELL_PAD = 12
local CELL_H = 208
local SCROLLBAR_RESERVE = 10

local RARITY_ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
local RARITY_RANK: { [string]: number } = {}
for i, rarity in RARITY_ORDER do
	RARITY_RANK[rarity] = i
end

-- Rarity ramp (doc §3.3: rarity colours tint stroke + label). The shop accent
-- rotation carries the low/mid tiers; the top two claim gold ("valuable") and
-- magenta, and Legendary+ also gets the golden IconArchive variant.
local function rarityAccent(theme: Types.UITheme, rarity: string?): Color3
	local a = theme.Arcade
	local rank = RARITY_RANK[rarity or ""]
	if not rank then
		return a.ShopAccents[3]
	elseif rank >= 6 then
		return a.Magenta
	elseif rank == 5 then
		return a.Gold
	elseif rank == 4 then
		return a.ShopAccents[1]
	elseif rank == 3 then
		return a.ShopAccents[4]
	elseif rank == 2 then
		return a.Green
	end
	return a.ShopAccents[3]
end

local function isTopTier(rarity: string?): boolean
	return (RARITY_RANK[rarity or ""] or 0) >= 5
end

local DEMO_SKINS: { Skin } = {
	{ id = "woodenStool", name = "Wooden Stool", icon = "box", rarity = "Common", owned = true, equipped = true },
	{ id = "plasticChair", name = "Plastic Chair", icon = "card", rarity = "Common", owned = true },
	{ id = "picnicChair", name = "Picnic Chair", icon = "leaf", rarity = "Common", price = 40, currency = "Cash" },
	{ id = "clayThrone", name = "Clay Throne", icon = "potion", rarity = "Uncommon", owned = true },
	{ id = "kilnStool", name = "Kiln Stool", icon = "fire", rarity = "Uncommon", price = 90, currency = "Cash" },
	{ id = "beanBag", name = "Bean Bag", icon = "heart", rarity = "Uncommon", price = 90, currency = "Cash" },
	{ id = "neonGamer", name = "Neon Gamer Chair", icon = "bolt", rarity = "Rare", price = 200, currency = "Bux" },
	{ id = "marbleBench", name = "Marble Bench", icon = "crystal", rarity = "Rare", price = 200, currency = "Bux" },
	{ id = "cactusChair", name = "Cactus Chair", icon = "leaf", rarity = "Rare", price = 200, currency = "Bux" },
	{ id = "lavaChair", name = "Molten Lava Chair", icon = "volcano", rarity = "Epic", price = 450, currency = "Bux" },
	{ id = "iceThrone", name = "Ice Throne", icon = "water", rarity = "Epic", price = 450, currency = "Bux" },
	{ id = "candyChair", name = "Candy Chair", icon = "gum", rarity = "Epic", price = 450, currency = "Bux" },
	{ id = "goldenKiln", name = "Golden Kiln Throne", icon = "crown", rarity = "Legendary", price = 900, currency = "Bux" },
	{ id = "dragonChair", name = "Dragon Chair", icon = "skull", rarity = "Legendary", price = 900, currency = "Bux" },
	{ id = "cloudThrone", name = "Cloud Throne", icon = "cloud", rarity = "Legendary", price = 900, currency = "Bux" },
	{ id = "galaxyThrone", name = "Galaxy Throne", icon = "planet", rarity = "Mythic", price = 199, currency = "Robux" },
	{ id = "prismThrone", name = "Prism Throne", icon = "rainbow", rarity = "Mythic", price = 199, currency = "Robux" },
}

local TABS = { "ALL", "OWNED", "LOCKED" }

local SkinsGalleryScreen = setmetatable({}, { __index = UIScreenBase })
SkinsGalleryScreen.__index = SkinsGalleryScreen

function SkinsGalleryScreen.new()
	local self = UIScreenBase.new("SkinsGalleryScreen", 5)
	self._skins = DEMO_SKINS :: { Skin }
	self._tab = TABS[1]
	self._selectedId = nil :: string?
	self._tabButtons = {} :: { [string]: any }
	self._tiles = {} :: { Frame }
	self._actionButton = nil :: any
	self._detailSpin = nil :: RBXScriptConnection?
	-- Injected by Show(data): (skin, action) -> (); action is "equip" or "buy".
	self._onAction = nil :: ((Skin, string) -> ())?
	return setmetatable(self, SkinsGalleryScreen)
end

-- ========================================================================
-- Build
-- ========================================================================

function SkinsGalleryScreen:_BuildContent()
	local theme = self:GetTheme()

	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = "SKINS",
		sizePx = CARD,
		onClose = function()
			self.ScreenController:HideScreen("skinsGallery")
		end,
	})
	self._modal = modal
	local content = modal.content

	-- Category tabs: the active one is Blue, the rest Ghost (the shop grammar).
	local tabs = UIStyler.Frame("Tabs")
	tabs.BackgroundTransparency = 1
	tabs.Size = UDim2.new(1, 0, 0, TABS_H)
	tabs.ZIndex = 43
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
	}).Parent = tabs
	tabs.Parent = content
	for i, tab in TABS do
		local button = UIButtonComponent.new()
		button:Create(tabs, {
			text = tab,
			variant = if tab == self._tab then "Blue" else "Ghost",
			size = UDim2.fromOffset(150, 40),
			layoutOrder = i,
			onClick = function()
				self:_SelectTab(tab)
			end,
		})
		button.Root.ZIndex = 44
		self._tabButtons[tab] = button
	end

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Tiles"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, BODY_Y)
	scroll.Size = UDim2.new(0, GRID_W, 1, -BODY_Y)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = theme.Arcade.Gold
	scroll.ZIndex = 43
	scroll.Parent = content
	self._scroll = scroll

	local grid = Instance.new("UIGridLayout")
	grid.CellPadding = UDim2.fromOffset(CELL_PAD, CELL_PAD)
	grid.CellSize = UDim2.fromOffset(210, CELL_H)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.FillDirectionMaxCells = COLUMNS
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
	grid.Parent = scroll
	self._grid = grid

	-- Cell width comes from the scroll's LIVE width so the three columns always
	-- fit; AbsoluteSize is real screen px, so divide the baseline UIScale back
	-- out first (offsets we assign get re-multiplied when rendered).
	local baseline = self.Root:FindFirstChild("BaselineScale")
	local function sizeCells()
		local s = 1
		if baseline and baseline:IsA("UIScale") and baseline.Scale > 0 then
			s = baseline.Scale
		end
		local width = scroll.AbsoluteSize.X / s
		local cell = (width - SCROLLBAR_RESERVE - CELL_PAD * (COLUMNS - 1)) / COLUMNS
		grid.CellSize = UDim2.fromOffset(math.max(1, math.floor(cell)), CELL_H)
	end
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(sizeCells)
	sizeCells()

	self:_BuildDetail(theme, content)
end

function SkinsGalleryScreen:_BuildDetail(theme: Types.UITheme, content: Frame)
	local detail = UIStyler.Frame("Detail")
	detail.BackgroundColor3 = theme.Arcade.NearBlack2
	detail.AnchorPoint = Vector2.new(1, 0)
	detail.Position = UDim2.new(1, 0, 0, BODY_Y)
	detail.Size = UDim2.new(0, DETAIL_W, 1, -BODY_Y)
	detail.ZIndex = 43
	UIChrome.Stroke(theme, "Arcade").Parent = detail
	UIChrome.GlassGradient().Parent = detail
	detail.Parent = content
	self._detail = detail

	local well = UIStyler.Frame("Preview")
	well.BackgroundColor3 = theme.Arcade.NearBlack
	well.AnchorPoint = Vector2.new(0.5, 0)
	well.Position = UDim2.new(0.5, 0, 0, 18)
	well.Size = UDim2.fromOffset(DETAIL_W - 36, 250)
	well.ZIndex = 44
	UIChrome.Stroke(theme, "Arcade").Parent = well
	well.Parent = detail

	local artSlot = UIStyler.Frame("Art")
	artSlot.BackgroundTransparency = 1
	artSlot.AnchorPoint = Vector2.new(0.5, 0.5)
	artSlot.Position = UDim2.fromScale(0.5, 0.5)
	artSlot.Size = UDim2.fromOffset(200, 200)
	artSlot.ZIndex = 45
	artSlot.Parent = well
	self._detailArt = artSlot

	local name = UIChrome.Text("Name", 30, theme.Colors.TextPrimary)
	name.Text = ""
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(16, 282)
	name.Size = UDim2.new(1, -32, 0, 38)
	name.ZIndex = 44
	name.Parent = detail
	self._detailName = name

	local rarity = UIChrome.Text("Rarity", 22, theme.Arcade.Gold)
	rarity.Text = ""
	rarity.Position = UDim2.fromOffset(16, 320)
	rarity.Size = UDim2.new(1, -32, 0, 28)
	rarity.ZIndex = 44
	rarity.Parent = detail
	self._detailRarity = rarity

	local blurb = UIChrome.BodyText("Blurb", 17, theme.Arcade.IceBlue)
	blurb.Text = ""
	blurb.TextXAlignment = Enum.TextXAlignment.Center
	blurb.TextYAlignment = Enum.TextYAlignment.Top
	blurb.Position = UDim2.fromOffset(16, 354)
	blurb.Size = UDim2.new(1, -32, 0, 60)
	blurb.ZIndex = 44
	blurb.TextWrapped = true
	blurb.Parent = detail
	self._detailBlurb = blurb

	local slot = UIStyler.Frame("ActionSlot")
	slot.BackgroundTransparency = 1
	slot.AnchorPoint = Vector2.new(0.5, 1)
	slot.Position = UDim2.new(0.5, 0, 1, -18)
	slot.Size = UDim2.fromOffset(DETAIL_W - 48, 56)
	slot.ZIndex = 44
	slot.Parent = detail
	self._actionSlot = slot
end

-- ========================================================================
-- Tiles
-- ========================================================================

function SkinsGalleryScreen:_VisibleSkins(): { Skin }
	local out = {}
	for _, skin in self._skins do
		local owned = skin.owned == true
		if self._tab == "ALL" or (self._tab == "OWNED") == owned then
			table.insert(out, skin)
		end
	end
	table.sort(out, function(a, b)
		local ra = RARITY_RANK[a.rarity or ""] or 0
		local rb = RARITY_RANK[b.rarity or ""] or 0
		if ra ~= rb then
			return ra < rb
		end
		return a.name < b.name
	end)
	return out
end

function SkinsGalleryScreen:_BuildTile(skin: Skin, order: number)
	local theme = self:GetTheme()
	local accent = rarityAccent(theme, skin.rarity)
	local selected = skin.id == self._selectedId

	-- Root is a fixed transparent footprint; the hover/press UIScale rides the
	-- inner surface, so a tile never reflows its grid cell.
	local root = UIStyler.Frame("Tile_" .. skin.id)
	root.BackgroundTransparency = 1
	root.LayoutOrder = order
	root.ZIndex = 44
	root.Parent = self._scroll
	table.insert(self._tiles, root)

	local surface = UIStyler.Frame("Surface")
	surface.BackgroundColor3 = theme.Arcade.NearBlack
	surface.AnchorPoint = Vector2.new(0.5, 0.5)
	surface.Position = UDim2.fromScale(0.5, 0.5)
	surface.Size = UDim2.fromScale(1, 1)
	surface.ZIndex = 45
	-- Rarity ring: the rarity colour tints the stroke (doc §3.3 colour-as-
	-- identity), which the black-only stroke policy cannot express; selection
	-- claims the gold ring from UIChrome instead.
	if selected then
		UIChrome.Stroke(theme, "Arcade", "Selection").Parent = surface
	else
		UIStyler.Stroke(accent, 3, 0).Parent = surface
	end
	UIChrome.GlassGradient().Parent = surface
	surface.Parent = root

	local artSlot = UIStyler.Frame("Art")
	artSlot.BackgroundTransparency = 1
	artSlot.AnchorPoint = Vector2.new(0.5, 0)
	artSlot.Position = UDim2.new(0.5, 0, 0, 14)
	artSlot.Size = UDim2.fromOffset(96, 96)
	artSlot.ZIndex = 46
	artSlot.Parent = surface
	local icon = IconArchive.Image(artSlot, skin.icon or "box", 88, { golden = isTopTier(skin.rarity) })
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.ZIndex = 47

	local name = UIChrome.Text("Name", 19, theme.Colors.TextPrimary)
	name.Text = skin.name
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.AnchorPoint = Vector2.new(0.5, 0)
	name.Position = UDim2.new(0.5, 0, 0, 118)
	name.Size = UDim2.new(1, -14, 0, 26)
	name.ZIndex = 46
	name.Parent = surface

	local rarity = UIChrome.Text("Rarity", 15, accent)
	rarity.Text = string.upper(skin.rarity or "")
	rarity.AnchorPoint = Vector2.new(0.5, 0)
	rarity.Position = UDim2.new(0.5, 0, 0, 144)
	rarity.Size = UDim2.new(1, -14, 0, 20)
	rarity.ZIndex = 46
	rarity.Parent = surface

	-- State strip: ownership recolours IN PLACE (doc §11.2), never disappears.
	local state = UIStyler.Frame("State")
	state.AnchorPoint = Vector2.new(0.5, 1)
	state.Position = UDim2.new(0.5, 0, 1, -10)
	state.Size = UDim2.new(1, -20, 0, 30)
	state.ZIndex = 46
	if skin.equipped then
		state.BackgroundColor3 = theme.Arcade.Gold
	elseif skin.owned then
		state.BackgroundColor3 = theme.Arcade.GreyOwned
	else
		state.BackgroundColor3 = UIChrome.CurrencyColor(theme, skin.currency or "Cash")
	end
	UIChrome.Stroke(theme, "Arcade").Parent = state
	UIChrome.ArcadeBevel().Parent = state
	state.Parent = surface

	local stateText = UIChrome.Text("StateText", 17, theme.Colors.TextPrimary)
	stateText.Text = if skin.equipped
		then "EQUIPPED"
		elseif skin.owned then "OWNED"
		else tostring(skin.price or 0)
	stateText.Size = UDim2.fromScale(1, 1)
	stateText.ZIndex = 47
	stateText.Parent = state
	if not skin.owned then
		-- Prices always lead with the currency's icon (doc §3.3/§8).
		local mark = IconArchive.Image(state, string.lower(skin.currency or "cash"), 22)
		mark.AnchorPoint = Vector2.new(0, 0.5)
		mark.Position = UDim2.new(0, 8, 0.5, 0)
		mark.ZIndex = 47
	end

	-- One full-size invisible button under the whole tile: no dead zones inside
	-- a card (doc §11.6). Plain frames never sink input, so it still receives
	-- every tap while nothing renders above the art.
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 44
	hit.Parent = root
	hit.Activated:Connect(function()
		self:_Select(skin.id)
	end)
	UIChrome.Animate(theme, hit, surface)
end

-- ========================================================================
-- Render
-- ========================================================================

function SkinsGalleryScreen:_SelectTab(tab: string)
	if tab == self._tab then
		return
	end
	self._tab = tab
	for id, button in self._tabButtons do
		button.Props.variant = if id == tab then "Blue" else "Ghost"
		button:ApplyTheme(self:GetTheme())
	end
	self:_RenderTiles()
end

function SkinsGalleryScreen:_Select(id: string)
	if self._selectedId == id then
		return
	end
	self._selectedId = id
	self:_RenderTiles()
	self:_RenderDetail()
end

function SkinsGalleryScreen:_Find(id: string?): Skin?
	if not id then
		return nil
	end
	for _, skin in self._skins do
		if skin.id == id then
			return skin
		end
	end
	return nil
end

function SkinsGalleryScreen:_RenderTiles()
	for _, tile in self._tiles do
		tile:Destroy()
	end
	table.clear(self._tiles)
	local visible = self:_VisibleSkins()
	for order, skin in visible do
		self:_BuildTile(skin, order)
	end
	-- Keep a selection alive so the detail pane is never blank.
	if not self:_Find(self._selectedId) then
		self._selectedId = visible[1] and visible[1].id or (self._skins[1] and self._skins[1].id)
	end
end

function SkinsGalleryScreen:_RenderDetail()
	local theme = self:GetTheme()
	local skin = self:_Find(self._selectedId)
	if not skin then
		return
	end
	local accent = rarityAccent(theme, skin.rarity)
	local top = isTopTier(skin.rarity)

	if self._detailSpin then
		self._detailSpin:Disconnect()
		self._detailSpin = nil
	end
	self._detailArt:ClearAllChildren()
	-- The house glow motif behind every preview (doc §10): white @ 0.7, 45°/s,
	-- gold for the top tier. UIChrome.Spin gates it on being on screen.
	local _, spin = UIAssets.SunburstBehind(
		self._detailArt,
		if top then theme.Arcade.SunburstGold else Color3.new(1, 1, 1),
		if top then 0.5 else 0.7,
		45
	)
	self._detailSpin = spin
	local icon = IconArchive.Image(self._detailArt, skin.icon or "box", 150, { golden = top })
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.ZIndex = 47

	self._detailName.Text = skin.name
	self._detailRarity.Text = string.upper(skin.rarity or "")
	self._detailRarity.TextColor3 = accent
	self._detailBlurb.Text = if skin.equipped
		then "Currently equipped. Pick another skin to swap."
		elseif skin.owned then "In your collection — equip it to wear it."
		else "Not owned yet. Buy it to add it to your collection."

	if self._actionButton then
		self._actionButton:Destroy()
		self._actionButton = nil
	end
	local button = UIButtonComponent.new()
	local props: { [string]: any } = {
		size = UDim2.fromScale(1, 1),
		onClick = function()
			self:_Act(skin)
		end,
	}
	if skin.equipped then
		-- EQUIPPED goes grey IN PLACE; the control stays live so the tap still
		-- answers with full press juice (doc §11.1/§11.2).
		props.text = "EQUIPPED"
		props.variant = "Grey"
		props.dimmed = true
	elseif skin.owned then
		props.text = "EQUIP"
		props.variant = "Green"
	else
		props.priceCurrency = skin.currency or "Cash"
		props.priceAmount = skin.price or 0
	end
	button:Create(self._actionSlot, props)
	button.Root.ZIndex = 46
	self._actionButton = button
end

function SkinsGalleryScreen:_Act(skin: Skin)
	local hud = self.ScreenController and self.ScreenController:GetScreen("hud")
	if skin.equipped then
		if hud then
			hud:PushToast({ text = skin.name .. " is already equipped.", variant = "Info" })
		end
		return
	end
	local action = if skin.owned then "equip" else "buy"
	if self._onAction then
		self._onAction(skin, action)
	elseif skin.owned then
		-- No handler bound: equip locally so the screen demos end-to-end.
		for _, other in self._skins do
			other.equipped = other.id == skin.id
		end
		if hud then
			hud:PushToast({ text = "Equipped " .. skin.name, variant = "Success" })
		end
	elseif hud then
		hud:PushToast({ text = "Buy " .. skin.name .. " to equip it.", variant = "Error" })
	end
	self:_RenderTiles()
	self:_RenderDetail()
end

-- ========================================================================
-- Lifecycle
-- ========================================================================

function SkinsGalleryScreen:_OnShow(data: any?)
	if type(data) == "table" then
		if type(data.skins) == "table" and #data.skins > 0 then
			self._skins = data.skins
		end
		if type(data.onAction) == "function" then
			self._onAction = data.onAction
		end
	end
	if not self:_Find(self._selectedId) then
		self._selectedId = self._skins[1] and self._skins[1].id
	end
	self:_RenderTiles()
	self:_RenderDetail()
	UIChrome.PopIn(self:GetTheme(), self._modal.content)
end

function SkinsGalleryScreen:_OnHide()
	if self._detailSpin then
		self._detailSpin:Disconnect()
		self._detailSpin = nil
	end
end

function SkinsGalleryScreen:Update(data: any)
	if self._built and self:IsVisible() then
		self:_OnShow(data)
	end
end

function SkinsGalleryScreen:Destroy()
	self:_OnHide()
	for _, button in self._tabButtons do
		button:Destroy()
	end
	table.clear(self._tabButtons)
	if self._actionButton then
		self._actionButton:Destroy()
		self._actionButton = nil
	end
	UIScreenBase.Destroy(self)
end

return SkinsGalleryScreen
