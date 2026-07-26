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

local RunService = game:GetService("RunService")

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UIScreenBase = require(script.Parent.UIScreenBase)
local GLLayoutKit = require(script.Parent.Parent.Framework.GLLayoutKit)

type Day = { day: number, icon: string, amount: string, claimed: boolean?, milestone: boolean? }

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

local function demoDays(): { Day }
	-- Reward ladder: small cash most days, a golden milestone every 7th.
	local ladder = {
		{ icon = "cash", amount = "250" },
		{ icon = "cash", amount = "400" },
		{ icon = "bux", amount = "15" },
		{ icon = "crate", amount = "1" },
		{ icon = "cash", amount = "750" },
		{ icon = "bux", amount = "25" },
		{ icon = "chest", amount = "1" },
	}
	local days = {}
	for index = 1, 28 do
		local spec = ladder[((index - 1) % #ladder) + 1]
		local milestone = index % 7 == 0
		table.insert(days, {
			day = index,
			icon = if milestone then "chest" else spec.icon,
			amount = if milestone then tostring(index * 100) else spec.amount,
			claimed = index < 5,
			milestone = milestone,
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
end

function DailyRewardsScreen:_Claim()
	if self._claimedToday then
		self:_Toast("ALREADY CLAIMED — COME BACK TOMORROW", "Info")
		return
	end
	local entry = self._days[self._day]
	if not entry then
		return
	end
	entry.claimed = true
	self._claimedToday = true
	self:_Toast(string.format("CLAIMED DAY %d  ·  %s", entry.day, tostring(entry.amount or "")), "Success")
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
	field.ClipsDescendants = false -- stamps + overhanging badges poke out
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

-- A style rebuild destroys the Gui, but UIShadow BUDGET counts only fall
-- when a handle is released — hand every GL shadow back here.
function DailyRewardsScreen:_OnTeardown()
	self:_StopTicker()
	self:_StopBreath()
	GLLayoutKit.ReleaseShadows(self._glShadows)
	if self._glCells then
		table.clear(self._glCells)
	end
	self._glCells = nil
	self._glField = nil
	self._countdown = nil
end

return DailyRewardsScreen
