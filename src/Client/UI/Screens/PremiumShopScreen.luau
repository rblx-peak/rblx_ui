--!strict
-- Robux storefront SHELL (id "premiumShop") — the monetization browser on the
-- Pottery Clash arcade family (doc §3.3 / §7.4 / §8). One modal card, one
-- vertical scroll, three sections:
--   FEATURED       — hero banner: rainbow-gradient headline offset-scrolled at
--                    0.45 cycles/s while shown (disconnected on hide), contents
--                    chips, a magenta buy button.
--   CURRENCY PACKS — four tiles, the bux gem growing per tier with the golden
--                    variant on the biggest, FredokaOne 30 amount, magenta price.
--   GAME PASSES    — icon + name + benefit rows whose price button flips to
--                    grey OWNED in place when the data marks the pass owned.
--
-- REAL CHECKOUT — read before wiring this up:
-- The ONLY real checkout on Roblox is MarketplaceService:
--   * PromptProductPurchase  — developer products (currency packs, bundles)
--   * PromptGamePassPurchase — game passes
-- This screen is a BROWSER that terminates in those prompts. The Roblox
-- purchase dialog cannot be skinned, restyled or replaced, and nothing here
-- pretends otherwise: every price button routes to the injected
-- onPrompt(kind, id) callback (kind = "product" | "gamepass"), which is where
-- the host calls MarketplaceService. Grants and ownership MUST be re-checked
-- SERVER-SIDE (ProcessReceipt / UserOwnsGamePassAsync) — the `owned` flags in
-- Show(data) are display state only, never proof of purchase.
--
-- Doc §3.3: a Robux-priced button is ALWAYS magenta — the price buttons here
-- get that for free from UIButtonComponent's price mode (priceCurrency
-- "Robux" resolves the magenta fill through UIChrome.CurrencyColor).
--
-- Show(data) = { featured, packs, passes, onPrompt }.

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local GPStoreParts = require(script.Parent.Parent.Framework.GPStoreParts)
local GPChairPreview = require(script.Parent.Parent.Framework.GPChairPreview)
local UITicker = require(script.Parent.Parent.Framework.UITicker)
local Store = require(script.Parent.Parent.Config.PotteryStoreConfig)

type ContentChip = { icon: string, label: string }
type FeaturedData = {
	id: string,
	headline: string,
	blurb: string,
	price: number,
	tag: string?,
	contents: { ContentChip },
}
-- `icon` is optional and defaults to the tiered bux gem: the shipped shop draws
-- its two BIGGEST packs with the gem-CHEST art instead, and that swap is a real
-- reading (the chest is what a four-figure pack looks like), not decoration.
type PackData = { id: string, amount: number, price: number, bonus: string?, icon: string? }
type PassData = {
	id: string,
	name: string,
	benefit: string,
	price: number,
	icon: string?,
	owned: boolean?,
}

-- Fixed px at the 1650×1020 baseline. Content = card − (28, 88) (§7.4 insets);
-- ROW_W leaves room for the scrollbar.
local CARD_W, CARD_H = 1120, 720
local ROW_W = 1060
local HEADER_H = 38
local HERO_H = 230
local PACK_W, PACK_H, PACK_GAP = 250, 250, 20
local PASS_H, PASS_GAP = 84, 10
local SECTION_GAP = 26
-- The bux gem grows per tier; the biggest tier wears the golden variant.
local PACK_ICON_SIZES = { 56, 68, 84, 100 }

local function comma(n: number): string
	local out = tostring(math.floor(math.abs(n)))
	while true do
		local replaced: number
		out, replaced = string.gsub(out, "^(%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then
			break
		end
	end
	return if n < 0 then "-" .. out else out
end

local function demoFeatured(): FeaturedData
	return {
		id = "starter_bundle",
		headline = "MEGA STARTER PACK",
		blurb = "Everything a new potter needs — one time only.",
		price = 199,
		tag = "ONE-TIME OFFER",
		contents = {
			{ icon = "cash", label = "5,000" },
			{ icon = "bux", label = "250" },
			{ icon = "crate", label = "x3" },
			{ icon = "sparkle", label = "GLAZE" },
		},
	}
end

local function demoPacks(): { PackData }
	return {
		{ id = "bux_250", amount = 250, price = 79 },
		{ id = "bux_700", amount = 700, price = 199, bonus = "+8% BONUS" },
		{ id = "bux_1500", amount = 1500, price = 399, bonus = "+15% BONUS" },
		{ id = "bux_4000", amount = 4000, price = 899, bonus = "BEST VALUE" },
	}
end

local function demoPasses(): { PassData }
	return {
		{ id = "vip", name = "VIP", benefit = "Gold name + 10% extra Cash from every duel", price = 349, icon = "crown", owned = true },
		{ id = "master_potter", name = "MASTER POTTER", benefit = "Every wheel unlocked + exclusive glazes", price = 499, icon = "premium" },
		{ id = "auto_collect", name = "AUTO COLLECT", benefit = "Booth sales collect themselves while you craft", price = 249, icon = "magnet" },
		{ id = "double_xp", name = "DOUBLE XP", benefit = "Level twice as fast, forever", price = 299, icon = "bolt" },
	}
end

local PremiumShopScreen = setmetatable({}, { __index = UIScreenBase })
PremiumShopScreen.__index = PremiumShopScreen

function PremiumShopScreen.new()
	local self = UIScreenBase.new("PremiumShopScreen", 5)
	self._featured = demoFeatured()
	self._packs = demoPacks()
	self._passes = demoPasses()
	self._onPrompt = nil :: ((kind: string, id: string) -> ())?
	self._components = {} :: { any }
	self._passButtons = {} :: { [string]: any }
	self._rainbowGradient = nil :: UIGradient?
	self._rainbowConn = nil :: RBXScriptConnection?
	return setmetatable(self, PremiumShopScreen)
end

function PremiumShopScreen:_Toast(text: string, variant: string)
	local hud = self.ScreenController and self.ScreenController:GetScreen("hud")
	if hud then
		hud:PushToast({ text = text, variant = variant })
	end
end

function PremiumShopScreen:_Track(component: any): any
	table.insert(self._components, component)
	return component
end

-- Every price button lands here. The injected onPrompt is the seam where the
-- host opens the real MarketplaceService prompt; without one (standalone demo)
-- the flow is simulated so the screen still demonstrates the OWNED flip.
function PremiumShopScreen:_Prompt(kind: string, id: string)
	local onPrompt = self._onPrompt
	if onPrompt then
		onPrompt(kind, id)
		return
	end
	if kind == "gamepass" then
		for _, pass in self._passes :: { PassData } do
			if pass.id == id then
				if pass.owned then
					self:_Toast("You already own this pass.", "Info")
					return
				end
				pass.owned = true
				-- OWNED recolours grey IN PLACE (doc §11.2) — no rebuild.
				local button = self._passButtons[id]
				if button then
					button:SetContent({ owned = true })
				end
				self:_Toast("Demo purchase — a real build re-checks ownership on the server.", "Success")
				return
			end
		end
		return
	end
	self:_Toast("Demo — this is where the Roblox purchase prompt opens.", "Info")
end

function PremiumShopScreen:_BuildContent()
	-- GP layout language: the pastel STOREFRONT (cream page, rose ribbon,
	-- petal tiles alternating mirror, butter price pills) — see _BuildGPLayout.
	if self:LayoutKit() == "GP" then
		-- Seed the REAL Pottery Battles catalog before the pastel page builds:
		-- the six passes with their actual value propositions, the four Bux
		-- packs with their actual promo badges, and the starter bundle as the
		-- featured shelf. Without this the pack renders placeholder copy.
		self:_GPSeedCatalog()
		self:_BuildGPLayout()
		return
	end

	local theme = self:GetTheme()

	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = "PREMIUM SHOP",
		sizePx = Vector2.new(CARD_W, CARD_H),
		onClose = function()
			self.ScreenController:HideScreen("premiumShop")
		end,
	})
	self._modal = modal

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Sections"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 8
	scroll.ScrollBarImageColor3 = theme.Arcade.Gold
	scroll.Parent = modal.content
	self._scroll = scroll

	self:_Render()
end

function PremiumShopScreen:_SectionHeader(text: string, y: number): TextLabel
	local theme = self:GetTheme()
	local label = UIChrome.Text("Section_" .. text, 24, theme.Arcade.Gold)
	label.Text = text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Position = UDim2.fromOffset(0, y)
	label.Size = UDim2.fromOffset(ROW_W, 30)
	label.Parent = self._scroll
	return label
end

function PremiumShopScreen:_ClearRender()
	for _, component in self._components :: { any } do
		component:Destroy()
	end
	table.clear(self._components)
	table.clear(self._passButtons)
	if self._rainbowConn then
		self._rainbowConn:Disconnect()
		self._rainbowConn = nil
	end
	self._rainbowGradient = nil
	for _, child in self._scroll:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function PremiumShopScreen:_Render()
	-- GP pastel storefront: the same three sections in the pack's own parts
	-- (see _GPRender). Every other render path below stays untouched.
	if self:LayoutKit() == "GP" then
		self:_GPRender()
		return
	end

	local theme = self:GetTheme()
	self:_ClearRender()

	local y = 0
	self:_SectionHeader("FEATURED", y)
	y += HEADER_H
	self:_BuildHero(y)
	y += HERO_H + SECTION_GAP

	self:_SectionHeader("CURRENCY PACKS", y)
	y += HEADER_H
	self:_BuildPacks(y)
	y += PACK_H + SECTION_GAP

	self:_SectionHeader("GAME PASSES", y)
	y += HEADER_H
	for index, pass in self._passes :: { PassData } do
		self:_BuildPassRow(pass, y)
		y += PASS_H + (if index < #self._passes then PASS_GAP else 0)
	end
	y += SECTION_GAP

	-- Footer note (muted body text): the checkout itself is never this screen.
	local footer = UIChrome.BodyText("Footer", 15, theme.Colors.Disabled)
	footer.Text = "Purchases are handled by Roblox — payment happens in the official Roblox prompt."
	footer.Position = UDim2.fromOffset(0, y)
	footer.Size = UDim2.fromOffset(ROW_W, 22)
	footer.Parent = self._scroll
	y += 34

	self._scroll.CanvasSize = UDim2.fromOffset(0, y)
end

function PremiumShopScreen:_BuildHero(y: number)
	local theme = self:GetTheme()
	local featured: FeaturedData = self._featured

	local hero = UIStyler.Frame("Hero")
	hero.BackgroundColor3 = theme.Arcade.NearBlack2
	hero.BackgroundTransparency = 0
	hero.Position = UDim2.fromOffset(0, y)
	hero.Size = UDim2.fromOffset(ROW_W, HERO_H)
	UIChrome.Stroke(theme, "Arcade").Parent = hero
	UIChrome.GlassGradient().Parent = hero
	hero.Parent = self._scroll

	-- Rainbow wordmark headline (doc §3.2): FredokaOne 44, black-outlined,
	-- 5-stop rainbow offset-scrolled at 0.45 cycles/s while shown.
	local headline = UIChrome.Text("Headline", 44, theme.Colors.TextPrimary)
	headline.RichText = false
	headline.Text = featured.headline
	headline.TextXAlignment = Enum.TextXAlignment.Left
	headline.TextTruncate = Enum.TextTruncate.AtEnd
	headline.Position = UDim2.fromOffset(24, 12)
	headline.Size = UDim2.fromOffset(620, 52)
	headline.ZIndex = 2
	local rainbow = UIChrome.RainbowGradient(theme)
	rainbow.Parent = headline
	self._rainbowGradient = rainbow
	headline.Parent = hero

	local blurb = UIChrome.BodyText("Blurb", 17, theme.Arcade.IceBlue)
	blurb.Text = featured.blurb
	blurb.TextXAlignment = Enum.TextXAlignment.Left
	blurb.TextTruncate = Enum.TextTruncate.AtEnd
	blurb.Position = UDim2.fromOffset(24, 66)
	blurb.Size = UDim2.fromOffset(620, 22)
	blurb.ZIndex = 2
	blurb.Parent = hero

	-- What's inside: boxless icon chips (doc §10 — flat cartoon art, no boxes).
	local chips = UIStyler.Frame("Contents")
	chips.BackgroundTransparency = 1
	chips.Position = UDim2.fromOffset(24, 100)
	chips.Size = UDim2.fromOffset(620, 116)
	chips.ZIndex = 2
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Padding = UDim.new(0, 14),
	}).Parent = chips
	chips.Parent = hero

	for index, chip in featured.contents do
		local slot = UIStyler.Frame("Chip" .. index)
		slot.BackgroundTransparency = 1
		slot.Size = UDim2.fromOffset(120, 110)
		slot.LayoutOrder = index
		slot.ZIndex = 2
		slot.Parent = chips

		local icon = IconArchive.Image(slot, chip.icon, 56)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 6)
		icon.ZIndex = 3

		local label = UIChrome.Text("Amount", 17, theme.Arcade.Gold)
		label.Text = chip.label
		label.Position = UDim2.fromOffset(0, 72)
		label.Size = UDim2.fromOffset(120, 24)
		label.ZIndex = 3
		label.Parent = slot
	end

	if featured.tag then
		local tag = UIChrome.Text("Tag", 17, theme.Arcade.Gold)
		tag.Text = featured.tag
		tag.TextXAlignment = Enum.TextXAlignment.Right
		tag.AnchorPoint = Vector2.new(1, 0)
		tag.Position = UDim2.new(1, -26, 0, 18)
		tag.Size = UDim2.fromOffset(260, 22)
		tag.ZIndex = 2
		tag.Parent = hero
	end

	local buy = self:_Track(UIButtonComponent.new())
	buy:Create(hero, {
		priceCurrency = "Robux",
		priceAmount = comma(featured.price),
		size = UDim2.fromOffset(200, 56),
		anchorPoint = Vector2.new(1, 0.5),
		position = UDim2.new(1, -26, 0.5, 10),
		onClick = function()
			self:_Prompt("product", featured.id)
		end,
	})
	buy.Root.ZIndex = 3
end

function PremiumShopScreen:_BuildPacks(y: number)
	local theme = self:GetTheme()
	local packs: { PackData } = self._packs

	for index, pack in packs do
		local tile = UIStyler.Frame("Pack_" .. pack.id)
		tile.BackgroundColor3 = theme.Arcade.NearBlack
		tile.BackgroundTransparency = 0
		tile.Position = UDim2.fromOffset((index - 1) * (PACK_W + PACK_GAP), y)
		tile.Size = UDim2.fromOffset(PACK_W, PACK_H)
		UIChrome.Stroke(theme, "Arcade").Parent = tile
		UIChrome.GlassGradient().Parent = tile
		tile.Parent = self._scroll

		-- Gem grows per tier; the biggest tier gets the golden treatment.
		local iconSize = PACK_ICON_SIZES[math.min(index, #PACK_ICON_SIZES)]
		local icon = IconArchive.Image(tile, "bux", iconSize, { golden = index == #packs })
		icon.AnchorPoint = Vector2.new(0.5, 1)
		icon.Position = UDim2.new(0.5, 0, 0, 124)
		icon.ZIndex = 2

		-- Amount in the currency's colour (doc §3.3: Bux = blue, everywhere).
		local amount = UIChrome.Text("Amount", 30, UIChrome.CurrencyColor(theme, "Bux"))
		amount.Text = comma(pack.amount) .. " BUX"
		amount.Position = UDim2.fromOffset(0, 132)
		amount.Size = UDim2.fromOffset(PACK_W, 34)
		amount.ZIndex = 2
		amount.Parent = tile

		if pack.bonus then
			local bonus = UIChrome.Text("Bonus", 15, theme.Arcade.Gold)
			bonus.Text = pack.bonus
			bonus.Position = UDim2.fromOffset(0, 164)
			bonus.Size = UDim2.fromOffset(PACK_W, 20)
			bonus.ZIndex = 2
			bonus.Parent = tile
		end

		local buy = self:_Track(UIButtonComponent.new())
		buy:Create(tile, {
			priceCurrency = "Robux",
			priceAmount = comma(pack.price),
			size = UDim2.fromOffset(160, 48),
			anchorPoint = Vector2.new(0.5, 1),
			position = UDim2.new(0.5, 0, 1, -12),
			onClick = function()
				self:_Prompt("product", pack.id)
			end,
		})
		buy.Root.ZIndex = 3
	end
end

function PremiumShopScreen:_BuildPassRow(pass: PassData, y: number)
	local theme = self:GetTheme()

	local row = UIStyler.Frame("Pass_" .. pass.id)
	row.BackgroundColor3 = theme.Arcade.Row
	row.BackgroundTransparency = theme.Arcade.RowTransparency
	row.Position = UDim2.fromOffset(0, y)
	row.Size = UDim2.fromOffset(ROW_W, PASS_H)
	UIChrome.Stroke(theme, "Arcade").Parent = row
	UIChrome.GlassGradient().Parent = row
	row.Parent = self._scroll

	local icon = IconArchive.Image(row, pass.icon or "gamepass", 56)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 14, 0.5, 0)
	icon.ZIndex = 2

	local name = UIChrome.Text("Name", 24, theme.Colors.TextPrimary)
	name.Text = pass.name
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(86, 12)
	name.Size = UDim2.fromOffset(720, 28)
	name.ZIndex = 2
	name.Parent = row

	local benefit = UIChrome.BodyText("Benefit", 16, theme.Arcade.IceBlue)
	benefit.Text = pass.benefit
	benefit.TextXAlignment = Enum.TextXAlignment.Left
	benefit.TextTruncate = Enum.TextTruncate.AtEnd
	benefit.Position = UDim2.fromOffset(86, 44)
	benefit.Size = UDim2.fromOffset(720, 20)
	benefit.ZIndex = 2
	benefit.Parent = row

	local buy = self:_Track(UIButtonComponent.new())
	buy:Create(row, {
		priceCurrency = "Robux",
		priceAmount = comma(pass.price),
		owned = pass.owned == true,
		size = UDim2.fromOffset(160, 48),
		anchorPoint = Vector2.new(1, 0.5),
		position = UDim2.new(1, -14, 0.5, 0),
		onClick = function()
			if pass.owned then
				-- Every tap answers (doc §11.1): OWNED still explains itself.
				self:_Toast("You already own this pass.", "Info")
				return
			end
			self:_Prompt("gamepass", pass.id)
		end,
	})
	buy.Root.ZIndex = 3
	self._passButtons[pass.id] = buy
end

-- The rainbow scroll is recreated per render (the gradient lives on a rebuilt
-- label), so hooking is separate from rendering and gated on visibility.
function PremiumShopScreen:_HookRainbow()
	if self._rainbowConn then
		self._rainbowConn:Disconnect()
		self._rainbowConn = nil
	end
	if self._rainbowGradient then
		self._rainbowConn = UIChrome.ScrollGradient(self._rainbowGradient, 0.45)
	end
end

function PremiumShopScreen:_Apply(data: any)
	if data.featured then
		self._featured = data.featured
	end
	if data.packs then
		self._packs = data.packs
	end
	if data.passes then
		self._passes = data.passes
	end
	if data.onPrompt then
		self._onPrompt = data.onPrompt
	end
end

function PremiumShopScreen:_OnShow(data: any?)
	if data then
		self:_Apply(data)
		self:_Render()
	end
	self:_HookRainbow()
	if self._modal then
		UIChrome.PopIn(self:GetTheme(), self._modal.content)
	elseif self._gpPage then
		-- Same POP_IN contract, on the pack's own plate (theme.Motion tokens).
		-- dim doubles as the page's OPEN flag: every chair preview on this
		-- page gates its spin on it, so a shut counter animates nothing.
		self._gpPage.dim.Visible = true
		UIChrome.PopIn(self:GetTheme(), self._gpPage.panel)
	end
end

function PremiumShopScreen:_OnHide()
	if self._rainbowConn then
		self._rainbowConn:Disconnect()
		self._rainbowConn = nil
	end
	if self._gpPage then
		self._gpPage.dim.Visible = false
	end
	if self._gpExtrasStop then
		self._gpExtrasStop()
		self._gpExtrasStop = nil
	end
end

function PremiumShopScreen:Update(data: any)
	if not data then
		return
	end
	self:_Apply(data)
	if self._built then
		self:_Render()
		if self._visible then
			self:_HookRainbow()
		end
	end
end

function PremiumShopScreen:Destroy()
	self:_OnHide()
	-- UIScreenBase.Destroy only throws the Gui away; the UIShadow BUDGET counts
	-- and the chair previews' Models live outside it and are only handed back by
	-- _OnTeardown. Without this call a destroyed shop keeps spending both.
	self:_OnTeardown()
	for _, component in self._components :: { any } do
		component:Destroy()
	end
	table.clear(self._components)
	UIScreenBase.Destroy(self)
end

-- ======================================================================
-- GP layout (theme.LayoutKit == "GP") — the pastel STOREFRONT, composed from
-- GPLayoutKit: a cream Page under a rose ribbon, then the SAME three
-- sections in the pack's own parts — a glazed featured shelf, four petal
-- pack tiles alternating mirror, and a pass ledger of petal rows. Value is
-- always the butter-gold PricePill; every plate casts a shadow deepened from
-- its OWN fill (pack law 2).
--
-- Presentation only. The REAL CHECKOUT note at the top of this file is
-- unchanged and unchangeable: every control here still terminates in
-- _Prompt(kind, id) → the injected onPrompt → MarketplaceService. Ownership
-- is still display state, still re-checked server-side.
--
-- DENSITY (pack law 6): every field the arcade build shows is here — the
-- rainbow-scrolled headline (on the pack's OWN pastel ramp, driven by the
-- screen's existing _HookRainbow), the blurb, all four content chips with
-- their icons and labels, the offer tag, the featured price; per pack the
-- tiered gem (golden on the top tier), the amount, the bonus and the price;
-- per pass the icon, name, benefit, price and owned state; and the footer.
-- The owned pass GAINS a field: the arcade button replaces the price with
-- the word OWNED, this one keeps the price pill AND prints an Owned chip.
-- ======================================================================

local GP_PAGE = Vector2.new(1120, 740)
local GP_ROW_W = 1064 -- content (1092) minus the scroll padding and scrollbar
local GP_HERO_H = 250
local GP_PACK_W, GP_PACK_H, GP_PACK_GAP = 254, 256, 16
local GP_PASS_H, GP_PASS_GAP = 92, 12
local GP_LABEL_H = 26
local GP_RULE_H = 18
local GP_SECTION_GAP = 26
local GP_CHIP_W, GP_CHIP_H = 128, 122

-- The Pottery Battles sections this page carries beyond the generic three:
-- the group-gated free reward, the banner bundles, and the troll pointer.
-- Declared HERE rather than beside their builders because _GPRender closes
-- over them, and a Luau closure captures only locals already in scope.
local GP_FREE_H = 272
local GP_FREE_TILE_W, GP_FREE_TILE_H = 196, 176
local GP_BUNDLE_H, GP_BUNDLE_GAP = 190, 14
local GP_BUNDLE_SLOT = 98
local GP_TROLL_H = 58
local GP_RANDOM_CYCLE = 5 -- seconds between random-chair swaps, as in the source

-- The icon archive's GLYPH FALLBACK is born pure-white with a black text
-- stroke — both banned outright by pack law 1. Every archive placement in
-- this branch goes through here so a pending upload cannot punch a hole in
-- the palette.
local function gpArt(theme: Types.UITheme, parent: Instance, key: string, sizePx: number, query: any?): GuiObject
	local art = IconArchive.Image(parent, key, sizePx, query)
	if art:IsA("TextLabel") then
		art.TextColor3 = theme.Colors.TextPrimary
		art.TextStrokeTransparency = 1
	end
	return art
end

-- A painted petal plate. UIStyler.Frame is born PURE WHITE, so no surface in
-- this branch is ever left unpainted. Shadow is opt-in: a plate per row
-- across a full ledger would spend a quarter of the engine's ~100-shadow
-- budget on furniture, so only the section surfaces take one.
local function gpPlate(theme: Types.UITheme, parent: Instance, fill: Color3, index: number, sink: { any }?): Frame
	local plate = UIStyler.Frame("Plate")
	plate.BackgroundColor3 = fill
	plate.Parent = parent
	GPLayoutKit.Petal(theme, plate, index)
	GPLayoutKit.SoftStroke(theme, plate, fill)
	if sink then
		GPLayoutKit.Shadow(theme, plate, "sm", sink, fill)
	end
	return plate
end

type GPChip = { root: Frame, label: TextLabel }

-- A glaze chip: pastel plate, INK copy. Colors.TextOnPrimary (near-white)
-- measures 2.14:1 on these tints and is legal only for LARGE display text on
-- a deepened one, so nothing small in this branch ever uses it.
local function gpChip(theme: Types.UITheme, parent: Instance, fill: Color3, text: string, index: number): GPChip
	local root = gpPlate(theme, parent, fill, index)
	root.Name = "Chip"
	root.ZIndex = 4

	local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "ChipText")
	label.Text = text
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 5
	label.Parent = root
	return { root = root, label = label }
end

type GPPriceButton = { root: TextButton, pill: any }

-- The price CONTROL: a butter-gold PricePill wearing a transparent button.
-- The button itself stays transparent because UIStyleEnforcer backstops any
-- SOLID GuiButton with a BLACK 2px stroke, which would break pack law 1 on
-- sight; the pill child carries the fill, the stroke and the hue shadow.
local function gpPriceButton(theme: Types.UITheme, parent: Instance, sink: { any }?, onClick: () -> ()): GPPriceButton
	local root = Instance.new("TextButton")
	root.Name = "GPPrice"
	root.BackgroundTransparency = 1
	root.Text = ""
	root.AutoButtonColor = false
	root.ZIndex = 5
	root.Parent = parent

	local pill = GPLayoutKit.PricePill(theme, root, sink)
	pill.root.Size = UDim2.fromScale(1, 1)
	pill.root.ZIndex = 5
	pill.amount.ZIndex = 6
	pill.icon.ZIndex = 6

	root.Activated:Connect(onClick)
	UIChrome.Animate(theme, root, pill.root)
	return { root = root, pill = pill }
end

function PremiumShopScreen:_BuildGPLayout()
	local theme = self:GetTheme()

	-- The arcade build's modal must not leak in: _OnShow pops it if present.
	self._modal = nil
	self._gpShadows = {} :: { any }
	-- TWO sinks by design. Page chrome is built once and released at teardown;
	-- section content is destroyed and rebuilt by _ClearRender on every render,
	-- so its handles are released at the TOP of each render or the budget
	-- counter climbs forever behind the destroyed instances.
	self._gpRowShadows = {} :: { any }

	local page = GPLayoutKit.Page(theme, self.Root, {
		titleText = "Premium Shop",
		subtitleText = "Robux handles the checkout, always",
		sizePx = GP_PAGE,
		onClose = function()
			self.ScreenController:HideScreen("premiumShop")
		end,
	})
	for _, handle in page.shadows do
		table.insert(self._gpShadows, handle)
	end
	self._gpPage = page

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Sections"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = theme.Colors.Primary
	-- MUST clip: unclipped rows spilling past the frame is a known past bug
	-- here. The padding keeps a plate's SOFT shadow off the clip edge so it is
	-- never sliced flat on the boundary.
	scroll.ClipsDescendants = true
	local pad = Instance.new("UIPadding")
	pad.Name = "gpSectionPad"
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 18)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = scroll
	scroll.Parent = page.content
	-- _ClearRender and _Render both address self._scroll, so the GP page hands
	-- them the same field name and every lifecycle path works unchanged.
	self._scroll = scroll

	self:_Render()
end

-- A section heading in the studio dialect: quiet label over a sage squiggle.
function PremiumShopScreen:_GPSection(text: string, y: number): number
	local theme = self:GetTheme()
	-- Verbatim copy, Title Case: this pack never shouts (pack law 5).
	local label = GPLayoutKit.SectionLabel(theme, self._scroll, text)
	label.FontFace = theme.Fonts.Subtitle
	label.TextColor3 = theme.Colors.TextPrimary
	label.TextSize = theme.TextSizes.Subtitle
	label.Position = UDim2.fromOffset(0, y)
	label.Size = UDim2.fromOffset(GP_ROW_W, GP_LABEL_H)

	-- The kit sizes the squiggle to its own art height; only the WIDTH is
	-- pinned here (this scroller places by offset, not by a list layout).
	local rule = GPLayoutKit.Divider(theme, self._scroll)
	rule.Position = UDim2.fromOffset(0, y + GP_LABEL_H)
	rule.Size = UDim2.fromOffset(GP_ROW_W, rule.Size.Y.Offset)
	return y + GP_LABEL_H + math.max(rule.Size.Y.Offset, GP_RULE_H)
end

function PremiumShopScreen:_GPRender()
	-- _gpPage is the definitive "was this tree built under GP" test. A style
	-- change flips LayoutKit() one frame BEFORE the deferred rebuild lands, so
	-- a render can arrive against the previous layout's instances.
	if not self._gpPage or not self._scroll then
		return
	end
	local theme = self:GetTheme()
	-- Release BEFORE the clear: _ClearRender destroys the instances, and a
	-- destroyed UIShadow still owes the budget until its handle is released.
	GPLayoutKit.ReleaseShadows(self._gpRowShadows)
	self:_ClearRender()

	-- _ClearRender has just destroyed every frame in the scroll, so the chair
	-- previews those frames held must be released BEFORE new ones are built:
	-- a view outlives its GuiObject (it owns a Model and a registration in the
	-- shared spin driver) and would otherwise leak both.
	self:_GPResetViews()

	local y = 0
	-- The group-gated FREE REWARD leads the page, exactly as it leads the
	-- lobby rail in the shipped game: it is the only thing here that costs
	-- nothing, so it is the only thing that gets the top of the counter.
	y = self:_GPSection(Store.Copy.storeSectionFree, y)
	self:_GPBuildFreeReward(y)
	y += GP_FREE_H + GP_SECTION_GAP

	y = self:_GPSection("Featured", y)
	self:_GPBuildHero(y)
	y += GP_HERO_H + GP_SECTION_GAP

	-- The banner BUNDLES: the source's Starter / Aura / Pro Potter packs plus
	-- the two single-chair products, each showing what is actually inside it
	-- as live spinning chairs rather than a line of prose.
	y = self:_GPSection(Store.Copy.storeSectionBundles, y)
	y = self:_GPBuildBundles(y)
	y += GP_SECTION_GAP

	y = self:_GPSection("Clay & bux packs", y)
	self:_GPBuildPacks(y)
	y += GP_PACK_H + GP_SECTION_GAP

	y = self:_GPSection("Game passes", y)
	for index, pass in self._passes :: { PassData } do
		self:_GPBuildPassRow(pass, y, index)
		y += GP_PASS_H + (if index < #self._passes then GP_PASS_GAP else 0)
	end
	y += GP_SECTION_GAP

	-- Trolls are bought MID-DUEL from the troll bar, where they fire the
	-- instant they are paid for. The counter says so rather than pretending
	-- to sell something it cannot deliver here.
	y = self:_GPSection(Store.Copy.storeSectionTrolls, y)
	local trollPlate = gpPlate(theme, self._scroll, theme.Colors.Surface, 1, self._gpRowShadows)
	trollPlate.Name = "TrollNote"
	trollPlate.Position = UDim2.fromOffset(0, y)
	trollPlate.Size = UDim2.fromOffset(GP_ROW_W, GP_TROLL_H)
	local trollMark = gpArt(theme, trollPlate, "bomb", 30)
	trollMark.AnchorPoint = Vector2.new(0, 0.5)
	trollMark.Position = UDim2.new(0, 16, 0.5, 0)
	trollMark.ZIndex = 3
	local trollText = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "TrollText")
	trollText.Text = Store.TrollNote
	trollText.TextXAlignment = Enum.TextXAlignment.Left
	trollText.Position = UDim2.fromOffset(58, 0)
	trollText.Size = UDim2.new(1, -74, 1, 0)
	trollText.ZIndex = 3
	trollText.Parent = trollPlate
	y += GP_TROLL_H + GP_SECTION_GAP

	local footer = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Footer")
	footer.Text = "Purchases are handled by Roblox — payment happens in the official Roblox prompt."
	footer.TextXAlignment = Enum.TextXAlignment.Left
	footer.Position = UDim2.fromOffset(0, y)
	footer.Size = UDim2.fromOffset(GP_ROW_W, 24)
	footer.Parent = self._scroll
	y += 36

	self._scroll.CanvasSize = UDim2.fromOffset(0, y)
end

function PremiumShopScreen:_GPBuildHero(y: number)
	local theme = self:GetTheme()
	local featured: FeaturedData = self._featured

	local heroFill = theme.Colors.Primary
	local hero = gpPlate(theme, self._scroll, heroFill, 0, self._gpRowShadows)
	hero.Name = "Hero"
	hero.Position = UDim2.fromOffset(0, y)
	hero.Size = UDim2.fromOffset(GP_ROW_W, GP_HERO_H)
	-- The glaze dialect on the ONE celebration surface of this page: the wash
	-- clones the plate's petal corner, so the shine can never square it off.
	GPLayoutKit.GlazeSheen(theme, hero)

	-- The rainbow wordmark, kept — under this pack theme.Arcade.Rainbow is the
	-- pastel ramp (rose / pink / butter / matcha / lavender), so the effect is
	-- the pack's own palette moving, and the screen's existing _HookRainbow
	-- drives it at the same 0.45 cycles/s with no new connection.
	local headline = GPLayoutKit.Text(theme, 40, theme.Colors.TextPrimary, "Headline")
	headline.RichText = false
	headline.Text = featured.headline
	headline.TextXAlignment = Enum.TextXAlignment.Left
	headline.TextTruncate = Enum.TextTruncate.AtEnd
	headline.Position = UDim2.fromOffset(24, 14)
	headline.Size = UDim2.fromOffset(620, 50)
	headline.ZIndex = 4
	local rainbow = UIChrome.RainbowGradient(theme)
	rainbow.Parent = headline
	self._rainbowGradient = rainbow
	headline.Parent = hero

	-- TextPrimary on rose measures 5.15:1; the near-white TextOnPrimary
	-- measures 2.14:1 and is illegal for body copy anywhere in this pack.
	local blurb = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "Blurb")
	blurb.Text = featured.blurb
	blurb.TextXAlignment = Enum.TextXAlignment.Left
	blurb.TextTruncate = Enum.TextTruncate.AtEnd
	blurb.Position = UDim2.fromOffset(24, 68)
	blurb.Size = UDim2.fromOffset(620, 24)
	blurb.ZIndex = 4
	blurb.Parent = hero

	-- What's inside: one petal slot per content chip, icon over label.
	for index, chip in featured.contents do
		local slot = gpPlate(theme, hero, theme.Colors.SurfaceRaised, index)
		slot.Name = "Chip" .. index
		slot.Position = UDim2.fromOffset(24 + (index - 1) * (GP_CHIP_W + 14), 100)
		slot.Size = UDim2.fromOffset(GP_CHIP_W, GP_CHIP_H)
		slot.ZIndex = 4

		local icon = gpArt(theme, slot, chip.icon, 56)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 10)
		icon.ZIndex = 5

		local label = GPLayoutKit.Text(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "Amount")
		label.Text = chip.label
		label.Position = UDim2.fromOffset(0, 74)
		label.Size = UDim2.fromOffset(GP_CHIP_W, 26)
		label.ZIndex = 5
		label.Parent = slot
	end

	if featured.tag then
		local tag = gpChip(theme, hero, theme.Colors.Accent, featured.tag, 1)
		tag.root.AnchorPoint = Vector2.new(1, 0)
		tag.root.Position = UDim2.new(1, -24, 0, 18)
		tag.root.Size = UDim2.fromOffset(240, 30)
		tag.label.TextSize = theme.TextSizes.Body
	end

	local price = gpPriceButton(theme, hero, self._gpRowShadows, function()
		self:_Prompt("product", featured.id)
	end)
	price.root.AnchorPoint = Vector2.new(1, 0)
	price.root.Position = UDim2.new(1, -24, 0, 128)
	price.root.Size = UDim2.fromOffset(210, 46)
	price.pill.icon.Image = IconArchive.Id("robux") or ""
	price.pill.amount.Text = comma(featured.price)

	local buy = gpPriceButton(theme, hero, self._gpRowShadows, function()
		self:_Prompt("product", featured.id)
	end)
	-- The CTA reuses the price control's shape but reads as an ACTION: matcha
	-- fill, no glyph, the word instead of the number.
	buy.root.AnchorPoint = Vector2.new(1, 0)
	buy.root.Position = UDim2.new(1, -24, 0, 184)
	buy.root.Size = UDim2.fromOffset(210, 50)
	buy.pill.root.BackgroundColor3 = theme.Colors.Secondary
	buy.pill.icon.Visible = false
	buy.pill.amount.Text = "Buy this pack"
	buy.pill.amount.TextXAlignment = Enum.TextXAlignment.Center
	buy.pill.amount.Position = UDim2.fromOffset(0, 0)
	buy.pill.amount.Size = UDim2.fromScale(1, 1)
	buy.pill.amount.FontFace = theme.Fonts.Button
end

function PremiumShopScreen:_GPBuildPacks(y: number)
	local theme = self:GetTheme()
	local packs: { PackData } = self._packs

	for index, pack in packs do
		-- Petal alternates by tile index so the shelf reads hand-arranged.
		local tile = gpPlate(theme, self._scroll, theme.Colors.SurfaceRaised, index, self._gpRowShadows)
		tile.Name = "Pack_" .. pack.id
		tile.Position = UDim2.fromOffset((index - 1) * (GP_PACK_W + GP_PACK_GAP), y)
		tile.Size = UDim2.fromOffset(GP_PACK_W, GP_PACK_H)

		-- The gem still grows per tier and the biggest tier still wears the
		-- golden variant — the arcade build's whole value ladder, unchanged.
		local iconSize = PACK_ICON_SIZES[math.min(index, #PACK_ICON_SIZES)]
		local icon = gpArt(theme, tile, pack.icon or "bux", iconSize, { golden = index == #packs })
		icon.AnchorPoint = Vector2.new(0.5, 1)
		icon.Position = UDim2.new(0.5, 0, 0, 112)
		icon.ZIndex = 3

		-- Doc §3.3 keeps Bux BLUE everywhere; the pack keeps text measured. So
		-- the currency colour lands as the PLATE and the numerals stay ink —
		-- Bux blue as 30px type on cream measures ~2:1 and would fail outright.
		local amountPlate = gpPlate(theme, tile, UIChrome.CurrencyColor(theme, "Bux"), index + 1)
		amountPlate.Name = "AmountPlate"
		amountPlate.Position = UDim2.fromOffset(14, 118)
		amountPlate.Size = UDim2.fromOffset(GP_PACK_W - 28, 38)
		amountPlate.ZIndex = 3

		local amount = GPLayoutKit.Text(theme, 26, theme.Colors.TextPrimary, "Amount")
		amount.Text = comma(pack.amount) .. " Bux"
		amount.Size = UDim2.fromScale(1, 1)
		amount.ZIndex = 4
		amount.Parent = amountPlate

		if pack.bonus then
			local bonus = gpChip(theme, tile, theme.Colors.Accent, pack.bonus, index)
			bonus.root.Position = UDim2.fromOffset(14, 162)
			bonus.root.Size = UDim2.fromOffset(GP_PACK_W - 28, 24)
			bonus.root.ZIndex = 3
		end

		local price = gpPriceButton(theme, tile, self._gpRowShadows, function()
			self:_Prompt("product", pack.id)
		end)
		price.root.AnchorPoint = Vector2.new(0.5, 1)
		price.root.Position = UDim2.new(0.5, 0, 1, -14)
		price.root.Size = UDim2.fromOffset(GP_PACK_W - 54, 44)
		price.pill.icon.Image = IconArchive.Id("robux") or ""
		price.pill.amount.Text = comma(pack.price)
	end
end

function PremiumShopScreen:_GPBuildPassRow(pass: PassData, y: number, index: number)
	local theme = self:GetTheme()
	local owned = pass.owned == true

	local row = gpPlate(theme, self._scroll, theme.Colors.SurfaceRaised, index, self._gpRowShadows)
	row.Name = "Pass_" .. pass.id
	row.Position = UDim2.fromOffset(0, y)
	row.Size = UDim2.fromOffset(GP_ROW_W, GP_PASS_H)

	local icon = gpArt(theme, row, pass.icon or "gamepass", 52)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 16, 0.5, 0)
	icon.ZIndex = 3

	local name = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "Name")
	name.Text = pass.name
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(84, 12)
	name.Size = UDim2.fromOffset(GP_ROW_W - 460, 28)
	name.ZIndex = 3
	name.Parent = row

	local benefit = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Benefit")
	benefit.Text = pass.benefit
	benefit.TextXAlignment = Enum.TextXAlignment.Left
	benefit.TextTruncate = Enum.TextTruncate.AtEnd
	benefit.Position = UDim2.fromOffset(84, 46)
	benefit.Size = UDim2.fromOffset(GP_ROW_W - 460, 22)
	benefit.ZIndex = 3
	benefit.Parent = row

	-- OWNED is a WORD and a chip, not a hue: this row keeps the price visible
	-- beside it, where the arcade build replaces the price with the word.
	if owned then
		local badge = gpChip(theme, row, theme.Colors.Secondary, "Owned", index + 1)
		badge.root.AnchorPoint = Vector2.new(1, 0.5)
		badge.root.Position = UDim2.new(1, -206, 0.5, 0)
		badge.root.Size = UDim2.fromOffset(110, 30)
		badge.label.TextSize = theme.TextSizes.Body
	elseif (pass :: any).badge then
		-- The source hangs a promo shout on VIP ("BEST VALUE"). It keeps its
		-- item, its slot and its meaning here; only the volume changes.
		local promo = gpChip(theme, row, theme.Arcade.Gold, (pass :: any).badge, index + 1)
		promo.root.AnchorPoint = Vector2.new(1, 0.5)
		promo.root.Position = UDim2.new(1, -206, 0.5, 0)
		promo.root.Size = UDim2.fromOffset(126, 30)
		promo.label.TextSize = theme.TextSizes.Body
	end

	local price = gpPriceButton(theme, row, self._gpRowShadows, function()
		if pass.owned then
			-- Every tap answers (doc §11.1): OWNED still explains itself.
			self:_Toast("You already own this pass.", "Info")
			return
		end
		self:_Prompt("gamepass", pass.id)
	end)
	price.root.AnchorPoint = Vector2.new(1, 0.5)
	price.root.Position = UDim2.new(1, -16, 0.5, 0)
	price.root.Size = UDim2.fromOffset(180, 46)
	price.pill.icon.Image = IconArchive.Id("robux") or ""
	price.pill.amount.Text = comma(pass.price)
	if owned then
		-- Quieted IN PLACE, never removed (doc §11.2) — and the SHADOW retints
		-- with the fill, because a quiet pill still casting amber would be the
		-- grey-shadow bug inverted.
		local quiet = theme.Colors.Disabled
		price.pill.root.BackgroundColor3 = quiet
		price.pill.shadow.Instance.Color = GPLayoutKit.Deepen(theme, quiet, 1)
	end
	-- _Prompt's demo path flips OWNED through self._passButtons[id]:SetContent.
	-- The arcade button recolours itself in place; a GP row's owned state is
	-- baked into its chip, its pill tint and its pill SHADOW, so the honest
	-- equivalent is a re-render. Registering an adapter here keeps that seam
	-- working without _Prompt knowing which layout is live.
	self._passButtons[pass.id] = {
		SetContent = function(_self: any, _props: any)
			self:_Render()
		end,
	}
end

-- ======================================================================
-- The Pottery Battles counter, on top of the pastel storefront above.
--
-- The shipped lobby's SHOP is not three generic sections — it is a group-
-- gated FREE REWARD, five banner BUNDLES whose contents are live spinning
-- chairs, six PASSES with real value propositions, four BUX packs wearing
-- promo badges, and a pointer at the mid-duel troll bar. This block adds
-- everything in that list the generic build does not already carry, and
-- seeds the generic build's own data with the real catalog so its featured
-- shelf, its pack tiles and its pass ledger stop showing placeholder copy.
--
-- PROMO BADGES: the source shouts BEST DEAL! / BEST VALUE / MOST POPULAR! /
-- EXCLUSIVE!. Every one survives on the same item, in the same slot, with
-- the same meaning — de-shouted, because shouting at this audience is this
-- pack's named failure mode (law 5). PotteryStoreConfig records the mapping.
-- ======================================================================

-- Seed the screen's own data tables from the real catalog. Runs before the
-- page builds, so the generic hero / packs / passes render Pottery Battles
-- content without their builders knowing anything changed.
function PremiumShopScreen:_GPSeedCatalog()
	if self._gpSeeded then
		return
	end
	self._gpSeeded = true

	local starter = Store.Bundles[1]
	self._featured = {
		id = starter.id,
		headline = starter.title,
		blurb = starter.tagline,
		price = starter.robux,
		tag = starter.valueLine, -- <- the source's "WORTH: 299" strike line
		contents = {
			{ icon = "bux", label = "500 Bux" },
			{ icon = "gift", label = "Exclusive chair" },
			{ icon = "crate", label = "Random chair" },
			{ icon = "sparkle", label = starter.badge or "Best value" },
		},
	}

	local packs = {}
	for _, pack in Store.BuxPacks do
		table.insert(packs, {
			id = pack.id,
			amount = pack.amount,
			price = pack.robux,
			-- The promo badge rides where the generic build prints its bonus
			-- line, so MOST POPULAR! / BEST DEAL! keep their exact slots.
			bonus = pack.badge or string.format("%.2f R$ per Bux", pack.robux / pack.amount),
			-- The gem for the small tiers, the gem CHEST for 4,000 and 15,000 —
			-- the source's own art split, carried across.
			icon = pack.iconKey,
		})
	end
	self._packs = packs

	local passes = {}
	local ownedPasses = Store.DemoState.robuxOwned
	for _, pass in Store.Passes do
		local benefit = pass.desc
		if pass.bullets then
			-- VIP is the one pass with a bullet list in the source; a single
			-- row cannot stack four bullets, so they are joined with the
			-- pack's own separator instead of being dropped.
			benefit = table.concat(pass.bullets, "  ·  ")
		end
		table.insert(passes, {
			id = pass.id,
			name = pass.title,
			benefit = benefit,
			price = pass.robux,
			icon = pass.iconKey,
			owned = ownedPasses[pass.id] == true,
			badge = pass.badge,
		})
	end
	self._passes = passes
end

-- Every chair preview this page owns. _ClearRender destroys the scroll's
-- children on each render, so the views are released FIRST — a ViewportFrame
-- whose GuiObject is gone still holds its Model and its spin registration.
function PremiumShopScreen:_GPResetViews()
	GPChairPreview.ReleaseAll(self._gpViews)
	self._gpViews = {}
	if self._gpExtrasStop then
		self._gpExtrasStop()
		self._gpExtrasStop = nil
	end
	self._gpBundleRainbow = nil
end

function PremiumShopScreen:_GPChairSlot(parent: Instance, x: number, chair: any?, caption: string, index: number): any
	local theme = self:GetTheme()
	local accent = if chair then GPStoreParts.RarityColor(theme, chair.rarity) else theme.Colors.Primary

	local slot = UIStyler.Frame("Slot")
	slot.BackgroundTransparency = 1
	slot.Position = UDim2.fromOffset(x, 72)
	slot.Size = UDim2.fromOffset(GP_BUNDLE_SLOT, 104)
	slot.ZIndex = 3
	slot.Parent = parent

	local view = GPChairPreview.New(theme, slot, {
		size = UDim2.fromOffset(GP_BUNDLE_SLOT, 76),
		cornerIndex = index,
		accent = accent,
		gate = self._gpPage and self._gpPage.dim or nil,
		zIndex = 4,
	})
	table.insert(self._gpViews, view)
	if chair then
		GPChairPreview.SetChair(theme, view, chair, GPStoreParts.Rank(chair.rarity))
	end

	local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Caption")
	label.Text = caption
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Position = UDim2.fromOffset(0, 80)
	label.Size = UDim2.fromOffset(GP_BUNDLE_SLOT, 20)
	label.ZIndex = 4
	label.Parent = slot
	return view
end

-- ---- free reward -------------------------------------------------------

function PremiumShopScreen:_GPBuildFreeReward(y: number)
	local theme = self:GetTheme()
	local reward = Store.FreeReward
	local chair = Store.ChairById[reward.chairId]
	self._gpClaimed = self._gpClaimed or false
	self._gpGroupJoined = self._gpGroupJoined or false

	local plate = gpPlate(theme, self._scroll, theme.Colors.SurfaceRaised, 0, self._gpRowShadows)
	plate.Name = "FreeReward"
	plate.Position = UDim2.fromOffset(0, y)
	plate.Size = UDim2.fromOffset(GP_ROW_W, GP_FREE_H)

	-- The GATE line. This is the source's "Join the group to claim!" and it
	-- says the same thing at the same moment; it just does not shout it.
	local gate = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "Gate")
	gate.Text = if self._gpClaimed
		then reward.already
		elseif self._gpGroupJoined then "You are in the group — the reward is yours to take."
		else reward.gate
	gate.TextXAlignment = Enum.TextXAlignment.Left
	gate.Position = UDim2.fromOffset(20, 12)
	gate.Size = UDim2.fromOffset(GP_ROW_W - 40, 28)
	gate.ZIndex = 3
	gate.Parent = plate

	-- Three reward tiles: the exclusive chair as a LIVE spinning model, then
	-- the Cash and the Bux with their archive art.
	local function tile(index: number): Frame
		local face = gpPlate(theme, plate, theme.Colors.Surface, index, nil)
		face.Name = "RewardTile" .. index
		face.Position = UDim2.fromOffset(20 + (index - 1) * (GP_FREE_TILE_W + 14), 48)
		face.Size = UDim2.fromOffset(GP_FREE_TILE_W, GP_FREE_TILE_H)
		face.ZIndex = 3
		return face
	end

	local chairTile = tile(1)
	local view = GPChairPreview.New(theme, chairTile, {
		size = UDim2.fromOffset(GP_FREE_TILE_W - 20, 116),
		position = UDim2.fromOffset(10, 10),
		cornerIndex = 1,
		accent = if chair then GPStoreParts.RarityColor(theme, chair.rarity) else theme.Arcade.Gold,
		gate = self._gpPage and self._gpPage.dim or nil,
		zIndex = 4,
	})
	table.insert(self._gpViews, view)
	if chair then
		GPChairPreview.SetChair(theme, view, chair, GPStoreParts.Rank(chair.rarity))
	end
	-- The source tilts an "EXCLUSIVE!" ribbon over this card. Nothing in this
	-- pack rotates, so the ribbon becomes a petal badge overhanging the
	-- corner — same claim, same position, no tilt.
	local ribbon = GPStoreParts.Badge(theme, chairTile, reward.tag, theme.Arcade.Gold, 0, self._gpRowShadows)
	ribbon.root.AnchorPoint = Vector2.new(0, 0)
	ribbon.root.Position = UDim2.fromOffset(-6, -8)

	local chairName = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "ChairName")
	chairName.Text = if chair then chair.name else "Free chair"
	chairName.TextTruncate = Enum.TextTruncate.AtEnd
	chairName.Position = UDim2.fromOffset(8, 134)
	chairName.Size = UDim2.fromOffset(GP_FREE_TILE_W - 16, 30)
	chairName.ZIndex = 4
	chairName.Parent = chairTile

	local function currencyTile(index: number, iconKey: string, amount: string)
		local face = tile(index)
		local art = gpArt(theme, face, iconKey, 84)
		art.AnchorPoint = Vector2.new(0.5, 0)
		art.Position = UDim2.new(0.5, 0, 0, 18)
		art.ZIndex = 4
		local label = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "Amount")
		label.Text = amount
		label.Position = UDim2.fromOffset(8, 128)
		label.Size = UDim2.fromOffset(GP_FREE_TILE_W - 16, 32)
		label.ZIndex = 4
		label.Parent = face
	end
	currencyTile(2, "cash", "$" .. Store.Comma(reward.cash) .. " Cash")
	currencyTile(3, "bux", Store.Comma(reward.bux) .. " Bux")

	-- CLAIM: green while it can fire, quiet once it has. It never disappears
	-- and it always answers — the persisted claimed state in the source keeps
	-- the button visible and simply stops it firing twice.
	local claimX = 20 + 3 * (GP_FREE_TILE_W + 14) + 10
	local claimW = GP_ROW_W - claimX - 20
	local claim = GPStoreParts.StateChip(theme, plate, {
		position = UDim2.fromOffset(claimX, 62),
		size = UDim2.fromOffset(claimW, 66),
		cornerIndex = 1,
		zIndex = 4,
		sink = self._gpRowShadows,
		onClick = function()
			self:_GPClaimFree()
		end,
	})
	if self._gpClaimed then
		claim.SetState(Store.Copy.stateClaimed, theme.Arcade.GreyClaimed, false)
	else
		claim.SetState(Store.Copy.stateClaim, theme.Colors.Secondary, true)
	end
	claim.label.TextSize = theme.TextSizes.Title

	local note = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "ClaimNote")
	note.Text = self._gpClaimNote or ""
	note.TextWrapped = true
	note.TextYAlignment = Enum.TextYAlignment.Top
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.Position = UDim2.fromOffset(claimX, 138)
	note.Size = UDim2.fromOffset(claimW, 60)
	note.ZIndex = 4
	note.Parent = plate

	local groupLine = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "GroupLine")
	groupLine.Text = string.format("Group %d  ·  one claim per account, forever", reward.groupId)
	groupLine.TextXAlignment = Enum.TextXAlignment.Left
	groupLine.Position = UDim2.fromOffset(claimX, 204)
	groupLine.Size = UDim2.fromOffset(claimW, 20)
	groupLine.ZIndex = 4
	groupLine.Parent = plate
end

-- The gate state machine, faithful to the source's three outcomes: already
-- claimed, not in the group (prompt, then a DEBOUNCED retry line), granted.
function PremiumShopScreen:_GPClaimFree()
	local reward = Store.FreeReward
	if self._gpClaimed then
		self._gpClaimNote = reward.already
		self:_Toast(reward.already, "Info")
		self:_GPRender()
		return
	end
	if not self._gpGroupJoined then
		local last = self._gpPromptedAt or 0
		if os.clock() - last > 10 then
			self._gpPromptedAt = os.clock()
			self._gpClaimNote = reward.prompting
			-- The real build opens GroupService:PromptJoinAsync here and
			-- re-claims when the popup closes; the collection has no group, so
			-- the same handoff is simulated on the same beat.
			task.delay(1.2, function()
				if not self._gpPage then
					return
				end
				self._gpGroupJoined = true
				self._gpClaimNote = "You're in. Press claim once more."
				self:_GPRender()
			end)
		else
			self._gpClaimNote = reward.retry
		end
		self:_GPRender()
		return
	end
	self._gpClaimed = true
	self._gpClaimNote = Store.FreeRewardGranted()
	self:_PlaySound("Success")
	self:_Toast(self._gpClaimNote, "Success")
	self:_GPRender()
end

-- ---- bundles -----------------------------------------------------------

function PremiumShopScreen:_GPBuildBundles(y: number): number
	local theme = self:GetTheme()
	self._gpBundleOwned = self._gpBundleOwned or {}
	local randomViews: { any } = {}
	self._gpBundleRainbow = nil

	for index, bundle in Store.Bundles do
		local owned = self._gpBundleOwned[bundle.id] == true
		local plate = gpPlate(theme, self._scroll, theme.Colors.SurfaceRaised, index, self._gpRowShadows)
		plate.Name = "Bundle_" .. bundle.id
		plate.Position = UDim2.fromOffset(0, y)
		plate.Size = UDim2.fromOffset(GP_ROW_W, GP_BUNDLE_H)

		-- The starter pack is the ONE rainbow wordmark in the shipped shop, on
		-- this pack's own pastel ramp. Everything else keeps ink.
		local title = GPLayoutKit.Text(theme, 26, theme.Colors.TextPrimary, "BundleTitle")
		title.Text = bundle.title
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Position = UDim2.fromOffset(20, 12)
		title.Size = UDim2.fromOffset(420, 32)
		title.ZIndex = 3
		title.Parent = plate
		if bundle.rainbow then
			local gradient = UIChrome.RainbowGradient(theme)
			gradient.Parent = title
			self._gpBundleRainbow = gradient
		end

		local tagline = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Tagline")
		tagline.Text = bundle.tagline
		tagline.TextXAlignment = Enum.TextXAlignment.Left
		tagline.Position = UDim2.fromOffset(20, 44)
		tagline.Size = UDim2.fromOffset(460, 22)
		tagline.ZIndex = 3
		tagline.Parent = plate

		for slotIndex, slot in bundle.slots do
			local x = 20 + (slotIndex - 1) * (GP_BUNDLE_SLOT + 14)
			if slot.kind == "chair" then
				self:_GPChairSlot(plate, x, Store.ChairById[slot.chairId or ""], slot.caption, slotIndex)
			elseif slot.kind == "randomChair" then
				-- The RANDOM CHAIR slot cycles the whole catalog, one every
				-- five seconds — the source's own deferred cycler, moved onto
				-- the shared ticker.
				local view = self:_GPChairSlot(plate, x, Store.Chairs[1], slot.caption, slotIndex)
				table.insert(randomViews, view)
			else
				local face = UIStyler.Frame("Slot")
				face.BackgroundTransparency = 1
				face.Position = UDim2.fromOffset(x, 72)
				face.Size = UDim2.fromOffset(GP_BUNDLE_SLOT, 104)
				face.ZIndex = 3
				face.Parent = plate
				local art = gpArt(theme, face, slot.iconKey or "bux", 64)
				art.AnchorPoint = Vector2.new(0.5, 0)
				art.Position = UDim2.new(0.5, 0, 0, 6)
				art.ZIndex = 4
				local caption = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "Caption")
				caption.Text = slot.caption
				caption.Position = UDim2.fromOffset(0, 80)
				caption.Size = UDim2.fromOffset(GP_BUNDLE_SLOT, 20)
				caption.ZIndex = 4
				caption.Parent = face
			end
		end

		-- The value line, right-aligned where the source strikes through its
		-- old price. RichText strike is kept — it is the claim, not decoration.
		local value = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "Value")
		value.RichText = bundle.wasRobux ~= nil
		value.Text = if bundle.wasRobux
			then string.format("%s  <s>%d</s>", bundle.valueLine, bundle.wasRobux)
			else bundle.valueLine
		value.TextXAlignment = Enum.TextXAlignment.Right
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.new(1, -20, 0, 14)
		value.Size = UDim2.fromOffset(420, 28)
		value.ZIndex = 3
		value.Parent = plate

		if bundle.badge then
			local badge = GPStoreParts.Badge(theme, plate, bundle.badge, theme.Arcade.Gold, index, self._gpRowShadows)
			badge.root.AnchorPoint = Vector2.new(1, 0)
			badge.root.Position = UDim2.fromOffset(GP_ROW_W - 20, -8)
		end

		if owned then
			-- OWNED collapses the buy control IN PLACE. These are repeatable
			-- dev products selling ONE-TIME goods: a second tap would charge
			-- again and grant nothing, which is the bug the source guards.
			local chip = gpChip(theme, plate, theme.Arcade.GreyOwned, Store.Copy.stateOwned, index + 1)
			chip.root.AnchorPoint = Vector2.new(1, 1)
			chip.root.Position = UDim2.new(1, -20, 1, -16)
			chip.root.Size = UDim2.fromOffset(200, 46)
			chip.label.TextSize = theme.TextSizes.Button
		else
			local price = gpPriceButton(theme, plate, self._gpRowShadows, function()
				if self._gpBundleOwned[bundle.id] then
					self:_Toast("You already own the " .. bundle.title .. ".", "Info")
					return
				end
				self._gpBundleOwned[bundle.id] = true
				self:_Prompt("product", bundle.id)
				self:_GPRender()
			end)
			price.root.AnchorPoint = Vector2.new(1, 1)
			price.root.Position = UDim2.new(1, -20, 1, -16)
			price.root.Size = UDim2.fromOffset(200, 46)
			price.pill.icon.Image = IconArchive.Id("robux") or ""
			price.pill.amount.Text = Store.Comma(bundle.robux)
		end

		y += GP_BUNDLE_H + (if index < #Store.Bundles then GP_BUNDLE_GAP else 0)
	end

	-- ONE ticker handler for both ambient effects on this section: the random
	-- chair cycler and the starter pack's rainbow wordmark. Two registrations
	-- for two effects on one page is exactly the pattern UITicker exists to
	-- prevent.
	if self._gpExtrasStop then
		self._gpExtrasStop()
		self._gpExtrasStop = nil
	end
	if #randomViews > 0 or self._gpBundleRainbow then
		local elapsed = 0
		local phase = 0
		local cursor = 1
		self._gpExtrasStop = UITicker.Register(function(dt: number)
			local gradient = self._gpBundleRainbow
			if gradient then
				local host = gradient.Parent
				if host and host:IsA("GuiObject") and UIChrome.IsOnScreen(host) then
					phase = (phase + 0.45 * dt) % 1
					gradient.Offset = Vector2.new(phase, 0)
				end
			end
			if #randomViews == 0 then
				return
			end
			elapsed += dt
			if elapsed < GP_RANDOM_CYCLE then
				return
			end
			elapsed -= GP_RANDOM_CYCLE
			cursor = (cursor % #Store.Chairs) + 1
			local chair = Store.Chairs[cursor]
			for _, view in randomViews do
				if view.alive then
					GPChairPreview.SetAccent(view, GPStoreParts.RarityColor(theme, chair.rarity))
					GPChairPreview.SetChair(theme, view, chair, GPStoreParts.Rank(chair.rarity))
				end
			end
		end)
	end

	return y
end

-- A style rebuild destroys the Gui, but UIShadow BUDGET counts live in
-- StyleKit.Capabilities and only fall when a handle is released — so every
-- GP shadow handle is handed back here. Chair previews own a Model and a
-- registration in the shared spin driver, so they are released too.
function PremiumShopScreen:_OnTeardown()
	self:_GPResetViews()
	GPLayoutKit.ReleaseShadows(self._gpRowShadows)
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	self._gpPage = nil
	self._gpSeeded = false
end

return PremiumShopScreen
