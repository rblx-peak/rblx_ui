--!strict
-- Statistics — Pottery Clash arcade family (doc §7.4). One modal card: a row
-- of hero stat tiles across the top, then a scrolling stack of titled groups
-- (Combat / Economy / Time / Social), each a near-black panel of stat rows —
-- icon + label left, value right in gold FredokaOne, hairline dividers between.
--
-- Every value is printed through one local formatter so the whole page reads
-- consistently: 1.2K / 3.4M for counts (the doc §9 leaderboard convention) and
-- H:MM:SS for durations. Hero tiles are DERIVED from the data (data.hero, or
-- the first stat of each group) so the page is a pure function of Show(data).
--
-- Layout is fixed px at the 1650×1020 baseline; UIScreenBase attaches the UIScale.

local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIScreenBase = require(script.Parent.UIScreenBase)

type Stat = { label: string, value: number, icon: string?, format: string? }
type Group = { title: string, stats: { Stat } }

local CARD_W, CARD_H = 940, 740
local CONTENT_W = CARD_W - 28
local CONTENT_H = CARD_H - 88
local SCROLLBAR = 8
local HERO_COUNT = 4
local HERO_GAP = 16
local HERO_W = (CONTENT_W - HERO_GAP * (HERO_COUNT - 1)) // HERO_COUNT
local HERO_H = 126
local GROUPS_Y = HERO_H + 16
local ROW_H = 44
local GROUP_TITLE_H = 30
local PANEL_PAD = 6

local DEMO_GROUPS: { Group } = {
	{
		title = "COMBAT",
		stats = {
			{ label = "Duels won", value = 1284, icon = "swords" },
			{ label = "Duels played", value = 2607, icon = "sword" },
			{ label = "Win rate", value = 49.3, icon = "trophy", format = "Percent" },
			{ label = "Best win streak", value = 17, icon = "fire" },
			{ label = "Perfect rounds", value = 96, icon = "star" },
		},
	},
	{
		title = "ECONOMY",
		stats = {
			{ label = "Cash earned", value = 3412000, icon = "cash" },
			{ label = "Cash spent", value = 2870400, icon = "cart" },
			{ label = "Bux earned", value = 14820, icon = "bux" },
			{ label = "Crates opened", value = 431, icon = "crate" },
			{ label = "Items traded", value = 78, icon = "trade" },
		},
	},
	{
		title = "TIME",
		stats = {
			{ label = "Time played", value = 462731, icon = "clock", format = "Time" },
			{ label = "Longest session", value = 19845, icon = "hourglass", format = "Time" },
			{ label = "Time at the wheel", value = 268412, icon = "settings", format = "Time" },
			{ label = "Days logged in", value = 214, icon = "calendar" },
			{ label = "Current streak", value = 12, icon = "bolt" },
		},
	},
	{
		title = "SOCIAL",
		stats = {
			{ label = "Friends made", value = 87, icon = "friends" },
			{ label = "Gifts sent", value = 349, icon = "gift" },
			{ label = "Gifts received", value = 262, icon = "heart" },
			{ label = "Parties joined", value = 156, icon = "players" },
			{ label = "Emotes used", value = 4120, icon = "sparkle" },
		},
	},
}

-- 1.2K / 3.4M for counts (doc §9 leaderboard convention).
local function short(value: number): string
	local magnitude = math.abs(value)
	if magnitude >= 1000000 then
		return string.format("%.1fM", value / 1000000)
	elseif magnitude >= 1000 then
		return string.format("%.1fK", value / 1000)
	end
	return tostring(math.floor(value))
end

-- One formatter for the whole page: durations read H:MM:SS (doc §11.3),
-- percents keep one decimal, everything else goes through `short`.
local function formatValue(value: number, format: string?): string
	if format == "Time" or format == "Duration" then
		local seconds = math.max(0, math.floor(value))
		return string.format("%d:%02d:%02d", seconds // 3600, (seconds % 3600) // 60, seconds % 60)
	elseif format == "Percent" then
		return string.format("%.1f%%", value)
	elseif format == "Raw" then
		return tostring(math.floor(value))
	end
	return short(value)
end

local StatsScreen = setmetatable({}, { __index = UIScreenBase })
StatsScreen.__index = StatsScreen

function StatsScreen.new()
	local self = UIScreenBase.new("StatsScreen", 6)
	self._groups = DEMO_GROUPS
	self._hero = nil :: { Stat }?
	return setmetatable(self, StatsScreen)
end

-- Hero tiles come from data.hero when supplied; otherwise the first stat of
-- each group headlines the page, so any dataset renders a full top row.
function StatsScreen:_HeroStats(): { Stat }
	if self._hero then
		return self._hero
	end
	local out: { Stat } = {}
	for _, group in self._groups do
		local first = group.stats[1]
		if first then
			table.insert(out, first)
		end
		if #out == HERO_COUNT then
			break
		end
	end
	return out
end

function StatsScreen:_BuildContent()
	local theme = self:GetTheme()

	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = "STATISTICS",
		sizePx = Vector2.new(CARD_W, CARD_H),
		onClose = function()
			self.ScreenController:HideScreen("stats")
		end,
	})
	self._modal = modal
	local content = modal.content

	local heroRow = UIStyler.Frame("HeroTiles")
	heroRow.BackgroundTransparency = 1
	heroRow.Size = UDim2.new(1, 0, 0, HERO_H)
	heroRow.Parent = content
	self._heroRow = heroRow

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Groups"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, GROUPS_Y)
	scroll.Size = UDim2.new(1, 0, 0, CONTENT_H - GROUPS_Y)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = SCROLLBAR
	scroll.ScrollBarImageColor3 = theme.Arcade.Gold
	scroll.Parent = content
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 18),
	}).Parent = scroll
	self._scroll = scroll

	self:_Render()
end

function StatsScreen:_Render()
	self:_RenderHero()
	self:_RenderGroups()
end

function StatsScreen:_RenderHero()
	local theme = self:GetTheme()
	for _, child in self._heroRow:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	for index, stat in self:_HeroStats() do
		if index > HERO_COUNT then
			break
		end
		local tile = UIStyler.Frame("Hero" .. index)
		tile.BackgroundColor3 = theme.Arcade.NearBlack
		tile.BackgroundTransparency = 0
		tile.Position = UDim2.fromOffset((index - 1) * (HERO_W + HERO_GAP), 0)
		tile.Size = UDim2.fromOffset(HERO_W, HERO_H)
		UIChrome.Stroke(theme, "Arcade").Parent = tile
		UIChrome.GlassGradient().Parent = tile
		tile.Parent = self._heroRow

		local icon = IconArchive.Image(tile, stat.icon or "stats", 34, { golden = true })
		icon.Position = UDim2.fromOffset(10, 10)

		local value = UIChrome.Text("Value", 38, theme.Arcade.SunburstGold)
		value.Text = formatValue(stat.value, stat.format)
		value.Position = UDim2.fromOffset(8, 40)
		value.Size = UDim2.new(1, -16, 0, 46)
		value.RichText = false
		value.TextTruncate = Enum.TextTruncate.AtEnd
		value.Parent = tile

		local label = UIChrome.Text("Label", 15, theme.Arcade.IceBlue)
		label.Text = string.upper(stat.label)
		label.Position = UDim2.fromOffset(8, 92)
		label.Size = UDim2.new(1, -16, 0, 22)
		label.RichText = false
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Parent = tile
	end
end

function StatsScreen:_RenderGroups()
	for _, child in self._scroll:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for index, group in self._groups do
		self:_BuildGroup(group, index)
	end
end

function StatsScreen:_BuildGroup(group: Group, index: number)
	local theme = self:GetTheme()
	local panelHeight = #group.stats * ROW_H + PANEL_PAD * 2

	local block = UIStyler.Frame("Group_" .. group.title)
	block.BackgroundTransparency = 1
	block.Size = UDim2.new(1, -SCROLLBAR, 0, GROUP_TITLE_H + 6 + panelHeight)
	block.LayoutOrder = index
	block.Parent = self._scroll

	local title = UIChrome.Text("Title", 22, theme.Arcade.Gold)
	title.Text = group.title
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Size = UDim2.new(1, 0, 0, GROUP_TITLE_H)
	title.Parent = block

	local panel = UIChrome.Panel(theme, "Arcade", "Panel")
	panel.Position = UDim2.fromOffset(0, GROUP_TITLE_H + 6)
	panel.Size = UDim2.new(1, 0, 0, panelHeight)
	panel.Parent = block

	for rowIndex, stat in group.stats do
		local row = UIStyler.Frame("Stat" .. rowIndex)
		row.BackgroundTransparency = 1
		row.Position = UDim2.fromOffset(0, PANEL_PAD + (rowIndex - 1) * ROW_H)
		row.Size = UDim2.new(1, 0, 0, ROW_H)
		row.Parent = panel

		local icon = IconArchive.Image(row, stat.icon or "stats", 26)
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 14, 0.5, 0)

		local label = UIChrome.Text("Label", 18, theme.Colors.TextPrimary)
		label.Text = stat.label
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Position = UDim2.fromOffset(52, 0)
		label.Size = UDim2.new(1, -240, 1, 0)
		label.RichText = false
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Parent = row

		local value = UIChrome.Text("Value", 22, theme.Arcade.SunburstGold)
		value.Text = formatValue(stat.value, stat.format)
		value.TextXAlignment = Enum.TextXAlignment.Right
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.new(1, -16, 0, 0)
		value.Size = UDim2.fromOffset(180, ROW_H)
		value.RichText = false
		value.Parent = row

		-- Hairline divider between rows (never after the last one).
		if rowIndex < #group.stats then
			local divider = UIStyler.Frame("Divider")
			divider.BackgroundColor3 = theme.Arcade.RulerTick
			divider.BackgroundTransparency = 0.78
			divider.AnchorPoint = Vector2.new(0, 1)
			divider.Position = UDim2.new(0, 14, 1, 0)
			divider.Size = UDim2.new(1, -28, 0, 1)
			divider.Parent = row
		end
	end
end

function StatsScreen:_Apply(data: any)
	if data.groups then
		self._groups = data.groups
	end
	if data.hero then
		self._hero = data.hero
	end
end

-- _EnsureBuilt has already rendered with the data the screen was holding, so
-- only a fresh payload re-renders here.
function StatsScreen:_OnShow(data: any?)
	if data then
		self:_Apply(data)
		self:_Render()
	end
	if self._modal then
		UIChrome.PopIn(self:GetTheme(), self._modal.content)
	end
end

function StatsScreen:Update(data: any)
	if not data then
		return
	end
	self:_Apply(data)
	if self._built then
		self:_Render()
	end
end

return StatsScreen
