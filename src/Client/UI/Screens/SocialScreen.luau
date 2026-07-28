--!strict
-- SOCIAL screen — friends + party, Pottery Clash arcade family. One §7.4 modal
-- card holds two columns: FRIENDS (a scrolling list of avatar rows with a
-- colour-coded presence line and a JOIN button) and PARTY (four member slots,
-- the leader wearing the crown, empty slots reading as dashed "+ INVITE" tiles,
-- and a red LEAVE PARTY at the foot). An INVITE FRIENDS button rides in the
-- modal header next to the close X.
--
-- Presence is colour-as-identity (doc §3.3): in this server = money green,
-- another server = ice blue, offline = the OWNED grey. A friend who isn't here
-- keeps a fully lit JOIN button that DIMS in place and answers the tap with a
-- toast (doc §11.1/§11.2) — blocked controls are never removed.
--
-- Show(data) = { friends = { {userId, name, status} }, party = { {userId, name,
-- leader} } }; status is "here" | "away" | "offline" (the display strings
-- "In this server" / "In another server" / "Offline" are accepted too). Both
-- lists fall back to the demo roster below so the screen renders standalone.
--
-- Avatar heads are the arcade's sanctioned round exception (doc §4.2): a
-- clipped pill-cornered well holding the player headshot, with the flat-cartoon
-- player icon showing until (or unless) the thumbnail fetch returns.

local Players = game:GetService("Players")

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)

type Friend = { userId: number, name: string, status: string }
type PartyMember = { userId: number, name: string, leader: boolean? }

local SocialScreen = setmetatable({}, { __index = UIScreenBase })
SocialScreen.__index = SocialScreen

-- Fixed px at the 1650×1020 baseline. Card 1160×700 → content 1132×612.
local CARD = Vector2.new(1160, 700)
local CONTENT_W = 1132
local CONTENT_H = 612
local FRIENDS_W = 700
local PARTY_X = 716
local PARTY_W = 416
local COL_PAD = 12
local ROW_H = 76
local ROW_GAP = 8
local SLOT_H = 96
local SLOT_GAP = 10
local PARTY_MAX = 4
local LEAVE_H = 48

-- Dashed empty-slot outline: short bars laid along each edge. The arcade has no
-- dashed UIStroke, and an empty party seat must read as an invitation rather
-- than a disabled tile — so the dashes are drawn, at a fixed px size known here.
local DASH_LEN = 12
local DASH_GAP = 8
local DASH_THICK = 3

local DEMO_FRIENDS: { Friend } = {
	{ userId = 1, name = "ClayCrusher", status = "here" },
	{ userId = 156, name = "KilnKing", status = "here" },
	{ userId = 2, name = "GlazeGoblin", status = "away" },
	{ userId = 3, name = "WheelWitch", status = "away" },
	{ userId = 261, name = "PorcelainPete", status = "offline" },
	{ userId = 1101, name = "MugMerchant", status = "offline" },
	{ userId = 8, name = "SlipCasterX", status = "offline" },
}

local DEMO_PARTY: { PartyMember } = {
	{ userId = 1, name = "ClayCrusher", leader = true },
	{ userId = 156, name = "KilnKing" },
}

-- Presence normalises to one of three keys so callers can hand us either the
-- key or the display string.
local function presenceKey(status: string?): string
	local s = string.lower(status or "offline")
	if string.find(s, "another", 1, true) or s == "away" or s == "other" then
		return "away"
	end
	if string.find(s, "this server", 1, true) or s == "here" or s == "inserver" then
		return "here"
	end
	return "offline"
end

local function presenceText(key: string): string
	if key == "here" then
		return "IN THIS SERVER"
	elseif key == "away" then
		return "IN ANOTHER SERVER"
	end
	return "OFFLINE"
end

local function presenceColor(theme: Types.UITheme, key: string): Color3
	if key == "here" then
		return theme.Arcade.MoneyGreen
	elseif key == "away" then
		return theme.Arcade.IceBlue
	end
	return theme.Arcade.GreyOwned
end

function SocialScreen.new()
	local self = UIScreenBase.new("SocialScreen", 7)
	self._friends = DEMO_FRIENDS
	self._party = DEMO_PARTY
	-- Every component this screen owns, so a rebuild/Destroy tears them down.
	self._rowButtons = {} :: { any }
	return setmetatable(self, SocialScreen)
end

function SocialScreen:_Toast(text: string, variant: string)
	local hud = self.ScreenController and self.ScreenController:GetScreen("hud")
	if hud then
		hud:PushToast({ text = text, variant = variant })
	end
end

-- A circular avatar well: pill corners + clipping, the flat-cartoon player icon
-- as the resting art, and the real headshot swapped in when the thumbnail
-- resolves. The fetch yields, so it runs off the build thread inside a pcall —
-- a failed fetch simply leaves the icon in place (doc §10 fallback chain).
local function avatarCircle(theme: Types.UITheme, parent: Instance, userId: number, sizePx: number): Frame
	local holder = UIStyler.Frame("Avatar")
	holder.BackgroundColor3 = theme.Arcade.NearBlack
	holder.Size = UDim2.fromOffset(sizePx, sizePx)
	holder.ClipsDescendants = true
	UIChrome.Corner("Arcade", "Pill").Parent = holder
	UIChrome.Stroke(theme, "Arcade", "Panel").Parent = holder
	holder.Parent = parent

	local glyph = IconArchive.Image(holder, "player", math.floor(sizePx * 0.62))
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.5)

	local photo = Instance.new("ImageLabel")
	photo.Name = "Headshot"
	photo.BackgroundTransparency = 1
	photo.ScaleType = Enum.ScaleType.Crop
	photo.Size = UDim2.fromScale(1, 1)
	photo.Visible = false
	photo.Parent = holder

	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		end)
		if ok and typeof(content) == "string" and content ~= "" and holder.Parent then
			photo.Image = content
			photo.Visible = true
			glyph.Visible = false
		end
	end)

	return holder
end

local function dashedOutline(parent: Instance, widthPx: number, heightPx: number, color: Color3)
	local pitch = DASH_LEN + DASH_GAP
	local function edge(horizontal: boolean, atStart: boolean)
		local span = if horizontal then widthPx else heightPx
		local count = math.max(1, math.floor(span / pitch))
		local inset = (span - (count * pitch - DASH_GAP)) / 2
		for i = 0, count - 1 do
			local dash = UIStyler.Frame("Dash")
			dash.BackgroundColor3 = color
			dash.BackgroundTransparency = 0.3
			if horizontal then
				dash.Size = UDim2.fromOffset(DASH_LEN, DASH_THICK)
				dash.Position = UDim2.fromOffset(inset + i * pitch, if atStart then 0 else heightPx - DASH_THICK)
			else
				dash.Size = UDim2.fromOffset(DASH_THICK, DASH_LEN)
				dash.Position = UDim2.fromOffset(if atStart then 0 else widthPx - DASH_THICK, inset + i * pitch)
			end
			dash.Parent = parent
		end
	end
	edge(true, true)
	edge(true, false)
	edge(false, true)
	edge(false, false)
end

-- A near-black column well with the arcade chrome (3px black stroke + the glass
-- sheen) and a gold section title with a right-aligned count line.
local function column(theme: Types.UITheme, parent: Instance, name: string, x: number, width: number): (Frame, TextLabel)
	local well = UIStyler.Frame(name)
	well.BackgroundColor3 = theme.Arcade.NearBlack2
	well.BackgroundTransparency = 0
	well.Position = UDim2.fromOffset(x, 0)
	well.Size = UDim2.fromOffset(width, CONTENT_H)
	UIChrome.Stroke(theme, "Arcade").Parent = well
	UIChrome.GlassGradient().Parent = well
	well.Parent = parent

	local title = UIChrome.Text("Title", 24, theme.Arcade.Gold)
	title.Text = name
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(COL_PAD + 2, 8)
	title.Size = UDim2.fromOffset(width - 200, 28)
	title.Parent = well

	local count = UIChrome.Text("Count", 18, theme.Arcade.IceBlue)
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.AnchorPoint = Vector2.new(1, 0)
	count.Position = UDim2.new(1, -(COL_PAD + 2), 0, 11)
	count.Size = UDim2.fromOffset(180, 24)
	count.Parent = well

	return well, count
end

function SocialScreen:_BuildContent()
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end
	local theme = self:GetTheme()

	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = self:_R("SOCIAL"),
		sizePx = CARD,
		onClose = function()
			self.ScreenController:HideScreen("social")
		end,
	})
	self._modal = modal

	-- INVITE FRIENDS rides in the header bar, clear of the 48px close X.
	local invite = UIButtonComponent.new()
	invite:Create(modal.header, {
		text = self:_R("INVITE FRIENDS"),
		variant = "Blue",
		iconId = IconArchive.Id("addFriend"),
		size = UDim2.fromOffset(226, 44),
		position = UDim2.new(1, -64, 0.5, 0),
		anchorPoint = Vector2.new(1, 0.5),
		onClick = function()
			self:_Toast("FRIEND INVITES SENT TO 3 PLAYERS", "Success")
		end,
	})
	invite.Root.ZIndex = 43
	self._inviteButton = invite

	local content = modal.content

	local friendsWell, friendsCount = column(theme, content, "FRIENDS", 0, FRIENDS_W)
	self._friendsCount = friendsCount

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "FriendRows"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(COL_PAD, 44)
	scroll.Size = UDim2.new(1, -COL_PAD * 2, 1, -(44 + COL_PAD))
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = theme.Arcade.Gold
	scroll.Parent = friendsWell
	UIStyler.ListLayout({
		Padding = UDim.new(0, ROW_GAP),
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	}).Parent = scroll
	self._friendScroll = scroll

	local partyWell, partyCount = column(theme, content, "PARTY", PARTY_X, PARTY_W)
	self._partyCount = partyCount

	local slots = UIStyler.Frame("Slots")
	slots.BackgroundTransparency = 1
	slots.Position = UDim2.fromOffset(COL_PAD, 44)
	slots.Size = UDim2.new(1, -COL_PAD * 2, 0, PARTY_MAX * SLOT_H + (PARTY_MAX - 1) * SLOT_GAP)
	UIStyler.ListLayout({
		Padding = UDim.new(0, SLOT_GAP),
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	}).Parent = slots
	slots.Parent = partyWell
	self._partySlots = slots

	local leave = UIButtonComponent.new()
	leave:Create(partyWell, {
		text = self:_R("LEAVE PARTY"),
		variant = "Red",
		size = UDim2.fromOffset(PARTY_W - COL_PAD * 2, LEAVE_H),
		position = UDim2.new(0.5, 0, 1, -COL_PAD),
		anchorPoint = Vector2.new(0.5, 1),
		onClick = function()
			self:_LeaveParty()
		end,
	})
	self._leaveButton = leave

	self:_Render()
end

-- One friend row: zebra fill by index, circular headshot, name over the
-- presence line, JOIN at the right end.
function SocialScreen:_BuildFriendRow(friend: Friend, index: number)
	if self:LayoutKit() == "GP" then
		self:_GPBuildFriendRow(friend, index)
		return
	end
	local theme = self:GetTheme()
	local key = presenceKey(friend.status)
	local joinable = key == "here"

	local row = UIStyler.Frame("Friend_" .. friend.name)
	row.BackgroundColor3 = if index % 2 == 1 then theme.Arcade.NearBlack2 else theme.Arcade.Row
	row.BackgroundTransparency = 0.15 -- doc §9 zebra rows
	row.Size = UDim2.new(1, -10, 0, ROW_H) -- 10px clear of the scrollbar
	row.LayoutOrder = index
	UIChrome.Stroke(theme, "Arcade").Parent = row
	UIChrome.GlassGradient().Parent = row
	row.Parent = self._friendScroll

	local avatar = avatarCircle(theme, row, friend.userId, 52)
	avatar.AnchorPoint = Vector2.new(0, 0.5)
	avatar.Position = UDim2.new(0, 14, 0.5, 0)

	local name = UIChrome.Text("Name", 22, Color3.new(1, 1, 1))
	name.Text = friend.name
	name.RichText = false
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(80, 12)
	name.Size = UDim2.fromOffset(340, 26)
	name.Parent = row

	local status = UIChrome.Text("Status", 17, presenceColor(theme, key))
	status.Text = presenceText(key)
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Position = UDim2.fromOffset(80, 40)
	status.Size = UDim2.fromOffset(340, 22)
	status.Parent = row

	local join = UIButtonComponent.new()
	join:Create(row, {
		text = self:_R("JOIN"),
		variant = "Green",
		-- Dimmed in place, never disabled: the tap still plays full juice and
		-- then explains why it can't land (doc §11.1).
		dimmed = not joinable,
		size = UDim2.fromOffset(118, 40),
		position = UDim2.new(1, -14, 0.5, 0),
		anchorPoint = Vector2.new(1, 0.5),
		onClick = function()
			if key == "offline" then
				self:_Toast(string.upper(friend.name) .. " IS OFFLINE", "Error")
			elseif key == "away" then
				self:_Toast("JOINING " .. string.upper(friend.name) .. "'S SERVER…", "Info")
			else
				self:_Toast(string.upper(friend.name) .. " IS ALREADY IN THIS SERVER", "Info")
			end
		end,
	})
	table.insert(self._rowButtons, join)
end

-- One party seat. Filled = avatar + name + role line, the leader carrying the
-- crown; empty = the dashed "+ INVITE" tile.
function SocialScreen:_BuildPartySlot(member: PartyMember?, index: number)
	if self:LayoutKit() == "GP" then
		self:_GPBuildPartySlot(member, index)
		return
	end
	local theme = self:GetTheme()
	local width = PARTY_W - COL_PAD * 2

	local slot = UIStyler.Frame("Slot" .. index)
	slot.Size = UDim2.fromOffset(width, SLOT_H)
	slot.LayoutOrder = index
	slot.Parent = self._partySlots

	if not member then
		slot.BackgroundColor3 = theme.Arcade.NearBlack
		slot.BackgroundTransparency = 0.55
		dashedOutline(slot, width, SLOT_H, theme.Arcade.Gold)

		local label = UIChrome.Text("Invite", 24, theme.Arcade.Gold)
		label.Text = "+ INVITE"
		label.Size = UDim2.fromScale(1, 1)
		label.Parent = slot

		-- Whole-cell hit target (doc §11.6): a transparent button under the
		-- label, with the press juice scaling the tile itself.
		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Text = ""
		hit.BackgroundTransparency = 1
		hit.AutoButtonColor = false
		hit.Size = UDim2.fromScale(1, 1)
		hit.Parent = slot
		hit.Activated:Connect(function()
			self:_Toast("PARTY INVITE PANEL OPENED", "Info")
		end)
		UIChrome.Animate(theme, hit, slot)
		return
	end

	slot.BackgroundColor3 = theme.Arcade.Row
	slot.BackgroundTransparency = 0.15
	UIChrome.Stroke(theme, "Arcade").Parent = slot
	UIChrome.GlassGradient().Parent = slot

	local avatar = avatarCircle(theme, slot, member.userId, 60)
	avatar.AnchorPoint = Vector2.new(0, 0.5)
	avatar.Position = UDim2.new(0, 14, 0.5, 0)

	local name = UIChrome.Text("Name", 22, Color3.new(1, 1, 1))
	name.Text = member.name
	name.RichText = false
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(88, 18)
	name.Size = UDim2.fromOffset(width - 88 - 56, 26)
	name.Parent = slot

	local role = UIChrome.Text("Role", 17, if member.leader then theme.Arcade.Gold else theme.Arcade.IceBlue)
	role.Text = if member.leader then "PARTY LEADER" else "MEMBER"
	role.TextXAlignment = Enum.TextXAlignment.Left
	role.Position = UDim2.fromOffset(88, 46)
	role.Size = UDim2.fromOffset(width - 88 - 56, 22)
	role.Parent = slot

	if member.leader then
		local crown = IconArchive.Image(slot, "crown", 34, { golden = true })
		crown.AnchorPoint = Vector2.new(1, 0.5)
		crown.Position = UDim2.new(1, -16, 0.5, 0)
	end
end

function SocialScreen:_Render()
	for _, button in self._rowButtons do
		button:Destroy()
	end
	table.clear(self._rowButtons)
	for _, child in self._friendScroll:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for _, child in self._partySlots:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local online = 0
	for index, friend in self._friends do
		if presenceKey(friend.status) ~= "offline" then
			online += 1
		end
		self:_BuildFriendRow(friend, index)
	end
	-- Pack law 5 (no all-caps copy) reaches the shared render path here, and
	-- nowhere else: the count is the only literal string _Render itself writes.
	self._friendsCount.Text = if self:LayoutKit() == "GP"
		then string.format("%d of %d online", online, #self._friends)
		else string.format("%d / %d ONLINE", online, #self._friends)

	for index = 1, PARTY_MAX do
		self:_BuildPartySlot(self._party[index], index)
	end
	self._partyCount.Text = string.format("%d / %d", math.min(#self._party, PARTY_MAX), PARTY_MAX)
	self._leaveButton.Root.Visible = #self._party > 0
end

function SocialScreen:_LeaveParty()
	if #self._party == 0 then
		self:_Toast("YOU ARE NOT IN A PARTY", "Error")
		return
	end
	self.ScreenController:ShowModal({
		kind = "Danger",
		title = self:_R("LEAVE PARTY"),
		body = self:_R("Leave the party? Your squad keeps playing without you."),
		confirmKey = "LEAVE",
		cancelKey = "STAY",
		onConfirm = function()
			self._party = {}
			self:_Render()
			self:_Toast("YOU LEFT THE PARTY", "Warning")
		end,
	})
end

function SocialScreen:_Ingest(data: any?)
	if not data then
		return
	end
	if data.friends then
		self._friends = data.friends
	end
	if data.party then
		self._party = data.party
	end
end

function SocialScreen:_OnShow(data: any?)
	self:_Ingest(data)
	if data then
		self:_Render()
	end
	if self._modal then
		UIChrome.PopIn(self:GetTheme(), self._modal.content)
	end
end

function SocialScreen:Update(data: any)
	self:_Ingest(data)
	if self._built then
		self:_Render()
	end
end

-- ========================================================================
-- GP layout — THE STUDIO SHELF (theme.LayoutKit == "GP").
--
-- Same two columns, same seven friend rows, same FOUR party seats, same four
-- data points per friend (headshot, name, presence, Join) and per seat
-- (headshot, name, role, crown). §6: nothing is dropped for prettiness. The
-- online counter, the seat counter, Invite friends and Leave party all survive.
--
-- Grammar changes only: cream page, blush column plates with a scalloped foot,
-- petal row plates ALTERNATING their mirror by index, presence carried by a
-- coloured pip plus sentence-case copy, and empty seats reading as an open
-- invitation rather than a hole.
--
-- The page is authored 48px taller than the classic card so the content field
-- lands at EXACTLY the classic 1132x612 — GPLayoutKit.Page spends 136px on
-- header + scallop + gutters where the arcade modal spends 88. The lip is paid
-- for by the CARD, never by the roster.
--
-- IMPROVISED LOCALLY (noted for the kit): GPLayoutKit has no button builder and
-- UIButtonComponent branches GL, not GP, so `gpChip` below is this screen's
-- pack-correct chip button. It returns the same {Root, SetContent, Destroy}
-- handle the existing paths already call, so _Render/_LeaveParty/Destroy are
-- untouched. Same for `gpAvatar` (the classic avatarCircle calls UIChrome.
-- Stroke, which under this pack's Chrome policy resolves to a BLACK stroke and
-- breaks pack law 1) and `gpDashPlate` (the drawn dashed outline squares off
-- petal corners).
-- ========================================================================

local GP_PAGE_GROW = 48
local GP_COL_PAD = 14
local GP_HEAD_H = 46
local GP_HEAD_INSET = 8
local GP_BODY_Y = GP_HEAD_INSET * 2 + GP_HEAD_H -- first row clears the ribbon
local GP_SCROLL_PAD = 8
local GP_ROW_H = ROW_H
local GP_SLOT_H = SLOT_H
local GP_AVATAR = 54
local GP_SLOT_AVATAR = 60
local GP_JOIN_W = 124
local GP_JOIN_H = 42

-- Two passes of the pack's own hue-preserving Deepen. One pass leaves matcha
-- and butter around 3:1 on blush — under the bar for a status line — and two
-- lands them past 6:1 while staying recognisably that hue. Colour-as-identity
-- (doc §3.3) and the pack's measured-contrast rule both survive.
local function gpInk(theme: Types.UITheme, color: Color3): Color3
	return GPLayoutKit.Deepen(theme, GPLayoutKit.Deepen(theme, color, 1), 1)
end

-- Presence, re-keyed for cream. The classic trio (MoneyGreen / IceBlue /
-- GreyOwned) reads at 2.6:1 and lower on this pack's light surfaces, and
-- GreyOwned is very nearly invisible on blush — so the SAME three states are
-- carried by ink-depth matcha, ink-depth butter and the corrected plum.
local function gpPresenceColor(theme: Types.UITheme, key: string): Color3
	if key == "here" then
		return gpInk(theme, theme.Colors.Secondary)
	elseif key == "away" then
		return gpInk(theme, theme.Colors.Accent)
	end
	return theme.Colors.TextSecondary
end

-- The pip keeps its full pastel hue (it is a shape, not text, so it has no
-- contrast floor to clear) while the line beside it runs at ink depth.
local function gpPresencePip(theme: Types.UITheme, key: string): Color3
	if key == "here" then
		return theme.Colors.Secondary
	elseif key == "away" then
		return theme.Colors.Accent
	end
	return theme.Colors.Disabled
end

-- Pack law 5: sentence case, never shouted.
local function gpPresenceText(key: string): string
	if key == "here" then
		return "In this server"
	elseif key == "away" then
		return "In another server"
	end
	return "Offline"
end

-- IconArchive's GLYPH fallback is born pure-white with a black text stroke,
-- both banned by this pack. Recolour it to ink; a real ImageLabel is left
-- alone (the flat-cartoon set is full colour by design).
local function gpIcon(theme: Types.UITheme, parent: Instance, key: string, sizePx: number, query: any?): GuiObject
	local icon = IconArchive.Image(parent, key, sizePx, query)
	if icon:IsA("TextLabel") then
		icon.TextColor3 = theme.Colors.TextPrimary
		icon.TextStrokeTransparency = 1
	end
	return icon
end

-- The GP headshot medallion: same fetch and same icon-first fallback chain as
-- avatarCircle above, with a soft deepened-tint rim in place of the black one.
local function gpAvatar(theme: Types.UITheme, parent: Instance, userId: number, sizePx: number, ring: Color3?): Frame
	local wellFill = theme.Colors.Surface
	local holder = UIStyler.Frame("Avatar")
	holder.BackgroundColor3 = wellFill
	holder.Size = UDim2.fromOffset(sizePx, sizePx)
	holder.ClipsDescendants = true
	UIStyler.Corner(theme.Radii.Pill).Parent = holder
	holder.Parent = parent
	local rim = GPLayoutKit.SoftStroke(theme, holder, ring or wellFill)
	if ring then
		rim.Color = GPLayoutKit.Deepen(theme, ring, 0.5)
		rim.Transparency = 0
	end

	local glyph = gpIcon(theme, holder, "player", math.floor(sizePx * 0.62))
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.5)

	local photo = Instance.new("ImageLabel")
	photo.Name = "Headshot"
	photo.BackgroundTransparency = 1
	photo.ScaleType = Enum.ScaleType.Crop
	photo.Size = UDim2.fromScale(1, 1)
	photo.Visible = false
	photo.Parent = holder

	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		end)
		if ok and typeof(content) == "string" and content ~= "" and holder.Parent then
			photo.Image = content
			photo.Visible = true
			glyph.Visible = false
		end
	end)

	return holder
end

local function gpVariantFill(theme: Types.UITheme, variant: string?): Color3
	local map: { [string]: Color3 } = {
		Green = theme.Colors.Secondary,
		Red = theme.Colors.Error,
		Blue = theme.Arcade.Blue,
		Gold = theme.Arcade.Gold,
		Grey = theme.Arcade.GreyOwned,
		Rose = theme.Colors.Primary,
		Ghost = theme.Colors.Surface,
	}
	return map[variant or "Ghost"] or theme.Colors.Surface
end

-- The pack's chip button. The TextButton itself stays TRANSPARENT and the fill
-- lives on a petal chip child, because UIStyleEnforcer backstops any SOLID
-- GuiButton with a BLACK 2px stroke — pack law 1 broken on sight. Dimming is
-- IN PLACE (doc §11.2): the control never disappears and the tap still lands.
local function gpChip(theme: Types.UITheme, parent: Instance, props: any, sink: { any }?): any
	local handle: any = {}

	local root = Instance.new("TextButton")
	root.Name = "GPChip"
	root.BackgroundTransparency = 1
	root.Text = ""
	root.AutoButtonColor = false
	root.Size = props.size or UDim2.fromOffset(140, 44)
	root.Position = props.position or UDim2.new()
	root.AnchorPoint = props.anchorPoint or Vector2.new(0, 0)
	root.ZIndex = props.zIndex or 6
	root.Parent = parent

	local fill = gpVariantFill(theme, props.variant)
	local chip = UIStyler.Frame("Chip")
	chip.BackgroundColor3 = fill
	chip.Size = UDim2.fromScale(1, 1)
	chip.ZIndex = root.ZIndex
	chip.Parent = root
	GPLayoutKit.Petal(theme, chip, props.petalIndex or 0)
	local stroke = GPLayoutKit.SoftStroke(theme, chip, fill)
	local shadow = GPLayoutKit.Shadow(theme, chip, "sm", sink, fill)

	local icon: GuiObject? = nil
	if props.iconKey then
		icon = gpIcon(theme, chip, props.iconKey, 24)
		local img = icon :: GuiObject
		img.AnchorPoint = Vector2.new(0, 0.5)
		img.Position = UDim2.new(0, 14, 0.5, 0)
		img.ZIndex = root.ZIndex + 1
	end

	-- Ink on every pastel: TextOnPrimary (near-white) measures 2.14:1 on rose
	-- and is not legal for a control label.
	local label = GPLayoutKit.Text(theme, theme.TextSizes.Button, theme.Colors.TextPrimary, "Label")
	label.Text = props.text or ""
	label.RichText = false
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Position = UDim2.fromOffset(if icon then 42 else 0, 0)
	label.Size = UDim2.new(1, if icon then -52 else 0, 1, 0)
	label.ZIndex = root.ZIndex + 1
	label.Parent = chip

	local function paint(variant: string?, dimmed: boolean?)
		local nextFill = gpVariantFill(theme, variant)
		chip.BackgroundColor3 = nextFill
		chip.BackgroundTransparency = if dimmed then 0.45 else 0
		stroke.Color = GPLayoutKit.Deepen(theme, nextFill, 1)
		stroke.Transparency = if dimmed then 0.6 else 0.35
		shadow.Instance.Color = GPLayoutKit.Deepen(theme, nextFill, 1)
		shadow:SetEnabled(not dimmed)
		label.TextTransparency = if dimmed then 0.35 else 0
		if icon then
			local img = icon :: any
			if img:IsA("ImageLabel") then
				img.ImageTransparency = if dimmed then 0.45 else 0
			else
				img.TextTransparency = if dimmed then 0.45 else 0
			end
		end
	end

	local variant = props.variant
	paint(variant, props.dimmed)
	if props.onClick then
		root.Activated:Connect(props.onClick)
	end
	UIChrome.Animate(theme, root, chip)

	handle.Root = root
	handle.chip = chip
	handle.label = label
	handle.shadow = shadow
	handle.SetContent = function(_self: any, next: any)
		if next.text ~= nil then
			label.Text = next.text
		end
		if next.variant ~= nil then
			variant = next.variant
		end
		paint(variant, next.dimmed)
	end
	handle.Destroy = function(_self: any)
		shadow:Release()
		if root.Parent then
			root:Destroy()
		end
	end
	return handle
end

-- An OPEN SEAT, the pack's way. The classic path draws a dashed rectangle,
-- which squares off the petal silhouette this pack is built on — so the
-- invitation is carried instead by a pale cream plate, a gingham wash, a rose
-- rim at half strength and a rose "+ Invite". Still an invitation, never a
-- disabled tile.
local function gpDashPlate(theme: Types.UITheme, host: Frame, index: number)
	local fill = theme.Colors.Background
	host.BackgroundColor3 = fill
	host.BackgroundTransparency = 0
	GPLayoutKit.Petal(theme, host, index)
	local rim = GPLayoutKit.SoftStroke(theme, host, theme.Colors.Primary)
	rim.Color = GPLayoutKit.Deepen(theme, theme.Colors.Primary, 0.6)
	rim.Transparency = 0.55

	local wash = GPLayoutKit.Tile(theme, "gingham", theme.Colors.Primary, 0.9, "SeatWash")
	wash.ZIndex = host.ZIndex + 1
	-- Clone the host's corner onto the wash so a full-bleed tile can never
	-- square off the petal silhouette underneath it (GlazeSheen's own trick).
	local hostCorner = host:FindFirstChildOfClass("UICorner")
	if hostCorner then
		hostCorner:Clone().Parent = wash
	end
	wash.Parent = host
end

-- A column plate: cream paper with a scalloped foot, a Title Case section name
-- and the right-aligned counter the classic column carries.
function SocialScreen:_GPColumn(parent: Instance, title: string, x: number, width: number): (Frame, TextLabel)
	local theme = self:GetTheme()
	local fill = theme.Colors.Surface

	local well = UIStyler.Frame(title)
	well.BackgroundColor3 = fill
	well.BackgroundTransparency = 0
	well.Position = UDim2.fromOffset(x, 0)
	well.Size = UDim2.fromOffset(width, CONTENT_H)
	-- Rows must never spill past the plate; nothing in this pack rotates, so
	-- clipping here is free (GPLayoutKit's clipping note).
	well.ClipsDescendants = true
	well.Parent = parent
	GPLayoutKit.Petal(theme, well, 0)
	GPLayoutKit.SoftStroke(theme, well, fill)
	GPLayoutKit.Shadow(theme, well, "md", self._gpShadows, fill)

	-- The header ribbon is INSET, for the reason GPLayoutKit.Page states about
	-- its own: a full-bleed band would have to match the plate's petal radii
	-- exactly or show cream slivers at the corners, and Roblox clips to the
	-- RECT, not to the rounded shape, so the sliver would survive the clip.
	local headerFill = theme.Colors.SurfaceRaised
	local header = UIStyler.Frame("Header")
	header.BackgroundColor3 = headerFill
	header.Position = UDim2.fromOffset(GP_HEAD_INSET, GP_HEAD_INSET)
	header.Size = UDim2.new(1, -GP_HEAD_INSET * 2, 0, GP_HEAD_H)
	header.ZIndex = 2
	header.Parent = well
	GPLayoutKit.Petal(theme, header, 0)
	GPLayoutKit.SoftStroke(theme, header, headerFill)

	local label = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle + 2, theme.Colors.TextPrimary, "Title")
	label.Text = title
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Position = UDim2.fromOffset(GP_COL_PAD, 0)
	label.Size = UDim2.new(1, -(GP_COL_PAD + 200), 1, 0)
	label.ZIndex = 3
	label.Parent = header

	local count = GPLayoutKit.NumberText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Count")
	count.AnchorPoint = Vector2.new(1, 0.5)
	count.Position = UDim2.new(1, -GP_COL_PAD, 0.5, 0)
	count.Size = UDim2.fromOffset(190, 24)
	count.ZIndex = 3
	count.Parent = header

	return well, count
end

function SocialScreen:_BuildGPLayout()
	local theme = self:GetTheme()

	local page = GPLayoutKit.Page(theme, self.Root, {
		titleText = "Social",
		subtitleText = "Your studio circle and tonight's party",
		sizePx = Vector2.new(CARD.X, CARD.Y + GP_PAGE_GROW),
		onClose = function()
			self.ScreenController:HideScreen("social")
		end,
	})
	self._modal = { content = page.content } :: any
	self._gpShadows = page.shadows
	local content = page.content

	-- Invite friends rides in the page ribbon's right slot, clear of the close
	-- chip (Page reserves that gap for exactly this).
	self._inviteButton = gpChip(theme, page.topRight, {
		text = "Invite friends",
		variant = "Rose",
		iconKey = "addFriend",
		size = UDim2.fromOffset(232, 44),
		zIndex = 8,
		onClick = function()
			self:_Toast("Friend invites sent to 3 players", "Success")
		end,
	}, self._gpShadows)

	local friendsWell, friendsCount = self:_GPColumn(content, "Friends", 0, FRIENDS_W)
	self._friendsCount = friendsCount

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "FriendRows"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ClipsDescendants = true -- leaking rows are a known past bug here
	scroll.Position = UDim2.fromOffset(GP_COL_PAD - GP_SCROLL_PAD, GP_BODY_Y)
	scroll.Size = UDim2.new(1, -(GP_COL_PAD - GP_SCROLL_PAD) * 2, 1, -(GP_BODY_Y + GP_COL_PAD))
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = theme.Colors.Primary
	scroll.ZIndex = 2
	scroll.Parent = friendsWell
	UIStyler.ListLayout({
		Padding = UDim.new(0, ROW_GAP),
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	}).Parent = scroll
	-- Inset so a petal corner is not sliced at the clip edge.
	UIStyler.PaddingXY(GP_SCROLL_PAD, GP_SCROLL_PAD).Parent = scroll
	self._friendScroll = scroll

	local partyWell, partyCount = self:_GPColumn(content, "Party", PARTY_X, PARTY_W)
	self._partyCount = partyCount

	local slots = UIStyler.Frame("Slots")
	slots.BackgroundTransparency = 1
	slots.Position = UDim2.fromOffset(GP_COL_PAD, GP_BODY_Y)
	slots.Size = UDim2.new(1, -GP_COL_PAD * 2, 0, PARTY_MAX * GP_SLOT_H + (PARTY_MAX - 1) * SLOT_GAP)
	slots.ZIndex = 2
	UIStyler.ListLayout({
		Padding = UDim.new(0, SLOT_GAP),
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	}).Parent = slots
	slots.Parent = partyWell
	self._partySlots = slots

	self._leaveButton = gpChip(theme, partyWell, {
		text = "Leave party",
		variant = "Red",
		size = UDim2.fromOffset(PARTY_W - GP_COL_PAD * 2, LEAVE_H),
		position = UDim2.new(0.5, 0, 1, -GP_COL_PAD),
		anchorPoint = Vector2.new(0.5, 1),
		zIndex = 3,
		onClick = function()
			self:_LeaveParty()
		end,
	}, self._gpShadows)

	self:_Render()
end

-- One friend row, GP grammar. FOUR data points, exactly as classic: headshot,
-- name, presence line, Join. Alternating petal mirror by index; no per-row
-- shadow (forty soft shadows in one scroll would eat the budget and read as a
-- sticker sheet — the reasoning GPLayoutKit.StatRow states).
function SocialScreen:_GPBuildFriendRow(friend: Friend, index: number)
	local theme = self:GetTheme()
	local key = presenceKey(friend.status)
	local joinable = key == "here"
	local fill = if index % 2 == 1 then theme.Colors.SurfaceRaised else theme.Colors.Background

	local row = UIStyler.Frame("Friend_" .. friend.name)
	row.BackgroundColor3 = fill
	row.BackgroundTransparency = 0
	row.Size = UDim2.new(1, -10, 0, GP_ROW_H) -- 10px clear of the scrollbar
	row.LayoutOrder = index
	row.Parent = self._friendScroll
	GPLayoutKit.Petal(theme, row, index)
	GPLayoutKit.SoftStroke(theme, row, fill)

	local avatar = gpAvatar(theme, row, friend.userId, GP_AVATAR, if joinable then theme.Colors.Secondary else nil)
	avatar.AnchorPoint = Vector2.new(0, 0.5)
	avatar.Position = UDim2.new(0, 14, 0.5, 0)

	local name = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "Name")
	name.Text = friend.name
	name.RichText = false
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(82, 12)
	name.Size = UDim2.fromOffset(340, 26)
	name.Parent = row

	-- Presence: a full-hue pip plus an ink-depth line. Meaning never rides on
	-- colour alone — the words say it too.
	local pip = UIStyler.Frame("PresencePip")
	pip.BackgroundColor3 = gpPresencePip(theme, key)
	pip.Position = UDim2.fromOffset(84, 46)
	pip.Size = UDim2.fromOffset(12, 12)
	UIStyler.Corner(theme.Radii.Pill).Parent = pip
	pip.Parent = row
	GPLayoutKit.SoftStroke(theme, pip, gpPresencePip(theme, key))

	local status = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, gpPresenceColor(theme, key), "Status")
	status.Text = gpPresenceText(key)
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Position = UDim2.fromOffset(104, 40)
	status.Size = UDim2.fromOffset(320, 22)
	status.Parent = row

	local join = gpChip(theme, row, {
		text = "Join",
		variant = "Green",
		-- Dimmed in place, never disabled: the tap still plays full juice and
		-- then explains why it can't land (doc §11.1).
		dimmed = not joinable,
		size = UDim2.fromOffset(GP_JOIN_W, GP_JOIN_H),
		position = UDim2.new(1, -14, 0.5, 0),
		anchorPoint = Vector2.new(1, 0.5),
		petalIndex = index + 1,
		zIndex = 3,
		onClick = function()
			if key == "offline" then
				self:_Toast(friend.name .. " is offline right now", "Error")
			elseif key == "away" then
				self:_Toast("Hopping over to " .. friend.name .. "'s server…", "Info")
			else
				self:_Toast(friend.name .. " is already in this server", "Info")
			end
		end,
	-- No page sink for a ROW chip: the handle lives in self._rowButtons, whose
	-- Destroy releases it. Pushing it into the page sink as well would grow
	-- that table by one entry per row on every re-render.
	}, nil)
	table.insert(self._rowButtons, join)
end

-- One party seat, GP grammar. Filled = medallion + name + role line, the
-- leader still wearing the crown; empty = the open-seat plate.
function SocialScreen:_GPBuildPartySlot(member: PartyMember?, index: number)
	local theme = self:GetTheme()
	local width = PARTY_W - GP_COL_PAD * 2

	local slot = UIStyler.Frame("Slot" .. index)
	slot.Size = UDim2.fromOffset(width, GP_SLOT_H)
	slot.LayoutOrder = index
	slot.ZIndex = 2
	slot.Parent = self._partySlots

	if not member then
		gpDashPlate(theme, slot, index)

		local label = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "Invite")
		label.Text = "+ Invite"
		label.TextColor3 = GPLayoutKit.Deepen(theme, theme.Colors.Primary, 1)
		label.Size = UDim2.fromScale(1, 1)
		label.ZIndex = 4
		label.Parent = slot

		-- Whole-cell hit target (doc §11.6): a transparent button under the
		-- label, with the press juice scaling the tile itself.
		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Text = ""
		hit.BackgroundTransparency = 1
		hit.AutoButtonColor = false
		hit.Size = UDim2.fromScale(1, 1)
		hit.ZIndex = 5
		hit.Parent = slot
		hit.Activated:Connect(function()
			self:_Toast("Party invite panel opened", "Info")
		end)
		UIChrome.Animate(theme, hit, slot)
		return
	end

	local fill = if member.leader then theme.Colors.SurfaceRaised else theme.Colors.Background
	slot.BackgroundColor3 = fill
	slot.BackgroundTransparency = 0
	GPLayoutKit.Petal(theme, slot, index)
	GPLayoutKit.SoftStroke(theme, slot, fill)
	if member.leader then
		-- The leader BLOOMS: a soft butter aura, not a harsh highlight.
		local glow = GPLayoutKit.Glow(theme, slot, theme.Colors.Accent)
		-- Seats are rebuilt on every _Render, so the handle rides in
		-- self._rowButtons (which _Render clears by calling Destroy) rather than
		-- in the page sink, where it would accumulate one aura per refresh and
		-- walk the budget counter up with nothing bringing it back down.
		table.insert(self._rowButtons, {
			Destroy = function(_self: any)
				glow:Release()
			end,
		} :: any)
	end

	local avatar = gpAvatar(theme, slot, member.userId, GP_SLOT_AVATAR, if member.leader then theme.Colors.Accent else nil)
	avatar.AnchorPoint = Vector2.new(0, 0.5)
	avatar.Position = UDim2.new(0, 14, 0.5, 0)

	local name = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "Name")
	name.Text = member.name
	name.RichText = false
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(90, 18)
	name.Size = UDim2.fromOffset(width - 90 - 60, 26)
	name.ZIndex = 3
	name.Parent = slot

	local role = GPLayoutKit.BodyText(
		theme,
		theme.TextSizes.Body,
		if member.leader then gpInk(theme, theme.Colors.Accent) else theme.Colors.TextSecondary,
		"Role"
	)
	role.Text = if member.leader then "Party leader" else "Member"
	role.TextXAlignment = Enum.TextXAlignment.Left
	role.Position = UDim2.fromOffset(90, 48)
	role.Size = UDim2.fromOffset(width - 90 - 60, 22)
	role.ZIndex = 3
	role.Parent = slot

	if member.leader then
		local crown = gpIcon(theme, slot, "crown", 34, { golden = true })
		crown.AnchorPoint = Vector2.new(1, 0.5)
		crown.Position = UDim2.new(1, -16, 0.5, 0)
		crown.ZIndex = 3
	end
end

-- Shadow handles are budget-registered; a destroyed GuiObject alone leaves the
-- counter high, so the sink is released here. A STYLE REBUILD runs this hook
-- and then throws the shell away, so the component teardown Destroy already did
-- lives here now and Destroy delegates — previously a style swap dropped the
-- button components on the floor.
function SocialScreen:_OnTeardown()
	for _, button in self._rowButtons do
		button:Destroy()
	end
	table.clear(self._rowButtons)
	if self._inviteButton then
		self._inviteButton:Destroy()
		self._inviteButton = nil
	end
	if self._leaveButton then
		self._leaveButton:Destroy()
		self._leaveButton = nil
	end
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	self._gpShadows = nil
end

function SocialScreen:Destroy()
	self:_OnTeardown()
	UIScreenBase.Destroy(self)
end

return SocialScreen
