--!strict
-- Iconography & imagery (UI_DESIGN_DOCUMENT.md §10).
--
-- This module is now a THIN FACADE over the icon archive: the artwork itself
-- lives in Icons/IconCatalog (the whole Gvesster pack, indexed) and is resolved
-- by Icons/IconArchive (semantic name -> best available variant). Keeping the
-- old surface (UIAssets.Icons.Cash, UIAssets.Icon, UIAssets.SunburstBehind)
-- means every screen written against it picked up the new pack without an edit.
--
-- Add artwork by uploading more of the pack and regenerating the catalog — not
-- by pasting asset ids here. There are no hardcoded item ids left below except
-- the sunburst glow motif and the click sound, which are house assets rather
-- than pack icons.

local IconArchive = require(script.Parent.Parent.Icons.IconArchive)

local UIAssets = {}

-- The house glow motif: tinted red behind the shop cart, gold behind promos and
-- reveals, white @ 0.7 behind previews — always spinning 45–60°/s, and only
-- while on screen (doc §10).
UIAssets.Sunburst = "rbxassetid://87843916320220"

-- Semantic name -> live asset id, resolved through the archive at require time.
-- Indexing a name the archive can't serve yields nil, and every consumer of a
-- possibly-missing icon goes through UIAssets.Icon, which falls back to a glyph.
local ICON_NAMES = {
	"Robux", "Bux", "Cash", "CashPile", "CashChest", "GemPile", "GemChest",
	"Trophy", "Gift", "Star", "Crown", "Clover", "LevelUp", "Check", "Lock",
	"Close", "Cart", "Settings", "Bell", "Heart", "Crate", "Chest", "Key",
	"Medal", "Ticket", "Book", "Shield", "Sword", "Fire", "Sparkle",
}

-- Names above that the pack expresses under a different semantic role.
local ICON_ALIAS: { [string]: string } = {
	CashPile = "cash",
	CashChest = "chest",
	GemPile = "currency.gem",
	GemChest = "chest",
	Clover = "luck",
	LevelUp = "levelUp",
}

local icons: { [string]: string } = {}
for _, name in ICON_NAMES do
	local key = ICON_ALIAS[name] or string.lower(string.sub(name, 1, 1)) .. string.sub(name, 2)
	local id = IconArchive.Id(key)
	if id then
		icons[name] = id
	end
end
UIAssets.Icons = icons

-- Glyph fallbacks are the archive's (booth iconography is pure Unicode in
-- FredokaOne, doc §10); kept here so older call sites still find them.
UIAssets.Glyphs = IconArchive.Glyphs

-- One boxless icon with the graceful fallback chain (image -> glyph), so a
-- missing upload degrades instead of leaving a hole.
function UIAssets.Icon(parent: Instance, key: string, sizePx: number): GuiObject
	-- Accept both the legacy PascalCase names and archive-native keys.
	local archiveKey = ICON_ALIAS[key] or (string.lower(string.sub(key, 1, 1)) .. string.sub(key, 2))
	if IconArchive.Id(archiveKey) then
		return IconArchive.Image(parent, archiveKey, sizePx)
	end
	return IconArchive.Image(parent, key, sizePx)
end

-- The spinning sunburst glow: parent it behind a preview/promo (lower ZIndex).
-- Returns the label plus its spin connection so callers disconnect on teardown.
function UIAssets.SunburstBehind(parent: GuiObject, tint: Color3, transparency: number, degreesPerSecond: number?): (ImageLabel, RBXScriptConnection)
	local UIChrome = require(script.Parent.Parent.UIChrome)
	local burst = Instance.new("ImageLabel")
	burst.Name = "Sunburst"
	burst.BackgroundTransparency = 1
	burst.Image = UIAssets.Sunburst
	burst.ImageColor3 = tint
	burst.ImageTransparency = transparency
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.Position = UDim2.fromScale(0.5, 0.5)
	burst.Size = UDim2.fromScale(1.15, 1.15)
	burst.ZIndex = math.max(1, parent.ZIndex - 1)
	burst.Parent = parent
	local spin = UIChrome.Spin(burst, degreesPerSecond or 45)
	return burst, spin
end

return UIAssets
