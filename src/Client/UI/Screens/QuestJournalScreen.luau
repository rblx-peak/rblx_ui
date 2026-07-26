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
	if self:LayoutKit() == "AC" then
		self:_ACRender()
		return
	end
	self:_RenderTabs()
	self:_RenderList()
	self:_RenderDetail()
end

function QuestJournalScreen:_RenderTabs()
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

return QuestJournalScreen
