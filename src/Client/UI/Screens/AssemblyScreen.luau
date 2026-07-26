--!strict
-- ASSEMBLY — the ARMORED CORE garage (manifest id "assembly", hidesHUD).
-- Full-bleed over the Colors.Background void: no ModalCard, no red header —
-- the AC style (mono type, hairline accent chrome, snap motion) IS the look.
--
-- Layout (fixed px at the 1650×1020 baseline; right column and bottom bar
-- anchor to true screen edges via Scale so ultrawide never strands them):
--   top bar   — unit name + [ ASSEMBLY ] bracket header, COAM funds right
--   left 380  — category list, then a POOLED part list (about 12 row
--               instances built once, rebound on category switch — the
--               screen opens hundreds of times; rows never churn)
--   center    — mech preview well: corner ticks, a hairline wireframe
--               stand-in, slot callouts with leader lines, and a drifting
--               coordinate readout
--   right 430 — notched SPEC panel: AP/EN segmented bars + nine stat rows
--               with hover PREVIEW ghosts and over-limit states
--   bottom    — context hints + the accent-stroked SORTIE READY ghost
--
-- ONE UITicker handler drives every ambient effect on the screen (coordinate
-- drift + over-limit banner blink); per-widget RunService connections are a
-- rejected pattern. BootSequence rescrambles the tagged labels on every show.
--
-- LOCALIZATION: the fixed-width mono columns, zero-padded values, bracket
-- framing and the [TAB]/[ESC] hint row WILL break under longer translations —
-- a localized build needs per-locale column widths. Flagged, not solved here.

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UITicker = require(script.Parent.Parent.Framework.UITicker)
local BootSequence = require(script.Parent.Parent.Framework.BootSequence)
local UISegmentedBarComponent = require(script.Parent.Parent.Components.UISegmentedBarComponent)
local UIStatRowComponent = require(script.Parent.Parent.Components.UIStatRowComponent)
local UINotchedPanelComponent = require(script.Parent.Parent.Components.UINotchedPanelComponent)
local UICornerTicksComponent = require(script.Parent.Parent.Components.UICornerTicksComponent)

local AssemblyScreen = setmetatable({}, { __index = UIScreenBase })
AssemblyScreen.__index = AssemblyScreen

-- ---- fixed px at the 1650×1020 baseline ---------------------------------

local PAD = 14
local CONTENT_Y = 72 -- below the 52px top bar + hairline rule
local BOTTOM_RESERVE = 68 -- bottom bar + rule + margins
local LEFT_W = 380
local RIGHT_W = 430
local COL_GAP = 12
local HEADER_H = 16
local CAT_ROW_H = 26
local PART_ROW_H = 44
local PART_ROW_POOL = 12
local STAT_ROW_H = 30
local AP_MAX = 12000

-- The SPEC readout, in display order. `max` normalises the row's internal
-- ghost bar; invertGoodness flips the delta colouring for costs.
local STAT_DEFS: { { id: string, label: string, unit: string?, max: number, invert: boolean? } } = {
	{ id = "AP", label = "AP", unit = nil, max = 12000 },
	{ id = "STABILITY", label = "ATTITUDE STABILITY", unit = nil, max = 3000 },
	{ id = "EN_CAP", label = "EN CAPACITY", unit = nil, max = 4500 },
	{ id = "EN_OUTPUT", label = "EN OUTPUT", unit = nil, max = 4500 },
	{ id = "EN_LOAD", label = "EN LOAD", unit = nil, max = 4500, invert = true },
	{ id = "WEIGHT", label = "WEIGHT", unit = "KG", max = 110000, invert = true },
	{ id = "LOAD_LIMIT", label = "LOAD LIMIT", unit = "KG", max = 110000 },
	{ id = "BOOST", label = "BOOST SPEED", unit = "KM/H", max = 450 },
	{ id = "QB", label = "QB RELOAD", unit = "S", max = 4 },
}

-- Which two stats a part-list row surfaces, by priority: the first two of
-- these present on the part win, so weapons lead with ATK, generators with
-- OUT/CAP, boosters with SPD/QB — without per-part display authoring.
local ROW_STAT_KEYS = {
	{ id = "ATK", tag = "ATK" },
	{ id = "AP", tag = "AP" },
	{ id = "EN_OUTPUT", tag = "OUT" },
	{ id = "EN_CAP", tag = "CAP" },
	{ id = "BOOST", tag = "SPD" },
	{ id = "QB", tag = "QB" },
	{ id = "STABILITY", tag = "STB" },
	{ id = "LOAD_LIMIT", tag = "LIM" },
	{ id = "WEIGHT", tag = "WGT" },
	{ id = "EN_LOAD", tag = "EN" },
}

type PartStats = { [string]: number }
type Part = { id: string, name: string, stats: PartStats }
type Category = { id: string, name: string, parts: { Part } }

type CatRow = { root: TextButton, label: TextLabel, tick: Frame }
type PartRow = {
	root: TextButton,
	name: TextLabel,
	s1: TextLabel,
	s2: TextLabel,
	chip: TextLabel,
	stroke: UIStroke,
}

-- ---- demo data -----------------------------------------------------------

local function part(name: string, stats: PartStats): Part
	return { id = name, name = name, stats = stats }
end

local function demoCategories(): { Category }
	local function cat(name: string, parts: { Part }): Category
		return { id = name, name = name, parts = parts }
	end
	return {
		cat("R-ARM", {
			part("MG-014 LUDLOW", { ATK = 448, WEIGHT = 2450, EN_LOAD = 102 }),
			part("RF-024 TURNER", { ATK = 621, WEIGHT = 3120, EN_LOAD = 158 }),
			part("HG-003 COQUILLETT", { ATK = 372, WEIGHT = 1650, EN_LOAD = 92 }),
			part("VVC-760PR AVIOR", { ATK = 1024, WEIGHT = 3860, EN_LOAD = 480 }),
		}),
		cat("L-ARM", {
			part("PB-033M ASHMEAD", { ATK = 1350, WEIGHT = 4180, EN_LOAD = 225 }),
			part("SG-026 HALDEMAN", { ATK = 880, WEIGHT = 3660, EN_LOAD = 180 }),
			part("VVC-770LB CANOPUS", { ATK = 1105, WEIGHT = 4520, EN_LOAD = 512 }),
			part("LT-004 KYORAI", { ATK = 590, WEIGHT = 2540, EN_LOAD = 138 }),
		}),
		cat("R-BACK", {
			part("BML-G1/P20MLT-04", { ATK = 1210, WEIGHT = 3300, EN_LOAD = 240 }),
			part("VVC-703 PULVERIZER", { ATK = 1580, WEIGHT = 5140, EN_LOAD = 604 }),
			part("SB-033M MORLEY", { ATK = 1420, WEIGHT = 4720, EN_LOAD = 262 }),
			part("BML-G2/P05MLT-10", { ATK = 1360, WEIGHT = 4020, EN_LOAD = 328 }),
		}),
		cat("L-BACK", {
			part("VP-60LCS", { ATK = 1660, WEIGHT = 6480, EN_LOAD = 720 }),
			part("BML-G1/P07VTC-12", { ATK = 980, WEIGHT = 2880, EN_LOAD = 196 }),
			part("VE-60SNA", { ATK = 1910, WEIGHT = 7350, EN_LOAD = 826 }),
			part("SI-27 SU-R8", { ATK = 240, WEIGHT = 2180, EN_LOAD = 295 }),
		}),
		cat("HEAD", {
			part("HD-011 MELANDER", { AP = 910, STABILITY = 452, WEIGHT = 3160, EN_LOAD = 145 }),
			part("VP-44S", { AP = 880, STABILITY = 500, WEIGHT = 3520, EN_LOAD = 210 }),
			part("NACHTREIHER/44E", { AP = 795, STABILITY = 386, WEIGHT = 2320, EN_LOAD = 265 }),
			part("HD-033M VERRILL", { AP = 1040, STABILITY = 545, WEIGHT = 4360, EN_LOAD = 330 }),
		}),
		cat("CORE", {
			part("BD-011 MELANDER", { AP = 3160, STABILITY = 745, WEIGHT = 15800, EN_LOAD = 300 }),
			part("VP-40S", { AP = 3480, STABILITY = 830, WEIGHT = 17100, EN_LOAD = 372 }),
			part("NACHTREIHER/40E", { AP = 2630, STABILITY = 616, WEIGHT = 12650, EN_LOAD = 410 }),
			part("CC-2000 ORBITER", { AP = 2890, STABILITY = 700, WEIGHT = 14150, EN_LOAD = 268 }),
		}),
		cat("ARMS", {
			part("AR-011 MELANDER", { AP = 2260, WEIGHT = 10480, EN_LOAD = 265 }),
			part("VP-46S", { AP = 2470, WEIGHT = 11420, EN_LOAD = 328 }),
			part("NACHTREIHER/46E", { AP = 1950, WEIGHT = 8500, EN_LOAD = 356 }),
			part("AC-3000 WRECKER", { AP = 2085, WEIGHT = 9820, EN_LOAD = 240 }),
		}),
		cat("LEGS", {
			part("LG-011 MELANDER", { AP = 4090, STABILITY = 865, LOAD_LIMIT = 72520, WEIGHT = 18560, EN_LOAD = 365 }),
			part("VP-422", { AP = 4370, STABILITY = 924, LOAD_LIMIT = 76900, WEIGHT = 20940, EN_LOAD = 430 }),
			part("NACHTREIHER/42E", { AP = 3560, STABILITY = 720, LOAD_LIMIT = 61200, WEIGHT = 14980, EN_LOAD = 462 }),
			part("LG-033M VERRILL", { AP = 4680, STABILITY = 1002, LOAD_LIMIT = 82640, WEIGHT = 23800, EN_LOAD = 512 }),
		}),
		cat("BOOSTER", {
			part("BST-G2/P04", { BOOST = 334, QB = 0.68, WEIGHT = 1820, EN_LOAD = 266 }),
			part("ALULA/21E", { BOOST = 361, QB = 0.52, WEIGHT = 2110, EN_LOAD = 390 }),
			part("BUERZEL/21D", { BOOST = 310, QB = 0.84, WEIGHT = 2460, EN_LOAD = 244 }),
			part("BST-G1/P10", { BOOST = 322, QB = 0.76, WEIGHT = 1590, EN_LOAD = 210 }),
		}),
		cat("FCS", {
			part("FCS-G2/P05", { WEIGHT = 100, EN_LOAD = 198 }),
			part("FC-006 ABBOT", { WEIGHT = 90, EN_LOAD = 218 }),
			part("VE-21A", { WEIGHT = 85, EN_LOAD = 264 }),
			part("FC-008 TALBOT", { WEIGHT = 130, EN_LOAD = 172 }),
		}),
		cat("GENERATOR", {
			part("VP-20S", { EN_CAP = 2560, EN_OUTPUT = 3160, WEIGHT = 3800 }),
			part("AG-J-098 JOSO", { EN_CAP = 2210, EN_OUTPUT = 2890, WEIGHT = 3160 }),
			part("VP-20C", { EN_CAP = 2980, EN_OUTPUT = 3420, WEIGHT = 4520 }),
			part("DF-GN-06 MING-TANG", { EN_CAP = 3420, EN_OUTPUT = 3720, WEIGHT = 5210 }),
		}),
	}
end

local function defaultLoadout(categories: { Category }): { [string]: string }
	local loadout: { [string]: string } = {}
	for _, category in categories do
		local first = category.parts[1]
		if first then
			loadout[category.name] = first.id
		end
	end
	return loadout
end

-- ---- small helpers -------------------------------------------------------

local function commas(value: number): string
	local out = tostring(math.floor(value))
	while true do
		local replaced: number
		out, replaced = string.gsub(out, "^(%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then
			break
		end
	end
	return out
end

-- Zero-padded 4-wide so the mono number columns stay flush; sub-10 decimals
-- (QB reload) keep two places instead.
local function fmtValue(v: number): string
	if math.abs(v) < 10 and v ~= math.floor(v) then
		return string.format("%.2f", v)
	end
	return string.format("%04d", math.floor(v + 0.5))
end

-- "0442.18" / "-0091.05" — the ambient coordinate readout format.
local function fmtCoord(v: number): string
	if v < 0 then
		return "-" .. string.format("%07.2f", -v)
	end
	return string.format("%07.2f", v)
end

local function keyStatTexts(p: Part): (string, string)
	local found: { string } = {}
	for _, key in ROW_STAT_KEYS do
		local v = p.stats[key.id]
		if v ~= nil then
			table.insert(found, key.tag .. " " .. fmtValue(v))
			if #found == 2 then
				break
			end
		end
	end
	return found[1] or "", found[2] or ""
end

-- RichText OFF on every label the boot scramble may touch: scramble frames
-- write arbitrary glyphs and must never be parsed as markup.
local function monoLabel(name: string, text: string, font: Font, size: number, color: Color3): TextLabel
	local label = UIStyler.TextLabel(name)
	label.RichText = false
	label.FontFace = font
	label.TextSize = size
	label.TextColor3 = color
	label.Text = text
	label.TextXAlignment = Enum.TextXAlignment.Left
	return label
end

-- Bracket framing law: "[" and "]" are SEPARATE TextSecondary labels around
-- the value label, never characters inside it.
local function bracketed(parent: Instance, theme: Types.UITheme, text: string): Frame
	local holder = UIStyler.Frame("Bracketed")
	holder.BackgroundTransparency = 1
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
	}).Parent = holder
	local open = monoLabel("Open", "[", theme.Fonts.Body, 14, theme.Colors.TextSecondary)
	open.AutomaticSize = Enum.AutomaticSize.X
	open.Size = UDim2.new(0, 0, 1, 0)
	open.LayoutOrder = 1
	open.Parent = holder
	local value = monoLabel("Value", text, theme.Fonts.Subtitle, 14, theme.Colors.TextPrimary)
	value.AutomaticSize = Enum.AutomaticSize.X
	value.Size = UDim2.new(0, 0, 1, 0)
	value.LayoutOrder = 2
	value.Parent = holder
	local close = monoLabel("Close", "]", theme.Fonts.Body, 14, theme.Colors.TextSecondary)
	close.AutomaticSize = Enum.AutomaticSize.X
	close.Size = UDim2.new(0, 0, 1, 0)
	close.LayoutOrder = 3
	close.Parent = holder
	holder.Parent = parent
	return holder
end

local function hairline(parent: Instance, color: Color3, transparency: number, size: UDim2, position: UDim2, rotation: number?): Frame
	local line = UIStyler.Frame("Hairline")
	line.BackgroundColor3 = color
	line.BackgroundTransparency = transparency
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Size = size
	line.Position = position
	line.Rotation = rotation or 0
	line.Parent = parent
	return line
end

local function wireBox(parent: Instance, theme: Types.UITheme, size: UDim2, position: UDim2): Frame
	local box = UIStyler.Frame("WireBox")
	box.BackgroundTransparency = 1
	box.AnchorPoint = Vector2.new(0.5, 0)
	box.Size = size
	box.Position = position
	UIChrome.Stroke(theme, "Arcade").Parent = box
	box.Parent = parent
	return box
end

-- Tag every worded label a component built for the boot scramble (numeric
-- value labels carry no letters and stay untouched).
local function tagScrambleLabels(root: Instance)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("TextLabel") and string.match(descendant.Text, "%a") then
			descendant:SetAttribute("BootScramble", true)
		end
	end
end

-- ---- screen --------------------------------------------------------------

function AssemblyScreen.new()
	local self = UIScreenBase.new("AssemblyScreen", 25)
	self._categories = demoCategories() :: { Category }
	self._loadout = defaultLoadout(self._categories)
	self._coam = 1240500
	self._selectedCat = 1
	self._catRows = {} :: { CatRow }
	self._partRows = {} :: { PartRow }
	self._rowParts = {} :: { [number]: Part }
	self._statRows = {} :: { [string]: any }
	self._components = {} :: { any }
	self._liveTotals = {} :: { [string]: number }
	self._hoverIndex = nil :: number?
	self._bannerActive = false
	self._confirmValid = true
	self._tickerStop = nil :: (() -> ())?
	self._bootCancel = nil :: (() -> ())?
	self._coordAccum = 0
	return setmetatable(self, AssemblyScreen)
end

function AssemblyScreen:_BuildContent()
	local theme = self:GetTheme()

	-- Opaque void: this is a full screen, not a modal over the world.
	local background = UIStyler.Frame("Background")
	background.BackgroundColor3 = theme.Colors.Background
	background.Size = UDim2.fromScale(1, 1)
	background.ZIndex = 1
	background.Parent = self.Root

	self:_BuildTopBar(theme)
	self:_BuildLeftColumn(theme)
	self:_BuildCenter(theme)
	self:_BuildSpecPanel(theme)
	self:_BuildBottomBar(theme)
end

-- ---- top bar -------------------------------------------------------------

function AssemblyScreen:_BuildTopBar(theme: Types.UITheme)
	local bar = UIStyler.Frame("TopBar")
	bar.BackgroundTransparency = 1
	bar.Position = UDim2.new(0, PAD, 0, 8)
	bar.Size = UDim2.new(1, -2 * PAD, 0, 52)
	bar.ZIndex = 2
	bar.Parent = self.Root

	local title = monoLabel("UnitName", "STEEL HAZE", theme.Fonts.Title, 20, theme.Colors.TextPrimary)
	title.Size = UDim2.new(0, 300, 1, 0)
	title:SetAttribute("BootScramble", true)
	UIChrome.TextOutline(title)
	title.Parent = bar
	self._unitLabel = title

	local header = bracketed(bar, theme, "ASSEMBLY")
	header.Position = UDim2.new(0, 320, 0, 10)
	header.Size = UDim2.new(0, 220, 0, 32)

	-- Funds, right-anchored: dim caption, then the flush-right mono amount.
	local caption = monoLabel("CoamCaption", "COAM", theme.Fonts.Body, 10, theme.Colors.TextSecondary)
	caption.AnchorPoint = Vector2.new(1, 0.5)
	caption.Position = UDim2.new(1, -186, 0.5, 0)
	caption.Size = UDim2.new(0, 60, 0, 14)
	caption.TextXAlignment = Enum.TextXAlignment.Right
	caption.Parent = bar

	local amount = monoLabel("CoamAmount", "1,240,500", theme.Fonts.Numeric, 16, theme.Colors.TextPrimary)
	amount.AnchorPoint = Vector2.new(1, 0.5)
	amount.Position = UDim2.new(1, 0, 0.5, 0)
	amount.Size = UDim2.new(0, 170, 0, 20)
	amount.TextXAlignment = Enum.TextXAlignment.Right
	amount.Parent = bar
	self._coamLabel = amount

	hairline(self.Root, theme.Colors.Accent, 0.6, UDim2.new(1, -2 * PAD, 0, 1), UDim2.new(0.5, 0, 0, 64))
end

-- ---- left column: categories + pooled part list --------------------------

function AssemblyScreen:_BuildLeftColumn(theme: Types.UITheme)
	local column = UIStyler.Frame("LeftColumn")
	column.BackgroundTransparency = 1
	column.Position = UDim2.new(0, PAD, 0, CONTENT_Y)
	column.Size = UDim2.new(0, LEFT_W, 1, -(CONTENT_Y + BOTTOM_RESERVE))
	column.ZIndex = 2
	column.Parent = self.Root
	self._leftColumn = column

	local catHeader = monoLabel("CatHeader", "CATEGORY", theme.Fonts.Body, 10, theme.Colors.TextSecondary)
	catHeader.Size = UDim2.new(1, 0, 0, HEADER_H)
	catHeader.Parent = column

	local catList = UIStyler.Frame("CategoryList")
	catList.BackgroundTransparency = 1
	catList.Position = UDim2.fromOffset(0, HEADER_H)
	catList.Size = UDim2.new(1, 0, 0, 11 * CAT_ROW_H)
	catList.Parent = column
	self._catList = catList

	local partHeader = monoLabel("PartHeader", "PART LIST", theme.Fonts.Body, 10, theme.Colors.TextSecondary)
	partHeader.Size = UDim2.new(1, 0, 0, HEADER_H)
	partHeader.Parent = column
	self._partHeader = partHeader

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "PartList"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 3
	scroll.ScrollBarImageColor3 = theme.Colors.Accent
	scroll.ScrollBarImageTransparency = 0.3
	scroll.CanvasSize = UDim2.new()
	-- The property is AutomaticCanvasSize but its VALUE type is AutomaticSize
	-- (there is no Enum.AutomaticCanvasSize).
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.Parent = column
	UIStyler.ListLayout({
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 2),
	}).Parent = scroll
	self._partScroll = scroll

	-- The pool: build the row instances ONCE; category switches only rebind.
	self:_EnsurePartRows(PART_ROW_POOL)
end

function AssemblyScreen:_EnsureCatRows(count: number)
	local theme = self:GetTheme()
	for i = #self._catRows + 1, count do
		local row = Instance.new("TextButton")
		row.Name = "Category" .. i
		row.AutoButtonColor = false
		row.BackgroundColor3 = theme.Colors.SurfaceRaised
		row.BackgroundTransparency = 1
		row.BorderSizePixel = 0
		row.Text = ""
		row.Position = UDim2.fromOffset(0, (i - 1) * CAT_ROW_H)
		row.Size = UDim2.new(1, 0, 0, CAT_ROW_H)
		row.Parent = self._catList

		local label = monoLabel("Name", "", theme.Fonts.Body, theme.TextSizes.Body, theme.Colors.TextSecondary)
		label.Position = UDim2.fromOffset(12, 0)
		label.Size = UDim2.new(1, -12, 1, 0)
		label:SetAttribute("BootScramble", true)
		label.Parent = row

		local tick = UIStyler.Frame("Tick")
		tick.BackgroundColor3 = theme.Colors.Accent
		tick.AnchorPoint = Vector2.new(0, 0.5)
		tick.Position = UDim2.new(0, 2, 0.5, 0)
		tick.Size = UDim2.fromOffset(3, 12)
		tick.Visible = false
		tick.Parent = row

		-- Discrete state snaps, no tweens: machines don't glide (theme law).
		row.MouseEnter:Connect(function()
			if self._selectedCat ~= i then
				row.BackgroundTransparency = 0.72
			end
		end)
		row.MouseLeave:Connect(function()
			row.BackgroundTransparency = if self._selectedCat == i then 0.82 else 1
		end)
		row.Activated:Connect(function()
			self:_SelectCategory(i)
		end)

		table.insert(self._catRows, { root = row, label = label, tick = tick })
	end
end

function AssemblyScreen:_EnsurePartRows(count: number)
	local theme = self:GetTheme()
	for i = #self._partRows + 1, count do
		local row = Instance.new("TextButton")
		row.Name = "Part" .. i
		row.AutoButtonColor = false
		row.BackgroundColor3 = theme.Colors.SurfaceRaised
		row.BackgroundTransparency = 0.55
		row.BorderSizePixel = 0
		row.Text = ""
		row.Size = UDim2.new(1, -8, 0, PART_ROW_H)
		row.LayoutOrder = i
		row.Visible = false
		row.Parent = self._partScroll

		-- Focus is a stroke, not a pop: Selection intent = opaque accent.
		local stroke = UIChrome.Stroke(theme, "Arcade", "Selection")
		stroke.Enabled = false
		stroke.Parent = row

		local name = monoLabel("PartName", "", theme.Fonts.Body, 13, theme.Colors.TextPrimary)
		name.Position = UDim2.fromOffset(10, 3)
		name.Size = UDim2.new(1, -210, 0, 18)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Parent = row

		local chip = monoLabel("EquippedChip", "EQUIPPED", theme.Fonts.Body, 10, theme.Colors.TextSecondary)
		chip.BackgroundTransparency = 0
		chip.BackgroundColor3 = theme.Colors.Surface
		chip.Position = UDim2.fromOffset(10, 25)
		chip.Size = UDim2.fromOffset(72, 14)
		chip.TextXAlignment = Enum.TextXAlignment.Center
		chip.Visible = false
		chip.Parent = row

		local s1 = monoLabel("Stat1", "", theme.Fonts.Numeric, 11, theme.Colors.TextSecondary)
		s1.AnchorPoint = Vector2.new(1, 0)
		s1.Position = UDim2.new(1, -104, 0, 0)
		s1.Size = UDim2.new(0, 88, 1, 0)
		s1.TextXAlignment = Enum.TextXAlignment.Right
		s1.Parent = row

		local s2 = monoLabel("Stat2", "", theme.Fonts.Numeric, 11, theme.Colors.TextSecondary)
		s2.AnchorPoint = Vector2.new(1, 0)
		s2.Position = UDim2.new(1, -10, 0, 0)
		s2.Size = UDim2.new(0, 88, 1, 0)
		s2.TextXAlignment = Enum.TextXAlignment.Right
		s2.Parent = row

		hairline(row, theme.Colors.Accent, 0.85, UDim2.new(1, -12, 0, 1), UDim2.new(0.5, 0, 1, 0))

		row.MouseEnter:Connect(function()
			self:_HoverRow(i)
		end)
		row.MouseLeave:Connect(function()
			self:_UnhoverRow(i)
		end)
		row.Activated:Connect(function()
			self:_EquipRow(i)
		end)

		table.insert(self._partRows, { root = row, name = name, s1 = s1, s2 = s2, chip = chip, stroke = stroke })
	end
end

-- ---- center: mech preview well -------------------------------------------

function AssemblyScreen:_BuildCenter(theme: Types.UITheme)
	local centerX = PAD + LEFT_W + COL_GAP
	local well = UIStyler.Frame("PreviewWell")
	well.BackgroundColor3 = theme.Colors.Surface
	well.BackgroundTransparency = 0.35
	well.Position = UDim2.new(0, centerX, 0, CONTENT_Y)
	well.Size = UDim2.new(1, -(centerX + COL_GAP + RIGHT_W + PAD), 1, -(CONTENT_Y + BOTTOM_RESERVE))
	well.ZIndex = 2
	well.Parent = self.Root
	self._well = well

	local ticks = UICornerTicksComponent.new()
	ticks:Create(well, {})
	table.insert(self._components, ticks)

	-- Wireframe stand-in built from hairlines. A REAL game parents a
	-- ViewportFrame + orbit camera here; the screen's layout contract (the
	-- well, callouts, coordinate line) is unchanged when that swap happens.
	local mech = UIStyler.Frame("Wireframe")
	mech.BackgroundTransparency = 1
	mech.AnchorPoint = Vector2.new(0.5, 0.5)
	mech.Position = UDim2.new(0.5, 0, 0.46, 0)
	mech.Size = UDim2.fromOffset(300, 540)
	mech.Parent = well

	wireBox(mech, theme, UDim2.fromOffset(48, 42), UDim2.new(0.5, 0, 0, 6))
	wireBox(mech, theme, UDim2.fromOffset(150, 178), UDim2.new(0.5, 0, 0, 58))
	local accent = theme.Colors.Accent
	hairline(mech, accent, 0.55, UDim2.fromOffset(244, 1), UDim2.new(0.5, 0, 0, 66))
	hairline(mech, accent, 0.55, UDim2.fromOffset(160, 1), UDim2.new(0.5, -108, 0, 168), 68)
	hairline(mech, accent, 0.55, UDim2.fromOffset(160, 1), UDim2.new(0.5, 108, 0, 168), -68)
	hairline(mech, accent, 0.55, UDim2.fromOffset(200, 1), UDim2.new(0.5, -58, 0, 352), 78)
	hairline(mech, accent, 0.55, UDim2.fromOffset(200, 1), UDim2.new(0.5, 58, 0, 352), -78)
	hairline(mech, accent, 0.55, UDim2.fromOffset(56, 1), UDim2.new(0.5, -84, 0, 448))
	hairline(mech, accent, 0.55, UDim2.fromOffset(56, 1), UDim2.new(0.5, 84, 0, 448))

	-- Slot callouts, positioned relative to the mech centre (0.5, 0.46) so
	-- they stay glued to the wireframe when the well flexes with the viewport.
	local function callout(text: string, labelDX: number, labelDY: number, lineDX: number, lineDY: number, lineLen: number, lineRot: number)
		local label = monoLabel("Callout" .. text, text, theme.Fonts.Body, 11, theme.Colors.TextSecondary)
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Position = UDim2.new(0.5, labelDX, 0.46, labelDY)
		label.Size = UDim2.fromOffset(0, 14)
		label.Parent = well
		hairline(well, theme.Colors.Accent, 0.5, UDim2.fromOffset(lineLen, 1), UDim2.new(0.5, lineDX, 0.46, lineDY), lineRot)
	end
	callout("HEAD", 166, -282, 94, -258, 130, 12)
	callout("CORE", 206, -108, 128, -104, 110, -4)
	callout("ARMS", -268, -103, -178, -88, 110, 8)
	callout("LEGS", -258, 178, -160, 176, 140, -12)

	-- Ambient coordinate readout; digits drift via the ONE shared ticker.
	local coords = monoLabel("Coords", "X: 0442.18  Y: -0091.05  Z: 0338.77", theme.Fonts.Numeric, 11, theme.Colors.TextSecondary)
	coords.AnchorPoint = Vector2.new(0.5, 1)
	coords.Position = UDim2.new(0.5, 0, 1, -12)
	coords.Size = UDim2.fromOffset(430, 14)
	coords.TextXAlignment = Enum.TextXAlignment.Center
	coords.Parent = well
	self._coordLabel = coords

	-- Over-limit banner: blinked DISCRETELY by the ticker, never faded.
	local banner = monoLabel("OverLimit", "OVER LIMIT — CANNOT SORTIE", theme.Fonts.Subtitle, 14, theme.Colors.Error)
	banner.AnchorPoint = Vector2.new(0.5, 1)
	banner.Position = UDim2.new(0.5, 0, 1, -34)
	banner.Size = UDim2.fromOffset(520, 20)
	banner.TextXAlignment = Enum.TextXAlignment.Center
	banner.Visible = false
	UIChrome.TextOutline(banner)
	banner.Parent = well
	self._banner = banner
end

-- ---- right column: SPEC panel --------------------------------------------

function AssemblyScreen:_BuildSpecPanel(theme: Types.UITheme)
	local panel = UINotchedPanelComponent.new()
	panel:Create(self.Root, {
		size = UDim2.new(0, RIGHT_W, 1, -(CONTENT_Y + BOTTOM_RESERVE)),
		position = UDim2.new(1, -PAD, 0, CONTENT_Y),
		anchorPoint = Vector2.new(1, 0),
	})
	table.insert(self._components, panel)
	local content = panel.Content
	UIStyler.PaddingXY(14, 12).Parent = content
	UIStyler.ListLayout({
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 6),
	}).Parent = content

	local specHeader = monoLabel("SpecHeader", "AC SPEC", theme.Fonts.Body, 10, theme.Colors.TextSecondary)
	specHeader.Size = UDim2.new(1, 0, 0, 14)
	specHeader.LayoutOrder = 0
	specHeader:SetAttribute("BootScramble", true)
	specHeader.Parent = content

	local apCaption = monoLabel("ApCaption", "AP", theme.Fonts.Body, 10, theme.Colors.TextSecondary)
	apCaption.Size = UDim2.new(1, 0, 0, 14)
	apCaption.LayoutOrder = 1
	apCaption:SetAttribute("BootScramble", true)
	apCaption.Parent = content

	local apBar = UISegmentedBarComponent.new()
	apBar:Create(content, {
		segments = 30,
		-- Bar contract: {at = ratio, colorToken = theme.Colors key}. The 25%
		-- band is the AP danger threshold (recolours the run + pulses).
		thresholds = { { at = 0.25, colorToken = "Error" } },
		chunkSize = 10,
		size = UDim2.new(1, 0, 0, 18),
		layoutOrder = 2,
	})
	table.insert(self._components, apBar)
	self._apBar = apBar

	local enCaption = monoLabel("EnCaption", "EN", theme.Fonts.Body, 10, theme.Colors.TextSecondary)
	enCaption.Size = UDim2.new(1, 0, 0, 14)
	enCaption.LayoutOrder = 3
	enCaption:SetAttribute("BootScramble", true)
	enCaption.Parent = content

	local enBar = UISegmentedBarComponent.new()
	enBar:Create(content, {
		segments = 20,
		chunkSize = 5,
		size = UDim2.new(1, 0, 0, 18),
		layoutOrder = 4,
	})
	table.insert(self._components, enBar)
	self._enBar = enBar

	for index, def in STAT_DEFS do
		local row = UIStatRowComponent.new()
		row:Create(content, {
			label = def.label,
			unit = def.unit,
			maxValue = def.max,
			invertGoodness = def.invert == true,
			value = 0,
			size = UDim2.new(1, 0, 0, STAT_ROW_H),
			layoutOrder = 10 + index,
		})
		tagScrambleLabels(row.Root)
		table.insert(self._components, row)
		self._statRows[def.id] = row
	end
end

-- ---- bottom bar -----------------------------------------------------------

function AssemblyScreen:_BuildBottomBar(theme: Types.UITheme)
	hairline(self.Root, theme.Colors.Accent, 0.6, UDim2.new(1, -2 * PAD, 0, 1), UDim2.new(0.5, 0, 1, -56))

	local bar = UIStyler.Frame("BottomBar")
	bar.BackgroundTransparency = 1
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.Position = UDim2.new(0, PAD, 1, -8)
	bar.Size = UDim2.new(1, -2 * PAD, 0, 44)
	bar.ZIndex = 2
	bar.Parent = self.Root

	local hints = monoLabel("Hints", "[TAB] CATEGORY   [CLICK] EQUIP   [ESC] EXIT", theme.Fonts.Body, 11, theme.Colors.TextSecondary)
	hints.Size = UDim2.new(0, 900, 1, 0)
	hints.Parent = bar

	-- Accent-stroked ghost. Dimmed while over limit, NEVER disabled: the tap
	-- still lands, plays its full press juice and then explains (house rule).
	local confirm = Instance.new("TextButton")
	confirm.Name = "Confirm"
	confirm.AutoButtonColor = false
	confirm.BackgroundColor3 = theme.Colors.Surface
	confirm.BackgroundTransparency = 1
	confirm.BorderSizePixel = 0
	confirm.AnchorPoint = Vector2.new(1, 0.5)
	confirm.Position = UDim2.new(1, 0, 0.5, 0)
	confirm.Size = UDim2.fromOffset(220, 30)
	confirm.Text = "SORTIE READY"
	confirm.FontFace = theme.Fonts.Button
	confirm.TextSize = theme.TextSizes.Button
	confirm.TextColor3 = theme.Colors.Accent
	confirm.RichText = false
	local stroke = UIChrome.Stroke(theme, "Arcade", "Selection")
	stroke.Parent = confirm
	UIChrome.TextOutline(confirm)
	confirm.Parent = bar
	confirm.Activated:Connect(function()
		self:_OnConfirm()
	end)
	UIChrome.Animate(theme, confirm) -- applied LAST, after final colours
	self._confirm = confirm
	self._confirmStroke = stroke
end

-- ---- data binding ---------------------------------------------------------

function AssemblyScreen:_ApplyData(d: any)
	if d.categories then
		self._categories = d.categories
		self._loadout = {}
		self._selectedCat = 1
	end
	if d.loadout then
		for categoryName, partId in d.loadout do
			self._loadout[categoryName] = partId
		end
	end
	-- Every category must resolve to an equipped part or the totals lie.
	for _, category in self._categories do
		if self._loadout[category.name] == nil and category.parts[1] then
			self._loadout[category.name] = category.parts[1].id
		end
	end
	if d.coam ~= nil then
		self._coam = d.coam
	end
end

function AssemblyScreen:_FillCategories()
	local count = #self._categories
	self:_EnsureCatRows(count)
	for i, row in self._catRows do
		local category = self._categories[i]
		if category then
			row.root.Visible = true
			row.label.Text = string.upper(category.name)
		else
			row.root.Visible = false
		end
	end
	-- Reflow the part-list block under however many categories exist.
	local listH = count * CAT_ROW_H
	self._catList.Size = UDim2.new(1, 0, 0, listH)
	local partY = HEADER_H + listH + 10
	self._partHeader.Position = UDim2.fromOffset(0, partY)
	local scrollY = partY + HEADER_H + 4
	self._partScroll.Position = UDim2.fromOffset(0, scrollY)
	self._partScroll.Size = UDim2.new(1, 0, 1, -scrollY)
end

function AssemblyScreen:_SelectCategory(index: number)
	local theme = self:GetTheme()
	if not self._categories[index] then
		return
	end
	self._selectedCat = index
	for i, row in self._catRows do
		local selected = i == index
		row.label.TextColor3 = if selected then theme.Colors.Accent else theme.Colors.TextSecondary
		row.tick.Visible = selected
		row.root.BackgroundTransparency = if selected then 0.82 else 1
	end
	self._hoverIndex = nil
	self:_FillPartList()
	self:_ClearPreview()
end

function AssemblyScreen:_FillPartList()
	local category = self._categories[self._selectedCat]
	local parts: { Part } = if category then category.parts else {}
	self:_EnsurePartRows(#parts)
	table.clear(self._rowParts)
	for i, row in self._partRows do
		local p = parts[i]
		if p then
			self._rowParts[i] = p
			row.root.Visible = true
			row.name.Text = string.upper(p.name)
			local s1, s2 = keyStatTexts(p)
			row.s1.Text = s1
			row.s2.Text = s2
		else
			row.root.Visible = false
		end
	end
	self:_RefreshRowChrome()
	self._partScroll.CanvasPosition = Vector2.new(0, 0)
end

function AssemblyScreen:_RefreshRowChrome()
	local category = self._categories[self._selectedCat]
	local equippedId = if category then self._loadout[category.name] else nil
	for i, row in self._partRows do
		local p = self._rowParts[i]
		if not p then
			continue
		end
		local hovered = self._hoverIndex == i
		local equipped = p.id == equippedId
		row.stroke.Enabled = hovered or equipped
		-- Hover reads opaque; the equipped part keeps a quieter persistent frame.
		row.stroke.Transparency = if hovered then 0 else 0.35
		row.chip.Visible = equipped
	end
end

-- ---- totals, previews, over-limit -----------------------------------------

function AssemblyScreen:_StatTotals(loadout: { [string]: string }): { [string]: number }
	local totals: { [string]: number } = {}
	for _, def in STAT_DEFS do
		totals[def.id] = 0
	end
	for _, category in self._categories do
		local equippedId = loadout[category.name]
		for _, p in category.parts do
			if p.id == equippedId then
				for statId, value in p.stats do
					if totals[statId] ~= nil then
						totals[statId] += value
					end
				end
				break
			end
		end
	end
	return totals
end

-- Paint the over-limit story for whichever totals are being LOOKED AT
-- (live, or the hover preview) — rows flip, banner arms, all discretely.
function AssemblyScreen:_SetOverDisplay(totals: { [string]: number })
	local overWeight = totals.WEIGHT > totals.LOAD_LIMIT
	local overEnergy = totals.EN_LOAD > totals.EN_OUTPUT
	self._statRows.WEIGHT:SetOverLimit(overWeight)
	self._statRows.EN_LOAD:SetOverLimit(overEnergy)
	self._bannerActive = overWeight or overEnergy
	self._banner.Visible = self._bannerActive
end

function AssemblyScreen:_RefreshConfirm()
	local theme = self:GetTheme()
	local totals = self._liveTotals
	self._confirmValid = totals.WEIGHT <= totals.LOAD_LIMIT and totals.EN_LOAD <= totals.EN_OUTPUT
	if self._confirmValid then
		self._confirm.Text = "SORTIE READY"
		self._confirm.TextColor3 = theme.Colors.Accent
		self._confirmStroke.Transparency = 0
	else
		self._confirm.Text = "CANNOT SORTIE"
		self._confirm.TextColor3 = theme.Colors.TextSecondary
		self._confirmStroke.Transparency = 0.55
	end
	-- Re-sync the glow to the new text colour (idempotent).
	UIChrome.TextOutline(self._confirm)
end

function AssemblyScreen:_ApplyLoadout()
	self._liveTotals = self:_StatTotals(self._loadout)
	local totals = self._liveTotals
	for _, def in STAT_DEFS do
		self._statRows[def.id]:SetValue(totals[def.id])
	end
	self._apBar:SetValue(totals.AP, AP_MAX)
	self._enBar:SetValue(totals.EN_LOAD, math.max(totals.EN_OUTPUT, 1))
	self:_SetOverDisplay(totals)
	self:_RefreshConfirm()
	self:_RefreshRowChrome()
end

function AssemblyScreen:_ClearPreview()
	for _, def in STAT_DEFS do
		self._statRows[def.id]:SetPreview(nil)
	end
	self:_SetOverDisplay(self._liveTotals)
end

function AssemblyScreen:_HoverRow(index: number)
	local p = self._rowParts[index]
	if not p then
		return
	end
	self._hoverIndex = index
	self:_RefreshRowChrome()
	local category = self._categories[self._selectedCat]
	if not category then
		return
	end
	-- Ghost the candidate: preview totals with this part swapped in, pushed
	-- only to the rows it actually moves.
	local override = table.clone(self._loadout)
	override[category.name] = p.id
	local preview = self:_StatTotals(override)
	for _, def in STAT_DEFS do
		local row = self._statRows[def.id]
		if preview[def.id] ~= self._liveTotals[def.id] then
			row:SetPreview(preview[def.id])
		else
			row:SetPreview(nil)
		end
	end
	self:_SetOverDisplay(preview)
end

function AssemblyScreen:_UnhoverRow(index: number)
	if self._hoverIndex ~= index then
		return
	end
	self._hoverIndex = nil
	self:_RefreshRowChrome()
	self:_ClearPreview()
end

function AssemblyScreen:_EquipRow(index: number)
	local p = self._rowParts[index]
	local category = self._categories[self._selectedCat]
	if not p or not category then
		return
	end
	self._loadout[category.name] = p.id
	self:_PlaySound("Click")
	-- Values re-render discretely in place; zero instance churn on equip.
	self:_ApplyLoadout()
	self:_ClearPreview()
	local row = self._partRows[index]
	if row then
		UIChrome.Pulse(self:GetTheme(), row.root)
	end
end

-- ---- confirm ---------------------------------------------------------------

function AssemblyScreen:_Toast(text: string, variant: string)
	local hud = self.ScreenController and self.ScreenController:GetScreen("hud")
	if hud then
		hud:PushToast({ text = text, variant = variant })
	end
end

function AssemblyScreen:_OnConfirm()
	if not self._confirmValid then
		local totals = self._liveTotals
		local reason = if totals.WEIGHT > totals.LOAD_LIMIT
			then "OVER LIMIT: WEIGHT EXCEEDS LOAD LIMIT"
			else "OVER LIMIT: EN LOAD EXCEEDS EN OUTPUT"
		self:_PlaySound("Error")
		self:_Toast(reason, "Error")
		return
	end
	self:_PlaySound("Success")
	UIChrome.Pulse(self:GetTheme(), self._confirm)
	self:_Toast("LOADOUT CONFIRMED — SORTIE READY", "Success")
end

-- ---- lifecycle --------------------------------------------------------------

function AssemblyScreen:_OnShow(data: any?)
	self:_ApplyData(data or {})
	self._coamLabel.Text = commas(self._coam)
	self:_FillCategories()
	self:_ApplyLoadout()
	self:_SelectCategory(math.clamp(self._selectedCat, 1, math.max(#self._categories, 1)))

	-- Boot flicker re-runs on every show; the previous pass is cancelled
	-- first so a fast reopen never stacks two scrambles.
	if self._bootCancel then
		self._bootCancel()
	end
	self._bootCancel = BootSequence.play(self.Root, { scramble = true })

	-- THE one ambient handler for the whole screen.
	if self._tickerStop then
		self._tickerStop()
	end
	self._coordAccum = 0
	self._tickerStop = UITicker.Register(function(dt: number, now: number)
		if not UIChrome.IsOnScreen(self._well) then
			return
		end
		self._coordAccum += dt
		if self._coordAccum >= 0.1 then
			-- 10Hz stepped update: the digits TICK, they don't glide.
			self._coordAccum = 0
			local x = 442.18 + math.sin(now * 0.7) * 3.4
			local y = -91.05 + math.cos(now * 0.53) * 2.2
			local z = 338.77 + math.sin(now * 0.31 + 1.7) * 4.1
			self._coordLabel.Text = string.format("X: %s  Y: %s  Z: %s", fmtCoord(x), fmtCoord(y), fmtCoord(z))
		end
		if self._bannerActive then
			-- Discrete blink, not a fade — AC state changes snap.
			self._banner.Visible = (now * 2) % 1 < 0.65
		end
	end, self.Root)
end

function AssemblyScreen:_OnHide()
	if self._bootCancel then
		self._bootCancel()
		self._bootCancel = nil
	end
	if self._tickerStop then
		self._tickerStop()
		self._tickerStop = nil
	end
end

function AssemblyScreen:Update(data: any)
	if not data or not self._built then
		return
	end
	self:_ApplyData(data)
	self._coamLabel.Text = commas(self._coam)
	self:_FillCategories()
	self:_ApplyLoadout()
	self:_SelectCategory(math.clamp(self._selectedCat, 1, math.max(#self._categories, 1)))
end

function AssemblyScreen:Destroy()
	self:_OnHide()
	for _, component in self._components do
		component:Destroy()
	end
	table.clear(self._components)
	UIScreenBase.Destroy(self)
end

-- Style rebuilds (UIScreenBase:_ResetShell) destroy the Gui for us; this hook
-- just releases the pooled state that would otherwise point at dead rows.
function AssemblyScreen:_OnTeardown()
	self:_OnHide()
	for _, component in self._components do
		component:Destroy()
	end
	table.clear(self._components)
	table.clear(self._catRows)
	table.clear(self._partRows)
	table.clear(self._rowParts)
	table.clear(self._statRows)
	self._hoverIndex = nil
	self._bannerActive = false
end

return AssemblyScreen
