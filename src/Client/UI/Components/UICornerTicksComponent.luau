--!strict
-- Four L-shaped corner brackets — the ARMORED CORE "targeting frame" motif.
-- Each corner is two hairline Frames (an L of 1px legs) in Colors.Accent,
-- inset from the panel corners. Opt-in per panel: parent it into any surface
-- and the brackets hug that surface's corners. UINotchedPanelComponent builds
-- one of these in by default.
--
-- Extra props (all optional, px at the 1650×1020 baseline):
--   inset     : distance from each corner (default 4)
--   length    : leg length of each L (default 8)
--   thickness : leg thickness (default 1 — hairline)
--
-- The root is a transparent full-bleed frame (Active = false, so it never
-- eats input). _Style recolours every leg from Colors.Accent on live theme
-- swaps; Destroy is inherited (no connections, no extra state).

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIComponentBase = require(script.Parent.UIComponentBase)

local UICornerTicksComponent = setmetatable({}, { __index = UIComponentBase })
UICornerTicksComponent.__index = UICornerTicksComponent

local DEFAULT_INSET = 4
local DEFAULT_LENGTH = 8
local DEFAULT_THICKNESS = 1

function UICornerTicksComponent.new()
	local self = UIComponentBase.new("UICornerTicks")
	return setmetatable(self, UICornerTicksComponent)
end

-- One hairline leg. BackgroundColor3 is painted in _Style.
local function leg(name: string, anchor: Vector2, position: UDim2, size: UDim2): Frame
	local frame = UIStyler.Frame(name)
	frame.AnchorPoint = anchor
	frame.Position = position
	frame.Size = size
	return frame
end

function UICornerTicksComponent:_Build(props: Types.UIComponentProps)
	local root = self.Root
	root.Active = false

	local inset = (props.inset :: number?) or DEFAULT_INSET
	local length = (props.length :: number?) or DEFAULT_LENGTH
	local thickness = (props.thickness :: number?) or DEFAULT_THICKNESS

	local horizontal = UDim2.fromOffset(length, thickness)
	local vertical = UDim2.fromOffset(thickness, length)

	local legs: { Frame } = {
		-- Top-left
		leg("TLH", Vector2.new(0, 0), UDim2.fromOffset(inset, inset), horizontal),
		leg("TLV", Vector2.new(0, 0), UDim2.fromOffset(inset, inset), vertical),
		-- Top-right
		leg("TRH", Vector2.new(1, 0), UDim2.new(1, -inset, 0, inset), horizontal),
		leg("TRV", Vector2.new(1, 0), UDim2.new(1, -inset, 0, inset), vertical),
		-- Bottom-left
		leg("BLH", Vector2.new(0, 1), UDim2.new(0, inset, 1, -inset), horizontal),
		leg("BLV", Vector2.new(0, 1), UDim2.new(0, inset, 1, -inset), vertical),
		-- Bottom-right
		leg("BRH", Vector2.new(1, 1), UDim2.new(1, -inset, 1, -inset), horizontal),
		leg("BRV", Vector2.new(1, 1), UDim2.new(1, -inset, 1, -inset), vertical),
	}
	for _, frame in legs do
		frame.BackgroundTransparency = 0
		frame.Parent = root
	end
	self._legs = legs
end

function UICornerTicksComponent:_Style(theme: Types.UITheme)
	for _, frame in self._legs :: { Frame } do
		self:_SetColor(frame, "BackgroundColor3", theme.Colors.Accent)
	end
end

return UICornerTicksComponent
