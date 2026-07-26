--!strict
-- CurrencyFlight — E3 "fly-to-counter": coins burst from a purchase point and
-- home into the currency counter pill, ticking the number as each one lands.
-- Works for any pack (theme comes in per call); the Gurren Lagann numbers
-- live in GurrenLagannTheme.DialectTokens.flight.
--
-- THE 0.4 BOUNDARY — this module is ENTIRELY on the Luau + UITicker side:
-- flight choreography (stagger, bezier motion, landing order, coalescing) is
-- sequenced, continuous behavior, so it is driven here and only here. Styling
-- owns nothing of this: no style tags are flipped (particles are transient
-- effect art, deliberately untagged so pack rules can never restyle them
-- mid-flight), and their static look — tint, stroke, circle geometry — comes
-- from theme tokens through UIChrome policy calls at acquire time. No
-- behavior in this file exists on the styling side too.
--
-- NO SKEW EXISTS IN ROBLOX — noted per the pack law: particles are geometric
-- circles (Pill corner via UIChrome policy, round in every pack including
-- HardCorners ones), so no rotation/slant trick is needed at all; the comic
-- energy is pure position choreography (fanned bezier arcs, Quad-In homing).
--
-- ONE SHARED TICKER: a single UITicker registration drives every in-flight
-- particle across all concurrent Fly calls, exists only while the module-level
-- flight list is non-empty, and is bound to the Toast layer root for
-- auto-cleanup. Never a per-flight or per-particle connection.
--
-- POOLING & BUDGET: particle frames come from a module pool and release with
-- Visible = false, never Destroy — 100x Fly = zero instance or connection
-- growth. No UIShadow/UIGlow is ever attached to a particle, so this module
-- spends nothing from the Capabilities shadow budget.
--
-- REDUCE-MOTION (ReduceMotion attribute on the Toast layer root, or wired via
-- SetReduceMotion from settings): no particles — one instant onLand covering
-- the whole amount, then onDone. SKIPPABLE: nothing here ever blocks input
-- (particles are inert overlay frames); ceremony coordinators call SkipAll()
-- on any user input to jump every flight to its final confirmed state.
--
-- COALESCING: count > 200, or a Fly already in-flight to the same target,
-- merges into ONE flight and one big final onLand covering the whole amount —
-- never particle spam. Total concurrent particles cap at 40; requests that
-- find no slots coalesce into a timed particle-less landing.

local TweenService = game:GetService("TweenService")

local Layers = require(script.Parent.Layers)
local UITicker = require(script.Parent.UITicker)
local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)

local CurrencyFlight = {}

export type LandCallback = (landedIndex: number, total: number) -> ()

export type FlyOptions = {
	theme: Types.UITheme,
	fromAbsolutePosition: Vector2,
	toGuiObject: GuiObject,
	count: number,
	currencyId: string?,
	onLand: LandCallback?,
	onDone: (() -> ())?,
}

-- Behavior constants (choreography shape, not visual identity — visual values
-- come from the theme; packs override the tunable feel numbers via
-- DialectTokens.flight, see FLIGHT_DEFAULTS below).
local PARTICLES_MIN = 8 -- count maps into 8..14 particles...
local PARTICLES_MAX = 14
local COUNT_PER_EXTRA_PARTICLE = 25 -- ...one extra per 25 count above 8
local COALESCE_COUNT = 200 -- above this, one 8-particle flight + one big onLand
local COALESCED_PARTICLES = 8
local MAX_LIVE_PARTICLES = 40 -- global cap across ALL concurrent flights
local PARTICLE_ZINDEX = 100 -- ride above toast cards inside the Toast layer

type FlightTokens = {
	particleSize: number,
	duration: number,
	durationJitter: number,
	stagger: number,
	spread: number,
	pulseMinInterval: number,
}

-- House defaults for packs without a DialectTokens.flight namespace. The GL
-- pack overrides these (faster, wider comic arcs) in its theme file.
local FLIGHT_DEFAULTS: FlightTokens = {
	particleSize = 14, -- px diameter of a coin pip
	duration = 0.55, -- seconds origin -> counter
	durationJitter = 0.12,
	stagger = 0.035, -- seconds between launches
	spread = 120, -- px bezier control-point fan
	pulseMinInterval = 0.09, -- throttle for the counter pop during a burst
}

type PoolEntry = {
	frame: Frame,
	stroke: UIStroke?,
	themeId: string?,
}

type Particle = {
	entry: PoolEntry,
	delay: number,
	duration: number,
	control: Vector2, -- absolute-space bezier control point, fixed at spawn
	launched: boolean,
	landed: boolean,
}

type Rider = {
	onLand: LandCallback?,
	onDone: (() -> ())?,
}

type Flight = {
	target: GuiObject,
	theme: Types.UITheme,
	origin: Vector2,
	elapsed: number,
	particles: { Particle },
	landedCount: number,
	-- single = one big final onLand(1, 1) instead of per-particle events
	-- (coalesced big amounts, slot-starved requests, merged riders).
	single: boolean,
	holdFor: number, -- particle-less flights land after this long
	pulseMinInterval: number,
	lastPulseAt: number,
	onLand: LandCallback?,
	onDone: (() -> ())?,
	riders: { Rider },
}

local flights: { [GuiObject]: Flight } = {}
local flightCount = 0
local pool: { PoolEntry } = {}
local liveParticles = 0
local toastRoot: Frame? = nil
local stopTicker: (() -> ())? = nil
local reduceMotionOverride = false
local rng = Random.new()

-- ---- tokens -------------------------------------------------------------

local function flightTokens(theme: Types.UITheme): FlightTokens
	local dialects = theme.DialectTokens
	local group: { [string]: any } = (dialects and dialects.flight) or {}
	return {
		particleSize = tonumber(group.particleSize) or FLIGHT_DEFAULTS.particleSize,
		duration = tonumber(group.duration) or FLIGHT_DEFAULTS.duration,
		durationJitter = tonumber(group.durationJitter) or FLIGHT_DEFAULTS.durationJitter,
		stagger = tonumber(group.stagger) or FLIGHT_DEFAULTS.stagger,
		spread = tonumber(group.spread) or FLIGHT_DEFAULTS.spread,
		pulseMinInterval = tonumber(group.pulseMinInterval) or FLIGHT_DEFAULTS.pulseMinInterval,
	}
end

-- ---- pool ---------------------------------------------------------------

local function acquireParticle(root: Frame, theme: Types.UITheme, currencyId: string, tokens: FlightTokens): PoolEntry
	local entry: PoolEntry? = nil
	while #pool > 0 do
		local candidate = table.remove(pool) :: PoolEntry
		if candidate.frame.Parent ~= nil then
			entry = candidate
			break
		end
		-- The Toast root was rebuilt at some point and this frame died with
		-- it — drop the husk and keep looking.
	end
	if not entry then
		local frame = UIStyler.Frame("FlightPip")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.BackgroundTransparency = 0
		frame.ZIndex = PARTICLE_ZINDEX
		frame.Visible = false
		-- Pill intent stays a geometric circle in EVERY pack — HardCorners
		-- styles flatten everything except pills (UIChrome corner policy).
		UIChrome.Corner("Arcade", "Pill").Parent = frame
		entry = { frame = frame, stroke = nil, themeId = nil }
	end
	local live = entry :: PoolEntry
	live.frame.Parent = root
	-- Re-chrome only when the pack changed since this pip last flew: the
	-- stroke is pack policy (GL: 3px comic ink), not a per-flight value.
	if live.themeId ~= theme.Id then
		if live.stroke then
			live.stroke:Destroy()
		end
		local stroke = UIChrome.Stroke(theme, "Arcade", "Button")
		stroke.Parent = live.frame
		live.stroke = stroke
		live.themeId = theme.Id
	end
	live.frame.Size = UDim2.fromOffset(tokens.particleSize, tokens.particleSize)
	live.frame.BackgroundColor3 = UIChrome.CurrencyColor(theme, currencyId)
	liveParticles += 1
	return live
end

local function releaseParticle(entry: PoolEntry)
	entry.frame.Visible = false
	liveParticles -= 1
	table.insert(pool, entry)
end

-- ---- flight math --------------------------------------------------------

local function mapParticleCount(count: number): number
	if count <= PARTICLES_MIN then
		return count -- min(count, mapped): 3 coins fly as 3 pips
	end
	local extra = (count - PARTICLES_MIN) // COUNT_PER_EXTRA_PARTICLE
	return math.min(PARTICLES_MIN + extra, PARTICLES_MAX)
end

-- Landing pop on the counter, throttled: a 14-pip burst restarts the pulse
-- tween a few times, not every 2 frames (which would read as frozen scale).
local function pulseTarget(flight: Flight)
	if flight.elapsed - flight.lastPulseAt < flight.pulseMinInterval then
		return
	end
	flight.lastPulseAt = flight.elapsed
	if flight.target.Parent then
		UIChrome.Pulse(flight.theme, flight.target)
	end
end

-- Complete a flight NOW: force-land the stragglers, fire everything owed.
-- User callbacks go through task.defer (never task.spawn: spawn resumes
-- immediately and a callback calling Fly again would mutate the flights map
-- mid-iteration; defer keeps FIFO order so counters still tick in sequence).
local function finishFlight(flight: Flight)
	if flights[flight.target] ~= flight then
		return
	end
	flights[flight.target] = nil
	flightCount -= 1
	local total = #flight.particles
	for _, particle in flight.particles do
		if not particle.landed then
			particle.landed = true
			releaseParticle(particle.entry)
			flight.landedCount += 1
			local onLand = flight.onLand
			if not flight.single and onLand then
				task.defer(onLand, flight.landedCount, total)
			end
		end
	end
	if flight.single then
		if flight.target.Parent then
			UIChrome.Pulse(flight.theme, flight.target) -- the one big landing pop
		end
		local onLand = flight.onLand
		if onLand then
			task.defer(onLand, 1, 1)
		end
	end
	for _, rider in flight.riders do
		local riderLand = rider.onLand
		if riderLand then
			task.defer(riderLand, 1, 1)
		end
		local riderDone = rider.onDone
		if riderDone then
			task.defer(riderDone)
		end
	end
	local onDone = flight.onDone
	if onDone then
		task.defer(onDone)
	end
end

-- ---- THE one shared per-frame driver ------------------------------------

local function step(dt: number, _now: number)
	local root = toastRoot
	if not root or root.Parent == nil then
		return
	end
	local rootPos = root.AbsolutePosition
	local rootSize = root.AbsoluteSize
	local sx = math.max(rootSize.X, 1)
	local sy = math.max(rootSize.Y, 1)

	-- finishFlight removes the CURRENT key during iteration, which Luau
	-- allows (only additions are undefined) — see the defer note above for
	-- why callbacks can never add keys mid-loop.
	for target, flight in flights do
		flight.elapsed += dt
		if target.Parent == nil then
			-- Counter died mid-flight (screen closed): jump to the final
			-- confirmed state; callbacks still fire so caller totals settle.
			finishFlight(flight)
			continue
		end
		local particles = flight.particles
		local total = #particles
		if total == 0 then
			-- Slot-starved coalesced flight: a timed single big landing.
			if flight.elapsed >= flight.holdFor then
				finishFlight(flight)
			end
			continue
		end
		-- Re-read the target center every frame so a moving counter still
		-- catches its coins; origin and control points stay fixed.
		local targetCenter = target.AbsolutePosition + target.AbsoluteSize / 2
		local origin = flight.origin
		for _, particle in particles do
			if particle.landed then
				continue
			end
			local t = flight.elapsed - particle.delay
			if t < 0 then
				continue -- still waiting on its stagger slot
			end
			local frame = particle.entry.frame
			if not particle.launched then
				particle.launched = true
				frame.Visible = true
			end
			local alpha = math.min(t / particle.duration, 1)
			if alpha >= 1 then
				particle.landed = true
				releaseParticle(particle.entry)
				flight.landedCount += 1
				local onLand = flight.onLand
				if not flight.single and onLand then
					task.defer(onLand, flight.landedCount, total)
				end
				pulseTarget(flight)
			else
				-- Quadratic bezier, Quad-In time: fan out lazily off the
				-- launch point, then RUSH the counter (the coin-suck feel).
				local eased = TweenService:GetValue(alpha, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				local inv = 1 - eased
				local pos = origin * (inv * inv)
					+ particle.control * (2 * inv * eased)
					+ targetCenter * (eased * eased)
				-- Scale-relative positioning stays exact under the layer's
				-- 1650x1020 UIScale (offset px would need dividing back out).
				frame.Position = UDim2.fromScale((pos.X - rootPos.X) / sx, (pos.Y - rootPos.Y) / sy)
			end
		end
		if flight.landedCount >= total then
			finishFlight(flight)
		end
	end

	if flightCount <= 0 and stopTicker then
		-- Last flight done: the handler unregisters itself (idempotent stop;
		-- UITicker tolerates removal mid-dispatch).
		local stop = stopTicker
		stopTicker = nil
		stop()
	end
end

local function ensureTicker(root: Frame)
	if stopTicker then
		return
	end
	stopTicker = UITicker.Register(step, root)
end

-- Fetch the Toast layer root; if the layer was torn down and rebuilt since we
-- last looked (Layers.Destroy in tests), every pooled frame and the bound
-- ticker died with it — hard-reset module state so nothing points at husks.
local function ensureRoot(): Frame
	local root = Layers.Get("Toast")
	if toastRoot ~= root then
		if stopTicker then
			local stop = stopTicker
			stopTicker = nil
			stop()
		end
		table.clear(flights)
		flightCount = 0
		table.clear(pool)
		liveParticles = 0
		toastRoot = root
	end
	return root
end

local function reduceMotionActive(root: Frame): boolean
	return reduceMotionOverride or root:GetAttribute("ReduceMotion") == true
end

-- ---- API ----------------------------------------------------------------

-- Launch a flight. onLand(landedIndex, total) fires once per landing event,
-- landedIndex 1..total — callers tick their counter by amount slices
-- (count * landedIndex // total). A coalesced, merged, slot-starved, or
-- reduce-motion flight fires exactly ONE event: onLand(1, 1) — the whole
-- amount at once. Callbacks are always deferred, never synchronous.
function CurrencyFlight.Fly(opts: FlyOptions)
	local target = opts.toGuiObject
	local theme = opts.theme
	local count = math.max(math.floor(opts.count), 1)
	local root = ensureRoot()

	if reduceMotionActive(root) then
		-- No particles: the whole amount lands instantly.
		local onLand = opts.onLand
		if onLand then
			task.defer(onLand, 1, 1)
		end
		local onDone = opts.onDone
		if onDone then
			task.defer(onDone)
		end
		return
	end

	-- Merge: a flight already headed at this counter absorbs the new call —
	-- no extra particles; this call gets one big onLand when the host lands.
	local existing = flights[target]
	if existing then
		table.insert(existing.riders, { onLand = opts.onLand, onDone = opts.onDone })
		return
	end

	local tokens = flightTokens(theme)
	local single = count > COALESCE_COUNT
	local wanted = if single then COALESCED_PARTICLES else mapParticleCount(count)
	local slots = MAX_LIVE_PARTICLES - liveParticles
	if wanted > slots then
		wanted = math.max(slots, 0)
	end
	if wanted < 1 then
		single = true -- no slots left: coalesce into a particle-less landing
	end

	-- Empty id resolves to the gold "valuable" fallback per UIChrome policy.
	local currencyId = opts.currencyId or ""
	local origin = opts.fromAbsolutePosition
	local targetCenter = target.AbsolutePosition + target.AbsoluteSize / 2
	local dir = targetCenter - origin
	local perp = if dir.Magnitude > 0.001 then Vector2.new(-dir.Y, dir.X).Unit else Vector2.new(0, -1)

	local particles: { Particle } = {}
	for i = 1, wanted do
		local entry = acquireParticle(root, theme, currencyId, tokens)
		-- Control points fan out on alternating sides of the straight path,
		-- 35..100% of the pack's spread, seated 30..85% along the route.
		local side = if i % 2 == 0 then 1 else -1
		local fan = (0.35 + rng:NextNumber() * 0.65) * tokens.spread * side
		local along = 0.3 + rng:NextNumber() * 0.55
		table.insert(particles, {
			entry = entry,
			delay = (i - 1) * tokens.stagger + rng:NextNumber() * tokens.stagger * 0.5,
			duration = tokens.duration + rng:NextNumber() * tokens.durationJitter,
			control = origin:Lerp(targetCenter, along) + perp * fan,
			launched = false,
			landed = false,
		})
	end

	flights[target] = {
		target = target,
		theme = theme,
		origin = origin,
		elapsed = 0,
		particles = particles,
		landedCount = 0,
		single = single,
		holdFor = tokens.duration + tokens.durationJitter,
		pulseMinInterval = tokens.pulseMinInterval,
		lastPulseAt = -math.huge,
		onLand = opts.onLand,
		onDone = opts.onDone,
		riders = {},
	}
	flightCount += 1
	ensureTicker(root)
end

-- Settings hook: mirrors the ReduceMotion attribute path for callers that
-- wire the toggle programmatically (UIThemeController:SetReduceMotion era).
function CurrencyFlight.SetReduceMotion(reduce: boolean)
	reduceMotionOverride = reduce
end

-- Skippability (pack law): jump EVERY in-flight ceremony to its final
-- confirmed state — all owed onLand events and onDones fire, every particle
-- releases. Ceremony coordinators call this on any user input mid-sequence.
function CurrencyFlight.SkipAll()
	for _, flight in flights do
		finishFlight(flight)
	end
	if stopTicker then
		local stop = stopTicker
		stopTicker = nil
		stop()
	end
end

-- Test hook: drop every flight WITHOUT firing callbacks, release particles
-- back to the pool (disable-not-destroy), unregister the ticker.
function CurrencyFlight.Reset()
	for _, flight in flights do
		for _, particle in flight.particles do
			if not particle.landed then
				particle.landed = true
				releaseParticle(particle.entry)
			end
		end
	end
	table.clear(flights)
	flightCount = 0
	if stopTicker then
		local stop = stopTicker
		stopTicker = nil
		stop()
	end
	reduceMotionOverride = false
end

-- Test observability: pooled-but-idle frames don't count, only in-flight.
function CurrencyFlight.LiveParticleCount(): number
	return liveParticles
end

function CurrencyFlight.InFlightCount(): number
	return flightCount
end

return CurrencyFlight
