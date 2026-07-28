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
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local GPMatchFlow = require(script.Parent.Parent.Framework.GPMatchFlow)

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

-- GP layout (theme.LayoutKit == "GP") fixed px. GPLayoutKit.Page's content well
-- comes out 1332 wide at this card width — EXACTLY the arcade card's — so the
-- slot grid and the settings well keep their footprints and their column
-- arithmetic. The 80 extra px of card height pay for the pack's chrome (petal
-- corners, hue shadows, the header's scalloped lip); the grid, the vote strip
-- and the settings well all grow, and nothing is dropped.
local GP_CARD = Vector2.new(1360, 840)
local GP_GRID_Y = 44
local GP_SLOT_W = 330
local GP_SLOT_H = 118
local GP_SLOT_GAP = 14
local GP_RIGHT_X = 700
local GP_SETTINGS_W = 620
local GP_SETTINGS_H = 470
local GP_TILE_W = 188
local GP_TILE_H = 160
local GP_TILE_GAP = 12
-- GPLayoutKit.Page CLIPS its content field, so everything that casts a
-- hue-matched shadow rides an inset field — otherwise a card's soft edge is
-- sliced dead straight at the clip boundary. 700 + 620 lands exactly on the
-- inset field's right edge (1332 - 12).
local GP_FIELD_INSET = 6
local GP_BOTTOM_H = 62
local GP_COUNTDOWN = Vector2.new(300, 40)

-- Three render paths write these lines, and all three are SHARED between the
-- layouts, so the phrasing is what differs — not the logic. Classic keeps its
-- exact strings (bullet and all); only the GP build reassigns the table.
local CLASSIC_COPY = {
	playersTitle = "PLAYERS %d/%d  •  %d READY",
	hostLine = "HOST: %s picks the mode",
	autoStart = "AUTO-START IN %s",
	ready = "READY",
	notReady = "NOT READY",
	votes = "%d VOTES",
	-- The mode id IS the arcade caption ("TEAM CLASH"); GP re-cases it for
	-- display only, so the id written back to _data.mode is untouched.
	modeName = function(id: string): string
		return id
	end,
}

local GP_COPY = {
	playersTitle = "Potters %d/%d  ·  %d ready",
	hostLine = "%s is hosting and picks the mode",
	autoStart = "Wheels start in %s",
	ready = "Ready",
	notReady = "Not ready",
	votes = "%d votes",
	modeName = GPMatchFlow.SoftCase,
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

-- `cornerPx` holds each dash run clear of a ROUNDED corner: where a petal
-- radius has eaten the fill there is nothing under the dash, and a dash drawn
-- into that void floats off the tile. Omitted (the arcade's square slot) the
-- geometry is unchanged.
local function dashedOutline(parent: Instance, widthPx: number, heightPx: number, color: Color3, cornerPx: number?)
	local pitch = DASH_LEN + DASH_GAP
	local corner = cornerPx or 0
	local function edge(horizontal: boolean, atStart: boolean)
		local span = (if horizontal then widthPx else heightPx) - corner * 2
		local count = math.max(1, math.floor(span / pitch))
		local lead = corner + (span - (count * pitch - DASH_GAP)) / 2
		for i = 0, count - 1 do
			local dash = UIStyler.Frame("Dash")
			dash.BackgroundColor3 = color
			dash.BackgroundTransparency = 0.3
			if horizontal then
				dash.Size = UDim2.fromOffset(DASH_LEN, DASH_THICK)
				dash.Position = UDim2.fromOffset(lead + i * pitch, if atStart then 0 else heightPx - DASH_THICK)
			else
				dash.Size = UDim2.fromOffset(DASH_THICK, DASH_LEN)
				dash.Position = UDim2.fromOffset(if atStart then 0 else widthPx - DASH_THICK, lead + i * pitch)
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
	-- Layout-neutral phrasing, overridden only by the GP build.
	self._copy = CLASSIC_COPY
	-- Three GP shadow sinks, by LIFETIME: the page and its furniture are built
	-- once, while slots and map tiles are destroyed and rebuilt on every render
	-- (a ready toggle re-renders the whole grid) and must hand their budget back
	-- each time. Nil under every other layout, where ReleaseShadows is a no-op.
	self._gpShadows = nil :: { any }?
	self._gpSlotShadows = nil :: { any }?
	self._gpTileShadows = nil :: { any }?
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
	-- GP layout language: cutesy pastel ceramics — a petal page, hue-matched
	-- shadows and the studio's warm voice. See _BuildGPLayout below.
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end

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
	if self:LayoutKit() == "GP" then
		self:_BuildGPSlot(player, index)
		return
	end

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
	status.Text = if ready then self._copy.ready else self._copy.notReady
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
	if self:LayoutKit() == "GP" then
		self:_BuildGPMapTile(map, index)
		return
	end

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
	votes.Text = string.format(self._copy.votes, map.votes)
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
	-- The slots churn on every render, so their shadow budget comes back BEFORE
	-- the rebuild (no-op on every layout but GP, which is the only one that
	-- fills the sink).
	GPLayoutKit.ReleaseShadows(self._gpSlotShadows)
	for _, child in self._grid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for index = 1, SLOT_COUNT do
		self:_BuildSlot(self._data.players[index], index)
	end
	self._playersTitle.Text = string.format(self._copy.playersTitle, #self._data.players, SLOT_COUNT, self:_ReadyCount())
end

function LobbyScreen:_RenderVotes()
	GPLayoutKit.ReleaseShadows(self._gpTileShadows)
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
	self._modeLabel.Text = self._copy.modeName(data.mode)

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
		self._hostLine.Text = string.format(self._copy.hostLine, hostName)
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
		self._countdownLabel.Text = string.format(self._copy.autoStart, UIChrome.FormatCountdown(self._data.autoStartIn))
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
		self._countdownLabel.Text = string.format(self._copy.autoStart, UIChrome.FormatCountdown(remaining))
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

-- ========================================================================
-- GP layout — the STUDIO waiting room (theme.LayoutKit == "GP").
--
-- Every part of the arcade lobby, in the pack's language and at the same
-- density: the 8-slot grid keeps all eight slots and every line inside them
-- (avatar, crown, name, ready caption, ready light), the settings well keeps
-- the mode line, the 3-tile map vote WITH its vote counts, the host's mode
-- picker and the START action, and the bottom row keeps the ready toggle and
-- leave. The auto-start countdown moves into the page header's counter slot,
-- where the kit already reserves room for exactly this.
--
-- Two substitutions, both forced by pack law 1 rather than taste:
--   * UIButtonComponent paints a SOLID button, which UIStyleEnforcer then
--     strokes BLACK — so actions are GPMatchFlow.Button chips instead, with
--     the identical Root / SetContent / Destroy surface;
--   * UIDropdownComponent is the same story, so the host's mode control
--     becomes a row of petal chips exposing the same Root / Set / Destroy.
-- Both keep the EXACT callbacks, toasts and state flow of the classic build.
-- ========================================================================

-- The host's mode control. Three chips beat a dropdown here: the option set is
-- fixed and tiny, and a chip row shows every choice at once instead of hiding
-- two behind a click. Same surface as UIDropdownComponent (Root/Set/Destroy).
function LobbyScreen:_BuildGPModePicker(parent: Instance, position: UDim2, width: number, onChanged: (string) -> ()): any
	local theme = self:GetTheme()
	local spacing = theme.Spacing

	local row = UIStyler.Frame("ModePicker")
	row.BackgroundTransparency = 1
	row.Position = position
	row.Size = UDim2.fromOffset(width, 48)
	row.ZIndex = 5
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, spacing.S),
	}).Parent = row
	row.Parent = parent

	local chipW = math.floor((width - spacing.S * (#MODE_OPTIONS - 1)) / #MODE_OPTIONS)
	local entries: { [string]: any } = {}

	local function select(id: string)
		for optionId, entry in entries do
			local on = optionId == id
			local fill = if on then theme.Colors.Primary else theme.Colors.Surface
			entry.chip.BackgroundColor3 = fill
			entry.stroke.Color = GPLayoutKit.Deepen(theme, fill, 1)
			-- Body copy on rose is TextPrimary (5.15:1); the near-white is not
			-- legal at this size on any of the pack's pastels.
			entry.label.TextColor3 = if on then theme.Colors.TextPrimary else theme.Colors.TextSecondary
			entry.underline.Visible = on
		end
	end

	for index, option in MODE_OPTIONS do
		local button = Instance.new("TextButton")
		button.Name = "Mode_" .. option.id
		button.BackgroundTransparency = 1 -- solid buttons get a black backstop stroke
		button.Text = ""
		button.AutoButtonColor = false
		button.Size = UDim2.fromOffset(chipW, 44)
		button.LayoutOrder = index
		button.ZIndex = 5
		button.Parent = row

		local idleFill = theme.Colors.Surface
		local chip = GPMatchFlow.Fill("Chip", idleFill)
		chip.Size = UDim2.fromScale(1, 1)
		chip.ZIndex = 5
		chip.Parent = button
		GPLayoutKit.CornerSet(theme, chip, "Tab")
		local stroke = GPLayoutKit.SoftStroke(theme, chip, idleFill)

		local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Button, theme.Colors.TextSecondary, "Label")
		label.Text = GPMatchFlow.SoftCase(option.text)
		label.Size = UDim2.fromScale(1, 1)
		label.ZIndex = 6
		label.Parent = chip

		local underline = GPMatchFlow.Fill("Underline", theme.Colors.Accent)
		underline.AnchorPoint = Vector2.new(0.5, 1)
		underline.Position = UDim2.new(0.5, 0, 1, -6)
		underline.Size = UDim2.new(0.56, 0, 0, 4)
		underline.Visible = false
		underline.ZIndex = 7
		underline.Parent = chip
		UIStyler.Corner(theme.Radii.Pill).Parent = underline

		button.Activated:Connect(function()
			select(option.id)
			onChanged(option.id)
		end)
		UIChrome.Animate(theme, button, chip)
		entries[option.id] = { chip = chip, stroke = stroke, label = label, underline = underline }
	end

	return {
		Root = row,
		Set = function(_, id: string)
			select(id)
		end,
		Destroy = function()
			row:Destroy()
		end,
	}
end

function LobbyScreen:_BuildGPLayout()
	local theme = self:GetTheme()
	local spacing = theme.Spacing
	self._copy = GP_COPY
	self._gpSlotShadows = {}
	self._gpTileShadows = {}

	local page = GPLayoutKit.Page(theme, self.Root, {
		titleText = "The Studio",
		subtitleText = "Everyone gets a wheel",
		sizePx = GP_CARD,
		onClose = function()
			self.ScreenController:HideScreen("lobby")
		end,
	})
	-- The page owns a sink; adopt it as THE page-lifetime sink.
	local shadows = page.shadows
	self._gpShadows = shadows
	-- _OnShow pops .content and the 1Hz ticker gates on .card being on screen.
	self._modal = { content = page.content, card = page.panel } :: any

	-- Everything below rides an inset field, not the clipped content frame
	-- itself; see GP_FIELD_INSET.
	local content = UIStyler.Frame("Field")
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(GP_FIELD_INSET, GP_FIELD_INSET)
	content.Size = UDim2.new(1, -GP_FIELD_INSET * 2, 1, -GP_FIELD_INSET)
	content.ZIndex = 3
	content.Parent = page.content

	-- ---- left: the potters' grid ---------------------------------------

	local playersTitle = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle + 4, theme.Colors.TextPrimary, "PlayersTitle")
	playersTitle.TextXAlignment = Enum.TextXAlignment.Left
	playersTitle.Position = UDim2.fromOffset(0, 2)
	playersTitle.Size = UDim2.fromOffset(460, 30)
	playersTitle.ZIndex = 4
	playersTitle.Parent = content
	self._playersTitle = playersTitle

	-- The auto-start countdown rides the header's counter slot (the kit
	-- reserves it for exactly this). The LABEL is the pill, so the shared
	-- `Visible = autoStartIn ~= nil` toggle hides the whole chip, not its text.
	local countdownFill = theme.Arcade.Gold
	local countdown = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "AutoStart")
	countdown.FontFace = theme.Fonts.Numeric -- a 1Hz reprint must not jitter
	countdown.BackgroundColor3 = countdownFill
	countdown.BackgroundTransparency = 0
	countdown.Size = UDim2.fromOffset(GP_COUNTDOWN.X, GP_COUNTDOWN.Y)
	countdown.Visible = false
	countdown.ZIndex = 6
	countdown.Parent = page.topRight
	UIStyler.Corner(theme.Radii.Pill).Parent = countdown
	GPLayoutKit.SoftStroke(theme, countdown, countdownFill)
	GPLayoutKit.Shadow(theme, countdown, "sm", shadows, countdownFill)
	self._countdownLabel = countdown

	local grid = UIStyler.Frame("Slots")
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.fromOffset(0, GP_GRID_Y)
	grid.Size = UDim2.fromOffset(GP_SLOT_W * 2 + GP_SLOT_GAP, (GP_SLOT_H + GP_SLOT_GAP) * 4 - GP_SLOT_GAP)
	grid.ZIndex = 4
	grid.Parent = content
	self._grid = grid

	-- ---- right: the match settings well --------------------------------

	local wellFill = theme.Colors.SurfaceRaised
	local settings = GPMatchFlow.Plate(theme, content, {
		name = "Settings",
		fill = wellFill,
		index = 1,
		shadow = "md",
		sink = shadows,
	})
	settings.Position = UDim2.fromOffset(GP_RIGHT_X, GP_GRID_Y)
	settings.Size = UDim2.fromOffset(GP_SETTINGS_W, GP_SETTINGS_H)
	settings.ZIndex = 4
	GPMatchFlow.Grain(theme, settings, wellFill, 5)

	local settingsTitle = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle + 2, theme.Colors.TextPrimary, "Title")
	settingsTitle.Text = "Match settings"
	settingsTitle.TextXAlignment = Enum.TextXAlignment.Left
	settingsTitle.Position = UDim2.fromOffset(spacing.M + 2, 12)
	settingsTitle.Size = UDim2.fromOffset(400, 28)
	settingsTitle.ZIndex = 6
	settingsTitle.Parent = settings

	local mode = GPLayoutKit.Text(theme, 30, theme.Colors.TextPrimary, "Mode")
	mode.TextXAlignment = Enum.TextXAlignment.Left
	mode.TextTruncate = Enum.TextTruncate.AtEnd
	mode.Position = UDim2.fromOffset(spacing.M + 2, 46)
	mode.Size = UDim2.fromOffset(GP_SETTINGS_W - spacing.M * 2 - 4, 38)
	mode.ZIndex = 6
	mode.Parent = settings
	self._modeLabel = mode

	local voteTitle = GPLayoutKit.SectionLabel(theme, settings, "Map vote")
	voteTitle.Position = UDim2.fromOffset(spacing.M + 2, 94)
	voteTitle.Size = UDim2.fromOffset(GP_SETTINGS_W - spacing.M * 2 - 4, 24)
	voteTitle.ZIndex = 6

	local voteStrip = UIStyler.Frame("VoteStrip")
	voteStrip.BackgroundTransparency = 1
	voteStrip.Position = UDim2.fromOffset(spacing.M + 2, 122)
	voteStrip.Size = UDim2.fromOffset(GP_SETTINGS_W - spacing.M * 2 - 4, GP_TILE_H)
	voteStrip.ZIndex = 6
	voteStrip.Parent = settings
	self._voteStrip = voteStrip

	self._modeDropdown = self:_BuildGPModePicker(
		settings,
		UDim2.fromOffset(spacing.M + 2, 300),
		GP_SETTINGS_W - spacing.M * 2 - 4,
		function(id: string)
			self._data.mode = id
			self._modeLabel.Text = self._copy.modeName(id)
			self:_Toast("MODE CHANGED TO " .. id, "Info")
		end
	)
	self._modeDropdown:Set(self._data.mode)

	local hostLine = GPLayoutKit.BodyText(theme, theme.TextSizes.Body + 2, theme.Colors.TextSecondary, "HostLine")
	hostLine.TextXAlignment = Enum.TextXAlignment.Left
	hostLine.TextTruncate = Enum.TextTruncate.AtEnd
	hostLine.Position = UDim2.fromOffset(spacing.M + 2, 308)
	hostLine.Size = UDim2.fromOffset(GP_SETTINGS_W - spacing.M * 2 - 4, 26)
	hostLine.Visible = false
	hostLine.ZIndex = 6
	hostLine.Parent = settings
	self._hostLine = hostLine

	self._startButton = GPMatchFlow.Button(theme, settings, {
		text = "START MATCH",
		fill = theme.Arcade.Gold,
		sizePx = Vector2.new(GP_SETTINGS_W - spacing.M * 2 - 4, 58),
		position = UDim2.fromOffset(spacing.M + 2, 364),
		index = 0,
		iconKey = "fire",
		onClick = function()
			self:_TryStart()
		end,
		sink = shadows,
	})
	self._startButton.Root.ZIndex = 6

	-- ---- bottom row: the ready toggle + leave ---------------------------

	self._readyButton = GPMatchFlow.Button(theme, content, {
		text = "READY UP",
		fill = theme.Colors.Secondary,
		sizePx = Vector2.new(360, GP_BOTTOM_H),
		position = UDim2.new(0.5, 0, 1, -8), -- 8px clear of the clipped field edge, so the chip shadow is not shaved
		anchorPoint = Vector2.new(0.5, 1),
		index = 0,
		onClick = function()
			self:_ToggleReady()
		end,
		sink = shadows,
	})
	self._readyButton.Root.ZIndex = 5

	self._leaveButton = GPMatchFlow.Button(theme, content, {
		text = "Leave",
		fill = theme.Colors.Error,
		sizePx = Vector2.new(180, GP_BOTTOM_H),
		position = UDim2.new(1, 0, 1, -8),
		anchorPoint = Vector2.new(1, 1),
		index = 1,
		onClick = function()
			self:_Toast("YOU LEFT THE LOBBY", "Warning")
			self.ScreenController:HideScreen("lobby")
		end,
		sink = shadows,
	})
	self._leaveButton.Root.ZIndex = 5

	self:_Render()
end

-- One slot. Filled slots keep every line the arcade slot carries — avatar,
-- host crown, name, ready caption and the ready light — and yours reads rose
-- with the "(you)" suffix. An empty slot stays an INVITATION, not a disabled
-- tile: the dashed lip is drawn in the pack's deepened rose rather than gold.
function LobbyScreen:_BuildGPSlot(player: LobbyPlayer?, index: number)
	local theme = self:GetTheme()
	local spacing = theme.Spacing
	local column = (index - 1) % 2
	local row = (index - 1) // 2
	local position = UDim2.fromOffset(column * (GP_SLOT_W + GP_SLOT_GAP), row * (GP_SLOT_H + GP_SLOT_GAP))

	if not player then
		local emptyFill = theme.Colors.Surface
		local slot = GPMatchFlow.Fill("Slot" .. index, emptyFill, 0.35)
		slot.Position = position
		slot.Size = UDim2.fromOffset(GP_SLOT_W, GP_SLOT_H)
		slot.ZIndex = 4
		slot.Parent = self._grid
		GPLayoutKit.Petal(theme, slot, index)
		-- The dashed lip: the same geometry as the arcade slot's, in a deepened
		-- rose so it reads as an open seat rather than a warning. The runs stop
		-- short of the petal radius so no dash hangs where the fill has been
		-- rounded away.
		dashedOutline(slot, GP_SLOT_W, GP_SLOT_H, GPLayoutKit.Deepen(theme, theme.Colors.Primary, 1), theme.Radii.Large)

		local label = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle, theme.Colors.TextSecondary, "Invite")
		label.Text = "+ Invite a friend"
		label.Size = UDim2.fromScale(1, 1)
		label.ZIndex = 5
		label.Parent = slot

		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Text = ""
		hit.BackgroundTransparency = 1 -- solid buttons get a black backstop stroke
		hit.AutoButtonColor = false
		hit.Size = UDim2.fromScale(1, 1)
		hit.ZIndex = 6
		hit.Parent = slot
		hit.Activated:Connect(function()
			self:_Toast("LOBBY INVITES SENT TO YOUR FRIENDS", "Success")
		end)
		UIChrome.Animate(theme, hit, slot)
		return
	end

	local you = player.you == true
	local fill = if you then theme.Colors.Primary else theme.Colors.SurfaceRaised
	local slot = GPMatchFlow.Plate(theme, self._grid, {
		name = "Slot" .. index,
		fill = fill,
		index = index,
		shadow = "sm",
		sink = self._gpSlotShadows,
	})
	slot.Position = position
	slot.Size = UDim2.fromOffset(GP_SLOT_W, GP_SLOT_H)
	slot.ZIndex = 4

	local avatar = GPMatchFlow.AvatarDisc(theme, slot, 56)
	avatar.root.AnchorPoint = Vector2.new(0, 0.5)
	avatar.root.Position = UDim2.new(0, spacing.M, 0.5, 0)
	avatar.root.ZIndex = 5
	GPMatchFlow.LoadHeadshot(avatar, player.userId)

	if player.host then
		local crown = GPMatchFlow.Icon(theme, slot, "crown", 26, nil, { golden = true })
		crown.Position = UDim2.fromOffset(6, 6)
		crown.ZIndex = 6
	end

	-- Body copy on rose is TextPrimary (5.15:1) — the near-white is illegal.
	local name = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "Name")
	name.RichText = false
	name.Text = if you then player.name .. " (you)" else player.name
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(86, 26)
	name.Size = UDim2.fromOffset(GP_SLOT_W - 86 - 72, 26)
	name.ZIndex = 5
	name.Parent = slot

	local ready = player.ready == true
	-- Law 3: body copy on this pack's pastels is the ink. A deepened-matcha
	-- caption measures 1.91:1 on the rose "you" plate and 3.85:1 on blush, so
	-- the READY state is carried by the light disc's fill AND its glyph below —
	-- colour was never allowed to be the only signal anyway (§3.3).
	local statusTone = if ready or you then theme.Colors.TextPrimary else theme.Colors.TextSecondary
	local status = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, statusTone, "Status")
	status.Text = if ready then self._copy.ready else self._copy.notReady
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Position = UDim2.fromOffset(86, 58)
	status.Size = UDim2.fromOffset(GP_SLOT_W - 86 - 72, 22)
	status.ZIndex = 5
	status.Parent = slot

	-- The ready light: a matcha disc with a check, or a quiet blush one with
	-- the hourglass. Colour AND glyph both carry the state, never colour alone.
	local lightFill = if ready then theme.Colors.Secondary else theme.Colors.Surface
	local light = GPMatchFlow.Fill("Light", lightFill)
	light.AnchorPoint = Vector2.new(1, 0.5)
	light.Position = UDim2.new(1, -spacing.M, 0.5, 0)
	light.Size = UDim2.fromOffset(44, 44)
	light.ZIndex = 5
	light.Parent = slot
	UIStyler.Corner(theme.Radii.Pill).Parent = light
	GPLayoutKit.SoftStroke(theme, light, lightFill)

	-- Untinted archive art (a multiply would only muddy the flat cartoon); the
	-- disc's own fill is what carries the state, and Icon() inks the fallback.
	local stateIcon = GPMatchFlow.Icon(theme, light, if ready then "check" else "hourglass", if ready then 26 else 24)
	stateIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	stateIcon.Position = UDim2.fromScale(0.5, 0.5)
	stateIcon.ZIndex = 6
end

-- One map tile. Selection is a RING here too (doc §4.3) — your vote wears a
-- butter ring and a zero-offset glow instead of a hard gold outline — and the
-- vote count stays on every tile.
function LobbyScreen:_BuildGPMapTile(map: MapOption, index: number)
	local theme = self:GetTheme()
	local mine = self._myVote == map.id
	local fill = if mine then theme.Colors.Surface else theme.Colors.Background

	local tile = GPMatchFlow.Fill("Map_" .. map.id, fill)
	tile.Position = UDim2.fromOffset((index - 1) * (GP_TILE_W + GP_TILE_GAP), 0)
	tile.Size = UDim2.fromOffset(GP_TILE_W, GP_TILE_H)
	tile.ZIndex = 6
	tile.Parent = self._voteStrip
	GPLayoutKit.Petal(theme, tile, index)
	if mine then
		UIStyler.Stroke(theme.Arcade.Gold, 3, 0).Parent = tile
		GPLayoutKit.Glow(theme, tile, theme.Arcade.Gold, self._gpTileShadows)
	else
		GPLayoutKit.SoftStroke(theme, tile, fill)
		GPLayoutKit.Shadow(theme, tile, "sm", self._gpTileShadows, fill)
	end
	self._mapTiles[map.id] = tile

	local icon = GPMatchFlow.Icon(theme, tile, map.icon or "compass", 54)
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 14)
	icon.ZIndex = 7

	local name = GPLayoutKit.Text(theme, theme.TextSizes.Body + 1, theme.Colors.TextPrimary, "Name")
	name.RichText = false
	name.Text = GPMatchFlow.SoftCase(map.name)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(4, 80)
	name.Size = UDim2.fromOffset(GP_TILE_W - 8, 24)
	name.ZIndex = 7
	name.Parent = tile

	local votes = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Votes")
	votes.FontFace = theme.Fonts.Numeric
	votes.Text = string.format(self._copy.votes, map.votes)
	votes.Position = UDim2.fromOffset(4, 110)
	votes.Size = UDim2.fromOffset(GP_TILE_W - 8, 24)
	votes.ZIndex = 7
	votes.Parent = tile

	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.BackgroundTransparency = 1 -- solid buttons get a black backstop stroke
	hit.AutoButtonColor = false
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 8
	hit.Parent = tile
	hit.Activated:Connect(function()
		self:_Vote(map.id)
	end)
	UIChrome.Animate(theme, hit, tile)
end

-- A style rebuild destroys the Gui, but UIShadow BUDGET counts only fall when
-- a handle is released — hand all three GP sinks back here.
function LobbyScreen:_OnTeardown()
	self:_StopTicker()
	GPLayoutKit.ReleaseShadows(self._gpSlotShadows)
	GPLayoutKit.ReleaseShadows(self._gpTileShadows)
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	self._gpSlotShadows = nil
	self._gpTileShadows = nil
	self._gpShadows = nil
	self._copy = CLASSIC_COPY
	table.clear(self._mapTiles)
end

function LobbyScreen:Destroy()
	self:_StopTicker()
	GPLayoutKit.ReleaseShadows(self._gpSlotShadows)
	GPLayoutKit.ReleaseShadows(self._gpTileShadows)
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	self._gpSlotShadows = nil
	self._gpTileShadows = nil
	self._gpShadows = nil
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
