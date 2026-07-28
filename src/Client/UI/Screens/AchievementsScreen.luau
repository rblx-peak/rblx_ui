--!strict
-- Achievements — Pottery Clash arcade family (UI_DESIGN_DOCUMENT.md §7.4).
-- One modal card: a completion header (X / Y over the gold ruler), a category
-- filter row, and a 4-column grid of achievement tiles.
--
-- Tile language follows the doc's "dim in place, never remove" rule (§11.2)
-- and "selection is a ring" rule (§4.3): a LOCKED tile is the near-black well
-- with a greyed title, a dimmed icon and the lock mark; an UNLOCKED tile keeps
-- the row fill, wears the gold Selection ring and swaps in the GOLDEN icon
-- variant plus its earned date. A partially-complete tile carries the gold
-- ruler; every tile carries its rarity line.
--
-- Layout is fixed px at the 1650×1020 baseline (UIScreenBase attaches the
-- UIScale). Pure function of Show(data).achievements, demo data as fallback.

local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UIProgressBarComponent = require(script.Parent.Parent.Components.UIProgressBarComponent)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local GPStudioKit = require(script.Parent.Parent.Framework.GPStudioKit)

type Achievement = {
	id: string,
	name: string,
	description: string,
	icon: string?,
	category: string?,
	unlocked: boolean?,
	progress: number,
	goal: number,
	rarityPercent: number?,
	date: string?,
}

local CARD_W, CARD_H = 1220, 740
local CONTENT_W = CARD_W - 28
local CONTENT_H = CARD_H - 88
local SCROLLBAR = 8
local FILTER_H = 44
local GRID_Y = 148
local COLUMNS = 4
local CELL_PAD = 14
local TILE_W = math.floor((CONTENT_W - SCROLLBAR - CELL_PAD * (COLUMNS - 1)) / COLUMNS)
local TILE_H = 210

local ALL = "ALL"

local DEMO_ACHIEVEMENTS: { Achievement } = {
	{ id = "first_throw", name = "FIRST THROW", description = "Centre your first lump of clay on the wheel.", icon = "star", category = "CRAFT", unlocked = true, progress = 1, goal = 1, rarityPercent = 88.4, date = "12 JUL" },
	{ id = "hundred_pots", name = "CENTURY POTTER", description = "Finish one hundred pieces from wheel to kiln.", icon = "trophy", category = "CRAFT", unlocked = true, progress = 100, goal = 100, rarityPercent = 21.7, date = "03 AUG" },
	{ id = "thousand_pots", name = "MASTER OF CLAY", description = "Finish one thousand pieces. Your hands know the shape now.", icon = "crown", category = "CRAFT", unlocked = false, progress = 412, goal = 1000, rarityPercent = 4.2 },
	{ id = "no_crack", name = "STEADY KILN", description = "Fire fifty pieces in a row without a single crack.", icon = "fire", category = "CRAFT", unlocked = false, progress = 31, goal = 50, rarityPercent = 9.6 },
	{ id = "first_sale", name = "OPEN FOR BUSINESS", description = "Sell your first piece at the market stall.", icon = "cash", category = "TRADE", unlocked = true, progress = 1, goal = 1, rarityPercent = 74.1, date = "12 JUL" },
	{ id = "millionaire", name = "KILN TYCOON", description = "Bank one million cash from stall sales.", icon = "chest", category = "TRADE", unlocked = false, progress = 264000, goal = 1000000, rarityPercent = 1.8 },
	{ id = "haggler", name = "HARD BARGAIN", description = "Complete twenty five trades with other potters.", icon = "trade", category = "TRADE", unlocked = false, progress = 11, goal = 25, rarityPercent = 12.3 },
	{ id = "collector", name = "GLAZE COLLECTOR", description = "Unlock every glaze in the honey family.", icon = "sparkle", category = "COLLECT", unlocked = true, progress = 8, goal = 8, rarityPercent = 16.9, date = "27 JUL" },
	{ id = "full_index", name = "COMPLETIONIST", description = "Fill every slot in the collection index.", icon = "book", category = "COLLECT", unlocked = false, progress = 34, goal = 120, rarityPercent = 0.7 },
	{ id = "night_owl", name = "NIGHT FIRING", description = "Sit an overnight firing from dusk until dawn.", icon = "moon", category = "SOCIAL", unlocked = true, progress = 1, goal = 1, rarityPercent = 33.5, date = "19 JUL" },
	{ id = "party", name = "GOOD COMPANY", description = "Work the booth alongside three friends at once.", icon = "friends", category = "SOCIAL", unlocked = false, progress = 2, goal = 3, rarityPercent = 28.0 },
	{ id = "gifted", name = "GENEROUS SOUL", description = "Gift fifty finished pieces to other players.", icon = "gift", category = "SOCIAL", unlocked = false, progress = 0, goal = 50, rarityPercent = 6.4 },
}

local function dimIcon(icon: GuiObject, transparency: number)
	if icon:IsA("ImageLabel") then
		icon.ImageTransparency = transparency
	elseif icon:IsA("TextLabel") then
		icon.TextTransparency = transparency
	end
end

local function formatCount(value: number): string
	if value >= 1000000 then
		return string.format("%.1fM", value / 1000000)
	elseif value >= 10000 then
		return string.format("%.1fK", value / 1000)
	end
	return tostring(math.floor(value))
end

local AchievementsScreen = setmetatable({}, { __index = UIScreenBase })
AchievementsScreen.__index = AchievementsScreen

function AchievementsScreen.new()
	local self = UIScreenBase.new("AchievementsScreen", 6)
	self._achievements = DEMO_ACHIEVEMENTS
	self._filter = ALL
	self._filterButtons = {} :: { any }
	self._tileComponents = {} :: { any }
	return setmetatable(self, AchievementsScreen)
end

function AchievementsScreen:_Toast(text: string, variant: string)
	local hud = self.ScreenController and self.ScreenController:GetScreen("hud")
	if hud then
		hud:PushToast({ text = text, variant = variant })
	end
end

-- ALL first, then every category present in the data, in first-seen order.
function AchievementsScreen:_Categories(): { string }
	local seen: { [string]: boolean } = { [ALL] = true }
	local out = { ALL }
	for _, achievement in self._achievements do
		local category = achievement.category or "GENERAL"
		if not seen[category] then
			seen[category] = true
			table.insert(out, category)
		end
	end
	return out
end

function AchievementsScreen:_BuildContent()
	-- GP layout language: the matte shelf of finished pieces (see
	-- _BuildGPLayout below); the classic arcade modal build stays untouched.
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end
	local theme = self:GetTheme()

	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = "ACHIEVEMENTS",
		sizePx = Vector2.new(CARD_W, CARD_H),
		onClose = function()
			self.ScreenController:HideScreen("achievements")
		end,
	})
	self._modal = modal
	local content = modal.content

	-- Completion header: label left, X / Y right, the gold ruler underneath.
	local label = UIChrome.Text("CompletionLabel", 22, theme.Arcade.Gold)
	label.Text = "TOTAL COMPLETION"
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Size = UDim2.new(0.6, 0, 0, 30)
	label.Parent = content

	local count = UIChrome.Text("CompletionCount", 26, theme.Colors.TextPrimary)
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.AnchorPoint = Vector2.new(1, 0)
	count.Position = UDim2.new(1, 0, 0, 0)
	count.Size = UDim2.new(0.4, 0, 0, 30)
	count.Parent = content
	self._count = count

	self._headerBar = UIProgressBarComponent.new()
	self._headerBar:Create(content, {
		value = 0,
		maxValue = 1,
		size = UDim2.new(1, 0, 0, 26),
		position = UDim2.fromOffset(0, 38),
	})

	-- Category filter row (blue tabs: active Blue / inactive Ghost).
	local filterRow = UIStyler.Frame("Filters")
	filterRow.BackgroundTransparency = 1
	filterRow.Position = UDim2.fromOffset(0, 84)
	filterRow.Size = UDim2.new(1, 0, 0, FILTER_H)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
	}).Parent = filterRow
	filterRow.Parent = content
	self._filterRow = filterRow

	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Tiles"
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.Position = UDim2.fromOffset(0, GRID_Y)
	grid.Size = UDim2.new(1, 0, 0, CONTENT_H - GRID_Y)
	grid.CanvasSize = UDim2.new()
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.ScrollBarThickness = SCROLLBAR
	grid.ScrollBarImageColor3 = theme.Arcade.Gold
	grid.Parent = content
	local layout = UIStyler.GridLayout(UDim2.fromOffset(TILE_W, TILE_H), UDim2.fromOffset(CELL_PAD, CELL_PAD))
	layout.FillDirectionMaxCells = COLUMNS
	layout.Parent = grid
	self._grid = grid

	self:_RenderFilters()
	self:_RenderHeader()
	self:_RenderTiles()
end

function AchievementsScreen:_RenderFilters()
	if self:LayoutKit() == "GP" then
		self:_GPRenderFilters()
		return
	end
	for _, button in self._filterButtons do
		button:Destroy()
	end
	table.clear(self._filterButtons)

	for i, category in self:_Categories() do
		local button = UIButtonComponent.new()
		button:Create(self._filterRow, {
			text = category,
			variant = category == self._filter and "Blue" or "Ghost",
			size = UDim2.fromOffset(150, FILTER_H),
			layoutOrder = i,
			onClick = function()
				if self._filter == category then
					return
				end
				self._filter = category
				self:_RenderFilters()
				self:_RenderTiles()
			end,
		})
		table.insert(self._filterButtons, button)
	end
end

function AchievementsScreen:_RenderHeader()
	local unlocked = 0
	for _, achievement in self._achievements do
		if achievement.unlocked then
			unlocked += 1
		end
	end
	local total = #self._achievements
	if self:LayoutKit() == "GP" then
		self:_GPRenderHeader(unlocked, total)
		return
	end
	self._count.Text = string.format("%d / %d", unlocked, total)
	self._headerBar:Set(unlocked, math.max(total, 1))
end

function AchievementsScreen:_RenderTiles()
	if self:LayoutKit() == "GP" then
		self:_GPRenderTiles()
		return
	end
	for _, component in self._tileComponents do
		component:Destroy()
	end
	table.clear(self._tileComponents)
	for _, child in self._grid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local index = 0
	for _, achievement in self._achievements do
		local category = achievement.category or "GENERAL"
		if self._filter == ALL or category == self._filter then
			index += 1
			self:_BuildTile(achievement, index)
		end
	end
end

function AchievementsScreen:_BuildTile(achievement: Achievement, index: number)
	local theme = self:GetTheme()
	local unlocked = achievement.unlocked == true

	local root = UIStyler.Frame("Tile_" .. achievement.id)
	root.BackgroundTransparency = 1
	root.LayoutOrder = index
	root.Parent = self._grid

	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 1
	hit.Parent = root

	local surface = UIStyler.Frame("Surface")
	surface.BackgroundColor3 = unlocked and theme.Arcade.Row or theme.Arcade.NearBlack
	surface.BackgroundTransparency = unlocked and theme.Arcade.RowTransparency or 0
	surface.AnchorPoint = Vector2.new(0.5, 0.5)
	surface.Position = UDim2.fromScale(0.5, 0.5)
	surface.Size = UDim2.fromScale(1, 1)
	surface.ZIndex = 2
	-- Unlocked wears the gold ring (doc §4.3: selection/valuable is a stroke).
	UIChrome.Stroke(theme, "Arcade", unlocked and "Selection" or "Panel").Parent = surface
	UIChrome.GlassGradient().Parent = surface
	surface.Parent = root

	local icon = IconArchive.Image(surface, achievement.icon or "medal", 60, { golden = unlocked })
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 14)
	if not unlocked then
		dimIcon(icon, 0.55)

		local lock = IconArchive.Image(surface, "lock", 24)
		lock.AnchorPoint = Vector2.new(1, 0)
		lock.Position = UDim2.new(1, -8, 0, 8)
	end

	local name = UIChrome.Text("Name", 18, unlocked and theme.Colors.TextPrimary or theme.Arcade.GreyOwned)
	name.Text = achievement.name
	name.Position = UDim2.fromOffset(8, 78)
	name.Size = UDim2.new(1, -16, 0, 24)
	name.RichText = false
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Parent = surface

	local description = UIChrome.BodyText("Description", 13, theme.Arcade.IceBlue)
	description.Text = achievement.description
	description.TextYAlignment = Enum.TextYAlignment.Top
	description.Position = UDim2.fromOffset(10, 104)
	description.Size = UDim2.new(1, -20, 0, 36)
	description.TextWrapped = true
	description.Parent = surface

	-- Middle slot: earned date when unlocked, the gold ruler while in progress,
	-- nothing at all when untouched (0 / goal reads as "not started").
	if unlocked then
		local earned = UIChrome.Text("Earned", 15, theme.Arcade.SunburstGold)
		earned.Text = achievement.date and ("EARNED " .. achievement.date) or "EARNED"
		earned.Position = UDim2.fromOffset(8, 146)
		earned.Size = UDim2.new(1, -16, 0, 22)
		earned.Parent = surface
	elseif achievement.progress > 0 then
		local bar = UIProgressBarComponent.new()
		bar:Create(surface, {
			value = achievement.progress,
			maxValue = achievement.goal,
			size = UDim2.new(1, -20, 0, 22),
			position = UDim2.fromOffset(10, 146),
		})
		table.insert(self._tileComponents, bar)

		local counts = UIChrome.Text("Counts", 13, theme.Arcade.SunburstGold)
		counts.Text = string.format("%s / %s", formatCount(achievement.progress), formatCount(achievement.goal))
		counts.Position = UDim2.fromOffset(10, 146)
		counts.Size = UDim2.new(1, -20, 0, 22)
		counts.ZIndex = 4
		counts.Parent = surface
	else
		local notStarted = UIChrome.Text("NotStarted", 14, theme.Arcade.GreyOwned)
		notStarted.Text = "NOT STARTED"
		notStarted.Position = UDim2.fromOffset(8, 146)
		notStarted.Size = UDim2.new(1, -16, 0, 22)
		notStarted.Parent = surface
	end

	local rarity = UIChrome.BodyText("Rarity", 13, theme.Arcade.GreyOwned)
	rarity.Text = string.format("%.1f%% of players", achievement.rarityPercent or 0)
	rarity.Position = UDim2.fromOffset(10, 176)
	rarity.Size = UDim2.new(1, -20, 0, 18)
	rarity.Parent = surface

	hit.Activated:Connect(function()
		UIChrome.Pulse(theme, surface)
		if unlocked then
			self:_Toast(string.format("%s — earned by %.1f%% of players.", achievement.name, achievement.rarityPercent or 0), "Success")
		else
			self:_Toast(string.format("%s — %s / %s", achievement.name, formatCount(achievement.progress), formatCount(achievement.goal)), "Info")
		end
	end)
	-- Animate LAST, after the final colours (it snapshots the rest colour).
	UIChrome.Animate(theme, hit, surface)
end

-- _EnsureBuilt has already rendered with the data the screen was holding, so
-- only a fresh payload re-renders here.
function AchievementsScreen:_OnShow(data: any?)
	if data and data.achievements then
		self._achievements = data.achievements
		self._filter = ALL
		self:_RenderFilters()
		self:_RenderHeader()
		self:_RenderTiles()
	end
	if self._modal then
		UIChrome.PopIn(self:GetTheme(), self._modal.content)
	end
end

function AchievementsScreen:Update(data: any)
	if data and data.achievements then
		self._achievements = data.achievements
		if self._built then
			self:_RenderFilters()
			self:_RenderHeader()
			self:_RenderTiles()
		end
	end
end

-- ========================================================================
-- GP layout (theme.LayoutKit == "GP") — THE SHELF, in the pack's MATTE
-- dialect: cream paper, faint clay speckle, sage hairlines. A finished piece
-- goes on the shelf; an unfinished one is still on the shelf, just waiting.
--
-- ANTI-CONDESCENSION LEDGER — every reading the arcade tile carries is here:
--   icon (golden when unlocked) · lock mark · name · full description ·
--   earned date / progress ruler + counts / "not started" · rarity percent ·
--   the completion header (label, X / Y, ruler) · the category filter row
--   with every category the data declares · four columns, unchanged.
-- ADDED, never substituted: the header ruler now prints its percentage, and
-- the per-tile ruler prints both its percentage and its counts where the
-- arcade build printed counts alone.
--
-- BUDGET NOTE: the tiles are deliberately SHADOWLESS. They repeat per cell
-- and the dataset is caller-supplied — a hundred achievements would be a
-- hundred UIShadows against an engine budget of ~100 on screen. Unlocked
-- therefore reads as a RING (a deepened butter stroke at 3px) plus the golden
-- icon, which is this codebase's selection grammar anyway.
--
-- The GP page is the classic card grown by 48px in Y — exactly the difference
-- between ModalCard's 88px of chrome and GPLayoutKit.Page's 136 — so
-- CONTENT_W / CONTENT_H at the top of this file describe the GP content box
-- byte for byte, and the grid keeps all four of its columns.
-- ========================================================================

local GP_PAGE = Vector2.new(CARD_W, CARD_H + 48)
local GP_SCROLL_PAD = 10
local GP_TILE_W = math.floor((CONTENT_W - SCROLLBAR - GP_SCROLL_PAD * 2 - CELL_PAD * (COLUMNS - 1)) / COLUMNS)
local GP_TILE_H = 230

function AchievementsScreen:_BuildGPLayout()
	local theme = self:GetTheme()

	local page = GPLayoutKit.Page(theme, self.Root, {
		titleText = "Achievements",
		subtitleText = "Everything you have finished, and everything still on the wheel.",
		sizePx = GP_PAGE,
		onClose = function()
			self.ScreenController:HideScreen("achievements")
		end,
	})
	self._gpShadows = page.shadows
	self._gpTabShadows = {} :: { any }
	self._modal = { content = page.content, card = page.panel } :: any
	local content = page.content

	local label = GPStudioKit.Heading(theme, content, "Total completion", {
		sizePx = theme.TextSizes.Subtitle,
		heightPx = 30,
		name = "CompletionLabel",
	})
	label.Size = UDim2.new(0.6, 0, 0, 30)

	local count = GPLayoutKit.NumberText(theme, 26, theme.Colors.TextPrimary, "CompletionCount")
	count.AnchorPoint = Vector2.new(1, 0)
	count.Position = UDim2.new(1, 0, 0, 0)
	count.Size = UDim2.new(0.4, 0, 0, 30)
	count.Parent = content
	self._gpCount = count

	self._gpHeaderMeter = GPStudioKit.Meter(theme, content, {
		value = 0,
		maxValue = 1,
		tone = theme.Arcade.Gold,
		heightPx = 26,
		sizeUDim = UDim2.new(1, 0, 0, 26),
		position = UDim2.fromOffset(0, 40),
		name = "CompletionMeter",
	})

	local filterHost = UIStyler.Frame("GPFilters")
	filterHost.BackgroundTransparency = 1
	filterHost.Position = UDim2.fromOffset(0, 84)
	filterHost.Size = UDim2.new(1, 0, 0, FILTER_H)
	filterHost.Parent = content
	self._gpFilterHost = filterHost

	local grid = GPStudioKit.Scroller(theme, content, {
		name = "GPTiles",
		padPx = GP_SCROLL_PAD,
	})
	grid.Position = UDim2.fromOffset(0, GRID_Y)
	grid.Size = UDim2.new(1, 0, 0, CONTENT_H - GRID_Y)
	local layout = UIStyler.GridLayout(UDim2.fromOffset(GP_TILE_W, GP_TILE_H), UDim2.fromOffset(CELL_PAD, CELL_PAD))
	layout.FillDirectionMaxCells = COLUMNS
	layout.Parent = grid
	self._gpGrid = grid

	self:_GPRenderFilters()
	self:_RenderHeader()
	self:_GPRenderTiles()
end

-- The tab bar is rebuilt only when the CATEGORY SET changes (a fresh payload);
-- a plain filter click recolours in place through the kit's own Select, so the
-- button being clicked is never destroyed underneath the click.
function AchievementsScreen:_GPRenderFilters()
	local theme = self:GetTheme()
	GPLayoutKit.ReleaseShadows(self._gpTabShadows)
	if self._gpTabs then
		self._gpTabs.frame:Destroy()
	end

	local tabs = GPLayoutKit.Tabs(theme, self._gpFilterHost, {
		widthPx = 150,
		heightPx = FILTER_H,
		tabHeightPx = FILTER_H,
	}, self._gpTabShadows)
	for _, category in self:_Categories() do
		tabs.Add(GPStudioKit.SoftCase(category), category, function()
			if self._filter == category then
				return
			end
			self._filter = category
			tabs.Select(category)
			self:_GPRenderTiles()
		end)
	end
	tabs.Select(self._filter)
	self._gpTabs = tabs
end

function AchievementsScreen:_GPRenderHeader(unlocked: number, total: number)
	self._gpCount.Text = string.format("%d / %d", unlocked, total)
	local percent = if total > 0 then math.floor(unlocked / total * 100 + 0.5) else 0
	self._gpHeaderMeter.Set(unlocked, math.max(total, 1), string.format("%d%%", percent))
end

function AchievementsScreen:_GPRenderTiles()
	for _, component in self._tileComponents do
		component:Destroy()
	end
	table.clear(self._tileComponents)
	for _, child in self._gpGrid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local index = 0
	for _, achievement in self._achievements do
		local category = achievement.category or "GENERAL"
		if self._filter == ALL or category == self._filter then
			index += 1
			self:_GPBuildTile(achievement, index)
		end
	end
end

function AchievementsScreen:_GPBuildTile(achievement: Achievement, index: number)
	local theme = self:GetTheme()
	local spacing = theme.Spacing
	local unlocked = achievement.unlocked == true

	-- The whole tile is one hit target and the BUTTON stays transparent: the
	-- style enforcer backstops any solid GuiButton with a black 2px stroke.
	local root = Instance.new("TextButton")
	root.Name = "GPTile_" .. achievement.id
	root.BackgroundTransparency = 1
	root.Text = ""
	root.AutoButtonColor = false
	root.LayoutOrder = index
	root.Parent = self._gpGrid

	local plate = GPStudioKit.Paper(theme, root, {
		name = "Plate",
		index = index,
		fill = if unlocked then theme.Colors.SurfaceRaised else theme.Colors.Surface,
		strokeTint = if unlocked then theme.Arcade.Gold else nil,
		strokeThickness = if unlocked then 3 else nil,
	})
	plate.Size = UDim2.fromScale(1, 1)

	local icon = GPStudioKit.Icon(theme, plate, achievement.icon or "medal", 60, {
		golden = unlocked,
		dim = if unlocked then nil else 0.55,
	})
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, spacing.M)
	icon.ZIndex = 3

	if not unlocked then
		local lock = GPStudioKit.Icon(theme, plate, "lock", 24, { tint = theme.Colors.TextSecondary })
		lock.AnchorPoint = Vector2.new(1, 0)
		lock.Position = UDim2.new(1, -spacing.M, 0, spacing.M)
		lock.ZIndex = 4
	end

	local name = GPLayoutKit.Text(theme, 18, if unlocked then theme.Colors.TextPrimary else theme.Colors.TextSecondary, "Name")
	name.Text = GPStudioKit.SoftCase(achievement.name)
	name.Position = UDim2.fromOffset(spacing.S, 84)
	name.Size = UDim2.new(1, -spacing.S * 2, 0, 26)
	name.RichText = false
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.ZIndex = 3
	name.Parent = plate

	local description = GPLayoutKit.BodyText(theme, 13, theme.Colors.TextSecondary, "Description")
	description.Text = achievement.description
	description.TextYAlignment = Enum.TextYAlignment.Top
	description.Position = UDim2.fromOffset(spacing.M, 114)
	description.Size = UDim2.new(1, -spacing.M * 2, 0, 40)
	description.TextWrapped = true
	description.RichText = false
	description.ZIndex = 3
	description.Parent = plate

	-- The sage hairline that separates the copy from the state slot.
	local rule = GPStudioKit.Rule(theme, plate, { transparency = 0.3, inset = spacing.M })
	rule.Position = UDim2.fromOffset(spacing.M, 160)
	rule.ZIndex = 3

	-- Middle slot: the earned date when unlocked, the ruler while in progress,
	-- and an honest line when untouched. Same three states as the arcade tile.
	if unlocked then
		local earned = GPLayoutKit.BodyText(theme, 15, GPLayoutKit.Deepen(theme, theme.Arcade.Gold, 1), "Earned")
		earned.Text = achievement.date and ("Earned " .. GPStudioKit.SoftCase(achievement.date)) or "Earned"
		earned.Position = UDim2.fromOffset(spacing.M, 172)
		earned.Size = UDim2.new(1, -spacing.M * 2, 0, 24)
		earned.ZIndex = 3
		earned.Parent = plate
	elseif achievement.progress > 0 then
		local ratio = if achievement.goal > 0 then achievement.progress / achievement.goal else 0
		local meter = GPStudioKit.Meter(theme, plate, {
			value = achievement.progress,
			maxValue = math.max(achievement.goal, 1),
			label = string.format("%d%%", math.floor(ratio * 100 + 0.5)),
			tone = theme.Colors.Primary,
			heightPx = 24,
			sizeUDim = UDim2.new(1, -spacing.M * 2, 0, 24),
			position = UDim2.fromOffset(spacing.M, 172),
			name = "Progress",
		})
		meter.root.ZIndex = 3
		meter.Set(
			achievement.progress,
			math.max(achievement.goal, 1),
			string.format("%s / %s", formatCount(achievement.progress), formatCount(achievement.goal))
		)
	else
		local notStarted = GPLayoutKit.BodyText(theme, 14, theme.Colors.TextSecondary, "NotStarted")
		notStarted.Text = "Not started yet"
		notStarted.Position = UDim2.fromOffset(spacing.M, 172)
		notStarted.Size = UDim2.new(1, -spacing.M * 2, 0, 24)
		notStarted.ZIndex = 3
		notStarted.Parent = plate
	end

	local rarity = GPLayoutKit.BodyText(theme, 13, theme.Colors.TextSecondary, "Rarity")
	rarity.Text = string.format("%.1f%% of players", achievement.rarityPercent or 0)
	rarity.Position = UDim2.fromOffset(spacing.M, 200)
	rarity.Size = UDim2.new(1, -spacing.M * 2, 0, 18)
	rarity.ZIndex = 3
	rarity.Parent = plate

	root.Activated:Connect(function()
		UIChrome.Pulse(theme, plate)
		if unlocked then
			self:_Toast(string.format("%s — earned by %.1f%% of players.", achievement.name, achievement.rarityPercent or 0), "Success")
		else
			self:_Toast(string.format("%s — %s / %s", achievement.name, formatCount(achievement.progress), formatCount(achievement.goal)), "Info")
		end
	end)
	-- Animate LAST, after the final colours (it snapshots the rest colour).
	UIChrome.Animate(theme, root, plate)
end

-- A style rebuild destroys the Gui, but UIShadow BUDGET counts live in
-- StyleKit.Capabilities and only fall when a handle is released.
function AchievementsScreen:_OnTeardown()
	GPStudioKit.ReleaseShadows(self._gpShadows)
	GPStudioKit.ReleaseShadows(self._gpTabShadows)
	self._gpShadows = nil
	self._gpTabShadows = nil
	self._gpTabs = nil
	self._gpFilterHost = nil
	self._gpGrid = nil
	self._gpCount = nil
	self._gpHeaderMeter = nil
end

function AchievementsScreen:Destroy()
	for _, component in self._tileComponents do
		component:Destroy()
	end
	table.clear(self._tileComponents)
	for _, button in self._filterButtons do
		button:Destroy()
	end
	table.clear(self._filterButtons)
	if self._headerBar then
		self._headerBar:Destroy()
		self._headerBar = nil
	end
	UIScreenBase.Destroy(self)
end

return AchievementsScreen
