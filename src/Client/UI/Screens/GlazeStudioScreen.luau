--!strict
-- GlazeStudioScreen — THE FINISHING BENCH of Pottery Battles, rebuilt as a page.
--
-- SOURCE OF TRUTH: the live game's PotteryFlow.client.luau (2653 lines) owns the
-- Shape -> Glaze flow as a scatter of floating side panels over the wheel. Every
-- control it has is here; nothing was dropped and the numeric contracts are
-- unchanged. The parity list, control by control:
--
--   glaze toolbar   Paint / Erase / Fill (the attribute value stays "Paint" —
--                   the game's wheel + accessory scripts gate on that literal),
--                   brush size 0.015..1.0 (default 0.4), "Reset paint", "Back".
--   glaze panel     the tall swatch scroller: stock glazes, the generated
--                   rainbow block, and the "My Mixes" tail rebuilt WHOLE on each
--                   push — never spliced, because splicing shifts every index
--                   under a live selection. Selection survives the rebuild BY
--                   NAME, exactly as the source does.
--   glaze surface   the selected glaze's material signature (roughness /
--                   metalness) — the source publishes GlazeRough/GlazeMetal but
--                   never showed them. Now it does.
--   paint meter     PaintStock over a 24-unit reference: sage above 6, butter
--                   under 6, terracotta at 0, and the exact source nudge
--                   "Out of glaze — buy barrels at Storage".
--   carve bar       Hands / Groove / Ridge, Groove's V|U profile sub-row, Ridge's
--                   1|2|4|8 symmetry grid, the height toggle, "Reset clay".
--                   Ridge parks the wheel and puts the spin back on unequip.
--   depth panel     the Guide flyout: on/off, Distance 0.3..GUIDE_MAX studs,
--                   Angle -1..1 as a centre-origin dial, plus the top slide with
--                   its spin-axis notch and draggable marker. Slide and Distance
--                   are TWO-WAY synced through the same echo guard the source
--                   uses (guideSyncing), and the marker's side of the axis is
--                   derived from the drag, never from a separate control.
--   accessory bar   the picker: owned-count badge, the out-of-stock scrim
--                   "Buy at Storage" (kept verbatim), the empty-state line, and
--                   selection that publishes folder + name.
--   placement       Symmetry 1..8 (step 1), Rotate 0..360 (step 15), Scale
--                   0.25..3 (step 0.25), "Done" / "Remove" shown ONLY while a
--                   piece is selected, and "Clear".
--
-- SLIDER PRECISION IS A CONTRACT. The source prints a step >= 1 as "%d" and
-- everything else as "%.2f". Symmetry and Rotate are integers; Scale, Distance,
-- Angle and Brush carry two decimals. sliderFormat() is that one rule, and every
-- readout in this screen runs through it.
--
-- THE UPGRADE (GP / DialectGlaze):
--   * Glossy petal panels. The glaze chip, the band preview and the paint meter
--     fill carry GPLayoutKit.GlazeSheen — applied to LEAF elements only, since
--     the sheen wash is a sibling that would otherwise sit over a panel's own
--     content (ZIndex is sibling-relative).
--   * The swatch shelf is a GRID with rarity-tinted rings from
--     theme.DialectTokens.rarity, petal corners alternating by index, and the
--     ring going solid on the chosen glaze — the source's cream-ring language,
--     now carrying rarity as well as selection.
--   * Paint and depth read as rounded pastel bars, and the whole bench keeps a
--     live readout column of eleven GPLayoutKit.StatRows.
--   * The placement dials use the StatRow DELTA GHOST: while a piece is selected
--     the sliders drive a PREVIEW, the row shows the signed change against the
--     committed value, and "Done" is what commits it. That is the source's
--     confirm semantics made visible instead of invisible.
--
-- ANTI-CONDESCENSION (pack law 6): feature count and data density only went UP.
-- Eleven live stats, a material signature, a rarity ladder and a coverage meter
-- are all additions; nothing the source had was simplified away.
--
-- SHADOW BUDGET: structural panels only. Twenty-four swatches and eleven picker
-- rows carry NO shadow — depth there comes from the petal silhouette and the
-- deepened stroke. Every handle taken lands in self._shadows and is released in
-- _OnTeardown.

local UserInputService = game:GetService("UserInputService")

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local IconVisibility = require(script.Parent.Parent.Icons.IconVisibility)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local UITicker = require(script.Parent.Parent.Framework.UITicker)
local UIScreenBase = require(script.Parent.UIScreenBase)

-- ========================================================================
-- TYPES
-- ========================================================================

export type Glaze = {
	name: string,
	color: Color3,
	rarity: number, -- 1..5, indexes theme.DialectTokens.rarity
	rough: number?, -- material signature (GlazeRough); nil = the wheel's stock literal
	metal: number?, -- material signature (GlazeMetal)
	textured: boolean?, -- a real SurfaceAppearance behind it, not a flat colour
	custom: boolean?, -- lives in the "My Mixes" tail
}

export type Accessory = {
	folder: string,
	name: string,
	iconKey: string?,
	owned: number?, -- nil = stock unknown (pre-push): never grey a card on unknown
}

-- ========================================================================
-- STUDIO CONFIG — every literal this screen renders, in one table.
-- ========================================================================

local STUDIO = {
	titleText = "Glaze studio",
	subtitleText = "Finish the piece — paint it, carve it, dress it up.",

	-- Verbatim from the source: these two strings are what players already know.
	outOfGlaze = "Out of glaze \u{2014} buy barrels at Storage",
	buyAtStorage = "Buy at Storage",
	storageFull = "Storage is full \u{2014} sell or clear a pot before firing another.",
	lowClay = "Low on clay \u{2014} restock at Storage",
	noAccessories = "Add an 'Accessories' folder with Handle / Decorative sub-folders.",
	placementHint = "Pick one at the right, then click the pot to place it. Click a piece and drag its arrows to move or its rings to spin; scale, rotation and symmetry live here.",
	guideHint = "While the guide is on, the mold line is a hard wall \u{2014} the clay stops at it from either side.",
	guideNotHands = "The mold line steers the hands. Pick Hands on the bench and the guide comes back with its distance and tilt where you left them.",
	emptyShelf = "Nothing picked yet. Choose a glaze from the shelf and the pot takes it on the next stroke.",

	-- Paint stock reference: a comfortably-stocked glaze fills the gauge. Amber
	-- under 6, terracotta at 0 — the source's METER_FULL and its two thresholds.
	meterFull = 24,
	meterLow = 6,

	-- Brush band: the source's GlazeBrushSize range and default.
	brushMin = 0.015,
	brushMax = 1.0,
	brushDefault = 0.4,

	-- Guide radius range. The live game derives the ceiling from PotConstants
	-- (MAX_RADIUS * POT_SCALE + 0.5); the collection has no wheel to ask, so the
	-- shipped ceiling is stated here and the whole slide scales off it.
	guideMinR = 0.3,
	guideMaxR = 6.5,
	-- ToolAngle is published as -1..1 and rendered as +/-35 degrees of tilt.
	guideTiltDegrees = 35,

	-- Placement dial ranges + steps. STEPS ARE THE PRECISION CONTRACT — see
	-- sliderFormat: step >= 1 prints "%d", anything finer prints "%.2f".
	accScaleMin = 0.25,
	accScaleMax = 3,
	accScaleStep = 0.25,
	accRotationStep = 15,
	accSymmetryMax = 8,

	-- The wall stays at the thinnest setting the wheel allows (the source pins
	-- HollowThickness to 0.1 and dropped its slider); shown, not editable.
	wallThickness = 0.1,

	rarityNames = { "Everyday", "Steady", "Choice", "Rare", "Kiln secret" },
}

-- Glaze tools. The LABEL is what a player reads; the id is the attribute value
-- the game's wheel gates on, so it is never re-spelled.
local GLAZE_TOOLS = {
	{ id = "Paint", label = "Paint", iconKey = "paintbrush", note = "Lays a full ring around the pot." },
	{ id = "Erase", label = "Erase", iconKey = "x", note = "Wipes the ring back to raw clay." },
	{ id = "Fill", label = "Fill", iconKey = "paintbucket", note = "Floods the whole piece at once." },
}

-- Shape tools. The duel build ships only Hands; Groove and Ridge are the full
-- game's, and both keep their sub-option rows here.
local SHAPE_TOOLS = {
	{ id = "Hands", label = "Hands", iconKey = "pointingHand", note = "Drag to pull the wall. Shift hollows, Alt takes height." },
	{ id = "Groove", label = "Groove", iconKey = "pencil", note = "Cuts a horizontal ring at the click height." },
	{ id = "Ridge", label = "Ridge", iconKey = "hammer", note = "Carves vertical grooves. The wheel parks while it is up." },
}

local GROOVE_PROFILES = {
	{ id = "V", note = "linear falloff" },
	{ id = "U", note = "cosine falloff, rounder" },
}

local RIDGE_SYMMETRY = { 1, 2, 4, 8 }

-- The stock shelf: real named glazes with a material signature, then the
-- generated rainbow block (flat colours, no signature — the source's
-- "regular painting" case), then the "My Mixes" tail.
local STOCK_GLAZES: { Glaze } = {
	{ name = "Celadon mist", color = Color3.fromRGB(168, 205, 232), rarity = 3, rough = 0.35, metal = 0.02, textured = true },
	{ name = "Honey ash", color = Color3.fromRGB(240, 196, 120), rarity = 2, rough = 0.48, metal = 0.05, textured = true },
	{ name = "Rose quartz", color = Color3.fromRGB(246, 178, 196), rarity = 3, rough = 0.30, metal = 0.00, textured = true },
	{ name = "Matcha crackle", color = Color3.fromRGB(168, 205, 145), rarity = 2, rough = 0.62, metal = 0.00, textured = true },
	{ name = "Plum tenmoku", color = Color3.fromRGB(150, 110, 150), rarity = 4, rough = 0.22, metal = 0.18, textured = true },
	{ name = "Butter slip", color = Color3.fromRGB(255, 214, 122), rarity = 1, rough = 0.55, metal = 0.00, textured = true },
	{ name = "Sea foam", color = Color3.fromRGB(150, 214, 196), rarity = 2, rough = 0.40, metal = 0.02, textured = true },
	{ name = "Copper bloom", color = Color3.fromRGB(214, 130, 100), rarity = 4, rough = 0.28, metal = 0.42, textured = true },
	{ name = "Moonlit pearl", color = Color3.fromRGB(236, 232, 240), rarity = 5, rough = 0.16, metal = 0.30, textured = true },
}

-- The rainbow block, 12 entries like the source. Saturation is pulled back from
-- the game's 0.85: a shelf of fully-saturated primaries on cream would be the
-- one loud object on the page, and these are flat colours anyway.
local RAINBOW_COUNT = 12
for i = 0, RAINBOW_COUNT - 1 do
	table.insert(STOCK_GLAZES, {
		name = string.format("Rainbow %02d", i + 1),
		color = Color3.fromHSV(i / RAINBOW_COUNT, 0.5, 0.98),
		rarity = 1,
	})
end

-- The "My Mixes" tail: what the server's GlazeState push would carry. Unlocked
-- specials ship a material signature; a plain saved mix does not.
local DEMO_MIXES: { Glaze } = {
	{ name = "Strawberry milk", color = Color3.fromRGB(252, 190, 202), rarity = 3, custom = true },
	{ name = "Sage + ash", color = Color3.fromRGB(186, 206, 172), rarity = 2, custom = true },
	{ name = "Comet glass", color = Color3.fromRGB(198, 178, 232), rarity = 5, rough = 0.12, metal = 0.55, custom = true },
}

local DEMO_ACCESSORIES: { Accessory } = {
	{ folder = "Handle", name = "Loop handle", iconKey = "coil", owned = 4 },
	{ folder = "Handle", name = "Twist handle", iconKey = "trail", owned = 2 },
	{ folder = "Handle", name = "Bead handle", iconKey = "gem", owned = 0 },
	{ folder = "Decorative", name = "Daisy stud", iconKey = "sparkle", owned = 9 },
	{ folder = "Decorative", name = "Heart charm", iconKey = "heart", owned = 3 },
	{ folder = "Decorative", name = "Leaf frill", iconKey = "leaf", owned = 6 },
	{ folder = "Decorative", name = "Star pip", iconKey = "star", owned = 0 },
	{ folder = "Decorative", name = "Crown rim", iconKey = "crown", owned = 1 },
	{ folder = "Decorative", name = "Ribbon bow", iconKey = "gift", owned = 5 },
	{ folder = "Decorative", name = "Berry cluster", iconKey = "strawberry", owned = 0 },
	{ folder = "Decorative", name = "Cookie chip", iconKey = "cookie", owned = 7 },
}

-- ========================================================================
-- LAYOUT CONSTANTS (fixed px at the 1650x1020 baseline; UIScreenBase scales)
-- ========================================================================

local PAGE_W, PAGE_H = 1180, 720
-- The two flanking columns are sized by what they must NOT truncate. The
-- readout has to clear StatRow's fixed right-hand ladder (unit 40 + gap 6 +
-- value 88 + gap 6 + delta 60 + label gap 10 = 210px) and still leave a
-- gutter that fits the longest stat name at body size; the shelf has to hold
-- three swatch columns inside its padding and scrollbar. Their SUM is held at
-- 700 so the centre bench stays exactly 424 whichever way the split moves.
local COL_LEFT_W = 384
local COL_RIGHT_W = 316
local COL_GAP = 14
local TAB_BAR_H = 52
local BODY_Y = 60
local PANEL_PAD = 14
-- The readout scroller takes a slimmer inset than the panels: its rows are
-- deliberately shadow-free (see the StatRow note), so padding there buys
-- nothing but lost label width.
local READOUT_PAD = 10
local ROW_GAP = 8

-- Fat finger targets: the source went up to 72px specifically so a swatch is
-- hittable mid-paint. The shelf width takes three of these per row; the grid
-- layout works that out, so no column count is hardcoded anywhere.
local SWATCH = 84
local SWATCH_GAP = 6
local ACC_ROW_H = 82
local BTN_H = 44
local SLIDER_H = 52
local METER_H = 36
local HINT_H = 38
local SURFACE_H = 176

local TABS = {
	{ id = "glaze", label = "Glaze" },
	{ id = "carve", label = "Carve" },
	{ id = "addons", label = "Add-ons" },
}

-- ========================================================================
-- LOCAL HELPERS
-- ========================================================================

-- THE PRECISION RULE, lifted whole from the source: a step of 1 or coarser is
-- an integer dial, anything finer prints two decimals. Every slider, bubble and
-- stat readout on this screen formats through this.
local function sliderFormat(step: number?): string
	if step and step >= 1 then
		return "%d"
	end
	return "%.2f"
end

-- PACK LAW 3, applied to a fill that is not always pale. TextSecondary is
-- corrected for 4.5:1 on CREAM and holds on the blush surfaces, but on the
-- pack's saturated action fills it collapses: measured against Studio.Next
-- (matcha deep) it is 1.71:1 and against Studio.Back (terracotta) 1.67:1.
-- Anything darker than the pale surfaces therefore takes the ink, which is
-- what "body on any pastel uses TextPrimary" means in practice.
local PALE_LUMA = 0.9
local function labelInk(theme: Types.UITheme, fill: Color3, muted: boolean): Color3
	if not muted then
		return theme.Colors.TextPrimary
	end
	local luma = 0.2126 * fill.R + 0.7152 * fill.G + 0.0722 * fill.B
	if luma >= PALE_LUMA then
		return theme.Colors.TextSecondary
	end
	return theme.Colors.TextPrimary
end

local function rarityColor(theme: Types.UITheme, rarity: number): Color3
	local ramp = ((theme :: any).DialectTokens or {}).rarity
	if typeof(ramp) == "table" and #ramp > 0 then
		return ramp[math.clamp(math.floor(rarity), 1, #ramp)]
	end
	-- No ramp on this pack: the selection colour is the only honest fallback.
	return theme.Semantic.Selection
end

local function rarityName(rarity: number): string
	return STUDIO.rarityNames[math.clamp(math.floor(rarity), 1, #STUDIO.rarityNames)] or "Everyday"
end

-- Fill an icon slot from the archive, falling back to a visible glyph rather
-- than a blank square. Every image created here is registered with
-- IconVisibility so the global icon toggle owns it.
local function applyIcon(image: ImageLabel, glyph: TextLabel, key: string?)
	local assetId = if key then IconArchive.Id(key) else nil
	if assetId and assetId ~= "" then
		image.Image = assetId
		image.Visible = true
		glyph.Visible = false
	else
		image.Visible = false
		glyph.Visible = true
		glyph.Text = if key then IconArchive.Glyph(key) else "\u{2022}"
	end
end

-- An icon slot plus its glyph understudy. The glyph is PAINTED explicitly:
-- UIStyler.TextLabel is born pure-white text, which pack law 1 forbids outright.
local function newIcon(parent: Instance, sizePx: number, color: Color3): (ImageLabel, TextLabel)
	local image = Instance.new("ImageLabel")
	image.Name = "Icon"
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Fit
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.5)
	image.Size = UDim2.fromOffset(sizePx, sizePx)
	image.Visible = false
	image.Parent = parent
	IconVisibility.Register(image)

	local glyph = UIStyler.TextLabel("Glyph")
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.5)
	glyph.Size = UDim2.fromOffset(sizePx, sizePx)
	glyph.TextSize = math.floor(sizePx * 0.7)
	glyph.TextColor3 = color
	glyph.Visible = false
	glyph.Parent = parent
	IconVisibility.Register(glyph)
	return image, glyph
end

-- ========================================================================
-- THE SCREEN
-- ========================================================================

local GlazeStudioScreen = setmetatable({}, { __index = UIScreenBase })
GlazeStudioScreen.__index = GlazeStudioScreen

function GlazeStudioScreen.new()
	local self = UIScreenBase.new("GlazeStudioScreen", 8)
	-- The workbench family: matte surfaces, data density, no arcade bevel.
	self.Family = "Studio" :: Types.UIFamily

	self._tab = "glaze"

	-- Palette. _stockCount is the immutable boundary: everything past it is the
	-- "My Mixes" tail, replaced whole on every push.
	self._glazes = table.clone(STOCK_GLAZES) :: { Glaze }
	self._stockCount = #STOCK_GLAZES
	for _, mix in DEMO_MIXES do
		table.insert(self._glazes, mix)
	end
	self._selectedGlaze = nil :: number?

	-- Glaze phase state (mirrors the source's published attributes).
	self._glazeTool = "Paint"
	self._glazeLineDir = "H" -- Paint/Erase stroke direction: always horizontal rings
	self._brush = STUDIO.brushDefault
	self._paintStock = 18
	self._coverage = 34

	-- Shape phase state.
	self._shapeTool = "Hands"
	self._grooveProfile = "V"
	self._ridgeSymmetry = 1
	self._spinning = true
	self._preRidgeSpin = true
	self._heightLive = false

	-- Guide state. guideSide is DERIVED from the marker drag, never a control.
	self._guideOn = false
	self._guideR = 1
	self._guideAngle = 0
	self._guideSide = 1
	self._guideSyncing = false

	-- Accessories.
	self._accessories = DEMO_ACCESSORIES :: { Accessory }
	self._accStockKnown = true -- false = pre-push: badges hide, nothing greys
	self._accPickedKey = nil :: string?
	self._pieceSelected = false
	self._piecesPlaced = 0
	self._accSymmetry = 1
	self._accRotation = 0
	self._accScale = 1
	-- The committed transform of the selected piece; the dials edit a PREVIEW
	-- against it and "Done" is what commits (the source's AccessoryConfirm).
	self._accScaleCommitted = 1
	self._accRotationCommitted = 0
	-- How many copies the live selection was placed with (Remove undoes THAT).
	self._lastPlacedCount = 0

	-- Station conditions the source warns on.
	self._storageFull = false
	self._lowClay = false

	-- Which shell this screen is wearing; set for real in _BuildContent, seeded
	-- here so a read before the first build can never be a nil compare.
	self._gp = false
	self._breathe = nil :: (() -> ())?

	-- Owned resources.
	self._shadows = {} :: { any }
	self._conns = {} :: { RBXScriptConnection }
	self._tickers = {} :: { () -> () }
	self._swatchPool = {} :: { any }
	self._swatches = {} :: { any }
	self._accRowPool = {} :: { any }
	self._accRows = {} :: { any }
	self._stats = {} :: { [string]: any }
	self._sliders = {} :: { [string]: any }
	self._meters = {} :: { [string]: any }
	self._toolButtons = {} :: { [string]: any }
	self._shapeButtons = {} :: { [string]: any }
	self._grooveButtons = {} :: { [string]: any }
	self._ridgeButtons = {} :: { [number]: any }
	self._drag = nil :: any

	return setmetatable(self, GlazeStudioScreen)
end

-- ========================================================================
-- SMALL BUILDERS
-- ========================================================================

-- A petal-cornered plate. Returns the frame AND its stroke, because the glaze
-- surface retints its own rim to the selected glaze's rarity.
function GlazeStudioScreen:_Panel(parent: Instance, name: string, index: number): (Frame, UIStroke)
	local theme = self:GetTheme()
	local fill = theme.Colors.SurfaceRaised
	local panel = UIStyler.Frame(name)
	panel.BackgroundColor3 = fill
	panel.BackgroundTransparency = 0
	panel.Size = UDim2.fromScale(1, 1)
	panel.Parent = parent
	GPLayoutKit.Petal(theme, panel, index)
	local stroke = GPLayoutKit.SoftStroke(theme, panel, fill)
	GPLayoutKit.Shadow(theme, panel, "sm", self._shadows, fill)
	return panel, stroke
end

-- A pill/petal button whose FILL lives on a child shape: a solid GuiButton trips
-- the style enforcer's black 2px backstop, which pack law 1 forbids on sight.
function GlazeStudioScreen:_Button(parent: Instance, opts: {
	text: string,
	iconKey: string?,
	fill: Color3?,
	widthPx: number?,
	heightPx: number?,
	index: number?,
	layoutOrder: number?,
	onClick: (() -> ())?,
}): any
	local theme = self:GetTheme()
	local fill = opts.fill or theme.Colors.Surface

	local button = Instance.new("TextButton")
	button.Name = "Button_" .. opts.text
	button.BackgroundTransparency = 1
	button.Text = ""
	button.AutoButtonColor = false
	button.Size = UDim2.new(
		if opts.widthPx then 0 else 1,
		opts.widthPx or 0,
		0,
		opts.heightPx or BTN_H
	)
	if opts.layoutOrder then
		button.LayoutOrder = opts.layoutOrder
	end
	button.Parent = parent

	local shape = UIStyler.Frame("Shape")
	shape.BackgroundColor3 = fill
	shape.BackgroundTransparency = 0
	shape.Size = UDim2.fromScale(1, 1)
	shape.Parent = button
	GPLayoutKit.Petal(theme, shape, opts.index or 0)
	local stroke = GPLayoutKit.SoftStroke(theme, shape, fill)

	local textX = 12
	local image: ImageLabel? = nil
	local glyph: TextLabel? = nil
	if opts.iconKey then
		local host = UIStyler.Frame("IconHost")
		host.BackgroundTransparency = 1
		host.AnchorPoint = Vector2.new(0, 0.5)
		host.Position = UDim2.new(0, 10, 0.5, 0)
		host.Size = UDim2.fromOffset(24, 24)
		host.ZIndex = 2
		host.Parent = shape
		local img, gly = newIcon(host, 22, theme.Colors.TextPrimary)
		applyIcon(img, gly, opts.iconKey)
		image, glyph = img, gly
		textX = 40
	end

	local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Button, theme.Colors.TextPrimary, "Label")
	label.Text = opts.text
	label.TextXAlignment = if opts.iconKey then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Position = UDim2.fromOffset(textX, 0)
	label.Size = UDim2.new(1, -(textX + 10), 1, 0)
	label.ZIndex = 2
	label.Parent = shape

	if opts.onClick then
		button.Activated:Connect(opts.onClick)
	end
	UIChrome.Animate(theme, button, shape)

	local entry = {
		root = button,
		shape = shape,
		stroke = stroke,
		label = label,
		image = image,
		glyph = glyph,
		baseFill = fill,
	}
	-- Selection reads as a solid deepened ring plus the pack's rose fill; the
	-- hover spring tweens the FILL, so selection must never ride on fill alone.
	function entry.SetSelected(on: boolean)
		local nextFill = if on then theme.Colors.Primary else entry.baseFill
		shape.BackgroundColor3 = nextFill
		stroke.Color = GPLayoutKit.Deepen(theme, nextFill, 1)
		stroke.Transparency = if on then 0 else 0.35
		stroke.Thickness = if on then 3 else 2
		-- Body copy on rose is TextPrimary (5.15:1). TextOnPrimary measures
		-- 2.14:1 there and is illegal for anything at this size. The idle
		-- state only softens to TextSecondary when the fill is pale enough to
		-- carry it (see labelInk) — the terracotta "back" and matcha "next"
		-- buttons keep the ink.
		label.TextColor3 = labelInk(theme, nextFill, not on)
	end
	function entry.SetEnabled(on: boolean)
		button.Active = on
		button.Visible = on
	end
	entry.SetSelected(false)
	return entry
end

-- A labelled dial. Same anatomy as the source's makeSlider — recessed rail,
-- accent fill, tick notches at the snap points, a knob that swells under the
-- thumb and a value bubble — restated in pastel with the pack's pill radius.
-- centerOrigin turns the fill into a centre-out dial for the Angle tilt.
function GlazeStudioScreen:_Slider(parent: Instance, opts: {
	label: string,
	min: number,
	max: number,
	default: number,
	step: number?,
	unit: string?,
	centerOrigin: boolean?,
	layoutOrder: number?,
	accent: Color3?,
	onChange: (number) -> (),
}): any
	local theme = self:GetTheme()
	local format = sliderFormat(opts.step)
	local accent = opts.accent or theme.Colors.Primary

	local holder = UIStyler.Frame("Slider_" .. opts.label)
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, SLIDER_H)
	if opts.layoutOrder then
		holder.LayoutOrder = opts.layoutOrder
	end
	holder.Parent = parent

	local caption = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Caption")
	caption.Text = opts.label
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.Size = UDim2.new(1, -110, 0, 18)
	caption.Parent = holder

	local readout = GPLayoutKit.NumberText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "Readout")
	readout.AnchorPoint = Vector2.new(1, 0)
	readout.Position = UDim2.new(1, 0, 0, 0)
	readout.Size = UDim2.fromOffset(108, 18)
	readout.Parent = holder

	local track = Instance.new("TextButton")
	track.Name = "Track"
	track.BackgroundTransparency = 1 -- the hit area; the rail child carries the fill
	track.Text = ""
	track.AutoButtonColor = false
	track.Position = UDim2.fromOffset(0, 22)
	track.Size = UDim2.new(1, 0, 0, 30)
	track.Parent = holder

	local rail = UIStyler.Frame("Rail")
	rail.BackgroundColor3 = theme.Arcade.RulerTrack
	rail.BackgroundTransparency = 0
	rail.AnchorPoint = Vector2.new(0.5, 0.5)
	rail.Position = UDim2.fromScale(0.5, 0.5)
	rail.Size = UDim2.new(1, 0, 0, 12)
	rail.Parent = track
	UIStyler.Corner(theme.Radii.Pill).Parent = rail

	local fill = UIStyler.Frame("Fill")
	fill.BackgroundColor3 = accent
	fill.BackgroundTransparency = 0
	fill.AnchorPoint = Vector2.new(0, 0.5)
	fill.Position = UDim2.new(0, 0, 0.5, 0)
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.ZIndex = 2
	fill.Parent = rail
	UIStyler.Corner(theme.Radii.Pill).Parent = fill

	-- Tick notches, one per interior snap point. Skipped when the step would
	-- spam the rail (the source's 2..24 window).
	local step = opts.step
	if step and step > 0 then
		local count = math.floor((opts.max - opts.min) / step + 0.5)
		if count >= 2 and count <= 24 then
			for t = 1, count - 1 do
				local tick = UIStyler.Frame("Tick")
				tick.BackgroundColor3 = GPLayoutKit.Deepen(theme, theme.Arcade.RulerTrack, 1)
				tick.BackgroundTransparency = 0
				tick.AnchorPoint = Vector2.new(0.5, 0.5)
				tick.Position = UDim2.new(t / count, 0, 0.5, 0)
				tick.Size = UDim2.fromOffset(2, 6)
				tick.ZIndex = 3
				tick.Parent = rail
				UIStyler.Corner(theme.Radii.Pill).Parent = tick
			end
		end
	end

	local centerF = if opts.centerOrigin and opts.max > opts.min
		then math.clamp((0 - opts.min) / (opts.max - opts.min), 0, 1)
		else 0
	if opts.centerOrigin then
		local notch = UIStyler.Frame("CentreNotch")
		notch.BackgroundColor3 = theme.Studio.Tan
		notch.BackgroundTransparency = 0
		notch.AnchorPoint = Vector2.new(0.5, 0.5)
		notch.Position = UDim2.new(centerF, 0, 0.5, 0)
		notch.Size = UDim2.fromOffset(3, 14)
		notch.ZIndex = 3
		notch.Parent = rail
		UIStyler.Corner(theme.Radii.Pill).Parent = notch
	end

	local knobFill = theme.Colors.Background
	local knob = UIStyler.Frame("Knob")
	knob.BackgroundColor3 = knobFill
	knob.BackgroundTransparency = 0
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.new(0, 0, 0.5, 0)
	knob.Size = UDim2.fromOffset(24, 24)
	knob.ZIndex = 4
	knob.Parent = rail
	UIStyler.Corner(theme.Radii.Pill).Parent = knob
	GPLayoutKit.SoftStroke(theme, knob, knobFill)

	local knobScale = Instance.new("UIScale")
	knobScale.Parent = knob

	local bubbleFill = theme.Colors.SurfaceRaised
	local bubble = UIStyler.Frame("Bubble")
	bubble.BackgroundColor3 = bubbleFill
	bubble.BackgroundTransparency = 0
	bubble.AnchorPoint = Vector2.new(0.5, 1)
	bubble.Position = UDim2.new(0.5, 0, 0, -6)
	bubble.Size = UDim2.fromOffset(64, 22)
	bubble.Visible = false
	bubble.ZIndex = 5
	bubble.Parent = knob
	UIStyler.Corner(theme.Radii.Pill).Parent = bubble
	GPLayoutKit.SoftStroke(theme, bubble, bubbleFill)

	local bubbleText = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "Value")
	bubbleText.Size = UDim2.fromScale(1, 1)
	bubbleText.ZIndex = 6
	bubbleText.Parent = bubble

	local value = opts.default
	local function apply(fraction: number)
		fraction = math.clamp(fraction, 0, 1)
		local v = opts.min + (opts.max - opts.min) * fraction
		if step and step > 0 then
			v = math.clamp(opts.min + math.round((v - opts.min) / step) * step, opts.min, opts.max)
			fraction = if opts.max > opts.min then (v - opts.min) / (opts.max - opts.min) else 0
		end
		value = v
		if opts.centerOrigin then
			fill.Position = UDim2.new(math.min(centerF, fraction), 0, 0.5, 0)
			fill.Size = UDim2.new(math.abs(fraction - centerF), 0, 1, 0)
		else
			fill.Size = UDim2.new(fraction, 0, 1, 0)
		end
		knob.Position = UDim2.new(fraction, 0, 0.5, 0)
		local printed = string.format(format, v)
		readout.Text = if opts.unit then printed .. " " .. opts.unit else printed
		bubbleText.Text = printed
		opts.onChange(v)
	end

	local function setHeld(held: boolean)
		knobScale.Scale = if held then 1.15 else 1
		bubble.Visible = held
	end

	track.MouseButton1Down:Connect(function()
		setHeld(true)
		self._drag = {
			rail = rail,
			apply = apply,
			release = function()
				setHeld(false)
			end,
		}
		self:_DragToMouse()
	end)

	apply(if opts.max > opts.min then (opts.default - opts.min) / (opts.max - opts.min) else 0)

	local entry = { root = holder, readout = readout }
	function entry.Set(v: number)
		apply(if opts.max > opts.min then (v - opts.min) / (opts.max - opts.min) else 0)
	end
	function entry.Get(): number
		return value
	end
	return entry
end

-- A rounded pastel gauge: label, numeric readout, track and a hue-tinted fill
-- that can take the glaze sheen (the paint meter does; the flatter coverage
-- gauge does not, so a data column never shimmers twice).
function GlazeStudioScreen:_Meter(parent: Instance, opts: {
	label: string,
	layoutOrder: number?,
	glossy: boolean?,
}): any
	local theme = self:GetTheme()

	local holder = UIStyler.Frame("Meter_" .. opts.label)
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, METER_H)
	if opts.layoutOrder then
		holder.LayoutOrder = opts.layoutOrder
	end
	holder.Parent = parent

	local caption = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Caption")
	caption.Text = opts.label
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.Size = UDim2.new(1, -120, 0, 18)
	caption.Parent = holder

	local readout = GPLayoutKit.NumberText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "Readout")
	readout.AnchorPoint = Vector2.new(1, 0)
	readout.Position = UDim2.new(1, 0, 0, 0)
	readout.Size = UDim2.fromOffset(118, 18)
	readout.Parent = holder

	local track = UIStyler.Frame("Track")
	track.BackgroundColor3 = theme.Arcade.RulerTrack
	track.BackgroundTransparency = 0
	track.Position = UDim2.fromOffset(0, 24)
	track.Size = UDim2.new(1, 0, 0, 12)
	track.Parent = holder
	UIStyler.Corner(theme.Radii.Pill).Parent = track

	local fill = UIStyler.Frame("Fill")
	fill.BackgroundColor3 = theme.Colors.Secondary
	fill.BackgroundTransparency = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = 2
	fill.Parent = track
	UIStyler.Corner(theme.Radii.Pill).Parent = fill
	if opts.glossy and self._gp then
		-- Leaf element: the sheen wash has no siblings to sit over.
		GPLayoutKit.GlazeSheen(theme, fill)
	end

	local entry = { root = holder, fill = fill, readout = readout }
	function entry.Set(ratio: number, text: string, tone: Color3)
		fill.Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
		fill.BackgroundColor3 = tone
		readout.Text = text
	end
	return entry
end

function GlazeStudioScreen:_Section(parent: Instance, text: string, layoutOrder: number): TextLabel
	local label = GPLayoutKit.SectionLabel(self:GetTheme(), parent, text)
	label.LayoutOrder = layoutOrder
	return label
end

-- A soft warning strip. The pack has a warm amber warn pair; a red-on-cream
-- alert bar would be the only shouting object on the page.
function GlazeStudioScreen:_Hint(parent: Instance, text: string, layoutOrder: number, tone: Color3?): any
	local theme = self:GetTheme()
	local fill = theme.Studio.WarnBg

	local strip = UIStyler.Frame("Hint")
	strip.BackgroundColor3 = fill
	strip.BackgroundTransparency = 0
	strip.Size = UDim2.new(1, 0, 0, HINT_H)
	strip.LayoutOrder = layoutOrder
	strip.Visible = false
	strip.Parent = parent
	GPLayoutKit.Petal(theme, strip, layoutOrder)
	GPLayoutKit.SoftStroke(theme, strip, fill)

	local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, tone or theme.Studio.WarnText, "Text")
	label.Text = text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.Position = UDim2.fromOffset(10, 0)
	label.Size = UDim2.new(1, -20, 1, 0)
	label.Parent = strip

	local entry = { root = strip, label = label }
	function entry.SetVisible(on: boolean)
		strip.Visible = on
	end
	return entry
end

-- ========================================================================
-- DRAG — one manager for every rail on the page (sliders and the guide slide),
-- so the screen owns exactly two UserInputService connections instead of two
-- per control.
-- ========================================================================

-- End the live drag and run its release dressing exactly once. Every path out
-- of a drag goes through here (input ended, the rail went away, the screen
-- hid), so a knob can never be left swollen with its bubble showing.
function GlazeStudioScreen:_EndDrag()
	local drag = self._drag
	self._drag = nil
	if drag and drag.release then
		drag.release()
	end
end

function GlazeStudioScreen:_DragToMouse()
	local drag = self._drag
	if not drag then
		return
	end
	local rail = drag.rail :: GuiObject
	if not rail.Parent then
		self:_EndDrag()
		return
	end
	local mouseX = UserInputService:GetMouseLocation().X
	drag.apply((mouseX - rail.AbsolutePosition.X) / math.max(1, rail.AbsoluteSize.X))
end

function GlazeStudioScreen:_BindDrag()
	table.insert(
		self._conns,
		UserInputService.InputChanged:Connect(function(input: InputObject)
			if not self._drag then
				return
			end
			if
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			then
				self:_DragToMouse()
			end
		end)
	)
	table.insert(
		self._conns,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if not self._drag then
				return
			end
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				self:_EndDrag()
			end
		end)
	)
end

-- ========================================================================
-- BUILD
-- ========================================================================

function GlazeStudioScreen:_BuildContent()
	local theme = self:GetTheme()
	self._gp = theme.LayoutKit == "GP"

	local content: Frame
	if self._gp then
		local page = GPLayoutKit.Page(theme, self.Root, {
			titleText = STUDIO.titleText,
			subtitleText = STUDIO.subtitleText,
			sizePx = Vector2.new(PAGE_W, PAGE_H),
			onClose = function()
				self.ScreenController:HideScreen("glazeStudio")
			end,
		})
		self._shadows = page.shadows
		self._page = page
		content = page.content

		-- The header's counter slot carries the paint barrel, so the number a
		-- player is about to spend is legible from the top of the page.
		local pill = GPLayoutKit.PricePill(theme, page.topRight, self._shadows)
		pill.root.Size = UDim2.fromOffset(168, 38)
		local barrelId = IconArchive.Id("bucket")
		if barrelId and barrelId ~= "" then
			pill.icon.Image = barrelId
		else
			-- No art resolved: the amount takes the whole pill rather than
			-- reserving a gap for a slot that will never fill.
			pill.icon.Visible = false
			pill.amount.Position = UDim2.fromOffset(theme.Spacing.S, 0)
			pill.amount.Size = UDim2.new(1, -theme.Spacing.S * 2, 1, 0)
		end
		self._stockPill = pill
	else
		local modal = UIChrome.ModalCard(theme, self.Root, {
			title = STUDIO.titleText,
			sizePx = Vector2.new(PAGE_W, PAGE_H),
			onClose = function()
				self.ScreenController:HideScreen("glazeStudio")
			end,
			paperContent = true,
		})
		self._shadows = {}
		self._modal = modal
		content = modal.content
	end

	self:_BindDrag()
	self:_BuildBody(content)
	self:_SelectTab(self._tab)
	self:_RefreshAll()
end

function GlazeStudioScreen:_BuildBody(content: Frame)
	local theme = self:GetTheme()

	-- Tab bar. Selection reads forward (rose fill + butter underline); the kit
	-- owns that language so every GP page agrees.
	local tabHost = UIStyler.Frame("TabHost")
	tabHost.BackgroundTransparency = 1
	tabHost.Size = UDim2.new(1, 0, 0, TAB_BAR_H)
	tabHost.Parent = content

	local tabs = GPLayoutKit.Tabs(theme, tabHost, { widthPx = 150 }, self._shadows)
	for _, tab in TABS do
		tabs.Add(tab.label, tab.id, function()
			self:_SelectTab(tab.id)
		end)
	end
	self._tabs = tabs

	local body = UIStyler.Frame("Body")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(0, BODY_Y)
	body.Size = UDim2.new(1, 0, 1, -BODY_Y)
	body.Parent = content

	local left = UIStyler.Frame("LeftColumn")
	left.BackgroundTransparency = 1
	left.Size = UDim2.new(0, COL_LEFT_W, 1, 0)
	left.Parent = body

	local centre = UIStyler.Frame("CentreColumn")
	centre.BackgroundTransparency = 1
	centre.Position = UDim2.fromOffset(COL_LEFT_W + COL_GAP, 0)
	centre.Size = UDim2.new(1, -(COL_LEFT_W + COL_RIGHT_W + COL_GAP * 2), 1, 0)
	centre.Parent = body

	local right = UIStyler.Frame("RightColumn")
	right.BackgroundTransparency = 1
	right.AnchorPoint = Vector2.new(1, 0)
	right.Position = UDim2.fromScale(1, 0)
	right.Size = UDim2.new(0, COL_RIGHT_W, 1, 0)
	right.Parent = body

	self:_BuildReadout(left)

	self._benches = {
		glaze = self:_BuildGlazeBench(centre),
		carve = self:_BuildCarveBench(centre),
		addons = self:_BuildAddonBench(centre),
	}
	self._sides = {
		glaze = self:_BuildGlazeShelf(right),
		carve = self:_BuildGuidePanel(right),
		addons = self:_BuildAddonList(right),
	}
end

-- ------------------------------------------------------------------------
-- LEFT: the readout column — eleven live stats plus the warning strips.
-- ------------------------------------------------------------------------

function GlazeStudioScreen:_BuildReadout(parent: Instance)
	local theme = self:GetTheme()
	local panel = self:_Panel(parent, "Readout", 0)

	-- Eleven stats plus three conditional warning strips overrun the column the
	-- moment every warning is live, so the readout scrolls. Clipped, and padded
	-- so a strip's own soft shadow is not sliced at the edges.
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Readings"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.ClipsDescendants = true
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = theme.Colors.Primary
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = panel
	UIStyler.Padding(READOUT_PAD).Parent = scroll
	UIStyler.ListLayout({
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 4),
	}).Parent = scroll
	self._readoutScroll = scroll
	local host: Instance = scroll

	self:_Section(host, "On the wheel", 0)

	-- Deliberately shadow-free rows (the kit's own note): a column of soft
	-- shadows would turn a data table into a sticker sheet.
	-- Labels are kept inside the ~120px gutter the ladder leaves at COL_LEFT_W;
	-- the UNIT column carries the rest of the sentence ("Placed … on pot"), so
	-- a short name is a complete reading, never a truncated one.
	local rows = {
		{ key = "coverage", label = "Glaze on pot", unit = "%", max = 100, precision = 1 },
		{ key = "stock", label = "Glaze stock", unit = "units", max = STUDIO.meterFull, precision = 0 },
		{ key = "brush", label = "Brush band", unit = "wide", max = STUDIO.brushMax, precision = 2 },
		{ key = "wall", label = "Wall", unit = "studs", max = 1, precision = 2 },
		{ key = "guideR", label = "Guide reach", unit = "studs", max = STUDIO.guideMaxR, precision = 2 },
		-- The tilt's SIDE rides the label, not the unit: the unit column is a
		-- fixed 40px and "deg right" would be clipped inside it.
		{ key = "guideTilt", label = "Guide tilt", unit = "deg", max = STUDIO.guideTiltDegrees, precision = 1 },
		{ key = "symmetry", label = "Ridge count", unit = "ridges", max = 8, precision = 0 },
		{ key = "pieces", label = "Placed", unit = "on pot", max = 12, precision = 0 },
		{ key = "accScale", label = "Add-on scale", unit = "x", max = STUDIO.accScaleMax, precision = 2 },
		{ key = "accRot", label = "Add-on spin", unit = "deg", max = 360, precision = 0 },
		{ key = "accSym", label = "Copies", unit = "around", max = STUDIO.accSymmetryMax, precision = 0 },
	}
	for index, row in rows do
		self._stats[row.key] = GPLayoutKit.StatRow(theme, host, {
			label = row.label,
			unit = row.unit,
			maxValue = row.max,
			precision = row.precision,
			accent = if index % 2 == 0 then theme.Colors.Secondary else theme.Colors.Primary,
			layoutOrder = index,
		})
	end

	-- The section header hides with its strips: a heading over nothing reads as
	-- a broken panel, and UIListLayout skips invisible children for free.
	self._hintSection = self:_Section(host, "Worth knowing", 20)
	self._hintSection.Visible = false
	self._hints = {
		glaze = self:_Hint(host, STUDIO.outOfGlaze, 21),
		storage = self:_Hint(host, STUDIO.storageFull, 22),
		clay = self:_Hint(host, STUDIO.lowClay, 23),
	}
end

-- ------------------------------------------------------------------------
-- CENTRE / GLAZE: the surface preview, the tool row, the brush dial and the
-- paint meter.
-- ------------------------------------------------------------------------

function GlazeStudioScreen:_BuildGlazeBench(parent: Instance): Frame
	local theme = self:GetTheme()
	local bench = self:_Panel(parent, "GlazeBench", 1)
	UIStyler.Padding(PANEL_PAD).Parent = bench
	UIStyler.ListLayout({
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, ROW_GAP),
	}).Parent = bench

	self:_Section(bench, "Glaze surface", 0)

	-- The surface plate: the chosen glaze as a glossy chip, its name, rarity and
	-- material signature, and the band the current brush would lay.
	local surfaceFill = theme.Colors.Surface
	local surface = UIStyler.Frame("Surface")
	surface.BackgroundColor3 = surfaceFill
	surface.BackgroundTransparency = 0
	surface.Size = UDim2.new(1, 0, 0, SURFACE_H)
	surface.LayoutOrder = 1
	surface.Parent = bench
	GPLayoutKit.Petal(theme, surface, 2)
	self._surfaceStroke = GPLayoutKit.SoftStroke(theme, surface, surfaceFill)

	local chipFill = theme.Colors.SurfaceRaised
	local chip = UIStyler.Frame("GlazeChip")
	chip.BackgroundColor3 = chipFill
	chip.BackgroundTransparency = 0
	chip.Position = UDim2.fromOffset(14, 14)
	chip.Size = UDim2.fromOffset(100, 100)
	chip.Parent = surface
	GPLayoutKit.Petal(theme, chip, 3)
	self._chipStroke = GPLayoutKit.SoftStroke(theme, chip, chipFill)
	if self._gp then
		-- The signature move: a glaze chip is CERAMIC, so it takes the sheen.
		GPLayoutKit.GlazeSheen(theme, chip)
	end
	self._glazeChip = chip

	local name = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "GlazeName")
	name.Text = "No glaze picked"
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(148, 16)
	name.Size = UDim2.new(1, -162, 0, 26)
	name.Parent = surface
	self._glazeName = name

	local rarity = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "GlazeRarity")
	rarity.Text = STUDIO.emptyShelf
	rarity.TextXAlignment = Enum.TextXAlignment.Left
	rarity.TextWrapped = true
	rarity.Position = UDim2.fromOffset(148, 42)
	rarity.Size = UDim2.new(1, -162, 0, 30)
	rarity.Parent = surface
	self._glazeRarity = rarity

	-- Material signature. The source publishes GlazeRough / GlazeMetal and never
	-- rendered them; a finishing bench that hides its own material data is the
	-- condescension this pack forbids.
	local sig = UIStyler.Frame("Signature")
	sig.BackgroundTransparency = 1
	sig.Position = UDim2.fromOffset(148, 74)
	sig.Size = UDim2.new(1, -162, 0, 58)
	sig.Parent = surface
	UIStyler.ListLayout({
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 2),
	}).Parent = sig
	self._stats.rough = GPLayoutKit.StatRow(theme, sig, {
		label = "Roughness",
		unit = "",
		maxValue = 1,
		precision = 2,
		heightPx = 28,
		accent = theme.Colors.Secondary,
		layoutOrder = 1,
	})
	self._stats.metal = GPLayoutKit.StatRow(theme, sig, {
		label = "Metalness",
		unit = "",
		maxValue = 1,
		precision = 2,
		heightPx = 28,
		accent = theme.Arcade.Gold,
		layoutOrder = 2,
	})

	-- The band the brush lays: horizontal, because GlazeLineDir is always "H".
	-- Fill ignores it, and the caption says so.
	local bandTrack = UIStyler.Frame("BandTrack")
	bandTrack.BackgroundColor3 = theme.Arcade.RulerTrack
	bandTrack.BackgroundTransparency = 0
	bandTrack.AnchorPoint = Vector2.new(0, 1)
	bandTrack.Position = UDim2.new(0, 14, 1, -12)
	bandTrack.Size = UDim2.new(0, 100, 0, 36)
	bandTrack.ClipsDescendants = true
	bandTrack.Parent = surface
	GPLayoutKit.Petal(theme, bandTrack, 4)

	local band = UIStyler.Frame("Band")
	band.BackgroundColor3 = theme.Colors.Disabled
	band.BackgroundTransparency = 0
	band.AnchorPoint = Vector2.new(0.5, 0.5)
	band.Position = UDim2.fromScale(0.5, 0.5)
	band.Size = UDim2.new(1, 0, 0, 8)
	band.Parent = bandTrack
	UIStyler.Corner(theme.Radii.Pill).Parent = band
	if self._gp then
		GPLayoutKit.GlazeSheen(theme, band)
	end
	self._band = band

	local toolNote = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "ToolNote")
	toolNote.Text = GLAZE_TOOLS[1].note
	toolNote.TextXAlignment = Enum.TextXAlignment.Left
	toolNote.TextWrapped = true
	toolNote.AnchorPoint = Vector2.new(0, 1)
	toolNote.Position = UDim2.new(0, 148, 1, -8)
	toolNote.Size = UDim2.new(1, -162, 0, 32)
	toolNote.Parent = surface
	self._toolNote = toolNote

	-- Tool row: Paint / Erase / Fill.
	self:_Section(bench, "Brush", 2)
	local toolRow = UIStyler.Frame("ToolRow")
	toolRow.BackgroundTransparency = 1
	toolRow.Size = UDim2.new(1, 0, 0, BTN_H)
	toolRow.LayoutOrder = 3
	toolRow.Parent = bench
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
	}).Parent = toolRow

	for index, tool in GLAZE_TOOLS do
		self._toolButtons[tool.id] = self:_Button(toolRow, {
			text = tool.label,
			iconKey = tool.iconKey,
			widthPx = 124,
			index = index,
			layoutOrder = index,
			onClick = function()
				self._glazeTool = tool.id
				self:_RefreshTools()
			end,
		})
	end

	self._sliders.brush = self:_Slider(bench, {
		label = "Brush width",
		min = STUDIO.brushMin,
		max = STUDIO.brushMax,
		default = self._brush,
		unit = "wide",
		layoutOrder = 4,
		onChange = function(v)
			self._brush = v
			self:_RefreshBrush()
		end,
	})

	self._meters.paint = self:_Meter(bench, { label = "Glaze in the barrel", layoutOrder = 5, glossy = true })
	self._meters.coverage = self:_Meter(bench, { label = "Glaze on the pot", layoutOrder = 6 })

	local actions = UIStyler.Frame("GlazeActions")
	actions.BackgroundTransparency = 1
	actions.Size = UDim2.new(1, 0, 0, BTN_H)
	actions.LayoutOrder = 7
	actions.Parent = bench
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
	}).Parent = actions

	self:_Button(actions, {
		text = "Back to shaping",
		fill = theme.Studio.Back,
		widthPx = 180,
		index = 0,
		layoutOrder = 1,
		onClick = function()
			self:_SelectTab("carve")
		end,
	})
	self:_Button(actions, {
		text = "Reset paint",
		widthPx = 150,
		index = 1,
		layoutOrder = 2,
		onClick = function()
			-- The source's Reset Paint bumps ResetGlaze ONLY — it strips the
			-- paint off the pot and deliberately KEEPS the chosen glaze, so
			-- the next stroke can go straight back down. (The selection is
			-- cleared elsewhere: a bare reset, a kiln crack, a duel reset.)
			-- Clearing it here would make a repaint a two-step chore.
			self._coverage = 0
			self:_RefreshGlaze()
		end,
	})

	return bench
end

-- ------------------------------------------------------------------------
-- CENTRE / CARVE: the shape tools, their sub-options, the height toggle and
-- the mold-line slide.
-- ------------------------------------------------------------------------

function GlazeStudioScreen:_BuildCarveBench(parent: Instance): Frame
	local theme = self:GetTheme()
	local bench = self:_Panel(parent, "CarveBench", 1)
	UIStyler.Padding(PANEL_PAD).Parent = bench
	UIStyler.ListLayout({
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, ROW_GAP),
	}).Parent = bench

	self:_Section(bench, "Tools", 0)

	for index, tool in SHAPE_TOOLS do
		self._shapeButtons[tool.id] = self:_Button(bench, {
			text = tool.label,
			iconKey = tool.iconKey,
			index = index,
			layoutOrder = index,
			onClick = function()
				self:_SetShapeTool(tool.id)
			end,
		})
	end

	local shapeNote = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "ShapeNote")
	shapeNote.Text = SHAPE_TOOLS[1].note
	shapeNote.TextXAlignment = Enum.TextXAlignment.Left
	shapeNote.TextWrapped = true
	shapeNote.Size = UDim2.new(1, 0, 0, 34)
	shapeNote.LayoutOrder = 4
	shapeNote.Parent = bench
	self._shapeNote = shapeNote

	-- The wheel's own state, said out loud. The source publishes Spinning and
	-- silently parks the wheel when Ridge is equipped (restoring the prior spin
	-- when it is put down) — a rule the player could only ever infer from the
	-- pot. Here it is a live line.
	local wheelNote = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "WheelNote")
	wheelNote.TextXAlignment = Enum.TextXAlignment.Left
	wheelNote.TextWrapped = true
	wheelNote.Size = UDim2.new(1, 0, 0, 34)
	wheelNote.LayoutOrder = 5
	wheelNote.Parent = bench
	self._wheelNote = wheelNote

	-- Groove's cut profile: V is a linear falloff, U a cosine one.
	local grooveRow = UIStyler.Frame("GrooveRow")
	grooveRow.BackgroundTransparency = 1
	grooveRow.Size = UDim2.new(1, 0, 0, 38)
	grooveRow.LayoutOrder = 6
	grooveRow.Visible = false
	grooveRow.Parent = bench
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
	}).Parent = grooveRow
	self._grooveRow = grooveRow

	for index, profile in GROOVE_PROFILES do
		self._grooveButtons[profile.id] = self:_Button(grooveRow, {
			text = profile.id .. "  \u{00B7}  " .. profile.note,
			widthPx = 168,
			heightPx = 38,
			index = index,
			layoutOrder = index,
			onClick = function()
				self._grooveProfile = profile.id
				self:_RefreshTools()
			end,
		})
	end

	-- Ridge symmetry: how many mirrored ridges one drag carves.
	local ridgeRow = UIStyler.Frame("RidgeRow")
	ridgeRow.BackgroundTransparency = 1
	ridgeRow.Size = UDim2.new(1, 0, 0, 38)
	ridgeRow.LayoutOrder = 7
	ridgeRow.Visible = false
	ridgeRow.Parent = bench
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
	}).Parent = ridgeRow
	self._ridgeRow = ridgeRow

	for index, count in RIDGE_SYMMETRY do
		self._ridgeButtons[count] = self:_Button(ridgeRow, {
			text = tostring(count),
			widthPx = 62,
			heightPx = 38,
			index = index,
			layoutOrder = index,
			onClick = function()
				self._ridgeSymmetry = count
				self:_RefreshTools()
				self:_RefreshStats()
			end,
		})
	end

	-- THE MOLD-LINE SLIDE. The rail spans the axis both ways: the SIDE of the
	-- notch you drag to is the side of the spin axis the guide stands on, and
	-- the radius is the distance from it. That is the source's derivation
	-- (guideSide from the sign, guideR from the magnitude), not a second dial.
	self:_Section(bench, "Mold line", 8)

	local slide = UIStyler.Frame("GuideSlide")
	slide.BackgroundTransparency = 1
	slide.Size = UDim2.new(1, 0, 0, 62)
	slide.LayoutOrder = 9
	slide.Parent = bench

	local slideCaption = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Caption")
	slideCaption.Text = "Drag either side of the axis"
	slideCaption.TextXAlignment = Enum.TextXAlignment.Left
	slideCaption.Size = UDim2.new(1, -180, 0, 18)
	slideCaption.Parent = slide

	-- Wider than the dial readouts: this one prints a SIDE as well as a
	-- distance ("2.40 studs left"), and a clipped side word is a lie.
	local slideValue = GPLayoutKit.NumberText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "Value")
	slideValue.AnchorPoint = Vector2.new(1, 0)
	slideValue.Position = UDim2.new(1, 0, 0, 0)
	slideValue.Size = UDim2.fromOffset(170, 18)
	slideValue.Parent = slide
	self._slideValue = slideValue

	local slideTrack = Instance.new("TextButton")
	slideTrack.Name = "Track"
	slideTrack.BackgroundTransparency = 1
	slideTrack.Text = ""
	slideTrack.AutoButtonColor = false
	slideTrack.Position = UDim2.fromOffset(0, 24)
	slideTrack.Size = UDim2.new(1, 0, 0, 34)
	slideTrack.Parent = slide

	local slideRail = UIStyler.Frame("Rail")
	slideRail.BackgroundColor3 = theme.Arcade.RulerTrack
	slideRail.BackgroundTransparency = 0
	slideRail.AnchorPoint = Vector2.new(0.5, 0.5)
	slideRail.Position = UDim2.fromScale(0.5, 0.5)
	slideRail.Size = UDim2.new(1, 0, 0, 8)
	slideRail.Parent = slideTrack
	UIStyler.Corner(theme.Radii.Pill).Parent = slideRail

	-- The spin axis: dead centre, because the shaping camera looks straight on.
	local axisNotch = UIStyler.Frame("AxisNotch")
	axisNotch.BackgroundColor3 = theme.Studio.Tan
	axisNotch.BackgroundTransparency = 0
	axisNotch.AnchorPoint = Vector2.new(0.5, 0.5)
	axisNotch.Position = UDim2.fromScale(0.5, 0.5)
	axisNotch.Size = UDim2.fromOffset(3, 18)
	axisNotch.ZIndex = 2
	axisNotch.Parent = slideRail
	UIStyler.Corner(theme.Radii.Pill).Parent = axisNotch

	local marker = GPLayoutKit.Text(theme, 20, theme.Colors.Primary, "Marker")
	marker.Text = "\u{25BC}"
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Position = UDim2.new(0.5, 0, 0.5, 0)
	marker.Size = UDim2.fromOffset(28, 28)
	marker.ZIndex = 3
	marker.Parent = slideRail
	self._guideMarker = marker

	local markerBubbleFill = theme.Colors.SurfaceRaised
	local markerBubble = UIStyler.Frame("Bubble")
	markerBubble.BackgroundColor3 = markerBubbleFill
	markerBubble.BackgroundTransparency = 0
	markerBubble.AnchorPoint = Vector2.new(0.5, 1)
	markerBubble.Position = UDim2.new(0.5, 0, 0, -4)
	markerBubble.Size = UDim2.fromOffset(96, 22)
	markerBubble.Visible = false
	markerBubble.ZIndex = 4
	markerBubble.Parent = marker
	UIStyler.Corner(theme.Radii.Pill).Parent = markerBubble
	GPLayoutKit.SoftStroke(theme, markerBubble, markerBubbleFill)

	local markerText = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "Value")
	markerText.Size = UDim2.fromScale(1, 1)
	markerText.ZIndex = 5
	markerText.Parent = markerBubble
	self._guideBubble = markerBubble
	self._guideBubbleText = markerText

	local span = STUDIO.guideMaxR
	slideTrack.MouseButton1Down:Connect(function()
		markerBubble.Visible = true
		self._drag = {
			rail = slideRail,
			apply = function(fraction: number)
				-- fraction 0..1 across a -span..+span rail: the sign is the side.
				local signed = (math.clamp(fraction, 0, 1) * 2 - 1) * span
				self._guideSide = if signed >= 0 then 1 else -1
				self:_SetGuideRadius(math.clamp(math.abs(signed), STUDIO.guideMinR, STUDIO.guideMaxR), true)
			end,
			release = function()
				markerBubble.Visible = false
			end,
		}
		self:_DragToMouse()
	end)

	local carveActions = UIStyler.Frame("CarveActions")
	carveActions.BackgroundTransparency = 1
	carveActions.Size = UDim2.new(1, 0, 0, BTN_H)
	carveActions.LayoutOrder = 10
	carveActions.Parent = bench
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
	}).Parent = carveActions

	-- The height toggle: the control mobile players actually need mid-shape.
	self._heightButton = self:_Button(carveActions, {
		text = "\u{2195}  Height",
		widthPx = 132,
		index = 0,
		layoutOrder = 1,
		onClick = function()
			self._heightLive = not self._heightLive
			self:_RefreshTools()
		end,
	})
	self:_Button(carveActions, {
		text = "Reset clay",
		fill = theme.Studio.Back,
		widthPx = 122,
		index = 1,
		layoutOrder = 2,
		onClick = function()
			self._ridgeSymmetry = 1
			self._grooveProfile = "V"
			self._guideSide = 1
			-- driveSlider = true: a programmatic reset has to move the Distance
			-- dial too, or the pair would disagree until the next drag.
			self:_SetGuideRadius(1, true)
			self:_RefreshTools()
			self:_RefreshStats()
		end,
	})
	self:_Button(carveActions, {
		text = "Paint  \u{2192}",
		fill = theme.Studio.Next,
		widthPx = 116,
		index = 2,
		layoutOrder = 3,
		onClick = function()
			self:_SelectTab("glaze")
		end,
	})

	return bench
end

-- ------------------------------------------------------------------------
-- CENTRE / ADD-ONS: the placement dials, confirm/remove/clear.
-- ------------------------------------------------------------------------

function GlazeStudioScreen:_BuildAddonBench(parent: Instance): Frame
	local theme = self:GetTheme()
	local bench = self:_Panel(parent, "AddonBench", 1)
	UIStyler.Padding(PANEL_PAD).Parent = bench
	UIStyler.ListLayout({
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, ROW_GAP),
	}).Parent = bench

	self:_Section(bench, "Placement", 0)

	local hint = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Hint")
	hint.Text = STUDIO.placementHint
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextWrapped = true
	hint.Size = UDim2.new(1, 0, 0, 52)
	hint.LayoutOrder = 1
	hint.Parent = bench

	-- Symmetry is a NEXT-PLACEMENT setting: how many radial copies one click
	-- drops. It is never a per-piece value, so selecting a piece leaves it be.
	self._sliders.accSymmetry = self:_Slider(bench, {
		label = "Copies around the pot",
		min = 1,
		max = STUDIO.accSymmetryMax,
		default = self._accSymmetry,
		step = 1,
		unit = "copies",
		layoutOrder = 2,
		accent = theme.Colors.Secondary,
		onChange = function(v)
			self._accSymmetry = v
			self:_RefreshStats()
		end,
	})

	-- Rotate and Scale double as live editors: with a piece selected they drive
	-- THAT piece as a pending edit; with nothing selected they are the
	-- next-placement defaults.
	self._sliders.accRotation = self:_Slider(bench, {
		label = "Spin",
		min = 0,
		max = 360,
		default = self._accRotation,
		step = STUDIO.accRotationStep,
		unit = "deg",
		layoutOrder = 3,
		onChange = function(v)
			self._accRotation = v
			self:_RefreshPlacement()
		end,
	})
	self._sliders.accScale = self:_Slider(bench, {
		label = "Scale",
		min = STUDIO.accScaleMin,
		max = STUDIO.accScaleMax,
		default = self._accScale,
		step = STUDIO.accScaleStep,
		unit = "x",
		layoutOrder = 4,
		accent = theme.Arcade.Gold,
		onChange = function(v)
			self._accScale = v
			self:_RefreshPlacement()
		end,
	})

	local selectionNote = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "SelectionNote")
	selectionNote.TextXAlignment = Enum.TextXAlignment.Left
	selectionNote.TextWrapped = true
	selectionNote.Size = UDim2.new(1, 0, 0, 34)
	selectionNote.LayoutOrder = 5
	selectionNote.Parent = bench
	self._selectionNote = selectionNote

	local actions = UIStyler.Frame("AddonActions")
	actions.BackgroundTransparency = 1
	actions.Size = UDim2.new(1, 0, 0, BTN_H)
	actions.LayoutOrder = 6
	actions.Parent = bench
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
	}).Parent = actions

	-- Done and Remove exist ONLY while a piece is selected, exactly as the
	-- source hides them: they are one-shot confirms, not standing controls.
	self._doneButton = self:_Button(actions, {
		text = "\u{2713}  Done",
		fill = theme.Studio.Next,
		widthPx = 124,
		index = 0,
		layoutOrder = 1,
		onClick = function()
			self:_ConfirmPiece()
		end,
	})
	self._removeButton = self:_Button(actions, {
		text = "Remove",
		fill = theme.Studio.Back,
		widthPx = 116,
		index = 1,
		layoutOrder = 2,
		onClick = function()
			self:_RemovePiece()
		end,
	})
	self:_Button(actions, {
		text = "Clear all",
		widthPx = 116,
		index = 2,
		layoutOrder = 3,
		onClick = function()
			self._piecesPlaced = 0
			self._lastPlacedCount = 0
			self._pieceSelected = false
			self:_RefreshPlacement()
			self:_RefreshStats()
		end,
	})

	-- A placed piece is a thing you can pick back up; without a wheel to click,
	-- this is how the selected-piece state is reachable in the collection.
	self._placeButton = self:_Button(bench, {
		text = "Place the picked piece on the pot",
		fill = theme.Colors.Secondary,
		index = 3,
		layoutOrder = 7,
		onClick = function()
			self:_PlacePiece()
		end,
	})

	return bench
end

-- ------------------------------------------------------------------------
-- RIGHT / GLAZE: the swatch shelf.
-- ------------------------------------------------------------------------

function GlazeStudioScreen:_BuildGlazeShelf(parent: Instance): Frame
	local theme = self:GetTheme()
	local panel = self:_Panel(parent, "GlazeShelf", 2)
	UIStyler.Padding(PANEL_PAD).Parent = panel

	local title = GPLayoutKit.SectionLabel(theme, panel, "Colours")
	title.Size = UDim2.new(1, 0, 0, 24)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Shelf"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, 30)
	scroll.Size = UDim2.new(1, 0, 1, -30)
	-- Scrolled rows must never spill past the plate.
	scroll.ClipsDescendants = true
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = theme.Colors.Primary
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	-- Automatic canvas, not arithmetic: the shelf grows and shrinks with every
	-- "My Mixes" push, and a hand-computed CanvasSize is one forgotten term away
	-- from a section the player cannot scroll to.
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = panel
	-- Padding so a swatch's own soft shadow is not sliced by the clip.
	UIStyler.Padding(6).Parent = scroll
	UIStyler.ListLayout({
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 8),
	}).Parent = scroll
	self._shelfScroll = scroll

	local stockLabel = GPLayoutKit.SectionLabel(theme, scroll, "On the shelf")
	stockLabel.LayoutOrder = 1

	local stockGrid = UIStyler.Frame("StockGrid")
	stockGrid.BackgroundTransparency = 1
	stockGrid.Size = UDim2.new(1, 0, 0, 0)
	stockGrid.AutomaticSize = Enum.AutomaticSize.Y
	stockGrid.LayoutOrder = 2
	stockGrid.Parent = scroll
	UIStyler.GridLayout(UDim2.fromOffset(SWATCH, SWATCH), UDim2.fromOffset(SWATCH_GAP, SWATCH_GAP)).Parent = stockGrid
	self._stockGrid = stockGrid

	-- The "My Mixes" header + grid are a SECTION, not spliced rows: the tail is
	-- destroyed and rebuilt whole on every push (see _SetCustomGlazes).
	local mixLabel = GPLayoutKit.SectionLabel(theme, scroll, "My mixes")
	mixLabel.LayoutOrder = 3
	self._mixLabel = mixLabel

	local mixGrid = UIStyler.Frame("MixGrid")
	mixGrid.BackgroundTransparency = 1
	mixGrid.Size = UDim2.new(1, 0, 0, 0)
	mixGrid.AutomaticSize = Enum.AutomaticSize.Y
	mixGrid.LayoutOrder = 4
	mixGrid.Parent = scroll
	UIStyler.GridLayout(UDim2.fromOffset(SWATCH, SWATCH), UDim2.fromOffset(SWATCH_GAP, SWATCH_GAP)).Parent = mixGrid
	self._mixGrid = mixGrid

	return panel
end

-- One swatch: a petal chip in the glaze's own colour, ringed in its rarity
-- tint. The ring goes SOLID and thick when chosen — the source's cream-ring
-- selection language, now carrying rarity as well.
function GlazeStudioScreen:_AcquireSwatch(): any
	local theme = self:GetTheme()
	local pooled = table.remove(self._swatchPool)
	if pooled then
		pooled.root.Visible = true
		return pooled
	end

	local button = Instance.new("TextButton")
	button.Name = "Swatch"
	button.BackgroundTransparency = 1
	button.Text = ""
	button.AutoButtonColor = false
	button.Size = UDim2.fromOffset(SWATCH, SWATCH)

	local chip = UIStyler.Frame("Chip")
	chip.BackgroundColor3 = theme.Colors.Surface
	chip.BackgroundTransparency = 0
	chip.Size = UDim2.fromScale(1, 1)
	chip.Parent = button

	local ring = UIStyler.Stroke(theme.Semantic.Selection, 3, 0.55)
	ring.LineJoinMode = Enum.LineJoinMode.Round
	ring.Parent = chip

	-- Textured glazes carry a real SurfaceAppearance in the game; here the
	-- speckle pattern stands in for "this one has a texture, not a flat fill".
	local texture = GPLayoutKit.Tile(theme, "speckle", theme.Colors.TextPrimary, 0.88, "Texture")
	texture.Visible = false
	texture.ZIndex = 2
	texture.Parent = chip

	local tick = GPLayoutKit.Text(theme, 22, theme.Colors.TextPrimary, "Tick")
	tick.Text = "\u{2713}"
	tick.AnchorPoint = Vector2.new(1, 1)
	tick.Position = UDim2.new(1, -4, 1, -2)
	tick.Size = UDim2.fromOffset(22, 22)
	tick.Visible = false
	tick.ZIndex = 3
	tick.Parent = chip

	UIChrome.Animate(theme, button, chip)
	local entry = { root = button, chip = chip, ring = ring, texture = texture, tick = tick, conn = nil :: RBXScriptConnection? }
	return entry
end

function GlazeStudioScreen:_RenderShelf()
	if not self._shelfScroll then
		return
	end
	local theme = self:GetTheme()

	for _, entry in self._swatches do
		if entry.conn then
			entry.conn:Disconnect()
			entry.conn = nil
		end
		entry.root.Visible = false
		entry.root.Parent = nil
		table.insert(self._swatchPool, entry)
	end
	table.clear(self._swatches)

	local mixCount = 0
	for index, glaze in self._glazes do
		local entry = self:_AcquireSwatch()
		local custom = index > self._stockCount
		entry.root.LayoutOrder = index
		entry.root.Parent = if custom then self._mixGrid else self._stockGrid
		entry.chip.BackgroundColor3 = glaze.color
		GPLayoutKit.Petal(theme, entry.chip, index)
		entry.texture.Visible = glaze.textured == true
		entry.ring.Color = rarityColor(theme, glaze.rarity)
		entry.conn = entry.root.Activated:Connect(function()
			self._selectedGlaze = index
			UIChrome.Pulse(theme, entry.chip)
			self:_RefreshGlaze()
		end)
		table.insert(self._swatches, entry)
		if custom then
			mixCount += 1
		end
	end

	-- Both grids auto-size to their rows and the scroller auto-sizes to them, so
	-- an empty mix tail simply collapses: hiding the pair is enough, because
	-- UIListLayout skips invisible children.
	self._mixGrid.Visible = mixCount > 0
	self._mixLabel.Visible = mixCount > 0
	self:_RefreshSwatchSelection()
end

function GlazeStudioScreen:_RefreshSwatchSelection()
	for index, entry in self._swatches do
		local on = index == self._selectedGlaze
		entry.ring.Transparency = if on then 0 else 0.55
		entry.ring.Thickness = if on then 4 else 3
		entry.tick.Visible = on
	end
end

-- Replace the "My Mixes" tail WHOLE. Splicing would shift every index under a
-- live selection, so the selection is remembered by NAME and re-resolved after.
function GlazeStudioScreen:_SetCustomGlazes(customs: { Glaze })
	local keepName: string? = nil
	if self._selectedGlaze and self._selectedGlaze > self._stockCount then
		local glaze = self._glazes[self._selectedGlaze]
		keepName = glaze and glaze.name
	end
	for i = #self._glazes, self._stockCount + 1, -1 do
		self._glazes[i] = nil
	end
	for _, custom in customs do
		local entry = table.clone(custom)
		entry.custom = true
		table.insert(self._glazes, entry)
	end
	if keepName then
		local resolved: number? = nil
		for i = self._stockCount + 1, #self._glazes do
			if self._glazes[i].name == keepName then
				resolved = i
				break
			end
		end
		self._selectedGlaze = resolved
	end
	self:_RenderShelf()
	self:_RefreshGlaze()
end

-- ------------------------------------------------------------------------
-- RIGHT / CARVE: the guide flyout.
-- ------------------------------------------------------------------------

function GlazeStudioScreen:_BuildGuidePanel(parent: Instance): Frame
	local theme = self:GetTheme()
	local panel = self:_Panel(parent, "GuidePanel", 2)
	UIStyler.Padding(PANEL_PAD).Parent = panel
	UIStyler.ListLayout({
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, ROW_GAP),
	}).Parent = panel

	self:_Section(panel, "Guide", 0)

	local note = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Note")
	note.Text = STUDIO.guideHint
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.TextWrapped = true
	note.Size = UDim2.new(1, 0, 0, 52)
	note.LayoutOrder = 1
	note.Parent = panel
	self._guideNote = note

	self._guideButton = self:_Button(panel, {
		text = "Guide: off",
		index = 0,
		layoutOrder = 2,
		onClick = function()
			if self._shapeTool ~= "Hands" then
				return -- hands-only, exactly as the source gates the flyout
			end
			self._guideOn = not self._guideOn
			self:_RefreshGuide()
		end,
	})

	-- Distance is TWO-WAY synced with the slide: driving one drives the other,
	-- and _guideSyncing is the echo guard that stops the pair looping.
	self._sliders.guideDistance = self:_Slider(panel, {
		label = "Distance from the axis",
		min = STUDIO.guideMinR,
		max = STUDIO.guideMaxR,
		default = self._guideR,
		step = 0.1,
		unit = "studs",
		layoutOrder = 3,
		onChange = function(v)
			if self._guideSyncing then
				return
			end
			self:_SetGuideRadius(v, false)
		end,
	})

	-- Angle swings both ways, so it is a centre-origin dial: value 0 = plumb.
	self._sliders.guideAngle = self:_Slider(panel, {
		label = "Tilt",
		min = -1,
		max = 1,
		default = self._guideAngle,
		step = 0.1,
		centerOrigin = true,
		layoutOrder = 4,
		accent = theme.Colors.Secondary,
		onChange = function(v)
			self._guideAngle = v
			self:_RefreshGuide()
		end,
	})

	self._sideLabel = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "SideLabel")
	self._sideLabel.TextXAlignment = Enum.TextXAlignment.Left
	self._sideLabel.Size = UDim2.new(1, 0, 0, 22)
	self._sideLabel.LayoutOrder = 5
	self._sideLabel.Parent = panel

	-- The wall slider is gone from the game (the wheel pins HollowThickness to
	-- its minimum), so this is a stated fact, not a dial. The readout column
	-- carries the same number with a bar.
	local wallNote = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "WallNote")
	wallNote.TextXAlignment = Enum.TextXAlignment.Left
	wallNote.TextWrapped = true
	wallNote.Size = UDim2.new(1, 0, 0, 34)
	wallNote.LayoutOrder = 6
	wallNote.Parent = panel
	self._wallNote = wallNote

	return panel
end

-- ------------------------------------------------------------------------
-- RIGHT / ADD-ONS: the picker.
-- ------------------------------------------------------------------------

function GlazeStudioScreen:_BuildAddonList(parent: Instance): Frame
	local theme = self:GetTheme()
	local panel = self:_Panel(parent, "AddonList", 2)
	UIStyler.Padding(PANEL_PAD).Parent = panel

	local title = GPLayoutKit.SectionLabel(theme, panel, "Add-ons")
	title.Size = UDim2.new(1, 0, 0, 24)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Picker"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, 30)
	scroll.Size = UDim2.new(1, 0, 1, -30)
	scroll.ClipsDescendants = true
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = theme.Colors.Primary
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = panel
	UIStyler.Padding(6).Parent = scroll
	UIStyler.ListLayout({
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 8),
	}).Parent = scroll
	self._accScroll = scroll

	-- The empty state is the source's, verbatim: it tells a builder exactly
	-- what to add and where.
	local empty = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Empty")
	empty.Text = STUDIO.noAccessories
	empty.TextXAlignment = Enum.TextXAlignment.Left
	empty.TextWrapped = true
	empty.Size = UDim2.new(1, 0, 0, 60)
	empty.LayoutOrder = 1
	empty.Visible = false
	empty.Parent = scroll
	self._accEmpty = empty

	return panel
end

function GlazeStudioScreen:_AcquireAccRow(): any
	local theme = self:GetTheme()
	local pooled = table.remove(self._accRowPool)
	if pooled then
		pooled.root.Visible = true
		return pooled
	end

	local button = Instance.new("TextButton")
	button.Name = "AccRow"
	button.BackgroundTransparency = 1
	button.Text = ""
	button.AutoButtonColor = false
	button.Size = UDim2.new(1, -6, 0, ACC_ROW_H)

	local bodyFill = theme.Colors.SurfaceRaised
	local body = UIStyler.Frame("Body")
	body.BackgroundColor3 = bodyFill
	body.BackgroundTransparency = 0
	body.Size = UDim2.fromScale(1, 1)
	body.Parent = button
	local ring = GPLayoutKit.SoftStroke(theme, body, bodyFill)

	local wellFill = theme.Colors.Surface
	local well = UIStyler.Frame("Well")
	well.BackgroundColor3 = wellFill
	well.BackgroundTransparency = 0
	well.Position = UDim2.fromOffset(10, 10)
	well.Size = UDim2.fromOffset(ACC_ROW_H - 20, ACC_ROW_H - 20)
	well.Parent = body

	local image, glyph = newIcon(well, 40, theme.Colors.TextPrimary)

	local name = GPLayoutKit.Text(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "Name")
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(ACC_ROW_H, 12)
	name.Size = UDim2.new(1, -(ACC_ROW_H + 56), 0, 22)
	name.Parent = body

	local folder = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Folder")
	folder.TextXAlignment = Enum.TextXAlignment.Left
	folder.TextTruncate = Enum.TextTruncate.AtEnd
	folder.Position = UDim2.fromOffset(ACC_ROW_H, 36)
	folder.Size = UDim2.new(1, -(ACC_ROW_H + 56), 0, 20)
	folder.Parent = body

	local badgeFill = theme.Colors.Surface
	local badge = UIStyler.Frame("Badge")
	badge.BackgroundColor3 = badgeFill
	badge.BackgroundTransparency = 0
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.Position = UDim2.new(1, -10, 0, 10)
	badge.Size = UDim2.fromOffset(46, 22)
	badge.Visible = false
	badge.ZIndex = 3
	badge.Parent = body
	UIStyler.Corner(theme.Radii.Pill).Parent = badge

	local badgeText = GPLayoutKit.NumberText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "Count")
	badgeText.TextXAlignment = Enum.TextXAlignment.Center
	badgeText.Size = UDim2.fromScale(1, 1)
	badgeText.ZIndex = 4
	badgeText.Parent = badge

	-- Out of stock: the card still previews (and stays clickable), it just says
	-- where to get more. Same wording the game already uses, and the same
	-- PLACEMENT — the source lays its scrim over the thumbnail well, which is
	-- also the only rect on this row that no text is already using. Anchored
	-- to the right of the name lines it would sit on top of the folder line.
	local scrimFill = theme.Studio.WarnBg
	local scrim = UIStyler.Frame("Scrim")
	scrim.BackgroundColor3 = scrimFill
	scrim.BackgroundTransparency = 0.12
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.Visible = false
	scrim.ZIndex = 3
	scrim.Parent = well

	local scrimText = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Studio.WarnText, "Text")
	scrimText.Text = STUDIO.buyAtStorage
	scrimText.TextWrapped = true
	scrimText.Size = UDim2.fromScale(1, 1)
	scrimText.ZIndex = 4
	scrimText.Parent = scrim

	UIChrome.Animate(theme, button, body)
	return {
		root = button,
		body = body,
		well = well,
		ring = ring,
		image = image,
		glyph = glyph,
		name = name,
		folder = folder,
		badge = badge,
		badgeText = badgeText,
		scrim = scrim,
		conn = nil :: RBXScriptConnection?,
	}
end

function GlazeStudioScreen:_RenderAccessories()
	if not self._accScroll then
		return
	end
	local theme = self:GetTheme()

	for _, row in self._accRows do
		if row.conn then
			row.conn:Disconnect()
			row.conn = nil
		end
		row.root.Visible = false
		row.root.Parent = nil
		table.insert(self._accRowPool, row)
	end
	table.clear(self._accRows)

	self._accEmpty.Visible = #self._accessories == 0

	for index, accessory in self._accessories do
		local row = self:_AcquireAccRow()
		row.root.LayoutOrder = index + 1
		row.root.Parent = self._accScroll
		GPLayoutKit.Petal(theme, row.body, index)
		GPLayoutKit.Petal(theme, row.well, index + 1)
		-- The scrim fills the well exactly, so it takes the well's silhouette.
		GPLayoutKit.Petal(theme, row.scrim, index + 1)
		row.name.Text = accessory.name
		row.folder.Text = accessory.folder
		applyIcon(row.image, row.glyph, accessory.iconKey)

		local key = accessory.folder .. "/" .. accessory.name
		row.key = key
		row.conn = row.root.Activated:Connect(function()
			self._accPickedKey = key
			UIChrome.Pulse(theme, row.body)
			self:_RefreshAccessories()
		end)
		table.insert(self._accRows, row)
	end

	-- No canvas arithmetic: the picker's scroller auto-sizes to its rows.
	self:_RefreshAccessories()
end

-- ========================================================================
-- STATE + REFRESH
-- ========================================================================

function GlazeStudioScreen:_SelectTab(id: string)
	self._tab = id
	if self._tabs then
		self._tabs.Select(id)
	end
	if self._benches then
		for key, bench in self._benches do
			bench.Visible = key == id
		end
	end
	if self._sides then
		for key, side in self._sides do
			side.Visible = key == id
		end
	end
end

-- Ridge cannot carve a spinning pot, so equipping it parks the wheel and the
-- prior spin state comes back the moment the tool is put down.
function GlazeStudioScreen:_SetShapeTool(id: string)
	if self._shapeTool == id then
		return
	end
	if id == "Ridge" then
		self._preRidgeSpin = self._spinning
		self._spinning = false
	elseif self._shapeTool == "Ridge" then
		self._spinning = self._preRidgeSpin
	end
	self._shapeTool = id
	self:_RefreshTools()
end

-- One radius, two controls. `driveSlider` is false only when the Distance dial
-- is what moved — writing back to it there would be the echo the source's
-- guideSyncing flag exists to kill.
function GlazeStudioScreen:_SetGuideRadius(radius: number, driveSlider: boolean)
	self._guideR = math.clamp(radius, STUDIO.guideMinR, STUDIO.guideMaxR)
	if driveSlider and self._sliders.guideDistance then
		self._guideSyncing = true
		self._sliders.guideDistance.Set(self._guideR)
		self._guideSyncing = false
	end
	self:_RefreshGuide()
end

function GlazeStudioScreen:_PlacePiece()
	if not self._accPickedKey then
		return
	end
	-- Remember how many copies THIS click dropped: symmetry is a live dial, so
	-- Remove must undo what was placed, not what the dial happens to say now.
	self._lastPlacedCount = self._accSymmetry
	self._piecesPlaced += self._accSymmetry
	self._pieceSelected = true
	-- A freshly placed piece is selected with the dials as its committed state.
	self._accScaleCommitted = self._accScale
	self._accRotationCommitted = self._accRotation
	self:_RefreshPlacement()
	self:_RefreshStats()
end

function GlazeStudioScreen:_ConfirmPiece()
	if not self._pieceSelected then
		return
	end
	self._accScaleCommitted = self._accScale
	self._accRotationCommitted = self._accRotation
	self._pieceSelected = false
	self:_RefreshPlacement()
	self:_RefreshStats()
end

function GlazeStudioScreen:_RemovePiece()
	if not self._pieceSelected then
		return
	end
	self._piecesPlaced = math.max(0, self._piecesPlaced - self._lastPlacedCount)
	self._lastPlacedCount = 0
	self._pieceSelected = false
	-- The pending edit dies with the piece; the dials fall back to the
	-- next-placement defaults, which are the last committed values.
	self._accScale = self._accScaleCommitted
	self._accRotation = self._accRotationCommitted
	if self._sliders.accScale then
		self._sliders.accScale.Set(self._accScale)
	end
	if self._sliders.accRotation then
		self._sliders.accRotation.Set(self._accRotation)
	end
	self:_RefreshPlacement()
	self:_RefreshStats()
end

function GlazeStudioScreen:_RefreshAll()
	self:_RenderShelf()
	self:_RenderAccessories()
	self:_RefreshTools()
	self:_RefreshGlaze()
	self:_RefreshGuide()
	self:_RefreshPlacement()
	self:_RefreshStats()
	self:_RefreshHints()
end

function GlazeStudioScreen:_RefreshTools()
	for id, button in self._toolButtons do
		button.SetSelected(id == self._glazeTool)
	end
	for _, tool in GLAZE_TOOLS do
		if tool.id == self._glazeTool and self._toolNote then
			-- GlazeLineDir is published as "H" and only Paint/Erase read it; Fill
			-- ignores direction entirely, so only those two say which way the
			-- stroke runs.
			local direction = if tool.id == "Fill"
				then ""
				elseif self._glazeLineDir == "H" then " Strokes run as horizontal rings."
				else " Strokes run as vertical stripes."
			self._toolNote.Text = tool.note .. direction
		end
	end
	for id, button in self._shapeButtons do
		button.SetSelected(id == self._shapeTool)
	end
	for _, tool in SHAPE_TOOLS do
		if tool.id == self._shapeTool and self._shapeNote then
			self._shapeNote.Text = tool.note
		end
	end
	for id, button in self._grooveButtons do
		button.SetSelected(id == self._grooveProfile)
	end
	for count, button in self._ridgeButtons do
		button.SetSelected(count == self._ridgeSymmetry)
	end
	if self._grooveRow then
		self._grooveRow.Visible = self._shapeTool == "Groove"
	end
	if self._ridgeRow then
		self._ridgeRow.Visible = self._shapeTool == "Ridge"
	end
	if self._heightButton then
		self._heightButton.label.Text = if self._heightLive then "\u{2195}  Height: on" else "\u{2195}  Height"
		self._heightButton.SetSelected(self._heightLive)
	end
	if self._wheelNote then
		self._wheelNote.Text = if self._spinning
			then "The wheel is turning."
			else "The wheel is parked \u{2014} ridges need a still pot. Put the tool down and the spin comes back."
	end
	-- The band preview reads the TOOL as well as the width: Fill floods the well,
	-- Erase greys it, Paint takes the glaze's own colour.
	self:_RefreshBrush()
	-- The guide flyout follows the live tool (the source only shows it for Hands).
	self:_RefreshGuide()
end

function GlazeStudioScreen:_RefreshBrush()
	if self._band then
		local theme = self:GetTheme()
		local glaze = if self._selectedGlaze then self._glazes[self._selectedGlaze] else nil
		local floods = self._glazeTool == "Fill"
		local height = if floods then 36 else math.round(6 + self._brush * 28)
		self._band.Size = UDim2.new(1, 0, 0, height)
		self._band.BackgroundColor3 = if self._glazeTool == "Erase"
			then theme.Colors.Disabled
			elseif glaze then glaze.color
			else theme.Colors.Disabled
	end
	if self._stats.brush then
		self._stats.brush.SetValue(self._brush)
	end
end

function GlazeStudioScreen:_RefreshGlaze()
	if not self._glazeChip then
		return -- torn down (or not built yet): nothing to repaint
	end
	local theme = self:GetTheme()
	local glaze = if self._selectedGlaze then self._glazes[self._selectedGlaze] else nil

	if glaze then
		local tint = rarityColor(theme, glaze.rarity)
		self._glazeChip.BackgroundColor3 = glaze.color
		self._chipStroke.Color = tint
		self._chipStroke.Transparency = 0
		self._surfaceStroke.Color = tint
		self._surfaceStroke.Transparency = 0.2
		self._glazeName.Text = glaze.name
		local kind = if glaze.textured then "textured glaze" else "flat colour"
		local where = if glaze.custom then "from my mixes" else "on the shelf"
		self._glazeRarity.Text = string.format("%s \u{00B7} %s \u{00B7} %s", rarityName(glaze.rarity), kind, where)
		self._stats.rough.SetValue(glaze.rough or 0)
		self._stats.metal.SetValue(glaze.metal or 0)
	else
		local fill = theme.Colors.SurfaceRaised
		self._glazeChip.BackgroundColor3 = fill
		self._chipStroke.Color = GPLayoutKit.Deepen(theme, fill, 1)
		self._chipStroke.Transparency = 0.35
		self._surfaceStroke.Color = GPLayoutKit.Deepen(theme, theme.Colors.Surface, 1)
		self._surfaceStroke.Transparency = 0.35
		self._glazeName.Text = "No glaze picked"
		self._glazeRarity.Text = STUDIO.emptyShelf
		self._stats.rough.SetValue(0)
		self._stats.metal.SetValue(0)
	end

	self:_RefreshSwatchSelection()
	self:_RefreshBrush()
	self:_RefreshMeters()
	self:_RefreshStats()
	self:_RefreshHints()
end

function GlazeStudioScreen:_RefreshMeters()
	local theme = self:GetTheme()
	local stock = self._paintStock
	-- The source's three bands: sage above 6, butter under 6, terracotta at 0.
	local tone = if stock <= 0
		then theme.Studio.Back
		elseif stock < STUDIO.meterLow then theme.Arcade.Gold
		else theme.Colors.Secondary
	if self._meters.paint then
		self._meters.paint.Set(stock / STUDIO.meterFull, string.format("%d units", math.floor(stock)), tone)
	end
	if self._meters.coverage then
		self._meters.coverage.Set(
			self._coverage / 100,
			string.format("%.1f %%", self._coverage),
			theme.Colors.Primary
		)
	end
	if self._stockPill then
		self._stockPill.amount.Text = string.format("%d units", math.floor(stock))
	end
end

function GlazeStudioScreen:_RefreshGuide()
	local theme = self:GetTheme()
	-- The mold line is a HANDS control: the source only ever shows this flyout
	-- while the Hands tool is up, because Groove and Ridge cut their own paths
	-- and the wheel's per-ring clamp is not in play for them. Rather than blank
	-- the column, the panel says so and the toggle reads as unavailable.
	local live = self._shapeTool == "Hands"
	if self._guideNote then
		self._guideNote.Text = if live
			then STUDIO.guideHint
			else STUDIO.guideNotHands
	end
	if self._guideButton then
		self._guideButton.label.Text = if not live
			then "Guide: hands only"
			elseif self._guideOn then "Guide: on"
			else "Guide: off"
		self._guideButton.SetSelected(live and self._guideOn)
	end
	if self._guideMarker then
		-- The marker re-derives from the radius every time, so the slide and the
		-- Distance dial can never disagree about where the line stands.
		local signed = self._guideR * self._guideSide
		local fraction = math.clamp((signed / STUDIO.guideMaxR + 1) / 2, 0, 1)
		self._guideMarker.Position = UDim2.new(fraction, 0, 0.5, 0)
		self._guideMarker.TextColor3 = if live and self._guideOn
			then theme.Colors.Primary
			else theme.Colors.Disabled
	end
	local sideWord = if self._guideSide >= 0 then "right" else "left"
	local printed = string.format(sliderFormat(0.1), self._guideR)
	if self._guideBubbleText then
		self._guideBubbleText.Text = printed .. " studs"
	end
	if self._slideValue then
		self._slideValue.Text = printed .. " studs " .. sideWord
	end
	if self._sideLabel then
		self._sideLabel.Text = string.format(
			"Standing %s of the axis, tilted %s\u{00B0} from plumb.",
			sideWord,
			string.format("%.1f", self._guideAngle * STUDIO.guideTiltDegrees)
		)
	end
	self:_RefreshStats()
end

function GlazeStudioScreen:_RefreshPlacement()
	local selected = self._pieceSelected
	if self._doneButton then
		self._doneButton.SetEnabled(selected)
	end
	if self._removeButton then
		self._removeButton.SetEnabled(selected)
	end
	if self._placeButton then
		self._placeButton.SetEnabled(not selected and self._accPickedKey ~= nil)
	end
	if self._selectionNote then
		if selected then
			self._selectionNote.Text =
				"A piece is selected. Scale and spin edit it live \u{2014} press Done to keep the change, or Remove to take it off."
		elseif self._accPickedKey then
			self._selectionNote.Text = "Nothing selected. Scale and spin are the settings the next piece lands with."
		else
			self._selectionNote.Text = "Pick an add-on at the right to get started."
		end
	end
	self:_RefreshStats()
end

function GlazeStudioScreen:_RefreshAccessories()
	local theme = self:GetTheme()
	for index, row in self._accRows do
		local accessory = self._accessories[index]
		if not accessory then
			continue
		end
		local on = row.key == self._accPickedKey
		row.ring.Color = if on then theme.Semantic.Selection else GPLayoutKit.Deepen(theme, theme.Colors.SurfaceRaised, 1)
		row.ring.Transparency = if on then 0 else 0.35
		row.ring.Thickness = if on then 3 else 2
		-- The picked card says so in its FOLDER line, not by dimming its name:
		-- an unpicked add-on is still perfectly readable.
		row.folder.TextColor3 = if on then theme.Colors.Primary else theme.Colors.TextSecondary

		-- Unknown stock (no push yet) is NOT zero: hide both badge and scrim.
		if not self._accStockKnown then
			row.badge.Visible = false
			row.scrim.Visible = false
		else
			local owned = accessory.owned or 0
			row.badge.Visible = true
			row.badgeText.Text = "\u{00D7}" .. tostring(owned)
			row.badgeText.TextColor3 = if owned <= 0 then theme.Studio.WarnText else theme.Colors.TextPrimary
			row.scrim.Visible = owned <= 0
		end
	end
	self:_RefreshPlacement()
end

function GlazeStudioScreen:_RefreshStats()
	local stats = self._stats
	if stats.coverage then
		stats.coverage.SetValue(self._coverage)
	end
	if stats.stock then
		stats.stock.SetValue(self._paintStock)
	end
	if stats.wall then
		stats.wall.SetValue(STUDIO.wallThickness)
	end
	if self._wallNote then
		self._wallNote.Text = string.format(
			"The wall sits at its thinnest, %s studs \u{2014} the wheel holds it there.",
			string.format(sliderFormat(0.1), STUDIO.wallThickness)
		)
	end
	if stats.guideR then
		stats.guideR.SetValue(self._guideR)
	end
	if stats.guideTilt then
		stats.guideTilt.SetValue(math.abs(self._guideAngle) * STUDIO.guideTiltDegrees)
		-- Plumb is neither side, so the label only names one once there is a lean.
		stats.guideTilt.label.Text = if math.abs(self._guideAngle) < 0.05
			then "Guide tilt"
			elseif self._guideAngle > 0 then "Tilt right"
			else "Tilt left"
	end
	if stats.symmetry then
		stats.symmetry.SetValue(self._ridgeSymmetry)
	end
	if stats.pieces then
		stats.pieces.SetValue(self._piecesPlaced)
	end
	if stats.accSym then
		stats.accSym.SetValue(self._accSymmetry)
	end
	-- THE DELTA GHOST: with a piece selected the row shows the COMMITTED value
	-- and previews the pending edit, so "Done" has something visible to commit.
	if stats.accScale then
		stats.accScale.SetValue(if self._pieceSelected then self._accScaleCommitted else self._accScale)
		stats.accScale.SetPreview(if self._pieceSelected then self._accScale else nil)
	end
	if stats.accRot then
		stats.accRot.SetValue(if self._pieceSelected then self._accRotationCommitted else self._accRotation)
		stats.accRot.SetPreview(if self._pieceSelected then self._accRotation else nil)
	end
end

function GlazeStudioScreen:_RefreshHints()
	if not self._hints then
		return
	end
	local outOfGlaze = self._paintStock <= 0
	self._hints.glaze.SetVisible(outOfGlaze)
	self._hints.storage.SetVisible(self._storageFull)
	self._hints.clay.SetVisible(self._lowClay)
	if self._hintSection then
		self._hintSection.Visible = outOfGlaze or self._storageFull or self._lowClay
	end
end

-- ========================================================================
-- LIFECYCLE
-- ========================================================================

function GlazeStudioScreen:_Ingest(data: any?)
	if typeof(data) ~= "table" then
		return
	end
	if typeof(data.glazes) == "table" then
		self._glazes = table.clone(data.glazes)
		self._stockCount = #self._glazes
		self._selectedGlaze = nil
	end
	if typeof(data.accessories) == "table" then
		self._accessories = data.accessories
	end
	if typeof(data.accStockKnown) == "boolean" then
		self._accStockKnown = data.accStockKnown
	end
	if typeof(data.paintStock) == "number" then
		self._paintStock = data.paintStock
	end
	if typeof(data.coverage) == "number" then
		self._coverage = math.clamp(data.coverage, 0, 100)
	end
	if typeof(data.storageFull) == "boolean" then
		self._storageFull = data.storageFull
	end
	if typeof(data.lowClay) == "boolean" then
		self._lowClay = data.lowClay
	end
	if typeof(data.tab) == "string" then
		self._tab = data.tab
	end
	if self._built then
		self:_SelectTab(self._tab)
		self:_RefreshAll()
		-- Mixes arrive last: the tail replaces whole and re-resolves by name.
		if typeof(data.mixes) == "table" then
			self:_SetCustomGlazes(data.mixes)
		end
	end
end

function GlazeStudioScreen:_OnShow(data: any?)
	self:_Ingest(data)
	if self._page then
		UIChrome.PopIn(self:GetTheme(), self._page.content)
	elseif self._modal then
		UIChrome.PopIn(self:GetTheme(), self._modal.content)
	end
	-- THE one shared ticker: the glaze chip breathes so a wet surface reads as
	-- wet. No RunService loop, and the handle is released on teardown.
	if not self._breathe and self._glazeChip then
		local theme = self:GetTheme()
		local motion = ((theme :: any).DialectTokens or {}).motion or {}
		local amount = motion.breatheScale or 0.02
		local seconds = math.max(0.5, motion.breatheSeconds or 3)
		local scale = self._glazeChip:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		scale.Parent = self._glazeChip
		self._breathe = UITicker.Register(function(_dt: number, now: number)
			if not self._visible then
				return
			end
			scale.Scale = 1 + amount * math.sin(now * (2 * math.pi) / seconds)
		end, self._glazeChip)
		table.insert(self._tickers, self._breathe)
	end
end

function GlazeStudioScreen:Update(data: any)
	self:_Ingest(data)
end

function GlazeStudioScreen:_OnHide()
	-- Hiding mid-drag must not leave a knob swollen and a bubble hanging: the
	-- InputEnded that would have released it lands after the screen is gone.
	self:_EndDrag()
end

function GlazeStudioScreen:_OnTeardown()
	for _, stop in self._tickers do
		stop()
	end
	table.clear(self._tickers)
	self._breathe = nil

	for _, conn in self._conns do
		conn:Disconnect()
	end
	table.clear(self._conns)

	for _, entry in self._swatches do
		if entry.conn then
			entry.conn:Disconnect()
		end
	end
	table.clear(self._swatches)
	table.clear(self._swatchPool)

	for _, row in self._accRows do
		if row.conn then
			row.conn:Disconnect()
		end
	end
	table.clear(self._accRows)
	table.clear(self._accRowPool)

	-- A destroyed GuiObject alone leaves the shadow budget counter high.
	GPLayoutKit.ReleaseShadows(self._shadows)
	self._shadows = {}

	table.clear(self._stats)
	table.clear(self._sliders)
	table.clear(self._meters)
	table.clear(self._toolButtons)
	table.clear(self._shapeButtons)
	table.clear(self._grooveButtons)
	table.clear(self._ridgeButtons)
	-- Every instance reference this screen holds, dropped in one place: the Gui
	-- is destroyed right after this hook, and a live field pointing into it is a
	-- crash waiting for the next refresh call.
	self._drag = nil
	self._page = nil
	self._modal = nil
	self._tabs = nil
	self._benches = nil
	self._sides = nil
	self._hints = nil
	self._hintSection = nil
	self._stockPill = nil
	self._glazeChip = nil
	self._chipStroke = nil
	self._surfaceStroke = nil
	self._glazeName = nil
	self._glazeRarity = nil
	self._band = nil
	self._toolNote = nil
	self._shapeNote = nil
	self._wheelNote = nil
	self._grooveRow = nil
	self._ridgeRow = nil
	self._heightButton = nil
	self._guideButton = nil
	self._guideNote = nil
	self._guideMarker = nil
	self._guideBubble = nil
	self._guideBubbleText = nil
	self._slideValue = nil
	self._sideLabel = nil
	self._wallNote = nil
	self._selectionNote = nil
	self._doneButton = nil
	self._removeButton = nil
	self._placeButton = nil
	self._readoutScroll = nil
	self._shelfScroll = nil
	self._stockGrid = nil
	self._mixGrid = nil
	self._mixLabel = nil
	self._accScroll = nil
	self._accEmpty = nil
end

function GlazeStudioScreen:Destroy()
	self:_OnTeardown()
	UIScreenBase.Destroy(self)
end

return GlazeStudioScreen
