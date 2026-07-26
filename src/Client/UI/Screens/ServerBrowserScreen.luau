--!strict
-- SERVER BROWSER — Pottery Clash arcade family (doc §7.4). One modal card: a
-- toolbar (server count + an orange REFRESH with a small sunburst that spins
-- while the 0.6s demo scan runs), a sortable column header (NAME / REGION /
-- PLAYERS / PING — click to sort, click again to flip; the active column goes
-- gold with a ▾/▴ marker), and zebra rows: mapPin + region code, "17/30" with
-- a mini gold ruler, colour-coded ping (green < 80 / gold < 150 / red above)
-- and a JOIN button per row.
--
-- The row for the server you are ON is pinned first and wears the gold
-- selection ring (§4.3). JOIN dims in place for full servers and for the
-- current server — the tap still plays full juice and answers with a toast
-- (§11.1/§11.2), never removal.
--
-- Show(data) = { servers, currentId, onJoin }.

local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIAssets = require(script.Parent.Parent.Config.UIAssets)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UIProgressBarComponent = require(script.Parent.Parent.Components.UIProgressBarComponent)

type Server = {
	id: string,
	name: string,
	region: string,
	players: number,
	maxPlayers: number,
	ping: number,
}

local WHITE = Color3.new(1, 1, 1)

-- Fixed px at the 1650×1020 baseline. Card 1240×720 → content 1212×632.
local CARD = Vector2.new(1240, 720)
local TOOLBAR_H = 44
local HEADER_Y = 56
local HEADER_H = 32
local LIST_Y = 96
local ROW_H = 56
local ROW_GAP = 6
local SCAN_SECONDS = 0.6

-- Column x positions shared by the header row and every data row.
local COL_MARKER_X = 16
local COL_NAME_X = 56
local COL_REGION_X = 470
local COL_PLAYERS_X = 680
local COL_PING_X = 900
local COL_PING_W = 70

local SORT_COLUMNS = {
	{ key = "name", label = "NAME", x = COL_NAME_X, w = 220 },
	{ key = "region", label = "REGION", x = COL_REGION_X, w = 150 },
	{ key = "players", label = "PLAYERS", x = COL_PLAYERS_X, w = 160 },
	{ key = "ping", label = "PING", x = COL_PING_X, w = 100 },
}

local DEMO_SERVERS: { Server } = {
	{ id = "srv-1", name = "KILN VALLEY 01", region = "US-E", players = 17, maxPlayers = 30, ping = 42 },
	{ id = "srv-2", name = "KILN VALLEY 02", region = "US-E", players = 30, maxPlayers = 30, ping = 48 },
	{ id = "srv-3", name = "GLAZE LAGOON", region = "US-W", players = 11, maxPlayers = 30, ping = 74 },
	{ id = "srv-4", name = "POTTER'S ROW", region = "US-W", players = 23, maxPlayers = 30, ping = 88 },
	{ id = "srv-5", name = "TERRACOTTA TEMPLE", region = "EU-W", players = 26, maxPlayers = 30, ping = 112 },
	{ id = "srv-6", name = "CERAMIC CIRCUS", region = "EU-W", players = 8, maxPlayers = 30, ping = 124 },
	{ id = "srv-7", name = "MUDSLIDE ARENA", region = "ASIA", players = 29, maxPlayers = 30, ping = 180 },
	{ id = "srv-8", name = "THE WHEELHOUSE", region = "ASIA", players = 14, maxPlayers = 30, ping = 205 },
	{ id = "srv-9", name = "AMPHORA OUTPOST", region = "OCE", players = 5, maxPlayers = 30, ping = 241 },
}

local ServerBrowserScreen = setmetatable({}, { __index = UIScreenBase })
ServerBrowserScreen.__index = ServerBrowserScreen

function ServerBrowserScreen.new()
	local self = UIScreenBase.new("ServerBrowserScreen", 8)
	self._servers = DEMO_SERVERS :: { Server }
	self._currentId = "srv-3" :: string?
	self._onJoin = nil :: ((server: Server) -> ())?
	self._sortKey = "ping"
	self._sortAsc = true
	self._loading = false
	self._refreshToken = 0
	self._sortButtons = {} :: { [string]: TextButton }
	self._rowComponents = {} :: { any }
	self._spinConn = nil :: RBXScriptConnection?
	return setmetatable(self, ServerBrowserScreen)
end

function ServerBrowserScreen:_Toast(text: string, variant: string)
	local hud = self.ScreenController and self.ScreenController:GetScreen("hud")
	if hud then
		hud:PushToast({ text = text, variant = variant })
	end
end

-- Ping is colour-coded (doc §3.3 colour = meaning): green under 80, gold under
-- 150, red above.
local function pingColor(theme: any, ping: number): Color3
	if ping < 80 then
		return theme.Arcade.Green
	elseif ping < 150 then
		return theme.Arcade.Gold
	end
	return theme.Arcade.Red
end

function ServerBrowserScreen:_BuildContent()
	local theme = self:GetTheme()

	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = self:_R("SERVER BROWSER"),
		sizePx = CARD,
		onClose = function()
			self.ScreenController:HideScreen("serverBrowser")
		end,
	})
	self._modal = modal
	local content = modal.content

	-- ---- toolbar: count + spinner + REFRESH ---------------------------

	local status = UIChrome.Text("Status", 18, theme.Arcade.IceBlue)
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Position = UDim2.fromOffset(0, 8)
	status.Size = UDim2.fromOffset(420, 26)
	status.Parent = content
	self._statusLabel = status

	-- The small scan sunburst: visible only while "loading" — UIChrome.Spin
	-- gates on visibility, so hiding the holder stops the work too.
	local spinner = UIStyler.Frame("Spinner")
	spinner.BackgroundTransparency = 1
	spinner.AnchorPoint = Vector2.new(1, 0)
	spinner.Position = UDim2.new(1, -176, 0, 4)
	spinner.Size = UDim2.fromOffset(36, 36)
	spinner.Visible = false
	spinner.Parent = content
	self._spinner = spinner
	local _burst, spin = UIAssets.SunburstBehind(spinner, theme.Arcade.SunburstGold, 0.25, 90)
	self._spinConn = spin

	self._refreshButton = UIButtonComponent.new()
	self._refreshButton:Create(content, {
		text = self:_R("REFRESH"),
		variant = "Orange",
		size = UDim2.fromOffset(160, TOOLBAR_H),
		position = UDim2.new(1, 0, 0, 0),
		anchorPoint = Vector2.new(1, 0),
		onClick = function()
			self:_Refresh()
		end,
	})

	-- ---- sortable column header ---------------------------------------

	for _, column in SORT_COLUMNS do
		local button = Instance.new("TextButton")
		button.Name = "Sort_" .. column.key
		button.BackgroundTransparency = 1
		button.AutoButtonColor = false
		button.Position = UDim2.fromOffset(column.x, HEADER_Y)
		button.Size = UDim2.fromOffset(column.w, HEADER_H)
		button.Text = column.label
		-- Explicit FontFace: the ▾/▴ sort markers need a symbol-capable
		-- font (the engine default renders them invisibly).
		button.FontFace = theme.Fonts.Button
		button.TextSize = 18
		button.TextXAlignment = Enum.TextXAlignment.Left
		button.TextColor3 = theme.Arcade.IceBlue
		UIChrome.TextOutline(button)
		button.Parent = content
		button.Activated:Connect(function()
			self:_SetSort(column.key)
		end)
		UIChrome.Animate(theme, button)
		self._sortButtons[column.key] = button
	end

	-- ---- rows ---------------------------------------------------------

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Rows"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, LIST_Y)
	scroll.Size = UDim2.new(1, 0, 1, -LIST_Y)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = theme.Arcade.Gold
	scroll.Parent = content
	UIStyler.ListLayout({
		Padding = UDim.new(0, ROW_GAP),
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	}).Parent = scroll
	self._scroll = scroll

	local scanning = UIChrome.Text("Scanning", 24, theme.Arcade.SunburstGold)
	scanning.Text = "SCANNING SERVERS…"
	scanning.Position = UDim2.fromOffset(0, LIST_Y + 80)
	scanning.Size = UDim2.new(1, 0, 0, 30)
	scanning.Visible = false
	scanning.Parent = content
	self._scanLabel = scanning

	self:_Render()
end

function ServerBrowserScreen:_SetSort(key: string)
	if self._sortKey == key then
		self._sortAsc = not self._sortAsc
	else
		self._sortKey = key
		-- Fuller servers first is the useful default for the players column.
		self._sortAsc = key ~= "players"
	end
	self:_Render()
end

function ServerBrowserScreen:_SortedServers(): { Server }
	local sorted = table.clone(self._servers)
	local key = self._sortKey
	local asc = self._sortAsc
	table.sort(sorted, function(a: Server, b: Server): boolean
		local av: any
		local bv: any
		if key == "name" then
			av, bv = a.name, b.name
		elseif key == "region" then
			av, bv = a.region, b.region
		elseif key == "players" then
			av, bv = a.players, b.players
		else
			av, bv = a.ping, b.ping
		end
		if av == bv then
			return a.name < b.name
		end
		if asc then
			return av < bv
		end
		return av > bv
	end)
	-- The current server is pinned first, whatever the sort says.
	local currentId = self._currentId
	if currentId then
		for index, server in sorted do
			if server.id == currentId then
				table.remove(sorted, index)
				table.insert(sorted, 1, server)
				break
			end
		end
	end
	return sorted
end

function ServerBrowserScreen:_SyncHeader()
	local theme = self:GetTheme()
	for _, column in SORT_COLUMNS do
		local button = self._sortButtons[column.key]
		if not button then
			continue
		end
		if column.key == self._sortKey then
			button.Text = column.label .. "  " .. (if self._sortAsc then "▴" else "▾")
			button.TextColor3 = theme.Semantic.Selection
		else
			button.Text = column.label
			button.TextColor3 = theme.Arcade.IceBlue
		end
	end
end

function ServerBrowserScreen:_ClearRows()
	for _, component in self._rowComponents do
		component:Destroy()
	end
	table.clear(self._rowComponents)
	for _, child in self._scroll:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function ServerBrowserScreen:_BuildRow(server: Server, index: number)
	local theme = self:GetTheme()
	local isCurrent = server.id == self._currentId
	local isFull = server.players >= server.maxPlayers

	local row = UIStyler.Frame("Server_" .. server.id)
	row.BackgroundColor3 = if index % 2 == 1 then theme.Arcade.NearBlack2 else theme.Arcade.Row
	row.BackgroundTransparency = 0.15 -- doc §9 zebra rows
	row.Size = UDim2.new(1, -10, 0, ROW_H) -- 10px clear of the scrollbar
	row.LayoutOrder = index
	-- Your server wears the gold ring (§4.3); the rest keep the black rim.
	UIChrome.Stroke(theme, "Arcade", if isCurrent then "Selection" else "Panel").Parent = row
	UIChrome.GlassGradient().Parent = row
	row.Parent = self._scroll

	if isCurrent then
		local star = IconArchive.Image(row, "star", 24, { golden = true })
		star.AnchorPoint = Vector2.new(0, 0.5)
		star.Position = UDim2.new(0, COL_MARKER_X, 0.5, 0)
	end

	local name = UIChrome.Text("Name", 20, if isCurrent then theme.Semantic.Selection else WHITE)
	name.RichText = false
	name.Text = server.name
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.AnchorPoint = Vector2.new(0, 0.5)
	name.Position = UDim2.new(0, COL_NAME_X, 0.5, 0)
	name.Size = UDim2.fromOffset(390, 24)
	name.Parent = row

	-- Region: mapPin + code (the flag substitute).
	local pin = IconArchive.Image(row, "mapPin", 22)
	pin.AnchorPoint = Vector2.new(0, 0.5)
	pin.Position = UDim2.new(0, COL_REGION_X, 0.5, 0)

	local region = UIChrome.Text("Region", 18, WHITE)
	region.Text = server.region
	region.TextXAlignment = Enum.TextXAlignment.Left
	region.AnchorPoint = Vector2.new(0, 0.5)
	region.Position = UDim2.new(0, COL_REGION_X + 28, 0.5, 0)
	region.Size = UDim2.fromOffset(110, 22)
	region.Parent = row

	-- Players: "17/30" + a mini gold ruler (doc §8).
	local players = UIChrome.Text("Players", 18, if isFull then theme.Arcade.Red else WHITE)
	players.Text = string.format("%d/%d", server.players, server.maxPlayers)
	players.TextXAlignment = Enum.TextXAlignment.Left
	players.AnchorPoint = Vector2.new(0, 0.5)
	players.Position = UDim2.new(0, COL_PLAYERS_X, 0.5, 0)
	players.Size = UDim2.fromOffset(64, 22)
	players.Parent = row

	local ruler = UIProgressBarComponent.new()
	ruler:Create(row, {
		value = server.players,
		maxValue = server.maxPlayers,
		size = UDim2.fromOffset(110, 12),
		position = UDim2.new(0, COL_PLAYERS_X + 72, 0.5, 0),
		anchorPoint = Vector2.new(0, 0.5),
	})
	table.insert(self._rowComponents, ruler)

	local ping = UIChrome.Text("Ping", 18, pingColor(theme, server.ping))
	ping.Text = string.format("%dms", server.ping)
	ping.TextXAlignment = Enum.TextXAlignment.Right
	ping.AnchorPoint = Vector2.new(0, 0.5)
	ping.Position = UDim2.new(0, COL_PING_X, 0.5, 0)
	ping.Size = UDim2.fromOffset(COL_PING_W, 22)
	ping.Parent = row

	-- JOIN dims in place when blocked (§11.2) and still answers (§11.1).
	local join = UIButtonComponent.new()
	join:Create(row, {
		text = if isFull then "FULL" else self:_R("JOIN"),
		variant = "Green",
		dimmed = isFull or isCurrent,
		size = UDim2.fromOffset(110, 40),
		position = UDim2.new(1, -12, 0.5, 0),
		anchorPoint = Vector2.new(1, 0.5),
		onClick = function()
			self:_TryJoin(server, isFull, isCurrent)
		end,
	})
	table.insert(self._rowComponents, join)
end

function ServerBrowserScreen:_TryJoin(server: Server, isFull: boolean, isCurrent: boolean)
	if isCurrent then
		self:_Toast("YOU ARE ALREADY ON THIS SERVER", "Info")
		return
	end
	if isFull then
		self:_Toast("SERVER FULL — TRY ANOTHER ONE", "Error")
		return
	end
	self:_Toast("JOINING " .. server.name .. "…", "Success")
	if self._onJoin then
		self._onJoin(server)
	end
end

function ServerBrowserScreen:_Render()
	self:_SyncHeader()
	self:_ClearRows()
	if self._loading then
		self._statusLabel.Text = "SCANNING…"
		self._scanLabel.Visible = true
		return
	end
	self._scanLabel.Visible = false
	local sorted = self:_SortedServers()
	for index, server in sorted do
		self:_BuildRow(server, index)
	end
	self._statusLabel.Text = string.format("%d SERVERS FOUND", #sorted)
end

-- The 0.6s demo scan: rows clear, the little sunburst spins, pings re-jitter.
function ServerBrowserScreen:_Refresh()
	if self._loading then
		self:_Toast("STILL SCANNING…", "Info")
		return
	end
	self._loading = true
	self._refreshToken += 1
	local token = self._refreshToken
	self._spinner.Visible = true
	self:_Render()
	task.delay(SCAN_SECONDS, function()
		if token ~= self._refreshToken or not self._built then
			return
		end
		for _, server in self._servers do
			server.ping = math.clamp(server.ping + math.random(-18, 18), 8, 350)
			local headroom = server.maxPlayers - server.players
			server.players = math.clamp(server.players + math.random(-3, math.min(3, headroom)), 0, server.maxPlayers)
		end
		self._loading = false
		self._spinner.Visible = false
		self:_Render()
	end)
end

function ServerBrowserScreen:_Ingest(data: any?)
	if not data then
		return
	end
	if data.servers then
		self._servers = data.servers
	end
	if data.currentId ~= nil then
		self._currentId = data.currentId
	end
	if data.onJoin then
		self._onJoin = data.onJoin
	end
end

function ServerBrowserScreen:_OnShow(data: any?)
	if data then
		self:_Ingest(data)
		self:_Render()
	end
	if self._modal then
		UIChrome.PopIn(self:GetTheme(), self._modal.content)
	end
end

function ServerBrowserScreen:Update(data: any)
	self:_Ingest(data)
	if self._built then
		self:_Render()
	end
end

function ServerBrowserScreen:Destroy()
	self._refreshToken += 1 -- orphan any in-flight scan
	if self._spinConn then
		self._spinConn:Disconnect()
		self._spinConn = nil
	end
	self:_ClearRows()
	if self._refreshButton then
		self._refreshButton:Destroy()
		self._refreshButton = nil
	end
	UIScreenBase.Destroy(self)
end

return ServerBrowserScreen
