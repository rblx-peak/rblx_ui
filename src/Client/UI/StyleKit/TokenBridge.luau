--!strict
-- Style/TokenBridge — flattens a pack's UITheme token tables into $token
-- attributes on that pack's StyleSheet, so StyleRules can say
-- `BackgroundColor3 = "$color_surface"` and a theme swap is an attribute
-- update, not a rule rewrite.
--
-- Naming: attribute names cannot contain dots, so the dotted token paths
-- flatten with underscores — `Colors.Surface` -> `color_surface`,
-- `Arcade.HeaderRed` -> `arcade_headerRed`, `effect.glow.md.blur` ->
-- `effect_glow_md_blur`. One scheme, documented here, used everywhere.
--
-- Fonts are the one token class that CANNOT bridge: the attribute type
-- system has no Font. Rules that need FontFace get it inlined per-pack by
-- SheetBuilder (resolved from theme.Fonts at build time); Luau consumers
-- keep reading theme.Fonts directly. Recorded in the migration report.
--
-- The bridge is write-only state: Theme.get()/theme table reads stay the
-- source of truth for Luau. Attributes exist for RULES. While styling is
-- inert (Capabilities.StylingActive == false) this is dormant data.

local Types = require(script.Parent.Parent:WaitForChild("Types"))

local TokenBridge = {}

local function setAttr(sheet: StyleSheet, key: string, value: any)
	-- Attribute values: Color3 / number / UDim / UDim2 / bool / string all
	-- supported; anything else (TweenInfo, Font, tables) must not reach here.
	sheet:SetAttribute(key, value)
end

local function bridgeGroup(sheet: StyleSheet, prefix: string, group: { [string]: any })
	for key, value in group do
		local t = typeof(value)
		if t == "Color3" or t == "number" or t == "boolean" or t == "string" or t == "UDim" or t == "UDim2" then
			-- lowerCamel the first letter of the group prefix; keep key casing
			setAttr(sheet, prefix .. "_" .. key, value)
		end
		-- tables (ShopAccents, Rainbow, Currency) and TweenInfos stay
		-- Luau-side: rules cannot index into them anyway.
	end
end

-- Write every bridgeable token of `theme` onto `sheet`. Idempotent; call on
-- every theme swap with the pack's live sheet.
function TokenBridge.Sync(sheet: StyleSheet, theme: Types.UITheme)
	bridgeGroup(sheet, "color", theme.Colors :: any)
	bridgeGroup(sheet, "textSize", theme.TextSizes :: any)
	bridgeGroup(sheet, "radius", theme.Radii :: any)
	bridgeGroup(sheet, "space", theme.Spacing :: any)
	bridgeGroup(sheet, "arcade", theme.Arcade :: any)
	bridgeGroup(sheet, "studio", theme.Studio :: any)
	bridgeGroup(sheet, "semantic", theme.Semantic :: any)
	if theme.Chrome then
		bridgeGroup(sheet, "chrome", theme.Chrome :: any)
	end
	-- effect.shadow.* / effect.glow.* (optional groups; see Types)
	local effects = (theme :: any).EffectShadows
	if effects then
		for size, def in effects do
			bridgeGroup(sheet, "effect_shadow_" .. size, def)
		end
	end
	local glows = (theme :: any).EffectGlows
	if glows then
		for size, def in glows do
			bridgeGroup(sheet, "effect_glow_" .. size, def)
		end
	end
	-- dialect sub-namespaces (GL: dialect.comic.* / dialect.tech.*)
	local dialects = (theme :: any).DialectTokens
	if dialects then
		for dialect, group in dialects do
			bridgeGroup(sheet, "dialect_" .. dialect, group)
		end
	end
	sheet:SetAttribute("packId", theme.Id)
end

return TokenBridge
