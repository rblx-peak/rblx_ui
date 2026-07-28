--!strict
-- GPChairPreview — the REAL preview mechanism, ported.
--
-- The shipped lobby previews a chair by cloning the seat mesh into a
-- ViewportFrame, applying the skin, adding the chair's decoration recipe and
-- spinning the whole thing as one rigid piece. The collection has no mesh
-- library, so the model is BUILT here from the chair's `look` (colour,
-- material, reflectance, effect) plus a per-tier silhouette: high tiers get
-- arms, a finial and a plinth, exactly as the source's high tiers are whole
-- models rather than reskins. Everything else about the mechanism survives:
--
--   * a transparent ViewportFrame layered OVER a swirling sunburst (a
--     viewport renders its 3D under its own GUI children, so the burst has to
--     live BENEATH the see-through viewport, not inside it);
--   * a camera framed off the model's extents;
--   * ONE shared spin driver for every live preview, gated on "is this
--     element actually overlapping the screen" AND on an owner GuiObject's
--     visibility — the source's two-tier gate, which is what stops 50+
--     viewports animating all lobby long;
--   * staggered fills (a few models per frame, never a single-frame burst)
--     and WINDOW fills (only cards inside the scroll viewport hold a Model;
--     scrolled-away cards drop theirs, and closing the panel drops all).
--
-- THE ONE Heartbeat: the spin driver is a UITicker handler, registered when
-- the first preview is created and released with the last. No RunService
-- connection is opened here.
--
-- PACK LAWS: no pure black and no pure white reach a pixel. The viewport's
-- ambient/light are warm cream, leg and shadow parts are hue-DEEPENED through
-- GPLayoutKit.Deepen (the same function the UI shadows use), and the glyph
-- fallback IconArchive hands back — which is born white-on-black — is
-- repainted to pack ink before it is ever parented into a page.

local Workspace = game:GetService("Workspace")

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local IconArchive = require(script.Parent.Parent.Icons.IconArchive)
local IconVisibility = require(script.Parent.Parent.Icons.IconVisibility)
local GPLayoutKit = require(script.Parent.GPLayoutKit)
local UITicker = require(script.Parent.UITicker)

local GPChairPreview = {}

export type View = {
	holder: Frame,
	viewport: ViewportFrame,
	camera: Camera,
	burst: ImageLabel?,
	fallback: GuiObject?,
	model: Model?,
	chairId: string?,
	gate: GuiObject?,
	spinSpeed: number,
	burstSpeed: number,
	alive: boolean,
}

export type FillSlot = {
	view: View,
	chair: any,
	rank: number,
	element: GuiObject,
	filled: boolean,
}

local BASE_SPIN = 0.9 -- radians/sec, the source's rate
local BURST_SPIN = 40 -- degrees/sec
local CAMERA_PULL = 1.35
local FILL_BATCH = 3 -- models per frame while staggering

-- ========================================================================
-- Screen gate
-- ========================================================================

-- True only when the element could actually be drawn: laid out (non-zero
-- size) AND its rect overlaps the camera viewport. Ancestor visibility is the
-- caller's job — that is what `gate` is for.
function GPChairPreview.OnScreen(element: GuiObject): boolean
	if element.AbsoluteSize.X <= 0 then
		return false
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return false
	end
	local viewport = camera.ViewportSize
	local position, size = element.AbsolutePosition, element.AbsoluteSize
	return position.X < viewport.X
		and position.Y < viewport.Y
		and position.X + size.X > 0
		and position.Y + size.Y > 0
end

-- ========================================================================
-- The shared spin driver
-- ========================================================================

local live: { View } = {}
local stopTicker: (() -> ())? = nil

local function step(_dt: number, now: number)
	if #live == 0 then
		return
	end
	-- Views sharing the house rate share ONE CFrame: it is built once per
	-- frame here rather than once per model, which is the whole reason this
	-- driver is centralised.
	local houseSpin = CFrame.Angles(0, now * BASE_SPIN, 0)
	local houseBurst = (now * BURST_SPIN) % 360
	for index = #live, 1, -1 do
		local view = live[index]
		if not view.alive or not view.viewport.Parent then
			table.remove(live, index)
		else
			local gate = view.gate
			local open = if gate then gate.Visible else true
			if open and GPChairPreview.OnScreen(view.viewport) then
				local model = view.model
				if model and model.Parent then
					local spin = if view.spinSpeed == BASE_SPIN
						then houseSpin
						else CFrame.Angles(0, now * view.spinSpeed, 0)
					model:PivotTo(spin)
				end
				local burst = view.burst
				if burst then
					burst.Rotation = if view.burstSpeed == BURST_SPIN
						then houseBurst
						else (now * view.burstSpeed) % 360
				end
			end
		end
	end
end

local function ensureTicker()
	if stopTicker then
		return
	end
	stopTicker = UITicker.Register(step)
end

local function releaseTickerIfIdle()
	if #live == 0 and stopTicker then
		stopTicker()
		stopTicker = nil
	end
end

-- ========================================================================
-- Icon helper — the pack-safe wrapper around the archive
-- ========================================================================

-- IconArchive's GLYPH fallback is born pure white with a pure black stroke,
-- which violates pack law 1 on sight. Every GP surface that wants an archive
-- icon goes through here so the fallback is repainted before it lands.
function GPChairPreview.Icon(
	theme: Types.UITheme,
	parent: Instance?,
	key: string,
	sizePx: number,
	query: any?
): GuiObject
	local icon = IconArchive.Image(parent, key, sizePx, query)
	if icon:IsA("TextLabel") then
		local label = icon :: TextLabel
		label.TextColor3 = theme.Colors.TextPrimary
		label.TextStrokeTransparency = 1
		label.FontFace = theme.Fonts.Title
	end
	IconVisibility.Register(icon)
	return icon
end

-- ========================================================================
-- Model building
-- ========================================================================

local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, reflectance: number): Part
	local piece = Instance.new("Part")
	piece.Name = name
	piece.Anchored = true
	piece.CanCollide = false
	piece.CastShadow = false
	piece.Size = size
	piece.CFrame = cframe
	piece.Color = color
	piece.Material = material
	piece.Reflectance = reflectance
	return piece
end

-- The effect a chair's look names, expressed as a NEON accent colour (a
-- ViewportFrame draws no particles, so the source skips them too — the
-- silhouette has to carry the effect instead).
local function effectColor(theme: Types.UITheme, effect: string?, base: Color3): Color3
	if effect == "fire" then
		return theme.Arcade.Orange
	elseif effect == "sparkle" then
		return theme.Arcade.Gold
	elseif effect == "rainbow" then
		return theme.Arcade.Magenta
	elseif effect == "galaxy" then
		return theme.Arcade.ShopAccents[4]
	end
	return base
end

-- A chair, built from its look and its tier. Rank drives the SILHOUETTE, not
-- just the tint: arms from Epic, a finial from Legendary, a plinth from
-- Mythic, so the ladder reads at a glance in a 110px well.
function GPChairPreview.BuildModel(theme: Types.UITheme, chair: any, rank: number): Model
	local look = chair.look or {}
	local color: Color3 = look.color or theme.Colors.Primary
	local material: Enum.Material = look.material or Enum.Material.SmoothPlastic
	local reflectance: number = look.reflectance or 0
	local deep = GPLayoutKit.Deepen(theme, color, 1)
	local accent = effectColor(theme, look.effect, color)

	local model = Instance.new("Model")
	model.Name = "ChairPreview_" .. tostring(chair.id)

	part("Seat", Vector3.new(2.4, 0.36, 2.2), CFrame.new(0, 1.2, 0), color, material, reflectance).Parent = model
	part("Back", Vector3.new(2.4, 1.9, 0.32), CFrame.new(0, 2.25, -0.94), color, material, reflectance).Parent = model

	for _, offset in { Vector3.new(-0.95, 0.6, -0.85), Vector3.new(0.95, 0.6, -0.85), Vector3.new(-0.95, 0.6, 0.85), Vector3.new(0.95, 0.6, 0.85) } do
		part("Leg", Vector3.new(0.3, 1.2, 0.3), CFrame.new(offset), deep, material, reflectance).Parent = model
	end

	if rank >= 4 then -- Epic and up: armrests
		part("ArmL", Vector3.new(0.3, 0.28, 2.0), CFrame.new(-1.05, 1.75, 0), deep, material, reflectance).Parent = model
		part("ArmR", Vector3.new(0.3, 0.28, 2.0), CFrame.new(1.05, 1.75, 0), deep, material, reflectance).Parent = model
	end
	if rank >= 5 then -- Legendary and up: a lit finial on the backrest
		local finial = part("Finial", Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, 3.35, -0.94), accent, Enum.Material.Neon, 0)
		finial.Shape = Enum.PartType.Ball
		finial.Parent = model
	end
	if rank >= 6 then -- Mythic and up: a plinth, so the seat reads as a throne
		part("Plinth", Vector3.new(3.1, 0.28, 2.9), CFrame.new(0, 0.14, 0), accent, Enum.Material.Neon, 0.1).Parent = model
	end

	-- Centre the built piece on the origin so the shared spin CFrame applies
	-- to every model identically.
	model:PivotTo(CFrame.new())
	return model
end

-- ========================================================================
-- Views
-- ========================================================================

function GPChairPreview.New(theme: Types.UITheme, parent: Instance, opts: {
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	cornerIndex: number?,
	accent: Color3?,
	gate: GuiObject?,
	burst: boolean?,
	sink: { any }?,
	zIndex: number?,
	spinSpeed: number?,
	plain: boolean?,
}): View
	local accent = opts.accent or theme.Colors.Primary
	local zIndex = opts.zIndex or 4

	-- The holder is the WELL the chair sits in: a blush plate, petal-cornered
	-- against its card, clipping so a big model never spills onto the name.
	-- `plain` drops the paint for the common case where the caller already has
	-- a well (a card's art slot) and wants only the clip and the layers.
	local holder = UIStyler.Frame("ChairWell")
	holder.BackgroundColor3 = theme.Colors.Surface
	holder.BackgroundTransparency = if opts.plain then 1 else 0
	holder.Size = opts.size or UDim2.fromScale(1, 1)
	holder.Position = opts.position or UDim2.fromScale(0, 0)
	holder.AnchorPoint = opts.anchorPoint or Vector2.new(0, 0)
	holder.ClipsDescendants = true
	holder.ZIndex = zIndex
	holder.Parent = parent
	if not opts.plain then
		GPLayoutKit.Petal(theme, holder, (opts.cornerIndex or 0) + 1)
		GPLayoutKit.SoftStroke(theme, holder, theme.Colors.Surface)
	end

	local burst: ImageLabel? = nil
	if opts.burst ~= false then
		-- The soft sunburst behind the chair, tinted by rarity. Decoration, not
		-- iconography — deliberately NOT registered with IconVisibility, the
		-- same call the layout kit makes for its own pattern tiles.
		local art = Instance.new("ImageLabel")
		art.Name = "Sunburst"
		art.BackgroundTransparency = 1
		local def = (theme :: any).Assets and (theme :: any).Assets.sunburstSoft
		if def then
			art.Image = def.image
		end
		art.ScaleType = Enum.ScaleType.Fit
		art.ImageColor3 = accent
		art.ImageTransparency = 0.72
		art.AnchorPoint = Vector2.new(0.5, 0.5)
		art.Position = UDim2.fromScale(0.5, 0.5)
		art.Size = UDim2.fromScale(1.55, 1.55)
		art.ZIndex = zIndex + 1
		art.Parent = holder
		burst = art
	end

	-- Flat archive art, shown until (and whenever) no 3D model is resident.
	-- A well is never blank: image -> glyph -> the well's own tint.
	local fallback: GuiObject? = nil

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "ChairViewport"
	viewport.BackgroundTransparency = 1
	viewport.BorderSizePixel = 0
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.ZIndex = zIndex + 3
	-- Warm cream light, never white: the pack's law reaches into the 3D too.
	viewport.Ambient = theme.Colors.Surface
	viewport.LightColor = theme.Colors.Background
	viewport.LightDirection = Vector3.new(-0.4, -1, -0.35)
	viewport.Parent = holder

	local camera = Instance.new("Camera")
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local view: View = {
		holder = holder,
		viewport = viewport,
		camera = camera,
		burst = burst,
		fallback = fallback,
		model = nil,
		chairId = nil,
		gate = opts.gate,
		spinSpeed = opts.spinSpeed or BASE_SPIN,
		burstSpeed = BURST_SPIN,
		alive = true,
	}
	table.insert(live, view)
	ensureTicker()
	return view
end

function GPChairPreview.SetAccent(view: View, accent: Color3)
	if view.burst then
		view.burst.ImageColor3 = accent
	end
end

-- Show `chair` in a view; nil clears it. Safe to call repeatedly — a view
-- already showing this exact chair returns immediately, because rebuilding it
-- costs a dozen part constructions for an identical result (the source pays
-- the same guard for its mesh clones).
function GPChairPreview.SetChair(theme: Types.UITheme, view: View, chair: any?, rank: number?)
	if not view.alive then
		return
	end
	local id = if chair then tostring(chair.id) else nil
	if id and view.chairId == id and view.model and view.model.Parent then
		return
	end
	view.chairId = id
	if view.model then
		view.model:Destroy()
		view.model = nil
	end
	if not chair then
		if view.fallback then
			view.fallback.Visible = true
		end
		return
	end

	local ok, model = pcall(GPChairPreview.BuildModel, theme, chair, rank or 1)
	if not ok or typeof(model) ~= "Instance" then
		-- The 3D failed: fall back to flat archive art rather than a hole.
		if not view.fallback then
			local icon = GPChairPreview.Icon(theme, view.holder, chair.iconKey or "box", 64)
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.fromScale(0.5, 0.5)
			icon.Size = UDim2.fromScale(0.6, 0.6)
			icon.ZIndex = view.viewport.ZIndex - 1
			view.fallback = icon
		end
		if view.fallback then
			view.fallback.Visible = true
		end
		return
	end

	local built = model :: Model
	built.Parent = view.viewport
	view.model = built
	if view.fallback then
		view.fallback.Visible = false
	end

	local extents = built:GetExtentsSize()
	local distance = math.max(extents.X, extents.Y, extents.Z) * CAMERA_PULL
	view.camera.CFrame = CFrame.lookAt(
		Vector3.new(0, extents.Y * 0.1, -distance),
		Vector3.new(0, 0, 0)
	)
end

function GPChairPreview.Clear(view: View)
	view.chairId = nil
	if view.model then
		view.model:Destroy()
		view.model = nil
	end
	if view.fallback then
		view.fallback.Visible = true
	end
end

function GPChairPreview.Destroy(view: View)
	view.alive = false
	GPChairPreview.Clear(view)
	if view.holder.Parent then
		view.holder:Destroy()
	end
	for index = #live, 1, -1 do
		if live[index] == view then
			table.remove(live, index)
		end
	end
	releaseTickerIfIdle()
end

-- Release every view a screen owns (teardown contract).
function GPChairPreview.ReleaseAll(views: { View }?)
	if not views then
		return
	end
	for _, view in views do
		GPChairPreview.Destroy(view)
	end
	table.clear(views)
end

-- ========================================================================
-- Filling without hitching
-- ========================================================================

-- Populate many views a few per frame: cards appear instantly, models stream
-- in behind them. Orphaned views (their card was destroyed by a re-render)
-- are skipped harmlessly.
function GPChairPreview.FillStaggered(theme: Types.UITheme, fills: { { view: View, chair: any, rank: number? } })
	task.spawn(function()
		for index, entry in fills do
			if entry.view.alive and entry.view.viewport.Parent then
				GPChairPreview.SetChair(theme, entry.view, entry.chair, entry.rank)
			end
			if index % FILL_BATCH == 0 then
				task.wait()
			end
		end
	end)
end

local function inWindow(element: GuiObject, scroll: ScrollingFrame, margin: number): boolean
	local elementPosition, elementSize = element.AbsolutePosition, element.AbsoluteSize
	local scrollPosition, scrollSize = scroll.AbsolutePosition, scroll.AbsoluteWindowSize
	return elementPosition.Y + elementSize.Y > scrollPosition.Y - margin
		and elementPosition.Y < scrollPosition.Y + scrollSize.Y + margin
		and elementPosition.X + elementSize.X > scrollPosition.X - margin
		and elementPosition.X < scrollPosition.X + scrollSize.X + margin
end

-- Only cards inside the scroll window (plus a row of slack) hold a Model, and
-- a shut panel holds none. Returns the refresh fn — call it once after a
-- re-render, deferred so the layout pass has run.
--
-- `generation` cancels a stale in-flight pass: a re-render is triggered from
-- several places at once (tab change, ownership change, window roll), so
-- overlapping passes are routine.
function GPChairPreview.AttachWindowFill(
	theme: Types.UITheme,
	scroll: ScrollingFrame,
	gate: GuiObject,
	slots: { FillSlot },
	margin: number
): (() -> (), { RBXScriptConnection })
	local generation = 0
	local function refresh()
		generation += 1
		local mine = generation
		task.spawn(function()
			local open = gate.Visible
			local done = 0
			for _, slot in slots do
				if generation ~= mine then
					return -- a newer pass owns these slots now
				end
				local want: boolean = open == true and inWindow(slot.element, scroll, margin)
				if want ~= slot.filled and slot.view.alive and slot.view.viewport.Parent then
					slot.filled = want
					GPChairPreview.SetChair(theme, slot.view, if want then slot.chair else nil, slot.rank)
					done += 1
					if done % FILL_BATCH == 0 then
						task.wait()
					end
				end
			end
		end)
	end

	local connections = {
		scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(refresh),
		gate:GetPropertyChangedSignal("Visible"):Connect(refresh),
	}
	return refresh, connections
end

return GPChairPreview
