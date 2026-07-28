--!strict
-- GIRLY POP — MintSoda. THE TOKENIZATION PROOF.
--
-- This variant swaps colour DOMINANCE: mint green becomes primary, rose
-- becomes the accent. It is authored as a deep clone of StrawberryMatcha
-- with only colour slots reassigned — no new tokens, no component edits, no
-- layout code. If this renders correctly, the pack is genuinely data-driven
-- rather than secretly depending on hand-tuned code paths.
--
-- Everything structural is INHERITED by construction: fonts, radii (including
-- the per-corner petal sets), spacing, motion, chrome policy, shadow kit,
-- asset ids and dialect tokens are all carried over untouched. The diff is
-- colour only.
--
-- Contrast: the same measured rule applies. Near-white cannot sit on these
-- pastels, so body copy on mint/rose uses TextPrimary (plum-brown), which
-- measures 6.39:1 on mint and 5.15:1 on rose. TextOnPrimary stays reserved
-- for large display text on the deepened tints.

local Types = require(script.Parent.Parent.Types)
local Base = require(script.Parent.GirlyPopTheme)

local MINT = Color3.fromRGB(168, 222, 196) -- primary now
local MINT_DEEP = Color3.fromRGB(112, 178, 150)
local ROSE = Color3.fromRGB(255, 138, 175) -- demoted to accent
local ROSE_DEEP = Color3.fromRGB(232, 90, 140)
local CREAM = Color3.fromRGB(248, 252, 248) -- cooled base
local FOAM = Color3.fromRGB(230, 246, 238) -- cooled secondary surface
local BUTTER = Color3.fromRGB(255, 214, 122)
local INK = Color3.fromRGB(52, 70, 62) -- cooled plum -> deep pine, still warm-ish
local INK_SOFT = Color3.fromRGB(104, 128, 116)

-- Deep-clone every group so mutating the copy can never touch the base pack
-- (the same clone contract ColorPresetConfig uses).
local function clone(theme: Types.UITheme): Types.UITheme
	local copy: any = table.clone(theme :: any)
	for _, field in { "Colors", "Fonts", "TextSizes", "Radii", "Spacing", "Animations", "Effects", "Arcade", "Studio", "Semantic", "Motion", "Shape", "Chrome", "Assets", "Corners", "EffectShadows" } do
		if (theme :: any)[field] then
			copy[field] = table.clone((theme :: any)[field])
		end
	end
	copy.Arcade.ShopAccents = table.clone(copy.Arcade.ShopAccents)
	copy.Arcade.Rainbow = table.clone(copy.Arcade.Rainbow)
	copy.Semantic.Currency = table.clone(copy.Semantic.Currency)
	copy.DialectTokens = table.clone((theme :: any).DialectTokens)
	return copy
end

local MintSoda: Types.UITheme = clone(Base)

MintSoda.Id = "GirlyPopMint"
MintSoda.DisplayName = "Girly Pop · Mint Soda"

-- ---- the entire diff: colour slots ------------------------------------

MintSoda.Colors.Primary = MINT
MintSoda.Colors.Secondary = ROSE
MintSoda.Colors.Accent = BUTTER
MintSoda.Colors.Background = CREAM
MintSoda.Colors.Surface = FOAM
MintSoda.Colors.SurfaceRaised = Color3.fromRGB(240, 250, 244)
MintSoda.Colors.TextPrimary = INK
MintSoda.Colors.TextSecondary = INK_SOFT
MintSoda.Colors.Stroke = MINT_DEEP

MintSoda.Arcade.Panel = FOAM
MintSoda.Arcade.Row = Color3.fromRGB(240, 250, 244)
MintSoda.Arcade.NearBlack = Color3.fromRGB(240, 250, 244)
MintSoda.Arcade.NearBlack2 = FOAM
MintSoda.Arcade.HeaderRed = MINT -- the header band follows the PRIMARY
MintSoda.Arcade.Red = Color3.fromRGB(235, 110, 120)
MintSoda.Arcade.Green = ROSE -- swapped: the "secondary" slot wears rose
MintSoda.Arcade.MoneyGreen = MINT_DEEP
MintSoda.Arcade.RulerTrack = Color3.fromRGB(224, 240, 232)
MintSoda.Arcade.RulerTick = INK_SOFT
MintSoda.Arcade.IceBlue = INK_SOFT
MintSoda.Arcade.ShopAccents = { MINT, ROSE, BUTTER, Color3.fromRGB(178, 210, 232) }
MintSoda.Arcade.Rainbow = { MINT, Color3.fromRGB(198, 236, 214), BUTTER, ROSE, Color3.fromRGB(198, 178, 232) }

MintSoda.Studio.Panel = CREAM
MintSoda.Studio.PanelSoft = Color3.fromRGB(248, 253, 250)
MintSoda.Studio.PanelDeep = FOAM
MintSoda.Studio.Card = Color3.fromRGB(248, 253, 250)
MintSoda.Studio.CardSoft = FOAM
MintSoda.Studio.Tan = Color3.fromRGB(206, 226, 214)
MintSoda.Studio.Accent = MINT
MintSoda.Studio.TextDark = INK
MintSoda.Studio.TextMuted = INK_SOFT
MintSoda.Studio.Next = MINT_DEEP

MintSoda.Semantic.Selection = MINT
MintSoda.Semantic.Seat1 = MINT
MintSoda.Semantic.Seat2 = ROSE
MintSoda.Semantic.CursorHover = MINT
MintSoda.Semantic.CursorPush = ROSE
MintSoda.Semantic.Currency = table.clone(MintSoda.Semantic.Currency)
MintSoda.Semantic.Currency.Cash = MINT_DEEP

return MintSoda
