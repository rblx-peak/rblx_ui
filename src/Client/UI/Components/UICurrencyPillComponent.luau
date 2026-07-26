--!strict
-- Currency pill (UI_DESIGN_DOCUMENT.md §8): dark slate box 56px tall, 3px
-- black stroke, 40px boxless currency icon left at x=8, FredokaOne 30 value
-- in the currency colour with a full black outline. The HUD parks these
-- bottom-left in a row (widths 220/180/180 × 56, doc §7.2).
--
-- NOT a button: it only displays a balance. The one bit of juice is a Pulse
-- on the inner surface whenever the value CHANGES (never on the initial set).
-- Root stays a fixed transparent footprint so the HUD row never reflows.
--
-- Extra props:
--   currencyId : "Cash" | "Bux" | "Robux" — picks icon + semantic colour
--   value      : number? — initial balance (formatted via ShopConfig.FormatPrice)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIAssets = require(script.Parent.Parent.Config.UIAssets)
local UIComponentBase = require(script.Parent.UIComponentBase)

local UICurrencyPillComponent = setmetatable({}, { __index = UIComponentBase })
UICurrencyPillComponent.__index = UICurrencyPillComponent

local WHITE = Color3.new(1, 1, 1)

function UICurrencyPillComponent.new()
	local self = UIComponentBase.new("UICurrencyPill")
	return setmetatable(self, UICurrencyPillComponent)
end

function UICurrencyPillComponent:_Build(props: Types.UIComponentProps)
	local root = self.Root
	-- Doc §8 default footprint: 220×56 (the Cash pill; Bux passes size 180×56).
	if not props.size then
		root.Size = UDim2.fromOffset(220, 56)
		self._baseSize = root.Size
	end

	self._currencyId = (props.currencyId :: string?) or "Cash"

	-- Inner surface = the visible slate box AND the scale target, so the
	-- value-change pulse pops in place without moving the Root footprint.
	local surface = UIStyler.Frame("Surface")
	surface.BackgroundTransparency = 0
	surface.AnchorPoint = Vector2.new(0.5, 0.5)
	surface.Position = UDim2.fromScale(0.5, 0.5)
	surface.Size = UDim2.fromScale(1, 1)
	UIChrome.Corner("Arcade").Parent = surface -- hard 90° arcade corners
	UIChrome.GlassGradient().Parent = surface -- top-lit glass sheen (§4.1.4)
	surface.Parent = root
	self._surface = surface
	self:_UseScaleTarget(surface)

	-- 40px boxless currency icon at x=8, vertically centred. UIAssets.Icon
	-- carries the graceful image → outlined-glyph fallback chain (doc §10).
	local icon = UIAssets.Icon(surface, self._currencyId, 40)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 8, 0.5, 0)

	-- FredokaOne 30 value with the non-negotiable black outline (UIChrome.Text
	-- assigns FontFace + TextStroke); currency colour lands in _Style.
	local valueLabel = UIChrome.Text("Value", 30, WHITE)
	valueLabel.Position = UDim2.fromOffset(56, 0)
	valueLabel.Size = UDim2.new(1, -64, 1, 0)
	valueLabel.TextXAlignment = Enum.TextXAlignment.Left
	valueLabel.Parent = surface
	self._valueLabel = valueLabel

	local initial = props.value :: number?
	self._value = initial
	valueLabel.Text = if initial ~= nil then ShopConfig.FormatPrice(initial) else ""
end

-- Update the displayed balance. Pulses (§5.1 "chosen!" spike on the inner
-- surface) only when the number actually changes — re-pushes of the same
-- balance stay still.
function UICurrencyPillComponent:SetValue(n: number)
	local changed = self._value ~= nil and self._value ~= n
	self._value = n
	self._valueLabel.Text = ShopConfig.FormatPrice(n)
	if changed then
		self:PlayAnimation("Pulse")
	end
end

function UICurrencyPillComponent:_Style(theme: Types.UITheme)
	local surface = self._surface :: Frame
	self:_SetColor(surface, "BackgroundColor3", theme.Arcade.Panel)
	-- Stroke policy via UIChrome (arcade = always 3px black Border). Created
	-- on first paint because policy needs the theme, which _Build never has.
	if not self._stroke then
		self._stroke = UIChrome.Stroke(theme, "Arcade", "Panel")
		self._stroke.Parent = surface
	end
	-- Semantic law (doc §3.3): Cash = green, Bux = blue, Robux = magenta.
	self:_SetColor(self._valueLabel, "TextColor3", UIChrome.CurrencyColor(theme, self._currencyId))
	-- Re-assert the style's text emphasis AFTER the colour so a styled glow
	-- tracks the currency colour (Classic: the same black outline, unchanged).
	UIChrome.TextOutline(self._valueLabel)
end

return UICurrencyPillComponent
