--!strict
-- Owns the screen registry and the single modal slot; decides what's visible
-- and animates transitions. Screens register themselves (id -> screen module
-- instance); the controller calls their Show/Hide/Update. It never builds Gui
-- itself — that's the screens' job — it just orchestrates them.
--
-- Also holds the highlight-target registry the tutorial uses: any screen can
-- publish "here is the GuiObject for nav.shop", and the tutorial asks for it by
-- id to point its spotlight, keeping tutorial data decoupled from layout.

local UISignal = require(script.Parent.Parent.UISignal)
local ScreenManifest = require(script.Parent.Parent.Manifests.ScreenManifest)

local UIScreenController = {}
UIScreenController.__index = UIScreenController

-- Panel screens that own the centre of the screen: only ONE may be open at a
-- time, so opening any of these first closes whichever other one is up. This is
-- the "open a new menu -> the previous one closes" consistency. The modal slot,
-- HUD, chat bar and toasts are NOT in this set (they layer independently).
-- The set comes from the manifest so adding a screen to the catalog enrols it
-- automatically — there is no second list to keep in sync.
local EXCLUSIVE_PANELS = ScreenManifest.ExclusiveSet()

function UIScreenController.new(themeController: any)
	local self = setmetatable({}, UIScreenController)
	self._themeController = themeController
	self._screens = {} :: { [string]: any }
	self._visible = {} :: { [string]: boolean }
	self._highlightTargets = {} :: { [string]: GuiObject }
	self._modalScreenId = nil :: string?
	self._registry = nil :: any
	self.ScreenShown = UISignal.new()
	self.ScreenHidden = UISignal.new()
	return self
end

-- Give the controller the on-demand screen library. Once set, ANY id in the
-- manifest resolves on first use — screens no longer have to be constructed
-- and registered at boot to be callable.
function UIScreenController:SetRegistry(registry: any)
	self._registry = registry
end

function UIScreenController:RegisterScreen(id: string, screen: any)
	self._screens[id] = screen
	if screen.SetControllers then
		screen:SetControllers(self._themeController, self)
	end
end

-- Nominate which registered screen acts as the modal host (ModalScreen).
function UIScreenController:SetModalScreen(id: string)
	self._modalScreenId = id
end

-- Fetch a screen, building it from the catalog on first use. Boot-registered
-- screens win; anything else is lazily constructed by the registry.
function UIScreenController:GetScreen(id: string): any
	local screen = self._screens[id]
	if screen then
		return screen
	end
	if self._registry then
		return self._registry:Get(id)
	end
	return nil
end

function UIScreenController:IsVisible(id: string): boolean
	return self._visible[id] == true
end

function UIScreenController:ShowScreen(id: string, data: any?)
	local screen = self:GetScreen(id)
	if not screen then
		warn("[UIScreenController] Unknown screen: " .. id)
		return
	end
	-- E8, the screen-transition slash: packs that declare ScreenWipe get a
	-- diagonal wipe on EXCLUSIVE panel switches, with the actual swap running
	-- in the covered window (the load-hiding trick). Router-level, so every
	-- screen gets it for free; themes without the flag pay nothing, and
	-- non-exclusive surfaces (HUD widgets, toasts) never wipe.
	local theme = self._themeController and self._themeController:GetTheme()
	if EXCLUSIVE_PANELS[id] and theme and (theme :: any).ScreenWipe then
		local SlashTransition = require(script.Parent.Parent.Framework.SlashTransition) :: any
		SlashTransition.Play(theme, {
			during = function()
				self:_ShowScreenNow(id, screen, data)
			end,
		})
		return
	end
	self:_ShowScreenNow(id, screen, data)
end

function UIScreenController:_ShowScreenNow(id: string, screen: any, data: any?)
	-- Single-panel rule: opening one exclusive panel closes any other open one,
	-- so its outro (reverse animation) plays as the new panel animates in.
	if EXCLUSIVE_PANELS[id] then
		for otherId in EXCLUSIVE_PANELS do
			if otherId ~= id and self._visible[otherId] then
				self:HideScreen(otherId)
			end
		end
	end
	self._visible[id] = true
	screen:Show(data)
	self.ScreenShown:Fire(id)
end

function UIScreenController:HideScreen(id: string)
	-- Deliberately NOT GetScreen: hiding must never build a screen that was
	-- never opened.
	local screen = self._screens[id]
	if not screen or not self._visible[id] then
		return
	end
	self._visible[id] = false
	screen:Hide()
	self.ScreenHidden:Fire(id)
end

function UIScreenController:ToggleScreen(id: string, data: any?)
	if self._visible[id] then
		self:HideScreen(id)
	else
		self:ShowScreen(id, data)
	end
end

function UIScreenController:UpdateScreen(id: string, data: any)
	local screen = self._screens[id]
	if screen and screen.Update then
		screen:Update(data)
	end
end

-- ---- modal slot -------------------------------------------------------

function UIScreenController:ShowModal(modalData: any)
	if not self._modalScreenId then
		warn("[UIScreenController] No modal screen registered")
		return
	end
	self:ShowScreen(self._modalScreenId, modalData)
end

function UIScreenController:HideModal()
	if self._modalScreenId then
		self:HideScreen(self._modalScreenId)
	end
end

-- ---- highlight targets (tutorial) -------------------------------------

function UIScreenController:RegisterHighlightTarget(id: string, guiObject: GuiObject)
	self._highlightTargets[id] = guiObject
end

function UIScreenController:GetHighlightTarget(id: string): GuiObject?
	return self._highlightTargets[id]
end

-- Hide whichever non-persistent screen is on top; used by the CloseTop action
-- (Esc / gamepad B / Android back all funnel here). Returns true if something
-- was closed.
function UIScreenController:CloseTopmost(): boolean
	if self._modalScreenId and self._visible[self._modalScreenId] then
		self:HideModal()
		return true
	end
	-- Named panels first, in a deliberate priority order (a dev tool on top of
	-- a shop should close before the shop does).
	for _, id in { "themeSelector", "store", "shop", "index", "settings", "tutorial" } do
		if self._visible[id] then
			self:HideScreen(id)
			return true
		end
	end
	-- Then anything else from the catalog that happens to be open, so every
	-- library screen answers Escape without being added to a list here.
	for id, visible in self._visible do
		if visible and EXCLUSIVE_PANELS[id] then
			self:HideScreen(id)
			return true
		end
	end
	return false
end

-- Every screen currently open (ids only) — used by the HUD-sync pass and by
-- match flow that must hide lobby chrome except exempted overlays.
function UIScreenController:VisibleIds(): { string }
	local ids = {}
	for id, visible in self._visible do
		if visible then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

return UIScreenController
