--!strict
-- Layout packs: named bundles of *arrangement* choices, orthogonal to themes.
-- A theme decides how things look (colour/font/motion); a pack decides how the
-- same data is arranged — the entry focal point, grid vs list, and where the
-- currency + nav rail live. Any theme combines with any pack.
--
-- Each pack points its shop at an EntryLayoutConfig spec id, so the six packs
-- below reuse one renderer and stay mutually consistent. Add a pack by
-- appending here; add a new *look* by adding a spec in EntryLayoutConfig.

local Types = require(script.Parent.Parent.Types)

local UIPackConfig = {}

UIPackConfig.DefaultPackId = "Default"

UIPackConfig.Packs = {
	-- ONE pack: the current layout IS the default. Layout variants were
	-- removed from the selector (layouts get configured later, per the owner);
	-- the pack machinery stays so per-game layout tuning remains possible.
	{
		Id = "Default",
		DisplayName = "Default",
		Shop = { Container = "Grid", Columns = 4, CardHeight = 200, EntryLayout = "StandardCard", ShowCategoryBar = true },
		HUD = { Compact = false, ShowObjectives = true, Scale = 1, MoneyRegion = "TopRight", MoneyIconSide = "Left" },
		Nav = { Side = "Left", Vertical = "Center" },
		Tutorial = { ShowStepList = true },
		Modal = { WidthScale = 0.42 },
	},
} :: { Types.UIPack }

function UIPackConfig.GetById(id: string): Types.UIPack?
	for _, pack in UIPackConfig.Packs do
		if pack.Id == id then
			return pack
		end
	end
	return nil
end

return UIPackConfig
