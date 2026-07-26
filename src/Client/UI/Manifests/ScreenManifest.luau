--!strict
-- THE CATALOG. Every window this system can build, declared as data.
--
-- To ship a new game you edit THIS FILE (and the theme pack) — not screen
-- code. Flip `enabled = false` on what the game doesn't use; the module is
-- never even required. Add a genre pack by dropping modules in a folder and
-- pointing entries at it with `folder`.
--
-- Fields:
--   id         the string every call site uses: ShowScreen("inventory")
--   module     ModuleScript name inside `folder` (default "Screens")
--   layer      which Layers band it parents into
--   exclusive  part of the one-panel-at-a-time set (default true for Screens)
--   hidesHUD   hide the HUD layer while this is open (focused moments, §11.5)
--   pausesInput  sink gameplay input while open
--   enabled    false = not built for this game, never required
--   tags       free-form grouping for tooling / the theme previewer

export type Entry = {
	id: string,
	module: string,
	folder: string?,
	layer: string?,
	exclusive: boolean?,
	hidesHUD: boolean?,
	pausesInput: boolean?,
	enabled: boolean?,
	tags: { string }?,
	description: string?,
}

local ScreenManifest = {}

ScreenManifest.Entries = {
	-- ===================== core (the original ten) =====================
	{ id = "hud", module = "GameHUDScreen", layer = "HUD", exclusive = false, tags = { "core" }, description = "Persistent gameplay HUD: rails, pills, timer, objectives" },
	{ id = "shop", module = "ShopScreen", tags = { "core", "economy" }, description = "Category shop browser with card grid" },
	{ id = "store", module = "StoreScreen", tags = { "core", "economy" }, description = "Featured/premium storefront" },
	{ id = "index", module = "IndexScreen", tags = { "core", "progression" }, description = "Collection index with locked tiles" },
	{ id = "modal", module = "ModalScreen", layer = "Modal", exclusive = false, tags = { "core" }, description = "Shared confirm / info / danger dialog" },
	{ id = "tutorial", module = "TutorialScreen", layer = "Overlay", tags = { "core" }, description = "Spotlight tutorial overlay" },
	{ id = "themeSelector", module = "ThemeSelectorScreen", tags = { "dev" }, description = "Theme editor / previewer (dev only)" },
	{ id = "npcDialog", module = "NPCDialogScreen", tags = { "core" }, description = "NPC dialogue with typewriter + choices" },
	{ id = "settings", module = "SettingsScreen", tags = { "core" }, description = "Data-driven settings" },
	{ id = "chatBar", module = "ChatBarScreen", layer = "HUD", exclusive = false, tags = { "core" }, description = "Bottom narration / subtitle bar" },

	-- ===================== system & session =====================
	{ id = "loading", module = "LoadingScreen", layer = "Backdrop", exclusive = false, hidesHUD = true, tags = { "system" }, description = "Boot/teleport loading screen with real preload progress" },
	{ id = "pause", module = "PauseScreen", pausesInput = true, tags = { "system" }, description = "Pause/menu overlay (Roblox can't truly pause a server)" },
	{ id = "death", module = "DeathScreen", layer = "Overlay", hidesHUD = true, tags = { "system" }, description = "Death + respawn countdown" },
	{ id = "matchSummary", module = "MatchSummaryScreen", tags = { "system", "progression" }, description = "End-of-match scoreboard + reward breakdown" },
	{ id = "patchNotes", module = "PatchNotesScreen", tags = { "system" }, description = "What's-new modal, version gated" },

	-- ===================== inventory & gear =====================
	{ id = "inventory", module = "InventoryScreen", tags = { "economy" }, description = "Grid inventory: sort, filter, item detail, equip" },
	{ id = "crafting", module = "CraftingScreen", tags = { "economy" }, description = "Recipe list with material requirements" },

	-- ===================== progression =====================
	{ id = "quests", module = "QuestJournalScreen", tags = { "progression" }, description = "Quest journal: active / completed tabs, track toggle" },
	{ id = "achievements", module = "AchievementsScreen", tags = { "progression" }, description = "Achievement list with progress + rarity" },
	{ id = "battlePass", module = "BattlePassScreen", tags = { "progression", "economy" }, description = "Season track: free/premium lanes, tier nodes" },
	{ id = "skillTree", module = "SkillTreeScreen", tags = { "progression" }, description = "Node graph with connectors and unlock states" },
	{ id = "stats", module = "StatsScreen", tags = { "progression" }, description = "Lifetime statistics page" },
	{ id = "titles", module = "TitlesScreen", tags = { "progression" }, description = "Equippable player titles with rarity" },

	-- ===================== economy & retention =====================
	{ id = "dailyRewards", module = "DailyRewardsScreen", tags = { "economy" }, description = "Login calendar with streak + claim" },
	{ id = "codes", module = "RedeemCodesScreen", tags = { "economy" }, description = "Promo code entry" },
	{ id = "rotatingShop", module = "RotatingShopScreen", tags = { "economy" }, description = "Timed rotating stock with restock countdown" },
	{ id = "crateReveal", module = "CrateRevealScreen", layer = "Modal", hidesHUD = false, tags = { "economy", "reveal" }, description = "Crate opening: bounce drop, pop, confetti" },
	{ id = "spinWheel", module = "SpinWheelScreen", hidesHUD = true, tags = { "economy", "reveal" }, description = "Prize wheel: 4.2s Quint spin + award popup" },
	{ id = "gifts", module = "GiftsScreen", tags = { "economy" }, description = "Gift inbox with claim countdown" },

	-- ===================== social =====================
	{ id = "social", module = "SocialScreen", tags = { "social" }, description = "Friends / party with invite + join" },
	{ id = "leaderboard", module = "LeaderboardScreen", tags = { "social" }, description = "Ranked boards with zebra rows and podium" },
	{ id = "trade", module = "TradeScreen", pausesInput = true, tags = { "social" }, description = "Dual-confirm player trade window" },

	-- ===================== match flow =====================
	{ id = "duelIntro", module = "DuelIntroScreen", layer = "Overlay", hidesHUD = true, tags = { "match" }, description = "VS intro over a staged camera shot" },
	{ id = "duelResult", module = "DuelResultScreen", layer = "Overlay", hidesHUD = true, tags = { "match" }, description = "Win/lose result with scrim and pips" },

	-- ===================== the way in =====================
	-- The dock is the persistent HUD strip that can open everything; the
	-- catalog is its full-screen counterpart. Both are dev/demo surfaces —
	-- set enabled = false to ship a game without them.
	{ id = "screenDock", module = "ScreenDockScreen", layer = "HUD", exclusive = false, tags = { "dev" }, description = "Persistent dock: open any screen, step through the catalog" },
	{ id = "screenCatalog", module = "ScreenCatalogScreen", tags = { "dev" }, description = "Full-screen browser of every screen in the manifest" },

	-- ===================== cosmetics & dev =====================
	{ id = "skinsGallery", module = "SkinsGalleryScreen", tags = { "cosmetics" }, description = "Skin/cosmetic gallery with live previews" },
	{ id = "adminPanel", module = "AdminPanelScreen", layer = "Debug", exclusive = false, tags = { "dev" }, description = "Admin/test command panel (allowlisted)" },

	-- ===================== world & navigation =====================
	{ id = "map", module = "MapScreen", tags = { "progression" }, description = "Full map: pan/zoom, pin layers, fast travel" },
	{ id = "codex", module = "CodexScreen", tags = { "progression" }, description = "Bestiary / lore library with categories + read states" },
	{ id = "faction", module = "FactionScreen", tags = { "progression" }, description = "Faction reputation meters with rank rewards" },
	{ id = "rank", module = "RankScreen", tags = { "progression" }, description = "Competitive rank / tier with promo series" },

	-- ===================== character =====================
	{ id = "characterCreator", module = "CharacterCreatorScreen", hidesHUD = true, tags = { "cosmetics" }, description = "Class select + appearance + name entry" },
	{ id = "loadout", module = "LoadoutScreen", tags = { "economy" }, description = "Saved builds / loadout presets with slot grid" },
	{ id = "radialWheel", module = "RadialWheelScreen", layer = "Overlay", exclusive = false, tags = { "core" }, description = "Generic radial wheel: emotes, weapons, pings" },

	-- ===================== monetization spine =====================
	{ id = "premiumShop", module = "PremiumShopScreen", tags = { "economy" }, description = "Robux products + gamepasses; hands off to Roblox prompts" },
	{ id = "vendor", module = "VendorScreen", tags = { "economy" }, description = "Soft-currency vendor: buy / sell / buyback tabs" },
	{ id = "mailbox", module = "MailboxScreen", tags = { "social" }, description = "Mail inbox with attachments + claim" },

	-- ===================== competitive & social =====================
	{ id = "guild", module = "GuildScreen", tags = { "social" }, description = "Guild hub: roster, ranks, contribution log" },
	{ id = "lobby", module = "LobbyScreen", tags = { "match" }, description = "Pre-match lobby: ready-up, host controls, map vote" },
	{ id = "matchmaking", module = "MatchmakingScreen", layer = "Overlay", exclusive = false, tags = { "match" }, description = "Queue status: wait estimate + cancel" },
	{ id = "spectator", module = "SpectatorScreen", layer = "HUD", exclusive = false, tags = { "match" }, description = "Spectator chrome: player switcher + follow cam controls" },
	{ id = "serverBrowser", module = "ServerBrowserScreen", tags = { "social" }, description = "Server list with region/ping + join" },

	-- ===================== genre: builder =====================
	-- The build palette pair. One shared model (BuildPaletteState) drives both:
	-- the persistent bottom toolbar and the palette panel that opens above it.
	{ id = "hotbar", module = "HotbarScreen", layer = "HUD", exclusive = false, tags = { "core", "build" }, description = "Bottom build toolbar: 9 slots, 1-9 selection, opens the palette" },
	{ id = "buildInventory", module = "BuildInventoryScreen", hidesHUD = false, tags = { "build" }, description = "Build palette above the toolbar: category tabs, item grid, click-to-swap hotbar loadout" },

	-- ===================== genre: mech garage =====================
	-- Owner call: the AC look ships as a STYLE over the universal library, not
	-- as a bespoke garage screen. Module stays on disk; flip to re-enable.
	{ id = "assembly", module = "AssemblyScreen", hidesHUD = true, enabled = false, tags = { "genre-mech" }, description = "AC-style ASSEMBLY garage: part lists, mech preview, live spec deltas" },

	-- ===================== session & system (batch 2) =====================
	{ id = "systemAlert", module = "SystemAlertScreen", layer = "Overlay", exclusive = false, tags = { "system" }, description = "Data-loss / session-lock / kick / maintenance / AFK alerts" },
	{ id = "credits", module = "CreditsScreen", hidesHUD = true, tags = { "system" }, description = "Scrolling credits with skip" },
	{ id = "photoMode", module = "PhotoModeScreen", hidesHUD = true, tags = { "system" }, description = "Photo mode: FOV, filters, frames, hide-HUD" },
	{ id = "iconBrowser", module = "IconBrowserScreen", tags = { "dev" }, description = "Icon archive browser with coverage + variants" },
} :: { Entry }

local byId: { [string]: Entry } = {}
for _, entry in ScreenManifest.Entries do
	byId[entry.id] = entry
end

function ScreenManifest.Get(id: string): Entry?
	return byId[id]
end

function ScreenManifest.Ids(): { string }
	local ids = {}
	for _, entry in ScreenManifest.Entries do
		if entry.enabled ~= false then
			table.insert(ids, entry.id)
		end
	end
	table.sort(ids)
	return ids
end

-- Every id carrying a tag — how tooling (and the theme previewer) walks a
-- domain without hardcoding a list.
function ScreenManifest.ByTag(tag: string): { string }
	local ids = {}
	for _, entry in ScreenManifest.Entries do
		if entry.enabled ~= false and entry.tags then
			for _, t in entry.tags do
				if t == tag then
					table.insert(ids, entry.id)
					break
				end
			end
		end
	end
	table.sort(ids)
	return ids
end

-- The exclusive set: opening one closes the others (doc §7.4 "one panel open
-- at a time"). Screens default to exclusive; HUD-band and modal entries opt out.
function ScreenManifest.ExclusiveSet(): { [string]: boolean }
	local set = {}
	for _, entry in ScreenManifest.Entries do
		if entry.enabled ~= false and entry.exclusive ~= false then
			set[entry.id] = true
		end
	end
	return set
end

return ScreenManifest
