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
local IconVisibility = require(script.Parent.Parent.Icons.IconVisibility)
local UIScreenBase = require(script.Parent.UIScreenBase)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local GPStudioKit = require(script.Parent.Parent.Framework.GPStudioKit)
local GPStoreParts = require(script.Parent.Parent.Framework.GPStoreParts)
local UITicker = require(script.Parent.Parent.Framework.UITicker)
local Store = require(script.Parent.Parent.Config.PotteryStoreConfig)

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

-- GP reads the SAME rarity ladder — colour is identity and that does not
-- change with the pack — but the pack's tokens are PASTELS, and pastel text on
-- cream paper does not carry. Butter gold measures ~1.5:1 on the pack's cream
-- and matcha ~2.3:1, so every rarity tint is deepened along its own hue before
-- it is used as ink: once for display sizes (which only owe 3:1) and TWICE for
-- body sizes (which owe 4.5:1). No rarity is dropped or merged — each one is
-- still its own colour, just a colour you can read.
local function gpRarityInk(theme: Types.UITheme, rarity: string, small: boolean): Color3
	local ink = GPLayoutKit.Deepen(theme, rarityColor(theme, rarity), 1)
	if small then
		ink = GPLayoutKit.Deepen(theme, ink, 1)
	end
	return ink
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
	-- GP layout language: the matte nameplate bench (see _BuildGPLayout below);
	-- the classic arcade modal build stays untouched.
	if self:LayoutKit() == "GP" then
		-- Seed the REAL progression first: twenty titles gated on Wins or
		-- Cash, with their actual thresholds. The placeholder eight above
		-- carry no numbers, and this screen's whole job is numbers.
		self:_SeedPotteryTitles()
		self:_BuildGPLayout()
		return
	end
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
	self._previewTitle.TextColor3 = if self:LayoutKit() == "GP"
		then (if equipped then gpRarityInk(theme, equipped.rarity, false) else theme.Colors.TextSecondary)
		else (equipped and rarityColor(theme, equipped.rarity) or theme.Arcade.GreyOwned)
	self._previewCash.Text = shortCash(self._cash)
end

function TitlesScreen:_RenderList()
	if self:LayoutKit() == "GP" then
		self:_GPRenderList()
		return
	end
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
	if data.wins ~= nil then
		self._wins = data.wins
	end
	-- A title landing while the screen is up is a CELEBRATION, not a list
	-- refresh: the source fires its own reveal card for exactly this event.
	-- Only once the shell exists: a ceremony built into a Root that is about
	-- to be replaced by _EnsureBuilt would play to nobody. GP ONLY — the card
	-- is composed entirely from GPLayoutKit/GPStoreParts, so firing it under
	-- the arcade layout would drop a pastel petal card onto the arcade page.
	if type(data.unlockedTitle) == "string" and self._built and self:LayoutKit() == "GP" then
		self:CelebrateTitle(data.unlockedTitle)
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
	-- The "%d/%d" tally the source keeps in its footer. It attaches to the GP
	-- page's header slot by the layout kit's own instance names, so it does
	-- not depend on how the page above was assembled.
	self:_GPAttachCounter()
end

function TitlesScreen:Update(data: any)
	if not data then
		return
	end
	self:_Apply(data)
	self:_GPAttachCounter()
	if self._built then
		self:_RenderPreview()
		self:_RenderList()
	end
end

-- UIScreenBase.Destroy only throws the Gui away. The UIShadow BUDGET counts in
-- StyleKit.Capabilities and the celebration's ticker registration live outside
-- the Gui and are only handed back by _OnTeardown, so Destroy has to run it.
function TitlesScreen:Destroy()
	self:_OnTeardown()
	UIScreenBase.Destroy(self)
end

-- ========================================================================
-- GP layout (theme.LayoutKit == "GP") — THE NAMEPLATE BENCH, in the pack's
-- MATTE dialect: cream paper, clay speckle, sage hairlines. The preview well
-- stays the ONLY box on the page, exactly as the arcade build argues — the
-- nameplate inside it is still boxless stacked text, because that is how it
-- renders over the player's head.
--
-- ANTI-CONDESCENSION LEDGER — every reading the arcade build carries:
--   preview: caption · flanking tier marks · title in its RARITY COLOUR ·
--   display name · cash mark + cash total
--   each row: title in its rarity colour · rarity name · unlock condition
--   (still prefixed when locked) · lock mark · state chip (Equip / Equipped /
--   Locked) · whole-row hit target with the locked-tap explanation
-- Nothing merged, nothing dropped. The rarity ladder keeps all six steps.
--
-- BUDGET NOTE: rows are SHADOWLESS on purpose (the list is caller-supplied and
-- unbounded). Equipped reads as a RING — a deepened butter stroke at 3px —
-- which is this codebase's own selection grammar.
-- ========================================================================

local GP_PAGE = Vector2.new(CARD_W, CARD_H + 48)
local GP_SCROLL_PAD = 10
local GP_ROW_H = 100
local GP_CHIP_W = 156
local GP_CHIP_H = 40

function TitlesScreen:_BuildGPLayout()
	local theme = self:GetTheme()
	local spacing = theme.Spacing

	local page = GPLayoutKit.Page(theme, self.Root, {
		titleText = "Titles",
		subtitleText = "What the booth calls you when you walk in.",
		sizePx = GP_PAGE,
		onClose = function()
			self.ScreenController:HideScreen("titles")
		end,
	})
	self._gpShadows = page.shadows
	self._modal = { content = page.content, card = page.panel } :: any
	local content = page.content

	-- The preview well: the one box on the page, blush rather than cream so the
	-- nameplate stack has something to sit on.
	local preview = GPStudioKit.Paper(theme, content, {
		name = "GPPreview",
		index = 0,
		fill = theme.Colors.Surface,
		shadow = "md",
	}, self._gpShadows)
	preview.Size = UDim2.new(1, 0, 0, PREVIEW_H)

	local caption = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Caption")
	caption.Text = "Live preview"
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.Position = UDim2.fromOffset(spacing.M, spacing.S)
	caption.Size = UDim2.fromOffset(300, 20)
	caption.ZIndex = 3
	caption.Parent = preview

	local stack = UIStyler.Frame("Nameplate")
	stack.BackgroundTransparency = 1
	stack.AnchorPoint = Vector2.new(0.5, 0.5)
	stack.Position = UDim2.fromScale(0.5, 0.56)
	stack.Size = UDim2.fromOffset(460, 84)
	stack.ZIndex = 3
	stack.Parent = preview
	self._stack = stack

	local titleRow = UIStyler.Frame("TitleRow")
	titleRow.BackgroundTransparency = 1
	titleRow.Size = UDim2.new(1, 0, 0, 28)
	titleRow.ZIndex = 3
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, spacing.S),
	}).Parent = titleRow
	titleRow.Parent = stack

	local leftMark = GPStudioKit.Icon(theme, titleRow, "crown", 22, { golden = true })
	leftMark.LayoutOrder = 1
	leftMark.ZIndex = 3

	local titleLabel = GPLayoutKit.Text(theme, 24, theme.Colors.TextPrimary, "Title")
	titleLabel.AutomaticSize = Enum.AutomaticSize.X
	titleLabel.Size = UDim2.fromOffset(0, 28)
	titleLabel.RichText = false
	titleLabel.LayoutOrder = 2
	titleLabel.ZIndex = 3
	titleLabel.Parent = titleRow
	self._previewTitle = titleLabel

	local rightMark = GPStudioKit.Icon(theme, titleRow, "crown", 22, { golden = true })
	rightMark.LayoutOrder = 3
	rightMark.ZIndex = 3

	local player = Players.LocalPlayer
	-- NOT SoftCased: a display name is the player's own casing, never ours.
	local nameLabel = GPLayoutKit.Text(theme, 24, theme.Colors.TextPrimary, "DisplayName")
	nameLabel.Text = player and player.DisplayName or "PotterOfTheYear"
	nameLabel.Position = UDim2.fromOffset(0, 30)
	nameLabel.Size = UDim2.new(1, 0, 0, 28)
	nameLabel.RichText = false
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.ZIndex = 3
	nameLabel.Parent = stack

	local cashRow = UIStyler.Frame("CashRow")
	cashRow.BackgroundTransparency = 1
	cashRow.Position = UDim2.fromOffset(0, 60)
	cashRow.Size = UDim2.new(1, 0, 0, 24)
	cashRow.ZIndex = 3
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, spacing.XS + 2),
	}).Parent = cashRow
	cashRow.Parent = stack

	local cashIcon = GPStudioKit.Icon(theme, cashRow, "cash", 20)
	cashIcon.LayoutOrder = 1
	cashIcon.ZIndex = 3

	-- Matcha deepened once: the pack's money green measures ~2.3:1 on blush and
	-- this is a 20px display line that owes 3:1.
	local cashLabel = GPLayoutKit.Text(theme, 20, GPLayoutKit.Deepen(theme, theme.Arcade.MoneyGreen, 1), "Cash")
	cashLabel.AutomaticSize = Enum.AutomaticSize.X
	cashLabel.Size = UDim2.fromOffset(0, 24)
	cashLabel.RichText = false
	cashLabel.LayoutOrder = 2
	cashLabel.ZIndex = 3
	cashLabel.Parent = cashRow
	self._previewCash = cashLabel

	local list = GPStudioKit.Scroller(theme, content, {
		name = "GPTitles",
		padPx = GP_SCROLL_PAD,
	})
	list.Position = UDim2.fromOffset(0, LIST_Y)
	list.Size = UDim2.new(1, 0, 0, CONTENT_H - LIST_Y)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, ROW_GAP),
	}).Parent = list
	self._gpList = list

	self:_RenderPreview()
	self:_GPRenderList()
end

function TitlesScreen:_GPRenderList()
	for _, child in self._gpList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for index, title in self._titles do
		self:_GPBuildRow(title, index)
	end
end

function TitlesScreen:_GPBuildRow(title: Title, index: number)
	local theme = self:GetTheme()
	local spacing = theme.Spacing
	local unlocked = title.unlocked == true
	local equipped = title.equipped == true

	local root = Instance.new("TextButton")
	root.Name = "GPTitle_" .. title.id
	root.BackgroundTransparency = 1
	root.Text = ""
	root.AutoButtonColor = false
	root.Size = UDim2.new(1, -SCROLLBAR, 0, GP_ROW_H)
	root.LayoutOrder = index
	root.Parent = self._gpList

	local plate = GPStudioKit.Paper(theme, root, {
		name = "Plate",
		index = index,
		fill = if unlocked then theme.Colors.SurfaceRaised else theme.Colors.Surface,
		strokeTint = if equipped then theme.Arcade.Gold else nil,
		strokeThickness = if equipped then 3 else nil,
	})
	plate.Size = UDim2.fromScale(1, 1)

	local titleInk = if unlocked then gpRarityInk(theme, title.rarity, false) else theme.Colors.TextSecondary
	local text = GPLayoutKit.Text(theme, 26, titleInk, "TitleText")
	text.Text = title.text
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.Position = UDim2.fromOffset(spacing.L, spacing.M)
	text.Size = UDim2.new(1, -(GP_CHIP_W + 88), 0, 32)
	text.RichText = false
	text.TextTruncate = Enum.TextTruncate.AtEnd
	text.ZIndex = 3
	text.Parent = plate

	local rarity = GPLayoutKit.BodyText(theme, 15, if unlocked then gpRarityInk(theme, title.rarity, true) else theme.Colors.TextSecondary, "Rarity")
	rarity.Text = GPStudioKit.SoftCase(title.rarity)
	rarity.TextXAlignment = Enum.TextXAlignment.Left
	rarity.Position = UDim2.fromOffset(spacing.L, 56)
	rarity.Size = UDim2.fromOffset(150, 24)
	rarity.ZIndex = 3
	rarity.Parent = plate

	-- The locked prefix is kept verbatim in meaning, softened in tone: the
	-- condition is still printed in full, which is the whole point of §11.1.
	local condition = GPLayoutKit.BodyText(theme, 14, theme.Colors.TextSecondary, "Condition")
	condition.Text = if unlocked then title.condition else ("Locked — " .. title.condition)
	condition.TextXAlignment = Enum.TextXAlignment.Left
	condition.Position = UDim2.fromOffset(186, 56)
	condition.Size = UDim2.new(1, -(186 + GP_CHIP_W + 88), 0, 24)
	condition.RichText = false
	condition.TextTruncate = Enum.TextTruncate.AtEnd
	condition.ZIndex = 3
	condition.Parent = plate

	if not unlocked then
		local lock = GPStudioKit.Icon(theme, plate, "lock", 26, { tint = theme.Colors.TextSecondary })
		lock.AnchorPoint = Vector2.new(1, 0.5)
		lock.Position = UDim2.new(1, -(GP_CHIP_W + 40), 0.5, 0)
		lock.ZIndex = 3
	end

	-- State chip: a FRAME, not a nested button, so the whole row stays one hit
	-- target with no dead zone (the arcade build's §11.6 argument, kept).
	local chip = GPStudioKit.Chip(theme, plate, {
		name = "State",
		text = if not unlocked then "Locked" elseif equipped then "Equipped" else "Equip",
		tone = if not unlocked
			then theme.Colors.Disabled
			elseif equipped then theme.Arcade.Gold
			else theme.Arcade.Green,
		index = index + 1,
		sizeUDim = UDim2.fromOffset(GP_CHIP_W, GP_CHIP_H),
		position = UDim2.new(1, -spacing.L, 0.5, 0),
		anchorPoint = Vector2.new(1, 0.5),
		textSize = theme.TextSizes.Button,
	})
	chip.root.ZIndex = 3
	chip.label.ZIndex = 4

	root.Activated:Connect(function()
		self:_Activate(title)
	end)
	-- Animate LAST, after the final colours (it snapshots the rest colour).
	UIChrome.Animate(theme, root, plate)
end

-- A style rebuild destroys the Gui, but UIShadow BUDGET counts live in
-- StyleKit.Capabilities and only fall when a handle is released.
function TitlesScreen:_OnTeardown()
	self:_ReleaseCelebration()
	GPStudioKit.ReleaseShadows(self._gpShadows)
	self._gpShadows = nil
	self._gpList = nil
	self._gpCounter = nil
end

-- ========================================================================
-- The Pottery Battles progression, and the moment it pays off.
--
-- The shipped lobby's TITLES panel is a twenty-rung ladder gated on Wins or
-- Cash, a footer reading "UNLOCKED TITLES: %d/%d", an equip control per row,
-- and — the part that is not a list at all — a full CELEBRATION when a new
-- title lands: the reveal card drops from the top with a bounce, pops out at
-- you, settles, a gold sunburst spins behind the wordmark and confetti falls.
-- This block carries all four onto the pastel page.
--
-- COPY: the source shouts "NEW TITLE UNLOCKED!" and "NICE!". Both survive
-- with the same meaning, de-shouted per pack law 5. The COUNTER's format is
-- untouched: "%d/%d" is data.
-- ========================================================================

local CONFETTI_COUNT = 34
local CELEBRATION_W, CELEBRATION_H = 400, 424

-- Rebuild self._titles from the real progression. The screen's own Title
-- shape is preserved exactly (id / text / rarity / condition / unlocked /
-- equipped) so whatever renders it needs no changes; the extra numeric
-- fields ride along for the counter and the progress read-out.
function TitlesScreen:_SeedPotteryTitles()
	if self._potterySeeded then
		return
	end
	self._potterySeeded = true
	self._wins = self._wins or Store.DemoState.wins
	self._cash = Store.DemoState.cash

	local equipped = Store.DemoState.equippedTitle
	local seeded = {}
	for index, entry in Store.Titles do
		local unlocked = Store.TitleUnlocked(entry, self._wins, self._cash)
		local have = if entry.stat == "cash" then self._cash else self._wins
		table.insert(seeded, {
			id = "title_" .. index,
			text = entry.name,
			rarity = Store.TitleRarity(entry),
			-- The unlock condition, printed the way the source prints it:
			-- "LOCKED (50 wins)" becomes a plain requirement line.
			condition = if entry.req <= 0
				then "Yours from the very first pot."
				else string.format("Reach %s.", Store.TitleRequirement(entry)),
			unlocked = unlocked,
			equipped = entry.name == equipped,
			stat = entry.stat,
			req = entry.req,
			have = have,
			progress = if entry.req > 0 then math.clamp(have / entry.req, 0, 1) else 1,
			iconKey = Store.TitleIconKey(entry),
		})
	end
	self._titles = seeded
end

-- "%d/%d" — the source's UNLOCKED TITLES tally, unchanged as a number.
function TitlesScreen:UnlockedTally(): (number, number)
	local unlocked = 0
	for _, title in self._titles do
		if title.unlocked then
			unlocked += 1
		end
	end
	return unlocked, #self._titles
end

-- Hang the tally in the page's header slot. The slot is found by the LAYOUT
-- KIT's own instance names ("GPPanel" -> "TopRight"), not by any field on
-- this screen, so the counter attaches to whatever GP page is built without
-- the two builds having to know about each other.
function TitlesScreen:_GPAttachCounter()
	if self:LayoutKit() ~= "GP" then
		return
	end
	local unlocked, total = self:UnlockedTally()
	if self._gpCounter then
		self._gpCounter.value.Text = Store.Fraction(unlocked, total)
		return
	end
	local panel = self.Root:FindFirstChild("GPPanel", true)
	local slot = panel and panel:FindFirstChild("TopRight", true)
	if not slot then
		return
	end
	local theme = self:GetTheme()
	self._gpShadows = self._gpShadows or {}
	self._gpCounter = GPStoreParts.Counter(theme, slot, {
		iconKey = "trophy",
		caption = Store.Copy.titlesCounter,
		widthPx = 188,
		fill = theme.Arcade.Gold,
		layoutOrder = 20,
		sink = self._gpShadows,
	})
	self._gpCounter.value.Text = Store.Fraction(unlocked, total)
end

-- ---- the celebration ---------------------------------------------------

function TitlesScreen:_ReleaseCelebration()
	if self._celebrationStop then
		self._celebrationStop()
		self._celebrationStop = nil
	end
	self._celebration = nil
end

function TitlesScreen:_BuildCelebration(): any
	if self._celebration then
		return self._celebration
	end
	local theme = self:GetTheme()
	local spacing = theme.Spacing
	local sink = self._gpShadows or {}
	self._gpShadows = sink

	local scrim = UIStyler.Frame("TitleCelebration")
	scrim.BackgroundColor3 = theme.Colors.Overlay -- warm plum scrim, never black
	scrim.BackgroundTransparency = 0.42
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.Visible = false
	scrim.ZIndex = 80
	scrim.Parent = self.Root

	local fill = theme.Colors.SurfaceRaised
	local card = UIStyler.Frame("Card")
	card.BackgroundColor3 = fill
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(CELEBRATION_W, CELEBRATION_H)
	card.ZIndex = 81
	card.Parent = scrim
	GPLayoutKit.Petal(theme, card, 0)
	local stroke = GPLayoutKit.SoftStroke(theme, card, fill)
	GPLayoutKit.Shadow(theme, card, "lg", sink, fill)
	GPLayoutKit.GlazeSheen(theme, card)
	local glow = GPLayoutKit.Glow(theme, card, theme.Arcade.Gold, sink)

	local scale = Instance.new("UIScale")
	scale.Parent = card

	-- The spinning sunburst behind the wordmark. It is a CHILD of the card
	-- (the card face is opaque, so a sibling behind it would never be seen)
	-- and the wordmark is raised above it.
	local burst = Instance.new("ImageLabel")
	burst.Name = "Sunburst"
	burst.BackgroundTransparency = 1
	local burstDef = (theme :: any).Assets and (theme :: any).Assets.sunburstSoft
	if burstDef then
		burst.Image = burstDef.image
	end
	burst.ScaleType = Enum.ScaleType.Fit
	burst.ImageColor3 = theme.Arcade.Gold
	burst.ImageTransparency = 0.55
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.Position = UDim2.fromScale(0.5, 0.42)
	burst.Size = UDim2.fromOffset(420, 420)
	burst.ZIndex = 82
	burst.Parent = card

	-- The tier mark: star / trophy / crown for the win ladder, cash / chest
	-- for the money ladder — the source's own flex ramp, and NO mark at all
	-- for the starting title, which has not flexed anything yet.
	local tierIcon = Instance.new("ImageLabel")
	tierIcon.Name = "TierMark"
	tierIcon.BackgroundTransparency = 1
	tierIcon.ScaleType = Enum.ScaleType.Fit
	tierIcon.AnchorPoint = Vector2.new(0.5, 0)
	tierIcon.Position = UDim2.new(0.5, 0, 0, spacing.L)
	tierIcon.Size = UDim2.fromOffset(76, 76)
	tierIcon.ZIndex = 84
	tierIcon.Parent = card
	-- Iconography, not chrome: the tier mark answers the global icon toggle
	-- like every other archive image on the page. (The sunburst above is
	-- surface art and deliberately stays out of the register.)
	IconVisibility.Register(tierIcon)

	local headline = GPLayoutKit.BodyText(theme, theme.TextSizes.Subtitle, theme.Colors.TextSecondary, "Headline")
	headline.Text = Store.Copy.titlesCelebration
	headline.Position = UDim2.fromOffset(spacing.L, 112)
	headline.Size = UDim2.new(1, -spacing.L * 2, 0, 26)
	headline.ZIndex = 84
	headline.Parent = card

	-- The wordmark: the title itself, at display size, in its rarity ink.
	local word = GPLayoutKit.Text(theme, 38, theme.Colors.TextPrimary, "Wordmark")
	word.Text = ""
	word.TextWrapped = true
	word.Position = UDim2.fromOffset(spacing.M, 146)
	word.Size = UDim2.new(1, -spacing.M * 2, 0, 92)
	word.ZIndex = 84
	word.Parent = card

	local rarity = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Rarity")
	rarity.Position = UDim2.fromOffset(spacing.L, 242)
	rarity.Size = UDim2.new(1, -spacing.L * 2, 0, 22)
	rarity.ZIndex = 84
	rarity.Parent = card

	-- "Earned at 50 wins" — the source prints the requirement under the name
	-- so the moment tells you what you actually did.
	local earned = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "Earned")
	earned.Position = UDim2.fromOffset(spacing.L, 268)
	earned.Size = UDim2.new(1, -spacing.L * 2, 0, 44)
	earned.TextWrapped = true
	earned.ZIndex = 84
	earned.Parent = card

	-- The dismiss control only DISMISSES: equipping lives in the list, and a
	-- button must never promise something it does not do.
	local chip = GPStoreParts.StateChip(theme, card, {
		position = UDim2.new(0.5, 0, 1, -spacing.L),
		size = UDim2.fromOffset(220, 56),
		anchorPoint = Vector2.new(0.5, 1),
		cornerIndex = 1,
		zIndex = 84,
		sink = sink,
		onClick = function()
			self:DismissCelebration()
		end,
	})
	chip.SetState(Store.Copy.titlesCelebrationButton, theme.Colors.Secondary, true)
	chip.label.TextSize = theme.TextSizes.Subtitle

	self._celebration = {
		scrim = scrim,
		card = card,
		stroke = stroke,
		glow = glow,
		scale = scale,
		burst = burst,
		tierIcon = tierIcon,
		word = word,
		rarity = rarity,
		earned = earned,
		chip = chip,
		tweens = {} :: { Tween },
	}
	return self._celebration
end

-- Confetti: a fire-and-forget shower of soft petals from the top edge, in
-- the pack's own rarity ramp. No pure white, no pure black, nothing grey.
function TitlesScreen:_BurstConfetti(host: GuiObject)
	local theme = self:GetTheme()
	local ramp = ((theme :: any).DialectTokens and (theme :: any).DialectTokens.rarity) or { theme.Colors.Primary }
	local tweenService = game:GetService("TweenService")
	for _ = 1, CONFETTI_COUNT do
		local petal = UIStyler.Frame("Confetti")
		local size = math.random(9, 16)
		petal.Size = UDim2.fromOffset(size, size)
		petal.Position = UDim2.new(math.random(), 0, 0, -24)
		petal.BackgroundColor3 = ramp[math.random(#ramp)]
		petal.BorderSizePixel = 0
		petal.Rotation = math.random(0, 360)
		petal.ZIndex = 86
		GPLayoutKit.Petal(theme, petal, math.random(0, 1))
		petal.Parent = host

		local drift = tweenService:Create(
			petal,
			TweenInfo.new(math.random(150, 240) / 100, Enum.EasingStyle.Linear),
			{
				Position = UDim2.new(petal.Position.X.Scale, math.random(-70, 70), 1, 48),
				Rotation = petal.Rotation + math.random(-320, 320),
			}
		)
		drift.Completed:Connect(function()
			petal:Destroy()
		end)
		drift:Play()
	end
end

-- The ceremony: DROP from the top with a bounce, POP out at you, then
-- SETTLE — the source's exact three-beat entrance, on this pack's tokens.
function TitlesScreen:CelebrateTitle(name: string)
	local theme = self:GetTheme()
	local view = self:_BuildCelebration()
	local entry: any = nil
	for _, title in self._titles do
		if title.text == name then
			entry = title
			break
		end
	end

	local rarity = entry and entry.rarity or "Legendary"
	local accent = GPStoreParts.RarityColor(theme, rarity)
	view.word.Text = name
	view.word.TextColor3 = theme.Colors.TextPrimary
	view.rarity.Text = GPStoreParts.RarityLine(rarity)
	view.stroke.Color = GPLayoutKit.Deepen(theme, accent, 1)
	view.glow.Instance.Color = accent
	view.burst.ImageColor3 = accent

	local iconKey = entry and entry.iconKey
	if iconKey then
		local id = IconArchive.Id(iconKey)
		view.tierIcon.Image = id or ""
		view.tierIcon.Visible = id ~= nil
	else
		view.tierIcon.Visible = false
	end

	view.earned.Text = if entry and entry.req and entry.req > 0
		then "Earned at " .. Store.TitleRequirement(entry)
		else "Yours from the very first pot."

	for _, tween in view.tweens do
		tween:Cancel()
	end
	table.clear(view.tweens)

	view.scrim.Visible = true
	local tweenService = game:GetService("TweenService")
	view.card.Position = UDim2.fromScale(0.5, -0.32)
	view.scale.Scale = 0.58
	local drop = tweenService:Create(
		view.card,
		TweenInfo.new(0.55, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out),
		{ Position = UDim2.fromScale(0.5, 0.5) }
	)
	table.insert(view.tweens, drop)
	drop.Completed:Once(function()
		if not view.scrim.Visible then
			return
		end
		local pop = tweenService:Create(view.scale, theme.Motion.PulseUp, { Scale = theme.Motion.PulseScale })
		table.insert(view.tweens, pop)
		pop.Completed:Once(function()
			local settle = tweenService:Create(view.scale, theme.Motion.PulseSettle, { Scale = 1 })
			table.insert(view.tweens, settle)
			settle:Play()
		end)
		pop:Play()
	end)
	drop:Play()

	self:_BurstConfetti(view.scrim)
	self:_PlaySound("Success")

	-- The sunburst spins on THE shared ticker while the card is up, and the
	-- registration is released the moment it is dismissed.
	if not self._celebrationStop then
		self._celebrationStop = UITicker.Register(function(dt: number)
			local live = self._celebration
			if not live or not live.scrim.Visible then
				return
			end
			live.burst.Rotation = (live.burst.Rotation + dt * 45) % 360
		end, view.scrim)
	end
end

function TitlesScreen:DismissCelebration()
	local view = self._celebration
	if not view then
		return
	end
	view.scrim.Visible = false
	for _, tween in view.tweens do
		tween:Cancel()
	end
	table.clear(view.tweens)
	if self._celebrationStop then
		self._celebrationStop()
		self._celebrationStop = nil
	end
	-- The tally moved: a title that just unlocked is a title now counted.
	self:_GPAttachCounter()
end

return TitlesScreen
