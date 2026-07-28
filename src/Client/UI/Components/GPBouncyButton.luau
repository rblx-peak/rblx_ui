--!strict
-- GPBouncyButton — the Girly Pop CTA: a petal-cornered pastel chip that
-- SQUASHES on press, STRETCHES on release, and wobbles a degree and a half
-- when you hover it. Extends UIComponentBase, overriding _Build/_Style (+ a
-- PlayAnimation branch and a Destroy for its ticker/shadow).
--
-- Generic and theme-agnostic by construction: every colour, radius, easing,
-- font and motion magnitude is a TOKEN read off the active theme. Under a pack
-- with no Corners table the corner falls back to the uniform radius ladder;
-- under a pack with no DialectTokens.motion the wobble amplitude is zero and
-- the ticker handler does no work. The cuteness is entirely in GirlyPop's
-- token values, not in this file.
--
-- THE 0.4 BOUNDARY: Styling owns static appearance and state LOOKS — the hit
-- target wears UIButton/UIButtonPrimary structurally and flips UIDisabled
-- through StateDriver (the sole tag mutator), so a pack's
-- ".UIButton.UIDisabled" band can dress it once the engine activates styling
-- application; the imperative paint in _Style renders the same look meanwhile.
-- Luau + UITicker own everything sequenced or continuous: the squash/stretch
-- choreography, the decaying hover wobble, sfx intent and the sparkle hook. No
-- StyleRule mirrors any of that — a behaviour implemented on BOTH sides is a
-- bug.
--
-- SQUASH-STRETCH IS UISCALE, NEVER SIZE. Size is what layout measures: an
-- animated Size would reflow every neighbour in a list or grid on every press.
-- UIScale is purely visual and centred, so the chip pops inside its own cell
-- and nothing moves. UIScale is also UNIFORM — Roblox has no non-uniform
-- transform that layout ignores — so the squash/stretch reads as MAGNITUDE and
-- EASING rather than as a widened silhouette: press collapses to
-- Motion.PressScale on Motion.PressIn (fast, Quad Out — the impact), release
-- overshoots to Motion.PulseScale on Motion.PulseUp and settles back on
-- Motion.PulseSettle (Back Out — the rebound). Those five tokens ARE the
-- squash and stretch; a pack tunes the feel without touching this file.
--
-- HOVER WOBBLE, AND WHY SPAM CANNOT STACK IT: the rotation is a pure function
-- of one clock — amplitude = wobbleDegrees * exp(-decay * t), angle =
-- amplitude * sin(2*pi*hz*t) — so re-entering hover RESTARTS t at 0 instead of
-- adding to anything. There is no accumulator to grow, which means flicking the
-- pointer across the button fifty times produces the same ±wobbleDegrees swing
-- as entering it once. The swing starts at zero (sin(0)) so it never jumps.
--
-- NO-SKEW / NO-CLIP ANNOTATION: Roblox has no skew, so the wobble is
-- whole-element Rotation on the ART child; the transparent root keeps its
-- unrotated rectangular footprint, so gamepad selection boxes and touch targets
-- stay predictable and list/grid layout never reflows. Roblox clipping is
-- axis-aligned and does NOT clip rotated descendants: at ±1.5° the overhang is
-- sub-pixel on a normal chip, but a caller placing this inside a tight
-- ScrollingFrame should either leave a pixel of margin or pass wobble = false.
--
-- REDUCE-MOTION: a ReduceMotion boolean attribute on the Root (or on any
-- ancestor layer that sets it, cached and re-read on change) parks the wobble
-- at the static pose. The press juice is NOT motion decoration — it is the
-- tactile answer to a tap — so it survives; only the ambient wobble stops.
--
-- EVERY TAP ANSWERS (house rule): a disabled button still plays the full
-- squash/stretch and still sparkles. Only the onClick callback is withheld.
--
-- BUDGETS: exactly ONE UITicker.Register (bound to the Root for auto-cleanup;
-- never a RunService connection) and at most ONE UIShadow per instance,
-- budget-counted through Capabilities.RegisterShadow and Released on every
-- restyle and on Destroy. 100x Create/Destroy = zero connection, instance or
-- budget growth.
--
-- Props (plus the shared layout props from UIComponentBase):
--   text / textKey  : label copy, passed through VERBATIM (this pack never
--                     shouts — there is no string.upper in this file)
--   onClick, enabled
--   fillToken       : Colors.* key for the chip fill (default "Primary")
--   wobble          : false disables the hover wobble entirely
--   sfxHover        : UISoundController event name played on hover (nil =
--                     silent; the Pottery pack maps no hover sound anyway)
--   sfxPress        : extra event on Activated. The ONE global UI click is
--                     already auto-hooked onto every GuiButton's Activated by
--                     UISoundController — this is for additional intent only.
--   onSparkle       : (center: Vector2) -> () fired on Activated with the
--                     chip's absolute centre, for celebration art.
--   sparkleEmitter  : anything with a :Burst(center) method (a GPSparkleBurst
--                     instance is the intended one) — duck-typed on purpose so
--                     this module never requires a sibling component.

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local TextConfig = require(script.Parent.Parent.Config.TextConfig)
local UITicker = require(script.Parent.Parent.Framework.UITicker)
local GPLayoutKit = require(script.Parent.Parent.Framework.GPLayoutKit)
local StateDriver = require(script.Parent.Parent.StyleKit.StateDriver)
local Tags = require(script.Parent.Parent.StyleKit.Tags)
local UIComponentBase = require(script.Parent.UIComponentBase)

local GPBouncyButton = setmetatable({}, { __index = UIComponentBase })
GPBouncyButton.__index = GPBouncyButton

-- Wobble shape. The AMPLITUDE is a pack token (DialectTokens.motion
-- .wobbleDegrees); these two describe the decay envelope and are read from the
-- same namespace when a pack bothers to name them, so the constants are
-- fallbacks rather than hardcoded feel.
local WOBBLE_HZ = 3.2
local WOBBLE_DECAY_PER_SEC = 3.4
-- Below this the swing is invisible; the handler parks and stops working.
local WOBBLE_STOP_DEGREES = 0.02
-- The chip runs a touch bigger than the arcade 180x48 default so a rounded
-- display face breathes inside a petal corner (layout default, not a token).
local DEFAULT_SIZE = UDim2.fromOffset(200, 52)

-- The pack's motion namespace, or nil under a pack that doesn't speak it —
-- then there is no wobble at all and the ticker early-outs, per the
-- dialect-scoping rule (a pack pays only for the dialects it declares).
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

function GPBouncyButton.new()
	local self = UIComponentBase.new("GPBouncyButton")
	return setmetatable(self, GPBouncyButton)
end

function GPBouncyButton:_Build(props: Types.UIComponentProps)
	local root = self.Root
	root.BackgroundTransparency = 1
	if not props.size then
		root.Size = DEFAULT_SIZE
		self._baseSize = root.Size
	end

	-- ART frame: carries the fill, the corner, the stroke, the shadow and the
	-- wobble. Centre-anchored so the rotation pivots in place and the rotated
	-- corners overhang the root's rectangular footprint without reflowing
	-- anything.
	--
	-- Born TRANSPARENT, never painted here: UIStyler.Frame's BackgroundColor3
	-- default is PURE WHITE, which this pack forbids outright, and _Build has no
	-- theme to paint from (it runs before the first ApplyTheme). A transparent
	-- frame renders nothing, so no white can ever reach a screen; _Style is the
	-- only place in this file that assigns a fill or clears the transparency.
	-- (GPLayoutKit's surface() helper paints a literal at this point instead,
	-- because a static builder is handed the theme up front — a component is
	-- not, which is why the two differ.)
	local art = UIStyler.Frame("Art")
	art.BackgroundTransparency = 1
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.5)
	art.Size = UDim2.fromScale(1, 1)
	art.ZIndex = 2
	art.Parent = root
	self._art = art
	-- The squash/stretch pops the ART, not the root — the footprint stays put.
	self:_UseScaleTarget(art)

	-- Display face label, born fully transparent for the same reason the art is:
	-- UIStyler.TextLabel's TextColor3 default is pure white, and every sibling
	-- component in this framework hands its placeholder Color3.new(1, 1, 1)
	-- explicitly — a literal this pack cannot write. _Style assigns the real
	-- token colour AND clears the transparency in one pass.
	local label = UIStyler.TextLabel("Label")
	label.TextTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 3
	-- RichText off: TextTruncate is unreliable on RichText labels (see
	-- UIListRowComponent), and a CTA label never needs markup.
	label.RichText = false
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = TextConfig.Resolve(props.textKey or props.text)
	label.Parent = art
	self._label = label

	-- Hit target: the UNROTATED root is the button. It stays TRANSPARENT for a
	-- second reason beyond a11y — UIStyleEnforcer backstops any SOLID GuiButton
	-- with a BLACK 2px stroke, and this pack forbids pure black on sight. Under
	-- ZIndexBehavior.Sibling the higher root-level sibling (Art, ZIndex 2)
	-- paints its whole subtree above this; Art is a plain Frame and never
	-- Active, so Hit still receives every click/tap/gamepad-A across its full
	-- rectangular bounds.
	local button = Instance.new("TextButton")
	button.Name = "Hit"
	button.BackgroundTransparency = 1
	button.Size = UDim2.fromScale(1, 1)
	button.Text = ""
	button.AutoButtonColor = false
	button.Selectable = true
	button.ZIndex = 1
	button.Parent = root
	self._button = button

	-- Structural identity for the styling side (build-time, never removed).
	StateDriver.Structural(button, Tags.Structural.Button)
	StateDriver.Structural(button, Tags.Structural.ButtonPrimary)

	-- Shared hover/press/click juice + the onClick gate.
	self:_BindInteractions(button)

	-- Wobble bookkeeping and the Luau-side hooks (sfx intent, sparkle).
	self._wobbleT = 0
	self._wobbleActive = false
	self._hovered = false
	self:_Connect(button.MouseEnter, function()
		self._hovered = true
		-- RESTART, never accumulate: this is the whole anti-stacking design.
		self._wobbleT = 0
		self._wobbleActive = true
		local sfx = self.Props.sfxHover
		if sfx and self.Props.enabled ~= false then
			self:_PlaySound(sfx)
		end
	end)
	self:_Connect(button.MouseLeave, function()
		self._hovered = false
		-- Deliberately NOT parked: an interrupted wobble that snaps to zero
		-- reads as a glitch. The envelope keeps decaying and the handler
		-- retires itself when the swing drops under WOBBLE_STOP_DEGREES.
	end)
	self:_Connect(button.Activated, function()
		self:_Sparkle()
		local sfx = self.Props.sfxPress
		if sfx then
			self:_PlaySound(sfx)
		end
	end)

	-- Reduce-motion: cached from the Root's attribute; a live flip lands next
	-- tick (the handler snaps to the static pose).
	self._reduceMotion = root:GetAttribute("ReduceMotion") == true
	self:_Connect(root:GetAttributeChangedSignal("ReduceMotion"), function()
		self._reduceMotion = root:GetAttribute("ReduceMotion") == true
	end)

	-- THE one UITicker handler of this module. Bound to the root so destruction
	-- auto-unregisters (Destroy also stops it explicitly, idempotently).
	self._stopWobble = UITicker.Register(function(dt: number, _now: number)
		self:_Wobble(dt)
	end, root)
end

-- Per-frame ambient choreography (Luau side of the 0.4 boundary). Gated hard:
-- inactive = no work, no motion tokens = no work, reduce-motion or off-screen =
-- the static pose (the frugal ambient rule, doc 5.4).
function GPBouncyButton:_Wobble(dt: number)
	if not self._wobbleActive then
		return
	end
	local art = self._art :: Frame
	local theme = self.Theme :: Types.UITheme?
	local degrees = if self.Props.wobble == false then 0 else motionNumber(theme, "wobbleDegrees", 0)
	if degrees <= 0 or self._reduceMotion or not UIChrome.IsOnScreen(self.Root) then
		if art.Rotation ~= 0 then
			art.Rotation = 0
		end
		self._wobbleActive = false
		return
	end

	self._wobbleT += dt
	local t = self._wobbleT
	local decay = motionNumber(theme, "wobbleDecayPerSec", WOBBLE_DECAY_PER_SEC)
	local hz = motionNumber(theme, "wobbleHz", WOBBLE_HZ)
	local amplitude = degrees * math.exp(-decay * t)
	if amplitude < WOBBLE_STOP_DEGREES then
		art.Rotation = 0
		self._wobbleActive = false
		return
	end
	-- sin(0) = 0: the swing always begins from the rest pose, so a restart
	-- mid-swing eases rather than snapping.
	art.Rotation = amplitude * math.sin(2 * math.pi * hz * t)
end

-- Sparkle hook. Two shapes, both optional and both duck-typed so this module
-- never requires a sibling component: a plain callback, and anything exposing
-- :Burst(center). Fires even when disabled — every tap answers.
function GPBouncyButton:_Sparkle()
	local art = self._art :: GuiObject
	local center = art.AbsolutePosition + art.AbsoluteSize / 2
	local callback = self.Props.onSparkle
	if callback then
		callback(center)
	end
	local emitter = self.Props.sparkleEmitter
	if emitter and typeof(emitter) == "table" and (emitter :: any).Burst then
		(emitter :: any):Burst(center)
	end
end

-- THE SQUASH AND THE STRETCH. Press collapses; release overshoots past rest and
-- settles. Both are pure UIScale on the ART child (never Size — see header),
-- and every magnitude and easing is a Motion token, so a pack retunes the feel
-- without editing this file. Every other animation name delegates to the base.
function GPBouncyButton:PlayAnimation(name: string)
	local theme = self.Theme :: Types.UITheme?
	if not theme then
		return
	end
	local motion = theme.Motion
	if name == "Press" then
		-- Invalidate any rebound still waiting to settle: without this, a stale
		-- Completed callback from the PREVIOUS release fires mid-press and
		-- yanks the scale back to rest while the finger is still down. A mashed
		-- button is the normal case, not the edge case.
		self._releaseToken = (self._releaseToken or 0) + 1
		self:_Tween(self:_EnsureScale(), motion.PressIn, { Scale = motion.PressScale })
		return
	elseif name == "Release" then
		local scale = self:_EnsureScale()
		local rest = if self._hovered then motion.HoverScale else 1
		local token = (self._releaseToken or 0) + 1
		self._releaseToken = token
		local stretch = self:_Tween(scale, motion.PulseUp, { Scale = motion.PulseScale })
		stretch.Completed:Once(function()
			-- Three guards, three real failure modes: a button destroyed
			-- mid-rebound (dead instance), a button unparented mid-rebound, and
			-- a NEWER press or release having superseded this one.
			if self._destroyed or self._releaseToken ~= token or not self.Root.Parent then
				return
			end
			self:_Tween(scale, motion.PulseSettle, { Scale = rest })
		end)
		return
	end
	UIComponentBase.PlayAnimation(self, name)
	if name == "HoverOn" then
		self:_HoverFill(true)
	elseif name == "HoverOff" then
		self:_HoverFill(false)
	end
end

-- The hover lift, done here instead of through UIComponentBase:_SetHoverFill
-- for one reason: the base lerps the fill toward PURE WHITE, and this pack
-- forbids pure white anywhere — including as a lerp target, which on a pastel
-- reads as a washed-out grey-pink rather than a lift. Cream (Colors.Background)
-- is this pack's "white", and lerping toward it keeps the hue warm.
function GPBouncyButton:_HoverFill(on: boolean)
	local theme = self.Theme :: Types.UITheme?
	local art = self._art :: Frame?
	if not theme or not art then
		return
	end
	if on then
		if self.Props.enabled == false then
			return
		end
		self._restFill = art.BackgroundColor3 -- re-capture: fills recolour at runtime
		self:_Tween(art, theme.Motion.HoverIn, {
			BackgroundColor3 = art.BackgroundColor3:Lerp(theme.Colors.Background, theme.Motion.HoverFillLerp),
		})
	elseif self._restFill then
		self:_Tween(art, theme.Motion.HoverOut, { BackgroundColor3 = self._restFill })
		self._restFill = nil
	end
end

-- Imperative paint (authoritative while styling application is inert): the
-- same tokens a pack's StyleRules would name, expressed once per side.
function GPBouncyButton:_Style(theme: Types.UITheme)
	local art = self._art :: Frame
	local label = self._label :: TextLabel
	local button = self._button :: TextButton
	local enabled = self.Props.enabled ~= false

	-- State surface: the sole tag mutator (idempotent). A pack's
	-- ".UIButton.UIDisabled" band reads this; so does any auditor.
	StateDriver.Set(button, Tags.Modifier.Disabled, not enabled)
	button.Selectable = enabled -- disabled drops out of gamepad nav
	button.Active = true -- every tap still answers (press juice always plays)

	local fillToken = self.Props.fillToken
	local fill = (fillToken and (theme.Colors :: any)[fillToken]) or theme.Colors.Primary
	if not enabled then
		fill = theme.Colors.Disabled
	end
	art.BackgroundTransparency = 0
	self:_SetColor(art, "BackgroundColor3", fill)
	-- If we're mid-hover, retarget the captured rest colour so a restyle or a
	-- SetEnabled during hover restores the NEW fill rather than snapping back
	-- to the pre-restyle one (the UIToggleComponent house pattern).
	if self._restFill then
		self._restFill = fill
	end

	-- PETAL CORNERS, alternating by layout order so a ROW of these reads
	-- hand-arranged rather than stamped. CornerSet destroys any stale UICorner
	-- before parenting: CornerRadius alongside per-corner radii — and two
	-- UICorner children — are the same documented-undefined engine behaviour.
	-- Packs without a Corners table fall back to the uniform radius ladder.
	GPLayoutKit.Petal(theme, art, self.Props.layoutOrder or 0)

	-- Soft 2px rounded-join stroke in a DEEPENED TINT OF THE FILL — never
	-- black, never grey. Mitred joins on a 24px petal radius read as a printing
	-- error at this scale, which is why SoftStroke rounds them.
	if self._stroke then
		self._stroke:Destroy()
	end
	self._stroke = GPLayoutKit.SoftStroke(theme, art, fill)

	-- THE HUE-MATCHED SHADOW: colour derived from this chip's OWN fill, so a
	-- rose button casts rose and a matcha button casts sage. Only packs that
	-- declare native shadow tokens pay (the UIChrome.Panel precedent);
	-- budget-counted, and the old handle is RELEASED, never leaked, on every
	-- restyle.
	if self._shadowHandle then
		self._shadowHandle:Release()
		self._shadowHandle = nil
	end
	if theme.EffectShadows then
		self._shadowHandle = GPLayoutKit.Shadow(theme, art, "sm", nil, fill)
	end

	-- Label: the pack's Button face at the Button size. MEASURED CONTRAST —
	-- TextPrimary (warm plum-brown) on rose is 5.15:1 and on matcha 6.39:1,
	-- both clearing the 4.5:1 body minimum; Colors.TextOnPrimary (near-white)
	-- measures 2.14:1 on rose and is never used at this size.
	label.FontFace = theme.Fonts.Button
	label.TextSize = theme.TextSizes.Button
	label.TextColor3 = if enabled then theme.Colors.TextPrimary else theme.Colors.TextSecondary
	label.TextTransparency = 0 -- clears the born-transparent guard (see _Build)
	-- Re-assert the style's text emphasis AFTER the colour so a styled glow
	-- tracks it (this pack sets TextGlowTransparency = 1, i.e. none).
	UIChrome.TextOutline(label)
end

-- Update the label after construction without rebuilding. An explicit SetText
-- overrides any build-time textKey — otherwise the stale key keeps winning the
-- resolve and the call silently does nothing.
function GPBouncyButton:SetText(text: string?)
	self.Props.text = text
	self.Props.textKey = nil
	local label = self._label :: TextLabel?
	if label then
		label.Text = TextConfig.Resolve(text)
	end
end

-- Flip enabled at runtime: tag + imperative dim both land through _Style.
function GPBouncyButton:SetEnabled(enabled: boolean)
	self.Props.enabled = enabled
	if self.Theme then
		self:_Style(self.Theme)
	end
end

function GPBouncyButton:Destroy()
	if self._stopWobble then
		self._stopWobble() -- idempotent; the root binding also covers this
		self._stopWobble = nil
	end
	if self._shadowHandle then
		self._shadowHandle:Release()
		self._shadowHandle = nil
	end
	UIComponentBase.Destroy(self)
end

return GPBouncyButton
