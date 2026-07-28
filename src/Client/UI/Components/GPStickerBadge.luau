--!strict
-- GPStickerBadge — the tag chip as a STICKER: a petal-cornered pastel chip
-- knocked a couple of degrees off true, with a soft hue-matched shadow behind
-- it so it reads as a real sticker pressed onto the card rather than a rectangle
-- printed on it. Extends UIComponentBase, overriding _Build/_Style (+ a Destroy
-- for its shadow handle).
--
-- Generic and theme-agnostic by construction: the fill comes from the pack's
-- own tag palette, the tilt from DialectTokens.motion.tiltSm (zero under a pack
-- that names no motion namespace, which leaves a straight chip), the corners
-- from theme.Corners, the type cap from theme.TextSizes. Nothing pink is
-- written down here.
--
-- THE 0.4 BOUNDARY: Styling owns static appearance — the chip wears UIChip
-- structurally (via StateDriver, the sole tag mutator) so a pack's ".UIChip"
-- band can dress it once the engine activates styling application; the
-- imperative paint in _Style renders the same look meanwhile. There is NOTHING
-- on the Luau motion side: a sticker does not animate. No UITicker handler, no
-- RunService connection, no tween — the tilt is a STATIC pose written once per
-- restyle, not a wobble. (Callers wanting a badge that breathes wrap it in a
-- GPWobbleCard; that is exactly the separation those two components exist for,
-- and it keeps this one free of a behaviour a pack rule could duplicate.)
--
-- THE TILT ALTERNATES BY LAYOUT ORDER. A row of stickers all leaning the same
-- way looks like a rendering bug — a skew applied to the container. Alternating
-- the SIGN by layout order is what makes a row read as separate stickers placed
-- by hand. Same reasoning as the pack's alternating petal corners, and the same
-- source of truth: the caller's LayoutOrder, so the pattern is stable across a
-- rebuild instead of reshuffling on every restyle.
--
-- NO-SKEW / NO-CLIP ANNOTATION: Roblox has no skew, so the tilt is
-- whole-element Rotation on the CHIP child; the transparent root keeps its
-- unrotated rectangular footprint, so a badge row's AutomaticSize measurement
-- and its layout neighbours never move. Roblox clipping is axis-aligned and
-- does NOT clip rotated descendants, so a sticker sitting flush against a
-- clipped card edge will overhang it by a pixel or two — that is the intended
-- "stuck on top" look, but a caller who needs a hard edge should pass
-- tilt = false.
--
-- MEASURED CONTRAST (this pack's third law): the label is Colors.TextPrimary,
-- the warm plum-brown ink. Colors.TextOnPrimary — near-white — measures 2.14:1
-- on this pack's rose and 1.72:1 on its matcha, and a badge is SMALL text, so
-- near-white is never used here no matter which tag colour the variant picks.
-- Every variant fill in this pack is a light pastel, which is exactly why ink
-- is the right answer for all of them.
--
-- COPY IS PASSED THROUGH VERBATIM. There is no string.upper in this file. A
-- caller handing "NEW" (or the "tag.new" key, which resolves to "NEW") gets
-- "NEW"; a caller handing nothing gets the variant's own sentence-case name.
-- The component never shouts on its own initiative — shouting at this audience
-- is the pack's named failure mode — but it also never quietly rewrites a
-- caller's deliberate casing.
--
-- BUDGETS: at most ONE UIShadow per instance, budget-counted through
-- Capabilities.RegisterShadow and Released on every restyle and on Destroy.
-- Zero ticker handlers, zero RunService connections. 100x Create/Destroy = zero
-- connection, instance or budget growth.
--
-- Props (plus the shared layout props from UIComponentBase):
--   text / textKey : chip copy, VERBATIM (defaults to the variant's own name)
--   variant        : "New" | "Sale" | "Rare" | "Limited" | "Popular", or any
--                    Colors.* token name as a raw-token escape hatch
--   tilt           : false pins the chip straight (see the clipping note)

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local TextConfig = require(script.Parent.Parent.Config.TextConfig)
local TextScaleConfig = require(script.Parent.Parent.Config.TextScaleConfig)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local StateDriver = require(script.Parent.Parent.StyleKit.StateDriver)
local Tags = require(script.Parent.Parent.StyleKit.Tags)
local UIComponentBase = require(script.Parent.UIComponentBase)

local GPStickerBadge = setmetatable({}, { __index = UIComponentBase })
GPStickerBadge.__index = GPStickerBadge

-- Maps a tag variant to a pack palette key. Identical to UIBadgeComponent's
-- map on purpose: a variant must mean the same colour in every pack, or colour
-- stops being meaning. A variant not listed here still resolves as a direct
-- Colors token name, then Primary.
local VARIANT_ARCADE: { [string]: string } = {
	New = "Green",
	Sale = "Red",
	Rare = "Magenta",
	Limited = "Orange",
	Popular = "Blue",
}

-- Sentence-case defaults, used only when the caller supplies no copy at all.
local VARIANT_COPY: { [string]: string } = {
	New = "New",
	Sale = "Sale",
	Rare = "Rare",
	Limited = "Limited",
	Popular = "Popular",
}

-- A tilt beyond this stops reading as "placed by hand" and starts reading as
-- "the layout is broken". A law, not a default: a pack may tilt less.
local MAX_TILT_DEGREES = 8

local function motionNumber(theme: Types.UITheme, key: string, fallback: number): number
	local dialects = theme.DialectTokens
	local tokens = if dialects then dialects.motion else nil
	local value = if tokens then tokens[key] else nil
	return if type(value) == "number" then value else fallback
end

function GPStickerBadge.new()
	local self = UIComponentBase.new("GPStickerBadge")
	return setmetatable(self, GPStickerBadge)
end

function GPStickerBadge:_Build(props: Types.UIComponentProps)
	local root = self.Root
	root.BackgroundTransparency = 1
	-- The root is the UNROTATED footprint and it hugs its content: height fills
	-- the parent row exactly (callers always parent into a row already sized to
	-- the tag-row height), width grows from the chip. Nothing here computes its
	-- own height independently, so it can never drift out of sync with the row.
	root.AutomaticSize = Enum.AutomaticSize.X
	if not props.size then
		root.Size = UDim2.fromScale(0, 1)
		self._baseSize = root.Size
	end

	-- CHIP: the sticker itself. Top-left anchored rather than centred, because
	-- an AnchorPoint-0.5 child inside an AutomaticSize.X parent makes the
	-- measurement circular (the parent's width would depend on the child's
	-- position, which depends on the parent's width). Rotation pivots about the
	-- element's own centre regardless of AnchorPoint, so the tilt still looks
	-- right.
	--
	-- Born TRANSPARENT, never painted here: UIStyler.Frame's BackgroundColor3
	-- default is PURE WHITE, which this pack forbids outright, and _Build has no
	-- theme to paint from (it runs before the first ApplyTheme). A transparent
	-- frame renders nothing, so no white can ever reach a screen; _Style is the
	-- only place in this file that assigns a fill or clears the transparency.
	local chip = UIStyler.Frame("Chip")
	chip.BackgroundTransparency = 1
	chip.AutomaticSize = Enum.AutomaticSize.X
	chip.Size = UDim2.fromScale(0, 1)
	chip.ZIndex = 2
	chip.Parent = root
	self._chip = chip
	StateDriver.Structural(chip, Tags.Structural.Chip)

	-- NO UIPadding anywhere in this chain: a UIPadding on an AutomaticSize.X
	-- host that measures an AutomaticSize.X child produces unstable sizing
	-- (confirmed across packs — see UIBadgeComponent). The literal spaces added
	-- in SetContent are what keep the copy off the chip's edges.
	local label = UIStyler.TextLabel("Label")
	label.TextTransparency = 1 -- born transparent: the default TextColor3 is white
	label.AutomaticSize = Enum.AutomaticSize.X
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.fromScale(0, 0.5)
	-- 0.8 of the chip height, not the full 1: the glyph should not fill the
	-- sticker edge to edge or the petal corners lose their shape.
	label.Size = UDim2.fromScale(0, 0.8)
	label.RichText = false
	label.ZIndex = 3
	-- TextScaled must be the LAST wrap-related assignment: setting TextWrapped
	-- afterwards (even to false) silently reverts it (confirmed in Studio).
	label.TextScaled = true
	self._labelConstraint = UIStyler.TextSizeConstraint(12, 6)
	self._labelConstraint.Parent = label
	label.Parent = chip
	self._label = label

	self:SetContent(props)
end

-- Copy, VERBATIM. The leading/trailing space is the padding (see _Build).
--
-- The content keys are FOLDED INTO self.Props first, because _Style reads the
-- variant from there to pick the fill: without the fold, a runtime
-- SetContent{ variant = "Sale" } would relabel the sticker "Sale" and leave it
-- the previous variant's colour, and in this pack colour IS the meaning.
function GPStickerBadge:SetContent(props: Types.UIComponentProps)
	if props ~= self.Props then
		if props.variant ~= nil then
			self.Props.variant = props.variant
		end
		if props.text ~= nil or props.textKey ~= nil then
			self.Props.text = props.text
			self.Props.textKey = props.textKey
		end
	end
	local variant = self.Props.variant or "New"
	local resolved = TextConfig.Resolve(self.Props.textKey or self.Props.text)
	if resolved == "" then
		resolved = VARIANT_COPY[variant] or variant
	end
	self._label.Text = resolved ~= "" and (" " .. resolved .. " ") or ""
	if self.Theme then
		self:_Style(self.Theme)
	end
end

function GPStickerBadge:_Style(theme: Types.UITheme)
	local chip = self._chip :: Frame
	local label = self._label :: TextLabel
	local variant = self.Props.variant or "New"

	-- Colour IS meaning: the variant picks a palette slot, never a literal.
	local arcadeKey = VARIANT_ARCADE[variant]
	local fill: Color3
	if arcadeKey then
		fill = (theme.Arcade :: any)[arcadeKey]
	else
		-- Unknown variants resolve as a direct Colors token, then Primary —
		-- the raw-token escape hatch every badge in this framework keeps.
		fill = (theme.Colors :: any)[variant] or theme.Colors.Primary
	end
	self:_SetColor(chip, "BackgroundColor3", fill)
	chip.BackgroundTransparency = 0 -- clears the born-transparent guard

	-- THE STATIC TILT, sign alternating by layout order so a ROW of stickers
	-- reads hand-placed rather than skewed (see header). Written once here, not
	-- animated — a sticker does not wobble on its own.
	local tilt = if self.Props.tilt == false then 0 else motionNumber(theme, "tiltSm", 0)
	tilt = math.clamp(tilt, 0, MAX_TILT_DEGREES)
	local order = self.Props.layoutOrder or 0
	chip.Rotation = if order % 2 == 0 then tilt else -tilt

	-- PETAL CORNERS, mirrored by the same layout order, so the silhouette
	-- alternates in step with the tilt. CornerSet destroys any stale UICorner
	-- before parenting: CornerRadius alongside per-corner radii — and two
	-- UICorner children — are the same documented-undefined engine behaviour.
	-- Packs without a Corners table fall back to the uniform radius ladder.
	GPLayoutKit.Petal(theme, chip, order)

	-- Soft rounded-join stroke in a DEEPENED TINT OF THE FILL — never black.
	-- Rebuilt rather than recoloured because stroke weight and transparency are
	-- Chrome policy and can move with the theme.
	if self._stroke then
		self._stroke:Destroy()
	end
	self._stroke = GPLayoutKit.SoftStroke(theme, chip, fill)

	-- THE HUE-MATCHED SHADOW: derived from this chip's OWN fill, so a matcha
	-- "New" casts sage and a coral "Sale" casts deep coral — never the same
	-- grey smear under both, which is what would make a row of stickers look
	-- printed instead of stuck on. Only packs declaring native shadow tokens
	-- pay; budget-counted, and the old handle is RELEASED, never leaked, on
	-- every restyle.
	if self._shadowHandle then
		self._shadowHandle:Release()
		self._shadowHandle = nil
	end
	if theme.EffectShadows then
		self._shadowHandle = GPLayoutKit.Shadow(theme, chip, "sm", nil, fill)
	end

	-- Type: the pack's Button face at the pack's Small cap, run through
	-- TextScaleConfig so the Theme Editor's live multiplier still applies. INK,
	-- never near-white — the measurement is in the header.
	label.FontFace = theme.Fonts.Button
	label.TextColor3 = theme.Colors.TextPrimary
	label.TextTransparency = 0 -- clears the born-transparent guard
	-- Re-assert the style's text emphasis AFTER the colour so a styled glow
	-- tracks the label (this pack sets TextGlowTransparency = 1, i.e. none).
	UIChrome.TextOutline(label)
	if self._labelConstraint then
		self._labelConstraint.MaxTextSize = TextScaleConfig.ScaledCap(theme.TextSizes.Small)
	end
end

function GPStickerBadge:Destroy()
	if self._shadowHandle then
		self._shadowHandle:Release()
		self._shadowHandle = nil
	end
	UIComponentBase.Destroy(self)
end

return GPStickerBadge
