--!strict
-- Base class every concrete component extends. It owns the lifecycle that all
-- components share so specializations only describe their own structure:
--
--   * Create(parent, props) — subclasses override _Build to add GuiObjects.
--   * ApplyTheme(theme)     — subclasses override _Style to paint tokens.
--   * PlayAnimation(name)   — a shared animation library (Appear/Disappear/
--                             HoverOn/HoverOff/Press/Release/Pulse) driven by
--                             the active theme's TweenInfos and effect scales.
--   * Destroy()             — cancels tweens, drops connections, unregisters
--                             from the theme controller, destroys instances.
--
-- Components auto-register with UIThemeController on Create and get ApplyTheme
-- called again on every live theme swap — that is what makes the whole UI
-- re-skin (and the in-game editor's live preview) work with no per-component
-- wiring. Registration is injected (SetThemeController) to avoid a require
-- cycle between components and the controller.

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local ThemeShape = require(script.Parent.Parent.ThemeShape)
local UISignal = require(script.Parent.Parent.UISignal)

local UIComponentBase = {}
UIComponentBase.__index = UIComponentBase

-- Injected once at boot by the ClientHandler. Nil-safe so components can be
-- built in isolation (e.g. unit/smoke tests) without a controller present.
local themeController: any = nil
function UIComponentBase.SetThemeController(controller: any)
	themeController = controller
end

-- Optional UI sound controller (also injected at boot). Buttons play Hover /
-- Click through it; nil-safe so sound is entirely optional.
local soundController: any = nil
function UIComponentBase.SetSoundController(controller: any)
	soundController = controller
end

function UIComponentBase:_PlaySound(event: string)
	if soundController then
		soundController:Play(event)
	end
end

export type Component = typeof(setmetatable(
	{} :: {
		Root: GuiObject,
		Props: Types.UIComponentProps,
		Theme: Types.UITheme?,
		Destroyed: typeof(UISignal.new()),
		_connections: { RBXScriptConnection },
		_tweens: { Tween },
		_baseSize: UDim2,
		_themeRegistration: any,
	},
	UIComponentBase
))

-- Subclasses call this from their own .new to get a configured instance, then
-- override _Build/_Style. `className` names the root frame for debugging.
function UIComponentBase.new(className: string): Component
	local self = setmetatable({}, UIComponentBase)
	self.Props = {}
	self.Theme = nil
	self.Destroyed = UISignal.new()
	self._destroyed = false
	self._connections = {}
	self._tweens = {}
	self._styledOnce = false
	self._scale = nil
	self._scaleTarget = nil
	self._hoverFill = nil
	self._hoverRestColor = nil
	self._baseSize = UDim2.fromScale(1, 1)
	self.Root = UIStyler.Frame(className)
	self.Root.BackgroundTransparency = 1
	return self :: any
end

-- ---- lifecycle ---------------------------------------------------------

function UIComponentBase:Create(parent: Instance?, props: Types.UIComponentProps?): GuiObject
	if props then
		self.Props = props
	end
	local p = self.Props

	if p.size then
		self.Root.Size = p.size
	end
	self._baseSize = self.Root.Size
	if p.position then
		self.Root.Position = p.position
	end
	if p.anchorPoint then
		self.Root.AnchorPoint = p.anchorPoint
	end
	if p.layoutOrder then
		self.Root.LayoutOrder = p.layoutOrder
	end

	-- Subclass builds its inner GuiObjects.
	self:_Build(p)

	if parent then
		self.Root.Parent = parent
	end

	-- Subscribe to live theme changes; apply the current theme immediately.
	if themeController then
		self._themeRegistration = themeController:RegisterComponent(self)
		self:ApplyTheme(themeController:GetTheme())
	end

	-- Safety net for style rebuilds: when a screen's shell is destroyed out
	-- from under its components (UIScreenBase:_ResetShell), each component
	-- unregisters itself instead of leaking a theme subscription per rebuild.
	self._connections[#self._connections + 1] = self.Root.Destroying:Connect(function()
		if not self._destroyed then
			self:Destroy()
		end
	end)

	return self.Root
end

-- Override in subclasses. Default is a no-op container.
function UIComponentBase:_Build(_props: Types.UIComponentProps) end

-- Override in subclasses to paint theme tokens onto instances built in _Build.
function UIComponentBase:_Style(_theme: Types.UITheme) end

function UIComponentBase:ApplyTheme(theme: Types.UITheme?)
	if not theme then
		return
	end
	self.Theme = theme
	self:_Style(theme)
	-- Apply (or clear) the theme's optional text outline on EVERY text-bearing
	-- descendant in one place, so a theme's "chunky outlined text" look — and the
	-- legibility it buys for light-coloured text on light fills — lands on every
	-- component's labels without each _Style having to opt each label in. Passing
	-- theme.TextOutline (which may be nil) means switching to a non-outline theme
	-- disables the strokes we added, so the effect is fully theme-gated.
	for _, d in self.Root:GetDescendants() do
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			UIStyler.ApplyThemeOutline(d, theme.TextOutline)
		end
	end
	-- After the first paint, later theme changes are allowed to cross-fade.
	self._styledOnce = true
end

-- Apply a color to a property. The FIRST time a component is themed we set it
-- directly so the correct color is guaranteed to land even if a tween is later
-- interrupted; subsequent theme swaps cross-fade for the polished feel. This is
-- why components never tween color straight from the default white.
function UIComponentBase:_SetColor(instance: Instance, prop: string, color: Color3)
	if self._styledOnce and self.Theme then
		self:_Tween(instance, self.Theme.Animations.ThemeSwap, { [prop] = color })
	else
		(instance :: any)[prop] = color
	end
end

-- ---- shared animation library -----------------------------------------

-- Hover/press/appear animate a UIScale on a target that defaults to the Root
-- but is usually an inner "surface" frame (see _UseScaleTarget). Scaling a
-- UIScale is purely visual and centered: it does NOT change the Root's Size,
-- so the element never reflows its list/grid neighbours or "leaves" its cell —
-- it just pops in place, the way a polished UI should.
function UIComponentBase:_EnsureScale(): UIScale
	if not self._scale then
		local target = self._scaleTarget or self.Root
		local scale = target:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		scale.Parent = target
		self._scale = scale
	end
	return self._scale
end

-- Subclasses call this from _Build to pop an inner surface instead of the Root.
function UIComponentBase:_UseScaleTarget(target: GuiObject)
	self._scaleTarget = target
end

-- Register the instance whose fill carries the hover white-lerp (doc §5.1:
-- HOVER_IN lerps the fill 12% toward white; the rest colour is re-captured
-- on every hover because buttons recolour at runtime). Components call this
-- from _Build with their main fill frame.
function UIComponentBase:_SetHoverFill(instance: GuiObject)
	self._hoverFill = instance
end

-- The §5.1 motion kit. All springs, no fades: pop in (0.82 → 1 Back Out),
-- hover 1.05 + fill toward white (0.12s Back Out in, 0.15s Quad Out back),
-- press squash 0.93 (0.07s Quad Out), pulse 1.14 spike then Back-Out settle.
function UIComponentBase:PlayAnimation(name: string)
	local theme = self.Theme
	if not theme then
		return
	end
	local motion = theme.Motion
	local scale = self:_EnsureScale()
	local hoverFill = self._hoverFill :: GuiObject?

	if name == "Appear" then
		-- Scale-pop only. We deliberately do NOT animate descendant transparency:
		-- doing so would fight the themed transparency values and, if
		-- interrupted, leave the whole component translucent/grey.
		self.Root.Visible = true
		scale.Scale = motion.PopFromScale
		self:_Tween(scale, motion.PopIn, { Scale = 1 })
	elseif name == "Disappear" then
		self:_Tween(scale, theme.Animations.Disappear, { Scale = 0.9 })
	elseif name == "HoverOn" then
		self:_Tween(scale, motion.HoverIn, { Scale = motion.HoverScale })
		if hoverFill then
			self._hoverRestColor = hoverFill.BackgroundColor3
			self:_Tween(hoverFill, motion.HoverIn, {
				BackgroundColor3 = hoverFill.BackgroundColor3:Lerp(Color3.new(1, 1, 1), motion.HoverFillLerp),
			})
		end
	elseif name == "HoverOff" then
		self:_Tween(scale, motion.HoverOut, { Scale = 1 })
		if hoverFill and self._hoverRestColor then
			self:_Tween(hoverFill, motion.HoverOut, { BackgroundColor3 = self._hoverRestColor })
			self._hoverRestColor = nil
		end
		self:_RaisedPressDepth(0)
	elseif name == "Press" then
		self:_Tween(scale, motion.PressIn, { Scale = motion.PressScale })
		-- Raised3D presses "into" the surface: nudge the scale target down.
		self:_RaisedPressDepth(ThemeShape.Resolve(theme).Depth)
	elseif name == "Release" then
		self:_Tween(scale, motion.HoverIn, { Scale = motion.HoverScale })
		self:_RaisedPressDepth(0)
	elseif name == "Pulse" then
		local pulse = self:_Tween(scale, motion.PulseUp, { Scale = motion.PulseScale })
		pulse.Completed:Once(function()
			if self.Root.Parent then
				self:_Tween(scale, motion.PulseSettle, { Scale = 1 })
			end
		end)
	end
end

-- For Raised3D components, shift the scale target down by `depth` px on press so
-- the button visibly depresses toward its shadow, then back to 0 on release.
-- No-op when there's no depth (Flat/Bubbly), and only when a surface is used.
function UIComponentBase:_RaisedPressDepth(depth: number)
	local target = self._scaleTarget
	if not target or not self.Theme then
		return
	end
	if ThemeShape.Resolve(self.Theme).Style ~= "Raised3D" then
		return
	end
	self:_Tween(target, self.Theme.Animations.Press, {
		Position = UDim2.new(0.5, 0, 0.5, depth),
	})
end

-- Scale a UDim2 about its center by multiplying its offset+scale magnitudes.
function UIComponentBase:_ScaledSize(factor: number): UDim2
	local base = self._baseSize
	return UDim2.new(
		base.X.Scale * factor,
		base.X.Offset * factor,
		base.Y.Scale * factor,
		base.Y.Offset * factor
	)
end

-- ---- tween / transparency helpers -------------------------------------

function UIComponentBase:_Tween(instance: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local tween = UIStyler.Tween(instance, info, goal)
	table.insert(self._tweens, tween)
	return tween
end

-- ---- connection bookkeeping -------------------------------------------

function UIComponentBase:_Connect(event: RBXScriptSignal, handler: (...any) -> ())
	table.insert(self._connections, event:Connect(handler))
end

-- Wire the universal hover/press feel + click callback onto any GuiButton.
-- No sounds here: the ONE global UI click (doc §6) is auto-hooked onto
-- Activated of every GuiButton by UISoundController, and there is no hover
-- sound in the Pottery language. AutoButtonColor stays off everywhere —
-- colour+scale is the only feedback story.
-- Every tap answers (doc §11.1): a disabled button still plays the full
-- press juice; only the onClick callback is withheld.
function UIComponentBase:_BindInteractions(button: GuiButton)
	button.AutoButtonColor = false
	self:_Connect(button.MouseEnter, function()
		if self.Props.enabled ~= false then
			self:PlayAnimation("HoverOn")
		end
	end)
	self:_Connect(button.MouseLeave, function()
		self:PlayAnimation("HoverOff")
	end)
	self:_Connect(button.MouseButton1Down, function()
		self:PlayAnimation("Press")
	end)
	self:_Connect(button.MouseButton1Up, function()
		self:PlayAnimation("Release")
	end)
	self:_Connect(button.Activated, function()
		if self.Props.enabled ~= false and self.Props.onClick then
			self.Props.onClick()
		end
	end)
end

function UIComponentBase:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	for _, tween in self._tweens do
		tween:Cancel()
	end
	table.clear(self._tweens)
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
	if self._themeRegistration then
		self._themeRegistration:Disconnect()
		self._themeRegistration = nil
	end
	self.Destroyed:Fire()
	self.Destroyed:Clear()
	if self.Root then
		self.Root:Destroy()
	end
end

return UIComponentBase
