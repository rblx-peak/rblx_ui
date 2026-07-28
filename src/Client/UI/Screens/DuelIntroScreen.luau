--!strict
-- DUEL INTRO (the VS face-off) — ported from Brick Game's DuelController
-- showVsScreen/buildVsSide onto the Pottery Clash chrome.
--
-- BOXLESS over a staged camera shot (doc §11.8): the root is a transparent
-- full-screen frame with NO scrim — the "background" is the 3D shot the match
-- flow has already framed. Only the results screen dims the world.
--
-- Colour IS identity (doc §3.3): seat 1 is Semantic.Seat1 blue, seat 2 is
-- Semantic.Seat2 red, and the same colour drives that side's panel tint, name
-- and win pips. The VS wordmark keeps the source's rose/sky accents
-- (Semantic.VSRose left, Semantic.VSSky right) as the two bars flanking it and
-- the glow pads under each competitor.
--
-- Avatar headshots come from Players:GetUserThumbnailAsync inside a pcall on a
-- spawned thread (it yields and can throw for a brand-new/blocked user); a
-- generation counter drops a late result if the screen re-rendered, and the
-- boxless player icon stands in until — or instead of — the real headshot.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIScreenBase = require(script.Parent.UIScreenBase)
local ACLayoutKit = require(script.Parent.Parent.Framework.ACLayoutKit)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local UITicker = require(script.Parent.Parent.Framework.UITicker)
local PotteryDuelConfig = require(script.Parent.Parent.Config.PotteryDuelConfig)

export type Competitor = {
	name: string,
	userId: number?,
	wins: number?,
	-- The live face-off prints a competitor's skill rating, equipped title and
	-- lifetime wins under the avatar; the GP branch shows all three.
	skill: number?,
	title: string?,
}

-- Fixed px at the 1650×1020 baseline.
local SIDE_W, SIDE_H = 470, 580
local HEAD = 240
local PIP = 28 -- doc §8: win pips are 28px circles
local PIP_GAP = 10
local LEFT_X, RIGHT_X = 0.27, 0.73 -- the source's half-centres
local SIDE_Y = 0.5
local ENTRANCE_OFFSET = 620 -- how far off its own edge a side starts
local PULSE_PERIOD = 1.2

-- Empty pip fill+ring (the assignment's grey, kept as a literal because it is
-- pip chrome, not a palette role).
local PIP_EMPTY = Color3.fromRGB(70, 76, 90)

-- AC layout (theme.LayoutKit == "AC") fixed px: callsign band width and the
-- clearance each callsign keeps from the centre VS block.
local AC_SIDE_W = 420
local AC_VS_GAP = 60

-- GP layout (theme.LayoutKit == "GP") fixed px: the mode ribbon, the two
-- competitor plates, and the pip/tick chrome the countdown uses.
local GP_RIBBON = Vector2.new(780, 108)
local GP_SIDE_W, GP_SIDE_H = 440, 464
local GP_HEAD = 212
local GP_PIP = 18
local GP_PIP_GAP = 8
local GP_TICK_PIP = 12
local GP_COUNT_W, GP_COUNT_H = 156, 96
local GP_RULES = Vector2.new(660, 132)
local GP_TICK_FLASH = 0.18 -- how long one countdown tick's scale spike lasts
local GP_BREATHE = 2.4 -- radians/sec, the calm timer's breath
local GP_PANIC = 10 -- radians/sec, the last-ten-seconds panic
local GP_LOBBY_CHIP = Vector2.new(280, 54)

-- The phases where the SEATED WAITING LOBBY owns the screen instead of the
-- face-off: the live HUD shows its wait panel here and hides the banner, the
-- names bar and the big timer, so the two never stack.
local LOBBY_PHASES = { waiting = true, prematch = true }

local DEMO_LEFT: Competitor = { name = "ClayCrusher", wins = 1, skill = 1284, title = "Kiln Keeper" }
local DEMO_RIGHT: Competitor = { name = "KilnKing", wins = 0, skill = 1197, title = "Rookie" }

local DuelIntroScreen = setmetatable({}, { __index = UIScreenBase })
DuelIntroScreen.__index = DuelIntroScreen

function DuelIntroScreen.new()
	local self = UIScreenBase.new("DuelIntroScreen", 50)
	self._mode = "CLASSIC"
	self._bestOf = 3
	self._left = DEMO_LEFT :: Competitor
	self._right = DEMO_RIGHT :: Competitor
	self._renderGen = 0
	self._pulseGen = 0
	self._sides = {} :: { Frame }
	-- Match state the live HUD carries alongside the face-off: which phase's
	-- banner copy is up, which round of how many, and the countdown the server
	-- owns. Defaults are the opening face-off of a classic best-of-3.
	self._phase = "countdown"
	self._roundNum = 1
	self._totalRounds = PotteryDuelConfig.Timing.Rounds
	self._countdown = PotteryDuelConfig.Timing.CountdownSeconds
	self._showRules = true
	-- The seated lobby's own state: how many of the table's two chairs are
	-- filled, and whether this table locks its mode server-side (fixed-mode
	-- tables hide CHANGE MODE entirely rather than showing a dead button).
	self._seated = 2
	self._fixedMode = false
	self._lastTickSec = -1
	self._tickFlash = 0
	self._gpShadows = {} :: { any }
	self._stopTicker = nil :: (() -> ())?
	return setmetatable(self, DuelIntroScreen)
end

-- ========================================================================
-- Build
-- ========================================================================

function DuelIntroScreen:_BuildContent()
	if self:LayoutKit() == "AC" then
		self:_BuildACLayout()
		return
	end
	-- GP layout language: cutesy pastel ceramics — a petal mode ribbon, hue-
	-- matched shadows, and the live HUD's banner/countdown carried onto it.
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end

	local theme = self:GetTheme()
	local root = self.Root

	-- Mode title, FredokaOne 54 above the face-off (doc §2 type scale).
	local mode = UIChrome.Text("Mode", 54, theme.Arcade.Gold)
	mode.Text = ""
	mode.Position = UDim2.fromOffset(0, 46)
	mode.Size = UDim2.new(1, 0, 0, 64)
	mode.ZIndex = 32
	mode.Parent = root
	self._modeLabel = mode

	local bestOf = UIChrome.Text("BestOf", 24, theme.Colors.TextPrimary)
	bestOf.Text = ""
	bestOf.Position = UDim2.fromOffset(0, 112)
	bestOf.Size = UDim2.new(1, 0, 0, 30)
	bestOf.ZIndex = 32
	UIChrome.TextOutline(bestOf, 0.2)
	bestOf.Parent = root
	self._bestOfLabel = bestOf

	-- The VS wordmark: FredokaOne 130 gold, flanked by the rose (left) and sky
	-- (right) accent bars the source used for its two halves.
	local vsHolder = UIStyler.Frame("VS")
	vsHolder.BackgroundTransparency = 1
	vsHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	vsHolder.Position = UDim2.new(0.5, 0, SIDE_Y, 0)
	vsHolder.Size = UDim2.fromOffset(360, 190)
	vsHolder.ZIndex = 36
	vsHolder.Parent = root
	self._vsHolder = vsHolder

	local roseBar = UIStyler.Frame("RoseBar")
	roseBar.BackgroundColor3 = theme.Semantic.VSRose
	roseBar.AnchorPoint = Vector2.new(0, 0.5)
	roseBar.Position = UDim2.new(0, 0, 0.5, 0)
	roseBar.Size = UDim2.fromOffset(84, 10)
	roseBar.ZIndex = 36
	UIChrome.Stroke(theme, "Arcade", "Wheel").Parent = roseBar
	roseBar.Parent = vsHolder

	local skyBar = UIStyler.Frame("SkyBar")
	skyBar.BackgroundColor3 = theme.Semantic.VSSky
	skyBar.AnchorPoint = Vector2.new(1, 0.5)
	skyBar.Position = UDim2.new(1, 0, 0.5, 0)
	skyBar.Size = UDim2.fromOffset(84, 10)
	skyBar.ZIndex = 36
	UIChrome.Stroke(theme, "Arcade", "Wheel").Parent = skyBar
	skyBar.Parent = vsHolder

	local vs = UIChrome.Text("Wordmark", 130, theme.Arcade.Gold)
	vs.Text = "VS"
	vs.AnchorPoint = Vector2.new(0.5, 0.5)
	vs.Position = UDim2.fromScale(0.5, 0.5)
	vs.Size = UDim2.fromOffset(240, 170)
	vs.ZIndex = 37
	vs.Parent = vsHolder
end

-- ========================================================================
-- GP layout (theme.LayoutKit == "GP")
-- ========================================================================

-- Still BOXLESS (doc §11.8): no scrim, because the "background" is the staged
-- over-the-shoulder wheel shot the match flow already framed. What GP adds is
-- everything the live duel HUD carries during this beat and the older branches
-- dropped: the MODE BANNER (emoji, name, blurb, its signature hue), the phase
-- banner's title + subtitle, the big server countdown with its last-three-
-- seconds ticks and ten-second panic, the vs names bar, each competitor's
-- skill / title / wins, and the HOW TO PLAY card that rides the face-off.
function DuelIntroScreen:_BuildGPLayout()
	local theme = self:GetTheme()
	local root = self.Root
	local spacing = theme.Spacing
	self._gpShadows = {}

	-- ---- mode ribbon ----
	local ribbonFill = theme.Colors.Primary
	local ribbon = UIStyler.Frame("ModeBanner")
	ribbon.BackgroundColor3 = ribbonFill
	ribbon.AnchorPoint = Vector2.new(0.5, 0)
	ribbon.Position = UDim2.new(0.5, 0, 0, 26)
	ribbon.Size = UDim2.fromOffset(GP_RIBBON.X, GP_RIBBON.Y)
	ribbon.ZIndex = 31
	ribbon.Parent = root
	GPLayoutKit.Petal(theme, ribbon, 0)
	self._gpRibbonStroke = GPLayoutKit.SoftStroke(theme, ribbon, ribbonFill)
	self._gpRibbonShadow = GPLayoutKit.Shadow(theme, ribbon, "md", self._gpShadows, ribbonFill)
	GPLayoutKit.GlazeSheen(theme, ribbon)
	-- "Bottom" is the unrotated edge, so it is safe anywhere; the strip is kept
	-- because it RETINTS with the mode alongside the ribbon it hangs from.
	self._gpRibbonLip = GPLayoutKit.Scallop(theme, ribbon, "Bottom", ribbonFill)
	self._gpRibbon = ribbon

	-- Small eyebrow so the big word is unmistakably a MODE, not a player name.
	local eyebrow = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "Eyebrow")
	eyebrow.Text = "Game mode"
	eyebrow.Position = UDim2.fromOffset(0, spacing.S)
	eyebrow.Size = UDim2.new(1, 0, 0, 18)
	eyebrow.ZIndex = 33
	eyebrow.Parent = ribbon

	-- Display text on a saturated pastel is still TextPrimary: the near-white
	-- TextOnPrimary measures 2.14:1 on rose and 1.72:1 on matcha, and the mode
	-- tone can be either.
	local mode = GPLayoutKit.Text(theme, 42, theme.Colors.TextPrimary, "Mode")
	mode.Position = UDim2.fromOffset(0, spacing.S + 16)
	mode.Size = UDim2.new(1, 0, 0, 48)
	mode.ZIndex = 33
	mode.Parent = ribbon
	self._modeLabel = mode

	local blurb = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "Blurb")
	blurb.TextTruncate = Enum.TextTruncate.AtEnd
	blurb.Position = UDim2.fromOffset(spacing.M, spacing.S + 64)
	blurb.Size = UDim2.new(1, -spacing.M * 2, 0, 24)
	blurb.ZIndex = 33
	blurb.Parent = ribbon
	self._gpBlurb = blurb

	-- ---- phase banner ----
	local phaseTitle = GPLayoutKit.Text(theme, 30, theme.Colors.TextPrimary, "PhaseTitle")
	phaseTitle.Position = UDim2.fromOffset(0, 150)
	phaseTitle.Size = UDim2.new(1, 0, 0, 38)
	phaseTitle.ZIndex = 32
	phaseTitle.Parent = root
	self._gpPhaseTitle = phaseTitle

	local phaseSub = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "PhaseSub")
	phaseSub.Position = UDim2.fromOffset(0, 188)
	phaseSub.Size = UDim2.new(1, 0, 0, 24)
	phaseSub.ZIndex = 32
	phaseSub.Parent = root
	self._gpPhaseSub = phaseSub

	local bestOf = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "BestOf")
	bestOf.Position = UDim2.fromOffset(0, 212)
	bestOf.Size = UDim2.new(1, 0, 0, 20)
	bestOf.ZIndex = 32
	bestOf.Parent = root
	self._bestOfLabel = bestOf

	-- ---- countdown chip ----
	local countFill = theme.Arcade.Gold
	local countHolder = UIStyler.Frame("CountdownHolder")
	countHolder.BackgroundTransparency = 1
	countHolder.AnchorPoint = Vector2.new(0.5, 0)
	countHolder.Position = UDim2.new(0.5, 0, 0, 240)
	countHolder.Size = UDim2.fromOffset(GP_COUNT_W, GP_COUNT_H + 26)
	countHolder.ZIndex = 34
	countHolder.Parent = root
	self._gpCountHolder = countHolder

	local chip = UIStyler.Frame("Chip")
	chip.BackgroundColor3 = countFill
	chip.Size = UDim2.fromOffset(GP_COUNT_W, GP_COUNT_H)
	chip.ZIndex = 34
	chip.Parent = countHolder
	GPLayoutKit.Petal(theme, chip, 1)
	self._gpCountStroke = GPLayoutKit.SoftStroke(theme, chip, countFill)
	self._gpCountShadow = GPLayoutKit.Shadow(theme, chip, "md", self._gpShadows, countFill)
	self._gpCountChip = chip

	local chipScale = Instance.new("UIScale")
	chipScale.Parent = chip
	self._gpCountScale = chipScale

	-- Numerals on butter gold are TextPrimary: butter is a LIGHT fill and the
	-- near-white would vanish on it.
	local countLabel = GPLayoutKit.NumberText(theme, 58, theme.Colors.TextPrimary, "Countdown")
	countLabel.TextXAlignment = Enum.TextXAlignment.Center
	countLabel.Size = UDim2.fromScale(1, 1)
	countLabel.ZIndex = 35
	countLabel.Parent = chip
	self._gpCountLabel = countLabel

	-- Three tick pips: the live HUD ticks the last three whole seconds and only
	-- those, kept SEPARATE from the ten-second visual panic so the two tune
	-- apart. The pips make that window visible instead of audible-only.
	local ticks = UIStyler.Frame("Ticks")
	ticks.BackgroundTransparency = 1
	ticks.AnchorPoint = Vector2.new(0.5, 1)
	ticks.Position = UDim2.new(0.5, 0, 1, 0)
	ticks.Size = UDim2.fromOffset(
		PotteryDuelConfig.Timing.TickFromSeconds * GP_TICK_PIP + (PotteryDuelConfig.Timing.TickFromSeconds - 1) * GP_PIP_GAP,
		GP_TICK_PIP
	)
	ticks.ZIndex = 34
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, GP_PIP_GAP),
	}).Parent = ticks
	ticks.Parent = countHolder

	self._gpTicks = {}
	for index = 1, PotteryDuelConfig.Timing.TickFromSeconds do
		local pip = UIStyler.Frame("Tick" .. index)
		pip.BackgroundColor3 = theme.Arcade.RulerTrack
		pip.Size = UDim2.fromOffset(GP_TICK_PIP, GP_TICK_PIP)
		pip.LayoutOrder = index
		pip.ZIndex = 34
		pip.Parent = ticks
		UIStyler.Corner(theme.Radii.Pill).Parent = pip
		self._gpTicks[index] = pip
	end

	-- ---- the seated waiting lobby ----
	-- The mode banner's other half: while the table is filling, the live HUD
	-- prints how many chairs are taken, counts the prematch hold down, and
	-- keeps three things reachable — swap the mode, stand up, pull a friend in.
	local lobby = UIStyler.Frame("Lobby")
	lobby.BackgroundTransparency = 1
	lobby.Size = UDim2.fromScale(1, 1)
	lobby.Visible = false
	lobby.ZIndex = 33
	lobby.Parent = root
	self._gpLobby = lobby

	local seats = GPLayoutKit.NumberText(theme, 66, theme.Arcade.Gold, "Seats")
	seats.TextXAlignment = Enum.TextXAlignment.Center
	seats.Position = UDim2.fromOffset(0, 240)
	seats.Size = UDim2.new(1, 0, 0, 76)
	seats.ZIndex = 33
	seats.Parent = lobby
	self._gpSeats = seats

	-- Prematch hold. Hidden outright while the table is still short a potter —
	-- there is no deadline to show yet.
	local prematch = GPLayoutKit.Text(theme, 30, theme.Colors.TextPrimary, "Prematch")
	prematch.Position = UDim2.fromOffset(0, 322)
	prematch.Size = UDim2.new(1, 0, 0, 40)
	prematch.Visible = false
	prematch.ZIndex = 33
	prematch.Parent = lobby
	self._gpPrematch = prematch

	local changeFill = theme.Colors.Secondary
	local changeButton, changeLabel, changeChip, changeStroke, changeShadow = self:_GPChipButton(
		lobby,
		PotteryDuelConfig.Copy.ChangeMode,
		changeFill,
		GP_LOBBY_CHIP,
		function()
			self:_PlaySound("Click")
		end
	)
	changeButton.AnchorPoint = Vector2.new(0.5, 0.5)
	changeButton.Position = UDim2.new(0.5, 0, 0.64, 0)
	self._gpChangeLabel = changeLabel
	self._gpChangeChip = changeChip
	self._gpChangeStroke = changeStroke
	self._gpChangeShadow = changeShadow
	self._gpChangeButton = changeButton

	local leaveButton = self:_GPChipButton(
		lobby,
		PotteryDuelConfig.Copy.LeaveTable,
		theme.Colors.Error,
		GP_LOBBY_CHIP,
		function()
			self:_PlaySound("Click")
		end
	)
	leaveButton.AnchorPoint = Vector2.new(0.5, 0.5)
	leaveButton.Position = UDim2.new(0.5, 0, 0.735, 0)

	local inviteButton = self:_GPChipButton(
		lobby,
		PotteryDuelConfig.Copy.InviteFriends,
		theme.Arcade.Gold,
		GP_LOBBY_CHIP,
		function()
			self:_PlaySound("Click")
		end
	)
	inviteButton.AnchorPoint = Vector2.new(0.5, 0.5)
	inviteButton.Position = UDim2.new(0.5, 0, 0.83, 0)

	-- ---- VS medallion ----
	local vsFill = theme.Semantic.VSRose or theme.Colors.Primary
	local vsHolder = UIStyler.Frame("VS")
	vsHolder.BackgroundColor3 = vsFill
	vsHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	vsHolder.Position = UDim2.new(0.5, 0, SIDE_Y, 0)
	vsHolder.Size = UDim2.fromOffset(208, 208)
	vsHolder.ZIndex = 36
	vsHolder.Parent = root
	GPLayoutKit.CornerSet(theme, vsHolder, "Leaf")
	GPLayoutKit.SoftStroke(theme, vsHolder, vsFill)
	GPLayoutKit.Glow(theme, vsHolder, vsFill, self._gpShadows)
	GPLayoutKit.GlazeSheen(theme, vsHolder)
	self._vsHolder = vsHolder

	local vs = GPLayoutKit.Text(theme, 92, theme.Colors.TextPrimary, "Wordmark")
	vs.Text = "vs"
	vs.Size = UDim2.fromScale(1, 1)
	vs.ZIndex = 38
	vs.Parent = vsHolder

	-- ---- vs names bar ----
	local names = GPLayoutKit.Text(theme, 24, theme.Colors.TextPrimary, "Names")
	names.AnchorPoint = Vector2.new(0.5, 0)
	names.Position = UDim2.new(0.5, 0, SIDE_Y, 116)
	names.Size = UDim2.fromOffset(560, 32)
	names.ZIndex = 36
	names.Parent = root
	self._gpNames = names

	local round = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "Round")
	round.AnchorPoint = Vector2.new(0.5, 0)
	round.Position = UDim2.new(0.5, 0, SIDE_Y, 150)
	round.Size = UDim2.fromOffset(560, 24)
	round.ZIndex = 36
	round.Parent = root
	self._gpRound = round

	-- ---- how to play ----
	local rulesFill = theme.Colors.SurfaceRaised
	local rules = UIStyler.Frame("RulesCard")
	rules.BackgroundColor3 = rulesFill
	rules.AnchorPoint = Vector2.new(0.5, 1)
	rules.Position = UDim2.new(0.5, 0, 1, -26)
	rules.Size = UDim2.fromOffset(GP_RULES.X, GP_RULES.Y)
	rules.ZIndex = 33
	rules.Parent = root
	GPLayoutKit.Petal(theme, rules, 0)
	GPLayoutKit.SoftStroke(theme, rules, rulesFill)
	GPLayoutKit.Shadow(theme, rules, "md", self._gpShadows, rulesFill)
	self._gpRules = rules

	local rulesTitle = GPLayoutKit.Text(theme, theme.TextSizes.Title, theme.Colors.TextPrimary, "RulesTitle")
	rulesTitle.Text = PotteryDuelConfig.RulesTitle
	rulesTitle.TextXAlignment = Enum.TextXAlignment.Left
	rulesTitle.Position = UDim2.fromOffset(spacing.L, spacing.S)
	rulesTitle.Size = UDim2.new(1, -spacing.L * 2, 0, 34)
	rulesTitle.ZIndex = 34
	rulesTitle.Parent = rules

	for index, line in PotteryDuelConfig.RuleLines do
		local y = spacing.S + 38 + (index - 1) * 36
		local glyph = IconArchive.Image(rules, line.iconKey, 26)
		glyph.AnchorPoint = Vector2.new(0, 0.5)
		glyph.Position = UDim2.new(0, spacing.L, 0, y + 14)
		glyph.ZIndex = 34

		local text = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "Rule" .. index)
		text.Text = line.text
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.TextTruncate = Enum.TextTruncate.AtEnd
		text.Position = UDim2.fromOffset(spacing.L + 34, y)
		text.Size = UDim2.new(1, -(spacing.L * 2 + 34), 0, 28)
		text.ZIndex = 34
		text.Parent = rules
	end
end

-- A transparent GuiButton wearing a petal chip: the style enforcer backstops
-- any SOLID button with a BLACK stroke, which law 1 forbids outright. The chip
-- is handed back too, so a caller can retint it for a state change.
function DuelIntroScreen:_GPChipButton(
	parent: Instance,
	text: string,
	fill: Color3,
	size: Vector2,
	onClick: () -> ()
): (TextButton, TextLabel, Frame, UIStroke, any)
	local theme = self:GetTheme()
	local button = Instance.new("TextButton")
	button.Name = "Action"
	button.BackgroundTransparency = 1
	button.Text = ""
	button.AutoButtonColor = false
	button.Size = UDim2.fromOffset(size.X, size.Y)
	button.ZIndex = 34
	button.Parent = parent

	local chip = UIStyler.Frame("Chip")
	chip.BackgroundColor3 = fill
	chip.Size = UDim2.fromScale(1, 1)
	chip.ZIndex = 34
	chip.Parent = button
	GPLayoutKit.Petal(theme, chip, 0)
	local stroke = GPLayoutKit.SoftStroke(theme, chip, fill)
	local shadow = GPLayoutKit.Shadow(theme, chip, "sm", self._gpShadows, fill)

	-- Body copy on any pastel is TextPrimary; TextOnPrimary is display-only.
	local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Button, theme.Colors.TextPrimary, "Label")
	label.Text = text
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 35
	label.Parent = chip

	button.Activated:Connect(onClick)
	UIChrome.Animate(theme, button, chip)
	return button, label, chip, stroke, shadow
end

-- One competitor's plate: petal (mirrored by index so the pair reads hand-
-- arranged), a hue-matched shadow, the avatar in a nested well, and the four
-- readouts the live face-off prints — name, skill level, equipped title, wins
-- — over a seat-coloured strip and the best-of clinch pips.
function DuelIntroScreen:_BuildGPSide(competitor: Competitor, leftSide: boolean, gen: number): Frame
	local theme = self:GetTheme()
	local spacing = theme.Spacing
	local seat = if leftSide then theme.Semantic.Seat1 else theme.Semantic.Seat2
	local index = if leftSide then 0 else 1
	local hx = if leftSide then LEFT_X else RIGHT_X

	local plateFill = theme.Colors.SurfaceRaised
	local side = UIStyler.Frame(if leftSide then "SeatLeft" else "SeatRight")
	side.BackgroundColor3 = plateFill
	side.AnchorPoint = Vector2.new(0.5, 0.5)
	side.Position = UDim2.new(hx, 0, SIDE_Y, 0)
	side.Size = UDim2.fromOffset(GP_SIDE_W, GP_SIDE_H)
	side.ZIndex = 32
	side.Parent = self.Root
	GPLayoutKit.Petal(theme, side, index)
	GPLayoutKit.SoftStroke(theme, side, plateFill)
	GPLayoutKit.Shadow(theme, side, "lg", self._gpShadows, plateFill)

	-- The source's soft accent pad under the competitor, as a hue-matched glow
	-- on the avatar well instead of a flat rectangle.
	local wellFill = theme.Colors.Surface
	local headSlot = UIStyler.Frame("Head")
	headSlot.BackgroundColor3 = wellFill
	headSlot.AnchorPoint = Vector2.new(0.5, 0)
	headSlot.Position = UDim2.new(0.5, 0, 0, spacing.M)
	headSlot.Size = UDim2.fromOffset(GP_HEAD, GP_HEAD)
	headSlot.ClipsDescendants = true
	headSlot.ZIndex = 33
	headSlot.Parent = side
	GPLayoutKit.Petal(theme, headSlot, index + 1)
	GPLayoutKit.SoftStroke(theme, headSlot, seat)
	GPLayoutKit.Glow(theme, headSlot, seat, self._gpShadows)

	local fallback = IconArchive.Image(headSlot, "player", GP_HEAD - 76)
	fallback.AnchorPoint = Vector2.new(0.5, 0.5)
	fallback.Position = UDim2.fromScale(0.5, 0.5)
	fallback.ZIndex = 34

	local head = Instance.new("ImageLabel")
	head.Name = "Headshot"
	head.BackgroundTransparency = 1
	head.ScaleType = Enum.ScaleType.Fit
	head.AnchorPoint = Vector2.new(0.5, 0.5)
	head.Position = UDim2.fromScale(0.5, 0.5)
	head.Size = UDim2.fromScale(1, 1)
	head.Visible = false
	head.ZIndex = 35
	head.Parent = headSlot
	self:_LoadHeadshot(head, fallback, competitor.userId, gen)

	local name = GPLayoutKit.Text(theme, 34, theme.Colors.TextPrimary, "Name")
	name.Text = competitor.name
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(spacing.M, spacing.M + GP_HEAD + 6)
	name.Size = UDim2.new(1, -spacing.M * 2, 0, 42)
	name.ZIndex = 34
	name.Parent = side

	local skill = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Skill")
	skill.Text = string.format(PotteryDuelConfig.Copy.SkillLevel, math.floor(competitor.skill or 1000))
	skill.Position = UDim2.fromOffset(spacing.M, spacing.M + GP_HEAD + 50)
	skill.Size = UDim2.new(1, -spacing.M * 2, 0, 24)
	skill.ZIndex = 34
	skill.Parent = side

	-- Equipped title, on the pack's value colour.
	local badgeFill = theme.Arcade.Gold
	local badge = UIStyler.Frame("TitleBadge")
	badge.BackgroundColor3 = badgeFill
	badge.AnchorPoint = Vector2.new(0.5, 0)
	badge.Position = UDim2.new(0.5, 0, 0, spacing.M + GP_HEAD + 78)
	badge.Size = UDim2.fromOffset(212, 40)
	badge.ZIndex = 34
	badge.Parent = side
	GPLayoutKit.Petal(theme, badge, index + 1)
	GPLayoutKit.SoftStroke(theme, badge, badgeFill)
	GPLayoutKit.Shadow(theme, badge, "sm", self._gpShadows, badgeFill)

	local badgeText = GPLayoutKit.BodyText(theme, theme.TextSizes.Button, theme.Colors.TextPrimary, "TitleText")
	badgeText.Text = competitor.title or "Rookie"
	badgeText.TextTruncate = Enum.TextTruncate.AtEnd
	badgeText.Size = UDim2.fromScale(1, 1)
	badgeText.ZIndex = 35
	badgeText.Parent = badge

	local wins = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Wins")
	wins.Text = string.format(PotteryDuelConfig.Copy.Wins, math.floor(competitor.wins or 0))
	wins.Position = UDim2.fromOffset(spacing.M, spacing.M + GP_HEAD + 124)
	wins.Size = UDim2.new(1, -spacing.M * 2, 0, 24)
	wins.ZIndex = 34
	wins.Parent = side

	-- Seat identity as a strip of the seat colour (doc §3.3), not a recolour of
	-- the plate — the plate must stay the pack's cream so its shadow reads.
	local strip = UIStyler.Frame("SeatStrip")
	strip.BackgroundColor3 = seat
	strip.AnchorPoint = Vector2.new(0.5, 0)
	strip.Position = UDim2.new(0.5, 0, 0, spacing.M + GP_HEAD + 152)
	strip.Size = UDim2.fromOffset(GP_SIDE_W - spacing.L * 2, 26)
	strip.ZIndex = 34
	strip.Parent = side
	UIStyler.Corner(theme.Radii.Pill).Parent = strip

	local seatLabel = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "Seat")
	seatLabel.Text = if leftSide then "Seat 1" else "Seat 2"
	seatLabel.Size = UDim2.fromScale(1, 1)
	seatLabel.ZIndex = 35
	seatLabel.Parent = strip

	-- Win pips: one per round needed to clinch (best-of-N clinches at
	-- floor(N/2)+1), filled in the seat colour.
	local needed = math.max(1, math.floor(self._bestOf / 2) + 1)
	local won = math.clamp(competitor.wins or 0, 0, needed)
	local pips = UIStyler.Frame("Pips")
	pips.BackgroundTransparency = 1
	pips.AnchorPoint = Vector2.new(0.5, 1)
	pips.Position = UDim2.new(0.5, 0, 1, -spacing.M)
	pips.Size = UDim2.fromOffset(needed * GP_PIP + (needed - 1) * GP_PIP_GAP, GP_PIP)
	pips.ZIndex = 34
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, GP_PIP_GAP),
	}).Parent = pips
	pips.Parent = side

	for pipIndex = 1, needed do
		local filled = pipIndex <= won
		local pip = UIStyler.Frame("Pip" .. pipIndex)
		pip.BackgroundColor3 = if filled then seat else theme.Arcade.RulerTrack
		pip.Size = UDim2.fromOffset(GP_PIP, GP_PIP)
		pip.LayoutOrder = pipIndex
		pip.ZIndex = 34
		pip.Parent = pips
		GPLayoutKit.Petal(theme, pip, pipIndex)
	end

	return side
end

-- The GP render: same ordering and clinch math as classic, plus the mode
-- banner / phase banner / countdown refresh. The ribbon and the countdown chip
-- RETINT with the mode's tone, which is the pack's own rule demonstrated in a
-- live state — a matcha mode casts matcha, a clay mode casts clay.
function DuelIntroScreen:_RenderGPLayout()
	local theme = self:GetTheme()
	self._renderGen += 1
	local gen = self._renderGen

	for _, side in self._sides do
		side:Destroy()
	end
	table.clear(self._sides)

	local mode = PotteryDuelConfig.GetMode(self._mode)
	local tone = PotteryDuelConfig.Tone(theme, mode.tone)
	self._modeLabel.Text = string.format("%s  %s", mode.emoji, mode.displayName)
	self._gpBlurb.Text = mode.blurb
	self._gpRibbon.BackgroundColor3 = tone
	self._gpRibbonStroke.Color = GPLayoutKit.Deepen(theme, tone, 1)
	self._gpRibbonShadow.Instance.Color = GPLayoutKit.Deepen(theme, tone, 1)
	-- Both channels: the lip is a tinted image when the doily art is present
	-- and a soft rounded fill when it is not.
	self._gpRibbonLip.ImageColor3 = tone
	self._gpRibbonLip.BackgroundColor3 = tone

	-- The seated lobby and the face-off are MUTUALLY EXCLUSIVE, exactly as the
	-- live HUD has it: while the wait panel is up the banner, the names bar and
	-- the big timer all stand down rather than stacking on top of it.
	local lobby = LOBBY_PHASES[self._phase] == true
	self._gpLobby.Visible = lobby
	self._gpCountHolder.Visible = not lobby
	self._vsHolder.Visible = not lobby
	self._gpNames.Visible = not lobby
	self._gpRound.Visible = not lobby

	local title, subtitle = PotteryDuelConfig.PhaseText(self._phase)
	self._gpPhaseTitle.Text = title
	self._gpPhaseTitle.Visible = not lobby
	self._gpPhaseSub.Text = subtitle
	self._gpPhaseSub.Visible = subtitle ~= "" and not lobby
	self._gpSeats.Text = string.format(PotteryDuelConfig.Copy.SeatCount, self._seated)
	-- Fixed-mode tables lock their mode server-side, so the button is hidden
	-- outright rather than shown dead.
	self._gpChangeButton.Visible = not self._fixedMode
	self._bestOfLabel.Text = string.format(
		"%s  \u{00B7}  %d second rounds  \u{00B7}  %s",
		string.format(PotteryDuelConfig.Copy.BestOf, self._bestOf),
		mode.roundSeconds,
		mode.rewardBlurb
	)

	self._gpRound.Text = string.format(PotteryDuelConfig.Copy.RoundHeading, self._roundNum, self._totalRounds)
	-- HOW TO PLAY rides the face-off and the walk; the lobby has its own panel.
	self._gpRules.Visible = self._showRules and not lobby

	-- The competitor plates ARE the face-off, so they stand down with it. Still
	-- built either way: the entrance below must be able to spring them back in
	-- the moment the phase leaves the lobby.
	local leftSide = self:_BuildGPSide(self._left, true, gen)
	local rightSide = self:_BuildGPSide(self._right, false, gen)
	leftSide.Visible = not lobby
	rightSide.Visible = not lobby
	table.insert(self._sides, leftSide)
	table.insert(self._sides, rightSide)

	-- "A vs B", a lone name, or nothing — never a dangling "vs".
	local names = {}
	if self._left and self._left.name ~= "" then
		table.insert(names, self._left.name)
	end
	if self._right and self._right.name ~= "" then
		table.insert(names, self._right.name)
	end
	self._gpNames.Text = table.concat(names, "   vs   ")

	-- Entrance: each plate springs in from ITS OWN edge (doc §5 — springs,
	-- never fades).
	for index, side in self._sides do
		local home = side.Position
		local fromX = if index == 1 then -ENTRANCE_OFFSET else ENTRANCE_OFFSET
		side.Position = UDim2.new(home.X.Scale, fromX, home.Y.Scale, home.Y.Offset)
		UIChrome.PopIn(theme, side)
		TweenService:Create(side, theme.Motion.PopIn, { Position = home }):Play()
	end

	self._lastTickSec = -1
	self._tickFlash = 0
	self:_RenderCountdown()
	self:_StartCountdown()
end

-- Paint the countdown from self._countdown. Split out of the ticker so a
-- render with no time passing still shows the right number and pip state.
function DuelIntroScreen:_RenderCountdown()
	local theme = self:GetTheme()
	local timing = PotteryDuelConfig.Timing
	local secs = math.ceil(math.max(0, self._countdown))
	self._gpCountLabel.Text = tostring(secs)

	-- The prematch hold runs on the SAME server clock as the face-off timer,
	-- so it reads off the same number rather than keeping a second one. The
	-- mode freezes for the last few seconds: the button says so instead of
	-- letting a tap silently do nothing.
	local prematch = self._phase == "prematch"
	local locked = prematch and self._countdown <= timing.ModeLockSeconds
	self._gpPrematch.Visible = prematch
	if prematch then
		self._gpPrematch.Text = string.format(PotteryDuelConfig.Copy.Prematch, secs)
	end
	self._gpChangeLabel.Text = if locked
		then PotteryDuelConfig.Copy.ModeLocked
		else PotteryDuelConfig.Copy.ChangeMode
	-- Law 2: the chip's shadow and stroke are its OWN fill deepened, so a state
	-- recolour has to carry both with it or the shadow goes off-hue.
	local chipFill = if locked then theme.Colors.SurfaceRaised else theme.Colors.Secondary
	self._gpChangeChip.BackgroundColor3 = chipFill
	self._gpChangeStroke.Color = GPLayoutKit.Deepen(theme, chipFill, 1)
	self._gpChangeShadow.Instance.Color = GPLayoutKit.Deepen(theme, chipFill, 1)

	-- A pip per remaining tick-second: three lit at 3, one at 1, none once the
	-- clock is out of the window.
	for index, pip in self._gpTicks do
		local lit = secs > 0 and secs <= timing.TickFromSeconds and index <= secs
		pip.BackgroundColor3 = if lit then theme.Colors.Error else theme.Arcade.RulerTrack
	end

	local panic = self._countdown > 0 and self._countdown <= timing.PanicFromSeconds
	local base = if panic then theme.Colors.Error else theme.Arcade.Gold
	self._gpCountChip.BackgroundColor3 = base
	self._gpCountStroke.Color = GPLayoutKit.Deepen(theme, base, 1)
	self._gpCountShadow.Instance.Color = GPLayoutKit.Deepen(theme, base, 1)
end

-- ONE handler on the shared ticker for the whole countdown: the second
-- readout, the tick pips, the tick spike and the breathe/panic scale. Bound to
-- the root so a destroyed screen releases it even if teardown is ever missed.
function DuelIntroScreen:_StartCountdown()
	self:_StopCountdown()
	local theme = self:GetTheme()
	local timing = PotteryDuelConfig.Timing
	local peak = theme.Motion.PulseScale or 1.12
	local breathe = (theme.DialectTokens and (theme.DialectTokens :: any).motion and (theme.DialectTokens :: any).motion.breatheScale)
		or 0.02

	self._stopTicker = UITicker.Register(function(dt: number, now: number)
		if not self:IsVisible() or not self._gpCountChip or not self._gpCountChip.Parent then
			return
		end
		if self._countdown > 0 then
			self._countdown = math.max(0, self._countdown - dt)
		end

		-- The tick belongs to the FACE-OFF clock, not the seated lobby's prematch
		-- hold: the live HUD ticks only while its big timer is up, and the chip
		-- is stood down here, so an audible tick would have nothing on screen.
		local lobby = LOBBY_PHASES[self._phase] == true

		-- Keyed off the DISPLAYED second, so the tick lands exactly when the
		-- number changes and a frame-rate dip can never double-fire it.
		local secs = math.ceil(self._countdown)
		if secs ~= self._lastTickSec then
			self._lastTickSec = secs
			if not lobby and secs > 0 and secs <= timing.TickFromSeconds then
				self._tickFlash = GP_TICK_FLASH
				self:_PlaySound("Click")
			end
			self:_RenderCountdown()
		end

		if self._tickFlash > 0 then
			self._tickFlash = math.max(0, self._tickFlash - dt)
		end
		local panic = self._countdown > 0 and self._countdown <= timing.PanicFromSeconds
		local wave = 0.5 + 0.5 * math.sin(now * (if panic then GP_PANIC else GP_BREATHE))
		local spike = (peak - 1) * (self._tickFlash / GP_TICK_FLASH)
		self._gpCountScale.Scale = 1 + breathe * wave * (if panic then 3 else 1) + spike
	end, self.Root)
end

function DuelIntroScreen:_StopCountdown()
	if self._stopTicker then
		self._stopTicker()
		self._stopTicker = nil
	end
end

-- ========================================================================
-- AC layout (theme.LayoutKit == "AC")
-- ========================================================================

-- Static chrome for the AC face-off: two hairline bands framing the staged
-- shot (mode readout top, stand-by strip bottom) and the VS marker as a
-- small accent block. Still boxless — no scrim, the camera shot is the page.
function DuelIntroScreen:_BuildACLayout()
	local theme = self:GetTheme()
	local root = self.Root

	local topBand = UIStyler.Frame("TopBand")
	topBand.BackgroundColor3 = theme.Colors.Background
	topBand.BackgroundTransparency = 0.35
	topBand.Position = UDim2.fromOffset(0, 84)
	topBand.Size = UDim2.new(1, 0, 0, 58)
	topBand.ZIndex = 31
	topBand.Parent = root
	local topOver = ACLayoutKit.Rule(theme, topBand, 0.5)
	topOver.ZIndex = 32
	local topUnder = ACLayoutKit.Rule(theme, topBand, 0.5)
	topUnder.AnchorPoint = Vector2.new(0, 1)
	topUnder.Position = UDim2.new(0, 0, 1, 0)
	topUnder.ZIndex = 32

	local mode = UIChrome.Text("Mode", 18, theme.Colors.TextPrimary)
	mode.RichText = false
	mode.Text = ""
	mode.Position = UDim2.fromOffset(0, 8)
	mode.Size = UDim2.new(1, 0, 0, 24)
	mode.ZIndex = 32
	mode.Parent = topBand
	self._modeLabel = mode

	local bestOf = UIChrome.BodyText("BestOf", 11, theme.Colors.TextSecondary)
	bestOf.RichText = false
	bestOf.Text = ""
	bestOf.Position = UDim2.fromOffset(0, 34)
	bestOf.Size = UDim2.new(1, 0, 0, 16)
	bestOf.ZIndex = 32
	bestOf.Parent = topBand
	self._bestOfLabel = bestOf

	local bottomBand = UIStyler.Frame("BottomBand")
	bottomBand.BackgroundColor3 = theme.Colors.Background
	bottomBand.BackgroundTransparency = 0.35
	bottomBand.AnchorPoint = Vector2.new(0, 1)
	bottomBand.Position = UDim2.new(0, 0, 1, -84)
	bottomBand.Size = UDim2.new(1, 0, 0, 34)
	bottomBand.ZIndex = 31
	bottomBand.Parent = root
	local bottomOver = ACLayoutKit.Rule(theme, bottomBand, 0.5)
	bottomOver.ZIndex = 32
	local bottomUnder = ACLayoutKit.Rule(theme, bottomBand, 0.5)
	bottomUnder.AnchorPoint = Vector2.new(0, 1)
	bottomUnder.Position = UDim2.new(0, 0, 1, 0)
	bottomUnder.ZIndex = 32

	local standby = UIChrome.BodyText("StandBy", 11, theme.Colors.TextSecondary)
	standby.Text = "STAND BY"
	standby.Size = UDim2.fromScale(1, 1)
	standby.ZIndex = 32
	standby.Parent = bottomBand

	-- The VS marker: a small accent block with page-ink lettering.
	local vsHolder = UIStyler.Frame("VS")
	vsHolder.BackgroundColor3 = theme.Colors.Accent
	vsHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	vsHolder.Position = UDim2.new(0.5, 0, SIDE_Y, 0)
	vsHolder.Size = UDim2.fromOffset(44, 20)
	vsHolder.ZIndex = 36
	vsHolder.Parent = root
	self._vsHolder = vsHolder

	local vs = UIChrome.Text("Wordmark", 13, theme.Colors.TextOnPrimary)
	vs.Text = "VS"
	vs.Size = UDim2.fromScale(1, 1)
	vs.ZIndex = 37
	vs.Parent = vsHolder
end

-- One callsign band: name in mono against the shot, seat identity as colour
-- (doc §3.3), and the classic pips' clinch math as a dense "W n/m" readout.
function DuelIntroScreen:_BuildACSide(competitor: Competitor, leftSide: boolean): Frame
	local theme = self:GetTheme()
	local seat = if leftSide then theme.Semantic.Seat1 else theme.Semantic.Seat2
	local align = if leftSide then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left

	local side = UIStyler.Frame(if leftSide then "SeatLeft" else "SeatRight")
	side.BackgroundTransparency = 1
	side.AnchorPoint = Vector2.new(if leftSide then 1 else 0, 0.5)
	side.Position = UDim2.new(0.5, if leftSide then -AC_VS_GAP else AC_VS_GAP, SIDE_Y, 0)
	side.Size = UDim2.fromOffset(AC_SIDE_W, 44)
	side.ZIndex = 33
	side.Parent = self.Root

	local name = UIChrome.Text("Name", 18, theme.Colors.TextPrimary)
	name.RichText = false
	name.Text = string.upper(competitor.name)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.TextXAlignment = align
	name.Size = UDim2.new(1, 0, 0, 22)
	name.ZIndex = 33
	name.Parent = side

	-- Seat-colour hairline under the callsign: colour IS identity (§3.3).
	local underline = UIStyler.Frame("SeatRule")
	underline.BackgroundColor3 = seat
	underline.BackgroundTransparency = 0.35
	underline.BorderSizePixel = 0
	underline.Position = UDim2.fromOffset(0, 24)
	underline.Size = UDim2.new(1, 0, 0, 1)
	underline.ZIndex = 33
	underline.Parent = side

	-- Same clinch math as the classic pips (best-of-N clinches at floor(N/2)+1).
	local needed = math.max(1, math.floor(self._bestOf / 2) + 1)
	local wins = math.clamp(competitor.wins or 0, 0, needed)
	local seatLabel = UIChrome.BodyText("Seat", 11, seat)
	seatLabel.RichText = false
	seatLabel.Text = string.format("%s // W %d/%d", if leftSide then "SEAT 1" else "SEAT 2", wins, needed)
	seatLabel.TextXAlignment = align
	seatLabel.Position = UDim2.fromOffset(0, 30)
	seatLabel.Size = UDim2.new(1, 0, 0, 14)
	seatLabel.ZIndex = 33
	seatLabel.Parent = side

	return side
end

-- The AC render: hard snap — bands and callsigns place instantly (pages
-- boot, they do not morph), no entrance slide, no ambient pulse. Reuses
-- self._sides so re-renders and the classic path clean up the same way.
function DuelIntroScreen:_RenderACLayout()
	self._renderGen += 1

	for _, side in self._sides do
		side:Destroy()
	end
	table.clear(self._sides)

	self._modeLabel.Text = string.upper(self._mode)
	self._bestOfLabel.Text = string.format("BEST OF %d", self._bestOf)

	table.insert(self._sides, self:_BuildACSide(self._left, true))
	table.insert(self._sides, self:_BuildACSide(self._right, false))
end

-- ========================================================================
-- One competitor's side
-- ========================================================================

-- The avatar headshot, guarded: GetUserThumbnailAsync yields and throws for
-- unresolvable ids, so it runs on its own thread inside a pcall and only lands
-- if this render is still the current one.
function DuelIntroScreen:_LoadHeadshot(image: ImageLabel, fallback: GuiObject, userId: number?, gen: number)
	if not userId or userId <= 0 then
		return
	end
	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(
				userId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size150x150
			)
		end)
		if not ok or type(content) ~= "string" or content == "" then
			return
		end
		if gen ~= self._renderGen or not image.Parent then
			return
		end
		image.Image = content
		image.Visible = true
		fallback.Visible = false
	end)
end

function DuelIntroScreen:_BuildSide(competitor: Competitor, leftSide: boolean, gen: number): Frame
	local theme = self:GetTheme()
	local seat = if leftSide then theme.Semantic.Seat1 else theme.Semantic.Seat2
	local vsAccent = if leftSide then theme.Semantic.VSRose else theme.Semantic.VSSky
	local hx = if leftSide then LEFT_X else RIGHT_X

	local side = UIStyler.Frame(if leftSide then "SeatLeft" else "SeatRight")
	side.BackgroundColor3 = seat
	side.BackgroundTransparency = 0.55
	side.AnchorPoint = Vector2.new(0.5, 0.5)
	side.Position = UDim2.new(hx, 0, SIDE_Y, 0)
	side.Size = UDim2.fromOffset(SIDE_W, SIDE_H)
	side.ZIndex = 31
	UIChrome.Stroke(theme, "Arcade").Parent = side
	UIChrome.GlassGradient().Parent = side
	side.Parent = self.Root

	-- The source's soft accent pad under the competitor: rose left, sky right.
	local pad = UIStyler.Frame("Pad")
	pad.BackgroundColor3 = vsAccent
	pad.BackgroundTransparency = 0.5
	pad.AnchorPoint = Vector2.new(0.5, 0)
	pad.Position = UDim2.new(0.5, 0, 0, 40)
	pad.Size = UDim2.fromOffset(HEAD + 60, HEAD - 24)
	pad.ZIndex = 31
	UIChrome.Corner("Arcade", "Wheel").Parent = pad
	pad.Parent = side

	-- Circular avatar head (doc §4.2: circles are the arcade's sanctioned
	-- exception for heads and pips), ringed in the seat colour.
	local headSlot = UIStyler.Frame("Head")
	headSlot.BackgroundColor3 = theme.Arcade.NearBlack
	headSlot.AnchorPoint = Vector2.new(0.5, 0)
	headSlot.Position = UDim2.new(0.5, 0, 0, 34)
	headSlot.Size = UDim2.fromOffset(HEAD, HEAD)
	headSlot.ClipsDescendants = true
	headSlot.ZIndex = 32
	UIChrome.Corner("Arcade", "Pill").Parent = headSlot
	UIStyler.Stroke(seat, 4, 0).Parent = headSlot -- seat colour = identity (§3.3)
	headSlot.Parent = side

	local fallback = IconArchive.Image(headSlot, "player", HEAD - 70)
	fallback.AnchorPoint = Vector2.new(0.5, 0.5)
	fallback.Position = UDim2.fromScale(0.5, 0.5)
	fallback.ZIndex = 33

	local head = Instance.new("ImageLabel")
	head.Name = "Headshot"
	head.BackgroundTransparency = 1
	head.ScaleType = Enum.ScaleType.Fit
	head.AnchorPoint = Vector2.new(0.5, 0.5)
	head.Position = UDim2.fromScale(0.5, 0.5)
	head.Size = UDim2.fromScale(1, 1)
	head.Visible = false
	head.ZIndex = 34
	head.Parent = headSlot
	self:_LoadHeadshot(head, fallback, competitor.userId, gen)

	local name = UIChrome.Text("Name", 42, theme.Colors.TextPrimary)
	name.Text = competitor.name
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.AnchorPoint = Vector2.new(0.5, 0)
	name.Position = UDim2.new(0.5, 0, 0, 300)
	name.Size = UDim2.fromOffset(SIDE_W - 36, 52)
	name.ZIndex = 33
	name.Parent = side

	local seatLabel = UIChrome.Text("Seat", 22, seat)
	seatLabel.Text = if leftSide then "SEAT 1" else "SEAT 2"
	seatLabel.AnchorPoint = Vector2.new(0.5, 0)
	seatLabel.Position = UDim2.new(0.5, 0, 0, 354)
	seatLabel.Size = UDim2.fromOffset(SIDE_W - 36, 28)
	seatLabel.ZIndex = 33
	seatLabel.Parent = side

	-- Win pips: one per round needed to clinch (best-of-N clinches at
	-- floor(N/2)+1). Empty = grey fill + ring; won = the seat colour's ring
	-- with the competitor's headshot inside (doc §8).
	local needed = math.max(1, math.floor(self._bestOf / 2) + 1)
	local wins = math.clamp(competitor.wins or 0, 0, needed)
	local pips = UIStyler.Frame("Pips")
	pips.BackgroundTransparency = 1
	pips.AnchorPoint = Vector2.new(0.5, 0)
	pips.Position = UDim2.new(0.5, 0, 0, 400)
	pips.Size = UDim2.fromOffset(needed * PIP + (needed - 1) * PIP_GAP, PIP)
	pips.ZIndex = 33
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, PIP_GAP),
	}).Parent = pips
	pips.Parent = side

	for i = 1, needed do
		local won = i <= wins
		local pip = UIStyler.Frame("Pip" .. i)
		pip.BackgroundColor3 = if won then theme.Arcade.NearBlack else PIP_EMPTY
		pip.Size = UDim2.fromOffset(PIP, PIP)
		pip.LayoutOrder = i
		pip.ClipsDescendants = true
		pip.ZIndex = 33
		UIChrome.Corner("Arcade", "Pill").Parent = pip
		-- Ring colour is per-seat identity, which the black-only stroke policy
		-- cannot express; the primitive is still UIStyler's, not a raw UIStroke.
		UIStyler.Stroke(if won then seat else PIP_EMPTY, 3, 0).Parent = pip
		pip.Parent = pips
		if won then
			local shot = Instance.new("ImageLabel")
			shot.Name = "PipShot"
			shot.BackgroundTransparency = 1
			shot.ScaleType = Enum.ScaleType.Fit
			shot.Size = UDim2.fromScale(1, 1)
			shot.Visible = false
			shot.ZIndex = 34
			shot.Parent = pip
			local glyph = IconArchive.Image(pip, "check", PIP - 10)
			glyph.AnchorPoint = Vector2.new(0.5, 0.5)
			glyph.Position = UDim2.fromScale(0.5, 0.5)
			glyph.ZIndex = 34
			self:_LoadHeadshot(shot, glyph, competitor.userId, gen)
		end
	end

	return side
end

-- ========================================================================
-- Render + entrance
-- ========================================================================

function DuelIntroScreen:_Render()
	if self:LayoutKit() == "AC" then
		self:_RenderACLayout()
		return
	end
	if self:LayoutKit() == "GP" then
		self:_RenderGPLayout()
		return
	end

	local theme = self:GetTheme()
	self._renderGen += 1
	local gen = self._renderGen

	for _, side in self._sides do
		side:Destroy()
	end
	table.clear(self._sides)

	self._modeLabel.Text = string.upper(self._mode)
	self._bestOfLabel.Text = string.format("BEST OF %d", self._bestOf)

	table.insert(self._sides, self:_BuildSide(self._left, true, gen))
	table.insert(self._sides, self:_BuildSide(self._right, false, gen))

	-- Entrance: each side pops in from ITS OWN edge (doc §5 — springs, never
	-- fades), and the wordmark keeps pulsing while the face-off holds.
	for i, side in self._sides do
		local home = side.Position
		local fromX = if i == 1 then -ENTRANCE_OFFSET else ENTRANCE_OFFSET
		side.Position = UDim2.new(home.X.Scale, fromX, home.Y.Scale, home.Y.Offset)
		UIChrome.PopIn(theme, side)
		TweenService:Create(side, theme.Motion.PopIn, { Position = home }):Play()
	end
	self:_StartPulse()
end

function DuelIntroScreen:_StartPulse()
	self._pulseGen += 1
	local gen = self._pulseGen
	local theme = self:GetTheme()
	task.spawn(function()
		while gen == self._pulseGen and self:IsVisible() do
			-- Visibility-gated like every ambient effect (doc §5.4).
			if UIChrome.IsOnScreen(self._vsHolder) then
				UIChrome.Pulse(theme, self._vsHolder)
			end
			task.wait(PULSE_PERIOD)
		end
	end)
end

-- ========================================================================
-- Lifecycle
-- ========================================================================

function DuelIntroScreen:_OnShow(data: any?)
	if type(data) == "table" then
		if type(data.mode) == "string" then
			self._mode = data.mode
		end
		if type(data.bestOf) == "number" then
			self._bestOf = math.max(1, math.floor(data.bestOf))
		end
		if type(data.left) == "table" then
			self._left = data.left
		end
		if type(data.right) == "table" then
			self._right = data.right
		end
		-- Match state the GP branch renders; ignored by classic/AC, which have
		-- no banner or countdown to drive.
		if type(data.phase) == "string" then
			self._phase = data.phase
		end
		if type(data.roundNum) == "number" then
			self._roundNum = math.max(1, math.floor(data.roundNum))
		end
		if type(data.totalRounds) == "number" then
			self._totalRounds = math.max(1, math.floor(data.totalRounds))
		end
		if type(data.countdown) == "number" then
			self._countdown = math.max(0, data.countdown)
		end
		if type(data.showRules) == "boolean" then
			self._showRules = data.showRules
		end
		-- Seated-lobby state: how many chairs are filled, and whether this
		-- table's mode is locked server-side.
		if type(data.seated) == "number" then
			self._seated = math.clamp(math.floor(data.seated), 0, 2)
		end
		if type(data.fixedMode) == "boolean" then
			self._fixedMode = data.fixedMode
		end
	end
	self:_Render()
end

function DuelIntroScreen:_OnHide()
	-- Stops the pulse loop, releases the countdown ticker, and orphans any
	-- in-flight headshot fetch.
	self._pulseGen += 1
	self._renderGen += 1
	self:_StopCountdown()
end

function DuelIntroScreen:Update(data: any)
	if self._built and self:IsVisible() then
		self:_OnShow(data)
	end
end

-- A style rebuild destroys the Gui, but a UIShadow's BUDGET count only falls
-- when its handle is released — hand every GP shadow back here.
function DuelIntroScreen:_OnTeardown()
	self:_StopCountdown()
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	table.clear(self._sides)
	self._gpRibbon = nil
	self._gpRibbonStroke = nil
	self._gpRibbonShadow = nil
	self._gpRibbonLip = nil
	self._gpCountChip = nil
	self._gpCountStroke = nil
	self._gpCountShadow = nil
	self._gpCountScale = nil
	self._gpCountLabel = nil
	self._gpCountHolder = nil
	self._gpLobby = nil
	self._gpSeats = nil
	self._gpPrematch = nil
	self._gpChangeButton = nil
	self._gpChangeLabel = nil
	self._gpChangeChip = nil
	self._gpChangeStroke = nil
	self._gpChangeShadow = nil
	self._gpTicks = nil
	self._gpPhaseTitle = nil
	self._gpPhaseSub = nil
	self._gpBlurb = nil
	self._gpNames = nil
	self._gpRound = nil
	self._gpRules = nil
end

function DuelIntroScreen:Destroy()
	self:_OnHide()
	self:_OnTeardown()
	UIScreenBase.Destroy(self)
end

return DuelIntroScreen
