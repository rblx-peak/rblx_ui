--!strict
-- Arcade micro-badge ("NEW", "RARE", ...) — doc §2 type scale: 11 micro
-- (badges, value bubbles). Hard 90° corners, 2px black stroke, the arcade
-- bevel on the fill, FredokaOne with the full black text outline. Colour IS
-- meaning (doc §3.3): each tag variant maps straight into the Arcade palette.
--
-- Extra props:
--   text / textKey
--   variant : "New" | "Sale" | "Rare" | "Limited" | "Popular" | Colors token name

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local TextConfig = require(script.Parent.Parent.Config.TextConfig)
local TextScaleConfig = require(script.Parent.Parent.Config.TextScaleConfig)
local UIComponentBase = require(script.Parent.UIComponentBase)

local UIBadgeComponent = setmetatable({}, { __index = UIComponentBase })
UIBadgeComponent.__index = UIBadgeComponent

-- Doc §2 type scale: `11` micro is the badge size. Routed through
-- TextScaleConfig.ScaledCap so the Theme Editor's live multiplier still applies.
local MICRO_TEXT_SIZE = 11

-- Maps a tag variant to an Arcade palette key (doc §3.2). A variant that isn't
-- listed here still resolves as a direct Colors token name, then Primary.
local VARIANT_ARCADE: { [string]: string } = {
	New = "Green",
	Sale = "Red",
	Rare = "Magenta",
	Limited = "Orange",
	Popular = "Blue",
}

function UIBadgeComponent.new()
	local self = UIComponentBase.new("UIBadge")
	return setmetatable(self, UIBadgeComponent)
end

function UIBadgeComponent:_Build(props: Types.UIComponentProps)
	local root = self.Root
	root.BackgroundTransparency = 0
	root.AutomaticSize = Enum.AutomaticSize.X
	if not props.size then
		-- Compact chip: the colour already makes it pop, so it stays small and
		-- doesn't crowd the more important name/price/buy. Height FILLS the
		-- parent row exactly (both callers always parent into a row/badgeArea
		-- frame already sized to CardSpacing.Height.TagRow, Scale or pixel) —
		-- this can't drift out of sync with the row because it never computes
		-- its own height independently.
		root.Size = UDim2.fromScale(0, 1)
		self._baseSize = UDim2.fromScale(0, 1)
	end

	-- HARD ARCADE corners: policy is 0px, no caller can deviate (doc §4.1.1).
	UIChrome.Corner("Arcade").Parent = root
	-- Micro chrome border attaches on first _Style: Classic keeps the doc
	-- §4.1.3 2px small-solid weight (thinner than the 3px panel stroke so the
	-- tiny chip isn't all edge, painted from theme.Colors.Stroke); a styled
	-- chrome (theme.Chrome) frames the chip through the UIChrome policy.
	-- The arcade bevel (doc §4.1.3): vertical multiply, white at the top to
	-- RGB(140,140,140) at the bottom, on the saturated fill.
	self._gradient = UIChrome.ArcadeBevel()
	self._gradient.Parent = root
	-- NO UIPadding here: root is AutomaticSize.X off the label, and the label
	-- is ALSO AutomaticSize.X — a UIPadding on root fighting that combination
	-- produced unstable/incorrect sizing (confirmed by direct testing across
	-- packs). The label is instead given a bit of extra horizontal room
	-- directly via the literal-space padding in SetContent.

	local label = UIStyler.TextLabel("Label")
	-- AutomaticSize.X stays (root itself AutomaticSizes off this label's real
	-- text width, so the chip hugs the text) — but the text scales via
	-- TextScaled capped at the doc's 11px micro size. Height is 0.8 of the
	-- badge's own height (not the full 1), so the glyph doesn't fill the chip
	-- edge-to-edge vertically.
	label.AutomaticSize = Enum.AutomaticSize.X
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.fromScale(0, 0.5)
	label.Size = UDim2.fromScale(0, 0.8)
	-- The non-negotiable black text outline (doc §2).
	UIChrome.TextOutline(label)
	-- TextScaled must be the LAST text-wrap-related assignment — setting
	-- TextWrapped afterward (even to false) silently reverts TextScaled back
	-- to false (confirmed via a live Studio test). AutomaticSize.X growing to
	-- fit the unwrapped text means wrapping never actually triggers anyway.
	label.TextScaled = true
	self._labelConstraint = UIStyler.TextSizeConstraint(TextScaleConfig.ScaledCap(MICRO_TEXT_SIZE), 6)
	self._labelConstraint.Parent = label
	label.Parent = root
	self._label = label

	self:SetContent(props)
end

function UIBadgeComponent:SetContent(props: Types.UIComponentProps)
	-- Leading/trailing space: the label has NO UIPadding (AutomaticSize.X off
	-- an AutomaticSize.X root fights a UIPadding — see _Build's comment), so
	-- the padded string itself is what keeps text off the chip's edge.
	local text = TextConfig.Resolve(props.textKey or props.text)
	self._label.Text = text ~= "" and (" " .. text .. " ") or ""
	if self.Theme then
		self:_Style(self.Theme)
	end
end

function UIBadgeComponent:_Style(theme: Types.UITheme)
	local variant = self.Props.variant or "New"
	local arcadeKey = VARIANT_ARCADE[variant]
	local fill: Color3
	if arcadeKey then
		fill = (theme.Arcade :: any)[arcadeKey]
	else
		-- Unknown variants still read as a direct Colors token lookup, then
		-- Primary — legacy escape hatch kept for raw-token callers.
		fill = (theme.Colors :: any)[variant] or theme.Colors.Primary
	end

	self.Root.BackgroundColor3 = fill
	-- Chip border (see _Build's comment): Classic = the bespoke 2px micro
	-- stroke painted from theme.Colors.Stroke; styled chrome = UIChrome policy.
	local styled = theme.Chrome ~= nil
	if not self._stroke then
		self._stroke = if styled
			then UIChrome.Stroke(theme, "Arcade", "Button")
			else UIStyler.Stroke(Color3.new(0, 0, 0), 2, 0)
		self._stroke.Parent = self.Root
	end
	if not styled then
		self._stroke.Color = theme.Colors.Stroke
	end
	if self._gradient then
		-- Effects toggle AND the style's bevel policy: a flat chrome
		-- (Chrome.Bevel = false) keeps the chip flat no matter what the
		-- Effects token says (same gate as UIButtonComponent's bevel).
		self._gradient.Enabled = theme.Effects.UseGradients and UIChrome.ActiveChrome().Bevel
	end
	-- The display font — FontFace is always assigned explicitly.
	self._label.FontFace = theme.Fonts.Button
	self._label.TextColor3 = theme.Colors.TextOnPrimary
	-- Re-assert the style's text emphasis AFTER the colour so a styled glow
	-- tracks the label colour (Classic: the same black outline, unchanged).
	UIChrome.TextOutline(self._label)
	if self._labelConstraint then
		-- Micro type scale (doc §2: 11) with the live editor multiplier applied.
		self._labelConstraint.MaxTextSize = TextScaleConfig.ScaledCap(MICRO_TEXT_SIZE)
	end
end

return UIBadgeComponent
