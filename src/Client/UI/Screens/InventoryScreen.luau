--!strict
-- INVENTORY — the workhorse economy screen, Pottery Clash arcade family.
-- One §7.4 modal card holding three columns inside the content inset:
--
--   [ tabs 196 ] [ slot grid 764 ] [ detail pane 384 ]
--
-- with a header strip carrying a search field, the sort dropdown and the
-- capacity ruler. Every slot is ONE invisible full-size button (doc §11.6 — no
-- dead zones inside a cell); the visual subtree sits ABOVE that button as plain
-- frames/labels, which never sink input, so a tap anywhere in the cell lands.
--
-- SELECTION IS A RING (doc §4.3): the gold ring is a separate outset frame that
-- switches Visible; slot backgrounds NEVER change on selection. The rarity ring
-- is a second, inset frame — two rings can't share one host, since one UIStroke
-- per instance is all the engine honours.
--
-- Fixed px at the 1650×1020 baseline (UIScreenBase attaches the UIScale).

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UIDropdownComponent = require(script.Parent.Parent.Components.UIDropdownComponent)
local UIProgressBarComponent = require(script.Parent.Parent.Components.UIProgressBarComponent)
local UIStatRowComponent = require(script.Parent.Parent.Components.UIStatRowComponent)
local UIScreenBase = require(script.Parent.UIScreenBase)
local ACLayoutKit = require(script.Parent.Parent.Framework.ACLayoutKit)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local IconVisibility = require(script.Parent.Parent.Icons.IconVisibility)
local UITicker = require(script.Parent.Parent.Framework.UITicker)

type Item = {
	id: string,
	name: string,
	icon: string,
	rarity: string,
	count: number,
	category: string,
	locked: boolean?,
	favorite: boolean?,
	description: string?,
	stats: any?,
}

-- Card 1400×840 → content 1372×752 after the §7.4 inset (14, 74, −28, −88).
local CARD = Vector2.new(1400, 840)
local CONTENT_W = 1372
local CONTENT_H = 752
local HEADER_H = 56
local BODY_Y = HEADER_H + 12
local BODY_H = CONTENT_H - BODY_Y
local GAP = 14
local TABS_W = 196
local GRID_W = 764 -- 6 × 116 slots + 5 × 12 padding + 8px scrollbar reserve
local DETAIL_W = 384
local DETAIL_X = TABS_W + GAP + GRID_W + GAP
local SLOT = 116
local SLOT_PAD = 12
local COLUMNS = 6
local TAB_H = 54
local PAD = 16

local WHITE = Color3.new(1, 1, 1)

local CATEGORIES = {
	{ id = "all", label = "ALL", icon = "bag" },
	{ id = "gear", label = "GEAR", icon = "sword" },
	{ id = "consumables", label = "CONSUMABLES", icon = "potion" },
	{ id = "materials", label = "MATERIALS", icon = "crystal" },
	{ id = "cosmetics", label = "COSMETICS", icon = "crown" },
}

local RARITY_RANK: { [string]: number } = {
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
}

-- The rarity ramp climbs the ShopAccents rotation (doc §3.2) for the tiers that
-- need to shout, and stays on the OWNED grey / arcade green for the quiet ones.
local function rarityColor(theme: Types.UITheme, rarity: string?): Color3
	local accents = theme.Arcade.ShopAccents
	if rarity == "Legendary" then
		return accents[2]
	elseif rarity == "Epic" then
		return accents[4]
	elseif rarity == "Rare" then
		return accents[3]
	elseif rarity == "Uncommon" then
		return theme.Arcade.Green
	end
	return theme.Arcade.GreyOwned
end

-- Stats arrive either as an ordered list ({ label, value } records) or as a
-- plain map; both render as the same right-aligned stat rows.
local function statLines(stats: any): { { label: string, value: string } }
	local out = {}
	if type(stats) ~= "table" then
		return out
	end
	if #stats > 0 then
		for _, entry in stats do
			table.insert(out, {
				label = string.upper(tostring(entry.label or entry[1] or "")),
				value = tostring(entry.value or entry[2] or ""),
			})
		end
	else
		local keys = {}
		for key in stats do
			table.insert(keys, tostring(key))
		end
		table.sort(keys)
		for _, key in keys do
			table.insert(out, { label = string.upper(key), value = tostring(stats[key]) })
		end
	end
	return out
end

local function item(
	id: string,
	name: string,
	icon: string,
	rarity: string,
	count: number,
	category: string,
	description: string,
	stats: any,
	locked: boolean?,
	favorite: boolean?
): Item
	return {
		id = id,
		name = name,
		icon = icon,
		rarity = rarity,
		count = count,
		category = category,
		description = description,
		stats = stats,
		locked = locked,
		favorite = favorite,
	}
end

-- Demo bag so the screen renders shippable with no backend behind it.
local function demoItems(): { Item }
	return {
		item("emberBlade", "EMBER BLADE", "sword", "Legendary", 1, "gear",
			"Forged in the great kiln. The edge never cools, and neither does whatever it touches.",
			{ { label = "Damage", value = "148" }, { label = "Speed", value = "1.24" }, { label = "Crit", value = "12%" } },
			false, true),
		item("kilnGuard", "KILN GUARD", "shield", "Epic", 1, "gear",
			"A slab of fired clay bound in iron. Heavy, ugly, and still standing.",
			{ { label = "Defense", value = "96" }, { label = "Weight", value = "8.4" } }),
		item("prospectPick", "PROSPECTOR PICK", "pickaxe", "Rare", 1, "gear",
			"Chews through anything softer than it is. Which is most things.",
			{ { label = "Mining", value = "34" }, { label = "Durability", value = "780" } }),
		item("clayHammer", "CLAY HAMMER", "hammer", "Uncommon", 1, "gear",
			"Standard workshop issue. Does one job and does it flat.",
			{ { label = "Damage", value = "41" }, { label = "Speed", value = "0.82" } }),
		item("trailAxe", "TRAILBLAZER AXE", "axe", "Rare", 1, "gear",
			"Balanced for clearing paths, repurposed for clearing rooms.",
			{ { label = "Damage", value = "77" }, { label = "Reach", value = "2.1" } }),
		item("scrapBlaster", "SCRAP BLASTER", "gun", "Epic", 1, "gear",
			"Fires whatever you feed it. Accuracy sold separately.",
			{ { label = "Damage", value = "112" }, { label = "Rate", value = "4.0/s" } }),
		item("explorerCompass", "EXPLORER COMPASS", "compass", "Rare", 1, "gear",
			"Points at the nearest undiscovered thing, not at north.",
			{ { label = "Range", value = "220m" } }),
		item("vaultKey", "VAULT KEY", "key", "Rare", 5, "gear",
			"Opens one vault door, once. Then it is scrap.",
			{ { label = "Charges", value = "5" } }, true),
		item("greaterPotion", "GREATER POTION", "potion", "Rare", 12, "consumables",
			"Tastes of ash and citrus. Restores a frankly unreasonable amount of health.",
			{ { label = "Heal", value = "240" }, { label = "Cooldown", value = "8s" } }),
		item("tricksterBomb", "TRICKSTER BOMB", "bomb", "Uncommon", 8, "consumables",
			"Short fuse, wide grin, wider blast.",
			{ { label = "Damage", value = "180" }, { label = "Radius", value = "6m" } }),
		item("luckyClover", "LUCKY CLOVER", "luck", "Epic", 3, "consumables",
			"Doubles your odds for ten minutes. Does not double your judgement.",
			{ { label = "Luck", value = "+100%" }, { label = "Duration", value = "10m" } }, false, true),
		item("speedBolt", "SPEED BOLT", "bolt", "Uncommon", 24, "consumables",
			"A jolt of stored lightning. Legs first, questions later.",
			{ { label = "Speed", value = "+35%" }, { label = "Duration", value = "45s" } }),
		item("firecracker", "FIRECRACKER", "fire", "Common", 16, "consumables",
			"Mostly noise. Occasionally very useful noise.",
			{ { label = "Damage", value = "24" } }),
		item("healthTonic", "HEALTH TONIC", "heart", "Common", 31, "consumables",
			"The cheap one. Drink two.",
			{ { label = "Heal", value = "60" } }),
		item("kilnCrystal", "KILN CRYSTAL", "crystal", "Epic", 14, "materials",
			"Grown in the hottest corner of the furnace over eleven days.",
			{ { label = "Purity", value = "94%" } }),
		item("glazeDust", "GLAZE DUST", "sparkle", "Rare", 240, "materials",
			"Ground fine enough to hang in the air. Do not inhale.",
			{ { label = "Grade", value = "Fine" } }),
		item("starFragment", "STAR FRAGMENT", "star", "Epic", 7, "materials",
			"Still warm. Nobody has explained that yet.",
			{ { label = "Energy", value = "88" } }),
		item("oakLeaf", "OAK LEAF", "leaf", "Common", 88, "materials",
			"Common binding agent. Smells like the good season.", nil),
		item("springWater", "SPRING WATER", "water", "Common", 52, "materials",
			"Clean, cold, and worth more than it looks.", nil),
		item("ironIngot", "IRON INGOT", "shield", "Uncommon", 63, "materials",
			"Stamped, stacked, and ready for the anvil.",
			{ { label = "Weight", value = "2.0" } }),
		item("emberCore", "EMBER CORE", "explosion", "Legendary", 2, "materials",
			"The heart of a burnt-out forge. Handle with tongs.",
			{ { label = "Heat", value = "1,480" } }, true),
		item("royalCrown", "ROYAL CROWN", "crown", "Legendary", 1, "cosmetics",
			"Purely decorative. Everyone still moves out of the way.", nil, true),
		item("championMedal", "CHAMPION MEDAL", "medal", "Epic", 1, "cosmetics",
			"Awarded for finishing first in a season nobody expected you to survive.", nil),
		item("verifiedHalo", "VERIFIED HALO", "verified", "Rare", 1, "cosmetics",
			"A quiet little ring of authority above your head.", nil),
		item("rainbowTrail", "RAINBOW TRAIL", "rainbow", "Legendary", 1, "cosmetics",
			"Leaves colour behind you for six seconds. Longer if you sprint.", nil, false, true),
		item("skullMask", "SKULL MASK", "skull", "Rare", 1, "cosmetics",
			"Fits badly, scares reliably.", nil),
		item("winterCloud", "WINTER CLOUD", "cloud", "Uncommon", 1, "cosmetics",
			"Follows you around and rains on precisely nobody else.", nil),
		item("trophyPlinth", "TROPHY PLINTH", "trophy", "Epic", 1, "cosmetics",
			"Displays your best run to anyone who visits your base.", nil),
		item("partyTicket", "PARTY TICKET", "ticket", "Uncommon", 9, "consumables",
			"Admits one to whatever is happening in the east hall.",
			{ { label = "Uses", value = "9" } }),
		item("dicePair", "LOADED DICE", "dice", "Rare", 4, "consumables",
			"Nobody has proved anything.",
			{ { label = "Luck", value = "+15%" } }),
		item("magnetCoil", "MAGNET COIL", "magnet", "Uncommon", 6, "consumables",
			"Drags loose drops to you from across the room.",
			{ { label = "Range", value = "18m" } }),
		item("questScroll", "SEALED SCROLL", "quest", "Rare", 3, "materials",
			"Unread. The seal is a problem for later.", nil),
		item("bellCharm", "BELL CHARM", "bell", "Common", 12, "materials",
			"Rings when something invisible is nearby. Rings a lot.", nil),
		item("portalShard", "PORTAL SHARD", "portal", "Legendary", 1, "materials",
			"One end of a door. The other end is somewhere unpleasant.",
			{ { label = "Charges", value = "1" } }, true),
	}
end

local InventoryScreen = setmetatable({}, { __index = UIScreenBase })
InventoryScreen.__index = InventoryScreen

function InventoryScreen.new()
	local self = UIScreenBase.new("InventoryScreen", 7)
	self._items = demoItems()
	self._capacityMax = 60
	self._category = "all"
	self._sortMode = "rarity"
	self._query = ""
	self._selectedId = nil :: string?
	self._equippedId = nil :: string?
	self._tabs = {} :: { [string]: { ring: UIStroke, label: TextLabel, count: TextLabel, frame: Frame } }
	self._statRows = {} :: { GuiObject }
	return setmetatable(self, InventoryScreen)
end

function InventoryScreen:_Toast(text: string, variant: string)
	local hud = self.ScreenController and self.ScreenController:GetScreen("hud")
	if hud then
		hud:PushToast({ text = text, variant = variant })
	end
end

function InventoryScreen:_Ingest(data: any)
	if type(data) ~= "table" then
		return
	end
	if type(data.items) == "table" then
		self._items = data.items
		self._selectedId = nil
	end
	if type(data.capacity) == "number" then
		self._capacityMax = data.capacity
	end
end

function InventoryScreen:_Find(id: string?): Item?
	if not id then
		return nil
	end
	for _, entry in self._items do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

-- ========================================================================
-- Header: search field, sort dropdown, capacity ruler
-- ========================================================================

function InventoryScreen:_BuildHeader(theme: Types.UITheme, content: Frame)
	local header = UIStyler.Frame("Header")
	header.BackgroundTransparency = 1
	header.Size = UDim2.fromOffset(CONTENT_W, HEADER_H)
	-- Above the body columns so the dropdown's open list paints over the grid
	-- (ZIndexBehavior.Sibling ranks whole subtrees by their root sibling).
	header.ZIndex = 46
	header.Parent = content

	-- Search field: the chrome lives on a wrapper frame, not on the TextBox —
	-- a UIPadding on the box itself would also inset the search icon child.
	local field = UIStyler.Frame("SearchField")
	field.BackgroundColor3 = theme.Arcade.Panel
	field.Position = UDim2.fromOffset(0, 6)
	field.Size = UDim2.fromOffset(320, 44)
	field.ZIndex = 46
	UIChrome.Corner("Arcade").Parent = field
	UIChrome.Stroke(theme, "Arcade", "Button").Parent = field
	UIChrome.GlassGradient().Parent = field
	field.Parent = header

	local searchIcon = IconArchive.Image(field, "search", 22)
	searchIcon.AnchorPoint = Vector2.new(0, 0.5)
	searchIcon.Position = UDim2.new(0, 10, 0.5, 0)
	searchIcon.ZIndex = 47

	local box = Instance.new("TextBox")
	box.Name = "Query"
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.Text = ""
	box.PlaceholderText = "SEARCH"
	box.PlaceholderColor3 = theme.Arcade.GreyOwned
	box.FontFace = theme.Fonts.Title -- the style's display font (Classic: FredokaOne)
	box.TextSize = 20
	box.TextColor3 = WHITE
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Position = UDim2.fromOffset(42, 0)
	box.Size = UDim2.new(1, -52, 1, 0)
	box.ZIndex = 47
	UIChrome.TextOutline(box)
	box.Parent = field
	box:GetPropertyChangedSignal("Text"):Connect(function()
		self._query = string.lower(box.Text)
		self:_RenderGrid()
	end)

	self._sort = UIDropdownComponent.new()
	self._sort:Create(header, {
		label = "SORT",
		options = {
			{ id = "rarity", text = "RARITY" },
			{ id = "name", text = "NAME" },
			{ id = "recent", text = "RECENT" },
		},
		value = "rarity",
		size = UDim2.fromOffset(300, 36),
		position = UDim2.fromOffset(340, 10),
		onChanged = function(id: string)
			self._sortMode = id
			self:_RenderGrid()
		end,
	})
	self._sort.Root.ZIndex = 47

	self._capacity = UIProgressBarComponent.new()
	self._capacity:Create(header, {
		value = 0,
		maxValue = self._capacityMax,
		label = "CAPACITY",
		size = UDim2.fromOffset(320, 30),
		position = UDim2.new(1, 0, 0.5, 0),
		anchorPoint = Vector2.new(1, 0.5),
	})
	self._capacity.Root.ZIndex = 46
end

-- ========================================================================
-- Category tabs
-- ========================================================================

function InventoryScreen:_BuildTabs(theme: Types.UITheme, content: Frame)
	local column = UIStyler.Frame("Tabs")
	column.BackgroundTransparency = 1
	column.Position = UDim2.fromOffset(0, BODY_Y)
	column.Size = UDim2.fromOffset(TABS_W, BODY_H)
	column.ZIndex = 43
	column.Parent = content
	UIStyler.ListLayout({
		Padding = UDim.new(0, 10),
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	}).Parent = column

	for index, category in CATEGORIES do
		-- Fixed transparent footprint; the hover UIScale rides the inner
		-- surface so the list never reflows (doc §5.1).
		local root = UIStyler.Frame("Tab_" .. category.id)
		root.BackgroundTransparency = 1
		root.LayoutOrder = index
		root.Size = UDim2.fromOffset(TABS_W, TAB_H)
		root.ZIndex = 43
		root.Parent = column

		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Text = ""
		hit.BackgroundTransparency = 1
		hit.Size = UDim2.fromScale(1, 1)
		hit.AutoButtonColor = false
		hit.ZIndex = 43
		hit.Parent = root

		local surface = UIStyler.Frame("Surface")
		surface.BackgroundColor3 = theme.Arcade.NearBlack
		surface.AnchorPoint = Vector2.new(0.5, 0.5)
		surface.Position = UDim2.fromScale(0.5, 0.5)
		surface.Size = UDim2.fromScale(1, 1)
		surface.ZIndex = 44
		UIChrome.Corner("Arcade").Parent = surface
		UIChrome.Stroke(theme, "Arcade", "Panel").Parent = surface
		UIChrome.GlassGradient().Parent = surface
		surface.Parent = root

		local icon = IconArchive.Image(surface, category.icon, 26)
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 12, 0.5, 0)
		icon.ZIndex = 45

		-- 16px keeps the longest label ("CONSUMABLES") inside its 104px column
		-- without truncating against the count on the right.
		local text = UIChrome.Text("Label", 16, WHITE)
		text.RichText = false
		text.Text = category.label
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.TextTruncate = Enum.TextTruncate.AtEnd
		text.Position = UDim2.fromOffset(46, 0)
		text.Size = UDim2.fromOffset(104, TAB_H)
		text.ZIndex = 45
		text.Parent = surface

		local count = UIChrome.Text("Count", 16, theme.Arcade.IceBlue)
		count.Text = "0"
		count.TextXAlignment = Enum.TextXAlignment.Right
		count.AnchorPoint = Vector2.new(1, 0.5)
		count.Position = UDim2.new(1, -10, 0.5, 0)
		count.Size = UDim2.fromOffset(34, TAB_H)
		count.ZIndex = 45
		count.Parent = surface

		-- Selection is a ring, never a fill change (doc §4.3): the gold ring
		-- sits OUTSIDE the black rim on its own frame and just toggles Visible.
		local ring = UIStyler.Frame("SelRing")
		ring.BackgroundTransparency = 1
		ring.Position = UDim2.fromOffset(-3, -3)
		ring.Size = UDim2.new(1, 6, 1, 6)
		ring.Visible = false
		ring.ZIndex = 45
		local ringStroke = UIChrome.Stroke(theme, "Arcade", "Selection")
		ringStroke.Parent = ring
		ring.Parent = root

		hit.Activated:Connect(function()
			if self._category == category.id then
				return
			end
			self._category = category.id
			UIChrome.Pulse(theme, surface)
			self:_SyncTabs()
			self:_RenderGrid()
		end)
		-- animate() is applied LAST, after the final colours (doc §5.1).
		UIChrome.Animate(theme, hit, surface)

		self._tabs[category.id] = { ring = ringStroke, label = text, count = count, frame = ring }
	end
end

function InventoryScreen:_SyncTabs()
	if self._builtLayout == "GP" then
		self:_SyncGPTabs()
		return
	end
	if self._builtLayout == "AC" then
		self:_SyncACRail()
		return
	end
	local theme = self:GetTheme()
	local counts: { [string]: number } = { all = #self._items }
	for _, entry in self._items do
		counts[entry.category] = (counts[entry.category] or 0) + 1
	end
	for _, category in CATEGORIES do
		local tab = self._tabs[category.id]
		if tab then
			local selected = self._category == category.id
			tab.frame.Visible = selected
			tab.label.TextColor3 = if selected then theme.Semantic.Selection else WHITE
			tab.count.Text = tostring(counts[category.id] or 0)
		end
	end
end

-- ========================================================================
-- Slot grid
-- ========================================================================

function InventoryScreen:_BuildGrid(theme: Types.UITheme, content: Frame)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Slots"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(TABS_W + GAP, BODY_Y)
	scroll.Size = UDim2.fromOffset(GRID_W, BODY_H)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = theme.Arcade.Gold
	scroll.ZIndex = 43
	scroll.Parent = content
	self._scroll = scroll

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(SLOT, SLOT)
	grid.CellPadding = UDim2.fromOffset(SLOT_PAD, SLOT_PAD)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.FillDirectionMaxCells = COLUMNS
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
	grid.Parent = scroll

	local empty = UIChrome.Text("EmptyHint", 24, theme.Arcade.GreyOwned)
	empty.Text = "NOTHING MATCHES THAT"
	empty.Size = UDim2.fromOffset(GRID_W, 60)
	empty.Position = UDim2.fromOffset(TABS_W + GAP, BODY_Y + 40)
	empty.Visible = false
	empty.ZIndex = 43
	empty.Parent = content
	self._gridEmpty = empty
end

function InventoryScreen:_BuildSlot(theme: Types.UITheme, entry: Item, order: number)
	local locked = entry.locked == true

	local root = UIStyler.Frame("Slot_" .. entry.id)
	root.BackgroundTransparency = 1
	root.LayoutOrder = order
	root.ZIndex = 43
	root.Parent = self._scroll

	-- Whole-cell hit target UNDER the visual subtree: plain frames/labels never
	-- sink input, so every pixel of the slot answers (doc §11.6).
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 43
	hit.Parent = root

	local surface = UIStyler.Frame("Surface")
	surface.BackgroundColor3 = theme.Arcade.NearBlack
	surface.BackgroundTransparency = if locked then 0.35 else 0
	surface.AnchorPoint = Vector2.new(0.5, 0.5)
	surface.Position = UDim2.fromScale(0.5, 0.5)
	surface.Size = UDim2.fromScale(1, 1)
	surface.ZIndex = 44
	UIChrome.Corner("Arcade").Parent = surface
	UIChrome.Stroke(theme, "Arcade", "Panel").Parent = surface
	UIChrome.GlassGradient().Parent = surface
	surface.Parent = root

	-- Rarity ring: inset inside the black rim, drawn through the selection
	-- stroke policy (3px, border mode) and only re-tinted to the rarity colour.
	local rarityRing = UIStyler.Frame("RarityRing")
	rarityRing.BackgroundTransparency = 1
	rarityRing.Position = UDim2.fromOffset(5, 5)
	rarityRing.Size = UDim2.new(1, -10, 1, -10)
	rarityRing.ZIndex = 45
	local rarityStroke = UIChrome.Stroke(theme, "Arcade", "Selection")
	rarityStroke.Color = rarityColor(theme, entry.rarity)
	rarityStroke.Transparency = if locked then 0.45 else 0
	rarityStroke.Parent = rarityRing
	rarityRing.Parent = surface

	local icon = IconArchive.Image(surface, entry.icon, 58)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.48)
	icon.ZIndex = 46
	if icon:IsA("ImageLabel") and locked then
		icon.ImageTransparency = 0.45
	end

	if locked then
		local lock = IconArchive.Image(surface, "lock", 20)
		lock.Position = UDim2.fromOffset(7, 7)
		lock.ZIndex = 47
	end
	if entry.favorite then
		local star = IconArchive.Image(surface, "star", 20, { golden = true })
		star.AnchorPoint = Vector2.new(1, 0)
		star.Position = UDim2.new(1, -7, 0, 7)
		star.ZIndex = 47
	end
	if self._equippedId == entry.id then
		-- Bottom-LEFT: the lock/star markers own the top corners and the stack
		-- chip owns the bottom-right.
		local mark = UIChrome.Text("Equipped", 11, theme.Arcade.MoneyGreen)
		mark.Text = "EQUIPPED"
		mark.TextXAlignment = Enum.TextXAlignment.Left
		mark.AnchorPoint = Vector2.new(0, 1)
		mark.Position = UDim2.new(0, 7, 1, -7)
		mark.Size = UDim2.fromOffset(60, 14)
		mark.ZIndex = 47
		mark.Parent = surface
	end

	if entry.count and entry.count > 1 then
		-- Micro badge tier (doc §2): 11px, bottom-right of the well.
		local chip = UIStyler.Frame("Count")
		chip.BackgroundColor3 = theme.Arcade.NearBlack2
		chip.AnchorPoint = Vector2.new(1, 1)
		chip.Position = UDim2.new(1, -5, 1, -5)
		chip.Size = UDim2.fromOffset(42, 20)
		chip.ZIndex = 47
		UIChrome.Corner("Arcade").Parent = chip
		UIChrome.Stroke(theme, "Arcade", "Button").Parent = chip
		chip.Parent = surface

		local count = UIChrome.Text("N", 11, theme.Arcade.IceBlue)
		count.RichText = false
		count.Text = "x" .. tostring(entry.count)
		count.Size = UDim2.fromScale(1, 1)
		count.ZIndex = 48
		count.Parent = chip
	end

	local ring = UIStyler.Frame("SelRing")
	ring.BackgroundTransparency = 1
	ring.Position = UDim2.fromOffset(-3, -3)
	ring.Size = UDim2.new(1, 6, 1, 6)
	ring.Visible = self._selectedId == entry.id
	ring.ZIndex = 45
	UIChrome.Stroke(theme, "Arcade", "Selection").Parent = ring
	ring.Parent = root

	hit.Activated:Connect(function()
		self:_Select(entry.id)
		UIChrome.Pulse(theme, surface)
	end)
	UIChrome.Animate(theme, hit, surface)
end

function InventoryScreen:_VisibleItems(): { Item }
	local filtered = {}
	for _, entry in self._items do
		local categoryOk = self._category == "all" or entry.category == self._category
		local queryOk = self._query == "" or string.find(string.lower(entry.name), self._query, 1, true) ~= nil
		if categoryOk and queryOk then
			table.insert(filtered, entry)
		end
	end

	local mode = self._sortMode
	if mode == "name" then
		table.sort(filtered, function(a: Item, b: Item)
			return a.name < b.name
		end)
	elseif mode == "recent" then
		-- "Recent" is newest-acquired first: the source list is oldest-first.
		local reversed = {}
		for i = #filtered, 1, -1 do
			table.insert(reversed, filtered[i])
		end
		filtered = reversed
	else
		table.sort(filtered, function(a: Item, b: Item)
			local ra = RARITY_RANK[a.rarity] or 0
			local rb = RARITY_RANK[b.rarity] or 0
			if ra ~= rb then
				return ra > rb
			end
			return a.name < b.name
		end)
	end
	return filtered
end

function InventoryScreen:_RenderGrid()
	if self._builtLayout == "GP" then
		self:_RenderGPList()
		return
	end
	if self._builtLayout == "AC" then
		self:_RenderACList()
		return
	end
	if not self._scroll then
		return
	end
	local theme = self:GetTheme()
	for _, child in self._scroll:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local visible = self:_VisibleItems()
	for order, entry in visible do
		self:_BuildSlot(theme, entry, order)
	end
	if self._gridEmpty then
		self._gridEmpty.Visible = #visible == 0
	end
end

-- ========================================================================
-- Detail pane
-- ========================================================================

function InventoryScreen:_BuildDetail(theme: Types.UITheme, content: Frame)
	local pane = UIChrome.Panel(theme, "Arcade", "Detail")
	pane.Position = UDim2.fromOffset(DETAIL_X, BODY_Y)
	pane.Size = UDim2.fromOffset(DETAIL_W, BODY_H)
	pane.ZIndex = 43
	pane.Parent = content
	self._detail = pane

	local hint = UIChrome.Text("Hint", 22, theme.Arcade.GreyOwned)
	hint.Text = "SELECT AN ITEM"
	hint.Size = UDim2.fromScale(1, 1)
	hint.ZIndex = 44
	hint.Parent = pane
	self._detailHint = hint

	local body = UIStyler.Frame("Body")
	body.BackgroundTransparency = 1
	body.Size = UDim2.fromScale(1, 1)
	body.Visible = false
	body.ZIndex = 44
	body.Parent = pane
	self._detailBody = body

	local well = UIStyler.Frame("ArtWell")
	well.BackgroundColor3 = theme.Arcade.NearBlack
	well.AnchorPoint = Vector2.new(0.5, 0)
	well.Position = UDim2.new(0.5, 0, 0, PAD)
	well.Size = UDim2.fromOffset(168, 168)
	well.ZIndex = 45
	UIChrome.Corner("Arcade").Parent = well
	UIChrome.Stroke(theme, "Arcade", "Panel").Parent = well
	UIChrome.GlassGradient().Parent = well
	well.Parent = body

	local ring = UIStyler.Frame("RarityRing")
	ring.BackgroundTransparency = 1
	ring.Position = UDim2.fromOffset(6, 6)
	ring.Size = UDim2.new(1, -12, 1, -12)
	ring.ZIndex = 46
	self._detailRing = UIChrome.Stroke(theme, "Arcade", "Selection")
	self._detailRing.Parent = ring
	ring.Parent = well
	self._detailWell = well

	local name = UIChrome.Text("Name", 28, WHITE)
	name.RichText = false
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(PAD, 196)
	name.Size = UDim2.fromOffset(DETAIL_W - PAD * 2, 34)
	name.ZIndex = 45
	name.Parent = body
	self._detailName = name

	local meta = UIChrome.Text("Meta", 17, theme.Arcade.Gold)
	meta.RichText = false
	meta.Position = UDim2.fromOffset(PAD, 232)
	meta.Size = UDim2.fromOffset(DETAIL_W - PAD * 2, 22)
	meta.ZIndex = 45
	meta.Parent = body
	self._detailMeta = meta

	local rule = UIStyler.Frame("Rule")
	rule.BackgroundColor3 = theme.Arcade.NearBlack
	rule.Position = UDim2.fromOffset(PAD, 264)
	rule.Size = UDim2.fromOffset(DETAIL_W - PAD * 2, 2)
	rule.ZIndex = 45
	rule.Parent = body

	local description = UIChrome.BodyText("Description", 17, theme.Arcade.IceBlue)
	description.RichText = false
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.TextYAlignment = Enum.TextYAlignment.Top
	description.Position = UDim2.fromOffset(PAD, 278)
	description.Size = UDim2.fromOffset(DETAIL_W - PAD * 2, 92)
	description.ZIndex = 45
	-- TextWrapped is the only wrap assignment here (TextScaled stays off), so
	-- the long-text safety of doc §2 comes from the fixed 17px body size.
	description.TextWrapped = true
	description.Parent = body
	self._detailDescription = description

	local statsTitle = UIChrome.Text("StatsTitle", 17, theme.Arcade.Gold)
	statsTitle.Text = "STATS"
	statsTitle.TextXAlignment = Enum.TextXAlignment.Left
	statsTitle.Position = UDim2.fromOffset(PAD, 378)
	statsTitle.Size = UDim2.fromOffset(DETAIL_W - PAD * 2, 22)
	statsTitle.ZIndex = 45
	statsTitle.Parent = body
	self._detailStatsTitle = statsTitle

	local stats = UIStyler.Frame("Stats")
	stats.BackgroundTransparency = 1
	stats.Position = UDim2.fromOffset(PAD, 406)
	stats.Size = UDim2.fromOffset(DETAIL_W - PAD * 2, 140)
	stats.ZIndex = 45
	stats.Parent = body
	UIStyler.ListLayout({ Padding = UDim.new(0, 4), HorizontalAlignment = Enum.HorizontalAlignment.Left }).Parent = stats
	self._detailStats = stats

	self._equipBtn = UIButtonComponent.new()
	self._equipBtn:Create(body, {
		text = "EQUIP",
		variant = "Green",
		size = UDim2.fromOffset(DETAIL_W - PAD * 2, 48),
		-- Bottom-anchored so it stacks CLEARLY above the DROP/FAVOURITE row
		-- (which occupies the last 48px + PAD of the pane).
		position = UDim2.new(0.5, 0, 1, -(PAD + 48 + 10)),
		anchorPoint = Vector2.new(0.5, 1),
		onClick = function()
			self:_Equip()
		end,
	})
	self._equipBtn.Root.ZIndex = 46

	self._dropBtn = UIButtonComponent.new()
	self._dropBtn:Create(body, {
		text = "DROP",
		variant = "Red",
		size = UDim2.fromOffset(168, 48),
		position = UDim2.new(0, PAD, 1, -PAD),
		anchorPoint = Vector2.new(0, 1),
		onClick = function()
			self:_Drop()
		end,
	})
	self._dropBtn.Root.ZIndex = 46

	self._favBtn = UIButtonComponent.new()
	self._favBtn:Create(body, {
		text = "FAVOURITE",
		variant = "Ghost",
		iconId = IconArchive.Id("star", { golden = true }),
		size = UDim2.fromOffset(168, 48),
		position = UDim2.new(1, -PAD, 1, -PAD),
		anchorPoint = Vector2.new(1, 1),
		onClick = function()
			self:_ToggleFavorite()
		end,
	})
	self._favBtn.Root.ZIndex = 46
end

function InventoryScreen:_RenderDetail()
	if self._builtLayout == "GP" then
		self:_RenderGPDetail()
		return
	end
	if self._builtLayout == "AC" then
		self:_RenderACDetail()
		return
	end
	local theme = self:GetTheme()
	local entry = self:_Find(self._selectedId)
	if not self._detailBody then
		return
	end
	self._detailBody.Visible = entry ~= nil
	self._detailHint.Visible = entry == nil
	if not entry then
		return
	end

	local color = rarityColor(theme, entry.rarity)
	self._detailRing.Color = color
	self._detailName.Text = entry.name
	self._detailName.TextColor3 = color
	self._detailMeta.Text = string.format(
		"%s  ·  %s  ·  x%d",
		string.upper(entry.rarity or "COMMON"),
		string.upper(entry.category or ""),
		entry.count or 1
	)
	self._detailDescription.Text = entry.description or "No description recorded for this item."

	if self._detailArt then
		self._detailArt:Destroy()
	end
	local art = IconArchive.Image(self._detailWell, entry.icon, 108, { golden = entry.rarity == "Legendary" })
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.5)
	art.ZIndex = 47
	self._detailArt = art

	for _, row in self._statRows do
		row:Destroy()
	end
	table.clear(self._statRows)
	local lines = statLines(entry.stats)
	self._detailStatsTitle.Visible = #lines > 0
	for order, line in lines do
		local row = UIStyler.Frame("Stat" .. order)
		row.BackgroundTransparency = 1
		row.LayoutOrder = order
		row.Size = UDim2.new(1, 0, 0, 28)
		row.ZIndex = 45
		row.Parent = self._detailStats

		local key = UIChrome.BodyText("Key", 17, theme.Arcade.IceBlue)
		key.RichText = false
		key.Text = line.label
		key.TextXAlignment = Enum.TextXAlignment.Left
		key.Size = UDim2.new(0.6, 0, 1, 0)
		key.ZIndex = 45
		key.Parent = row

		local value = UIChrome.Text("Value", 20, theme.Arcade.Gold)
		value.RichText = false
		value.Text = line.value
		value.TextXAlignment = Enum.TextXAlignment.Right
		value.Position = UDim2.fromScale(0.6, 0)
		value.Size = UDim2.new(0.4, 0, 1, 0)
		value.ZIndex = 45
		value.Parent = row

		table.insert(self._statRows, row)
	end

	-- Blocked controls dim IN PLACE and still answer on tap (doc §11.1/§11.2).
	local locked = entry.locked == true
	local equipped = self._equippedId == entry.id
	self._equipBtn:SetContent({
		text = if equipped then "EQUIPPED" else "EQUIP",
		variant = if equipped then "Grey" else "Green",
		dimmed = locked,
	})
	self._dropBtn:SetContent({ text = "DROP", variant = "Red", dimmed = locked })
	self._favBtn:SetContent({
		text = "FAVOURITE",
		variant = if entry.favorite then "Gold" else "Ghost",
		iconId = IconArchive.Id("star", { golden = true }),
	})
end

function InventoryScreen:_Select(id: string)
	self._selectedId = id
	for _, slot in self._scroll:GetChildren() do
		if slot:IsA("GuiObject") then
			local ring = slot:FindFirstChild("SelRing")
			if ring and ring:IsA("GuiObject") then
				ring.Visible = slot.Name == "Slot_" .. id
			end
		end
	end
	self:_RenderDetail()
end

-- ========================================================================
-- Actions
-- ========================================================================

function InventoryScreen:_Equip()
	local entry = self:_Find(self._selectedId)
	if not entry then
		return
	end
	if entry.locked then
		self:_Toast(entry.name .. " IS LOCKED", "Error")
		return
	end
	if self._equippedId == entry.id then
		self:_Toast(entry.name .. " IS ALREADY EQUIPPED", "Info")
		return
	end
	self._equippedId = entry.id
	self:_Toast("EQUIPPED " .. entry.name, "Success")
	self:_RenderGrid()
	self:_RenderDetail()
end

function InventoryScreen:_Drop()
	local entry = self:_Find(self._selectedId)
	if not entry then
		return
	end
	if entry.locked then
		self:_Toast(entry.name .. " IS LOCKED", "Error")
		return
	end
	for index, candidate in self._items do
		if candidate.id == entry.id then
			table.remove(self._items, index)
			break
		end
	end
	if self._equippedId == entry.id then
		self._equippedId = nil
	end
	self._selectedId = nil
	self:_Toast("DROPPED " .. entry.name, "Warning")
	self:_Render()
end

function InventoryScreen:_ToggleFavorite()
	local entry = self:_Find(self._selectedId)
	if not entry then
		return
	end
	entry.favorite = not entry.favorite
	UIChrome.Pulse(self:GetTheme(), self._favBtn.Root)
	self:_RenderGrid()
	self:_RenderDetail()
end

-- ========================================================================
-- AC layout (theme.LayoutKit == "AC") — the terminal INVENTORY page: left
-- category/sort rail, dense mono item rows (name in rarity ink / qty /
-- state marker) and a bracketed detail pane whose numeric stats ride
-- UIStatRowComponent ladder rows. The shared render methods dispatch here,
-- so Update/_OnShow and every action callback work unchanged.
-- ========================================================================

local AC_RAIL_W = 190
local AC_DETAIL_W = 340
local AC_GAP = 20
local AC_ROW_H = 26

-- The same sort modes the classic dropdown offers.
local AC_SORT_MODES = {
	{ id = "rarity", label = "RARITY" },
	{ id = "name", label = "NAME" },
	{ id = "recent", label = "RECENT" },
}

-- The AC action buttons are raw hairline TextButtons; this wrapper covers
-- the slice of the component contract the shared methods touch (:Destroy
-- from InventoryScreen:Destroy, .Root from _ToggleFavorite's pulse).
local function wrapAction(button: TextButton): any
	return {
		Root = button,
		Destroy = function()
			button:Destroy()
		end,
	}
end

-- "148" / "12%" / "4.0/s" / "1,480" -> whole number + unit suffix for the
-- stat ladder; nil for values that are fractional or not numeric at all
-- (those keep their exact text on a plain line instead, so no data is
-- rounded away).
local function parseStatValue(value: string): (number?, string?)
	local raw = string.gsub(value, ",", "")
	local numberText, unitText = string.match(raw, "^%+?(%-?%d+%.?%d*)%s*(.*)$")
	local numeric = if numberText then tonumber(numberText) else nil
	if numeric and numeric == math.round(numeric) then
		return numeric, if unitText ~= nil and unitText ~= "" then unitText else nil
	end
	return nil, nil
end

function InventoryScreen:_BuildACLayout()
	local theme = self:GetTheme()

	-- Stale classic handles must not leak into the terminal page: _OnShow
	-- pops _modal and _SyncTabs walks _tabs. The classic search box does not
	-- exist here, so its filter resets with it.
	self._modal = nil
	self._tabs = {}
	self._query = ""
	self._acRailCounts = {} :: { [string]: TextLabel }
	self._acCategoryRail = nil :: any
	self._acStatRows = {} :: { any }

	local shell = ACLayoutKit.Shell(theme, self.Root, "INVENTORY")
	ACLayoutKit.SetHints(shell, {
		{ key = "CLICK", action = "SELECT" },
		{ key = "ESC", action = "CLOSE" },
	})

	-- Top-right status readout replaces the classic capacity ruler; the
	-- wrapper keeps _Render's :Set(value, max) contract alive.
	local capacityLabel = UIChrome.BodyText("Capacity", 12, theme.Colors.TextSecondary)
	capacityLabel.TextXAlignment = Enum.TextXAlignment.Right
	capacityLabel.Size = UDim2.fromOffset(150, 16)
	capacityLabel.Parent = shell.topRight
	self._capacity = {
		Set = function(_wrapper: any, value: number, maxValue: number)
			capacityLabel.Text = string.format("STORAGE %d/%d", value, maxValue)
		end,
		Destroy = function() end,
	} :: any

	-- Left rail: the same categories and sort modes classic offers.
	local railColumn = UIStyler.Frame("RailColumn")
	railColumn.BackgroundTransparency = 1
	railColumn.Size = UDim2.new(0, AC_RAIL_W, 1, 0)
	railColumn.Parent = shell.content
	UIStyler.ListLayout({
		Padding = UDim.new(0, 4),
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	}).Parent = railColumn

	ACLayoutKit.SectionLabel(theme, railColumn, "CATEGORY", 1)
	local categoryRail = ACLayoutKit.Rail(theme, railColumn, AC_RAIL_W)
	categoryRail.frame.LayoutOrder = 2
	categoryRail.frame.Size = UDim2.new(1, 0, 0, #CATEGORIES * 28)
	for _, category in CATEGORIES do
		local id = category.id
		local row = categoryRail.AddEntry(category.label, function()
			if self._category ~= id then
				self._category = id
				self:_SyncTabs()
				self:_RenderGrid()
			end
		end)
		local count = UIChrome.BodyText("Count", 11, theme.Colors.TextSecondary)
		count.Text = "0"
		count.TextXAlignment = Enum.TextXAlignment.Right
		count.AnchorPoint = Vector2.new(1, 0.5)
		count.Position = UDim2.new(1, -6, 0.5, 0)
		count.Size = UDim2.fromOffset(40, 14)
		count.Parent = row
		self._acRailCounts[id] = count
	end
	self._acCategoryRail = categoryRail :: any

	local spacer = UIStyler.Frame("Spacer")
	spacer.BackgroundTransparency = 1
	spacer.LayoutOrder = 3
	spacer.Size = UDim2.new(1, 0, 0, 8)
	spacer.Parent = railColumn

	ACLayoutKit.SectionLabel(theme, railColumn, "SORT", 4)
	local sortRail = ACLayoutKit.Rail(theme, railColumn, AC_RAIL_W)
	sortRail.frame.LayoutOrder = 5
	sortRail.frame.Size = UDim2.new(1, 0, 0, #AC_SORT_MODES * 28)
	for index, mode in AC_SORT_MODES do
		local id = mode.id
		sortRail.AddEntry(mode.label, function()
			if self._sortMode ~= id then
				self._sortMode = id
				self:_RenderGrid()
			end
		end)
		if id == self._sortMode then
			sortRail.Select(index)
		end
	end
	self._sort = { Destroy = function() end } :: any

	-- Centre: dense data rows under fixed column captions.
	local centre = UIStyler.Frame("ListColumn")
	centre.BackgroundTransparency = 1
	centre.Position = UDim2.fromOffset(AC_RAIL_W + AC_GAP, 0)
	centre.Size = UDim2.new(1, -(AC_RAIL_W + AC_GAP + AC_DETAIL_W + AC_GAP), 1, 0)
	centre.Parent = shell.content

	ACLayoutKit.ListRow(theme, centre, {
		{ text = "ITEM", widthScale = 0.58, dim = true },
		{ text = "QTY", widthScale = 0.18, align = Enum.TextXAlignment.Right, dim = true },
		{ text = "STATE", widthScale = 0.24, align = Enum.TextXAlignment.Right, dim = true },
	}, { heightPx = 20 })

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Slots"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, 24)
	scroll.Size = UDim2.new(1, 0, 1, -24)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = theme.Colors.Accent
	scroll.Parent = centre
	UIStyler.ListLayout({ HorizontalAlignment = Enum.HorizontalAlignment.Left }).Parent = scroll
	self._scroll = scroll

	local empty = UIChrome.BodyText("EmptyHint", 12, theme.Colors.TextSecondary)
	empty.Text = "NOTHING MATCHES THAT"
	empty.TextXAlignment = Enum.TextXAlignment.Left
	empty.Position = UDim2.fromOffset(0, 32)
	empty.Size = UDim2.new(1, 0, 0, 20)
	empty.Visible = false
	empty.Parent = centre
	self._gridEmpty = empty

	-- Right: hairline detail pane with corner brackets.
	local pane = UIStyler.Frame("Detail")
	pane.BackgroundColor3 = theme.Colors.Surface
	pane.BackgroundTransparency = 0.2
	pane.AnchorPoint = Vector2.new(1, 0)
	pane.Position = UDim2.fromScale(1, 0)
	pane.Size = UDim2.new(0, AC_DETAIL_W, 1, 0)
	UIChrome.Stroke(theme, "Arcade", "Panel").Parent = pane
	pane.Parent = shell.content
	ACLayoutKit.Brackets(theme, pane)
	self._detail = pane

	local hint = UIChrome.BodyText("Hint", 12, theme.Colors.TextSecondary)
	hint.Text = "SELECT AN ITEM"
	hint.Size = UDim2.fromScale(1, 1)
	hint.Parent = pane
	self._detailHint = hint

	local body = UIStyler.Frame("Body")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(14, 12)
	body.Size = UDim2.new(1, -28, 1, -24)
	body.Visible = false
	body.Parent = pane
	self._detailBody = body

	local name = UIChrome.Text("Name", 16, theme.Colors.TextPrimary)
	name.RichText = false
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Size = UDim2.new(1, 0, 0, 20)
	name.Parent = body
	self._detailName = name

	local meta = UIChrome.BodyText("Meta", 11, theme.Colors.TextSecondary)
	meta.RichText = false
	meta.TextXAlignment = Enum.TextXAlignment.Left
	meta.Position = UDim2.fromOffset(0, 22)
	meta.Size = UDim2.new(1, 0, 0, 16)
	meta.Parent = body
	self._detailMeta = meta

	local rule = ACLayoutKit.Rule(theme, body)
	rule.Position = UDim2.fromOffset(0, 44)

	local description = UIChrome.BodyText("Description", 12, theme.Colors.TextSecondary)
	description.RichText = false
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.TextYAlignment = Enum.TextYAlignment.Top
	description.TextWrapped = true
	description.Position = UDim2.fromOffset(0, 52)
	description.Size = UDim2.new(1, 0, 0, 84)
	description.Parent = body
	self._detailDescription = description

	local statsTitle = ACLayoutKit.SectionLabel(theme, body, "STATS")
	statsTitle.Position = UDim2.fromOffset(0, 144)
	self._detailStatsTitle = statsTitle

	local stats = UIStyler.Frame("Stats")
	stats.BackgroundTransparency = 1
	stats.Position = UDim2.fromOffset(0, 164)
	stats.Size = UDim2.new(1, 0, 1, -248)
	stats.Parent = body
	UIStyler.ListLayout({
		Padding = UDim.new(0, 6),
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	}).Parent = stats
	self._detailStats = stats

	local equip = ACLayoutKit.ActionButton(theme, body, "EQUIP", function()
		self:_Equip()
	end)
	equip.AnchorPoint = Vector2.new(0, 1)
	equip.Position = UDim2.new(0, 0, 1, -38)
	equip.Size = UDim2.new(1, 0, 0, 30)
	self._equipBtn = wrapAction(equip)

	local drop = ACLayoutKit.ActionButton(theme, body, "DROP", function()
		self:_Drop()
	end)
	drop.AnchorPoint = Vector2.new(0, 1)
	drop.Position = UDim2.new(0, 0, 1, 0)
	drop.Size = UDim2.new(0.5, -4, 0, 30)
	self._dropBtn = wrapAction(drop)

	local fav = ACLayoutKit.ActionButton(theme, body, "FAVOURITE", function()
		self:_ToggleFavorite()
	end)
	fav.AnchorPoint = Vector2.new(1, 1)
	fav.Position = UDim2.new(1, 0, 1, 0)
	fav.Size = UDim2.new(0.5, -4, 0, 30)
	self._favBtn = wrapAction(fav)

	self:_Render()
end

function InventoryScreen:_SyncACRail()
	local counts: { [string]: number } = { all = #self._items }
	for _, entry in self._items do
		counts[entry.category] = (counts[entry.category] or 0) + 1
	end
	for _, category in CATEGORIES do
		local label = self._acRailCounts and self._acRailCounts[category.id]
		if label then
			label.Text = tostring(counts[category.id] or 0)
		end
	end
	local rail = self._acCategoryRail
	if rail then
		for index, category in CATEGORIES do
			if category.id == self._category then
				rail.Select(index)
				break
			end
		end
	end
end

function InventoryScreen:_BuildACRow(theme: Types.UITheme, entry: Item, order: number)
	local locked = entry.locked == true
	local state: string
	local stateColor: Color3
	if self._equippedId == entry.id then
		state, stateColor = "EQP", theme.Colors.Success
	elseif locked then
		state, stateColor = "LOCK", theme.Colors.TextSecondary
	elseif entry.favorite then
		state, stateColor = "FAV", theme.Semantic.Selection
	else
		state, stateColor = "", theme.Colors.TextSecondary
	end

	local row, labels = ACLayoutKit.ListRow(theme, self._scroll, {
		{ text = entry.name, widthScale = 0.58, color = rarityColor(theme, entry.rarity) },
		{ text = tostring(entry.count or 1), widthScale = 0.18, align = Enum.TextXAlignment.Right },
		{ text = state, widthScale = 0.24, align = Enum.TextXAlignment.Right, color = stateColor },
	}, { heightPx = AC_ROW_H, layoutOrder = order, clickable = true })
	row.Name = "Slot_" .. entry.id
	if locked then
		labels[1].TextTransparency = 0.35
	end

	-- Selection marker riding the classic ring contract: _Select just toggles
	-- the "SelRing" child's Visible, so the AC accent notch needs no new code.
	local ring = UIStyler.Frame("SelRing")
	ring.BackgroundTransparency = 1
	ring.Size = UDim2.fromScale(1, 1)
	ring.Visible = self._selectedId == entry.id
	ring.Parent = row
	local notch = UIStyler.Frame("Notch")
	notch.BackgroundColor3 = theme.Colors.Accent
	notch.BorderSizePixel = 0
	notch.Position = UDim2.new(0, 0, 0, 4)
	notch.Size = UDim2.new(0, 3, 1, -8)
	notch.Parent = ring

	local button = row :: TextButton
	button.Activated:Connect(function()
		self:_Select(entry.id)
	end)
end

function InventoryScreen:_RenderACList()
	if not self._scroll then
		return
	end
	local theme = self:GetTheme()
	for _, child in self._scroll:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local visible = self:_VisibleItems()
	for order, entry in visible do
		self:_BuildACRow(theme, entry, order)
	end
	if self._gridEmpty then
		self._gridEmpty.Visible = #visible == 0
	end
end

-- Honest ladder scale: a stat's bar tops out at the highest value of the
-- SAME stat label anywhere in the bag, so bars compare items instead of
-- inventing a ceiling.
function InventoryScreen:_ACStatMax(label: string, fallback: number): number
	local best = fallback
	for _, entry in self._items do
		for _, line in statLines(entry.stats) do
			if line.label == label then
				local numeric = parseStatValue(line.value)
				if numeric and numeric > best then
					best = numeric
				end
			end
		end
	end
	return best
end

function InventoryScreen:_RenderACDetail()
	local theme = self:GetTheme()
	local entry = self:_Find(self._selectedId)
	if not self._detailBody then
		return
	end
	self._detailBody.Visible = entry ~= nil
	self._detailHint.Visible = entry == nil
	if not entry then
		return
	end

	self._detailName.Text = entry.name
	self._detailName.TextColor3 = rarityColor(theme, entry.rarity)
	self._detailMeta.Text = string.format(
		"%s  ·  %s  ·  x%d",
		string.upper(entry.rarity or "COMMON"),
		string.upper(entry.category or ""),
		entry.count or 1
	)
	self._detailDescription.Text = entry.description or "No description recorded for this item."

	for _, row in self._acStatRows do
		row:Destroy()
	end
	table.clear(self._acStatRows)
	local lines = statLines(entry.stats)
	self._detailStatsTitle.Visible = #lines > 0
	for order, line in lines do
		local numeric, unit = parseStatValue(line.value)
		if numeric then
			local statRow = UIStatRowComponent.new()
			statRow:Create(self._detailStats, {
				label = line.label,
				unit = unit,
				value = numeric,
				maxValue = self:_ACStatMax(line.label, numeric),
				layoutOrder = order,
			})
			table.insert(self._acStatRows, statRow)
		else
			local plainRow = ACLayoutKit.ListRow(theme, self._detailStats, {
				{ text = line.label, widthScale = 0.55, dim = true },
				{ text = line.value, widthScale = 0.45, align = Enum.TextXAlignment.Right },
			}, { heightPx = 22, layoutOrder = order })
			table.insert(self._acStatRows, plainRow)
		end
	end

	-- Blocked controls dim IN PLACE and still answer on tap (doc §11.1).
	local locked = entry.locked == true
	local equipped = self._equippedId == entry.id
	local equip = self._equipBtn.Root :: TextButton
	equip.Text = if equipped then "EQUIPPED" else "EQUIP"
	equip.TextColor3 = if locked or equipped then theme.Colors.TextSecondary else theme.Colors.Success
	local drop = self._dropBtn.Root :: TextButton
	drop.TextColor3 = if locked then theme.Colors.TextSecondary else theme.Colors.Error
	local fav = self._favBtn.Root :: TextButton
	fav.TextColor3 = if entry.favorite then theme.Semantic.Selection else theme.Colors.TextSecondary
end

-- ========================================================================
-- GP layout (theme.LayoutKit == "GP") — THE STUDIO SHELF, matte dialect.
--
-- This is the pack's ANTI-CONDESCENSION page (§0.3): a soft aesthetic is not
-- a simple one, so the information count here MEETS the Armored Core assembly
-- screen rather than trailing it. AC's spec panel carries two segmented bars
-- and NINE UIStatRowComponent rows with hover preview ghosts and an over-limit
-- state; this page carries two pastel gauges and NINE GPLayoutKit.StatRow rows
-- (five judging criteria + a four-row shelf/clay ladder) with the same hover
-- ghosts, the same invertGoodness mapping and the same over-limit story — at
-- ONE MORE decimal place (studio dialect statPrecision = 1 where AC rounds to
-- integers). It then adds a maker's-marks list of the piece's OWN stat table,
-- so nothing the AC detail pane shows is dropped here.
--
--   [ search + sort chips                                            ]
--   [ category tabs with live counts                                 ]
--   [ Piece            Glaze     On hand   State ]  [ piece plate    ]
--   [ petal rows, alternating mirror, glaze chip ]  [ kiln gauge     ]
--   [ ...                                        ]  [ 5 judging rows ]
--                                                   [ shelf gauge    ]
--                                                   [ 4 ladder rows  ]
--                                                   [ maker's marks  ]
--                                                   [ actions        ]
--
-- MATTE: no GlazeSheen anywhere on this dialect (Page is built with glaze =
-- false). Depth comes from petal silhouettes, hue-matched shadows and the clay
-- speckle grain — the glossy treatment belongs to celebration screens.
--
-- The shared render methods dispatch here, so Update/_OnShow, _Select and every
-- action callback work unchanged: rows are named "Slot_<id>" and carry a
-- "SelRing" child, which is the entire contract _Select relies on.
-- ========================================================================

local GP_PAGE = Vector2.new(1420, 880)
local GP_LIST_W = 812
local GP_STAT_W = 560
local GP_TOOLBAR_H = 40
local GP_TAB_BAR_H = 52
local GP_TAB_W = 152
local GP_TAB_H = 44
local GP_COLHEAD_H = 20
local GP_ROW_H = 62
local GP_ROW_GAP = 8
local GP_SCROLLBAR = 8
local GP_ACTIONS_H = 92
local GP_GAUGE_H = 56
local GP_GAUGE_SEGMENTS = 10
local GP_SPEC_ROW_H = 22
local GP_SEARCH_W = 320
local GP_SORT_CHIP_W = 118
local GP_PLATE_H = 96
local GP_DESC_H = 74

-- The piece row's column ladder, measured from the RIGHT edge so the numerals
-- stay flush down the whole list however long a name runs — the same rule the
-- AC list row and GPLayoutKit.StatRow are built on.
local GP_COL_STATE_W = 118
local GP_COL_COUNT_W = 74
local GP_COL_GLAZE_W = 108
local GP_COL_GAP = 10
local GP_ROW_ICON = 38
local GP_ROW_TEXT_X = 60
local GP_STATE_X = GP_COL_STATE_W
local GP_COUNT_X = GP_STATE_X + GP_COL_GAP + GP_COL_COUNT_W
local GP_GLAZE_X = GP_COUNT_X + GP_COL_GAP + GP_COL_GLAZE_W

-- The five judging criteria, in scoring order. FIRING is the peak kiln
-- temperature the piece reached rather than a 0-100 score, which is why it
-- carries its own unit and scale — a judged spread that is all one shape
-- teaches the reader nothing.
local GP_JUDGING: { { id: string, label: string, unit: string?, max: number } } = {
	{ id = "FORM", label = "Form", max = 100 },
	{ id = "SYMMETRY", label = "Symmetry", unit = "%", max = 100 },
	{ id = "GLAZE", label = "Glaze quality", max = 100 },
	{ id = "FIRING", label = "Firing", unit = "C", max = 1300 },
	{ id = "FLAIR", label = "Flair", max = 100 },
}

-- The totals ladder: a cost and its ceiling, twice — AC's WEIGHT/LOAD LIMIT and
-- EN LOAD/EN OUTPUT pairs in pottery terms. The costs are invertGoodness, so
-- the hover ghost paints "this piece leaving the shelf" GREEN.
local GP_LADDER: { { id: string, label: string, unit: string, invert: boolean? } } = {
	{ id = "WEIGHT", label = "Shelf weight", unit = "kg", invert = true },
	{ id = "LIMIT", label = "Shelf limit", unit = "kg" },
	{ id = "CLAY", label = "Clay used", unit = "kg", invert = true },
	{ id = "STOCK", label = "Clay stock", unit = "kg" },
}

-- Shelf and clay ceilings scale off the bag's own capacity, so a backend that
-- pushes a bigger shelf gets a bigger allowance rather than an instant fault.
local GP_KG_PER_SLOT = 2.7
local GP_CLAY_PER_SLOT = 6.5

-- The glaze ramp NAMES the theme's rarity ramp (cream -> sage -> sky ->
-- lavender -> rose-gold), so the chip colour and the chip word say the
-- same thing and meaning never rides on hue alone.
local GP_GLAZE_NAME = { "Bisque", "Sage", "Sky", "Lilac", "Rose gold" }

-- Presentation-only relabelling, keyed by the EXISTING category ids: the data
-- is untouched, but "CONSUMABLES" cannot appear on a page whose pack forbids
-- shouting. An id with no entry falls back to its re-cased source label.
local GP_CATEGORY_LABEL: { [string]: string } = {
	all = "All pieces",
	gear = "Tools",
	consumables = "Glazes",
	materials = "Clay",
	cosmetics = "Trim",
}

local GP_SORT_MODES = {
	{ id = "rarity", label = "Glaze" },
	{ id = "name", label = "Name" },
	{ id = "recent", label = "Newest" },
}

-- The bag's copy is authored in ALL CAPS for the arcade page, and law 5 of this
-- pack forbids shouting. string.upper appears here only as a TEST (is this
-- string already shouting?) and to lift a single leading letter — no all-caps
-- string is ever produced. A name that already carries mixed case is a
-- deliberate authoring choice and passes through untouched.
local function softCase(text: string): string
	if text ~= string.upper(text) then
		return text
	end
	local cased = string.gsub(string.lower(text), "(%a[%w']*)", function(word: string): string
		return string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2)
	end)
	return cased
end

-- Small exact-integer string hash (stays well inside 2^53, so it is stable
-- across machines and runs). Salt separates the draws one piece makes.
local function gpHash01(text: string, salt: number): number
	local h = 7919 + salt * 104729
	for index = 1, #text do
		h = (h * 31 + string.byte(text, index)) % 1000003
	end
	return h / 1000003
end

-- THE JUDGING PROFILE. The bag carries no judging record — the classic and AC
-- branches read entry.stats verbatim, and this page shows that table too, under
-- "Maker's marks" — so the five criteria are DERIVED: anchored by rarity so a
-- legendary really does score higher, jittered per piece id so no two pieces
-- read identically, and deterministic, so the same shelf renders the same
-- numbers on every build. Presentation only; nothing is written back.
local function gpProfile(entry: Item): { [string]: number }
	local rank = RARITY_RANK[entry.rarity] or 1
	local base = 44 + rank * 9
	local out: { [string]: number } = {}
	for index, def in GP_JUDGING do
		local jitter = (gpHash01(entry.id, index) - 0.5) * 22
		if def.id == "FIRING" then
			-- Rarity drives the peak temperature hard (a legendary piece went
			-- into a hotter kiln) with ±110 C of per-piece variance. The spread
			-- was checked against the real demo bag: all FIVE kiln states below
			-- occur, so no status string on this page is unreachable copy.
			out[def.id] = math.clamp(700 + rank * 112 + jitter * 10, 600, def.max)
		else
			out[def.id] = math.clamp(base + jitter, 4, 99.4)
		end
	end
	return out
end

-- The judged average across the four 0-100 criteria (FIRING is a temperature,
-- not a score, so it is deliberately excluded from the mean).
local function gpJudgedAverage(profile: { [string]: number }): number
	local sum, count = 0, 0
	for _, def in GP_JUDGING do
		if def.id ~= "FIRING" then
			sum += profile[def.id] or 0
			count += 1
		end
	end
	return if count > 0 then sum / count else 0
end

local function gpPieceWeight(entry: Item): number
	local rank = RARITY_RANK[entry.rarity] or 1
	return 1.4 + rank * 0.55 + gpHash01(entry.id, 91) * 1.9 + math.min(entry.count or 1, 40) * 0.03
end

local function gpPieceClay(entry: Item): number
	local rank = RARITY_RANK[entry.rarity] or 1
	return 2.2 + rank * 1.6 + gpHash01(entry.id, 137) * 3.1
end

local function gpGlazeColor(theme: Types.UITheme, rank: number): Color3
	local ramp = (theme.DialectTokens :: any) and (theme.DialectTokens :: any).rarity
	if ramp and ramp[rank] then
		return ramp[rank]
	end
	return theme.Colors.Surface
end

-- A Frame that is ALWAYS painted: UIStyler.Frame is born PURE WHITE, which this
-- pack forbids outright, so nothing on this page may use it bare.
local function gpFrame(name: string, fill: Color3, transparency: number?): Frame
	local frame = UIStyler.Frame(name)
	frame.BackgroundColor3 = fill
	frame.BackgroundTransparency = transparency or 0
	return frame
end

-- A frame that grows with its own list layout, for the stat groups inside the
-- scrolling stat column.
local function gpStack(name: string, fill: Color3, padding: number, layoutOrder: number, parent: Instance): Frame
	local host = gpFrame(name, fill, 1)
	host.AutomaticSize = Enum.AutomaticSize.Y
	host.Size = UDim2.new(1, 0, 0, 0)
	host.LayoutOrder = layoutOrder
	host.Parent = parent
	UIStyler.ListLayout({
		Padding = UDim.new(0, padding),
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	}).Parent = host
	return host
end

-- A soft status pill. The fill is the tone LIGHTENED toward cream so the ink
-- can stay TextPrimary: the raw tones measure as low as 3.3:1 under the warm
-- plum-brown, and this page has no large text to spend that on. Lightened,
-- every tone clears 6:1 — and the pill's WORD carries the meaning anyway, so
-- nothing here depends on the reader resolving a hue.
local function gpPill(theme: Types.UITheme, parent: Instance, widthPx: number, name: string): (Frame, TextLabel, UIStroke)
	local pill = gpFrame(name, theme.Colors.Surface, 0)
	pill.Size = UDim2.fromOffset(widthPx, 18)
	pill.Parent = parent
	UIStyler.Corner(theme.Radii.Pill).Parent = pill
	local stroke = GPLayoutKit.SoftStroke(theme, pill)
	local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "Text")
	label.Size = UDim2.fromScale(1, 1)
	label.Parent = pill
	return pill, label, stroke
end

local function gpPaintPill(theme: Types.UITheme, pill: Frame, stroke: UIStroke, tone: Color3)
	local fill = tone:Lerp(theme.Colors.Background, 0.62)
	pill.BackgroundColor3 = fill
	stroke.Color = GPLayoutKit.Deepen(theme, fill, 1)
end

-- ---- the pastel gauge ----------------------------------------------------

type GPGauge = {
	root: Frame,
	fill: Frame,
	readout: TextLabel,
	chip: Frame,
	chipLabel: TextLabel,
	chipStroke: UIStroke,
	chipScale: UIScale,
	Set: (ratio: number, readout: string, status: string, tone: Color3) -> (),
}

-- The rounded pastel gauge — this page's answer to the AC spec panel's
-- segmented bars. Sage tick hairlines ride OVER the fill so the reading stays
-- chunked even at full, because an unbroken pastel capsule reads as decoration
-- rather than a measurement.
local function gpGauge(theme: Types.UITheme, parent: Instance, caption: string, accent: Color3, layoutOrder: number): GPGauge
	local root = gpFrame("Gauge", theme.Colors.Background, 1)
	root.Size = UDim2.new(1, 0, 0, GP_GAUGE_H)
	root.LayoutOrder = layoutOrder
	root.Parent = parent

	local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Caption")
	label.Text = caption
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Size = UDim2.new(1, -200, 0, 18)
	label.Parent = root

	local readout = GPLayoutKit.NumberText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "Readout")
	readout.AnchorPoint = Vector2.new(1, 0)
	readout.Position = UDim2.fromScale(1, 0)
	readout.Size = UDim2.fromOffset(200, 18)
	readout.Parent = root

	local track = gpFrame("Track", theme.Arcade.RulerTrack, 0)
	track.Position = UDim2.fromOffset(0, 22)
	track.Size = UDim2.new(1, 0, 0, 12)
	track.ClipsDescendants = true
	track.Parent = root
	UIStyler.Corner(theme.Radii.Pill).Parent = track

	local fill = gpFrame("Fill", accent, 0)
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = 2
	fill.Parent = track
	UIStyler.Corner(theme.Radii.Pill).Parent = fill

	for index = 1, GP_GAUGE_SEGMENTS - 1 do
		local tick = gpFrame("Tick" .. index, theme.Studio.Tan, 0.3)
		tick.AnchorPoint = Vector2.new(0.5, 0)
		tick.Position = UDim2.fromScale(index / GP_GAUGE_SEGMENTS, 0)
		tick.Size = UDim2.new(0, 1, 1, 0)
		tick.ZIndex = 3
		tick.Parent = track
	end

	local chip, chipLabel, chipStroke = gpPill(theme, root, 200, "StatusChip")
	chip.AnchorPoint = Vector2.new(0, 0.5)
	chip.Position = UDim2.fromOffset(0, 47)
	-- The breathe scale lives on its OWN UIScale so it composes with anything
	-- else that ever touches the chip, and grows from the left edge outward.
	local chipScale = Instance.new("UIScale")
	chipScale.Parent = chip

	local function set(ratio: number, readoutText: string, status: string, tone: Color3)
		fill.Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
		readout.Text = readoutText
		chipLabel.Text = status
		gpPaintPill(theme, chip, chipStroke, tone)
	end

	return {
		root = root,
		fill = fill,
		readout = readout,
		chip = chip,
		chipLabel = chipLabel,
		chipStroke = chipStroke,
		chipScale = chipScale,
		Set = set,
	}
end

-- ---- soft action button --------------------------------------------------

type GPButton = { root: TextButton, shape: Frame, stroke: UIStroke, label: TextLabel, shadow: any }

-- The clickable root stays TRANSPARENT with its fill on a child: UIStyleEnforcer
-- backstops any SOLID GuiButton with a BLACK 2px stroke, which would violate
-- the pack's first law on sight.
local function gpButton(theme: Types.UITheme, parent: Instance, text: string, index: number, sink: { any }): GPButton
	local root = Instance.new("TextButton")
	root.Name = "GPAction"
	root.BackgroundTransparency = 1
	root.Text = ""
	root.AutoButtonColor = false
	root.Parent = parent

	local fill = theme.Colors.Surface
	local shape = gpFrame("Shape", fill, 0)
	shape.Size = UDim2.fromScale(1, 1)
	shape.Parent = root
	GPLayoutKit.Petal(theme, shape, index)
	local stroke = GPLayoutKit.SoftStroke(theme, shape)
	local shadow = GPLayoutKit.Shadow(theme, shape, "sm", sink, fill)

	local label = GPLayoutKit.Text(theme, theme.TextSizes.Button, theme.Colors.TextPrimary, "Label")
	label.Text = text
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 2
	label.Parent = shape

	-- Applied LAST, after the final colours (doc §5.1).
	UIChrome.Animate(theme, root, shape)
	return { root = root, shape = shape, stroke = stroke, label = label, shadow = shadow }
end

-- Blocked controls dim IN PLACE and still answer on tap (doc §11.1/§11.2): the
-- connection is never severed, only the ink and the fill soften.
local function gpPaintButton(theme: Types.UITheme, button: GPButton, text: string, fill: Color3, dimmed: boolean)
	local deep = GPLayoutKit.Deepen(theme, fill, 1)
	button.label.Text = text
	button.label.TextTransparency = if dimmed then 0.45 else 0
	button.shape.BackgroundColor3 = fill
	button.shape.BackgroundTransparency = if dimmed then 0.35 else 0
	button.stroke.Color = deep
	button.shadow.Instance.Color = deep
end

-- The over-limit state, AC's SetOverLimit in this pack's grammar. The NUMERAL
-- stays TextPrimary on purpose: Error ink on an error-tinted capsule measures
-- 2.31:1, so the state is carried by the capsule tint, the bar, the signed
-- delta and the spelled-out banner instead of by a red number nobody can read.
local function gpSetOverLimit(theme: Types.UITheme, row: any, stroke: UIStroke, over: boolean)
	row.capsule.BackgroundColor3 = if over
		then theme.Colors.Error:Lerp(theme.Colors.Background, 0.72)
		else theme.Colors.Surface
	row.fill.BackgroundColor3 = if over then theme.Colors.Error else theme.Colors.Primary
	stroke.Transparency = if over then 0.15 else 1
	stroke.Color = GPLayoutKit.Deepen(theme, theme.Colors.Error, 1)
end

-- ---- build ---------------------------------------------------------------

function InventoryScreen:_BuildGPLayout()
	-- Recorded FIRST: the shared render dispatchers read it, and _Render runs
	-- before this function returns.
	self._builtLayout = "GP"
	local theme = self:GetTheme()

	-- Stale classic/AC handles must not leak into the studio page: _SyncTabs
	-- walks _tabs, and the fresh search box is empty so the filter starts empty.
	self._tabs = {}
	self._query = ""
	self._gpShadows = {} :: { any }
	self._gpRows = {} :: { any }
	self._gpTabCounts = {} :: { [string]: TextLabel }
	self._gpSortChips = {} :: { [string]: any }
	self._gpJudge = {} :: { [string]: any }
	self._gpLadder = {} :: { [string]: any }
	self._gpLadderStrokes = {} :: { [string]: UIStroke }
	self._gpSpecRows = {} :: { GuiObject }
	self._gpLadderCap = nil :: number?

	local page = GPLayoutKit.Page(theme, self.Root, {
		titleText = "Studio shelf",
		subtitleText = "Every piece you have thrown, judged and shelved.",
		sizePx = GP_PAGE,
		-- MATTE dialect: no specular wash on a data page.
		glaze = false,
		onClose = function()
			self.ScreenController:HideScreen("inventory")
		end,
	})
	-- THE PAGE OPENS ITS OWN SINK and puts three handles in it (the panel's lg
	-- shadow, the header ribbon's md and the close chip's sm), so that array
	-- becomes this screen's sink rather than the empty one above — the contract
	-- Page documents and every other GP screen follows. Kept separate, those
	-- three would never reach ReleaseShadows and the live-shadow counter would
	-- climb by three on every style rebuild until it tripped the budget warning.
	self._gpShadows = page.shadows
	-- _OnShow pops _modal.content; handing it the panel gives the studio page
	-- the same entrance every other layout gets, with no new lifecycle code.
	self._modal = { content = page.panel } :: any

	-- The header counter, TextPrimary because it sits on ROSE: body-sized copy
	-- there measures 5.15:1 in the ink and 2.14:1 in the near-white.
	local shelfReadout = GPLayoutKit.NumberText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "ShelfCount")
	shelfReadout.Size = UDim2.fromOffset(260, 28)
	shelfReadout.Parent = page.topRight
	self._gpShelfReadout = shelfReadout

	-- The classic capacity ruler's contract, kept alive: _Render calls
	-- :Set(value, max) on whatever this slot holds, and a stale component from a
	-- previous style's build must never survive into this page.
	self._capacity = {
		Set = function(_wrapper: any, _value: number, maxValue: number)
			self._capacityMax = maxValue
			self:_RefreshGPShelf()
		end,
		Destroy = function() end,
	} :: any

	local content = page.content

	local list = gpFrame("PieceList", theme.Colors.Background, 1)
	list.Size = UDim2.new(0, GP_LIST_W, 1, 0)
	list.Parent = content

	local statColumn = gpFrame("StatBlock", theme.Colors.Background, 1)
	statColumn.AnchorPoint = Vector2.new(1, 0)
	statColumn.Position = UDim2.fromScale(1, 0)
	statColumn.Size = UDim2.new(0, GP_STAT_W, 1, 0)
	statColumn.Parent = content

	self:_BuildGPToolbar(theme, list)
	self:_BuildGPTabs(theme, list)
	self:_BuildGPListColumn(theme, list)
	self:_BuildGPStatColumn(theme, statColumn)

	-- ONE ticker handler for the whole page: the kiln chip breathes while the
	-- selected piece is still firing. Per-widget RunService loops are a rejected
	-- pattern, and bindTo means a destroyed page unregisters itself.
	local motion = ((theme.DialectTokens :: any) and (theme.DialectTokens :: any).motion) or {}
	self._gpBreatheScale = motion.breatheScale or 0.02
	self._gpBreatheSeconds = motion.breatheSeconds or 3
	self._gpTickerStop = UITicker.Register(function(_dt: number, now: number)
		self:_TickGP(now)
	end, page.panel)

	self:_Render()
end

function InventoryScreen:_BuildGPToolbar(theme: Types.UITheme, parent: Frame)
	local toolbar = gpFrame("Toolbar", theme.Colors.Background, 1)
	toolbar.Size = UDim2.new(1, 0, 0, GP_TOOLBAR_H)
	toolbar.Parent = parent

	-- Search: the chrome rides a wrapper frame, never the TextBox — a UIPadding
	-- on the box itself would also inset the magnifier child.
	local fieldFill = theme.Colors.SurfaceRaised
	local field = gpFrame("SearchField", fieldFill, 0)
	field.Size = UDim2.fromOffset(GP_SEARCH_W, GP_TOOLBAR_H)
	field.Parent = toolbar
	UIStyler.Corner(theme.Radii.Pill).Parent = field
	GPLayoutKit.SoftStroke(theme, field)
	GPLayoutKit.Shadow(theme, field, "sm", self._gpShadows, fieldFill)

	local searchIcon = IconArchive.Image(field, "search", 20)
	searchIcon.AnchorPoint = Vector2.new(0, 0.5)
	searchIcon.Position = UDim2.new(0, 12, 0.5, 0)

	local box = Instance.new("TextBox")
	box.Name = "Query"
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.Text = ""
	box.PlaceholderText = "Find a piece"
	box.PlaceholderColor3 = theme.Colors.TextSecondary
	box.FontFace = theme.Fonts.Body
	box.TextSize = theme.TextSizes.Body
	-- Ink, never white: UIStyler's TextBox-adjacent defaults are pure white and
	-- this pack has no white.
	box.TextColor3 = theme.Colors.TextPrimary
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Position = UDim2.fromOffset(42, 0)
	box.Size = UDim2.new(1, -54, 1, 0)
	box.Parent = field
	box:GetPropertyChangedSignal("Text"):Connect(function()
		self._query = string.lower(box.Text)
		self:_RenderGrid()
	end)

	local sortCaption = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "SortCaption")
	sortCaption.Text = "Sort by"
	sortCaption.TextXAlignment = Enum.TextXAlignment.Right
	sortCaption.Position = UDim2.fromOffset(GP_SEARCH_W + 16, 0)
	sortCaption.Size = UDim2.fromOffset(96, GP_TOOLBAR_H)
	sortCaption.Parent = toolbar

	local chipsW = #GP_SORT_MODES * GP_SORT_CHIP_W + (#GP_SORT_MODES - 1) * 8
	for index, mode in GP_SORT_MODES do
		local id = mode.id
		local chip = gpButton(theme, toolbar, mode.label, index, self._gpShadows)
		chip.root.Name = "Sort_" .. id
		chip.root.Position = UDim2.new(1, -chipsW + (index - 1) * (GP_SORT_CHIP_W + 8), 0, 0)
		chip.root.Size = UDim2.fromOffset(GP_SORT_CHIP_W, GP_TOOLBAR_H)
		chip.root.Activated:Connect(function()
			if self._sortMode == id then
				return
			end
			self._sortMode = id
			self:_SyncGPSort()
			self:_RenderGrid()
		end)
		self._gpSortChips[id] = chip
	end
	self:_SyncGPSort()

	-- The classic dropdown has no counterpart here (sort is three chips), but
	-- Destroy walks the same five component slots for every layout.
	self._sort = { Destroy = function() end } :: any
end

function InventoryScreen:_SyncGPSort()
	local theme = self:GetTheme()
	for id, chip in self._gpSortChips do
		local on = self._sortMode == id
		-- Body-sized copy on rose MUST be TextPrimary (5.15:1); the near-white
		-- TextOnPrimary measures 2.14:1 and is illegal at this size.
		gpPaintButton(theme, chip, chip.label.Text, if on then theme.Colors.Primary else theme.Colors.Surface, false)
	end
end

function InventoryScreen:_BuildGPTabs(theme: Types.UITheme, parent: Frame)
	local host = gpFrame("TabHost", theme.Colors.Background, 1)
	host.Position = UDim2.fromOffset(0, GP_TOOLBAR_H + 8)
	host.Size = UDim2.new(1, 0, 0, GP_TAB_BAR_H)
	host.Parent = parent

	local tabs = GPLayoutKit.Tabs(theme, host, {
		widthPx = GP_TAB_W,
		heightPx = GP_TAB_BAR_H,
		tabHeightPx = GP_TAB_H,
	}, self._gpShadows)

	for _, category in CATEGORIES do
		local id = category.id
		tabs.Add(GP_CATEGORY_LABEL[id] or softCase(category.label), id, function()
			if self._category == id then
				return
			end
			self._category = id
			self:_SyncTabs()
			self:_RenderGrid()
		end)
		-- The kit's TabBar owns caption, fill and underline; the live COUNT is
		-- this screen's information, so it is parented in beside the caption
		-- rather than dropped for want of a kit seam. Reached through the bar the
		-- kit handed back, not by guessing at the tree.
		local button = tabs.frame:FindFirstChild("Tab_" .. id)
		local shape = button and button:FindFirstChild("Shape")
		if shape then
			local count = GPLayoutKit.NumberText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Count")
			count.Text = "0"
			count.AnchorPoint = Vector2.new(1, 0)
			count.Position = UDim2.new(1, -10, 0, 6)
			count.Size = UDim2.fromOffset(30, 16)
			count.ZIndex = 6
			count.Parent = shape
			self._gpTabCounts[id] = count
		end
	end
	-- GPLayoutKit.Tabs never auto-selects; _SyncGPTabs does it on every render.
	self._gpTabs = tabs
end

function InventoryScreen:_SyncGPTabs()
	local counts: { [string]: number } = { all = #self._items }
	for _, entry in self._items do
		counts[entry.category] = (counts[entry.category] or 0) + 1
	end
	for id, label in self._gpTabCounts do
		label.Text = tostring(counts[id] or 0)
	end
	if self._gpTabs then
		self._gpTabs.Select(self._category)
	end
end

function InventoryScreen:_BuildGPListColumn(theme: Types.UITheme, parent: Frame)
	local top = GP_TOOLBAR_H + 8 + GP_TAB_BAR_H + 8

	-- Fixed column captions over the list, the AC list-row precedent: the reader
	-- is told what the numerals mean once, at the top, instead of per row.
	local header = gpFrame("ColumnHead", theme.Colors.Background, 1)
	header.Position = UDim2.fromOffset(0, top)
	header.Size = UDim2.new(1, -GP_SCROLLBAR, 0, GP_COLHEAD_H)
	header.Parent = parent

	local function caption(text: string, x: UDim2, width: number, align: Enum.TextXAlignment)
		local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Head")
		label.Text = text
		label.TextXAlignment = align
		label.Position = x
		label.Size = UDim2.fromOffset(width, GP_COLHEAD_H)
		label.Parent = header
	end
	-- Each caption sits on EXACTLY the column its rows use, alignment included:
	-- the glaze chip centres its word, the state word stops short of its dot.
	caption("Piece", UDim2.fromOffset(GP_ROW_TEXT_X, 0), 240, Enum.TextXAlignment.Left)
	caption("Glaze", UDim2.new(1, -GP_GLAZE_X, 0, 0), GP_COL_GLAZE_W, Enum.TextXAlignment.Center)
	caption("On hand", UDim2.new(1, -GP_COUNT_X, 0, 0), GP_COL_COUNT_W, Enum.TextXAlignment.Right)
	caption("State", UDim2.new(1, -GP_STATE_X, 0, 0), GP_COL_STATE_W - 24, Enum.TextXAlignment.Right)

	-- Sage hairline under the captions (studio dialect rule colour).
	local rule = gpFrame("HeadRule", theme.Studio.Tan, 0)
	rule.AnchorPoint = Vector2.new(0, 1)
	rule.Position = UDim2.fromScale(0, 1)
	rule.Size = UDim2.new(1, 0, 0, 1)
	rule.Parent = header

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Slots"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	-- Rows are petal plates with strokes; an unclipped viewport would let them
	-- ride over the column captions on the way past.
	scroll.ClipsDescendants = true
	scroll.Position = UDim2.fromOffset(0, top + GP_COLHEAD_H + 6)
	scroll.Size = UDim2.new(1, 0, 1, -(top + GP_COLHEAD_H + 6))
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = theme.Colors.Primary
	scroll.Parent = parent
	UIStyler.ListLayout({
		Padding = UDim.new(0, GP_ROW_GAP),
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	}).Parent = scroll
	self._scroll = scroll

	local empty = GPLayoutKit.BodyText(theme, theme.TextSizes.Subtitle, theme.Colors.TextSecondary, "EmptyHint")
	empty.Text = "Nothing on the shelf matches that."
	empty.TextXAlignment = Enum.TextXAlignment.Left
	empty.Position = UDim2.fromOffset(GP_ROW_TEXT_X, top + GP_COLHEAD_H + 28)
	empty.Size = UDim2.new(1, -GP_ROW_TEXT_X, 0, 28)
	empty.Visible = false
	empty.Parent = parent
	self._gridEmpty = empty
end

-- ---- the piece row (POOLED) ----------------------------------------------
--
-- Rows are built ONCE and rebound, never destroyed and rebuilt: the search box
-- re-renders the list on every keystroke, so churning instances here would
-- churn instances at typing speed. Rows are deliberately SHADOW-FREE for the
-- same reason GPLayoutKit.StatRow is — thirty-four of them would eat half the
-- 80-shadow budget and turn a data table into a sticker sheet. Depth comes from
-- the petal silhouette, the soft stroke and the plate riding lighter than the
-- cream paper; SELECTION is a ring (doc §4.3), not a fill change.
function InventoryScreen:_BuildGPRow(theme: Types.UITheme, index: number): any
	local root = Instance.new("TextButton")
	root.Name = "SlotIdle"
	root.BackgroundTransparency = 1 -- see the enforcer note on gpButton
	root.Text = ""
	root.AutoButtonColor = false
	root.Size = UDim2.new(1, -GP_SCROLLBAR, 0, GP_ROW_H)
	root.Parent = self._scroll

	local shapeFill = theme.Colors.SurfaceRaised
	local shape = gpFrame("Shape", shapeFill, 0)
	shape.Size = UDim2.fromScale(1, 1)
	shape.Parent = root
	-- ALTERNATING petal/mirror down the list, so the shelf reads hand-arranged
	-- rather than stamped.
	GPLayoutKit.Petal(theme, shape, index)
	local stroke = GPLayoutKit.SoftStroke(theme, shape)

	-- Selection ring: a separate OUTSET frame that switches Visible, matching
	-- the classic slot contract _Select drives by name.
	local ring = gpFrame("SelRing", shapeFill, 1)
	ring.Position = UDim2.fromOffset(-4, -4)
	ring.Size = UDim2.new(1, 8, 1, 8)
	ring.Visible = false
	ring.ZIndex = 3
	ring.Parent = root
	GPLayoutKit.Petal(theme, ring, index)
	local ringStroke = UIStyler.Stroke(theme.Semantic.Selection, 3, 0)
	ringStroke.LineJoinMode = Enum.LineJoinMode.Round
	ringStroke.Parent = ring

	local icon = Instance.new("ImageLabel")
	icon.Name = "Art"
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 12, 0.5, 0)
	icon.Size = UDim2.fromOffset(GP_ROW_ICON, GP_ROW_ICON)
	icon.ZIndex = 4
	icon.Parent = shape
	IconVisibility.Register(icon)

	-- The archive's own fallback when a role has no uploaded art: same slot,
	-- same size, so the row never changes shape. Registered too, because the
	-- archive treats a glyph fallback as iconography and the global toggle must
	-- take both or the list half-empties.
	local glyph = GPLayoutKit.Text(theme, 22, theme.Colors.TextSecondary, "Glyph")
	glyph.AnchorPoint = Vector2.new(0, 0.5)
	glyph.Position = UDim2.new(0, 12, 0.5, 0)
	glyph.Size = UDim2.fromOffset(GP_ROW_ICON, GP_ROW_ICON)
	glyph.Visible = false
	glyph.ZIndex = 4
	glyph.Parent = shape
	IconVisibility.Register(glyph)

	local name = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "Name")
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(GP_ROW_TEXT_X, 8)
	name.Size = UDim2.new(1, -(GP_ROW_TEXT_X + GP_GLAZE_X + 12), 0, 24)
	name.ZIndex = 4
	name.Parent = shape

	-- The second line is the AC part row's two-key-stat readout in this pack's
	-- vocabulary: a piece is never listed as a bare name.
	local spec = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Spec")
	spec.TextXAlignment = Enum.TextXAlignment.Left
	spec.TextTruncate = Enum.TextTruncate.AtEnd
	spec.Position = UDim2.fromOffset(GP_ROW_TEXT_X, 34)
	spec.Size = UDim2.new(1, -(GP_ROW_TEXT_X + GP_GLAZE_X + 12), 0, 18)
	spec.ZIndex = 4
	spec.Parent = shape

	local glazeChip = gpFrame("GlazeChip", theme.Colors.Surface, 0)
	glazeChip.AnchorPoint = Vector2.new(0, 0.5)
	glazeChip.Position = UDim2.new(1, -GP_GLAZE_X, 0.5, 0)
	glazeChip.Size = UDim2.fromOffset(GP_COL_GLAZE_W, 24)
	glazeChip.ZIndex = 4
	glazeChip.Parent = shape
	GPLayoutKit.Petal(theme, glazeChip, index + 1)
	local glazeStroke = GPLayoutKit.SoftStroke(theme, glazeChip)
	local glazeLabel = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "Glaze")
	glazeLabel.Size = UDim2.fromScale(1, 1)
	glazeLabel.ZIndex = 5
	glazeLabel.Parent = glazeChip

	local count = GPLayoutKit.NumberText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "Count")
	count.AnchorPoint = Vector2.new(0, 0.5)
	count.Position = UDim2.new(1, -GP_COUNT_X, 0.5, 0)
	count.Size = UDim2.fromOffset(GP_COL_COUNT_W, 20)
	count.ZIndex = 4
	count.Parent = shape

	local state = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "State")
	state.TextXAlignment = Enum.TextXAlignment.Right
	state.AnchorPoint = Vector2.new(0, 0.5)
	state.Position = UDim2.new(1, -GP_STATE_X, 0.5, 0)
	state.Size = UDim2.new(0, GP_COL_STATE_W - 24, 0, 20)
	state.ZIndex = 4
	state.Parent = shape

	-- The state DOT carries the tone the state word cannot: Success/Selection on
	-- pastel ink measures under 2:1 at 13px, so the word stays in TextPrimary and
	-- the colour rides a 8px mark beside it, where contrast is not a legibility
	-- question.
	local dot = gpFrame("StateDot", theme.Colors.Success, 0)
	dot.AnchorPoint = Vector2.new(1, 0.5)
	dot.Position = UDim2.new(1, -8, 0.5, 0)
	dot.Size = UDim2.fromOffset(8, 8)
	dot.Visible = false
	dot.ZIndex = 4
	dot.Parent = shape
	UIStyler.Corner(theme.Radii.Pill).Parent = dot

	local entry: any = {
		root = root,
		shape = shape,
		stroke = stroke,
		ring = ring,
		ringStroke = ringStroke,
		icon = icon,
		glyph = glyph,
		name = name,
		spec = spec,
		glazeChip = glazeChip,
		glazeStroke = glazeStroke,
		glazeLabel = glazeLabel,
		count = count,
		state = state,
		dot = dot,
		item = nil :: Item?,
	}

	-- Bound ONCE against the pooled entry, so a rebind never re-connects.
	root.Activated:Connect(function()
		local item = entry.item
		if item then
			self:_Select(item.id)
			UIChrome.Pulse(theme, shape)
		end
	end)
	root.MouseEnter:Connect(function()
		local item = entry.item
		if item then
			self:_HoverGPRow(item)
		end
	end)
	root.MouseLeave:Connect(function()
		self:_ClearGPPreview()
	end)
	UIChrome.Animate(theme, root, shape)
	return entry
end

function InventoryScreen:_BindGPRow(theme: Types.UITheme, row: any, entry: Item, order: number)
	local locked = entry.locked == true
	local rank = RARITY_RANK[entry.rarity] or 1
	local glaze = gpGlazeColor(theme, rank)
	local profile = gpProfile(entry)

	row.item = entry
	row.root.Name = "Slot_" .. entry.id
	row.root.LayoutOrder = order
	row.root.Visible = true

	row.name.Text = softCase(entry.name)
	row.name.TextTransparency = if locked then 0.35 else 0
	row.spec.Text = string.format(
		"Form %.1f   ·   Glaze %.1f   ·   Firing %d C",
		profile.FORM,
		profile.GLAZE,
		math.round(profile.FIRING)
	)
	row.glazeChip.BackgroundColor3 = glaze
	row.glazeStroke.Color = GPLayoutKit.Deepen(theme, glaze, 1)
	row.glazeLabel.Text = GP_GLAZE_NAME[rank] or GP_GLAZE_NAME[1]
	row.count.Text = "x" .. tostring(entry.count or 1)

	local stateText: string
	local stateTone: Color3? = nil
	if self._equippedId == entry.id then
		stateText, stateTone = "On the wheel", theme.Colors.Success
	elseif locked then
		stateText, stateTone = "Locked", theme.Colors.Disabled
	elseif entry.favorite then
		stateText, stateTone = "Loved", theme.Semantic.Selection
	else
		stateText, stateTone = "", nil
	end
	row.state.Text = stateText
	row.state.TextColor3 = if stateTone then theme.Colors.TextPrimary else theme.Colors.TextSecondary
	row.dot.Visible = stateTone ~= nil
	if stateTone then
		row.dot.BackgroundColor3 = stateTone
	end

	local assetId = IconArchive.Id(entry.icon)
	if assetId and assetId ~= "" then
		row.icon.Image = assetId
		row.icon.Visible = true
		-- A LOCKED piece dims its art, but a pooled row is rebound constantly and
		-- a bare ImageTransparency write would resurrect an icon the global
		-- toggle had switched off. The dim is published as the icon's REST
		-- transparency (the attribute IconVisibility restores from) and only
		-- applied live while icons are on.
		local rest = if locked then 0.45 else 0
		row.icon:SetAttribute("IconRestTransparency", rest)
		row.icon.ImageTransparency = if IconVisibility.IsEnabled() then rest else 1
		row.glyph.Visible = false
	else
		row.icon.Visible = false
		row.glyph.Text = IconArchive.Glyph(entry.icon)
		row.glyph.Visible = true
	end

	row.ring.Visible = self._selectedId == entry.id
end

function InventoryScreen:_RenderGPList()
	if not self._scroll then
		return
	end
	local theme = self:GetTheme()
	local visible = self:_VisibleItems()
	for order, entry in visible do
		local row = self._gpRows[order]
		if not row then
			row = self:_BuildGPRow(theme, order)
			self._gpRows[order] = row
		end
		self:_BindGPRow(theme, row, entry, order)
	end
	-- Surplus rows are HIDDEN and unbound, never destroyed (the pooling law).
	-- The name is cleared too, so _Select's name walk cannot light the ring on
	-- a parked row.
	for order = #visible + 1, #self._gpRows do
		local row = self._gpRows[order]
		row.item = nil
		row.root.Visible = false
		row.root.Name = "SlotIdle"
		row.ring.Visible = false
	end
	if self._gridEmpty then
		self._gridEmpty.Visible = #visible == 0
	end
end

-- ---- the stat column -----------------------------------------------------

function InventoryScreen:_BuildGPStatColumn(theme: Types.UITheme, parent: Frame)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "StatScroll"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ClipsDescendants = true
	scroll.Size = UDim2.new(1, 0, 1, -(GP_ACTIONS_H + 10))
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = theme.Colors.Primary
	scroll.Parent = parent
	UIStyler.ListLayout({
		Padding = UDim.new(0, 10),
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	}).Parent = scroll
	-- Every child is authored (1, -GP_SCROLLBAR) wide rather than padded, so the
	-- ladder's right-anchored numerals clear the scrollbar gutter exactly.

	local hint = GPLayoutKit.BodyText(theme, theme.TextSizes.Subtitle, theme.Colors.TextSecondary, "Hint")
	hint.Text = "Pick a piece from the shelf to see how it judged."
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextWrapped = true
	hint.Size = UDim2.new(1, -GP_SCROLLBAR, 0, 56)
	hint.LayoutOrder = 1
	hint.Parent = scroll
	self._detailHint = hint

	-- ---- the selected piece --------------------------------------------
	local piece = gpStack("Piece", theme.Colors.Background, 10, 2, scroll)
	piece.Visible = false
	self._detailBody = piece

	local plateFill = theme.Colors.Surface
	local plate = gpFrame("Plate", plateFill, 0)
	plate.Size = UDim2.new(1, -GP_SCROLLBAR, 0, GP_PLATE_H)
	plate.LayoutOrder = 1
	plate.Parent = piece
	GPLayoutKit.Petal(theme, plate, 0)
	GPLayoutKit.SoftStroke(theme, plate)
	GPLayoutKit.Shadow(theme, plate, "md", self._gpShadows, plateFill)

	local wellFill = theme.Colors.SurfaceRaised
	local well = gpFrame("ArtWell", wellFill, 0)
	well.Position = UDim2.fromOffset(14, 16)
	well.Size = UDim2.fromOffset(64, 64)
	well.ZIndex = 2
	well.Parent = plate
	GPLayoutKit.Petal(theme, well, 1)
	GPLayoutKit.SoftStroke(theme, well)
	-- The pack's zero-offset ROSE aura, one handle for the whole page: the piece
	-- under the reader's eye BLOOMS rather than falling into shade. It rides the
	-- art well and not the plate, because the plate already carries its own soft
	-- drop shadow and a second UIShadow on one host is not a contract this
	-- codebase has verified.
	GPLayoutKit.Glow(theme, well, theme.Semantic.Selection, self._gpShadows)
	self._detailWell = well

	local name = GPLayoutKit.Text(theme, 26, theme.Colors.TextPrimary, "Name")
	name.RichText = false
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(92, 12)
	name.Size = UDim2.new(1, -(92 + 150), 0, 30)
	name.ZIndex = 2
	name.Parent = plate
	self._detailName = name

	local meta = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Meta")
	meta.RichText = false
	meta.TextXAlignment = Enum.TextXAlignment.Left
	meta.TextTruncate = Enum.TextTruncate.AtEnd
	meta.Position = UDim2.fromOffset(92, 44)
	meta.Size = UDim2.new(1, -106, 0, 18)
	meta.ZIndex = 2
	meta.Parent = plate
	self._detailMeta = meta

	-- What this ONE piece contributes to the ladder below — the line that makes
	-- the hover ghost on "Shelf weight" legible instead of magic.
	local cost = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Cost")
	cost.TextXAlignment = Enum.TextXAlignment.Left
	cost.Position = UDim2.fromOffset(92, 66)
	cost.Size = UDim2.new(1, -106, 0, 18)
	cost.ZIndex = 2
	cost.Parent = plate
	self._gpCostLine = cost

	local badge, badgeLabel, badgeStroke = gpPill(theme, plate, 138, "Verdict")
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.Position = UDim2.new(1, -14, 0, 14)
	badge.ZIndex = 2
	self._gpVerdict = { pill = badge, label = badgeLabel, stroke = badgeStroke }

	local description = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Description")
	description.RichText = false
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.TextYAlignment = Enum.TextYAlignment.Top
	description.TextWrapped = true
	description.Size = UDim2.new(1, -GP_SCROLLBAR, 0, GP_DESC_H)
	description.LayoutOrder = 2
	description.Parent = piece
	self._detailDescription = description

	GPLayoutKit.Divider(theme, piece).LayoutOrder = 3

	self._gpKiln = gpGauge(theme, piece, "Kiln", theme.Colors.Primary, 4)
	-- Inset like every other child of this scroll: the gauge's readout is
	-- RIGHT-anchored, so a full-width root would run its numerals under the
	-- scrollbar gutter (the stat rows already take this offset explicitly).
	self._gpKiln.root.Size = UDim2.new(1, -GP_SCROLLBAR, 0, GP_GAUGE_H)

	local judgeLabel = GPLayoutKit.SectionLabel(theme, piece, "Judging")
	judgeLabel.LayoutOrder = 5
	self._detailStatsTitle = judgeLabel

	local judgeHost = gpStack("Judging", theme.Colors.Background, 4, 6, piece)
	for index, def in GP_JUDGING do
		local row = GPLayoutKit.StatRow(theme, judgeHost, {
			label = def.label,
			unit = def.unit,
			maxValue = def.max,
			value = 0,
			-- FIRING is a temperature in the high hundreds; a decimal place on a
			-- kiln reading is noise, where on a judged score it is the point.
			precision = if def.id == "FIRING" then 0 else 1,
			layoutOrder = index,
		})
		row.root.Size = UDim2.new(1, -GP_SCROLLBAR, 0, row.root.Size.Y.Offset)
		self._gpJudge[def.id] = row
	end

	local marksLabel = GPLayoutKit.SectionLabel(theme, piece, "Maker's marks")
	marksLabel.LayoutOrder = 7
	self._gpSpecLabel = marksLabel
	self._gpSpecHost = gpStack("Marks", theme.Colors.Background, 2, 8, piece)

	-- ---- the shelf (independent of the selection) -----------------------
	local shelf = gpStack("Shelf", theme.Colors.Background, 10, 3, scroll)

	GPLayoutKit.Divider(theme, shelf).LayoutOrder = 1

	local shelfLabel = GPLayoutKit.SectionLabel(theme, shelf, "Shelf and clay")
	shelfLabel.LayoutOrder = 2

	self._gpShelf = gpGauge(theme, shelf, "Shelf", theme.Colors.Secondary, 3)
	self._gpShelf.root.Size = UDim2.new(1, -GP_SCROLLBAR, 0, GP_GAUGE_H)

	self._gpLadderHost = gpStack("Ladder", theme.Colors.Background, 4, 4, shelf)
	self:_EnsureGPLadder(theme)

	-- The over-limit story SPELLED OUT, AC's banner in this pack's voice — and it
	-- rides a TINTED CAPSULE rather than red ink, for the reason the whole page
	-- keeps repeating: Colors.Error as body copy on the cream paper measures
	-- 3.18:1, under the 4.5:1 floor, so an alarm printed that way is the one line
	-- on the page you cannot read. Lightened to the same tint the over-limit
	-- capsule takes, with the warm plum-brown ink on top, it measures 7.7:1. The
	-- stroke is derived from that fill, so the plate casts its own hue like
	-- everything else here.
	local bannerFill = theme.Colors.Error:Lerp(theme.Colors.Background, 0.72)
	local banner = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "OverLimit")
	banner.Text = "Shelf over limit — the bottom pieces will not fire."
	banner.TextXAlignment = Enum.TextXAlignment.Left
	banner.TextWrapped = true
	banner.BackgroundColor3 = bannerFill
	banner.BackgroundTransparency = 0
	banner.Size = UDim2.new(1, -GP_SCROLLBAR, 0, 40)
	banner.LayoutOrder = 5
	banner.Visible = false
	banner.Parent = shelf
	GPLayoutKit.Petal(theme, banner, 1)
	GPLayoutKit.SoftStroke(theme, banner)
	UIStyler.PaddingXY(theme.Spacing.M, 0).Parent = banner
	self._gpBanner = banner

	self:_BuildGPActions(theme, parent)
end

-- The ladder's bar scales come from the bag's capacity, which a backend can
-- change under us — and GPLayoutKit.StatRow fixes maxValue at construction. So
-- the four rows are rebuilt (cheaply: they carry no shadows) whenever the
-- capacity actually moves, and left alone otherwise.
function InventoryScreen:_EnsureGPLadder(theme: Types.UITheme)
	if self._gpLadderCap == self._capacityMax or not self._gpLadderHost then
		return
	end
	self._gpLadderCap = self._capacityMax
	for _, child in self._gpLadderHost:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(self._gpLadder)
	table.clear(self._gpLadderStrokes)

	local shelfLimit = self._capacityMax * GP_KG_PER_SLOT
	local clayStock = self._capacityMax * GP_CLAY_PER_SLOT
	for index, def in GP_LADDER do
		local isClay = def.id == "CLAY" or def.id == "STOCK"
		local row = GPLayoutKit.StatRow(theme, self._gpLadderHost, {
			label = def.label,
			unit = def.unit,
			maxValue = if isClay then clayStock else shelfLimit,
			value = 0,
			invertGoodness = def.invert == true,
			layoutOrder = index,
		})
		row.root.Size = UDim2.new(1, -GP_SCROLLBAR, 0, row.root.Size.Y.Offset)
		-- The over-limit capsule outline, born invisible.
		local stroke = UIStyler.Stroke(theme.Colors.Error, 2, 1)
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		stroke.Parent = row.capsule
		self._gpLadder[def.id] = row
		self._gpLadderStrokes[def.id] = stroke
	end
end

function InventoryScreen:_BuildGPActions(theme: Types.UITheme, parent: Frame)
	local bar = gpFrame("Actions", theme.Colors.Background, 1)
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.Position = UDim2.fromScale(0, 1)
	bar.Size = UDim2.new(1, -GP_SCROLLBAR, 0, GP_ACTIONS_H)
	bar.Parent = parent

	local equip = gpButton(theme, bar, "Put it on the wheel", 0, self._gpShadows)
	equip.root.Size = UDim2.new(1, 0, 0, 44)
	equip.root.Activated:Connect(function()
		self:_Equip()
	end)
	self._gpEquip = equip
	self._equipBtn = wrapAction(equip.root)

	local drop = gpButton(theme, bar, "Return to clay", 1, self._gpShadows)
	drop.root.Position = UDim2.fromOffset(0, 52)
	drop.root.Size = UDim2.new(0.5, -6, 0, 40)
	drop.root.Activated:Connect(function()
		self:_Drop()
	end)
	self._gpDrop = drop
	self._dropBtn = wrapAction(drop.root)

	local fav = gpButton(theme, bar, "Favourite", 2, self._gpShadows)
	fav.root.AnchorPoint = Vector2.new(1, 0)
	fav.root.Position = UDim2.new(1, 0, 0, 52)
	fav.root.Size = UDim2.new(0.5, -6, 0, 40)
	fav.root.Activated:Connect(function()
		self:_ToggleFavorite()
	end)
	self._gpFav = fav
	self._favBtn = wrapAction(fav.root)
end

-- ---- totals, status, preview ---------------------------------------------

function InventoryScreen:_GPTotals(): (number, number)
	local weight, clay = 0, 0
	for _, entry in self._items do
		weight += gpPieceWeight(entry)
		clay += gpPieceClay(entry)
	end
	return weight, clay
end

-- Paint the over-limit story for whichever totals are being LOOKED AT (live, or
-- the hover preview) — the AC _SetOverDisplay contract.
function InventoryScreen:_SetGPOverDisplay(weight: number, clay: number)
	local theme = self:GetTheme()
	local shelfLimit = self._capacityMax * GP_KG_PER_SLOT
	local clayStock = self._capacityMax * GP_CLAY_PER_SLOT
	local overWeight = weight > shelfLimit
	local overClay = clay > clayStock
	if self._gpLadder.WEIGHT then
		gpSetOverLimit(theme, self._gpLadder.WEIGHT, self._gpLadderStrokes.WEIGHT, overWeight)
	end
	if self._gpLadder.CLAY then
		gpSetOverLimit(theme, self._gpLadder.CLAY, self._gpLadderStrokes.CLAY, overClay)
	end
	if self._gpBanner then
		self._gpBanner.Visible = overWeight or overClay
		self._gpBanner.Text = if overClay and not overWeight
			then "Clay bin is empty — throw fewer pieces or recycle some."
			else "Shelf over limit — the bottom pieces will not fire."
	end
end

-- The shelf half of the page: gauge, ladder and over-limit, from the bag alone.
-- Reached from _Render (through the _capacity wrapper) and from every detail
-- render, so the two halves can never disagree.
function InventoryScreen:_RefreshGPShelf()
	local theme = self:GetTheme()
	self:_EnsureGPLadder(theme)
	local count = #self._items
	local capacity = math.max(self._capacityMax, 1)
	local weight, clay = self:_GPTotals()
	local shelfLimit = self._capacityMax * GP_KG_PER_SLOT
	local clayStock = self._capacityMax * GP_CLAY_PER_SLOT

	if self._gpLadder.WEIGHT then
		self._gpLadder.WEIGHT.SetValue(weight)
		self._gpLadder.LIMIT.SetValue(shelfLimit)
		self._gpLadder.CLAY.SetValue(clay)
		self._gpLadder.STOCK.SetValue(clayStock)
	end

	local ratio = count / capacity
	local status: string
	local tone: Color3
	if ratio >= 1 then
		status, tone = "Shelf full", theme.Colors.Error
	elseif ratio >= 0.85 then
		status, tone = "Nearly full", theme.Colors.Warning
	else
		status, tone = "Room to throw", theme.Colors.Success
	end
	if self._gpShelf then
		self._gpShelf.Set(ratio, string.format("%d / %d pieces", count, self._capacityMax), status, tone)
	end
	if self._gpShelfReadout then
		self._gpShelfReadout.Text = string.format("%d / %d on the shelf", count, self._capacityMax)
	end
	self:_SetGPOverDisplay(weight, clay)
end

-- Hovering a piece asks a real question — "what does the shelf look like
-- without this?" — because DROP is a live action on this page. The judging rows
-- ask the swap question instead: how this piece scores against the selected
-- one. Both are AC's part-swap ghost, with a pottery verb behind them.
function InventoryScreen:_HoverGPRow(entry: Item)
	if not self._gpLadder.WEIGHT then
		return
	end
	local weight, clay = self:_GPTotals()
	local previewWeight = weight - gpPieceWeight(entry)
	local previewClay = clay - gpPieceClay(entry)
	self._gpLadder.WEIGHT.SetPreview(previewWeight)
	self._gpLadder.CLAY.SetPreview(previewClay)
	self:_SetGPOverDisplay(previewWeight, previewClay)

	-- Only when a piece is actually selected: previewing against a zeroed block
	-- would print a full-width green ghost that means nothing.
	local selected = self:_Find(self._selectedId)
	if not selected then
		return
	end
	local profile = gpProfile(entry)
	for _, def in GP_JUDGING do
		local row = self._gpJudge[def.id]
		if row then
			row.SetPreview(profile[def.id])
		end
	end
end

function InventoryScreen:_ClearGPPreview()
	for _, def in GP_JUDGING do
		local row = self._gpJudge[def.id]
		if row then
			row.SetPreview(nil)
		end
	end
	for _, def in GP_LADDER do
		local row = self._gpLadder[def.id]
		if row then
			row.SetPreview(nil)
		end
	end
	local weight, clay = self:_GPTotals()
	self:_SetGPOverDisplay(weight, clay)
end

function InventoryScreen:_TickGP(now: number)
	local gauge = self._gpKiln
	if not gauge then
		return
	end
	if not self._gpKilnBreathe then
		gauge.chipScale.Scale = 1
		return
	end
	-- Off-screen widgets cost nothing (the shared-ticker rule).
	if not UIChrome.IsOnScreen(gauge.chip) then
		return
	end
	local seconds = math.max(self._gpBreatheSeconds or 3, 0.1)
	local wave = 0.5 + 0.5 * math.sin(now * (2 * math.pi) / seconds)
	gauge.chipScale.Scale = 1 + (self._gpBreatheScale or 0.02) * wave
end

-- ---- detail render -------------------------------------------------------

function InventoryScreen:_RenderGPDetail()
	local theme = self:GetTheme()
	local entry = self:_Find(self._selectedId)
	if not self._detailBody then
		return
	end
	-- Previews are cleared FIRST: a stale preview would be re-evaluated against
	-- the incoming values and paint a ghost for a comparison nobody asked for.
	self:_ClearGPPreview()
	self:_RefreshGPShelf()

	self._detailBody.Visible = entry ~= nil
	self._detailHint.Visible = entry == nil
	if not entry then
		self._gpKilnBreathe = false
		-- The action bar lives OUTSIDE the piece block (it is pinned to the
		-- column, not scrolled with it), so with nothing selected it would sit
		-- there reading as live while _Equip/_Drop/_ToggleFavorite all return on
		-- the first line. Doc §11.1/§11.2: blocked controls dim IN PLACE and
		-- still answer on tap — the same treatment a locked piece gets.
		gpPaintButton(theme, self._gpEquip, "Put it on the wheel", theme.Colors.Surface, true)
		gpPaintButton(theme, self._gpDrop, "Return to clay", theme.Colors.Surface, true)
		gpPaintButton(theme, self._gpFav, "Favourite", theme.Colors.Surface, true)
		return
	end

	local rank = RARITY_RANK[entry.rarity] or 1
	local profile = gpProfile(entry)

	self._detailName.Text = softCase(entry.name)
	self._detailMeta.Text = string.format(
		"%s glaze   ·   %s   ·   x%d",
		GP_GLAZE_NAME[rank] or GP_GLAZE_NAME[1],
		GP_CATEGORY_LABEL[entry.category] or softCase(entry.category or ""),
		entry.count or 1
	)
	self._gpCostLine.Text = string.format(
		"Weight %.1f kg   ·   Clay %.1f kg",
		gpPieceWeight(entry),
		gpPieceClay(entry)
	)
	self._detailDescription.Text = entry.description or "No notes in the studio book for this one."

	-- The verdict badge: the judged average, said in words.
	local average = gpJudgedAverage(profile)
	local verdict: string
	local verdictTone: Color3
	if average >= 82 then
		verdict, verdictTone = "Gallery worthy", theme.Colors.Accent
	elseif average >= 62 then
		verdict, verdictTone = "Shelf ready", theme.Colors.Secondary
	else
		verdict, verdictTone = "Studio seconds", theme.Colors.Warning
	end
	self._gpVerdict.label.Text = string.format("%s  %.1f", verdict, average)
	gpPaintPill(theme, self._gpVerdict.pill, self._gpVerdict.stroke, verdictTone)

	if self._detailArt then
		self._detailArt:Destroy()
	end
	local art = IconArchive.Image(self._detailWell, entry.icon, 44)
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.5)
	art.ZIndex = 3
	self._detailArt = art

	for _, def in GP_JUDGING do
		local row = self._gpJudge[def.id]
		if row then
			row.SetValue(profile[def.id] or 0)
		end
	end

	-- The kiln: the selected piece's peak firing against its cone. The bands are
	-- the real ceramic ones — under ~805 C the ware never vitrified (a misfire),
	-- bisque runs to ~1015, and glaze maturity sits at the top of the range.
	local firing = profile.FIRING or 0
	local ratio = firing / 1300
	local kilnStatus: string
	local kilnTone: Color3
	if ratio < 0.62 then
		kilnStatus, kilnTone = "Misfire risk", theme.Colors.Error
	elseif ratio < 0.78 then
		kilnStatus, kilnTone = "Bisque", theme.Colors.Disabled
	elseif ratio < 0.88 then
		kilnStatus, kilnTone = "Firing", theme.Colors.Warning
	elseif ratio < 0.95 then
		kilnStatus, kilnTone = "Cooling", theme.Colors.Secondary
	else
		kilnStatus, kilnTone = "Kiln ready", theme.Colors.Success
	end
	self._gpKilnBreathe = kilnStatus == "Firing"
	self._gpKiln.Set(ratio, string.format("%d / 1300 C", math.round(firing)), kilnStatus, kilnTone)

	-- Maker's marks: the piece's OWN stat table, verbatim from the shared
	-- statLines reader. Nothing the classic or AC detail pane shows is lost
	-- because this page has its own judging block.
	for _, row in self._gpSpecRows do
		row:Destroy()
	end
	table.clear(self._gpSpecRows)
	local lines = statLines(entry.stats)
	self._gpSpecLabel.Visible = #lines > 0
	for order, line in lines do
		local row = gpFrame("Mark" .. order, theme.Colors.Background, 1)
		row.Size = UDim2.new(1, -GP_SCROLLBAR, 0, GP_SPEC_ROW_H)
		row.LayoutOrder = order
		row.Parent = self._gpSpecHost

		local key = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Key")
		key.Text = softCase(line.label)
		key.TextXAlignment = Enum.TextXAlignment.Left
		key.Size = UDim2.new(1, -140, 1, 0)
		key.Parent = row

		local value = GPLayoutKit.NumberText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "Value")
		value.Text = line.value
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.fromScale(1, 0)
		value.Size = UDim2.fromOffset(140, GP_SPEC_ROW_H)
		value.Parent = row

		table.insert(self._gpSpecRows, row)
	end

	local locked = entry.locked == true
	local equipped = self._equippedId == entry.id
	gpPaintButton(
		theme,
		self._gpEquip,
		if equipped then "On the wheel" else "Put it on the wheel",
		if equipped then theme.Colors.Secondary else theme.Colors.Primary,
		locked
	)
	gpPaintButton(theme, self._gpDrop, "Return to clay", theme.Colors.Surface, locked)
	gpPaintButton(
		theme,
		self._gpFav,
		if entry.favorite then "Favourited" else "Favourite",
		if entry.favorite then theme.Colors.Accent else theme.Colors.Surface,
		false
	)
end

-- ========================================================================
-- Lifecycle
-- ========================================================================

function InventoryScreen:_Render()
	self:_SyncTabs()
	self:_RenderGrid()
	self:_RenderDetail()
	if self._capacity then
		self._capacity:Set(#self._items, self._capacityMax)
	end
end

function InventoryScreen:_BuildContent()
	-- GP layout language: the matte STUDIO page — cream paper, petal piece rows
	-- and the nine-row judging/shelf stat block (see _BuildGPLayout below). It
	-- records its own _builtLayout, so the shared render dispatchers route to it.
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
		return
	end
	-- Record which layout THIS build used: the render methods dispatch on it,
	-- so a style swap while hidden can't route classic content into AC paths
	-- (the stale build rebuilds on its next Show anyway).
	self._builtLayout = self:LayoutKit()
	if self._builtLayout == "AC" then
		self:_BuildACLayout()
		return
	end

	local theme = self:GetTheme()

	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = "INVENTORY",
		sizePx = CARD,
		onClose = function()
			self.ScreenController:HideScreen("inventory")
		end,
	})
	self._modal = modal

	self:_BuildHeader(theme, modal.content)
	self:_BuildTabs(theme, modal.content)
	self:_BuildGrid(theme, modal.content)
	self:_BuildDetail(theme, modal.content)
	self:_Render()
end

function InventoryScreen:_OnShow(data: any?)
	self:_Ingest(data)
	self:_Render()
	if self._modal then
		UIChrome.PopIn(self:GetTheme(), self._modal.content)
	end
end

function InventoryScreen:Update(data: any)
	self:_Ingest(data)
	if self._built then
		self:_Render()
	end
end

-- A style rebuild destroys the Gui, but UIShadow BUDGET counts live in
-- StyleKit.Capabilities and only fall when a handle is RELEASED, and the shared
-- ticker keeps running until its handler unregisters. The studio page hands
-- both back here. Idempotent, and a no-op under every other layout.
function InventoryScreen:_OnTeardown()
	if self._gpTickerStop then
		self._gpTickerStop()
		self._gpTickerStop = nil
	end
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	self._gpShadows = nil
	-- The LOOKUP tables are emptied rather than nil'd: they are walked by the
	-- render and preview paths, and an empty table degrades to "nothing to
	-- paint" where a nil would throw. Instance refs ARE nil'd, because the
	-- guards those paths open with (`if not self._detailBody`, `if not
	-- self._scroll`) are what makes a post-teardown render a no-op.
	self._gpRows = {}
	self._gpSpecRows = {}
	self._gpTabCounts = {}
	self._gpSortChips = {}
	self._gpJudge = {}
	self._gpLadder = {}
	self._gpLadderStrokes = {}
	self._gpLadderCap = nil
	self._gpTabs = nil
	self._gpLadderHost = nil
	self._gpKiln = nil
	self._gpShelf = nil
	self._gpShelfReadout = nil
	self._gpBanner = nil
	self._gpVerdict = nil
	self._gpKilnBreathe = false
	self._gpEquip, self._gpDrop, self._gpFav = nil, nil, nil
	self._detailBody = nil
	self._detailHint = nil
	self._gridEmpty = nil
	self._scroll = nil
end

function InventoryScreen:Destroy()
	-- Screen destruction never routes through _ResetShell, so the teardown that
	-- returns the shadow budget has to be invoked here too.
	self:_OnTeardown()
	for _, component in { self._sort, self._capacity, self._equipBtn, self._dropBtn, self._favBtn } do
		if component then
			component:Destroy()
		end
	end
	self._sort, self._capacity = nil, nil
	self._equipBtn, self._dropBtn, self._favBtn = nil, nil, nil
	UIScreenBase.Destroy(self)
end

return InventoryScreen
