--!strict
-- THE base theme: "Pottery Clash" — a chunky arcade cartoon riding on top of a
-- warm ceramic studio (see UI_DESIGN_DOCUMENT.md; every value below is the real
-- shipped value from that spec — colours as exact RGB, timings as real TweenInfos).
--
-- Two families live side by side:
--   * Arcade  — near-black slate panels, saturated primary accents, FredokaOne
--     with full black outlines, hard 90° corners + thick black strokes.
--   * Studio  — dark-chocolate panels, cream cards, honey-gold accents, soft
--     16px corners, hairline tan strokes, muted body font.
-- Corner/stroke POLICY is enforced by UIChrome (family helpers) and
-- UIStyleEnforcer, not here — this file is purely the token set (doc §12).
--
-- The legacy generic groups (Colors/Fonts/TextSizes/…) are retuned to the
-- Arcade family so older call sites render on-spec without edits; adapted
-- code reads theme.Arcade / theme.Studio / theme.Semantic / theme.Motion.

local Types = require(script.Parent.Parent.Types)

local DefaultTheme: Types.UITheme = {
	Id = "Default",
	-- The base STYLE. Styles are hand-built looks (chrome, shape policy,
	-- motion); colour comes from ColorPresetConfig palettes layered on top.
	DisplayName = "Roblox Classic",

	-- Legacy generic tokens, mapped onto the Arcade HUD palette (doc §3.2).
	Colors = {
		Primary = Color3.fromRGB(58, 130, 240), -- blue: tabs / secondary actions
		Secondary = Color3.fromRGB(225, 70, 235), -- magenta: Robux-priced
		Accent = Color3.fromRGB(245, 190, 55), -- gold: rewards / selection
		Background = Color3.fromRGB(18, 22, 28), -- near-black
		Surface = Color3.fromRGB(38, 44, 54), -- dark slate chrome
		SurfaceRaised = Color3.fromRGB(52, 60, 74), -- card/row background
		Success = Color3.fromRGB(64, 190, 84), -- green: buy / claim / positive
		Warning = Color3.fromRGB(235, 130, 40), -- orange
		Error = Color3.fromRGB(224, 64, 64), -- red: close / danger
		-- White display text everywhere; the enforced black text outline is
		-- what lets it sit over 3D scenes and busy panels (doc §2).
		TextPrimary = Color3.fromRGB(255, 255, 255),
		TextSecondary = Color3.fromRGB(150, 220, 255), -- ice blue: secondary notes
		TextOnPrimary = Color3.fromRGB(255, 255, 255),
		Stroke = Color3.fromRGB(0, 0, 0), -- every border is a black stroke
		Overlay = Color3.fromRGB(0, 0, 0), -- modal dim (callers use 0.45)
		Disabled = Color3.fromRGB(90, 96, 108), -- OWNED grey
	},

	-- Doc §2: FredokaOne is the display font for 99% of text; GothamMedium is
	-- the quiet body font; GothamBold exists only for cursor chevrons.
	Fonts = {
		Title = Font.fromEnum(Enum.Font.FredokaOne),
		Subtitle = Font.fromEnum(Enum.Font.FredokaOne),
		Body = Font.fromEnum(Enum.Font.GothamMedium),
		Button = Font.fromEnum(Enum.Font.FredokaOne),
		Numeric = Font.fromEnum(Enum.Font.FredokaOne),
	},

	-- From the doc's fixed type scale: 34 panel titles / big buttons,
	-- 26–30 buttons + currency values, 20–24 labels/rows, 17–19 captions.
	TextSizes = {
		Title = 34,
		Subtitle = 22,
		Body = 20,
		Button = 26,
		Small = 17,
	},

	-- HARD ARCADE ruleset: zero rounded corners (doc §4.1). Pill stays maximal
	-- for the few true pills (phase pills, knobs — Studio-family surfaces).
	Radii = {
		Small = 0,
		Medium = 0,
		Large = 0,
		Pill = 1000,
	},

	Spacing = {
		XS = 4,
		S = 8,
		M = 14,
		L = 20,
		XL = 28,
	},

	-- Legacy tween slots mapped onto the §5.1 motion kit so unadapted call
	-- sites (Appear/Hover/Press) already move on-spec.
	Animations = {
		Appear = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), -- POP_IN
		Disappear = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), -- hard-hide fast
		Hover = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), -- HOVER_IN
		Press = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), -- PRESS_IN
		Emphasis = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		ThemeSwap = TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
	},

	Effects = {
		UseGradients = true,
		-- 0.45 makes UIStyler.Gradient bottom out at RGB(140,140,140) — the
		-- exact arcade button bevel (white → 140 vertical multiply, doc §4.1).
		GradientIntensity = 0.45,
		ShadowTransparency = 1, -- no drop shadows in the arcade language
		HoverScale = 1.05,
		PressScale = 0.93,
		StrokeThickness = 3, -- every border: 3px black
	},

	-- ==================================================================
	-- Arcade HUD palette (doc §3.2)
	-- ==================================================================
	Arcade = {
		Panel = Color3.fromRGB(38, 44, 54), -- #262C36
		Row = Color3.fromRGB(52, 60, 74), -- #343C4A
		RowTransparency = 0.08,
		NearBlack = Color3.fromRGB(18, 22, 28), -- #12161C
		NearBlack2 = Color3.fromRGB(24, 26, 34), -- #181A22
		HeaderRed = Color3.fromRGB(235, 45, 30), -- #EB2D1E
		Red = Color3.fromRGB(224, 64, 64), -- #E04040
		Green = Color3.fromRGB(64, 190, 84), -- #40BE54
		Blue = Color3.fromRGB(58, 130, 240), -- #3A82F0
		Gold = Color3.fromRGB(245, 190, 55), -- #F5BE37
		Magenta = Color3.fromRGB(225, 70, 235), -- #E146EB
		Orange = Color3.fromRGB(235, 130, 40), -- #EB8228
		GreyOwned = Color3.fromRGB(90, 96, 108), -- #5A606C
		GreyClaimed = Color3.fromRGB(80, 86, 98), -- #505662
		IceBlue = Color3.fromRGB(150, 220, 255), -- #96DCFF
		SunburstGold = Color3.fromRGB(255, 200, 60), -- #FFC83C
		MoneyGreen = Color3.fromRGB(90, 235, 120), -- #5AEB78
		RulerTrack = Color3.fromRGB(16, 20, 28), -- #10141C
		RulerTick = Color3.fromRGB(235, 238, 250), -- #EBEEFA (@ 0.35)
		-- Shop card accents rotate through red · yellow · blue · purple.
		ShopAccents = {
			Color3.fromRGB(240, 70, 70), -- #F04646
			Color3.fromRGB(245, 205, 55), -- #F5CD37
			Color3.fromRGB(70, 150, 255), -- #4696FF
			Color3.fromRGB(190, 110, 255), -- #BE6EFF
		},
		-- Rainbow gradient (STARTER PACK headline, GRAND PRIZE sign),
		-- offset-scrolled at 0.45 cycles/sec (UIChrome.ScrollGradient).
		Rainbow = {
			Color3.fromRGB(255, 90, 90),
			Color3.fromRGB(255, 210, 70),
			Color3.fromRGB(90, 230, 120),
			Color3.fromRGB(80, 180, 255),
			Color3.fromRGB(200, 120, 255),
		},
	},

	-- ==================================================================
	-- Ceramic studio palette (doc §3.1)
	-- ==================================================================
	Studio = {
		Panel = Color3.fromRGB(58, 42, 31), -- #3A2A1F dark chocolate
		PanelTransparency = 0.06,
		PanelSoft = Color3.fromRGB(76, 56, 42), -- #4C382A raised
		PanelDeep = Color3.fromRGB(43, 31, 23), -- #2B1F17 recessed
		Card = Color3.fromRGB(238, 223, 200), -- #EEDFC8 cream
		CardSoft = Color3.fromRGB(224, 203, 172), -- #E0CBAC pressed cream
		Tan = Color3.fromRGB(197, 160, 120), -- #C5A078
		Accent = Color3.fromRGB(233, 170, 99), -- #E9AA63 honey
		Gold = Color3.fromRGB(244, 199, 91), -- #F4C75B
		TextLight = Color3.fromRGB(245, 233, 215), -- #F5E9D7
		TextDark = Color3.fromRGB(72, 51, 36), -- #483324
		TextMuted = Color3.fromRGB(186, 163, 138), -- #BAA38A
		Back = Color3.fromRGB(184, 92, 68), -- #B85C44 terracotta
		Next = Color3.fromRGB(135, 158, 96), -- #879E60 sage
		WarnBg = Color3.fromRGB(140, 58, 44), -- #8C3A2C
		WarnText = Color3.fromRGB(255, 232, 222), -- #FFE8DE
	},

	-- ==================================================================
	-- Semantic colour rules (doc §3.3) — colour IS meaning.
	-- ==================================================================
	Semantic = {
		Currency = {
			Cash = Color3.fromRGB(64, 190, 84), -- green, everywhere
			Bux = Color3.fromRGB(58, 130, 240), -- blue, everywhere
			Robux = Color3.fromRGB(225, 70, 235), -- magenta, always
		},
		Selection = Color3.fromRGB(245, 190, 55), -- gold = selected/active/valuable
		Seat1 = Color3.fromRGB(90, 175, 255),
		Seat2 = Color3.fromRGB(255, 110, 90),
		VSRose = Color3.fromRGB(233, 110, 120),
		VSSky = Color3.fromRGB(110, 170, 233),
		CursorHover = Color3.fromRGB(96, 226, 118), -- hover-clay green
		CursorPush = Color3.fromRGB(120, 190, 255), -- push-in blue
		CursorPull = Color3.fromRGB(255, 148, 82), -- pull-out orange
		CursorHollow = Color3.fromRGB(120, 235, 205), -- hollow teal
	},

	-- ==================================================================
	-- Motion kit (doc §5.1 / §5.2) — the exact shipped TweenInfos.
	-- ==================================================================
	Motion = {
		HoverIn = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		HoverOut = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		PressIn = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		PopIn = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		PulseUp = TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		PulseSettle = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		HoverScale = 1.05,
		HoverFillLerp = 0.12,
		PressScale = 0.93,
		PopFromScale = 0.82,
		PulseScale = 1.14,
		BigHover = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		BigHoverScale = 1.12,
		BigHoverTilt = 30,
		BigPressScale = 0.82,
		BigRelease = TweenInfo.new(0.34, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
	},

	-- Flat, hard-cornered; radii are already 0 (arcade) so no scaling.
	Shape = {
		RoundnessScale = 1,
		Style = "Flat",
		Depth = 0,
		HighlightTransparency = 1,
		ShadowStrength = 0,
		Bounce = 0,
	},

	-- No Texture and no TextOutline token: the spec's black text outline is
	-- enforced engine-wide by UIStyleEnforcer (TextStroke properties on every
	-- text object), so the per-label ThemeOutline mechanism stays off.
}

return DefaultTheme
