--!strict
-- POTTERY WHEEL — the throwing minigame HUD: the core loop of Pottery Battles,
-- rebuilt in the Girly Pop layout language (theme.LayoutKit == "GP") over the
-- universal screen base.
--
-- WHAT THE SOURCE ACTUALLY HAS (PotteryWheel.client.luau + the panels its
-- attribute bus drives in PotteryFlow.client.luau). Every one of these is
-- present here; nothing was dropped and nothing was invented in its place:
--
--   * BLUEPRINT / TARGET GHOST — five procedural radius-by-height profiles
--     (Cylinder / Vase / Bowl / Bottle / Urn) sampled bottom→rim, published as
--     the Blueprint attribute, drawn as a 24-disc translucent ghost with a
--     Ghost/Outline view toggle (TargetView). A commission (CommissionSpec)
--     OVERRIDES the deterministic rotation and carries its own height ask.
--   * ACCURACY — Accuracy = clamp(1 − meanRadiusError/LATHE_RADIUS × shapeCurve)
--     × 100, printed by the source as "Match: %d%%".
--   * DEPTH GUIDE — DepthGuideOn / DepthGuideR (0.30…2.00 world studs, the
--     centre notch IS the spin axis, the marker sits on either side) and
--     ToolAngle (−1…1 → ±35° tilt). While on, the tilted line is a HARD mold
--     edge every ring stops at.
--   * CARVE BAR — ShapeTool "Hands" | "Groove" | "Ridge", with Groove's V/U
--     profile sub-row and Ridge's 1/2/4/8 symmetry sub-row. Equipping Ridge
--     PARKS the wheel and un-equipping restores the previous spin state.
--   * CONTACT / SHAPING FEEDBACK — HasContact / ContactPoint, Shaping,
--     Hollowing, Painting, Hovering, ShapeDir (press in vs widen) and Intensity.
--   * MODAL DRAGS — plain drag shapes the wall, Shift+drag hollows (Hollow, a
--     fraction of MAX_HOLLOW 0.9), Alt+drag scales height (HeightScale, clamped
--     HEIGHT_MIN 0.45 … HEIGHT_MAX 1.5, latched by HeightToggle/HeightLive).
--   * CONTROLS CARD — the "?" panel's per-device control list, rebuilt for
--     keyboard / touch / gamepad from the live last-input type.
--   * GLAZE BENCH — GlazeTool "Paint" | "Erase" | "Fill", GlazeLineDir "H"
--     (360° band) vs "V" (full-height line), the GlazeBrushSize slider
--     (0.015…1.0, default 0.4), PaintStock drain and PaintCoverage. Erase is
--     always free; only LAYING is gated on stock.
--   * ACCESSORIES — the phase between Shape and Glaze (PHASE_CODE 1). The target
--     ghost stays up through it and a contact there is a PLACEMENT, not a
--     shaping stroke; ClearAccessories empties the pot.
--   * KILN + STORAGE — FireProgress over BAKE_SECONDS 2.5 × KilnBurnMult, the
--     Fired flag, Carrying, and THREE storage gates: StorageFull, PillarsFull
--     and ShelfFull, each with its own real refusal string.
--   * DISPLAY — SellEstimate (the wheel's own PotMaterials preview), the
--     Deliver/Sell fate handshake (FinishMode), "Make another" (store on a
--     pillar) vs "Shelf", and DisplaySpin as its own turntable gate.
--   * PHASES — Shape → Accessories → Glaze → Fire → Display in the source's own
--     PHASE_CODE order, wheel spin 75°/s while working and the 45°/s display
--     turntable, the three separate resets (Reset Clay / Reset Paint / reset
--     pot) and the mesh's own density (29 rings × 48 radial segments).
--
-- WHAT THIS VERSION ADDS (the upgrade, all of it on ONE ticker handler):
--   * RADIAL GUIDE RINGS from theme.Assets.wheelRadial, three of them counter-
--     rotating at true throw speed, so the HUD reads the wheel's actual rpm.
--   * A CENTERING INDICATOR that genuinely drifts (deterministic sum-of-sines,
--     no RNG — the source is deliberately RNG-free so pots stay reproducible)
--     and must be corrected: A/D/W/S or the arrow keys steer it, and the four
--     steady-hand chips do the same job for touch and gamepad.
--   * A WOBBLE WARNING RING whose stroke flushes to theme.Colors.Error the
--     moment the throw goes off-centre, and whose hue drives the status line.
--   * The accuracy readout on a rounded pastel meter with grade thresholds, a
--     best-so-far ghost mark and a five-star badge (the commission board's star
--     preview reads off this same number in the live game).
--   * A dense readout column — nineteen GPLayoutKit.StatRows, one decimal more
--     precision than the source's panels ever showed.
--
-- PACK LAWS OBSERVED (GirlyPopTheme's header states them):
--   1. No pure black, no pure white anywhere. Ink is Colors.TextPrimary. The
--      icon archive's glyph fallback is born white-on-black and is repainted on
--      arrival (see iconArt).
--   2. Shadows are hue-matched — every one comes from GPLayoutKit.Shadow, which
--      deepens the host's own fill. The handles land in self._shadows and are
--      released in _OnTeardown.
--   3. Colors.TextOnPrimary (2.14:1 on rose) is never used. Body copy on any
--      pastel is TextPrimary.
--   4. Petal corners via the kit's CornerSet/Petal, alternating by index.
--   5. No all-caps body copy — including the status vocabulary, which keeps its
--      words ("Perfectly centered" / "Wobble detected" / "Kiln ready") and drops
--      the shouting. Law 5 outranks the caps in a spec sheet.
--   6. Anti-condescension: the readout count went UP, not down.
--
-- OVERLAY DISCIPLINE: this is a gameplay HUD, so every surface is a translucent
-- cream chip clustered at the SCREEN EDGES (CHIP_TRANSPARENCY), the wheel field
-- itself carries nothing but non-interactive art, and no chip ever covers the
-- pot. Nothing here is a modal page — GPLayoutKit.Page is deliberately unused.

local UserInputService = game:GetService("UserInputService")

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local IconVisibility = require(script.Parent.Parent.Icons.IconVisibility)
local UITicker = require(script.Parent.Parent.Framework.UITicker)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local UIScreenBase = require(script.Parent.UIScreenBase)

-- ========================================================================
-- CONFIG + DEMO DATA — every literal this screen shows lives in this block.
-- Values carry the live game's units: world studs are already multiplied by
-- POT_SCALE (0.5) exactly where PotteryWheel scales them.
-- ========================================================================

local WHEEL = {
	SpinDegPerSec = 75, -- SPIN_SPEED = math.rad(75)
	DisplaySpinDegPerSec = 45, -- DISPLAY_SPIN_SPEED, the finished-pot turntable
	Rings = 29, -- C.RING_COUNT (LATHE_HEIGHT_SEGMENTS + 1)
	RadialSegments = 48, -- C.LATHE_RADIAL_SEGMENTS
	LatheRadius = 1.5, -- C.LATHE_RADIUS, mesh units (the blueprint profiles' R)
	GuideMin = 0.30, -- GUIDE_MIN_R
	GuideMax = 2.00, -- C.MAX_RADIUS × C.POT_SCALE + 0.5
	GuideTiltDeg = 35, -- ToolAngle ±1 maps to ±35°
	HeightMin = 0.45, -- C.HEIGHT_MIN
	HeightMax = 1.50, -- C.HEIGHT_MAX
	MaxHollow = 0.90, -- C.MAX_HOLLOW, a fraction of pot height
	WallThickness = 0.10, -- HollowThickness, as PotteryFlow publishes it
	BakeSeconds = 2.5, -- Glaze.BAKE_SECONDS
	Pillars = 3, -- demo pillar capacity behind PillarsFull
	ShelfSlots = 3, -- demo shelf capacity behind ShelfFull (total = StorageFull)
	PaintStock = 40, -- PaintStock, the selected glaze's remaining barrels
	BrushMin = 0.015, -- GlazeBrushSize slider floor (PotteryFlow's "Brush")
	BrushMax = 1.0, -- ... and its ceiling; GLAZE_BRUSH 0.4 is the default
	BrushStep = 0.05,
	AccessorySlots = 8, -- add-ons the pot can carry (PlacedAccessories)
}

-- Drift/centring model. OffsetLimit is the puck's leash; WobbleLimit is the
-- distance that reads as a full-blown wobble.
local DRIFT = {
	OffsetLimit = 0.50,
	WobbleLimit = 0.35,
	Speed = 0.30, -- studs/second of wander at full drift
	Correct = 0.62, -- studs/second the player can pull back
	CenteredAt = 0.28, -- wobble below this is "perfectly centered"
	WarnAt = 0.58, -- wobble above this flushes the ring to Error
	GainPerSecond = 7.5, -- accuracy earned while centred
	LossPerSecond = 9.5, -- accuracy lost while wobbling
	KilnReady = 92, -- accuracy that reads as kiln-ready
}

-- The five procedural blueprints, ported profile-for-profile from the source's
-- BP.BLUEPRINTS so the drawn silhouette IS the target the game grades against.
local R = WHEEL.LatheRadius
local BLUEPRINTS: { { name: string, note: string, heightScale: number, r: (number) -> number } } = {
	{
		name = "Cylinder",
		note = "Straight walls, the same all the way up",
		heightScale = 1,
		r = function(_t: number): number
			return R * 0.9
		end,
	},
	{
		name = "Vase",
		note = "Narrow foot, full belly, drawn back in at the rim",
		heightScale = 1,
		r = function(t: number): number
			return R * (0.55 + 0.6 * math.sin(t * math.pi))
		end,
	},
	{
		name = "Bowl",
		note = "Opens steadily from the foot to a wide lip",
		heightScale = 1,
		r = function(t: number): number
			return R * (0.45 + 0.9 * t)
		end,
	},
	{
		name = "Bottle",
		note = "Full body to two thirds, then a collared neck",
		heightScale = 1,
		r = function(t: number): number
			return R * (if t < 0.68 then 1.05 else math.max(0.32, 1.05 - (t - 0.68) * 2.4))
		end,
	},
	{
		name = "Urn",
		note = "Shoulders high and early, closing to a small mouth",
		heightScale = 1.15,
		r = function(t: number): number
			return R * (0.5 + 0.55 * math.sin(math.min(1, t * 1.15) * math.pi))
		end,
	},
}

-- The canonical phase ladder, in the live game's own order (PotStream.PHASE_CODE
-- 0..4). Accessories sits BETWEEN Shape and Glaze: the target ghost stays up
-- through it and a contact there is a placement, not a shaping stroke.
local PHASES = { "Shape", "Accessories", "Glaze", "Fire", "Display" }
local PHASE_INDEX: { [string]: number } = {}
for index, phase in PHASES do
	PHASE_INDEX[phase] = index
end

-- Pip labels. "Accessories" is the attribute value; "Add-ons" is what the game
-- itself calls the phase in copy, and it is what fits a pip.
local PHASE_PIPS: { [string]: string } = {
	Shape = "Shape",
	Accessories = "Add-ons",
	Glaze = "Glaze",
	Fire = "Fire",
	Display = "Display",
}

-- The per-phase heading over the phase tool bar — PotteryFlow rebuilds its whole
-- toolbar per phase, so this HUD swaps groups the same way.
local PHASE_TITLES: { [string]: string } = {
	Shape = "Shaping tools",
	Accessories = "Add-ons",
	Glaze = "Glaze tools",
	Fire = "The kiln",
	Display = "Your finished pottery",
}

local TOOLS: { { id: string, label: string, note: string } } = {
	{ id = "Hands", label = "Hands", note = "Drag across the clay to mold the wall in or out" },
	{ id = "Groove", label = "Groove", note = "Click the pot to cut a ring groove; clicks deepen it" },
	{ id = "Ridge", label = "Ridge", note = "Drag down the pot to carve mirrored vertical grooves" },
}
local GROOVE_PROFILES: { { id: string, label: string } } = {
	{ id = "V", label = "V" },
	{ id = "U", label = "U" },
}
local RIDGE_SYMMETRY = { 1, 2, 4, 8 }
-- GlazeTool, verbatim from the source's attribute contract: "Paint" lays a full
-- 360° band, "Erase" scrubs back to bare clay (always free, even out of stock),
-- "Fill" floods the whole pot in one click.
local GLAZE_TOOLS: { { id: string, label: string, note: string } } = {
	{ id = "Paint", label = "Paint", note = "Drag on the pot to lay a full band of colour" },
	{ id = "Erase", label = "Erase", note = "Scrub colour back to bare clay \u{2014} always free" },
	{ id = "Fill", label = "Fill", note = "One click floods the whole pot with this glaze" },
}
-- GlazeLineDir: "H" is the horizontal 360° band, "V" the full-height stripe.
local GLAZE_DIRS: { { id: string, label: string } } = {
	{ id = "H", label = "Bands" },
	{ id = "V", label = "Lines" },
}
-- The three modal drags, exactly as the source latches them.
local LATCHES: { { id: string, label: string } } = {
	{ id = "Shape", label = "Shape" },
	{ id = "Hollow", label = "Hollow" },
	{ id = "Height", label = "Height" },
}

-- The "?" card's control list, per device — the source rebuilds this string on
-- every open so a controller plugged in mid-session shows the right bindings.
-- The last line of each is this build's centring addition.
local CONTROL_HINTS: { [string]: { string } } = {
	Keyboard = {
		"Click and drag on the clay to mold the wall in or out",
		"Shift and drag up or down to hollow the inside",
		"Alt and drag up or down (or the Height latch) for pot height",
		"Scroll to zoom \u{2014} orbit unlocks in the paint phase",
		"A / D steady the throw, W / S feed the latched drag",
	},
	Touch = {
		"Drag on the clay to mold the wall in or out",
		"Hold the Height latch and drag up or down for pot height",
		"Pinch to zoom in and out",
		"Paint phase: pick a colour, then drag on the pot",
		"Tap the steady-hand arrows to pull the throw back to centre",
	},
	Gamepad = {
		"Left stick moves the pointer over the clay",
		"Hold R2 and steer to mold the wall in or out",
		"Hold L2 and push up or down to hollow the inside",
		"Hold L1 and push up or down for pot height",
		"The steady-hand arrows pull the throw back to centre",
	},
}

-- Status vocabulary. Sentence case on purpose: the pack forbids all-caps body
-- copy, and these are copy, not labels on a machine.
local STATUS = {
	Centered = "Perfectly centered",
	Finding = "Finding the centre",
	Wobble = "Wobble detected",
	Kiln = "Kiln ready",
	Placing = "Placing add-ons",
	Painting = "Laying glaze",
	Erasing = "Scrubbing colour back",
	Firing = "In the kiln",
	Display = "On the stand",
}

-- The real empty/blocked states the live game ships, verbatim.
local NOTICES = {
	StorageFull = "Storage is full \u{2014} sell or clear a pot before firing another.",
	OutOfGlaze = "Out of glaze \u{2014} buy barrels at Storage.",
	PillarsFull = "Pillars are full \u{2014} use Shelf instead (or upgrade capacity).",
	ShelfFull = "The shelf is full \u{2014} sell a pot or upgrade capacity.",
	Carrying = "The pot is still on its way to the kiln.",
	NoAccessorySlots = "Every add-on slot on this pot is taken \u{2014} clear one to place another.",
}

-- The grade ladder behind the meter's colour bands and the star badge.
local GRADES: { { at: number, word: string } } = {
	{ at = 94, word = "Gallery piece" },
	{ at = 88, word = "Beautifully thrown" },
	{ at = 78, word = "Coming together" },
	{ at = 62, word = "Rough but honest" },
	{ at = 0, word = "Still a lump" },
}
local STAR_AT = { 60, 72, 82, 89, 95 }

-- The readout column. One table drives both layout branches, so the arcade
-- build can never quietly show fewer stats than the GP one.
local READOUTS: { { id: string, label: string, unit: string, max: number, precision: number, invert: boolean? } } = {
	{ id = "accuracy", label = "Match to blueprint", unit = "%", max = 100, precision = 1 },
	{ id = "best", label = "Best this pot", unit = "%", max = 100, precision = 1 },
	{ id = "drift", label = "Centring drift", unit = "studs", max = DRIFT.OffsetLimit, precision = 2, invert = true },
	{ id = "wobble", label = "Wobble", unit = "%", max = 100, precision = 1, invert = true },
	{ id = "height", label = "Height scale", unit = "\u{00D7}", max = WHEEL.HeightMax, precision = 2 },
	{ id = "hollow", label = "Cavity depth", unit = "%", max = 100, precision = 1 },
	{ id = "wall", label = "Wall thickness", unit = "studs", max = 0.3, precision = 2 },
	{ id = "guide", label = "Guide distance", unit = "studs", max = WHEEL.GuideMax, precision = 2 },
	{ id = "tilt", label = "Guide tilt", unit = "\u{00B0}", max = WHEEL.GuideTiltDeg, precision = 1 },
	{ id = "spin", label = "Wheel speed", unit = "\u{00B0}/s", max = 90, precision = 1 },
	{ id = "rings", label = "Live wall rings", unit = "", max = WHEEL.Rings, precision = 0 },
	{ id = "coverage", label = "Glaze coverage", unit = "%", max = 100, precision = 1 },
	{ id = "brush", label = "Glaze brush", unit = "studs", max = WHEEL.BrushMax, precision = 3 },
	{ id = "stock", label = "Paint stock", unit = "", max = WHEEL.PaintStock, precision = 1 },
	{ id = "addons", label = "Add-ons placed", unit = "", max = WHEEL.AccessorySlots, precision = 0 },
	{ id = "kiln", label = "Kiln progress", unit = "%", max = 100, precision = 1 },
	{ id = "pillars", label = "Pillars used", unit = "", max = WHEEL.Pillars, precision = 0, invert = true },
	{ id = "shelf", label = "Shelf slots used", unit = "", max = WHEEL.ShelfSlots, precision = 0, invert = true },
	{ id = "sell", label = "Sell estimate", unit = "$", max = 400, precision = 0 },
}

-- Layout, fixed px at the 1650×1020 authoring baseline (UIScreenBase attaches
-- the scale). Everything is anchored to an EDGE so the wheel field stays clear.
local CHIP_TRANSPARENCY = 0.16 -- the world must stay readable through the HUD
local FIELD_Y = 0.46 -- the wheel's centre on screen
local RING_SIZES = { 436, 316, 210 }
local WOBBLE_RING = 486
local GHOST_ROWS = 24 -- BP.buildGhost's disc count
local PAINT_STEP = 1 / 12 -- text/meters repaint at 12Hz; the rings spin every frame

-- ========================================================================
-- Small helpers
-- ========================================================================

local function grade(accuracy: number): string
	for _, band in GRADES do
		if accuracy >= band.at then
			return band.word
		end
	end
	return GRADES[#GRADES].word
end

-- Deterministic wander: three detuned sines, no Random object. The live game is
-- deliberately RNG-free (pots must rebuild identically on every client) and the
-- HUD keeps that property so a replay of the same session drifts the same way.
local function wander(t: number, seed: number): number
	return (math.sin(t * 0.73 + seed) + math.sin(t * 1.31 + seed * 2.1) * 0.6 + math.sin(t * 2.17 + seed * 3.7) * 0.35) / 1.95
end

local function setText(label: TextLabel?, text: string)
	if label and label.Text ~= text then
		label.Text = text
	end
end

-- Icon-archive art. Full-colour pack art is left untinted (the archive's own
-- house rule); only the GLYPH fallback is repainted, because it is born pure
-- white with a pure black outline and this pack allows neither.
local function iconArt(parent: Instance, key: string, sizePx: number, ink: Color3): GuiObject
	local art = IconArchive.Image(parent, key, sizePx)
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.5)
	if art:IsA("TextLabel") then
		local label = art :: TextLabel
		label.TextColor3 = ink
		label.TextStrokeTransparency = 1
	end
	-- Idempotent; IconArchive.Image already tagged it, and the screen contract
	-- says every icon this file creates answers the global toggle.
	IconVisibility.Register(art)
	return art
end

-- Dim an icon WITHOUT fighting the global icon toggle: the rest transparency is
-- written as the attribute IconVisibility restores from, and the live property is
-- only touched while icons are actually on. Writing transparency blind would turn
-- hidden icons back on the moment a star lit up.
local function setIconDim(icon: GuiObject, transparency: number)
	icon:SetAttribute("IconRestTransparency", transparency)
	if not IconVisibility.IsEnabled() then
		return
	end
	if icon:IsA("ImageLabel") then
		(icon :: ImageLabel).ImageTransparency = transparency
	elseif icon:IsA("TextLabel") then
		(icon :: TextLabel).TextTransparency = transparency
	end
end

-- The live tool's one-line explainer (the source's per-tool hint).
local function toolNote(id: string): string
	for _, tool in TOOLS do
		if tool.id == id then
			return tool.note
		end
	end
	return ""
end

-- A painted frame. UIStyler.Frame is born pure white, which the pack forbids,
-- so nothing in this file may use it bare.
local function surface(name: string, fill: Color3, transparency: number?): Frame
	local frame = UIStyler.Frame(name)
	frame.BackgroundColor3 = fill
	frame.BackgroundTransparency = transparency or 0
	return frame
end

-- ========================================================================
-- The screen
-- ========================================================================

type Chip = {
	button: TextButton,
	shape: Frame,
	label: TextLabel,
	stroke: UIStroke?,
	on: boolean,
}

local PotteryWheelScreen = setmetatable({}, { __index = UIScreenBase })
PotteryWheelScreen.__index = PotteryWheelScreen

local function freshModel(): { [string]: any }
	return {
		phaseIndex = 1,
		blueprintIndex = 3, -- Bowl: the friendliest first throw
		tool = "Hands",
		grooveProfile = "V",
		ridgeSymmetry = 1,
		latch = "Shape",
		targetView = "Ghost",
		spinning = true,
		spinRestore = true,
		-- DisplaySpin is its OWN gate in the source: the display turntable keeps
		-- turning even when the working wheel is parked.
		displaySpin = true,
		guideOn = false,
		guideR = 1.10,
		guideSide = 1,
		toolAngle = 0,
		heightScale = 1,
		hollow = 0,
		wallThickness = WHEEL.WallThickness,
		accuracy = 34,
		best = 34,
		offsetX = 0.06,
		offsetY = -0.03,
		wobble = 0,
		contact = true,
		shapeDir = 0,
		intensity = 0,
		coverage = 0,
		paintStock = WHEEL.PaintStock,
		-- Glaze bench state, exactly the three attributes the wheel reads:
		-- GlazeTool / GlazeLineDir / GlazeBrushSize.
		glazeTool = "Paint",
		glazeDir = "H",
		glazeBrush = 0.4,
		glazeSelected = true,
		-- Accessories phase (PlacedAccessories + ClearAccessories).
		addons = 0,
		placing = false,
		firing = false,
		carrying = false,
		fireProgress = 0,
		fired = false,
		burnMult = 1,
		-- Storage is TWO destinations in the source, each with its own gate.
		pillarsUsed = 0,
		shelfUsed = 0,
		storageFull = false,
		pillarsFull = false,
		shelfFull = false,
		sellEstimate = 0,
		finishMode = nil :: string?,
		commission = nil :: string?,
		ringAngle = 0,
		clock = 0,
	}
end

function PotteryWheelScreen.new()
	local self = UIScreenBase.new("PotteryWheelScreen", 3)
	-- The whole minigame state in one table; both layout branches read it and
	-- neither owns it.
	self._m = freshModel()
	-- Widget refs, keyed identically by both branches so ONE _Paint drives both.
	self._w = {} :: { [string]: any }
	self._rows = {} :: { [string]: any }
	-- Pools: the ghost silhouette's rows and the star badge are built once and
	-- re-dressed in place — a blueprint swap never destroys an instance.
	self._ghostRows = {} :: { Frame }
	self._stars = {} :: { GuiObject }
	self._chips = {} :: { [string]: Chip }
	-- Hue-matched shadow budget handles (GPLayoutKit.Shadow pushes them here).
	self._shadows = {} :: { any }
	-- Show-scoped connections (input); dropped on hide AND on teardown.
	self._conns = {} :: { any }
	self._tickStop = nil :: (() -> ())?
	self._paintAccum = 0
	self._guideDrag = false
	-- Which ghost dressing is currently applied ("Ghost"/"Outline"); nil forces
	-- the first pass to actually paint.
	self._ghostView = nil :: string?
	self._steady = Vector2.zero -- the steady-hand chips' held impulse
	return setmetatable(self, PotteryWheelScreen)
end

-- ---- lifecycle ---------------------------------------------------------

function PotteryWheelScreen:_BuildContent()
	if self:LayoutKit() == "GP" then
		self:_BuildGPLayout()
	else
		self:_BuildArcadeLayout()
	end
	self:_Paint()
end

function PotteryWheelScreen:_OnShow(data: any?)
	if data and typeof(data) == "table" then
		if typeof(data.commission) == "string" then
			self._m.commission = data.commission
		end
		if typeof(data.blueprint) == "string" then
			for index, blueprint in BLUEPRINTS do
				if blueprint.name == data.blueprint then
					self:_SelectBlueprint(index)
					break
				end
			end
		end
	end
	self:_DropConnections()
	-- The control hint strip follows the device, exactly as the source's "?"
	-- card rebuilds itself per last-input type.
	table.insert(self._conns, UserInputService.LastInputTypeChanged:Connect(function()
		self:_RefreshHints()
	end))
	-- Releasing anywhere ends a guide-marker drag, including a touch release
	-- that lands off the rail.
	table.insert(self._conns, UserInputService.InputEnded:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			self._guideDrag = false
			local bubble = self._w.guideBubble
			if bubble then
				bubble.Visible = false
			end
		end
	end))
	self:_RefreshHints()
	self:_StartTicker()
end

function PotteryWheelScreen:_OnHide()
	self:_DropConnections()
	self:_StopTicker()
end

-- Idempotent: a style rebuild runs _OnHide and then _OnTeardown, and both land
-- here.
function PotteryWheelScreen:_DropConnections()
	for _, conn in self._conns do
		conn:Disconnect()
	end
	table.clear(self._conns)
end

function PotteryWheelScreen:_StopTicker()
	if self._tickStop then
		self._tickStop()
		self._tickStop = nil
	end
end

-- THE one shared-ticker handler. Rings, drift, wobble, accuracy, the kiln timer
-- and the throttled repaint all ride it — no screen-local RunService loop.
function PotteryWheelScreen:_StartTicker()
	self:_StopTicker()
	self._tickStop = UITicker.Register(function(dt: number, now: number)
		self:_Step(dt, now)
	end, self.Root)
end

function PotteryWheelScreen:_OnTeardown()
	self:_DropConnections()
	self:_StopTicker()
	GPLayoutKit.ReleaseShadows(self._shadows)
	table.clear(self._rows)
	table.clear(self._ghostRows)
	table.clear(self._stars)
	table.clear(self._chips)
	self._w = {}
	self._paintAccum = 0
	self._guideDrag = false
	self._ghostView = nil
	self._steady = Vector2.zero
end

-- ---- the model ---------------------------------------------------------

function PotteryWheelScreen:_Phase(): string
	return PHASES[self._m.phaseIndex] or PHASES[1]
end

function PotteryWheelScreen:_Blueprint(): { name: string, note: string, heightScale: number, r: (number) -> number }
	return BLUEPRINTS[self._m.blueprintIndex] or BLUEPRINTS[1]
end

-- The player's steering this frame: held keys plus whatever the steady-hand
-- chips are pushing. Polling beats four more connections for eight keys.
function PotteryWheelScreen:_SteerVector(): Vector2
	local x, y = self._steady.X, self._steady.Y
	if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
		x -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
		x += 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
		y -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then
		y += 1
	end
	if x == 0 and y == 0 then
		return Vector2.zero
	end
	return Vector2.new(x, y).Unit
end

function PotteryWheelScreen:_Step(dt: number, now: number)
	local m = self._m
	local phase = self:_Phase()
	m.clock = now

	-- Wheel spin. The source runs TWO gates: Spinning covers the working phases
	-- (parked by the Ridge tool and by the kiln), DisplaySpin drives the finished
	-- pot's turntable at its own slower 45°/s.
	local speed: number
	if phase == "Display" then
		speed = if m.displaySpin then WHEEL.DisplaySpinDegPerSec else 0
	elseif phase == "Fire" then
		speed = 0 -- in the furnace it sits still
	else
		speed = if m.spinning then WHEEL.SpinDegPerSec else 0
	end
	m.ringAngle = (m.ringAngle + speed * dt) % 360

	local steer = self:_SteerVector()
	m.intensity = m.intensity + (steer.Magnitude - m.intensity) * math.min(1, dt * 6)

	if phase == "Shape" then
		-- The clay wanders off the axis on its own; the player pulls it back.
		local driftX = wander(now, 1.7) * DRIFT.Speed
		local driftY = wander(now, 4.3) * DRIFT.Speed
		m.offsetX = math.clamp(m.offsetX + (driftX - steer.X * DRIFT.Correct) * dt, -DRIFT.OffsetLimit, DRIFT.OffsetLimit)
		if m.latch == "Shape" then
			m.offsetY = math.clamp(m.offsetY + (driftY - steer.Y * DRIFT.Correct) * dt, -DRIFT.OffsetLimit, DRIFT.OffsetLimit)
		else
			-- Shift/Alt drags: the vertical axis feeds the latched tool instead
			-- of the centring, exactly like the source's modal drags.
			m.offsetY = math.clamp(m.offsetY + driftY * dt, -DRIFT.OffsetLimit, DRIFT.OffsetLimit)
			if m.latch == "Hollow" then
				m.hollow = math.clamp(m.hollow - steer.Y * 0.45 * dt, 0, WHEEL.MaxHollow)
			elseif m.latch == "Height" then
				m.heightScale = math.clamp(m.heightScale - steer.Y * 0.5 * dt, WHEEL.HeightMin, WHEEL.HeightMax)
			end
		end
		m.shapeDir = if math.abs(steer.X) < 0.01 then 0 elseif steer.X > 0 then 1 else -1

		local offset = math.sqrt(m.offsetX * m.offsetX + m.offsetY * m.offsetY)
		m.wobble = math.clamp(offset / DRIFT.WobbleLimit, 0, 1)
		m.contact = m.wobble < 0.94
		if m.wobble < DRIFT.CenteredAt then
			m.accuracy = math.clamp(m.accuracy + DRIFT.GainPerSecond * (1 - m.wobble) * dt, 0, 100)
		else
			m.accuracy = math.clamp(m.accuracy - DRIFT.LossPerSecond * m.wobble * dt, 0, 100)
		end
		m.best = math.max(m.best, m.accuracy)
	elseif phase == "Accessories" then
		-- The target ghost stays up through this phase and a contact is a PLACEMENT,
		-- not a shaping stroke (the source's FLAG_PLACING gate).
		local push = steer.Magnitude
		m.contact = push > 0
		m.placing = push > 0 and m.addons < WHEEL.AccessorySlots
		m.wobble = m.wobble * math.max(0, 1 - dt * 2)
	elseif phase == "Glaze" then
		-- Painting drains the selected glaze's barrels; coverage is what the
		-- source publishes as PaintCoverage. Erase is ALWAYS free (scrubbing must
		-- never be gated on stock) and Fill floods in one go; a vertical Lines
		-- stroke covers less per pass than a full 360° band.
		local push = math.abs(steer.X) + math.abs(steer.Y)
		local dirRate = if m.glazeDir == "V" then 0.62 else 1
		local brushRate = 0.4 + m.glazeBrush * 1.5
		if push > 0 and m.glazeSelected then
			if m.glazeTool == "Erase" then
				m.coverage = math.clamp(m.coverage - push * 18 * brushRate * dirRate * dt, 0, 100)
			elseif m.paintStock > 0 then
				local gain = if m.glazeTool == "Fill" then 55 else 16 * brushRate * dirRate
				m.coverage = math.clamp(m.coverage + push * gain * dt, 0, 100)
				m.paintStock = math.max(0, m.paintStock - push * 4 * brushRate * dt)
			end
		end
		m.contact = push > 0
		m.wobble = m.wobble * math.max(0, 1 - dt * 2)
	elseif phase == "Fire" then
		m.contact = false
		m.wobble = 0
		if m.firing then
			local bakeSeconds = math.max(0.1, WHEEL.BakeSeconds * m.burnMult)
			m.fireProgress = math.clamp(m.fireProgress + dt / bakeSeconds, 0, 1)
			if m.fireProgress >= 1 then
				m.firing = false
				m.carrying = false
				m.fired = true
				-- Fired locks the shape, so the sell price is knowable from here —
				-- the source primes SellEstimate on exactly this edge.
				m.sellEstimate = self:_SellEstimate()
			end
		end
	else
		m.contact = false
		m.wobble = 0
	end

	-- Rings spin every frame; everything else repaints at 12Hz. Wide-open text
	-- writes at 60Hz would be the one expensive thing in a HUD this dense.
	self:_SpinRings()
	self._paintAccum += dt
	if self._paintAccum >= PAINT_STEP then
		self._paintAccum = 0
		self:_Paint()
	end
end

function PotteryWheelScreen:_SpinRings()
	local w = self._w
	local angle = self._m.ringAngle
	local first = w.ring1
	if not first then
		return
	end
	-- Frugal ambient effect: off-screen (or hidden) costs nothing.
	if not UIChrome.IsOnScreen(first) then
		return
	end
	first.Rotation = angle
	if w.ring2 then
		w.ring2.Rotation = -angle * 0.62
	end
	if w.ring3 then
		w.ring3.Rotation = angle * 0.35
	end
end

-- ---- state edits (every chip lands in one of these) --------------------

function PotteryWheelScreen:_SelectPhase(index: number)
	local m = self._m
	m.phaseIndex = math.clamp(index, 1, #PHASES)
	-- The source refreshes the "Sell $N" preview the moment the finished pot lands
	-- on the podium.
	if PHASES[m.phaseIndex] == "Display" then
		m.sellEstimate = self:_SellEstimate()
	end
	self:_Paint()
end

function PotteryWheelScreen:_SelectBlueprint(index: number)
	self._m.blueprintIndex = math.clamp(index, 1, #BLUEPRINTS)
	-- A fresh target restarts the grade: the source resamples targetRadii and
	-- rebuilds the ghost on every applyBlueprint.
	self._m.accuracy = math.min(self._m.accuracy, 40)
	self._m.best = self._m.accuracy
	self:_PaintGhost()
	self:_Paint()
end

-- Ridge cannot carve a spinning pot: equipping it parks the wheel and putting
-- it down restores whatever the spin state was before (source: setShapeTool).
function PotteryWheelScreen:_SelectTool(id: string)
	local m = self._m
	if m.tool == id then
		return
	end
	if id == "Ridge" then
		m.spinRestore = m.spinning
		m.spinning = false
	elseif m.tool == "Ridge" then
		m.spinning = m.spinRestore
	end
	m.tool = id
	self:_Paint()
end

-- resetShape: the "Reset Clay" button. Shape state only — the glaze survives,
-- exactly as the source's resetShape does.
function PotteryWheelScreen:_ResetClay()
	local m = self._m
	m.accuracy = 12
	m.best = 12
	m.hollow = 0
	m.heightScale = 1
	m.offsetX = 0
	m.offsetY = 0
	m.wobble = 0
	self:_Paint()
end

-- resetGlaze: the separate "Reset Paint" button. Colour only; the shape stands.
function PotteryWheelScreen:_ResetGlaze()
	local m = self._m
	m.coverage = 0
	m.fired = false
	m.fireProgress = 0
	m.firing = false
	self:_Paint()
end

-- resetPot: shape AND glaze back to bare clay, then the next blueprint — what the
-- source runs after a finished pot is stored.
function PotteryWheelScreen:_ResetPot()
	self:_ResetClay()
	self:_ResetGlaze()
	local m = self._m
	m.addons = 0
	m.paintStock = WHEEL.PaintStock
	m.finishMode = nil
	m.sellEstimate = 0
	-- The deterministic rotation: the live game steps the blueprint off the stored
	-- pot count, and a live commission keeps its grip on the target.
	if m.commission == nil then
		self:_SelectBlueprint((m.blueprintIndex % #BLUEPRINTS) + 1)
	end
	self:_SelectPhase(PHASE_INDEX.Shape)
end

-- The flat material price PotteryFlow prints on its "Sell $N" button. Same inputs
-- the source feeds PotMaterials — clay volume from the profile and height, minus
-- the cavity, plus paint units once anything is glazed. No RNG.
function PotteryWheelScreen:_SellEstimate(): number
	local m = self._m
	local blueprint = self:_Blueprint()
	local volume = 0
	for index = 1, WHEEL.Rings do
		local t = (index - 0.5) / WHEEL.Rings
		local r = blueprint.r(t)
		volume += r * r
	end
	volume = (volume / WHEEL.Rings) * m.heightScale * (1 - m.hollow * 0.5)
	local clay = volume * 34
	local paint = (m.coverage / 100) * 26
	local quality = 0.55 + (m.accuracy / 100) * 0.9
	return math.floor((clay + paint) * quality + 0.5)
end

-- Store.publishStorage: two destinations, three gates. A place with neither
-- pillars nor a shelf is not "full" — it simply has no storage.
function PotteryWheelScreen:_PublishStorage()
	local m = self._m
	local total = WHEEL.Pillars + WHEEL.ShelfSlots
	m.pillarsFull = WHEEL.Pillars > 0 and m.pillarsUsed >= WHEEL.Pillars
	m.shelfFull = WHEEL.ShelfSlots > 0 and m.shelfUsed >= WHEEL.ShelfSlots
	m.storageFull = total > 0 and (m.pillarsUsed + m.shelfUsed) >= total
end

-- "Make another" (pillar) and "Shelf" — each REFUSES a full destination before
-- the reset, because a failed store silently discards the finished pot.
function PotteryWheelScreen:_StorePot(destination: string)
	local m = self._m
	if not m.fired then
		return
	end
	if destination == "shelf" then
		if m.shelfFull then
			self:_Paint()
			return
		end
		m.shelfUsed += 1
	else
		if m.pillarsFull then
			self:_Paint()
			return
		end
		m.pillarsUsed += 1
	end
	self:_PublishStorage()
	self:_ResetPot()
end

-- The Deliver / Sell handshake. A live commission is DELIVERED (graded against
-- the accepted spec); anything else sells for the flat material price. Either
-- fate sends the pot AWAY — it never occupies a storage slot — and the wheel is
-- cleared for the next one, which is what the source does on the server's ack.
function PotteryWheelScreen:_FinishPot()
	local m = self._m
	if not m.fired or m.finishMode ~= nil then
		return
	end
	m.finishMode = if m.commission ~= nil then "deliver" else "sell"
	self:_Paint()
	self:_ResetPot()
end

-- "sell or clear a pot" — the other half of the source's own StorageFull copy.
-- Frees the most recently filled destination so the kiln can accept another.
function PotteryWheelScreen:_SellStoredPot()
	local m = self._m
	if m.shelfUsed > 0 then
		m.shelfUsed -= 1
	elseif m.pillarsUsed > 0 then
		m.pillarsUsed -= 1
	else
		self:_Paint()
		return
	end
	self:_PublishStorage()
	self:_Paint()
end

function PotteryWheelScreen:_PlaceAccessory()
	local m = self._m
	if m.addons >= WHEEL.AccessorySlots then
		self:_Paint()
		return
	end
	m.addons += 1
	self:_Paint()
end

function PotteryWheelScreen:_ClearAccessories()
	self._m.addons = 0
	self:_Paint()
end

function PotteryWheelScreen:_NudgeBrush(delta: number)
	local m = self._m
	m.glazeBrush = math.clamp(m.glazeBrush + delta, WHEEL.BrushMin, WHEEL.BrushMax)
	self:_Paint()
end

function PotteryWheelScreen:_StartFiring()
	local m = self._m
	-- The source refuses on BOTH gates: nothing may fire while the pot is still
	-- being carried to the kiln, or when there is nowhere to put it afterwards.
	if m.storageFull or m.firing or m.carrying then
		self:_SelectPhase(PHASE_INDEX.Fire)
		return
	end
	m.phaseIndex = PHASE_INDEX.Fire
	m.firing = true
	m.fireProgress = 0
	self:_Paint()
end

function PotteryWheelScreen:_SetGuideFromX(x: number)
	local track = self._w.guideTrack
	if not track then
		return
	end
	local left = track.AbsolutePosition.X
	local width = math.max(1, track.AbsoluteSize.X)
	local ratio = math.clamp((x - left) / width, 0, 1)
	-- The rail's centre notch IS the spin axis; the marker rides either side of
	-- it at radius R, which is the source's one source of truth.
	local signed = (ratio - 0.5) * 2
	self._m.guideSide = if signed >= 0 then 1 else -1
	self._m.guideR = math.clamp(math.abs(signed) * WHEEL.GuideMax, WHEEL.GuideMin, WHEEL.GuideMax)
	local bubble = self._w.guideBubble
	if bubble then
		bubble.Visible = true
	end
	self:_Paint()
end

-- ========================================================================
-- PAINT — one implementation, both layouts. Branches populate self._w with
-- the same keys; anything a branch does not build is simply skipped.
-- ========================================================================

function PotteryWheelScreen:_ReadoutValue(id: string): number
	local m = self._m
	if id == "accuracy" then
		return m.accuracy
	elseif id == "best" then
		return m.best
	elseif id == "drift" then
		return math.sqrt(m.offsetX * m.offsetX + m.offsetY * m.offsetY)
	elseif id == "wobble" then
		return m.wobble * 100
	elseif id == "height" then
		return m.heightScale
	elseif id == "hollow" then
		return (m.hollow / WHEEL.MaxHollow) * 100
	elseif id == "wall" then
		return m.wallThickness
	elseif id == "guide" then
		return m.guideR
	elseif id == "tilt" then
		return m.toolAngle * WHEEL.GuideTiltDeg
	elseif id == "spin" then
		local phase = self:_Phase()
		if phase == "Fire" then
			return 0
		elseif phase == "Display" then
			return if m.displaySpin then WHEEL.DisplaySpinDegPerSec else 0
		end
		return if m.spinning then WHEEL.SpinDegPerSec else 0
	elseif id == "rings" then
		return WHEEL.Rings
	elseif id == "coverage" then
		return m.coverage
	elseif id == "brush" then
		return m.glazeBrush
	elseif id == "stock" then
		return m.paintStock
	elseif id == "addons" then
		return m.addons
	elseif id == "kiln" then
		return m.fireProgress * 100
	elseif id == "pillars" then
		return m.pillarsUsed
	elseif id == "shelf" then
		return m.shelfUsed
	elseif id == "sell" then
		return m.sellEstimate
	end
	return 0
end

function PotteryWheelScreen:_StatusText(): (string, Color3)
	local theme = self:GetTheme()
	local m = self._m
	local phase = self:_Phase()
	if phase == "Accessories" then
		return STATUS.Placing, theme.Semantic.CursorHollow
	elseif phase == "Glaze" then
		if m.glazeTool == "Erase" then
			return STATUS.Erasing, theme.Colors.Warning
		end
		return STATUS.Painting, theme.Semantic.Selection
	elseif phase == "Fire" then
		return STATUS.Firing, theme.Colors.Warning
	elseif phase == "Display" then
		return STATUS.Display, theme.Colors.Secondary
	end
	if m.accuracy >= DRIFT.KilnReady and m.wobble < DRIFT.CenteredAt then
		return STATUS.Kiln, theme.Colors.Accent
	elseif m.wobble >= DRIFT.WarnAt then
		return STATUS.Wobble, theme.Colors.Error
	elseif m.wobble < DRIFT.CenteredAt then
		return STATUS.Centered, theme.Colors.Secondary
	end
	return STATUS.Finding, theme.Colors.Warning
end

function PotteryWheelScreen:_NoticeText(): string?
	local m = self._m
	local phase = self:_Phase()
	if m.storageFull then
		return NOTICES.StorageFull
	elseif phase == "Display" and m.pillarsFull then
		-- Per-destination refusal: the shelf may still have room, so say which.
		return NOTICES.PillarsFull
	elseif phase == "Display" and m.shelfFull then
		return NOTICES.ShelfFull
	elseif phase == "Accessories" and m.addons >= WHEEL.AccessorySlots then
		return NOTICES.NoAccessorySlots
	elseif m.carrying then
		return NOTICES.Carrying
	elseif phase == "Glaze" and m.glazeTool ~= "Erase" and m.paintStock <= 0 then
		-- Out of glaze refuses to LAY; erasing always stays free.
		return NOTICES.OutOfGlaze
	elseif m.firing then
		return string.format("Firing \u{2014} %d%% (burn \u{00D7}%.2f)", math.floor(m.fireProgress * 100 + 0.5), m.burnMult)
	elseif m.fired then
		return "Fired and cooling \u{2014} the glaze developed its finish."
	end
	return nil
end

function PotteryWheelScreen:_RefreshHints()
	local label = self._w.hintLabel
	if not label then
		return
	end
	local last = UserInputService:GetLastInputType()
	local kind = "Keyboard"
	if last == Enum.UserInputType.Touch then
		kind = "Touch"
	elseif last == Enum.UserInputType.Gamepad1 then
		kind = "Gamepad"
	end
	setText(label, table.concat(CONTROL_HINTS[kind], "   \u{2022}   "))
end

function PotteryWheelScreen:_Paint()
	local w = self._w
	if not next(w) then
		return
	end
	local theme = self:GetTheme()
	local m = self._m
	local phase = self:_Phase()
	local blueprint = self:_Blueprint()

	-- Status + blueprint line -------------------------------------------
	local statusText, statusTone = self:_StatusText()
	setText(w.statusLabel, statusText)
	if w.statusChip then
		w.statusChip.BackgroundColor3 = statusTone
	end
	if w.statusStroke then
		w.statusStroke.Color = GPLayoutKit.Deepen(theme, statusTone, 1)
	end
	setText(w.blueprintName, m.commission or blueprint.name)
	setText(w.blueprintNote, blueprint.note)
	if w.commissionBadge then
		w.commissionBadge.Visible = m.commission ~= nil
	end
	setText(w.heightAsk, string.format("Height ask %.2f\u{00D7}", blueprint.heightScale))
	-- The source shows the target ghost on the wheel through Shape AND Accessories
	-- only; past that the shape is locked and the ghost comes down.
	local ghostLive = phase == "Shape" or phase == "Accessories"
	setText(
		w.densityLabel,
		string.format(
			"%d rings \u{00D7} %d segments \u{2022} %s",
			WHEEL.Rings,
			WHEEL.RadialSegments,
			if ghostLive then "ghost up" else "ghost down"
		)
	)
	if w.ghostWell then
		w.ghostWell.BackgroundTransparency = if ghostLive then 0.25 else 0.55
	end

	-- Phase pips ---------------------------------------------------------
	if w.phaseTabs then
		w.phaseTabs.Select(phase)
	end

	-- Wheel field --------------------------------------------------------
	local wobbleTone = theme.Colors.Secondary:Lerp(theme.Colors.Error, math.clamp(m.wobble / DRIFT.WarnAt, 0, 1))
	if m.wobble >= DRIFT.WarnAt then
		-- Past the warning line the ring FLUSHES: no lerp, the pack's Error.
		wobbleTone = theme.Colors.Error
	end
	if w.wobbleStroke then
		w.wobbleStroke.Color = wobbleTone
		w.wobbleStroke.Thickness = 3 + 5 * m.wobble
		local pulse = if m.wobble >= DRIFT.WarnAt then 0.18 + 0.16 * math.sin(m.clock * 9) else 0.42
		w.wobbleStroke.Transparency = pulse
	end
	if w.puck then
		local reach = RING_SIZES[1] * 0.5 - 22
		w.puck.Position = UDim2.new(
			0.5,
			(m.offsetX / DRIFT.OffsetLimit) * reach,
			0.5,
			(m.offsetY / DRIFT.OffsetLimit) * reach
		)
		w.puck.BackgroundColor3 = wobbleTone
	end
	if w.puckStroke then
		w.puckStroke.Color = GPLayoutKit.Deepen(theme, wobbleTone, 1)
	end
	if w.puckShadow then
		w.puckShadow.Instance.Color = GPLayoutKit.Deepen(theme, wobbleTone, 1)
	end
	setText(
		w.driftLabel,
		string.format("Drift %.2f studs \u{2022} wobble %d%%", self:_ReadoutValue("drift"), math.floor(m.wobble * 100 + 0.5))
	)

	-- Contact / shaping feedback ----------------------------------------
	local contactText: string
	if not m.contact then
		contactText = "Hands off the clay"
	elseif phase == "Accessories" then
		contactText = if m.placing then "Reaching a piece onto the pot" else "No slot left for that piece"
	elseif phase == "Glaze" then
		if m.glazeTool == "Erase" then
			contactText = "Scrubbing colour off"
		elseif m.glazeTool == "Fill" then
			contactText = "Flooding the whole pot"
		elseif m.glazeDir == "V" then
			contactText = "Laying a full-height line"
		else
			contactText = "Laying a 360\u{00B0} band"
		end
	elseif m.shapeDir > 0 then
		contactText = "Widening the wall"
	elseif m.shapeDir < 0 then
		contactText = "Pressing the wall in"
	else
		contactText = "Hands resting on the clay"
	end
	setText(w.contactLabel, contactText)
	if w.contactDot then
		w.contactDot.BackgroundColor3 = if m.contact then theme.Colors.Success else theme.Colors.Disabled
	end
	if w.intensityFill then
		w.intensityFill.Size = UDim2.fromScale(math.clamp(m.intensity, 0, 1), 1)
	end

	-- Depth guide --------------------------------------------------------
	if w.guideMarker then
		local ratio = 0.5 + (m.guideSide * m.guideR / WHEEL.GuideMax) * 0.5
		w.guideMarker.Position = UDim2.new(math.clamp(ratio, 0.02, 0.98), 0, 0.5, 0)
	end
	setText(w.guideBubble, string.format("%.2f studs", m.guideR))
	setText(w.guideTiltLabel, string.format("Tilt %+.1f\u{00B0}", m.toolAngle * WHEEL.GuideTiltDeg))
	if w.guideRail then
		w.guideRail.BackgroundTransparency = if m.guideOn then 0 else 0.55
	end

	-- Readout column -----------------------------------------------------
	for _, spec in READOUTS do
		local row = self._rows[spec.id]
		if row then
			row.SetValue(self:_ReadoutValue(spec.id))
		end
	end

	-- Accuracy meter + stars ---------------------------------------------
	local ratio = math.clamp(m.accuracy / 100, 0, 1)
	if w.meterFill then
		w.meterFill.Size = UDim2.fromScale(ratio, 1)
		local tone = theme.Colors.Error:Lerp(theme.Colors.Secondary, math.clamp(m.accuracy / DRIFT.KilnReady, 0, 1))
		if m.accuracy >= DRIFT.KilnReady then
			tone = theme.Colors.Accent
		end
		w.meterFill.BackgroundColor3 = tone
	end
	if w.meterBest then
		w.meterBest.Position = UDim2.fromScale(math.clamp(m.best / 100, 0, 1), 0)
		w.meterBest.Visible = m.best > m.accuracy + 0.5
	end
	setText(w.meterValue, string.format("%d%%", math.floor(m.accuracy + 0.5)))
	setText(w.gradeLabel, grade(m.accuracy))
	for index, star in self._stars do
		local lit = m.accuracy >= (STAR_AT[index] or 100)
		setIconDim(star, if lit then 0 else 0.72)
	end

	-- Notices -------------------------------------------------------------
	local notice = self:_NoticeText()
	if w.noticeChip then
		w.noticeChip.Visible = notice ~= nil
	end
	setText(w.noticeLabel, notice or "")

	-- Chips ---------------------------------------------------------------
	self:_PaintChips()
	self:_PaintGhostView()
end

function PotteryWheelScreen:_SetChip(key: string, on: boolean)
	local chip = self._chips[key]
	if not chip or chip.on == on then
		return
	end
	local theme = self:GetTheme()
	chip.on = on
	local fill = if on then theme.Colors.Primary else theme.Colors.Surface
	chip.shape.BackgroundColor3 = fill
	if chip.stroke then
		chip.stroke.Color = GPLayoutKit.Deepen(theme, fill, 1)
	end
	-- Body-sized copy on rose is TextPrimary (5.15:1). TextOnPrimary measures
	-- 2.14:1 there and is illegal in this pack.
	chip.label.TextColor3 = if on then theme.Colors.TextPrimary else theme.Colors.TextSecondary
end

function PotteryWheelScreen:_PaintChips()
	local m = self._m
	local phase = self:_Phase()
	for _, blueprint in BLUEPRINTS do
		self:_SetChip("bp_" .. blueprint.name, self:_Blueprint().name == blueprint.name)
	end
	for _, tool in TOOLS do
		self:_SetChip("tool_" .. tool.id, m.tool == tool.id)
	end
	for _, tool in GLAZE_TOOLS do
		self:_SetChip("glaze_" .. tool.id, m.glazeTool == tool.id)
	end
	for _, dir in GLAZE_DIRS do
		self:_SetChip("dir_" .. dir.id, m.glazeDir == dir.id)
	end
	self:_SetChip("displaySpin", m.displaySpin)
	for _, profile in GROOVE_PROFILES do
		self:_SetChip("groove_" .. profile.id, m.grooveProfile == profile.id)
	end
	for _, n in RIDGE_SYMMETRY do
		self:_SetChip("ridge_" .. tostring(n), m.ridgeSymmetry == n)
	end
	for _, latch in LATCHES do
		self:_SetChip("latch_" .. latch.id, m.latch == latch.id)
	end
	self:_SetChip("guide", m.guideOn)
	self:_SetChip("view", m.targetView == "Outline")
	self:_SetChip("spin", m.spinning)
	local w = self._w
	setText(w.guideChipLabel, if m.guideOn then "Guide on" else "Guide off")
	setText(w.viewChipLabel, "Target: " .. m.targetView)
	setText(w.spinChipLabel, if m.spinning then "Wheel spinning" else "Wheel parked")
	setText(w.toolNote, toolNote(m.tool))
	-- Sub-rows follow the live tool, exactly as refreshShapeTools does.
	if w.grooveRow then
		w.grooveRow.Visible = phase == "Shape" and m.tool == "Groove"
	end
	if w.ridgeRow then
		w.ridgeRow.Visible = phase == "Shape" and m.tool == "Ridge"
	end
	if w.fireChipLabel then
		local fireText = "Fire the kiln"
		if m.storageFull then
			fireText = "Kiln blocked"
		elseif m.firing then
			fireText = "Firing\u{2026}"
		elseif m.fired then
			fireText = "Fired"
		end
		setText(w.fireChipLabel, fireText)
	end

	-- The phase tool bar swaps groups, exactly as PotteryFlow rebuilds its whole
	-- toolbar per phase.
	setText(w.phaseTitle, PHASE_TITLES[phase] or phase)
	for _, key in { "shapeGroup", "accGroup", "glazeGroup", "fireGroup", "displayGroup" } do
		local group = w[key]
		if group then
			group.Visible = false
		end
	end
	local liveGroup
	if phase == "Shape" then
		liveGroup = w.shapeGroup
	elseif phase == "Accessories" then
		liveGroup = w.accGroup
	elseif phase == "Glaze" then
		liveGroup = w.glazeGroup
	elseif phase == "Fire" then
		liveGroup = w.fireGroup
	else
		liveGroup = w.displayGroup
	end
	if liveGroup then
		liveGroup.Visible = true
	end

	-- Glaze bench readouts.
	setText(w.glazeNote, self:_GlazeNote())
	setText(
		w.glazeInfo,
		string.format("Brush %.3f studs \u{2022} coverage %d%% \u{2022} %d barrels left",
			m.glazeBrush, math.floor(m.coverage + 0.5), math.floor(m.paintStock))
	)

	-- Add-ons.
	setText(w.addonCount, string.format("%d of %d add-ons placed", m.addons, WHEEL.AccessorySlots))

	-- Kiln.
	setText(
		w.fireInfo,
		if m.fired
			then "Fired! The glaze has set."
			else string.format("Bake %.1fs at burn \u{00D7}%.2f", WHEEL.BakeSeconds * m.burnMult, m.burnMult)
	)

	-- Display fates.
	setText(w.displaySpinLabel, if m.displaySpin then "Spin: on" else "Spin: off")
	local fateText: string
	if m.finishMode == "deliver" then
		fateText = "Delivering\u{2026}"
	elseif m.finishMode == "sell" then
		fateText = "Selling\u{2026}"
	elseif m.commission ~= nil then
		fateText = "Deliver"
	elseif m.sellEstimate > 0 then
		fateText = string.format("Sell  $%d", m.sellEstimate)
	else
		fateText = "Sell"
	end
	setText(w.fateChipLabel, fateText)
	setText(w.storeChipLabel, if m.pillarsFull then "Pillars full" else "Make another")
	setText(w.shelfChipLabel, if m.shelfFull then "Shelf full" else "Shelf")
	setText(
		w.storageInfo,
		string.format("Pillars %d/%d \u{2022} shelf %d/%d", m.pillarsUsed, WHEEL.Pillars, m.shelfUsed, WHEEL.ShelfSlots)
	)
end

-- The live glaze tool's one-line explainer.
function PotteryWheelScreen:_GlazeNote(): string
	for _, tool in GLAZE_TOOLS do
		if tool.id == self._m.glazeTool then
			return tool.note
		end
	end
	return ""
end

-- The silhouette itself: 24 rows sampled off the blueprint's own r(t), so the
-- drawn ghost is the same curve the live game grades the pot against.
function PotteryWheelScreen:_PaintGhost()
	local rows = self._ghostRows
	if #rows == 0 then
		return
	end
	local blueprint = self:_Blueprint()
	local maxR = 0
	for index = 1, GHOST_ROWS do
		local t = (index - 0.5) / GHOST_ROWS
		maxR = math.max(maxR, blueprint.r(t))
	end
	maxR = math.max(maxR, 1e-3)
	for index, row in rows do
		local t = (index - 0.5) / GHOST_ROWS
		local width = math.clamp(blueprint.r(t) / maxR, 0.06, 1)
		row.Size = UDim2.new(width * 0.94, 0, 0, row.Size.Y.Offset)
	end
end

-- Ghost vs Outline. Only ever runs when the view actually changed: twenty-four
-- rows × a child lookup at 12Hz would be pure waste in a HUD that repaints
-- forever.
function PotteryWheelScreen:_PaintGhostView()
	local view = self._m.targetView
	if self._ghostView == view then
		return
	end
	self._ghostView = view
	local theme = self:GetTheme()
	local outline = view == "Outline"
	for _, row in self._ghostRows do
		row.BackgroundTransparency = if outline then 0.86 else 0.42
		local stroke = row:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = if outline then 0.1 else 0.65
			stroke.Color = GPLayoutKit.Deepen(theme, theme.Arcade.Blue, 1)
		end
	end
end

-- ========================================================================
-- GP LAYOUT
-- ========================================================================

-- A translucent cream chip: the only surface language this HUD uses. Petal
-- corners alternate by index, the stroke is a deepened tint of the fill, and
-- the shadow is hue-matched by the kit.
function PotteryWheelScreen:_GPPlate(name: string, index: number, sizePx: Vector2): Frame
	local theme = self:GetTheme()
	local fill = theme.Colors.Background
	local plate = surface(name, fill, CHIP_TRANSPARENCY)
	plate.Size = UDim2.fromOffset(sizePx.X, sizePx.Y)
	plate.Parent = self.Root
	GPLayoutKit.Petal(theme, plate, index)
	GPLayoutKit.SoftStroke(theme, plate, fill)
	GPLayoutKit.Shadow(theme, plate, "sm", self._shadows, fill)
	return plate
end

function PotteryWheelScreen:_GPChip(key: string, parent: Instance, text: string, index: number, widthPx: number, onClick: () -> ()): Chip
	local theme = self:GetTheme()
	local button = Instance.new("TextButton")
	button.Name = "Chip_" .. key
	-- Transparent button, fill on a chip child: the enforcer backstops a SOLID
	-- GuiButton with a BLACK stroke, which would violate law 1 on sight.
	button.BackgroundTransparency = 1
	button.Text = ""
	button.AutoButtonColor = false
	button.Size = UDim2.fromOffset(widthPx, 30)
	button.LayoutOrder = index
	button.Parent = parent

	local fill = theme.Colors.Surface
	local shape = surface("Shape", fill, 0)
	shape.Size = UDim2.fromScale(1, 1)
	shape.Parent = button
	GPLayoutKit.Petal(theme, shape, index)
	local stroke = GPLayoutKit.SoftStroke(theme, shape, fill)

	local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Label")
	label.Text = text
	label.Size = UDim2.fromScale(1, 1)
	label.Parent = shape

	button.Activated:Connect(onClick)
	UIChrome.Animate(theme, button, shape)

	local chip: Chip = { button = button, shape = shape, label = label, stroke = stroke, on = false }
	self._chips[key] = chip
	return chip
end

-- The rotating radial guide art. wheelRadial when the pack ships it; a soft
-- stroked ring otherwise, so a missing upload still reads as a wheel and never
-- as a solid pastel square sitting on the pot.
function PotteryWheelScreen:_GPRing(parent: Instance, sizePx: number, tint: Color3, transparency: number, name: string): GuiObject
	local theme = self:GetTheme()
	local assets = (theme :: any).Assets
	if assets and assets.wheelRadial then
		local ring = GPLayoutKit.Slice(theme, "wheelRadial", tint, name)
		ring.ImageTransparency = transparency
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 0.5)
		ring.Size = UDim2.fromOffset(sizePx, sizePx)
		ring.Parent = parent
		return ring
	end
	local ring = surface(name, tint, 1)
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(sizePx, sizePx)
	ring.Parent = parent
	UIStyler.Corner(theme.Radii.Pill).Parent = ring
	local stroke = UIStyler.Stroke(tint, 3, transparency)
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = ring
	return ring
end

function PotteryWheelScreen:_BuildGPLayout()
	local theme = self:GetTheme()
	self:_GPWheelField(theme)
	self:_GPTopRibbon(theme)
	self:_GPGuideRail(theme)
	self:_GPBlueprintPanel(theme)
	self:_GPSteadyPanel(theme)
	self:_GPReadouts(theme)
	self:_GPCarveBar(theme)
	self:_GPMeter(theme)
	self:_GPHints(theme)
	self:_PaintGhost()
end

-- The wheel field: rings, the wobble warning ring, the crosshair and the puck.
-- NOTHING here is a button and nothing is opaque — the pot has to stay visible
-- and clickable straight through it.
function PotteryWheelScreen:_GPWheelField(theme: Types.UITheme)
	local field = surface("WheelField", theme.Colors.Background, 1)
	field.AnchorPoint = Vector2.new(0.5, 0.5)
	field.Position = UDim2.new(0.5, 0, FIELD_Y, 0)
	field.Size = UDim2.fromOffset(WOBBLE_RING + 40, WOBBLE_RING + 40)
	field.Parent = self.Root

	local w = self._w
	w.ring1 = self:_GPRing(field, RING_SIZES[1], theme.Colors.Primary, 0.78, "RadialOuter")
	w.ring2 = self:_GPRing(field, RING_SIZES[2], theme.Colors.Secondary, 0.82, "RadialMid")
	w.ring3 = self:_GPRing(field, RING_SIZES[3], theme.Colors.Accent, 0.84, "RadialInner")

	-- The wobble warning ring: a stroke only, so it never dims the world.
	local wobble = surface("WobbleRing", theme.Colors.Background, 1)
	wobble.AnchorPoint = Vector2.new(0.5, 0.5)
	wobble.Position = UDim2.fromScale(0.5, 0.5)
	wobble.Size = UDim2.fromOffset(WOBBLE_RING, WOBBLE_RING)
	wobble.Parent = field
	UIStyler.Corner(theme.Radii.Pill).Parent = wobble
	local wobbleStroke = UIStyler.Stroke(theme.Colors.Secondary, 3, 0.42)
	wobbleStroke.LineJoinMode = Enum.LineJoinMode.Round
	wobbleStroke.Parent = wobble
	w.wobbleRing = wobble
	w.wobbleStroke = wobbleStroke

	-- Crosshair: two hairlines marking the true spin axis.
	for _, axis in { "H", "V" } do
		local line = surface("Axis" .. axis, theme.Colors.Stroke, 0.62)
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.Position = UDim2.fromScale(0.5, 0.5)
		line.Size = if axis == "H" then UDim2.fromOffset(RING_SIZES[3], 2) else UDim2.fromOffset(2, RING_SIZES[3])
		line.Parent = field
		UIStyler.Corner(theme.Radii.Pill).Parent = line
	end

	-- The centring puck.
	local puck = surface("CentringPuck", theme.Colors.Secondary, 0)
	puck.AnchorPoint = Vector2.new(0.5, 0.5)
	puck.Position = UDim2.fromScale(0.5, 0.5)
	puck.Size = UDim2.fromOffset(30, 30)
	puck.ZIndex = 4
	puck.Parent = field
	UIStyler.Corner(theme.Radii.Pill).Parent = puck
	w.puckStroke = GPLayoutKit.SoftStroke(theme, puck, theme.Colors.Secondary)
	w.puckShadow = GPLayoutKit.Shadow(theme, puck, "sm", self._shadows, theme.Colors.Secondary)
	w.puck = puck
end

function PotteryWheelScreen:_GPTopRibbon(theme: Types.UITheme)
	local spacing = theme.Spacing
	local plate = self:_GPPlate("Ribbon", 0, Vector2.new(700, 84))
	plate.AnchorPoint = Vector2.new(0.5, 0)
	plate.Position = UDim2.new(0.5, 0, 0, 16)

	local name = GPLayoutKit.Text(theme, theme.TextSizes.Subtitle, theme.Colors.TextPrimary, "Blueprint")
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Position = UDim2.fromOffset(spacing.M, spacing.S)
	name.Size = UDim2.new(0, 220, 0, 26)
	name.Parent = plate
	self._w.blueprintName = name

	local note = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Note")
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.TextTruncate = Enum.TextTruncate.AtEnd
	note.Position = UDim2.fromOffset(spacing.M, spacing.S + 26)
	note.Size = UDim2.new(0, 320, 0, 20)
	note.Parent = plate
	self._w.blueprintNote = note

	-- Commission badge: a commission overrides the deterministic rotation, so
	-- the ribbon has to say so.
	local badge = surface("Commission", theme.Colors.Accent, 0)
	badge.Position = UDim2.fromOffset(spacing.M, spacing.S + 48)
	badge.Size = UDim2.fromOffset(150, 22)
	badge.Visible = false
	badge.Parent = plate
	UIStyler.Corner(theme.Radii.Pill).Parent = badge
	GPLayoutKit.SoftStroke(theme, badge, theme.Colors.Accent)
	local badgeLabel = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "Label")
	badgeLabel.Text = "Commission order"
	badgeLabel.Size = UDim2.fromScale(1, 1)
	badgeLabel.Parent = badge
	self._w.commissionBadge = badge

	-- Status pill.
	local status = surface("Status", theme.Colors.Secondary, 0)
	status.AnchorPoint = Vector2.new(1, 0)
	status.Position = UDim2.new(1, -spacing.M, 0, spacing.S)
	status.Size = UDim2.fromOffset(212, 34)
	status.Parent = plate
	UIStyler.Corner(theme.Radii.Pill).Parent = status
	self._w.statusStroke = GPLayoutKit.SoftStroke(theme, status, theme.Colors.Secondary)
	self._w.statusChip = status
	local statusLabel = GPLayoutKit.Text(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "StatusLabel")
	statusLabel.Text = STATUS.Finding
	statusLabel.Size = UDim2.fromScale(1, 1)
	statusLabel.Parent = status
	self._w.statusLabel = statusLabel

	-- Phase pips reuse the kit's tab bar: selected reads FORWARD (rose fill,
	-- butter underline, a scale step), never a recolour.
	local tabHost = surface("PhaseHost", theme.Colors.Background, 1)
	tabHost.AnchorPoint = Vector2.new(1, 1)
	tabHost.Position = UDim2.new(1, -spacing.M, 1, -spacing.XS)
	tabHost.Size = UDim2.fromOffset(470, 34)
	tabHost.Parent = plate
	local tabs = GPLayoutKit.Tabs(theme, tabHost, { widthPx = 86, heightPx = 34, tabHeightPx = 28 }, self._shadows)
	for index, phase in PHASES do
		tabs.Add(PHASE_PIPS[phase] or phase, phase, function()
			self:_SelectPhase(index)
		end)
	end
	tabs.Select(PHASES[self._m.phaseIndex])
	self._w.phaseTabs = tabs
end

-- The guide slide: centre notch = the spin axis, a draggable marker either side
-- of it, a value bubble in studs and the tilt readout.
function PotteryWheelScreen:_GPGuideRail(theme: Types.UITheme)
	local spacing = theme.Spacing
	local plate = self:_GPPlate("GuideRail", 1, Vector2.new(520, 62))
	plate.AnchorPoint = Vector2.new(0.5, 0)
	plate.Position = UDim2.new(0.5, 0, 0, 110)

	local track = Instance.new("TextButton")
	track.Name = "Track"
	track.BackgroundColor3 = theme.Arcade.RulerTrack
	track.BackgroundTransparency = 0
	track.AutoButtonColor = false
	track.Text = ""
	track.AnchorPoint = Vector2.new(0.5, 0.5)
	track.Position = UDim2.new(0.5, 0, 0.5, 4)
	track.Size = UDim2.new(1, -spacing.XL, 0, 8)
	track.Parent = plate
	UIStyler.Corner(theme.Radii.Pill).Parent = track
	self._w.guideTrack = track
	self._w.guideRail = track

	local notch = surface("AxisNotch", theme.Arcade.RulerTick, 0)
	notch.AnchorPoint = Vector2.new(0.5, 0.5)
	notch.Position = UDim2.fromScale(0.5, 0.5)
	notch.Size = UDim2.fromOffset(3, 18)
	notch.ZIndex = 2
	notch.Parent = track
	UIStyler.Corner(theme.Radii.Pill).Parent = notch

	local marker = surface("Marker", theme.Colors.Primary, 0)
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Position = UDim2.fromScale(0.5, 0.5)
	marker.Size = UDim2.fromOffset(22, 22)
	marker.ZIndex = 3
	marker.Parent = track
	GPLayoutKit.Petal(theme, marker, 0)
	GPLayoutKit.SoftStroke(theme, marker, theme.Colors.Primary)
	self._w.guideMarker = marker

	local bubble = GPLayoutKit.NumberText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "Bubble")
	bubble.TextXAlignment = Enum.TextXAlignment.Center
	bubble.AnchorPoint = Vector2.new(0.5, 1)
	bubble.Position = UDim2.new(0.5, 0, 0, -6)
	bubble.Size = UDim2.fromOffset(92, 18)
	bubble.Visible = false
	bubble.ZIndex = 4
	bubble.Parent = marker
	self._w.guideBubble = bubble

	track.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			self._guideDrag = true
			self:_SetGuideFromX(input.Position.X)
		end
	end)
	track.InputChanged:Connect(function(input: InputObject)
		if
			self._guideDrag
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			self:_SetGuideFromX(input.Position.X)
		end
	end)

	local tilt = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Tilt")
	tilt.TextXAlignment = Enum.TextXAlignment.Left
	tilt.Position = UDim2.fromOffset(spacing.M, spacing.XS)
	tilt.Size = UDim2.fromOffset(120, 18)
	tilt.Parent = plate
	self._w.guideTiltLabel = tilt

	-- Tilt nudges (±0.1 of ToolAngle = ±3.5°) and the guide toggle.
	local row = surface("GuideRow", theme.Colors.Background, 1)
	row.AnchorPoint = Vector2.new(1, 0)
	row.Position = UDim2.new(1, -spacing.M, 0, spacing.XS)
	row.Size = UDim2.fromOffset(240, 30)
	row.Parent = plate
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, theme.Spacing.XS),
	}).Parent = row

	self:_GPChip("tiltDown", row, "\u{2212}", 0, 34, function()
		self._m.toolAngle = math.clamp(self._m.toolAngle - 0.1, -1, 1)
		self:_Paint()
	end)
	self:_GPChip("tiltUp", row, "+", 1, 34, function()
		self._m.toolAngle = math.clamp(self._m.toolAngle + 0.1, -1, 1)
		self:_Paint()
	end)
	local guideChip = self:_GPChip("guide", row, "Guide off", 2, 108, function()
		self._m.guideOn = not self._m.guideOn
		self:_Paint()
	end)
	self._w.guideChipLabel = guideChip.label
end

-- LEFT: the target ghost panel — the blueprint silhouette, its note, the view
-- toggle and the five-shape rotation.
function PotteryWheelScreen:_GPBlueprintPanel(theme: Types.UITheme)
	local spacing = theme.Spacing
	local plate = self:_GPPlate("BlueprintPanel", 0, Vector2.new(312, 436))
	plate.Position = UDim2.fromOffset(24, 172)

	GPLayoutKit.SectionLabel(theme, plate, "Target blueprint").Position = UDim2.fromOffset(spacing.M, spacing.S)

	-- The silhouette well. Rows are mirrored about the centre line, so the well
	-- clips nothing and needs no scroll.
	local well = surface("GhostWell", theme.Colors.Surface, 0.25)
	well.Position = UDim2.fromOffset(spacing.M, spacing.S + 30)
	well.Size = UDim2.new(1, -spacing.M * 2, 0, 236)
	well.ClipsDescendants = true
	well.Parent = plate
	GPLayoutKit.Petal(theme, well, 1)
	GPLayoutKit.SoftStroke(theme, well, theme.Colors.Surface)
	self._w.ghostWell = well

	local rowH = 236 / GHOST_ROWS
	for index = 1, GHOST_ROWS do
		-- Bottom row first: the profile samples base → rim, and the pot stands
		-- up in the well.
		local row = surface("GhostRow", theme.Arcade.Blue, 0.42)
		row.AnchorPoint = Vector2.new(0.5, 1)
		row.Position = UDim2.new(0.5, 0, 1, -math.floor((index - 1) * rowH))
		row.Size = UDim2.new(0.5, 0, 0, math.ceil(rowH) + 1)
		row.Parent = well
		GPLayoutKit.Petal(theme, row, index)
		local stroke = UIStyler.Stroke(GPLayoutKit.Deepen(theme, theme.Arcade.Blue, 1), 1, 0.65)
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		stroke.Parent = row
		table.insert(self._ghostRows, row)
	end

	local rim = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Rim")
	rim.Text = "rim"
	rim.TextXAlignment = Enum.TextXAlignment.Left
	rim.Position = UDim2.fromOffset(spacing.S, spacing.XS)
	rim.Size = UDim2.fromOffset(60, 16)
	rim.Parent = well
	local base = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Base")
	base.Text = "base"
	base.TextXAlignment = Enum.TextXAlignment.Left
	base.AnchorPoint = Vector2.new(0, 1)
	base.Position = UDim2.new(0, spacing.S, 1, -spacing.XS)
	base.Size = UDim2.fromOffset(60, 16)
	base.Parent = well

	local ask = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "HeightAsk")
	ask.TextXAlignment = Enum.TextXAlignment.Left
	ask.Position = UDim2.fromOffset(spacing.M, spacing.S + 272)
	ask.Size = UDim2.new(1, -spacing.M * 2, 0, 18)
	ask.Parent = plate
	self._w.heightAsk = ask

	local density = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Density")
	density.TextXAlignment = Enum.TextXAlignment.Left
	density.Position = UDim2.fromOffset(spacing.M, spacing.S + 292)
	density.Size = UDim2.new(1, -spacing.M * 2, 0, 18)
	density.Parent = plate
	self._w.densityLabel = density

	local viewChip = self:_GPChip("view", plate, "Target: Ghost", 0, 148, function()
		self._m.targetView = if self._m.targetView == "Ghost" then "Outline" else "Ghost"
		self:_Paint()
	end)
	viewChip.button.Position = UDim2.fromOffset(spacing.M, spacing.S + 316)
	self._w.viewChipLabel = viewChip.label

	local resetChip = self:_GPChip("reset", plate, "Reset clay", 1, 130, function()
		self:_ResetClay()
	end)
	resetChip.button.Position = UDim2.fromOffset(spacing.M + 154, spacing.S + 316)

	-- The five-shape rotation. The live game rotates deterministically off the
	-- stored-pot count; here the player can also pick.
	local row = surface("BlueprintChips", theme.Colors.Background, 1)
	row.Position = UDim2.fromOffset(spacing.M, spacing.S + 354)
	row.Size = UDim2.new(1, -spacing.M * 2, 0, 66)
	row.Parent = plate
	local grid = UIStyler.GridLayout(UDim2.fromOffset(88, 30), UDim2.fromOffset(6, 6))
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = row
	for index, blueprint in BLUEPRINTS do
		self:_GPChip("bp_" .. blueprint.name, row, blueprint.name, index, 88, function()
			self:_SelectBlueprint(index)
		end)
	end
end

-- LEFT-LOWER: the centring readout, the steady-hand pad and the three modal
-- latches (plain drag / Shift hollow / Alt height).
function PotteryWheelScreen:_GPSteadyPanel(theme: Types.UITheme)
	local spacing = theme.Spacing
	local plate = self:_GPPlate("SteadyPanel", 1, Vector2.new(312, 196))
	plate.Position = UDim2.fromOffset(24, 620)

	GPLayoutKit.SectionLabel(theme, plate, "Steady the throw").Position = UDim2.fromOffset(spacing.M, spacing.XS)

	local drift = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Drift")
	drift.TextXAlignment = Enum.TextXAlignment.Left
	drift.Position = UDim2.fromOffset(spacing.M, spacing.XS + 26)
	drift.Size = UDim2.new(1, -spacing.M * 2, 0, 18)
	drift.Parent = plate
	self._w.driftLabel = drift

	-- Contact chip: dot + copy + the intensity meter, the three feedback
	-- signals the source publishes as HasContact / ShapeDir / Intensity.
	local dot = surface("ContactDot", theme.Colors.Success, 0)
	dot.Position = UDim2.fromOffset(spacing.M, spacing.XS + 50)
	dot.Size = UDim2.fromOffset(12, 12)
	dot.Parent = plate
	UIStyler.Corner(theme.Radii.Pill).Parent = dot
	self._w.contactDot = dot

	local contact = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "Contact")
	contact.TextXAlignment = Enum.TextXAlignment.Left
	contact.Position = UDim2.fromOffset(spacing.M + 20, spacing.XS + 46)
	contact.Size = UDim2.new(1, -(spacing.M * 2 + 20), 0, 18)
	contact.Parent = plate
	self._w.contactLabel = contact

	local track = surface("IntensityTrack", theme.Arcade.RulerTrack, 0)
	track.Position = UDim2.fromOffset(spacing.M, spacing.XS + 70)
	track.Size = UDim2.new(1, -spacing.M * 2, 0, 6)
	track.Parent = plate
	UIStyler.Corner(theme.Radii.Pill).Parent = track
	local fill = surface("IntensityFill", theme.Colors.Primary, 0)
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = track
	UIStyler.Corner(theme.Radii.Pill).Parent = fill
	self._w.intensityFill = fill

	-- The steady-hand pad: the same correction the keys give, for touch and
	-- gamepad. Press-and-hold pushes; release lets go.
	local pad = surface("SteadyPad", theme.Colors.Background, 1)
	pad.Position = UDim2.fromOffset(spacing.M, spacing.XS + 84)
	pad.Size = UDim2.fromOffset(96, 62)
	pad.Parent = plate

	local function arrow(key: string, iconKey: string, position: UDim2, direction: Vector2)
		local button = Instance.new("TextButton")
		button.Name = "Steady_" .. key
		button.BackgroundTransparency = 1
		button.Text = ""
		button.AutoButtonColor = false
		button.Position = position
		button.Size = UDim2.fromOffset(28, 28)
		button.Parent = pad

		local shape = surface("Shape", theme.Colors.Surface, 0)
		shape.Size = UDim2.fromScale(1, 1)
		shape.Parent = button
		GPLayoutKit.Petal(theme, shape, if direction.X ~= 0 then 0 else 1)
		GPLayoutKit.SoftStroke(theme, shape, theme.Colors.Surface)
		iconArt(shape, iconKey, 18, theme.Colors.TextPrimary)

		button.MouseButton1Down:Connect(function()
			self._steady = direction
		end)
		button.MouseButton1Up:Connect(function()
			self._steady = Vector2.zero
		end)
		button.MouseLeave:Connect(function()
			self._steady = Vector2.zero
		end)
		UIChrome.Animate(theme, button, shape)
	end

	arrow("left", "arrowLeft", UDim2.fromOffset(0, 17), Vector2.new(-1, 0))
	arrow("right", "arrowRight", UDim2.fromOffset(64, 17), Vector2.new(1, 0))
	arrow("up", "arrowUp", UDim2.fromOffset(32, 0), Vector2.new(0, -1))
	arrow("down", "arrowDown", UDim2.fromOffset(32, 34), Vector2.new(0, 1))

	-- The three modal drags as latches.
	local latchRow = surface("Latches", theme.Colors.Background, 1)
	latchRow.Position = UDim2.fromOffset(spacing.M + 108, spacing.XS + 84)
	latchRow.Size = UDim2.fromOffset(160, 62)
	latchRow.Parent = plate
	local list = UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Padding = UDim.new(0, spacing.XS),
	})
	list.Wraps = true
	list.Parent = latchRow
	for index, latch in LATCHES do
		self:_GPChip("latch_" .. latch.id, latchRow, latch.label, index, 76, function()
			self._m.latch = latch.id
			self:_Paint()
		end)
	end
end

-- RIGHT: the dense readout column. Fourteen stat rows in a clipped scrolling
-- viewport with padding, so no shadow or capsule is ever sliced by the edge.
function PotteryWheelScreen:_GPReadouts(theme: Types.UITheme)
	local spacing = theme.Spacing
	local plate = self:_GPPlate("Readouts", 1, Vector2.new(342, 452))
	plate.AnchorPoint = Vector2.new(1, 0)
	plate.Position = UDim2.new(1, -24, 0, 150)

	GPLayoutKit.SectionLabel(theme, plate, "Wheel readouts").Position = UDim2.fromOffset(spacing.M, spacing.XS)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Rows"
	scroll.BackgroundColor3 = theme.Colors.Background
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(spacing.S, spacing.XS + 26)
	scroll.Size = UDim2.new(1, -spacing.S * 2, 1, -(spacing.XS + 34))
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 5
	scroll.ScrollBarImageColor3 = theme.Colors.Stroke
	scroll.ClipsDescendants = true
	scroll.Parent = plate
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Padding = UDim.new(0, 2),
	}).Parent = scroll
	UIStyler.PaddingXY(spacing.S, spacing.XS).Parent = scroll

	for index, spec in READOUTS do
		local row = GPLayoutKit.StatRow(theme, scroll, {
			label = spec.label,
			value = self:_ReadoutValue(spec.id),
			maxValue = spec.max,
			unit = spec.unit,
			precision = spec.precision,
			invertGoodness = spec.invert,
			accent = if spec.invert then theme.Colors.Secondary else theme.Colors.Primary,
			layoutOrder = index,
		})
		self._rows[spec.id] = row
	end
end

-- A horizontal chip row inside the phase tool bar. One helper so every group
-- lays out identically and the file never repeats a ListLayout block.
local function chipRow(theme: Types.UITheme, parent: Instance, name: string, y: number): Frame
	local row = surface(name, theme.Colors.Background, 1)
	row.Position = UDim2.fromOffset(0, y)
	row.Size = UDim2.new(1, 0, 0, 30)
	row.Parent = parent
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, theme.Spacing.XS),
	}).Parent = row
	return row
end

-- RIGHT-LOWER: the PHASE tool bar. PotteryFlow rebuilds its entire toolbar per
-- phase, so this plate carries one group per phase and swaps them — carve tools
-- on Shape, the add-on bar on Accessories, the glaze bench on Glaze, the kiln on
-- Fire, and the finished pot's fates on Display.
function PotteryWheelScreen:_GPCarveBar(theme: Types.UITheme)
	local spacing = theme.Spacing
	local w = self._w
	local plate = self:_GPPlate("PhaseTools", 0, Vector2.new(342, 250))
	plate.AnchorPoint = Vector2.new(1, 0)
	plate.Position = UDim2.new(1, -24, 0, 620)

	local title = GPLayoutKit.SectionLabel(theme, plate, PHASE_TITLES.Shape)
	title.Position = UDim2.fromOffset(spacing.M, spacing.XS)
	w.phaseTitle = title

	-- One host per phase, stacked in the same slot; _PaintChips shows exactly one.
	local function group(name: string): Frame
		local host = surface(name, theme.Colors.Background, 1)
		host.Position = UDim2.fromOffset(spacing.M, spacing.XS + 26)
		host.Size = UDim2.new(1, -spacing.M * 2, 0, 154)
		host.Visible = false
		host.Parent = plate
		return host
	end

	local function note(parent: Instance, name: string, y: number): TextLabel
		local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, name)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextWrapped = true
		label.Position = UDim2.fromOffset(0, y)
		label.Size = UDim2.new(1, 0, 0, 32)
		label.Parent = parent
		return label
	end

	-- ---- Shape: Hands / Groove / Ridge with their sub-rows -----------------
	local shapeGroup = group("ShapeGroup")
	w.shapeGroup = shapeGroup
	local toolRow = chipRow(theme, shapeGroup, "Tools", 0)
	for index, tool in TOOLS do
		self:_GPChip("tool_" .. tool.id, toolRow, tool.label, index, 96, function()
			self:_SelectTool(tool.id)
		end)
	end
	w.toolNote = note(shapeGroup, "ToolNote", 34)

	local grooveRow = chipRow(theme, shapeGroup, "GrooveRow", 68)
	grooveRow.Visible = false
	for index, profile in GROOVE_PROFILES do
		self:_GPChip("groove_" .. profile.id, grooveRow, profile.label, index, 44, function()
			self._m.grooveProfile = profile.id
			self:_Paint()
		end)
	end
	w.grooveRow = grooveRow

	local ridgeRow = chipRow(theme, shapeGroup, "RidgeRow", 68)
	ridgeRow.Visible = false
	for index, n in RIDGE_SYMMETRY do
		self:_GPChip("ridge_" .. tostring(n), ridgeRow, tostring(n), index, 44, function()
			self._m.ridgeSymmetry = n
			self:_Paint()
		end)
	end
	w.ridgeRow = ridgeRow

	-- ---- Accessories: place and clear the add-ons --------------------------
	local accGroup = group("AccGroup")
	w.accGroup = accGroup
	local accRow = chipRow(theme, accGroup, "AccRow", 0)
	self:_GPChip("accPlace", accRow, "Place a piece", 0, 144, function()
		self:_PlaceAccessory()
	end)
	self:_GPChip("accClear", accRow, "Clear", 1, 92, function()
		self:_ClearAccessories()
	end)
	local addonCount = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "AddonCount")
	addonCount.TextXAlignment = Enum.TextXAlignment.Left
	addonCount.Position = UDim2.fromOffset(0, 36)
	addonCount.Size = UDim2.new(1, 0, 0, 18)
	addonCount.Parent = accGroup
	w.addonCount = addonCount
	local accNote = note(accGroup, "AccNote", 58)
	accNote.Text = "Click the pot to place a piece, then drag its arrows to move it and its rings to spin it."

	-- ---- Glaze: Paint / Erase / Fill, bands or lines, brush size ----------
	local glazeGroup = group("GlazeGroup")
	w.glazeGroup = glazeGroup
	local glazeRow = chipRow(theme, glazeGroup, "GlazeTools", 0)
	for index, tool in GLAZE_TOOLS do
		self:_GPChip("glaze_" .. tool.id, glazeRow, tool.label, index, 92, function()
			self._m.glazeTool = tool.id
			self:_Paint()
		end)
	end
	local dirRow = chipRow(theme, glazeGroup, "GlazeDirs", 34)
	for index, dir in GLAZE_DIRS do
		self:_GPChip("dir_" .. dir.id, dirRow, dir.label, index, 78, function()
			self._m.glazeDir = dir.id
			self:_Paint()
		end)
	end
	self:_GPChip("brushDown", dirRow, "\u{2212}", 3, 40, function()
		self:_NudgeBrush(-WHEEL.BrushStep)
	end)
	self:_GPChip("brushUp", dirRow, "+", 4, 40, function()
		self:_NudgeBrush(WHEEL.BrushStep)
	end)
	w.glazeNote = note(glazeGroup, "GlazeNote", 68)
	local glazeInfo = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "GlazeInfo")
	glazeInfo.TextXAlignment = Enum.TextXAlignment.Left
	glazeInfo.TextTruncate = Enum.TextTruncate.AtEnd
	glazeInfo.Position = UDim2.fromOffset(0, 100)
	glazeInfo.Size = UDim2.new(1, 0, 0, 18)
	glazeInfo.Parent = glazeGroup
	w.glazeInfo = glazeInfo
	local resetPaint = chipRow(theme, glazeGroup, "ResetPaintRow", 122)
	self:_GPChip("resetGlaze", resetPaint, "Reset paint", 0, 130, function()
		self:_ResetGlaze()
	end)

	-- ---- Fire: the kiln --------------------------------------------------
	local fireGroup = group("FireGroup")
	w.fireGroup = fireGroup
	local fireRow = chipRow(theme, fireGroup, "FireRow", 0)
	local fireChip = self:_GPChip("fire", fireRow, "Fire the kiln", 0, 168, function()
		self:_StartFiring()
	end)
	w.fireChipLabel = fireChip.label
	self:_GPChip("toDisplay", fireRow, "Display", 1, 110, function()
		self:_SelectPhase(PHASE_INDEX.Display)
	end)
	local fireInfo = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "FireInfo")
	fireInfo.TextXAlignment = Enum.TextXAlignment.Left
	fireInfo.Position = UDim2.fromOffset(0, 36)
	fireInfo.Size = UDim2.new(1, 0, 0, 18)
	fireInfo.Parent = fireGroup
	w.fireInfo = fireInfo
	note(fireGroup, "FireNote", 58).Text =
		"A fired pot needs somewhere to live, so the kiln refuses when storage is full."

	-- ---- Display: the pot's fate, both destinations, the turntable --------
	local displayGroup = group("DisplayGroup")
	w.displayGroup = displayGroup
	local fateRow = chipRow(theme, displayGroup, "FateRow", 0)
	local fateChip = self:_GPChip("fate", fateRow, "Sell", 0, 150, function()
		self:_FinishPot()
	end)
	w.fateChipLabel = fateChip.label
	local spinDisplay = self:_GPChip("displaySpin", fateRow, "Spin: on", 1, 112, function()
		self._m.displaySpin = not self._m.displaySpin
		self:_Paint()
	end)
	w.displaySpinLabel = spinDisplay.label

	local storeRow = chipRow(theme, displayGroup, "StoreRow", 34)
	local storeChip = self:_GPChip("store", storeRow, "Make another", 0, 152, function()
		self:_StorePot("pillar")
	end)
	w.storeChipLabel = storeChip.label
	local shelfChip = self:_GPChip("shelf", storeRow, "Shelf", 1, 108, function()
		self:_StorePot("shelf")
	end)
	w.shelfChipLabel = shelfChip.label

	local clearRow = chipRow(theme, displayGroup, "ClearRow", 68)
	self:_GPChip("sellStored", clearRow, "Sell a stored pot", 0, 176, function()
		self:_SellStoredPot()
	end)

	local storageInfo = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextPrimary, "StorageInfo")
	storageInfo.TextXAlignment = Enum.TextXAlignment.Left
	storageInfo.Position = UDim2.fromOffset(0, 104)
	storageInfo.Size = UDim2.new(1, 0, 0, 18)
	storageInfo.Parent = displayGroup
	w.storageInfo = storageInfo
	local displayNote = note(displayGroup, "DisplayNote", 124)
	displayNote.Size = UDim2.new(1, 0, 0, 30)
	displayNote.Text =
		"Storing a pot clears the wheel and rolls the next blueprint; a commission keeps its own target."

	-- ---- The working-wheel spin gate, live in every phase -----------------
	local bottom = surface("PhaseBottom", theme.Colors.Background, 1)
	bottom.AnchorPoint = Vector2.new(0, 1)
	bottom.Position = UDim2.new(0, spacing.M, 1, -spacing.S)
	bottom.Size = UDim2.new(1, -spacing.M * 2, 0, 30)
	bottom.Parent = plate
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, spacing.XS),
	}).Parent = bottom

	local spinChip = self:_GPChip("spin", bottom, "Wheel spinning", 0, 158, function()
		local m = self._m
		m.spinning = not m.spinning
		m.spinRestore = m.spinning
		self:_Paint()
	end)
	w.spinChipLabel = spinChip.label

	-- Back / Next: every phase of the source's toolbar carries them.
	self:_GPChip("phaseBack", bottom, "\u{25C0} Back", 1, 66, function()
		self:_SelectPhase(self._m.phaseIndex - 1)
	end)
	self:_GPChip("phaseNext", bottom, "Next \u{25B6}", 2, 66, function()
		self:_SelectPhase(self._m.phaseIndex + 1)
	end)
end

-- BOTTOM: the accuracy meter, the grade word, the star badge and the notice
-- strip that carries the game's two real blocked-state strings.
function PotteryWheelScreen:_GPMeter(theme: Types.UITheme)
	local spacing = theme.Spacing
	local plate = self:_GPPlate("Meter", 0, Vector2.new(680, 92))
	plate.AnchorPoint = Vector2.new(0.5, 1)
	plate.Position = UDim2.new(0.5, 0, 1, -104)

	local caption = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Caption")
	caption.Text = "Match to blueprint"
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.Position = UDim2.fromOffset(spacing.M, spacing.XS)
	caption.Size = UDim2.fromOffset(220, 18)
	caption.Parent = plate

	local value = GPLayoutKit.NumberText(theme, theme.TextSizes.Title, theme.Colors.TextPrimary, "Value")
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.new(1, -spacing.M, 0, spacing.XS)
	value.Size = UDim2.fromOffset(120, 34)
	value.Parent = plate
	self._w.meterValue = value

	local gradeLabel = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "Grade")
	gradeLabel.TextXAlignment = Enum.TextXAlignment.Left
	gradeLabel.Position = UDim2.fromOffset(spacing.M + 224, spacing.XS)
	gradeLabel.Size = UDim2.fromOffset(240, 18)
	gradeLabel.Parent = plate
	self._w.gradeLabel = gradeLabel

	-- Star badge: the commission board's five-star preview reads off exactly
	-- this number in the live game.
	local starRow = surface("Stars", theme.Colors.Background, 1)
	starRow.AnchorPoint = Vector2.new(1, 0)
	starRow.Position = UDim2.new(1, -(spacing.M + 124), 0, spacing.XS + 2)
	starRow.Size = UDim2.fromOffset(140, 26)
	starRow.Parent = plate
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 4),
	}).Parent = starRow
	for index = 1, #STAR_AT do
		local star = iconArt(starRow, "star", 22, theme.Colors.Accent)
		star.AnchorPoint = Vector2.new(0, 0)
		star.Position = UDim2.fromOffset(0, 0)
		star.LayoutOrder = index
		table.insert(self._stars, star)
	end

	local track = surface("MeterTrack", theme.Arcade.RulerTrack, 0)
	track.AnchorPoint = Vector2.new(0.5, 1)
	track.Position = UDim2.new(0.5, 0, 1, -spacing.M)
	track.Size = UDim2.new(1, -spacing.M * 2, 0, 18)
	track.ClipsDescendants = true
	track.Parent = plate
	UIStyler.Corner(theme.Radii.Pill).Parent = track

	local fill = surface("MeterFill", theme.Colors.Primary, 0)
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = 2
	fill.Parent = track
	UIStyler.Corner(theme.Radii.Pill).Parent = fill
	self._w.meterFill = fill

	-- Grade thresholds, drawn on the track so the bands are legible.
	for _, band in GRADES do
		if band.at > 0 then
			local tick = surface("Tick", theme.Arcade.RulerTick, 0.35)
			tick.AnchorPoint = Vector2.new(0.5, 0.5)
			tick.Position = UDim2.fromScale(band.at / 100, 0.5)
			tick.Size = UDim2.fromOffset(2, 12)
			tick.ZIndex = 3
			tick.Parent = track
		end
	end

	local best = surface("BestMark", theme.Colors.Accent, 0)
	best.AnchorPoint = Vector2.new(0.5, 0)
	best.Size = UDim2.new(0, 4, 1, 0)
	best.ZIndex = 4
	best.Visible = false
	best.Parent = track
	UIStyler.Corner(theme.Radii.Pill).Parent = best
	self._w.meterBest = best

	-- The notice strip (storage full / out of glaze / kiln progress).
	local notice = self:_GPPlate("Notice", 1, Vector2.new(680, 40))
	notice.AnchorPoint = Vector2.new(0.5, 1)
	notice.Position = UDim2.new(0.5, 0, 1, -202)
	notice.Visible = false
	self._w.noticeChip = notice

	local noticeLabel = GPLayoutKit.BodyText(theme, theme.TextSizes.Body, theme.Colors.TextPrimary, "NoticeLabel")
	noticeLabel.TextXAlignment = Enum.TextXAlignment.Left
	noticeLabel.TextTruncate = Enum.TextTruncate.AtEnd
	noticeLabel.Position = UDim2.fromOffset(theme.Spacing.M + 26, 0)
	noticeLabel.Size = UDim2.new(1, -(theme.Spacing.M * 2 + 26), 1, 0)
	noticeLabel.Parent = notice
	self._w.noticeLabel = noticeLabel

	local warn = iconArt(notice, "warning", 20, theme.Colors.Warning)
	warn.AnchorPoint = Vector2.new(0, 0.5)
	warn.Position = UDim2.new(0, theme.Spacing.S, 0.5, 0)
end

function PotteryWheelScreen:_GPHints(theme: Types.UITheme)
	local plate = self:_GPPlate("Hints", 1, Vector2.new(1000, 40))
	plate.AnchorPoint = Vector2.new(0.5, 1)
	plate.Position = UDim2.new(0.5, 0, 1, -52)

	local label = GPLayoutKit.BodyText(theme, theme.TextSizes.Small, theme.Colors.TextSecondary, "Hints")
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Size = UDim2.new(1, -theme.Spacing.M * 2, 1, 0)
	label.Position = UDim2.fromOffset(theme.Spacing.M, 0)
	label.Parent = plate
	self._w.hintLabel = label
end

-- ========================================================================
-- ARCADE LAYOUT — the same model, the house arcade language. Every readout in
-- READOUTS is present here too; the branch is leaner, never smaller.
-- ========================================================================

-- The house arcade panel recipe, composed here rather than through
-- UIChrome.Panel for one reason: Panel drops a shadow whose BUDGET HANDLE it
-- never returns, and this screen owes every handle to _OnTeardown.
function PotteryWheelScreen:_ArcadePanel(name: string, sizePx: Vector2): Frame
	local theme = self:GetTheme()
	local panel = surface(name, theme.Arcade.Panel, 0.25)
	panel.Size = UDim2.fromOffset(sizePx.X, sizePx.Y)
	panel.Parent = self.Root
	UIChrome.Corner("Arcade", "Panel").Parent = panel
	UIChrome.Stroke(theme, "Arcade", "Panel").Parent = panel
	UIChrome.GlassGradient().Parent = panel
	if theme.EffectShadows then
		local _shadow, handle = UIChrome.Shadow(theme, "md", panel)
		table.insert(self._shadows, handle)
	end
	return panel
end

function PotteryWheelScreen:_ArcadeChip(key: string, parent: Instance, text: string, index: number, widthPx: number, onClick: () -> ()): Chip
	local theme = self:GetTheme()
	local button = Instance.new("TextButton")
	button.Name = "Chip_" .. key
	button.BackgroundTransparency = 1
	button.Text = ""
	button.AutoButtonColor = false
	button.Size = UDim2.fromOffset(widthPx, 30)
	button.LayoutOrder = index
	button.Parent = parent

	local shape = surface("Shape", theme.Arcade.Row, 0)
	shape.Size = UDim2.fromScale(1, 1)
	shape.Parent = button
	UIChrome.Corner("Arcade", "Button").Parent = shape
	UIChrome.Stroke(theme, "Arcade", "Button").Parent = shape

	local label = UIChrome.BodyText("Label", theme.TextSizes.Small, theme.Colors.TextPrimary)
	label.Text = text
	label.Size = UDim2.fromScale(1, 1)
	label.Parent = shape

	button.Activated:Connect(onClick)
	UIChrome.Animate(theme, button, shape)

	local chip: Chip = { button = button, shape = shape, label = label, stroke = nil, on = false }
	self._chips[key] = chip
	return chip
end

function PotteryWheelScreen:_BuildArcadeLayout()
	local theme = self:GetTheme()
	local w = self._w

	-- Wheel field (rings + wobble ring + puck) — identical geometry, arcade
	-- palette. Nothing here is interactive.
	local field = surface("WheelField", theme.Colors.Background, 1)
	field.AnchorPoint = Vector2.new(0.5, 0.5)
	field.Position = UDim2.new(0.5, 0, FIELD_Y, 0)
	field.Size = UDim2.fromOffset(WOBBLE_RING + 40, WOBBLE_RING + 40)
	field.Parent = self.Root
	w.ring1 = self:_GPRing(field, RING_SIZES[1], theme.Colors.Primary, 0.72, "RadialOuter")
	w.ring2 = self:_GPRing(field, RING_SIZES[2], theme.Colors.Accent, 0.78, "RadialMid")
	w.ring3 = self:_GPRing(field, RING_SIZES[3], theme.Colors.Secondary, 0.8, "RadialInner")

	local wobble = surface("WobbleRing", theme.Colors.Background, 1)
	wobble.AnchorPoint = Vector2.new(0.5, 0.5)
	wobble.Position = UDim2.fromScale(0.5, 0.5)
	wobble.Size = UDim2.fromOffset(WOBBLE_RING, WOBBLE_RING)
	wobble.Parent = field
	UIStyler.Corner(1000).Parent = wobble
	local wobbleStroke = UIStyler.Stroke(theme.Colors.Success, 3, 0.4)
	wobbleStroke.Parent = wobble
	w.wobbleStroke = wobbleStroke

	local puck = surface("CentringPuck", theme.Colors.Success, 0)
	puck.AnchorPoint = Vector2.new(0.5, 0.5)
	puck.Position = UDim2.fromScale(0.5, 0.5)
	puck.Size = UDim2.fromOffset(28, 28)
	puck.ZIndex = 4
	puck.Parent = field
	UIStyler.Corner(1000).Parent = puck
	UIChrome.Stroke(theme, "Arcade", "Button").Parent = puck
	w.puck = puck

	-- Top ribbon.
	local ribbon = self:_ArcadePanel("Ribbon", Vector2.new(700, 84))
	ribbon.AnchorPoint = Vector2.new(0.5, 0)
	ribbon.Position = UDim2.new(0.5, 0, 0, 16)

	local name = UIChrome.Text("Blueprint", theme.TextSizes.Subtitle, theme.Colors.TextPrimary)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Position = UDim2.fromOffset(14, 6)
	name.Size = UDim2.fromOffset(240, 26)
	name.Parent = ribbon
	w.blueprintName = name

	local note = UIChrome.BodyText("Note", theme.TextSizes.Small, theme.Colors.TextSecondary)
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.Position = UDim2.fromOffset(14, 32)
	note.Size = UDim2.fromOffset(340, 18)
	note.Parent = ribbon
	w.blueprintNote = note

	local status = surface("Status", theme.Colors.Success, 0)
	status.AnchorPoint = Vector2.new(1, 0)
	status.Position = UDim2.new(1, -14, 0, 8)
	status.Size = UDim2.fromOffset(220, 32)
	status.Parent = ribbon
	UIChrome.Corner("Arcade", "Button").Parent = status
	UIChrome.Stroke(theme, "Arcade", "Button").Parent = status
	w.statusChip = status

	local statusLabel = UIChrome.Text("StatusLabel", theme.TextSizes.Body, theme.Colors.TextPrimary)
	statusLabel.Text = STATUS.Finding
	statusLabel.Size = UDim2.fromScale(1, 1)
	statusLabel.Parent = status
	w.statusLabel = statusLabel

	local phaseRow = surface("Phases", theme.Colors.Background, 1)
	phaseRow.AnchorPoint = Vector2.new(1, 1)
	phaseRow.Position = UDim2.new(1, -14, 1, -6)
	phaseRow.Size = UDim2.fromOffset(470, 30)
	phaseRow.Parent = ribbon
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
	}).Parent = phaseRow
	for index, phase in PHASES do
		self:_ArcadeChip("phase_" .. phase, phaseRow, PHASE_PIPS[phase] or phase, index, 86, function()
			self:_SelectPhase(index)
		end)
	end
	-- The arcade branch has no TabBar; phase selection paints through _SetChip.
	w.phaseTabs = {
		Select = function(phase: string)
			for _, entry in PHASES do
				self:_SetChip("phase_" .. entry, entry == phase)
			end
		end,
	}

	-- Left: the ghost silhouette + blueprint chips.
	local left = self:_ArcadePanel("BlueprintPanel", Vector2.new(312, 436))
	left.Position = UDim2.fromOffset(24, 172)

	local well = surface("GhostWell", theme.Arcade.NearBlack, 0.2)
	well.Position = UDim2.fromOffset(14, 14)
	well.Size = UDim2.new(1, -28, 0, 236)
	well.ClipsDescendants = true
	well.Parent = left
	UIChrome.Corner("Arcade", "Panel").Parent = well
	UIChrome.Stroke(theme, "Arcade", "Panel").Parent = well
	w.ghostWell = well

	local rowH = 236 / GHOST_ROWS
	for index = 1, GHOST_ROWS do
		local row = surface("GhostRow", theme.Arcade.Blue, 0.42)
		row.AnchorPoint = Vector2.new(0.5, 1)
		row.Position = UDim2.new(0.5, 0, 1, -math.floor((index - 1) * rowH))
		row.Size = UDim2.new(0.5, 0, 0, math.ceil(rowH) + 1)
		row.Parent = well
		table.insert(self._ghostRows, row)
	end

	local ask = UIChrome.BodyText("HeightAsk", theme.TextSizes.Small, theme.Colors.TextSecondary)
	ask.TextXAlignment = Enum.TextXAlignment.Left
	ask.Position = UDim2.fromOffset(14, 258)
	ask.Size = UDim2.new(1, -28, 0, 18)
	ask.Parent = left
	w.heightAsk = ask

	local density = UIChrome.BodyText("Density", theme.TextSizes.Small, theme.Colors.TextSecondary)
	density.TextXAlignment = Enum.TextXAlignment.Left
	density.Position = UDim2.fromOffset(14, 278)
	density.Size = UDim2.new(1, -28, 0, 18)
	density.Parent = left
	w.densityLabel = density

	local viewChip = self:_ArcadeChip("view", left, "Target: Ghost", 0, 148, function()
		self._m.targetView = if self._m.targetView == "Ghost" then "Outline" else "Ghost"
		self:_Paint()
	end)
	viewChip.button.Position = UDim2.fromOffset(14, 302)
	w.viewChipLabel = viewChip.label

	local resetChip = self:_ArcadeChip("reset", left, "Reset clay", 1, 130, function()
		self:_ResetClay()
	end)
	resetChip.button.Position = UDim2.fromOffset(168, 302)

	local bpRow = surface("BlueprintChips", theme.Colors.Background, 1)
	bpRow.Position = UDim2.fromOffset(14, 340)
	bpRow.Size = UDim2.new(1, -28, 0, 76)
	bpRow.Parent = left
	local grid = UIStyler.GridLayout(UDim2.fromOffset(88, 30), UDim2.fromOffset(6, 6))
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = bpRow
	for index, blueprint in BLUEPRINTS do
		self:_ArcadeChip("bp_" .. blueprint.name, bpRow, blueprint.name, index, 88, function()
			self:_SelectBlueprint(index)
		end)
	end

	-- Left-lower: contact + drift + latches.
	local steady = self:_ArcadePanel("SteadyPanel", Vector2.new(312, 196))
	steady.Position = UDim2.fromOffset(24, 620)

	local drift = UIChrome.BodyText("Drift", theme.TextSizes.Small, theme.Colors.TextSecondary)
	drift.TextXAlignment = Enum.TextXAlignment.Left
	drift.Position = UDim2.fromOffset(14, 10)
	drift.Size = UDim2.new(1, -28, 0, 18)
	drift.Parent = steady
	w.driftLabel = drift

	local dot = surface("ContactDot", theme.Colors.Success, 0)
	dot.Position = UDim2.fromOffset(14, 38)
	dot.Size = UDim2.fromOffset(12, 12)
	dot.Parent = steady
	UIStyler.Corner(1000).Parent = dot
	w.contactDot = dot

	local contact = UIChrome.BodyText("Contact", theme.TextSizes.Small, theme.Colors.TextPrimary)
	contact.TextXAlignment = Enum.TextXAlignment.Left
	contact.Position = UDim2.fromOffset(34, 34)
	contact.Size = UDim2.new(1, -48, 0, 18)
	contact.Parent = steady
	w.contactLabel = contact

	local intensityTrack = surface("IntensityTrack", theme.Arcade.RulerTrack, 0)
	intensityTrack.Position = UDim2.fromOffset(14, 58)
	intensityTrack.Size = UDim2.new(1, -28, 0, 6)
	intensityTrack.Parent = steady
	local intensityFill = surface("IntensityFill", theme.Colors.Primary, 0)
	intensityFill.Size = UDim2.fromScale(0, 1)
	intensityFill.Parent = intensityTrack
	w.intensityFill = intensityFill

	local latchRow = surface("Latches", theme.Colors.Background, 1)
	latchRow.Position = UDim2.fromOffset(14, 76)
	latchRow.Size = UDim2.new(1, -28, 0, 30)
	latchRow.Parent = steady
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
	}).Parent = latchRow
	for index, latch in LATCHES do
		self:_ArcadeChip("latch_" .. latch.id, latchRow, latch.label, index, 88, function()
			self._m.latch = latch.id
			self:_Paint()
		end)
	end

	local guideRow = surface("GuideRow", theme.Colors.Background, 1)
	guideRow.Position = UDim2.fromOffset(14, 112)
	guideRow.Size = UDim2.new(1, -28, 0, 30)
	guideRow.Parent = steady
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
	}).Parent = guideRow
	local guideChip = self:_ArcadeChip("guide", guideRow, "Guide off", 0, 108, function()
		self._m.guideOn = not self._m.guideOn
		self:_Paint()
	end)
	w.guideChipLabel = guideChip.label
	self:_ArcadeChip("tiltDown", guideRow, "\u{2212}", 1, 40, function()
		self._m.toolAngle = math.clamp(self._m.toolAngle - 0.1, -1, 1)
		self:_Paint()
	end)
	self:_ArcadeChip("tiltUp", guideRow, "+", 2, 40, function()
		self._m.toolAngle = math.clamp(self._m.toolAngle + 0.1, -1, 1)
		self:_Paint()
	end)

	local tilt = UIChrome.BodyText("Tilt", theme.TextSizes.Small, theme.Colors.TextSecondary)
	tilt.TextXAlignment = Enum.TextXAlignment.Left
	tilt.Position = UDim2.fromOffset(14, 148)
	tilt.Size = UDim2.new(1, -28, 0, 18)
	tilt.Parent = steady
	w.guideTiltLabel = tilt

	-- Right: the readout column (same READOUTS, arcade rows).
	local right = self:_ArcadePanel("Readouts", Vector2.new(342, 452))
	right.AnchorPoint = Vector2.new(1, 0)
	right.Position = UDim2.new(1, -24, 0, 150)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Rows"
	scroll.BackgroundColor3 = theme.Colors.Background
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(10, 10)
	scroll.Size = UDim2.new(1, -20, 1, -20)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 5
	scroll.ScrollBarImageColor3 = theme.Colors.Accent
	scroll.ClipsDescendants = true
	scroll.Parent = right
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Padding = UDim.new(0, 2),
	}).Parent = scroll
	UIStyler.PaddingXY(8, 4).Parent = scroll

	for index, spec in READOUTS do
		self._rows[spec.id] = self:_ArcadeRow(scroll, spec, index)
	end

	-- Right-lower: the SAME per-phase tool bar the GP branch carries.
	local carve = self:_ArcadePanel("PhaseTools", Vector2.new(342, 250))
	carve.AnchorPoint = Vector2.new(1, 0)
	carve.Position = UDim2.new(1, -24, 0, 620)

	local phaseTitle = UIChrome.Text("PhaseTitle", theme.TextSizes.Body, theme.Colors.Accent)
	phaseTitle.TextXAlignment = Enum.TextXAlignment.Left
	phaseTitle.Text = PHASE_TITLES.Shape
	phaseTitle.Position = UDim2.fromOffset(14, 6)
	phaseTitle.Size = UDim2.new(1, -28, 0, 22)
	phaseTitle.Parent = carve
	w.phaseTitle = phaseTitle

	local function arcGroup(name: string): Frame
		local host = surface(name, theme.Colors.Background, 1)
		host.Position = UDim2.fromOffset(14, 32)
		host.Size = UDim2.new(1, -28, 0, 154)
		host.Visible = false
		host.Parent = carve
		return host
	end
	local function arcNote(parent: Instance, name: string, y: number): TextLabel
		local label = UIChrome.BodyText(name, theme.TextSizes.Small, theme.Colors.TextSecondary)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextWrapped = true
		label.Position = UDim2.fromOffset(0, y)
		label.Size = UDim2.new(1, 0, 0, 32)
		label.Parent = parent
		return label
	end

	local shapeGroup = arcGroup("ShapeGroup")
	w.shapeGroup = shapeGroup
	local toolRow = chipRow(theme, shapeGroup, "Tools", 0)
	for index, tool in TOOLS do
		self:_ArcadeChip("tool_" .. tool.id, toolRow, tool.label, index, 96, function()
			self:_SelectTool(tool.id)
		end)
	end
	w.toolNote = arcNote(shapeGroup, "ToolNote", 34)

	local grooveRow = chipRow(theme, shapeGroup, "GrooveRow", 68)
	grooveRow.Visible = false
	for index, profile in GROOVE_PROFILES do
		self:_ArcadeChip("groove_" .. profile.id, grooveRow, profile.label, index, 44, function()
			self._m.grooveProfile = profile.id
			self:_Paint()
		end)
	end
	w.grooveRow = grooveRow

	local ridgeRow = chipRow(theme, shapeGroup, "RidgeRow", 68)
	ridgeRow.Visible = false
	for index, n in RIDGE_SYMMETRY do
		self:_ArcadeChip("ridge_" .. tostring(n), ridgeRow, tostring(n), index, 44, function()
			self._m.ridgeSymmetry = n
			self:_Paint()
		end)
	end
	w.ridgeRow = ridgeRow

	local accGroup = arcGroup("AccGroup")
	w.accGroup = accGroup
	local accRow = chipRow(theme, accGroup, "AccRow", 0)
	self:_ArcadeChip("accPlace", accRow, "Place a piece", 0, 144, function()
		self:_PlaceAccessory()
	end)
	self:_ArcadeChip("accClear", accRow, "Clear", 1, 92, function()
		self:_ClearAccessories()
	end)
	local addonCount = UIChrome.BodyText("AddonCount", theme.TextSizes.Small, theme.Colors.TextPrimary)
	addonCount.TextXAlignment = Enum.TextXAlignment.Left
	addonCount.Position = UDim2.fromOffset(0, 36)
	addonCount.Size = UDim2.new(1, 0, 0, 18)
	addonCount.Parent = accGroup
	w.addonCount = addonCount
	arcNote(accGroup, "AccNote", 58).Text =
		"Click the pot to place a piece, then drag its arrows to move it and its rings to spin it."

	local glazeGroup = arcGroup("GlazeGroup")
	w.glazeGroup = glazeGroup
	local glazeRow = chipRow(theme, glazeGroup, "GlazeTools", 0)
	for index, tool in GLAZE_TOOLS do
		self:_ArcadeChip("glaze_" .. tool.id, glazeRow, tool.label, index, 92, function()
			self._m.glazeTool = tool.id
			self:_Paint()
		end)
	end
	local dirRow = chipRow(theme, glazeGroup, "GlazeDirs", 34)
	for index, dir in GLAZE_DIRS do
		self:_ArcadeChip("dir_" .. dir.id, dirRow, dir.label, index, 78, function()
			self._m.glazeDir = dir.id
			self:_Paint()
		end)
	end
	self:_ArcadeChip("brushDown", dirRow, "\u{2212}", 3, 40, function()
		self:_NudgeBrush(-WHEEL.BrushStep)
	end)
	self:_ArcadeChip("brushUp", dirRow, "+", 4, 40, function()
		self:_NudgeBrush(WHEEL.BrushStep)
	end)
	w.glazeNote = arcNote(glazeGroup, "GlazeNote", 68)
	local glazeInfo = UIChrome.BodyText("GlazeInfo", theme.TextSizes.Small, theme.Colors.TextPrimary)
	glazeInfo.TextXAlignment = Enum.TextXAlignment.Left
	glazeInfo.Position = UDim2.fromOffset(0, 100)
	glazeInfo.Size = UDim2.new(1, 0, 0, 18)
	glazeInfo.Parent = glazeGroup
	w.glazeInfo = glazeInfo
	local resetPaintRow = chipRow(theme, glazeGroup, "ResetPaintRow", 122)
	self:_ArcadeChip("resetGlaze", resetPaintRow, "Reset paint", 0, 130, function()
		self:_ResetGlaze()
	end)

	local fireGroup = arcGroup("FireGroup")
	w.fireGroup = fireGroup
	local fireRow = chipRow(theme, fireGroup, "FireRow", 0)
	local fireChip = self:_ArcadeChip("fire", fireRow, "Fire the kiln", 0, 168, function()
		self:_StartFiring()
	end)
	w.fireChipLabel = fireChip.label
	self:_ArcadeChip("toDisplay", fireRow, "Display", 1, 110, function()
		self:_SelectPhase(PHASE_INDEX.Display)
	end)
	local fireInfo = UIChrome.BodyText("FireInfo", theme.TextSizes.Small, theme.Colors.TextPrimary)
	fireInfo.TextXAlignment = Enum.TextXAlignment.Left
	fireInfo.Position = UDim2.fromOffset(0, 36)
	fireInfo.Size = UDim2.new(1, 0, 0, 18)
	fireInfo.Parent = fireGroup
	w.fireInfo = fireInfo
	arcNote(fireGroup, "FireNote", 58).Text =
		"A fired pot needs somewhere to live, so the kiln refuses when storage is full."

	local displayGroup = arcGroup("DisplayGroup")
	w.displayGroup = displayGroup
	local fateRow = chipRow(theme, displayGroup, "FateRow", 0)
	local fateChip = self:_ArcadeChip("fate", fateRow, "Sell", 0, 150, function()
		self:_FinishPot()
	end)
	w.fateChipLabel = fateChip.label
	local spinDisplay = self:_ArcadeChip("displaySpin", fateRow, "Spin: on", 1, 112, function()
		self._m.displaySpin = not self._m.displaySpin
		self:_Paint()
	end)
	w.displaySpinLabel = spinDisplay.label

	local storeRow = chipRow(theme, displayGroup, "StoreRow", 34)
	local storeChip = self:_ArcadeChip("store", storeRow, "Make another", 0, 152, function()
		self:_StorePot("pillar")
	end)
	w.storeChipLabel = storeChip.label
	local shelfChip = self:_ArcadeChip("shelf", storeRow, "Shelf", 1, 108, function()
		self:_StorePot("shelf")
	end)
	w.shelfChipLabel = shelfChip.label

	local clearRow = chipRow(theme, displayGroup, "ClearRow", 68)
	self:_ArcadeChip("sellStored", clearRow, "Sell a stored pot", 0, 176, function()
		self:_SellStoredPot()
	end)

	local storageInfo = UIChrome.BodyText("StorageInfo", theme.TextSizes.Small, theme.Colors.TextPrimary)
	storageInfo.TextXAlignment = Enum.TextXAlignment.Left
	storageInfo.Position = UDim2.fromOffset(0, 104)
	storageInfo.Size = UDim2.new(1, 0, 0, 18)
	storageInfo.Parent = displayGroup
	w.storageInfo = storageInfo
	local displayNote = arcNote(displayGroup, "DisplayNote", 124)
	displayNote.Size = UDim2.new(1, 0, 0, 30)
	displayNote.Text =
		"Storing a pot clears the wheel and rolls the next blueprint; a commission keeps its own target."

	local bottomRow = surface("PhaseBottom", theme.Colors.Background, 1)
	bottomRow.AnchorPoint = Vector2.new(0, 1)
	bottomRow.Position = UDim2.new(0, 14, 1, -12)
	bottomRow.Size = UDim2.new(1, -28, 0, 30)
	bottomRow.Parent = carve
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
	}).Parent = bottomRow
	local spinChip = self:_ArcadeChip("spin", bottomRow, "Wheel spinning", 0, 158, function()
		local m = self._m
		m.spinning = not m.spinning
		m.spinRestore = m.spinning
		self:_Paint()
	end)
	w.spinChipLabel = spinChip.label
	self:_ArcadeChip("phaseBack", bottomRow, "\u{25C0} Back", 1, 62, function()
		self:_SelectPhase(self._m.phaseIndex - 1)
	end)
	self:_ArcadeChip("phaseNext", bottomRow, "Next \u{25B6}", 2, 62, function()
		self:_SelectPhase(self._m.phaseIndex + 1)
	end)

	-- Bottom: meter + notice + hints.
	local meter = self:_ArcadePanel("Meter", Vector2.new(680, 92))
	meter.AnchorPoint = Vector2.new(0.5, 1)
	meter.Position = UDim2.new(0.5, 0, 1, -104)

	local caption = UIChrome.BodyText("Caption", theme.TextSizes.Small, theme.Colors.TextSecondary)
	caption.Text = "Match to blueprint"
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.Position = UDim2.fromOffset(14, 6)
	caption.Size = UDim2.fromOffset(220, 18)
	caption.Parent = meter

	local value = UIChrome.Text("Value", theme.TextSizes.Title, theme.Colors.Accent)
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.new(1, -14, 0, 6)
	value.Size = UDim2.fromOffset(120, 34)
	value.Parent = meter
	w.meterValue = value

	local gradeLabel = UIChrome.BodyText("Grade", theme.TextSizes.Body, theme.Colors.TextPrimary)
	gradeLabel.TextXAlignment = Enum.TextXAlignment.Left
	gradeLabel.Position = UDim2.fromOffset(238, 6)
	gradeLabel.Size = UDim2.fromOffset(240, 18)
	gradeLabel.Parent = meter
	w.gradeLabel = gradeLabel

	local starRow = surface("Stars", theme.Colors.Background, 1)
	starRow.AnchorPoint = Vector2.new(1, 0)
	starRow.Position = UDim2.new(1, -138, 0, 8)
	starRow.Size = UDim2.fromOffset(140, 26)
	starRow.Parent = meter
	UIStyler.ListLayout({
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 4),
	}).Parent = starRow
	for index = 1, #STAR_AT do
		local star = iconArt(starRow, "star", 22, theme.Colors.Accent)
		star.AnchorPoint = Vector2.new(0, 0)
		star.Position = UDim2.fromOffset(0, 0)
		star.LayoutOrder = index
		table.insert(self._stars, star)
	end

	local track = surface("MeterTrack", theme.Arcade.RulerTrack, 0)
	track.AnchorPoint = Vector2.new(0.5, 1)
	track.Position = UDim2.new(0.5, 0, 1, -14)
	track.Size = UDim2.new(1, -28, 0, 18)
	track.ClipsDescendants = true
	track.Parent = meter
	UIChrome.Stroke(theme, "Arcade", "Panel").Parent = track

	local fill = surface("MeterFill", theme.Colors.Primary, 0)
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = 2
	fill.Parent = track
	w.meterFill = fill

	local best = surface("BestMark", theme.Colors.Accent, 0)
	best.AnchorPoint = Vector2.new(0.5, 0)
	best.Size = UDim2.new(0, 4, 1, 0)
	best.ZIndex = 4
	best.Visible = false
	best.Parent = track
	w.meterBest = best

	local notice = self:_ArcadePanel("Notice", Vector2.new(680, 40))
	notice.AnchorPoint = Vector2.new(0.5, 1)
	notice.Position = UDim2.new(0.5, 0, 1, -202)
	notice.Visible = false
	w.noticeChip = notice

	local noticeLabel = UIChrome.BodyText("NoticeLabel", theme.TextSizes.Body, theme.Colors.TextPrimary)
	noticeLabel.TextXAlignment = Enum.TextXAlignment.Left
	noticeLabel.Position = UDim2.fromOffset(14, 0)
	noticeLabel.Size = UDim2.new(1, -28, 1, 0)
	noticeLabel.Parent = notice
	w.noticeLabel = noticeLabel

	local hints = self:_ArcadePanel("Hints", Vector2.new(1000, 40))
	hints.AnchorPoint = Vector2.new(0.5, 1)
	hints.Position = UDim2.new(0.5, 0, 1, -52)

	local hintLabel = UIChrome.BodyText("Hints", theme.TextSizes.Small, theme.Colors.TextSecondary)
	hintLabel.TextTruncate = Enum.TextTruncate.AtEnd
	hintLabel.Position = UDim2.fromOffset(14, 0)
	hintLabel.Size = UDim2.new(1, -28, 1, 0)
	hintLabel.Parent = hints
	w.hintLabel = hintLabel

	self:_PaintGhost()
end

-- One arcade readout row, exposing the SAME SetValue contract as the kit's
-- StatRow so _Paint never branches on layout.
function PotteryWheelScreen:_ArcadeRow(parent: Instance, spec: { id: string, label: string, unit: string, max: number, precision: number, invert: boolean? }, order: number): { SetValue: (number) -> () }
	local theme = self:GetTheme()
	local row = surface("Row_" .. spec.id, theme.Arcade.Row, 0.35)
	row.Size = UDim2.new(1, 0, 0, 30)
	row.LayoutOrder = order
	row.Parent = parent

	local label = UIChrome.BodyText("Label", theme.TextSizes.Small, theme.Colors.TextSecondary)
	label.Text = spec.label
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Position = UDim2.fromOffset(8, 0)
	label.Size = UDim2.new(1, -140, 0, 20)
	label.Parent = row

	local value = UIChrome.BodyText("Value", theme.TextSizes.Small, theme.Colors.TextPrimary)
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.new(1, -8, 0, 0)
	value.Size = UDim2.fromOffset(128, 20)
	value.Parent = row

	local track = surface("Track", theme.Arcade.RulerTrack, 0)
	track.AnchorPoint = Vector2.new(0, 1)
	track.Position = UDim2.new(0, 8, 1, -4)
	track.Size = UDim2.new(1, -16, 0, 4)
	track.Parent = row

	local fill = surface("Fill", if spec.invert then theme.Colors.Warning else theme.Colors.Accent, 0)
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = track

	local format = "%." .. tostring(math.max(0, spec.precision)) .. "f"
	local function setValue(v: number)
		local text = string.format(format, v)
		if spec.unit ~= "" then
			text = text .. " " .. spec.unit
		end
		if value.Text ~= text then
			value.Text = text
		end
		fill.Size = UDim2.fromScale(if spec.max > 0 then math.clamp(v / spec.max, 0, 1) else 0, 1)
	end
	setValue(0)
	return { SetValue = setValue }
end

return PotteryWheelScreen
