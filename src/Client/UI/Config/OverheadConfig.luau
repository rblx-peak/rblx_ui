--!strict
-- Data-driven config for the above-character billboard UI (nameplate + vitals).
-- Decides which rows show, the bar order/colours, and the *location presets*
-- that place the billboard relative to the head — swapping location is a one-word
-- change here or a single UIOverheadController:SetLocation call at runtime.
--
-- Pottery Clash world-space grammar (UI_DESIGN_DOCUMENT.md §9): the billboard is
-- a FIXED PX OFFSET size now (no boxes, just stacked outlined text), so Width /
-- RowHeight / NameHeight below are px at the billboard's native resolution —
-- NOT studs. Only the Locations presets remain in studs (world offsets).

local OverheadConfig = {}

-- StudsOffsetWorldSpace presets. Y is height above the attach part's center;
-- Z pushes it toward the camera-facing front. Doc §9: nameplates sit +3 studs
-- over the head.
OverheadConfig.Locations = {
	Above = Vector3.new(0, 3, 0), -- the spec placement: +3 studs over the head
	High = Vector3.new(0, 4.2, 0), -- floats higher, good with big bars
	Head = Vector3.new(0, 2.2, 0), -- tight to the head
	Front = Vector3.new(0, 3, -1.4), -- tilted toward the viewer
	Feet = Vector3.new(0, -3.2, 0), -- ring-of-stats at the feet
}

OverheadConfig.DefaultLocation = "Above"

-- Which bars appear under the name, in order. Each maps a value key to a theme
-- colour token + icon. Drop or reorder rows to taste; add a bar by appending.
-- colorToken must be a key of Types.UIThemeColors (Error = red, Primary = blue).
OverheadConfig.Bars = {
	{ id = "health", colorToken = "Error", icon = "❤️", maxValue = 100 },
	{ id = "mana", colorToken = "Primary", icon = "🔷", maxValue = 100 },
}

OverheadConfig.ShowNameplate = true
OverheadConfig.ShowLevel = true

-- Billboard sizing in PX (the BillboardGui is offset-sized per doc §9).
-- The nameplate stack is 300×80: gold "LV %d" 22 / white DisplayName 24 /
-- money-green cash 20 (= 66px, NameHeight), then each vitals ruler takes a
-- 7px row (6px track + 1px air) — 66 + 2×7 = the spec's fixed 80px height.
OverheadConfig.Width = 300
OverheadConfig.RowHeight = 7
OverheadConfig.NameHeight = 66

return OverheadConfig
