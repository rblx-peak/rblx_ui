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
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local GPCelebrationKit = require(script.Parent.Parent.Framework.GPCelebrationKit)
local UITicker = require(script.Parent.Parent.Framework.UITicker)

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
	-- Every layout kit answers this call in its own language, the same way
	-- UIChrome.ModalCard does — so the screens that borrow this treatment
	-- (quest journal, codex, vendor) get the pack's empty state for free.
	if theme.LayoutKit == "GP" then
		return GPCelebrationKit.EmptyState(theme, parent, opts)
	end
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
	-- GP repaints the pastel inbox in its own copy (this pack never shouts, and
	-- the count line is generated here) — see _GPRender.
	if self:LayoutKit() == "GP" then
		self:_GPRender()
		return
	end
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
	-- GP layout language: the pastel gift shelf — cream page, glossy petal
	-- rows, sparkles on the claimable ones only — see _BuildGPLayout below.
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end

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
	-- UIScreenBase.Destroy throws the Gui away but never runs _OnTeardown (only
	-- _ResetShell does), and a destroyed UIShadow does NOT decrement the budget
	-- counter on its own — so a Destroy without this leaves the page, header,
	-- close chip and every row shadow counted forever. Same call the other GP
	-- screens make (GuildScreen, DuelResultScreen, CrateRevealScreen).
	self:_OnTeardown()
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

-- ======================================================================
-- GP layout (theme.LayoutKit == "GP") — THE GIFT SHELF.
--
-- The same inbox, re-thrown in the pack's clay: a cream Page, glossy petal
-- rows whose silhouette alternates so the stack reads hand-arranged, a butter
-- timer pill per row and a matcha claim chip — every one of them casting a
-- HUE-MATCHED shadow of its own fill.
--
-- THE CELEBRATION GRAMMAR, and it is a GRAMMAR, not decoration:
--   ready to claim — the row blooms (a zero-offset butter aura) and a ring of
--                    sparkles twinkles around its claim chip. Nothing else on
--                    the page twinkles, which is the only reason twinkling
--                    means anything.
--   claimed        — a sticker-stamp rosette lands on the sender well and the
--                    row deepens to blush IN PLACE. It is never removed.
--   expired        — the row deepens the same way, the timer goes coral, the
--                    chip dims. Still live, still answers a tap.
--
-- PRESENTATION ONLY. The same _gifts data, the same _Claim / _ClaimAll / _Toast
-- flow, the same _UnclaimedCount, and — the part that matters — the SAME 1Hz
-- expiry ticker: _StartTicker is untouched, because every row registers the
-- identical { label, gift, button, row } record, the GP claim chip answers the
-- same :SetContent({ text, variant, dimmed }) vocabulary the arcade button
-- does, and the ticker's "fade the row out" poke is caught and re-expressed as
-- this pack's deepen-in-place (see the transparency mirror in _GPBuildRow).
--
-- DENSITY IS UNCHANGED: sender art, sender name, message line, EVERY reward
-- chip, the expiry caption, the live countdown and the per-row claim control
-- all survive, plus the header count and CLAIM ALL. Nothing was dropped to
-- make room for the pastel.
-- ======================================================================

local GP_PAGE = Vector2.new(1160, 780)
local GP_HEADER_H = 52
local GP_LIST_Y = GP_HEADER_H + 12
local GP_ROW_W = 1100
local GP_ROW_H = 124
local GP_WELL = 84
local GP_TEXT_X = 114
local GP_CLAIM_W = 150
local GP_CLAIM_H = 48
local GP_TIMER_W = 176
local GP_TIMER_H = 58
-- The text column stops clear of the timer pill, so a long message truncates
-- instead of running under the clock (the classic row's rule, re-measured).
local GP_TEXT_W = GP_ROW_W - GP_TEXT_X - (14 + GP_CLAIM_W + 14 + GP_TIMER_W) - 14
local GP_GLOW_BASE = 0.44
local GP_GLOW_SWING = 0.16
local GP_GLOW_HZ = 1.5

function GiftsScreen:_BuildGPLayout()
	local theme = self:GetTheme()

	self._gpShadows = {} :: { any }
	self._gpRowShadows = {} :: { any }
	self._gpSparkles = {} :: { any }
	self._gpGlows = {} :: { any }

	local page = GPLayoutKit.Page(theme, self.Root, {
		titleText = "Gifts",
		subtitleText = "Somebody left something on your shelf.",
		sizePx = GP_PAGE,
		onClose = function()
			self.ScreenController:HideScreen("gifts")
		end,
	})
	for _, handle in page.shadows do
		table.insert(self._gpShadows, handle)
	end
	-- _OnShow pops the panel through the shared modal contract; the GP page has
	-- no separate card/content split, so both point at the plate.
	self._modal = { card = page.panel, content = page.panel }

	local content = page.content

	local header = UIStyler.Frame("Header")
	header.BackgroundColor3 = theme.Colors.Background
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, GP_HEADER_H)
	header.ZIndex = 4
	header.Parent = content

	local bell = GPCelebrationKit.Icon(theme, header, "bell", 34)
	bell.AnchorPoint = Vector2.new(0, 0.5)
	bell.Position = UDim2.new(0, 0, 0.5, 0)
	bell.ZIndex = 5

	local count = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle + 2, theme.Colors.TextPrimary, "Count")
	count.Text = ""
	count.RichText = false
	count.TextXAlignment = Enum.TextXAlignment.Left
	count.TextTruncate = Enum.TextTruncate.AtEnd
	count.Position = UDim2.fromOffset(46, 0)
	count.Size = UDim2.fromOffset(560, GP_HEADER_H)
	count.ZIndex = 5
	count.Parent = header
	self._countLabel = count

	-- The claim-all chip is NOT in self._components: _Render clears that list on
	-- every repaint and this control outlives every repaint (the arcade build
	-- keeps it in its own field for the same reason).
	self._claimAllBtn = GPCelebrationKit.Button(theme, header, {
		text = "Claim all",
		variant = "Green",
		size = UDim2.fromOffset(220, 46),
		position = UDim2.new(1, 0, 0.5, 0),
		anchorPoint = Vector2.new(1, 0.5),
		zIndex = 5,
		cornerIndex = 1,
		onClick = function()
			self:_ClaimAll()
		end,
	}, self._gpShadows)

	-- MUST clip: unclipped rows spilling past the frame is a known past bug
	-- here, and the Scroller's padding keeps the clip edge off the row shadows.
	local list = GPCelebrationKit.Scroller(theme, content, { padPx = 8, gapPx = theme.Spacing.S, zIndex = 3 })
	list.Position = UDim2.fromOffset(0, GP_LIST_Y)
	list.Size = UDim2.new(1, 0, 1, -GP_LIST_Y)
	self._list = list

	-- The empty state occupies the LIST rect, not the whole page, so the header
	-- keeps its own space above it.
	local emptyHost = UIStyler.Frame("EmptyHost")
	emptyHost.BackgroundColor3 = theme.Colors.Background
	emptyHost.BackgroundTransparency = 1
	emptyHost.Position = UDim2.fromOffset(0, GP_LIST_Y)
	emptyHost.Size = UDim2.new(1, 0, 1, -GP_LIST_Y)
	emptyHost.Visible = false
	emptyHost.ZIndex = 4
	emptyHost.Parent = content
	self._emptyHost = emptyHost

	-- ONE ticker handler for the whole page (never a RunService connection):
	-- the sparkle shimmer and the claimable aura's breath. Bound to the panel,
	-- so a destroyed page releases it even if teardown never ran.
	self._gpStop = UITicker.Register(function(_dt: number, now: number)
		if not UIChrome.IsOnScreen(list) then
			return
		end
		for _, sparkles in self._gpSparkles do
			sparkles.Step(now)
		end
		local breath = GP_GLOW_BASE + GP_GLOW_SWING * (0.5 + 0.5 * math.sin(now * GP_GLOW_HZ))
		for _, glow in self._gpGlows do
			glow.Instance.Transparency = breath
		end
	end, page.panel)

	self:_GPRender()
end

-- One gift, as a glossy petal row. Registers the SAME countdown record the
-- arcade row does, so the shared 1Hz ticker drives it with no branch.
function GiftsScreen:_GPBuildRow(theme: Types.UITheme, gift: Gift, order: number)
	local expired = gift.expiresIn ~= nil and gift.expiresIn <= 0
	local claimed = gift.claimed == true
	local claimable = not claimed and not expired
	-- A spent row DEEPENS to blush rather than fading out: this pack says
	-- "done" with fill and shadow, never by draining a row toward the page.
	local spentTone = theme.Colors.Surface

	local row = GPCelebrationKit.Row(theme, self._list, order, self._gpRowShadows, {
		widthPx = GP_ROW_W,
		heightPx = GP_ROW_H,
		zIndex = 4,
	})
	row.root.Name = "Gift_" .. tostring(gift.id or order)
	local body = row.body
	if not claimable then
		row.SetTone(spentTone)
	end

	-- THE TICKER MIRROR. _StartTicker expires a row by pushing its
	-- BackgroundTransparency to 0.4 — the arcade "fade it back" idiom, which
	-- under this pack would drain a pastel row toward the cream page and lose
	-- both the fill and the hue-matched shadow that carry the state. The poke is
	-- caught here and re-expressed as the pack's deepen-in-place, which is what
	-- keeps _StartTicker byte-identical across all four layout kits.
	body:GetPropertyChangedSignal("BackgroundTransparency"):Connect(function()
		if body.BackgroundTransparency > 0 then
			body.BackgroundTransparency = 0
			row.SetTone(spentTone)
		end
	end)

	local wellFill = theme.Colors.Background
	local well = UIStyler.Frame("Sender")
	well.BackgroundColor3 = wellFill
	well.AnchorPoint = Vector2.new(0, 0.5)
	well.Position = UDim2.new(0, 14, 0.5, 0)
	well.Size = UDim2.fromOffset(GP_WELL, GP_WELL)
	well.ZIndex = 6
	well.Parent = body
	-- +1 against the row's own petal so the two silhouettes nest, not fight.
	GPLayoutKit.Petal(theme, well, order + 1)
	GPLayoutKit.SoftStroke(theme, well, wellFill)

	local avatar = GPCelebrationKit.Icon(theme, well, gift.icon or "player", 54)
	avatar.AnchorPoint = Vector2.new(0.5, 0.5)
	avatar.Position = UDim2.fromScale(0.5, 0.5)
	avatar.ZIndex = 7
	if not claimable then
		GPCelebrationKit.TintIcon(avatar, theme.Colors.Disabled, 0.25)
	end

	-- The sticker stamp: claimed gifts wear a rosette on the sender well. It
	-- does not rotate — a rotated descendant is NOT clipped by the scroller.
	local stamp = GPCelebrationKit.Stamp(theme, well, "Claimed", {
		sizePx = GP_WELL + 10,
		textSize = theme.TextSizes.Small,
		zIndex = 9,
	})
	stamp.SetVisible(claimed)

	local from = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle, GPLayoutKit.Deepen(theme, theme.Colors.Primary, 1), "From")
	from.Text = "From " .. tostring(gift.from or "someone shy")
	from.RichText = false
	from.TextXAlignment = Enum.TextXAlignment.Left
	from.TextTruncate = Enum.TextTruncate.AtEnd
	from.Position = UDim2.fromOffset(GP_TEXT_X, 12)
	from.Size = UDim2.fromOffset(GP_TEXT_W, 24)
	from.ZIndex = 6
	from.Parent = body

	local message = GPLayoutKit.BodyText(
		theme,
		theme.TextSizes.Body + 1,
		if claimable then theme.Colors.TextPrimary else theme.Colors.TextSecondary,
		"Message"
	)
	message.Text = tostring(gift.message or "")
	message.RichText = false
	message.TextXAlignment = Enum.TextXAlignment.Left
	message.TextTruncate = Enum.TextTruncate.AtEnd
	message.Position = UDim2.fromOffset(GP_TEXT_X, 40)
	message.Size = UDim2.fromOffset(GP_TEXT_W, 26)
	message.ZIndex = 6
	message.Parent = body

	-- EVERY reward chip, exactly as the arcade row lists them.
	local strip = UIStyler.Frame("Rewards")
	strip.BackgroundColor3 = theme.Colors.Background
	strip.BackgroundTransparency = 1
	strip.Position = UDim2.fromOffset(GP_TEXT_X, 74)
	strip.Size = UDim2.fromOffset(GP_TEXT_W, 34)
	strip.ZIndex = 6
	strip.Parent = body
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
	}).Parent = strip

	for chipOrder, chip in rewardChips(gift.rewards) do
		GPCelebrationKit.RewardChip(theme, strip, {
			iconKey = chip.icon,
			text = chip.text,
			index = chipOrder,
			textTone = if claimable then theme.Colors.TextPrimary else theme.Colors.TextSecondary,
			zIndex = 7,
		})
	end

	local button = self:_Track(GPCelebrationKit.Button(theme, body, {
		text = if claimed then "Claimed" elseif expired then "Expired" else "Claim",
		variant = if claimed or expired then "Grey" else "Green",
		dimmed = expired and not claimed,
		size = UDim2.fromOffset(GP_CLAIM_W, GP_CLAIM_H),
		position = UDim2.new(1, -14, 0.5, 0),
		anchorPoint = Vector2.new(1, 0.5),
		zIndex = 7,
		cornerIndex = order,
		onClick = function()
			self:_Claim(gift)
		end,
		-- Tracked in _components AND in the row sink on purpose: _GPRender
		-- releases through the component, teardown releases through the sink,
		-- and a second Release is a no-op (it decrements only once).
	}, self._gpRowShadows))

	if gift.expiresIn ~= nil and not claimed then
		local timer = GPCelebrationKit.Countdown(theme, body, {
			caption = "Expires in",
			widthPx = GP_TIMER_W,
			heightPx = GP_TIMER_H,
			zIndex = 6,
		}, self._gpRowShadows)
		timer.root.AnchorPoint = Vector2.new(1, 0.5)
		timer.root.Position = UDim2.new(1, -(14 + GP_CLAIM_W + 14), 0.5, 0)
		timer.value.Text = if expired then "Expired" else UIChrome.FormatCountdown(gift.expiresIn)
		if expired then
			timer.value.TextColor3 = theme.Colors.Error
		end
		-- THE SECOND TICKER MIRROR, and it is the same move as the transparency
		-- one above. When a gift runs out, _StartTicker retitles this clock to the
		-- arcade's "EXPIRED" — a SHOUT, which law 5 forbids under this pack, and
		-- which would disagree with the "Expired" the very same row was built with
		-- a second earlier. The poke is caught here and re-cased, which is what
		-- keeps _StartTicker byte-identical across every layout kit.
		-- A live tick passes straight through: FormatCountdown emits digits and
		-- colons only, and SoftCase returns any string already carrying a lowercase
		-- letter verbatim — so the re-set settles in one pass and never loops.
		timer.value:GetPropertyChangedSignal("Text"):Connect(function()
			local cased = GPCelebrationKit.SoftCase(timer.value.Text)
			if cased ~= timer.value.Text then
				timer.value.Text = cased
			end
		end)
		-- The SAME record the arcade row registers: shared _StartTicker owns it.
		table.insert(self._countdowns, { label = timer.value, gift = gift, button = button, row = body })
	end

	-- CLAIMABLE ONLY, and this is the whole point of the treatment: the row
	-- blooms and the sparkles come out for the gifts you can actually take.
	if claimable then
		local glow = GPLayoutKit.Glow(theme, body, theme.Colors.Accent, self._gpRowShadows)
		table.insert(self._gpGlows, glow)
		local sparkles = GPCelebrationKit.Sparkles(theme, button.Root, { inflatePx = 14, zIndex = 8 })
		sparkles.SetEnabled(true)
		table.insert(self._gpSparkles, sparkles)
	end
end

-- The GP answer to _Render (see the dispatch at the top of that function).
-- Same clear/rebuild/count sequence; this pack's copy, and a shadow sink that
-- is handed back before the rows it belongs to are destroyed.
function GiftsScreen:_GPRender()
	if not self._list then
		return
	end
	local theme = self:GetTheme()
	for _, component in self._components do
		component:Destroy()
	end
	table.clear(self._components)
	table.clear(self._countdowns)
	table.clear(self._gpSparkles)
	table.clear(self._gpGlows)
	-- Release BEFORE the rows are destroyed: a destroyed GuiObject alone leaves
	-- the live-UIShadow budget counter high forever.
	GPLayoutKit.ReleaseShadows(self._gpRowShadows)
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
			headline = "Nothing on the shelf",
			hint = "Gifts from friends, guilds and events land right here.",
		})
	else
		for order, gift in self._gifts do
			self:_GPBuildRow(theme, gift, order)
		end
	end

	local unclaimed = self:_UnclaimedCount()
	self._countLabel.Text = if isEmpty
		then "Your shelf is empty"
		elseif unclaimed == 0 then "Every gift claimed"
		else string.format("%d gift%s waiting for you", unclaimed, if unclaimed == 1 then "" else "s")
	self._countLabel.TextColor3 = if unclaimed == 0
		then theme.Colors.TextSecondary
		else GPLayoutKit.Deepen(theme, theme.Colors.Primary, 1)
	-- Blocked in place (doc §11.2): claim-all dims when there is nothing left,
	-- and still answers on tap.
	self._claimAllBtn:SetContent({ text = "Claim all", variant = "Green", dimmed = unclaimed == 0 })
end

-- A style rebuild destroys the Gui, but UIShadow BUDGET counts only fall when a
-- handle is released — hand every GP shadow back here, and stop the one ticker.
function GiftsScreen:_OnTeardown()
	self:_StopTicker()
	if self._gpStop then
		self._gpStop()
		self._gpStop = nil :: any
	end
	GPLayoutKit.ReleaseShadows(self._gpRowShadows)
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	-- Cleared, not nil'd: _BuildGPLayout re-seeds both on the next build, and a
	-- live table keeps the ticker handler's loops trivially safe if it races the
	-- teardown by a frame.
	if self._gpSparkles then
		table.clear(self._gpSparkles)
	end
	if self._gpGlows then
		table.clear(self._gpGlows)
	end
end

return GiftsScreen
