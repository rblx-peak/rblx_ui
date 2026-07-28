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
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local GPStudioKit = require(script.Parent.Parent.Framework.GPStudioKit)

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
	-- GP layout language: the matte guild ledger (see _BuildGPLayout below);
	-- the classic arcade modal build stays untouched.
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end
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
	-- Explicitly `any`: the two layouts hold their list in different fields and
	-- narrowing the union buys nothing here.
	local list: any = if self:LayoutKit() == "GP" then self._gpList else self._list
	local keepPosition = list.CanvasPosition
	for _, component in self._rowComponents do
		component:Destroy()
	end
	table.clear(self._rowComponents)
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local isGP = self:LayoutKit() == "GP"
	for index, faction in (self._data :: FactionData).factions do
		if isGP then
			self:_GPBuildFaction(faction, index)
		else
			self:_BuildFaction(faction, index)
		end
	end

	-- Restore after the layout pass: the immediate write clamps against the
	-- stale (smaller) canvas, so re-apply once the rows have been measured.
	list.CanvasPosition = keepPosition
	task.defer(function()
		if list and list.Parent then
			list.CanvasPosition = keepPosition
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

-- ========================================================================
-- GP layout (theme.LayoutKit == "GP") — THE GUILD LEDGER, in the pack's
-- MATTE dialect: cream paper, clay speckle, sage hairlines.
--
-- ANTI-CONDESCENSION LEDGER — every reading the arcade row carries:
--   faction icon in its own well · THE FACTION'S ACCENT as the ring (colour
--   is identity and survives the re-skin verbatim) · name · current rank ·
--   reputation ruler · the comma-grouped "2,400 / 6,000" readout · the
--   "next rank rewards" caption · all three reward chips, future ones dimmed
--   in place behind a lock · the expandable band listing EVERY rank on the
--   ladder with its check/lock, its CURRENT marker and its REP threshold.
-- ADDED: the ruler now also prints its percentage. Nothing was traded for it.
--
-- The one presentational liberty: the well BEHIND the icon is a pastel wash
-- of the faction's own accent (accent lerped 72% toward cream) rather than
-- near-black, so a saturated brand colour can sit on cream paper without
-- shouting. The RING stays the accent at full strength, which is where the
-- identity actually lives.
--
-- BUDGET NOTE: rows, chips and band rows are SHADOWLESS — the faction list is
-- caller-supplied and every expanded band multiplies the row count.
-- ========================================================================

local GP_PAGE = Vector2.new(CARD_W, CARD_H + 48)
local GP_SCROLL_PAD = 10
local GP_ROW_H = 128
local GP_BAND_ROW_H = 36
local GP_CHIP = 68
local GP_WELL = 88

function FactionScreen:_BuildGPLayout()
	local theme = self:GetTheme()

	local page = GPLayoutKit.Page(theme, self.Root, {
		titleText = "Factions",
		subtitleText = "Who in the valley knows your work, and how well.",
		sizePx = GP_PAGE,
		onClose = function()
			self.ScreenController:HideScreen("faction")
		end,
	})
	self._gpShadows = page.shadows
	self._modal = { content = page.content, card = page.panel } :: any
	local content = page.content

	local hint = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Hint")
	hint.Text = "Earn reputation from commissions and contracts. Pick a faction to open its ladder."
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.Size = UDim2.new(1, 0, 0, 20)
	hint.Parent = content

	local list = GPStudioKit.Scroller(theme, content, {
		name = "GPFactionList",
		padPx = GP_SCROLL_PAD,
	})
	list.Position = UDim2.fromOffset(0, LIST_Y)
	list.Size = UDim2.new(1, 0, 0, LIST_H)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, ROW_GAP),
	}).Parent = list
	self._gpList = list

	self:_RenderList()
end

function FactionScreen:_GPBuildFaction(faction: Faction, index: number)
	local theme = self:GetTheme()
	local spacing = theme.Spacing
	local expanded = self._expandedId == faction.id
	local bandH = 16 + #faction.ranks * GP_BAND_ROW_H
	local containerH = if expanded then (GP_ROW_H + 8 + bandH) else GP_ROW_H

	local container = UIStyler.Frame("GPFaction_" .. faction.id)
	container.BackgroundTransparency = 1
	container.Size = UDim2.new(1, -SCROLLBAR, 0, containerH)
	container.LayoutOrder = index
	container.Parent = self._gpList

	local root = Instance.new("TextButton")
	root.Name = "Row"
	root.BackgroundTransparency = 1
	root.Text = ""
	root.AutoButtonColor = false
	root.Size = UDim2.new(1, 0, 0, GP_ROW_H)
	root.Parent = container

	local plate = GPStudioKit.Paper(theme, root, {
		name = "Plate",
		index = index,
		fill = theme.Colors.SurfaceRaised,
		strokeTint = if expanded then theme.Arcade.Gold else nil,
		strokeThickness = if expanded then 3 else nil,
	})
	plate.Size = UDim2.fromScale(1, 1)

	-- The icon well: a pastel wash of the faction's OWN accent, ringed in that
	-- accent at full strength. Colour is identity; the wash is only how a brand
	-- colour learns to sit on cream.
	local wellFill = faction.accent:Lerp(theme.Colors.Background, 0.72)
	local well = GPStudioKit.Paper(theme, plate, {
		name = "Well",
		index = index + 1,
		fill = wellFill,
		speckle = false,
		strokeTint = faction.accent,
		strokeThickness = 3,
	})
	well.Position = UDim2.fromOffset(spacing.M + 2, 20)
	well.Size = UDim2.fromOffset(GP_WELL, GP_WELL)
	well.ZIndex = 3

	local icon = GPStudioKit.Icon(theme, well, faction.icon, 56)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.ZIndex = 4

	local name = GPLayoutKit.Text(theme, 24, theme.Colors.TextPrimary, "Name")
	name.Text = GPStudioKit.SoftCase(faction.name)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Position = UDim2.fromOffset(124, 18)
	name.Size = UDim2.fromOffset(340, 30)
	name.RichText = false
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.ZIndex = 3
	name.Parent = plate

	-- Deepened butter: the pack's gold is a LIGHT fill and would not carry as
	-- 18px body copy on cream paper.
	local rank = GPLayoutKit.BodyText(theme, 18, GPLayoutKit.Deepen(theme, theme.Arcade.Gold, 1), "Rank")
	rank.Text = GPStudioKit.SoftCase(faction.rank)
	rank.TextXAlignment = Enum.TextXAlignment.Left
	rank.Position = UDim2.fromOffset(124, 52)
	rank.Size = UDim2.fromOffset(340, 24)
	rank.ZIndex = 3
	rank.Parent = plate

	local ratio = if faction.repToNext > 0 then faction.rep / faction.repToNext else 0
	local meter = GPStudioKit.Meter(theme, plate, {
		value = faction.rep,
		maxValue = math.max(faction.repToNext, 1),
		label = string.format("%d%%", math.floor(math.clamp(ratio, 0, 1) * 100 + 0.5)),
		tone = faction.accent:Lerp(theme.Colors.Primary, 0.25),
		heightPx = 26,
		sizeUDim = UDim2.fromOffset(360, 26),
		position = UDim2.fromOffset(124, 84),
		name = "RepMeter",
	})
	meter.root.ZIndex = 3
	-- The comma-grouped readout the arcade build prints beside the ruler, kept
	-- verbatim: the meter's own default would print bare integers.
	meter.Set(faction.rep, math.max(faction.repToNext, 1), string.format("%s / %s", comma(faction.rep), comma(faction.repToNext)))

	local caption = GPLayoutKit.BodyText(theme, 13, theme.Colors.TextSecondary, "NextCaption")
	caption.Text = "Next rank rewards"
	caption.TextXAlignment = Enum.TextXAlignment.Right
	caption.AnchorPoint = Vector2.new(1, 0)
	caption.Position = UDim2.new(1, -spacing.L, 0, 16)
	caption.Size = UDim2.fromOffset(GP_CHIP * 3 + 28, 18)
	caption.ZIndex = 3
	caption.Parent = plate

	local chips = UIStyler.Frame("Chips")
	chips.BackgroundTransparency = 1
	chips.AnchorPoint = Vector2.new(1, 0)
	chips.Position = UDim2.new(1, -spacing.L, 0, 40)
	chips.Size = UDim2.fromOffset(GP_CHIP * 3 + 28, GP_CHIP)
	chips.ZIndex = 3
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 14),
	}).Parent = chips
	chips.Parent = plate

	for order, reward in faction.rewards do
		if order > 3 then
			break
		end
		local chip = GPStudioKit.Paper(theme, chips, {
			name = "Chip" .. order,
			index = order,
			fill = if reward.locked then theme.Colors.Surface else theme.Colors.SurfaceRaised,
			speckle = false,
		})
		chip.Size = UDim2.fromOffset(GP_CHIP, GP_CHIP)
		chip.LayoutOrder = order
		chip.ZIndex = 3

		local rewardIcon = GPStudioKit.Icon(theme, chip, reward.icon, 42, {
			golden = not reward.locked,
			dim = if reward.locked then 0.55 else nil,
		})
		rewardIcon.AnchorPoint = Vector2.new(0.5, 0.5)
		rewardIcon.Position = UDim2.fromScale(0.5, 0.5)
		rewardIcon.ZIndex = 4
		if reward.locked then
			-- Dimmed in place, never removed (doc §11.2).
			local lock = GPStudioKit.Icon(theme, chip, "lock", 18, { tint = theme.Colors.TextSecondary })
			lock.AnchorPoint = Vector2.new(1, 1)
			lock.Position = UDim2.new(1, -4, 1, -4)
			lock.ZIndex = 5
		end
	end

	if expanded then
		self:_GPBuildBand(container, faction, bandH, index)
	end

	root.Activated:Connect(function()
		self._expandedId = if self._expandedId == faction.id then nil else faction.id
		self:_RenderList()
	end)
	-- Animate LAST, after the final colours (it snapshots the rest colour).
	UIChrome.Animate(theme, root, plate)
end

-- The expanded detail band: EVERY rank on the ladder, checked when earned —
-- the same full ladder the arcade build prints, not an abbreviated one.
function FactionScreen:_GPBuildBand(container: Frame, faction: Faction, bandH: number, index: number)
	local theme = self:GetTheme()
	local spacing = theme.Spacing

	local band = GPStudioKit.Paper(theme, container, {
		name = "Band",
		index = index + 1,
		fill = theme.Colors.Surface,
	})
	band.Position = UDim2.fromOffset(spacing.M, GP_ROW_H + 8)
	band.Size = UDim2.new(1, -spacing.M * 2, 0, bandH)
	-- Pop the band, not the container: the entrance juice lives on contents.
	UIChrome.PopIn(theme, band)

	for i, step in faction.ranks do
		local y = 8 + (i - 1) * GP_BAND_ROW_H
		local earned = i <= faction.rankIndex
		local current = i == faction.rankIndex

		if earned then
			local check = GPStudioKit.Icon(theme, band, "check", 22, {
				tint = GPLayoutKit.Deepen(theme, theme.Arcade.Green, 1),
			})
			check.Position = UDim2.fromOffset(spacing.M, y + 5)
			check.ZIndex = 3
		else
			local lock = GPStudioKit.Icon(theme, band, "lock", 18, {
				tint = theme.Colors.TextSecondary,
				dim = 0.35,
			})
			lock.Position = UDim2.fromOffset(spacing.M + 2, y + 7)
			lock.ZIndex = 3
		end

		local title = GPLayoutKit.BodyText(theme, 18,
			if current then GPLayoutKit.Deepen(theme, theme.Arcade.Gold, 1)
			elseif earned then theme.Colors.TextPrimary
			else theme.Colors.TextSecondary, "RankTitle")
		title.Text = GPStudioKit.SoftCase(step.title)
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Position = UDim2.fromOffset(54, y)
		title.Size = UDim2.fromOffset(300, GP_BAND_ROW_H - 4)
		title.ZIndex = 3
		title.Parent = band

		if current then
			local marker = GPStudioKit.Chip(theme, band, {
				name = "Current",
				text = "Current",
				tone = theme.Arcade.Gold,
				index = i,
				pill = true,
				sizeUDim = UDim2.fromOffset(102, 24),
				position = UDim2.fromOffset(360, y + 4),
				textSize = theme.TextSizes.Small,
			})
			marker.root.ZIndex = 3
			marker.label.ZIndex = 4
		end

		local threshold = GPLayoutKit.NumberText(theme, 14, theme.Colors.TextSecondary, "Threshold")
		threshold.Text = comma(step.rep) .. " rep"
		threshold.AnchorPoint = Vector2.new(1, 0)
		threshold.Position = UDim2.new(1, -spacing.L, 0, y + 6)
		threshold.Size = UDim2.fromOffset(150, 22)
		threshold.ZIndex = 3
		threshold.Parent = band

		-- A sage hairline between ladder steps, never after the last one.
		if i < #faction.ranks then
			local rule = GPStudioKit.Rule(theme, band, { transparency = 0.35, inset = spacing.M })
			rule.Position = UDim2.fromOffset(spacing.M, y + GP_BAND_ROW_H - 2)
			rule.ZIndex = 3
		end
	end
end

-- A style rebuild destroys the Gui, but UIShadow BUDGET counts live in
-- StyleKit.Capabilities and only fall when a handle is released.
function FactionScreen:_OnTeardown()
	GPStudioKit.ReleaseShadows(self._gpShadows)
	self._gpShadows = nil
	self._gpList = nil
end

function FactionScreen:Destroy()
	for _, component in self._rowComponents do
		component:Destroy()
	end
	table.clear(self._rowComponents)
	UIScreenBase.Destroy(self)
end

return FactionScreen
