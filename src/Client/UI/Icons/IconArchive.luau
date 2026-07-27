--!strict
-- The icon archive: ONE place the whole UI asks for artwork.
--
--   IconArchive.Id("close")                  -> "rbxassetid://..."
--   IconArchive.Id("chest", { golden = true })
--   IconArchive.Image(parent, "cash", 40)    -> a boxless ImageLabel
--
-- Callers name a SEMANTIC role ("currency.cash", "close", "lock"), never a
-- filename and never a raw asset id. The archive maps that role onto a
-- catalogued icon, picks the best available variant (outline first — the house
-- style is chunky black outlines), and degrades gracefully: uploaded id →
-- another variant of the same icon → a Unicode glyph. A game re-skins its
-- iconography by editing ALIASES, not by touching a single screen.
--
-- Art: Gvesster Icon Pack v6 (@gvesster).

local IconCatalog = require(script.Parent.IconCatalog)
local IconVisibility = require(script.Parent.IconVisibility)

local IconArchive = {}

export type Query = {
	-- Prefer a specific colourway ("Golden", "Blue", "Bronze", "Rainbow"...).
	colorway: string?,
	-- Prefer the golden treatment — shorthand for colorway = "Golden".
	golden: boolean?,
	-- Outline variants are the default; pass false for the clean fill.
	outline: boolean?,
	-- Preferred source resolution (256 or 64). Falls back to whatever exists.
	size: number?,
}

-- ========================================================================
-- Semantic aliases: role -> catalogue key. This is the per-game seam.
-- ========================================================================

local ALIASES: { [string]: string } = {
	-- currency (doc §3.3 — Cash green, Bux blue, Robux magenta)
	["currency.cash"] = "cash",
	["currency.bux"] = "gem",
	["currency.robux"] = "robux",
	["currency.coin"] = "coin",
	["currency.gem"] = "gem",
	["currency.emerald"] = "emerald",
	["currency.ingot"] = "ingot",
	cash = "cash",
	bux = "gem",
	robux = "robux",

	-- chrome / actions
	close = "closeButton",
	x = "x",
	check = "checkmark",
	checkButton = "checkmarkButton",
	plus = "plus",
	minus = "minus",
	menu = "menu",
	settings = "settings",
	search = "magnifyingGlass",
	info = "info",
	warning = "warning",
	question = "questionMark",
	alert = "exclamationMark",
	bell = "bell",
	trash = "trash",
	edit = "pencil",
	save = "save",
	sort = "sort",
	expand = "expand",
	shrink = "shrink",
	skip = "skip",
	cursor = "cursor",
	upgrade = "upgrade",
	downgrade = "downgrade",
	arrowUp = "arrowUp",
	arrowDown = "arrowDown",
	arrowLeft = "arrowLeft",
	arrowRight = "arrowRight",
	soundOn = "soundOn",
	soundOff = "soundOff",
	musicOn = "musicOn",
	musicOff = "musicOff",
	pin = "pinMark",
	mapPin = "mapmark",
	ageGate = "n16Only",

	-- economy
	shop = "shoppingCart",
	cart = "shoppingCart",
	bag = "shoppingBag",
	gift = "gift",
	crate = "crate",
	chest = "chest",
	-- The pack has no dedicated gem/cash chest art; the chest colourways carry
	-- that meaning instead (blue reads as the gem chest).
	gemChest = "chest",
	cashChest = "chest",
	box = "box",
	ticket = "ticket",
	card = "card",
	gamepass = "gamepass",
	premium = "premium",
	trade = "trade",
	codes = "codes",
	wheel = "wheel",
	luck = "luck",
	dice = "dice",
	luckyBlock = "luckyBlock",

	-- progression / rewards
	trophy = "trophy",
	medal = "medal",
	star = "star",
	crown = "crown",
	rebirth = "rebirth",
	stats = "stats",
	calendar = "calendar",
	quest = "scroll",
	book = "book",
	journal = "newspaper",
	levelUp = "upgrade",
	verified = "verifyBadge",
	sparkle = "sparkle",
	target = "target",
	checkpoint = "checkpoint",

	-- state
	lock = "lock",
	unlock = "unlock",
	heart = "heart",
	brokenHeart = "brokenHeart",
	clock = "clock",
	hourglass = "hourglass",
	banned = "banned",
	skull = "skull",
	death = "ripPlayer",
	thumbsUp = "thumbsUp",
	thumbsDown = "thumbsDown",

	-- social / player
	player = "player",
	players = "n4Players",
	friends = "friends",
	addFriend = "addFriend",
	party = "n4Players",
	backpack = "backpack",
	inventory = "backpack",
	house = "house",
	teleport = "teleporter",

	-- combat / genre
	sword = "sword",
	swords = "crossedSwords",
	shield = "shield",
	bomb = "bomb",
	gun = "gun",
	axe = "axe",
	pickaxe = "pickaxe",
	hammer = "hammer",
	key = "key",
	compass = "compass",
	potion = "potion",
	magnet = "magnet",

	-- elements / fx
	fire = "fire",
	bolt = "bolt",
	water = "water",
	leaf = "leaf",
	crystal = "crystal",
	portal = "portal",
	rainbow = "rainbow",
	explosion = "explosion",
	sun = "sun",
	moon = "moon",
	cloud = "cloud",

	-- tech / links
	discord = "discord",
	youtube = "youtube",
	twitter = "xTwitter",
	controller = "controller",
	rocket = "rocket",
}

-- Last-resort glyphs so a missing upload still renders SOMETHING readable
-- (doc §10 asset robustness: image -> glyph -> plain shape, never blank).
local GLYPHS: { [string]: string } = {
	close = "X",
	x = "X",
	check = "\u{2713}",
	checkButton = "\u{2713}",
	plus = "+",
	minus = "-",
	menu = "\u{2261}",
	settings = "\u{2699}",
	search = "S",
	info = "i",
	warning = "!",
	question = "?",
	alert = "!",
	bell = "!",
	trash = "X",
	arrowUp = "\u{25B2}",
	arrowDown = "\u{25BC}",
	arrowLeft = "\u{25C0}",
	arrowRight = "\u{25B6}",
	lock = "L",
	unlock = "U",
	star = "\u{2605}",
	crown = "V",
	trophy = "T",
	gift = "G",
	heart = "\u{2665}",
	clock = "O",
	shop = "B",
	cart = "B",
	cash = "$",
	bux = "\u{25C6}",
	robux = "R$",
	skull = "K",
	fire = "F",
}

-- ========================================================================
-- Resolution
-- ========================================================================

-- Some roles carry a colour MEANING, and the pack ships the icon in several
-- colourways. Currency is the strict case (doc §3.3: Cash green, Bux blue,
-- Robux magenta — no exceptions), so those aliases pin a colourway instead of
-- taking whichever variant happens to score first.
local PREFERRED_COLORWAY: { [string]: string } = {
	["currency.cash"] = "Green",
	cash = "Green",
	["currency.bux"] = "Blue",
	bux = "Blue",
	["currency.gem"] = "Blue",
	["currency.robux"] = "Golden",
	robux = "Golden",
	["currency.ingot"] = "Golden",
	chest = "Green",
}

IconArchive.Aliases = ALIASES
IconArchive.Glyphs = GLYPHS
IconArchive.PreferredColorway = PREFERRED_COLORWAY

local function resolveKey(nameOrAlias: string): string
	return ALIASES[nameOrAlias] or nameOrAlias
end

-- Score a variant against the query: higher is better. Only variants that
-- actually carry an uploaded assetId can win, because a catalogued-but-not-
-- uploaded file is useless to the engine.
-- The pack names colourways inconsistently: "Green" (Green Cash), "Chest Green"
-- (Chest Green), "Golden". Match on the colour WORD so a caller asking for
-- "Green" finds it however the file happened to be named.
local function colorwayMatches(variantColorway: string, want: string): boolean
	if variantColorway == want then
		return true
	end
	local haystack = string.lower(variantColorway)
	local needle = string.lower(want)
	return string.find(haystack, "^" .. needle .. " ") ~= nil
		or string.find(haystack, " " .. needle .. "$") ~= nil
end

-- "Golden" is a REQUEST FOR THE PREMIUM TREATMENT, not a literal colour name.
-- The pack expresses that differently per icon — Golden Crate, Yellow Star,
-- Rainbow Lucky Block, Silver/Bronze medals — and some icons (Crown, Skull)
-- ship no premium variant at all. Ranking the whole family means a reward tier
-- reads as special wherever the art allows, and falls back cleanly where it
-- doesn't, instead of silently rendering the plain icon.
local PREMIUM_RANK = { Golden = 4, Rainbow = 3, Yellow = 2, Diamond = 2, Silver = 1 }

local function premiumScore(colorway: string): number
	local best = 0
	for word, rank in PREMIUM_RANK do
		if colorwayMatches(colorway, word) and rank > best then
			best = rank
		end
	end
	return best
end

local function score(variant: IconCatalog.Variant, query: Query): number
	if not variant.assetId then
		return -1
	end
	local n = 0
	local wantColorway = query.colorway
	if wantColorway then
		n += colorwayMatches(variant.colorway, wantColorway) and 100 or 0
	elseif query.golden then
		-- Rank premium-ness rather than demanding the literal word "Golden".
		n += premiumScore(variant.colorway) * 25
	else
		n += (variant.colorway == "Default") and 40 or 0
	end
	-- Outline is the house default (chunky black outlines, doc §2/§4.1).
	local wantOutline = if query.outline == nil then true else query.outline
	n += (variant.outline == wantOutline) and 20 or 0
	if query.size then
		n += (variant.size == query.size) and 10 or 0
	else
		n += (variant.size == 256) and 5 or 0
	end
	return n
end

-- The best available asset id for a semantic name, or nil when nothing in the
-- archive has been uploaded for it yet.
function IconArchive.Id(nameOrAlias: string, query: Query?): string?
	local icon = IconCatalog.Get(resolveKey(nameOrAlias))
	if not icon then
		return nil
	end
	local q = query or {}
	-- A pinned colourway is the role's meaning (green cash, blue bux); an
	-- explicit query still wins so a caller can ask for the golden treatment.
	if not q.colorway and not q.golden then
		local pinned = PREFERRED_COLORWAY[nameOrAlias]
		if pinned then
			q = { colorway = pinned, outline = q.outline, size = q.size }
		end
	end
	local best, bestScore = nil :: IconCatalog.Variant?, -1
	for _, variant in icon.variants do
		local s = score(variant, q)
		if s > bestScore then
			best, bestScore = variant, s
		end
	end
	return best and best.assetId or nil
end

function IconArchive.Has(nameOrAlias: string): boolean
	return IconArchive.Id(nameOrAlias) ~= nil
end

function IconArchive.Glyph(nameOrAlias: string): string
	return GLYPHS[nameOrAlias] or GLYPHS[resolveKey(nameOrAlias)] or "?"
end

-- The full catalogue entry (all variants, uploaded or not) — for tooling, the
-- icon browser, and any flow that wants to offer colourway choices.
function IconArchive.Entry(nameOrAlias: string): IconCatalog.Icon?
	return IconCatalog.Get(resolveKey(nameOrAlias))
end

-- ========================================================================
-- Builders
-- ========================================================================

-- A boxless icon (doc §10: the flat cartoon set is always shown WITHOUT a
-- box). Renders an ImageLabel when the art exists, otherwise an outlined
-- FredokaOne glyph at the same size — the caller's layout is identical either
-- way, so a pending upload never leaves a hole.
function IconArchive.Image(parent: Instance?, nameOrAlias: string, sizePx: number, query: Query?): GuiObject
	local id = IconArchive.Id(nameOrAlias, query)
	if id then
		local image = Instance.new("ImageLabel")
		image.Name = "Icon_" .. nameOrAlias
		image.BackgroundTransparency = 1
		image.Image = id
		image.ScaleType = Enum.ScaleType.Fit
		image.Size = UDim2.fromOffset(sizePx, sizePx)
		image.Parent = parent
		IconVisibility.Register(image)
		return image
	end
	local label = Instance.new("TextLabel")
	label.Name = "IconGlyph_" .. nameOrAlias
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromOffset(sizePx, sizePx)
	label.Text = IconArchive.Glyph(nameOrAlias)
	label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0
	label.Parent = parent
	-- The glyph fallback is iconography too: it answers the global toggle.
	IconVisibility.Register(label)
	return label
end

-- ========================================================================
-- Browsing (icon picker, theme previewer, tooling)
-- ========================================================================

function IconArchive.Categories(): { string }
	return IconCatalog.Categories()
end

function IconArchive.InCategory(category: string): { IconCatalog.Icon }
	return IconCatalog.ByCategory(category)
end

-- Substring search over key + display name, e.g. Search("chest").
function IconArchive.Search(term: string): { IconCatalog.Icon }
	local needle = string.lower(term)
	local out = {}
	for _, icon in IconCatalog.Icons do
		if string.find(string.lower(icon.key), needle, 1, true)
			or string.find(string.lower(icon.name), needle, 1, true)
		then
			table.insert(out, icon)
		end
	end
	return out
end

-- How much of the archive is actually usable right now (uploaded vs
-- catalogued) — the number the icon browser prints in its header.
function IconArchive.Coverage(): (number, number)
	local usable, total = 0, 0
	for _, icon in IconCatalog.Icons do
		total += 1
		for _, variant in icon.variants do
			if variant.assetId then
				usable += 1
				break
			end
		end
	end
	return usable, total
end

return IconArchive
