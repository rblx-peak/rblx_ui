--!strict
-- SPIN WHEEL — the walk-up prize wheel, ported from Brick Game's
-- SpinWheel.client.luau (+ SpinWheelConfig) onto the Pottery Clash chrome.
-- The source's choreography is preserved exactly (doc §5.3): the face spins
-- 4.2s Quint Out through 4 full laps plus the landing angle, then the award
-- popup appears at scale 0.6 off-screen top, DROPS to centre with 0.6s Bounce
-- Out, POPS to 1.3 (0.16s Quad), settles to 1 (0.4s Back Out), holds, and
-- exits upward at t=3.4s with 0.35s Back In.
--
-- Roblox GUI has no triangle primitive, so each wedge is a FAN of thin rotated
-- bars around the hub (the source's trick): they overlap solid at the centre
-- and splay to full sector width at the rim, reading as a true pie slice. Bar
-- width is derived from the arc the fan step subtends at the rim, so the fan
-- stays gap-free for ANY segment count, not just the source's eight.
--
-- Chrome is the doc §4.2 wheel exception — corners clamp to 5px
-- (UIChrome.Corner(family, "Wheel")) and strokes are the thin 1.2px black
-- (UIChrome.Stroke(..., "Wheel")) — lighter than the 3px HUD language.
-- The manifest marks this screen hidesHUD: it is a focused moment (doc §11.5).

--
-- GP (theme.LayoutKit == "GP") re-cuts the same wheel as a glazed plate: a
-- butter rim, pastel rarity wedges, petal chrome, hue-matched shadows — and
-- restores the two pieces of the source screen the arcade port dropped, the
-- Robux SPIN PACK buttons and the GRAND PRIZE showcase. See the GP section at
-- the bottom of this file.

local TweenService = game:GetService("TweenService")

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIAssets = require(script.Parent.Parent.Config.UIAssets)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local UITicker = require(script.Parent.Parent.Framework.UITicker)
local UIScreenBase = require(script.Parent.UIScreenBase)

export type Segment = {
	id: string,
	label: string,
	icon: string?,
	weight: number?,
	rarity: string?,
}

-- A Robux spin pack (the source's +5 SPINS / +10 SPINS dev products). A zero
-- productId is the source's "not set up yet" case and answers in the hint.
export type SpinPack = {
	id: string,
	label: string,
	spins: number,
	robux: number?,
	productId: number?,
}

-- The pedestal beside the source wheel: the actual grand-prize chair, shown
-- live in full colour while every other prize row is a silhouette.
export type GrandPrize = {
	name: string,
	icon: string?,
	rarity: string?,
	blurb: string?,
}

-- Fixed px at the 1650×1020 baseline (UIScreenBase attaches the UIScale).
local WHEEL = 560 -- disc diameter
local RIM = 12 -- gold rim thickness around the disc
local C = WHEEL / 2
local RADIUS = 260 -- bars run from the hub out to this radius
local BARS = 11 -- fan bars per wedge (the source's count)
local FAN_COVERAGE = 0.91 -- fraction of the wedge the fan spans (source: 41°/45°)
local HUB = 118
local WHEEL_Y = 0.46 -- vertical centre of the wheel, as a scale of the screen
local ODDS_W = 330
local ODDS_ROW = 62

local LAPS = 4
local SPIN_TWEEN = TweenInfo.new(4.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
-- The award popup beats (doc §5.3), in source order.
local AWARD_DROP = TweenInfo.new(0.6, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out)
local AWARD_POP = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local AWARD_SETTLE = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local AWARD_EXIT = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.In)
local AWARD_HOLD = 3.4
local AWARD_OFF = UDim2.new(0.5, 0, -0.3, 0)
local AWARD_HOME = UDim2.new(0.5, 0, 0.42, 0)

-- Rarity ramp (doc §3.3: rarity colours tint stroke + label). The shop accent
-- rotation carries the low/mid tiers; the top two claim gold ("valuable") and
-- magenta so a jackpot never reads as "just another purple".
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
		return a.ShopAccents[2]
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

-- LAW 5 (GP): no all-caps body copy. Prize labels arrive from a config that
-- SHOUTS ("1500 BUX", "RANDOM SKIN") because the arcade face wants them that
-- way, and the same table feeds both faces — so the pastel branch re-cases at
-- the point of drawing rather than forking the data. Only a string with NO
-- lowercase at all is touched: "Kiln God's Seat" and "R$79" pass through whole.
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

-- The house prize table, mirroring SpinWheelConfig's weights so the screen
-- renders (and spins, and pays out) standalone with no backend.
local DEMO_SEGMENTS: { Segment } = {
	{ id = "bux1500", label = "1500 BUX", icon = "chest", weight = 2.38, rarity = "Epic" },
	{ id = "skinUncommon", label = "RANDOM SKIN", icon = "crate", weight = 13.48, rarity = "Uncommon" },
	{ id = "spins3", label = "3 FREE SPINS", icon = "ticket", weight = 4.76, rarity = "Rare" },
	{ id = "grand", label = "GRAND PRIZE", icon = "crown", weight = 0.99, rarity = "Mythic" },
	{ id = "bux350", label = "350 BUX", icon = "bux", weight = 15.85, rarity = "Rare" },
	{ id = "cash500", label = "500 CASH", icon = "cash", weight = 17.15, rarity = "Common" },
	{ id = "spins1", label = "FREE SPIN", icon = "gift", weight = 14.14, rarity = "Uncommon" },
	{ id = "bux100", label = "100 BUX", icon = "bux", weight = 31.25, rarity = "Common" },
}

-- The source's two dev-product packs, and the pedestal prize.
local DEMO_PACKS: { SpinPack } = {
	{ id = "spins5", label = "+5 spins", spins = 5, robux = 79, productId = 0 },
	{ id = "spins10", label = "+10 spins", spins = 10, robux = 149, productId = 0 },
}

local DEMO_GRAND: GrandPrize = {
	name = "Kiln God's Seat",
	icon = "crown",
	rarity = "Mythic",
	blurb = "One seat, one server, one lucky potter.",
}

local SpinWheelScreen = setmetatable({}, { __index = UIScreenBase })
SpinWheelScreen.__index = SpinWheelScreen

function SpinWheelScreen.new()
	local self = UIScreenBase.new("SpinWheelScreen", 40)
	self._segments = DEMO_SEGMENTS :: { Segment }
	self._gp = false
	self._packs = DEMO_PACKS :: { SpinPack }
	self._grand = DEMO_GRAND :: GrandPrize
	-- Injected by Show(data): (packId: string) -> (). The screen never buys
	-- anything itself — it asks, exactly like the source's promptSpins.
	self._onBuyPack = nil :: ((packId: string) -> ())?
	-- Injected by Show(data): () -> number? — the authoritative landing index.
	-- Returning nil lets the screen roll the advertised weights itself, so the
	-- wheel is fully exercisable with no server attached.
	self._onSpin = nil :: (() -> number?)?
	self._spins = nil :: number?
	self._spinning = false
	self._topIndex = 1 -- the rarest wedge: golden icon + the sunburst odds row
	self._spinGen = 0
	self._awardGen = 0
	self._awardTweens = {} :: { Tween }
	self._spinTween = nil :: Tween?
	self._awardSpin = nil :: RBXScriptConnection?
	-- Frugal ambient effects (doc §5.4): every spin connection is stored and
	-- dropped on hide, and re-made by the next render.
	self._conns = {} :: { RBXScriptConnection }
	return setmetatable(self, SpinWheelScreen)
end

-- ========================================================================
-- Build
-- ========================================================================

function SpinWheelScreen:_BuildContent()
	-- GP layout language: the glazed plate, the pack buttons, the pedestal.
	if self:LayoutKit() == "GP" then
		self._gp = true
		self:_BuildGPLayout()
		return
	end
	self._gp = false

	local theme = self:GetTheme()
	local root = self.Root

	local title = UIChrome.Text("Title", 46, theme.Arcade.Gold)
	title.Text = "SPIN TO WIN"
	title.Position = UDim2.fromOffset(0, 24)
	title.Size = UDim2.new(1, 0, 0, 56)
	title.ZIndex = 22
	title.Parent = root

	-- Rim → disc → spinRoot. The disc clips to its own circle so a wedge fan
	-- can never spill past the rim while the face turns.
	local rim = UIStyler.Frame("Rim")
	rim.BackgroundColor3 = theme.Arcade.Gold
	rim.AnchorPoint = Vector2.new(0.5, 0.5)
	rim.Position = UDim2.new(0.5, 0, WHEEL_Y, 0)
	rim.Size = UDim2.fromOffset(WHEEL + RIM * 2, WHEEL + RIM * 2)
	rim.ZIndex = 20
	UIChrome.Corner("Arcade", "Pill").Parent = rim
	UIChrome.Stroke(theme, "Arcade", "Wheel").Parent = rim
	UIChrome.GlassGradient().Parent = rim
	rim.Parent = root
	self._rim = rim

	local disc = UIStyler.Frame("Disc")
	disc.BackgroundColor3 = theme.Arcade.NearBlack
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size = UDim2.fromOffset(WHEEL, WHEEL)
	disc.ClipsDescendants = true
	disc.ZIndex = 21
	UIChrome.Corner("Arcade", "Pill").Parent = disc
	UIChrome.Stroke(theme, "Arcade", "Wheel").Parent = disc
	disc.Parent = rim

	local spinRoot = UIStyler.Frame("Face")
	spinRoot.BackgroundTransparency = 1
	spinRoot.AnchorPoint = Vector2.new(0.5, 0.5)
	spinRoot.Position = UDim2.fromScale(0.5, 0.5)
	spinRoot.Size = UDim2.fromOffset(WHEEL, WHEEL)
	spinRoot.ZIndex = 22
	spinRoot.Parent = disc
	self._spinRoot = spinRoot

	-- Hub: covers the bars' overlapping origin so the centre reads clean.
	local hub = UIStyler.Frame("Hub")
	hub.BackgroundColor3 = theme.Arcade.NearBlack2
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.Position = UDim2.fromScale(0.5, 0.5)
	hub.Size = UDim2.fromOffset(HUB, HUB)
	hub.ZIndex = 26
	UIChrome.Corner("Arcade", "Pill").Parent = hub
	UIChrome.Stroke(theme, "Arcade", "Wheel").Parent = hub
	UIChrome.GlassGradient().Parent = hub
	hub.Parent = disc
	local hubIcon = IconArchive.Image(hub, "star", 58, { golden = true })
	hubIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	hubIcon.Position = UDim2.fromScale(0.5, 0.5)
	hubIcon.ZIndex = 27

	-- Pointer: a 45°-rotated gold square, its lower tip biting into the rim.
	local pointer = UIStyler.Frame("Pointer")
	pointer.BackgroundColor3 = theme.Arcade.Gold
	pointer.AnchorPoint = Vector2.new(0.5, 0.5)
	pointer.Rotation = 45
	pointer.Position = UDim2.new(0.5, 0, WHEEL_Y, -(WHEEL / 2 + RIM) + 6)
	pointer.Size = UDim2.fromOffset(46, 46)
	pointer.ZIndex = 28
	UIChrome.Corner("Arcade", "Wheel").Parent = pointer
	UIChrome.Stroke(theme, "Arcade", "Wheel").Parent = pointer
	UIChrome.GlassGradient().Parent = pointer
	pointer.Parent = root

	-- Odds panel (left), rarest first — the source's side panel.
	local odds = UIStyler.Frame("Odds")
	odds.BackgroundColor3 = theme.Arcade.NearBlack2
	odds.BackgroundTransparency = 0.15
	odds.AnchorPoint = Vector2.new(0, 0.5)
	odds.Position = UDim2.new(0, 28, 0.5, 0)
	odds.Size = UDim2.fromOffset(ODDS_W, 200)
	odds.ZIndex = 22
	UIChrome.Corner("Arcade", "Wheel").Parent = odds
	UIChrome.Stroke(theme, "Arcade", "Wheel").Parent = odds
	UIChrome.GlassGradient().Parent = odds
	odds.Parent = root
	self._odds = odds

	local oddsTitle = UIChrome.Text("OddsTitle", 24, theme.Arcade.Gold)
	oddsTitle.Text = "PRIZE ODDS"
	oddsTitle.TextXAlignment = Enum.TextXAlignment.Left
	oddsTitle.Position = UDim2.fromOffset(14, 10)
	oddsTitle.Size = UDim2.new(1, -28, 0, 30)
	oddsTitle.ZIndex = 23
	oddsTitle.Parent = odds

	local oddsList = UIStyler.Frame("OddsList")
	oddsList.BackgroundTransparency = 1
	oddsList.Position = UDim2.fromOffset(8, 48)
	oddsList.Size = UDim2.new(1, -16, 1, -60)
	oddsList.ZIndex = 23
	oddsList.Parent = odds
	self._oddsList = oddsList

	local hint = UIChrome.Text("Hint", 26, theme.Colors.TextPrimary)
	hint.Text = ""
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -196)
	hint.Size = UDim2.fromOffset(760, 34)
	hint.ZIndex = 22
	UIChrome.TextOutline(hint, 0.3)
	hint.Parent = root
	self._hint = hint

	self._spinButton = UIButtonComponent.new()
	self._spinButton:Create(root, {
		text = "SPIN",
		variant = "Gold",
		size = UDim2.fromOffset(300, 82),
		position = UDim2.new(0.5, 0, 1, -104),
		anchorPoint = Vector2.new(0.5, 1),
		onClick = function()
			self:_Spin()
		end,
	})
	self._spinButton.Root.ZIndex = 24

	self:_BuildAward(theme)
end

-- The award popup (doc §5.3). Built once and re-used: the choreography is a
-- position + UIScale story, never a rebuild.
function SpinWheelScreen:_BuildAward(theme: Types.UITheme)
	local award = UIStyler.Frame("Award")
	award.BackgroundColor3 = theme.Arcade.NearBlack2
	award.BackgroundTransparency = 0.12
	award.AnchorPoint = Vector2.new(0.5, 0.5)
	award.Position = AWARD_OFF
	award.Size = UDim2.fromOffset(380, 262)
	award.Visible = false
	award.ZIndex = 60
	UIChrome.Corner("Arcade", "Wheel").Parent = award
	-- Gold 3px ring: the doc's "selected / valuable" language (§4.3) — this is
	-- the you-won-it moment, not ordinary panel chrome.
	UIChrome.Stroke(theme, "Arcade", "Selection").Parent = award
	UIChrome.GlassGradient().Parent = award
	award.Parent = self.Root
	self._award = award

	local artSlot = UIStyler.Frame("ArtSlot")
	artSlot.BackgroundTransparency = 1
	artSlot.AnchorPoint = Vector2.new(0.5, 0.5)
	artSlot.Position = UDim2.new(0.5, 0, 0, 88)
	artSlot.Size = UDim2.fromOffset(130, 130)
	artSlot.ZIndex = 61
	artSlot.Parent = award
	self._awardArt = artSlot

	local title = UIChrome.Text("AwardTitle", 30, theme.Arcade.Gold)
	title.Text = "YOU WON"
	title.Position = UDim2.fromOffset(6, 158)
	title.Size = UDim2.new(1, -12, 0, 36)
	title.ZIndex = 62
	title.Parent = award

	local prize = UIChrome.Text("AwardPrize", 24, theme.Colors.TextPrimary)
	prize.Text = ""
	prize.TextTruncate = Enum.TextTruncate.AtEnd
	prize.Position = UDim2.fromOffset(6, 198)
	prize.Size = UDim2.new(1, -12, 0, 34)
	prize.ZIndex = 62
	prize.Parent = award
	self._awardPrize = prize

	local scale = Instance.new("UIScale")
	scale.Parent = award
	self._awardScale = scale
end

-- ========================================================================
-- Render (data-driven: segments decide the whole face + odds list)
-- ========================================================================

function SpinWheelScreen:_ClearConnections()
	for _, conn in self._conns do
		conn:Disconnect()
	end
	table.clear(self._conns)
end

function SpinWheelScreen:_Render()
	if self._gp then
		self:_GPRender()
		return
	end
	local theme = self:GetTheme()
	local segments = self._segments
	local n = #segments
	if n == 0 then
		return
	end

	self:_ClearConnections()
	self._spinRoot:ClearAllChildren()
	self._oddsList:ClearAllChildren()
	self._spinRoot.Rotation = 0

	-- The rarest wedge is the jackpot: golden icon art on the face and in the
	-- popup, plus the spinning sunburst on its odds row.
	local top, topWeight = 1, math.huge
	for i, segment in segments do
		local weight = segment.weight or 1
		if weight < topWeight then
			top, topWeight = i, weight
		end
	end
	self._topIndex = top

	local segAngle = 360 / n
	local step = segAngle * FAN_COVERAGE / (BARS - 1)
	-- Bar width = the arc one fan step subtends at the rim (+3px of overlap),
	-- so the fan closes into a solid wedge at ANY segment count.
	local barW = math.ceil(RADIUS * math.rad(step)) + 3

	for i, segment in segments do
		local baseAngle = (i - 1) * segAngle
		local accent = rarityAccent(theme, segment.rarity)

		for k = 1, BARS do
			local angle = baseAngle + (k - (BARS + 1) / 2) * step
			local rad = math.rad(angle)
			local bar = UIStyler.Frame("Bar")
			bar.BackgroundColor3 = accent
			bar.AnchorPoint = Vector2.new(0.5, 0.5)
			bar.Position = UDim2.fromOffset(
				C + math.sin(rad) * RADIUS / 2,
				C - math.cos(rad) * RADIUS / 2
			)
			bar.Size = UDim2.fromOffset(barW, RADIUS)
			bar.Rotation = angle
			bar.ZIndex = 22
			UIChrome.GlassGradient().Parent = bar
			bar.Parent = self._spinRoot
		end

		-- The label rides its own transparent sector container over the fan, so
		-- icon + text stay upright relative to their wedge as the face turns.
		local sector = UIStyler.Frame("Sector" .. i)
		sector.BackgroundTransparency = 1
		sector.AnchorPoint = Vector2.new(0.5, 0.5)
		sector.Position = UDim2.fromScale(0.5, 0.5)
		sector.Size = UDim2.fromOffset(WHEEL, WHEEL)
		sector.Rotation = baseAngle
		sector.ZIndex = 24
		sector.Parent = self._spinRoot

		local icon = IconArchive.Image(sector, segment.icon or "gift", 60, { golden = i == top })
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 22)
		icon.ZIndex = 25

		local label = UIChrome.Text("Label", 21, theme.Colors.TextPrimary)
		label.Text = segment.label
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.new(0.5, 0, 0, 88)
		label.Size = UDim2.fromOffset(112, 74)
		label.ZIndex = 25
		-- Long-text safety (doc §2): wrap, then scale down under a cap.
		-- TextScaled must be the LAST wrap-related assignment.
		label.TextWrapped = true
		UIStyler.TextSizeConstraint(21, 11).Parent = label
		label.TextScaled = true
		label.Parent = sector
	end

	-- Odds rows, rarest first (the source sorts by ascending chance).
	local total = 0
	for _, segment in segments do
		total += segment.weight or 1
	end
	local order = table.clone(segments)
	table.sort(order, function(a, b)
		return (a.weight or 1) < (b.weight or 1)
	end)

	self._odds.Size = UDim2.fromOffset(ODDS_W, 48 + n * ODDS_ROW + 12)
	for i, segment in order do
		local isTop = segment.id == segments[top].id
		local row = UIStyler.Frame("Odds" .. i)
		row.BackgroundTransparency = 1
		row.Position = UDim2.fromOffset(0, (i - 1) * ODDS_ROW)
		row.Size = UDim2.new(1, 0, 0, 56)
		row.ZIndex = 24
		row.Parent = self._oddsList

		local artSlot = UIStyler.Frame("Art")
		artSlot.BackgroundTransparency = 1
		artSlot.Position = UDim2.fromOffset(2, 2)
		artSlot.Size = UDim2.fromOffset(52, 52)
		artSlot.ZIndex = 24
		artSlot.Parent = row
		if isTop then
			-- The jackpot row gets the house glow motif (doc §10), 60°/s like
			-- the source's odds panel. Visibility-gated by UIChrome.Spin.
			local _, spin = UIAssets.SunburstBehind(artSlot, theme.Arcade.SunburstGold, 0.35, 60)
			table.insert(self._conns, spin)
		end
		local icon = IconArchive.Image(artSlot, segment.icon or "gift", 46, { golden = isTop })
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.ZIndex = 25

		local text = UIChrome.Text("Text", 20, rarityAccent(theme, segment.rarity))
		text.Text = string.format("%.2f%%  %s", (segment.weight or 1) / total * 100, segment.label)
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.Position = UDim2.fromOffset(62, 0)
		text.Size = UDim2.new(1, -66, 1, 0)
		text.ZIndex = 25
		text.TextWrapped = true
		UIStyler.TextSizeConstraint(20, 11).Parent = text
		text.TextScaled = true
		text.Parent = row
	end

	self:_RefreshSpinButton()
end

-- Spin count drives the button label/variant and the hint line, exactly like
-- the source's refreshSpinBtn. A zero-spin button stays live (doc §11.1) — it
-- dims in place and answers the tap with a toast.
function SpinWheelScreen:_RefreshSpinButton()
	if self._gp then
		self:_GPRefreshSpinButton()
		return
	end
	local spins = self._spins
	local button = self._spinButton
	if not button then
		return
	end
	if self._spinning then
		button:SetContent({ text = "..." })
		self._hint.Text = ""
		return
	end
	if spins == nil then
		button:SetContent({ text = "SPIN", variant = "Gold", dimmed = false })
		self._hint.Text = "TAP SPIN FOR A PRIZE!"
	elseif spins > 0 then
		button:SetContent({ text = string.format("SPIN (%d)", spins), variant = "Gold", dimmed = false })
		self._hint.Text = "USE YOUR FREE SPIN NOW!"
	else
		button:SetContent({ text = "SPIN (0)", variant = "Gold", dimmed = true })
		self._hint.Text = "Come back tomorrow for a free spin!"
	end
end

-- ========================================================================
-- Spinning
-- ========================================================================

local function weightedIndex(segments: { Segment }): number
	local total = 0
	for _, segment in segments do
		total += segment.weight or 1
	end
	local roll = math.random() * total
	local acc = 0
	for i, segment in segments do
		acc += segment.weight or 1
		if roll <= acc then
			return i
		end
	end
	return #segments
end

function SpinWheelScreen:_Spin()
	if self._spinning then
		return
	end
	local segments = self._segments
	local n = #segments
	if n == 0 then
		return
	end
	if self._spins ~= nil and self._spins <= 0 then
		-- Every tap answers (doc §11.1): the press juice already played. The
		-- hint line carries the source's own refusal even when no HUD is up to
		-- take the toast.
		self._hint.Text = "No spins left — a free one arrives tomorrow!"
		local hud = self.ScreenController and self.ScreenController:GetScreen("hud")
		if hud then
			hud:PushToast({ text = "No spins left — a free one arrives tomorrow!", variant = "Error" })
		end
		return
	end

	local index: number? = nil
	if self._onSpin then
		local ok, result = pcall(self._onSpin)
		if ok and type(result) == "number" then
			index = result
		end
	end
	-- No authoritative result: roll the advertised weights so the wheel is
	-- exercisable standalone.
	index = math.clamp(index or weightedIndex(segments), 1, n)

	self._spinning = true
	self._spinGen += 1
	local gen = self._spinGen
	if self._spins ~= nil then
		self._spins = math.max(0, self._spins - 1)
	end
	self:_RefreshSpinButton()

	-- Wedge i sits at (i-1)*segAngle with the pointer at 0 (top), so the face
	-- must END at -(i-1)*segAngle (mod 360) — plus four dramatic full laps.
	local segAngle = 360 / n
	local target = 360 * LAPS + (360 - (index - 1) * segAngle) % 360
	self._spinRoot.Rotation = self._spinRoot.Rotation % 360
	if self._spinTween then
		self._spinTween:Cancel()
	end
	local tween = TweenService:Create(self._spinRoot, SPIN_TWEEN, { Rotation = target })
	self._spinTween = tween
	tween.Completed:Once(function(state: Enum.PlaybackState)
		if state ~= Enum.PlaybackState.Completed or gen ~= self._spinGen then
			return
		end
		self._spinning = false
		self:_RefreshSpinButton()
		-- The celebration LAST, so the button refresh can't stamp over it.
		local segment = segments[index]
		-- The source's "YOU WON: <granted>", in each face's own voice: the arcade
		-- shouts it, the pastel pack may not (law 5 — no all-caps body copy).
		self._hint.Text = if self._gp
			then "You won: " .. gpSentence(segment.label)
			else "YOU WON:  " .. segment.label
		self:_ShowAward(segment, index == self._topIndex)
	end)
	tween:Play()
end

-- ========================================================================
-- Award popup (doc §5.3, beat for beat)
-- ========================================================================

function SpinWheelScreen:_CancelAward()
	for _, tween in self._awardTweens do
		tween:Cancel()
	end
	table.clear(self._awardTweens)
end

function SpinWheelScreen:_ShowAward(segment: Segment, golden: boolean)
	if self._gp then
		self:_GPShowAward(segment, golden)
		return
	end
	self:_CancelAward()
	self._awardGen += 1
	local gen = self._awardGen

	-- One award burst at a time: the previous popup's spin connection outlives
	-- its (destroyed) sunburst, so it is dropped before the new one is made.
	if self._awardSpin then
		self._awardSpin:Disconnect()
		self._awardSpin = nil
	end
	self._awardArt:ClearAllChildren()
	if golden then
		local _, spin = UIAssets.SunburstBehind(self._awardArt, self:GetTheme().Arcade.SunburstGold, 0.25, 45)
		self._awardSpin = spin
	end
	local icon = IconArchive.Image(self._awardArt, segment.icon or "gift", 96, { golden = golden })
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.ZIndex = 62

	self._awardPrize.Text = segment.label
	self._award.Visible = true
	self._award.Position = AWARD_OFF
	self._awardScale.Scale = 0.6
	self:_PlaySound("Success")

	local drop = TweenService:Create(self._award, AWARD_DROP, { Position = AWARD_HOME })
	table.insert(self._awardTweens, drop)
	drop.Completed:Once(function()
		if gen ~= self._awardGen then
			return
		end
		local pop = TweenService:Create(self._awardScale, AWARD_POP, { Scale = 1.3 })
		table.insert(self._awardTweens, pop)
		pop.Completed:Once(function()
			if gen ~= self._awardGen then
				return
			end
			local settle = TweenService:Create(self._awardScale, AWARD_SETTLE, { Scale = 1 })
			table.insert(self._awardTweens, settle)
			settle:Play()
		end)
		pop:Play()
	end)
	drop:Play()

	task.delay(AWARD_HOLD, function()
		if gen ~= self._awardGen or not self._award.Visible then
			return
		end
		local exit = TweenService:Create(self._award, AWARD_EXIT, { Position = AWARD_OFF })
		table.insert(self._awardTweens, exit)
		exit.Completed:Once(function()
			if gen == self._awardGen then
				self._award.Visible = false
			end
		end)
		exit:Play()
	end)
end

-- ========================================================================
-- Lifecycle
-- ========================================================================

function SpinWheelScreen:_OnShow(data: any?)
	if type(data) == "table" then
		if type(data.segments) == "table" and #data.segments > 0 then
			self._segments = data.segments
		end
		if type(data.onSpin) == "function" then
			self._onSpin = data.onSpin
		end
		if type(data.spins) == "number" then
			self._spins = data.spins
		end
		if type(data.packs) == "table" and #data.packs > 0 then
			self._packs = data.packs
		end
		if type(data.grand) == "table" then
			self._grand = data.grand
		end
		if type(data.onBuyPack) == "function" then
			self._onBuyPack = data.onBuyPack
		end
	end
	self:_Render()
	-- Open is an instant Visible flip (base); the pop lives on the CONTENT.
	UIChrome.PopIn(self:GetTheme(), self._rim)
end

function SpinWheelScreen:_OnHide()
	self._spinGen += 1
	self._awardGen += 1
	self._spinning = false
	if self._spinTween then
		self._spinTween:Cancel()
		self._spinTween = nil
	end
	self:_CancelAward()
	if self._award then
		self._award.Visible = false
		self._award.Position = AWARD_OFF
	end
	if self._awardSpin then
		self._awardSpin:Disconnect()
		self._awardSpin = nil
	end
	if self._gp and self._gpSparkles then
		self:_GPClearSparkles()
	end
	self:_ClearConnections()
end

function SpinWheelScreen:Update(data: any)
	if type(data) ~= "table" then
		return
	end
	if type(data.spins) == "number" then
		self._spins = data.spins
		if self._built then
			self:_RefreshSpinButton()
		end
	end
	if type(data.segments) == "table" and #data.segments > 0 then
		self._segments = data.segments
		if self._built then
			self:_Render()
		end
	end
end

function SpinWheelScreen:Destroy()
	self:_OnHide()
	if self._built then
		self:_OnTeardown()
	end
	if self._spinButton then
		self._spinButton:Destroy()
		self._spinButton = nil
	end
	UIScreenBase.Destroy(self)
end

-- ======================================================================
-- GP layout (theme.LayoutKit == "GP") — THE GLAZE WHEEL.
--
-- Same machine, re-thrown in the pack's clay: a butter rim with a soft amber
-- shadow, wedges cut from the pack's rarity ramp (adjacent wedges separated by
-- a lift toward cream so two Commons never read as one slice), petal chrome
-- everywhere, and every label in TextPrimary — the near-white TextOnPrimary
-- measures 2.14:1 on rose and cannot carry a wedge caption.
--
-- The spin itself is untouched, beat for beat: 4 laps + the landing angle over
-- 4.2s Quint Out, driven by the SHARED _Spin, so the authoritative index still
-- decides where it stops and this screen still never rolls anything.
--
-- FEATURES RESTORED FROM THE SOURCE (the arcade port had dropped them):
--   * the two Robux SPIN PACKS either side of the spin button, including the
--     source's exact answer when a product id is missing;
--   * the GRAND PRIZE pedestal, as a showcase card with its own aura;
--   * the source's three hint lines, verbatim in sentence case.
-- Density is up, not down: every odds row now carries its rarity, its
-- percentage, its "1 in N" and a chance meter, and the panel foots with the
-- house edge in plain words.
-- ======================================================================

local GP_WHEEL = 560
local GP_RIM = 16
local GP_C = GP_WHEEL / 2
local GP_RADIUS = 262
local GP_BARS = 11
local GP_FAN_COVERAGE = 0.91
local GP_HUB = 122
local GP_WHEEL_Y = 0.46
local GP_ODDS_W = 372
local GP_ODDS_ROW = 62
local GP_GRAND_W = 320
local GP_NEIGHBOUR_LIFT = 0.2 -- how far an even wedge lifts toward cream
-- A rarity colour in this pack is a FILL colour: the ramp starts at cream so a
-- WEDGE reads soft. Pulled straight onto TEXT it disappears — cream (the Common
-- tier) on blush measures 1.05:1, the same near-white-on-pastel failure the
-- pack's header corrects TextOnPrimary for. Anything that must be READ takes the
-- accent pulled toward ink; only the wedges keep the raw pastel. INK_PULL is the
-- text pull; METER_PULL is the lighter pull a bar needs against the cream track.
local GP_INK_PULL = 0.7
local GP_METER_PULL = 0.45

local function gpSurface(name: string, fill: Color3, transparency: number?): Frame
	local frame = UIStyler.Frame(name)
	frame.BackgroundColor3 = fill
	frame.BackgroundTransparency = transparency or 0
	return frame
end

local function gpIcon(theme: Types.UITheme, parent: Instance, key: string, sizePx: number, golden: boolean?): GuiObject
	local icon = IconArchive.Image(parent, key, sizePx, { golden = golden })
	if icon:IsA("TextLabel") then
		-- The archive's glyph fallback is born white-on-black; both colours are
		-- banned outright in this pack.
		icon.TextColor3 = theme.Colors.TextPrimary
		icon.TextStrokeTransparency = 1
	end
	return icon
end

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

type GPButton = {
	root: TextButton,
	chip: Frame,
	label: TextLabel,
	-- The budget handle, exposed because the button row is REBUILT on every
	-- render: destroying the instance alone leaves the shadow counter high
	-- forever (Capabilities only decrements on Release).
	shadow: any,
	SetText: (string) -> (),
	SetFill: (Color3) -> (),
	SetDimmed: (boolean) -> (),
}

-- Transparent button, fill on a petal chip child: UIStyleEnforcer backstops a
-- SOLID GuiButton with a black 2px stroke, and law 1 forbids black outright.
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
	local zIndex = opts.zIndex or 24

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
	GPLayoutKit.GlazeSheen(theme, chip)

	local label = GPLayoutKit.Text(theme, opts.textSize or theme.TextSizes.Button, theme.Colors.TextPrimary, "Label")
	label.Text = opts.text
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = zIndex + 2
	label.Parent = chip

	if opts.onClick then
		root.Activated:Connect(opts.onClick)
	end
	UIChrome.Animate(theme, root, chip)

	return {
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
			-- Dimmed IN PLACE, never removed: the tap must still answer.
			label.TextColor3 = if dimmed then theme.Colors.TextSecondary else theme.Colors.TextPrimary
			chip.BackgroundTransparency = if dimmed then 0.4 else 0
			shadow:SetEnabled(not dimmed)
		end,
	}
end

function SpinWheelScreen:_BuildGPLayout()
	local theme = self:GetTheme()
	local root = self.Root
	local spacing = theme.Spacing

	-- Classic leftovers must not leak into the pastel page.
	if self._spinButton then
		self._spinButton:Destroy()
		self._spinButton = nil
	end

	self._gpShadows = {} :: { any }
	self._gpOddsRows = {} :: { any }
	self._gpOddsPool = {} :: { any }
	self._gpPackButtons = {} :: { any }
	self._gpSparkles = {} :: { ImageLabel }

	-- The page floor: warm cream with the studio dialect's clay speckle. Not a
	-- scrim — this screen hides the HUD and OWNS the viewport.
	local floor = gpSurface("Floor", theme.Colors.Background, 0)
	floor.Size = UDim2.fromScale(1, 1)
	floor.ZIndex = 18
	floor.Parent = root
	local studioTokens = ((theme :: any).DialectTokens or {}).studio or {}
	local grain = GPLayoutKit.Tile(
		theme,
		studioTokens.patternKey or "speckle",
		GPLayoutKit.Deepen(theme, theme.Colors.Background, 1),
		studioTokens.speckleTransparency or 0.94,
		"ClayGrain"
	)
	grain.ZIndex = 18
	grain.Parent = floor

	local title = GPLayoutKit.Text(theme, theme.TextSizes.Title + 12, theme.Colors.TextPrimary, "Title")
	title.Text = "Spin the glaze wheel"
	title.Position = UDim2.fromOffset(0, 26)
	title.Size = UDim2.new(1, 0, 0, 52)
	title.ZIndex = 22
	title.Parent = root

	local subtitle = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Subtitle")
	subtitle.Text = "The server rolls it. The wheel only shows you where it landed."
	subtitle.Position = UDim2.fromOffset(0, 78)
	subtitle.Size = UDim2.new(1, 0, 0, 24)
	subtitle.ZIndex = 22
	subtitle.Parent = root

	-- Rim → disc → face. The disc clips to its own circle so a wedge fan can
	-- never spill past the rim while the face turns.
	local rimFill = theme.Arcade.Gold
	local rim = gpSurface("Rim", rimFill, 0)
	rim.AnchorPoint = Vector2.new(0.5, 0.5)
	rim.Position = UDim2.new(0.5, 0, GP_WHEEL_Y, 0)
	rim.Size = UDim2.fromOffset(GP_WHEEL + GP_RIM * 2, GP_WHEEL + GP_RIM * 2)
	rim.ZIndex = 20
	rim.Parent = root
	UIStyler.Corner(theme.Radii.Pill).Parent = rim
	GPLayoutKit.SoftStroke(theme, rim)
	GPLayoutKit.Shadow(theme, rim, "lg", self._gpShadows, rimFill)
	GPLayoutKit.GlazeSheen(theme, rim)
	self._rim = rim

	local discFill = theme.Colors.Surface
	local disc = gpSurface("Disc", discFill, 0)
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size = UDim2.fromOffset(GP_WHEEL, GP_WHEEL)
	disc.ClipsDescendants = true
	disc.ZIndex = 21
	disc.Parent = rim
	UIStyler.Corner(theme.Radii.Pill).Parent = disc

	local spinRoot = gpSurface("Face", discFill, 1)
	spinRoot.AnchorPoint = Vector2.new(0.5, 0.5)
	spinRoot.Position = UDim2.fromScale(0.5, 0.5)
	spinRoot.Size = UDim2.fromOffset(GP_WHEEL, GP_WHEEL)
	spinRoot.ZIndex = 22
	spinRoot.Parent = disc
	self._spinRoot = spinRoot

	-- Hub: covers the bars' overlapping origin. A circle, because a circle is
	-- geometry here and not decoration — the one place petals stay away.
	local hubFill = theme.Colors.Background
	local hub = gpSurface("Hub", hubFill, 0)
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.Position = UDim2.fromScale(0.5, 0.5)
	hub.Size = UDim2.fromOffset(GP_HUB, GP_HUB)
	hub.ZIndex = 26
	hub.Parent = disc
	UIStyler.Corner(theme.Radii.Pill).Parent = hub
	GPLayoutKit.SoftStroke(theme, hub)
	GPLayoutKit.Shadow(theme, hub, "sm", self._gpShadows, hubFill)
	local hubIcon = gpIcon(theme, hub, "wheel", 60)
	hubIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	hubIcon.Position = UDim2.fromScale(0.5, 0.5)
	hubIcon.ZIndex = 27

	-- Pointer: a soft rounded square on its corner, its lower tip biting the
	-- rim. Its shadow is butter deepened, never grey.
	local pointerFill = theme.Colors.Primary
	local pointer = gpSurface("Pointer", pointerFill, 0)
	pointer.AnchorPoint = Vector2.new(0.5, 0.5)
	pointer.Rotation = 45
	pointer.Position = UDim2.new(0.5, 0, GP_WHEEL_Y, -(GP_WHEEL / 2 + GP_RIM) + 8)
	pointer.Size = UDim2.fromOffset(48, 48)
	pointer.ZIndex = 28
	pointer.Parent = root
	UIStyler.Corner(theme.Radii.Small).Parent = pointer
	GPLayoutKit.SoftStroke(theme, pointer)
	GPLayoutKit.Shadow(theme, pointer, "sm", self._gpShadows, pointerFill)

	self:_BuildGPOdds(theme, root)
	self:_BuildGPGrand(theme, root)

	local hint = GPLayoutKit.BodyText(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "Hint")
	hint.Text = ""
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -136)
	hint.Size = UDim2.fromOffset(880, 32)
	hint.ZIndex = 22
	hint.Parent = root
	self._hint = hint

	-- The button row: pack, spin, pack — the source's exact arrangement.
	local buttonRow = gpSurface("Buttons", theme.Colors.Background, 1)
	buttonRow.AnchorPoint = Vector2.new(0.5, 1)
	buttonRow.Position = UDim2.new(0.5, 0, 1, -46)
	buttonRow.Size = UDim2.fromOffset(860, 82)
	buttonRow.ZIndex = 24
	buttonRow.Parent = root
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, spacing.M),
	}).Parent = buttonRow
	self._gpButtonRow = buttonRow

	self._gpStopTicker = UITicker.Register(function(dt: number, now: number)
		self:_GPStep(dt, now)
	end, self.Gui)
end

function SpinWheelScreen:_BuildGPOdds(theme: Types.UITheme, root: Instance)
	local spacing = theme.Spacing
	local panelFill = theme.Colors.SurfaceRaised

	local panel = gpSurface("Odds", panelFill, 0)
	panel.AnchorPoint = Vector2.new(0, 0.5)
	panel.Position = UDim2.new(0, 34, 0.5, 0)
	panel.Size = UDim2.fromOffset(GP_ODDS_W, 240)
	panel.ClipsDescendants = true
	panel.ZIndex = 22
	panel.Parent = root
	GPLayoutKit.Petal(theme, panel, 0)
	GPLayoutKit.SoftStroke(theme, panel)
	GPLayoutKit.Shadow(theme, panel, "md", self._gpShadows, panelFill)
	self._odds = panel

	local heading = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "OddsTitle")
	heading.Text = "What the wheel can give you"
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.TextTruncate = Enum.TextTruncate.AtEnd
	heading.Position = UDim2.fromOffset(spacing.M, spacing.S)
	heading.Size = UDim2.new(1, -spacing.M * 2, 0, 30)
	heading.ZIndex = 23
	heading.Parent = panel

	local list = gpSurface("OddsList", panelFill, 1)
	list.Position = UDim2.fromOffset(spacing.S, 46)
	list.Size = UDim2.new(1, -spacing.S * 2, 1, -(46 + 34))
	list.ZIndex = 23
	list.Parent = panel
	UIStyler.ListLayout({ Padding = UDim.new(0, 6) }).Parent = list
	self._oddsList = list

	local footer = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "OddsFooter")
	footer.Text = ""
	footer.TextXAlignment = Enum.TextXAlignment.Left
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.new(0, spacing.M, 1, -spacing.S)
	footer.Size = UDim2.new(1, -spacing.M * 2, 0, 22)
	footer.ZIndex = 23
	footer.Parent = panel
	self._gpOddsFooter = footer
end

-- The source's pedestal, flattened onto the page: the grand prize in full
-- colour with its own aura, while every other prize is a silhouette row.
function SpinWheelScreen:_BuildGPGrand(theme: Types.UITheme, root: Instance)
	local spacing = theme.Spacing
	local cardFill = theme.Colors.SurfaceRaised

	local card = gpSurface("GrandPrize", cardFill, 0)
	card.AnchorPoint = Vector2.new(1, 0.5)
	card.Position = UDim2.new(1, -34, 0.5, 0)
	card.Size = UDim2.fromOffset(GP_GRAND_W, 400)
	card.ZIndex = 22
	card.Parent = root
	GPLayoutKit.Petal(theme, card, 1)
	GPLayoutKit.SoftStroke(theme, card)
	GPLayoutKit.Shadow(theme, card, "md", self._gpShadows, cardFill)
	self._gpGrandCard = card

	local scale = Instance.new("UIScale")
	scale.Parent = card
	self._gpGrandScale = scale

	local eyebrow = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Eyebrow")
	eyebrow.Text = "On the pedestal"
	eyebrow.Position = UDim2.fromOffset(spacing.M, spacing.M)
	eyebrow.Size = UDim2.new(1, -spacing.M * 2, 0, 20)
	eyebrow.ZIndex = 23
	eyebrow.Parent = card

	local wellFill = theme.Colors.Surface
	local well = gpSurface("Well", wellFill, 0)
	well.Position = UDim2.fromOffset(spacing.M, 44)
	well.Size = UDim2.new(1, -spacing.M * 2, 0, 190)
	well.ClipsDescendants = true
	well.ZIndex = 23
	well.Parent = card
	GPLayoutKit.Petal(theme, well, 0)
	GPLayoutKit.SoftStroke(theme, well)
	GPLayoutKit.GlazeSheen(theme, well)
	self._gpGrandGlow = GPLayoutKit.Glow(theme, well, theme.Arcade.Gold, self._gpShadows)

	local burst = GPLayoutKit.Slice(theme, "sunburstSoft", theme.Arcade.SunburstGold, "GrandBurst")
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.Position = UDim2.fromScale(0.5, 0.5)
	burst.Size = UDim2.fromOffset(260, 260)
	burst.ImageTransparency = 0.6
	burst.ZIndex = 23
	burst.Parent = well
	self._gpGrandBurst = burst

	local artSlot = gpSurface("Art", wellFill, 1)
	artSlot.AnchorPoint = Vector2.new(0.5, 0.5)
	artSlot.Position = UDim2.fromScale(0.5, 0.5)
	artSlot.Size = UDim2.fromOffset(150, 150)
	artSlot.ZIndex = 25
	artSlot.Parent = well
	self._gpGrandArt = artSlot

	local name = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "GrandName")
	name.Text = ""
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(spacing.M, 246)
	name.Size = UDim2.new(1, -spacing.M * 2, 0, 30)
	name.ZIndex = 23
	name.Parent = card
	self._gpGrandName = name

	local rarityChipFill = theme.Colors.Surface
	local rarityChip = gpSurface("GrandRarity", rarityChipFill, 0)
	rarityChip.Position = UDim2.fromOffset(spacing.M, 282)
	rarityChip.Size = UDim2.fromOffset(150, 28)
	rarityChip.ZIndex = 23
	rarityChip.Parent = card
	UIStyler.Corner(theme.Radii.Pill).Parent = rarityChip
	-- The chip is re-tinted per rarity and the ramp's first tier is CREAM, which
	-- would leave it with no edge at all on the cream card. The soft stroke is
	-- what guarantees it always reads as a chip.
	self._gpGrandRarityStroke = GPLayoutKit.SoftStroke(theme, rarityChip)
	self._gpGrandRarityChip = rarityChip

	local rarityLabel = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "GrandRarityLabel")
	rarityLabel.Text = ""
	rarityLabel.Size = UDim2.fromScale(1, 1)
	rarityLabel.ZIndex = 24
	rarityLabel.Parent = rarityChip
	self._gpGrandRarityLabel = rarityLabel

	local blurb = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "GrandBlurb")
	blurb.Text = ""
	blurb.TextXAlignment = Enum.TextXAlignment.Left
	blurb.TextWrapped = true
	blurb.Position = UDim2.fromOffset(spacing.M, 318)
	blurb.Size = UDim2.new(1, -spacing.M * 2, 0, 44)
	blurb.ZIndex = 23
	blurb.Parent = card
	self._gpGrandBlurb = blurb

	local chance = GPLayoutKit.NumberText(theme, theme.TextSizes.Body, theme.Arcade.Gold, "GrandChance")
	chance.Text = ""
	chance.AnchorPoint = Vector2.new(1, 1)
	chance.Position = UDim2.new(1, -spacing.M, 1, -spacing.S)
	chance.Size = UDim2.fromOffset(180, 24)
	chance.ZIndex = 23
	chance.Parent = card
	self._gpGrandChance = chance
end

-- ---- pooled odds rows -----------------------------------------------

function SpinWheelScreen:_GPAcquireOddsRow(): any
	local pooled = table.remove(self._gpOddsPool)
	if pooled then
		pooled.root.Visible = true
		return pooled
	end
	local theme = self:GetTheme()
	local rowFill = theme.Colors.Surface

	local root = gpSurface("OddsRow", rowFill, 0)
	root.Size = UDim2.new(1, 0, 0, GP_ODDS_ROW - 6)
	root.ZIndex = 23

	local wellFill = theme.Colors.Background
	local well = gpSurface("Well", wellFill, 0)
	well.Position = UDim2.fromOffset(6, 6)
	well.Size = UDim2.fromOffset(44, 44)
	well.ZIndex = 24
	well.Parent = root

	local iconSlot = gpSurface("IconSlot", wellFill, 1)
	iconSlot.Size = UDim2.fromScale(1, 1)
	iconSlot.ZIndex = 25
	iconSlot.Parent = well

	local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "Label")
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Position = UDim2.fromOffset(58, 4)
	label.Size = UDim2.new(1, -(58 + 96), 0, 22)
	label.ZIndex = 24
	label.Parent = root

	local rarity = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Rarity")
	rarity.TextXAlignment = Enum.TextXAlignment.Left
	rarity.Position = UDim2.fromOffset(58, 26)
	rarity.Size = UDim2.new(1, -(58 + 96), 0, 18)
	rarity.ZIndex = 24
	rarity.Parent = root

	local pct = GPLayoutKit.NumberText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "Pct")
	pct.AnchorPoint = Vector2.new(1, 0)
	pct.Position = UDim2.new(1, -10, 0, 4)
	pct.Size = UDim2.fromOffset(92, 22)
	pct.ZIndex = 24
	pct.Parent = root

	local oneIn = GPLayoutKit.NumberText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "OneIn")
	oneIn.AnchorPoint = Vector2.new(1, 0)
	oneIn.Position = UDim2.new(1, -10, 0, 26)
	oneIn.Size = UDim2.fromOffset(92, 18)
	oneIn.ZIndex = 24
	oneIn.Parent = root

	local track = gpSurface("Track", theme.Arcade.RulerTrack, 0)
	track.AnchorPoint = Vector2.new(0, 1)
	track.Position = UDim2.new(0, 58, 1, -5)
	track.Size = UDim2.new(1, -(58 + 16), 0, 5)
	track.ZIndex = 24
	track.Parent = root
	UIStyler.Corner(theme.Radii.Pill).Parent = track

	local fill = gpSurface("Fill", theme.Colors.Primary, 0)
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = 25
	fill.Parent = track
	UIStyler.Corner(theme.Radii.Pill).Parent = fill

	return {
		root = root,
		well = well,
		iconSlot = iconSlot,
		label = label,
		rarity = rarity,
		pct = pct,
		oneIn = oneIn,
		fill = fill,
		burst = nil :: ImageLabel?,
	}
end

function SpinWheelScreen:_GPReleaseOddsRows()
	for _, row in self._gpOddsRows do
		row.root.Visible = false
		row.root.Parent = nil
		row.iconSlot:ClearAllChildren()
		if row.burst then
			row.burst:Destroy()
			row.burst = nil
		end
		table.insert(self._gpOddsPool, row)
	end
	table.clear(self._gpOddsRows)
end

-- ---- render ---------------------------------------------------------

function SpinWheelScreen:_GPRender()
	local theme = self:GetTheme()
	local segments = self._segments
	local n = #segments
	if n == 0 then
		return
	end

	self._spinRoot:ClearAllChildren()
	self._spinRoot.Rotation = 0
	self:_GPReleaseOddsRows()

	-- The rarest wedge is the jackpot: it wears the golden art, the pedestal
	-- card and the spinning aura on its odds row.
	local top, topWeight = 1, math.huge
	local total = 0
	for i, segment in segments do
		local weight = segment.weight or 1
		total += weight
		if weight < topWeight then
			top, topWeight = i, weight
		end
	end
	self._topIndex = top

	local segAngle = 360 / n
	local step = segAngle * GP_FAN_COVERAGE / (GP_BARS - 1)
	-- Bar width = the arc one fan step subtends at the rim (+3px overlap), so
	-- the fan closes into a solid wedge at ANY segment count.
	local barW = math.ceil(GP_RADIUS * math.rad(step)) + 3

	for i, segment in segments do
		local baseAngle = (i - 1) * segAngle
		-- Rarity carries the hue; the parity lift separates two neighbours of
		-- the same tier so a pastel wheel never reads as one smear.
		local wedge = gpRarityColor(theme, segment.rarity)
		if i % 2 == 0 then
			wedge = wedge:Lerp(theme.Colors.Background, GP_NEIGHBOUR_LIFT)
		end

		for k = 1, GP_BARS do
			local angle = baseAngle + (k - (GP_BARS + 1) / 2) * step
			local rad = math.rad(angle)
			local bar = gpSurface("Bar", wedge, 0)
			bar.AnchorPoint = Vector2.new(0.5, 0.5)
			bar.Position = UDim2.fromOffset(
				GP_C + math.sin(rad) * GP_RADIUS / 2,
				GP_C - math.cos(rad) * GP_RADIUS / 2
			)
			bar.Size = UDim2.fromOffset(barW, GP_RADIUS)
			bar.Rotation = angle
			bar.ZIndex = 22
			UIChrome.GlassGradient().Parent = bar
			bar.Parent = self._spinRoot
		end

		local sector = gpSurface("Sector" .. i, theme.Colors.Background, 1)
		sector.AnchorPoint = Vector2.new(0.5, 0.5)
		sector.Position = UDim2.fromScale(0.5, 0.5)
		sector.Size = UDim2.fromOffset(GP_WHEEL, GP_WHEEL)
		sector.Rotation = baseAngle
		sector.ZIndex = 24
		sector.Parent = self._spinRoot

		local icon = gpIcon(theme, sector, segment.icon or "gift", 58, i == top)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 24)
		icon.ZIndex = 25

		-- Body copy on a pastel wedge is ALWAYS TextPrimary (5.15:1 on rose);
		-- TextOnPrimary measures 2.14:1 there and is illegal here.
		local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Body + 3, theme.Colors.TextPrimary, "Label")
		label.Text = gpSentence(segment.label)
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.new(0.5, 0, 0, 86)
		label.Size = UDim2.fromOffset(118, 72)
		label.ZIndex = 25
		label.TextWrapped = true
		-- TextScaled must be the LAST wrap-related assignment.
		UIStyler.TextSizeConstraint(theme.TextSizes.Body + 3, 11).Parent = label
		label.TextScaled = true
		label.Parent = sector
	end

	-- Odds rows, rarest first (the source sorts by ascending chance).
	local order = table.clone(segments)
	table.sort(order, function(a, b)
		return (a.weight or 1) < (b.weight or 1)
	end)

	self._odds.Size = UDim2.fromOffset(GP_ODDS_W, 46 + n * GP_ODDS_ROW + 40)
	for i, segment in order do
		local isTop = segment.id == segments[top].id
		local accent = gpRarityColor(theme, segment.rarity)
		local pct = (segment.weight or 1) / total * 100
		local row = self:_GPAcquireOddsRow()
		row.root.LayoutOrder = i
		GPLayoutKit.Petal(theme, row.root, i)
		GPLayoutKit.Petal(theme, row.well, i + 1)
		row.label.Text = gpSentence(segment.label)
		row.rarity.Text = segment.rarity or "Common"
		row.rarity.TextColor3 = gpReadable(theme, accent, GP_INK_PULL)
		row.pct.Text = string.format("%.2f%%", pct)
		row.pct.TextColor3 = gpReadable(theme, accent, GP_INK_PULL)
		row.oneIn.Text = if pct > 0 then string.format("1 in %d", math.max(1, math.floor(100 / pct + 0.5))) else "—"
		-- The COMMONEST prize owns the longest bar, and Common is the cream tier —
		-- left raw it would be the one meter you cannot see.
		row.fill.BackgroundColor3 = gpReadable(theme, accent, GP_METER_PULL)
		row.fill.Size = UDim2.fromScale(math.clamp(pct / 100, 0.02, 1), 1)
		if isTop then
			local burst = GPLayoutKit.Slice(theme, "sunburstSoft", theme.Arcade.SunburstGold, "RowBurst")
			burst.AnchorPoint = Vector2.new(0.5, 0.5)
			burst.Position = UDim2.fromScale(0.5, 0.5)
			burst.Size = UDim2.fromOffset(62, 62)
			burst.ImageTransparency = 0.45
			burst.ZIndex = 24
			burst.Parent = row.well
			row.burst = burst
		end
		local icon = gpIcon(theme, row.iconSlot, segment.icon or "gift", 34, isTop)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.ZIndex = 26
		row.root.Parent = self._oddsList
		table.insert(self._gpOddsRows, row)
	end

	local topPct = (segments[top].weight or 1) / total * 100
	self._gpOddsFooter.Text = string.format("%d prizes · rarest lands %.2f%% of the time", n, topPct)

	self:_GPRenderGrand(segments[top], topPct)
	self:_GPRenderPacks()
	self:_GPRefreshSpinButton()
end

function SpinWheelScreen:_GPRenderGrand(topSegment: Segment, topPct: number)
	local theme = self:GetTheme()
	local grand = self._grand
	local rarity = grand.rarity or topSegment.rarity
	local accent = gpRarityColor(theme, rarity)

	self._gpGrandArt:ClearAllChildren()
	local art = gpIcon(theme, self._gpGrandArt, grand.icon or topSegment.icon or "crown", 130, true)
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.5)
	art.ZIndex = 26

	self._gpGrandName.Text = gpSentence(grand.name)
	self._gpGrandRarityLabel.Text = rarity or "Grand prize"
	self._gpGrandRarityChip.BackgroundColor3 = accent:Lerp(theme.Colors.Background, 0.5)
	self._gpGrandRarityStroke.Color = GPLayoutKit.Deepen(theme, accent, 1)
	self._gpGrandBlurb.Text = grand.blurb or "The one everybody walks over to look at."
	self._gpGrandChance.Text = string.format("%.2f%% per spin", topPct)
	self._gpGrandGlow.Instance.Color = accent
end

function SpinWheelScreen:_GPRenderPacks()
	local theme = self:GetTheme()
	for _, entry in self._gpPackButtons do
		-- Release BEFORE destroy: the budget counter only falls on Release.
		entry.button.shadow:Release()
		entry.button.root:Destroy()
	end
	table.clear(self._gpPackButtons)
	if self._gpSpinButton then
		self._gpSpinButton.shadow:Release()
		self._gpSpinButton.root:Destroy()
		self._gpSpinButton = nil
	end

	local packs = self._packs
	local left = packs[1]
	local right = packs[2]

	local function packButton(pack: SpinPack?, order: number, index: number)
		if not pack then
			return
		end
		local packName = gpSentence(pack.label)
		local label = if pack.robux then string.format("%s · R$%d", packName, pack.robux) else packName
		local button = gpButton(theme, self._gpButtonRow, {
			name = "Pack_" .. pack.id,
			text = label,
			fill = theme.Colors.Secondary,
			size = UDim2.fromOffset(230, 74),
			index = index,
			layoutOrder = order,
			sink = self._gpShadows,
			onClick = function()
				self:_GPBuyPack(pack)
			end,
		})
		table.insert(self._gpPackButtons, { button = button, pack = pack })
	end

	packButton(left, 1, 0)

	self._gpSpinButton = gpButton(theme, self._gpButtonRow, {
		name = "Spin",
		text = "Spin",
		fill = theme.Arcade.Gold,
		size = UDim2.fromOffset(280, 82),
		index = 1,
		textSize = theme.TextSizes.Title,
		layoutOrder = 2,
		sink = self._gpShadows,
		onClick = function()
			self:_Spin()
		end,
	})

	packButton(right, 3, 2)
end

function SpinWheelScreen:_GPBuyPack(pack: SpinPack)
	-- The source's exact answer when the dev products have not been set up.
	if (pack.productId or 0) == 0 then
		self._hint.Text = "Spin packs need their Robux product ids set up first."
		self:_PlaySound("Error")
		return
	end
	local onBuyPack = self._onBuyPack
	if onBuyPack then
		task.spawn(onBuyPack, pack.id)
	end
	self:_PlaySound("Click")
end

-- The source's refreshSpinBtn, hint lines and all.
function SpinWheelScreen:_GPRefreshSpinButton()
	local button = self._gpSpinButton
	if not button then
		return
	end
	local theme = self:GetTheme()
	local spins = self._spins
	if self._spinning then
		button.SetText("…")
		button.SetDimmed(false)
		self._hint.Text = "Round and round it goes."
		return
	end
	if spins == nil then
		button.SetText("Spin")
		button.SetFill(theme.Arcade.Gold)
		button.SetDimmed(false)
		self._hint.Text = "Give it a spin — something always comes out."
	elseif spins > 0 then
		button.SetText(string.format("Spin (%d)", spins))
		button.SetFill(theme.Arcade.Gold)
		button.SetDimmed(false)
		self._hint.Text = "Use your free spin now!"
	else
		button.SetText("Spin (0)")
		button.SetFill(theme.Arcade.Gold)
		-- Dimmed in place, never removed: the tap still answers.
		button.SetDimmed(true)
		self._hint.Text = "Come back tomorrow for a free spin!"
	end
end

-- ---- award ----------------------------------------------------------

function SpinWheelScreen:_GPBuildAward()
	local theme = self:GetTheme()
	local spacing = theme.Spacing

	local cardFill = theme.Colors.SurfaceRaised
	local award = gpSurface("Award", cardFill, 0)
	award.AnchorPoint = Vector2.new(0.5, 0.5)
	award.Position = AWARD_OFF
	award.Size = UDim2.fromOffset(420, 300)
	award.Visible = false
	award.ZIndex = 60
	award.Parent = self.Root
	GPLayoutKit.Petal(theme, award, 0)
	GPLayoutKit.SoftStroke(theme, award)
	GPLayoutKit.Shadow(theme, award, "lg", self._gpShadows, cardFill)
	GPLayoutKit.GlazeSheen(theme, award)
	self._award = award
	self._gpAwardGlow = GPLayoutKit.Glow(theme, award, theme.Arcade.Gold, self._gpShadows)

	local wellFill = theme.Colors.Surface
	local well = gpSurface("AwardWell", wellFill, 0)
	well.AnchorPoint = Vector2.new(0.5, 0)
	well.Position = UDim2.new(0.5, 0, 0, spacing.M)
	well.Size = UDim2.fromOffset(160, 160)
	well.ClipsDescendants = true
	well.ZIndex = 61
	well.Parent = award
	GPLayoutKit.Petal(theme, well, 1)
	GPLayoutKit.SoftStroke(theme, well)

	local burst = GPLayoutKit.Slice(theme, "sunburstSoft", theme.Arcade.SunburstGold, "AwardBurst")
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.Position = UDim2.fromScale(0.5, 0.5)
	burst.Size = UDim2.fromOffset(220, 220)
	burst.ImageTransparency = 0.5
	burst.Visible = false
	burst.ZIndex = 61
	burst.Parent = well
	self._gpAwardBurst = burst

	local artSlot = gpSurface("AwardArt", wellFill, 1)
	artSlot.AnchorPoint = Vector2.new(0.5, 0.5)
	artSlot.Position = UDim2.fromScale(0.5, 0.5)
	artSlot.Size = UDim2.fromOffset(120, 120)
	artSlot.ZIndex = 63
	artSlot.Parent = well
	self._awardArt = artSlot

	local title = GPLayoutKit.Text(theme, theme.TextSizes.Title, theme.Colors.TextPrimary, "AwardTitle")
	title.Text = "You won"
	title.Position = UDim2.fromOffset(spacing.S, 190)
	title.Size = UDim2.new(1, -spacing.S * 2, 0, 38)
	title.ZIndex = 62
	title.Parent = award

	local prize = GPLayoutKit.BodyText(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "AwardPrize")
	prize.Text = ""
	prize.TextTruncate = Enum.TextTruncate.AtEnd
	prize.Position = UDim2.fromOffset(spacing.S, 228)
	prize.Size = UDim2.new(1, -spacing.S * 2, 0, 32)
	prize.ZIndex = 62
	prize.Parent = award
	self._awardPrize = prize

	local rarity = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "AwardRarity")
	rarity.Text = ""
	rarity.Position = UDim2.fromOffset(spacing.S, 260)
	rarity.Size = UDim2.new(1, -spacing.S * 2, 0, 22)
	rarity.ZIndex = 62
	rarity.Parent = award
	self._gpAwardRarity = rarity

	local scale = Instance.new("UIScale")
	scale.Parent = award
	self._awardScale = scale
end

function SpinWheelScreen:_GPSparkleBurst()
	local theme = self:GetTheme()
	self:_GPClearSparkles()
	for i = 1, 8 do
		local angle = (i / 8) * math.pi * 2
		local sparkle = GPLayoutKit.Slice(theme, "sparkle", theme.Arcade.Gold, "Sparkle")
		sparkle.AnchorPoint = Vector2.new(0.5, 0.5)
		sparkle.Position = UDim2.new(0.5, math.floor(math.cos(angle) * 96), 0.5, math.floor(math.sin(angle) * 96))
		sparkle.Size = UDim2.fromOffset(30 + math.random(0, 14), 30 + math.random(0, 14))
		sparkle.Rotation = math.random(0, 360)
		sparkle.ImageTransparency = 0.15
		sparkle.ZIndex = 64
		sparkle.Parent = self._award
		table.insert(self._gpSparkles, sparkle)
	end
end

function SpinWheelScreen:_GPClearSparkles()
	for _, sparkle in self._gpSparkles do
		sparkle:Destroy()
	end
	table.clear(self._gpSparkles)
end

-- The source's award beats, unchanged: drop (0.6 Bounce Out) → pop to 1.3
-- (0.16 Quad) → settle to 1 (0.4 Back Out) → hold 3.4s → exit (0.35 Back In).
function SpinWheelScreen:_GPShowAward(segment: Segment, golden: boolean)
	local theme = self:GetTheme()
	if not self._award then
		self:_GPBuildAward()
	end
	self:_CancelAward()
	self:_GPClearSparkles()
	self._awardGen += 1
	local gen = self._awardGen

	local accent = gpRarityColor(theme, segment.rarity)
	self._awardArt:ClearAllChildren()
	local icon = gpIcon(theme, self._awardArt, segment.icon or "gift", 106, golden)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.ZIndex = 64

	self._awardPrize.Text = gpSentence(segment.label)
	self._gpAwardRarity.Text = segment.rarity or ""
	-- Text takes the readable pull; the GLOW keeps the raw hue (Glow lifts its
	-- own saturation, and an aura is a shape, not copy).
	self._gpAwardRarity.TextColor3 = gpReadable(theme, accent, GP_INK_PULL)
	self._gpAwardGlow.Instance.Color = accent
	self._gpAwardBurst.Visible = golden
	self._award.Visible = true
	self._award.Position = AWARD_OFF
	self._awardScale.Scale = 0.6
	self:_PlaySound("Success")
	if golden then
		self:_GPSparkleBurst()
	end

	local drop = TweenService:Create(self._award, AWARD_DROP, { Position = AWARD_HOME })
	table.insert(self._awardTweens, drop)
	drop.Completed:Once(function()
		if gen ~= self._awardGen then
			return
		end
		local pop = TweenService:Create(self._awardScale, AWARD_POP, { Scale = 1.3 })
		table.insert(self._awardTweens, pop)
		pop.Completed:Once(function()
			if gen ~= self._awardGen then
				return
			end
			local settle = TweenService:Create(self._awardScale, AWARD_SETTLE, { Scale = 1 })
			table.insert(self._awardTweens, settle)
			settle:Play()
		end)
		pop:Play()
	end)
	drop:Play()

	task.delay(AWARD_HOLD, function()
		if gen ~= self._awardGen or not self._award.Visible then
			return
		end
		local exit = TweenService:Create(self._award, AWARD_EXIT, { Position = AWARD_OFF })
		table.insert(self._awardTweens, exit)
		exit.Completed:Once(function()
			if gen == self._awardGen then
				self._award.Visible = false
				self:_GPClearSparkles()
			end
		end)
		exit:Play()
	end)
end

-- ---- ticker + teardown ----------------------------------------------

-- THE one shared Heartbeat handler for this screen: the pedestal aura, the
-- jackpot row's aura, and the pedestal card's slow breath. No screen in this
-- framework opens its own RunService loop.
function SpinWheelScreen:_GPStep(_dt: number, now: number)
	if not self:IsVisible() then
		return
	end
	local theme = self:GetTheme()
	local motion = ((theme :: any).DialectTokens or {}).motion or {}
	if self._gpGrandBurst then
		self._gpGrandBurst.Rotation = (now * 18) % 360
	end
	if self._gpAwardBurst and self._gpAwardBurst.Visible then
		self._gpAwardBurst.Rotation = (now * 24) % 360
	end
	for _, row in self._gpOddsRows do
		if row.burst then
			row.burst.Rotation = (now * 30) % 360
		end
	end
	if self._gpGrandScale then
		local depth = motion.breatheScale or 0.02
		local seconds = motion.breatheSeconds or 3
		self._gpGrandScale.Scale = 1 + depth * math.sin(now * (math.pi * 2 / math.max(seconds, 0.1)))
	end
end

function SpinWheelScreen:_OnTeardown()
	if self._gpStopTicker then
		self._gpStopTicker()
		self._gpStopTicker = nil
	end
	self:_CancelAward()
	if self._gpSparkles then
		self:_GPClearSparkles()
	end
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	-- Pooled rows are PARENTLESS while idle, so the Gui's destruction does not
	-- take them with it.
	for _, bucket in { self._gpOddsRows, self._gpOddsPool } do
		if bucket then
			for _, row in bucket :: { any } do
				row.root:Destroy()
			end
			table.clear(bucket :: { any })
		end
	end
	self._gpSpinButton = nil
	if self._gpPackButtons then
		table.clear(self._gpPackButtons)
	end
	self._award = nil
	self._gpGrandBurst = nil
	self._gpAwardBurst = nil
end

return SpinWheelScreen
