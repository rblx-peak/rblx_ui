--!strict
-- GIRLY POP — StrawberryMatcha. Cutesy pastel ceramics for Pottery Battles:
-- warm cream base, rose and matcha as twin colour masses, butter gold on
-- value, everything soft-edged and hue-shadowed.
--
-- THE INVERSION (this pack is the schema's hardest test):
--   * Every prior pack FORBIDS UICorner. This one is built on it — radii run
--     8/16/24 plus PER-CORNER petal sets (Types.UITheme.Corners, emitted by
--     UIChrome.CornerSet). That field and emitter did not exist; adding them
--     was a framework fix, not a pack workaround (see PRIOR PACK IMPACT).
--   * GL uses UIShadow as a HARD sticker offset. This pack uses the same
--     token namespace for SOFT, HUE-MATCHED shadows and zero-offset glows.
--     A pink element casts a pink shadow — never grey. That single rule
--     carries more of the aesthetic than any other.
--
-- DIALECTS (tags, same mechanism as GL):
--   * DialectGlaze  — glossy: gradient fills, specular sheen arc, sparkle.
--   * DialectStudio — matte: cream paper, clay speckle, sage hairlines.
--   The split keeps data-dense screens legible while celebration screens go
--   maximalist. §0.3 LAW: the matte dialect carries the SAME stat density as
--   the Armored Core assembly screen. Cute is not simple.
--
-- CONTRAST CORRECTIONS (measured, not assumed — WCAG 2.1):
--   The spec's own pairing text.onRose (near-white) on surface.rose measured
--   2.14:1, far under the 4.5:1 body minimum; on matcha it measured 1.72:1.
--   Near-white cannot sit on these pastels. Corrections applied here:
--     - Body text on rose/matcha uses TextPrimary (plum-brown): 5.15:1 and
--       6.39:1 respectively. Both pass.
--     - TextOnPrimary (near-white) is retained ONLY for large display text
--       on rose.deep (3.24:1, clears the 3:1 large-text bar) — never body.
--     - TextSecondary darkened 140,115,122 -> 132,107,114 to clear 4.5:1 on
--       cream (was 4.04:1).
--   No pure black and no pure white appear anywhere in the pack.

local Types = require(script.Parent.Parent.Types)

-- ---- palette -----------------------------------------------------------

local CREAM = Color3.fromRGB(252, 246, 240) -- app base, warm off-white
local BLUSH = Color3.fromRGB(250, 232, 236) -- secondary surface / wells
local ROSE = Color3.fromRGB(255, 138, 175) -- primary pink
local ROSE_DEEP = Color3.fromRGB(232, 90, 140) -- pressed / shadow tint
local MATCHA = Color3.fromRGB(168, 205, 145) -- secondary green
local MATCHA_DEEP = Color3.fromRGB(122, 165, 105)
local BUTTER = Color3.fromRGB(255, 214, 122) -- stars, currency
local TERRACOTTA = Color3.fromRGB(214, 130, 100) -- clay / unfired
local INK = Color3.fromRGB(74, 52, 60) -- warm plum-brown, NEVER black
local INK_SOFT = Color3.fromRGB(132, 107, 114) -- corrected for 4.5:1 on cream
local ON_ROSE = Color3.fromRGB(255, 250, 250) -- large display text only
local DANGER = Color3.fromRGB(235, 90, 95) -- soft coral, not fire-engine
local POSITIVE = Color3.fromRGB(120, 200, 150)
local WARNING = Color3.fromRGB(250, 190, 100)

-- Glaze rarity ramp: cream -> sage -> sky -> lavender -> rose-gold.
local RARITY = {
	Color3.fromRGB(245, 238, 228),
	Color3.fromRGB(186, 214, 178),
	Color3.fromRGB(168, 205, 232),
	Color3.fromRGB(198, 178, 232),
	Color3.fromRGB(240, 178, 150),
}

local function face(family: string, weight: Enum.FontWeight): Font
	local ok, font = pcall(function()
		return Font.new("rbxasset://fonts/families/" .. family .. ".json", weight, Enum.FontStyle.Normal)
	end)
	if ok then
		return font
	end
	return Font.fromEnum(Enum.Font.FredokaOne)
end

local GirlyPopTheme: Types.UITheme = {
	Id = "GirlyPop",
	DisplayName = "Girly Pop",

	Colors = {
		Primary = ROSE,
		Secondary = MATCHA,
		Accent = BUTTER,
		Background = CREAM,
		Surface = BLUSH,
		SurfaceRaised = Color3.fromRGB(255, 241, 244),
		Success = POSITIVE,
		Warning = WARNING,
		Error = DANGER,
		TextPrimary = INK,
		TextSecondary = INK_SOFT,
		-- Reads on rose.deep at display sizes only; body copy on any pastel
		-- surface uses TextPrimary (see the contrast note in the header).
		TextOnPrimary = ON_ROSE,
		Stroke = ROSE_DEEP, -- strokes are a deepened tint of the fill, never black
		Overlay = Color3.fromRGB(74, 52, 60), -- warm scrim, not pure black
		Disabled = Color3.fromRGB(214, 200, 204),
	},

	-- Display: FredokaOne (rounded, chunky). Body: Nunito with real weights —
	-- rounded humanist, legible small. No italics, no condensed, no all-caps
	-- body: shouting at this audience is the §8 failure mode.
	Fonts = {
		Title = face("FredokaOne", Enum.FontWeight.Regular),
		Subtitle = face("Nunito", Enum.FontWeight.Bold),
		Body = face("Nunito", Enum.FontWeight.Medium),
		Button = face("Nunito", Enum.FontWeight.Bold),
		-- Numerals ride the body face at SemiBold so stat columns stay
		-- tabular — this is a stats game and numbers must line up.
		Numeric = face("Nunito", Enum.FontWeight.SemiBold),
	},

	-- Generous, per §1.2. Nothing is shrunk to make room for decoration.
	TextSizes = {
		Title = 30,
		Subtitle = 20,
		Body = 16,
		Button = 17,
		Small = 13,
	},

	Radii = {
		Small = 8,
		Medium = 16,
		Large = 24,
		Pill = 999,
	},

	-- THE SIGNATURE SHAPE. Per-corner sets consumed via UIChrome.CornerSet;
	-- alternate Petal/PetalMirror across a grid so rows read hand-arranged
	-- rather than stamped. Requires the Types.UITheme.Corners field added
	-- for this pack — the schema had the TYPE but no carrier or emitter.
	Corners = {
		Petal = { TopLeft = 24, TopRight = 8, BottomLeft = 8, BottomRight = 24 },
		PetalMirror = { TopLeft = 8, TopRight = 24, BottomLeft = 24, BottomRight = 8 },
		Leaf = { TopLeft = 26, TopRight = 4, BottomLeft = 26, BottomRight = 4 },
		Tab = { TopLeft = 16, TopRight = 16, BottomLeft = 0, BottomRight = 0 },
	},

	Spacing = {
		XS = 4,
		S = 8,
		M = 14,
		L = 20,
		XL = 32,
	},

	-- Bouncy, with a CAP: sustained elastic wobble reads as broken, not
	-- playful, so overshoot is tokenized and bounded (Motion.PulseScale).
	Animations = {
		Appear = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		Disappear = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		Hover = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		Press = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		Emphasis = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		ThemeSwap = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	},

	Effects = {
		UseGradients = true, -- glaze sheen is the whole point
		GradientIntensity = 0.35,
		ShadowTransparency = 0.6,
		HoverScale = 1.05,
		PressScale = 0.94,
		StrokeThickness = 2,
	},

	Arcade = {
		Panel = BLUSH,
		Row = Color3.fromRGB(255, 241, 244),
		RowTransparency = 0,
		NearBlack = Color3.fromRGB(255, 241, 244), -- "well" reads LIGHT here
		NearBlack2 = BLUSH,
		HeaderRed = ROSE,
		Red = DANGER,
		Green = MATCHA,
		MoneyGreen = MATCHA_DEEP,
		Blue = Color3.fromRGB(168, 205, 232),
		Gold = BUTTER,
		Magenta = Color3.fromRGB(226, 150, 210),
		Orange = TERRACOTTA,
		GreyOwned = Color3.fromRGB(224, 212, 214),
		GreyClaimed = Color3.fromRGB(212, 200, 202),
		IceBlue = INK_SOFT,
		SunburstGold = BUTTER,
		RulerTrack = Color3.fromRGB(240, 226, 230),
		RulerTick = INK_SOFT,
		ShopAccents = { ROSE, MATCHA, BUTTER, Color3.fromRGB(198, 178, 232) },
		Rainbow = { ROSE, Color3.fromRGB(255, 178, 196), BUTTER, MATCHA, Color3.fromRGB(198, 178, 232) },
	},

	-- The matte workbench dialect: cream paper, sage rules, clay speckle.
	Studio = {
		Panel = CREAM,
		PanelTransparency = 0,
		PanelSoft = Color3.fromRGB(255, 250, 245),
		PanelDeep = BLUSH,
		Card = Color3.fromRGB(255, 250, 245),
		CardSoft = BLUSH,
		Tan = Color3.fromRGB(206, 220, 196), -- sage hairline
		Accent = ROSE,
		Gold = BUTTER,
		TextLight = CREAM,
		TextDark = INK,
		TextMuted = INK_SOFT,
		Back = TERRACOTTA,
		Next = MATCHA_DEEP,
		WarnBg = Color3.fromRGB(255, 236, 214),
		WarnText = Color3.fromRGB(140, 92, 40),
	},

	Semantic = {
		Currency = {
			-- CLAY is the pottery currency; Cash/Bux/Robux keep their coding
			-- so the shared shop logic reads correctly under this pack too.
			Cash = MATCHA_DEEP,
			Bux = Color3.fromRGB(150, 178, 226),
			Robux = Color3.fromRGB(226, 150, 210),
			Clay = TERRACOTTA,
		},
		Selection = ROSE,
		Seat1 = ROSE,
		Seat2 = MATCHA,
		VSRose = ROSE,
		VSSky = Color3.fromRGB(168, 205, 232),
		CursorHover = MATCHA,
		CursorPush = ROSE,
		CursorPull = TERRACOTTA,
		CursorHollow = Color3.fromRGB(198, 178, 232),
	},

	-- Squash and stretch lives on UIScale (never Size — layout must not
	-- reflow). Overshoot magnitudes are deliberately modest.
	Motion = {
		HoverIn = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		HoverOut = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		PressIn = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		PopIn = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		PulseUp = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		PulseSettle = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		HoverScale = 1.05,
		HoverFillLerp = 0.08,
		PressScale = 0.94,
		PopFromScale = 0.9,
		PulseScale = 1.12, -- capped: bigger reads as broken, not playful
		BigHover = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		BigHoverScale = 1.06,
		BigHoverTilt = 1.5, -- the wobble axis
		BigPressScale = 0.95,
		BigRelease = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	},

	Shape = {
		RoundnessScale = 1,
		Style = "Bubbly",
		Depth = 0,
		HighlightTransparency = 0.75,
		ShadowStrength = 0.4,
		Bounce = 0.6,
	},

	LayoutKit = "GP",

	-- Soft everywhere: 2px rounded-join strokes in a deepened fill tint, no
	-- outlines on text (weight and colour carry emphasis instead), and the
	-- glass sheen ON because ceramics are glossy.
	Chrome = {
		StrokeThickness = 2,
		StrokeFollowsAccent = false,
		StrokeTransparency = 0.35,
		TextOutline = false,
		TextGlowTransparency = 1, -- no glow: soft pastel needs no halo
		Bevel = false,
		Glass = true,
		HardCorners = false,
	},

	-- SOFT, HUE-MATCHED shadows — the inversion of GL's hard sticker offset.
	-- Colour nil means "deepen the element's own hue" (resolved at the call
	-- site), which is what stops this pack from ever casting a grey shadow.
	EffectShadows = {
		sm = { Blur = 10, OffsetY = 4, Spread = 0, Transparency = 0.62 },
		md = { Blur = 16, OffsetY = 6, Spread = 1, Transparency = 0.58 },
		lg = { Blur = 22, OffsetY = 8, Spread = 2, Transparency = 0.55 },
		-- Zero-offset aura for featured/selected/reward states.
		glow = { Blur = 24, OffsetY = 0, Spread = 4, Transparency = 0.55 },
	},

	Assets = {
		scallopEdge = { image = "rbxassetid://106589516395336", tileX = 256, height = 32 },
		panelPetal = { image = "rbxassetid://92106748877100", slice = Rect.new(28, 28, 68, 68) },
		panelPetalFill = { image = "rbxassetid://131548493751697", slice = Rect.new(28, 28, 68, 68) },
		blob1 = { image = "rbxassetid://85882133300139" },
		blob2 = { image = "rbxassetid://124309693507855" },
		blob3 = { image = "rbxassetid://108816989093481" },
		sparkle = { image = "rbxassetid://83377649377794" },
		sparkleBurst = { image = "rbxassetid://114564477746249" },
		heart = { image = "rbxassetid://113173742029509" },
		daisy = { image = "rbxassetid://77390276672311" },
		bow = { image = "rbxassetid://97233003488656", slice = Rect.new(52, 40, 76, 56) },
		checker = { image = "rbxassetid://108330446377564", tile = 64 },
		gingham = { image = "rbxassetid://125087907872258", tile = 64 },
		polkadot = { image = "rbxassetid://132997749525296", tile = 64 },
		speckle = { image = "rbxassetid://113460944542117", tile = 256 },
		crackle = { image = "rbxassetid://118647602629412", tile = 512 },
		sheenArc = { image = "rbxassetid://133588714347812" },
		squiggle = { image = "rbxassetid://80854844205978", tileX = 256, height = 16 },
		sunburstSoft = { image = "rbxassetid://75252479509956" },
		confetti = { image = "rbxassetid://104287898359765" },
		wheelRadial = { image = "rbxassetid://101797410363615" },
	},

	-- Dialect + pottery tokens. Vocabulary is Pottery Battles', not generic.
	DialectTokens = {
		glaze = {
			sheenTransparency = 0.72,
			sheenHeightScale = 0.35,
			sparkleCount = 6,
			glowTransparency = 0.55,
			patternKey = "polkadot",
			patternTransparency = 0.92,
			-- The specular sweep along a poured meter: one slow pass with a
			-- narrow window, so the bar reads WET rather than animated.
			sheenSweepSeconds = 2.4,
			sheenWidthScale = 0.08,
			-- The sparkle spray, in full. These live HERE rather than as
			-- component constants because the spray's size, speed and spin are
			-- the pack's feel, not the emitter's implementation — a pack that
			-- wants a calmer twinkle retunes it without touching Luau. The
			-- emitter still floors the duration for photosensitivity: a pack may
			-- slow a sparkle down, never speed it into a strobe.
			sparkleSpreadPx = 74,
			sparkleSeconds = 0.52,
			sparkleSizePx = 26,
			sparkleSpinDegrees = 120,
			sparkleStagger = 0.03,
		},
		studio = {
			paper = CREAM,
			rule = Color3.fromRGB(206, 220, 196),
			speckleTransparency = 0.94,
			patternKey = "speckle",
			-- §0.3: the matte dialect shows the SAME stat count and precision
			-- as the AC assembly screen. Density is not negotiable here.
			statRowHeight = 30,
			statPrecision = 1,
		},
		-- Every DialectTokens entry is a NAMESPACE table (TokenBridge walks
		-- them one level deep); flat scalars live inside one.
		motion = {
			tiltSm = 2.5,
			wobbleDegrees = 1.5,
			breatheScale = 0.02,
			breatheSeconds = 3,
			-- The wobble ENVELOPE, not just its amplitude: a hover wobble is a
			-- decaying sine, and a pack owning the swing but not the decay owns
			-- half a gesture. ~3 swings, gone inside a second — sustained
			-- elastic reads as broken, not playful (the Motion.PulseScale cap
			-- above is the same argument).
			wobbleHz = 3.2,
			wobbleDecayPerSec = 3.4,
			-- Exponential approach rates (per second) for pointer tilt and for a
			-- meter chasing its value. Both are frame-rate independent, so these
			-- are FEEL numbers rather than speeds.
			tiltEasePerSec = 9,
			meterLerpRate = 9,
		},
		rarity = RARITY,
	},
}

return GirlyPopTheme
