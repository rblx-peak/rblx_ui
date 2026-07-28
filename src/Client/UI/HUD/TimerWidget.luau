--!strict
-- Round timer (HUD widget) — the doc §5.3 recipe, verbatim: a FIXED 220×60
-- arcade box at the §7.2 top-centre y=118 slot, gold FredokaOne 48 digits,
-- ticking at 1Hz (doc §11.3).
--
-- THE BOX NEVER RESIZES. Urgency is carried entirely by TextSize, colour and
-- the glow stroke, so the panic never reflows the HUD around it:
--   normal   — the gold glow breathes on sin(t·2.4)
--   final 10 — TextSize oscillates 52→66 on sin(t·10), the colour flashes red
--              (255,70,55) toward near-white, the glow thickens 4→7
-- The digits themselves never change format mid-panic either (§5.3: urgency =
-- size + colour + stroke, never text changes).

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local HUDWidgetBase = require(script.Parent.HUDWidgetBase)
local GPHUDStyle = require(script.Parent.GPHUDStyle)

local TimerWidget = setmetatable({}, { __index = HUDWidgetBase })
TimerWidget.__index = TimerWidget

local TEXT_SIZE = 48
local PANIC_WINDOW = 10
local PANIC_RED = Color3.fromRGB(255, 70, 55)
local PANIC_WHITE = Color3.fromRGB(255, 245, 240)

function TimerWidget.new()
	local self = HUDWidgetBase.new("timer", "TimerWidget")
	self._remaining = 95 -- demo: long enough to watch it fall into the panic
	self._running = true
	self._shown = -1
	self._expired = false
	-- The final-10s flash pair, as fields rather than literals so a pack can
	-- carry its own urgency without touching the choreography: the oscillation,
	-- the window and the size ramp are identical for every style. Defaults ARE
	-- the doc §5.3 constants, so nothing moves unless a theme moves it.
	self._panicHot = PANIC_RED
	self._panicCool = PANIC_WHITE
	-- The RESTING digit + glow pair, for the same reason: classic runs gold
	-- digits in a gold glow on a slate box, which is a legible pairing only
	-- because the box is near-black. A pack on a light box has to move both.
	self._restInk = Color3.fromRGB(245, 190, 55)
	self._restGlow = Color3.fromRGB(245, 190, 55)
	return setmetatable(self, TimerWidget)
end

function TimerWidget:_Build(props: HUDWidgetBase.Props)
	local theme = self.Theme
	if props.seconds then
		self._remaining = props.seconds
	end
	if props.running ~= nil then
		self._running = props.running
	end

	local box = UIChrome.Panel(theme, "Arcade", "Box")
	box.Size = UDim2.fromScale(1, 1)
	box.Parent = self.Root
	self._box = box

	local value = UIChrome.Text("Value", TEXT_SIZE, theme.Arcade.Gold)
	value.Size = UDim2.fromScale(1, 1)
	value.ZIndex = 2
	value.Parent = box
	self._value = value

	-- The breathing/panic glow: a Contextual stroke around the digits, riding
	-- on top of the enforced black text outline.
	local glow = Instance.new("UIStroke")
	glow.Name = "Glow"
	glow.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	glow.LineJoinMode = Enum.LineJoinMode.Round
	glow.Color = theme.Arcade.Gold
	glow.Thickness = 3
	glow.Transparency = 0.45
	glow.Parent = value
	self._glow = glow

	self:_RenderStep(function(dt: number, clock: number)
		self:_Step(dt, clock)
	end)
	self:_RenderText(true)
end

-- data: { seconds, running } | { timer = n } | a raw number of seconds.
function TimerWidget:Update(data: any)
	if data == nil then
		return
	end
	if type(data) == "number" then
		self:SetTime(data)
		return
	end
	local seconds = data.seconds or data.time or data.timer or data.remaining
	if seconds then
		self:SetTime(seconds)
	end
	if data.running ~= nil then
		self._running = data.running
	end
end

function TimerWidget:SetTime(seconds: number)
	self._remaining = math.max(seconds, 0)
	self._expired = self._remaining <= 0
	self:_RenderText(true)
end

function TimerWidget:Start()
	self._running = true
end

function TimerWidget:Stop()
	self._running = false
end

function TimerWidget:GetTime(): number
	return self._remaining
end

function TimerWidget:_Step(dt: number, clock: number)
	if self._running and self._remaining > 0 then
		self._remaining = math.max(self._remaining - dt, 0)
		self:_RenderText(false)
		if self._remaining <= 0 and not self._expired then
			self._expired = true
			local onExpire = self.Props.onExpire
			if onExpire then
				onExpire()
			end
		end
	end
	self:_RenderFx(clock)
end

-- 1Hz: the label is only touched when the whole second changes (doc §11.3).
function TimerWidget:_RenderText(force: boolean)
	local whole = math.floor(self._remaining)
	if not force and whole == self._shown then
		return
	end
	self._shown = whole
	if self._value then
		self._value.Text = UIChrome.FormatCountdown(self._remaining)
	end
end

function TimerWidget:_RenderFx(clock: number)
	local value, glow = self._value, self._glow
	if not (value and glow) then
		return
	end
	-- Both states read PRE-RESOLVED colour fields rather than the theme: the
	-- pairing that makes a countdown legible depends on what is behind it, and
	-- _Style is the only place that knows.
	if self._remaining <= PANIC_WINDOW then
		local s = math.sin(clock * 10)
		value.TextSize = 59 + 7 * s -- 52 → 66
		value.TextColor3 = self._panicHot:Lerp(self._panicCool, (s + 1) / 2)
		glow.Color = self._panicHot
		glow.Transparency = 0
		glow.Thickness = 5.5 + 1.5 * s -- 4 → 7
	else
		value.TextSize = TEXT_SIZE
		value.TextColor3 = self._restInk
		glow.Color = self._restGlow
		glow.Transparency = 0.45
		glow.Thickness = 3 + math.sin(clock * 2.4) -- gentle breathe
	end
end

function TimerWidget:_Style(theme: Types.UITheme)
	if self._box then
		self._box.BackgroundColor3 = theme.Arcade.Panel
	end
	if self._value then
		self._value.FontFace = theme.Fonts.Numeric
		self._value.TextColor3 = theme.Arcade.Gold
		UIChrome.TextOutline(self._value)
	end
	if self._glow then
		self._glow.Color = theme.Arcade.Gold
	end

	-- GIRLY POP: the round timer is the one piece of HUD chrome that carries the
	-- pack's whole signature — a translucent BUTTER tile on the large radius,
	-- a glaze sheen across the top third and a scalloped pie-crust lip hanging
	-- off its bottom edge. Butter is the pack's value colour and the timer is
	-- the most valuable number on screen, so the box takes the gold and the
	-- digits take the ink: gold-on-slate reads at range only because slate is
	-- near-black, and gold digits on any pastel measure ~1.2:1.
	--
	-- THE BOX STILL NEVER RESIZES. The §5.3 panic keeps its window, its 52→66
	-- ramp, its sin(t·10) and its 4→7 glow; only the two colours move — the
	-- fire-engine red becomes a deep plum-coral that still clears large-text
	-- contrast on butter, flashing toward the pack's soft coral, and the glow
	-- carries the alarm hue at full weight. No siren, still unmissable.
	local gp = GPHUDStyle.Active(theme)
	local caramel = theme.Arcade.Gold:Lerp(theme.Colors.TextPrimary, 0.5)
	self._panicHot = if gp then theme.Colors.Error:Lerp(theme.Colors.TextPrimary, 0.4) else PANIC_RED
	self._panicCool = if gp then theme.Colors.Error else PANIC_WHITE
	self._restInk = if gp then theme.Colors.TextPrimary else theme.Arcade.Gold
	self._restGlow = if gp then caramel else theme.Arcade.Gold
	if self._value then
		self._value.TextColor3 = self._restInk
		-- The digits already own a Contextual stroke (the panic glow), and the
		-- engine renders exactly one per object — the emphasis glow would win.
		GPHUDStyle.YieldGlow(theme, self._value)
	end
	if self._glow then
		self._glow.Color = self._restGlow
	end
	GPHUDStyle.Surface(theme, self._box, {
		fill = theme.Arcade.Gold,
		restFill = theme.Arcade.Panel,
		transparency = GPHUDStyle.Plate,
		radius = theme.Radii.Large,
		stroke = true,
		strokeIntent = "Panel",
		glaze = true,
		scallop = true,
	})
end

return TimerWidget
