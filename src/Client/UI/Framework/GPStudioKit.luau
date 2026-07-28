--!strict
-- GPStudioKit — the MATTE (DialectStudio) composition layer shared by the
-- eight DATA-DENSE Girly Pop screens: battle pass, quest journal,
-- achievements, skill tree, statistics, rank, factions and titles.
--
-- GPLayoutKit is the pack's LAYOUT LANGUAGE (Page / Card / Tabs / StatRow /
-- petal corners / hue-matched shadows) and everything here composes from it.
-- What this file adds is the handful of builders those eight screens need and
-- the kit does not ship — an action button, a state chip, a standalone
-- progress ruler, a hairline rule, a clipped scroller — plus the two
-- corrections the pack laws demand of screens whose DATA was authored for the
-- arcade family (SHOUTED strings, pure-white icon fallbacks).
--
-- WHY A SEPARATE FILE AND NOT AN EDIT TO GPLayoutKit: the brief for these
-- screens is "compose from the kit; if a builder you need is missing,
-- improvise locally and note it". The alternative to this file is eight
-- private copies of the same action button, so the improvisation is shared
-- here — and GPLayoutKit itself is left exactly as its author wrote it.
--
-- THE LAWS THIS FILE IS RESPONSIBLE FOR (the kit enforces the rest):
--
--   * ANTI-CONDESCENSION, the hardest one. Nothing here may REDUCE what a
--     screen shows. Meter() always prints its numerals as well as drawing its
--     bar (a bar alone is a picture of a number) and keeps the ruler's ten
--     per cent ticks; StatLine() takes a VERBATIM valueText so a screen's own
--     formatter survives the port at full precision — StatsScreen prints
--     H:MM:SS durations and 1.2K counts, and rounding those to the studio
--     dialect's one decimal place would break the law by accident; and where
--     a readout is too long for the kit's fixed numeric column the column is
--     WIDENED, never truncated.
--
--   * NO all-caps body copy. SoftCase() title-cases the data strings that
--     were authored SHOUTING for the arcade family ("HONORED" -> "Honored")
--     and passes anything already carrying a lowercase letter through
--     untouched, so a deliberate "Novice Potter" is never mangled. Acronyms
--     and division numerals survive via KEEP_UPPER.
--
--   * NO pure white, NO pure black. IconArchive.Image's GLYPH FALLBACK (what
--     you get when the art has not uploaded yet) is born pure white with a
--     black text stroke — correct for the arcade family, two violations here
--     — so Icon() repaints it in ink.
--
--   * SOLID GuiButtons are effectively illegal under this pack: the
--     UIStyleEnforcer backstops any solid GuiButton with a BLACK 2px stroke
--     on sight. Button() therefore keeps the TextButton itself transparent
--     and paints a CHIP CHILD, exactly the way GPLayoutKit.Page builds its
--     close control.
--
--   * SHADOWS ARE BUDGETED AND HUE-MATCHED. Every shadow created here goes
--     through GPLayoutKit.Shadow (which derives its colour from the host's
--     own fill and registers the handle with StyleKit.Capabilities) into a
--     caller-owned sink. Nothing that repeats PER ROW / PER CELL / PER NODE
--     casts one: twenty shadowed rows would eat a quarter of the engine's
--     on-screen budget and turn a data table into a sticker sheet.
--
-- 0.4 BOUNDARY: like GPLayoutKit this is static composition. The only motion
-- delegated from here is UIChrome.Animate's hover/press juice, so it stays
-- one implementation. Sequenced motion lives in the screens, on UITicker.
--
-- OVERLAP WITH GPControlKit — READ BEFORE EXTENDING EITHER. GPControlKit
-- landed alongside this file with its own Button / Chip / Meter, and the two
-- SHOULD be consolidated. They are not yet, because the shapes these eight
-- data-dense screens need differ from the general control set in ways that
-- matter to the density law rather than to taste:
--   * Meter here is an OVERLAY ruler — caption and numerals sit INSIDE a
--     24-28px pill track that also carries the arcade ruler's ten-per-cent
--     ticks — because the slots on these pages are 24px tall (an achievement
--     tile's state row, the bar beside a faction icon). GPControlKit.Meter is
--     a 42px two-row stack with no ticks and a fixed "%d / %d" readout, and
--     these screens need a VERBATIM readout string: FactionScreen prints
--     "2,400 / 6,000" comma-grouped and AchievementsScreen prints 1.2K.
--   * Button here takes a resolved `iconId` (BattlePassScreen hands it
--     IconArchive.Id("robux")) and exposes SetText / SetTone / SetDimmed /
--     SetIcon separately rather than one SetContent.
--   * Chip here can take PETAL corners, not only the pill.
-- Consolidating means widening GPControlKit's three to cover the above and
-- then deleting them from here; nothing in the screens would have to move
-- except the module name.

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local GPLayoutKit = require(script.Parent.GPLayoutKit)

local GPStudioKit = {}

-- ---- constants ---------------------------------------------------------

local HAIRLINE = 1
local BUTTON_H = 48
local CHIP_H = 34
local METER_H = 24
local TICK_COUNT = 9 -- the ruler's ten-per-cent marks (doc §8), kept verbatim
local TICK_TALL = 10
local TICK_SHORT = 6

-- Words that must survive SoftCase intact: unit acronyms and the division
-- numerals RankScreen prints ("GOLD II"). Deliberately an EXPLICIT set — a
-- pattern-based roman-numeral test would also swallow "MIX", "DIM" and "LID".
local KEEP_UPPER: { [string]: boolean } = {
	RP = true, XP = true, HP = true, MP = true, KO = true, ID = true, OK = true,
	VIP = true, PVP = true, PVE = true, MVP = true, AFK = true, TNT = true,
	I = true, II = true, III = true, IV = true, V = true, VI = true,
	VII = true, VIII = true, IX = true, X = true, XI = true, XII = true,
}

-- ---- local helpers -----------------------------------------------------

-- The studio (matte) dialect namespace, with a house fallback so a pack that
-- omits it still renders in the same language.
local function studio(theme: Types.UITheme): { [string]: any }
	local tokens = (theme :: any).DialectTokens
	return (tokens and tokens.studio) or {}
end

local function ruleTint(theme: Types.UITheme): Color3
	return studio(theme).rule or theme.Studio.Tan
end

-- A Frame that is ALWAYS painted: UIStyler.Frame is born pure white, which
-- this pack forbids outright, so no builder here may use it bare.
local function surface(name: string, fill: Color3, transparency: number?): Frame
	local frame = UIStyler.Frame(name)
	frame.BackgroundColor3 = fill
	frame.BackgroundTransparency = transparency or 0
	return frame
end

-- ========================================================================
-- Copy
-- ========================================================================

-- Title-case a SHOUTED data string. A string already carrying any lowercase
-- letter is the author's own casing and passes through verbatim, so
-- "Novice Potter" and a player's DisplayName are safe; only the arcade
-- family's block capitals are softened. Digits, punctuation and em dashes are
-- untouched, and RichText markup (anything with a "<") is passed through
-- whole rather than risking a mangled tag.
function GPStudioKit.SoftCase(text: string): string
	if text == "" or string.find(text, "<", 1, true) or string.match(text, "%l") then
		return text
	end
	local out = string.gsub(text, "[%a']+", function(word: string): string
		if KEEP_UPPER[word] then
			return word
		end
		return string.upper(string.sub(word, 1, 1)) .. string.lower(string.sub(word, 2))
	end)
	return out
end

-- ========================================================================
-- Iconography
-- ========================================================================

-- IconArchive.Image, corrected for this pack. When the art has not uploaded
-- the archive falls back to a FredokaOne glyph painted PURE WHITE with a
-- black text stroke — the arcade family's language, and two pack-law
-- violations at once — so the fallback is repainted in ink here. Registration
-- with IconVisibility already happened inside the archive.
function GPStudioKit.Icon(theme: Types.UITheme, parent: Instance?, key: string, sizePx: number, opts: {
	golden: boolean?,
	tint: Color3?,
	dim: number?,
}?): GuiObject
	local o = opts or {}
	local icon = IconArchive.Image(parent, key, sizePx, { golden = o.golden })
	if icon:IsA("TextLabel") then
		local glyph = icon :: TextLabel
		glyph.TextColor3 = o.tint or theme.Colors.TextPrimary
		glyph.TextStrokeTransparency = 1
		if o.dim then
			glyph.TextTransparency = o.dim
		end
	else
		local image = icon :: ImageLabel
		if o.tint then
			image.ImageColor3 = o.tint
		end
		if o.dim then
			image.ImageTransparency = o.dim
		end
	end
	return icon
end

-- Dim an already-built icon IN PLACE (the "never remove, always dim" rule),
-- whichever of the two shapes the archive returned.
function GPStudioKit.DimIcon(icon: GuiObject, transparency: number)
	if icon:IsA("ImageLabel") then
		(icon :: ImageLabel).ImageTransparency = transparency
	elseif icon:IsA("TextLabel") then
		(icon :: TextLabel).TextTransparency = transparency
	end
end

function GPStudioKit.TintIcon(icon: GuiObject, color: Color3)
	if icon:IsA("ImageLabel") then
		(icon :: ImageLabel).ImageColor3 = color
	elseif icon:IsA("TextLabel") then
		(icon :: TextLabel).TextColor3 = color
	end
end

-- ========================================================================
-- Surfaces
-- ========================================================================

-- THE MATTE PLATE every dense block sits on: cream paper, a soft deepened-
-- tint hairline, the clay speckle, and petal corners alternating by index so
-- a stack of these reads hand-arranged rather than stamped.
--
-- `sink` is optional BECAUSE MOST CALLERS MUST NOT SHADOW. Pass a shadow
-- intent only for the handful of structural plates on a page; a shadow per
-- row is exactly how a data table becomes a sticker sheet.
function GPStudioKit.Paper(theme: Types.UITheme, parent: Instance, opts: {
	name: string?,
	index: number?,
	fill: Color3?,
	cornerKey: string?,
	speckle: boolean?,
	shadow: string?,
	stroke: boolean?,
	strokeTint: Color3?,
	strokeThickness: number?,
}?, sink: { any }?): Frame
	local o = opts or {}
	local fill = o.fill or theme.Studio.Card
	local plate = surface(o.name or "Paper", fill, 0)
	plate.Parent = parent
	if o.cornerKey then
		GPLayoutKit.CornerSet(theme, plate, o.cornerKey)
	else
		GPLayoutKit.Petal(theme, plate, o.index or 0)
	end
	if o.stroke ~= false then
		-- `strokeTint` is how SELECTION reads on a plate that must not cast a
		-- shadow: a deepened butter or rose ring instead of the arcade's gold
		-- one. The stroke is still derived, so it stays hue-matched.
		local stroke = GPLayoutKit.SoftStroke(theme, plate, o.strokeTint or fill)
		if o.strokeThickness then
			stroke.Thickness = o.strokeThickness
		end
		if o.strokeTint then
			stroke.Transparency = 0
		end
	end
	if o.speckle ~= false then
		local tokens = studio(theme)
		local grain = GPLayoutKit.Tile(
			theme,
			tokens.patternKey or "speckle",
			GPLayoutKit.Deepen(theme, fill, 1),
			tokens.speckleTransparency or 0.94,
			"ClayGrain"
		)
		-- Clone the plate's corner onto the grain so the speckle cannot square
		-- off a petal (the tile is a full-bleed 1×1 image with no corner of its
		-- own). Added FIRST, so later children draw over it at equal ZIndex.
		local corner = plate:FindFirstChildOfClass("UICorner")
		if corner then
			corner:Clone().Parent = grain
		end
		grain.ZIndex = plate.ZIndex
		grain.Parent = plate
	end
	if o.shadow then
		GPLayoutKit.Shadow(theme, plate, o.shadow, sink, fill)
	end
	return plate
end

-- A clipped scrolling viewport. ClipsDescendants is MANDATORY (content
-- leaking past its frame is a known past bug in this codebase) and the
-- padding is there so a plate's soft shadow is not sliced at the clip edge.
--
-- Nothing this kit builds rotates, so axis-aligned clipping is sufficient —
-- but note that GPLayoutKit.Scallop's Top/Left/Right strips DO rotate and
-- must never be placed inside one of these.
function GPStudioKit.Scroller(theme: Types.UITheme, parent: Instance, opts: {
	name: string?,
	direction: Enum.ScrollingDirection?,
	automatic: Enum.AutomaticSize?,
	thickness: number?,
	padPx: number?,
	padTopPx: number?,
}?): ScrollingFrame
	local o = opts or {}
	local pad = o.padPx or 10
	local direction = o.direction or Enum.ScrollingDirection.Y
	local automatic = o.automatic
	if automatic == nil then
		if direction == Enum.ScrollingDirection.X then
			automatic = Enum.AutomaticSize.X
		elseif direction == Enum.ScrollingDirection.XY then
			automatic = Enum.AutomaticSize.XY
		else
			automatic = Enum.AutomaticSize.Y
		end
	end

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = o.name or "GPScroll"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ClipsDescendants = true
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = automatic
	scroll.ScrollingDirection = direction
	scroll.ScrollBarThickness = o.thickness or 8
	-- A deepened rose thumb, never the arcade gold: the scrollbar is chrome and
	-- chrome belongs to the pack.
	scroll.ScrollBarImageColor3 = GPLayoutKit.Deepen(theme, theme.Colors.Primary, 1)
	scroll.ScrollBarImageTransparency = 0.25
	scroll.Parent = parent

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, o.padTopPx or pad)
	padding.PaddingBottom = UDim.new(0, pad)
	padding.PaddingLeft = UDim.new(0, pad)
	padding.PaddingRight = UDim.new(0, pad)
	padding.Parent = scroll
	return scroll
end

-- The studio dialect's SAGE HAIRLINE. GPLayoutKit.Divider tiles the pack's
-- squiggle at its authored 16px height — right between sections, far too loud
-- between rows — so this is the quiet 1px version for row separators.
function GPStudioKit.Rule(theme: Types.UITheme, parent: Instance, opts: {
	thickness: number?,
	transparency: number?,
	inset: number?,
	layoutOrder: number?,
}?): Frame
	local o = opts or {}
	local inset = o.inset or 0
	local rule = surface("Rule", ruleTint(theme), o.transparency or 0.25)
	rule.Size = UDim2.new(1, -inset * 2, 0, o.thickness or HAIRLINE)
	rule.Position = UDim2.fromOffset(inset, 0)
	if o.layoutOrder then
		rule.LayoutOrder = o.layoutOrder
	end
	UIStyler.Corner(theme.Radii.Pill).Parent = rule
	rule.Parent = parent
	return rule
end

-- ========================================================================
-- Text
-- ========================================================================

-- A display-face heading in ink. Copy is SoftCased, never uppercased.
function GPStudioKit.Heading(theme: Types.UITheme, parent: Instance, text: string, opts: {
	sizePx: number?,
	color: Color3?,
	heightPx: number?,
	layoutOrder: number?,
	name: string?,
}?): TextLabel
	local o = opts or {}
	local label = GPLayoutKit.Text(theme, o.sizePx or theme.TextSizes.Subtitle, o.color or theme.Colors.TextPrimary, o.name or "Heading")
	label.Text = GPStudioKit.SoftCase(text)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Size = UDim2.new(1, 0, 0, o.heightPx or 28)
	if o.layoutOrder then
		label.LayoutOrder = o.layoutOrder
	end
	label.Parent = parent
	return label
end

-- The quiet empty state. Warm and playful, never patronizing — the caller
-- supplies the sentence; this only paints it.
function GPStudioKit.Empty(theme: Types.UITheme, parent: Instance, text: string, heightPx: number?): TextLabel
	local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Empty")
	label.Text = text
	label.Size = UDim2.new(1, 0, 0, heightPx or 72)
	label.TextWrapped = true
	label.Parent = parent
	return label
end

-- ========================================================================
-- The value ruler
-- ========================================================================

export type Meter = {
	root: Frame,
	track: Frame,
	fill: Frame,
	name: TextLabel,
	readout: TextLabel,
	Set: (value: number, maxValue: number?, readoutText: string?) -> (),
	SetTone: (fill: Color3) -> (),
}

-- A standalone progress ruler for the places a full StatRow is the wrong
-- shape: a completion header, a reputation bar, a season XP bar, an RP bar.
--
-- IT ALWAYS PRINTS ITS NUMERALS. The arcade UIProgressBarComponent overlays
-- "value / max" on the bar and marks every ten per cent with a tick; both are
-- kept here, because a bar without its number is a picture of a number and
-- dropping it is precisely the reduction this pack's law 6 exists to stop.
-- The numerals ride the pack's tabular Numeric face in INK: the fill is rose
-- or butter, and TextOnPrimary (near-white) measures 2.14:1 on rose.
function GPStudioKit.Meter(theme: Types.UITheme, parent: Instance, opts: {
	value: number?,
	maxValue: number?,
	label: string?,
	tone: Color3?,
	heightPx: number?,
	sizeUDim: UDim2?,
	position: UDim2?,
	layoutOrder: number?,
	ticks: boolean?,
	name: string?,
}?): Meter
	local o = opts or {}
	local height = o.heightPx or METER_H
	local tone = o.tone or theme.Colors.Primary

	local root = surface(o.name or "Meter", theme.Colors.Background, 1)
	root.Size = o.sizeUDim or UDim2.new(1, 0, 0, height)
	if o.position then
		root.Position = o.position
	end
	if o.layoutOrder then
		root.LayoutOrder = o.layoutOrder
	end
	root.Parent = parent

	local trackFill = theme.Arcade.RulerTrack
	local track = surface("Track", trackFill, 0)
	track.Size = UDim2.fromScale(1, 1)
	track.ClipsDescendants = true
	track.Parent = root
	UIStyler.Corner(theme.Radii.Pill).Parent = track
	GPLayoutKit.SoftStroke(theme, track, trackFill)

	local fill = surface("Fill", tone, 0)
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = 2
	fill.Parent = track
	UIStyler.Corner(theme.Radii.Pill).Parent = fill

	-- The ruler's ten-per-cent marks, alternating tall/short, bottom-anchored
	-- and drawn OVER the fill so the markings read across filled and empty
	-- track alike. Sage, not the arcade's pale grey.
	if o.ticks ~= false then
		for k = 1, TICK_COUNT do
			local tick = surface("Tick", ruleTint(theme), 0.35)
			tick.AnchorPoint = Vector2.new(0.5, 1)
			tick.Position = UDim2.new(k / (TICK_COUNT + 1), 0, 1, 0)
			tick.Size = UDim2.fromOffset(1, if k % 2 == 1 then TICK_TALL else TICK_SHORT)
			tick.ZIndex = 3
			tick.Parent = track
		end
	end

	local name = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "Name")
	name.Text = o.label and GPStudioKit.SoftCase(o.label) or ""
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Size = UDim2.new(0.5, 0, 1, 0)
	name.Visible = o.label ~= nil and o.label ~= ""
	name.ZIndex = 4
	UIStyler.PaddingXY(10, 0).Parent = name
	name.Parent = track

	local readout = GPLayoutKit.NumberText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "Readout")
	readout.Size = UDim2.new(0.5, 0, 1, 0)
	readout.Position = UDim2.fromScale(0.5, 0)
	readout.ZIndex = 4
	UIStyler.PaddingXY(10, 0).Parent = readout
	readout.Parent = track

	local current = o.value or 0
	local maximum = o.maxValue or 100

	local function set(value: number, maxValue: number?, readoutText: string?)
		current = value
		if maxValue then
			maximum = maxValue
		end
		local ratio = if maximum > 0 then math.clamp(current / maximum, 0, 1) else 0
		fill.Size = UDim2.fromScale(ratio, 1)
		readout.Text = readoutText or string.format("%d / %d", math.floor(current + 0.5), math.floor(maximum + 0.5))
	end

	local function setTone(newFill: Color3)
		fill.BackgroundColor3 = newFill
	end

	set(current, maximum)
	return { root = root, track = track, fill = fill, name = name, readout = readout, Set = set, SetTone = setTone }
end

-- ========================================================================
-- Controls
-- ========================================================================

export type Button = {
	root: TextButton,
	chip: Frame,
	label: TextLabel,
	icon: ImageLabel,
	shadow: any,
	SetText: (text: string) -> (),
	SetTone: (fill: Color3) -> (),
	SetDimmed: (dimmed: boolean) -> (),
	SetIcon: (assetId: string?) -> (),
}

-- The improvised action button (GPLayoutKit ships no ActionButton). The
-- TextButton itself stays TRANSPARENT and the fill lives on a chip child,
-- because UIStyleEnforcer backstops any SOLID GuiButton with a BLACK 2px
-- stroke and that would violate law 1 on sight.
--
-- DIMMED IS NOT DISABLED: a dimmed button still fires its callback, so a tap
-- can answer with a toast explaining why nothing happened. That is the
-- codebase's own §11.1 rule and this pack has no reason to break it.
function GPStudioKit.Button(theme: Types.UITheme, parent: Instance, opts: {
	text: string,
	tone: Color3?,
	index: number?,
	sizeUDim: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	iconId: string?,
	dimmed: boolean?,
	textSize: number?,
	onClick: (() -> ())?,
}, sink: { any }?): Button
	local spacing = theme.Spacing
	local index = opts.index or 0
	local tone = opts.tone or theme.Colors.Primary

	local root = Instance.new("TextButton")
	root.Name = "GPButton"
	root.BackgroundTransparency = 1
	root.Text = ""
	root.AutoButtonColor = false
	root.Size = opts.sizeUDim or UDim2.new(1, 0, 0, BUTTON_H)
	if opts.position then
		root.Position = opts.position
	end
	if opts.anchorPoint then
		root.AnchorPoint = opts.anchorPoint
	end
	if opts.layoutOrder then
		root.LayoutOrder = opts.layoutOrder
	end
	root.Parent = parent

	local chip = surface("Chip", tone, 0)
	chip.Size = UDim2.fromScale(1, 1)
	chip.Parent = root
	GPLayoutKit.Petal(theme, chip, index)
	local stroke = GPLayoutKit.SoftStroke(theme, chip, tone)
	local shadow: any = GPLayoutKit.Shadow(theme, chip, "sm", sink, tone)

	local icon = Instance.new("ImageLabel")
	icon.Name = "Glyph"
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, spacing.M, 0.5, 0)
	icon.Size = UDim2.fromOffset(24, 24)
	icon.Visible = false
	icon.ZIndex = 3
	icon.Parent = chip

	-- Ink, not TextOnPrimary: this is button-sized body copy and near-white on
	-- an undeepened rose measures 2.14:1.
	local label = GPLayoutKit.BodyText(theme, opts.textSize or theme.TextSizes.Button, theme.Colors.TextPrimary, "Label")
	label.Text = GPStudioKit.SoftCase(opts.text)
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 3
	label.Parent = chip

	local function layOut()
		if icon.Visible then
			label.Position = UDim2.fromOffset(spacing.M + 24 + spacing.S, 0)
			label.Size = UDim2.new(1, -(spacing.M * 2 + 24 + spacing.S), 1, 0)
			label.TextXAlignment = Enum.TextXAlignment.Left
		else
			label.Position = UDim2.fromOffset(0, 0)
			label.Size = UDim2.fromScale(1, 1)
			label.TextXAlignment = Enum.TextXAlignment.Center
		end
	end

	local function setIcon(assetId: string?)
		if assetId and assetId ~= "" then
			icon.Image = assetId
			icon.Visible = true
		else
			icon.Visible = false
		end
		layOut()
	end

	local baseTone = tone
	local dimmed = false

	local function paint()
		local shownFill = if dimmed then baseTone:Lerp(theme.Colors.Disabled, 0.6) else baseTone
		chip.BackgroundColor3 = shownFill
		local deep = GPLayoutKit.Deepen(theme, shownFill, 1)
		stroke.Color = deep
		if shadow then
			-- The shadow retints with the fill: a rose button casts rose, a
			-- dimmed one casts the dimmed tint. Law 2, demonstrated in a state.
			shadow.Instance.Color = deep
		end
		label.TextColor3 = if dimmed then theme.Colors.TextSecondary else theme.Colors.TextPrimary
		icon.ImageTransparency = if dimmed then 0.45 else 0
	end

	local function setTone(newTone: Color3)
		baseTone = newTone
		paint()
	end

	local function setDimmed(value: boolean)
		dimmed = value
		paint()
	end

	local function setText(text: string)
		label.Text = GPStudioKit.SoftCase(text)
	end

	setIcon(opts.iconId)
	setDimmed(opts.dimmed == true)
	if opts.onClick then
		root.Activated:Connect(opts.onClick)
	end
	-- Animate LAST, after the final colours: it snapshots the rest colour.
	UIChrome.Animate(theme, root, chip)

	return {
		root = root,
		chip = chip,
		label = label,
		icon = icon,
		shadow = shadow,
		SetText = setText,
		SetTone = setTone,
		SetDimmed = setDimmed,
		SetIcon = setIcon,
	}
end

export type Chip = {
	root: Frame,
	label: TextLabel,
	icon: GuiObject?,
	SetTone: (fill: Color3) -> (),
	SetText: (text: string) -> (),
}

-- A small NON-INTERACTIVE state pill: a title's EQUIP / EQUIPPED / LOCKED
-- badge, a battle-pass tier number, the skill tree's points counter. A Frame
-- rather than a button on purpose — the whole row is usually the control, and
-- a nested button inside it would create a dead zone.
--
-- Shadow-free by default: these repeat per row and per column.
function GPStudioKit.Chip(theme: Types.UITheme, parent: Instance, opts: {
	text: string,
	tone: Color3?,
	textColor: Color3?,
	index: number?,
	iconKey: string?,
	iconPx: number?,
	golden: boolean?,
	sizeUDim: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	textSize: number?,
	pill: boolean?,
	name: string?,
}): Chip
	local spacing = theme.Spacing
	local tone = opts.tone or theme.Colors.Surface

	local root = surface(opts.name or "Chip", tone, 0)
	root.Size = opts.sizeUDim or UDim2.new(0, 132, 0, CHIP_H)
	if opts.position then
		root.Position = opts.position
	end
	if opts.anchorPoint then
		root.AnchorPoint = opts.anchorPoint
	end
	if opts.layoutOrder then
		root.LayoutOrder = opts.layoutOrder
	end
	root.Parent = parent
	if opts.pill then
		UIStyler.Corner(theme.Radii.Pill).Parent = root
	else
		GPLayoutKit.Petal(theme, root, opts.index or 0)
	end
	local stroke = GPLayoutKit.SoftStroke(theme, root, tone)

	local icon: GuiObject? = nil
	local textLeft = 0
	if opts.iconKey then
		local size = opts.iconPx or 22
		local built = GPStudioKit.Icon(theme, root, opts.iconKey, size, { golden = opts.golden })
		built.AnchorPoint = Vector2.new(0, 0.5)
		built.Position = UDim2.new(0, spacing.S, 0.5, 0)
		built.ZIndex = 3
		icon = built
		textLeft = spacing.S + size + spacing.XS
	end

	local label = GPLayoutKit.BodyText(theme, opts.textSize or theme.TextSizes.Body, opts.textColor or theme.Colors.TextPrimary, "Label")
	label.Text = GPStudioKit.SoftCase(opts.text)
	label.Position = UDim2.fromOffset(textLeft, 0)
	label.Size = UDim2.new(1, -(textLeft + (if icon then spacing.S else 0)), 1, 0)
	label.TextXAlignment = if icon then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.ZIndex = 3
	label.Parent = root

	local function setTone(fill: Color3)
		root.BackgroundColor3 = fill
		stroke.Color = GPLayoutKit.Deepen(theme, fill, 1)
	end

	local function setText(text: string)
		label.Text = GPStudioKit.SoftCase(text)
	end

	return { root = root, label = label, icon = icon, SetTone = setTone, SetText = setText }
end

-- ========================================================================
-- The dense row — GPLayoutKit.StatRow at full density
-- ========================================================================

-- Grow the kit's fixed value column LEFTWARD by `extra` px and pull every
-- column left of it in by the same amount. The kit's ladder is authored for
-- short numerals; a H:MM:SS duration or a comma-grouped reputation total
-- needs more room, and TRUNCATING A NUMBER IS A PRECISION LOSS. Widening is
-- not. Every column keeps its right-flush alignment because the whole ladder
-- is measured from the right edge.
local function widenValue(row: any, extra: number)
	if extra <= 0 then
		return
	end
	local shift = UDim2.fromOffset(extra, 0)
	row.capsule.Position -= shift
	row.capsule.Size += shift
	row.delta.Position -= shift
	row.label.Size -= shift
end

-- GPLayoutKit.StatRow with the two things these screens need and the kit
-- cannot know: a LEADING ICON (every one of these pages labels its rows with
-- one) and a VERBATIM value string.
--
-- `valueText` is printed over the kit's own numeric format. That is the whole
-- anti-condescension guarantee for this port: StatsScreen formats durations
-- as H:MM:SS, counts as 1.2K/3.4M and rates as 49.3%, and re-deriving those
-- from the studio dialect's one-decimal float would quietly destroy them. The
-- bar underneath still shows magnitude against maxValue, so the row GAINS a
-- reading rather than losing one.
function GPStudioKit.StatLine(theme: Types.UITheme, parent: Instance, opts: {
	label: string,
	value: number?,
	maxValue: number?,
	valueText: string?,
	unit: string?,
	precision: number?,
	invertGoodness: boolean?,
	accent: Color3?,
	heightPx: number?,
	layoutOrder: number?,
	iconKey: string?,
	iconPx: number?,
	golden: boolean?,
	dim: number?,
	widenPx: number?,
	labelColor: Color3?,
	valueColor: Color3?,
}): any
	-- Explicitly `any`: the icon is attached to the returned record below, and
	-- the kit's StatRow type has no field for it.
	local row: any = GPLayoutKit.StatRow(theme, parent, {
		label = GPStudioKit.SoftCase(opts.label),
		value = opts.value,
		maxValue = opts.maxValue,
		unit = opts.unit,
		precision = opts.precision,
		invertGoodness = opts.invertGoodness,
		accent = opts.accent,
		heightPx = opts.heightPx,
		layoutOrder = opts.layoutOrder,
	})
	widenValue(row, opts.widenPx or 0)

	if opts.iconKey then
		local size = opts.iconPx or 20
		local textH = row.label.Size.Y.Offset
		local icon = GPStudioKit.Icon(theme, row.root, opts.iconKey, size, {
			golden = opts.golden,
			dim = opts.dim,
		})
		icon.AnchorPoint = Vector2.new(0, 0)
		icon.Position = UDim2.fromOffset(0, math.max(0, (textH - size) // 2))
		local gap = size + theme.Spacing.S
		row.label.Position = UDim2.fromOffset(gap, 0)
		row.label.Size -= UDim2.fromOffset(gap, 0)
		row.icon = icon
	end

	if opts.valueText then
		row.value.Text = opts.valueText
	end
	if opts.labelColor then
		row.label.TextColor3 = opts.labelColor
	end
	if opts.valueColor then
		row.value.TextColor3 = opts.valueColor
	end
	return row
end

-- ========================================================================
-- Teardown
-- ========================================================================

-- Convenience passthrough so a screen's _OnTeardown only has to know about
-- one kit. A destroyed GuiObject alone leaves the shadow budget counter high.
function GPStudioKit.ReleaseShadows(sink: { any }?)
	GPLayoutKit.ReleaseShadows(sink)
end

return GPStudioKit
