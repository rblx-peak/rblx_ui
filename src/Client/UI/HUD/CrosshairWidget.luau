--!strict
-- Dynamic crosshair (HUD widget, shipped disabled — a shooter flips it on in
-- HUDManifest): four 2px white bars around a centre dot. Spread is data
-- (Update({spread}) in px), recoil is Fire() — an instant kick that decays
-- exponentially — and the bars only ever REPOSITION when the rounded offset
-- actually changes, so a resting crosshair costs nothing per frame.
--
-- Hitmarkers are four diagonal ticks that flash for 0.12s on Hit(kind) — white
-- for a plain hit, gold for "crit"/"kill" (doc §3.3 gold = valuable) — and
-- Hit("kill") additionally flashes a bigger red X for the confirm. EVERYTHING
-- IS PREBUILT and toggled by Visible: firefights push events faster than any
-- surface on the HUD, and per-shot instancing is exactly the hitch §5.4 bans.

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local HUDWidgetBase = require(script.Parent.HUDWidgetBase)

local CrosshairWidget = setmetatable({}, { __index = HUDWidgetBase })
CrosshairWidget.__index = CrosshairWidget

local BASE_GAP = 7
local BAR_LEN = 13
local BAR_THICK = 2
local DOT = 4
local KICK_PX = 9
local KICK_DECAY = 11 -- 1/s exponential recovery
local TICK_R = 13
local HIT_FLASH = 0.12
local KILL_FLASH = 0.24

function CrosshairWidget.new()
	local self = HUDWidgetBase.new("crosshair", "CrosshairWidget")
	self._spread = 0
	self._kick = 0
	self._lastOffset = -1
	self._hitUntil = 0
	self._killUntil = 0
	self._bars = {} :: { any }
	self._ticks = {} :: { Frame }
	self._killBars = {} :: { Frame }
	return setmetatable(self, CrosshairWidget)
end

function CrosshairWidget:_Build(props: HUDWidgetBase.Props)
	local theme = self.Theme
	if props.spread then
		self._spread = props.spread
	end

	-- A zero-size anchor at screen centre: every child positions itself in
	-- pure px offsets from this point, so "outward" is just ±offset.
	local centre = UIStyler.Frame("Centre")
	centre.BackgroundTransparency = 1
	centre.AnchorPoint = Vector2.new(0.5, 0.5)
	centre.Position = UDim2.fromScale(0.5, 0.5)
	centre.Size = UDim2.fromOffset(0, 0)
	centre.Parent = self.Root
	self._centre = centre

	local dot = UIStyler.Frame("Dot")
	dot.BackgroundColor3 = theme.Colors.TextPrimary
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Size = UDim2.fromOffset(DOT, DOT)
	dot.ZIndex = 2
	dot.Parent = centre
	self._dot = dot

	local defs = {
		{ anchor = Vector2.new(0.5, 1), dx = 0, dy = -1, w = BAR_THICK, h = BAR_LEN },
		{ anchor = Vector2.new(0.5, 0), dx = 0, dy = 1, w = BAR_THICK, h = BAR_LEN },
		{ anchor = Vector2.new(1, 0.5), dx = -1, dy = 0, w = BAR_LEN, h = BAR_THICK },
		{ anchor = Vector2.new(0, 0.5), dx = 1, dy = 0, w = BAR_LEN, h = BAR_THICK },
	}
	for i, def in defs do
		local bar = UIStyler.Frame("Bar" .. i)
		bar.BackgroundColor3 = theme.Colors.TextPrimary
		bar.AnchorPoint = def.anchor
		bar.Size = UDim2.fromOffset(def.w, def.h)
		bar.ZIndex = 2
		bar.Parent = centre
		table.insert(self._bars, { gui = bar, dx = def.dx, dy = def.dy })
	end

	-- Hitmarker: four diagonal ticks. A vertical bar rotated +45° lies along
	-- the NE–SW diagonal, −45° along NW–SE.
	local hitGroup = UIStyler.Frame("Hitmarker")
	hitGroup.BackgroundTransparency = 1
	hitGroup.Size = UDim2.fromOffset(0, 0)
	hitGroup.Visible = false
	hitGroup.Parent = centre
	self._hitGroup = hitGroup

	local diagonals = {
		{ x = 1, y = -1, rot = 45 },
		{ x = -1, y = 1, rot = 45 },
		{ x = -1, y = -1, rot = -45 },
		{ x = 1, y = 1, rot = -45 },
	}
	for i, d in diagonals do
		local tick = UIStyler.Frame("Tick" .. i)
		tick.BackgroundColor3 = theme.Colors.TextPrimary
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.Position = UDim2.fromOffset(d.x * TICK_R, d.y * TICK_R)
		tick.Size = UDim2.fromOffset(BAR_THICK, 9)
		tick.Rotation = d.rot
		tick.ZIndex = 3
		tick.Parent = hitGroup
		table.insert(self._ticks, tick)
	end

	-- Kill confirm: a bigger red X, prebuilt, flashed on Hit("kill").
	local killGroup = UIStyler.Frame("KillConfirm")
	killGroup.BackgroundTransparency = 1
	killGroup.Size = UDim2.fromOffset(0, 0)
	killGroup.Visible = false
	killGroup.Parent = centre
	self._killGroup = killGroup

	for i, rot in { 45, -45 } do
		local bar = UIStyler.Frame("KillBar" .. i)
		bar.BackgroundColor3 = theme.Arcade.Red
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Size = UDim2.fromOffset(3, 30)
		bar.Rotation = rot
		bar.ZIndex = 4
		bar.Parent = killGroup
		table.insert(self._killBars, bar)
	end

	self:_ApplyOffset(BASE_GAP + math.floor(self._spread + 0.5))

	self:_RenderStep(function(dt: number, clock: number)
		self:_Step(dt, clock)
	end)
end

-- ---- API ---------------------------------------------------------------

-- data: { spread = px } — the weapon's current bloom; kick rides on top.
function CrosshairWidget:Update(data: any)
	if type(data) == "number" then
		self._spread = math.max(data, 0)
		return
	end
	if type(data) == "table" and data.spread ~= nil then
		self._spread = math.max(data.spread, 0)
	end
end

-- One shot fired: instant outward kick, exponential settle.
function CrosshairWidget:Fire()
	self._kick = KICK_PX
end

-- kind: nil/"hit" | "crit" | "kill"
function CrosshairWidget:Hit(kind: string?)
	local theme = self.Theme
	local clock = os.clock()
	local color = (kind == "crit" or kind == "kill") and theme.Arcade.Gold or theme.Colors.TextPrimary
	for _, tick in self._ticks do
		tick.BackgroundColor3 = color
	end
	self._hitGroup.Visible = true
	self._hitUntil = clock + HIT_FLASH
	if kind == "kill" then
		self._killGroup.Visible = true
		self._killUntil = clock + KILL_FLASH
	end
end

-- ---- per-frame ---------------------------------------------------------

function CrosshairWidget:_ApplyOffset(offset: number)
	for _, bar in self._bars do
		bar.gui.Position = UDim2.fromOffset(bar.dx * offset, bar.dy * offset)
	end
end

function CrosshairWidget:_Step(dt: number, clock: number)
	if self._kick > 0 then
		self._kick *= math.exp(-dt * KICK_DECAY)
		if self._kick < 0.05 then
			self._kick = 0
		end
	end
	local offset = math.floor(BASE_GAP + self._spread + self._kick + 0.5)
	if offset ~= self._lastOffset then
		self._lastOffset = offset
		self:_ApplyOffset(offset)
	end
	if self._hitUntil > 0 and clock >= self._hitUntil then
		self._hitUntil = 0
		self._hitGroup.Visible = false
	end
	if self._killUntil > 0 and clock >= self._killUntil then
		self._killUntil = 0
		self._killGroup.Visible = false
	end
end

function CrosshairWidget:_Style(theme: Types.UITheme)
	local white = theme.Colors.TextPrimary
	if self._dot then
		self._dot.BackgroundColor3 = white
	end
	for _, bar in self._bars do
		bar.gui.BackgroundColor3 = white
	end
	for _, tick in self._ticks do
		tick.BackgroundColor3 = white
	end
	for _, bar in self._killBars do
		bar.BackgroundColor3 = theme.Arcade.Red
	end
end

return CrosshairWidget
