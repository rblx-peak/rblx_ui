--!strict
-- Owns the floating nav rail: the on-screen shortcut buttons (open shop, theme
-- editor, help, …) that behave like a regular game's "open shop" GUI buttons.
-- Rewritten as its own controller (was inline in ClientHandler) so the rail's
-- geometry math lives in one place and can be reasoned about/tested on its own.
--
-- Content (icons/labels/actions) comes from NavConfig; PLACEMENT (which side,
-- top/center/bottom, column vs toolbar, labelled or not) comes from whichever
-- is active: a UILayoutController preset, else the active pack's own Nav block.
--
-- Sizing is computed EXPLICITLY from the button list up front (not left to
-- AutomaticSize) so the rail's height is known before it's ever positioned —
-- that's what makes "Center" a true, deterministic vertical center instead of
-- an approximation that depends on layout resolving before the next read.
--
-- Vertical placement is computed in ABSOLUTE PIXELS from the camera's real
-- viewport size, not a Position scale-fraction. Confirmed via measurement that
-- even with ScreenGui.IgnoreGuiInset = true, EVERY Position (scale OR pixel
-- offset) still renders shifted up by exactly GuiService:GetGuiInset().Y (the
-- top bar) — a real, reproducible engine quirk in this environment, not a
-- one-off. Rather than fight it, we read the live inset and add it back in, so
-- the rail lands exactly where computed regardless of platform/inset size.
-- Re-centers automatically on viewport resize (window resize on PC, orientation
-- change on mobile) via a Changed listener.

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")

local NavConfig = require(script.Parent.Parent.Config.NavConfig)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIButtonComponent = require(script.Parent.Parent.Components.UIButtonComponent)

local UINavRailController = {}
UINavRailController.__index = UINavRailController

-- Fixed pixel clearance from the top/bottom screen edge (used for the Top/
-- Bottom vertical anchors) — a plain px margin is predictable across any
-- viewport size, unlike a scale fraction that shifts with aspect ratio.
local EDGE_MARGIN_Y = 70

function UINavRailController.new(themeController: any, screenController: any, layoutController: any, devConfig: any)
	local self = setmetatable({}, UINavRailController)
	self._themeController = themeController
	self._screenController = screenController
	self._layoutController = layoutController
	self._devConfig = devConfig
	self._player = Players.LocalPlayer
	self._gui = nil :: ScreenGui?
	self._actionHandler = nil :: ((string) -> ())?
	self._buttons = {} :: { any }
	-- The rail is PERSISTENT (it never goes through the screen-rebuild path).
	-- Its buttons do re-style themselves through the component registry, but
	-- that pass runs BEFORE the ClientHandler handler that refreshes
	-- UIChrome's active style — so chrome policy (outline vs glow, bevel,
	-- corners, strokes) would land one style behind. When a swap crosses a
	-- styled-chrome boundary, defer one extra ApplyTheme (after the policy
	-- refresh — the same deferred pattern as UIScreenBase) over the live
	-- buttons. Classic-to-Classic swaps skip it: the registry pass alone is
	-- already correct there, so Classic behaviour is untouched.
	if themeController and themeController.ThemeChanged then
		local current = themeController.GetTheme and themeController:GetTheme()
		self._lastChrome = current and current.Chrome or nil
		themeController.ThemeChanged:Connect(function(theme)
			local prevChrome = self._lastChrome
			self._lastChrome = theme.Chrome
			if prevChrome == nil and theme.Chrome == nil then
				return
			end
			task.defer(function()
				-- Fresh policy by now (ClientHandler's handler ran).
				local outlined = UIChrome.ActiveChrome().TextOutline
				for _, button in self._buttons do
					button:ApplyTheme(theme)
					-- A swap BACK to an outline style must also drop the
					-- styled-era text-glow strokes: UIChrome.TextOutline
					-- leaves them in place and these buttons never rebuild.
					if outlined then
						for _, d in button.Root:GetDescendants() do
							if d:IsA("UIStroke") and d.Name == "TextGlow" then
								d:Destroy()
							end
						end
					end
				end
			end)
		end)
	end
	return self
end

-- ClientHandler wires this so button clicks route back through its navAction map.
function UINavRailController:SetActionHandler(fn: (action: string) -> ())
	self._actionHandler = fn
end

-- The buttons that should actually render (authorization-filtered).
function UINavRailController:_VisibleButtons(): { NavConfig.NavButton }
	local out = {}
	for _, def in NavConfig.Buttons do
		if not (def.authorizedOnly and not self._devConfig.IsAuthorized(self._player.UserId)) then
			table.insert(out, def)
		end
	end
	return out
end

-- Resolve the geometry to build with right now: the active layout preset if
-- one is set, else the active pack's own Nav block (via the layout controller,
-- which already knows how to fall back — see UILayoutController:GetNavGeometry).
function UINavRailController:_Geometry()
	local packNav = self._themeController:GetPack().Nav
	return self._layoutController:GetNavGeometry(packNav)
end

function UINavRailController:Build()
	if not self._devConfig.ShowNavRail then
		return
	end
	-- Fresh component list per build (Rebuild destroys the old gui, which
	-- self-destroys/unregisters the old components via Root.Destroying).
	self._buttons = {}
	local playerGui = self._player:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "NavRail"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- REQUIRED — this was the actual root cause of every "invisible icon" symptom.
	-- ScreenGui's true engine default is ZIndexBehavior.Global (confirmed by
	-- direct measurement — NOT Sibling, despite that being commonly assumed).
	-- Under Global, a descendant needs a HIGHER ZIndex than every ancestor to
	-- paint above it; Icon (ZIndex 1, nested inside Surface at ZIndex 2) was
	-- losing to its own ancestor and rendering fully behind it — invisible, no
	-- matter the text/font/size, confirmed by exhaustively ruling out every
	-- other candidate (font, weight, TextScaled, asset loading, capture tool).
	-- UIScreenBase already sets Sibling for every OTHER screen; this ScreenGui
	-- is built outside that base class, so it never inherited that fix.
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 8
	gui.Parent = playerGui
	self._gui = gui

	local geo = self:_Geometry()
	local buttons = self:_VisibleButtons()
	local horizontal = geo.fill == "Horizontal"
	local onRight = geo.side == "Right"

	-- Every button's size is a SCALE fraction of the viewport (converted from
	-- its design-space pixel size via NavConfig.ScaleX/ScaleY) — never a raw
	-- Offset — so the whole rail shrinks/grows with the real screen size
	-- exactly like the reference MainGui's UI does, with no UIScale needed.
	local sizes = {}
	local totalMainFrac, maxCrossFrac = 0, 0
	for i, def in buttons do
		local sizePx = NavConfig.SizeFor(def, geo.showLabels)
		local sizeFrac = Vector2.new(NavConfig.ScaleX(sizePx.X), NavConfig.ScaleY(sizePx.Y))
		sizes[i] = sizeFrac
		local main = horizontal and sizeFrac.X or sizeFrac.Y
		local cross = horizontal and sizeFrac.Y or sizeFrac.X
		totalMainFrac += main
		maxCrossFrac = math.max(maxCrossFrac, cross)
	end
	local spacingFrac = horizontal and NavConfig.ScaleX(NavConfig.Spacing) or NavConfig.ScaleY(NavConfig.Spacing)
	if #buttons > 1 then
		totalMainFrac += spacingFrac * (#buttons - 1)
	end
	local crossPadFrac = horizontal and NavConfig.ScaleY(16) or NavConfig.ScaleX(16)
	local railWFrac = horizontal and totalMainFrac or (maxCrossFrac + crossPadFrac)
	local railHFrac = horizontal and (maxCrossFrac + crossPadFrac) or totalMainFrac

	-- Vertical anchor, computed as a SCALE fraction of the real viewport height,
	-- then compensated for the GuiInset quirk (see module-level note) — the
	-- inset itself is genuinely a fixed pixel amount (a real screen element,
	-- not a design-space size), so it stays an Offset added on top of the
	-- Scale position. Top/Bottom hug the edge with a scaled margin; Center is
	-- a true fractional centre — AnchorPoint.Y = 0.5 at that exact fraction.
	local insetY = GuiService:GetGuiInset().Y
	local edgeMarginFrac = NavConfig.ScaleY(EDGE_MARGIN_Y)
	local anchorY, fracY
	if geo.vertical == "Top" then
		anchorY, fracY = 0, edgeMarginFrac
	elseif geo.vertical == "Bottom" then
		anchorY, fracY = 1, 1 - edgeMarginFrac
	else
		anchorY, fracY = 0.5, 0.5
	end
	local edgeFrac = NavConfig.ScaleX(NavConfig.EdgeOffset)

	local rail = UIStyler.Frame("Rail")
	rail.BackgroundTransparency = 1
	rail.AnchorPoint = Vector2.new(onRight and 1 or 0, anchorY)
	if onRight then
		rail.Position = UDim2.new(1, 0, fracY, insetY) - UDim2.fromScale(edgeFrac, 0)
	else
		rail.Position = UDim2.new(0, 0, fracY, insetY) + UDim2.fromScale(edgeFrac, 0)
	end
	rail.Size = UDim2.fromScale(railWFrac, railHFrac)
	-- Same viewport-fraction -> rail-fraction conversion as the buttons below:
	-- Padding resolves against rail's own size, so spacingFrac (a fraction OF
	-- THE VIEWPORT) must be divided by the rail's own main-axis fraction first.
	local railMainFrac = horizontal and railWFrac or railHFrac
	local spacingFracOfRail = railMainFrac > 0 and (spacingFrac / railMainFrac) or 0
	UIStyler.ListLayout({
		FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
		Padding = UDim.new(spacingFracOfRail, 0),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}).Parent = rail
	rail.Parent = gui

	-- Buttons are parented INSIDE `rail`, so a Scale fraction on them resolves
	-- against rail's OWN AbsoluteSize, not the viewport — but sizeFrac above was
	-- computed as a fraction OF THE VIEWPORT. Re-expressing it as a fraction of
	-- rail (divide by rail's own viewport fraction) cancels that out to the
	-- correct final size, the same fix pattern as the earlier UIScale
	-- double-scaling bug, just via nested Scale instead of nested UIScale.
	for i, def in buttons do
		local sizeFrac = sizes[i]
		local showLabel = geo.showLabels and def.label ~= nil and def.label ~= ""
		local button = UIButtonComponent.new()
		button:Create(rail, {
			icon = def.icon,
			iconId = def.iconId,
			text = showLabel and def.label or nil,
			variant = def.variant or "Primary",
			size = UDim2.fromScale(sizeFrac.X / railWFrac, sizeFrac.Y / railHFrac),
			layoutOrder = i,
			onClick = function()
				if self._actionHandler then
					self._actionHandler(def.action)
				end
			end,
		})
		table.insert(self._buttons, button)
		-- ScaleX/ScaleY convert the SAME design-space pixel size against
		-- DIFFERENT denominators (viewport width vs height) — sizeFrac.X and
		-- sizeFrac.Y only produce a true square (or the intended rectangle)
		-- when the real viewport's aspect ratio happens to exactly match
		-- NavConfig's 1280x720 design reference. Any other aspect ratio
		-- stretches the button — confirmed the cause of nav buttons not
		-- holding their shape. A fixed AspectRatioConstraint (design px
		-- width:height) locks the button to its authored shape regardless of
		-- viewport, the same fix already applied to shop cards/screens.
		-- DominantAxis matches whichever axis the rail's own total-size budget
		-- was already computed from (the "main" axis for this fill direction)
		-- — that axis must stay authoritative, so only the free CROSS axis
		-- gets adjusted to hold the ratio, never overflowing the rail itself.
		local sizePx = NavConfig.SizeFor(def, geo.showLabels)
		if sizePx.Y > 0 then
			local dominant = horizontal and Enum.DominantAxis.Width or Enum.DominantAxis.Height
			UIStyler.AspectRatio(sizePx.X / sizePx.Y, dominant).Parent = button.Root
		end
		self._screenController:RegisterHighlightTarget(def.id, button.Root)
	end
end

-- Tear down and rebuild — used after a pack swap or a layout-preset change,
-- since either can change the rail's side/vertical/labelled geometry.
function UINavRailController:Rebuild()
	if self._gui then
		self._gui:Destroy()
		self._gui = nil
	end
	self:Build()
end

-- Keep the rail correctly placed across a window resize (PC) or orientation
-- change (mobile/tablet) — the pixel math in Build() is only right for the
-- viewport size at the moment it ran, so a real size change needs a rebuild.
function UINavRailController:WatchViewportResize()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		self:Rebuild()
	end)
end

return UINavRailController
