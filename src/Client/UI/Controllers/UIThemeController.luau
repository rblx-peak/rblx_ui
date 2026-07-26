--!strict
-- Central theme + pack registry and live switcher. Every component registers
-- here on creation; SetTheme re-applies the new theme to all of them at once,
-- which is what makes a theme swap (and the editor's live preview) ripple
-- across the entire UI with no per-screen code.
--
-- It also owns runtime-only themes: the Theme Editor previews an edited or
-- imported theme by calling UpsertRuntimeTheme (no module file needed) and then
-- SetTheme. Exporting that runtime theme to a .luau file is the ThemeSerializer
-- path; this controller just holds the live table.
--
-- Registration returns a connection object with :Disconnect(), so components
-- clean up uniformly in their Destroy.

local Types = require(script.Parent.Parent.Types)
local UISignal = require(script.Parent.Parent.UISignal)
local UIChrome = require(script.Parent.Parent.UIChrome)
local UIThemeConfig = require(script.Parent.Parent.Config.UIThemeConfig)
local UIPackConfig = require(script.Parent.Parent.Config.UIPackConfig)

local UIThemeController = {}
UIThemeController.__index = UIThemeController

export type ThemeController = typeof(setmetatable(
	{} :: {
		_themes: { [string]: Types.UITheme },
		_themeOrder: { string },
		_packs: { [string]: Types.UIPack },
		_packOrder: { string },
		_components: { any },
		_currentTheme: Types.UITheme,
		_currentPack: Types.UIPack,
		ThemeChanged: typeof(UISignal.new()),
		PackChanged: typeof(UISignal.new()),
		ThemeListChanged: typeof(UISignal.new()),
	},
	UIThemeController
))

function UIThemeController.new(): ThemeController
	local self = setmetatable({}, UIThemeController)
	self._themes = {}
	self._themeOrder = {}
	self._packs = {}
	self._packOrder = {}
	self._components = {}
	self.ThemeChanged = UISignal.new()
	self.PackChanged = UISignal.new()
	self.ThemeListChanged = UISignal.new()

	for _, theme in UIThemeConfig.Themes do
		self:_AddTheme(theme)
	end
	for _, pack in UIPackConfig.Packs do
		self._packs[pack.Id] = pack
		table.insert(self._packOrder, pack.Id)
	end

	self._currentTheme = self._themes[UIThemeConfig.DefaultThemeId] or UIThemeConfig.Themes[1]
	self._currentPack = self._packs[UIPackConfig.DefaultPackId] or UIPackConfig.Packs[1]
	return self :: any
end

function UIThemeController:_AddTheme(theme: Types.UITheme)
	if not self._themes[theme.Id] then
		table.insert(self._themeOrder, theme.Id)
	end
	self._themes[theme.Id] = theme
end

-- ---- component registration -------------------------------------------

-- Components call this in Create. Returns a { Disconnect } handle.
function UIThemeController:RegisterComponent(component: any)
	table.insert(self._components, component)
	local components = self._components
	return {
		Disconnect = function()
			local index = table.find(components, component)
			if index then
				table.remove(components, index)
			end
		end,
	}
end

-- ---- theme switching --------------------------------------------------

function UIThemeController:GetTheme(): Types.UITheme
	return self._currentTheme
end

function UIThemeController:GetPack(): Types.UIPack
	return self._currentPack
end

function UIThemeController:GetThemeList(): { Types.UITheme }
	local list = {}
	for _, id in self._themeOrder do
		table.insert(list, self._themes[id])
	end
	return list
end

function UIThemeController:GetPackList(): { Types.UIPack }
	local list = {}
	for _, id in self._packOrder do
		table.insert(list, self._packs[id])
	end
	return list
end

-- Apply a registered theme by id. Every live component's ApplyTheme runs,
-- and because component _Style methods tween color properties with the
-- theme's ThemeSwap TweenInfo, the change cross-fades instead of snapping.
function UIThemeController:SetTheme(themeId: string)
	local theme = self._themes[themeId]
	if not theme or theme == self._currentTheme then
		return
	end
	self:ApplyThemeObject(theme)
end

-- Apply a theme table directly (used for live-edited/imported themes that may
-- not be registered under a stable id).
function UIThemeController:ApplyThemeObject(theme: Types.UITheme)
	self._currentTheme = theme
	-- The chrome policy must flip BEFORE any component restyles or any
	-- ThemeChanged listener runs — component _Style paths consult
	-- UIChrome.ActiveChrome() (outline vs glow, bevel, hairline weight), so
	-- restyling first would paint the OUTGOING style's chrome. ClientHandler's
	-- listener also calls this; a second call is a cheap no-op.
	UIChrome.SetActiveTheme(theme)
	for _, component in table.clone(self._components) do
		task.spawn(function()
			component:ApplyTheme(theme)
		end)
	end
	self.ThemeChanged:Fire(theme)
end

function UIThemeController:SetPack(packId: string)
	local pack = self._packs[packId]
	if not pack or pack == self._currentPack then
		return
	end
	self._currentPack = pack
	self.PackChanged:Fire(pack)
end

-- ---- runtime themes (editor / import) ---------------------------------

-- Register or replace a runtime theme (e.g. "Custom") so it shows in the
-- selector and can be re-selected by id. Fires ThemeListChanged for the UI.
function UIThemeController:UpsertRuntimeTheme(theme: Types.UITheme)
	self:_AddTheme(theme)
	self.ThemeListChanged:Fire(self:GetThemeList())
end

return UIThemeController
