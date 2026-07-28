--!strict
-- Health meter (HUD widget). Near-black §8 ruler track, green arcade fill,
-- 3px black stroke, segment ticks every 25%.
--
-- The one non-obvious part is the REGEN GHOST: a red bar sitting behind the
-- green fill. On damage the green fill snaps/tweens down immediately while the
-- ghost holds at the old value for a beat and then drains to the new one over
-- ~0.5s, so the size of the hit is readable AFTER it has landed (the eye can't
-- read a bar that just teleports). Healing skips the trail entirely — the
-- ghost jumps straight up with the fill, because there is nothing to mourn.

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local HUDWidgetBase = require(script.Parent.HUDWidgetBase)
local GPHUDStyle = require(script.Parent.GPHUDStyle)

local HealthBarWidget = setmetatable({}, { __index = HUDWidgetBase })
HealthBarWidget.__index = HealthBarWidget

-- Ghost timing: hold, then drain over half a second (doc §5 "all springs" —
-- this one is a linear drain because it reads as a quantity leaving, not a
-- surface moving).
local GHOST_HOLD = 0.22
local GHOST_DRAIN = 0.5
local FLASH_IN = TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FLASH_OUT = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FLASH_STRENGTH = 0.4

-- Segment ticks every 25% (the 0/100 edges are already the stroke).
local SEGMENTS = { 0.25, 0.5, 0.75 }
local TICK_TRANSPARENCY = 0.35

function HealthBarWidget.new()
	local self = HUDWidgetBase.new("health", "HealthBarWidget")
	self._value = 780
	self._max = 1000
	self._alpha = 0.78
	self._ghost = 0.78
	self._ghostHold = 0
	self._ghostRate = 0
	self._ticks = {} :: { Frame }
	return setmetatable(self, HealthBarWidget)
end

function HealthBarWidget:_Build(_props: HUDWidgetBase.Props)
	local theme = self.Theme

	local track = UIStyler.Frame("Track")
	track.Size = UDim2.fromScale(1, 1)
	track.ClipsDescendants = true
	UIChrome.Corner("Arcade").Parent = track
	-- Kept rather than parented anonymously: _Style is the only repaint path a
	-- widget gets (they never rebuild on a theme swap), so a rim it cannot reach
	-- is a rim frozen at whatever the boot theme happened to be.
	self._trackStroke = UIChrome.Stroke(theme, "Arcade", "Panel")
	self._trackStroke.Parent = track
	track.Parent = self.Root
	self._track = track

	local ghost = UIStyler.Frame("Ghost")
	ghost.Size = UDim2.fromScale(self._ghost, 1)
	ghost.ZIndex = 1
	ghost.Parent = track
	self._ghostFill = ghost

	local fill = UIStyler.Frame("Fill")
	fill.Size = UDim2.fromScale(self._alpha, 1)
	fill.ZIndex = 2
	UIChrome.GlassGradient().Parent = fill
	fill.Parent = track
	self._fill = fill

	for _, at in SEGMENTS do
		local tick = UIStyler.Frame("Tick")
		tick.AnchorPoint = Vector2.new(0.5, 0)
		tick.Position = UDim2.fromScale(at, 0)
		tick.Size = UDim2.new(0, 1, 1, 0)
		tick.BackgroundTransparency = TICK_TRANSPARENCY
		tick.ZIndex = 3
		tick.Parent = track
		table.insert(self._ticks, tick)
	end

	-- Damage flash: a full-bar red wash. Transparency IS the effect here, which
	-- is the sanctioned exception to "no fades" (doc §5: effect overlays only).
	local flash = UIStyler.Frame("Flash")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundTransparency = 1
	flash.ZIndex = 4
	flash.Parent = track
	self._flash = flash

	local heart = IconArchive.Image(track, "heart", 20)
	heart.AnchorPoint = Vector2.new(0, 0.5)
	heart.Position = UDim2.new(0, 6, 0.5, 0)
	heart.ZIndex = 5
	self._heart = heart

	local value = UIChrome.Text("Value", 17, Color3.new(1, 1, 1))
	value.Size = UDim2.new(1, -16, 1, 0)
	value.Position = UDim2.fromOffset(8, 0)
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.ZIndex = 5
	value.Parent = track
	self._valueText = value

	self:_RenderStep(function(dt: number)
		self:_StepGhost(dt)
	end)
	self:_Render(false)
end

-- data: { health, maxHealth } | { value, max } | a raw number.
function HealthBarWidget:Update(data: any)
	if data == nil then
		return
	end
	local value, max
	if type(data) == "number" then
		value = data
	else
		value = data.health or data.value or data.current
		max = data.maxHealth or data.max or data.maxValue
	end
	self:SetHealth(value or self._value, max)
end

function HealthBarWidget:SetHealth(value: number, max: number?)
	if max and max > 0 then
		self._max = max
	end
	local previous = self._alpha
	self._value = math.clamp(value, 0, self._max)
	self._alpha = self._max > 0 and self._value / self._max or 0
	if self._alpha < previous then
		-- Damage: park the ghost at the old value, then drain it.
		self._ghost = math.max(self._ghost, previous)
		self._ghostHold = GHOST_HOLD
		self._ghostRate = math.max((self._ghost - self._alpha) / GHOST_DRAIN, 0.02)
		self:_Flash()
	else
		self._ghost = self._alpha
		if self._ghostFill then
			self._ghostFill.Size = UDim2.fromScale(self._ghost, 1)
		end
	end
	self:_Render(true)
end

function HealthBarWidget:_Render(animate: boolean)
	if not self._fill then
		return
	end
	local goal = UDim2.fromScale(self._alpha, 1)
	if animate then
		self:_Tween(self._fill, self.Theme.Animations.Emphasis, { Size = goal })
	else
		self._fill.Size = goal
	end
	if self._valueText then
		self._valueText.Text = string.format(
			"%s / %s",
			HUDWidgetBase.Commas(self._value),
			HUDWidgetBase.Commas(self._max)
		)
	end
end

function HealthBarWidget:_StepGhost(dt: number)
	local ghost = self._ghostFill
	if not ghost or self._ghost <= self._alpha + 0.001 then
		return
	end
	if self._ghostHold > 0 then
		self._ghostHold -= dt
		return
	end
	self._ghost = math.max(self._alpha, self._ghost - self._ghostRate * dt)
	ghost.Size = UDim2.fromScale(self._ghost, 1)
end

function HealthBarWidget:_Flash()
	local flash = self._flash
	if not flash then
		return
	end
	local up = self:_Tween(flash, FLASH_IN, { BackgroundTransparency = FLASH_STRENGTH })
	up.Completed:Once(function()
		if flash.Parent then
			self:_Tween(flash, FLASH_OUT, { BackgroundTransparency = 1 })
		end
	end)
end

function HealthBarWidget:_Style(theme: Types.UITheme)
	local arcade = theme.Arcade
	if self._track then
		self._track.BackgroundColor3 = arcade.RulerTrack
	end
	if self._fill then
		self._fill.BackgroundColor3 = arcade.Green
	end
	if self._ghostFill then
		self._ghostFill.BackgroundColor3 = arcade.Red
	end
	if self._flash then
		self._flash.BackgroundColor3 = arcade.Red
	end
	for _, tick in self._ticks do
		tick.BackgroundColor3 = arcade.RulerTick
	end
	if self._valueText then
		self._valueText.FontFace = theme.Fonts.Numeric
		self._valueText.TextColor3 = theme.Colors.TextPrimary
		UIChrome.TextOutline(self._valueText)
	end

	-- GIRLY POP: a thrown rim, not a box. The track becomes a translucent pill
	-- with a hue-matched rose rim and a soft shadow so it floats over the world
	-- instead of cutting a hole in it; the matcha fill and its coral damage
	-- ghost take the same pill so the leading edge reads round as it drains.
	-- Every tick, the segment count, the heart and the "780 / 1,000" readout
	-- stay exactly as authored — a softer meter is not a smaller one.
	GPHUDStyle.Surface(theme, self._track, {
		transparency = GPHUDStyle.Meter,
		radius = theme.Radii.Pill,
		stroke = true,
		strokeIntent = "Panel",
		shadow = "sm",
		sink = self._shadows,
	})
	GPHUDStyle.Surface(theme, self._fill, { keepTransparency = true, radius = theme.Radii.Pill })
	GPHUDStyle.Surface(theme, self._ghostFill, { keepTransparency = true, radius = theme.Radii.Pill })
	GPHUDStyle.Halo(theme, self._valueText)
end

return HealthBarWidget
