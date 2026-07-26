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
	self:_StopTicker()
	self:_StopRainbow()
end

function RotatingShopScreen:Update(data: any)
	self:_Ingest(data)
	if self._built then
		self._countdown.Text = UIChrome.FormatCountdown(self._restockIn)
		self:_RenderBoard()
	end
end

function RotatingShopScreen:Destroy()
	self:_OnHide()
	for _, component in self._components do
		component:Destroy()
	end
	table.clear(self._components)
	UIScreenBase.Destroy(self)
end

return RotatingShopScreen
