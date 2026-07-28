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
--
-- GP (theme.LayoutKit == "GP") re-tells the page as the STUDIO LEDGER in the
-- matte dialect: cream paper, clay speckle, sage hairlines, and every stat as
-- a GPLayoutKit.StatRow carrying its own magnitude bar. See the GP section at
-- the bottom of this file. Same four hero tiles, same four groups, same five
-- rows each, same formatter — nothing is dropped for the sake of pastel.

local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIScreenBase = require(script.Parent.UIScreenBase)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local GPStudioKit = require(script.Parent.Parent.Framework.GPStudioKit)

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
	-- GP layout language: the studio ledger (see _BuildGPLayout below); the
	-- classic arcade modal build stays untouched.
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end
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
	if self:LayoutKit() == "GP" then
		self:_GPRenderHero()
		self:_GPRenderGroups()
		return
	end
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

-- ========================================================================
-- GP layout (theme.LayoutKit == "GP") — THE STUDIO LEDGER, in the pack's
-- MATTE dialect: cream paper, faint clay speckle, sage hairline rules, and
-- not one shimmer, because this is a page you read rather than admire.
--
-- ANTI-CONDESCENSION LEDGER for this screen — what the arcade build shows and
-- what this one shows, side by side:
--   * 4 hero tiles  -> 4 hero tiles (icon, value, label: all three kept)
--   * 4 stat groups -> 4 stat groups, in order, titles intact
--   * 5 rows each   -> 5 rows each (icon, label, value: all three kept)
--   * one formatter -> THE SAME formatter. formatValue() is called verbatim
--     and its output is handed to the kit row as `valueText`, so H:MM:SS
--     durations, 1.2K/3.4M counts and 49.3% rates survive at full precision
--     rather than being re-derived from the dialect's one-decimal float.
--   * hairline dividers between rows -> the sage hairline, same cadence.
-- The one difference is ADDITIVE: every row now carries a magnitude bar
-- measured against the largest value in its own group, so a column of
-- numbers also reads as a shape. Nothing was removed to pay for it.
--
-- The GP page is the classic card grown by 48px in Y — exactly the difference
-- between UIChrome.ModalCard's 88px of chrome and GPLayoutKit.Page's 136
-- (8 gutter + 76 header + 18 scallop lip + 14 gap + 20 foot) — so CONTENT_W
-- and CONTENT_H at the top of this file describe the GP content box byte for
-- byte. Nothing below has less room than it had.
-- ========================================================================

local GP_PAGE = Vector2.new(CARD_W, CARD_H + 48)
local GP_HERO_H = 132
local GP_GROUPS_Y = GP_HERO_H + 18
-- A row SLOT is taller than the row it holds: the kit row ends in its 6px
-- magnitude bar, and a hairline drawn flush against that bar would read as a
-- second rule. The 8px difference is the breathing room between them.
local GP_ROW_H = 46
local GP_ROW_BODY_H = 38
local GP_TITLE_H = 30
local GP_PANEL_PAD = 10
local GP_SCROLL_PAD = 10
-- The kit's value column is authored for short numerals; a H:MM:SS duration
-- needs more. Widen it rather than truncate — truncating a number is the
-- precision loss law 6 forbids.
local GP_VALUE_WIDEN = 46

-- One accent per group, cycling the pack's own accent ladder, so the four
-- blocks read as four subjects instead of one long stripe.
local function gpGroupAccent(theme: any, index: number): Color3
	local accents = theme.Arcade.ShopAccents
	return accents[((index - 1) % #accents) + 1]
end

function StatsScreen:_BuildGPLayout()
	local theme = self:GetTheme()

	local page = GPLayoutKit.Page(theme, self.Root, {
		titleText = "Statistics",
		subtitleText = "Everything the studio has kept count of.",
		sizePx = GP_PAGE,
		onClose = function()
			self.ScreenController:HideScreen("stats")
		end,
	})
	self._gpShadows = page.shadows
	-- _OnShow pops self._modal.content in every layout; under GP that is the
	-- page's content region, and `card` is what the on-screen gate reads.
	self._modal = { content = page.content, card = page.panel } :: any
	local content = page.content

	-- The header counter states the ledger's size, which the arcade build
	-- never printed — an addition, not a substitution.
	local total = 0
	for _, group in self._groups do
		total += #group.stats
	end
	self._gpCounter = GPStudioKit.Chip(theme, page.topRight, {
		text = string.format("%d tracked", total),
		tone = theme.Colors.SurfaceRaised,
		iconKey = "stats",
		iconPx = 22,
		golden = true,
		pill = true,
		sizeUDim = UDim2.fromOffset(168, 40),
		layoutOrder = 1,
		name = "TrackedCount",
	})

	local heroRow = UIStyler.Frame("GPHeroTiles")
	heroRow.BackgroundTransparency = 1
	heroRow.Size = UDim2.new(1, 0, 0, GP_HERO_H)
	heroRow.Parent = content
	self._gpHeroRow = heroRow

	local scroll = GPStudioKit.Scroller(theme, content, {
		name = "GPGroups",
		padPx = GP_SCROLL_PAD,
	})
	scroll.Position = UDim2.fromOffset(0, GP_GROUPS_Y)
	scroll.Size = UDim2.new(1, 0, 0, CONTENT_H - GP_GROUPS_Y)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 18),
	}).Parent = scroll
	self._gpScroll = scroll

	self:_GPRenderHero()
	self:_GPRenderGroups()
end

function StatsScreen:_GPRenderHero()
	local theme = self:GetTheme()
	for _, child in self._gpHeroRow:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	for index, stat in self:_HeroStats() do
		if index > HERO_COUNT then
			break
		end
		-- Petal corners alternate by index so the four tiles read hand-placed.
		local tile = GPStudioKit.Paper(theme, self._gpHeroRow, {
			name = "GPHero" .. index,
			index = index,
			fill = theme.Colors.SurfaceRaised,
			shadow = "sm",
		}, self._gpShadows)
		tile.Position = UDim2.fromOffset((index - 1) * (HERO_W + HERO_GAP), 0)
		tile.Size = UDim2.fromOffset(HERO_W, GP_HERO_H)

		local icon = GPStudioKit.Icon(theme, tile, stat.icon or "stats", 34, { golden = true })
		icon.Position = UDim2.fromOffset(theme.Spacing.M, theme.Spacing.M)
		icon.ZIndex = 3

		-- TextScaled inside a size constraint rather than TextTruncate: a long
		-- duration shrinks to fit instead of losing its last digits.
		local value = GPLayoutKit.Text(theme, 32, theme.Colors.TextPrimary, "Value")
		value.Text = formatValue(stat.value, stat.format)
		value.TextXAlignment = Enum.TextXAlignment.Left
		value.TextScaled = true
		value.RichText = false
		value.Position = UDim2.fromOffset(theme.Spacing.M, 54)
		value.Size = UDim2.new(1, -theme.Spacing.M * 2, 0, 40)
		value.ZIndex = 3
		value.Parent = tile
		UIStyler.TextSizeConstraint(32, 16).Parent = value

		local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Label")
		label.Text = GPStudioKit.SoftCase(stat.label)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.RichText = false
		label.Position = UDim2.fromOffset(theme.Spacing.M, 98)
		label.Size = UDim2.new(1, -theme.Spacing.M * 2, 0, 22)
		label.ZIndex = 3
		label.Parent = tile
	end
end

function StatsScreen:_GPRenderGroups()
	for _, child in self._gpScroll:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for index, group in self._groups do
		self:_GPBuildGroup(group, index)
	end
end

function StatsScreen:_GPBuildGroup(group: Group, index: number)
	local theme = self:GetTheme()
	local accent = gpGroupAccent(theme, index)
	local panelHeight = #group.stats * GP_ROW_H + GP_PANEL_PAD * 2

	-- The scroller's UIPadding already insets its children's scale box, so the
	-- only thing left to subtract is the scrollbar: a full-width plate must
	-- never slide under the thumb.
	local block = UIStyler.Frame("GPGroup_" .. group.title)
	block.BackgroundTransparency = 1
	block.Size = UDim2.new(1, -SCROLLBAR, 0, GP_TITLE_H + 10 + panelHeight)
	block.LayoutOrder = index
	block.Parent = self._gpScroll

	local title = GPStudioKit.Heading(theme, block, group.title, {
		sizePx = theme.TextSizes.Subtitle,
		heightPx = GP_TITLE_H,
		name = "GroupTitle",
	})
	title.Size = UDim2.new(1, 0, 0, GP_TITLE_H)

	local panel = GPStudioKit.Paper(theme, block, {
		name = "GroupPaper",
		index = index,
		fill = theme.Studio.Card,
		shadow = "sm",
	}, self._gpShadows)
	panel.Position = UDim2.fromOffset(0, GP_TITLE_H + 10)
	panel.Size = UDim2.new(1, 0, 0, panelHeight)

	local rows = UIStyler.Frame("Rows")
	rows.BackgroundTransparency = 1
	rows.Position = UDim2.fromOffset(theme.Spacing.M, GP_PANEL_PAD)
	rows.Size = UDim2.new(1, -theme.Spacing.M * 2, 1, -GP_PANEL_PAD * 2)
	rows.ZIndex = 3
	rows.Parent = panel

	-- Every bar in a group is measured against that group's largest value, so
	-- the block reads as a shape as well as a column of numbers. Percentages
	-- are measured against 100 instead — a win rate's scale is not its
	-- neighbours'.
	local groupMax = 0
	for _, stat in group.stats do
		groupMax = math.max(groupMax, math.abs(stat.value))
	end

	for rowIndex, stat in group.stats do
		local isPercent = stat.format == "Percent"
		local row = GPStudioKit.StatLine(theme, rows, {
			label = stat.label,
			value = math.abs(stat.value),
			maxValue = if isPercent then 100 else math.max(groupMax, 1),
			valueText = formatValue(stat.value, stat.format),
			iconKey = stat.icon or "stats",
			iconPx = 22,
			accent = accent,
			heightPx = GP_ROW_BODY_H,
			widenPx = GP_VALUE_WIDEN,
			layoutOrder = rowIndex,
		})
		row.root.Position = UDim2.fromOffset(0, (rowIndex - 1) * GP_ROW_H)
		row.label.RichText = false
		row.value.RichText = false

		-- The sage hairline between rows, never after the last one — the same
		-- cadence the arcade build draws in pale grey.
		if rowIndex < #group.stats then
			local rule = GPStudioKit.Rule(theme, rows, { transparency = 0.3 })
			rule.Position = UDim2.fromOffset(0, rowIndex * GP_ROW_H - 4)
		end
	end
end

-- A style rebuild destroys the Gui, but UIShadow BUDGET counts live in
-- StyleKit.Capabilities and only fall when a handle is released.
function StatsScreen:_OnTeardown()
	GPStudioKit.ReleaseShadows(self._gpShadows)
	self._gpShadows = nil
	self._gpHeroRow = nil
	self._gpScroll = nil
	self._gpCounter = nil
end

return StatsScreen
