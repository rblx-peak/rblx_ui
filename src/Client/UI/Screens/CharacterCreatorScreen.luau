--!strict
-- CHARACTER CREATOR — full-screen class + name + look picker, Pottery Clash
-- arcade family (manifest: hidesHUD — a focused moment, doc §11.5).
--
-- Three columns over a light scrim: LEFT is the class select (one card per
-- class: icon, name, two-line blurb, three PWR/SPD/DEF mini-rulers in the §8
-- ruler colours; the picked card wears the gold selection ring — §4.3
-- selection-is-a-ring, backgrounds never change). CENTRE is a near-black
-- preview well with the house sunburst (white @ 0.7 behind previews, doc §10)
-- and the class icon at 160px standing in for the character. RIGHT is the
-- name entry (uppercase-as-typed), a row of four "look" swatches wearing the
-- studio cream-ring selection (§4.3 glaze-swatch grammar: 0.8 → 0), and a
-- RANDOMIZE dice button. Footer: StudioBack out, green CONFIRM that dims in
-- place until a class is picked AND a name is typed — a dimmed tap still
-- plays full juice and toasts the reason (§11.1 every tap answers).
--
-- Show(data) = { classes, presets, onConfirm = function(classId, name, presetId) }.
-- Fixed px at the 1650×1020 baseline (UIScreenBase attaches the UIScale).

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIAssets = require(script.Parent.Parent.Config.UIAssets)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local GPControlKit = require(script.Parent.Parent.Framework.GPControlKit)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UIScreenBase = require(script.Parent.UIScreenBase)

type ClassStats = { pwr: number, spd: number, def: number }
type ClassEntry = {
	id: string,
	name: string,
	blurb: string,
	icon: string?,
	stats: ClassStats?,
}
type Preset = { id: string, name: string, color: Color3 }

local WHITE = Color3.new(1, 1, 1)

local MARGIN = 48
local TOP_Y = 104
local COL_W = 380
local CARD_H = 150
local CARD_GAP = 12
local WELL_W, WELL_H = 560, 700
local FIELD_H = 64
local SWATCH = 76
local SWATCH_GAP = 14
local STAT_MAX = 10
local NAME_MAX = 20

-- The playable archetypes. RANGER carries the target icon (the archive ships
-- no bow) — the crosshair reads "hits from range" cleanly.
local DEMO_CLASSES: { ClassEntry } = {
	{
		id = "warrior",
		name = "WARRIOR",
		icon = "sword",
		blurb = "Front-line bruiser. Slow, loud, and very hard to move.",
		stats = { pwr = 8, spd = 4, def = 7 },
	},
	{
		id = "ranger",
		name = "RANGER",
		icon = "target",
		blurb = "Fleet skirmisher who wins from range and never stops moving.",
		stats = { pwr = 6, spd = 9, def = 3 },
	},
	{
		id = "mage",
		name = "MAGE",
		icon = "potion",
		blurb = "Volatile brew-slinger. Enormous damage, paper-thin defence.",
		stats = { pwr = 9, spd = 6, def = 2 },
	},
	{
		id = "builder",
		name = "BUILDER",
		icon = "hammer",
		blurb = "Turns rubble into ramparts and outlasts everyone behind them.",
		stats = { pwr = 4, spd = 5, def = 9 },
	},
}

-- Look swatch colours are DATA (glaze tints), not chrome — they deliberately
-- match no theme token.
local DEMO_PRESETS: { Preset } = {
	{ id = "clay", name = "RAW CLAY", color = Color3.fromRGB(203, 120, 88) },
	{ id = "ash", name = "ASH GLAZE", color = Color3.fromRGB(126, 132, 142) },
	{ id = "cobalt", name = "COBALT DIP", color = Color3.fromRGB(86, 120, 210) },
	{ id = "moss", name = "MOSS CRACKLE", color = Color3.fromRGB(120, 158, 96) },
}

local RANDOM_NAMES = {
	"KILNBORN", "EMBERWISP", "SLIPCASTER", "GLAZERUNNER", "MUDDANCER",
	"SHARDLING", "WHEELTURNER", "BISQUEBACK", "COILWRAITH", "FIREFLUX",
}

local function trim(s: string): string
	return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

-- GP (Girly Pop). The class blurbs, the stat captions and the hero name are all
-- authored in arcade caps; pack law 5 forbids all-caps copy, so GP title-cases
-- on the way to the screen. Idempotent, which matters: the name field
-- re-normalises its own text on every keystroke.
local function gpTitle(text: string): string
	return (string.gsub(string.lower(text), "(%a[%w']*)", function(word: string)
		return string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2)
	end))
end

-- The GP stat ruler pitch. The arcade card prints three bars with no numerals;
-- this one prints the numeral TOO, in the same 18px pitch — denser, not softer.
local GP_STAT_PITCH = 18
local GP_STAT_CAP_W = 40
local GP_STAT_NUM_W = 34
local GP_STAT_BAR_H = 8

local CharacterCreatorScreen = setmetatable({}, { __index = UIScreenBase })
CharacterCreatorScreen.__index = CharacterCreatorScreen

function CharacterCreatorScreen.new()
	local self = UIScreenBase.new("CharacterCreatorScreen", 30)
	self._classes = DEMO_CLASSES :: { ClassEntry }
	self._presets = DEMO_PRESETS :: { Preset }
	self._onConfirm = nil :: ((string, string, string) -> ())?
	self._selectedClass = nil :: string?
	self._selectedPreset = DEMO_PRESETS[1].id
	-- Class-card + swatch records so selection restyles in place (no rebuild).
	self._classCards = {} :: { { id: string, surface: Frame, stroke: UIStroke } }
	self._swatches = {} :: { { id: string, button: TextButton, stroke: UIStroke } }
	self._burstSpin = nil :: RBXScriptConnection?
	-- GP branch state: the flag the shared render methods read, plus three
	-- independent shadow sinks (page chrome, class cards, glaze swatches) —
	-- independent because the column and the row rebuild separately, and
	-- releasing a live shadow's handle would undercount the budget.
	self._gp = false
	self._gpShadows = nil :: { any }?
	self._gpCardShadows = nil :: { any }?
	self._gpSwatchShadows = nil :: { any }?
	return setmetatable(self, CharacterCreatorScreen)
end

function CharacterCreatorScreen:_Toast(text: string, variant: string)
	local hud = self.ScreenController and self.ScreenController:GetScreen("hud")
	if hud then
		hud:PushToast({ text = text, variant = variant })
	end
end

function CharacterCreatorScreen:_Ingest(data: any)
	if type(data) ~= "table" then
		return
	end
	if type(data.classes) == "table" and #data.classes > 0 then
		self._classes = data.classes
		self._selectedClass = nil
	end
	if type(data.presets) == "table" and #data.presets > 0 then
		self._presets = data.presets
		self._selectedPreset = data.presets[1].id
	end
	if type(data.onConfirm) == "function" then
		self._onConfirm = data.onConfirm
	end
end

function CharacterCreatorScreen:_ClassById(id: string?): ClassEntry?
	for _, entry in self._classes :: { ClassEntry } do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

function CharacterCreatorScreen:_PresetById(id: string?): Preset?
	for _, preset in self._presets :: { Preset } do
		if preset.id == id then
			return preset
		end
	end
	return nil
end

-- ========================================================================
-- Build
-- ========================================================================

-- ========================================================================
-- GIRLY POP
-- ========================================================================
-- The same three columns at the same widths: class select on the left (icon,
-- name, blurb and all three PWR/SPD/DEF rulers — with the numerals printed,
-- which the arcade card does not do), the preview well in the centre, and name
-- + look + randomize on the right, over the same footer pair.
--
-- ONE DELIBERATE DIFFERENCE from the arcade build: the scrim is a nearly opaque
-- CREAM SHEET rather than a translucent near-black one. Ink on pastel needs a
-- stable ground, and a see-through scrim would put warm plum type over whatever
-- colour the world happens to be behind it. The world still glows faintly.
--
-- Controls come from GPControlKit: UIChrome.Stroke resolves to BLACK under this
-- pack's Chrome policy and UIStyleEnforcer backstops solid buttons with a black
-- rim, both of which break pack law 1. The kit's Button carries the same
-- SetContent/Destroy contract, so _RefreshConfirm and Destroy are untouched.

function CharacterCreatorScreen:_BuildGPLayout()
	local theme = self:GetTheme()
	local root = self.Root
	self._gpShadows = {}
	self._gpCardShadows = {}

	local paper = theme.Colors.Background
	local scrim = UIStyler.Frame("Scrim")
	scrim.BackgroundColor3 = paper
	scrim.BackgroundTransparency = 0.06
	scrim.ZIndex = 1
	scrim.Parent = root

	local studio = ((theme :: any).DialectTokens and (theme :: any).DialectTokens.studio) or {}
	local grain = GPLayoutKit.Tile(
		theme,
		studio.patternKey or "speckle",
		GPLayoutKit.Deepen(theme, paper, 1),
		studio.speckleTransparency or 0.94,
		"ClayGrain"
	)
	grain.ZIndex = 2
	grain.Parent = scrim

	local title = GPLayoutKit.Text(theme, 46, theme.Colors.TextPrimary, "Title")
	title.Text = "Create your potter"
	title.Position = UDim2.fromOffset(0, 24)
	title.Size = UDim2.new(1, 0, 0, 56)
	title.ZIndex = 5
	title.Parent = root

	self:_BuildGPClassColumn(theme, root)
	self:_BuildGPPreview(theme, root)
	self:_BuildGPRightColumn(theme, root)

	self._backBtn = GPControlKit.Button(theme, root, {
		text = "Back",
		fill = theme.Arcade.Orange,
		index = 1,
		size = UDim2.fromOffset(170, 52),
		position = UDim2.new(0, MARGIN, 1, -36),
		anchorPoint = Vector2.new(0, 1),
		zIndex = 5,
		sink = self._gpShadows,
		onClick = function()
			self.ScreenController:HideScreen("characterCreator")
		end,
	})

	self._confirmBtn = GPControlKit.Button(theme, root, {
		text = "Confirm",
		fill = theme.Colors.Secondary,
		dimmed = true,
		textSize = theme.TextSizes.Subtitle,
		size = UDim2.fromOffset(300, 64),
		position = UDim2.new(1, -MARGIN, 1, -32),
		anchorPoint = Vector2.new(1, 1),
		zIndex = 5,
		sink = self._gpShadows,
		onClick = function()
			self:_Confirm()
		end,
	})

	local footHint = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "FootHint")
	footHint.Text = "You can change your look later — your class is forever."
	footHint.AnchorPoint = Vector2.new(0.5, 1)
	footHint.Position = UDim2.new(0.5, 0, 1, -44)
	footHint.Size = UDim2.fromOffset(600, 22)
	footHint.ZIndex = 5
	footHint.Parent = root

	self:_RenderClasses()
	self:_RenderPresets()
	self:_RefreshPreview()
	self:_RefreshConfirm()
end

function CharacterCreatorScreen:_BuildGPClassColumn(theme: Types.UITheme, root: Frame)
	local header = GPLayoutKit.SectionLabel(theme, root, "Class")
	header.Position = UDim2.fromOffset(MARGIN, TOP_Y)
	header.Size = UDim2.fromOffset(COL_W, 28)
	header.ZIndex = 5

	local list = UIStyler.Frame("ClassList")
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(MARGIN, TOP_Y + 38)
	list.Size = UDim2.fromOffset(COL_W, (CARD_H + CARD_GAP) * 4)
	list.ZIndex = 5
	UIStyler.ListLayout({
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, CARD_GAP),
	}).Parent = list
	list.Parent = root
	self._classList = list
end

-- One class card: petal plate, hue-matched shade, and the full stat ladder.
function CharacterCreatorScreen:_BuildGPClassCard(theme: Types.UITheme, entry: ClassEntry, index: number)
	local selected = entry.id == self._selectedClass

	local card = UIStyler.Frame("Class_" .. entry.id)
	card.BackgroundTransparency = 1
	card.Size = UDim2.fromOffset(COL_W, CARD_H)
	card.LayoutOrder = index
	card.Parent = self._classList

	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 1
	hit.Parent = card

	local fill = theme.Colors.SurfaceRaised
	local surface = UIStyler.Frame("Surface")
	surface.BackgroundColor3 = fill
	surface.AnchorPoint = Vector2.new(0.5, 0.5)
	surface.Position = UDim2.fromScale(0.5, 0.5)
	surface.Size = UDim2.fromScale(1, 1)
	surface.ZIndex = 2
	surface.Parent = card
	GPLayoutKit.Petal(theme, surface, index)
	local stroke = GPLayoutKit.SoftStroke(theme, surface, fill)
	if selected then
		stroke.Color = GPLayoutKit.Deepen(theme, theme.Semantic.Selection, 1)
		stroke.Thickness = 3
		stroke.Transparency = 0
	end
	GPLayoutKit.Shadow(theme, surface, "sm", self._gpCardShadows, fill)

	-- Through the kit wrapper: IconArchive's GLYPH FALLBACK is born pure white
	-- with a pure black outline, which pack law 1 forbids.
	local icon = GPControlKit.Icon(theme, surface, entry.icon or "sword", 54)
	icon.Position = UDim2.fromOffset(16, 14)
	icon.ZIndex = 3

	local name = GPLayoutKit.Text(theme, 24, theme.Colors.TextPrimary, "Name")
	name.Text = gpTitle(entry.name)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(84, 12)
	name.Size = UDim2.fromOffset(COL_W - 100, 28)
	name.ZIndex = 3
	name.Parent = surface

	local blurb = GPLayoutKit.BodyText(theme, 14, theme.Colors.TextSecondary, "Blurb")
	blurb.Text = entry.blurb
	blurb.TextXAlignment = Enum.TextXAlignment.Left
	blurb.TextYAlignment = Enum.TextYAlignment.Top
	blurb.TextWrapped = true
	blurb.Position = UDim2.fromOffset(84, 44)
	blurb.Size = UDim2.fromOffset(COL_W - 100, 40)
	blurb.ZIndex = 3
	blurb.Parent = surface

	local stats = entry.stats or { pwr = 5, spd = 5, def = 5 }
	self:_BuildGPStatRuler(theme, surface, "Pwr", stats.pwr, 96)
	self:_BuildGPStatRuler(theme, surface, "Spd", stats.spd, 114)
	self:_BuildGPStatRuler(theme, surface, "Def", stats.def, 132)

	table.insert(self._classCards, { id = entry.id, surface = surface, stroke = stroke })

	hit.Activated:Connect(function()
		self:_SelectClass(entry.id)
	end)
	-- Animate LAST, after final colours (it snapshots the rest colour).
	UIChrome.Animate(theme, hit, surface)
end

-- Caption, PRINTED value and bar. The arcade card shows the bar alone; a bar
-- alone is a vibe, not a number, and this pack is not allowed to be vaguer.
function CharacterCreatorScreen:_BuildGPStatRuler(theme: Types.UITheme, parent: Frame, label: string, value: number, y: number)
	local caption = GPLayoutKit.BodyText(theme, 13, theme.Colors.TextSecondary, "Stat" .. label)
	caption.Text = label
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.Position = UDim2.fromOffset(16, y - 4)
	caption.Size = UDim2.fromOffset(GP_STAT_CAP_W, GP_STAT_PITCH)
	caption.ZIndex = 3
	caption.Parent = parent

	local numeral = GPLayoutKit.NumberText(theme, 13, theme.Colors.TextPrimary, "Num" .. label)
	numeral.Text = string.format("%d", value)
	numeral.Position = UDim2.fromOffset(16 + GP_STAT_CAP_W, y - 4)
	numeral.Size = UDim2.fromOffset(GP_STAT_NUM_W, GP_STAT_PITCH)
	numeral.ZIndex = 3
	numeral.Parent = parent

	local barX = 16 + GP_STAT_CAP_W + GP_STAT_NUM_W + 8
	local trackW = COL_W - barX - 16
	local track = UIStyler.Frame("Track" .. label)
	track.BackgroundColor3 = theme.Arcade.RulerTrack
	track.Position = UDim2.fromOffset(barX, y)
	track.Size = UDim2.fromOffset(trackW, GP_STAT_BAR_H)
	track.ZIndex = 3
	track.Parent = parent
	UIStyler.Corner(theme.Radii.Pill).Parent = track

	local frac = math.clamp(value / STAT_MAX, 0, 1)
	local fill = UIStyler.Frame("Fill")
	fill.BackgroundColor3 = theme.Arcade.Gold
	fill.Size = UDim2.fromOffset(math.floor(trackW * frac + 0.5), GP_STAT_BAR_H)
	fill.ZIndex = 4
	fill.Parent = track
	UIStyler.Corner(theme.Radii.Pill).Parent = fill
end

function CharacterCreatorScreen:_BuildGPPreview(theme: Types.UITheme, root: Frame)
	local wellFill = theme.Colors.Surface
	local well = UIStyler.Frame("PreviewWell")
	well.BackgroundColor3 = wellFill
	well.AnchorPoint = Vector2.new(0.5, 0)
	well.Position = UDim2.new(0.5, 0, 0, TOP_Y)
	well.Size = UDim2.fromOffset(WELL_W, WELL_H)
	well.ClipsDescendants = true
	well.ZIndex = 3
	well.Parent = root
	GPLayoutKit.CornerSet(theme, well, "Petal")
	GPLayoutKit.SoftStroke(theme, well, wellFill)
	GPLayoutKit.Shadow(theme, well, "lg", self._gpShadows, wellFill)
	self._well = well

	local artSlot = UIStyler.Frame("ArtSlot")
	artSlot.BackgroundTransparency = 1
	artSlot.AnchorPoint = Vector2.new(0.5, 0)
	artSlot.Position = UDim2.new(0.5, 0, 0, 110)
	artSlot.Size = UDim2.fromOffset(360, 360)
	artSlot.ZIndex = 4
	artSlot.Parent = well

	-- The house glow behind every preview, in the pack's own soft art and in
	-- rose rather than white (pure white is forbidden). Sized to stay INSIDE
	-- the slot: ClipsDescendants does not clip a rotated descendant, so the
	-- spin must not need clipping in the first place.
	local burst = GPLayoutKit.Slice(theme, "sunburstSoft", theme.Colors.Primary, "Sunburst")
	burst.ImageTransparency = 0.62
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.Position = UDim2.fromScale(0.5, 0.5)
	burst.Size = UDim2.fromScale(1, 1)
	burst.ZIndex = 4
	burst.Parent = artSlot
	self._burst = burst
	self._burstSpin = UIChrome.Spin(burst, 45)

	-- STAND-IN: a real game replaces this icon slot with a ViewportFrame
	-- carrying a HumanoidDescription preview (doc §10 viewport recipe).
	local iconSlot = UIStyler.Frame("IconSlot")
	iconSlot.BackgroundTransparency = 1
	iconSlot.AnchorPoint = Vector2.new(0.5, 0.5)
	iconSlot.Position = UDim2.fromScale(0.5, 0.5)
	iconSlot.Size = UDim2.fromOffset(200, 200)
	iconSlot.ZIndex = 5
	iconSlot.Parent = artSlot
	self._previewIconSlot = iconSlot

	local previewName = GPLayoutKit.Text(theme, 32, theme.Colors.TextPrimary, "PreviewName")
	previewName.Text = ""
	previewName.Position = UDim2.fromOffset(20, 506)
	previewName.Size = UDim2.fromOffset(WELL_W - 40, 40)
	previewName.ZIndex = 4
	previewName.Parent = well
	self._previewName = previewName

	local previewBlurb = GPLayoutKit.BodyText(theme, 15, theme.Colors.TextSecondary, "PreviewBlurb")
	previewBlurb.Text = ""
	previewBlurb.TextWrapped = true
	previewBlurb.Position = UDim2.fromOffset(40, 554)
	previewBlurb.Size = UDim2.fromOffset(WELL_W - 80, 60)
	previewBlurb.ZIndex = 4
	previewBlurb.Parent = well
	self._previewBlurb = previewBlurb

	local rule = GPLayoutKit.Divider(theme, well)
	rule.Position = UDim2.fromOffset(20, 618)
	rule.Size = UDim2.new(0, WELL_W - 40, 0, rule.Size.Y.Offset)
	rule.ZIndex = 4

	local lookLine = GPLayoutKit.BodyText(theme, 16, theme.Colors.TextPrimary, "PreviewLook")
	lookLine.Text = ""
	lookLine.TextXAlignment = Enum.TextXAlignment.Left
	lookLine.Position = UDim2.fromOffset(20, 636)
	lookLine.Size = UDim2.fromOffset(WELL_W - 40, 24)
	lookLine.ZIndex = 4
	lookLine.Parent = well
	self._previewLook = lookLine
end

function CharacterCreatorScreen:_BuildGPRightColumn(theme: Types.UITheme, root: Frame)
	local x = UIChrome.BASE_WIDTH - MARGIN - COL_W

	local nameHeader = GPLayoutKit.SectionLabel(theme, root, "Name")
	nameHeader.Position = UDim2.fromOffset(x, TOP_Y)
	nameHeader.Size = UDim2.fromOffset(COL_W, 28)
	nameHeader.ZIndex = 5

	local field = GPControlKit.Field(theme, root, {
		placeholder = "Your potter's name",
		iconKey = "edit",
		textSize = 24,
		size = UDim2.fromOffset(COL_W, FIELD_H),
		position = UDim2.fromOffset(x, TOP_Y + 38),
		zIndex = 5,
	})
	local box = field.box
	box.FontFace = theme.Fonts.Title
	self._nameBox = box

	-- Title-cased as typed (the arcade field shouts; this one does not), capped
	-- at NAME_MAX. gpTitle is idempotent, so re-assigning settles in one pass
	-- and an identical string never re-fires the signal.
	box:GetPropertyChangedSignal("Text"):Connect(function()
		local cased = gpTitle(box.Text)
		if #cased > NAME_MAX then
			cased = string.sub(cased, 1, NAME_MAX)
		end
		if box.Text ~= cased then
			box.Text = cased
		end
		self:_RefreshConfirm()
	end)

	-- The display name is UNTRUSTED INPUT: a real game must round-trip it
	-- through TextService:FilterStringAsync on the SERVER before any other
	-- player ever sees it. This screen only collects it.
	local filterNote = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "FilterNote")
	filterNote.Text = "Names are filtered before other potters see them."
	filterNote.TextXAlignment = Enum.TextXAlignment.Left
	filterNote.Position = UDim2.fromOffset(x, TOP_Y + 38 + FIELD_H + 8)
	filterNote.Size = UDim2.fromOffset(COL_W, 18)
	filterNote.ZIndex = 5
	filterNote.Parent = root

	local lookHeader = GPLayoutKit.SectionLabel(theme, root, "Glaze")
	lookHeader.Position = UDim2.fromOffset(x, TOP_Y + 156)
	lookHeader.Size = UDim2.fromOffset(COL_W, 28)
	lookHeader.ZIndex = 5

	local swatchRow = UIStyler.Frame("SwatchRow")
	swatchRow.BackgroundTransparency = 1
	swatchRow.Position = UDim2.fromOffset(x, TOP_Y + 194)
	swatchRow.Size = UDim2.fromOffset(COL_W, SWATCH)
	swatchRow.ZIndex = 5
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, SWATCH_GAP),
	}).Parent = swatchRow
	swatchRow.Parent = root
	self._swatchRow = swatchRow

	local lookName = GPLayoutKit.BodyText(theme, 18, theme.Colors.TextPrimary, "LookName")
	lookName.Text = ""
	lookName.TextXAlignment = Enum.TextXAlignment.Left
	lookName.Position = UDim2.fromOffset(x, TOP_Y + 194 + SWATCH + 10)
	lookName.Size = UDim2.fromOffset(COL_W, 24)
	lookName.ZIndex = 5
	lookName.Parent = root
	self._lookName = lookName

	self._randomBtn = GPControlKit.Button(theme, root, {
		text = "Surprise me",
		fill = theme.Arcade.Blue,
		iconKey = "dice",
		size = UDim2.fromOffset(COL_W, 52),
		position = UDim2.fromOffset(x, TOP_Y + 194 + SWATCH + 48),
		zIndex = 5,
		sink = self._gpShadows,
		onClick = function()
			self:_Randomize()
		end,
	})
end

-- Glaze swatches: the preset colour is DATA, so the chip keeps it verbatim and
-- only the ring is themed. Rest is the pack's half-opacity rim; selected snaps
-- solid — which is exactly what _SelectPreset already toggles, so that method
-- needs no branch.
function CharacterCreatorScreen:_RenderGPPresets()
	local theme = self:GetTheme()
	table.clear(self._swatches)
	-- Its OWN sink: the class column is rebuilt independently of this row, and
	-- releasing a live shadow's handle would undercount the budget.
	GPLayoutKit.ReleaseShadows(self._gpSwatchShadows)
	self._gpSwatchShadows = self._gpSwatchShadows or {}
	for _, child in self._swatchRow:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for index, preset in self._presets :: { Preset } do
		local selected = preset.id == self._selectedPreset

		-- Transparent button + painted chip child: a SOLID GuiButton would be
		-- given a black rim by UIStyleEnforcer (pack law 1).
		local hit = Instance.new("TextButton")
		hit.Name = "Swatch_" .. preset.id
		hit.Text = ""
		hit.AutoButtonColor = false
		hit.BackgroundTransparency = 1
		hit.Size = UDim2.fromOffset(SWATCH, SWATCH)
		hit.LayoutOrder = index
		hit.ZIndex = 5
		hit.Parent = self._swatchRow

		local chip = UIStyler.Frame("Chip")
		chip.BackgroundColor3 = preset.color
		chip.Size = UDim2.fromScale(1, 1)
		chip.ZIndex = 5
		chip.Parent = hit
		GPLayoutKit.Petal(theme, chip, index)
		local stroke = GPLayoutKit.SoftStroke(theme, chip, preset.color)
		stroke.Transparency = if selected then 0 else ((theme.Chrome and theme.Chrome.StrokeTransparency) or 0.35)
		GPLayoutKit.Shadow(theme, chip, "sm", self._gpSwatchShadows, preset.color)

		table.insert(self._swatches, { id = preset.id, button = hit, stroke = stroke })
		hit.Activated:Connect(function()
			self:_SelectPreset(preset.id)
		end)
		UIChrome.Animate(theme, hit, chip)
	end
	local active = self:_PresetById(self._selectedPreset)
	self._lookName.Text = if active then gpTitle(active.name) else ""
end

function CharacterCreatorScreen:_BuildContent()
	-- GP layout language: the studio sheet.
	if self:LayoutKit() == "GP" then
		self._gp = true
		self:_BuildGPLayout()
		return
	end
	self._gp = false

	local theme = self:GetTheme()
	local root = self.Root

	-- Light scrim, not the full modal dim: the creator owns the screen
	-- (hidesHUD) but the world should still glow through behind the well.
	local scrim = UIStyler.Frame("Scrim")
	scrim.BackgroundColor3 = theme.Arcade.NearBlack
	scrim.BackgroundTransparency = 0.25
	scrim.ZIndex = 1
	scrim.Parent = root

	local title = UIChrome.Text("Title", 46, theme.Arcade.Gold)
	title.Text = "CREATE YOUR HERO"
	title.Position = UDim2.fromOffset(0, 24)
	title.Size = UDim2.new(1, 0, 0, 56)
	title.ZIndex = 5
	title.Parent = root

	self:_BuildClassColumn(theme, root)
	self:_BuildPreview(theme, root)
	self:_BuildRightColumn(theme, root)

	self._backBtn = UIButtonComponent.new()
	self._backBtn:Create(root, {
		text = "BACK",
		variant = "StudioBack",
		size = UDim2.fromOffset(170, 52),
		position = UDim2.new(0, MARGIN, 1, -36),
		anchorPoint = Vector2.new(0, 1),
		onClick = function()
			self.ScreenController:HideScreen("characterCreator")
		end,
	})
	self._backBtn.Root.ZIndex = 5

	self._confirmBtn = UIButtonComponent.new()
	self._confirmBtn:Create(root, {
		text = "CONFIRM",
		variant = "Green",
		dimmed = true,
		size = UDim2.fromOffset(300, 64),
		position = UDim2.new(1, -MARGIN, 1, -32),
		anchorPoint = Vector2.new(1, 1),
		onClick = function()
			self:_Confirm()
		end,
	})
	self._confirmBtn.Root.ZIndex = 5

	local footHint = UIChrome.BodyText("FootHint", 14, theme.Colors.TextSecondary)
	footHint.Text = "You can change your look later — your class is forever."
	footHint.AnchorPoint = Vector2.new(0.5, 1)
	footHint.Position = UDim2.new(0.5, 0, 1, -44)
	footHint.Size = UDim2.fromOffset(600, 22)
	footHint.ZIndex = 5
	footHint.Parent = root

	self:_RenderClasses()
	self:_RenderPresets()
	self:_RefreshPreview()
	self:_RefreshConfirm()
end

function CharacterCreatorScreen:_BuildClassColumn(theme: Types.UITheme, root: Frame)
	local header = UIChrome.Text("ClassHeader", 22, theme.Arcade.Gold)
	header.Text = "CLASS"
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Position = UDim2.fromOffset(MARGIN, TOP_Y)
	header.Size = UDim2.fromOffset(COL_W, 28)
	header.ZIndex = 5
	header.Parent = root

	local list = UIStyler.Frame("ClassList")
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(MARGIN, TOP_Y + 38)
	list.Size = UDim2.fromOffset(COL_W, (CARD_H + CARD_GAP) * 4)
	list.ZIndex = 5
	UIStyler.ListLayout({
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, CARD_GAP),
	}).Parent = list
	list.Parent = root
	self._classList = list
end

function CharacterCreatorScreen:_RenderClasses()
	local theme = self:GetTheme()
	table.clear(self._classCards)
	-- Card shadows are budget handles; a rebuilt column gives the old ones back
	-- before it takes new ones.
	GPLayoutKit.ReleaseShadows(self._gpCardShadows)
	for _, child in self._classList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for index, entry in self._classes :: { ClassEntry } do
		self:_BuildClassCard(theme, entry, index)
	end
end

function CharacterCreatorScreen:_BuildClassCard(theme: Types.UITheme, entry: ClassEntry, index: number)
	-- Reached from _RenderClasses on every data change, so it branches here.
	if self._gp then
		self:_BuildGPClassCard(theme, entry, index)
		return
	end
	local selected = entry.id == self._selectedClass

	local card = UIStyler.Frame("Class_" .. entry.id)
	card.BackgroundTransparency = 1
	card.Size = UDim2.fromOffset(COL_W, CARD_H)
	card.LayoutOrder = index
	card.Parent = self._classList

	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 1
	hit.Parent = card

	local surface = UIStyler.Frame("Surface")
	surface.BackgroundColor3 = theme.Arcade.NearBlack2
	surface.AnchorPoint = Vector2.new(0.5, 0.5)
	surface.Position = UDim2.fromScale(0.5, 0.5)
	surface.Size = UDim2.fromScale(1, 1)
	surface.ZIndex = 2
	local stroke = UIChrome.Stroke(theme, "Arcade", if selected then "Selection" else "Panel")
	stroke.Parent = surface
	UIChrome.GlassGradient().Parent = surface
	surface.Parent = card

	local icon = IconArchive.Image(surface, entry.icon or "sword", 54)
	icon.Position = UDim2.fromOffset(16, 14)
	icon.ZIndex = 3

	local name = UIChrome.Text("Name", 24, WHITE)
	name.Text = entry.name
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(84, 12)
	name.Size = UDim2.fromOffset(COL_W - 100, 28)
	name.ZIndex = 3
	name.Parent = surface

	local blurb = UIChrome.BodyText("Blurb", 14, theme.Colors.TextSecondary)
	blurb.Text = entry.blurb
	blurb.TextXAlignment = Enum.TextXAlignment.Left
	blurb.TextYAlignment = Enum.TextYAlignment.Top
	blurb.TextWrapped = true
	blurb.Position = UDim2.fromOffset(84, 44)
	blurb.Size = UDim2.fromOffset(COL_W - 100, 40)
	blurb.ZIndex = 3
	blurb.Parent = surface

	local stats = entry.stats or { pwr = 5, spd = 5, def = 5 }
	self:_BuildStatRuler(theme, surface, "PWR", stats.pwr, 96)
	self:_BuildStatRuler(theme, surface, "SPD", stats.spd, 114)
	self:_BuildStatRuler(theme, surface, "DEF", stats.def, 132)

	table.insert(self._classCards, { id = entry.id, surface = surface, stroke = stroke })

	hit.Activated:Connect(function()
		self:_SelectClass(entry.id)
	end)
	-- Animate LAST, after final colours (it snapshots the rest colour).
	UIChrome.Animate(theme, hit, surface)
end

-- The §8 ruler grammar shrunk to card scale: near-black track, gold fill.
function CharacterCreatorScreen:_BuildStatRuler(theme: Types.UITheme, parent: Frame, label: string, value: number, y: number)
	local caption = UIChrome.Text("Stat" .. label, 13, WHITE)
	caption.Text = label
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.Position = UDim2.fromOffset(16, y - 3)
	caption.Size = UDim2.fromOffset(40, 14)
	caption.ZIndex = 3
	caption.Parent = parent

	local trackW = COL_W - 62 - 16
	local track = UIStyler.Frame("Track" .. label)
	track.BackgroundColor3 = theme.Arcade.RulerTrack
	track.Position = UDim2.fromOffset(62, y)
	track.Size = UDim2.fromOffset(trackW, 8)
	track.ZIndex = 3
	track.Parent = parent

	local frac = math.clamp(value / STAT_MAX, 0, 1)
	local fill = UIStyler.Frame("Fill")
	fill.BackgroundColor3 = theme.Arcade.SunburstGold
	fill.Size = UDim2.fromOffset(math.floor(trackW * frac + 0.5), 8)
	fill.ZIndex = 4
	UIChrome.GlassGradient().Parent = fill
	fill.Parent = track
end

function CharacterCreatorScreen:_BuildPreview(theme: Types.UITheme, root: Frame)
	local well = UIStyler.Frame("PreviewWell")
	well.BackgroundColor3 = theme.Arcade.NearBlack
	well.AnchorPoint = Vector2.new(0.5, 0)
	well.Position = UDim2.new(0.5, 0, 0, TOP_Y)
	well.Size = UDim2.fromOffset(WELL_W, WELL_H)
	well.ClipsDescendants = true -- the sunburst spins; it must never leave the well
	well.ZIndex = 3
	UIChrome.Stroke(theme, "Arcade", "Panel").Parent = well
	UIChrome.GlassGradient().Parent = well
	well.Parent = root
	self._well = well

	local artSlot = UIStyler.Frame("ArtSlot")
	artSlot.BackgroundTransparency = 1
	artSlot.AnchorPoint = Vector2.new(0.5, 0)
	artSlot.Position = UDim2.new(0.5, 0, 0, 110)
	artSlot.Size = UDim2.fromOffset(360, 360)
	artSlot.ZIndex = 4
	artSlot.Parent = well

	-- White @ 0.7 sunburst behind every preview (doc §10), 45°/s. The spin
	-- connection is captured here, dropped on hide and re-made on the next
	-- show (§5.4 frugality).
	local burst, spin = UIAssets.SunburstBehind(artSlot, WHITE, 0.7, 45)
	self._burst = burst
	self._burstSpin = spin

	-- STAND-IN: a real game replaces this icon slot with a ViewportFrame
	-- carrying a HumanoidDescription preview (doc §10 viewport recipe: warm
	-- ambient 170,170,175, FOV 22–26, idle animation 507766388).
	local iconSlot = UIStyler.Frame("IconSlot")
	iconSlot.BackgroundTransparency = 1
	iconSlot.AnchorPoint = Vector2.new(0.5, 0.5)
	iconSlot.Position = UDim2.fromScale(0.5, 0.5)
	iconSlot.Size = UDim2.fromOffset(200, 200)
	iconSlot.ZIndex = 5
	iconSlot.Parent = artSlot
	self._previewIconSlot = iconSlot

	local previewName = UIChrome.Text("PreviewName", 32, theme.Arcade.Gold)
	previewName.Text = ""
	previewName.Position = UDim2.fromOffset(20, 506)
	previewName.Size = UDim2.fromOffset(WELL_W - 40, 40)
	previewName.ZIndex = 4
	previewName.Parent = well
	self._previewName = previewName

	local previewBlurb = UIChrome.BodyText("PreviewBlurb", 15, theme.Colors.TextSecondary)
	previewBlurb.Text = ""
	previewBlurb.TextWrapped = true
	previewBlurb.Position = UDim2.fromOffset(40, 554)
	previewBlurb.Size = UDim2.fromOffset(WELL_W - 80, 60)
	previewBlurb.ZIndex = 4
	previewBlurb.Parent = well
	self._previewBlurb = previewBlurb

	local lookLine = UIChrome.Text("PreviewLook", 16, theme.Studio.Card)
	lookLine.Text = ""
	lookLine.Position = UDim2.fromOffset(20, 630)
	lookLine.Size = UDim2.fromOffset(WELL_W - 40, 24)
	lookLine.ZIndex = 4
	lookLine.Parent = well
	self._previewLook = lookLine
end

function CharacterCreatorScreen:_BuildRightColumn(theme: Types.UITheme, root: Frame)
	local x = UIChrome.BASE_WIDTH - MARGIN - COL_W

	local nameHeader = UIChrome.Text("NameHeader", 22, theme.Arcade.Gold)
	nameHeader.Text = "NAME"
	nameHeader.TextXAlignment = Enum.TextXAlignment.Left
	nameHeader.Position = UDim2.fromOffset(x, TOP_Y)
	nameHeader.Size = UDim2.fromOffset(COL_W, 28)
	nameHeader.ZIndex = 5
	nameHeader.Parent = root

	-- Chrome rides a wrapper frame, not the TextBox, so the icon child is
	-- never inset by field padding (same recipe as the codes field).
	local field = UIStyler.Frame("NameField")
	field.BackgroundColor3 = theme.Arcade.Panel
	field.Position = UDim2.fromOffset(x, TOP_Y + 38)
	field.Size = UDim2.fromOffset(COL_W, FIELD_H)
	field.ZIndex = 5
	UIChrome.Corner("Arcade").Parent = field
	UIChrome.Stroke(theme, "Arcade", "Panel").Parent = field
	UIChrome.GlassGradient().Parent = field
	field.Parent = root

	local pencil = IconArchive.Image(field, "edit", 32)
	pencil.AnchorPoint = Vector2.new(0, 0.5)
	pencil.Position = UDim2.new(0, 14, 0.5, 0)
	pencil.ZIndex = 6

	local box = Instance.new("TextBox")
	box.Name = "Name"
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.Text = ""
	box.PlaceholderText = "HERO NAME"
	box.PlaceholderColor3 = theme.Arcade.GreyOwned
	box.FontFace = theme.Fonts.Title
	box.TextSize = 28
	box.TextColor3 = WHITE
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Position = UDim2.fromOffset(58, 0)
	box.Size = UDim2.new(1, -72, 1, 0)
	box.ZIndex = 6
	UIChrome.TextOutline(box)
	box.Parent = field
	self._nameBox = box

	-- Uppercase-as-typed, capped at NAME_MAX. Re-assigning an identical string
	-- never re-fires the changed signal, so this settles in one pass.
	box:GetPropertyChangedSignal("Text"):Connect(function()
		local up = string.upper(box.Text)
		if #up > NAME_MAX then
			up = string.sub(up, 1, NAME_MAX)
		end
		if box.Text ~= up then
			box.Text = up
		end
		self:_RefreshConfirm()
	end)

	-- The display name is UNTRUSTED INPUT: a real game must round-trip it
	-- through TextService:FilterStringAsync on the SERVER before any other
	-- player ever sees it. This screen only collects it.
	local filterNote = UIChrome.BodyText("FilterNote", 13, theme.Colors.TextSecondary)
	filterNote.Text = "Names are filtered before other potters see them."
	filterNote.TextXAlignment = Enum.TextXAlignment.Left
	filterNote.Position = UDim2.fromOffset(x, TOP_Y + 38 + FIELD_H + 8)
	filterNote.Size = UDim2.fromOffset(COL_W, 18)
	filterNote.ZIndex = 5
	filterNote.Parent = root

	local lookHeader = UIChrome.Text("LookHeader", 22, theme.Arcade.Gold)
	lookHeader.Text = "LOOK"
	lookHeader.TextXAlignment = Enum.TextXAlignment.Left
	lookHeader.Position = UDim2.fromOffset(x, TOP_Y + 156)
	lookHeader.Size = UDim2.fromOffset(COL_W, 28)
	lookHeader.ZIndex = 5
	lookHeader.Parent = root

	local swatchRow = UIStyler.Frame("SwatchRow")
	swatchRow.BackgroundTransparency = 1
	swatchRow.Position = UDim2.fromOffset(x, TOP_Y + 194)
	swatchRow.Size = UDim2.fromOffset(COL_W, SWATCH)
	swatchRow.ZIndex = 5
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, SWATCH_GAP),
	}).Parent = swatchRow
	swatchRow.Parent = root
	self._swatchRow = swatchRow

	local lookName = UIChrome.Text("LookName", 18, theme.Studio.Card)
	lookName.Text = ""
	lookName.TextXAlignment = Enum.TextXAlignment.Left
	lookName.Position = UDim2.fromOffset(x, TOP_Y + 194 + SWATCH + 10)
	lookName.Size = UDim2.fromOffset(COL_W, 24)
	lookName.ZIndex = 5
	lookName.Parent = root
	self._lookName = lookName

	self._randomBtn = UIButtonComponent.new()
	self._randomBtn:Create(root, {
		text = "RANDOMIZE",
		variant = "Blue",
		iconId = IconArchive.Id("dice"),
		size = UDim2.fromOffset(COL_W, 52),
		position = UDim2.fromOffset(x, TOP_Y + 194 + SWATCH + 48),
		onClick = function()
			self:_Randomize()
		end,
	})
	self._randomBtn.Root.ZIndex = 5
end

function CharacterCreatorScreen:_RenderPresets()
	-- Reached from _OnShow and Update as well as the build, so it branches here.
	if self._gp then
		self:_RenderGPPresets()
		return
	end
	local theme = self:GetTheme()
	table.clear(self._swatches)
	for _, child in self._swatchRow:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for index, preset in self._presets :: { Preset } do
		local selected = preset.id == self._selectedPreset

		local swatch = Instance.new("TextButton")
		swatch.Name = "Swatch_" .. preset.id
		swatch.Text = ""
		swatch.AutoButtonColor = false
		swatch.BackgroundColor3 = preset.color
		swatch.Size = UDim2.fromOffset(SWATCH, SWATCH)
		swatch.LayoutOrder = index
		swatch.ZIndex = 5
		-- Studio glaze-swatch grammar (doc §4.3): corner 10, a ring resting at
		-- the style's frame transparency (Classic: cream 3px @ 0.8) that snaps
		-- solid when selected.
		UIChrome.Corner("Studio", "Tool").Parent = swatch
		local stroke = UIChrome.Stroke(theme, "Studio", "Swatch")
		stroke.Transparency = if selected then 0 elseif theme.Chrome then theme.Chrome.StrokeTransparency else 0.8
		stroke.Parent = swatch
		UIChrome.GlassGradient().Parent = swatch
		swatch.Parent = self._swatchRow

		table.insert(self._swatches, { id = preset.id, button = swatch, stroke = stroke })
		swatch.Activated:Connect(function()
			self:_SelectPreset(preset.id)
		end)
		UIChrome.Animate(theme, swatch)
	end
	local active = self:_PresetById(self._selectedPreset)
	self._lookName.Text = if active then active.name else ""
end

-- ========================================================================
-- Selection / behaviour
-- ========================================================================

function CharacterCreatorScreen:_SelectClass(id: string)
	local theme = self:GetTheme()
	local already = self._selectedClass == id
	self._selectedClass = id
	-- Restyle in place: the ring moves, backgrounds never change (§4.3).
	for _, record in self._classCards do
		local selected = record.id == id
		if self._gp then
			-- Repaint the SAME stroke rather than swapping it: UIChrome.Stroke
			-- resolves to BLACK under this pack's Chrome policy (law 1).
			if selected then
				record.stroke.Color = GPLayoutKit.Deepen(theme, theme.Semantic.Selection, 1)
				record.stroke.Thickness = 3
				record.stroke.Transparency = 0
			else
				record.stroke.Color = GPLayoutKit.Deepen(theme, record.surface.BackgroundColor3, 1)
				record.stroke.Thickness = (theme.Chrome and theme.Chrome.StrokeThickness) or 2
				record.stroke.Transparency = (theme.Chrome and theme.Chrome.StrokeTransparency) or 0.35
			end
		else
			record.stroke:Destroy()
			local stroke = UIChrome.Stroke(theme, "Arcade", if selected then "Selection" else "Panel")
			stroke.Parent = record.surface
			record.stroke = stroke
		end
		if selected then
			UIChrome.Pulse(theme, record.surface)
		end
	end
	if not already then
		self:_PlaySound("Click")
	end
	self:_RefreshPreview()
	self:_RefreshConfirm()
end

function CharacterCreatorScreen:_SelectPreset(id: string)
	self._selectedPreset = id
	local theme = self:GetTheme()
	for _, record in self._swatches do
		local selected = record.id == id
		record.stroke.Transparency = if selected then 0 elseif theme.Chrome then theme.Chrome.StrokeTransparency else 0.8
		if selected then
			UIChrome.Pulse(theme, record.button)
		end
	end
	local preset = self:_PresetById(id)
	self._lookName.Text = if preset then preset.name else ""
	self:_RefreshPreview()
end

function CharacterCreatorScreen:_RefreshPreview()
	local theme = self:GetTheme()
	local entry = self:_ClassById(self._selectedClass)

	self._previewIconSlot:ClearAllChildren()
	local icon: GuiObject
	if entry then
		icon = if self._gp
			then GPControlKit.Icon(theme, self._previewIconSlot, entry.icon or "sword", 160)
			else IconArchive.Image(self._previewIconSlot, entry.icon or "sword", 160)
	else
		icon = if self._gp
			then GPControlKit.Icon(theme, self._previewIconSlot, "player", 160)
			else IconArchive.Image(self._previewIconSlot, "player", 160)
		if icon:IsA("ImageLabel") then
			icon.ImageTransparency = 0.45
		elseif icon:IsA("TextLabel") then
			icon.TextTransparency = 0.45
		end
	end
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.ZIndex = 6

	if self._gp then
		-- Butter gold measures ~1.2:1 on this pack's cream and the arcade
		-- "owned grey" is a pale mauve; both would vanish. Ink and soft ink
		-- carry the two states instead, and the colour lives in the well's
		-- own hue-matched shade.
		if entry then
			self._previewName.Text = gpTitle(entry.name)
			self._previewName.TextColor3 = theme.Colors.TextPrimary
			self._previewBlurb.Text = entry.blurb
		else
			self._previewName.Text = "Pick a class"
			self._previewName.TextColor3 = theme.Colors.TextSecondary
			self._previewBlurb.Text = "Choose a class on the left to see it here."
		end
	elseif entry then
		self._previewName.Text = entry.name
		self._previewName.TextColor3 = theme.Arcade.Gold
		self._previewBlurb.Text = entry.blurb
	else
		self._previewName.Text = "PICK A CLASS"
		self._previewName.TextColor3 = theme.Arcade.GreyOwned
		self._previewBlurb.Text = "Choose a class on the left to preview it here."
	end

	local preset = self:_PresetById(self._selectedPreset)
	if self._gp then
		self._previewLook.Text = if preset then "Glaze  ·  " .. gpTitle(preset.name) else ""
	else
		self._previewLook.Text = if preset then "LOOK  ·  " .. preset.name else ""
	end
	if entry then
		UIChrome.Pulse(theme, self._previewIconSlot)
	end
end

function CharacterCreatorScreen:_IsValid(): boolean
	return self._selectedClass ~= nil and trim(self._nameBox.Text) ~= ""
end

-- CONFIRM dims in place while incomplete; the tap still answers (§11.1).
function CharacterCreatorScreen:_RefreshConfirm()
	if self._confirmBtn then
		self._confirmBtn:SetContent({
			text = if self._gp then "Confirm" else "CONFIRM",
			dimmed = not self:_IsValid(),
		})
	end
end

function CharacterCreatorScreen:_Confirm()
	if self._selectedClass == nil then
		self:_Toast("Pick a class first.", "Error")
		return
	end
	local name = trim(self._nameBox.Text)
	if name == "" then
		self:_Toast("Name your hero first.", "Error")
		return
	end
	local classId = self._selectedClass :: string
	if self._onConfirm then
		pcall(self._onConfirm, classId, name, self._selectedPreset)
	end
	self:_Toast(string.format("Welcome to the kiln, %s!", name), "Success")
	self.ScreenController:HideScreen("characterCreator")
end

function CharacterCreatorScreen:_Randomize()
	local classes = self._classes :: { ClassEntry }
	local presets = self._presets :: { Preset }
	if #classes > 0 then
		self:_SelectClass(classes[math.random(#classes)].id)
	end
	if #presets > 0 then
		self:_SelectPreset(presets[math.random(#presets)].id)
	end
	self._nameBox.Text = RANDOM_NAMES[math.random(#RANDOM_NAMES)]
	UIChrome.Pulse(self:GetTheme(), self._well)
end

-- ========================================================================
-- Lifecycle
-- ========================================================================

function CharacterCreatorScreen:_OnShow(data: any?)
	local hadData = type(data) == "table"
	self:_Ingest(data)
	if self._built and hadData then
		self:_RenderClasses()
		self:_RenderPresets()
		self:_RefreshPreview()
		self:_RefreshConfirm()
	end
	-- Sunburst spins only while this screen is up (§5.4).
	if not self._burstSpin and self._burst then
		self._burstSpin = UIChrome.Spin(self._burst, 45)
	end
	if self._well then
		UIChrome.PopIn(self:GetTheme(), self._well)
	end
end

function CharacterCreatorScreen:_OnHide()
	if self._burstSpin then
		self._burstSpin:Disconnect()
		self._burstSpin = nil
	end
end

function CharacterCreatorScreen:Update(data: any)
	self:_Ingest(data)
	if self._built then
		self:_RenderClasses()
		self:_RenderPresets()
		self:_RefreshPreview()
		self:_RefreshConfirm()
	end
end

-- A style rebuild destroys the Gui but NOT the shadow budget count.
function CharacterCreatorScreen:_OnTeardown()
	self:_OnHide()
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	GPLayoutKit.ReleaseShadows(self._gpCardShadows)
	GPLayoutKit.ReleaseShadows(self._gpSwatchShadows)
	self._gpShadows = nil
	self._gpCardShadows = nil
	self._gpSwatchShadows = nil
	self._burst = nil
	self._well = nil
	table.clear(self._classCards)
	table.clear(self._swatches)
	for _, key in { "_backBtn", "_confirmBtn", "_randomBtn" } do
		(self :: any)[key] = nil
	end
end

function CharacterCreatorScreen:Destroy()
	self:_OnHide()
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	GPLayoutKit.ReleaseShadows(self._gpCardShadows)
	GPLayoutKit.ReleaseShadows(self._gpSwatchShadows)
	for _, key in { "_backBtn", "_confirmBtn", "_randomBtn" } do
		local component = (self :: any)[key]
		if component then
			component:Destroy();
			(self :: any)[key] = nil
		end
	end
	UIScreenBase.Destroy(self)
end

return CharacterCreatorScreen
