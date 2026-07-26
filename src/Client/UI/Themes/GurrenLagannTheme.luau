--!strict
-- GURREN LAGANN — the third STYLE: hot-blooded super-robot manga. Cel-flat
-- fills, thick black comic ink, cream paper text, blazing orange-red heat,
-- gold where value lives, everything slightly too loud on purpose. Never
-- static: this pack pairs with the Life Pass modules (SlamText, SpiralGauge,
-- CutIn, CurrencyFlight, DrawCeremony, SlashTransition).
--
-- DUAL DIALECT, settled as style tags (Style/Tags):
--   * DialectComic — paper-and-ink hype chrome: sticker shadows (hard
--     offset, near-opaque — native UIShadow, verified rendering), gold heat
--     glows on value, halftone drift (Luau ticker).
--   * DialectTech — phosphor terminal: green-on-black CRT bloom (zero-offset
--     UIShadow glow), used for gunmen readouts and "serious mode".
--   Panel roots wear the tag; rules select .UIPanel.DialectComic. Packs
--   without dialects never apply the tags and pay nothing.
--
-- Geometry law: NO rounding (HardCorners; chamfers are cut, not rounded)
-- and NO skew transform exists in Roblox — slants come from rotated-clipped
-- frames or angular 9-slice art (see GLAngularButton + the ASSET SPEC).
--
-- Fonts: Bangers (comic display shout) and Jura (tech mono-ish body) from
-- the Roblox catalog, constructed via Font.fromName with graceful render
-- fallback if a family is missing on some platform.

local Types = require(script.Parent.Parent.Types)

local INK = Color3.fromRGB(24, 12, 8) -- comic ink (near-black warm)
local PAPER = Color3.fromRGB(255, 244, 224) -- cream paper
local HEAT = Color3.fromRGB(255, 84, 32) -- blazing orange-red
local GOLD = Color3.fromRGB(255, 196, 32)
local PHOSPHOR = Color3.fromRGB(90, 255, 140)

local function face(family: string, weight: Enum.FontWeight, style: Enum.FontStyle?): Font
	local ok, font = pcall(function()
		return Font.new("rbxasset://fonts/families/" .. family .. ".json", weight, style or Enum.FontStyle.Normal)
	end)
	if ok then
		return font
	end
	return Font.fromEnum(Enum.Font.FredokaOne)
end

-- Display type LEANS: the reference's headline type is heavy and italic
-- ("CRAZY HUNDRED DRAWS", "700%+"). Italic is requested on the FontFace; a
-- family without a true italic face renders upright rather than erroring,
-- which is why the pack also carries the whole-element tilt language.
local function display(family: string, weight: Enum.FontWeight): Font
	return face(family, weight, Enum.FontStyle.Italic)
end

local GurrenLagannTheme: Types.UITheme = {
	Id = "GurrenLagann",
	DisplayName = "Gurren Lagann",

	Colors = {
		Primary = HEAT,
		Secondary = GOLD,
		Accent = HEAT,
		-- Reference palette is CHARCOAL, not brown: near-black plates so the
		-- heat red and gold read as light sources against them.
		Background = Color3.fromRGB(16, 13, 15), -- scorched void
		Surface = Color3.fromRGB(30, 25, 28), -- panel cel
		SurfaceRaised = Color3.fromRGB(44, 36, 40), -- rows / cards
		Success = Color3.fromRGB(110, 225, 120),
		Warning = Color3.fromRGB(255, 210, 60),
		Error = Color3.fromRGB(255, 44, 66),
		TextPrimary = PAPER,
		TextSecondary = Color3.fromRGB(222, 176, 144),
		TextOnPrimary = PAPER,
		Stroke = INK, -- comic ink outlines everywhere
		Overlay = Color3.new(0, 0, 0),
		Disabled = Color3.fromRGB(96, 72, 62),
	},

	-- Bangers shouts the display text; Jura keeps values/机-tech legible.
	Fonts = {
		Title = display("Bangers", Enum.FontWeight.Regular),
		Subtitle = display("Bangers", Enum.FontWeight.Regular),
		Body = face("Jura", Enum.FontWeight.Medium),
		Button = display("Bangers", Enum.FontWeight.Regular),
		Numeric = face("Jura", Enum.FontWeight.Bold),
	},

	TextSizes = {
		Title = 36, -- comic display runs LOUD
		Subtitle = 22,
		Body = 18,
		Button = 24,
		Small = 13,
	},

	-- Chamfers are cut, not rounded: zero radii, pills stay geometric circles.
	Radii = {
		Small = 0,
		Medium = 0,
		Large = 0,
		Pill = 1000,
	},

	Spacing = {
		XS = 4,
		S = 8,
		M = 12,
		L = 18,
		XL = 28,
	},

	-- Punchy: fast Back-eased overshoot everywhere; nothing glides politely.
	Animations = {
		Appear = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		Disappear = TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		Hover = TweenInfo.new(0.08, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		Press = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		Emphasis = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		ThemeSwap = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	},

	Effects = {
		UseGradients = false, -- cel shading: flat fills, no sheens
		GradientIntensity = 0,
		ShadowTransparency = 0.15,
		HoverScale = 1.06,
		PressScale = 0.92,
		StrokeThickness = 3,
	},

	Arcade = {
		Panel = Color3.fromRGB(30, 25, 28),
		Row = Color3.fromRGB(44, 36, 40),
		RowTransparency = 0.1,
		NearBlack = Color3.fromRGB(18, 15, 17),
		NearBlack2 = Color3.fromRGB(26, 21, 24),
		HeaderRed = Color3.fromRGB(196, 44, 24), -- banner red header bands
		Red = Color3.fromRGB(226, 56, 34), -- close X / danger chrome
		Green = Color3.fromRGB(64, 190, 84), -- currency LAW (Cash)
		MoneyGreen = Color3.fromRGB(64, 190, 84), -- world-space money/positive (required Arcade token)
		Blue = Color3.fromRGB(58, 130, 240), -- currency LAW (Bux)
		Gold = GOLD,
		Magenta = Color3.fromRGB(225, 70, 235), -- currency LAW (Robux)
		Orange = HEAT,
		GreyOwned = Color3.fromRGB(92, 66, 54),
		GreyClaimed = Color3.fromRGB(74, 54, 46),
		IceBlue = Color3.fromRGB(255, 214, 170), -- "secondary note" = warm paper
		SunburstGold = GOLD,
		RulerTrack = Color3.fromRGB(40, 20, 14),
		RulerTick = PAPER,
		ShopAccents = {
			HEAT,
			GOLD,
			Color3.fromRGB(255, 140, 48),
			Color3.fromRGB(255, 210, 60),
		},
		Rainbow = {
			Color3.fromRGB(255, 44, 66),
			HEAT,
			Color3.fromRGB(255, 160, 40),
			GOLD,
			PAPER,
		},
	},

	Studio = {
		Panel = Color3.fromRGB(42, 22, 16),
		PanelTransparency = 0.04,
		PanelSoft = Color3.fromRGB(64, 32, 24),
		PanelDeep = Color3.fromRGB(30, 16, 12),
		Card = PAPER,
		CardSoft = Color3.fromRGB(238, 218, 190),
		Tan = Color3.fromRGB(222, 176, 144),
		Accent = HEAT,
		Gold = GOLD,
		TextLight = PAPER,
		-- PACK LAW: no text FILL is ever black — black exists only as the
		-- outline stroke. Ink-on-light surfaces use this deep heat-brown.
		TextDark = Color3.fromRGB(72, 26, 18),
		TextMuted = Color3.fromRGB(190, 150, 122),
		Back = Color3.fromRGB(150, 44, 34),
		Next = Color3.fromRGB(60, 150, 84),
		WarnBg = Color3.fromRGB(110, 30, 22),
		WarnText = Color3.fromRGB(255, 226, 200),
	},

	Semantic = {
		Currency = {
			Cash = Color3.fromRGB(64, 190, 84),
			Bux = Color3.fromRGB(58, 130, 240),
			Robux = Color3.fromRGB(225, 70, 235),
		},
		Selection = GOLD,
		Seat1 = HEAT,
		Seat2 = Color3.fromRGB(58, 130, 240),
		VSRose = Color3.fromRGB(255, 96, 96),
		VSSky = Color3.fromRGB(96, 180, 255),
		CursorHover = GOLD,
		CursorPush = HEAT,
		CursorPull = Color3.fromRGB(255, 160, 40),
		CursorHollow = PAPER,
	},

	-- The stamp kit: overshoot in, squash on press, tilt on the big cells.
	Motion = {
		HoverIn = TweenInfo.new(0.08, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		HoverOut = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		PressIn = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		PopIn = TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		PulseUp = TweenInfo.new(0.07, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		PulseSettle = TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		HoverScale = 1.06,
		HoverFillLerp = 0.1,
		PressScale = 0.92,
		PopFromScale = 0.7, -- stamps SLAM in from small
		PulseScale = 1.18,
		BigHover = TweenInfo.new(0.09, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		BigHoverScale = 1.1,
		BigHoverTilt = -2, -- the whole-element tilt (no skew exists; tilt sells it)
		BigPressScale = 0.88,
		BigRelease = TweenInfo.new(0.18, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
	},

	Shape = {
		RoundnessScale = 0,
		Style = "Flat",
		Depth = 0,
		HighlightTransparency = 1,
		ShadowStrength = 0.85,
		Bounce = 0.4,
	},

	-- Exclusive panel switches wear the E8 diagonal slash-wipe.
	ScreenWipe = true,

	-- GL LAYOUT language: screens with a _BuildGLLayout branch compose along
	-- the pack's diagonal (slanted banners, trapezoid tabs, tilted chips);
	-- screens without one keep the classic anatomy in GL chrome.
	LayoutKit = "GL",

	-- PROCEDURAL CHROME ASSETS — generated + uploaded 2026-07-26 (SDF
	-- rasterizer, monochrome-on-transparent: black ink survives any tint,
	-- white fill takes ImageColor3). Slice rects are per the generator.
	Assets = {
		halftone = { image = "rbxassetid://107321838338900", tile = 128 },
		actionLines = { image = "rbxassetid://109419217423398", tile = 256 },
		edgeTorn = { image = "rbxassetid://113171142852777", tileX = 256, height = 32 },
		-- v2: white-fill variants. v1 shipped transparent-fill + black border,
		-- which ImageColor3 cannot fill (tint multiplies: black stays black,
		-- transparent stays transparent) — the banner rendered as a bare
		-- outline. Fill must be WHITE for a one-image tintable shape.
		panelSlantL = { image = "rbxassetid://83790588165231", slice = Rect.new(32, 8, 64, 88) },
		panelSlantR = { image = "rbxassetid://81518849678221", slice = Rect.new(32, 8, 64, 88) },
		chipPaper = { image = "rbxassetid://84491777878728", slice = Rect.new(12, 12, 44, 34) },
		tabTrapezoid = { image = "rbxassetid://100649383769633", slice = Rect.new(18, 8, 78, 54) },
		bannerSlash = { image = "rbxassetid://111270937853863", slice = Rect.new(30, 10, 240, 86) },
		bannerSlashInner = { image = "rbxassetid://75991618484550", slice = Rect.new(30, 10, 240, 86) },
		-- 26px chamfered card plate: the 10px chip nick vanished at card scale,
		-- so cards get their own pronounced cut-corner silhouette.
		cardCut = { image = "rbxassetid://92497649078929", slice = Rect.new(34, 34, 94, 94) },
		-- ART SLOT (spec 3.3): item/character/promo illustration cannot be
		-- generated procedurally, so the layout ships a correctly-shaped,
		-- hatched, visibly-intentional placeholder well instead of borrowing
		-- another game's icon style.
		-- v2 border-only: v1's interior hatch was smeared into long diagonal
		-- streaks by 9-slice center stretching. Texture = the tiled halftone.
		artSlot = { image = "rbxassetid://123732146013435", slice = Rect.new(30, 30, 98, 98) },
		starBurst = { image = "rbxassetid://128217810184608" },
		hexTile = { image = "rbxassetid://89451013451410", tile = 128 },
		scanline = { image = "rbxassetid://108326105362595", tile = 4 },
	},

	-- Comic ink chrome: THICK black strokes, black text outlines (this is
	-- the one styled pack where the classic outline rule is the aesthetic),
	-- zero bevel/glass (cel shading), hard corners everywhere.
	Chrome = {
		StrokeThickness = 3,
		StrokeFollowsAccent = false, -- ink is BLACK, never accent
		StrokeTransparency = 0,
		TextOutline = true,
		TextGlowTransparency = 0.75,
		Bevel = false,
		Glass = false,
		HardCorners = true,
	},

	-- NATIVE EFFECT TOKENS (UIShadow-backed, verified rendering).
	-- The sticker shadow: manga "cut paper stacked on paper" — hard, dark,
	-- offset along the pack's slant direction (see DialectTokens.comic).
	EffectShadows = {
		sm = { Blur = UDim.new(0, 2), Offset = UDim2.fromOffset(4, 4), Spread = UDim2.new(), Color = Color3.new(0, 0, 0), Transparency = 0.2 },
		md = { Blur = UDim.new(0, 3), Offset = UDim2.fromOffset(6, 6), Spread = UDim2.new(), Color = Color3.new(0, 0, 0), Transparency = 0.15 },
		lg = { Blur = UDim.new(0, 4), Offset = UDim2.fromOffset(8, 8), Spread = UDim2.new(), Color = Color3.new(0, 0, 0), Transparency = 0.12 },
	},
	-- Gold heat for value; pulse drives COMBINATION READY / GIGA states.
	EffectGlows = {
		sm = { Blur = UDim.new(0, 10), Offset = UDim2.new(), Spread = UDim2.new(), Color = GOLD, Transparency = 0.55 },
		md = { Blur = UDim.new(0, 18), Offset = UDim2.new(), Spread = UDim2.new(), Color = GOLD, Transparency = 0.35 },
		lg = { Blur = UDim.new(0, 30), Offset = UDim2.new(), Spread = UDim2.new(), Color = Color3.fromRGB(255, 240, 210), Transparency = 0.2 },
		pulse = { Blur = UDim.new(0, 22), Offset = UDim2.new(), Spread = UDim2.new(), Color = GOLD, Transparency = 0.3 },
	},

	-- Dialect sub-namespaces (bridged as dialect_comic_* / dialect_tech_*).
	DialectTokens = {
		comic = {
			ink = INK,
			paper = PAPER,
			shadowSlantX = 6, -- sticker-shadow offset follows the slant angle
			shadowSlantY = 6,
			slantDeg = -4, -- whole-element tilt used where art allows
			halftoneDrift = 8, -- px/s of halftone texture drift (Luau ticker)
			slashAngleDeg = 14, -- SlashTransition seam tilt (whole-element rotation; no skew exists)
			-- GLAngularButton ambient numbers (additive; Luau-ticker side):
			idleDriftPx = 1.5, -- ± sticker float amplitude, px
			idleDriftHz = 0.25, -- one lazy drift circle every 4 s
			tiltEasePerSec = 12, -- pointer-parallax rotation smoothing rate
			-- GLSlamText (comic word-slam engine) rhythm + punch (additive):
			slamPerWordSeconds = 0.12, -- beat between word landings
			slamPopScale = 1.15, -- landed-word spike, settles via Motion.PulseSettle
			slamShakePx = 2, -- landing shake amplitude px (framework cap 6)
			slamShakeSeconds = 0.15, -- shake decay time (framework cap 0.4s)
			slamCjkRunGraphemes = 6, -- a boundary-less run longer than this...
			slamCjkStepGraphemes = 2, -- ...slams every 2 graphemes instead
			-- GLSpiralGauge (SPIRAL POWER meter) feel (additive; ticker side):
			spiralPointerBaseDps = 240, -- pointer °/s at full charge (framework cap: 360)
			spiralOverspinSeconds = 0.45, -- overcharge burst decay
			spiralLerpRate = 9, -- 1/s exponential display chase on the ticker
			spiralMaxedText = "COMBINATION READY!",
			-- GLCutIn (speedline cut-in banner) choreography (additive):
			cutinStripeCount = 10, -- 8..12 speedline stripes (frames, not images)
			cutinStripeScrollPxPerSec = 520,
			cutinStripeBrightTransparency = 0.45,
			cutinStripeDarkTransparency = 0.62,
			cutinSlideSeconds = 0.2,
			cutinOutSeconds = 0.14,
			cutinHoldNormal = 0.8,
			cutinHoldRare = 1.15,
			cutinHoldGiga = 1.9,
			cutinBandHeightPx = 150,
			cutinGigaBandScale = 0.46, -- takeover band height, fraction of screen
			cutinBackdropTransparency = 0.35,
			cutinGigaTextScale = 1.6, -- multiplies TextSizes.Title for the takeover callout
		},
		tech = {
			phosphor = PHOSPHOR,
			bg = Color3.fromRGB(6, 16, 10),
			panel = Color3.fromRGB(10, 24, 15),
			grid = Color3.fromRGB(28, 58, 38),
			bloomTransparency = 0.7, -- phosphor CRT bloom (glow.sm variant)
		},
		-- Life Pass flight kit (Framework/CurrencyFlight): GL coins fly FAST
		-- on wide comic arcs — chunky pips, greedy homing. Packs without this
		-- namespace get the module's quieter house defaults.
		flight = {
			particleSize = 16, -- px diameter of a coin pip (comic = chunky)
			duration = 0.48, -- s origin -> counter
			durationJitter = 0.14,
			stagger = 0.03, -- s between launches
			spread = 160, -- px bezier control-point fan (wide arcs)
			pulseMinInterval = 0.09, -- s between counter pops during a burst
		},
		-- Draw ceremony (Screens/DrawCeremonyScreen) choreography numbers +
		-- rarity palette. ADDITIVE: the screen carries per-key fallbacks so
		-- other packs still play a plainer ceremony without this namespace.
		ceremony = {
			rarityCommon = Color3.fromRGB(222, 176, 144), -- warm tan: "fine"
			rarityRare = GOLD, -- gold where value lives
			rarityGiga = HEAT, -- blazing heat for the top pull
			slamFromScale = 2.4, -- drill ticket slams in from LARGE
			insertTime = 0.6, -- s, stage 1
			spinUpTime = 1.05, -- s, stage 2
			spinMaxDegPerSec = 1080, -- dial pointer terminal velocity
			slashDeg = 12, -- slash-wipe seam angle (whole-element Rotation)
			slashCloseTime = 0.22, -- s, panels close
			slashHoldTime = 0.12, -- s, held shut on the slash line
			slashOpenTime = 0.28, -- s, panels open onto the reveals
			revealBeat = 0.55, -- s between full card reveals
			quickBeat = 0.3, -- s between lesser rare/giga pops on a 10-pull
			batchBeat = 0.45, -- the ONE beat every common shares on a 10-pull
			cutInSmallTime = 0.5, -- s, rare drive-by band
			cutInGigaTime = 0.85, -- s, giga announcement band
			slamShakePx = 6, -- framework cap: never above 6
			slamShakeDecay = 0.35, -- framework cap: decay under 0.4s
			pulseHz = 1.2, -- giga glow breath (under the 3 flashes/s cap)
			pulseDepth = 0.25, -- transparency swing of that breath
			batchThreshold = 6, -- pulls at/over this count reveal batch-style
		},
	},

	-- DECLARATIVE RULES for native styling (SheetBuilder). Authored now,
	-- inert until the engine activates application (Style/Capabilities);
	-- the imperative chrome renders the same look meanwhile — these are the
	-- same tokens, expressed twice on purpose during the bridge era.
	StyleRules = {
		{ selector = ".UIPanel", props = { BackgroundColor3 = "$color_surface" } },
		{ selector = ".UIListRow", props = { BackgroundColor3 = "$color_surfaceRaised" } },
		{ selector = ".UIPanel.DialectComic::UIShadow", props = { BlurRadius = UDim.new(0, 3), Offset = UDim2.fromOffset(6, 6), Color = Color3.new(0, 0, 0), Transparency = 0.15 } },
		{ selector = ".UIChip.DialectComic::UIShadow", props = { BlurRadius = UDim.new(0, 2), Offset = UDim2.fromOffset(4, 4), Color = Color3.new(0, 0, 0), Transparency = 0.2 } },
		{ selector = ".UIPanel.DialectTech", band = "Dialect", props = { BackgroundColor3 = "$dialect_tech_panel" } },
		{ selector = ".UIPanel.DialectTech::UIShadow", band = "Dialect", props = { BlurRadius = UDim.new(0, 10), Offset = UDim2.new(), Color = PHOSPHOR, Transparency = 0.7 } },
		{
			selector = ".UIButton:Hover",
			band = "State",
			props = { BackgroundColor3 = "$color_primary" },
			transitions = { BackgroundColor3 = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) },
		},
		{
			selector = ".UIButton:Press",
			band = "State",
			props = { BackgroundColor3 = "$arcade_headerRed" },
			transitions = { BackgroundColor3 = TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) },
		},
		{ selector = ".UIChip.UIFeatured::UIShadow", band = "State", props = { BlurRadius = UDim.new(0, 18), Offset = UDim2.new(), Color = GOLD, Transparency = 0.35 } },
		{ selector = ".UISlot.UISelected::UIStroke", band = "State", props = { Color = GOLD, Thickness = 4 } },
		{ selector = ".UIButton.UIDisabled", band = "State", props = { BackgroundColor3 = "$color_disabled" } },
		{ selector = ".UIValue.UIDanger", band = "State", props = { TextColor3 = "$color_error" } },
	} :: { any }, -- heterogeneous rule literals; the schema field is { any }?
}

return GurrenLagannTheme
