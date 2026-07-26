--!strict
-- GURREN LAGANN · TECH — the token-swap proof: the same pack with the TECH
-- dialect applied GLOBALLY ("serious mode"): phosphor green terminal over
-- scorched black, CRT bloom instead of gold heat, Jura everywhere, glow
-- instead of comic ink outlines. Zero component edits — every difference
-- below is a token.

local Types = require(script.Parent.Parent.Types)
local Base = require(script.Parent.GurrenLagannTheme)

local PHOSPHOR = Color3.fromRGB(90, 255, 140)
local PHOS_DIM = Color3.fromRGB(58, 160, 96)
local VOID = Color3.fromRGB(6, 16, 10)

local function face(family: string, weight: Enum.FontWeight): Font
	local ok, font = pcall(function()
		return Font.new("rbxasset://fonts/families/" .. family .. ".json", weight)
	end)
	if ok then
		return font
	end
	return Font.fromEnum(Enum.Font.Code)
end

local function derive(base: Types.UITheme): Types.UITheme
	local theme: any = table.clone(base :: any)
	for _, field in { "Colors", "Fonts", "TextSizes", "Radii", "Spacing", "Animations", "Effects", "Arcade", "Studio", "Semantic", "Motion", "Chrome", "EffectShadows", "EffectGlows", "DialectTokens" } do
		if (base :: any)[field] then
			theme[field] = table.clone((base :: any)[field])
		end
	end
	theme.Arcade.ShopAccents = table.clone(theme.Arcade.ShopAccents)
	theme.Arcade.Rainbow = table.clone(theme.Arcade.Rainbow)
	theme.Semantic.Currency = table.clone(theme.Semantic.Currency)
	return theme :: Types.UITheme
end

local theme = derive(Base)
local t: any = theme

t.Id = "GurrenLagannTech"
t.DisplayName = "Gurren Lagann · Tech"

t.Colors.Primary = PHOSPHOR
t.Colors.Accent = PHOSPHOR
t.Colors.Secondary = Color3.fromRGB(180, 255, 200)
t.Colors.Background = VOID
t.Colors.Surface = Color3.fromRGB(10, 24, 15)
t.Colors.SurfaceRaised = Color3.fromRGB(16, 34, 22)
t.Colors.TextPrimary = Color3.fromRGB(214, 255, 226)
t.Colors.TextSecondary = PHOS_DIM
t.Colors.TextOnPrimary = VOID
t.Colors.Stroke = PHOSPHOR
t.Colors.Disabled = Color3.fromRGB(40, 66, 50)

t.Fonts.Title = face("Jura", Enum.FontWeight.Bold)
t.Fonts.Subtitle = face("Jura", Enum.FontWeight.SemiBold)
t.Fonts.Button = face("Jura", Enum.FontWeight.Bold)

t.Arcade.Panel = t.Colors.Surface
t.Arcade.Row = t.Colors.SurfaceRaised
t.Arcade.NearBlack = VOID
t.Arcade.NearBlack2 = Color3.fromRGB(8, 20, 12)
t.Arcade.HeaderRed = Color3.fromRGB(14, 44, 26)
t.Arcade.Red = Color3.fromRGB(30, 78, 46)
t.Arcade.Gold = PHOSPHOR
t.Arcade.SunburstGold = PHOSPHOR
t.Arcade.IceBlue = PHOS_DIM
t.Arcade.RulerTrack = Color3.fromRGB(10, 26, 16)

t.Semantic.Selection = PHOSPHOR

-- Terminal chrome: hairline phosphor framing, glow-not-outline.
t.Chrome.StrokeThickness = 1
t.Chrome.StrokeFollowsAccent = true
t.Chrome.StrokeTransparency = 0.35
t.Chrome.TextOutline = false
t.Chrome.TextGlowTransparency = 0.7

-- CRT bloom replaces gold heat; sticker shadows soften to screen-glow.
t.EffectShadows = {
	sm = { Blur = UDim.new(0, 6), Offset = UDim2.fromOffset(0, 2), Spread = UDim2.new(), Color = Color3.new(0, 0, 0), Transparency = 0.5 },
	md = { Blur = UDim.new(0, 12), Offset = UDim2.fromOffset(0, 3), Spread = UDim2.new(), Color = Color3.new(0, 0, 0), Transparency = 0.45 },
	lg = { Blur = UDim.new(0, 20), Offset = UDim2.fromOffset(0, 5), Spread = UDim2.new(), Color = Color3.new(0, 0, 0), Transparency = 0.4 },
}
t.EffectGlows = {
	sm = { Blur = UDim.new(0, 10), Offset = UDim2.new(), Spread = UDim2.new(), Color = PHOSPHOR, Transparency = 0.7 },
	md = { Blur = UDim.new(0, 18), Offset = UDim2.new(), Spread = UDim2.new(), Color = PHOSPHOR, Transparency = 0.5 },
	lg = { Blur = UDim.new(0, 28), Offset = UDim2.new(), Spread = UDim2.new(), Color = Color3.fromRGB(200, 255, 220), Transparency = 0.35 },
	pulse = { Blur = UDim.new(0, 20), Offset = UDim2.new(), Spread = UDim2.new(), Color = PHOSPHOR, Transparency = 0.45 },
}

return theme
