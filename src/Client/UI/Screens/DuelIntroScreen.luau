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

export type Competitor = {
	name: string,
	userId: number?,
	wins: number?,
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

local DEMO_LEFT: Competitor = { name = "ClayCrusher", wins = 1 }
local DEMO_RIGHT: Competitor = { name = "KilnKing", wins = 0 }

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
	end
	self:_Render()
end

function DuelIntroScreen:_OnHide()
	-- Stops the pulse loop and orphans any in-flight headshot fetch.
	self._pulseGen += 1
	self._renderGen += 1
end

function DuelIntroScreen:Update(data: any)
	if self._built and self:IsVisible() then
		self:_OnShow(data)
	end
end

function DuelIntroScreen:Destroy()
	self:_OnHide()
	UIScreenBase.Destroy(self)
end

return DuelIntroScreen
