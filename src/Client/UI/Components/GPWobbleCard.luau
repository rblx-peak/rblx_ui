--!strict
-- GPWobbleCard — a wrapper that makes whatever you put inside it feel alive: a
-- slow idle "breathe" on UIScale and a small tilt toward the pointer on hover.
-- It paints nothing and owns no surface of its own; it is pure motion applied
-- to someone else's card. Extends UIComponentBase so it restyles live (the
-- motion magnitudes are tokens) and tears down with its screen.
--
-- Generic and theme-agnostic by construction: amplitude, period and tilt are
-- all DialectTokens.motion values, and a pack that declares no motion namespace
-- gets a wrapper that does nothing at all and costs nothing — no ticker slot,
-- no per-frame work. Nothing pink is written down here.
--
-- THE 0.4 BOUNDARY: this component is ENTIRELY on the Luau + UITicker side.
-- Idle breathing and pointer tilt are continuous, non-styling-triggered
-- choreography, so they are driven here and only here. Styling owns nothing of
-- it — deliberately, this wrapper flips NO tags and applies NO structural tag,
-- because it has no surface for a pack rule to dress; the content inside it
-- carries its own identity. A behaviour implemented on BOTH sides is a bug, and
-- there is nothing here for a StyleRule to duplicate.
--
-- PHASE OFFSET IS THE WHOLE POINT. Twelve cards breathing in lockstep read as
-- the SCREEN pulsing — a bug, or worse, a seizure risk. The phase is derived
-- from LayoutOrder against a PRIME bucket count, so a 2-, 3-, 4-, 5- or
-- 6-column grid never lands two neighbours on the same phase within a row, and
-- successive rows do not resynchronise either. Deriving it from LayoutOrder
-- rather than from math.random also means the pattern is STABLE across a
-- rebuild: a screen that restyles does not reshuffle its own breathing.
--
-- ONE SHARED TICKER FOR EVERY CARD. A single module-level UITicker registration
-- drives all live wrappers; it exists only while at least one is registered and
-- unregisters itself the moment the last one leaves. Per-card cleanup is bound
-- to the ROOT from two directions — UIComponentBase already wires
-- Root.Destroying to Destroy (which deregisters), and the shared step prunes
-- any card whose root has left the DataModel without being destroyed — so a
-- screen rebuild can never leave a stale entry driving a dead frame. 100 cards
-- is ONE Heartbeat connection, and 100 open/close cycles leave zero.
--
-- SCALE IS UISCALE, NEVER SIZE, and the breathe is capped at 2%. Size is what
-- layout measures: breathing on Size would make a grid of cards jitter its own
-- gutters at 0.33Hz. UIScale is visual and centred, so each card swells inside
-- its own cell and nothing moves. The cap is a LAW rather than a default — a
-- pack may make the breathe subtler, never louder, because a large idle scale
-- on a grid is motion sickness rather than charm.
--
-- NO-SKEW / NO-CLIP ANNOTATION: Roblox has no skew, so the tilt is
-- whole-element Rotation on the CARD child; the transparent root keeps its
-- unrotated rectangular footprint, so layout never reflows and hit targets stay
-- predictable. Roblox clipping is axis-aligned and does NOT clip rotated
-- descendants: a tilted card inside a ScrollingFrame will visibly overhang the
-- viewport's edge at the top and bottom of the scroll. Callers putting these in
-- a scroller should either leave DialectTokens.motion.tiltSm worth of margin or
-- pass tilt = false — the breathe alone is safe anywhere.
--
-- REDUCE-MOTION: a ReduceMotion boolean attribute on the Root parks the card at
-- the static pose — scale 1, rotation 0 — and the handler then does no work at
-- all. Off-screen (UIChrome.IsOnScreen) it does no work either. Nothing here is
-- a blocking ceremony and nothing captures input: the wrapper listens to
-- MouseEnter/MouseLeave/MouseMoved on a plain Frame, so clicks pass straight
-- through to whatever the caller put inside.
--
--   local wobble = GPWobbleCard.new()
--   wobble:Create(grid, { layoutOrder = i })
--   myCard.Parent = wobble.Content
--
-- Props (plus the shared layout props from UIComponentBase):
--   adopt   : a GuiObject to reparent into Content at build time
--   breathe : false disables the idle scale
--   tilt    : false disables the hover tilt (see the clipping note above)

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UITicker = require(script.Parent.Parent.Framework.UITicker)
local UIComponentBase = require(script.Parent.UIComponentBase)

local GPWobbleCard = setmetatable({}, { __index = UIComponentBase })
GPWobbleCard.__index = GPWobbleCard

-- PRIME on purpose: coprime with every common column count (2..6), so no row of
-- a grid can land two neighbours on the same breathing phase and no two rows
-- can resynchronise. 7 also keeps neighbours visibly apart (~51 degrees) rather
-- than merely different.
local PHASE_BUCKETS = 7
-- THE CAP (a law, not a default): idle scale never exceeds 2% peak-to-peak.
local MAX_BREATHE_SCALE = 0.02
local DEFAULT_BREATHE_SECONDS = 3
-- Exponential approach rate for the tilt, in "per second" — frame-rate
-- independent via 1 - exp(-rate * dt). A FALLBACK, not the feel: a pack naming
-- DialectTokens.motion.tiltEasePerSec owns how eagerly its cards lean (the same
-- token GLAngularButtonComponent reads out of its own dialect).
local TILT_EASE_PER_SEC = 9

-- ---- the ONE shared ticker ----------------------------------------------

local cards: { [any]: boolean } = {}
local cardCount = 0
local stopTicker: (() -> ())? = nil

local function step(dt: number, now: number)
	-- Removing the CURRENT key during iteration is allowed in Luau (only
	-- additions are undefined), and prune/unregister only ever removes the key
	-- it is standing on.
	for card in cards do
		card:_Ambient(dt, now)
	end
end

local function register(card: any)
	if cards[card] then
		return
	end
	cards[card] = true
	cardCount += 1
	if not stopTicker then
		-- Deliberately UNBOUND: this handler outlives any single card, and
		-- binding it to whichever card registered first would kill every other
		-- card's motion when that one died. The refcount below is what stops
		-- it, and the per-card root binding is what feeds the refcount.
		stopTicker = UITicker.Register(step)
	end
end

local function unregister(card: any)
	if not cards[card] then
		return
	end
	cards[card] = nil
	cardCount -= 1
	if cardCount <= 0 and stopTicker then
		local stop = stopTicker
		stopTicker = nil
		stop() -- idempotent; UITicker tolerates removal mid-dispatch
	end
end

-- Test observability: how many wrappers the shared handler is driving.
function GPWobbleCard.LiveCardCount(): number
	return cardCount
end

-- ---- tokens --------------------------------------------------------------

local function motionTokens(theme: Types.UITheme?): { [string]: any }?
	if not theme then
		return nil
	end
	local dialects = theme.DialectTokens
	return if dialects then dialects.motion else nil
end

local function motionNumber(theme: Types.UITheme?, key: string, fallback: number): number
	local tokens = motionTokens(theme)
	local value = if tokens then tokens[key] else nil
	return if type(value) == "number" then value else fallback
end

-- ---- component -----------------------------------------------------------

function GPWobbleCard.new()
	local self = UIComponentBase.new("GPWobbleCard")
	self._phase = 0
	self._tiltNorm = 0
	self._hovered = false
	self._breatheAmp = 0
	self._breatheSeconds = DEFAULT_BREATHE_SECONDS
	self._tiltDegrees = 0
	self._tiltEase = TILT_EASE_PER_SEC
	return setmetatable(self, GPWobbleCard)
end

function GPWobbleCard:_Build(props: Types.UIComponentProps)
	local root = self.Root
	root.BackgroundTransparency = 1
	-- NOT ClipsDescendants: the card tilts, and clipping is axis-aligned — a
	-- clipping wrapper would shave the tilted corners it exists to show off.

	-- CARD child: carries the scale and the rotation. Centre-anchored so both
	-- pivot in place and the rotated corners overhang the root's rectangular
	-- footprint without reflowing a single neighbour. Transparent: this wrapper
	-- paints nothing, so it can never fight the surface it is wrapping (and can
	-- never introduce the pure white UIStyler.Frame is born with).
	local card = UIStyler.Frame("Card")
	card.BackgroundTransparency = 1
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromScale(1, 1)
	card.Parent = root
	self.Content = card
	self._card = card
	self:_UseScaleTarget(card)
	self._scaleInstance = self:_EnsureScale()

	local adopt = props.adopt
	if adopt and typeof(adopt) == "Instance" then
		(adopt :: Instance).Parent = card
	end

	-- Phase from LayoutOrder: stable across rebuilds, spread across a prime
	-- bucket count so a grid never breathes in lockstep (see header).
	self._phase = ((props.layoutOrder or 0) % PHASE_BUCKETS) / PHASE_BUCKETS * 2 * math.pi

	-- Hover on a plain Frame: MouseEnter/MouseLeave/MouseMoved fire on any
	-- GuiObject, so the wrapper never needs to become a button and never
	-- swallows a click meant for the content inside it.
	self:_Connect(root.MouseEnter, function()
		self._hovered = true
	end)
	self:_Connect(root.MouseLeave, function()
		self._hovered = false
		self._tiltNorm = 0
	end)
	self:_Connect(root.MouseMoved, function(x: number, _y: number)
		-- X only: the topbar inset shifts event Y, never X, so the norm is
		-- inset-proof. -1 at the left edge, +1 at the right.
		local width = root.AbsoluteSize.X
		if width > 0 then
			self._tiltNorm = math.clamp(((x - root.AbsolutePosition.X) / width) * 2 - 1, -1, 1)
		end
	end)

	-- Reduce-motion: cached from the Root's attribute; a live flip lands next
	-- tick (the handler snaps to the static pose).
	self._reduceMotion = root:GetAttribute("ReduceMotion") == true
	self:_Connect(root:GetAttributeChangedSignal("ReduceMotion"), function()
		self._reduceMotion = root:GetAttribute("ReduceMotion") == true
	end)

	-- The per-card half of the "bound to the root" contract: leaving the
	-- DataModel deregisters from the shared handler immediately, without
	-- waiting for the step's prune. (UIComponentBase also wires Root.Destroying
	-- to Destroy, which deregisters again — both paths are idempotent.)
	self:_Connect(root.AncestryChanged, function(_child, parent)
		if not parent then
			unregister(self)
		elseif not self._destroyed and (self._breatheAmp > 0 or self._tiltDegrees > 0) then
			-- Re-parented back in (a screen moving its content between layers).
			-- Guarded on the tokens so a pack with no motion namespace can never
			-- be re-registered into a handler it would only park inside.
			register(self)
		end
	end)
end

-- Park the card at its static pose. Called whenever motion is off (no tokens,
-- reduce-motion, off-screen) so a card never freezes mid-breath.
function GPWobbleCard:_Park()
	local card = self._card :: Frame
	local scale = self._scaleInstance :: UIScale
	if scale.Scale ~= 1 then
		scale.Scale = 1
	end
	if card.Rotation ~= 0 then
		card.Rotation = 0
	end
end

-- Per-frame ambient choreography, driven by the ONE shared handler. Gated hard:
-- dead root = prune, no motion tokens = park, reduce-motion or off-screen =
-- park (the frugal ambient rule, doc 5.4).
function GPWobbleCard:_Ambient(dt: number, now: number)
	local root = self.Root
	if self._destroyed or root.Parent == nil then
		unregister(self)
		return
	end
	if self._breatheAmp <= 0 and self._tiltDegrees <= 0 then
		self:_Park()
		return
	end
	if self._reduceMotion or not UIChrome.IsOnScreen(root) then
		self:_Park()
		return
	end

	if self._breatheAmp > 0 then
		-- Centred on 1 so the card spends equal time above and below its
		-- authored size; amplitude is HALF the peak-to-peak cap.
		local omega = 2 * math.pi / math.max(self._breatheSeconds, 0.1)
		local scale = self._scaleInstance :: UIScale
		scale.Scale = 1 + self._breatheAmp * 0.5 * math.sin(now * omega + self._phase)
	end

	if self._tiltDegrees > 0 then
		local card = self._card :: Frame
		local target = if self._hovered then self._tiltNorm * self._tiltDegrees else 0
		-- Frame-rate-independent exponential approach: the card leans toward
		-- the pointer and eases home when it leaves.
		local rate = self._tiltEase or TILT_EASE_PER_SEC
		card.Rotation += (target - card.Rotation) * (1 - math.exp(-rate * dt))
	end
end

-- Nothing to paint — this wrapper owns no surface. What _Style DOES do is
-- re-read the motion tokens, which is why it exists: a live theme swap changes
-- the breathe amplitude and the tilt magnitude, and a pack with no motion
-- namespace zeroes both and drops the card out of the shared handler entirely
-- (the dialect-scoping rule: a pack pays only for the dialects it declares).
function GPWobbleCard:_Style(theme: Types.UITheme)
	local props = self.Props

	local breathe = motionNumber(theme, "breatheScale", 0)
	if props.breathe == false then
		breathe = 0
	end
	-- THE CAP: a pack may go subtler, never louder.
	self._breatheAmp = math.clamp(breathe, 0, MAX_BREATHE_SCALE)
	self._breatheSeconds = motionNumber(theme, "breatheSeconds", DEFAULT_BREATHE_SECONDS)

	local tilt = motionNumber(theme, "tiltSm", 0)
	if props.tilt == false then
		tilt = 0
	end
	self._tiltDegrees = math.max(tilt, 0)
	-- Positive-only: a zero or negative rate would freeze the lean or invert it.
	self._tiltEase = math.max(motionNumber(theme, "tiltEasePerSec", TILT_EASE_PER_SEC), 0.01)

	if self._breatheAmp > 0 or self._tiltDegrees > 0 then
		register(self)
	else
		unregister(self)
		self:_Park()
	end
end

function GPWobbleCard:Destroy()
	unregister(self)
	UIComponentBase.Destroy(self)
end

return GPWobbleCard
