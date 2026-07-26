--!strict
-- RGB color editor row: a name, a live swatch, and three sliders. This is the
-- per-color control the Theme Editor stacks for every color token. Reports the
-- composed Color3 via onChanged on every slider move, driving live re-theming.
--
-- STUDIO family (the Theme Editor is this project's ceramic "workbench",
-- doc §1/§4.2): the row itself is boxless (transparent) so it sits quietly on
-- the chocolate panel behind it; the label is display-font cream ink with the
-- non-negotiable black outline; the swatch is a soft 10px "tool" square carrying
-- the cream swatch ring (doc §4.3 glaze-swatch language). The three RGB channel
-- sliders are stock UISliderComponents (compact mode) and pick up the studio
-- slider recipe from their own restyle — nothing slider-specific lives here.
--
-- Extra props:
--   label     : token display name
--   value     : Color3 initial
--   onChanged : (color: Color3) -> ()

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIComponentBase = require(script.Parent.UIComponentBase)
local UISliderComponent = require(script.Parent.UISliderComponent)

local UIColorFieldComponent = setmetatable({}, { __index = UIComponentBase })
UIColorFieldComponent.__index = UIColorFieldComponent

function UIColorFieldComponent.new()
	local self = UIComponentBase.new("UIColorField")
	self._sliders = {}
	return setmetatable(self, UIColorFieldComponent)
end

function UIColorFieldComponent:_Build(props: Types.UIComponentProps)
	local color = (props.value :: Color3?) or Color3.new(1, 1, 1)
	self._color = color

	-- Boxless row: the chocolate panel behind the stack is the surface.
	local root = self.Root
	root.BackgroundTransparency = 1
	if not props.size then
		root.Size = UDim2.new(1, 0, 0, 92)
		self._baseSize = root.Size
	end
	UIStyler.Padding(8).Parent = root

	local header = UIStyler.Frame("Header")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0.28, 0)
	header.Parent = root

	-- Swatch is a perfect square (AspectRatioConstraint 1:1, DominantAxis
	-- Height) instead of a fixed pixel Offset, so it scales with the header's
	-- real resolved height. Starting size is non-zero on both axes (never
	-- Scale=0) — an AspectRatioConstraint driving a Scale=0 starting
	-- dimension collapses to 0x0 instead of resolving correctly.
	local swatch = UIStyler.Frame("Swatch")
	swatch.Size = UDim2.fromScale(0.3, 1)
	UIStyler.AspectRatio(1, Enum.DominantAxis.Height).Parent = swatch
	swatch.BackgroundColor3 = color
	-- Studio "tool" square (corner 10); the cream swatch ring is themed on in
	-- _Style (it needs the live theme's cream token).
	UIChrome.Corner("Studio", "Tool").Parent = swatch
	swatch.Parent = header
	self._swatch = swatch

	-- Token name: display font (FredokaOne 14) with the mandatory black
	-- outline — UIChrome.Text owns that policy; _Style paints the cream ink.
	local name = UIChrome.Text("Name", 14, Color3.new(1, 1, 1))
	name.Size = UDim2.fromScale(0.84, 1)
	name.Position = UDim2.fromScale(0.16, 0)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Text = props.label or "Color"
	self._nameConstraint = UIStyler.TextSizeConstraint(14, 8)
	self._nameConstraint.Parent = name
	-- Long-text safety (doc §2): FredokaOne runs wide, so long token names
	-- shrink-to-fit under the 14px cap. TextScaled is assigned LAST of the
	-- wrap-related properties (engine landmine).
	name.TextScaled = true
	name.Parent = header
	self._name = name

	-- Three channel sliders laid out below the header.
	local sliderHolder = UIStyler.Frame("Channels")
	sliderHolder.BackgroundTransparency = 1
	sliderHolder.Size = UDim2.new(1, 0, 0.72, 0)
	sliderHolder.Position = UDim2.new(0, 0, 0.28, 0)
	UIStyler.ListLayout({ Padding = UDim.new(0, 2) }).Parent = sliderHolder
	sliderHolder.Parent = root

	local channels = { "R", "G", "B" }
	local components = { color.R * 255, color.G * 255, color.B * 255 }
	for i, channel in channels do
		local slider = UISliderComponent.new()
		slider:Create(sliderHolder, {
			label = channel,
			compact = true,
			min = 0,
			max = 255,
			step = 1,
			decimals = 0,
			value = math.round(components[i]),
			layoutOrder = i,
			size = UDim2.new(1, 0, 0, 20),
			onChanged = function()
				self:_Recompose()
			end,
		})
		self._sliders[channel] = slider
	end
end

function UIColorFieldComponent:_Recompose()
	local r = self._sliders.R:GetValue() / 255
	local g = self._sliders.G:GetValue() / 255
	local b = self._sliders.B:GetValue() / 255
	self._color = Color3.new(r, g, b)
	self._swatch.BackgroundColor3 = self._color
	if self.Props.onChanged then
		self.Props.onChanged(self._color)
	end
end

function UIColorFieldComponent:GetColor(): Color3
	return self._color
end

function UIColorFieldComponent:_Style(theme: Types.UITheme)
	-- Cream ink on the dark chocolate panel behind the row; the style's text
	-- emphasis is re-asserted AFTER the colour so a styled glow tracks it.
	self._name.TextColor3 = theme.Studio.TextLight
	UIChrome.TextOutline(self._name)
	-- The cream swatch ring (doc §4.3): created through UIChrome on first
	-- paint so the stroke policy stays central; under Classic, later theme
	-- swaps only need the cream token repainted.
	if not self._swatchRing then
		local ring = UIChrome.Stroke(theme, "Studio", "Swatch")
		ring.Parent = self._swatch
		self._swatchRing = ring
	elseif theme.Chrome == nil then
		-- Classic repaint only: the cream token can move under the live editor.
		-- A styled chrome's ring is policy-owned — never repaint it cream.
		self._swatchRing.Color = theme.Studio.Card
	end
end

function UIColorFieldComponent:Destroy()
	for _, slider in self._sliders do
		slider:Destroy()
	end
	UIComponentBase.Destroy(self)
end

return UIColorFieldComponent
