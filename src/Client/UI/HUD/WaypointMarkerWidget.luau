--!strict
-- World waypoint markers (HUD widget): a full-bleed overlay that projects each
-- tracked waypoint with Camera:WorldToViewportPoint every frame. On screen a
-- waypoint is its icon with an optional name above and a live "128m" distance
-- below; off screen (or behind the camera, where the projection mirrors — same
-- gotcha DamageNumbersWidget documents) the icon CLAMPS to the viewport edge
-- with a rotated ">" pointing toward the objective, so it always tells you
-- which way to turn instead of vanishing.
--
-- MARKERS ARE POOLED and the per-frame loop allocates nothing. Distance text
-- only rewrites when the whole metre changes (doc §11.3 update-rate frugality),
-- and the whole loop runs through _RenderStep, which gates on
-- UIChrome.IsOnScreen of the widget root and is disconnected in Destroy.
--
-- Positions use Scale fractions of the ScreenGui's own AbsoluteSize — the same
-- trick DamageNumbersWidget documents — so the baseline UIScale on our root
-- never skews the projection.

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local HUDWidgetBase = require(script.Parent.HUDWidgetBase)

local WaypointMarkerWidget = setmetatable({}, { __index = HUDWidgetBase })
WaypointMarkerWidget.__index = WaypointMarkerWidget

local POOL_SIZE = 6
local ICON = 28
local EDGE_PX = 46 -- clamp margin from the viewport edge
local ARROW_R = 30 -- how far past the icon the pointer sits

-- Demo waypoints so the overlay renders standalone with no backend.
local DEMO_WAYPOINTS = {
	{ worldPosition = Vector3.new(140, 12, -90), icon = "quest", label = "QUEST" },
	{ worldPosition = Vector3.new(-180, 6, 130), icon = "chest", label = "STASH" },
	{ worldPosition = Vector3.new(30, 20, 260), icon = "pin", label = "RALLY" },
}

function WaypointMarkerWidget.new()
	local self = HUDWidgetBase.new("waypoints", "WaypointMarkerWidget")
	self._pool = {} :: { any }
	self._waypoints = DEMO_WAYPOINTS :: { any }
	return setmetatable(self, WaypointMarkerWidget)
end

function WaypointMarkerWidget:_Build(props: HUDWidgetBase.Props)
	for i = 1, POOL_SIZE do
		table.insert(self._pool, self:_BuildMarker(i))
	end

	self:SetWaypoints(props.waypoints or self._waypoints)

	self:_RenderStep(function()
		self:_Step()
	end)
end

function WaypointMarkerWidget:_BuildMarker(index: number)
	local theme = self.Theme

	local root = UIStyler.Frame("Waypoint" .. index)
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Size = UDim2.fromOffset(64, 64)
	root.Visible = false
	root.ZIndex = 2
	root.Parent = self.Root

	local name = UIChrome.Text("Label", 14, theme.Arcade.Gold)
	name.AnchorPoint = Vector2.new(0.5, 1)
	name.Position = UDim2.new(0.5, 0, 0.5, -20)
	name.Size = UDim2.fromOffset(140, 16)
	name.ZIndex = 3
	name.Parent = root

	local icon = IconArchive.Image(root, "compass", ICON)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.ZIndex = 3

	local dist = UIChrome.Text("Distance", 14, theme.Arcade.IceBlue)
	dist.AnchorPoint = Vector2.new(0.5, 0)
	dist.Position = UDim2.new(0.5, 0, 0.5, 20)
	dist.Size = UDim2.fromOffset(90, 16)
	dist.ZIndex = 3
	dist.Parent = root

	-- The off-screen pointer. FredokaOne has a clean ">" glyph (unlike ✕);
	-- rotating the LABEL points it anywhere, cheaper than art and never blank.
	local arrow = UIChrome.Text("Arrow", 22, theme.Colors.TextPrimary)
	arrow.Text = ">"
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Size = UDim2.fromOffset(22, 22)
	arrow.Visible = false
	arrow.ZIndex = 4
	arrow.Parent = root

	return { root = root, name = name, icon = icon, dist = dist, arrow = arrow, lastDist = -1 }
end

-- ---- data --------------------------------------------------------------

-- data: { waypoints = { {worldPosition = Vector3, icon = string?, label = string?} } }
function WaypointMarkerWidget:Update(data: any)
	if type(data) ~= "table" then
		return
	end
	if data.waypoints then
		self:SetWaypoints(data.waypoints)
	end
end

function WaypointMarkerWidget:SetWaypoints(list: { any })
	self._waypoints = list
	for index, entry in self._pool do
		local waypoint = list[index]
		entry.lastDist = -1
		entry.root.Visible = false
		if waypoint then
			entry.name.Text = waypoint.label or ""
			self:_SetIcon(entry, waypoint.icon or "compass")
		end
	end
end

-- Pooled markers keep whichever instance IconArchive handed us at build time,
-- so the swap covers both shapes (uploaded image, or glyph fallback).
function WaypointMarkerWidget:_SetIcon(entry: any, iconName: string)
	local icon = entry.icon
	if icon:IsA("ImageLabel") then
		local id = IconArchive.Id(iconName)
		if id then
			icon.Image = id
		end
	elseif icon:IsA("TextLabel") then
		icon.Text = IconArchive.Glyph(iconName)
	end
end

-- ---- per-frame ---------------------------------------------------------

function WaypointMarkerWidget:_Step()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local gui = self.Root:FindFirstAncestorOfClass("ScreenGui")
	local span = (gui and gui.AbsoluteSize) or camera.ViewportSize
	if span.X <= 0 or span.Y <= 0 then
		return
	end
	local origin = camera.CFrame.Position
	local mx, my = EDGE_PX / span.X, EDGE_PX / span.Y

	for index, entry in self._pool do
		local waypoint = self._waypoints[index]
		local position = waypoint and (waypoint.worldPosition or waypoint.position)
		if not position then
			entry.root.Visible = false
		else
			local point = camera:WorldToViewportPoint(position)
			local behind = point.Z <= 0
			local fx, fy = point.X / span.X, point.Y / span.Y
			local onScreen = not behind
				and fx >= mx and fx <= 1 - mx
				and fy >= my and fy <= 1 - my
			entry.root.Visible = true

			if onScreen then
				entry.root.Position = UDim2.new(fx, 0, fy, 0)
				entry.arrow.Visible = false
				entry.dist.Visible = true
				entry.name.Visible = entry.name.Text ~= ""
			else
				-- Behind the camera the projection mirrors, so flip the
				-- direction before clamping it onto the edge rectangle.
				local dx, dy = fx - 0.5, fy - 0.5
				if behind then
					dx, dy = -dx, -dy
				end
				if dx == 0 and dy == 0 then
					dy = 1
				end
				local k = math.min(
					(0.5 - mx) / math.max(math.abs(dx), 1e-4),
					(0.5 - my) / math.max(math.abs(dy), 1e-4)
				)
				entry.root.Position = UDim2.new(0.5 + dx * k, 0, 0.5 + dy * k, 0)
				-- Angle in PIXEL space, not fraction space — fractions are
				-- squashed by the aspect ratio and would skew the pointer.
				local angle = math.atan2(dy * span.Y, dx * span.X)
				entry.arrow.Rotation = math.deg(angle)
				entry.arrow.Position = UDim2.new(0.5, math.cos(angle) * ARROW_R, 0.5, math.sin(angle) * ARROW_R)
				entry.arrow.Visible = true
				entry.dist.Visible = false
				entry.name.Visible = false
			end

			-- Whole-metre granularity: never rewrite the label at render rate.
			local metres = math.floor((position - origin).Magnitude + 0.5)
			if metres ~= entry.lastDist then
				entry.lastDist = metres
				entry.dist.Text = tostring(metres) .. "m"
			end
		end
	end
end

function WaypointMarkerWidget:_Style(theme: Types.UITheme)
	for _, entry in self._pool do
		entry.name.FontFace = theme.Fonts.Button
		entry.name.TextColor3 = theme.Arcade.Gold
		UIChrome.TextOutline(entry.name)
		entry.dist.FontFace = theme.Fonts.Button
		entry.dist.TextColor3 = theme.Arcade.IceBlue
		UIChrome.TextOutline(entry.dist)
		entry.arrow.FontFace = theme.Fonts.Button
		entry.arrow.TextColor3 = theme.Colors.TextPrimary
		UIChrome.TextOutline(entry.arrow)
	end
end

return WaypointMarkerWidget
