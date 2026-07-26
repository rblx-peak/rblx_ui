--!strict
-- GIFTS — the gift inbox, Pottery Clash arcade family.
-- One §7.4 modal card: an unclaimed-count header with a CLAIM ALL button over a
-- scrolling list of gift rows (sender well, message line, reward chips, a 1Hz
-- gold expiry countdown and a per-row green CLAIM). Claiming recolours the row's
-- button to grey CLAIMED IN PLACE — nothing is ever removed (doc §11.2).
--
-- REUSABLE EMPTY STATE: `GiftsScreen.EmptyState(theme, parent, opts)` is a plain
-- static (no instance state) so any other screen can reuse the same treatment —
-- centred golden icon, gold FredokaOne headline, quiet GothamMedium hint:
--
--     local Gifts = require(script.Parent.GiftsScreen)
--     Gifts.EmptyState(theme, myScroll, { icon = "quest",
--         headline = "NO ACTIVE QUESTS", hint = "Talk to the foreman..." })
--
-- Fixed px at the 1650×1020 baseline (UIScreenBase attaches the UIScale).

local RunService = game:GetService("RunService")

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UIScreenBase = require(script.Parent.UIScreenBase)

type Gift = {
	id: string,
	from: string,
	message: string,
	rewards: any,
	icon: string?,
	expiresIn: number?,
	claimed: boolean?,
}

-- Card 1160×780 → content 1132×692 after the §7.4 inset.
local CARD = Vector2.new(1160, 780)
local CONTENT_W = 1132
local CONTENT_H = 692
local HEADER_H = 52
local LIST_Y = HEADER_H + 12
local LIST_H = CONTENT_H - LIST_Y
local ROW_W = CONTENT_W - 8 -- scrollbar reserve
local ROW_H = 124
local WELL = 84
local TEXT_X = 116
local RIGHT_RESERVE = 182 -- CLAIM button column
local COUNTDOWN_W = 170
-- Text column stops clear of the countdown block, so a long message truncates
-- instead of running under the timer.
local TEXT_W = ROW_W - TEXT_X - RIGHT_RESERVE - COUNTDOWN_W - 16

local WHITE = Color3.new(1, 1, 1)

local function demoGifts(): { Gift }
	return {
		{
			id = "g1", from = "CLAYMORE_99", icon = "player",
			message = "Thanks for the carry last night. Take these before I spend them.",
			rewards = { { icon = "cash", amount = "500" }, { icon = "bux", amount = "10" } },
			expiresIn = 5400,
		},
		{
			id = "g2", from = "THE KILN CREW", icon = "players",
			message = "Weekly guild payout. Spend it badly, like everyone else does.",
			rewards = { { icon = "crate", amount = "x2" } },
			expiresIn = 40 * 3600,
		},
		{
			id = "g3", from = "MODERATION TEAM", icon = "verified",
			message = "Apology package for the server hiccup on Tuesday.",
			rewards = { { icon = "bux", amount = "50" }, { icon = "ticket", amount = "x3" } },
		},
		{
			id = "g4", from = "SEASON REWARDS", icon = "trophy",
			message = "Season 4 placement bonus — top 500 finish.",
			rewards = { { icon = "trophy", amount = "x1" }, { icon = "cash", amount = "2,500" } },
			expiresIn = 11 * 3600 + 42 * 60,
		},
		{
			id = "g5", from = "POTTERBOI", icon = "player",
			message = "You dropped this in the east hall. No, really.",
			rewards = { { icon = "key", amount = "x1" } },
			claimed = true,
		},
	}
end

-- Rewards arrive as records ({ icon, amount }) or as bare strings; both render
-- as the same chip.
local function rewardChips(rewards: any): { { icon: string, text: string } }
	local chips = {}
	if type(rewards) ~= "table" then
		return chips
	end
	for _, reward in rewards do
		if type(reward) == "table" then
			table.insert(chips, {
				icon = tostring(reward.icon or "gift"),
				text = tostring(reward.amount or reward.text or reward.name or ""),
			})
		else
			table.insert(chips, { icon = "gift", text = tostring(reward) })
		end
	end
	return chips
end

local GiftsScreen = setmetatable({}, { __index = UIScreenBase })
GiftsScreen.__index = GiftsScreen

-- ========================================================================
-- Reusable empty state (static — no instance state, safe to call from any
-- screen that wants the same "nothing here" treatment).
-- ========================================================================

export type EmptyStateOptions = {
	icon: string?,
	headline: string?,
	hint: string?,
	iconSize: number?,
	golden: boolean?,
}

function GiftsScreen.EmptyState(theme: Types.UITheme, parent: Instance, opts: EmptyStateOptions?): Frame
	local options = opts or {}
	local root = UIStyler.Frame("EmptyState")
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = 45
	root.Parent = parent

	local art = IconArchive.Image(root, options.icon or "gift", options.iconSize or 104, {
		golden = options.golden ~= false,
	})
	art.AnchorPoint = Vector2.new(0.5, 1)
	art.Position = UDim2.new(0.5, 0, 0.5, -18)
	art.ZIndex = 46

	local headline = UIChrome.Text("Headline", 30, theme.Arcade.Gold)
	headline.RichText = false
	headline.Text = options.headline or "NOTHING HERE YET"
	headline.AnchorPoint = Vector2.new(0.5, 0)
	headline.Position = UDim2.new(0.5, 0, 0.5, -6)
	headline.Size = UDim2.fromOffset(640, 38)
	headline.ZIndex = 46
	headline.Parent = root

	local hint = UIChrome.BodyText("Hint", 18, theme.Arcade.IceBlue)
	hint.RichText = false
	hint.Text = options.hint or "Check back later."
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.Position = UDim2.new(0.5, 0, 0.5, 34)
	hint.Size = UDim2.fromOffset(640, 26)
	hint.ZIndex = 46
	hint.Parent = root

	return root
end

-- ========================================================================

function GiftsScreen.new()
	local self = UIScreenBase.new("GiftsScreen", 12)
	self._gifts = demoGifts()
	self._components = {} :: { any }
	self._countdowns = {} :: { { label: TextLabel, gift: Gift, button: any, row: Frame } }
	self._tickConn = nil :: RBXScriptConnection?
	return setmetatable(self, GiftsScreen)
end

function GiftsScreen:_Toast(text: string, variant: string)
	local hud = self.ScreenController and self.ScreenController:GetScreen("hud")
	if hud then
		hud:PushToast({ text = text, variant = variant })
	end
end

function GiftsScreen:_Track(component: any): any
	table.insert(self._components, component)
	return component
end

function GiftsScreen:_Ingest(data: any)
	if type(data) ~= "table" then
		return
	end
	local list = if type(data.gifts) == "table" then data.gifts elseif #data > 0 then data else nil
	if list then
		self._gifts = list
	end
end

function GiftsScreen:_UnclaimedCount(): number
	local count = 0
	for _, gift in self._gifts do
		if not gift.claimed and (gift.expiresIn == nil or gift.expiresIn > 0) then
			count += 1
		end
	end
	return count
end

-- ========================================================================
-- Rows
-- ========================================================================

function GiftsScreen:_BuildChips(theme: Types.UITheme, parent: Instance, gift: Gift)
	local strip = UIStyler.Frame("Rewards")
	strip.BackgroundTransparency = 1
	strip.Position = UDim2.fromOffset(TEXT_X, 76)
	strip.Size = UDim2.fromOffset(TEXT_W, 32)
	strip.ZIndex = 45
	strip.Parent = parent
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
	}).Parent = strip

	for order, chip in rewardChips(gift.rewards) do
		local box = UIStyler.Frame("Chip" .. order)
		box.BackgroundColor3 = theme.Arcade.NearBlack2
		box.AutomaticSize = Enum.AutomaticSize.X
		box.Size = UDim2.fromOffset(0, 30)
		box.LayoutOrder = order
		box.ZIndex = 46
		UIChrome.Corner("Arcade").Parent = box
		UIChrome.Stroke(theme, "Arcade", "Button").Parent = box
		UIStyler.ListLayout({
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
		}).Parent = box
		box.Parent = strip

		-- Inset comes from transparent spacer cells, NOT a UIPadding: a
		-- UIPadding on a frame that AutomaticSize.X's off an AutomaticSize.X
		-- label produces unstable widths (the same finding UIBadgeComponent
		-- records).
		local function spacer(layoutOrder: number)
			local gap = UIStyler.Frame("Gap")
			gap.BackgroundTransparency = 1
			gap.Size = UDim2.fromOffset(4, 30)
			gap.LayoutOrder = layoutOrder
			gap.ZIndex = 47
			gap.Parent = box
		end

		spacer(0)
		local icon = IconArchive.Image(box, chip.icon, 20)
		icon.LayoutOrder = 1
		icon.ZIndex = 47

		local text = UIChrome.Text("Amount", 17, theme.Arcade.Gold)
		text.RichText = false
		text.Text = chip.text
		text.AutomaticSize = Enum.AutomaticSize.X
		text.Size = UDim2.fromOffset(0, 30)
		text.LayoutOrder = 2
		text.ZIndex = 47
		text.Parent = box
		spacer(3)
	end
end

function GiftsScreen:_BuildRow(theme: Types.UITheme, gift: Gift, order: number)
	local expired = gift.expiresIn ~= nil and gift.expiresIn <= 0
	local claimed = gift.claimed == true

	local row = UIStyler.Frame("Gift_" .. tostring(gift.id or order))
	-- Zebra by list position (doc §9 row grammar), both fills at 0.15.
	row.BackgroundColor3 = if order % 2 == 1 then theme.Arcade.NearBlack2 else theme.Arcade.Row
	row.BackgroundTransparency = if claimed or expired then 0.4 else 0.15
	row.LayoutOrder = order
	row.Size = UDim2.fromOffset(ROW_W, ROW_H)
	row.ZIndex = 44
	UIChrome.Corner("Arcade").Parent = row
	UIChrome.Stroke(theme, "Arcade", "Panel").Parent = row
	UIChrome.GlassGradient().Parent = row
	row.Parent = self._list

	local well = UIStyler.Frame("Sender")
	well.BackgroundColor3 = theme.Arcade.NearBlack
	well.AnchorPoint = Vector2.new(0, 0.5)
	well.Position = UDim2.new(0, 16, 0.5, 0)
	well.Size = UDim2.fromOffset(WELL, WELL)
	well.ZIndex = 45
	UIChrome.Corner("Arcade").Parent = well
	UIChrome.Stroke(theme, "Arcade", "Button").Parent = well
	UIChrome.GlassGradient().Parent = well
	well.Parent = row

	local avatar = IconArchive.Image(well, gift.icon or "player", 54)
	avatar.AnchorPoint = Vector2.new(0.5, 0.5)
	avatar.Position = UDim2.fromScale(0.5, 0.5)
	avatar.ZIndex = 46

	local from = UIChrome.Text("From", 20, theme.Arcade.Gold)
	from.RichText = false
	from.Text = "FROM " .. tostring(gift.from or "UNKNOWN")
	from.TextXAlignment = Enum.TextXAlignment.Left
	from.TextTruncate = Enum.TextTruncate.AtEnd
	from.Position = UDim2.fromOffset(TEXT_X, 14)
	from.Size = UDim2.fromOffset(TEXT_W, 24)
	from.ZIndex = 45
	from.Parent = row

	local message = UIChrome.BodyText("Message", 18, if claimed or expired then theme.Arcade.GreyOwned else WHITE)
	message.RichText = false
	message.Text = tostring(gift.message or "")
	message.TextXAlignment = Enum.TextXAlignment.Left
	message.TextTruncate = Enum.TextTruncate.AtEnd
	message.Position = UDim2.fromOffset(TEXT_X, 42)
	message.Size = UDim2.fromOffset(TEXT_W, 26)
	message.ZIndex = 45
	message.Parent = row

	self:_BuildChips(theme, row, gift)

	local button = self:_Track(UIButtonComponent.new())
	button:Create(row, {
		text = if claimed then "CLAIMED" elseif expired then "EXPIRED" else "CLAIM",
		variant = if claimed or expired then "Grey" else "Green",
		dimmed = expired and not claimed,
		size = UDim2.fromOffset(150, 48),
		position = UDim2.new(1, -16, 0.5, 0),
		anchorPoint = Vector2.new(1, 0.5),
		onClick = function()
			self:_Claim(gift)
		end,
	})
	button.Root.ZIndex = 46

	if gift.expiresIn ~= nil and not claimed then
		local caption = UIChrome.Text("ExpiresCaption", 15, theme.Arcade.IceBlue)
		caption.Text = "EXPIRES IN"
		caption.TextXAlignment = Enum.TextXAlignment.Right
		caption.AnchorPoint = Vector2.new(1, 0)
		caption.Position = UDim2.new(1, -RIGHT_RESERVE, 0, 32)
		caption.Size = UDim2.fromOffset(COUNTDOWN_W, 20)
		caption.ZIndex = 45
		caption.Parent = row

		-- Countdown surface (doc §11.3): 1Hz, gold FredokaOne, HH:MM:SS.
		local countdown = UIChrome.Text("Expires", 24, theme.Arcade.SunburstGold)
		countdown.Text = if expired then "EXPIRED" else UIChrome.FormatCountdown(gift.expiresIn)
		countdown.TextXAlignment = Enum.TextXAlignment.Right
		countdown.AnchorPoint = Vector2.new(1, 0)
		countdown.Position = UDim2.new(1, -RIGHT_RESERVE, 0, 54)
		countdown.Size = UDim2.fromOffset(COUNTDOWN_W, 28)
		countdown.ZIndex = 45
		countdown.Parent = row
		if expired then
			countdown.TextColor3 = theme.Arcade.Red
		end

		table.insert(self._countdowns, { label = countdown, gift = gift, button = button, row = row })
	end
end

function GiftsScreen:_Render()
	if not self._list then
		return
	end
	local theme = self:GetTheme()
	for _, component in self._components do
		component:Destroy()
	end
	table.clear(self._components)
	table.clear(self._countdowns)
	for _, child in self._list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if self._empty then
		self._empty:Destroy()
		self._empty = nil
	end

	local isEmpty = #self._gifts == 0
	self._emptyHost.Visible = isEmpty
	self._list.Visible = not isEmpty
	if isEmpty then
		self._empty = GiftsScreen.EmptyState(theme, self._emptyHost, {
			icon = "gift",
			headline = "NO GIFTS RIGHT NOW",
			hint = "Gifts from friends, guilds and events land here.",
		})
	else
		for order, gift in self._gifts do
			self:_BuildRow(theme, gift, order)
		end
	end

	local unclaimed = self:_UnclaimedCount()
	self._countLabel.Text = if isEmpty
		then "INBOX EMPTY"
		elseif unclaimed == 0 then "ALL GIFTS CLAIMED"
		else string.format("%d GIFT%s WAITING", unclaimed, if unclaimed == 1 then "" else "S")
	self._countLabel.TextColor3 = if unclaimed == 0 then theme.Arcade.GreyOwned else theme.Arcade.Gold
	-- Blocked in place (doc §11.2): CLAIM ALL dims when there is nothing left,
	-- and still answers on tap.
	self._claimAllBtn:SetContent({ text = "CLAIM ALL", variant = "Green", dimmed = unclaimed == 0 })
end

-- ========================================================================
-- Ticker
-- ========================================================================

function GiftsScreen:_StartTicker()
	if self._tickConn then
		return
	end
	local accumulated = 0
	self._tickConn = RunService.Heartbeat:Connect(function(dt: number)
		local list = self._list
		if not list or not list.Parent or not UIChrome.IsOnScreen(list) then
			return
		end
		accumulated += dt
		if accumulated < 1 then
			return
		end
		accumulated -= 1
		local theme = self:GetTheme()
		for _, entry in self._countdowns do
			local gift = entry.gift
			if gift.expiresIn and gift.expiresIn > 0 and not gift.claimed then
				gift.expiresIn = math.max(0, gift.expiresIn - 1)
				if gift.expiresIn <= 0 then
					-- Expired: recolour in place, never remove the row.
					entry.label.Text = "EXPIRED"
					entry.label.TextColor3 = theme.Arcade.Red
					entry.row.BackgroundTransparency = 0.4
					entry.button:SetContent({ text = "EXPIRED", variant = "Grey", dimmed = true })
				else
					entry.label.Text = UIChrome.FormatCountdown(gift.expiresIn)
				end
			end
		end
	end)
end

function GiftsScreen:_StopTicker()
	if self._tickConn then
		self._tickConn:Disconnect()
		self._tickConn = nil
	end
end

-- ========================================================================
-- Claiming
-- ========================================================================

local function describe(gift: Gift): string
	local parts = {}
	for _, chip in rewardChips(gift.rewards) do
		table.insert(parts, chip.text)
	end
	return table.concat(parts, " + ")
end

function GiftsScreen:_Claim(gift: Gift)
	if gift.claimed then
		self:_Toast("THAT GIFT IS ALREADY CLAIMED", "Info")
		return
	end
	if gift.expiresIn ~= nil and gift.expiresIn <= 0 then
		self:_Toast("THAT GIFT HAS EXPIRED", "Error")
		return
	end
	gift.claimed = true
	local reward = describe(gift)
	self:_Toast(if reward == "" then "GIFT CLAIMED" else "CLAIMED " .. reward, "Success")
	self:_Render()
end

function GiftsScreen:_ClaimAll()
	local claimed, parts = 0, {}
	for _, gift in self._gifts do
		if not gift.claimed and (gift.expiresIn == nil or gift.expiresIn > 0) then
			gift.claimed = true
			claimed += 1
			local reward = describe(gift)
			if reward ~= "" then
				table.insert(parts, reward)
			end
		end
	end
	if claimed == 0 then
		self:_Toast("NOTHING LEFT TO CLAIM", "Info")
		return
	end
	self:_Toast(string.format("CLAIMED %d GIFTS  ·  %s", claimed, table.concat(parts, " + ")), "Success")
	self:_Render()
end

-- ========================================================================
-- Lifecycle
-- ========================================================================

function GiftsScreen:_BuildContent()
	local theme = self:GetTheme()

	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = "GIFTS",
		sizePx = CARD,
		onClose = function()
			self.ScreenController:HideScreen("gifts")
		end,
	})
	self._modal = modal
	local content = modal.content

	local header = UIStyler.Frame("Header")
	header.BackgroundTransparency = 1
	header.Size = UDim2.fromOffset(CONTENT_W, HEADER_H)
	header.ZIndex = 44
	header.Parent = content

	local bell = IconArchive.Image(header, "bell", 32)
	bell.AnchorPoint = Vector2.new(0, 0.5)
	bell.Position = UDim2.new(0, 0, 0.5, 0)
	bell.ZIndex = 45

	local count = UIChrome.Text("Count", 24, theme.Arcade.Gold)
	count.Text = ""
	count.TextXAlignment = Enum.TextXAlignment.Left
	count.Position = UDim2.fromOffset(44, 0)
	count.Size = UDim2.fromOffset(500, HEADER_H)
	count.ZIndex = 45
	count.Parent = header
	self._countLabel = count

	self._claimAllBtn = UIButtonComponent.new()
	self._claimAllBtn:Create(header, {
		text = "CLAIM ALL",
		variant = "Green",
		size = UDim2.fromOffset(220, 46),
		position = UDim2.new(1, 0, 0.5, 0),
		anchorPoint = Vector2.new(1, 0.5),
		onClick = function()
			self:_ClaimAll()
		end,
	})
	self._claimAllBtn.Root.ZIndex = 45

	local list = Instance.new("ScrollingFrame")
	list.Name = "Gifts"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(0, LIST_Y)
	list.Size = UDim2.fromOffset(CONTENT_W, LIST_H)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = theme.Arcade.Gold
	list.ZIndex = 43
	list.Parent = content
	UIStyler.ListLayout({ Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Left }).Parent = list
	self._list = list

	-- The empty state occupies the LIST rect, not the whole card, so the
	-- header keeps its own space above it.
	local emptyHost = UIStyler.Frame("EmptyHost")
	emptyHost.BackgroundTransparency = 1
	emptyHost.Position = UDim2.fromOffset(0, LIST_Y)
	emptyHost.Size = UDim2.fromOffset(CONTENT_W, LIST_H)
	emptyHost.Visible = false
	emptyHost.ZIndex = 44
	emptyHost.Parent = content
	self._emptyHost = emptyHost

	self:_Render()
end

function GiftsScreen:_OnShow(data: any?)
	self:_Ingest(data)
	if self._built then
		self:_Render()
	end
	self:_StartTicker()
	if self._modal then
		UIChrome.PopIn(self:GetTheme(), self._modal.content)
	end
end

function GiftsScreen:_OnHide()
	self:_StopTicker()
end

function GiftsScreen:Update(data: any)
	self:_Ingest(data)
	if self._built then
		self:_Render()
	end
end

function GiftsScreen:Destroy()
	self:_OnHide()
	for _, component in self._components do
		component:Destroy()
	end
	table.clear(self._components)
	if self._claimAllBtn then
		self._claimAllBtn:Destroy()
		self._claimAllBtn = nil
	end
	UIScreenBase.Destroy(self)
end

return GiftsScreen
