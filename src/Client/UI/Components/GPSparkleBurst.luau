--!strict
-- GPSparkleBurst — the pooled sparkle emitter: a transparent, input-inert field
-- you parent into a screen, which throws a short spray of token-tinted twinkles
-- from any point on demand. Extends UIComponentBase so it restyles live and
-- tears down with its screen like every other component.
--
-- Generic and theme-agnostic by construction: the art, tint, count, spread,
-- duration and size all resolve from theme tokens, and the whole thing degrades
-- to soft rounded pips when a pack ships no sparkle asset. Nothing pink is
-- written down here.
--
-- THE 0.4 BOUNDARY: this module is ENTIRELY on the Luau + UITicker side. A
-- burst is sequenced, continuous, transient choreography, so it is driven here
-- and only here. Styling owns nothing of it: particles are deliberately
-- UNTAGGED (the CurrencyFlight rule — transient effect art must not be
-- restylable mid-flight by a pack rule), and their static look comes from theme
-- tokens at acquire time. No StyleRule mirrors any behaviour in this file.
--
-- ONE SHARED TICKER FOR ALL BURSTS, ACROSS ALL EMITTERS. A single module-level
-- UITicker registration drives every live particle in the game; it exists only
-- while the live list is non-empty and unregisters itself the frame it empties.
-- It is deliberately NOT bound to any one instance: it outlives individual
-- emitters by design, and binding it to whichever emitter happened to register
-- first would kill every other emitter's particles when that one died. Teardown
-- is guaranteed from three directions instead — each emitter releases its own
-- particles in Destroy, the step prunes any particle whose host has left the
-- DataModel, and the refcount stops the handler at zero. 100 screens opening
-- and closing therefore leaves exactly zero registrations, never 100.
--
-- POOLING & BUDGET: particle instances come from a module pool and are released
-- with Visible = false, never destroyed. A pooled frame whose emitter was torn
-- down becomes a husk (Parent == nil) and is discarded at acquire time. No
-- UIShadow is ever attached to a particle, so this module spends NOTHING from
-- the Capabilities shadow budget — a sparkle spray is the one place a soft glow
-- would be most tempting and least affordable (a 6-particle burst would be 6 of
-- the 80-shadow warning threshold).
--
-- CAPS ARE LAWS, NOT TUNING. Concurrent bursts are capped, total live particles
-- are capped, and a burst that finds no slots is DROPPED rather than queued —
-- a celebration that arrives late is worse than one that doesn't arrive.
--
-- FLASH RATE (photosensitivity, non-negotiable): each particle's opacity is ONE
-- smooth rise and fall — a single luminance event, never a flicker — and the
-- throttle is MODULE-WIDE, not per emitter. Three luminance events per second is
-- an accessibility ceiling on the SCREEN, not on one widget: six emitters each
-- politely holding to 3/s would still put eighteen flashes a second in front of
-- the player. So MIN_BURST_INTERVAL gates a single shared timestamp and the
-- first caller inside a window wins — a decorative corner sparkle can lose a
-- race with the reward burst, which is the correct trade for a safety law.
--
-- REDUCE-MOTION: a ReduceMotion boolean attribute on the Root (or wired via
-- SetReduceMotion) collapses a burst to ONE static twinkle that fades in place
-- — no travel, no spin, no spray. The celebration still reads; nothing moves.
-- Nothing here ever blocks input: the field and every particle are Active =
-- false, so a burst can never eat a tap.
--
--   local sparkles = GPSparkleBurst.new()
--   sparkles:Create(screenRoot)                  -- a full-bleed, inert field
--   sparkles:Burst(button.AbsolutePosition + button.AbsoluteSize / 2)
--
-- The Vector2 is an ABSOLUTE screen position, which is why GPBouncyButton's
-- sparkleEmitter hook hands over its own absolute centre: positions are
-- converted into the field's SCALE space so they stay exact under the layer's
-- 1650x1020 UIScale (offset px would need dividing back out).

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UITicker = require(script.Parent.Parent.Framework.UITicker)
local UIComponentBase = require(script.Parent.UIComponentBase)

local GPSparkleBurst = setmetatable({}, { __index = UIComponentBase })
GPSparkleBurst.__index = GPSparkleBurst

-- ---- laws (caps and rates, not feel) ------------------------------------

local MAX_LIVE_SPARKLES = 48 -- global, across every emitter
local MAX_CONCURRENT_BURSTS = 6 -- global; a 7th is dropped, never queued
-- Photosensitivity ceiling: at most 3 luminance events per second ON SCREEN,
-- counted across every emitter at once (see the flash-rate law in the header).
-- Measured against os.clock (real wall time), NOT UITicker.Now — the shared
-- clock only advances while some handler is registered, so a pack tokenizing a
-- very short sparkle would let the clock freeze between bursts and the throttle
-- would silently stop throttling. A safety law must not depend on the thing it
-- is protecting the player from.
local MIN_BURST_INTERVAL = 1 / 3
-- And the floor on a particle's own life, for the same reason: a 0.05s rise and
-- fall IS a strobe however few of them there are. Packs may slow a sparkle
-- down, never speed it past this.
local MIN_PARTICLE_SECONDS = 0.25
-- Fraction of a particle's life spent brightening. One rise, one fall, no
-- second peak — that is what makes a burst a glow and not a strobe.
local RISE_FRACTION = 0.18
local PARTICLE_ZINDEX = 90

-- ---- house feel (fallbacks for packs that name no glaze dialect) ---------

type SparkleTokens = {
	count: number,
	spreadPx: number,
	seconds: number,
	sizePx: number,
	spinDegrees: number,
	stagger: number,
}

local SPARKLE_DEFAULTS: SparkleTokens = {
	count = 6,
	spreadPx = 74,
	seconds = 0.52,
	sizePx = 26,
	spinDegrees = 120,
	stagger = 0.03,
}

local function sparkleTokens(theme: Types.UITheme): SparkleTokens
	local dialects = theme.DialectTokens
	local glaze: { [string]: any } = (dialects and dialects.glaze) or {}
	return {
		count = tonumber(glaze.sparkleCount) or SPARKLE_DEFAULTS.count,
		spreadPx = tonumber(glaze.sparkleSpreadPx) or SPARKLE_DEFAULTS.spreadPx,
		seconds = tonumber(glaze.sparkleSeconds) or SPARKLE_DEFAULTS.seconds,
		sizePx = tonumber(glaze.sparkleSizePx) or SPARKLE_DEFAULTS.sizePx,
		spinDegrees = tonumber(glaze.sparkleSpinDegrees) or SPARKLE_DEFAULTS.spinDegrees,
		stagger = tonumber(glaze.sparkleStagger) or SPARKLE_DEFAULTS.stagger,
	}
end

-- ---- module state (the pool, the live list, the ONE ticker) -------------

type PoolEntry = {
	image: ImageLabel,
	themeId: string?,
	usesImage: boolean,
}

type Live = {
	entry: PoolEntry,
	host: GuiObject,
	burstId: number,
	origin: Vector2, -- absolute screen px, captured at spawn
	angle: number,
	distance: number,
	spin: number,
	elapsed: number,
	delay: number,
	duration: number,
	sizePx: number,
}

local pool: { PoolEntry } = {}
local live: { Live } = {}
local liveCount = 0
-- Concurrency is counted per BURST, not per particle: a burst is "active" until
-- its LAST particle dies. Counting a raw total instead would let a long tail of
-- stragglers permanently occupy the cap and starve every later celebration.
local burstParticles: { [number]: number } = {}
local burstCount = 0
local nextBurstId = 0
local stopTicker: (() -> ())? = nil
local reduceMotionOverride = false
local rng = Random.new()
-- THE flash-rate clock, shared by every emitter in the game (see the header):
-- a per-emitter timestamp would let N emitters multiply the on-screen rate by N.
local lastFlashAt = -math.huge

local function releaseParticle(particle: Live)
	particle.entry.image.Visible = false
	liveCount -= 1
	table.insert(pool, particle.entry)
	local remaining = (burstParticles[particle.burstId] or 1) - 1
	if remaining <= 0 then
		burstParticles[particle.burstId] = nil
		burstCount -= 1
	else
		burstParticles[particle.burstId] = remaining
	end
end

-- Acquire a pooled particle, re-chroming it only when the pack changed since it
-- last flew (the art and tint are pack policy, not per-burst values). Husks —
-- frames whose emitter was destroyed out from under the pool — are discarded
-- here rather than swept, so teardown costs nothing.
local function acquireEntry(host: GuiObject, theme: Types.UITheme, tint: Color3, sizePx: number): PoolEntry
	local entry: PoolEntry? = nil
	while #pool > 0 do
		local candidate = table.remove(pool) :: PoolEntry
		if candidate.image.Parent ~= nil then
			entry = candidate
			break
		end
	end
	if not entry then
		local image = Instance.new("ImageLabel")
		image.Name = "Sparkle"
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.BackgroundTransparency = 1
		image.BorderSizePixel = 0
		image.ScaleType = Enum.ScaleType.Fit
		image.Active = false -- a sparkle never eats a tap
		image.Visible = false
		image.ZIndex = PARTICLE_ZINDEX
		entry = { image = image, themeId = nil, usesImage = false }
	end
	local acquired = entry :: PoolEntry
	acquired.image.Parent = host

	if acquired.themeId ~= theme.Id then
		local assets = theme.Assets
		local def = assets and assets.sparkle
		local existingCorner = acquired.image:FindFirstChildOfClass("UICorner")
		if def then
			acquired.usesImage = true
			acquired.image.Image = def.image
			acquired.image.BackgroundTransparency = 1
			if existingCorner then
				existingCorner:Destroy()
			end
		else
			-- TODO: asset missing — a soft rounded PIP in the same tint. Still
			-- soft, still token-tinted, never a hard placeholder square.
			acquired.usesImage = false
			acquired.image.Image = ""
			if not existingCorner then
				UIStyler.Corner(theme.Radii.Pill).Parent = acquired.image
			end
		end
		acquired.themeId = theme.Id
	end

	if acquired.usesImage then
		acquired.image.ImageColor3 = tint
		acquired.image.ImageTransparency = 1
	else
		acquired.image.BackgroundColor3 = tint
		acquired.image.BackgroundTransparency = 1
	end
	acquired.image.Size = UDim2.fromOffset(sizePx, sizePx)
	acquired.image.Rotation = 0
	liveCount += 1
	return acquired
end

local function setParticleAlpha(entry: PoolEntry, transparency: number)
	if entry.usesImage then
		entry.image.ImageTransparency = transparency
	else
		entry.image.BackgroundTransparency = transparency
	end
end

-- THE one shared per-frame driver. Iterated backwards so a release can swap-pop
-- without disturbing the walk.
local function step(dt: number, _now: number)
	for index = #live, 1, -1 do
		local particle = live[index]
		local host = particle.host
		if host.Parent == nil then
			-- The emitter's screen was torn down mid-burst: the particle is
			-- released and its slot returned, with no callback owed to anyone.
			releaseParticle(particle)
			table.remove(live, index)
			continue
		end
		particle.elapsed += dt
		local t = particle.elapsed - particle.delay
		if t < 0 then
			continue -- still waiting on its stagger slot
		end
		local alpha = t / particle.duration
		if alpha >= 1 then
			releaseParticle(particle)
			table.remove(live, index)
			continue
		end

		local image = particle.entry.image
		if not image.Visible then
			image.Visible = true
		end

		-- Outward drift on a cubic ease-out: the spray leaves fast and coasts
		-- to a stop, which is what makes it read as a burst rather than a slide.
		local ease = 1 - (1 - alpha) ^ 3
		local reach = particle.distance * ease
		local pos = particle.origin
			+ Vector2.new(math.cos(particle.angle) * reach, math.sin(particle.angle) * reach)
		local hostPos = host.AbsolutePosition
		local hostSize = host.AbsoluteSize
		-- Scale-relative, never offset px: the layer carries a UIScale, and an
		-- offset derived from AbsolutePosition would need dividing back out.
		image.Position = UDim2.fromScale(
			(pos.X - hostPos.X) / math.max(hostSize.X, 1),
			(pos.Y - hostPos.Y) / math.max(hostSize.Y, 1)
		)

		-- ONE luminance event: a single rise then a single fall. No second peak
		-- anywhere in a particle's life — see the flash-rate law in the header.
		local luminance = if alpha < RISE_FRACTION
			then alpha / RISE_FRACTION
			else 1 - (alpha - RISE_FRACTION) / (1 - RISE_FRACTION)
		setParticleAlpha(particle.entry, 1 - luminance)
		-- Size rides the same curve so the twinkle POPS instead of sliding in.
		local scaled = particle.sizePx * (0.45 + 0.55 * luminance)
		image.Size = UDim2.fromOffset(scaled, scaled)
		image.Rotation = particle.spin * alpha
	end

	if #live == 0 and stopTicker then
		-- Last particle gone: the handler unregisters itself (idempotent stop;
		-- UITicker tolerates removal mid-dispatch).
		local stop = stopTicker
		stopTicker = nil
		stop()
	end
end

local function ensureTicker()
	if stopTicker then
		return
	end
	stopTicker = UITicker.Register(step)
end

-- ---- component ----------------------------------------------------------

export type BurstOptions = {
	count: number?,
	tint: Color3?,
	spreadPx: number?,
	seconds: number?,
	sizePx: number?,
}

function GPSparkleBurst.new()
	local self = UIComponentBase.new("GPSparkleBurst")
	return setmetatable(self, GPSparkleBurst)
end

function GPSparkleBurst:_Build(props: Types.UIComponentProps)
	local root = self.Root
	root.BackgroundTransparency = 1
	root.Active = false -- an effect field never blocks input
	-- NOT ClipsDescendants: a burst is meant to spray past the box it was
	-- thrown from, and clipping it would shave the spray at the field's edge.
	if not props.size then
		-- Full-bleed by default so absolute-space origins always land inside
		-- the field's own box and the scale conversion stays well-conditioned.
		root.Size = UDim2.fromScale(1, 1)
		self._baseSize = root.Size
	end
	root.ZIndex = props.zIndex or PARTICLE_ZINDEX

	-- Reduce-motion: cached from the Root's attribute; a live flip is honoured
	-- by the NEXT burst (an in-flight spray is never yanked mid-air).
	self._reduceMotion = root:GetAttribute("ReduceMotion") == true
	self:_Connect(root:GetAttributeChangedSignal("ReduceMotion"), function()
		self._reduceMotion = root:GetAttribute("ReduceMotion") == true
	end)
end

-- Nothing to paint: the field is transparent and the particles take their tint
-- at acquire time from whatever theme is active THEN, so a mid-burst theme swap
-- never repaints art that is already fading out. Present because ApplyTheme
-- calls it, and because a reader looking for the paint should find this note.
function GPSparkleBurst:_Style(_theme: Types.UITheme) end

-- Throw a spray. `center` is an ABSOLUTE screen position (defaults to the
-- field's own centre). Returns true if the burst played, false if it was
-- refused — by the flash-rate throttle, the concurrency cap, or the particle
-- cap. Callers do not need to check: a refused sparkle is a non-event.
function GPSparkleBurst:Burst(center: Vector2?, opts: BurstOptions?): boolean
	local theme = self.Theme :: Types.UITheme?
	local root = self.Root :: GuiObject
	if not theme or self._destroyed or root.Parent == nil then
		return false
	end

	-- THE FLASH-RATE LAW, enforced by refusal against the MODULE-WIDE clock: a
	-- caller mashing a button — or six emitters each behaving impeccably on
	-- their own — cannot put more than three luminance events a second on
	-- screen, because there is only one timestamp to beat.
	local now = os.clock()
	if now - lastFlashAt < MIN_BURST_INTERVAL then
		return false
	end
	if burstCount >= MAX_CONCURRENT_BURSTS then
		return false
	end

	local options: BurstOptions = opts or {}
	local tokens = sparkleTokens(theme)
	local tint = options.tint or theme.Colors.Accent
	local sizePx = options.sizePx or tokens.sizePx
	local origin = center or (root.AbsolutePosition + root.AbsoluteSize / 2)
	local reduce = reduceMotionOverride or self._reduceMotion == true

	-- Reduce-motion is ONE static twinkle fading in place: the celebration
	-- still reads, and nothing travels, spins or sprays.
	local wanted = if reduce then 1 else math.max(1, math.floor(options.count or tokens.count))
	local slots = MAX_LIVE_SPARKLES - liveCount
	if slots <= 0 then
		return false
	end
	wanted = math.min(wanted, slots)

	local spread = if reduce then 0 else (options.spreadPx or tokens.spreadPx)
	local duration = options.seconds or tokens.seconds
	-- A staggered spray under reduce-motion would be a sequence, which is the
	-- exact thing reduce-motion removes; the single twinkle starts immediately.
	local stagger = if reduce then 0 else tokens.stagger
	local baseAngle = rng:NextNumber() * 2 * math.pi

	nextBurstId += 1
	local burstId = nextBurstId
	for i = 1, wanted do
		local entry = acquireEntry(root, theme, tint, sizePx)
		-- Even angular spacing plus jitter: an evenly-fanned burst reads as a
		-- deliberate flourish, a purely random one reads as a rendering fault.
		local angle = baseAngle + (i - 1) * (2 * math.pi / wanted) + rng:NextNumber(-0.25, 0.25)
		table.insert(live, {
			entry = entry,
			host = root,
			burstId = burstId,
			origin = origin,
			angle = angle,
			distance = spread * (0.55 + rng:NextNumber() * 0.45),
			spin = if reduce then 0 else rng:NextNumber(-1, 1) * tokens.spinDegrees,
			elapsed = 0,
			delay = (i - 1) * stagger,
			-- MIN_PARTICLE_SECONDS is a floor, not a default: a pack may slow a
			-- twinkle down but can never speed it into a strobe.
			duration = math.max(duration, MIN_PARTICLE_SECONDS) + rng:NextNumber() * 0.08,
			sizePx = sizePx,
		})
		-- Park it invisible until its stagger slot opens, so a staggered
		-- particle can never flash for a frame at a stale position.
		entry.image.Visible = false
		setParticleAlpha(entry, 1)
	end

	burstParticles[burstId] = wanted
	burstCount += 1
	lastFlashAt = now
	ensureTicker()
	return true
end

-- Settings hook, mirroring the ReduceMotion attribute path for callers that
-- wire the toggle programmatically (the CurrencyFlight precedent). Module-wide
-- on purpose: reduce-motion is a player setting, not a per-emitter one.
function GPSparkleBurst.SetReduceMotion(reduce: boolean)
	reduceMotionOverride = reduce
end

-- Test observability: pooled-but-idle particles don't count, only live ones.
function GPSparkleBurst.LiveSparkleCount(): number
	return liveCount
end

function GPSparkleBurst.ActiveBurstCount(): number
	return burstCount
end

-- Test hook: drop every live particle back to the pool and stop the shared
-- ticker. Never destroys pooled instances — that is the pool's whole point.
function GPSparkleBurst.Reset()
	for index = #live, 1, -1 do
		releaseParticle(live[index])
		table.remove(live, index)
	end
	table.clear(burstParticles)
	burstCount = 0
	if stopTicker then
		local stop = stopTicker
		stopTicker = nil
		stop()
	end
	reduceMotionOverride = false
	lastFlashAt = -math.huge
end

function GPSparkleBurst:Destroy()
	-- Release THIS field's particles explicitly rather than waiting for the
	-- step's husk sweep: the root is about to be destroyed, and a live count
	-- that only falls on the next frame would briefly deny slots to whatever
	-- screen opens next.
	local root = self.Root
	for index = #live, 1, -1 do
		if live[index].host == root then
			releaseParticle(live[index])
			table.remove(live, index)
		end
	end
	if #live == 0 and stopTicker then
		local stop = stopTicker
		stopTicker = nil
		stop()
	end
	UIComponentBase.Destroy(self)
end

return GPSparkleBurst
