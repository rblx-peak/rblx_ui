--!strict
-- LEADERBOARD screen — the doc §9 board grammar lifted off the SurfaceGui and
-- onto a §7.4 modal card. Anatomy, top to bottom:
--
--   * a board-selector tab row — each board owns ONE accent colour (doc §3.3
--     "colour = identity") used for both its title and its value column;
--   * a podium strip for the top 3: circular headshots with gold / silver /
--     bronze rings on near-black pedestals, #1 larger and centre;
--   * zebra rows 48px (Arcade.NearBlack2 / Arcade.Row @ 0.15) — gold rank
--     number, circular headshot, name, accent-coloured value in 1.2K format;
--   * the local player's row pinned to the bottom, always visible, ringed in
--     gold (doc §11.4 "local player first").
--
-- Show(data) = { boards = { {id, title, accent, rows, localRow?} }, localRank },
-- where a row is {rank, name, userId, value} and `accent` is either a Color3 or
-- one of "Green" / "Gold" / "Orange" / "Purple". `localRank` may be a row table
-- or a plain rank number (looked up in the active board). Falls back to the
-- demo boards below so the screen renders standalone.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIScreenBase = require(script.Parent.UIScreenBase)
local ACLayoutKit = require(script.Parent.Parent.Framework.ACLayoutKit)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local UITicker = require(script.Parent.Parent.Framework.UITicker)

type Row = { rank: number, name: string, userId: number, value: number }
type Board = { id: string, title: string, accent: any, rows: { Row }, localRow: Row? }

local LeaderboardScreen = setmetatable({}, { __index = UIScreenBase })
LeaderboardScreen.__index = LeaderboardScreen

-- Fixed px at the 1650×1020 baseline. Card 1160×760 → content 1132×672.
local CARD = Vector2.new(1160, 760)
local CONTENT_W = 1132
local CONTENT_H = 672
local TAB_H = 46
local TAB_GAP = 16
local PODIUM_Y = 60
local PODIUM_H = 200
local ROWS_Y = 272
local ROW_H = 48
local LOCAL_H = 56
local SCROLLBAR_RESERVE = 10
local ZEBRA_TRANSPARENCY = 0.15 -- doc §9
-- Row column geometry: rank | headshot | name | accent value (right-aligned).
local AVATAR = 34
local AVATAR_X = 104
local NAME_X = AVATAR_X + AVATAR + 14

-- Podium geometry: #1 centre and taller, #2 left, #3 right.
local PODIUM_SLOTS = {
	{ rank = 1, x = 566, pedestalW = 220, pedestalH = 78, avatar = 112, valueSize = 24 },
	{ rank = 2, x = 316, pedestalW = 200, pedestalH = 62, avatar = 88, valueSize = 20 },
	{ rank = 3, x = 816, pedestalW = 200, pedestalH = 52, avatar = 88, valueSize = 20 },
}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local function demoRows(seed: number, top: number, step: number): { Row }
	local names = {
		"ClayCrusher", "KilnKing", "GlazeGoblin", "WheelWitch", "PorcelainPete",
		"MugMerchant", "SlipCasterX", "BisqueBaron", "TerraTina", "OxideOllie",
		"CrackleQueen", "PotluckPaul",
	}
	local ids = { 1, 156, 2, 3, 261, 1101, 8, 12, 16, 18, 261, 1 }
	local rows: { Row } = {}
	for i, name in names do
		table.insert(rows, {
			rank = i,
			name = name,
			userId = ids[i] or 1,
			value = math.max(1, top - (i - 1) * step + (seed * i) % step),
		})
	end
	return rows
end

local DEMO_BOARDS: { Board } = {
	{
		id = "wins",
		title = "MOST WINS",
		accent = "Green",
		rows = demoRows(3, 1840, 120),
		localRow = { rank = 27, name = "You", userId = 0, value = 214 },
	},
	{
		id = "cash",
		title = "RICHEST",
		accent = "Gold",
		rows = demoRows(7, 2450000, 160000),
		localRow = { rank = 341, name = "You", userId = 0, value = 86400 },
	},
	{
		id = "streak",
		title = "LONGEST STREAK",
		accent = "Orange",
		rows = demoRows(5, 96, 6),
		localRow = { rank = 62, name = "You", userId = 0, value = 19 },
	},
	{
		id = "trophies",
		title = "TROPHIES",
		accent = "Purple",
		rows = demoRows(11, 12800, 700),
		localRow = { rank = 88, name = "You", userId = 0, value = 3120 },
	},
}

-- Doc §9: leaderboard values render in the compact 1.2K format.
local function formatValue(n: number): string
	if n >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif n >= 1000 then
		return string.format("%.1fK", n / 1000)
	end
	return tostring(math.floor(n + 0.5))
end

local function accentColor(theme: Types.UITheme, accent: any): Color3
	if typeof(accent) == "Color3" then
		return accent
	end
	local map: { [string]: Color3 } = {
		Green = theme.Arcade.Green,
		Gold = theme.Arcade.Gold,
		Orange = theme.Arcade.Orange,
		Purple = theme.Arcade.ShopAccents[4],
		Blue = theme.Arcade.Blue,
		Red = theme.Arcade.Red,
	}
	return map[tostring(accent)] or theme.Arcade.Gold
end

-- Podium ring colours, all drawn from the palette: gold / the ruler-tick near
-- white as silver / arcade orange as bronze (doc §3.3 colour = identity).
local function ringColor(theme: Types.UITheme, rank: number): Color3
	if rank == 1 then
		return theme.Arcade.Gold
	elseif rank == 2 then
		return theme.Arcade.RulerTick
	end
	return theme.Arcade.Orange
end

-- A circular headshot well (doc §4.2: circles are the arcade's round
-- exception). The flat-cartoon player icon holds the slot until the thumbnail
-- resolves; a failed fetch just leaves the icon (doc §10 fallback chain).
local function avatarCircle(theme: Types.UITheme, parent: Instance, userId: number, sizePx: number, ring: Color3?): Frame
	local holder = UIStyler.Frame("Avatar")
	holder.BackgroundColor3 = theme.Arcade.NearBlack
	holder.Size = UDim2.fromOffset(sizePx, sizePx)
	holder.ClipsDescendants = true
	UIChrome.Corner("Arcade", "Pill").Parent = holder
	-- Policy stroke from UIChrome (3px Border); only its COLOUR carries the
	-- podium identity when a ring is asked for.
	local stroke = UIChrome.Stroke(theme, "Arcade", "Panel")
	if ring then
		stroke.Color = ring
	end
	stroke.Parent = holder
	holder.Parent = parent

	local glyph = IconArchive.Image(holder, "player", math.floor(sizePx * 0.6))
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.5)

	local photo = Instance.new("ImageLabel")
	photo.Name = "Headshot"
	photo.BackgroundTransparency = 1
	photo.ScaleType = Enum.ScaleType.Crop
	photo.Size = UDim2.fromScale(1, 1)
	photo.Visible = false
	photo.Parent = holder

	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		end)
		if ok and typeof(content) == "string" and content ~= "" and holder.Parent then
			photo.Image = content
			photo.Visible = true
			glyph.Visible = false
		end
	end)

	return holder
end

function LeaderboardScreen.new()
	local self = UIScreenBase.new("LeaderboardScreen", 8)
	self._boards = DEMO_BOARDS
	self._activeIndex = 1
	self._localRank = nil :: any
	self._tabs = {} :: { { surface: Frame, stroke: UIStroke, label: TextLabel, accent: Color3 } }
	return setmetatable(self, LeaderboardScreen)
end

function LeaderboardScreen:_ActiveBoard(): Board
	return self._boards[self._activeIndex] or self._boards[1]
end

function LeaderboardScreen:_BuildContent()
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end
	if self:LayoutKit() == "AC" then
		self:_BuildACLayout()
		return
	end
	local theme = self:GetTheme()

	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = self:_R("LEADERBOARDS"),
		sizePx = CARD,
		onClose = function()
			self.ScreenController:HideScreen("leaderboard")
		end,
	})
	self._modal = modal
	local content = modal.content

	local tabRow = UIStyler.Frame("Tabs")
	tabRow.BackgroundTransparency = 1
	tabRow.Size = UDim2.new(1, 0, 0, TAB_H)
	tabRow.Parent = content
	self._tabRow = tabRow

	local podium = UIStyler.Frame("Podium")
	podium.BackgroundTransparency = 1
	podium.Position = UDim2.fromOffset(0, PODIUM_Y)
	podium.Size = UDim2.new(1, 0, 0, PODIUM_H)
	podium.Parent = content
	self._podium = podium

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Rows"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, ROWS_Y)
	scroll.Size = UDim2.new(1, 0, 0, CONTENT_H - ROWS_Y - LOCAL_H - 10)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = theme.Arcade.Gold
	scroll.Parent = content
	UIStyler.ListLayout({
		Padding = UDim.new(0, 0), -- true zebra: the rows meet edge to edge
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	}).Parent = scroll
	self._scroll = scroll

	-- The pinned local row lives OUTSIDE the scroll so it is always visible.
	local localRow = UIStyler.Frame("LocalRow")
	localRow.BackgroundColor3 = theme.Arcade.NearBlack
	localRow.BackgroundTransparency = 0
	localRow.AnchorPoint = Vector2.new(0, 1)
	localRow.Position = UDim2.fromScale(0, 1)
	localRow.Size = UDim2.new(1, 0, 0, LOCAL_H)
	UIChrome.Stroke(theme, "Arcade", "Selection").Parent = localRow -- gold ring
	UIChrome.GlassGradient().Parent = localRow
	localRow.Parent = content
	self._localRowFrame = localRow

	self:_BuildTabs()
	self:_RenderBoard()
end

function LeaderboardScreen:_BuildTabs()
	if self:LayoutKit() == "GP" then
		self:_GPBuildTabs()
		return
	end
	if self:LayoutKit() == "AC" then
		self:_ACRenderRail()
		return
	end
	local theme = self:GetTheme()
	for _, child in self._tabRow:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(self._tabs)

	local count = math.max(1, #self._boards)
	local width = math.floor((CONTENT_W - TAB_GAP * (count - 1)) / count)

	for index, board in self._boards do
		local accent = accentColor(theme, board.accent)

		local root = UIStyler.Frame("Tab_" .. board.id)
		root.BackgroundTransparency = 1
		root.Position = UDim2.fromOffset((index - 1) * (width + TAB_GAP), 0)
		root.Size = UDim2.fromOffset(width, TAB_H)
		root.Parent = self._tabRow

		local surface = UIStyler.Frame("Surface")
		surface.BackgroundColor3 = theme.Arcade.NearBlack2
		surface.AnchorPoint = Vector2.new(0.5, 0.5)
		surface.Position = UDim2.fromScale(0.5, 0.5)
		surface.Size = UDim2.fromScale(1, 1)
		-- One policy stroke per tab whose COLOUR flips between the style's
		-- resting frame colour (black under Classic) and the board accent
		-- (selected) — selection is a ring, doc §4.3.
		local stroke = UIChrome.Stroke(theme, "Arcade", "Selection")
		stroke.Parent = surface
		UIChrome.GlassGradient().Parent = surface
		surface.Parent = root

		local label = UIChrome.Text("Label", 22, accent)
		label.Text = board.title
		label.RichText = false -- TextTruncate is unreliable on a RichText label
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Size = UDim2.fromScale(1, 1)
		label.Parent = surface

		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Text = ""
		hit.BackgroundTransparency = 1
		hit.AutoButtonColor = false
		hit.Size = UDim2.fromScale(1, 1)
		hit.Parent = root
		hit.Activated:Connect(function()
			self:_SelectBoard(index)
		end)
		UIChrome.Animate(theme, hit, surface)

		table.insert(self._tabs, { surface = surface, stroke = stroke, label = label, accent = accent })
	end

	self:_PaintTabs()
end

function LeaderboardScreen:_PaintTabs()
	if self:LayoutKit() == "GP" then
		self:_GPPaintTabs()
		return
	end
	local theme = self:GetTheme()
	local chrome = theme.Chrome
	for index, tab in self._tabs do
		local active = index == self._activeIndex
		tab.surface.BackgroundColor3 = if active then theme.Arcade.NearBlack else theme.Arcade.NearBlack2
		tab.surface.BackgroundTransparency = if active then 0 else 0.5
		tab.stroke.Color = if active
			then tab.accent
			elseif chrome and chrome.StrokeFollowsAccent then theme.Colors.Accent
			else BLACK
		tab.stroke.Transparency = if active or chrome == nil then 0 else chrome.StrokeTransparency
		tab.label.TextTransparency = if active then 0 else 0.3
	end
end

function LeaderboardScreen:_SelectBoard(index: number)
	if index == self._activeIndex then
		return
	end
	self._activeIndex = index
	self:_PaintTabs()
	local tab = self._tabs[index]
	if tab then
		UIChrome.Pulse(self:GetTheme(), tab.surface)
	end
	self:_RenderBoard()
end

-- One podium column: pedestal block carrying the name + accent value, the
-- ringed headshot above it, and the rank numeral straddling the two.
function LeaderboardScreen:_BuildPodiumSlot(slot: any, row: Row, accent: Color3)
	local theme = self:GetTheme()
	local ring = ringColor(theme, slot.rank)

	local pedestal = UIStyler.Frame("Pedestal" .. slot.rank)
	pedestal.BackgroundColor3 = theme.Arcade.NearBlack2
	pedestal.AnchorPoint = Vector2.new(0.5, 1)
	pedestal.Position = UDim2.fromOffset(slot.x, PODIUM_H)
	pedestal.Size = UDim2.fromOffset(slot.pedestalW, slot.pedestalH)
	UIChrome.Stroke(theme, "Arcade").Parent = pedestal
	UIChrome.GlassGradient().Parent = pedestal
	pedestal.Parent = self._podium

	local name = UIChrome.Text("Name", 19, WHITE)
	name.Text = row.name
	name.RichText = false
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(8, 6)
	name.Size = UDim2.new(1, -16, 0, 24)
	name.Parent = pedestal

	local value = UIChrome.Text("Value", slot.valueSize, accent)
	value.Text = formatValue(row.value)
	value.Position = UDim2.fromOffset(8, 30)
	value.Size = UDim2.new(1, -16, 0, slot.valueSize + 6)
	value.Parent = pedestal

	local avatarBottom = PODIUM_H - slot.pedestalH - 10
	local avatar = avatarCircle(theme, self._podium, row.userId, slot.avatar, ring)
	avatar.AnchorPoint = Vector2.new(0.5, 1)
	avatar.Position = UDim2.fromOffset(slot.x, avatarBottom)

	local badge = UIStyler.Frame("Rank" .. slot.rank)
	badge.BackgroundColor3 = ring
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.fromOffset(slot.x, avatarBottom)
	badge.Size = UDim2.fromOffset(34, 34)
	UIChrome.Corner("Arcade", "Pill").Parent = badge
	UIChrome.Stroke(theme, "Arcade").Parent = badge
	badge.Parent = self._podium

	local numeral = UIChrome.Text("Numeral", 20, theme.Arcade.NearBlack)
	numeral.Text = tostring(slot.rank)
	numeral.Size = UDim2.fromScale(1, 1)
	UIChrome.TextOutline(numeral, 1) -- dark ink on a bright pip: no black halo
	numeral.Parent = badge
end

-- One board row: gold rank, circular headshot, name, accent value. `highlight`
-- paints the pinned local row instead of the zebra fill.
function LeaderboardScreen:_BuildRow(parent: Instance, row: Row, index: number, accent: Color3, highlight: boolean): Frame
	local theme = self:GetTheme()
	local height = if highlight then LOCAL_H else ROW_H

	local frame: Frame
	if highlight then
		frame = parent :: Frame
	else
		frame = UIStyler.Frame("Row" .. index)
		frame.BackgroundColor3 = if index % 2 == 1 then theme.Arcade.NearBlack2 else theme.Arcade.Row
		frame.BackgroundTransparency = ZEBRA_TRANSPARENCY
		frame.Size = UDim2.new(1, -SCROLLBAR_RESERVE, 0, height)
		frame.LayoutOrder = index
		frame.Parent = parent
	end

	local rank = UIChrome.Text("Rank", 22, theme.Arcade.Gold)
	rank.Text = "#" .. tostring(row.rank)
	rank.TextXAlignment = Enum.TextXAlignment.Left
	rank.Position = UDim2.fromOffset(16, 0)
	rank.Size = UDim2.fromOffset(84, height)
	rank.Parent = frame

	-- One avatar size and one name column on both the list rows and the pinned
	-- local row, so the two never drift out of alignment.
	local avatar = avatarCircle(theme, frame, row.userId, AVATAR, if highlight then theme.Arcade.Gold else nil)
	avatar.AnchorPoint = Vector2.new(0, 0.5)
	avatar.Position = UDim2.new(0, AVATAR_X, 0.5, 0)

	local name = UIChrome.Text("Name", 20, if highlight then theme.Arcade.Gold else WHITE)
	name.Text = if highlight then row.name .. " (you)" else row.name
	name.RichText = false
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(NAME_X, 0)
	name.Size = UDim2.new(1, -(NAME_X + 210), 0, height)
	name.Parent = frame

	local value = UIChrome.Text("Value", 22, accent)
	value.Text = formatValue(row.value)
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.new(1, -18, 0, 0)
	value.Size = UDim2.fromOffset(180, height)
	value.Parent = frame

	return frame
end

-- The local player's row for the active board: an explicit localRank wins,
-- then a rank number looked up in the board, then the board's own demo row.
function LeaderboardScreen:_LocalRow(board: Board): Row
	local supplied = self._localRank
	if type(supplied) == "table" then
		return supplied :: Row
	end
	if type(supplied) == "number" then
		for _, row in board.rows do
			if row.rank == supplied then
				return row
			end
		end
		local player = Players.LocalPlayer
		return {
			rank = supplied,
			name = if player then player.DisplayName else "You",
			userId = if player then player.UserId else 0,
			value = 0,
		}
	end
	local fallback = board.localRow or { rank = #board.rows + 1, name = "You", userId = 0, value = 0 }
	local player = Players.LocalPlayer
	if player then
		return { rank = fallback.rank, name = player.DisplayName, userId = player.UserId, value = fallback.value }
	end
	return fallback
end

function LeaderboardScreen:_RenderBoard()
	if self:LayoutKit() == "GP" then
		self:_GPRenderBoard()
		return
	end
	if self:LayoutKit() == "AC" then
		self:_ACRenderBoard()
		return
	end
	local theme = self:GetTheme()
	local board = self:_ActiveBoard()
	if not board then
		return
	end
	local accent = accentColor(theme, board.accent)

	for _, child in self._podium:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for _, child in self._scroll:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for _, child in self._localRowFrame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	for _, slot in PODIUM_SLOTS do
		local row = board.rows[slot.rank]
		if row then
			self:_BuildPodiumSlot(slot, row, accent)
		end
	end

	-- The podium already tells the top-3 story; the list carries from 4 down.
	for index = 4, #board.rows do
		self:_BuildRow(self._scroll, board.rows[index], index, accent, false)
	end

	self:_BuildRow(self._localRowFrame, self:_LocalRow(board), 0, accent, true)
	self._scroll.CanvasPosition = Vector2.new(0, 0)
end

function LeaderboardScreen:_Ingest(data: any?)
	if not data then
		return
	end
	if data.boards and #data.boards > 0 then
		self._boards = data.boards
		self._activeIndex = math.clamp(self._activeIndex, 1, #self._boards)
	end
	if data.localRank ~= nil then
		self._localRank = data.localRank
	end
end

function LeaderboardScreen:_OnShow(data: any?)
	if data then
		self:_Ingest(data)
		self:_BuildTabs()
		self:_RenderBoard()
	end
	if self._modal then
		UIChrome.PopIn(self:GetTheme(), self._modal.content)
	end
end

function LeaderboardScreen:Update(data: any)
	self:_Ingest(data)
	if self._built then
		self:_BuildTabs()
		self:_RenderBoard()
	end
end

-- ========================================================================
-- AC layout — the "RANKING" terminal page (theme.LayoutKit == "AC").
-- A left board rail and ONE dense mono table: a dim header row, hairline
-- rows rank / callsign / score with the numerals right-aligned, and the
-- local player pinned under the scroll behind the accent notch. No podium
-- under AC — the flat table IS the look. Same boards/localRank feed and
-- the same _SelectBoard/_Ingest paths as classic; only the grammar changes.
-- ========================================================================

local AC_RAIL_W = 200
local AC_HEADER_H = 24
local AC_ROW_H = 26
local AC_LOCAL_H = 30

function LeaderboardScreen:_BuildACLayout()
	local theme = self:GetTheme()

	local shell = ACLayoutKit.Shell(theme, self.Root, self:_R("RANKING"))
	-- _OnShow pops self._modal.content in both layouts; under AC that is the
	-- shell's content region.
	self._modal = { content = shell.content } :: any
	ACLayoutKit.SetHints(shell, { { key = "ESC", action = "CLOSE" } })

	local close = ACLayoutKit.ActionButton(theme, shell.topRight, "CLOSE", function()
		self.ScreenController:HideScreen("leaderboard")
	end)
	close.Size = UDim2.fromOffset(96, 26)

	-- THE one UITicker handler for this screen backs the [ESC] hint; bound to
	-- the page so a style rebuild unregisters it.
	local escDown = false
	UITicker.Register(function()
		local pressed = UserInputService:IsKeyDown(Enum.KeyCode.Escape)
		if pressed and not escDown and self._visible then
			self.ScreenController:HideScreen("leaderboard")
		end
		escDown = pressed
	end, shell.page)

	local railHost = UIStyler.Frame("RailHost")
	railHost.BackgroundTransparency = 1
	railHost.Size = UDim2.new(0, AC_RAIL_W, 1, 0)
	railHost.Parent = shell.content
	self._acRailHost = railHost

	local divider = ACLayoutKit.Rule(theme, shell.content, 0.75)
	divider.Size = UDim2.new(0, 1, 1, 0)
	divider.Position = UDim2.fromOffset(AC_RAIL_W + 11, 0)

	local tableHost = UIStyler.Frame("TableHost")
	tableHost.BackgroundTransparency = 1
	tableHost.Position = UDim2.fromOffset(AC_RAIL_W + 24, 0)
	tableHost.Size = UDim2.new(1, -(AC_RAIL_W + 24), 1, 0)
	tableHost.Parent = shell.content

	-- Static dim header row; the data rows land in the scroll below it.
	ACLayoutKit.ListRow(theme, tableHost, {
		{ text = "RANK", widthScale = 0.16, align = Enum.TextXAlignment.Right, dim = true },
		{ text = "CALLSIGN", widthScale = 0.56, dim = true },
		{ text = "SCORE", widthScale = 0.28, align = Enum.TextXAlignment.Right, dim = true },
	}, { heightPx = AC_HEADER_H })

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Table"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, AC_HEADER_H + 4)
	scroll.Size = UDim2.new(1, 0, 1, -(AC_HEADER_H + 4 + AC_LOCAL_H + 6))
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = theme.Colors.Accent
	scroll.Parent = tableHost
	UIStyler.ListLayout({
		Padding = UDim.new(0, 0),
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	}).Parent = scroll
	self._acScroll = scroll

	-- The pinned local row lives OUTSIDE the scroll so it is always visible.
	local localHost = UIStyler.Frame("LocalRow")
	localHost.BackgroundColor3 = theme.Colors.SurfaceRaised
	localHost.BackgroundTransparency = 0.85
	localHost.AnchorPoint = Vector2.new(0, 1)
	localHost.Position = UDim2.fromScale(0, 1)
	localHost.Size = UDim2.new(1, 0, 0, AC_LOCAL_H)
	localHost.Parent = tableHost
	self._acLocalHost = localHost

	self:_ACRenderRail()
	self:_ACRenderBoard()
end

function LeaderboardScreen:_ACRenderRail()
	local theme = self:GetTheme()
	-- A style flip can leave stale classic tab records behind; drop them so
	-- _SelectBoard's classic-tab touches stay no-ops under AC.
	table.clear(self._tabs)
	for _, child in self._acRailHost:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	ACLayoutKit.SectionLabel(theme, self._acRailHost, "BOARD")
	local rail = ACLayoutKit.Rail(theme, self._acRailHost, AC_RAIL_W)
	rail.frame.Position = UDim2.fromOffset(0, 24)
	rail.frame.Size = UDim2.new(0, AC_RAIL_W, 1, -24)
	for index, board in self._boards do
		rail.AddEntry(board.title, function()
			self:_SelectBoard(index)
		end)
	end
	rail.Select(self._activeIndex)
end

function LeaderboardScreen:_ACRenderBoard()
	local theme = self:GetTheme()
	local board = self:_ActiveBoard()
	if not board then
		return
	end

	for _, child in self._acScroll:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for _, child in self._acLocalHost:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	-- The full flat table, rank 1 down — the podium story is the top rows.
	for index, row in board.rows do
		ACLayoutKit.ListRow(theme, self._acScroll, {
			{ text = "#" .. tostring(row.rank), widthScale = 0.16, align = Enum.TextXAlignment.Right, dim = true },
			{ text = row.name, widthScale = 0.56 },
			{ text = formatValue(row.value), widthScale = 0.28, align = Enum.TextXAlignment.Right, color = theme.Colors.Accent },
		}, { heightPx = AC_ROW_H, layoutOrder = index })
	end

	local localRow = self:_LocalRow(board)
	local pinned = ACLayoutKit.ListRow(theme, self._acLocalHost, {
		{ text = "#" .. tostring(localRow.rank), widthScale = 0.16, align = Enum.TextXAlignment.Right },
		{ text = localRow.name .. " (YOU)", widthScale = 0.56 },
		{ text = formatValue(localRow.value), widthScale = 0.28, align = Enum.TextXAlignment.Right, color = theme.Colors.Accent },
	}, { heightPx = AC_LOCAL_H })
	-- The accent notch marks the local player (the AC selection grammar).
	local notch = UIStyler.Frame("Notch")
	notch.BackgroundColor3 = theme.Colors.Accent
	notch.BorderSizePixel = 0
	notch.Size = UDim2.new(0, 3, 1, -8)
	notch.Position = UDim2.new(0, 0, 0, 4)
	notch.Parent = pinned

	self._acScroll.CanvasPosition = Vector2.new(0, 0)
end

-- ========================================================================
-- GP layout — THE SHELF (theme.LayoutKit == "GP"). Girly Pop, cutesy pastel
-- ceramics. Presentation only: the same four boards, the same podium, the same
-- FOUR row columns (rank / headshot / name / value in the 1.2K format) and the
-- same pinned local row. §6 anti-condescension: a soft aesthetic is not a
-- simple one, so nothing here shows less than the classic board.
--
-- What changes is the grammar:
--   * a cream page with a rose ribbon instead of a near-black modal;
--   * tab chips and row plates in PETAL corners that ALTERNATE their mirror by
--     index, so a scroll reads hand-arranged rather than stamped;
--   * gold / silver / bronze become butter / muted-plum / terracotta rims;
--   * the local player is marked with a soft ROSE GLOW, not the hard gold ring.
--
-- THE PAGE IS AUTHORED 48px TALLER THAN THE CLASSIC CARD, ON PURPOSE.
-- GPLayoutKit.Page spends 136px on header + scallop lip + gutters where the
-- arcade modal spends 88; +48 lands the content field at EXACTLY 1132x672 —
-- the classic geometry to the pixel. The lip is paid for by the CARD, never by
-- the data.
--
-- Rows deliberately carry NO shadow (the reasoning GPLayoutKit.StatRow states:
-- forty soft shadows in one scroll would eat the budget and turn a table into a
-- sticker sheet). Depth here is the alternating petal plus the deepened-tint
-- rim. The one glow on the page belongs to the local player.
-- ========================================================================

local GP_PAGE_GROW = 48 -- see the note above: content lands at 1132x672
local GP_TAB_H = 48
local GP_TAB_GAP = 12
local GP_PODIUM_Y = 64
local GP_PODIUM_H = 208
local GP_ROWS_Y = 288
local GP_ROW_H = 52
local GP_ROW_GAP = 6
local GP_LOCAL_H = 60
local GP_SCROLL_PAD = 10 -- keeps the local-row glow clear of the clip edge
local GP_AVATAR = 38
local GP_AVATAR_X = 100
local GP_NAME_X = GP_AVATAR_X + GP_AVATAR + 14
local GP_VALUE_W = 190
local GP_PIP = 36

-- A glaze WASH: the identity colour pulled toward cream so ink reads on it.
local function gpWash(theme: Types.UITheme, color: Color3, amount: number): Color3
	return color:Lerp(theme.Colors.Background, amount)
end

-- Pack law 5: no all-caps copy. Board titles arrive SHOUTED ("MOST WINS") from
-- the data feed, so they are re-cased here rather than at the source — the
-- classic and AC branches must keep rendering them exactly as supplied.
--
-- Only a FULLY uppercase string is touched, matching the gpCopy in the five
-- sibling screens: a feed that already sends mixed-case ("Most Wins", "PvP
-- Kills") is deliberate copy and passes through verbatim rather than being
-- flattened to "Pvp Kills".
local function titleCaseWords(text: string): string
	if text == "" or string.find(text, "<", 1, true) or text ~= string.upper(text) then
		return text -- RichText markup and already-cased copy are left alone
	end
	return (string.gsub(string.lower(text), "(%a[\'%a]*)", function(word: string): string
		return string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2)
	end))
end

-- The identity colour taken to INK DEPTH (two passes of the pack's own hue-
-- preserving Deepen). One pass leaves butter at ~3:1 on blush, which is under
-- the bar for a value numeral; two lands every board accent past 6:1 while
-- still being recognisably that board's hue. Doc §3.3 colour-as-identity is
-- kept; the pack's measured-contrast rule is kept too.
local function gpInkAccent(theme: Types.UITheme, accent: Color3): Color3
	return GPLayoutKit.Deepen(theme, GPLayoutKit.Deepen(theme, accent, 1), 1)
end

-- IconArchive's GLYPH fallback is born pure-white with a black text stroke —
-- both banned outright by this pack. Recolour it to ink; a real ImageLabel is
-- left alone (the flat-cartoon set is full colour by design).
local function gpIcon(theme: Types.UITheme, parent: Instance, key: string, sizePx: number, query: any?): GuiObject
	local icon = IconArchive.Image(parent, key, sizePx, query)
	if icon:IsA("TextLabel") then
		icon.TextColor3 = theme.Colors.TextPrimary
		icon.TextStrokeTransparency = 1
	end
	return icon
end

-- The GP headshot medallion. Deliberately NOT the classic avatarCircle above:
-- that one calls UIChrome.Stroke, and under this pack's Chrome policy
-- (StrokeFollowsAccent = false) that resolves to a BLACK stroke, which would
-- break pack law 1 on every single row. Same thumbnail fetch, same icon-first
-- fallback chain (doc §10); soft deepened-tint rim instead of the black rim.
local function gpAvatar(theme: Types.UITheme, parent: Instance, userId: number, sizePx: number, ring: Color3?): Frame
	local wellFill = theme.Colors.Surface
	local holder = UIStyler.Frame("Avatar")
	holder.BackgroundColor3 = wellFill
	holder.Size = UDim2.fromOffset(sizePx, sizePx)
	holder.ClipsDescendants = true
	UIStyler.Corner(theme.Radii.Pill).Parent = holder
	holder.Parent = parent
	local rim = GPLayoutKit.SoftStroke(theme, holder, ring or wellFill)
	if ring then
		-- A podium rim is IDENTITY, so it goes fully opaque and keeps its hue.
		rim.Color = GPLayoutKit.Deepen(theme, ring, 0.5)
		rim.Transparency = 0
	end

	local glyph = gpIcon(theme, holder, "player", math.floor(sizePx * 0.6))
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.5)

	local photo = Instance.new("ImageLabel")
	photo.Name = "Headshot"
	photo.BackgroundTransparency = 1
	photo.ScaleType = Enum.ScaleType.Crop
	photo.Size = UDim2.fromScale(1, 1)
	photo.Visible = false
	photo.Parent = holder

	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		end)
		if ok and typeof(content) == "string" and content ~= "" and holder.Parent then
			photo.Image = content
			photo.Visible = true
			glyph.Visible = false
		end
	end)

	return holder
end

function LeaderboardScreen:_BuildGPLayout()
	local theme = self:GetTheme()

	local page = GPLayoutKit.Page(theme, self.Root, {
		titleText = "Leaderboards",
		subtitleText = "Who is firing the finest ware this week",
		sizePx = Vector2.new(CARD.X, CARD.Y + GP_PAGE_GROW),
		onClose = function()
			self.ScreenController:HideScreen("leaderboard")
		end,
	})
	-- _OnShow pops self._modal.content in every layout; under GP that is the
	-- page's content field.
	self._modal = { content = page.content } :: any
	self._gpShadows = page.shadows
	-- TWO MORE sinks, for the two things that are torn down and rebuilt at
	-- runtime. Parked in the page sink their handles would accumulate — one
	-- plinth set per tab click, one tab set per Update — and walk the budget
	-- counter up with nothing ever bringing it back down. Each is released at
	-- the top of the render that refills it.
	self._gpTabShadows = {}
	self._gpBoardShadows = {}
	local content = page.content

	local tabRow = UIStyler.Frame("Tabs")
	tabRow.BackgroundTransparency = 1
	tabRow.Size = UDim2.new(1, 0, 0, GP_TAB_H)
	tabRow.Parent = content
	self._tabRow = tabRow

	local podium = UIStyler.Frame("Podium")
	podium.BackgroundTransparency = 1
	podium.Position = UDim2.fromOffset(0, GP_PODIUM_Y)
	podium.Size = UDim2.new(1, 0, 0, GP_PODIUM_H)
	podium.Parent = content
	self._podium = podium

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Rows"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	-- Explicit: a leaking scroll viewport is a known past bug in this repo.
	scroll.ClipsDescendants = true
	scroll.Position = UDim2.fromOffset(0, GP_ROWS_Y)
	scroll.Size = UDim2.new(1, 0, 0, CONTENT_H - GP_ROWS_Y - GP_LOCAL_H - 12)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = theme.Colors.Primary
	scroll.Parent = content
	UIStyler.ListLayout({
		Padding = UDim.new(0, GP_ROW_GAP), -- petal plates need air; zebra is gone
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	}).Parent = scroll
	-- Inset so a petal corner (and any glow) is not sliced at the clip edge.
	UIStyler.PaddingXY(GP_SCROLL_PAD, GP_SCROLL_PAD).Parent = scroll
	self._scroll = scroll

	-- The pinned local row lives OUTSIDE the scroll so it is always visible.
	local localFill = theme.Colors.SurfaceRaised
	local localRow = UIStyler.Frame("LocalRow")
	localRow.BackgroundColor3 = localFill
	localRow.BackgroundTransparency = 0
	localRow.AnchorPoint = Vector2.new(0, 1)
	localRow.Position = UDim2.new(0, GP_SCROLL_PAD, 1, -4)
	localRow.Size = UDim2.new(1, -GP_SCROLL_PAD * 2, 0, GP_LOCAL_H)
	localRow.Parent = content
	GPLayoutKit.Petal(theme, localRow, 0)
	GPLayoutKit.SoftStroke(theme, localRow, theme.Colors.Primary)
	self._localRowFrame = localRow
	-- THE mark: a soft rose aura, not a harsh highlight (the brief's rule and
	-- the pack's own "featured" grammar). Retinted per board in _GPRenderBoard.
	self._gpLocalGlow = GPLayoutKit.Glow(theme, localRow, theme.Colors.Primary, self._gpShadows)

	self:_BuildTabs()
	self:_RenderBoard()
end

function LeaderboardScreen:_GPBuildTabs()
	local theme = self:GetTheme()
	GPLayoutKit.ReleaseShadows(self._gpTabShadows)
	for _, child in self._tabRow:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(self._tabs)

	local count = math.max(1, #self._boards)
	local width = math.floor((CONTENT_W - GP_TAB_GAP * (count - 1)) / count)

	for index, board in self._boards do
		local accent = accentColor(theme, board.accent)

		-- The button stays TRANSPARENT and the fill lives on a chip child:
		-- UIStyleEnforcer backstops any SOLID GuiButton with a BLACK 2px stroke,
		-- which would violate pack law 1 on sight.
		local root = Instance.new("TextButton")
		root.Name = "Tab_" .. board.id
		root.BackgroundTransparency = 1
		root.Text = ""
		root.AutoButtonColor = false
		root.Position = UDim2.fromOffset((index - 1) * (width + GP_TAB_GAP), 0)
		root.Size = UDim2.fromOffset(width, GP_TAB_H)
		root.Parent = self._tabRow

		local surface = UIStyler.Frame("Surface")
		surface.BackgroundColor3 = theme.Colors.Surface
		surface.Size = UDim2.fromScale(1, 1)
		surface.Parent = root
		-- Alternating petal: adjacent chips mirror so the row reads arranged.
		GPLayoutKit.Petal(theme, surface, index)
		local stroke = GPLayoutKit.SoftStroke(theme, surface, theme.Colors.Surface)
		local shadow = GPLayoutKit.Shadow(theme, surface, "sm", self._gpTabShadows, theme.Colors.Surface)

		-- The identity PIP: this board's accent at full strength, shown whether
		-- the tab is selected or not, so colour-as-identity survives resting.
		local pip = UIStyler.Frame("Pip")
		pip.BackgroundColor3 = accent
		pip.AnchorPoint = Vector2.new(0, 0.5)
		pip.Position = UDim2.new(0, 14, 0.5, 0)
		pip.Size = UDim2.fromOffset(14, 14)
		UIStyler.Corner(theme.Radii.Pill).Parent = pip
		pip.Parent = surface

		-- Title Case, not the source's shouted caps: pack law 5.
		local label = GPLayoutKit.Text(theme, theme.TextSizes.Button, theme.Colors.TextPrimary, "Label")
		label.Text = titleCaseWords(board.title)
		label.RichText = false
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Position = UDim2.fromOffset(36, 0)
		label.Size = UDim2.new(1, -46, 1, 0)
		label.Parent = surface

		local underline = UIStyler.Frame("Underline")
		underline.BackgroundColor3 = theme.Colors.Accent
		underline.AnchorPoint = Vector2.new(0.5, 1)
		underline.Position = UDim2.new(0.5, 0, 1, -6)
		underline.Size = UDim2.new(0.62, 0, 0, 4)
		underline.Visible = false
		UIStyler.Corner(theme.Radii.Pill).Parent = underline
		underline.Parent = surface

		root.Activated:Connect(function()
			self:_SelectBoard(index)
		end)
		UIChrome.Animate(theme, root, surface)

		-- Same record shape the classic path stores, so _SelectBoard's Pulse
		-- (self._tabs[index].surface) keeps working untouched under GP.
		table.insert(self._tabs, {
			surface = surface,
			stroke = stroke,
			label = label,
			accent = accent,
			shadow = shadow,
			underline = underline,
		} :: any)
	end

	self:_PaintTabs()
end

-- Selected reads FORWARD: the board's accent washed toward cream (so ink still
-- measures), a butter underline, an opaque rim and a hue-matched shadow that
-- retints with the fill. Idle chips stay blush. No default-blue recolour, and
-- no near-white text anywhere.
function LeaderboardScreen:_GPPaintTabs()
	local theme = self:GetTheme()
	for index, entry in self._tabs do
		-- The GP record carries two fields beyond the classic tab shape (its
		-- shadow handle and its underline), so it is read through `any` rather
		-- than widening the declared _tabs type the classic path relies on.
		local tab: any = entry
		local active = index == self._activeIndex
		local fill = if active then gpWash(theme, tab.accent, 0.42) else theme.Colors.Surface
		local deep = GPLayoutKit.Deepen(theme, fill, 1)
		tab.surface.BackgroundColor3 = fill
		tab.stroke.Color = deep
		tab.stroke.Transparency = if active then 0.1 else 0.35
		if tab.shadow then
			tab.shadow.Instance.Color = deep
		end
		tab.label.TextColor3 = if active then theme.Colors.TextPrimary else theme.Colors.TextSecondary
		tab.label.TextTransparency = 0
		if tab.underline then
			tab.underline.Visible = active
		end
	end
end

-- One podium column, GP grammar: a petal plinth washed in the board accent,
-- the ringed medallion above it and the rank pip straddling the two. Every
-- classic data point survives — rank, headshot, name and the formatted value.
function LeaderboardScreen:_GPBuildPodiumSlot(slot: any, row: Row, accent: Color3)
	local theme = self:GetTheme()
	local ring = ringColor(theme, slot.rank)
	local plinthFill = gpWash(theme, accent, 0.62)

	local pedestal = UIStyler.Frame("Pedestal" .. slot.rank)
	pedestal.BackgroundColor3 = plinthFill
	pedestal.AnchorPoint = Vector2.new(0.5, 1)
	pedestal.Position = UDim2.fromOffset(slot.x, GP_PODIUM_H)
	pedestal.Size = UDim2.fromOffset(slot.pedestalW, slot.pedestalH)
	pedestal.Parent = self._podium
	GPLayoutKit.Petal(theme, pedestal, slot.rank)
	GPLayoutKit.SoftStroke(theme, pedestal, plinthFill)
	GPLayoutKit.Shadow(theme, pedestal, "sm", self._gpBoardShadows, plinthFill)
	-- The scalloped lip reads as the plinth's glazed foot. "Bottom" is the one
	-- unrotated edge, so it is safe anywhere (GPLayoutKit's clipping caveat).
	GPLayoutKit.Scallop(theme, pedestal, "Bottom", plinthFill)

	local name = GPLayoutKit.Text(theme, theme.TextSizes.Body + 2, theme.Colors.TextPrimary, "Name")
	name.Text = row.name
	name.RichText = false
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(10, 6)
	name.Size = UDim2.new(1, -20, 0, 24)
	name.Parent = pedestal

	local value = GPLayoutKit.NumberText(theme, slot.valueSize, gpInkAccent(theme, accent), "Value")
	value.Text = formatValue(row.value)
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.Position = UDim2.fromOffset(10, 30)
	value.Size = UDim2.new(1, -20, 0, slot.valueSize + 6)
	value.Parent = pedestal

	local avatarBottom = GP_PODIUM_H - slot.pedestalH - 12
	local avatar = gpAvatar(theme, self._podium, row.userId, slot.avatar, ring)
	avatar.AnchorPoint = Vector2.new(0.5, 1)
	avatar.Position = UDim2.fromOffset(slot.x, avatarBottom)
	if slot.rank == 1 then
		-- The winner blooms rather than falls into shade (GPLayoutKit.Glow).
		GPLayoutKit.Glow(theme, avatar, ring, self._gpBoardShadows)
	end

	local badge = UIStyler.Frame("Rank" .. slot.rank)
	badge.BackgroundColor3 = ring
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.fromOffset(slot.x, avatarBottom)
	badge.Size = UDim2.fromOffset(GP_PIP, GP_PIP)
	badge.Parent = self._podium
	UIStyler.Corner(theme.Radii.Pill).Parent = badge
	GPLayoutKit.SoftStroke(theme, badge, ring)

	-- Ink on a light pip. The classic path uses Arcade.NearBlack, which this
	-- pack redefines to a NEAR-WHITE pink — it would vanish on butter.
	local numeral = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "Numeral")
	numeral.Text = tostring(slot.rank)
	numeral.Size = UDim2.fromScale(1, 1)
	numeral.Parent = badge
end

-- One board row, GP grammar. FOUR columns, exactly as classic: rank, circular
-- headshot, name, formatted value. `highlight` paints the pinned local row.
function LeaderboardScreen:_GPBuildRow(parent: Instance, row: Row, index: number, accent: Color3, highlight: boolean): Frame
	local theme = self:GetTheme()
	local height = if highlight then GP_LOCAL_H else GP_ROW_H

	local frame: Frame
	if highlight then
		frame = parent :: Frame
	else
		local fill = if index % 2 == 1 then theme.Colors.SurfaceRaised else theme.Colors.Surface
		frame = UIStyler.Frame("Row" .. index)
		frame.BackgroundColor3 = fill
		frame.BackgroundTransparency = 0
		-- The scroll's UIPadding already inset both edges; this only clears the
		-- scrollbar.
		frame.Size = UDim2.new(1, -SCROLLBAR_RESERVE, 0, height)
		frame.LayoutOrder = index
		frame.Parent = parent
		-- Alternating mirror, so a long scroll reads hand-arranged. No shadow
		-- per row: see the budget note in this section's header.
		GPLayoutKit.Petal(theme, frame, index)
		GPLayoutKit.SoftStroke(theme, frame, fill)
	end

	local rank = GPLayoutKit.NumberText(theme, theme.TextSizes.Subtitle, theme.Colors.TextSecondary, "Rank")
	rank.Text = "#" .. tostring(row.rank)
	rank.TextXAlignment = Enum.TextXAlignment.Left
	rank.Position = UDim2.fromOffset(16, 0)
	rank.Size = UDim2.fromOffset(80, height)
	rank.Parent = frame

	-- One avatar size and one name column on both the list rows and the pinned
	-- local row, so the two never drift out of alignment.
	local avatar = gpAvatar(theme, frame, row.userId, GP_AVATAR, if highlight then theme.Colors.Primary else nil)
	avatar.AnchorPoint = Vector2.new(0, 0.5)
	avatar.Position = UDim2.new(0, GP_AVATAR_X, 0.5, 0)

	local name = GPLayoutKit.Text(theme, theme.TextSizes.Body + 2, theme.Colors.TextPrimary, "Name")
	name.Text = if highlight then row.name .. " (you)" else row.name
	name.RichText = false
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(GP_NAME_X, 0)
	name.Size = UDim2.new(1, -(GP_NAME_X + GP_VALUE_W + 40), 0, height)
	name.Parent = frame

	local value = GPLayoutKit.NumberText(theme, theme.TextSizes.Subtitle, gpInkAccent(theme, accent), "Value")
	value.Text = formatValue(row.value)
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.new(1, -18, 0, 0)
	value.Size = UDim2.fromOffset(GP_VALUE_W, height)
	value.Parent = frame

	return frame
end

function LeaderboardScreen:_GPRenderBoard()
	local theme = self:GetTheme()
	local board = self:_ActiveBoard()
	if not board then
		return
	end
	local accent = accentColor(theme, board.accent)

	-- Release before the rebuild, not after: these handles own the budget count
	-- of the plinth shadows the loop below is about to destroy.
	GPLayoutKit.ReleaseShadows(self._gpBoardShadows)

	for _, child in self._podium:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for _, child in self._scroll:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for _, child in self._localRowFrame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	for _, slot in PODIUM_SLOTS do
		local row = board.rows[slot.rank]
		if row then
			self:_GPBuildPodiumSlot(slot, row, accent)
		end
	end

	-- The podium already tells the top-3 story; the list carries from 4 down —
	-- identical to the classic path, so no row is lost in either direction.
	for index = 4, #board.rows do
		self:_GPBuildRow(self._scroll, board.rows[index], index, accent, false)
	end

	self:_GPBuildRow(self._localRowFrame, self:_LocalRow(board), 0, accent, true)
	-- The local aura carries the ACTIVE BOARD's identity, so switching boards
	-- moves the whole page's colour mass together.
	if self._gpLocalGlow then
		self._gpLocalGlow.Instance.Color = gpWash(theme, accent, 0.1)
	end
	self._scroll.CanvasPosition = Vector2.new(0, 0)
end

-- Shadow handles are budget-registered; a destroyed GuiObject alone leaves the
-- counter high, so the sink is released here (and on Destroy).
function LeaderboardScreen:_OnTeardown()
	GPLayoutKit.ReleaseShadows(self._gpTabShadows)
	GPLayoutKit.ReleaseShadows(self._gpBoardShadows)
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	self._gpTabShadows = nil
	self._gpBoardShadows = nil
	self._gpShadows = nil
	self._gpLocalGlow = nil
end

function LeaderboardScreen:Destroy()
	self:_OnTeardown()
	UIScreenBase.Destroy(self)
end

return LeaderboardScreen
