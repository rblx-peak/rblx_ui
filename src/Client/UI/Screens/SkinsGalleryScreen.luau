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
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local GPStoreParts = require(script.Parent.Parent.Framework.GPStoreParts)
local GPChairPreview = require(script.Parent.Parent.Framework.GPChairPreview)
local UITicker = require(script.Parent.Parent.Framework.UITicker)
local Store = require(script.Parent.Parent.Config.PotteryStoreConfig)

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
	-- GP layout language: the CHAIR SKINS inventory as pastel ceramics —
	-- window-filled ViewportFrame previews, a rarity glow ramp and petal
	-- cards alternating mirror. See _BuildGPLayout below.
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end

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
	if self._gpPage then
		self:_GPShow(data)
		return
	end
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
	if self._gpPage then
		self:_GPHide()
		return
	end
	if self._detailSpin then
		self._detailSpin:Disconnect()
		self._detailSpin = nil
	end
end

function SkinsGalleryScreen:Update(data: any)
	if self._gpPage then
		self:_GPIngest(data)
		self:_GPRender()
		return
	end
	if self._built and self:IsVisible() then
		self:_OnShow(data)
	end
end

function SkinsGalleryScreen:Destroy()
	self:_OnHide()
	self:_OnTeardown()
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

-- ========================================================================
-- GP layout (theme.LayoutKit == "GP") — the CHAIR SKINS panel from the
-- shipped lobby.
--
-- WHAT THE SOURCE HAS, and what this branch therefore has:
--   * a shard readout and an "UNLOCKED: %d / %d" tally in the header;
--   * a grid of the chairs you own, each a LIVE ViewportFrame of the real
--     chair, spinning — filled only while the card is inside the scroll
--     window and the panel is open, and dropped wholesale on close (the
--     source's attachWindowFill, which is the difference between 8 resident
--     Models and 50);
--   * EQUIP / EQUIPPED per card, with the equipped card claiming the gold
--     ring off the rarity ring;
--   * "Open a crate to earn your first chair!" as the empty state, verbatim;
--   * the hourly FEATURED rotation with its own countdown, and a re-render
--     when the window rolls;
--   * a re-render on any ownership / equip / shard change.
--
-- WHAT THIS BRANCH ADDS (density only goes up):
--   * LOCKED is a real state, not an absence: every chair in the catalog is
--     shown, unowned ones wearing a lock, their Bux price AND their shard
--     craft price, so the gallery is a map of what exists rather than a list
--     of what you happen to have;
--   * a rarity glow ramp (nothing under Epic blooms) and the crate drop share
--     printed under every tier;
--   * a detail pane with a big spinning preview, the unlock route, and a
--     collection-completion bar per rarity tier;
--   * sparkle on the featured rotation ONLY.
-- ========================================================================

local GP_PAGE = Vector2.new(1240, 760)
local GP_DETAIL_W = 384
local GP_CELL_W = 214
local GP_CELL_H = 236
local GP_CELL_PAD = 14
local GP_TABS_H = 56
local GP_FILL_MARGIN = GP_CELL_H + GP_CELL_PAD -- one row of slack either side

local GP_TABS = {
	{ id = "all", label = "Everything" },
	{ id = "owned", label = "Yours" },
	{ id = "locked", label = "Still locked" },
	{ id = "featured", label = "Featured now" },
}

local function gpNow(): number
	local ok, value = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	if ok and typeof(value) == "number" then
		return value
	end
	return os.time()
end

function SkinsGalleryScreen:_GPIngest(data: any)
	if type(data) ~= "table" then
		return
	end
	if type(data.owned) == "table" then
		table.clear(self._gpOwned)
		for _, id in data.owned do
			self._gpOwned[id] = true
		end
	end
	if type(data.equipped) == "string" then
		self._gpEquipped = data.equipped
	end
	if type(data.shards) == "number" then
		self._gpShards = data.shards
	end
	if type(data.bux) == "number" then
		self._gpBux = data.bux
	end
	if type(data.onAction) == "function" then
		self._onAction = data.onAction
	end
end

function SkinsGalleryScreen:_Toast(text: string, variant: string)
	local hud = self.ScreenController and self.ScreenController:GetScreen("hud")
	if hud then
		hud:PushToast({ text = text, variant = variant })
	end
end

function SkinsGalleryScreen:_BuildGPLayout()
	local theme = self:GetTheme()

	-- Arcade leftovers must not leak into the pastel page.
	self._modal = nil
	self._scroll = nil
	self._detailSpin = nil
	self._tabButtons = {}
	self._tiles = {}

	self._gpShadows = {}
	self._gpViews = {} :: { any }
	self._gpCards = {} :: { [string]: any }
	self._gpPool = {} :: { any }
	self._gpSlots = {} :: { any }
	self._gpConnections = {} :: { RBXScriptConnection }
	self._gpOwned = self._gpOwned or {}
	if not next(self._gpOwned) then
		for _, id in Store.DemoState.ownedChairs do
			self._gpOwned[id] = true
		end
	end
	self._gpEquipped = self._gpEquipped or Store.DemoState.equippedChair
	self._gpShards = self._gpShards or Store.DemoState.shards
	self._gpBux = self._gpBux or Store.DemoState.bux
	self._gpTab = self._gpTab or GP_TABS[1].id
	self._gpSelected = self._gpSelected or self._gpEquipped
	self._gpWindow = Store.Window(gpNow())

	local page = GPLayoutKit.Page(theme, self.Root, {
		titleText = Store.Copy.galleryTitle,
		subtitleText = Store.Copy.gallerySubtitle,
		sizePx = GP_PAGE,
		onClose = function()
			self.ScreenController:HideScreen("skinsGallery")
		end,
	})
	-- The scrim is the panel's OPEN flag: the window-fill pass listens to it,
	-- and every preview gates its spin on it.
	page.panel.Parent = page.dim
	self._gpPage = page
	for _, handle in page.shadows do
		table.insert(self._gpShadows, handle)
	end

	self._gpUnlockCounter = GPStoreParts.Counter(theme, page.topRight, {
		iconKey = "unlock",
		caption = Store.Copy.galleryUnlocked,
		widthPx = 150,
		fill = theme.Colors.Secondary,
		layoutOrder = 1,
		sink = self._gpShadows,
	})
	self._gpShardCounter = GPStoreParts.Counter(theme, page.topRight, {
		iconKey = "crystal",
		caption = Store.Copy.galleryShards,
		widthPx = 132,
		layoutOrder = 2,
		sink = self._gpShadows,
	})
	self._gpFeatureCounter = GPStoreParts.Counter(theme, page.topRight, {
		iconKey = "star",
		caption = Store.Copy.galleryFeatured,
		widthPx = 158,
		fill = theme.Arcade.Gold,
		layoutOrder = 3,
		sink = self._gpShadows,
	})

	local tabs = GPLayoutKit.Tabs(theme, page.content, { widthPx = 168, heightPx = GP_TABS_H }, self._gpShadows)
	self._gpTabs = tabs
	for _, tab in GP_TABS do
		local id = tab.id
		tabs.Add(tab.label, id, function()
			if self._gpTab == id then
				return
			end
			self._gpTab = id
			self:_GPRender()
		end)
	end

	local gridWidth = GP_PAGE.X - theme.Spacing.M * 2 - GP_DETAIL_W - theme.Spacing.M
	self._gpGridWidth = gridWidth
	local board = GPStoreParts.Scroller(theme, page.content, {
		position = UDim2.fromOffset(0, GP_TABS_H + theme.Spacing.S),
		size = UDim2.new(0, gridWidth, 1, -(GP_TABS_H + theme.Spacing.S)),
		name = "SkinGrid",
	})
	self._gpBoard = board

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(GP_CELL_W, GP_CELL_H)
	grid.CellPadding = UDim2.fromOffset(GP_CELL_PAD, GP_CELL_PAD)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
	grid.Parent = board

	-- Only cards inside the window hold a Model, and a shut panel holds none.
	local refresh, connections = GPChairPreview.AttachWindowFill(theme, board, page.dim, self._gpSlots, GP_FILL_MARGIN)
	self._gpRefreshWindow = refresh
	for _, connection in connections do
		table.insert(self._gpConnections, connection)
	end

	self:_GPBuildDetail(theme, page.content, GP_TABS_H + theme.Spacing.S)
	self:_GPRender()
end

-- ---- detail pane -------------------------------------------------------

function SkinsGalleryScreen:_GPBuildDetail(theme: Types.UITheme, content: Frame, top: number)
	local fill = theme.Colors.SurfaceRaised
	local pane = UIStyler.Frame("Detail")
	pane.BackgroundColor3 = fill
	pane.BackgroundTransparency = 0
	pane.AnchorPoint = Vector2.new(1, 0)
	pane.Position = UDim2.new(1, 0, 0, top)
	pane.Size = UDim2.new(0, GP_DETAIL_W, 1, -top)
	pane.ClipsDescendants = true
	pane.ZIndex = 5
	pane.Parent = content
	GPLayoutKit.Petal(theme, pane, 0)
	GPLayoutKit.SoftStroke(theme, pane, fill)
	GPLayoutKit.Shadow(theme, pane, "md", self._gpShadows, fill)
	self._gpDetail = pane

	local spacing = theme.Spacing
	self._gpDetailView = GPChairPreview.New(theme, pane, {
		size = UDim2.new(1, -spacing.L * 2, 0, 250),
		position = UDim2.fromOffset(spacing.L, spacing.L),
		cornerIndex = 1,
		gate = self._gpPage.dim,
		sink = self._gpShadows,
		zIndex = 6,
	})
	table.insert(self._gpViews, self._gpDetailView)

	local y = spacing.L + 250 + spacing.M
	self._gpDetailName = GPStoreParts.Title(theme, pane, 26, "")
	self._gpDetailName.Position = UDim2.fromOffset(spacing.L, y)
	self._gpDetailName.Size = UDim2.new(1, -spacing.L * 2, 0, 32)
	self._gpDetailName.ZIndex = 7

	y += 34
	self._gpDetailRarity = GPStoreParts.Body(theme, pane, theme.TextSizes.Body, "")
	self._gpDetailRarity.Position = UDim2.fromOffset(spacing.L, y)
	self._gpDetailRarity.Size = UDim2.new(1, -spacing.L * 2, 0, 22)
	self._gpDetailRarity.ZIndex = 7

	y += 26
	self._gpDetailBlurb = GPStoreParts.Body(theme, pane, theme.TextSizes.Body, "", theme.Colors.TextPrimary)
	self._gpDetailBlurb.TextWrapped = true
	self._gpDetailBlurb.TextYAlignment = Enum.TextYAlignment.Top
	self._gpDetailBlurb.Position = UDim2.fromOffset(spacing.L, y)
	self._gpDetailBlurb.Size = UDim2.new(1, -spacing.L * 2, 0, 48)
	self._gpDetailBlurb.ZIndex = 7

	y += 54
	-- Tier completion: how much of THIS chair's rarity band you have. The
	-- source shows one global tally; a per-tier bar is the same fact at the
	-- resolution a collector actually plays at.
	self._gpDetailStat = GPLayoutKit.StatRow(theme, pane, {
		label = "Tier collected",
		value = 0,
		maxValue = 100,
		unit = "%",
		precision = 0,
		accent = theme.Colors.Primary,
	})
	self._gpDetailStat.root.Position = UDim2.fromOffset(spacing.L, y)
	self._gpDetailStat.root.Size = UDim2.new(1, -spacing.L * 2, 0, 30)
	self._gpDetailStat.root.ZIndex = 7

	self._gpDetailPrice = GPStoreParts.PricePill(theme, pane, self._gpShadows)
	self._gpDetailPrice.root.Position = UDim2.new(0, spacing.L, 1, -(spacing.L + 96))
	self._gpDetailPrice.root.Size = UDim2.new(1, -spacing.L * 2, 0, 40)
	self._gpDetailPrice.root.ZIndex = 7

	self._gpDetailAction = GPStoreParts.StateChip(theme, pane, {
		position = UDim2.new(0, spacing.L, 1, -(spacing.L + 46)),
		size = UDim2.new(1, -spacing.L * 2, 0, 46),
		cornerIndex = 1,
		zIndex = 7,
		sink = self._gpShadows,
		onClick = function()
			local chair = Store.ChairById[self._gpSelected or ""]
			if chair then
				self:_GPAct(chair)
			end
		end,
	})
end

-- ---- cards -------------------------------------------------------------

function SkinsGalleryScreen:_GPBuildCard(): any
	local theme = self:GetTheme()
	self._gpCardCount = (self._gpCardCount or 0) + 1
	local index = self._gpCardCount
	local entry: any = {}

	local card = GPLayoutKit.Card(theme, self._gpBoard, index, self._gpShadows)
	entry.root = card.root
	entry.body = card.body
	entry.art = card.art
	entry.name = card.name
	entry.shadow = card.shadow
	entry.index = index
	card.artLabel.Visible = false
	card.artImage.Visible = false
	card.art.ClipsDescendants = true
	card.art.Position = UDim2.fromOffset(theme.Spacing.S, theme.Spacing.S)
	card.art.Size = UDim2.new(1, -theme.Spacing.S * 2, 0, 116)

	entry.view = GPChairPreview.New(theme, card.art, {
		size = UDim2.fromScale(1, 1),
		plain = true,
		gate = self._gpPage.dim,
		zIndex = card.art.ZIndex + 1,
	})
	table.insert(self._gpViews, entry.view)

	entry.name.AnchorPoint = Vector2.new(0, 0)
	entry.name.TextSize = 17
	entry.name.Position = UDim2.fromOffset(theme.Spacing.S, 130)
	entry.name.Size = UDim2.new(1, -theme.Spacing.S * 2, 0, 22)

	entry.rarity = GPStoreParts.Body(theme, card.body, theme.TextSizes.Small, "")
	entry.rarity.Position = UDim2.fromOffset(theme.Spacing.S, 152)
	entry.rarity.Size = UDim2.new(1, -theme.Spacing.S * 2, 0, 16)
	entry.rarity.ZIndex = 5

	entry.cost = GPStoreParts.Body(theme, card.body, theme.TextSizes.Small, "")
	entry.cost.Position = UDim2.fromOffset(theme.Spacing.S, 168)
	entry.cost.Size = UDim2.new(1, -theme.Spacing.S * 2, 0, 16)
	entry.cost.ZIndex = 5

	entry.chip = GPStoreParts.StateChip(theme, card.body, {
		position = UDim2.new(0, theme.Spacing.S, 1, -theme.Spacing.S),
		size = UDim2.new(1, -theme.Spacing.S * 2, 0, 34),
		anchorPoint = Vector2.new(0, 1),
		cornerIndex = index + 1,
		zIndex = 6,
		sink = self._gpShadows,
		onClick = function()
			if entry.chair then
				self:_GPSelect(entry.chair.id)
				self:_GPAct(entry.chair)
			end
		end,
	})

	entry.lock = GPChairPreview.Icon(theme, card.body, "lock", 22)
	entry.lock.AnchorPoint = Vector2.new(1, 0)
	entry.lock.Position = UDim2.new(1, -theme.Spacing.S, 0, theme.Spacing.S)
	entry.lock.ZIndex = 8
	entry.lock.Visible = false

	local badge = GPStoreParts.Badge(theme, card.body, "", theme.Arcade.Gold, index, self._gpShadows)
	badge.root.AnchorPoint = Vector2.new(0, 0)
	badge.root.Position = UDim2.fromOffset(-6, -8)
	badge.root.Visible = false
	entry.badge = badge

	card.root.Activated:Connect(function()
		if entry.chair then
			self:_GPSelect(entry.chair.id)
		end
	end)
	return entry
end

function SkinsGalleryScreen:_GPPaintCard(entry: any, item: any)
	local theme = self:GetTheme()
	local chair = item.chair
	local accent = GPStoreParts.RarityColor(theme, chair.rarity)
	entry.chair = chair

	if entry.glow then
		entry.glow:Release()
		for slot = #self._gpShadows, 1, -1 do
			if self._gpShadows[slot] == entry.glow then
				table.remove(self._gpShadows, slot)
			end
		end
		entry.glow = nil
	end
	-- The EQUIPPED card claims a butter aura outright — it outranks its own
	-- rarity, because "this is the one you are sitting on" is the louder fact.
	if item.equipped then
		entry.glow = GPLayoutKit.Glow(theme, entry.body, theme.Arcade.Gold, self._gpShadows)
	else
		entry.glow = GPStoreParts.RarityGlow(theme, entry.body, chair.rarity, self._gpShadows)
	end

	if entry.sparkle then
		entry.sparkle:Destroy()
		entry.sparkle = nil
	end
	if item.featured then
		entry.sparkle = GPStoreParts.Sparkle(theme, entry.body, accent)
	end

	GPChairPreview.SetAccent(entry.view, accent)
	entry.name.Text = chair.name
	entry.name.TextColor3 = if item.owned then theme.Colors.TextPrimary else theme.Colors.TextSecondary
	entry.rarity.Text = GPStoreParts.RarityLine(chair.rarity)
	entry.lock.Visible = not item.owned

	if item.owned then
		entry.cost.Text = if item.equipped then "On your chair right now" else "In your collection"
	elseif chair.buxPrice then
		entry.cost.Text = string.format("%s Bux  ·  %s shards", Store.Comma(chair.buxPrice), Store.Comma(chair.shardPrice))
	else
		entry.cost.Text = "Events only — never sold"
	end

	if item.equipped then
		entry.chip.SetState(Store.Copy.stateEquipped, theme.Arcade.Gold, false)
	elseif item.owned then
		entry.chip.SetState(Store.Copy.stateEquip, theme.Colors.Secondary, true)
	elseif chair.buxPrice then
		entry.chip.SetState(string.format("Buy · %s", Store.Comma(chair.buxPrice)), theme.Colors.Primary, true)
	else
		entry.chip.SetState(Store.Copy.stateLocked, theme.Arcade.GreyOwned, false)
	end

	local showBadge = item.featured or item.equipped
	entry.badge.root.Visible = showBadge
	if item.equipped then
		entry.badge.Set(Store.Copy.stateEquipped, theme.Arcade.Gold)
	elseif item.featured then
		entry.badge.Set(Store.Copy.galleryFeatured, accent)
	end
	entry.badge.shadow:SetEnabled(showBadge)

	entry.shadow:SetEnabled(true)
	entry.chip.shadow:SetEnabled(true)
	entry.root.Visible = true
end

-- ---- render ------------------------------------------------------------

function SkinsGalleryScreen:_GPItems(): { any }
	local window = self._gpWindow
	local featuredSet: { [string]: boolean } = {}
	for _, chair in Store.Gallery(window) do
		featuredSet[chair.id] = true
	end

	local items = {}
	for _, chair in Store.Chairs do
		local owned = self._gpOwned[chair.id] == true
		local featured = featuredSet[chair.id] == true
		local keep = self._gpTab == "all"
			or (self._gpTab == "owned" and owned)
			or (self._gpTab == "locked" and not owned)
			or (self._gpTab == "featured" and featured)
		if keep then
			table.insert(items, {
				chair = chair,
				owned = owned,
				featured = featured,
				equipped = self._gpEquipped == chair.id,
			})
		end
	end
	-- Equipped first, then featured, then down the ladder — the source sorts
	-- its featured chairs to the front for exactly this reason.
	table.sort(items, function(a, b)
		if a.equipped ~= b.equipped then
			return a.equipped
		end
		if a.featured ~= b.featured then
			return a.featured
		end
		local ra, rb = GPStoreParts.Rank(a.chair.rarity), GPStoreParts.Rank(b.chair.rarity)
		if ra ~= rb then
			return ra > rb
		end
		return a.chair.name < b.chair.name
	end)
	return items
end

function SkinsGalleryScreen:_GPOwnedCount(): number
	local count = 0
	for _, chair in Store.Chairs do
		if self._gpOwned[chair.id] then
			count += 1
		end
	end
	return count
end

function SkinsGalleryScreen:_GPRender()
	local board = self._gpBoard
	if not board then
		return
	end
	local theme = self:GetTheme()
	if self._gpTabs then
		self._gpTabs.Select(self._gpTab)
	end

	self._gpUnlockCounter.value.Text = Store.Fraction(self:_GPOwnedCount(), #Store.Chairs)
	self._gpShardCounter.value.Text = Store.Comma(self._gpShards)
	self._gpFeatureCounter.value.Text = Store.Clock(Store.SecondsLeft(gpNow()))

	local items = self:_GPItems()
	local seen: { [string]: boolean } = {}
	table.clear(self._gpSlots)

	for order, item in items do
		local id = item.chair.id
		seen[id] = true
		local entry = self._gpCards[id]
		if not entry then
			entry = table.remove(self._gpPool) or self:_GPBuildCard()
			entry.root.Parent = board
			self._gpCards[id] = entry
		end
		entry.root.LayoutOrder = order
		self:_GPPaintCard(entry, item)
		table.insert(self._gpSlots, {
			view = entry.view,
			chair = item.chair,
			rank = GPStoreParts.Rank(item.chair.rarity),
			element = entry.root,
			filled = false,
		})
	end

	for id, entry in self._gpCards do
		if not seen[id] then
			entry.chair = nil
			entry.root.Visible = false
			entry.shadow:SetEnabled(false)
			entry.chip.shadow:SetEnabled(false)
			entry.badge.shadow:SetEnabled(false)
			GPChairPreview.Clear(entry.view)
			table.insert(self._gpPool, entry)
			self._gpCards[id] = nil
		end
	end

	if self._gpEmpty then
		self._gpEmpty:Destroy()
		self._gpEmpty = nil
	end
	if #items == 0 then
		local text = if self._gpTab == "owned" then Store.Copy.galleryEmpty else Store.Copy.rotatingEmpty
		-- Parented ALONGSIDE the grid, never inside it: a UIGridLayout would
		-- squeeze the empty state into a 214px cell and make the one thing
		-- that has to be readable the least readable thing on the page.
		self._gpEmpty = GPStoreParts.Empty(theme, self._gpPage.content, text, self._gpShadows)
		self._gpEmpty.Position = UDim2.fromOffset(theme.Spacing.M, board.Position.Y.Offset + theme.Spacing.M)
		self._gpEmpty.Size = UDim2.fromOffset((self._gpGridWidth or 700) - theme.Spacing.L, 132)
		self._gpEmpty.ZIndex = 7
	end

	if not Store.ChairById[self._gpSelected or ""] then
		self._gpSelected = items[1] and items[1].chair.id or Store.Chairs[1].id
	end
	self:_GPRenderDetail()

	-- Defer: the grid needs a layout pass before AbsolutePosition is real, and
	-- "is this card in the window" is a question about real geometry.
	task.defer(function()
		if self._gpRefreshWindow then
			self._gpRefreshWindow()
		end
	end)
end

function SkinsGalleryScreen:_GPRenderDetail()
	local theme = self:GetTheme()
	local chair = Store.ChairById[self._gpSelected or ""]
	if not chair or not self._gpDetail then
		return
	end
	local owned = self._gpOwned[chair.id] == true
	local equipped = self._gpEquipped == chair.id
	local accent = GPStoreParts.RarityColor(theme, chair.rarity)

	GPChairPreview.SetAccent(self._gpDetailView, accent)
	GPChairPreview.SetChair(theme, self._gpDetailView, chair, GPStoreParts.Rank(chair.rarity))

	self._gpDetailName.Text = chair.name
	self._gpDetailRarity.Text = GPStoreParts.RarityLine(chair.rarity)
	self._gpDetailRarity.TextColor3 = if GPStoreParts.Rank(chair.rarity) >= 5
		then theme.Colors.TextPrimary
		else theme.Colors.TextSecondary
	self._gpDetailBlurb.Text = if equipped
		then Store.Copy.galleryEquippedHint
		elseif owned then Store.Copy.galleryOwnedHint
		else Store.Copy.galleryLockedHint

	-- Tier completion for the selected chair's own band.
	local have, total = 0, 0
	for _, other in Store.Chairs do
		if other.rarity == chair.rarity then
			total += 1
			if self._gpOwned[other.id] then
				have += 1
			end
		end
	end
	self._gpDetailStat.label.Text = string.format("%s collected  %d/%d", chair.rarity, have, total)
	self._gpDetailStat.SetValue(if total > 0 then have / total * 100 else 0)
	self._gpDetailStat.fill.BackgroundColor3 = accent

	local showPrice = not owned and chair.buxPrice ~= nil
	self._gpDetailPrice.root.Visible = showPrice
	self._gpDetailPrice.shadow:SetEnabled(showPrice)
	if showPrice then
		self._gpDetailPrice.Set("bux", chair.buxPrice or 0)
	end

	if equipped then
		self._gpDetailAction.SetState(Store.Copy.stateEquipped, theme.Arcade.Gold, false)
	elseif owned then
		self._gpDetailAction.SetState(Store.Copy.stateEquip, theme.Colors.Secondary, true)
	elseif chair.buxPrice and self._gpShards >= chair.shardPrice then
		self._gpDetailAction.SetState(string.format("Craft for %s shards", Store.Comma(chair.shardPrice)), theme.Colors.Primary, true)
	elseif chair.buxPrice then
		self._gpDetailAction.SetState(string.format("Buy for %s Bux", Store.Comma(chair.buxPrice)), theme.Colors.Primary, true)
	else
		self._gpDetailAction.SetState("Events only", theme.Arcade.GreyOwned, false)
	end
end

function SkinsGalleryScreen:_GPSelect(id: string)
	if self._gpSelected == id then
		return
	end
	self._gpSelected = id
	self:_GPRenderDetail()
end

-- One action per chair, in the order the source offers them: equip what you
-- own, craft with shards when you can, buy with Bux otherwise.
function SkinsGalleryScreen:_GPAct(chair: any)
	local owned = self._gpOwned[chair.id] == true
	if self._gpEquipped == chair.id then
		self:_Toast(chair.name .. " is already under you.", "Info")
		return
	end
	if owned then
		if self._onAction then
			self._onAction(chair, "equip")
		end
		self._gpEquipped = chair.id
		self:_PlaySound("Success")
		self:_Toast("Sitting pretty on the " .. chair.name .. ".", "Success")
		self:_GPRender()
		return
	end
	if not chair.buxPrice then
		self:_Toast(chair.name .. " only shows up at events.", "Info")
		return
	end
	if self._gpShards >= chair.shardPrice then
		if self._onAction then
			self._onAction(chair, "craft")
		end
		self._gpShards -= chair.shardPrice
		self._gpOwned[chair.id] = true
		self:_PlaySound("Success")
		self:_Toast("Crafted the " .. chair.name .. ".", "Success")
		self:_GPRender()
		return
	end
	if self._gpBux >= chair.buxPrice then
		if self._onAction then
			self._onAction(chair, "buy")
		end
		self._gpBux -= chair.buxPrice
		self._gpOwned[chair.id] = true
		self:_PlaySound("Success")
		self:_Toast(chair.name .. " is yours.", "Success")
		self:_GPRender()
		return
	end
	self:_Toast(string.format("%s shards short of crafting that one.", Store.Comma(chair.shardPrice - self._gpShards)), "Error")
end

function SkinsGalleryScreen:_GPTick()
	if self._gpTickerStop then
		return
	end
	local accumulated = 0
	self._gpTickerStop = UITicker.Register(function(dt: number)
		local counter = self._gpFeatureCounter
		if not counter or not counter.value.Parent then
			return
		end
		accumulated += dt
		if accumulated < 1 then
			return
		end
		accumulated -= 1
		local now = gpNow()
		counter.value.Text = Store.Clock(Store.SecondsLeft(now))
		local window = Store.Window(now)
		if window ~= self._gpWindow then
			self._gpWindow = window
			self:_GPRender()
		end
	end)
end

function SkinsGalleryScreen:_GPShow(data: any?)
	self:_GPIngest(data)
	local page = self._gpPage
	if page then
		page.dim.Visible = true
		UIChrome.PopIn(self:GetTheme(), page.panel)
	end
	self._gpWindow = Store.Window(gpNow())
	self:_GPRender()
	self:_GPTick()
end

function SkinsGalleryScreen:_GPHide()
	if self._gpTickerStop then
		self._gpTickerStop()
		self._gpTickerStop = nil
	end
	-- dim.Visible false drives the window-fill pass to drop EVERY resident
	-- model, which is the whole point of the gate.
	if self._gpPage then
		self._gpPage.dim.Visible = false
	end
	if self._gpDetailView then
		GPChairPreview.Clear(self._gpDetailView)
	end
end

function SkinsGalleryScreen:_OnTeardown()
	if self._gpTickerStop then
		self._gpTickerStop()
		self._gpTickerStop = nil
	end
	for _, connection in self._gpConnections or {} do
		connection:Disconnect()
	end
	self._gpConnections = {}
	GPChairPreview.ReleaseAll(self._gpViews)
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	if self._gpCards then
		table.clear(self._gpCards)
	end
	if self._gpPool then
		table.clear(self._gpPool)
	end
	if self._gpSlots then
		table.clear(self._gpSlots)
	end
	self._gpPage = nil
	self._gpBoard = nil
	self._gpTabs = nil
	self._gpDetail = nil
	self._gpDetailView = nil
	self._gpRefreshWindow = nil
	self._gpEmpty = nil
end

return SkinsGalleryScreen
