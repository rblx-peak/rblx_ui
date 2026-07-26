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

function InventoryScreen:Destroy()
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
