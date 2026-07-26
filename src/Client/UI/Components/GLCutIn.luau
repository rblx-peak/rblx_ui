--!strict
-- GLCutIn — the Gurren Lagann speedline cut-in banner (Life Pass juice
-- layer): a full-width comic band slams across the Overlay layer at the
-- comic slant, speedlines streaming down its length while GLSlamText slams
-- the callout word by word. Tier scaling: "normal" = band only; "rare" =
-- band + gold md glow; "giga" = full-screen ink takeover + lg glow + longer
-- hold.
--
-- THE 0.4 BOUNDARY: this module is the Luau + UITicker side. Styling owns
-- static appearance — the band wears UIPanel + DialectComic so the pack's
-- ".UIPanel.DialectComic" rules dress it once the engine activates styling
-- application; the imperative theme paint below renders the same look
-- meanwhile. Luau + UITicker own everything sequenced, continuous, or
-- non-styling-triggered: slide-in/hold/slide-out choreography, stripe
-- scrolling, word timing (delegated to GLSlamText — one text engine, not
-- two), tier holds. No StyleRule mirrors any of that, and no modifier tag
-- flips here — a cut-in is a ceremony, not a state.
--
-- NO-SKEW ANNOTATION: Roblox has no skew transform. The tilt is
-- whole-element Rotation on the band ART child (DialectTokens.comic
-- .slantDeg); the unrotated positioning root spans the screen width plus
-- bleed so the tilted band always covers edge to edge, and nothing ever
-- reflows. SPEEDLINES ARE NOT IMAGES: thin alternating gradient-faded
-- stripe frames in a clipped strip, wrapped by ONE ticker handler moving
-- ONE container — the ALTERNATING pattern's true period is TWO stripe
-- spacings (bright/dark parity), so the container wraps at exactly two
-- spacings and the stripe field carries two spacings of slack; a
-- one-spacing wrap would swap parities every cycle, a visible pop.
-- ClipsDescendants is set on the (rotated-space) clip frame, and the
-- geometry keeps stripe bleed plus off-screen band ends so the effect
-- also reads clean on engine builds that skip clipping under rotation.
--
-- REDUCE-MOTION (opts.reduceMotion, else a ReduceMotion attribute on the
-- band holder or the Overlay layer root): no slide, no scroll, no word
-- stagger — the band appears at its final pose with the full text, holds,
-- and vanishes. SKIPPABLE: handle.Skip() jumps to the final confirmed state
-- (dismissed; onDone fired) instantly at any point. The banner NEVER blocks
-- input (every frame stays Active = false); under "giga" — a takeover — any
-- UserInputService press also skips, while lesser tiers stay passive so
-- routine gameplay keys can't eat a routine banner.
--
-- POOLING & BUDGETS: ONE band structure, built lazily, reused by every Play
-- (rebuilt only when the active pack actually changes); the glows and the
-- comic sticker shadow keep their Capabilities handles between plays and
-- disable-not-destroy on release; the text label lives in GLSlamText's own
-- pool. At most ONE UITicker.Register is live (registered per play, stopped
-- at finalize; bound to the holder for auto-cleanup). 100x Play = zero
-- connection, instance, or budget growth.
--
--   local handle = GLCutIn.Play(theme, { text = "ROW ROW FIGHT THE POWER", tier = "rare" })
--   handle.Skip() -- collapse instantly (onDone still fires)

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UITicker = require(script.Parent.Parent.Framework.UITicker)
local Layers = require(script.Parent.Parent.Framework.Layers)
local StateDriver = require(script.Parent.Parent.StyleKit.StateDriver)
local Tags = require(script.Parent.Parent.StyleKit.Tags)
local Capabilities = require(script.Parent.Parent.StyleKit.Capabilities)
local GLSlamText = require(script.Parent.GLSlamText)

local GLCutIn = {}

export type CutInTier = "normal" | "rare" | "giga"

export type CutInOptions = {
	text: string,
	tier: CutInTier?,
	onDone: (() -> ())?,
	reduceMotion: boolean?,
}

export type CutInHandle = {
	Skip: () -> (),
}

-- Slide distance in position-scale units: fully clears the screen even with
-- the band's bleed and tilt overhang.
local OFFSCREEN_X = 1.4
-- The band root spans the screen plus bleed so the rotated art covers edge
-- to edge and stripe-wrap residue stays off-screen (see header).
local BAND_BLEED_SCALE = 1.3
-- Safety ceiling (guard rail, not choreography): a play can never outlive
-- this even if its slam callback is somehow lost.
local MAX_LIFE_SECONDS = 12

type Pool = {
	themeId: string,
	holder: Frame,
	backdrop: Frame,
	bandRoot: Frame,
	bandArt: Frame,
	strip: Frame,
	slamHost: Frame,
	stripeWrapScale: number, -- TWO stripe spacings: the alternating pattern's true period
	bandShadow: Capabilities.ShadowHandle?,
	glowMd: Capabilities.ShadowHandle?,
	glowLg: Capabilities.ShadowHandle?,
}

type PlayState = {
	tier: CutInTier,
	elapsed: number,
	scrollPhase: number, -- position-scale phase within one stripe spacing
	scrollPx: number, -- speedline drift, px/s
	inSeconds: number,
	holdSeconds: number,
	outSeconds: number,
	holdEnd: number?, -- armed by the slam's onDone; nil = text still landing
	backdropGoal: number,
	reduce: boolean,
	onDone: (() -> ())?,
	slam: GLSlamText.SlamHandle?,
	inputConn: RBXScriptConnection?,
}

-- ---- GL comic token access (GurrenLagannTheme.DialectTokens.comic is the
-- authority; fallbacks keep the banner sane under packs without dialects) --

local function comicTokens(theme: Types.UITheme): { [string]: any }?
	local dialects = theme.DialectTokens
	return if dialects then dialects.comic else nil
end

local function comicNumber(theme: Types.UITheme, key: string, fallback: number): number
	local comic = comicTokens(theme)
	local value = if comic then comic[key] else nil
	return if type(value) == "number" then value else fallback
end

local function comicColor(theme: Types.UITheme, key: string, fallback: Color3): Color3
	local comic = comicTokens(theme)
	local value = if comic then comic[key] else nil
	return if typeof(value) == "Color3" then value else fallback
end

-- ---- the pooled band (ONE structure, reused by every Play) ---------------

local pool: Pool? = nil
local activePlay: PlayState? = nil
local stopTicker: (() -> ())? = nil

local function teardownPool()
	local p = pool
	if not p then
		return
	end
	pool = nil
	-- Actual teardown (pack swap): budget slots are returned for real.
	if p.bandShadow then
		p.bandShadow:Release()
	end
	if p.glowMd then
		p.glowMd:Release()
	end
	if p.glowLg then
		p.glowLg:Release()
	end
	p.holder:Destroy()
end

local function buildPool(theme: Types.UITheme): Pool
	local overlay = Layers.Get("Overlay")

	local holder = UIStyler.Frame("GLCutIn")
	holder.BackgroundTransparency = 1
	holder.Visible = false
	holder.Active = false -- a cut-in never blocks input
	holder.ZIndex = 50
	holder.Parent = overlay

	-- Giga takeover backdrop: unrotated full-screen ink behind the band, so
	-- the tilted band's uncovered corners read as intentional blackout.
	local backdrop = UIStyler.Frame("Takeover")
	backdrop.BackgroundColor3 = comicColor(theme, "ink", theme.Colors.Overlay)
	backdrop.BackgroundTransparency = 1
	backdrop.Visible = false
	backdrop.Active = false
	backdrop.ZIndex = 1
	backdrop.Parent = holder

	-- Unrotated positioning root: the choreography moves THIS; the tilt
	-- lives on the art child (no-skew technique, see header).
	local bandRoot = UIStyler.Frame("BandRoot")
	bandRoot.BackgroundTransparency = 1
	bandRoot.Active = false
	bandRoot.AnchorPoint = Vector2.new(0.5, 0.5)
	bandRoot.Position = UDim2.fromScale(0.5, 0.5)
	bandRoot.Size = UDim2.new(BAND_BLEED_SCALE, 0, 0, 150) -- height set per Play
	bandRoot.ZIndex = 2
	bandRoot.Parent = holder

	local bandArt = UIStyler.Frame("BandArt")
	bandArt.BackgroundColor3 = theme.Colors.Primary
	bandArt.AnchorPoint = Vector2.new(0.5, 0.5)
	bandArt.Position = UDim2.fromScale(0.5, 0.5)
	bandArt.Size = UDim2.fromScale(1, 1)
	bandArt.Rotation = comicNumber(theme, "slantDeg", 0)
	bandArt.Active = false
	bandArt.ZIndex = 2
	UIChrome.Stroke(theme, "Arcade", "Panel").Parent = bandArt
	-- Structural identity + dialect scope for the styling side.
	StateDriver.Structural(bandArt, Tags.Structural.Panel)
	if comicTokens(theme) then
		StateDriver.SetDialect(bandArt, Tags.Dialect.Comic)
	end
	bandArt.Parent = bandRoot

	-- Comic sticker shadow (native UIShadow, budget-counted). Enabled only
	-- while a play is on screen; disable-not-destroy between plays.
	local bandShadow: Capabilities.ShadowHandle? = nil
	if theme.EffectShadows then
		local _shadowInstance, handle = UIChrome.Shadow(theme, "md", bandArt)
		local typed = handle :: Capabilities.ShadowHandle
		typed:SetEnabled(false)
		bandShadow = typed
	end

	-- Speedlines: 8–12 thin alternating stripes in a clipped strip, scrolled
	-- by ONE ticker handler moving ONE container. Stripes sit one spacing
	-- apart; because they ALTERNATE bright/dark, the pattern's true period
	-- is TWO spacings, so the wrap happens at two spacings and the field
	-- carries one spacing of lead-in bleed plus two spacings of tail slack
	-- (spacing = 1/(count - 4) makes the rightmost stripe sit exactly at the
	-- band edge at maximum phase — [0, 1] stays covered for every phase, and
	-- the wrap maps each stripe onto a SAME-PARITY predecessor: seamless).
	-- Each stripe is a plain frame with a transparency gradient — no image
	-- assets anywhere.
	local clip = UIStyler.Frame("SpeedlineClip")
	clip.BackgroundTransparency = 1
	clip.Active = false
	clip.ClipsDescendants = true -- see header re: clipping under rotation
	clip.ZIndex = 3
	clip.Parent = bandArt

	local strip = UIStyler.Frame("SpeedlineStrip")
	strip.BackgroundTransparency = 1
	strip.Active = false
	strip.ZIndex = 3
	strip.Parent = clip

	local count = math.clamp(math.floor(comicNumber(theme, "cutinStripeCount", 10)), 8, 12)
	local spacing = 1 / (count - 4)
	local brightColor = comicColor(theme, "paper", theme.Colors.TextPrimary)
	local darkColor = comicColor(theme, "ink", theme.Colors.Stroke)
	local brightTransparency = comicNumber(theme, "cutinStripeBrightTransparency", 0.45)
	local darkTransparency = comicNumber(theme, "cutinStripeDarkTransparency", 0.62)
	for index = 1, count do
		local bright = index % 2 == 0
		local stripe = UIStyler.Frame("Stripe" .. index)
		stripe.BackgroundColor3 = if bright then brightColor else darkColor
		stripe.BackgroundTransparency = if bright then brightTransparency else darkTransparency
		stripe.AnchorPoint = Vector2.new(0.5, 0.5)
		stripe.Position = UDim2.fromScale((index - 2) * spacing, 0.5)
		stripe.Size = UDim2.new(spacing * 0.3, 0, 1, 0)
		stripe.ZIndex = 3
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.25, 0.1),
			NumberSequenceKeypoint.new(0.75, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = stripe
		stripe.Parent = strip
	end

	-- GLSlamText's host: the slam label fills this and renders above the
	-- speedlines (sibling ZIndex).
	local slamHost = UIStyler.Frame("Callout")
	slamHost.BackgroundTransparency = 1
	slamHost.Active = false
	slamHost.AnchorPoint = Vector2.new(0.5, 0.5)
	slamHost.Position = UDim2.fromScale(0.5, 0.5)
	slamHost.Size = UDim2.new(1, -theme.Spacing.XL * 2, 1, 0)
	slamHost.ZIndex = 4
	slamHost.Parent = bandArt

	return {
		themeId = theme.Id,
		holder = holder,
		backdrop = backdrop,
		bandRoot = bandRoot,
		bandArt = bandArt,
		strip = strip,
		slamHost = slamHost,
		stripeWrapScale = spacing * 2,
		bandShadow = bandShadow,
		glowMd = nil,
		glowLg = nil,
	}
end

local function ensurePool(theme: Types.UITheme): Pool
	local p = pool
	if p and p.themeId == theme.Id and p.holder.Parent ~= nil then
		return p
	end
	teardownPool()
	local fresh = buildPool(theme)
	pool = fresh
	return fresh
end

-- ---- finalize (natural completion AND Skip — identical end state) --------

local function finalize(fireDone: boolean)
	local play = activePlay
	if not play then
		return
	end
	activePlay = nil
	if stopTicker then
		stopTicker()
		stopTicker = nil
	end
	if play.inputConn then
		play.inputConn:Disconnect()
		play.inputConn = nil
	end
	local slam = play.slam
	if slam then
		play.slam = nil
		slam.Destroy() -- releases the pooled label; never re-fires its onDone
	end
	local p = pool
	if p then
		p.holder.Visible = false
		p.backdrop.Visible = false
		p.backdrop.BackgroundTransparency = 1
		-- Pooled effects park: disable-not-destroy (budget handles kept).
		if p.glowMd then
			p.glowMd:SetEnabled(false)
		end
		if p.glowLg then
			p.glowLg:SetEnabled(false)
		end
		if p.bandShadow then
			p.bandShadow:SetEnabled(false)
		end
	end
	if fireDone then
		local callback = play.onDone
		play.onDone = nil
		if callback then
			task.spawn(callback)
		end
	end
end

-- ---- the per-play ticker handler (the module's ONE Register) -------------

local function step(dt: number, _now: number)
	local play = activePlay
	local p = pool
	if not play or not p then
		return
	end
	play.elapsed += dt
	local e = play.elapsed

	if not play.reduce then
		-- Speedline scroll: one container, wrapped at the pattern period
		-- (TWO stripe spacings — the alternation's parity survives the wrap).
		local widthPx = math.max(1, p.bandArt.AbsoluteSize.X)
		play.scrollPhase = (play.scrollPhase + (play.scrollPx * dt) / widthPx) % p.stripeWrapScale
		p.strip.Position = UDim2.new(-play.scrollPhase, 0, 0, 0)

		local holdEnd = play.holdEnd
		if e < play.inSeconds then
			-- Slide in: Back Out — overshoots center, settles on it.
			local alpha = TweenService:GetValue(e / play.inSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			p.bandRoot.Position = UDim2.new(0.5 - (1 - alpha) * OFFSCREEN_X, 0, 0.5, 0)
			if play.tier == "giga" then
				p.backdrop.BackgroundTransparency = 1 - (1 - play.backdropGoal) * math.clamp(alpha, 0, 1)
			end
		elseif holdEnd and e >= holdEnd then
			-- Slide out: quick Quad In exit to the right.
			local alpha = TweenService:GetValue(
				math.clamp((e - holdEnd) / math.max(play.outSeconds, 0.01), 0, 1),
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.In
			)
			p.bandRoot.Position = UDim2.new(0.5 + alpha * OFFSCREEN_X, 0, 0.5, 0)
		else
			p.bandRoot.Position = UDim2.fromScale(0.5, 0.5)
			if play.tier == "giga" then
				p.backdrop.BackgroundTransparency = play.backdropGoal
			end
		end
	end

	-- The hold clock arms once the slam lands (holdEnd set by its onDone).
	local holdEnd = play.holdEnd
	if holdEnd and e >= holdEnd + play.outSeconds then
		finalize(true)
		return
	end
	if e >= MAX_LIFE_SECONDS then
		finalize(true)
	end
end

-- ---- API ----------------------------------------------------------------

-- Plays the cut-in on the Overlay layer. Returns { Skip }. A Play issued
-- while another is live collapses the previous one first (its onDone still
-- fires — a queued reward must never be lost).
function GLCutIn.Play(theme: Types.UITheme, opts: CutInOptions): CutInHandle
	finalize(true)

	local p = ensurePool(theme)
	local tier: CutInTier = opts.tier or "normal"

	local reduce = opts.reduceMotion
	if reduce == nil then
		local overlay = p.holder.Parent
		reduce = p.holder:GetAttribute("ReduceMotion") == true
			or (overlay ~= nil and overlay:GetAttribute("ReduceMotion") == true)
	end
	local reduceMotion: boolean = reduce == true

	-- Tier geometry: strip for normal/rare, takeover-scale band for giga.
	if tier == "giga" then
		p.bandRoot.Size = UDim2.new(BAND_BLEED_SCALE, 0, comicNumber(theme, "cutinGigaBandScale", 0.46), 0)
	else
		p.bandRoot.Size = UDim2.new(BAND_BLEED_SCALE, 0, 0, math.floor(comicNumber(theme, "cutinBandHeightPx", 150)))
	end

	-- Tier effects: gold glows built lazily ONCE, then enable/disable only.
	if tier == "rare" then
		local glow = p.glowMd
		if glow == nil then
			local _glowInstance, handle = UIChrome.Glow(theme, "md", p.bandArt)
			p.glowMd = handle :: Capabilities.ShadowHandle
		else
			glow:SetEnabled(true)
		end
	elseif tier == "giga" then
		local glow = p.glowLg
		if glow == nil then
			local _glowInstance, handle = UIChrome.Glow(theme, "lg", p.bandArt)
			p.glowLg = handle :: Capabilities.ShadowHandle
		else
			glow:SetEnabled(true)
		end
	end
	if p.bandShadow then
		p.bandShadow:SetEnabled(true)
	end

	local backdropGoal = comicNumber(theme, "cutinBackdropTransparency", 0.35)
	p.backdrop.Visible = tier == "giga"
	p.backdrop.BackgroundTransparency = if reduceMotion and tier == "giga" then backdropGoal else 1

	local holdSeconds = if tier == "giga"
		then comicNumber(theme, "cutinHoldGiga", 1.9)
		elseif tier == "rare" then comicNumber(theme, "cutinHoldRare", 1.15)
		else comicNumber(theme, "cutinHoldNormal", 0.8)

	-- Reduce-motion collapses the slide phases to instant final poses.
	local inSeconds = if reduceMotion then 0 else comicNumber(theme, "cutinSlideSeconds", 0.2)
	local outSeconds = if reduceMotion then 0 else comicNumber(theme, "cutinOutSeconds", 0.14)

	p.bandRoot.Position = if reduceMotion
		then UDim2.fromScale(0.5, 0.5)
		else UDim2.new(0.5 - OFFSCREEN_X, 0, 0.5, 0)
	p.strip.Position = UDim2.fromScale(0, 0)
	p.holder.Visible = true

	local play: PlayState = {
		tier = tier,
		elapsed = 0,
		scrollPhase = 0,
		scrollPx = comicNumber(theme, "cutinStripeScrollPxPerSec", 520),
		inSeconds = inSeconds,
		holdSeconds = holdSeconds,
		outSeconds = outSeconds,
		holdEnd = nil,
		backdropGoal = backdropGoal,
		reduce = reduceMotion,
		onDone = opts.onDone,
		slam = nil,
		inputConn = nil,
	}
	activePlay = play

	-- Word timing belongs to GLSlamText (one text engine, not two); its
	-- onDone arms the hold clock relative to whichever finishes later, the
	-- slide or the slam.
	play.slam = GLSlamText.Play(p.slamHost, theme, opts.text, {
		sizePx = if tier == "giga"
			then math.floor(theme.TextSizes.Title * comicNumber(theme, "cutinGigaTextScale", 1.6))
			else theme.TextSizes.Title,
		reduceMotion = reduceMotion,
		onDone = function()
			if activePlay == play then
				play.holdEnd = math.max(play.inSeconds, play.elapsed) + play.holdSeconds
			end
		end,
	})

	if tier == "giga" then
		-- A TAKEOVER yields to the player instantly (skippable law). Lesser
		-- tiers stay passive: routine gameplay input must not eat a routine
		-- banner — their skip hook is the returned handle.
		play.inputConn = UserInputService.InputBegan:Connect(function(_input, _processed)
			if activePlay == play then
				finalize(true)
			end
		end)
	end

	-- The module's ONE ticker registration, live only while a play is
	-- (finalize stops it); bound to the holder for auto-cleanup.
	stopTicker = UITicker.Register(step, p.holder)

	return {
		Skip = function()
			if activePlay == play then
				finalize(true)
			end
		end,
	}
end

return GLCutIn
