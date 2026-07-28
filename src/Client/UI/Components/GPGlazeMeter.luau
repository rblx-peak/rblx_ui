--!strict
-- GPGlazeMeter — a filled bar that reads as poured glaze: a rounded track, a
-- vertically-graded fill, a specular sheen sweeping along it, and a soft
-- hue-matched aura when it tops out. Extends UIComponentBase, overriding
-- _Build/_Style (+ a Destroy for its ticker and glow handle).
--
-- Generic and theme-agnostic by construction. THE RADIUS IS A TOKEN, not a
-- decision: props.radiusToken names a key in theme.Radii ("Pill" by default),
-- and a pack declaring Chrome.HardCorners flattens it to 0 — so the Armored
-- Core terminal can consume this exact component and get a square capacity bar,
-- with the same fill, the same sheen and the same readout. Nothing pink and
-- nothing round is written down here.
--
-- THE 0.4 BOUNDARY: Styling owns static appearance and the MAXED state LOOK —
-- the fill wears UIMeterFill structurally and UIMaxed flips through StateDriver
-- (the sole tag mutator), so a pack's ".UIMeterFill.UIMaxed" band can dress it
-- once the engine activates styling application; the imperative paint here
-- (including the budget-safe glow) renders the same look meanwhile. Luau +
-- UITicker own everything sequenced or continuous: the display chase and the
-- sheen sweep. Neither side implements the other's half.
--
-- THE METER LAW (inherited from GLSpiralGauge): display updates are TICKER
-- work. The fill and the readout are NEVER tweened. A tweened meter lies —
-- interrupt it mid-flight and it sits at a number that was never true — and a
-- transition on a meter fill is exactly what SheetBuilder refuses, which the
-- UIMeterFill tag on the fill frame extends to this component too. SetValue is
-- a discrete assignment; the ticker chases it at a token rate.
--
-- WHY THE GRADIENT IS TWO FRAMES AND NOT A COLORSEQUENCE: UIGradient.Color
-- MULTIPLIES the fill, so authoring "accent at the top, deepened accent at the
-- bottom" the obvious way needs a pure-white identity keypoint at one end —
-- the one colour this pack bans outright. Instead the fill is painted with the
-- DEEPENED tint and a light overlay in the plain accent fades out down its
-- height via a TRANSPARENCY ramp. Same gradient on screen, zero white
-- anywhere. (GPLayoutKit.GlazeSheen makes the identical trade for the same
-- reason.)
--
-- THE SHEEN IS AN OFFSET, NOT A REBUILD: one UIGradient with a narrow bright
-- window, scrolled by moving Offset.X from -1 to 1 on the shared ticker. No
-- NumberSequence is ever rebuilt per frame (allocating a sequence every frame
-- for a decoration is how a meter starts costing more than the screen it sits
-- on), and the window's own transparency is a dialect token.
--
-- REDUCE-MOTION: a ReduceMotion boolean attribute on the Root snaps the display
-- chase to its target and parks the sheen at rest. The bar still fills, still
-- reads, still glows at full — only the sweep and the ease stop. Nothing here
-- is a blocking ceremony; the meter never captures input.
--
-- BUDGETS: exactly ONE UITicker.Register (bound to the Root for auto-cleanup;
-- Destroy also stops it explicitly, idempotently) and at most ONE UIShadow — a
-- glow, built LAZILY on the first time the meter tops out, then
-- disable-not-destroy across every later fill/empty cycle, and Released only in
-- Destroy. 100x new/Destroy and 100x max/unmax = zero connection or budget
-- growth.
--
-- Props (plus the shared layout props from UIComponentBase):
--   value, maxValue : numbers (default 0 .. 100)
--   accentToken     : Colors.* key for the fill (default "Primary")
--   radiusToken     : Radii.* key for track + fill (default "Pill")
--   precision       : decimal places in the readout; defaults to the studio
--                     dialect's statPrecision, so this pack shows ONE MORE
--                     decimal than the Armored Core rows rather than fewer
--   label           : caption above the bar, passed through VERBATIM
--   showText        : "value / max" readout, right-aligned above the bar
--   unit            : suffix appended to the readout ("%", "kg", "s")
--   sheen           : force the sweep on/off (default: on under a pack that
--                     declares a glaze dialect, off otherwise)
--   barHeight       : px height of the track itself (default 18)
--   ticks           : false removes the ruler marks; a number overrides the
--                     division count (default 10 divisions => 9 marks)
--
-- THE RULER MARKS ARE NOT DECORATION, they are the reason this passes the
-- pack's anti-condescension law. The bar this component replaces under GP
-- (UIProgressBarComponent) rules its track every 10%, alternating tall/short,
-- drawn OVER the fill — that is what lets a player read a magnitude off the
-- track without parsing the numeral. Dropping them to make the meter prettier
-- would be exactly the "soft therefore simple" trade the pack forbids, so they
-- are kept, hue-matched to the pack's own rule colour rather than the classic
-- grey, and the readout above them carries MORE precision than AC's integers.

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UITicker = require(script.Parent.Parent.Framework.UITicker)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local StateDriver = require(script.Parent.Parent.StyleKit.StateDriver)
local Tags = require(script.Parent.Parent.StyleKit.Tags)
local UIComponentBase = require(script.Parent.UIComponentBase)

local GPGlazeMeter = setmetatable({}, { __index = UIComponentBase })
GPGlazeMeter.__index = GPGlazeMeter

local DEFAULT_BAR_H = 18
local TEXT_GAP = 4
-- Sheen sweep: seconds for one pass, and the half-width of the bright window
-- as a fraction of the bar. Both fall back to these when a pack names neither.
local SHEEN_SECONDS = 2.4
local SHEEN_HALF_WIDTH = 0.08
-- How hard the fill's own colour is deepened for the bottom of the gradient.
-- Modest on purpose: a strong pour reads as two stacked bars, not one glazed
-- one.
local FILL_DEEPEN = 0.55
-- Below this the chase is done; snapping avoids a fill that creeps forever.
local CHASE_EPSILON = 0.0005
local CHASE_RATE = 9
-- Ruler marks, at the classic bar's own proportions (UIProgressBarComponent):
-- one mark per division, alternating tall/short so every other one reads as a
-- major, at a transparency that rules the track without competing with the fill.
local TICK_DIVISIONS = 10
local TICK_TALL_SCALE = 0.9
local TICK_SHORT_SCALE = 0.5
local TICK_TRANSPARENCY = 0.35

local function dialectTokens(theme: Types.UITheme, name: string): { [string]: any }
	local tokens = theme.DialectTokens
	return (tokens and tokens[name]) or {}
end

-- THE RADIUS TOKEN. A pack declaring HardCorners flattens every meter it hosts
-- — that is the whole point of routing the radius through a token instead of
-- hardcoding a pill: this component belongs to no single pack's shape language.
local function meterRadius(theme: Types.UITheme, key: string?): number
	if UIChrome.ActiveChrome().HardCorners then
		return 0
	end
	return (theme.Radii :: any)[key or "Pill"] or theme.Radii.Pill
end

function GPGlazeMeter.new()
	local self = UIComponentBase.new("GPGlazeMeter")
	self._value = 0
	self._max = 100
	self._displayed = 0
	self._maxed = false
	self._lastText = ""
	return setmetatable(self, GPGlazeMeter)
end

function GPGlazeMeter:_Build(props: Types.UIComponentProps)
	self._value = props.value or 0
	self._max = props.maxValue or 100
	self._displayed = if self._max > 0 then math.clamp(self._value / self._max, 0, 1) else 0
	-- Derived at BUILD, not left false until the first Set: a meter constructed
	-- already at full would otherwise render full, carry no UIMaxed tag and never
	-- bloom — the state would only become true after someone lowered it and
	-- raised it again.
	self._maxed = self._displayed >= 1

	local root = self.Root
	root.BackgroundTransparency = 1
	local barHeight = props.barHeight or DEFAULT_BAR_H
	local hasText = props.label ~= nil or props.showText == true
	if not props.size then
		-- The caption row is EXTRA height, never a slice out of the bar: this
		-- pack's hardest law is that nothing gets smaller for being decorated.
		root.Size = UDim2.new(1, 0, 0, if hasText then barHeight + 22 + TEXT_GAP else barHeight)
		self._baseSize = root.Size
	end
	StateDriver.Structural(root, Tags.Structural.Surface)

	-- Caption + readout share one row above the bar. Built only when asked for,
	-- so a bare meter costs two frames and nothing else.
	if hasText then
		-- Born transparent for the same reason the surfaces are:
		-- UIStyler.TextLabel's TextColor3 default is pure white.
		local caption = UIStyler.TextLabel("Caption")
		caption.TextTransparency = 1
		caption.TextXAlignment = Enum.TextXAlignment.Left
		caption.Text = props.label or ""
		caption.Parent = root
		self._caption = caption

		if props.showText then
			local readout = UIStyler.TextLabel("Readout")
			readout.TextTransparency = 1
			readout.TextXAlignment = Enum.TextXAlignment.Right
			readout.Parent = root
			StateDriver.Structural(readout, Tags.Structural.Value)
			self._readout = readout
		end
	end

	-- Every surface below is born TRANSPARENT and never painted here:
	-- UIStyler.Frame's BackgroundColor3 default is PURE WHITE, which this pack
	-- forbids outright, and _Build has no theme to paint from (it runs before
	-- the first ApplyTheme). A transparent frame renders nothing, so no white
	-- can ever reach a screen; _Style is the only place in this file that
	-- assigns a fill or clears the transparency.
	local track = UIStyler.Frame("Track")
	track.BackgroundTransparency = 1
	track.AnchorPoint = Vector2.new(0, 1)
	track.Position = UDim2.fromScale(0, 1)
	track.Size = UDim2.new(1, 0, 0, barHeight)
	-- Clips the fill's own corners at low ratios AND keeps the sheen inside the
	-- bar. Safe: nothing in this component rotates, and Roblox clipping is
	-- axis-aligned (the one thing it cannot clip is a rotated descendant).
	track.ClipsDescendants = true
	track.Parent = root
	self._track = track

	-- FILL: the DEEP end of the pour (see the two-frame note in the header).
	local fill = UIStyler.Frame("Fill")
	fill.BackgroundTransparency = 1
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = 2
	fill.Parent = track
	StateDriver.Structural(fill, Tags.Structural.MeterFill)
	self._fill = fill

	-- The LIGHT end, faded out down the bar's height by a TRANSPARENCY ramp so
	-- the gradient needs no white multiplier keypoint.
	local light = UIStyler.Frame("FillLight")
	light.BackgroundTransparency = 1
	light.Size = UDim2.fromScale(1, 1)
	light.ZIndex = 3
	light.Parent = fill
	local ramp = Instance.new("UIGradient")
	ramp.Rotation = 90
	ramp.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	ramp.Parent = light
	self._light = light

	-- SHEEN: a cream wash whose gradient carries one narrow bright window. Only
	-- Offset.X moves — the sequence itself is built once, here.
	local sheen = UIStyler.Frame("Sheen")
	sheen.BackgroundTransparency = 1
	sheen.Size = UDim2.fromScale(1, 1)
	sheen.ZIndex = 4
	sheen.Visible = false
	sheen.Parent = fill
	local sweep = Instance.new("UIGradient")
	sweep.Parent = sheen
	self._sheen = sheen
	self._sweep = sweep
	self._sweepT = 0

	-- RULER MARKS, over the fill and over the sheen so they stay readable across
	-- filled and empty track alike (the classic bar's reasoning, kept). Structure
	-- is built once here — the division count is a build-time prop because the
	-- instance count cannot change with a theme — and only the tint and the two
	-- heights are repainted in _Style. Born transparent like every other surface
	-- in this file: UIStyler.Frame's default fill is pure white.
	self._ticks = {}
	local divisions = math.floor(tonumber(props.ticks) or TICK_DIVISIONS)
	if props.ticks == false then
		divisions = 0
	end
	for k = 1, math.max(divisions - 1, 0) do
		local tick = UIStyler.Frame("Tick")
		tick.BackgroundTransparency = 1
		tick.AnchorPoint = Vector2.new(0.5, 1)
		tick.Position = UDim2.new(k / divisions, 0, 1, 0)
		tick.Size = UDim2.fromOffset(1, barHeight)
		tick.ZIndex = 5
		tick.Parent = track
		table.insert(self._ticks, tick)
	end

	-- Reduce-motion: cached from the Root's attribute; a live flip lands next
	-- tick (the handler snaps the chase and parks the sweep).
	self._reduceMotion = root:GetAttribute("ReduceMotion") == true
	self:_Connect(root:GetAttributeChangedSignal("ReduceMotion"), function()
		self._reduceMotion = root:GetAttribute("ReduceMotion") == true
	end)

	-- THE one UITicker handler of this meter: display chase + sheen sweep.
	-- Bound to the Root so destruction auto-unregisters (Destroy also stops it
	-- explicitly, idempotently).
	self._stopTicker = UITicker.Register(function(dt: number, _now: number)
		self:_Tick(dt)
	end, root)
end

-- Discrete value in; the ticker chases it (the meter law — never a tween).
function GPGlazeMeter:Set(value: number, maxValue: number?)
	self._value = value
	if maxValue then
		self._max = maxValue
	end
	self:_RenderText()
	local ratio = if self._max > 0 then math.clamp(self._value / self._max, 0, 1) else 0
	local maxed = ratio >= 1
	if maxed ~= self._maxed then
		self._maxed = maxed
		self:_ApplyMaxed(maxed)
	end
end

-- The MAXED state: the tag flip belongs to the styling side, the imperative
-- glow is the bridge that renders it meanwhile. Built LAZILY the first time the
-- meter tops out, then disable-not-destroy — so a hundred fill/empty cycles
-- cost one budget slot and zero instance churn.
function GPGlazeMeter:_ApplyMaxed(maxed: boolean)
	local theme = self.Theme :: Types.UITheme?
	-- Guarded: Set() is callable before Create(), and the tag surface must not
	-- be the thing that turns a caller's ordering mistake into a hard error.
	local fill = self._fill :: Frame?
	if not fill then
		return
	end
	StateDriver.Set(self.Root, Tags.Modifier.Maxed, maxed)
	StateDriver.Set(fill, Tags.Modifier.Maxed, maxed)
	if not theme or not theme.EffectShadows then
		return -- a pack declaring no shadow tokens pays nothing for the aura
	end
	if maxed then
		local handle = self._glowHandle
		if handle == nil then
			local accentToken = self.Props.accentToken
			local accent = (accentToken and (theme.Colors :: any)[accentToken]) or theme.Colors.Primary
			-- An aura BLOOMS rather than falls into shade: Glow keeps the hue
			-- and lifts saturation, the opposite move to the shadow's Deepen.
			self._glowHandle = GPLayoutKit.Glow(theme, self._track :: GuiObject, accent, nil)
		else
			handle:SetEnabled(true)
		end
	elseif self._glowHandle then
		self._glowHandle:SetEnabled(false)
	end
end

function GPGlazeMeter:_RenderText()
	local readout = self._readout :: TextLabel?
	if not readout then
		return
	end
	local precision = self._precision or 1
	local format = "%." .. precision .. "f"
	local unit = self.Props.unit or ""
	local text = string.format(format, self._value) .. " / " .. string.format(format, self._max) .. unit
	-- Assign only on change: a per-frame string write on a text label is the
	-- kind of cost that only shows up when twenty meters share a screen.
	if text ~= self._lastText then
		self._lastText = text
		readout.Text = text
	end
end

-- Per-frame work (the Luau side of the boundary): the chase and the sweep.
function GPGlazeMeter:_Tick(dt: number)
	local target = if self._max > 0 then math.clamp(self._value / self._max, 0, 1) else 0
	local reduce = self._reduceMotion == true

	if reduce then
		self._displayed = target
	elseif self._displayed ~= target then
		self._displayed += (target - self._displayed) * math.min(1, dt * (self._chaseRate or CHASE_RATE))
		if math.abs(target - self._displayed) < CHASE_EPSILON then
			self._displayed = target
		end
	end
	local fill = self._fill :: Frame
	local size = UDim2.fromScale(self._displayed, 1)
	if fill.Size ~= size then
		fill.Size = size
	end

	-- Frugal ambient (doc 5.4): the sweep does nothing off-screen, nothing
	-- under reduce-motion, and nothing on an empty bar.
	local sheen = self._sheen :: Frame
	if not sheen.Visible then
		return
	end
	if reduce or self._displayed <= 0 or not UIChrome.IsOnScreen(self.Root) then
		if self._sweepT ~= 0 then
			self._sweepT = 0
			;(self._sweep :: UIGradient).Offset = Vector2.new(-1, 0)
		end
		return
	end
	local seconds = self._sheenSeconds or SHEEN_SECONDS
	self._sweepT = (self._sweepT + dt / seconds) % 1
	-- One pass runs the window from fully before the bar to fully past it.
	;(self._sweep :: UIGradient).Offset = Vector2.new(self._sweepT * 2 - 1, 0)
end

function GPGlazeMeter:_Style(theme: Types.UITheme)
	local props = self.Props
	local studio = dialectTokens(theme, "studio")
	local glaze = dialectTokens(theme, "glaze")
	local motion = dialectTokens(theme, "motion")

	-- ANTI-CONDESCENSION: the readout's precision comes from the studio
	-- dialect (1 decimal here), so a soft-looking meter reports MORE precisely
	-- than the terminal packs' integer rows, never less.
	self._precision = math.max(0, math.floor(props.precision or studio.statPrecision or 1))
	self._chaseRate = tonumber(motion.meterLerpRate) or CHASE_RATE
	self._sheenSeconds = tonumber(glaze.sheenSweepSeconds) or SHEEN_SECONDS

	local accentToken = props.accentToken
	local accent = (accentToken and (theme.Colors :: any)[accentToken]) or theme.Colors.Primary
	local radius = meterRadius(theme, props.radiusToken)
	local barHeight = props.barHeight or DEFAULT_BAR_H

	-- TRACK: the pack's own recessed rail tint, with a soft deepened-tint
	-- hairline. Never black: SoftStroke derives its colour from the fill.
	local track = self._track :: Frame
	local trackFill = theme.Arcade.RulerTrack
	self:_SetColor(track, "BackgroundColor3", trackFill)
	track.BackgroundTransparency = 0 -- clears the born-transparent guard
	track.Size = UDim2.new(1, 0, 0, barHeight)
	if self._trackCorner then
		self._trackCorner:Destroy()
	end
	self._trackCorner = UIStyler.Corner(radius)
	self._trackCorner.Parent = track
	if self._trackStroke then
		self._trackStroke:Destroy()
	end
	self._trackStroke = GPLayoutKit.SoftStroke(theme, track, trackFill)

	-- FILL: the deep end of the pour, with the light end fading down over it.
	local fill = self._fill :: Frame
	local light = self._light :: Frame
	self:_SetColor(fill, "BackgroundColor3", GPLayoutKit.Deepen(theme, accent, FILL_DEEPEN))
	self:_SetColor(light, "BackgroundColor3", accent)
	fill.BackgroundTransparency = 0
	light.BackgroundTransparency = 0
	-- Land the CURRENT ratio here rather than waiting for the first tick: a
	-- restyle (or a build already carrying a value) would otherwise show one
	-- frame of empty track before the chase catches up.
	fill.Size = UDim2.fromScale(self._displayed, 1)
	for _, host in { fill, light } do
		local stale = host:FindFirstChildOfClass("UICorner")
		if stale then
			stale:Destroy()
		end
		UIStyler.Corner(radius).Parent = host
	end

	-- RULER MARKS: the pack's own rule colour where it declares one (GP ships a
	-- sage hairline), the shared RulerTick token otherwise — never a hardcoded
	-- grey. Heights re-derive from barHeight so a caller shrinking the bar keeps
	-- proportional marks instead of ticks taller than their own track.
	local tickTint = studio.rule or theme.Arcade.RulerTick
	local tallPx = math.max(1, math.floor(barHeight * TICK_TALL_SCALE))
	local shortPx = math.max(1, math.floor(barHeight * TICK_SHORT_SCALE))
	for index, tick in self._ticks do
		self:_SetColor(tick, "BackgroundColor3", tickTint)
		tick.BackgroundTransparency = TICK_TRANSPARENCY -- clears the born-transparent guard
		tick.Size = UDim2.fromOffset(1, if index % 2 == 1 then tallPx else shortPx)
	end

	-- SHEEN: opt-in. On by default only under a pack that actually declares a
	-- glaze dialect — a matte pack has no business shimmering, and a pack with
	-- no dialects at all gets a plain, honest bar.
	local wantsSheen = props.sheen
	if wantsSheen == nil then
		wantsSheen = glaze.sheenTransparency ~= nil
	end
	local sheen = self._sheen :: Frame
	sheen.Visible = wantsSheen == true
	if sheen.Visible then
		-- Cream, NEVER white: pure white reads as a render artifact here and
		-- the pack forbids it outright.
		self:_SetColor(sheen, "BackgroundColor3", theme.Colors.Background)
		sheen.BackgroundTransparency = 0 -- the gradient window does the fading
		local stale = sheen:FindFirstChildOfClass("UICorner")
		if stale then
			stale:Destroy()
		end
		UIStyler.Corner(radius).Parent = sheen
		-- Both CLAMPED before they reach the sequence: NumberSequenceKeypoint
		-- throws outside 0..1, and a pack token is caller data, not a promise.
		local peak = math.clamp(tonumber(glaze.sheenTransparency) or 0.72, 0, 1)
		local half = math.clamp(tonumber(glaze.sheenWidthScale) or SHEEN_HALF_WIDTH, 0.02, 0.45)
		-- Built ONCE per restyle, never per frame — only Offset.X moves.
		;(self._sweep :: UIGradient).Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(math.max(0.5 - half, 0.01), 1),
			NumberSequenceKeypoint.new(0.5, peak),
			NumberSequenceKeypoint.new(math.min(0.5 + half, 0.99), 1),
			NumberSequenceKeypoint.new(1, 1),
		})
	end

	-- Text row. MEASURED CONTRAST: TextSecondary was corrected to clear 4.5:1
	-- on this pack's cream, and these labels sit on the page, not on a pastel
	-- fill; the readout takes TextPrimary because a number is the thing the
	-- player came to read. Colors.TextOnPrimary (near-white) is never used at
	-- these sizes — it measures 2.14:1 on rose.
	local textH = theme.TextSizes.Body + 6
	local caption = self._caption :: TextLabel?
	if caption then
		caption.FontFace = theme.Fonts.Body
		caption.TextSize = theme.TextSizes.Body
		caption.TextColor3 = theme.Colors.TextSecondary
		caption.TextTransparency = 0 -- clears the born-transparent guard
		caption.TextTruncate = Enum.TextTruncate.AtEnd
		caption.Size = UDim2.new(0.55, 0, 0, textH)
		caption.Text = props.label or ""
		UIChrome.TextOutline(caption)
	end
	local readout = self._readout :: TextLabel?
	if readout then
		-- Tabular numerals, assigned explicitly: a label that never had
		-- FontFace written keeps a default face and breaks column alignment the
		-- moment the pack's numeric font differs.
		readout.FontFace = theme.Fonts.Numeric
		readout.TextSize = theme.TextSizes.Body
		readout.TextColor3 = theme.Colors.TextPrimary
		readout.TextTransparency = 0 -- clears the born-transparent guard
		readout.AnchorPoint = Vector2.new(1, 0)
		readout.Position = UDim2.fromScale(1, 0)
		readout.Size = UDim2.new(0.45, 0, 0, textH)
		UIChrome.TextOutline(readout)
		self._lastText = "" -- force a repaint at the new precision
		self:_RenderText()
	end

	-- The glow is derived from the accent, so a theme swap must re-derive it.
	-- Release-and-rebuild rather than recolour: Glow's hue lift is computed at
	-- construction from the fill it was handed.
	if self._glowHandle then
		self._glowHandle:Release()
		self._glowHandle = nil
	end
	if self._maxed then
		self:_ApplyMaxed(true)
	end
end

function GPGlazeMeter:Destroy()
	if self._stopTicker then
		self._stopTicker() -- idempotent; the root binding also covers this
		self._stopTicker = nil
	end
	if self._glowHandle then
		self._glowHandle:Release() -- actual teardown: the budget slot returns
		self._glowHandle = nil
	end
	UIComponentBase.Destroy(self)
end

return GPGlazeMeter
