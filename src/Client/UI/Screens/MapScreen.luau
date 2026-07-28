--!strict
-- MAP screen — the full-screen world map, Pottery Clash arcade family. One
-- §7.4 modal card holds a clipped map viewport on the left and a legend column
-- on the right.
--
-- The map surface is a placeholder: no baked map art exists yet, so it is an
-- ImageLabel (drop a texture id on `self._surface.Image` and the whole screen
-- is done) over a subtle grid drawn from thin Frames, with named region blocks
-- so the empty plate still reads as a place.
--
-- Interaction:
--   * drag to pan — clamped so the world edges can never leave the viewport;
--   * zoom on the shared UISliderComponent AND the scroll wheel, anchored on
--     the viewport centre; markers counter-scale so they stay a constant size;
--   * pins are icon markers at NORMALISED x/y (0..1 of the map), so the same
--     pin data survives any future map art;
--   * the legend toggles each pin layer on and off in place;
--   * clicking a pin opens a callout whose FAST TRAVEL raises the shared
--     confirm modal (locked destinations dim and answer with a toast).
--
-- Show(data) = a list of pins { id, name, kind, x, y, unlocked }; kind is
-- "quest" | "vendor" | "teleport" | "player". Falls back to the demo map below.
--
-- Every input connection is made on show and dropped on hide (doc §5.4).

local UserInputService = game:GetService("UserInputService")

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local GPControlKit = require(script.Parent.Parent.Framework.GPControlKit)
local UIScreenBase = require(script.Parent.UIScreenBase)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)
local UISliderComponent = require(script.Parent.Parent.Components.UISliderComponent)
local UIToggleComponent = require(script.Parent.Parent.Components.UIToggleComponent)
local UIProgressBarComponent = require(script.Parent.Parent.Components.UIProgressBarComponent)

type Pin = { id: string, name: string, kind: string, x: number, y: number, unlocked: boolean? }

local MapScreen = setmetatable({}, { __index = UIScreenBase })
MapScreen.__index = MapScreen

-- Fixed px at the 1650×1020 baseline. Card 1380×800 → content 1352×712.
local CARD = Vector2.new(1380, 800)
local VIEW_W = 1040
local VIEW_H = 644
local ZOOM_ROW_Y = 656
local ZOOM_ROW_H = 44
local LEGEND_X = 1056
local LEGEND_W = 296
local LEGEND_H = 712
local PAD = 14

-- The map world, in baseline px. Kept larger than the viewport at MIN_ZOOM so
-- the clamp maths always has slack in both axes.
local WORLD_W = 1600
local WORLD_H = 1000
local GRID_STEP = 100
local MIN_ZOOM = 0.7
local MAX_ZOOM = 2.2
local ZOOM_STEP = 0.12 -- per wheel notch
local PIN_BOX = 46
local PIN_WELL = 40

local WHITE = Color3.new(1, 1, 1)

-- GP (Girly Pop) geometry. GPLayoutKit.Page spends 48px more vertical chrome
-- than the §7.4 modal card (taller ribbon + scalloped lip), so the GP card is
-- authored 48px TALLER and its content rect lands pixel-identical to the
-- classic one. Every px constant above is therefore reused verbatim — same
-- viewport, same legend column, same zoom row — which is what keeps the pan
-- and zoom maths (VIEW_W / VIEW_H) valid without a single logic change.
local GP_CARD_GROW = 48
local GP_LAYER_ROW_H = 54
local GP_LAYER_ROW_STEP = 62
local GP_LOCKED_ROW_STEP = 32
local GP_LOCKED_LIMIT = 4

-- Pin kinds: icon + the identity colour (doc §3.3 colour = identity).
local KIND_ORDER = { "quest", "vendor", "teleport", "player" }
local KIND_ICON: { [string]: string } = {
	quest = "target",
	vendor = "cart",
	teleport = "teleport",
	player = "player",
}
local KIND_LABEL: { [string]: string } = {
	quest = "QUESTS",
	vendor = "VENDORS",
	teleport = "TELEPORTS",
	player = "PLAYERS",
}

local REGIONS = {
	{ name = "KILN FLATS", x = 0.04, y = 0.06, w = 0.42, h = 0.36 },
	{ name = "GLAZE BAY", x = 0.52, y = 0.08, w = 0.42, h = 0.3 },
	{ name = "THE SLIP MINES", x = 0.06, y = 0.5, w = 0.36, h = 0.42 },
	{ name = "OXIDE RIDGE", x = 0.48, y = 0.46, w = 0.46, h = 0.46 },
}

local DEMO_PINS: { Pin } = {
	{ id = "q1", name = "THE CRACKED KILN", kind = "quest", x = 0.18, y = 0.22, unlocked = true },
	{ id = "q2", name = "A BOWL FOR BRENDA", kind = "quest", x = 0.63, y = 0.19, unlocked = true },
	{ id = "q3", name = "DEEP SLIP DESCENT", kind = "quest", x = 0.25, y = 0.71, unlocked = false },
	{ id = "v1", name = "TILDA'S TOOL CART", kind = "vendor", x = 0.35, y = 0.34, unlocked = true },
	{ id = "v2", name = "BAYSIDE GLAZE STALL", kind = "vendor", x = 0.74, y = 0.31, unlocked = true },
	{ id = "v3", name = "RIDGE BLACK MARKET", kind = "vendor", x = 0.82, y = 0.66, unlocked = false },
	{ id = "t1", name = "FLATS WAYSTONE", kind = "teleport", x = 0.1, y = 0.14, unlocked = true },
	{ id = "t2", name = "BAY WAYSTONE", kind = "teleport", x = 0.9, y = 0.14, unlocked = true },
	{ id = "t3", name = "MINE WAYSTONE", kind = "teleport", x = 0.12, y = 0.86, unlocked = true },
	{ id = "t4", name = "RIDGE WAYSTONE", kind = "teleport", x = 0.9, y = 0.88, unlocked = false },
	{ id = "p1", name = "CLAYCRUSHER", kind = "player", x = 0.44, y = 0.52, unlocked = true },
	{ id = "p2", name = "KILNKING", kind = "player", x = 0.58, y = 0.62, unlocked = true },
}

local function kindColor(theme: Types.UITheme, kind: string): Color3
	if kind == "quest" then
		return theme.Arcade.Gold
	elseif kind == "vendor" then
		return theme.Arcade.Green
	elseif kind == "teleport" then
		return theme.Arcade.Blue
	end
	return theme.Semantic.Seat1
end

-- The map's copy is authored in ARCADE CAPS ("KILN FLATS", "QUESTS"). Pack law
-- 5 forbids all-caps body copy, so the GP build title-cases the same strings on
-- the way to the screen — presentation only, the data is untouched.
local function gpTitle(text: string): string
	return (string.gsub(string.lower(text), "(%a[%w']*)", function(word: string)
		return string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2)
	end))
end

-- IconArchive returns an ImageLabel when the art exists and an outlined glyph
-- TextLabel when it doesn't; tint whichever came back.
local function tint(icon: GuiObject, color: Color3)
	if icon:IsA("ImageLabel") then
		icon.ImageColor3 = color
	elseif icon:IsA("TextLabel") then
		icon.TextColor3 = color
	end
end

function MapScreen.new()
	local self = UIScreenBase.new("MapScreen", 10)
	self._pins = DEMO_PINS
	self._zoom = 1
	self._pan = Vector2.new(0, 0)
	self._dragging = false
	self._dragStart = Vector2.new(0, 0)
	self._panStart = Vector2.new(0, 0)
	self._markers = {} :: { { pin: Pin, frame: Frame, scale: UIScale } }
	self._layerOn = {} :: { [string]: boolean }
	self._toggles = {} :: { any }
	self._conns = {} :: { RBXScriptConnection }
	self._selected = nil :: Pin?
	-- GP branch state: the flag every shared method below reads, plus the three
	-- shadow sinks (page chrome, legend, pin layer) the budget is released from.
	self._gp = false
	self._gpShadows = nil :: { any }?
	self._gpLegendShadows = nil :: { any }?
	self._gpPinShadows = nil :: { any }?
	for _, kind in KIND_ORDER do
		self._layerOn[kind] = true
	end
	return setmetatable(self, MapScreen)
end

function MapScreen:_Toast(text: string, variant: string)
	local hud = self.ScreenController and self.ScreenController:GetScreen("hud")
	if hud then
		hud:PushToast({ text = text, variant = variant })
	end
end

-- Real screen px → baseline px: everything here is authored at 1650×1020, and
-- AbsolutePosition/AbsoluteSize come back already multiplied by that UIScale.
function MapScreen:_BaselineScale(): number
	local scale = self._baselineScale
	if scale and scale.Scale > 0 then
		return scale.Scale
	end
	return 1
end

-- ---- build -------------------------------------------------------------

function MapScreen:_BuildContent()
	-- GP layout language: the same map, cut in cream paper and petal corners.
	if self:LayoutKit() == "GP" then
		self._gp = true
		self:_BuildGPLayout()
		return
	end
	self._gp = false

	local theme = self:GetTheme()
	local baseline = self.Root:FindFirstChild("BaselineScale")
	if baseline and baseline:IsA("UIScale") then
		self._baselineScale = baseline
	end

	local modal = UIChrome.ModalCard(theme, self.Root, {
		title = self:_R("MAP"),
		sizePx = CARD,
		onClose = function()
			self.ScreenController:HideScreen("map")
		end,
	})
	self._modal = modal
	local content = modal.content

	-- Viewport: the clipping window onto the world.
	local viewport = UIStyler.Frame("Viewport")
	viewport.BackgroundColor3 = theme.Arcade.NearBlack
	viewport.BackgroundTransparency = 0
	viewport.Size = UDim2.fromOffset(VIEW_W, VIEW_H)
	viewport.ClipsDescendants = true
	-- Active so the drag-to-pan InputBegan fires for touch as well as mouse;
	-- the pin buttons are children and still take their own clicks first.
	viewport.Active = true
	UIChrome.Stroke(theme, "Arcade").Parent = viewport
	viewport.Parent = content
	self._viewport = viewport

	-- World: fixed baseline-px canvas, moved by pan and grown by a UIScale for
	-- zoom (anchored top-left, which is what the clamp maths assumes).
	local world = UIStyler.Frame("World")
	world.BackgroundTransparency = 1
	world.AnchorPoint = Vector2.new(0, 0)
	world.Size = UDim2.fromOffset(WORLD_W, WORLD_H)
	world.Parent = viewport
	self._world = world

	local worldScale = Instance.new("UIScale")
	worldScale.Name = "ZoomScale"
	worldScale.Parent = world
	self._worldScale = worldScale

	-- The map plate itself. No baked art yet: this is the placeholder that a
	-- real texture id drops straight into.
	local surface = Instance.new("ImageLabel")
	surface.Name = "MapSurface"
	surface.BackgroundColor3 = theme.Arcade.NearBlack2
	surface.BackgroundTransparency = 0
	surface.BorderSizePixel = 0
	surface.Image = ""
	surface.ScaleType = Enum.ScaleType.Stretch
	surface.Size = UDim2.fromScale(1, 1)
	surface.Parent = world
	self._surface = surface

	self:_BuildRegions()
	self:_BuildGrid()

	-- Zoom row under the map: the shared slider plus a reset.
	local zoomRow = UIStyler.Frame("ZoomRow")
	zoomRow.BackgroundTransparency = 1
	zoomRow.Position = UDim2.fromOffset(0, ZOOM_ROW_Y)
	zoomRow.Size = UDim2.fromOffset(VIEW_W, ZOOM_ROW_H)
	zoomRow.Parent = content

	local slider = UISliderComponent.new()
	slider:Create(zoomRow, {
		label = "ZOOM",
		min = MIN_ZOOM,
		max = MAX_ZOOM,
		step = 0.05,
		value = self._zoom,
		decimals = 2,
		size = UDim2.fromOffset(760, ZOOM_ROW_H),
		onChanged = function(value: number)
			self:_SetZoom(value, true)
		end,
	})
	self._slider = slider

	local reset = UIButtonComponent.new()
	reset:Create(zoomRow, {
		text = self:_R("RESET VIEW"),
		variant = "Ghost",
		size = UDim2.fromOffset(200, 42),
		position = UDim2.new(1, 0, 0.5, 0),
		anchorPoint = Vector2.new(1, 0.5),
		onClick = function()
			self:_ResetView()
		end,
	})
	self._resetButton = reset

	self:_BuildLegend(content)
	self:_BuildCallout()
	self:_RenderPins()
	self:_ResetView()
end

-- ========================================================================
-- GIRLY POP
-- ========================================================================
-- The same window, the same 1040×644 viewport, the same 296px legend column
-- and the same twelve pins across four toggleable layers — re-cut in warm
-- cream, petal corners and hue-matched shade. Nothing is dropped: every stat
-- the arcade legend prints (per-layer counts, the discovery ruler, the named
-- locked destinations, the control hint) prints here too.
--
-- The controls are built from GPControlKit rather than the shared components
-- because UIChrome.Stroke resolves to BLACK under this pack and UIStyleEnforcer
-- backstops solid buttons with a black rim — both break pack law 1. The kit's
-- Slider / Toggle / Button / Meter carry the SAME Set / SetContent / Destroy
-- contract the components did, which is why _RebuildLegend, _SetZoom,
-- _ResetView, _OpenCallout and Destroy below are untouched.

function MapScreen:_BuildGPLayout()
	local theme = self:GetTheme()
	local baseline = self.Root:FindFirstChild("BaselineScale")
	if baseline and baseline:IsA("UIScale") then
		self._baselineScale = baseline
	end

	local page = GPLayoutKit.Page(theme, self.Root, {
		titleText = gpTitle(self:_R("MAP")),
		subtitleText = "Kiln Flats to Oxide Ridge — drag to wander.",
		sizePx = Vector2.new(CARD.X, CARD.Y + GP_CARD_GROW),
		onClose = function()
			self.ScreenController:HideScreen("map")
		end,
	})
	self._modal = page
	self._gpShadows = page.shadows
	self._gpPinShadows = {}
	self._gpLegendShadows = {}
	local content = page.content

	-- The map window. Its fill and the map plate's fill are DELIBERATELY the
	-- same colour: ClipsDescendants clips to the RECT, not to the UICorner, so
	-- a contrasting plate would square off the window's rounded corners. Same
	-- colour on both sides of that seam and the corner reads clean.
	local viewFill = theme.Colors.SurfaceRaised
	local viewport = UIStyler.Frame("Viewport")
	viewport.BackgroundColor3 = viewFill
	viewport.BackgroundTransparency = 0
	viewport.Size = UDim2.fromOffset(VIEW_W, VIEW_H)
	viewport.ClipsDescendants = true
	-- Active so drag-to-pan's InputBegan fires for touch as well as mouse; the
	-- pin buttons are children and still take their own clicks first.
	viewport.Active = true
	viewport.Parent = content
	UIStyler.Corner(theme.Radii.Medium).Parent = viewport
	GPLayoutKit.SoftStroke(theme, viewport, viewFill)
	GPLayoutKit.Shadow(theme, viewport, "md", self._gpShadows, viewFill)
	self._viewport = viewport

	local world = UIStyler.Frame("World")
	world.BackgroundTransparency = 1
	world.AnchorPoint = Vector2.new(0, 0)
	world.Size = UDim2.fromOffset(WORLD_W, WORLD_H)
	world.Parent = viewport
	self._world = world

	local worldScale = Instance.new("UIScale")
	worldScale.Name = "ZoomScale"
	worldScale.Parent = world
	self._worldScale = worldScale

	-- Still the placeholder plate a real texture id drops straight into.
	local surface = Instance.new("ImageLabel")
	surface.Name = "MapSurface"
	surface.BackgroundColor3 = viewFill
	surface.BackgroundTransparency = 0
	surface.BorderSizePixel = 0
	surface.Image = ""
	surface.ScaleType = Enum.ScaleType.Stretch
	surface.Size = UDim2.fromScale(1, 1)
	surface.Parent = world
	self._surface = surface

	-- Clay speckle across the whole world so the empty plate reads as paper
	-- rather than as a missing texture.
	local studio = ((theme :: any).DialectTokens and (theme :: any).DialectTokens.studio) or {}
	local grain = GPLayoutKit.Tile(
		theme,
		studio.patternKey or "speckle",
		GPLayoutKit.Deepen(theme, viewFill, 1),
		studio.speckleTransparency or 0.94,
		"ClayGrain"
	)
	grain.ZIndex = 1
	grain.Parent = surface

	self:_BuildGPRegions()
	self:_BuildGPGrid()

	-- Zoom row under the map: the same slider range and the same reset.
	local zoomRow = UIStyler.Frame("ZoomRow")
	zoomRow.BackgroundTransparency = 1
	zoomRow.Position = UDim2.fromOffset(0, ZOOM_ROW_Y)
	zoomRow.Size = UDim2.fromOffset(VIEW_W, ZOOM_ROW_H)
	zoomRow.Parent = content

	self._slider = GPControlKit.Slider(theme, zoomRow, {
		label = "Zoom",
		min = MIN_ZOOM,
		max = MAX_ZOOM,
		step = 0.05,
		value = self._zoom,
		decimals = 2,
		size = UDim2.fromOffset(760, ZOOM_ROW_H),
		sink = self._gpShadows,
		onChanged = function(value: number)
			self:_SetZoom(value, true)
		end,
	})

	self._resetButton = GPControlKit.Button(theme, zoomRow, {
		text = gpTitle(self:_R("RESET VIEW")),
		fill = theme.Colors.Secondary,
		index = 1,
		size = UDim2.fromOffset(200, 42),
		position = UDim2.new(1, 0, 0.5, 0),
		anchorPoint = Vector2.new(1, 0.5),
		sink = self._gpShadows,
		onClick = function()
			self:_ResetView()
		end,
	})

	self:_BuildLegend(content)
	self:_BuildGPCallout()
	self:_RenderPins()
	self:_ResetView()
end

-- Hand-painted regions: alternating pastel washes with alternating petal sets,
-- so the map reads as something somebody made rather than a survey printout.
function MapScreen:_BuildGPRegions()
	local theme = self:GetTheme()
	local washes = theme.Arcade.ShopAccents
	for index, region in REGIONS do
		local wash = washes[(index - 1) % #washes + 1]
		local block = UIStyler.Frame("Region_" .. region.name)
		block.BackgroundColor3 = wash
		block.BackgroundTransparency = 0.62
		block.Position = UDim2.fromScale(region.x, region.y)
		block.Size = UDim2.fromScale(region.w, region.h)
		block.ZIndex = 2
		block.Parent = self._world
		GPLayoutKit.Petal(theme, block, index)
		local rim = GPLayoutKit.SoftStroke(theme, block, wash)
		rim.Transparency = 0.45

		-- Ink, not a tinted near-white: a region name is body-sized copy and
		-- has to clear 4.5:1 on whatever wash it lands on.
		local label = GPLayoutKit.Text(theme, 22, theme.Colors.TextPrimary, "Name")
		label.Text = gpTitle(region.name)
		label.TextTransparency = 0.15
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Position = UDim2.fromOffset(16, 12)
		label.Size = UDim2.new(1, -32, 0, 28)
		label.ZIndex = 3
		label.Parent = block
	end
end

-- The survey grid in the studio dialect's sage rule colour, held far back.
function MapScreen:_BuildGPGrid()
	local theme = self:GetTheme()
	local studio = ((theme :: any).DialectTokens and (theme :: any).DialectTokens.studio) or {}
	local sage = studio.rule or theme.Studio.Tan
	local function line(x: number, y: number, width: number, height: number)
		local tick = UIStyler.Frame("Grid")
		tick.BackgroundColor3 = sage
		tick.BackgroundTransparency = 0.72
		tick.Position = UDim2.fromOffset(x, y)
		tick.Size = UDim2.fromOffset(width, height)
		tick.ZIndex = 1
		tick.Parent = self._world
	end
	for x = GRID_STEP, WORLD_W - 1, GRID_STEP do
		line(x, 0, 2, WORLD_H)
	end
	for y = GRID_STEP, WORLD_H - 1, GRID_STEP do
		line(0, y, WORLD_W, 2)
	end
end

-- The legend column, at the arcade legend's full density: a title, one row per
-- layer carrying its icon, its NAME AND COUNT and its toggle, the discovery
-- ruler, every locked destination named, and the control hint.
function MapScreen:_BuildGPLegend(parent: Instance)
	local theme = self:GetTheme()
	self._legendParent = parent
	-- The legend is rebuilt whole on new pin data; its shadow handles have to
	-- go back to the budget before the new ones are taken.
	GPLayoutKit.ReleaseShadows(self._gpLegendShadows)
	self._gpLegendShadows = self._gpLegendShadows or {}
	local sink = self._gpLegendShadows

	local legendFill = theme.Colors.SurfaceRaised
	local legend = UIStyler.Frame("Legend")
	legend.BackgroundColor3 = legendFill
	legend.BackgroundTransparency = 0
	legend.Position = UDim2.fromOffset(LEGEND_X, 0)
	legend.Size = UDim2.fromOffset(LEGEND_W, LEGEND_H)
	legend.Parent = parent
	GPLayoutKit.CornerSet(theme, legend, "Petal")
	GPLayoutKit.SoftStroke(theme, legend, legendFill)
	GPLayoutKit.Shadow(theme, legend, "md", sink, legendFill)
	self._legend = legend

	local innerW = LEGEND_W - PAD * 2

	local title = GPLayoutKit.Text(theme, 24, theme.Colors.TextPrimary, "Title")
	title.Text = "Legend"
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(PAD, 12)
	title.Size = UDim2.fromOffset(innerW, 28)
	title.Parent = legend

	local rule = GPLayoutKit.Divider(theme, legend)
	rule.Position = UDim2.fromOffset(PAD, 44)
	rule.Size = UDim2.new(0, innerW, 0, rule.Size.Y.Offset)

	for index, kind in KIND_ORDER do
		local count = 0
		for _, pin in self._pins do
			if pin.kind == kind then
				count += 1
			end
		end

		local rowFill = theme.Colors.Surface
		local row = UIStyler.Frame("Layer_" .. kind)
		row.BackgroundColor3 = rowFill
		row.BackgroundTransparency = 0
		row.Position = UDim2.fromOffset(PAD, 56 + (index - 1) * GP_LAYER_ROW_STEP)
		row.Size = UDim2.fromOffset(innerW, GP_LAYER_ROW_H)
		row.Parent = legend
		GPLayoutKit.Petal(theme, row, index)
		GPLayoutKit.SoftStroke(theme, row, rowFill)
		GPLayoutKit.Shadow(theme, row, "sm", sink, rowFill)

		-- The whole row is the toggle's hit target (doc §11.6); the icon rides
		-- ABOVE it and, being an ImageLabel, never sinks the click.
		local toggle = GPControlKit.Toggle(theme, row, {
			label = string.format("%s (%d)", gpTitle(KIND_LABEL[kind]), count),
			value = self._layerOn[kind] ~= false,
			size = UDim2.fromScale(1, 1),
			onChanged = function(on: boolean)
				self:_SetLayer(kind, on)
			end,
		})
		toggle.label.Position = UDim2.fromOffset(48, 0)
		toggle.label.Size = UDim2.new(1, -(48 + 78), 1, 0)
		toggle.track.Position = UDim2.new(1, -12, 0.5, 0)
		table.insert(self._toggles, toggle)

		-- Through the kit wrapper, and deepened so a pastel identity colour still
		-- reads at 28px. IconArchive's GLYPH FALLBACK is born pure white with a
		-- pure black outline, which pack law 1 forbids outright.
		local icon = GPControlKit.Icon(theme, row, KIND_ICON[kind], 28, GPLayoutKit.Deepen(theme, kindColor(theme, kind), 1))
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 12, 0.5, 0)
		icon.ZIndex = row.ZIndex + 3
	end

	local discoveryY = 56 + #KIND_ORDER * GP_LAYER_ROW_STEP + 8
	local rule2 = GPLayoutKit.Divider(theme, legend)
	rule2.Position = UDim2.fromOffset(PAD, discoveryY)
	rule2.Size = UDim2.new(0, innerW, 0, rule2.Size.Y.Offset)

	local unlocked, locked = 0, {}
	for _, pin in self._pins do
		if pin.unlocked == false then
			table.insert(locked, pin)
		else
			unlocked += 1
		end
	end

	local discovery = GPLayoutKit.SectionLabel(theme, legend, "Discovery")
	discovery.Position = UDim2.fromOffset(PAD, discoveryY + 12)
	discovery.Size = UDim2.fromOffset(innerW, 24)

	-- Same ruler the arcade legend prints, with the fraction spelled out.
	self._progress = GPControlKit.Meter(theme, legend, {
		label = "Found",
		value = unlocked,
		maxValue = math.max(1, #self._pins),
		size = UDim2.fromOffset(innerW, 42),
		position = UDim2.fromOffset(PAD, discoveryY + 42),
	})

	local lockedY = discoveryY + 94
	local lockedTitle = GPLayoutKit.SectionLabel(theme, legend, string.format("Still to find (%d)", #locked))
	lockedTitle.Position = UDim2.fromOffset(PAD, lockedY)
	lockedTitle.Size = UDim2.fromOffset(innerW, 24)

	for index, pin in locked do
		if index > GP_LOCKED_LIMIT then
			break
		end
		local y = lockedY + 30 + (index - 1) * GP_LOCKED_ROW_STEP
		local lock = GPControlKit.Icon(theme, legend, "lock", 18, theme.Colors.TextSecondary)
		lock.Position = UDim2.fromOffset(PAD + 2, y + 5)

		local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Locked" .. index)
		label.Text = gpTitle(pin.name)
		label.RichText = false
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Position = UDim2.fromOffset(PAD + 28, y)
		label.Size = UDim2.fromOffset(innerW - 28, 26)
		label.Parent = legend
	end
	-- The list is capped at four, so say how many are hiding behind the cap
	-- rather than silently swallowing them.
	if #locked > GP_LOCKED_LIMIT then
		local more = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "LockedMore")
		more.Text = string.format("+%d more waiting", #locked - GP_LOCKED_LIMIT)
		more.TextXAlignment = Enum.TextXAlignment.Left
		more.Position = UDim2.fromOffset(PAD + 28, lockedY + 30 + GP_LOCKED_LIMIT * GP_LOCKED_ROW_STEP)
		more.Size = UDim2.fromOffset(innerW - 28, 22)
		more.Parent = legend
	end

	local hint = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Hint")
	hint.Text = "Drag the map to wander. Scroll or slide the zoom to lean in. Tap a pin to travel."
	hint.TextWrapped = true
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextYAlignment = Enum.TextYAlignment.Bottom
	hint.AnchorPoint = Vector2.new(0, 1)
	hint.Position = UDim2.new(0, PAD, 1, -PAD)
	hint.Size = UDim2.fromOffset(innerW, 110)
	hint.Parent = legend
end

-- The pin callout, on the cream card. Lives in the VIEWPORT (not the world) so
-- its type size stays constant under zoom, exactly like the classic one.
function MapScreen:_BuildGPCallout()
	local theme = self:GetTheme()
	local calloutFill = theme.Colors.Background

	local callout = UIStyler.Frame("Callout")
	callout.BackgroundColor3 = calloutFill
	callout.BackgroundTransparency = 0
	callout.AnchorPoint = Vector2.new(0.5, 1)
	callout.Size = UDim2.fromOffset(300, 132)
	callout.Visible = false
	callout.ZIndex = 6
	callout.Parent = self._viewport
	GPLayoutKit.CornerSet(theme, callout, "Petal")
	GPLayoutKit.SoftStroke(theme, callout, theme.Colors.Primary)
	GPLayoutKit.Shadow(theme, callout, "sm", self._gpShadows, theme.Colors.Primary)
	self._callout = callout

	local name = GPLayoutKit.Text(theme, 20, theme.Colors.TextPrimary, "Name")
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(14, 8)
	name.Size = UDim2.fromOffset(226, 26)
	name.ZIndex = 7
	name.Parent = callout
	self._calloutName = name

	local kindLabel = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextSecondary, "Kind")
	kindLabel.TextXAlignment = Enum.TextXAlignment.Left
	kindLabel.TextTruncate = Enum.TextTruncate.AtEnd
	kindLabel.Position = UDim2.fromOffset(14, 36)
	kindLabel.Size = UDim2.fromOffset(272, 22)
	kindLabel.ZIndex = 7
	kindLabel.Parent = callout
	self._calloutKind = kindLabel

	self._gpCalloutClose = GPControlKit.Button(theme, callout, {
		text = "X",
		fill = theme.Colors.SurfaceRaised,
		index = 1,
		textSize = 18,
		size = UDim2.fromOffset(30, 30),
		position = UDim2.new(1, -8, 0, 8),
		anchorPoint = Vector2.new(1, 0),
		zIndex = 7,
		sink = self._gpShadows,
		onClick = function()
			self:_CloseCallout()
		end,
	})

	-- Same SetContent contract the shared button had, so _OpenCallout's
	-- dimmed/undimmed call site is unchanged.
	self._travelButton = GPControlKit.Button(theme, callout, {
		text = gpTitle(self:_R("FAST TRAVEL")),
		fill = theme.Colors.Primary,
		size = UDim2.fromOffset(272, 46),
		position = UDim2.new(0.5, 0, 1, -10),
		anchorPoint = Vector2.new(0.5, 1),
		zIndex = 7,
		sink = self._gpShadows,
		onClick = function()
			self:_FastTravel()
		end,
	})
end

-- Pins as glazed buttons: a pill chip in the layer's identity colour casting a
-- shadow of its OWN hue, the layer icon deepened on top of it. Locked pins dim
-- in place and keep a whispered lock — the state still reads, it just does not
-- scold.
function MapScreen:_RenderGPPins()
	local theme = self:GetTheme()
	for _, marker in self._markers do
		marker.frame:Destroy()
	end
	table.clear(self._markers)
	GPLayoutKit.ReleaseShadows(self._gpPinShadows)
	self._gpPinShadows = self._gpPinShadows or {}
	local sink = self._gpPinShadows

	for _, pin in self._pins do
		local color = kindColor(theme, pin.kind)
		local unlocked = pin.unlocked ~= false

		local box = UIStyler.Frame("Pin_" .. pin.id)
		box.BackgroundTransparency = 1
		box.AnchorPoint = Vector2.new(0.5, 0.5)
		box.Position = UDim2.fromScale(pin.x, pin.y)
		box.Size = UDim2.fromOffset(PIN_BOX, PIN_BOX)
		box.ZIndex = 4
		box.Visible = self._layerOn[pin.kind] ~= false
		box.Parent = self._world

		-- Markers counter-scale against the world zoom so they stay one size.
		local counter = Instance.new("UIScale")
		counter.Name = "CounterScale"
		counter.Parent = box

		local well = UIStyler.Frame("Well")
		well.BackgroundColor3 = color
		well.BackgroundTransparency = if unlocked then 0 else 0.45
		well.AnchorPoint = Vector2.new(0.5, 0.5)
		well.Position = UDim2.fromScale(0.5, 0.5)
		well.Size = UDim2.fromOffset(PIN_WELL, PIN_WELL)
		well.ZIndex = 4
		well.Parent = box
		UIStyler.Corner(theme.Radii.Pill).Parent = well
		local ring = GPLayoutKit.SoftStroke(theme, well, color)
		if not unlocked then
			ring.Transparency = math.min(ring.Transparency + 0.4, 1)
		end
		GPLayoutKit.Shadow(theme, well, "sm", sink, color)

		local icon = GPControlKit.Icon(theme, well, KIND_ICON[pin.kind], 26, GPLayoutKit.Deepen(theme, color, 1))
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.ZIndex = 5
		if not unlocked then
			if icon:IsA("ImageLabel") then
				icon.ImageTransparency = 0.45
			else
				(icon :: TextLabel).TextTransparency = 0.45
			end
			local lock = GPControlKit.Icon(theme, box, "lock", 18, theme.Colors.TextSecondary)
			lock.AnchorPoint = Vector2.new(1, 1)
			lock.Position = UDim2.fromScale(1, 1)
			lock.ZIndex = 6
		end

		-- Whole-cell hit target (doc §11.6), press juice on the chip.
		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Text = ""
		hit.BackgroundTransparency = 1
		hit.AutoButtonColor = false
		hit.Size = UDim2.fromScale(1, 1)
		hit.ZIndex = 4
		hit.Parent = box
		hit.Activated:Connect(function()
			self:_OpenCallout(pin)
		end)
		UIChrome.Animate(theme, hit, well)

		table.insert(self._markers, { pin = pin, frame = box, scale = counter })
	end

	self:_ApplyTransform()
end

function MapScreen:_BuildRegions()
	local theme = self:GetTheme()
	for _, region in REGIONS do
		local block = UIStyler.Frame("Region_" .. region.name)
		block.BackgroundColor3 = theme.Arcade.Panel
		block.BackgroundTransparency = 0.62
		block.Position = UDim2.fromScale(region.x, region.y)
		block.Size = UDim2.fromScale(region.w, region.h)
		block.Parent = self._world

		local label = UIChrome.Text("Name", 22, theme.Arcade.IceBlue)
		label.Text = region.name
		label.TextTransparency = 0.35
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Position = UDim2.fromOffset(14, 10)
		label.Size = UDim2.new(1, -28, 0, 26)
		label.Parent = block
	end
end

-- The subtle grid: 2px ticks in the ruler-tick near-white, held far back so
-- they read as survey lines rather than chrome.
function MapScreen:_BuildGrid()
	local theme = self:GetTheme()
	local function line(x: number, y: number, width: number, height: number)
		local tick = UIStyler.Frame("Grid")
		tick.BackgroundColor3 = theme.Arcade.RulerTick
		tick.BackgroundTransparency = 0.88
		tick.Position = UDim2.fromOffset(x, y)
		tick.Size = UDim2.fromOffset(width, height)
		tick.Parent = self._world
	end
	for x = GRID_STEP, WORLD_W - 1, GRID_STEP do
		line(x, 0, 2, WORLD_H)
	end
	for y = GRID_STEP, WORLD_H - 1, GRID_STEP do
		line(0, y, WORLD_W, 2)
	end
end

function MapScreen:_BuildLegend(parent: Instance)
	-- _RebuildLegend routes back through here on new pin data, so the kit
	-- branch has to live at this seam and not only in _BuildContent.
	if self._gp then
		self:_BuildGPLegend(parent)
		return
	end
	local theme = self:GetTheme()
	self._legendParent = parent

	local legend = UIStyler.Frame("Legend")
	legend.BackgroundColor3 = theme.Arcade.NearBlack2
	legend.BackgroundTransparency = 0
	legend.Position = UDim2.fromOffset(LEGEND_X, 0)
	legend.Size = UDim2.fromOffset(LEGEND_W, LEGEND_H)
	UIChrome.Stroke(theme, "Arcade").Parent = legend
	UIChrome.GlassGradient().Parent = legend
	legend.Parent = parent
	self._legend = legend

	local title = UIChrome.Text("Title", 24, theme.Arcade.Gold)
	title.Text = "LEGEND"
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(PAD, 10)
	title.Size = UDim2.fromOffset(LEGEND_W - PAD * 2, 28)
	title.Parent = legend

	for index, kind in KIND_ORDER do
		local count = 0
		for _, pin in self._pins do
			if pin.kind == kind then
				count += 1
			end
		end

		local row = UIStyler.Frame("Layer_" .. kind)
		row.BackgroundColor3 = theme.Arcade.NearBlack
		row.BackgroundTransparency = 0.35
		row.Position = UDim2.fromOffset(PAD, 48 + (index - 1) * 60)
		row.Size = UDim2.fromOffset(LEGEND_W - PAD * 2, 52)
		UIChrome.Stroke(theme, "Arcade").Parent = row
		row.Parent = legend

		local icon = IconArchive.Image(row, KIND_ICON[kind], 28)
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 10, 0.5, 0)
		tint(icon, kindColor(theme, kind))

		local toggle = UIToggleComponent.new()
		toggle:Create(row, {
			label = string.format("%s (%d)", KIND_LABEL[kind], count),
			value = self._layerOn[kind] ~= false,
			size = UDim2.fromOffset(LEGEND_W - PAD * 2 - 50, 36),
			position = UDim2.new(0, 46, 0.5, 0),
			anchorPoint = Vector2.new(0, 0.5),
			onChanged = function(on: boolean)
				self:_SetLayer(kind, on)
			end,
		})
		table.insert(self._toggles, toggle)
	end

	-- Discovery block: the gold ruler counting unlocked destinations, then the
	-- locked ones named so the column reads as a checklist, not a colour key.
	local unlocked, locked = 0, {}
	for _, pin in self._pins do
		if pin.unlocked == false then
			table.insert(locked, pin)
		else
			unlocked += 1
		end
	end

	local discovery = UIChrome.Text("DiscoveryTitle", 20, theme.Arcade.Gold)
	discovery.Text = "DISCOVERY"
	discovery.TextXAlignment = Enum.TextXAlignment.Left
	discovery.Position = UDim2.fromOffset(PAD, 300)
	discovery.Size = UDim2.fromOffset(LEGEND_W - PAD * 2, 26)
	discovery.Parent = legend

	local progress = UIProgressBarComponent.new()
	progress:Create(legend, {
		value = unlocked,
		maxValue = math.max(1, #self._pins),
		label = "FOUND",
		size = UDim2.fromOffset(LEGEND_W - PAD * 2, 26),
		position = UDim2.fromOffset(PAD, 332),
	})
	self._progress = progress

	local lockedTitle = UIChrome.Text("LockedTitle", 20, theme.Arcade.GreyOwned)
	lockedTitle.Text = "STILL LOCKED"
	lockedTitle.TextXAlignment = Enum.TextXAlignment.Left
	lockedTitle.Position = UDim2.fromOffset(PAD, 378)
	lockedTitle.Size = UDim2.fromOffset(LEGEND_W - PAD * 2, 26)
	lockedTitle.Parent = legend

	for index, pin in locked do
		if index > 4 then
			break
		end
		local y = 410 + (index - 1) * 30
		local lock = IconArchive.Image(legend, "lock", 18)
		lock.Position = UDim2.fromOffset(PAD + 2, y + 4)

		local label = UIChrome.Text("Locked" .. index, 16, theme.Arcade.GreyOwned)
		label.Text = pin.name
		label.RichText = false
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Position = UDim2.fromOffset(PAD + 28, y)
		label.Size = UDim2.fromOffset(LEGEND_W - PAD * 2 - 28, 26)
		label.Parent = legend
	end

	-- Quiet body-font control hint (doc §2: GothamMedium for hints).
	local hint = UIChrome.BodyText("Hint", 15, theme.Arcade.GreyOwned)
	hint.Text = "Drag the map to pan. Scroll or use the zoom slider to get closer. Click a pin for fast travel."
	hint.TextWrapped = true
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextYAlignment = Enum.TextYAlignment.Bottom
	hint.AnchorPoint = Vector2.new(0, 1)
	hint.Position = UDim2.new(0, PAD, 1, -PAD)
	hint.Size = UDim2.fromOffset(LEGEND_W - PAD * 2, 110)
	hint.Parent = legend
end

-- New pin data changes the per-layer counts, so the legend is rebuilt whole
-- (the layer on/off state lives in self._layerOn and survives the rebuild).
function MapScreen:_RebuildLegend()
	if not self._legendParent then
		return
	end
	for _, toggle in self._toggles do
		toggle:Destroy()
	end
	table.clear(self._toggles)
	if self._progress then
		self._progress:Destroy()
		self._progress = nil
	end
	if self._legend then
		self._legend:Destroy()
		self._legend = nil
	end
	self:_BuildLegend(self._legendParent)
end

-- The pin callout lives in the VIEWPORT, not the world, so its type size stays
-- constant; it is repositioned from the marker's live screen rect on every pan
-- and zoom.
function MapScreen:_BuildCallout()
	local theme = self:GetTheme()

	local callout = UIStyler.Frame("Callout")
	callout.BackgroundColor3 = theme.Arcade.NearBlack
	callout.BackgroundTransparency = 0
	callout.AnchorPoint = Vector2.new(0.5, 1)
	callout.Size = UDim2.fromOffset(300, 132)
	callout.Visible = false
	callout.ZIndex = 6
	UIChrome.Stroke(theme, "Arcade", "Selection").Parent = callout
	UIChrome.GlassGradient().Parent = callout
	callout.Parent = self._viewport
	self._callout = callout

	local name = UIChrome.Text("Name", 20, WHITE)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(12, 8)
	name.Size = UDim2.fromOffset(230, 26)
	name.ZIndex = 7
	name.Parent = callout
	self._calloutName = name

	local kindLabel = UIChrome.Text("Kind", 16, theme.Arcade.Gold)
	kindLabel.TextXAlignment = Enum.TextXAlignment.Left
	kindLabel.Position = UDim2.fromOffset(12, 36)
	kindLabel.Size = UDim2.fromOffset(276, 22)
	kindLabel.ZIndex = 7
	kindLabel.Parent = callout
	self._calloutKind = kindLabel

	local close = UIChrome.CloseButton(theme, callout, function()
		self:_CloseCallout()
	end)
	close.Size = UDim2.fromOffset(30, 30)
	close.TextSize = 18
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -8, 0, 8)
	close.ZIndex = 7

	local travel = UIButtonComponent.new()
	travel:Create(callout, {
		text = self:_R("FAST TRAVEL"),
		variant = "Blue",
		size = UDim2.fromOffset(276, 46),
		position = UDim2.new(0.5, 0, 1, -10),
		anchorPoint = Vector2.new(0.5, 1),
		onClick = function()
			self:_FastTravel()
		end,
	})
	travel.Root.ZIndex = 7
	self._travelButton = travel
end

-- ---- pins --------------------------------------------------------------

function MapScreen:_RenderPins()
	-- Reached from _OnShow and Update as well as the build, so it branches here.
	if self._gp then
		self:_RenderGPPins()
		return
	end
	local theme = self:GetTheme()
	for _, marker in self._markers do
		marker.frame:Destroy()
	end
	table.clear(self._markers)

	for _, pin in self._pins do
		local color = kindColor(theme, pin.kind)
		local unlocked = pin.unlocked ~= false

		local box = UIStyler.Frame("Pin_" .. pin.id)
		box.BackgroundTransparency = 1
		box.AnchorPoint = Vector2.new(0.5, 0.5)
		box.Position = UDim2.fromScale(pin.x, pin.y)
		box.Size = UDim2.fromOffset(PIN_BOX, PIN_BOX)
		box.ZIndex = 3
		box.Visible = self._layerOn[pin.kind] ~= false
		box.Parent = self._world

		-- Markers counter-scale against the world zoom so they stay one size.
		local counter = Instance.new("UIScale")
		counter.Name = "CounterScale"
		counter.Parent = box

		local well = UIStyler.Frame("Well")
		well.BackgroundColor3 = theme.Arcade.NearBlack
		well.BackgroundTransparency = if unlocked then 0 else 0.45
		well.AnchorPoint = Vector2.new(0.5, 0.5)
		well.Position = UDim2.fromScale(0.5, 0.5)
		well.Size = UDim2.fromOffset(PIN_WELL, PIN_WELL)
		well.ZIndex = 3
		UIChrome.Corner("Arcade", "Pill").Parent = well
		-- Policy stroke; only its COLOUR carries the pin-kind identity.
		local ring = UIChrome.Stroke(theme, "Arcade", "Panel")
		ring.Color = color
		-- Locked pins fade the ring ON TOP of the style's resting transparency
		-- (Classic: 0 → 0.4).
		if not unlocked then
			ring.Transparency += 0.4
		end
		ring.Parent = well
		well.Parent = box

		local icon = IconArchive.Image(well, KIND_ICON[pin.kind], 26)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.ZIndex = 4
		tint(icon, color)
		if not unlocked then
			if icon:IsA("ImageLabel") then
				icon.ImageTransparency = 0.45
			else
				(icon :: TextLabel).TextTransparency = 0.45
			end
			local lock = IconArchive.Image(box, "lock", 18)
			lock.AnchorPoint = Vector2.new(1, 1)
			lock.Position = UDim2.fromScale(1, 1)
			lock.ZIndex = 5
		end

		-- Whole-cell hit target (doc §11.6), with the press juice on the well.
		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Text = ""
		hit.BackgroundTransparency = 1
		hit.AutoButtonColor = false
		hit.Size = UDim2.fromScale(1, 1)
		hit.ZIndex = 3
		hit.Parent = box
		hit.Activated:Connect(function()
			self:_OpenCallout(pin)
		end)
		UIChrome.Animate(theme, hit, well)

		table.insert(self._markers, { pin = pin, frame = box, scale = counter })
	end

	self:_ApplyTransform()
end

function MapScreen:_SetLayer(kind: string, on: boolean)
	self._layerOn[kind] = on
	for _, marker in self._markers do
		if marker.pin.kind == kind then
			marker.frame.Visible = on
		end
	end
	local selected = self._selected
	if selected and selected.kind == kind and not on then
		self:_CloseCallout()
	end
end

-- ---- pan / zoom --------------------------------------------------------

function MapScreen:_ClampPan(pan: Vector2): Vector2
	local worldW = WORLD_W * self._zoom
	local worldH = WORLD_H * self._zoom
	local minX = math.min(0, VIEW_W - worldW)
	local minY = math.min(0, VIEW_H - worldH)
	return Vector2.new(math.clamp(pan.X, minX, 0), math.clamp(pan.Y, minY, 0))
end

function MapScreen:_ApplyTransform()
	self._pan = self:_ClampPan(self._pan)
	self._world.Position = UDim2.fromOffset(self._pan.X, self._pan.Y)
	self._worldScale.Scale = self._zoom
	local counter = 1 / self._zoom
	for _, marker in self._markers do
		marker.scale.Scale = counter
	end
	if self._selected then
		self:_PositionCallout()
	end
end

-- Zoom anchored on the viewport centre: the world point currently under the
-- centre stays under it, which is what makes wheel-zoom feel right.
function MapScreen:_SetZoom(zoom: number, fromSlider: boolean)
	local target = math.clamp(zoom, MIN_ZOOM, MAX_ZOOM)
	if math.abs(target - self._zoom) < 1e-4 then
		return
	end
	local centreX = (VIEW_W / 2 - self._pan.X) / self._zoom
	local centreY = (VIEW_H / 2 - self._pan.Y) / self._zoom
	self._zoom = target
	self._pan = Vector2.new(VIEW_W / 2 - centreX * target, VIEW_H / 2 - centreY * target)
	self:_ApplyTransform()
	if not fromSlider and self._slider then
		self._slider:Set(target, false)
	end
end

function MapScreen:_ResetView()
	self._zoom = 1
	self._pan = Vector2.new((VIEW_W - WORLD_W) / 2, (VIEW_H - WORLD_H) / 2)
	self:_ApplyTransform()
	if self._slider then
		self._slider:Set(1, false)
	end
end

function MapScreen:_ConnectInput()
	if #self._conns > 0 then
		return
	end
	local viewport = self._viewport

	table.insert(self._conns, viewport.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self._dragging = true
			self._dragStart = Vector2.new(input.Position.X, input.Position.Y)
			self._panStart = self._pan
		end
	end))

	table.insert(self._conns, UserInputService.InputChanged:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			-- No cursor hit-test: these connections only exist while the map is
			-- open, and the map owns the whole screen while it is (exclusive
			-- panel + modal dim), so the wheel always means "zoom the map".
			-- Position.Z carries the notch direction.
			self:_SetZoom(self._zoom * (1 + ZOOM_STEP * input.Position.Z), false)
			return
		end
		if not self._dragging then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			-- Input arrives in real screen px; the pan lives in baseline px.
			local scale = self:_BaselineScale()
			local delta = (Vector2.new(input.Position.X, input.Position.Y) - self._dragStart) / scale
			self._pan = self._panStart + delta
			self:_ApplyTransform()
		end
	end))

	table.insert(self._conns, UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self._dragging = false
		end
	end))
end

function MapScreen:_DisconnectInput()
	for _, connection in self._conns do
		connection:Disconnect()
	end
	table.clear(self._conns)
	self._dragging = false
end

-- ---- callout -----------------------------------------------------------

function MapScreen:_OpenCallout(pin: Pin)
	self._selected = pin
	-- Same strings, title-cased under GP: pack law 5 forbids all-caps copy.
	self._calloutName.Text = if self._gp then gpTitle(pin.name) else pin.name
	local unlocked = pin.unlocked ~= false
	local kindText = KIND_LABEL[pin.kind] or string.upper(pin.kind)
	if self._gp then
		self._calloutKind.Text = if unlocked then gpTitle(kindText) else gpTitle(kindText) .. " · not found yet"
		-- The kind's identity colour is a PASTEL here (butter measures 1.2:1 on
		-- cream), so the line stays ink and the colour is carried by the pin
		-- chip and the callout's own hue-matched shadow instead.
		self._calloutKind.TextColor3 = if unlocked then self:GetTheme().Colors.TextPrimary else self:GetTheme().Colors.TextSecondary
	else
		self._calloutKind.Text = if unlocked
			then KIND_LABEL[pin.kind] or string.upper(pin.kind)
			else (KIND_LABEL[pin.kind] or string.upper(pin.kind)) .. " • LOCKED"
		self._calloutKind.TextColor3 = if unlocked then kindColor(self:GetTheme(), pin.kind) else self:GetTheme().Arcade.GreyOwned
	end
	-- Blocked destinations dim in place and still answer the tap (doc §11.1).
	self._travelButton:SetContent({
		text = if self._gp then gpTitle(self:_R("FAST TRAVEL")) else self:_R("FAST TRAVEL"),
		variant = "Blue",
		dimmed = not unlocked,
	})
	self._callout.Visible = true
	self:_PositionCallout()
	UIChrome.PopIn(self:GetTheme(), self._callout)
end

function MapScreen:_CloseCallout()
	self._selected = nil
	self._callout.Visible = false
end

-- Park the callout above its marker, clamped inside the viewport so it never
-- hangs off the clipped edge.
function MapScreen:_PositionCallout()
	local pin = self._selected
	if not pin then
		return
	end
	local worldW = WORLD_W * self._zoom
	local worldH = WORLD_H * self._zoom
	local x = self._pan.X + pin.x * worldW
	local y = self._pan.Y + pin.y * worldH
	local size = self._callout.AbsoluteSize / self:_BaselineScale()
	local halfW = (if size.X > 0 then size.X else 300) / 2
	local height = if size.Y > 0 then size.Y else 132
	local clampedX = math.clamp(x, halfW + 6, VIEW_W - halfW - 6)
	local clampedY = math.clamp(y - PIN_BOX / 2 - 6, height + 6, VIEW_H - 6)
	self._callout.Position = UDim2.fromOffset(clampedX, clampedY)
end

function MapScreen:_FastTravel()
	local pin = self._selected
	if not pin then
		return
	end
	if pin.unlocked == false then
		self:_Toast(
			if self._gp then gpTitle(pin.name) .. " is still to find" else pin.name .. " IS STILL LOCKED",
			"Error"
		)
		return
	end
	self.ScreenController:ShowModal({
		kind = "Confirm",
		title = self:_R("FAST TRAVEL"),
		body = string.format("Travel to %s? You'll leave your current spot behind.", pin.name),
		confirmKey = "TRAVEL",
		cancelKey = "STAY",
		onConfirm = function()
			self:_Toast(
				if self._gp then "Off to " .. gpTitle(pin.name) else "TRAVELLING TO " .. pin.name,
				"Success"
			)
			self:_CloseCallout()
			self.ScreenController:HideScreen("map")
		end,
	})
end

-- ---- lifecycle ---------------------------------------------------------

function MapScreen:_Ingest(data: any?)
	if type(data) == "table" and #data > 0 then
		self._pins = data
		return true
	end
	if type(data) == "table" and data.pins then
		self._pins = data.pins
		return true
	end
	return false
end

function MapScreen:_OnShow(data: any?)
	if self:_Ingest(data) then
		self:_RebuildLegend()
		self:_RenderPins()
	end
	self:_CloseCallout()
	self:_ConnectInput()
	if self._modal then
		UIChrome.PopIn(self:GetTheme(), self._modal.content)
	end
end

function MapScreen:_OnHide()
	self:_DisconnectInput()
	self:_CloseCallout()
end

function MapScreen:Update(data: any)
	if self:_Ingest(data) and self._built then
		self:_RebuildLegend()
		self:_RenderPins()
	end
end

-- A style rebuild destroys the Gui but NOT the shadow budget count: every
-- handle the GP build took has to be handed back by hand. Three sinks, because
-- the legend and the pin layer are both rebuilt on new data while the page
-- chrome is not.
function MapScreen:_OnTeardown()
	self:_DisconnectInput()
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	GPLayoutKit.ReleaseShadows(self._gpLegendShadows)
	GPLayoutKit.ReleaseShadows(self._gpPinShadows)
	self._gpShadows = nil
	self._gpLegendShadows = nil
	self._gpPinShadows = nil
	self._gpCalloutClose = nil
	self._modal = nil
	self._legend = nil
	self._legendParent = nil
	table.clear(self._toggles)
	table.clear(self._markers)
	self._progress = nil
	self._slider = nil
	self._resetButton = nil
	self._travelButton = nil
end

function MapScreen:Destroy()
	self:_DisconnectInput()
	GPLayoutKit.ReleaseShadows(self._gpShadows)
	GPLayoutKit.ReleaseShadows(self._gpLegendShadows)
	GPLayoutKit.ReleaseShadows(self._gpPinShadows)
	for _, toggle in self._toggles do
		toggle:Destroy()
	end
	table.clear(self._toggles)
	if self._progress then
		self._progress:Destroy()
		self._progress = nil
	end
	if self._slider then
		self._slider:Destroy()
		self._slider = nil
	end
	if self._resetButton then
		self._resetButton:Destroy()
		self._resetButton = nil
	end
	if self._travelButton then
		self._travelButton:Destroy()
		self._travelButton = nil
	end
	UIScreenBase.Destroy(self)
end

return MapScreen
