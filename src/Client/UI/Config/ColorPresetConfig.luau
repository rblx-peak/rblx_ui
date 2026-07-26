--!strict
-- Colour presets — curated 5-swatch palettes (coolors.co-style) that recolour
-- the ACTIVE style live. This is the digestible replacement for per-token
-- colour fields and sliders: a preset is one click, not fifteen edits.
--
-- A preset deliberately changes ONLY the chrome + highlight colours:
--   bg      -> page / wells / near-black chrome (darkest stop)
--   surface -> panels / slate chrome
--   raised  -> rows / cards / raised chrome
--   accent  -> the highlight: selection rings, gold-slots, rulers, sunbursts
--   text    -> primary ink
-- Semantic colours are LAW and never touched by a preset: currency coding
-- (Cash green / Bux blue / Robux magenta), success/error/warn, and the black
-- stroke policy all stay put, so a recolour can never break meaning.
--
-- Add a preset: append a row. First preset = the stock "Roblox Classic"
-- palette and the boot default.

local Types = require(script.Parent.Parent.Types)

local ColorPresetConfig = {}

export type Preset = {
	id: string,
	name: string,
	bg: Color3,
	surface: Color3,
	raised: Color3,
	accent: Color3,
	text: Color3,
	-- The header-bar hue: modal headers AND the whole close/danger red family
	-- (close X, RESET, LEAVE...) follow it, per the owner ("this red should
	-- change even the X buttons"). Omitted = derived from the accent.
	header: Color3?,
	-- Explicit close/danger colour; omitted = lightened header.
	close: Color3?,
	-- Light palettes flip ink dark; everything else keeps light text.
	darkText: boolean?,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

ColorPresetConfig.DefaultPresetId = "classic"

ColorPresetConfig.Presets = {
	-- The stock palette of the Roblox Classic style (the shipped arcade look).
	{ id = "classic", name = "Roblox Classic", bg = rgb(18, 22, 28), surface = rgb(38, 44, 54), raised = rgb(52, 60, 74), accent = rgb(245, 190, 55), text = rgb(255, 255, 255), header = rgb(235, 45, 30), close = rgb(224, 64, 64) },
	{ id = "blurple", name = "Midnight Blurple", bg = rgb(26, 27, 44), surface = rgb(42, 44, 72), raised = rgb(58, 61, 98), accent = rgb(140, 142, 255), text = rgb(255, 255, 255), header = rgb(96, 92, 232) },
	{ id = "emerald", name = "Emerald Arcade", bg = rgb(10, 26, 20), surface = rgb(20, 44, 34), raised = rgb(30, 62, 48), accent = rgb(80, 220, 130), text = rgb(255, 255, 255), header = rgb(24, 150, 96) },
	{ id = "sunset", name = "Sunset Punch", bg = rgb(38, 16, 30), surface = rgb(64, 26, 46), raised = rgb(90, 38, 62), accent = rgb(255, 122, 90), text = rgb(255, 244, 235), header = rgb(235, 84, 60) },
	{ id = "bubblegum", name = "Bubblegum Pop", bg = rgb(48, 24, 44), surface = rgb(80, 36, 68), raised = rgb(112, 50, 92), accent = rgb(255, 120, 190), text = rgb(255, 255, 255), header = rgb(232, 62, 148) },
	{ id = "ocean", name = "Ocean Deep", bg = rgb(8, 22, 36), surface = rgb(16, 38, 58), raised = rgb(26, 56, 82), accent = rgb(90, 200, 255), text = rgb(255, 255, 255), header = rgb(28, 118, 198) },
	{ id = "lava", name = "Lava Forge", bg = rgb(28, 14, 12), surface = rgb(50, 22, 18), raised = rgb(74, 32, 24), accent = rgb(255, 140, 50), text = rgb(255, 246, 238), header = rgb(226, 88, 28) },
	{ id = "royal", name = "Royal Court", bg = rgb(22, 18, 34), surface = rgb(38, 30, 56), raised = rgb(56, 44, 80), accent = rgb(245, 190, 55), text = rgb(255, 255, 255), header = rgb(132, 82, 220) },
	{ id = "slate", name = "Slate Mono", bg = rgb(18, 18, 22), surface = rgb(34, 34, 40), raised = rgb(50, 50, 58), accent = rgb(205, 210, 220), text = rgb(255, 255, 255), header = rgb(92, 98, 112) },
	{ id = "toxic", name = "Toxic Rush", bg = rgb(16, 24, 10), surface = rgb(28, 42, 18), raised = rgb(40, 60, 26), accent = rgb(190, 255, 70), text = rgb(255, 255, 255), header = rgb(108, 178, 30) },
	{ id = "cherry", name = "Cherry Soda", bg = rgb(34, 12, 18), surface = rgb(58, 20, 30), raised = rgb(84, 30, 42), accent = rgb(255, 96, 128), text = rgb(255, 255, 255), header = rgb(224, 48, 88) },
	{ id = "cotton", name = "Cotton Candy", bg = rgb(226, 232, 246), surface = rgb(246, 249, 255), raised = rgb(208, 218, 240), accent = rgb(255, 110, 165), text = rgb(38, 34, 52), darkText = true, header = rgb(255, 110, 165) },
	-- The Armored Core alternates: the AC style's stock is Teal; these give
	-- the Amber variant (and Teal-as-a-preset so OTHER styles can wear it).
	{ id = "acAmber", name = "AC Amber", bg = rgb(10, 9, 7), surface = rgb(16, 15, 13), raised = rgb(22, 20, 17), accent = rgb(255, 170, 0), text = rgb(240, 236, 228), header = rgb(46, 34, 10) },
	{ id = "acTeal", name = "AC Teal", bg = rgb(8, 8, 10), surface = rgb(15, 15, 15), raised = rgb(20, 20, 22), accent = rgb(0, 200, 255), text = rgb(235, 240, 240), header = rgb(16, 34, 42) },
} :: { Preset }

function ColorPresetConfig.Get(id: string): Preset?
	for _, preset in ColorPresetConfig.Presets do
		if preset.id == id then
			return preset
		end
	end
	return nil
end

-- The five swatches in display order (dark -> light -> accent last, the way
-- a coolors strip reads).
function ColorPresetConfig.Swatches(preset: Preset): { Color3 }
	return { preset.bg, preset.surface, preset.raised, preset.text, preset.accent }
end

local function darken(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

local function lighten(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), amount)
end

-- Deep-clone a theme far enough that recolouring the copy can never mutate
-- the live one (same field set the theme editor used to clone).
local function cloneTheme(theme: Types.UITheme): Types.UITheme
	local copy: any = table.clone(theme :: any)
	for _, field in { "Colors", "Fonts", "TextSizes", "Radii", "Spacing", "Animations", "Effects", "Arcade", "Studio", "Semantic", "Motion" } do
		copy[field] = table.clone((theme :: any)[field])
	end
	copy.Arcade.ShopAccents = table.clone(copy.Arcade.ShopAccents)
	copy.Arcade.Rainbow = table.clone(copy.Arcade.Rainbow)
	copy.Semantic.Currency = table.clone(copy.Semantic.Currency)
	if copy.Shape then
		copy.Shape = table.clone(copy.Shape)
	end
	return copy
end

-- Recolour `base` with a preset. Returns a NEW theme table (same Id, same
-- style) ready for UIThemeController:ApplyThemeObject. Only chrome +
-- highlight slots move; semantics stay (see module comment).
function ColorPresetConfig.Apply(base: Types.UITheme, preset: Preset): Types.UITheme
	local theme = cloneTheme(base)
	local c = theme.Colors
	local a = theme.Arcade

	-- Chrome.
	c.Background = preset.bg
	c.Surface = preset.surface
	c.SurfaceRaised = preset.raised
	a.NearBlack = darken(preset.bg, 0.25)
	a.NearBlack2 = preset.bg
	a.Panel = preset.surface
	a.Row = preset.raised
	a.RulerTrack = darken(preset.bg, 0.35)

	-- Highlight: one accent drives everything "selected / valuable".
	c.Accent = preset.accent
	a.Gold = preset.accent
	a.SunburstGold = lighten(preset.accent, 0.1)
	theme.Semantic.Selection = preset.accent

	-- Header + the close/danger family: modal header bars, every close X and
	-- red danger button follow the preset's header hue ("this red should
	-- change even the X buttons" — the owner). Colors.Error is left alone so
	-- error TEXT keeps its meaning.
	local header = preset.header or darken(preset.accent, 0.2)
	a.HeaderRed = header
	a.Red = preset.close or lighten(header, 0.12)

	-- Ink.
	c.TextPrimary = preset.text
	c.TextOnPrimary = preset.text
	if preset.darkText then
		-- Light palette: secondary ink darkens instead of icing over.
		c.TextSecondary = lighten(preset.text, 0.35)
	else
		c.TextSecondary = lighten(preset.surface, 0.55)
	end

	return theme
end

return ColorPresetConfig
