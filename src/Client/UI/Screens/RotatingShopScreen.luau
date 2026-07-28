--!strict
-- ROTATING SHOP — timed stock, Pottery Clash arcade family.
-- One §7.4 modal card: a prominent 1Hz gold restock countdown in the header
-- (UIChrome.FormatCountdown, doc §11.3) over a scrolling board of offer cards.
-- The first card is FEATURED and double-width, carrying the rainbow wordmark
-- headline (UIChrome.RainbowGradient offset-scrolled at 0.45 cycles/sec, doc
-- §3.2) — that connection is stored and disconnected on hide (doc §5.4).
--
-- Every card is ONE invisible full-size button (doc §11.6); the price button
-- sits above it and answers for itself. Nothing is ever removed: OWNED goes
-- grey in place, SOLD OUT keeps its slot and dims, and both still play the full
-- press juice before toasting the reason (doc §11.1/§11.2).
--
-- When the countdown reaches zero the board restocks itself — stock returns to
-- its opening level and the window re-arms — so the screen is a closed loop
-- with no backend behind it.
--
-- Fixed px at the 1650×1020 baseline (UIScreenBase attaches the UIScale).

local RunService = game:GetService("RunService")

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UIBadgeComponent = require(script.Parent.Parent.Components.UIBadgeComponent)
local UIScreenBase = require(script.Parent.UIScreenBase)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local GPStoreParts = require(script.Parent.Parent.Framework.GPStoreParts)
local GPChairPreview = require(script.Parent.Parent.Framework.GPChairPreview)
local UITicker = require(script.Parent.Parent.Framework.UITicker)
local Store = require(script.Parent.Parent.Config.PotteryStoreConfig)

type Offer = {
	id: string,
	name: string,
	icon: string,
	rarity: string,
	price: number,
	currency: string,
	stock: number,
	featured: boolean?,
	owned: boolean?,
	tagline: string?,
}

-- Card 1360×820 → content 1332×732 after the §7.4 inset.
local CARD = Vector2.new(1360, 820)
local CONTENT_W = 1332
local CONTENT_H = 732
local HEADER_H = 60
local BOARD_Y = HEADER_H + 12
local BOARD_H = CONTENT_H - BOARD_Y
local COL_W = 319
local COL_GAP = 16
local COL_PITCH = COL_W + COL_GAP
local CARD_H = 316
local ROW_PITCH = CARD_H + COL_GAP
local FEATURED_W = COL_W * 2 + COL_GAP
local RESTOCK_WINDOW = 4 * 3600

local WHITE = Color3.new(1, 1, 1)

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

local function formatPrice(amount: number): string
	local text = string.format("%d", math.floor(amount))
	while true do
		local replaced, count = string.gsub(text, "^(%d+)(%d%d%d)", "%1,%2")
		text = replaced
		if count == 0 then
			break
		end
	end
	return text
end

local function demoOffers(): { Offer }
	return {
		{ id = "emberBlade", name = "EMBER BLADE", icon = "sword", rarity = "Legendary", price = 2400,
			currency = "Cash", stock = 1, featured = true, tagline = "TODAY'S HEADLINE STOCK — ONE ONLY" },
		{ id = "kilnGuard", name = "KILN GUARD", icon = "shield", rarity = "Epic", price = 1200, currency = "Cash", stock = 3 },
		{ id = "luckyClover", name = "LUCKY CLOVER", icon = "luck", rarity = "Rare", price = 45, currency = "Bux", stock = 5 },
		{ id = "starFragment", name = "STAR FRAGMENT", icon = "star", rarity = "Epic", price = 90, currency = "Bux", stock = 2 },
		{ id = "goldCrate", name = "GOLD CRATE", icon = "crate", rarity = "Legendary", price = 199, currency = "Robux", stock = 0 },
		{ id = "tricksterBomb", name = "TRICKSTER BOMB", icon = "bomb", rarity = "Uncommon", price = 350, currency = "Cash", stock = 12 },
		{ id = "royalCrown", name = "ROYAL CROWN", icon = "crown", rarity = "Legendary", price = 499, currency = "Robux", stock = 1, owned = true },
		{ id = "speedBolt", name = "SPEED BOLT", icon = "bolt", rarity = "Common", price = 120, currency = "Cash", stock = 20 },
		{ id = "vaultKey", name = "VAULT KEY", icon = "key", rarity = "Rare", price = 60, currency = "Bux", stock = 4 },
		{ id = "rainbowTrail", name = "RAINBOW TRAIL", icon = "rainbow", rarity = "Legendary", price = 799, currency = "Robux", stock = 1 },
	}
end

local RotatingShopScreen = setmetatable({}, { __index = UIScreenBase })
RotatingShopScreen.__index = RotatingShopScreen

function RotatingShopScreen.new()
	local self = UIScreenBase.new("RotatingShopScreen", 11)
	self._offers = demoOffers()
	self._restockIn = 2 * 3600 + 17 * 60 + 5
	self._openingStock = {} :: { [string]: number }
	self._components = {} :: { any }
	self._tickConn = nil :: RBXScriptConnection?
	self._rainbowConn = nil :: RBXScriptConnection?
	-- Methods only resolve once the metatable is in place.
	local screen = setmetatable(self, RotatingShopScreen)
	screen:_RememberStock()
	return screen
end

function RotatingShopScreen:_RememberStock()
	table.clear(self._openingStock)
	for _, offer in self._offers do
		self._openingStock[offer.id] = offer.stock
	end
end

function RotatingShopScreen:_Toast(text: string, variant: string)
	local hud = self.ScreenController and self.ScreenController:GetScreen("hud")
	if hud then
		hud:PushToast({ text = text, variant = variant })
	end
end

function RotatingShopScreen:_Track(component: any): any
	table.insert(self._components, component)
	return component
end

function RotatingShopScreen:_Ingest(data: any)
	if type(data) ~= "table" then
		return
	end
	if type(data.offers) == "table" then
		self._offers = data.offers
		self:_RememberStock()
	end
	if type(data.restockIn) == "number" then
		self._restockIn = data.restockIn
	end
end

-- ========================================================================
-- Header
-- ========================================================================

function RotatingShopScreen:_BuildHeader(theme: Types.UITheme, content: Frame)
	local header = UIStyler.Frame("Header")
	header.BackgroundTransparency = 1
	header.Size = UDim2.fromOffset(CONTENT_W, HEADER_H)
	header.ZIndex = 44
	header.Parent = content

	local glass = IconArchive.Image(header, "hourglass", 38)
	glass.AnchorPoint = Vector2.new(0, 0.5)
	glass.Position = UDim2.new(0, 0, 0.5, 0)
	glass.ZIndex = 45

	local caption = UIChrome.Text("Caption", 20, theme.Arcade.IceBlue)
	caption.Text = "RESTOCK IN"
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.Position = UDim2.fromOffset(50, 0)
	caption.Size = UDim2.fromOffset(150, HEADER_H)
	caption.ZIndex = 45
	caption.Parent = header

	-- Countdown surface (doc §11.3): 1Hz, gold FredokaOne, HH:MM:SS.
	local countdown = UIChrome.Text("Countdown", 38, theme.Arcade.SunburstGold)
	countdown.Text = UIChrome.FormatCountdown(self._restockIn)
	countdown.TextXAlignment = Enum.TextXAlignment.Left
	countdown.Position = UDim2.fromOffset(204, 0)
	countdown.Size = UDim2.fromOffset(240, HEADER_H)
	countdown.ZIndex = 45
	countdown.Parent = header
	self._countdown = countdown

	local note = UIChrome.BodyText("Note", 18, theme.Arcade.IceBlue)
	note.Text = "Stock rotates every 4 hours. Sold-out slots stay empty until then."
	note.TextXAlignment = Enum.TextXAlignment.Right
	note.AnchorPoint = Vector2.new(1, 0.5)
	note.Position = UDim2.new(1, 0, 0.5, 0)
	note.Size = UDim2.fromOffset(560, HEADER_H)
	note.ZIndex = 45
	note.Parent = header
end

-- ========================================================================
-- Offer cards
-- ========================================================================

function RotatingShopScreen:_BuildOffer(theme: Types.UITheme, offer: Offer, x: number, y: number, width: number)
	local featured = offer.featured == true
	local soldOut = (offer.stock or 0) <= 0
	local owned = offer.owned == true
	local accent = rarityColor(theme, offer.rarity)

	-- Fixed transparent footprint; hover/press scale the inner surface so the
	-- board never reflows (doc §5.1).
	local root = UIStyler.Frame("Offer_" .. offer.id)
	root.BackgroundTransparency = 1
	root.Position = UDim2.fromOffset(x, y)
	root.Size = UDim2.fromOffset(width, CARD_H)
	root.ZIndex = 43
	root.Parent = self._board

	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 43
	hit.Parent = root

	local surface = UIStyler.Frame("Surface")
	surface.BackgroundColor3 = if featured then theme.Arcade.NearBlack2 else theme.Arcade.NearBlack
	surface.BackgroundTransparency = if soldOut then 0.35 else 0
	surface.AnchorPoint = Vector2.new(0.5, 0.5)
	surface.Position = UDim2.fromScale(0.5, 0.5)
	surface.Size = UDim2.fromScale(1, 1)
	surface.ZIndex = 44
	UIChrome.Corner("Arcade").Parent = surface
	UIChrome.Stroke(theme, "Arcade", "Panel").Parent = surface
	UIChrome.GlassGradient().Parent = surface
	surface.Parent = root

	-- Rarity ring: inset inside the black rim, built through the selection
	-- stroke policy (3px border) and only re-tinted to the rarity colour.
	local ring = UIStyler.Frame("RarityRing")
	ring.BackgroundTransparency = 1
	ring.Position = UDim2.fromOffset(5, 5)
	ring.Size = UDim2.new(1, -10, 1, -10)
	ring.ZIndex = 45
	local ringStroke = UIChrome.Stroke(theme, "Arcade", "Selection")
	ringStroke.Color = accent
	ringStroke.Transparency = if soldOut then 0.5 else 0
	ringStroke.Parent = ring
	ring.Parent = surface

	local stockText = if soldOut then "SOLD OUT" else string.format("%d LEFT", offer.stock)
	local stockColor = if soldOut then theme.Arcade.GreyOwned else theme.Arcade.IceBlue

	local priceProps: { [string]: any } = {
		priceCurrency = offer.currency,
		priceAmount = formatPrice(offer.price),
		owned = owned,
		dimmed = soldOut and not owned,
		onClick = function()
			self:_Buy(offer)
		end,
	}

	if featured then
		-- Rainbow wordmark headline (doc §3.2): FredokaOne 40, black-outlined,
		-- 5-stop rainbow gradient offset-scrolled at 0.45 cycles/sec.
		local headline = UIChrome.Text("Headline", 40, WHITE)
		headline.Text = "FEATURED"
		headline.TextXAlignment = Enum.TextXAlignment.Left
		headline.Position = UDim2.fromOffset(24, 14)
		headline.Size = UDim2.fromOffset(width - 200, 48)
		headline.ZIndex = 46
		local rainbow = UIChrome.RainbowGradient(theme)
		rainbow.Parent = headline
		headline.Parent = surface
		self._rainbow = rainbow

		local badge = self:_Track(UIBadgeComponent.new())
		badge:Create(surface, {
			text = "LIMITED",
			variant = "Limited",
			size = UDim2.fromOffset(0, 26),
			position = UDim2.new(1, -20, 0, 24),
			anchorPoint = Vector2.new(1, 0),
		})
		badge.Root.ZIndex = 46

		local art = IconArchive.Image(surface, offer.icon, 150, { golden = offer.rarity == "Legendary" })
		art.AnchorPoint = Vector2.new(0, 0.5)
		art.Position = UDim2.new(0, 36, 0.5, 24)
		art.ZIndex = 46
		if art:IsA("ImageLabel") and soldOut then
			art.ImageTransparency = 0.45
		end

		local name = UIChrome.Text("Name", 30, accent)
		name.RichText = false
		name.Text = offer.name
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Position = UDim2.fromOffset(228, 96)
		name.Size = UDim2.fromOffset(width - 252, 36)
		name.ZIndex = 46
		name.Parent = surface

		local tagline = UIChrome.BodyText("Tagline", 18, theme.Arcade.IceBlue)
		tagline.RichText = false
		tagline.Text = offer.tagline or "Rotates out with the next restock."
		tagline.TextXAlignment = Enum.TextXAlignment.Left
		tagline.Position = UDim2.fromOffset(228, 138)
		tagline.Size = UDim2.fromOffset(width - 252, 24)
		tagline.ZIndex = 46
		tagline.Parent = surface

		local stock = UIChrome.Text("Stock", 22, stockColor)
		stock.Text = stockText
		stock.TextXAlignment = Enum.TextXAlignment.Left
		stock.Position = UDim2.fromOffset(228, 170)
		stock.Size = UDim2.fromOffset(width - 252, 26)
		stock.ZIndex = 46
		stock.Parent = surface

		priceProps.size = UDim2.fromOffset(240, 56)
		priceProps.position = UDim2.fromOffset(228, 214)
	else
		local art = IconArchive.Image(surface, offer.icon, 96, { golden = offer.rarity == "Legendary" })
		art.AnchorPoint = Vector2.new(0.5, 0)
		art.Position = UDim2.new(0.5, 0, 0, 40)
		art.ZIndex = 46
		if art:IsA("ImageLabel") and soldOut then
			art.ImageTransparency = 0.45
		end

		local name = UIChrome.Text("Name", 22, accent)
		name.RichText = false
		name.Text = offer.name
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Position = UDim2.fromOffset(12, 150)
		name.Size = UDim2.fromOffset(width - 24, 28)
		name.ZIndex = 46
		name.Parent = surface

		local stock = UIChrome.Text("Stock", 18, stockColor)
		stock.Text = stockText
		stock.Position = UDim2.fromOffset(12, 182)
		stock.Size = UDim2.fromOffset(width - 24, 24)
		stock.ZIndex = 46
		stock.Parent = surface

		priceProps.size = UDim2.fromOffset(200, 48)
		priceProps.position = UDim2.new(0.5, 0, 1, -14)
		priceProps.anchorPoint = Vector2.new(0.5, 1)
	end

	local price = self:_Track(UIButtonComponent.new())
	price:Create(surface, priceProps)
	price.Root.ZIndex = 47

	hit.Activated:Connect(function()
		self:_Buy(offer)
	end)
	-- animate() is applied LAST, after the final colours (doc §5.1).
	UIChrome.Animate(theme, hit, surface)
end

function RotatingShopScreen:_BuildBoard(theme: Types.UITheme, content: Frame)
	local board = Instance.new("ScrollingFrame")
	board.Name = "Board"
	board.BackgroundTransparency = 1
	board.BorderSizePixel = 0
	board.Position = UDim2.fromOffset(0, BOARD_Y)
	board.Size = UDim2.fromOffset(CONTENT_W, BOARD_H)
	board.CanvasSize = UDim2.new()
	board.ScrollingDirection = Enum.ScrollingDirection.Y
	board.ScrollBarThickness = 6
	board.ScrollBarImageColor3 = theme.Arcade.Gold
	board.ZIndex = 43
	board.Parent = content
	self._board = board
end

function RotatingShopScreen:_RenderBoard()
	if not self._board then
		return
	end
	local theme = self:GetTheme()
	self:_StopRainbow()
	for _, component in self._components do
		component:Destroy()
	end
	table.clear(self._components)
	for _, child in self._board:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	self._rainbow = nil

	-- Manual placement rather than a UIGridLayout: the featured card spans two
	-- columns, which a uniform grid cell cannot express.
	local featured: { Offer } = {}
	local normal: { Offer } = {}
	for _, offer in self._offers do
		if offer.featured then
			table.insert(featured, offer)
		else
			table.insert(normal, offer)
		end
	end

	local column, row = 0, 0
	local function advance(span: number)
		column += span
		if column >= 4 then
			column, row = 0, row + 1
		end
	end

	for _, offer in featured do
		if column > 2 then
			column, row = 0, row + 1
		end
		self:_BuildOffer(theme, offer, column * COL_PITCH, row * ROW_PITCH, FEATURED_W)
		advance(2)
	end
	for _, offer in normal do
		self:_BuildOffer(theme, offer, column * COL_PITCH, row * ROW_PITCH, COL_W)
		advance(1)
	end

	local rows = row + (if column > 0 then 1 else 0)
	self._board.CanvasSize = UDim2.fromOffset(0, math.max(0, rows * ROW_PITCH - COL_GAP))

	if self._rainbow and self:IsVisible() then
		self:_StartRainbow()
	end
end

-- ========================================================================
-- Ambient effects (doc §5.4: stored, visibility-gated, disconnected on hide)
-- ========================================================================

function RotatingShopScreen:_StartRainbow()
	if self._rainbowConn or not self._rainbow then
		return
	end
	self._rainbowConn = UIChrome.ScrollGradient(self._rainbow, 0.45)
end

function RotatingShopScreen:_StopRainbow()
	if self._rainbowConn then
		self._rainbowConn:Disconnect()
		self._rainbowConn = nil
	end
end

function RotatingShopScreen:_StartTicker()
	if self._tickConn then
		return
	end
	local accumulated = 0
	self._tickConn = RunService.Heartbeat:Connect(function(dt: number)
		local label = self._countdown
		if not label or not label.Parent or not UIChrome.IsOnScreen(label) then
			return
		end
		accumulated += dt
		if accumulated < 1 then
			return
		end
		accumulated -= 1
		self._restockIn = math.max(0, self._restockIn - 1)
		label.Text = UIChrome.FormatCountdown(self._restockIn)
		if self._restockIn <= 0 then
			self:_Restock()
		end
	end)
end

function RotatingShopScreen:_StopTicker()
	if self._tickConn then
		self._tickConn:Disconnect()
		self._tickConn = nil
	end
end

function RotatingShopScreen:_Restock()
	for _, offer in self._offers do
		offer.stock = self._openingStock[offer.id] or offer.stock
	end
	self._restockIn = RESTOCK_WINDOW
	self._countdown.Text = UIChrome.FormatCountdown(self._restockIn)
	self:_Toast("THE SHOP HAS RESTOCKED", "Success")
	self:_RenderBoard()
end

-- ========================================================================
-- Buying
-- ========================================================================

function RotatingShopScreen:_Buy(offer: Offer)
	if offer.owned then
		self:_Toast("YOU ALREADY OWN " .. offer.name, "Info")
		return
	end
	if (offer.stock or 0) <= 0 then
		self:_Toast(offer.name .. " IS SOLD OUT", "Error")
		return
	end
	offer.stock -= 1
	self:_Toast(string.format("BOUGHT %s FOR %s %s", offer.name, formatPrice(offer.price), string.upper(offer.currency)), "Success")
	self:_RenderBoard()
end

-- ========================================================================
-- Lifecycle
-- ========================================================================

function RotatingShopScreen:_BuildContent()
	-- GP layout language: the CHAIR SHOP as cutesy pastel ceramics — petal
	-- cards alternating mirror, butter-gold price pills, a rarity glow ramp
	-- and live ViewportFrame chair previews. See _BuildGPLayout below.
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end

	local theme = self:GetTheme()

	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = "ROTATING SHOP",
		sizePx = CARD,
		onClose = function()
			self.ScreenController:HideScreen("rotatingShop")
		end,
	})
	self._modal = modal

	self:_BuildHeader(theme, modal.content)
	self:_BuildBoard(theme, modal.content)
	self:_RenderBoard()
end

function RotatingShopScreen:_OnShow(data: any?)
	self:_Ingest(data)
	if self._gpPage then
		self:_GPShow(data)
		return
	end
	if self._built then
		self._countdown.Text = UIChrome.FormatCountdown(self._restockIn)
		self:_RenderBoard()
	end
	self:_StartTicker()
	self:_StartRainbow()
	if self._modal then
		UIChrome.PopIn(self:GetTheme(), self._modal.content)
	end
end

function RotatingShopScreen:_OnHide()
	if self._gpPage then
		self:_GPHide()
		return
	end
	self:_StopTicker()
	self:_StopRainbow()
end

function RotatingShopScreen:Update(data: any)
	self:_Ingest(data)
	if self._gpPage then
		self:_GPIngest(data)
		self:_GPRender()
		return
	end
	if self._built then
		self._countdown.Text = UIChrome.FormatCountdown(self._restockIn)
		self:_RenderBoard()
	end
end

function RotatingShopScreen:Destroy()
	self:_OnHide()
	self:_OnTeardown()
	for _, component in self._components do
		component:Destroy()
	end
	table.clear(self._components)
	UIScreenBase.Destroy(self)
end

-- ========================================================================
-- GP layout (theme.LayoutKit == "GP") — the CHAIR SHOP from the shipped
-- lobby, rebuilt as cutesy pastel ceramics.
--
-- WHAT THE SOURCE ACTUALLY HAS, and what this branch therefore has:
--   * a DETERMINISTIC hourly rotation (seeded shuffle off the time window),
--     so the featured set needs no round trip and the countdown is just the
--     remainder of the window (PotteryStoreConfig.Window / .SecondsLeft);
--   * the "REFRESHES IN: %02d:%02d:%02d" readout, ticking at 1Hz, which
--     RE-RENDERS the board the moment the window rolls over;
--   * per-card ViewportFrame previews of the real chair, spinning;
--   * OWNED collapsing the buy controls in place;
--   * a Bux price wearing the gem mark, and a SECOND direct-Robux row that
--     appears only where the chair has a product;
--   * a repaint on any ownership change while the panel is open.
--
-- WHAT THIS BRANCH ADDS (pack law 6: density only goes up):
--   * per-item STOCK, derived from the same window seed so the whole board
--     restocks on the tick the countdown rolls — with "Last one!" and a
--     "Sold out" state that keeps its slot instead of vanishing;
--   * three filters (the featured six / the whole buyable catalog / what you
--     already own) with a real empty state on each;
--   * the crate DROP SHARE printed next to every rarity, because "Mythic"
--     alone is decoration and "1 in 534" is information;
--   * a shard craft price on every card, the second route the source's
--     inventory panel exposes;
--   * a running total of what the visible board is worth in Bux.
--
-- The FEATURED slot — and only the featured slot — wears sparkle. The rarity
-- GLOW ramp does the rest of the work: nothing below Epic blooms at all.
-- ========================================================================

local GP_PAGE = Vector2.new(1180, 748)
local GP_FIELD_W = 1108 -- inside the scroller's shadow gutter
local GP_COLS = 4
local GP_GAP = 16
local GP_CARD_W = math.floor((GP_FIELD_W - (GP_COLS - 1) * GP_GAP) / GP_COLS)
local GP_CARD_H = 356
local GP_HERO_W = GP_CARD_W * 2 + GP_GAP
local GP_TABS_H = 56

local GP_TABS = {
	{ id = "featured", label = "The featured six" },
	{ id = "catalog", label = "Whole catalog" },
	{ id = "owned", label = "Already yours" },
}

-- Server time where it exists (the rotation must agree across clients), the
-- local clock where it does not — a standalone collection build has no
-- server, and a countdown that errors is worse than one that drifts.
local function nowSeconds(): number
	local ok, value = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	if ok and typeof(value) == "number" then
		return value
	end
	return os.time()
end

function RotatingShopScreen:_GPIngest(data: any)
	if type(data) ~= "table" then
		return
	end
	if type(data.owned) == "table" then
		table.clear(self._gpOwned)
		for _, id in data.owned do
			self._gpOwned[id] = true
		end
	end
	if type(data.bux) == "number" then
		self._gpBux = data.bux
	end
	if type(data.shards) == "number" then
		self._gpShards = data.shards
	end
	if type(data.onBuy) == "function" then
		self._gpOnBuy = data.onBuy
	end
end

function RotatingShopScreen:_BuildGPLayout()
	local theme = self:GetTheme()

	-- Arcade leftovers must not leak into the pastel page: the classic
	-- _OnShow/_RenderBoard read these and the GP branch answers instead.
	self._modal = nil
	self._board = nil
	self._countdown = nil
	self._rainbow = nil

	self._gpShadows = {}
	self._gpViews = {} :: { any }
	self._gpCards = {} :: { [string]: any }
	self._gpPool = {} :: { any }
	self._gpConnections = {} :: { RBXScriptConnection }
	self._gpOwned = self._gpOwned or {}
	if not next(self._gpOwned) then
		for _, id in Store.DemoState.ownedChairs do
			self._gpOwned[id] = true
		end
	end
	self._gpSold = self._gpSold or {} :: { [string]: number }
	self._gpBux = self._gpBux or Store.DemoState.bux
	self._gpShards = self._gpShards or Store.DemoState.shards
	self._gpTab = self._gpTab or GP_TABS[1].id
	self._gpWindow = Store.Window(nowSeconds())

	local page = GPLayoutKit.Page(theme, self.Root, {
		titleText = "Chair shop",
		subtitleText = Store.Copy.rotatingSubtitle,
		sizePx = GP_PAGE,
		onClose = function()
			self.ScreenController:HideScreen("rotatingShop")
		end,
	})
	-- The scrim becomes the page's OPEN flag, exactly as the source's dim
	-- frame is: every chair preview gates its spin on it, and the window-fill
	-- pass drops every resident model when it goes false.
	page.panel.Parent = page.dim
	self._gpPage = page
	for _, handle in page.shadows do
		table.insert(self._gpShadows, handle)
	end

	-- Header counters: the restock clock and the two balances the board
	-- spends. Same shape for all three, because they are the same kind of fact.
	self._gpClock = GPStoreParts.Counter(theme, page.topRight, {
		iconKey = "hourglass",
		caption = Store.Copy.rotatingRefresh,
		widthPx = 176,
		fill = theme.Arcade.Gold,
		layoutOrder = 1,
		sink = self._gpShadows,
	})
	self._gpClock.value.Text = Store.Clock(Store.SecondsLeft(nowSeconds()))

	self._gpBuxCounter = GPStoreParts.Counter(theme, page.topRight, {
		iconKey = "bux",
		caption = "Bux",
		widthPx = 132,
		layoutOrder = 2,
		sink = self._gpShadows,
	})
	self._gpShardCounter = GPStoreParts.Counter(theme, page.topRight, {
		iconKey = "crystal",
		caption = Store.Copy.galleryShards,
		widthPx = 132,
		layoutOrder = 3,
		sink = self._gpShadows,
	})

	local tabs = GPLayoutKit.Tabs(theme, page.content, { widthPx = 186, heightPx = GP_TABS_H }, self._gpShadows)
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

	-- Manual CanvasSize, not AutomaticCanvasSize: the featured hero spans two
	-- columns, which no uniform grid cell can express, so the cards are placed
	-- by hand — and a pooled hidden card must not be measured.
	local board = GPStoreParts.Scroller(theme, page.content, {
		position = UDim2.fromOffset(0, GP_TABS_H + theme.Spacing.S),
		size = UDim2.new(1, 0, 1, -(GP_TABS_H + theme.Spacing.S)),
		automatic = false,
		name = "ChairBoard",
	})
	self._gpBoard = board

	-- The board's running total sits under the tabs on the right: what the
	-- visible slots would cost to sweep. Cheap to compute, and it is the one
	-- number a rotating shop never tells you.
	self._gpTotal = GPStoreParts.Body(theme, page.content, theme.TextSizes.Small, "", theme.Colors.TextSecondary)
	self._gpTotal.TextXAlignment = Enum.TextXAlignment.Right
	self._gpTotal.AnchorPoint = Vector2.new(1, 0)
	self._gpTotal.Position = UDim2.new(1, 0, 0, GP_TABS_H - 22)
	self._gpTotal.Size = UDim2.fromOffset(420, 20)
	self._gpTotal.ZIndex = 6

	self:_GPRender()
end

-- One pooled GP card. Every child exists up front and is repainted per item,
-- so a re-render never destroys a ViewportFrame (rebuilding a chair model is
-- a dozen part constructions for an identical result).
function RotatingShopScreen:_GPBuildCard(): any
	local theme = self:GetTheme()
	-- The petal index alternates per CARD EVER BUILT, so a pooled card keeps
	-- the silhouette it was born with and the board stays hand-arranged
	-- instead of re-stamping itself on every filter change.
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
	-- The art slot becomes the viewport well: it must clip, because a spinning
	-- model is wider than its seat at 45 degrees.
	card.art.ClipsDescendants = true

	entry.view = GPChairPreview.New(theme, card.art, {
		size = UDim2.fromScale(1, 1),
		plain = true,
		gate = self._gpPage.dim,
		zIndex = card.art.ZIndex + 1,
	})
	table.insert(self._gpViews, entry.view)

	entry.rarity = GPStoreParts.Body(theme, card.body, theme.TextSizes.Small, "", theme.Colors.TextSecondary)
	entry.rarity.ZIndex = 5

	entry.tagline = GPStoreParts.Body(theme, card.body, theme.TextSizes.Body, "", theme.Colors.TextPrimary)
	entry.tagline.TextWrapped = true
	entry.tagline.TextYAlignment = Enum.TextYAlignment.Top
	entry.tagline.Visible = false
	entry.tagline.ZIndex = 5

	entry.stock = GPStoreParts.Body(theme, card.body, theme.TextSizes.Small, "", theme.Colors.TextSecondary)
	entry.stock.ZIndex = 5

	entry.craft = GPStoreParts.Body(theme, card.body, theme.TextSizes.Small, "", theme.Colors.TextSecondary)
	entry.craft.ZIndex = 5

	entry.price = GPStoreParts.PricePill(theme, card.body, self._gpShadows)
	entry.price.root.ZIndex = 6

	entry.buy = GPStoreParts.StateChip(theme, card.body, {
		cornerIndex = index + 1,
		zIndex = 6,
		sink = self._gpShadows,
		onClick = function()
			if entry.chair then
				self:_GPBuy(entry.chair)
			end
		end,
	})

	-- The direct-Robux row. In the source it appears ONLY where the chair has
	-- a product id; here it appears only where a chair is buyable at all, and
	-- it is hidden — not removed — everywhere else.
	entry.robux = GPStoreParts.StateChip(theme, card.body, {
		cornerIndex = index,
		zIndex = 6,
		sink = self._gpShadows,
		onClick = function()
			if entry.chair then
				self:_GPPromptRobux(entry.chair)
			end
		end,
	})

	local badge = GPStoreParts.Badge(theme, card.body, "", theme.Arcade.Gold, index, self._gpShadows)
	badge.root.AnchorPoint = Vector2.new(1, 0)
	badge.root.Position = UDim2.new(1, -theme.Spacing.S, 0, -8)
	badge.root.Visible = false
	entry.badge = badge

	card.root.Activated:Connect(function()
		if entry.chair then
			self:_GPBuy(entry.chair)
		end
	end)
	return entry
end

-- Paint one entry as a NORMAL slot or as the double-width FEATURED hero.
function RotatingShopScreen:_GPPaintCard(entry: any, offer: any, x: number, y: number, hero: boolean)
	local theme = self:GetTheme()
	local spacing = theme.Spacing
	local chair = offer.chair
	local accent = GPStoreParts.RarityColor(theme, chair.rarity)
	local width = if hero then GP_HERO_W else GP_CARD_W

	entry.chair = chair
	entry.root.Position = UDim2.fromOffset(x, y)
	entry.root.Size = UDim2.fromOffset(width, GP_CARD_H)

	-- Rarity GLOW: rebuilt per paint because the tier can change under a
	-- pooled card. The old handle is released so the budget never drifts.
	if entry.glow then
		entry.glow:Release()
		for slot = #self._gpShadows, 1, -1 do
			if self._gpShadows[slot] == entry.glow then
				table.remove(self._gpShadows, slot)
			end
		end
		entry.glow = nil
	end
	entry.glow = GPStoreParts.RarityGlow(theme, entry.body, chair.rarity, self._gpShadows)

	-- Sparkle is the FEATURED slot's alone. A pooled card that stops being
	-- the hero drops it, or the mark stops meaning anything.
	if entry.sparkle then
		entry.sparkle:Destroy()
		entry.sparkle = nil
	end
	if hero then
		entry.sparkle = GPStoreParts.Sparkle(theme, entry.body, theme.Arcade.Gold)
	end

	GPChairPreview.SetAccent(entry.view, accent)

	local artW = if hero then 250 else width - spacing.S * 2
	local artH = if hero then 250 else 150
	entry.art.Position = UDim2.fromOffset(spacing.S, spacing.S)
	entry.art.Size = UDim2.fromOffset(artW, artH)

	local textX = if hero then artW + spacing.L else spacing.S
	local textW = width - textX - spacing.S

	entry.name.AnchorPoint = Vector2.new(0, 0)
	entry.name.Text = chair.name
	entry.name.TextSize = if hero then 28 else 19
	entry.name.Position = UDim2.fromOffset(textX, if hero then 22 else artH + spacing.M)
	entry.name.Size = UDim2.fromOffset(textW, if hero then 36 else 26)

	entry.rarity.Text = GPStoreParts.RarityLine(chair.rarity)
	entry.rarity.TextColor3 = if GPStoreParts.Rank(chair.rarity) >= 5 then theme.Colors.TextPrimary else theme.Colors.TextSecondary
	entry.rarity.Position = UDim2.fromOffset(textX, if hero then 62 else artH + spacing.M + 26)
	entry.rarity.Size = UDim2.fromOffset(textW, 18)

	entry.tagline.Visible = hero
	if hero then
		entry.tagline.Text = "Today's headline slot. It leaves when the clock does."
		entry.tagline.Position = UDim2.fromOffset(textX, 88)
		entry.tagline.Size = UDim2.fromOffset(textW, 44)
	end

	-- STOCK: kept in its slot when it hits zero (a removed row teaches the
	-- player nothing), and shouting only at the very last unit.
	local stockText: string
	local stockTone = theme.Colors.TextSecondary
	if offer.stock <= 0 then
		stockText = Store.Copy.rotatingSoldOut
		stockTone = theme.Colors.Error
	elseif offer.stock == 1 then
		stockText = Store.Copy.rotatingLastOne
		stockTone = theme.Colors.Primary
	else
		stockText = string.format("%d left", offer.stock)
	end
	entry.stock.Text = stockText
	entry.stock.TextColor3 = stockTone
	entry.stock.Position = UDim2.fromOffset(textX, if hero then 140 else artH + spacing.M + 44)
	entry.stock.Size = UDim2.fromOffset(textW, 18)

	-- The craft line sits ABOVE the value stack on a narrow card and BELOW it on
	-- the hero, where the wide text column has room under the controls. Pinning
	-- it to the card foot on both would land it straight on top of the Robux
	-- chip, which is where the two silhouettes used to collide.
	entry.craft.Text = string.format("or %s shards to craft", Store.Comma(chair.shardPrice))
	entry.craft.Position = UDim2.fromOffset(textX, if hero then GP_CARD_H - 28 else artH + spacing.M + 62)
	entry.craft.Size = UDim2.fromOffset(textW, 18)
	entry.craft.Visible = not offer.owned

	local pillY = if hero then 180 else artH + spacing.M + 84
	entry.price.root.Position = UDim2.fromOffset(textX, pillY)
	entry.price.root.Size = UDim2.fromOffset(if hero then 220 else textW, if hero then 44 else 34)
	entry.price.amount.TextSize = if hero then 22 else theme.TextSizes.Button
	entry.price.Set("bux", chair.buxPrice or 0)
	entry.price.root.Visible = not offer.owned and chair.buxPrice ~= nil

	local buyY = pillY + (if hero then 54 else 40)
	entry.buy.root.Position = UDim2.fromOffset(textX, buyY)
	entry.buy.root.Size = UDim2.fromOffset(if hero then 220 else textW, if hero then 42 else 32)

	if offer.owned then
		entry.buy.SetState(Store.Copy.stateOwned, theme.Arcade.GreyOwned, false)
	elseif offer.stock <= 0 then
		entry.buy.SetState(Store.Copy.rotatingSoldOut, theme.Arcade.GreyClaimed, false)
	elseif not chair.buxPrice then
		entry.buy.SetState(Store.Copy.stateLocked, theme.Arcade.GreyOwned, false)
	elseif self._gpBux < chair.buxPrice then
		-- Unaffordable ANSWERS: the control stays live and says what it needs.
		entry.buy.SetState("Need more Bux", theme.Colors.Surface, false)
	else
		entry.buy.SetState("Buy with Bux", theme.Colors.Secondary, true)
	end

	local showRobux = not offer.owned and offer.stock > 0
	entry.robux.root.Visible = showRobux
	if showRobux then
		entry.robux.root.Position = UDim2.fromOffset(textX, buyY + (if hero then 52 else 36))
		entry.robux.root.Size = UDim2.fromOffset(if hero then 220 else textW, if hero then 38 else 28)
		entry.robux.SetState(string.format("R$ %d straight up", chair.robuxPrice), theme.Arcade.Magenta, true)
	end

	entry.badge.root.Visible = hero or offer.owned
	if hero then
		entry.badge.Set("Featured", theme.Arcade.Gold)
	elseif offer.owned then
		entry.badge.Set(Store.Copy.stateOwned, theme.Arcade.GreyOwned)
	end
	entry.badge.shadow:SetEnabled(entry.badge.root.Visible)

	-- A card coming back from the pool had every shadow disabled; re-arm the
	-- ones that are actually visible again and leave the rest off.
	entry.shadow:SetEnabled(true)
	entry.buy.shadow:SetEnabled(true)
	entry.price.shadow:SetEnabled(entry.price.root.Visible)
	entry.robux.shadow:SetEnabled(entry.robux.root.Visible)
	entry.root.Visible = true
end

function RotatingShopScreen:_GPOffers(): { any }
	local window = self._gpWindow
	local featuredSet = Store.FeaturedSet(window)
	local source: { any }
	if self._gpTab == "featured" then
		source = Store.Featured(window)
	elseif self._gpTab == "owned" then
		source = {}
		for _, chair in Store.Chairs do
			if self._gpOwned[chair.id] then
				table.insert(source, chair)
			end
		end
	else
		source = Store.BuyableChairs
	end

	local offers = {}
	for _, chair in source do
		local sold = self._gpSold[chair.id] or 0
		table.insert(offers, {
			chair = chair,
			owned = self._gpOwned[chair.id] == true,
			featured = featuredSet[chair.id] == true,
			stock = math.max(0, Store.StockFor(window, chair) - sold),
		})
	end
	-- Featured first, then down the rarity ladder: the scarce end of the shop
	-- is what the player came for.
	table.sort(offers, function(a, b)
		if a.featured ~= b.featured then
			return a.featured
		end
		local ra, rb = GPStoreParts.Rank(a.chair.rarity), GPStoreParts.Rank(b.chair.rarity)
		if ra ~= rb then
			return ra > rb
		end
		return a.chair.name < b.chair.name
	end)
	return offers
end

function RotatingShopScreen:_GPRender()
	local board = self._gpBoard
	if not board then
		return -- built under another layout; the next Show rebuilds
	end
	local theme = self:GetTheme()
	if self._gpTabs then
		self._gpTabs.Select(self._gpTab)
	end
	self._gpBuxCounter.value.Text = Store.Comma(self._gpBux)
	self._gpShardCounter.value.Text = Store.Comma(self._gpShards)

	local offers = self:_GPOffers()
	local seen: { [string]: boolean } = {}
	local column, row = 0, 0
	local total = 0

	for index, offer in offers do
		local id = offer.chair.id
		seen[id] = true
		local entry = self._gpCards[id]
		if not entry then
			entry = table.remove(self._gpPool) or self:_GPBuildCard()
			entry.root.Parent = board
			self._gpCards[id] = entry
		end
		-- Only the FIRST card of the featured tab is the hero: a board of six
		-- heroes is a board with no hero.
		local hero = index == 1 and offer.featured and self._gpTab == "featured"
		local span = if hero then 2 else 1
		if column + span > GP_COLS then
			column, row = 0, row + 1
		end
		self:_GPPaintCard(entry, offer, column * (GP_CARD_W + GP_GAP), row * (GP_CARD_H + GP_GAP), hero)
		entry.root.LayoutOrder = index
		column += span
		if column >= GP_COLS then
			column, row = 0, row + 1
		end
		if not offer.owned and offer.stock > 0 and offer.chair.buxPrice then
			total += offer.chair.buxPrice
		end
	end

	-- Pool what vanished: hidden, shadows DISABLED, model dropped, never
	-- destroyed. Destroying a card here would also destroy its viewport.
	for id, entry in self._gpCards do
		if not seen[id] then
			entry.chair = nil
			entry.root.Visible = false
			entry.shadow:SetEnabled(false)
			entry.buy.shadow:SetEnabled(false)
			entry.robux.shadow:SetEnabled(false)
			entry.price.shadow:SetEnabled(false)
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
	if #offers == 0 then
		local text = if self._gpTab == "owned"
			then Store.Copy.galleryEmpty
			else Store.Copy.rotatingEmpty
		self._gpEmpty = GPStoreParts.Empty(theme, board, text, self._gpShadows)
	end

	self._gpTotal.Text = if #offers == 0
		then ""
		else string.format("%d slots on the board  ·  %s Bux to sweep it", #offers, Store.Comma(total))

	local rows = row + (if column > 0 then 1 else 0)
	board.CanvasSize = UDim2.fromOffset(0, if #offers == 0 then 160 else math.max(0, rows * (GP_CARD_H + GP_GAP)))

	-- Fill the previews AFTER the layout pass, so "is this card inside the
	-- scroll window" is asked of real geometry rather than of zero rects.
	task.defer(function()
		if not self._gpBoard then
			return
		end
		local fills = {}
		for _, entry in self._gpCards do
			if entry.chair then
				table.insert(fills, {
					view = entry.view,
					chair = entry.chair,
					rank = GPStoreParts.Rank(entry.chair.rarity),
				})
			end
		end
		GPChairPreview.FillStaggered(theme, fills)
	end)
end

function RotatingShopScreen:_GPBuy(chair: any)
	if self._gpOwned[chair.id] then
		self:_Toast("You already have " .. chair.name .. ".", "Info")
		return
	end
	local sold = self._gpSold[chair.id] or 0
	local stock = math.max(0, Store.StockFor(self._gpWindow, chair) - sold)
	if stock <= 0 then
		self:_Toast(chair.name .. " is sold out until the next refresh.", "Error")
		return
	end
	if not chair.buxPrice then
		self:_Toast(chair.name .. " is not for sale — it is an event chair.", "Info")
		return
	end
	if self._gpBux < chair.buxPrice then
		self:_Toast(string.format("You need %s more Bux for %s.", Store.Comma(chair.buxPrice - self._gpBux), chair.name), "Error")
		return
	end
	if self._gpOnBuy then
		self._gpOnBuy(chair, "bux")
	end
	self._gpBux -= chair.buxPrice
	self._gpSold[chair.id] = sold + 1
	self._gpOwned[chair.id] = true
	self:_PlaySound("Success")
	self:_Toast(chair.name .. " is yours.", "Success")
	self:_GPRender()
end

-- The Robux route terminates in the host's prompt; nothing here pretends to
-- be a checkout. Without a handler the screen says so plainly.
function RotatingShopScreen:_GPPromptRobux(chair: any)
	if self._gpOnBuy then
		self._gpOnBuy(chair, "robux")
		return
	end
	self:_Toast("This is where the Roblox purchase prompt opens.", "Info")
end

function RotatingShopScreen:_GPTick()
	if self._gpTickerStop then
		return
	end
	local accumulated = 0
	self._gpTickerStop = UITicker.Register(function(dt: number)
		local clock = self._gpClock
		if not clock or not clock.value.Parent then
			return
		end
		accumulated += dt
		if accumulated < 1 then
			return
		end
		accumulated -= 1
		local now = nowSeconds()
		clock.value.Text = Store.Clock(Store.SecondsLeft(now))
		local window = Store.Window(now)
		if window ~= self._gpWindow then
			-- The hour rolled: a brand new featured six AND a full restock,
			-- because stock is seeded off the same window number.
			self._gpWindow = window
			table.clear(self._gpSold)
			self:_Toast(Store.Copy.rotatingRestocked, "Success")
			self:_GPRender()
		end
	end)
end

function RotatingShopScreen:_GPShow(data: any?)
	self:_GPIngest(data)
	local page = self._gpPage
	if page then
		page.dim.Visible = true
		UIChrome.PopIn(self:GetTheme(), page.panel)
	end
	self._gpWindow = Store.Window(nowSeconds())
	self:_GPRender()
	self:_GPTick()
end

function RotatingShopScreen:_GPHide()
	if self._gpTickerStop then
		self._gpTickerStop()
		self._gpTickerStop = nil
	end
	-- Closing the page drops every resident chair model: the gate goes false,
	-- and a shut panel holding fifty Models is the leak the source fixed.
	if self._gpPage then
		self._gpPage.dim.Visible = false
	end
	for _, entry in self._gpCards do
		GPChairPreview.Clear(entry.view)
	end
end

-- A style rebuild destroys the Gui, but UIShadow BUDGET counts live in
-- StyleKit.Capabilities and only fall when a handle is released — and a
-- ViewportFrame's Model outlives its GuiObject unless it is cleared.
function RotatingShopScreen:_OnTeardown()
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
	self._gpPage = nil
	self._gpBoard = nil
	self._gpTabs = nil
	self._gpClock = nil
	self._gpEmpty = nil
end

return RotatingShopScreen
