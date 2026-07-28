--!strict
-- EVENT BANNER — the server-event presentation layer, ported from Pottery
-- Battles' EventController onto the collection's chrome. This is the ambient
-- half of the Potter's Cup: the thing that tells you a competition is coming,
-- lets you enter from where you already are, and then keeps score.
--
-- WHAT IT CARRIES (all of it real, all of it from the source):
--   * THE BAND — a full-width strip with an eyebrow, the event name and a
--     LIVE countdown line, plus its own ENTER button. Entries open WITH the
--     one-minute warning, so the button is live the moment the band appears:
--     a countdown you cannot act on is just a nag.
--   * THE PHASE HUD — a clock plate reading the phase ("Round 2 — Shape!",
--     "Final — Results") over a big countdown that turns Error-red and pulses
--     through the last ten seconds of a shaping round.
--   * THE STANDINGS BOARD — every competitor, their score, and THE CUT LINE
--     drawn where the bottom half dies, computed from the SAME survivorsFor
--     the server cuts with, so the line a player sees can never disagree with
--     who actually goes home.
--   * THE TITLE CARD — "Round 2 of 3", "The final" (with the tiebreak seconds),
--     "Eliminated" + who went home, "<name> wins!". The ceremony card's
--     subtitle is PERSONAL FIRST: a player who competed reads their own
--     placement and payout ("You placed 2 — +500 Bux, +$250"), and only a
--     spectator falls back to the champion line. The winner card is showered
--     with the source's confetti (48 squares, 9–17px, 1.9–3.2s linear).
--   * THE ENTRY DETAILS PANEL — the reward ladder (1st/2nd/3rd/everyone on
--     stage). Retired as a second entry UI in the source, kept built there and
--     kept built here; `showEntryDetails` in the payload is what opens it.
--   * THE SPECTATE BAR — "Spectating" / "Eliminated — spectating" + leave.
--
-- TWO CLOCKS, DELIBERATELY. `phaseEndsAt` is stamped with the server clock
-- (Workspace:GetServerTimeNow()) while `nextEventAt` is stamped with os.time()
-- — the announce cadence keys off os.time() % period so every server announces
-- together. Both are epoch-based and they are NOT the same clock, so each
-- deadline is compared against the clock that produced it. Getting this wrong
-- is a countdown that drifts by the server's uptime.
--
-- THE COUNTDOWN IS RENDERED EVERY FRAME FROM STORED DEADLINES, never written
-- when state arrives: event state only broadcasts on CHANGE, and during the
-- warning nothing changes for seconds at a time, so text written in the state
-- handler simply freezes on screen. One UITicker handler does the drawing —
-- this framework has exactly one Heartbeat and screens do not open their own.
--
-- OWNS NO STATE. Every frame of it is derived from the payload, so a player
-- who arrives mid-event sees the correct picture on the very next Update.
--
-- LAYOUT LANGUAGES: geometry is shared; the SKIN branches. Under GP
-- (theme.LayoutKit == "GP") the band is a rose ribbon with a scalloped lip and
-- a glaze sheen, plates are petal-cornered with hue-matched shadows, and copy
-- stays sentence case — this pack never shouts. Every other pack gets the
-- house arcade chrome through UIChrome. One builder, two paints.

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local UITicker = require(script.Parent.Parent.Framework.UITicker)
local UIScreenBase = require(script.Parent.UIScreenBase)

export type EventPlayer = {
	name: string,
	score: number,
	alive: boolean?,
	eliminatedRound: number?,
}

export type EventRewards = {
	placementBux: { number }?,
	participationBux: number?,
	firstChairRarity: string?,
}

-- What THIS player walked away with. The source's ceremony card prints the
-- player's own placement and payout when they competed, and only falls back to
-- "<champion> takes the cup" for everyone else — a spectator's card and a
-- finalist's card are not the same card.
export type EventResult = {
	place: number?,
	bux: number?,
	cash: number?,
	chair: boolean?,
	chairRarity: string?,
}

export type EventData = {
	eventName: string?,
	blurb: string?,
	phase: string?,
	roundNum: number?,
	roundCount: number?,
	isFinal: boolean?,
	-- How long the final's single tiebreak pot gets. The source prints it on the
	-- final's title card ("%d seconds. One pot. Winner takes it.").
	tiebreakSeconds: number?,
	-- server clock (Workspace:GetServerTimeNow)
	phaseEndsAt: number?,
	-- os.time clock
	nextEventAt: number?,
	queueOpen: boolean?,
	queueCount: number?,
	slots: number?,
	entered: boolean?,
	alive: boolean?,
	spectating: boolean?,
	inMatch: boolean?,
	showEntryDetails: boolean?,
	players: { EventPlayer }?,
	rewards: EventRewards?,
	myResult: EventResult?,
	survivorsFor: ((aliveCount: number) -> number)?,
	onEnter: (() -> ())?,
	onLeaveSpectate: (() -> ())?,
}

-- Phase → what that clock MEANS. Sentence case: the source shouts these, and
-- under the GP pack shouting is the named failure mode. Meaning is unchanged.
local PHASE_LABEL: { [string]: string } = {
	warn = "Starting soon",
	queue = "Entries open",
	gather = "Take your places",
	intro = "Get ready",
	walk = "To your wheel",
	shape = "Shape!",
	grading = "Time",
	reveal = "Scores",
	cut = "Elimination",
	ceremony = "Results",
	teardown = "",
}

-- Layout px at the 1650×1020 authoring baseline.
local BANNER_H = 104
local BANNER_Y = 0.11
local BTN_ZONE = 340 -- right strip reserved for ENTER; text centres in the rest
local CLOCK_W, CLOCK_H = 330, 128
local BOARD_W, BOARD_H = 360, 500
local BOARD_ROW_H = 38
local DETAILS_W, DETAILS_H = 440, 320
local SPECT_W, SPECT_H = 380, 96
local PANIC_SECONDS = 10

-- The source's ceremony confetti, beat for beat (EventController.burstConfetti):
-- 48 squares on the winner card, 9–17px, 1.9–3.2s LINEAR from above the top
-- edge to below the bottom, ±90px horizontal drift, ±540° spin. Repainted from
-- the pack's own rotation so the pastel page never gets a primary-colour shower.
local CONFETTI_COUNT = 48
local CONFETTI_MIN, CONFETTI_MAX = 9, 17
local CONFETTI_DRIFT = 90
local CONFETTI_SPIN = 540
local CONFETTI_MIN_TIME, CONFETTI_MAX_TIME = 1.9, 3.2

-- The house cut rule, used only when the caller does not hand in the server's
-- own survivorsFor: the bottom half goes home, and at least one survives.
local function houseSurvivors(aliveCount: number): number
	return math.max(1, math.ceil(aliveCount / 2))
end

-- Demo state, so the screen is fully exercisable with no backend attached.
local DEMO_PLAYERS: { EventPlayer } = {
	{ name = "clayfingers", score = 94, alive = true },
	{ name = "GlazeGoblin", score = 88, alive = true },
	{ name = "wobblyrim", score = 81, alive = true },
	{ name = "Kiln_Kitty", score = 77, alive = true },
	{ name = "throwsalot", score = 61, alive = true },
	{ name = "MugLord", score = 54, alive = true },
	{ name = "saggarsam", score = 40, alive = false, eliminatedRound = 1 },
	{ name = "bisquebee", score = 33, alive = false, eliminatedRound = 1 },
}

local DEMO_REWARDS: EventRewards = {
	placementBux = { 1000, 500, 250 },
	participationBux = 50,
	firstChairRarity = "Legendary",
}

local EventBannerScreen = setmetatable({}, { __index = UIScreenBase })
EventBannerScreen.__index = EventBannerScreen

function EventBannerScreen.new()
	local self = UIScreenBase.new("EventBannerScreen", 6)
	self._gp = false

	self._eventName = "The Potter's Cup"
	self._blurb = "Three rounds. One wheel each. The best pot takes it."
	self._phase = "idle"
	self._roundNum = 0
	self._roundCount = 3
	self._isFinal = false
	self._tiebreakSeconds = 45
	self._phaseEndsAt = 0
	self._nextEventAt = 0
	self._queueOpen = false
	self._queueCount = 0
	self._slots = 12
	self._entered = false
	self._alive = true
	self._spectating = false
	self._inMatch = false
	self._showEntryDetails = false
	self._players = DEMO_PLAYERS :: { EventPlayer }
	self._rewards = DEMO_REWARDS :: EventRewards
	self._myResult = nil :: EventResult?
	self._survivorsFor = houseSurvivors :: (aliveCount: number) -> number
	self._onEnter = nil :: (() -> ())?
	self._onLeaveSpectate = nil :: (() -> ())?

	-- What the band is counting down to. "none" | "next" (the idle cadence,
	-- os.time) | "entry" (warn/queue, server clock).
	self._bannerKind = "none"
	self._bannerAt = 0

	self._lastPhase = ""
	self._lastRound = -1
	self._titleUntil = 0
	self._rows = {} :: { any }
	self._rowPool = {} :: { any }
	self._shadows = {} :: { any }
	self._confetti = {} :: { GuiObject }
	self._confettiTweens = {} :: { Tween }
	self._seeded = false
	return setmetatable(self, EventBannerScreen)
end

-- ========================================================================
-- Skin seams: one geometry, two paints. Every builder below asks these for a
-- surface instead of picking chrome itself.
-- ========================================================================

function EventBannerScreen:_Plate(parent: Instance, name: string, index: number?, fill: Color3?): Frame
	local theme = self:GetTheme()
	if self._gp then
		local surface = fill or theme.Colors.SurfaceRaised
		local plate = UIStyler.Frame(name)
		plate.BackgroundColor3 = surface
		plate.BackgroundTransparency = 0
		plate.Parent = parent
		GPLayoutKit.Petal(theme, plate, index or 0)
		GPLayoutKit.SoftStroke(theme, plate)
		GPLayoutKit.Shadow(theme, plate, "md", self._shadows, surface)
		return plate
	end
	local plate = UIChrome.Panel(theme, "Arcade", name)
	if fill then
		plate.BackgroundColor3 = fill
	end
	plate.Parent = parent
	return plate
end

function EventBannerScreen:_Display(parent: Instance, text: string, size: number, color: Color3?): TextLabel
	local theme = self:GetTheme()
	local label = if self._gp
		then GPLayoutKit.Text(theme, size, color or theme.Colors.TextPrimary, "Display")
		else UIChrome.Text("Display", size, color or theme.Colors.TextPrimary)
	label.Text = text
	label.Parent = parent
	return label
end

function EventBannerScreen:_Body(parent: Instance, text: string, size: number, color: Color3?): TextLabel
	local theme = self:GetTheme()
	local label = if self._gp
		then GPLayoutKit.BodyText(theme, size, color or theme.Colors.TextSecondary, "Body")
		else UIChrome.BodyText("Body", size, color or theme.Colors.TextSecondary)
	label.Text = text
	label.Parent = parent
	return label
end

function EventBannerScreen:_Numeric(parent: Instance, size: number, color: Color3?): TextLabel
	local theme = self:GetTheme()
	if self._gp then
		local label = GPLayoutKit.NumberText(theme, size, color or theme.Colors.TextPrimary, "Number")
		label.Parent = parent
		return label
	end
	local label = UIChrome.Text("Number", size, color or theme.Colors.TextPrimary)
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.Parent = parent
	return label
end

function EventBannerScreen:_Fill(parent: Instance, name: string, color: Color3, transparency: number?): Frame
	-- UIStyler.Frame is born PURE WHITE; nothing here may leave it unpainted.
	local frame = UIStyler.Frame(name)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency or 0
	frame.Parent = parent
	return frame
end

type ActionButton = {
	root: TextButton,
	chip: Frame,
	label: TextLabel,
	SetText: (string) -> (),
	SetFill: (Color3) -> (),
	SetActive: (boolean) -> (),
}

-- The button itself stays TRANSPARENT and the fill lives on a chip child: the
-- style enforcer backstops any SOLID GuiButton with a black 2px stroke, which
-- the GP pack forbids on sight. A transparent button never trips it, and the
-- construction is identical under every pack.
function EventBannerScreen:_Button(parent: Instance, opts: {
	name: string,
	text: string,
	fill: Color3,
	size: UDim2,
	position: UDim2?,
	anchorPoint: Vector2?,
	index: number?,
	textSize: number?,
	zIndex: number?,
	onClick: (() -> ())?,
}): ActionButton
	local theme = self:GetTheme()
	local zIndex = opts.zIndex or 6

	local root = Instance.new("TextButton")
	root.Name = opts.name
	root.BackgroundTransparency = 1
	root.Text = ""
	root.AutoButtonColor = false
	root.Size = opts.size
	root.Position = opts.position or UDim2.fromScale(0, 0)
	root.AnchorPoint = opts.anchorPoint or Vector2.new(0, 0)
	root.ZIndex = zIndex
	root.Parent = parent

	local chip = self:_Fill(root, "Chip", opts.fill)
	chip.Size = UDim2.fromScale(1, 1)
	chip.ZIndex = zIndex

	local stroke: UIStroke
	local shadow: any = nil
	if self._gp then
		GPLayoutKit.Petal(theme, chip, opts.index or 0)
		stroke = GPLayoutKit.SoftStroke(theme, chip)
		shadow = GPLayoutKit.Shadow(theme, chip, "sm", self._shadows, opts.fill)
	else
		UIChrome.Corner("Arcade", "Button").Parent = chip
		stroke = UIChrome.Stroke(theme, "Arcade", "Button")
		stroke.Parent = chip
		UIChrome.GlassGradient().Parent = chip
	end

	local label = self:_Display(chip, opts.text, opts.textSize or theme.TextSizes.Button, theme.Colors.TextPrimary)
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = zIndex + 1

	if opts.onClick then
		root.Activated:Connect(function()
			if root.Active then
				opts.onClick()
			end
		end)
	end
	UIChrome.Animate(theme, root, chip)

	return {
		root = root,
		chip = chip,
		label = label,
		SetText = function(text: string)
			label.Text = text
		end,
		SetFill = function(color: Color3)
			chip.BackgroundColor3 = color
			if self._gp then
				local deep = GPLayoutKit.Deepen(theme, color, 1)
				stroke.Color = deep
				if shadow then
					shadow.Instance.Color = deep
				end
			end
		end,
		SetActive = function(active: boolean)
			root.Active = active
			label.TextColor3 = if active then theme.Colors.TextPrimary else theme.Colors.TextSecondary
		end,
	}
end

-- ========================================================================
-- Build
-- ========================================================================

function EventBannerScreen:_BuildContent()
	self._gp = self:LayoutKit() == "GP"
	local theme = self:GetTheme()

	self._shadows = {}
	self._rows = {}
	self._rowPool = {}

	self:_BuildBand(theme)
	self:_BuildClock(theme)
	self:_BuildBoard(theme)
	self:_BuildDetails(theme)
	self:_BuildSpectateBar(theme)
	self:_BuildTitleCard(theme)

	-- THE one ticker registration for this screen: both countdowns, the panic
	-- pulse and the title-card hold. Bound to the Gui, so a style rebuild
	-- unregisters it for free.
	self._stopTicker = UITicker.Register(function(_dt: number, now: number)
		self:_Tick(now)
	end, self.Gui)
end

-- A full-width band, not a centred popup: a floating box reads as one more
-- notification, a band reads as the game telling you something. ONE height,
-- always — the ENTER button sits INLINE on the right rather than stacking
-- under the text, so the band costs the same 104px whether entries are open
-- or not.
function EventBannerScreen:_BuildBand(theme: Types.UITheme)
	local band = self:_Fill(self.Root, "Band", if self._gp then theme.Colors.Primary else theme.Arcade.Panel)
	band.Position = UDim2.new(0, 0, BANNER_Y, 0)
	band.Size = UDim2.new(1, 0, 0, BANNER_H)
	band.Visible = false
	band.ZIndex = 10
	self._band = band

	if self._gp then
		GPLayoutKit.SoftStroke(theme, band)
		GPLayoutKit.Shadow(theme, band, "md", self._shadows, theme.Colors.Primary)
		GPLayoutKit.GlazeSheen(theme, band)
		-- The doily lip along the bottom edge. "Bottom" is the unrotated edge,
		-- so it is safe anywhere; the rotated Top/Left/Right strips are page
		-- chrome only and would not clip inside a scrolling host.
		GPLayoutKit.Scallop(theme, band, "Bottom", theme.Colors.Primary)
	else
		-- Rules top and bottom rather than a UIStroke: a stroke would box the
		-- screen edges too.
		for _, yScale in { 0, 1 } do
			local rule = self:_Fill(band, "Rule", theme.Colors.Stroke)
			rule.AnchorPoint = Vector2.new(0, yScale)
			rule.Position = UDim2.new(0, 0, yScale, 0)
			rule.Size = UDim2.new(1, 0, 0, 3)
			rule.ZIndex = 13
		end
		UIChrome.GlassGradient().Parent = band
	end

	local eyebrow = self:_Body(band, "Server event", theme.TextSizes.Small, theme.Colors.TextSecondary)
	eyebrow.Position = UDim2.fromOffset(0, 10)
	eyebrow.Size = UDim2.new(1, -BTN_ZONE, 0, 22)
	eyebrow.ZIndex = 11
	self._eyebrow = eyebrow

	local title = self:_Display(band, self._eventName, theme.TextSizes.Title + 6, theme.Colors.TextPrimary)
	title.Position = UDim2.fromOffset(0, 30)
	title.Size = UDim2.new(1, -BTN_ZONE, 0, 42)
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.ZIndex = 11
	self._bandTitle = title

	-- Body copy on rose is TextPrimary (5.15:1). TextOnPrimary measures 2.14:1
	-- there and can never carry a line this long.
	local sub = self:_Body(band, "", theme.TextSizes.Body, theme.Colors.TextPrimary)
	sub.Position = UDim2.fromOffset(0, 70)
	sub.Size = UDim2.new(1, -BTN_ZONE, 0, 26)
	sub.ZIndex = 11
	self._bandSub = sub

	-- Entry fill meter: how full the field is, at a glance.
	local track = self:_Fill(band, "QueueTrack", theme.Arcade.RulerTrack)
	track.AnchorPoint = Vector2.new(1, 1)
	track.Position = UDim2.new(1, -(BTN_ZONE - 40), 1, -14)
	track.Size = UDim2.fromOffset(240, 6)
	track.ZIndex = 11
	UIStyler.Corner(theme.Radii.Pill).Parent = track
	self._queueTrack = track

	local fill = self:_Fill(track, "QueueFill", theme.Colors.Secondary)
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = 12
	UIStyler.Corner(theme.Radii.Pill).Parent = fill
	self._queueFill = fill

	self._enterButton = self:_Button(band, {
		name = "Enter",
		text = "Enter",
		fill = theme.Colors.Secondary,
		size = UDim2.fromOffset(268, 62),
		position = UDim2.new(1, -32, 0.5, 0),
		anchorPoint = Vector2.new(1, 0.5),
		index = 1,
		textSize = theme.TextSizes.Subtitle,
		zIndex = 14,
		onClick = function()
			self:_Enter()
		end,
	})
	self._enterButton.root.Visible = false
end

function EventBannerScreen:_BuildClock(theme: Types.UITheme)
	local plate = self:_Plate(self.Root, "ClockPlate", 0)
	plate.AnchorPoint = Vector2.new(0.5, 0)
	plate.Position = UDim2.new(0.5, 0, 0, 20)
	plate.Size = UDim2.fromOffset(CLOCK_W, CLOCK_H)
	plate.Visible = false
	plate.ZIndex = 8
	self._clockPlate = plate

	local phase = self:_Display(plate, "", theme.TextSizes.Subtitle, theme.Arcade.Gold)
	phase.Position = UDim2.fromOffset(0, 8)
	phase.Size = UDim2.new(1, 0, 0, 26)
	phase.ZIndex = 9
	self._clockPhase = phase

	local time = self:_Display(plate, "", 54, theme.Colors.TextPrimary)
	time.Position = UDim2.fromOffset(0, 32)
	time.Size = UDim2.new(1, 0, 0, 58)
	time.ZIndex = 9
	self._clockTime = time

	-- Round pips: which round of how many, without spending a line of copy.
	local pips = self:_Fill(plate, "RoundPips", theme.Colors.Background, 1)
	pips.AnchorPoint = Vector2.new(0.5, 1)
	pips.Position = UDim2.new(0.5, 0, 1, -8)
	pips.Size = UDim2.new(1, -24, 0, 12)
	pips.ZIndex = 9
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
	}).Parent = pips
	self._roundPips = pips
	self._pips = {} :: { Frame }
end

function EventBannerScreen:_BuildBoard(theme: Types.UITheme)
	local plate = self:_Plate(self.Root, "BoardPlate", 1)
	plate.AnchorPoint = Vector2.new(1, 0.5)
	plate.Position = UDim2.new(1, -20, 0.5, 0)
	plate.Size = UDim2.fromOffset(BOARD_W, BOARD_H)
	plate.Visible = false
	plate.ClipsDescendants = true
	plate.ZIndex = 8
	self._boardPlate = plate

	local title = self:_Display(plate, "Standings", theme.TextSizes.Subtitle, theme.Arcade.Gold)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(14, 10)
	title.Size = UDim2.new(1, -28, 0, 28)
	title.ZIndex = 9
	self._boardTitle = title

	local sub = self:_Body(plate, "", theme.TextSizes.Small, theme.Colors.TextSecondary)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.Position = UDim2.fromOffset(14, 38)
	sub.Size = UDim2.new(1, -28, 0, 20)
	sub.ZIndex = 9
	self._boardSub = sub

	local list = Instance.new("ScrollingFrame")
	list.Name = "Rows"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(8, 64)
	list.Size = UDim2.new(1, -16, 1, -(64 + 40))
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 5
	list.ScrollBarImageColor3 = theme.Colors.Primary
	-- Scrolled rows must never spill past the plate, and the padding keeps the
	-- rows' own soft shadows from being sheared off by the clip.
	list.ClipsDescendants = true
	list.ZIndex = 9
	list.Parent = plate
	UIStyler.ListLayout({ Padding = UDim.new(0, 5) }).Parent = list
	UIStyler.PaddingXY(6, 6).Parent = list
	self._boardList = list

	local footer = self:_Body(plate, "", theme.TextSizes.Small, theme.Colors.TextSecondary)
	footer.TextXAlignment = Enum.TextXAlignment.Left
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.new(0, 14, 1, -10)
	footer.Size = UDim2.new(1, -28, 0, 22)
	footer.ZIndex = 9
	self._boardFooter = footer
end

-- The reward ladder. The source retired this as a competing entry UI and kept
-- it built; so does this — `showEntryDetails` is the only thing that opens it.
function EventBannerScreen:_BuildDetails(theme: Types.UITheme)
	local plate = self:_Plate(self.Root, "DetailsPlate", 0)
	plate.AnchorPoint = Vector2.new(0.5, 0.5)
	plate.Position = UDim2.fromScale(0.5, 0.5)
	plate.Size = UDim2.fromOffset(DETAILS_W, DETAILS_H)
	plate.Visible = false
	plate.ZIndex = 12
	self._detailsPlate = plate

	local title = self:_Display(plate, "Entries open", theme.TextSizes.Title, theme.Arcade.Gold)
	title.Position = UDim2.fromOffset(0, 14)
	title.Size = UDim2.new(1, 0, 0, 38)
	title.ZIndex = 13

	local count = self:_Display(plate, "", theme.TextSizes.Subtitle, theme.Colors.TextPrimary)
	count.Position = UDim2.fromOffset(0, 54)
	count.Size = UDim2.new(1, 0, 0, 28)
	count.ZIndex = 13
	self._detailsCount = count

	local ladder = self:_Body(plate, "", theme.TextSizes.Body, theme.Colors.TextPrimary)
	ladder.TextXAlignment = Enum.TextXAlignment.Left
	ladder.TextWrapped = true
	ladder.Position = UDim2.fromOffset(20, 92)
	ladder.Size = UDim2.new(1, -40, 0, 120)
	ladder.ZIndex = 13
	self._detailsLadder = ladder

	self._detailsButton = self:_Button(plate, {
		name = "DetailsEnter",
		text = "Enter",
		fill = theme.Colors.Secondary,
		size = UDim2.fromOffset(244, 62),
		position = UDim2.new(0.5, 0, 1, -22),
		anchorPoint = Vector2.new(0.5, 1),
		index = 1,
		textSize = theme.TextSizes.Subtitle,
		zIndex = 14,
		onClick = function()
			self:_Enter()
		end,
	})
end

function EventBannerScreen:_BuildSpectateBar(theme: Types.UITheme)
	local plate = self:_Plate(self.Root, "SpectatePlate", 1)
	plate.AnchorPoint = Vector2.new(0.5, 1)
	plate.Position = UDim2.new(0.5, 0, 1, -20)
	plate.Size = UDim2.fromOffset(SPECT_W, SPECT_H)
	plate.Visible = false
	plate.ZIndex = 8
	self._spectPlate = plate

	local text = self:_Display(plate, "Spectating", theme.TextSizes.Subtitle, theme.Arcade.Gold)
	text.Position = UDim2.fromOffset(0, 8)
	text.Size = UDim2.new(1, 0, 0, 28)
	text.ZIndex = 9
	self._spectText = text

	self._spectButton = self:_Button(plate, {
		name = "LeaveSpectate",
		text = "Leave spectating",
		fill = theme.Colors.Error,
		size = UDim2.fromOffset(224, 40),
		position = UDim2.new(0.5, 0, 1, -12),
		anchorPoint = Vector2.new(0.5, 1),
		index = 0,
		textSize = theme.TextSizes.Body,
		zIndex = 10,
		onClick = function()
			local callback = self._onLeaveSpectate
			if callback then
				task.spawn(callback)
			end
			self._spectating = false
			self:_Render()
		end,
	})
end

function EventBannerScreen:_BuildTitleCard(theme: Types.UITheme)
	local card = self:_Fill(self.Root, "TitleCard", theme.Colors.Background, 1)
	card.Size = UDim2.fromScale(1, 1)
	card.Visible = false
	card.ZIndex = 20
	self._titleCard = card

	local big = self:_Display(card, "", 88, theme.Arcade.Gold)
	big.AnchorPoint = Vector2.new(0.5, 0.5)
	big.Position = UDim2.new(0.5, 0, 0.42, 0)
	big.Size = UDim2.fromOffset(1000, 110)
	big.TextTruncate = Enum.TextTruncate.AtEnd
	big.ZIndex = 21
	self._titleBig = big

	local small = self:_Display(card, "", theme.TextSizes.Title, theme.Colors.TextPrimary)
	small.AnchorPoint = Vector2.new(0.5, 0.5)
	small.Position = UDim2.new(0.5, 0, 0.53, 0)
	small.Size = UDim2.fromOffset(1000, 44)
	small.ZIndex = 21
	self._titleSmall = small

	local scale = Instance.new("UIScale")
	scale.Parent = card
	self._titleScale = scale

	-- Confetti gets its own layer ABOVE the title card: the card is a full-screen
	-- transparent host and parenting the shower inside it would tie the shower's
	-- lifetime to the card's 4-second hold. This layer never hides.
	local fx = self:_Fill(self.Root, "FxLayer", theme.Colors.Background, 1)
	fx.Size = UDim2.fromScale(1, 1)
	fx.ZIndex = 30
	self._fxLayer = fx
end

-- ========================================================================
-- Ceremony confetti — the source's shower, tracked so a hide can kill it
-- mid-air (a fire-and-forget tween outlives the screen otherwise).
-- ========================================================================

function EventBannerScreen:_ClearConfetti()
	for _, tween in self._confettiTweens do
		tween:Cancel()
	end
	table.clear(self._confettiTweens)
	for _, piece in self._confetti do
		piece:Destroy()
	end
	table.clear(self._confetti)
end

function EventBannerScreen:_BurstConfetti(count: number)
	local theme = self:GetTheme()
	local host = self._fxLayer
	if not host then
		return
	end
	local colors = table.clone(theme.Arcade.Rainbow)
	table.insert(colors, theme.Arcade.Magenta)

	for _ = 1, count do
		local size = math.random(CONFETTI_MIN, CONFETTI_MAX)
		local tint = colors[math.random(#colors)]
		-- Under GP the squares are cut from the pack's confetti art; every other
		-- pack keeps the source's plain square.
		local piece: GuiObject = if self._gp
			then GPLayoutKit.Slice(theme, "confetti", tint, "Confetti")
			else self:_Fill(host, "Confetti", tint)
		piece.Position = UDim2.new(math.random(), 0, 0, -30)
		piece.Size = UDim2.fromOffset(size, size)
		piece.Rotation = math.random(0, 360)
		piece.ZIndex = 31
		piece.Parent = host
		table.insert(self._confetti, piece)

		local seconds = CONFETTI_MIN_TIME + math.random() * (CONFETTI_MAX_TIME - CONFETTI_MIN_TIME)
		local tween = TweenService:Create(piece, TweenInfo.new(seconds, Enum.EasingStyle.Linear), {
			Position = UDim2.new(piece.Position.X.Scale, math.random(-CONFETTI_DRIFT, CONFETTI_DRIFT), 1, 60),
			Rotation = piece.Rotation + math.random(-CONFETTI_SPIN, CONFETTI_SPIN),
		})
		table.insert(self._confettiTweens, tween)
		-- BOTH lists are pruned on landing. The screen stays shown across many
		-- ceremonies, so tracking that only ever appends would grow by a shower
		-- every twenty minutes and never come back down.
		tween.Completed:Once(function()
			local pieceIndex = table.find(self._confetti, piece)
			if pieceIndex then
				table.remove(self._confetti, pieceIndex)
			end
			local tweenIndex = table.find(self._confettiTweens, tween)
			if tweenIndex then
				table.remove(self._confettiTweens, tweenIndex)
			end
			piece:Destroy()
		end)
		tween:Play()
	end
end

-- ========================================================================
-- Standings rows (pooled)
-- ========================================================================

function EventBannerScreen:_AcquireRow(): any
	local pooled = table.remove(self._rowPool)
	if pooled then
		pooled.root.Visible = true
		return pooled
	end
	local theme = self:GetTheme()

	local root = self:_Fill(self._boardList, "Row", theme.Colors.Surface)
	root.Size = UDim2.new(1, 0, 0, BOARD_ROW_H)
	root.ZIndex = 10
	if not self._gp then
		-- Added ONCE, at creation. Re-cornering a pooled row every render is
		-- how you end up with a stack of UICorner children; the GP path is
		-- immune because CornerSet clears the stale one first.
		UIChrome.Corner("Arcade", "Sub").Parent = root
	end

	local rank = self:_Numeric(root, theme.TextSizes.Small, theme.Colors.TextSecondary)
	rank.TextXAlignment = Enum.TextXAlignment.Right
	rank.Position = UDim2.fromOffset(4, 0)
	rank.Size = UDim2.fromOffset(26, 22)
	rank.ZIndex = 11

	local name = self:_Body(root, "", theme.TextSizes.Body, theme.Colors.TextPrimary)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(38, 0)
	name.Size = UDim2.new(1, -(38 + 78), 0, 22)
	name.ZIndex = 11

	local score = self:_Numeric(root, theme.TextSizes.Body, theme.Arcade.Gold)
	score.AnchorPoint = Vector2.new(1, 0)
	score.Position = UDim2.new(1, -10, 0, 0)
	score.Size = UDim2.fromOffset(70, 22)
	score.ZIndex = 11

	local track = self:_Fill(root, "Track", theme.Arcade.RulerTrack)
	track.AnchorPoint = Vector2.new(0, 1)
	track.Position = UDim2.new(0, 38, 1, -6)
	track.Size = UDim2.new(1, -(38 + 14), 0, 5)
	track.ZIndex = 11
	UIStyler.Corner(theme.Radii.Pill).Parent = track

	local fill = self:_Fill(track, "Fill", theme.Colors.Primary)
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = 12
	UIStyler.Corner(theme.Radii.Pill).Parent = fill

	-- The CUT LINE, drawn on the last surviving row rather than as an extra
	-- row: it belongs to the boundary, not to the list.
	local cutLine = self:_Fill(root, "CutLine", theme.Colors.Error)
	cutLine.AnchorPoint = Vector2.new(0, 1)
	cutLine.Position = UDim2.new(0, 0, 1, 0)
	cutLine.Size = UDim2.new(1, 0, 0, 2)
	cutLine.Visible = false
	cutLine.ZIndex = 13
	UIStyler.Corner(theme.Radii.Pill).Parent = cutLine

	return { root = root, rank = rank, name = name, score = score, fill = fill, cutLine = cutLine }
end

function EventBannerScreen:_ReleaseRows()
	for _, row in self._rows do
		row.root.Visible = false
		row.root.Parent = nil
		table.insert(self._rowPool, row)
	end
	table.clear(self._rows)
end

-- ========================================================================
-- Ingest — record WHAT to show; the ticker draws it every frame.
-- ========================================================================

function EventBannerScreen:_Ingest(data: any?)
	if type(data) ~= "table" then
		return
	end
	local payload = data :: EventData

	if type(payload.eventName) == "string" then
		self._eventName = payload.eventName
	end
	if type(payload.blurb) == "string" then
		self._blurb = payload.blurb
	end
	if type(payload.phase) == "string" then
		self._phase = payload.phase
	end
	if type(payload.roundNum) == "number" then
		self._roundNum = payload.roundNum
	end
	if type(payload.roundCount) == "number" then
		self._roundCount = payload.roundCount
	end
	if type(payload.isFinal) == "boolean" then
		self._isFinal = payload.isFinal
	end
	if type(payload.tiebreakSeconds) == "number" then
		self._tiebreakSeconds = payload.tiebreakSeconds
	end
	if type(payload.phaseEndsAt) == "number" then
		self._phaseEndsAt = payload.phaseEndsAt
	end
	if type(payload.nextEventAt) == "number" then
		self._nextEventAt = payload.nextEventAt
	end
	if type(payload.queueOpen) == "boolean" then
		self._queueOpen = payload.queueOpen
	end
	if type(payload.queueCount) == "number" then
		self._queueCount = payload.queueCount
	end
	if type(payload.slots) == "number" then
		self._slots = payload.slots
	end
	if type(payload.entered) == "boolean" then
		self._entered = payload.entered
	end
	if type(payload.alive) == "boolean" then
		self._alive = payload.alive
	end
	if type(payload.spectating) == "boolean" then
		self._spectating = payload.spectating
	end
	if type(payload.inMatch) == "boolean" then
		self._inMatch = payload.inMatch
	end
	if type(payload.showEntryDetails) == "boolean" then
		self._showEntryDetails = payload.showEntryDetails
	end
	if type(payload.players) == "table" then
		self._players = payload.players
	end
	if type(payload.rewards) == "table" then
		self._rewards = payload.rewards
	end
	if type(payload.myResult) == "table" then
		self._myResult = payload.myResult
	end
	if type(payload.survivorsFor) == "function" then
		self._survivorsFor = payload.survivorsFor
	end
	if type(payload.onEnter) == "function" then
		self._onEnter = payload.onEnter
	end
	if type(payload.onLeaveSpectate) == "function" then
		self._onLeaveSpectate = payload.onLeaveSpectate
	end

	-- WHICH clock the band is counting against. Idle counts the announce
	-- cadence (os.time); the entry window counts the phase deadline (server
	-- clock). Mixing them is a countdown that drifts by the server's uptime.
	if self._phase == "idle" then
		self._bannerKind = "next"
		self._bannerAt = self._nextEventAt
	elseif self._phase == "warn" or self._phase == "queue" then
		self._bannerKind = "entry"
		self._bannerAt = self._phaseEndsAt
	else
		self._bannerKind = "none"
	end
end

-- ========================================================================
-- Render
-- ========================================================================

function EventBannerScreen:_Render()
	self:_RenderBand()
	self:_RenderClock()
	self:_RenderBoard()
	self:_RenderDetails()
	self:_RenderSpectate()
end

function EventBannerScreen:_RenderBand()
	local theme = self:GetTheme()
	local band = self._band
	if not band then
		return
	end

	-- Players at a table get NO band at all. The server refuses their entry
	-- anyway, so an ENTER they can press but that can never work is a lie —
	-- and a wide opaque strip across a live match is worse than useless.
	if self._inMatch then
		band.Visible = false
		self._enterButton.root.Visible = false
		return
	end

	self._bandTitle.Text = self._eventName

	if self._bannerKind == "next" then
		local left = math.max(0, self._bannerAt - os.time())
		-- Announce only inside the last two minutes, and never at zero.
		band.Visible = left <= 120 and left > 0
		self._bandSub.Text = string.format("Next competition in %d:%02d", left // 60, left % 60)
	elseif self._bannerKind == "entry" then
		band.Visible = true
		local left = math.max(0, math.ceil(self._bannerAt - Workspace:GetServerTimeNow()))
		local firstBux = (self._rewards.placementBux or {})[1] or 1000
		if self._entered then
			self._bandSub.Text = string.format(
				"You're in! Starts in %ds \u{2014} %d/%d entered",
				left,
				self._queueCount,
				self._slots
			)
		else
			self._bandSub.Text = string.format(
				"Starts in %ds \u{2014} %d/%d entered \u{2014} 1st: a %s chair + %d Bux",
				left,
				self._queueCount,
				self._slots,
				self._rewards.firstChairRarity or "Legendary",
				firstBux
			)
		end
	else
		band.Visible = false
	end

	local showQueue = band.Visible and self._bannerKind == "entry"
	self._queueTrack.Visible = showQueue
	if showQueue then
		local ratio = if self._slots > 0 then math.clamp(self._queueCount / self._slots, 0, 1) else 0
		self._queueFill.Size = UDim2.fromScale(ratio, 1)
		self._queueFill.BackgroundColor3 = if ratio >= 1 then theme.Colors.Error else theme.Colors.Secondary
	end

	local showEnter = band.Visible and self._bannerKind == "entry" and self._queueOpen
	self._enterButton.root.Visible = showEnter
	if showEnter then
		self._enterButton.SetText(if self._entered then "Entered \u{2713}" else "Enter")
		self._enterButton.SetFill(if self._entered then theme.Colors.Disabled else theme.Colors.Secondary)
		self._enterButton.SetActive(not self._entered)
	end
end

function EventBannerScreen:_RenderClock()
	local theme = self:GetTheme()
	local plate = self._clockPlate
	if not plate then
		return
	end
	local phase = self._phase
	local showClock = phase ~= "idle" and phase ~= "teardown" and self._phaseEndsAt > 0
	-- "queue" and "warn" belong to the band, which already carries that number
	-- AND the button. Two copies of one countdown, overlapping, is the bug.
	plate.Visible = showClock and phase ~= "queue" and phase ~= "warn"
	if not plate.Visible then
		return
	end

	local label = PHASE_LABEL[phase] or phase
	if phase == "shape" or phase == "intro" or phase == "walk" then
		label = string.format("Round %d \u{2014} %s", math.max(1, self._roundNum), label)
	end
	if self._isFinal then
		label = "Final \u{2014} " .. (PHASE_LABEL[phase] or "")
	end
	self._clockPhase.Text = label

	local left = math.max(0, self._phaseEndsAt - Workspace:GetServerTimeNow())
	self._clockTime.Text = if left >= 60
		then string.format("%d:%02d", left // 60, left % 60)
		else string.format("%d", math.ceil(left))

	-- The last ten seconds of a shaping round go red and pulse.
	local panic = left <= PANIC_SECONDS and phase == "shape"
	self._clockTime.TextColor3 = if panic then theme.Colors.Error else theme.Colors.TextPrimary
	self._clockTime.TextSize = if panic then math.round(54 * (1 + 0.12 * math.abs(math.sin(os.clock() * 6)))) else 54

	self:_RenderPips()
end

function EventBannerScreen:_RenderPips()
	local theme = self:GetTheme()
	local count = math.max(0, self._roundCount)
	if #self._pips ~= count then
		for _, pip in self._pips do
			pip:Destroy()
		end
		table.clear(self._pips)
		for i = 1, count do
			local pip = self:_Fill(self._roundPips, "Pip" .. i, theme.Arcade.RulerTrack)
			pip.Size = UDim2.fromOffset(26, 6)
			pip.LayoutOrder = i
			pip.ZIndex = 10
			UIStyler.Corner(theme.Radii.Pill).Parent = pip
			table.insert(self._pips, pip)
		end
	end
	for i, pip in self._pips do
		pip.BackgroundColor3 = if i <= self._roundNum then theme.Colors.Primary else theme.Arcade.RulerTrack
	end
end

function EventBannerScreen:_RenderBoard()
	local theme = self:GetTheme()
	local plate = self._boardPlate
	if not plate then
		return
	end
	local phase = self._phase
	local players = self._players
	local show = phase ~= "idle" and phase ~= "warn" and #players > 0
	plate.Visible = show
	if not show then
		self:_ReleaseRows()
		return
	end

	self:_ReleaseRows()

	local aliveCount = 0
	local best, total = 0, 0
	for _, entry in players do
		if entry.alive ~= false then
			aliveCount += 1
			total += entry.score
			best = math.max(best, entry.score)
		end
	end
	-- The cut line comes from the SAME function the server eliminates with, so
	-- the line a player sees can never disagree with who actually goes home.
	local keep = math.clamp(self._survivorsFor(aliveCount), 0, aliveCount)
	local showCut = (phase == "shape" or phase == "grading" or phase == "reveal") and aliveCount > keep

	self._boardSub.Text = if showCut
		then string.format("top %d of %d survive", keep, aliveCount)
		else string.format("%d competitor%s", aliveCount, if aliveCount == 1 then "" else "s")

	local aliveSeen = 0
	for i, entry in players do
		local alive = entry.alive ~= false
		if alive then
			aliveSeen += 1
		end
		local inCutZone = showCut and alive and aliveSeen > keep
		local row = self:_AcquireRow()
		row.root.LayoutOrder = i
		if self._gp then
			-- Alternating petal sets, so a board reads hand-arranged.
			GPLayoutKit.Petal(theme, row.root, i)
		end
		row.root.BackgroundColor3 = if not alive
			then theme.Colors.Disabled
			elseif inCutZone then theme.Colors.Error:Lerp(theme.Colors.Surface, 0.7)
			else theme.Colors.Surface
		row.rank.Text = tostring(i)
		row.name.Text = entry.name
		row.name.TextColor3 = if alive then theme.Colors.TextPrimary else theme.Colors.TextSecondary
		row.score.Text = if alive then string.format("%d%%", entry.score) else "out"
		row.score.TextColor3 = if not alive
			then theme.Colors.TextSecondary
			elseif inCutZone then theme.Colors.Error
			else theme.Arcade.Gold
		row.fill.Size = UDim2.fromScale(if best > 0 then math.clamp(entry.score / best, 0, 1) else 0, 1)
		row.fill.BackgroundColor3 = if inCutZone then theme.Colors.Error else theme.Colors.Primary
		row.cutLine.Visible = showCut and alive and aliveSeen == keep
		row.root.Parent = self._boardList
		table.insert(self._rows, row)
	end

	local average = if aliveCount > 0 then total / aliveCount else 0
	self._boardFooter.Text = string.format("leader %d%% \u{00B7} average %.1f%%", best, average)
end

function EventBannerScreen:_RenderDetails()
	local theme = self:GetTheme()
	local plate = self._detailsPlate
	if not plate then
		return
	end
	local show = self._showEntryDetails and (self._phase == "queue" or self._phase == "warn")
	plate.Visible = show
	if not show then
		return
	end
	local bux = self._rewards.placementBux or { 1000, 500, 250 }
	self._detailsCount.Text = string.format("%d of %d entered", self._queueCount, self._slots)
	self._detailsLadder.Text = string.format(
		"1st: a %s chair + %d Bux\n2nd: %d Bux    3rd: %d Bux\nEveryone on stage: %d Bux",
		self._rewards.firstChairRarity or "Legendary",
		bux[1] or 0,
		bux[2] or 0,
		bux[3] or 0,
		self._rewards.participationBux or 0
	)
	self._detailsButton.SetText(if self._entered then "Entered \u{2713}" else "Enter")
	self._detailsButton.SetFill(if self._entered then theme.Colors.Disabled else theme.Colors.Secondary)
	self._detailsButton.SetActive(not self._entered)
end

function EventBannerScreen:_RenderSpectate()
	local plate = self._spectPlate
	if not plate then
		return
	end
	plate.Visible = self._spectating and self._phase ~= "idle"
	self._spectText.Text = if self._entered and not self._alive
		then "Eliminated \u{2014} spectating"
		else "Spectating"
end

-- ========================================================================
-- Title cards
-- ========================================================================

function EventBannerScreen:_ShowTitle(big: string, small: string, hold: number)
	if not self._titleCard then
		return
	end
	self._titleBig.Text = big
	self._titleSmall.Text = small
	self._titleCard.Visible = true
	self._titleScale.Scale = 0.72
	self._titleUntil = UITicker.Now() + hold
	UIStyler.Tween(self._titleScale, self:GetTheme().Motion.PopIn, { Scale = 1 }):Play()
end

-- Phase entry cards, in the source's own words.
function EventBannerScreen:_OnPhaseEntered()
	local phase = self._phase
	local involved = self._entered or self._spectating
	if phase == "queue" then
		if involved then
			self:_ShowTitle(self._eventName, self._blurb, 3)
		end
		return
	end
	if not involved then
		-- Bystanders get no title cards for the rest of the run.
		return
	end
	if phase == "intro" then
		if self._isFinal then
			self:_ShowTitle(
				"The final",
				string.format("%d seconds. One pot. Winner takes it.", math.max(0, self._tiebreakSeconds)),
				4
			)
		else
			self:_ShowTitle(
				string.format("Round %d of %d", math.max(1, self._roundNum), math.max(1, self._roundCount)),
				"Everyone shapes the same pot",
				3.5
			)
		end
	elseif phase == "cut" then
		local gone = {}
		for _, entry in self._players do
			if entry.alive == false and entry.eliminatedRound == self._roundNum then
				table.insert(gone, entry.name)
			end
		end
		if #gone > 0 then
			self:_ShowTitle("Eliminated", table.concat(gone, "  \u{2022}  "), 3.5)
		end
	elseif phase == "ceremony" then
		local champion: EventPlayer? = nil
		for _, entry in self._players do
			if entry.alive ~= false and (not champion or entry.score > champion.score) then
				champion = entry
			end
		end
		-- THE SUBTITLE IS PERSONAL FIRST. The source prints the player's own
		-- placement and payout when they competed and only falls back to the
		-- champion line for spectators — a finalist reading "someone else takes
		-- the cup" instead of their own +Bux is the whole payoff thrown away.
		local mine = self._myResult
		local sub = ""
		if mine and mine.place then
			local chairLine = if mine.chair
				then string.format(
					" + a %s chair!",
					mine.chairRarity or self._rewards.firstChairRarity or "Legendary"
				)
				else ""
			sub = string.format(
				"You placed %d \u{2014} +%d Bux, +$%d%s",
				mine.place,
				mine.bux or 0,
				mine.cash or 0,
				chairLine
			)
		elseif champion then
			sub = string.format("%s takes the cup with %d%%", champion.name, champion.score)
		end
		self:_ShowTitle(if champion then champion.name .. " wins!" else "Results", sub, 4)
		-- The source showers the winner card. Same beats, pack colours.
		self:_BurstConfetti(CONFETTI_COUNT)
		self:_PlaySound("Success")
	end
end

function EventBannerScreen:_Enter()
	if self._entered then
		return
	end
	local callback = self._onEnter
	if callback then
		task.spawn(callback)
	end
	-- OPTIMISTIC only in the button's own look; the payload is still the truth
	-- and the next Update overwrites this either way.
	self._entered = true
	self:_Render()
	self:_PlaySound("Success")
end

-- ========================================================================
-- Tick — the countdowns, the panic pulse, the title-card hold
-- ========================================================================

function EventBannerScreen:_Tick(now: number)
	if not self:IsVisible() then
		return
	end
	self:_RenderBand()
	self:_RenderClock()
	if self._titleCard and self._titleCard.Visible and now >= self._titleUntil then
		self._titleCard.Visible = false
	end
end

-- ========================================================================
-- Lifecycle
-- ========================================================================

function EventBannerScreen:_OnShow(data: any?)
	if data == nil and not self._seeded then
		-- Standalone demo: seed both clocks so the screen is exercisable with
		-- no backend, each against the clock that would have produced it.
		-- "queue" is the state the band OWNS: the clock plate is deliberately
		-- suppressed here (two copies of one countdown, overlapping, is the bug
		-- this rule exists to prevent), so the band and the board carry it.
		self._seeded = true
		self._phase = "queue"
		self._roundNum = 0
		self._phaseEndsAt = Workspace:GetServerTimeNow() + 45
		self._nextEventAt = os.time() + 95
		self._queueOpen = true
		self._queueCount = 8
		self._entered = false
		self:_Ingest({})
	end
	self:_Ingest(data)
	local phaseChanged = self._phase ~= self._lastPhase or self._roundNum ~= self._lastRound
	self._lastPhase = self._phase
	self._lastRound = self._roundNum
	self:_Render()
	if phaseChanged then
		self:_OnPhaseEntered()
	end
end

function EventBannerScreen:_OnHide()
	if self._titleCard then
		self._titleCard.Visible = false
	end
	self:_ClearConfetti()
	self:_ReleaseRows()
end

function EventBannerScreen:Update(data: any)
	if not self._built then
		self:_Ingest(data)
		return
	end
	self:_Ingest(data)
	local phaseChanged = self._phase ~= self._lastPhase or self._roundNum ~= self._lastRound
	self._lastPhase = self._phase
	self._lastRound = self._roundNum
	self:_Render()
	if phaseChanged then
		self:_OnPhaseEntered()
	end
end

-- A style rebuild destroys the Gui, but UIShadow BUDGET counts only fall when
-- a handle is Released — hand every shadow back here, and stop the ticker.
function EventBannerScreen:_OnTeardown()
	if self._stopTicker then
		self._stopTicker()
		self._stopTicker = nil
	end
	-- A confetti tween outlives the Gui that hosted it, so it is cancelled here
	-- rather than left to fire Completed against a destroyed square.
	self:_ClearConfetti()
	GPLayoutKit.ReleaseShadows(self._shadows)
	-- Pooled rows are PARENTLESS while idle, so the Gui's destruction does not
	-- take them with it.
	for _, bucket in { self._rows, self._rowPool } do
		if bucket then
			for _, row in bucket :: { any } do
				row.root:Destroy()
			end
			table.clear(bucket :: { any })
		end
	end
	if self._pips then
		table.clear(self._pips)
	end
	self._band = nil
	self._clockPlate = nil
	self._boardPlate = nil
	self._detailsPlate = nil
	self._spectPlate = nil
	self._titleCard = nil
	self._fxLayer = nil
end

function EventBannerScreen:Destroy()
	self:_OnHide()
	if self._built then
		self:_OnTeardown()
	end
	UIScreenBase.Destroy(self)
end

return EventBannerScreen
