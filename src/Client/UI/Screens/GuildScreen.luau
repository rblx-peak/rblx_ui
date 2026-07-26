--!strict
-- GUILD hub — Pottery Clash arcade family (doc §7.4). One modal card: a header
-- (crest well + guild name, level/member meta line, guild XP ruler) over three
-- tabs — ROSTER (avatar rows with colour-coded rank chips, right-aligned
-- contribution and an online dot), PERKS (level-gated rows that dim in place,
-- doc §11.2) and LOG (contribution/event feed, newest first) — with INVITE and
-- LEAVE GUILD (Danger confirm modal) in the footer.
--
-- Rank is colour-as-identity (doc §3.3): LEADER gold, OFFICER blue, MEMBER
-- grey — the chip carries the rank the same way everywhere. A locked perk dims
-- in place and still answers every tap with its unlock requirement (§11.1);
-- the three tab bodies are built once and toggled, so switching never rebuilds.
--
-- Show(data) = { name, level, xp, xpMax, members, perks, log }.

local Players = game:GetService("Players")

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UIProgressBarComponent = require(script.Parent.Parent.Components.UIProgressBarComponent)

type Member = { userId: number, name: string, rank: string, contribution: number, online: boolean? }
type Perk = { icon: string?, name: string, desc: string, requires: number }
type LogEntry = { icon: string?, text: string, ago: number }
type GuildData = {
	name: string,
	level: number,
	xp: number,
	xpMax: number,
	members: { Member },
	perks: { Perk },
	log: { LogEntry },
}

local WHITE = Color3.new(1, 1, 1)

-- Fixed px at the 1650×1020 baseline. Card 1160×720 → content 1132×632.
local CARD = Vector2.new(1160, 720)
local CONTENT_H = 632
local CREST = 96
local TABS_Y = 118
local TAB_W = 170
local TAB_H = 40
local WELL_Y = 170
local FOOTER_H = 52
local WELL_H = CONTENT_H - WELL_Y - FOOTER_H - 12
local ROSTER_ROW_H = 64
local PERK_ROW_H = 72
local LOG_ROW_H = 48
local ROW_GAP = 6

local TABS = {
	{ id = "roster", label = "ROSTER" },
	{ id = "perks", label = "PERKS" },
	{ id = "log", label = "LOG" },
}

local DEMO: GuildData = {
	name = "KILN & KIN",
	level = 7,
	xp = 5400,
	xpMax = 8000,
	members = {
		{ userId = 1, name = "ClayCrusher", rank = "LEADER", contribution = 48210, online = true },
		{ userId = 156, name = "KilnKing", rank = "OFFICER", contribution = 31940, online = true },
		{ userId = 2, name = "WheelWitch", rank = "OFFICER", contribution = 27615, online = false },
		{ userId = 3, name = "GlazeGoblin", rank = "MEMBER", contribution = 19480, online = true },
		{ userId = 261, name = "PorcelainPete", rank = "MEMBER", contribution = 12305, online = false },
		{ userId = 1101, name = "MugMerchant", rank = "MEMBER", contribution = 9840, online = true },
		{ userId = 8, name = "SlipCasterX", rank = "MEMBER", contribution = 7420, online = false },
		{ userId = 21, name = "AmphoraAnnie", rank = "MEMBER", contribution = 5115, online = false },
		{ userId = 55, name = "TerracottaTom", rank = "MEMBER", contribution = 2980, online = true },
		{ userId = 89, name = "BisqueBoss", rank = "MEMBER", contribution = 1240, online = false },
	},
	perks = {
		{ icon = "cash", name = "CLAY CUT", desc = "+5% Cash from every match", requires = 2 },
		{ icon = "star", name = "KILN BOOST", desc = "+10% Guild XP from contributions", requires = 4 },
		{ icon = "heart", name = "STURDY WARE", desc = "+1 extra life in duels", requires = 6 },
		{ icon = "bag", name = "MARKET STALL", desc = "5% discount at every vendor", requires = 9 },
		{ icon = "crate", name = "WEEKLY CRATE", desc = "A free guild crate every week", requires = 11 },
		{ icon = "crown", name = "BANNER OF THE KILN", desc = "Exclusive guild title + nameplate crest", requires = 14 },
	},
	log = {
		{ icon = "cash", text = "KilnKing donated 2,500 Cash", ago = 120 },
		{ icon = "star", text = "Guild reached Level 7", ago = 1560 },
		{ icon = "addFriend", text = "TerracottaTom joined the guild", ago = 4980 },
		{ icon = "swords", text = "GlazeGoblin won a ranked duel (+150 Guild XP)", ago = 7620 },
		{ icon = "cash", text = "MugMerchant donated 1,000 Cash", ago = 21600 },
		{ icon = "crate", text = "Weekly guild crate delivered", ago = 64800 },
		{ icon = "quest", text = "Guild quest completed: FIRE 500 POTS", ago = 172800 },
	},
}

local function formatNumber(n: number): string
	local formatted = tostring(math.floor(n))
	while true do
		local replaced: number
		formatted, replaced = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then
			break
		end
	end
	return formatted
end

local function agoText(seconds: number): string
	if seconds < 60 then
		return "JUST NOW"
	elseif seconds < 3600 then
		return string.format("%dM AGO", seconds // 60)
	elseif seconds < 86400 then
		return string.format("%dH AGO", seconds // 3600)
	end
	return string.format("%dD AGO", seconds // 86400)
end

local function rankColors(theme: Types.UITheme, rank: string): (Color3, Color3)
	if rank == "LEADER" then
		return theme.Arcade.Gold, theme.Arcade.NearBlack
	elseif rank == "OFFICER" then
		return theme.Arcade.Blue, WHITE
	end
	return theme.Arcade.GreyOwned, WHITE
end

local function dimIcon(icon: GuiObject, transparency: number)
	if icon:IsA("ImageLabel") then
		icon.ImageTransparency = transparency
	elseif icon:IsA("TextLabel") then
		icon.TextTransparency = transparency
	end
end

-- Circular avatar well (the arcade's sanctioned round exception, doc §4.2):
-- flat-cartoon player icon resting, real headshot swapped in when the fetch
-- resolves — a failed fetch just leaves the icon (doc §10 fallback chain).
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

local GuildScreen = setmetatable({}, { __index = UIScreenBase })
GuildScreen.__index = GuildScreen

function GuildScreen.new()
	local self = UIScreenBase.new("GuildScreen", 7)
	self._data = DEMO :: GuildData
	self._tab = "roster"
	self._tabButtons = {} :: { [string]: any }
	self._tabBodies = {} :: { [string]: ScrollingFrame }
	return setmetatable(self, GuildScreen)
end

function GuildScreen:_Toast(text: string, variant: string)
	local hud = self.ScreenController and self.ScreenController:GetScreen("hud")
	if hud then
		hud:PushToast({ text = text, variant = variant })
	end
end

function GuildScreen:_BuildContent()
	local theme = self:GetTheme()

	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = self:_R("GUILD"),
		sizePx = CARD,
		onClose = function()
			self.ScreenController:HideScreen("guild")
		end,
	})
	self._modal = modal
	local content = modal.content

	-- ---- header: crest, name, meta, XP ruler --------------------------

	local crest = UIStyler.Frame("Crest")
	crest.BackgroundColor3 = theme.Arcade.NearBlack
	crest.Position = UDim2.fromOffset(0, 4)
	crest.Size = UDim2.fromOffset(CREST, CREST)
	UIChrome.Stroke(theme, "Arcade").Parent = crest
	UIChrome.GlassGradient().Parent = crest
	crest.Parent = content

	local crown = IconArchive.Image(crest, "crown", 64, { golden = true })
	crown.AnchorPoint = Vector2.new(0.5, 0.5)
	crown.Position = UDim2.fromScale(0.5, 0.5)

	local name = UIChrome.Text("GuildName", 34, WHITE)
	name.RichText = false
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(CREST + 18, 4)
	name.Size = UDim2.fromOffset(620, 40)
	name.Parent = content
	self._nameLabel = name

	local meta = UIChrome.Text("Meta", 20, theme.Arcade.IceBlue)
	meta.TextXAlignment = Enum.TextXAlignment.Left
	meta.Position = UDim2.fromOffset(CREST + 18, 48)
	meta.Size = UDim2.fromOffset(620, 24)
	meta.Parent = content
	self._metaLabel = meta

	self._xpBar = UIProgressBarComponent.new()
	self._xpBar:Create(content, {
		value = 0,
		maxValue = 1,
		label = "GUILD XP",
		size = UDim2.fromOffset(420, 24),
		position = UDim2.fromOffset(CREST + 18, 80),
	})

	-- ---- tabs ---------------------------------------------------------

	for index, tab in TABS do
		local button = UIButtonComponent.new()
		button:Create(content, {
			text = tab.label,
			variant = if tab.id == self._tab then "Blue" else "Ghost",
			size = UDim2.fromOffset(TAB_W, TAB_H),
			position = UDim2.fromOffset((index - 1) * (TAB_W + 12), TABS_Y),
			onClick = function()
				self:_SetTab(tab.id)
			end,
		})
		self._tabButtons[tab.id] = button
	end

	-- ---- shared body well + one scroller per tab ----------------------

	local well = UIStyler.Frame("Well")
	well.BackgroundColor3 = theme.Arcade.NearBlack2
	well.BackgroundTransparency = 0
	well.Position = UDim2.fromOffset(0, WELL_Y)
	well.Size = UDim2.new(1, 0, 0, WELL_H)
	UIChrome.Stroke(theme, "Arcade").Parent = well
	UIChrome.GlassGradient().Parent = well
	well.Parent = content

	for _, tab in TABS do
		local scroll = Instance.new("ScrollingFrame")
		scroll.Name = "Body_" .. tab.id
		scroll.BackgroundTransparency = 1
		scroll.BorderSizePixel = 0
		scroll.Position = UDim2.fromOffset(10, 10)
		scroll.Size = UDim2.new(1, -20, 1, -20)
		scroll.CanvasSize = UDim2.new()
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.ScrollingDirection = Enum.ScrollingDirection.Y
		scroll.ScrollBarThickness = 6
		scroll.ScrollBarImageColor3 = theme.Arcade.Gold
		scroll.Visible = tab.id == self._tab
		scroll.Parent = well
		UIStyler.ListLayout({
			Padding = UDim.new(0, ROW_GAP),
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
		}).Parent = scroll
		self._tabBodies[tab.id] = scroll
	end

	-- ---- footer -------------------------------------------------------

	self._inviteButton = UIButtonComponent.new()
	self._inviteButton:Create(content, {
		text = self:_R("INVITE"),
		variant = "Green",
		iconId = IconArchive.Id("addFriend"),
		size = UDim2.fromOffset(240, FOOTER_H),
		position = UDim2.new(0, 0, 1, 0),
		anchorPoint = Vector2.new(0, 1),
		onClick = function()
			self:_Toast("GUILD INVITES SENT TO YOUR FRIENDS", "Success")
		end,
	})

	self._leaveButton = UIButtonComponent.new()
	self._leaveButton:Create(content, {
		text = self:_R("LEAVE GUILD"),
		variant = "Red",
		size = UDim2.fromOffset(240, FOOTER_H),
		position = UDim2.new(1, 0, 1, 0),
		anchorPoint = Vector2.new(1, 1),
		onClick = function()
			self:_ConfirmLeave()
		end,
	})

	self:_Render()
end

function GuildScreen:_SetTab(id: string)
	if self._tab == id then
		return
	end
	self._tab = id
	for tabId, body in self._tabBodies do
		body.Visible = tabId == id
	end
	-- SetContent re-reads the label from the props it is handed, so every call
	-- restates the text alongside the variant flip.
	for _, tab in TABS do
		self._tabButtons[tab.id]:SetContent({
			text = tab.label,
			variant = if tab.id == id then "Blue" else "Ghost",
		})
	end
	local body = self._tabBodies[id]
	if body then
		UIChrome.PopIn(self:GetTheme(), body)
	end
end

function GuildScreen:_RenderHeader()
	local data: GuildData = self._data
	self._nameLabel.Text = data.name
	self._metaLabel.Text = string.format("LEVEL %d  •  %d MEMBERS", data.level, #data.members)
	self._xpBar:Set(data.xp, math.max(data.xpMax, 1))
end

function GuildScreen:_ClearBody(id: string)
	local body = self._tabBodies[id]
	for _, child in body:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function GuildScreen:_RenderRoster()
	local theme = self:GetTheme()
	local data: GuildData = self._data
	self:_ClearBody("roster")

	for index, member in data.members do
		local row = UIStyler.Frame("Member_" .. member.name)
		row.BackgroundColor3 = if index % 2 == 1 then theme.Arcade.NearBlack2 else theme.Arcade.Row
		row.BackgroundTransparency = 0.15 -- doc §9 zebra rows
		row.Size = UDim2.new(1, -10, 0, ROSTER_ROW_H) -- 10px clear of the scrollbar
		row.LayoutOrder = index
		UIChrome.Stroke(theme, "Arcade").Parent = row
		UIChrome.GlassGradient().Parent = row
		row.Parent = self._tabBodies.roster

		local avatar = avatarCircle(theme, row, member.userId, 48)
		avatar.AnchorPoint = Vector2.new(0, 0.5)
		avatar.Position = UDim2.new(0, 12, 0.5, 0)

		local name = UIChrome.Text("Name", 22, WHITE)
		name.RichText = false
		name.Text = member.name
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.AnchorPoint = Vector2.new(0, 0.5)
		name.Position = UDim2.new(0, 74, 0.5, 0)
		name.Size = UDim2.fromOffset(330, 26)
		name.Parent = row

		-- Rank chip, colour-as-identity (doc §3.3): LEADER gold, OFFICER blue,
		-- MEMBER grey.
		local chipFill, chipText = rankColors(theme, member.rank)
		local chip = UIStyler.Frame("Rank")
		chip.BackgroundColor3 = chipFill
		chip.AnchorPoint = Vector2.new(0, 0.5)
		chip.Position = UDim2.new(0, 430, 0.5, 0)
		chip.Size = UDim2.fromOffset(110, 26)
		UIChrome.Stroke(theme, "Arcade").Parent = chip
		UIChrome.GlassGradient().Parent = chip
		chip.Parent = row

		local rank = UIChrome.Text("Label", 15, chipText)
		rank.Text = member.rank
		rank.Size = UDim2.fromScale(1, 1)
		rank.Parent = chip

		local contribution = UIChrome.Text("Contribution", 20, theme.Arcade.Gold)
		contribution.Text = formatNumber(member.contribution)
		contribution.TextXAlignment = Enum.TextXAlignment.Right
		contribution.AnchorPoint = Vector2.new(1, 0.5)
		contribution.Position = UDim2.new(1, -56, 0.5, 0)
		contribution.Size = UDim2.fromOffset(170, 24)
		contribution.Parent = row

		local dot = UIStyler.Frame("Online")
		dot.BackgroundColor3 = if member.online then theme.Arcade.MoneyGreen else theme.Arcade.GreyOwned
		dot.AnchorPoint = Vector2.new(1, 0.5)
		dot.Position = UDim2.new(1, -18, 0.5, 0)
		dot.Size = UDim2.fromOffset(16, 16)
		UIChrome.Corner("Arcade", "Pill").Parent = dot
		UIChrome.Stroke(theme, "Arcade").Parent = dot
		dot.Parent = row

		-- Whole-row hit target (doc §11.6).
		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Text = ""
		hit.BackgroundTransparency = 1
		hit.AutoButtonColor = false
		hit.Size = UDim2.fromScale(1, 1)
		hit.Parent = row
		hit.Activated:Connect(function()
			self:_Toast("VIEWING " .. string.upper(member.name) .. "'S PROFILE", "Info")
		end)
		UIChrome.Animate(theme, hit, row)
	end
end

function GuildScreen:_RenderPerks()
	local theme = self:GetTheme()
	local data: GuildData = self._data
	self:_ClearBody("perks")

	for index, perk in data.perks do
		local unlocked = perk.requires <= data.level

		local row = UIStyler.Frame("Perk_" .. index)
		row.BackgroundColor3 = if index % 2 == 1 then theme.Arcade.NearBlack2 else theme.Arcade.Row
		row.BackgroundTransparency = if unlocked then 0.15 else 0.5 -- locked dims in place (§11.2)
		row.Size = UDim2.new(1, -10, 0, PERK_ROW_H)
		row.LayoutOrder = index
		UIChrome.Stroke(theme, "Arcade").Parent = row
		UIChrome.GlassGradient().Parent = row
		row.Parent = self._tabBodies.perks

		local icon = IconArchive.Image(row, perk.icon or "star", 44, { golden = unlocked })
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 14, 0.5, 0)
		if not unlocked then
			dimIcon(icon, 0.5)
		end

		local name = UIChrome.Text("Name", 22, if unlocked then WHITE else theme.Arcade.GreyOwned)
		name.Text = perk.name
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Position = UDim2.fromOffset(74, 10)
		name.Size = UDim2.fromOffset(560, 26)
		name.Parent = row

		local desc = UIChrome.BodyText("Desc", 16, if unlocked then theme.Colors.TextSecondary else theme.Arcade.GreyOwned)
		desc.Text = perk.desc
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.TextTruncate = Enum.TextTruncate.AtEnd
		desc.Position = UDim2.fromOffset(74, 40)
		desc.Size = UDim2.fromOffset(560, 20)
		desc.Parent = row

		if unlocked then
			local active = UIChrome.Text("Active", 17, theme.Arcade.MoneyGreen)
			active.Text = "ACTIVE"
			active.TextXAlignment = Enum.TextXAlignment.Right
			active.AnchorPoint = Vector2.new(1, 0.5)
			active.Position = UDim2.new(1, -18, 0.5, 0)
			active.Size = UDim2.fromOffset(180, 24)
			active.Parent = row
		else
			local requirement = UIChrome.Text("Requires", 17, theme.Arcade.GreyOwned)
			requirement.Text = string.format("GUILD LV %d", perk.requires)
			requirement.TextXAlignment = Enum.TextXAlignment.Right
			requirement.AnchorPoint = Vector2.new(1, 0.5)
			requirement.Position = UDim2.new(1, -52, 0.5, 0)
			requirement.Size = UDim2.fromOffset(180, 24)
			requirement.Parent = row

			local lock = IconArchive.Image(row, "lock", 26)
			lock.AnchorPoint = Vector2.new(1, 0.5)
			lock.Position = UDim2.new(1, -16, 0.5, 0)
		end

		-- Every tap answers (§11.1): locked perks explain their gate.
		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Text = ""
		hit.BackgroundTransparency = 1
		hit.AutoButtonColor = false
		hit.Size = UDim2.fromScale(1, 1)
		hit.Parent = row
		hit.Activated:Connect(function()
			if unlocked then
				self:_Toast(perk.name .. " IS ACTIVE FOR THE WHOLE GUILD", "Info")
			else
				self:_Toast(string.format("REACH GUILD LEVEL %d TO UNLOCK %s", perk.requires, perk.name), "Error")
			end
		end)
		UIChrome.Animate(theme, hit, row)
	end
end

function GuildScreen:_RenderLog()
	local theme = self:GetTheme()
	local data: GuildData = self._data
	self:_ClearBody("log")

	-- Newest first: smallest "ago" sorts to the top.
	local entries = table.clone(data.log)
	table.sort(entries, function(a: LogEntry, b: LogEntry): boolean
		return a.ago < b.ago
	end)

	for index, entry in entries do
		local row = UIStyler.Frame("Log_" .. index)
		row.BackgroundColor3 = if index % 2 == 1 then theme.Arcade.NearBlack2 else theme.Arcade.Row
		row.BackgroundTransparency = 0.15
		row.Size = UDim2.new(1, -10, 0, LOG_ROW_H)
		row.LayoutOrder = index
		UIChrome.Stroke(theme, "Arcade").Parent = row
		UIChrome.GlassGradient().Parent = row
		row.Parent = self._tabBodies.log

		local icon = IconArchive.Image(row, entry.icon or "bell", 28)
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 12, 0.5, 0)

		local text = UIChrome.Text("Text", 18, WHITE)
		text.RichText = false
		text.Text = entry.text
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.TextTruncate = Enum.TextTruncate.AtEnd
		text.AnchorPoint = Vector2.new(0, 0.5)
		text.Position = UDim2.new(0, 52, 0.5, 0)
		text.Size = UDim2.new(1, -52 - 140, 0, 24)
		text.Parent = row

		local when = UIChrome.Text("When", 15, theme.Arcade.IceBlue)
		when.Text = agoText(entry.ago)
		when.TextXAlignment = Enum.TextXAlignment.Right
		when.AnchorPoint = Vector2.new(1, 0.5)
		when.Position = UDim2.new(1, -14, 0.5, 0)
		when.Size = UDim2.fromOffset(120, 22)
		when.Parent = row
	end
end

function GuildScreen:_Render()
	self:_RenderHeader()
	self:_RenderRoster()
	self:_RenderPerks()
	self:_RenderLog()
end

function GuildScreen:_ConfirmLeave()
	local data: GuildData = self._data
	self.ScreenController:ShowModal({
		kind = "Danger",
		title = self:_R("LEAVE GUILD"),
		body = string.format("Leave %s? Your contribution stays behind and re-joining needs a fresh invite.", data.name),
		confirmKey = "LEAVE",
		cancelKey = "STAY",
		onConfirm = function()
			self:_Toast("YOU LEFT " .. data.name, "Warning")
			self.ScreenController:HideScreen("guild")
		end,
	})
end

function GuildScreen:_Ingest(data: any?)
	if not data then
		return
	end
	local current: GuildData = self._data
	self._data = {
		name = data.name or current.name,
		level = data.level or current.level,
		xp = data.xp or current.xp,
		xpMax = data.xpMax or current.xpMax,
		members = data.members or current.members,
		perks = data.perks or current.perks,
		log = data.log or current.log,
	}
end

function GuildScreen:_OnShow(data: any?)
	if data then
		self:_Ingest(data)
		self:_Render()
	end
	if self._modal then
		UIChrome.PopIn(self:GetTheme(), self._modal.content)
	end
end

function GuildScreen:Update(data: any)
	self:_Ingest(data)
	if self._built then
		self:_Render()
	end
end

function GuildScreen:Destroy()
	if self._xpBar then
		self._xpBar:Destroy()
		self._xpBar = nil
	end
	for _, button in self._tabButtons do
		button:Destroy()
	end
	table.clear(self._tabButtons)
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

return GuildScreen
