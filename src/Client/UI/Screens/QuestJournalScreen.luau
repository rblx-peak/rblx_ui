--!strict
-- Quest journal — Pottery Clash arcade family (UI_DESIGN_DOCUMENT.md §7.4).
-- One modal card holds an ACTIVE / COMPLETED / FAILED tab bar, a scrolling
-- quest list on the left and a detail pane on the right: description, the full
-- objective checklist, the reward chips and (for active quests) the ABANDON
-- danger button.
--
-- Two structural decisions worth stating:
--   * A row is a whole-row hit target (doc §11.6): the invisible Hit button
--     sits UNDER the visible surface, because plain Frames never sink input —
--     so a tap anywhere on the row selects it, while the TRACK toggle inside
--     the surface still answers for itself.
--   * Selection is stroke-only (doc §4.3) so the hover spring never fights it:
--     the row's single UIChrome stroke is REBUILT as the gold Selection ring
--     (rebuilt, not recoloured — policy stays inside UIChrome).
--
-- Layout is fixed px at the 1650×1020 baseline; UIScreenBase attaches the
-- UIScale. Pure function of Show(data).quests, with demo data as the fallback.

local UserInputService = game:GetService("UserInputService")

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UIProgressBarComponent = require(script.Parent.Parent.Components.UIProgressBarComponent)
local ACLayoutKit = require(script.Parent.Parent.Framework.ACLayoutKit)
local GLLayoutKit = require(script.Parent.Parent.Framework.GLLayoutKit)
local UITicker = require(script.Parent.Parent.Framework.UITicker)

type Reward = { currency: string?, icon: string?, amount: number, label: string? }
type Objective = { text: string, done: boolean? }
type Quest = {
	id: string,
	title: string,
	description: string,
	state: string, -- "active" | "completed" | "failed"
	progress: number,
	goal: number,
	icon: string?,
	objectives: { Objective },
	rewards: { Reward },
	tracked: boolean?,
}

local CARD_W, CARD_H = 1180, 720
local CONTENT_W = CARD_W - 28
local CONTENT_H = CARD_H - 88
local TAB_H = 44
local TAB_W = 200
local BODY_Y = TAB_H + 14
local BODY_H = CONTENT_H - BODY_Y
local LIST_W = 640
local DETAIL_X = LIST_W + 16
local DETAIL_W = CONTENT_W - DETAIL_X
local ROW_H = 108
local ROW_GAP = 10
local SCROLLBAR = 6

local TABS = {
	{ id = "active", label = "ACTIVE" },
	{ id = "completed", label = "COMPLETED" },
	{ id = "failed", label = "FAILED" },
}

-- Renders standalone with no backend (the screen is a pure function of the
-- data handed to Show; this is only the fallback).
local DEMO_QUESTS: { Quest } = {
	{
		id = "clay_haul",
		title = "CLAY HAULER",
		description = "The kiln burns hot and the riverbank is thick with good grey clay. Haul enough of it back to the booth and the master will keep the fires lit all week.",
		state = "active",
		progress = 3,
		goal = 10,
		icon = "quest",
		objectives = {
			{ text = "Find the riverbank dig site", done = true },
			{ text = "Haul 10 lumps of grey clay", done = false },
			{ text = "Stack them by the kiln door", done = false },
		},
		rewards = { { currency = "Cash", amount = 750 }, { currency = "Bux", amount = 12 } },
		tracked = true,
	},
	{
		id = "wheel_master",
		title = "STEADY HANDS",
		description = "Ten clean pulls on the wheel with no collapse. Slow the wheel, wet the clay, and let the rim find its own centre.",
		state = "active",
		progress = 7,
		goal = 10,
		icon = "target",
		objectives = {
			{ text = "Throw 10 pots without a collapse", done = false },
			{ text = "Keep the wall under 8mm", done = true },
		},
		rewards = { { currency = "Cash", amount = 1200 }, { icon = "crate", amount = 1, label = "CRATE" } },
		tracked = false,
	},
	{
		id = "glaze_run",
		title = "GLAZE RUN",
		description = "Three glazes, three firings, one afternoon. Anything that comes out of the kiln cracked does not count.",
		state = "active",
		progress = 1,
		goal = 3,
		icon = "sparkle",
		objectives = {
			{ text = "Mix the honey glaze", done = true },
			{ text = "Fire 3 glazed pieces", done = false },
			{ text = "Sell one at the stall", done = false },
		},
		rewards = { { currency = "Bux", amount = 25 } },
		tracked = false,
	},
	{
		id = "market_day",
		title = "MARKET DAY",
		description = "Sell twenty pieces before the stalls close. The crowd wants mugs, not statues.",
		state = "active",
		progress = 14,
		goal = 20,
		icon = "cart",
		objectives = {
			{ text = "Open the stall before noon", done = true },
			{ text = "Sell 20 pieces", done = false },
		},
		rewards = { { currency = "Cash", amount = 2400 } },
		tracked = false,
	},
	{
		id = "first_pot",
		title = "FIRST POT",
		description = "Every potter has a lopsided first pot somewhere on a shelf. This one is yours.",
		state = "completed",
		progress = 1,
		goal = 1,
		icon = "trophy",
		objectives = {
			{ text = "Throw your first pot", done = true },
			{ text = "Fire it without cracking", done = true },
		},
		rewards = { { currency = "Cash", amount = 200 } },
		tracked = false,
	},
	{
		id = "kiln_watch",
		title = "KILN WATCH",
		description = "Sit the overnight firing and keep the temperature above 900°C until dawn.",
		state = "completed",
		progress = 8,
		goal = 8,
		icon = "fire",
		objectives = {
			{ text = "Stoke the kiln 8 times", done = true },
		},
		rewards = { { currency = "Bux", amount = 40 } },
		tracked = false,
	},
	{
		id = "grand_commission",
		title = "GRAND COMMISSION",
		description = "The gallery wanted a two-metre urn by the festival. The festival came and went.",
		state = "failed",
		progress = 2,
		goal = 5,
		icon = "crown",
		objectives = {
			{ text = "Throw the base sections", done = true },
			{ text = "Join 5 sections before the deadline", done = false },
		},
		rewards = { { currency = "Cash", amount = 9000 } },
		tracked = false,
	},
}

-- Compact reward/amount format (doc §9 leaderboard convention: 1.2K).
local function formatAmount(value: number): string
	if value >= 1000000 then
		return string.format("%.1fM", value / 1000000)
	elseif value >= 1000 then
		return string.format("%.1fK", value / 1000)
	end
	return tostring(math.floor(value))
end

local function rewardColor(theme: Types.UITheme, reward: Reward): Color3
	if reward.currency then
		return UIChrome.CurrencyColor(theme, reward.currency)
	end
	return theme.Arcade.Gold
end

local function rewardIconName(reward: Reward): string
	if reward.icon then
		return reward.icon
	end
	if reward.currency then
		return string.lower(reward.currency)
	end
	return "star"
end

-- One reward chip: near-black arcade box, boxless icon + coloured amount.
local function buildRewardChip(theme: Types.UITheme, parent: Instance, reward: Reward, order: number)
	local chip = UIStyler.Frame("Reward" .. order)
	chip.BackgroundColor3 = theme.Arcade.NearBlack
	chip.BackgroundTransparency = 0
	chip.Size = UDim2.fromOffset(96, 26)
	chip.LayoutOrder = order
	UIChrome.Stroke(theme, "Arcade").Parent = chip
	UIChrome.GlassGradient().Parent = chip
	chip.Parent = parent

	local icon = IconArchive.Image(chip, rewardIconName(reward), 20, { golden = reward.currency == nil })
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 5, 0.5, 0)

	local amount = UIChrome.Text("Amount", 16, rewardColor(theme, reward))
	amount.Text = reward.label or formatAmount(reward.amount)
	amount.TextXAlignment = Enum.TextXAlignment.Left
	amount.Position = UDim2.fromOffset(30, 0)
	amount.Size = UDim2.new(1, -34, 1, 0)
	amount.RichText = false
	amount.TextTruncate = Enum.TextTruncate.AtEnd
	amount.Parent = chip
	return chip
end

local QuestJournalScreen = setmetatable({}, { __index = UIScreenBase })
QuestJournalScreen.__index = QuestJournalScreen

function QuestJournalScreen.new()
	local self = UIScreenBase.new("QuestJournalScreen", 6)
	self._quests = DEMO_QUESTS
	self._tab = "active"
	self._selectedId = nil :: string?
	self._tabButtons = {} :: { [string]: any }
	self._rows = {} :: { { quest: Quest, surface: Frame, stroke: UIStroke } }
	self._rowComponents = {} :: { any }
	self._detailComponents = {} :: { any }
	return setmetatable(self, QuestJournalScreen)
end

function QuestJournalScreen:_Toast(text: string, variant: string)
	local hud = self.ScreenController and self.ScreenController:GetScreen("hud")
	if hud then
		hud:PushToast({ text = text, variant = variant })
	end
end

function QuestJournalScreen:_Filtered(): { Quest }
	local out = {}
	for _, quest in self._quests do
		if quest.state == self._tab then
			table.insert(out, quest)
		end
	end
	return out
end

function QuestJournalScreen:_CountFor(state: string): number
	local n = 0
	for _, quest in self._quests do
		if quest.state == state then
			n += 1
		end
	end
	return n
end

function QuestJournalScreen:_BuildContent()
	-- GL layout language: the comic broadsheet page (see _BuildGLLayout below);
	-- the classic arcade modal build stays untouched.
	if self:LayoutKit() == "GL" then
		self:_BuildGLLayout()
		return
	end
	if self:LayoutKit() == "AC" then
		self:_BuildACLayout()
		return
	end
	local theme = self:GetTheme()

	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = "QUEST JOURNAL",
		sizePx = Vector2.new(CARD_W, CARD_H),
		onClose = function()
			self.ScreenController:HideScreen("quests")
		end,
	})
	self._modal = modal
	local content = modal.content

	-- Tab bar: blue arcade tabs, active = Blue / inactive = Ghost (ShopScreen's
	-- category-bar grammar).
	local tabBar = UIStyler.Frame("Tabs")
	tabBar.BackgroundTransparency = 1
	tabBar.Size = UDim2.new(1, 0, 0, TAB_H)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
	}).Parent = tabBar
	tabBar.Parent = content

	for i, tab in TABS do
		local button = UIButtonComponent.new()
		button:Create(tabBar, {
			text = tab.label,
			variant = tab.id == self._tab and "Blue" or "Ghost",
			size = UDim2.fromOffset(TAB_W, TAB_H),
			layoutOrder = i,
			onClick = function()
				self:_SelectTab(tab.id)
			end,
		})
		self._tabButtons[tab.id] = button
	end

	-- Left: the quest list.
	local list = Instance.new("ScrollingFrame")
	list.Name = "QuestList"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(0, BODY_Y)
	list.Size = UDim2.fromOffset(LIST_W, BODY_H)
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

	-- Right: the detail pane (UIChrome.Panel = surface + rim + glass sheen).
	local detail = UIChrome.Panel(theme, "Arcade", "Detail")
	detail.Position = UDim2.fromOffset(DETAIL_X, BODY_Y)
	detail.Size = UDim2.fromOffset(DETAIL_W, BODY_H)
	detail.Parent = content
	self._detail = detail

	local detailScroll = Instance.new("ScrollingFrame")
	detailScroll.Name = "DetailBody"
	detailScroll.BackgroundTransparency = 1
	detailScroll.BorderSizePixel = 0
	detailScroll.Position = UDim2.fromOffset(16, 16)
	detailScroll.Size = UDim2.new(1, -32, 1, -(16 + 16 + 60))
	detailScroll.CanvasSize = UDim2.new()
	detailScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	detailScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	detailScroll.ScrollBarThickness = SCROLLBAR
	detailScroll.ScrollBarImageColor3 = theme.Arcade.Gold
	detailScroll.Parent = detail
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 8),
	}).Parent = detailScroll
	self._detailScroll = detailScroll

	-- The action slot is fixed at the pane's foot so the scrolling body above
	-- it never pushes ABANDON off the card.
	local actionSlot = UIStyler.Frame("Action")
	actionSlot.BackgroundTransparency = 1
	actionSlot.AnchorPoint = Vector2.new(0, 1)
	actionSlot.Position = UDim2.new(0, 16, 1, -14)
	actionSlot.Size = UDim2.new(1, -32, 0, 48)
	actionSlot.Parent = detail
	self._actionSlot = actionSlot

	self:_Render()
end

function QuestJournalScreen:_SelectTab(tabId: string)
	if self._tab == tabId then
		return
	end
	self._tab = tabId
	self._selectedId = nil
	self:_Render()
end

function QuestJournalScreen:_Render()
	if self:LayoutKit() == "GL" then
		self:_GLRefresh()
		return
	end
	if self:LayoutKit() == "AC" then
		self:_ACRender()
		return
	end
	self:_RenderTabs()
	self:_RenderList()
	self:_RenderDetail()
end

function QuestJournalScreen:_RenderTabs()
	if self:LayoutKit() == "GL" then
		-- The GL tab bar carries the same counts; it is rebuilt only when the
		-- counts actually move (see _GLSyncTabs).
		self:_GLSyncTabs()
		return
	end
	for _, tab in TABS do
		local button = self._tabButtons[tab.id]
		if button then
			button:SetContent({
				text = string.format("%s  %d", tab.label, self:_CountFor(tab.id)),
				variant = tab.id == self._tab and "Blue" or "Ghost",
			})
		end
	end
end

function QuestJournalScreen:_RenderList()
	if self:LayoutKit() == "GL" then
		-- _ToggleTrack re-renders through here; under GL the pooled rows and the
		-- detail column refresh together.
		self:_GLRefresh()
		return
	end
	if self:LayoutKit() == "AC" then
		-- _ToggleTrack re-renders through here; under AC the whole page
		-- re-prints (list + detail) — dense raw rows, cheap by design.
		self:_ACRender()
		return
	end
	for _, component in self._rowComponents do
		component:Destroy()
	end
	table.clear(self._rowComponents)
	table.clear(self._rows)
	for _, child in self._list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local quests = self:_Filtered()
	if #quests == 0 then
		local empty = UIChrome.Text("Empty", 22, self:GetTheme().Arcade.GreyOwned)
		empty.Text = "NOTHING HERE YET"
		empty.Size = UDim2.new(1, -SCROLLBAR, 0, 80)
		empty.Parent = self._list
		return
	end

	-- First quest of the tab is pre-selected so the detail pane is never empty.
	if not self._selectedId then
		self._selectedId = quests[1].id
	end
	for index, quest in quests do
		self:_BuildRow(quest, index)
	end
	self:_RefreshSelection()
end

function QuestJournalScreen:_BuildRow(quest: Quest, index: number)
	local theme = self:GetTheme()

	-- Fixed transparent footprint: hover/press scale the inner surface only, so
	-- the row never reflows its neighbours in the list layout.
	local root = UIStyler.Frame("Row_" .. quest.id)
	root.BackgroundTransparency = 1
	root.Size = UDim2.new(1, -SCROLLBAR, 0, ROW_H)
	root.LayoutOrder = index
	root.Parent = self._list

	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 1
	hit.Parent = root

	local surface = UIStyler.Frame("Surface")
	surface.BackgroundColor3 = theme.Arcade.Row
	surface.BackgroundTransparency = theme.Arcade.RowTransparency
	surface.AnchorPoint = Vector2.new(0.5, 0.5)
	surface.Position = UDim2.fromScale(0.5, 0.5)
	surface.Size = UDim2.fromScale(1, 1)
	surface.ZIndex = 2
	local stroke = UIChrome.Stroke(theme, "Arcade")
	stroke.Parent = surface
	UIChrome.GlassGradient().Parent = surface
	surface.Parent = root

	local icon = IconArchive.Image(surface, quest.icon or "quest", 44, {
		golden = quest.state == "completed",
	})
	icon.AnchorPoint = Vector2.new(0, 0)
	icon.Position = UDim2.fromOffset(14, 16)

	local title = UIChrome.Text("Title", 22, theme.Colors.TextPrimary)
	title.Text = quest.title
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(70, 10)
	title.Size = UDim2.new(1, -190, 0, 26)
	title.RichText = false
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Parent = surface

	-- Quiet sub-line: the current objective, GothamMedium in ice blue (doc §2
	-- body font / §3.2 secondary notes).
	local current = quest.objectives[1]
	for _, objective in quest.objectives do
		if not objective.done then
			current = objective
			break
		end
	end
	local sub = UIChrome.BodyText("Objective", 15, theme.Arcade.IceBlue)
	sub.Text = current and current.text or ""
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.Position = UDim2.fromOffset(70, 40)
	sub.Size = UDim2.new(1, -190, 0, 20)
	sub.RichText = false
	sub.TextTruncate = Enum.TextTruncate.AtEnd
	sub.Parent = surface

	local ruler = UIProgressBarComponent.new()
	ruler:Create(surface, {
		value = quest.progress,
		maxValue = quest.goal,
		showText = true,
		size = UDim2.fromOffset(240, 24),
		position = UDim2.fromOffset(70, 68),
	})
	table.insert(self._rowComponents, ruler)

	local rewardRow = UIStyler.Frame("Rewards")
	rewardRow.BackgroundTransparency = 1
	rewardRow.Position = UDim2.fromOffset(326, 68)
	rewardRow.Size = UDim2.new(1, -338, 0, 26)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
	}).Parent = rewardRow
	rewardRow.Parent = surface
	for order, reward in quest.rewards do
		buildRewardChip(theme, rewardRow, reward, order)
	end

	-- TRACK toggle. Only an active quest can be tracked; the toggle on a
	-- finished quest is dimmed IN PLACE and still answers with a toast
	-- (doc §11.1/§11.2 — never removed, never dead).
	local trackable = quest.state == "active"
	local track = UIButtonComponent.new()
	track:Create(surface, {
		text = quest.tracked and "TRACKED" or "TRACK",
		variant = quest.tracked and "Gold" or "Ghost",
		dimmed = not trackable,
		size = UDim2.fromOffset(104, 32),
		position = UDim2.new(1, -12, 0, 12),
		anchorPoint = Vector2.new(1, 0),
		onClick = function()
			self:_ToggleTrack(quest)
		end,
	})
	table.insert(self._rowComponents, track)

	hit.Activated:Connect(function()
		self._selectedId = quest.id
		self:_RefreshSelection()
		self:_RenderDetail()
	end)
	-- Animate LAST, after the final colours (it snapshots the rest colour).
	UIChrome.Animate(theme, hit, surface)

	table.insert(self._rows, { quest = quest, surface = surface, stroke = stroke })
end

function QuestJournalScreen:_RefreshSelection()
	local theme = self:GetTheme()
	for _, row in self._rows do
		local selected = row.quest.id == self._selectedId
		row.stroke:Destroy()
		local stroke = UIChrome.Stroke(theme, "Arcade", selected and "Selection" or "Panel")
		stroke.Parent = row.surface
		row.stroke = stroke
	end
end

function QuestJournalScreen:_ToggleTrack(quest: Quest)
	if quest.state ~= "active" then
		self:_Toast("Only active quests can be tracked.", "Error")
		return
	end
	-- One tracked quest at a time — the HUD objective strip only has room for one.
	local turningOn = not quest.tracked
	for _, other in self._quests do
		other.tracked = false
	end
	quest.tracked = turningOn
	self:_RenderList()
	self:_Toast(turningOn and ("Now tracking " .. quest.title) or "Tracking cleared.", turningOn and "Success" or "Info")
end

function QuestJournalScreen:_Selected(): Quest?
	for _, quest in self._quests do
		if quest.id == self._selectedId then
			return quest
		end
	end
	return nil
end

function QuestJournalScreen:_RenderDetail()
	if self:LayoutKit() == "GL" then
		self:_GLRefreshDetail()
		return
	end
	local theme = self:GetTheme()
	for _, component in self._detailComponents do
		component:Destroy()
	end
	table.clear(self._detailComponents)
	for _, child in self._detailScroll:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for _, child in self._actionSlot:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local quest = self:_Selected()
	if not quest then
		local empty = UIChrome.Text("Empty", 20, theme.Arcade.GreyOwned)
		empty.Text = "SELECT A QUEST"
		empty.Size = UDim2.new(1, 0, 0, 60)
		empty.Parent = self._detailScroll
		return
	end

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local head = UIStyler.Frame("Head")
	head.BackgroundTransparency = 1
	head.Size = UDim2.new(1, -SCROLLBAR, 0, 56)
	head.LayoutOrder = nextOrder()
	head.Parent = self._detailScroll

	local headIcon = IconArchive.Image(head, quest.icon or "quest", 48, {
		golden = quest.state == "completed",
	})
	headIcon.AnchorPoint = Vector2.new(0, 0.5)
	headIcon.Position = UDim2.new(0, 0, 0.5, 0)

	local headTitle = UIChrome.Text("Title", 26, theme.Arcade.Gold)
	headTitle.Text = quest.title
	headTitle.TextXAlignment = Enum.TextXAlignment.Left
	headTitle.Position = UDim2.fromOffset(60, 0)
	headTitle.Size = UDim2.new(1, -60, 1, 0)
	headTitle.RichText = false
	headTitle.TextTruncate = Enum.TextTruncate.AtEnd
	headTitle.Parent = head

	local stateColors: { [string]: Color3 } = {
		active = theme.Arcade.SunburstGold,
		completed = theme.Arcade.Green,
		failed = theme.Arcade.Red,
	}
	local stateLine = UIChrome.Text("State", 17, stateColors[quest.state] or theme.Arcade.Gold)
	stateLine.Text = string.format("%s  ·  %d / %d", string.upper(quest.state), quest.progress, quest.goal)
	stateLine.TextXAlignment = Enum.TextXAlignment.Left
	stateLine.Size = UDim2.new(1, -SCROLLBAR, 0, 22)
	stateLine.LayoutOrder = nextOrder()
	stateLine.Parent = self._detailScroll

	local description = UIChrome.BodyText("Description", 16, theme.Colors.TextPrimary)
	description.Text = quest.description
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.TextYAlignment = Enum.TextYAlignment.Top
	description.Size = UDim2.new(1, -SCROLLBAR, 0, 0)
	description.AutomaticSize = Enum.AutomaticSize.Y
	description.TextWrapped = true
	description.LayoutOrder = nextOrder()
	description.Parent = self._detailScroll

	local objectivesHeader = UIChrome.Text("ObjectivesHeader", 18, theme.Arcade.Gold)
	objectivesHeader.Text = "OBJECTIVES"
	objectivesHeader.TextXAlignment = Enum.TextXAlignment.Left
	objectivesHeader.Size = UDim2.new(1, -SCROLLBAR, 0, 28)
	objectivesHeader.LayoutOrder = nextOrder()
	objectivesHeader.Parent = self._detailScroll

	for i, objective in quest.objectives do
		local row = UIStyler.Frame("Objective" .. i)
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, -SCROLLBAR, 0, 30)
		row.LayoutOrder = nextOrder()
		row.Parent = self._detailScroll

		if objective.done then
			local check = IconArchive.Image(row, "check", 22, { colorway = "Green" })
			check.AnchorPoint = Vector2.new(0, 0.5)
			check.Position = UDim2.new(0, 0, 0.5, 0)
		else
			-- Not-done reads as an empty arcade box, same footprint as the check.
			local box = UIStyler.Frame("Box")
			box.BackgroundColor3 = theme.Arcade.NearBlack
			box.BackgroundTransparency = 0
			box.AnchorPoint = Vector2.new(0, 0.5)
			box.Position = UDim2.new(0, 3, 0.5, 0)
			box.Size = UDim2.fromOffset(16, 16)
			UIChrome.Stroke(theme, "Arcade").Parent = box
			box.Parent = row
		end

		local text = UIChrome.BodyText("Text", 15, objective.done and theme.Arcade.GreyOwned or theme.Colors.TextPrimary)
		text.Text = objective.text
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.Position = UDim2.fromOffset(32, 0)
		text.Size = UDim2.new(1, -32, 1, 0)
		text.RichText = false
		text.TextTruncate = Enum.TextTruncate.AtEnd
		text.Parent = row
	end

	local rewardsHeader = UIChrome.Text("RewardsHeader", 18, theme.Arcade.Gold)
	rewardsHeader.Text = "REWARDS"
	rewardsHeader.TextXAlignment = Enum.TextXAlignment.Left
	rewardsHeader.Size = UDim2.new(1, -SCROLLBAR, 0, 28)
	rewardsHeader.LayoutOrder = nextOrder()
	rewardsHeader.Parent = self._detailScroll

	local rewardRow = UIStyler.Frame("Rewards")
	rewardRow.BackgroundTransparency = 1
	rewardRow.Size = UDim2.new(1, -SCROLLBAR, 0, 30)
	rewardRow.LayoutOrder = nextOrder()
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
	}).Parent = rewardRow
	rewardRow.Parent = self._detailScroll
	for i, reward in quest.rewards do
		buildRewardChip(theme, rewardRow, reward, i)
	end

	-- The action slot: ABANDON for an active quest, an inert state button
	-- otherwise (recoloured grey in place — doc §11.2).
	local action = UIButtonComponent.new()
	if quest.state == "active" then
		action:Create(self._actionSlot, {
			text = "ABANDON",
			variant = "Red",
			size = UDim2.new(1, 0, 0, 48),
			onClick = function()
				self:_PromptAbandon(quest)
			end,
		})
	else
		action:Create(self._actionSlot, {
			text = quest.state == "completed" and "COMPLETED" or "FAILED",
			variant = "Grey",
			enabled = false,
			size = UDim2.new(1, 0, 0, 48),
		})
	end
	table.insert(self._detailComponents, action)
end

function QuestJournalScreen:_PromptAbandon(quest: Quest)
	self.ScreenController:ShowModal({
		kind = "Danger",
		title = "ABANDON QUEST",
		body = string.format("Abandon %s? All progress on it is lost.", quest.title),
		confirmKey = "ABANDON",
		cancelKey = "KEEP IT",
		onConfirm = function()
			quest.state = "failed"
			quest.tracked = false
			self._selectedId = nil
			self:_Render()
			self:_Toast(quest.title .. " abandoned.", "Warning")
		end,
	})
end

-- _EnsureBuilt has already rendered with the data the screen was holding, so
-- only a fresh payload re-renders here.
function QuestJournalScreen:_OnShow(data: any?)
	if data and data.quests then
		self._quests = data.quests
		self._selectedId = nil
		self:_Render()
	end
	if self._modal then
		UIChrome.PopIn(self:GetTheme(), self._modal.content)
	end
end

function QuestJournalScreen:Update(data: any)
	if data and data.quests then
		self._quests = data.quests
		self._selectedId = nil
		if self._built then
			self:_Render()
		end
	end
end

function QuestJournalScreen:Destroy()
	for _, component in self._rowComponents do
		component:Destroy()
	end
	table.clear(self._rowComponents)
	for _, component in self._detailComponents do
		component:Destroy()
	end
	table.clear(self._detailComponents)
	for _, button in self._tabButtons do
		button:Destroy()
	end
	table.clear(self._tabButtons)
	UIScreenBase.Destroy(self)
end

-- ========================================================================
-- AC layout — the "MISSIONS" terminal page (theme.LayoutKit == "AC").
-- Left: one dense row per quest (name + status marker: accent ACTIVE, dim
-- DONE, error FAILED). Right: the detail pane — title, status/progress
-- line, objectives as tick rows (complete ones dim), reward lines in
-- currency colours, and the same TRACK / ABANDON callbacks as classic
-- (_ToggleTrack / _PromptAbandon). All raw instances: the style rebuild
-- throws the page away wholesale, so there is nothing to unwind.
-- ========================================================================

local AC_LIST_W = 400
local AC_ROW_H = 26

function QuestJournalScreen:_BuildACLayout()
	local theme = self:GetTheme()

	local shell = ACLayoutKit.Shell(theme, self.Root, "MISSIONS")
	-- _OnShow pops self._modal.content in both layouts; under AC that is the
	-- shell's content region.
	self._modal = { content = shell.content } :: any
	ACLayoutKit.SetHints(shell, { { key = "ESC", action = "CLOSE" } })

	local close = ACLayoutKit.ActionButton(theme, shell.topRight, "CLOSE", function()
		self.ScreenController:HideScreen("quests")
	end)
	close.Size = UDim2.fromOffset(96, 26)

	-- THE one UITicker handler for this screen backs the [ESC] hint; bound to
	-- the page so a style rebuild unregisters it.
	local escDown = false
	UITicker.Register(function()
		local pressed = UserInputService:IsKeyDown(Enum.KeyCode.Escape)
		if pressed and not escDown and self._visible then
			self.ScreenController:HideScreen("quests")
		end
		escDown = pressed
	end, shell.page)

	-- Left: the mission list.
	local listHost = UIStyler.Frame("ListHost")
	listHost.BackgroundTransparency = 1
	listHost.Size = UDim2.new(0, AC_LIST_W, 1, 0)
	listHost.Parent = shell.content

	ACLayoutKit.SectionLabel(theme, listHost, "MISSION LIST")

	local list = Instance.new("ScrollingFrame")
	list.Name = "Missions"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(0, 24)
	list.Size = UDim2.new(1, 0, 1, -24)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = 4
	list.ScrollBarImageColor3 = theme.Colors.Accent
	list.Parent = listHost
	UIStyler.ListLayout({
		Padding = UDim.new(0, 0),
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	}).Parent = list
	self._acList = list

	local divider = ACLayoutKit.Rule(theme, shell.content, 0.75)
	divider.Size = UDim2.new(0, 1, 1, 0)
	divider.Position = UDim2.fromOffset(AC_LIST_W + 12, 0)

	-- Right: the detail pane, marked live with corner brackets.
	local detailHost = UIStyler.Frame("DetailHost")
	detailHost.BackgroundTransparency = 1
	detailHost.Position = UDim2.fromOffset(AC_LIST_W + 26, 0)
	detailHost.Size = UDim2.new(1, -(AC_LIST_W + 26), 1, 0)
	detailHost.Parent = shell.content
	ACLayoutKit.Brackets(theme, detailHost)

	local detailScroll = Instance.new("ScrollingFrame")
	detailScroll.Name = "DetailBody"
	detailScroll.BackgroundTransparency = 1
	detailScroll.BorderSizePixel = 0
	detailScroll.Position = UDim2.fromOffset(12, 10)
	detailScroll.Size = UDim2.new(1, -24, 1, -60)
	detailScroll.CanvasSize = UDim2.new()
	detailScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	detailScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	detailScroll.ScrollBarThickness = 4
	detailScroll.ScrollBarImageColor3 = theme.Colors.Accent
	detailScroll.Parent = detailHost
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 6),
	}).Parent = detailScroll
	self._acDetailScroll = detailScroll

	-- Fixed action line at the pane's foot (classic's actionSlot grammar) so
	-- the scrolling body never pushes the actions off the page.
	local actionRow = UIStyler.Frame("Actions")
	actionRow.BackgroundTransparency = 1
	actionRow.AnchorPoint = Vector2.new(0, 1)
	actionRow.Position = UDim2.new(0, 12, 1, -8)
	actionRow.Size = UDim2.new(1, -24, 0, 30)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
	}).Parent = actionRow
	actionRow.Parent = detailHost
	self._acActionRow = actionRow

	self:_ACRender()
end

function QuestJournalScreen:_ACRender()
	local theme = self:GetTheme()
	for _, child in self._acList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	if #self._quests == 0 then
		local empty = UIChrome.BodyText("Empty", 12, theme.Colors.TextSecondary)
		empty.Text = "NO MISSIONS ON RECORD"
		empty.TextXAlignment = Enum.TextXAlignment.Left
		empty.Size = UDim2.new(1, 0, 0, 40)
		empty.Parent = self._acList
		self:_ACRenderDetail()
		return
	end

	-- First quest pre-selected so the detail pane is never empty.
	if not self._selectedId then
		self._selectedId = self._quests[1].id
	end

	for index, quest in self._quests do
		local marker: string
		local markerColor: Color3? = nil
		local markerDim = false
		if quest.state == "active" then
			marker = "ACTIVE"
			markerColor = theme.Colors.Accent
		elseif quest.state == "completed" then
			marker = "DONE"
			markerDim = true
		else
			marker = "FAILED"
			markerColor = theme.Colors.Error
		end

		local row = ACLayoutKit.ListRow(theme, self._acList, {
			{ text = quest.title, widthScale = 0.68, dim = quest.state ~= "active" },
			{ text = marker, widthScale = 0.32, align = Enum.TextXAlignment.Right, color = markerColor, dim = markerDim },
		}, { heightPx = AC_ROW_H, layoutOrder = index, clickable = true })
		if quest.id == self._selectedId then
			row.BackgroundTransparency = 0.85
			local notch = UIStyler.Frame("Notch")
			notch.BackgroundColor3 = theme.Colors.Accent
			notch.BorderSizePixel = 0
			notch.Size = UDim2.new(0, 3, 1, -8)
			notch.Position = UDim2.new(0, 0, 0, 4)
			notch.Parent = row
		end
		local button = row :: TextButton
		button.Activated:Connect(function()
			self._selectedId = quest.id
			self:_ACRender()
		end)
	end

	self:_ACRenderDetail()
end

function QuestJournalScreen:_ACRenderDetail()
	local theme = self:GetTheme()
	for _, child in self._acDetailScroll:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for _, child in self._acActionRow:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local quest = self:_Selected()
	if not quest then
		local empty = UIChrome.BodyText("Empty", 12, theme.Colors.TextSecondary)
		empty.Text = "NO MISSION SELECTED"
		empty.TextXAlignment = Enum.TextXAlignment.Left
		empty.Size = UDim2.new(1, 0, 0, 40)
		empty.Parent = self._acDetailScroll
		return
	end

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local title = UIChrome.Text("Title", 16, theme.Colors.TextPrimary)
	title.Text = quest.title
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.RichText = false
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Size = UDim2.new(1, 0, 0, 24)
	title.LayoutOrder = nextOrder()
	title.Parent = self._acDetailScroll

	local stateColors: { [string]: Color3 } = {
		active = theme.Colors.Accent,
		completed = theme.Colors.TextSecondary,
		failed = theme.Colors.Error,
	}
	local status = UIChrome.BodyText("Status", 12, stateColors[quest.state] or theme.Colors.TextSecondary)
	status.Text = string.format("%s  //  %d / %d", string.upper(quest.state), quest.progress, quest.goal)
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Size = UDim2.new(1, 0, 0, 16)
	status.LayoutOrder = nextOrder()
	status.Parent = self._acDetailScroll

	local rule = ACLayoutKit.Rule(theme, self._acDetailScroll)
	rule.LayoutOrder = nextOrder()

	local description = UIChrome.BodyText("Description", 12, theme.Colors.TextSecondary)
	description.Text = quest.description
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.TextYAlignment = Enum.TextYAlignment.Top
	description.TextWrapped = true
	description.Size = UDim2.new(1, 0, 0, 0)
	description.AutomaticSize = Enum.AutomaticSize.Y
	description.LayoutOrder = nextOrder()
	description.Parent = self._acDetailScroll

	ACLayoutKit.SectionLabel(theme, self._acDetailScroll, "OBJECTIVES", nextOrder())

	for _, objective in quest.objectives do
		local done = objective.done == true
		ACLayoutKit.ListRow(theme, self._acDetailScroll, {
			{ text = if done then "[x]" else "[ ]", widthScale = 0.1, color = if done then nil else theme.Colors.Accent, dim = done },
			{ text = objective.text, widthScale = 0.9, dim = done },
		}, { heightPx = 20, layoutOrder = nextOrder() })
	end

	ACLayoutKit.SectionLabel(theme, self._acDetailScroll, "REWARDS", nextOrder())

	for _, reward in quest.rewards do
		ACLayoutKit.ListRow(theme, self._acDetailScroll, {
			{ text = "+" .. formatAmount(reward.amount), widthScale = 0.3, color = rewardColor(theme, reward) },
			{ text = string.upper(reward.currency or reward.label or "REWARD"), widthScale = 0.7, dim = true },
		}, { heightPx = 20, layoutOrder = nextOrder() })
	end

	-- Same callbacks as classic: TRACK answers through _ToggleTrack (which
	-- toasts on a finished quest — never removed, never dead), ABANDON
	-- through _PromptAbandon.
	local track = ACLayoutKit.ActionButton(theme, self._acActionRow, if quest.tracked then "TRACKED" else "TRACK", function()
		self:_ToggleTrack(quest)
	end)
	if quest.tracked then
		track.TextColor3 = theme.Colors.Accent
	elseif quest.state ~= "active" then
		track.TextColor3 = theme.Colors.TextSecondary
	end

	if quest.state == "active" then
		local abandon = ACLayoutKit.ActionButton(theme, self._acActionRow, "ABANDON", function()
			self:_PromptAbandon(quest)
		end)
		abandon.TextColor3 = theme.Colors.Error
	else
		local state = UIChrome.BodyText("State", 12, theme.Colors.TextSecondary)
		state.Text = if quest.state == "completed" then "MISSION COMPLETE" else "MISSION FAILED"
		state.TextXAlignment = Enum.TextXAlignment.Left
		state.Size = UDim2.fromOffset(180, 30)
		state.Parent = self._acActionRow
	end
end

-- ========================================================================
-- GL layout (theme.LayoutKit == "GL") — the comic quest broadsheet, composed
-- entirely from GLLayoutKit (the approved shop composition, not a re-derived
-- one). PRESENTATION ONLY: the same _Filtered/_CountFor reads and the same
-- _SelectTab / _ToggleTrack / _PromptAbandon callbacks as the classic build.
--
--   * kit Page — charcoal plate, halftone, slanted banner breaking the
--     top-left, tilted close chip breaking the top-right;
--   * kit Tabs — ACTIVE / COMPLETED / FAILED carrying their live counts;
--   * kit ListRows — alternating tilt, the gold objective count in the value
--     slot, a gold TRACKED badge overhanging the plate;
--   * the detail column — kit Card (ART SLOT: quest art is content we cannot
--     generate), kit SectionLabels, POOLED kit PriceChips for the rewards and
--     kit ActionButtons wired straight to _ToggleTrack / _PromptAbandon.
--
-- Every shadow arrives as a budget HANDLE: pooled rows disable theirs on
-- release and _OnTeardown releases the lot.
-- ========================================================================

local GL_PAGE = Vector2.new(1180, 720)
local GL_LIST_W = 560
local GL_DETAIL_X = GL_LIST_W + 24
local GL_BODY_Y = 64
local GL_BODY_H = 558
local GL_ROW_H = 76
local GL_CARD_H = 190
local GL_ACTION_H = 56

-- Kit builders push their shadow handles into whatever sink they are handed.
-- Collect through a fresh bucket so the ROW keeps a reference (pooling
-- disables handles rather than destroying them) while the screen-wide list
-- still owns every handle for _OnTeardown.
local function glTake(self: any, bucket: { any }): any
	for _, handle in bucket do
		table.insert(self._glShadows, handle)
	end
	return bucket[1]
end

local function glObjectiveCount(quest: Quest): (number, number)
	local done = 0
	for _, objective in quest.objectives do
		if objective.done then
			done += 1
		end
	end
	return done, #quest.objectives
end

-- The one-line "what now" sub-caption: the first unfinished objective.
local function glCurrentObjective(quest: Quest): string
	for _, objective in quest.objectives do
		if not objective.done then
			return objective.text
		end
	end
	local last = quest.objectives[#quest.objectives]
	return last and last.text or ""
end

local function glStateFill(theme: Types.UITheme, state: string): Color3
	if state == "completed" then
		return theme.Arcade.Gold
	elseif state == "failed" then
		return theme.Arcade.Red
	end
	return theme.Colors.Primary
end

function QuestJournalScreen:_BuildGLLayout()
	local theme = self:GetTheme()

	local page = GLLayoutKit.Page(theme, self.Root, {
		titleText = "QUEST JOURNAL",
		sizePx = GL_PAGE,
		onClose = function()
			self.ScreenController:HideScreen("quests")
		end,
	})
	-- The Page's own sink becomes the screen's shadow list; every later kit
	-- call feeds the same list.
	self._glShadows = page.shadows
	self._glRows = {} :: { any }
	self._glRewardChips = {} :: { any }
	self._glTabSig = nil :: string?
	-- _OnShow pops self._modal.content in every layout; under GL that is the
	-- page's content region.
	self._modal = { content = page.content } :: any
	local content = page.content

	-- Tracked/objective counters live in the page's top-right slot.
	local counter = GLLayoutKit.PriceChip(theme, page.topRight, self._glShadows)
	counter.root.Size = UDim2.fromOffset(190, 40)
	counter.icon.Visible = false
	counter.amount.Position = UDim2.fromOffset(14, 0)
	counter.amount.Size = UDim2.new(1, -24, 1, 0)
	counter.amount.TextXAlignment = Enum.TextXAlignment.Center
	self._glCounter = counter

	local tabHost = UIStyler.Frame("TabHost")
	tabHost.BackgroundTransparency = 1
	tabHost.Size = UDim2.new(1, 0, 0, 52)
	tabHost.ZIndex = 4
	tabHost.Parent = content
	self._glTabHost = tabHost

	-- Left: the pooled quest rows.
	local list = Instance.new("ScrollingFrame")
	list.Name = "GLQuests"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(0, GL_BODY_Y)
	list.Size = UDim2.fromOffset(GL_LIST_W, GL_BODY_H)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = theme.Arcade.Gold
	list.Parent = content
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 16),
	}).Parent = list
	-- Room inside the frame for the badges that overhang their plates, so the
	-- overhang reads as intentional instead of being clipped at the edge.
	local listPad = Instance.new("UIPadding")
	listPad.PaddingTop = UDim.new(0, 18)
	listPad.PaddingLeft = UDim.new(0, 16)
	listPad.PaddingRight = UDim.new(0, 14)
	listPad.PaddingBottom = UDim.new(0, 18)
	listPad.Parent = list
	self._glList = list

	local empty = GLLayoutKit.Text(theme, 24, theme.Colors.TextSecondary, "Empty")
	empty.Text = "NOTHING HERE YET"
	empty.Size = UDim2.new(1, 0, 0, 90)
	empty.Visible = false
	empty.Parent = list
	self._glEmpty = empty

	-- Right: the detail column.
	local detail = UIStyler.Frame("GLDetail")
	detail.BackgroundTransparency = 1
	detail.Position = UDim2.fromOffset(GL_DETAIL_X, GL_BODY_Y)
	detail.Size = UDim2.new(1, -GL_DETAIL_X, 0, GL_BODY_H)
	detail.Parent = content

	local card = GLLayoutKit.Card(theme, detail, self._glShadows)
	card.root.Size = UDim2.new(1, 0, 0, GL_CARD_H)
	card.name.RichText = false
	self._glCard = card

	local stateBucket = {}
	local stateBadge, stateBadgeText = GLLayoutKit.Badge(theme, card.body, "ACTIVE", theme.Colors.Primary, stateBucket)
	glTake(self, stateBucket)
	self._glStateBadge = stateBadge
	self._glStateBadgeText = stateBadgeText

	local detailScroll = Instance.new("ScrollingFrame")
	detailScroll.Name = "GLDetailBody"
	detailScroll.BackgroundTransparency = 1
	detailScroll.BorderSizePixel = 0
	detailScroll.Position = UDim2.fromOffset(0, GL_CARD_H + 12)
	detailScroll.Size = UDim2.new(1, 0, 0, GL_BODY_H - GL_CARD_H - 12 - GL_ACTION_H - 10)
	detailScroll.CanvasSize = UDim2.new()
	detailScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	detailScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	detailScroll.ScrollBarThickness = 6
	detailScroll.ScrollBarImageColor3 = theme.Arcade.Gold
	detailScroll.Parent = detail
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 8),
	}).Parent = detailScroll
	self._glDetailScroll = detailScroll

	local stateLine = GLLayoutKit.Text(theme, 20, theme.Arcade.Gold, "State")
	stateLine.TextXAlignment = Enum.TextXAlignment.Left
	stateLine.Size = UDim2.new(1, -10, 0, 26)
	stateLine.LayoutOrder = 1
	stateLine.Parent = detailScroll
	self._glStateLine = stateLine

	local description = GLLayoutKit.BodyText(theme, 15, theme.Colors.TextPrimary, "Description")
	description.RichText = false
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.TextYAlignment = Enum.TextYAlignment.Top
	description.TextWrapped = true
	description.AutomaticSize = Enum.AutomaticSize.Y
	description.Size = UDim2.new(1, -10, 0, 0)
	description.LayoutOrder = 2
	description.Parent = detailScroll
	self._glDescription = description

	local objectivesLabel = GLLayoutKit.SectionLabel(theme, detailScroll, "OBJECTIVES")
	objectivesLabel.LayoutOrder = 3
	GLLayoutKit.Divider(theme, detailScroll).LayoutOrder = 4

	local objectivesHost = UIStyler.Frame("Objectives")
	objectivesHost.BackgroundTransparency = 1
	objectivesHost.AutomaticSize = Enum.AutomaticSize.Y
	objectivesHost.Size = UDim2.new(1, -10, 0, 0)
	objectivesHost.LayoutOrder = 5
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 4),
	}).Parent = objectivesHost
	objectivesHost.Parent = detailScroll
	self._glObjectivesHost = objectivesHost

	local rewardsLabel = GLLayoutKit.SectionLabel(theme, detailScroll, "REWARDS")
	rewardsLabel.LayoutOrder = 6
	GLLayoutKit.Divider(theme, detailScroll).LayoutOrder = 7

	local rewardsHost = UIStyler.Frame("Rewards")
	rewardsHost.BackgroundTransparency = 1
	rewardsHost.Size = UDim2.new(1, -10, 0, 46)
	rewardsHost.LayoutOrder = 8
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
	}).Parent = rewardsHost
	rewardsHost.Parent = detailScroll
	self._glRewardsHost = rewardsHost

	-- The action slot is pinned at the column's foot so the scrolling body
	-- above it can never push TRACK / ABANDON off the page (classic grammar).
	local actionRow = UIStyler.Frame("Actions")
	actionRow.BackgroundTransparency = 1
	actionRow.AnchorPoint = Vector2.new(0, 1)
	actionRow.Position = UDim2.fromScale(0, 1)
	actionRow.Size = UDim2.new(1, 0, 0, GL_ACTION_H)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 14),
	}).Parent = actionRow
	actionRow.Parent = detail

	-- Both actions run the EXACT classic callbacks (_ToggleTrack toasts by
	-- itself on a finished quest; _PromptAbandon raises the danger modal), so
	-- the buttons are built once and only their skin changes per selection.
	local trackBucket = {}
	local track = GLLayoutKit.ActionButton(theme, actionRow, "TRACK", function()
		local quest = self:_Selected()
		if quest then
			self:_ToggleTrack(quest)
		end
	end, trackBucket)
	glTake(self, trackBucket)
	track.LayoutOrder = 1
	self._glTrack = track
	self._glTrackPlate = track:FindFirstChild("Plate") :: ImageLabel
	self._glTrackLabel = track:FindFirstChild("Label") :: TextLabel

	local abandonBucket = {}
	local abandon = GLLayoutKit.ActionButton(theme, actionRow, "ABANDON", function()
		local quest = self:_Selected()
		-- Mirrors the classic inert state button: a finished quest's slot is
		-- dimmed IN PLACE and does nothing.
		if quest and quest.state == "active" then
			self:_PromptAbandon(quest)
		end
	end, abandonBucket)
	glTake(self, abandonBucket)
	abandon.LayoutOrder = 2
	self._glAbandon = abandon
	self._glAbandonPlate = abandon:FindFirstChild("Plate") :: ImageLabel
	self._glAbandonLabel = abandon:FindFirstChild("Label") :: TextLabel

	self:_GLRefresh()
end

-- The tab bar carries live counts, so it is rebuilt only when a count moves
-- (abandoning a quest) — never on a plain re-render.
function QuestJournalScreen:_GLSyncTabs()
	if not self._glTabHost then
		return
	end
	local theme = self:GetTheme()
	local signature = string.format(
		"%d|%d|%d",
		self:_CountFor("active"),
		self:_CountFor("completed"),
		self:_CountFor("failed")
	)
	if signature ~= self._glTabSig then
		self._glTabSig = signature
		if self._glTabs then
			-- Tabs carry no shadow handles, so dropping the frame leaks nothing.
			self._glTabs.frame:Destroy()
		end
		local tabs = GLLayoutKit.Tabs(theme, self._glTabHost, { widthPx = 176 })
		for _, tab in TABS do
			tabs.Add(string.format("%s  %d", tab.label, self:_CountFor(tab.id)), tab.id, function()
				self:_SelectTab(tab.id)
			end)
		end
		self._glTabs = tabs
	end
	self._glTabs.Select(self._tab)
end

-- One pooled quest row: kit ListRow (alternating tilt from its index) plus
-- the sub-caption, the gold selection slash and the TRACKED badge.
function QuestJournalScreen:_GLBuildRow(theme: Types.UITheme, index: number): any
	local plateBucket = {}
	local root, plate, name, value = GLLayoutKit.ListRow(theme, self._glList, {
		heightPx = GL_ROW_H,
		layoutOrder = index,
		clickable = true,
		tiltIndex = index,
	}, plateBucket)

	name.RichText = false
	name.Position = UDim2.fromOffset(18, 8)
	name.Size = UDim2.new(0.62, 0, 0, 30)
	value.Position = UDim2.new(1, -16, 0, 8)
	value.Size = UDim2.new(0.32, 0, 0, 30)

	local sub = GLLayoutKit.BodyText(theme, 14, theme.Arcade.IceBlue, "Objective")
	sub.RichText = false
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.TextTruncate = Enum.TextTruncate.AtEnd
	sub.Position = UDim2.fromOffset(18, 40)
	sub.Size = UDim2.new(0.78, 0, 0, 22)
	sub.ZIndex = 3
	sub.Parent = plate

	-- Selection is the pack's gold slash, tilted with the axis — never a
	-- recoloured plate alone.
	local slash = UIStyler.Frame("Slash")
	slash.BackgroundColor3 = theme.Arcade.Gold
	slash.BorderSizePixel = 0
	slash.AnchorPoint = Vector2.new(0, 0.5)
	slash.Position = UDim2.new(0, 6, 0.5, 0)
	slash.Size = UDim2.fromOffset(5, GL_ROW_H - 24)
	slash.Rotation = GLLayoutKit.TILT
	slash.Visible = false
	slash.ZIndex = 4
	slash.Parent = plate

	local badgeBucket = {}
	local badge, badgeText = GLLayoutKit.Badge(theme, plate, "TRACKED", theme.Arcade.Gold, badgeBucket)
	badgeText.TextColor3 = theme.Studio.TextDark -- pack law: ink-on-light is heat-brown, never black
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.Position = UDim2.new(1, 14, 0, -14)
	badge.Visible = false

	return {
		root = root,
		plate = plate,
		name = name,
		value = value,
		sub = sub,
		slash = slash,
		badge = badge,
		plateShadow = glTake(self, plateBucket),
		badgeShadow = glTake(self, badgeBucket),
		clickConn = nil :: RBXScriptConnection?,
	}
end

-- Index-keyed pooling: a row's tilt comes from its POSITION, so reusing row
-- i for whatever quest lands at position i keeps the diagonal agreeing.
function QuestJournalScreen:_GLRefresh()
	if not self._glList then
		return -- built under another layout; the next Show rebuilds
	end
	local theme = self:GetTheme()
	self:_GLSyncTabs()

	local quests = self:_Filtered()
	-- First quest of the tab is pre-selected so the detail column is never
	-- empty (the classic rule).
	if not self._selectedId and #quests > 0 then
		self._selectedId = quests[1].id
	end
	self._glEmpty.Visible = #quests == 0

	local tracked = 0
	for _, quest in self._quests do
		if quest.tracked then
			tracked += 1
		end
	end
	self._glCounter.amount.Text = string.format("%d TRACKED", tracked)

	for index, quest in quests do
		local entry = self._glRows[index]
		if not entry then
			entry = self:_GLBuildRow(theme, index)
			self._glRows[index] = entry
		end
		entry.root.Visible = true
		entry.plateShadow:SetEnabled(true)

		local selected = quest.id == self._selectedId
		local done, total = glObjectiveCount(quest)
		entry.name.Text = quest.title
		entry.name.TextColor3 = quest.state == "active" and theme.Colors.TextPrimary or theme.Colors.TextSecondary
		entry.sub.Text = glCurrentObjective(quest)
		entry.value.Text = string.format("%d / %d", done, total)
		entry.plate.ImageColor3 = selected and UIStyler.Lighten(theme.Arcade.Row, 0.14) or theme.Arcade.Row
		entry.slash.Visible = selected
		entry.badge.Visible = quest.tracked == true
		entry.badgeShadow:SetEnabled(quest.tracked == true)

		if entry.clickConn then
			entry.clickConn:Disconnect()
		end
		entry.clickConn = (entry.root :: TextButton).Activated:Connect(function()
			self._selectedId = quest.id
			self:_GLRefresh()
		end)
	end

	-- Surplus rows go back to the pool: hidden, shadows DISABLED, never
	-- destroyed (the pack pooling law).
	for index = #quests + 1, #self._glRows do
		local entry = self._glRows[index]
		entry.root.Visible = false
		entry.plateShadow:SetEnabled(false)
		entry.badgeShadow:SetEnabled(false)
		if entry.clickConn then
			entry.clickConn:Disconnect()
			entry.clickConn = nil
		end
	end

	self:_GLRefreshDetail()
end

-- One pooled reward chip (ink plate + gold numerals — the pack's only legal
-- value treatment).
function QuestJournalScreen:_GLRewardChip(theme: Types.UITheme, index: number): any
	local chip = self._glRewardChips[index]
	if not chip then
		local bucket = {}
		chip = GLLayoutKit.PriceChip(theme, self._glRewardsHost, bucket)
		chip.root.Size = UDim2.fromOffset(168, 40)
		chip.root.LayoutOrder = index
		-- No currency glyph is available on a quest reward, so the chip reads
		-- as amount + unit rather than borrowing an icon set.
		chip.icon.Visible = false
		chip.amount.Position = UDim2.fromOffset(14, 0)
		chip.amount.Size = UDim2.new(1, -24, 1, 0)
		glTake(self, bucket)
		self._glRewardChips[index] = chip
	end
	return chip
end

-- "750 CASH" / "1 CRATE": amount + unit, since a quest reward carries no
-- currency ART id to put in the chip's glyph slot.
local function glRewardText(reward: Reward): string
	if reward.currency then
		return string.format("%s %s", formatAmount(reward.amount), string.upper(reward.currency))
	end
	if reward.label then
		return string.format("%s %s", formatAmount(reward.amount), string.upper(reward.label))
	end
	return formatAmount(reward.amount)
end

function QuestJournalScreen:_GLRefreshDetail()
	if not self._glDetailScroll then
		return
	end
	local theme = self:GetTheme()
	local quest = self:_Selected()

	for _, child in self._glObjectivesHost:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy() -- plain text lines: no shadow handles to release
		end
	end

	if not quest then
		self._glCard.root.Visible = false
		self._glStateBadge.Visible = false
		self._glStateLine.Text = "SELECT A QUEST"
		self._glDescription.Text = ""
		self._glTrack.Visible = false
		self._glAbandon.Visible = false
		for _, chip in self._glRewardChips do
			chip.root.Visible = false
			chip.shadowHandle:SetEnabled(false)
		end
		return
	end

	self._glCard.root.Visible = true
	self._glTrack.Visible = true
	self._glAbandon.Visible = true
	self._glCard.name.Text = quest.title
	self._glStateBadge.Visible = true
	self._glStateBadge.ImageColor3 = glStateFill(theme, quest.state)
	self._glStateBadgeText.Text = string.upper(quest.state)
	self._glStateBadgeText.TextColor3 = quest.state == "completed" and theme.Studio.TextDark or theme.Colors.TextPrimary

	local done, total = glObjectiveCount(quest)
	self._glStateLine.Text = string.format("%s  //  %d / %d  //  %d OF %d DONE", string.upper(quest.state), quest.progress, quest.goal, done, total)
	self._glDescription.Text = quest.description

	for index, objective in quest.objectives do
		local line = UIStyler.Frame("Objective" .. index)
		line.BackgroundTransparency = 1
		line.Size = UDim2.new(1, 0, 0, 28)
		line.LayoutOrder = index
		line.Parent = self._glObjectivesHost

		local mark = GLLayoutKit.Slice(theme, "starSmall", objective.done and theme.Arcade.Gold or theme.Colors.Disabled, "Mark")
		mark.AnchorPoint = Vector2.new(0, 0.5)
		mark.Position = UDim2.new(0, 0, 0.5, 0)
		mark.Size = UDim2.fromOffset(18, 18)
		mark.Rotation = GLLayoutKit.TILT * 2
		mark.Parent = line

		local text = GLLayoutKit.BodyText(theme, 15, objective.done and theme.Colors.TextSecondary or theme.Colors.TextPrimary, "Text")
		text.RichText = false
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.TextTruncate = Enum.TextTruncate.AtEnd
		text.Position = UDim2.fromOffset(28, 0)
		text.Size = UDim2.new(1, -28, 1, 0)
		text.Parent = line
	end

	for index, reward in quest.rewards do
		local chip = self:_GLRewardChip(theme, index)
		chip.root.Visible = true
		chip.shadowHandle:SetEnabled(true)
		chip.amount.Text = string.format(
			"%s %s",
			reward.label or formatAmount(reward.amount),
			string.upper(reward.currency or (reward.label and "" or "REWARD"))
		)
	end
	for index = #quest.rewards + 1, #self._glRewardChips do
		local chip = self._glRewardChips[index]
		chip.root.Visible = false
		chip.shadowHandle:SetEnabled(false)
	end

	local active = quest.state == "active"
	self._glTrackLabel.Text = quest.tracked and "TRACKED" or "TRACK"
	self._glTrackPlate.ImageColor3 = quest.tracked and theme.Arcade.Gold or theme.Colors.Primary
	self._glTrackLabel.TextColor3 = quest.tracked and theme.Studio.TextDark or theme.Colors.TextPrimary
	self._glAbandonLabel.Text = if active then "ABANDON" elseif quest.state == "completed" then "COMPLETED" else "FAILED"
	self._glAbandonPlate.ImageColor3 = active and theme.Arcade.Red or theme.Arcade.GreyClaimed
end

-- A style rebuild destroys the Gui, but UIShadow BUDGET counts live in
-- StyleKit.Capabilities and only fall when a handle is released.
function QuestJournalScreen:_OnTeardown()
	GLLayoutKit.ReleaseShadows(self._glShadows)
	if self._glRows then
		for _, entry in self._glRows do
			if entry.clickConn then
				entry.clickConn:Disconnect()
				entry.clickConn = nil
			end
		end
		table.clear(self._glRows)
	end
	if self._glRewardChips then
		table.clear(self._glRewardChips)
	end
	self._glShadows = nil
	self._glList = nil
	self._glTabs = nil
	self._glTabHost = nil
	self._glTabSig = nil
	self._glDetailScroll = nil
end

return QuestJournalScreen
