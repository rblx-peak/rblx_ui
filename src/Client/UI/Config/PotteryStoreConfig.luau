--!strict
-- PotteryStoreConfig — the DATA behind every Pottery Battles shop surface:
-- the chair catalog and its rarity ladder, the deterministic rotating-shop
-- window, the pass/bundle/Bux catalog with its promo badges, the title
-- progression, and the group-gated free reward.
--
-- WHY ONE MODULE: four screens (rotatingShop, skinsGallery, premiumShop,
-- titles) render the SAME catalog from different angles. The shipped game
-- keeps this split across ChairConfig / ShopConfig / RotatingShop / Titles so
-- the server and client can never disagree; the collection has no server, so
-- the four tables land here together and the screens hold no literals.
--
-- COPY VOICE (GirlyPop law 5): the source game SHOUTS — "BEST DEAL!",
-- "REFRESHES IN:", "UNLOCKED TITLES: %d/%d", "EQUIPPED", "LOCKED". Every one
-- of those surfaces survives here with the SAME meaning, the same placement
-- and the same numbers; only the shouting is gone, because this pack's named
-- failure mode is shouting at its audience. Numeric FORMATS are untouched
-- (%02d:%02d:%02d, %d/%d) — they are data, not tone. Each de-shouted label
-- records its source string in a comment so the mapping is auditable.
--
-- NOTHING HERE TOUCHES ROBLOX MONETIZATION. Prices are display numbers for a
-- browser screen; a real build terminates in MarketplaceService prompts and
-- re-checks every grant server-side.

local PotteryStoreConfig = {}

-- ========================================================================
-- Rarity ladder
-- ========================================================================

export type Look = {
	color: Color3,
	material: Enum.Material,
	reflectance: number,
	effect: string?,
}

export type Chair = {
	id: string,
	name: string,
	rarity: string,
	source: string, -- "crate" | "robux" | "event"
	buxPrice: number?,
	robuxPrice: number,
	shardPrice: number,
	iconKey: string, -- IconArchive semantic role for the flat-art fallback
	look: Look,
}

export type Title = { name: string, stat: string, req: number }

export type Pass = {
	id: string,
	title: string,
	desc: string,
	bullets: { string }?,
	robux: number,
	effect: string,
	iconKey: string,
	badge: string?,
}

export type BuxPack = { id: string, amount: number, robux: number, iconKey: string, badge: string?, badgeTone: string? }

export type BundleSlot = { kind: string, chairId: string?, iconKey: string?, caption: string }

export type Bundle = {
	id: string,
	title: string,
	tagline: string,
	robux: number,
	wasRobux: number?,
	valueLine: string,
	ownedAttribute: string,
	slots: { BundleSlot },
	rainbow: boolean?,
	badge: string?,
}

PotteryStoreConfig.Rarities = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Exclusive" }

PotteryStoreConfig.Rank = {} :: { [string]: number }
for index, rarity in PotteryStoreConfig.Rarities do
	PotteryStoreConfig.Rank[rarity] = index
end

-- The crate weights the shipped game rolls on. Carried so a shop card can
-- print a real drop chance next to a rarity instead of a bare word — density
-- goes UP, never down (pack law 6).
PotteryStoreConfig.RarityWeights = {
	Common = 50,
	Uncommon = 9.76,
	Rare = 3.417,
	Epic = 1.22,
	Legendary = 0.61,
	Mythic = 0.122,
	Exclusive = 0, -- never in crates
} :: { [string]: number }

-- Realised drop share per tier, normalised across everything a crate can roll.
function PotteryStoreConfig.DropChance(rarity: string): number
	local total = 0
	for _, weight in PotteryStoreConfig.RarityWeights do
		total += weight
	end
	if total <= 0 then
		return 0
	end
	return (PotteryStoreConfig.RarityWeights[rarity] or 0) / total
end

-- ========================================================================
-- Chairs — the cosmetic catalog every surface previews
-- ========================================================================

local function look(color: Color3, material: Enum.Material, reflectance: number, effect: string?): Look
	return { color = color, material = material, reflectance = reflectance, effect = effect }
end

-- Robux reference price by tier; a chair may override with its own robuxPrice.
local ROBUX_BY_RARITY: { [string]: number } =
	{ Common = 9, Uncommon = 19, Rare = 39, Epic = 59, Legendary = 79, Mythic = 99, Exclusive = 129 }
-- Shards are the CRAFT path (the source's ◈ currency): a chair costs its Bux
-- price in shards at a 1.6x craft premium, so crafting never undercuts buying.
local SHARD_MULTIPLIER = 1.6

-- The literal list omits robuxPrice and shardPrice: both are DERIVED below
-- from rarity, so writing them by hand is 46 opportunities for the ladder to
-- disagree with itself. The cast is the honest way to say "these two fields
-- arrive on the next pass" without loosening the exported Chair type, which
-- every consumer reads as complete.
local chairs: { Chair } = ({
	-- Common (exclusives near the bottom carry NO buxPrice: they are not for
	-- sale, which is why `buxPrice` is optional on the Chair type)
	{ id = "woodenStool", name = "Wooden Stool", rarity = "Common", source = "crate", buxPrice = 40, iconKey = "box",
		look = look(Color3.fromRGB(196, 150, 96), Enum.Material.WoodPlanks, 0) },
	{ id = "plasticChair", name = "Plastic Chair", rarity = "Common", source = "crate", buxPrice = 40, iconKey = "card",
		look = look(Color3.fromRGB(180, 184, 196), Enum.Material.SmoothPlastic, 0) },
	{ id = "picnicChair", name = "Picnic Chair", rarity = "Common", source = "crate", buxPrice = 40, iconKey = "leaf",
		look = look(Color3.fromRGB(230, 90, 80), Enum.Material.SmoothPlastic, 0) },
	-- Uncommon
	{ id = "clayThrone", name = "Clay Throne", rarity = "Uncommon", source = "crate", buxPrice = 90, iconKey = "potion",
		look = look(Color3.fromRGB(200, 120, 84), Enum.Material.Slate, 0) },
	{ id = "kilnStool", name = "Kiln Stool", rarity = "Uncommon", source = "crate", buxPrice = 90, iconKey = "fire",
		look = look(Color3.fromRGB(60, 54, 58), Enum.Material.Concrete, 0) },
	{ id = "beanBag", name = "Bean Bag", rarity = "Uncommon", source = "crate", buxPrice = 90, iconKey = "heart",
		look = look(Color3.fromRGB(120, 90, 220), Enum.Material.SmoothPlastic, 0) },
	-- Rare
	{ id = "neonGamer", name = "Neon Gamer Chair", rarity = "Rare", source = "crate", buxPrice = 200, iconKey = "bolt",
		look = look(Color3.fromRGB(60, 220, 255), Enum.Material.Neon, 0, "sparkle") },
	{ id = "soccerChair", name = "Soccer Chair", rarity = "Rare", source = "crate", buxPrice = 200, iconKey = "target",
		look = look(Color3.fromRGB(245, 245, 245), Enum.Material.SmoothPlastic, 0) },
	{ id = "marbleBench", name = "Marble Bench", rarity = "Rare", source = "crate", buxPrice = 200, iconKey = "crystal",
		look = look(Color3.fromRGB(235, 235, 240), Enum.Material.Marble, 0.1) },
	{ id = "cactusChair", name = "Cactus Chair", rarity = "Rare", source = "crate", buxPrice = 200, iconKey = "leaf",
		look = look(Color3.fromRGB(70, 170, 90), Enum.Material.Grass, 0) },
	-- Epic
	{ id = "lavaChair", name = "Molten Lava Chair", rarity = "Epic", source = "crate", buxPrice = 45, iconKey = "fire",
		look = look(Color3.fromRGB(255, 90, 30), Enum.Material.Neon, 0, "fire") },
	{ id = "iceThrone", name = "Ice Throne", rarity = "Epic", source = "crate", buxPrice = 45, iconKey = "water",
		look = look(Color3.fromRGB(185, 235, 255), Enum.Material.Glass, 0.3, "sparkle") },
	{ id = "mushroomChair", name = "Mushroom Chair", rarity = "Epic", source = "crate", buxPrice = 45, iconKey = "potion",
		look = look(Color3.fromRGB(230, 70, 90), Enum.Material.SmoothPlastic, 0) },
	{ id = "candyChair", name = "Candy Chair", rarity = "Epic", source = "crate", buxPrice = 45, iconKey = "heart",
		look = look(Color3.fromRGB(255, 130, 220), Enum.Material.SmoothPlastic, 0.1, "sparkle") },
	-- Legendary
	{ id = "goldenKiln", name = "Golden Kiln Throne", rarity = "Legendary", source = "crate", buxPrice = 90, iconKey = "crown",
		look = look(Color3.fromRGB(245, 200, 70), Enum.Material.Metal, 0.25, "sparkle") },
	{ id = "dragonChair", name = "Dragon Chair", rarity = "Legendary", source = "crate", buxPrice = 90, iconKey = "skull",
		look = look(Color3.fromRGB(150, 40, 40), Enum.Material.Metal, 0.1, "fire") },
	{ id = "cloudThrone", name = "Cloud Throne", rarity = "Legendary", source = "crate", buxPrice = 90, iconKey = "cloud",
		look = look(Color3.fromRGB(240, 245, 255), Enum.Material.Neon, 0, "sparkle") },
	-- Mythic
	{ id = "galaxyThrone", name = "Galaxy Throne", rarity = "Mythic", source = "crate", buxPrice = 130, iconKey = "portal",
		look = look(Color3.fromRGB(90, 40, 200), Enum.Material.Neon, 0, "galaxy") },
	{ id = "phoenixChair", name = "Phoenix Chair", rarity = "Mythic", source = "crate", buxPrice = 130, iconKey = "fire",
		look = look(Color3.fromRGB(255, 120, 20), Enum.Material.Neon, 0, "fire") },
	{ id = "rainbowVortex", name = "Rainbow Vortex Seat", rarity = "Mythic", source = "crate", buxPrice = 130, iconKey = "rainbow",
		look = look(Color3.fromRGB(255, 90, 230), Enum.Material.Neon, 0, "rainbow") },
	-- Exclusive: never in a crate. They show as look-what-exists showcases.
	{ id = "pumpkinThrone", name = "Pumpkin Throne", rarity = "Exclusive", source = "event", iconKey = "gift",
		look = look(Color3.fromRGB(240, 130, 30), Enum.Material.SmoothPlastic, 0, "sparkle") },
	{ id = "giftBoxChair", name = "Gift-Box Chair", rarity = "Exclusive", source = "robux", iconKey = "gift",
		look = look(Color3.fromRGB(220, 60, 70), Enum.Material.SmoothPlastic, 0.1, "sparkle") },
	{ id = "anniversaryCrown", name = "Anniversary Crown Seat", rarity = "Exclusive", source = "event", iconKey = "crown",
		look = look(Color3.fromRGB(255, 215, 90), Enum.Material.Metal, 0.3, "rainbow") },
} :: { any }) :: { Chair }

for _, chair in chairs do
	chair.robuxPrice = ROBUX_BY_RARITY[chair.rarity] or 49
	chair.shardPrice = math.floor((chair.buxPrice or chair.robuxPrice * 7) * SHARD_MULTIPLIER)
end

PotteryStoreConfig.Chairs = chairs

PotteryStoreConfig.ChairById = {} :: { [string]: Chair }
for _, chair in chairs do
	PotteryStoreConfig.ChairById[chair.id] = chair
end

-- The buyable pool: chairs carrying a Bux price. Exclusives are excluded for
-- the same reason the shipped game excludes them — they are not for sale.
PotteryStoreConfig.BuyableChairs = {} :: { Chair }
for _, chair in chairs do
	if chair.buxPrice then
		table.insert(PotteryStoreConfig.BuyableChairs, chair)
	end
end

-- ========================================================================
-- Rotating shop — deterministic from the clock, exactly like the source
-- ========================================================================

PotteryStoreConfig.RotateSeconds = 3600 -- hourly refresh
PotteryStoreConfig.FeaturedSlots = 6
PotteryStoreConfig.GallerySlots = 18 -- three rows of six under the skins sign

function PotteryStoreConfig.Window(nowSeconds: number): number
	return math.floor(nowSeconds / PotteryStoreConfig.RotateSeconds)
end

function PotteryStoreConfig.SecondsLeft(nowSeconds: number): number
	return PotteryStoreConfig.RotateSeconds - (nowSeconds % PotteryStoreConfig.RotateSeconds)
end

local function seededShuffle(pool: { Chair }, seed: number): { Chair }
	local out = table.clone(pool)
	local rng = Random.new(seed)
	for i = #out, 2, -1 do
		local j = rng:NextInteger(1, i)
		out[i], out[j] = out[j], out[i]
	end
	return out
end

-- The featured six for a window. Seeded shuffle -> every client agrees with
-- the server without a round trip, and the countdown is just the remainder.
function PotteryStoreConfig.Featured(window: number): { Chair }
	local shuffled = seededShuffle(PotteryStoreConfig.BuyableChairs, window + 1)
	local out: { Chair } = {}
	for i = 1, math.min(PotteryStoreConfig.FeaturedSlots, #shuffled) do
		out[i] = shuffled[i]
	end
	return out
end

function PotteryStoreConfig.FeaturedSet(window: number): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, chair in PotteryStoreConfig.Featured(window) do
		set[chair.id] = true
	end
	return set
end

-- The physical gallery rotation: the WHOLE catalog (exclusives included),
-- on a different seed stream so the two rotations never mirror each other.
function PotteryStoreConfig.Gallery(window: number): { Chair }
	local shuffled = seededShuffle(chairs, window * 7 + 13)
	local out: { Chair } = {}
	for i = 1, math.min(PotteryStoreConfig.GallerySlots, #shuffled) do
		out[i] = shuffled[i]
	end
	return out
end

-- Per-item stock for a window. Scarcity tracks rarity (a Mythic slot is a
-- single unit; Commons stock deep), and it is derived from the window seed so
-- the whole board restocks on the same tick the countdown rolls over.
local STOCK_BY_RARITY: { [string]: { number } } = {
	Common = { 8, 20 },
	Uncommon = { 6, 14 },
	Rare = { 3, 8 },
	Epic = { 2, 5 },
	Legendary = { 1, 3 },
	Mythic = { 1, 2 },
	Exclusive = { 1, 1 },
}

function PotteryStoreConfig.StockFor(window: number, chair: Chair): number
	local band = STOCK_BY_RARITY[chair.rarity] or { 1, 4 }
	local rng = Random.new(window * 131 + #chair.id * 17 + (PotteryStoreConfig.Rank[chair.rarity] or 1))
	return rng:NextInteger(band[1], band[2])
end

-- ========================================================================
-- Passes — the permanent perks, with their real value propositions
-- ========================================================================

-- badge strings map to the source's promo shouts:
--   "Best value"   <- BEST VALUE      (VIP)
--   "Most popular" <- MOST POPULAR!   (300 Bux)
--   "Best deal"    <- BEST DEAL!      (1000 Bux)
--   "Exclusive"    <- EXCLUSIVE!      (free-reward chair, aura pack)
PotteryStoreConfig.Passes = {
	{ id = "vip", title = "VIP", desc = "Daily free crate and a gold tag over your head.",
		bullets = { "An exclusive chair, yours on day one", "Golden name tag in every lobby", "25% more coins from every match", "A free crate, every single day" },
		robux = 41, effect = "VIP", iconKey = "crown", badge = "Best value" },
	{ id = "cash2x", title = "2x Cash", desc = "Double the Cash from every match you finish.",
		robux = 68, effect = "Cash2x", iconKey = "cash" },
	{ id = "win2x", title = "2x Wins", desc = "Every victory counts twice on your record.",
		robux = 81, effect = "Win2x", iconKey = "trophy" },
	{ id = "streak2x", title = "2x Streak", desc = "Your streak climbs two rungs a win.",
		robux = 62, effect = "Streak2x", iconKey = "levelUp" },
	{ id = "bux2x", title = "2x Bux", desc = "Double the Bux you receive, from anywhere.",
		robux = 21, effect = "Bux2x", iconKey = "bux" },
	{ id = "luck2x", title = "2x Luck", desc = "Kinder crate odds on every single pull.",
		robux = 90, effect = "Luck2x", iconKey = "luck" },
} :: { Pass }

-- ========================================================================
-- Bux packs
-- ========================================================================

PotteryStoreConfig.BuxPacks = {
	{ id = "bux300", amount = 300, robux = 41, iconKey = "bux", badge = "Most popular", badgeTone = "Accent" },
	{ id = "bux1000", amount = 1000, robux = 81, iconKey = "bux", badge = "Best deal", badgeTone = "Primary" },
	{ id = "bux4000", amount = 4000, robux = 315, iconKey = "gemChest" },
	{ id = "bux15000", amount = 15000, robux = 900, iconKey = "gemChest" },
} :: { BuxPack }

-- ========================================================================
-- Bundles — the banner packs. `ownedAttribute` is the flag that proves the
-- one-time goods landed, so a repeatable dev product can never double-charge.
-- ========================================================================

PotteryStoreConfig.Bundles = {
	{
		id = "starterPack", title = "Starter pack", tagline = "Everything a new potter needs.",
		robux = 9, wasRobux = 299, valueLine = "Worth 299", ownedAttribute = "Owned_ExclusiveChair",
		rainbow = true, badge = "Best value",
		slots = {
			{ kind = "currency", iconKey = "bux", caption = "500 Bux" },
			{ kind = "chair", chairId = "giftBoxChair", caption = "Exclusive chair" },
			{ kind = "randomChair", caption = "Random chair" },
		},
	},
	{
		id = "auraPack", title = "Aura pack", tagline = "A cool way to aura farm.",
		robux = 65, valueLine = "Three chairs that trail effects", ownedAttribute = "Owned_RedAuraChair",
		badge = "Exclusive",
		slots = {
			{ kind = "chair", chairId = "dragonChair", caption = "Red aura" },
			{ kind = "chair", chairId = "goldenKiln", caption = "Yellow aura" },
			{ kind = "chair", chairId = "iceThrone", caption = "Blue aura" },
		},
	},
	{
		id = "proPack", title = "Pro potter pack", tagline = "Go pro in one click.",
		robux = 249, wasRobux = 499, valueLine = "2,500 Bux included", ownedAttribute = "Owned_GalaxyThrone",
		slots = {
			{ kind = "chair", chairId = "galaxyThrone", caption = "Galaxy" },
			{ kind = "chair", chairId = "cloudThrone", caption = "Cloud" },
			{ kind = "currency", iconKey = "gemChest", caption = "2,500 Bux" },
		},
	},
	{
		id = "premiumChair", title = "67 premium chair", tagline = "The marble bench, straight up.",
		robux = 55, valueLine = "One chair, no crate needed", ownedAttribute = "OwnChair_marbleBench",
		slots = { { kind = "chair", chairId = "marbleBench", caption = "Marble bench" } },
	},
	{
		id = "rainbowChair", title = "Rainbow chair", tagline = "The vortex seat, in every colour at once.",
		robux = 81, valueLine = "Mythic tier, bought outright", ownedAttribute = "OwnChair_rainbowVortex",
		slots = { { kind = "chair", chairId = "rainbowVortex", caption = "Rainbow vortex" } },
	},
} :: { Bundle }

-- Trolls are bought DURING a duel from the troll bar, where they fire the
-- instant they are paid for. The store only points players there.
PotteryStoreConfig.TrollNote = "Trolls are bought mid-duel, from the troll bar. Nothing to buy here."

-- ========================================================================
-- Free reward — the group-gated one-time grant
-- ========================================================================

PotteryStoreConfig.FreeReward = {
	groupId = 311291680,
	cash = 1000,
	bux = 300,
	chairId = "iceThrone", -- an Epic-tier chair handed out with the reward
	-- Gate + result copy. Every one of these strings has a source counterpart:
	--   gate      <- "Join the group to claim!"
	--   prompting <- "Join in the popup -- the reward claims itself!"
	--   retry     <- "Join the group first, then claim!"
	--   already   <- "You already own this reward!"
	gate = "Join the group to claim!",
	prompting = "Join in the popup — the reward claims itself.",
	retry = "Join the group first, then claim.",
	already = "You already own this reward.",
	claimedNote = "You already claimed this reward.",
	tag = "Exclusive", -- <- EXCLUSIVE! ribbon on the chair card
}

function PotteryStoreConfig.FreeRewardGranted(): string
	local reward = PotteryStoreConfig.FreeReward
	return string.format("+$%d Cash, +%d Bux and a free chair!", reward.cash, reward.bux)
end

-- ========================================================================
-- Titles — the full progression, gated on Wins or Cash
-- ========================================================================

PotteryStoreConfig.Titles = {
	{ name = "Noob", stat = "wins", req = 0 },
	{ name = "Potter", stat = "wins", req = 1 },
	{ name = "Rookie", stat = "wins", req = 5 },
	{ name = "Fighter", stat = "wins", req = 10 },
	{ name = "Artisan", stat = "wins", req = 15 },
	{ name = "Veteran", stat = "wins", req = 20 },
	{ name = "Craftsman", stat = "wins", req = 30 },
	{ name = "Champion", stat = "wins", req = 50 },
	{ name = "Sculptor", stat = "wins", req = 75 },
	{ name = "Master", stat = "wins", req = 100 },
	{ name = "Elite", stat = "wins", req = 200 },
	{ name = "Legend", stat = "wins", req = 350 },
	{ name = "Mythic", stat = "wins", req = 500 },
	{ name = "Godlike", stat = "wins", req = 1000 },
	{ name = "Saver", stat = "cash", req = 500 },
	{ name = "Wealthy", stat = "cash", req = 2500 },
	{ name = "Rich", stat = "cash", req = 10000 },
	{ name = "Loaded", stat = "cash", req = 50000 },
	{ name = "Tycoon", stat = "cash", req = 200000 },
	{ name = "Billionaire", stat = "cash", req = 1000000 },
} :: { Title }

function PotteryStoreConfig.TitleUnlocked(title: Title, wins: number, cash: number): boolean
	return (if title.stat == "cash" then cash else wins) >= title.req
end

-- The unlock condition, printed. Cash requirements lead with the currency
-- mark; win requirements read as a plain count.
function PotteryStoreConfig.TitleRequirement(title: Title): string
	if title.stat == "cash" then
		return "$" .. PotteryStoreConfig.Comma(title.req)
	end
	if title.req <= 0 then
		return "yours from the start"
	elseif title.req == 1 then
		return "1 win"
	end
	return PotteryStoreConfig.Comma(title.req) .. " wins"
end

-- The flex ramp: the starting title earns NO icon (it has not flexed
-- anything yet), then star -> trophy -> crown for wins and cash -> chest for
-- money. Mirrors Titles.iconFor in the source.
function PotteryStoreConfig.TitleIconKey(title: Title?): string?
	if not title or title.req <= 0 then
		return nil
	end
	if title.stat == "cash" then
		if title.req <= 2500 then
			return "cash"
		elseif title.req <= 50000 then
			return "chest"
		end
		return "gemChest"
	end
	if title.req <= 30 then
		return "star"
	elseif title.req <= 350 then
		return "trophy"
	end
	return "crown"
end

-- The rarity a title wears, derived from how hard it is to reach — so the
-- title list and the chair list share ONE colour ladder.
function PotteryStoreConfig.TitleRarity(title: Title): string
	local scale = if title.stat == "cash" then title.req / 50 else title.req
	if scale >= 1000 then
		return "Exclusive"
	elseif scale >= 350 then
		return "Mythic"
	elseif scale >= 100 then
		return "Legendary"
	elseif scale >= 30 then
		return "Epic"
	elseif scale >= 10 then
		return "Rare"
	elseif scale >= 1 then
		return "Uncommon"
	end
	return "Common"
end

-- ========================================================================
-- Demo player state — what a screen shows before a host injects real data
-- ========================================================================

PotteryStoreConfig.DemoState = {
	bux = 640,
	cash = 12400,
	shards = 275,
	wins = 63,
	robuxOwned = { vip = true },
	ownedChairs = {
		"woodenStool", "plasticChair", "clayThrone", "beanBag",
		"marbleBench", "cactusChair", "iceThrone", "goldenKiln",
	},
	equippedChair = "goldenKiln",
	equippedTitle = "Champion",
}

-- ========================================================================
-- Formatting
-- ========================================================================

function PotteryStoreConfig.Comma(value: number): string
	local text = string.format("%d", math.floor(math.abs(value)))
	while true do
		local replaced, count = string.gsub(text, "^(%d+)(%d%d%d)", "%1,%2")
		text = replaced
		if count == 0 then
			break
		end
	end
	return if value < 0 then "-" .. text else text
end

-- HH:MM:SS, the source's exact "%02d:%02d:%02d" countdown format. The caption
-- beside it is de-shouted ("Refreshes in" <- "REFRESHES IN:"); the numerals
-- are not, because a clock is data.
function PotteryStoreConfig.Clock(seconds: number): string
	local remaining = math.max(0, math.floor(seconds))
	return string.format(
		"%02d:%02d:%02d",
		remaining // 3600,
		(remaining % 3600) // 60,
		remaining % 60
	)
end

-- "%d/%d" — the source's UNLOCKED TITLES counter, and the skins gallery's
-- UNLOCKED: %d / %d, sharing one formatter.
function PotteryStoreConfig.Fraction(have: number, total: number): string
	return string.format("%d/%d", have, total)
end

-- Copy the screens read instead of holding literals. Warm, never patronizing.
PotteryStoreConfig.Copy = {
	rotatingSubtitle = "Six chairs, chosen on the hour. When they go, they go.",
	rotatingRefresh = "Refreshes in", -- <- "REFRESHES IN:"
	rotatingEmpty = "Nothing in this filter right now — try another tab.",
	rotatingSoldOut = "Sold out", -- <- "SOLD OUT"
	rotatingLastOne = "Last one!",
	rotatingRestocked = "The shelves are full again.",
	galleryTitle = "Chair skins",
	gallerySubtitle = "Every chair you have thrown, glazed or won.",
	galleryFeatured = "Featured", -- <- "⭐ FEATURED"
	galleryEmpty = "Open a crate to earn your first chair!", -- source verbatim
	galleryLockedHint = "Not yours yet — win it from a crate, or buy it outright.",
	galleryEquippedHint = "Currently equipped. Pick another chair to swap.",
	galleryOwnedHint = "In your collection — equip it to sit on it.",
	galleryUnlocked = "Unlocked", -- <- "UNLOCKED:"
	galleryShards = "Shards",
	storeSubtitle = "Passes, packs and Bux — the whole counter.",
	storeSectionFree = "Free reward",
	storeSectionBundles = "Bundles",
	storeSectionPasses = "Passes",
	storeSectionBux = "Bux",
	storeSectionTrolls = "Trolls",
	storeFooter = "Every purchase is handled by Roblox — payment happens in the official prompt.",
	titlesSubtitle = "Wear what you have earned. The lobby will see it.",
	titlesCounter = "Unlocked titles", -- <- "UNLOCKED TITLES:"
	titlesEmpty = "Nothing unlocked in this filter yet — keep throwing.",
	titlesCelebration = "New title unlocked!", -- <- "NEW TITLE UNLOCKED!"
	titlesCelebrationButton = "Lovely!", -- <- "NICE!"
	stateEquip = "Equip", -- <- "EQUIP"
	stateEquipped = "Equipped", -- <- "EQUIPPED"
	stateOwned = "Owned", -- <- "OWNED"
	stateLocked = "Locked", -- <- "LOCKED"
	stateClaim = "Claim", -- <- "CLAIM"
	stateClaimed = "Claimed!", -- <- "CLAIMED!"
}

return PotteryStoreConfig
