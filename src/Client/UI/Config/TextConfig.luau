--!strict
-- The localization seam. Every user-facing string in the UI is referenced by a
-- textKey, and this module resolves keys -> display text. Today it holds one
-- English table; to localize later, swap Strings for a per-locale lookup and
-- Resolve() stays the same everywhere it's called.
--
-- Resolve() tolerates being handed an already-resolved literal (any string
-- without a "namespaced.key" shape passes through), so screens can mix keys and
-- ad-hoc text during MVP without crashing.

local TextConfig = {}

TextConfig.Strings = {
	-- Currencies
	["currency.cash"] = "Cash",
	["currency.bux"] = "Bux",
	["currency.robux"] = "Robux",

	-- Shop chrome
	["shop.title"] = "SHOP",
	["shop.buy"] = "Buy",
	["shop.owned"] = "Owned",
	["shop.cant_afford"] = "Not enough",
	["shop.category.featured"] = "Featured",
	["shop.category.boosts"] = "Boosts",
	["shop.category.cosmetics"] = "Cosmetics",
	["shop.purchase_success"] = "Purchase complete!",
	["shop.purchase_failed"] = "Purchase failed",

	-- Items
	["item.starter_bundle.name"] = "Starter Bundle",
	["item.mega_bundle.name"] = "Mega Bundle",
	["item.mystery_crate.name"] = "Mystery Crate",
	["item.speed_cola.name"] = "Speed Cola",
	["item.shield_generator.name"] = "Shield Generator",
	["item.double_xp.name"] = "2x XP (1h)",
	["item.golden_crown.name"] = "Golden Crown",
	["item.pixel_shades.name"] = "Pixel Shades",
	["item.rainbow_trail.name"] = "Rainbow Trail",

	-- Item descriptions (used by text-heavy / split layout packs)
	["item.starter_bundle.desc"] = "A hand-picked kit to kickstart your run: cash, a boost, and a cosmetic.",
	["item.mega_bundle.desc"] = "Everything in the Starter Bundle, doubled — the best value for serious players.",
	["item.mystery_crate.desc"] = "Contains one random item. Could be common, could be legendary. Feeling lucky?",
	["item.speed_cola.desc"] = "Reload and act faster for the next 10 minutes. Stacks with other boosts.",
	["item.shield_generator.desc"] = "Absorbs the next three hits you take. Recharges between waves.",
	["item.double_xp.desc"] = "Earn twice the XP for one hour. Timer keeps running while you play.",
	["item.golden_crown.desc"] = "A gleaming crown worn on your head. Purely cosmetic, endlessly regal.",
	["item.pixel_shades.desc"] = "Retro pixel sunglasses. Look cool, stay cool.",
	["item.rainbow_trail.desc"] = "Leave a shimmering rainbow trail wherever you walk.",

	-- Tags
	["tag.new"] = "NEW",
	["tag.sale"] = "SALE",
	["tag.rare"] = "RARE",
	["tag.limited"] = "LIMITED",
	["tag.popular"] = "POPULAR",

	-- HUD
	["hud.level"] = "Level",
	["hud.health"] = "Health",
	["hud.mana"] = "Mana",
	["hud.stamina"] = "Stamina",
	["hud.timer"] = "Time",
	["hud.objectives"] = "Objectives",
	["hud.wave"] = "Wave",

	-- Objectives (sample)
	["objective.reach_shop"] = "Find the shop",
	["objective.buy_boost"] = "Buy your first boost",
	["objective.survive"] = "Survive the wave",

	-- Tutorial (sample)
	["tutorial.welcome.title"] = "Welcome!",
	["tutorial.welcome.text"] = "This is your HUD. Your stats live up top.",
	["tutorial.shop.title"] = "The Shop",
	["tutorial.shop.text"] = "Tap the shop button to spend Cash and Bux.",
	["tutorial.themes.title"] = "Make It Yours",
	["tutorial.themes.text"] = "Open the Theme Editor to restyle everything live.",
	["tutorial.hint.tap"] = "Tap the highlighted element to continue.",

	-- Modal
	["modal.confirm"] = "Confirm",
	["modal.cancel"] = "Cancel",
	["modal.ok"] = "OK",
	["modal.confirm_purchase.title"] = "Confirm Purchase",

	-- Theme editor / selector
	["theme.selector.title"] = "Theme & Style",
	["theme.editor.title"] = "Theme Editor",
	["theme.export"] = "Export",
	["theme.export_script"] = "Script",
	["theme.import"] = "Import",
	["theme.export.hint"] = "Copied! Paste this module into Client/UI/Themes.",
	["theme.export.hint_manual"] = "Select all and copy this theme module.",
	["theme.import.hint"] = "Paste an exported theme module, then Import.",
	["theme.import.success"] = "Theme imported and applied.",
	["theme.import.failed"] = "Couldn't parse that theme.",
	["theme.reset"] = "Reset",
	["theme.close"] = "Close",

	-- NPC dialogue (sample)
	["npc.merchant.name"] = "Merchant Pip",
	["npc.merchant.l1"] = "Well met, traveler! You've got the look of someone who appreciates fine wares.",
	["npc.merchant.l2"] = "I've stocked crates, boosts, and cosmetics — all fairly priced, I assure you.",
	["npc.merchant.l3"] = "So, what'll it be? Care to browse my shop, or are you just passing through?",
	["npc.choice.shop"] = "Show me the shop",
	["npc.choice.bye"] = "Maybe later",

	-- Settings menu
	["settings.title"] = "SETTINGS",
	["settings.section.audio"] = "Audio",
	["settings.section.display"] = "Display",
	["settings.section.gameplay"] = "Gameplay",
	["settings.master_volume"] = "Master Volume",
	["settings.music_volume"] = "Music Volume",
	["settings.sfx_enabled"] = "Sound Effects",
	["settings.ui_scale"] = "UI Scale",
	["settings.reduced_motion"] = "Reduced Motion",
	["settings.quality"] = "Graphics Quality",
	["settings.quality.low"] = "Low",
	["settings.quality.medium"] = "Medium",
	["settings.quality.high"] = "High",
	["settings.show_damage"] = "Show Damage Numbers",
	["settings.show_overheads"] = "Show Overhead UI",
	["settings.camera_side"] = "Camera Side",
	["settings.side.left"] = "Left",
	["settings.side.right"] = "Right",

	-- Notification banners (sample)
	["notify.levelup.title"] = "Level Up!",
	["notify.levelup.body"] = "You reached level 8. New rewards unlocked.",
	["notify.achievement.title"] = "Achievement",
	["notify.achievement.body"] = "First Purchase — you bought your first item!",
}

-- true for "namespaced.key" shapes we should look up; false for literals that
-- should pass through untouched (already-resolved text, numbers-as-text, etc.).
local function looksLikeKey(value: string): boolean
	return string.match(value, "^[%w_]+%.[%w_%.]+$") ~= nil
end

function TextConfig.Resolve(keyOrText: string?): string
	if not keyOrText then
		return ""
	end
	local value = keyOrText :: string
	if looksLikeKey(value) then
		return TextConfig.Strings[value] or value
	end
	return value
end

function TextConfig.Has(key: string): boolean
	return TextConfig.Strings[key] ~= nil
end

return TextConfig
