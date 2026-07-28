--!strict
-- Compass strip (HUD widget) at the doc §7.2 secondary top-centre slot (y=62):
-- a near-black tape marked every 15°, with cardinal letters, a gold centre
-- needle and pips for tracked waypoints.
--
-- The tape is NOT a sliding frame. Every mark is positioned analytically each
-- frame from the camera's yaw (x = centre + shortestAngle(mark − yaw) × px/°),
-- which means the tape can never "run out" of strip at any heading, needs no
-- duplicate wrap-around copy of itself, and lets waypoint pips use exactly the
-- same maths as the letters. Marks that fall outside the strip hide; waypoint
-- pips instead CLAMP to the edge and dim, so an off-screen objective still
-- tells you which way to turn.

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local HUDWidgetBase = require(script.Parent.HUDWidgetBase)
local GPHUDStyle = require(script.Parent.GPHUDStyle)

local CompassWidget = setmetatable({}, { __index = HUDWidgetBase })
CompassWidget.__index = CompassWidget

local SPAN_DEG = 180 -- how much of the world the strip shows edge to edge
local MARK_STEP = 15
local PIP_POOL = 6
local PIP_SIZE = 10
local CLAMPED_TRANSPARENCY = 0.35

local CARDINALS: { [number]: string } = { [0] = "N", [90] = "E", [180] = "S", [270] = "W" }

-- Demo waypoints so the strip has something to point at with no backend.
local DEMO_WAYPOINTS = {
	{ position = Vector3.new(120, 0, -80) },
	{ position = Vector3.new(-220, 0, 40) },
	{ position = Vector3.new(30, 0, 260) },
}

-- Shortest signed angle from `from` to `to`, in (−180, 180].
local function shortestAngle(from: number, to: number): number
	return (to - from + 540) % 360 - 180
end

-- Compass bearing of a direction, with Roblox's usual convention: −Z is north,
-- +X is east. The camera's yaw is measured the same way so the two agree.
local function bearingOf(x: number, z: number): number
	return math.deg(math.atan2(x, -z)) % 360
end

function CompassWidget.new()
	local self = HUDWidgetBase.new("compass", "CompassWidget")
	self._marks = {} :: { any }
	self._pips = {} :: { Frame }
	self._waypoints = DEMO_WAYPOINTS
	return setmetatable(self, CompassWidget)
end

function CompassWidget:_Build(props: HUDWidgetBase.Props)
	local theme = self.Theme
	local width = math.max(self.Root.Size.X.Offset, 200)
	local height = math.max(self.Root.Size.Y.Offset, 24)
	self._width = width
	self._pxPerDeg = width / SPAN_DEG

	local strip = UIStyler.Frame("Strip")
	strip.BackgroundColor3 = theme.Arcade.NearBlack
	strip.Size = UDim2.fromScale(1, 1)
	strip.ClipsDescendants = true
	UIChrome.Corner("Arcade").Parent = strip
	self._stroke = UIChrome.Stroke(theme, "Arcade", "Panel")
	self._stroke.Parent = strip
	UIChrome.GlassGradient().Parent = strip
	strip.Parent = self.Root
	self._strip = strip

	for degrees = 0, 359, MARK_STEP do
		table.insert(self._marks, self:_BuildMark(degrees, height))
	end

	-- Waypoint pips are pooled: the tracked list changes as quests do, and a
	-- compass must never allocate inside its per-frame loop.
	for i = 1, PIP_POOL do
		local pip = UIStyler.Frame("Pip" .. i)
		pip.AnchorPoint = Vector2.new(0.5, 0)
		pip.Size = UDim2.fromOffset(PIP_SIZE, PIP_SIZE)
		pip.Rotation = 45 -- a diamond, in the same shape family as the ruler ticks
		pip.ZIndex = 6
		pip.Visible = false
		pip.Parent = strip
		table.insert(self._pips, pip)
	end

	local needle = UIStyler.Frame("Needle")
	needle.AnchorPoint = Vector2.new(0.5, 0.5)
	needle.Position = UDim2.fromScale(0.5, 0.5)
	needle.Size = UDim2.new(0, 2, 1, -6)
	needle.ZIndex = 7
	needle.Parent = strip
	self._needle = needle

	if props.waypoints then
		self._waypoints = props.waypoints
	end

	self:_RenderStep(function()
		self:_Step()
	end)
end

function CompassWidget:_BuildMark(degrees: number, height: number)
	local theme = self.Theme
	local letter = CARDINALS[degrees]
	if letter then
		local label = UIChrome.Text("Mark" .. degrees, 15, theme.Colors.TextPrimary)
		label.Text = letter
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Size = UDim2.fromOffset(30, height)
		label.ZIndex = 3
		label.Visible = false
		label.Parent = self._strip
		return { degrees = degrees, gui = label, cardinal = true, north = degrees == 0 }
	end
	local major = degrees % 45 == 0
	local tick = UIStyler.Frame("Tick" .. degrees)
	tick.AnchorPoint = Vector2.new(0.5, 1)
	tick.Size = UDim2.fromOffset(2, major and 12 or 6)
	tick.BackgroundTransparency = major and 0.15 or 0.45
	tick.ZIndex = 2
	tick.Visible = false
	tick.Parent = self._strip
	return { degrees = degrees, gui = tick, cardinal = false, north = false }
end

-- ---- data --------------------------------------------------------------

-- data: { waypoints = { {position = Vector3, color = Color3?} } }
function CompassWidget:Update(data: any)
	if type(data) ~= "table" then
		return
	end
	if data.waypoints then
		self:SetWaypoints(data.waypoints)
	end
end

function CompassWidget:SetWaypoints(waypoints: { any })
	self._waypoints = waypoints
	for _, pip in self._pips do
		pip.Visible = false
	end
end

-- ---- per-frame ---------------------------------------------------------

function CompassWidget:_Step()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local cf = camera.CFrame
	local look = cf.LookVector
	local yaw = bearingOf(look.X, look.Z)
	local centre = self._width / 2
	local halfSpan = SPAN_DEG / 2

	for _, mark in self._marks do
		local delta = shortestAngle(yaw, mark.degrees)
		if math.abs(delta) > halfSpan then
			mark.gui.Visible = false
		else
			mark.gui.Visible = true
			local x = centre + delta * self._pxPerDeg
			if mark.cardinal then
				mark.gui.Position = UDim2.new(0, x, 0.5, 0)
			else
				mark.gui.Position = UDim2.new(0, x, 1, -3)
			end
		end
	end

	local origin = cf.Position
	for index, pip in self._pips do
		local waypoint = self._waypoints[index]
		if not waypoint or not waypoint.position then
			pip.Visible = false
		else
			local offset = waypoint.position - origin
			local delta = shortestAngle(yaw, bearingOf(offset.X, offset.Z))
			local clamped = math.abs(delta) > halfSpan
			local x = math.clamp(centre + delta * self._pxPerDeg, 6, self._width - 6)
			pip.Visible = true
			pip.Position = UDim2.new(0, x, 0, 5)
			pip.BackgroundTransparency = clamped and CLAMPED_TRANSPARENCY or 0
			pip.BackgroundColor3 = waypoint.color or self.Theme.Semantic.Selection
		end
	end
end

function CompassWidget:_Style(theme: Types.UITheme)
	if self._strip then
		self._strip.BackgroundColor3 = theme.Arcade.NearBlack
	end
	if self._stroke then
		self._stroke.Color = theme.Colors.Stroke
	end
	if self._needle then
		self._needle.BackgroundColor3 = theme.Semantic.Selection
	end
	-- North is the reference the whole strip is read against, so it gets the
	-- "this is the important one" colour (doc §3.3) — gold on the near-black
	-- arcade tape, and the pack's deepened rose on a pastel one, where butter
	-- on a light plate measures ~1.2:1 and would simply vanish.
	local northInk = if GPHUDStyle.Active(theme) then theme.Colors.Stroke else theme.Arcade.Gold
	for _, mark in self._marks do
		if mark.cardinal then
			local label = mark.gui :: TextLabel
			label.FontFace = theme.Fonts.Button
			label.TextColor3 = mark.north and northInk or theme.Colors.TextPrimary
			GPHUDStyle.Halo(theme, label)
		else
			mark.gui.BackgroundColor3 = theme.Arcade.RulerTick
		end
	end
	for _, pip in self._pips do
		pip.BackgroundColor3 = theme.Semantic.Selection
	end

	-- GIRLY POP: the tape becomes a translucent pill with a soft hue shadow —
	-- a ribbon laid over the world rather than a slab bolted on top of it. All
	-- 24 marks at 15°, the four cardinals, the major/minor tick weights, the
	-- centre needle and all six waypoint pips (clamped and dimmed off-span) are
	-- exactly as authored.
	GPHUDStyle.Surface(theme, self._strip, {
		transparency = GPHUDStyle.Plate,
		radius = theme.Radii.Pill,
		stroke = true,
		strokeIntent = "Panel",
		strokeKeepColor = true,
		shadow = "sm",
		sink = self._shadows,
	})
	GPHUDStyle.Surface(theme, self._needle, { keepTransparency = true, radius = theme.Radii.Pill })
end

return CompassWidget
