--!strict
-- CRATE REVEAL — the crate-opening celebration, ported from Brick Game's
-- LobbyHud reveal overlay (+ CrateFx / CrateConfig) onto the Pottery Clash
-- chrome. The source choreography is preserved exactly (doc §5.3):
--
--   * first page  — the card drops from y −0.3 with 0.55s Bounce Out, its
--     scale pops to 1.28 in 0.16s Quad, then settles to 1 in 0.4s Back Out;
--   * later pages — no drop, just 0.75 → 1 in 0.35s Back Out;
--   * every page  — 36 confetti squares (8–14px, 6 theme colours) tween
--     1.6–2.4s LINEAR from above the top edge to below the bottom, with ±60px
--     horizontal drift and ±360° spin.
--
-- A multi-open (5×/10×) arrives as a queue and PAGES THROUGH THIS ONE CARD —
-- the CONTINUE button reads "NEXT (i/n)" until the last item. Page dots under
-- the card show where you are. Every confetti square, tween and RenderStepped
-- connection is torn down in _OnHide, so a closed reveal costs nothing.
--
-- GP (theme.LayoutKit == "GP") retells the whole flow as THE KILN FIRING — the
-- crate preview becomes the loading bay (what is on the shelf, at what odds,
-- x1/x5/x10, and what it costs), and the reveal becomes a seven-stage firing
-- ceremony. See the GP section at the bottom of this file.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIAssets = require(script.Parent.Parent.Config.UIAssets)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local UITicker = require(script.Parent.Parent.Framework.UITicker)
local UIScreenBase = require(script.Parent.UIScreenBase)

export type RevealItem = {
	name: string,
	icon: string?,
	rarity: string?,
	note: string?,
	-- GP extras. `kind = "title"` is the source's TITLE UNLOCKED reveal, which
	-- shares this one card; `value`/`valueCurrency` print the reward receipt.
	kind: string?,
	value: number?,
	valueCurrency: string?,
	req: string?,
}

-- One entry of the crate's advertised drop table (the source's CRATE menu).
export type OddsEntry = {
	name: string,
	rarity: string?,
	pct: number,
	icon: string?,
}

export type CrateDef = {
	name: string,
	accent: Color3?,
	cashCost: number?,
	buxCost: number?,
	robuxCost: number?,
	productId: number?,
}

-- Fixed px at the 1650×1020 baseline.
local CARD_W, CARD_H = 400, 470
local DOT = 12

local CARD_OFF = UDim2.new(0.5, 0, -0.3, 0)
local CARD_HOME = UDim2.fromScale(0.5, 0.5)
local DROP = TweenInfo.new(0.55, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out)
local POP = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SETTLE = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local REPOP = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FIRST_FROM_SCALE = 0.55
local PAGE_FROM_SCALE = 0.75

local CONFETTI_COUNT = 36
local CONFETTI_MIN, CONFETTI_MAX = 8, 14
local CONFETTI_DRIFT = 60

-- Rarity ramp (doc §3.3: rarity colours tint stroke + label). The shop accent
-- rotation carries the low/mid tiers; the top two claim gold and magenta.
local RARITY_RANK: { [string]: number } = {
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
	Mythic = 6,
	Exclusive = 6,
}

local function rarityAccent(theme: Types.UITheme, rarity: string?): Color3
	local a = theme.Arcade
	local rank = RARITY_RANK[rarity or ""]
	if not rank then
		return a.Gold
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

-- Legendary and up get the golden icon variant and the gold sunburst.
local function isHighRarity(rarity: string?): boolean
	return (RARITY_RANK[rarity or ""] or 0) >= 5
end

local DEMO_ITEMS: { RevealItem } = {
	{ name = "Golden Kiln Throne", icon = "crown", rarity = "Legendary", value = 2500, valueCurrency = "Cash" },
	{ name = "Neon Gamer Chair", icon = "bolt", rarity = "Rare", value = 900, valueCurrency = "Cash" },
	{ name = "Clay Throne", icon = "potion", rarity = "Uncommon", note = "Duplicate  +12 shards", value = 12, valueCurrency = "Clay" },
}

-- The loading-bay demo set: the source CRATE menu's drop table, commonest
-- first, plus its price row. Data lives HERE (or arrives through Show), never
-- as literals sprinkled through the build.
local DEMO_CRATE: CrateDef = {
	name = "Butter Glaze Kiln",
	cashCost = 750,
	buxCost = 45,
	robuxCost = 79,
	productId = 0,
}

local DEMO_ODDS: { OddsEntry } = {
	{ name = "Speckled Stool", rarity = "Common", pct = 38.5, icon = "potion" },
	{ name = "Sage Studio Chair", rarity = "Common", pct = 24, icon = "leaf" },
	{ name = "Blush Wheel Seat", rarity = "Uncommon", pct = 16.25, icon = "heart" },
	{ name = "Matcha Lounger", rarity = "Uncommon", pct = 10.5, icon = "crystal" },
	{ name = "Sugarplum Perch", rarity = "Rare", pct = 6.25, icon = "star" },
	{ name = "Neon Gamer Chair", rarity = "Rare", pct = 2.75, icon = "bolt" },
	{ name = "Rose Gold Wheel", rarity = "Epic", pct = 1.2, icon = "medal" },
	{ name = "Golden Kiln Throne", rarity = "Legendary", pct = 0.45, icon = "crown" },
	{ name = "Kiln God's Seat", rarity = "Mythic", pct = 0.1, icon = "trophy" },
}

local DEMO_COUNTS: { number } = { 1, 5, 10 }

local CrateRevealScreen = setmetatable({}, { __index = UIScreenBase })
CrateRevealScreen.__index = CrateRevealScreen

function CrateRevealScreen.new()
	local self = UIScreenBase.new("CrateRevealScreen", 62)
	self._items = DEMO_ITEMS :: { RevealItem }
	self._crateName = "GOLDEN CRATE"
	self._gp = false
	self._crate = DEMO_CRATE :: CrateDef
	self._odds = DEMO_ODDS :: { OddsEntry }
	self._counts = DEMO_COUNTS :: { number }
	self._openCount = 1
	self._paidRandomAllowed = nil :: boolean?
	self._onOpen = nil :: ((count: number, currency: string) -> ())?
	self._page = 1
	self._tweens = {} :: { Tween }
	self._confetti = {} :: { Frame }
	self._confettiTweens = {} :: { Tween }
	self._dots = {} :: { Frame }
	self._spinConn = nil :: RBXScriptConnection?
	return setmetatable(self, CrateRevealScreen)
end

-- ========================================================================
-- Build
-- ========================================================================

function CrateRevealScreen:_BuildContent()
	-- GP layout language: the kiln firing ceremony + the loading bay preview.
	if self:LayoutKit() == "GP" then
		self._gp = true
		self:_BuildGPLayout()
		return
	end
	self._gp = false

	local theme = self:GetTheme()

	-- The §7.4 modal dim. Confetti is parented HERE (not to the card) so it
	-- rains across the whole screen, exactly like the source overlay.
	local dim = UIStyler.Frame("Dim")
	dim.BackgroundColor3 = theme.Colors.Overlay
	dim.BackgroundTransparency = 0.45
	dim.ZIndex = 60
	dim.Parent = self.Root
	self._dim = dim

	local card = UIStyler.Frame("Card")
	card.BackgroundColor3 = theme.Arcade.Panel
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = CARD_HOME
	card.Size = UDim2.fromOffset(CARD_W, CARD_H)
	card.ZIndex = 61
	UIChrome.GlassGradient().Parent = card
	card.Parent = dim
	self._card = card

	-- The rarity ring: the ONE stroke this screen re-colours at runtime, because
	-- rarity IS the card's identity (doc §3.3). Policy thickness/mode still come
	-- from UIChrome — only the colour is swapped per item, in _RenderPage.
	local ring = UIChrome.Stroke(theme, "Arcade", "Selection")
	ring.Parent = card
	self._ring = ring

	local scale = Instance.new("UIScale")
	scale.Parent = card
	self._scale = scale

	local crate = UIChrome.Text("Crate", 22, theme.Arcade.IceBlue)
	crate.Text = ""
	crate.TextTruncate = Enum.TextTruncate.AtEnd
	crate.Position = UDim2.fromOffset(12, 14)
	crate.Size = UDim2.new(1, -24, 0, 26)
	crate.ZIndex = 62
	crate.Parent = card
	self._crateLabel = crate

	-- Art well: gold sunburst (doc §10, 45°/s, visibility-gated) behind the
	-- item icon.
	local art = UIStyler.Frame("Art")
	art.BackgroundColor3 = theme.Arcade.NearBlack
	art.AnchorPoint = Vector2.new(0.5, 0)
	art.Position = UDim2.new(0.5, 0, 0, 48)
	art.Size = UDim2.fromOffset(CARD_W - 48, 200)
	art.ZIndex = 62
	UIChrome.Stroke(theme, "Arcade").Parent = art
	art.Parent = card
	self._art = art

	local iconSlot = UIStyler.Frame("IconSlot")
	iconSlot.BackgroundTransparency = 1
	iconSlot.AnchorPoint = Vector2.new(0.5, 0.5)
	iconSlot.Position = UDim2.fromScale(0.5, 0.5)
	iconSlot.Size = UDim2.fromOffset(170, 170)
	iconSlot.ZIndex = 64
	iconSlot.Parent = art
	self._iconSlot = iconSlot

	local name = UIChrome.Text("Name", 26, theme.Colors.TextPrimary)
	name.Text = ""
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(12, 258)
	name.Size = UDim2.new(1, -24, 0, 34)
	name.ZIndex = 63
	name.Parent = card
	self._name = name

	local rarity = UIChrome.Text("Rarity", 20, theme.Arcade.Gold)
	rarity.Text = ""
	rarity.Position = UDim2.fromOffset(12, 294)
	rarity.Size = UDim2.new(1, -24, 0, 26)
	rarity.ZIndex = 63
	rarity.Parent = card
	self._rarity = rarity

	local note = UIChrome.Text("Note", 18, theme.Arcade.IceBlue)
	note.Text = ""
	note.Position = UDim2.fromOffset(12, 322)
	note.Size = UDim2.new(1, -24, 0, 24)
	note.ZIndex = 63
	note.Parent = card
	self._note = note

	local dots = UIStyler.Frame("Dots")
	dots.BackgroundTransparency = 1
	dots.AnchorPoint = Vector2.new(0.5, 0)
	dots.Position = UDim2.new(0.5, 0, 0, 354)
	dots.Size = UDim2.new(1, -24, 0, DOT + 4)
	dots.ZIndex = 63
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
	}).Parent = dots
	dots.Parent = card
	self._dotRow = dots

	self._continue = UIButtonComponent.new()
	self._continue:Create(card, {
		text = "CONTINUE",
		variant = "Green",
		size = UDim2.fromOffset(200, 52),
		position = UDim2.new(0.5, 0, 1, -18),
		anchorPoint = Vector2.new(0.5, 1),
		onClick = function()
			self:_Advance()
		end,
	})
	self._continue.Root.ZIndex = 63
end

-- ========================================================================
-- Confetti (doc §5.3) — fire-and-forget, but every square is tracked so hide
-- can destroy it mid-flight.
-- ========================================================================

function CrateRevealScreen:_ConfettiColors(): { Color3 }
	local theme = self:GetTheme()
	local colors = table.clone(theme.Arcade.Rainbow)
	table.insert(colors, theme.Arcade.Magenta) -- the source's sixth colour
	return colors
end

function CrateRevealScreen:_ClearConfetti()
	for _, tween in self._confettiTweens do
		tween:Cancel()
	end
	table.clear(self._confettiTweens)
	for _, square in self._confetti do
		square:Destroy()
	end
	table.clear(self._confetti)
end

function CrateRevealScreen:_BurstConfetti()
	local colors = self:_ConfettiColors()
	for _ = 1, CONFETTI_COUNT do
		local size = math.random(CONFETTI_MIN, CONFETTI_MAX)
		local square = UIStyler.Frame("Confetti")
		square.BackgroundColor3 = colors[math.random(#colors)]
		square.Position = UDim2.new(math.random(), 0, 0, -20)
		square.Size = UDim2.fromOffset(size, size)
		square.Rotation = math.random(0, 360)
		square.ZIndex = 65
		square.Parent = self._dim
		table.insert(self._confetti, square)

		local tween = TweenService:Create(
			square,
			TweenInfo.new(math.random(160, 240) / 100, Enum.EasingStyle.Linear),
			{
				Position = UDim2.new(
					square.Position.X.Scale,
					math.random(-CONFETTI_DRIFT, CONFETTI_DRIFT),
					1,
					40
				),
				Rotation = square.Rotation + math.random(-360, 360),
			}
		)
		table.insert(self._confettiTweens, tween)
		tween.Completed:Once(function()
			local index = table.find(self._confetti, square)
			if index then
				table.remove(self._confetti, index)
			end
			square:Destroy()
		end)
		tween:Play()
	end
end

-- ========================================================================
-- Paging
-- ========================================================================

function CrateRevealScreen:_CancelTweens()
	for _, tween in self._tweens do
		tween:Cancel()
	end
	table.clear(self._tweens)
end

-- The entrance beats. firstPage plays the full drop → pop → settle; later
-- queue pages get the quick re-pop only.
function CrateRevealScreen:_Animate(firstPage: boolean)
	self:_CancelTweens()
	local card, scale = self._card, self._scale
	if firstPage then
		card.Position = CARD_OFF
		scale.Scale = FIRST_FROM_SCALE
		local drop = TweenService:Create(card, DROP, { Position = CARD_HOME })
		table.insert(self._tweens, drop)
		drop.Completed:Once(function()
			if not self:IsVisible() then
				return
			end
			local pop = TweenService:Create(scale, POP, { Scale = 1.28 })
			table.insert(self._tweens, pop)
			pop.Completed:Once(function()
				if not self:IsVisible() then
					return
				end
				local settle = TweenService:Create(scale, SETTLE, { Scale = 1 })
				table.insert(self._tweens, settle)
				settle:Play()
			end)
			pop:Play()
		end)
		drop:Play()
	else
		card.Position = CARD_HOME
		scale.Scale = PAGE_FROM_SCALE
		local repop = TweenService:Create(scale, REPOP, { Scale = 1 })
		table.insert(self._tweens, repop)
		repop:Play()
	end
end

function CrateRevealScreen:_RenderDots()
	for _, dot in self._dots do
		dot:Destroy()
	end
	table.clear(self._dots)
	local count = #self._items
	self._dotRow.Visible = count > 1
	if count <= 1 then
		return
	end
	local theme = self:GetTheme()
	for i = 1, count do
		local dot = UIStyler.Frame("Dot" .. i)
		dot.BackgroundColor3 = if i == self._page then theme.Arcade.Gold else theme.Arcade.GreyOwned
		dot.Size = UDim2.fromOffset(DOT, DOT)
		dot.LayoutOrder = i
		dot.ZIndex = 64
		UIChrome.Corner("Arcade", "Pill").Parent = dot
		dot.Parent = self._dotRow
		table.insert(self._dots, dot)
	end
end

function CrateRevealScreen:_RenderPage(page: number, firstPage: boolean)
	local theme = self:GetTheme()
	local item = self._items[page]
	if not item then
		return
	end
	self._page = page

	local accent = rarityAccent(theme, item.rarity)
	local golden = isHighRarity(item.rarity)
	self._ring.Color = accent

	-- Text FIRST: even if art hiccups, the card still announces the prize.
	self._crateLabel.Text = self._crateName
	self._name.Text = item.name
	self._rarity.Text = string.upper(item.rarity or "")
	self._rarity.TextColor3 = accent
	self._note.Text = item.note or "NEW!"
	self._note.TextColor3 = if item.note then theme.Arcade.IceBlue else theme.Arcade.MoneyGreen

	if self._spinConn then
		self._spinConn:Disconnect()
		self._spinConn = nil
	end
	self._iconSlot:ClearAllChildren()
	if golden then
		-- Parented INTO the square icon slot so the sunburst stays round (the
		-- well itself is a wide rectangle) and the next page's ClearAllChildren
		-- takes it with the icon.
		local _, spin = UIAssets.SunburstBehind(self._iconSlot, theme.Arcade.SunburstGold, 0.55, 45)
		self._spinConn = spin
	end
	local icon = IconArchive.Image(self._iconSlot, item.icon or "chest", 140, { golden = golden })
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.ZIndex = 65

	local last = page >= #self._items
	self._continue:SetContent({
		text = if last then "CONTINUE" else string.format("NEXT  (%d/%d)", page, #self._items),
		variant = if last then "Green" else "Blue",
	})

	self:_RenderDots()
	self:_Animate(firstPage)
	self:_BurstConfetti()
	self:_PlaySound("Success")
end

function CrateRevealScreen:_Advance()
	if self._page < #self._items then
		self:_RenderPage(self._page + 1, false)
	else
		self.ScreenController:HideScreen("crateReveal")
	end
end

-- ========================================================================
-- Lifecycle
-- ========================================================================

function CrateRevealScreen:_OnShow(data: any?)
	if type(data) == "table" then
		if type(data.items) == "table" and #data.items > 0 then
			self._items = data.items
		end
		if type(data.crateName) == "string" then
			self._crateName = data.crateName
		end
	end
	if self._gp then
		self:_GPShow(data)
		return
	end
	self:_ClearConfetti()
	self:_RenderPage(1, true)
end

function CrateRevealScreen:_OnHide()
	if self._gp then
		self:_GPHide()
		return
	end
	self:_CancelTweens()
	self:_ClearConfetti()
	if self._spinConn then
		self._spinConn:Disconnect()
		self._spinConn = nil
	end
	if self._card then
		self._card.Position = CARD_HOME
		self._scale.Scale = 1
	end
end

function CrateRevealScreen:Update(data: any)
	if self._built and self:IsVisible() then
		self:_OnShow(data)
	end
end

function CrateRevealScreen:Destroy()
	self:_OnHide()
	if self._built then
		self:_OnTeardown()
	end
	if self._continue then
		self._continue:Destroy()
		self._continue = nil
	end
	UIScreenBase.Destroy(self)
end

-- ======================================================================
-- GP layout (theme.LayoutKit == "GP") — THE KILN FIRING.
--
-- Same flow, pottery vocabulary, more data. The screen has three MODES and
-- one Page; which one shows is decided entirely by the Show payload:
--
--   preview  — the LOADING BAY. The source CRATE menu: the crate's name, its
--              whole drop table (commonest → rarest, "%.2f%%" each, with a
--              chance meter per row), the x1/x5/x10 count selector that
--              multiplies the prices, and one price button per currency.
--              Bux/Robux are PAID RANDOM items and stay hidden unless the
--              caller says the policy verdict came back clear — nil means the
--              verdict is still in flight, and that fails CLOSED, exactly as
--              the source does with the PaidRandomRestricted attribute. Robux
--              is always a single open (a dev product is one receipt), and a
--              missing product id answers "Coming soon!" in place.
--   ceremony — THE FIRING, seven stages, skippable at every one of them:
--              load (the bisque piece goes on the shelf) → close (the door
--              swings shut) → fire (an EffectShadows.glow transparency ramp
--              blooms while the chamber's fill shifts terracotta → butter →
--              hot rose, with the temperature and the firing progress running
--              live on two StatRows) → open → emerge (the piece comes out and
--              a sheen sweep wipes across it to reveal the glaze) → celebrate
--              (rarity-tiered: a soft chime, a sparkle burst, or the full
--              screen sunburst + confetti for the top tier) → receipt.
--   failure  — the kiln stays cold. The source's two exact refusals:
--              "Not enough to open that crate." and "Crates can only be
--              opened with Cash on your account."
--
-- SERVER-CONFIRMED ONLY: the ceremony renders the items it is handed. It
-- never rolls, weights, or decides anything — the price buttons just call
-- back out with (count, currency) and wait to be told what came out.
--
-- ONE UITicker handler drives every continuous thing here (door slide, heat
-- ramp, temperature count, sheen sweep, sunburst spin, sparkle fade). The
-- confetti fall is the one TweenService flight, tracked so a skip can kill it
-- mid-air. Every shadow lands in self._gpShadows and is Released at teardown.
-- ======================================================================

local GP_PAGE = Vector2.new(1180, 742)
local GP_STAGES = { "load", "close", "fire", "open", "emerge", "celebrate", "receipt" }
local GP_NEXT_STAGE: { [string]: string } = {
	load = "close",
	close = "fire",
	fire = "open",
	open = "emerge",
	emerge = "celebrate",
	celebrate = "receipt",
}
local GP_STAGE_RANK: { [string]: number } = {}
for i, stage in GP_STAGES do
	GP_STAGE_RANK[stage] = i
end

-- Choreography defaults for packs without a DialectTokens.kiln namespace.
local GP_KILN: { [string]: number } = {
	loadTime = 0.75,
	closeTime = 0.45,
	fireTime = 1.9,
	openTime = 0.5,
	emergeTime = 0.85,
	celebrateSoft = 0.55,
	celebrateSparkle = 1,
	celebrateSunburst = 1.6,
	restTemperature = 24,
	peakTemperature = 1240,
	sparkleCount = 10,
	sunburstDegPerSec = 22,
	confettiCount = 36,
	confettiMin = 8,
	confettiMax = 14,
	confettiDrift = 60,
	confettiMinTime = 1.6,
	confettiMaxTime = 2.4,
}

local GP_CHAMBER = Vector2.new(430, 330)
local GP_ODDS_ROW_H = 56
local GP_RECEIPT_ROW_H = 34
-- A rarity colour in this pack is a FILL colour: the ramp starts at cream so a
-- big shape reads soft. Pulled straight onto TEXT it disappears — cream (the
-- Common tier) on blush measures 1.05:1, which is the same near-white-on-pastel
-- failure the pack's header corrects TextOnPrimary for. So anything that has to
-- be READ takes the accent pulled toward ink; only the big shapes keep the raw
-- pastel. INK_PULL is the text pull (clears 4.5:1); METER_PULL is the lighter
-- pull a progress bar needs to separate from the cream track it sits in.
local GP_INK_PULL = 0.7
local GP_METER_PULL = 0.45
-- The source's ultra-rare rule: a drop card under 1% wears a heavier edge.
local GP_ULTRA_PCT = 1
local GP_ULTRA_STROKE = 4

local function gpToken(theme: Types.UITheme, key: string): number
	local dialects = (theme :: any).DialectTokens
	local kiln = dialects and dialects.kiln
	local value = kiln and kiln[key]
	if typeof(value) == "number" then
		return value
	end
	return GP_KILN[key]
end

-- The pack's own rarity ramp (cream → sage → sky → lavender → rose-gold),
-- with the two top tiers claiming butter and magenta so a jackpot never reads
-- as "just another pastel".
local function gpRarityColor(theme: Types.UITheme, rarity: string?): Color3
	local dialects = (theme :: any).DialectTokens
	local ramp = dialects and dialects.rarity
	local rank = RARITY_RANK[rarity or ""] or 1
	if rank >= 6 then
		return theme.Arcade.Magenta
	elseif rank == 5 then
		return theme.Arcade.Gold
	end
	if typeof(ramp) == "table" and #ramp > 0 then
		return ramp[math.clamp(rank, 1, #ramp)]
	end
	return rarityAccent(theme, rarity)
end

-- The readable form of a rarity accent (see GP_INK_PULL). Keeps the hue, drops
-- the value far enough to survive on cream.
local function gpReadable(theme: Types.UITheme, accent: Color3, pull: number): Color3
	return accent:Lerp(theme.Colors.TextPrimary, pull)
end

-- 1 = soft chime, 2 = sparkle burst, 3 = sunburst + confetti.
local function gpTier(rarity: string?): number
	local rank = RARITY_RANK[rarity or ""] or 1
	if rank >= 5 then
		return 3
	elseif rank >= 3 then
		return 2
	end
	return 1
end

local function gpLerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- LAW 5: no all-caps body copy. Crate and piece names arrive from a config the
-- arcade face wants SHOUTED ("GOLDEN CRATE"), and one table feeds both faces —
-- so the pastel branch re-cases where it draws rather than forking the data.
-- Only a string with NO lowercase at all is touched: "Kiln God's Seat" and
-- "Butter Glaze Kiln" pass through whole.
local function gpSentence(text: string): string
	if string.find(text, "%l") ~= nil then
		return text
	end
	local words: { string } = {}
	for word in string.gmatch(text, "%S+") do
		table.insert(words, string.upper(string.sub(word, 1, 1)) .. string.lower(string.sub(word, 2)))
	end
	return table.concat(words, " ")
end

-- UIStyler.Frame is born PURE WHITE, which this pack forbids outright, so
-- nothing here may use it bare.
local function gpSurface(name: string, fill: Color3, transparency: number?): Frame
	local frame = UIStyler.Frame(name)
	frame.BackgroundColor3 = fill
	frame.BackgroundTransparency = transparency or 0
	return frame
end

-- IconArchive's glyph fallback paints white-on-black — repaint it in ink so a
-- pending upload can't smuggle the two banned colours onto a pastel page.
local function gpIcon(theme: Types.UITheme, parent: Instance, key: string, sizePx: number, golden: boolean?): GuiObject
	local icon = IconArchive.Image(parent, key, sizePx, { golden = golden })
	if icon:IsA("TextLabel") then
		icon.TextColor3 = theme.Colors.TextPrimary
		icon.TextStrokeTransparency = 1
	end
	return icon
end

type GPButton = {
	root: TextButton,
	chip: Frame,
	label: TextLabel,
	-- The budget handle, exposed because the count/price rows are REBUILT on
	-- every price change: destroying the instance alone leaves the shadow
	-- counter high forever (Capabilities only decrements on Release).
	shadow: any,
	SetText: (string) -> (),
	SetFill: (Color3) -> (),
	SetDimmed: (boolean) -> (),
}

-- A petal chip that happens to be pressable. The BUTTON itself stays fully
-- transparent and the fill lives on the chip child: UIStyleEnforcer backstops
-- any SOLID GuiButton with a black 2px stroke, which would violate law 1 on
-- sight, and a transparent button never trips it.
local function gpButton(theme: Types.UITheme, parent: Instance, opts: {
	name: string?,
	text: string,
	fill: Color3?,
	size: UDim2,
	position: UDim2?,
	anchorPoint: Vector2?,
	index: number?,
	textSize: number?,
	layoutOrder: number?,
	zIndex: number?,
	onClick: (() -> ())?,
	sink: { any }?,
}): GPButton
	local fill = opts.fill or theme.Colors.Primary
	local zIndex = opts.zIndex or 6

	local root = Instance.new("TextButton")
	root.Name = opts.name or "GPButton"
	root.BackgroundTransparency = 1
	root.Text = ""
	root.AutoButtonColor = false
	root.Size = opts.size
	root.Position = opts.position or UDim2.fromScale(0, 0)
	root.AnchorPoint = opts.anchorPoint or Vector2.new(0, 0)
	root.LayoutOrder = opts.layoutOrder or 0
	root.ZIndex = zIndex
	root.Parent = parent

	local chip = gpSurface("Chip", fill, 0)
	chip.Size = UDim2.fromScale(1, 1)
	chip.ZIndex = zIndex
	chip.Parent = root
	GPLayoutKit.Petal(theme, chip, opts.index or 0)
	local stroke = GPLayoutKit.SoftStroke(theme, chip)
	local shadow = GPLayoutKit.Shadow(theme, chip, "sm", opts.sink, fill)

	-- Body-sized copy on rose MUST be TextPrimary (5.15:1); TextOnPrimary
	-- measures 2.14:1 there and is illegal on a button caption.
	local label = GPLayoutKit.Text(theme, opts.textSize or theme.TextSizes.Button, theme.Colors.TextPrimary, "Label")
	label.Text = opts.text
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = zIndex + 1
	label.Parent = chip

	if opts.onClick then
		root.Activated:Connect(opts.onClick)
	end
	UIChrome.Animate(theme, root, chip)

	local api: GPButton
	api = {
		root = root,
		chip = chip,
		label = label,
		shadow = shadow,
		SetText = function(text: string)
			label.Text = text
		end,
		SetFill = function(color: Color3)
			local deep = GPLayoutKit.Deepen(theme, color, 1)
			chip.BackgroundColor3 = color
			stroke.Color = deep
			shadow.Instance.Color = deep
		end,
		SetDimmed = function(dimmed: boolean)
			-- Dimmed in place, never removed: the tap still answers.
			label.TextColor3 = if dimmed then theme.Colors.TextSecondary else theme.Colors.TextPrimary
			chip.BackgroundTransparency = if dimmed then 0.35 else 0
			shadow:SetEnabled(not dimmed)
		end,
	}
	return api
end

function CrateRevealScreen:_BuildGPLayout()
	local theme = self:GetTheme()

	-- Classic leftovers must not leak into the pastel page.
	if self._continue then
		self._continue:Destroy()
		self._continue = nil
	end
	self._dim = nil
	self._card = nil
	self._ring = nil
	self._dotRow = nil

	self._gpShadows = {} :: { any }
	self._gpOddsRows = {} :: { any }
	self._gpOddsPool = {} :: { any }
	self._gpReceiptRows = {} :: { any }
	self._gpReceiptPool = {} :: { any }
	self._gpCountChips = {} :: { any }
	self._gpPriceButtons = {} :: { any }
	self._gpSparkles = {} :: { ImageLabel }
	self._gpConfetti = {} :: { GuiObject }
	self._gpConfettiTweens = {} :: { Tween }
	self._gpMode = "preview"
	self._gpStage = "idle"
	self._gpStageClock = 0
	self._gpStageDuration = 0
	self._gpTier = 1
	self._gpTemperature = gpToken(theme, "restTemperature")

	local page = GPLayoutKit.Page(theme, self.Root, {
		titleText = self._crateName,
		subtitleText = "Load a bisque piece and let the kiln decide.",
		sizePx = GP_PAGE,
		onClose = function()
			self.ScreenController:HideScreen("crateReveal")
		end,
	})
	self._gpPage = page
	for _, handle in page.shadows do
		table.insert(self._gpShadows, handle)
	end
	page.dim.ZIndex = 1
	page.panel.ZIndex = 5

	-- Celebration furniture lives OUTSIDE the panel: the panel clips (rows must
	-- never spill past the cream plate) and a sunburst that stops at the plate
	-- edge is not a celebration. Sunburst under the panel, confetti over it.
	local burstLayer = gpSurface("BurstLayer", theme.Colors.Background, 1)
	burstLayer.Size = UDim2.fromScale(1, 1)
	burstLayer.Visible = false
	burstLayer.ZIndex = 2
	burstLayer.Parent = self.Root
	self._gpBurstLayer = burstLayer

	local sunburst = GPLayoutKit.Slice(theme, "sunburstSoft", theme.Arcade.SunburstGold, "Sunburst")
	sunburst.AnchorPoint = Vector2.new(0.5, 0.5)
	sunburst.Position = UDim2.fromScale(0.5, 0.5)
	sunburst.Size = UDim2.fromOffset(1500, 1500)
	sunburst.ImageTransparency = 0.55
	sunburst.ZIndex = 2
	sunburst.Parent = burstLayer
	self._gpSunburst = sunburst

	local fxLayer = gpSurface("FxLayer", theme.Colors.Background, 1)
	fxLayer.Size = UDim2.fromScale(1, 1)
	fxLayer.ZIndex = 60
	fxLayer.Parent = self.Root
	self._gpFxLayer = fxLayer

	self:_BuildGPCeremony(theme, page.content)
	self:_BuildGPPreview(theme, page.content)
	self:_BuildGPFailure(theme, page.content)

	-- SKIPPABLE AT EVERY STAGE. The catcher sits above the panel and below the
	-- skip chip; it is hidden the moment the receipt is up so CONTINUE can be
	-- clicked normally.
	local catcher = Instance.new("TextButton")
	catcher.Name = "SkipCatcher"
	catcher.Text = ""
	catcher.BackgroundTransparency = 1
	catcher.Size = UDim2.fromScale(1, 1)
	catcher.Visible = false
	catcher.ZIndex = 65
	catcher.Parent = self.Root
	catcher.Activated:Connect(function()
		self:_GPAdvance()
	end)
	self._gpCatcher = catcher

	self._gpSkip = gpButton(theme, self.Root, {
		name = "SkipAll",
		text = "Skip the firing",
		fill = theme.Colors.SurfaceRaised,
		size = UDim2.fromOffset(190, 44),
		position = UDim2.new(1, -28, 0, 28),
		anchorPoint = Vector2.new(1, 0),
		index = 1,
		zIndex = 70,
		sink = self._gpShadows,
		onClick = function()
			self:_GPSkipAll()
		end,
	})
	self._gpSkip.root.Visible = false

	-- THE one ticker registration for this screen. Bound to the Gui, so a style
	-- rebuild (which destroys the shell) unregisters it for free.
	self._gpStopTicker = UITicker.Register(function(dt: number, now: number)
		self:_GPStep(dt, now)
	end, self.Gui)
end

-- ---- ceremony -------------------------------------------------------

function CrateRevealScreen:_BuildGPCeremony(theme: Types.UITheme, host: Instance)
	local spacing = theme.Spacing

	local root = gpSurface("Ceremony", theme.Colors.Background, 1)
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = 6
	root.Visible = false
	root.Parent = host
	self._gpCeremony = root

	-- THE KILN. A terracotta chamber in a cream housing: the housing casts the
	-- soft hue-matched shadow, the chamber carries the heat glow.
	local housingFill = theme.Colors.SurfaceRaised
	local housing = gpSurface("KilnHousing", housingFill, 0)
	housing.Position = UDim2.fromOffset(0, 0)
	housing.Size = UDim2.fromOffset(GP_CHAMBER.X + spacing.L * 2, GP_CHAMBER.Y + spacing.L * 2)
	housing.ZIndex = 6
	housing.Parent = root
	GPLayoutKit.Petal(theme, housing, 0)
	GPLayoutKit.SoftStroke(theme, housing)
	GPLayoutKit.Shadow(theme, housing, "lg", self._gpShadows, housingFill)

	local chamberFill = theme.Semantic.Currency.Clay or theme.Arcade.Orange
	self._gpChamberCool = chamberFill
	local chamber = gpSurface("Chamber", chamberFill, 0)
	chamber.Position = UDim2.fromOffset(spacing.L, spacing.L)
	chamber.Size = UDim2.fromOffset(GP_CHAMBER.X, GP_CHAMBER.Y)
	chamber.ClipsDescendants = true
	chamber.ZIndex = 7
	chamber.Parent = housing
	GPLayoutKit.Petal(theme, chamber, 1)
	GPLayoutKit.SoftStroke(theme, chamber)
	self._gpChamber = chamber

	-- The heat glow: a zero-offset hue-matched aura whose transparency ramps
	-- from invisible to the pack's glow token across the firing stage. This is
	-- the EffectShadows.glow ramp the ceremony is built around.
	local heatHandle = GPLayoutKit.Glow(theme, chamber, theme.Arcade.Gold, self._gpShadows)
	self._gpHeatHandle = heatHandle
	self._gpHeatRest = heatHandle.Instance.Transparency
	heatHandle.Instance.Transparency = 1
	self._gpHeatHot = theme.Arcade.Gold:Lerp(theme.Colors.Primary, 0.35)

	local pieceSlot = gpSurface("PieceSlot", chamberFill, 1)
	pieceSlot.AnchorPoint = Vector2.new(0.5, 0.5)
	pieceSlot.Position = UDim2.fromScale(0.5, 0.5)
	pieceSlot.Size = UDim2.fromOffset(180, 180)
	pieceSlot.ZIndex = 9
	pieceSlot.Parent = chamber
	self._gpPieceSlot = pieceSlot

	local pieceScale = Instance.new("UIScale")
	pieceScale.Parent = pieceSlot
	self._gpPieceScale = pieceScale

	-- The glaze sheen SWEEP: a soft cream band whose gradient offset wipes
	-- left-to-right across the piece as it emerges. Transparency ramp, never a
	-- white colour keypoint — the pack bans that colour outright.
	local sweep = gpSurface("GlazeSweep", theme.Colors.Background, 0.55)
	sweep.Size = UDim2.fromScale(1, 1)
	sweep.Visible = false
	sweep.ZIndex = 11
	sweep.Parent = chamber
	local sweepGradient = Instance.new("UIGradient")
	sweepGradient.Rotation = 18
	sweepGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.42, 1),
		NumberSequenceKeypoint.new(0.5, 0.15),
		NumberSequenceKeypoint.new(0.58, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	sweepGradient.Parent = sweep
	self._gpSweep = sweep
	self._gpSweepGradient = sweepGradient

	-- The door, in two halves. Each is the housing's own fill deepened, so the
	-- door reads as the kiln closing on itself.
	local doorFill = GPLayoutKit.Deepen(theme, housingFill, 0.6)
	local doorLeft = gpSurface("DoorLeft", doorFill, 0)
	doorLeft.Size = UDim2.fromScale(0.5, 1)
	doorLeft.Position = UDim2.fromScale(-0.5, 0)
	doorLeft.ZIndex = 13
	doorLeft.Parent = chamber
	GPLayoutKit.SoftStroke(theme, doorLeft)
	self._gpDoorLeft = doorLeft

	local doorRight = gpSurface("DoorRight", doorFill, 0)
	doorRight.Size = UDim2.fromScale(0.5, 1)
	doorRight.Position = UDim2.fromScale(1, 0)
	doorRight.ZIndex = 13
	doorRight.Parent = chamber
	GPLayoutKit.SoftStroke(theme, doorRight)
	self._gpDoorRight = doorRight

	-- The right-hand column: what the firing IS, in numbers. Two live StatRows
	-- (the pack's anti-condescension proof) plus the piece's identity.
	local column = gpSurface("Readout", theme.Colors.Background, 1)
	column.Position = UDim2.fromOffset(GP_CHAMBER.X + spacing.L * 2 + spacing.L, 0)
	column.Size = UDim2.new(1, -(GP_CHAMBER.X + spacing.L * 3 + spacing.L), 1, 0)
	column.ZIndex = 6
	column.Parent = root

	local caption = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Caption")
	caption.Text = ""
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.Size = UDim2.new(1, 0, 0, 26)
	caption.ZIndex = 7
	caption.Parent = column
	self._gpCaption = caption

	local pieceName = GPLayoutKit.Text(theme, theme.TextSizes.Title, theme.Colors.TextPrimary, "PieceName")
	pieceName.Text = ""
	pieceName.TextXAlignment = Enum.TextXAlignment.Left
	pieceName.TextTruncate = Enum.TextTruncate.AtEnd
	pieceName.Position = UDim2.fromOffset(0, 30)
	pieceName.Size = UDim2.new(1, 0, 0, 40)
	pieceName.ZIndex = 7
	pieceName.Parent = column
	self._gpPieceName = pieceName

	local rarityRow = gpSurface("RarityRow", theme.Colors.Background, 1)
	rarityRow.Position = UDim2.fromOffset(0, 74)
	rarityRow.Size = UDim2.new(1, 0, 0, 34)
	rarityRow.ZIndex = 7
	rarityRow.Parent = column
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, spacing.S),
	}).Parent = rarityRow

	local rarityChipFill = theme.Colors.Surface
	local rarityChip = gpSurface("RarityChip", rarityChipFill, 0)
	rarityChip.Size = UDim2.fromOffset(158, 30)
	rarityChip.LayoutOrder = 1
	rarityChip.ZIndex = 7
	rarityChip.Parent = rarityRow
	UIStyler.Corner(theme.Radii.Pill).Parent = rarityChip
	-- The chip is re-tinted per rarity and the ramp's first tier is CREAM, which
	-- would leave a Common chip with no edge at all on the cream page. The soft
	-- stroke is what guarantees it always reads as a chip.
	self._gpRarityStroke = GPLayoutKit.SoftStroke(theme, rarityChip)
	self._gpRarityChip = rarityChip

	local rarityLabel = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "Rarity")
	rarityLabel.Text = ""
	rarityLabel.Size = UDim2.fromScale(1, 1)
	rarityLabel.ZIndex = 8
	rarityLabel.Parent = rarityChip
	self._gpRarityLabel = rarityLabel

	local note = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Note")
	note.Text = ""
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.LayoutOrder = 2
	note.Size = UDim2.new(0, 260, 1, 0)
	note.ZIndex = 7
	note.Parent = rarityRow
	self._gpNote = note

	GPLayoutKit.Divider(theme, column).Position = UDim2.fromOffset(0, 118)

	local statHost = gpSurface("Stats", theme.Colors.Background, 1)
	statHost.Position = UDim2.fromOffset(0, 138)
	statHost.Size = UDim2.new(1, 0, 0, 76)
	statHost.ZIndex = 7
	statHost.Parent = column
	UIStyler.ListLayout({ Padding = UDim.new(0, spacing.S) }).Parent = statHost

	self._gpTempRow = GPLayoutKit.StatRow(theme, statHost, {
		label = "Kiln temperature",
		value = gpToken(theme, "restTemperature"),
		maxValue = gpToken(theme, "peakTemperature"),
		unit = "°C",
		precision = 0,
		accent = theme.Arcade.Gold,
		layoutOrder = 1,
	})
	self._gpFireRow = GPLayoutKit.StatRow(theme, statHost, {
		label = "Firing progress",
		value = 0,
		maxValue = 100,
		unit = "%",
		precision = 1,
		accent = theme.Colors.Secondary,
		layoutOrder = 2,
	})

	GPLayoutKit.SectionLabel(theme, column, "Receipt from this firing").Position = UDim2.fromOffset(0, 226)

	-- The receipt: one line per piece already out of the kiln, so a 10× open
	-- ends with the whole run readable instead of only its last page.
	local receipts = Instance.new("ScrollingFrame")
	receipts.Name = "Receipts"
	receipts.BackgroundTransparency = 1
	receipts.BorderSizePixel = 0
	receipts.Position = UDim2.fromOffset(0, 254)
	-- Leaves the dot row and CONTINUE their own air below.
	receipts.Size = UDim2.new(1, 0, 1, -(254 + 90))
	receipts.CanvasSize = UDim2.new()
	receipts.AutomaticCanvasSize = Enum.AutomaticSize.Y
	receipts.ScrollBarThickness = 5
	receipts.ScrollBarImageColor3 = theme.Colors.Primary
	receipts.ClipsDescendants = true
	receipts.ZIndex = 7
	receipts.Parent = column
	UIStyler.ListLayout({ Padding = UDim.new(0, 4) }).Parent = receipts
	-- Padding so the rows' own soft shadows are not sliced by the clip.
	UIStyler.PaddingXY(6, 4).Parent = receipts
	self._gpReceiptHost = receipts

	local dots = gpSurface("Dots", theme.Colors.Background, 1)
	dots.AnchorPoint = Vector2.new(0, 1)
	dots.Position = UDim2.new(0, 0, 1, -62)
	dots.Size = UDim2.new(1, 0, 0, DOT + 6)
	dots.ZIndex = 7
	dots.Parent = column
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
	}).Parent = dots
	self._gpDotRow = dots
	self._gpDots = {} :: { Frame }

	self._gpContinue = gpButton(theme, column, {
		name = "Continue",
		text = "Continue",
		fill = theme.Colors.Secondary,
		size = UDim2.fromOffset(230, 52),
		position = UDim2.new(0, 0, 1, 0),
		anchorPoint = Vector2.new(0, 1),
		index = 0,
		sink = self._gpShadows,
		onClick = function()
			self:_GPContinue()
		end,
	})
	self._gpContinue.root.ZIndex = 8
	self._gpContinue.root.Visible = false
end

-- ---- loading bay (the crate preview) --------------------------------

function CrateRevealScreen:_BuildGPPreview(theme: Types.UITheme, host: Instance)
	local spacing = theme.Spacing

	local root = gpSurface("Preview", theme.Colors.Background, 1)
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = 6
	root.Visible = false
	root.Parent = host
	self._gpPreview = root

	local bayFill = theme.Colors.SurfaceRaised
	local bay = gpSurface("Bay", bayFill, 0)
	bay.Size = UDim2.new(0, 400, 1, 0)
	bay.ZIndex = 6
	bay.Parent = root
	GPLayoutKit.Petal(theme, bay, 0)
	GPLayoutKit.SoftStroke(theme, bay)
	GPLayoutKit.Shadow(theme, bay, "md", self._gpShadows, bayFill)

	local wellFill = theme.Colors.Surface
	local well = gpSurface("CrateWell", wellFill, 0)
	well.Position = UDim2.fromOffset(spacing.M, spacing.M)
	well.Size = UDim2.new(1, -spacing.M * 2, 0, 220)
	well.ZIndex = 7
	well.Parent = bay
	GPLayoutKit.Petal(theme, well, 1)
	GPLayoutKit.SoftStroke(theme, well)
	GPLayoutKit.GlazeSheen(theme, well)
	self._gpPreviewGlow = GPLayoutKit.Glow(theme, well, theme.Arcade.Gold, self._gpShadows)

	local art = gpIcon(theme, well, "crate", 150)
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.5)
	art.ZIndex = 9
	self._gpPreviewArt = art

	local crateName = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "CrateName")
	crateName.Text = ""
	crateName.TextTruncate = Enum.TextTruncate.AtEnd
	crateName.Position = UDim2.fromOffset(spacing.M, 250)
	crateName.Size = UDim2.new(1, -spacing.M * 2, 0, 30)
	crateName.ZIndex = 7
	crateName.Parent = bay
	self._gpCrateName = crateName

	GPLayoutKit.SectionLabel(theme, bay, "How many to fire").Position = UDim2.fromOffset(spacing.M, 286)

	local countRow = gpSurface("Counts", theme.Colors.Background, 1)
	countRow.Position = UDim2.fromOffset(spacing.M, 314)
	countRow.Size = UDim2.new(1, -spacing.M * 2, 0, 44)
	countRow.ZIndex = 7
	countRow.Parent = bay
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, spacing.S),
	}).Parent = countRow
	self._gpCountRow = countRow

	local priceHost = gpSurface("Prices", theme.Colors.Background, 1)
	priceHost.Position = UDim2.fromOffset(spacing.M, 372)
	priceHost.Size = UDim2.new(1, -spacing.M * 2, 0, 190)
	priceHost.ZIndex = 7
	priceHost.Parent = bay
	UIStyler.ListLayout({ Padding = UDim.new(0, spacing.S) }).Parent = priceHost
	self._gpPriceHost = priceHost

	local priceNote = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "PriceNote")
	priceNote.Text = ""
	priceNote.TextXAlignment = Enum.TextXAlignment.Left
	priceNote.TextWrapped = true
	priceNote.AnchorPoint = Vector2.new(0, 1)
	priceNote.Position = UDim2.new(0, spacing.M, 1, -spacing.S)
	priceNote.Size = UDim2.new(1, -spacing.M * 2, 0, 38)
	priceNote.ZIndex = 7
	priceNote.Parent = bay
	self._gpPriceNote = priceNote

	-- The drop table, commonest → rarest, exactly as the source advertises it.
	local shelf = gpSurface("Shelf", theme.Colors.Background, 1)
	shelf.Position = UDim2.fromOffset(400 + spacing.L, 0)
	shelf.Size = UDim2.new(1, -(400 + spacing.L), 1, 0)
	shelf.ZIndex = 6
	shelf.Parent = root

	GPLayoutKit.SectionLabel(theme, shelf, "On the shelf, and how often it lands")

	local list = Instance.new("ScrollingFrame")
	list.Name = "Odds"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(0, 30)
	list.Size = UDim2.new(1, 0, 1, -(30 + 34))
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = theme.Colors.Primary
	list.ClipsDescendants = true
	list.ZIndex = 6
	list.Parent = shelf
	UIStyler.ListLayout({ Padding = UDim.new(0, spacing.S) }).Parent = list
	-- Padding on all four sides: the rows cast soft shadows and a flush clip
	-- would shear them off.
	UIStyler.PaddingXY(8, 8).Parent = list
	self._gpOddsHost = list

	local footer = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "OddsFooter")
	footer.Text = ""
	footer.TextXAlignment = Enum.TextXAlignment.Left
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.new(0, 0, 1, 0)
	footer.Size = UDim2.new(1, 0, 0, 26)
	footer.ZIndex = 6
	footer.Parent = shelf
	self._gpOddsFooter = footer
end

-- ---- failure --------------------------------------------------------

function CrateRevealScreen:_BuildGPFailure(theme: Types.UITheme, host: Instance)
	local spacing = theme.Spacing

	local root = gpSurface("Failure", theme.Colors.Background, 1)
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = 6
	root.Visible = false
	root.Parent = host
	self._gpFailure = root

	local cardFill = theme.Colors.SurfaceRaised
	local card = gpSurface("ColdKiln", cardFill, 0)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(560, 300)
	card.ZIndex = 7
	card.Parent = root
	GPLayoutKit.Petal(theme, card, 0)
	GPLayoutKit.SoftStroke(theme, card)
	GPLayoutKit.Shadow(theme, card, "lg", self._gpShadows, cardFill)

	local icon = gpIcon(theme, card, "lock", 72)
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, spacing.L)
	icon.ZIndex = 8

	local title = GPLayoutKit.Text(theme, theme.TextSizes.Title, theme.Colors.TextPrimary, "ColdTitle")
	title.Text = "The kiln stays cold."
	title.Position = UDim2.fromOffset(spacing.L, 108)
	title.Size = UDim2.new(1, -spacing.L * 2, 0, 40)
	title.ZIndex = 8
	title.Parent = card

	-- The source's exact refusal copy, verbatim.
	local body = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "ColdBody")
	body.Text = ""
	body.TextWrapped = true
	body.Position = UDim2.fromOffset(spacing.L, 150)
	body.Size = UDim2.new(1, -spacing.L * 2, 0, 60)
	body.ZIndex = 8
	body.Parent = card
	self._gpFailureBody = body

	self._gpFailureButton = gpButton(theme, card, {
		name = "ColdClose",
		text = "Back to the bay",
		fill = theme.Colors.Primary,
		size = UDim2.fromOffset(230, 50),
		position = UDim2.new(0.5, 0, 1, -spacing.L),
		anchorPoint = Vector2.new(0.5, 1),
		index = 1,
		sink = self._gpShadows,
		onClick = function()
			if #self._odds > 0 then
				self:_GPSetMode("preview")
			else
				self.ScreenController:HideScreen("crateReveal")
			end
		end,
	})
	self._gpFailureButton.root.ZIndex = 8
end

-- ---- pooled rows ----------------------------------------------------

function CrateRevealScreen:_GPAcquireOddsRow(): any
	local pooled = table.remove(self._gpOddsPool)
	if pooled then
		pooled.root.Visible = true
		return pooled
	end
	local theme = self:GetTheme()
	local spacing = theme.Spacing

	local rowFill = theme.Colors.SurfaceRaised
	local root = gpSurface("OddsRow", rowFill, 0)
	root.Size = UDim2.new(1, 0, 0, GP_ODDS_ROW_H)
	root.ZIndex = 7
	local stroke = GPLayoutKit.SoftStroke(theme, root)
	local shadow = GPLayoutKit.Shadow(theme, root, "sm", self._gpShadows, rowFill)

	local wellFill = theme.Colors.Surface
	local well = gpSurface("Well", wellFill, 0)
	well.Position = UDim2.fromOffset(spacing.S, spacing.S)
	well.Size = UDim2.fromOffset(GP_ODDS_ROW_H - spacing.S * 2, GP_ODDS_ROW_H - spacing.S * 2)
	well.ZIndex = 8
	well.Parent = root

	local iconSlot = gpSurface("IconSlot", wellFill, 1)
	iconSlot.AnchorPoint = Vector2.new(0.5, 0.5)
	iconSlot.Position = UDim2.fromScale(0.5, 0.5)
	iconSlot.Size = UDim2.fromScale(0.86, 0.86)
	iconSlot.ZIndex = 9
	iconSlot.Parent = well

	local name = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "Name")
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(GP_ODDS_ROW_H + spacing.S, 6)
	name.Size = UDim2.new(1, -(GP_ODDS_ROW_H + spacing.S + 200), 0, 24)
	name.ZIndex = 8
	name.Parent = root

	local rarity = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Rarity")
	rarity.TextXAlignment = Enum.TextXAlignment.Left
	rarity.Position = UDim2.fromOffset(GP_ODDS_ROW_H + spacing.S, 28)
	rarity.Size = UDim2.new(1, -(GP_ODDS_ROW_H + spacing.S + 200), 0, 20)
	rarity.ZIndex = 8
	rarity.Parent = root

	local pct = GPLayoutKit.NumberText(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "Pct")
	pct.AnchorPoint = Vector2.new(1, 0)
	pct.Position = UDim2.new(1, -spacing.M, 0, 6)
	pct.Size = UDim2.fromOffset(120, 24)
	pct.ZIndex = 8
	pct.Parent = root

	local oneIn = GPLayoutKit.NumberText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "OneIn")
	oneIn.AnchorPoint = Vector2.new(1, 0)
	oneIn.Position = UDim2.new(1, -spacing.M, 0, 30)
	oneIn.Size = UDim2.fromOffset(120, 18)
	oneIn.ZIndex = 8
	oneIn.Parent = root

	local track = gpSurface("Track", theme.Arcade.RulerTrack, 0)
	track.AnchorPoint = Vector2.new(1, 1)
	track.Position = UDim2.new(1, -spacing.M, 1, -8)
	track.Size = UDim2.fromOffset(120, 5)
	track.ZIndex = 8
	track.Parent = root
	UIStyler.Corner(theme.Radii.Pill).Parent = track

	local fill = gpSurface("Fill", theme.Colors.Primary, 0)
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = 9
	fill.Parent = track
	UIStyler.Corner(theme.Radii.Pill).Parent = fill

	return {
		root = root,
		stroke = stroke,
		shadow = shadow,
		iconSlot = iconSlot,
		well = well,
		name = name,
		rarity = rarity,
		pct = pct,
		oneIn = oneIn,
		fill = fill,
	}
end

function CrateRevealScreen:_GPReleaseOddsRows()
	for _, row in self._gpOddsRows do
		row.root.Visible = false
		row.root.Parent = nil
		row.shadow:SetEnabled(false)
		row.iconSlot:ClearAllChildren()
		table.insert(self._gpOddsPool, row)
	end
	table.clear(self._gpOddsRows)
end

function CrateRevealScreen:_GPAcquireReceiptRow(): any
	local pooled = table.remove(self._gpReceiptPool)
	if pooled then
		pooled.root.Visible = true
		return pooled
	end
	local theme = self:GetTheme()

	local rowFill = theme.Colors.Surface
	local root = gpSurface("ReceiptRow", rowFill, 0)
	root.Size = UDim2.new(1, 0, 0, GP_RECEIPT_ROW_H)
	root.ZIndex = 8

	local pip = gpSurface("Pip", theme.Colors.Primary, 0)
	pip.AnchorPoint = Vector2.new(0, 0.5)
	pip.Position = UDim2.new(0, 10, 0.5, 0)
	pip.Size = UDim2.fromOffset(10, 10)
	pip.ZIndex = 9
	pip.Parent = root
	UIStyler.Corner(theme.Radii.Pill).Parent = pip

	local text = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "Text")
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextTruncate = Enum.TextTruncate.AtEnd
	text.Position = UDim2.fromOffset(28, 0)
	text.Size = UDim2.new(1, -(28 + 96), 1, 0)
	text.ZIndex = 9
	text.Parent = root

	local value = GPLayoutKit.NumberText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Value")
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.new(1, -10, 0, 0)
	value.Size = UDim2.fromOffset(86, GP_RECEIPT_ROW_H)
	value.ZIndex = 9
	value.Parent = root

	return { root = root, pip = pip, text = text, value = value }
end

function CrateRevealScreen:_GPClearReceipts()
	for _, row in self._gpReceiptRows do
		row.root.Visible = false
		row.root.Parent = nil
		table.insert(self._gpReceiptPool, row)
	end
	table.clear(self._gpReceiptRows)
end

function CrateRevealScreen:_GPPushReceipt(item: RevealItem, index: number)
	local theme = self:GetTheme()
	local row = self:_GPAcquireReceiptRow()
	local accent = gpRarityColor(theme, item.rarity)
	-- A 10px pip in the raw Common cream would be invisible on the blush row.
	row.pip.BackgroundColor3 = gpReadable(theme, accent, GP_METER_PULL)
	row.text.Text = string.format("%d. %s — %s", index, gpSentence(item.name), item.rarity or "Unfired")
	if item.value then
		row.value.Text = string.format("+%d %s", item.value, item.valueCurrency or "Cash")
		row.value.TextColor3 = UIChrome.CurrencyColor(theme, item.valueCurrency or "Cash")
	else
		row.value.Text = if item.note then "dupe" else "new"
		row.value.TextColor3 = theme.Colors.TextSecondary
	end
	GPLayoutKit.Petal(theme, row.root, index)
	row.root.LayoutOrder = index
	row.root.Parent = self._gpReceiptHost
	table.insert(self._gpReceiptRows, row)
end

-- ---- preview render -------------------------------------------------

function CrateRevealScreen:_GPRenderPreview()
	local theme = self:GetTheme()
	local crate = self._crate

	-- The source prints the crate's name in the crate's OWN colour. Its panel is
	-- near-black, so a bright accent reads there; this page is cream, so the same
	-- identity has to travel the other way — the accent is pulled most of the way
	-- to ink, which keeps the hue and clears 4.5:1 on the paper.
	local accent = crate.accent or theme.Arcade.Gold
	self._gpCrateName.Text = gpSentence(crate.name)
	self._gpCrateName.TextColor3 = accent:Lerp(theme.Colors.TextPrimary, GP_INK_PULL)
	self._gpPreviewGlow.Instance.Color = accent
	self._gpPage.title.Text = gpSentence(crate.name)
	self._gpPage.subtitle.Text = "Load a bisque piece and let the kiln decide."
	self._gpPage.subtitle.Visible = true

	self:_GPRenderCounts()
	self:_GPRenderPrices()
	self:_GPRenderOdds()
end

function CrateRevealScreen:_GPRenderCounts()
	local theme = self:GetTheme()
	for _, entry in self._gpCountChips do
		-- Release BEFORE destroy: the budget counter only falls on Release.
		entry.button.shadow:Release()
		entry.button.root:Destroy()
	end
	table.clear(self._gpCountChips)

	for i, n in self._counts do
		local chip = gpButton(theme, self._gpCountRow, {
			name = "Count" .. n,
			text = "×" .. n,
			fill = if n == self._openCount then theme.Colors.Primary else theme.Colors.Surface,
			size = UDim2.fromOffset(88, 40),
			index = i,
			layoutOrder = i,
			zIndex = 8,
			sink = self._gpShadows,
			onClick = function()
				self:_GPSetCount(n)
			end,
		})
		table.insert(self._gpCountChips, { button = chip, count = n })
	end
end

function CrateRevealScreen:_GPSetCount(n: number)
	local theme = self:GetTheme()
	self._openCount = n
	for _, entry in self._gpCountChips do
		entry.button.SetFill(if entry.count == n then theme.Colors.Primary else theme.Colors.Surface)
	end
	self:_GPRenderPrices()
end

function CrateRevealScreen:_GPRenderPrices()
	local theme = self:GetTheme()
	for _, button in self._gpPriceButtons do
		-- Release BEFORE destroy: the budget counter only falls on Release.
		button.shadow:Release()
		button.root:Destroy()
	end
	table.clear(self._gpPriceButtons)

	local crate = self._crate
	local count = self._openCount
	local order = 0

	local function priceButton(label: string, currency: string, onClick: () -> ())
		order += 1
		local button = gpButton(theme, self._gpPriceHost, {
			name = "Buy" .. currency,
			text = label,
			fill = UIChrome.CurrencyColor(theme, currency),
			size = UDim2.new(1, 0, 0, 58),
			index = order,
			layoutOrder = order,
			textSize = theme.TextSizes.Subtitle,
			zIndex = 8,
			sink = self._gpShadows,
			onClick = onClick,
		})
		local icon = gpIcon(theme, button.chip, string.lower(currency), 30)
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, theme.Spacing.M, 0.5, 0)
		icon.ZIndex = button.chip.ZIndex + 2
		button.label.TextXAlignment = Enum.TextXAlignment.Left
		UIStyler.PaddingXY(theme.Spacing.M + 40, 0).Parent = button.label
		table.insert(self._gpPriceButtons, button)
		return button
	end

	if crate.cashCost then
		priceButton("$" .. crate.cashCost * count, "Cash", function()
			self:_GPRequestOpen("Cash")
		end)
	end

	-- PolicyService: crates bought with Bux or Robux are PAID RANDOM items.
	-- nil = the verdict has not landed yet, and that fails CLOSED — the Cash
	-- button above always stays.
	local paidRandomOK = self._paidRandomAllowed == true
	if crate.buxCost and paidRandomOK then
		priceButton(tostring(crate.buxCost * count), "Bux", function()
			self:_GPRequestOpen("Bux")
		end)
	end
	if crate.robuxCost and paidRandomOK then
		-- Robux stays a SINGLE open whatever the selector says: a dev product
		-- purchase is one receipt.
		priceButton(tostring(crate.robuxCost), "Robux", function()
			if (crate.productId or 0) == 0 then
				self._gpPriceNote.Text = "Coming soon!"
				self._gpPriceNote.TextColor3 = theme.Arcade.Gold
				return
			end
			self:_GPRequestOpen("Robux")
		end)
	end

	if self._paidRandomAllowed == nil then
		self._gpPriceNote.Text = "Checking what this account is allowed to buy — Cash always works."
	elseif not paidRandomOK then
		self._gpPriceNote.Text = "Crates can only be opened with Cash on your account."
	else
		self._gpPriceNote.Text = "Robux always fires one piece, whatever the count says."
	end
	self._gpPriceNote.TextColor3 = theme.Colors.TextSecondary
end

function CrateRevealScreen:_GPRequestOpen(currency: string)
	-- The screen NEVER decides a reward: it asks, and waits to be handed a
	-- server-confirmed result through Show/Update.
	local onOpen = self._onOpen
	if onOpen then
		task.spawn(onOpen, self._openCount, currency)
	end
	self:_PlaySound("Click")
end

function CrateRevealScreen:_GPRenderOdds()
	local theme = self:GetTheme()
	self:_GPReleaseOddsRows()

	local best = 0
	for _, entry in self._odds do
		best = math.max(best, entry.pct)
	end
	for i, entry in self._odds do
		local row = self:_GPAcquireOddsRow()
		local accent = gpRarityColor(theme, entry.rarity)
		row.root.LayoutOrder = i
		-- Alternating petal sets, so a shelf reads hand-arranged.
		GPLayoutKit.Petal(theme, row.root, i)
		GPLayoutKit.Petal(theme, row.well, i + 1)
		-- THE RARITY EDGE, from the source: every drop card is outlined in its
		-- own rarity colour and the ultra-rares (< 1%) get the heavier stroke, so
		-- the jackpot is findable at a glance instead of only in the numbers. The
		-- colour is the accent DEEPENED along its own hue — never grey, never black.
		-- Chrome is optional on the schema, so the house values back it up.
		local chrome = theme.Chrome
		local ultra = entry.pct < GP_ULTRA_PCT
		row.stroke.Color = GPLayoutKit.Deepen(theme, accent, 1)
		row.stroke.Thickness = if ultra then GP_ULTRA_STROKE else (chrome and chrome.StrokeThickness or 2)
		row.stroke.Transparency = if ultra then 0 else (chrome and chrome.StrokeTransparency or 0.35)
		row.well.BackgroundColor3 = accent:Lerp(theme.Colors.Surface, 0.62)
		row.name.Text = gpSentence(entry.name)
		row.rarity.Text = entry.rarity or "Unfired"
		row.rarity.TextColor3 = gpReadable(theme, accent, GP_INK_PULL)
		row.pct.Text = string.format("%.2f%%", entry.pct)
		row.pct.TextColor3 = gpReadable(theme, accent, GP_INK_PULL)
		row.oneIn.Text = if entry.pct > 0 then string.format("1 in %d", math.max(1, math.floor(100 / entry.pct + 0.5))) else "—"
		-- The COMMONEST row owns the longest bar, and Common is the cream tier —
		-- left raw it would be the one meter you cannot see.
		row.fill.BackgroundColor3 = gpReadable(theme, accent, GP_METER_PULL)
		row.fill.Size = UDim2.fromScale(if best > 0 then math.clamp(entry.pct / best, 0.02, 1) else 0, 1)
		row.shadow:SetEnabled(true)
		local icon = gpIcon(theme, row.iconSlot, entry.icon or "chest", 32)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.ZIndex = 10
		row.root.Parent = self._gpOddsHost
		table.insert(self._gpOddsRows, row)
	end

	local total = 0
	for _, entry in self._odds do
		total += entry.pct
	end
	self._gpOddsFooter.Text = string.format(
		"%d pieces on the shelf · rates add to %.2f%% · shown per piece fired",
		#self._odds,
		total
	)
end

-- ---- ceremony render + stage machine --------------------------------

function CrateRevealScreen:_GPRenderDots()
	local theme = self:GetTheme()
	for _, dot in self._gpDots do
		dot:Destroy()
	end
	table.clear(self._gpDots)
	local count = #self._items
	self._gpDotRow.Visible = count > 1
	if count <= 1 then
		return
	end
	for i = 1, count do
		local dot = gpSurface("Dot" .. i, if i <= self._page then theme.Colors.Primary else theme.Arcade.RulerTrack, 0)
		dot.Size = UDim2.fromOffset(DOT, DOT)
		dot.LayoutOrder = i
		dot.ZIndex = 8
		UIStyler.Corner(theme.Radii.Pill).Parent = dot
		dot.Parent = self._gpDotRow
		table.insert(self._gpDots, dot)
	end
end

function CrateRevealScreen:_GPRenderPage(page: number, firstPage: boolean)
	local theme = self:GetTheme()
	local item = self._items[page]
	if not item then
		return
	end
	self._page = page
	self._gpTier = gpTier(item.rarity)
	self._gpRevealed = false

	local accent = gpRarityColor(theme, item.rarity)
	self._gpPage.title.Text = gpSentence(self._crateName)
	self._gpPage.subtitle.Text = string.format("Firing piece %d of %d", page, #self._items)
	self._gpPage.subtitle.Visible = true

	-- Text FIRST — even if the art hiccups, the card still announces the prize.
	self._gpPieceName.Text = gpSentence(item.name)
	self._gpRarityLabel.Text = if item.kind == "title" then "New title unlocked!" else (item.rarity or "Unfired")
	self._gpRarityChip.BackgroundColor3 = accent:Lerp(theme.Colors.Background, 0.55)
	self._gpRarityStroke.Color = GPLayoutKit.Deepen(theme, accent, 1)
	self._gpNote.Text = if item.kind == "title"
		then (if item.req then "Earned at " .. item.req else "")
		elseif item.note then item.note
		else "New!"
	self._gpNote.TextColor3 = if item.note then theme.Colors.TextSecondary else theme.Arcade.MoneyGreen

	self._gpPieceSlot:ClearAllChildren()
	self._gpPieceScale = Instance.new("UIScale")
	self._gpPieceScale.Parent = self._gpPieceSlot
	-- The piece goes in UNFIRED (a clay silhouette) and only wears its glaze
	-- once it is out of the kiln — that swap IS the reveal.
	local bisque = gpIcon(theme, self._gpPieceSlot, item.icon or "chest", 150)
	bisque.AnchorPoint = Vector2.new(0.5, 0.5)
	bisque.Position = UDim2.fromScale(0.5, 0.5)
	bisque.ZIndex = 10
	if bisque:IsA("ImageLabel") then
		bisque.ImageColor3 = GPLayoutKit.Deepen(theme, self._gpChamberCool, 0.5)
	end
	self._gpPiece = bisque
	self._gpPieceGolden = self._gpTier >= 3

	self:_GPRenderDots()
	self:_GPSetStage(if firstPage then "load" else "emerge")
end

-- Set the stage machine to `stage`: every EARLIER stage snaps to its finished
-- state, this one starts at zero. That is what makes a skip honest — nothing
-- is left half-open behind the piece.
function CrateRevealScreen:_GPSetStage(stage: string)
	local theme = self:GetTheme()
	local rank = GP_STAGE_RANK[stage] or 1
	for i = 1, rank - 1 do
		self:_GPApplyStage(GP_STAGES[i], 1, 0)
	end
	self._gpStage = stage
	self._gpStageClock = 0

	if stage == "load" then
		self._gpStageDuration = gpToken(theme, "loadTime")
		self._gpCaption.Text = "Setting the bisque piece on the shelf."
	elseif stage == "close" then
		self._gpStageDuration = gpToken(theme, "closeTime")
		self._gpCaption.Text = "Closing the kiln door."
	elseif stage == "fire" then
		self._gpStageDuration = gpToken(theme, "fireTime")
		self._gpCaption.Text = "Firing. Nobody knows what the glaze does in there."
	elseif stage == "open" then
		self._gpStageDuration = gpToken(theme, "openTime")
		self._gpCaption.Text = "Cracking the door."
	elseif stage == "emerge" then
		self._gpStageDuration = gpToken(theme, "emergeTime")
		self._gpCaption.Text = "The glaze has taken."
		self:_GPRevealPiece()
	elseif stage == "celebrate" then
		self._gpStageDuration = if self._gpTier >= 3
			then gpToken(theme, "celebrateSunburst")
			elseif self._gpTier == 2 then gpToken(theme, "celebrateSparkle")
			else gpToken(theme, "celebrateSoft")
		self:_GPCelebrate()
	elseif stage == "receipt" then
		self._gpStageDuration = math.huge
		self._gpCaption.Text = "Out of the kiln, and yours."
		self:_GPPushReceipt(self._items[self._page], self._page)
		local last = self._page >= #self._items
		self._gpContinue.SetText(if last then "Continue" else string.format("Next  (%d/%d)", self._page, #self._items))
		self._gpContinue.SetFill(if last then theme.Colors.Secondary else theme.Colors.Primary)
		self._gpContinue.root.Visible = true
		self._gpCatcher.Visible = false
		self._gpSkip.root.Visible = false
	end

	if stage ~= "receipt" then
		self._gpContinue.root.Visible = false
		self._gpCatcher.Visible = true
		self._gpSkip.root.Visible = true
	end
	self:_GPApplyStage(stage, 0, 0)
end

-- Every continuous visual of a stage, expressed as a pure function of its
-- progress t. The ticker calls it with the live clock; a skip calls it with 1.
function CrateRevealScreen:_GPApplyStage(stage: string, t: number, now: number)
	local theme = self:GetTheme()
	t = math.clamp(t, 0, 1)

	if stage == "load" then
		-- Drop in, ease out, land.
		local eased = 1 - (1 - t) ^ 3
		self._gpPieceSlot.Position = UDim2.new(0.5, 0, gpLerp(-0.35, 0.5, eased), 0)
		self._gpPieceScale.Scale = gpLerp(0.62, 1, eased)
		self._gpDoorLeft.Position = UDim2.fromScale(-0.5, 0)
		self._gpDoorRight.Position = UDim2.fromScale(1, 0)
	elseif stage == "close" then
		local eased = t * t
		self._gpDoorLeft.Position = UDim2.fromScale(gpLerp(-0.5, 0, eased), 0)
		self._gpDoorRight.Position = UDim2.fromScale(gpLerp(1, 0.5, eased), 0)
	elseif stage == "fire" then
		-- THE HEAT: the glow token's transparency ramps in while the chamber's
		-- own fill shifts along its hue toward butter and then hot rose.
		local heat = self._gpHeatHandle.Instance
		heat.Transparency = gpLerp(1, self._gpHeatRest, t)
		heat.Color = theme.Arcade.Gold:Lerp(self._gpHeatHot, t)
		self._gpChamber.BackgroundColor3 = self._gpChamberCool:Lerp(self._gpHeatHot, t * 0.85)
		self._gpDoorLeft.Position = UDim2.fromScale(0, 0)
		self._gpDoorRight.Position = UDim2.fromScale(0.5, 0)
		local temperature = gpLerp(gpToken(theme, "restTemperature"), gpToken(theme, "peakTemperature"), t)
		self._gpTemperature = temperature
		self._gpTempRow.SetValue(temperature)
		self._gpFireRow.SetValue(t * 100)
		self._gpCaption.Text = string.format("Firing at %d°C.", math.floor(temperature))
	elseif stage == "open" then
		local eased = 1 - (1 - t) ^ 2
		self._gpDoorLeft.Position = UDim2.fromScale(gpLerp(0, -0.5, eased), 0)
		self._gpDoorRight.Position = UDim2.fromScale(gpLerp(0.5, 1, eased), 0)
		-- The kiln cools the moment the door opens.
		local heat = self._gpHeatHandle.Instance
		heat.Transparency = gpLerp(self._gpHeatRest, 0.85, eased)
	elseif stage == "emerge" then
		-- The reveal is idempotent and lives HERE as well as in _GPSetStage, so
		-- a skip that jumps straight past this stage still swaps the bisque
		-- silhouette for the glazed piece instead of leaving clay on screen.
		self:_GPRevealPiece()
		-- The sheen sweep: the glaze catching the light as the piece comes out.
		self._gpSweep.Visible = t < 1
		self._gpSweepGradient.Offset = Vector2.new(gpLerp(-1.1, 1.1, t), 0)
		local pop = if t < 0.45 then gpLerp(0.9, 1.08, t / 0.45) else gpLerp(1.08, 1, (t - 0.45) / 0.55)
		self._gpPieceScale.Scale = pop
		self._gpPieceSlot.Position = UDim2.fromScale(0.5, 0.5)
		self._gpChamber.BackgroundColor3 = self._gpHeatHot:Lerp(self._gpChamberCool, t)
		self._gpDoorLeft.Position = UDim2.fromScale(-0.5, 0)
		self._gpDoorRight.Position = UDim2.fromScale(1, 0)
	elseif stage == "celebrate" then
		self._gpSweep.Visible = false
		if self._gpTier >= 3 then
			self._gpSunburst.Rotation = (now * gpToken(theme, "sunburstDegPerSec")) % 360
		end
		for _, sparkle in self._gpSparkles do
			sparkle.ImageTransparency = math.clamp(gpLerp(0.1, 1, t), 0, 1)
		end
		self._gpPieceScale.Scale = 1 + 0.04 * math.sin(t * math.pi)
	elseif stage == "receipt" then
		self._gpSweep.Visible = false
		self._gpPieceScale.Scale = 1
	end
end

function CrateRevealScreen:_GPRevealPiece()
	if self._gpRevealed then
		return
	end
	local theme = self:GetTheme()
	local item = self._items[self._page]
	if not item then
		return
	end
	self._gpRevealed = true
	local accent = gpRarityColor(theme, item.rarity)
	self._gpPieceSlot:ClearAllChildren()
	self._gpPieceScale = Instance.new("UIScale")
	self._gpPieceScale.Parent = self._gpPieceSlot
	local glazed = gpIcon(theme, self._gpPieceSlot, item.icon or "chest", 150, self._gpPieceGolden)
	glazed.AnchorPoint = Vector2.new(0.5, 0.5)
	glazed.Position = UDim2.fromScale(0.5, 0.5)
	glazed.ZIndex = 10
	self._gpPiece = glazed
	self._gpChamber.BackgroundColor3 = accent:Lerp(self._gpChamberCool, 0.55)
end

function CrateRevealScreen:_GPCelebrate()
	local tier = self._gpTier
	self:_PlaySound("Success")
	if tier == 1 then
		self._gpCaption.Text = "A soft chime. Tidy little piece."
		return
	end
	if tier == 2 then
		self._gpCaption.Text = "Look at that glaze."
		self:_GPSparkleBurst()
		return
	end
	self._gpCaption.Text = "The kiln gods smiled. Everybody look."
	self:_GPSparkleBurst()
	self._gpBurstLayer.Visible = true
	self:_GPBurstConfetti()
end

function CrateRevealScreen:_GPSparkleBurst()
	local theme = self:GetTheme()
	self:_GPClearSparkles()
	local count = math.floor(gpToken(theme, "sparkleCount"))
	for i = 1, count do
		local angle = (i / count) * math.pi * 2
		local radius = 70 + math.random(0, 46)
		local sparkle = GPLayoutKit.Slice(theme, "sparkle", theme.Arcade.Gold, "Sparkle")
		sparkle.AnchorPoint = Vector2.new(0.5, 0.5)
		sparkle.Position = UDim2.new(0.5, math.floor(math.cos(angle) * radius), 0.5, math.floor(math.sin(angle) * radius))
		sparkle.Size = UDim2.fromOffset(28 + math.random(0, 18), 28 + math.random(0, 18))
		sparkle.Rotation = math.random(0, 360)
		sparkle.ImageTransparency = 0.1
		sparkle.ZIndex = 12
		sparkle.Parent = self._gpChamber
		table.insert(self._gpSparkles, sparkle)
	end
end

function CrateRevealScreen:_GPClearSparkles()
	for _, sparkle in self._gpSparkles do
		sparkle:Destroy()
	end
	table.clear(self._gpSparkles)
end

-- The source's confetti, kept beat for beat (36 pieces, 8–14px, 1.6–2.4s
-- LINEAR from above the top edge to below the bottom, ±60px drift, ±360°
-- spin) — repainted in the pack's pastel rotation and cut from the confetti
-- art instead of plain squares.
function CrateRevealScreen:_GPBurstConfetti()
	local theme = self:GetTheme()
	local colors = table.clone(theme.Arcade.Rainbow)
	table.insert(colors, theme.Arcade.Magenta)
	local count = math.floor(gpToken(theme, "confettiCount"))
	local minSize = math.floor(gpToken(theme, "confettiMin"))
	local maxSize = math.floor(gpToken(theme, "confettiMax"))
	local drift = math.floor(gpToken(theme, "confettiDrift"))
	local minTime = gpToken(theme, "confettiMinTime")
	local maxTime = gpToken(theme, "confettiMaxTime")

	for _ = 1, count do
		local size = math.random(minSize, maxSize)
		local piece = GPLayoutKit.Slice(theme, "confetti", colors[math.random(#colors)], "Confetti")
		piece.Position = UDim2.new(math.random(), 0, 0, -20)
		piece.Size = UDim2.fromOffset(size, size)
		piece.Rotation = math.random(0, 360)
		piece.ZIndex = 61
		piece.Parent = self._gpFxLayer
		table.insert(self._gpConfetti, piece)

		local seconds = minTime + math.random() * math.max(0, maxTime - minTime)
		local tween = TweenService:Create(piece, TweenInfo.new(seconds, Enum.EasingStyle.Linear), {
			Position = UDim2.new(piece.Position.X.Scale, math.random(-drift, drift), 1, 40),
			Rotation = piece.Rotation + math.random(-360, 360),
		})
		table.insert(self._gpConfettiTweens, tween)
		tween.Completed:Once(function()
			local index = table.find(self._gpConfetti, piece)
			if index then
				table.remove(self._gpConfetti, index)
			end
			piece:Destroy()
		end)
		tween:Play()
	end
end

function CrateRevealScreen:_GPClearConfetti()
	for _, tween in self._gpConfettiTweens do
		tween:Cancel()
	end
	table.clear(self._gpConfettiTweens)
	for _, piece in self._gpConfetti do
		piece:Destroy()
	end
	table.clear(self._gpConfetti)
end

function CrateRevealScreen:_GPStep(dt: number, now: number)
	if not self:IsVisible() or self._gpMode ~= "ceremony" or self._gpStage == "idle" then
		return
	end
	self._gpStageClock += dt
	local duration = self._gpStageDuration
	local t = if duration > 0 and duration < math.huge then self._gpStageClock / duration else 1
	self:_GPApplyStage(self._gpStage, t, now)
	if self._gpStageClock >= duration then
		local nextStage = GP_NEXT_STAGE[self._gpStage]
		if nextStage then
			self:_GPSetStage(nextStage)
		end
	end
end

-- ---- skipping, paging, modes ----------------------------------------

function CrateRevealScreen:_GPAdvance()
	local nextStage = GP_NEXT_STAGE[self._gpStage]
	if nextStage then
		self:_GPSetStage(nextStage)
	end
end

function CrateRevealScreen:_GPSkipAll()
	if self._gpMode ~= "ceremony" or self._gpStage == "receipt" then
		return
	end
	self:_GPSetStage("receipt")
end

function CrateRevealScreen:_GPContinue()
	if self._page < #self._items then
		self:_GPRenderPage(self._page + 1, false)
	else
		self.ScreenController:HideScreen("crateReveal")
	end
end

function CrateRevealScreen:_GPSetMode(mode: string)
	self._gpMode = mode
	self._gpPreview.Visible = mode == "preview"
	self._gpCeremony.Visible = mode == "ceremony"
	self._gpFailure.Visible = mode == "failure"
	if mode ~= "ceremony" then
		self._gpStage = "idle"
		self._gpCatcher.Visible = false
		self._gpSkip.root.Visible = false
		self._gpBurstLayer.Visible = false
		self:_GPClearConfetti()
		self:_GPClearSparkles()
	end
	if mode == "preview" then
		self:_GPRenderPreview()
	end
end

function CrateRevealScreen:_GPShow(data: any?)
	local theme = self:GetTheme()
	local failure: string? = nil
	local crateGiven = false
	local nameGiven = type(data) == "table" and type((data :: any).crateName) == "string"
	if type(data) == "table" then
		if type(data.crate) == "table" then
			self._crate = data.crate
			crateGiven = true
		end
		if type(data.odds) == "table" and #data.odds > 0 then
			self._odds = data.odds
		end
		if type(data.counts) == "table" and #data.counts > 0 then
			self._counts = data.counts
			self._openCount = data.counts[1]
		end
		if type(data.paidRandomAllowed) == "boolean" then
			self._paidRandomAllowed = data.paidRandomAllowed
		end
		if type(data.onOpen) == "function" then
			self._onOpen = data.onOpen
		end
		if type(data.error) == "string" then
			failure = data.error
		end
	end
	-- A REVEAL payload carries `crateName` and no crate definition (the server
	-- has already rolled; there is nothing left to price). Letting the crate
	-- table win unconditionally meant the last previewed crate renamed every
	-- later reveal — so only an explicitly supplied crate may rename the page.
	if crateGiven or not nameGiven then
		self._crateName = (self._crate and self._crate.name) or self._crateName
	end

	self:_GPClearConfetti()
	self:_GPClearSparkles()
	self:_GPClearReceipts()
	self._gpHeatHandle.Instance.Transparency = 1
	self._gpChamber.BackgroundColor3 = self._gpChamberCool
	self._gpTempRow.SetValue(gpToken(theme, "restTemperature"))
	self._gpFireRow.SetValue(0)

	if failure then
		-- The source's two exact refusals, verbatim.
		self._gpFailureBody.Text = if failure == "policy"
			then "Crates can only be opened with Cash on your account."
			else "Not enough to open that crate."
		self._gpPage.title.Text = gpSentence(self._crateName)
		self._gpPage.subtitle.Text = "Nothing was fired, and nothing was spent."
		self:_GPSetMode("failure")
		self:_PlaySound("Error")
		return
	end

	local hasResults = type(data) == "table" and type((data :: any).items) == "table" and #(data :: any).items > 0
	if not hasResults then
		self:_GPSetMode("preview")
		return
	end

	self:_GPSetMode("ceremony")
	-- ReduceMotion collapses the ceremony to its confirmed end state.
	local reduceMotion = self.Gui:GetAttribute("ReduceMotion") == true or self.Root:GetAttribute("ReduceMotion") == true
	self:_GPRenderPage(1, not reduceMotion)
	if reduceMotion then
		self:_GPSetStage("receipt")
	end

	if self._gpInputConn then
		self._gpInputConn:Disconnect()
	end
	-- One InputBegan connection per show, dropped on hide (zero growth).
	self._gpInputConn = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not self:IsVisible() or self._gpMode ~= "ceremony" then
			return
		end
		local inputType = input.UserInputType
		if inputType == Enum.UserInputType.Keyboard then
			if input.KeyCode == Enum.KeyCode.Escape then
				self:_GPSkipAll()
			else
				self:_GPAdvance()
			end
		elseif inputType == Enum.UserInputType.Gamepad1 then
			if input.KeyCode == Enum.KeyCode.ButtonB then
				self:_GPSkipAll()
			elseif input.KeyCode == Enum.KeyCode.ButtonA then
				self:_GPAdvance()
			end
		end
	end)
end

function CrateRevealScreen:_GPHide()
	self._gpStage = "idle"
	self:_GPClearConfetti()
	self:_GPClearSparkles()
	if self._gpInputConn then
		self._gpInputConn:Disconnect()
		self._gpInputConn = nil
	end
	if self._gpBurstLayer then
		self._gpBurstLayer.Visible = false
	end
	if self._gpHeatHandle then
		self._gpHeatHandle.Instance.Transparency = 1
	end
	if self._gpCatcher then
		self._gpCatcher.Visible = false
	end
	if self._gpSkip then
		self._gpSkip.root.Visible = false
	end
end

-- A style rebuild destroys the Gui, but UIShadow BUDGET counts only fall when
-- a handle is Released — hand every GP shadow back here, and stop the ticker.
function CrateRevealScreen:_OnTeardown()
	if self._gpStopTicker then
		self._gpStopTicker()
		self._gpStopTicker = nil
	end
	if self._gpInputConn then
		self._gpInputConn:Disconnect()
		self._gpInputConn = nil
	end
	if self._gpConfettiTweens then
		self:_GPClearConfetti()
	end
	if self._gpSparkles then
		self:_GPClearSparkles()
	end
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	-- Pooled rows are PARENTLESS while idle, so the Gui's destruction does not
	-- take them with it — they are destroyed by hand here.
	for _, bucket in { self._gpOddsRows, self._gpOddsPool, self._gpReceiptRows, self._gpReceiptPool } do
		if bucket then
			for _, row in bucket :: { any } do
				row.root:Destroy()
			end
			table.clear(bucket :: { any })
		end
	end
	self._gpPage = nil
	self._gpCeremony = nil
	self._gpPreview = nil
	self._gpFailure = nil
end

return CrateRevealScreen
