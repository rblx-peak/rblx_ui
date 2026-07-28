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

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIAssets = require(script.Parent.Parent.Config.UIAssets)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UIProgressBarComponent = require(script.Parent.Parent.Components.UIProgressBarComponent)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)

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
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end
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

-- ---- copy + tone seams -------------------------------------------------
-- One code path serves both layouts; these three seams are the only places
-- they differ. Under Classic they return the exact strings and Arcade tokens
-- the screen always used. Under GP they answer pack law 5 (no all-caps copy)
-- and swap the near-black-era tones for ones that measure on cream — no
-- column, marker or reading is added or removed either way.

function ServerBrowserScreen:_ColumnLabel(label: string): string
	if self:LayoutKit() == "GP" then
		-- Title Case, and "Ping" keeps its meaning without shouting.
		return string.upper(string.sub(label, 1, 1)) .. string.lower(string.sub(label, 2))
	end
	return label
end

function ServerBrowserScreen:_HeaderTone(active: boolean): Color3
	local theme = self:GetTheme()
	if self:LayoutKit() == "GP" then
		-- Selection rose measures 2.0:1 on cream at this size; deepened along
		-- its OWN hue it lands at ~5:1 and is still unmistakably the rose.
		return if active then GPLayoutKit.Deepen(theme, theme.Semantic.Selection, 1) else theme.Colors.TextSecondary
	end
	return if active then theme.Semantic.Selection else theme.Arcade.IceBlue
end

function ServerBrowserScreen:_StatusText(count: number?): string
	if self:LayoutKit() == "GP" then
		return if count then string.format("%d servers found", count) else "Scanning…"
	end
	return if count then string.format("%d SERVERS FOUND", count) else "SCANNING…"
end

function ServerBrowserScreen:_SyncHeader()
	for _, column in SORT_COLUMNS do
		local button = self._sortButtons[column.key]
		if not button then
			continue
		end
		local label = self:_ColumnLabel(column.label)
		local active = column.key == self._sortKey
		-- The ▴/▾ marker is never dropped: it is how the table states which
		-- column it is sorted on, and in which direction.
		button.Text = if active then label .. "  " .. (if self._sortAsc then "▴" else "▾") else label
		button.TextColor3 = self:_HeaderTone(active)
	end
end

function ServerBrowserScreen:_ClearRows()
	for _, component in self._rowComponents do
		component:Destroy()
	end
	table.clear(self._rowComponents)
	-- Nil-guarded: teardown can reach here on a screen that was constructed but
	-- never built, in which case there is no scroll yet.
	if not self._scroll then
		return
	end
	for _, child in self._scroll:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function ServerBrowserScreen:_BuildRow(server: Server, index: number)
	if self:LayoutKit() == "GP" then
		self:_GPBuildRow(server, index)
		return
	end
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
		self._statusLabel.Text = self:_StatusText(nil)
		self._scanLabel.Visible = true
		return
	end
	self._scanLabel.Visible = false
	local sorted = self:_SortedServers()
	for index, server in sorted do
		self:_BuildRow(server, index)
	end
	self._statusLabel.Text = self:_StatusText(#sorted)
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

-- ========================================================================
-- GP layout — THE KILN REGISTER (theme.LayoutKit == "GP").
--
-- §6 anti-condescension, stated as an inventory: the server count, the scan
-- spinner, Refresh, ALL FOUR sortable columns with their ▴/▾ direction marker,
-- and every one of the six readings a row carries — current-server marker,
-- name, region pin + code, "17/30" WITH its mini ruler, colour-coded ping in
-- ms, and Join — survive verbatim. Sorting, pinning and the dim-in-place Join
-- rules are untouched; they live in _SortedServers / _TryJoin, which this
-- branch never sees.
--
-- The page is authored 48px taller than the classic card so the content field
-- lands at EXACTLY the classic 1212x632 — GPLayoutKit.Page spends 136px on
-- header + scallop + gutters where the arcade modal spends 88. Every column x
-- above is therefore reused verbatim; the header row is shifted by the scroll's
-- own padding so header and data stay on one ladder.
--
-- IMPROVISED LOCALLY (noted for the kit): GPLayoutKit ships neither a button
-- nor a meter, and UIButtonComponent / UIProgressBarComponent branch GL and
-- Arcade but not GP. `gpChip` and `gpMiniRuler` below are this screen's
-- pack-correct stand-ins, returning the same {Root, SetContent, Destroy} /
-- {Destroy} handles _ClearRows and the teardown already call.
-- ========================================================================

local GP_PAGE_GROW = 48
local GP_SCROLL_PAD = 8
local GP_ROW_H = ROW_H

-- Two passes of the pack's own hue-preserving Deepen: one leaves matcha, butter
-- and coral near 3:1 on cream, two lands them past 6:1 while staying
-- recognisably that hue. Doc §3.3 colour-as-meaning and the pack's measured-
-- contrast rule both survive.
local function gpInk(theme: Types.UITheme, color: Color3): Color3
	return GPLayoutKit.Deepen(theme, GPLayoutKit.Deepen(theme, color, 1), 1)
end

-- Ping keeps its three-band meaning (doc §3.3), re-keyed to tones that measure
-- on cream: green under 80, butter under 150, coral above.
local function gpPingColor(theme: Types.UITheme, ping: number): Color3
	if ping < 80 then
		return gpInk(theme, theme.Colors.Secondary)
	elseif ping < 150 then
		return gpInk(theme, theme.Colors.Accent)
	end
	return gpInk(theme, theme.Colors.Error)
end

local function gpIcon(theme: Types.UITheme, parent: Instance, key: string, sizePx: number, query: any?): GuiObject
	local icon = IconArchive.Image(parent, key, sizePx, query)
	if icon:IsA("TextLabel") then
		-- IconArchive's GLYPH fallback is born pure-white with a black text
		-- stroke — both banned by this pack.
		icon.TextColor3 = theme.Colors.TextPrimary
		icon.TextStrokeTransparency = 1
	end
	return icon
end

local function gpVariantFill(theme: Types.UITheme, variant: string?): Color3
	local map: { [string]: Color3 } = {
		Green = theme.Colors.Secondary,
		Red = theme.Colors.Error,
		Blue = theme.Arcade.Blue,
		Gold = theme.Arcade.Gold,
		Grey = theme.Arcade.GreyOwned,
		Orange = theme.Arcade.Orange,
		Rose = theme.Colors.Primary,
		Ghost = theme.Colors.Surface,
	}
	return map[variant or "Ghost"] or theme.Colors.Surface
end

-- The pack's chip button. The TextButton itself stays TRANSPARENT and the fill
-- lives on a petal chip child, because UIStyleEnforcer backstops any SOLID
-- GuiButton with a BLACK 2px stroke — pack law 1 broken on sight. Dimming is
-- IN PLACE (doc §11.2): a full or current server's Join stays there, stays
-- tappable, and answers with the reason.
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

-- The mini occupancy ruler that rides beside "17/30". Deliberately shadow-free
-- (one per row) and pill-capped: this is the arcade §8 ruler in the pack's
-- silhouette, not a replacement for the reading beside it.
local function gpMiniRuler(theme: Types.UITheme, parent: Instance, props: any): any
	local handle: any = {}
	local trackFill = theme.Arcade.RulerTrack

	local root = UIStyler.Frame("GPMiniRuler")
	root.BackgroundColor3 = trackFill
	root.AnchorPoint = props.anchorPoint or Vector2.new(0, 0)
	root.Position = props.position or UDim2.new()
	root.Size = props.size or UDim2.fromOffset(110, 12)
	root.ZIndex = props.zIndex or 3
	root.Parent = parent
	UIStyler.Corner(theme.Radii.Pill).Parent = root
	GPLayoutKit.SoftStroke(theme, root, trackFill)

	local alpha = if props.maxValue > 0 then math.clamp(props.value / props.maxValue, 0, 1) else 0
	local fillColor = props.fill or theme.Colors.Primary
	local fill = UIStyler.Frame("Fill")
	fill.BackgroundColor3 = fillColor
	fill.Size = UDim2.fromScale(alpha, 1)
	fill.ZIndex = root.ZIndex + 1
	fill.Parent = root
	UIStyler.Corner(theme.Radii.Pill).Parent = fill

	handle.Root = root
	handle.Destroy = function(_self: any)
		if root.Parent then
			root:Destroy()
		end
	end
	return handle
end

function ServerBrowserScreen:_BuildGPLayout()
	local theme = self:GetTheme()

	local page = GPLayoutKit.Page(theme, self.Root, {
		titleText = "Server browser",
		subtitleText = "Pick a kiln with room and a short hop",
		sizePx = Vector2.new(CARD.X, CARD.Y + GP_PAGE_GROW),
		onClose = function()
			self.ScreenController:HideScreen("serverBrowser")
		end,
	})
	self._modal = { content = page.content } :: any
	self._gpShadows = page.shadows
	local content = page.content

	-- ---- toolbar: count + spinner + Refresh ---------------------------

	local status = GPLayoutKit.BodyText(theme, theme.TextSizes.Subtitle, theme.Colors.TextSecondary, "Status")
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Position = UDim2.fromOffset(GP_SCROLL_PAD, 8)
	status.Size = UDim2.fromOffset(420, 26)
	status.Parent = content
	self._statusLabel = status

	-- The small scan sunburst: visible only while "loading" — UIChrome.Spin
	-- gates on visibility, so hiding the holder stops the work too. It is the
	-- one rotating thing on a GP page, and it sits well inside the content
	-- bounds (a rotated descendant is not clipped by an ancestor).
	local spinner = UIStyler.Frame("Spinner")
	spinner.BackgroundTransparency = 1
	spinner.AnchorPoint = Vector2.new(1, 0)
	spinner.Position = UDim2.new(1, -176, 0, 4)
	spinner.Size = UDim2.fromOffset(36, 36)
	spinner.Visible = false
	spinner.Parent = content
	self._spinner = spinner
	local _burst, spin = UIAssets.SunburstBehind(spinner, theme.Colors.Accent, 0.25, 90)
	self._spinConn = spin

	self._refreshButton = gpChip(theme, content, {
		text = "Refresh",
		variant = "Orange",
		size = UDim2.fromOffset(160, TOOLBAR_H),
		position = UDim2.new(1, 0, 0, 0),
		anchorPoint = Vector2.new(1, 0),
		onClick = function()
			self:_Refresh()
		end,
	}, self._gpShadows)

	-- ---- sortable column header ---------------------------------------
	-- All four columns, still click-to-sort and click-again-to-flip. The
	-- buttons stay TRANSPARENT so the enforcer's black backstop never fires.

	for _, column in SORT_COLUMNS do
		local button = Instance.new("TextButton")
		button.Name = "Sort_" .. column.key
		button.BackgroundTransparency = 1
		button.AutoButtonColor = false
		-- Shifted by the scroll's own padding so the header sits on the same
		-- ladder as the data rows below it.
		button.Position = UDim2.fromOffset(column.x + GP_SCROLL_PAD, HEADER_Y)
		button.Size = UDim2.fromOffset(column.w, HEADER_H)
		button.Text = self:_ColumnLabel(column.label)
		-- Explicit FontFace: the ▾/▴ sort markers need a symbol-capable font
		-- (the engine default renders them invisibly).
		button.FontFace = theme.Fonts.Button
		button.TextSize = theme.TextSizes.Button
		button.TextXAlignment = Enum.TextXAlignment.Left
		button.TextColor3 = theme.Colors.TextSecondary
		button.Parent = content
		button.Activated:Connect(function()
			self:_SetSort(column.key)
		end)
		UIChrome.Animate(theme, button)
		self._sortButtons[column.key] = button
	end

	GPLayoutKit.Divider(theme, content).Position = UDim2.fromOffset(0, LIST_Y - 10)

	-- ---- rows ---------------------------------------------------------

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Rows"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ClipsDescendants = true -- leaking rows are a known past bug here
	scroll.Position = UDim2.fromOffset(0, LIST_Y)
	scroll.Size = UDim2.new(1, 0, 1, -LIST_Y)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = theme.Colors.Primary
	scroll.Parent = content
	UIStyler.ListLayout({
		Padding = UDim.new(0, ROW_GAP),
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	}).Parent = scroll
	-- Inset so the pinned row's glow is not sliced at the clip edge.
	UIStyler.PaddingXY(GP_SCROLL_PAD, GP_SCROLL_PAD).Parent = scroll
	self._scroll = scroll

	local scanning = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle + 4, GPLayoutKit.Deepen(theme, theme.Colors.Accent, 1), "Scanning")
	scanning.Text = "Scanning servers…"
	scanning.Position = UDim2.fromOffset(0, LIST_Y + 80)
	scanning.Size = UDim2.new(1, 0, 0, 30)
	scanning.Visible = false
	scanning.Parent = content
	self._scanLabel = scanning

	self:_Render()
end

-- One server row, GP grammar. SIX readings, exactly as classic: the current-
-- server marker, name, region pin + code, occupancy text + ruler, ping in ms,
-- and Join. Petal alternates by index; no per-row shadow (see the budget note
-- in this section's header). The server you are ON is marked with a soft ROSE
-- GLOW instead of the classic hard gold ring.
function ServerBrowserScreen:_GPBuildRow(server: Server, index: number)
	local theme = self:GetTheme()
	local isCurrent = server.id == self._currentId
	local isFull = server.players >= server.maxPlayers
	-- Zebra by index; the pinned current server always takes the lighter plate
	-- so its glow has something to bloom off, whatever position it lands in.
	local fill = if isCurrent or index % 2 == 1 then theme.Colors.SurfaceRaised else theme.Colors.Background

	local row = UIStyler.Frame("Server_" .. server.id)
	row.BackgroundColor3 = fill
	row.BackgroundTransparency = 0
	row.Size = UDim2.new(1, -10, 0, GP_ROW_H) -- 10px clear of the scrollbar
	row.LayoutOrder = index
	row.Parent = self._scroll
	GPLayoutKit.Petal(theme, row, index)
	local rim = GPLayoutKit.SoftStroke(theme, row, fill)
	if isCurrent then
		rim.Color = GPLayoutKit.Deepen(theme, theme.Colors.Primary, 1)
		rim.Transparency = 0.1
		-- The mark: a soft aura, not a harsh highlight. Deliberately NOT in the
		-- page sink — rows are rebuilt on every sort, refresh and Update, so the
		-- handle rides in self._rowComponents, which _ClearRows releases at the
		-- top of the render that refills it. In the page sink it would walk the
		-- budget counter up one aura per render with nothing bringing it down.
		local glow = GPLayoutKit.Glow(theme, row, theme.Colors.Primary)
		table.insert(self._rowComponents, {
			Destroy = function(_self: any)
				glow:Release()
			end,
		} :: any)

		local star = gpIcon(theme, row, "star", 24, { golden = true })
		star.AnchorPoint = Vector2.new(0, 0.5)
		star.Position = UDim2.new(0, COL_MARKER_X, 0.5, 0)
		star.ZIndex = 3
	end

	local name = GPLayoutKit.Text(
		theme,
		theme.TextSizes.Subtitle,
		if isCurrent then GPLayoutKit.Deepen(theme, theme.Colors.Primary, 1) else theme.Colors.TextPrimary,
		"Name"
	)
	name.RichText = false
	-- A server NAME is data, not copy: it is never re-cased.
	name.Text = server.name
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.AnchorPoint = Vector2.new(0, 0.5)
	name.Position = UDim2.new(0, COL_NAME_X, 0.5, 0)
	name.Size = UDim2.fromOffset(390, 24)
	name.ZIndex = 3
	name.Parent = row

	-- Region: mapPin + code (the flag substitute).
	local pin = gpIcon(theme, row, "mapPin", 22)
	pin.AnchorPoint = Vector2.new(0, 0.5)
	pin.Position = UDim2.new(0, COL_REGION_X, 0.5, 0)
	pin.ZIndex = 3

	local region = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "Region")
	region.Text = server.region -- a region CODE, left exactly as supplied
	region.TextXAlignment = Enum.TextXAlignment.Left
	region.AnchorPoint = Vector2.new(0, 0.5)
	region.Position = UDim2.new(0, COL_REGION_X + 28, 0.5, 0)
	region.Size = UDim2.fromOffset(110, 22)
	region.ZIndex = 3
	region.Parent = row

	-- Players: "17/30" + the mini ruler (doc §8). Both, always.
	local players = GPLayoutKit.NumberText(
		theme,
		theme.TextSizes.Body,
		if isFull then gpInk(theme, theme.Colors.Error) else theme.Colors.TextPrimary,
		"Players"
	)
	players.Text = string.format("%d/%d", server.players, server.maxPlayers)
	players.TextXAlignment = Enum.TextXAlignment.Left
	players.AnchorPoint = Vector2.new(0, 0.5)
	players.Position = UDim2.new(0, COL_PLAYERS_X, 0.5, 0)
	players.Size = UDim2.fromOffset(64, 22)
	players.ZIndex = 3
	players.Parent = row

	local ruler = gpMiniRuler(theme, row, {
		value = server.players,
		maxValue = server.maxPlayers,
		fill = if isFull then theme.Colors.Error else theme.Colors.Secondary,
		size = UDim2.fromOffset(110, 12),
		position = UDim2.new(0, COL_PLAYERS_X + 72, 0.5, 0),
		anchorPoint = Vector2.new(0, 0.5),
	})
	table.insert(self._rowComponents, ruler)

	local ping = GPLayoutKit.NumberText(theme, theme.TextSizes.Body, gpPingColor(theme, server.ping), "Ping")
	ping.Text = string.format("%dms", server.ping)
	ping.AnchorPoint = Vector2.new(0, 0.5)
	ping.Position = UDim2.new(0, COL_PING_X, 0.5, 0)
	ping.Size = UDim2.fromOffset(COL_PING_W, 22)
	ping.ZIndex = 3
	ping.Parent = row

	local join = gpChip(theme, row, {
		text = if isFull then "Full" else "Join",
		variant = "Green",
		dimmed = isFull or isCurrent,
		size = UDim2.fromOffset(110, 40),
		position = UDim2.new(1, -12, 0.5, 0),
		anchorPoint = Vector2.new(1, 0.5),
		petalIndex = index + 1,
		zIndex = 3,
		onClick = function()
			self:_TryJoin(server, isFull, isCurrent)
		end,
	-- No page sink for a ROW chip: the handle lives in self._rowComponents,
	-- whose Destroy releases it. Pushing it into the page sink as well would
	-- grow that table by one entry per row on every re-render.
	}, nil)
	table.insert(self._rowComponents, join)
end

-- A STYLE REBUILD runs this hook and then throws the shell away, so the
-- component teardown Destroy already did lives here now and Destroy delegates —
-- previously a style swap dropped the components and the spin connection on the
-- floor. Shadow handles are budget-registered: a destroyed GuiObject alone
-- leaves the counter high.
function ServerBrowserScreen:_OnTeardown()
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
	table.clear(self._sortButtons)
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	self._gpShadows = nil
end

function ServerBrowserScreen:Destroy()
	self:_OnTeardown()
	UIScreenBase.Destroy(self)
end

return ServerBrowserScreen
