--!strict
-- The arcade button (UI_DESIGN_DOCUMENT.md §4.1/§8): a solid flat fill carrying
-- the arcade bevel gradient (white → RGB(140,140,140) vertical multiply), a 3px
-- black Border stroke and hard 90° corners, with a FredokaOne label wearing the
-- non-negotiable black text outline. Hover/press is the §5.1 motion kit via
-- UIComponentBase (UIScale 1.05/0.93 on the Surface + fill 12% toward white).
-- Extends UIComponentBase, overriding only _Build and _Style.
--
-- Extra props:
--   variant : legacy  "Primary"→Blue | "Secondary"→Magenta | "Accent"→Gold |
--                     "Success"→Green | "Danger"→Red |
--                     "Ghost"→transparent fill + 2px black stroke + white text
--             arcade  "Green" | "Blue" | "Red" | "Gold" | "Magenta" | "Orange" | "Grey"
--             studio  "StudioToolbar" (PanelSoft, corner 12, tan hairline,
--                     FredokaOne 15 cream, 42 tall) | "StudioBack" (terracotta) |
--                     "StudioNext" (sage)
--   text / textKey, icon (emoji), iconId (image)
--   priceCurrency ("Cash" | "Bux" | "Robux") + priceAmount (number) :
--       PRICE-BUTTON mode (doc §8) — 28px boxless currency icon LEFT of a
--       FredokaOne 28 white amount, fill = the currency's colour (Cash green /
--       Bux blue / Robux magenta, no exceptions). owned = true flips the button
--       to GreyOwned "OWNED" with the icon+amount hidden — recoloured in place,
--       flippable at runtime through SetContent.
--   enabled : false to disable — GreyOwned fill, no gradient; the Hit target
--       stays live so every tap still answers with the full press juice.

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local TextConfig = require(script.Parent.Parent.Config.TextConfig)
local TextScaleConfig = require(script.Parent.Parent.Config.TextScaleConfig)
local UIAssets = require(script.Parent.Parent.Config.UIAssets)
local UIComponentBase = require(script.Parent.UIComponentBase)

-- The resolved surface recipe for the current props (variant + price mode +
-- enabled state), consumed by _Style.
type Recipe = {
	family: Types.UIFamily,
	fill: Color3?, -- nil = transparent surface (Ghost)
	text: Color3,
	cap: number, -- label TextScaled cap, px at the 1650×1020 baseline
	bevel: boolean, -- arcade bevel gradient enabled?
	ghost: boolean, -- 2px black stroke instead of the family stroke
}

local UIButtonComponent = setmetatable({}, { __index = UIComponentBase })
UIButtonComponent.__index = UIButtonComponent

function UIButtonComponent.new()
	local self = UIComponentBase.new("UIButton")
	return setmetatable(self, UIButtonComponent)
end

local function isStudioVariant(variant: string?): boolean
	return variant == "StudioToolbar" or variant == "StudioBack" or variant == "StudioNext"
end

function UIButtonComponent:_Build(props: Types.UIComponentProps)
	local root = self.Root
	root.BackgroundTransparency = 1
	if not props.size then
		-- Booth toolbar buttons run 42 tall ("taller so the bubbly font
		-- breathes", doc §8); arcade buttons keep the 48 default.
		root.Size = UDim2.new(0, 180, 0, if isStudioVariant(props.variant) then 42 else 48)
		self._baseSize = root.Size
	end

	-- Surface holds the fill + all visuals and is what hover/press scale. The
	-- Root is a fixed, transparent footprint that stays put in any layout, so
	-- the hover "pop" never reflows neighbours or spills out of a grid cell.
	-- Chrome (corner + stroke) lands in _Style through UIChrome so the family
	-- POLICY (hard 0px + 3px black vs studio 12px + tan hairline) is decided
	-- there, never per-call.
	local surface = UIStyler.Frame("Surface")
	surface.BackgroundTransparency = 0
	surface.Size = UDim2.fromScale(1, 1)
	surface.AnchorPoint = Vector2.new(0.5, 0.5)
	surface.Position = UDim2.fromScale(0.5, 0.5)
	surface.ClipsDescendants = true
	surface.ZIndex = 2
	surface.Parent = root
	self._surface = surface
	self:_UseScaleTarget(surface)
	-- Register the fill with the base class: HOVER_IN lerps it 12% toward
	-- white (rest colour re-captured each hover — buttons recolour at runtime).
	self:_SetHoverFill(surface)

	-- The arcade button bevel (doc §4.1.3): vertical white → RGB(140,140,140)
	-- multiply over the flat fill. Toggled per-recipe in _Style (off for Ghost,
	-- studio variants and the disabled/OWNED grey).
	local bevelGradient = UIChrome.ArcadeBevel()
	bevelGradient.Parent = surface
	self._bevelGradient = bevelGradient

	-- Content holds the icon + label under its own layout, separate from the
	-- Hit button so the full-size hit target never joins the content layout.
	local content = UIStyler.Frame("Content")
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 1)
	content.ZIndex = 3
	local layout = UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
	})
	layout.Parent = content
	content.Parent = surface

	-- Price-button currency icon (doc §8): 28px, boxless, ALWAYS leading —
	-- LayoutOrder 0 keeps it left of the amount. Image resolved from the
	-- UIAssets registry per priceCurrency in SetContent.
	local priceIcon = Instance.new("ImageLabel")
	priceIcon.Name = "PriceIcon"
	priceIcon.BackgroundTransparency = 1
	priceIcon.ScaleType = Enum.ScaleType.Fit
	priceIcon.Size = UDim2.fromOffset(28, 28)
	priceIcon.LayoutOrder = 0
	priceIcon.Visible = false
	priceIcon.Parent = content
	self._priceIcon = priceIcon

	local icon = UIStyler.TextLabel("Icon")
	-- RichText=false: the earlier "TextScaled draws nothing" finding was
	-- specifically on a RichText-enabled box (UIStyler.TextLabel's default) —
	-- a single emoji glyph never needs rich text markup, and turning it off
	-- is what actually lets TextScaled render correctly here (confirmed via
	-- live test), instead of the old workaround of a manually computed
	-- TextSize that only updated on theme changes, not continuously.
	icon.RichText = false
	icon.Size = UDim2.fromScale(0.6, 0.6)
	-- Perfect square (AspectRatioConstraint 1:1, DominantAxis Height) instead
	-- of a fixed pixel Offset, so it scales with the button's real resolved
	-- height. Starting size is non-zero on both axes (never Scale=0) — an
	-- AspectRatioConstraint driving a Scale=0 starting dimension collapses to
	-- 0x0 instead of resolving correctly.
	UIStyler.AspectRatio(1, Enum.DominantAxis.Height).Parent = icon
	icon.TextScaled = true
	self._iconConstraint = UIStyler.TextSizeConstraint(40, 12)
	self._iconConstraint.Parent = icon
	icon.LayoutOrder = 1
	icon.Visible = false
	icon.Parent = content
	self._icon = icon

	-- Image variant of the icon (used when props.iconId is an asset id instead
	-- of an emoji) — an ImageLabel scales its image content with Size
	-- automatically, so it just needs the same Scale+AspectRatio treatment,
	-- no TextScaled-equivalent concern. Same slot/order as the emoji icon;
	-- only one is ever visible.
	local iconImage = Instance.new("ImageLabel")
	iconImage.Name = "IconImage"
	iconImage.BackgroundTransparency = 1
	iconImage.Size = UDim2.fromScale(0.6, 0.6)
	UIStyler.AspectRatio(1, Enum.DominantAxis.Height).Parent = iconImage
	iconImage.LayoutOrder = 1
	iconImage.Visible = false
	iconImage.Parent = content
	self._iconImage = iconImage

	local label = UIStyler.TextLabel("Label")
	-- AutomaticSize.X stays (it shares a UIListLayout row with the icon, whose
	-- own width comes from measuring the label's real text width) — but the
	-- text itself now scales via TextScaled instead of a fixed pixel size, per
	-- TextScaleConfig, so it shrinks/grows with the button at any viewport.
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromScale(0, 1)
	-- The non-negotiable black text outline (doc §2) — explicit chrome, so the
	-- look doesn't depend on the UIStyleEnforcer backstop.
	UIChrome.TextOutline(label)
	-- TextScaled must be the LAST text-wrap-related assignment: setting
	-- TextWrapped afterward (even to false) silently reverts TextScaled back
	-- to false, confirmed via a live Studio test — the mirror image of
	-- TextScaled's own documented side effect of forcing TextWrapped to true.
	-- AutomaticSize.X growing to fit the unwrapped text means wrapping never
	-- actually triggers in practice, so leaving TextWrapped at its (now true)
	-- default is harmless here.
	label.TextScaled = true
	label.LayoutOrder = 2
	label.TextXAlignment = Enum.TextXAlignment.Center
	self._labelConstraint = UIStyler.TextSizeConstraint(26, 8)
	self._labelConstraint.Parent = label
	label.Parent = content
	self._label = label

	-- Hit target overlays everything so the whole button is clickable. It does
	-- NOT need to render above Surface: under the default ZIndexBehavior.Sibling,
	-- whichever ROOT-level sibling has the higher ZIndex paints its ENTIRE
	-- subtree on top of the other's — so Hit at ZIndex 5 (vs Surface's 2) was
	-- painting over Surface's whole subtree, including the icon/label inside it,
	-- no matter what ZIndex THEY had. That's what made every icon invisible.
	-- Surface is a plain Frame (Active is never set true), so it never blocks
	-- input — Hit still receives every click/tap/gamepad-A over its full bounds
	-- sitting BELOW Surface, with nothing rendered on top of the icon anymore.
	local button = Instance.new("TextButton")
	button.Name = "Hit"
	button.BackgroundTransparency = 1
	button.Size = UDim2.fromScale(1, 1)
	button.Text = ""
	button.AutoButtonColor = false
	-- Selectable so a gamepad/console can navigate to and A-press this button;
	-- Activated (bound in _BindInteractions) fires for mouse, touch AND gamepad,
	-- so one code path serves PC, mobile and console.
	button.Selectable = true
	button.ZIndex = 1
	button.Parent = root
	self._button = button

	self:_BindInteractions(button)
	self:SetContent(props)
end

-- True when the button renders in PRICE-BUTTON mode (doc §8).
function UIButtonComponent:_IsPriceMode(): boolean
	return self.Props.priceCurrency ~= nil
end

-- Update text/icon after construction without rebuilding. Supports an emoji
-- `icon`, an image `iconId`, a text label, or any combination — an icon-only
-- button, a text-only button, an icon+text button and the price button all
-- come from here. Price props (priceCurrency/priceAmount/owned) merge into
-- Props so ownership can flip at runtime: SetContent({ owned = true }) turns
-- a live price button grey "OWNED" in place (icon+amount hidden, children
-- never removed) and SetContent({ owned = false }) flips it back.
function UIButtonComponent:SetContent(props: Types.UIComponentProps)
	local p = self.Props
	if props ~= p then
		-- Merge stateful keys so partial updates keep the full recipe.
		if props.variant ~= nil then
			p.variant = props.variant
		end
		if props.priceCurrency ~= nil then
			p.priceCurrency = props.priceCurrency
		end
		if props.priceAmount ~= nil then
			p.priceAmount = props.priceAmount
		end
		if props.owned ~= nil then
			p.owned = props.owned
		end
		if props.dimmed ~= nil then
			p.dimmed = props.dimmed
		end
	end

	if self:_IsPriceMode() then
		-- PRICE-BUTTON mode: currency icon leading the amount; OWNED goes
		-- grey with the icon+amount hidden (the label carries "OWNED").
		self._icon.Visible = false
		self._iconImage.Visible = false
		if p.owned == true then
			self._priceIcon.Visible = false
			self._label.Text = " OWNED "
		else
			self._priceIcon.Image = UIAssets.Icons[p.priceCurrency] or ""
			self._priceIcon.Visible = true
			-- Leading/trailing space: AutomaticSize.X off the label with no
			-- UIPadding (a UIPadding fighting AutomaticSize.X produced unstable
			-- sizing), so the padded string keeps the label off the edges.
			self._label.Text = " " .. tostring(p.priceAmount) .. " "
		end
		self._label.Visible = true
	else
		self._priceIcon.Visible = false
		local text = TextConfig.Resolve(props.textKey or props.text)
		self._label.Text = text ~= "" and (" " .. text .. " ") or ""
		self._label.Visible = text ~= ""
		if props.icon and props.icon ~= "" then
			-- Emoji glyph.
			self._icon.Text = props.icon
			self._icon.Visible = true
			self._iconImage.Visible = false
		elseif props.iconId and props.iconId ~= "" then
			-- Image asset.
			self._iconImage.Image = props.iconId
			self._iconImage.Visible = true
			self._icon.Visible = false
		else
			self._icon.Visible = false
			self._iconImage.Visible = false
		end
	end

	-- Restyle so recipe changes (currency colour, OWNED grey, variant flips
	-- from Update paths) land immediately, not only on the next theme swap.
	if self.Theme then
		self:_Style(self.Theme)
	end
end

function UIButtonComponent:SetEnabled(enabled: boolean)
	self.Props.enabled = enabled
	if self.Theme then
		self:_Style(self.Theme)
	end
end

-- Resolve the surface recipe for the current props + enabled state. Legacy
-- variant names keep working, remapped onto the arcade palette; disabled is
-- always the OWNED grey with no gradient (dimmed in place, never removed).
function UIButtonComponent:_Recipe(theme: Types.UITheme): Recipe
	local p = self.Props
	local a = theme.Arcade
	local s = theme.Studio
	local white = theme.Colors.TextPrimary
	local enabled = p.enabled ~= false

	-- PRICE-BUTTON mode (doc §8): fill = the currency's colour, no exceptions
	-- (§3.3). Only OWNED goes grey; a blocked (unaffordable/disabled) price
	-- button KEEPS its currency fill and is dimmed in place by _Style instead
	-- (§8 troll cell: 55% transparency dims + grey text — never grey-out,
	-- never removal), so "can't afford" never reads as "already owned".
	local priceCurrency = p.priceCurrency :: string?
	if priceCurrency then
		local owned = p.owned == true
		return {
			family = "Arcade" :: Types.UIFamily,
			fill = if owned then a.GreyOwned else UIChrome.CurrencyColor(theme, priceCurrency),
			text = white,
			cap = 28, -- FredokaOne 28 amount
			bevel = enabled and not owned,
			ghost = false,
		}
	end

	local function arcadeFill(fill: Color3): Recipe
		return {
			family = "Arcade" :: Types.UIFamily,
			fill = fill,
			text = white,
			cap = theme.TextSizes.Button,
			bevel = true,
			ghost = false,
		}
	end
	-- Booth toolbar recipe (doc §8): PanelSoft-style fill, corner 12, tan
	-- hairline, FredokaOne 15, cream text; terracotta back / sage next.
	local function studioFill(fill: Color3): Recipe
		return {
			family = "Studio" :: Types.UIFamily,
			fill = fill,
			text = s.TextLight,
			cap = 15,
			bevel = false,
			ghost = false,
		}
	end

	local map: { [string]: Recipe } = {
		-- Legacy names, remapped onto the arcade palette.
		Primary = arcadeFill(a.Blue),
		Secondary = arcadeFill(a.Magenta),
		Accent = arcadeFill(a.Gold),
		Success = arcadeFill(a.Green),
		Danger = arcadeFill(a.Red),
		Ghost = {
			family = "Arcade" :: Types.UIFamily,
			fill = nil, -- transparent surface
			text = white,
			cap = theme.TextSizes.Button,
			bevel = false,
			ghost = true,
		},
		-- Arcade palette names.
		Green = arcadeFill(a.Green),
		Blue = arcadeFill(a.Blue),
		Red = arcadeFill(a.Red),
		Gold = arcadeFill(a.Gold),
		Magenta = arcadeFill(a.Magenta),
		Orange = arcadeFill(a.Orange),
		Grey = arcadeFill(a.GreyOwned),
		-- Studio (booth) variants.
		StudioToolbar = studioFill(s.PanelSoft),
		StudioBack = studioFill(s.Back),
		StudioNext = studioFill(s.Next),
	}
	local spec = map[p.variant or "Primary"] or map.Primary

	if not enabled then
		return {
			family = spec.family,
			fill = a.GreyOwned, -- OWNED/CLAIMED grey — recolour in place
			text = spec.text,
			cap = spec.cap,
			bevel = false, -- disabled = flat grey, no gradient
			ghost = spec.ghost,
		}
	end
	return spec
end

function UIButtonComponent:_Style(theme: Types.UITheme)
	local recipe: Recipe = self:_Recipe(theme)
	local surface = self._surface :: Frame
	local enabled = self.Props.enabled ~= false

	-- Solid flat fill; the arcade bevel gradient supplies the top-lit shading.
	local fill = recipe.fill
	if fill then
		surface.BackgroundTransparency = 0
		self:_SetColor(surface, "BackgroundColor3", fill)
	else
		-- Ghost: transparent surface, stroke + text carry the shape.
		surface.BackgroundTransparency = 1
		surface.BackgroundColor3 = theme.Arcade.Panel
	end

	-- Blocked-in-place dim (doc §8 troll cell / §11.2): 55% transparency on
	-- the fill + grey text, never removal. `dimmed` is purely visual — the
	-- button stays interactive so every tap still answers (the screen then
	-- explains, e.g. a "can't afford" toast). A disabled-but-not-owned price
	-- button gets the same treatment so it never masquerades as OWNED.
	local owned = self.Props.owned == true
	local dimmed = self.Props.dimmed == true
		or (self:_IsPriceMode() and not enabled and not owned)
	if dimmed and fill then
		surface.BackgroundTransparency = 0.55
	end
	-- Style-gated: a chrome that rejects the arcade bevel (Chrome.Bevel =
	-- false) keeps the fill flat no matter what the recipe asks for.
	self._bevelGradient.Enabled = recipe.bevel and not dimmed and UIChrome.ActiveChrome().Bevel

	-- Chrome is recreated THROUGH UIChrome so the family policy (arcade hard
	-- 0px corners + 3px black stroke, studio corner 12 + tan 1.5px hairline)
	-- can never drift per-call.
	if self._corner then
		self._corner:Destroy()
	end
	local corner = UIChrome.Corner(recipe.family, "Button")
	corner.Parent = surface
	self._corner = corner

	if self._stroke then
		self._stroke:Destroy()
	end
	local stroke: UIStroke
	if recipe.ghost and theme.Chrome == nil then
		-- Ghost's sanctioned Classic exception (per spec): 2px black instead
		-- of 3px. A styled chrome frames ghosts like every other button.
		stroke = UIStyler.Stroke(theme.Colors.Stroke, 2, 0)
	else
		stroke = UIChrome.Stroke(theme, recipe.family, "Button")
	end
	stroke.Parent = surface
	self._stroke = stroke

	-- Label: the style's Button font; the cap tracks the recipe (26 arcade /
	-- 15 studio / 28 price). The text emphasis is re-asserted AFTER the colour
	-- so a styled glow tracks the label colour (Classic: same black outline).
	self._label.FontFace = theme.Fonts.Button
	self._label.TextColor3 = if dimmed then theme.Colors.Disabled else recipe.text
	UIChrome.TextOutline(self._label)
	if self._labelConstraint then
		self._labelConstraint.MaxTextSize = TextScaleConfig.ScaledCap(recipe.cap)
	end
	-- Icon is TextScaled (see _Build) — genuinely continuous scaling with the
	-- button's real size.
	if self._iconConstraint then
		self._iconConstraint.MaxTextSize = 40
	end
	-- FontFace was never assigned, so the icon silently fell back to the engine
	-- default (LegacyArial) — a font with NO emoji glyph coverage at all, so
	-- every emoji icon rendered as genuinely invisible (not a screenshot quirk;
	-- confirmed on the live TextLabel: TextSize collapsed to ~8 with nothing
	-- drawn). Any modern FontFace (the theme's, same as the button label) covers
	-- emoji correctly via Roblox's normal glyph-substitution path.
	self._icon.FontFace = theme.Fonts.Button
	self._icon.TextColor3 = recipe.text

	-- Every tap answers (doc §11.1): the Hit target stays Active even when
	-- disabled so the full press juice still plays — only onClick is withheld
	-- (UIComponentBase._BindInteractions gates it on Props.enabled).
	self._button.Active = true
	self._button.Selectable = enabled -- disabled buttons drop out of gamepad nav
	self._button.AutoButtonColor = false
end

return UIButtonComponent
