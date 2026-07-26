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

local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)

type ContentChip = { icon: string, label: string }
type FeaturedData = {
	id: string,
	headline: string,
	blurb: string,
	price: number,
	tag: string?,
	contents: { ContentChip },
}
type PackData = { id: string, amount: number, price: number, bonus: string? }
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
	end
end

function PremiumShopScreen:_OnHide()
	if self._rainbowConn then
		self._rainbowConn:Disconnect()
		self._rainbowConn = nil
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
	for _, component in self._components :: { any } do
		component:Destroy()
	end
	table.clear(self._components)
	UIScreenBase.Destroy(self)
end

return PremiumShopScreen
