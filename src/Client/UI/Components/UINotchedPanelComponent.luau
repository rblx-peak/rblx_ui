--!strict
-- The ARMORED CORE chamfered panel — the flat black data surface every AC
-- readout sits on.
--
-- DOCUMENTED PLACEHOLDER: the proper build is a notched 9-slice ImageLabel
-- (45° chamfers cut out of two opposing corners), but no notched asset exists
-- in the icon archive yet. Until it does, this renders as a square Frame with
-- the style hairline stroke (UIChrome.Stroke — the AC theme's Chrome policy
-- turns that into a 1px accent line @ 0.4) plus the four corner tick brackets
-- (UICornerTicksComponent) built in, which carries the silhouette's intent.
--
-- -- TODO: notched 9-slice asset
-- Future asset spec: 64x64px source image, 16px slice inset (SliceCenter
-- Rect(16, 16, 48, 48)), 8px 45-degree notch depth on the top-left and
-- bottom-right corners, drawn as a 1px light line on transparent so it can be
-- tinted via ImageColor3 from Colors.Accent. When it lands, swap the Frame
-- for the ImageLabel here; the .Content contract and props do not change.
--
-- Props { size, position, anchorPoint, layoutOrder, ticks: boolean? } —
-- ticks default true. Callers build INTO `.Content`, a transparent inner
-- frame inset by 8px, so panel chrome never collides with panel content.
-- Zero UICorner anywhere: AC law, and a chamfer faked with roundness is worse
-- than no chamfer.

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIComponentBase = require(script.Parent.UIComponentBase)
local UICornerTicksComponent = require(script.Parent.UICornerTicksComponent)

local UINotchedPanelComponent = setmetatable({}, { __index = UIComponentBase })
UINotchedPanelComponent.__index = UINotchedPanelComponent

local CONTENT_INSET = 8

function UINotchedPanelComponent.new()
	local self = UIComponentBase.new("UINotchedPanel")
	return setmetatable(self, UINotchedPanelComponent)
end

function UINotchedPanelComponent:_Build(props: Types.UIComponentProps)
	local root = self.Root
	root.BackgroundTransparency = 0

	local content = UIStyler.Frame("Content")
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(CONTENT_INSET, CONTENT_INSET)
	content.Size = UDim2.new(1, -CONTENT_INSET * 2, 1, -CONTENT_INSET * 2)
	content.Parent = root
	self.Content = content

	-- Corner brackets sit as a later sibling of Content so they always draw
	-- over content that runs to the panel edge.
	if props.ticks ~= false then
		local ticks = UICornerTicksComponent.new()
		ticks:Create(root, {})
		self._ticks = ticks
	end
end

function UINotchedPanelComponent:_Style(theme: Types.UITheme)
	self:_SetColor(self.Root, "BackgroundColor3", theme.Colors.Surface)
	-- Stroke policy lives in UIChrome, and thickness/transparency can change
	-- per style — rebuild rather than re-derive the policy here. Theme swaps
	-- are rare; panels are not.
	local old = self._stroke :: UIStroke?
	if old then
		old:Destroy()
	end
	local stroke = UIChrome.Stroke(theme, "Arcade", "Panel")
	stroke.Parent = self.Root
	self._stroke = stroke
end

function UINotchedPanelComponent:Destroy()
	-- The ticks component holds its own theme registration; release it before
	-- the base destroys the tree.
	local ticks = self._ticks
	if ticks then
		ticks:Destroy()
		self._ticks = nil
	end
	UIComponentBase.Destroy(self)
end

return UINotchedPanelComponent
