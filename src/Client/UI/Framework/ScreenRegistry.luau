--!strict
-- The screen library: every window the system knows how to build, declared as
-- data and constructed ON DEMAND. Nothing is required or instantiated until
-- something actually opens it, so a game that never opens the trade window
-- pays nothing for it — but every game can call it.
--
-- This is the "catalog" half of the universal UI system: to ship a new game you
-- enable/disable entries in ScreenManifest, you don't edit screen code.
--
-- Screens keep the existing duck-type (new()/Show/Hide/Update/IsVisible/
-- SetControllers), so registry-built screens and hand-registered ones are
-- indistinguishable to UIScreenController.

local ScreenManifest = require(script.Parent.Parent.Manifests.ScreenManifest)

local ScreenRegistry = {}
ScreenRegistry.__index = ScreenRegistry

export type Entry = ScreenManifest.Entry

function ScreenRegistry.new(themeController: any, screenController: any)
	local self = setmetatable({}, ScreenRegistry)
	self._themeController = themeController
	self._screenController = screenController
	self._instances = {} :: { [string]: any }
	self._failed = {} :: { [string]: string }
	return self
end

-- Where a screen module lives. Screens/ is the flat library folder; a manifest
-- entry may override with an explicit folder for genre packs.
local function resolveModule(entry: Entry): ModuleScript?
	local uiRoot = script.Parent.Parent
	local folder = uiRoot:FindFirstChild(entry.folder or "Screens")
	if not folder then
		return nil
	end
	local module = folder:FindFirstChild(entry.module)
	return (module and module:IsA("ModuleScript")) and module or nil
end

-- Build (or fetch the cached) screen for an id. Returns nil when the manifest
-- has no such id or the module is missing/broken — callers warn and continue,
-- because one missing optional screen must never break the whole UI.
function ScreenRegistry:Get(id: string): any?
	local existing = self._instances[id]
	if existing then
		return existing
	end
	if self._failed[id] then
		return nil
	end

	local entry = ScreenManifest.Get(id)
	if not entry then
		return nil
	end
	if entry.enabled == false then
		return nil
	end

	local module = resolveModule(entry)
	if not module then
		self._failed[id] = "module not found: " .. entry.module
		warn(`[ScreenRegistry] {id}: module '{entry.module}' not found`)
		return nil
	end

	local ok, result = pcall(require, module)
	if not ok or type(result) ~= "table" or type(result.new) ~= "function" then
		self._failed[id] = tostring(result)
		warn(`[ScreenRegistry] {id}: require failed — {result}`)
		return nil
	end

	local built, screen = pcall(function()
		return result.new()
	end)
	if not built or not screen then
		self._failed[id] = tostring(screen)
		warn(`[ScreenRegistry] {id}: new() failed — {screen}`)
		return nil
	end

	-- Carry manifest policy onto the instance so the router and the HUD-sync
	-- pass can read it without re-consulting the manifest.
	screen.Layer = entry.layer or "Screens"
	screen.Exclusive = entry.exclusive ~= false
	screen.HidesHUD = entry.hidesHUD == true
	screen.PausesInput = entry.pausesInput == true

	self._instances[id] = screen
	-- Register with the screen controller so every existing code path
	-- (ShowScreen/HideScreen/CloseTopmost/highlight targets) just works.
	self._screenController:RegisterScreen(id, screen)
	return screen
end

-- Has this id been built yet? (Used by sweeps that must not force-build every
-- screen in the catalog just to ask whether it is open.)
function ScreenRegistry:IsBuilt(id: string): boolean
	return self._instances[id] ~= nil
end

function ScreenRegistry:Built(): { [string]: any }
	return self._instances
end

-- Every id the catalog can produce, whether or not it has been built.
function ScreenRegistry:Catalog(): { string }
	return ScreenManifest.Ids()
end

function ScreenRegistry:Failures(): { [string]: string }
	return self._failed
end

return ScreenRegistry
