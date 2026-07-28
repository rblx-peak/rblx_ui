--!strict
-- Base class every HUD widget extends. Widgets are the persistent gameplay
-- chrome (health, abilities, killfeed, compass…) — they are NOT screens: they
-- own no ScreenGui, they parent straight into the shared HUD layer at the
-- anchor slot HUDManifest declares for their id.
--
-- The shape every widget keeps (so a host can drive them all identically):
--
--   local w = HealthBarWidget.new()
--   w:Create(parent?, props?)  -> Root   parent defaults to Layers.Get("HUD")
--   w:Update(data)                       pure function of the data handed in
--   w:ApplyTheme(theme)                  repaints tokens in place
--   w:Destroy()                          drops connections, tweens, instances
--
-- Subclasses override _Build (structure), _Style (paint), Update (data) and,
-- when they own extra state, Destroy (calling HUDWidgetBase.Destroy(self)).
--
-- Two contracts the base enforces so no widget has to remember them:
--   * placement comes from the manifest, in fixed px at the 1650×1020
--     baseline (doc §7.1) — props may override for one-off hosts;
--   * every RenderStepped effect goes through _RenderStep, which gates on
--     UIChrome.IsOnScreen (doc §5.4 animation frugality) and is disconnected
--     in Destroy.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Types = require(script.Parent.Parent.Types)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIStyler = require(script.Parent.Parent.UIStyler)
local Layers = require(script.Parent.Parent.Framework.Layers)
local HUDManifest = require(script.Parent.Parent.Manifests.HUDManifest)
local DefaultTheme = require(script.Parent.Parent.Themes.DefaultTheme)

local HUDWidgetBase = {}
HUDWidgetBase.__index = HUDWidgetBase

-- Doc §7.3 ZIndex ladder: lobby chrome occupies 20–24, below modals (40+) and
-- toasts (60+). Manifest `order` fans the widgets out inside that band.
local HUD_ZINDEX = 20

export type Props = {
	anchor: HUDManifest.Anchor?,
	offset: Vector2?,
	size: Vector2?,
	theme: Types.UITheme?,
	visible: boolean?,
	[string]: any,
}

-- Injected once at boot (same seam as UIComponentBase) so widgets repaint on a
-- live theme swap. Nil-safe: a widget built with no controller still renders,
-- painted from DefaultTheme.
local themeController: any = nil
function HUDWidgetBase.SetThemeController(controller: any)
	themeController = controller
end

-- ---- placement ---------------------------------------------------------

local ANCHORS: { [string]: { point: Vector2, sx: number, sy: number } } = {
	TopLeft = { point = Vector2.new(0, 0), sx = 0, sy = 0 },
	TopCenter = { point = Vector2.new(0.5, 0), sx = 0.5, sy = 0 },
	TopRight = { point = Vector2.new(1, 0), sx = 1, sy = 0 },
	BottomLeft = { point = Vector2.new(0, 1), sx = 0, sy = 1 },
	BottomCenter = { point = Vector2.new(0.5, 1), sx = 0.5, sy = 1 },
	BottomRight = { point = Vector2.new(1, 1), sx = 1, sy = 1 },
	LeftEdge = { point = Vector2.new(0, 0.5), sx = 0, sy = 0.5 },
	RightEdge = { point = Vector2.new(1, 0.5), sx = 1, sy = 0.5 },
}

-- Scale anchors glue the widget to a TRUE screen edge/centre; only the offset
-- space shrinks and grows with the baseline UIScale (doc §7.1).
function HUDWidgetBase.Place(gui: GuiObject, anchor: string, offset: Vector2, size: Vector2)
	if size.X <= 0 and size.Y <= 0 then
		-- The manifest's documented "fill the layer" size: full-bleed overlays
		-- must cover the whole viewport at any aspect ratio, so they can't be
		-- authored as a fixed 1650×1020 box (that would letterbox on ultrawide).
		gui.AnchorPoint = Vector2.new(0, 0)
		gui.Position = UDim2.fromScale(0, 0)
		gui.Size = UDim2.fromScale(1, 1)
		return
	end
	local slot = ANCHORS[anchor] or ANCHORS.TopLeft
	gui.AnchorPoint = slot.point
	gui.Position = UDim2.new(slot.sx, offset.X, slot.sy, offset.Y)
	gui.Size = UDim2.fromOffset(size.X, size.Y)
end

-- ---- lifecycle ---------------------------------------------------------

function HUDWidgetBase.new(id: string, className: string?)
	local self = setmetatable({}, HUDWidgetBase)
	self.Id = id
	self.Props = {} :: Props
	-- Demo-safe default: a widget created with no ThemeController still paints
	-- real tokens instead of white boxes. Create/ApplyTheme overwrite this the
	-- moment a controller (or a props.theme) exists.
	self.Theme = DefaultTheme :: Types.UITheme
	self.Entry = nil :: HUDManifest.Entry?
	self._connections = {} :: { RBXScriptConnection }
	self._tweens = {} :: { Tween }
	self._themeRegistration = nil :: any
	-- Shadow budget sink (engine guidance: <=100 live UIShadows). A UIShadow
	-- destroyed with its host does NOT decrement the counter — only a released
	-- handle does — and HUD widgets are the most persistent surfaces in the
	-- game, so the base owns the release. Empty and free on packs that cast none.
	self._shadows = {} :: { any }

	local root = UIStyler.Frame(className or id)
	root.BackgroundTransparency = 1
	self.Root = root
	return self
end

function HUDWidgetBase:Create(parent: Instance?, props: Props?): GuiObject
	self.Props = props or {}
	local p = self.Props
	if p.theme then
		self.Theme = p.theme
	end

	local entry = HUDManifest.Get(self.Id)
	self.Entry = entry
	HUDWidgetBase.Place(
		self.Root,
		p.anchor or (entry and entry.anchor) or "TopLeft",
		p.offset or (entry and entry.offset) or Vector2.new(0, 0),
		p.size or (entry and entry.size) or Vector2.new(220, 48)
	)
	self.Root.ZIndex = HUD_ZINDEX + ((entry and entry.order) or 0)

	self:_Build(p)
	-- No parent given = mount into the shared HUD layer, which is the whole
	-- point of a widget: z-order is a property of the system, not the widget.
	self.Root.Parent = parent or Layers.Get("HUD")

	if themeController then
		self._themeRegistration = themeController:RegisterComponent(self)
		self:ApplyTheme(themeController:GetTheme())
	else
		self:ApplyTheme(self.Theme)
	end
	if p.visible ~= nil then
		self.Root.Visible = p.visible
	end
	return self.Root
end

-- Override: build GuiObjects into self.Root.
function HUDWidgetBase:_Build(_props: Props) end

-- Override: paint theme tokens onto the instances _Build made.
function HUDWidgetBase:_Style(_theme: Types.UITheme) end

function HUDWidgetBase:ApplyTheme(theme: Types.UITheme?)
	if not theme then
		return
	end
	self.Theme = theme
	self:_Style(theme)
end

-- Override: widgets are pure functions of the data handed in here.
function HUDWidgetBase:Update(_data: any) end

function HUDWidgetBase:SetVisible(visible: boolean)
	self.Root.Visible = visible
end

function HUDWidgetBase:IsVisible(): boolean
	return self.Root.Visible
end

-- ---- helpers -----------------------------------------------------------

function HUDWidgetBase:_Connect(event: RBXScriptSignal, handler: (...any) -> ())
	table.insert(self._connections, event:Connect(handler))
end

function HUDWidgetBase:_Tween(instance: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local tween = UIStyler.Tween(instance, info, goal)
	table.insert(self._tweens, tween)
	return tween
end

-- THE only sanctioned way a widget runs per-frame work (doc §5.4): gated on
-- the widget being parented, visible and actually on screen, tracked so
-- Destroy disconnects it. `fn(dt, clock)`.
function HUDWidgetBase:_RenderStep(fn: (number, number) -> ()): RBXScriptConnection
	local connection = RunService.RenderStepped:Connect(function(dt: number)
		local root = self.Root
		if not root or not root.Parent then
			return
		end
		if not UIChrome.IsOnScreen(root) then
			return
		end
		fn(dt, os.clock())
	end)
	table.insert(self._connections, connection)
	return connection
end

function HUDWidgetBase:_PopIn(gui: GuiObject?)
	UIChrome.PopIn(self.Theme, gui or self.Root)
end

function HUDWidgetBase:_Pulse(gui: GuiObject?)
	UIChrome.Pulse(self.Theme, gui or self.Root)
end

-- "Local player first" (doc §11.4): widgets that highlight you (killfeed rows,
-- damage numbers) resolve the name once, with a demo fallback so a standalone
-- widget still renders a believable row.
function HUDWidgetBase.LocalName(): string
	local player = Players.LocalPlayer
	return (player and player.Name) or "You"
end

-- 1,240 — the thousands separator every HUD number uses.
function HUDWidgetBase.Commas(value: number): string
	local text = tostring(math.floor(value))
	local sign = ""
	if string.sub(text, 1, 1) == "-" then
		sign, text = "-", string.sub(text, 2)
	end
	local out = text
	while true do
		local replaced: number
		out, replaced = string.gsub(out, "^(%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then
			break
		end
	end
	return sign .. out
end

function HUDWidgetBase:Destroy()
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
	for _, handle in self._shadows do
		handle:Release()
	end
	table.clear(self._shadows)
	if self.Root then
		self.Root:Destroy()
	end
end

return HUDWidgetBase
