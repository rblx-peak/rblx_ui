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
local IconVisibility = require(script.Parent.Parent.Icons.IconVisibility)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UIProgressBarComponent = require(script.Parent.Parent.Components.UIProgressBarComponent)
local ACLayoutKit = require(script.Parent.Parent.Framework.ACLayoutKit)
local GLLayoutKit = require(script.Parent.Parent.Framework.GLLayoutKit)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local UITicker = require(script.Parent.Parent.Framework.UITicker)

type Reward = { currency: string?, icon: string?, amount: number, label: string? }
type Objective = { text: string, done: boolean? }
-- The lobby's DAILY QUESTS panel, which is a separate surface in the live game
-- (QuestService pushes { quests = {...}, refreshAt = <unix> } and the panel
-- prints a 1Hz "REFRESH IN: HH:MM:SS"). The GP journal carries it as a rail —
-- see the GP section at the foot of this file.
type DailyQuest = {
	id: string,
	desc: string,
	progress: number,
	target: number,
	rewardText: string,
	claimed: boolean?,
}
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

-- The live daily set, verbatim from QuestService's QUESTS table (win / play /
-- cash, with the rewards it actually pays). Seeded across all three states the
-- shipped panel can show: locked, ready, already claimed.
local DEMO_DAILY: { DailyQuest } = {
	{ id = "win", desc = "Win 2 duels", progress = 1, target = 2, rewardText = "+200 Cash", claimed = false },
	{ id = "play", desc = "Play for 10 minutes", progress = 10, target = 10, rewardText = "+1 Win", claimed = false },
	{ id = "cash", desc = "Earn 300 Cash", progress = 300, target = 300, rewardText = "+150 Cash", claimed = true },
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
	-- The daily set + its reset clock. QuestService generates three quests per
	-- player and refreshes them at UTC midnight; standalone, this is the
	-- fallback in exactly that shape.
	self._daily = DEMO_DAILY
	self._dailyRefreshIn = 5 * 3600 + 12 * 60 + 44
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
	-- GP layout language: the pastel journal with the lobby's DAILY QUESTS rail
	-- alongside it (see _BuildGPLayout at the foot of this file).
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
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
	if self:LayoutKit() == "GP" then
		self:_GPRefresh()
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
	if self:LayoutKit() == "GP" then
		self:_GPSyncTabs()
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
	if self:LayoutKit() == "GP" then
		self:_GPRefresh()
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
	if self:LayoutKit() == "GP" then
		self:_GPRefreshDetail()
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
	-- The daily set arrives on the same payload (QuestService's state push);
	-- only the GP branch renders it, but ingesting is layout-agnostic.
	if self:_IngestDaily(data) then
		self:_GPRefreshDaily()
	end
	self:_GPStartTicker()
	if self._modal then
		UIChrome.PopIn(self:GetTheme(), self._modal.content)
	end
end

function QuestJournalScreen:_OnHide()
	self:_GPStopTicker()
end

function QuestJournalScreen:Update(data: any)
	if data and data.quests then
		self._quests = data.quests
		self._selectedId = nil
		if self._built then
			self:_Render()
		end
	end
	if self:_IngestDaily(data) and self._built then
		self:_GPRefreshDaily()
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

-- ========================================================================
-- GP layout (theme.LayoutKit == "GP") — GIRLY POP: the pastel journal, and
-- the lobby's DAILY QUESTS panel carried in as a third column.
--
-- WHAT THIS BRANCH ADDS THAT THE COLLECTION SCREEN NEVER HAD. In the live
-- game the daily set is its own 560×560 panel behind the QUESTS button, and
-- the journal in this collection had none of it:
--   * the three-quest daily list with per-quest progress (the shipped
--     "%d / %d" over a fill bar), each row's reward line, and the exact
--     CLAIM / CLAIMED / LOCKED tri-state its claim button carries;
--   * CLAIM ALL across the ready set (the shipped panel claims one at a
--     time; taking the lot is the honest extension of it);
--   * the refresh countdown, in QuestService's own "%02d:%02d:%02d" — the
--     set regenerates at UTC midnight and the panel rolls over with it.
-- The journal side keeps every classic feature (tabs with live counts, the
-- objective checklist, reward chips, TRACK, ABANDON) and gains a per-row
-- progress bar, objective tally and reward chip in the LIST, which the
-- arcade rows only ever showed one at a time.
--
-- THE UPGRADES:
--   * ONE 1Hz TICKER — a single UITicker handler drives the countdown pill
--     AND the "resets at midnight" line, and performs the rollover. No
--     per-label loop, no screen-owned RunService connection.
--   * The selected row wears a soft rose GLOW (one handle, reparented onto
--     whichever row is selected) instead of a recoloured plate alone.
--
-- Copy is sentence case throughout: pack law 5 forbids all-caps, so the
-- shipped "CLAIM ALL" / "LOCKED" shouts are carried as features, not caps.
-- ========================================================================

local GP_PAGE = Vector2.new(1380, 800)
local GP_LIST_W = 440
local GP_DETAIL_X = GP_LIST_W + 16
local GP_DETAIL_W = 500
local GP_RAIL_X = GP_DETAIL_X + GP_DETAIL_W + 16
local GP_RAIL_W = 380
local GP_TAB_H = 52
local GP_BODY_Y = GP_TAB_H + 10
local GP_BODY_H = 602
local GP_COL_H = 664
local GP_ROW_H = 96
local GP_CARD_H = 176
local GP_ACTION_H = 56
local GP_DAILY_ROW_H = 96
local GP_DAY_SECONDS = 86400

-- The shipped panel prints "REFRESH IN: HH:MM:SS" and never elides the hour
-- field, so the format is carried literally rather than through
-- UIChrome.FormatCountdown (which drops to M:SS under an hour).
local GP_REFRESH_FORMAT = "%02d:%02d:%02d"
local GP_REFRESH_CAPTION = "Quests refresh in"
local GP_REFRESH_HINT = "A fresh set of three lands at midnight, wherever you are."
local GP_DAILY_TITLE = "Daily quests"
local GP_DAILY_EMPTY = "No daily quests today — check back after the reset."
local GP_REWARD_PREFIX = "Reward  %s"

local function gpRefreshText(seconds: number): string
	local left = math.max(0, math.floor(seconds))
	return string.format(GP_REFRESH_FORMAT, left // 3600, (left % 3600) // 60, left % 60)
end

type GPButton = {
	root: TextButton,
	shape: Frame,
	label: TextLabel,
	shadow: any,
	SetTone: (Color3) -> (),
}

-- Always-painted frame: UIStyler.Frame is born pure white, which this pack
-- forbids outright (the kit keeps the same private helper for the same reason).
local function gpSurface(name: string, fill: Color3, transparency: number?): Frame
	local frame = UIStyler.Frame(name)
	frame.BackgroundColor3 = fill
	frame.BackgroundTransparency = transparency or 0
	return frame
end

-- Archive art WITHOUT IconArchive.Image's glyph fallback: that fallback emits
-- pure-white text with a pure-black stroke — two law-1 violations on a pastel
-- page. A missing id leaves an empty slot instead.
local function gpIcon(parent: Instance, key: string, sizePx: number): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Name = "Icon_" .. key
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Fit
	image.Size = UDim2.fromOffset(sizePx, sizePx)
	local id = IconArchive.Id(key)
	image.Image = id or ""
	image.Parent = parent
	IconVisibility.Register(image)
	return image
end

-- GPLayoutKit ships composition primitives, not a button, so the screen
-- composes one: transparent hit target + painted petal chip, with SetTone
-- retinting fill, stroke and shadow together — a state change can never leave
-- a rose shadow under a grey button.
local function gpButton(theme: Types.UITheme, parent: Instance, opts: {
	text: string,
	fill: Color3,
	sizePx: Vector2,
	index: number?,
	textSize: number?,
	onClick: () -> (),
}, sink: { any }?): GPButton
	local root = Instance.new("TextButton")
	root.Name = "GPButton"
	-- Transparent: UIStyleEnforcer backstops a SOLID GuiButton with a black 2px
	-- stroke, which would violate law 1 on sight (see GPLayoutKit.Page).
	root.BackgroundTransparency = 1
	root.Text = ""
	root.AutoButtonColor = false
	root.Size = UDim2.fromOffset(opts.sizePx.X, opts.sizePx.Y)
	root.ZIndex = 4
	root.Parent = parent

	local shape = gpSurface("Shape", opts.fill, 0)
	shape.Size = UDim2.fromScale(1, 1)
	shape.ZIndex = 4
	shape.Parent = root
	GPLayoutKit.Petal(theme, shape, opts.index or 0)
	local stroke = GPLayoutKit.SoftStroke(theme, shape)
	local shadow = GPLayoutKit.Shadow(theme, shape, "sm", sink)

	-- Ink on every fill this screen uses: TextOnPrimary measures 2.14:1 on rose
	-- and is display-only, never a button caption.
	local label = GPLayoutKit.Text(theme, opts.textSize or theme.TextSizes.Button, theme.Colors.TextPrimary, "Label")
	label.Text = opts.text
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 5
	label.Parent = shape

	root.Activated:Connect(opts.onClick)
	UIChrome.Animate(theme, root, shape)

	local function setTone(fill: Color3)
		shape.BackgroundColor3 = fill
		local deep = GPLayoutKit.Deepen(theme, fill, 1)
		stroke.Color = deep
		shadow.Instance.Color = deep
	end

	return { root = root, shape = shape, label = label, shadow = shadow, SetTone = setTone }
end

-- Butter value pill with ink numerals — the pack's only legal value treatment
-- (a gold NUMERAL on cream would measure ~1.5:1).
local function gpChip(theme: Types.UITheme, parent: Instance, sizePx: Vector2): { root: Frame, label: TextLabel }
	local fill = theme.Arcade.Gold
	local chip = gpSurface("Chip", fill, 0)
	chip.Size = UDim2.fromOffset(sizePx.X, sizePx.Y)
	chip.ZIndex = 4
	chip.Parent = parent
	UIStyler.Corner(theme.Radii.Pill).Parent = chip
	GPLayoutKit.SoftStroke(theme, chip)

	local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "Text")
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 5
	label.Parent = chip
	return { root = chip, label = label }
end

local function gpStateFill(theme: Types.UITheme, state: string): Color3
	if state == "completed" then
		return theme.Colors.Secondary
	elseif state == "failed" then
		return theme.Colors.Error
	end
	return theme.Colors.Primary
end

local function gpObjectiveCount(quest: Quest): (number, number)
	local done = 0
	for _, objective in quest.objectives do
		if objective.done then
			done += 1
		end
	end
	return done, #quest.objectives
end

local function gpCurrentObjective(quest: Quest): string
	for _, objective in quest.objectives do
		if not objective.done then
			return objective.text
		end
	end
	local last = quest.objectives[#quest.objectives]
	return last and last.text or ""
end

-- The shared demo ladder (and any server payload) SHOUTS its titles, because
-- every other layout in this framework shouts. Law 5 forbids that here, so a
-- string that is entirely upper case is softened FOR DISPLAY ONLY — the data
-- is never rewritten, and mixed-case copy passes through untouched.
local function gpSoften(text: string): string
	if text == "" or text ~= string.upper(text) then
		return text
	end
	return string.sub(text, 1, 1) .. string.lower(string.sub(text, 2))
end

-- The unit a reward is counted in: its currency, else its own label ("crate"),
-- else nothing at all.
local function gpRewardUnit(reward: Reward): string?
	local unit = reward.currency or reward.label
	return if unit then gpSoften(unit) else nil
end

-- "750 Cash" / "1 Crate", plus a "+1" tail when a quest pays several things —
-- the list row summarises, the detail column lists them all.
local function gpRewardSummary(quest: Quest): string
	local first = quest.rewards[1]
	if not first then
		return "No reward"
	end
	local unit = gpRewardUnit(first)
	local head = if unit then string.format("%s %s", formatAmount(first.amount), unit) else formatAmount(first.amount)
	if #quest.rewards > 1 then
		return string.format("%s +%d", head, #quest.rewards - 1)
	end
	return head
end

function QuestJournalScreen:_IngestDaily(data: any?): boolean
	if type(data) ~= "table" then
		return false
	end
	local touched = false
	if type(data.daily) == "table" then
		self._daily = data.daily
		touched = true
	end
	if type(data.dailyRefreshIn) == "number" then
		self._dailyRefreshIn = data.dailyRefreshIn
		touched = true
	end
	-- The service publishes an absolute unix `refreshAt`; the panel only ever
	-- shows the remainder, so it is converted once here.
	if type(data.refreshAt) == "number" then
		self._dailyRefreshIn = math.max(0, data.refreshAt - os.time())
		touched = true
	end
	return touched
end

function QuestJournalScreen:_BuildGPLayout()
	local theme = self:GetTheme()

	self._gpRows = {} :: { any }
	self._gpRowQuest = {} :: { any }
	self._gpRewardPills = {} :: { any }
	self._gpDailyRows = {} :: { any }
	self._gpTabSig = nil :: string?

	local page = GPLayoutKit.Page(theme, self.Root, {
		titleText = "Quest journal",
		subtitleText = "Everything you are working on, and today's three.",
		sizePx = GP_PAGE,
		onClose = function()
			self.ScreenController:HideScreen("quests")
		end,
	})
	-- The Page's own sink becomes the screen's shadow list; every later kit call
	-- feeds the same list.
	self._gpShadows = page.shadows
	-- _OnShow pops self._modal.content in every layout; under GP that is the
	-- page's content region.
	self._modal = { content = page.content } :: any
	local content = page.content

	-- Tracked counter in the ribbon's right slot.
	local counter = GPLayoutKit.PricePill(theme, page.topRight, self._gpShadows)
	counter.root.Size = UDim2.fromOffset(190, 40)
	counter.root.LayoutOrder = 1
	local starId = IconArchive.Id("star")
	counter.icon.Image = starId or ""
	counter.amount.TextXAlignment = Enum.TextXAlignment.Center
	self._gpCounter = counter

	local tabHost = gpSurface("TabHost", theme.Colors.Background, 1)
	tabHost.Size = UDim2.fromOffset(GP_LIST_W, GP_TAB_H)
	tabHost.ZIndex = 4
	tabHost.Parent = content
	self._gpTabHost = tabHost

	self:_GPBuildList(theme, content)
	self:_GPBuildDetail(theme, content)
	self:_GPBuildRail(theme, content)

	-- ONE aura for the whole list, parked on a zero-size host and REPARENTED
	-- onto the selected row (a handle per pooled row would spend the shadow
	-- budget on a thing only one row can ever wear).
	local glowHome = gpSurface("GlowHome", theme.Colors.Primary, 1)
	glowHome.Size = UDim2.fromOffset(0, 0)
	glowHome.ZIndex = 3
	glowHome.Parent = content
	self._gpGlowHome = glowHome
	self._gpGlow = GPLayoutKit.Glow(theme, glowHome, theme.Colors.Primary, self._gpShadows)
	self._gpGlow:SetEnabled(false)

	self:_GPRefresh()
end

function QuestJournalScreen:_GPBuildList(theme: Types.UITheme, content: Frame)
	local list = Instance.new("ScrollingFrame")
	list.Name = "GPQuests"
	list.BackgroundColor3 = theme.Colors.Background
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(0, GP_BODY_Y)
	list.Size = UDim2.fromOffset(GP_LIST_W, GP_BODY_H)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = 8
	list.ScrollBarImageColor3 = theme.Colors.Primary
	-- MUST clip (the pack law); the padding keeps the selected row's glow off
	-- the cut edge instead of slicing it.
	list.ClipsDescendants = true
	list.ZIndex = 3
	list.Parent = content
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 12),
	}).Parent = list

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 18)
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = list
	self._gpList = list

	local empty = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Empty")
	empty.Text = "Nothing here yet — go throw some clay."
	empty.TextWrapped = true
	empty.Size = UDim2.new(1, -16, 0, 80)
	empty.Visible = false
	empty.Parent = list
	self._gpEmpty = empty
end

-- One pooled journal row: art, title, the current objective with its tally, a
-- progress bar, the reward summary and the TRACK toggle — every classic row
-- feature at once, where the arcade row showed them in turns.
function QuestJournalScreen:_GPBuildRow(theme: Types.UITheme, index: number): any
	local root = Instance.new("TextButton")
	root.Name = "GPRow" .. index
	root.BackgroundTransparency = 1
	root.Text = ""
	root.AutoButtonColor = false
	root.Size = UDim2.new(1, -8, 0, GP_ROW_H)
	root.LayoutOrder = index
	root.ZIndex = 3
	root.Parent = self._gpList

	local bodyFill = theme.Colors.Surface
	local body = gpSurface("Body", bodyFill, 0)
	body.Size = UDim2.fromScale(1, 1)
	body.ZIndex = 3
	body.Parent = root
	GPLayoutKit.Petal(theme, body, index)
	local stroke = GPLayoutKit.SoftStroke(theme, body)
	local shadow = GPLayoutKit.Shadow(theme, body, "sm", self._gpShadows, bodyFill)

	local art = gpIcon(body, "quest", 34)
	art.Position = UDim2.fromOffset(12, 10)
	art.ZIndex = 4

	local name = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "Name")
	name.RichText = false
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(54, 8)
	name.Size = UDim2.fromOffset(212, 26)
	name.ZIndex = 4
	name.Parent = body

	local sub = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Objective")
	sub.RichText = false
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.TextTruncate = Enum.TextTruncate.AtEnd
	sub.Position = UDim2.fromOffset(54, 34)
	sub.Size = UDim2.new(1, -68, 0, 20)
	sub.ZIndex = 4
	sub.Parent = body

	local track = gpSurface("Track", theme.Arcade.RulerTrack, 0)
	track.Position = UDim2.fromOffset(12, 68)
	track.Size = UDim2.fromOffset(232, 8)
	track.ZIndex = 4
	track.Parent = body
	UIStyler.Corner(theme.Radii.Pill).Parent = track

	local fill = gpSurface("Fill", theme.Colors.Primary, 0)
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = 5
	fill.Parent = track
	UIStyler.Corner(theme.Radii.Pill).Parent = fill

	local reward = gpChip(theme, body, Vector2.new(84, 22))
	reward.root.Position = UDim2.fromOffset(252, 60)

	local count = GPLayoutKit.NumberText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "Count")
	count.AnchorPoint = Vector2.new(1, 0)
	count.Position = UDim2.new(1, -12, 0, 60)
	count.Size = UDim2.fromOffset(56, 22)
	count.ZIndex = 4
	count.Parent = body

	local toggle = gpButton(theme, body, {
		text = "Track",
		fill = theme.Colors.Surface,
		sizePx = Vector2.new(92, 26),
		index = index + 1,
		textSize = theme.TextSizes.Small,
		onClick = function()
			-- Read through the map, not into it: _OnTeardown drops it while the
			-- shell is still standing, and gpButton's Activated is owned by the
			-- instance rather than a stored connection.
			local map = self._gpRowQuest
			local quest = map and map[index]
			if quest then
				self:_ToggleTrack(quest)
			end
		end,
	}, self._gpShadows)
	toggle.root.AnchorPoint = Vector2.new(1, 0)
	toggle.root.Position = UDim2.new(1, -12, 0, 10)

	UIChrome.Animate(theme, root, body)
	local entry: any = {
		root = root,
		body = body,
		stroke = stroke,
		shadow = shadow,
		art = art,
		name = name,
		sub = sub,
		track = track,
		fill = fill,
		reward = reward,
		count = count,
		toggle = toggle,
	}
	entry.click = root.Activated:Connect(function()
		local map = self._gpRowQuest
		local quest = map and map[index]
		if quest then
			self._selectedId = quest.id
			self:_GPRefresh()
		end
	end)
	return entry
end

function QuestJournalScreen:_GPBuildDetail(theme: Types.UITheme, content: Frame)
	local detail = gpSurface("GPDetail", theme.Colors.Background, 1)
	detail.Position = UDim2.fromOffset(GP_DETAIL_X, 0)
	detail.Size = UDim2.fromOffset(GP_DETAIL_W, GP_COL_H)
	detail.ZIndex = 3
	detail.Parent = content

	local card = GPLayoutKit.Card(theme, detail, 0, self._gpShadows)
	card.root.Size = UDim2.new(1, 0, 0, GP_CARD_H)
	card.name.RichText = false
	-- Leave the name line's right end to the state chip below, so a long quest
	-- title truncates instead of running under it.
	card.name.Size = UDim2.new(1, -168, 0, 26)
	self._gpCard = card

	-- The state chip sits in the card's own name row rather than overhanging
	-- it: nothing in this pack breaks its own silhouette.
	local chip = gpChip(theme, card.body, Vector2.new(120, 26))
	chip.root.AnchorPoint = Vector2.new(1, 1)
	chip.root.Position = UDim2.new(1, -14, 1, -8)
	chip.root.ZIndex = 5
	chip.label.ZIndex = 6
	self._gpStateChip = chip

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "GPDetailBody"
	scroll.BackgroundColor3 = theme.Colors.Background
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, GP_CARD_H + 12)
	scroll.Size = UDim2.new(1, 0, 0, GP_COL_H - GP_CARD_H - 12 - GP_ACTION_H - 12)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 8
	scroll.ScrollBarImageColor3 = theme.Colors.Primary
	scroll.ClipsDescendants = true
	scroll.ZIndex = 3
	scroll.Parent = detail
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 8),
	}).Parent = scroll

	local scrollPad = Instance.new("UIPadding")
	scrollPad.PaddingRight = UDim.new(0, 14)
	scrollPad.PaddingBottom = UDim.new(0, 12)
	scrollPad.Parent = scroll
	self._gpDetailScroll = scroll

	local stateLine = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "State")
	stateLine.TextXAlignment = Enum.TextXAlignment.Left
	stateLine.Size = UDim2.new(1, 0, 0, 26)
	stateLine.LayoutOrder = 1
	stateLine.Parent = scroll
	self._gpStateLine = stateLine

	local description = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Description")
	description.RichText = false
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.TextYAlignment = Enum.TextYAlignment.Top
	description.TextWrapped = true
	description.AutomaticSize = Enum.AutomaticSize.Y
	description.Size = UDim2.new(1, 0, 0, 0)
	description.LayoutOrder = 2
	description.Parent = scroll
	self._gpDescription = description

	GPLayoutKit.SectionLabel(theme, scroll, "Objectives").LayoutOrder = 3
	GPLayoutKit.Divider(theme, scroll).LayoutOrder = 4

	local objectives = gpSurface("Objectives", theme.Colors.Background, 1)
	objectives.AutomaticSize = Enum.AutomaticSize.Y
	objectives.Size = UDim2.new(1, 0, 0, 0)
	objectives.LayoutOrder = 5
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 6),
	}).Parent = objectives
	objectives.Parent = scroll
	self._gpObjectives = objectives

	GPLayoutKit.SectionLabel(theme, scroll, "Rewards").LayoutOrder = 6
	GPLayoutKit.Divider(theme, scroll).LayoutOrder = 7

	local rewards = gpSurface("Rewards", theme.Colors.Background, 1)
	rewards.Size = UDim2.new(1, 0, 0, 46)
	rewards.LayoutOrder = 8
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
	}).Parent = rewards
	rewards.Parent = scroll
	self._gpRewardsHost = rewards

	-- The action slot is pinned at the column's foot so the scrolling body can
	-- never push Track / Abandon off the page (classic grammar).
	local actions = gpSurface("Actions", theme.Colors.Background, 1)
	actions.AnchorPoint = Vector2.new(0, 1)
	actions.Position = UDim2.fromScale(0, 1)
	actions.Size = UDim2.new(1, 0, 0, GP_ACTION_H)
	actions.ZIndex = 4
	actions.Parent = detail

	-- Both actions run the EXACT classic callbacks, so the buttons are built
	-- once and only their skin changes per selection.
	self._gpTrack = gpButton(theme, actions, {
		text = "Track",
		fill = theme.Colors.Primary,
		sizePx = Vector2.new(180, GP_ACTION_H - 8),
		index = 0,
		onClick = function()
			local quest = self:_Selected()
			if quest then
				self:_ToggleTrack(quest)
			end
		end,
	}, self._gpShadows)

	self._gpAbandon = gpButton(theme, actions, {
		text = "Abandon",
		fill = theme.Colors.Error,
		sizePx = Vector2.new(180, GP_ACTION_H - 8),
		index = 1,
		onClick = function()
			local quest = self:_Selected()
			-- Mirrors the classic inert state button: a finished quest's slot is
			-- dimmed IN PLACE and does nothing.
			if quest and quest.state == "active" then
				self:_PromptAbandon(quest)
			end
		end,
	}, self._gpShadows)
	self._gpAbandon.root.Position = UDim2.fromOffset(196, 0)
end

-- ---- the daily rail -------------------------------------------------

function QuestJournalScreen:_GPBuildRail(theme: Types.UITheme, content: Frame)
	local rail = gpSurface("GPDaily", theme.Colors.Background, 1)
	rail.Position = UDim2.fromOffset(GP_RAIL_X, 0)
	rail.Size = UDim2.fromOffset(GP_RAIL_W, GP_COL_H)
	rail.ZIndex = 3
	rail.Parent = content

	local title = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle + 2, theme.Colors.TextPrimary, "DailyTitle")
	title.Text = GP_DAILY_TITLE
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Size = UDim2.new(1, 0, 0, 28)
	title.ZIndex = 4
	title.Parent = rail

	local summary = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "DailySummary")
	summary.TextXAlignment = Enum.TextXAlignment.Left
	summary.Position = UDim2.fromOffset(0, 28)
	summary.Size = UDim2.new(1, 0, 0, 22)
	summary.ZIndex = 4
	summary.Parent = rail
	self._gpDailySummary = summary

	GPLayoutKit.Divider(theme, rail).Position = UDim2.fromOffset(0, 54)

	local empty = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "DailyEmpty")
	empty.Text = GP_DAILY_EMPTY
	empty.TextXAlignment = Enum.TextXAlignment.Left
	empty.TextWrapped = true
	empty.Position = UDim2.fromOffset(0, 72)
	empty.Size = UDim2.new(1, 0, 0, 48)
	empty.Visible = false
	empty.ZIndex = 4
	empty.Parent = rail
	self._gpDailyEmpty = empty
	self._gpRail = rail

	self._gpClaimAll = gpButton(theme, rail, {
		text = "Claim all",
		fill = theme.Arcade.Gold,
		sizePx = Vector2.new(GP_RAIL_W, 52),
		index = 0,
		onClick = function()
			self:_ClaimAllDaily()
		end,
	}, self._gpShadows)
	self._gpClaimAll.root.Position = UDim2.fromOffset(0, 396)

	GPLayoutKit.Divider(theme, rail).Position = UDim2.fromOffset(0, 466)

	local caption = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "RefreshCaption")
	caption.Text = GP_REFRESH_CAPTION
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.Position = UDim2.fromOffset(0, 482)
	caption.Size = UDim2.new(1, 0, 0, 22)
	caption.ZIndex = 4
	caption.Parent = rail

	local pill = GPLayoutKit.PricePill(theme, rail, self._gpShadows)
	pill.root.Position = UDim2.fromOffset(0, 508)
	pill.root.Size = UDim2.fromOffset(200, 44)
	local clockId = IconArchive.Id("clock")
	pill.icon.Image = clockId or ""
	pill.amount.TextXAlignment = Enum.TextXAlignment.Center
	pill.amount.Text = gpRefreshText(self._dailyRefreshIn)
	self._gpRefreshLabel = pill.amount

	local hint = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "RefreshHint")
	hint.Text = GP_REFRESH_HINT
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextWrapped = true
	hint.Position = UDim2.fromOffset(0, 560)
	hint.Size = UDim2.new(1, 0, 0, 40)
	hint.ZIndex = 4
	hint.Parent = rail
end

-- One pooled daily row. The progress line IS GPLayoutKit.StatRow — the kit's
-- anti-condescension row, at the Armored Core assembly row's density — so a
-- daily quest reads label / value capsule / target / magnitude bar rather than
-- the shipped panel's bare bar.
function QuestJournalScreen:_GPDailyRow(index: number, quest: DailyQuest): any
	local existing = self._gpDailyRows[index]
	if existing and existing.target == quest.target then
		return existing
	end
	if existing then
		-- The target moved (a different quest landed in this slot), and StatRow
		-- captures maxValue at build. Rebuild the row, handing back every shadow
		-- it owned first — a destroyed GuiObject alone leaves the budget high.
		GPLayoutKit.ReleaseShadows(existing.shadows)
		existing.root:Destroy()
	end
	local theme = self:GetTheme()

	-- The row keeps its OWN bucket so a rebuild can release exactly its
	-- handles; every handle also lands in the screen-wide list for teardown
	-- (releasing twice is a no-op, leaking one is not).
	local bucket: { any } = {}
	local fillColor = theme.Colors.SurfaceRaised
	local root = gpSurface("GPDailyRow" .. index, fillColor, 0)
	root.Position = UDim2.fromOffset(0, 68 + (index - 1) * (GP_DAILY_ROW_H + 12))
	root.Size = UDim2.fromOffset(GP_RAIL_W, GP_DAILY_ROW_H)
	root.ZIndex = 3
	root.Parent = self._gpRail
	GPLayoutKit.Petal(theme, root, index)
	GPLayoutKit.SoftStroke(theme, root)
	local shadow = GPLayoutKit.Shadow(theme, root, "sm", bucket, fillColor)

	local host = gpSurface("StatHost", theme.Colors.Background, 1)
	host.Position = UDim2.fromOffset(12, 8)
	host.Size = UDim2.new(1, -24, 0, 32)
	host.ZIndex = 4
	host.Parent = root

	local stat = GPLayoutKit.StatRow(theme, host, {
		label = quest.desc,
		value = quest.progress,
		maxValue = quest.target,
		unit = "/ " .. tostring(quest.target),
		precision = 0, -- quest counters are whole things: duels, minutes, Cash
		accent = theme.Colors.Primary,
	})
	-- StatRow reserves a DELTA column for SetPreview, which a daily quest never
	-- calls — 60px of dead air next to a description the shipped panel gave 347.
	-- Hand it back to the label so "Play for 10 minutes" reads in full. Measured
	-- off the capsule rather than the kit's private constants.
	stat.delta.Visible = false
	stat.label.Size = UDim2.new(1, stat.capsule.Position.X.Offset - 10, 0, stat.label.Size.Y.Offset)

	local reward = gpChip(theme, root, Vector2.new(150, 26))
	reward.root.Position = UDim2.fromOffset(12, 50)

	local claim = gpButton(theme, root, {
		text = "Claim",
		fill = theme.Colors.Secondary,
		sizePx = Vector2.new(108, 38),
		index = index,
		textSize = theme.TextSizes.Small + 1,
		onClick = function()
			self:_ClaimDaily(index)
		end,
	}, bucket)
	claim.root.AnchorPoint = Vector2.new(1, 0)
	claim.root.Position = UDim2.new(1, -12, 0, 46)

	for _, handle in bucket do
		table.insert(self._gpShadows, handle)
	end

	local entry: any = {
		root = root,
		stat = stat,
		reward = reward,
		claim = claim,
		shadow = shadow,
		shadows = bucket,
		target = quest.target,
	}
	self._gpDailyRows[index] = entry
	return entry
end

-- The shipped panel fires QuestClaim and lets the server decide; the same three
-- refusals are stated here so the button is never a dead end.
function QuestJournalScreen:_ClaimDaily(index: number)
	local quest = self._daily[index]
	if not quest then
		return
	end
	if quest.claimed then
		self:_Toast("Already claimed — try the next one!", "Info")
		return
	end
	if quest.progress < quest.target then
		self:_Toast(string.format("Not yet — %d of %d.", quest.progress, quest.target), "Info")
		return
	end
	quest.claimed = true
	self:_Toast(string.format("Claimed %s", quest.rewardText), "Success")
	self:_GPRefreshDaily()
end

function QuestJournalScreen:_ClaimAllDaily()
	local taken = {}
	for _, quest in self._daily do
		if not quest.claimed and quest.progress >= quest.target then
			quest.claimed = true
			table.insert(taken, quest.rewardText)
		end
	end
	if #taken == 0 then
		self:_Toast("Nothing ready to claim yet — keep playing!", "Info")
		return
	end
	-- Joined with a middot, not " + ": every rewardText already CARRIES its sign
	-- ("+200 Cash"), so a plus between them reads "+200 Cash + +1 Win".
	self:_Toast("Claimed " .. table.concat(taken, " · "), "Success")
	self:_GPRefreshDaily()
end

function QuestJournalScreen:_GPRefreshDaily()
	if not self._gpRail then
		return -- built under another layout; the next Show rebuilds
	end
	local theme = self:GetTheme()
	local daily = self._daily
	local ready, claimed = 0, 0

	for index, quest in daily do
		local entry = self:_GPDailyRow(index, quest)
		entry.root.Visible = true
		entry.shadow:SetEnabled(true)
		entry.stat.label.Text = quest.desc
		entry.stat.SetValue(math.clamp(quest.progress, 0, quest.target))
		entry.reward.label.Text = string.format(GP_REWARD_PREFIX, quest.rewardText)

		local isReady = quest.progress >= quest.target
		local isClaimed = quest.claimed == true
		if isClaimed then
			claimed += 1
		elseif isReady then
			ready += 1
		end

		-- The shipped tri-state, verbatim in behaviour: CLAIMED (spent) /
		-- CLAIM (ready) / LOCKED (still working).
		entry.claim.label.Text = if isClaimed then "Claimed" elseif isReady then "Claim" else "Locked"
		entry.claim.SetTone(
			if isClaimed then theme.Colors.Disabled elseif isReady then theme.Colors.Secondary else theme.Colors.Surface
		)
		entry.stat.fill.BackgroundColor3 = if isClaimed
			then theme.Colors.Disabled
			elseif isReady then theme.Colors.Secondary
			else theme.Colors.Primary
	end

	-- Surplus rows go back to the pool: hidden, shadows DISABLED, never
	-- destroyed (the pooling law).
	for index = #daily + 1, #self._gpDailyRows do
		local entry = self._gpDailyRows[index]
		entry.root.Visible = false
		entry.shadow:SetEnabled(false)
	end

	self._gpDailyEmpty.Visible = #daily == 0
	self._gpDailySummary.Text = string.format("%d ready · %d claimed · %d today", ready, claimed, #daily)
	self._gpClaimAll.label.Text = if ready > 0 then string.format("Claim all (%d)", ready) else "Claim all"
	self._gpClaimAll.SetTone(if ready > 0 then theme.Arcade.Gold else theme.Colors.Disabled)
	self:_GPPaintClock()
end

-- ---- the journal side -----------------------------------------------

-- The tab bar carries live counts, so it is rebuilt only when a count moves.
function QuestJournalScreen:_GPSyncTabs()
	if not self._gpTabHost then
		return
	end
	local theme = self:GetTheme()
	local signature = string.format(
		"%d|%d|%d",
		self:_CountFor("active"),
		self:_CountFor("completed"),
		self:_CountFor("failed")
	)
	if signature ~= self._gpTabSig then
		self._gpTabSig = signature
		if self._gpTabs then
			GPLayoutKit.ReleaseShadows(self._gpTabShadows)
			self._gpTabs.frame:Destroy()
		end
		self._gpTabShadows = {} :: { any }
		local tabs = GPLayoutKit.Tabs(theme, self._gpTabHost, {
			widthPx = 138,
			heightPx = GP_TAB_H,
			tabHeightPx = GP_TAB_H - 8,
		}, self._gpTabShadows)
		for _, tab in TABS do
			-- TABS is shared with the shouting layouts; law 5 softens it here.
			local caption = gpSoften(tab.label)
			tabs.Add(string.format("%s  %d", caption, self:_CountFor(tab.id)), tab.id, function()
				self:_SelectTab(tab.id)
			end)
		end
		self._gpTabs = tabs
	end
	self._gpTabs.Select(self._tab)
end

function QuestJournalScreen:_GPRefresh()
	if not self._gpList then
		return -- built under another layout; the next Show rebuilds
	end
	local theme = self:GetTheme()
	self:_GPSyncTabs()

	local quests = self:_Filtered()
	-- First quest of the tab is pre-selected so the detail column is never
	-- empty (the classic rule).
	if not self._selectedId and #quests > 0 then
		self._selectedId = quests[1].id
	end
	self._gpEmpty.Visible = #quests == 0

	local tracked = 0
	for _, quest in self._quests do
		if quest.tracked then
			tracked += 1
		end
	end
	self._gpCounter.amount.Text = string.format("%d tracked", tracked)

	-- Index-keyed pooling: a row's petal parity comes from its POSITION, so
	-- reusing row i for whatever quest lands there keeps the grid agreeing.
	self._gpRowQuest = {}
	local selectedIndex: number? = nil
	for index, quest in quests do
		local entry = self._gpRows[index]
		if not entry then
			entry = self:_GPBuildRow(theme, index)
			self._gpRows[index] = entry
		end
		self._gpRowQuest[index] = quest
		entry.root.Visible = true
		entry.shadow:SetEnabled(true)

		local selected = quest.id == self._selectedId
		if selected then
			selectedIndex = index
		end
		local done, total = gpObjectiveCount(quest)
		local artId = IconArchive.Id(quest.icon or "quest")
		entry.art.Image = artId or ""
		entry.name.Text = gpSoften(quest.title)
		entry.sub.Text = string.format("%d of %d · %s", done, total, gpCurrentObjective(quest))
		entry.count.Text = string.format("%d / %d", quest.progress, quest.goal)
		entry.reward.label.Text = gpRewardSummary(quest)
		entry.fill.Size = UDim2.fromScale(
			if quest.goal > 0 then math.clamp(quest.progress / quest.goal, 0, 1) else 0,
			1
		)
		entry.fill.BackgroundColor3 = gpStateFill(theme, quest.state)

		local rowFill = if selected then theme.Colors.SurfaceRaised else theme.Colors.Surface
		entry.body.BackgroundColor3 = rowFill
		entry.stroke.Color = GPLayoutKit.Deepen(theme, if selected then theme.Colors.Primary else rowFill, 1)
		entry.shadow.Instance.Color = GPLayoutKit.Deepen(theme, rowFill, 1)

		entry.toggle.label.Text = if quest.tracked then "Tracked" else "Track"
		entry.toggle.SetTone(if quest.tracked then theme.Arcade.Gold else theme.Colors.Background)
	end

	for index = #quests + 1, #self._gpRows do
		local entry = self._gpRows[index]
		entry.root.Visible = false
		entry.shadow:SetEnabled(false)
	end

	-- Move the one aura onto the selected row (or park it).
	if selectedIndex then
		self._gpGlow.Instance.Parent = self._gpRows[selectedIndex].body
		self._gpGlow:SetEnabled(true)
	else
		self._gpGlow:SetEnabled(false)
		self._gpGlow.Instance.Parent = self._gpGlowHome
	end

	self:_GPRefreshDetail()
	self:_GPRefreshDaily()
end

function QuestJournalScreen:_GPRewardPill(theme: Types.UITheme, index: number): any
	local pill = self._gpRewardPills[index]
	if not pill then
		pill = GPLayoutKit.PricePill(theme, self._gpRewardsHost, self._gpShadows)
		pill.root.Size = UDim2.fromOffset(160, 38)
		pill.root.LayoutOrder = index
		self._gpRewardPills[index] = pill
	end
	return pill
end

function QuestJournalScreen:_GPRefreshDetail()
	if not self._gpDetailScroll then
		return
	end
	local theme = self:GetTheme()
	local quest = self:_Selected()

	for _, child in self._gpObjectives:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy() -- plain lines: no shadow handles to release
		end
	end

	if not quest then
		self._gpCard.root.Visible = false
		self._gpStateChip.root.Visible = false
		self._gpStateLine.Text = "Pick a quest on the left."
		self._gpDescription.Text = ""
		self._gpTrack.root.Visible = false
		self._gpAbandon.root.Visible = false
		for _, pill in self._gpRewardPills do
			pill.root.Visible = false
			pill.shadow:SetEnabled(false)
		end
		return
	end

	self._gpCard.root.Visible = true
	self._gpStateChip.root.Visible = true
	self._gpTrack.root.Visible = true
	self._gpAbandon.root.Visible = true
	self._gpCard.name.Text = gpSoften(quest.title)
	GPLayoutKit.ApplyItemArt(self._gpCard, { iconKey = quest.icon or "quest", iconGolden = quest.state == "completed" })

	local stateName = string.sub(quest.state, 1, 1):upper() .. string.sub(quest.state, 2)
	self._gpStateChip.label.Text = stateName
	self._gpStateChip.root.BackgroundColor3 = gpStateFill(theme, quest.state)

	local done, total = gpObjectiveCount(quest)
	self._gpStateLine.Text = string.format("%s · %d of %d · %d of %d objectives done", stateName, quest.progress, quest.goal, done, total)
	self._gpDescription.Text = quest.description

	for index, objective in quest.objectives do
		local line = gpSurface("Objective" .. index, theme.Colors.Background, 1)
		line.Size = UDim2.new(1, 0, 0, 26)
		line.LayoutOrder = index
		line.Parent = self._gpObjectives

		local mark = GPLayoutKit.Slice(
			theme,
			"daisy",
			if objective.done then theme.Colors.Secondary else theme.Colors.Disabled,
			"Mark"
		)
		mark.AnchorPoint = Vector2.new(0, 0.5)
		mark.Position = UDim2.new(0, 0, 0.5, 0)
		mark.Size = UDim2.fromOffset(18, 18)
		mark.Parent = line

		local text = GPLayoutKit.BodyText(
			theme,
			theme.TextSizes.Body,
			if objective.done then theme.Colors.TextSecondary else theme.Colors.TextPrimary,
			"Text"
		)
		text.RichText = false
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.TextTruncate = Enum.TextTruncate.AtEnd
		text.Position = UDim2.fromOffset(28, 0)
		text.Size = UDim2.new(1, -28, 1, 0)
		text.Parent = line
	end

	for index, reward in quest.rewards do
		local pill = self:_GPRewardPill(theme, index)
		pill.root.Visible = true
		pill.shadow:SetEnabled(true)
		local iconId = IconArchive.Id(rewardIconName(reward))
		pill.icon.Image = iconId or ""
		local unit = gpRewardUnit(reward)
		pill.amount.Text = if unit
			then string.format("%s %s", formatAmount(reward.amount), unit)
			else formatAmount(reward.amount)
	end
	for index = #quest.rewards + 1, #self._gpRewardPills do
		local pill = self._gpRewardPills[index]
		pill.root.Visible = false
		pill.shadow:SetEnabled(false)
	end

	local active = quest.state == "active"
	self._gpTrack.label.Text = if quest.tracked then "Tracked" else "Track"
	self._gpTrack.SetTone(if quest.tracked then theme.Arcade.Gold else theme.Colors.Primary)
	self._gpAbandon.label.Text = if active then "Abandon" elseif quest.state == "completed" then "Completed" else "Failed"
	self._gpAbandon.SetTone(if active then theme.Colors.Error else theme.Colors.Disabled)
end

-- ---- one 1Hz handler for every clock on the page --------------------

function QuestJournalScreen:_GPPaintClock()
	if self._gpRefreshLabel then
		self._gpRefreshLabel.Text = gpRefreshText(self._dailyRefreshIn)
	end
end

function QuestJournalScreen:_GPStartTicker()
	if self._gpTickStop or self:LayoutKit() ~= "GP" then
		return
	end
	local accumulated = 0
	-- ONE handler on the shared UITicker Heartbeat for the whole page. The
	-- shipped panel ran a Heartbeat connection that reformatted the label every
	-- FRAME; this ticks at 1Hz, which is the resolution the label actually has.
	self._gpTickStop = UITicker.Register(function(dt: number)
		local label = self._gpRefreshLabel
		if not label or not label.Parent or not UIChrome.IsOnScreen(label) then
			return
		end
		accumulated += dt
		if accumulated < 1 then
			return
		end
		while accumulated >= 1 do
			accumulated -= 1
			self._dailyRefreshIn = math.max(0, self._dailyRefreshIn - 1)
		end
		if self._dailyRefreshIn > 0 then
			self:_GPPaintClock()
			return
		end
		-- Midnight: QuestService regenerates the set, so progress and claims
		-- reset and the clock re-arms for the next day.
		self._dailyRefreshIn = GP_DAY_SECONDS
		for _, quest in self._daily do
			quest.claimed = false
			quest.progress = 0
		end
		self:_Toast("A fresh set of daily quests!", "Success")
		self:_GPRefreshDaily()
	end, self.Root)
end

function QuestJournalScreen:_GPStopTicker()
	if self._gpTickStop then
		self._gpTickStop()
		self._gpTickStop = nil
	end
end

-- A style rebuild destroys the Gui, but UIShadow BUDGET counts live in
-- StyleKit.Capabilities and only fall when a handle is released.
function QuestJournalScreen:_OnTeardown()
	self:_GPStopTicker()
	GLLayoutKit.ReleaseShadows(self._glShadows)
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	GPLayoutKit.ReleaseShadows(self._gpTabShadows)
	if self._gpRows then
		for _, entry in self._gpRows do
			if entry.click then
				entry.click:Disconnect()
				entry.click = nil
			end
		end
		table.clear(self._gpRows)
	end
	if self._gpDailyRows then
		table.clear(self._gpDailyRows)
	end
	if self._gpRewardPills then
		table.clear(self._gpRewardPills)
	end
	self._gpRows = nil
	self._gpRowQuest = nil
	self._gpDailyRows = nil
	self._gpRewardPills = nil
	self._gpShadows = nil
	self._gpTabShadows = nil
	self._gpTabs = nil
	self._gpTabHost = nil
	self._gpTabSig = nil
	self._gpList = nil
	self._gpRail = nil
	self._gpDetailScroll = nil
	self._gpRefreshLabel = nil
	self._gpGlow = nil
	self._gpGlowHome = nil
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
