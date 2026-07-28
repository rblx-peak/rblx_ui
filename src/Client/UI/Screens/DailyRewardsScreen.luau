--!strict
-- DAILY REWARDS — the login calendar, Pottery Clash arcade family.
-- One §7.4 modal card: a streak header (fire icon, "DAY n STREAK", a 1Hz gold
-- countdown to the next daily reset) over a 7-column calendar of 28 day tiles.
--
-- Tile states, all recoloured IN PLACE (doc §11.2):
--   claimed  — dimmed well, a grey check standing in for the reward art
--   today    — gold selection ring that BREATHES on sin(t·2.4) (doc §5.3) with
--              a green CLAIM button in the tile's action strip
--   future   — dimmed art + grey text, never removed
--
-- Both ambient loops (the 1Hz countdown and the ring breath) are stored and
-- gated on UIChrome.IsOnScreen, then disconnected on hide (doc §5.4).
--
-- Fixed px at the 1650×1020 baseline (UIScreenBase attaches the UIScale).
--
-- GP (Girly Pop) additionally carries the live lobby's FULL daily surface —
-- free reward, the two paid affordances and their gating — see _BuildGPLayout.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local IconVisibility = require(script.Parent.Parent.Icons.IconVisibility)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UIScreenBase = require(script.Parent.UIScreenBase)
local GLLayoutKit = require(script.Parent.Parent.Framework.GLLayoutKit)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local UITicker = require(script.Parent.Parent.Framework.UITicker)

type Day = {
	day: number,
	icon: string,
	amount: string,
	claimed: boolean?,
	milestone: boolean?,
	-- The human reward line ("400 Cash", "Random limited chair"). The live
	-- lobby's ladder is labelled, not just numbered; the GP calendar prints it
	-- under the value pill and the classic/GL builds ignore it.
	label: string?,
}

-- Card 1240×800 → content 1212×712 after the §7.4 inset.
local CARD = Vector2.new(1240, 800)
local CONTENT_W = 1212
local CONTENT_H = 712
local HEADER_H = 68
local GRID_Y = HEADER_H + 12
local GRID_H = CONTENT_H - GRID_Y
local COLUMNS = 7
local CELL_W = 160
local CELL_H = 147
local CELL_PAD = 14
local DAY_SECONDS = 86400

local WHITE = Color3.new(1, 1, 1)

-- The reward ladder, in the live lobby's vocabulary (its DAY_META rungs are
-- labelled "100 BUX" / "RANDOM RARE SKIN" / "RANDOM LIMITED CHAIR"), rolled
-- over the collection's 28-day calendar. One table, read by every layout —
-- the build sites never carry reward strings of their own.
local LADDER: { { icon: string, amount: string, label: string } } = {
	{ icon = "cash", amount = "250", label = "250 Cash" },
	{ icon = "cash", amount = "400", label = "400 Cash" },
	{ icon = "bux", amount = "15", label = "15 Bux" },
	{ icon = "crate", amount = "1", label = "Glaze crate" },
	{ icon = "cash", amount = "750", label = "750 Cash" },
	{ icon = "bux", amount = "25", label = "25 Bux" },
	{ icon = "chest", amount = "1", label = "Random limited chair" },
}
local MILESTONE_LABEL = "Limited chair + %s Cash"

local function demoDays(): { Day }
	-- Reward ladder: small cash most days, a golden milestone every 7th.
	local days = {}
	for index = 1, 28 do
		local spec = LADDER[((index - 1) % #LADDER) + 1]
		local milestone = index % 7 == 0
		local amount = if milestone then tostring(index * 100) else spec.amount
		table.insert(days, {
			day = index,
			icon = if milestone then "chest" else spec.icon,
			amount = amount,
			claimed = index < 5,
			milestone = milestone,
			label = if milestone then string.format(MILESTONE_LABEL, amount) else spec.label,
		})
	end
	return days
end

local DailyRewardsScreen = setmetatable({}, { __index = UIScreenBase })
DailyRewardsScreen.__index = DailyRewardsScreen

function DailyRewardsScreen.new()
	local self = UIScreenBase.new("DailyRewardsScreen", 9)
	self._days = demoDays()
	self._day = 5
	self._claimedToday = false
	self._nextClaimIn = 8 * 3600 + 42 * 60 + 11
	self._tickConn = nil :: RBXScriptConnection?
	self._breathConn = nil :: RBXScriptConnection?
	self._claimBtn = nil :: any
	-- The live lobby's paid-daily gates (DailyRewardService publishes both):
	-- ONE paid action per UTC day, and paid RANDOM items are refused outright
	-- on restricted accounts — fail-closed, exactly as the shipped panel does.
	self._paidToday = false
	self._paidRestricted = false
	-- The group free-reward panel's persisted state (player attribute
	-- FreeClaimed) plus the membership check its CLAIM answers with.
	self._freeClaimed = false
	self._inGroup = false
	self._freeNote = ""
	return setmetatable(self, DailyRewardsScreen)
end

function DailyRewardsScreen:_Toast(text: string, variant: string)
	local hud = self.ScreenController and self.ScreenController:GetScreen("hud")
	if hud then
		hud:PushToast({ text = text, variant = variant })
	end
end

function DailyRewardsScreen:_Ingest(data: any)
	if type(data) ~= "table" then
		return
	end
	if type(data.days) == "table" then
		self._days = data.days
	end
	if type(data.day) == "number" then
		self._day = data.day
	end
	if type(data.claimedToday) == "boolean" then
		self._claimedToday = data.claimedToday
	end
	if type(data.nextClaimIn) == "number" then
		self._nextClaimIn = data.nextClaimIn
	end
	if type(data.paidToday) == "boolean" then
		self._paidToday = data.paidToday
	end
	if type(data.paidRestricted) == "boolean" then
		self._paidRestricted = data.paidRestricted
	end
	if type(data.freeClaimed) == "boolean" then
		self._freeClaimed = data.freeClaimed
	end
	if type(data.inGroup) == "boolean" then
		self._inGroup = data.inGroup
	end
end

-- ========================================================================
-- Header
-- ========================================================================

function DailyRewardsScreen:_BuildHeader(theme: Types.UITheme, content: Frame)
	local header = UIStyler.Frame("Header")
	header.BackgroundTransparency = 1
	header.Size = UDim2.fromOffset(CONTENT_W, HEADER_H)
	header.ZIndex = 44
	header.Parent = content

	local fire = IconArchive.Image(header, "fire", 46)
	fire.AnchorPoint = Vector2.new(0, 0.5)
	fire.Position = UDim2.new(0, 0, 0.5, 0)
	fire.ZIndex = 45

	local streak = UIChrome.Text("Streak", 34, theme.Arcade.Gold)
	streak.Text = "DAY 5 STREAK"
	streak.TextXAlignment = Enum.TextXAlignment.Left
	streak.Position = UDim2.fromOffset(58, 0)
	streak.Size = UDim2.fromOffset(420, HEADER_H)
	streak.ZIndex = 45
	streak.Parent = header
	self._streakLabel = streak

	local progress = UIChrome.Text("Progress", 20, theme.Arcade.IceBlue)
	progress.Text = ""
	progress.Position = UDim2.fromOffset(480, 0)
	progress.Size = UDim2.fromOffset(260, HEADER_H)
	progress.ZIndex = 45
	progress.Parent = header
	self._progressLabel = progress

	local clock = IconArchive.Image(header, "clock", 30)
	clock.AnchorPoint = Vector2.new(1, 0.5)
	clock.Position = UDim2.new(1, -352, 0.5, 0)
	clock.ZIndex = 45

	local caption = UIChrome.Text("Caption", 18, theme.Arcade.IceBlue)
	caption.Text = "NEXT DAY IN"
	caption.TextXAlignment = Enum.TextXAlignment.Right
	caption.AnchorPoint = Vector2.new(1, 0.5)
	caption.Position = UDim2.new(1, -186, 0.5, 0)
	caption.Size = UDim2.fromOffset(160, HEADER_H)
	caption.ZIndex = 45
	caption.Parent = header

	-- Countdown surface (doc §11.3): 1Hz, gold FredokaOne, HH:MM:SS.
	local countdown = UIChrome.Text("Countdown", 32, theme.Arcade.SunburstGold)
	countdown.Text = UIChrome.FormatCountdown(self._nextClaimIn)
	countdown.TextXAlignment = Enum.TextXAlignment.Right
	countdown.AnchorPoint = Vector2.new(1, 0.5)
	countdown.Position = UDim2.new(1, 0, 0.5, 0)
	countdown.Size = UDim2.fromOffset(180, HEADER_H)
	countdown.ZIndex = 45
	countdown.Parent = header
	self._countdown = countdown
end

-- ========================================================================
-- Calendar
-- ========================================================================

function DailyRewardsScreen:_BuildGrid(theme: Types.UITheme, content: Frame)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Calendar"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, GRID_Y)
	scroll.Size = UDim2.fromOffset(CONTENT_W, GRID_H)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = theme.Arcade.Gold
	scroll.ZIndex = 43
	scroll.Parent = content

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(CELL_W, CELL_H)
	grid.CellPadding = UDim2.fromOffset(CELL_PAD, CELL_PAD)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.FillDirectionMaxCells = COLUMNS
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
	grid.Parent = scroll
	self._grid = scroll
end

function DailyRewardsScreen:_BuildTile(theme: Types.UITheme, entry: Day, order: number)
	local claimed = entry.claimed == true
	local isToday = entry.day == self._day and not claimed
	local future = entry.day > self._day

	local root = UIStyler.Frame("Day" .. entry.day)
	root.BackgroundTransparency = 1
	root.LayoutOrder = order
	root.ZIndex = 43
	root.Parent = self._grid

	local surface = UIStyler.Frame("Surface")
	surface.BackgroundColor3 = if entry.milestone then theme.Arcade.NearBlack2 else theme.Arcade.NearBlack
	surface.BackgroundTransparency = if claimed then 0.45 elseif future then 0.3 else 0
	surface.Size = UDim2.fromScale(1, 1)
	surface.ZIndex = 44
	UIChrome.Corner("Arcade").Parent = surface
	UIChrome.Stroke(theme, "Arcade", "Panel").Parent = surface
	UIChrome.GlassGradient().Parent = surface
	surface.Parent = root

	local dim = if claimed then theme.Arcade.GreyClaimed elseif future then theme.Arcade.GreyOwned else WHITE
	local dayLabel = UIChrome.Text("DayLabel", 17, dim)
	dayLabel.Text = "DAY " .. tostring(entry.day)
	dayLabel.Position = UDim2.fromOffset(0, 6)
	dayLabel.Size = UDim2.new(1, 0, 0, 20)
	dayLabel.ZIndex = 45
	dayLabel.Parent = surface

	-- Claimed days swap the reward art for a grey check, in place.
	local artName = if claimed then "check" else entry.icon
	local art = IconArchive.Image(surface, artName, 48, { golden = entry.milestone and not claimed })
	art.AnchorPoint = Vector2.new(0.5, 0)
	art.Position = UDim2.new(0.5, 0, 0, 30)
	art.ZIndex = 45
	if art:IsA("ImageLabel") then
		if claimed then
			art.ImageColor3 = theme.Arcade.GreyClaimed
		elseif future then
			art.ImageTransparency = 0.35
		end
	else
		(art :: any).TextColor3 = dim
	end

	local amount = UIChrome.Text("Amount", 20, if claimed or future then dim else theme.Arcade.Gold)
	amount.RichText = false
	amount.Text = tostring(entry.amount or "")
	amount.Position = UDim2.fromOffset(0, 82)
	amount.Size = UDim2.new(1, 0, 0, 24)
	amount.ZIndex = 45
	amount.Parent = surface

	if isToday then
		self._claimBtn = UIButtonComponent.new()
		self._claimBtn:Create(surface, {
			text = if self._claimedToday then "CLAIMED" else "CLAIM",
			variant = if self._claimedToday then "Grey" else "Green",
			size = UDim2.fromOffset(CELL_W - 24, 32),
			position = UDim2.new(0.5, 0, 0, 108),
			anchorPoint = Vector2.new(0.5, 0),
			onClick = function()
				self:_Claim()
			end,
		})
		self._claimBtn.Root.ZIndex = 46

		-- Selection/attention ring: gold, outset, breathing on sin(t·2.4).
		local ring = UIStyler.Frame("TodayRing")
		ring.BackgroundTransparency = 1
		ring.Position = UDim2.fromOffset(-3, -3)
		ring.Size = UDim2.new(1, 6, 1, 6)
		ring.ZIndex = 46
		local stroke = UIChrome.Stroke(theme, "Arcade", "Selection")
		stroke.Parent = ring
		ring.Parent = root
		self:_StartBreath(ring, stroke)
	else
		local strip = UIChrome.Text("Strip", 14, dim)
		strip.Text = if claimed then "CLAIMED" elseif entry.milestone then "MILESTONE" else ""
		strip.Position = UDim2.fromOffset(0, 112)
		strip.Size = UDim2.new(1, 0, 0, 24)
		strip.ZIndex = 45
		strip.Parent = surface
		if entry.milestone and not claimed then
			strip.TextColor3 = theme.Arcade.SunburstGold
		end
	end
end

function DailyRewardsScreen:_StartBreath(host: GuiObject, stroke: UIStroke)
	self:_StopBreath()
	local elapsed = 0
	self._breathConn = RunService.RenderStepped:Connect(function(dt: number)
		if not stroke.Parent or not UIChrome.IsOnScreen(host) then
			return
		end
		elapsed += dt
		stroke.Thickness = 3 + 2.4 * (0.5 + 0.5 * math.sin(elapsed * 2.4))
	end)
end

function DailyRewardsScreen:_StopBreath()
	if self._breathConn then
		self._breathConn:Disconnect()
		self._breathConn = nil
	end
end

function DailyRewardsScreen:_RenderGrid()
	-- GL comic layout: the staggered cell field repaints in place (see
	-- _GLRefresh); the classic calendar build below is untouched.
	if self:LayoutKit() == "GL" then
		self:_GLRefresh()
		return
	end
	-- GP repaints the pastel calendar (and its rail) in place — see _GPRefresh.
	if self:LayoutKit() == "GP" then
		self:_GPRefresh()
		return
	end
	if not self._grid then
		return
	end
	local theme = self:GetTheme()
	self:_StopBreath()
	if self._claimBtn then
		self._claimBtn:Destroy()
		self._claimBtn = nil
	end
	for _, child in self._grid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for order, entry in self._days do
		self:_BuildTile(theme, entry, order)
	end

	local claimedCount = 0
	for _, entry in self._days do
		if entry.claimed then
			claimedCount += 1
		end
	end
	self._streakLabel.Text = string.format("DAY %d STREAK", self._day)
	self._progressLabel.Text = string.format("%d / %d CLAIMED", claimedCount, #self._days)
end

-- ========================================================================
-- Ticker + claiming
-- ========================================================================

function DailyRewardsScreen:_StartTicker()
	-- GP runs its clocks off the ONE shared UITicker Heartbeat instead of a
	-- screen-owned RunService connection (see _GPStartTicker).
	if self:LayoutKit() == "GP" then
		self:_GPStartTicker()
		return
	end
	if self._tickConn then
		return
	end
	local accumulated = 0
	self._tickConn = RunService.Heartbeat:Connect(function(dt: number)
		local label = self._countdown
		if not label or not label.Parent or not UIChrome.IsOnScreen(label) then
			return
		end
		accumulated += dt
		if accumulated < 1 then
			return
		end
		accumulated -= 1
		self._nextClaimIn = math.max(0, self._nextClaimIn - 1)
		label.Text = UIChrome.FormatCountdown(self._nextClaimIn)
		if self._nextClaimIn <= 0 then
			-- The daily reset rolled over: open the next day and re-arm.
			self._nextClaimIn = DAY_SECONDS
			self._claimedToday = false
			self._day = math.min(self._day + 1, #self._days)
			label.Text = UIChrome.FormatCountdown(self._nextClaimIn)
			self:_RenderGrid()
		end
	end)
end

function DailyRewardsScreen:_StopTicker()
	if self._tickConn then
		self._tickConn:Disconnect()
		self._tickConn = nil
	end
	self:_GPStopTicker()
end

function DailyRewardsScreen:_Claim()
	if self._claimedToday then
		self:_Toast(
			if self:LayoutKit() == "GP"
				then "Already claimed — come back tomorrow!"
				else "ALREADY CLAIMED — COME BACK TOMORROW",
			"Info"
		)
		return
	end
	local entry = self._days[self._day]
	if not entry then
		return
	end
	entry.claimed = true
	self._claimedToday = true
	-- Pack law 5 (no all-caps copy) applies to the toast this screen raises as
	-- much as to the labels it builds, so the shout is layout-scoped.
	if self:LayoutKit() == "GP" then
		self:_Toast(string.format("Day %d claimed — %s is yours!", entry.day, entry.label or tostring(entry.amount or "")), "Success")
	else
		self:_Toast(string.format("CLAIMED DAY %d  ·  %s", entry.day, tostring(entry.amount or "")), "Success")
	end
	self:_RenderGrid()
end

-- ========================================================================
-- Lifecycle
-- ========================================================================

function DailyRewardsScreen:_BuildContent()
	-- GL layout language: comic diagonal composition (slanted banner Page,
	-- staggered cut-silhouette cells, gold stamps) — see _BuildGLLayout below.
	if self:LayoutKit() == "GL" then
		self:_BuildGLLayout()
		return
	end
	-- GP layout language: the pastel login calendar with the live lobby's full
	-- daily surface (free reward + the two paid actions) — see _BuildGPLayout.
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end

	local theme = self:GetTheme()

	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = "DAILY REWARDS",
		sizePx = CARD,
		onClose = function()
			self.ScreenController:HideScreen("dailyRewards")
		end,
	})
	self._modal = modal

	self:_BuildHeader(theme, modal.content)
	self:_BuildGrid(theme, modal.content)
	self:_RenderGrid()
end

function DailyRewardsScreen:_OnShow(data: any?)
	self:_Ingest(data)
	if self._built then
		self._countdown.Text = UIChrome.FormatCountdown(self._nextClaimIn)
		self:_RenderGrid()
	end
	self:_StartTicker()
	if self._modal then
		UIChrome.PopIn(self:GetTheme(), self._modal.content)
	end
end

function DailyRewardsScreen:_OnHide()
	self:_StopTicker()
	self:_StopBreath()
end

function DailyRewardsScreen:Update(data: any)
	self:_Ingest(data)
	if self._built then
		self._countdown.Text = UIChrome.FormatCountdown(self._nextClaimIn)
		self:_RenderGrid()
	end
end

function DailyRewardsScreen:Destroy()
	self:_OnHide()
	if self._claimBtn then
		self._claimBtn:Destroy()
		self._claimBtn = nil
	end
	UIScreenBase.Destroy(self)
end

-- ======================================================================
-- GL layout (theme.LayoutKit == "GL") — the comic diagonal login ladder,
-- composed from GLLayoutKit so it is the same parts as the APPROVED shop
-- page: slanted banner Page, a staggered field of chamfered Cards, ink/gold
-- PriceChips for the reward value, tilted Badges that overhang their cell.
--
-- Cell states, all repainted IN PLACE:
--   claimed    — a gold stampBurst slapped across the cell at ~-8° with a
--                cream CLAIMED shout (the pack's "stamped and done")
--   claimable  — a gold TODAY badge breaking the corner + the kit CLAIM
--                ActionButton hanging off the bottom edge, wired to the
--                EXISTING _Claim callback
--   future     — art + numerals dim to Colors.Disabled, never removed
--
-- Presentation only: the same _days ladder, the same _Claim/_Toast flow,
-- the same 1Hz ticker (which drives self._countdown — built here too, so
-- every shared lifecycle method keeps working verbatim).
-- ======================================================================

local GL_PAGE = Vector2.new(1240, 800)
local GL_CELLS = 10
local GL_COLS = 5
local GL_GAP = 18
local GL_CELL_W = 224
local GL_CELL_H = 236
local GL_ROW_PITCH = 268
local GL_STAMP_TILT = GLLayoutKit.TILT * 3.2 -- ~-8°, still on the one axis

function DailyRewardsScreen:_BuildGLLayout()
	local theme = self:GetTheme()

	-- Classic leftovers must not leak into the comic page.
	if self._claimBtn then
		self._claimBtn:Destroy()
		self._claimBtn = nil
	end
	self:_StopBreath()
	self._grid = nil
	self._streakLabel = nil
	self._progressLabel = nil

	self._glShadows = {}
	self._glCells = {} :: { any }

	local page = GLLayoutKit.Page(theme, self.Root, {
		titleText = "DAILY REWARDS",
		sizePx = GL_PAGE,
		onClose = function()
			self.ScreenController:HideScreen("dailyRewards")
		end,
	})
	for _, handle in page.shadows do
		table.insert(self._glShadows, handle)
	end
	-- _OnShow pops the panel through the shared modal contract; the GL page
	-- has no separate card/content split, so both point at the plate.
	self._modal = { card = page.panel, content = page.panel }

	-- Countdown chip in the page's top-right slot. self._countdown is the
	-- field _StartTicker / _OnShow / Update already drive, so the 1Hz reset
	-- ticker needs no branch of its own.
	local caption = GLLayoutKit.BodyText(theme, 14, theme.Colors.TextSecondary, "NextIn")
	caption.Text = "NEXT DAY IN"
	caption.TextXAlignment = Enum.TextXAlignment.Right
	caption.Size = UDim2.fromOffset(120, 40)
	caption.LayoutOrder = 1
	caption.Parent = page.topRight

	local clock = GLLayoutKit.Slice(theme, "chipPaper", theme.Arcade.NearBlack, "Clock")
	clock.Size = UDim2.fromOffset(190, 42)
	clock.Rotation = -GLLayoutKit.TILT
	clock.LayoutOrder = 2
	clock.Parent = page.topRight
	GLLayoutKit.Shadow(theme, clock, "sm", self._glShadows)
	local countdown = GLLayoutKit.Text(theme, 26, theme.Arcade.Gold, "Countdown")
	countdown.Text = UIChrome.FormatCountdown(self._nextClaimIn)
	countdown.Size = UDim2.fromScale(1, 1)
	countdown.ZIndex = 2
	countdown.Parent = clock
	self._countdown = countdown

	-- Streak shout, tilted with the axis so the header reads as a slam.
	local streak = GLLayoutKit.Text(theme, 34, theme.Arcade.Gold, "Streak")
	streak.TextXAlignment = Enum.TextXAlignment.Left
	streak.Position = UDim2.fromOffset(4, 0)
	streak.Size = UDim2.fromOffset(620, 44)
	streak.Rotation = GLLayoutKit.TILT
	streak.Parent = page.content
	self._glStreak = streak

	local progress = GLLayoutKit.BodyText(theme, 16, theme.Colors.TextSecondary, "Progress")
	progress.TextXAlignment = Enum.TextXAlignment.Left
	progress.Position = UDim2.fromOffset(6, 46)
	progress.Size = UDim2.fromOffset(620, 22)
	progress.Parent = page.content
	-- Was missing while its sibling `self._glStreak` above was assigned: the
	-- _GLRefresh at the end of this very function writes `self._glProgress.Text`,
	-- so the GL calendar crashed on nil the moment it was built.
	self._glProgress = progress

	GLLayoutKit.Divider(theme, page.content).Position = UDim2.fromOffset(0, 74)

	local field = Instance.new("ScrollingFrame")
	field.Name = "Ladder"
	field.BackgroundTransparency = 1
	field.BorderSizePixel = 0
	field.Position = UDim2.fromOffset(0, 96)
	field.Size = UDim2.new(1, 0, 1, -96)
	field.CanvasSize = UDim2.new()
	field.AutomaticCanvasSize = Enum.AutomaticSize.Y
	field.ScrollBarThickness = 6
	field.ScrollBarImageColor3 = theme.Arcade.Gold
	field.ScrollingDirection = Enum.ScrollingDirection.Y
	field.ClipsDescendants = true -- MUST clip: unclipped cells spill past the
	-- frame (padding gives stamp/badge overhang room inside the viewport)
	field.Parent = page.content
	self._glField = field

	-- The cell count is FIXED, so the field is built once and every render is
	-- a repaint (the pooling law, in its simplest honest form).
	for slot = 1, GL_CELLS do
		table.insert(self._glCells, self:_GLBuildCell(slot))
	end

	self:_GLRefresh()
end

function DailyRewardsScreen:_GLBuildCell(slot: number): any
	local theme = self:GetTheme()
	local cell: any = {}
	local card = GLLayoutKit.Card(theme, self._glField, self._glShadows)
	cell.root = card.root
	cell.body = card.body
	cell.art = card.art
	cell.artLabel = card.artLabel
	cell.day = card.name
	cell.shadow = card.shadow

	local col = (slot - 1) % GL_COLS
	local row = (slot - 1) // GL_COLS
	-- The DIAGONAL AXIS: each column steps down, so a row reads as a
	-- descending slash rather than a ruled shelf, and the plate tilt
	-- alternates against it.
	card.root.Position = UDim2.fromOffset(col * (GL_CELL_W + GL_GAP), row * GL_ROW_PITCH + col * 14)
	card.root.Size = UDim2.fromOffset(GL_CELL_W, GL_CELL_H)
	card.root.LayoutOrder = slot
	card.body.Rotation = (col % 2 == 0) and GLLayoutKit.TILT or -GLLayoutKit.TILT * 0.8

	card.name.Position = UDim2.fromOffset(14, 8)
	card.name.Size = UDim2.new(1, -28, 0, 26)
	card.name.TextSize = 22
	card.art.Position = UDim2.new(0.5, 0, 0, 42)
	card.art.Size = UDim2.new(1, -28, 0, 108)

	cell.price = GLLayoutKit.PriceChip(theme, card.body, self._glShadows)
	-- No currency glyph on a login reward (the ladder is not priced in one
	-- currency), so the numerals take the whole plate.
	cell.price.icon.Visible = false
	cell.price.amount.Position = UDim2.fromOffset(12, 0)
	cell.price.amount.Size = UDim2.new(1, -24, 1, 0)
	cell.price.amount.TextXAlignment = Enum.TextXAlignment.Center

	local badgeSink = {}
	local badge, badgeText = GLLayoutKit.Badge(theme, card.body, "", theme.Arcade.Gold, badgeSink)
	-- Overhang the top-RIGHT corner instead: the top-left is the day line.
	badge.Position = UDim2.new(1, -82, 0, -12)
	cell.badge = badge
	cell.badgeText = badgeText
	cell.badgeShadow = badgeSink[1]
	table.insert(self._glShadows, badgeSink[1])

	local claimSink = {}
	local claim = GLLayoutKit.ActionButton(theme, card.body, "CLAIM", function()
		self:_Claim()
	end, claimSink)
	-- Breaks the cell's bottom edge on purpose (nothing stays in its box).
	claim.Size = UDim2.fromOffset(180, 46)
	claim.Position = UDim2.new(0.5, -90, 1, -26)
	claim.Visible = false
	cell.claim = claim
	cell.claimPlate = claim:FindFirstChild("Plate") :: ImageLabel
	cell.claimLabel = claim:FindFirstChild("Label") :: TextLabel
	cell.claimShadow = claimSink[1]
	table.insert(self._glShadows, claimSink[1])

	-- The CLAIMED stamp: a gold burst slapped across the cell, off-axis by a
	-- multiple of the pack tilt, with a cream shout riding it.
	local stamp = GLLayoutKit.Slice(theme, "stampBurst", theme.Arcade.Gold, "Stamp")
	stamp.AnchorPoint = Vector2.new(0.5, 0.5)
	stamp.Position = UDim2.fromScale(0.5, 0.52)
	stamp.Size = UDim2.fromOffset(168, 168)
	stamp.Rotation = GL_STAMP_TILT
	stamp.Visible = false
	stamp.ZIndex = 6
	stamp.Parent = card.body
	cell.stamp = stamp

	local stampText = GLLayoutKit.Text(theme, 24, theme.Colors.TextPrimary, "Stamped")
	stampText.Text = "CLAIMED"
	stampText.Size = UDim2.fromScale(1, 1)
	stampText.ZIndex = 7
	stampText.Parent = stamp
	cell.stampText = stampText

	return cell
end

-- Repaint the staggered ladder from the CURRENT ladder data. This is the GL
-- answer to _RenderGrid — see the dispatch at the top of that function.
function DailyRewardsScreen:_GLRefresh()
	local cells = self._glCells
	if not cells then
		return -- built under another layout; the next Show rebuilds
	end
	local theme = self:GetTheme()
	local days = self._days
	local total = #days

	local claimedCount = 0
	for _, entry in days do
		if entry.claimed then
			claimedCount += 1
		end
	end
	self._glStreak.Text = string.format("DAY %d STREAK", self._day)
	self._glProgress.Text = string.format("%d / %d CLAIMED", claimedCount, total)

	-- A fixed 10-cell field over a longer ladder: the window always carries
	-- the live day, so the claimable cell is never off the page.
	local first = math.clamp(self._day - 4, 1, math.max(1, total - GL_CELLS + 1))

	for slot, cell in cells do
		local entry = days[first + slot - 1]
		if not entry then
			cell.root.Visible = false
			cell.shadow:SetEnabled(false)
			cell.price.shadow:SetEnabled(false)
			cell.badgeShadow:SetEnabled(false)
			cell.claimShadow:SetEnabled(false)
			continue
		end

		local claimed = entry.claimed == true
		local isToday = entry.day == self._day and not claimed
		local future = entry.day > self._day
		local dim = (claimed or future) and theme.Colors.Disabled or theme.Colors.TextPrimary

		cell.root.Visible = true
		cell.shadow:SetEnabled(true)
		cell.price.shadow:SetEnabled(true)

		cell.day.Text = "DAY " .. tostring(entry.day)
		cell.day.TextColor3 = dim
		cell.art.ImageColor3 = future and theme.Colors.Disabled or theme.Colors.TextSecondary
		cell.artLabel.TextColor3 = dim

		cell.price.root.Size = UDim2.fromOffset(150, 38)
		cell.price.root.Position = isToday and UDim2.new(0.5, -75, 1, -84) or UDim2.new(0.5, -75, 1, -52)
		cell.price.root.ImageColor3 = theme.Arcade.NearBlack
		cell.price.amount.Text = tostring(entry.amount or "")
		cell.price.amount.TextColor3 = (claimed or future) and theme.Colors.Disabled or theme.Arcade.Gold
		cell.price.shadow:SetEnabled(true)

		-- The stamp is the claimed state; nothing else needs to say it.
		cell.stamp.Visible = claimed

		if isToday then
			cell.claim.Visible = true
			cell.claimShadow:SetEnabled(true)
			cell.claimLabel.Text = self._claimedToday and "CLAIMED" or "CLAIM"
			cell.claimPlate.ImageColor3 = self._claimedToday and theme.Colors.Disabled or theme.Colors.Primary
		else
			cell.claim.Visible = false
			cell.claimShadow:SetEnabled(false)
		end

		if isToday then
			cell.badge.Visible = true
			cell.badge.ImageColor3 = theme.Arcade.Gold
			cell.badgeText.Text = "TODAY"
			cell.badgeText.TextColor3 = theme.Colors.TextPrimary
			cell.badgeShadow:SetEnabled(true)
		elseif entry.milestone and not claimed then
			cell.badge.Visible = true
			cell.badge.ImageColor3 = theme.Arcade.Red
			cell.badgeText.Text = "MILESTONE"
			cell.badgeText.TextColor3 = theme.Colors.TextPrimary
			cell.badgeShadow:SetEnabled(true)
		else
			cell.badge.Visible = false
			cell.badgeShadow:SetEnabled(false)
		end
	end
end

-- ======================================================================
-- GP layout (theme.LayoutKit == "GP") — GIRLY POP: the pastel login
-- calendar, composed from GPLayoutKit (cream Page, petal cells alternating
-- across the grid, butter value pills, hue-matched shadows).
--
-- WHAT THIS BRANCH ADDS THAT THE COLLECTION SCREEN NEVER HAD. The live
-- lobby's daily surface is three panels, not one, and the arcade/GL builds
-- only ever carried the calendar. All of it lands here:
--   * SKIP DAY — the paid "take tomorrow now" action, with the shipped
--     three-way gate: restricted accounts refused fail-closed, ONE paid
--     action per day, and today's FREE claim must be spent first (never
--     sell someone the freebie they already have);
--   * CLAIM ALL — the paid "take the rest of the ladder" action, same
--     restricted/once-a-day gate, answering when there is nothing left;
--   * FREE REWARD — the group-join panel: three reward items, the
--     CLAIM → CLAIMED! button with its check riding inside, and the real
--     note copy for every branch (member, already claimed, join first);
--   * the claim button's CLAIMED! state and its inline check icon;
--   * the reward LABEL under every day ("Random limited chair"), which the
--     shipped ladder prints and the collection had dropped to a bare number.
--
-- THE UPGRADES over both:
--   * STICKER STAMP — claiming slams a rounded "Claimed!" sticker onto the
--     cell (fast scale-down, then the pack's capped overshoot). CLAIM ALL
--     cascades them a frame apart. Nothing rotates: a rotated descendant is
--     not clipped by the scrolling calendar, and this pack's angle comes
--     from petal silhouettes anyway.
--   * NEXT-CLAIMABLE GLOW — a single zero-offset butter aura, REPARENTED
--     onto whichever cell is claimable. One UIShadow, not twenty-eight.
--   * ONE 1Hz TICKER — a single UITicker handler drives the header
--     countdown AND the paid-reset hint. No per-label loops, no
--     screen-owned RunService connection.
--
-- SHADOW BUDGET (StyleKit.Capabilities warns past 80 live UIShadows): the
-- 28 calendar cells are deliberately shadow-FREE — GPLayoutKit.StatRow
-- documents the same call for the same reason — so depth in the grid comes
-- from the petal silhouette, the deepened-tint stroke and a blush fill that
-- sits off the cream page. The page, the band, the rail cards and the
-- buttons carry the pack's shadows, and the calendar carries the one glow.
-- ======================================================================

local GP_PAGE = Vector2.new(1330, 830)
local GP_GRID_W = 940
local GP_RAIL_X = GP_GRID_W + 18
local GP_RAIL_W = 344
local GP_BAND_H = 78
local GP_BODY_Y = GP_BAND_H + 10
local GP_BODY_H = 606
local GP_COLUMNS = 7
local GP_CELL_W = 118
local GP_CELL_H = 152
local GP_CELL_PAD = 13
local GP_STAMP = Vector2.new(108, 36)
local GP_CASCADE = 0.05 -- per-cell delay when CLAIM ALL stamps the ladder

-- Copy lives in one table per panel, never inline in the build (the same rule
-- the ladder above follows). Sentence case throughout: pack law 5 forbids
-- all-caps copy, so the shipped "CLAIMED!" / "SKIP DAY" shouts are carried as
-- features, not as capitals.
local GP_FREE = {
	title = "Free reward",
	subtitle = "Join the group to claim!",
	joinNote = "Join in the popup — the reward claims itself!",
	joinToast = "Join the group first, then claim!",
	grantedNote = "+$2,500 Cash, +120 Bux & a free chair!",
	claimedNote = "You already own this reward!",
}

-- The three cards the shipped panel shows: the exclusive chair (tagged), the
-- Cash grant and the Bux grant. Typed, so the optional tag is optional.
type GPFreeItem = { icon: string, label: string, tag: string? }
local GP_FREE_ITEMS: { GPFreeItem } = {
	{ icon = "chest", label = "Exclusive chair", tag = "Exclusive!" },
	{ icon = "cash", label = "$2,500 Cash" },
	{ icon = "bux", label = "120 Bux" },
}

-- The paid-daily refusals, verbatim from the shipped panel.
local GP_PAID = {
	section = "Skip ahead",
	restricted = "Not available on your account.",
	spent = "You've already used a paid daily reward today!",
	needFree = "Claim today's free reward first!",
	nothingLeft = "Nothing left to claim on this ladder!",
	hint = "One paid reward a day · resets in %s",
}

local GP_CELL_CLAIM = "Tap to claim!"
-- Identity tint for the archive's FULL-COLOUR art. Not a painted surface —
-- pack law 1 bans white as a fill, and this never becomes one.
local GP_ART_IDENTITY = Color3.new(1, 1, 1)

type GPButton = {
	root: TextButton,
	shape: Frame,
	label: TextLabel,
	check: ImageLabel,
	stroke: UIStroke,
	shadow: any,
	SetTone: (Color3) -> (),
}

-- Always-painted frame: UIStyler.Frame is born pure white, which this pack
-- forbids outright (GPLayoutKit keeps the same private helper for the same
-- reason).
local function gpSurface(name: string, fill: Color3, transparency: number?): Frame
	local frame = UIStyler.Frame(name)
	frame.BackgroundColor3 = fill
	frame.BackgroundTransparency = transparency or 0
	return frame
end

-- Archive art WITHOUT IconArchive.Image's glyph fallback: that fallback emits
-- pure-white text with a pure-black stroke, which is two law-1 violations on a
-- pastel page. A missing id leaves an empty (invisible) slot instead.
local function gpIcon(parent: Instance, key: string, sizePx: number): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Name = "Icon_" .. key
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Fit
	image.Size = UDim2.fromOffset(sizePx, sizePx)
	local id = IconArchive.Id(key)
	image.Image = id or ""
	image.Parent = parent
	IconVisibility.Register(image)
	return image
end

-- Compact butter value pill. GPLayoutKit.PricePill is the kit's version and is
-- used in the rail; a calendar cell is 118px wide (the pill's own width is 132)
-- and 28 of them would each carry a shadow, so the grid gets this flat twin.
local function gpValueChip(theme: Types.UITheme, parent: Instance): { root: Frame, amount: TextLabel, stroke: UIStroke }
	local fill = theme.Arcade.Gold
	local chip = gpSurface("Value", fill, 0)
	chip.Size = UDim2.fromOffset(98, 24)
	chip.ZIndex = 4
	chip.Parent = parent
	UIStyler.Corner(theme.Radii.Pill).Parent = chip
	local stroke = GPLayoutKit.SoftStroke(theme, chip)

	-- Numerals are TextPrimary: butter is a LIGHT fill and TextOnPrimary
	-- (near-white) would vanish on it — the kit's PricePill makes the same call.
	local amount = GPLayoutKit.NumberText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "Amount")
	amount.TextXAlignment = Enum.TextXAlignment.Center
	amount.Size = UDim2.fromScale(1, 1)
	amount.ZIndex = 5
	amount.Parent = chip
	return { root = chip, amount = amount, stroke = stroke }
end

-- The pack has no button builder (GPLayoutKit is composition primitives), so
-- one lives here: transparent hit target + painted petal chip, a deepened
-- stroke, a hue-matched shadow, and SetTone retinting all three together so a
-- state change can never leave a rose shadow under a grey button.
local function gpButton(theme: Types.UITheme, parent: Instance, opts: {
	text: string,
	fill: Color3,
	sizePx: Vector2,
	index: number?,
	iconKey: string?,
	onClick: () -> (),
}, sink: { any }?): GPButton
	local root = Instance.new("TextButton")
	root.Name = "GPButton"
	-- Transparent: UIStyleEnforcer backstops a SOLID GuiButton with a black 2px
	-- stroke, which would violate law 1 on sight (see GPLayoutKit.Page).
	root.BackgroundTransparency = 1
	root.Text = ""
	root.AutoButtonColor = false
	root.Size = UDim2.fromOffset(opts.sizePx.X, opts.sizePx.Y)
	root.ZIndex = 4
	root.Parent = parent

	local shape = gpSurface("Shape", opts.fill, 0)
	shape.Size = UDim2.fromScale(1, 1)
	shape.ZIndex = 4
	shape.Parent = root
	GPLayoutKit.Petal(theme, shape, opts.index or 0)
	local stroke = GPLayoutKit.SoftStroke(theme, shape)
	local shadow = GPLayoutKit.Shadow(theme, shape, "sm", sink)

	local label = GPLayoutKit.Text(theme, theme.TextSizes.Button, theme.Colors.TextPrimary, "Label")
	label.Text = opts.text
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 5
	label.Parent = shape

	if opts.iconKey then
		local glyph = gpIcon(shape, opts.iconKey, 22)
		glyph.AnchorPoint = Vector2.new(0, 0.5)
		glyph.Position = UDim2.new(0, 12, 0.5, 0)
		glyph.ZIndex = 6
	end

	-- The claimed-state check rides INSIDE the button, as the shipped panel's
	-- claimCheck does.
	local check = gpIcon(shape, "check", 22)
	check.AnchorPoint = Vector2.new(1, 0.5)
	check.Position = UDim2.new(1, -12, 0.5, 0)
	check.ZIndex = 6
	check.Visible = false

	root.Activated:Connect(opts.onClick)
	UIChrome.Animate(theme, root, shape)

	local function setTone(fill: Color3)
		shape.BackgroundColor3 = fill
		local deep = GPLayoutKit.Deepen(theme, fill, 1)
		stroke.Color = deep
		shadow.Instance.Color = deep
	end

	return { root = root, shape = shape, label = label, check = check, stroke = stroke, shadow = shadow, SetTone = setTone }
end

function DailyRewardsScreen:_BuildGPLayout()
	local theme = self:GetTheme()

	-- Classic/GL leftovers must not leak into the pastel page.
	if self._claimBtn then
		self._claimBtn:Destroy()
		self._claimBtn = nil
	end
	self:_StopBreath()
	self._grid = nil
	self._streakLabel = nil
	self._progressLabel = nil
	self._glCells = nil
	self._glField = nil

	self._gpCells = {} :: { any }
	self._gpStamped = {} :: { [number]: boolean }
	self._gpPrimed = false

	local page = GPLayoutKit.Page(theme, self.Root, {
		titleText = "Daily rewards",
		subtitleText = "A gift a day — miss one and the streak starts over.",
		sizePx = GP_PAGE,
		onClose = function()
			self.ScreenController:HideScreen("dailyRewards")
		end,
	})
	-- The Page's own sink becomes the screen's shadow list; every later kit
	-- call feeds the same list (the GL precedent).
	self._gpShadows = page.shadows
	-- _OnShow pops self._modal.content in every layout; the GP page has no
	-- separate card/content split, so both point at the cream plate.
	self._modal = { card = page.panel, content = page.panel }
	local content = page.content

	-- The countdown rides the ribbon's right slot. self._countdown is the field
	-- _OnShow / Update / the ticker already drive, so nothing else needs a
	-- branch of its own.
	local caption = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "NextIn")
	caption.Text = "Next day in"
	caption.TextXAlignment = Enum.TextXAlignment.Right
	caption.Size = UDim2.fromOffset(130, 40)
	caption.LayoutOrder = 1
	caption.Parent = page.topRight

	local clock = GPLayoutKit.PricePill(theme, page.topRight, self._gpShadows)
	clock.root.Size = UDim2.fromOffset(152, 40)
	clock.root.LayoutOrder = 2
	local clockId = IconArchive.Id("clock")
	clock.icon.Image = clockId or ""
	clock.amount.TextXAlignment = Enum.TextXAlignment.Center
	clock.amount.Text = UIChrome.FormatCountdown(self._nextClaimIn)
	self._countdown = clock.amount

	self:_GPBuildBand(theme, content)
	self:_GPBuildGrid(theme, content)
	self:_GPBuildRail(theme, content)

	-- ONE aura for the whole calendar, parked on a zero-size host and
	-- REPARENTED onto the claimable cell (28 per-cell glows would be a third of
	-- the shadow budget for a thing only one cell can ever wear).
	local glowHome = gpSurface("GlowHome", theme.Colors.Accent, 1)
	glowHome.Size = UDim2.fromOffset(0, 0)
	glowHome.ZIndex = 3
	glowHome.Parent = content
	self._gpGlowHome = glowHome
	self._gpGlow = GPLayoutKit.Glow(theme, glowHome, theme.Colors.Accent, self._gpShadows)
	self._gpGlow:SetEnabled(false)

	self:_GPRefresh()
end

-- The streak band: fire, the streak shout, the ladder line and a magnitude bar.
function DailyRewardsScreen:_GPBuildBand(theme: Types.UITheme, content: Frame)
	local fill = theme.Colors.SurfaceRaised
	local band = gpSurface("StreakBand", fill, 0)
	band.Size = UDim2.new(1, 0, 0, GP_BAND_H)
	band.ZIndex = 3
	band.Parent = content
	GPLayoutKit.Petal(theme, band, 0)
	GPLayoutKit.SoftStroke(theme, band)
	GPLayoutKit.Shadow(theme, band, "sm", self._gpShadows, fill)

	local fire = gpIcon(band, "fire", 42)
	fire.AnchorPoint = Vector2.new(0, 0.5)
	fire.Position = UDim2.new(0, 16, 0.5, 0)
	fire.ZIndex = 4

	local streak = GPLayoutKit.Text(theme, 28, theme.Colors.TextPrimary, "Streak")
	streak.TextXAlignment = Enum.TextXAlignment.Left
	streak.Position = UDim2.fromOffset(70, 8)
	streak.Size = UDim2.fromOffset(430, 34)
	streak.ZIndex = 4
	streak.Parent = band
	self._gpStreak = streak

	local progress = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Progress")
	progress.TextXAlignment = Enum.TextXAlignment.Left
	progress.Position = UDim2.fromOffset(72, 42)
	progress.Size = UDim2.fromOffset(520, 24)
	progress.ZIndex = 4
	progress.Parent = band
	self._gpProgress = progress

	local count = GPLayoutKit.NumberText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "Count")
	count.AnchorPoint = Vector2.new(1, 0)
	count.Position = UDim2.new(1, -18, 0, 12)
	count.Size = UDim2.fromOffset(300, 22)
	count.ZIndex = 4
	count.Parent = band
	self._gpCount = count

	local track = gpSurface("Track", theme.Arcade.RulerTrack, 0)
	track.AnchorPoint = Vector2.new(1, 0)
	track.Position = UDim2.new(1, -18, 0, 44)
	track.Size = UDim2.fromOffset(300, 12)
	track.ZIndex = 4
	track.Parent = band
	UIStyler.Corner(theme.Radii.Pill).Parent = track

	local fillBar = gpSurface("Fill", theme.Colors.Primary, 0)
	fillBar.Size = UDim2.fromScale(0, 1)
	fillBar.ZIndex = 5
	fillBar.Parent = track
	UIStyler.Corner(theme.Radii.Pill).Parent = fillBar
	self._gpBar = fillBar
end

function DailyRewardsScreen:_GPBuildGrid(theme: Types.UITheme, content: Frame)
	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Calendar"
	grid.BackgroundColor3 = theme.Colors.Background
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.Position = UDim2.fromOffset(0, GP_BODY_Y)
	grid.Size = UDim2.fromOffset(GP_GRID_W, GP_BODY_H)
	grid.CanvasSize = UDim2.new()
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.ScrollBarThickness = 8
	grid.ScrollBarImageColor3 = theme.Colors.Primary
	-- MUST clip (the pack law): the padding below keeps the glow's bloom and a
	-- mid-slam sticker off the cut edge instead of slicing them.
	grid.ClipsDescendants = true
	grid.ZIndex = 3
	grid.Parent = content

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 18)
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = grid

	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(GP_CELL_W, GP_CELL_H)
	layout.CellPadding = UDim2.fromOffset(GP_CELL_PAD, GP_CELL_PAD)
	layout.FillDirectionMaxCells = GP_COLUMNS
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Parent = grid

	self._gpGrid = grid
end

-- One pooled calendar cell. Built once per ladder position and repainted for
-- ever after — the petal parity comes from the POSITION, so a cell keeps
-- agreeing with its neighbours no matter what data lands in it.
function DailyRewardsScreen:_GPCell(index: number): any
	local existing = self._gpCells[index]
	if existing then
		return existing
	end
	local theme = self:GetTheme()

	local root = Instance.new("TextButton")
	root.Name = "GPDay" .. index
	root.BackgroundTransparency = 1
	root.Text = ""
	root.AutoButtonColor = false
	root.LayoutOrder = index
	root.ZIndex = 3
	root.Parent = self._gpGrid

	local bodyFill = theme.Colors.Surface
	local body = gpSurface("Body", bodyFill, 0)
	body.Size = UDim2.fromScale(1, 1)
	body.ZIndex = 3
	body.Parent = root
	GPLayoutKit.Petal(theme, body, index)
	local stroke = GPLayoutKit.SoftStroke(theme, body)

	local dayLabel = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "Day")
	dayLabel.Text = "Day " .. index
	dayLabel.Position = UDim2.fromOffset(0, 6)
	dayLabel.Size = UDim2.new(1, 0, 0, 20)
	dayLabel.ZIndex = 4
	dayLabel.Parent = body

	-- THE HIGH-VALUE RUNG MARK. The shipped panel rings days 6-7 apart from the
	-- rest of the ladder, and both sibling layouts badge a milestone (the classic
	-- "MILESTONE" strip, the GL stamp); the calendar must not be the one surface
	-- that hides where the chairs are. Butter is this pack's value colour, and
	-- the crest is doubled by the cell's ring below so the mark survives the
	-- global icon toggle.
	local crest = gpIcon(body, "star", 16)
	crest.AnchorPoint = Vector2.new(1, 0)
	crest.Position = UDim2.new(1, -6, 0, 8)
	crest.ZIndex = 5
	crest.Visible = false

	local art = gpIcon(body, "gift", 44)
	art.AnchorPoint = Vector2.new(0.5, 0)
	art.Position = UDim2.new(0.5, 0, 0, 28)
	art.ZIndex = 4

	local chip = gpValueChip(theme, body)
	chip.root.AnchorPoint = Vector2.new(0.5, 0)
	chip.root.Position = UDim2.new(0.5, 0, 0, 78)

	local note = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Note")
	note.TextWrapped = true
	note.Position = UDim2.fromOffset(6, 106)
	note.Size = UDim2.new(1, -12, 0, 40)
	note.ZIndex = 4
	note.Parent = body

	-- The sticker. A GROUP holds the burst and the pill as SIBLINGS: a child
	-- always draws over its parent under ZIndexBehavior.Sibling, so a burst
	-- parented to the pill would cover it however the ZIndexes read. The one
	-- UIScale lives on the group, so burst and pill slam together.
	local group = gpSurface("Stamp", theme.Colors.Primary, 1)
	group.AnchorPoint = Vector2.new(0.5, 0.5)
	group.Position = UDim2.fromScale(0.5, 0.54)
	group.Size = UDim2.fromOffset(GP_STAMP.X, GP_STAMP.Y)
	group.Visible = false
	group.ZIndex = 6
	group.Parent = body

	local stampScale = Instance.new("UIScale")
	stampScale.Parent = group

	local burst = GPLayoutKit.Slice(theme, "sunburstSoft", theme.Colors.Accent, "StampBurst")
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.Position = UDim2.fromScale(0.5, 0.5)
	burst.Size = UDim2.fromOffset(GP_STAMP.X + 40, GP_STAMP.X + 40)
	burst.ImageTransparency = 0.3
	burst.ZIndex = 6
	burst.Parent = group

	-- Rose pill, ink copy: TextPrimary on rose measures 5.15:1, and the
	-- near-white TextOnPrimary (2.14:1) is display-only — never a label.
	local stampFill = theme.Colors.Primary
	local pill = gpSurface("Pill", stampFill, 0)
	pill.AnchorPoint = Vector2.new(0.5, 0.5)
	pill.Position = UDim2.fromScale(0.5, 0.5)
	pill.Size = UDim2.fromScale(1, 1)
	pill.ZIndex = 7
	pill.Parent = group
	UIStyler.Corner(theme.Radii.Pill).Parent = pill
	GPLayoutKit.SoftStroke(theme, pill)

	local stampCheck = gpIcon(pill, "check", 16)
	stampCheck.AnchorPoint = Vector2.new(0, 0.5)
	stampCheck.Position = UDim2.new(0, 8, 0.5, 0)
	stampCheck.ZIndex = 8

	local stampText = GPLayoutKit.Text(theme, 15, theme.Colors.TextPrimary, "Stamped")
	stampText.Text = "Claimed!"
	stampText.Position = UDim2.fromOffset(26, 0)
	stampText.Size = UDim2.new(1, -32, 1, 0)
	stampText.ZIndex = 8
	stampText.Parent = pill

	UIChrome.Animate(theme, root, body)
	local cell: any = {
		root = root,
		body = body,
		stroke = stroke,
		day = dayLabel,
		crest = crest,
		art = art,
		chip = chip,
		note = note,
		stamp = group,
		stampScale = stampScale,
		slam = nil :: Tween?,
		settle = nil :: Tween?,
	}
	cell.click = root.Activated:Connect(function()
		self:_GPCellPressed(index)
	end)
	self._gpCells[index] = cell
	return cell
end

-- The right rail: the free-reward panel over the two paid actions over the
-- primary claim. Every button is the local gpButton, so state changes retint
-- fill + stroke + shadow together.
function DailyRewardsScreen:_GPBuildRail(theme: Types.UITheme, content: Frame)
	local rail = gpSurface("Rail", theme.Colors.Background, 1)
	rail.Position = UDim2.fromOffset(GP_RAIL_X, GP_BODY_Y)
	rail.Size = UDim2.fromOffset(GP_RAIL_W, GP_BODY_H)
	rail.ZIndex = 3
	rail.Parent = content

	-- ---- free reward -------------------------------------------------
	local cardFill = theme.Colors.SurfaceRaised
	local card = gpSurface("FreeReward", cardFill, 0)
	card.Size = UDim2.fromOffset(GP_RAIL_W, 292)
	card.ZIndex = 3
	card.Parent = rail
	GPLayoutKit.Petal(theme, card, 1)
	GPLayoutKit.SoftStroke(theme, card)
	GPLayoutKit.Shadow(theme, card, "md", self._gpShadows, cardFill)

	local title = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle + 2, theme.Colors.TextPrimary, "FreeTitle")
	title.Text = GP_FREE.title
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(16, 12)
	title.Size = UDim2.new(1, -32, 0, 28)
	title.ZIndex = 4
	title.Parent = card

	local subtitle = GPLayoutKit.BodyText(theme, theme.TextSizes.Small + 1, theme.Colors.TextSecondary, "FreeSub")
	subtitle.Text = GP_FREE.subtitle
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Position = UDim2.fromOffset(16, 42)
	subtitle.Size = UDim2.new(1, -32, 0, 22)
	subtitle.ZIndex = 4
	subtitle.Parent = card

	for index, item in GP_FREE_ITEMS do
		local row = gpSurface("FreeItem" .. index, theme.Colors.Surface, 0)
		row.Position = UDim2.fromOffset(14, 68 + (index - 1) * 46)
		row.Size = UDim2.fromOffset(GP_RAIL_W - 28, 42)
		row.ZIndex = 4
		row.Parent = card
		GPLayoutKit.Petal(theme, row, index)
		GPLayoutKit.SoftStroke(theme, row)

		local icon = gpIcon(row, item.icon, 28)
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 10, 0.5, 0)
		icon.ZIndex = 5

		local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "Label")
		label.Text = item.label
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Position = UDim2.fromOffset(48, 0)
		label.Size = UDim2.new(1, -140, 1, 0)
		label.ZIndex = 5
		label.Parent = row

		if item.tag then
			-- The shipped panel tilts this tag -12°; nothing tilts in this pack,
			-- so the emphasis is carried by the butter fill instead.
			local tag = gpSurface("Tag", theme.Arcade.Gold, 0)
			tag.AnchorPoint = Vector2.new(1, 0.5)
			tag.Position = UDim2.new(1, -10, 0.5, 0)
			tag.Size = UDim2.fromOffset(84, 24)
			tag.ZIndex = 5
			tag.Parent = row
			UIStyler.Corner(theme.Radii.Pill).Parent = tag
			GPLayoutKit.SoftStroke(theme, tag)

			local tagText = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "TagText")
			tagText.Text = item.tag
			tagText.Size = UDim2.fromScale(1, 1)
			tagText.ZIndex = 6
			tagText.Parent = tag
		end
	end

	self._gpFree = gpButton(theme, card, {
		text = "Claim",
		fill = theme.Colors.Secondary,
		sizePx = Vector2.new(GP_RAIL_W - 28, 46),
		index = 0,
		onClick = function()
			self:_ClaimFree()
		end,
	}, self._gpShadows)
	self._gpFree.root.Position = UDim2.fromOffset(14, 212)

	local note = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "FreeNote")
	note.Text = ""
	note.TextWrapped = true
	note.Position = UDim2.fromOffset(16, 262)
	note.Size = UDim2.new(1, -32, 0, 24)
	note.ZIndex = 4
	note.Parent = card
	self._gpFreeNote = note

	-- ---- paid actions ------------------------------------------------
	local divider = GPLayoutKit.Divider(theme, rail)
	divider.Position = UDim2.fromOffset(0, 304)

	local section = GPLayoutKit.SectionLabel(theme, rail, GP_PAID.section)
	section.Position = UDim2.fromOffset(2, 326)

	self._gpSkip = gpButton(theme, rail, {
		text = "Skip day",
		-- Both paid actions are priced in the premium currency, so the button
		-- wears its colour (through the token accessor, never a raw field).
		fill = UIChrome.CurrencyColor(theme, "Bux"),
		sizePx = Vector2.new(GP_RAIL_W, 52),
		index = 1,
		iconKey = "skip",
		onClick = function()
			self:_SkipDay()
		end,
	}, self._gpShadows)
	self._gpSkip.root.Position = UDim2.fromOffset(0, 354)

	self._gpAll = gpButton(theme, rail, {
		text = "Claim all",
		fill = theme.Arcade.Gold,
		sizePx = Vector2.new(GP_RAIL_W, 52),
		index = 0,
		iconKey = "chest",
		onClick = function()
			self:_ClaimAll()
		end,
	}, self._gpShadows)
	self._gpAll.root.Position = UDim2.fromOffset(0, 414)

	local hint = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "PaidHint")
	hint.TextWrapped = true
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.Position = UDim2.fromOffset(2, 474)
	hint.Size = UDim2.new(1, -4, 0, 40)
	hint.ZIndex = 4
	hint.Parent = rail
	self._gpResetHint = hint

	-- ---- the primary claim -------------------------------------------
	self._gpClaim = gpButton(theme, rail, {
		text = "Claim",
		fill = theme.Colors.Secondary,
		sizePx = Vector2.new(GP_RAIL_W, 64),
		index = 1,
		onClick = function()
			self:_Claim()
		end,
	}, self._gpShadows)
	self._gpClaim.root.AnchorPoint = Vector2.new(0, 1)
	self._gpClaim.root.Position = UDim2.fromScale(0, 1)
end

-- ---- state ---------------------------------------------------------

-- The shipped panel's paid gate, fail-closed in the same order.
function DailyRewardsScreen:_GPPaidBlocked(): string?
	if self._paidRestricted then
		return GP_PAID.restricted
	end
	if self._paidToday then
		return GP_PAID.spent
	end
	return nil
end

function DailyRewardsScreen:_GPCellPressed(index: number)
	local entry = self._days[index]
	if not entry then
		return
	end
	if entry.claimed then
		self:_Toast(string.format("Day %d is already in your pocket.", entry.day), "Info")
		return
	end
	if entry.day == self._day and not self._claimedToday then
		self:_Claim()
		return
	end
	local away = entry.day - self._day
	if away <= 0 then
		self:_Toast("Come back tomorrow for the next one!", "Info")
	else
		self:_Toast(string.format("Day %d opens in %d %s.", entry.day, away, if away == 1 then "day" else "days"), "Info")
	end
end

-- FREE REWARD. The live panel answers three ways: already claimed (the
-- persisted FreeClaimed attribute), not a group member (it opens the join
-- prompt and re-claims when the popup closes), or a grant. All three are here;
-- standalone, the prompt is the membership flip.
function DailyRewardsScreen:_ClaimFree()
	if self._freeClaimed then
		self._freeNote = GP_FREE.claimedNote
		self:_GPRefreshRail()
		return
	end
	if not self._inGroup then
		self._inGroup = true
		self._freeNote = GP_FREE.joinNote
		self:_Toast(GP_FREE.joinToast, "Info")
		self:_GPRefreshRail()
		return
	end
	self._freeClaimed = true
	self._freeNote = GP_FREE.grantedNote
	self:_Toast(GP_FREE.grantedNote, "Success")
	self:_GPRefreshRail()
end

-- SKIP DAY: take the next rung without waiting for the reset. Gated on the
-- account check, the once-a-day paid budget AND today's free claim — the
-- shipped rule is "never sell someone the freebie they already have".
function DailyRewardsScreen:_SkipDay()
	local blocked = self:_GPPaidBlocked()
	if blocked then
		self:_Toast(blocked, "Warning")
		return
	end
	if not self._claimedToday then
		self:_Toast(GP_PAID.needFree, "Warning")
		return
	end
	-- The rung a skip BUYS is the next one. self._day is today's rung and the
	-- gate above proves it is already spent, so granting self._days[self._day]
	-- would re-award the freebie and hand back nothing for the Robux — the very
	-- thing the service's "claim today's free reward first" rule exists to stop.
	local nextDay = self._day + 1
	local entry = self._days[nextDay]
	if not entry or entry.claimed then
		self:_Toast(GP_PAID.nothingLeft, "Info")
		return
	end
	entry.claimed = true
	self._paidToday = true
	-- The skipped rung BECOMES today and is already spent, so _claimedToday
	-- stays true; the 1Hz rollover opens day n+1 as normal.
	self._day = nextDay
	self:_Toast(string.format("Day %d skipped — %s is yours!", entry.day, entry.label or tostring(entry.amount or "")), "Success")
	self:_RenderGrid()
end

-- CLAIM ALL: take every remaining rung at once. The service restarts the
-- ladder at day 1 on the NEXT login; until then the panel shows the completed
-- ladder, which is what the stamped grid below renders.
function DailyRewardsScreen:_ClaimAll()
	local blocked = self:_GPPaidBlocked()
	if blocked then
		self:_Toast(blocked, "Warning")
		return
	end
	local taken = 0
	for _, entry in self._days do
		if not entry.claimed then
			entry.claimed = true
			taken += 1
		end
	end
	if taken == 0 then
		self:_Toast(GP_PAID.nothingLeft, "Info")
		return
	end
	self._paidToday = true
	self._claimedToday = true
	self._day = #self._days
	self:_Toast(string.format("Claimed the rest of the ladder — %d days!", taken), "Success")
	self:_RenderGrid()
end

-- ---- the sticker ---------------------------------------------------

function DailyRewardsScreen:_GPStamp(cell: any, delaySeconds: number)
	local theme = self:GetTheme()
	if cell.slam then
		cell.slam:Cancel()
	end
	if cell.settle then
		cell.settle:Cancel()
	end
	cell.stamp.Visible = true
	cell.stampScale.Scale = 2.3

	-- Scale, never Size (layout must not reflow) and never Rotation (a rotated
	-- descendant escapes the calendar's clip). Fast in, then the pack's capped
	-- overshoot settles it — the whole slam is ~0.34s.
	local slam = TweenService:Create(
		cell.stampScale,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, delaySeconds),
		{ Scale = 0.86 }
	)
	cell.slam = slam
	slam.Completed:Once(function(state: Enum.PlaybackState)
		if state ~= Enum.PlaybackState.Completed or not cell.stamp.Parent then
			return
		end
		local settle = TweenService:Create(cell.stampScale, theme.Motion.PulseSettle, { Scale = 1 })
		cell.settle = settle
		settle:Play()
	end)
	slam:Play()
end

-- ---- repaint -------------------------------------------------------

function DailyRewardsScreen:_GPRefresh()
	if not self._gpGrid then
		return -- built under another layout; the next Show rebuilds
	end
	local theme = self:GetTheme()
	local days = self._days
	local total = #days

	local claimedCount = 0
	for _, entry in days do
		if entry.claimed then
			claimedCount += 1
		end
	end

	local nextMilestone = 0
	for _, entry in days do
		if entry.milestone and not entry.claimed then
			nextMilestone = entry.day
			break
		end
	end

	self._gpStreak.Text = string.format("Day %d streak", self._day)
	self._gpProgress.Text = if nextMilestone > 0
		then string.format("%d of %d days claimed · next chair on day %d", claimedCount, total, nextMilestone)
		else string.format("%d of %d days claimed · every chair is yours", claimedCount, total)
	self._gpCount.Text = string.format("%d / %d", claimedCount, total)
	self._gpBar.Size = UDim2.fromScale(if total > 0 then claimedCount / total else 0, 1)

	-- The first repaint SEEDS the stamped set: days already claimed on open are
	-- stamped flat, and only a claim made from here on actually slams.
	local prime = not self._gpPrimed
	self._gpPrimed = true
	local cascade = 0

	local claimableIndex: number? = nil
	for index = 1, math.max(total, #self._gpCells) do
		local entry = days[index]
		if not entry then
			local spare = self._gpCells[index]
			if spare then
				spare.root.Visible = false
			end
			continue
		end

		local cell = self:_GPCell(index)
		local claimed = entry.claimed == true
		local isToday = entry.day == self._day and not claimed
		local future = entry.day > self._day
		-- A chair rung. Marked whether it is ahead of you or not — knowing WHERE
		-- the chairs sit is the whole reason the shipped panel rings days 6-7.
		local milestone = entry.milestone == true and not claimed
		cell.root.Visible = true

		if isToday then
			claimableIndex = index
		end

		local bodyFill = if claimed
			then theme.Colors.Disabled
			elseif isToday then theme.Colors.SurfaceRaised
			else theme.Colors.Surface
		cell.body.BackgroundColor3 = bodyFill
		-- Ring priority: today's rose ring wins, then the milestone's butter one,
		-- then the quiet deepened fill.
		cell.stroke.Color = GPLayoutKit.Deepen(
			theme,
			if isToday then theme.Colors.Primary elseif milestone then theme.Arcade.Gold else bodyFill,
			1
		)
		cell.crest.Visible = milestone
		cell.crest.ImageColor3 = theme.Arcade.Gold

		cell.day.Text = "Day " .. tostring(entry.day)
		cell.day.TextColor3 = if claimed or future then theme.Colors.TextSecondary else theme.Colors.TextPrimary

		-- Dimming rides the TINT, never ImageTransparency: transparency is
		-- IconVisibility's channel (the global icon toggle restores it), and
		-- fighting it would make a dim cell flash back to full on any toggle.
		local artId = IconArchive.Id(entry.icon, { golden = milestone })
		cell.art.Image = artId or ""
		cell.art.ImageColor3 = if claimed or future then theme.Colors.Disabled else GP_ART_IDENTITY

		cell.chip.amount.Text = tostring(entry.amount or "")
		local chipFill = if claimed or future then theme.Colors.Disabled else theme.Arcade.Gold
		cell.chip.root.BackgroundColor3 = chipFill
		cell.chip.stroke.Color = GPLayoutKit.Deepen(theme, chipFill, 1)

		if isToday and not self._claimedToday then
			cell.note.Text = GP_CELL_CLAIM
			cell.note.TextColor3 = theme.Colors.TextPrimary
		else
			cell.note.Text = entry.label or ""
			cell.note.TextColor3 = theme.Colors.TextSecondary
		end

		if claimed then
			if not self._gpStamped[index] then
				self._gpStamped[index] = true
				if prime then
					cell.stamp.Visible = true
					cell.stampScale.Scale = 1
				else
					self:_GPStamp(cell, cascade)
					cascade += GP_CASCADE
				end
			else
				cell.stamp.Visible = true
			end
		else
			self._gpStamped[index] = nil
			cell.stamp.Visible = false
			cell.stampScale.Scale = 1
		end
	end

	-- Move the one aura onto the claimable cell (or park it).
	if claimableIndex and not self._claimedToday then
		local cell = self._gpCells[claimableIndex]
		self._gpGlow.Instance.Parent = cell.body
		self._gpGlow:SetEnabled(true)
	else
		self._gpGlow:SetEnabled(false)
		self._gpGlow.Instance.Parent = self._gpGlowHome
	end

	self:_GPRefreshRail()
	self:_GPPaintClock()
end

function DailyRewardsScreen:_GPRefreshRail()
	if not self._gpClaim then
		return
	end
	local theme = self:GetTheme()

	-- CLAIM / CLAIMED! with the check riding inside, exactly as shipped.
	local ready = not self._claimedToday
	self._gpClaim.label.Text = if ready then string.format("Claim day %d", self._day) else "Claimed!"
	self._gpClaim.check.Visible = not ready
	self._gpClaim.SetTone(if ready then theme.Colors.Secondary else theme.Colors.Disabled)

	-- Both paid buttons stay PRESSABLE when gated (the shipped panel answers
	-- with the reason rather than going inert), but the tone telegraphs it.
	local blocked = self:_GPPaidBlocked()
	local skipReady = blocked == nil and self._claimedToday
	self._gpSkip.SetTone(if skipReady then UIChrome.CurrencyColor(theme, "Bux") else theme.Colors.Disabled)
	self._gpAll.SetTone(if blocked == nil then theme.Arcade.Gold else theme.Colors.Disabled)

	if self._freeClaimed then
		self._gpFree.label.Text = "Claimed!"
		self._gpFree.check.Visible = true
		self._gpFree.SetTone(theme.Colors.Disabled)
		if self._freeNote == "" then
			self._freeNote = GP_FREE.claimedNote
		end
	else
		self._gpFree.label.Text = "Claim"
		self._gpFree.check.Visible = false
		self._gpFree.SetTone(theme.Colors.Secondary)
	end
	self._gpFreeNote.Text = self._freeNote
end

-- ---- one 1Hz handler for every clock on the page --------------------

function DailyRewardsScreen:_GPPaintClock()
	local text = UIChrome.FormatCountdown(self._nextClaimIn)
	if self._countdown then
		self._countdown.Text = text
	end
	if self._gpResetHint then
		self._gpResetHint.Text = string.format(GP_PAID.hint, text)
	end
end

function DailyRewardsScreen:_GPStartTicker()
	if self._gpTickStop then
		return
	end
	local accumulated = 0
	-- ONE handler on the shared UITicker Heartbeat, driving BOTH clocks (the
	-- ribbon countdown and the paid-reset hint). Per-label loops are the
	-- rejected pattern; so is a screen-owned RunService connection.
	self._gpTickStop = UITicker.Register(function(dt: number)
		local label = self._countdown
		if not label or not label.Parent or not UIChrome.IsOnScreen(label) then
			return
		end
		accumulated += dt
		if accumulated < 1 then
			return
		end
		while accumulated >= 1 do
			accumulated -= 1
			self._nextClaimIn = math.max(0, self._nextClaimIn - 1)
		end
		if self._nextClaimIn > 0 then
			self:_GPPaintClock()
			return
		end
		-- The daily reset rolled over: open the next rung, hand back today's
		-- paid budget (the service's one-paid-action-per-UTC-day) and repaint.
		self._nextClaimIn = DAY_SECONDS
		self._claimedToday = false
		self._paidToday = false
		self._day = math.min(self._day + 1, #self._days)
		self:_RenderGrid()
	end, self.Root)
end

function DailyRewardsScreen:_GPStopTicker()
	if self._gpTickStop then
		self._gpTickStop()
		self._gpTickStop = nil
	end
end

-- A style rebuild destroys the Gui, but UIShadow BUDGET counts only fall
-- when a handle is released — hand every GL and GP shadow back here.
function DailyRewardsScreen:_OnTeardown()
	self:_StopTicker()
	self:_StopBreath()
	GLLayoutKit.ReleaseShadows(self._glShadows)
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	if self._glCells then
		table.clear(self._glCells)
	end
	if self._gpCells then
		for _, cell in self._gpCells do
			if cell.slam then
				cell.slam:Cancel()
				cell.slam = nil
			end
			if cell.settle then
				cell.settle:Cancel()
				cell.settle = nil
			end
			if cell.click then
				cell.click:Disconnect()
				cell.click = nil
			end
		end
		table.clear(self._gpCells)
	end
	self._glCells = nil
	self._glField = nil
	self._gpCells = nil
	self._gpShadows = nil
	self._gpGrid = nil
	self._gpGlow = nil
	self._gpGlowHome = nil
	self._gpStamped = nil
	self._gpClaim = nil
	self._gpSkip = nil
	self._gpAll = nil
	self._gpFree = nil
	self._gpResetHint = nil
	self._countdown = nil
end

return DailyRewardsScreen
