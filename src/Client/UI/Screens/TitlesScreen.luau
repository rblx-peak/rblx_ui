--!strict
-- Titles — Pottery Clash arcade family (doc §7.4). One modal card: a live
-- nameplate PREVIEW strip on top, then a scrolling list of equippable title
-- cards.
--
-- The preview reproduces the world-space grammar of doc §9 exactly — no boxes,
-- just stacked outlined FredokaOne over a dark well: tier icons flanking the
-- title (22), white DisplayName (24), green cash (20), the 300×80 stack. The
-- title carries its RARITY colour so the player sees what they would actually
-- look like over their head; nameplate strokes stay at 0 (the doc's densest
-- tier), which is why the text reads over any backdrop.
--
-- Each card is one whole-card hit target (doc §11.6): the state chip is a
-- non-interactive Frame, so there are no dead zones and no nested buttons —
-- EQUIP / EQUIPPED / LOCKED is a recolour in place (§11.2) and a locked tap
-- still answers with its unlock condition (§11.1).

local Players = game:GetService("Players")

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIScreenBase = require(script.Parent.UIScreenBase)

type Title = {
	id: string,
	text: string,
	rarity: string,
	condition: string,
	unlocked: boolean?,
	equipped: boolean?,
}

local CARD_W, CARD_H = 1060, 760
local CONTENT_W = CARD_W - 28
local CONTENT_H = CARD_H - 88
local PREVIEW_H = 172
local LIST_Y = PREVIEW_H + 16
local ROW_H = 92
local ROW_GAP = 10
local SCROLLBAR = 8
local CHIP_W = 156
local CHIP_H = 44
local DEMO_CASH = 12400

local DEMO_TITLES: { Title } = {
	{ id = "novice", text = "Novice Potter", rarity = "Common", condition = "Throw your first pot.", unlocked = true, equipped = false },
	{ id = "regular", text = "Booth Regular", rarity = "Common", condition = "Log in on 10 separate days.", unlocked = true, equipped = false },
	{ id = "kilnhand", text = "Kiln Hand", rarity = "Uncommon", condition = "Complete 50 firings.", unlocked = true, equipped = true },
	{ id = "glazer", text = "Master Glazer", rarity = "Rare", condition = "Unlock every glaze in one family.", unlocked = true, equipped = false },
	{ id = "cobalt", text = "Cobalt Touched", rarity = "Epic", condition = "Pull a crystalline glaze from a reduction firing.", unlocked = false, equipped = false },
	{ id = "grandmaster", text = "Grandmaster of Clay", rarity = "Legendary", condition = "Finish 1,000 pieces.", unlocked = false, equipped = false },
	{ id = "kilnfather", text = "Kilnfather", rarity = "Mythic", condition = "Place top 3 on the season leaderboard.", unlocked = false, equipped = false },
	{ id = "festival", text = "Festival Champion", rarity = "Mythic", condition = "Win the summer festival commission.", unlocked = false, equipped = false },
}

-- Rarity is colour (doc §3.3: colour IS identity) — every entry resolves to a
-- theme token, never a literal, so a re-skin carries the rarity ladder with it.
local function rarityColor(theme: Types.UITheme, rarity: string): Color3
	local ladder: { [string]: Color3 } = {
		Common = theme.Colors.TextPrimary,
		Uncommon = theme.Arcade.Green,
		Rare = theme.Arcade.Blue,
		Epic = theme.Arcade.ShopAccents[4],
		Legendary = theme.Arcade.Gold,
		Mythic = theme.Arcade.Magenta,
	}
	return ladder[rarity] or theme.Colors.TextPrimary
end

local function shortCash(value: number): string
	if value >= 1000000 then
		return string.format("%.1fM", value / 1000000)
	elseif value >= 1000 then
		return string.format("%.1fK", value / 1000)
	end
	return tostring(math.floor(value))
end

local TitlesScreen = setmetatable({}, { __index = UIScreenBase })
TitlesScreen.__index = TitlesScreen

function TitlesScreen.new()
	local self = UIScreenBase.new("TitlesScreen", 6)
	self._titles = DEMO_TITLES
	self._cash = DEMO_CASH
	return setmetatable(self, TitlesScreen)
end

function TitlesScreen:_Toast(text: string, variant: string)
	local hud = self.ScreenController and self.ScreenController:GetScreen("hud")
	if hud then
		hud:PushToast({ text = text, variant = variant })
	end
end

function TitlesScreen:_Equipped(): Title?
	for _, title in self._titles do
		if title.equipped then
			return title
		end
	end
	return nil
end

function TitlesScreen:_BuildContent()
	local theme = self:GetTheme()

	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = "TITLES",
		sizePx = Vector2.new(CARD_W, CARD_H),
		onClose = function()
			self.ScreenController:HideScreen("titles")
		end,
	})
	self._modal = modal
	local content = modal.content

	-- Preview well. The well is the only box here: the nameplate stack inside
	-- it is boxless outlined text, exactly as it renders in the world (§9).
	local preview = UIStyler.Frame("Preview")
	preview.BackgroundColor3 = theme.Arcade.NearBlack
	preview.BackgroundTransparency = 0
	preview.Size = UDim2.new(1, 0, 0, PREVIEW_H)
	UIChrome.Stroke(theme, "Arcade").Parent = preview
	UIChrome.GlassGradient().Parent = preview
	preview.Parent = content

	local caption = UIChrome.Text("Caption", 15, theme.Arcade.Gold)
	caption.Text = "LIVE PREVIEW"
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.Position = UDim2.fromOffset(14, 10)
	caption.Size = UDim2.fromOffset(300, 20)
	caption.Parent = preview

	-- The doc §9 nameplate footprint: 300×80, three stacked rows.
	local stack = UIStyler.Frame("Nameplate")
	stack.BackgroundTransparency = 1
	stack.AnchorPoint = Vector2.new(0.5, 0.5)
	stack.Position = UDim2.fromScale(0.5, 0.56)
	stack.Size = UDim2.fromOffset(420, 84)
	stack.Parent = preview
	self._stack = stack

	-- Title row: tier icons flank the title, measured off the text row itself
	-- (a centred horizontal list is the layout equivalent of the doc's
	-- "measured off actual text width").
	local titleRow = UIStyler.Frame("TitleRow")
	titleRow.BackgroundTransparency = 1
	titleRow.Size = UDim2.new(1, 0, 0, 26)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
	}).Parent = titleRow
	titleRow.Parent = stack

	local leftMark = IconArchive.Image(titleRow, "crown", 22, { golden = true })
	leftMark.LayoutOrder = 1

	local titleLabel = UIChrome.Text("Title", 22, theme.Arcade.Gold)
	titleLabel.AutomaticSize = Enum.AutomaticSize.X
	titleLabel.Size = UDim2.fromOffset(0, 26)
	titleLabel.RichText = false
	titleLabel.LayoutOrder = 2
	titleLabel.Parent = titleRow
	self._previewTitle = titleLabel

	local rightMark = IconArchive.Image(titleRow, "crown", 22, { golden = true })
	rightMark.LayoutOrder = 3

	local player = Players.LocalPlayer
	local nameLabel = UIChrome.Text("DisplayName", 24, theme.Colors.TextPrimary)
	nameLabel.Text = player and player.DisplayName or "PotterOfTheYear"
	nameLabel.Position = UDim2.fromOffset(0, 28)
	nameLabel.Size = UDim2.new(1, 0, 0, 28)
	nameLabel.RichText = false
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = stack

	-- Cash row: green money text with the boxless cash mark (doc §9).
	local cashRow = UIStyler.Frame("CashRow")
	cashRow.BackgroundTransparency = 1
	cashRow.Position = UDim2.fromOffset(0, 58)
	cashRow.Size = UDim2.new(1, 0, 0, 24)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
	}).Parent = cashRow
	cashRow.Parent = stack

	local cashIcon = IconArchive.Image(cashRow, "cash", 20)
	cashIcon.LayoutOrder = 1

	local cashLabel = UIChrome.Text("Cash", 20, theme.Arcade.MoneyGreen)
	cashLabel.AutomaticSize = Enum.AutomaticSize.X
	cashLabel.Size = UDim2.fromOffset(0, 24)
	cashLabel.RichText = false
	cashLabel.LayoutOrder = 2
	cashLabel.Parent = cashRow
	self._previewCash = cashLabel

	local list = Instance.new("ScrollingFrame")
	list.Name = "Titles"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(0, LIST_Y)
	list.Size = UDim2.new(1, 0, 0, CONTENT_H - LIST_Y)
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

	self:_RenderPreview()
	self:_RenderList()
end

function TitlesScreen:_RenderPreview()
	local theme = self:GetTheme()
	local equipped = self:_Equipped()
	self._previewTitle.Text = equipped and equipped.text or "No Title"
	self._previewTitle.TextColor3 = equipped and rarityColor(theme, equipped.rarity) or theme.Arcade.GreyOwned
	self._previewCash.Text = shortCash(self._cash)
end

function TitlesScreen:_RenderList()
	for _, child in self._list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for index, title in self._titles do
		self:_BuildRow(title, index)
	end
end

function TitlesScreen:_BuildRow(title: Title, index: number)
	local theme = self:GetTheme()
	local unlocked = title.unlocked == true
	local equipped = title.equipped == true
	local tint = rarityColor(theme, title.rarity)

	local root = UIStyler.Frame("Title_" .. title.id)
	root.BackgroundTransparency = 1
	root.Size = UDim2.new(1, -SCROLLBAR, 0, ROW_H)
	root.LayoutOrder = index
	root.Parent = self._list

	-- Whole-card hit target under the surface: plain Frames never sink input,
	-- and the state chip is a Frame, so the card has no dead zones (§11.6).
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
	surface.BackgroundTransparency = if not unlocked then 0.45 else theme.Arcade.RowTransparency
	surface.AnchorPoint = Vector2.new(0.5, 0.5)
	surface.Position = UDim2.fromScale(0.5, 0.5)
	surface.Size = UDim2.fromScale(1, 1)
	surface.ZIndex = 2
	UIChrome.Stroke(theme, "Arcade", equipped and "Selection" or "Panel").Parent = surface
	UIChrome.GlassGradient().Parent = surface
	surface.Parent = root

	-- The title exactly as it renders in-world: FredokaOne in the rarity
	-- colour with the full black outline, no box behind it.
	local text = UIChrome.Text("TitleText", 26, unlocked and tint or theme.Arcade.GreyOwned)
	text.Text = title.text
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.Position = UDim2.fromOffset(20, 10)
	text.Size = UDim2.new(1, -(CHIP_W + 80), 0, 32)
	text.RichText = false
	text.TextTruncate = Enum.TextTruncate.AtEnd
	text.Parent = surface

	local rarity = UIChrome.Text("Rarity", 15, unlocked and tint or theme.Arcade.GreyOwned)
	rarity.Text = string.upper(title.rarity)
	rarity.TextXAlignment = Enum.TextXAlignment.Left
	rarity.Position = UDim2.fromOffset(20, 50)
	rarity.Size = UDim2.fromOffset(150, 22)
	rarity.Parent = surface

	local condition = UIChrome.BodyText("Condition", 14, theme.Arcade.IceBlue)
	condition.Text = unlocked and title.condition or ("LOCKED — " .. title.condition)
	condition.TextXAlignment = Enum.TextXAlignment.Left
	condition.Position = UDim2.fromOffset(180, 50)
	-- Ends clear of the lock mark, which sits just left of the state chip.
	condition.Size = UDim2.new(1, -(180 + CHIP_W + 80), 0, 22)
	condition.RichText = false
	condition.TextTruncate = Enum.TextTruncate.AtEnd
	condition.Parent = surface

	if not unlocked then
		local lock = IconArchive.Image(surface, "lock", 26)
		lock.AnchorPoint = Vector2.new(1, 0.5)
		lock.Position = UDim2.new(1, -(CHIP_W + 36), 0.5, 0)
	end

	-- State chip: EQUIP green / EQUIPPED gold / LOCKED grey — a recolour in
	-- place, not a separate control (the whole card is the control).
	local chip = UIStyler.Frame("State")
	chip.BackgroundColor3 = if not unlocked
		then theme.Arcade.GreyOwned
		elseif equipped then theme.Arcade.Gold
		else theme.Arcade.Green
	chip.BackgroundTransparency = 0
	chip.AnchorPoint = Vector2.new(1, 0.5)
	chip.Position = UDim2.new(1, -16, 0.5, 0)
	chip.Size = UDim2.fromOffset(CHIP_W, CHIP_H)
	UIChrome.Stroke(theme, "Arcade").Parent = chip
	UIChrome.ArcadeBevel().Parent = chip
	chip.Parent = surface

	local chipText = UIChrome.Text("Label", 18, theme.Colors.TextPrimary)
	chipText.Text = if not unlocked then "LOCKED" elseif equipped then "EQUIPPED" else "EQUIP"
	chipText.Size = UDim2.fromScale(1, 1)
	chipText.Parent = chip

	hit.Activated:Connect(function()
		self:_Activate(title)
	end)
	-- Animate LAST, after the final colours (it snapshots the rest colour).
	UIChrome.Animate(theme, hit, surface)
end

function TitlesScreen:_Activate(title: Title)
	if not title.unlocked then
		self:_Toast(string.format("%s is locked — %s", title.text, title.condition), "Error")
		return
	end
	if title.equipped then
		title.equipped = false
		self:_Toast("Title cleared.", "Info")
	else
		for _, other in self._titles do
			other.equipped = false
		end
		title.equipped = true
		self:_Toast("Now wearing " .. title.text .. ".", "Success")
	end
	self:_RenderPreview()
	self:_RenderList()
	-- Pulse the PREVIEW, not the card: the list is rebuilt above, so the card's
	-- surface is already gone — and the nameplate is what actually changed.
	UIChrome.Pulse(self:GetTheme(), self._stack)
end

function TitlesScreen:_Apply(data: any)
	if data.titles then
		self._titles = data.titles
	end
	if data.cash ~= nil then
		self._cash = data.cash
	end
end

-- _EnsureBuilt has already rendered with the data the screen was holding, so
-- only a fresh payload re-renders here.
function TitlesScreen:_OnShow(data: any?)
	if data then
		self:_Apply(data)
		self:_RenderPreview()
		self:_RenderList()
	end
	if self._modal then
		UIChrome.PopIn(self:GetTheme(), self._modal.content)
	end
end

function TitlesScreen:Update(data: any)
	if not data then
		return
	end
	self:_Apply(data)
	if self._built then
		self:_RenderPreview()
		self:_RenderList()
	end
end

return TitlesScreen
