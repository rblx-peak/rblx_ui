--!strict
-- Stamina meter (HUD widget). The thin sibling of the health bar: same
-- near-black §8 ruler track, gold fill, no text — a meter you read with your
-- peripheral vision while you are busy sprinting.
--
-- It honours the manifest's `hideWhenFull` rule: at 100% the bar waits a beat
-- and fades away so a full HUD isn't cluttered by a meter that says nothing,
-- and it SNAPS back (no tween — you must see it the instant you spend) the
-- moment stamina drops. Spending is instant for the same reason; only regen
-- tweens.

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local HUDWidgetBase = require(script.Parent.HUDWidgetBase)
local GPHUDStyle = require(script.Parent.GPHUDStyle)

local StaminaBarWidget = setmetatable({}, { __index = HUDWidgetBase })
StaminaBarWidget.__index = StaminaBarWidget

local FULL_HOLD = 0.6 -- how long a full bar stays before it fades
local FADE_OUT = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local REGEN = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function StaminaBarWidget.new()
	local self = HUDWidgetBase.new("stamina", "StaminaBarWidget")
	self._value = 68
	self._max = 100
	self._alpha = 0.68
	self._hideWhenFull = true
	self._fullTimer = -1 -- <0 = not counting down to a hide
	self._hidden = false
	-- The meter's REST fill transparency. Opaque under the arcade grammar;
	-- _Style lifts it for packs whose HUD must not cut holes in the world. It
	-- lives here (rather than as a literal in _SnapIn) so the snap-back and the
	-- repaint can never disagree about what "visible" looks like.
	self._restFill = 0
	return setmetatable(self, StaminaBarWidget)
end

function StaminaBarWidget:_Build(props: HUDWidgetBase.Props)
	local theme = self.Theme
	local entry = self.Entry
	if props.hideWhenFull ~= nil then
		self._hideWhenFull = props.hideWhenFull
	elseif entry then
		self._hideWhenFull = entry.hideWhenFull == true
	end

	local track = UIStyler.Frame("Track")
	track.Size = UDim2.fromScale(1, 1)
	track.ClipsDescendants = true
	UIChrome.Corner("Arcade").Parent = track
	-- "Wheel" is UIChrome's LIGHT chrome intent (1.2px black instead of the
	-- 3px panel border): on a 14px-tall meter the full arcade border would be
	-- almost half the bar. Policy still comes from UIChrome, not from here.
	self._stroke = UIChrome.Stroke(theme, "Arcade", "Wheel")
	self._stroke.Parent = track
	track.Parent = self.Root
	self._track = track

	local fill = UIStyler.Frame("Fill")
	fill.Size = UDim2.fromScale(self._alpha, 1)
	UIChrome.GlassGradient().Parent = fill
	fill.Parent = track
	self._fill = fill

	self:_RenderStep(function(dt: number)
		self:_StepHide(dt)
	end)
end

-- data: { stamina, maxStamina } | { value, max } | a raw number.
function StaminaBarWidget:Update(data: any)
	if data == nil then
		return
	end
	local value, max
	if type(data) == "number" then
		value = data
	else
		value = data.stamina or data.value or data.current
		max = data.maxStamina or data.max or data.maxValue
	end
	self:SetStamina(value or self._value, max)
end

function StaminaBarWidget:SetStamina(value: number, max: number?)
	if max and max > 0 then
		self._max = max
	end
	local previous = self._alpha
	self._value = math.clamp(value, 0, self._max)
	self._alpha = self._max > 0 and self._value / self._max or 0

	local goal = UDim2.fromScale(self._alpha, 1)
	if self._fill then
		if self._alpha < previous then
			self._fill.Size = goal -- spending reads instantly
		else
			self:_Tween(self._fill, REGEN, { Size = goal })
		end
	end

	if self._alpha < 0.999 then
		self._fullTimer = -1
		self:_SnapIn()
	elseif self._hideWhenFull and self._fullTimer < 0 and not self._hidden then
		self._fullTimer = FULL_HOLD
	end
end

function StaminaBarWidget:_StepHide(dt: number)
	if self._fullTimer < 0 then
		return
	end
	self._fullTimer -= dt
	if self._fullTimer > 0 then
		return
	end
	self._fullTimer = -1
	self._hidden = true
	local track, fill, stroke = self._track, self._fill, self._stroke
	if track then
		self:_Tween(track, FADE_OUT, { BackgroundTransparency = 1 })
	end
	if fill then
		self:_Tween(fill, FADE_OUT, { BackgroundTransparency = 1 })
	end
	if stroke then
		self:_Tween(stroke, FADE_OUT, { Transparency = 1 })
	end
end

-- Snap in: cancel any in-flight fade and set the transparencies directly. A
-- tween here would mean the player spends stamina before the meter admits it.
function StaminaBarWidget:_SnapIn()
	if not self._hidden and self._fullTimer < 0 then
		return
	end
	self._hidden = false
	for _, tween in self._tweens do
		tween:Cancel()
	end
	table.clear(self._tweens)
	if self._track then
		self._track.BackgroundTransparency = self._restFill
	end
	if self._fill then
		self._fill.BackgroundTransparency = self._restFill
	end
	if self._stroke then
		-- Back to the style's REST transparency: Classic wheel chrome is
		-- opaque, styled hairlines carry their own (e.g. 0.4).
		local chrome = self.Theme.Chrome
		self._stroke.Transparency = if chrome then chrome.StrokeTransparency else 0
	end
end

function StaminaBarWidget:_Style(theme: Types.UITheme)
	local arcade = theme.Arcade
	if self._track then
		self._track.BackgroundColor3 = arcade.RulerTrack
	end
	if self._fill then
		self._fill.BackgroundColor3 = arcade.SunburstGold
	end
	if self._stroke then
		self._stroke.Color = theme.Colors.Stroke
	end

	-- GIRLY POP: the thin sibling of the health rim — same pill, same soft
	-- shadow, butter fill. `keepTransparency` on both is deliberate: this widget
	-- OWNS its transparencies (hideWhenFull fades the track, the fill and the
	-- stroke out, _SnapIn puts them back), and a repaint that reset them would
	-- pop a hidden meter back on screen mid-fade — so the rest value is moved
	-- instead, and only applied while the meter is actually up. The rim colour
	-- is likewise the widget's own line above: the pack's Colors.Stroke is
	-- already a deepened rose, so law 1 is satisfied without the pass touching it.
	self._restFill = if GPHUDStyle.Active(theme) then GPHUDStyle.Meter else 0
	if not self._hidden and self._fullTimer < 0 then
		if self._track then
			self._track.BackgroundTransparency = self._restFill
		end
		if self._fill then
			self._fill.BackgroundTransparency = self._restFill
		end
	end
	GPHUDStyle.Surface(theme, self._track, {
		keepTransparency = true,
		radius = theme.Radii.Pill,
		shadow = "sm",
		sink = self._shadows,
	})
	GPHUDStyle.Surface(theme, self._fill, { keepTransparency = true, radius = theme.Radii.Pill })
end

return StaminaBarWidget
