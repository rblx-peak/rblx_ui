--!strict
-- Codex / bestiary — Pottery Clash arcade family (doc §7.4).
-- One modal card, two panes. Left: category tabs (Blue active / Ghost rest,
-- the shop category-bar grammar) over a scrolling entry list. Right: a detail
-- pane whose big icon sits over a spinning white sunburst (doc §10).
--
-- Discovery states follow the doc's language: an UNDISCOVERED entry is a
-- near-black silhouette row ("???" + lock) and its detail icon renders as a
-- near-black silhouette over the sunburst — the §9 mystery-item grammar
-- brought on-screen. A discovered entry wears a NEW badge until it is opened;
-- opening it marks it read in place. Selection is stroke-only gold (§4.3).
--
-- The lore body rides UIChrome.BodyText (GothamMedium under Classic): quiet
-- body copy is exactly what the body font is for (doc §2).

local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIAssets = require(script.Parent.Parent.Config.UIAssets)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local GPControlKit = require(script.Parent.Parent.Framework.GPControlKit)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UIBadgeComponent = require(script.Parent.Parent.Components.UIBadgeComponent)
local UIProgressBarComponent = require(script.Parent.Parent.Components.UIProgressBarComponent)

type Entry = {
	id: string,
	name: string,
	icon: string?,
	category: string,
	discovered: boolean,
	read: boolean?,
	body: string?,
	foundDate: string?,
}
type CodexData = { entries: { Entry } }

local CARD_W, CARD_H = 1280, 700
local CONTENT_W = CARD_W - 28
local CONTENT_H = CARD_H - 88
local TAB_W, TAB_H = 131, 40
local LEFT_W = TAB_W * 4 + 8 * 3 -- the tab row defines the left pane's width
local BODY_Y = 52
local BODY_H = CONTENT_H - BODY_Y
local ROW_H = 64
local ROW_GAP = 8
local DETAIL_X = LEFT_W + 16
local DETAIL_W = CONTENT_W - DETAIL_X
local SCROLLBAR = 8

local TABS = {
	{ id = "creatures", label = "CREATURES" },
	{ id = "places", label = "PLACES" },
	{ id = "lore", label = "LORE" },
	{ id = "audio", label = "AUDIO LOGS" },
}

local function demoEntries(): { Entry }
	return {
		-- creatures
		{ id = "kilnImp", name = "KILN IMP", icon = "fire", category = "creatures", discovered = true, read = true, foundDate = "3 MAY",
			body = "A fist-sized spark spirit that nests in cooling kilns. Harmless unless your glaze is still wet — then it is a menace with opinions. Feeding it charcoal earns a brief, blazing loyalty." },
		{ id = "slipWisp", name = "SLIP WISP", icon = "water", category = "creatures", discovered = true, read = false, foundDate = "12 JUL",
			body = "A drifting bead of living slip. It follows potters home and thins itself into bowls left overnight. Old hands leave a saucer of water out so it thins that instead." },
		{ id = "glazeGolem", name = "GLAZE GOLEM", icon = "crystal", category = "creatures", discovered = true, read = true, foundDate = "9 JUN",
			body = "Built from a thousand dropped pots, glued by honey-gold glaze. It guards the deep shard piles and repairs anything you break near it — slowly, judgmentally." },
		{ id = "shardHound", name = "SHARD HOUND", icon = "skull", category = "creatures", discovered = false },
		{ id = "emberMoth", name = "EMBER MOTH", icon = "sparkle", category = "creatures", discovered = true, read = false, foundDate = "20 JUL",
			body = "Drawn to kiln light from miles away. Its wing dust is the secret behind every iridescent glaze in the bayside stalls, which the moths consider theft." },
		{ id = "mudLurker", name = "MUD LURKER", icon = "heart", category = "creatures", discovered = false },

		-- places
		{ id = "crackedKiln", name = "THE CRACKED KILN", icon = "house", category = "places", discovered = true, read = true, foundDate = "1 MAY",
			body = "The first kiln ever raised on the flats, split down its spine in the Clay Wars. It still fires true — locals say the crack lets the heat breathe." },
		{ id = "baysideMarket", name = "BAYSIDE MARKET", icon = "cart", category = "places", discovered = true, read = true, foundDate = "2 MAY",
			body = "Forty stalls, one rule: no two vendors may sell the same glaze. The rule has caused eleven feuds, two marriages and one extremely good teapot." },
		{ id = "slipMine", name = "DEEP SLIP MINE", icon = "pickaxe", category = "places", discovered = true, read = false, foundDate = "18 JUL",
			body = "The only source of black slip on the coast. Miners work in pairs: one digs, one listens. Nobody writes down what they are listening for." },
		{ id = "ridgeWaystone", name = "RIDGE WAYSTONE", icon = "teleport", category = "places", discovered = false },
		{ id = "galleryMasters", name = "GALLERY OF MASTERS", icon = "trophy", category = "places", discovered = false },

		-- lore
		{ id = "firstFiring", name = "THE FIRST FIRING", icon = "book", category = "lore", discovered = true, read = true, foundDate = "5 MAY",
			body = "Before the first firing there was only wet clay and argument. The story goes that the sun itself was borrowed for a night, and returned slightly used." },
		{ id = "clayWars", name = "THE CLAY WARS", icon = "swords", category = "lore", discovered = true, read = false, foundDate = "14 JUL",
			body = "Three seasons of catapulted greenware between the ridge and the bay. Ended not by treaty but by a shared kiln failure nobody could afford twice." },
		{ id = "glazeAccord", name = "THE GLAZE ACCORD", icon = "quest", category = "lore", discovered = true, read = true, foundDate = "30 MAY",
			body = "The document that ended the Clay Wars: every studio fires its neighbour's finest piece once a year. Trust, enforced by kiln." },
		{ id = "wheelSong", name = "SONG OF THE WHEEL", icon = "wheel", category = "lore", discovered = false },
		{ id = "missingMaster", name = "THE MISSING MASTER", icon = "search", category = "lore", discovered = false },

		-- audio logs
		{ id = "foremanLog1", name = "FOREMAN'S LOG 01", icon = "soundOn", category = "audio", discovered = true, read = true, foundDate = "7 MAY",
			body = "\"Day one at the new pit. Slip's black as a closed kiln and twice as warm. Marking the good vein with red cord. Do not move the red cord.\"" },
		{ id = "foremanLog2", name = "FOREMAN'S LOG 02", icon = "soundOn", category = "audio", discovered = true, read = false, foundDate = "21 JUL",
			body = "\"Somebody moved the red cord. The vein still sings if you tap it, but it sings back a beat late now. Requesting a listener from the bay.\"" },
		{ id = "dockTalk", name = "OVERHEARD AT THE DOCK", icon = "bell", category = "audio", discovered = false },
		{ id = "kilnEcho", name = "KILN ROOM ECHO", icon = "musicOn", category = "audio", discovered = false },
		{ id = "lastBroadcast", name = "THE LAST BROADCAST", icon = "soundOff", category = "audio", discovered = false },
	}
end

-- GP (Girly Pop) geometry: GPLayoutKit.Page spends 48px more vertical chrome
-- than the §7.4 card, so the GP card is authored 48px taller and its content
-- rect comes out pixel-identical — every constant above is reused verbatim and
-- the two-pane split keeps its exact proportions.
local GP_CARD_GROW = 48
local GP_SCROLL_PAD = 8

-- The codex is authored in arcade caps ("KILN IMP", "AUDIO LOGS"). Pack law 5
-- forbids all-caps copy, so the GP build title-cases on the way to the screen;
-- the data is untouched.
local function gpTitle(text: string): string
	return (string.gsub(string.lower(text), "(%a[%w']*)", function(word: string)
		return string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2)
	end))
end

local function tintIcon(icon: GuiObject, color: Color3)
	if icon:IsA("ImageLabel") then
		icon.ImageColor3 = color
	elseif icon:IsA("TextLabel") then
		icon.TextColor3 = color
	end
end

local function dimIcon(icon: GuiObject, transparency: number)
	if icon:IsA("ImageLabel") then
		icon.ImageTransparency = transparency
	elseif icon:IsA("TextLabel") then
		icon.TextTransparency = transparency
	end
end

local CodexScreen = setmetatable({}, { __index = UIScreenBase })
CodexScreen.__index = CodexScreen

function CodexScreen.new()
	local self = UIScreenBase.new("CodexScreen", 6)
	self._data = { entries = demoEntries() } :: CodexData
	self._tab = "creatures"
	self._selectedId = nil :: string?
	self._tabButtons = {} :: { [string]: any }
	self._rows = {} :: { { entry: Entry, surface: Frame, stroke: UIStroke } }
	self._rowComponents = {} :: { any }
	self._burst = nil :: ImageLabel?
	self._spinConn = nil :: RBXScriptConnection?
	self._detailIcon = nil :: GuiObject?
	-- GP branch state: the flag the shared render methods read, plus the page
	-- and row shadow sinks the budget is released from.
	self._gp = false
	self._gpShadows = nil :: { any }?
	self._gpRowShadows = nil :: { any }?
	return setmetatable(self, CodexScreen)
end

function CodexScreen:_Counts(): (number, number)
	local discovered, total = 0, 0
	for _, entry in (self._data :: CodexData).entries do
		total += 1
		if entry.discovered then
			discovered += 1
		end
	end
	return discovered, total
end

function CodexScreen:_Filtered(): { Entry }
	local out = {}
	for _, entry in (self._data :: CodexData).entries do
		if entry.category == self._tab then
			table.insert(out, entry)
		end
	end
	return out
end

-- ========================================================================
-- GIRLY POP
-- ========================================================================
-- The same two-pane codex at the same density: four category tabs, the
-- completion ruler, every entry in the scrolling list with its NEW badge and
-- its discovery state, and the full detail pane (icon over a spinning glaze
-- burst, title, category, scrolling lore body, found-date line).
--
-- Undiscovered entries become SOFT OUTLINES rather than black silhouettes with
-- padlocks. Nothing is hidden that the arcade build showed — the row still says
-- it is undiscovered, the detail pane still says so, and the counts still count
-- it. It just reads as a shelf waiting to be filled instead of a locked door.
--
-- Controls come from GPControlKit because UIChrome.Stroke resolves to BLACK
-- under this pack's Chrome policy and UIStyleEnforcer backstops solid buttons
-- with a black rim; both break pack law 1.

function CodexScreen:_BuildGPLayout()
	local theme = self:GetTheme()

	local page = GPLayoutKit.Page(theme, self.Root, {
		titleText = "Codex",
		subtitleText = "Everything the studio has written down.",
		sizePx = Vector2.new(CARD_W, CARD_H + GP_CARD_GROW),
		onClose = function()
			self.ScreenController:HideScreen("codex")
		end,
	})
	self._modal = page
	self._gpShadows = page.shadows
	self._gpRowShadows = {}
	local content = page.content

	-- Category tabs, verbatim copy in Title Case. GPLayoutKit.Tabs owns the
	-- selected read (rose fill, butter underline, retinted shadow); the
	-- adapters below give _RenderTabs the SetContent contract it already calls.
	local bar = GPLayoutKit.Tabs(theme, content, {
		widthPx = TAB_W,
		tabHeightPx = TAB_H,
		heightPx = TAB_H,
	}, self._gpShadows)
	bar.frame.Size = UDim2.fromOffset(LEFT_W, TAB_H)
	for _, tab in TABS do
		local id = tab.id
		bar.Add(gpTitle(tab.label), id, function()
			self:_SelectTab(id)
		end)
		self._tabButtons[id] = {
			-- _RenderTabs paints every tab and marks exactly one "Blue"; that
			-- one call is what drives the kit's own Select.
			SetContent = function(_self: any, props: { [string]: any })
				if props.variant == "Blue" then
					bar.Select(id)
				end
			end,
			Destroy = function(_self: any) end,
		}
	end
	bar.Select(self._tab)

	-- The completion ruler, with the fraction PRINTED next to the bar.
	self._completionBar = GPControlKit.Meter(theme, content, {
		label = "Discovered",
		value = 0,
		maxValue = 1,
		size = UDim2.fromOffset(360, 42),
		position = UDim2.new(1, -360, 0, 4),
	})

	local list = Instance.new("ScrollingFrame")
	list.Name = "EntryList"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(0, BODY_Y)
	list.Size = UDim2.fromOffset(LEFT_W, BODY_H)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = SCROLLBAR
	list.ScrollBarImageColor3 = GPLayoutKit.Deepen(theme, theme.Colors.Primary, 1)
	-- Scrolled rows must never spill onto the paper (a known past bug here).
	list.ClipsDescendants = true
	list.Parent = content
	UIStyler.Padding(GP_SCROLL_PAD).Parent = list
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, ROW_GAP),
	}).Parent = list
	self._list = list

	local detail = GPControlKit.Well(theme, content, {
		fill = theme.Colors.SurfaceRaised,
		index = 1,
		shadow = "md",
		position = UDim2.fromOffset(DETAIL_X, BODY_Y),
		size = UDim2.fromOffset(DETAIL_W, BODY_H),
		sink = self._gpShadows,
	})
	self._detail = detail

	local iconSlot = UIStyler.Frame("IconSlot")
	iconSlot.BackgroundTransparency = 1
	iconSlot.AnchorPoint = Vector2.new(0.5, 0)
	iconSlot.Position = UDim2.new(0.5, 0, 0, 20)
	iconSlot.Size = UDim2.fromOffset(190, 190)
	iconSlot.ZIndex = 3
	iconSlot.Parent = detail
	self._iconSlot = iconSlot

	-- The house sunburst, in the pack's own soft art and rose instead of white
	-- (pure white is forbidden). The spin connection keeps the classic
	-- lifecycle: dropped in _OnHide, remade on the next _OnShow.
	local burst = GPLayoutKit.Slice(theme, "sunburstSoft", theme.Colors.Primary, "Sunburst")
	burst.ImageTransparency = 0.6
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.Position = UDim2.fromScale(0.5, 0.5)
	burst.Size = UDim2.fromScale(1.5, 1.5)
	burst.ZIndex = 2
	burst.Parent = iconSlot
	self._burst = burst
	self._spinConn = UIChrome.Spin(burst, 45)

	local title = GPLayoutKit.Text(theme, 28, theme.Colors.TextPrimary, "Title")
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(24, 216)
	title.Size = UDim2.new(1, -48, 0, 34)
	title.RichText = false
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.ZIndex = 3
	title.Parent = detail
	self._titleLabel = title

	local category = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Category")
	category.TextXAlignment = Enum.TextXAlignment.Left
	category.Position = UDim2.fromOffset(24, 252)
	category.Size = UDim2.new(1, -48, 0, 22)
	category.ZIndex = 3
	category.Parent = detail
	self._categoryLabel = category

	local rule = GPLayoutKit.Divider(theme, detail)
	rule.Position = UDim2.fromOffset(24, 278)
	rule.Size = UDim2.new(1, -48, 0, rule.Size.Y.Offset)
	rule.ZIndex = 3

	-- Long lore paragraphs scroll rather than truncate.
	local bodyScroll = Instance.new("ScrollingFrame")
	bodyScroll.Name = "Body"
	bodyScroll.BackgroundTransparency = 1
	bodyScroll.BorderSizePixel = 0
	bodyScroll.Position = UDim2.fromOffset(26, 296)
	bodyScroll.Size = UDim2.new(1, -52, 0, BODY_H - 296 - 46)
	bodyScroll.CanvasSize = UDim2.new()
	bodyScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	bodyScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	bodyScroll.ScrollBarThickness = SCROLLBAR
	bodyScroll.ScrollBarImageColor3 = GPLayoutKit.Deepen(theme, theme.Colors.Primary, 1)
	bodyScroll.ClipsDescendants = true
	bodyScroll.ZIndex = 3
	bodyScroll.Parent = detail

	local body = GPLayoutKit.BodyText(theme, 17, theme.Colors.TextPrimary, "Flavour")
	body.Size = UDim2.new(1, -SCROLLBAR - 4, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.RichText = false
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.LineHeight = 1.25
	body.ZIndex = 4
	body.Parent = bodyScroll
	self._bodyLabel = body

	local found = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Found")
	found.AnchorPoint = Vector2.new(0, 1)
	found.Position = UDim2.new(0, 24, 1, -14)
	found.Size = UDim2.new(1, -48, 0, 24)
	found.TextXAlignment = Enum.TextXAlignment.Left
	found.ZIndex = 3
	found.Parent = detail
	self._foundLabel = found

	self:_RenderAll()
end

-- One GP list row. DISCOVERED rows are petal plates that cast their own hue;
-- undiscovered ones are the pack's soft outline — still labelled, still
-- selectable, still counted.
function CodexScreen:_BuildGPRow(entry: Entry, index: number)
	local theme = self:GetTheme()
	local spacing = theme.Spacing

	local root = UIStyler.Frame("Row_" .. entry.id)
	root.BackgroundTransparency = 1
	root.Size = UDim2.new(1, -(SCROLLBAR + GP_SCROLL_PAD), 0, ROW_H)
	root.LayoutOrder = index
	root.Parent = self._list

	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 1
	hit.Parent = root

	local fill = if entry.discovered then theme.Colors.SurfaceRaised else theme.Colors.Background
	local surface = UIStyler.Frame("Surface")
	surface.BackgroundColor3 = fill
	surface.BackgroundTransparency = if entry.discovered then 0 else 0.45
	surface.AnchorPoint = Vector2.new(0.5, 0.5)
	surface.Position = UDim2.fromScale(0.5, 0.5)
	surface.Size = UDim2.fromScale(1, 1)
	surface.ZIndex = 2
	surface.Parent = root
	GPLayoutKit.Petal(theme, surface, index)
	local stroke = GPLayoutKit.SoftStroke(theme, surface, fill)
	if entry.discovered then
		GPLayoutKit.Shadow(theme, surface, "sm", self._gpRowShadows, fill)
	else
		-- A slot that is not filled does not cast: the lighter rim IS the
		-- "dashed" read against its solid neighbours.
		stroke.Transparency = 0.5
	end

	if entry.discovered then
		-- Through the kit wrapper: IconArchive's GLYPH FALLBACK is born pure
		-- white with a pure black outline, which pack law 1 forbids.
		local icon = GPControlKit.Icon(theme, surface, entry.icon or "book", 40)
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, spacing.M, 0.5, 0)
		icon.ZIndex = 3

		local name = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "Name")
		name.Text = gpTitle(entry.name)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Position = UDim2.fromOffset(66, 0)
		name.Size = UDim2.new(1, -146, 1, 0)
		name.RichText = false
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.ZIndex = 3
		name.Parent = surface

		if not entry.read then
			-- The unread mark, kept: it is a state the arcade row shows and
			-- dropping it would cost the reader information.
			GPControlKit.Chip(theme, surface, {
				text = "New",
				fill = theme.Colors.Secondary,
				size = UDim2.fromOffset(62, 24),
				position = UDim2.new(1, -spacing.M, 0.5, 0),
				anchorPoint = Vector2.new(1, 0.5),
				zIndex = 3,
			})
		end
	else
		local mark = GPLayoutKit.Slice(theme, "daisy", theme.Colors.Surface, "Mark")
		mark.ImageTransparency = 0.3
		mark.ScaleType = Enum.ScaleType.Fit
		mark.AnchorPoint = Vector2.new(0, 0.5)
		mark.Position = UDim2.new(0, spacing.M + 4, 0.5, 0)
		mark.Size = UDim2.fromOffset(32, 32)
		mark.ZIndex = 3
		mark.Parent = surface

		local name = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Name")
		name.Text = "Still to find"
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Position = UDim2.fromOffset(66, 0)
		name.Size = UDim2.new(1, -80, 1, 0)
		name.ZIndex = 3
		name.Parent = surface
	end

	hit.Activated:Connect(function()
		self:_SelectEntry(entry)
	end)
	-- Animate LAST, after the final colours (it snapshots the rest colour).
	UIChrome.Animate(theme, hit, surface)

	table.insert(self._rows, { entry = entry, surface = surface, stroke = stroke })
end

-- Selection is a RING, never a background change (§4.3) — under GP the ring is
-- a deepened-rose 3px rim, and rest returns to the deepened tint of the row's
-- own fill so a discovered row and an empty one each keep their own hue.
function CodexScreen:_RefreshGPSelection()
	local theme = self:GetTheme()
	local chrome = theme.Chrome
	for _, row in self._rows do
		local selected = row.entry.id == self._selectedId
		if selected then
			row.stroke.Color = GPLayoutKit.Deepen(theme, theme.Semantic.Selection, 1)
			row.stroke.Thickness = 3
			row.stroke.Transparency = 0
		else
			row.stroke.Color = GPLayoutKit.Deepen(theme, row.surface.BackgroundColor3, 1)
			row.stroke.Thickness = (chrome and chrome.StrokeThickness) or 2
			row.stroke.Transparency = if row.entry.discovered
				then ((chrome and chrome.StrokeTransparency) or 0.35)
				else 0.5
		end
	end
end

function CodexScreen:_RenderGPDetail()
	local theme = self:GetTheme()
	local entry = self:_Selected()
	if not entry then
		self._titleLabel.Text = ""
		self._categoryLabel.Text = ""
		self._bodyLabel.Text = "Pick an entry."
		self._foundLabel.Text = ""
		return
	end

	local icon = GPControlKit.Icon(theme, self._iconSlot, entry.icon or "book", 140)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.ZIndex = 4
	self._detailIcon = icon

	local categoryLabel = ""
	for _, tab in TABS do
		if tab.id == entry.category then
			categoryLabel = gpTitle(tab.label)
			break
		end
	end

	if entry.discovered then
		self._titleLabel.Text = gpTitle(entry.name)
		self._titleLabel.TextColor3 = theme.Colors.TextPrimary
		self._categoryLabel.Text = categoryLabel
		self._bodyLabel.Text = entry.body or ""
		self._bodyLabel.TextColor3 = theme.Colors.TextPrimary
		self._foundLabel.Text = entry.foundDate and ("Found " .. gpTitle(entry.foundDate)) or ""
		self._foundLabel.TextColor3 = theme.Colors.TextPrimary
	else
		-- The §9 mystery grammar, translated: a BLUSH silhouette on cream. The
		-- arcade near-black would be invisible here — under this pack
		-- Arcade.NearBlack resolves to a near-WHITE.
		tintIcon(icon, theme.Colors.Surface)
		self._titleLabel.Text = "Still to find"
		self._titleLabel.TextColor3 = theme.Colors.TextSecondary
		self._categoryLabel.Text = categoryLabel
		self._bodyLabel.Text = "Nobody has written this one up yet. Keep wandering — it is out there."
		self._bodyLabel.TextColor3 = theme.Colors.TextSecondary
		self._foundLabel.Text = "Not found yet"
		self._foundLabel.TextColor3 = theme.Colors.TextSecondary
	end
end

function CodexScreen:_BuildContent()
	-- GP layout language: the same codex on cream paper.
	if self:LayoutKit() == "GP" then
		self._gp = true
		self:_BuildGPLayout()
		return
	end
	self._gp = false

	local theme = self:GetTheme()

	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = "CODEX",
		sizePx = Vector2.new(CARD_W, CARD_H),
		onClose = function()
			self.ScreenController:HideScreen("codex")
		end,
	})
	self._modal = modal
	local content = modal.content

	-- Category tabs: Blue active / Ghost rest (the shop category-bar grammar).
	local tabBar = UIStyler.Frame("Tabs")
	tabBar.BackgroundTransparency = 1
	tabBar.Size = UDim2.fromOffset(LEFT_W, TAB_H)
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
	}).Parent = tabBar
	tabBar.Parent = content

	for i, tab in TABS do
		local button = UIButtonComponent.new()
		button:Create(tabBar, {
			text = tab.label,
			variant = tab.id == self._tab and "Blue" or "Ghost",
			size = UDim2.fromOffset(TAB_W, TAB_H),
			layoutOrder = i,
			onClick = function()
				self:_SelectTab(tab.id)
			end,
		})
		self._tabButtons[tab.id] = button
	end

	-- Header completion ruler (doc §8: gold ruler), top-right over the detail
	-- pane's column.
	self._completionBar = UIProgressBarComponent.new()
	self._completionBar:Create(content, {
		value = 0,
		maxValue = 1,
		label = "DISCOVERED",
		size = UDim2.fromOffset(360, 28),
		position = UDim2.new(1, -360, 0, 6),
	})

	-- Left: the entry list.
	local list = Instance.new("ScrollingFrame")
	list.Name = "EntryList"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(0, BODY_Y)
	list.Size = UDim2.fromOffset(LEFT_W, BODY_H)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = SCROLLBAR
	list.ScrollBarImageColor3 = theme.Arcade.Gold
	list.Parent = content
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, ROW_GAP),
	}).Parent = list
	self._list = list

	-- Right: the detail pane.
	local detail = UIChrome.Panel(theme, "Arcade", "Detail")
	detail.Position = UDim2.fromOffset(DETAIL_X, BODY_Y)
	detail.Size = UDim2.fromOffset(DETAIL_W, BODY_H)
	detail.Parent = content
	self._detail = detail

	-- Big icon over the spinning white sunburst (doc §10 — white @ 0.7,
	-- 45°/s, only while on-screen; the connection drops on hide).
	local iconSlot = UIStyler.Frame("IconSlot")
	iconSlot.BackgroundTransparency = 1
	iconSlot.AnchorPoint = Vector2.new(0.5, 0)
	iconSlot.Position = UDim2.new(0.5, 0, 0, 20)
	iconSlot.Size = UDim2.fromOffset(190, 190)
	iconSlot.Parent = detail
	self._iconSlot = iconSlot
	local burst, spin = UIAssets.SunburstBehind(iconSlot, Color3.new(1, 1, 1), 0.7, 45)
	self._burst = burst
	self._spinConn = spin

	local title = UIChrome.Text("Title", 28, theme.Colors.TextPrimary)
	title.Position = UDim2.fromOffset(24, 216)
	title.Size = UDim2.new(1, -48, 0, 34)
	title.RichText = false
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Parent = detail
	self._titleLabel = title

	local category = UIChrome.Text("Category", 16, theme.Arcade.Gold)
	category.Position = UDim2.fromOffset(24, 252)
	category.Size = UDim2.new(1, -48, 0, 20)
	category.Parent = detail
	self._categoryLabel = category

	-- Long lore paragraphs scroll rather than truncate.
	local bodyScroll = Instance.new("ScrollingFrame")
	bodyScroll.Name = "Body"
	bodyScroll.BackgroundTransparency = 1
	bodyScroll.BorderSizePixel = 0
	bodyScroll.Position = UDim2.fromOffset(26, 286)
	bodyScroll.Size = UDim2.new(1, -52, 0, BODY_H - 286 - 46)
	bodyScroll.CanvasSize = UDim2.new()
	bodyScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	bodyScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	bodyScroll.ScrollBarThickness = SCROLLBAR
	bodyScroll.ScrollBarImageColor3 = theme.Arcade.Gold
	bodyScroll.Parent = detail

	local body = UIChrome.BodyText("Flavour", 17, theme.Colors.TextPrimary)
	body.Size = UDim2.new(1, -SCROLLBAR - 4, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.RichText = false
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.LineHeight = 1.25
	body.Parent = bodyScroll
	self._bodyLabel = body

	-- Discovery stat line, pinned to the pane's foot (countdown-surface gold,
	-- doc §11.3 grammar).
	local found = UIChrome.Text("Found", 18, theme.Arcade.SunburstGold)
	found.AnchorPoint = Vector2.new(0, 1)
	found.Position = UDim2.new(0, 24, 1, -14)
	found.Size = UDim2.new(1, -48, 0, 24)
	found.TextXAlignment = Enum.TextXAlignment.Left
	found.Parent = detail
	self._foundLabel = found

	self:_RenderAll()
end

function CodexScreen:_SelectTab(tabId: string)
	if self._tab == tabId then
		return
	end
	self._tab = tabId
	self._selectedId = nil
	self:_RenderAll()
end

function CodexScreen:_RenderAll()
	self:_RenderTabs()
	self:_RenderHeader()
	self:_RenderList()
	self:_RenderDetail()
end

function CodexScreen:_RenderTabs()
	for _, tab in TABS do
		local button = self._tabButtons[tab.id]
		if button then
			button:SetContent({
				text = tab.label,
				variant = tab.id == self._tab and "Blue" or "Ghost",
			})
		end
	end
end

function CodexScreen:_RenderHeader()
	local discovered, total = self:_Counts()
	self._completionBar:Set(discovered, math.max(total, 1))
end

function CodexScreen:_RenderList()
	local theme = self:GetTheme()
	for _, component in self._rowComponents do
		component:Destroy()
	end
	table.clear(self._rowComponents)
	table.clear(self._rows)
	-- Row shadows are budget handles; a rebuilt list has to give the old ones
	-- back before it takes new ones.
	GPLayoutKit.ReleaseShadows(self._gpRowShadows)
	for _, child in self._list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local entries = self:_Filtered()
	if #entries == 0 then
		if self._gp then
			local empty = GPLayoutKit.BodyText(theme, theme.TextSizes.Subtitle, theme.Colors.TextSecondary, "Empty")
			empty.Text = "Nothing written down here yet."
			empty.TextXAlignment = Enum.TextXAlignment.Left
			empty.Size = UDim2.new(1, -SCROLLBAR, 0, 80)
			empty.Parent = self._list
			return
		end
		local empty = UIChrome.Text("Empty", 22, theme.Arcade.GreyOwned)
		empty.Text = "NOTHING CATALOGUED"
		empty.Size = UDim2.new(1, -SCROLLBAR, 0, 80)
		empty.Parent = self._list
		return
	end

	if not self._selectedId then
		self._selectedId = entries[1].id
	end
	for index, entry in entries do
		self:_BuildRow(entry, index)
	end
	self:_RefreshSelection()
end

function CodexScreen:_BuildRow(entry: Entry, index: number)
	if self._gp then
		self:_BuildGPRow(entry, index)
		return
	end
	local theme = self:GetTheme()

	-- Fixed transparent footprint: hover/press scale the inner surface only,
	-- so the row never reflows its list neighbours.
	local root = UIStyler.Frame("Row_" .. entry.id)
	root.BackgroundTransparency = 1
	root.Size = UDim2.new(1, -SCROLLBAR, 0, ROW_H)
	root.LayoutOrder = index
	root.Parent = self._list

	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 1
	hit.Parent = root

	local surface = UIStyler.Frame("Surface")
	-- Undiscovered rows are near-black silhouettes; discovered rows use the
	-- standard card/row surface (doc §3.2).
	surface.BackgroundColor3 = entry.discovered and theme.Arcade.Row or theme.Arcade.NearBlack
	surface.BackgroundTransparency = entry.discovered and theme.Arcade.RowTransparency or 0
	surface.AnchorPoint = Vector2.new(0.5, 0.5)
	surface.Position = UDim2.fromScale(0.5, 0.5)
	surface.Size = UDim2.fromScale(1, 1)
	surface.ZIndex = 2
	local stroke = UIChrome.Stroke(theme, "Arcade")
	stroke.Parent = surface
	UIChrome.GlassGradient().Parent = surface
	surface.Parent = root

	if entry.discovered then
		local icon = IconArchive.Image(surface, entry.icon or "book", 40)
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 12, 0.5, 0)

		local name = UIChrome.Text("Name", 20, theme.Colors.TextPrimary)
		name.Text = entry.name
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Position = UDim2.fromOffset(64, 0)
		name.Size = UDim2.new(1, -140, 1, 0)
		name.RichText = false
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Parent = surface

		if not entry.read then
			local badgeSlot = UIStyler.Frame("BadgeSlot")
			badgeSlot.BackgroundTransparency = 1
			badgeSlot.AnchorPoint = Vector2.new(1, 0.5)
			badgeSlot.Position = UDim2.new(1, -14, 0.5, 0)
			badgeSlot.Size = UDim2.fromOffset(56, 22)
			badgeSlot.Parent = surface
			local badge = UIBadgeComponent.new()
			badge:Create(badgeSlot, { text = "NEW", variant = "New" })
			badge.Root.AnchorPoint = Vector2.new(1, 0)
			badge.Root.Position = UDim2.fromScale(1, 0)
			table.insert(self._rowComponents, badge)
		end
	else
		local lock = IconArchive.Image(surface, "lock", 28)
		lock.AnchorPoint = Vector2.new(0, 0.5)
		lock.Position = UDim2.new(0, 18, 0.5, 0)
		dimIcon(lock, 0.35)

		local name = UIChrome.Text("Name", 20, theme.Arcade.GreyOwned)
		name.Text = "???"
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Position = UDim2.fromOffset(64, 0)
		name.Size = UDim2.new(1, -80, 1, 0)
		name.Parent = surface
	end

	hit.Activated:Connect(function()
		self:_SelectEntry(entry)
	end)
	-- Animate LAST, after the final colours (it snapshots the rest colour).
	UIChrome.Animate(theme, hit, surface)

	table.insert(self._rows, { entry = entry, surface = surface, stroke = stroke })
end

function CodexScreen:_RefreshSelection()
	if self._gp then
		self:_RefreshGPSelection()
		return
	end
	local theme = self:GetTheme()
	for _, row in self._rows do
		local selected = row.entry.id == self._selectedId
		row.stroke:Destroy()
		local stroke = UIChrome.Stroke(theme, "Arcade", selected and "Selection" or "Panel")
		stroke.Parent = row.surface
		row.stroke = stroke
	end
end

function CodexScreen:_SelectEntry(entry: Entry)
	self._selectedId = entry.id
	if entry.discovered and not entry.read then
		-- Opening an entry is what clears its NEW badge (read in place).
		entry.read = true
		self:_RenderList()
	else
		self:_RefreshSelection()
	end
	self:_RenderDetail()
end

function CodexScreen:_Selected(): Entry?
	for _, entry in (self._data :: CodexData).entries do
		if entry.id == self._selectedId then
			return entry
		end
	end
	return nil
end

function CodexScreen:_RenderDetail()
	local theme = self:GetTheme()
	if self._detailIcon then
		self._detailIcon:Destroy()
		self._detailIcon = nil
	end
	if self._gp then
		self:_RenderGPDetail()
		return
	end

	local entry = self:_Selected()
	if not entry then
		self._titleLabel.Text = ""
		self._categoryLabel.Text = ""
		self._bodyLabel.Text = "Select an entry."
		self._foundLabel.Text = ""
		return
	end

	local icon = IconArchive.Image(self._iconSlot, entry.icon or "book", 140)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.ZIndex = 3
	self._detailIcon = icon

	local categoryLabel = ""
	for _, tab in TABS do
		if tab.id == entry.category then
			categoryLabel = tab.label
			break
		end
	end

	if entry.discovered then
		self._titleLabel.Text = entry.name
		self._titleLabel.TextColor3 = theme.Colors.TextPrimary
		self._categoryLabel.Text = categoryLabel
		self._bodyLabel.Text = entry.body or ""
		self._bodyLabel.TextColor3 = theme.Colors.TextPrimary
		self._foundLabel.Text = entry.foundDate and ("FOUND " .. entry.foundDate) or ""
		self._foundLabel.TextColor3 = theme.Arcade.SunburstGold
	else
		-- The §9 mystery grammar: the real icon recoloured near-black as a
		-- silhouette over the spinning white sunburst.
		tintIcon(icon, theme.Arcade.NearBlack)
		self._titleLabel.Text = "???"
		self._titleLabel.TextColor3 = theme.Arcade.GreyOwned
		self._categoryLabel.Text = categoryLabel
		self._bodyLabel.Text = "This entry has not been discovered yet. Keep exploring."
		self._bodyLabel.TextColor3 = theme.Arcade.GreyOwned
		self._foundLabel.Text = "UNDISCOVERED"
		self._foundLabel.TextColor3 = theme.Arcade.GreyOwned
	end
end

function CodexScreen:_Apply(data: any)
	if data.entries then
		self._data = { entries = data.entries }
		self._selectedId = nil
	end
end

function CodexScreen:_OnShow(data: any?)
	if data then
		self:_Apply(data)
		self:_RenderAll()
	end
	-- The sunburst spin was dropped on hide (doc §5.4); rewire it.
	if self._burst and not self._spinConn then
		self._spinConn = UIChrome.Spin(self._burst, 45)
	end
	if self._modal then
		UIChrome.PopIn(self:GetTheme(), self._modal.content)
	end
end

function CodexScreen:_OnHide()
	if self._spinConn then
		self._spinConn:Disconnect()
		self._spinConn = nil
	end
end

function CodexScreen:Update(data: any)
	if not data then
		return
	end
	self:_Apply(data)
	if self._built then
		self:_RenderAll()
	end
end

-- A style rebuild destroys the Gui but NOT the shadow budget count.
function CodexScreen:_OnTeardown()
	if self._spinConn then
		self._spinConn:Disconnect()
		self._spinConn = nil
	end
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	GPLayoutKit.ReleaseShadows(self._gpRowShadows)
	self._gpShadows = nil
	self._gpRowShadows = nil
	self._modal = nil
	self._burst = nil
	self._detailIcon = nil
	table.clear(self._rows)
	table.clear(self._tabButtons)
	self._completionBar = nil
end

function CodexScreen:Destroy()
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	GPLayoutKit.ReleaseShadows(self._gpRowShadows)
	if self._spinConn then
		self._spinConn:Disconnect()
		self._spinConn = nil
	end
	for _, component in self._rowComponents do
		component:Destroy()
	end
	table.clear(self._rowComponents)
	for _, button in self._tabButtons do
		button:Destroy()
	end
	table.clear(self._tabButtons)
	if self._completionBar then
		self._completionBar:Destroy()
		self._completionBar = nil
	end
	UIScreenBase.Destroy(self)
end

return CodexScreen
