--!strict
-- Single source of truth for everything sold in the shop: currencies,
-- categories, items and price helpers. The server validates purchases against
-- this module; the client renders from it. Tune the shop by editing data here
-- only — no gameplay script should hardcode an item or price.

local Types = require(script.Parent.Parent.Types)

local ShopConfig = {}

ShopConfig.StartingBalances = {
	Cash = 750,
	Bux = 120,
} :: Types.CurrencyBalances

-- Cash = green, Bux = blue, everywhere (doc §3.3). colorToken keys into
-- theme.Semantic.Currency; iconId is the uploaded flat cartoon icon set
-- (doc §10), with the emoji as the graceful-fallback glyph.
ShopConfig.Currencies = {
	-- iconId is a LAST-RESORT literal: the client resolves currency art through
	-- Icons/IconArchive by colorToken ("currency.cash"), which picks the
	-- semantically-correct colourway (green cash, blue bux) from the pack.
	Cash = { id = "Cash", nameKey = "currency.cash", icon = "💰", iconId = "rbxassetid://79313435115123", colorToken = "Cash", order = 1 },
	Bux = { id = "Bux", nameKey = "currency.bux", icon = "💎", iconId = "rbxassetid://79025429735979", colorToken = "Bux", order = 2 },
} :: { [string]: Types.CurrencyDef }

ShopConfig.Categories = {
	{ id = "featured", nameKey = "shop.category.featured", order = 1 },
	{ id = "boosts", nameKey = "shop.category.boosts", order = 2 },
	{ id = "cosmetics", nameKey = "shop.category.cosmetics", order = 3 },
} :: { Types.ShopCategory }

ShopConfig.Items = {
	-- Featured (a fuller set so grids fill several rows and scrolling is exercised)
	{ id = "starter_bundle", nameKey = "item.starter_bundle.name", descriptionKey = "item.starter_bundle.desc", iconId = "", iconKey = "gift", price = 99, currencyType = "Cash", category = "featured", tags = { "Sale" } },
	{ id = "mega_bundle", nameKey = "item.mega_bundle.name", descriptionKey = "item.mega_bundle.desc", iconId = "", iconKey = "chest", price = 120, currencyType = "Bux", category = "featured", tags = { "Popular", "Limited" } },
	{ id = "mystery_crate", nameKey = "item.mystery_crate.name", descriptionKey = "item.mystery_crate.desc", iconId = "", iconKey = "crate", price = 500, currencyType = "Cash", category = "featured", tags = { "New" } },
	{ id = "value_pack", nameKey = "item.mega_bundle.name", descriptionKey = "item.mega_bundle.desc", iconId = "", iconKey = "box", price = 260, currencyType = "Cash", category = "featured", tags = { "Popular" } },
	{ id = "daily_deal", nameKey = "item.starter_bundle.name", descriptionKey = "item.starter_bundle.desc", iconId = "", iconKey = "calendar", price = 60, currencyType = "Cash", category = "featured", tags = { "Sale", "Limited" } },
	{ id = "legend_crate", nameKey = "item.mystery_crate.name", descriptionKey = "item.mystery_crate.desc", iconId = "", iconKey = "crate", iconGolden = true, price = 900, currencyType = "Bux", category = "featured", tags = { "Rare" } },
	{ id = "coin_pouch", nameKey = "item.starter_bundle.name", descriptionKey = "item.starter_bundle.desc", iconId = "", iconKey = "currency.coin", price = 40, currencyType = "Cash", category = "featured" },
	{ id = "gem_chest", nameKey = "item.mega_bundle.name", descriptionKey = "item.mega_bundle.desc", iconId = "", iconKey = "gemChest", price = 75, currencyType = "Bux", category = "featured", tags = { "New" } },
	{ id = "season_pass", nameKey = "item.mega_bundle.name", descriptionKey = "item.mega_bundle.desc", iconId = "", iconKey = "ticket", price = 480, currencyType = "Cash", category = "featured", tags = { "Popular", "New" } },
	{ id = "lucky_box", nameKey = "item.mystery_crate.name", descriptionKey = "item.mystery_crate.desc", iconId = "", iconKey = "luckyBlock", price = 130, currencyType = "Cash", category = "featured", tags = { "Sale" } },
	{ id = "vip_bundle", nameKey = "item.mega_bundle.name", descriptionKey = "item.mega_bundle.desc", iconId = "", iconKey = "crown", iconGolden = true, price = 640, currencyType = "Bux", category = "featured", tags = { "Rare", "Limited" } },
	{ id = "welcome_gift", nameKey = "item.starter_bundle.name", descriptionKey = "item.starter_bundle.desc", iconId = "", iconKey = "gift", price = 20, currencyType = "Cash", category = "featured", tags = { "New" } },

	-- Boosts
	{ id = "speed_cola", nameKey = "item.speed_cola.name", descriptionKey = "item.speed_cola.desc", iconId = "", iconKey = "potion", price = 150, currencyType = "Cash", category = "boosts", tags = { "New" } },
	{ id = "shield_generator", nameKey = "item.shield_generator.name", descriptionKey = "item.shield_generator.desc", iconId = "", iconKey = "shield", price = 320, currencyType = "Cash", category = "boosts", tags = { "Popular" } },
	{ id = "double_xp", nameKey = "item.double_xp.name", descriptionKey = "item.double_xp.desc", iconId = "", iconKey = "star", price = 25, currencyType = "Bux", category = "boosts", tags = { "Limited" } },

	-- Cosmetics
	{ id = "golden_crown", nameKey = "item.golden_crown.name", descriptionKey = "item.golden_crown.desc", iconId = "", iconKey = "crown", iconGolden = true, price = 90, currencyType = "Bux", category = "cosmetics", tags = { "Rare" } },
	{ id = "pixel_shades", nameKey = "item.pixel_shades.name", descriptionKey = "item.pixel_shades.desc", iconId = "", iconKey = "outfit", price = 220, currencyType = "Cash", category = "cosmetics" },
	{ id = "rainbow_trail", nameKey = "item.rainbow_trail.name", descriptionKey = "item.rainbow_trail.desc", iconId = "", iconKey = "rainbow", price = 45, currencyType = "Bux", category = "cosmetics", tags = { "New", "Rare" } },
} :: { Types.ShopItem }

function ShopConfig.GetItemById(itemId: string): Types.ShopItem?
	for _, item in ShopConfig.Items do
		if item.id == itemId then
			return item
		end
	end
	return nil
end

function ShopConfig.GetItemsForCategory(categoryId: string): { Types.ShopItem }
	local items = {}
	for _, item in ShopConfig.Items do
		if item.category == categoryId then
			table.insert(items, item)
		end
	end
	return items
end

function ShopConfig.GetOrderedCategories(): { Types.ShopCategory }
	local categories = table.clone(ShopConfig.Categories)
	table.sort(categories, function(a, b)
		return a.order < b.order
	end)
	return categories
end

function ShopConfig.GetOrderedCurrencies(): { Types.CurrencyDef }
	local currencies = {}
	for _, currency in ShopConfig.Currencies do
		table.insert(currencies, currency)
	end
	table.sort(currencies, function(a, b)
		return a.order < b.order
	end)
	return currencies
end

-- "1234567" -> "1,234,567"
function ShopConfig.FormatPrice(amount: number): string
	local formatted = tostring(math.floor(amount))
	while true do
		local replaced
		formatted, replaced = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then
			break
		end
	end
	return formatted
end

function ShopConfig.CanAfford(balances: Types.CurrencyBalances, item: Types.ShopItem): boolean
	return (balances[item.currencyType] or 0) >= item.price
end

return ShopConfig
