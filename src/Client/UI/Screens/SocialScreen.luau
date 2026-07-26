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
	self._friendsCount.Text = string.format("%d / %d ONLINE", online, #self._friends)

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

function SocialScreen:Destroy()
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
	UIScreenBase.Destroy(self)
end

return SocialScreen
