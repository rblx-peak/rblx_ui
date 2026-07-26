--!strict
-- GLLayoutKit — the shared builders of the "GL" LAYOUT language
-- (theme.LayoutKit == "GL"): comic diagonal composition. Extracted from the
-- APPROVED shop screen so every other screen composes from the same proven
-- parts instead of re-deriving the look (and drifting back to defaults).
--
-- Screens branch their build:
--
--   function MyScreen:_BuildContent()
--       if self:LayoutKit() == "GL" then
--           self:_BuildGLLayout()
--           return
--       end
--       ... classic build ...
--   end
--
-- THE LAWS THIS KIT ENFORCES SO CALLERS CANNOT BREAK THEM:
--   * No UICorner, ever — silhouettes come from chamfered 9-slice art.
--   * Text FILL is never black; black exists only as the outline stroke.
--   * Every plate carries a hard sticker shadow offset along the pack slant.
--   * Tilts alternate around ONE axis (GL_TILT) so the diagonal agrees.
--   * Art we cannot generate ships as a visibly-intentional ART SLOT.
--   * Shadows are budget-registered handles (disable-not-destroy on pooled
--     elements; Release on teardown) — see StyleKit.Capabilities.
--
-- 0.4 BOUNDARY: this kit is pure STATIC COMPOSITION (Luau-built instances
-- painted from tokens). Sequenced motion (slam text, ceremonies, ticker
-- effects) lives in the GL modules; styling-side state looks arrive via
-- StateDriver tags. Nothing here animates.

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)

local GLLayoutKit = {}

-- The pack's single diagonal axis, in degrees. Everything that tilts tilts
-- by this or a multiple of it, so slants never disagree.
GLLayoutKit.TILT = -2.5

export type Page = {
	dim: Frame,
	panel: Frame,
	banner: ImageLabel,
	title: TextLabel,
	topRight: Frame,
	content: Frame,
	close: TextButton,
	shadows: { any },
}

local function assetDef(theme: Types.UITheme, key: string): any
	local assets = (theme :: any).Assets
	return assets and assets[key] or nil
end

-- A tinted 9-slice plate. Pack art is white-fill + black-ink, so the tint
-- colours the FILL and the ink stays ink. Missing asset = hairline
-- placeholder chrome (the spec'd fallback), never a different aesthetic.
function GLLayoutKit.Slice(theme: Types.UITheme, key: string, tint: Color3, name: string?): ImageLabel
	local def = assetDef(theme, key)
	local img = Instance.new("ImageLabel")
	img.Name = name or key
	img.BackgroundTransparency = 1
	if def then
		img.Image = def.image
		if def.slice then
			img.ScaleType = Enum.ScaleType.Slice
			img.SliceCenter = def.slice
		end
	else
		img.BackgroundTransparency = 0.15 -- TODO: asset missing
		img.BackgroundColor3 = tint
		UIStyler.Stroke(theme.Colors.Stroke, 3, 0).Parent = img
	end
	img.ImageColor3 = tint
	return img
end

-- A tiled pattern overlay (halftone / action lines / chevrons), token-tinted.
function GLLayoutKit.Tile(theme: Types.UITheme, key: string, tint: Color3, transparency: number, name: string?): ImageLabel
	local def = assetDef(theme, key)
	local img = Instance.new("ImageLabel")
	img.Name = name or key
	img.BackgroundTransparency = 1
	if def then
		img.Image = def.image
		img.ScaleType = Enum.ScaleType.Tile
		local tile = def.tile or 128
		img.TileSize = UDim2.fromOffset(tile, tile)
	end
	img.ImageColor3 = tint
	img.ImageTransparency = transparency
	img.Size = UDim2.fromScale(1, 1)
	return img
end

-- The hard comic sticker shadow. Returns the BUDGET HANDLE (owns
-- SetEnabled/Release); push it into the caller's shadow list so teardown
-- can release the budget — a destroyed Gui alone would leak the count.
function GLLayoutKit.Shadow(theme: Types.UITheme, host: GuiObject, intent: string, sink: { any }?): any
	local _, handle = UIChrome.Shadow(theme, intent, host)
	if sink then
		table.insert(sink, handle)
	end
	return handle
end

-- Display text: pack display font, cream/token ink, black OUTLINE (never a
-- black fill). `size` is px at the 1650x1020 authoring baseline.
function GLLayoutKit.Text(theme: Types.UITheme, size: number, color: Color3?, name: string?): TextLabel
	local label = UIChrome.Text(name or "Label", size, color or theme.Colors.TextPrimary)
	return label
end

function GLLayoutKit.BodyText(theme: Types.UITheme, size: number, color: Color3?, name: string?): TextLabel
	return UIChrome.BodyText(name or "Body", size, color or theme.Colors.TextSecondary)
end

-- THE PAGE: dim scrim -> chamfer-free charcoal plate with halftone, torn
-- bottom edge, slanted banner header breaking the top-left, tilted close
-- chip breaking the top-right, and a top-right slot for counters.
-- This is the approved shop anatomy, reusable.
function GLLayoutKit.Page(theme: Types.UITheme, root: Instance, opts: {
	titleText: string,
	sizePx: Vector2?,
	onClose: (() -> ())?,
	showClose: boolean?,
}): Page
	local shadows = {}
	local ink = theme.Colors.Stroke
	local paper = theme.Colors.TextPrimary
	local gold = theme.Arcade.Gold
	local size = opts.sizePx or Vector2.new(1010, 660)

	local dim = UIStyler.Frame("Dim")
	dim.BackgroundColor3 = theme.Colors.Overlay
	dim.BackgroundTransparency = 0.45
	dim.Size = UDim2.fromScale(1, 1)
	dim.Parent = root

	-- Off-centre by a few px so the banner/close can break its corners.
	local panel = UIStyler.Frame("GLPanel")
	panel.BackgroundColor3 = theme.Colors.Surface
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, -6, 0.5, 6)
	panel.Size = UDim2.fromOffset(size.X, size.Y)
	panel.Parent = root
	UIStyler.Stroke(ink, 3, 0).Parent = panel
	GLLayoutKit.Shadow(theme, panel, "lg", shadows)

	GLLayoutKit.Tile(theme, "halftone", ink, 0.92, "PanelTone").Parent = panel

	local tornBottom = GLLayoutKit.Slice(theme, "edgeTorn", theme.Colors.Background, "TornBottom")
	tornBottom.AnchorPoint = Vector2.new(0, 1)
	tornBottom.Position = UDim2.new(0, 0, 1, 2)
	tornBottom.Size = UDim2.new(1, 0, 0, 22)
	tornBottom.ZIndex = 8
	tornBottom.Parent = panel

	-- Banner header: red slash + gold inner rule + halftone + raking lines.
	local banner = GLLayoutKit.Slice(theme, "bannerSlash", theme.Arcade.HeaderRed, "Banner")
	banner.Position = UDim2.fromOffset(-26, -34)
	banner.Size = UDim2.fromOffset(430, 86)
	banner.Rotation = GLLayoutKit.TILT
	banner.ZIndex = 5
	banner.Parent = panel
	GLLayoutKit.Shadow(theme, banner, "md", shadows)
	local inner = GLLayoutKit.Slice(theme, "bannerSlashInner", gold, "BannerInner")
	inner.Size = UDim2.fromScale(1, 1)
	inner.ZIndex = 6
	inner.Parent = banner
	local tone = GLLayoutKit.Tile(theme, "halftone", ink, 0.82, "BannerTone")
	tone.ZIndex = 6
	tone.Parent = banner
	local lines = GLLayoutKit.Tile(theme, "actionLines", ink, 0.88, "BannerLines")
	lines.Size = UDim2.new(0.45, 0, 1, 0)
	lines.Position = UDim2.fromScale(0.55, 0)
	lines.ZIndex = 6
	lines.Parent = banner

	local title = GLLayoutKit.Text(theme, 46, paper, "Title")
	title.Text = string.upper(opts.titleText)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Position = UDim2.fromOffset(46, 6)
	title.Size = UDim2.new(1, -60, 1, -12)
	title.ZIndex = 7
	title.Parent = banner

	-- Close: tilted ink chip, heavy cream X, counter-tilted so it reads
	-- deliberate rather than sloppy.
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.BackgroundTransparency = 1
	close.Text = ""
	close.AutoButtonColor = false
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, 26, 0, -22)
	close.Size = UDim2.fromOffset(64, 56)
	close.ZIndex = 7
	close.Visible = opts.showClose ~= false
	close.Parent = panel
	local closeChip = GLLayoutKit.Slice(theme, "chipPaper", ink, "CloseChip")
	closeChip.Size = UDim2.fromScale(1, 1)
	closeChip.Rotation = -GLLayoutKit.TILT
	closeChip.ZIndex = 7
	closeChip.Parent = close
	GLLayoutKit.Shadow(theme, closeChip, "sm", shadows)
	local closeX = GLLayoutKit.Text(theme, 34, paper, "X")
	closeX.Text = "X"
	closeX.Size = UDim2.fromScale(1, 1)
	closeX.Rotation = -GLLayoutKit.TILT
	closeX.ZIndex = 8
	closeX.Parent = close
	if opts.onClose then
		close.Activated:Connect(opts.onClose)
	end
	UIChrome.Animate(theme, close, closeChip)

	-- Top-right slot: currency counters / status chips, right-aligned row.
	local topRight = UIStyler.Frame("TopRight")
	topRight.BackgroundTransparency = 1
	topRight.AnchorPoint = Vector2.new(1, 0)
	topRight.Position = UDim2.new(1, -56, 0, -16)
	topRight.Size = UDim2.fromOffset(340, 44)
	topRight.ZIndex = 6
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
	}).Parent = topRight
	topRight.Parent = panel

	local content = UIStyler.Frame("Content")
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(24, 74)
	content.Size = UDim2.new(1, -48, 1, -98)
	content.Parent = panel

	return {
		dim = dim,
		panel = panel,
		banner = banner,
		title = title,
		topRight = topRight,
		content = content,
		close = close,
		shadows = shadows,
	}
end

export type TabBar = {
	frame: Frame,
	Add: (text: string, id: string, onClick: (() -> ())?) -> (),
	Select: (id: string) -> (),
}

-- Trapezoid tab row. Selected reads FORWARD: heat fill + 4% scale + a gold
-- underline slash tilted with the axis. Never a recoloured blue state.
function GLLayoutKit.Tabs(theme: Types.UITheme, parent: Instance, opts: { widthPx: number? }?): TabBar
	local o = opts or {}
	local bar = UIStyler.Frame("Tabs")
	bar.BackgroundTransparency = 1
	bar.Size = UDim2.new(1, 0, 0, 52)
	bar.ZIndex = 4
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, 6),
	}).Parent = bar
	bar.Parent = parent

	local entries: { [string]: any } = {}
	local order = 0

	local function select(id: string)
		for entryId, entry in entries do
			local on = entryId == id
			entry.shape.ImageColor3 = on and theme.Colors.Primary or theme.Arcade.NearBlack2
			entry.label.TextColor3 = on and theme.Colors.TextPrimary or theme.Colors.TextSecondary
			entry.slash.Visible = on
			entry.scale.Scale = on and 1.04 or 1
		end
	end

	local function add(text: string, id: string, onClick: (() -> ())?)
		order += 1
		local tab = Instance.new("TextButton")
		tab.Name = "Tab_" .. id
		tab.BackgroundTransparency = 1
		tab.Text = ""
		tab.AutoButtonColor = false
		tab.Size = UDim2.fromOffset(o.widthPx or 186, 46)
		tab.LayoutOrder = order
		tab.ZIndex = 4
		tab.Parent = bar
		local shape = GLLayoutKit.Slice(theme, "tabTrapezoid", theme.Arcade.NearBlack2, "Shape")
		shape.Size = UDim2.fromScale(1, 1)
		shape.ZIndex = 4
		shape.Parent = tab
		local scale = Instance.new("UIScale")
		scale.Parent = tab
		local label = GLLayoutKit.Text(theme, 22, theme.Colors.TextSecondary, "Label")
		label.Text = string.upper(text)
		label.Size = UDim2.fromScale(1, 1)
		label.ZIndex = 5
		label.Parent = tab
		local slash = UIStyler.Frame("Slash")
		slash.BackgroundColor3 = theme.Arcade.Gold
		slash.BorderSizePixel = 0
		slash.AnchorPoint = Vector2.new(0.5, 1)
		slash.Position = UDim2.new(0.5, 0, 1, 6)
		slash.Size = UDim2.new(0.7, 0, 0, 4)
		slash.Rotation = GLLayoutKit.TILT
		slash.Visible = false
		slash.ZIndex = 6
		slash.Parent = tab
		if onClick then
			tab.Activated:Connect(onClick)
		end
		entries[id] = { shape = shape, label = label, slash = slash, scale = scale }
	end

	return { frame = bar, Add = add, Select = select }
end

export type Card = {
	root: TextButton,
	body: ImageLabel,
	art: ImageLabel,
	artLabel: TextLabel,
	name: TextLabel,
	shadow: any,
}

-- The chamfered card plate: 26px cut corners, halftone, ART SLOT well with
-- a torn lower edge, and a name line. Plates ride LIGHTER than the page so
-- the hard sticker shadow actually reads.
function GLLayoutKit.Card(theme: Types.UITheme, parent: Instance, sink: { any }?): Card
	local ink = theme.Colors.Stroke
	local root = Instance.new("TextButton")
	root.Name = "GLCard"
	root.BackgroundTransparency = 1
	root.Text = ""
	root.AutoButtonColor = false
	root.Parent = parent

	local body = GLLayoutKit.Slice(theme, "cardCut", theme.Arcade.Row, "Body")
	body.Size = UDim2.fromScale(1, 1)
	body.Parent = root
	local shadow = GLLayoutKit.Shadow(theme, body, "sm", sink)

	local tone = GLLayoutKit.Tile(theme, "halftone", ink, 0.88, "Tone")
	tone.ZIndex = 2
	tone.Parent = body

	local art = GLLayoutKit.Slice(theme, "artSlot", theme.Colors.Disabled, "ArtSlot")
	art.AnchorPoint = Vector2.new(0.5, 0)
	art.Position = UDim2.new(0.5, 0, 0, 14)
	art.Size = UDim2.new(1, -28, 0, 118)
	art.ZIndex = 3
	art.Parent = body
	local artTone = GLLayoutKit.Tile(theme, "halftone", ink, 0.8, "ArtTone")
	artTone.ZIndex = 3
	artTone.Parent = art
	local artLabel = GLLayoutKit.Text(theme, 13, theme.Colors.TextSecondary, "Icon")
	artLabel.Text = "ART SLOT"
	artLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	artLabel.Position = UDim2.fromScale(0.5, 0.5)
	artLabel.Size = UDim2.fromScale(1, 0.3)
	artLabel.Rotation = GLLayoutKit.TILT * 2
	artLabel.ZIndex = 4
	artLabel.Parent = art
	local torn = GLLayoutKit.Slice(theme, "edgeTorn", ink, "Torn")
	torn.AnchorPoint = Vector2.new(0, 1)
	torn.Position = UDim2.new(0, 0, 1, 6)
	torn.Size = UDim2.new(1, 0, 0, 10)
	torn.Rotation = 180
	torn.ZIndex = 4
	torn.Parent = art

	local name = GLLayoutKit.Text(theme, 21, theme.Colors.TextPrimary, "Name")
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(14, 142)
	name.Size = UDim2.new(1, -28, 0, 26)
	name.ZIndex = 3
	name.Parent = body

	UIChrome.Animate(theme, root, body)
	return { root = root, body = body, art = art, artLabel = artLabel, name = name, shadow = shadow }
end

export type PriceChip = {
	root: ImageLabel,
	icon: ImageLabel,
	amount: TextLabel,
	shadow: any,
}

-- Value chip: INK plate, GOLD numerals, currency glyph. The pack's only
-- legal price treatment (text fill is never black, so "black on paper" is
-- out; candy pills are banned outright).
function GLLayoutKit.PriceChip(theme: Types.UITheme, parent: Instance, sink: { any }?): PriceChip
	local chip = GLLayoutKit.Slice(theme, "chipPaper", theme.Arcade.NearBlack, "Price")
	chip.Rotation = -GLLayoutKit.TILT
	chip.Size = UDim2.fromOffset(150, 38)
	chip.ZIndex = 4
	chip.Parent = parent
	local shadow = GLLayoutKit.Shadow(theme, chip, "sm", sink)
	local icon = Instance.new("ImageLabel")
	icon.Name = "Glyph"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromOffset(22, 22)
	icon.Position = UDim2.fromOffset(8, 6)
	icon.ZIndex = 5
	icon.Parent = chip
	local amount = GLLayoutKit.Text(theme, 22, theme.Arcade.Gold, "Amount")
	amount.TextXAlignment = Enum.TextXAlignment.Left
	amount.Position = UDim2.fromOffset(38, 0)
	amount.Size = UDim2.new(1, -46, 1, 0)
	amount.ZIndex = 5
	amount.Parent = chip
	return { root = chip, icon = icon, amount = amount, shadow = shadow }
end

-- Tilted paper badge chip (SALE / NEW / FEATURED / rarity). Cream text on a
-- token fill, overhanging its host corner by design.
function GLLayoutKit.Badge(theme: Types.UITheme, parent: Instance, text: string, fill: Color3?, sink: { any }?): (ImageLabel, TextLabel)
	local badge = GLLayoutKit.Slice(theme, "chipPaper", fill or theme.Arcade.Red, "Badge")
	badge.Position = UDim2.fromOffset(-10, -12)
	badge.Size = UDim2.fromOffset(92, 30)
	badge.Rotation = GLLayoutKit.TILT * 1.6
	badge.ZIndex = 5
	badge.Parent = parent
	GLLayoutKit.Shadow(theme, badge, "sm", sink)
	local label = GLLayoutKit.Text(theme, 16, theme.Colors.TextPrimary, "BadgeText")
	label.Text = string.upper(text)
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 6
	label.Parent = badge
	return badge, label
end

-- The heat CTA: tilted slab, cream shout, sticker shadow.
function GLLayoutKit.ActionButton(theme: Types.UITheme, parent: Instance, text: string, onClick: (() -> ())?, sink: { any }?): TextButton
	local button = Instance.new("TextButton")
	button.Name = "Action"
	button.BackgroundTransparency = 1
	button.Text = ""
	button.AutoButtonColor = false
	button.Size = UDim2.fromOffset(210, 52)
	button.Parent = parent
	local plate = GLLayoutKit.Slice(theme, "chipPaper", theme.Colors.Primary, "Plate")
	plate.Size = UDim2.fromScale(1, 1)
	plate.Rotation = GLLayoutKit.TILT
	plate.Parent = button
	GLLayoutKit.Shadow(theme, plate, "sm", sink)
	local label = GLLayoutKit.Text(theme, 24, theme.Colors.TextPrimary, "Label")
	label.Text = string.upper(text)
	label.Size = UDim2.fromScale(1, 1)
	label.Rotation = GLLayoutKit.TILT
	label.ZIndex = 2
	label.Parent = button
	if onClick then
		button.Activated:Connect(onClick)
	end
	UIChrome.Animate(theme, button, plate)
	return button
end

-- Diagonal hatched section divider.
function GLLayoutKit.Divider(theme: Types.UITheme, parent: Instance): ImageLabel
	local rule = GLLayoutKit.Tile(theme, "slashDivider", theme.Colors.Stroke, 0.4, "Divider")
	rule.Size = UDim2.new(1, 0, 0, 12)
	rule.Parent = parent
	return rule
end

-- Dim uppercase section label.
function GLLayoutKit.SectionLabel(theme: Types.UITheme, parent: Instance, text: string): TextLabel
	local label = GLLayoutKit.BodyText(theme, 14, theme.Colors.TextSecondary, "Section")
	label.Text = string.upper(text)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Size = UDim2.new(1, 0, 0, 20)
	label.Parent = parent
	return label
end

-- A dense list row on a chamfered plate: name + optional value, tilted
-- slightly, sticker-shadowed. The GL answer to a table row.
function GLLayoutKit.ListRow(theme: Types.UITheme, parent: Instance, opts: {
	heightPx: number?,
	layoutOrder: number?,
	clickable: boolean?,
	tiltIndex: number?,
}?, sink: { any }?): (GuiObject, ImageLabel, TextLabel, TextLabel)
	local o = opts or {}
	local root: GuiObject
	if o.clickable then
		local b = Instance.new("TextButton")
		b.Text = ""
		b.AutoButtonColor = false
		root = b
	else
		root = UIStyler.Frame("Row")
	end
	root.Name = "GLRow"
	root.BackgroundTransparency = 1
	root.Size = UDim2.new(1, 0, 0, o.heightPx or 56)
	if o.layoutOrder then
		root.LayoutOrder = o.layoutOrder
	end
	root.Parent = parent

	local plate = GLLayoutKit.Slice(theme, "cardCut", theme.Arcade.Row, "Plate")
	plate.Size = UDim2.fromScale(1, 1)
	plate.Rotation = ((o.tiltIndex or 0) % 2 == 0) and GLLayoutKit.TILT * 0.35 or -GLLayoutKit.TILT * 0.3
	plate.Parent = root
	GLLayoutKit.Shadow(theme, plate, "sm", sink)
	GLLayoutKit.Tile(theme, "halftone", theme.Colors.Stroke, 0.9, "Tone").Parent = plate

	local name = GLLayoutKit.Text(theme, 20, theme.Colors.TextPrimary, "Name")
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(16, 0)
	name.Size = UDim2.new(0.6, 0, 1, 0)
	name.ZIndex = 3
	name.Parent = plate

	local value = GLLayoutKit.Text(theme, 20, theme.Arcade.Gold, "Value")
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.new(1, -16, 0, 0)
	value.Size = UDim2.new(0.35, 0, 1, 0)
	value.ZIndex = 3
	value.Parent = plate

	if o.clickable then
		UIChrome.Animate(theme, root :: TextButton, plate)
	end
	return root, plate, name, value
end

-- Chevron progress meter: >>> energy instead of a flat bar. Returns a
-- SetRatio(0..1) setter; the fill is a tiled chevron image, token-tinted.
function GLLayoutKit.Meter(theme: Types.UITheme, parent: Instance, sink: { any }?): (Frame, (number) -> ())
	local track = UIStyler.Frame("Meter")
	track.BackgroundColor3 = theme.Arcade.RulerTrack
	track.BorderSizePixel = 0
	track.Size = UDim2.new(1, 0, 0, 22)
	track.Parent = parent
	UIStyler.Stroke(theme.Colors.Stroke, 3, 0).Parent = track
	GLLayoutKit.Shadow(theme, track, "sm", sink)

	local fillClip = UIStyler.Frame("FillClip")
	fillClip.BackgroundTransparency = 1
	fillClip.ClipsDescendants = true
	fillClip.Size = UDim2.fromScale(0, 1)
	fillClip.Parent = track
	local fill = GLLayoutKit.Tile(theme, "chevronFill", theme.Colors.Primary, 0, "Fill")
	fill.Size = UDim2.new(0, 4000, 1, 0)
	fill.Parent = fillClip

	local function setRatio(ratio: number)
		fillClip.Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
	end
	return track, setRatio
end

-- Release every shadow handle a screen collected (teardown contract).
function GLLayoutKit.ReleaseShadows(sink: { any }?)
	if not sink then
		return
	end
	for _, handle in sink do
		handle:Release()
	end
	table.clear(sink)
end

return GLLayoutKit
