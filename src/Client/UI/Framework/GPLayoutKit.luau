--!strict
-- GPLayoutKit — the shared builders of the "GP" LAYOUT language
-- (theme.LayoutKit == "GP"): Girly Pop, cutesy pastel ceramics for Pottery
-- Battles. Structurally this is GLLayoutKit's twin — same builder shapes, same
-- shadows-sink discipline, same graceful asset fallback — and aesthetically its
-- exact opposite. GL is hard ink, diagonal slam and sticker offsets; GP is warm
-- cream, petal corners and soft HUE-MATCHED shadows.
--
-- Screens branch their build the same way every other kit is entered:
--
--   function MyScreen:_BuildContent()
--       if self:LayoutKit() == "GP" then
--           self:_BuildGPLayout()
--           return
--       end
--       ... classic build ...
--   end
--
-- THE LAWS THIS KIT ENFORCES SO CALLERS CANNOT BREAK THEM:
--   * NO pure black and NO pure white, anywhere. Ink is Colors.TextPrimary (a
--     warm plum-brown); "white" is Colors.Background (warm cream). Every Frame
--     this kit builds is painted explicitly, because UIStyler.Frame is born
--     pure white and UIStyler.TextLabel is born pure-white text.
--   * SHADOWS ARE HUE-MATCHED, NEVER GREY. A rose element casts a rose shadow;
--     a matcha element casts a matcha one. Shadow() derives the colour from the
--     host's own fill (see Deepen) — this single rule carries more of the
--     aesthetic than everything else in the file combined.
--   * CONTRAST IS MEASURED. Body copy on rose/matcha uses TextPrimary
--     (5.15:1 / 6.39:1). Colors.TextOnPrimary (near-white) measures 2.14:1 on
--     rose and is never used here — not for labels, not for numerals, not for
--     tab captions.
--   * PETAL CORNERS are the signature shape, and they ALTERNATE by index so a
--     grid reads hand-arranged rather than stamped. One UICorner per instance,
--     ever: CornerRadius alongside per-corner radii is documented-undefined
--     engine behaviour, and two UICorner children is the same ambiguity by
--     another route — CornerSet() clears a stale corner before parenting.
--   * NO all-caps. Every other kit uppercases its titles, tabs and section
--     labels; this one passes copy through verbatim. Shouting at this audience
--     is the pack's named failure mode.
--   * ANTI-CONDESCENSION. A soft aesthetic is not a simple one. StatRow carries
--     the SAME column ladder, delta ghost and invertGoodness contract as the
--     Armored Core assembly row (UIStatRowComponent), at MORE precision — the
--     studio dialect ships statPrecision = 1 where AC rounds to integers.
--   * Shadows are budget-registered handles (disable-not-destroy on pooled
--     elements; Release on teardown) — see StyleKit.Capabilities.
--
-- WHY THE SHADOW PATH DOES NOT GO THROUGH UIChrome.Shadow: two reasons, both
-- structural. (1) Hue-matching needs a colour resolved AT THE CALL SITE from
-- the host's own fill; UIChrome resolves it from a static token. (2) This
-- pack's EffectShadows entries are SCALARS ({Blur, OffsetY, Spread} in px)
-- while UIShadow wants UDim/UDim2, and UIChrome.Shadow assigns token fields
-- straight onto the instance. So the normalization lives here (see `px`, which
-- accepts either token shape). The budget contract is untouched: every shadow
-- still passes through Capabilities.RegisterShadow, and every handle still
-- lands in a caller-owned sink for ReleaseShadows.
--
-- CLIPPING: the GL clipping law (ClipsDescendants is axis-aligned and does NOT
-- clip ROTATED descendants) does not bite here, because nothing in this pack
-- tilts — the angular language GL needed rotation for, GP gets from petal
-- silhouettes. Page therefore clips its panel and its content freely. The one
-- exception is Scallop's Top/Left/Right strips, which use Rotation to point the
-- doily art outward; those are page CHROME, positioned inside their host's
-- bounds, and must never be placed inside a scrolling viewport.
--
-- 0.4 BOUNDARY: this kit is pure STATIC COMPOSITION (Luau-built instances
-- painted from theme tokens). NOTHING HERE ANIMATES. The SetValue/SetPreview/
-- Select closures assign properties directly — no TweenService, no UITicker
-- handler, no RunService connection. Sequenced motion (kiln ceremonies, glaze
-- pours, celebration bursts) lives in the GP screen modules; styling-side state
-- looks arrive via StateDriver tags. Hover/press juice is the one delegated
-- exception: UIChrome.Animate owns it, so it stays one implementation.

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local IconVisibility = require(script.Parent.Parent.Icons.IconVisibility)
-- WaitForChild for the same reason UIChrome does it: this module can be
-- required while a newly-replicated sibling folder is still landing.
local Capabilities = require(script.Parent.Parent:WaitForChild("StyleKit"):WaitForChild("Capabilities"))

local GPLayoutKit = {}

-- ---- pack constants ----------------------------------------------------

-- Deepening moves a fill ALONG ITS OWN HUE: saturation up, value down. The
-- pull toward the pack's deep tint is deliberately small — a large one would
-- drag a matcha shadow toward rose and destroy the hue match.
local SHADOW_SAT_LIFT = 0.18
local SHADOW_VAL_DROP = 0.34
local SHADOW_STROKE_PULL = 0.18
-- Below this saturation a fill has no hue to deepen, and HSV-darkening it
-- would produce exactly the GREY this pack forbids.
local NEUTRAL_SATURATION = 0.12
local NEUTRAL_DEEP_BASE = 0.5
local NEUTRAL_DEEP_RANGE = 0.3
-- A glow BLOOMS rather than deepens: same hue, saturation lifted so a pale
-- pastel still auras visibly against cream.
local GLOW_SAT_LIFT = 0.22
local GLOW_MIN_VALUE = 0.82

local DIM_TRANSPARENCY = 0.5 -- warm scrim; the world stays readable behind it
local HEADER_H = 76
local SCALLOP_H = 18
local CLOSE_SIZE = 44
local CARD_NAME_H = 34
local TAB_W = 168
local TAB_H = 44
local TAB_BAR_H = 52
local PILL_W = 132
local PILL_H = 36

-- StatRow's fixed column ladder, measured from the RIGHT edge so every row in
-- a stack keeps its numerals flush regardless of label length. This is the AC
-- assembly row's ladder, re-proportioned for a wider numeric column (GP shows
-- a decimal place AC does not).
local STAT_ROW_H = 30
local STAT_BAR_H = 6
local STAT_BAR_GAP = 4
local STAT_UNIT_W = 40
local STAT_VALUE_W = 88
local STAT_DELTA_W = 60
local STAT_COL_GAP = 6
local STAT_LABEL_GAP = 10
local STAT_VALUE_PAD = 10

-- House shadow tokens in THIS PACK'S scalar shape, used when a theme declares
-- none. Never grey: the colour is always derived per call site.
local HOUSE_SHADOWS: { [string]: { Blur: number, OffsetY: number, Spread: number, Transparency: number } } = {
	sm = { Blur = 10, OffsetY = 4, Spread = 0, Transparency = 0.62 },
	md = { Blur = 16, OffsetY = 6, Spread = 1, Transparency = 0.58 },
	lg = { Blur = 22, OffsetY = 8, Spread = 2, Transparency = 0.55 },
	glow = { Blur = 24, OffsetY = 0, Spread = 4, Transparency = 0.55 },
}

-- ---- local helpers -----------------------------------------------------

local function assetDef(theme: Types.UITheme, key: string): any
	local assets = (theme :: any).Assets
	return assets and assets[key] or nil
end

-- Dialect namespace with a house fallback, so a pack that omits a namespace
-- still renders (never a different aesthetic).
local function dialect(theme: Types.UITheme, name: string): { [string]: any }
	local tokens = (theme :: any).DialectTokens
	return (tokens and tokens[name]) or {}
end

-- Accepts EITHER token shape: this pack's scalar px numbers, or the UDim/UDim2
-- shape the comic and terminal packs ship. Anything else falls back.
local function px(value: any, fallback: number): number
	if typeof(value) == "number" then
		return value
	elseif typeof(value) == "UDim" then
		return (value :: UDim).Offset
	elseif typeof(value) == "UDim2" then
		return (value :: UDim2).Y.Offset
	end
	return fallback
end

-- THE PACK, in one function. Deepen a fill along its OWN hue so the shadow it
-- casts belongs to it. See NEUTRAL_SATURATION for the cream/blush case.
local function deepen(theme: Types.UITheme, fill: Color3, strength: number?): Color3
	local k = math.clamp(strength or 1, 0, 1)
	local deep = theme.Colors.Stroke
	local h, s, v = fill:ToHSV()
	if s < NEUTRAL_SATURATION then
		-- A near-neutral fill (cream, blush-white, butter at low chroma) has no
		-- hue of its own to deepen. Borrow the pack's deep tint so a cream card
		-- still casts a WARM shadow instead of the grey the pack forbids.
		return fill:Lerp(deep, NEUTRAL_DEEP_BASE + NEUTRAL_DEEP_RANGE * k)
	end
	local deepened = Color3.fromHSV(
		h,
		math.clamp(s + SHADOW_SAT_LIFT * k, 0, 1),
		math.clamp(v * (1 - SHADOW_VAL_DROP * k), 0, 1)
	)
	return deepened:Lerp(deep, SHADOW_STROKE_PULL * k)
end

-- The fill a hue-matched effect should key off. GP surfaces are frequently
-- TINTED 9-SLICE IMAGES with a transparent background, so BackgroundColor3
-- alone would read UIStyler's unpainted default and every image plate would
-- cast the same shadow.
local function hostTint(theme: Types.UITheme, host: GuiObject): Color3
	if host.BackgroundTransparency < 1 then
		return host.BackgroundColor3
	end
	if host:IsA("ImageLabel") or host:IsA("ImageButton") then
		return (host :: any).ImageColor3
	end
	return theme.Colors.Surface
end

-- A Frame that is ALWAYS painted. UIStyler.Frame is born pure white, which
-- this pack forbids outright, so no builder here may use it bare.
local function surface(name: string, fill: Color3, transparency: number?): Frame
	local frame = UIStyler.Frame(name)
	frame.BackgroundColor3 = fill
	frame.BackgroundTransparency = transparency or 0
	return frame
end

-- 2px rounded-join stroke in a deepened tint of the fill it frames. Mitred
-- joins on a 24px petal radius read as a printing error at this scale.
local function softStroke(theme: Types.UITheme, fill: Color3): UIStroke
	local chrome = theme.Chrome
	local stroke = UIStyler.Stroke(
		deepen(theme, fill, 1),
		chrome and chrome.StrokeThickness or 2,
		chrome and chrome.StrokeTransparency or 0.35
	)
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	return stroke
end

local function applySlice(img: ImageLabel, def: any)
	img.Image = def.image
	if def.slice then
		img.ScaleType = Enum.ScaleType.Slice
		img.SliceCenter = def.slice
	end
end

-- Decoration-only slice: nil when the art is absent. Slice()'s soft tinted-
-- frame fallback is right for a STRUCTURAL plate (a card must exist whether or
-- not its art uploaded) but wrong for an OVERLAY — a missing sheen arc drawn as
-- a solid cream box would sit on top of the content it was meant to flatter.
local function sliceOptional(theme: Types.UITheme, key: string, tint: Color3, name: string): ImageLabel?
	local def = assetDef(theme, key)
	if not def then
		return nil
	end
	local img = Instance.new("ImageLabel")
	img.Name = name
	img.BackgroundTransparency = 1
	applySlice(img, def)
	img.ImageColor3 = tint
	return img
end

-- ========================================================================
-- Colour + stroke seams (public: screens compose their own surfaces too)
-- ========================================================================

function GPLayoutKit.Deepen(theme: Types.UITheme, fill: Color3, strength: number?): Color3
	return deepen(theme, fill, strength)
end

function GPLayoutKit.SoftStroke(theme: Types.UITheme, host: GuiObject, tint: Color3?): UIStroke
	local stroke = softStroke(theme, tint or hostTint(theme, host))
	stroke.Parent = host
	return stroke
end

-- ========================================================================
-- Text
-- ========================================================================

-- Display text (the pack's rounded chunky face). Colour defaults to the warm
-- plum-brown ink — never black, and never the near-white TextOnPrimary.
function GPLayoutKit.Text(theme: Types.UITheme, size: number, color: Color3?, name: string?): TextLabel
	return UIChrome.Text(name or "Label", size, color or theme.Colors.TextPrimary)
end

function GPLayoutKit.BodyText(theme: Types.UITheme, size: number, color: Color3?, name: string?): TextLabel
	return UIChrome.BodyText(name or "Body", size, color or theme.Colors.TextSecondary)
end

-- Tabular numerals. FontFace is assigned explicitly here and on every
-- symbol-bearing label in this file — the engine landmine the AC stat row
-- documents: a label that never had FontFace written keeps a default face and
-- breaks column alignment the moment the pack's numeric font differs.
function GPLayoutKit.NumberText(theme: Types.UITheme, size: number, color: Color3?, name: string?): TextLabel
	local label = UIStyler.TextLabel(name or "Number")
	label.FontFace = theme.Fonts.Numeric
	label.TextSize = size
	label.TextColor3 = color or theme.Colors.TextPrimary
	label.TextXAlignment = Enum.TextXAlignment.Right
	return label
end

-- ========================================================================
-- Art primitives
-- ========================================================================

-- A tinted 9-slice plate. Pack art is monochrome white-on-transparent, so the
-- tint IS the fill. Missing asset = a SOFT tinted frame with a 2px deepened-
-- tint stroke and the pack's medium radius — the same soft language, never a
-- hard placeholder box from some other aesthetic.
function GPLayoutKit.Slice(theme: Types.UITheme, key: string, tint: Color3, name: string?): ImageLabel
	local def = assetDef(theme, key)
	local img = Instance.new("ImageLabel")
	img.Name = name or key
	img.BackgroundTransparency = 1
	if def then
		applySlice(img, def)
	else
		-- TODO: asset missing — soft fallback chrome.
		img.BackgroundTransparency = 0
		img.BackgroundColor3 = tint
		UIStyler.Corner(theme.Radii.Medium).Parent = img
		softStroke(theme, tint).Parent = img
	end
	img.ImageColor3 = tint
	return img
end

-- A tiled pattern overlay (gingham / polkadot / clay speckle / crackle),
-- token-tinted. Square patterns carry `tile`; edge strips carry `tileX` and
-- `height`. These are pack CHROME, not iconography, so they are deliberately
-- NOT registered with IconVisibility — toggling icons off must not strip the
-- page's own surface texture.
function GPLayoutKit.Tile(theme: Types.UITheme, key: string, tint: Color3, transparency: number, name: string?): ImageLabel
	local def = assetDef(theme, key)
	local img = Instance.new("ImageLabel")
	img.Name = name or key
	img.BackgroundTransparency = 1
	if def then
		img.Image = def.image
		img.ScaleType = Enum.ScaleType.Tile
		img.TileSize = UDim2.fromOffset(def.tile or def.tileX or 128, def.tile or def.height or 128)
	end
	img.ImageColor3 = tint
	img.ImageTransparency = transparency
	img.Size = UDim2.fromScale(1, 1)
	return img
end

-- ========================================================================
-- Shadows and glows — THE PACK
-- ========================================================================

-- The soft HUE-MATCHED drop shadow. Colour comes from `tint`, or from the
-- host's own fill, deepened along its own hue. Returns the BUDGET HANDLE (it
-- owns SetEnabled/Release) and pushes it into the caller's sink so teardown can
-- release the count — a destroyed GuiObject alone would leak it.
function GPLayoutKit.Shadow(theme: Types.UITheme, host: GuiObject, intent: string?, sink: { any }?, tint: Color3?): any
	local key = intent or "md"
	local house = HOUSE_SHADOWS[key] or HOUSE_SHADOWS.md
	-- Explicitly `any`: the token may arrive in either shape (see `px`), so the
	-- field set is not statically known and must not be narrowed to the house
	-- record's four keys.
	local def: any = (theme.EffectShadows and (theme.EffectShadows :: any)[key]) or house
	local spread = px(def.Spread, house.Spread)

	local shadow = Instance.new("UIShadow")
	shadow.Name = "GPShadow_" .. key
	shadow.BlurRadius = UDim.new(0, px(def.Blur, house.Blur))
	-- `OffsetY or Offset`: 0 is truthy in Luau, so a zero-offset glow token
	-- still reads its own 0 rather than falling through to the other shape.
	shadow.Offset = UDim2.fromOffset(0, px(def.OffsetY or def.Offset, house.OffsetY))
	shadow.Spread = UDim2.fromOffset(spread, spread)
	shadow.Color = deepen(theme, tint or hostTint(theme, host), 1)
	shadow.Transparency = typeof(def.Transparency) == "number" and def.Transparency or house.Transparency
	shadow.Parent = host

	local handle = Capabilities.RegisterShadow(shadow)
	if sink then
		table.insert(sink, handle)
	end
	return handle
end

-- Zero-offset coloured aura for featured / selected / reward states. An aura is
-- the element BLOOMING, not falling into shade, so the colour keeps its own hue
-- at full value with saturation lifted — the opposite move to Deepen.
function GPLayoutKit.Glow(theme: Types.UITheme, host: GuiObject, tint: Color3?, sink: { any }?): any
	local fill = tint or hostTint(theme, host)
	local handle = GPLayoutKit.Shadow(theme, host, "glow", sink, fill)
	local shadow = handle.Instance
	shadow.Name = "GPGlow"
	local h, s, v = fill:ToHSV()
	if s < NEUTRAL_SATURATION then
		-- Nothing to bloom: a neutral aura would be a grey halo. The pack's
		-- value colour is what "featured" means here anyway.
		shadow.Color = theme.Colors.Accent
	else
		shadow.Color = Color3.fromHSV(h, math.clamp(s + GLOW_SAT_LIFT, 0, 1), math.max(v, GLOW_MIN_VALUE))
	end
	return handle
end

-- ========================================================================
-- Corners — the signature shape
-- ========================================================================

-- One UICorner per instance, always. A stale corner is destroyed rather than
-- joined, because two UICorner children (or CornerRadius alongside per-corner
-- radii) is documented-undefined engine behaviour.
function GPLayoutKit.CornerSet(theme: Types.UITheme, host: GuiObject, key: string): UICorner
	local stale = host:FindFirstChildOfClass("UICorner")
	if stale then
		stale:Destroy()
	end
	local corner = UIChrome.CornerSet(theme, key, "Panel")
	corner.Parent = host
	return corner
end

-- Petal or PetalMirror by index parity, so a grid of these reads hand-arranged
-- rather than stamped. Pass a card's grid index; pass index + 1 to a nested
-- well so the two shapes nest instead of fighting.
function GPLayoutKit.Petal(theme: Types.UITheme, host: GuiObject, index: number?): UICorner
	local key = (((index or 0) % 2) == 0) and "Petal" or "PetalMirror"
	return GPLayoutKit.CornerSet(theme, host, key)
end

-- ========================================================================
-- Glaze — the specular treatment
-- ========================================================================

-- What makes a flat pink rectangle read as CERAMIC: a broad top-lit wash that
-- dissolves by the glaze dialect's sheenHeightScale, plus the sheen arc riding
-- inside it. OPT-IN (glaze dialect); the matte studio dialect stays flat so
-- data-dense screens do not shimmer.
--
-- The wash clones the host's UICorner so it matches the silhouette exactly —
-- it can never square off a petal corner — and the ARC is inset so it never
-- reaches those corners and therefore never needs clipping.
--
-- ORDERING CONTRACT: give the host its corner FIRST (CornerSet/Petal, or a
-- UIStyler.Corner), then apply the sheen. Reversed, there is nothing to clone
-- and the wash renders square over a rounded plate.
function GPLayoutKit.GlazeSheen(theme: Types.UITheme, host: GuiObject): Frame
	local tokens = dialect(theme, "glaze")
	local heightScale = math.clamp(tokens.sheenHeightScale or 0.35, 0.05, 0.95)
	local sheenTransparency = tokens.sheenTransparency or 0.72
	-- Warm cream, NEVER white: pure white reads as a render artifact, and the
	-- pack forbids it outright.
	local light = theme.Colors.Background

	local wash = surface("GlazeSheen", light, sheenTransparency)
	wash.Size = UDim2.fromScale(1, 1)
	wash.ZIndex = host.ZIndex + 1
	local hostCorner = host:FindFirstChildOfClass("UICorner")
	if hostCorner then
		hostCorner:Clone().Parent = wash
	end

	-- White-to-transparent as a TRANSPARENCY ramp, not a colour ramp: a white
	-- ColorSequence keypoint would reintroduce the one colour this pack bans.
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(heightScale, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = wash
	wash.Parent = host

	local arc = sliceOptional(theme, "sheenArc", light, "SheenArc")
	if arc then
		arc.ImageTransparency = sheenTransparency
		arc.Position = UDim2.fromScale(0.06, 0.06)
		arc.Size = UDim2.new(0.88, 0, heightScale * 0.8, 0)
		arc.ZIndex = wash.ZIndex + 1
		arc.Parent = wash
	end
	return wash
end

-- ========================================================================
-- Scalloped edges
-- ========================================================================

export type ScallopEdge = "Top" | "Bottom" | "Left" | "Right"

-- The doily / pie-crust lip, tiled along one side of a host and hanging fully
-- OUTSIDE that side. Tint defaults to the host's own fill, so the scallop reads
-- as the surface itself dripping past its edge.
--
-- CAVEAT: Top/Left/Right rotate the strip to point the art outward, and Roblox
-- clipping is axis-aligned — a rotated descendant is not clipped by an ancestor
-- ClipsDescendants. These belong on page chrome, never inside a scrolling
-- viewport. "Bottom" is unrotated and safe anywhere.
function GPLayoutKit.Scallop(theme: Types.UITheme, host: GuiObject, edge: ScallopEdge?, tint: Color3?): ImageLabel
	local side: ScallopEdge = edge or "Bottom"
	local def = assetDef(theme, "scallopEdge")
	local height = (def and def.height) or SCALLOP_H
	local fill = tint or hostTint(theme, host)

	local strip = Instance.new("ImageLabel")
	strip.Name = "Scallop" .. side
	strip.BackgroundTransparency = 1
	strip.ImageColor3 = fill
	strip.ZIndex = host.ZIndex
	if def then
		strip.Image = def.image
		strip.ScaleType = Enum.ScaleType.Tile
		strip.TileSize = UDim2.fromOffset(def.tileX or 256, height)
	else
		-- TODO: asset missing — a soft rounded LIP in the same tint. Still
		-- soft, still hue-matched, never a hard placeholder bar.
		strip.BackgroundTransparency = 0
		strip.BackgroundColor3 = fill
		UIStyler.Corner(theme.Radii.Pill).Parent = strip
	end

	if side == "Left" or side == "Right" then
		-- A square whose side is the HOST'S HEIGHT. That is what lets a
		-- horizontally-tiled strip, rotated 90°, span a vertical edge exactly:
		-- there is no "parent height as my width" UDim to express it directly.
		local rail = surface("ScallopRail", fill, 1)
		rail.AnchorPoint = Vector2.new(0.5, 0.5)
		rail.Position = UDim2.fromScale(side == "Left" and 0 or 1, 0.5)
		rail.Size = UDim2.fromScale(1, 1)
		rail.ZIndex = host.ZIndex
		local square = Instance.new("UIAspectRatioConstraint")
		square.AspectRatio = 1
		square.DominantAxis = Enum.DominantAxis.Height
		square.AspectType = Enum.AspectType.ScaleWithParentSize
		square.Parent = rail
		rail.Parent = host

		strip.AnchorPoint = Vector2.new(0.5, 0.5)
		strip.Position = UDim2.new(0.5, side == "Left" and -height / 2 or height / 2, 0.5, 0)
		strip.Size = UDim2.new(1, 0, 0, height)
		strip.Rotation = side == "Left" and 90 or -90
		strip.Parent = rail
		return strip
	end

	if side == "Top" then
		strip.AnchorPoint = Vector2.new(0, 1)
		strip.Position = UDim2.fromScale(0, 0)
		strip.Rotation = 180
	else
		strip.AnchorPoint = Vector2.new(0, 0)
		strip.Position = UDim2.fromScale(0, 1)
	end
	strip.Size = UDim2.new(1, 0, 0, height)
	strip.Parent = host
	return strip
end

-- ========================================================================
-- THE PAGE
-- ========================================================================

export type Page = {
	dim: Frame,
	panel: Frame,
	header: Frame,
	title: TextLabel,
	subtitle: TextLabel,
	topRight: Frame,
	content: Frame,
	close: TextButton,
	shadows: { any },
}

-- Warm scrim → a cream plate with a soft rose shadow and clay-speckle grain →
-- an inset ROSE header ribbon with a glaze sheen and a scalloped bottom lip →
-- a transparent content field on the cream (cards ride ON the paper; a second
-- tinted well underneath them would flatten the card shadows that carry this
-- pack) → a petal close chip and a right-aligned counter slot in the ribbon.
--
-- The header is INSET rather than full-bleed for a concrete reason: a full-
-- bleed band would have to match the panel's 24px corner exactly or show cream
-- slivers at the top corners, and the inset ribbon reads better anyway.
--
-- The returned `shadows` array is the screen's SINK: pass it to every Card /
-- Tabs / PricePill built into this page, and release it in _OnTeardown with
-- ReleaseShadows so the budget counter comes back down.
function GPLayoutKit.Page(theme: Types.UITheme, root: Instance, opts: {
	titleText: string,
	subtitleText: string?,
	sizePx: Vector2?,
	onClose: (() -> ())?,
	showClose: boolean?,
	glaze: boolean?,
}): Page
	local shadows: { any } = {}
	local spacing = theme.Spacing
	local size = opts.sizePx or Vector2.new(1010, 660)

	local dim = surface("Dim", theme.Colors.Overlay, DIM_TRANSPARENCY)
	dim.Size = UDim2.fromScale(1, 1)
	dim.Parent = root

	local panelFill = theme.Colors.Background
	local panel = surface("GPPanel", panelFill, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(size.X, size.Y)
	-- Safe to clip: nothing in this pack rotates (see the CLIPPING note in the
	-- header), and scrolled rows must never spill past the cream plate. The
	-- panel's OWN shadow is unaffected — a parent clips its children, not the
	-- shadow the child itself casts outward from its own rect.
	panel.ClipsDescendants = true
	panel.Parent = root
	UIStyler.Corner(theme.Radii.Large).Parent = panel
	softStroke(theme, panelFill).Parent = panel
	GPLayoutKit.Shadow(theme, panel, "lg", shadows, panelFill)

	local studioTokens = dialect(theme, "studio")
	local grain = GPLayoutKit.Tile(
		theme,
		studioTokens.patternKey or "speckle",
		deepen(theme, panelFill, 1),
		studioTokens.speckleTransparency or 0.94,
		"ClayGrain"
	)
	grain.ZIndex = 2
	grain.Parent = panel

	local headerFill = theme.Colors.Primary
	local header = surface("Header", headerFill, 0)
	header.Position = UDim2.fromOffset(spacing.S, spacing.S)
	header.Size = UDim2.new(1, -spacing.S * 2, 0, HEADER_H)
	header.ZIndex = 4
	header.Parent = panel
	-- "Tab": rounded across the top, flat along the bottom the scallop hangs
	-- from. A petal set here would fight the lip.
	GPLayoutKit.CornerSet(theme, header, "Tab")
	softStroke(theme, headerFill).Parent = header
	GPLayoutKit.Shadow(theme, header, "md", shadows, headerFill)
	if opts.glaze ~= false then
		GPLayoutKit.GlazeSheen(theme, header)
	end
	GPLayoutKit.Scallop(theme, header, "Bottom", headerFill)

	-- Copy is passed through VERBATIM: no string.upper anywhere in this kit.
	local title = GPLayoutKit.Text(theme, theme.TextSizes.Title, theme.Colors.TextPrimary, "Title")
	title.Text = opts.titleText
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Position = UDim2.fromOffset(spacing.L, spacing.S)
	title.Size = UDim2.new(0.5, -spacing.L, 0, 38)
	title.ZIndex = 6
	title.Parent = header

	-- TextPrimary, not TextSecondary and certainly not TextOnPrimary: this is
	-- body-sized copy sitting on rose, where the near-white measures 2.14:1.
	local subtitle = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "Subtitle")
	subtitle.Text = opts.subtitleText or ""
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.TextTruncate = Enum.TextTruncate.AtEnd
	subtitle.Position = UDim2.fromOffset(spacing.L, spacing.S + 38)
	subtitle.Size = UDim2.new(0.5, -spacing.L, 0, 22)
	subtitle.Visible = opts.subtitleText ~= nil and opts.subtitleText ~= ""
	subtitle.ZIndex = 6
	subtitle.Parent = header

	local topRight = surface("TopRight", panelFill, 1)
	topRight.AnchorPoint = Vector2.new(1, 0.5)
	topRight.Position = UDim2.new(1, -(CLOSE_SIZE + spacing.M + spacing.S), 0.5, 0)
	topRight.Size = UDim2.fromOffset(360, CLOSE_SIZE)
	topRight.ZIndex = 6
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, spacing.S),
	}).Parent = topRight
	topRight.Parent = header

	-- The button itself stays TRANSPARENT and the fill lives on a chip child.
	-- UIStyleEnforcer backstops any SOLID GuiButton with a BLACK 2px stroke,
	-- which would violate law 1 on sight; a transparent button never trips it.
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.BackgroundTransparency = 1
	close.Text = ""
	close.AutoButtonColor = false
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.new(1, -spacing.M, 0.5, 0)
	close.Size = UDim2.fromOffset(CLOSE_SIZE, CLOSE_SIZE)
	close.ZIndex = 7
	close.Visible = opts.showClose ~= false
	close.Parent = header

	local closeFill = theme.Colors.SurfaceRaised
	local closeChip = surface("CloseChip", closeFill, 0)
	closeChip.Size = UDim2.fromScale(1, 1)
	closeChip.ZIndex = 7
	closeChip.Parent = close
	GPLayoutKit.Petal(theme, closeChip, 1)
	softStroke(theme, closeFill).Parent = closeChip
	GPLayoutKit.Shadow(theme, closeChip, "sm", shadows, closeFill)

	-- A letterform, not an archive icon: the icon pack's close art is full
	-- colour and would be the one loud thing on a pastel ribbon. Every pack's
	-- close in this framework is a display-face "X" (see UIChrome).
	local closeGlyph = GPLayoutKit.Text(theme, 24, theme.Colors.TextPrimary, "X")
	closeGlyph.Text = "X"
	closeGlyph.Size = UDim2.fromScale(1, 1)
	closeGlyph.ZIndex = 8
	closeGlyph.Parent = close
	if opts.onClose then
		close.Activated:Connect(opts.onClose)
	end
	UIChrome.Animate(theme, close, closeChip)

	local top = spacing.S + HEADER_H + SCALLOP_H + spacing.M
	local content = surface("Content", panelFill, 1)
	content.Position = UDim2.fromOffset(spacing.M, top)
	content.Size = UDim2.new(1, -spacing.M * 2, 1, -(top + spacing.L))
	content.ClipsDescendants = true
	content.ZIndex = 3
	content.Parent = panel

	return {
		dim = dim,
		panel = panel,
		header = header,
		title = title,
		subtitle = subtitle,
		topRight = topRight,
		content = content,
		close = close,
		shadows = shadows,
	}
end

-- ========================================================================
-- The card atom
-- ========================================================================

export type Card = {
	root: TextButton,
	body: Frame,
	art: Frame,
	artImage: ImageLabel,
	artLabel: TextLabel,
	name: TextLabel,
	shadow: any,
}

-- Petal-cornered plate (mirrored by index), soft hue shadow, art well, name
-- line. The well takes the MIRROR of the body's petal so the two silhouettes
-- nest rather than fight, and the plate rides LIGHTER than the page so the
-- shadow it casts actually reads.
function GPLayoutKit.Card(theme: Types.UITheme, parent: Instance, index: number?, sink: { any }?): Card
	local i = index or 0
	local spacing = theme.Spacing

	local root = Instance.new("TextButton")
	root.Name = "GPCard"
	root.BackgroundTransparency = 1 -- see the enforcer note in Page
	root.Text = ""
	root.AutoButtonColor = false
	root.Parent = parent

	local bodyFill = theme.Colors.SurfaceRaised
	local body = surface("Body", bodyFill, 0)
	body.Size = UDim2.fromScale(1, 1)
	body.Parent = root
	GPLayoutKit.Petal(theme, body, i)
	softStroke(theme, bodyFill).Parent = body
	local shadow = GPLayoutKit.Shadow(theme, body, "sm", sink, bodyFill)

	local studioTokens = dialect(theme, "studio")
	local grain = GPLayoutKit.Tile(
		theme,
		studioTokens.patternKey or "speckle",
		deepen(theme, bodyFill, 1),
		studioTokens.speckleTransparency or 0.94,
		"Grain"
	)
	grain.ZIndex = 2
	grain.Parent = body

	local wellFill = theme.Colors.Surface
	local art = surface("ArtWell", wellFill, 0)
	art.Position = UDim2.fromOffset(spacing.S, spacing.S)
	art.Size = UDim2.new(1, -spacing.S * 2, 1, -(spacing.S * 2 + CARD_NAME_H))
	art.ZIndex = 3
	art.Parent = body
	GPLayoutKit.Petal(theme, art, i + 1)
	softStroke(theme, wellFill).Parent = art

	local artImage = Instance.new("ImageLabel")
	artImage.Name = "ArtImage"
	artImage.BackgroundTransparency = 1
	artImage.ScaleType = Enum.ScaleType.Fit
	artImage.AnchorPoint = Vector2.new(0.5, 0.5)
	artImage.Position = UDim2.fromScale(0.5, 0.5)
	artImage.Size = UDim2.fromScale(0.82, 0.82)
	artImage.Visible = false
	artImage.ZIndex = 5
	artImage.Parent = art

	-- Sentence case: the placeholder is copy, and copy is never shouted here.
	local artLabel = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "ArtLabel")
	artLabel.Text = "Art slot"
	artLabel.Size = UDim2.fromScale(1, 1)
	artLabel.ZIndex = 4
	artLabel.Parent = art

	local name = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "Name")
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.AnchorPoint = Vector2.new(0, 1)
	name.Position = UDim2.new(0, spacing.M, 1, -spacing.S)
	name.Size = UDim2.new(1, -spacing.M * 2, 0, CARD_NAME_H - spacing.S)
	name.ZIndex = 4
	name.Parent = body

	UIChrome.Animate(theme, root, body)
	return { root = root, body = body, art = art, artImage = artImage, artLabel = artLabel, name = name, shadow = shadow }
end

-- Fill an art slot from the ICON ARCHIVE. Items carry a semantic iconKey
-- ("chest", "gift", "crate"...) which the archive resolves to uploaded art,
-- with item.iconId as the last-resort literal. When nothing resolves the slot
-- keeps its visible placeholder rather than rendering blank.
function GPLayoutKit.ApplyItemArt(entry: { artImage: ImageLabel?, artLabel: TextLabel? }, item: any)
	local image = entry.artImage
	local label = entry.artLabel
	if not image then
		return
	end
	local assetId: string? = nil
	local key = (item :: any).iconKey
	if key then
		assetId = IconArchive.Id(key, { golden = (item :: any).iconGolden })
	end
	if not assetId or assetId == "" then
		local literal = (item :: any).iconId
		if literal and literal ~= "" then
			assetId = literal
		end
	end
	if assetId and assetId ~= "" then
		image.Image = assetId
		image.Visible = true
		IconVisibility.Register(image)
		if label then
			label.Visible = false
		end
	else
		image.Visible = false
		if label then
			label.Visible = true
		end
	end
end

-- ========================================================================
-- Value
-- ========================================================================

export type PricePill = {
	root: Frame,
	icon: ImageLabel,
	amount: TextLabel,
	shadow: any,
}

-- Butter-gold value pill: pill radius, deepened-butter stroke, soft amber
-- shadow. Numerals are TextPrimary — butter is a LIGHT fill and the near-white
-- TextOnPrimary would vanish on it.
function GPLayoutKit.PricePill(theme: Types.UITheme, parent: Instance, sink: { any }?): PricePill
	local fill = theme.Arcade.Gold
	local pill = surface("PricePill", fill, 0)
	pill.Size = UDim2.fromOffset(PILL_W, PILL_H)
	pill.ZIndex = 4
	pill.Parent = parent
	UIStyler.Corner(theme.Radii.Pill).Parent = pill
	softStroke(theme, fill).Parent = pill
	local shadow = GPLayoutKit.Shadow(theme, pill, "sm", sink, fill)

	local icon = Instance.new("ImageLabel")
	icon.Name = "Glyph"
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, theme.Spacing.S, 0.5, 0)
	icon.Size = UDim2.fromOffset(22, 22)
	icon.ZIndex = 5
	icon.Parent = pill
	IconVisibility.Register(icon)

	local amount = GPLayoutKit.NumberText(theme, theme.TextSizes.Button, theme.Colors.TextPrimary, "Amount")
	amount.Position = UDim2.fromOffset(theme.Spacing.S * 2 + 22, 0)
	amount.Size = UDim2.new(1, -(theme.Spacing.S * 3 + 22), 1, 0)
	amount.ZIndex = 5
	amount.Parent = pill
	return { root = pill, icon = icon, amount = amount, shadow = shadow }
end

-- ========================================================================
-- Tabs
-- ========================================================================

export type TabBar = {
	frame: Frame,
	Add: (text: string, id: string, onClick: (() -> ())?) -> (),
	Select: (id: string) -> (),
}

-- Tab-cornered row. SELECTED reads FORWARD — rose fill, a butter underline and
-- a scale step — never a default-blue recolour. The selected tab's SHADOW
-- retints with its fill, which is the pack's rule demonstrated in an
-- interactive state: a rose tab casts rose, an idle blush tab casts blush.
--
-- Two independent UIScales are in play by design: this one on the button for
-- selection, and UIChrome.Animate's on the shape for hover. They compose, so a
-- hovered selected tab reads as both.
function GPLayoutKit.Tabs(theme: Types.UITheme, parent: Instance, opts: {
	widthPx: number?,
	heightPx: number?,
	tabHeightPx: number?,
}?, sink: { any }?): TabBar
	local o = opts or {}
	local spacing = theme.Spacing

	local bar = surface("Tabs", theme.Colors.Background, 1)
	bar.Size = UDim2.new(1, 0, 0, o.heightPx or TAB_BAR_H)
	bar.ZIndex = 4
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, spacing.S),
	}).Parent = bar
	bar.Parent = parent

	local entries: { [string]: any } = {}
	local order = 0
	local selectedScale = theme.Motion.HoverScale

	local function select(id: string)
		for entryId, entry in entries do
			local on = entryId == id
			local fill = on and theme.Colors.Primary or theme.Colors.Surface
			local deep = deepen(theme, fill, 1)
			entry.shape.BackgroundColor3 = fill
			entry.stroke.Color = deep
			entry.shadow.Instance.Color = deep
			-- Body-sized copy on rose MUST be TextPrimary (5.15:1); the
			-- near-white TextOnPrimary measures 2.14:1 and is illegal here.
			entry.label.TextColor3 = on and theme.Colors.TextPrimary or theme.Colors.TextSecondary
			entry.underline.Visible = on
			entry.scale.Scale = on and selectedScale or 1
		end
	end

	local function add(text: string, id: string, onClick: (() -> ())?)
		order += 1
		local tab = Instance.new("TextButton")
		tab.Name = "Tab_" .. id
		tab.BackgroundTransparency = 1 -- see the enforcer note in Page
		tab.Text = ""
		tab.AutoButtonColor = false
		tab.Size = UDim2.fromOffset(o.widthPx or TAB_W, o.tabHeightPx or TAB_H)
		tab.LayoutOrder = order
		tab.ZIndex = 4
		tab.Parent = bar

		local scale = Instance.new("UIScale")
		scale.Parent = tab

		local idleFill = theme.Colors.Surface
		local shape = surface("Shape", idleFill, 0)
		shape.Size = UDim2.fromScale(1, 1)
		shape.ZIndex = 4
		shape.Parent = tab
		GPLayoutKit.CornerSet(theme, shape, "Tab")
		local stroke = softStroke(theme, idleFill)
		stroke.Parent = shape
		local shadow = GPLayoutKit.Shadow(theme, shape, "sm", sink, idleFill)

		local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Button, theme.Colors.TextSecondary, "Label")
		label.Text = text -- verbatim: no string.upper in this pack
		label.Size = UDim2.fromScale(1, 1)
		label.ZIndex = 5
		label.Parent = shape

		local underline = surface("Underline", theme.Colors.Accent, 0)
		underline.AnchorPoint = Vector2.new(0.5, 1)
		underline.Position = UDim2.new(0.5, 0, 1, -spacing.S)
		underline.Size = UDim2.new(0.56, 0, 0, 4)
		underline.Visible = false
		underline.ZIndex = 6
		UIStyler.Corner(theme.Radii.Pill).Parent = underline
		underline.Parent = shape

		if onClick then
			tab.Activated:Connect(onClick)
		end
		UIChrome.Animate(theme, tab, shape)
		entries[id] = { shape = shape, stroke = stroke, shadow = shadow, label = label, underline = underline, scale = scale }
	end

	return { frame = bar, Add = add, Select = select }
end

-- ========================================================================
-- StatRow — the anti-condescension proof
-- ========================================================================

export type StatRow = {
	root: Frame,
	label: TextLabel,
	value: TextLabel,
	unit: TextLabel,
	delta: TextLabel,
	capsule: Frame,
	track: Frame,
	fill: Frame,
	ghost: Frame,
	SetValue: (number) -> (),
	SetPreview: (number?) -> (),
}

-- The dense data row, at the Armored Core assembly row's density and ONE MORE
-- decimal place. Fixed right-anchored column ladder (unit / value capsule /
-- signed delta) over a magnitude bar, with the part-swap DELTA GHOST: a second
-- bar segment spanning value→preview, painted Success when the change is GOOD
-- and Error when BAD, `invertGoodness` flipping the mapping for lower-is-better
-- stats. The sign prefix is ALWAYS printed, so meaning never rides on hue alone.
--
-- Deliberately shadow-free: twenty of these in a column would eat a quarter of
-- the 80-shadow budget and turn a data table into a sticker sheet. Depth here
-- comes from the capsule and the rounded track.
--
-- Copy is NOT uppercased. The AC row shouts its labels; this pack does not.
function GPLayoutKit.StatRow(theme: Types.UITheme, parent: Instance, opts: {
	label: string,
	value: number?,
	maxValue: number?,
	unit: string?,
	precision: number?,
	invertGoodness: boolean?,
	accent: Color3?,
	heightPx: number?,
	layoutOrder: number?,
}): StatRow
	local studioTokens = dialect(theme, "studio")
	local height = opts.heightPx or studioTokens.statRowHeight or STAT_ROW_H
	local precision = math.max(0, math.floor(opts.precision or studioTokens.statPrecision or 1))
	local maxValue = opts.maxValue or 100
	local invert = opts.invertGoodness == true
	local accent = opts.accent or theme.Colors.Primary
	local textH = height - STAT_BAR_H - STAT_BAR_GAP
	local valueFormat = "%." .. precision .. "f"
	local deltaFormat = "%+." .. precision .. "f"
	-- Half a display unit: a change too small to be PRINTED must not draw a
	-- ghost, or the row shows a coloured bar next to a "+0.0".
	local epsilon = 0.5 * 10 ^ -precision

	local root = surface("GPStatRow", theme.Colors.Background, 1)
	root.Size = UDim2.new(1, 0, 0, height)
	if opts.layoutOrder then
		root.LayoutOrder = opts.layoutOrder
	end
	root.Parent = parent

	local x = STAT_UNIT_W
	local unit = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Unit")
	unit.Text = opts.unit or ""
	unit.TextXAlignment = Enum.TextXAlignment.Left
	unit.Position = UDim2.new(1, -x, 0, 0)
	unit.Size = UDim2.new(0, STAT_UNIT_W, 0, textH)
	unit.Parent = root

	x += STAT_COL_GAP + STAT_VALUE_W
	local capsule = surface("ValueCapsule", theme.Colors.Surface, 0)
	capsule.Position = UDim2.new(1, -x, 0, 0)
	capsule.Size = UDim2.new(0, STAT_VALUE_W, 0, textH)
	capsule.Parent = root
	UIStyler.Corner(theme.Radii.Pill).Parent = capsule

	local value = GPLayoutKit.NumberText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "Value")
	value.Size = UDim2.new(1, -STAT_VALUE_PAD, 1, 0)
	value.Parent = capsule

	x += STAT_COL_GAP + STAT_DELTA_W
	local delta = GPLayoutKit.NumberText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Delta")
	delta.Text = ""
	delta.Position = UDim2.new(1, -x, 0, 0)
	delta.Size = UDim2.new(0, STAT_DELTA_W, 0, textH)
	delta.Parent = root

	local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Label")
	label.Text = opts.label
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Size = UDim2.new(1, -(x + STAT_LABEL_GAP), 0, textH)
	label.Parent = root

	local track = surface("Track", theme.Arcade.RulerTrack, 0)
	track.Position = UDim2.new(0, 0, 1, -STAT_BAR_H)
	track.Size = UDim2.new(1, 0, 0, STAT_BAR_H)
	track.Parent = root
	UIStyler.Corner(theme.Radii.Pill).Parent = track

	local fill = surface("Fill", accent, 0)
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = 2
	fill.Parent = track
	UIStyler.Corner(theme.Radii.Pill).Parent = fill

	local ghost = surface("PreviewGhost", theme.Colors.Success, 0)
	ghost.Size = UDim2.fromScale(0, 1)
	ghost.ZIndex = 3
	ghost.Visible = false
	ghost.Parent = track
	UIStyler.Corner(theme.Radii.Pill).Parent = ghost

	local current = opts.value or 0
	local preview: number? = nil

	local function ratioOf(v: number): number
		return if maxValue > 0 then math.clamp(v / maxValue, 0, 1) else 0
	end

	-- Static composition: a direct assign, never a tween (see the 0.4 boundary
	-- note in the header).
	local function renderPreview()
		if preview == nil then
			ghost.Visible = false
			delta.Text = ""
			delta.TextColor3 = theme.Colors.TextSecondary
			return
		end
		local diff = preview - current
		if math.abs(diff) < epsilon then
			ghost.Visible = false
			delta.Text = string.format(deltaFormat, 0)
			delta.TextColor3 = theme.Colors.TextSecondary
			return
		end
		local vRatio, pRatio = ratioOf(current), ratioOf(preview)
		local lo, hi = math.min(vRatio, pRatio), math.max(vRatio, pRatio)
		local good = (diff > 0) ~= invert
		local tone = if good then theme.Colors.Success else theme.Colors.Error
		ghost.Visible = true
		ghost.Position = UDim2.fromScale(lo, 0)
		ghost.Size = UDim2.fromScale(hi - lo, 1)
		ghost.BackgroundColor3 = tone
		delta.Text = string.format(deltaFormat, diff)
		delta.TextColor3 = tone
	end

	local function setValue(v: number)
		current = v
		value.Text = string.format(valueFormat, v)
		fill.Size = UDim2.fromScale(ratioOf(v), 1)
		renderPreview()
	end

	local function setPreview(v: number?)
		preview = v
		renderPreview()
	end

	setValue(current)

	return {
		root = root,
		label = label,
		value = value,
		unit = unit,
		delta = delta,
		capsule = capsule,
		track = track,
		fill = fill,
		ghost = ghost,
		SetValue = setValue,
		SetPreview = setPreview,
	}
end

-- ========================================================================
-- Quiet furniture
-- ========================================================================

-- Squiggle divider in the studio dialect's sage rule colour.
function GPLayoutKit.Divider(theme: Types.UITheme, parent: Instance): ImageLabel
	local def = assetDef(theme, "squiggle")
	local sage = dialect(theme, "studio").rule or theme.Studio.Tan
	local rule = Instance.new("ImageLabel")
	rule.Name = "Divider"
	rule.BackgroundTransparency = 1
	rule.ImageColor3 = sage
	if def then
		rule.Image = def.image
		rule.ScaleType = Enum.ScaleType.Tile
		rule.TileSize = UDim2.fromOffset(def.tileX or 256, def.height or 16)
		rule.Size = UDim2.new(1, 0, 0, def.height or 16)
	else
		-- TODO: asset missing — the studio dialect's own SAGE HAIRLINE, rounded.
		rule.BackgroundTransparency = 0
		rule.BackgroundColor3 = sage
		rule.Size = UDim2.new(1, 0, 0, 2)
		UIStyler.Corner(theme.Radii.Pill).Parent = rule
	end
	rule.Parent = parent
	return rule
end

-- Quiet section label. The text is passed through VERBATIM — every sibling kit
-- uppercases here, and doing so would both break law 5 and mangle a caller's
-- deliberate "Glaze quality".
function GPLayoutKit.SectionLabel(theme: Types.UITheme, parent: Instance, text: string): TextLabel
	local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Section")
	label.Text = text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Size = UDim2.new(1, 0, 0, 24)
	label.Parent = parent
	return label
end

-- Archive art, with the archive's GLYPH FALLBACK repainted into this pack's
-- ink. That fallback is born PURE WHITE with a PURE BLACK text stroke — both
-- banned outright here — and it only appears when a role's art is missing,
-- which is precisely the moment a screen must not start rendering the two
-- forbidden colours. Real uploaded art comes back untouched (and already
-- IconVisibility-registered by the archive).
function GPLayoutKit.Icon(theme: Types.UITheme, parent: Instance?, nameOrAlias: string, sizePx: number): GuiObject
	local icon = IconArchive.Image(parent, nameOrAlias, sizePx)
	if icon:IsA("TextLabel") then
		icon.TextColor3 = theme.Colors.TextPrimary
		icon.TextStrokeTransparency = 1
	end
	return icon
end

-- ========================================================================
-- Copy casing — THE ONE RULE for this pack
-- ========================================================================

-- Two-letter ALL-CAPS words are the ambiguous case: "UI", "QA", "OK", "XP" are
-- acronyms that must survive intact, while "IN", "OF", "TO" are ordinary words
-- — and "Server Restart IN 04:32" is exactly the shouting law 5 forbids. So
-- only the short FUNCTION words are retitled; every other run of two
-- characters or fewer stands as authored.
local SHORT_WORDS: { [string]: boolean } = {
	AN = true, AS = true, AT = true, BE = true, BY = true, DO = true,
	GO = true, IF = true, IN = true, IS = true, IT = true, ME = true,
	MY = true, NO = true, OF = true, ON = true, OR = true, SO = true,
	TO = true, UP = true, WE = true,
}

-- Retitle SHOUTED copy for DISPLAY. Strings reach the screens pre-uppercased
-- from config, data and shared render code every other kit shares; forking that
-- source would change what every pack shows, so the retitle happens here, at
-- the last possible moment, and only on the GP path.
--
-- This is the pack's SINGLE casing rule — screens must not carry their own, or
-- "VIP" renders one way in a modal title and another in a credits role.
-- Wholly-uppercase runs are retitled; a mixed-case word is left exactly as
-- authored (so "sable_dev" and "echo.wav" survive); a RichText string is passed
-- through whole rather than half-lowercased inside its own markup.
function GPLayoutKit.TitleCase(text: string): string
	if string.find(text, "<", 1, true) then
		return text
	end
	return (string.gsub(text, "[%a][%w']*", function(word: string): string
		if word ~= string.upper(word) then
			return word
		end
		if #word < 3 and not SHORT_WORDS[word] then
			return word
		end
		return string.upper(string.sub(word, 1, 1)) .. string.lower(string.sub(word, 2))
	end))
end

-- Release every shadow handle a screen collected (teardown contract). Call
-- from _OnTeardown: a destroyed GuiObject alone leaves the budget counter high.
function GPLayoutKit.ReleaseShadows(sink: { any }?)
	if not sink then
		return
	end
	for _, handle in sink do
		handle:Release()
	end
	table.clear(sink)
end

return GPLayoutKit
