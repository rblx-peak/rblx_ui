--!strict
-- Data-driven shop (Arcade family, doc §7.4): a fixed 1000×720 modal card with
-- currency pills in the header, blue category tabs, and an item grid/list from
-- ShopConfig + the active pack's layout. Cards are UICardComponents; the buy
-- flow raises a confirm modal, then calls the injected purchase function.
--
-- Layout (grid vs list, columns, card height) comes entirely from the active
-- UIPack, so switching packs re-lays-out the same data with no code change.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local SharedTypes = require(ReplicatedStorage.Shared.Types)

local Types = require(script.Parent.Parent.Types)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local IconVisibility = require(script.Parent.Parent.Icons.IconVisibility)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local TextConfig = require(script.Parent.Parent.Config.TextConfig)
local EntryLayoutConfig = require(script.Parent.Parent.Config.EntryLayoutConfig)
local CardSpacing = require(script.Parent.Parent.Config.CardSpacingConfig)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIPanelComponent = require(script.Parent.Parent.Components.UIPanelComponent)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UICardComponent = require(script.Parent.Parent.Components.UICardComponent)
local UIListRowComponent = require(script.Parent.Parent.Components.UIListRowComponent)
local UICurrencyPillComponent = require(script.Parent.Parent.Components.UICurrencyPillComponent)
local ACLayoutKit = require(script.Parent.Parent.Framework.ACLayoutKit)
local GLLayoutKit = require(script.Parent.Parent.Framework.GLLayoutKit)
local UITicker = require(script.Parent.Parent.Framework.UITicker)

local ShopScreen = setmetatable({}, { __index = UIScreenBase })
ShopScreen.__index = ShopScreen

function ShopScreen.new()
	local self = UIScreenBase.new("ShopScreen", 5)
	self._categoryId = "featured"
	self._balances = table.clone(ShopConfig.StartingBalances)
	-- Cards keyed by item id so re-renders can UPDATE existing cards instead of
	-- destroying/rebuilding the whole grid every time a balance or category
	-- changes (a full reload on every value tick is the kind of thing that would
	-- visibly flicker in a live game).
	self._cardsById = {} :: { [string]: any }
	self._cardOrder = {} :: { string }
	self._categoryButtons = {}
	self._currencyPills = {} :: { [string]: any }
	-- Injected by ClientHandler: (item) -> Types.PurchaseResult
	self._purchaseFn = nil :: ((SharedTypes.ShopItem) -> SharedTypes.PurchaseResult)?
	return setmetatable(self, ShopScreen)
end

function ShopScreen:SetPurchaseHandler(fn: (SharedTypes.ShopItem) -> SharedTypes.PurchaseResult)
	self._purchaseFn = fn
end

function ShopScreen:_BuildContent()
	-- GL layout language: comic diagonal composition (slanted banner header,
	-- trapezoid tabs, tilted cut-silhouette cards) — see _BuildGLLayout below.
	if self:LayoutKit() == "GL" then
		self:_BuildGLLayout()
		return
	end
	-- AC layout language: the whole screen is a bespoke terminal page (see
	-- _BuildACLayout below); the classic arcade modal build stays untouched.
	if self:LayoutKit() == "AC" then
		self:_BuildACLayout()
		return
	end

	-- The §7.4 modal card via UIPanelComponent: a FIXED 1000×720 px card at
	-- the 1650×1020 authoring baseline (UIScreenBase's UIScale handles device
	-- scaling — doc §7.1), so no AspectRatioConstraint is needed or wanted:
	-- the card IS its shape.
	local panel = UIPanelComponent.new()
	self._panel = panel
	self:_SetAnimatedPanel(panel)
	panel:Create(self.Root, {
		titleKey = "shop.title",
		size = UDim2.fromOffset(1000, 720),
		onClose = function()
			self.ScreenController:HideScreen("shop")
		end,
	})

	-- Currency pills in the 64px header (doc §7.4: title left, close X at the
	-- right end — the pills tuck in just left of the close, leaving both
	-- clear). Two small §8 currency pills; Update({balances}) refreshes them
	-- via _RefreshCurrencies.
	local currencyBar = UIStyler.Frame("Currencies")
	currencyBar.BackgroundTransparency = 1
	currencyBar.AnchorPoint = Vector2.new(1, 0.5)
	-- Close X is 48px wide anchored at (1, -8); end the pill row 12px left of it.
	currencyBar.Position = UDim2.new(1, -68, 0.5, 0)
	currencyBar.Size = UDim2.fromOffset(312, 44)
	currencyBar.ZIndex = 43
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 12),
	}).Parent = currencyBar
	currencyBar.Parent = panel.Header
	self._currencyPills = {}
	for i, currency in ShopConfig.GetOrderedCurrencies() do
		local pill = UICurrencyPillComponent.new()
		pill:Create(currencyBar, {
			currencyId = currency.id,
			value = self._balances[currency.id] or 0,
			size = UDim2.fromOffset(150, 44),
			layoutOrder = i,
		})
		self._currencyPills[currency.id] = pill
	end

	-- Category bar — blue arcade tabs (active = Blue, inactive = Ghost), a
	-- 44px row directly under the header inside the card's content frame.
	local categoryBar = UIStyler.Frame("Categories")
	categoryBar.BackgroundTransparency = 1
	categoryBar.Size = UDim2.new(1, 0, 0, 44)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
	}).Parent = categoryBar
	categoryBar.Parent = panel.Body
	self._categoryBar = categoryBar
	for i, category in ShopConfig.GetOrderedCategories() do
		local button = UIButtonComponent.new()
		button:Create(categoryBar, {
			-- Tabs shout, like every other display-font control; the config
			-- keeps its sentence-case source string for other surfaces.
			text = string.upper(TextConfig.Resolve(category.nameKey)),
			variant = category.id == self._categoryId and "Blue" or "Ghost",
			size = UDim2.fromOffset(180, 44),
			layoutOrder = i,
			onClick = function()
				self:_SelectCategory(category.id)
			end,
		})
		self._categoryButtons[category.id] = button
	end

	-- Scrolling item container — fills the content frame below the tab row.
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Items"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.new(1, 0, 1, -52)
	scroll.Position = UDim2.fromOffset(0, 52)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ClipsDescendants = true
	scroll.Parent = panel.Body
	self._scroll = scroll

	-- Inner padding so the first row/column and the last row don't touch the
	-- scroll edges (where the hover "pop" would otherwise clip), so the last row
	-- is never cut, and so the automatic canvas height includes a bottom margin.
	-- A SCALE fraction of the scroll's own size. PaddingTop is set per-render in
	-- _RebuildLayout (Grid vs List need different values — see its own comment);
	-- everything else here is fixed and only ever set once.
	local pad = Instance.new("UIPadding")
	pad.PaddingBottom = UDim.new(0, 0)
	pad.PaddingLeft = UDim.new(0.015, 0)
	pad.PaddingRight = UDim.new(0.011, 0)
	pad.Parent = scroll
	self._scrollPad = pad

	-- ServerRow footer (shown only for the ServerRow layout, hidden otherwise):
	-- an orange arcade Refresh button on the left + a gold FredokaOne countdown
	-- on the right, fixed at the card bottom. Built once here; _RebuildLayout
	-- toggles its visibility and shrinks the scroll to make room.
	local footer = UIStyler.Frame("Footer")
	footer.BackgroundTransparency = 1
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.new(0, 0, 1, 0)
	footer.Size = UDim2.new(1, 0, 0, 64)
	footer.Visible = false
	footer.ZIndex = 43
	footer.Parent = panel.Body
	self._footer = footer

	local refreshButton = UIButtonComponent.new()
	refreshButton:Create(footer, {
		text = "Refresh",
		variant = "Orange",
		size = UDim2.fromOffset(220, 52),
		position = UDim2.new(0, 0, 0.5, 0),
		anchorPoint = Vector2.new(0, 0.5),
		onClick = function()
			-- Every tap answers (doc §11.1): re-sync the rows in place.
			self:_SyncItems()
		end,
	})
	self._refreshButton = refreshButton

	-- Countdown surface (doc §11.3): gold FredokaOne, M:SS, ticking at 1Hz
	-- while the shop is open (driven from _OnShow). The 5-minute restock
	-- cycle is a placeholder value until real restock data feeds it.
	local timerLabel = UIChrome.Text("Timer", 28, self:GetTheme().Arcade.Gold)
	timerLabel.AnchorPoint = Vector2.new(1, 0.5)
	timerLabel.Position = UDim2.new(1, -10, 0.5, 0)
	timerLabel.Size = UDim2.fromOffset(260, 40)
	timerLabel.TextXAlignment = Enum.TextXAlignment.Right
	timerLabel.Text = "Timer: " .. UIChrome.FormatCountdown(0)
	timerLabel.ZIndex = 44
	timerLabel.Parent = footer
	self._timerLabel = timerLabel

	-- Re-render when the scroll frame's width first becomes known / changes, so the
	-- CardTop grid height (which is derived from the real cell width) is correct.
	-- Guarded by _lastScrollW so a no-op resize doesn't loop.
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local w = scroll.AbsoluteSize.X
		if w > 0 and math.abs(w - (self._lastScrollW or 0)) > 1 then
			self._lastScrollW = w
			self:_RebuildLayout()
		end
	end)

	self:_RebuildLayout()
end

function ShopScreen:_SelectCategory(categoryId: string)
	if categoryId == self._categoryId then
		return
	end
	self._categoryId = categoryId
	for id, button in self._categoryButtons do
		button.Props.variant = id == categoryId and "Blue" or "Ghost"
		button:ApplyTheme(self:GetTheme())
	end
	-- The category swaps which items show, so the grid/list geometry (a shape
	-- change) is recomputed; _RebuildLayout diffs cards, it does not destroy them.
	self:_RebuildLayout()
end

-- Compute the grid/list geometry for the active pack + spec (column layout,
-- per-arrangement card height, image pixel size), THEN sync cards into it. Call
-- this when the SHAPE changes (pack swap, category swap, scroll width first
-- known) — never on a plain data update like a balance tick.
function ShopScreen:_RebuildLayout()
	-- GL comic layout: shape changes re-render the tilted card set in place.
	if self:LayoutKit() == "GL" then
		self:_GLRefresh()
		return
	end
	-- AC terminal layout: there is no grid geometry to derive — a shape change
	-- just re-renders the dense rows (this keeps _OnShow/_SelectCategory
	-- working unchanged in both layouts).
	if self:LayoutKit() == "AC" then
		self:_ACRefreshList()
		return
	end

	-- Clear any previous layout object (UIGridLayout/UIListLayout), but leave
	-- existing card Instances alone — _SyncItems reuses or destroys them by id.
	for _, child in self._scroll:GetChildren() do
		if child:IsA("UIGridLayout") or child:IsA("UIListLayout") then
			child:Destroy()
		end
	end

	local pack = self.ThemeController:GetPack()
	local shopLayout = pack.Shop
	local spec = EntryLayoutConfig.Get(shopLayout.EntryLayout)
	self._activeSpec = spec
	self._activeShopLayout = shopLayout

	-- The ServerRow layout gets the footer (Refresh + countdown) and a shorter
	-- scroll to make room; every other layout hides it and takes the full
	-- height below the 44px tab row (+8px gap).
	local boxy = shopLayout.EntryLayout == "ServerRow"
	self._footer.Visible = boxy
	self._scroll.Size = boxy and UDim2.new(1, 0, 1, -124) or UDim2.new(1, 0, 1, -52)

	-- Grid keeps the original -0.02 (a small negative pull that tightens the
	-- top row against the category bar — fine there since a grid cell has
	-- enough of its own top margin that nothing actually goes unreachable).
	-- List/Row layouts get 0 instead: their rows are short enough that the
	-- same -0.02 fraction pushes a whole row above the frame's visible top,
	-- into canvas space a ScrollingFrame can never scroll UP into (confirmed
	-- as the cause of the first row(s) going missing on Compact/Menu etc.).
	self._scrollPad.PaddingTop = shopLayout.Container == "Grid" and UDim.new(-0.02, 0) or UDim.new(0.001, 0)

	if shopLayout.Container == "Grid" and (spec.arrangement == "CardTop" or spec.arrangement == "Overlay") then
		-- Pure-Scale path (matches the reference MainGui pattern): the card now
		-- keeps its OWN fixed width:height ratio via a UIAspectRatioConstraint on
		-- the card itself (see UICardComponent._Build), with AspectType
		-- FitWithinMaxSize — so the grid CELL just needs to be a big-enough Scale
		-- box, and the card centres itself inside it at the correct shape. No
		-- pixel measurement, no per-pass height computation, no ShopScreen/
		-- CardSpacingConfig cross-referencing needed for either arrangement.
		self._cardImageSizePx = nil
		-- Pure Scale cell size — hand-tuned to look right in Studio (see
		-- CardSpacingConfig.GridCell for the editable values) instead of
		-- computed from column count + a pixel gap. Overlay gets its OWN
		-- (shorter) CellSizeY — its card is just the image, much shorter than
		-- a CardTop card at the same width (see GridCellOverlay's doc).
		local cellSizeY = spec.arrangement == "Overlay" and CardSpacing.GridCellOverlay.CellSizeY or CardSpacing.GridCell.CellSizeY

		-- Standard's own spec (StandardCard) is locked to the exact flat -0.06
		-- (CardSpacing.GridCell.CellPaddingY) — that value must never drift for
		-- THIS pack specifically, by explicit request. Every other CardTop/
		-- Overlay spec gets a COMPUTED value instead: a flat number only ever
		-- matches ONE card shape's real slack (the gap between the cell's
		-- nominal height and the card's real FitWithinMaxSize-fitted height) —
		-- reusing Standard's -0.06 on a spec with a taller/shorter card left a
		-- real visible gap between rows (confirmed: this is what the "too much
		-- space vertically on the grid" screenshot was showing, on packs other
		-- than Standard, right after -0.06 got hardcoded for every CardTop
		-- spec). Mirroring FitWithinMaxSize's own math (candidate height from
		-- full cell width, clamped to the cell height) gives each spec's exact
		-- slack instead, so every OTHER pack is tight with zero overlap again.
		local cellPaddingY
		if shopLayout.EntryLayout == "StandardCard" then
			cellPaddingY = CardSpacing.GridCell.CellPaddingY
		else
			local cellWAbs = CardSpacing.GridCell.CellSizeX * self._scroll.AbsoluteSize.X
			local cellHAbs = cellSizeY * self._scroll.AbsoluteSize.Y
			local cardAspect = spec.arrangement == "Overlay"
				and (spec.imageAspect and spec.imageAspect > 0 and spec.imageAspect or 1)
				or CardSpacing.CardTop.AspectRatioForSpec(spec)
			local candidateH = cardAspect > 0 and (cellWAbs / cardAspect) or cellHAbs
			local fittedH = math.min(candidateH, cellHAbs)
			cellPaddingY = self._scroll.AbsoluteSize.Y > 0 and ((fittedH - cellHAbs) / self._scroll.AbsoluteSize.Y) or 0
		end

		local cell = UIStyler.GridLayout(
			UDim2.fromScale(CardSpacing.GridCell.CellSizeX, cellSizeY),
			UDim2.fromScale(CardSpacing.GridCell.CellPaddingX, cellPaddingY)
		)
		cell.Parent = self._scroll
	elseif shopLayout.Container == "Grid" then
		local cols = shopLayout.Columns
		local cellPad = 10
		local cardHeight = shopLayout.CardHeight
		-- For legacy Overlay specs (image-on-top), the image FILLS the card width
		-- and holds its aspect, so the card must be exactly tall enough for that
		-- image + the text block — no fixed height, no empty side space. We compute
		-- the real pixel cell width to derive that height. Other grid arrangements
		-- (Split) keep their configured CardHeight.
		if spec.arrangement == "Overlay" then
			local scrollW = self._scroll.AbsoluteSize.X
			if scrollW <= 0 then
				scrollW = 700 -- pre-measure fallback; corrected on the next render
			end
			local cellW = (scrollW - cellPad * (cols - 1)) / cols
			local aspect = spec.imageAspect
			if not aspect or aspect <= 0 then
				aspect = 1
			end
			if spec.arrangement == "Overlay" then
				-- The image IS the whole card (text is overlaid), so the card is just
				-- the square — very compact, so many tiles fit on screen at once.
				self._cardImageSizePx = math.floor(cellW)
				cardHeight = math.floor(cellW / aspect)
			else
				-- CardTop: square (or spec aspect) image over a text strip below.
				-- Exact height of everything below the image — built from the SAME
				-- CardSpacingConfig values UICardComponent._BuildCardTop reads, term
				-- for term, so this can never silently drift out of sync with the
				-- renderer again (a real bug class hit repeatedly before this config
				-- existed). Each `+ CardSpacing.Gap.X` below is one explicit spacer
				-- frame the renderer inserts; tune spacing by editing the config, not
				-- by hunting for matching magic numbers in two files.
				local H, G = CardSpacing.Height, CardSpacing.Gap
				local surfacePad = CardSpacing.SurfacePadding * 2
				-- tagStraddle puts the badges ON the image (a sibling of it, not a row
				-- in the text column below) — so it never occupies text-column height,
				-- same as if showTags were false for THIS purpose.
				local tagsInColumn = spec.showTags and not spec.tagStraddle
				local external = spec.buyStyle == "OutsideBelow" or spec.buyStyle == "Straddle"
				local textBlock
				if external then
					-- The buy button lives OUTSIDE the surface entirely (see
					-- UICardComponent._BuildExternalBuy) — the internal column ends
					-- with a small 4px pad instead of a buy row, and the reserved
					-- space for the external button is added on top, outside the
					-- surface's own content height. Reserve is half the external buy
					-- height for Straddle, or buttonH+gap for OutsideBelow (both
					-- computed in UICardComponent._Build/_BuildExternalBuy).
					local EB = CardSpacing.ExternalBuy
					local tagsBlock = tagsInColumn and (G.ImageToTags + H.TagRow + G.TagsToName) or G.ImageToName
					local reserve = spec.buyStyle == "Straddle" and math.floor(EB.Height / 2) or (EB.Height + EB.BelowGap)
					textBlock = surfacePad + tagsBlock + H.Name + G.NameToPrice + H.Price + EB.BottomPad + reserve
				elseif spec.priceWithTags then
					-- Standard 2.0: image, name, [tags+price on one row], buy.
					-- No separate tags/price rows.
					local buyH = spec.buyStyle == "Pill" and H.BuyPill or H.BuyFull
					local buyGap = spec.buyStyle == "Pill" and G.BuyToPill or G.PriceToBuy
					textBlock = surfacePad + G.ImageToName + H.Name + G.NameToPrice + H.TagPriceRow + buyGap + buyH
				elseif spec.overlayBadgeAndPrice then
					-- Standard 2.0: badges + price both overlay the image itself, so
					-- the text column below is just Name + Buy — no tags/price rows.
					local buyH = spec.buyStyle == "Pill" and H.BuyPill or H.BuyFull
					local buyGap = spec.buyStyle == "Pill" and G.BuyToPill or G.PriceToBuy
					textBlock = surfacePad + G.ImageToName + H.Name + buyGap + buyH
				else
					local tagsBlock = tagsInColumn and (G.ImageToTags + H.TagRow + G.TagsToName) or G.ImageToName
					local buyH = spec.buyStyle == "Pill" and H.BuyPill or H.BuyFull
					local buyGap = spec.buyStyle == "Pill" and G.BuyToPill or G.PriceToBuy
					textBlock = surfacePad + tagsBlock + H.Name + G.NameToPrice + H.Price + buyGap + buyH
				end
				if spec.imageFillWidth then
					-- Image fills the card content width edge-to-edge (no side margin).
					-- The card is exactly as tall as image + text needs — no target-ratio
					-- clamp, so it can end up a bit long, and that's the intended look.
					local imgW = cellW - 20
					local imgH = imgW / aspect
					self._cardImageSizePx = math.floor(imgW)
					cardHeight = math.floor(imgH + textBlock)
				else
					-- Compact look: the card targets a pleasant ~1:1.2 ratio and the
					-- image gets the leftover height as a CENTRED square/rect. On wide
					-- cards the box is a touch narrower than the card (small even
					-- margins, never a lonely edge); it never produces a lanky 1:2 card.
					local targetCardH = cellW * 1.2
					local imgH = math.clamp(targetCardH - textBlock, cellW * 0.62, cellW - 12)
					self._cardImageSizePx = math.floor(imgH * aspect)
					cardHeight = math.floor(imgH + textBlock)
				end
			end
		elseif spec.arrangement == "Split" or spec.arrangement == "Banner" then
			-- Split/Banner: the image just fills whatever height it's given, but the
			-- TEXT column's own stacked content (name/tags/desc/price/buy) is what
			-- actually determines how tall the card needs to be. A mismatched fixed
			-- CardHeight here is exactly what left dead space below the Buy button
			-- while the image side filled edge-to-edge — computed to match the
			-- renderer exactly (_BuildSplit) so there's never a gap either way.
			self._cardImageSizePx = nil
			local rows = 2 -- name (wrap-capable) + buy always present
			local rowsH = 30 + 30
			if spec.showTags then
				rows += 1
				rowsH += 15
			end
			if spec.showDescription then
				rows += 1
				rowsH += 44
			end
			rows += 2 -- price + spacer, always present
			rowsH += 17 + 2
			local gaps = (rows - 1) * 6
			cardHeight = math.floor(20 + rowsH + gaps) -- 20 = surface top+bottom padding
		else
			self._cardImageSizePx = nil
		end
		local cell = UIStyler.GridLayout(
			UDim2.new(1 / cols, -cellPad, 0, cardHeight),
			UDim2.fromOffset(cellPad, cellPad)
		)
		cell.Parent = self._scroll
	else
		self._cardImageSizePx = nil
		UIStyler.ListLayout({ Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Center }).Parent = self._scroll
	end

	-- The layout shape (spec/columns) determines each card's Create-time props
	-- (spec, size, imageSizePx), so a shape change destroys and rebuilds every
	-- card — but a plain data change (balances, category re-select with the same
	-- items) never reaches this function and just calls _SyncItems below.
	for _, card in self._cardsById do
		card:Destroy()
	end
	table.clear(self._cardsById)
	table.clear(self._cardOrder)

	self:_SyncItems()
end

-- Reconcile self._cardsById against the current category's items: create cards
-- for new ids, destroy cards for ids no longer present, and UPDATE existing
-- cards' affordability/owned in place. This is what lets a balance change or a
-- purchase refresh the shop WITHOUT tearing down and rebuilding every entry —
-- the full-reload-on-every-tick pattern is bad in any live game.
function ShopScreen:_SyncItems()
	-- GL comic layout: keyed pooled reconcile lives in _GLRefresh.
	if self:LayoutKit() == "GL" then
		self:_GLRefresh()
		return
	end
	-- AC terminal layout: 26px mono rows are cheap enough that a wholesale
	-- re-render IS the sync (this keeps Update/_DoPurchase working unchanged).
	if self:LayoutKit() == "AC" then
		self:_ACRefreshList()
		return
	end

	local shopLayout = self._activeShopLayout
	local spec = self._activeSpec
	if not shopLayout or not spec then
		return
	end

	local items = ShopConfig.GetItemsForCategory(self._categoryId)
	local seen = {}

	for i, item in items do
		seen[item.id] = true
		local currency = ShopConfig.Currencies[item.currencyType]
		local affordable = ShopConfig.CanAfford(self._balances, item)
		local existing = self._cardsById[item.id]
		if existing then
			-- Same item, same layout shape: just patch the parts that can change.
			existing:Update({ affordable = affordable })
			existing.Root.LayoutOrder = i
		else
			-- The boxy nested-box list row (ServerRow spec) uses its own
			-- self-contained renderer; every other spec uses the grid/list card
			-- renderer. Both expose .Root, :Create, :Update, :PlayAnimation and
			-- :Destroy, so the rest of the sync loop treats them identically.
			local useRow = shopLayout.EntryLayout == "ServerRow"
			local card = useRow and UIListRowComponent.new() or UICardComponent.new()
			-- List rows get an explicit full-width size; grid cells are sized by the
			-- grid layout, so leave size nil there.
			local size = shopLayout.Container == "List" and UDim2.new(1, 0, 0, shopLayout.CardHeight) or nil
			card:Create(self._scroll, {
				item = item,
				spec = spec,
				currencyIcon = currency and currency.icon or "",
				affordable = affordable,
				layoutOrder = i,
				size = size,
				-- Exact image pixel width so a CardTop image fills the card with no gap.
				imageSizePx = self._cardImageSizePx,
				onBuy = function(boughtItem)
					self:_PromptPurchase(boughtItem)
				end,
			})
			card:PlayAnimation("Appear")
			self._cardsById[item.id] = card
		end
	end

	-- Drop cards for items that vanished (category filter changed the set, or an
	-- item was removed from config at runtime).
	for id, card in self._cardsById do
		if not seen[id] then
			card:Destroy()
			self._cardsById[id] = nil
		end
	end

	self:_RefreshCurrencies()
end

-- Raise a confirm modal; on confirm, run the injected purchase and toast.
-- A tap on an unaffordable (dimmed) buy has already played its press juice —
-- answer it with the REASON instead of the confirm modal (every tap answers,
-- doc §11.1). Mirrors StoreScreen's gate key-for-key.
function ShopScreen:_PromptPurchase(item: SharedTypes.ShopItem)
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

function ShopScreen:_DoPurchase(item: SharedTypes.ShopItem)
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
	-- A purchase only changes affordability/owned, never the layout shape, so
	-- sync cards in place rather than rebuilding the whole grid.
	self:_SyncItems()
end

function ShopScreen:_RefreshCurrencies()
	-- Push balances into the header pills; the pill formats via
	-- ShopConfig.FormatPrice and pulses only when a value actually changes.
	for id, pill in self._currencyPills do
		pill:SetValue(self._balances[id] or 0)
	end
end

-- Countdown surfaces tick at 1Hz only while their panel is open (doc §11.3 /
-- §5.4). Token-guarded so re-opens never stack multiple tickers; the deadline
-- persists across open/close within one restock cycle and re-arms on expiry.
local FOOTER_RESTOCK_SECONDS = 300

function ShopScreen:_StartFooterTimer()
	local token = {}
	self._footerToken = token
	task.spawn(function()
		while self._footerToken == token and self._visible do
			if not self._footerDeadline or self._footerDeadline <= os.clock() then
				self._footerDeadline = os.clock() + FOOTER_RESTOCK_SECONDS
			end
			if self._timerLabel then
				local remaining = math.max(0, math.floor(self._footerDeadline - os.clock()))
				self._timerLabel.Text = "Timer: " .. UIChrome.FormatCountdown(remaining)
			end
			task.wait(1)
		end
	end)
end

function ShopScreen:_OnHide()
	-- Stop the 1Hz footer ticker the moment the panel closes.
	self._footerToken = nil
end

-- A style rebuild destroys the Gui, but UIShadow BUDGET counts live in
-- StyleKit.Capabilities and only fall when a handle is released — so the GL
-- layout hands every shadow back here, plus its click connections.
function ShopScreen:_OnTeardown()
	self._footerToken = nil
	-- The one ambient handler (sunburst rotation) dies with the layout.
	if self._glRayStop then
		self._glRayStop()
		self._glRayStop = nil
	end
	if self._glShadows then
		for _, handle in self._glShadows do
			handle:Release()
		end
		table.clear(self._glShadows)
	end
	if self._glCards then
		for _, entry in self._glCards do
			if entry.clickConn then
				entry.clickConn:Disconnect()
				entry.clickConn = nil
			end
		end
		table.clear(self._glCards)
	end
	if self._glCardPool then
		table.clear(self._glCardPool)
	end
	self._glTabs = nil
	self._glPanel = nil
	self._scroll = nil
end

function ShopScreen:_OnShow(data: any?)
	if data and data.balances then
		self._balances = data.balances
	end
	if data and data.categoryId and data.categoryId ~= self._categoryId then
		self._categoryId = data.categoryId
		-- Category changed while hidden: the item set (shape) changed too.
		self:_RebuildLayout()
	else
		-- Re-opening the shop: the pack could have changed while it was hidden
		-- (e.g. the Theme Editor's pack picker), so re-derive the layout shape.
		-- Cheap and infrequent (screen open), unlike a per-tick balance update.
		self:_RebuildLayout()
	end
	-- 1Hz footer countdown while the panel is open (visible only in the
	-- ServerRow layout; ticking a hidden label is harmless and cheap).
	self:_StartFooterTimer()
	-- Intro is driven centrally by UIScreenBase:Show (active animation pack).
end

function ShopScreen:Update(data: any)
	if data.balances then
		self._balances = data.balances
		-- Balances can arrive (currency pushes, boot snapshot) before the shop
		-- has ever been opened/built; just cache them until first show. Once
		-- built, this is a pure data change — sync cards in place, never rebuild.
		if self._built then
			self:_SyncItems()
		end
	end
end

-- ======================================================================
-- AC layout (theme.LayoutKit == "AC") — the dense terminal data list.
-- Full-bleed Shell page: mono currency readouts in the top-right slot, a
-- left category rail (same _SelectCategory flow as the tabs), a centre
-- column of hairline item rows, and a bracketed detail pane whose PURCHASE
-- action runs the exact classic buy gate (_PromptPurchase → confirm modal
-- → injected purchase fn). Rows are 26px frames — rebuilding them wholesale
-- on every sync is the simplest correct diff at this density.
-- ======================================================================

function ShopScreen:_BuildACLayout()
	local theme = self:GetTheme()
	local shell = ACLayoutKit.Shell(theme, self.Root, self:_R("shop.title"))
	ACLayoutKit.SetHints(shell, {
		{ key = "CLICK", action = "SELECT" },
		{ key = "ESC", action = "CLOSE" },
	})

	-- Classic-build leftovers must not leak into the terminal page: stale
	-- cards release their tweens/connections (same as _RebuildLayout does),
	-- the tab buttons died with the old Gui, and the footer timer label is
	-- gone (_StartFooterTimer nil-guards it, so the 1Hz ticker stays harmless).
	for _, card in self._cardsById do
		card:Destroy()
	end
	table.clear(self._cardsById)
	table.clear(self._cardOrder)
	self._categoryButtons = {}
	self._timerLabel = nil
	self._panel = nil

	-- Top-right currency readouts: dense mono text in the semantic currency
	-- colour — the honest AC equivalent of the arcade pills. Each wrapper
	-- answers :SetValue, so _RefreshCurrencies works unchanged in both layouts.
	self._currencyPills = {}
	for i, currency in ShopConfig.GetOrderedCurrencies() do
		local label = UIChrome.BodyText("Currency" .. currency.id, 13, UIChrome.CurrencyColor(theme, currency.id))
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = UDim2.new(0, 0, 1, 0)
		label.LayoutOrder = i
		label.Parent = shell.topRight
		local prefix = string.upper(self:_R(currency.nameKey)) .. " "
		local readout = {
			SetValue = function(_: any, n: number)
				label.Text = prefix .. ShopConfig.FormatPrice(n)
			end,
		}
		readout:SetValue(self._balances[currency.id] or 0)
		self._currencyPills[currency.id] = readout
	end

	-- Left rail: the same shop categories, the same selection flow.
	local rail = ACLayoutKit.Rail(theme, shell.content, 200)
	local categories = ShopConfig.GetOrderedCategories()
	for _, category in categories do
		rail.AddEntry(self:_R(category.nameKey), function()
			self:_SelectCategory(category.id)
		end)
	end
	self._acRail = rail
	self._acCategories = categories

	-- Centre: dim caption row over the dense scrolling item rows.
	local listPane = UIStyler.Frame("ItemList")
	listPane.BackgroundTransparency = 1
	listPane.Position = UDim2.fromOffset(216, 0)
	listPane.Size = UDim2.new(1, -532, 1, 0)
	listPane.Parent = shell.content

	ACLayoutKit.ListRow(theme, listPane, {
		{ text = "NAME", widthScale = 0.55, dim = true },
		{ text = "PRICE", widthScale = 0.3, align = Enum.TextXAlignment.Right, dim = true },
		{ text = "STATE", widthScale = 0.15, align = Enum.TextXAlignment.Right, dim = true },
	}, { heightPx = 20 })

	local list = Instance.new("ScrollingFrame")
	list.Name = "Rows"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(0, 24)
	list.Size = UDim2.new(1, 0, 1, -24)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = 4
	list.ScrollBarImageColor3 = theme.Colors.Accent
	list.Parent = listPane
	UIStyler.ListLayout({
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 0),
	}).Parent = list
	self._acList = list
	self._acRows = {} :: { GuiObject }

	-- Right: the bracketed hairline detail pane. Selecting a row fills it.
	local detail = UIStyler.Frame("Detail")
	detail.BackgroundColor3 = theme.Colors.Surface
	detail.BackgroundTransparency = 0.25
	detail.AnchorPoint = Vector2.new(1, 0)
	detail.Position = UDim2.new(1, 0, 0, 0)
	detail.Size = UDim2.new(0, 300, 1, 0)
	detail.Parent = shell.content
	UIStyler.Stroke(theme.Colors.Accent, 1, 0.5).Parent = detail
	ACLayoutKit.Brackets(theme, detail)

	local inner = UIStyler.Frame("Inner")
	inner.BackgroundTransparency = 1
	inner.Parent = detail
	UIStyler.Padding(14).Parent = inner
	UIStyler.ListLayout({
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 8),
	}).Parent = inner

	local name = UIChrome.BodyText("Name", 14, theme.Colors.TextPrimary)
	name.Size = UDim2.new(1, 0, 0, 20)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.LayoutOrder = 1
	name.Parent = inner

	local rule = ACLayoutKit.Rule(theme, inner)
	rule.LayoutOrder = 2

	local tags = UIChrome.BodyText("Tags", 10, theme.Colors.TextSecondary)
	tags.Size = UDim2.new(1, 0, 0, 14)
	tags.TextXAlignment = Enum.TextXAlignment.Left
	tags.LayoutOrder = 3
	tags.Parent = inner

	local desc = UIChrome.BodyText("Desc", 11, theme.Colors.TextSecondary)
	desc.Size = UDim2.new(1, 0, 0, 0)
	desc.AutomaticSize = Enum.AutomaticSize.Y
	desc.TextWrapped = true
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.LayoutOrder = 4
	desc.Parent = inner

	local price = UIChrome.BodyText("Price", 13, theme.Colors.TextPrimary)
	price.Size = UDim2.new(1, 0, 0, 18)
	price.TextXAlignment = Enum.TextXAlignment.Left
	price.LayoutOrder = 5
	price.Parent = inner

	-- PURCHASE pinned to the pane's bottom edge — the same buy gate the
	-- classic card click runs (unaffordable taps toast the reason, affordable
	-- ones raise the confirm modal, then the injected purchase fn).
	local buy = ACLayoutKit.ActionButton(theme, detail, "PURCHASE", function()
		local item = self._acSelectedItem :: SharedTypes.ShopItem?
		if item then
			self:_PromptPurchase(item)
		end
	end)
	buy.AnchorPoint = Vector2.new(0.5, 1)
	buy.Position = UDim2.new(0.5, 0, 1, -14)
	buy.Size = UDim2.new(1, -28, 0, 30)

	self._acDetailName = name
	self._acDetailTags = tags
	self._acDetailDesc = desc
	self._acDetailPrice = price
	self._acSelectedItem = nil

	self:_ACRefreshList()
end

-- Re-render the dense rows for the current category + balances, restore the
-- rail highlight and selection, and refill the detail pane. This is the AC
-- answer to BOTH _RebuildLayout (shape) and _SyncItems (data) — see the
-- dispatches at the top of those functions.
function ShopScreen:_ACRefreshList()
	local list = self._acList :: ScrollingFrame?
	if not list then
		-- Built under the classic layout (theme swapped while hidden): the
		-- rebuild on next Show constructs the AC page; just cache data now.
		return
	end
	local theme = self:GetTheme()

	-- The rail highlight follows _categoryId (it can change via _OnShow data).
	local rail = self._acRail :: ACLayoutKit.Rail
	local categories = self._acCategories :: { SharedTypes.ShopCategory }
	for i, category in categories do
		if category.id == self._categoryId then
			rail.Select(i)
			break
		end
	end

	local rows = self._acRows :: { GuiObject }
	for _, row in rows do
		row:Destroy()
	end
	table.clear(rows)

	local items = ShopConfig.GetItemsForCategory(self._categoryId)
	local selected: SharedTypes.ShopItem? = nil
	for _, item in items do
		if item.id == self._acSelectedId then
			selected = item
			break
		end
	end
	if not selected then
		selected = items[1]
	end
	local selectedId = if selected then selected.id else nil
	self._acSelectedId = selectedId

	for i, item in items do
		local currency = ShopConfig.Currencies[item.currencyType]
		local currencyName = string.upper(currency and self:_R(currency.nameKey) or item.currencyType)
		local affordable = ShopConfig.CanAfford(self._balances, item)
		local isSelected = item.id == selectedId
		local row = ACLayoutKit.ListRow(theme, list, {
			{
				text = string.upper(self:_R(item.nameKey)),
				widthScale = 0.55,
				color = isSelected and theme.Colors.Accent or theme.Colors.TextPrimary,
			},
			{
				text = ShopConfig.FormatPrice(item.price) .. " " .. currencyName,
				widthScale = 0.3,
				align = Enum.TextXAlignment.Right,
				color = UIChrome.CurrencyColor(theme, item.currencyType),
			},
			-- The shop has no ownership data (see SharedTypes.ShopItem), so the
			-- state column reports the one state it DOES have: affordability.
			{ text = affordable and "" or "LOW FUNDS", widthScale = 0.15, align = Enum.TextXAlignment.Right, dim = true },
		}, { heightPx = 26, layoutOrder = i, clickable = true })
		if isSelected then
			-- Selected row: faint raised fill (ListRow's SurfaceRaised base).
			row.BackgroundTransparency = 0.85
		end
		local button = row :: TextButton
		button.Activated:Connect(function()
			self._acSelectedId = item.id
			self:_ACRefreshList()
		end)
		table.insert(rows, row)
	end

	self:_ACFillDetail(selected)
	self:_RefreshCurrencies()
end

function ShopScreen:_ACFillDetail(item: SharedTypes.ShopItem?)
	self._acSelectedItem = item
	local name = self._acDetailName :: TextLabel?
	if not name then
		return
	end
	local tags = self._acDetailTags :: TextLabel
	local desc = self._acDetailDesc :: TextLabel
	local price = self._acDetailPrice :: TextLabel
	if not item then
		name.Text = "—"
		tags.Text = ""
		desc.Text = ""
		price.Text = ""
		return
	end
	local theme = self:GetTheme()
	name.Text = string.upper(self:_R(item.nameKey))
	local itemTags = item.tags
	if itemTags and #itemTags > 0 then
		local parts = {}
		for _, tag in itemTags do
			table.insert(parts, string.upper(tag))
		end
		tags.Text = table.concat(parts, " / ")
	else
		tags.Text = "—"
	end
	desc.Text = self:_R(item.descriptionKey)
	local currency = ShopConfig.Currencies[item.currencyType]
	price.Text = ShopConfig.FormatPrice(item.price) .. " " .. string.upper(currency and self:_R(currency.nameKey) or item.currencyType)
	price.TextColor3 = UIChrome.CurrencyColor(theme, item.currencyType)
end

-- ======================================================================
-- GL layout (theme.LayoutKit == "GL") — the comic diagonal shop, iteration 2.
-- Value structure per the reference: a LIGHT PAPER content field inside DARK
-- chrome, a dense portrait rarity-tile grid, and character art breaking the
-- panel's left/top edges. Composed entirely from GLLayoutKit so every other
-- screen inherits the same proven atoms.
--
-- Presentation only: same ShopConfig data, same _SelectCategory /
-- _PromptPurchase / _DoPurchase / Update flow as the classic branch.
-- ======================================================================

function ShopScreen:_BuildGLLayout()
	local theme = self:GetTheme()
	self._glShadows = {}
	self._glTiles = {} :: { [string]: any }
	self._glTilePool = {} :: { any }

	-- Classic/AC leftovers must not leak.
	for _, card in self._cardsById do
		card:Destroy()
	end
	table.clear(self._cardsById)
	table.clear(self._cardOrder)
	self._categoryButtons = {}
	self._timerLabel = nil
	self._panel = nil

	-- Two-tone header: first word huge on gold, the rest cream on the red
	-- slash (the reference's "CRAZY | HUNDRED DRAWS" collision).
	local titleRaw = string.upper(self:_R("shop.title"))
	local first, rest = string.match(titleRaw, "^(%S+)%s+(.+)$")
	local titleText = first and (first .. " | " .. rest) or titleRaw

	local page = GLLayoutKit.Page(theme, self.Root, {
		titleText = titleText,
		subtitleText = nil, -- no shop.subtitle key exists; TextConfig would echo the key
		sizePx = Vector2.new(1180, 648),
		onClose = function()
			self.ScreenController:HideScreen("shop")
		end,
	})
	self._glPage = page

	-- Currency counters: angular dark chips with gold numerals + a "+" chip.
	self._currencyPills = {}
	for i, currency in ShopConfig.GetOrderedCurrencies() do
		local chip = GLLayoutKit.Slice(theme, "chipPaper", theme.Arcade.NearBlack, "Cur" .. currency.id)
		chip.Size = UDim2.fromOffset(148, 42)
		chip.Rotation = GLLayoutKit.TILT
		chip.LayoutOrder = i
		chip.ZIndex = 6
		chip.Parent = page.topRight
		GLLayoutKit.Shadow(theme, chip, "sm", self._glShadows)
		local icon = Instance.new("ImageLabel")
		icon.Name = "Glyph"
		icon.BackgroundTransparency = 1
		icon.Image = currency.iconId or ""
		icon.Size = UDim2.fromOffset(26, 26)
		icon.Position = UDim2.fromOffset(8, 8)
		icon.ZIndex = 7
		icon.Parent = chip
		IconVisibility.Register(icon)
		local value = GLLayoutKit.Text(theme, 22, theme.Arcade.Gold, "Value")
		value.TextXAlignment = Enum.TextXAlignment.Right
		value.Position = UDim2.fromOffset(36, 0)
		value.Size = UDim2.new(1, -46, 1, 0)
		value.ZIndex = 7
		value.Parent = chip
		local readout = {
			SetValue = function(_: any, n: number)
				value.Text = ShopConfig.FormatPrice(n)
			end,
		}
		readout:SetValue(self._balances[currency.id] or 0)
		self._currencyPills[currency.id] = readout
	end
	do
		local plus = GLLayoutKit.Slice(theme, "chipPaper", theme.Colors.Primary, "AddCurrency")
		plus.Size = UDim2.fromOffset(42, 42)
		plus.Rotation = GLLayoutKit.TILT
		plus.LayoutOrder = 99
		plus.ZIndex = 6
		plus.Parent = page.topRight
		GLLayoutKit.Shadow(theme, plus, "sm", self._glShadows)
		local glyph = GLLayoutKit.Text(theme, 30, theme.Colors.TextPrimary, "Plus")
		glyph.Text = "+"
		glyph.Size = UDim2.fromScale(1, 1)
		glyph.ZIndex = 7
		glyph.Parent = plus
	end

	-- Tabs sit on the DARK chrome, above the paper field.
	local tabs = GLLayoutKit.Tabs(theme, page.panel, { widthPx = 176 })
	tabs.frame.Position = UDim2.fromOffset(360, 62)
	tabs.frame.Size = UDim2.new(0, 580, 0, 48)
	tabs.frame.ZIndex = 10
	for _, category in ShopConfig.GetOrderedCategories() do
		tabs.Add(TextConfig.Resolve(category.nameKey), category.id, function()
			self:_SelectCategory(category.id)
		end)
	end
	self._glTabs = tabs

	-- Content sits on PAPER, inset from the character art on the left.
	local field = UIStyler.Frame("Field")
	field.BackgroundTransparency = 1
	field.Position = UDim2.fromOffset(26, 26)
	field.Size = UDim2.new(1, -52, 1, -46)
	field.ClipsDescendants = true
	field.ZIndex = 3
	field.Parent = page.content
	self._glField = field

	-- Featured hero slab: dark accent card ON the paper, wide + slanted.
	local hero = Instance.new("TextButton")
	hero.Name = "Hero"
	hero.BackgroundTransparency = 1
	hero.Text = ""
	hero.AutoButtonColor = false
	hero.Size = UDim2.new(1, 0, 0, 160)
	hero.ZIndex = 4
	hero.Parent = field
	local heroPlate = GLLayoutKit.Slice(theme, "cardCut", theme.Arcade.NearBlack2, "HeroPlate")
	heroPlate.Size = UDim2.fromScale(1, 1)
	heroPlate.Rotation = GLLayoutKit.TILT * 0.4
	heroPlate.ZIndex = 4
	heroPlate.Parent = hero
	GLLayoutKit.Shadow(theme, heroPlate, "md", self._glShadows)
	GLLayoutKit.HalftoneEdge(theme, heroPlate, 20)
	-- Featured artwork well on the hero's left, filled from the archive.
	local heroArt = GLLayoutKit.Slice(theme, "artSlot", theme.Colors.Disabled, "HeroArt")
	heroArt.Position = UDim2.fromOffset(18, 16)
	heroArt.Size = UDim2.new(0.34, 0, 1, -32)
	heroArt.ZIndex = 5
	heroArt.Parent = heroPlate
	GLLayoutKit.Tile(theme, "halftone", theme.Colors.Stroke, 0.86, "HeroArtTone").Parent = heroArt
	local heroArtImage = Instance.new("ImageLabel")
	heroArtImage.Name = "ArtImage"
	heroArtImage.BackgroundTransparency = 1
	heroArtImage.ScaleType = Enum.ScaleType.Fit
	heroArtImage.AnchorPoint = Vector2.new(0.5, 0.5)
	heroArtImage.Position = UDim2.fromScale(0.5, 0.5)
	heroArtImage.Size = UDim2.fromScale(0.8, 0.8)
	heroArtImage.Visible = false
	heroArtImage.ZIndex = 6
	heroArtImage.Parent = heroArt
	local heroArtLabel = GLLayoutKit.Text(theme, 13, theme.Colors.TextSecondary, "HeroArtLabel")
	heroArtLabel.Text = "ART SLOT"
	heroArtLabel.Size = UDim2.fromScale(1, 0.3)
	heroArtLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	heroArtLabel.Position = UDim2.fromScale(0.5, 0.5)
	heroArtLabel.ZIndex = 6
	heroArtLabel.Parent = heroArt
	self._glHeroArt = { artImage = heroArtImage, artLabel = heroArtLabel }
	self._glHero = hero
	self._glHeroName = GLLayoutKit.Text(theme, 34, theme.Colors.TextPrimary, "HeroName")
	self._glHeroName.TextXAlignment = Enum.TextXAlignment.Left
	self._glHeroName.Position = UDim2.new(0.38, 0, 0, 18)
	self._glHeroName.Size = UDim2.new(0.6, 0, 0, 40)
	self._glHeroName.ZIndex = 6
	self._glHeroName.Parent = heroPlate
	self._glHeroDesc = GLLayoutKit.BodyText(theme, 15, theme.Colors.TextSecondary, "HeroDesc")
	self._glHeroDesc.TextXAlignment = Enum.TextXAlignment.Left
	self._glHeroDesc.TextYAlignment = Enum.TextYAlignment.Top
	self._glHeroDesc.TextWrapped = true
	self._glHeroDesc.Position = UDim2.new(0.38, 0, 0, 62)
	self._glHeroDesc.Size = UDim2.new(0.56, 0, 0, 52)
	self._glHeroDesc.ZIndex = 6
	self._glHeroDesc.Parent = heroPlate
	self._glHeroPrice = GLLayoutKit.PriceChip(theme, heroPlate, self._glShadows)
	self._glHeroPrice.root.Position = UDim2.new(0.38, 0, 0, 116)
	self._glHeroPrice.root.Size = UDim2.fromOffset(170, 40)
	self._glHeroPrice.root.ZIndex = 6
	-- Gold glow on the FEATURED price chip only (never the whole card).
	if theme.EffectGlows then
		local _, glow = UIChrome.Glow(theme, "md", self._glHeroPrice.root)
		table.insert(self._glShadows, glow)
	end
	self._glHeroCta = GLLayoutKit.ActionButton(theme, heroPlate, self:_R("shop.buy"), function()
		local item = self._glHeroItem
		if item then
			self:_PromptPurchase(item)
		end
	end, self._glShadows)
	self._glHeroCta.Position = UDim2.new(0.38, 190, 0, 112)
	self._glHeroCta.Size = UDim2.fromOffset(184, 48)
	self._glHeroCta.ZIndex = 6
	-- PACK LAW: text fill is always white/light — the badge keeps the kit's
	-- cream ink over gold, legible via its black outline stroke.
	local heroBadge = GLLayoutKit.Badge(theme, heroPlate, "FEATURED", theme.Arcade.Gold, self._glShadows)
	self._glHeroBadge = heroBadge

	-- Dense portrait tile grid on the paper, 5 across with tight gutters.
	-- Sunburst rays behind the grid: fills the paper at any item count and
	-- gives the field a centre of gravity. Slow rotation on the SHARED
	-- ticker (one handler, bound to the panel so a rebuild cleans it up).
	local rays = GLLayoutKit.Slice(theme, "sunburstRays", theme.Colors.Primary, "Rays")
	rays.ImageTransparency = 0.88
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = UDim2.fromScale(0.5, 0.62)
	rays.Size = UDim2.fromOffset(760, 760)
	rays.ZIndex = 2
	rays.Parent = field
	if self._glRayStop then
		self._glRayStop()
	end
	self._glRayStop = UITicker.Register(function(dt: number)
		if UIChrome.IsOnScreen(rays) then
			rays.Rotation = (rays.Rotation + dt * 1.5) % 360
		end
	end, page.panel)

	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Tiles"
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.Position = UDim2.fromOffset(0, 178)
	grid.Size = UDim2.new(1, 0, 1, -178)
	grid.CanvasSize = UDim2.new()
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.ScrollBarThickness = 5
	grid.ScrollBarImageColor3 = theme.Colors.Stroke
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.ClipsDescendants = true
	grid.ZIndex = 4
	grid.Parent = field
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0.185, 0, 0, 156)
	layout.CellPadding = UDim2.fromOffset(10, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	local gridPad = Instance.new("UIPadding")
	gridPad.Name = "glGridPad"
	gridPad.PaddingTop = UDim.new(0, 14)
	gridPad.PaddingBottom = UDim.new(0, 14)
	gridPad.PaddingLeft = UDim.new(0, 12)
	gridPad.Parent = grid
	self._glGrid = grid

	self:_GLRefresh()
end

-- Keyed pooled reconcile over the portrait tiles + the hero slab.
function ShopScreen:_GLRefresh()
	local grid = self._glGrid :: ScrollingFrame?
	if not grid or not self._glTabs then
		return -- built under another layout; the next Show rebuilds
	end
	local theme = self:GetTheme()
	self._glTabs.Select(self._categoryId)

	local items = ShopConfig.GetItemsForCategory(self._categoryId)
	local seen = {}

	-- Hero = the first item of the category.
	local heroItem = items[1]
	self._glHeroItem = heroItem
	if heroItem then
		local currency = ShopConfig.Currencies[heroItem.currencyType]
		local affordable = ShopConfig.CanAfford(self._balances, heroItem)
		self._glHero.Visible = true
		self._glHeroName.Text = string.upper(self:_R(heroItem.nameKey))
		self._glHeroDesc.Text = self:_R(heroItem.descriptionKey)
		self._glHeroPrice.icon.Image = (currency and currency.iconId) or ""
		GLLayoutKit.ApplyItemArt(self._glHeroArt, heroItem)
		self._glHeroPrice.amount.Text = ShopConfig.FormatPrice(heroItem.price)
		self._glHeroPrice.amount.TextColor3 = affordable and theme.Arcade.Gold or theme.Colors.TextSecondary
	else
		self._glHero.Visible = false
	end

	-- Every remaining item becomes a portrait rarity tile.
	for i = 2, #items do
		local item = items[i]
		seen[item.id] = true
		local entry = self._glTiles[item.id]
		if not entry then
			entry = table.remove(self._glTilePool) or GLLayoutKit.ItemTile(theme, grid, self._glShadows)
			entry.root.Visible = true
			entry.root.Parent = grid
			self._glTiles[item.id] = entry
		end
		local currency = ShopConfig.Currencies[item.currencyType]
		local affordable = ShopConfig.CanAfford(self._balances, item)
		entry.root.LayoutOrder = i
		entry.countText.Text = ShopConfig.FormatPrice(item.price)
		entry.countChip.ImageColor3 = theme.Arcade.NearBlack
		entry.countText.TextColor3 = affordable and theme.Arcade.Gold or theme.Colors.TextSecondary
		entry.lock.Visible = not affordable
		-- Rarity ramp drives the BORDER only, from the item's first tag.
		local tag = item.tags and item.tags[1]
		local rarity = "common"
		if tag == "Rare" or tag == "Limited" then
			rarity = "rare"
		elseif tag == "Popular" or tag == "New" then
			rarity = "common"
		end
		if item.price >= 500 then
			rarity = "giga"
		end
		GLLayoutKit.SetTileRarity(theme, entry, rarity)
		-- Real artwork from the ICON ARCHIVE (semantic iconKey -> uploaded art);
		-- the ART SLOT placeholder only survives where nothing resolves.
		GLLayoutKit.ApplyItemArt(entry, item)
		entry.artLabel.Text = string.upper(self:_R(item.nameKey))
		entry.artLabel.TextSize = 11
		if entry.clickConn then
			entry.clickConn:Disconnect()
		end
		entry.clickConn = entry.root.Activated:Connect(function()
			self:_PromptPurchase(item)
		end)
	end

	-- Release vanished tiles to the pool: hidden, shadows DISABLED, never
	-- destroyed (the pack pooling law).
	for id, entry in self._glTiles do
		if not seen[id] then
			entry.root.Visible = false
			entry.shadow:SetEnabled(false)
			if entry.clickConn then
				entry.clickConn:Disconnect()
				entry.clickConn = nil
			end
			table.insert(self._glTilePool, entry)
			self._glTiles[id] = nil
		end
	end

	-- Rotated children escape ClipsDescendants; sweep the viewport clean.
	if self._glGrid then
		GLLayoutKit.EnforceClipSafety(self._glGrid)
	end
	self:_RefreshCurrencies()
end

return ShopScreen
