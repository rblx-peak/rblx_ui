--!strict
-- Fillable bar styled as the Pottery Clash RULER (UI_DESIGN_DOCUMENT.md §8):
-- near-black track, hard 90° corners, 2px black stroke, sunburst-gold fill and
-- 1px pale ticks alternating tall/short every 10% across the track — the same
-- gold the in-world 3D ruler uses, so screen and world measure "the same
-- number". Fill tweens with the theme's Emphasis easing so value changes feel
-- alive.
--
-- Extra props:
--   value, maxValue : numbers (default 0..100)
--   colorToken      : OPTIONAL fill override — a legacy theme Colors token name,
--                      resolved dynamically (e.g. "Success"). When omitted the
--                      fill is the DEFAULT gold ruler fill
--                      (theme.Arcade.SunburstGold, #FFC83C).
--   showText        : boolean, overlay "value / max" centred on the bar
--   label           : string — overlay the METER'S NAME left-aligned on the bar
--                      (e.g. "❤️ Health") with "value/max" right-aligned on the
--                      SAME row, both sitting over the fill. Lets a HUD meter be
--                      just the one bar (name+value baked in) instead of a
--                      separate name row stacked above it. Overrides showText.

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIComponentBase = require(script.Parent.UIComponentBase)

local UIProgressBarComponent = setmetatable({}, { __index = UIComponentBase })
UIProgressBarComponent.__index = UIProgressBarComponent

-- Ruler ticks (doc §8): 1px marks every 10%, alternating tall/short, rendered
-- at 0.35 transparency in the pale RulerTick tint.
local TICK_TALL_PX = 16
local TICK_SHORT_PX = 9
local TICK_TRANSPARENCY = 0.35

function UIProgressBarComponent.new()
	local self = UIComponentBase.new("UIProgressBar")
	self._value = 0
	self._max = 100
	return setmetatable(self, UIProgressBarComponent)
end

function UIProgressBarComponent:_Build(props: Types.UIComponentProps)
	self._value = props.value or 0
	self._max = props.maxValue or 100
	-- nil = the gold ruler default; an explicitly-passed token still wins and
	-- keeps its dynamic Colors lookup (resolved in _Style).
	self._colorToken = props.colorToken

	local root = self.Root
	root.BackgroundTransparency = 0
	if not props.size then
		root.Size = UDim2.new(1, 0, 0, 18)
		self._baseSize = root.Size
	end
	-- Hard 90° corners: arcade family policy (radius 0, no caller can deviate).
	UIChrome.Corner("Arcade").Parent = root
	-- The ruler's own outline needs the theme (2px black under Classic, the
	-- style hairline under styled chrome) — attached in _Style.

	local fill = UIStyler.Frame("Fill")
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = 1
	fill.Parent = root
	self._fill = fill

	-- Tick marks every 10% (skipping the stroked 0/100 edges), alternating
	-- tall/short so 10/30/50/70/90 read as majors. Bottom-anchored like a real
	-- ruler and drawn ABOVE the fill so the markings stay visible across filled
	-- and empty track alike.
	self._ticks = {}
	for k = 1, 9 do
		local tick = UIStyler.Frame("Tick")
		tick.AnchorPoint = Vector2.new(0.5, 1)
		tick.Position = UDim2.new(k / 10, 0, 1, 0)
		tick.Size = UDim2.fromOffset(1, if k % 2 == 1 then TICK_TALL_PX else TICK_SHORT_PX)
		tick.BackgroundTransparency = TICK_TRANSPARENCY
		tick.ZIndex = 2
		tick.Parent = root
		table.insert(self._ticks, tick)
	end

	if props.label then
		-- Name overlay, left-aligned, and value overlay, right-aligned — same
		-- row, both over the fill. UIPadding parented directly to each TextLabel
		-- insets ITS OWN text from the bar's edges.
		local name = UIStyler.TextLabel("Name")
		name.Size = UDim2.new(0.6, 0, 1, 0)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Text = props.label
		name.ZIndex = 3
		UIStyler.PaddingXY(8, 0).Parent = name
		name.Parent = root
		self._nameText = name

		local value = UIStyler.TextLabel("Value")
		value.Size = UDim2.new(0.4, 0, 1, 0)
		value.Position = UDim2.fromScale(0.6, 0)
		value.TextXAlignment = Enum.TextXAlignment.Right
		value.ZIndex = 3
		UIStyler.PaddingXY(8, 0).Parent = value
		value.Parent = root
		self._valueText = value
	elseif props.showText then
		local text = UIStyler.TextLabel("Text")
		text.Size = UDim2.fromScale(1, 1)
		text.ZIndex = 3
		text.Parent = root
		self._text = text
	end

	self:_Render(false)
end

function UIProgressBarComponent:Set(value: number, maxValue: number?)
	self._value = value
	if maxValue then
		self._max = maxValue
	end
	self:_Render(true)
end

function UIProgressBarComponent:_Render(animate: boolean)
	local alpha = self._max > 0 and math.clamp(self._value / self._max, 0, 1) or 0
	if animate and self.Theme then
		self:_Tween(self._fill, self.Theme.Animations.Emphasis, { Size = UDim2.fromScale(alpha, 1) })
	else
		self._fill.Size = UDim2.fromScale(alpha, 1)
	end
	if self._text then
		self._text.Text = string.format("%d / %d", math.floor(self._value), math.floor(self._max))
	end
	if self._valueText then
		self._valueText.Text = string.format("%d/%d", math.floor(self._value), math.floor(self._max))
	end
end

-- Paints the §8 ruler: RulerTrack near-black track, gold fill, RulerTick
-- marks, gold display-font outlined text (Classic: FredokaOne). FontFace is
-- always assigned on the overlay labels (the name may carry emoji —
-- LegacyArial has no glyphs).
function UIProgressBarComponent:_Style(theme: Types.UITheme)
	local arcade = theme.Arcade
	self.Root.BackgroundColor3 = arcade.RulerTrack
	if not self._stroke then
		-- The ruler carries its own 2px black outline (doc §8) — lighter than
		-- the 3px panel stroke, same weight the style enforcer backstops onto
		-- buttons. Styled chrome frames it like every surface (hairline).
		self._stroke = if theme.Chrome ~= nil
			then UIChrome.Stroke(theme, "Arcade")
			else UIStyler.Stroke(Color3.new(0, 0, 0), 2)
		self._stroke.Parent = self.Root
	end
	if theme.Chrome == nil then
		-- Colour only; thickness stays the ruler's own 2px — deliberately NOT
		-- Effects.StrokeThickness (that is the 3px panel/button weight).
		self._stroke.Color = theme.Colors.Stroke
	end
	-- DEFAULT = the gold ruler fill. A caller-passed colorToken still resolves
	-- dynamically against the legacy Colors group (Badge/Highlight parity).
	local fillColor = arcade.SunburstGold
	if self._colorToken then
		fillColor = (theme.Colors :: any)[self._colorToken] or arcade.SunburstGold
	end
	self._fill.BackgroundColor3 = fillColor
	for _, tick in self._ticks do
		tick.BackgroundColor3 = arcade.RulerTick
	end
	-- Label/value text: gold display font with the full black outline (doc §2).
	if self._text then
		self._text.FontFace = theme.Fonts.Numeric
		self._text.TextSize = theme.TextSizes.Small
		self._text.TextColor3 = arcade.SunburstGold
		UIChrome.TextOutline(self._text)
	end
	if self._nameText then
		self._nameText.FontFace = theme.Fonts.Button
		self._nameText.TextSize = theme.TextSizes.Small
		self._nameText.TextColor3 = arcade.SunburstGold
		UIChrome.TextOutline(self._nameText)
	end
	if self._valueText then
		self._valueText.FontFace = theme.Fonts.Numeric
		self._valueText.TextSize = theme.TextSizes.Small
		self._valueText.TextColor3 = arcade.SunburstGold
		UIChrome.TextOutline(self._valueText)
	end
end

return UIProgressBarComponent
