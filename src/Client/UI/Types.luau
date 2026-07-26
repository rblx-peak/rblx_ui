--!strict
-- Schemas for the client UI system: theme tokens, layout packs, component
-- props and per-screen data shapes. Pure types — no runtime logic.

-- ========================================================================
-- Theme tokens
-- ========================================================================

export type UIThemeColors = {
	Primary: Color3,
	Secondary: Color3,
	Accent: Color3,
	Background: Color3,
	Surface: Color3,
	SurfaceRaised: Color3,
	Success: Color3,
	Warning: Color3,
	Error: Color3,
	TextPrimary: Color3,
	TextSecondary: Color3,
	TextOnPrimary: Color3,
	Stroke: Color3,
	Overlay: Color3,
	Disabled: Color3,
}

export type UIThemeFonts = {
	Title: Font,
	Subtitle: Font,
	Body: Font,
	Button: Font,
	Numeric: Font,
}

export type UIThemeTextSizes = {
	Title: number,
	Subtitle: number,
	Body: number,
	Button: number,
	Small: number,
}

export type UIThemeRadii = {
	Small: number,
	Medium: number,
	Large: number,
	-- Oversized on purpose: UICorner clamps it to a full pill/circle.
	Pill: number,
}

export type UIThemeSpacing = {
	XS: number,
	S: number,
	M: number,
	L: number,
	XL: number,
}

export type UIThemeAnimations = {
	Appear: TweenInfo,
	Disappear: TweenInfo,
	Hover: TweenInfo,
	Press: TweenInfo,
	-- Value changes, attention pulses, toggle knobs, bar fills.
	Emphasis: TweenInfo,
	-- Used for every property tween during a live theme swap.
	ThemeSwap: TweenInfo,
}

export type UIThemeEffects = {
	UseGradients: boolean,
	GradientIntensity: number, -- 0..1
	ShadowTransparency: number, -- 0..1 (1 = shadow invisible)
	HoverScale: number,
	PressScale: number,
	StrokeThickness: number,
}

-- Optional tiled surface texture (e.g. a Roblox "studs" image) layered over the
-- flat fill of panels and cards, under the content. OPTIONAL on a theme so
-- themes that omit it render flat exactly as before.
export type UIThemeTexture = {
	Image: string, -- "rbxassetid://..."
	TileSize: number, -- px size of one repeated tile (ScaleType = Tile)
	Tint: Color3, -- ImageColor3 applied to the texture
	Transparency: number, -- 0..1 (1 = texture invisible, so it reads as subtle grain)
}

-- Optional glyph/element outline: the "chunky Roblox" bold dark line around text
-- (and small elements like slider/toggle knobs). Applied via a Contextual
-- UIStroke so it outlines a label's text but a frame's border. OPTIONAL — themes
-- that omit it get no outline, exactly as before.
export type UIThemeTextOutline = {
	Color: Color3,
	Thickness: number,
	Transparency: number, -- 0..1 (0 = solid outline)
}

-- Shape: the "feel" of surfaces independent of colour/font. Decides how round
-- things are and whether buttons/cards read as Flat, Bubbly (pill-round, springy)
-- or Raised3D (bevel + drop shadow that depresses on press). OPTIONAL on a theme
-- so older theme files keep working; ThemeShape.Resolve fills in Flat defaults.
export type UIThemeShapeStyle = "Flat" | "Bubbly" | "Raised3D"

export type UIThemeShape = {
	-- Multiplies every corner radius. 1 = as-authored, >1 rounder, <1 boxier.
	-- Bubbly styles push this high; the styler still clamps to a full pill.
	RoundnessScale: number,
	Style: UIThemeShapeStyle,
	-- Raised3D: how many px the bevel/shadow drops the surface, and how bright the
	-- top highlight / how dark the bottom shade read (0..1). Ignored by Flat.
	Depth: number,
	HighlightTransparency: number, -- 0..1, top inner-bevel brightness
	ShadowStrength: number, -- 0..1, bottom drop-shadow darkness (1 = strongest)
	-- Bubbly: extra hover/press springiness added on top of Effects scales.
	Bounce: number,
}

-- ========================================================================
-- Pottery Clash families (see UI_DESIGN_DOCUMENT.md — the base spec)
--
-- The UI has two deliberate colour families plus world-space grammar:
--   Arcade  — loud game-show HUD chrome (menus, shop, modals, HUD)
--   Studio  — quiet ceramic-workshop surfaces (the "workbench" screens)
-- Which family a surface belongs to decides its corner/stroke POLICY too
-- (hard 0px + 3px black vs the soft 16px ladder + tan hairlines) — that
-- policy lives in UIChrome, these are only the colour tokens.
-- ========================================================================

export type UIFamily = "Arcade" | "Studio" | "World"

export type UIThemeArcade = {
	Panel: Color3, -- dark slate chrome (currency pills, progress bg)
	Row: Color3, -- card/row background
	RowTransparency: number, -- rows usually sit at 8% transparency
	NearBlack: Color3, -- icon boxes, odds panels
	NearBlack2: Color3, -- rules card, viewport wells
	HeaderRed: Color3, -- modal header bars
	Red: Color3, -- close buttons, danger
	Green: Color3, -- buy / claim / equip / positive; Cash text
	Blue: Color3, -- tabs, secondary actions, Bux-priced buttons
	Gold: Color3, -- rewards, countdowns, top-3 rows, selection
	Magenta: Color3, -- Robux-priced buttons (always)
	Orange: Color3, -- daily-reward button
	GreyOwned: Color3, -- OWNED disabled fill
	GreyClaimed: Color3, -- CLAIMED disabled fill
	IceBlue: Color3, -- shard counts, secondary notes
	SunburstGold: Color3, -- sunburst tints, rulers, amber status lines
	MoneyGreen: Color3, -- world-space money/positive (nameplates, OWNED tags)
	RulerTrack: Color3, -- near-black ruler/progress track
	RulerTick: Color3, -- 1px ruler ticks (rendered at 0.35 transparency)
	ShopAccents: { Color3 }, -- shop card accent rotation (red/yellow/blue/purple)
	Rainbow: { Color3 }, -- 5-stop rainbow gradient (STARTER PACK / GRAND PRIZE)
}

export type UIThemeStudio = {
	Panel: Color3, -- dark-chocolate surface (floating panels)
	PanelTransparency: number, -- panels render at 6% transparency
	PanelSoft: Color3, -- raised chocolate — buttons resting on a panel
	PanelDeep: Color3, -- recessed chocolate — rails, wells, tracks, bubbles
	Card: Color3, -- cream surface (dark text on it)
	CardSoft: Color3, -- pressed / secondary cream
	Tan: Color3, -- warm tan — hairline strokes, active pill fill
	Accent: Color3, -- honey — selection rings, slider fills, "on" state
	Gold: Color3, -- currency / reward text
	TextLight: Color3, -- ink on dark panels
	TextDark: Color3, -- ink on cream/tan
	TextMuted: Color3, -- secondary ink on dark panels
	Back: Color3, -- terracotta — go back / destructive / close
	Next: Color3, -- sage — advance / confirm
	WarnBg: Color3, -- warning banner surface
	WarnText: Color3, -- warning banner ink
}

-- Semantic colour rules (doc §3.3) — colour IS meaning, no exceptions.
export type UIThemeSemantic = {
	-- Currency is colour-coded everywhere: keyed by CurrencyId ("Cash", "Bux",
	-- "Robux"); price buttons/text always use these.
	Currency: { [string]: Color3 },
	Selection: Color3, -- honey/gold: "selected / active / valuable"
	Seat1: Color3, -- duel seat 1 (blue) — names + win pips
	Seat2: Color3, -- duel seat 2 (red)
	VSRose: Color3, -- VS-screen left accent
	VSSky: Color3, -- VS-screen right accent
	CursorHover: Color3, -- hover-clay green
	CursorPush: Color3, -- push-in blue
	CursorPull: Color3, -- pull-out orange
	CursorHollow: Color3, -- hollow teal
}

-- The motion kit (doc §5.1) — all springs, no fades. Things pop in and
-- hard-hide out. Every button gets colour+scale feedback only.
export type UIThemeMotion = {
	HoverIn: TweenInfo, -- 0.12s Back Out
	HoverOut: TweenInfo, -- 0.15s Quad Out
	PressIn: TweenInfo, -- 0.07s Quad Out
	PopIn: TweenInfo, -- 0.24s Back Out (entrance)
	PulseUp: TweenInfo, -- 0.09s Quad Out
	PulseSettle: TweenInfo, -- 0.22s Back Out
	HoverScale: number, -- 1.05
	HoverFillLerp: number, -- fill lerps 12% toward white on hover
	PressScale: number, -- 0.93 squash
	PopFromScale: number, -- entrance starts at 0.82
	PulseScale: number, -- 1.14 "chosen!" spike
	-- Big-button juice (rail buttons, feature cells) — applied to the ART child.
	BigHover: TweenInfo, -- 0.18s Back Out
	BigHoverScale: number, -- 1.12
	BigHoverTilt: number, -- degrees of tilt on hover
	BigPressScale: number, -- 0.82 squash
	BigRelease: TweenInfo, -- 0.34s Elastic Out overshoot return
}

-- Per-STYLE chrome policy overrides. nil = the Roblox Classic behaviour
-- (3px black strokes, black text outlines, arcade bevel + glass). A style
-- like Armored Core sets this to swap the whole chrome language — hairline
-- accent strokes, text GLOW instead of outline, no bevel — without touching
-- UIChrome's call sites. This is the schema slot that makes styles more than
-- palettes.
export type UIThemeChrome = {
	StrokeThickness: number, -- 1 = hairline
	StrokeFollowsAccent: boolean, -- true: strokes tint from Colors.Accent, not black
	StrokeTransparency: number, -- resting frame transparency (selection is always 0)
	TextOutline: boolean, -- false: no black TextStroke; glow instead
	TextGlowTransparency: number, -- Contextual UIStroke glow strength (≈0.75)
	Bevel: boolean, -- arcade white→grey button bevel
	Glass: boolean, -- top-lit glass sheen on panels
	HardCorners: boolean?, -- true: 90° corners EVERYWHERE (both families), pills excepted
}

-- Native UIShadow token (verified rendering 2026-07: hard offset drops AND
-- zero-offset glows). Replaces the obsolete "image asset + transparency"
-- shadow premise; UIChrome.Shadow/Glow realize these, budget-counted.
export type UIThemeEffect = {
	Blur: UDim, -- Scale = % of parent's shortest dimension
	Offset: UDim2, -- zero for glows
	Spread: UDim2, -- engine takes UDim2 here (probed), not a bare number
	ColorToken: string?, -- Colors.* key; nil = explicit Color below
	Color: Color3?,
	Transparency: number,
}

-- Per-corner radius token: {tl, tr, bl, br}. A theme may set the uniform
-- Radii.* OR a Corners table per intent — SheetBuilder refuses rules mixing
-- CornerRadius with per-corner keys (documented-undefined engine behavior).
export type UIThemeCornerSet = {
	TopLeft: number,
	TopRight: number,
	BottomLeft: number,
	BottomRight: number,
}

export type UITheme = {
	Id: string,
	DisplayName: string,
	Colors: UIThemeColors,
	Fonts: UIThemeFonts,
	TextSizes: UIThemeTextSizes,
	Radii: UIThemeRadii,
	Spacing: UIThemeSpacing,
	Animations: UIThemeAnimations,
	Effects: UIThemeEffects,
	-- The Pottery Clash family palettes + semantics + motion kit. Required on
	-- every theme — adapted components read these instead of the legacy groups.
	Arcade: UIThemeArcade,
	Studio: UIThemeStudio,
	Semantic: UIThemeSemantic,
	Motion: UIThemeMotion,
	-- Optional; ThemeShape.Resolve(theme) returns a full shape with Flat defaults
	-- when a theme omits this, so every theme is shape-safe without editing it.
	Shape: UIThemeShape?,
	-- Optional; a tiled "studs"-style texture over panel/card fills. nil = flat.
	Texture: UIThemeTexture?,
	-- Optional; a bold outline around text glyphs + knob borders. nil = no outline.
	-- The Pottery base leaves this nil: the black text outline is enforced
	-- engine-wide by UIStyleEnforcer (TextStroke properties) per the spec.
	TextOutline: UIThemeTextOutline?,
	-- Optional per-style chrome policy; nil = Roblox Classic chrome.
	Chrome: UIThemeChrome?,
	-- Optional LAYOUT language. nil/"Arcade" = the classic modal-card anatomy.
	-- "AC" = full-bleed terminal pages: thin top status bar, hairline frames,
	-- corner brackets, dense mono list rows, footer key hints. Screens branch
	-- their _BuildContent on this (they rebuild on style change), and
	-- UIChrome.ModalCard swaps its whole anatomy accordingly.
	LayoutKit: string?,
	-- Optional native-effect token groups (UIShadow-backed; see UIThemeEffect).
	EffectShadows: { sm: UIThemeEffect, md: UIThemeEffect, lg: UIThemeEffect }?,
	EffectGlows: { sm: UIThemeEffect, md: UIThemeEffect, lg: UIThemeEffect, pulse: UIThemeEffect }?,
	-- Optional dialect token sub-namespaces (pack-defined, e.g. comic/tech),
	-- bridged to sheet attributes as dialect_<name>_<key>.
	DialectTokens: { [string]: { [string]: any } }?,
	-- Optional declarative StyleRule definitions consumed by SheetBuilder
	-- (native UI Styling; inert until the engine activates application).
	StyleRules: { any }?,
	-- Optional: exclusive-panel switches route through the SlashTransition
	-- diagonal wipe (E8). Packs without the flag pay nothing.
	ScreenWipe: boolean?,
}

-- ========================================================================
-- Layout packs
-- ========================================================================

export type UIPackShop = {
	-- How entries flow in the scroll frame.
	Container: "Grid" | "List",
	Columns: number,
	CardHeight: number,
	-- EntryLayoutConfig spec id — decides the per-card focal/arrangement.
	EntryLayout: string,
	ShowCategoryBar: boolean,
}

export type Region = "TopLeft" | "TopCenter" | "TopRight" | "BottomLeft" | "BottomCenter" | "BottomRight"

export type UIPackHUD = {
	Compact: boolean,
	ShowObjectives: boolean,
	Scale: number,
	-- Where the currency chips sit, and which side their icon is on. Moving
	-- these per pack is what gives each pack a different "feel".
	MoneyRegion: Region,
	MoneyIconSide: "Left" | "Right",
	-- Optional per-element region overrides (elementId -> region). Lets a pack —
	-- or runtime code via GameHUDScreen:SetElementRegion — move ANY HUD element
	-- (timer, level, health, a skills bar, ...) anywhere, not just the money.
	Regions: { [string]: Region }?,
}

export type UIPackNav = {
	Side: "Left" | "Right",
	Vertical: "Top" | "Center" | "Bottom",
}

export type UIPackTutorial = {
	ShowStepList: boolean,
}

export type UIPackModal = {
	WidthScale: number,
}

export type UIPack = {
	Id: string,
	DisplayName: string,
	Shop: UIPackShop,
	HUD: UIPackHUD,
	Nav: UIPackNav,
	Tutorial: UIPackTutorial,
	Modal: UIPackModal,
}

-- ========================================================================
-- Components
-- ========================================================================

export type UIComponentProps = {
	id: string?,
	text: string?,
	textKey: string?,
	icon: string?, -- emoji placeholder
	iconId: string?, -- rbxassetid:// image
	variant: string?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	enabled: boolean?,
	onClick: ((...any) -> ())?,
	tags: { string }?,
	[string]: any,
}

-- ========================================================================
-- Screen data
-- ========================================================================

export type ToastData = {
	text: string?,
	textKey: string?,
	variant: ("Info" | "Success" | "Error" | "Warning")?,
	duration: number?,
	icon: string?,
}

export type ModalData = {
	kind: ("Info" | "Confirm" | "Danger")?,
	title: string?,
	titleKey: string?,
	body: string?,
	bodyKey: string?,
	confirmKey: string?,
	cancelKey: string?,
	onConfirm: (() -> ())?,
	onCancel: (() -> ())?,
}

export type ObjectiveData = {
	id: string,
	text: string?,
	textKey: string?,
	done: boolean?,
}

export type HUDElementFormat = "Number" | "Time" | "Bar"

export type HUDElement = {
	id: string,
	format: HUDElementFormat,
	region: string,
	order: number,
	labelKey: string?,
	icon: string?,
	maxValue: number?,
	colorToken: string?,
}

export type HUDScreenData = {
	values: { [string]: number }?,
	objectives: { ObjectiveData }?,
}

export type ShopScreenData = {
	categoryId: string?,
	balances: { [string]: number }?,
}

export type TutorialStep = {
	id: string,
	titleKey: string?,
	textKey: string,
	highlightTargetId: string?,
	hintKeys: { string }?,
	-- Optional per-step highlight styling (see UIHighlightComponent) — falls
	-- back to its own defaults (RoundedSquare, no arrow) when omitted.
	highlightShape: ("Circle" | "Square" | "RoundedSquare")?,
	highlightArrowDirection: ("Up" | "Down" | "Left" | "Right")?,
}

export type TutorialScreenData = {
	steps: { TutorialStep }?,
	onComplete: ((completed: boolean) -> ())?,
}

local Types = {}

return Types
