--!strict
-- ARMORED CORE — the second STYLE: the tactical, data-dense, monospaced
-- machine-overlay language of Armored Core VI's mission HUD and ASSEMBLY
-- screens. A laser-projected readout that does not care about your comfort:
-- information density over breathing room, numbers over icons, snap over
-- ease. Stock accent is Teal; the Amber treatment ships as a colour preset.
--
-- What makes this a STYLE and not a palette:
--   * Chrome policy (Types.UIThemeChrome): hairline accent strokes @ 0.4,
--     text GLOW instead of the black outline, no bevel, no glass.
--   * Monospaced FontFaces throughout (RobotoMono — numerals align in
--     columns, which is the whole point; ShareTechMono does not exist in
--     the Roblox catalog, RobotoMono is the correct available family).
--   * Snap motion: nothing over 0.2s, Quad Out only, no springy Back/Elastic.
--
-- Semantic colour LAW still holds (currency coding, success/error), and the
-- required legacy groups are mapped so every existing component renders
-- coherently under this style without edits.

local Types = require(script.Parent.Parent.Types)

local ACCENT = Color3.fromRGB(0, 200, 255) -- Teal (stock)
local TEXT = Color3.fromRGB(235, 240, 240)
local TEXT_DIM = Color3.fromRGB(140, 148, 150)

local function mono(weight: Enum.FontWeight): Font
	return Font.fromName("RobotoMono", weight)
end

local ArmoredCoreTheme: Types.UITheme = {
	Id = "ArmoredCore",
	DisplayName = "Armored Core",

	Colors = {
		Primary = ACCENT,
		Secondary = Color3.fromRGB(255, 170, 0), -- amber (alt accent slot)
		Accent = ACCENT,
		Background = Color3.fromRGB(8, 8, 10), -- void
		Surface = Color3.fromRGB(15, 15, 15), -- panel backing
		SurfaceRaised = Color3.fromRGB(20, 20, 22), -- data wells, list rows
		Success = Color3.fromRGB(120, 255, 160), -- positive deltas
		Warning = Color3.fromRGB(255, 210, 60), -- over-limit approach
		Error = Color3.fromRGB(255, 0, 0), -- AP LOW / ACS OVERLOAD
		TextPrimary = TEXT, -- values
		TextSecondary = TEXT_DIM, -- labels
		TextOnPrimary = Color3.fromRGB(8, 8, 10), -- ink on an accent fill
		Stroke = ACCENT, -- framing follows the accent in this style
		Overlay = Color3.new(0, 0, 0),
		Disabled = Color3.fromRGB(70, 74, 76), -- empty slots
	},

	-- Monospace everywhere; weight carries emphasis (Light labels, Regular
	-- values, Medium headers). GothamMedium survives nowhere in this style.
	Fonts = {
		Title = mono(Enum.FontWeight.Medium),
		Subtitle = mono(Enum.FontWeight.Regular),
		Body = mono(Enum.FontWeight.Light),
		Button = mono(Enum.FontWeight.Regular),
		Numeric = mono(Enum.FontWeight.Regular),
	},

	-- Small and dense (AC spec: body 11–13, labels 10). Legacy consumers get
	-- readable-but-tight sizes.
	TextSizes = {
		Title = 18,
		Subtitle = 13,
		Body = 12,
		Button = 13,
		Small = 10,
	},

	-- Zero rounded corners — and no notches faked with UICorner either; the
	-- notched-panel silhouette is a 9-slice component concern.
	Radii = {
		Small = 0,
		Medium = 0,
		Large = 0,
		Pill = 1000, -- knobs/pips only
	},

	Spacing = {
		XS = 2,
		S = 4,
		M = 8,
		L = 12,
		XL = 16,
	},

	-- Snap, don't glide: instant/fast/normal = 0 / 0.06 / 0.12; the rare
	-- tween is Quad Out; nothing over 0.2s anywhere in this table.
	Animations = {
		Appear = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		Disappear = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		Hover = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		Press = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		Emphasis = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		ThemeSwap = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	},

	Effects = {
		UseGradients = false,
		GradientIntensity = 0,
		ShadowTransparency = 1,
		HoverScale = 1.0, -- machines don't bounce; focus is a stroke, not a pop
		PressScale = 0.985,
		StrokeThickness = 1,
	},

	-- Legacy Arcade slots mapped onto the AC monochrome so every existing
	-- component (cards, pills, dock, headers) renders coherently here.
	Arcade = {
		Panel = Color3.fromRGB(15, 15, 15),
		Row = Color3.fromRGB(20, 20, 22),
		RowTransparency = 0.7,
		NearBlack = Color3.fromRGB(8, 8, 10),
		NearBlack2 = Color3.fromRGB(12, 12, 14),
		HeaderRed = Color3.fromRGB(16, 34, 42), -- accent-tinted header band
		Red = Color3.fromRGB(60, 24, 24), -- close/danger chrome, muted machine red
		Green = Color3.fromRGB(64, 190, 84), -- currency LAW (Cash)
		Blue = Color3.fromRGB(58, 130, 240), -- currency LAW (Bux)
		Gold = ACCENT, -- "valuable/selected" rides the accent here
		Magenta = Color3.fromRGB(225, 70, 235), -- currency LAW (Robux)
		Orange = Color3.fromRGB(255, 170, 0),
		GreyOwned = Color3.fromRGB(46, 50, 52),
		GreyClaimed = Color3.fromRGB(38, 42, 44),
		IceBlue = TEXT_DIM, -- secondary notes = dim mono ink
		SunburstGold = ACCENT,
		RulerTrack = Color3.fromRGB(14, 16, 18),
		RulerTick = Color3.fromRGB(235, 240, 240),
		ShopAccents = {
			ACCENT,
			Color3.fromRGB(255, 170, 0),
			Color3.fromRGB(120, 255, 160),
			Color3.fromRGB(255, 210, 60),
		},
		Rainbow = {
			Color3.fromRGB(0, 200, 255),
			Color3.fromRGB(120, 255, 160),
			Color3.fromRGB(255, 210, 60),
			Color3.fromRGB(255, 170, 0),
			Color3.fromRGB(255, 0, 0),
		},
	},

	-- The workbench family barely appears in this style; keep it as darkened
	-- steel so any studio surface still reads.
	Studio = {
		Panel = Color3.fromRGB(14, 14, 16),
		PanelTransparency = 0.08,
		PanelSoft = Color3.fromRGB(22, 22, 26),
		PanelDeep = Color3.fromRGB(10, 10, 12),
		Card = Color3.fromRGB(210, 216, 218),
		CardSoft = Color3.fromRGB(180, 186, 188),
		Tan = TEXT_DIM,
		Accent = ACCENT,
		Gold = ACCENT,
		TextLight = TEXT,
		TextDark = Color3.fromRGB(8, 8, 10),
		TextMuted = TEXT_DIM,
		Back = Color3.fromRGB(120, 40, 40),
		Next = Color3.fromRGB(40, 120, 90),
		WarnBg = Color3.fromRGB(80, 24, 20),
		WarnText = Color3.fromRGB(255, 220, 210),
	},

	Semantic = {
		Currency = {
			Cash = Color3.fromRGB(64, 190, 84),
			Bux = Color3.fromRGB(58, 130, 240),
			Robux = Color3.fromRGB(225, 70, 235),
		},
		Selection = ACCENT,
		Seat1 = ACCENT,
		Seat2 = Color3.fromRGB(255, 170, 0),
		VSRose = Color3.fromRGB(255, 96, 96),
		VSSky = ACCENT,
		CursorHover = ACCENT,
		CursorPush = Color3.fromRGB(120, 190, 255),
		CursorPull = Color3.fromRGB(255, 148, 82),
		CursorHollow = Color3.fromRGB(120, 235, 205),
	},

	-- Snap kit: same slots, machine timings. No Back/Elastic anywhere.
	Motion = {
		HoverIn = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		HoverOut = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		PressIn = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		PopIn = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		PulseUp = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		PulseSettle = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		HoverScale = 1.0,
		HoverFillLerp = 0.06,
		PressScale = 0.985,
		PopFromScale = 0.97,
		PulseScale = 1.03,
		BigHover = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		BigHoverScale = 1.02,
		BigHoverTilt = 0,
		BigPressScale = 0.97,
		BigRelease = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	},

	Shape = {
		RoundnessScale = 1,
		Style = "Flat",
		Depth = 0,
		HighlightTransparency = 1,
		ShadowStrength = 0,
		Bounce = 0,
	},

	-- The LAYOUT language: not just chrome — whole-screen anatomy. Terminal
	-- pages, corner brackets, left rails, dense rows, footer hints.
	LayoutKit = "AC",

	-- THE style switch: hairline accent framing, glow-not-outline, no bevel,
	-- no glass (UIChrome + the enforcer consult this).
	Chrome = {
		StrokeThickness = 1,
		StrokeFollowsAccent = true,
		StrokeTransparency = 0.4,
		TextOutline = false,
		TextGlowTransparency = 0.75,
		Bevel = false,
		Glass = false,
		HardCorners = true, -- the Studio 16px ladder flattens too; machines are square
	},
}

return ArmoredCoreTheme
