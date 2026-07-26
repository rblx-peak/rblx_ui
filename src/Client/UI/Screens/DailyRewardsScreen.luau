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

return DailyRewardsScreen
