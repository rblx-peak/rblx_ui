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
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)

local GLLayoutKit = {}

-- The pack's single diagonal axis, in degrees. Everything that tilts tilts
-- by this or a multiple of it, so slants never disagree.
GLLayoutKit.TILT = -2.5

export type Page = {
	dim: Frame,
	panel: Frame,
	banner: ImageLabel,
	title: TextLabel,
	subtitle: TextLabel,
	topRight: Frame,
	content: Frame, -- THE PAPER SURFACE (light); put content here
	close: TextButton,
	characterSlot: Frame, -- art layer that BREAKS the panel edges
	shadows: { any },
}

-- Comic dialect tokens with house fallbacks, so a pack that omits them
-- still renders (never a different aesthetic).
local function comic(theme: Types.UITheme): { [string]: any }
	local dialects = (theme :: any).DialectTokens
	return (dialects and dialects.comic) or {}
end

function GLLayoutKit.Paper(theme: Types.UITheme): Color3
	return comic(theme).surfacePaper or Color3.fromRGB(245, 240, 228)
end

function GLLayoutKit.PaperWarm(theme: Types.UITheme): Color3
	return comic(theme).surfacePaperWarm or Color3.fromRGB(230, 226, 214)
end

-- Near-black ink for text ON paper (never pure black — pack law).
function GLLayoutKit.PaperInk(theme: Types.UITheme): Color3
	return comic(theme).paperInk or Color3.fromRGB(38, 22, 18)
end

-- THE SIGNATURE DOUBLE FRAME: heavy black outer stroke + a thin gold inner
-- stroke inset a few px (multiple UIStrokes per instance are legal).
function GLLayoutKit.DoubleFrame(theme: Types.UITheme, host: GuiObject)
	local c = comic(theme)
	UIStyler.Stroke(theme.Colors.Stroke, c.frameOuterPx or 4, 0).Parent = host
	local innerHost = UIStyler.Frame("InnerFrame")
	innerHost.BackgroundTransparency = 1
	local inset = c.frameInnerInset or 4
	innerHost.Position = UDim2.fromOffset(inset, inset)
	innerHost.Size = UDim2.new(1, -inset * 2, 1, -inset * 2)
	innerHost.ZIndex = (host.ZIndex or 1) + 1
	innerHost.Parent = host
	UIStyler.Stroke(theme.Arcade.Gold, c.frameInnerPx or 2, 0).Parent = innerHost
end

-- Halftone as an EDGE TREATMENT, not a fill: dots ride an accent slab and
-- fade toward its interior. Never a texture laid over content.
function GLLayoutKit.HalftoneEdge(theme: Types.UITheme, slab: GuiObject, rotation: number?)
	local tone = GLLayoutKit.Tile(theme, "halftone", theme.Colors.Stroke, 0.55, "HalftoneEdge")
	tone.ZIndex = (slab.ZIndex or 1) + 1
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation or 0
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.55, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = tone
	tone.Parent = slab
	return tone
end

-- Decorative shard fragments: small rotated accent slabs that echo the main
-- slant. Their absence is what makes a GL screen read "clean" instead of
-- "explosive". Count/spread are tokens so other packs can dial to zero.
function GLLayoutKit.Shards(theme: Types.UITheme, parent: GuiObject, origin: UDim2, opts: { count: number?, spread: number?, seed: number? }?)
	local o = opts or {}
	local c = comic(theme)
	local count = o.count or c.shardCount or 8
	local spread = o.spread or c.shardSpread or 180
	local palette = { theme.Colors.Primary, theme.Arcade.HeaderRed, theme.Colors.Stroke, theme.Arcade.Gold }
	-- Deterministic scatter: no Math.random, so layouts are reproducible.
	local seed = o.seed or 7
	for i = 1, count do
		local a = (i * 2.399963 + seed) -- golden-angle walk
		local dx = math.cos(a) * spread * (0.35 + (i % 4) * 0.22)
		local dy = math.sin(a) * spread * 0.42 * (0.4 + (i % 3) * 0.3)
		local shard = UIStyler.Frame("Shard" .. i)
		shard.BackgroundColor3 = palette[(i % #palette) + 1]
		shard.BorderSizePixel = 0
		shard.AnchorPoint = Vector2.new(0.5, 0.5)
		shard.Position = UDim2.new(origin.X.Scale, origin.X.Offset + dx, origin.Y.Scale, origin.Y.Offset + dy)
		local long = 14 + (i % 5) * 12
		shard.Size = UDim2.fromOffset(long, 4 + (i % 3) * 3)
		shard.Rotation = GLLayoutKit.TILT * (2 + (i % 4))
		shard.ZIndex = 3
		shard.Parent = parent
	end
end

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
-- THE PAGE. Value structure per the reference: a LIGHT PAPER content surface
-- (double-framed: heavy black outer + thin gold inner) sitting inside DARK
-- chrome — dark window frame, dark header slabs, dark currency chips. The
-- squint test is the gate: light centre, dark edge, one big diagonal.
--
-- `titleText` may carry TWO words separated by "|" for the reference's
-- two-tone header ("CRAZY | HUNDRED DRAWS"): the first lands huge and
-- near-black on a gold slab, the second white on a black slab, mid-collision.
function GLLayoutKit.Page(theme: Types.UITheme, root: Instance, opts: {
	titleText: string,
	subtitleText: string?,
	sizePx: Vector2?,
	onClose: (() -> ())?,
	showClose: boolean?,
	characterArt: boolean?,
}): Page
	local shadows = {}
	local ink = theme.Colors.Stroke
	local cream = theme.Colors.TextPrimary
	local gold = theme.Arcade.Gold
	local paperInk = GLLayoutKit.PaperInk(theme)
	local size = opts.sizePx or Vector2.new(1010, 660)

	local dim = UIStyler.Frame("Dim")
	dim.BackgroundColor3 = theme.Colors.Overlay
	dim.BackgroundTransparency = 0.45
	dim.Size = UDim2.fromScale(1, 1)
	dim.Parent = root

	-- The DARK window frame. ClipsDescendants stays false on purpose: the
	-- banner, close, character art and shards must break these edges.
	local panel = UIStyler.Frame("GLPanel")
	panel.BackgroundColor3 = theme.Arcade.NearBlack
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, -6, 0.5, 6)
	panel.Size = UDim2.fromOffset(size.X, size.Y)
	panel.ClipsDescendants = false
	panel.Parent = root
	UIStyler.Stroke(ink, 4, 0).Parent = panel
	GLLayoutKit.Shadow(theme, panel, "lg", shadows)

	local tornBottom = GLLayoutKit.Slice(theme, "edgeTorn", theme.Colors.Background, "TornBottom")
	tornBottom.AnchorPoint = Vector2.new(0, 1)
	tornBottom.Position = UDim2.new(0, 0, 1, 2)
	tornBottom.Size = UDim2.new(1, 0, 0, 22)
	tornBottom.ZIndex = 20
	tornBottom.Parent = panel

	-- ---- TWO-TONE HEADER: two slabs, mismatched sizes, mid-collision ----
	local primaryWord, secondaryWord = string.match(opts.titleText, "^(.-)%s*|%s*(.*)$")
	if not primaryWord then
		primaryWord, secondaryWord = opts.titleText, nil
	end

	-- Slab A: the red banner slash carrying the SECONDARY (or whole) string.
	local banner = GLLayoutKit.Slice(theme, "bannerSlash", theme.Arcade.HeaderRed, "Banner")
	banner.Position = UDim2.fromOffset(-26, -38)
	banner.Size = UDim2.fromOffset(470, 88)
	banner.Rotation = GLLayoutKit.TILT
	banner.ZIndex = 12
	banner.Parent = panel
	GLLayoutKit.Shadow(theme, banner, "md", shadows)
	local innerRule = GLLayoutKit.Slice(theme, "bannerSlashInner", gold, "BannerInner")
	innerRule.Size = UDim2.fromScale(1, 1)
	innerRule.ZIndex = 13
	innerRule.Parent = banner
	-- Halftone here is an EDGE treatment on the accent slab (P1-1).
	GLLayoutKit.HalftoneEdge(theme, banner, 200)
	local lines = GLLayoutKit.Tile(theme, "actionLines", ink, 0.9, "BannerLines")
	lines.Size = UDim2.new(0.4, 0, 1, 0)
	lines.Position = UDim2.fromScale(0.6, 0)
	lines.ZIndex = 13
	lines.Parent = banner

	local title: TextLabel
	if secondaryWord and secondaryWord ~= "" then
		-- Gold slab: the primary shout, huge, near-black italic, colliding
		-- over the red slash's leading edge.
		local goldSlab = GLLayoutKit.Slice(theme, "chipPaper", gold, "TitleSlabA")
		goldSlab.Position = UDim2.fromOffset(6, -30)
		goldSlab.Size = UDim2.fromOffset(276, 76)
		goldSlab.Rotation = GLLayoutKit.TILT
		goldSlab.ZIndex = 15
		goldSlab.Parent = panel
		GLLayoutKit.Shadow(theme, goldSlab, "md", shadows)
		local primary = GLLayoutKit.Text(theme, 58, paperInk, "TitlePrimary")
		primary.Text = string.upper(primaryWord)
		primary.Size = UDim2.fromScale(1, 1)
		primary.ZIndex = 16
		primary.Parent = goldSlab
		-- The secondary rides the red slash, smaller and cream.
		title = GLLayoutKit.Text(theme, 32, cream, "Title")
		title.Text = string.upper(secondaryWord)
		title.TextXAlignment = Enum.TextXAlignment.Right
		title.Position = UDim2.fromOffset(20, 8)
		title.Size = UDim2.new(1, -40, 1, -16)
	else
		title = GLLayoutKit.Text(theme, 46, cream, "Title")
		title.Text = string.upper(primaryWord)
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Position = UDim2.fromOffset(46, 6)
		title.Size = UDim2.new(1, -60, 1, -12)
	end
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.ZIndex = 14
	title.Parent = banner

	-- Subtitle chip: small black slab below-right of the header.
	local subtitle = GLLayoutKit.Text(theme, 15, cream, "Subtitle")
	do
		local chip = GLLayoutKit.Slice(theme, "chipPaper", theme.Arcade.NearBlack2, "SubtitleChip")
		chip.Position = UDim2.fromOffset(300, 40)
		chip.Size = UDim2.fromOffset(340, 30)
		chip.Rotation = GLLayoutKit.TILT * 0.5
		chip.ZIndex = 11
		chip.Visible = opts.subtitleText ~= nil and opts.subtitleText ~= ""
		chip.Parent = panel
		GLLayoutKit.Shadow(theme, chip, "sm", shadows)
		subtitle.Text = opts.subtitleText and string.upper(opts.subtitleText) or ""
		subtitle.Size = UDim2.fromScale(1, 1)
		subtitle.ZIndex = 12
		subtitle.Parent = chip
	end

	-- Shard fragments near the header's trailing edge and the lower-left.
	GLLayoutKit.Shards(theme, panel, UDim2.new(1, -120, 0, -10), { seed = 3 })
	GLLayoutKit.Shards(theme, panel, UDim2.new(0, 40, 1, -40), { seed = 11, count = 5 })

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

	-- ---- THE PAPER SURFACE: the light content field, double-framed ----
	local content = UIStyler.Frame("Content")
	content.BackgroundColor3 = GLLayoutKit.Paper(theme)
	content.BackgroundTransparency = 0
	content.Position = UDim2.fromOffset(26, 92)
	content.Size = UDim2.new(1, -52, 1, -124)
	content.ClipsDescendants = false
	content.ZIndex = 2
	content.Parent = panel
	GLLayoutKit.DoubleFrame(theme, content)
	GLLayoutKit.Shadow(theme, content, "sm", shadows)

	-- ---- CHARACTER ART: must BREAK the panel (left edge + above the top).
	-- ClipsDescendants is false on both the panel and this container ON
	-- PURPOSE — it fights the usual instinct, which is exactly why the
	-- reference reads as art standing in front of a window rather than art
	-- pasted inside a box.
	local characterSlot = UIStyler.Frame("CharacterSlot")
	characterSlot.BackgroundTransparency = 1
	characterSlot.AnchorPoint = Vector2.new(0, 1)
	characterSlot.Position = UDim2.new(0, -152, 1, 26)
	characterSlot.Size = UDim2.new(0, 330, 1.06, 0)
	characterSlot.ClipsDescendants = false
	characterSlot.ZIndex = 30
	characterSlot.Visible = opts.characterArt ~= false
	characterSlot.Parent = panel
	do
		-- The orange backing slab, rotated ~12deg: this is what makes the art
		-- read as ON TOP OF the panel rather than cut out of it.
		local slab = UIStyler.Frame("BackingSlab")
		slab.BackgroundColor3 = theme.Colors.Primary
		slab.BorderSizePixel = 0
		slab.AnchorPoint = Vector2.new(0.5, 1)
		slab.Position = UDim2.new(0.5, 10, 1, -30)
		slab.Size = UDim2.new(0, 250, 0, 430)
		slab.Rotation = 12
		slab.ZIndex = 30
		slab.Parent = characterSlot
		UIStyler.Stroke(ink, 4, 0).Parent = slab
		GLLayoutKit.Shadow(theme, slab, "md", shadows)
		GLLayoutKit.HalftoneEdge(theme, slab, 90)

		local art = GLLayoutKit.Slice(theme, "cardCut", theme.Arcade.NearBlack2, "CharacterArt")
		art.AnchorPoint = Vector2.new(0.5, 1)
		art.Position = UDim2.new(0.5, -14, 1, -24)
		art.Size = UDim2.new(0, 186, 0.78, 0)
		art.ZIndex = 32
		art.Parent = characterSlot
		local label = GLLayoutKit.Text(theme, 18, cream, "CharacterArtLabel")
		label.Text = "ART SLOT\nCHARACTER"
		label.Size = UDim2.fromScale(1, 1)
		label.Rotation = GLLayoutKit.TILT * 2
		label.ZIndex = 33
		label.Parent = art
	end

	return {
		dim = dim,
		panel = panel,
		banner = banner,
		title = title,
		subtitle = subtitle,
		topRight = topRight,
		content = content,
		close = close,
		characterSlot = characterSlot,
		shadows = shadows,
	}
end

export type Tile = {
	root: TextButton,
	frame: ImageLabel,
	art: ImageLabel,
	artLabel: TextLabel,
	countChip: ImageLabel,
	countText: TextLabel,
	lock: Frame,
	shadow: any,
}

-- THE ITEM TILE ATOM (portrait rarity frame). This is the reference's
-- repeating unit: ~4:5 portrait, violet fill, a coloured RARITY BORDER, a
-- count chip bottom-right, and a lock overlay when unavailable. Dense grids
-- of these — not airy landscape cards — carry the reference's rhythm.
function GLLayoutKit.ItemTile(theme: Types.UITheme, parent: Instance, sink: { any }?): Tile
	local c = comic(theme)
	local ink = theme.Colors.Stroke
	local root = Instance.new("TextButton")
	root.Name = "GLTile"
	root.BackgroundTransparency = 1
	root.Text = ""
	root.AutoButtonColor = false
	root.Parent = parent
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 0.8 -- 4:5 portrait
	ratio.DominantAxis = Enum.DominantAxis.Width
	ratio.Parent = root

	local frame = GLLayoutKit.Slice(theme, "cardCut", c.surfaceTile or Color3.fromRGB(92, 78, 130), "TileFrame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.Parent = root
	local shadow = GLLayoutKit.Shadow(theme, frame, "sm", sink)
	-- The rarity border rides its own stroke so the ramp swaps ONE value.
	UIStyler.Stroke(c.rarityRare or theme.Arcade.Gold, 2, 0).Parent = frame

	local art = GLLayoutKit.Slice(theme, "artSlot", theme.Colors.Disabled, "TileArt")
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.45)
	art.Size = UDim2.new(0.78, 0, 0.6, 0)
	art.ZIndex = 3
	art.Parent = frame
	local artLabel = GLLayoutKit.Text(theme, 11, theme.Colors.TextPrimary, "TileArtLabel")
	artLabel.Text = "ART"
	artLabel.Size = UDim2.fromScale(1, 1)
	artLabel.ZIndex = 4
	artLabel.Parent = art

	-- Count chip, bottom-right: dark chip, gold numeral.
	local countChip = GLLayoutKit.Slice(theme, "chipPaper", theme.Arcade.NearBlack, "CountChip")
	countChip.AnchorPoint = Vector2.new(1, 1)
	countChip.Position = UDim2.new(1, -4, 1, -4)
	countChip.Size = UDim2.fromOffset(46, 24)
	countChip.ZIndex = 5
	countChip.Parent = frame
	local countText = GLLayoutKit.Text(theme, 16, theme.Arcade.Gold, "CountText")
	countText.Size = UDim2.fromScale(1, 1)
	countText.ZIndex = 6
	countText.Parent = countChip

	-- Lock overlay for unavailable tiles.
	local lock = UIStyler.Frame("Lock")
	lock.BackgroundColor3 = theme.Colors.Overlay
	lock.BackgroundTransparency = 0.45
	lock.Size = UDim2.fromScale(1, 1)
	lock.Visible = false
	lock.ZIndex = 7
	lock.Parent = frame
	-- PACK LAW: never an emoji — every glyph comes from the ICON GALLERY.
	local glyph = IconArchive.Image(lock, "lock", 34)
	glyph.Name = "LockGlyph"
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.5)
	glyph.ZIndex = 8

	UIChrome.Animate(theme, root, frame)
	return {
		root = root, frame = frame, art = art, artLabel = artLabel,
		countChip = countChip, countText = countText, lock = lock, shadow = shadow,
	}
end

-- Rarity ramp: swaps the tile BORDER colour only (never the fill).
function GLLayoutKit.SetTileRarity(theme: Types.UITheme, tile: Tile, rarity: string)
	local c = comic(theme)
	local stroke = tile.frame:FindFirstChildOfClass("UIStroke")
	if not stroke then
		return
	end
	if rarity == "giga" then
		stroke.Color = c.rarityGiga or Color3.fromRGB(255, 250, 236)
		stroke.Thickness = 3
	elseif rarity == "rare" then
		stroke.Color = c.rarityRare or theme.Arcade.Gold
		stroke.Thickness = 2
	else
		stroke.Color = c.rarityCommon or Color3.fromRGB(176, 168, 158)
		stroke.Thickness = 2
	end
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
