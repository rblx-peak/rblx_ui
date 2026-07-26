--!strict
-- Pre-match LOBBY — Pottery Clash arcade family (doc §7.4). One modal card:
-- the LEFT half is the 8-player slot grid (filled = avatar + name + a ready
-- light: green check / grey hourglass; empty = a dashed gold "+ INVITE" tile),
-- the RIGHT half is the match settings well (mode name, the 3-tile map-vote
-- strip, and — host only — a mode dropdown + a gold START MATCH that dims in
-- place until enough players are ready, §11.2). The bottom row carries the big
-- READY toggle (green "READY UP" flips to grey "UNREADY") and a red LEAVE.
--
-- Voting is selection-is-a-ring (doc §4.3): your map wears the gold ring; a
-- vote click moves your vote, re-renders the counts and pulses the new tile.
-- The optional auto-start countdown ticks at 1Hz in gold (doc §11.3) on ONE
-- RenderStepped connection gated on UIChrome.IsOnScreen (§5.4).
--
-- Show(data) = { isHost, minReady, players, maps, mode, autoStartIn }.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UIDropdownComponent = require(script.Parent.Parent.Components.UIDropdownComponent)

type LobbyPlayer = { userId: number, name: string, ready: boolean?, host: boolean?, you: boolean? }
type MapOption = { id: string, name: string, icon: string?, votes: number }
type LobbyData = {
	isHost: boolean,
	minReady: number,
	players: { LobbyPlayer },
	maps: { MapOption },
	mode: string,
	autoStartIn: number?,
}

local WHITE = Color3.new(1, 1, 1)

-- Fixed px at the 1650×1020 baseline. Card 1360×760 → content 1332×672.
local CARD = Vector2.new(1360, 760)
local CONTENT_H = 672
local SLOT_COUNT = 8
local SLOT_W = 330
local SLOT_H = 118
local SLOT_GAP = 12
local GRID_Y = 40
local RIGHT_X = 700
local SETTINGS_W = 632
local SETTINGS_H = 430
local TILE_W = 194
local TILE_H = 150
local BOTTOM_H = 62

-- Dashed empty-slot outline (an invitation, not a disabled tile): the arcade
-- has no dashed UIStroke, so the dashes are drawn at a fixed px size.
local DASH_LEN = 12
local DASH_GAP = 8
local DASH_THICK = 3

local MODE_OPTIONS = {
	{ id = "CLASSIC", text = "CLASSIC" },
	{ id = "BLITZ", text = "BLITZ" },
	{ id = "TEAM CLASH", text = "TEAM CLASH" },
}

local function demoData(): LobbyData
	return {
		isHost = true,
		minReady = 4,
		players = {
			{ userId = 1, name = "ClayCrusher", ready = true, host = true, you = true },
			{ userId = 156, name = "KilnKing", ready = true },
			{ userId = 2, name = "GlazeGoblin", ready = false },
			{ userId = 3, name = "WheelWitch", ready = true },
			{ userId = 1101, name = "MugMerchant", ready = false },
		},
		maps = {
			{ id = "kiln", name = "THE KILN", icon = "fire", votes = 3 },
			{ id = "gardens", name = "GLAZE GARDENS", icon = "leaf", votes = 1 },
			{ id = "quarry", name = "CLAY QUARRY", icon = "pickaxe", votes = 2 },
		},
		mode = "CLASSIC",
		autoStartIn = 45,
	}
end

local function tintIcon(icon: GuiObject, color: Color3)
	if icon:IsA("ImageLabel") then
		icon.ImageColor3 = color
	elseif icon:IsA("TextLabel") then
		icon.TextColor3 = color
	end
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

local LobbyScreen = setmetatable({}, { __index = UIScreenBase })
LobbyScreen.__index = LobbyScreen

function LobbyScreen.new()
	local self = UIScreenBase.new("LobbyScreen", 9)
	self._data = demoData() :: LobbyData
	self._myVote = nil :: string?
	self._mapTiles = {} :: { [string]: Frame }
	self._tickConn = nil :: RBXScriptConnection?
	self._accum = 0
	return setmetatable(self, LobbyScreen)
end

function LobbyScreen:_Toast(text: string, variant: string)
	local hud = self.ScreenController and self.ScreenController:GetScreen("hud")
	if hud then
		hud:PushToast({ text = text, variant = variant })
	end
end

function LobbyScreen:_You(): LobbyPlayer?
	for _, player in self._data.players do
		if player.you then
			return player
		end
	end
	return self._data.players[1]
end

function LobbyScreen:_ReadyCount(): number
	local n = 0
	for _, player in self._data.players do
		if player.ready then
			n += 1
		end
	end
	return n
end

function LobbyScreen:_BuildContent()
	local theme = self:GetTheme()

	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = self:_R("LOBBY"),
		sizePx = CARD,
		onClose = function()
			self.ScreenController:HideScreen("lobby")
		end,
	})
	self._modal = modal
	local content = modal.content

	-- ---- left: player slot grid ---------------------------------------

	local playersTitle = UIChrome.Text("PlayersTitle", 24, theme.Arcade.Gold)
	playersTitle.TextXAlignment = Enum.TextXAlignment.Left
	playersTitle.Position = UDim2.fromOffset(0, 2)
	playersTitle.Size = UDim2.fromOffset(400, 28)
	playersTitle.Parent = content
	self._playersTitle = playersTitle

	-- Auto-start countdown (doc §11.3): 1Hz, gold FredokaOne.
	local countdown = UIChrome.Text("AutoStart", 22, theme.Arcade.SunburstGold)
	countdown.TextXAlignment = Enum.TextXAlignment.Right
	countdown.AnchorPoint = Vector2.new(1, 0)
	countdown.Position = UDim2.new(1, 0, 0, 2)
	countdown.Size = UDim2.fromOffset(380, 28)
	countdown.Visible = false
	countdown.Parent = content
	self._countdownLabel = countdown

	local grid = UIStyler.Frame("Slots")
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.fromOffset(0, GRID_Y)
	grid.Size = UDim2.fromOffset(SLOT_W * 2 + SLOT_GAP, (SLOT_H + SLOT_GAP) * 4 - SLOT_GAP)
	grid.Parent = content
	self._grid = grid

	-- ---- right: match settings well -----------------------------------

	local settings = UIStyler.Frame("Settings")
	settings.BackgroundColor3 = theme.Arcade.NearBlack2
	settings.BackgroundTransparency = 0
	settings.Position = UDim2.fromOffset(RIGHT_X, GRID_Y)
	settings.Size = UDim2.fromOffset(SETTINGS_W, SETTINGS_H)
	UIChrome.Stroke(theme, "Arcade").Parent = settings
	UIChrome.GlassGradient().Parent = settings
	settings.Parent = content

	local settingsTitle = UIChrome.Text("Title", 24, theme.Arcade.Gold)
	settingsTitle.Text = "MATCH SETTINGS"
	settingsTitle.TextXAlignment = Enum.TextXAlignment.Left
	settingsTitle.Position = UDim2.fromOffset(14, 10)
	settingsTitle.Size = UDim2.fromOffset(400, 28)
	settingsTitle.Parent = settings

	local mode = UIChrome.Text("Mode", 30, WHITE)
	mode.TextXAlignment = Enum.TextXAlignment.Left
	mode.Position = UDim2.fromOffset(14, 44)
	mode.Size = UDim2.fromOffset(SETTINGS_W - 28, 36)
	mode.Parent = settings
	self._modeLabel = mode

	local voteTitle = UIChrome.Text("VoteTitle", 18, theme.Arcade.IceBlue)
	voteTitle.Text = "MAP VOTE"
	voteTitle.TextXAlignment = Enum.TextXAlignment.Left
	voteTitle.Position = UDim2.fromOffset(14, 96)
	voteTitle.Size = UDim2.fromOffset(300, 22)
	voteTitle.Parent = settings

	local voteStrip = UIStyler.Frame("VoteStrip")
	voteStrip.BackgroundTransparency = 1
	voteStrip.Position = UDim2.fromOffset(14, 124)
	voteStrip.Size = UDim2.fromOffset(SETTINGS_W - 28, TILE_H)
	voteStrip.Parent = settings
	self._voteStrip = voteStrip

	-- Host controls: the mode dropdown + START MATCH. Built once, visibility
	-- follows isHost; non-hosts get the host line instead.
	self._modeDropdown = UIDropdownComponent.new()
	self._modeDropdown:Create(settings, {
		label = "MODE",
		options = MODE_OPTIONS,
		value = self._data.mode,
		size = UDim2.fromOffset(SETTINGS_W - 28, 40),
		position = UDim2.fromOffset(14, 296),
		onChanged = function(id: string)
			self._data.mode = id
			self._modeLabel.Text = id
			self:_Toast("MODE CHANGED TO " .. id, "Info")
		end,
	})
	-- The open option list must draw above the START button below it.
	self._modeDropdown.Root.ZIndex = 5

	local hostLine = UIChrome.BodyText("HostLine", 18, theme.Colors.TextSecondary)
	hostLine.TextXAlignment = Enum.TextXAlignment.Left
	hostLine.Position = UDim2.fromOffset(14, 304)
	hostLine.Size = UDim2.fromOffset(SETTINGS_W - 28, 24)
	hostLine.Visible = false
	hostLine.Parent = settings
	self._hostLine = hostLine

	self._startButton = UIButtonComponent.new()
	self._startButton:Create(settings, {
		text = "START MATCH",
		variant = "Gold",
		size = UDim2.fromOffset(SETTINGS_W - 28, 58),
		position = UDim2.fromOffset(14, 356),
		onClick = function()
			self:_TryStart()
		end,
	})

	-- ---- bottom row: READY toggle + LEAVE -----------------------------

	self._readyButton = UIButtonComponent.new()
	self._readyButton:Create(content, {
		text = "READY UP",
		variant = "Green",
		size = UDim2.fromOffset(360, BOTTOM_H),
		position = UDim2.new(0.5, 0, 1, 0),
		anchorPoint = Vector2.new(0.5, 1),
		onClick = function()
			self:_ToggleReady()
		end,
	})

	self._leaveButton = UIButtonComponent.new()
	self._leaveButton:Create(content, {
		text = self:_R("LEAVE"),
		variant = "Red",
		size = UDim2.fromOffset(180, BOTTOM_H),
		position = UDim2.new(1, 0, 1, 0),
		anchorPoint = Vector2.new(1, 1),
		onClick = function()
			self:_Toast("YOU LEFT THE LOBBY", "Warning")
			self.ScreenController:HideScreen("lobby")
		end,
	})

	self:_Render()
end

function LobbyScreen:_BuildSlot(player: LobbyPlayer?, index: number)
	local theme = self:GetTheme()
	local column = (index - 1) % 2
	local row = (index - 1) // 2

	local slot = UIStyler.Frame("Slot" .. index)
	slot.Position = UDim2.fromOffset(column * (SLOT_W + SLOT_GAP), row * (SLOT_H + SLOT_GAP))
	slot.Size = UDim2.fromOffset(SLOT_W, SLOT_H)
	slot.Parent = self._grid

	if not player then
		slot.BackgroundColor3 = theme.Arcade.NearBlack
		slot.BackgroundTransparency = 0.55
		dashedOutline(slot, SLOT_W, SLOT_H, theme.Arcade.Gold)

		local label = UIChrome.Text("Invite", 22, theme.Arcade.Gold)
		label.Text = "+ INVITE"
		label.Size = UDim2.fromScale(1, 1)
		label.Parent = slot

		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Text = ""
		hit.BackgroundTransparency = 1
		hit.AutoButtonColor = false
		hit.Size = UDim2.fromScale(1, 1)
		hit.Parent = slot
		hit.Activated:Connect(function()
			self:_Toast("LOBBY INVITES SENT TO YOUR FRIENDS", "Success")
		end)
		UIChrome.Animate(theme, hit, slot)
		return
	end

	slot.BackgroundColor3 = theme.Arcade.Row
	slot.BackgroundTransparency = 0.15
	UIChrome.Stroke(theme, "Arcade").Parent = slot
	UIChrome.GlassGradient().Parent = slot

	local avatar = avatarCircle(theme, slot, player.userId, 56)
	avatar.AnchorPoint = Vector2.new(0, 0.5)
	avatar.Position = UDim2.new(0, 14, 0.5, 0)

	if player.host then
		local crown = IconArchive.Image(slot, "crown", 26, { golden = true })
		crown.Position = UDim2.fromOffset(4, 4)
		crown.ZIndex = 3
	end

	local name = UIChrome.Text("Name", 20, WHITE)
	name.RichText = false
	name.Text = if player.you then player.name .. " (YOU)" else player.name -- §11.4 local player first
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(86, 26)
	name.Size = UDim2.fromOffset(SLOT_W - 86 - 72, 24)
	name.Parent = slot

	local ready = player.ready == true
	local status = UIChrome.Text("Status", 15, if ready then theme.Arcade.MoneyGreen else theme.Arcade.GreyOwned)
	status.Text = if ready then "READY" else "NOT READY"
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Position = UDim2.fromOffset(86, 56)
	status.Size = UDim2.fromOffset(SLOT_W - 86 - 72, 20)
	status.Parent = slot

	-- The ready state light: green check / grey hourglass in a round well.
	local light = UIStyler.Frame("Light")
	light.BackgroundColor3 = theme.Arcade.NearBlack
	light.AnchorPoint = Vector2.new(1, 0.5)
	light.Position = UDim2.new(1, -14, 0.5, 0)
	light.Size = UDim2.fromOffset(44, 44)
	UIChrome.Corner("Arcade", "Pill").Parent = light
	UIChrome.Stroke(theme, "Arcade").Parent = light
	light.Parent = slot

	local stateIcon = IconArchive.Image(light, if ready then "check" else "hourglass", if ready then 26 else 24)
	stateIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	stateIcon.Position = UDim2.fromScale(0.5, 0.5)
	tintIcon(stateIcon, if ready then theme.Arcade.MoneyGreen else theme.Arcade.GreyOwned)
end

function LobbyScreen:_BuildMapTile(map: MapOption, index: number)
	local theme = self:GetTheme()
	local mine = self._myVote == map.id

	local tile = UIStyler.Frame("Map_" .. map.id)
	tile.BackgroundColor3 = theme.Arcade.NearBlack
	tile.BackgroundTransparency = 0
	tile.Position = UDim2.fromOffset((index - 1) * (TILE_W + 11), 0)
	tile.Size = UDim2.fromOffset(TILE_W, TILE_H)
	-- Selection is a ring (doc §4.3): your vote wears gold, others the panel rim.
	UIChrome.Stroke(theme, "Arcade", if mine then "Selection" else "Panel").Parent = tile
	UIChrome.GlassGradient().Parent = tile
	tile.Parent = self._voteStrip
	self._mapTiles[map.id] = tile

	local icon = IconArchive.Image(tile, map.icon or "compass", 56)
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 14)

	local name = UIChrome.Text("Name", 16, if mine then theme.Semantic.Selection else WHITE)
	name.RichText = false
	name.Text = map.name
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(4, 78)
	name.Size = UDim2.fromOffset(TILE_W - 8, 22)
	name.Parent = tile

	local votes = UIChrome.Text("Votes", 16, theme.Arcade.Gold)
	votes.Text = string.format("%d VOTES", map.votes)
	votes.Position = UDim2.fromOffset(4, 106)
	votes.Size = UDim2.fromOffset(TILE_W - 8, 22)
	votes.Parent = tile

	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Size = UDim2.fromScale(1, 1)
	hit.Parent = tile
	hit.Activated:Connect(function()
		self:_Vote(map.id)
	end)
	UIChrome.Animate(theme, hit, tile)
end

function LobbyScreen:_Vote(mapId: string)
	if self._myVote == mapId then
		self:_Toast("YOUR VOTE IS ALREADY ON THIS MAP", "Info")
		return
	end
	local target: MapOption? = nil
	for _, map in self._data.maps do
		if map.id == self._myVote then
			map.votes = math.max(0, map.votes - 1)
		end
		if map.id == mapId then
			target = map
		end
	end
	if not target then
		return
	end
	target.votes += 1
	self._myVote = mapId
	self:_RenderVotes()
	local tile = self._mapTiles[mapId]
	if tile then
		UIChrome.Pulse(self:GetTheme(), tile)
	end
	self:_Toast("VOTED FOR " .. target.name, "Success")
end

function LobbyScreen:_RenderSlots()
	for _, child in self._grid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for index = 1, SLOT_COUNT do
		self:_BuildSlot(self._data.players[index], index)
	end
	self._playersTitle.Text = string.format("PLAYERS %d/%d  •  %d READY", #self._data.players, SLOT_COUNT, self:_ReadyCount())
end

function LobbyScreen:_RenderVotes()
	table.clear(self._mapTiles)
	for _, child in self._voteStrip:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for index, map in self._data.maps do
		self:_BuildMapTile(map, index)
	end
end

function LobbyScreen:_RenderControls()
	local data: LobbyData = self._data
	self._modeLabel.Text = data.mode

	self._modeDropdown.Root.Visible = data.isHost
	self._startButton.Root.Visible = data.isHost
	self._hostLine.Visible = not data.isHost
	if not data.isHost then
		local hostName = "?"
		for _, player in data.players do
			if player.host then
				hostName = player.name
			end
		end
		self._hostLine.Text = "HOST: " .. hostName .. " picks the mode"
	end

	-- START dims in place until minReady (§11.2); the tap still answers.
	local enough = self:_ReadyCount() >= data.minReady
	self._startButton:SetContent({ text = "START MATCH", variant = "Gold", dimmed = not enough })

	local you = self:_You()
	local ready = you ~= nil and you.ready == true
	self._readyButton:SetContent({
		text = if ready then "UNREADY" else "READY UP",
		variant = if ready then "Grey" else "Green",
	})

	self._countdownLabel.Visible = self._data.autoStartIn ~= nil
	if self._data.autoStartIn then
		self._countdownLabel.Text = "AUTO-START IN " .. UIChrome.FormatCountdown(self._data.autoStartIn)
	end
end

function LobbyScreen:_Render()
	self:_RenderSlots()
	self:_RenderVotes()
	self:_RenderControls()
end

function LobbyScreen:_ToggleReady()
	local you = self:_You()
	if not you then
		return
	end
	you.ready = not you.ready
	self:_RenderSlots()
	self:_RenderControls()
	if you.ready then
		self:_Toast("YOU ARE READY", "Success")
	else
		self:_Toast("READY CANCELLED", "Info")
	end
end

function LobbyScreen:_TryStart()
	local data: LobbyData = self._data
	local ready = self:_ReadyCount()
	if ready < data.minReady then
		self:_Toast(string.format("NEED %d READY PLAYERS TO START (%d/%d)", data.minReady, ready, data.minReady), "Error")
		return
	end
	self:_Toast("MATCH STARTING — GOOD LUCK!", "Success")
end

-- ONE 1Hz ticker for the auto-start countdown (doc §5.4 frugality).
function LobbyScreen:_StartTicker()
	if self._tickConn then
		return
	end
	self._accum = 0
	self._tickConn = RunService.RenderStepped:Connect(function(dt: number)
		local card = self._modal and self._modal.card
		if not card or not UIChrome.IsOnScreen(card) then
			return
		end
		self._accum += dt
		if self._accum < 1 then
			return
		end
		self._accum -= 1
		local remaining = self._data.autoStartIn
		if not remaining then
			return
		end
		remaining = math.max(0, remaining - 1)
		self._data.autoStartIn = remaining
		self._countdownLabel.Text = "AUTO-START IN " .. UIChrome.FormatCountdown(remaining)
		if remaining == 0 then
			self._data.autoStartIn = nil
			self._countdownLabel.Visible = false
			self:_Toast("MATCH STARTING…", "Success")
		end
	end)
end

function LobbyScreen:_StopTicker()
	if self._tickConn then
		self._tickConn:Disconnect()
		self._tickConn = nil
	end
end

function LobbyScreen:_Ingest(data: any?)
	if not data then
		return
	end
	local current: LobbyData = self._data
	self._data = {
		isHost = if data.isHost ~= nil then data.isHost else current.isHost,
		minReady = data.minReady or current.minReady,
		players = data.players or current.players,
		maps = data.maps or current.maps,
		mode = data.mode or current.mode,
		autoStartIn = if data.autoStartIn ~= nil then data.autoStartIn else current.autoStartIn,
	}
	if data.maps then
		self._myVote = nil -- a fresh map set invalidates the old vote
	end
	if data.mode and self._modeDropdown then
		self._modeDropdown:Set(data.mode)
	end
end

function LobbyScreen:_OnShow(data: any?)
	if data then
		self:_Ingest(data)
		self:_Render()
	end
	self:_StartTicker()
	if self._modal then
		UIChrome.PopIn(self:GetTheme(), self._modal.content)
	end
end

function LobbyScreen:_OnHide()
	self:_StopTicker()
end

function LobbyScreen:Update(data: any)
	self:_Ingest(data)
	if self._built then
		self:_Render()
	end
end

function LobbyScreen:Destroy()
	self:_StopTicker()
	if self._modeDropdown then
		self._modeDropdown:Destroy()
		self._modeDropdown = nil
	end
	if self._startButton then
		self._startButton:Destroy()
		self._startButton = nil
	end
	if self._readyButton then
		self._readyButton:Destroy()
		self._readyButton = nil
	end
	if self._leaveButton then
		self._leaveButton:Destroy()
		self._leaveButton = nil
	end
	UIScreenBase.Destroy(self)
end

return LobbyScreen
