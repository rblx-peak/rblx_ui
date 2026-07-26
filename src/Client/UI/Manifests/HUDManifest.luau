--!strict
-- THE HUD WIDGET CATALOG. Every persistent gameplay widget the system can
-- build, declared as data — the HUD half of what ScreenManifest is for panels.
--
-- Widgets are NOT screens: they own no ScreenGui, they parent into the shared
-- HUD layer (Framework/Layers.Get("HUD")) at the anchor slot declared here.
-- Placement therefore lives in ONE file: a game re-lays-out its HUD by editing
-- offsets in this manifest, never by editing widget code.
--
-- Fields:
--   id            the string a host uses to look a widget up
--   module        ModuleScript name inside src/Client/UI/HUD/
--   anchor        which corner/edge of the HUD layer the widget hangs off
--   offset        px from that anchor at the 1650×1020 baseline (doc §7.1);
--                 negative on the axis the anchor pins to (right/bottom)
--   size          fixed px at the same baseline. (0, 0) means FILL THE LAYER —
--                 used by full-bleed overlays (damage numbers) that project
--                 world positions and must cover the whole viewport.
--   order         paint order inside the HUD band (doc §7.3: lobby chrome
--                 20–24); also the sort order ByAnchor returns
--   enabled       false = this game doesn't use it; never required
--   hideWhenFull  ambient meters that fade out at 100% and snap back on use
--   tags          free-form grouping for tooling
--
-- The offsets below follow the doc §7.2 screen map exactly where it speaks:
-- top-centre status line y=14 (objective ticker), secondary widget y=62
-- (compass), round timer y=118, bottom-centre working dock y=−70 (ability
-- bar). The vitals stack sits bottom-left ABOVE the §7.2 currency pill row
-- (y=−14, 56 tall), and the killfeed hangs under the §7.2 top-right action
-- row (y=14, 52 tall).

local HUDManifest = {}

export type Anchor =
	"TopLeft" | "TopCenter" | "TopRight"
	| "BottomLeft" | "BottomCenter" | "BottomRight"
	| "LeftEdge" | "RightEdge"

export type Entry = {
	id: string,
	module: string,
	anchor: Anchor,
	offset: Vector2,
	size: Vector2,
	order: number,
	enabled: boolean?,
	hideWhenFull: boolean?,
	tags: { string }?,
	description: string?,
}

HUDManifest.Entries = {
	-- ===================== vitals (bottom left, above the pills) =========
	{
		id = "health",
		module = "HealthBarWidget",
		anchor = "BottomLeft",
		offset = Vector2.new(16, -78),
		size = Vector2.new(420, 30),
		order = 1,
		tags = { "vitals" },
		description = "Segmented health with a regen ghost trail and damage flash",
	},
	{
		id = "stamina",
		module = "StaminaBarWidget",
		anchor = "BottomLeft",
		offset = Vector2.new(16, -114),
		size = Vector2.new(420, 14),
		order = 2,
		hideWhenFull = true,
		tags = { "vitals" },
		description = "Thin gold stamina meter; fades out while full",
	},
	{
		id = "xp",
		module = "XPBarWidget",
		anchor = "BottomLeft",
		offset = Vector2.new(16, -136),
		size = Vector2.new(460, 46),
		order = 3,
		tags = { "progression" },
		description = "Circular level badge + XP ruler + 'x / y' label",
	},

	-- ===================== action dock (bottom centre) ===================
	{
		id = "abilities",
		module = "AbilityBarWidget",
		anchor = "BottomCenter",
		offset = Vector2.new(0, -58),
		size = Vector2.new(460, 96),
		order = 4,
		tags = { "combat" },
		description = "Five ability slots: cooldown wipe, charge pips, global dim",
	},
	{
		id = "keyHints",
		module = "KeyHintsWidget",
		anchor = "BottomCenter",
		offset = Vector2.new(0, -14),
		size = Vector2.new(760, 34),
		order = 5,
		tags = { "context" },
		description = "Contextual [KEY] Action chips, rebuilt per input mode",
	},
	{
		id = "interact",
		module = "InteractionPromptWidget",
		anchor = "BottomCenter",
		offset = Vector2.new(0, -300),
		size = Vector2.new(340, 84),
		order = 6,
		tags = { "context" },
		description = "[E] OPEN chip with hold-progress fill and input-mode swap",
	},

	-- ===================== status (top) ==================================
	{
		id = "buffs",
		module = "BuffTrayWidget",
		anchor = "TopLeft",
		offset = Vector2.new(16, 16),
		size = Vector2.new(540, 76),
		order = 7,
		tags = { "status" },
		description = "Buff/debuff chips with stacks and 1Hz remaining time",
	},
	{
		id = "objective",
		module = "ObjectiveTickerWidget",
		anchor = "TopCenter",
		offset = Vector2.new(0, 14),
		size = Vector2.new(640, 44),
		order = 8,
		tags = { "status" },
		description = "Gold objective line + ice-blue hint (doc §7.2 y=14)",
	},
	{
		id = "compass",
		module = "CompassWidget",
		anchor = "TopCenter",
		offset = Vector2.new(0, 62),
		size = Vector2.new(520, 32),
		order = 9,
		tags = { "nav" },
		description = "Yaw-driven compass tape with waypoint pips (doc §7.2 y=62)",
	},
	{
		id = "timer",
		module = "TimerWidget",
		anchor = "TopCenter",
		offset = Vector2.new(0, 118),
		size = Vector2.new(220, 60),
		order = 10,
		tags = { "match" },
		description = "Fixed 220×60 round timer with the §5.3 final-10s panic",
	},

	-- ===================== feedback ======================================
	{
		id = "killfeed",
		module = "KillfeedWidget",
		anchor = "TopRight",
		offset = Vector2.new(-16, 78),
		size = Vector2.new(420, 200),
		order = 11,
		tags = { "feedback" },
		description = "Pooled kill rows, newest on top, expiring after 5s",
	},
	{
		id = "damage",
		module = "DamageNumbersWidget",
		anchor = "TopLeft",
		offset = Vector2.new(0, 0),
		size = Vector2.new(0, 0), -- fills the layer: it projects world → screen
		order = 12,
		tags = { "feedback" },
		description = "Pooled floating damage / crit / heal numbers",
	},

	-- ===================== gameplay kit (batch 2) ========================
	-- Top-right column reads top to bottom: score (y=14) → killfeed (y=78,
	-- 200 tall) → minimap under it (y=292).
	{
		id = "score",
		module = "ScoreWidget",
		anchor = "TopRight",
		offset = Vector2.new(-16, 14),
		size = Vector2.new(320, 60),
		order = 2,
		tags = { "match" },
		description = "SCORE ticker count-up, decaying multiplier chip, pooled +N floaters",
	},
	{
		id = "minimap",
		module = "MinimapWidget",
		anchor = "TopRight",
		offset = Vector2.new(-16, 292),
		size = Vector2.new(220, 220),
		order = 13,
		tags = { "nav" },
		description = "North-up square minimap: pooled markers, yaw arrow, 2-level zoom",
	},
	{
		id = "waypoints",
		module = "WaypointMarkerWidget",
		anchor = "TopLeft",
		offset = Vector2.new(0, 0),
		size = Vector2.new(0, 0), -- fills the layer: it projects world → screen
		order = 14,
		tags = { "nav" },
		description = "Pooled world waypoint markers with edge-clamped off-screen arrows",
	},
	{
		id = "crosshair",
		module = "CrosshairWidget",
		anchor = "TopLeft",
		offset = Vector2.new(0, 0),
		size = Vector2.new(0, 0), -- fills the layer: it centres its own reticle
		order = 15,
		enabled = false, -- genre-specific: a shooter flips it on
		tags = { "combat" },
		description = "Dynamic spread crosshair with fire kick and pooled hitmarkers",
	},
	{
		id = "ammo",
		module = "AmmoWidget",
		anchor = "BottomRight",
		offset = Vector2.new(-16, -16),
		size = Vector2.new(260, 96),
		order = 16,
		enabled = false, -- genre-specific: a shooter flips it on
		tags = { "combat" },
		description = "Mag / reserve readout, low-ammo flash, reload sweep, RELOAD chip",
	},
	{
		id = "zoneBanner",
		module = "ZoneBannerWidget",
		anchor = "TopLeft",
		offset = Vector2.new(0, 0),
		size = Vector2.new(0, 0), -- fills the layer: it centres its own banner
		order = 17,
		tags = { "feedback" },
		description = "Queued zone-entry titles: grapheme reveal, 2.5s hold, hard-hide",
	},
} :: { Entry }

local byId: { [string]: Entry } = {}
for _, entry in HUDManifest.Entries do
	byId[entry.id] = entry
end

function HUDManifest.Get(id: string): Entry?
	return byId[id]
end

function HUDManifest.Ids(): { string }
	local ids = {}
	for _, entry in HUDManifest.Entries do
		if entry.enabled ~= false then
			table.insert(ids, entry.id)
		end
	end
	table.sort(ids)
	return ids
end

-- Every enabled widget hanging off one anchor, in paint order — how a host
-- lays out (or nudges) a whole corner of the HUD without hardcoding a list.
function HUDManifest.ByAnchor(anchor: Anchor): { Entry }
	local out = {}
	for _, entry in HUDManifest.Entries do
		if entry.enabled ~= false and entry.anchor == anchor then
			table.insert(out, entry)
		end
	end
	table.sort(out, function(a, b)
		return a.order < b.order
	end)
	return out
end

return HUDManifest
