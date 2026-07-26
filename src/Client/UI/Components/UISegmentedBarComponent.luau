--!strict
-- UISegmentedBarComponent — the ARMORED CORE segmented meter. AP, EN, ACS
-- strain and boost charge are all THIS component with different props: a run
-- of discrete cells in a UIListLayout, filled left-to-right (or bottom-to-top
-- when Vertical), with the AC grouped-tick pattern (a wider gap every
-- `chunkSize` cells), damage ghosts that hold newly-lost cells in Error for a
-- beat, and threshold recolouring of the whole filled run.
--
-- Discrete by design: SetValue only touches the cells whose state actually
-- changed — never a rebuild, never one tween per cell. The single boundary
-- cell expresses the fractional remainder through BackgroundTransparency
-- (never width: a width change would reflow the whole list). All timing
-- (damage ghosts, danger pulse) runs on ONE UITicker handler owned by the
-- bar — zero tweens, zero per-cell connections.
--
-- PERF NOTE: one Frame per cell is the right trade up to ~64 cells. Above
-- that, instance count (not fill rate) becomes the bottleneck and the correct
-- replacement is a single tiled-texture ImageLabel whose tile mask carries
-- the cell pattern — deliberately NOT implemented here; no current meter
-- exceeds 40 cells.
--
-- Extra props (beyond Types.UIComponentProps):
--   segments    : number       cell count (default 20)
--   orientation : "Horizontal" (default) | "Vertical" (fills bottom-to-top)
--   thresholds  : { { at: number, colorToken: string } }
--                 `at` is a RATIO of max (0..1). The active threshold is the
--                 smallest `at` that still contains the current ratio; its
--                 colorToken (a theme.Colors key, e.g. "Error") recolours the
--                 whole filled run. The LOWEST threshold is the danger band:
--                 while inside it the filled run pulses subtly.
--   chunkSize   : number?      wider gap every N cells (the AC tick grouping)
--
-- API: :SetValue(current, max)   :GetValue() -> (current, max)

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIComponentBase = require(script.Parent.UIComponentBase)
local UITicker = require(script.Parent.Parent.Framework.UITicker)

local UISegmentedBarComponent = setmetatable({}, { __index = UIComponentBase })
UISegmentedBarComponent.__index = UISegmentedBarComponent

export type Threshold = {
	at: number, -- ratio of max, 0..1
	colorToken: string, -- key into theme.Colors ("Error", "Warning", ...)
}

local DEFAULT_SEGMENTS = 20
local SEGMENT_GAP_PX = 1
local CHUNK_GAP_PX = 3
local EMPTY_TRANSPARENCY = 0.4
-- The boundary cell fades from nearly-empty (0.85) toward solid as the
-- fraction grows; it never quite reaches invisible so "a sliver left" still
-- reads against the empty track.
local BOUNDARY_MAX_TRANSPARENCY = 0.85
local GHOST_SECONDS = 0.12
local DANGER_PULSE_RATE = 6 -- rad/s, ~1s cycle
local DANGER_PULSE_DEPTH = 0.25

function UISegmentedBarComponent.new()
	local self = UIComponentBase.new("UISegmentedBar")
	self._value = 0
	self._max = 100
	self._segmentCount = DEFAULT_SEGMENTS
	self._segments = {} :: { Frame }
	self._baseTransparency = {} :: { number }
	-- Logical index -> UITicker clock time at which the damage ghost expires.
	self._ghosts = {} :: { [number]: number }
	self._thresholds = {} :: { Threshold }
	self._filled = 0
	self._boundary = nil :: number?
	self._fraction = 0
	self._activeToken = nil :: string?
	self._danger = false
	self._pulsing = false
	self._stopTicker = nil :: (() -> ())?
	return setmetatable(self, UISegmentedBarComponent)
end

function UISegmentedBarComponent:_Build(props: Types.UIComponentProps)
	local segs = math.max(1, math.floor((props.segments :: number?) or DEFAULT_SEGMENTS))
	local vertical = props.orientation == "Vertical"
	local chunk: number? = props.chunkSize
	if chunk and chunk < 1 then
		chunk = nil
	end
	self._segmentCount = segs

	-- Own sorted copy so the FIRST containing threshold is always the
	-- smallest `at` — and index 1 is, by construction, the danger band.
	local thresholds: { Threshold } = {}
	for _, t in ((props.thresholds :: { Threshold }?) or {}) do
		table.insert(thresholds, { at = t.at, colorToken = t.colorToken })
	end
	table.sort(thresholds, function(a, b)
		return a.at < b.at
	end)
	self._thresholds = thresholds

	local root = self.Root
	if not props.size then
		root.Size = if vertical then UDim2.new(0, 14, 1, 0) else UDim2.new(1, 0, 0, 14)
		self._baseSize = root.Size
	end

	local layout = UIStyler.ListLayout({
		FillDirection = if vertical then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = if vertical then Enum.VerticalAlignment.Bottom else Enum.VerticalAlignment.Top,
		Padding = UDim.new(0, SEGMENT_GAP_PX),
	})
	layout.Parent = root

	-- Every cell shares the root's length exactly: Scale carries the equal
	-- split, a negative Offset hands back each cell's share of the gap px
	-- (list padding between all children + the wider chunk spacers).
	local spacerCount = if chunk then (segs - 1) // chunk else 0
	local gapTotal = (segs + spacerCount - 1) * SEGMENT_GAP_PX + spacerCount * CHUNK_GAP_PX
	local perCell = -gapTotal / segs
	local cellSize = if vertical then UDim2.new(1, 0, 1 / segs, perCell) else UDim2.new(1 / segs, perCell, 1, 0)

	local order = 0
	for i = 1, segs do
		order += 1
		local cell = UIStyler.Frame("Seg" .. i)
		cell.Size = cellSize
		-- Vertical meters fill bottom-to-top: negating LayoutOrder puts
		-- logical cell 1 at the BOTTOM of the top-to-bottom list flow.
		cell.LayoutOrder = if vertical then -order else order
		cell.BackgroundTransparency = EMPTY_TRANSPARENCY
		cell.Parent = root
		self._segments[i] = cell
		self._baseTransparency[i] = EMPTY_TRANSPARENCY

		if chunk and i % chunk == 0 and i < segs then
			order += 1
			local spacer = UIStyler.Frame("ChunkGap")
			spacer.BackgroundTransparency = 1
			spacer.Size = if vertical
				then UDim2.new(1, 0, 0, CHUNK_GAP_PX)
				else UDim2.new(0, CHUNK_GAP_PX, 1, 0)
			spacer.LayoutOrder = if vertical then -order else order
			spacer.Parent = root
		end
	end

	-- THE one ticker handler for this bar: ghost expiry + danger pulse.
	-- bindTo the Root so any teardown path auto-unregisters; Destroy also
	-- stops it explicitly (stop is idempotent).
	self._stopTicker = UITicker.Register(function(dt: number, now: number)
		self:_Tick(dt, now)
	end, root)

	self:SetValue((props.value :: number?) or 0, (props.maxValue :: number?) or 100)
end

-- Active threshold for a ratio: smallest `at` that contains it. Second return
-- marks the danger band (the lowest threshold of the set).
function UISegmentedBarComponent:_ActiveThreshold(ratio: number): (string?, boolean)
	for index, t in self._thresholds do
		if ratio <= t.at then
			return t.colorToken, index == 1
		end
	end
	return nil, false
end

function UISegmentedBarComponent:_FillColor(theme: Types.UITheme): Color3
	local token = self._activeToken
	if token then
		local color = (theme.Colors :: any)[token]
		if typeof(color) == "Color3" then
			return color
		end
	end
	return theme.Colors.Accent
end

-- Paint ONE cell from current state. Priority: filled > ghost > boundary >
-- empty — so healing over a ghost clears it, and a half-lost boundary cell
-- flashes Error first, then settles to its partial fill when the ghost
-- expires. Instant sets only: discrete state changes are the AC language.
function UISegmentedBarComponent:_PaintSegment(i: number)
	local theme = self.Theme
	local cell = self._segments[i]
	if not theme or not cell then
		return
	end
	local colors = theme.Colors
	local color: Color3
	local transparency: number
	if i <= self._filled then
		self._ghosts[i] = nil
		color = self:_FillColor(theme)
		transparency = 0
	elseif self._ghosts[i] then
		color = colors.Error
		transparency = 0
	elseif i == self._boundary then
		color = self:_FillColor(theme)
		transparency = (1 - self._fraction) * BOUNDARY_MAX_TRANSPARENCY
	else
		color = colors.SurfaceRaised
		transparency = EMPTY_TRANSPARENCY
	end
	cell.BackgroundColor3 = color
	cell.BackgroundTransparency = transparency
	self._baseTransparency[i] = transparency
end

function UISegmentedBarComponent:SetValue(current: number, max: number)
	self._value = current
	self._max = max

	local segs = self._segmentCount
	local ratio = if max > 0 then math.clamp(current / max, 0, 1) else 0
	local scaled = ratio * segs
	local filled = math.floor(scaled + 0.0001)
	local fraction = math.max(scaled - filled, 0)
	local boundary: number? = if fraction > 0.001 and filled < segs then filled + 1 else nil

	local oldFilled = self._filled
	local oldBoundary = self._boundary
	self._filled = filled
	self._boundary = boundary
	self._fraction = fraction

	-- Damage ghosts: every newly-emptied cell (and a lost partial boundary)
	-- holds in Error until the ticker expires it — never a tween.
	if filled < oldFilled then
		local now = UITicker.Now()
		for i = filled + 1, oldFilled do
			self._ghosts[i] = now + GHOST_SECONDS
		end
		if oldBoundary and oldBoundary > filled and oldBoundary ~= boundary then
			self._ghosts[oldBoundary] = now + GHOST_SECONDS
		end
	end

	local token, danger = self:_ActiveThreshold(ratio)
	local tokenChanged = token ~= self._activeToken
	self._activeToken = token
	self._danger = danger

	if not self.Theme then
		return -- state is set; the first ApplyTheme paints everything
	end

	if tokenChanged then
		-- Crossing a threshold recolours the WHOLE filled run.
		for i = 1, math.max(filled, oldFilled) do
			self:_PaintSegment(i)
		end
		if boundary then
			self:_PaintSegment(boundary)
		end
		if oldBoundary then
			self:_PaintSegment(oldBoundary)
		end
	else
		-- Only the cells whose state changed — the whole point of the bar.
		for i = math.min(oldFilled, filled) + 1, math.max(oldFilled, filled) do
			self:_PaintSegment(i)
		end
		if oldBoundary and oldBoundary ~= boundary then
			self:_PaintSegment(oldBoundary)
		end
		if boundary then
			self:_PaintSegment(boundary)
		end
	end
end

function UISegmentedBarComponent:GetValue(): (number, number)
	return self._value, self._max
end

-- The bar's single per-frame handler: expire damage ghosts, run the danger
-- pulse. Early-outs to nothing when the bar is calm.
function UISegmentedBarComponent:_Tick(_dt: number, now: number)
	local ghosts = self._ghosts
	local hasGhosts = next(ghosts) ~= nil
	if not hasGhosts and not self._danger and not self._pulsing then
		return
	end

	if hasGhosts then
		-- Removing keys during generalized iteration is safe in Luau.
		for i, expiry in ghosts do
			if now >= expiry then
				ghosts[i] = nil
				self:_PaintSegment(i)
			end
		end
	end

	if self._danger then
		-- Frugality: no pulse work while the bar is off screen; ghosts above
		-- still expire so state never sticks.
		if UIChrome.IsOnScreen(self.Root) then
			self._pulsing = true
			local offset = DANGER_PULSE_DEPTH * (0.5 + 0.5 * math.sin(now * DANGER_PULSE_RATE))
			for i = 1, self._filled do
				if not ghosts[i] then
					self._segments[i].BackgroundTransparency = offset
				end
			end
		end
	elseif self._pulsing then
		self._pulsing = false
		for i = 1, self._segmentCount do
			self._segments[i].BackgroundTransparency = self._baseTransparency[i]
		end
	end
end

-- Full repaint from the theme: filled/empty/ghost/boundary colours all
-- resolve through _PaintSegment, so a live theme swap re-skins in place.
function UISegmentedBarComponent:_Style(_theme: Types.UITheme)
	for i = 1, self._segmentCount do
		self:_PaintSegment(i)
	end
end

function UISegmentedBarComponent:Destroy()
	if self._stopTicker then
		self._stopTicker()
		self._stopTicker = nil
	end
	UIComponentBase.Destroy(self)
end

return UISegmentedBarComponent
