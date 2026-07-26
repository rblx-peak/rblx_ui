--!strict
-- Base class for screens. Each screen owns exactly one ScreenGui built via
-- script; the base handles construction, the show/hide fade, controller
-- injection and teardown. Subclasses override _BuildContent (populate the root)
-- and optionally _OnShow/_OnHide/Update.
--
-- Screens receive the theme + screen controllers via SetControllers, so they
-- can read the active theme/pack and (for interactive screens) drive
-- navigation without global singletons.

local Players = game:GetService("Players")

local Types = require(script.Parent.Parent.Types)
local UIStyler = require(script.Parent.Parent.UIStyler)
local UIScaleHelper = require(script.Parent.Parent.UIScaleHelper)
local UIStyleEnforcer = require(script.Parent.Parent.UIStyleEnforcer)
local TextConfig = require(script.Parent.Parent.Config.TextConfig)

local UIScreenBase = {}
UIScreenBase.__index = UIScreenBase

-- Optional sound controller injected at boot; screens play Success/Error etc.
local soundController: any = nil
function UIScreenBase.SetSoundController(controller: any)
	soundController = controller
end

function UIScreenBase:_PlaySound(event: string)
	if soundController then
		soundController:Play(event)
	end
end

-- The empty ScreenGui + Root shell every screen builds into. Factored out of
-- .new so a STYLE rebuild (see _ResetShell) can recreate it identically.
local function buildShell(name: string, displayOrder: number): (ScreenGui, Frame)
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = displayOrder
	gui.Enabled = false

	-- Full-screen transparent root every screen parents content into.
	local root = UIStyler.Frame("Root")
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui

	return gui, root
end

function UIScreenBase.new(name: string, displayOrder: number?)
	local self = setmetatable({}, UIScreenBase)
	self.Name = name
	self.ThemeController = nil :: any
	self.ScreenController = nil :: any
	-- Which style family the enforcer applies (doc §1): "Arcade" for
	-- menus/HUD (the default), "Studio" for workbench screens. Subclasses
	-- set this in their constructor, before the first Show builds the Gui.
	self.Family = "Arcade" :: Types.UIFamily
	self._built = false
	self._visible = false
	-- STYLE staleness: a hidden screen built under a previous style rebuilds
	-- on its next Show; a visible one rebuilds immediately (deferred a frame).
	self._styleStale = false
	self._rebuildQueued = false
	self._lastShowData = nil :: any
	-- Raw (non-component) labels this screen wants kept in sync with the theme.
	self._themedLabels = {} :: { { label: TextLabel, colorToken: string, fontToken: string } }

	local gui, root = buildShell(name, displayOrder or 1)
	self.Gui = gui
	self.Root = root

	return self
end

-- A screen with a main UIPanelComponent registers it here so the base can drive
-- a consistent intro on show and a REVERSE outro on hide (the panel leaves the
-- way it came), instead of the old instant fade-out. The panel's animation pack
-- (grow/slide/…) is chosen globally in PanelAnimConfig.
function UIScreenBase:_SetAnimatedPanel(panel: any)
	self._animatedPanel = panel
end

function UIScreenBase:SetControllers(themeController: any, screenController: any)
	self.ThemeController = themeController
	self.ScreenController = screenController
	-- A theme change is a STYLE change (fonts, chrome, corners — not just
	-- colours), and raw builds don't repaint. Built screens therefore REBUILD:
	-- visible ones now (deferred a frame so the click that triggered the
	-- change finishes cleanly), hidden ones lazily on their next Show.
	themeController.ThemeChanged:Connect(function()
		self:_RepaintLabels()
		if not self._built then
			return
		end
		if self._visible then
			if self._rebuildQueued then
				return
			end
			self._rebuildQueued = true
			task.defer(function()
				self._rebuildQueued = false
				if self._built and self._visible then
					self:_OnHide()
					self:_ResetShell()
					self:Show(self._lastShowData)
				end
			end)
		else
			self._styleStale = true
		end
	end)
end

-- Resolve a text key (or pass-through literal).
function UIScreenBase:_R(keyOrText: string?): string
	return TextConfig.Resolve(keyOrText)
end

-- Create a raw TextLabel wired to theme tokens and registered for repaint on
-- live theme changes. Use for section headers and other non-component text.
function UIScreenBase:_ScreenLabel(parent: Instance, text: string, colorToken: string, fontToken: string, layoutOrder: number?): TextLabel
	local label = UIStyler.TextLabel("Label")
	label.Size = UDim2.new(1, 0, 0, 26)
	label.Text = text
	label.TextXAlignment = Enum.TextXAlignment.Left
	if layoutOrder then
		label.LayoutOrder = layoutOrder
	end
	label.Parent = parent
	table.insert(self._themedLabels, { label = label, colorToken = colorToken, fontToken = fontToken })
	self:_PaintLabel(label, colorToken, fontToken)
	return label
end

function UIScreenBase:_PaintLabel(label: TextLabel, colorToken: string, fontToken: string)
	local theme = self:GetTheme()
	label.TextColor3 = (theme.Colors :: any)[colorToken] or theme.Colors.TextPrimary
	label.FontFace = (theme.Fonts :: any)[fontToken] or theme.Fonts.Body
	label.TextSize = (theme.TextSizes :: any)[fontToken] or theme.TextSizes.Body
	-- Match component text: apply the theme's optional outline to raw section
	-- labels too (theme-gated; disabled cleanly for themes without one).
	UIStyler.ApplyThemeOutline(label, theme.TextOutline)
end

function UIScreenBase:_RepaintLabels()
	-- Drop destroyed labels lazily while repainting the live ones.
	for i = #self._themedLabels, 1, -1 do
		local entry = self._themedLabels[i]
		if entry.label.Parent then
			self:_PaintLabel(entry.label, entry.colorToken, entry.fontToken)
		else
			table.remove(self._themedLabels, i)
		end
	end
end

function UIScreenBase:_EnsureBuilt()
	if self._built then
		return
	end
	self._built = true
	-- Parent to the local player's PlayerGui lazily (first show), so screens
	-- can be constructed before the GUI hierarchy is needed.
	local playerGui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		self.Gui.Parent = playerGui
	end
	-- The 1650×1020 baseline UIScale (doc §7.1) — px-authored layout shrinks/
	-- grows with the viewport while Scale-anchored positions stay glued to
	-- true screen edges. Attached before build so first-frame layout is right.
	UIScaleHelper.Attach(self.Root)
	-- The style enforcer (doc §4.1.3) backstops everything this screen ever
	-- builds: black text outlines, black strokes + arcade bevel on buttons.
	UIStyleEnforcer.Attach(self.Gui, self.Family)
	self:_BuildContent()
end

-- Override: build content into self.Root using components.
function UIScreenBase:_BuildContent() end

-- Override: react to show/hide (start timers, refresh data).
function UIScreenBase:_OnShow(_data: any?) end
function UIScreenBase:_OnHide() end

-- Override: release state that outlives the Gui (pooled row tables, component
-- refs, ticker handles) before a style rebuild destroys the shell. The Gui
-- and its descendants are destroyed FOR you right after this hook runs.
function UIScreenBase:_OnTeardown() end

-- Throw the built tree away and stand up a fresh empty shell; the next
-- Show/_EnsureBuilt rebuilds content under the CURRENT style. This is how a
-- live style switch re-skins raw (non-component) builds: honestly, from zero.
function UIScreenBase:_ResetShell()
	self._styleStale = false
	self:_OnTeardown()
	local displayOrder = self.Gui.DisplayOrder
	self.Gui:Destroy()
	local gui, root = buildShell(self.Name, displayOrder)
	self.Gui = gui
	self.Root = root
	self._built = false
	self._visible = false
	self._animatedPanel = nil
	self._themedLabels = {}
end

function UIScreenBase:GetTheme(): Types.UITheme
	return self.ThemeController:GetTheme()
end

-- The active LAYOUT language ("Arcade" default, "AC" terminal pages). Screens
-- branch _BuildContent on this; the branch re-evaluates because screens
-- rebuild on every style change.
function UIScreenBase:LayoutKit(): string
	local theme = self:GetTheme()
	return theme.LayoutKit or "Arcade"
end

-- Doc §7.4 / §5: open is an INSTANT Visible flip — the pop/juice lives on
-- the contents (the registered panel plays POP_IN on its content), never on
-- a container fade.
function UIScreenBase:Show(data: any?)
	-- Built under a previous style while hidden? Rebuild before showing.
	if self._built and self._styleStale then
		self:_ResetShell()
	end
	self._lastShowData = data
	self:_EnsureBuilt()
	self._visible = true
	self.Gui.Enabled = true
	self:_OnShow(data)
	if self._animatedPanel then
		self._animatedPanel:AnimateIn()
	end
end

-- Things pop in and HARD-HIDE out (doc §5): close is an instant flip. A
-- panel whose AnimateOut still returns a Tween (legacy packs) is honoured —
-- the Gui disables when that outro finishes.
function UIScreenBase:Hide()
	if not self._visible then
		return
	end
	self._visible = false
	self:_OnHide()
	if self._animatedPanel then
		local out = self._animatedPanel:AnimateOut()
		if out then
			out.Completed:Once(function()
				if not self._visible then
					self.Gui.Enabled = false
				end
			end)
			return
		end
	end
	self.Gui.Enabled = false
end

function UIScreenBase:Update(_data: any) end

function UIScreenBase:IsVisible(): boolean
	return self._visible
end

function UIScreenBase:Destroy()
	if self.Gui then
		self.Gui:Destroy()
	end
end

return UIScreenBase
