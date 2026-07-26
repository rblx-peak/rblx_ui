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

local TweenService = game:GetService("TweenService")

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIAssets = require(script.Parent.Parent.Config.UIAssets)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UIScreenBase = require(script.Parent.UIScreenBase)

export type Segment = {
	id: string,
	label: string,
	icon: string?,
	weight: number?,
	rarity: string?,
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

local SpinWheelScreen = setmetatable({}, { __index = UIScreenBase })
SpinWheelScreen.__index = SpinWheelScreen

function SpinWheelScreen.new()
	local self = UIScreenBase.new("SpinWheelScreen", 40)
	self._segments = DEMO_SEGMENTS :: { Segment }
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
		-- Every tap answers (doc §11.1): the press juice already played.
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
		self._hint.Text = "YOU WON:  " .. segment.label
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
	if self._spinButton then
		self._spinButton:Destroy()
		self._spinButton = nil
	end
	UIScreenBase.Destroy(self)
end

return SpinWheelScreen
