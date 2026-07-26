--!strict
-- Boxless toast (doc §8): NO background box, NO stroke frame — just outlined
-- FredokaOne text with a leading emoji icon, floating over the game. Gold by
-- default; variants recolour the text via theme.Arcade (Success→green,
-- Error→red, Warning→orange, Info→gold). The black text outline is what lets
-- it sit over 3D scenes and busy panels (doc §2, non-negotiable).
--
-- Two modes (doc §5.3 / §8):
--   * bottom toast (default): TextSize 24, plain show, gone after 3s.
--   * top banner (banner=true): TextSize 34, enters with a 1.45→1 scale pop
--     over 0.4s Back Out (a UIScale tween on the inner content — the Root
--     stays a fixed transparent footprint, so stacks never reflow), 5s hold.
-- Exit is a hard hide either way: things pop in and hard-hide out (doc §5).
--
-- Extra props:
--   text / textKey
--   variant  : "Info" | "Success" | "Error" | "Warning"
--   icon     : emoji override
--   banner   : boolean? — top-banner mode (TextSize 34 + the 1.45→1 pop)
--   duration : seconds visible (default 3; banners default 5)
--   onDone   : () -> ()  fired after it removes itself

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local TextConfig = require(script.Parent.Parent.Config.TextConfig)
local UIComponentBase = require(script.Parent.UIComponentBase)

local UIToastComponent = setmetatable({}, { __index = UIComponentBase })
UIToastComponent.__index = UIToastComponent

-- Variant → theme.Arcade colour token + fallback emoji. Gold is the default
-- toast colour (doc §8), so Info reads gold too.
local VARIANT = {
	Info = { arcade = "Gold", icon = "ℹ️" },
	Success = { arcade = "Green", icon = "✅" },
	Error = { arcade = "Red", icon = "⛔" },
	Warning = { arcade = "Orange", icon = "⚠️" },
}

-- Doc §5.3: the top banner pops from scale 1.45 → 1 over 0.4s Back Out.
local BANNER_POP_FROM = 1.45
local BANNER_POP = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- Doc §8 toast recipe: bottom 24px / 3s · top banner 34px / 5s.
local TOAST_TEXT_SIZE = 24
local BANNER_TEXT_SIZE = 34
local TOAST_DURATION = 3
local BANNER_DURATION = 5

function UIToastComponent.new()
	local self = UIComponentBase.new("UIToast")
	return setmetatable(self, UIToastComponent)
end

function UIToastComponent:_Build(props: Types.UIComponentProps)
	local root = self.Root
	self._bannerMode = props.banner == true
	local textSize = if self._bannerMode then BANNER_TEXT_SIZE else TOAST_TEXT_SIZE

	-- Boxless: Root keeps the transparent background it was born with. Only
	-- pick a default footprint when the caller didn't pass one (the base class
	-- already applied props.size before _Build runs).
	if not props.size then
		root.Size = UDim2.new(1, 0, 0, if self._bannerMode then 56 else 44)
		self._baseSize = root.Size
	end
	root.ZIndex = 60 -- toasts/reveals band of the ZIndex ladder (doc §7.3)

	-- All motion lives on this inner content frame via a UIScale — never a
	-- Size change on Root, so toast stacks/slots never reflow.
	local content = UIStyler.Frame("Content")
	content.BackgroundTransparency = 1
	content.Parent = root
	self._content = content
	self:_UseScaleTarget(content)

	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
	}).Parent = content

	-- Leading emoji icon. RichText=false is what lets TextScaled render a
	-- single emoji glyph on a small box (see UIButtonComponent's icon — the
	-- "TextScaled draws nothing" failure was specific to RichText boxes).
	local icon = UIStyler.TextLabel("Icon")
	icon.RichText = false
	-- Perfect square via AspectRatioConstraint; starting Size is non-zero on
	-- BOTH axes — a Scale=0 starting dimension collapses the constraint to 0x0.
	icon.Size = UDim2.fromScale(0.7, 0.7)
	UIStyler.AspectRatio(1, Enum.DominantAxis.Height).Parent = icon
	icon.TextScaled = true
	self._iconConstraint = UIStyler.TextSizeConstraint(textSize, 10)
	self._iconConstraint.Parent = icon
	-- ALWAYS assign FontFace on emoji labels: the engine default (LegacyArial)
	-- has no emoji glyphs at all, so the icon would be genuinely invisible.
	-- The assignment lives in _Style (theme.Fonts.Button), which Create runs
	-- before Play ever shows the toast.
	icon.LayoutOrder = 1
	icon.Parent = content
	self._icon = icon

	local label = UIStyler.TextLabel("Label")
	-- AutomaticSize.X so the icon+text pair centres as a group in the slot.
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromScale(0, 1)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.LayoutOrder = 2
	-- TextScaled must be the LAST wrap-related assignment on this label.
	-- The cap makes it render at exactly 24/34 and only ever shrink for long
	-- lines (doc §2 long-text safety: FredokaOne runs wide).
	label.TextScaled = true
	self._labelConstraint = UIStyler.TextSizeConstraint(textSize, 10)
	self._labelConstraint.Parent = label
	label.Parent = content
	self._label = label

	local variant = VARIANT[props.variant or "Info"] or VARIANT.Info
	self._variant = variant
	icon.Text = props.icon or variant.icon
	label.Text = TextConfig.Resolve(props.textKey or props.text)
end

-- Show, hold for `duration`, then self-destroy. Bottom toast = plain show;
-- banner = the 1.45→1 pop. Called by the HUD's toast stack after Create.
function UIToastComponent:Play()
	self.Root.Visible = true
	if self._bannerMode then
		local scale = self:_EnsureScale()
		scale.Scale = BANNER_POP_FROM
		self:_Tween(scale, BANNER_POP, { Scale = 1 })
	end
	local duration = self.Props.duration or (if self._bannerMode then BANNER_DURATION else TOAST_DURATION)
	task.delay(duration, function()
		if not self.Root or not self.Root.Parent then
			return
		end
		if self.Props.onDone then
			self.Props.onDone()
		end
		self:Destroy()
	end)
end

function UIToastComponent:_Style(theme: Types.UITheme)
	local accent = ((theme.Arcade :: any)[self._variant.arcade] :: Color3?) or theme.Arcade.Gold
	-- FredokaOne display font (doc §2) — theme-driven so live swaps land.
	self._icon.FontFace = theme.Fonts.Button
	self._label.FontFace = theme.Fonts.Button
	self:_SetColor(self._label, "TextColor3", accent)
	self:_SetColor(self._icon, "TextColor3", accent)
	-- The black text outline, applied explicitly (UIChrome) rather than
	-- leaning on the style-enforcer backstop.
	UIChrome.TextOutline(self._label)
	UIChrome.TextOutline(self._icon)
end

return UIToastComponent
