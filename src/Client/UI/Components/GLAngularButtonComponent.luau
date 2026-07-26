--!strict
-- GLAngularButtonComponent — the Gurren Lagann slanted comic CTA: a cel-flat
-- HEAT sticker slapped a few degrees off true, 3px ink outline, Bangers shout
-- label, hard-offset sticker shadow. Extends UIComponentBase, overriding only
-- _Build/_Style (+ a PlayAnimation gate and a Destroy for its ticker/shadow).
--
-- THE 0.4 BOUNDARY: Styling owns static appearance and state looks — flipped
-- through tags via StateDriver and the GL theme's StyleRules GuiState bands
-- (inert until the engine activates styling application; the imperative theme
-- path renders meanwhile). Luau + UITicker own everything sequenced,
-- continuous, or non-styling-triggered: sfx intent, idle drift, tilt
-- parallax. A behavior implemented on BOTH sides is a bug.
--
-- DUAL-PATH BRIDGE (hover/press/disabled appearance): the GL theme authors
-- ".UIButton:Hover/:Press" and ".UIButton.UIDisabled" bands against the same
-- Motion/Colors tokens this file reads. Because styling application is INERT
-- today (Style/Capabilities probes the running engine), the imperative
-- fallback renders the state looks meanwhile: hover fill lerp + disabled dim
-- via UIComponentBase.PlayAnimation/_Style. The moment Capabilities
-- .StylingActive resolves true the imperative FILL paths yield (checked at
-- animation/style time, so a late flip is honoured) and the sheet bands own
-- state colour — scale/rotation juice stays Luau forever, it was never on
-- the styling side.
--
-- NO-SKEW ANNOTATION: Roblox has no skew transform. The slant here is the
-- WHOLE-ELEMENT Rotation technique — the tilt lives on the ART child
-- (DialectTokens.comic.slantDeg), while the transparent root keeps its
-- rectangular, unrotated footprint, so list/grid layout never reflows and
-- the tilted sticker just overhangs its cell like cut paper.
--
-- HIT-TARGET A11Y RULE: the UNROTATED root bounds are the button. A full-size
-- transparent TextButton ("Hit") sits at root level, so gamepad selection
-- boxes and touch targets stay rectangular and predictable on slanted
-- chrome; art rotates inside, input does not.
--
-- REDUCE-MOTION: a ReduceMotion boolean attribute on the module root kills
-- the ambient choreography — drift/parallax collapse to the static pose.
-- Off-screen (UIChrome.IsOnScreen) the ticker handler does zero work. There
-- is no blocking ceremony here: the Hit target is always live (disabled only
-- withholds onClick, per the "every tap answers" house rule).
--
-- BUDGETS: exactly ONE UITicker.Register (bound to the Root for
-- auto-cleanup; never a RunService connection) and ONE sticker shadow per
-- instance, budget-counted through UIChrome.Shadow → Capabilities
-- .RegisterShadow and Released on restyle/Destroy. No pooled repeats exist
-- in this module. 100x Create/Destroy = zero connection or budget growth.
--
-- Props: { text (or textKey), onClick, enabled } — plus the shared layout
-- props (size/position/anchorPoint/layoutOrder) from UIComponentBase.

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local TextConfig = require(script.Parent.Parent.Config.TextConfig)
local UITicker = require(script.Parent.Parent.Framework.UITicker)
local StateDriver = require(script.Parent.Parent.StyleKit.StateDriver)
local Tags = require(script.Parent.Parent.StyleKit.Tags)
local Capabilities = require(script.Parent.Parent.StyleKit.Capabilities)
local UIComponentBase = require(script.Parent.UIComponentBase)

-- The ART frame's rest pose (centered on the root); drift modulates around it.
local REST_POSITION = UDim2.fromScale(0.5, 0.5)

local GLAngularButtonComponent = setmetatable({}, { __index = UIComponentBase })
GLAngularButtonComponent.__index = GLAngularButtonComponent

function GLAngularButtonComponent.new()
	local self = UIComponentBase.new("GLAngularButton")
	return setmetatable(self, GLAngularButtonComponent)
end

-- The GL comic dialect token namespace, or nil under a pack that doesn't
-- speak it (then: no slant, no drift — the component stays a plain flat CTA
-- and pays nothing, per the dialect-scoping rule).
local function comicTokens(theme: Types.UITheme?): { [string]: any }?
	if not theme then
		return nil
	end
	local dialects = theme.DialectTokens
	return if dialects then dialects.comic else nil
end

function GLAngularButtonComponent:_Build(props: Types.UIComponentProps)
	local root = self.Root
	root.BackgroundTransparency = 1
	if not props.size then
		-- Comic CTA runs bigger than the arcade 180×48 default so the Bangers
		-- shout breathes (layout default, not a theme value).
		root.Size = UDim2.new(0, 220, 0, 56)
		self._baseSize = root.Size
	end

	-- ART frame: carries every visual and the slant. Whole-element Rotation
	-- (no skew exists in Roblox — see header); center-anchored so the tilt
	-- pivots in place and the rotated corners overhang the root's rectangular
	-- footprint without ever reflowing layout neighbours. Rotation itself is
	-- painted in _Style from DialectTokens.comic.slantDeg.
	local art = UIStyler.Frame("Art")
	art.BackgroundTransparency = 0
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = REST_POSITION
	art.Size = UDim2.fromScale(1, 1)
	art.ZIndex = 2
	art.Parent = root
	self._art = art
	-- Hover/press scale pops the ART, not the root — the footprint stays put.
	self:_UseScaleTarget(art)

	-- Bangers shout label (UIChrome.Text assigns the active display font +
	-- the style's text emphasis). Placeholder size/colour, same pattern as
	-- UIColorFieldComponent: _Style paints the real tokens.
	local label = UIChrome.Text("Label", 24, Color3.new(1, 1, 1))
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 3
	-- RichText off: TextTruncate is unreliable on RichText labels (see
	-- UIListRowComponent), and a shout label never needs markup.
	label.RichText = false
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = TextConfig.Resolve(props.textKey or props.text)
	label.Parent = art
	self._label = label

	-- Hit target: the UNROTATED root is the button (a11y rule, see header).
	-- Under ZIndexBehavior.Sibling the higher root-level sibling paints its
	-- whole subtree on top, so Hit sits BELOW the art (ZIndex 1 vs 2) —
	-- Art is a plain Frame (never Active), so Hit still receives every
	-- click/tap/gamepad-A across its full rectangular bounds.
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

	-- Shared hover/press/click juice (the imperative half of the bridge).
	self:_BindInteractions(button)

	-- Luau side of the boundary: sfx INTENT + parallax bookkeeping. The
	-- active sound pack decides policy (Pottery: Hover is deliberately
	-- silent; the ONE global click is auto-hooked on Activated by
	-- UISoundController — no click wiring here).
	self._hovered = false
	self._tiltNorm = 0
	self:_Connect(button.MouseEnter, function()
		self._hovered = true
		if self.Props.enabled ~= false then
			self:_PlaySound("Hover")
		end
	end)
	self:_Connect(button.MouseLeave, function()
		self._hovered = false
		self._tiltNorm = 0
	end)
	self:_Connect(button.MouseMoved, function(x: number, _y: number)
		-- X only: the topbar inset shifts event Y, never X, so the norm is
		-- inset-proof. -1 at the left edge, +1 at the right.
		local width = root.AbsoluteSize.X
		if width > 0 then
			self._tiltNorm = math.clamp(((x - root.AbsolutePosition.X) / width) * 2 - 1, -1, 1)
		end
	end)

	-- Reduce-motion: cached from the module root's attribute; a live flip
	-- lands next tick (the handler snaps to the static pose).
	self._reduceMotion = root:GetAttribute("ReduceMotion") == true
	self:_Connect(root:GetAttributeChangedSignal("ReduceMotion"), function()
		self._reduceMotion = root:GetAttribute("ReduceMotion") == true
	end)

	-- THE one UITicker handler of this module: idle drift + tilt parallax.
	-- Bound to the root so destruction auto-unregisters (Destroy also stops
	-- it explicitly, idempotently). Random phase desyncs sibling stickers.
	self._driftPhase = math.random() * 2 * math.pi
	self._stopDrift = UITicker.Register(function(dt: number, now: number)
		self:_Ambient(dt, now)
	end, root)
end

-- Per-frame ambient choreography (Luau side of the 0.4 boundary): the
-- ±idleDriftPx circular sticker float and the pointer-parallax tilt around
-- slantDeg. Gated hard: no comic tokens = no work; reduce-motion = static
-- pose; off-screen = nothing (the frugal ambient rule).
function GLAngularButtonComponent:_Ambient(dt: number, now: number)
	local theme = self.Theme :: Types.UITheme?
	if not theme then
		return
	end
	local comic = comicTokens(theme)
	if not comic then
		return -- non-comic pack: _Style already parked the static pose
	end
	local art = self._art :: Frame
	local slant: number = comic.slantDeg or 0

	if self._reduceMotion then
		-- Continuous choreography collapses to the instant final state.
		if art.Position ~= REST_POSITION then
			art.Position = REST_POSITION
		end
		if art.Rotation ~= slant then
			art.Rotation = slant
		end
		return
	end
	if not UIChrome.IsOnScreen(self.Root) then
		return
	end

	-- Idle drift: one slow circle of radius idleDriftPx (a single sine pair —
	-- well under the 6px shake cap; this is a float, not a shake).
	local amp: number = comic.idleDriftPx or 0
	local hz: number = comic.idleDriftHz or 0
	if amp > 0 and hz > 0 then
		local t = now * hz * 2 * math.pi + self._driftPhase
		art.Position = UDim2.new(0.5, math.cos(t) * amp, 0.5, math.sin(t) * amp)
	end

	-- Tilt parallax: while hovered, the pointer's X-position leans the
	-- sticker up to ±Motion.BigHoverTilt degrees around the slant; released,
	-- it eases home. Frame-rate-independent exponential approach.
	local target = slant
	if self._hovered then
		target = slant + self._tiltNorm * theme.Motion.BigHoverTilt
	end
	local rate: number = comic.tiltEasePerSec or 0
	if rate > 0 then
		art.Rotation += (target - art.Rotation) * (1 - math.exp(-rate * dt))
	else
		art.Rotation = target
	end
end

-- DUAL-PATH BRIDGE gate: once native styling actually applies, the GL
-- ":Hover"/":Press" bands own the fill colour — the imperative hover fill
-- lerp yields (checked per-hover, so a late Capabilities flip is honoured).
-- The scale juice below it stays Luau: it was never authored on the styling
-- side, so there is nothing to double up.
function GLAngularButtonComponent:PlayAnimation(name: string)
	if name == "HoverOn" then
		self._hoverFill = if Capabilities.StylingActive then nil else self._art
	end
	UIComponentBase.PlayAnimation(self, name)
end

-- Imperative paint (authoritative while styling application is inert): the
-- same tokens the GL StyleRules name, expressed once per side on purpose.
function GLAngularButtonComponent:_Style(theme: Types.UITheme)
	local art = self._art :: Frame
	local label = self._label :: TextLabel
	local button = self._button :: TextButton
	local enabled = self.Props.enabled ~= false

	-- State surface: the sole tag mutator (idempotent). The styled
	-- ".UIButton.UIDisabled" band reads this; so does any auditor.
	StateDriver.Set(button, Tags.Modifier.Disabled, not enabled)
	button.Selectable = enabled -- disabled drops out of gamepad nav
	button.Active = true -- every tap still answers (press juice always plays)

	-- Static pose: the whole-element slant (no skew — header annotation).
	-- Packs without comic tokens park the art straight; the ticker then
	-- early-outs, so nothing fights this write.
	local comic = comicTokens(theme)
	local slant: number = if comic then comic.slantDeg or 0 else 0
	art.Rotation = slant
	art.Position = REST_POSITION

	-- Fill: Colors.Primary; disabled dims to Colors.Disabled — the SAME
	-- token the ".UIButton.UIDisabled" band names. Imperative side yields
	-- once styling application is live (dual-path bridge, header).
	local fill = theme.Colors.Primary
	if not enabled and not Capabilities.StylingActive then
		fill = theme.Colors.Disabled
	end
	art.BackgroundTransparency = 0
	self:_SetColor(art, "BackgroundColor3", fill)
	-- If we're mid-hover the base class restores its captured rest colour on
	-- HoverOff — retarget it so a restyle/SetEnabled mid-hover restores the
	-- NEW fill instead of snapping back to the pre-restyle colour (the
	-- UIToggleComponent house pattern).
	if self._hoverRestColor then
		self._hoverRestColor = fill
	end

	-- Chrome through policy, never per-call: GL = hard 0px corners + the
	-- 3px comic ink stroke (Chrome.StrokeThickness/black); other packs get
	-- their own stroke language from the same intent.
	if self._corner then
		self._corner:Destroy()
	end
	local corner = UIChrome.Corner("Arcade", "Button")
	corner.Parent = art
	self._corner = corner

	if self._stroke then
		self._stroke:Destroy()
	end
	local stroke = UIChrome.Stroke(theme, "Arcade", "Button")
	stroke.Parent = art
	self._stroke = stroke

	-- Sticker shadow on the ART frame (it follows the slant since UIShadow
	-- offsets in the element's rotated frame): only packs declaring native
	-- shadow tokens pay (UIChrome.Panel precedent). Budget-counted; the old
	-- handle is Released (not leaked) on every restyle.
	if self._shadowHandle then
		self._shadowHandle:Release()
		self._shadowHandle = nil
	end
	if theme.EffectShadows then
		local _, handle = UIChrome.Shadow(theme, "sm", art)
		self._shadowHandle = handle
	end

	-- The shout label: the style's Button font (GL: Bangers) + the style's
	-- text emphasis, re-asserted AFTER the colour so a styled glow tracks it.
	label.FontFace = theme.Fonts.Button
	label.TextSize = theme.TextSizes.Button
	label.TextColor3 = if enabled then theme.Colors.TextOnPrimary else theme.Colors.TextSecondary
	UIChrome.TextOutline(label)
end

-- Update the label after construction without rebuilding. An explicit
-- SetText overrides any build-time textKey — otherwise the stale key keeps
-- winning the resolve and the call silently does nothing.
function GLAngularButtonComponent:SetText(text: string?)
	self.Props.text = text
	self.Props.textKey = nil
	local label = self._label :: TextLabel?
	if label then
		label.Text = TextConfig.Resolve(text)
	end
end

-- Flip enabled at runtime: tag + imperative dim both land through _Style.
function GLAngularButtonComponent:SetEnabled(enabled: boolean)
	self.Props.enabled = enabled
	if self.Theme then
		self:_Style(self.Theme)
	end
end

function GLAngularButtonComponent:Destroy()
	if self._stopDrift then
		self._stopDrift() -- idempotent; the root binding also covers this
		self._stopDrift = nil
	end
	if self._shadowHandle then
		self._shadowHandle:Release()
		self._shadowHandle = nil
	end
	UIComponentBase.Destroy(self)
end

return GLAngularButtonComponent
