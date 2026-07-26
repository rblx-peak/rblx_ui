--!strict
-- The house slider — §8 recipe GEOMETRY on ARCADE colours (the chocolate
-- studio palette read as dated on menus, per the owner):
--
--   * label      : body font 12 in ice blue (Classic: GothamMedium — quiet
--                  caption, no outline)
--   * rail       : 12px recessed near-black ruler track, hard corners
--   * fill       : 6px accent-gold bar vertically centred in the rail
--   * knob       : 26px white circle that swells to 1.15× while held
--   * ticks      : 2px ruler-tick notches at the step snap points
--   * bubble     : slate chip above the knob with the current value,
--                  visible only while dragging (fades — allowed: effect overlay)
--
-- Reports the live value via onChanged as the user drags — this is what powers
-- real-time theme preview.
--
-- Extra props:
--   labelKey / label
--   min, max  : number range (default 0..1)
--   step      : optional snap increment (also draws the tick notches)
--   value     : initial value
--   decimals  : digits shown in the value bubble (default 2)
--   compact   : single-row layout (label | rail) for dense controls
--   onChanged : (value: number) -> ()

local UserInputService = game:GetService("UserInputService")

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local TextConfig = require(script.Parent.Parent.Config.TextConfig)
local UIComponentBase = require(script.Parent.UIComponentBase)

local UISliderComponent = setmetatable({}, { __index = UIComponentBase })
UISliderComponent.__index = UISliderComponent

-- §8 recipe numbers, authored in px at the 1650×1020 baseline.
local RAIL_HEIGHT = 12
local FILL_HEIGHT = 6
local KNOB_SIZE = 26
local KNOB_HELD_SCALE = 1.15
local TICK_WIDTH = 2
local TICK_TRANSPARENCY = 0.5
-- Notches stay readable: a 0–255 step-1 channel slider would paint hundreds
-- of marks, so past this interior count the rail stays clean.
local MAX_TICKS = 24
local BUBBLE_WIDTH = 56
local BUBBLE_HEIGHT = 22
local BUBBLE_TEXT_SIZE = 11 -- doc §2: 11 = micro (badges, value bubbles)
local BUBBLE_GAP = 5

-- Nil-theme fallback only (theme is always present after Create).
local FALLBACK_FADE = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function UISliderComponent.new()
	local self = UIComponentBase.new("UISlider")
	self._value = 0
	self._dragging = false
	self._ticks = {}
	return setmetatable(self, UISliderComponent)
end

function UISliderComponent:_Build(props: Types.UIComponentProps)
	self._min = props.min or 0
	self._max = props.max or 1
	self._step = props.step
	self._decimals = props.decimals or 2
	self._value = math.clamp(props.value or self._min, self._min, self._max)

	-- Compact = single row (label · rail), for dense controls like the color
	-- channel editors. Stacked = the §8 anatomy verbatim: label caption over a
	-- full-width rail. One component, two layouts, so the two never drift apart.
	self._compact = props.compact == true
	local root = self.Root
	root.BackgroundTransparency = 1
	if not props.size then
		root.Size = UDim2.new(1, 0, 0, self._compact and 22 or 44)
		self._baseSize = root.Size
	end

	-- Label: the quiet body-font 12 caption (ice blue, no outline — body
	-- text stays clean per doc §2; the FontFace lands in _Style from
	-- theme.Fonts.Body). Fixed px, not TextScaled.
	local label = UIStyler.TextLabel("Label")
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = TextConfig.Resolve(props.labelKey or props.label)
	self._label = label

	-- Track: the transparent full-height hit surface the drag math reads.
	-- The visible 12px rail is a child, so the finger target stays generous.
	local track = Instance.new("TextButton")
	track.Name = "Track"
	track.Text = ""
	track.AutoButtonColor = false
	track.BackgroundTransparency = 1
	track.BorderSizePixel = 0
	self._track = track

	if self._compact then
		-- One row: label (left) | rail (fills the rest).
		label.Size = UDim2.fromScale(0.16, 1)
		label.Parent = root
		track.AnchorPoint = Vector2.new(1, 0)
		track.Position = UDim2.fromScale(1, 0)
		track.Size = UDim2.fromScale(0.81, 1)
		track.Parent = root
	else
		-- Caption row stacked over a full-width rail.
		label.Size = UDim2.new(1, 0, 0, 16)
		label.Parent = root
		track.Position = UDim2.new(0, 0, 0, 16)
		track.Size = UDim2.new(1, 0, 1, -16)
		track.Parent = root
	end

	-- Rail: 12px recessed near-black ruler track, hard corners.
	local rail = UIStyler.Frame("Rail")
	rail.AnchorPoint = Vector2.new(0, 0.5)
	rail.Position = UDim2.fromScale(0, 0.5)
	rail.Size = UDim2.new(1, 0, 0, RAIL_HEIGHT)
	UIChrome.Corner("Arcade").Parent = rail
	rail.Parent = track
	self._rail = rail

	-- Fill: the 6px honey bar, vertically centred in the rail.
	local fill = UIStyler.Frame("Fill")
	fill.AnchorPoint = Vector2.new(0, 0.5)
	fill.Position = UDim2.fromScale(0, 0.5)
	fill.Size = UDim2.new(0, 0, 0, FILL_HEIGHT)
	fill.ZIndex = 2
	UIChrome.Corner("Arcade").Parent = fill
	fill.Parent = rail
	self._fill = fill

	self:_BuildTicks()

	-- Knob: 26px white circle. Its swell is a UIScale tween (never a Size
	-- change) so nothing ever reflows.
	local knob = UIStyler.Frame("Knob")
	knob.Size = UDim2.fromOffset(KNOB_SIZE, KNOB_SIZE)
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(0, 0.5)
	knob.ZIndex = 3
	UIChrome.Corner("Arcade", "Pill").Parent = knob
	knob.Parent = track
	self._knob = knob

	local knobScale = Instance.new("UIScale")
	knobScale.Parent = knob
	self._knobScale = knobScale

	-- Value bubble: a PanelDeep pill above the knob, only while dragging.
	-- Starts fully faded; _SetDragging fades it in/out (an effect overlay —
	-- the one place opacity tweens are allowed).
	local bubble = UIStyler.Frame("Bubble")
	bubble.AnchorPoint = Vector2.new(0.5, 1)
	bubble.Size = UDim2.fromOffset(BUBBLE_WIDTH, BUBBLE_HEIGHT)
	bubble.BackgroundTransparency = 1
	bubble.Visible = false
	bubble.ZIndex = 4
	UIChrome.Corner("Arcade").Parent = bubble
	bubble.Parent = track
	self._bubble = bubble

	-- Micro display text (11px, outlined; Classic: FredokaOne). FontFace is
	-- always assigned explicitly — in _Style, from theme.Fonts.Numeric —
	-- never left to the default font.
	local bubbleText = UIStyler.TextLabel("BubbleValue")
	bubbleText.TextSize = BUBBLE_TEXT_SIZE
	bubbleText.TextTransparency = 1
	UIChrome.TextOutline(bubbleText, 1)
	bubbleText.ZIndex = 5
	bubbleText.Parent = bubble
	self._bubbleText = bubbleText

	self:_Connect(track.MouseButton1Down, function()
		self:_SetDragging(true)
		self:_UpdateFromInput()
	end)
	self:_Connect(UserInputService.InputEnded, function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self:_SetDragging(false)
		end
	end)
	self:_Connect(UserInputService.InputChanged, function(input: InputObject)
		if self._dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			self:_UpdateFromInput()
		end
	end)

	self:_Render()
end

-- Tick notches at the step snap points (§8): 2px tan marks at 0.5
-- transparency along the rail. Interior points only — the rail's own ends
-- already read as the min/max stops.
function UISliderComponent:_BuildTicks()
	local step = self._step
	local range = self._max - self._min
	if not step or step <= 0 or range <= 0 then
		return
	end
	local count = math.floor(range / step + 0.5) - 1
	if count < 1 or count > MAX_TICKS then
		return
	end
	for i = 1, count do
		local alpha = (i * step) / range
		if alpha >= 1 then
			break
		end
		local tick = UIStyler.Frame("Tick")
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.Position = UDim2.fromScale(alpha, 0.5)
		tick.Size = UDim2.new(0, TICK_WIDTH, 1, 0)
		tick.BackgroundTransparency = TICK_TRANSPARENCY
		tick.ZIndex = 3 -- above the honey fill
		tick.Parent = self._rail
		table.insert(self._ticks, tick)
	end
end

-- Held-state juice: the knob swells to 1.15× while held and the value bubble
-- fades in above it; both reverse on release. Guarded so the global
-- InputEnded listener doesn't re-fire the exit tweens on every mouse-up.
function UISliderComponent:_SetDragging(held: boolean)
	if self._dragging == held then
		return
	end
	self._dragging = held

	local theme = self.Theme
	local swellInfo = if theme
		then (if held then theme.Motion.HoverIn else theme.Motion.HoverOut)
		else FALLBACK_FADE
	local fadeInfo = if theme then theme.Motion.HoverOut else FALLBACK_FADE
	self:_Tween(self._knobScale, swellInfo, { Scale = if held then KNOB_HELD_SCALE else 1 })

	local bubble = self._bubble
	local bubbleText = self._bubbleText
	-- Classic fades the black TextStroke outline with the text; glow styles
	-- (Chrome.TextOutline = false) park TextStroke at 1 and fade the TextGlow
	-- stroke UIChrome.TextOutline attached instead — never the black halo.
	local chrome = UIChrome.ActiveChrome()
	local glow = bubbleText:FindFirstChild("TextGlow") :: UIStroke?
	if held then
		bubble.BackgroundTransparency = 1
		bubbleText.TextTransparency = 1
		bubbleText.TextStrokeTransparency = 1
		if glow then
			glow.Transparency = 1
		end
		bubble.Visible = true
		self:_Tween(bubble, fadeInfo, { BackgroundTransparency = 0 })
		self:_Tween(bubbleText, fadeInfo, {
			TextTransparency = 0,
			TextStrokeTransparency = if chrome.TextOutline then 0 else 1,
		})
		if glow then
			self:_Tween(glow, fadeInfo, { Transparency = chrome.TextGlowTransparency })
		end
	else
		self:_Tween(bubble, fadeInfo, { BackgroundTransparency = 1 })
		if glow then
			self:_Tween(glow, fadeInfo, { Transparency = 1 })
		end
		local out = self:_Tween(bubbleText, fadeInfo, { TextTransparency = 1, TextStrokeTransparency = 1 })
		out.Completed:Once(function()
			if not self._dragging then
				bubble.Visible = false
			end
		end)
	end
end

function UISliderComponent:_UpdateFromInput()
	local mouse = UserInputService:GetMouseLocation()
	local absPos = self._track.AbsolutePosition.X
	local absSize = self._track.AbsoluteSize.X
	local alpha = absSize > 0 and math.clamp((mouse.X - absPos) / absSize, 0, 1) or 0
	self:Set(self._min + alpha * (self._max - self._min), true)
end

function UISliderComponent:Set(value: number, notify: boolean?)
	if self._step then
		value = math.floor(value / self._step + 0.5) * self._step
	end
	value = math.clamp(value, self._min, self._max)
	self._value = value
	self:_Render()
	if notify and self.Props.onChanged then
		self.Props.onChanged(value)
	end
end

function UISliderComponent:GetValue(): number
	return self._value
end

function UISliderComponent:_Render()
	local range = self._max - self._min
	local alpha = range > 0 and (self._value - self._min) / range or 0
	self._fill.Size = UDim2.new(alpha, 0, 0, FILL_HEIGHT)
	self._knob.Position = UDim2.fromScale(alpha, 0.5)
	self._bubble.Position = UDim2.new(alpha, 0, 0.5, -(KNOB_SIZE / 2 + BUBBLE_GAP))
	self._bubbleText.Text = string.format("%." .. self._decimals .. "f", self._value)
end

-- Arcade colours (owner's call: the chocolate/honey studio controls read as
-- dated everywhere they appeared). Geometry keeps the §8 recipe — recessed
-- rail, thin fill, swelling knob, drag-only bubble — only the palette moved:
-- near-black ruler track, accent-gold fill, white knob, slate bubble.
function UISliderComponent:_Style(theme: Types.UITheme)
	local a = theme.Arcade
	self._label.FontFace = theme.Fonts.Body
	self._bubbleText.FontFace = theme.Fonts.Numeric
	self:_SetColor(self._label, "TextColor3", a.IceBlue)
	self:_SetColor(self._rail, "BackgroundColor3", a.RulerTrack)
	self:_SetColor(self._fill, "BackgroundColor3", a.Gold)
	self:_SetColor(self._knob, "BackgroundColor3", theme.Colors.TextPrimary)
	for _, tick in self._ticks do
		self:_SetColor(tick, "BackgroundColor3", a.RulerTick)
	end
	self:_SetColor(self._bubble, "BackgroundColor3", a.Panel)
	self:_SetColor(self._bubbleText, "TextColor3", theme.Colors.TextPrimary)
	-- Glow styles only: the TextGlow stroke UIChrome.TextOutline attached at
	-- build time captured the label's PRE-style colour — keep it matched to
	-- the live text colour (Classic has no TextGlow child; no-op there).
	local glow = self._bubbleText:FindFirstChild("TextGlow") :: UIStroke?
	if glow then
		glow.Color = theme.Colors.TextPrimary
	end
end

return UISliderComponent
