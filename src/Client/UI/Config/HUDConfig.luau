--!strict
-- Declarative description of the Pottery Clash HUD. Each element names a
-- value key (filled at runtime by GameHUDScreen:Update), a display format,
-- and a screen region (doc §7.2: currency pills bottom-left, status line +
-- round timer top-centre).
--
-- Currency ids are exactly "Cash"/"Bux" so CurrencyChanged pushes (balances
-- keyed with capitalised currency ids) land straight on the HUD pills.

local Types = require(script.Parent.Parent.Types)

local HUDConfig = {}

-- Regions map to anchored containers the HUD screen creates.
-- "TopLeft" | "TopCenter" | "TopRight" | "BottomLeft" | "BottomCenter"
HUDConfig.Elements = {
	{ id = "Cash", format = "Number", region = "BottomLeft", order = 1, labelKey = "currency.cash", colorToken = "Success" },
	{ id = "Bux", format = "Number", region = "BottomLeft", order = 2, labelKey = "currency.bux", colorToken = "Primary" },
	{ id = "wave", format = "Number", region = "TopCenter", order = 1, labelKey = "hud.wave", colorToken = "Accent" },
	{ id = "timer", format = "Time", region = "TopCenter", order = 2, labelKey = "hud.timer", colorToken = "Accent" },
} :: { Types.HUDElement }

HUDConfig.DefaultValues = {
	Cash = 750,
	Bux = 120,
	wave = 3,
	timer = 754,
	-- Overhead-demo feeds (ClientHandler's nameplate/vitals demo reads these;
	-- the HUD itself ignores ids it doesn't render).
	level = 3,
	health = 86,
	mana = 54,
}

function HUDConfig.GetElementsForRegion(region: string): { Types.HUDElement }
	local out = {}
	for _, element in HUDConfig.Elements do
		if element.region == region then
			table.insert(out, element)
		end
	end
	table.sort(out, function(a, b)
		return a.order < b.order
	end)
	return out
end

-- Seconds -> "M:SS" for Time-format elements (same M:SS logic the HUD's
-- round timer uses via UIChrome.FormatCountdown for sub-hour values).
function HUDConfig.FormatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

return HUDConfig
