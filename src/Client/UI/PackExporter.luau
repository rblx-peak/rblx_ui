--!strict
-- Exports a ready-to-hand-off Luau module for the whole UI pack or any single
-- part of it (shop, npc, dialog, tutorial, chat, overheads, hud, nav, full).
--
-- WHAT IT EMITS
-- Each export is ONE self-contained ModuleScript that returns a fully-resolved
-- `SPEC` table — every theme token, pack/layout choice, config value and text
-- string that part actually uses, with NO require()s of the rest of the pack —
-- plus a heavily-commented header. The header is written for another AI: it
-- states the rblx_ui architecture rules and tells the AI exactly how to turn the
-- SPEC into working UI. So a person can paste one file into a fresh chat and the
-- AI has everything it needs to rebuild that part faithfully, or a developer can
-- read the SPEC directly as the source of truth for that part's design.
--
-- WHY DATA + BRIEF (not inlined renderer code): the live game cannot read module
-- .Source at runtime, and inlining ~3700 lines of renderer per part would be
-- unmaintainable and fragile. The resolved SPEC + explicit build instructions is
-- the durable, portable artifact — it captures the *decisions*, which is what
-- another AI (or you, later) needs to reproduce the look exactly.

local ThemeSerializer = require(script.Parent.Themes.ThemeSerializer)
local EntryLayoutConfig = require(script.Parent.Config.EntryLayoutConfig)
local HUDConfig = require(script.Parent.Config.HUDConfig)
local NavConfig = require(script.Parent.Config.NavConfig)
local OverheadConfig = require(script.Parent.Config.OverheadConfig)
local NPCDialogConfig = require(script.Parent.Config.NPCDialogConfig)
local SettingsConfig = require(script.Parent.Config.SettingsConfig)
local TextConfig = require(script.Parent.Config.TextConfig)

local PackExporter = {}

-- Known parts and a one-line description of each, surfaced in the picker UI.
PackExporter.Parts = {
	{ id = "full", label = "🌐 Full Pack" },
	{ id = "shop", label = "🛒 Shop" },
	{ id = "hud", label = "📊 HUD + Vitals" },
	{ id = "overheads", label = "🧍 Overheads" },
	{ id = "npc", label = "💬 NPC Dialog" },
	{ id = "tutorial", label = "🎓 Tutorial" },
	{ id = "nav", label = "🧭 Nav Rail" },
	{ id = "notify", label = "🔔 Notifications" },
	{ id = "settings", label = "⚙️ Settings Menu" },
	{ id = "chat", label = "🗨️ Chat (bubble + bar)" },
}

-- ---- Luau literal writers ---------------------------------------------

local writeValue -- forward decl (recursive)

local function writeColor(c: Color3): string
	return string.format("Color3.fromRGB(%d, %d, %d)", math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255))
end

local function writeVector3(v: Vector3): string
	return string.format("Vector3.new(%s, %s, %s)", tostring(v.X), tostring(v.Y), tostring(v.Z))
end

local function keyNeedsBracket(k: string): boolean
	return string.match(k, "^[%a_][%w_]*$") == nil
end

-- Serialize an arbitrary data table (no functions/instances) to indented Luau.
function writeValue(value: any, indent: number): string
	local t = typeof(value)
	if t == "string" then
		return string.format("%q", value)
	elseif t == "number" or t == "boolean" then
		return tostring(value)
	elseif t == "Color3" then
		return writeColor(value)
	elseif t == "Vector3" then
		return writeVector3(value)
	elseif t == "Vector2" then
		return string.format("Vector2.new(%s, %s)", tostring(value.X), tostring(value.Y))
	elseif t == "EnumItem" then
		-- tostring already yields "Enum.TextXAlignment.Left" — do NOT prefix again.
		return tostring(value)
	elseif t == "table" then
		local pad = string.rep("\t", indent)
		local padIn = string.rep("\t", indent + 1)
		-- Array vs map.
		local isArray = #value > 0
		local parts = {}
		if isArray then
			for _, item in value do
				table.insert(parts, padIn .. writeValue(item, indent + 1) .. ",")
			end
		else
			-- Stable key order for readable diffs.
			local keys = {}
			for k in value do
				table.insert(keys, k)
			end
			table.sort(keys, function(a, b)
				return tostring(a) < tostring(b)
			end)
			for _, k in keys do
				local keyStr = keyNeedsBracket(tostring(k)) and string.format("[%q]", tostring(k)) or tostring(k)
				table.insert(parts, padIn .. keyStr .. " = " .. writeValue(value[k], indent + 1) .. ",")
			end
		end
		if #parts == 0 then
			return "{}"
		end
		return "{\n" .. table.concat(parts, "\n") .. "\n" .. pad .. "}"
	end
	-- Unsupported (function, Instance, Font, TweenInfo) collapse to a note.
	return string.format("%q --[[ unsupported %s ]]", tostring(value), t)
end

-- ---- header / brief ----------------------------------------------------

-- The canonical source repo for the full pack (public — readable by anyone,
-- including another AI, with no access request needed). The in-game export can
-- only ship a design SPEC (a running game cannot read module source), so this
-- points the consuming AI at the real code. Update this string if the repo moves.
PackExporter.SourceRepo = "https://github.com/mrseph34/rblx_ui"

-- Prepended above every export so whoever receives the file knows the REAL code
-- exists and where — the SPEC below is the design, the repo is the source.
local function sourceHeader(): string
	return string.format(
		[[
-- ============================================================================
-- GET THE REAL CODE FIRST
-- ============================================================================
-- The `SPEC` table below is the DESIGN of this pack (every colour, font, layout,
-- HUD/nav/overhead config and string) — it is NOT the renderer code. To recreate
-- the pack faithfully, read the actual source modules here (public repo, no
-- access request needed):
--
--     %s   (folder: src/Client/UI)
--
-- With the real source you get an exact copy; with only this SPEC below you get
-- a faithful rebuild guided by the brief that follows.
-- ============================================================================
]],
		PackExporter.SourceRepo
	)
end

local ARCHITECTURE_BRIEF = [[
-- ============================================================================
-- rblx_ui EXPORTED PACK — AI BUILD BRIEF
-- ============================================================================
-- This module returns a single `SPEC` table describing one part of a
-- script-driven, theme-able Roblox UI pack. Everything below (colours, fonts,
-- sizes, layout choices, config, strings) is fully resolved from the live pack,
-- so it is the complete source of truth for this part's look and behaviour.
-- (For the actual renderer code, see the repo named in the header above.)
--
-- IF YOU ARE AN AI ASKED TO BUILD UI FROM THIS FILE, follow these rules:
--  1. Architecture: ONE ServerHandler + ONE ClientHandler; everything else is
--     ModuleScripts. Name things SomethingService/Controller/Config/Screen.
--     Shared = config/types/net; Server = authoritative; Client = UI/input/VFX.
--  2. Theming: read SPEC.theme for every colour/font/size/radius/anim token.
--     Paint tokens in one _Style pass per component so a live theme swap can
--     re-apply them; never hardcode a colour a token already covers.
--  3. Shape/feel: SPEC.theme.Shape decides roundness + Flat/Bubbly/Raised3D.
--     Bubbly => pill corners + springy hover; Raised3D => inner bevel (light top,
--     dark bottom) + drop shadow + press-depth; Flat => plain.
--  4. Layout: SPEC.layout / SPEC.pack decide arrangement, columns, card height,
--     image aspect (mostly square). ONE renderer builds every repeated entry
--     from a spec — do NOT write bespoke per-item code; that is what keeps every
--     entry consistent. Missing optional elements must still reserve their slot.
--  5. Responsiveness: size with scale + constraints (UIAspectRatioConstraint,
--     UITextSizeConstraint), pad scroll frames so nothing clips or is cut, and
--     make hit targets comfortable on touch. Support PC/mobile/controller.
--  6. Text: every user-facing string is in SPEC.strings keyed by id; resolve
--     through one lookup so it can be localized later.
--
-- **DO NOT build the Tutorial system (the onboarding walkthrough that
-- highlights/points at buttons) or the Theme Editor screen.** Both are
-- internal DEV TOOLING for this source project only — used to author and
-- preview the theme itself — and are NOT part of the pack a real game ships.
-- A game using this exported SPEC has no use for either: build only the
-- actual gameplay screens described here (shop, HUD, modal, NPC dialog, chat
-- bar, settings, etc.), never a screen that shows/edits/highlights the UI kit.
-- (BUT you may adjust the Tutorial to match this new game if instructed to do
-- so or if you so choose — that exception is Tutorial-only; the Theme Editor
-- still has no place in a shipped game regardless.)
--
-- Placeholders: emoji stand in for icon art (e.g. 💰 🛒 ❤️). Swap for images by
-- setting an asset id where the SPEC notes an icon.
-- ============================================================================
]]

local function resolveThemeStrings(): { [string]: string }
	-- Ship the whole string table; it is small and keeps the export standalone.
	return TextConfig.Strings
end

-- ---- part specs --------------------------------------------------------

-- Build the resolved data table for a given part from the live theme + pack.
local function buildPartSpec(part: string, theme: any, pack: any): any
	if part == "shop" then
		-- ServerRow is NOT rendered by the shared arrangement-keyed card renderer —
		-- it uses a dedicated boxy nested-box list-row renderer (UIListRowComponent).
		-- The generic note would mislead an export consumer into rebuilding a plain
		-- Row card, so describe the actual row structure when that layout is active.
		local isServerRow = pack.Shop.EntryLayout == "ServerRow"
		return {
			part = "shop",
			pack = pack.Shop,
			layout = EntryLayoutConfig.Get(pack.Shop.EntryLayout),
			allLayouts = EntryLayoutConfig.Specs,
			note = isServerRow
					and "This pack's shop is a scrollable LIST of boxy nested-box rows rendered by a DEDICATED renderer (not the shared arrangement-keyed card). Each row is a nested box: dark navy border -> light gap frame -> gradient inner box. Inside: a blue nested image box on the left (item icon, or a monogram of the name); the item name in white at the top-left; a gold label line showing the item description at the bottom-left; a green price/buy button at the top-right showing the currency icon + price (this IS the buy button); and a right-aligned category sub-label at the bottom-right. Every text label carries the theme's navy outline. See Reference/RefServersShop for the exact target look."
				or "Render one card per item with a single renderer keyed on layout.arrangement; reserve slots for optional name/desc/tags/price/buy so every card is structurally identical.",
		}
	elseif part == "hud" then
		return {
			part = "hud",
			elements = HUDConfig.Elements,
			defaultValues = HUDConfig.DefaultValues,
			hud = pack.HUD,
			note = "Place each element in its region container; Bar elements (health/mana/stamina) are a labelled track+fill. Any element can be relocated by region override.",
		}
	elseif part == "overheads" then
		return {
			part = "overheads",
			locations = OverheadConfig.Locations,
			bars = OverheadConfig.Bars,
			width = OverheadConfig.Width,
			rowHeight = OverheadConfig.RowHeight,
			note = "A BillboardGui adorned to the Head part: themed nameplate + vitals bars. StudsOffsetWorldSpace = locations[chosen]; feed values 0..maxValue per bar.",
		}
	elseif part == "npc" then
		return {
			part = "npc",
			sequences = NPCDialogConfig.Sequences,
			note = "Bottom panel: portrait + speaker + typewriter body (reveal chars at typeSpeed/sec, utf8-safe). Click skips to full line, then advances. Final line may show choices.",
		}
	elseif part == "tutorial" then
		return {
			part = "tutorial",
			note = "Dimming overlay + a highlight ring positioned over a target element (convert the target's AbsolutePosition into the ring parent's local space), a coach-mark popup with title/text, and next/skip. Steps reference highlightTargetId.",
		}
	elseif part == "nav" then
		return {
			part = "nav",
			buttons = NavConfig.Buttons,
			buttonSize = NavConfig.ButtonSize,
			spacing = NavConfig.Spacing,
			edgeOffset = NavConfig.EdgeOffset,
			nav = pack.Nav,
			note = "A rail of square icon buttons hugging pack.Nav.Side; each button's action opens a screen. Sizes/positions come from this data so buttons resize/move freely.",
		}
	elseif part == "notify" then
		return {
			part = "notify",
			note = "Top-center banner (variants Info/Success/Achievement/LevelUp tint the badge+accent) that slides down, holds `duration`, slides up; plus corner toasts for smaller feedback.",
		}
	elseif part == "settings" then
		return {
			part = "settings",
			sections = SettingsConfig.Sections,
			defaults = SettingsConfig.Defaults(),
			note = "Themed options panel: titled sections, each a scroll of consistent rows. Each row is a toggle (sliding knob), slider (labelled track + value) or dropdown (current value + drop list). Build all rows with ONE shared component per kind so they stay uniform.",
		}
	elseif part == "chat" then
		return {
			part = "chat",
			note = "TWO forms sharing a typewriter reveal (utf8-safe): (1) an overhead BillboardGui speech bubble above the Head that types, holds `duration`, then fades; (2) a bottom-of-screen speech BAR with optional speaker name that types a line/queue and auto-advances. Both fully themed; click skips to full line.",
		}
	end
	-- full
	return {
		part = "full",
		pack = pack,
		layouts = EntryLayoutConfig.Specs,
		hudElements = HUDConfig.Elements,
		hudDefaults = HUDConfig.DefaultValues,
		nav = { buttons = NavConfig.Buttons, buttonSize = NavConfig.ButtonSize },
		overheads = { locations = OverheadConfig.Locations, bars = OverheadConfig.Bars },
		npc = NPCDialogConfig.Sequences,
		note = "The complete pack: theme + layout packs + HUD + nav + overheads + npc dialog. Build each part per its sub-table following the brief above.",
	}
end

-- ---- public ------------------------------------------------------------

-- Serialize a full export module string for `part` from the live theme + pack.
function PackExporter.Export(part: string, theme: any, pack: any): string
	local partSpec = buildPartSpec(part, theme, pack)
	-- The theme block reuses the theme serializer verbatim so it matches the
	-- hand-written theme files (and round-trips through Import).
	local themeSource = ThemeSerializer.Serialize(theme)
	-- Strip the theme module's own header/return so we can embed just its table.
	local themeTable = string.match(themeSource, "=%s*(%b{})") or "{}"

	local moduleName = "RblxUI_" .. (string.upper(string.sub(part, 1, 1)) .. string.sub(part, 2)) .. "Export"

	local lines = {
		"--!strict",
		sourceHeader(),
		ARCHITECTURE_BRIEF,
		string.format("-- Part: %s   Theme: %s   Pack: %s", part, theme.DisplayName, pack.DisplayName),
		"",
		string.format("local %s = {}", moduleName),
		"",
		string.format("%s.SPEC = {", moduleName),
		"\ttheme = " .. string.gsub(themeTable, "\n", "\n\t") .. ",",
		"\tpackId = " .. string.format("%q", pack.Id) .. ",",
		"\tdata = " .. string.gsub(writeValue(partSpec, 1), "^", "") .. ",",
		"\tstrings = " .. string.gsub(writeValue(resolveThemeStrings(), 1), "^", "") .. ",",
		"}",
		"",
		string.format("return %s", moduleName),
		"",
	}
	return table.concat(lines, "\n")
end

return PackExporter
