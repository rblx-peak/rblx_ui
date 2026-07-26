--!strict
-- THEME & STYLE — two ideas, per the owner:
--
--   * STYLES are whole looks, hand-built in code (chrome, shape policy,
--     motion). They are listed, not edited — no shape sliders, no numeric
--     knobs. The base style is "Roblox Classic" (theme id "Default").
--   * COLOUR PRESETS are curated 5-swatch palettes (coolors.co-style, see
--     Config/ColorPresetConfig) that recolour the active style live with one
--     click. Semantic colours (currency coding, success/error, black strokes)
--     never move, so no preset can break meaning.
--
-- Layout packs were removed from this screen entirely — the current layout is
-- the one Default pack, configured elsewhere, later.
--
-- Wears the ARCADE family like the rest of the menus (doc §7.4 modal card:
-- red header, black card, slate wells, gold selection). Because presets
-- recolour the very chrome this screen is made of, every apply repaints the
-- open screen from the new theme — the selector demos its own work.
--
-- Layout is fixed px at the 1650×1020 baseline; UIScreenBase adds the UIScale.

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local ColorPresetConfig = require(script.Parent.Parent.Config.ColorPresetConfig)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)

local ThemeSelectorScreen = setmetatable({}, { __index = UIScreenBase })
ThemeSelectorScreen.__index = ThemeSelectorScreen

-- Fixed px geometry (1650×1020 baseline). Card uses the §7.4 anatomy: 64px
-- red header, content inset (14, 74, -28, -88).
local CARD = Vector2.new(1000, 660)
local LEFT_W = 300
local STYLE_ROW_H = 46
local PRESET_ROW_H = 62
local SWATCH = 26
local WELL_LABEL_H = 34

function ThemeSelectorScreen.new()
	local self = UIScreenBase.new("ThemeSelectorScreen", 18)
	-- nil would mean "stock, untracked"; default to the stock preset so the
	-- Classic row wears the ring on first open.
	self._activePresetId = ColorPresetConfig.DefaultPresetId :: string?
	self._styleButtons = {} :: { [string]: any }
	self._presetRows = {} :: { [string]: { row: Frame, ring: UIStroke, label: TextLabel } }
	self._buttons = {} :: { any }
	return setmetatable(self, ThemeSelectorScreen)
end

-- ClientHandler injects dev tools when present; this screen no longer hosts
-- them (layouts/tests moved out per the owner), but the seam stays so boot
-- wiring never breaks.
function ThemeSelectorScreen:SetDevTools(_layoutController: any, _runTestAll: any, _previews: any) end

-- The REGISTERED stock table for the active style — the base every preset
-- recolours from, so presets never compound on each other.
function ThemeSelectorScreen:_StockTheme(): Types.UITheme
	local current = self.ThemeController:GetTheme()
	for _, theme in self.ThemeController:GetThemeList() do
		if theme.Id == current.Id then
			return theme
		end
	end
	return current
end

function ThemeSelectorScreen:_ApplyPreset(presetId: string)
	local preset = ColorPresetConfig.Get(presetId)
	if not preset then
		return
	end
	self._activePresetId = presetId
	self.ThemeController:ApplyThemeObject(ColorPresetConfig.Apply(self:_StockTheme(), preset))
	self:_RepaintChrome()
end

function ThemeSelectorScreen:_BuildContent()
	local theme = self:GetTheme()

	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = "THEME & STYLE",
		sizePx = CARD,
		onClose = function()
			self.ScreenController:HideScreen("themeSelector")
		end,
	})
	self._modal = modal
	local content = modal.content

	-- ---- left well: styles -------------------------------------------
	local stylesWell = UIStyler.Frame("StylesWell")
	stylesWell.BackgroundColor3 = theme.Arcade.NearBlack2
	stylesWell.BackgroundTransparency = 0.25
	stylesWell.Size = UDim2.new(0, LEFT_W, 1, 0)
	stylesWell.ZIndex = 43
	UIChrome.Corner("Arcade").Parent = stylesWell
	-- Classic recipe: 2px black frame; styled chrome brings its own stroke.
	if theme.Chrome then
		UIChrome.Stroke(theme, "Arcade").Parent = stylesWell
	else
		UIStyler.Stroke(Color3.new(0, 0, 0), 2, 0).Parent = stylesWell
	end
	stylesWell.Parent = content
	self._stylesWell = stylesWell

	local stylesLabel = UIChrome.Text("Label", 18, theme.Arcade.Gold)
	stylesLabel.Text = "STYLES"
	stylesLabel.TextXAlignment = Enum.TextXAlignment.Left
	stylesLabel.Position = UDim2.fromOffset(12, 6)
	stylesLabel.Size = UDim2.new(1, -24, 0, WELL_LABEL_H - 6)
	stylesLabel.ZIndex = 44
	stylesLabel.Parent = stylesWell
	self._stylesLabel = stylesLabel

	local stylesScroll = Instance.new("ScrollingFrame")
	stylesScroll.Name = "Styles"
	stylesScroll.BackgroundTransparency = 1
	stylesScroll.BorderSizePixel = 0
	stylesScroll.Position = UDim2.fromOffset(10, WELL_LABEL_H + 4)
	stylesScroll.Size = UDim2.new(1, -20, 1, -(WELL_LABEL_H + 62))
	stylesScroll.CanvasSize = UDim2.new()
	stylesScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	stylesScroll.ScrollBarThickness = 6
	stylesScroll.ScrollBarImageColor3 = theme.Arcade.Gold
	stylesScroll.ZIndex = 44
	stylesScroll.Parent = stylesWell
	self._stylesScroll = stylesScroll

	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 6),
	}).Parent = stylesScroll

	-- Styles are built in code, with you — not knob-twiddled. Say so.
	local note = UIChrome.BodyText("Note", 13, theme.Arcade.IceBlue)
	note.Text = "Styles are whole looks, built in code.\nPalettes recolour the active style."
	note.TextWrapped = true
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.AnchorPoint = Vector2.new(0, 1)
	note.Position = UDim2.new(0, 12, 1, -8)
	note.Size = UDim2.new(1, -24, 0, 44)
	note.ZIndex = 44
	note.Parent = stylesWell
	self._note = note

	-- ---- right well: colour presets ----------------------------------
	local presetsWell = UIStyler.Frame("PresetsWell")
	presetsWell.BackgroundColor3 = theme.Arcade.NearBlack2
	presetsWell.BackgroundTransparency = 0.25
	presetsWell.Position = UDim2.fromOffset(LEFT_W + 14, 0)
	presetsWell.Size = UDim2.new(1, -(LEFT_W + 14), 1, 0)
	presetsWell.ZIndex = 43
	UIChrome.Corner("Arcade").Parent = presetsWell
	-- Classic recipe: 2px black frame; styled chrome brings its own stroke.
	if theme.Chrome then
		UIChrome.Stroke(theme, "Arcade").Parent = presetsWell
	else
		UIStyler.Stroke(Color3.new(0, 0, 0), 2, 0).Parent = presetsWell
	end
	presetsWell.Parent = content
	self._presetsWell = presetsWell

	local presetsLabel = UIChrome.Text("Label", 18, theme.Arcade.Gold)
	presetsLabel.Text = "COLOR PRESETS"
	presetsLabel.TextXAlignment = Enum.TextXAlignment.Left
	presetsLabel.Position = UDim2.fromOffset(12, 6)
	presetsLabel.Size = UDim2.new(1, -150, 0, WELL_LABEL_H - 6)
	presetsLabel.ZIndex = 44
	presetsLabel.Parent = presetsWell
	self._presetsLabel = presetsLabel

	-- RESET: back to the style's stock palette.
	local reset = UIButtonComponent.new()
	reset:Create(presetsWell, {
		text = "RESET",
		variant = "Red",
		size = UDim2.fromOffset(110, 30),
		position = UDim2.new(1, -10, 0, 4),
		anchorPoint = Vector2.new(1, 0),
		onClick = function()
			self._activePresetId = ColorPresetConfig.DefaultPresetId
			self.ThemeController:ApplyThemeObject(self:_StockTheme())
			self:_RepaintChrome()
		end,
	})
	reset.Root.ZIndex = 44
	table.insert(self._buttons, reset)

	local presetsScroll = Instance.new("ScrollingFrame")
	presetsScroll.Name = "Presets"
	presetsScroll.BackgroundTransparency = 1
	presetsScroll.BorderSizePixel = 0
	presetsScroll.Position = UDim2.fromOffset(10, WELL_LABEL_H + 4)
	presetsScroll.Size = UDim2.new(1, -20, 1, -(WELL_LABEL_H + 14))
	presetsScroll.CanvasSize = UDim2.new()
	presetsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	presetsScroll.ScrollBarThickness = 6
	presetsScroll.ScrollBarImageColor3 = theme.Arcade.Gold
	presetsScroll.ZIndex = 44
	presetsScroll.Parent = presetsWell
	self._presetsScroll = presetsScroll

	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 8),
	}).Parent = presetsScroll

	self:_BuildStyleList()
	self:_BuildPresetList()
end

function ThemeSelectorScreen:_BuildStyleList()
	local scroll = self._stylesScroll
	for _, button in self._styleButtons do
		button:Destroy()
	end
	table.clear(self._styleButtons)

	local currentId = self.ThemeController:GetTheme().Id
	for order, styleTheme in self.ThemeController:GetThemeList() do
		local button = UIButtonComponent.new()
		button:Create(scroll, {
			text = string.upper(styleTheme.DisplayName),
			-- Selection is colour (§3.3): the active style rides gold.
			variant = styleTheme.Id == currentId and "Gold" or "Blue",
			size = UDim2.new(1, -6, 0, STYLE_ROW_H),
			layoutOrder = order,
			onClick = function()
				-- Switching styles lands on that style's stock palette.
				self.ThemeController:SetTheme(styleTheme.Id)
				self._activePresetId = ColorPresetConfig.DefaultPresetId
				self:_BuildStyleList()
				self:_RepaintChrome()
			end,
		})
		button.Root.ZIndex = 45
		self._styleButtons[styleTheme.Id] = button
	end
end

function ThemeSelectorScreen:_BuildPresetList()
	local theme = self:GetTheme()
	local scroll = self._presetsScroll

	for _, entry in self._presetRows do
		entry.row:Destroy()
	end
	table.clear(self._presetRows)

	for order, preset in ColorPresetConfig.Presets do
		local row = UIStyler.Frame("Preset_" .. preset.id)
		row.BackgroundColor3 = theme.Arcade.Row
		row.BackgroundTransparency = 0.2
		row.Size = UDim2.new(1, -6, 0, PRESET_ROW_H)
		row.LayoutOrder = order
		row.ZIndex = 45
		UIChrome.Corner("Arcade").Parent = row
		-- Selection is a ring (§4.3): rest = thin black (Classic) or the
		-- style's own framing stroke; active = Semantic.Selection. The
		-- rest/active values are (re)painted in _RepaintChrome.
		local ring = if theme.Chrome
			then UIChrome.Stroke(theme, "Arcade")
			else UIStyler.Stroke(Color3.new(0, 0, 0), 2, 0)
		ring.Parent = row
		row.Parent = scroll

		local label = UIChrome.Text("Name", 16, theme.Colors.TextPrimary)
		label.Text = string.upper(preset.name)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Position = UDim2.fromOffset(14, 6)
		label.Size = UDim2.new(1, -28, 0, 22)
		label.ZIndex = 46
		label.Parent = row

		-- The coolors strip: five swatches, dark → light → accent.
		for i, color in ColorPresetConfig.Swatches(preset) do
			local swatch = UIStyler.Frame("Swatch" .. i)
			swatch.BackgroundColor3 = color
			swatch.Position = UDim2.fromOffset(14 + (i - 1) * (SWATCH + 6), 30)
			swatch.Size = UDim2.fromOffset(SWATCH, SWATCH)
			swatch.ZIndex = 46
			UIChrome.Corner("Arcade").Parent = swatch
			-- Classic: soft black ring; styled chrome frames swatches its own way.
			if theme.Chrome then
				UIChrome.Stroke(theme, "Arcade", "Swatch").Parent = swatch
			else
				UIStyler.Stroke(Color3.new(0, 0, 0), 1.5, 0.2).Parent = swatch
			end
			swatch.Parent = row
		end

		-- Whole row is one invisible button (§11.6) with the house juice.
		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.Size = UDim2.fromScale(1, 1)
		hit.AutoButtonColor = false
		hit.ZIndex = 47
		hit.Parent = row
		hit.Activated:Connect(function()
			self:_ApplyPreset(preset.id)
			UIChrome.Pulse(self:GetTheme(), row)
		end)
		UIChrome.Animate(theme, hit, row)

		self._presetRows[preset.id] = { row = row, ring = ring, label = label }
	end

	self:_RepaintChrome()
end

-- Repaint every stored piece of chrome from the CURRENT theme — called after
-- each preset apply so the open selector immediately wears the palette it
-- just handed out. Ring-only selection: backgrounds never change (§4.3).
function ThemeSelectorScreen:_RepaintChrome()
	local theme = self:GetTheme()
	local a = theme.Arcade
	if self._stylesWell then
		self._stylesWell.BackgroundColor3 = a.NearBlack2
	end
	if self._presetsWell then
		self._presetsWell.BackgroundColor3 = a.NearBlack2
	end
	if self._stylesLabel then
		self._stylesLabel.TextColor3 = a.Gold
	end
	if self._presetsLabel then
		self._presetsLabel.TextColor3 = a.Gold
	end
	if self._note then
		self._note.TextColor3 = a.IceBlue
	end
	if self._stylesScroll then
		self._stylesScroll.ScrollBarImageColor3 = a.Gold
	end
	if self._presetsScroll then
		self._presetsScroll.ScrollBarImageColor3 = a.Gold
	end
	-- Ring rest/active values mirror the UIChrome.Stroke policy: Classic =
	-- thin black rest / solid 3px Selection; styled chrome = its own framing
	-- stroke at rest, Selection at the style's weight when active.
	local chrome = theme.Chrome
	for id, entry in self._presetRows do
		entry.row.BackgroundColor3 = a.Row
		local active = id == self._activePresetId
		if active then
			entry.ring.Color = theme.Semantic.Selection
			entry.ring.Thickness = if chrome then math.max(chrome.StrokeThickness, 1) else 3
			entry.ring.Transparency = 0
			entry.label.TextColor3 = theme.Semantic.Selection
		else
			entry.ring.Color = if chrome and chrome.StrokeFollowsAccent then theme.Colors.Accent else Color3.new(0, 0, 0)
			entry.ring.Thickness = if chrome then chrome.StrokeThickness else 2
			entry.ring.Transparency = if chrome then chrome.StrokeTransparency else 0
			entry.label.TextColor3 = theme.Colors.TextPrimary
		end
	end
end

function ThemeSelectorScreen:_OnShow(_data: any?)
	-- Style roster can change between shows (future styles register at
	-- runtime); rebuild cheap lists on open.
	if self._stylesScroll then
		self:_BuildStyleList()
		self:_RepaintChrome()
	end
	if self._modal then
		UIChrome.PopIn(self:GetTheme(), self._modal.content)
	end
end

function ThemeSelectorScreen:Destroy()
	for _, button in self._buttons do
		button:Destroy()
	end
	for _, button in self._styleButtons do
		button:Destroy()
	end
	table.clear(self._styleButtons)
	UIScreenBase.Destroy(self)
end

return ThemeSelectorScreen
