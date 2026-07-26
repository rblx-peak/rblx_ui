--!strict
-- BuildPaletteState — the ONE source of truth for the build hotbar + palette
-- (Minecraft-creative semantics: the palette is infinite, a hotbar slot holds
-- a REFERENCE to an item, placing never consumes anything).
--
-- Two surfaces render this state and stay in sync purely through it:
--   * HotbarScreen        — the persistent bottom toolbar (select with 1-9)
--   * BuildInventoryScreen — the palette panel that opens above the toolbar
--
-- Neither surface talks to the other; they both subscribe here. A future
-- build system reads GetSelected() to know which brick the player places.

local UISignal = require(script.Parent.Parent.UISignal)

local BuildPaletteState = {}

export type Item = {
	id: string,
	name: string,
	icon: string, -- IconArchive key (placeholder art)
	color: Color3, -- tile backdrop tint so bricks read apart at a glance
}

BuildPaletteState.SLOT_COUNT = 9

-- Fired with (slotIndex) after a single slot changes, or () after a bulk
-- change (swap) — listeners just re-render all slots either way.
BuildPaletteState.SlotsChanged = UISignal.new()
-- Fired with (selectedIndex) after the selected slot changes.
BuildPaletteState.SelectionChanged = UISignal.new()

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function item(id: string, name: string, icon: string, color: Color3): Item
	return { id = id, name = name, icon = icon, color = color }
end

-- The demo palette, grouped for the inventory's top nav. Placeholder art via
-- IconArchive keys; swap for real brick renders later without touching UI.
local CATEGORIES: { { name: string, items: { Item } } } = {
	{
		name = "Blocks",
		items = {
			item("stone", "Stone Brick", "rock", rgb(128, 132, 138)),
			item("crate", "Crate", "crate", rgb(178, 128, 66)),
			item("chest", "Chest", "chest", rgb(150, 100, 48)),
			item("ingot", "Metal Block", "ingot", rgb(180, 186, 196)),
			item("crystal", "Crystal Block", "crystal", rgb(120, 190, 235)),
			item("box", "Cardboard Box", "box", rgb(196, 158, 104)),
			item("gem", "Gem Block", "gem", rgb(96, 210, 160)),
		},
	},
	{
		name = "Nature",
		items = {
			item("tree", "Tree", "tree", rgb(84, 160, 90)),
			item("leaf", "Leaf Pile", "leaf", rgb(110, 185, 92)),
			item("water", "Water", "water", rgb(70, 140, 220)),
			item("fire", "Fire", "fire", rgb(235, 120, 52)),
			item("cloud", "Cloud", "cloud", rgb(210, 220, 235)),
			item("sun", "Sun Lamp", "sun", rgb(245, 200, 70)),
			item("moon", "Moon Lamp", "moon", rgb(170, 175, 220)),
		},
	},
	{
		name = "Decor",
		items = {
			item("torch", "Torch", "torch", rgb(230, 160, 60)),
			item("paint", "Paint Bucket", "paintbucket", rgb(200, 96, 180)),
			item("balloon", "Balloon", "balloon", rgb(230, 90, 110)),
			item("book", "Bookshelf", "book", rgb(140, 104, 190)),
			item("clock", "Clock", "clock", rgb(215, 185, 120)),
			item("bell", "Bell", "bell", rgb(235, 200, 90)),
		},
	},
	{
		name = "Special",
		items = {
			item("portal", "Portal", "portal", rgb(150, 90, 230)),
			item("rainbow", "Rainbow Bridge", "rainbow", rgb(240, 140, 200)),
			item("bolt", "Power Cell", "bolt", rgb(250, 215, 80)),
			item("teleporter", "Teleporter", "teleporter", rgb(90, 200, 230)),
			item("explosion", "TNT", "explosion", rgb(225, 80, 70)),
			item("planet", "Gravity Orb", "planet", rgb(110, 130, 235)),
		},
	},
}

local itemsById: { [string]: Item } = {}
for _, category in CATEGORIES do
	for _, entry in category.items do
		itemsById[entry.id] = entry
	end
end

-- Slots hold item ids (nil = empty). Seeded so the mock reads instantly.
local slots: { Item? } = {}
for i, id in { "stone", "crate", "ingot", "crystal", "tree", "water", "torch" } do
	slots[i] = itemsById[id]
end

local selectedIndex = 1

-- ---- palette (read-only) ----------------------------------------------

function BuildPaletteState.Categories(): { { name: string, items: { Item } } }
	return CATEGORIES
end

function BuildPaletteState.FindItem(id: string): Item?
	return itemsById[id]
end

-- ---- hotbar slots ------------------------------------------------------

function BuildPaletteState.GetSlot(index: number): Item?
	return slots[index]
end

function BuildPaletteState.GetSlots(): { Item? }
	return table.clone(slots)
end

function BuildPaletteState.SetSlot(index: number, entry: Item?)
	if index < 1 or index > BuildPaletteState.SLOT_COUNT then
		return
	end
	slots[index] = entry
	BuildPaletteState.SlotsChanged:Fire(index)
end

function BuildPaletteState.SwapSlots(a: number, b: number)
	if a == b then
		return
	end
	slots[a], slots[b] = slots[b], slots[a]
	BuildPaletteState.SlotsChanged:Fire()
end

-- ---- selection ---------------------------------------------------------

function BuildPaletteState.GetSelectedIndex(): number
	return selectedIndex
end

-- The item the player is "holding" — what a build system would place.
function BuildPaletteState.GetSelected(): Item?
	return slots[selectedIndex]
end

function BuildPaletteState.Select(index: number)
	if index < 1 or index > BuildPaletteState.SLOT_COUNT or index == selectedIndex then
		return
	end
	selectedIndex = index
	BuildPaletteState.SelectionChanged:Fire(index)
end

return BuildPaletteState
