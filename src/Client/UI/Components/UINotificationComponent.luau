--!strict
-- Prominent notification banner (level-up / achievement / unlock) — the big
-- top-center sibling of the corner toast, in the Pottery Clash arcade
-- language: a slate Arcade.Panel card with a 3px black stroke, hard 90°
-- corners and the glass sheen; FredokaOne title tinted per variant, ice-blue
-- FredokaOne body, boxless emoji icon on the left.
--
-- Entrance is the doc §5.3 banner pop — scale 1.45 → 1 over 0.4s Back Out
-- (no slide); exit is a quick scale-down, then onDone + self-destroy.
--
-- Props: title/titleKey, body/bodyKey, icon (emoji), variant
-- ("Info"|"Success"|"Achievement"|"LevelUp"), duration, onDone.

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local TextConfig = require(script.Parent.Parent.Config.TextConfig)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIComponentBase = require(script.Parent.UIComponentBase)

local UINotificationComponent = setmetatable({}, { __index = UIComponentBase })
UINotificationComponent.__index = UINotificationComponent

-- Variant → Arcade palette colour for the title tint (doc §3.2 semantics:
-- gold = rewards/valuable, green = positive, orange = daily/level energy).
-- `icon` is an ARCHIVE KEY, not a glyph: the banner draws real pack art and
-- only falls back to a Unicode glyph if that art is missing (IconArchive owns
-- that chain). Callers may still pass their own key via props.icon.
local VARIANT = {
	Info = { color = "Gold", icon = "info" },
	Success = { color = "Green", icon = "checkButton" },
	Achievement = { color = "Gold", icon = "trophy" },
	LevelUp = { color = "Orange", icon = "levelUp" },
}

-- Doc §5.3 toasts: the top banner pops from scale 1.45 → 1 (0.4s Back Out)
-- and auto-hides after 5s. The exit is a quick hard-hide scale-down.
local BANNER_POP = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local BANNER_POP_FROM = 1.45
local BANNER_EXIT_FALLBACK = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local DEFAULT_DURATION = 5

function UINotificationComponent.new()
	local self = UIComponentBase.new("UINotification")
	return setmetatable(self, UINotificationComponent)
end

function UINotificationComponent:_Build(props: Types.UIComponentProps)
	local root = self.Root
	root.BackgroundTransparency = 1
	-- Fills whatever the caller's container gives it (GameHUDScreen's banner
	-- slot) instead of a fixed pixel Offset, so this popup scales with the
	-- HUD at any viewport instead of staying a constant absolute size.
	root.Size = UDim2.fromScale(1, 1)
	self._baseSize = root.Size

	-- The card: Arcade.Panel slate + hard corners + glass sheen. The 3px
	-- black stroke is added at first _Style (UIChrome.Stroke needs a theme).
	-- All banner motion (the 1.45 → 1 pop) is a UIScale on THIS surface —
	-- the Root stays a fixed transparent footprint and never reflows.
	local surface = UIStyler.Frame("Surface")
	surface.Size = UDim2.fromScale(1, 1)
	surface.AnchorPoint = Vector2.new(0.5, 0.5)
	surface.Position = UDim2.fromScale(0.5, 0.5)
	surface.Parent = root
	self._surface = surface
	self:_UseScaleTarget(surface)

	UIChrome.Corner("Arcade").Parent = surface
	UIChrome.GlassGradient().Parent = surface
	UIStyler.PaddingScale(0.1).Parent = surface

	-- Boxless icon slot (left): real pack art, no badge circle, no fill.
	-- A holder frame carries the square aspect so the art (or the glyph
	-- fallback) can just fill it — an AspectRatioConstraint needs a non-zero
	-- starting Size on BOTH axes or it collapses to 0x0.
	local iconSlot = UIStyler.Frame("IconSlot")
	iconSlot.BackgroundTransparency = 1
	iconSlot.Size = UDim2.fromScale(0.2, 0.8)
	iconSlot.AnchorPoint = Vector2.new(0, 0.5)
	iconSlot.Position = UDim2.new(0, 0, 0.5, 0)
	UIStyler.AspectRatio(1, Enum.DominantAxis.Height).Parent = iconSlot
	iconSlot.Parent = surface
	self._iconSlot = iconSlot

	-- Title + body (right of the icon). Fixed-size FredokaOne per the doc
	-- type scale (34 banner headline / 18 body), with TextScaled +
	-- UITextSizeConstraint caps so long strings shrink to fit but never grow.
	local title = UIStyler.TextLabel("Title")
	title.Size = UDim2.new(0.8, 0, 0.44, 0)
	title.Position = UDim2.fromScale(0.2, 0.02)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextScaled = true
	UIChrome.TextOutline(title)
	self._titleConstraint = UIStyler.TextSizeConstraint(34, 14)
	self._titleConstraint.Parent = title
	title.Parent = surface
	self._title = title

	local body = UIStyler.TextLabel("Body")
	body.Size = UDim2.new(0.8, 0, 0.42, 0)
	body.Position = UDim2.fromScale(0.2, 0.52)
	body.TextXAlignment = Enum.TextXAlignment.Left
	UIChrome.TextOutline(body)
	self._bodyConstraint = UIStyler.TextSizeConstraint(18, 8)
	self._bodyConstraint.Parent = body
	-- TextScaled LAST among wrap-related assignments: setting TextWrapped
	-- after TextScaled silently reverts TextScaled.
	body.TextWrapped = true
	body.TextScaled = true
	body.Parent = surface
	self._body = body

	local variant = VARIANT[props.variant or "Info"] or VARIANT.Info
	self._variant = variant
	self:_SetIcon(props.icon or variant.icon)
	self._title.Text = TextConfig.Resolve(props.titleKey or props.title)
	self._body.Text = TextConfig.Resolve(props.bodyKey or props.body)
end

-- Swap the banner art. IconArchive returns either an ImageLabel or an outlined
-- glyph label; either way it fills the square slot, so the layout is identical
-- whichever it hands back.
function UINotificationComponent:_SetIcon(key: string)
	if self._icon then
		self._icon:Destroy()
	end
	local icon = IconArchive.Image(self._iconSlot, key, 1)
	icon.Size = UDim2.fromScale(1, 1)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	self._icon = icon
end

-- Banner pop in (1.45 → 1, 0.4s Back Out), hold, quick scale-down, clean up.
function UINotificationComponent:Play()
	local root = self.Root
	root.Visible = true

	local scale = self:_EnsureScale()
	scale.Scale = BANNER_POP_FROM
	self:_Tween(scale, BANNER_POP, { Scale = 1 })

	local duration = self.Props.duration or DEFAULT_DURATION
	task.delay(duration, function()
		if not root or not root.Parent then
			return
		end
		local exit = self.Theme and self.Theme.Animations.Disappear or BANNER_EXIT_FALLBACK
		self:_Tween(scale, exit, { Scale = 0.6 })
		task.wait(exit.Time)
		if self.Props.onDone then
			self.Props.onDone()
		end
		self:Destroy()
	end)
end

function UINotificationComponent:_Style(theme: Types.UITheme)
	local arcade = theme.Arcade
	local accent = (arcade :: any)[self._variant.color] or arcade.Gold

	-- Card fill = slate Arcade.Panel; the 3px black stroke comes from the
	-- UIChrome policy helper (created once — the arcade border never varies).
	self:_SetColor(self._surface, "BackgroundColor3", arcade.Panel)
	if not self._stroke then
		self._stroke = UIChrome.Stroke(theme, "Arcade")
		self._stroke.Parent = self._surface
	end

	-- The icon is normally real pack art (an ImageLabel, nothing to style). It
	-- is only a TextLabel when the archive fell back to a glyph — and then it
	-- MUST get a FontFace, because the engine default (LegacyArial) has no
	-- symbol coverage and the label would draw nothing at all.
	if self._icon and self._icon:IsA("TextLabel") then
		self._icon.FontFace = theme.Fonts.Title
		local iconH = self._icon.AbsoluteSize.Y
		if iconH > 0 then
			self._icon.TextSize = math.clamp(iconH * 0.72, 14, 48)
		end
	end

	-- Title: the display font in the variant colour, wearing the style's text
	-- emphasis (Classic: the doc §2 black outline) — re-asserted AFTER the
	-- colour so a styled glow tracks it.
	self._title.FontFace = theme.Fonts.Title
	self:_SetColor(self._title, "TextColor3", accent)
	UIChrome.TextOutline(self._title)
	if self._titleConstraint then
		self._titleConstraint.MaxTextSize = theme.TextSizes.Title
	end

	-- Body: ice-blue 18, wearing the style's text emphasis (same rule as above).
	self._body.FontFace = theme.Fonts.Numeric
	self:_SetColor(self._body, "TextColor3", arcade.IceBlue)
	UIChrome.TextOutline(self._body)
	if self._bodyConstraint then
		self._bodyConstraint.MaxTextSize = 18
	end
end

return UINotificationComponent
