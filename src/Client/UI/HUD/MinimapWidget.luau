--!strict
-- Minimap (HUD widget): a fixed 220×220 north-up square in the top-right band
-- under the killfeed. The "baked map" is a near-black plate with a faint grid —
-- a real game bakes a top-down render of its island into ONE ImageLabel here
-- (static, costs nothing per frame); a live ViewportFrame camera re-renders
-- actual scene geometry every frame and is far too expensive for HUD chrome.
--
-- The map never rotates. The player arrow at the centre rotates with the
-- camera's yaw instead (compass convention: −Z is north, +X is east), the
-- circular N tick stays glued to the top rim, and every other marker is a
-- POOLED dot positioned from normalised map coords via Update({markers}) —
-- allies green, enemies red, pins gold (doc §3.3 colour is meaning). Zoom is a
-- 2-level toggle: coords spread around the centre; pins CLAMP to the rim so an
-- objective outside the zoomed window still shows its direction, plain dots
-- (which carry no routing meaning off-map) just hide.

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local HUDWidgetBase = require(script.Parent.HUDWidgetBase)
local GPHUDStyle = require(script.Parent.GPHUDStyle)

local MinimapWidget = setmetatable({}, { __index = HUDWidgetBase })
MinimapWidget.__index = MinimapWidget

local MARKER_POOL = 12
local GRID_DIV = 8
local GRID_TRANSPARENCY = 0.88
local DOT = 8
local PIN_DOT = 10
local EDGE = 0.05 -- rim clamp for pins, in map fractions

-- Demo markers so the map reads populated with no backend.
local DEMO_MARKERS = {
	{ x = 0.42, y = 0.63, kind = "ally" },
	{ x = 0.35, y = 0.31, kind = "ally" },
	{ x = 0.68, y = 0.44, kind = "enemy" },
	{ x = 0.61, y = 0.78, kind = "enemy" },
	{ x = 0.21, y = 0.55, kind = "enemy" },
	{ x = 0.82, y = 0.18, kind = "pin" },
}

function MinimapWidget.new()
	local self = HUDWidgetBase.new("minimap", "MinimapWidget")
	self._markers = DEMO_MARKERS :: { any }
	self._dots = {} :: { Frame }
	self._gridLines = {} :: { Frame }
	self._zoom = 1
	return setmetatable(self, MinimapWidget)
end

function MinimapWidget:_Build(props: HUDWidgetBase.Props)
	local theme = self.Theme
	if props.markers then
		self._markers = props.markers
	end

	local map = UIStyler.Frame("Map")
	map.BackgroundColor3 = theme.Arcade.NearBlack
	map.Size = UDim2.fromScale(1, 1)
	map.ClipsDescendants = true
	UIChrome.Corner("Arcade").Parent = map
	self._stroke = UIChrome.Stroke(theme, "Arcade", "Panel")
	self._stroke.Parent = map
	UIChrome.GlassGradient().Parent = map
	map.Parent = self.Root
	self._map = map

	-- Baked-map placeholder: a survey grid, thin frames only. The real art
	-- drop-in replaces this whole block with one ImageLabel.
	for i = 1, GRID_DIV - 1 do
		local fraction = i / GRID_DIV
		local v = UIStyler.Frame("GridV" .. i)
		v.BackgroundColor3 = theme.Arcade.RulerTick
		v.BackgroundTransparency = GRID_TRANSPARENCY
		v.AnchorPoint = Vector2.new(0.5, 0)
		v.Position = UDim2.fromScale(fraction, 0)
		v.Size = UDim2.new(0, 1, 1, 0)
		v.ZIndex = 2
		v.Parent = map
		table.insert(self._gridLines, v)

		local h = UIStyler.Frame("GridH" .. i)
		h.BackgroundColor3 = theme.Arcade.RulerTick
		h.BackgroundTransparency = GRID_TRANSPARENCY
		h.AnchorPoint = Vector2.new(0, 0.5)
		h.Position = UDim2.fromScale(0, fraction)
		h.Size = UDim2.new(1, 0, 0, 1)
		h.ZIndex = 2
		h.Parent = map
		table.insert(self._gridLines, h)
	end

	for i = 1, MARKER_POOL do
		local dot = UIStyler.Frame("Marker" .. i)
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Size = UDim2.fromOffset(DOT, DOT)
		UIChrome.Corner("Arcade", "Pill").Parent = dot
		dot.ZIndex = 4
		dot.Visible = false
		dot.Parent = map
		table.insert(self._dots, dot)
	end

	-- The player arrow: shaft + diamond head in one container, rotated as a
	-- unit by the camera's yaw each frame.
	local arrow = UIStyler.Frame("PlayerArrow")
	arrow.BackgroundTransparency = 1
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Position = UDim2.fromScale(0.5, 0.5)
	arrow.Size = UDim2.fromOffset(18, 18)
	arrow.ZIndex = 5
	arrow.Parent = map
	self._arrow = arrow

	local shaft = UIStyler.Frame("Shaft")
	shaft.AnchorPoint = Vector2.new(0.5, 1)
	shaft.Position = UDim2.new(0.5, 0, 1, -2)
	shaft.Size = UDim2.fromOffset(4, 9)
	shaft.Parent = arrow
	self._arrowShaft = shaft

	local head = UIStyler.Frame("Head")
	head.AnchorPoint = Vector2.new(0.5, 0.5)
	head.Position = UDim2.new(0.5, 0, 0, 5)
	head.Size = UDim2.fromOffset(9, 9)
	head.Rotation = 45
	UIChrome.Stroke(theme, "Arcade", "Wheel").Parent = head
	head.Parent = arrow
	self._arrowHead = head

	-- Circular N tick: the one fixed reference the rotating arrow is read
	-- against ("Pill" is the arcade's sanctioned round exception, doc §4.2).
	local north = UIStyler.Frame("North")
	north.BackgroundColor3 = theme.Arcade.NearBlack2
	north.AnchorPoint = Vector2.new(0.5, 0)
	north.Position = UDim2.new(0.5, 0, 0, 4)
	north.Size = UDim2.fromOffset(20, 20)
	UIChrome.Corner("Arcade", "Pill").Parent = north
	UIChrome.Stroke(theme, "Arcade", "Wheel").Parent = north
	north.ZIndex = 6
	north.Parent = map
	self._north = north

	local northLabel = UIChrome.Text("NorthLabel", 13, theme.Arcade.Gold)
	northLabel.Text = "N"
	northLabel.Size = UDim2.fromScale(1, 1)
	northLabel.ZIndex = 7
	northLabel.Parent = north
	self._northLabel = northLabel

	local zoom = Instance.new("TextButton")
	zoom.Name = "Zoom"
	zoom.AnchorPoint = Vector2.new(1, 1)
	zoom.Position = UDim2.new(1, -4, 1, -4)
	zoom.Size = UDim2.fromOffset(32, 24)
	zoom.BackgroundColor3 = theme.Arcade.Blue
	zoom.BorderSizePixel = 0
	zoom.Text = "1X"
	zoom.FontFace = theme.Fonts.Button
	zoom.TextSize = 13
	zoom.TextColor3 = theme.Colors.TextPrimary
	UIChrome.TextOutline(zoom)
	UIChrome.Stroke(theme, "Arcade", "Panel").Parent = zoom
	UIChrome.ArcadeBevel().Parent = zoom
	zoom.ZIndex = 6
	zoom.Parent = map
	self._zoomButton = zoom
	self:_Connect(zoom.Activated, function()
		self:_SetZoom(self._zoom == 1 and 2 or 1)
	end)
	UIChrome.Animate(theme, zoom) -- LAST, after final colours

	self:_LayoutMarkers()

	self:_RenderStep(function()
		local camera = workspace.CurrentCamera
		if camera then
			local look = camera.CFrame.LookVector
			self._arrow.Rotation = math.deg(math.atan2(look.X, -look.Z))
		end
	end)
end

-- ---- data --------------------------------------------------------------

-- data: { markers = { {x, y, kind = "ally"|"enemy"|"pin"} }, zoom = 1|2 }
-- with x/y as normalised map coords (0..1).
function MinimapWidget:Update(data: any)
	if type(data) ~= "table" then
		return
	end
	if data.markers then
		self._markers = data.markers
	end
	if data.zoom then
		self._zoom = math.clamp(math.floor(data.zoom), 1, 2)
		if self._zoomButton then
			self._zoomButton.Text = tostring(self._zoom) .. "X"
		end
	end
	self:_LayoutMarkers()
end

function MinimapWidget:_SetZoom(level: number)
	self._zoom = math.clamp(math.floor(level), 1, 2)
	if self._zoomButton then
		self._zoomButton.Text = tostring(self._zoom) .. "X"
	end
	self:_LayoutMarkers()
end

function MinimapWidget:_KindColor(kind: string?): Color3
	local arcade = self.Theme.Arcade
	if kind == "ally" then
		return arcade.Green
	elseif kind == "enemy" then
		return arcade.Red
	elseif kind == "pin" then
		return arcade.Gold
	end
	return self.Theme.Colors.TextPrimary
end

function MinimapWidget:_LayoutMarkers()
	if #self._dots == 0 then
		return
	end
	for index, dot in self._dots do
		local marker = self._markers[index]
		if not marker then
			dot.Visible = false
		else
			local px = 0.5 + ((marker.x or 0.5) - 0.5) * self._zoom
			local py = 0.5 + ((marker.y or 0.5) - 0.5) * self._zoom
			local pin = marker.kind == "pin"
			if pin then
				px = math.clamp(px, EDGE, 1 - EDGE)
				py = math.clamp(py, EDGE, 1 - EDGE)
				dot.Visible = true
			else
				dot.Visible = px >= EDGE and px <= 1 - EDGE and py >= EDGE and py <= 1 - EDGE
			end
			dot.Position = UDim2.fromScale(px, py)
			dot.Size = UDim2.fromOffset(pin and PIN_DOT or DOT, pin and PIN_DOT or DOT)
			dot.BackgroundColor3 = self:_KindColor(marker.kind)
		end
	end
end

function MinimapWidget:_Style(theme: Types.UITheme)
	if self._map then
		self._map.BackgroundColor3 = theme.Arcade.NearBlack
	end
	if self._stroke then
		self._stroke.Color = theme.Colors.Stroke
	end
	for _, line in self._gridLines do
		line.BackgroundColor3 = theme.Arcade.RulerTick
	end
	if self._north then
		self._north.BackgroundColor3 = theme.Arcade.NearBlack2
	end
	if self._northLabel then
		self._northLabel.FontFace = theme.Fonts.Button
		-- Gold lettering reads on a near-black tick and measures ~1.2:1 on a
		-- pastel one, so the pack swaps which half of the pair carries the
		-- colour: the TICK goes butter and the letter goes ink.
		self._northLabel.TextColor3 = if GPHUDStyle.Active(theme) then theme.Colors.TextPrimary else theme.Arcade.Gold
		UIChrome.TextOutline(self._northLabel)
	end
	if self._arrowShaft then
		self._arrowShaft.BackgroundColor3 = theme.Colors.TextPrimary
	end
	if self._arrowHead then
		self._arrowHead.BackgroundColor3 = theme.Colors.TextPrimary
	end
	if self._zoomButton then
		self._zoomButton.BackgroundColor3 = theme.Arcade.Blue
		self._zoomButton.FontFace = theme.Fonts.Button
		self._zoomButton.TextColor3 = theme.Colors.TextPrimary
		UIChrome.TextOutline(self._zoomButton)
	end

	-- GIRLY POP: the map plate goes translucent on the large radius so the world
	-- shows THROUGH the map as well as around it, with one soft hue shadow
	-- lifting the whole tile. The survey grid, all twelve marker slots, the
	-- ally/enemy/pin colour coding, the rim-clamped pins, the rotating player
	-- arrow, the north tick and the 2-level zoom are all exactly as authored.
	GPHUDStyle.Surface(theme, self._map, {
		transparency = GPHUDStyle.Plate,
		radius = theme.Radii.Large,
		stroke = true,
		strokeIntent = "Panel",
		strokeKeepColor = true,
		shadow = "md",
		sink = self._shadows,
	})
	GPHUDStyle.Surface(theme, self._north, {
		fill = theme.Arcade.Gold,
		restFill = theme.Arcade.NearBlack2,
		keepTransparency = true,
		keepCorner = true,
		stroke = true,
		strokeIntent = "Wheel",
	})
	GPHUDStyle.Surface(theme, self._arrowHead, {
		keepTransparency = true,
		keepCorner = true,
		stroke = true,
		strokeIntent = "Wheel",
	})
	-- The map CLIPS, and under this pack its corner is a 24px round instead of
	-- the arcade's 90°, so the zoom button authored 4px off the bottom-right
	-- would have a bite taken out of it. It steps inside the curve rather than
	-- the plate losing its radius — same button, same size, same 2 levels.
	if self._zoomButton then
		self._zoomButton.Position = if GPHUDStyle.Active(theme)
			then UDim2.new(1, -12, 1, -12)
			else UDim2.new(1, -4, 1, -4)
	end
	GPHUDStyle.Surface(theme, self._zoomButton, {
		keepTransparency = true,
		radius = theme.Radii.Small,
		stroke = true,
		strokeIntent = "Panel",
	})
	-- Only the north letter takes a halo. The zoom button already carries a
	-- Border UIStroke and the engine renders one UIStroke per object, so a glow
	-- beside it would be inert — and the button has a plate behind its text.
	GPHUDStyle.Halo(theme, self._northLabel)
	self:_LayoutMarkers()
end

return MinimapWidget
