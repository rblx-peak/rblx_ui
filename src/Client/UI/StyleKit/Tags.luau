--!strict
-- Style/Tags — the canonical tag registry: the contract between components
-- and style packs, replacing "don't fork components" with "don't invent
-- structural tags".
--
--   * STRUCTURAL tags describe what a thing IS (panel, button, list row).
--     Components apply them at build time via StateDriver.Structural. Packs
--     write StyleRules against them. Packs may NOT invent new ones — if a
--     pack needs a structure the registry lacks, the registry (framework)
--     grows, deliberately.
--   * MODIFIER tags describe a STATE (selected, danger, featured). Only
--     StateDriver may flip them at runtime, so every state change is
--     auditable and styling transitions fire from exactly one place.
--   * DIALECT tags scope a pack's sub-language on a subtree (Gurren Lagann
--     ships Comic and Tech dialects). Applied to panel roots; pack rules
--     select ".UIPanel.DialectComic" (compound selectors verified accepted
--     by the engine; render-time behavior gated on Capabilities).
--
-- Existing CollectionService tags (UIHeaderBar / UICloseButton, used by the
-- preset retint sweep since before this layer existed) fold in as structural
-- tags so there is ONE registry, not two.

local Tags = {}

Tags.Structural = {
	Panel = "UIPanel",
	Surface = "UISurface",
	Button = "UIButton",
	ButtonPrimary = "UIButtonPrimary",
	Label = "UILabel",
	Value = "UIValue",
	ListRow = "UIListRow",
	Slot = "UISlot",
	Chip = "UIChip",
	MeterFill = "UIMeterFill",
	Tab = "UITab",
	Icon = "UIIcon",
	-- Pre-existing sweep tags, absorbed unchanged:
	HeaderBar = "UIHeaderBar",
	CloseButton = "UICloseButton",
}

Tags.Modifier = {
	Selected = "UISelected",
	Danger = "UIDanger",
	Disabled = "UIDisabled",
	Featured = "UIFeatured",
	-- "charged/maxed" celebratory state (spiral gauge MAX, over-threshold
	-- meters). Generic on purpose: packs style it, features flip it.
	Maxed = "UIMaxed",
	Armed = "UIArmed",
}

Tags.Dialect = {
	Comic = "DialectComic",
	Tech = "DialectTech",
}

local structuralSet: { [string]: boolean } = {}
for _, tag in Tags.Structural do
	structuralSet[tag] = true
end
local modifierSet: { [string]: boolean } = {}
for _, tag in Tags.Modifier do
	modifierSet[tag] = true
end
local dialectSet: { [string]: boolean } = {}
for _, tag in Tags.Dialect do
	dialectSet[tag] = true
end

function Tags.IsStructural(tag: string): boolean
	return structuralSet[tag] == true
end

function Tags.IsModifier(tag: string): boolean
	return modifierSet[tag] == true
end

function Tags.IsDialect(tag: string): boolean
	return dialectSet[tag] == true
end

return Tags
