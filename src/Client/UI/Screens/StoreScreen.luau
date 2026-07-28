--!strict
-- EXCLUSIVE STORE screen — the doc's featured-shop moment (UI_DESIGN_DOCUMENT.md
-- §3.2 / §7.4 / §8), rebuilt on the Pottery Clash arcade family. One modal card
-- holds: the rainbow "STARTER PACK" headline (offset-scrolled at 0.45 cycles/s),
-- a near-black featured panel (headline item + spinning white sunburst + green
-- price button on the left, three accent-tinted item cards on the right), and a
-- decorative row of four gold REWARD tiles. All layout is fixed px at the
-- 1650×1020 baseline (UIScreenBase attaches the UIScale).
--
-- Purchase flow mirrors ShopScreen (SetPurchaseHandler -> _PromptPurchase ->
-- confirm modal -> _DoPurchase -> hud toast), and every balance change
-- re-renders affordability: each rendered price button re-checks CanAfford and
-- dims in place when the player can't pay (dimmed, never removed — a blocked
-- tap still plays full press juice, then answers with a toast; doc §11.1/§11.2).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local SharedTypes = require(ReplicatedStorage.Shared.Types)

local Types = require(script.Parent.Parent.Types)
local TextConfig = require(script.Parent.Parent.Config.TextConfig)
local UIAssets = require(script.Parent.Parent.Config.UIAssets)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UIScreenBase = require(script.Parent.UIScreenBase)
local ACLayoutKit = require(script.Parent.Parent.Framework.ACLayoutKit)
local GLLayoutKit = require(script.Parent.Parent.Framework.GLLayoutKit)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)

-- Items ship no real iconId yet (ShopConfig.iconId == ""), so item art is an
-- emoji placeholder in an art slot, cycled per slot for variety.
-- Fallback art keys for items whose own iconKey is unset — real pack art
-- from the archive, cycled so a row of cards never repeats one picture.
local ITEM_ART = { "gift", "box", "crystal", "bolt", "rocket", "currency.gem" }

-- Fixed px layout at the 1650×1020 baseline. The modal content frame is
-- 1092×572 (card 1120×660 minus the §7.4 insets).
local HEADLINE_H = 54
local FEATURED_Y = 62
local FEATURED_H = 310
local CARD_W = 210
local CARD_H = 262
local CARD_X = { 410, 634, 858 }
local REWARDS_Y = 388
local TILE_W = 255
local TILE_H = 160
local TILE_PITCH = 279
local PRICE_SIZE = UDim2.fromOffset(118, 48)

local StoreScreen = setmetatable({}, { __index = UIScreenBase })
StoreScreen.__index = StoreScreen

function StoreScreen.new()
	local self = UIScreenBase.new("StoreScreen", 5)
	-- Which category the exclusive store showcases (read in _BuildContent).
	self._categoryId = "featured"
	self._balances = table.clone(ShopConfig.StartingBalances)
	-- Injected by ClientHandler: (item) -> Types.PurchaseResult (mirrors ShopScreen).
	self._purchaseFn = nil :: ((SharedTypes.ShopItem) -> SharedTypes.PurchaseResult)?
	-- Every rendered price button + its item, so affordability re-renders in
	-- place after any balance change (the dim overlay toggles, nothing rebuilds).
	self._priceButtons = {} :: { { button: any, item: SharedTypes.ShopItem, dim: Frame } }
	-- Frugal ambient effects (doc §5.4): connections live only while shown.
	self._rainbowGradient = nil :: UIGradient?
	self._rainbowConn = nil :: RBXScriptConnection?
	self._burst = nil :: ImageLabel?
	self._spinConn = nil :: RBXScriptConnection?
	return setmetatable(self, StoreScreen)
end

-- Mirrors ShopScreen:SetPurchaseHandler — the authoritative purchase function is
-- injected at boot; the store just calls it and renders the result.
function StoreScreen:SetPurchaseHandler(fn: (SharedTypes.ShopItem) -> SharedTypes.PurchaseResult)
	self._purchaseFn = fn
end

-- Boxless item art from the icon archive (doc §10: the flat cartoon set is
-- always shown without a box). IconArchive returns an ImageLabel, or an
-- outlined glyph label when that art is missing — same slot either way.
local function itemArt(parent: Instance, key: string, sizePx: number, zindex: number): GuiObject
	local art = IconArchive.Image(parent, key, sizePx)
	art.Name = "Art"
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.ZIndex = zindex
	return art
end

-- One price button (UIButtonComponent price mode: currency icon leading the
-- number, coloured by currency), registered for affordability re-renders. The
-- dim overlay is a non-Active frame above the button's whole subtree, so a
-- dimmed button still receives taps (full press juice, then the blocked toast)
-- — dimmed, never dead (doc §11.1).
function StoreScreen:_MakePriceButton(parent: Instance, item: SharedTypes.ShopItem, position: UDim2, anchor: Vector2)
	local theme = self:GetTheme()
	local button = UIButtonComponent.new()
	button:Create(parent, {
		priceCurrency = item.currencyType,
		priceAmount = ShopConfig.FormatPrice(item.price),
		size = PRICE_SIZE,
		position = position,
		anchorPoint = anchor,
		onClick = function()
			self:_PromptPurchase(item)
		end,
	})
	button.Root.ZIndex = 46

	local dim = UIStyler.Frame("Dim")
	dim.BackgroundColor3 = theme.Colors.Overlay
	dim.BackgroundTransparency = 0.55
	dim.ZIndex = 10
	dim.Visible = false
	dim.Parent = button.Root

	table.insert(self._priceButtons, { button = button, item = item, dim = dim })
	return button
end

-- One showcase item card: Arcade.Row @ 8% fill + 3px black stroke + glass,
-- accent-rotation name tint (ShopAccents by slot), emoji art, a price button in
-- the item's currency, and a whole-card invisible hit button (doc §11.6 — no
-- dead zones inside a card) with the big hover juice on the card surface.
function StoreScreen:_BuildItemCard(parent: Instance, x: number, slot: number, item: SharedTypes.ShopItem)
	local theme = self:GetTheme()

	-- Root is a fixed transparent footprint; hover/press motion scales the
	-- inner surface only, so the card never reflows or spills its slot.
	local root = UIStyler.Frame("Card_" .. item.id)
	root.BackgroundTransparency = 1
	root.Position = UDim2.fromOffset(x, 24)
	root.Size = UDim2.fromOffset(CARD_W, CARD_H)
	root.ZIndex = 44
	root.Parent = parent

	local surface = UIStyler.Frame("Surface")
	surface.BackgroundColor3 = theme.Arcade.Row
	surface.BackgroundTransparency = theme.Arcade.RowTransparency
	surface.AnchorPoint = Vector2.new(0.5, 0.5)
	surface.Position = UDim2.fromScale(0.5, 0.5)
	surface.Size = UDim2.fromScale(1, 1)
	surface.ZIndex = 45
	UIChrome.Stroke(theme, "Arcade").Parent = surface
	UIChrome.GlassGradient().Parent = surface
	surface.Parent = root

	local accents = theme.Arcade.ShopAccents
	local accent = accents[((slot - 1) % #accents) + 1]
	local name = UIChrome.Text("Name", 22, accent)
	name.Text = TextConfig.Resolve(item.nameKey)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(10, 12)
	name.Size = UDim2.fromOffset(CARD_W - 20, 26)
	name.ZIndex = 46
	name.Parent = surface

	itemArt(surface, item.iconKey or ITEM_ART[(slot % #ITEM_ART) + 1], 110, 46).Position = UDim2.fromOffset(CARD_W / 2, 120)

	self:_MakePriceButton(surface, item, UDim2.fromOffset(CARD_W / 2, CARD_H - 12), Vector2.new(0.5, 1))

	-- Whole-card invisible buy control UNDER the surface subtree: plain frames
	-- and labels never sink input, so taps anywhere on the card reach it —
	-- except over the price button's own hit, which sits higher and answers
	-- itself. Both paths lead to the same purchase prompt.
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 44
	hit.Parent = root
	hit.Activated:Connect(function()
		self:_PromptPurchase(item)
	end)
	UIChrome.Animate(theme, hit, surface)
end

-- ========================================================================
-- AC layout (theme.LayoutKit == "AC") — the terminal STORE page: the same
-- featured stock as dense mono data rows (name / tags / price coloured by
-- currency) beside a bracketed detail pane mirroring the classic primary
-- action (buy the headline item). Row taps keep the exact classic purchase
-- handoff (_PromptPurchase → confirm modal → _DoPurchase), and
-- _RefreshAffordability keeps toggling dim films in place.
-- ========================================================================

local AC_DETAIL_W = 320
local AC_GAP = 24
local AC_ROW_H = 30

function StoreScreen:_BuildACLayout()
	local theme = self:GetTheme()

	-- Stale classic-build handles must not leak into the terminal page:
	-- _OnShow restarts ambient connections off these fields and
	-- _RefreshAffordability walks _priceButtons.
	self._modal = nil
	self._rainbowGradient = nil
	self._burst = nil
	self._priceButtons = {}

	local shell = ACLayoutKit.Shell(theme, self.Root, "STORE")
	ACLayoutKit.SetHints(shell, {
		{ key = "CLICK", action = "BUY" },
		{ key = "ESC", action = "CLOSE" },
	})

	local items = ShopConfig.GetItemsForCategory(self._categoryId)
	local headlineItem = items[1]

	-- Affordability keeps the classic dimmed-never-dead semantics (doc
	-- §11.1/§11.2): a film toggles over the control in place from
	-- _RefreshAffordability, and a blocked tap still answers with the toast.
	local function registerAffordable(host: GuiObject, item: SharedTypes.ShopItem)
		local dim = UIStyler.Frame("Dim")
		dim.BackgroundColor3 = theme.Colors.Overlay
		dim.BackgroundTransparency = 0.55
		dim.ZIndex = host.ZIndex + 3
		dim.Visible = false
		dim.Parent = host
		table.insert(self._priceButtons, { button = host :: any, item = item, dim = dim })
	end

	-- Left: every featured item as one dense data row.
	local list = UIStyler.Frame("List")
	list.BackgroundTransparency = 1
	list.Size = UDim2.new(1, -(AC_DETAIL_W + AC_GAP), 1, 0)
	list.Parent = shell.content
	UIStyler.ListLayout({ HorizontalAlignment = Enum.HorizontalAlignment.Left }).Parent = list

	ACLayoutKit.SectionLabel(theme, list, "FEATURED STOCK", 1)
	ACLayoutKit.ListRow(theme, list, {
		{ text = "NAME", widthScale = 0.5, dim = true },
		{ text = "TAG", widthScale = 0.26, dim = true },
		{ text = "PRICE", widthScale = 0.24, align = Enum.TextXAlignment.Right, dim = true },
	}, { heightPx = 22, layoutOrder = 2 })

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Rows"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.LayoutOrder = 3
	scroll.Size = UDim2.new(1, 0, 1, -40)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = theme.Colors.Accent
	scroll.Parent = list
	UIStyler.ListLayout({ HorizontalAlignment = Enum.HorizontalAlignment.Left }).Parent = scroll

	for order, item in items do
		local tags = item.tags
		local row = ACLayoutKit.ListRow(theme, scroll, {
			{ text = TextConfig.Resolve(item.nameKey), widthScale = 0.5 },
			{ text = if tags then string.upper(table.concat(tags, " ")) else "", widthScale = 0.26, dim = true },
			{
				text = ShopConfig.FormatPrice(item.price),
				widthScale = 0.24,
				align = Enum.TextXAlignment.Right,
				color = UIChrome.CurrencyColor(theme, item.currencyType),
			},
		}, { heightPx = AC_ROW_H, layoutOrder = order, clickable = true })
		local rowButton = row :: TextButton
		rowButton.Activated:Connect(function()
			self:_PromptPurchase(item)
		end)
		registerAffordable(rowButton, item)
	end

	-- Right: bracketed detail pane mirroring the classic primary action —
	-- the headline featured item and its buy control.
	local pane = UIStyler.Frame("Detail")
	pane.BackgroundColor3 = theme.Colors.Surface
	pane.BackgroundTransparency = 0.2
	pane.AnchorPoint = Vector2.new(1, 0)
	pane.Position = UDim2.fromScale(1, 0)
	pane.Size = UDim2.new(0, AC_DETAIL_W, 1, 0)
	UIChrome.Stroke(theme, "Arcade", "Panel").Parent = pane
	pane.Parent = shell.content
	ACLayoutKit.Brackets(theme, pane)

	local inner = UIStyler.Frame("Inner")
	inner.BackgroundTransparency = 1
	inner.Position = UDim2.fromOffset(14, 12)
	inner.Size = UDim2.new(1, -28, 1, -24)
	inner.Parent = pane

	ACLayoutKit.SectionLabel(theme, inner, "FEATURED")

	local name = UIChrome.Text("Name", 16, theme.Colors.TextPrimary)
	name.Text = if headlineItem then TextConfig.Resolve(headlineItem.nameKey) else ""
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(0, 24)
	name.Size = UDim2.new(1, 0, 0, 22)
	name.Parent = inner

	local rule = ACLayoutKit.Rule(theme, inner)
	rule.Position = UDim2.fromOffset(0, 54)

	if headlineItem then
		local headline: SharedTypes.ShopItem = headlineItem

		local priceLabel = UIChrome.BodyText("PriceLabel", 12, theme.Colors.TextSecondary)
		priceLabel.Text = "PRICE"
		priceLabel.TextXAlignment = Enum.TextXAlignment.Left
		priceLabel.Position = UDim2.fromOffset(0, 64)
		priceLabel.Size = UDim2.new(0.4, 0, 0, 18)
		priceLabel.Parent = inner

		local currency = ShopConfig.Currencies[headline.currencyType]
		local price = UIChrome.BodyText("Price", 14, UIChrome.CurrencyColor(theme, headline.currencyType))
		price.Text = ShopConfig.FormatPrice(headline.price)
			.. " "
			.. string.upper(if currency then TextConfig.Resolve(currency.nameKey) else headline.currencyType)
		price.TextXAlignment = Enum.TextXAlignment.Right
		price.AnchorPoint = Vector2.new(1, 0)
		price.Position = UDim2.new(1, 0, 0, 64)
		price.Size = UDim2.new(0.6, 0, 0, 18)
		price.Parent = inner

		local buy = ACLayoutKit.ActionButton(theme, inner, "BUY", function()
			self:_PromptPurchase(headline)
		end)
		buy.AnchorPoint = Vector2.new(0, 1)
		buy.Position = UDim2.new(0, 0, 1, 0)
		buy.Size = UDim2.new(1, 0, 0, 32)
		registerAffordable(buy, headline)
	end

	self:_RefreshAffordability()
end

function StoreScreen:_BuildContent()
	-- GP layout language: the pastel pottery SHELF (cream page, rose ribbon,
	-- petal cards alternating mirror, butter price pills) — see _BuildGPLayout.
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end
	-- GL layout language: comic diagonal composition (slanted banner header,
	-- trapezoid tabs, tilted cut-silhouette cards) — see _BuildGLLayout below.
	if self:LayoutKit() == "GL" then
		self:_BuildGLLayout()
		return
	end
	if self:LayoutKit() == "AC" then
		self:_BuildACLayout()
		return
	end

	local theme = self:GetTheme()

	-- The §7.4 modal anatomy (dim → card → red header + close X → content).
	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = TextConfig.Resolve("store.title"),
		sizePx = Vector2.new(1120, 660),
		onClose = function()
			self.ScreenController:HideScreen("store")
		end,
	})
	self._modal = modal
	local content = modal.content

	-- Rainbow wordmark headline (doc §3.2): FredokaOne 44, black-outlined,
	-- 5-stop rainbow gradient offset-scrolled at 0.45 cycles/s while shown.
	local headline = UIChrome.Text("Headline", 44, theme.Colors.TextPrimary)
	headline.Text = "STARTER PACK"
	headline.Position = UDim2.fromOffset(0, 0)
	headline.Size = UDim2.new(1, 0, 0, HEADLINE_H)
	headline.ZIndex = 43
	local rainbow = UIChrome.RainbowGradient(theme)
	rainbow.Parent = headline
	self._rainbowGradient = rainbow
	headline.Parent = content

	-- Featured panel: near-black well + 3px black stroke + glass sheen.
	local featured = UIStyler.Frame("Featured")
	featured.BackgroundColor3 = theme.Arcade.NearBlack2
	featured.BackgroundTransparency = 0
	featured.Position = UDim2.fromOffset(0, FEATURED_Y)
	featured.Size = UDim2.new(1, 0, 0, FEATURED_H)
	featured.ZIndex = 43
	UIChrome.Stroke(theme, "Arcade").Parent = featured
	UIChrome.GlassGradient().Parent = featured
	featured.Parent = content

	-- Real featured items drive the whole panel: item[1] is the pack headline
	-- (name, sunburst art, price button), items[2..4] are the showcase cards.
	local items = ShopConfig.GetItemsForCategory(self._categoryId)
	local headlineItem = items[1]

	-- Left half: featured item name (gold 30), art slot over a spinning white
	-- sunburst (doc §10 — white @ 0.7, 45°/s, only while on-screen), green
	-- price button buying it.
	local featuredName = UIChrome.Text("FeaturedName", 30, theme.Arcade.Gold)
	featuredName.Text = headlineItem and TextConfig.Resolve(headlineItem.nameKey) or ""
	featuredName.TextXAlignment = Enum.TextXAlignment.Left
	featuredName.TextTruncate = Enum.TextTruncate.AtEnd
	featuredName.Position = UDim2.fromOffset(24, 18)
	featuredName.Size = UDim2.fromOffset(360, 36)
	featuredName.ZIndex = 45
	featuredName.Parent = featured

	local artSlot = UIStyler.Frame("ArtSlot")
	artSlot.BackgroundTransparency = 1
	artSlot.AnchorPoint = Vector2.new(0.5, 0)
	artSlot.Position = UDim2.fromOffset(202, 70)
	artSlot.Size = UDim2.fromOffset(160, 160)
	artSlot.ZIndex = 45
	artSlot.Parent = featured
	local burst, spin = UIAssets.SunburstBehind(artSlot, Color3.new(1, 1, 1), 0.7, 45)
	self._burst = burst
	self._spinConn = spin
	itemArt(artSlot, (headlineItem and headlineItem.iconKey) or ITEM_ART[1], 120, 46).Position = UDim2.fromScale(0.5, 0.5)

	if headlineItem then
		self:_MakePriceButton(featured, headlineItem, UDim2.fromOffset(202, 246), Vector2.new(0.5, 0))
	end

	-- Right half: three showcase cards for items[2..4].
	for slot = 1, 3 do
		local item = items[slot + 1]
		if item then
			self:_BuildItemCard(featured, CARD_X[slot], slot, item)
		end
	end

	-- Decorative reward strip: four near-black tiles, gold FredokaOne REWARD,
	-- boxless Cash icon (doc §10 — flat cartoon PNGs are always boxless).
	local rewards = UIStyler.Frame("Rewards")
	rewards.BackgroundTransparency = 1
	rewards.Position = UDim2.fromOffset(0, REWARDS_Y)
	rewards.Size = UDim2.new(1, 0, 0, TILE_H)
	rewards.ZIndex = 43
	rewards.Parent = content
	for i = 1, 4 do
		local tile = UIStyler.Frame("Reward" .. i)
		tile.BackgroundColor3 = theme.Arcade.NearBlack
		tile.BackgroundTransparency = 0
		tile.Position = UDim2.fromOffset((i - 1) * TILE_PITCH, 0)
		tile.Size = UDim2.fromOffset(TILE_W, TILE_H)
		tile.ZIndex = 44
		UIChrome.Stroke(theme, "Arcade").Parent = tile
		UIChrome.GlassGradient().Parent = tile
		tile.Parent = rewards

		local label = UIChrome.Text("Label", 26, theme.Arcade.Gold)
		label.Text = "REWARD"
		label.Position = UDim2.fromOffset(0, 14)
		label.Size = UDim2.new(1, 0, 0, 30)
		label.ZIndex = 45
		label.Parent = tile

		local icon = UIAssets.Icon(tile, "Cash", 72)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 62)
		icon.ZIndex = 45
	end

	self:_RefreshAffordability()
end

-- Re-check CanAfford for every rendered price button and dim the ones the
-- player can't pay for — in place, controls never removed (doc §11.2).
function StoreScreen:_RefreshAffordability()
	-- GP pastel layout: affordability is part of the card paint (the pill goes
	-- quiet and the card SAYS what is short), so a balance change re-renders
	-- the pooled cards in place (see _GPRefresh).
	if self:LayoutKit() == "GP" then
		self:_GPRefresh()
		return
	end
	-- GL comic layout: affordability is part of the card paint, so a balance
	-- change re-renders the pooled cards in place (see _GLRefresh).
	if self:LayoutKit() == "GL" then
		self:_GLRefresh()
		return
	end
	for _, entry in self._priceButtons do
		entry.dim.Visible = not ShopConfig.CanAfford(self._balances, entry.item)
	end
end

-- Raise a confirm modal; on confirm, run the injected purchase (mirrors
-- ShopScreen:_PromptPurchase, including the modal keys). A tap on an
-- unaffordable control has already played its press juice — answer it with
-- the reason instead of the modal (every tap answers, doc §11.1).
function StoreScreen:_PromptPurchase(item: SharedTypes.ShopItem)
	if not ShopConfig.CanAfford(self._balances, item) then
		local hud = self.ScreenController:GetScreen("hud")
		if hud then
			hud:PushToast({ textKey = "shop.cant_afford", variant = "Error" })
		end
		return
	end
	local currency = ShopConfig.Currencies[item.currencyType]
	local body = string.format(
		"%s — %s %s",
		TextConfig.Resolve(item.nameKey),
		ShopConfig.FormatPrice(item.price),
		currency and TextConfig.Resolve(currency.nameKey) or ""
	)
	self.ScreenController:ShowModal({
		kind = "Confirm",
		titleKey = "modal.confirm_purchase.title",
		body = body,
		confirmKey = "shop.buy",
		cancelKey = "modal.cancel",
		onConfirm = function()
			self:_DoPurchase(item)
		end,
	})
end

function StoreScreen:_DoPurchase(item: SharedTypes.ShopItem)
	if not self._purchaseFn then
		return
	end
	local result = self._purchaseFn(item)
	if result.balances then
		self._balances = result.balances
	end
	local hud = self.ScreenController:GetScreen("hud")
	if hud then
		hud:PushToast({
			textKey = result.success and "shop.purchase_success" or result.messageKey,
			variant = result.success and "Success" or "Error",
		})
		if result.balances then
			hud:Update({ values = result.balances })
		end
	end
	-- Balances changed: re-render affordability on every price button in place.
	self:_RefreshAffordability()
end

function StoreScreen:_OnShow(data: any?)
	if data and data.balances then
		self._balances = data.balances
	end
	-- Restart the frugal ambient effects (disconnected on hide, doc §5.4).
	-- First show: _BuildContent just created these connections, so the nil
	-- guards keep them single.
	if self._rainbowGradient and not self._rainbowConn then
		self._rainbowConn = UIChrome.ScrollGradient(self._rainbowGradient, 0.45)
	end
	if self._burst and not self._spinConn then
		self._spinConn = UIChrome.Spin(self._burst, 45)
	end
	self:_RefreshAffordability()
end

function StoreScreen:_OnHide()
	if self._rainbowConn then
		self._rainbowConn:Disconnect()
		self._rainbowConn = nil
	end
	if self._spinConn then
		self._spinConn:Disconnect()
		self._spinConn = nil
	end
end

function StoreScreen:Update(data: any)
	if data.balances then
		self._balances = data.balances
		if self._built then
			self:_RefreshAffordability()
		end
	end
end

function StoreScreen:Destroy()
	self:_OnHide()
	UIScreenBase.Destroy(self)
end

-- ======================================================================
-- GL layout (theme.LayoutKit == "GL") — the comic diagonal store, composed
-- entirely from GLLayoutKit so this page and the APPROVED shop page are
-- literally the same parts: slanted banner Page, trapezoid Tabs, a wide
-- featured hero slab, a 3-up staggered field of chamfered cards, ink/gold
-- PriceChips and tilted Badges that overhang their cards.
--
-- Presentation only: the same ShopConfig stock, the same balances, the same
-- purchase handoff (_PromptPurchase -> confirm modal -> the injected
-- _purchaseFn). Affordability still answers in place (doc §11.2) — the GL
-- form is DIMMED GOLD numerals on the ink chip, never a removed control and
-- never a candy pill.
-- ======================================================================

local GL_PAGE = Vector2.new(1120, 660)
local GL_FIELD_W = 1058 -- card field width inside the page's content frame
local GL_COLS = 3
local GL_GAP = 18
local GL_CARD_H = 236
local GL_HERO_H = 240

function StoreScreen:_BuildGLLayout()
	local theme = self:GetTheme()

	-- Classic/AC leftovers must not leak into the comic page: _OnShow restarts
	-- the ambient effects off these fields and _RefreshAffordability walks
	-- _priceButtons (which the GL branch answers by re-rendering instead).
	self._modal = nil
	self._rainbowGradient = nil
	self._burst = nil
	self._priceButtons = {}

	self._glShadows = {}
	self._glCards = {} :: { [string]: any }
	self._glCardPool = {} :: { any }
	self._glCounters = {} :: { [string]: any }
	-- The GL page browses the same categories the shop does. This is a
	-- LAYOUT-LOCAL cursor: the classic build's _categoryId is never written,
	-- so the exclusive-store showcase keeps its exact classic behaviour.
	self._glCategoryId = self._glCategoryId or self._categoryId

	local page = GLLayoutKit.Page(theme, self.Root, {
		titleText = TextConfig.Resolve("store.title"),
		sizePx = GL_PAGE,
		onClose = function()
			self.ScreenController:HideScreen("store")
		end,
	})
	for _, handle in page.shadows do
		table.insert(self._glShadows, handle)
	end
	self._glPage = page

	-- Currency counters in the page's top-right slot: ink plate + gold
	-- numerals + the currency glyph (the one legal value treatment).
	for i, currency in ShopConfig.GetOrderedCurrencies() do
		local chip = GLLayoutKit.PriceChip(theme, page.topRight, self._glShadows)
		chip.root.Name = "Counter_" .. currency.id
		chip.root.LayoutOrder = i
		chip.root.Rotation = GLLayoutKit.TILT
		-- currency.iconId is the ART; currency.icon is an EMOJI string.
		chip.icon.Image = currency.iconId or ""
		chip.amount.Text = ShopConfig.FormatPrice(self._balances[currency.id] or 0)
		self._glCounters[currency.id] = chip
	end

	local tabs = GLLayoutKit.Tabs(theme, page.content, { widthPx = 186 })
	self._glTabs = tabs
	for _, category in ShopConfig.GetOrderedCategories() do
		local categoryId = category.id
		tabs.Add(TextConfig.Resolve(category.nameKey), categoryId, function()
			if self._glCategoryId == categoryId then
				return
			end
			self._glCategoryId = categoryId
			self:_GLRefresh()
		end)
	end

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Items"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, 62)
	scroll.Size = UDim2.new(1, 0, 1, -62)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = theme.Arcade.Gold
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ClipsDescendants = true -- MUST clip: unclipped rows spill past the
	-- frame (padding below gives badge overhang room inside the viewport)
	local pad = Instance.new("UIPadding")
	pad.Name = "glStorePad"
	pad.PaddingTop = UDim.new(0, 16)
	pad.PaddingBottom = UDim.new(0, 16)
	pad.PaddingLeft = UDim.new(0, 14)
	pad.Parent = scroll
	scroll.Parent = page.content
	self._glScroll = scroll

	self:_GLRefresh()
end

-- One pooled GL card: the kit's chamfered plate plus the promo copy, ink
-- price chip, tilted badge and heat CTA the hero slab needs. Click handlers
-- read entry.item, so a pooled card never has to re-wire its connections.
function StoreScreen:_GLBuildCard(): any
	local theme = self:GetTheme()
	local entry: any = {}
	local card = GLLayoutKit.Card(theme, self._glScroll, self._glShadows)
	entry.root = card.root
	entry.body = card.body
	entry.art = card.art
	entry.artLabel = card.artLabel
	entry.artImage = card.artImage
	entry.name = card.name
	entry.shadow = card.shadow

	local desc = GLLayoutKit.BodyText(theme, 15, theme.Colors.TextSecondary, "Desc")
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.TextWrapped = true
	desc.Visible = false
	desc.ZIndex = 3
	desc.Parent = card.body
	entry.desc = desc

	entry.price = GLLayoutKit.PriceChip(theme, card.body, self._glShadows)

	-- Badge and ActionButton register their sticker shadow in the sink they
	-- are handed; a one-shot sink hands the HANDLE back (pooling needs
	-- SetEnabled), and the handle then joins the screen's release list.
	local badgeSink = {}
	local badge, badgeText = GLLayoutKit.Badge(theme, card.body, "", theme.Arcade.Red, badgeSink)
	entry.badge = badge
	entry.badgeText = badgeText
	entry.badgeShadow = badgeSink[1]
	table.insert(self._glShadows, badgeSink[1])

	local ctaSink = {}
	local cta = GLLayoutKit.ActionButton(theme, card.body, TextConfig.Resolve("shop.buy"), function()
		local item = entry.item
		if item then
			self:_PromptPurchase(item)
		end
	end, ctaSink)
	cta.Visible = false
	entry.cta = cta
	entry.ctaShadow = ctaSink[1]
	table.insert(self._glShadows, ctaSink[1])

	card.root.Activated:Connect(function()
		local item = entry.item
		if item then
			self:_PromptPurchase(item)
		end
	end)
	return entry
end

-- Keyed pooled reconcile: the featured item takes the hero slab, the rest
-- flow 3-up below it. Each column steps DOWN the diagonal axis and the plate
-- tilt alternates against it, so a row reads as a descending slash instead
-- of a ruled shelf.
function StoreScreen:_GLRefresh()
	local scroll = self._glScroll
	if not scroll then
		return -- built under another layout; the next Show rebuilds
	end
	local theme = self:GetTheme()
	local gold = theme.Arcade.Gold

	local tabs = self._glTabs
	if tabs then
		tabs.Select(self._glCategoryId)
	end

	local items = ShopConfig.GetItemsForCategory(self._glCategoryId)
	local seen = {}
	local cardW = math.floor((GL_FIELD_W - (GL_COLS - 1) * GL_GAP) / GL_COLS)

	for i, item in items do
		seen[item.id] = true
		local entry = self._glCards[item.id]
		if not entry then
			entry = table.remove(self._glCardPool) or self:_GLBuildCard()
			entry.root.Visible = true
			entry.root.Parent = scroll
			entry.shadow:SetEnabled(true)
			entry.price.shadow:SetEnabled(true)
			self._glCards[item.id] = entry
		end
		entry.item = item

		local hero = i == 1
		local root = entry.root :: TextButton
		local currency = ShopConfig.Currencies[item.currencyType]
		local affordable = ShopConfig.CanAfford(self._balances, item)

		-- The ROOT never rotates: gamepad/touch bounds stay rectangular on
		-- slanted chrome (a11y law). The body plate carries the tilt.
		root.Rotation = 0
		if hero then
			root.Position = UDim2.fromOffset(0, 4)
			root.Size = UDim2.new(1, -14, 0, GL_HERO_H)
			entry.body.Rotation = 0 -- CLIPPING LAW: scroll children stay axis-aligned
			entry.art.AnchorPoint = Vector2.new(0, 0)
			entry.art.Position = UDim2.fromOffset(16, 14)
			entry.art.Size = UDim2.new(0.42, 0, 1, -28)
			-- Real artwork from the ICON ARCHIVE; the ART SLOT placeholder only

			-- survives where no art resolves for the item.

			GLLayoutKit.ApplyItemArt(entry, item)

			entry.artLabel.TextSize = 18
			entry.name.TextSize = 36
			entry.name.Position = UDim2.new(0.46, 0, 0, 28)
			entry.name.Size = UDim2.new(0.52, 0, 0, 46)
			entry.desc.Visible = true
			entry.desc.Position = UDim2.new(0.46, 0, 0, 80)
			entry.desc.Size = UDim2.new(0.5, 0, 0, 58)
			entry.desc.Text = TextConfig.Resolve(item.descriptionKey)
			entry.price.root.Size = UDim2.fromOffset(190, 46)
			entry.price.root.Position = UDim2.new(0.46, 0, 1, -70)
			entry.price.amount.TextSize = 26
			entry.cta.Visible = true
			entry.cta.Size = UDim2.fromOffset(210, 52)
			entry.cta.Position = UDim2.new(0.46, 210, 1, -73)
			entry.ctaShadow:SetEnabled(true)
		else
			entry.desc.Visible = false
			entry.cta.Visible = false
			entry.ctaShadow:SetEnabled(false)
			local gi = i - 2 -- grid index below the hero
			local col = gi % GL_COLS
			local row = gi // GL_COLS
			local stagger = col * 14
			root.Position = UDim2.fromOffset(col * (cardW + GL_GAP), GL_HERO_H + 22 + row * (GL_CARD_H + 30) + stagger)
			root.Size = UDim2.fromOffset(cardW, GL_CARD_H)
			entry.body.Rotation = 0 -- CLIPPING LAW: scroll children stay axis-aligned
			entry.art.AnchorPoint = Vector2.new(0.5, 0)
			entry.art.Position = UDim2.new(0.5, 0, 0, 14)
			entry.art.Size = UDim2.new(1, -28, 0, 118)
			GLLayoutKit.ApplyItemArt(entry, item)

			entry.artLabel.TextSize = 13
			entry.name.TextSize = 21
			entry.name.Position = UDim2.fromOffset(14, 142)
			entry.name.Size = UDim2.new(1, -28, 0, 26)
			entry.price.root.Size = UDim2.fromOffset(150, 38)
			entry.price.root.Position = UDim2.new(0.5, -75, 1, -52)
			entry.price.amount.TextSize = 20
		end

		entry.name.Text = string.upper(TextConfig.Resolve(item.nameKey))
		entry.price.icon.Image = (currency and currency.iconId) or ""
		entry.price.amount.Text = ShopConfig.FormatPrice(item.price)
		-- Ink plate + gold numerals; unaffordable DIMS the numerals in place,
		-- it never turns the chip into a coloured candy pill.
		entry.price.root.ImageColor3 = theme.Arcade.NearBlack
		entry.price.amount.TextColor3 = affordable and gold or theme.Colors.Disabled

		-- Badge from the item's first tag; the hero wears a gold FEATURED.
		local tag = item.tags and item.tags[1]
		if hero or tag then
			entry.badge.Visible = true
			entry.badge.ImageColor3 = hero and gold or theme.Arcade.Red
			entry.badgeText.Text = string.upper(hero and "FEATURED" or tag)
			-- Cream on every badge: text FILL is never black (pack law); the
			-- black is the outline stroke the kit's Text already applied.
			entry.badgeText.TextColor3 = theme.Colors.TextPrimary
			entry.badgeShadow:SetEnabled(true)
		else
			entry.badge.Visible = false
			entry.badgeShadow:SetEnabled(false)
		end

		root.LayoutOrder = i
	end

	-- Release vanished cards to the pool: hidden, shadows DISABLED, never
	-- destroyed (the pack pooling law).
	for id, entry in self._glCards do
		if not seen[id] then
			entry.item = nil
			entry.root.Visible = false
			entry.shadow:SetEnabled(false)
			entry.price.shadow:SetEnabled(false)
			entry.badgeShadow:SetEnabled(false)
			entry.ctaShadow:SetEnabled(false)
			table.insert(self._glCardPool, entry)
			self._glCards[id] = nil
		end
	end

	for id, chip in self._glCounters do
		chip.amount.Text = ShopConfig.FormatPrice(self._balances[id] or 0)
	end
	-- Rotated children escape ClipsDescendants; sweep the viewport clean.
	if self._glScroll then
		GLLayoutKit.EnforceClipSafety(self._glScroll)
	end
end

-- A style rebuild destroys the Gui, but UIShadow BUDGET counts live in
-- StyleKit.Capabilities and only fall when a handle is released — so every
-- GL shadow handle is handed back here.
function StoreScreen:_OnTeardown()
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	if self._gpCards then
		table.clear(self._gpCards)
	end
	if self._gpCardPool then
		table.clear(self._gpCardPool)
	end
	if self._gpCounters then
		table.clear(self._gpCounters)
	end
	self._gpTabs = nil
	self._gpPage = nil
	self._gpScroll = nil
	self._gpRewardStrip = nil

	GLLayoutKit.ReleaseShadows(self._glShadows)
	if self._glCards then
		table.clear(self._glCards)
	end
	if self._glCardPool then
		table.clear(self._glCardPool)
	end
	if self._glCounters then
		table.clear(self._glCounters)
	end
	self._glTabs = nil
	self._glPage = nil
	self._glScroll = nil
end

-- ======================================================================
-- GP layout (theme.LayoutKit == "GP") — the pastel SHELF, composed from
-- GPLayoutKit so this page and every other GP screen are literally the same
-- parts: a cream Page under a rose ribbon, category Tabs, and the SAME
-- ShopConfig stock as petal cards whose corners ALTERNATE mirror across the
-- grid (pack law 4 — a shelf reads hand-arranged, never stamped). Value is
-- the butter-gold PricePill; the item's tag is a glaze chip off the pack's
-- DialectTokens.rarity ramp; every plate casts a shadow deepened from its
-- OWN fill (pack law 2), which is what stops this page reading grey.
--
-- Presentation only: the same categories, the same balances, the same
-- purchase handoff (_PromptPurchase -> confirm modal -> the injected
-- _purchaseFn). Affordability still answers IN PLACE (doc §11.2) — the GP
-- form is a QUIETED pill plus a printed shortfall line, never a removed
-- control, and a blocked tap still plays its juice before the toast.
--
-- DENSITY (pack law 6): this branch is a superset of both siblings. It keeps
-- the classic build's featured item, its showcase cards and its four reward
-- tiles; it keeps the GL branch's category tabs, currency counters, item
-- blurb, tag badge and buy CTA; and it ADDS a per-card shortfall/purse line,
-- plus a blurb on the grid cards the GL branch shows only on the hero.
-- ======================================================================

local GP_PAGE = Vector2.new(1120, 700)
local GP_FIELD_W = 1064 -- content (1092) minus the shelf padding and scrollbar
local GP_COLS = 3
local GP_GAP = 16
local GP_CARD_H = 320
local GP_HERO_H = 240
local GP_TILE_W = 254
local GP_TILE_H = 132
local GP_REWARD_TILES = 4

-- The pack's glaze ramp (cream -> sage -> sky -> lavender -> rose-gold) IS
-- its rarity language, so the shop's promo tags ride the same ladder: a
-- "Rare" chip here and a Legendary crate elsewhere agree on what rare looks
-- like. Unknown tags land on the calm bottom rung rather than inventing a hue.
local GP_TAG_RANK: { [string]: number } = {
	Sale = 2,
	New = 3,
	Popular = 3,
	Limited = 4,
	Rare = 5,
}

-- GP never shouts. TextConfig ships arcade-cased copy ("STORE") that every
-- other pack renders verbatim, so the SAME string is retitled for DISPLAY
-- only — no config, no data and no other branch is touched. This is the
-- ShopScreen GP branch's rule, kept identical so the two shop pages agree.
local function gpTitleCase(text: string): string
	if string.find(text, "<", 1, true) then
		return text
	end
	-- Only SHOUTED copy is retitled. A string that already carries a lowercase
	-- letter was cased deliberately by its author, and flattening it would do
	-- real damage: TextConfig's "2x XP (1h)" comes back out as "2X Xp (1H)".
	-- The law is "never shout", not "always title-case".
	if string.find(text, "%l") then
		return text
	end
	local retitled = string.gsub(string.lower(text), "[%a][%w']*", function(word: string): string
		return string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2)
	end)
	return retitled
end

local function gpRampColor(theme: Types.UITheme, rank: number): Color3
	local tokens = (theme :: any).DialectTokens
	local ramp = tokens and tokens.rarity
	local color = if type(ramp) == "table" then ramp[math.clamp(rank, 1, #ramp)] else nil
	return if typeof(color) == "Color3" then color else theme.Colors.Surface
end

-- The icon archive's GLYPH FALLBACK is born pure-white with a black text
-- stroke — both banned outright by pack law 1. Any archive art this page
-- places goes through here so a pending upload can never punch a hole in the
-- palette.
local function gpArt(theme: Types.UITheme, parent: Instance, key: string, sizePx: number, query: any?): GuiObject
	local art = IconArchive.Image(parent, key, sizePx, query)
	if art:IsA("TextLabel") then
		art.TextColor3 = theme.Colors.TextPrimary
		art.TextStrokeTransparency = 1
	end
	return art
end

type GPChip = { root: Frame, label: TextLabel, stroke: UIStroke }

-- A glaze chip. Deliberately SHADOW-FREE: one per card across a full shelf
-- would spend a fifth of the engine's ~100-shadow budget on decoration, and
-- the petal silhouette carries it without one.
local function gpChip(theme: Types.UITheme, parent: Instance, index: number): GPChip
	local fill = theme.Colors.Surface
	local root = UIStyler.Frame("Chip")
	root.BackgroundColor3 = fill
	root.ZIndex = 6
	root.Parent = parent
	GPLayoutKit.Petal(theme, root, index)
	local stroke = GPLayoutKit.SoftStroke(theme, root, fill)

	-- Ink, not TextOnPrimary: near-white measures 2.14:1 on these tints and is
	-- legal only for LARGE display text on a deepened one.
	local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "ChipText")
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 7
	label.Parent = root
	return { root = root, label = label, stroke = stroke }
end

type GPButton = { root: TextButton, shape: Frame, label: TextLabel, stroke: UIStroke, shadow: any }

-- GPLayoutKit ships no action button, so this is the local one: a petal plate
-- in a pack colour, a deepened-tint stroke, its own hue-matched shadow and
-- the shared hover/press juice. The BUTTON stays transparent and the fill
-- lives on a child — UIStyleEnforcer backstops any SOLID GuiButton with a
-- BLACK 2px stroke, which would break pack law 1 on sight.
local function gpButton(
	theme: Types.UITheme,
	parent: Instance,
	text: string,
	fill: Color3,
	index: number,
	sink: { any }?,
	onClick: () -> ()
): GPButton
	local root = Instance.new("TextButton")
	root.Name = "GPButton"
	root.BackgroundTransparency = 1
	root.Text = ""
	root.AutoButtonColor = false
	root.ZIndex = 6
	root.Parent = parent

	local shape = UIStyler.Frame("Shape")
	shape.BackgroundColor3 = fill
	shape.Size = UDim2.fromScale(1, 1)
	shape.ZIndex = 6
	shape.Parent = root
	GPLayoutKit.Petal(theme, shape, index)
	local stroke = GPLayoutKit.SoftStroke(theme, shape, fill)
	local shadow = GPLayoutKit.Shadow(theme, shape, "sm", sink, fill)

	local label = GPLayoutKit.Text(theme, theme.TextSizes.Button, theme.Colors.TextPrimary, "Label")
	label.Text = text
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 7
	label.Parent = shape

	root.Activated:Connect(onClick)
	UIChrome.Animate(theme, root, shape)
	return { root = root, shape = shape, label = label, stroke = stroke, shadow = shadow }
end

function StoreScreen:_BuildGPLayout()
	local theme = self:GetTheme()

	-- Classic / AC / GL leftovers must not leak into the pastel page: _OnShow
	-- restarts the ambient effects off these fields and _RefreshAffordability
	-- walks _priceButtons (which this branch answers by re-rendering instead).
	self._modal = nil
	self._rainbowGradient = nil
	self._burst = nil
	self._priceButtons = {}

	self._gpShadows = {}
	self._gpCards = {} :: { [string]: any }
	self._gpCardPool = {} :: { any }
	self._gpCounters = {} :: { [string]: any }
	-- LAYOUT-LOCAL cursor, exactly as the GL branch keeps one: the classic
	-- build's _categoryId is never written, so the exclusive-store showcase
	-- keeps its classic behaviour untouched.
	self._gpCategoryId = self._gpCategoryId or self._categoryId

	local page = GPLayoutKit.Page(theme, self.Root, {
		titleText = gpTitleCase(TextConfig.Resolve("store.title")),
		subtitleText = "Fresh off the wheel — today's shelf",
		sizePx = GP_PAGE,
		onClose = function()
			self.ScreenController:HideScreen("store")
		end,
	})
	for _, handle in page.shadows do
		table.insert(self._gpShadows, handle)
	end
	self._gpPage = page

	-- Currency counters in the ribbon's right slot: butter-gold pills with the
	-- currency glyph and INK numerals (butter is a light fill — the near-white
	-- TextOnPrimary would vanish on it).
	for i, currency in ShopConfig.GetOrderedCurrencies() do
		local pill = GPLayoutKit.PricePill(theme, page.topRight, self._gpShadows)
		pill.root.Name = "Counter_" .. currency.id
		pill.root.LayoutOrder = i
		-- currency.iconId is the ART; currency.icon is an EMOJI string.
		pill.icon.Image = currency.iconId or ""
		pill.amount.Text = ShopConfig.FormatPrice(self._balances[currency.id] or 0)
		self._gpCounters[currency.id] = pill
	end

	local tabs = GPLayoutKit.Tabs(theme, page.content, { widthPx = 168 }, self._gpShadows)
	self._gpTabs = tabs
	for _, category in ShopConfig.GetOrderedCategories() do
		local categoryId = category.id
		tabs.Add(TextConfig.Resolve(category.nameKey), categoryId, function()
			if self._gpCategoryId == categoryId then
				return
			end
			self._gpCategoryId = categoryId
			self:_GPRefresh()
		end)
	end

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Shelf"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, 60)
	scroll.Size = UDim2.new(1, 0, 1, -60)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = theme.Colors.Primary
	-- MUST clip: unclipped rows spilling past the frame is a known past bug
	-- here. The padding is what keeps a card's SOFT shadow off the clip edge,
	-- so a plate is never sliced flat on the boundary.
	scroll.ClipsDescendants = true
	local pad = Instance.new("UIPadding")
	pad.Name = "gpShelfPad"
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 18)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = scroll
	scroll.Parent = page.content
	self._gpScroll = scroll

	-- The classic build's decorative reward strip, kept (pack law 6: nothing a
	-- screen already shows is dropped for looking cleaner in pastel). Built
	-- once here; _GPRefresh only moves it below the last shelf row.
	local strip = UIStyler.Frame("Rewards")
	strip.BackgroundColor3 = theme.Colors.Background
	strip.BackgroundTransparency = 1
	strip.Size = UDim2.fromOffset(GP_FIELD_W, GP_TILE_H)
	strip.Parent = scroll
	self._gpRewardStrip = strip

	for i = 1, GP_REWARD_TILES do
		local fill = theme.Colors.Accent
		local tile = UIStyler.Frame("Reward" .. i)
		tile.BackgroundColor3 = fill
		tile.Position = UDim2.fromOffset((i - 1) * (GP_TILE_W + GP_GAP), 0)
		tile.Size = UDim2.fromOffset(GP_TILE_W, GP_TILE_H)
		tile.Parent = strip
		GPLayoutKit.Petal(theme, tile, i)
		GPLayoutKit.SoftStroke(theme, tile, fill)
		GPLayoutKit.Shadow(theme, tile, "sm", self._gpShadows, fill)

		-- Sentence case, verbatim: this pack never shouts (pack law 5).
		local label = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "Label")
		label.Text = "Reward"
		label.Position = UDim2.fromOffset(0, 10)
		label.Size = UDim2.new(1, 0, 0, 26)
		label.ZIndex = 3
		label.Parent = tile

		local icon = gpArt(theme, tile, "cash", 56)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 44)
		icon.ZIndex = 3
	end

	self:_GPRefresh()
end

-- One pooled GP card: the kit's petal plate plus the blurb, butter price
-- pill, glaze tag chip, shortfall line and buy CTA this shelf needs. Click
-- handlers read entry.item, so a pooled card never re-wires its connections.
function StoreScreen:_GPBuildCard(): any
	local theme = self:GetTheme()
	local entry: any = {}
	local card = GPLayoutKit.Card(theme, self._gpScroll, 0, self._gpShadows)
	entry.root = card.root
	entry.body = card.body
	entry.art = card.art
	entry.artLabel = card.artLabel
	entry.artImage = card.artImage
	entry.name = card.name
	entry.shadow = card.shadow

	-- The kit's card is art + name, so its name line is bottom-anchored. This
	-- shelf stacks name / blurb / price / state, so the anchor is reset once
	-- here and every position is written per form in _GPRefresh.
	entry.name.AnchorPoint = Vector2.new(0, 0)

	local desc = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Desc")
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.TextWrapped = true
	desc.ZIndex = 4
	desc.Parent = card.body
	entry.desc = desc

	entry.price = GPLayoutKit.PricePill(theme, card.body, self._gpShadows)
	entry.chip = gpChip(theme, card.body, 1)
	entry.chip.root.AnchorPoint = Vector2.new(1, 0)

	-- State IN WORDS, not in hue alone (doc §11.1): the pill tint says
	-- "payable", this line says exactly how short the purse is.
	local state = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "State")
	state.TextXAlignment = Enum.TextXAlignment.Left
	state.TextTruncate = Enum.TextTruncate.AtEnd
	state.ZIndex = 4
	state.Parent = card.body
	entry.state = state

	entry.cta = gpButton(
		theme,
		card.body,
		TextConfig.Resolve("shop.buy"),
		theme.Colors.Secondary,
		0,
		self._gpShadows,
		function()
			local item = entry.item
			if item then
				self:_PromptPurchase(item)
			end
		end
	)
	entry.cta.root.Visible = false

	card.root.Activated:Connect(function()
		local item = entry.item
		if item then
			self:_PromptPurchase(item)
		end
	end)
	return entry
end

-- Keyed pooled reconcile: the featured item takes the wide shelf plate, the
-- rest flow 3-up below it, and the reward strip follows the last row.
function StoreScreen:_GPRefresh()
	local scroll = self._gpScroll
	if not scroll then
		return -- built under another layout; the next Show rebuilds
	end
	local theme = self:GetTheme()

	local tabs = self._gpTabs
	if tabs then
		tabs.Select(self._gpCategoryId)
	end

	local items = ShopConfig.GetItemsForCategory(self._gpCategoryId)
	local seen = {}
	local cardW = math.floor((GP_FIELD_W - (GP_COLS - 1) * GP_GAP) / GP_COLS)
	local bottom = 0

	for i, item in items do
		seen[item.id] = true
		local entry = self._gpCards[item.id]
		if not entry then
			entry = table.remove(self._gpCardPool) or self:_GPBuildCard()
			entry.root.Visible = true
			entry.root.Parent = scroll
			entry.shadow:SetEnabled(true)
			entry.price.shadow:SetEnabled(true)
			self._gpCards[item.id] = entry
		end
		entry.item = item

		local hero = i == 1
		local currency = ShopConfig.Currencies[item.currencyType]
		local affordable = ShopConfig.CanAfford(self._balances, item)
		local balance = self._balances[item.currencyType] or 0
		local short = math.max(0, item.price - balance)

		-- PETAL PARITY IS POSITIONAL, not per-instance: a pooled card lands in
		-- a different slot each refresh, so the Petal/PetalMirror alternation
		-- is re-applied from the SLOT index (CornerSet replaces the stale
		-- corner, so this never leaves two UICorners fighting on one plate).
		GPLayoutKit.Petal(theme, entry.body, i)
		GPLayoutKit.Petal(theme, entry.art, i + 1)

		if hero then
			entry.root.Position = UDim2.fromOffset(0, 0)
			entry.root.Size = UDim2.fromOffset(GP_FIELD_W, GP_HERO_H)
			entry.art.Position = UDim2.fromOffset(14, 14)
			entry.art.Size = UDim2.new(0.3, 0, 1, -28)
			entry.artLabel.TextSize = theme.TextSizes.Body
			entry.name.TextSize = 32
			entry.name.Position = UDim2.new(0.33, 0, 0, 20)
			entry.name.Size = UDim2.new(0.44, 0, 0, 40)
			entry.desc.TextSize = theme.TextSizes.Body
			entry.desc.Position = UDim2.new(0.33, 0, 0, 64)
			entry.desc.Size = UDim2.new(0.44, 0, 0, 48)
			entry.price.root.Position = UDim2.new(0.33, 0, 1, -80)
			entry.price.root.Size = UDim2.fromOffset(186, 44)
			entry.price.amount.TextSize = 22
			entry.state.Position = UDim2.new(0.33, 0, 1, -32)
			entry.state.Size = UDim2.new(0.6, 0, 0, 22)
			entry.chip.root.Position = UDim2.new(1, -16, 0, 16)
			entry.chip.root.Size = UDim2.fromOffset(140, 30)
			entry.cta.root.Visible = true
			entry.cta.root.Position = UDim2.new(0.33, 200, 1, -82)
			entry.cta.root.Size = UDim2.fromOffset(196, 48)
			entry.cta.shadow:SetEnabled(true)
			bottom = math.max(bottom, GP_HERO_H)
		else
			entry.cta.root.Visible = false
			entry.cta.shadow:SetEnabled(false)
			local gi = i - 2 -- grid index below the featured plate
			local col = gi % GP_COLS
			local row = gi // GP_COLS
			local y = GP_HERO_H + GP_GAP + row * (GP_CARD_H + GP_GAP)
			entry.root.Position = UDim2.fromOffset(col * (cardW + GP_GAP), y)
			entry.root.Size = UDim2.fromOffset(cardW, GP_CARD_H)
			entry.art.Position = UDim2.fromOffset(10, 10)
			entry.art.Size = UDim2.new(1, -20, 0, 148)
			entry.artLabel.TextSize = theme.TextSizes.Small
			entry.name.TextSize = theme.TextSizes.Subtitle
			entry.name.Position = UDim2.fromOffset(14, 166)
			entry.name.Size = UDim2.new(1, -28, 0, 28)
			entry.desc.TextSize = theme.TextSizes.Small
			entry.desc.Position = UDim2.fromOffset(14, 196)
			entry.desc.Size = UDim2.new(1, -28, 0, 34)
			entry.price.root.Position = UDim2.fromOffset(14, 236)
			entry.price.root.Size = UDim2.fromOffset(150, 38)
			entry.price.amount.TextSize = theme.TextSizes.Button
			entry.state.Position = UDim2.fromOffset(14, 282)
			entry.state.Size = UDim2.new(1, -28, 0, 22)
			entry.chip.root.Position = UDim2.new(1, -12, 0, 14)
			entry.chip.root.Size = UDim2.fromOffset(112, 26)
			bottom = math.max(bottom, y + GP_CARD_H)
		end

		-- Real artwork from the ICON ARCHIVE; the art-slot placeholder only
		-- survives where nothing resolves for the item.
		GPLayoutKit.ApplyItemArt(entry, item)
		-- No string.upper anywhere in this branch (pack law 5); a name that
		-- arrives SHOUTED from an injected catalog is retitled for display, the
		-- same rule the GP shop page applies to the same config.
		entry.name.Text = gpTitleCase(TextConfig.Resolve(item.nameKey))
		entry.desc.Text = TextConfig.Resolve(item.descriptionKey)
		entry.price.icon.Image = (currency and currency.iconId) or ""
		entry.price.amount.Text = ShopConfig.FormatPrice(item.price)

		-- Butter while it is payable, the pack's quiet tint while it is not —
		-- and the SHADOW retints with the fill, because a disabled pill that
		-- kept casting amber would be exactly the grey-shadow bug inverted.
		local pillFill = if affordable then theme.Arcade.Gold else theme.Colors.Disabled
		entry.price.root.BackgroundColor3 = pillFill
		entry.price.shadow.Instance.Color = GPLayoutKit.Deepen(theme, pillFill, 1)

		local currencyName = if currency then TextConfig.Resolve(currency.nameKey) else item.currencyType
		if affordable then
			entry.state.Text = string.format("Ready — %s %s in the purse", ShopConfig.FormatPrice(balance), currencyName)
			entry.state.FontFace = theme.Fonts.Body
			entry.state.TextColor3 = theme.Colors.TextSecondary
		else
			-- WEIGHT carries the emphasis, not a coral fill: soft coral on
			-- these pastels does not clear 4.5:1 at 13px, and ink does.
			entry.state.Text = string.format("Need %s more %s", ShopConfig.FormatPrice(short), currencyName)
			entry.state.FontFace = theme.Fonts.Subtitle
			entry.state.TextColor3 = theme.Colors.TextPrimary
		end

		local tag = item.tags and item.tags[1]
		local chipText = if hero then "Featured" else tag
		if chipText then
			-- Butter on the featured plate (gold is this pack's value colour);
			-- everything else rides the glaze ramp by tag rank.
			local chipFill = if hero then theme.Colors.Accent else gpRampColor(theme, GP_TAG_RANK[tag or ""] or 1)
			entry.chip.root.Visible = true
			entry.chip.root.BackgroundColor3 = chipFill
			entry.chip.stroke.Color = GPLayoutKit.Deepen(theme, chipFill, 1)
			entry.chip.label.Text = chipText
		else
			entry.chip.root.Visible = false
		end

		entry.root.LayoutOrder = i
	end

	-- Release vanished cards to the pool: hidden, shadows DISABLED, never
	-- destroyed (the pooling law — a destroyed shadow still owes the budget).
	for id, entry in self._gpCards do
		if not seen[id] then
			entry.item = nil
			entry.root.Visible = false
			entry.shadow:SetEnabled(false)
			entry.price.shadow:SetEnabled(false)
			entry.cta.shadow:SetEnabled(false)
			table.insert(self._gpCardPool, entry)
			self._gpCards[id] = nil
		end
	end

	if self._gpRewardStrip then
		self._gpRewardStrip.Position = UDim2.fromOffset(0, bottom + 24)
	end

	for id, pill in self._gpCounters do
		pill.amount.Text = ShopConfig.FormatPrice(self._balances[id] or 0)
	end
end

return StoreScreen
