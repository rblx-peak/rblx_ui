--!strict
-- Round-trips a live UITheme table to/from Luau module source.
--
-- Serialize() is what the in-game Theme Editor's Export button calls: it emits
-- a module that is byte-for-byte compatible with the hand-written theme files
-- in this folder (see DefaultTheme). Paste that text into a new file under
-- Client/UI/Themes and register it — or hand it to a developer verbatim.
--
-- Deserialize() closes the loop: it parses an exported block back into a live
-- theme so the editor's Import can preview pasted source without a rebuild.
-- It intentionally understands only the value forms Serialize() produces
-- (Color3.fromRGB, Font.fromEnum, TweenInfo.new, numbers, booleans, strings) —
-- it is not a general Luau evaluator.
--
-- Besides the legacy generic groups, both directions carry the Pottery Clash
-- family groups (Arcade / Studio / Semantic / Motion). Key names repeat across
-- those groups (Gold, Panel, Accent, Red, …), so the family groups are parsed
-- section-scoped: each group's balanced-brace block is extracted first and
-- keys are only matched inside it. A group absent from the source falls back
-- to the base theme's group, so exports that predate the families still import.

local Types = require(script.Parent.Parent.Types)

local ThemeSerializer = {}

-- ========================================================================
-- Serialize
-- ========================================================================

local function color(c: Color3): string
	return string.format(
		"Color3.fromRGB(%d, %d, %d)",
		math.round(c.R * 255),
		math.round(c.G * 255),
		math.round(c.B * 255)
	)
end

-- Recover the Enum.Font name from a Font so exports read like the hand-written
-- themes (Font.fromEnum(Enum.Font.GothamBold)) instead of a raw content id.
local function font(f: Font): string
	for _, item in Enum.Font:GetEnumItems() do
		if item ~= Enum.Font.Unknown then
			local ok, candidate = pcall(Font.fromEnum, item)
			if ok and candidate.Family == f.Family and candidate.Weight == f.Weight and candidate.Style == f.Style then
				return string.format("Font.fromEnum(Enum.Font.%s)", item.Name)
			end
		end
	end
	-- Fallback: reconstruct from raw family/weight/style.
	return string.format(
		'Font.new("%s", Enum.FontWeight.%s, Enum.FontStyle.%s)',
		f.Family,
		f.Weight.Name,
		f.Style.Name
	)
end

local function tween(t: TweenInfo): string
	return string.format(
		"TweenInfo.new(%s, Enum.EasingStyle.%s, Enum.EasingDirection.%s)",
		tostring(t.Time),
		t.EasingStyle.Name,
		t.EasingDirection.Name
	)
end

local function num(n: number): string
	if n == math.floor(n) then
		return tostring(math.floor(n))
	end
	return tostring(n)
end

local function indentBlock(lines: { string }): string
	return table.concat(lines, "\n")
end

-- Emit a `Name = value,` line at a given indent depth.
local function line(depth: number, key: string, value: string): string
	return string.rep("\t", depth) .. key .. " = " .. value .. ","
end

-- Currency is an open map; emit the canonical ids first so exports read like
-- the hand-written themes, then any extra currencies alphabetically.
local CURRENCY_ORDER = { "Cash", "Bux", "Robux" }

local function currencyKeys(map: { [string]: Color3 }): { string }
	local keys: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, key in CURRENCY_ORDER do
		if map[key] then
			table.insert(keys, key)
			seen[key] = true
		end
	end
	local extras: { string } = {}
	for key in map do
		if not seen[key] then
			table.insert(extras, key)
		end
	end
	table.sort(extras)
	for _, key in extras do
		table.insert(keys, key)
	end
	return keys
end

function ThemeSerializer.Serialize(theme: Types.UITheme): string
	local c = theme.Colors
	local f = theme.Fonts
	local ts = theme.TextSizes
	local r = theme.Radii
	local sp = theme.Spacing
	local a = theme.Animations
	local e = theme.Effects
	local ar = theme.Arcade
	local st = theme.Studio
	local sem = theme.Semantic
	local mo = theme.Motion

	-- Sanitise the id into a valid, unique-ish variable/module name.
	local varName = (string.gsub(theme.DisplayName, "[^%w]", "")) .. "Theme"
	if varName == "Theme" then
		varName = "CustomTheme"
	end

	local lines = {
		"--!strict",
		"-- Exported from the in-game Theme Editor. Drop this file into",
		"-- Client/UI/Themes and register it in UIThemeConfig to use it.",
		"",
		"local Types = require(script.Parent.Parent.Types)",
		"",
		string.format("local %s: Types.UITheme = {", varName),
		line(1, "Id", string.format("%q", theme.Id)),
		line(1, "DisplayName", string.format("%q", theme.DisplayName)),
		"",
		"\tColors = {",
		line(2, "Primary", color(c.Primary)),
		line(2, "Secondary", color(c.Secondary)),
		line(2, "Accent", color(c.Accent)),
		line(2, "Background", color(c.Background)),
		line(2, "Surface", color(c.Surface)),
		line(2, "SurfaceRaised", color(c.SurfaceRaised)),
		line(2, "Success", color(c.Success)),
		line(2, "Warning", color(c.Warning)),
		line(2, "Error", color(c.Error)),
		line(2, "TextPrimary", color(c.TextPrimary)),
		line(2, "TextSecondary", color(c.TextSecondary)),
		line(2, "TextOnPrimary", color(c.TextOnPrimary)),
		line(2, "Stroke", color(c.Stroke)),
		line(2, "Overlay", color(c.Overlay)),
		line(2, "Disabled", color(c.Disabled)),
		"\t},",
		"",
		"\tFonts = {",
		line(2, "Title", font(f.Title)),
		line(2, "Subtitle", font(f.Subtitle)),
		line(2, "Body", font(f.Body)),
		line(2, "Button", font(f.Button)),
		line(2, "Numeric", font(f.Numeric)),
		"\t},",
		"",
		"\tTextSizes = {",
		line(2, "Title", num(ts.Title)),
		line(2, "Subtitle", num(ts.Subtitle)),
		line(2, "Body", num(ts.Body)),
		line(2, "Button", num(ts.Button)),
		line(2, "Small", num(ts.Small)),
		"\t},",
		"",
		"\tRadii = {",
		line(2, "Small", num(r.Small)),
		line(2, "Medium", num(r.Medium)),
		line(2, "Large", num(r.Large)),
		line(2, "Pill", num(r.Pill)),
		"\t},",
		"",
		"\tSpacing = {",
		line(2, "XS", num(sp.XS)),
		line(2, "S", num(sp.S)),
		line(2, "M", num(sp.M)),
		line(2, "L", num(sp.L)),
		line(2, "XL", num(sp.XL)),
		"\t},",
		"",
		"\tAnimations = {",
		line(2, "Appear", tween(a.Appear)),
		line(2, "Disappear", tween(a.Disappear)),
		line(2, "Hover", tween(a.Hover)),
		line(2, "Press", tween(a.Press)),
		line(2, "Emphasis", tween(a.Emphasis)),
		line(2, "ThemeSwap", tween(a.ThemeSwap)),
		"\t},",
		"",
		"\tEffects = {",
		line(2, "UseGradients", tostring(e.UseGradients)),
		line(2, "GradientIntensity", num(e.GradientIntensity)),
		line(2, "ShadowTransparency", num(e.ShadowTransparency)),
		line(2, "HoverScale", num(e.HoverScale)),
		line(2, "PressScale", num(e.PressScale)),
		line(2, "StrokeThickness", num(e.StrokeThickness)),
		"\t},",
	}

	local function push(text: string)
		table.insert(lines, text)
	end

	local function pushColorArray(key: string, colors: { Color3 })
		push("\t\t" .. key .. " = {")
		for _, entry in colors do
			push("\t\t\t" .. color(entry) .. ",")
		end
		push("\t\t},")
	end

	-- Arcade HUD palette (doc §3.2).
	push("")
	push("\tArcade = {")
	push(line(2, "Panel", color(ar.Panel)))
	push(line(2, "Row", color(ar.Row)))
	push(line(2, "RowTransparency", num(ar.RowTransparency)))
	push(line(2, "NearBlack", color(ar.NearBlack)))
	push(line(2, "NearBlack2", color(ar.NearBlack2)))
	push(line(2, "HeaderRed", color(ar.HeaderRed)))
	push(line(2, "Red", color(ar.Red)))
	push(line(2, "Green", color(ar.Green)))
	push(line(2, "Blue", color(ar.Blue)))
	push(line(2, "Gold", color(ar.Gold)))
	push(line(2, "Magenta", color(ar.Magenta)))
	push(line(2, "Orange", color(ar.Orange)))
	push(line(2, "GreyOwned", color(ar.GreyOwned)))
	push(line(2, "GreyClaimed", color(ar.GreyClaimed)))
	push(line(2, "IceBlue", color(ar.IceBlue)))
	push(line(2, "SunburstGold", color(ar.SunburstGold)))
	push(line(2, "MoneyGreen", color(ar.MoneyGreen)))
	push(line(2, "RulerTrack", color(ar.RulerTrack)))
	push(line(2, "RulerTick", color(ar.RulerTick)))
	pushColorArray("ShopAccents", ar.ShopAccents)
	pushColorArray("Rainbow", ar.Rainbow)
	push("\t},")

	-- Ceramic studio palette (doc §3.1).
	push("")
	push("\tStudio = {")
	push(line(2, "Panel", color(st.Panel)))
	push(line(2, "PanelTransparency", num(st.PanelTransparency)))
	push(line(2, "PanelSoft", color(st.PanelSoft)))
	push(line(2, "PanelDeep", color(st.PanelDeep)))
	push(line(2, "Card", color(st.Card)))
	push(line(2, "CardSoft", color(st.CardSoft)))
	push(line(2, "Tan", color(st.Tan)))
	push(line(2, "Accent", color(st.Accent)))
	push(line(2, "Gold", color(st.Gold)))
	push(line(2, "TextLight", color(st.TextLight)))
	push(line(2, "TextDark", color(st.TextDark)))
	push(line(2, "TextMuted", color(st.TextMuted)))
	push(line(2, "Back", color(st.Back)))
	push(line(2, "Next", color(st.Next)))
	push(line(2, "WarnBg", color(st.WarnBg)))
	push(line(2, "WarnText", color(st.WarnText)))
	push("\t},")

	-- Semantic colour rules (doc §3.3) — currency map + identity colours.
	push("")
	push("\tSemantic = {")
	push("\t\tCurrency = {")
	for _, key in currencyKeys(sem.Currency) do
		push(line(3, key, color(sem.Currency[key])))
	end
	push("\t\t},")
	push(line(2, "Selection", color(sem.Selection)))
	push(line(2, "Seat1", color(sem.Seat1)))
	push(line(2, "Seat2", color(sem.Seat2)))
	push(line(2, "VSRose", color(sem.VSRose)))
	push(line(2, "VSSky", color(sem.VSSky)))
	push(line(2, "CursorHover", color(sem.CursorHover)))
	push(line(2, "CursorPush", color(sem.CursorPush)))
	push(line(2, "CursorPull", color(sem.CursorPull)))
	push(line(2, "CursorHollow", color(sem.CursorHollow)))
	push("\t},")

	-- Motion kit (doc §5.1 / §5.2).
	push("")
	push("\tMotion = {")
	push(line(2, "HoverIn", tween(mo.HoverIn)))
	push(line(2, "HoverOut", tween(mo.HoverOut)))
	push(line(2, "PressIn", tween(mo.PressIn)))
	push(line(2, "PopIn", tween(mo.PopIn)))
	push(line(2, "PulseUp", tween(mo.PulseUp)))
	push(line(2, "PulseSettle", tween(mo.PulseSettle)))
	push(line(2, "HoverScale", num(mo.HoverScale)))
	push(line(2, "HoverFillLerp", num(mo.HoverFillLerp)))
	push(line(2, "PressScale", num(mo.PressScale)))
	push(line(2, "PopFromScale", num(mo.PopFromScale)))
	push(line(2, "PulseScale", num(mo.PulseScale)))
	push(line(2, "BigHover", tween(mo.BigHover)))
	push(line(2, "BigHoverScale", num(mo.BigHoverScale)))
	push(line(2, "BigHoverTilt", num(mo.BigHoverTilt)))
	push(line(2, "BigPressScale", num(mo.BigPressScale)))
	push(line(2, "BigRelease", tween(mo.BigRelease)))
	push("\t},")

	-- Shape is optional; emit it only when present so Flat themes stay minimal.
	local shape = theme.Shape
	if shape then
		table.insert(lines, "")
		table.insert(lines, "\tShape = {")
		table.insert(lines, line(2, "RoundnessScale", num(shape.RoundnessScale)))
		table.insert(lines, line(2, "Style", string.format("%q", shape.Style)))
		table.insert(lines, line(2, "Depth", num(shape.Depth)))
		table.insert(lines, line(2, "HighlightTransparency", num(shape.HighlightTransparency)))
		table.insert(lines, line(2, "ShadowStrength", num(shape.ShadowStrength)))
		table.insert(lines, line(2, "Bounce", num(shape.Bounce)))
		table.insert(lines, "\t},")
	end

	table.insert(lines, "}")
	table.insert(lines, "")
	table.insert(lines, string.format("return %s", varName))
	table.insert(lines, "")

	return indentBlock(lines)
end

-- ========================================================================
-- Deserialize
-- ========================================================================

-- Grab the first occurrence of a `Key = <value>,` pair anywhere in the source.
-- Legacy-group keys are unique enough across the theme table that a flat
-- search is fine (kept byte-compatible; the family groups use grabIn below).
local function grab(source: string, key: string): string?
	local value = string.match(source, key .. "%s*=%s*([^\n]-),%s*\n")
	if value then
		return (string.gsub(value, "%s+$", ""))
	end
	return nil
end

-- Decode the literal value forms Serialize() emits.
local function decodeColor(raw: string?): Color3?
	if raw then
		local rr, gg, bb = string.match(raw, "Color3%.fromRGB%(%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*%)")
		if rr then
			return Color3.fromRGB(tonumber(rr) :: number, tonumber(gg) :: number, tonumber(bb) :: number)
		end
	end
	return nil
end

local function decodeTween(raw: string?): TweenInfo?
	if raw then
		local time, style, dir = string.match(
			raw,
			"TweenInfo%.new%(%s*([%d%.]+)%s*,%s*Enum%.EasingStyle%.(%w+)%s*,%s*Enum%.EasingDirection%.(%w+)"
		)
		if time then
			local easingStyle = (Enum.EasingStyle :: any)[style]
			local easingDir = (Enum.EasingDirection :: any)[dir]
			if easingStyle and easingDir then
				return TweenInfo.new(tonumber(time) :: number, easingStyle, easingDir)
			end
		end
	end
	return nil
end

local function parseColor(source: string, key: string, fallback: Color3): Color3
	return decodeColor(grab(source, key)) or fallback
end

local function parseNumber(source: string, key: string, fallback: number): number
	local raw = grab(source, key)
	return raw and tonumber(raw) or fallback
end

local function parseBool(source: string, key: string, fallback: boolean): boolean
	local raw = grab(source, key)
	if raw == "true" then
		return true
	elseif raw == "false" then
		return false
	end
	return fallback
end

local function parseFont(source: string, key: string, fallback: Font): Font
	local raw = grab(source, key)
	if raw then
		local enumName = string.match(raw, "Enum%.Font%.(%w+)")
		if enumName and (Enum.Font :: any)[enumName] then
			return Font.fromEnum((Enum.Font :: any)[enumName])
		end
	end
	return fallback
end

local function parseTween(source: string, key: string, fallback: TweenInfo): TweenInfo
	return decodeTween(grab(source, key)) or fallback
end

-- ========================================================================
-- Section-scoped parsing for the family groups (Arcade/Studio/Semantic/
-- Motion). Duplicated key names across groups (Gold, Panel, Accent, Red, …)
-- WOULD collide with the flat grab(), so each group's balanced-brace block
-- is extracted first and keys are matched only inside it — anchored on a
-- word boundary (%f[%w]) so e.g. `Red` never matches the tail of `HeaderRed`.
-- ========================================================================

local function sectionBlock(source: string, groupName: string): string?
	return string.match(source, "%f[%w]" .. groupName .. "%s*=%s*(%b{})")
end

local function grabIn(block: string, key: string): string?
	local value = string.match(block, "%f[%w]" .. key .. "%s*=%s*([^\n]-),%s*\n")
	if value then
		return (string.gsub(value, "%s+$", ""))
	end
	return nil
end

local function colorIn(block: string, key: string, fallback: Color3): Color3
	return decodeColor(grabIn(block, key)) or fallback
end

local function numberIn(block: string, key: string, fallback: number): number
	local raw = grabIn(block, key)
	return raw and tonumber(raw) or fallback
end

local function tweenIn(block: string, key: string, fallback: TweenInfo): TweenInfo
	return decodeTween(grabIn(block, key)) or fallback
end

-- Parse a `{ Color3.fromRGB(...), ... }` array; empty/absent = base's array.
local function colorArrayIn(block: string, key: string, fallback: { Color3 }): { Color3 }
	local arr = string.match(block, "%f[%w]" .. key .. "%s*=%s*(%b{})")
	if arr then
		local colors: { Color3 } = {}
		for rr, gg, bb in string.gmatch(arr, "Color3%.fromRGB%(%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*%)") do
			table.insert(colors, Color3.fromRGB(tonumber(rr) :: number, tonumber(gg) :: number, tonumber(bb) :: number))
		end
		if #colors > 0 then
			return colors
		end
	end
	return table.clone(fallback)
end

local function parseArcade(source: string, base: Types.UIThemeArcade): Types.UIThemeArcade
	local block = sectionBlock(source, "Arcade")
	if not block then
		return base
	end
	return {
		Panel = colorIn(block, "Panel", base.Panel),
		Row = colorIn(block, "Row", base.Row),
		RowTransparency = numberIn(block, "RowTransparency", base.RowTransparency),
		NearBlack = colorIn(block, "NearBlack", base.NearBlack),
		NearBlack2 = colorIn(block, "NearBlack2", base.NearBlack2),
		HeaderRed = colorIn(block, "HeaderRed", base.HeaderRed),
		Red = colorIn(block, "Red", base.Red),
		Green = colorIn(block, "Green", base.Green),
		Blue = colorIn(block, "Blue", base.Blue),
		Gold = colorIn(block, "Gold", base.Gold),
		Magenta = colorIn(block, "Magenta", base.Magenta),
		Orange = colorIn(block, "Orange", base.Orange),
		GreyOwned = colorIn(block, "GreyOwned", base.GreyOwned),
		GreyClaimed = colorIn(block, "GreyClaimed", base.GreyClaimed),
		IceBlue = colorIn(block, "IceBlue", base.IceBlue),
		SunburstGold = colorIn(block, "SunburstGold", base.SunburstGold),
		MoneyGreen = colorIn(block, "MoneyGreen", base.MoneyGreen),
		RulerTrack = colorIn(block, "RulerTrack", base.RulerTrack),
		RulerTick = colorIn(block, "RulerTick", base.RulerTick),
		ShopAccents = colorArrayIn(block, "ShopAccents", base.ShopAccents),
		Rainbow = colorArrayIn(block, "Rainbow", base.Rainbow),
	}
end

local function parseStudio(source: string, base: Types.UIThemeStudio): Types.UIThemeStudio
	local block = sectionBlock(source, "Studio")
	if not block then
		return base
	end
	return {
		Panel = colorIn(block, "Panel", base.Panel),
		PanelTransparency = numberIn(block, "PanelTransparency", base.PanelTransparency),
		PanelSoft = colorIn(block, "PanelSoft", base.PanelSoft),
		PanelDeep = colorIn(block, "PanelDeep", base.PanelDeep),
		Card = colorIn(block, "Card", base.Card),
		CardSoft = colorIn(block, "CardSoft", base.CardSoft),
		Tan = colorIn(block, "Tan", base.Tan),
		Accent = colorIn(block, "Accent", base.Accent),
		Gold = colorIn(block, "Gold", base.Gold),
		TextLight = colorIn(block, "TextLight", base.TextLight),
		TextDark = colorIn(block, "TextDark", base.TextDark),
		TextMuted = colorIn(block, "TextMuted", base.TextMuted),
		Back = colorIn(block, "Back", base.Back),
		Next = colorIn(block, "Next", base.Next),
		WarnBg = colorIn(block, "WarnBg", base.WarnBg),
		WarnText = colorIn(block, "WarnText", base.WarnText),
	}
end

local function parseSemantic(source: string, base: Types.UIThemeSemantic): Types.UIThemeSemantic
	local block = sectionBlock(source, "Semantic")
	if not block then
		return base
	end
	-- Currency is an open map: take every `Key = Color3.fromRGB(...)` pair in
	-- the nested Currency block, then fill any id the source omits from base
	-- (Cash/Bux/Robux must always exist — CurrencyColor depends on them).
	local currency: { [string]: Color3 } = {}
	local currencyBlock = string.match(block, "%f[%w]Currency%s*=%s*(%b{})")
	if currencyBlock then
		for key, rr, gg, bb in
			string.gmatch(currencyBlock, "(%w+)%s*=%s*Color3%.fromRGB%(%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*%)")
		do
			currency[key] = Color3.fromRGB(tonumber(rr) :: number, tonumber(gg) :: number, tonumber(bb) :: number)
		end
	end
	for key, value in base.Currency do
		if currency[key] == nil then
			currency[key] = value
		end
	end
	return {
		Currency = currency,
		Selection = colorIn(block, "Selection", base.Selection),
		Seat1 = colorIn(block, "Seat1", base.Seat1),
		Seat2 = colorIn(block, "Seat2", base.Seat2),
		VSRose = colorIn(block, "VSRose", base.VSRose),
		VSSky = colorIn(block, "VSSky", base.VSSky),
		CursorHover = colorIn(block, "CursorHover", base.CursorHover),
		CursorPush = colorIn(block, "CursorPush", base.CursorPush),
		CursorPull = colorIn(block, "CursorPull", base.CursorPull),
		CursorHollow = colorIn(block, "CursorHollow", base.CursorHollow),
	}
end

local function parseMotion(source: string, base: Types.UIThemeMotion): Types.UIThemeMotion
	local block = sectionBlock(source, "Motion")
	if not block then
		return base
	end
	return {
		HoverIn = tweenIn(block, "HoverIn", base.HoverIn),
		HoverOut = tweenIn(block, "HoverOut", base.HoverOut),
		PressIn = tweenIn(block, "PressIn", base.PressIn),
		PopIn = tweenIn(block, "PopIn", base.PopIn),
		PulseUp = tweenIn(block, "PulseUp", base.PulseUp),
		PulseSettle = tweenIn(block, "PulseSettle", base.PulseSettle),
		HoverScale = numberIn(block, "HoverScale", base.HoverScale),
		HoverFillLerp = numberIn(block, "HoverFillLerp", base.HoverFillLerp),
		PressScale = numberIn(block, "PressScale", base.PressScale),
		PopFromScale = numberIn(block, "PopFromScale", base.PopFromScale),
		PulseScale = numberIn(block, "PulseScale", base.PulseScale),
		BigHover = tweenIn(block, "BigHover", base.BigHover),
		BigHoverScale = numberIn(block, "BigHoverScale", base.BigHoverScale),
		BigHoverTilt = numberIn(block, "BigHoverTilt", base.BigHoverTilt),
		BigPressScale = numberIn(block, "BigPressScale", base.BigPressScale),
		BigRelease = tweenIn(block, "BigRelease", base.BigRelease),
	}
end

-- Parse exported source into a theme, layering onto `base` (usually the
-- current DefaultTheme) so any token the source omits keeps a sane value.
-- Returns nil + reason if the block is clearly not a theme export.
function ThemeSerializer.Deserialize(source: string, base: Types.UITheme): (Types.UITheme?, string?)
	if not string.find(source, "Colors") or not string.find(source, "Primary") then
		return nil, "That doesn't look like an exported theme (no Colors block found)."
	end

	local id = grab(source, "Id")
	local displayName = grab(source, "DisplayName")
	local function unquote(s: string?): string?
		return s and (string.match(s, '^"(.*)"$') or string.match(s, "^'(.*)'$")) or s
	end

	local c = base.Colors
	local f = base.Fonts
	local ts = base.TextSizes
	local r = base.Radii
	local sp = base.Spacing
	local a = base.Animations
	local e = base.Effects

	local theme: Types.UITheme = {
		Id = unquote(id) or "Custom",
		DisplayName = unquote(displayName) or "Custom",
		Colors = {
			Primary = parseColor(source, "Primary", c.Primary),
			Secondary = parseColor(source, "Secondary", c.Secondary),
			Accent = parseColor(source, "Accent", c.Accent),
			Background = parseColor(source, "Background", c.Background),
			Surface = parseColor(source, "Surface", c.Surface),
			SurfaceRaised = parseColor(source, "SurfaceRaised", c.SurfaceRaised),
			Success = parseColor(source, "Success", c.Success),
			Warning = parseColor(source, "Warning", c.Warning),
			Error = parseColor(source, "Error", c.Error),
			TextPrimary = parseColor(source, "TextPrimary", c.TextPrimary),
			TextSecondary = parseColor(source, "TextSecondary", c.TextSecondary),
			TextOnPrimary = parseColor(source, "TextOnPrimary", c.TextOnPrimary),
			Stroke = parseColor(source, "Stroke", c.Stroke),
			Overlay = parseColor(source, "Overlay", c.Overlay),
			Disabled = parseColor(source, "Disabled", c.Disabled),
		},
		Fonts = {
			Title = parseFont(source, "Title", f.Title),
			Subtitle = parseFont(source, "Subtitle", f.Subtitle),
			Body = parseFont(source, "Body", f.Body),
			Button = parseFont(source, "Button", f.Button),
			Numeric = parseFont(source, "Numeric", f.Numeric),
		},
		TextSizes = {
			Title = parseNumber(source, "Title", ts.Title),
			Subtitle = parseNumber(source, "Subtitle", ts.Subtitle),
			Body = parseNumber(source, "Body", ts.Body),
			Button = parseNumber(source, "Button", ts.Button),
			Small = parseNumber(source, "Small", ts.Small),
		},
		Radii = {
			Small = parseNumber(source, "Small", r.Small),
			Medium = parseNumber(source, "Medium", r.Medium),
			Large = parseNumber(source, "Large", r.Large),
			Pill = parseNumber(source, "Pill", r.Pill),
		},
		Spacing = {
			XS = parseNumber(source, "XS", sp.XS),
			S = parseNumber(source, "S", sp.S),
			M = parseNumber(source, "M", sp.M),
			L = parseNumber(source, "L", sp.L),
			XL = parseNumber(source, "XL", sp.XL),
		},
		Animations = {
			Appear = parseTween(source, "Appear", a.Appear),
			Disappear = parseTween(source, "Disappear", a.Disappear),
			Hover = parseTween(source, "Hover", a.Hover),
			Press = parseTween(source, "Press", a.Press),
			Emphasis = parseTween(source, "Emphasis", a.Emphasis),
			ThemeSwap = parseTween(source, "ThemeSwap", a.ThemeSwap),
		},
		Effects = {
			UseGradients = parseBool(source, "UseGradients", e.UseGradients),
			GradientIntensity = parseNumber(source, "GradientIntensity", e.GradientIntensity),
			ShadowTransparency = parseNumber(source, "ShadowTransparency", e.ShadowTransparency),
			HoverScale = parseNumber(source, "HoverScale", e.HoverScale),
			PressScale = parseNumber(source, "PressScale", e.PressScale),
			StrokeThickness = parseNumber(source, "StrokeThickness", e.StrokeThickness),
		},
		-- Family groups: section-scoped (see above); absent = base's group,
		-- so exports that predate them still import cleanly.
		Arcade = parseArcade(source, base.Arcade),
		Studio = parseStudio(source, base.Studio),
		Semantic = parseSemantic(source, base.Semantic),
		Motion = parseMotion(source, base.Motion),
	}

	-- Shape round-trips only if the source has a Shape block (Style key present);
	-- otherwise carry the base theme's Shape so imports of Flat exports stay Flat.
	if string.find(source, "Shape") and string.find(source, "Style") then
		local styleRaw = grab(source, "Style")
		local style = (styleRaw and (string.match(styleRaw, '^"(.*)"$') or string.match(styleRaw, "^'(.*)'$"))) or "Flat"
		theme.Shape = {
			RoundnessScale = parseNumber(source, "RoundnessScale", 1),
			Style = style :: any,
			Depth = parseNumber(source, "Depth", 0),
			HighlightTransparency = parseNumber(source, "HighlightTransparency", 1),
			ShadowStrength = parseNumber(source, "ShadowStrength", 0),
			Bounce = parseNumber(source, "Bounce", 0),
		}
	else
		theme.Shape = base.Shape
	end

	return theme, nil
end

return ThemeSerializer
