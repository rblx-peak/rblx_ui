--!strict
-- Faction reputation — Pottery Clash arcade family (doc §7.4).
-- One modal card, one scrolling list: a row per faction carrying its icon in a
-- near-black well ringed in the faction's ACCENT colour (colour = identity,
-- doc §3.3 — the same rule that gives each leaderboard its own accent), the
-- current rank title, the gold reputation ruler through the current rank, and
-- a preview strip of the next three rank rewards (future ones dim in place
-- with a lock, §11.2 — never removed).
--
-- Selecting a faction expands a detail band under its row listing every rank
-- with green checks on the earned ones; the open faction's row wears the gold
-- selection ring (§4.3 selection-is-a-ring). Rows are rebuilt on toggle, so
-- the list's CanvasPosition is captured and re-applied after the layout pass
-- (AutomaticCanvasSize only catches up a frame later).

local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIProgressBarComponent = require(script.Parent.Parent.Components.UIProgressBarComponent)

type RankStep = { title: string, rep: number }
type Reward = { icon: string, locked: boolean? }
type Faction = {
	id: string,
	name: string,
	icon: string,
	accent: Color3,
	rank: string,
	rankIndex: number,
	rep: number,
	repToNext: number,
	ranks: { RankStep },
	rewards: { Reward },
}
type FactionData = { factions: { Faction } }

local CARD_W, CARD_H = 1140, 700
local CONTENT_W = CARD_W - 28
local CONTENT_H = CARD_H - 88
local LIST_Y = 30
local LIST_H = CONTENT_H - LIST_Y
local ROW_H = 122
local ROW_GAP = 10
local BAND_ROW_H = 34
local CHIP = 68
local SCROLLBAR = 8

-- The shared reputation ladder every demo faction climbs.
local function demoRanks(): { RankStep }
	return {
		{ title = "STRANGER", rep = 0 },
		{ title = "NEUTRAL", rep = 500 },
		{ title = "FRIENDLY", rep = 1500 },
		{ title = "HONORED", rep = 3000 },
		{ title = "REVERED", rep = 6000 },
		{ title = "EXALTED", rep = 12000 },
	}
end

local function demoFactions(): { Faction }
	return {
		{
			id = "guild", name = "POTTERS' GUILD", icon = "wheel",
			accent = Color3.fromRGB(70, 150, 255),
			rank = "HONORED", rankIndex = 4, rep = 2400, repToNext = 6000,
			ranks = demoRanks(),
			rewards = { { icon = "ticket" }, { icon = "crate", locked = true }, { icon = "crown", locked = true } },
		},
		{
			id = "wardens", name = "KILN WARDENS", icon = "fire",
			accent = Color3.fromRGB(240, 70, 70),
			rank = "FRIENDLY", rankIndex = 3, rep = 950, repToNext = 1500,
			ranks = demoRanks(),
			rewards = { { icon = "key" }, { icon = "sparkle", locked = true }, { icon = "chest", locked = true } },
		},
		{
			id = "merchants", name = "GLAZE MERCHANTS", icon = "cart",
			accent = Color3.fromRGB(245, 205, 55),
			rank = "NEUTRAL", rankIndex = 2, rep = 350, repToNext = 1000,
			ranks = demoRanks(),
			rewards = { { icon = "bag" }, { icon = "ticket", locked = true }, { icon = "crate", locked = true } },
		},
		{
			id = "divers", name = "THE SLIP DIVERS", icon = "water",
			accent = Color3.fromRGB(120, 235, 205),
			rank = "REVERED", rankIndex = 5, rep = 4800, repToNext = 6000,
			ranks = demoRanks(),
			rewards = { { icon = "potion" }, { icon = "medal", locked = true }, { icon = "crown", locked = true } },
		},
	}
end

local function comma(n: number): string
	local formatted = tostring(math.floor(n))
	while true do
		local replaced
		formatted, replaced = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then
			break
		end
	end
	return formatted
end

local function tintIcon(icon: GuiObject, color: Color3)
	if icon:IsA("ImageLabel") then
		icon.ImageColor3 = color
	elseif icon:IsA("TextLabel") then
		icon.TextColor3 = color
	end
end

local function dimIcon(icon: GuiObject, transparency: number)
	if icon:IsA("ImageLabel") then
		icon.ImageTransparency = transparency
	elseif icon:IsA("TextLabel") then
		icon.TextTransparency = transparency
	end
end

local FactionScreen = setmetatable({}, { __index = UIScreenBase })
FactionScreen.__index = FactionScreen

function FactionScreen.new()
	local self = UIScreenBase.new("FactionScreen", 6)
	self._data = { factions = demoFactions() } :: FactionData
	self._expandedId = nil :: string?
	self._rowComponents = {} :: { any }
	return setmetatable(self, FactionScreen)
end

function FactionScreen:_BuildContent()
	local theme = self:GetTheme()

	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = "FACTIONS",
		sizePx = Vector2.new(CARD_W, CARD_H),
		onClose = function()
			self.ScreenController:HideScreen("faction")
		end,
	})
	self._modal = modal
	local content = modal.content

	local hint = UIChrome.BodyText("Hint", 15, theme.Arcade.IceBlue)
	hint.Text = "Earn reputation from commissions and contracts. Select a faction to see its ranks."
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.Size = UDim2.new(1, 0, 0, 20)
	hint.Parent = content

	local list = Instance.new("ScrollingFrame")
	list.Name = "FactionList"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(0, LIST_Y)
	list.Size = UDim2.new(1, 0, 0, LIST_H)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = SCROLLBAR
	list.ScrollBarImageColor3 = theme.Arcade.Gold
	list.Parent = content
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, ROW_GAP),
	}).Parent = list
	self._list = list

	self:_RenderList()
end

function FactionScreen:_RenderList()
	local keepPosition = self._list.CanvasPosition
	for _, component in self._rowComponents do
		component:Destroy()
	end
	table.clear(self._rowComponents)
	for _, child in self._list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	for index, faction in (self._data :: FactionData).factions do
		self:_BuildFaction(faction, index)
	end

	-- Restore after the layout pass: the immediate write clamps against the
	-- stale (smaller) canvas, so re-apply once the rows have been measured.
	self._list.CanvasPosition = keepPosition
	task.defer(function()
		if self._list and self._list.Parent then
			self._list.CanvasPosition = keepPosition
		end
	end)
end

function FactionScreen:_BuildFaction(faction: Faction, index: number)
	local theme = self:GetTheme()
	local expanded = self._expandedId == faction.id
	local bandH = 16 + #faction.ranks * BAND_ROW_H
	local containerH = expanded and (ROW_H + 6 + bandH) or ROW_H

	local container = UIStyler.Frame("Faction_" .. faction.id)
	container.BackgroundTransparency = 1
	container.Size = UDim2.new(1, -SCROLLBAR, 0, containerH)
	container.LayoutOrder = index
	container.Parent = self._list

	-- The row: a fixed footprint whose surface carries the hover/press scale,
	-- so toggling never reflows its list neighbours mid-spring.
	local row = UIStyler.Frame("Row")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, ROW_H)
	row.Parent = container

	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 1
	hit.Parent = row

	local surface = UIStyler.Frame("Surface")
	surface.BackgroundColor3 = theme.Arcade.Row
	surface.BackgroundTransparency = theme.Arcade.RowTransparency
	surface.AnchorPoint = Vector2.new(0.5, 0.5)
	surface.Position = UDim2.fromScale(0.5, 0.5)
	surface.Size = UDim2.fromScale(1, 1)
	surface.ZIndex = 2
	UIChrome.Stroke(theme, "Arcade", expanded and "Selection" or "Panel").Parent = surface
	UIChrome.GlassGradient().Parent = surface
	surface.Parent = row

	-- Icon well: near-black, ringed in the faction's accent — colour IS the
	-- faction's identity (doc §3.3), so this ring deliberately bypasses the
	-- black-stroke policy the way leaderboard accents do.
	local well = UIStyler.Frame("Well")
	well.BackgroundColor3 = theme.Arcade.NearBlack
	well.BackgroundTransparency = 0
	well.Position = UDim2.fromOffset(16, 19)
	well.Size = UDim2.fromOffset(84, 84)
	UIStyler.Stroke(faction.accent, 3, 0).Parent = well
	UIChrome.GlassGradient().Parent = well
	well.Parent = surface
	local icon = IconArchive.Image(well, faction.icon, 56)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)

	local name = UIChrome.Text("Name", 24, theme.Colors.TextPrimary)
	name.Text = faction.name
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Position = UDim2.fromOffset(120, 16)
	name.Size = UDim2.fromOffset(330, 28)
	name.RichText = false
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Parent = surface

	local rank = UIChrome.Text("Rank", 18, theme.Arcade.Gold)
	rank.Text = faction.rank
	rank.TextXAlignment = Enum.TextXAlignment.Left
	rank.Position = UDim2.fromOffset(120, 50)
	rank.Size = UDim2.fromOffset(330, 22)
	rank.Parent = surface

	local ruler = UIProgressBarComponent.new()
	ruler:Create(surface, {
		value = faction.rep,
		maxValue = math.max(faction.repToNext, 1),
		size = UDim2.fromOffset(300, 24),
		position = UDim2.fromOffset(120, 82),
	})
	table.insert(self._rowComponents, ruler)

	-- Comma-formatted rep readout beside the ruler (the bar's own overlay
	-- prints plain integers; the spec wants "2,400 / 6,000").
	local repText = UIChrome.Text("Rep", 16, theme.Arcade.SunburstGold)
	repText.Text = string.format("%s / %s", comma(faction.rep), comma(faction.repToNext))
	repText.TextXAlignment = Enum.TextXAlignment.Left
	repText.Position = UDim2.fromOffset(430, 84)
	repText.Size = UDim2.fromOffset(180, 20)
	repText.Parent = surface

	-- Next-rank reward preview: three icon chips, future ones dim + lock.
	local caption = UIChrome.BodyText("NextCaption", 13, theme.Colors.TextSecondary)
	caption.Text = "NEXT RANK REWARDS"
	caption.TextXAlignment = Enum.TextXAlignment.Right
	caption.AnchorPoint = Vector2.new(1, 0)
	caption.Position = UDim2.new(1, -20, 0, 14)
	caption.Size = UDim2.fromOffset(CHIP * 3 + 28, 16)
	caption.Parent = surface

	local chips = UIStyler.Frame("Chips")
	chips.BackgroundTransparency = 1
	chips.AnchorPoint = Vector2.new(1, 0)
	chips.Position = UDim2.new(1, -20, 0, 36)
	chips.Size = UDim2.fromOffset(CHIP * 3 + 28, CHIP)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 14),
	}).Parent = chips
	chips.Parent = surface

	for order, reward in faction.rewards do
		if order > 3 then
			break
		end
		local chip = UIStyler.Frame("Chip" .. order)
		chip.BackgroundColor3 = theme.Arcade.NearBlack
		chip.BackgroundTransparency = 0
		chip.Size = UDim2.fromOffset(CHIP, CHIP)
		chip.LayoutOrder = order
		UIChrome.Stroke(theme, "Arcade").Parent = chip
		UIChrome.GlassGradient().Parent = chip
		chip.Parent = chips

		local rewardIcon = IconArchive.Image(chip, reward.icon, 42, { golden = not reward.locked })
		rewardIcon.AnchorPoint = Vector2.new(0.5, 0.5)
		rewardIcon.Position = UDim2.fromScale(0.5, 0.5)
		if reward.locked then
			-- Dimmed in place, never removed (doc §11.2).
			dimIcon(rewardIcon, 0.55)
			local lock = IconArchive.Image(chip, "lock", 18)
			lock.AnchorPoint = Vector2.new(1, 1)
			lock.Position = UDim2.new(1, -4, 1, -4)
		end
	end

	if expanded then
		self:_BuildBand(container, faction, bandH)
	end

	hit.Activated:Connect(function()
		self._expandedId = if self._expandedId == faction.id then nil else faction.id
		self:_RenderList()
	end)
	-- Animate LAST, after the final colours (it snapshots the rest colour).
	UIChrome.Animate(theme, hit, surface)
end

-- The expanded detail band: every rank on the ladder, checked when earned.
function FactionScreen:_BuildBand(container: Frame, faction: Faction, bandH: number)
	local theme = self:GetTheme()

	local band = UIStyler.Frame("Band")
	band.BackgroundColor3 = theme.Arcade.NearBlack2
	band.BackgroundTransparency = 0
	band.Position = UDim2.fromOffset(16, ROW_H + 6)
	band.Size = UDim2.new(1, -32, 0, bandH)
	UIChrome.Stroke(theme, "Arcade").Parent = band
	UIChrome.GlassGradient().Parent = band
	band.Parent = container
	-- Pop the band, not the container: the entrance juice lives on contents.
	UIChrome.PopIn(theme, band)

	for i, step in faction.ranks do
		local y = 8 + (i - 1) * BAND_ROW_H
		local earned = i <= faction.rankIndex
		local current = i == faction.rankIndex

		if earned then
			local check = IconArchive.Image(band, "check", 22)
			check.Position = UDim2.fromOffset(16, y + 4)
			tintIcon(check, theme.Arcade.Green)
		else
			local lock = IconArchive.Image(band, "lock", 18)
			lock.Position = UDim2.fromOffset(18, y + 6)
			dimIcon(lock, 0.5)
		end

		local title = UIChrome.Text("RankTitle", 18,
			if current then theme.Arcade.Gold
			elseif earned then theme.Colors.TextPrimary
			else theme.Arcade.GreyOwned)
		title.Text = step.title
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Position = UDim2.fromOffset(52, y)
		title.Size = UDim2.fromOffset(300, 30)
		title.Parent = band

		if current then
			local marker = UIChrome.Text("Current", 14, theme.Arcade.Gold)
			marker.Text = "CURRENT"
			marker.TextXAlignment = Enum.TextXAlignment.Left
			marker.Position = UDim2.fromOffset(360, y + 2)
			marker.Size = UDim2.fromOffset(110, 26)
			marker.Parent = band
		end

		local threshold = UIChrome.BodyText("Threshold", 14, theme.Colors.TextSecondary)
		threshold.Text = comma(step.rep) .. " REP"
		threshold.TextXAlignment = Enum.TextXAlignment.Right
		threshold.AnchorPoint = Vector2.new(1, 0)
		threshold.Position = UDim2.new(1, -18, 0, y + 5)
		threshold.Size = UDim2.fromOffset(140, 20)
		threshold.Parent = band
	end
end

function FactionScreen:_Apply(data: any)
	if data.factions then
		self._data = { factions = data.factions }
		self._expandedId = nil
	end
end

function FactionScreen:_OnShow(data: any?)
	if data then
		self:_Apply(data)
		self:_RenderList()
	end
	if self._modal then
		UIChrome.PopIn(self:GetTheme(), self._modal.content)
	end
end

function FactionScreen:Update(data: any)
	if not data then
		return
	end
	self:_Apply(data)
	if self._built then
		self:_RenderList()
	end
end

function FactionScreen:Destroy()
	for _, component in self._rowComponents do
		component:Destroy()
	end
	table.clear(self._rowComponents)
	UIScreenBase.Destroy(self)
end

return FactionScreen
