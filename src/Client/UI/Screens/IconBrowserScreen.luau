--!strict
-- Icon archive browser — dev tooling, deliberately NOT in ScreenManifest: a
-- dev panel constructs and registers it under the id "iconBrowser" when it
-- wants it. It is the tool that proves the archive works end to end.
--
-- Layout (fixed px at the 1650×1020 baseline): a search well and a selected-key
-- field across the top, a horizontally-scrolling category tab row built from
-- IconArchive.Categories(), then a 7-column grid of every icon in the active
-- category — each rendered through IconArchive.Image at 56px with its catalogue
-- key underneath in micro type — and a detail panel on the right listing every
-- VARIANT (colourway · outline flag · source size) with whether that variant is
-- actually uploaded. The modal header carries IconArchive.Coverage() as
-- "142 / 203 icons uploaded" — the one number that says how usable the archive
-- is right now.
--
-- Selection is stroke-only (doc §4.3): the cell's black rim is swapped for the
-- gold selection ring through UIChrome, so the hover spring never fights it.

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
-- Required for its exported Icon/Variant types only; every lookup goes through
-- IconArchive, which is the seam screens are allowed to use.
local IconCatalog = require(script.Parent.Parent.Icons.IconCatalog)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local GPControlKit = require(script.Parent.Parent.Framework.GPControlKit)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)

local IconBrowserScreen = setmetatable({}, { __index = UIScreenBase })
IconBrowserScreen.__index = IconBrowserScreen

-- Fixed px at the 1650×1020 baseline. Content = card − the §7.4 insets.
local CARD = Vector2.new(1300, 800)
local ROW_A_H = 44
local ROW_B_H = 42
local SEARCH_W = 460
local COUNT_W = 200
local SELECTED_W = 560
local DETAIL_W = 400
local GUTTER = 14
local COLUMNS = 7
local CELL_PAD = 10
local CELL_H = 132
local ICON_PX = 56
local SCROLLBAR_RESERVE = 12
local TAB_W = 132
local TAB_H = 38
local TAB_GAP = 8
local ALL_TAB = "ALL"
local SEARCH_DEBOUNCE = 0.15

-- The whole archive, walked category by category so the ALL tab reads as
-- grouped rather than as one alphabetical soup.
local function allIcons(): { IconCatalog.Icon }
	local out: { IconCatalog.Icon } = {}
	for _, category in IconArchive.Categories() do
		for _, icon in IconArchive.InCategory(category) do
			table.insert(out, icon)
		end
	end
	return out
end

-- GP (Girly Pop) geometry: GPLayoutKit.Page spends 48px more vertical chrome
-- than the §7.4 card, so the GP card is authored 48px taller and its content
-- rect lands pixel-identical — same three rows, same seven columns, same
-- 400px detail panel.
local GP_CARD_GROW = 48
local GP_SCROLL_PAD = 6

-- Category names arrive as catalogue strings ("ALL", "ui", "combat"). Pack law
-- 5 forbids all-caps copy; the raw key is still printed verbatim on every cell
-- and in the selected-key field, so nothing is lost to the casing.
local function gpTitle(text: string): string
	return (string.gsub(string.lower(text), "(%a[%w']*)", function(word: string)
		return string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2)
	end))
end

function IconBrowserScreen.new()
	local self = UIScreenBase.new("IconBrowserScreen", 21)
	self._category = ALL_TAB
	self._search = ""
	self._selected = nil :: string?
	self._cells = {} :: { { key: string, surface: Frame, stroke: UIStroke, selected: boolean } }
	self._tabs = {} :: { { id: string, button: any } }
	-- GP branch state: the flag the shared render methods read, plus the page
	-- shadow sink. Grid cells take NO shadow — the archive can show 200+ at
	-- once and the engine's budget is about 100.
	self._gp = false
	self._gpShadows = nil :: { any }?
	return setmetatable(self, IconBrowserScreen)
end

-- Not in the manifest, so the controller may not know this id. Ask it first
-- (the normal path once a dev panel has registered us), then fall back to
-- hiding ourselves so the close button is never dead.
function IconBrowserScreen:_Close()
	if self.ScreenController then
		self.ScreenController:HideScreen("iconBrowser")
	end
	if self._visible then
		self:Hide()
	end
end

-- ---- chrome helpers ----------------------------------------------------

-- A recessed near-black well: the arcade's input/readout surface.
local function well(theme: Types.UITheme, name: string): Frame
	local frame = UIStyler.Frame(name)
	frame.BackgroundColor3 = theme.Arcade.NearBlack
	frame.BackgroundTransparency = 0
	UIChrome.Stroke(theme, "Arcade").Parent = frame
	UIChrome.GlassGradient().Parent = frame
	return frame
end

-- ---- selection ---------------------------------------------------------

function IconBrowserScreen:_SetSelected(key: string?)
	local theme = self:GetTheme()
	self._selected = key
	if self._gp then
		-- Repaint the SAME stroke rather than swapping it: UIChrome.Stroke
		-- resolves to BLACK under this pack's Chrome policy (law 1). Selection
		-- is still a RING and still only touches the two cells that changed.
		local chrome = theme.Chrome
		for _, cell in self._cells do
			local selected = cell.key == key
			if selected ~= cell.selected then
				cell.selected = selected
				if selected then
					cell.stroke.Color = GPLayoutKit.Deepen(theme, theme.Semantic.Selection, 1)
					cell.stroke.Thickness = 3
					cell.stroke.Transparency = 0
				else
					cell.stroke.Color = GPLayoutKit.Deepen(theme, cell.surface.BackgroundColor3, 1)
					cell.stroke.Thickness = (chrome and chrome.StrokeThickness) or 2
					cell.stroke.Transparency = if cell.surface.BackgroundTransparency > 0
						then 0.5
						else ((chrome and chrome.StrokeTransparency) or 0.35)
				end
			end
		end
		self:_RenderDetail(key)
		return
	end
	for _, cell in self._cells do
		local selected = cell.key == key
		if selected ~= cell.selected then
			-- Swap the rim rather than tinting it: the stroke POLICY lives in
			-- UIChrome, so selection asks for the "Selection" intent and gets
			-- the gold 3px ring while rest gets the 3px black. Only the two
			-- cells that actually changed are touched.
			cell.selected = selected
			cell.stroke:Destroy()
			cell.stroke = UIChrome.Stroke(theme, "Arcade", if selected then "Selection" else "Panel")
			cell.stroke.Parent = cell.surface
		end
	end
	self:_RenderDetail(key)
end

-- ---- detail panel ------------------------------------------------------

-- The GP variant list. Same rows, same "colourway · fill/outline · Npx" spec
-- string and the same UPLOADED / MISSING chip on every one — an archive
-- browser that hides a variant is worthless, so nothing here collapses.
function IconBrowserScreen:_RenderGPDetail(key: string?)
	local theme = self:GetTheme()
	local spacing = theme.Spacing
	local body = self._detailBody

	local icon = if key then IconArchive.Entry(key) else nil
	if not icon then
		self._selectedField.Text = "(none)"
		self._detailKey.Text = "Pick an icon"
		self._detailMeta.Text = "Tap any tile to inspect its variants."
		self._detailId.Text = ""
		return
	end

	self._selectedField.Text = icon.key
	self._detailKey.Text = icon.key
	self._detailMeta.Text = string.format("%s  ·  %s", icon.name, icon.category)
	self._detailId.Text = IconArchive.Id(icon.key) or "not uploaded yet"

	local preview = GPControlKit.Icon(theme, self._detailPreview, icon.key, 132)
	preview.AnchorPoint = Vector2.new(0.5, 0.5)
	preview.Position = UDim2.fromScale(0.5, 0.5)
	preview.ZIndex = 45
	UIChrome.PopIn(theme, preview)

	for index, variant in icon.variants do
		local uploaded = variant.assetId ~= nil
		local fill = if uploaded then theme.Colors.SurfaceRaised else theme.Colors.Background
		local row = UIStyler.Frame("Variant" .. index)
		row.BackgroundColor3 = fill
		row.BackgroundTransparency = if uploaded then 0 else 0.45
		row.Size = UDim2.new(1, -GP_SCROLL_PAD, 0, 34)
		row.LayoutOrder = index
		row.ZIndex = 45
		row.Parent = body
		GPLayoutKit.Petal(theme, row, index)
		local rim = GPLayoutKit.SoftStroke(theme, row, fill)
		if not uploaded then
			-- An un-uploaded variant is an EMPTY SLOT, not a locked one: the
			-- lighter rim is the pack's dashed read against its filled siblings.
			rim.Transparency = 0.5
		end

		local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "Spec")
		label.RichText = false
		label.Text = string.format(
			"%s · %s · %dpx",
			variant.colorway,
			if variant.outline then "outline" else "fill",
			variant.size
		)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Position = UDim2.fromOffset(spacing.M, 0)
		label.Size = UDim2.new(1, -(spacing.M + 100), 1, 0)
		label.ZIndex = 46
		label.Parent = row

		-- Availability recolours IN PLACE (doc §11.2): a missing upload is a
		-- state, never a removed row.
		GPControlKit.Chip(theme, row, {
			text = if uploaded then "Uploaded" else "Not yet",
			fill = if uploaded then theme.Colors.Secondary else theme.Colors.Surface,
			size = UDim2.fromOffset(84, 22),
			position = UDim2.new(1, -8, 0.5, 0),
			anchorPoint = Vector2.new(1, 0.5),
			zIndex = 46,
		})
	end
end

function IconBrowserScreen:_RenderDetail(key: string?)
	local theme = self:GetTheme()
	local body = self._detailBody
	for _, child in body:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for _, child in self._detailPreview:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if self._gp then
		self:_RenderGPDetail(key)
		return
	end

	local icon = if key then IconArchive.Entry(key) else nil
	if not icon then
		self._selectedField.Text = "(none)"
		self._detailKey.Text = "SELECT AN ICON"
		self._detailMeta.Text = "Click any tile to inspect its variants."
		self._detailId.Text = ""
		return
	end

	self._selectedField.Text = icon.key
	self._detailKey.Text = icon.key
	self._detailMeta.Text = string.format("%s  ·  %s", icon.name, icon.category)
	self._detailId.Text = IconArchive.Id(icon.key) or "not uploaded"

	local preview = IconArchive.Image(self._detailPreview, icon.key, 132)
	preview.AnchorPoint = Vector2.new(0.5, 0.5)
	preview.Position = UDim2.fromScale(0.5, 0.5)
	preview.ZIndex = 45
	UIChrome.PopIn(theme, preview)

	for index, variant in icon.variants do
		local row = UIStyler.Frame("Variant" .. index)
		row.BackgroundColor3 = theme.Arcade.Row
		row.BackgroundTransparency = theme.Arcade.RowTransparency
		row.Size = UDim2.new(1, 0, 0, 34)
		row.LayoutOrder = index
		row.ZIndex = 45
		UIChrome.Stroke(theme, "Arcade").Parent = row
		row.Parent = body

		local uploaded = variant.assetId ~= nil
		local label = UIChrome.Text("Spec", 15, theme.Colors.TextPrimary)
		label.RichText = false
		label.Text = string.format(
			"%s · %s · %dpx",
			variant.colorway,
			if variant.outline then "outline" else "fill",
			variant.size
		)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Position = UDim2.fromOffset(8, 0)
		label.Size = UDim2.new(1, -96, 1, 0)
		label.ZIndex = 46
		label.Parent = row

		-- Ownership/availability recolours IN PLACE (doc §11.2): a missing
		-- upload is the grey state, never a removed row.
		local chip = UIStyler.Frame("State")
		chip.BackgroundColor3 = if uploaded then theme.Arcade.Green else theme.Arcade.GreyOwned
		chip.BackgroundTransparency = 0
		chip.AnchorPoint = Vector2.new(1, 0.5)
		chip.Position = UDim2.new(1, -6, 0.5, 0)
		chip.Size = UDim2.fromOffset(76, 22)
		chip.ZIndex = 46
		UIChrome.ArcadeBevel().Parent = chip
		chip.Parent = row

		local chipLabel = UIChrome.Text("Label", 13, theme.Colors.TextPrimary)
		chipLabel.RichText = false
		chipLabel.Text = if uploaded then "UPLOADED" else "MISSING"
		chipLabel.Size = UDim2.fromScale(1, 1)
		chipLabel.ZIndex = 47
		chipLabel.Parent = chip
	end
end

-- ---- grid --------------------------------------------------------------

-- Search and category compose: with no search term the tab decides the pool,
-- and a term narrows whatever that tab already showed (ALL searches the lot).
function IconBrowserScreen:_Results(): { IconCatalog.Icon }
	local term = self._search
	if term == "" then
		if self._category == ALL_TAB then
			return allIcons()
		end
		return IconArchive.InCategory(self._category)
	end
	local matches = IconArchive.Search(term)
	if self._category == ALL_TAB then
		return matches
	end
	local out: { IconCatalog.Icon } = {}
	for _, icon in matches do
		if icon.category == self._category then
			table.insert(out, icon)
		end
	end
	return out
end

-- One grid cell: a near-black surface carrying the boxless icon and its key,
-- with a full-size invisible hit button so the whole cell is the target and
-- there are no dead zones inside it (doc §11.6).
-- One GP grid cell. Petal plate, the archive art at 56px and the catalogue key
-- verbatim underneath. A catalogued-but-unuploaded icon becomes the pack's SOFT
-- OUTLINE instead of a dimmed black tile — the gap is still obvious at a
-- glance, it just reads as a slot waiting to be filled.
--
-- Deliberately SHADOW-FREE: the ALL tab can render 200+ cells and the engine's
-- guidance is about 100 shadows on screen.
function IconBrowserScreen:_BuildGPCell(parent: Instance, order: number, icon: IconCatalog.Icon)
	local theme = self:GetTheme()
	local has = IconArchive.Has(icon.key)

	local root = UIStyler.Frame("Cell_" .. icon.key)
	root.BackgroundTransparency = 1
	root.LayoutOrder = order
	root.ZIndex = 43
	root.Parent = parent

	local fill = if has then theme.Colors.SurfaceRaised else theme.Colors.Background
	local surface = UIStyler.Frame("Surface")
	surface.BackgroundColor3 = fill
	surface.BackgroundTransparency = if has then 0 else 0.45
	surface.AnchorPoint = Vector2.new(0.5, 0.5)
	surface.Position = UDim2.fromScale(0.5, 0.5)
	surface.Size = UDim2.fromScale(1, 1)
	surface.ZIndex = 44
	surface.Parent = root
	GPLayoutKit.Petal(theme, surface, order)
	local stroke = GPLayoutKit.SoftStroke(theme, surface, fill)
	if not has then
		stroke.Transparency = 0.5
	end

	local art = GPControlKit.Icon(theme, surface, icon.key, ICON_PX)
	art.AnchorPoint = Vector2.new(0.5, 0)
	art.Position = UDim2.new(0.5, 0, 0, 16)
	art.ZIndex = 45

	-- The catalogue key VERBATIM: this is the string a caller has to type, so
	-- it is never re-cased or prettified.
	local label = GPLayoutKit.BodyText(theme, 11, theme.Colors.TextPrimary, "Key")
	label.RichText = false
	label.Text = icon.key
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -8)
	label.Size = UDim2.new(1, -8, 0, 26)
	label.TextWrapped = true
	label.ZIndex = 45
	label.Parent = surface
	if not has then
		label.TextColor3 = theme.Colors.TextSecondary
	end

	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 43
	hit.Parent = root
	hit.Activated:Connect(function()
		self:_SetSelected(icon.key)
		UIChrome.Pulse(theme, surface)
	end)
	-- Applied LAST, after the final colours (it snapshots the rest colour).
	UIChrome.Animate(theme, hit, surface)

	table.insert(self._cells, { key = icon.key, surface = surface, stroke = stroke, selected = false })
end

function IconBrowserScreen:_BuildCell(parent: Instance, order: number, icon: IconCatalog.Icon)
	if self._gp then
		self:_BuildGPCell(parent, order, icon)
		return
	end
	local theme = self:GetTheme()

	local root = UIStyler.Frame("Cell_" .. icon.key)
	root.BackgroundTransparency = 1
	root.LayoutOrder = order
	root.ZIndex = 43
	root.Parent = parent

	local surface = UIStyler.Frame("Surface")
	surface.BackgroundColor3 = theme.Arcade.NearBlack
	surface.BackgroundTransparency = 0
	surface.AnchorPoint = Vector2.new(0.5, 0.5)
	surface.Position = UDim2.fromScale(0.5, 0.5)
	surface.Size = UDim2.fromScale(1, 1)
	surface.ZIndex = 44
	local stroke = UIChrome.Stroke(theme, "Arcade", "Panel")
	stroke.Parent = surface
	UIChrome.GlassGradient().Parent = surface
	surface.Parent = root

	local art = IconArchive.Image(surface, icon.key, ICON_PX)
	art.AnchorPoint = Vector2.new(0.5, 0)
	art.Position = UDim2.new(0.5, 0, 0, 16)
	art.ZIndex = 45

	local label = UIChrome.Text("Key", 11, theme.Arcade.IceBlue)
	label.RichText = false
	label.Text = icon.key
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -8)
	label.Size = UDim2.new(1, -8, 0, 26)
	label.TextWrapped = true
	label.ZIndex = 45
	label.Parent = surface

	-- A catalogued-but-unuploaded icon rendered as a glyph fallback: dim the
	-- tile so the gap is visible at a glance without hiding the entry.
	if not IconArchive.Has(icon.key) then
		surface.BackgroundTransparency = 0.45
		label.TextColor3 = theme.Arcade.GreyOwned
	end

	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 43
	hit.Parent = root
	hit.Activated:Connect(function()
		self:_SetSelected(icon.key)
		UIChrome.Pulse(theme, surface)
	end)
	-- Applied LAST, after the final colours (it snapshots the rest colour).
	UIChrome.Animate(theme, hit, surface)

	table.insert(self._cells, { key = icon.key, surface = surface, stroke = stroke, selected = false })
end

function IconBrowserScreen:_RenderGrid()
	local theme = self:GetTheme()
	table.clear(self._cells)
	for _, child in self._grid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local results = self:_Results()
	self._countLabel.Text = if self._gp
		then string.format("%d shown", #results)
		else string.format("%d SHOWN", #results)
	for index, icon in results do
		self:_BuildCell(self._grid, index, icon)
	end
	if #results == 0 then
		local empty = UIChrome.Text("Empty", 20, theme.Studio.TextMuted)
		empty.Text = "No icons match that search."
		empty.TextXAlignment = Enum.TextXAlignment.Left
		empty.Size = UDim2.fromOffset(400, 40)
		empty.ZIndex = 44
		empty.Parent = self._grid
	end
	self._grid.CanvasPosition = Vector2.new(0, 0)
	-- Selection survives a re-filter when the icon is still on screen.
	self:_SetSelected(self._selected)
end

-- ---- tabs --------------------------------------------------------------

function IconBrowserScreen:_SetCategory(id: string)
	self._category = id
	local theme = self:GetTheme()
	for _, tab in self._tabs do
		if self._gp then
			-- Same active/inactive split the arcade strip makes, in the pack's
			-- own terms: rose for the live tab, the blush well for the rest.
			tab.button:SetContent({
				text = gpTitle(tab.id),
				fill = if tab.id == id then theme.Colors.Primary else theme.Colors.Surface,
			})
		else
			-- Blue is the arcade's tab colour (doc §3.2); inactive tabs drop to
			-- the OWNED grey rather than disappearing.
			tab.button:SetContent({ text = tab.id, variant = if tab.id == id then "Blue" else "Grey" })
		end
	end
	self:_RenderGrid()
end

-- ---- build -------------------------------------------------------------

function IconBrowserScreen:_BuildContent()
	local theme = self:GetTheme()

	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = "ICON ARCHIVE",
		sizePx = CARD,
		onClose = function()
			self:_Close()
		end,
	})
	self._modal = modal
	local content = modal.content

	-- Coverage sits in the header, right of the title: how much of the
	-- catalogue is actually usable by the engine right now.
	local usable, total = IconArchive.Coverage()
	local coverage = UIChrome.Text("Coverage", 20, theme.Arcade.Gold)
	coverage.RichText = false
	coverage.Text = string.format("%d / %d icons uploaded", usable, total)
	coverage.TextXAlignment = Enum.TextXAlignment.Right
	coverage.AnchorPoint = Vector2.new(1, 0.5)
	coverage.Position = UDim2.new(1, -66, 0.5, 0)
	coverage.Size = UDim2.fromOffset(360, 40)
	coverage.ZIndex = 43
	coverage.Parent = modal.header

	-- Row A: search well · result count · selected-key field.
	local searchWell = well(theme, "SearchWell")
	searchWell.Size = UDim2.fromOffset(SEARCH_W, ROW_A_H)
	searchWell.ZIndex = 43
	searchWell.Parent = content

	local searchIcon = IconArchive.Image(searchWell, "search", 24)
	searchIcon.AnchorPoint = Vector2.new(0, 0.5)
	searchIcon.Position = UDim2.new(0, 10, 0.5, 0)
	searchIcon.ZIndex = 44

	local box = Instance.new("TextBox")
	box.Name = "Search"
	box.BackgroundTransparency = 1
	box.Text = ""
	box.PlaceholderText = "search the archive"
	box.PlaceholderColor3 = theme.Arcade.GreyOwned
	box.FontFace = theme.Fonts.Title
	box.TextSize = 20
	box.TextColor3 = theme.Colors.TextPrimary
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.ClearTextOnFocus = false
	box.Position = UDim2.fromOffset(44, 0)
	box.Size = UDim2.new(1, -54, 1, 0)
	box.ZIndex = 44
	UIChrome.TextOutline(box)
	box.Parent = searchWell
	self._box = box
	-- Debounced: a keystroke can rebuild 200 tiles, and rebuilding on every
	-- character of a fast typist is what makes a browser feel broken.
	self._searchToken = 0
	box:GetPropertyChangedSignal("Text"):Connect(function()
		self._searchToken += 1
		local token = self._searchToken
		task.delay(SEARCH_DEBOUNCE, function()
			if token ~= self._searchToken or not self._built then
				return
			end
			self._search = string.lower(box.Text)
			self:_RenderGrid()
		end)
	end)

	local count = UIChrome.Text("Count", 17, theme.Arcade.IceBlue)
	count.RichText = false
	count.Text = ""
	count.TextXAlignment = Enum.TextXAlignment.Left
	count.Position = UDim2.fromOffset(SEARCH_W + GUTTER, 0)
	count.Size = UDim2.fromOffset(COUNT_W, ROW_A_H)
	count.ZIndex = 43
	count.Parent = content
	self._countLabel = count

	local selectedWell = well(theme, "SelectedWell")
	selectedWell.AnchorPoint = Vector2.new(1, 0)
	selectedWell.Position = UDim2.fromScale(1, 0)
	selectedWell.Size = UDim2.fromOffset(SELECTED_W, ROW_A_H)
	selectedWell.ZIndex = 43
	selectedWell.Parent = content

	local selectedCaption = UIChrome.BodyText("Caption", 13, theme.Studio.TextMuted)
	selectedCaption.Text = "SELECTED KEY"
	selectedCaption.TextXAlignment = Enum.TextXAlignment.Left
	selectedCaption.Position = UDim2.fromOffset(12, 0)
	selectedCaption.Size = UDim2.fromOffset(120, ROW_A_H)
	selectedCaption.ZIndex = 44
	selectedCaption.Parent = selectedWell

	local selectedField = UIChrome.Text("Value", 22, theme.Arcade.Gold)
	selectedField.RichText = false
	selectedField.Text = "(none)"
	selectedField.TextXAlignment = Enum.TextXAlignment.Left
	selectedField.TextTruncate = Enum.TextTruncate.AtEnd
	selectedField.Position = UDim2.fromOffset(140, 0)
	selectedField.Size = UDim2.new(1, -150, 1, 0)
	selectedField.ZIndex = 44
	selectedField.Parent = selectedWell
	self._selectedField = selectedField

	-- Row B: the category tab strip. 13 tabs never fit the card, so the strip
	-- scrolls horizontally instead of shrinking the tabs into illegibility.
	local tabScroll = Instance.new("ScrollingFrame")
	tabScroll.Name = "Tabs"
	tabScroll.BackgroundTransparency = 1
	tabScroll.BorderSizePixel = 0
	tabScroll.Position = UDim2.fromOffset(0, ROW_A_H + 10)
	tabScroll.Size = UDim2.new(1, 0, 0, ROW_B_H)
	tabScroll.CanvasSize = UDim2.new()
	tabScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
	tabScroll.ScrollingDirection = Enum.ScrollingDirection.X
	tabScroll.ScrollBarThickness = 4
	tabScroll.ScrollBarImageColor3 = theme.Arcade.Gold
	tabScroll.ZIndex = 43
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Padding = UDim.new(0, TAB_GAP),
	}).Parent = tabScroll
	tabScroll.Parent = content

	local tabIds = { ALL_TAB }
	for _, category in IconArchive.Categories() do
		table.insert(tabIds, category)
	end
	for order, id in tabIds do
		local button = UIButtonComponent.new()
		button:Create(tabScroll, {
			text = id,
			variant = if id == self._category then "Blue" else "Grey",
			size = UDim2.fromOffset(TAB_W, TAB_H),
			layoutOrder = order,
			onClick = function()
				self:_SetCategory(id)
			end,
		})
		button.Root.ZIndex = 43
		table.insert(self._tabs, { id = id, button = button })
	end

	-- Row C: the grid (left) and the detail panel (right).
	local gridTop = ROW_A_H + 10 + ROW_B_H + 10
	local gridW = CARD.X - 28 - DETAIL_W - GUTTER

	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.Position = UDim2.fromOffset(0, gridTop)
	grid.Size = UDim2.new(0, gridW, 1, -gridTop)
	grid.CanvasSize = UDim2.new()
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.ScrollBarThickness = 6
	grid.ScrollBarImageColor3 = theme.Arcade.Gold
	grid.ZIndex = 43
	grid.Parent = content
	self._grid = grid

	local cellW = math.floor((gridW - SCROLLBAR_RESERVE - CELL_PAD * (COLUMNS - 1)) / COLUMNS)
	local layout = UIStyler.GridLayout(UDim2.fromOffset(cellW, CELL_H), UDim2.fromOffset(CELL_PAD, CELL_PAD))
	layout.FillDirectionMaxCells = COLUMNS
	layout.Parent = grid

	local detail = UIChrome.Panel(theme, "Arcade", "Detail")
	detail.AnchorPoint = Vector2.new(1, 0)
	detail.Position = UDim2.new(1, 0, 0, gridTop)
	detail.Size = UDim2.new(0, DETAIL_W, 1, -gridTop)
	detail.ZIndex = 43
	detail.Parent = content

	local previewSlot = UIStyler.Frame("Preview")
	previewSlot.BackgroundColor3 = theme.Arcade.NearBlack
	previewSlot.BackgroundTransparency = 0
	previewSlot.AnchorPoint = Vector2.new(0.5, 0)
	previewSlot.Position = UDim2.new(0.5, 0, 0, 14)
	previewSlot.Size = UDim2.fromOffset(DETAIL_W - 28, 160)
	previewSlot.ZIndex = 44
	UIChrome.Stroke(theme, "Arcade").Parent = previewSlot
	previewSlot.Parent = detail
	self._detailPreview = previewSlot

	local detailKey = UIChrome.Text("Key", 26, theme.Arcade.Gold)
	detailKey.RichText = false
	detailKey.Text = "SELECT AN ICON"
	detailKey.TextTruncate = Enum.TextTruncate.AtEnd
	detailKey.Position = UDim2.fromOffset(14, 184)
	detailKey.Size = UDim2.fromOffset(DETAIL_W - 28, 32)
	detailKey.ZIndex = 44
	detailKey.Parent = detail
	self._detailKey = detailKey

	local detailMeta = UIChrome.BodyText("Meta", 15, theme.Studio.TextMuted)
	detailMeta.Text = "Click any tile to inspect its variants."
	detailMeta.Position = UDim2.fromOffset(14, 218)
	detailMeta.Size = UDim2.fromOffset(DETAIL_W - 28, 22)
	detailMeta.ZIndex = 44
	detailMeta.Parent = detail
	self._detailMeta = detailMeta

	-- The resolved asset id: the actual string IconArchive.Id would hand the
	-- engine. Monospace on purpose — it is meant to be read digit by digit
	-- (styled themes reach it via the Numeric token, Classic keeps Code).
	local styled = theme.Chrome ~= nil
	local detailId = UIStyler.TextLabel("AssetId")
	detailId.FontFace = if styled then theme.Fonts.Numeric else Font.fromEnum(Enum.Font.Code)
	detailId.TextSize = 13
	detailId.TextColor3 = theme.Arcade.IceBlue
	detailId.RichText = false
	detailId.TextTruncate = Enum.TextTruncate.AtEnd
	detailId.Position = UDim2.fromOffset(14, 242)
	detailId.Size = UDim2.fromOffset(DETAIL_W - 28, 20)
	detailId.ZIndex = 44
	detailId.Parent = detail
	self._detailId = detailId

	local variantsCaption = UIChrome.Text("VariantsCaption", 17, theme.Arcade.SunburstGold)
	variantsCaption.RichText = false
	variantsCaption.Text = "VARIANTS"
	variantsCaption.TextXAlignment = Enum.TextXAlignment.Left
	variantsCaption.Position = UDim2.fromOffset(14, 268)
	variantsCaption.Size = UDim2.fromOffset(DETAIL_W - 28, 24)
	variantsCaption.ZIndex = 44
	variantsCaption.Parent = detail

	local variantScroll = Instance.new("ScrollingFrame")
	variantScroll.Name = "Variants"
	variantScroll.BackgroundTransparency = 1
	variantScroll.BorderSizePixel = 0
	variantScroll.Position = UDim2.fromOffset(14, 296)
	variantScroll.Size = UDim2.new(1, -28, 1, -310)
	variantScroll.CanvasSize = UDim2.new()
	variantScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	variantScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	variantScroll.ScrollBarThickness = 4
	variantScroll.ScrollBarImageColor3 = theme.Arcade.Gold
	variantScroll.ZIndex = 44
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Padding = UDim.new(0, 6),
	}).Parent = variantScroll
	variantScroll.Parent = detail
	self._detailBody = variantScroll

	self:_RenderGrid()
end

function IconBrowserScreen:_OnShow(_data: any?)
	UIChrome.PopIn(self:GetTheme(), self._modal.content)
end

function IconBrowserScreen:Destroy()
	for _, tab in self._tabs do
		tab.button:Destroy()
	end
	table.clear(self._tabs)
	table.clear(self._cells)
	UIScreenBase.Destroy(self)
end

return IconBrowserScreen
