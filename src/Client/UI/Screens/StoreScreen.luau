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

local TextConfig = require(script.Parent.Parent.Config.TextConfig)
local UIAssets = require(script.Parent.Parent.Config.UIAssets)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UIScreenBase = require(script.Parent.UIScreenBase)
local ACLayoutKit = require(script.Parent.Parent.Framework.ACLayoutKit)

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
	if self:LayoutKit() == "AC" then
		self:_BuildACLayout()
		return
	end

	local theme = self:GetTheme()

	-- The §7.4 modal anatomy (dim → card → red header + close X → content).
	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = TextConfig.Resolve("shop.title"),
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

return StoreScreen
