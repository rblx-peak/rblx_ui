--!strict
-- Style/SheetBuilder — turns a pack's declarative rule table into a live
-- StyleSheet: token attributes (TokenBridge), StyleRules with a fixed
-- priority ladder, gated transitions, and the documented-undefined-behavior
-- guards. Packs author DATA; this module is the only thing that touches the
-- styling instance API.
--
-- PRIORITY LADDER (deterministic conflict resolution — never authoring-order
-- luck): Base 0 < Pack 100 < Dialect 200 < State 300 < A11y 400. Within a
-- band, rules keep authoring order via +index (0..99 per band).
--
-- GUARDS:
--   * A rule that sets BOTH `CornerRadius` and any per-corner radius is
--     refused with an error — the engine documents that combination as
--     undefined behavior.
--   * Transitions are attached only when the styling classes exist; under
--     reduce-motion every TweenInfo is substituted with a zero-duration
--     TweenInfo and the sheet is REBUILT (styling has no user-preference
--     hook — sheet substitution is the honest cost, and it's paid only on
--     an accessibility toggle, never per frame).
--   * Transitions may not be attached to rules matching high-frequency
--     elements: any selector touching UIMeterFill is refused a transition
--     (meter fills are ticker-driven by contract).
--
-- While Capabilities.StylingActive is false (the case in this environment
-- today — see Capabilities.luau), built sheets are inert data linked at the
-- layer roots: zero render cost, ready for the engine build that turns
-- styling on. The imperative UIChrome path remains authoritative until then.

local Types = require(script.Parent.Parent:WaitForChild("Types"))
local Capabilities = require(script.Parent:WaitForChild("Capabilities"))
local TokenBridge = require(script.Parent:WaitForChild("TokenBridge"))

local SheetBuilder = {}

export type RuleDef = {
	selector: string,
	band: ("Base" | "Pack" | "Dialect" | "State" | "A11y")?, -- default "Pack"
	props: { [string]: any },
	transitions: { [string]: TweenInfo }?,
}

local BAND_PRIORITY: { [string]: number } = {
	Base = 0,
	Pack = 100,
	Dialect = 200,
	State = 300,
	A11y = 400,
}

local PER_CORNER = { "TopLeftRadius", "TopRightRadius", "BottomLeftRadius", "BottomRightRadius" }

local function guardCorners(def: RuleDef)
	if def.props.CornerRadius == nil then
		return
	end
	for _, key in PER_CORNER do
		if def.props[key] ~= nil then
			error(("SheetBuilder: rule %q sets CornerRadius AND %s — documented undefined behavior; pick one form"):format(def.selector, key))
		end
	end
end

local function guardTransitionTarget(def: RuleDef)
	if def.transitions and string.find(def.selector, "UIMeterFill", 1, true) then
		error(("SheetBuilder: rule %q attaches transitions to a meter fill — high-frequency elements stay ticker-driven"):format(def.selector))
	end
end

local function zeroed(info: TweenInfo): TweenInfo
	return TweenInfo.new(0, info.EasingStyle, info.EasingDirection)
end

-- The shared framework-default token sheet every pack sheet derives from.
local baseSheet: StyleSheet? = nil

function SheetBuilder.BaseSheet(defaultTheme: Types.UITheme): StyleSheet
	if baseSheet and baseSheet.Parent ~= nil then
		return baseSheet
	end
	local sheet = Instance.new("StyleSheet")
	sheet.Name = "BaseTokens"
	TokenBridge.Sync(sheet, defaultTheme)
	baseSheet = sheet
	return sheet
end

-- Build a pack sheet: tokens + rules (+ derive from base). `reduceMotion`
-- swaps every transition for a zero-duration one.
function SheetBuilder.Build(theme: Types.UITheme, opts: {
	base: StyleSheet?,
	reduceMotion: boolean?,
}?): StyleSheet
	local o = opts or {}
	local sheet = Instance.new("StyleSheet")
	sheet.Name = "Pack_" .. theme.Id
	TokenBridge.Sync(sheet, theme)

	if o.base then
		local derive = Instance.new("StyleDerive")
		derive.StyleSheet = o.base
		derive.Parent = sheet
	end

	local ruleDefs = (theme :: any).StyleRules :: { RuleDef }?
	if ruleDefs then
		local bandCounts: { [string]: number } = {}
		for _, def in ruleDefs do
			guardCorners(def)
			guardTransitionTarget(def)
			local band = def.band or "Pack"
			local basePriority = BAND_PRIORITY[band] or BAND_PRIORITY.Pack
			local index = bandCounts[band] or 0
			bandCounts[band] = index + 1

			local rule = Instance.new("StyleRule")
			rule.Selector = def.selector
			rule.Priority = basePriority + math.min(index, 99)
			rule:SetProperties(def.props)
			if def.transitions then
				local transitions: { [string]: TweenInfo } = {}
				for prop, info in def.transitions do
					transitions[prop] = o.reduceMotion and zeroed(info) or info
				end
				pcall(function()
					rule:SetPropertyTransitions(transitions)
				end)
			end
			rule.Parent = sheet
		end
	end

	return sheet
end

-- Rebuild-for-accessibility: same pack, motion zeroed. Caller swaps links.
function SheetBuilder.Rebuild(theme: Types.UITheme, base: StyleSheet?, reduceMotion: boolean): StyleSheet
	return SheetBuilder.Build(theme, { base = base, reduceMotion = reduceMotion })
end

return SheetBuilder
