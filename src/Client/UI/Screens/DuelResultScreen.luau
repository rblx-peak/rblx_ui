--!strict
-- DUEL RESULT — ported from Brick Game's DuelController showResults onto the
-- Pottery Clash chrome.
--
-- This is the ONE cinematic screen that dims the world (doc §11.8): VS intro
-- and the waiting lobby are boxless over a staged camera shot, but results sit
-- behind a black scrim @ 0.4 so the numbers read.
--
-- Doc §11.4 conventions, kept literally from the source:
--   * the local player sorts LEFTMOST and carries a "(you)" suffix;
--   * gold marks the winner EVERYWHERE — headline, name, percent and the glow
--     pad behind their column;
--   * a defeat headline goes Arcade.Red, a tie stays white.
--
-- Avatar headshots come from Players:GetUserThumbnailAsync inside a pcall on a
-- spawned thread (it yields and can throw), with the boxless player icon
-- standing in until — or instead of — the real headshot.

local Players = game:GetService("Players")

local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UIScreenBase = require(script.Parent.UIScreenBase)
local ACLayoutKit = require(script.Parent.Parent.Framework.ACLayoutKit)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local UITicker = require(script.Parent.Parent.Framework.UITicker)
local PotteryDuelConfig = require(script.Parent.Parent.Config.PotteryDuelConfig)

export type PlayerResult = {
	name: string,
	userId: number?,
	score: number?,
	isLocal: boolean?,
	-- The live results column prints the two sub-scores under the percent
	-- ("shape 88%   colour 82%") and the table carries the REAL thrown pot;
	-- the GP branch renders both, plus the star grade the score earns.
	shape: number?,
	colour: number?,
	recipe: PotteryDuelConfig.PotRecipe?,
}

-- Fixed px at the 1650×1020 baseline.
local COL_W, COL_H = 420, 400
local COL_PITCH = 460
local HEAD = 200
local COLUMNS_Y = 0.56

-- AC layout (theme.LayoutKit == "AC") fixed px: the centred readout panel.
local AC_PANEL_W = 460
local AC_PANEL_H = 300

-- GP layout (theme.LayoutKit == "GP") fixed px.
local GP_COL_W, GP_COL_H = 460, 540
local GP_COL_PITCH = 500
local GP_HEAD = 150
local GP_PROFILE_H = 286
local GP_STAR = 18
local GP_STAR_GAP = 5
local GP_COLUMNS_Y = 0.52
local GP_COUNT_SECONDS = 1.0 -- how long a percent takes to count up
local GP_COUNT_DELAY = 0.35 -- yours first...
local GP_COUNT_STAGGER = 0.25 -- ...theirs a beat later
local GP_STAR_STEP = 0.07

local DEMO_RESULTS: { PlayerResult } = {
	{
		name = "ClayCrusher",
		score = 82,
		isLocal = true,
		shape = 88,
		colour = 82,
		recipe = PotteryDuelConfig.DemoMade,
	},
	{
		name = "KilnKing",
		score = 67,
		shape = 80,
		colour = 74,
		recipe = PotteryDuelConfig.DemoRival,
	},
}

local DuelResultScreen = setmetatable({}, { __index = UIScreenBase })
DuelResultScreen.__index = DuelResultScreen

function DuelResultScreen.new()
	local self = UIScreenBase.new("DuelResultScreen", 50)
	self._won = true
	self._headline = nil :: string?
	self._results = DEMO_RESULTS :: { PlayerResult }
	self._renderGen = 0
	self._columns = {} :: { Frame }
	-- The rest of what the live results window carries: the best-of round
	-- tally, the commission every pot was measured against, the confined-to-
	-- your-table re-seat countdown, and the loser's second-chance offer.
	self._roundWins = { 2, 1 }
	-- BETWEEN ROUNDS the same window becomes the round-end readout: which round
	-- just ended, who took it, and both marks counting up — over the world
	-- cinematic with NO scrim, and with none of the match-level furniture. nil
	-- means this is the match result proper.
	self._roundResult = nil :: any
	self._target = PotteryDuelConfig.DemoTarget :: PotteryDuelConfig.PotRecipe
	self._finalizing = true
	self._reseat = PotteryDuelConfig.Timing.IntermissionSeconds
	self._left = false -- this client already pressed Leave this window
	self._offer = nil :: any
	self._offerLeft = 0
	self._offerLocked = false
	self._elapsed = 0
	self._gpShadows = {} :: { any }
	self._gpColumns = {} :: { any }
	self._stopTicker = nil :: (() -> ())?
	return setmetatable(self, DuelResultScreen)
end

-- ========================================================================
-- Build
-- ========================================================================

function DuelResultScreen:_BuildContent()
	if self:LayoutKit() == "AC" then
		self:_BuildACLayout()
		return
	end
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end

	local theme = self:GetTheme()

	-- The scrim: results are the only cinematic screen that dims (doc §11.8).
	local scrim = UIStyler.Frame("Scrim")
	scrim.BackgroundColor3 = theme.Colors.Overlay
	scrim.BackgroundTransparency = 0.4
	scrim.ZIndex = 20
	scrim.Parent = self.Root
	self._scrim = scrim

	local content = UIStyler.Frame("Content")
	content.BackgroundTransparency = 1
	content.ZIndex = 21
	content.Parent = scrim
	self._content = content

	-- YOU WIN, FredokaOne 76 (doc §2 type scale).
	local headline = UIChrome.Text("Headline", 76, theme.Arcade.Gold)
	headline.Text = ""
	headline.Position = UDim2.fromOffset(0, 42)
	headline.Size = UDim2.new(1, 0, 0, 92)
	headline.ZIndex = 22
	headline.Parent = content
	self._headlineLabel = headline

	local tally = UIChrome.Text("Tally", 44, theme.Arcade.SunburstGold)
	tally.Text = ""
	tally.Position = UDim2.fromOffset(0, 136)
	tally.Size = UDim2.new(1, 0, 0, 52)
	tally.ZIndex = 22
	tally.Parent = content
	self._tally = tally

	self._continue = UIButtonComponent.new()
	self._continue:Create(content, {
		text = "CONTINUE",
		variant = "Green",
		size = UDim2.fromOffset(260, 62),
		position = UDim2.new(0.5, 0, 1, -46),
		anchorPoint = Vector2.new(0.5, 1),
		onClick = function()
			self.ScreenController:HideScreen("duelResult")
		end,
	})
	self._continue.Root.ZIndex = 23
end

-- ========================================================================
-- GP layout (theme.LayoutKit == "GP")
-- ========================================================================

-- The scrim is Colors.Overlay (a warm plum-brown), NOT black: results are the
-- one cinematic screen that dims the world, and this pack forbids pure black
-- even behind everything else.
--
-- What GP adds over the older branches, all of it from the live results
-- window: the best-of ROUND TALLY, each competitor's shape/colour sub-scores,
-- the star grade the score earns, the POT RECIPE COMPARISON (the pot each
-- potter actually threw, drawn over the commission's own profile), the
-- confined-to-your-table re-seat countdown with its Leave button, and the
-- loser's SECOND CHANCE offer with its tenth-of-a-second timer.
local function gpProfile(theme: any, parent: Instance, tint: Color3, transparency: number, zIndex: number): { Frame }
	local holder = UIStyler.Frame("Profile")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = zIndex
	holder.Parent = parent

	local count = PotteryDuelConfig.SampleRings
	local bars = table.create(count)
	local step = 1 / count
	for ring = 1, count do
		local bar = UIStyler.Frame("Ring" .. ring)
		bar.BackgroundColor3 = tint
		bar.BackgroundTransparency = transparency
		bar.AnchorPoint = Vector2.new(0.5, 1)
		bar.Position = UDim2.new(0.5, 0, 1 - (ring - 1) * step, 0)
		bar.Size = UDim2.new(0, 0, step, 1)
		bar.ZIndex = zIndex
		bar.Parent = holder
		UIStyler.Corner(theme.Radii.Small).Parent = bar
		bars[ring] = bar
	end
	return bars
end

local function layProfile(bars: { Frame }, radii: { number }, widest: number)
	for index, bar in bars do
		local radius = radii[index] or 0
		bar.Size = UDim2.new(math.clamp(radius / math.max(widest, 0.001), 0, 1), 0, 1 / #bars, 1)
	end
end

-- A transparent GuiButton wearing a petal chip: the enforcer backstops any
-- SOLID button with a BLACK stroke, which law 1 forbids outright.
function DuelResultScreen:_GPChipButton(parent: Instance, text: string, fill: Color3, size: Vector2, onClick: () -> ()): (TextButton, TextLabel)
	local theme = self:GetTheme()
	local button = Instance.new("TextButton")
	button.Name = "Action"
	button.BackgroundTransparency = 1
	button.Text = ""
	button.AutoButtonColor = false
	button.Size = UDim2.fromOffset(size.X, size.Y)
	button.ZIndex = 26
	button.Parent = parent

	local chip = UIStyler.Frame("Chip")
	chip.BackgroundColor3 = fill
	chip.Size = UDim2.fromScale(1, 1)
	chip.ZIndex = 26
	chip.Parent = button
	GPLayoutKit.Petal(theme, chip, 0)
	GPLayoutKit.SoftStroke(theme, chip, fill)
	GPLayoutKit.Shadow(theme, chip, "sm", self._gpShadows, fill)

	-- Body copy on any pastel is TextPrimary; TextOnPrimary is display-only.
	local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Button, theme.Colors.TextPrimary, "Label")
	label.Text = text
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 27
	label.Parent = chip

	button.Activated:Connect(onClick)
	UIChrome.Animate(theme, button, chip)
	return button, label
end

function DuelResultScreen:_BuildGPLayout()
	local theme = self:GetTheme()
	local spacing = theme.Spacing
	self._gpShadows = {}

	local scrim = UIStyler.Frame("Scrim")
	scrim.BackgroundColor3 = theme.Colors.Overlay
	scrim.BackgroundTransparency = 0.4
	scrim.ZIndex = 20
	scrim.Parent = self.Root
	self._scrim = scrim

	local content = UIStyler.Frame("Content")
	content.BackgroundTransparency = 1
	content.ZIndex = 21
	content.Parent = scrim
	self._content = content

	local headline = GPLayoutKit.Text(theme, 68, theme.Colors.TextPrimary, "Headline")
	headline.Text = ""
	headline.Position = UDim2.fromOffset(0, 34)
	headline.Size = UDim2.new(1, 0, 0, 84)
	headline.ZIndex = 22
	headline.Parent = content
	self._headlineLabel = headline

	local tallyCaption = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "TallyCaption")
	tallyCaption.Text = PotteryDuelConfig.Copy.RoundWins
	tallyCaption.Position = UDim2.fromOffset(0, 118)
	tallyCaption.Size = UDim2.new(1, 0, 0, 20)
	tallyCaption.ZIndex = 22
	tallyCaption.Parent = content
	self._gpTallyCaption = tallyCaption

	-- The round-end line, in the slot the match tally otherwise fills: who took
	-- the round, or that it was tied. Only ever up between rounds.
	local roundLine = GPLayoutKit.Text(theme, 38, theme.Arcade.Gold, "RoundLine")
	roundLine.Text = ""
	roundLine.Position = UDim2.fromOffset(0, 122)
	roundLine.Size = UDim2.new(1, 0, 0, 48)
	roundLine.Visible = false
	roundLine.ZIndex = 22
	roundLine.Parent = content
	self._gpRoundLine = roundLine

	local tally = GPLayoutKit.NumberText(theme, 42, theme.Arcade.Gold, "Tally")
	tally.TextXAlignment = Enum.TextXAlignment.Center
	tally.Text = ""
	tally.Position = UDim2.fromOffset(0, 136)
	tally.Size = UDim2.new(1, 0, 0, 50)
	tally.ZIndex = 22
	tally.Parent = content
	self._tally = tally

	local commission = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "Commission")
	commission.Position = UDim2.fromOffset(0, 186)
	commission.Size = UDim2.new(1, 0, 0, 20)
	commission.ZIndex = 22
	commission.Parent = content
	self._gpCommission = commission

	-- ---- bottom furniture: the verdict hand-off + the re-seat countdown ----
	local bar = UIStyler.Frame("BottomBar")
	bar.BackgroundTransparency = 1
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -26)
	bar.Size = UDim2.fromOffset(820, 110)
	bar.ZIndex = 25
	bar.Parent = content
	self._gpBottomBar = bar

	local panelFill = theme.Colors.SurfaceRaised
	local panel = UIStyler.Frame("ReseatPanel")
	panel.BackgroundColor3 = panelFill
	panel.Size = UDim2.fromScale(1, 1)
	panel.ZIndex = 25
	panel.Parent = bar
	GPLayoutKit.Petal(theme, panel, 0)
	GPLayoutKit.SoftStroke(theme, panel, panelFill)
	GPLayoutKit.Shadow(theme, panel, "md", self._gpShadows, panelFill)
	self._gpReseatPanel = panel

	local reseat = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "Reseat")
	reseat.TextXAlignment = Enum.TextXAlignment.Left
	reseat.Position = UDim2.fromOffset(spacing.L, spacing.M)
	reseat.Size = UDim2.fromOffset(420, 26)
	reseat.ZIndex = 26
	reseat.Parent = panel
	self._gpReseatLabel = reseat

	local reseatHint = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "ReseatHint")
	reseatHint.Text = "You are held at your own table until the next match forms."
	reseatHint.TextXAlignment = Enum.TextXAlignment.Left
	reseatHint.TextTruncate = Enum.TextTruncate.AtEnd
	reseatHint.Position = UDim2.fromOffset(spacing.L, spacing.M + 28)
	reseatHint.Size = UDim2.fromOffset(460, 22)
	reseatHint.ZIndex = 26
	reseatHint.Parent = panel

	local verdictButton = self:_GPChipButton(
		panel,
		PotteryDuelConfig.Copy.SeeVerdict,
		theme.Colors.Secondary,
		Vector2.new(240, 48),
		function()
			self.ScreenController:ShowScreen("judging")
		end
	)
	verdictButton.AnchorPoint = Vector2.new(1, 0.5)
	verdictButton.Position = UDim2.new(1, -(spacing.L + 160), 0.5, 0)

	local leaveButton, leaveLabel = self:_GPChipButton(
		panel,
		PotteryDuelConfig.Copy.Leave,
		theme.Colors.Error,
		Vector2.new(140, 48),
		function()
			self:_GPLeave()
		end
	)
	leaveButton.AnchorPoint = Vector2.new(1, 0.5)
	leaveButton.Position = UDim2.new(1, -spacing.L, 0.5, 0)
	self._gpLeaveButton = leaveButton
	self._gpLeaveLabel = leaveLabel

	self:_BuildGPSecondChance(content)
end

-- The storefront half of the live SECOND CHANCE offer: the loser gets a short,
-- server-owned window to buy one redemption round whose winner takes the
-- match. This card only ASKS — the countdown, the "buying" hand-off and the
-- locked "starting extra round" state are all mirrored from the payload.
function DuelResultScreen:_BuildGPSecondChance(parent: Instance)
	local theme = self:GetTheme()
	local spacing = theme.Spacing

	local fill = theme.Colors.SurfaceRaised
	local card = UIStyler.Frame("SecondChance")
	card.BackgroundColor3 = fill
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.new(0.5, 0, 0.42, 0)
	card.Size = UDim2.fromOffset(660, 330)
	card.Visible = false
	card.ZIndex = 36
	card.Parent = parent
	GPLayoutKit.Petal(theme, card, 0)
	GPLayoutKit.SoftStroke(theme, card, fill)
	GPLayoutKit.Shadow(theme, card, "lg", self._gpShadows, fill)
	GPLayoutKit.GlazeSheen(theme, card)
	self._gpOfferCard = card

	local title = GPLayoutKit.Text(theme, 30, theme.Colors.TextPrimary, "OfferTitle")
	title.Text = PotteryDuelConfig.Copy.SecondChanceTitle
	title.TextWrapped = true
	title.Position = UDim2.fromOffset(spacing.L, spacing.L)
	title.Size = UDim2.new(1, -spacing.L * 2, 0, 92)
	title.ZIndex = 37
	title.Parent = card

	local timer = GPLayoutKit.NumberText(theme, 34, theme.Colors.Error, "OfferTimer")
	timer.TextXAlignment = Enum.TextXAlignment.Center
	timer.Position = UDim2.fromOffset(0, 124)
	timer.Size = UDim2.new(1, 0, 0, 44)
	timer.ZIndex = 37
	timer.Parent = card
	self._gpOfferTimer = timer

	local yes, yesLabel = self:_GPChipButton(
		card,
		PotteryDuelConfig.Copy.SecondChanceYes,
		theme.Colors.Secondary,
		Vector2.new(250, 76),
		function()
			self:_GPOfferAnswer(true)
		end
	)
	yes.AnchorPoint = Vector2.new(0, 1)
	yes.Position = UDim2.new(0, spacing.L + 20, 1, -spacing.L)
	yes.ZIndex = 37
	self._gpOfferYes = yes
	self._gpOfferYesLabel = yesLabel

	local no, noLabel = self:_GPChipButton(
		card,
		PotteryDuelConfig.Copy.SecondChanceNo,
		theme.Colors.Error,
		Vector2.new(250, 76),
		function()
			self:_GPOfferAnswer(false)
		end
	)
	no.AnchorPoint = Vector2.new(1, 1)
	no.Position = UDim2.new(1, -(spacing.L + 20), 1, -spacing.L)
	no.ZIndex = 37
	self._gpOfferNo = no
	self._gpOfferNoLabel = noLabel

	-- The deal sticker, overlapping the YES chip. Rotation is fine HERE: it is
	-- card chrome inside its host's bounds, never inside a scrolling viewport.
	local badgeFill = theme.Arcade.Gold
	local badge = UIStyler.Frame("OfferBadge")
	badge.BackgroundColor3 = badgeFill
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.new(0, spacing.L + 145, 1, -(spacing.L + 66))
	badge.Size = UDim2.fromOffset(160, 34)
	badge.Rotation = -8
	badge.ZIndex = 38
	badge.Parent = card
	GPLayoutKit.Petal(theme, badge, 1)
	GPLayoutKit.SoftStroke(theme, badge, badgeFill)

	local badgeText = GPLayoutKit.BodyText(theme, theme.TextSizes.Button, theme.Colors.TextPrimary, "BadgeText")
	badgeText.Text = PotteryDuelConfig.Copy.SecondChanceBadge
	badgeText.Size = UDim2.fromScale(1, 1)
	badgeText.ZIndex = 39
	badgeText.Parent = badge
end

-- One competitor's plate. Everything the live column had (avatar, name with
-- the "(you)" suffix, the counting percent, gold on the winner) plus the three
-- readouts it dropped: the shape/colour sub-scores, the star grade, and the
-- pot's own ring profile over the commission's.
function DuelResultScreen:_BuildGPColumn(result: PlayerResult, index: number, count: number, winner: boolean, gen: number): Frame
	local theme = self:GetTheme()
	local spacing = theme.Spacing
	local score = result.score or 0
	local stars = PotteryDuelConfig.StarsFor(math.clamp(score / 100, 0, 1))
	local tier = PotteryDuelConfig.TierFor(stars)
	local accent = if winner then theme.Arcade.Gold else theme.Colors.Primary

	local plateFill = theme.Colors.SurfaceRaised
	local column = UIStyler.Frame("Result" .. index)
	column.BackgroundColor3 = plateFill
	column.AnchorPoint = Vector2.new(0.5, 0.5)
	column.Position = UDim2.new(0.5, (index - (count + 1) / 2) * GP_COL_PITCH, GP_COLUMNS_Y, 0)
	column.Size = UDim2.fromOffset(GP_COL_W, GP_COL_H)
	column.ZIndex = 22
	column.Parent = self._content
	GPLayoutKit.Petal(theme, column, index)
	GPLayoutKit.SoftStroke(theme, column, plateFill)
	GPLayoutKit.Shadow(theme, column, "lg", self._gpShadows, plateFill)
	table.insert(self._columns, column)

	-- The winner blooms rather than falls into shade: a zero-offset gold aura.
	if winner then
		GPLayoutKit.Glow(theme, column, theme.Arcade.Gold, self._gpShadows)
	end

	local wellFill = theme.Colors.Surface
	local headSlot = UIStyler.Frame("Head")
	headSlot.BackgroundColor3 = wellFill
	headSlot.AnchorPoint = Vector2.new(0, 0)
	headSlot.Position = UDim2.fromOffset(spacing.M, spacing.M)
	headSlot.Size = UDim2.fromOffset(GP_HEAD, GP_HEAD)
	headSlot.ClipsDescendants = true
	headSlot.ZIndex = 23
	headSlot.Parent = column
	GPLayoutKit.Petal(theme, headSlot, index + 1)
	GPLayoutKit.SoftStroke(theme, headSlot, if winner then theme.Arcade.Gold else wellFill)

	local fallback = IconArchive.Image(headSlot, "player", GP_HEAD - 54)
	fallback.AnchorPoint = Vector2.new(0.5, 0.5)
	fallback.Position = UDim2.fromScale(0.5, 0.5)
	fallback.ZIndex = 24

	local head = Instance.new("ImageLabel")
	head.Name = "Headshot"
	head.BackgroundTransparency = 1
	head.ScaleType = Enum.ScaleType.Fit
	head.AnchorPoint = Vector2.new(0.5, 0.5)
	head.Position = UDim2.fromScale(0.5, 0.5)
	head.Size = UDim2.fromScale(1, 1)
	head.Visible = false
	head.ZIndex = 25
	head.Parent = headSlot
	self:_LoadHeadshot(head, fallback, result.userId, gen)

	if winner then
		local crown = IconArchive.Image(column, "crown", 58, { golden = true })
		crown.AnchorPoint = Vector2.new(0.5, 0.5)
		crown.Position = UDim2.fromOffset(spacing.M + GP_HEAD - 12, spacing.M + 16)
		crown.ZIndex = 26
	end

	-- "you" always carries the suffix (doc §11.4).
	local name = GPLayoutKit.Text(theme, 28, theme.Colors.TextPrimary, "Name")
	name.Text = result.name .. (if result.isLocal then " (you)" else "")
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(spacing.M + GP_HEAD + spacing.M, spacing.M + 6)
	name.Size = UDim2.new(1, -(spacing.M * 3 + GP_HEAD), 0, 34)
	name.ZIndex = 24
	name.Parent = column

	local percent = GPLayoutKit.NumberText(theme, 58, accent, "Percent")
	percent.TextXAlignment = Enum.TextXAlignment.Left
	percent.Text = "0.0%"
	percent.Position = UDim2.fromOffset(spacing.M + GP_HEAD + spacing.M, spacing.M + 40)
	percent.Size = UDim2.new(1, -(spacing.M * 3 + GP_HEAD), 0, 66)
	percent.ZIndex = 24
	percent.Parent = column

	local breakdown = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Breakdown")
	breakdown.Text = string.format(
		PotteryDuelConfig.Copy.ShapeBreakdown,
		math.floor(result.shape or 0),
		math.floor(result.colour or 0)
	)
	breakdown.TextXAlignment = Enum.TextXAlignment.Left
	breakdown.Position = UDim2.fromOffset(spacing.M + GP_HEAD + spacing.M, spacing.M + 106)
	breakdown.Size = UDim2.new(1, -(spacing.M * 3 + GP_HEAD), 0, 24)
	breakdown.ZIndex = 24
	breakdown.Parent = column

	-- Star grade, on the engine's own exponential ladder.
	local starRow = UIStyler.Frame("Stars")
	starRow.BackgroundTransparency = 1
	starRow.Position = UDim2.fromOffset(spacing.M, spacing.M + GP_HEAD + 10)
	starRow.Size = UDim2.fromOffset(
		PotteryDuelConfig.MaxStars * GP_STAR + (PotteryDuelConfig.MaxStars - 1) * GP_STAR_GAP,
		GP_STAR
	)
	starRow.ZIndex = 24
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, GP_STAR_GAP),
	}).Parent = starRow
	starRow.Parent = column

	local starPips = {}
	for pipIndex = 1, PotteryDuelConfig.MaxStars do
		local pip = UIStyler.Frame("Star" .. pipIndex)
		pip.BackgroundColor3 = theme.Arcade.RulerTrack
		pip.Size = UDim2.fromOffset(GP_STAR, GP_STAR)
		pip.LayoutOrder = pipIndex
		pip.ZIndex = 24
		pip.Parent = starRow
		GPLayoutKit.Petal(theme, pip, pipIndex)

		local scale = Instance.new("UIScale")
		scale.Scale = 0.01
		scale.Parent = pip
		starPips[pipIndex] = { pip = pip, scale = scale }
	end

	local tierLabel = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, tier.color, "Tier")
	tierLabel.Text = string.format("%s \u{00B7} %d of %d stars", tier.name, stars, PotteryDuelConfig.MaxStars)
	tierLabel.TextXAlignment = Enum.TextXAlignment.Right
	tierLabel.AnchorPoint = Vector2.new(1, 0)
	tierLabel.Position = UDim2.new(1, -spacing.M, 0, spacing.M + GP_HEAD + 8)
	tierLabel.Size = UDim2.fromOffset(220, 22)
	tierLabel.ZIndex = 24
	tierLabel.Parent = column

	-- ---- the pot recipe comparison ----
	local wellFill2 = theme.Colors.Surface
	local well = UIStyler.Frame("PotWell")
	well.BackgroundColor3 = wellFill2
	well.Position = UDim2.fromOffset(spacing.M, spacing.M + GP_HEAD + 40)
	well.Size = UDim2.new(1, -spacing.M * 2, 0, GP_PROFILE_H)
	well.ClipsDescendants = true
	well.ZIndex = 23
	well.Parent = column
	GPLayoutKit.Petal(theme, well, index + 1)
	GPLayoutKit.SoftStroke(theme, well, wellFill2)

	local field = UIStyler.Frame("Field")
	field.BackgroundTransparency = 1
	field.Position = UDim2.fromOffset(spacing.S, spacing.S)
	field.Size = UDim2.new(1, -spacing.S * 2, 1, -spacing.S * 2)
	field.ZIndex = 23
	field.Parent = well

	local target = self._target
	local made = result.recipe or target
	local widest = 0.001
	for _, radius in target.radii do
		widest = math.max(widest, radius)
	end
	for _, radius in made.radii do
		widest = math.max(widest, radius)
	end
	local ghostBars = gpProfile(theme, field, GPLayoutKit.Deepen(theme, wellFill2, 1), 0.4, 24)
	local madeBars = gpProfile(theme, field, accent, 0.05, 25)
	layProfile(ghostBars, target.radii, widest)
	layProfile(madeBars, made.radii, widest)

	local caption = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "PotCaption")
	caption.Text = string.format(
		"%s behind \u{00B7} height %.2fx \u{00B7} hollow %.2f \u{00B7} coverage %d%%",
		PotteryDuelConfig.Copy.TargetHeading,
		made.heightScale,
		made.hollow,
		math.round((made.coverage or 1) * 100)
	)
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.TextTruncate = Enum.TextTruncate.AtEnd
	caption.AnchorPoint = Vector2.new(0, 1)
	caption.Position = UDim2.new(0, spacing.M, 1, -spacing.M)
	caption.Size = UDim2.new(1, -spacing.M * 2, 0, 20)
	caption.ZIndex = 24
	caption.Parent = column

	local entry = {
		root = column,
		percent = percent,
		stars = starPips,
		score = score,
		starCount = stars,
		tierColor = tier.color,
		delay = GP_COUNT_DELAY + (if result.isLocal then 0 else GP_COUNT_STAGGER),
	}
	table.insert(self._gpColumns, entry)
	return column
end

function DuelResultScreen:_RenderGPLayout()
	local theme = self:GetTheme()
	self._renderGen += 1
	local gen = self._renderGen

	for _, column in self._columns do
		column:Destroy()
	end
	table.clear(self._columns)
	table.clear(self._gpColumns)

	-- Local player LEFTMOST, then descending score (doc §11.4).
	local order = table.clone(self._results)
	table.sort(order, function(a, b)
		local ka = if a.isLocal then 0 else 1
		local kb = if b.isLocal then 0 else 1
		if ka ~= kb then
			return ka < kb
		end
		return (a.score or 0) > (b.score or 0)
	end)

	local best, bestCount = -math.huge, 0
	for _, result in order do
		local score = result.score or 0
		if score > best then
			best, bestCount = score, 1
		elseif score == best then
			bestCount += 1
		end
	end
	local tie = bestCount > 1

	-- ROUND END vs MATCH RESULT. Between rounds the world cinematic is the
	-- background, so the scrim lifts entirely and the match-level furniture —
	-- the tally, the commission line, the re-seat panel and the offer — all
	-- stand down. Only the round heading, who won it, and the two marks stay.
	local round = self._roundResult
	local isRound = type(round) == "table"
	self._scrim.BackgroundTransparency = if isRound then 1 else 0.4
	self._gpTallyCaption.Visible = not isRound
	self._tally.Visible = not isRound
	self._gpCommission.Visible = not isRound
	self._gpRoundLine.Visible = isRound
	self._gpBottomBar.Visible = not isRound

	if isRound then
		local total = math.max(1, math.floor(tonumber(round.totalRounds) or PotteryDuelConfig.Timing.Rounds))
		local number = math.clamp(math.floor(tonumber(round.roundNum) or 1), 1, total)
		local heading = string.format(PotteryDuelConfig.Copy.RoundResultHeading, number, total)
		-- Best-of-N clinches at floor(N/2)+1, the grader's own math. One win
		-- short of that and the NEXT round decides it — worth saying out loud.
		local clinch = math.floor(total / 2) + 1
		local leader = math.max(tonumber(self._roundWins[1]) or 0, tonumber(self._roundWins[2]) or 0)
		if clinch - leader == 1 then
			heading ..= string.format("  \u{00B7}  %s", PotteryDuelConfig.Copy.MatchPoint)
		end
		self._headlineLabel.Text = heading
		self._headlineLabel.TextColor3 = theme.Colors.TextPrimary

		-- A tie prints its own line rather than a nameless winner.
		local winnerName = if type(round.winner) == "string" then round.winner else nil
		if round.tie == true or not winnerName then
			self._gpRoundLine.Text = PotteryDuelConfig.Copy.RoundTied
			self._gpRoundLine.TextColor3 = theme.Colors.TextPrimary
		else
			self._gpRoundLine.Text = string.format(PotteryDuelConfig.Copy.RoundWinner, winnerName)
			self._gpRoundLine.TextColor3 = theme.Arcade.Gold
		end
	else
		if self._headline then
			self._headlineLabel.Text = self._headline
		else
			self._headlineLabel.Text = if tie
				then PotteryDuelConfig.Copy.Tie
				elseif self._won then PotteryDuelConfig.Copy.Win
				else PotteryDuelConfig.Copy.Lose
		end
		-- Gold marks the winner everywhere; a defeat is the pack's soft coral,
		-- and a tie stays the warm ink.
		self._headlineLabel.TextColor3 = if tie
			then theme.Colors.TextPrimary
			elseif self._won then theme.Arcade.Gold
			else theme.Colors.Error

		self._tally.Text = string.format("%d   -   %d", self._roundWins[1] or 0, self._roundWins[2] or 0)
		self._gpCommission.Text = string.format(
			"Both pots were measured against \u{201C}%s\u{201D} \u{00B7} %s \u{00B7} difficulty %d",
			self._target.title,
			self._target.family,
			self._target.difficulty
		)
	end

	local count = #order
	for index, result in order do
		local winner = not tie and (result.score or 0) == best
		self:_BuildGPColumn(result, index, count, winner, gen)
	end

	self:_GPRefreshReseat()
	self:_GPRefreshOffer()

	self._elapsed = 0
	self:_ApplyGPCountUp(0)
	UIChrome.PopIn(theme, self._content)
	-- Between rounds the sting follows the ROUND, not the match: taking a round
	-- you are still losing overall must not play the defeat cue.
	local wonThis = self._won
	if isRound then
		local mine: PlayerResult? = nil
		for _, result in order do
			if result.isLocal then
				mine = result
			end
		end
		wonThis = round.tie ~= true and mine ~= nil and mine.name == round.winner
	end
	self:_PlaySound(if wonThis and not tie then "Success" else "Error")
	self:_StartGPTicker()
end

-- The count-up + star punch, rendered as a pure function of elapsed time so
-- the whole reveal is restartable and never half-finished.
function DuelResultScreen:_ApplyGPCountUp(t: number)
	local theme = self:GetTheme()
	local peak = theme.Motion.PulseScale or 1.12
	for _, entry in self._gpColumns do
		local progress = math.clamp((t - entry.delay) / GP_COUNT_SECONDS, 0, 1)
		local eased = 1 - (1 - progress) * (1 - progress)
		entry.percent.Text = string.format("%.1f%%", entry.score * eased)

		local starsAt = entry.delay + GP_COUNT_SECONDS
		for pipIndex, star in entry.stars do
			local at = starsAt + (pipIndex - 1) * GP_STAR_STEP
			if pipIndex > entry.starCount or t < at then
				star.pip.BackgroundColor3 = theme.Arcade.RulerTrack
				star.scale.Scale = 0.01
			else
				local punch = math.clamp((t - at) / 0.2, 0, 1)
				-- Overshoot solved from the pack's own capped PulseScale.
				local c1 = 1.70158 * math.max(0, peak - 1) / 0.0999
				local x = punch - 1
				star.pip.BackgroundColor3 = entry.tierColor
				star.scale.Scale = math.max(1 + (c1 + 1) * x * x * x + c1 * x * x, 0.01)
			end
		end
	end
end

function DuelResultScreen:_GPRefreshReseat()
	if not self._gpReseatLabel then
		return
	end
	if self._left then
		self._gpReseatLabel.Text = PotteryDuelConfig.Copy.Leaving
		self._gpLeaveButton.Visible = false
		return
	end
	self._gpLeaveButton.Visible = true
	-- The live window is TWO deadlines back to back, and one shared number
	-- read as a timer glitching and restarting. So the results hold says only
	-- that the match is wrapping up; the intermission owns the real countdown.
	if self._finalizing then
		self._gpReseatLabel.Text = PotteryDuelConfig.Copy.Finalizing
	else
		self._gpReseatLabel.Text = string.format(PotteryDuelConfig.Copy.ReseatFormat, math.ceil(math.max(0, self._reseat)))
	end
end

function DuelResultScreen:_GPRefreshOffer()
	if not self._gpOfferCard then
		return
	end
	-- The offer belongs to the MATCH's tail, never to a round break: a stale
	-- payload must not float it over the between-rounds cinematic.
	local offer = if self._roundResult then nil else self._offer
	self._gpOfferCard.Visible = offer ~= nil
	if not offer then
		return
	end
	-- LOCKED: the purchase was confirmed at the dialog and the receipt is in
	-- flight. Both answers fade out rather than disappear — an interactive NO
	-- in that gap would cancel a purchase the player just made.
	if self._offerLocked then
		self._gpOfferTimer.Text = PotteryDuelConfig.Copy.SecondChanceLocked
		self._gpOfferYesLabel.TextTransparency = 0.5
		self._gpOfferNoLabel.TextTransparency = 0.5
		return
	end
	self._gpOfferYesLabel.TextTransparency = 0
	self._gpOfferNoLabel.TextTransparency = 0
	self._gpOfferTimer.Text = string.format(PotteryDuelConfig.Copy.SecondChanceTimer, math.max(0, self._offerLeft))
end

function DuelResultScreen:_GPLeave()
	if self._left then
		return
	end
	self._left = true
	self:_PlaySound("Click")
	self:_GPRefreshReseat()
end

-- YES mirrors the live client: it hands off to the purchase prompt and FREEZES
-- the card, because the receipt can lag the dialog by seconds and an
-- interactive NO in that gap would cancel a purchase the player just made.
function DuelResultScreen:_GPOfferAnswer(accept: boolean)
	if self._offerLocked then
		return
	end
	if accept then
		self._offerLocked = true
		self._offerLeft = math.max(self._offerLeft, PotteryDuelConfig.Timing.SecondChanceGraceSeconds)
	else
		self._offer = nil
	end
	self:_PlaySound("Click")
	self:_GPRefreshOffer()
end

-- ONE handler drives the count-up, the re-seat countdown and the offer clock.
function DuelResultScreen:_StartGPTicker()
	self:_StopGPTicker()
	self._stopTicker = UITicker.Register(function(dt: number)
		if not self:IsVisible() or not self._content or not self._content.Parent then
			return
		end
		self._elapsed += dt
		self:_ApplyGPCountUp(self._elapsed)

		if not self._finalizing and self._reseat > 0 then
			self._reseat = math.max(0, self._reseat - dt)
		end
		self:_GPRefreshReseat()

		if self._offer and not self._offerLocked then
			self._offerLeft = math.max(0, self._offerLeft - dt)
			if self._offerLeft <= 0 then
				-- The server owns the real window; the card just stops asking.
				self._offer = nil
			end
			self:_GPRefreshOffer()
		end
	end, self.Root)
end

function DuelResultScreen:_StopGPTicker()
	if self._stopTicker then
		self._stopTicker()
		self._stopTicker = nil
	end
end

-- ========================================================================
-- AC layout (theme.LayoutKit == "AC")
-- ========================================================================

-- The AC results readout: same cinematic scrim, then a bracketed terminal
-- panel — mono verdict between hairline rules, dense name/score rows with
-- hard-square win pips, and a hairline CONTINUE action.
function DuelResultScreen:_BuildACLayout()
	local theme = self:GetTheme()

	-- Scrim at the classic 0.4 (doc §11.8) — results still dim the world.
	local scrim = UIStyler.Frame("Scrim")
	scrim.BackgroundColor3 = theme.Colors.Overlay
	scrim.BackgroundTransparency = 0.4
	scrim.ZIndex = 20
	scrim.Parent = self.Root
	self._scrim = scrim

	local content = UIStyler.Frame("Content")
	content.BackgroundTransparency = 1
	content.ZIndex = 21
	content.Parent = scrim
	self._content = content

	local panel = UIStyler.Frame("Readout")
	panel.BackgroundTransparency = 1
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.46)
	panel.Size = UDim2.fromOffset(AC_PANEL_W, AC_PANEL_H)
	panel.ZIndex = 22
	panel.Parent = content
	ACLayoutKit.Brackets(theme, panel)

	local ruleTop = ACLayoutKit.Rule(theme, panel, 0.5)
	ruleTop.Position = UDim2.fromOffset(0, 0)
	ruleTop.ZIndex = 22

	-- Verdict — text and colour mapping are applied per render (accent win /
	-- error loss / plain tie, exactly the classic mapping).
	local headline = UIChrome.Text("Headline", 18, theme.Colors.TextPrimary)
	headline.RichText = false
	headline.Text = ""
	headline.Position = UDim2.fromOffset(0, 10)
	headline.Size = UDim2.new(1, 0, 0, 24)
	headline.ZIndex = 22
	headline.Parent = panel
	self._headlineLabel = headline

	local tally = UIChrome.BodyText("Tally", 12, theme.Colors.TextSecondary)
	tally.RichText = false
	tally.Text = ""
	tally.FontFace = theme.Fonts.Numeric
	tally.Position = UDim2.fromOffset(0, 36)
	tally.Size = UDim2.new(1, 0, 0, 16)
	tally.ZIndex = 22
	tally.Parent = panel
	self._tally = tally

	local ruleMid = ACLayoutKit.Rule(theme, panel, 0.5)
	ruleMid.Position = UDim2.fromOffset(0, 60)
	ruleMid.ZIndex = 22

	-- Result rows land here per render.
	local rows = UIStyler.Frame("Rows")
	rows.BackgroundTransparency = 1
	rows.Position = UDim2.fromOffset(0, 70)
	rows.Size = UDim2.new(1, 0, 0, 150)
	rows.ZIndex = 22
	UIStyler.ListLayout({ Padding = UDim.new(0, 2) }).Parent = rows
	rows.Parent = panel
	self._acRows = rows

	local continueButton = ACLayoutKit.ActionButton(theme, panel, "CONTINUE", function()
		self.ScreenController:HideScreen("duelResult")
	end)
	continueButton.AnchorPoint = Vector2.new(0.5, 1)
	continueButton.Position = UDim2.new(0.5, 0, 1, -14)
	continueButton.ZIndex = 23

	-- Destroy() is the only surface the lifecycle needs from _continue.
	self._continue = {
		Root = continueButton,
		Destroy = function()
			continueButton:Destroy()
		end,
	} :: any
end

-- One dense result row: hard-square pip (accent filled = won, hairline
-- empty = lost — the screen carries no per-round tally, so the pip marks
-- the match outcome per row), mono name and percent.
function DuelResultScreen:_BuildACRow(result: PlayerResult, index: number, winner: boolean): Frame
	local theme = self:GetTheme()
	local ink = if winner then theme.Colors.Accent else theme.Colors.TextPrimary

	local row = UIStyler.Frame("Result" .. index)
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 26)
	row.LayoutOrder = index
	row.ZIndex = 23
	row.Parent = self._acRows
	table.insert(self._columns, row)

	local pip = UIStyler.Frame("Pip")
	pip.AnchorPoint = Vector2.new(0, 0.5)
	pip.Position = UDim2.new(0, 4, 0.5, 0)
	pip.Size = UDim2.fromOffset(10, 10)
	pip.ZIndex = 23
	if winner then
		pip.BackgroundColor3 = theme.Colors.Accent
	else
		pip.BackgroundTransparency = 1
		UIStyler.Stroke(theme.Colors.Accent, 1, 0.4).Parent = pip
	end
	pip.Parent = row

	-- "you" always carries the suffix (doc §11.4), uppercased with the row.
	local name = UIChrome.BodyText("Name", 12, ink)
	name.RichText = false
	name.Text = string.upper(result.name .. (if result.isLocal then " (you)" else ""))
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(24, 0)
	name.Size = UDim2.new(1, -110, 1, 0)
	name.ZIndex = 23
	name.Parent = row

	local score = UIChrome.BodyText("Score", 12, ink)
	score.RichText = false
	score.Text = string.format("%d%%", math.floor(result.score or 0))
	score.FontFace = theme.Fonts.Numeric
	score.TextXAlignment = Enum.TextXAlignment.Right
	score.AnchorPoint = Vector2.new(1, 0)
	score.Position = UDim2.new(1, -4, 0, 0)
	score.Size = UDim2.fromOffset(80, 26)
	score.ZIndex = 23
	score.Parent = row

	local underline = ACLayoutKit.Rule(theme, row, 0.85)
	underline.AnchorPoint = Vector2.new(0, 1)
	underline.Position = UDim2.new(0, 0, 1, 0)

	return row
end

-- The AC render: verdict + dense rows. Same ordering, tie/winner math,
-- sound and pop flow as the classic render (doc §11.4).
function DuelResultScreen:_RenderACLayout()
	local theme = self:GetTheme()
	self._renderGen += 1

	for _, column in self._columns do
		column:Destroy()
	end
	table.clear(self._columns)

	-- Local player LEFTMOST becomes local player TOPMOST, then descending
	-- score — the same comparator as classic.
	local order = table.clone(self._results)
	table.sort(order, function(a, b)
		local ka = if a.isLocal then 0 else 1
		local kb = if b.isLocal then 0 else 1
		if ka ~= kb then
			return ka < kb
		end
		return (a.score or 0) > (b.score or 0)
	end)

	local best, bestCount = -math.huge, 0
	for _, result in order do
		local score = result.score or 0
		if score > best then
			best, bestCount = score, 1
		elseif score == best then
			bestCount += 1
		end
	end
	local tie = bestCount > 1

	if self._headline then
		self._headlineLabel.Text = self._headline
	else
		self._headlineLabel.Text = if tie then "IT'S A TIE!" elseif self._won then "YOU WIN" else "DEFEAT"
	end
	self._headlineLabel.TextColor3 = if tie
		then theme.Colors.TextPrimary
		elseif self._won then theme.Colors.Accent
		else theme.Colors.Error

	local scores = {}
	for _, result in order do
		table.insert(scores, string.format("%d", math.floor(result.score or 0)))
	end
	self._tally.Text = table.concat(scores, "   -   ")

	for index, result in order do
		local winner = not tie and (result.score or 0) == best
		self:_BuildACRow(result, index, winner)
	end

	UIChrome.PopIn(theme, self._content)
	self:_PlaySound(if self._won and not tie then "Success" else "Error")
end

-- ========================================================================
-- Result columns
-- ========================================================================

function DuelResultScreen:_LoadHeadshot(image: ImageLabel, fallback: GuiObject, userId: number?, gen: number)
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

function DuelResultScreen:_BuildColumn(result: PlayerResult, index: number, count: number, winner: boolean, gen: number): Frame
	local theme = self:GetTheme()
	local accent = if winner then theme.Arcade.Gold else theme.Colors.TextPrimary

	local column = UIStyler.Frame("Result" .. index)
	column.BackgroundTransparency = 1
	column.AnchorPoint = Vector2.new(0.5, 0.5)
	column.Position = UDim2.new(0.5, (index - (count + 1) / 2) * COL_PITCH, COLUMNS_Y, 0)
	column.Size = UDim2.fromOffset(COL_W, COL_H)
	column.ZIndex = 22
	column.Parent = self._content
	table.insert(self._columns, column)

	-- Gold glow pad behind the winner (the source's buildProfileVP treatment).
	if winner then
		local glow = UIStyler.Frame("Glow")
		glow.BackgroundColor3 = theme.Arcade.Gold
		glow.BackgroundTransparency = 0.45
		glow.AnchorPoint = Vector2.new(0.5, 0)
		glow.Position = UDim2.new(0.5, 0, 0, 12)
		glow.Size = UDim2.fromOffset(HEAD + 76, HEAD + 40)
		glow.ZIndex = 22
		UIChrome.Corner("Arcade", "Wheel").Parent = glow
		glow.Parent = column
	end

	local headSlot = UIStyler.Frame("Head")
	headSlot.BackgroundColor3 = theme.Arcade.NearBlack
	headSlot.AnchorPoint = Vector2.new(0.5, 0)
	headSlot.Position = UDim2.new(0.5, 0, 0, 32)
	headSlot.Size = UDim2.fromOffset(HEAD, HEAD)
	headSlot.ClipsDescendants = true
	headSlot.ZIndex = 23
	UIChrome.Corner("Arcade", "Pill").Parent = headSlot
	-- Gold ring on the winner, plain black policy stroke on everyone else.
	if winner then
		UIStyler.Stroke(theme.Arcade.Gold, 4, 0).Parent = headSlot
	else
		UIChrome.Stroke(theme, "Arcade").Parent = headSlot
	end
	headSlot.Parent = column

	local fallback = IconArchive.Image(headSlot, "player", HEAD - 64)
	fallback.AnchorPoint = Vector2.new(0.5, 0.5)
	fallback.Position = UDim2.fromScale(0.5, 0.5)
	fallback.ZIndex = 24

	local head = Instance.new("ImageLabel")
	head.Name = "Headshot"
	head.BackgroundTransparency = 1
	head.ScaleType = Enum.ScaleType.Fit
	head.AnchorPoint = Vector2.new(0.5, 0.5)
	head.Position = UDim2.fromScale(0.5, 0.5)
	head.Size = UDim2.fromScale(1, 1)
	head.Visible = false
	head.ZIndex = 25
	head.Parent = headSlot
	self:_LoadHeadshot(head, fallback, result.userId, gen)

	if winner then
		local crown = IconArchive.Image(column, "crown", 64, { golden = true })
		crown.AnchorPoint = Vector2.new(0.5, 0.5)
		crown.Position = UDim2.new(0.5, 0, 0, 26)
		crown.ZIndex = 26
	end

	-- "you" always carries the suffix (doc §11.4).
	local name = UIChrome.Text("Name", 30, accent)
	name.Text = result.name .. (if result.isLocal then " (you)" else "")
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.AnchorPoint = Vector2.new(0.5, 0)
	name.Position = UDim2.new(0.5, 0, 0, HEAD + 52)
	name.Size = UDim2.fromOffset(COL_W - 20, 38)
	name.ZIndex = 24
	name.Parent = column

	-- Result percent, FredokaOne 70 (doc §2), gold on the winner.
	local percent = UIChrome.Text("Percent", 70, accent)
	percent.Text = string.format("%d%%", math.floor(result.score or 0))
	percent.AnchorPoint = Vector2.new(0.5, 0)
	percent.Position = UDim2.new(0.5, 0, 0, HEAD + 96)
	percent.Size = UDim2.fromOffset(COL_W - 20, 84)
	percent.ZIndex = 24
	percent.Parent = column

	return column
end

-- ========================================================================
-- Render
-- ========================================================================

function DuelResultScreen:_Render()
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

	for _, column in self._columns do
		column:Destroy()
	end
	table.clear(self._columns)

	-- Local player LEFTMOST, then descending score (doc §11.4).
	local order = table.clone(self._results)
	table.sort(order, function(a, b)
		local ka = if a.isLocal then 0 else 1
		local kb = if b.isLocal then 0 else 1
		if ka ~= kb then
			return ka < kb
		end
		return (a.score or 0) > (b.score or 0)
	end)

	-- The winner is the single highest score; a shared top score is a tie and
	-- nothing gets the gold treatment.
	local best, bestCount = -math.huge, 0
	for _, result in order do
		local score = result.score or 0
		if score > best then
			best, bestCount = score, 1
		elseif score == best then
			bestCount += 1
		end
	end
	local tie = bestCount > 1

	if self._headline then
		self._headlineLabel.Text = self._headline
	else
		self._headlineLabel.Text = if tie then "IT'S A TIE!" elseif self._won then "YOU WIN" else "DEFEAT"
	end
	self._headlineLabel.TextColor3 = if tie
		then theme.Colors.TextPrimary
		elseif self._won then theme.Arcade.Gold
		else theme.Arcade.Red

	local scores = {}
	for _, result in order do
		table.insert(scores, string.format("%d", math.floor(result.score or 0)))
	end
	self._tally.Text = table.concat(scores, "   -   ")

	local count = #order
	for index, result in order do
		local winner = not tie and (result.score or 0) == best
		self:_BuildColumn(result, index, count, winner, gen)
	end

	-- Open is an instant flip (base); the pop lives on the CONTENT (doc §7.4).
	UIChrome.PopIn(theme, self._content)
	self:_PlaySound(if self._won and not tie then "Success" else "Error")
end

-- ========================================================================
-- Lifecycle
-- ========================================================================

function DuelResultScreen:_OnShow(data: any?)
	if type(data) == "table" then
		if type(data.won) == "boolean" then
			self._won = data.won
		end
		-- Reset first: a payload without a headline must fall back to the
		-- derived one, not inherit the previous match's override.
		self._headline = if type(data.headline) == "string" then data.headline else nil
		if type(data.results) == "table" and #data.results > 0 then
			self._results = data.results
		end
		-- GP-only match context; the classic/AC branches have nowhere to put it.
		if type(data.roundWins) == "table" then
			self._roundWins = data.roundWins
		end
		-- Reset first: a match-result payload must never inherit the previous
		-- round break's readout and keep the scrim lifted.
		self._roundResult = if type(data.roundResult) == "table" then data.roundResult else nil
		if type(data.target) == "table" then
			self._target = data.target
		end
		if type(data.finalizing) == "boolean" then
			self._finalizing = data.finalizing
		end
		if type(data.reseatSeconds) == "number" then
			self._reseat = math.max(0, data.reseatSeconds)
		end
		-- A fresh results window always RE-ARMS the leave state: a previous
		-- match's press must never carry over and hide this one's countdown.
		self._left = false
		self._offerLocked = false
		self._offer = if type(data.secondChance) == "table" then data.secondChance else nil
		self._offerLeft = if self._offer
			then math.max(0, tonumber(self._offer.seconds) or PotteryDuelConfig.Timing.SecondChanceSeconds)
			else 0
	end
	self:_Render()
end

function DuelResultScreen:_OnHide()
	-- Orphans any in-flight headshot fetch and releases the reveal ticker.
	self._renderGen += 1
	self:_StopGPTicker()
end

function DuelResultScreen:Update(data: any)
	if self._built and self:IsVisible() then
		self:_OnShow(data)
	end
end

-- A style rebuild destroys the Gui, but a UIShadow's BUDGET count only falls
-- when its handle is released — hand every GP shadow back here.
function DuelResultScreen:_OnTeardown()
	self:_StopGPTicker()
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	table.clear(self._columns)
	table.clear(self._gpColumns)
	self._gpReseatPanel = nil
	self._gpReseatLabel = nil
	self._gpLeaveButton = nil
	self._gpLeaveLabel = nil
	self._gpOfferCard = nil
	self._gpOfferTimer = nil
	self._gpOfferYes = nil
	self._gpOfferYesLabel = nil
	self._gpOfferNo = nil
	self._gpOfferNoLabel = nil
	self._gpCommission = nil
	self._gpTallyCaption = nil
	self._gpRoundLine = nil
	self._gpBottomBar = nil
end

function DuelResultScreen:Destroy()
	self:_OnHide()
	self:_OnTeardown()
	if self._continue then
		self._continue:Destroy()
		self._continue = nil
	end
	UIScreenBase.Destroy(self)
end

return DuelResultScreen
